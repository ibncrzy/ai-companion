-- AI Companion - Help
local u = require("commands.init")

-- Version command
commands.add_command("fac_version", nil, function()
  local version = script.active_mods["ai-companion"] or "unknown"
  u.json_response({version = version, factorio = script.active_mods["base"] or "unknown"})
  game.print("[AI Companion] v" .. version, u.print_color(u.COLORS.system))
end)

-- Kept in sync by hand with the actual commands.add_command(...) calls across
-- commands/*.lua (mirrors commands_reference.bat) — it can't be generated at
-- runtime since the Factorio API doesn't expose a list of registered commands.
commands.add_command("fac_help", nil, function()
  local version = script.active_mods["ai-companion"] or "unknown"
  u.json_response({
    version = version,
    commands = 59,
    categories = {"action", "building", "chat", "companion", "context", "goal", "item", "move", "research", "resource", "world", "misc"},
    action = {"attack", "attack_start", "attack_status", "attack_stop", "defend", "flee", "patrol", "wololo"},
    building = {"can_place", "empty", "fill", "finish_ghosts", "fuel", "info", "place", "place_blueprint", "place_start", "place_status", "recipe", "remove", "rotate"},
    chat = {"get", "say"},
    companion = {"disappear", "health", "inventory", "list", "position", "spawn"},
    context = {"check", "clear"},
    goal = {"create", "delete", "get", "list", "update"},
    item = {"craft", "craft_start", "craft_status", "craft_stop", "pick", "recipes"},
    move = {"follow", "stop", "to"},
    research = {"get", "progress", "set"},
    resource = {"list", "mine", "mine_status", "mine_stop", "nearest"},
    world = {"enemies", "nearest", "scan"},
    misc = {"version", "help"},
    player = {"/fac <msg>", "/fac <id> <msg>", "/fac spawn", "/fac list", "/fac kill", "/fac clear", "/fac name"}
  })
end)
