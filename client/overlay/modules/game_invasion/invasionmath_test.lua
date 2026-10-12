-- luajit invasionmath_test.lua && lua5.3 invasionmath_test.lua (CI runs every client/overlay/modules/*/*_test.lua)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'invasionmath.lua')
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local M = InvasionMath
eq(M.clock(725), '12:05', 'clock')
eq(M.clock(nil), '0:00', 'clock nil')
eq(M.left(100, 10, 15), 95, 'left')
eq(M.left(3, 10, 20), 0, 'left not negative')
eq(M.countdown(0), 'now', 'countdown now')
eq(M.countdown(2 * 86400 + 3 * 3600), 'in 2d 3h', 'countdown days')
eq(M.countdown(5 * 3600 + 12 * 60), 'in 5h 12m', 'countdown hours')
eq(M.countdown(30), 'in 1m', 'countdown under a minute')
eq(M.title({ area = 'Cinderhold' }), 'Invasion: Cinderhold', 'title')
eq(M.title({ area = 'Cinderhold', phase = 'occupied' }), 'Cinderhold is occupied', 'title occupied')
eq(M.subtitle({ faction = 'Orc Warband', target = 'the temple steps' }), 'Orc Warband - defend the temple steps', 'subtitle')
eq(M.waveLine({ wave = 3, waves = 5, left = 14 }), 'Wave 3 of 5 - 14 invaders left', 'wave line')
eq(M.waveLine({ wave = 5, waves = 5, left = 1 }), 'Wave 5 of 5 - 1 invader left', 'wave line singular')
eq(M.waveLine({ wave = 0, waves = 5, next = 25 }), 'Wave 1 of 5 in 0:25', 'first wave countdown')
eq(M.waveLine({ phase = 'occupied', left = 7 }), '7 occupiers left', 'occupiers')
eq(M.breachColor(10), '#b08a20', 'breach low')
eq(M.breachColor(55), '#d86a10', 'breach mid')
eq(M.breachColor(90), '#d01818', 'breach high')
local top = M.topLines({ { name = 'A', share = 50 }, { name = 'B', share = 30 } })
eq(#top, 2, 'top lines')
eq(top[1], '1. A  50%', 'top line')
eq(#M.topLines(nil), 0, 'top nil')
eq(M.youLine({ rank = 2, share = 12, kills = 1 }), 'You: #2, 12% of the defence, 1 kill', 'you')
eq(M.youLine(nil), 'You: not in the defence yet', 'you nil')
eq(M.resultColor('win'), '#7fd07f', 'win colour')
eq(M.resultColor('breach'), '#ff5030', 'loss colour')
eq(M.kindColor('storm'), '#b07aff', 'kind colour')
eq(M.kindColor('x'), '#d6c9ae', 'kind default')

-- placement: the measured layouts (screen rects) of 1280x720, 1366x768 and 1920x1080
local plate = { x = 34, y = 40, width = 300, height = 96 }
eq(M.columnTop(plate, -120), 144, 'column under the plate')
eq(M.columnTop(nil, -120), 40, 'no plate: 40 px into the visible view')
local function overlaps(a, b)
  return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end
for _, L in ipairs({
  { name = '1280x720', view = { x = 0, y = -80, width = 1280, height = 800 }, buff = { x = 335, y = 44, width = 64, height = 42 },
    party = { x = 894, y = 226, width = 200, height = 120 }, strip = { x = 758, y = 502, width = 336, height = 44 }, bottom = 554 },
  { name = '1366x768', view = { x = 0, y = -85, width = 1366, height = 853 }, buff = { x = 335, y = 39, width = 64, height = 42 },
    party = { x = 980, y = 244, width = 200, height = 120 }, strip = { x = 844, y = 550, width = 336, height = 44 }, bottom = 602 },
  { name = '1920x1080', view = { x = 0, y = -120, width = 1920, height = 1200 }, buff = { x = 335, y = 4, width = 64, height = 42 },
    party = { x = 1534, y = 356, width = 200, height = 120 }, strip = { x = 1398, y = 862, width = 336, height = 44 }, bottom = 914 },
}) do
  local zone = M.characterZone(L.view)
  local obstacles = { plate, L.buff, L.party, L.strip, zone }
  local top = M.columnTop(plate, L.view.y)
  -- alone (40 px from the left) and beside a 230 px rift HUD; folded (110 px) and full with a result (260 px)
  for _, case in ipairs({ { x = 40, h = 110 }, { x = 40, h = 260 }, { x = 40 + 230 + 8, h = 260 } }) do
    local x, y = M.place(case.x, top, 270, case.h, obstacles, L.bottom)
    local what = L.name .. ' x ' .. case.x .. ' h ' .. case.h
    eq(x ~= nil, true, what .. ': a spot')
    if x then
      local r = { x = x, y = y, width = 270, height = case.h }
      for i, o in ipairs(obstacles) do eq(overlaps(r, o), false, what .. ': clear of obstacle ' .. i) end
      eq(y + case.h <= L.bottom, true, what .. ': above the console')
      eq(y, 144, what .. ': right under the plate')
    end
  end
end
-- an obstacle in the column: the HUD goes below it; no room: nil
local x, y = M.place(40, 144, 270, 100, { { x = 0, y = 150, width = 400, height = 50 } }, 600)
eq(y, 208, 'below an obstacle in the column')
eq(M.place(40, 144, 270, 500, { { x = 0, y = 150, width = 400, height = 50 } }, 600), nil, 'no room')
eq(select(2, M.place(40, 144, 270, 100, { { x = 400, y = 150, width = 100, height = 50 } }, 600)), 144, 'obstacle beside: no move')

if fails > 0 then os.exit(1) end
print('invasionmath tests OK')
