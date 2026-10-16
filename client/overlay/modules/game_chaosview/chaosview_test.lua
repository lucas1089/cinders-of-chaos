-- luajit chaosview_test.lua && lua5.3 chaosview_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'chaosview_logic.lua')
local L = ChaosViewLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- the server's default area (17 x 13, the client reports 18 x 14): a 2000 x 1340 window was held at 11 rows
eq(L.maxZoomOut(18, 14, 2000 / 1340), 11, 'default area: 11 rows')
-- the largest area (29 x 21, reported 30 x 22): room for 15 rows and more
eq(L.maxZoomOut(30, 22, 2000 / 1340), 19, 'largest area on 2000 x 1340')
eq(L.maxZoomOut(30, 22, 21 / 9), 11, 'ultra wide: width limits')
eq(L.maxZoomOut(4, 4, 10), 3, 'never under 3')

-- default zoom: about 72 px per tile, 11 to 15 rows
eq(L.defaultZoom(1340, 19), 15, '2000 x 1340: 15 rows (89 px tiles), not 11 (122 px)')
eq(L.defaultZoom(768, 19), 11, 'small window: the classic 11 rows')
eq(L.defaultZoom(1000, 19), 13, 'medium window')
eq(L.defaultZoom(2160, 19), 15, '4k: still 15 rows at most')
eq(L.defaultZoom(1340, 11), 11, 'held by what the server sends')
eq(L.defaultZoom(0, nil), 11, 'no size yet')
eq(L.defaultZoom(1340, 19) % 2, 1, 'odd rows')

-- a saved zoom wins, inside the limit
eq(L.zoomFor(17, 1340, 19), 17, 'saved zoom')
eq(L.zoomFor(21, 1340, 19), 19, 'saved zoom clamped')
eq(L.zoomFor(nil, 1340, 19), 15, 'new player: default')
eq(L.zoomFor(1, 1340, 19), 15, 'bad saved value: default')

if fails > 0 then os.exit(1) end
print('chaosview tests OK')
