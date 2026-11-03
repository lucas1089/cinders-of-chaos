-- luajit / lua5.3, from the repo root: client/overlay/modules/client_chaos_theme/althelp_test.lua
local dir = (arg and arg[0] or ''):match('^(.*)/[^/]*$') or '.'
dofile(dir .. '/althelp.lua')
local A = ChaosAltHelp
local function tr(s, ...) if select('#', ...) > 0 then s = string.format(s, ...) end return '<' .. s .. '>' end
local function eq(a, b, msg)
  assert(#a == #b, msg .. ': count ' .. #a .. ' ~= ' .. #b)
  for i = 1, #a do assert(a[i] == b[i], msg .. ': line ' .. i .. ' ' .. tostring(a[i]) .. ' ~= ' .. tostring(b[i])) end
end

-- pure lines
local base = { 'Dodge +5%', 'Item Level 40' }
local extra = { 'Dodge: a chance that a hit misses you.' }
eq(A.lines(base, extra, false, tr), { 'Dodge +5%', 'Item Level 40', '<Hold Alt for what each line does.>' }, 'no alt')
eq(A.lines(base, extra, true, tr), { 'Dodge +5%', 'Item Level 40', 'Dodge: a chance that a hit misses you.' }, 'alt')
eq(A.lines(base, extra, false, tr, 'own hint'), { 'Dodge +5%', 'Item Level 40', 'own hint' }, 'own hint')
eq(A.lines(base, {}, false, tr), base, 'no help, no hint')
eq(A.lines(base, nil, true, tr), base, 'nil help')
eq(A.lines(nil, extra, true, tr), extra, 'nil texts')
assert(#base == 2 and #extra == 1, 'inputs untouched')
assert(A.text({ 'a' }, { 'b' }, true, tr) == 'a\nb', 'text joins')
eq(A.unique({ 'a', 'b', 'a', '', 'c', 'b' }), { 'a', 'b', 'c' }, 'unique')

-- engine part with a fake keyboard, hover, tooltip and events
local alt = false
g_keyboard = { isAltPressed = function() return alt end }
local hovered
g_ui = { getHoveredWidget = function() return hovered end }
local shownText
g_tooltip = { displayText = function(t) shownText = t end }
local events = {}
cycleEvent = function(fn, ms) events[#events + 1] = fn return #events end
local removed = {}
removeEvent = function(id) removed[#removed + 1] = id end

local function widget(parent)
  local w = { tip = nil, parent = parent }
  function w:isDestroyed() return false end
  function w:setTooltip(t) self.tip = t end
  function w:getTooltip() return self.tip end
  function w:getParent() return self.parent end
  return w
end

local row = widget(nil)
row.altTip = function(down) return down and 'long' or 'short' end
row:setTooltip('short')
local label = widget(row) -- the row's label is what the mouse is over
local other = widget(nil)

local changes = {}
A.watch('test', function(down) changes[#changes + 1] = down end)
assert(#events == 1, 'poll started')
A.watch('test2')
assert(#events == 1, 'one poll for every watcher')

hovered = label
A.poll()
assert(row.tip == 'short' and shownText == nil and #changes == 0, 'no alt: nothing')
alt = true
A.poll()
assert(changes[1] == true and A.isDown(), 'watcher told')
assert(row.tip == 'long' and shownText == 'long', 'hovered parent gets the long text, redrawn')
A.poll()
assert(#changes == 1, 'no change, no call')
hovered = other
A.poll()
assert(row.tip == 'short', 'left the row: short text back')
hovered = label
A.poll()
assert(row.tip == 'long', 'back on the row with Alt')
alt = false
shownText = nil
A.poll()
assert(changes[2] == false and row.tip == 'short' and shownText == 'short', 'Alt up: short text redrawn')

A.unwatch('test')
assert(#removed == 0, 'still watched')
A.unwatch('test2')
assert(#removed == 1 and A._state.event == nil, 'poll stopped')
A.unwatch('nothing')

-- no keyboard API: never down
g_keyboard = nil
assert(A.pressed() == false, 'no keyboard')
print('althelp_test: ok')
