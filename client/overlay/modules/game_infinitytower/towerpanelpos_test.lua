-- luajit towerpanelpos_test.lua && lua5.3 towerpanelpos_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'towerpanelpos.lua')
local M = TowerPanelPos
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

-- key per character
eq(M.key('Ember', 'Knight'), 'Ember/Knight', 'key world/name')
eq(M.key(nil, 'Knight'), '-/Knight', 'key without world')
eq(M.key('Ember', ''), nil, 'no name: no key')
eq(M.key('Ember', nil), nil, 'nil name: no key')

-- parse: numbers, strings from g_settings, junk
local p = M.parse({ x = 120, y = 33 })
eq(p.x, 120, 'parse x'); eq(p.y, 33, 'parse y')
p = M.parse({ x = '120', y = '33.7' })
eq(p.x, 120, 'parse string x'); eq(p.y, 33, 'parse string y floored')
eq(M.parse({ x = 'a', y = 1 }), nil, 'parse junk x')
eq(M.parse({ x = 1 }), nil, 'parse missing y')
eq(M.parse({ x = 0 / 0, y = 1 }), nil, 'parse nan')
eq(M.parse({ x = math.huge, y = 1 }), nil, 'parse inf')
eq(M.parse('12,3'), nil, 'parse not a table')
eq(M.parse(nil), nil, 'parse nil')

-- saved / store / forget
local node = M.store(nil, 'W/A', { x = 10, y = 20 })
eq(M.saved(node, 'W/A').x, 10, 'stored x')
eq(M.saved(node, 'W/B'), nil, 'other character: nothing')
node = M.store(node, 'W/B', { x = 5, y = 6 })
node = M.store(node, 'W/A', nil)
eq(M.saved(node, 'W/A'), nil, 'forgotten')
eq(M.saved(node, 'W/B').y, 6, 'other character kept')
eq(M.saved(node, nil), nil, 'no key: nothing')
eq(M.saved('x', 'W/B'), nil, 'node not a table')
eq(M.store(node, nil, { x = 1, y = 1 }), node, 'no key: node unchanged')

-- clamp fully inside
local x, y = M.clamp(-50, -10, 290, 108, 1000, 600)
eq(x, 0, 'clamp left'); eq(y, 0, 'clamp top')
x, y = M.clamp(900, 590, 290, 108, 1000, 600)
eq(x, 710, 'clamp right'); eq(y, 492, 'clamp bottom')
x, y = M.clamp(100, 200, 290, 108, 1000, 600)
eq(x, 100, 'inside x kept'); eq(y, 200, 'inside y kept')
x, y = M.clamp(50, 50, 290, 108, 200, 80)
eq(x, 0, 'parent too narrow: left'); eq(y, 0, 'parent too low: top')

-- default place
x, y = M.default(290, 108, 1000, 600)
eq(x, 355, 'default centred'); eq(y, M.DEFAULT_TOP, 'default top')

-- place: nothing saved keeps the default anchors; a saved spot off screen after a resize is pulled in
eq(M.place(nil, 290, 108, 1000, 600), nil, 'nothing saved: default anchors')
eq(M.place({ x = 'bad' }, 290, 108, 1000, 600), nil, 'bad saved: default anchors')
p = M.place({ x = 1500, y = 900 }, 290, 108, 1000, 600)
eq(p.x, 710, 'smaller window: x clamped'); eq(p.y, 492, 'smaller window: y clamped')
p = M.place({ x = 300, y = 250 }, 290, 108, 1000, 600)
eq(p.x, 300, 'saved x'); eq(p.y, 250, 'saved y')

-- drag
x, y = M.dragTo(520, 300, 20, 10, 100, 50, 290, 108, 1000, 600)
eq(x, 400, 'drag x relative to parent'); eq(y, 240, 'drag y relative to parent')
x, y = M.dragTo(5, 5, 20, 10, 100, 50, 290, 108, 1000, 600)
eq(x, 0, 'drag past left clamped'); eq(y, 0, 'drag past top clamped')
eq(M.moved(10, 10, 11, 12), false, 'tiny move: a click')
eq(M.moved(10, 10, 13, 10), true, 'moved x')
eq(M.moved(10, 10, 10, 6), true, 'moved y')

-- widths: the box fits its text, the panel grows when the texts need it
local pw, bw = M.widths(160, 50)
eq(bw, 84, 'short box text: minimum box')
eq(pw, 290, 'short texts: default width')
pw, bw = M.widths(160, 70)
eq(bw, 94, 'box grows with its text')
eq(pw, 290, 'still fits 290')
pw, bw = M.widths(200, 70)
eq(pw, 6 + 216 + 6 + 94 + 6, 'long button text: wider panel')
pw, bw = M.widths(nil, nil)
eq(pw, 290, 'no measure: default width'); eq(bw, 84, 'no measure: minimum box')

print(string.format('towerpanelpos_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
