-- AI Companion - Goal/task RCON commands
local u = require("commands.init")
local goals = require("commands.goals")

-- <id> may be "-" for a shared goal not tied to any one companion (e.g. a
-- strategic milestone); watch_type isn't valid without a companion.
local VALID_WATCH_TYPES = {harvest = true, craft = true, build = true}

commands.add_command("fac_goal_create", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s*(.*)$", cmd.parameter)
    local id = nil
    if args[1] and args[1] ~= "-" then
      id = u.find_companion(args[1])
      if not id then u.error_response("Companion not found"); return end
    end
    local rest = args[2] or ""
    -- Only a companion-tied goal can auto-resolve, and only via one of the
    -- three real watch types — anything else (or a shared goal) is just
    -- description text, not a watch_type to peel off the front.
    local watch_type, description = nil, rest
    if id then
      local first, remainder = rest:match("^(%S+)%s*(.*)$")
      if first and VALID_WATCH_TYPES[first] then
        watch_type, description = first, remainder
      end
    end
    if description == "" then description = watch_type or "" end
    u.json_response(goals.create(id, description, watch_type))
  end)
end)

commands.add_command("fac_goal_update", nil, function(cmd)
  u.safe_command(function()
    local args = u.parse_args("^(%S+)%s+(%S+)%s*(.*)$", cmd.parameter)
    if not args[1] then u.error_response("Usage: fac_goal_update <id> <status> [note]"); return end
    local note = args[3] ~= "" and args[3] or nil
    u.json_response(goals.update(args[1], args[2], note))
  end)
end)

commands.add_command("fac_goal_list", nil, function(cmd)
  u.safe_command(function()
    local param = cmd.parameter or ""
    local filter = {}
    local cid = tonumber(param:match("^%d+$"))
    if cid then filter.companion_id = cid
    elseif param ~= "" then filter.status = param end
    u.json_response(goals.list(filter))
  end)
end)

commands.add_command("fac_goal_get", nil, function(cmd)
  u.safe_command(function()
    local g = goals.get(cmd.parameter)
    if not g then u.error_response("Goal not found"); return end
    u.json_response(g)
  end)
end)

commands.add_command("fac_goal_delete", nil, function(cmd)
  u.safe_command(function()
    u.json_response(goals.delete(cmd.parameter))
  end)
end)
