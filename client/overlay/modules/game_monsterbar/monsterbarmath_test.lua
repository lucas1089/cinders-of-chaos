-- luajit monsterbarmath_test.lua && lua5.3 monsterbarmath_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'monsterbarmath.lua')
local M = MonsterBarMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local W, H = 420, 86 -- the bar (monsterbar.otui)
local function rects(t)
  return function(id) return t[id] end
end

-- extended view at 1280x720: the map panel is 1280x800 at y -80, the menu bar covers y 0..38
local root = { x = 0, y = 0, width = 1280, height = 720 }
local panel = { x = 0, y = -80, width = 1280, height = 800 }
local limits = M.screenLimits(root, rects({
  chaosMenuBar = { x = 346, y = 0, width = 588, height = 38 },
  gameRightPanels = { x = 1103, y = 0, width = 177, height = 720 },
}))
eq(limits.top, 38, '1280x720: below the menu bar')
eq(limits.right, 1103, '1280x720: left of the right panels')
local top, offset = M.place(panel, limits, W, H)
eq(panel.y + top, 38 + M.GAP, '1280x720: bar top on screen, under the menu bar')
eq(offset, 0, '1280x720: centred over the character')
eq(panel.y + top >= 0, true, '1280x720: never above the window')

-- 1920x1080: the panel starts at y -120
panel = { x = 0, y = -120, width = 1920, height = 1200 }
limits = M.screenLimits({ x = 0, y = 0, width = 1920, height = 1080 }, rects({
  chaosMenuBar = { x = 666, y = 0, width = 588, height = 38 } }))
top, offset = M.place(panel, limits, W, H)
eq(panel.y + top, 38 + M.GAP, '1920x1080: under the menu bar')
eq(offset, 0, '1920x1080: centred')

-- classic view: the panel lies inside the window, below its top; the menu bar is not over it
panel = { x = 180, y = 50, width = 900, height = 500 }
limits = M.screenLimits({ x = 0, y = 0, width = 1280, height = 720 }, rects({
  chaosMenuBar = { x = 346, y = 0, width = 588, height = 38 },
  gameLeftPanels = { x = 0, y = 0, width = 180, height = 720 },
  gameBottomPanel = { x = 180, y = 560, width = 900, height = 160 } }))
top, offset = M.place(panel, limits, W, H)
eq(top, M.GAP, 'classic: just below the panel top')
eq(offset, 0, 'classic: centred')

-- no menu bar, nothing else: the window top
top = M.place({ x = 0, y = -80, width = 1280, height = 800 }, M.screenLimits(root, rects({})), W, H)
eq(top, 80 + M.GAP, 'no menu bar: window top')

-- a menu bar lower than 60 px is not a top bar
limits = M.screenLimits(root, rects({ chaosMenuBar = { x = 0, y = 300, width = 100, height = 30 } }))
eq(limits.top, 0, 'a lower bar is ignored')

-- a narrow visible part: the bar moves sideways to stay on screen
top, offset = M.place({ x = 0, y = 0, width = 1000, height = 600 }, { left = 0, right = 700, top = 0, bottom = 600 }, W, H)
eq(offset, 700 - W - (500 - W / 2), 'right panel over the centre: moved left')
top, offset = M.place({ x = 0, y = 0, width = 1000, height = 600 }, { left = 400, right = 1000, top = 0, bottom = 600 }, W, H)
eq(offset, 400 + W / 2 - 500, 'left panel over the centre: moved right')

-- a very short view: as high as it fits, never above the visible top
top = M.place({ x = 0, y = 0, width = 800, height = 90 }, { top = 0, bottom = 90 }, W, H)
eq(top, 4, 'short view: fits at the bottom')
top = M.place({ x = 0, y = 0, width = 800, height = 50 }, { top = 0, bottom = 50 }, W, H)
eq(top, 0, 'shorter than the bar: at the top')

-- the character plate (40..325 x 55..125) reaches under a centred bar at 1024 px: the bar moves right of it
local plate = { x = 40, y = 55, width = 285, height = 70 }
panel = { x = 0, y = -59, width = 1024, height = 827 }
limits = { left = 0, right = 848, top = 38, bottom = 560 }
top, offset = M.place(panel, limits, W, H, nil, { plate })
eq(panel.y + top, 38 + M.GAP, '1024: same height')
eq(512 + offset - W / 2, 325 + M.GAP, '1024: right of the plate')
-- at 1280 the centred bar clears the plate: unchanged
panel = { x = 0, y = -80, width = 1280, height = 800 }
top, offset = M.place(panel, { left = 0, right = 1103, top = 38, bottom = 520 }, W, H, nil, { plate })
eq(offset, 0, '1280: plate clear, centred')
-- no room right of the plate: below it
panel = { x = 0, y = 0, width = 700, height = 600 }
top, offset = M.place(panel, { left = 0, right = 700, top = 0, bottom = 600 }, W, H, nil, { plate })
eq(top, 125 + M.GAP, 'narrow: below the plate')
-- an empty or hidden rect changes nothing
top, offset = M.place(panel, { left = 0, right = 700, top = 0, bottom = 600 }, W, H, nil, { { x = 0, y = 0, width = 0, height = 0 } })
eq(top, M.GAP, 'empty rect ignored')

-- O351: draw sizes
local jug = { -11, 10, -101, -95, 28, 5, 5, 0, 49 } -- look 1423 (Inferno Juggernaut), 5x5
local small = { 16, 21, -8, -8, 23, 1, 1, 0, 15 } -- a 1x1 look
local twoByTwo = { 12, 22, -28, 1, 32, 2, 2, 0, 12 }
local w, h = M.bodySize(jug)
eq(w, 123, 'juggernaut body width'); eq(h, 111, 'juggernaut body height')
eq(M.drawScale(jug, nil, nil), 0.61, 'an oversized monster is shrunk to fit')
eq(M.drawScale(jug, 'elite', nil), 0.61, 'an elite is no boss: shrunk too')
eq(M.drawScale(jug, 'boss', nil), M.BOSS_SCALE, 'a boss keeps its size, bigger')
eq(M.drawScale(jug, nil, 'omen'), M.BOSS_SCALE, 'an omen is drawn as a boss')
eq(M.drawScale(jug, nil, 'guardian'), 1, 'a rift guardian keeps its art')
eq(M.drawScale(small, nil, nil), 1, 'a small look stays')
eq(M.drawScale(twoByTwo, 'normal', nil), 1, 'a 2x2 look stays')
eq(M.drawScale(nil, nil, nil), 1, 'no anchor: as drawn')
eq(M.drawScale({ 1, 2 }, nil, nil), 1, 'junk anchor: as drawn')
eq(M.drawScale({ 0, 10, -400, -300, 300, 9, 9, 0, 0 }, nil, nil), M.SCALE_MIN, 'never below the engine floor')
eq(M.isOversized(jug), true, 'oversized'); eq(M.isOversized(small), false, 'not oversized')

print(string.format('monsterbar math: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
