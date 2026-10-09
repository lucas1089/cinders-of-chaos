-- Item links in chat. Shift+click on an item in the inventory or a container puts "[Item Name]" into the chat input
-- (up to 3 per message); the server (extended opcode 249, server/data/scripts/chaos/itemlink.lua) checks the player
-- carries the item and keeps a snapshot of its tooltip for 10 minutes under a random id; when the message is sent the
-- name is replaced by the link text "[Item Name]{<r><id>}", which travels as ordinary speech (default channel, party,
-- guild, channels, private messages). Messages that contain links are shown here with the name in the rarity colour;
-- hovering one asks the server for the snapshot and shows the same tooltip as an inventory item (Ctrl compares).
--   client -> server  register {n, items = [{pos = {x, y, z}, iid}], ctx = {kind, id}}   get {id}
--   server -> client  registered {n, links = [{token, name, rarity}]}  refused {n, reason}
--                     link {id, tip, owner, left} | link {id, gone}   caps {help}
-- The console is the stock one (game_console): this module wraps three of its functions (Message:updateLabel to colour
-- and hook the links, Chat:sendMessage to write the chips out, Chat:sendMapText to keep the markers off the map) and
-- puts them back on terminate. The pure logic is in chatlinks_logic.lua.

local OPCODE = 249
local POLL_MS = 60 -- how often the pointer is looked at while it is over a message with links
local L = ChatLinksLogic

local store = L.newStore() -- link id -> snapshot / expired answer
local seen = {} -- link ids that appeared in a message shown here: only these are asked for
local chips = {} -- { { name, token } } of the message being written
local requests = {} -- nonce -> { at } of register requests in flight
local nonce = 0
local helpAllowed = false -- the server says: this player may link in the Help channel (tutors)
local hoverRange, hoverWidget -- the link under the pointer
local original = {}
local handlers = {}

local function now()
  return os.time()
end

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, a, b = pcall(fn, ...)
    if not ok then
      if not reported then
        reported = true
        g_logger.warning('[chatlinks] ' .. name .. ': ' .. tostring(a))
      end
      return false
    end
    return a, b
  end
end

local function console()
  return modules.game_console
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data }))
  end
end

local function say(text)
  local tm = modules.game_textmessage
  if tm and tm.displayFailureMessage then
    tm.displayFailureMessage(text)
  else
    g_logger.info('[chatlinks] ' .. text)
  end
end

-- ---------------------------------------------------------------- the tab being written in
local function tabInfo(tab)
  if not tab then return nil end
  local c = console()
  return {
    name = tab:getName(), id = tab:getId(), private = tab:isPrivate(), npc = tab:isNpcChat(),
    loot = tab:isLootChannel(), spell = tab:isSpellChannel(), local_ = tab:isLocalChat(),
    serverLog = tab.isServerLogChat and tab:isServerLogChat() or false,
  }
end

local function currentContext()
  local c = console()
  local chat = c and c.g_chat
  local tab = chat and chat:getCurrentTab()
  return L.contextOf(tabInfo(tab), helpAllowed)
end

-- ---------------------------------------------------------------- writing a link
local function itemIid(item)
  local ok, v = pcall(function() return item:getCustomAttribute(6) end)
  return ok and tonumber(v) or 0
end

local function editWidget()
  local c = console()
  return c and c.getConsole and c.getConsole() or nil
end

local function linkItem(item, pos)
  local edit = editWidget()
  if not edit or not edit:isEnabled() then return false end
  local ctx, why = currentContext()
  if not ctx then
    say(why or 'Items cannot be linked here.')
    return true
  end
  local text = edit:getText()
  chips = L.liveChips(text, chips)
  local ok, reason = L.canAdd(text, chips, { name = '', token = string.rep('x', 30) })
  if not ok then
    say(reason)
    return true
  end
  nonce = nonce + 1
  requests[nonce] = { at = now() }
  send('register', { n = nonce, items = { { pos = { x = pos.x, y = pos.y, z = pos.z }, iid = L.iidText(itemIid(item)) } }, ctx = ctx })
  return true
end

local function insertChip(name, token)
  local edit = editWidget()
  if not edit then return end
  chips = L.liveChips(edit:getText(), chips)
  local ok, reason = L.canAdd(edit:getText(), chips, { name = name, token = token })
  if not ok then
    say(reason)
    return
  end
  chips[#chips + 1] = { name = name, token = token }
  local label = '[' .. name .. '] '
  if not pcall(function() edit:appendText(label) end) then
    edit:setText(edit:getText() .. label)
  end
end

-- Shift + left click on an item widget of the inventory or an open container, with the chat input active
local function onItemMouseRelease(widget, mousePos, button)
  if button ~= MouseLeftButton or not g_keyboard.isShiftPressed() or g_keyboard.isCtrlPressed() then
    return false
  end
  if not g_game.isOnline() or widget:isVirtual() or not widget:containsPoint(mousePos) then return false end
  local item = widget:getItem()
  if not item then return false end
  local pos = item:getPosition()
  if not L.linkable(pos) then return false end
  local c = console()
  if c and c.isChatEnabled and not c.isChatEnabled() then return false end
  return linkItem(item, pos) == true
end

-- ---------------------------------------------------------------- sending
local function wrappedSendMessage(self, message, tab)
  local t = tab or self:getCurrentTab()
  local out = message
  if type(message) == 'string' then
    local allowed = L.contextOf(tabInfo(t), helpAllowed) ~= nil
    out = L.expand(message, allowed and chips or {})
    out = L.scrub(out, allowed)
    if #out > 255 then out = message end
  end
  chips = {}
  return original.sendMessage(self, out, tab)
end

-- the floating text over a player shows the names only
local function wrappedSendMapText(self, mode, creaturePos, name, message)
  return original.sendMapText(self, mode, creaturePos, name, L.plain(message))
end

-- ---------------------------------------------------------------- showing links
local function asTooltip(entry, range)
  if entry and entry.tip then return entry.tip end
  return { name = range.name, id = 0, count = 1, rarity = range.rarity, desc = 'This item link has expired.' }
end

local function footer(entry)
  if entry and entry.tip then
    return { { text = L.footer(entry.owner, entry, now()), color = '#8c8070', sep = true } }
  end
  return nil
end

local function showLink(widget, range)
  local tt = modules.game_itemtooltip
  if not tt or not tt.showTip then return end
  local entry = L.get(store, range.id, now())
  if entry then
    tt.showTip(widget, 'link:' .. range.id, asTooltip(entry, range), footer(entry))
  elseif L.shouldAsk(store, range.id, now()) and seen[range.id] and g_game.isOnline() then
    send('get', { id = range.id })
  end
end

local function hideLink()
  local tt = modules.game_itemtooltip
  if tt and tt.hideTip and hoverWidget then tt.hideTip(hoverWidget) end
  hoverRange, hoverWidget = nil, nil
end

local function onLinkHover(widget, index, hovered)
  local range = hovered and L.rangeAt(widget.chatLinks, index) or nil
  if range then
    if hoverRange ~= range or hoverWidget ~= widget then
      if hoverWidget and hoverWidget ~= widget then hideLink() end
      hoverRange, hoverWidget = range, widget
      showLink(widget, range)
    end
  elseif hoverRange and hoverWidget == widget then
    hideLink()
  end
end

local pollEvent, pollWidget

local function pollOnce()
  pollEvent = nil
  local widget = pollWidget
  if not widget or widget:isDestroyed() or not widget.chatLinks then
    pollWidget = nil
    hideLink()
    return
  end
  local pos = g_window.getMousePosition()
  if not widget:containsPoint(pos) then
    pollWidget = nil
    onLinkHover(widget, -1, false)
    return
  end
  onLinkHover(widget, widget:getTextPos(pos), true)
  pollEvent = scheduleEvent(pollOnce, POLL_MS)
end

local function startPolling(widget)
  pollWidget = widget
  if not pollEvent then pollEvent = scheduleEvent(pollOnce, POLL_MS) end
end

local function stopPolling(widget)
  if pollWidget == widget then
    pollWidget = nil
    if pollEvent then removeEvent(pollEvent) pollEvent = nil end
    onLinkHover(widget, -1, false)
  end
end

local function onLinkClick(widget, index)
  local range = L.rangeAt(widget.chatLinks, index)
  if range then
    store.asked[range.id] = nil
    hoverRange, hoverWidget = range, widget
    showLink(widget, range)
  end
end

local function decorate(self, label)
  local c = console()
  local types = MessageTypes or (c and c.MessageTypes)
  local mt = types and types[self.mode]
  local p = L.pieces(self:format(), mt and mt.color or 'white')
  if #p.ranges == 0 then return end
  for _, r in ipairs(p.ranges) do seen[r.id] = true end
  label:setColoredText(p.parts)
  label.chatLinks = p.ranges
  -- the console's labels are text edits: they send no text hover events and no mouse move events to Lua, only
  -- onHoverChange; while the pointer is over a label with links its position in the text is polled
  label.onHoverChange = safe('hover', function(widget, hovered)
    if hovered then
      startPolling(widget)
    else
      stopPolling(widget)
    end
  end)
end

local decorateSafe = safe('updateLabel', decorate)

local function wrappedUpdateLabel(self, label, tab)
  if label.chatLinks then
    label.chatLinks, label.onHoverChange = nil, nil
    if pollWidget == label then stopPolling(label) end
  end
  original.updateLabel(self, label, tab)
  if type(self.text) == 'string' and self.text:find('{', 1, true) then
    decorateSafe(self, label)
  end
end

-- a left click on a link shows its tooltip again (the stock handler runs as before)
local function wrappedHandleMouseRelease(self, label, mousePos, mouseButton)
  if mouseButton == MouseLeftButton and label.chatLinks then
    onLinkClick(label, label:getTextPos(mousePos))
  end
  return original.handleMouseRelease(self, label, mousePos, mouseButton)
end

-- ---------------------------------------------------------------- server
local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  local d = msg.data
  if msg.action == 'registered' then
    requests[tonumber(d.n) or 0] = nil
    for _, k in ipairs(type(d.links) == 'table' and d.links or {}) do
      if type(k.token) == 'string' and type(k.name) == 'string' then insertChip(k.name, k.token) end
    end
  elseif msg.action == 'refused' then
    requests[tonumber(d.n) or 0] = nil
    say(tostring(d.reason or 'That item cannot be linked.'))
  elseif msg.action == 'link' then
    if not L.validId(d.id) then return end
    if d.gone or type(d.tip) ~= 'table' then
      L.put(store, d.id, { gone = true }, now())
    else
      L.put(store, d.id, { tip = d.tip, owner = d.owner, left = tonumber(d.left) or L.TTL }, now())
    end
    if hoverRange and hoverRange.id == d.id and hoverWidget and not hoverWidget:isDestroyed() then
      showLink(hoverWidget, hoverRange)
    end
  elseif msg.action == 'caps' then
    helpAllowed = d.help == true
  end
end

local function reset()
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
  pollWidget = nil
  store = L.newStore()
  seen, chips, requests = {}, {}, {}
  helpAllowed = false
  hoverRange, hoverWidget = nil, nil
end

function init()
  local c = console()
  if not c or not c.Message or not c.Chat then
    g_logger.warning('[chatlinks] the console is not available: item links are off')
    return
  end
  original.updateLabel = c.Message.updateLabel
  original.handleMouseRelease = c.Message.handleMouseRelease
  original.sendMessage = c.Chat.sendMessage
  original.sendMapText = c.Chat.sendMapText
  c.Message.updateLabel = wrappedUpdateLabel
  c.Message.handleMouseRelease = wrappedHandleMouseRelease
  c.Chat.sendMessage = wrappedSendMessage
  c.Chat.sendMapText = wrappedSendMapText
  handlers.mouse = safe('mouse', onItemMouseRelease)
  handlers.reset = safe('reset', reset)
  connect(UIItem, { onMouseRelease = handlers.mouse }, true)
  connect(g_game, { onGameStart = handlers.reset, onGameEnd = handlers.reset })
  ProtocolGame.registerExtendedOpcode(OPCODE, safe('opcode', onExtendedOpcode))
end

function terminate()
  local c = console()
  if c and c.Message and original.updateLabel then
    c.Message.updateLabel = original.updateLabel
    c.Message.handleMouseRelease = original.handleMouseRelease
    c.Chat.sendMessage = original.sendMessage
    c.Chat.sendMapText = original.sendMapText
  end
  if handlers.mouse then disconnect(UIItem, { onMouseRelease = handlers.mouse }) end
  disconnect(g_game, { onGameStart = handlers.reset, onGameEnd = handlers.reset })
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  reset()
end
