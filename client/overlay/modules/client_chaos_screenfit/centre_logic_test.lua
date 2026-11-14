-- luajit centre_logic_test.lua && lua5.3 centre_logic_test.lua (from anywhere; CI runs it from the repo root)
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'centre_logic.lua')
local C = WindowCentreLogic
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- centring one axis and a rect
eq(C.centreAxis(300, 0, 1000), 350, 'centred')
eq(C.centreAxis(301, 0, 1000), 349, 'odd size rounds down')
eq(C.centreAxis(300, 40, 1000), 390, 'area offset')
eq(C.centreAxis(1200, 0, 1000), 0, 'too wide: start edge, title in view')
eq(C.centreAxis(1000, 0, 1000), 0, 'exact fit')
local p = C.centre({ width = 900, height = 536 }, { x = 0, y = 0, width = 1280, height = 720 })
eq(p.x, 190, 'forge x'); eq(p.y, 92, 'forge y')

-- origin and valid positions
local bounds = { x = 0, y = 38, width = 1280, height = 682 }
eq(C.atOrigin({ x = 0, y = 0 }, bounds), true, 'root origin')
eq(C.atOrigin({ x = 1, y = 39 }, bounds), true, 'origin of the usable area (under the bar)')
eq(C.atOrigin({ x = 0, y = 200 }, bounds), false, 'left edge, not the corner')
eq(C.atOrigin(nil, bounds), true, 'no position')
eq(C.validPosition({ x = 0, y = 0 }, { width = 300, height = 200 }, bounds), false, 'origin is not a position')
eq(C.validPosition({ x = 400, y = 200 }, { width = 300, height = 200 }, bounds), true, 'inside')
eq(C.validPosition({ x = 1270, y = 200 }, { width = 300, height = 200 }, bounds), false, 'off the right edge')
eq(C.validPosition({ x = 400, y = 700 }, { width = 300, height = 200 }, bounds), false, 'off the bottom edge')
eq(C.validPosition({ x = -280, y = 200 }, { width = 300, height = 200 }, bounds), false, 'off the left edge')
eq(C.validPosition({ x = -200, y = 200 }, { width = 300, height = 200 }, bounds), true, 'partly off but 100 px in view')
eq(C.validPosition({ x = 0, y = 0 }, { width = 1280, height = 720 }, bounds), false, 'a window as big as the screen at the corner is moved below the bar')
eq(C.validPosition({ x = 5, y = 5 }, { width = 300, height = 200 }, nil), true, 'no screen: leave it')
eq(C.validPosition({ x = 0 / 0, y = 5 }, { width = 300, height = 200 }, bounds), false, 'NaN')

-- saved positions
eq(C.keepSaved({ x = 0, y = 0 }, { width = 300, height = 200 }, bounds), false, 'saved (0,0) is dropped')
eq(C.keepSaved({ x = 400, y = 150 }, { width = 300, height = 200 }, bounds), true, 'a saved place is kept')
eq(C.keepSaved({ x = 5000, y = 150 }, { width = 300, height = 200 }, bounds), false, 'a saved place off the screen is dropped')
eq(C.keepSaved(nil, { width = 300, height = 200 }, bounds), false, 'nothing saved')

-- areas
local root = { x = 0, y = 0, width = 1280, height = 720 }
local u = C.usableArea(root, 38)
eq(u.y, 38, 'below the bar'); eq(u.height, 682, 'height without the bar')
eq(C.usableArea(root, nil).y, 0, 'no bar')
eq(C.usableArea(root, 9999).y, 0, 'a bar bottom outside the screen is ignored')
eq(C.usableArea({ x = 0, y = 0, width = 0, height = 0 }, 38), nil, 'root not laid out')
local a = C.centreArea(u, { x = 200, y = 0, width = 880, height = 720 })
eq(a.x, 200, 'map panel x'); eq(a.y, 38, 'map panel top cut by the bar'); eq(a.width, 880, 'map panel width')
eq(C.centreArea(u, nil), u, 'no map: the usable area')
eq(C.centreArea(u, { x = 2000, y = 0, width = 10, height = 10 }), u, 'map outside: the usable area')

-- a window as it opens
local function open(pos, size, extra)
  local info = { pos = pos, size = size, root = root, barBottom = 38 }
  for k, v in pairs(extra or {}) do info[k] = v end
  return C.openPosition(info)
end
local win = { width = 600, height = 400 }
local r = open({ x = 0, y = 0 }, win)
eq(r.x, 340, 'unanchored window: centred x'); eq(r.y, 38 + 141, 'unanchored window: centred below the bar')
eq(open({ x = 340, y = 179 }, win), nil, 'an anchored (centred) window is left alone')
eq(open({ x = 120, y = 90 }, win), nil, 'a place the player gave it is kept')
eq(open({ x = 0, y = 0 }, win, { moved = true }), nil, 'a window the player moved is never recentred')
r = open({ x = 0, y = 0 }, win, { map = { x = 200, y = 0, width = 880, height = 720 } })
eq(r.x, 340, 'centred in the map panel (same centre here)')
r = open({ x = 0, y = 0 }, win, { map = { x = 0, y = 0, width = 800, height = 720 } })
eq(r.x, 100, 'map panel left of the screen centre: its centre')
r = open({ x = 0, y = 0 }, { width = 780, height = 400 }, { map = { x = 0, y = 0, width = 800, height = 720 } })
eq(r.x, 10, 'a window almost as wide as the map panel')
r = open({ x = 0, y = 0 }, { width = 900, height = 536 }, { map = { x = 700, y = 0, width = 580, height = 720 } })
eq(r.x, 380, 'a window wider than the map panel stays on the screen (right edge)')
r = open({ x = 0, y = 0 }, { width = 1400, height = 900 })
eq(r.x, 0, 'larger than the screen: start edge x'); eq(r.y, 38, 'larger than the screen: just below the bar, title in view')
r = open({ x = 0, y = 0 }, { width = 1400, height = 400 })
eq(r.x, 0, 'too wide only: x at the edge'); eq(r.y, 38 + 141, 'too wide only: y centred')
eq(open({ x = 0, y = 0 }, { width = 1280, height = 720 }), nil, 'a window that fills the screen is left alone')
eq(open({ x = 0, y = 0 }, { width = 0, height = 0 }), nil, 'no size yet')
eq(open({ x = 0, y = 0 }, win, { root = { x = 0, y = 0, width = 0, height = 0 } }), nil, 'no screen yet')
r = C.openPosition({ pos = { x = 0, y = 0 }, size = win, root = root })
eq(r.y, 160, 'no bar: centred on the screen')
eq(open({ x = 9000, y = 9000 }, win) ~= nil, true, 'off the screen: centred')

if fails > 0 then error(fails .. ' failure(s)') end
print('centre_logic_test: OK')
