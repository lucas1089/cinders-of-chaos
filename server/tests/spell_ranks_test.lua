-- Run from the server/ folder: luajit tests/spell_ranks_test.lua && lua5.3 tests/spell_ranks_test.lua (CI runs both)
-- O686 phase 2: the spell rank core (spell_ranks_core.lua, numbers in spell_ranks_config.lua), the read API of
-- data/lib/chaos_spell_ranks.lua, and the places the opcode, the storage block and the table were taken.

local checks, fails = 0, 0
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
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " vs " .. tostring(b))
end

local P = dofile("data/scripts/chaos/spell_ranks_core.lua")
local cfg = dofile("data/scripts/chaos/spell_ranks_config.lua")

-- ---------------------------------------------------------------- the switch and the shipped numbers
eq(cfg.enabled, false, "ships switched off")
eq(cfg.opcode, 168, "opcode 168")
eq(cfg.maxRank, 20, "rank 20")
eq(cfg.pvp.rank, 0.5, "PvP half (owner 2026-11-20)")
eq(cfg.pvp.awakening, false, "no awakening in PvP")
eq(cfg.pvp.combos, false, "no combos in PvP")
eq(next(cfg.reassigned), nil, "no reassigned id yet")
eq(cfg.storage.grantVersion, 7107503, "the launch grant key stays reserved")

-- ---------------------------------------------------------------- the cost curve (design 1.4)
near(P.cumCost(20, cfg), 42, 1e-9, "ranks 1 to 20 cost 42 SP")
local design = {0.06, 0.16, 0.29, 0.44, 0.62, 0.81, 1.02, 1.25, 1.49, 1.75, 2.01, 2.29, 2.59, 2.89, 3.21, 3.53, 3.87, 4.22, 4.57, 4.94}
for r = 1, 20 do
	near(P.rankCost(r, cfg), design[r], 0.011, "rank " .. r .. " costs about the design's " .. design[r])
end
for r = 2, 20 do
	ok(P.rankCost(r, cfg) > P.rankCost(r - 1, cfg), "costs rise: " .. r)
end
eq(P.cumCost(0, cfg), 0, "rank 0 costs nothing")
eq(P.cumCost(99, cfg), P.cumCost(20, cfg), "past the top: the top")
do
	local r, into, nextCost = P.rankOf(0, 1, cfg)
	eq(r, 0, "no SP: rank 0")
	near(nextCost, P.rankCost(1, cfg), 1e-9, "next rank cost")
	r = P.rankOf(P.cumCost(5, cfg), 1, cfg)
	eq(r, 5, "exactly the cost of rank 5")
	r = P.rankOf(P.cumCost(5, cfg) - 0.001, 1, cfg)
	eq(r, 4, "just under rank 5")
	r, into, nextCost = P.rankOf(1000, 1, cfg)
	eq(r, 20, "capped at 20")
	eq(nextCost, 0, "nothing after 20")
	r = P.rankOf(P.cumCost(10, cfg) * 0.35, 0.35, cfg)
	eq(r, 10, "a weight 0.35 spell needs 0.35 of the SP")
end
near(P.spForRank(20, 0.35, cfg), 14.7, 1e-9, "an ultimate needs 14.7 SP (design: about 15)")

-- ---------------------------------------------------------------- the weight of a spell (needScale)
do
	local w, s = P.weight({cooldownMs = 4000}, cfg)
	eq(s, 1.0, "cooldown 4 s: 1.0")
	eq(select(2, P.weight({cooldownMs = 8000}, cfg)), 1.0, "cooldown 8 s: 1.0")
	eq(select(2, P.weight({cooldownMs = 9000}, cfg)), 0.8, "cooldown 9 s: 0.8")
	eq(select(2, P.weight({cooldownMs = 13000}, cfg)), 0.8, "cooldown 13 s: 0.8")
	eq(select(2, P.weight({cooldownMs = 20000}, cfg)), 0.8, "cooldown 20 s: 0.8 (default)")
	eq(select(2, P.weight({cooldownMs = 35000}, cfg)), 0.35, "ultimate 35 s: 0.35")
	eq(select(2, P.weight({cooldownMs = 60000}, cfg)), 0.35, "ultimate 60 s: 0.35")
	w, s = P.weight({heal = true, cooldownMs = 60000}, cfg)
	eq(s, 0.7, "a heal is 0.7 whatever its cooldown")
	eq(w, "heal", "heal weight class")
end

-- ---------------------------------------------------------------- the kill value
near(P.refXp(100, cfg), 27757437, 1, "ref at a point")
near(P.refXp(125, cfg), (27757437 + 39130589) / 2, 1, "ref between points: linear")
eq(P.refXp(1, cfg), 45627, "ref at level 1")
eq(P.refXp(9999, cfg), 1154319240, "ref above the last point: flat")
do
	local ref = P.refXp(500, cfg)
	near(P.killValue(ref / 1100, 500, cfg), 1 / 1100, 1e-12, "a kill of 1/1100 of the hour")
	eq(P.killValue(ref * 10, 500, cfg), 0.05, "a huge kill is clamped to 3 minutes")
	eq(P.killValue(0, 500, cfg), 0, "no experience, no value")
	eq(P.killValue(-5, 500, cfg), 0, "negative experience, no value")
	-- the level of the player, never of the monster: a low kill at a high level is worth little
	ok(P.killValue(1e6, 1500, cfg) < P.killValue(1e6, 700, cfg), "the same kill is worth less to a higher level")
end

-- ---------------------------------------------------------------- exclusions
do
	local c = {level = 200, exp = 100}
	ok(P.counts(c, cfg), "a normal kill counts")
	local ok1, why = P.counts({level = 200, exp = 100, tester = true}, cfg)
	ok(not ok1 and why == "tester", "tester characters earn nothing")
	ok1, why = P.counts({level = 200, exp = 100, pvp = true}, cfg)
	ok(not ok1 and why == "pvp", "PvP earns nothing")
	ok1, why = P.counts({level = 200, exp = 100, monsterMaster = {}}, cfg)
	ok(not ok1 and why == "summon", "summons and clones pay nothing")
	ok1, why = P.counts({level = 3, exp = 100}, cfg)
	ok(not ok1 and why == "level", "the tutorial pays nothing")
	ok1, why = P.counts({level = 200, exp = 0}, cfg)
	ok(not ok1 and why == "noexp", "training dummies pay no experience, so no SP")
end

-- ---------------------------------------------------------------- credit by damage share
local function rec(total, spells)
	local r = P.newRecord()
	for id, d in pairs(spells) do
		P.record(r, id, d, cfg)
	end
	P.record(r, 0, total - (function() local s = 0 for _, d in pairs(spells) do s = s + d end return s end)(), cfg)
	return r
end
local all = function() return true end
do
	local r = rec(1000, {[10] = 300, [11] = 100})
	eq(r.total, 1000, "record total counts the auto bucket")
	local sh = P.shares(r, 5000, nil, 0, all, cfg)
	near(sh[10], 0.3, 1e-12, "share by damage: 30%")
	near(sh[11], 0.1, 1e-12, "share by damage: 10%")
	eq(sh[0], nil, "auto attacks earn nothing")
	-- not eligible: stays in the denominator
	local sh2 = P.shares(r, 5000, nil, 0, function(id) return id == 10 end, cfg)
	near(sh2[10], 0.3, 1e-12, "an excluded spell leaves the denominator alone")
	eq(sh2[11], nil, "an excluded spell earns nothing")
	-- the 2% floor
	local small = rec(90, {[10] = 90})
	eq(next(P.shares(small, 5000, nil, 0, all, cfg)), nil, "under 2% of the monster's health: nothing (no leeching)")
	local edge = rec(100, {[10] = 100})
	near(P.shares(edge, 5000, nil, 0, all, cfg)[10], 1, 1e-12, "exactly 2%: counts")
	eq(next(P.shares(nil, 5000, nil, 0, all, cfg)), nil, "no record: nothing")
	eq(next(P.shares(r, 0, nil, 0, all, cfg)), nil, "unknown monster health: nothing")
end
do
	-- area: each monster hit is its own table; two records, two kills
	local a, b = rec(500, {[20] = 500}), rec(100, {[20] = 100})
	near(P.shares(a, 1000, nil, 0, all, cfg)[20], 1, 1e-12, "area, monster A")
	near(P.shares(b, 1000, nil, 0, all, cfg)[20], 1, 1e-12, "area, monster B (10% of health)")
	-- more than 16 spell ids: the rest fall into the auto bucket, the total keeps counting
	local many = P.newRecord()
	for id = 1, 20 do
		P.record(many, id, 10, cfg)
	end
	eq(many.n, 16, "at most 16 spell ids per monster")
	eq(many.total, 200, "all the damage counts in the total")
	P.record(many, 3, 5, cfg)
	eq(many.spells[3], 15, "a tracked id keeps adding")
	P.record(many, 4, -5, cfg)
	P.record(many, 4, 0, cfg)
	eq(many.total, 205, "zero and negative damage add nothing")
end

-- ---------------------------------------------------------------- who is credited for a hit
do
	eq(P.creditSpell({spellId = 12}, cfg), 12, "a direct hit: the spell")
	eq(P.creditSpell({spellId = 12, summon = "wolf"}, cfg), 12, "a summon in a command's cast: the command")
	eq(P.creditSpell({summon = "Risen Skeleton"}, cfg), 192, "a minion with no cast: the spell that raised it")
	eq(P.creditSpell({summon = "Bone Golem"}, cfg), 186, "the Bone Golem: its spell")
	eq(P.creditSpell({summon = "war wolf"}, cfg), 0, "a companion with no command spell gives no credit")
	eq(P.creditSpell({}, cfg), 0, "an auto attack or weapon hit: bucket 0")
	eq(P.creditSpell({spellId = 0}, cfg), 0, "no spell id: bucket 0")
end

-- ---------------------------------------------------------------- the heal pool
do
	local r = rec(1000, {[10] = 1000})
	local t = 100000
	local heals = P.recordHeal({}, 30, 500, 2000, t - 3000, cfg)
	local sh = P.shares(r, 5000, heals, t, all, cfg)
	near(sh[30], 0.2, 1e-12, "a qualifying heal: 20% of K to the heal")
	near(sh[10], 0.8, 1e-12, "the damage spells keep 80%")
	-- below 1% of the ally's health
	local weak = P.recordHeal({}, 30, 10, 2000, t - 3000, cfg)
	local sh2 = P.shares(r, 5000, weak, t, all, cfg)
	eq(sh2[30], nil, "a heal under 1% of the ally's health does not count")
	near(sh2[10], 1, 1e-12, "no qualifying heal: damage keeps 100%")
	-- outside the 10 s window
	local old = P.recordHeal({}, 30, 500, 2000, t - 11000, cfg)
	eq(P.shares(r, 5000, old, t, all, cfg)[30], nil, "a heal older than 10 s does not count")
	-- split by effective healing
	local two = P.recordHeal(P.recordHeal({}, 30, 300, 2000, t - 2000, cfg), 31, 100, 2000, t - 1000, cfg)
	local sh3 = P.shares(r, 5000, two, t, all, cfg)
	near(sh3[30], 0.15, 1e-12, "the pool splits by effective healing: 3/4")
	near(sh3[31], 0.05, 1e-12, "the pool splits by effective healing: 1/4")
	-- a healer that dealt under 2% still earns the pool; the damage part is lost to it
	local idle = P.newRecord()
	local sh4 = P.shares(idle, 5000, heals, t, all, cfg)
	near(sh4[30], 0.2, 1e-12, "a pure healer earns the pool")
	-- a heal of a spell that is not ranked does not feed the pool
	local sh5 = P.shares(r, 5000, heals, t, function(id) return id ~= 30 end, cfg)
	near(sh5[10], 1, 1e-12, "an unranked heal does not take the pool")
	-- the list is cut to the window at every call
	local list = P.recordHeal(heals, 31, 400, 2000, t + 20000, cfg)
	eq(#list, 1, "old heals leave the list")
	eq(#P.recordHeal({}, 30, 0, 2000, t, cfg), 0, "a heal of nothing is not kept")
end

-- ---------------------------------------------------------------- catch-up, echo
do
	eq(P.catchUp(3, 8, cfg), 2, "more than 4 ranks below the best of its weight: x2")
	eq(P.catchUp(4, 8, cfg), 1, "exactly 4 below: 1")
	eq(P.catchUp(8, 8, cfg), 1, "the best itself: 1")
	eq(P.catchUp(0, 0, cfg), 1, "nothing yet: 1")
	eq(P.echoFloor(0, cfg), 0, "echo: no best rank, no floor")
	eq(P.echoFloor(1, cfg), 0, "echo: best 1 gives 0")
	eq(P.echoFloor(7, cfg), 3, "echo: half of 7, down")
	eq(P.echoFloor(20, cfg), 10, "echo: at most 10")
	eq(P.echoFloor(14, cfg), 7, "echo: half of 14")
	local best, changed = P.echoBest(5, 7)
	ok(best == 7 and changed, "a higher rank is the new best")
	best, changed = P.echoBest(7, 5)
	ok(best == 7 and not changed, "a lower rank leaves the best")
	near(P.withFloor(0, 10, 1, cfg), P.cumCost(10, cfg), 1e-9, "the floor gives the SP of the floor rank")
	near(P.withFloor(30, 10, 1, cfg), 30, 1e-9, "SP above the floor stay")
	near(P.withFloor(0, 5, 0.7, cfg), P.cumCost(5, cfg) * 0.7, 1e-9, "the floor of a heal is x0.7")
end

-- ---------------------------------------------------------------- awarding
do
	near(P.gain(0.01, 0.5, 1, 1, 0, cfg), 0.005, 1e-12, "gain = K x share")
	near(P.gain(0.01, 0.5, 2, 1, 0, cfg), 0.01, 1e-12, "gain with catch-up")
	eq(P.gain(0.01, 0, 1, 1, 0, cfg), 0, "no share, no gain")
	near(P.gain(5, 1, 1, 1, 41.9, cfg), 0.1, 1e-9, "never past the cost of rank 20")
	eq(P.gain(5, 1, 1, 1, 42, cfg), 0, "at the top: nothing")
	-- the design: a main rotation spell at 16% share climbs to rank 20 in about 262 hunting hours
	near(42 / 0.16, 262.5, 0.1, "42 SP at a 16% share: 262 hunting hours")
end

-- ---------------------------------------------------------------- what a rank gives (design 1.5)
do
	near(P.power(20, false, false, cfg), 1.18, 1e-9, "damage +18% at 20")
	near(P.power(10, false, false, cfg), 1.09, 1e-9, "damage +9% at 10")
	near(P.power(20, true, false, cfg), 1.12, 1e-9, "heal +12% at 20 (owner default)")
	eq(P.power(0, false, false, cfg), 1, "rank 0: 1")
	near(P.power(20, false, true, cfg), 1.09, 1e-9, "PvP: half the damage gain")
	near(P.power(20, true, true, cfg), 1.06, 1e-9, "PvP: half the heal gain")
	eq(P.power(99, false, false, cfg), P.power(20, false, false, cfg), "ranks past 20 count as 20")
	eq(P.cooldownMult(3, false, cfg), 1, "cooldown: no cut under rank 4")
	near(P.cooldownMult(4, false, cfg), 0.98, 1e-9, "cooldown: -2% at 4")
	near(P.cooldownMult(12, false, cfg), 0.94, 1e-9, "cooldown: -6% at 12")
	near(P.cooldownMult(20, false, cfg), 0.90, 1e-9, "cooldown: -10% at 20")
	near(P.cooldownMult(20, true, cfg), 0.85, 1e-9, "heal cooldown: -15% at 20")
	near(P.manaMult(20, false, cfg), 0.80, 1e-9, "mana: -20% at 20")
	near(P.manaMult(20, true, cfg), 0.75, 1e-9, "heal mana: -25% at 20")
	near(P.manaMult(10, false, cfg), 0.90, 1e-9, "mana: -10% at 10")
	eq(P.cooldown(10000, 20, false, cfg), 9000, "cooldown 10 s at rank 20: 9 s")
	eq(P.cooldown(10000, 0, false, cfg), 10000, "cooldown at rank 0: unchanged")
	eq(P.cooldown(1050, 20, false, cfg), 1000, "the 1 s floor")
	eq(P.cooldown(800, 20, false, cfg), 800, "a cooldown shorter than the floor is kept")
	eq(P.mana(1000, 20, false, cfg), 800, "mana 1000 at rank 20: 800")
	eq(P.mana(0, 20, false, cfg), 0, "no mana: none")
end

-- ---------------------------------------------------------------- packed state
do
	local v = P.pack(17, 2, 1, true)
	local r, f1, f2, aw = P.unpack(v)
	ok(r == 17 and f1 == 2 and f2 == 1 and aw == true, "pack / unpack round trip")
	r, f1, f2, aw = P.unpack(P.pack(20, 3, 3, false))
	ok(r == 20 and f1 == 3 and f2 == 3 and aw == false, "all the bits")
	r, f1, f2, aw = P.unpack(0)
	ok(r == 0 and f1 == 0 and f2 == 0 and aw == false, "zero")
	r = P.unpack(-1)
	eq(r, 0, "a missing storage (-1) reads as rank 0")
	eq(P.pack(20, 3, 3, true), 20 + 96 + 384 + 512, "the most it holds")
	ok(P.pack(20, 3, 3, true) < 1024, "fits ten bits")
end

-- ---------------------------------------------------------------- retire, class change, reset
do
	local c2 = {reassigned = {[77] = 3}, storage = cfg.storage}
	ok(P.reassignedClears(77, 2, c2), "a stored version below the id's version clears it")
	ok(not P.reassignedClears(77, 3, c2), "the same version keeps it")
	ok(not P.reassignedClears(78, 0, c2), "an id that was never reassigned stays")
	local dormant = P.dormant({[10] = 5, [11] = 0, [12] = 9}, {[10] = true})
	eq(#dormant, 1, "a ranked spell the class does not know is dormant")
	eq(dormant[1], 12, "the dormant spell id")
	local a, b = P.resetRange(cfg)
	eq(a, 7107000, "reset range from")
	eq(b, 7108099, "reset range to")
end

-- ---------------------------------------------------------------- monster health (design 5.3)
do
	eq(P.healthFactor(1, cfg), 1, "level 1: x1")
	eq(P.healthFactor(99, cfg), 1, "below 100: x1")
	near(P.healthFactor(100, cfg), 1.02, 1e-9, "level 100: 1.02")
	near(P.healthFactor(150, cfg), 1.025, 1e-9, "level 150: between points")
	near(P.healthFactor(1000, cfg), 1.22, 1e-9, "level 1000: 1.22 (1.21 until the combo riders of phase 6b)")
	near(P.healthFactor(2500, cfg), 1.39, 1e-9, "level 2500: 1.39")
	near(P.healthFactor(3000, cfg), 1.39, 1e-9, "above the last: flat")
	for i = 2, #cfg.health do
		ok(cfg.health[i][1] > cfg.health[i - 1][1] and cfg.health[i][2] >= cfg.health[i - 1][2], "health curve rises: " .. i)
	end
end

-- ---------------------------------------------------------------- the read API of the lib (off by default)
do
	ChaosSpellRanksCore, ChaosSpellRanksConfig = P, cfg
	ORIGIN_SPELL, COMBAT_HEALING, COMBAT_NONE = 3, 9, 0
	dofile("data/lib/chaos_spell_ranks.lua")
	local R = ChaosSpellRanks
	local store = {[7107000 + 40] = P.pack(20, 0, 0, false)}
	local function mkPlayer(ctx)
		local pl = {}
		function pl:getId() return 1 end
		function pl:isPlayer() return true end
		function pl:getStorageValue(k) return store[k] or -1 end
		return pl
	end
	local pl = mkPlayer()
	eq(R.rankOf(pl, 40), 20, "the rank is read from the packed storage")
	eq(R.rankOf(pl, 41), 0, "a spell with no storage: rank 0")
	eq(R.rankOf(pl, 9999), 0, "an id outside the block: rank 0")
	eq(R.factor(pl, 40, false, false), 1, "switched off: factor 1")
	eq(R.healthFactor(2500), 1, "switched off: health x1")
	eq(R.manaFor(pl, 40, 100), 100, "switched off: mana unchanged")
	eq(R.cooldownFor(pl, 40, 8000), 8000, "switched off: cooldown unchanged")
	-- a cast context: ChaosSupportsSpell.cast() names the spell
	ChaosSupportsSpell = {cast = function() return 1, 40 end}
	eq(R.hitFactor(pl, {}, ORIGIN_SPELL, 5), 1, "switched off: a hit is x1")
	cfg.enabled = true
	near(R.factor(pl, 40, false, false), 1.18, 1e-9, "on: rank 20 is +18%")
	near(R.factor(pl, 40, false, true), 1.09, 1e-9, "on: PvP half")
	eq(R.factor(pl, 41, false, false), 1, "on: rank 0 is x1")
	near(R.hitFactor(pl, {}, ORIGIN_SPELL, 5), 1.18, 1e-9, "on: a spell hit in a cast")
	eq(R.hitFactor(pl, {}, 1, 5), 1, "on: a weapon hit is x1")
	eq(R.hitFactor(pl, {}, ORIGIN_SPELL, 0), 1, "on: no combat type is x1")
	local other = {isPlayer = function() return true end}
	near(R.hitFactor(pl, other, ORIGIN_SPELL, 5), 1.09, 1e-9, "on: a hit on another player is the PvP half")
	R.healIds[40] = true
	near(R.hitFactor(pl, {}, ORIGIN_SPELL, COMBAT_HEALING), 1.12, 1e-9, "on: a heal is +12% at 20")
	near(R.hitFactor(pl, other, ORIGIN_SPELL, COMBAT_HEALING), 1.12, 1e-9, "on: a heal on another player is no PvP: the whole +12%")
	eq(R.manaFor(pl, 40, 100), 75, "on: heal mana -25%")
	eq(R.cooldownFor(pl, 40, 8000), 6800, "on: heal cooldown -15%")
	near(R.healthFactor(2500), 1.39, 1e-9, "on: health x1.39 at 2500")
	ChaosSupportsSpell = {cast = function() return 2, 40 end}
	eq(R.hitFactor(pl, {}, ORIGIN_SPELL, 5), 1, "another player's cast context is not ours")
	cfg.enabled = false
end

-- ---------------------------------------------------------------- the opcode, the storage block and the table
do
	local function read(path)
		local f = io.open(path, "r")
		if not f then
			return ""
		end
		local s = f:read("*a")
		f:close()
		return s
	end
	local constants = read("data/scripts/chaos/chaos_constants.lua")
	ok(constants:find("ChaosOpcodes.spellRanks = 168", 1, true), "chaos_constants.lua names opcode 168")
	ok(constants:find("Chaos.storage.spellRanks = 7107000", 1, true), "chaos_constants.lua names the storage block")
	ok(constants:find('Chaos.tables.spellRanks = "chaos_spell_ranks"', 1, true), "chaos_constants.lua names the table")
	-- no other script or file of the server names 168 as an opcode
	local opcodes = {}
	for n in constants:gmatch("ChaosOpcodes%.[%w_]+%s*=%s*(%d+)") do
		opcodes[#opcodes + 1] = n
	end
	local seen = {}
	for _, n in ipairs(opcodes) do
		ok(not seen[n] or n == "168" and false, "opcode " .. n .. " used twice")
		seen[n] = true
	end
	eq(#(function() local t = {} for n in constants:gmatch("ChaosOpcodes%.[%w_]+%s*=%s*168%f[%D]") do t[#t + 1] = n end return t end)(), 1,
		"168 is named once in the constants")
	-- not an opcode of the reference server or of the reference client
	for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 126, 127, 144, 145, 146, 210, 212, 213, 230, 246, 140}) do
		ok(v ~= 168, "168 is not the reference opcode " .. v)
	end
	-- no client module and no other script names 168 as an opcode; no script other than ours and the constants names a key of the block
	local used = {}
	local ls = io.popen("ls ../client/overlay/modules 2>/dev/null")
	for dir in ls:lines() do
		local ph = io.popen("ls ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
		for file in ph:lines() do
			local s = read(file)
			if not file:find("_test.lua", 1, true) and (s:find("[Oo]pcode[%w_]*%s*=%s*168%f[%D]") or s:find("xtended[%w]*Opcode%(%s*168%f[%D]")) then
				used[#used + 1] = file
			end
		end
		ph:close()
	end
	ls:close()
	local ps = io.popen("ls data/scripts/chaos/*.lua data/lib/*.lua")
	for file in ps:lines() do
		local s = read(file)
		if not file:find("chaos_constants.lua", 1, true) and not file:find("spell_ranks", 1, true) and (s:find("[Oo]pcode[%w_]*%s*=%s*168%f[%D]") or s:find("sendExtendedOpcode%(%s*168%f[%D]")) then
			used[#used + 1] = file
		end
		if not file:find("spell_ranks", 1, true) and not file:find("chaos_constants.lua", 1, true) and not file:find("pinnacle", 1, true)
				and (s:find("%f[%d]710[78]%d%d%d%f[%D]")) then
			used[#used + 1] = file .. " (storage block)"
		end
	end
	ps:close()
	eq(#used, 0, "168 and the block 7107000 - 7108099 are free: " .. table.concat(used, ", "))
	-- the storage block is inside the Chaos range and holds the keys of the design
	local s = cfg.storage
	ok(s.base >= 7100000 and s.last <= 7127999, "the block is inside 7100000 - 7127999")
	eq(s.base, 7107000, "block start")
	eq(s.last, 7108099, "block end")
	ok(s.rankBase + s.maxSpellId < s.version, "the packed ranks end before the version key")
	ok(s.spBase + s.maxSpellId <= s.last, "the SP keys end inside the block")
	ok(s.spBase > s.awakenedSlots + 9, "the SP keys start after the awakened slots")
	ok(s.maxSpellId < 500, "spell ids below 500")
	ok(cfg.spUnit * 42 < 2 ^ 31, "the SP of a full climb fit a 32 bit storage")
	-- no other config or script names a key of the block
	local sql = read("sql/chaos_spell_ranks.sql")
	ok(sql:find("CREATE TABLE IF NOT EXISTS `chaos_spell_ranks`", 1, true), "the SQL file creates the table")
	ok(sql:find("PRIMARY KEY (`account_id`, `spell_id`)", 1, true), "the primary key is account and spell")
	local wipe = read("deploy/launch_wipe_tables.json")
	ok(wipe:find('"chaos_spell_ranks"', 1, true), "the wipe policy lists the table")
	ok(read("data/scripts/chaos/spell_ranks.lua"):find("ChaosOpcodes.spellRanks", 1, true), "spell_ranks.lua reads the opcode constant")
	-- the hooks the glue hangs on exist where the design puts them
	local cl = read("data/scripts/chaos/combatlog.lua")
	ok(cl:find("CL.spellHook", 1, true) and cl:find("sph, owner, summon, creature, amount, castIdOf", 1, true), "combatlog.lua calls the damage hook with the spell id")
	ok(cl:find("CL.healSpellHook", 1, true), "combatlog.lua calls the heal hook")
	local pt = read("data/scripts/chaos/passivetree_effects.lua")
	ok(pt:find('rawget(_G, "ChaosSpellRanks")', 1, true) and pt:find("ranks.hitFactor(attacker, creature, origin, primaryType)", 1, true),
		"ChaosPassiveDealt asks the rank factor (1 while off)")
end

print(string.format("spell_ranks_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
