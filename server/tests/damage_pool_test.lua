-- Run from the server/ folder: luajit tests/damage_pool_test.lua && lua5.3 tests/damage_pool_test.lua (CI runs both)
-- O473 (2026-11-10): the one additive "increased damage" pool. What this holds:
--   * the numbers (damage_pool_config.lua) and the pure rules (damage_pool_core.lua): each entry alone, each cap, the group cap,
--     the sum, the soft cap (the tree's, applied once), a character with nothing gets exactly 1;
--   * the real ChaosPassiveDealt event: the tree, the worn Spell Damage and Paragon add into ONE pool, the sources that register
--     (unique passives, gems, masteries, card sets, charms, the sword edge) add into the same sum, the attributes, the class
--     factor stay multiplicative, a heal takes the tree's Healing only, a Necromancer minion takes the death percent;
--   * every damage path of tests/spell_paths_test.lua is one hit through that one event: each provider is asked exactly once per
--     part, no source counts twice (the old multiplier of each source is gone: read from the source files);
--   * the sources themselves: the registered names, the caps they hold (gems.lua / charms.lua / cards.lua / weapon_families.lua /
--     unique_passives.lua / supports.lua keep their own tests for each entry alone).
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function near(a, b, tol, m)
	ok(math.abs(a - b) <= tol * math.max(1, math.abs(b)), (m or "") .. ": " .. tostring(a) .. " vs " .. tostring(b))
end
local function readAll(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- the mocked engine: unknown ALL_CAPS names become numbers
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {}
local registered = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function(self) local l = rawget(self, "_last"); registered[l[1]] = l[2] end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function Condition(t) local c = {t = t, p = {}}; function c:setTicks(x) end; function c:setParameter(k, v) self.p[k] = v end; return c end
function addEvent() end
os.mtime = function() return 1000 end
dofile("data/scripts/chaos/passivetree_effects.lua")
local ev = registered["ChaosPassiveDealt"]
ok(ev ~= nil, "the passive damage event is registered")
local P = ChaosDamagePool
local cfg = P.config

-- ============================================================================================== the numbers
ok(cfg.sources.uniques.each == 10 and cfg.sources.uniques.cap == 40, "uniques: +10 each, at most 40")
ok(cfg.sources.gems.cap == 25 and cfg.sources.gems.capPhysical == 12, "gems: at most 25, physical 12")
ok(cfg.sources.masteries.each == 3 and cfg.sources.masteries.cap == 12, "masteries: +3 each, at most 12")
ok(cfg.sources.cardSets.cap == 4, "card sets: at most 4")
ok(cfg.groups.extras.cap == 6 and cfg.sources.charms.group == "extras" and cfg.sources.families.group == "extras",
	"charms and weapon families: at most 6 together")
ok(P.softCap() == 150 and select(2, P.softCap()) == 60, "the soft cap is the tree's: 150, H 60 (unchanged)")
local gcfg = dofile("data/lib/chaos_gems_config.lua")
ok(gcfg.effects.dmg_fire.cap == cfg.sources.gems.cap and gcfg.effects.dmg_holy.cap == cfg.sources.gems.cap, "the gem effect caps are the pool's")
ok(gcfg.effects.dmg_physical.cap == cfg.sources.gems.capPhysical, "(physical too)")
local ccfg = dofile("data/scripts/chaos/cards_config.lua")
ok(ccfg.sets and true, "the card config loads")

-- ============================================================================================== the pure rules
near(P.soft(0), 0, 1e-12, "soft(0)")
near(P.soft(150), 150, 1e-12, "soft at the cap")
near(P.soft(300), ChaosSoftCap(300, 150, 60), 1e-12, "soft = the tree's ChaosSoftCap at 300")
near(P.soft(190), 150 + 60 * math.log(1 + 40 / 60), 1e-9, "soft(190)")
near(P.factor(0), 1, 1e-12, "nothing: exactly 1")
near(P.factor(-5), 1, 1e-12, "never below 1")
near(P.factor(40), 1.4, 1e-12, "factor(40)")
for _, raw in ipairs({10, 100, 150, 151, 400, 1000}) do
	near(P.factor(raw), 1 + ChaosSoftCap(raw, 150, 60) / 100, 1e-12, "factor " .. raw)
end
-- each entry alone, each cap
local function alone(name, raw, ctype)
	local list, sum = P.combine({[name] = raw}, 0, ctype or COMBAT_FIREDAMAGE)
	return sum, list
end
near(alone("uniques", 10), 10, 1e-12, "uniques 10 alone")
near(alone("uniques", 55), 40, 1e-12, "uniques held at 40")
near(alone("gems", 20), 20, 1e-12, "gems 20 alone")
near(alone("gems", 40), 25, 1e-12, "gems held at 25")
near(alone("gems", 40, COMBAT_PHYSICALDAMAGE), 12, 1e-12, "physical gems held at 12")
near(alone("gems", 8, COMBAT_PHYSICALDAMAGE), 8, 1e-12, "physical gems 8 alone")
near(alone("masteries", 3), 3, 1e-12, "masteries 3 alone")
near(alone("masteries", 30), 12, 1e-12, "masteries held at 12")
near(alone("cardSets", 4), 4, 1e-12, "card set 4 alone")
near(alone("cardSets", 9), 4, 1e-12, "card set held at 4")
near(alone("charms", 5), 5, 1e-12, "charms 5 alone")
near(alone("charms", 15), 6, 1e-12, "charms held at 6")
near(alone("families", 2), 2, 1e-12, "the sword edge 2 alone")
near(alone("paragon", 26), 26, 1e-12, "Paragon: no cap of its own")
do
	local _, sum = P.combine({charms = 5, families = 2}, 0, COMBAT_FIREDAMAGE)
	near(sum, 6, 1e-12, "charms 5 + family 2 share one cap of 6")
	_, sum = P.combine({charms = 3, families = 2}, 0, COMBAT_FIREDAMAGE)
	near(sum, 5, 1e-12, "charms 3 + family 2 = 5, under it")
	local list
	list, sum = P.combine({tree = 999, uniques = 50, gems = 99, masteries = 99, cardSets = 99, charms = 4, families = 99, paragon = 26},
		60, COMBAT_FIREDAMAGE)
	near(sum, 60 + 40 + 25 + 12 + 4 + 6 + 26, 1e-12, "everything at its cap: the tree raw is the caller's, the rest held")
	ok(#list == 8 and list[1].name == "tree" and list[2].name == "uniques" and list[8].name == "paragon", "the lines come in the config's order")
	ok(list[2].capped and list[3].capped and not list[8].capped, "a held entry says so")
	list = P.combine({}, 0, COMBAT_FIREDAMAGE)
	ok(#list == 1 and list[1].name == "tree", "a character with nothing has the tree line only")
end
ok(next(P.raws({attacker = {}, creature = {}, cache = {}}, COMBAT_HEALING, "primary")) == nil, "a heal asks no source")
ok(next(P.raws({attacker = {}, creature = {}, cache = {}}, COMBAT_NONE, "primary")) == nil, "no type asks no source")

-- ============================================================================================== the real event
local function attacker(id)
	local a = {}
	function a:isPlayer() return true end
	function a:getId() return id end
	return a
end
local mon = {isPlayer = function() return false end, getId = function() return 500 end}
local atk = attacker(7)
local calls
local function stand(name, raw, only)
	-- a stand-in provider: gives `raw` (or a table by combat type) and counts its asks
	P.register(name, function(hit, ctype, which)
		calls[name] = (calls[name] or 0) + 1
		calls[name .. "/" .. which] = (calls[name .. "/" .. which] or 0) + 1
		if type(raw) == "table" then
			return raw[ctype] or 0
		end
		return raw
	end)
end
local function reset()
	calls = {}
	for _, name in ipairs({"uniques", "gems", "masteries", "cardSets", "charms", "families"}) do
		stand(name, 0)
	end
end
reset()
local function hit(damage, ctype, origin, sdamage, stype)
	local p, pt, s = ev.onHealthChange(mon, atk, -damage, ctype or COMBAT_FIREDAMAGE, -(sdamage or 0), stype or COMBAT_NONE, origin or ORIGIN_SPELL)
	return -p, -s
end
local origLine = ChaosPassiveLineFactor
ChaosPassiveLineFactor = function() return 1 end -- the class factor off unless a test turns it on
-- a character with nothing gets exactly 1
ChaosPassiveCache[7] = {}
ok(hit(1000) == 1000, "nothing: 1000 stays 1000 (a spell)")
ok(hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) == 1000, "nothing: a melee hit")
ChaosPassiveCache[7] = nil
ok(hit(1000) == 1000, "no tree state at all: untouched")
ChaosPassiveCache[7] = {}
-- the tree alone, then each source alone
ChaosPassiveCache[7] = {incrementFire = 50}
ok(hit(1000) == 1500, "tree +50: x1.5")
ChaosPassiveCache[7] = {}
for _, row in ipairs({{"uniques", 10, 1100}, {"gems", 20, 1200}, {"masteries", 3, 1030}, {"cardSets", 4, 1040}, {"charms", 5, 1050},
		{"families", 2, 1020}}) do
	reset()
	stand(row[1], row[2])
	ok(hit(1000) == row[3], row[1] .. " alone: +" .. row[2] .. " raw -> " .. row[3] .. " (" .. hit(1000) .. ")")
end
reset()
-- Paragon alone
ChaosPassiveCache[7] = {paragonDamage = 26}
ok(hit(1000) == 1260, "Paragon +26: x1.26")
-- the sum: one pool, not a product: tree 50 + Paragon 10 + gems 10 + uniques 10 = 80 -> x1.8 (the old way: 1.5 x 1.1 x 1.1 x 1.1)
ChaosPassiveCache[7] = {incrementFire = 50, paragonDamage = 10}
stand("gems", 10)
stand("uniques", 10)
ok(hit(1000) == 1800, "tree 50 + Paragon 10 + gems 10 + uniques 10: one pool x1.80 (the product would be x2.00): " .. hit(1000))
ok(hit(1000) < math.floor(1000 * 1.5 * 1.1 * 1.1 * 1.1), "less than the old product")
-- the soft cap applies once to the whole sum
reset()
ChaosPassiveCache[7] = {incrementFire = 100, paragonDamage = 20}
stand("uniques", 40)
stand("gems", 25)
stand("cardSets", 4)
stand("charms", 4)
stand("families", 2)
stand("masteries", 3)
do
	local raw = 100 + 20 + 40 + 25 + 4 + 6 + 3
	local expect = math.floor(1000 * (1 + ChaosSoftCap(raw, 150, 60) / 100) + 1e-6)
	ok(raw == 198, "the sum is 198")
	ok(hit(1000) == expect, "everything: the soft cap once on 198: " .. hit(1000) .. " vs " .. expect)
	ok(hit(1000) < 1000 * (1 + raw / 100), "past the cap the sum counts less")
end
-- the same sources but over their caps: held
reset()
ChaosPassiveCache[7] = {}
stand("uniques", 90) stand("gems", 90) stand("cardSets", 90) stand("charms", 90) stand("families", 90) stand("masteries", 90)
ok(hit(1000, COMBAT_FIREDAMAGE) == math.floor(1000 * (1 + ChaosSoftCap(40 + 25 + 4 + 6 + 12, 150, 60) / 100) + 1e-6),
	"every entry at its cap: " .. hit(1000))
ok(hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) == math.floor(1000 * (1 + (40 + 12 + 4 + 6 + 12) / 100) + 1e-6),
	"physical gems at 12")
-- the attributes and the class factor stay multiplicative, outside the pool
reset()
stand("uniques", 10)
ChaosPassiveCache[7] = {incrementFire = 40, intelligence = 60}
do
	local m = (1 + 50 / 100) * (1 + ChaosPassiveCharStat(60, "intelligence") / 230)
	ok(hit(1000) == math.floor(1000 * m + 1e-6), "intelligence multiplies the pool: " .. hit(1000) .. " vs " .. math.floor(1000 * m))
	ChaosPassiveLineFactor = function() return 1.25 end
	ok(hit(1000) == math.floor(1000 * m * 1.25 + 1e-6) or math.abs(hit(1000) - 1000 * m * 1.25) <= 1, "the class factor multiplies the pool")
	ChaosPassiveLineFactor = function() return 1 end
end
-- a heal: the tree's Healing only; nothing else asks
reset()
stand("uniques", 40) stand("gems", {[COMBAT_HEALING] = 25})
ChaosPassiveCache[7] = {incrementHealth = 30, paragonDamage = 20, incrementFire = 90}
do
	local p = ev.onHealthChange(mon, atk, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
	ok(p == 1300, "a heal takes Healing +30 only: " .. p)
	ok(next(calls) == nil, "no source was asked for the heal")
end
-- a Necromancer minion's hit also takes the death percent, inside the pool
reset()
ChaosPassiveCache[7] = {incrementPhysical = 10, incrementDeath = 20, multiIncrement = 4}
ChaosNecroMinions = ChaosNecroMinions or {}
ChaosNecroMinions.dealing = 1
stand("gems", 5)
ok(hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) == 1390, "a minion's physical hit: own 10 + death 20 + all elements 4 + gems 5 in one pool: " .. hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL))
ChaosNecroMinions.dealing = 0
ok(hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) == 1150, "the owner's own physical hit: only its 10 (plus gems 5)")
-- the worn Spell Damage joins for a spell or a wand, never for a melee hit (as before)
reset()
ChaosPassiveCache[7] = {incrementFire = 10, gearSpell = 20}
ok(hit(1000, COMBAT_FIREDAMAGE, ORIGIN_SPELL) == 1300, "gear Spell Damage joins the pool for a spell")
ok(hit(1000, COMBAT_FIREDAMAGE, ORIGIN_MELEE) == 1100, "not for a melee hit")

-- ============================================================================================== every path, exactly once
-- the paths of tests/spell_paths_test.lua and the matrix of the O468 audit all end as one hit of the player (or its owner's
-- minion, bite, aura, pulse, snare, mine) through ChaosPassiveDealt: one pool per part, each source asked once per part
reset()
ChaosPassiveCache[7] = {incrementFire = 10, incrementPhysical = 10}
stand("gems", 10) stand("uniques", 10) stand("cardSets", 4) stand("charms", 3) stand("families", 2) stand("masteries", 3)
local ORIGINS = {spell = ORIGIN_SPELL, melee = ORIGIN_MELEE, ranged = ORIGIN_RANGED, wand = ORIGIN_WAND, condition = ORIGIN_CONDITION,
	none = ORIGIN_NONE}
local expect = math.floor(1000 * (1 + (10 + 10 + 10 + 4 + 5 + 3) / 100) + 1e-6)
for name, origin in pairs(ORIGINS) do
	calls = {}
	local d = hit(1000, COMBAT_FIREDAMAGE, origin)
	ok(d == expect, name .. ": one pool, " .. d .. " vs " .. expect)
	for _, src in ipairs({"uniques", "gems", "masteries", "cardSets", "charms", "families"}) do
		ok(calls[src] == 1, name .. ": " .. src .. " asked once for one damage part (" .. tostring(calls[src]) .. ")")
	end
end
-- two parts: one ask each, never more
calls = {}
local a, b = hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE, 500, COMBAT_FIREDAMAGE)
ok(calls.gems == 2 and calls["gems/primary"] == 1 and calls["gems/secondary"] == 1, "two parts: one ask each")
-- a hit inside the class spell factor's guard (the Beastmaster bite, the pet aura, a Necromancer minion) is ORIGIN_SPELL as the owner:
-- one pool, no spell factor
ChaosSpellFactor.depth = 1
calls = {}
ok(hit(1000, COMBAT_PHYSICALDAMAGE, ORIGIN_SPELL) == math.floor(1000 * (1 + (10 + 10 + 10 + 4 + 5 + 3) / 100) + 1e-6), "a bite inside the guard: one pool")
ok(calls.gems == 1, "a bite: the sources asked once")
ChaosSpellFactor.depth = 0
-- a keystone proc is a share of a hit that had the pool: not again
ChaosKeystones = {depth = 1}
calls = {}
ok(hit(1000, COMBAT_FIREDAMAGE, ORIGIN_SPELL) == 1000 and next(calls) == nil, "a keystone proc: no second pool")
ChaosKeystones.depth = 0
-- the pool is computed in one place
for _, f in ipairs({"gems.lua", "cards.lua", "charms.lua", "weapon_families.lua", "unique_passives.lua", "supports.lua", "passivetree_effects.lua",
		"combat_stats.lua", "passivetree_totals.lua", "paragon.lua"}) do
	local text = readAll("data/scripts/chaos/" .. f)
	local callsPart = select(2, text:gsub("ChaosDamagePool%.part%(", "")) + select(2, text:gsub("ChaosPassivePoolPart%(", ""))
	if f == "passivetree_effects.lua" then
		ok(callsPart == 4, f .. ": the pool is built by the one event (the function, its one ChaosDamagePool.part and the two parts of the hit), found " .. callsPart)
	else
		ok(callsPart == 0, f .. ": does not build the pool itself")
	end
end

-- ============================================================================================== the sources: no old multiplier left
local gems = readAll("data/scripts/chaos/gems.lua")
ok(gems:find('ChaosDamagePool.register("gems"', 1, true), "gems register in the pool")
ok(gems:find("attacker:isPlayer()", 1, true), "the gem event leaves a player's own hit to the pool (summons keep it)")
local charms = readAll("data/scripts/chaos/charms.lua")
ok(charms:find('ChaosDamagePool.register("charms"', 1, true), "charms register in the pool")
ok(charms:find("attacker:isPlayer()", 1, true), "the charm event leaves a player's own hit to the pool")
local cards = readAll("data/scripts/chaos/cards.lua")
ok(cards:find('ChaosDamagePool.register("cardSets"', 1, true), "card sets register in the pool")
ok(not cards:find('K.setExtra(element, "damage"', 1, true), "the card set's damage part is no multiplier in the hit event any more")
local fams = readAll("data/scripts/chaos/weapon_families.lua")
ok(fams:find('ChaosDamagePool.register("families"', 1, true), "the weapon family registers in the pool")
local famCore = readAll("data/scripts/chaos/weapon_families_core.lua")
ok(not famCore:find("t.edge) * stacks", 1, true), "the sword's edge is no multiplier of the hit")
local up = readAll("data/scripts/chaos/unique_passives.lua")
ok(up:find('ChaosDamagePool.register("uniques"', 1, true), "unique passives register in the pool")
local sup = readAll("data/scripts/chaos/supports.lua")
ok(sup:find('ChaosDamagePool.register("masteries"', 1, true), "damage masteries register in the pool")
local pt = readAll("data/scripts/chaos/passivetree_effects.lua")
ok(pt:find('ChaosDamagePool.register("paragon"', 1, true), "Paragon registers in the pool")
ok(not pt:find("ChaosParagonDamageMultiplier", 1, true), "Paragon is no multiplier any more")
local names = {}
for _, name in ipairs(P.names) do names[name] = true end
ok(names.paragon and names.uniques and names.gems and names.masteries and names.cardSets and names.charms and names.families,
	"the seven sources and Paragon are registered with the pool")

ChaosPassiveLineFactor = origLine
if fails > 0 then
	error(fails .. " of " .. checks .. " damage pool checks failed")
end
print("damage_pool_test: " .. checks .. " checks OK")
