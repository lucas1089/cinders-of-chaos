-- Referral window (server data/scripts/chaos/referral.lua, extended opcode 220, JSON {action, data}).
--   client -> server  open | sync | enter {code}
--   server -> client  status {...} (open = true: show the window) | message {text, error}
-- Menu: Character > Referral (added to client_chaos_topbar with ChaosTopBar.addEntry). The server decides everything;
-- this window shows the account's code (Copy code puts it on the clipboard), takes a friend's code while the account
-- is new, and lists the referred friends with their milestones.

local OPCODE = 220
local V = ReferralView

local window
local status
local handlers = {}
local reported = {}

local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[referral] ' .. name .. ': ' .. tostring(res))
      end
      return nil
    end
    return res
  end
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data or {} }))
  end
end

local function note(text, color)
  if window then
    window.note:setText(text or '')
    window.note:setColor(color or '#8c8070')
  end
end

local function fillFriends()
  local list = window.friends
  list:destroyChildren()
  window.friendsPlate.friendsTitle:setText(V.friendsHeader(status))
  window.empty:setText(V.emptyText(status))
  for _, r in ipairs(V.friendRows(status)) do
    local w = g_ui.createWidget('ReferralFriendRow', list)
    w.name:setText(r.name)
    w.sub:setText(r.sub)
    for _, st in ipairs(r.steps) do
      local l = g_ui.createWidget('ReferralStep', w.steps)
      l:setText(st.text)
      l:setColor(st.color)
    end
  end
end

local function refresh()
  if not window or not status then return end
  local code, under = V.code(status)
  window.header.code:setText(code)
  window.header.codeNote:setText(under)
  window.header.copyButton:setEnabled((status.code or '') ~= '')
  window.rewards:setText(V.rewardsText(status))
  local text, box = V.entry(status)
  window.entryText:setText(text)
  window.codeEdit:setVisible(box)
  window.enterButton:setVisible(box)
  window.month:setText(V.monthText(status))
  fillFriends()
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  local d = msg.data
  if msg.action == 'status' then
    status = d
    refresh()
    if d.open and window then
      note('')
      window:show()
      window:raise()
      window:focus()
    end
  elseif msg.action == 'message' then
    note(d.text or '', d.error and '#e07060' or '#80c070')
  end
end

function show()
  send('open')
end

function hide()
  if window then window:hide() end
end

function toggle()
  if window and window:isVisible() then hide() else show() end
end

function copyCode()
  if not status or (status.code or '') == '' then return end
  local text = (status.shareUrl or '') ~= '' and status.shareUrl or status.code
  if g_window and g_window.setClipboardText then
    g_window.setClipboardText(text)
    note(tr('Copied: ') .. text, '#80c070')
  end
end

function enterCode()
  if not window then return end
  local code = window.codeEdit:getText()
  if code == '' then
    note(tr('Type the code first.'), '#e07060')
    return
  end
  send('enter', { code = code })
end

-- for other modules and tests
function getState()
  return { status = status, visible = window and window:isVisible() or false }
end

local function addMenu()
  local top = modules.client_chaos_topbar
  local api = top and top.ChaosTopBar
  if api and api.addEntry and not handlers.menu then
    handlers.menu = pcall(api.addEntry, 'character',
      { text = 'Referral', icon = 'vip', modules = { 'game_referral' }, fns = { 'toggle' } })
  end
end

local function onGameStart()
  status = nil
  addMenu()
end

local function onGameEnd()
  hide()
  status = nil
end

function init()
  g_ui.importStyle('referral')
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  local ok, ui = pcall(g_ui.createWidget, 'ReferralWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
  else
    g_logger.warning('[referral] window not loaded: ' .. tostring(ui))
  end
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  addMenu()
  if g_game.isOnline() then onGameStart() end
end

function terminate()
  disconnect(g_game, handlers.game)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if window then window:destroy() window = nil end
  handlers = {}
end
