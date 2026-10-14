-- Ground loot labels: a name plate over every item worth seeing on the ground, in its rarity colour, following the
-- loot filter (game_lootfilter); Alt held shows everything; "Corpse: 2 items" over a corpse you may loot that holds
-- loot the filter cares about; a despawn timer where the server says the thing decays.
-- Server: server/data/scripts/chaos/groundloot.lua, extended opcode 230 (JSON {action, data}).
--   client -> server  look {t = [[x, y, z], ...]}    the tiles whose items changed (at most 30 per message)
--                     tip {p = [x, y, z], s, id}     the rich tooltip of one ground item
--                     raise {p, s, id, c, iid}       put an item lower in a pile on top (then it is moved as usual)
--   server -> client  tiles {t = [{p, i = [rows]}]}   tip {p, s, id, tip | gone}   raised {p, id[, err]}
-- The rules (what gets a label, text, colour, timer, priority, layout) are in groundlabelslogic.lua.
--
-- How it is drawn: the engine has no Lua callback for tile changes, so the tiles in view are scanned on a light timer
-- (and at once when the player moves); only tiles whose item ids or counts changed are asked about. Each labelled tile
-- carries one widget (Tile:setWidget) that the engine draws centred on the tile, every frame, walking included; the
-- labels of a tile are stacked in it and moved up (or down) past the labels of neighbouring tiles. Tile widgets are
-- not part of the UI tree, so clicks and hovering are taken from the map panel and matched to the label rectangles.
-- Left click: pick the item up into the backpack (the normal move: the engine walks there first and checks capacity,
-- room and every move rule; it only moves the top item of a pile, so an item lower down is first put on top by the
-- server, "raise") or open the corpse. Right click: the usual item menu. Hover: the rich tooltip (game_itemtooltip).

local OPCODE = 230
local GL = GroundLabelsLogic

local SCAN_MS = 400        -- tiles in view are compared with what was last seen this often
local MOVE_SCAN_MS = 60    -- and this soon after the player moved
local ALT_POLL_MS = 100
local RETRY_S = 3          -- a tile asked about and not answered is asked again after this long
local MAX_ASK = 30         -- tiles per request (the server's limit)
local SERVER_RANGE_X, SERVER_RANGE_Y = 8, 6
local LIFT = 0.18          -- the block's bottom sits this much of a tile above the tile's centre
local BACKPACK_POS = { x = 65535, y = 3, z = 0 } -- InventorySlotBack: the engine puts the item inside the backpack

local settings = GL.defaults()
local rawCache = {}    -- posKey -> {raw, n, sig}: the last look at a tile in view (ids and counts of all its items)
local lastScanMs = 0
local tiles = {}       -- posKey -> {pos, sig, rows, at, askedSig, askedAt, widget, wid, render}
local labels = {}      -- the drawn labels: {widget = row label, tile, row, d}
local widgetSeq = 0
local altDown = false
local hovered, pressed
local menuLabel -- the label whose item menu is open (its tooltip stays hidden until the pointer leaves it)
local tipCache, tipPending = {}, {}
local filterKey = ''
local window
local events = {}
local handlers = {}
local mapPanel

local reported = {}
local function safe(name, fn)
  return function(...)
    local ok, res = pcall(fn, ...)
    if not ok then
      if not reported[name] then
        reported[name] = true
        g_logger.warning('[groundlabels] ' .. name .. ': ' .. tostring(res))
      end
      return false
    end
    return res
  end
end

local function now()
  return g_clock.seconds()
end

local function send(action, data)
  local protocol = g_game.getProtocolGame()
  if protocol then
    protocol:sendExtendedOpcode(OPCODE, json.encode({ action = action, data = data }))
  end
end

local function filterLogic()
  local lf = modules.game_lootfilter
  return lf and lf.LootFilterLogic or LootFilterLogic
end

local function filterSettings()
  local lf = modules.game_lootfilter
  local s = lf and lf.getSettings and lf.getSettings()
  return type(s) == 'table' and s or filterLogic().defaults()
end

-- ---------------------------------------------------------------- settings
local function loadSettings()
  settings = GL.normalize(g_settings.getNode('groundLabels'))
end

local function saveSettings()
  g_settings.setNode('groundLabels', settings)
end

-- ---------------------------------------------------------------- widgets
local function destroyWidget(t)
  if t.widget then
    if t.tile then
      local w = t.tile:getWidget()
      if w and w:getId() == t.wid then t.tile:removeWidget() end
    end
    if not t.widget:isDestroyed() then t.widget:destroy() end
  end
  t.widget, t.render = nil, nil
end

local function dropTile(key)
  local t = tiles[key]
  if t then
    destroyWidget(t)
    tiles[key] = nil
  end
end

local function clearAll()
  rawCache = {}
  for key in pairs(tiles) do dropTile(key) end
  tiles, labels = {}, {}
  if hovered then
    if modules.game_itemtooltip and modules.game_itemtooltip.hideTip then modules.game_itemtooltip.hideTip() end
    if g_tooltip then g_tooltip.hide() end
  end
  hovered, pressed = nil, nil
end

-- the candidate things of a tile, in tile order: {thing, id, c}
local function candidates(tile)
  local out = {}
  for _, item in ipairs(tile:getItems() or {}) do
    local f = {
      ground = item:isGround(), border = item:isGroundBorder(), bottom = item:isOnBottom(), top = item:isOnTop(),
      pickupable = item:isPickupable(), container = item:isContainer(),
    }
    f.corpse = f.container and (item:isCorpse() or item:isLyingCorpse())
    if GL.isCandidate(f) then
      out[#out + 1] = { thing = item, id = item:getId(), c = item:getCount() }
    end
  end
  return out
end

-- the client item a server row means: same id, then the one whose count, rarity and unique flag (the item custom
-- attributes, game_itemrarity) and stack position agree best (two Fire Swords of different rarity on one tile)
local function attr(item, key)
  if getItemAttribute then return getItemAttribute(item, key) end
  local ok, v = pcall(item.getCustomAttribute, item, key)
  return ok and tonumber(v) or 0
end

local function thingOf(t, row)
  if not t.tile then return nil end
  local A = ChaosItemAttr or { RARITY = 1, UNIQUE = 4 }
  local best, bestScore
  for _, x in ipairs(candidates(t.tile)) do
    if x.id == tonumber(row.id) then
      local score = 0
      if x.c == (tonumber(row.c) or 1) then score = score + 8 end
      if attr(x.thing, A.RARITY) == (tonumber(row.r) or 0) then score = score + 4 end
      if (attr(x.thing, A.UNIQUE) > 0) == (tonumber(row.u) == 1) then score = score + 2 end
      if x.thing:getStackPos() == tonumber(row.s) then score = score + 1 end
      if not bestScore or score > bestScore then best, bestScore = x.thing, score end
    end
  end
  return best
end

-- ---------------------------------------------------------------- layout and drawing
local function tileSize()
  local vd = mapPanel and mapPanel:getVisibleDimension()
  local r = mapPanel and mapPanel:getRect()
  if not vd or not r or vd.width <= 0 or vd.height <= 0 then return 64, 64 end
  local w, h = r.width / vd.width, r.height / vd.height
  if mapPanel:isKeepAspectRatioEnabled() then
    local s = math.min(w, h)
    return s, s
  end
  return w, h
end

local function styleLabel(label, d, color)
  local st = GL.style(d, color) -- the highlight background may be the player's accent cosmetic (setAccent)
  label:setColor(st.text)
  label:setBorderWidth(1)
  label:setBorderColor(st.border)
  label:setBackgroundColor(st.background)
  label:setOpacity(d.dim and 0.7 or 1)
  label.baseBackground = label:getBackgroundColor()
end

local lastLayoutMs = 0
local layout
local function relayout()
  local started = g_clock.millis()
  layout()
  lastLayoutMs = g_clock.millis() - started
end

layout = function()
  labels = {}
  if not g_game.isOnline() or not settings.enabled or not mapPanel then
    for _, t in pairs(tiles) do destroyWidget(t) end
    return
  end
  local L = filterLogic()
  GL.setFilterLogic(L)
  local filter = filterSettings()
  local player = g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  if not ppos then return end
  local t0 = now()
  local entries, order = {}, 0
  for key, t in pairs(tiles) do
    for _, row in ipairs(t.rows or {}) do
      local d = GL.decide(row, settings, filter, altDown)
      if d then
        order = order + 1
        entries[#entries + 1] = { key = key, t = t, row = row, d = d, prio = GL.priority(row, d), order = order,
          dist = math.max(math.abs(t.pos.x - ppos.x), math.abs(t.pos.y - ppos.y)) }
      end
    end
  end
  local chosen = GL.select(entries)
  local size = GL.SIZES[settings.size]
  local tw, th = tileSize()
  -- one block per tile: its rows top to bottom in priority order
  local blocks, blockOrder = {}, {}
  for _, e in ipairs(chosen) do
    local b = blocks[e.key]
    if not b then
      b = { key = e.key, t = e.t, rows = {}, ax = (e.t.pos.x - ppos.x) * tw, ay = (e.t.pos.y - ppos.y) * th, w = 0, h = 0 }
      blocks[e.key] = b
      blockOrder[#blockOrder + 1] = b
    end
    b.rows[#b.rows + 1] = e
  end
  -- measure every row with a scratch label of the chosen font
  local probe = g_ui.createWidget('GroundLabel')
  probe:setFont(size.font)
  for _, b in ipairs(blockOrder) do
    for _, e in ipairs(b.rows) do
      e.text = GL.text(e.row, e.d, settings, t0)
      probe:setText(GL.showTimer(e.row, e.d, settings) and (e.text:gsub('%d', '0')) or e.text) -- timer digits as 0s: no jitter
      local ts = probe:getTextSize()
      e.w, e.h = ts.width + size.pad * 2, ts.height + 2
      b.w = math.max(b.w, e.w)
      b.h = b.h + e.h + (b.h > 0 and 1 or 0)
    end
  end
  probe:destroy()
  local boxes = GL.layout(blockOrder, { gap = 2, lift = math.floor(th * LIFT), maxShift = th * 3 })
  local drawn = {}
  for _, b in ipairs(blockOrder) do
    local t = b.t
    drawn[b.key] = true
    local box = GL.widgetBox(boxes[b.key])
    local sig = {}
    for _, e in ipairs(b.rows) do sig[#sig + 1] = e.text .. '|' .. tostring(e.d.dim) .. tostring(e.d.highlight) end
    local render = table.concat(sig, '\n') .. '@' .. box.w .. 'x' .. box.h .. '+' .. box.cx .. ',' .. box.cy .. settings.size .. (GL.accent or '')
    if t.render ~= render or not t.widget or t.widget:isDestroyed() then
      destroyWidget(t)
      widgetSeq = widgetSeq + 1
      t.wid = 'groundLabels' .. widgetSeq
      local w = g_ui.createWidget('GroundLabelBlock')
      w:setId(t.wid)
      w:resize(box.w, box.h)
      local y = box.cy
      for _, e in ipairs(b.rows) do
        local label = g_ui.createWidget('GroundLabel', w)
        label:setFont(size.font)
        label:setText(e.text)
        label:resize(b.w, e.h)
        label:addAnchor(AnchorTop, 'parent', AnchorTop)
        label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        label:setMarginTop(y)
        label:setMarginLeft(box.cx)
        styleLabel(label, e.d, GL.color(e.row, e.d))
        e.label = label
        y = y + e.h + 1
      end
      t.widget, t.render, t.rowsDrawn = w, render, b.rows
      t.tile:setWidget(w)
    else
      -- same text and place: keep the widget, refresh what the rows point at
      for i, e in ipairs(b.rows) do e.label = t.rowsDrawn[i].label end
      t.rowsDrawn = b.rows
    end
    for _, e in ipairs(b.rows) do
      labels[#labels + 1] = { label = e.label, t = t, row = e.row, d = e.d }
    end
  end
  for key, t in pairs(tiles) do
    if not drawn[key] then destroyWidget(t) end
  end
end

-- timers: only the text changes (the width was measured with zeros)
local function tickTimers()
  if not settings.timers then return end
  local t0 = now()
  for _, l in ipairs(labels) do
    if l.label and not l.label:isDestroyed() and GL.showTimer(l.row, l.d, settings) then
      l.label:setText(GL.text(l.row, l.d, settings, t0))
    end
  end
end

-- ---------------------------------------------------------------- scanning and asking
local function ask(list)
  local batch = {}
  local t0 = now()
  for _, t in ipairs(list) do
    t.askedSig, t.askedAt = t.sig, t0
    batch[#batch + 1] = { t.pos.x, t.pos.y, t.pos.z }
    if #batch >= MAX_ASK then
      send('look', { t = batch })
      batch = {}
    end
  end
  if #batch > 0 then send('look', { t = batch }) end
end

local function scan()
  if not g_game.isOnline() or not settings.enabled or not mapPanel or mapPanel:isDestroyed() then
    if next(tiles) then clearAll() end
    return
  end
  local player = g_game.getLocalPlayer()
  local ppos = player and player:getPosition()
  if not ppos then return end
  local vd = mapPanel:getVisibleDimension()
  local rx = math.min(SERVER_RANGE_X, math.floor((vd and vd.width or 15) / 2))
  local ry = math.min(SERVER_RANGE_Y, math.floor((vd and vd.height or 11) / 2))
  local seen, need, changed = {}, {}, false
  local t0 = now()
  local started = g_clock.millis()
  local cache = {}
  for dy = -ry, ry do
    for dx = -rx, rx do
      local pos = { x = ppos.x + dx, y = ppos.y + dy, z = ppos.z }
      local tile = g_map.getTile(pos)
      if tile and tile:getThingCount() > 1 then
        -- ids and counts of everything on the tile; the candidate test (several engine calls per item) only runs
        -- again when they change
        local key = GL.posKey(pos)
        local items = tile:getItems() or {}
        local parts = {}
        for i, item in ipairs(items) do parts[i] = item:getId() .. 'x' .. item:getCount() end
        local raw = table.concat(parts, ';')
        local c = rawCache[key]
        if not c or c.raw ~= raw then
          local list = candidates(tile)
          c = { raw = raw, n = #list, sig = GL.signature(list) }
        end
        cache[key] = c
        if c.n > 0 then
          seen[key] = true
          local t = tiles[key]
          if not t then
            t = { pos = pos }
            tiles[key] = t
          end
          t.tile = tile
          if t.widget then
            -- the engine rebuilt the tile (the area left the view and came back): the widget went with the old one
            local w = tile:getWidget()
            if not w or w:getId() ~= t.wid then
              if not t.widget:isDestroyed() then t.widget:destroy() end
              t.widget, t.render = nil, nil
              changed = true
            end
          end
          local sig = c.sig
          if t.sig ~= sig then
            t.sig = sig
            if t.rows then t.rows = nil changed = true end
          end
          if not t.rows and (t.askedSig ~= sig or t0 - (t.askedAt or 0) >= RETRY_S) then
            need[#need + 1] = t
          end
        end
      end
    end
  end
  rawCache = cache
  lastScanMs = g_clock.millis() - started
  for key in pairs(tiles) do
    if not seen[key] then
      dropTile(key)
      changed = true
    end
  end
  if #need > 0 then ask(need) end
  local fk = GL.filterKey(filterSettings())
  if fk ~= filterKey then
    filterKey = fk
    changed = true
  end
  if changed then relayout() end
end

local function scheduleScan(delay)
  if events.scanSoon then return end
  events.scanSoon = scheduleEvent(function()
    events.scanSoon = nil
    scan()
  end, delay or MOVE_SCAN_MS)
end

local function onTiles(data)
  local t0 = now()
  local changed = false
  local entries = {} -- the tile answers; an entry that is no table is left out
  for _, e in ipairs(type(data.t) == 'table' and data.t or {}) do
    if type(e) == 'table' then entries[#entries + 1] = e end
  end
  for _, entry in ipairs(entries) do
    local p = type(entry.p) == 'table' and entry.p or {}
    local pos = { x = tonumber(p[1]) or -1, y = tonumber(p[2]) or -1, z = tonumber(p[3]) or -1 }
    local t = tiles[GL.posKey(pos)]
    -- an answer for a tile that changed again in between is dropped: the newer question is on its way
    if t and t.askedSig == t.sig then
      local rows = {}
      for _, row in ipairs(type(entry.i) == 'table' and entry.i or {}) do
        if type(row) == 'table' then
          row.at = t0
          rows[#rows + 1] = row
        end
      end
      t.rows = rows
      changed = true
    end
  end
  if changed then relayout() end
end

-- ---------------------------------------------------------------- mouse
local function labelAt(pos)
  for i = #labels, 1, -1 do
    local l = labels[i]
    if l.label and not l.label:isDestroyed() and l.label:containsPoint(pos) then return l end
  end
  return nil
end

local function tipKey(l)
  return 'gl:' .. GL.posKey(l.t.pos) .. ':' .. tostring(l.row.s) .. ':' .. tostring(l.row.id) .. ':' .. tostring(l.row.c)
end

local function showHoverTip(l)
  if l.d.kind == 'corpse' then
    if g_tooltip and g_tooltip.displayText then g_tooltip.displayText(GL.corpseTooltip(l.row)) end
    return
  end
  local key = tipKey(l)
  local tip = tipCache[key]
  if tip and modules.game_itemtooltip and modules.game_itemtooltip.showTip then
    modules.game_itemtooltip.showTip(l.label, key, tip)
  elseif not tipPending[key] or now() - tipPending[key] > RETRY_S then
    tipPending[key] = now()
    send('tip', { p = { l.t.pos.x, l.t.pos.y, l.t.pos.z }, s = l.row.s, id = l.row.id })
  end
end

local function setHover(l)
  if hovered == l then return end
  if hovered then
    local old = hovered
    if old.label and not old.label:isDestroyed() then
      old.label:setBackgroundColor(old.label.baseBackground or '#0c0a0cd8')
    end
    if modules.game_itemtooltip and modules.game_itemtooltip.hideTip then modules.game_itemtooltip.hideTip(old.label) end
    if g_tooltip then g_tooltip.hide() end
  end
  hovered = l
  if l then
    l.label:setBackgroundColor('#3a2a1cf0')
    showHoverTip(l)
  end
end

local function onTip(data)
  local p = type(data.p) == 'table' and data.p or {}
  for key in pairs(tipPending) do
    if key:find('^gl:' .. (tonumber(p[1]) or -1) .. ',' .. (tonumber(p[2]) or -1) .. ',' .. (tonumber(p[3]) or -1) .. ':' .. (tonumber(data.s) or -1) .. ':') then
      tipPending[key] = nil
      if type(data.tip) == 'table' then tipCache[key] = data.tip end
    end
  end
  if hovered and hovered.d.kind ~= 'corpse' and tipCache[tipKey(hovered)] then
    modules.game_itemtooltip.showTip(hovered.label, tipKey(hovered), tipCache[tipKey(hovered)])
  end
end

local function message(text)
  if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
    modules.game_textmessage.displayFailureMessage(text)
  end
end

-- the top of a pile: the engine only ever moves that one (the candidate with the lowest stack position)
local function topOf(t)
  local top
  for _, x in ipairs(candidates(t.tile)) do
    if not top or x.thing:getStackPos() < top:getStackPos() then top = x.thing end
  end
  return top
end

local pendingPick -- {key, row, at}: asked the server to put this item on top of its pile

local function pickUp(thing)
  local player = g_game.getLocalPlayer()
  if not player or not player:getInventoryItem(BACKPACK_POS.y) then
    message('You have no backpack to put it in.')
    return
  end
  g_game.move(thing, BACKPACK_POS, thing:getCount()) -- the engine walks there first when it is not next to you
end

local RAISE_ERRORS = {
  far = 'That item is too far away.',
  sight = 'You cannot reach that item from here.',
  gone = 'That item is gone.',
  fixed = 'You cannot pick that up.',
}

local function onRaised(data)
  local p = type(data.p) == 'table' and data.p or {}
  local key = GL.posKey({ x = tonumber(p[1]) or -1, y = tonumber(p[2]) or -1, z = tonumber(p[3]) or -1 })
  local pick = pendingPick
  if not pick or pick.key ~= key or now() - pick.at > RETRY_S then return end
  pendingPick = nil
  if data.err then
    message(RAISE_ERRORS[data.err] or RAISE_ERRORS.gone)
    return
  end
  local t = tiles[key]
  local thing = t and thingOf(t, pick.row)
  local top = t and topOf(t)
  if thing and top and top:getStackPos() == thing:getStackPos() then
    pickUp(thing)
  else
    message(RAISE_ERRORS.gone)
  end
end

local function activate(l, mousePos, button)
  local thing = thingOf(l.t, l.row)
  if not thing then
    message('That item is gone.')
    scheduleScan(0)
    return
  end
  if button == MouseRightButton then
    setHover(nil) -- the menu opens where the tooltip was
    menuLabel = l.label
    if modules.game_interface and modules.game_interface.createThingMenu then
      modules.game_interface.createThingMenu(l.t.tile, mousePos, thing, thing, nil)
    end
    return
  end
  if l.d.kind == 'corpse' then
    g_game.open(thing) -- the engine walks there first and checks the corpse owner
    return
  end
  local top = topOf(l.t)
  if top and top:getStackPos() == thing:getStackPos() then
    pickUp(thing)
    return
  end
  -- lower in a pile: the server puts it on top first (the engine only moves the top item), then it is moved as usual
  local A = ChaosItemAttr or { ID = 6 }
  pendingPick = { key = GL.posKey(l.t.pos), row = l.row, at = now() }
  send('raise', { p = { l.t.pos.x, l.t.pos.y, l.t.pos.z }, s = l.row.s, id = l.row.id, c = l.row.c,
    iid = string.format('%.0f', attr(thing, A.ID)) })
end

local function onMousePress(widget, mousePos, button)
  local l = labelAt(mousePos)
  if not l or (button ~= MouseLeftButton and button ~= MouseRightButton) then
    pressed = nil
    return false
  end
  pressed = { l = l, button = button }
  return true
end

local function onMouseRelease(widget, mousePos, button)
  if not pressed then return false end
  local p = pressed
  pressed = nil
  local l = labelAt(mousePos)
  if l and l.label == p.l.label and button == p.button then
    activate(l, mousePos, button)
  end
  return true
end

local function onMouseMove(widget, mousePos)
  local l = labelAt(mousePos)
  if l and l.label == menuLabel then return false end -- no tooltip over the menu just opened from this label
  menuLabel = nil
  setHover(l)
  return false
end

-- ---------------------------------------------------------------- loop
local function pollAlt()
  local down = g_keyboard.isAltPressed()
  if down ~= altDown then
    altDown = down
    relayout()
  end
end

local function stopLoops()
  for k, e in pairs(events) do
    removeEvent(e)
    events[k] = nil
  end
end

local function startLoops()
  stopLoops()
  if not settings.enabled then return end
  events.scan = cycleEvent(handlers.scan, SCAN_MS)
  events.alt = cycleEvent(handlers.alt, ALT_POLL_MS)
  events.timer = cycleEvent(handlers.timer, 1000)
end

local function onGameStart()
  mapPanel = modules.game_interface.getMapPanel()
  clearAll()
  tipCache, tipPending = {}, {}
end

local function onGameEnd()
  clearAll()
  tipCache, tipPending = {}, {}
end

local function onPositionChange()
  scheduleScan(MOVE_SCAN_MS)
end

local function onExtendedOpcode(protocol, opcode, buffer)
  local ok, msg = pcall(json.decode, buffer)
  if not ok or type(msg) ~= 'table' or type(msg.data) ~= 'table' then return end
  if msg.action == 'tiles' then onTiles(msg.data)
  elseif msg.action == 'tip' then onTip(msg.data)
  elseif msg.action == 'raised' then onRaised(msg.data)
  end
end

-- ---------------------------------------------------------------- settings window
local updatingUi = false

local function refreshWindow()
  if not window then return end
  updatingUi = true
  for _, k in ipairs({ 'enabled', 'rarePlus', 'altAll', 'corpses', 'timers' }) do
    window[k]:setChecked(settings[k])
  end
  local combo = window.sizeCombo
  combo:clearOptions()
  for _, k in ipairs(GL.SIZE_ORDER) do combo:addOption(tr(k:sub(1, 1):upper() .. k:sub(2)), k) end
  for i, k in ipairs(GL.SIZE_ORDER) do
    if k == settings.size then combo:setCurrentIndex(i) end
  end
  updatingUi = false
end

local function onUiChange()
  if updatingUi or not window then return end
  for _, k in ipairs({ 'enabled', 'rarePlus', 'altAll', 'corpses', 'timers' }) do
    settings[k] = window[k]:isChecked()
  end
  local opt = window.sizeCombo:getCurrentOption()
  settings.size = opt and GL.SIZES[opt.data] and opt.data or settings.size
  saveSettings()
  startLoops()
  for _, t in pairs(tiles) do t.render = nil end
  if settings.enabled and g_game.isOnline() then
    scan()
    relayout()
  else
    clearAll()
  end
end

function showSettings()
  if not window then return end
  refreshWindow()
  window:show()
  window:raise()
  window:focus()
end

function hideSettings()
  if window then window:hide() end
end

function toggleSettings()
  if window and window:isVisible() then hideSettings() else showSettings() end
end

-- for other modules and tests: the labels on screen {text, pos, kind}
-- the loot label accent cosmetic (game_cosmetics): nil = the default background; labels are redrawn
function setAccent(color)
  local before = GL.accent
  GL.setAccent(color)
  if GL.accent ~= before and g_game.isOnline() then relayout() end
end

function getLabels()
  local out = {}
  for _, l in ipairs(labels) do
    out[#out + 1] = { text = l.label and not l.label:isDestroyed() and l.label:getText() or '', pos = l.t.pos,
      kind = l.d.kind, dim = l.d.dim, highlight = l.d.highlight, rect = l.label and l.label:getRect() }
  end
  return out
end

-- counts for the terminal: tiles watched, tiles answered, rows, labels drawn
function getStats()
  local n, answered, rows = 0, 0, 0
  for _, t in pairs(tiles) do
    n = n + 1
    if t.rows then
      answered = answered + 1
      rows = rows + #t.rows
    end
  end
  return { tiles = n, answered = answered, rows = rows, labels = #labels, alt = altDown, enabled = settings.enabled,
    running = events.scan ~= nil, map = mapPanel ~= nil, scanMs = lastScanMs,
    layoutMs = lastLayoutMs }
end

function init()
  g_ui.importStyle('groundlabels')
  loadSettings()
  handlers.scan = safe('scan', scan)
  handlers.alt = safe('alt', pollAlt)
  handlers.timer = safe('timer', tickTimers)
  handlers.opcode = safe('opcode', onExtendedOpcode)
  handlers.game = { onGameStart = safe('start', onGameStart), onGameEnd = safe('end', onGameEnd) }
  handlers.player = { onPositionChange = safe('move', onPositionChange) }
  handlers.map = { onMousePress = safe('press', onMousePress), onMouseRelease = safe('release', onMouseRelease),
    onMouseMove = safe('hover', onMouseMove) }
  local ok, ui = pcall(g_ui.createWidget, 'GroundLabelsWindow', rootWidget)
  if ok and ui then
    window = ui
    window:hide()
    for _, k in ipairs({ 'enabled', 'rarePlus', 'altAll', 'corpses', 'timers' }) do
      window[k].onCheckChange = safe('ui', onUiChange)
    end
    window.sizeCombo.onOptionChange = safe('ui', onUiChange)
  else
    g_logger.warning('[groundlabels] settings window not loaded: ' .. tostring(ui))
  end
  mapPanel = modules.game_interface.getMapPanel()
  if mapPanel then connect(mapPanel, handlers.map, true) end
  ProtocolGame.registerExtendedOpcode(OPCODE, handlers.opcode)
  connect(g_game, handlers.game)
  connect(LocalPlayer, handlers.player)
  -- the loops run from the start (offline they only check g_game.isOnline()): the game start signal is not a
  -- reliable trigger here, an earlier handler that throws stops the engine's loop over the handlers
  startLoops()
end

function terminate()
  stopLoops()
  clearAll()
  if mapPanel then disconnect(mapPanel, handlers.map) end
  disconnect(g_game, handlers.game)
  disconnect(LocalPlayer, handlers.player)
  pcall(ProtocolGame.unregisterExtendedOpcode, OPCODE)
  if window then window:destroy() window = nil end
  handlers = {}
end
