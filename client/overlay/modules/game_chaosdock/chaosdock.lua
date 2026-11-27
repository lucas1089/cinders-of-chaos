-- game_chaosdock (O732, owner 2026-11-23: option A of the UI mockups, "mantenha a barra de skills embaixo com os orbs ao
-- lado", "mantenha tudo na skin principal do jogo"). A panel in the right column of the game screen with icon tabs on top:
-- Equip., Quests, Attributes, Spells, Shop (chaosdocklogic.lua L.TABS). A tab hosts the windows that already exist: the
-- dock opens the window through its menu entry (ChaosTopBar.runRaw), takes it out of its parent and puts it in its
-- content area; closing the dock, another tab or logout gives it back where it was, open or closed as before.
-- O755 (owner 2026-11-24): "deixe ele bem menor, do tamanho de 1 coluna mesmo, como a bp fica hoje"; "esconda a janela
-- inteira da bp, o dock vai ser o principal agora; quando ele estiver fechado, so apareca o mapa".
--  * The dock is exactly one right panel column wide (the column the Inventory panel had), under the minimap, for every
--    window. It never widens. A two pane window stacks its panes in the column (chaosdockcolumn.lua) and the dock scrolls
--    it when it is taller than the room; Market and Store (wide grids, fit 'float') open on their own, centred in the
--    game left of the dock, while the dock stays open on their tab.
--  * While the dock is enabled the right column shows only the minimap: every other window there hides (the Inventory
--    panel too: it is the Equip. tab now). Turning the dock off gives them back.
--  * The open state, the tab and the window of each tab are kept per character (settings chaosDockOpen_NAME,
--    chaosDockTab_NAME, chaosDockSubs_NAME); a dock open at the logout opens again at the next entry.
--  * The hub menu (client_chaos_topbar, O550): an entry of a tab (a card, the text menu, its hotkey) opens the dock on
--    that tab (ChaosDock.route); every other entry opens its window as before. A bag click (game_bagpanel) opens Equip.
--  * Keys: Alt+D shows or hides the dock, Alt+I / Alt+Q / Alt+A open Equip. / Quests / Attributes; Spells and Shop
--    open with the entry keys Alt+S (Spellbook) and Alt+E (Market). Layout options > "Side panel with tabs" turns the
--    dock off (setting chaosDockEnabled): the old floating windows and the right column come back.
--  * The hotbar and its globes (game_hotbar, game_shaderfx) stay at the bottom centre: the dock stops above the hotbar
--    when the two would meet. A phone gets the dock as a sheet over the whole screen.
-- The skin is client_chaos_theme's (window frame, tab buttons, ChaosCloseX) and the glyphs of the hub menu.
ChaosDock = ChaosDock or {}
local M = ChaosDock
local L = ChaosDockLogic
local COL = ChaosDockColumn

local GLYPHS = '/modules/client_chaos_topbar/images/glyphs_bar'
local POLL_MS, POLL_TRIES = 120, 12
local TICK_MS = 1000
local COLUMN_MS = 700
local SLIDE_MS = 25
local CHROME = { 'closeButton', 'minimizeButton', 'lockButton', 'closeX' }
local WINDOW_CLASSES = { UIWindow = true, UIMiniWindow = true }

local panel
local st
local held = {}          -- records of the windows in the dock: widget, home, index, wasVisible, spec, size, pos, ...
local known = {}         -- menu entry -> the widget it opened last (a module that keeps a local window)
local tabButtons = {}
local floated            -- a window too wide for the column, opened on its own: { widget, opened = the dock opened it }
local coverNotified = 0  -- the width last told to the toasts (game_chaosnotify)
local slideEvent, tickEvent, pollEvent, columnEvent, reopenEvent
local boundKeys = {}
local releasing = false
local lastKey = 0
local columnHidden = {}  -- the right column's windows the dock hid: { widget, key }
local startedAt = 0

-- ---------------------------------------------------------------- helpers
local function alive(w)
  if not w then return false end
  local ok, destroyed = pcall(function() return w:isDestroyed() end)
  return ok and not destroyed
end

local function keyOf(w)
  local k = w.chaosDockKey
  if not k then
    lastKey = lastKey + 1
    k = lastKey
    w.chaosDockKey = k
  end
  return k
end

local function same(a, b) return alive(a) and alive(b) and keyOf(a) == keyOf(b) end

local function isPhone()
  return g_app.isMobile and g_app.isMobile() or false
end

local function now()
  local ok, t = pcall(function() return g_clock.millis() end)
  return ok and t or 0
end

local function charName()
  local ok, name = pcall(function()
    if g_game.isOnline() and g_game.getCharacterName then return g_game.getCharacterName() end
  end)
  return ok and name and name ~= '' and name or nil
end

local function read(key)
  local ok, v = pcall(g_settings.getString, key)
  if ok and v ~= nil and v ~= '' then return v end
  return nil
end

-- the dock's own settings go under the character's keys (O755); chaosDockEnabled stays one for the client
local function write(values)
  local name = charName()
  for k, v in pairs(values or {}) do
    local key = k == L.SETTING_ENABLED and k or L.charKey(k, name)
    pcall(g_settings.set, key, v)
  end
end

local function gameRoot()
  local gi = modules.game_interface
  return gi and gi.getRootPanel and gi.getRootPanel() or nil
end

local function topbar()
  local m = modules.client_chaos_topbar
  return m and rawget(m, 'ChaosTopBar') or nil
end

local function palette(name, fallback)
  local theme = rawget(_G, 'ChaosTheme')
  return theme and theme.palette and theme.palette[name] or fallback
end

-- a part of the dock: its own children and the content's (scroller, scrollBar). Never a recursive search: a hosted window
-- has its own 'scrollBar', 'note' or 'title' deeper down (seen in a client: the Quest Log's bar was toggled instead)
local function child(id)
  if not panel then return nil end
  local w = panel:getChildById(id)
  if w then return w end
  local content = panel:getChildById('content')
  return content and content:getChildById(id) or nil
end

-- ---------------------------------------------------------------- the right column (O755)
local function rightPanels()
  local root = gameRoot()
  local rp = root and root:getChildById('gameRightPanels')
  return alive(rp) and rp or nil
end

-- the right panel column the dock covers: the rightmost side panel of the right (game_interface.getRightPanel)
local function columnRect()
  local rp = rightPanels()
  if not rp then return nil end
  local best
  for _, p in ipairs(rp:getChildren()) do
    if p:isVisible() and p:getWidth() >= 40 then
      local r = p:getRect()
      if not best or r.x > best.x then best = r end
    end
  end
  return best
end

-- the windows of the right column: { widget } of each side panel's children
local function columnWindows()
  local out = {}
  local rp = rightPanels()
  for _, p in ipairs(rp and rp:getChildren() or {}) do
    for _, w in ipairs(p:getChildren()) do
      local class = w.getClassName and w:getClassName() or ''
      if WINDOW_CLASSES[class] then out[#out + 1] = w end
    end
  end
  return out
end

-- the minimap when the right column shows it: the dock starts under it
local function mapRect()
  for _, w in ipairs(columnWindows()) do
    if tostring(w:getId()):find(L.MINIMAP, 1, true) and w:isVisible() then return w:getRect() end
  end
  return nil
end

-- the right column shows only the minimap while the dock is enabled: every other window there hides (and comes back
-- when the dock is turned off)
local function keepColumn()
  if not st or not st.enabled or isPhone() or not g_game.isOnline() then return end
  local heldIds = {}
  for _, rec in ipairs(held) do
    if alive(rec.widget) then heldIds[tostring(rec.widget:getId())] = true end
  end
  for _, w in ipairs(columnWindows()) do
    if w:isVisible() and L.hidesInColumn(w:getId(), heldIds) then
      local seen = false
      for _, h in ipairs(columnHidden) do
        if same(h.widget, w) then seen = true break end
      end
      if not seen then columnHidden[#columnHidden + 1] = { widget = w } end
      pcall(w.hide, w)
    end
  end
end

-- a window keepColumn hid in the right column: it is open, only the column hides it. The dock takes it as an open one
-- and leaves its menu entry alone (V31, seen in a client 2026-11-27: the Skills entry toggles by the state of its side
-- button, which still says open, so running it closed the window and the dock showed "not available"). Taken out of
-- the list: its release puts it back open and keepColumn hides it again.
local function takeFromColumn(w)
  for i, h in ipairs(columnHidden) do
    if same(h.widget, w) then
      table.remove(columnHidden, i)
      return true
    end
  end
  return false
end

local function giveColumnBack()
  local list = columnHidden
  columnHidden = {}
  for _, h in ipairs(list) do
    if alive(h.widget) and h.widget:getParent() then pcall(h.widget.show, h.widget) end
  end
end

local function columnCycle()
  columnEvent = nil
  if not st or not g_game.isOnline() then return end
  keepColumn()
  columnEvent = scheduleEvent(columnCycle, COLUMN_MS)
end

-- ---------------------------------------------------------------- finding a window
-- the visible windows a menu entry may have opened: children of the root, of the game root and of the side panels
local function windowsNow()
  local out = {}
  local function scan(parent, depth)
    for _, w in ipairs(alive(parent) and parent:getChildren() or {}) do
      local class = w.getClassName and w:getClassName() or ''
      if WINDOW_CLASSES[class] then
        if w:isVisible() and not same(w, panel) then out[#out + 1] = w end
      elseif depth > 0 then
        scan(w, depth - 1)
      end
    end
  end
  scan(g_ui.getRootWidget(), 0)
  scan(gameRoot(), 2) -- gameLeftPanels / gameRightPanels -> the panel containers -> their miniwindows
  return out
end

-- the window of a spec the module keeps where the dock can read it (or the one this entry opened last time)
local function findSpec(spec)
  local m = spec.module and modules[spec.module]
  if type(m) == 'table' then
    if spec.getter then
      local fn = rawget(m, spec.getter)
      if type(fn) == 'function' then
        local ok, w = pcall(fn)
        if ok and alive(w) then return w end
      end
    end
    for _, var in ipairs(spec.vars or {}) do
      local w = rawget(m, var)
      -- a widget (userdata in the client; a table with the widget calls on the test's fake engine)
      local widgetLike = type(w) == 'userdata' or (type(w) == 'table' and type(w.getClassName) == 'function')
      if widgetLike and alive(w) then return w end
    end
  end
  local w = known[spec.entry]
  if alive(w) then return w end
  known[spec.entry] = nil
  return nil
end

-- ---------------------------------------------------------------- the column layout of a window (chaosdockcolumn.lua)
local EDGE = { top = AnchorTop, bottom = AnchorBottom, left = AnchorLeft, right = AnchorRight }
local SETTERS = {
  width = { 'getWidth', 'setWidth' }, height = { 'getHeight', 'setHeight' },
  marginTop = { 'getMarginTop', 'setMarginTop' }, marginLeft = { 'getMarginLeft', 'setMarginLeft' },
  marginRight = { 'getMarginRight', 'setMarginRight' }, marginBottom = { 'getMarginBottom', 'setMarginBottom' },
  visible = { 'isExplicitlyVisible', 'setVisible' },
}

local function anchor(part, edge, target)
  local e = EDGE[edge]
  pcall(part.removeAnchor, part, e)
  if target then
    local id, to = COL.target(target)
    if id then pcall(part.addAnchor, part, e, id, EDGE[to]) end
  end
end

-- a label wraps at the column's edge and is as tall as its lines (O760); off, it has its own wrap and its .otui's
-- text-auto-resize again (rule.autoResize)
local function setWrap(part, on, wrap, autoResize)
  if on then
    pcall(part.setTextHorizontalAutoResize, part, false)
    pcall(part.setTextWrap, part, true)
    pcall(part.setTextVerticalAutoResize, part, true)
  else
    pcall(part.setTextVerticalAutoResize, part, false)
    pcall(part.setTextWrap, part, wrap == true)
    pcall(part.setTextAutoResize, part, autoResize == true)
  end
end

local function setProp(part, key, value)
  if key == 'wrap' then
    if value == true then setWrap(part, true) end
    return
  end
  local s = SETTERS[key]
  local fn = s and part[s[2]]
  if fn then pcall(fn, part, value) end
end

local function getProp(part, key)
  local s = SETTERS[key]
  local fn = s and part[s[1]]
  if not fn then return nil end
  local ok, v = pcall(fn, part)
  return ok and v or nil
end

-- the parts of the window as the column wants them; what they were is kept in rec.layoutSaved
local function layoutIn(rec, layout)
  local w = rec.widget
  rec.layoutSaved = {}
  for _, rule in ipairs(layout.rules or {}) do
    local part = w:recursiveGetChildById(rule.id)
    if part then
      local saved = { part = part, rule = rule, props = {} }
      for _, key in ipairs({ 'width', 'height' }) do saved.props[key] = getProp(part, key) end
      if rule.col.wrap then
        local ok, wrap = pcall(part.getTextWrap, part)
        saved.wrap = { wrap = ok and wrap == true }
      end
      for key in pairs(rule.col) do
        if SETTERS[key] and saved.props[key] == nil then saved.props[key] = getProp(part, key) end
      end
      for _, edge in ipairs(COL.EDGES) do
        if rule.col[edge] ~= nil then anchor(part, edge, rule.col[edge]) end
      end
      for key, value in pairs(rule.col) do
        if SETTERS[key] then setProp(part, key, value) end
      end
      if rule.col.wrap then setProp(part, 'wrap', true) end
      rec.layoutSaved[#rec.layoutSaved + 1] = saved
    end
  end
end

-- every part back: its anchors (home), then its own size, margins and visibility
local function layoutOut(rec)
  for i = #(rec.layoutSaved or {}), 1, -1 do
    local saved = rec.layoutSaved[i]
    local part = saved.part
    if alive(part) then
      for _, edge in ipairs(COL.EDGES) do
        local home = saved.rule.home and saved.rule.home[edge]
        if home ~= nil then anchor(part, edge, home) end
      end
      if saved.wrap then setWrap(part, false, saved.wrap.wrap, saved.rule.autoResize) end
      for key, value in pairs(saved.props) do setProp(part, key, value) end
    end
  end
  rec.layoutSaved = nil
end

-- ---------------------------------------------------------------- holding and giving back
local function setChrome(w, rec, hide)
  for _, id in ipairs(CHROME) do
    local c = w:getChildById(id)
    if c then
      if hide then
        -- its own state: a window taken while hidden (the Inventory panel, O755) has every part hidden by its parent
        rec.chrome[id] = c.isExplicitlyVisible and c:isExplicitlyVisible() or c:isVisible()
        c:hide()
      elseif rec.chrome[id] then
        c:show()
      end
    end
  end
end

-- a window (not a miniwindow) shows without its own frame, title and wide padding in the dock: the dock has a frame and
-- the title, and one column has no room for both (O755). Given back, all of it returns.
local PADS = { 'Top', 'Left', 'Right', 'Bottom' }
local function frame(rec, strip)
  local w = rec.widget
  if rec.mini or not alive(w) then return end
  if strip then
    rec.frame = { text = w.getText and w:getText() or nil, image = w.getImageSource and w:getImageSource() or nil, pad = {} }
    for _, side in ipairs(PADS) do
      local get = w['getPadding' .. side]
      rec.frame.pad[side] = get and get(w) or nil
    end
    if rec.frame.text ~= nil then pcall(w.setText, w, '') end
    if rec.frame.image ~= nil then pcall(w.setImageSource, w, '') end
    for _, side in ipairs(PADS) do
      local set = w['setPadding' .. side]
      if set then pcall(set, w, 2) end
    end
  elseif rec.frame then
    local f = rec.frame
    rec.frame = nil
    if f.text then pcall(w.setText, w, f.text) end
    if f.image and f.image ~= '' then pcall(w.setImageSource, w, f.image) end
    for _, side in ipairs(PADS) do
      local set = w['setPadding' .. side]
      if set and f.pad[side] then pcall(set, w, f.pad[side]) end
    end
  end
end

-- the module's own hook for a docked window (spec.docked: the Inventory panel hides its title bar and tab row)
local function dockedHook(rec, on)
  local m = rec.spec and rec.spec.docked and rec.spec.module and modules[rec.spec.module]
  local fn = type(m) == 'table' and rawget(m, rec.spec.docked) or nil
  if type(fn) == 'function' then pcall(fn, on) end
end

-- the scroll area back to the top, its bar hidden (no window, or one that fits)
local function resetScroll(scroll)
  local scroller, bar = child('scroller'), child('scrollBar')
  if bar then
    pcall(bar.setValue, bar, 0)
    bar:setVisible(scroll == true)
  end
  if scroller then scroller:setMarginRight(scroll and L.SCROLL or 0) end
end

-- a held window in the scroll area at the column's width: one that fits fills the room (a miniwindow always does: it
-- scrolls its own contents), one taller keeps its height (its column layout's or its own) and the bar scrolls it
local function fit(rec, scroll)
  local w = rec.widget
  if not alive(w) or (rec.fitted and rec.scroll == scroll) then return end
  rec.fitted, rec.scroll = true, scroll
  w:breakAnchors()
  w:setMargin(0)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorRight, 'parent', AnchorRight)
  if scroll then w:setHeight(rec.height) else w:addAnchor(AnchorBottom, 'parent', AnchorBottom) end
  resetScroll(scroll)
end

local function release(rec)
  local w = rec.widget
  if not alive(w) then return end
  releasing = true
  pcall(function()
    if rec.onVisible then disconnect(w, { onVisibilityChange = rec.onVisible }) end
    dockedHook(rec, false)
    layoutOut(rec)
    frame(rec, false)
    setChrome(w, rec, false)
    if w.setDraggable and rec.draggable ~= nil then w:setDraggable(rec.draggable) end
    w.chaosRmlSkip = rec.rmlSkip
    w:breakAnchors()
    if alive(rec.home) then
      -- back at its place among the home's children (a side panel keeps its order), as game_chaoslayout moves them
      local cur = w:getParent()
      if cur then cur:removeChild(w) end
      rec.home:insertChild(math.min(rec.index or 1, rec.home:getChildCount() + 1), w)
    end
    w:setSize(rec.size)
    if not rec.mini and rec.pos then w:setPosition(rec.pos) end
    if rec.wasVisible ~= true and rec.mini and type(w.close) == 'function' then
      -- a side window the dock opened through its entry closes the way its module does (its onClose): hidden only, the
      -- module still thought it open and its next toggle closed it (V31: Skills "not available" on the second visit)
      w:close()
    else
      w:setVisible(rec.wasVisible == true)
    end
    if alive(rec.home) and rec.home.fitAll then pcall(rec.home.fitAll, rec.home, w) end
  end)
  releasing = false
end

local function releaseAll()
  local list = held
  held = {}
  for i = #list, 1, -1 do release(list[i]) end
  resetScroll(false)
  keepColumn() -- a window given back to the right column hides there again (O755)
end

local function hold(w, spec, wasVisible)
  local content = child('scroller') or child('content')
  if not content then return end
  local home = w:getParent()
  local rec = {
    widget = w, spec = spec, home = home, index = home and home.getChildIndex and home:getChildIndex(w) or 1,
    wasVisible = wasVisible, size = w:getSize(), pos = w:getPosition(), chrome = {}, rmlSkip = w.chaosRmlSkip,
    mini = (w.getClassName and w:getClassName() or '') == 'UIMiniWindow',
    draggable = w.isDraggable and w:isDraggable() or nil,
  }
  local layout = not isPhone() and COL.layout(spec.entry) or nil
  rec.height = L.heightIn(layout, rec.size.height)
  known[spec.entry] = w
  setChrome(w, rec, true)
  if w.setDraggable then w:setDraggable(false) end
  w.chaosRmlSkip = true -- the RmlUi mirror (client_chaos_rmlmirror) leaves a docked window in OTUI
  w:setParent(content)
  dockedHook(rec, true)
  if not isPhone() then frame(rec, true) end
  if layout then layoutIn(rec, layout) end
  -- anchored by fit() from relayout(), which knows the room (adopt calls it right after)
  w:breakAnchors()
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorRight, 'parent', AnchorRight)
  w:show()
  -- the window's own close (Escape, a button of its own) closes the dock
  -- The engine also calls it when an ancestor hides (the dock panel itself, cinema mode Ctrl+Shift+H): the window is
  -- then still explicitly visible, and that is no close. Before, cinema mode closed the dock and showed its empty panel
  -- again when it ended (seen in a client 2026-11-27, V36).
  rec.onVisible = function(widget, visible)
    if visible or releasing then return end
    if widget and widget.isExplicitlyVisible and widget:isExplicitlyVisible() then return end
    scheduleEvent(function() M.close() end, 1)
  end
  connect(w, { onVisibilityChange = rec.onVisible })
  held[#held + 1] = rec
end

-- ---------------------------------------------------------------- geometry
local function hotbarRect()
  local hb = rawget(_G, 'ChaosHotbar')
  local ok, w = pcall(function() return hb and hb.getWidget and hb.getWidget() end)
  return ok and alive(w) and w:getRect() or nil
end

-- the hub menu bar (client_chaos_topbar, O550) when it is shown: a dock under it starts below it
local function menuBarRect()
  local root = gameRoot()
  local bar = root and root:getChildById('chaosMenuBar')
  return alive(bar) and bar:isVisible() and bar:getRect() or nil
end

-- the toasts (game_chaosnotify) and the How it works card (game_howitworks) keep left of the dock: they are told when the
-- width it covers changes
local function tellToasts()
  local cover = M.coverRight()
  if cover == coverNotified then return end
  coverNotified = cover
  local n = modules.game_chaosnotify
  local fn = n and rawget(n, 'repositionNotifications')
  if type(fn) == 'function' then pcall(fn) end
  local h = modules.game_howitworks
  local place = h and rawget(h, 'reposition')
  if type(place) == 'function' then pcall(place) end
end

-- the tabs and the sub tabs share the column's row (O755: five tabs in one column)
local function sizeTabs(width)
  local room = width - 2 * L.PAD
  local tw = L.share(#L.TABS, room)
  for _, t in ipairs(L.TABS) do
    local b = tabButtons[t.id]
    if alive(b) then b:setWidth(tw) end
  end
  local subs = child('subs')
  if subs then
    local list = subs:getChildren()
    local sw = L.share(math.min(#list, L.SUB_COLS), room)
    local layout = subs.getLayout and subs:getLayout()
    if layout and layout.setCellSize then pcall(layout.setCellSize, layout, { width = sw, height = L.SUB_H }) end
    for _, b in ipairs(list) do b:setWidth(sw) end
  end
end

local function relayout()
  if not alive(panel) then return end
  local root = gameRoot()
  if not root then return end
  local rr = root:getRect()
  local phone = isPhone()
  local width = L.width(columnRect(), rr.x + rr.width, phone, rr.width)
  local bottom, top = 0, 0
  if not phone then
    local left = rr.x + rr.width - width
    bottom = L.bottomMargin(left, hotbarRect(), rr.y + rr.height)
    top = math.max(L.topMargin(left, menuBarRect(), rr.y), L.mapMargin(mapRect(), rr.y))
  end
  local rec = held[1]
  if rec then
    local content = child('content')
    local chrome = content and (panel:getHeight() - content:getHeight()) or nil
    fit(rec, L.scrolls(rec.mini, rec.height, L.room(rr.height, top, bottom, chrome)))
  end
  panel:setWidth(width)
  panel:setMarginBottom(bottom)
  panel:setMarginTop(top)
  sizeTabs(width)
  tellToasts()
end

-- a window too wide for the column (fit 'float': Market, Store) opens on its own, centred in the game left of the dock
local function placeFloat(w)
  if not alive(w) then return end
  local root = gameRoot()
  local rr = root and root:getRect()
  if not rr then return end
  local room = rr.width - M.coverRight()
  local x = math.max(rr.x, rr.x + math.floor((room - w:getWidth()) / 2))
  local y = math.max(rr.y, rr.y + math.floor((rr.height - w:getHeight()) / 2))
  w:breakAnchors()
  w:setPosition({ x = x, y = y })
  w:raise()
end

-- ---------------------------------------------------------------- drawing
local function setGlyph(widget, name, tint)
  local all = modules.client_chaos_topbar and rawget(modules.client_chaos_topbar, 'ChaosTopBarGlyphs')
  local atlas = all and all.bar
  local cell = atlas and atlas.slots[name]
  if not widget or not cell then return end
  widget:setImageSource(GLYPHS)
  widget:setImageClip(string.format('%d %d %d %d', cell[1], cell[2], atlas.cell, atlas.cell))
  widget:setImageColor(tint)
end

local function drawTabs()
  for _, t in ipairs(L.TABS) do
    local b = tabButtons[t.id]
    if alive(b) then
      local on = st.open and st.tab == t.id
      b:setChecked(on)
      setGlyph(b:getChildById('glyph'), t.glyph, on and palette('accent2', '#f6cf72') or palette('textDim', '#8c8070'))
    end
  end
end

local function drawSubs()
  local subs = child('subs')
  if not subs then return end
  subs:destroyChildren()
  local t = L.tab(st.tab)
  local many = t and #t.windows > 1
  subs:setVisible(many == true)
  subs:setHeight(many and L.subsHeight(#t.windows) or 0)
  if not many then return end
  local current = L.subOf(st, t.id)
  for i, spec in ipairs(t.windows) do
    local b = g_ui.createWidget('ChaosDockSub', subs)
    b:setText(tr(spec.entry))
    b:setTooltip(tr(spec.entry))
    b:setChecked(i == current)
    b.onClick = function() M.dispatch(L.pickSub(st, i)) end
  end
end

local function setNote(text)
  local note = child('note')
  if not note then return end
  note:setText(text or '')
  note:setVisible(text ~= nil)
end

-- ---------------------------------------------------------------- showing a tab
local function stopPoll()
  if pollEvent then removeEvent(pollEvent) pollEvent = nil end
end

-- a window that opened on its own (too wide) goes with its tab, if the dock opened it
local function dropFloat()
  local f = floated
  floated = nil
  if f and f.opened and alive(f.widget) and f.widget:isVisible() then pcall(f.widget.hide, f.widget) end
end

local function adopt(w, spec, wasVisible)
  if L.fitOf(spec, isPhone()) == 'float' then
    floated = { widget = w, opened = not wasVisible }
    setNote(tr(L.FLOAT_NOTE))
    relayout()
    placeFloat(w)
    return
  end
  hold(w, spec, wasVisible)
  setNote(nil)
  relayout()
end

local function showCurrent()
  stopPoll()
  releaseAll()
  dropFloat()
  local t = L.tab(st.tab)
  local spec = t and t.windows[L.subOf(st, t.id)]
  local title = child('title')
  if title then title:setText(spec and tr(spec.entry) or '') end
  drawTabs()
  drawSubs()
  setNote(nil)
  relayout()
  if not spec then return end
  local w = findSpec(spec)
  if w and not w:isVisible() and takeFromColumn(w) then adopt(w, spec, true) return end
  if w and (w:isVisible() or spec.hidden) then adopt(w, spec, w:isVisible()) return end
  -- not open: its menu entry opens it (the module fills it as it always does), then the dock takes it
  local before = windowsNow()
  local bar = topbar()
  if bar and bar.runRaw then pcall(bar.runRaw, spec.entry) end
  local tries = 0
  local function look()
    pollEvent = nil
    if not st.open then return end
    local found = findSpec(spec)
    if not (found and found:isVisible()) then found = L.pickNew(before, windowsNow(), same) end
    if found then adopt(found, spec, false) return end
    tries = tries + 1
    if tries < POLL_TRIES then pollEvent = scheduleEvent(look, POLL_MS) return end
    setNote(tr('This window is not available now.'))
    relayout()
  end
  look()
end

-- ---------------------------------------------------------------- open, close, slide
local function stopSlide()
  if slideEvent then removeEvent(slideEvent) slideEvent = nil end
end

local function slide(out, done)
  stopSlide()
  if not alive(panel) then return end
  local steps = L.slide(panel:getWidth())
  local i = 0
  local function step()
    slideEvent = nil
    if not alive(panel) then return end
    i = i + 1
    local margin = out and steps[#steps - i + 1] or steps[i]
    if out and i == #steps then margin = -panel:getWidth() end
    panel:setMarginRight(margin or 0)
    if i < #steps then slideEvent = scheduleEvent(step, SLIDE_MS) elseif done then done() end
  end
  step()
end

local function tick()
  tickEvent = nil
  if not st or not st.open or not alive(panel) then return end
  relayout()
  tickEvent = scheduleEvent(tick, TICK_MS)
end

local function openPanel()
  if not alive(panel) then return end
  local wasShown = panel:isVisible()
  keepColumn()
  relayout()
  panel:show()
  panel:raise()
  if not wasShown then
    panel:setMarginRight(-panel:getWidth())
    slide(false)
  end
  showCurrent()
  if not tickEvent then tickEvent = scheduleEvent(tick, TICK_MS) end
end

function M.close()
  stopPoll()
  if st then st.open = false end
  releaseAll()
  dropFloat()
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  if alive(panel) and panel:isVisible() then
    drawTabs()
    slide(true, function()
      if alive(panel) then panel:hide() end
      tellToasts()
    end)
  else
    tellToasts()
  end
end

-- runs an action of chaosdocklogic.lua (route, toggle, pickTab, pickSub)
function M.dispatch(action)
  if not action or not st then return false end
  write(L.apply(st, action))
  if action.close then M.close() else openPanel() end
  return true
end

-- ---------------------------------------------------------------- the menu and the keys
-- client_chaos_topbar asks before it runs an entry: true when the dock took it (it opened or closed the dock)
function M.route(text)
  if not st or not alive(panel) or not g_game.isOnline() then return false end
  if st.open and L.releaseForOther(held, text) then M.close() end
  return M.dispatch(L.route(st, text))
end

function M.toggle() return M.dispatch(st and L.toggle(st)) end
function M.openTab(id) return M.dispatch(st and L.pickTab(st, id, false)) end
function M.isEnabled() return st ~= nil and st.enabled end
function M.isOpen() return st ~= nil and st.open end

-- a bag the player opened (game_bagpanel): the dock shows the Inventory, unless it already does (O755: the panel has no
-- window of its own). restoring / quiet: opened by the login restore or a pinned bag's reopen.
function M.bagOpened(restoring, quiet)
  if not st or not alive(panel) or not g_game.isOnline() then return false end
  if not L.bagOpensDock(st, restoring, quiet, now() - startedAt) then return false end
  return M.openTab('equip')
end

-- the width the dock covers at the right of the game screen (0 when closed), for the toasts of game_chaosnotify
function M.coverRight()
  if not st or not st.open or not alive(panel) or not panel:isVisible() or isPhone() then return 0 end
  return panel:getWidth()
end

-- the windows the dock holds now, for game_chaoslayout (a miniwindow is saved in the side panel it came from)
function M.held()
  local out = {}
  for _, rec in ipairs(held) do
    if alive(rec.widget) then out[#out + 1] = { widget = rec.widget, home = rec.home, index = rec.index, visible = rec.wasVisible,
        height = rec.size.height } end
  end
  return out
end

-- the window opened on its own beside the dock (Market, Store), for the tour of test_docktour
function M.floating()
  return floated and alive(floated.widget) and floated.widget or nil
end

local function unbindKeys()
  for key, fn in pairs(boundKeys) do pcall(g_keyboard.unbindKeyDown, key, fn) end
  boundKeys = {}
end

local function bindKeys()
  unbindKeys()
  if not st or not st.enabled or isPhone() then return end
  for _, k in ipairs(L.hotkeys()) do
    local fn = function()
      if k.tab then M.dispatch(L.pickTab(st, k.tab, true)) else M.toggle() end
      return true
    end
    boundKeys[k.key] = fn
    g_keyboard.bindKeyDown(k.key, fn)
  end
end

-- the option of the Layout options window (game_hotbar): off gives the floating windows and the right column back
function M.setEnabled(on)
  if not st then return end
  st.enabled = on ~= false
  write({ [L.SETTING_ENABLED] = st.enabled and 'true' or 'false' })
  if not st.enabled then
    M.close()
    giveColumnBack()
    local bp = modules.game_bagpanel
    local show = bp and rawget(bp, 'showWindow')
    if type(show) == 'function' then pcall(show) end
  else
    keepColumn()
  end
  if g_game.isOnline() then bindKeys() end
end

-- ---------------------------------------------------------------- building
local function build()
  if alive(panel) then return end
  local root = gameRoot()
  if not root then return end
  panel = g_ui.createWidget('ChaosDockPanel', root)
  panel.chaosNoMirror = true
  panel:hide()
  local tabs = child('tabs')
  tabButtons = {}
  for _, t in ipairs(L.TABS) do
    local b = g_ui.createWidget('ChaosDockTab', tabs)
    b:setId('chaosDockTab_' .. t.id)
    b:getChildById('label'):setText(tr(t.name))
    b:setTooltip(t.key and (tr(t.name) .. ' (' .. t.key .. ')') or tr(t.name))
    b.onClick = function() M.dispatch(L.pickTab(st, t.id, false)) end
    tabButtons[t.id] = b
  end
  local x = child('closeX')
  if x then x.onClick = function() M.close() end end
  drawTabs()
end

local function onGameStart()
  -- the character's own dock: its tab, windows and whether it was open (O755)
  local enabled = st and st.enabled
  st = L.newState(read, charName())
  if enabled ~= nil then st.enabled = enabled end
  startedAt = now()
  build()
  bindKeys()
  keepColumn()
  if columnEvent then removeEvent(columnEvent) end
  columnEvent = scheduleEvent(columnCycle, COLUMN_MS)
  -- open again as it was left, after the login has put the windows back
  if reopenEvent then removeEvent(reopenEvent) end
  if st.enabled and st.wasOpen then
    reopenEvent = scheduleEvent(function()
      reopenEvent = nil
      if st and not st.open and g_game.isOnline() then M.toggle() end
    end, 3000)
  end
end

local function onGameEnd()
  if reopenEvent then removeEvent(reopenEvent) reopenEvent = nil end
  if columnEvent then removeEvent(columnEvent) columnEvent = nil end
  -- the logout closes the dock without a write: the character's saved state stays (it opens again at the next entry)
  M.close()
  stopSlide()
  unbindKeys()
  if alive(panel) then panel:destroy() end
  panel, tabButtons, known, columnHidden = nil, {}, {}, {}
end

function M.init()
  g_ui.importStyle('chaosdock')
  st = L.newState(read)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  giveColumnBack()
  onGameEnd()
  st = nil
end

function init() M.init() end
function terminate() M.terminate() end
function closeDock() M.close() end
