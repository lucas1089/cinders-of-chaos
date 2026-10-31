-- Window mirror (docs/RMLUI_SPIKE.md, phase 4). Every visible OTUI window (UIWindow, UIMessageBox) whose controls the form
-- layer can draw (client_chaos_rmlform) is shown in RmlUi with the client skin. The OTUI window stays where it is, with
-- opacity 0 and phantom: its module keeps working with it (texts, values, enabled states are read back every 150 ms;
-- a change in RmlUi goes through the OTUI widget's own click or setter; keys still reach the OTUI window, so Enter,
-- Escape and typing into a focused OTUI field work as before).
-- A window a module styled itself (the login panel) sets w.chaosNoMirror = true and stays in OTUI.
-- A window with something the layer cannot draw (items, creatures, the map, tables...) stays in OTUI. So does a mirrored
-- window while an OTUI window or menu that is not mirrored lies over it, and any window after its "Classic" button.
-- Only a client built with -DCHAOS_RMLUI=ON has g_rml; without it this module does nothing.
--   ChaosRmlMirror.setEnabled(bool) / .toggle()  (Ctrl+Alt+M; saved as the setting chaosRmlMirror, on by default)

ChaosRmlMirror = ChaosRmlMirror or {}
local M = ChaosRmlMirror

local PATH = '/modules/client_chaos_rmlmirror/'
local TICK_MS = 150

M.WINDOW_CLASSES = { UIWindow = true, UIMessageBox = true, UIInputBox = true }
-- OTUI widgets that hide a mirror when they lie over it (z order above it in the same parent, rects meet)
M.COVER_CLASSES = { UIWindow = true, UIMessageBox = true, UIInputBox = true, UIPopupMenu = true, UIPopupScrollMenu = true,
  UIMiniWindow = true }

local function classOf(w)
  return w.getClassName and w:getClassName() or 'UIWidget'
end

-- tables of windows are keyed by ChaosRmlForm.keyOf (a widget reaches Lua as a new userdata each time)
function M.keyOf(w) return ChaosRmlForm.keyOf(w) end

local function meets(a, b)
  return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

-- Pure: may this window be mirrored? Returns the form items, or nil and the reason.
function M.eligible(w, deny)
  if not w:isExplicitlyVisible() then return nil, 'hidden' end
  if not M.WINDOW_CLASSES[classOf(w)] then return nil, 'class' end
  if w.chaosRmlSkip or w.chaosNoMirror or (deny and deny[M.keyOf(w)]) then return nil, 'skip' end
  local items, unsupported = ChaosRmlForm.collect(w)
  if #unsupported > 0 then return nil, 'unsupported: ' .. table.concat(unsupported, ', ') end
  local controls = 0
  for _, it in ipairs(items) do
    if it.kind ~= 'group' and it.kind ~= 'endgroup' and it.kind ~= 'sep' and it.kind ~= 'image' and it.kind ~= 'help' then
      controls = controls + 1
    end
  end
  if controls == 0 then return nil, 'empty' end
  return items
end

-- Pure: the top-level widgets of the given roots (the UI root, the game root panel), each once.
function M.candidates(roots)
  local out, seen = {}, {}
  for _, root in ipairs(roots) do
    if root then
      for _, c in ipairs(root:getChildren()) do
        local k = M.keyOf(c)
        if not seen[k] then seen[k] = true out[#out + 1] = c end
      end
    end
  end
  return out
end

-- Pure: is window w covered by a visible sibling drawn after it that is not mirrored itself (mirrored: keys)?
function M.covered(w, mirrored)
  local parent = w:getParent()
  if not parent then return false end
  local mine = w:getRect()
  local after = false
  for _, c in ipairs(parent:getChildren()) do
    if c == w then
      after = true
    elseif after and not mirrored[M.keyOf(c)] and c:isExplicitlyVisible() and M.COVER_CLASSES[classOf(c)] and meets(mine, c:getRect()) then
      return true
    end
  end
  return false
end

-- engine side ----------------------------------------------------------------------------------------------------------

M.entries = M.entries or {}   -- key of the OTUI window -> { window, doc, form, opacity, phantom, pos, dy, suspended }
local tickEvent = nil

local function settingOn()
  if g_settings and g_settings.getBoolean then
    local ok, v = pcall(g_settings.getBoolean, 'chaosRmlMirror', true)
    if ok and v ~= nil then return v end
  end
  return true
end

function M.available()
  return ChaosRmlForm ~= nil and ChaosRmlForm.available()
end

local function hideOtui(e)
  e.window:setOpacity(0)
  e.window:setPhantom(true)
end

local function showOtui(e)
  if e.window:isDestroyed() then return end
  e.window:setOpacity(e.opacity)
  e.window:setPhantom(e.phantom)
end

local NARROW = 260   -- below this width the crest goes and the title gets the whole bar

-- The RmlUi window takes the OTUI window's place and width; its height grows when the skin's larger text needs more room
-- (an RmlUi window never scrolls where the OTUI one did not). It stays centred on the OTUI window; e.dy is how far its
-- top sits above the OTUI top.
local function place(e)
  local r = e.window:getRect()
  e.pos = { x = r.x, y = r.y, width = r.width, height = r.height }
  e.dy = e.dy or 0
  g_rml.setProperty(e.doc, 'window', 'left', r.x .. 'px')
  g_rml.setProperty(e.doc, 'window', 'top', math.max(0, r.y - e.dy) .. 'px')
  g_rml.setProperty(e.doc, 'window', 'width', r.width .. 'px')
  g_rml.setProperty(e.doc, 'window', 'min-height', r.height .. 'px')
  g_rml.setClass(e.doc, 'window', 'narrow', r.width < NARROW)
end

-- Pure: how far a grown mirror moves up to stay centred on the OTUI window (never above the screen top).
function M.centreShift(otuiY, otuiH, rmlH)
  if rmlH <= otuiH then return 0 end
  return math.min(otuiY, math.floor((rmlH - otuiH) / 2))
end

local function recentre(e)
  local rr = g_rml.getRect(e.doc, 'window')
  if not rr or rr.height == 0 then return end
  local dy = M.centreShift(e.pos.y, e.pos.height, rr.height)
  if dy ~= e.dy then
    e.dy = dy
    g_rml.setProperty(e.doc, 'window', 'top', (e.pos.y - dy) .. 'px')
  end
end

local function close(e)
  ChaosRmlForm.unlisten(e.doc)
  e.form.alive = false
  g_rml.close(e.doc)
  M.entries[e.key] = nil
  showOtui(e)
end

local function onEvent(e, elementId, eventType)
  if not M.entries[e.key] then return end
  if eventType == 'moved' and elementId == 'window' then
    local r = g_rml.getRect(e.doc, 'window')
    local y = r.y + (e.dy or 0)
    if not e.window:isDestroyed() then
      -- as an OTUI window drag does: a centred (anchored) window would snap back
      if e.window.breakAnchors then e.window:breakAnchors() end
      e.window:setPosition({ x = r.x, y = y })
    end
    e.pos.x, e.pos.y = r.x, y
    return
  end
  if eventType == 'click' and elementId == 'classic' then
    e.window.chaosRmlSkip = true
    M.skipped[e.key] = e.window
    close(e)
    return
  end
  e.form:handle(elementId, eventType)
end

M.skipped = M.skipped or {}   -- key -> OTUI window sent to the classic look

local function mirror(w, items)
  ChaosRmlForm.loadFonts()
  local doc = g_rml.loadDocument(PATH .. 'rmlmirror.rml')
  if doc == 0 then
    w.chaosRmlSkip = true
    M.skipped[M.keyOf(w)] = w
    return
  end
  local e = { window = w, key = M.keyOf(w), doc = doc, opacity = w:getOpacity(), phantom = w:isPhantom() }
  e.form = ChaosRmlForm.newForm(doc, 'content', w, {
    onEnter = function() if w.onEnter then signalcall(w.onEnter, w) end end,
    onEscape = function() if w.onEscape then signalcall(w.onEscape, w) end end,
  })
  M.entries[e.key] = e
  g_rml.setText(doc, 'title', ChaosRmlForm.textOf(w))
  g_rml.setText(doc, 'classic', tr('Classic'))
  ChaosRmlForm.listen(doc, function(id, ev) onEvent(e, id, ev) end)
  e.form:build(items)
  place(e)
  hideOtui(e)
  g_rml.show(doc)
end

local function roots()
  local list = { g_ui.getRootWidget() }
  local gi = modules and modules.game_interface
  if gi and gi.getRootPanel then
    local ok, p = pcall(gi.getRootPanel)
    if ok and p then list[#list + 1] = p end
  end
  return list
end

local function deny()
  local d = {}
  local cs = modules and modules.client_settings
  if cs and cs.optionsWindow then d[M.keyOf(cs.optionsWindow)] = true end
  return d
end

function M.tick()
  if not M.available() then return end
  if not M.enabled then
    for _, e in pairs(M.entries) do close(e) end
    return
  end
  -- windows that went away
  for _, e in pairs(M.entries) do
    local w = e.window
    if w:isDestroyed() or not w:isExplicitlyVisible() then close(e) end
  end
  -- a window the player sent to the classic look gets the mirror again the next time it opens
  for k, w in pairs(M.skipped) do
    if w:isDestroyed() or not w:isExplicitlyVisible() then
      if not w:isDestroyed() then w.chaosRmlSkip = nil end
      M.skipped[k] = nil
    end
  end
  local mirrored = {}
  for k in pairs(M.entries) do mirrored[k] = true end
  -- live ones: shape, values, place, and whether an OTUI window lies over them
  for _, e in pairs(M.entries) do
    local w = e.window
    local cover = M.covered(w, mirrored)
    if cover and not e.suspended then
      e.suspended = true
      g_rml.hide(e.doc)
      showOtui(e)
    elseif not cover then
      if e.suspended then
        e.suspended = false
        hideOtui(e)
        g_rml.show(e.doc)
      end
      if not e.form:changed() then e.form:refresh() end
      local r = w:getRect()
      if r.x ~= e.pos.x or r.y ~= e.pos.y or r.width ~= e.pos.width or r.height ~= e.pos.height then place(e) end
      recentre(e)
      local title = ChaosRmlForm.textOf(w)
      if e.title ~= title then e.title = title g_rml.setText(e.doc, 'title', title) end
    end
  end
  -- new ones
  local d = deny()
  for _, w in ipairs(M.candidates(roots())) do
    if not M.entries[M.keyOf(w)] and M.WINDOW_CLASSES[classOf(w)] and w:isExplicitlyVisible() then
      local items, why = M.eligible(w, d)
      if items then
        mirror(w, items)
      elseif M.debug and why ~= 'hidden' and w.chaosRmlWhy ~= why then
        w.chaosRmlWhy = why   -- logged once per window and reason
        g_logger.info('[rmlmirror] ' .. tostring(w:getId()) .. ' stays OTUI: ' .. tostring(why)) -- i18n-ok: log
      end
    end
  end
end

function M.setEnabled(on)
  M.enabled = on and true or false
  if g_settings and g_settings.set then g_settings.set('chaosRmlMirror', M.enabled) end
  M.tick()
end

function M.toggle()
  M.setEnabled(not M.enabled)
end

function init()
  if not g_rml then return end
  M.enabled = settingOn()
  M.debug = os.getenv and os.getenv('CHAOS_RMLMIRROR_DEBUG') ~= nil
  if g_keyboard then g_keyboard.bindKeyDown('Ctrl+Alt+M', M.toggle) end
  tickEvent = cycleEvent(M.tick, TICK_MS)
end

function terminate()
  if not g_rml then return end
  if tickEvent then removeEvent(tickEvent) tickEvent = nil end
  for _, e in pairs(M.entries) do close(e) end
  for _, w in pairs(M.skipped) do
    if not w:isDestroyed() then w.chaosRmlSkip = nil end
  end
  M.skipped = {}
  if g_keyboard then pcall(function() g_keyboard.unbindKeyDown('Ctrl+Alt+M', M.toggle) end) end
end
