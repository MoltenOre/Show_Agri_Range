if mods["maraxsis"] then
  local proto = data.raw["agricultural-tower"]["maraxsis-fishing-tower"]
  if proto then
    proto.grid_selection_box_offset = 1
  end
end

if mods["condensing-agricultural-tower"] then
  local proto = data.raw["agricultural-tower"]["condensing-agricultural-tower"]
  if proto then
    proto.selection_box = {{-1.5, -1.5}, {1.5, 1.5}}
  end
end


for _, proto in pairs(data.raw["agricultural-tower"] or {}) do
  local radius = proto.radius or 2
  log("Processing: " .. proto.name .. " with radius " .. radius .. " and growth_grid_tile_size: " .. serpent.line(proto.growth_grid_tile_size))

  local growth_grid_tile_size = proto.growth_grid_tile_size or 3
  proto.grid_radius = radius * growth_grid_tile_size
  log("grid_radius: " .. serpent.line(proto.grid_radius))

end