-- run from the repo root: luajit client/overlay/modules/game_minimapdots/minimapdots_logic_test.lua (and lua5.3)
dofile('client/overlay/modules/game_minimapdots/minimapdots_logic.lua')
local L = MinimapDotsLogic

assert(L.OPCODE == 153, 'the map marker opcode')
assert(L.OPTION == 'minimapRadar', 'the option the settings dataset names')

-- the option: on unless false
assert(L.isOn(true) and L.isOn(nil) and not L.isOn(false), 'option as a switch')
assert(L.isOn(0) == true, 'only false turns it off')

-- when the radar is wanted
assert(L.wantRadar(true, true, true) == true, 'on, window shown, online')
assert(L.wantRadar(false, true, true) == false, 'option off')
assert(L.wantRadar(true, false, true) == false, 'window hidden')
assert(L.wantRadar(true, true, false) == false, 'offline')
assert(L.wantRadar(nil, true, true) == false, 'unknown option is not a yes here (the module resolves it first)')

-- kinds
assert(L.kindOf(0) == 'monster', 'plain monster')
assert(L.kindOf(1) == 'boss', 'boss flag')
assert(L.kindOf(2) == 'npc', 'NPC flag')
assert(L.kindOf(4) == 'party', 'party flag')
assert(L.kindOf(5) == 'boss', 'boss wins over party')
assert(L.kindOf(6) == 'party', 'party wins over NPC')
assert(L.kindOf(nil) == 'monster', 'no flag')
assert(L.kindOf(8) == 'monster', 'unknown bits are ignored')

-- decode
local d = L.decode({ z = 7, r = 30, m = { { 1000, 1001, 0 }, { 1002, 999, 1 }, { 5, 6, 2 }, { 7, 8, 4 } } })
assert(d and d.z == 7 and d.r == 30 and #d.dots == 4, 'four dots')
assert(d.dots[1].x == 1000 and d.dots[1].y == 1001 and d.dots[1].kind == 'monster', 'first dot')
assert(d.dots[2].kind == 'boss' and d.dots[3].kind == 'npc' and d.dots[4].kind == 'party', 'kinds decoded')
assert(L.decode(nil) == nil, 'no data')
assert(L.decode({ m = {} }) == nil, 'no floor')
assert(L.decode({ z = 99, m = {} }) == nil, 'bad floor')
local e = L.decode({ z = 7, m = {} })
assert(e and #e.dots == 0, 'an empty list is a list')
local bad = L.decode({ z = 7, m = { 'x', { 'a', 2, 0 }, { 1, 2 }, { -1, 5, 0 }, { 70000, 5, 0 }, { 10, 20, 0 }, { 0 / 0, 1, 0 } } })
assert(#bad.dots == 2, 'bad entries dropped, two good ones left: ' .. #bad.dots)
assert(bad.dots[1].kind == 'monster', 'a missing flag is a monster')
local many = {}
for i = 1, 600 do many[i] = { 100 + i, 200, 0 } end
assert(#L.decode({ z = 7, m = many }).dots == L.MAX_DOTS, 'cut at the maximum')

-- styles: 2 x 2 at 1 px per tile, bigger boss, growing with the zoom
local s1 = L.style('monster', 1)
assert(s1.size == 2 and s1.ring == 0, 'monster at 1 px per tile is 2 x 2')
assert(L.style('npc', 1).size == 2, 'NPC at 1 px per tile is 2 x 2')
assert(L.style('boss', 1).size == 6 and L.style('boss', 1).ring == 1, 'boss at 1 px per tile is 6 x 6 with a ring')
assert(L.style('self', 1).size == 4 and L.style('party', 1).size == 4, 'you and the party 4 x 4')
assert(L.style('monster', 0.5).size == 2, 'below 1 px per tile too')
local s2, s4, s8, s32 = L.style('monster', 2), L.style('monster', 4), L.style('monster', 8), L.style('monster', 32)
assert(s2.size == 3 and s2.ring == 0, 'at 2 px per tile a dot is 3 px, no edge')
assert(s4.size == 4 and s4.ring == 0, 'at 4 px per tile 4 px')
assert(s8.size == 6 and s8.ring == 1, 'at 8 px per tile 6 px with an edge')
assert(s2.size <= s4.size and s4.size <= s8.size and s8.size <= s32.size, 'grows with the zoom')
assert(s32.size == 9, 'at most 9 px')
assert(L.style('boss', 4).size == s4.size + 3 and L.style('boss', 4).ring == 2, 'boss bigger with a thick ring')
assert(L.style('self', 4).size == s4.size + 1 and L.style('self', 4).ring == 1, 'you one px bigger with a ring')
assert(L.style('party', 2).size == 4 and L.style('party', 2).ring == 1, 'party at 2 px per tile')
assert(L.style('boss', 4).edge == '#ffd646', 'boss ring is gold')
assert(L.style('monster', 4).fill == '#e82828', 'monsters are red')
assert(L.style('party', 4).fill == '#46e15a', 'party is green')
assert(L.style('npc', 4).fill == '#5096ff', 'NPCs are blue')
assert(L.style('self', 4).fill == '#ffffff', 'you are white')
assert(L.style('nonsense', 4).fill == '#e82828', 'an unknown kind is a monster')
assert(#L.DRAW_ORDER == 5 and L.DRAW_ORDER[5] == 'self' and L.DRAW_ORDER[4] == 'boss', 'you on top, bosses over the pack')

-- what the options show
assert(L.shows('monster', {}) and L.shows('boss', {}), 'monsters and bosses always')
assert(L.shows('npc', { npcs = false }) == false and L.shows('npc', {}) == true, 'NPC switch')
assert(L.shows('party', { party = false }) == false and L.shows('party', nil) == true, 'party switch')

-- geometry
local x, y = L.corner(100, 50, 3)
assert(x == 99 and y == 49, 'a 3 px dot centred on 100, 50')
x, y = L.corner(100, 50, 2)
assert(x == 99 and y == 49, 'a 2 px dot')
local rect = { x = 10, y = 20, width = 100, height = 80 }
assert(L.inside(10, 20, rect, 0) and not L.inside(9, 20, rect, 0), 'left edge')
assert(L.inside(109, 99, rect, 0) and not L.inside(110, 99, rect, 0), 'right edge')
assert(L.inside(8, 20, rect, 4) and not L.inside(5, 20, rect, 4), 'room for the dot')

-- freshness
local st = { z = 7, at = 1000, dots = {} }
assert(L.fresh(st, 7, 1000 + L.STALE_MS) == true, 'still fresh at the limit')
assert(L.fresh(st, 7, 1001 + L.STALE_MS) == false, 'stale after the limit')
assert(L.fresh(st, 8, 1000) == false, 'another floor')
assert(L.fresh(nil, 7, 0) == false, 'no list')

-- summary
assert(L.summary(nil) == 'no radar list', 'no list')
assert(L.summary(d) == 'radar: 1 monsters, 1 bosses, 1 party, 1 NPCs on floor 7', L.summary(d))

print('minimapdots_logic_test: ok')
