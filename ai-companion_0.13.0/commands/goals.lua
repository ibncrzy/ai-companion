-- AI Companion - Persistent goal/task tracking
local M = {}

local VALID_STATUS = {pending = true, in_progress = true, done = true, failed = true}

function M.init()
  storage.goals = storage.goals or {}
  storage.goal_next_id = storage.goal_next_id or 1
end

function M.create(companion_id, description, watch_type)
  M.init() -- self-heal: this table may not exist yet on saves from before goals.lua was added
  local id = storage.goal_next_id
  storage.goal_next_id = id + 1
  local goal = {
    id = id,
    companion_id = tonumber(companion_id),
    description = description or "",
    status = watch_type and "in_progress" or "pending",
    watch_type = watch_type,
    note = nil,
    created_tick = game.tick,
    updated_tick = game.tick
  }
  storage.goals[id] = goal
  return goal
end

function M.update(goal_id, status, note)
  M.init()
  local g = storage.goals[tonumber(goal_id)]
  if not g then return {error = "Goal not found"} end
  if status then
    if not VALID_STATUS[status] then return {error = "Invalid status: " .. tostring(status)} end
    g.status = status
  end
  if note ~= nil then g.note = note end
  g.updated_tick = game.tick
  return g
end

-- Called by queues.lua when a watched harvest/craft/build queue finishes,
-- so goals created with a watch_type auto-resolve without manual updates.
function M.resolve_watch(companion_id, watch_type, success, note)
  M.init()
  for _, g in pairs(storage.goals) do
    if g.companion_id == companion_id and g.watch_type == watch_type and g.status == "in_progress" then
      g.status = success and "done" or "failed"
      g.note = note
      g.updated_tick = game.tick
    end
  end
end

function M.get(goal_id)
  M.init()
  return storage.goals[tonumber(goal_id)]
end

function M.list(filter)
  M.init()
  filter = filter or {}
  local out = {}
  for _, g in pairs(storage.goals) do
    local include = true
    if filter.companion_id and g.companion_id ~= filter.companion_id then include = false end
    if filter.status and g.status ~= filter.status then include = false end
    if include then out[#out + 1] = g end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

return M
