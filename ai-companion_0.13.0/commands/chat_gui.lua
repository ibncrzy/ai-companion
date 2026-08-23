-- AI Companion - In-game chat history GUI
local u = require("commands.init")

local M = {}

function M.init()
  storage.chat_gui_open = storage.chat_gui_open or {}
end

local function build_frame(player)
  if player.gui.screen.ai_companion_chat then player.gui.screen.ai_companion_chat.destroy() end

  local frame = player.gui.screen.add{type = "frame", name = "ai_companion_chat", direction = "vertical"}
  frame.auto_center = true

  local titlebar = frame.add{type = "flow", direction = "horizontal"}
  titlebar.drag_target = frame
  titlebar.add{type = "label", caption = "AI Companion Chat", style = "frame_title", ignored_by_interaction = true}
  local filler = titlebar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  titlebar.add{type = "sprite-button", name = "ai_companion_chat_close", sprite = "utility/close", style = "frame_action_button"}

  local scroll = frame.add{type = "scroll-pane", name = "scroll", direction = "vertical"}
  scroll.style.maximal_height = 400
  scroll.style.minimal_width = 480

  local log = storage.chat_log or {}
  if #log == 0 then
    scroll.add{type = "label", caption = "No messages yet. Type /fac <message> in chat."}
  else
    for _, m in ipairs(log) do
      local label = scroll.add{type = "label", caption = "[" .. m.who .. "] " .. m.text}
      label.style.single_line = false
      if m.color then label.style.font_color = m.color end
    end
  end

  frame.add{type = "label", caption = "Type /fac <message> in chat to talk.", style = "info_label"}
  return frame
end

function M.toggle(player)
  M.init()
  if player.gui.screen.ai_companion_chat then
    player.gui.screen.ai_companion_chat.destroy()
    storage.chat_gui_open[player.index] = nil
  else
    build_frame(player)
    storage.chat_gui_open[player.index] = true
  end
end

-- Called periodically from control.lua's tick handler so anyone with the
-- panel open sees new messages as they arrive (typed in-game or posted back
-- by the external chat bridge over RCON) without having to reopen it.
function M.refresh_open()
  M.init()
  for player_index in pairs(storage.chat_gui_open) do
    local player = game.players[player_index]
    if player and player.valid then
      local frame = player.gui.screen.ai_companion_chat
      -- Only rebuild (and re-scroll to bottom) when the log actually grew,
      -- so an open panel isn't fighting the player's own scroll position.
      local log = storage.chat_log or {}
      if not frame or frame.tags.count ~= #log then
        build_frame(player).tags = {count = #log}
        local scroll = player.gui.screen.ai_companion_chat.scroll
        if scroll then scroll.scroll_to_bottom() end
      end
    else
      storage.chat_gui_open[player_index] = nil
    end
  end
end

local function ensure_button(player)
  if player.gui.top.ai_companion_chat_toggle then return end
  player.gui.top.add{
    type = "sprite-button",
    name = "ai_companion_chat_toggle",
    sprite = "item/blueprint",
    tooltip = "AI Companion Chat"
  }
end

function M.ensure_buttons()
  for _, player in pairs(game.players) do
    if player.valid then ensure_button(player) end
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

  if element.name == "ai_companion_chat_toggle" then
    M.toggle(player)
  elseif element.name == "ai_companion_chat_close" then
    if player.gui.screen.ai_companion_chat then player.gui.screen.ai_companion_chat.destroy() end
    storage.chat_gui_open[event.player_index] = nil
  end
end)

return M
