-- luajit tradewindowlogic_test.lua && lua5.3 tradewindowlogic_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'tradewindowlogic.lua')
local L = TradeWindowLogic
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local g = L.geometry(1920, 1080, 0)
eq(g.w, 420, 'full width on a big view'); eq(g.h, 520, 'full height on a big view')
eq(g.x, 750, 'centred x'); eq(g.y, 280, 'centred y')
g = L.geometry(1920, 1080, 40)
eq(g.y, 40 + math.floor((1080 - 40 - 520) / 2), 'centred under the menu bar')
g = L.geometry(800, 600, 0)
eq(g.w, 420, 'width fits'); eq(g.h, 520, 'height fits')
g = L.geometry(400, 400, 30)
eq(g.w, 352, 'narrow view: width less the margins'); eq(g.h, 322, 'short view: height less the margins')
eq(g.x >= 0, true, 'x never negative'); eq(g.y >= 30, true, 'y never above the bar')
g = L.geometry(200, 200, 0)
eq(g.w, 300, 'tiny view: minimum width'); eq(g.h, 300, 'tiny view: minimum height'); eq(g.x, 0, 'x clamped at 0')
g = L.geometry(nil, nil, nil)
eq(g.w, 300, 'bad input: minimum'); eq(g.x, 0, 'bad input x')
eq(L.needsFloat(true, false), true, 'shown in a side panel: float')
eq(L.needsFloat(true, true), false, 'already floating')
eq(L.needsFloat(false, false), false, 'hidden: nothing to do')

print('npctradewindow tests OK (' .. checks .. ' checks)')
if fails > 0 then os.exit(1) end
