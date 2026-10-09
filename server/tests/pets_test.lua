-- Run from the server/ folder: luajit tests/pets_test.lua (and lua5.3; CI runs both)
-- Pure logic of the pets (pets_core.lua) with the real pets_config.lua: XP curve, kill XP, abilities and their
-- unlocks, zone rules, drops, names, cooldowns, gold, anti-block, rest reasons and the window view.
dofile("data/scripts/chaos/pets_core.lua")
local K = ChaosPetsCore
local cfg = dofile("data/scripts/chaos/pets_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- config sanity
local keys, monsters = {}, {}
for _, s in ipairs(cfg.species) do
	assert(not keys[s.key], "duplicate species key " .. s.key)
	assert(not monsters[s.monster:lower()], "duplicate monster " .. s.monster)
	keys[s.key], monsters[s.monster:lower()] = true, true
	assert(s.key:match("^[a-z_]+$"), "species key " .. s.key)
	assert(type(s.look) == "number" and s.look > 0, "look of " .. s.key)
	eq(#s.abilities, 2, "two abilities: " .. s.key)
	for _, a in ipairs(s.abilities) do
		assert(cfg.abilities[a], "unknown ability " .. a .. " of " .. s.key)
	end
	assert(s.abilities[1] ~= s.abilities[2], "two different abilities: " .. s.key)
	local src = s.source
	assert(src and (src.drop or src.store or src.achievement), "a source: " .. s.key)
	assert(type(s.how) == "string" and #s.how > 0, "how: " .. s.key)
	assert(({fire = 1, ice = 1, death = 1, holy = 1, earth = 1, energy = 1, physical = 1})[s.element], "element " .. s.key)
	if src.store then
		eq(cfg.store[src.store], s.key, "store map of " .. s.key)
	end
end
for unlock, key in pairs(cfg.store) do
	assert(K.species(key, cfg), "store unlock " .. unlock .. " -> " .. key)
end
for _, a in pairs(cfg.abilities) do
	assert(a.kind == "combat" or a.kind == "utility", "ability kind")
	assert(a.desc:find("%%s"), "desc has the value: " .. a.name)
end

-- ---------------------------------------------------------------- species lookups
eq(K.species("ember_whelp", cfg).name, "Ember Whelp")
eq(K.species("nope", cfg), nil)
eq(K.speciesByMonster("ash cat", cfg).key, "ash_cat", "any case")
eq(K.speciesByMonster(nil, cfg), nil)

-- ---------------------------------------------------------------- XP curve (the numbers in pets_config.lua)
eq(K.xpNeed(1, cfg), 8)
eq(K.xpNeed(10, cfg), 200)
eq(K.xpNeed(25, cfg), 724)
eq(K.xpNeed(49, cfg), 1859)
eq(K.xpNeed(50, cfg), nil, "no next level at the max")
eq(K.xpNeed(0, cfg), nil)
eq(K.totalFor(1, cfg), 0)
eq(K.totalFor(10, cfg), 736)
eq(K.totalFor(25, cfg), 7180)
eq(K.totalFor(50, cfg), 38871)
local lvl, into, need, pct = K.levelOf(0, cfg)
eq(lvl, 1); eq(into, 0); eq(need, 8); eq(pct, 0)
lvl, into, need = K.levelOf(8, cfg)
eq(lvl, 2, "8 XP = level 2"); eq(into, 0)
lvl, into, need, pct = K.levelOf(736 + 100, cfg)
eq(lvl, 10); eq(into, 100); eq(need, 200); eq(pct, 50)
lvl, into, need, pct = K.levelOf(10 ^ 9, cfg)
eq(lvl, 50, "capped"); eq(need, 0); eq(pct, 100)
eq(K.capXp(-5, cfg), 0)
eq(K.capXp(10 ^ 9, cfg), 38871)
eq(K.capXp("12", cfg), 12)
-- every level up to the max is reachable and levelOf(totalFor(L)) == L
for L = 1, cfg.maxLevel do
	eq((K.levelOf(K.totalFor(L, cfg), cfg)), L, "level " .. L)
end

-- ---------------------------------------------------------------- kill XP
eq(K.killXp({tier = "normal", monsterExp = 700, ownerLevel = 300}, cfg), 1, "dragon at 300 counts")
eq(K.killXp({tier = "normal", monsterExp = 700, ownerLevel = 400}, cfg), 0, "dragon at 400 is trivial")
eq(K.killXp({tier = "magic", monsterExp = 5, ownerLevel = 400}, cfg), 2, "tiered always counts")
eq(K.killXp({tier = "legendary", monsterExp = 5, ownerLevel = 400}, cfg), 8)
eq(K.killXp({tier = "boss", monsterExp = 5, ownerLevel = 400}, cfg), 11)
eq(K.killXp({tier = "rare", monsterExp = 5, ownerLevel = 1, summon = true}, cfg), 0, "summons never")
eq(K.killXp(nil, cfg), 0)

-- ---------------------------------------------------------------- abilities
eq(K.abilityValue("mend", 1, 100, cfg), 4)
eq(K.abilityValue("mend", 50, 100, cfg), 7.9)
eq(K.abilityValue("ward", 50, 100, cfg), 11.9)
eq(K.abilityValue("goldFind", 1, 1, cfg), 2)
eq(K.abilityValue("goldFind", 50, 1, cfg), 6.9)
eq(K.abilityValue("itemFind", 50, 1, cfg), 5.9)
eq(K.abilityValue("fetch", 1, 1, cfg), 3)
eq(K.abilityValue("fetch", 50, 1, cfg), 5)
eq(K.abilityValue("nope", 50, 1, cfg), 0)
eq(K.abilityValue("mend", 999, 1, cfg), 7.9, "level clamped")
local lo, hi = K.auraDamage(300, 50, cfg)
eq(lo, 220); eq(hi, 330)
eq(K.abilityValue("aura", 50, 300, cfg), 275, "aura shows the middle")
eq(K.abilityValue("aura", 50, 1000, cfg), 450)
eq(K.mendAmount(1, 10000, cfg), 400)
eq(K.mendAmount(50, 10000, cfg), 790)
eq(K.number(7.5), "7.5"); eq(K.number(12), "12"); eq(K.number(nil), "0")

local whelp = K.species("ember_whelp", cfg)
assert(K.hasAbility(whelp, "aura", 1, cfg), "first ability from level 1")
assert(not K.hasAbility(whelp, "ward", cfg.secondAt - 1, cfg), "second ability locked")
assert(K.hasAbility(whelp, "ward", cfg.secondAt, cfg), "second ability at secondAt")
assert(not K.hasAbility(whelp, "mend", 50, cfg), "not its ability")
local list = K.abilitiesOf(whelp, 5, 300, cfg)
eq(#list, 2)
eq(list[1].key, "aura"); eq(list[1].unlocked, true); eq(list[1].unlockAt, 1)
eq(list[2].key, "ward"); eq(list[2].unlocked, false); eq(list[2].unlockAt, cfg.secondAt)
assert(list[2].desc:find("6.5%%"), "ward text at level 5: " .. list[2].desc)
eq(list[2].cooldown, 45)

-- ---------------------------------------------------------------- zones
eq(K.zoneRule({}, cfg), "full")
eq(K.zoneRule(nil, cfg), "full")
eq(K.zoneRule({rift = true}, cfg), "utility")
eq(K.zoneRule({dungeon = true}, cfg), "utility")
local r, z = K.zoneRule({rift = true, arena = true}, cfg)
eq(r, "banned"); eq(z, "arena")
eq((K.zoneRule({pvpZone = true}, cfg)), "banned")
eq((K.zoneRule({siege = true}, cfg)), "banned")
assert(K.abilityActive("combat", "full", false))
assert(not K.abilityActive("combat", "full", true), "combat pauses in PvP")
assert(not K.abilityActive("combat", "utility", false), "combat off in utility zones")
assert(K.abilityActive("utility", "utility", true), "utility keeps working")
assert(not K.abilityActive("utility", "banned", false))

-- ---------------------------------------------------------------- drops
eq(K.dropChance(whelp, "Dragon", "normal", false), 1 / 2500, "listed monster, any case, no level rule")
eq(K.dropChance(whelp, "Rat", "normal", true), 0, "not listed")
local dusk = K.species("duskwing", cfg)
eq(K.dropChance(dusk, "Rat", "normal", false), 0, "any-monster drop needs a counted kill")
eq(K.dropChance(dusk, "Rat", "normal", true), 1 / 20000)
eq(K.dropChance(dusk, "Rat", "legendary", true), 8 / 20000)
eq(K.dropChance(K.species("lantern_wisp", cfg), "Dragon", "boss", true), 0, "store pets never drop")
eq(K.rollDrop("Dragon", "normal", function() return 0 end, cfg, true), "ember_whelp")
eq(K.rollDrop("Rat", "normal", function() return 0 end, cfg, true), "duskwing")
eq(K.rollDrop("Rat", "normal", function() return 0 end, cfg, false), nil)
eq(K.rollDrop("Dragon", "normal", function() return 0.99 end, cfg, true), nil)
-- a seeded run: about 1 in 2500 dragons
math.randomseed(7)
local got = 0
for _ = 1, 250000 do
	if K.rollDrop("dragon", "normal", math.random, cfg, false) == "ember_whelp" then
		got = got + 1
	end
end
assert(got > 60 and got < 140, "about 100 whelps in 250,000 dragons: " .. got)
eq(K.grantKind({ember_whelp = true}, "ember_whelp"), "xp")
eq(K.grantKind({}, "ember_whelp"), "new")

-- ---------------------------------------------------------------- names
eq(K.validName("  mister   whiskers ", cfg), "Mister Whiskers")
eq(K.validName("EMBER", cfg), "Ember")
assert(not K.validName("a", cfg), "too short")
assert(not K.validName(string.rep("a", 17), cfg), "too long")
assert(not K.validName("x1", cfg), "digits")
assert(not K.validName("<b>", cfg), "symbols")
assert(not K.validName(nil, cfg))
local n, why = K.validName("dragon", cfg, function(name) return name == "Dragon" end)
assert(not n and why:find("creature"), "reserved")

-- ---------------------------------------------------------------- cooldowns and summon errors
eq(K.cooldownLeft(105, 100), 5); eq(K.cooldownLeft(100.2, 100), 1); eq(K.cooldownLeft(90, 100), 0); eq(K.cooldownLeft(nil, 1), 0)
eq(K.summonError({owned = true, now = 100}, cfg), nil)
assert(K.summonError({owned = false, now = 100}, cfg):find("own"))
assert(K.summonError({owned = true, now = 100, zone = "banned", zoneName = "arena"}, cfg):find("arena"))
assert(K.summonError({owned = true, now = 100, deathReady = 150}, cfg):find("50 s"))
assert(K.summonError({owned = true, now = 100, summonReady = 103}, cfg):find("3 s"))

-- ---------------------------------------------------------------- gold
local c = K.coins(1234567)
eq(c.crystal, 123); eq(c.platinum, 45); eq(c.gold, 67)
c = K.coins(-5)
eq(c.crystal + c.platinum + c.gold, 0)
eq(K.goldBonus(1000, 2.5, function() return 0.99 end), 25)
eq(K.goldBonus(500, 2.5, function() return 0.1 end), 13, "12.5 rounds up when the roll is below .5")
eq(K.goldBonus(500, 2.5, function() return 0.9 end), 12)
eq(K.goldBonus(0, 5), 0); eq(K.goldBonus(100, 0), 0)

-- ---------------------------------------------------------------- following, blocking, rest
local P = function(x, y, z) return {x = x, y = y, z = z or 7} end
eq(K.distance(P(1, 1), P(4, 2)), 3)
eq(K.distance(P(1, 1), P(1, 1, 8)), math.huge)
-- owner at 10,10, pet at 11,10: a monster at 12,10 targets the owner but cannot reach it -> the pet blocks
assert(K.blocking(P(11, 10), P(10, 10), {{pos = P(12, 10)}}, cfg), "pet in the way")
assert(not K.blocking(P(11, 10), P(10, 10), {{pos = P(11, 11)}}, cfg), "monster already next to the owner")
assert(not K.blocking(P(11, 10), P(10, 10), {{pos = P(14, 10)}}, cfg), "monster far from the pet")
assert(not K.blocking(P(11, 10), P(10, 10), {}, cfg))
-- a monster without a path to the owner (it wanders in the corridor behind the pet) counts within block.pathRange
assert(K.blocking(P(11, 10), P(10, 10), {{pos = P(14, 10), noPath = true}}, cfg), "no path, 3 from the pet")
assert(not K.blocking(P(11, 10), P(10, 10), {{pos = P(16, 10), noPath = true}}, cfg), "no path, beyond pathRange")
assert(not K.blocking(P(11, 10), P(10, 10), {{pos = P(14, 10), noPath = false}}, cfg), "has a path: it is coming")
assert(not K.blocking(P(11, 10), P(10, 10), {{pos = P(9, 11), noPath = true}}, cfg), "no path but next to the owner")
eq(K.restReason({now = 1}), nil)
eq(K.restReason({inPz = true, zone = "banned", now = 1}), "zone", "zone first")
eq(K.restReason({inPz = true, otherSummons = true, now = 1}), "pz")
eq(K.restReason({otherSummons = true, now = 1}), "summons")
eq(K.restReason({hiddenUntil = 5, now = 1}), "hidden")
eq(K.restReason({hiddenUntil = 5, now = 6}), nil)
assert(K.restText("pz"):find("protection zone"))
eq(K.restText(nil), nil)

-- ---------------------------------------------------------------- view
local v = K.view({id = 3, species = "frost_whelp", name = "", xp = 736 + 100, active = 1, source = "drop"}, 300, 0, cfg)
eq(v.name, "Frost Whelp", "species name when unnamed")
eq(v.level, 10); eq(v.pct, 50); eq(v.active, true); eq(v.look, 283); eq(#v.abilities, 2)
v = K.view({id = 4, species = "ash_cat", name = "Soot", xp = 0, active = 0}, 300, 0, cfg)
eq(v.name, "Soot"); eq(v.active, false)
eq(K.view({id = 5, species = "retired", name = "", xp = 0}, 1, 0, cfg), nil, "unknown species is skipped")

print("pets: all asserts passed")
