-- luajit chatpanel_test.lua && lua5.3 chatpanel_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chatpanel_logic.lua')
local L = ChaosChatLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- Enter / Shift+Enter
eq(L.enterAction({ text = '', temporary = true }), 'close', 'empty Chat On* closes')
eq(L.enterAction({ text = '', persistent = true }), 'close', 'empty Chat On closes')
eq(L.enterAction({ text = '   ', persistent = true }), 'close', 'spaces count as empty')
eq(L.enterAction({ text = 'hi', temporary = true }), 'send_close', 'Chat On* sends then closes')
eq(L.enterAction({ text = 'hi', persistent = true }), 'send', 'Chat On sends and stays')
eq(L.enterAction({ text = 'hi', persistent = true, temporary = true }), 'send', 'persistent wins')
eq(L.enterAction({ text = '' }), 'none', 'chat not open')
eq(L.enterAction(nil), 'none', 'no state')

-- width: the default on a big window, the room on a small one, never under the minimum otherwise
eq(L.clampWidth(nil, 1700), L.DEFAULT_WIDTH, 'default width')
eq(L.clampWidth(5000, 1700), 1700, 'not wider than the room')
eq(L.clampWidth(100, 1700), L.MIN_WIDTH, 'minimum width')
eq(L.clampWidth(760, 500), 500, 'small window')
eq(L.clampWidth(760, 300), 300, 'tiny window: the room wins over the minimum')
eq(L.marginRightFor(760, 1700, 1), 1 + 940, 'margin leaves the width')
eq(L.marginRightFor(760, 600, 1), 1, 'no margin when it does not fit')

-- height: the splitter minimum, a share of the window at most
eq(L.clampHeight(nil, 150, 1340), 150 + L.DEFAULT_EXTRA_HEIGHT, 'new character: minimum + a few lines')
eq(L.clampHeight(100, 150, 1340), 150, 'not under the minimum')
eq(L.clampHeight(2000, 150, 1340), math.floor(1340 * L.MAX_HEIGHT_SHARE), 'not over the share')
eq(L.clampHeight(400, 150, 200), 150, 'a tiny window keeps the minimum')

-- saved sizes per character
local saved = { Alice = { width = 600, height = 180 } }
eq(L.sizeFor(saved, 'Alice').width, 600, 'saved width')
eq(L.sizeFor(saved, 'Alice').height, 180, 'saved height')
eq(L.sizeFor(saved, 'Bob').width, L.DEFAULT_WIDTH, 'new character width')
eq(L.sizeFor(saved, 'Bob').height, nil, 'new character height: default')
eq(L.sizeFor(nil, 'Bob').width, L.DEFAULT_WIDTH, 'nothing saved')

if fails > 0 then os.exit(1) end
print('chatpanel tests OK')
