-- Run from the server/ folder: luajit tests/start_stats_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Level 1 stats of every class (data/scripts/chaos/start_stats.lua): a row per class of the vocation XML files, the
-- order of the classes' gains kept, casters able to cast their level 1 spell many times, ascended classes like their
-- base; NP.statsFor / NP.statsFix (the one-time login correction); the creation paths reading the same numbers
-- (tools/linux/server/add-account.sh, tools/windows/test_accounts.sql); NP.kitParts (the wearable part on arrival,
-- the rest when the island ends: nothing twice).
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/newplayer_core.lua")
local NP = ChaosNewPlayer
local cfg = NP.cfg()
local S = NP.startStatsCfg()

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function read(path)
	local f = assert(io.open(path, "r"))
	local text = f:read("*a")
	f:close()
	return text
end

-- ------------------------------------------------------------------ the vocations and their gains
local gains = {}
for _, file in ipairs({"chaos_vocations.xml", "chaos_vocations_monk.xml", "chaos_vocations_necro.xml",
		"chaos_vocations_templar.xml"}) do
	for tag in read("data/XML/" .. file):gmatch("<vocation%s[^>]*>") do
		local id = tonumber(tag:match('%sid="(%d+)"'))
		gains[id] = {hp = tonumber(tag:match('gainhp="(%d+)"')), mana = tonumber(tag:match('gainmana="(%d+)"')),
			cap = tonumber(tag:match('gaincap="(%d+)"'))}
	end
end
local n = 0
for id, g in pairs(gains) do
	n = n + 1
	ok(S.stats[id] ~= nil, "a start row for vocation " .. id)
	ok(g.hp and g.mana and g.cap, "gains of vocation " .. id)
end
eq(n, 21, "the 21 classes of the vocation files")
for id, g in pairs(gains) do
	local r = S.stats[id]
	ok(r and r.gainhp == g.hp and r.gainmana == g.mana and r.gaincap == g.cap, "the row's gains are the vocation file's " .. id)
end
-- the start: level 8 with exactly its experience (owner design 2026-10-16: no tutorial island)
local L8, X8 = NP.startLevel()
eq(L8, 8, "start level") eq(X8, 4200, "start experience") eq(NP.expForLevel(8), 4200, "the engine's level 8 experience")
eq(NP.expForLevel(9) > X8, true, "short of level 9")
ok(NP.startLevelDue(1, false), "a new level 1 character is raised")
ok(not NP.startLevelDue(1, true), "a character with its kit keeps its level")
ok(not NP.startLevelDue(8, false), "already level 8")
ok(S.stats[0] ~= nil, "vocation 0 (staff)")

-- ascended classes start like their base class
local baseOf = Chaos.classes.baseOf
for id in pairs(gains) do
	local b = baseOf[id]
	ok(b ~= nil, "base class of " .. id)
	if b and b ~= id then
		local r, br = S.stats[id], S.stats[b]
		ok(r.health == br.health and r.mana == br.mana and r.cap == br.cap, "vocation " .. id .. " starts like " .. b)
	end
end

-- the base classes: more gain per level, at least as much at level 1 (health, mana, capacity)
local bases = {}
for id in pairs(gains) do
	if baseOf[id] == id then
		bases[#bases + 1] = id
	end
end
eq(#bases, 7, "seven base classes")
for _, a in ipairs(bases) do
	for _, b in ipairs(bases) do
		for _, k in ipairs({{"hp", "health"}, {"mana", "mana"}, {"cap", "cap"}}) do
			if gains[a][k[1]] > gains[b][k[1]] then
				ok(S.stats[a][k[2]] >= S.stats[b][k[2]], string.format("%s: class %d (gain %d) >= class %d (gain %d)",
					k[2], a, gains[a][k[1]], b, gains[b][k[1]]))
			end
		end
	end
end
for id, r in pairs(S.stats) do
	ok(r.health >= 150 and r.cap >= 400 and r.soul == 100, "no class starts below the old flat values " .. id)
	if id ~= 0 then
		ok(r.mana > 0, "every class has mana at level 1 " .. id)
	end
end

-- the tutorial spells (Minor Mending for the Ranger and Mystic lines since the 15-spell cap, 2026-10-20): every class
-- with one casts it 3 times or more from a level 8 pool (the start level), casters 10 times or more
for id in pairs(gains) do
	local spell = NP.tutorialSpellFor(id)
	local kit = NP.kitFor(id)
	if spell then
		ok(NP.statsFor(id, 8).mana >= 3 * spell.mana, "class " .. id .. " casts " .. spell.name .. " three times")
		if kit and kit.role == "caster" then
			ok(NP.statsFor(id, 8).mana >= 10 * spell.mana, "caster " .. id .. " casts " .. spell.name .. " ten times")
		end
	end
	if kit and kit.role == "caster" then
		ok(S.stats[id].mana >= 75, "caster " .. id .. ": room for an Everfull mana potion's roll (75-125)")
	end
end

-- ------------------------------------------------------------------ statsFor / statsFix
local m = NP.statsFor(1, 1, gains[1])
eq(m.health, 150, "Mystic level 1 health") eq(m.mana, 90, "Mystic level 1 mana") eq(m.cap, 400, "Mystic cap")
m = NP.statsFor(1, 2, gains[1])
eq(m.mana, 90 + gains[1].mana, "level 2 adds one level of gains")
eq(NP.statsFor(99, 1).health, S.stats[0].health, "an unknown class: vocation 0's row")
eq(NP.statsFor(5, 1).mana, S.stats[1].mana, "Elementalist like the Mystic")
m = NP.statsFor(1, 8)
eq(m.health, 185, "Mystic level 8 health (150 + 7 x 5)") eq(m.mana, 300, "Mystic level 8 mana (90 + 7 x 30)")
eq(m.cap, 470, "Mystic level 8 cap")
eq(NP.statsFor(4, 8).health, 185 + 7 * gains[4].hp, "Warrior level 8 health from the row's own gains")

-- the owner's character: a level 1 Mystic made by the old add-account.sh (150 health, 0 mana, 400 cap)
local fix = NP.statsFix(1, 1, {maxHealth = 150, maxMana = 0, cap = 40000}, gains[1])
ok(fix ~= nil, "the old add-account.sh Mystic is corrected")
eq(fix.maxMana, 90, "mana raised") eq(fix.maxHealth, 150, "health kept") eq(fix.cap, 40000, "cap kept (hundredths)")
fix = NP.statsFix(4, 1, {maxHealth = 150, maxMana = 0, cap = 40000}, gains[4])
eq(fix.maxHealth, 185, "Warrior health raised") eq(fix.maxMana, 35, "Warrior mana raised") eq(fix.cap, 47000, "Warrior cap raised")
fix = NP.statsFix(4, 2, {maxHealth = 165, maxMana = 5, cap = 42500}, gains[4])
eq(fix.maxHealth, 185 + gains[4].hp, "level 2: one level of gains on top")
eq(NP.statsFix(1, 1, {maxHealth = 150, maxMana = 90, cap = 40000}, gains[1]), nil, "right values: nothing to do")
eq(NP.statsFix(1, 1, {maxHealth = 400, maxMana = 500, cap = 90000}, gains[1]), nil, "more than the class's: never lowered")
eq(NP.statsFix(1, 9, {maxHealth = 150, maxMana = 0, cap = 40000}, gains[1]), nil, "level 9: left alone")

-- inflated maximums (536 million mana seen live, 2026-10-24): reset to the class's value, nothing else touched
local want = NP.statsFor(1, 300, gains[1])
local inf = NP.inflatedFix(1, 300, {maxHealth = want.health, maxMana = 536000000}, gains[1])
ok(inf ~= nil, "536M mana is repaired")
eq(inf.maxMana, want.mana, "mana back to the formula") eq(inf.maxHealth, want.health, "healthy health kept")
inf = NP.inflatedFix(1, 300, {maxHealth = 3000000000, maxMana = want.mana}, gains[1])
eq(inf.maxHealth, want.health, "inflated health back to the formula") eq(inf.maxMana, want.mana, "mana kept")
eq(NP.inflatedFix(1, 300, {maxHealth = want.health * 5, maxMana = want.mana * 10}, gains[1]), nil, "generous but real: untouched")
eq(NP.inflatedFix(1, 300, {maxHealth = 900000, maxMana = 900000}, gains[1]), nil, "under the floor: untouched")
eq(NP.inflatedFix(1, 300, {maxHealth = want.health, maxMana = inf.maxMana}, gains[1]), nil, "a repaired character: idempotent")

-- the login repair on a mocked player: maximums reset, current health and mana come down, a second login does nothing
do
  local st = {mh = want.health, mm = 536000000, h = want.health, mn = 500000000}
  local pl = {}
  function pl:getVocation() return {getId = function() return 1 end, getHealthGain = function() return gains[1].hp end,
    getManaGain = function() return gains[1].mana end, getCapacityGain = function() return gains[1].cap end} end
  function pl:getLevel() return 300 end
  function pl:getName() return "Test" end
  function pl:getMaxHealth() return st.mh end
  function pl:getMaxMana() return st.mm end
  function pl:setMaxHealth(v) st.mh = v; if st.h > v then st.h = v end end
  function pl:setMaxMana(v) st.mm = v; if st.mn > v then st.mn = v end end
  function pl:getHealth() return st.h end
  function pl:getMana() return st.mn end
  function pl:setHealth(v) st.h = math.min(v, st.mh) end
  function pl:setMana(v) st.mn = math.min(v, st.mm) end
  ok(NP.repairInflated(pl), "login repair acts on 536M mana")
  eq(st.mm, want.mana, "max mana reset") eq(st.mn, want.mana, "current mana comes down") eq(st.mh, want.health, "health untouched")
  ok(not NP.repairInflated(pl), "second login: nothing to do")
end
-- the owner's island Mystic raised to level 8 by the engine (gains from 150 / 0 / 400): mana below the class's
fix = NP.statsFix(1, 8, {maxHealth = 185, maxMana = 210, cap = 47000}, gains[1])
eq(fix.maxMana, 300, "level 8 Mystic mana raised to the class's") eq(fix.maxHealth, 185, "its health was right")
fix = NP.statsFix(1, 1, {maxHealth = 200, maxMana = 0, cap = 40000}, gains[1])
eq(fix.maxHealth, 200, "a higher value stays when another is raised")

-- ------------------------------------------------------------------ the creation paths read the same numbers
-- one row per line, in the form the website (lib.php chaos_start_stats) and add-account.sh read with a pattern
local text = read("data/scripts/chaos/start_stats.lua")
local lines = 0
for id, h, mn, c, so, gh, gm, gc in text:gmatch(
		"\n%s*%[(%d+)%] = {health = (%d+), mana = (%d+), cap = (%d+), soul = (%d+), gainhp = (%d+), gainmana = (%d+), gaincap = (%d+)}") do
	lines = lines + 1
	local r = S.stats[tonumber(id)]
	ok(r and r.health == tonumber(h) and r.mana == tonumber(mn) and r.cap == tonumber(c) and r.soul == tonumber(so)
		and r.gainhp == tonumber(gh) and r.gainmana == tonumber(gm) and r.gaincap == tonumber(gc),
		"line of vocation " .. id .. " reads as the table")
end
ok(text:find("\n\tstartLevel = 8,\n", 1, true) and text:find("\n\tstartExperience = 4200,\n", 1, true),
	"startLevel and startExperience on lines of their own")
local rows = 0
for _ in pairs(S.stats) do
	rows = rows + 1
end
eq(lines, rows, "every row on its own line in the plain form")

-- add-account.sh reads this file and the class looks; test_accounts.sql writes the values of its four classes
local add = read("../tools/linux/server/add-account.sh")
ok(add:find("start_stats.lua", 1, true) ~= nil, "add-account.sh reads start_stats.lua")
ok(add:find("class_looks_core.lua", 1, true) ~= nil, "add-account.sh reads the class looks")
ok(add:find("healthmax", 1, true) and add:find("manamax", 1, true) and add:find("town_id", 1, true)
	and add:find("looktype", 1, true) and add:find("experience", 1, true), "add-account.sh writes level, health, mana, look and town")
-- run it (no database: ADD_ACCOUNT_PRINT_ONLY) for every class it offers: the same values as NP.statsFor
local sh = io.popen("command -v bash 2>/dev/null")
local bash = sh and sh:read("*l")
if sh then sh:close() end
if bash and bash ~= "" then
	for cls, voc in pairs({warrior = 4, ranger = 3, mystic = 1, thief = 11}) do
		local p = io.popen("CHAOS_SCRIPTS=data/scripts/chaos ADD_ACCOUNT_PRINT_ONLY=1 bash ../tools/linux/server/add-account.sh abc secret1 'Some Name' "
			.. cls .. " 2>&1")
		local out = p:read("*a")
		p:close()
		local r = NP.statsFor(voc, L8)
		local want = string.format("level=%d experience=%d health=%d mana=%d cap=%d soul=%d", L8, X8, r.health, r.mana, r.cap, r.soul)
		ok(out:find(want, 1, true) ~= nil, "add-account.sh " .. cls .. ": " .. want .. " (got " .. out .. ")")
	end
else
	print("note: no bash, add-account.sh was not run")
end
local sql = read("../tools/windows/test_accounts.sql")
local seen = 0
for name, voc, lv, h, mn, c, so in sql:gmatch("'(Test %a+)', (%d+), (%d+), (%d+), (%d+), (%d+), (%d+)") do
	seen = seen + 1
	local r = NP.statsFor(tonumber(voc), L8)
	eq(tonumber(lv), L8, "test_accounts.sql: " .. name .. " at the start level")
	ok(r.health == tonumber(h) and r.mana == tonumber(mn) and r.cap == tonumber(c) and r.soul == tonumber(so),
		"test_accounts.sql: " .. name .. " has its class's start values")
end
ok(sql:find("c.`lvl`, " .. X8, 1, true) ~= nil, "test_accounts.sql: the start experience")
eq(seen, 4, "the four test characters")
-- the website reads the file with the plain pattern too
local lib = read("../website/overlay/plugins/chaos/lib.php")
ok(lib:find("scripts/chaos/start_stats.lua", 1, true) ~= nil, "the website reads start_stats.lua")

-- ------------------------------------------------------------------ the kit in two parts
for vocId in pairs(gains) do
	local kit = NP.kitFor(vocId)
	local parts = NP.kitParts(kit, 1)
	eq(#parts.wear, #kit.equip, "every equipment entry is worn on arrival " .. vocId)
	local worn = {}
	for _, w in ipairs(parts.wear) do
		worn[w.id] = (worn[w.id] or 0) + 1
	end
	for _, r in ipairs(parts.rest) do
		-- the rest holds no worn item, except a second copy the kit lists on purpose (the Ninja's off-hand dagger)
		if worn[r.id] then
			local listed = 0
			for _, b in ipairs(kit.backpack) do
				if b.id == r.id then
					listed = listed + 1
				end
			end
			ok(listed > 0, "the rest does not repeat a worn item " .. vocId .. " " .. r.id)
		end
		ok(r.id ~= 7618 and r.id ~= 7620, "no stock potions in the rest " .. vocId)
	end
end
local myst = NP.kitParts(NP.kitFor(1), 1)
local spare = false
for _, r in ipairs(myst.rest) do
	spare = spare or r.id == 2190
end
ok(spare, "the Mystic's real wand (level 7) comes with the rest, the scorcher is worn")
local rest = {}
for _, r in ipairs(NP.kitParts(NP.kitFor(4), 1).rest) do
	rest[r.id] = true
end
ok(rest[2120] and rest[2554] and rest[2789], "rope, shovel and food come with the rest")

-- ------------------------------------------------------------------ the start look of every class, on every path
-- owner report 2026-10-16: a Ranger ("Jokr", made on the website) looked like a mage: a blue robe and a headband. Its
-- look type was the Ranger's (2163 / 2164, the hooded archer, on every path); the website's old starter colours (head 78
-- yellow, body 68 blue) on that colour template made the mage. Every class now starts in its own colours.
dofile("data/scripts/chaos/class_looks_core.lua")
local CL = ChaosClassLooks
local ownerOf = {}
for v, e in pairs(CL.looks) do
	ownerOf[e.male] = ownerOf[e.male] or v
	ownerOf[e.female] = ownerOf[e.female] or v
end
local starts = {}
for _, v in ipairs(bases) do
	for sex = 0, 1 do
		local look = CL.lookFor(v, sex)
		ok(look ~= nil, "base class " .. v .. " sex " .. sex .. " has a start look")
		eq(ownerOf[look], v, "the start look of class " .. v .. " sex " .. sex .. " is that class's own")
		ok(not starts[look] or starts[look] == v, "no other class starts in look " .. tostring(look))
		starts[look] = v
		local o = CL.startOutfit({lookType = 136, lookHead = 78, lookBody = 68, lookLegs = 58, lookFeet = 76, lookMount = 5}, v, sex)
		local c = CL.startColorsFor(v)
		ok(c ~= nil, "start colours of class " .. v)
		ok(o.lookType == look and o.lookAddons == CL.ADDONS and o.lookHead == c.head and o.lookBody == c.body
			and o.lookLegs == c.legs and o.lookFeet == c.feet and o.lookMount == 5, "first login outfit of class " .. v .. " sex " .. sex)
		ok(not (c.head == CL.OLD_COLORS.head and c.body == CL.OLD_COLORS.body), "class " .. v .. ": not the old yellow and blue")
	end
end
eq(CL.lookFor(3, 1), 2163, "Ranger male: the hooded archer") eq(CL.lookFor(3, 0), 2164, "Ranger female")
eq(CL.startColorsFor(3).body, 120, "Ranger body: forest green")
for id in pairs(gains) do
	ok(CL.startColorsFor(id) == CL.startColorsFor(baseOf[id]), "ascended class " .. id .. " starts in its base class's colours")
end
-- add-account.sh: the same look and colours, both sexes
if bash and bash ~= "" then
	for cls, voc in pairs({warrior = 4, ranger = 3, mystic = 1, thief = 11}) do
		for sex, name in pairs({[0] = "female", [1] = "male"}) do
			local p = io.popen("CHAOS_SCRIPTS=data/scripts/chaos ADD_ACCOUNT_PRINT_ONLY=1 bash ../tools/linux/server/add-account.sh abc secret1 'Some Name' "
				.. cls .. " " .. name .. " 2>&1")
			local out = p:read("*a")
			p:close()
			local c = CL.startColorsFor(voc)
			local want = string.format("looktype=%d colors=%d/%d/%d/%d", CL.lookFor(voc, sex), c.head, c.body, c.legs, c.feet)
			ok(out:find(want, 1, true) ~= nil, "add-account.sh " .. cls .. " " .. name .. ": " .. want .. " (got " .. out .. ")")
		end
	end
end

print(string.format("start_stats_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
