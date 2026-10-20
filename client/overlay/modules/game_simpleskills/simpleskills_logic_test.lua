-- luajit simpleskills_logic_test.lua && lua5.3 simpleskills_logic_test.lua
local dir = (arg and arg[0] or ''):match('^(.*[/\\])') or './'
dofile(dir .. 'simpleskills_logic.lua')
local S = ChaosSimpleSkills
local fails = 0
local function eq(a, b, what)
  if a ~= b then print('FAIL ' .. what .. ': ' .. tostring(a) .. ' ~= ' .. tostring(b)); fails = fails + 1 end
end

local function sk(level, base, percent) return { level = level, base = base or level, percent = percent or 0 } end

-- the best of the three
local m = S.melee({ sword = sk(100, 100, 20), club = sk(40), axe = sk(70) })
eq(m.name, 'sword', 'best: sword'); eq(m.level, 100, 'best level'); eq(m.percent, 20, 'its percent')
m = S.melee({ sword = sk(30), club = sk(40), axe = sk(70, 65, 90) })
eq(m.name, 'axe', 'best: axe'); eq(m.level, 70, 'axe level'); eq(m.base, 65, 'axe base (an item adds 5)'); eq(m.percent, 90, 'axe percent')
m = S.melee({ sword = sk(50, 50, 10), club = sk(50, 50, 60), axe = sk(50, 50, 30) })
eq(m.name, 'club', 'a tie in level: the higher percent')
m = S.melee({ sword = sk(50), club = sk(50), axe = sk(50) })
eq(m.name, 'sword', 'a full tie: the server\'s order (sword first)')
m = S.melee(nil)
eq(m.level, 0, 'nothing known: 0')
m = S.melee({ sword = sk(12), club = sk(10) })
eq(m.name, 'sword', 'a missing skill is skipped')

-- the fist row
eq(S.showFist(17), true, 'Monk'); eq(S.showFist(18), true, 'Shadowfist'); eq(S.showFist(19), true, 'Iron Sage')
eq(S.showFist(4), false, 'Warrior'); eq(S.showFist(nil), false, 'unknown'); eq(S.showFist(0), false, 'none')
eq(table.concat(S.hidden(4), ','), 'club,axe,fist', 'a Warrior hides club, axe and fist')
eq(table.concat(S.hidden(18), ','), 'club,axe', 'a Shadowfist keeps the fist')

-- the skill ids are the protocol's
eq(S.SKILL.fist, 0, 'fist'); eq(S.SKILL.club, 1, 'club'); eq(S.SKILL.sword, 2, 'sword'); eq(S.SKILL.axe, 3, 'axe')
eq(S.SKILL.distance, 4, 'distance')

-- the module files exist and name the same things
local f = io.open(dir .. 'simpleskills.lua', 'r')
local src = f and f:read('*a') or ''
if f then f:close() end
eq(src:find("tr('Melee')", 1, true) ~= nil, true, 'the module says Melee through tr()')
eq(src:find("Magic / Wand", 1, true) ~= nil, true, 'and Magic / Wand')

if fails > 0 then print(fails .. ' failure(s)'); os.exit(1) end
print('simpleskills_logic_test: OK')
