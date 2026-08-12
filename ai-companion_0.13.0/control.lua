-- AI Companion - Factorio 2.x
local u = require("commands.init")
local queues = require("commands.queues")
local goals = require("commands.goals")
local gui = require("commands.gui")

-- Get version dynamically from mod info
local MOD_VERSION = script.active_mods["ai-companion"] or "unknown"

local function init_storage()
  storage.companion_messages = storage.companion_messages or {}
  storage.companions = storage.companions or {}
  storage.companion_next_id = storage.companion_next_id or 1
  storage.walking_queues = storage.walking_queues or {}
  storage.context_clear_requests = storage.context_clear_requests or {}
  storage.errors = storage.errors or {}
  storage.companion_markers = storage.companion_markers or {}
  queues.init()
  goals.init()
  gui.init()
end

local function cleanup_messages()
  local new_msgs, now = {}, game.tick
  for _, m in ipairs(storage.companion_messages) do
    if not m.read or (now - m.tick) < 18000 then new_msgs[#new_msgs + 1] = m end
  end
  if #new_msgs > 100 then
    local trimmed = {}
    for i = #new_msgs - 99, #new_msgs do trimmed[#trimmed + 1] = new_msgs[i] end
    new_msgs = trimmed
  end
  storage.companion_messages = new_msgs
end

script.on_init(function()
  init_storage()
  gui.ensure_buttons()
  game.print("[AI Companion] v" .. MOD_VERSION .. " ready. /fac for help", u.print_color(u.COLORS.system))
end)

script.on_configuration_changed(function()
  init_storage()
  gui.ensure_buttons()
  game.print("[AI Companion] Updated to v" .. MOD_VERSION, u.print_color(u.COLORS.system))
end)

-- Auto-defend: companions fight back when hit by an enemy
script.on_event(defines.events.on_entity_damaged, function(event)
  local entity = event.entity
  if not entity or not entity.valid or entity.type ~= "character" then return end
  local cause = event.cause
  if not cause or not cause.valid then return end
  if not cause.force or cause.force.name ~= "enemy" then return end
  for cid, c in pairs(storage.companions) do
    if c.entity == entity then
      queues.start_combat(cid, cause.position)
      break
    end
  end
end)

local subcommands = {}

subcommands.spawn = function(player, args)
  local count = math.min(tonumber(args) or 1, 10)
  table.insert(storage.companion_messages, {player = player.name, message = "spawn " .. count, tick = game.tick, read = false, spawn_request = count})
  game.print("[" .. player.name .. "] Spawn " .. count .. " companion(s)...", u.print_color(u.COLORS.player))
end

subcommands.list = function(player)
  local count = 0
  for id, c in pairs(storage.companions) do
    if c.entity and c.entity.valid then
      local p = c.entity.position
      game.print(string.format("[#%d] (%.1f, %.1f)", id, p.x, p.y), u.print_color(c.color or u.get_companion_color(id)))
      count = count + 1
    else storage.companions[id] = nil end
  end
  if count == 0 then game.print("[AI Companion] No companions. /fac spawn", u.print_color(u.COLORS.system)) end
end

subcommands.kill = function(player, args)
  local id, killed = tonumber(args), 0
  local function kill_one(cid)
    local c = storage.companions[cid]
    if c then
      if c.label and c.label.valid then c.label.destroy() end
      -- Remove map marker
      if storage.companion_markers and storage.companion_markers[cid] then
        if storage.companion_markers[cid].valid then storage.companion_markers[cid].destroy() end
        storage.companion_markers[cid] = nil
      end
      if c.entity and c.entity.valid then c.entity.destroy(); killed = killed + 1 end
      storage.companions[cid] = nil
    end
  end
  if id then kill_one(id) else for cid in pairs(storage.companions) do kill_one(cid) end end
  game.print("[AI Companion] Killed " .. killed, u.print_color(u.COLORS.system))
end

subcommands.clear = function()
  local count = #storage.companion_messages
  storage.companion_messages = {}
  game.print("[AI Companion] Cleared " .. count .. " msg(s)", u.print_color(u.COLORS.system))
end

subcommands.name = function(player, args)
  local id_str, name = args:match("^(%d+)%s+(.+)$")
  local id = tonumber(id_str)
  if not id or not name then player.print("/fac name <id> <name>", u.print_color(u.COLORS.system)); return end
  local c = u.get_companion(id)
  if not c then player.print("#" .. id .. " not found", u.print_color(u.COLORS.error)); return end
  c.name = name
  if c.label and c.label.valid then c.label.destroy() end
  local color = c.color or u.get_companion_color(id)
  c.label = u.render_label(c.entity, name .. "(#" .. id .. ")", color)
  game.print("#" .. id .. " -> " .. name, u.print_color(color))
end

local function handle_fac(cmd)
  local ok, err = pcall(function()
    local player = cmd.player_index and game.players[cmd.player_index]
    if cmd.player_index and (not player or not player.valid) then return end
    local param = cmd.parameter
    if not param or param == "" then
      if player then player.print("/fac <msg> | <id> <msg> | spawn | list | kill | clear | name", u.print_color(u.COLORS.system)) end
      return
    end
    local first, rest = param:match("^(%S+)%s+(.+)$")
    if first and rest and not subcommands[first] then
      local id, comp = u.find_companion(first)
      if id then
        table.insert(storage.companion_messages, {player = player.name, message = rest, tick = game.tick, read = false, target_companion = id})
        game.print("[" .. player.name .. " -> " .. u.get_companion_display(id) .. "] " .. rest, u.print_color(comp.color or u.get_companion_color(id)))
        return
      end
    end
    local sub, args = param:match("^(%S+)%s*(.*)")
    if subcommands[sub] then subcommands[sub](player, args)
    else
      table.insert(storage.companion_messages, {player = player and player.name or "server", message = param, tick = game.tick, read = false})
      game.print("[" .. (player and player.name or "server") .. "] " .. param, u.print_color(u.COLORS.player))
    end
  end)
  if not ok then u.error_response(err, "fac"); game.print("Error: " .. tostring(err), u.print_color(u.COLORS.error)) end
end

commands.add_command("fac", "AI Companion", handle_fac)

-- Bridge interface: lets RCON Lua callers (remote.call) do what the fac_*
-- console commands do, since raw console commands aren't reachable that way.
local function equip_companion(e)
  local guns = e.get_inventory(defines.inventory.character_guns)
  local ammo = e.get_inventory(defines.inventory.character_ammo)
  if guns and guns.is_empty() then guns.insert{name = "pistol", count = 1} end
  if ammo then ammo.insert{name = "firearm-magazine", count = 20} end
  e.selected_gun_index = 1

  -- Power armor + belt immunity: characters standing on transport belts get
  -- physically carried by them, which repeatedly derailed companions walking
  -- through built-up areas (mining_state/walking_state logic has no belt
  -- awareness). Belt immunity equipment is the vanilla fix.
  local armor_inv = e.get_inventory(defines.inventory.character_armor)
  if armor_inv and armor_inv.is_empty() then armor_inv.insert{name = "power-armor"} end
  local armor_stack = armor_inv and armor_inv[1]
  if armor_stack and armor_stack.valid_for_read and armor_stack.grid then
    local grid = armor_stack.grid
    if grid.count("belt-immunity-equipment") == 0 then grid.put{name = "belt-immunity-equipment"} end
    -- Belt immunity draws power from the grid; without a source it just sits inert.
    if grid.count("battery-equipment") == 0 then grid.put{name = "battery-equipment"} end
  end
end

remote.add_interface("ai_companion_bridge", {
  spawn_companion = function(count)
    count = math.min(math.max(tonumber(count) or 1, 1), 10)
    local p = game.players[1]
    if not p or not p.valid then return {error = "No player"} end
    local ids = {}
    for _ = 1, count do
      local id = storage.companion_next_id
      storage.companion_next_id = id + 1
      local e = p.surface.create_entity{name = "character", position = {x = p.position.x + id * 2, y = p.position.y}, force = p.force}
      if e then
        local color = u.get_companion_color(id)
        e.color = color
        equip_companion(e)
        storage.companions[id] = {entity = e, color = color, label = u.render_label(e, "#" .. id, color), spawned_tick = game.tick}
        game.print("[#" .. id .. " spawned]", u.print_color(color))
        ids[#ids + 1] = id
      end
    end
    return {spawned = ids}
  end,

  equip_weapon = function(id)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    equip_companion(c.entity)
    return {id = cid, equipped = true}
  end,

  list_companions = function()
    local list = {}
    for id, c in pairs(storage.companions) do
      if c.entity and c.entity.valid then
        local pos = c.entity.position
        local e = c.entity
        list[#list + 1] = {id = id, x = pos.x, y = pos.y, name = c.name, health = e.health, max_health = e.prototype.get_max_health()}
      end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
  end,

  chat_say = function(msg, id)
    if not id or tostring(id) == "0" then
      game.print("[Claude] " .. tostring(msg), u.print_color(u.COLORS.orchestrator))
      return {id = 0, name = "Claude", said = msg}
    end
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    game.print("[" .. u.get_companion_display(cid) .. "] " .. tostring(msg), u.print_color(c.color or u.get_companion_color(cid)))
    return {id = cid, name = c.name, said = msg}
  end,

  chat_get = function()
    local msgs = {}
    for _, m in ipairs(storage.companion_messages) do
      if not m.read then
        msgs[#msgs + 1] = {player = m.player, message = m.message, tick = m.tick}
        m.read = true
      end
    end
    return msgs
  end,

  move_follow = function(id, player_name)
    local cid = tonumber(id)
    if not cid or not u.get_companion(cid) then return {error = "Companion not found"} end
    local pname = player_name or (game.players[1] and game.players[1].name)
    if not pname or not game.get_player(pname) then return {error = "Player not found"} end
    storage.walking_queues[cid] = {follow_player = pname}
    return {id = cid, following = pname}
  end,

  move_stop = function(id)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    storage.walking_queues[cid] = nil
    c.entity.walking_state = {walking = false}
    return {id = cid, stopped = true}
  end,

  mine_ore = function(id, count, resource_name)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    count = tonumber(count) or 20
    local filter = {type = "resource", position = c.entity.position, radius = 200}
    if resource_name and resource_name ~= "" then filter.name = resource_name end
    local res = c.entity.surface.find_entities_filtered(filter)
    if #res == 0 then return {error = "No resource found nearby"} end
    table.sort(res, function(a, b) return u.distance(a.position, c.entity.position) < u.distance(b.position, c.entity.position) end)
    local target = res[1]
    storage.walking_queues[cid] = nil
    c.entity.teleport(target.position)
    local result = queues.start_harvest(cid, target.position, count, resource_name and resource_name ~= "" and resource_name or nil)
    return {id = cid, resource = target.name, position = {x = target.position.x, y = target.position.y}, result = result}
  end,

  companion_inventory = function(id)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local items = {}
    for _, item in pairs(inv.get_contents()) do
      items[#items + 1] = {name = item.name, count = item.count}
    end
    table.sort(items, function(a, b) return a.count > b.count end)
    return {id = cid, items = items}
  end,

  store_ore = function(builder_id, depositor_ids, chest_type, item_name)
    local cid, c = u.find_companion(tostring(builder_id))
    if not cid then return {error = "Builder companion not found"} end
    chest_type = (chest_type and chest_type ~= "") and chest_type or "iron-chest"
    item_name = (item_name and item_name ~= "") and item_name or "iron-ore"

    local surf, force = c.entity.surface, c.entity.force
    local base = c.entity.position
    local chest = nil
    local offsets = {{1,0},{-1,0},{0,1},{0,-1},{2,0},{0,2},{-2,0},{0,-2}}
    for _, off in ipairs(offsets) do
      local pos = {x = base.x + off[1], y = base.y + off[2]}
      if surf.can_place_entity{name = chest_type, position = pos, force = force} then
        chest = surf.create_entity{name = chest_type, position = pos, force = force}
        break
      end
    end
    if not chest then return {error = "No room to place chest"} end

    local chest_inv = chest.get_inventory(defines.inventory.chest)
    local deposits = {}
    for _, did in ipairs(depositor_ids) do
      local dcid, dc = u.find_companion(tostring(did))
      if dcid then
        local inv = dc.entity.get_inventory(defines.inventory.character_main)
        local have = inv.get_item_count(item_name)
        if have > 0 then
          local ins = chest_inv.insert{name = item_name, count = have}
          if ins > 0 then inv.remove{name = item_name, count = ins} end
          deposits[#deposits + 1] = {id = dcid, deposited = ins}
        else
          deposits[#deposits + 1] = {id = dcid, deposited = 0}
        end
      end
    end
    return {builder = cid, chest = chest_type, position = {x = chest.position.x, y = chest.position.y}, deposits = deposits}
  end,

  diagnose_companion = function(id)
    local cid, c = u.find_companion(tostring(id))
    if not cid then
      local raw = storage.companions[tonumber(id)]
      return {error = "Not found via find_companion", raw_exists = raw ~= nil, raw_entity_valid = raw and raw.entity and raw.entity.valid}
    end
    local e = c.entity
    local nearby = e.surface.find_entities_filtered{position = e.position, radius = 1}
    local near_list = {}
    for _, n in ipairs(nearby) do
      near_list[#near_list + 1] = {name = n.name, type = n.type, unit_number = n.unit_number, is_self = (n == e)}
    end
    local out = {id = cid, position = {x = e.position.x, y = e.position.y}, nearby = near_list}
    local fields = {
      valid = function() return e.valid end,
      selectable = function() return e.prototype.selectable_in_game end,
      still_in_vehicle = function() return e.vehicle ~= nil end,
      color = function() return e.color end,
      label_exists = function() return c.label ~= nil end,
      label_valid = function() return c.label and c.label.valid end,
      surface = function() return e.surface.name end,
      character_running_speed = function() return e.character_running_speed end,
      walking_state = function() return e.walking_state end,
      active = function() return e.active end,
      destructible = function() return e.destructible end,
    }
    for key, fn in pairs(fields) do
      local fok, fv = pcall(fn)
      out[key] = fok and fv or ("ERR: " .. tostring(fv))
    end
    return out
  end,

  kill_companion = function(id)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local pos, surf = c.entity.position, c.entity.surface
    local dropped = {}
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    if inv then
      for _, item in pairs(inv.get_contents()) do
        surf.spill_item_stack{position = pos, stack = {name = item.name, count = item.count, quality = item.quality}, enable_looted = true}
        dropped[#dropped + 1] = {name = item.name, count = item.count}
      end
    end
    if c.label and c.label.valid then c.label.destroy() end
    if storage.companion_markers and storage.companion_markers[cid] then
      if storage.companion_markers[cid].valid then storage.companion_markers[cid].destroy() end
      storage.companion_markers[cid] = nil
    end
    c.entity.destroy()
    storage.context_clear_requests[cid] = game.tick
    storage.companions[cid] = nil
    storage.walking_queues[cid] = nil
    game.print("[#" .. cid .. " gone]", u.print_color(u.COLORS.system))
    return {id = cid, killed = true, dropped = dropped}
  end,

  -- ===== Realistic (tick-based) mode: travel, mine, craft, build =====

  move_to = function(id, x, y)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local tx, ty = tonumber(x), tonumber(y)
    if not tx or not ty then return {error = "Invalid coordinates"} end
    local off = u.spread_offset(cid)
    local target = {x = tx + off.x, y = ty + off.y}
    storage.walking_queues[cid] = {target = target}
    return {id = cid, walking_to = target}
  end,

  companion_status = function(id)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local wq = storage.walking_queues[cid]
    return {
      id = cid,
      position = {x = c.entity.position.x, y = c.entity.position.y},
      walking = wq ~= nil,
      walk_target = wq and wq.target,
      following = wq and wq.follow_player,
      harvest = queues.get_harvest_status(cid),
      craft = queues.get_craft_status(cid),
      build = queues.get_build_status(cid),
    }
  end,

  harvest_start = function(id, x, y, count, resource_name)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local tx, ty = tonumber(x), tonumber(y)
    if not tx or not ty then return {error = "Invalid coordinates"} end
    local off = u.spread_offset(cid)
    local result = queues.start_harvest(cid, {x = tx + off.x, y = ty + off.y}, tonumber(count) or 20, (resource_name and resource_name ~= "") and resource_name or nil)
    result.id = cid
    return result
  end,

  harvest_status = function(id)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    return queues.get_harvest_status(cid)
  end,

  harvest_stop = function(id)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    return queues.stop_harvest(cid)
  end,

  craft_start = function(id, recipe, count)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local result = queues.start_craft(cid, recipe, tonumber(count) or 1)
    result.id = cid
    return result
  end,

  craft_status = function(id)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    return queues.get_craft_status(cid)
  end,

  craft_stop = function(id)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    return queues.stop_craft(cid)
  end,

  build_start = function(id, entity_name, x, y, direction)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local tx, ty = tonumber(x), tonumber(y)
    if not tx or not ty then return {error = "Invalid coordinates"} end
    local dir = u.dir_map[tonumber(direction) or 0] or defines.direction.north
    local result = queues.start_build(cid, entity_name, {x = tx, y = ty}, dir)
    result.id = cid
    return result
  end,

  build_status = function(id)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    return queues.get_build_status(cid)
  end,

  -- Instant multi-entity placement from a Factorio blueprint export string.
  place_blueprint = function(id, x, y, blueprint_string)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local tx, ty = tonumber(x), tonumber(y)
    if not tx or not ty or not blueprint_string or blueprint_string == "" then
      return {error = "Invalid arguments"}
    end
    local bp, err = u.decode_blueprint(blueprint_string)
    if not bp then return {error = err} end
    local result = u.place_blueprint(c, bp, tx, ty)
    result.id = cid
    return result
  end,

  -- Complete construction ghosts within radius of (x,y) using matching items
  -- from the companion's inventory.
  finish_ghosts = function(id, x, y, radius)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local tx, ty = tonumber(x), tonumber(y)
    if not tx or not ty then return {error = "Invalid coordinates"} end
    local result = u.finish_ghosts(c, tx, ty, tonumber(radius) or 10)
    result.id = cid
    return result
  end,

  build_stop = function(id)
    local cid = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    return queues.stop_build(cid)
  end,

  -- Fuel a burner-type entity (furnace, boiler, etc.) from the companion's inventory
  fuel_entity = function(id, fuel, amount, x, y)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local have = inv.get_item_count(fuel)
    if have == 0 then return {error = "No " .. fuel} end
    local pos = (tonumber(x) and tonumber(y)) and {x = tonumber(x), y = tonumber(y)} or c.entity.position
    local es = c.entity.surface.find_entities_filtered{position = pos, radius = 3, type = {"furnace", "boiler", "burner-inserter", "car", "locomotive", "mining-drill"}}
    if #es == 0 then return {error = "No burner nearby"} end
    local fi = es[1].get_fuel_inventory()
    if not fi then return {error = "No fuel slot"} end
    local ins = fi.insert{name = fuel, count = math.min(tonumber(amount) or 5, have)}
    if ins > 0 then inv.remove{name = fuel, count = ins}; return {id = cid, inserted = ins, fuel = fuel} end
    return {error = "Full"}
  end,

  -- Move items between the companion's inventory and a nearby entity (chest/furnace/assembler slots)
  transfer_item = function(id, item, count, x, y, direction)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local pos = (tonumber(x) and tonumber(y)) and {x = tonumber(x), y = tonumber(y)} or c.entity.position
    local es = c.entity.surface.find_entities_filtered{position = pos, radius = 3}
    local n = tonumber(count) or 10
    if direction == "in" then
      local have = inv.get_item_count(item)
      if have == 0 then return {error = "No " .. item .. " in inventory"} end
      for _, e in ipairs(es) do
        if e.valid and e ~= c.entity then
          local r = e.insert{name = item, count = math.min(n, have)}
          if r > 0 then inv.remove{name = item, count = r}; return {id = cid, transferred = r, item = item, direction = "in"} end
        end
      end
      return {error = "Could not insert"}
    else
      for _, e in ipairs(es) do
        if e.valid and e ~= c.entity then
          for _, slot in ipairs({defines.inventory.chest, defines.inventory.furnace_result, defines.inventory.assembling_machine_output}) do
            local einv = e.get_inventory(slot)
            if einv then
              local av = einv.get_item_count(item)
              if av > 0 then
                local rm = einv.remove{name = item, count = math.min(n, av)}
                if rm > 0 then c.entity.insert{name = item, count = rm}; return {id = cid, transferred = rm, item = item, direction = "out"} end
              end
            end
          end
        end
      end
      return {error = "Not found nearby"}
    end
  end,

  -- Bootstrap helper: directly grant items to a companion's inventory (e.g. a starter tool/building kit)
  give_item = function(id, item, count)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    local inv = c.entity.get_inventory(defines.inventory.character_main)
    local ins = inv.insert{name = item, count = tonumber(count) or 1}
    return {id = cid, item = item, inserted = ins}
  end,

  renumber_companion = function(old_id, new_id)
    old_id, new_id = tonumber(old_id), tonumber(new_id)
    local c = storage.companions[old_id]
    if not c then return {error = "Companion #" .. tostring(old_id) .. " not found"} end
    if storage.companions[new_id] then return {error = "#" .. new_id .. " is already in use"} end
    storage.companions[new_id] = c
    storage.companions[old_id] = nil
    if storage.walking_queues[old_id] then
      storage.walking_queues[new_id] = storage.walking_queues[old_id]
      storage.walking_queues[old_id] = nil
    end
    if storage.companion_markers and storage.companion_markers[old_id] then
      storage.companion_markers[new_id] = storage.companion_markers[old_id]
      storage.companion_markers[old_id] = nil
    end
    if c.label and c.label.valid then c.label.destroy() end
    local label_text = c.name and (c.name .. "(#" .. new_id .. ")") or ("#" .. new_id)
    c.label = u.render_label(c.entity, label_text, c.color or u.get_companion_color(new_id))
    if new_id >= storage.companion_next_id then storage.companion_next_id = new_id + 1 end
    return {old_id = old_id, new_id = new_id, renumbered = true}
  end,

  rename_companion = function(id, name)
    local cid, c = u.find_companion(tostring(id))
    if not cid then return {error = "Companion not found"} end
    if not name or name == "" then return {error = "Name required"} end
    if c.label and c.label.valid then c.label.destroy() end
    c.name = name
    c.label = u.render_label(c.entity, name .. "(#" .. cid .. ")", c.color or u.get_companion_color(cid))
    return {id = cid, name = name, renamed = true}
  end,

  -- ===== Persistent goal/task tracking =====
  -- watch_type ("harvest"|"craft"|"build") auto-resolves the goal to done/failed
  -- when that companion's matching action queue finishes; omit it for a manually-tracked goal.
  -- id may be omitted/empty for a shared goal not tied to any one companion
  -- (e.g. a strategic milestone) -- watch_type isn't valid without a companion,
  -- since there's no action queue to watch.
  goal_create = function(id, description, watch_type)
    watch_type = watch_type ~= "" and watch_type or nil
    local cid = nil
    if id and tostring(id) ~= "" then
      cid = u.find_companion(tostring(id))
      if not cid then return {error = "Companion not found"} end
    elseif watch_type then
      return {error = "watch_type requires a companion id"}
    end
    return goals.create(cid, description, watch_type)
  end,

  goal_update = function(goal_id, status, note)
    return goals.update(goal_id, status, note)
  end,

  goal_get = function(goal_id)
    local g = goals.get(goal_id)
    return g or {error = "Goal not found"}
  end,

  goal_delete = function(goal_id)
    return goals.delete(goal_id)
  end,

  goal_list = function(companion_id, status)
    local filter = {}
    if companion_id and tostring(companion_id) ~= "" then filter.companion_id = tonumber(companion_id) end
    if status and status ~= "" then filter.status = status end
    return goals.list(filter)
  end,

  toggle_goals_gui = function(player_name)
    local p = (player_name and player_name ~= "") and game.get_player(player_name) or game.players[1]
    if not p or not p.valid then return {error = "Player not found"} end
    gui.toggle(p)
    return {player = p.name, open = p.gui.screen.ai_companion_goals ~= nil}
  end,
})

require("commands.action")
require("commands.building")
require("commands.chat")
require("commands.companion")
require("commands.context")
require("commands.goal")
require("commands.item")
require("commands.move")
require("commands.research")
require("commands.resource")
require("commands.world")
require("commands.combat")
require("commands.help")

-- Update companion map markers
local function update_companion_markers()
  if not storage.companion_markers then storage.companion_markers = {} end
  for cid, c in pairs(storage.companions) do
    if c.entity and c.entity.valid then
      local marker = storage.companion_markers[cid]
      local display = u.get_companion_display(cid)
      -- Create marker if doesn't exist
      if not marker or not marker.valid then
        local force = c.entity.force
        local surf = c.entity.surface
        marker = force.add_chart_tag(surf, {
          position = c.entity.position,
          text = display
        })
        storage.companion_markers[cid] = marker
      else
        -- Update marker position
        marker.position = c.entity.position
      end
    else
      -- Companion died/invalid, remove marker
      local marker = storage.companion_markers[cid]
      if marker and marker.valid then marker.destroy() end
      storage.companion_markers[cid] = nil
    end
  end
end

script.on_nth_tick(5, function(ev)
  if ev.tick % 1800 == 0 then cleanup_messages() end
  -- Update map markers and the position readout every 30 ticks (0.5 sec)
  if ev.tick % 30 == 0 then update_companion_markers(); gui.update_position_labels() end
  -- Keep the goals toolbar button present and refresh any open goals GUI once a second.
  -- Not just on_init/on_configuration_changed: those don't fire on a plain restart
  -- with an unchanged mod version, so this is the reliable path on existing saves.
  if ev.tick % 60 == 0 then gui.ensure_buttons(); gui.refresh_open() end
  -- Process all tick-based queues (realistic actions)
  queues.tick_harvest_queues()
  queues.tick_craft_queues()
  queues.tick_build_queues()
  queues.tick_combat_queues()
  -- Process walking queues
  if not storage.walking_queues then return end
  for cid, q in pairs(storage.walking_queues) do
    local c = u.get_companion(cid)
    if not c then storage.walking_queues[cid] = nil; goto skip end
    if q.follow_player then
      local p = game.players[q.follow_player]
      if p and p.valid then
        local angle = (cid % 8) * (2 * math.pi / 8)
        q.target = {x = p.position.x + math.cos(angle) * 2.5, y = p.position.y + math.sin(angle) * 2.5}
      else storage.walking_queues[cid] = nil; goto skip end
    end
    if not q.target then storage.walking_queues[cid] = nil; goto skip end
    local e, dist = c.entity, u.distance(c.entity.position, q.target)
    if dist < 1 then
      e.walking_state = {walking = false}
      q.stuck_pos, q.stuck_tick, q.sidestep_until = nil, nil, nil
      if not q.follow_player then storage.walking_queues[cid] = nil end
    else
      -- Stuck detection: if barely moved in the last ~60 ticks, sidestep perpendicular to the path
      if q.sidestep_until and game.tick < q.sidestep_until then
        local dir = u.get_direction(e.position, q.sidestep_target)
        if dir then e.walking_state = {walking = true, direction = dir} end
      else
        if q.sidestep_until then q.sidestep_until = nil end
        if not q.stuck_pos or game.tick - (q.stuck_tick or 0) >= 60 then
          if q.stuck_pos and u.distance(e.position, q.stuck_pos) < 0.5 then
            local dx, dy = q.target.x - e.position.x, q.target.y - e.position.y
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0 then
              local px, py = -dy / len, dx / len
              if (cid % 2) == 0 then px, py = -px, -py end
              q.sidestep_target = {x = e.position.x + px * 4, y = e.position.y + py * 4}
              q.sidestep_until = game.tick + 60
            end
          end
          q.stuck_pos, q.stuck_tick = {x = e.position.x, y = e.position.y}, game.tick
        end
        if not q.sidestep_until then
          local dir = u.get_direction(e.position, q.target)
          if dir then e.walking_state = {walking = true, direction = dir} end
        end
      end
    end
    ::skip::
  end
end)
