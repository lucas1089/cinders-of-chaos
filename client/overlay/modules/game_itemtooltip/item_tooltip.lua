-- Rich item tooltips (server-driven). Hovering an item in the inventory or an open container asks the server
-- (extended opcode 242, server/data/scripts/chaos/item_tooltip.lua) for its tooltip: name, rarity, item level, base
-- stats, every modifier with its tier and roll range, sockets and gems, unique and set (the pieces worn and the bonuses
-- active; the cached set pieces are dropped when the equipment changes), requirements. Holding Ctrl
-- shows the equipped item(s) worn the same way next to it, and the hovered tooltip lists the differences per stat
-- (green better, red worse).
-- Tooltips are cached by the item's per-item id and version (item custom attributes, game_itemrarity ChaosItemAttr):
-- the version changes whenever the server changes the item (orbs, gems), so a changed item is asked for again.
-- Items without those attributes (plain items, or a server without engine patch 0003) are cached for a short time
-- under their position, id and count. A tooltip with counted charges is asked for again whenever its slot gets the
-- item again (the server sends an exercise weapon after every training hit): the shown charges follow the training.
-- The view logic is in tooltiplogic.lua (tested by tooltiplogic_test.lua).
--   client -> server  get {items = [{pos = {x, y, z}, iid, cid, n}]}   (iid as a decimal string; cid = the client id,
--                     n = the count of a stackable: the server answers for that item, tooltiplogic.lua L.tipMatches)
--   server -> client  tips {items = [{pos, iid, tip} | {pos, iid, gone}]}

local OPCODE = 242
local L = ItemTooltipLogic
local C = L.COLORS

local PAD_X, PAD_TOP, LINE_GAP, SEP_GAP = 8, 46, 1, 5
local MIN_WIDTH = 190
local ASK_DELAY = 60 -- ms of hover before asking the server
local PENDING_TIMEOUT = 2 -- s before an unanswered request may be sent again
local CTRL_POLL = 100 -- ms
local RETRY_DELAY, RETRIES = 300, 2 -- an answer for another item (L.tipMatches): ask again this often, at most

local cache = L.newCache()
local pending = {} -- posKey -> {key, plain, at}
local hovered = nil -- {widget, item, pos, key, plain}
local panels = {} -- the tooltip panels on screen (1 = hovered, then the compare ones)
local askEvent, pollEvent
local compareShown = false
local handlers = {}

local function now()
  return os.time()
end

local function safe(name, fn)
  local reported = false
  return function(...)
    local ok, err = pcall(fn, ...)
    if not ok and not reported then
      reported = true
      g_logger.warning('[itemtooltip] ' .. name .. ': ' .. tostring(err))
    end
  end
end

-- ---------------------------------------------------------------- items and keys
local function attr(item, key)
  if getItemAttribute then
    return getItemAttribute(item, key)
  end
  local ok, v = pcall(function() return item:getCustomAttribute(key) end)
  return ok and tonumber(v) or 0
end

local function describe(item)
  local A = ChaosItemAttr or { ID = 6, VERSION = 7 }
  local pos = item:getPosition()
  pos = { x = pos.x, y = pos.y, z = pos.z }
  local iid = attr(item, A.ID)
  local key, plain = L.cacheKey({ id = iid, ver = attr(item, A.VERSION) }, item:getId(), item:getCount(), pos)
  local stackable = item.isStackable and item:isStackable() or false
  return { item = item, pos = pos, iid = iid, key = key, plain = plain,
    ident = L.identity(item:getId(), item:getCount(), stackable) }
end

local function equippedItem(slot)
  local player = g_game.getLocalPlayer()
  return player and player:getInventoryItem(slot) or nil
end

-- ---------------------------------------------------------------- server
local function send(list)
  local protocol = g_game.getProtocolGame()
  if not protocol or #list == 0 then return end
  local items = {}
  for _, d in ipairs(list) do
    -- the id as a string: the JSON encoder writes big numbers with 14 digits (1.8785738780836e+15)
    local ident = d.ident or {}
    items[#items + 1] = { pos = d.pos, iid = L.iidText(d.iid), cid = ident.cid, n = ident.n }
    pending[L.posKey(d.pos, d.iid)] = { key = d.key, plain = d.plain, at = now(), ident = ident }
  end
  protocol:sendExtendedOpcode(OPCODE, json.encode({ action = 'get', data = { items = items } }))
end

local function needs(d)
  if L.cacheGet(cache, d.key, now()) then return false end
  local p = pending[L.posKey(d.pos, d.iid)]
  return not p or now() - p.at > PENDING_TIMEOUT or p.key ~= d.key
end

-- ---------------------------------------------------------------- panels
local function clearPanels()
  for _, p in ipairs(panels) do
    if not p:isDestroyed() then p:destroy() end
  end
  panels = {}
end

local function addLine(panel, y, row)
  local label = g_ui.createWidget('ItemTooltipLine', panel)
  if row.parts and label.setColoredText then
    label:setColoredText(row.parts)
  else
    label:setText(row.text)
    label:setColor(row.color or C.text)
  end
  label:addAnchor(AnchorTop, 'parent', AnchorTop)
  label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  label:setMarginTop(y)
  label:setMarginLeft(PAD_X)
  local size = label:getTextSize()
  label:resize(size.width, size.height)
  return size
end

-- one plate: icon and name, the lines, then extra rows (the differences); returns the panel
local function buildPanel(tip, extra, heading)
  local panel = g_ui.createWidget('ItemTooltipPanel', rootWidget)
  local titleColor = L.titleColor(tip)
  panel:getChildById('band'):setBackgroundColor(titleColor)
  local icon = panel:getChildById('icon')
  icon:setItemId(tip.id or 0)
  if (tip.count or 1) > 1 then icon:setItemCount(tip.count) end
  -- a transmog look (server transmog.lua, tip.look; client base patch 0030): the icon shows the item as it looks, also
  -- for item links in chat (their snapshot carries the look)
  local look = type(tip.look) == 'table' and tonumber(tip.look.cid) or 0
  local iconItem = look > 0 and icon:getItem() or nil
  if iconItem then pcall(function() iconItem:setAppearanceId(look) end) end
  if heading then
    local h = panel:getChildById('header')
    h:setText(heading)
    h:show()
  end
  local width = MIN_WIDTH
  local title = g_ui.createWidget('ItemTooltipTitle', panel)
  title:setText(L.title(tip.name))
  title:setColor(titleColor)
  title:addAnchor(AnchorTop, 'parent', AnchorTop)
  title:addAnchor(AnchorLeft, 'icon', AnchorRight)
  title:setMarginTop(heading and 20 or 12)
  title:setMarginLeft(6)
  local ts = title:getTextSize()
  title:resize(ts.width, ts.height)
  width = math.max(width, 46 + ts.width + PAD_X)

  local y = PAD_TOP
  local rows = L.lines(tip, { level = g_game.getLocalPlayer() and g_game.getLocalPlayer():getLevel() or 0 })
  for _, r in ipairs(extra or {}) do rows[#rows + 1] = r end
  for _, row in ipairs(rows) do
    if row.sep then
      local rule = g_ui.createWidget('ItemTooltipRule', panel)
      rule:addAnchor(AnchorTop, 'parent', AnchorTop)
      rule:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      rule:addAnchor(AnchorRight, 'parent', AnchorRight)
      rule:setMarginTop(y + 2)
      rule:setMarginLeft(PAD_X)
      rule:setMarginRight(PAD_X)
      y = y + SEP_GAP
    end
    local size = addLine(panel, y, row)
    y = y + size.height + LINE_GAP
    width = math.max(width, size.width + 2 * PAD_X)
  end
  panel:resize(width, y + 6)
  return panel
end

-- the rows of the differences hovered - equipped
local function diffRows(tip, other)
  local rows = { { text = tr('Compared with %s', (other.name or tr('equipped'))), color = C.dim, sep = true } }
  local diffs = L.diff(tip, other)
  if #diffs == 0 then
    rows[#rows + 1] = { text = tr('No difference'), color = C.dim }
  end
  for _, d in ipairs(diffs) do
    rows[#rows + 1] = { text = L.diffText(d), color = d.better and C.better or C.worse }
  end
  return rows
end

local function place()
  if #panels == 0 then return end
  local mouse = g_window.getMousePosition()
  local screen = rootWidget:getSize()
  local main = panels[1]
  local total = 0
  for _, p in ipairs(panels) do total = total + p:getWidth() + 4 end
  -- main tooltip right of the cursor when it fits, else left; the compare plates on the side with room
  local x = mouse.x + 18
  if x + main:getWidth() > screen.width then
    x = mouse.x - main:getWidth() - 12
  end
  local function clampY(h)
    return math.max(0, math.min(mouse.y + 8, screen.height - h))
  end
  main:setPosition({ x = math.max(0, x), y = clampY(main:getHeight()) })
  local left = x - 4
  local right = x + main:getWidth() + 4
  for i = 2, #panels do
    local p = panels[i]
    if left - p:getWidth() >= 0 then
      left = left - p:getWidth()
      p:setPosition({ x = left, y = clampY(p:getHeight()) })
      left = left - 4
    else
      p:setPosition({ x = math.min(right, screen.width - p:getWidth()), y = clampY(p:getHeight()) })
      right = right + p:getWidth() + 4
    end
  end
  for _, p in ipairs(panels) do
    p:raise()
    p:show()
  end
end

-- the equipped items in the slots the tooltip names: {[slot] = tip} of those already known, and the ones to ask for
local function equippedTips(tip)
  local bySlot, missing = {}, {}
  for _, slot in ipairs(tip.cmp or {}) do
    local item = equippedItem(slot)
    if item then
      local d = describe(item)
      local known = L.cacheGet(cache, d.key, now())
      if known then
        known.key = known.key or d.key
        bySlot[slot] = known
      elseif d.key ~= hovered.key and needs(d) then
        missing[#missing + 1] = d
      end
    end
  end
  return bySlot, missing
end

local function render()
  clearPanels()
  if not hovered then return end
  local tip = L.cacheGet(cache, hovered.key, now())
  if not tip then return end
  local wantCompare = g_keyboard.isCtrlPressed() and tip.cmp ~= nil
  local extra, others = {}, {}
  for _, r in ipairs(hovered.extra or {}) do extra[#extra + 1] = r end
  if wantCompare then
    local bySlot, missing = equippedTips(tip)
    if #missing > 0 then send(missing) end
    others = L.compareWith(tip, bySlot, hovered.key)
    for _, o in ipairs(others) do
      local partner = o
      if hovered.external then
        -- a linked or inspected item has no "Your Attack Interval" (it is the viewer's own number): leave it out of
        -- the equipped item's side too, or the difference would list it as a change (the estimated DPS is the viewer's too)
        partner = {}
        for k, v in pairs(o) do partner[k] = v end
        partner.stats = {}
        for _, st in ipairs(o.stats or {}) do
          if st.k ~= 'yourinterval' and st.k ~= 'dps' then partner.stats[#partner.stats + 1] = st end
        end
      end
      for _, r in ipairs(diffRows(tip, partner)) do extra[#extra + 1] = r end
    end
    if #others == 0 and #missing == 0 then
      extra[#extra + 1] = { text = tr('Nothing equipped to compare'), color = C.dim, sep = true }
    end
  elseif tip.cmp then
    extra[#extra + 1] = { text = tr('Hold Ctrl to compare'), color = C.dim, sep = true }
  end
  compareShown = wantCompare
  panels[1] = buildPanel(tip, extra)
  for _, o in ipairs(others) do
    panels[#panels + 1] = buildPanel(o, nil, 'Equipped')
  end
  place()
end

local function ask()
  askEvent = nil
  if not hovered or not g_game.isOnline() then return end
  -- the slot's item now (a container shifts its items when one goes in at the front)
  if not hovered.external and hovered.widget and not hovered.widget:isDestroyed() then
    local item = hovered.widget:getItem()
    if item then
      local d = describe(item)
      d.widget, d.retries = hovered.widget, hovered.retries
      hovered = d
    end
  end
  if L.cacheGet(cache, hovered.key, now()) then
    render()
    return
  end
  if needs(hovered) then send({ hovered }) end
end

local function poll()
  pollEvent = nil
  if not hovered then return end
  if hovered.widget:isDestroyed() or not hovered.widget:isVisible() or
      (hovered.external and not hovered.widget:containsPoint(g_window.getMousePosition())) then
    hovered = nil
    clearPanels()
    return
  end
  local ctrl = g_keyboard.isCtrlPressed()
  if #panels > 0 and ctrl ~= compareShown then
    render()
  elseif #panels > 0 then
    place()
  end
  pollEvent = scheduleEvent(poll, CTRL_POLL)
end

-- Tooltips of items that are not in this player's inventory or containers (item links in the chat, the inspect
-- window): the caller has the tooltip and a widget the pointer is over. Same plate, Ctrl compares with what the
-- player wears. key is any string unique to the item, extra = { { text, color, sep } } lines under the tooltip.
function showTip(widget, key, tip, extra)
  if not widget or widget:isDestroyed() or type(tip) ~= 'table' then return end
  L.cachePut(cache, key, tip, false, now())
  if askEvent then removeEvent(askEvent) askEvent = nil end
  hovered = { widget = widget, key = key, plain = false, external = true, extra = extra }
  render()
  if not pollEvent then pollEvent = scheduleEvent(poll, CTRL_POLL) end
end

function hideTip(widget)
  if hovered and hovered.external and (not widget or hovered.widget == widget) then
    hovered = nil
    clearPanels()
  end
end

-- ---------------------------------------------------------------- events
local function onHoverChange(widget, isHovered)
  if not isHovered then
    if hovered and hovered.widget == widget then
      hovered = nil
      clearPanels()
    end
    return
  end
  local item = widget:getItem()
  if not item or widget:isVirtual() or not g_game.isOnline() then return end
  local d = describe(item)
  if not L.askable(d.pos) then return end
  d.widget = widget
  hovered = d
  if askEvent then removeEvent(askEvent) end
  if L.cacheGet(cache, d.key, now()) then
    render()
  else
    clearPanels()
    askEvent = scheduleEvent(ask, ASK_DELAY)
  end
  if not pollEvent then pollEvent = scheduleEvent(poll, CTRL_POLL) end
end

-- a slot got its item again with the same key: a cached tooltip with counted charges is stale (L.liveTip; an exercise
-- weapon in training). Dropped, so the next hover asks; returns true when the hovered one was dropped.
local function dropLive(widget, d)
  if not L.liveTip(L.cacheGet(cache, d.key, now())) then return false end
  L.cacheDrop(cache, d.key)
  return hovered ~= nil and hovered.widget == widget and not hovered.external
end

-- the hovered slot got a new item or the same item with a new version: ask again. The same item with counted charges
-- is asked for again too; the shown plate stays until the answer comes (no flicker on every training hit).
local function onItemChange(widget)
  local item = widget:getItem()
  if not hovered or hovered.widget ~= widget then
    if item and not widget:isVirtual() then
      local d = describe(item)
      if L.askable(d.pos) then dropLive(widget, d) end
    end
    return
  end
  if not item then
    hovered = nil
    clearPanels()
    return
  end
  local d = describe(item)
  d.widget = widget
  if d.key ~= hovered.key then
    hovered = d
    if L.cacheGet(cache, d.key, now()) then render() else
      clearPanels()
      if askEvent then removeEvent(askEvent) end
      askEvent = scheduleEvent(ask, ASK_DELAY)
    end
  elseif dropLive(widget, d) then
    if askEvent then removeEvent(askEvent) end
    askEvent = scheduleEvent(ask, ASK_DELAY)
  end
end

-- the equipment changed: the set block of every cached set piece may be stale (tooltiplogic.lua L.dropSetTips); the
-- hovered piece is asked for again
local function onInventoryChange()
  if L.dropSetTips(cache) == 0 then return end
  if hovered and not hovered.external and not L.cacheGet(cache, hovered.key, now()) then
    if askEvent then removeEvent(askEvent) end
    askEvent = scheduleEvent(ask, ASK_DELAY)
  end
end

local function onTips(data)
  local t = now()
  for _, row in ipairs(type(data.items) == 'table' and data.items or {}) do
    local pk = L.posKey(row.pos, row.iid)
    local p = pending[pk]
    pending[pk] = nil
    -- only the item asked for: an answer for another item (the slots shifted) is dropped, the hover asks again
    if p and type(row.tip) == 'table' then
      if L.tipMatches(p.ident, row.tip) then
        L.cachePut(cache, p.key, row.tip, p.plain, t)
      elseif hovered and not hovered.external and hovered.key == p.key then
        hovered.retries = (hovered.retries or 0) + 1
        if hovered.retries <= RETRIES then
          if askEvent then removeEvent(askEvent) end
          askEvent = scheduleEvent(ask, RETRY_DELAY)
        end
      end
    end
  end
  if hovered and L.cacheGet(cache, hovered.key, t) then
    render()
  end
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' then return end
  if msg.action == 'tips' and type(msg.data) == 'table' then
    onTips(msg.data)
  end
end

local function reset()
  cache = L.newCache()
  pending = {}
  hovered = nil
  clearPanels()
end

function init()
  g_ui.importStyle('item_tooltip')
  handlers.hover = safe('hover', onHoverChange)
  handlers.change = safe('change', onItemChange)
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.reset = safe('reset', reset)
  handlers.inventory = safe('inventory', onInventoryChange)
  connect(UIItem, { onHoverChange = handlers.hover, onItemChange = handlers.change })
  connect(LocalPlayer, { onInventoryChange = handlers.inventory })
  connect(g_game, { onGameEnd = handlers.reset, onGameStart = handlers.reset })
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
end

function terminate()
  disconnect(UIItem, { onHoverChange = handlers.hover, onItemChange = handlers.change })
  disconnect(LocalPlayer, { onInventoryChange = handlers.inventory })
  disconnect(g_game, { onGameEnd = handlers.reset, onGameStart = handlers.reset })
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if askEvent then removeEvent(askEvent) askEvent = nil end
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
  reset()
end
