-- Rich item tooltips (server-driven). Hovering an item in the inventory or an open container asks the server
-- (extended opcode 242, server/data/scripts/chaos/item_tooltip.lua) for its tooltip: name, rarity, item level, base
-- stats, every modifier with its tier and roll range, sockets and gems, unique and set (the pieces worn and the bonuses
-- active; the cached set pieces are dropped when the equipment changes), requirements. Holding Ctrl
-- shows the equipped item(s) worn the same way next to it, and the hovered tooltip lists the differences per stat
-- (green better, red worse). Holding Alt adds a plain line on what each term does (itemhelp.lua, O372); without Alt a
-- hint line says so.
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

local PAD_X, LINE_GAP = 16, 1
local CARD_W = 320 -- the card is this wide (phone: the 960x540 interface keeps it readable)
local HELP_WRAP = 46 -- characters per Alt help line (itemhelp.lua)
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
local helpShown = false -- the plate on screen has the Alt help lines (itemhelp.lua)
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

-- Alt held now (the shared helper of client_chaos_theme althelp.lua; this module polls it with Ctrl)
local function altPressed()
  local A = rawget(_G, 'ChaosAltHelp')
  return A ~= nil and A.pressed()
end

local function altHint()
  local A = rawget(_G, 'ChaosAltHelp')
  return A and A.hint(tr) or tr('Hold Alt for what each line does.')
end

-- ---------------------------------------------------------------- panels
local function clearPanels()
  for _, p in ipairs(panels) do
    if not p:isDestroyed() then p:destroy() end
  end
  panels = {}
end

-- every engine call that may be missing on an older client runs here
local function try(fn, ...)
  local ok, a = pcall(fn, ...)
  if ok then return a end
  return nil
end

-- a measuring label per style (hidden); the pixel width of a text in that style
local meters = {}
local function textWidth(style, text)
  local m = meters[style]
  if not m or m:isDestroyed() then
    m = try(g_ui.createWidget, style, rootWidget)
    if m then try(m.hide, m) end
    meters[style] = m
  end
  if m then
    local w = try(function() m:setText(text) return m:getTextSize().width end)
    if w then return w end
  end
  return #text * (style == 'ItemTooltipTitle' and 10 or 6)
end

local function destroyMeters()
  for _, m in pairs(meters) do
    if m and not m:isDestroyed() then m:destroy() end
  end
  meters = {}
end

-- a label at x of its parent (absolute: the card has a fixed width); returns its size
local function putLabel(parent, style, y, x, text, color, parts)
  local label = g_ui.createWidget(style, parent)
  if parts and label.setColoredText then
    label:setColoredText(parts)
  else
    label:setText(text)
    label:setColor(color or C.text)
  end
  label:addAnchor(AnchorTop, 'parent', AnchorTop)
  label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  label:setMarginTop(y)
  local size = label:getTextSize()
  label:resize(size.width, size.height)
  local left = type(x) == 'function' and x(size.width) or x
  label:setMarginLeft(left)
  return size, label
end

-- centred in a box of width w (the card or a tile)
local function centred(w)
  return function(width) return math.max(0, math.floor((w - width) / 2)) end
end

local function partsText(parts)
  local t = {}
  for i = 1, #parts, 2 do t[#t + 1] = parts[i] end
  return table.concat(t)
end

local function color(c)
  return c or C.text
end

-- the pieces of one card, each returns the y below it
local function divider(panel, y)
  local rule = g_ui.createWidget('ItemTooltipRule', panel)
  rule:addAnchor(AnchorTop, 'parent', AnchorTop)
  rule:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  rule:addAnchor(AnchorRight, 'parent', AnchorRight)
  rule:setMarginTop(y + 5)
  rule:setMarginLeft(PAD_X)
  rule:setMarginRight(PAD_X)
  local d = g_ui.createWidget('ItemTooltipDiamond', panel)
  d:addAnchor(AnchorTop, 'parent', AnchorTop)
  d:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  d:setMarginTop(y)
  d:setMarginLeft(math.floor((CARD_W - 11) / 2))
  return y + 14
end

local function caption(panel, y, text, col)
  local size = putLabel(panel, 'ItemTooltipCap', y, centred(CARD_W), text, col or '#7a6240')
  return y + size.height + 3
end

local function centredRow(panel, y, row)
  local size = putLabel(panel, 'ItemTooltipLine', y, centred(CARD_W), row.text, row.color, row.parts)
  return y + size.height + LINE_GAP
end

local function statTiles(panel, y, tiles)
  local n = #tiles
  local gap = 6
  local tw = math.floor((CARD_W - 2 * PAD_X - (n - 1) * gap) / n)
  for i, t in ipairs(tiles) do
    local tile = g_ui.createWidget('ItemTooltipTile', panel)
    tile:addAnchor(AnchorTop, 'parent', AnchorTop)
    tile:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    tile:setMarginTop(y)
    tile:setMarginLeft(PAD_X + (i - 1) * (tw + gap))
    tile:resize(tw, 38)
    if t.hero then
      try(tile.setBorderColor, tile, '#8a5a1e')
      try(tile.setBackgroundColor, tile, '#241a0e')
    end
    putLabel(tile, 'ItemTooltipCap', 5, centred(tw), L.caps(t.caption))
    putLabel(tile, 'ItemTooltipLine', 19, centred(tw), t.value, t.hero and C.gold or '#f2e6cc')
  end
  return y + 38 + 5
end

-- the highlighted main effect of a rune: one wide tile with the text wrapped inside it
local function effectTile(panel, y, effect)
  local w = CARD_W - 2 * PAD_X
  local lines = L.wrapPx(effect.text, w - 16, function(t) return textWidth('ItemTooltipLine', t) end)
  local h = 12 + #lines * 14
  local tile = g_ui.createWidget('ItemTooltipTile', panel)
  tile:addAnchor(AnchorTop, 'parent', AnchorTop)
  tile:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  tile:setMarginTop(y)
  tile:setMarginLeft(PAD_X)
  tile:resize(w, h)
  try(tile.setBorderColor, tile, '#8a5a1e')
  try(tile.setBackgroundColor, tile, '#241a0e')
  for i, line in ipairs(lines) do
    putLabel(tile, 'ItemTooltipLine', 6 + (i - 1) * 14, centred(w), line, effect.color)
  end
  return y + h + 5
end

-- the gem block of a gem item (tooltiplogic.lua L.gemBlock, O479): one framed box, a header, then a row per place: the place
-- label left in its own colour, the effect texts in one column (the left edge of the widest label + a gap); a pair effect
-- continues on a row without a label. The labels and the effect texts are plain (the tooltip fonts have no bold).
local function gemBox(panel, y, g)
  local w = CARD_W - 2 * PAD_X
  local labelW = 0
  for _, row in ipairs(g.rows) do
    if row.label ~= '' then labelW = math.max(labelW, textWidth('ItemTooltipLine', row.label)) end
  end
  local x = 8
  local col = x + labelW + 8
  local h = 6 + 12 + #g.rows * 14 + 6
  local box = g_ui.createWidget('ItemTooltipTile', panel)
  box:addAnchor(AnchorTop, 'parent', AnchorTop)
  box:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  box:setMarginTop(y)
  box:setMarginLeft(PAD_X)
  box:resize(w, h)
  putLabel(box, 'ItemTooltipCap', 5, x, g.head, g.headColor)
  for i, row in ipairs(g.rows) do
    local ry = 6 + 12 + (i - 1) * 14
    if row.label ~= '' then putLabel(box, 'ItemTooltipLine', ry, x, row.label, row.labelColor) end
    putLabel(box, 'ItemTooltipLine', ry, col, row.text, row.color, row.parts)
  end
  return y + h + 5
end

local function modRow(panel, y, row)
  local textX = PAD_X + 32
  local rangeW = row.range and (textWidth('ItemTooltipCap', row.range) + 4) or 0
  local maxw = CARD_W - PAD_X - textX - rangeW - 4
  local lines = L.wrapPx(row.text, maxw, function(t) return textWidth('ItemTooltipLine', t) end)
  if #lines == 0 then lines = { '' } end
  if row.tag then
    local tag = g_ui.createWidget('ItemTooltipTag', panel)
    tag:addAnchor(AnchorTop, 'parent', AnchorTop)
    tag:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    tag:setMarginTop(y)
    tag:setMarginLeft(PAD_X)
    tag:setText(row.tag)
    if row.top then
      try(tag.setColor, tag, C.quality)
      try(tag.setBorderColor, tag, '#3f9a5a')
      try(tag.setBackgroundColor, tag, '#12301c')
    elseif row.tagColor then
      try(tag.setColor, tag, row.tagColor)
    end
  end
  local h = 0
  for i, line in ipairs(lines) do
    local parts
    if row.parts and i == #lines then parts = { line, row.parts[2], row.parts[3], row.parts[4] } end
    local size = putLabel(panel, 'ItemTooltipLine', y + h + 1, textX, line, row.color, parts)
    h = h + math.max(size.height, 13)
  end
  if row.range then
    putLabel(panel, 'ItemTooltipCap', y + 3, function(w) return CARD_W - PAD_X - w end, row.range, '#7a7060')
  end
  return y + math.max(16, h + 2) + 2
end

local function groupRows(panel, y, groups)
  for gi, g in ipairs(groups) do
    if gi > 1 then y = y + 3 end
    if g.kind == 'gembox' then
      y = gemBox(panel, y, g)
    else
      if g.caption then y = caption(panel, y, g.caption, g.capColor) end
      for _, row in ipairs(g.rows) do
        y = row.kind == 'mod' and modRow(panel, y, row) or centredRow(panel, y, row)
      end
    end
  end
  return y
end

local function chipRows(panel, y, chips)
  local widths = {}
  for i, c in ipairs(chips) do widths[i] = textWidth('ItemTooltipCap', c.text) + 16 end
  local gap = 5
  for _, row in ipairs(L.chipRows(widths, gap, CARD_W - 2 * PAD_X)) do
    local total = -gap
    for _, i in ipairs(row) do total = total + widths[i] + gap end
    local x = math.floor((CARD_W - total) / 2)
    for _, i in ipairs(row) do
      local chip = g_ui.createWidget('ItemTooltipChip', panel)
      chip:addAnchor(AnchorTop, 'parent', AnchorTop)
      chip:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      chip:setMarginTop(y)
      chip:setMarginLeft(x)
      chip:setText(chips[i].text)
      chip:setColor(color(chips[i].color))
      chip:resize(widths[i], 17)
      if chips[i].low then try(chip.setBorderColor, chip, '#7a2a1a') end
      x = x + widths[i] + gap
    end
    y = y + 17 + 4
  end
  return y
end

-- one card: icon, name, kind, level, the blocks, then the extra rows (the differences, hints, Alt help); returns the panel
local function buildPanel(tip, extra, heading)
  local panel = g_ui.createWidget('ItemTooltipPanel', rootWidget)
  local player = g_game.getLocalPlayer()
  local card = L.card(tip, { level = player and player:getLevel() or 0 })
  local rarity = card.titleColor
  try(function() panel:getChildById('glow'):setImageColor(rarity) end)
  try(function() panel:getChildById('ring'):setImageColor(rarity) end)
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

  -- head: name (wrapped to the card), kind, item level, flags
  local y = 14 + 52 + 8
  local nameLines = L.wrapPx(card.title, CARD_W - 2 * PAD_X, function(t) return textWidth('ItemTooltipTitle', t) end)
  if #nameLines == 0 then nameLines = { '' } end
  for i = 1, math.min(#nameLines, 3) do
    local size = putLabel(panel, 'ItemTooltipTitle', y, centred(CARD_W), nameLines[i], card.titleColor)
    y = y + size.height
  end
  y = y + 2
  if card.kind then
    local size = putLabel(panel, 'ItemTooltipKind', y, centred(CARD_W), card.kind, card.kindColor)
    y = y + size.height
  end
  if card.slotLine then y = centredRow(panel, y, { text = card.slotLine, color = C.dim }) end
  if card.level then y = centredRow(panel, y, { text = card.level, color = C.dim }) end
  for _, f in ipairs(card.flags) do y = centredRow(panel, y, f) end

  -- blocks, a divider before each
  if card.stats then
    y = divider(panel, y + 4)
    if #card.stats.tiles > 0 then y = statTiles(panel, y, card.stats.tiles) end
    if card.stats.effect then y = effectTile(panel, y, card.stats.effect) end
    for _, parts in ipairs(card.stats.extra) do
      y = centredRow(panel, y, { text = partsText(parts), color = C.text, parts = parts })
    end
  end
  if card.mods then
    y = divider(panel, y + 2)
    y = groupRows(panel, y, card.mods)
  end
  if card.extras then
    y = divider(panel, y + 2)
    y = groupRows(panel, y, card.extras)
  end
  if #card.chips > 0 or #card.foot > 0 or card.fitChips then
    y = divider(panel, y + 2)
    if card.fitChips then
      y = caption(panel, y, card.fitCaption)
      y = chipRows(panel, y, card.fitChips)
    end
    y = chipRows(panel, y, card.chips)
    for _, row in ipairs(card.foot) do y = centredRow(panel, y, row) end
  end
  -- extra rows: the differences of the Ctrl compare, the hints, the Alt help
  for _, row in ipairs(extra or {}) do
    if row.sep then y = divider(panel, y + 2) end
    local text = row.text
    if textWidth('ItemTooltipLine', text) > CARD_W - 2 * PAD_X then
      for _, part in ipairs(L.wrapPx(text, CARD_W - 2 * PAD_X, function(t) return textWidth('ItemTooltipLine', t) end)) do
        y = centredRow(panel, y, { text = part, color = row.color })
      end
    else
      y = centredRow(panel, y, row)
    end
  end
  panel:resize(CARD_W, y + 12)
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
  local comparable = L.comparable(tip) -- wearable gear with numbers only: no Ctrl hint on runes, potions, gems, materials
  local wantCompare = g_keyboard.isCtrlPressed() and comparable
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
  elseif comparable then
    extra[#extra + 1] = { text = tr('Hold Ctrl to compare'), color = C.dim, sep = true }
  end
  -- Alt (O372, itemhelp.lua): a plain line on what each term of the item does; without Alt a hint line
  local wantHelp = altPressed()
  local help = ItemTooltipHelp.lines(tip, tr)
  if #help > 0 then
    if wantHelp then
      for i, line in ipairs(help) do
        for j, part in ipairs(L.wrap(line, HELP_WRAP)) do
          extra[#extra + 1] = { text = part, color = C.help, sep = i == 1 and j == 1 }
        end
      end
    else
      extra[#extra + 1] = { text = altHint(), color = C.dim, sep = not (comparable and not wantCompare) }
    end
  end
  compareShown = wantCompare
  helpShown = wantHelp
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
  if #panels > 0 and (ctrl ~= compareShown or altPressed() ~= helpShown) then
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
  destroyMeters()
  if askEvent then removeEvent(askEvent) askEvent = nil end
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
  reset()
end

-- the Codex page of an item the player has hovered (O467; game_codex asks it for the right-click entry Open in Codex): the
-- id the server put in the tip of a unique or set piece (tip.codex, L.codexId), nil for any other item or one whose tip
-- is not here yet
function codexIdOf(item)
  if not item then return nil end
  local ok, d = pcall(describe, item)
  if not ok or not d then return nil end
  return L.codexId(L.cacheGet(cache, d.key, now()))
end
