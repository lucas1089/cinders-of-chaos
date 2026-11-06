-- ChaosAltHelp: "Hold Alt for help" in tooltips (O372). Shared by the passive tree, item tooltips, the spellbook, the
-- helper's spell pickers and the buff bar.
-- Without Alt a tooltip stays short and ends with a hint line. With Alt it shows plain lines on what each part does.
-- Two parts:
--   * pure: A.lines / A.text join the short lines, the help lines and the hint (tested by althelp_test.lua);
--   * engine: one shared poll every 100 ms while a window wants it (A.watch / A.unwatch). On an Alt change each
--     watcher runs. A widget with widget.altTip = function(down) return text end gets that text as its tooltip while
--     it is hovered with Alt held, and its short text back after. The tooltip on screen is redrawn at once.
-- The module is sandboxed: the table is set on _G too. Modules read it with rawget(_G, 'ChaosAltHelp').
ChaosAltHelp = {}
local A = ChaosAltHelp
if rawget(_G, 'ChaosAltHelp') ~= A then _G.ChaosAltHelp = A end

A.POLL_MS = 100
A.PARENT_DEPTH = 4 -- how far up from the hovered widget an altTip is looked for (a row's label is hovered, not the row)

local function translate(tr)
  if type(tr) == 'function' then return tr end
  local g = rawget(_G, 'tr')
  if type(g) == 'function' then return g end
  return function(s, ...)
    if select('#', ...) > 0 then return string.format(s, ...) end
    return s
  end
end

-- the default hint line
function A.hint(tr)
  tr = translate(tr)
  return tr('Hold Alt for what each line does.')
end

-- texts: the short lines; extra: the help lines (may be empty or nil); altDown: Alt held now
-- hint: the hint line (nil: A.hint). Returns a new list: texts, then extra with Alt or the hint without it.
-- No help lines: no hint either.
function A.lines(texts, extra, altDown, tr, hint)
  local out = {}
  for _, line in ipairs(texts or {}) do
    out[#out + 1] = line
  end
  if extra and #extra > 0 then
    if altDown then
      for _, line in ipairs(extra) do
        out[#out + 1] = line
      end
    else
      out[#out + 1] = hint or A.hint(tr)
    end
  end
  return out
end

-- the same joined with newlines (a plain tooltip)
function A.text(texts, extra, altDown, tr, hint)
  return table.concat(A.lines(texts, extra, altDown, tr, hint), '\n')
end

-- a list without repeats, order kept (two modifiers of one group share one help line)
function A.unique(list)
  local out, seen = {}, {}
  for _, line in ipairs(list or {}) do
    if line and line ~= '' and not seen[line] then
      seen[line] = true
      out[#out + 1] = line
    end
  end
  return out
end

-- ---------------------------------------------------------------- engine part
local state = { down = false, shown = nil, watchers = {}, count = 0, event = nil }
A._state = state -- tests

local function alive(w)
  if not w then return false end
  local ok, dead = pcall(function() return w:isDestroyed() end)
  return ok and not dead
end

-- Alt held right now (false without a keyboard API)
function A.pressed()
  local kb = rawget(_G, 'g_keyboard')
  if not kb or not kb.isAltPressed then return false end
  local ok, down = pcall(kb.isAltPressed)
  return ok and down and true or false
end

-- the last polled state (what the tooltips were built for)
function A.isDown()
  return state.down
end

-- the widget that has its Alt text as tooltip now (nil: none)
function A.shown()
  return state.shown
end

-- the widget under the mouse (other modules: ChaosAltHelp.hovered())
local function hoveredWidget()
  local ui = rawget(_G, 'g_ui')
  if not ui then return nil end
  if ui.getHoveredWidget then -- not bound in our engine build
    local ok, w = pcall(ui.getHoveredWidget)
    if ok and w then return w end
  end
  -- fallback: the widget under the mouse, phantom widgets (labels on an icon) skipped
  local win = rawget(_G, 'g_window')
  if not ui.getRootWidget or not win or not win.getMousePosition then return nil end
  local ok, w = pcall(function()
    return ui.getRootWidget():recursiveGetChildByPos(win.getMousePosition(), false)
  end)
  return ok and w or nil
end

A.hovered = function() return hoveredWidget() end

-- the hovered widget, or a parent of it, that has an altTip
function A.tipOwner(widget)
  local w = widget
  for _ = 0, A.PARENT_DEPTH do
    if not alive(w) then return nil end
    if type(w.altTip) == 'function' then return w end
    local ok, parent = pcall(function() return w:getParent() end)
    w = ok and parent or nil
  end
  return nil
end

-- show a text in the tooltip on screen now (the engine shows a widget's tooltip only when the hover starts)
function A.redraw(text)
  local tip = rawget(_G, 'g_tooltip')
  if text and text ~= '' and tip and tip.displayText then
    pcall(tip.displayText, text)
  end
end

local function setTip(w, down)
  local ok, text = pcall(w.altTip, down)
  if ok and type(text) == 'string' then
    w:setTooltip(text)
    return text
  end
  return nil
end

-- one poll step: Alt state to the watchers, the hovered altTip widget
function A.poll()
  local down = A.pressed()
  if down ~= state.down then
    state.down = down
    for _, fn in pairs(state.watchers) do
      pcall(fn, down)
    end
  end
  local owner = down and A.tipOwner(hoveredWidget()) or nil
  if owner ~= state.shown then
    local old = state.shown
    state.shown = owner
    local text
    if alive(old) then text = setTip(old, false) end
    if owner then text = setTip(owner, true) end
    -- the text on screen: the new owner's, or the old one's short text while it is still hovered
    if owner or (old and A.tipOwner(hoveredWidget()) == old) then A.redraw(text) end
  end
end

-- fn(down) runs on every Alt change while key is watched; the poll runs while anything is watched
function A.watch(key, fn)
  if state.watchers[key] == nil then state.count = state.count + 1 end
  state.watchers[key] = fn or function() end
  if not state.event then
    local cycle = rawget(_G, 'cycleEvent')
    if cycle then state.event = cycle(A.poll, A.POLL_MS) end
  end
end

function A.unwatch(key)
  if state.watchers[key] == nil then return end
  state.watchers[key] = nil
  state.count = state.count - 1
  if state.count <= 0 then
    state.count = 0
    if state.event then
      local remove = rawget(_G, 'removeEvent')
      if remove then remove(state.event) end
      state.event = nil
    end
    if alive(state.shown) then setTip(state.shown, false) end
    state.shown = nil
    state.down = false
  end
end

-- module unload: no poll left behind
function A.stop()
  for key in pairs(state.watchers) do A.unwatch(key) end
end

return A
