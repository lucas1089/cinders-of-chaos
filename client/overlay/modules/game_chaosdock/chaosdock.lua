-- game_chaosdock (O732, owner 2026-11-23: option A of the UI mockups, "mantenha a barra de skills embaixo com os orbs ao
-- lado", "mantenha tudo na skin principal do jogo"). A panel docked on the right of the game screen, full height, 330 px,
-- that slides in and out. Icon tabs on top: Equip., Quests, Attributes, Spells, Shop (chaosdocklogic.lua L.TABS). A tab
-- hosts the windows that already exist: the dock opens the window through its menu entry (ChaosTopBar.runRaw), takes it
-- out of its parent and puts it in its content area; closing the dock, another tab or logout gives it back where it was,
-- open or closed as before. Nothing of the windows' own logic changes.
--  * The hub menu (client_chaos_topbar, O550): an entry of a tab (a card, the text menu, its hotkey) opens the dock on
--    that tab (ChaosDock.route); every other entry opens its window as before.
--  * A tab with two or more windows shows one at a time, picked by the row of small tabs under the icons.
--  * A window wider than the dock widens the dock while it is shown (at most the screen less 320 px of game); a window
--    wider than that stays a window of its own, placed left of the dock.
--  * The hotbar and its globes (game_hotbar, game_shaderfx) stay at the bottom centre: the dock stops above the hotbar
--    when the two would meet.
--  * Keys: Alt+D shows or hides the dock, Alt+I / Alt+Q / Alt+A open Equip. / Quests / Attributes; Spells and Shop
--    open with the entry keys Alt+S (Spellbook) and Alt+E (Market). The last tab and window are kept (settings
--    chaosDockTab, chaosDockSubs). Layout options > "Side panel with tabs" turns the dock off (setting chaosDockEnabled):
--    the old floating windows come back.
--  * A phone gets the dock as a sheet over the whole screen.
-- The skin is client_chaos_theme's (window frame, tab buttons, ChaosCloseX) and the glyphs of the hub menu.
ChaosDock = ChaosDock or {}
local M = ChaosDock
local L = ChaosDockLogic

local GLYPHS = '/modules/client_chaos_topbar/images/glyphs_bar'
local POLL_MS, POLL_TRIES = 120, 12
local TICK_MS = 1000
local SLIDE_MS = 25
local CHROME = { 'closeButton', 'minimizeButton', 'lockButton', 'closeX' }
local WINDOW_CLASSES = { UIWindow = true, UIMiniWindow = true }

local panel
local st
local held = {}          -- records of the windows in the dock: widget, home, index, wasVisible, spec, size, pos, ...
local known = {}         -- menu entry -> the widget it opened last (a module that keeps a local window)
local tabButtons = {}
local floated            -- a window too wide for the dock, opened beside it: { widget, opened = the dock opened it }
local coverNotified = 0  -- the width last told to the toasts (game_chaosnotify)
local slideEvent, tickEvent, pollEvent
local boundKeys = {}
local releasing = false
local lastKey = 0

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

local function read(key)
  local ok, v = pcall(g_settings.getString, key)
  if ok and v ~= nil and v ~= '' then return v end
  return nil
end

local function write(values)
  for k, v in pairs(values or {}) do pcall(g_settings.set, k, v) end
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

local function child(id) return panel and panel:recursiveGetChildById(id) or nil end

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
      if type(w) == 'userdata' and alive(w) then return w end
    end
  end
  local w = known[spec.entry]
  if alive(w) then return w end
  known[spec.entry] = nil
  return nil
end

-- ---------------------------------------------------------------- holding and giving back
local function setChrome(w, rec, hide)
  for _, id in ipairs(CHROME) do
    local c = w:getChildById(id)
    if c then
      if hide then
        rec.chrome[id] = c:isVisible()
        c:hide()
      elseif rec.chrome[id] then
        c:show()
      end
    end
  end
end

local function release(rec)
  local w = rec.widget
  if not alive(w) then return end
  releasing = true
  pcall(function()
    if rec.onVisible then disconnect(w, { onVisibilityChange = rec.onVisible }) end
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
    w:setVisible(rec.wasVisible == true)
    if alive(rec.home) and rec.home.fitAll then pcall(rec.home.fitAll, rec.home, w) end
  end)
  releasing = false
end

local function releaseAll()
  local list = held
  held = {}
  for i = #list, 1, -1 do release(list[i]) end
end

local function hold(w, spec, wasVisible)
  local content = child('content')
  if not content then return end
  local home = w:getParent()
  local rec = {
    widget = w, spec = spec, home = home, index = home and home.getChildIndex and home:getChildIndex(w) or 1,
    wasVisible = wasVisible, size = w:getSize(), pos = w:getPosition(), chrome = {}, rmlSkip = w.chaosRmlSkip,
    mini = (w.getClassName and w:getClassName() or '') == 'UIMiniWindow',
    draggable = w.isDraggable and w:isDraggable() or nil,
  }
  known[spec.entry] = w
  setChrome(w, rec, true)
  if w.setDraggable then w:setDraggable(false) end
  w.chaosRmlSkip = true -- the RmlUi mirror (client_chaos_rmlmirror) leaves a docked window in OTUI
  w:setParent(content)
  w:breakAnchors()
  w:setMargin(0)
  w:addAnchor(AnchorTop, 'parent', AnchorTop)
  w:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  w:addAnchor(AnchorRight, 'parent', AnchorRight)
  if rec.mini or rec.size.height <= content:getHeight() then w:addAnchor(AnchorBottom, 'parent', AnchorBottom) end
  w:show()
  -- the window's own close (Escape, a button of its own) closes the dock
  rec.onVisible = function(_, visible)
    if not visible and not releasing then scheduleEvent(function() M.close() end, 1) end
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

-- the hub menu bar (client_chaos_topbar, O550) when it is shown: a dock widened under it starts below it
local function menuBarRect()
  local root = gameRoot()
  local bar = root and root:getChildById('chaosMenuBar')
  return alive(bar) and bar:isVisible() and bar:getRect() or nil
end

-- the toasts (game_chaosnotify) keep left of the dock: they are told when the width it covers changes
local function tellToasts()
  local cover = M.coverRight()
  if cover == coverNotified then return end
  coverNotified = cover
  local n = modules.game_chaosnotify
  local fn = n and rawget(n, 'repositionNotifications')
  if type(fn) == 'function' then pcall(fn) end
end

local function relayout()
  if not alive(panel) then return end
  local root = gameRoot()
  if not root then return end
  local rr = root:getRect()
  local rec = held[1]
  local width, float = L.width(rec and rec.size.width or nil, rr.width, isPhone())
  panel:setWidth(width)
  local bottom, top = 0, 0
  if not isPhone() then
    local left = rr.x + rr.width - width
    bottom = L.bottomMargin(left, hotbarRect(), rr.y + rr.height)
    top = L.topMargin(left, menuBarRect(), rr.y)
  end
  panel:setMarginBottom(bottom)
  panel:setMarginTop(top)
  tellToasts()
  return float
end

local function placeFloat(w)
  if not alive(w) or not alive(panel) then return end
  local root = gameRoot()
  local rr = root and root:getRect()
  if not rr then return end
  local x = math.max(rr.x, panel:getX() - w:getWidth() - 4)
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
  subs:setHeight(many and 24 or 0)
  if not many then return end
  local current = L.subOf(st, t.id)
  for i, spec in ipairs(t.windows) do
    local b = g_ui.createWidget('ChaosDockSub', subs)
    b:setText(tr(spec.entry))
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

-- a window that floated beside the dock goes when the dock moves on or closes, if the dock opened it
local function dropFloat()
  local f = floated
  floated = nil
  if f and f.opened and alive(f.widget) and f.widget:isVisible() then pcall(f.widget.hide, f.widget) end
end

local function adopt(w, spec, wasVisible)
  local rr = gameRoot() and gameRoot():getRect()
  local _, float = L.width(w:getWidth(), rr and rr.width or 0, isPhone())
  if float then
    floated = { widget = w, opened = not wasVisible }
    placeFloat(w)
    setNote(tr('This window is too wide for the panel on this screen: it opened beside it.'))
    relayout()
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
  if not spec then return end
  local w = findSpec(spec)
  if w and w:isVisible() then adopt(w, spec, true) return end
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

-- the option of the Layout options window (game_hotbar): off gives the floating windows back
function M.setEnabled(on)
  if not st then return end
  st.enabled = on ~= false
  write({ [L.SETTING_ENABLED] = st.enabled and 'true' or 'false' })
  if not st.enabled then M.close() end
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
  build()
  bindKeys()
end

local function onGameEnd()
  M.close()
  stopSlide()
  unbindKeys()
  if alive(panel) then panel:destroy() end
  panel, tabButtons, known = nil, {}, {}
end

function M.init()
  g_ui.importStyle('chaosdock')
  st = L.newState(read)
  connect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  if g_game.isOnline() then onGameStart() end
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart, onGameEnd = onGameEnd })
  onGameEnd()
  st = nil
end

function init() M.init() end
function terminate() M.terminate() end
function closeDock() M.close() end
