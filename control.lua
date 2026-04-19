local flib_position = require("__flib__.position")
local flib_bounding_box = require("__flib__.bounding-box")

local debug_mode = false

local Handler = {}

script.on_init(function()
  storage.playerdata = {}
end)

-- Is this entity an agricultural tower?
local is_agricultural_tower_entity = {}
for _, entity in pairs(prototypes.entity) do
  is_agricultural_tower_entity[entity.name] = entity.type == "agricultural-tower"
end

-- Get the Position of the Tower!
local function position_key(position)
  assert(position.x)
  assert(position.y)
  return string.format("[%g, %g]", position.x, position.y)
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
script.on_event(defines.events.on_player_cursor_stack_changed, function(event)
  local player = game.get_player(event.player_index)
  assert(player)

  local playerdata = storage.playerdata[player.index]

  if playerdata == nil then
    if is_player_holding_agricultural_tower(player) then
      storage.playerdata[player.index] = {
        player_index = player.index,
        surface_index = player.surface.index,

        rectangles = {},
        seen_chunks = {},

        tile_render_objects = {},
        rendered_towers = {},
      }

      Handler.tick_player(event)
    end
  else
    if is_player_holding_agricultural_tower(player) ~= true then
        for _, rectangle in pairs(playerdata.rectangles) do
            rectangle.destroy()
        end

        for _, tile_render_object in pairs(playerdata.tile_render_objects) do
            tile_render_object.destroy()
        end

        storage.playerdata[player.index] = nil
    end
  end

end)


local function get_tower_planting_radius(proto)
  game.print(proto.name .. ": selection_box_offset: " .. selection_box_offset .. " grid_radius: " .. proto.radius )
  return 3*2
end

local function add_selection_box_offset(proto, pos, r)
  local selection_box = proto.selection_box

  local offset_left_top = selection_box.left_top
  local offset_right_bottom = selection_box.right_bottom

  if debug_mode then
    game.print(proto.name .. ":left_top = {" .. offset_left_top.x .. ", " .. offset_left_top.y .. "} Pos = {" .. pos.x .. ", " .. pos.y .. "}"
            .."right_bottom = {" .. offset_right_bottom.x .. ", " .. offset_right_bottom.y .. "}")
  end

  local left_top = {x = pos.x + offset_left_top.x - r,
                    y = pos.y + offset_left_top.y - r}
  local right_bottom = {x = pos.x + offset_right_bottom.x + r,
                        y = pos.y + offset_right_bottom.y + r}

  return left_top, right_bottom
end


-- render each tower overlay
local function render_tower(tower, surface, playerdata) 
  local id = playerdata.rendered_towers[tower.unit_number]
  
  if not id then
    local proto = tower.prototype    
    local pos = tower.position

    local r = get_tower_planting_radius(proto)

    local left_top, right_bottom = add_selection_box_offset(proto, pos, r)

    id = rendering.draw_rectangle{
      left_top = left_top,
      right_bottom = right_bottom,
      surface = surface,
      players = {playerdata.player_index},
      color = {0.3, 1, 0.3, 0.15},
      filled = false
      }
      
      playerdata.rendered_towers[tower.unit_number] = id
      table.insert(playerdata.rectangles, id)
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

        -- add all found towers into a lookup
        for _, tower_entity in pairs(found_towers_in_chunk) do
            table.insert(all_visual_towers, tower_entity)
        end

        
        ::continue::
    end
        -- render all 
    for _, tower in pairs(all_visual_towers) do
        render_tower(tower, surface, playerdata)
    end
end


--TODO Render Overlaping areas red
    --destroy render when tower is deconstrocted 
    --Entity-Ghost not working creating a render


script.on_event(defines.events.on_player_changed_position, Handler.tick_player)
