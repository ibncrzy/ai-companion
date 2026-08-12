-- AI Companion - In-game goal/task GUI
local u = require("commands.init")
local goals = require("commands.goals")

local M = {}

local STATUS_COLOR = {
  pending = {r = 0.7, g = 0.7, b = 0.7},
  in_progress = {r = 1, g = 0.9, b = 0.3},
  done = {r = 0.4, g = 1, b = 0.4},
  failed = {r = 1, g = 0.4, b = 0.4}
}

function M.init()
  storage.goal_gui_open = storage.goal_gui_open or {}
end

local function companion_label(companion_id)
  if not companion_id then return "shared" end
  return u.get_companion_display(companion_id)
end

local function build_frame(player)
  if player.gui.screen.ai_companion_goals then player.gui.screen.ai_companion_goals.destroy() end

  local frame = player.gui.screen.add{type = "frame", name = "ai_companion_goals", direction = "vertical"}
  frame.auto_center = true

  local titlebar = frame.add{type = "flow", direction = "horizontal"}
  titlebar.drag_target = frame
  titlebar.add{type = "label", caption = "AI Companion Goals", style = "frame_title", ignored_by_interaction = true}
  local filler = titlebar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add{type = "sprite-button", name = "ai_companion_goals_close", sprite = "utility/close", style = "frame_action_button"}

  local scroll = frame.add{type = "scroll-pane", name = "scroll", direction = "vertical"}
  scroll.style.maximal_height = 400
  scroll.style.minimal_width = 420

  local list = goals.list()
  if #list == 0 then
    scroll.add{type = "label", caption = "No goals yet."}
  else
    for i = #list, 1, -1 do -- newest first
      local g = list[i]
      local row = scroll.add{type = "flow", direction = "horizontal"}
      local status_label = row.add{type = "label", caption = "[" .. g.status .. "]"}
      status_label.style.font_color = STATUS_COLOR[g.status] or {r = 1, g = 1, b = 1}
      status_label.style.minimal_width = 90
      local text = "#" .. g.id .. " (" .. companion_label(g.companion_id) .. ") " .. g.description
      if g.note then text = text .. "  -  " .. g.note end
      row.add{type = "label", caption = text}
    end
  end
  return frame
end

function M.toggle(player)
  M.init() -- self-heal: this table may not exist yet on saves from before gui.lua was added
  if player.gui.screen.ai_companion_goals then
    player.gui.screen.ai_companion_goals.destroy()
    storage.goal_gui_open[player.index] = nil
  else
    build_frame(player)
    storage.goal_gui_open[player.index] = true
  end
end

-- Called periodically from control.lua's tick handler so the list stays
-- current for anyone with it open, since goals change over RCON between
-- that player's own actions.
function M.refresh_open()
  M.init()
  for player_index in pairs(storage.goal_gui_open) do
    local player = game.players[player_index]
    if player and player.valid then
      build_frame(player)
    else
      storage.goal_gui_open[player_index] = nil
    end
  end
end

local function ensure_button(player)
  if player.gui.top.ai_companion_goals_toggle then return end
  player.gui.top.add{
    type = "sprite-button",
    name = "ai_companion_goals_toggle",
    sprite = "item/repair-pack",
    tooltip = "AI Companion Goals"
  }
end

local function ensure_position_label(player)
  if player.gui.top.ai_companion_position then return end
  local label = player.gui.top.add{
    type = "label",
    name = "ai_companion_position",
    caption = "X: 0  Y: 0"
  }
  label.style.font = "default-bold"
  label.style.left_padding = 8
  label.style.right_padding = 8
end

-- Called periodically from control.lua's tick handler to keep the readout live.
function M.update_position_labels()
  for _, player in pairs(game.players) do
    if player.valid and player.character then
      local label = player.gui.top.ai_companion_position
      if label and label.valid then
        local pos = player.character.position
        label.caption = string.format("X: %.0f  Y: %.0f", pos.x, pos.y)
      end
    end
  end
end

-- on_player_created only fires for genuinely new players, so already-connected
-- players need the button added explicitly on init/config-changed/mod reload.
function M.ensure_buttons()
  for _, player in pairs(game.players) do
    if player.valid then
      ensure_button(player)
      ensure_position_label(player)
    end
  end
end

script.on_event(defines.events.on_player_created, function(event)
  local player = game.players[event.player_index]
  if player and player.valid then ensure_button(player) end
end)

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not element or not element.valid then return end
  local player = game.players[event.player_index]
  if not player or not player.valid then return end

  if element.name == "ai_companion_goals_toggle" then
    M.toggle(player)
  elseif element.name == "ai_companion_goals_close" then
    if player.gui.screen.ai_companion_goals then player.gui.screen.ai_companion_goals.destroy() end
    storage.goal_gui_open[event.player_index] = nil
  end
end)

return M
