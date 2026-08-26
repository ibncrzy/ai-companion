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
  storage.player_position_renders = storage.player_position_renders or {}
end

local function companion_label(companion_id)
  if not companion_id then return "shared" end
  return u.get_companion_display(companion_id)
end

-- Repopulates just the scroll-pane's rows, leaving the frame/titlebar/close
-- button untouched. Previously this rebuilt the whole frame from scratch on
-- every refresh (once a second while open), which meant the close button was
-- being destroyed and recreated out from under the player's cursor — click
-- it at the wrong instant and the click landed on nothing. Updating in place
-- keeps the close button (and the frame itself) stable across refreshes.
local function populate_scroll(scroll)
  scroll.clear()
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
  populate_scroll(scroll)
  return frame
end

function M.toggle(player)
  M.init() -- self-heal: this table may not exist yet on saves from before gui.lua was added
  if player.gui.screen.ai_companion_goals then
    player.gui.screen.ai_companion_goals.destroy()
    storage.goal_gui_open[player.index] = nil
    if player.opened_gui_type == defines.gui_type.custom then player.opened = nil end
  else
    local frame = build_frame(player)
    storage.goal_gui_open[player.index] = true
    -- Registers this as the player's "opened" GUI so the vanilla close-all
    -- shortcut (Escape / E by default) dismisses it too, not just the X
    -- button — matches how every other window in the game behaves.
    player.opened = frame
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
      local frame = player.gui.screen.ai_companion_goals
      if frame and frame.valid and frame.scroll and frame.scroll.valid then
        populate_scroll(frame.scroll)
      else
        -- frame got closed/destroyed some other way (e.g. player pressed
        -- the in-game "close all" hotkey) without going through our close
        -- button handler, so the open-flag never got cleared. Rebuild it
        -- once rather than silently doing nothing every second.
        local rebuilt = build_frame(player)
        player.opened = rebuilt
      end
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

-- Factorio's shared mod-gui library (used by various mods to add top-bar
-- buttons) leaves an empty mod_gui_top_frame/mod_gui_inner_frame pair
-- sitting visible even when nothing ever populated it. Not ours to own, but
-- since any mod that wants it will just recreate it on demand, it's safe to
-- clear out while it's empty rather than leave a blank box on screen.
local function cleanup_empty_mod_gui_frame(player)
  local ok = pcall(function()
    local frame = player.gui.top.mod_gui_top_frame
    if not frame or not frame.valid then return end
    local inner = frame.mod_gui_inner_frame
    if inner and inner.valid and #inner.children == 0 then
      frame.destroy()
    end
  end)
  if not ok then return end
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
  storage.player_position_renders = storage.player_position_renders or {}
  for _, player in pairs(game.players) do
    if player.valid and player.character then
      local pos = player.character.position
      local text = string.format("X: %.0f  Y: %.0f", pos.x, pos.y)

      local label = player.gui.top.ai_companion_position
      if label and label.valid then label.caption = text end

      -- Floating in-world label above the character, same as companion nametags.
      local render = storage.player_position_renders[player.index]
      if render and render.valid then
        render.text = player.name .. "  " .. text
      else
        storage.player_position_renders[player.index] = u.render_label(player.character, player.name .. "  " .. text, {r = 1, g = 1, b = 1})
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
      cleanup_empty_mod_gui_frame(player)
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
    if player.opened_gui_type == defines.gui_type.custom then player.opened = nil end
  end
end)

-- Fires for Escape / E (or any other way the game closes a "player.opened"
-- window) so the goals window responds to the same dismiss shortcut as
-- every other in-game panel, not just its own X button.
script.on_event(defines.events.on_gui_closed, function(event)
  if event.gui_type ~= defines.gui_type.custom then return end
  local element = event.element
  if not element or not element.valid or element.name ~= "ai_companion_goals" then return end
  element.destroy()
  storage.goal_gui_open[event.player_index] = nil
end)

return M
