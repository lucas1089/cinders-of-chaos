-- game_hudmove: makes a floating HUD panel movable (client/MANIFEST.md "Movable HUD panels"). Global ChaosHudMove, not
-- sandboxed. A module needs one call once its panel exists:
--   ChaosHudMove.attach(panel, 'myPanelId', { otui = '/modules/game_x/x.otui', style = 'MyHud' })
-- The player drags the panel by its background (or by the handles given); a press on a button, checkbox, edit or item
-- stays theirs. The spot is saved per panel and character (g_settings node chaosHudPos), restored when the panel shows,
-- clamped on screen (again when the window or the panel resizes). A double-click puts the panel back at its default
-- place and forgets the spot. Nothing saved: the module's own anchors are never touched. Pure part: hudmove_core.lua.
--
-- attach(panel, id, opts)   opts (all optional):
--   handles = { widget, ... }  children that drag the panel too, even with a click of their own (a title that folds:
--                              a click still folds, a drag does not; set onClick before attach)
--   panel = false              only the handles drag (a click-through HUD stays click-through)
--   otui, style                the .otui file (and style name) whose anchors are the default place
--   reset = function(panel)    puts the panel at its default place instead (anchors set in Lua)
--   onDefault = function(panel) runs after the panel is back at its default place (a module that fine-tunes its margins)
-- detach(panel)              stops it (the panel keeps its spot)
-- place(panel)               this character's spot again (attach and showing the panel do it)
-- isMoved(panel)             true while the panel sits at a saved spot (a module that re-anchors its panel skips then)
-- reset(panel)               back to the default place, the spot forgotten (as the double-click)
ChaosHudMove = ChaosHudMove or {}
local M = ChaosHudMove
local C = HudMoveCore

-- the attached panels. A widget pushed to Lua twice is two userdata that are == (the engine's __eq) but not the same
-- table key, so panels and handles are found by ==, never by indexing.
local entries = {}

local function find(panel)
  if panel == nil then return nil end
  for i, st in ipairs(entries) do
    if st.panel == panel then return st, i end
  end
  return nil
end

local function isHandle(st, w)
  for _, h in ipairs(st.handleList) do
    if h == w then return true end
  end
  return false
end

local EDGE = {}
local function edgeConst(name)
  if not next(EDGE) then
    EDGE = { top = AnchorTop, bottom = AnchorBottom, left = AnchorLeft, right = AnchorRight,
      horizontalCenter = AnchorHorizontalCenter, verticalCenter = AnchorVerticalCenter }
  end
  return EDGE[name]
end

local function alive(w)
  return w ~= nil and not (w.isDestroyed and w:isDestroyed())
end

local function charKey()
  local world = g_game.getWorldName and g_game.getWorldName() or nil
  return C.key(world, g_game.getCharacterName and g_game.getCharacterName() or nil)
end

local function savedNode()
  local ok, node = pcall(g_settings.getNode, C.NODE)
  return ok and type(node) == 'table' and node or {}
end

local function savePos(st, pos)
  local key = charKey()
  if not key then return end
  pcall(g_settings.setNode, C.NODE, C.store(savedNode(), st.id, key, pos))
  pcall(g_settings.save) -- a client that crashes or is killed keeps the spot too
end

local function rectOf(w)
  if not alive(w) then return nil end
  return { x = w:getX(), y = w:getY(), width = w:getWidth(), height = w:getHeight() }
end

local function boundsOf(panel)
  local parent = panel:getParent()
  return C.bounds(rectOf(parent), rectOf(g_ui.getRootWidget()))
end

local function anchorAt(panel, x, y)
  panel:breakAnchors()
  panel:addAnchor(AnchorTop, 'parent', AnchorTop)
  panel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  panel:setMarginTop(y)
  panel:setMarginLeft(x)
end

-- the default place: the module's reset, else the anchors of its .otui and the margins it had when attached
local function anchorDefault(st)
  local panel = st.panel
  if st.reset then
    pcall(st.reset, panel)
  elseif st.anchors then
    M.applyAnchors(panel, st.anchors, st.margins)
  end
  if st.onDefault then pcall(st.onDefault, panel) end
end

-- default anchors (C.parseAnchors) and margins on a widget
function M.applyAnchors(panel, anchors, m)
  panel:breakAnchors()
  for _, a in ipairs(anchors) do
    if a[1] == 'fill' then
      panel:fill(a[2])
    elseif a[1] == 'centerIn' then
      panel:centerIn(a[2])
    else
      panel:addAnchor(edgeConst(a[1]), a[2], edgeConst(a[3]))
    end
  end
  panel:setMarginTop(m.top)
  panel:setMarginRight(m.right)
  panel:setMarginBottom(m.bottom)
  panel:setMarginLeft(m.left)
end

function M.place(panel)
  local st = find(panel)
  if not st or st.drag or not alive(panel) or not panel:getParent() then return end
  local pos = C.place(C.saved(savedNode(), st.id, charKey()), panel:getWidth(), panel:getHeight(), boundsOf(panel))
  if pos then
    local parent = panel:getParent()
    local x, y = panel:getX() - parent:getX(), panel:getY() - parent:getY()
    if not st.moved or x ~= pos.x or y ~= pos.y then anchorAt(panel, pos.x, pos.y) end
    st.moved = true
  elseif st.moved then
    st.moved = false
    anchorDefault(st)
  end
end

-- after a layout pass: the window, the parent or the panel's size changed
local function schedulePlace(st)
  if st.placeEvent then return end
  st.placeEvent = addEvent(function()
    st.placeEvent = nil
    if st.moved then M.place(st.panel) end
  end)
end

function M.isMoved(panel)
  local st = find(panel)
  return st ~= nil and st.moved == true
end

function M.reset(panel)
  local st = find(panel)
  if not st then return end
  if st.drag then
    pcall(function() st.drag.source:ungrabMouse() end)
    st.drag = nil
  end
  savePos(st, nil)
  M.place(panel)
end

-- the widgets from the one under the mouse up to the drag source, described for C.canStartDrag
local function chainAt(st, source, pos)
  local chain = {}
  local ok, hit = pcall(function() return source:recursiveGetChildByPos(pos, false) end)
  local w = ok and hit or nil
  local guard = 0
  while w and w ~= source and guard < 32 do
    local okc, class = pcall(function() return w:getClassName() end)
    chain[#chain + 1] = {
      class = okc and class or nil,
      click = (w.onClick ~= nil or w.onCheckChange ~= nil or w.onDoubleClick ~= nil) or nil,
      draggable = (w.isDraggable and w:isDraggable()) or nil,
      handle = isHandle(st, w) or nil,
    }
    w = w:getParent()
    guard = guard + 1
  end
  return chain
end

local function onPress(st, source, pos, button)
  if button ~= MouseLeftButton or not alive(st.panel) then return false end
  st.justDragged = false
  if not C.canStartDrag(chainAt(st, source, pos)) then return false end
  local panel, parent = st.panel, st.panel:getParent()
  if not parent then return false end
  st.drag = { source = source, offX = pos.x - panel:getX(), offY = pos.y - panel:getY(), mx = pos.x, my = pos.y,
    fromX = panel:getX() - parent:getX(), fromY = panel:getY() - parent:getY(), active = false }
  source:grabMouse()
  return true
end

local function onMove(st, pos)
  local d = st.drag
  if not d then return false end
  local panel = st.panel
  if not d.active then
    if not C.moved(d.mx, d.my, pos.x, pos.y) then return true end
    d.active = true
    anchorAt(panel, d.fromX, d.fromY) -- the default anchors give way only once it really moves
  end
  local parent = panel:getParent()
  local x, y = C.dragTo(pos.x, pos.y, d.offX, d.offY, parent:getX(), parent:getY(), panel:getWidth(),
    panel:getHeight(), boundsOf(panel))
  panel:setMarginLeft(x)
  panel:setMarginTop(y)
  return true
end

local function onRelease(st)
  local d = st.drag
  if not d then return false end
  st.drag = nil
  pcall(function() d.source:ungrabMouse() end)
  if not d.active then return false end -- a click: the panel never left its anchors
  local panel, parent = st.panel, st.panel:getParent()
  st.moved = true
  st.justDragged = true -- the click the release fires on a handle is not a click
  savePos(st, { x = panel:getX() - parent:getX(), y = panel:getY() - parent:getY() })
  return true
end

local function onDouble(st, source, pos)
  if not C.canStartDrag(chainAt(st, source, pos)) then return false end
  M.reset(st.panel)
  return true
end

-- a source with a click of its own (a title or a panel that folds): no click right after a drag. The module sets its
-- onClick before attach.
local function guardClick(st, w)
  local orig = w.onClick
  if type(orig) ~= 'function' then return end
  w.onClick = function(...)
    if st.justDragged then
      st.justDragged = false
      return true
    end
    return orig(...)
  end
  st.clickGuards[#st.clickGuards + 1] = { widget = w, onClick = orig }
end

local function addTooltip(w)
  local ok, tip = pcall(function() return w:getTooltip() end)
  local hint = tr('Drag to move. Double-click to put it back.')
  if ok and type(tip) == 'string' and tip ~= '' then
    if not tip:find(hint, 1, true) then w:setTooltip(tip .. '\n' .. hint) end
  else
    w:setTooltip(hint)
  end
end

local function readOtui(path)
  if type(path) ~= 'string' then return nil end
  if not path:match('%.otui$') then path = path .. '.otui' end
  local ok, text = pcall(g_resources.readFileContents, path)
  return ok and text or nil
end

function M.attach(panel, id, opts)
  if not alive(panel) or type(id) ~= 'string' or id == '' then return nil end
  local known = find(panel)
  if known then return known end
  opts = opts or {}
  local st = { panel = panel, id = id, reset = opts.reset, onDefault = opts.onDefault, handleList = {}, sources = {},
    clickGuards = {},
    margins = { top = panel:getMarginTop(), right = panel:getMarginRight(), bottom = panel:getMarginBottom(),
      left = panel:getMarginLeft() } }
  if not st.reset then st.anchors = C.parseAnchors(readOtui(opts.otui), opts.style) end
  entries[#entries + 1] = st

  local list = {}
  if opts.panel ~= false then list[#list + 1] = panel end
  for _, h in ipairs(opts.handles or {}) do
    if alive(h) then
      st.handleList[#st.handleList + 1] = h
      list[#list + 1] = h
    end
  end
  for _, src in ipairs(list) do
    local s = src
    local handlers = {
      onMousePress = function(_, pos, button) return onPress(st, s, pos, button) end,
      onMouseMove = function(_, pos) return onMove(st, pos) end,
      onMouseRelease = function() return onRelease(st) end,
      onDoubleClick = function(_, pos) return onDouble(st, s, pos) end,
    }
    s:setPhantom(false)
    connect(s, handlers)
    st.sources[#st.sources + 1] = { widget = s, handlers = handlers }
    guardClick(st, s)
    pcall(addTooltip, s)
  end

  st.onShow = function(_, visible) if visible then M.place(panel) end end
  st.lastW, st.lastH = panel:getWidth(), panel:getHeight()
  st.onSize = function()
    if not alive(panel) then return end
    local w, h = panel:getWidth(), panel:getHeight()
    if w == st.lastW and h == st.lastH then return end
    st.lastW, st.lastH = w, h
    if st.moved and not st.drag then schedulePlace(st) end
  end
  st.onParent = function() if st.moved and not st.drag then schedulePlace(st) end end
  connect(panel, { onVisibilityChange = st.onShow, onGeometryChange = st.onSize })
  st.parent = panel:getParent()
  if st.parent then connect(st.parent, { onGeometryChange = st.onParent }) end
  M.place(panel)
  return st
end

function M.detach(panel)
  local st, i = find(panel)
  if not st then return end
  table.remove(entries, i)
  if st.placeEvent then removeEvent(st.placeEvent); st.placeEvent = nil end
  if st.drag then pcall(function() st.drag.source:ungrabMouse() end) end
  if not alive(panel) then return end
  for _, s in ipairs(st.sources) do pcall(disconnect, s.widget, s.handlers) end
  for _, g in ipairs(st.clickGuards) do if alive(g.widget) then g.widget.onClick = g.onClick end end
  pcall(disconnect, panel, { onVisibilityChange = st.onShow, onGeometryChange = st.onSize })
  if alive(st.parent) then pcall(disconnect, st.parent, { onGeometryChange = st.onParent }) end
end

-- another character: its own spots (a panel that stays shown through a relog)
local function onGameStart()
  for _, st in ipairs(entries) do
    if alive(st.panel) and st.panel:isVisible() then M.place(st.panel) end
  end
end

function M.init()
  connect(g_game, { onGameStart = onGameStart })
end

function M.terminate()
  disconnect(g_game, { onGameStart = onGameStart })
  for i = #entries, 1, -1 do M.detach(entries[i].panel) end
end
