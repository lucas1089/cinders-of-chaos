-- luajit huntportmath_test.lua && lua5.3 huntportmath_test.lua (CI runs it from the repo root)
-- O568, the hunt teleport markers: the server list cleaned, the hunt the character stands in, the teleport it used and
-- the one it came out of (from its own steps), the saved state, the markers drawn on a floor and their hover texts.
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'huntportmath.lua')
local M = HuntPortMath
local fails, checks = 0, 0
local function eq(a, b, what)
  checks = checks + 1
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end
local function ok(c, what) eq(not not c, true, what) end
local function P(x, y, z) return { x = x, y = y, z = z } end

-- the list
local ports = M.parse({ ports = {
  { i = 'widowmere', n = 'Widowmere', l = { 480, 640 }, t = P(31638, 32258, 6), f = P(31638, 32257, 6), a = P(16000, 14400, 6), b = P(16010, 14410, 6) },
  { i = 'alder', n = 'Alder Fen', l = { 10, 40 }, t = P(31634, 32254, 7), f = P(31634, 32255, 7), a = P(15700, 14400, 7) },
  { i = 'rotworm', n = 'Rotworm', l = { 20, 60 }, t = P(31654, 32254, 7), f = P(31654, 32255, 7), a = P(32000, 32000, 8), b = P(32002, 32001, 8) },
  { i = 'alder', n = 'Alder again', l = { 1, 2 }, t = P(1, 1, 7) },        -- a repeated id: the first row stays
  { i = 'nowhere', n = 'No teleport', l = { 1, 2 } },                       -- no hall teleport: dropped
  { i = '', n = 'No id', t = P(1, 1, 7) }, 'junk', { n = 'No id either', t = P(1, 1, 7) },
  { i = 'bad', t = { x = 'a', y = 1, z = 7 } },                             -- not numbers: dropped
  { i = 'deep', t = P(5, 5, 99) },                                          -- not a floor: dropped
  { i = 'plain', t = P(31650.9, 32254, 7) },                                -- whole numbers; no name, no band: its id, 0-0
} })
eq(#ports, 4, 'four good rows')
eq(ports[1].i, 'widowmere', 'order kept'); eq(ports[2].n, 'Alder Fen', 'the first row of a repeated id'); eq(ports[3].b.x, 32002, 'way out')
eq(ports[4].t.x, 31650, 'whole tile'); eq(ports[4].n, 'plain', 'the id names a hunt without a name'); eq(ports[4].lo, 0, 'no band: 0')
eq(ports[2].b, nil, 'no way out'); eq(ports[1].lo, 480, 'band low'); eq(ports[1].hi, 640, 'band high')
eq(#M.parse(nil), 0, 'nothing'); eq(#M.parse({ ports = 'x' }), 0, 'bad list'); eq(#M.parse({}), 0, 'no list')
local many = {}
for i = 1, M.MAX + 20 do many[i] = { i = 'h' .. i, t = P(i, 1, 7) } end
eq(#M.parse({ ports = many }), M.MAX, 'at most MAX hunts')
ports = M.parse({ ports = {
  { i = 'widowmere', n = 'Widowmere', l = { 480, 640 }, t = P(31638, 32258, 6), f = P(31638, 32257, 6), a = P(16000, 14400, 6), b = P(16010, 14410, 6) },
  { i = 'alder', n = 'Alder Fen', l = { 10, 40 }, t = P(31634, 32254, 7), f = P(31634, 32255, 7), a = P(15700, 14400, 7) },
  { i = 'rotworm', n = 'Rotworm', l = { 20, 60 }, t = P(31654, 32254, 7), f = P(31654, 32255, 7), a = P(32000, 32000, 8), b = P(32002, 32001, 8) },
} })
eq(M.index(ports).rotworm.n, 'Rotworm', 'index by id')

-- the hunt the character stands in
eq(M.hereFor(ports, P(16020, 14420, 6)), 'widowmere', 'near the arrival of a plan')
eq(M.hereFor(ports, P(16020 + 400, 14420, 6)), nil, 'too far from every arrival')
eq(M.hereFor(ports, P(31640, 32256, 6)), nil, 'in the hall: in no hunt')
eq(M.hereFor(ports, P(31640, 32256, 3)), nil, 'in the hall, another floor of it')
eq(M.hereFor(ports, P(32010, 32010, 8)), 'rotworm', 'a base hunt')
eq(M.hereFor(ports, P(32010, 32010, 9)), 'rotworm', 'one floor down still counts')
eq(M.hereFor(ports, P(32010, 32010, 12)), nil, 'four floors down does not')
eq(M.hereFor(ports, nil), nil, 'no position')
eq(M.hereFor(ports, P(16000, 14400, 6), 'widowmere'), 'widowmere', 'kept')
eq(M.hereFor(ports, P(16000 + 140, 14400, 6), 'widowmere'), 'widowmere', 'kept while within the range')
eq(M.hereFor(ports, P(32010, 32010, 8), 'widowmere'), 'rotworm', 'a hint far away is not kept')
eq(M.hereFor({ { i = 'x', t = P(1, 1, 7), a = P(500, 500, 7) }, { i = 'y', t = P(2, 2, 7), a = P(540, 500, 7) } }, P(530, 500, 7)), 'y', 'the nearest arrival')

-- the character's steps
local st = M.newState()
eq(M.track(st, ports, nil, P(31640, 32256, 6)), false, 'a login in the hall changes nothing')
eq(st.last, nil, 'nothing used yet')
eq(M.track(st, ports, P(31638, 32257, 6), P(16000, 14400, 6)), true, 'a step from the front of a teleport to far away: used it')
eq(st.last, 'widowmere', 'last used'); eq(st.here, 'widowmere', 'in that hunt'); ok(st.used.widowmere, 'entered')
eq(M.track(st, ports, P(16000, 14400, 6), P(16001, 14400, 6)), false, 'a step in the hunt changes nothing')
eq(M.track(st, ports, P(16010, 14410, 6), P(31638, 32257, 6)), true, 'out by the camp portal: in front of the teleport')
eq(st.last, 'widowmere', 'still the one to go back to'); eq(st.here, nil, 'no longer in the hunt')
-- the teleport tile itself counts as next to it
eq(M.track(st, ports, P(31654, 32254, 7), P(32000, 32000, 8)), true, 'from the teleport tile')
eq(st.last, 'rotworm', 'the other hunt is last now'); eq(st.here, 'rotworm', 'in it'); ok(st.used.rotworm and st.used.widowmere, 'both entered')
-- death: the temple is not in front of a teleport: nothing is used, the hunt is left
eq(M.track(st, ports, P(32010, 32010, 8), P(32369, 32241, 7)), true, 'dead, in the temple')
eq(st.last, 'rotworm', 'the last one stays'); eq(st.here, nil, 'out of the hunt')
-- a jump from somewhere else than a teleport (a spell, a scroll) into a hunt: standing in it, nothing used
local st2 = M.newState()
eq(M.track(st2, ports, P(32369, 32241, 7), P(15710, 14405, 7)), true, 'a scroll into a hunt')
eq(st2.here, 'alder', 'in it'); eq(st2.last, nil, 'nothing used'); eq(next(st2.used), nil, 'nothing entered')
-- a login in a hunt
local st3 = M.newState()
eq(M.track(st3, ports, nil, P(16050, 14450, 6)), true, 'a login in a hunt'); eq(st3.here, 'widowmere', 'in it')
-- a floor change by stairs in the hall is a step, not a teleport
local st4 = M.newState()
eq(M.track(st4, ports, P(31648, 32256, 6), P(31649, 32257, 7)), false, 'stairs')
-- the second floor of a hall: a teleport of z 7 is not used from z 6
eq(M.track(st4, ports, P(31634, 32255, 6), P(15700, 14400, 7)), true, 'a jump from the wrong floor')
eq(st4.last, nil, 'not the teleport of another floor'); eq(st4.here, 'alder', 'but in the hunt it landed in')
-- a way out lands next to another teleport's front: the front within one tile
local st5 = M.newState()
eq(M.track(st5, ports, P(16010, 14410, 6), P(31639, 32257, 6)), true, 'out, one tile off the front')
eq(st5.last, 'widowmere', 'still that hunt')

-- saving
local node = M.save(nil, 'Ann', st)
eq(node.chars.Ann.last, 'rotworm', 'saved last'); eq(#node.chars.Ann.used, 2, 'saved used'); eq(node.chars.Ann.used[1], 'rotworm', 'sorted')
local back = M.load(node, 'Ann')
eq(back.last, 'rotworm', 'loaded last'); ok(back.used.widowmere and back.used.rotworm, 'loaded used'); eq(back.here, nil, 'here is not saved')
eq(M.load(node, 'Bob').last, nil, 'another character starts empty')
eq(M.load(nil, 'Ann').last, nil, 'no node'); eq(M.load({ chars = 'x' }, 'Ann').last, nil, 'bad node')
eq(M.load({ chars = { Ann = { last = 5, used = { 1, 'ok', '' } } } }, 'Ann').last, nil, 'bad last dropped')
ok(M.load({ chars = { Ann = { last = 5, used = { 1, 'ok', '' } } } }, 'Ann').used.ok, 'good id of a bad list kept')
local n2 = M.save(node, 'Bob', st2)
ok(n2.chars.Ann and n2.chars.Bob, 'a second character is added'); eq(n2.order[2], 'Bob', 'newest last')
local cur = nil
for i = 1, M.MAX_CHARS + 5 do cur = M.save(cur, 'c' .. i, st) end
local count = 0
for _ in pairs(cur.chars) do count = count + 1 end
eq(count, M.MAX_CHARS, 'the oldest characters are dropped'); eq(cur.chars.c1, nil, 'the first is gone'); ok(cur.chars['c' .. (M.MAX_CHARS + 5)], 'the newest stays')
local bigState = M.newState()
for i = 1, M.MAX_USED + 30 do bigState.used['h' .. i] = true end
eq(#M.save(nil, 'Ann', bigState).chars.Ann.used, M.MAX_USED, 'used is capped')
eq(M.save(nil, '', st).chars[''], nil, 'no name: nothing saved')

-- the markers
local bounds = { x1 = 31600, y1 = 32240, x2 = 31700, y2 = 32270, z = 7 }
local state = { last = 'rotworm', here = nil, used = {} }
local list = M.markers(ports, state, bounds, 4, 100)
eq(#list, 2, 'two hall teleports on floor 7 in view')
eq(list[1].id, 'rotworm', 'the highlighted one first'); eq(list[1].highlighted, true, 'highlighted'); eq(list[1].image, 'huntport_last', 'its image')
eq(list[2].id, 'alder', 'the other'); eq(list[2].image, 'huntport', 'plain image'); eq(list[2].kind, 'in', 'kind in')
eq(list[2].x, 31634, 'x'); eq(list[2].y, 32254, 'y')
eq(#M.markers(ports, state, bounds, 1, 100), 1, 'zoomed out: only the one to go back to')
eq(#M.markers(ports, { used = {} }, bounds, 1, 100), 0, 'zoomed out, none used: nothing')
eq(#M.markers(ports, state, { x1 = 0, y1 = 0, x2 = 10, y2 = 10, z = 7 }, 4, 100), 0, 'out of view')
eq(#M.markers(ports, state, { x1 = 31600, y1 = 32240, x2 = 31700, y2 = 32270, z = 6 }, 4, 100), 1, 'floor 6: the plan on it')
eq(#M.markers(ports, state, bounds, 4, 1), 1, 'limit')
eq(M.markers(ports, state, bounds, 4, 1)[1].id, 'rotworm', 'the limit keeps the highlighted')
-- the ways out
local far = { x1 = 15900, y1 = 14300, x2 = 16100, y2 = 14500, z = 6 }
eq(#M.markers(ports, { used = {} }, far, 4, 100), 0, 'a hunt not entered: no way out on the map')
list = M.markers(ports, { used = { widowmere = true } }, far, 4, 100)
eq(#list, 1, 'a hunt entered: its way out'); eq(list[1].kind, 'out', 'kind out'); eq(list[1].image, 'huntexit', 'image'); eq(list[1].highlighted, false, 'plain')
list = M.markers(ports, { used = {}, here = 'widowmere' }, far, 1, 100)
eq(#list, 1, 'the hunt it stands in: its way out, whatever the scale'); eq(list[1].image, 'huntexit_here', 'highlighted image'); eq(list[1].highlighted, true, 'highlighted')
eq(#M.markers(ports, { used = { alder = true } }, far, 4, 100), 0, 'alder has no way out known')

-- the texts (no locale in this test: the English keys)
eq(M.text('in', ports[1], false), 'Hunt teleport: Widowmere (levels 480-640)', 'teleport text')
eq(M.text('in', ports[1], true), 'Hunt teleport: Widowmere (levels 480-640), last used: your way back', 'last used text')
eq(M.text('out', ports[1], false), 'Way out of Widowmere (to the teleport room)', 'way out text')
eq(M.text('out', ports[1], true), 'Way out of Widowmere: you are in this hunt', 'way out here text')
-- with a locale
_G.tr = function(s, ...) return 'PT:' .. string.format(s, ...) end
eq(M.text('out', ports[1], false), 'PT:Way out of Widowmere (to the teleport room)', 'tr is used when the client has it')
_G.tr = nil

-- the pulse stays between 0.55 and 1 and repeats
local lo, hi = 2, 0
for ms = 0, M.PULSE_MS * 2, 50 do
  local v = M.pulse(ms)
  if v < lo then lo = v end
  if v > hi then hi = v end
end
ok(lo >= 0.549 and lo < 0.6, 'pulse low'); ok(hi <= 1.0001 and hi > 0.95, 'pulse high')
ok(math.abs(M.pulse(100) - M.pulse(100 + M.PULSE_MS)) < 1e-9, 'pulse repeats')
eq(M.size(true), 18, 'highlighted size'); eq(M.size(false), 14, 'plain size')
for _, name in pairs(M.IMAGE) do ok(#name > 0, 'an image name') end

print(string.format('huntportmath_test: %d checks, %d failed', checks, fails))
if fails > 0 then os.exit(1) end
