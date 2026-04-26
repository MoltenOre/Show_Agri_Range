local flib_position = require("__flib__.position")
local Handler = {}

script.on_init(function()
  storage.playerdata = {}
end)

-- Looks for all agri Towers in the game pressent
local is_agricultural_tower_entity = {}
for _, entity in pairs(prototypes.entity) do
  is_agricultural_tower_entity[entity.name] = entity.type == "agricultural-tower"
end

-- Is this entity an agricultural tower?
function is_agricultural_tower_type(entity)
  return entity.type == "agricultural-tower" or (entity.type == "entity-ghost" and is_agricultural_tower_entity[entity.ghost_name])
end

-- returns the prototype of an entity, even if it's a ghost
function get_proto(entity)
  if entity.type == "entity-ghost" then
    return prototypes.entity[entity.ghost_name]
  else
    return entity.prototype
  end
end

-- Every chunk the player can see!
local function get_chunks_in_viewport(chunk_position)
  local chunk_positions = {}

  local x = chunk_position.x
  local y = chunk_position.y

  -- this gets all the chunks on my 1920 x 1080 screen when i fully zoom out
  local vertical = 2
  local horizontal = 4

  for i = y - vertical, y + vertical do
      for j = x - horizontal, x + horizontal do
          table.insert(chunk_positions, {x = j, y = i})
      end
  end

  return chunk_positions
end

-- Is this item something that will place an agricultural tower?
local is_agricultural_tower_item = {}
for _, item in pairs(prototypes.item) do
  local place_result = item.place_result
  if place_result and is_agricultural_tower_entity[place_result.name] then
    is_agricultural_tower_item[item.name] = true
  else
    is_agricultural_tower_item[item.name] = false
  end
end

-- Is the Player currently holding an agricultural tower?
local function is_player_holding_agricultural_tower(player)
  if player.cursor_ghost then
    return is_agricultural_tower_item[player.cursor_ghost.name.name]
  end

  if player.cursor_stack.valid_for_read then
    if player.cursor_stack.is_blueprint then
      for _, blueprint_entity in ipairs(player.cursor_stack.get_blueprint_entities() or {}) do
        if is_agricultural_tower_entity[blueprint_entity.name] then return true end
      end
    end
    return is_agricultural_tower_item[player.cursor_stack.prototype.name]
  end
end

-- clean up and generation of Rendering scuffolding
-- construct playerdata
-- look for change in held item, if its an agricultural tower add playerdata and start rendering,
-- if its not remove playerdata and destroy all renders
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  assert(player)

  local playerdata = storage.playerdata[player.index]

  if playerdata == nil then
    if is_player_holding_agricultural_tower(player) then
      storage.playerdata[player.index] = {
        player_index = player.index,
        surface_index = player.surface.index,
        seen_chunks = {},
        rendered_towers = {},
        overlap_renders = {},
      }

      Handler.tick_player(event)
    end
  else
    if is_player_holding_agricultural_tower(player) ~= true then
        for _, tower_entry in pairs(playerdata.rendered_towers) do
            tower_entry.destroy()
        end
        for _, overlap_renders in pairs(playerdata.overlap_renders) do
            for _, render in ipairs(overlap_renders) do
                render.destroy()
            end
        end
        storage.playerdata[player.index] = nil
    end
  end

end)

local function get_tower_planting_radius(proto)
  return (proto.agricultural_tower_radius or 2 ) * (proto.growth_grid_tile_size or 3)
end

-- Get the ToplFeft and BottomRight of the Tower rectangle based on
-- the tower prototype, position, and planting radius as well as the selection box
local function get_tower_planting_area(tower)
  local proto = get_proto(tower)
  local pos = tower.position
  local selection_box = proto.selection_box
  local offset_left_top = selection_box.left_top
  local offset_right_bottom = selection_box.right_bottom
  local r = get_tower_planting_radius(proto)

  local left_top = {x = pos.x + offset_left_top.x - r,
                    y = pos.y + offset_left_top.y - r}
  local right_bottom = {x = pos.x + offset_right_bottom.x + r,
                        y = pos.y + offset_right_bottom.y + r}

  return {left_top = left_top, right_bottom = right_bottom}
end

-- Check if two rectangles overlap and return the intersection rectangle if they do
local function get_intersection_area(area_1, area_2)
  local rect1_lt = area_1.left_top
  local rect1_rb = area_1.right_bottom
  local rect2_lt = area_2.left_top
  local rect2_rb = area_2.right_bottom
  -- Check if rectangles overlap
  if rect1_rb.x <= rect2_lt.x or rect2_rb.x <= rect1_lt.x or
     rect1_rb.y <= rect2_lt.y or rect2_rb.y <= rect1_lt.y then
    return nil  -- No overlap
  end

  -- Calculate intersection rectangle
  local intersection_lt = {
    x = math.max(rect1_lt.x, rect2_lt.x),
    y = math.max(rect1_lt.y, rect2_lt.y)
  }
  local intersection_rb = {
    x = math.min(rect1_rb.x, rect2_rb.x),
    y = math.min(rect1_rb.y, rect2_rb.y)
  }
  return {left_top = intersection_lt, right_bottom = intersection_rb}
end

-- create a lookup for all overlaping areas, so they dont get reredndered multiple times when 
-- multiple towers overlap in the same area
local function make_pair_key(a, b)
  if a < b then
    return tostring(a) .. "_" .. tostring(b)
  else
    return tostring(b) .. "_" .. tostring(a)
  end
end

local function has_positive_size(rect)
  return rect.right_bottom.x > rect.left_top.x and rect.right_bottom.y > rect.left_top.y
end

local function subtract_rectangle(target, subtract)
  local result = {}
  local t_lt = target.left_top
  local t_rb = target.right_bottom
  local s_lt = subtract.left_top
  local s_rb = subtract.right_bottom

  -- Left part
  if t_lt.x < s_lt.x then
    local part = {left_top = {x = t_lt.x, y = t_lt.y}, right_bottom = {x = s_lt.x, y = t_rb.y}}
    if has_positive_size(part) then
      table.insert(result, part)
    end
  end

  -- Right part
  if t_rb.x > s_rb.x then
    local part = {left_top = {x = s_rb.x, y = t_lt.y}, right_bottom = {x = t_rb.x, y = t_rb.y}}
    if has_positive_size(part) then
      table.insert(result, part)
    end
  end

  -- Top part
  local left = math.max(t_lt.x, s_lt.x)
  local right = math.min(t_rb.x, s_rb.x)
  if left < right and t_lt.y < s_lt.y then
    local part = {left_top = {x = left, y = t_lt.y}, right_bottom = {x = right, y = s_lt.y}}
    if has_positive_size(part) then
      table.insert(result, part)
    end
  end

  -- Bottom part
  if left < right and t_rb.y > s_rb.y then
    local part = {left_top = {x = left, y = s_rb.y}, right_bottom = {x = right, y = t_rb.y}}
    if has_positive_size(part) then
      table.insert(result, part)
    end
  end

  return result
end

local function subtract_rectangles(target, subtract_list)
  local current = {target}
  for _, sub in ipairs(subtract_list) do
    local new_current = {}
    for _, rect in ipairs(current) do
      local parts = subtract_rectangle(rect, sub)
      for _, part in ipairs(parts) do
        table.insert(new_current, part)
      end
    end
    current = new_current
  end
  return current
end

-- render each tower overlay
local function render_tower(tower, surface, playerdata)
  if playerdata.rendered_towers[tower.unit_number] then
    return
  end

  local area = get_tower_planting_area(tower)
  local id = rendering.draw_rectangle{
    left_top = area.left_top,
    right_bottom = area.right_bottom,
    surface = surface,
    players = {playerdata.player_index},
    color = {0.3, 1, 0.3, 0.15},
    filled = false
  }

  playerdata.rendered_towers[tower.unit_number] = id

  if not settings.get_player_settings(game.get_player(playerdata.player_index))["show-agri-range-overlap-indication"].value then
    return
  end

  -- only check overlaps for the newly added tower against already visible towers
  for other_unit, other_entry in pairs(playerdata.rendered_towers) do
    if other_unit ~= tower.unit_number then
      local key = make_pair_key(tower.unit_number, other_unit)
      if not playerdata.overlap_renders[key] then
        local overlap_area = get_intersection_area(area, {left_top = other_entry.left_top.position, right_bottom = other_entry.right_bottom.position})
        if overlap_area then
          -- Collect intersecting existing overlap rectangles
          local intersecting_rects = {}
          for _, overlap_ids in pairs(playerdata.overlap_renders) do
            for _, overlap_id in ipairs(overlap_ids) do
              local existing_render = rendering.get_object_by_id(overlap_id.id)
              if existing_render and existing_render.valid then
                local existing_rect = {
                  left_top = {x = existing_render.left_top.position.x, y = existing_render.left_top.position.y},
                  right_bottom = {x = existing_render.right_bottom.position.x, y = existing_render.right_bottom.position.y}
                }
                if get_intersection_area(overlap_area, existing_rect) then
                  table.insert(intersecting_rects, existing_rect)
                end
              end
            end
          end

          -- Subtract the intersecting rectangles from the overlap_area
          local parts = subtract_rectangles(overlap_area, intersecting_rects)

          -- Render each part
          for _, part in ipairs(parts) do
            local overlap_id = rendering.draw_rectangle{
              left_top = part.left_top,
              right_bottom = part.right_bottom,
              surface = surface,
              players = {playerdata.player_index},
              color = {1, 0.3, 0.2, 0.10},
              filled = true
            }
            -- Store the id
            if not playerdata.overlap_renders[key] then
              playerdata.overlap_renders[key] = {}
            end
            table.insert(playerdata.overlap_renders[key], overlap_id)
          end
        end
      end
    end
  end
end

local function destroy_tower_render(unit_number, playerdata)
  if not playerdata then return end
  local tower_entry = playerdata.rendered_towers[unit_number]
  if tower_entry then
    tower_entry.destroy()
    playerdata.rendered_towers[unit_number] = nil
  end

  for key, overlap_ids in pairs(playerdata.overlap_renders) do
    local a, b = key:match("^(%d+)_(%d+)$")
    if a == tostring(unit_number) or b == tostring(unit_number) then
      for _, id in ipairs(overlap_ids) do
        id.destroy()
      end
      playerdata.overlap_renders[key] = nil
    end
  end
end

function Handler.on_tower_removed(event)
  local entity = event.entity
  if not entity then return end
  if is_agricultural_tower_type(entity) then
    for _, playerdata in pairs(storage.playerdata) do
      destroy_tower_render(entity.unit_number, playerdata)
    end
  end
end

-- render green rectengles as per the game
function Handler.tick_player(event)
    local playerdata = storage.playerdata[event.player_index]
    if not playerdata then return end

    local player = assert(game.get_player(event.player_index))
    local surface = player.surface

    local chunk_position_with_player = flib_position.to_chunk(player.position)

    local all_visual_towers = {}

    for _, chunk_position in ipairs(get_chunks_in_viewport(chunk_position_with_player)) do
        --chunkposition top left corner and bottom right corner
        local left_top = flib_position.from_chunk(chunk_position)
        local right_bottom = {left_top.x + 32, left_top.y + 32}

        -- find all towers in visible chunks
        local found_towers_in_chunk = surface.find_entities_filtered{
            area = {left_top, right_bottom},
            type = "agricultural-tower"
        }

        local found_tower_ghosts = surface.find_entities_filtered{
            area = {left_top, right_bottom},
            type = "entity-ghost"
        }

        --add all towers and tower ghosts to the list of towers to render
        for _, tower_entity in pairs(found_towers_in_chunk) do
            if not tower_entity.to_be_deconstructed() then
                table.insert(all_visual_towers, tower_entity)
            end
        end

        for _, ghost_entity in pairs(found_tower_ghosts) do
            if is_agricultural_tower_entity[ghost_entity.ghost_name] then
                table.insert(all_visual_towers, ghost_entity)
            end
        end
        
    end

    -- First, collect current unit numbers
    local current_unit_numbers = {}
    for _, tower in pairs(all_visual_towers) do
        current_unit_numbers[tower.unit_number] = true
    end

    -- Remove renders for towers no longer present in view
    local to_remove = {}
    for unit_number, _ in pairs(playerdata.rendered_towers) do
        if not current_unit_numbers[unit_number] then
            table.insert(to_remove, unit_number)
        end
    end
    for _, unit_number in ipairs(to_remove) do
        destroy_tower_render(unit_number, playerdata)
    end

    -- Render only newly visible towers
    for _, tower in pairs(all_visual_towers) do
        render_tower(tower, surface, playerdata)
    end
end

function Handler.on_tower_built(event)
  local entity = event.entity or event.created_entity
  if not entity then return end

  if is_agricultural_tower_type(entity) then
    for _, playerdata in pairs(storage.playerdata) do
      render_tower(entity, entity.surface, playerdata)
    end
  end
end

-- When player moves
script.on_event({
  defines.events.on_player_changed_position,
  defines.events.on_player_changed_surface
}, Handler.tick_player)

-- When player mines
script.on_event({
 --defines.events.on_pre_player_mined_item,
  defines.events.on_player_mined_entity,
  defines.events.on_robot_pre_mined,
  defines.events.on_entity_died,
  defines.events.on_marked_for_deconstruction
}, Handler.on_tower_removed)

-- When player builds
script.on_event({
  defines.events.on_built_entity
}, Handler.on_tower_built)