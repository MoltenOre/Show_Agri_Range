if mods["maraxsis"] then
  local proto = data.raw["agricultural-tower"]["maraxsis-fishing-tower"]
  if proto then
    proto.selection_box = {{-3, -3}, {3, 3}}
  end
end

if mods["condensing-agricultural-tower"] then
  local proto = data.raw["agricultural-tower"]["condensing-agricultural-tower"]
  if proto then
    proto.selection_box = {{-1.5, -1.5}, {1.5, 1.5}}
  end
end

if mods["aquilo-seabloom-algaculture"] then
  local proto = data.raw["agricultural-tower"]["algacultural-bay"]
  if proto then
    proto.growth_area_radius = proto.growth_area_radius + 0.5
  end
end