-- luajit dragguard_test.lua && lua5.3 dragguard_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'dragguard.lua')
local G = ChaosDragGuard
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

eq(G.interactiveClass('UIButton'), true, 'a button keeps its press')
eq(G.interactiveClass('UICheckBox'), true, 'a check box keeps its press')
eq(G.interactiveClass('UIWidget'), false, 'a plain widget does not')
eq(G.interactiveClass('UILabel'), false, 'a label does not')
eq(G.interactiveClass(nil), false, 'nil class')
eq(G.isStale(false, true), true, 'button up is stale')
eq(G.isStale(true, false), true, 'out of focus is stale')
eq(G.isStale(true, true), false, 'a live drag is not stale')
eq(G.isStale(nil, nil), false, 'unknown state is not stale')

-- onChild on a tiny widget tree: header > button > icon, header > label
local function node(class, parent) return { class = class, parent = parent } end
local header = node('UIWidget')
local button = node('UIButton', header)
local label = node('UILabel', header)
local inner = node('UIWidget', button)
for _, n in ipairs({ header, button, label, inner }) do
  n.getClassName = function(self) return self.class end
  n.getParent = function(self) return self.parent end
end
local under
header.recursiveGetChildByPos = function() return under end
under = button;  eq(G.onChild(header, { x = 1, y = 1 }), true, 'a press on a button belongs to the button')
under = inner;   eq(G.onChild(header, { x = 1, y = 1 }), true, 'a press on a child of a button belongs to the button')
under = label;   eq(G.onChild(header, { x = 1, y = 1 }), false, 'a press on a label may drag')
under = nil;     eq(G.onChild(header, { x = 1, y = 1 }), false, 'a press on nothing may drag')
under = header;  eq(G.onChild(header, { x = 1, y = 1 }), false, 'a press on the header itself may drag')
eq(G.onChild(nil, { x = 1, y = 1 }), false, 'no source')
eq(G.onChild(header, nil), false, 'no position')

-- stale() from the engine globals
g_mouse = { isPressed = function() return false end }
MouseLeftButton = 1
eq(G.stale(), true, 'stale: the left button is up')
g_mouse = { isPressed = function() return true end }
g_window = { hasFocus = function() return true end }
eq(G.stale(), false, 'not stale: button down, window focused')
g_window = { hasFocus = function() return false end }
eq(G.stale(), true, 'stale: the window lost focus')
g_mouse, g_window = nil, nil
eq(G.stale(), false, 'no engine: never stale')

if fails == 0 then print('dragguard_test: ok') end
os.exit(fails == 0 and 0 or 1)
