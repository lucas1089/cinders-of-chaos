-- luajit cursorowner_test.lua && lua5.3 cursorowner_test.lua (from the repository root or this folder)
-- Base patch 0083 (client/base-patches/0083-use-with-cursor-kept.patch) changes corelib/mouse.lua, which is not in the
-- repository. The patch carries the whole file as one hunk, so the new text is rebuilt from it here (context and added
-- lines) and run against a mocked g_mouse / g_window: the cursor of the active grabber (Use with, the item picker)
-- is kept while a border, a splitter or a link asks for its own.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
local path = dir .. '../../../base-patches/0083-use-with-cursor-kept.patch'
local f = assert(io.open(path, 'r'), 'cannot open ' .. path)
local out, inHunk = {}, false
for line in f:lines() do
  if line:match('^@@') then
    inHunk = true
  elseif inHunk then
    local c = line:sub(1, 1)
    if c == ' ' or c == '+' then out[#out + 1] = line:sub(2) end
  end
end
f:close()
local text = table.concat(out, '\n') .. '\n'

local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local calls
local native = true
g_mouse = {
  isUsingNativeCursor = function() return native end,
  isPressed = function() return false end,
}
g_window = {
  setSystemCursor = function(name) calls[#calls + 1] = 'set:' .. name end,
  restoreMouseCursor = function() calls[#calls + 1] = 'restore' end,
}
local chunk = assert((loadstring or load)(text, '@0083 mouse.lua'))
chunk()
local function reset() calls = {} end
local function last() return calls[#calls] end

local grabber = { destroyed = false, isDestroyed = function(self) return self.destroyed end }
local other = { isDestroyed = function() return false end }

-- no selection: a border shows its arrow and gives the default back (unchanged behaviour)
reset()
eq(g_mouse.applyNativeCursor('vertical'), true, 'apply without a grabber')
eq(last(), 'set:vertical', 'a border shows its resize arrow')
eq(g_mouse.restoreNativeCursor(), true, 'restore without a grabber')
eq(last(), 'restore', 'the default cursor comes back')
eq(g_mouse.getActiveGrabberCursor(), nil, 'no grabber, no owner')

-- Use with: the target cursor ('cross') is set by setGrabber and kept
reset()
g_mouse.setGrabber(grabber, 'target')
eq(last(), 'set:cross', 'setGrabber sets the system target cursor')
eq(g_mouse.getActiveGrabberCursor(), 'target', 'the grabber owns the cursor')
reset()
g_mouse.applyNativeCursor('vertical')
eq(last(), 'set:cross', 'a border over the pointer does not replace the target cursor')
g_mouse.applyNativeCursor('horizontal')
eq(last(), 'set:cross', 'neither does a splitter')
g_mouse.applyNativeCursor('pointer')
eq(last(), 'set:cross', 'neither does a chat link')
reset()
eq(g_mouse.restoreNativeCursor(), true, 'restore during a selection')
eq(last(), 'set:cross', 'leaving a border puts the target cursor back, not the default arrow')
eq(#calls, 1, 'restore did not also reset the window cursor')
-- the popup menu asks for the plain arrow
reset()
g_mouse.applyNativeCursor('')
eq(last(), 'set:', 'an empty name is honoured (popup menus)')

-- the selection ends: borders work as before and the default cursor comes back
reset()
eq(g_mouse.releaseGrabber(grabber), 'target', 'releaseGrabber returns the cursor name')
eq(last(), 'restore', 'the default cursor comes back at the end')
g_mouse.applyNativeCursor('vertical')
eq(last(), 'set:vertical', 'borders show their arrow again')

-- a second grabber with a cursor of its own (the picker) is the owner too
reset()
g_mouse.setGrabber(other, 'target')
g_mouse.applyNativeCursor('horizontal')
eq(last(), 'set:cross', 'the item picker keeps its cursor')
g_mouse.releaseGrabber(other)

-- a destroyed grabber (its window closed in the selection) no longer owns the cursor
reset()
g_mouse.setGrabber(grabber, 'target')
grabber.destroyed = true
eq(g_mouse.getActiveGrabberCursor(), nil, 'a destroyed grabber owns nothing')
g_mouse.applyNativeCursor('vertical')
eq(last(), 'set:vertical', 'and a border works again')
eq(g_mouse.grabbedMouse[grabber], nil, 'it is dropped from the table')

-- software cursors (not native): untouched, nothing is set
native = false
reset()
eq(g_mouse.applyNativeCursor('vertical'), false, 'not native: apply is declined')
eq(g_mouse.restoreNativeCursor(), false, 'not native: restore is declined')
eq(#calls, 0, 'not native: the window is not touched')

if fails == 0 then print('cursorowner_test ok') else os.exit(1) end
