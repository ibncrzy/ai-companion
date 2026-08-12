-- AI Companion v0.9.0
local M = {}

M.COLORS = {
  player = {r=0.4, g=0.8, b=1},
  orchestrator = {r=0.3, g=1, b=0.3},
  system = {r=1, g=0.5, b=0},
  error = {r=1, g=0, b=0}
}

M.COMPANION_COLORS = {
  {r=1, g=0.6, b=0.2}, {r=0.8, g=0.4, b=1}, {r=1, g=1, b=0.3}, {r=0.4, g=1, b=0.8},
  {r=1, g=0.4, b=0.6}, {r=0.6, g=0.8, b=1}, {r=1, g=0.8, b=0.4}, {r=0.7, g=1, b=0.5}
}

M.dir_map = {
  [0] = defines.direction.north, [1] = defines.direction.east,
  [2] = defines.direction.south, [3] = defines.direction.west
}

function M.print_color(c) return {color = c} end

function M.get_companion_color(id)
  return M.COMPANION_COLORS[((id - 1) % #M.COMPANION_COLORS) + 1]
end

function M.json_response(data)
  local ok, result = pcall(helpers.table_to_json, data)
  rcon.print(ok and result or '{"error":"JSON failed"}')
end

function M.error_response(msg, ctx)
  if storage.errors then
    table.insert(storage.errors, {context = ctx or "rcon", error = tostring(msg), tick = game.tick})
    if #storage.errors > 50 then table.remove(storage.errors, 1) end
  end
  rcon.print('{"error":"' .. tostring(msg) .. '"}')
end

function M.safe_command(callback)
  local ok, err = pcall(callback)
  if not ok then
    M.error_response(err)
  end
end

function M.get_companion(id)
  local c = storage.companions[id]
  return (c and c.entity and c.entity.valid) and c or nil
end

function M.find_companion(identifier)
  local id = tonumber(identifier)
  if id then
    local c = M.get_companion(id)
    if c then return id, c end
  end
  for cid, c in pairs(storage.companions) do
    if c.name and c.name:lower() == identifier:lower() and c.entity and c.entity.valid then
      return cid, c
    end
  end
  return nil, nil
end

function M.get_companion_display(id)
  local c = storage.companions[id]
  return c and c.name and (c.name .. "(#" .. id .. ")") or ("#" .. id)
end

function M.parse_args(pattern, args)
  return args and {args:match(pattern)} or {}
end

function M.distance(a, b)
  return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

-- Small per-companion offset so a group sent to the same nominal coordinates
-- (move_to/harvest) spreads out instead of stacking on the same tile.
function M.spread_offset(id)
  local angle = (id % 8) * (2 * math.pi / 8)
  return {x = math.cos(angle) * 0.3, y = math.sin(angle) * 0.3}
end

-- LuaInventory:get_contents() returns an ARRAY of {name, count, quality} records
-- in Factorio 2.0 (not a dict keyed by item name, since quality tiers of the same
-- item can coexist). Collapse it to a name -> total-count map for delta math.
function M.inventory_totals(contents)
  local totals = {}
  for _, item in pairs(contents) do
    totals[item.name] = (totals[item.name] or 0) + item.count
  end
  return totals
end

-- The item that places a given entity doesn't always share its name (e.g.
-- entity "straight-rail"/"elevated-straight-rail" are both placed by item
-- "rail"). Resolve via the prototype instead of assuming item == entity.
function M.place_item_name(entity_name)
  local proto = prototypes.entity[entity_name]
  local items = proto and proto.items_to_place_this
  return (items and items[1] and items[1].name) or entity_name
end

-- Decode a Factorio blueprint export string into its entity list.
-- Returns (blueprint_table, nil) on success or (nil, error_message) on failure.
function M.decode_blueprint(str)
  -- Export strings start with a version byte (e.g. "0") that must be stripped
  -- before decode_string; passing it through makes decode_string return nil.
  local ok, decoded = pcall(helpers.decode_string, str:sub(2))
  if not ok or not decoded then return nil, "Invalid blueprint string" end
  local ok2, data = pcall(helpers.json_to_table, decoded)
  if not ok2 or not data then return nil, "Failed to parse blueprint" end
  local bp = data.blueprint
  if not bp or not bp.entities or #bp.entities == 0 then
    return nil, "No entities in blueprint (blueprint books not supported)"
  end
  return bp
end

-- Instantly place every entity in a decoded blueprint from the companion's
-- inventory, anchored so the blueprint's first entity lands at (x, y).
function M.place_blueprint(c, bp, x, y)
  local surf, force = c.entity.surface, c.entity.force
  local inv = c.entity.get_inventory(defines.inventory.character_main)
  local anchor = bp.entities[1].position
  local offset = {x = x - anchor.x, y = y - anchor.y}

  local placed, failed = {}, {}
  for _, ent in ipairs(bp.entities) do
    local pos = {x = ent.position.x + offset.x, y = ent.position.y + offset.y}
    local dir = ent.direction or 0
    local item_name = M.place_item_name(ent.name)
    if inv.get_item_count(item_name) < 1 then
      failed[#failed + 1] = {name = ent.name, reason = "not in inventory", position = pos}
    elseif not surf.can_place_entity{name = ent.name, position = pos, direction = dir, force = force} then
      failed[#failed + 1] = {name = ent.name, reason = "cannot place", position = pos}
    else
      local e = surf.create_entity{name = ent.name, position = pos, direction = dir, force = force}
      if e then
        inv.remove{name = item_name, count = 1}
        placed[#placed + 1] = {name = ent.name, position = pos}
      else
        failed[#failed + 1] = {name = ent.name, reason = "create_entity failed", position = pos}
      end
    end
  end
  return {placed = #placed, failed = #failed, entities = #bp.entities, failures = failed}
end

-- Complete construction ghosts (unbuilt blueprint entities) within radius of
-- (x, y), consuming matching items from the companion's inventory.
function M.finish_ghosts(c, x, y, radius)
  local surf, force = c.entity.surface, c.entity.force
  local inv = c.entity.get_inventory(defines.inventory.character_main)
  local ghosts = surf.find_entities_filtered{type = "entity-ghost", position = {x = x, y = y}, radius = radius, force = force}

  local finished, failed = {}, {}
  for _, ghost in ipairs(ghosts) do
    if ghost.valid then
      local pos = {x = ghost.position.x, y = ghost.position.y}
      local name = ghost.ghost_name
      local item_name = M.place_item_name(name)
      if inv.get_item_count(item_name) < 1 then
        failed[#failed + 1] = {name = name, reason = "not in inventory", position = pos}
      else
        local ok, revived = pcall(function() return ghost.revive{raise_revive = false} end)
        if ok and revived then
          inv.remove{name = item_name, count = 1}
          finished[#finished + 1] = {name = name, position = pos}
        else
          failed[#failed + 1] = {name = name, reason = "revive failed", position = pos}
        end
      end
    end
  end
  return {finished = #finished, failed = #failed, total = #ghosts, failures = failed}
end

function M.get_direction(from, to)
  local dx, dy = to.x - from.x, to.y - from.y
  if math.abs(dx) < 0.5 and math.abs(dy) < 0.5 then return nil end
  local deg = math.atan2(dy, dx) * 180 / math.pi
  if deg < 0 then deg = deg + 360 end
  local dirs = {
    {337.5, 22.5, defines.direction.east}, {22.5, 67.5, defines.direction.southeast},
    {67.5, 112.5, defines.direction.south}, {112.5, 157.5, defines.direction.southwest},
    {157.5, 202.5, defines.direction.west}, {202.5, 247.5, defines.direction.northwest},
    {247.5, 292.5, defines.direction.north}, {292.5, 337.5, defines.direction.northeast}
  }
  for _, d in ipairs(dirs) do
    if d[1] > d[2] then
      if deg >= d[1] or deg < d[2] then return d[3] end
    elseif deg >= d[1] and deg < d[2] then return d[3] end
  end
  return defines.direction.east
end

function M.render_label(entity, text, color)
  if not rendering then return nil end
  return rendering.draw_text{
    text = text, surface = entity.surface, target = entity,
    target_offset = {0, -2.5}, color = color, scale = 1.5, alignment = "center", use_rich_text = false
  }
end

return M
