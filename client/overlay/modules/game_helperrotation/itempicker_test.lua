-- luajit itempicker_test.lua && lua5.3 itempicker_test.lua (from the repository root or this folder)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local log = {}
local escape = nil
ChaosItemPicker = { env = {
  setGrabber = function(w) log[#log + 1] = 'grab:' .. w.name end,
  releaseGrabber = function(w) log[#log + 1] = 'release:' .. w.name end,
  pushCursor = function() log[#log + 1] = 'push' end,
  popCursor = function() log[#log + 1] = 'pop' end,
  bindEscape = function(f) escape = f end,
  unbindEscape = function(f) if escape == f then escape = nil end end,
  rightButton = function() return 2 end,
  leftButton = function() return 1 end,
} }
dofile(dir .. 'itempicker.lua')
local P = ChaosItemPicker
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function count(what)
  local n = 0
  for _, v in ipairs(log) do if v == what then n = n + 1 end end
  return n
end

-- a slot like the helper's: its release handler ungrabs, calls finish, then reads what is under the mouse
local picked
local function slot(name)
  local g = { name = name }
  g.onMouseRelease = function(self, pos, button)
    P.finish(self)
    picked = (pos.x >= 0) and (name .. '@' .. pos.x) or 'nothing'
    return true
  end
  P.begin(g)
  return g
end

-- start: the system cursor (setGrabber, like Use with) and the software cursor
local g = slot('potion')
eq(P.isActive(), true, 'picker active')
eq(log[1], 'grab:potion', 'setGrabber sets the system target cursor')
eq(count('push'), 1, 'cursor pushed once')
eq(escape ~= nil, true, 'Escape bound')
-- a left click picks
g.onMouseRelease(g, { x = 40, y = 10 }, 1)
eq(picked, 'potion@40', 'left click picks the item under the mouse')
eq(count('pop'), 1, 'cursor popped once')
eq(count('release:potion'), 1, 'grabber cursor released once')
eq(P.isActive(), false, 'picker over')
eq(escape, nil, 'Escape unbound')
P.finish(g)
eq(count('pop'), 1, 'a second finish pops nothing')

-- a right click cancels: the handler runs off the window and picks nothing
log, picked = {}, nil
g = slot('rune')
g.onMouseRelease(g, { x = 40, y = 10 }, 2)
eq(picked, 'nothing', 'right click picks nothing')
eq(count('pop'), 1, 'right click: cursor back')
eq(P.isActive(), false, 'right click ends the picker')
eq(P.cancelling, false, 'cancelling flag cleared')

-- Escape cancels
log, picked = {}, nil
g = slot('timer')
escape()
eq(picked, 'nothing', 'Escape picks nothing')
eq(count('pop'), 1, 'Escape: cursor back')
eq(P.isActive(), false, 'Escape ends the picker')

-- a handler that never calls finish still gets the cursor back on cancel
log, picked = {}, nil
local h = { name = 'old' }
h.onMouseRelease = function() return true end
P.begin(h)
escape()
eq(count('pop'), 1, 'cancel finishes for a handler without finish')

-- a second picker while one runs: the first is cancelled, one cursor on the stack
log, picked = {}, nil
slot('food')
local g2 = slot('tool')
eq(picked, 'nothing', 'the first picker is cancelled')
eq(count('push') - count('pop'), 1, 'one cursor pushed at a time')
g2.onMouseRelease(g2, { x = 5, y = 5 }, 1)
eq(picked, 'tool@5', 'the second picker picks')
eq(count('push') - count('pop'), 0, 'balanced pushes and pops')

if fails > 0 then error(fails .. ' failure(s)') end
print('itempicker_test: OK')
