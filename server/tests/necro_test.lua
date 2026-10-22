-- Run from the server/ folder: luajit tests/necro_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the Necromancer line's pure logic (data/scripts/chaos/necro_core.lua + necro_config.lua): classes and the
-- ascension words, minion caps by class and level, minion health and hits scaling with level and magic level, Banner
-- of Bones, the Bone Lord splash, Raise Dead plans, corpse rules and choice, the leash, minion and Soul Rot target
-- choice, the sacrifice choice, spell values and the level scale, Soul Hoard, curse math, Life Siphon, Bone Offering,
-- the protection-zone rest and the caps after a vocation change; and that the ids, spells and monsters line up with
-- the rest of the server data.
local cfg = dofile("data/scripts/chaos/necro_config.lua")
dofile("data/scripts/chaos/necro_core.lua")
local N = ChaosNecroCore

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
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local t = f:read("*a")
	f:close()
	return t
end

local NECRO, LICH, BONE = cfg.ids.necromancer, cfg.ids.lich, cfg.ids.bonelord

-- ------------------------------------------------------------------ classes
eq(N.classOf(cfg, NECRO), "necromancer", "necromancer id")
eq(N.classOf(cfg, LICH), "lich", "lich id")
eq(N.classOf(cfg, BONE), "bonelord", "bone lord id")
eq(N.classOf(cfg, 11), nil, "thief is not of the line")
eq(N.isLine(cfg, 4), false, "warrior is not of the line")
eq(N.ascensionId(cfg, "lich"), LICH, "!ascend lich")
eq(N.ascensionId(cfg, " Bone Lord "), BONE, "!ascend bone lord (spaces, case)")
eq(N.ascensionId(cfg, "bone_lord"), BONE, "!ascend bone_lord")
eq(N.ascensionId(cfg, "ninja"), nil, "not a necromancer ascension")

-- ------------------------------------------------------------------ caps
eq(N.raiseKind(cfg, "necromancer"), "skeleton", "the necromancer raises skeletons")
eq(N.raiseKind(cfg, "lich"), "shade", "the lich raises shades")
eq(N.raiseKind(cfg, "bonelord"), "skeleton", "the bone lord raises skeletons")
eq(N.raiseKind(cfg, nil), nil, "no class, no minion")
eq(N.minionCap(cfg, "necromancer", "skeleton", 8), 1, "necromancer level 8: 1")
eq(N.minionCap(cfg, "necromancer", "skeleton", 40), 2, "necromancer level 40: 2")
eq(N.minionCap(cfg, "necromancer", "skeleton", 199), 3, "necromancer level 199: 3")
eq(N.minionCap(cfg, "necromancer", "skeleton", 300), 4, "necromancer level 300: 4")
eq(N.minionCap(cfg, "lich", "shade", 1000), 1, "the lich keeps one shade")
eq(N.minionCap(cfg, "lich", "skeleton", 1000), 0, "the lich raises no skeletons")
eq(N.minionCap(cfg, "bonelord", "skeleton", 100), 5, "bone lord level 100: 5")
eq(N.minionCap(cfg, "bonelord", "skeleton", 1000), 6, "bone lord level 1000: 6")
eq(N.minionCap(cfg, "bonelord", "golem", 100), 1, "bone lord: one golem")
eq(N.minionCap(cfg, "necromancer", "golem", 1000), 0, "only the bone lord has a golem")
eq(N.minionCap(cfg, "lich", "golem", 1000), 0, "the lich has no golem")
ok(N.minionCap(cfg, "bonelord", "skeleton", 300) > N.minionCap(cfg, "necromancer", "skeleton", 300),
	"the bone lord's army is the largest")

-- ------------------------------------------------------------------ scaling
local h300 = N.minionHealth(cfg, "necromancer", "skeleton", 300, 100)
local h1000 = N.minionHealth(cfg, "necromancer", "skeleton", 1000, 140)
eq(h300, math.floor(200 + 300 * 9 + 100 * 6), "skeleton health at 300 / ml 100")
ok(h1000 > 2.5 * h300, "health grows with level")
ok(N.minionHealth(cfg, "necromancer", "skeleton", 300, 120) > h300, "health grows with magic level")
ok(N.minionHealth(cfg, "lich", "shade", 300, 100) > 2 * h300, "the lich's shade is much tougher")
ok(N.minionHealth(cfg, "bonelord", "golem", 300, 100) > 3 * h300, "the golem is the toughest")
local a, b = N.minionHit(cfg, "necromancer", "skeleton", 300, 100, false)
local avg = 300 * 0.24 + 100 * 0.5
eq(a, math.floor(avg * 0.8), "skeleton hit min")
eq(b, math.floor(avg * 1.2), "skeleton hit max")
local a2, b2 = N.minionHit(cfg, "necromancer", "skeleton", 300, 100, true)
eq(b2, math.floor(avg * 1.3 * 1.2), "Banner of Bones +30%")
local la, lb = N.minionHit(cfg, "lich", "shade", 300, 100, false)
ok(lb > 2 * b, "a shade hits harder than two skeletons")
local ba, bb = N.minionHit(cfg, "bonelord", "skeleton", 300, 100, false)
ok(bb < b, "a bone lord skeleton hits a little softer (it splashes)")
local ga, gb = N.minionHit(cfg, "bonelord", "golem", 300, 100, false)
ok(gb > bb, "the golem hits harder than a skeleton")
local ma, mb = N.minionHit(cfg, "necromancer", "skeleton", 1000, 140, false)
ok(mb > 2.3 * b, "hits grow with level")
eq(N.splashShare(cfg, "bonelord", "skeleton"), cfg.minions.classes.bonelord.splash, "bone lord splash")
eq(N.splashShare(cfg, "necromancer", "skeleton"), 0, "no splash for the necromancer")
eq(N.splashShare(cfg, "bonelord", "golem"), 0, "the golem slams instead")
eq(N.minionDamageTaken(cfg, -1000, true), -750, "aura: -25% damage taken")
eq(N.minionDamageTaken(cfg, -1000, false), -1000, "no aura")

-- ------------------------------------------------------------------ the total cap (all kinds together)
eq(N.totalCap(cfg, "necromancer", 1), 3, "necromancer: 3 minions in all at level 1")
eq(N.totalCap(cfg, "necromancer", 1000), 3, "necromancer: still 3 at level 1000")
eq(N.totalCap(cfg, "necromancer", 1000, 1), 4, "necromancer: Legion adds to the total")
eq(N.totalCap(cfg, "lich", 1000), 1, "lich: its one minion, as before")
eq(N.totalCap(cfg, "bonelord", 100), 6, "bone lord level 100: 5 skeletons + the golem")
eq(N.totalCap(cfg, "bonelord", 400), 7, "bone lord level 400: 6 skeletons + the golem")
eq(N.totalCap(cfg, nil, 100), 0, "no class, no minions")
for _, kind in ipairs({"skeleton", "shade", "golem"}) do
	for _, class in ipairs({"necromancer", "lich", "bonelord"}) do
		-- the old per-kind caps are still the caps of Raise Dead and the golem
		ok(N.minionCap(cfg, class, kind, 1000) <= (kind == "skeleton" and 6 or 1), class .. " " .. kind .. ": cap unchanged")
	end
end
eq(N.minionCap(cfg, "necromancer", "skeleton", 300), 4, "Raise Dead's own cap stays")
for _, kind in ipairs({"warrior", "archer", "mage"}) do
	eq(N.minionCap(cfg, "necromancer", kind, 50), 3, "necromancer " .. kind .. ": limited only by the total")
	eq(N.minionCap(cfg, "lich", kind, 50), 1, "lich " .. kind .. ": the total of 1")
	eq(N.minionCap(cfg, "bonelord", kind, 50), 6, "bone lord " .. kind .. ": the total of 6")
	eq(N.minionCap(cfg, nil, kind, 50), 0, kind .. ": no class, none")
end
-- room for a new minion: the OLDEST ones go first
local function kinds(...) local t = {} for i, k in ipairs({...}) do t[i] = {kind = k} end return t end
local room = N.makeRoom(cfg, "necromancer", 30, kinds())
eq(#room, 0, "no minions: nothing dismissed")
room = N.makeRoom(cfg, "necromancer", 30, kinds("skeleton", "warrior"))
eq(#room, 0, "two of three: nothing dismissed")
room = N.makeRoom(cfg, "necromancer", 30, kinds("skeleton", "warrior", "archer"))
eq(#room, 1, "three of three: one goes"); eq(room[1], 1, "the oldest (the first)")
room = N.makeRoom(cfg, "necromancer", 300, kinds("mage", "skeleton", "archer"))
eq(room[1], 1, "the oldest whatever its kind (a mage here)")
room = N.makeRoom(cfg, "necromancer", 30, kinds("skeleton", "warrior", "archer", "mage"))
eq(#room, 2, "four out (the cap was lowered): two go"); eq(room[1], 1, "oldest first"); eq(room[2], 2, "then the next")
room = N.makeRoom(cfg, "lich", 300, kinds("shade"))
eq(#room, 1, "the lich's shade makes room for a warrior"); eq(room[1], 1, "the shade")
eq(#N.makeRoom(cfg, "lich", 300, kinds()), 0, "the lich with none: room")
room = N.makeRoom(cfg, "bonelord", 100, kinds("skeleton", "skeleton", "skeleton", "skeleton", "skeleton", "golem"))
eq(#room, 1, "bone lord with 5 skeletons and the golem: one goes"); eq(room[1], 1, "the oldest skeleton")
eq(N.makeRoom(cfg, nil, 100, kinds()), nil, "no class: no room")
-- three, then a fourth, a fifth: the first dies, then the second (simulate the owner's list)
local army = kinds("skeleton", "warrior", "archer")
for step = 1, 2 do
	local drop = N.makeRoom(cfg, "necromancer", 50, army)
	for j = #drop, 1, -1 do table.remove(army, drop[j]) end
	army[#army + 1] = {kind = "mage"}
	eq(#army, 3, "step " .. step .. ": still 3")
end
eq(army[1].kind, "archer", "the skeleton and the warrior are gone, the archer is the oldest left")
-- over the caps after a level or vocation change: the per-kind cap first, then the total (newest first)
local over2 = N.overCap(cfg, "necromancer", 50, kinds("skeleton", "warrior", "archer", "mage"))
eq(#over2, 1, "four minions of a total of 3: one too many"); eq(over2[1], 4, "the newest")
eq(#N.overCap(cfg, "necromancer", 50, kinds("warrior", "archer", "mage")), 0, "three: within the total")
eq(#N.overCap(cfg, "lich", 50, kinds("warrior")), 0, "the lich may have a warrior")
eq(#N.overCap(cfg, "lich", 50, kinds("warrior", "mage")), 1, "the lich: only one in all")
eq(#N.restFilter(cfg, "necromancer", 50, kinds("warrior", "archer", "mage", "mage")), 3, "rest: at most the total")
eq(#N.restFilter(cfg, "lich", 50, kinds("shade", "warrior")), 1, "rest: the lich keeps one")

-- ------------------------------------------------------------------ the summon kinds' numbers
eq(N.kindOf(cfg, "Risen Warrior"), "warrior", "kind of Risen Warrior")
eq(N.kindOf(cfg, "risen archer"), "archer", "kind of Risen Archer")
eq(N.kindOf(cfg, "Risen Mage"), "mage", "kind of Risen Mage")
local m = cfg.minions
eq(m.warrior.range, 1, "warrior: melee"); eq(m.archer.range, 5, "archer: range 5"); eq(m.mage.range, 4, "mage: range 4")
eq(m.warrior.combat, "physical", "warrior: physical"); eq(m.archer.combat, "physical", "archer: physical (arrows)")
ok(m.mage.combat == "death" or m.mage.combat == "energy", "mage: death or energy")
for _, kind in ipairs({"warrior", "archer", "mage"}) do
	ok(m[kind].summon, kind .. ": a summon-spell kind")
	ok(m[kind].intervalMs >= 1000, kind .. ": a hit interval")
end
local hw = N.minionHealth(cfg, "necromancer", "warrior", 100, 50)
local hs = N.minionHealth(cfg, "necromancer", "skeleton", 100, 50)
local ha = N.minionHealth(cfg, "necromancer", "archer", 100, 50)
local hm = N.minionHealth(cfg, "necromancer", "mage", 100, 50)
ok(hw > hs, "the warrior is sturdier than a skeleton (" .. hw .. " vs " .. hs .. ")")
ok(ha < hs and hm < hs, "the archer and the mage are fragile (" .. ha .. ", " .. hm .. " vs " .. hs .. ")")
eq(hw, math.floor((200 + 100 * 9 + 50 * 6) * 1.0 * m.warrior.mult.health), "warrior health = formula x mult")
local aMin, aMax = N.minionHit(cfg, "necromancer", "archer", 100, 50)
local sMin, sMax = N.minionHit(cfg, "necromancer", "skeleton", 100, 50)
ok(aMax > sMax, "the archer hits harder than the skeleton")
local wMin, wMax = N.minionHit(cfg, "necromancer", "warrior", 100, 50)
eq(wMax, sMax, "the warrior hits like a skeleton")
ok(N.minionHealth(cfg, "lich", "warrior", 100, 50) > hw, "the lich's single minion is stronger (class factor)")
ok(N.minionHealth(cfg, "bonelord", "warrior", 100, 50) ~= hw, "the class factors apply to the new kinds")
eq(N.splashShare(cfg, "bonelord", "archer"), 0, "only skeletons splash")

-- ------------------------------------------------------------------ Raise Dead
local plan = N.raisePlan(cfg, "necromancer", 300, 0, 5)
eq(plan.raise, 2, "two per cast from corpses"); eq(plan.fromNothing, false, "from corpses"); eq(plan.extraMana, 0, "no extra")
plan = N.raisePlan(cfg, "necromancer", 300, 3, 5)
eq(plan.raise, 1, "only the free slot")
plan = N.raisePlan(cfg, "bonelord", 300, 0, 2)
eq(plan.raise, 2, "only as many as corpses")
plan = N.raisePlan(cfg, "necromancer", 300, 0, 0)
eq(plan.fromNothing, true, "no corpse: from nothing"); eq(plan.raise, 1, "one from nothing")
eq(plan.extraMana, cfg.raiseDead.mana, "from nothing costs twice the mana")
local none, why = N.raisePlan(cfg, "necromancer", 300, 4, 3)
eq(none, nil, "a full army raises nothing"); ok(why:find("complete") ~= nil, "says why")
eq(N.raisePlan(cfg, nil, 300, 0, 3), nil, "no class")
plan = N.raisePlan(cfg, "lich", 300, 0, 3)
eq(plan.raise, 1, "the lich raises one shade")

-- ------------------------------------------------------------------ corpses
local me = {[7] = true, [8] = true}
eq(N.corpseUsable({isCorpse = true, items = 0, owner = 0}, me), true, "empty unowned corpse")
eq(N.corpseUsable({isCorpse = true, items = 0, owner = 7}, me), true, "own corpse")
eq(N.corpseUsable({isCorpse = true, items = 0, owner = 9}, me), false, "someone else's corpse")
eq(N.corpseUsable({isCorpse = true, items = 2, owner = 0}, me), false, "never a corpse with loot")
eq(N.corpseUsable({isCorpse = true, items = 0, playerCorpse = true}, me), false, "never a player corpse")
eq(N.corpseUsable({isCorpse = false}, me), false, "not a corpse")
local picked = N.pickCorpses({
	{isCorpse = true, items = 0, owner = 0, dist = 3, order = 1},
	{isCorpse = true, items = 1, owner = 0, dist = 0, order = 2},
	{isCorpse = true, items = 0, owner = 7, dist = 1, order = 3},
	{isCorpse = true, items = 0, owner = 0, dist = 1, order = 4},
	{isCorpse = true, items = 0, owner = 0, dist = 2, order = 5},
}, me, 3)
eq(#picked, 3, "at most 3")
eq(picked[1].order, 3, "nearest first, ties by order"); eq(picked[2].order, 4, "then the other at 1")
eq(picked[3].order, 5, "the looted one is skipped")

-- ------------------------------------------------------------------ positions and targets
local P = function(x, y, z) return {x = x, y = y, z = z or 7} end
eq(N.distance(P(0, 0), P(3, -2)), 3, "chebyshev")
eq(N.distance(P(0, 0, 7), P(0, 0, 8)), math.huge, "other floor")
eq(N.leash(cfg, P(0, 0), P(7, 7)), "stay", "within the leash")
eq(N.leash(cfg, P(0, 0), P(8, 0)), "teleport", "too far")
eq(N.leash(cfg, P(0, 0, 6), P(0, 0, 7)), "teleport", "another floor")
local ownerT = {id = 1, pos = P(5, 5), alive = true}
local ownT = {id = 2, pos = P(1, 1), alive = true}
eq(N.minionTarget(P(4, 4), 1, ownerT, ownT), ownerT, "the owner's target first")
eq(N.minionTarget(P(1, 2), 1, ownerT, ownT), ownT, "else its own when in reach")
eq(N.minionTarget(P(9, 9), 1, ownerT, ownT), nil, "nothing in reach")
eq(N.minionTarget(P(3, 3), 4, ownerT, nil), ownerT, "a shade reaches 4 sqm")
eq(N.minionTarget(P(4, 4), 1, {id = 1, pos = P(5, 5), alive = false}, nil), nil, "never a dead target")
local sac = N.pickSacrifice({
	{kind = "golem", pos = P(5, 6), id = 1},
	{kind = "skeleton", pos = P(9, 9), id = 2},
	{kind = "skeleton", pos = P(6, 6), id = 3},
}, P(5, 5))
eq(sac.id, 3, "the skeleton nearest to the target, never the golem")
eq(N.pickSacrifice({{kind = "golem", pos = P(5, 6), id = 1}}, P(5, 5)), nil, "no skeleton, no offering")
local jump = N.rotJump({{id = 4, pos = P(3, 0), alive = true}, {id = 5, pos = P(1, 1), alive = true},
	{id = 6, pos = P(0, 1), alive = false}}, P(0, 0), 3)
eq(jump.id, 5, "the rot jumps to the nearest living enemy")
eq(N.rotJump({{id = 4, pos = P(4, 0), alive = true}}, P(0, 0), 3), nil, "out of reach")

-- ------------------------------------------------------------------ spells
-- the level scale stood in for the passive tree: dropped with the class trees (1 everywhere), still honoured when set
eq(N.levelScale(cfg, 300), 1, "no level scale"); eq(N.levelScale(cfg, 1000), 1, "no level scale at 1000")
local withScale = {levelScale = {from = 300, per = 700, max = 2.2}}
eq(N.levelScale(withScale, 1000), 2, "a configured scale still works"); eq(N.levelScale(withScale, 5000), 2.2, "capped")
local sa, sb = N.values(cfg, cfg.boneSpear, 300, 100)
eq(sa, math.floor(60 + 100 * 1.6 + 20), "bone spear min at 300")
eq(sb, math.floor(60 + 100 * 2.6 + 40), "bone spear max at 300")
local ha, hb = N.values(cfg, cfg.boneSpear, 300, 100, 1.25)
eq(hb, math.floor((60 + 100 * 2.6 + 40) * 1.25), "extra factor")
eq(N.soulHoard(cfg, "lich", 1, 0), 1 + cfg.soulHoard.perFreeSlot, "Soul Hoard: no shade out")
eq(N.soulHoard(cfg, "lich", 1, 1), 1, "Soul Hoard: shade out")
eq(N.soulHoard(cfg, "bonelord", 6, 0), 1, "Soul Hoard is the lich's")
eq(N.curseAmplify(cfg, "lich"), 0.25, "lich curse"); eq(N.curseAmplify(cfg, "necromancer"), 0.15, "base curse")
local ca, cb = N.curseTick(cfg, "necromancer", 300, 100)
local lca, lcb = N.curseTick(cfg, "lich", 300, 100)
ok(lcb > cb, "the lich's rot ticks harder")
eq(N.cursedDamage(-1000, 0.25, false), -1250, "cursed monster takes +25%")
eq(N.cursedDamage(-1000, 0.25, true), -1000, "players are never amplified")
eq(N.cursedDamage(0, 0.25, false), 0, "no damage")
eq(N.activeAmplify(cfg, true, true), 0.25, "the stronger curse wins")
eq(N.activeAmplify(cfg, true, false), 0.15, "base curse")
eq(N.activeAmplify(cfg, false, false), 0, "no curse")
eq(N.siphonHeal(cfg, 1001), 500, "siphon heals half")
eq(N.siphonHeal(cfg, -5), 0, "never negative")
local oa, ob = N.offeringValues(cfg, 300, 100, 4000)
local fa, fb = N.values(cfg, cfg.boneOffering.hit, 300, 100)
eq(oa, fa + 600, "offering adds 15% of the skeleton's health")
eq(N.shielded(cfg, -1000, true), -800, "bone shield -20%")
eq(N.shielded(cfg, -1000, false), -1000, "no shield")

-- ------------------------------------------------------------------ rest and caps
local rest = {}
N.restPut(rest, 7, 1000, {{kind = "skeleton", ratio = 0.5}, {kind = "skeleton", ratio = 1}})
N.restPut(rest, 7, 1010, {{kind = "golem", ratio = 0.9}})
local back = N.restTake(cfg, rest, 7, 1020)
eq(#back, 3, "all rested minions come back"); eq(rest[7], nil, "and the rest is forgotten")
N.restPut(rest, 7, 1000, {{kind = "skeleton", ratio = 1}})
eq(N.restTake(cfg, rest, 7, 1000 + cfg.minions.restKeepSeconds + 1), nil, "a rest too old is lost")
N.restPut(rest, 7, 1000, {})
eq(rest[7], nil, "nothing to rest")
local kept = N.restFilter(cfg, "lich", 300, {{kind = "skeleton", ratio = 1}, {kind = "shade", ratio = 1},
	{kind = "shade", ratio = 1}})
eq(#kept, 1, "after becoming a lich: one shade, no skeletons"); eq(kept[1].kind, "shade", "the shade")
local over = N.overCap(cfg, "necromancer", 50, {{kind = "skeleton"}, {kind = "skeleton"}, {kind = "skeleton"},
	{kind = "golem"}})
eq(#over, 2, "level 50 necromancer: one skeleton and the golem too many")
eq(over[1], 4, "newest first"); eq(over[2], 3, "then the third skeleton")
eq(#N.overCap(cfg, "bonelord", 300, {{kind = "skeleton"}, {kind = "golem"}}), 0, "within the caps")
eq(N.kindOf(cfg, "risen skeleton"), "skeleton", "kind of a monster name")
eq(N.kindOf(cfg, "Bone Golem"), "golem", "golem")
eq(N.kindOf(cfg, "Skeleton"), nil, "a wild skeleton is no minion")

-- ------------------------------------------------------------------ the data lines up
local seen = {}
for key, id in pairs(cfg.spellIds) do
	ok(id > 0 and id < 256, "spell id " .. key .. " below 256 (one byte in the cooldown packet)")
	ok(not seen[id], "spell id " .. id .. " unique")
	seen[id] = true
end
local xml = readFile("data/spells/chaos/spells_chaos.xml") or ""
for name, id in pairs(cfg.spellIds) do
	for line in xml:gmatch('<instant[^>]-spellid="' .. id .. '"[^>]*>') do
		-- once the spells are integrated, the id must be one of ours (a Necromancer spell script)
		ok(line:find('script="chaos/necromancer/') or line:find('script="chaos/lich/')
			or line:find('script="chaos/bonelord/'), "spell id " .. id .. " (" .. name .. ") is used by another spell")
	end
end
local raiseLine = xml:match('<instant[^>]-spellid="' .. cfg.spellIds.raiseDead .. '"[^>]*>')
if raiseLine then
	eq(tonumber(raiseLine:match('mana="(%d+)"')), cfg.raiseDead.mana, "Raise Dead mana in spells_chaos.xml = raiseDead.mana")
end
-- the store lock (class_unlocks_core.lua, another module) locks exactly the line's vocations
if readFile("data/scripts/chaos/class_unlocks_core.lua") then
	local okLoad = pcall(dofile, "data/scripts/chaos/class_unlocks_core.lua")
	local lock = okLoad and ChaosClassUnlocksCore and ChaosClassUnlocksCore.config
		and ChaosClassUnlocksCore.config.classes and ChaosClassUnlocksCore.config.classes[cfg.unlockKey]
	if lock then
		local want = {}
		for _, id in pairs(cfg.ids) do
			want[id] = true
		end
		eq(#lock.vocations, 3, "the lock names three vocations")
		for _, id in ipairs(lock.vocations) do
			ok(want[id], "locked vocation " .. id .. " is one of the line's")
		end
	end
end
local vocs = readFile("data/XML/chaos_vocations.xml") or ""
for key, id in pairs(cfg.ids) do
	ok(not vocs:find('<vocation id="' .. id .. '"', 1, true) or vocs:find('name="Necromancer"', 1, true),
		"vocation id " .. id .. " (" .. key .. ") is free in chaos_vocations.xml")
end
local frag = readFile("data/XML/chaos_vocations_necro.xml") or ""
for key, id in pairs(cfg.ids) do
	ok(frag:find('<vocation id="' .. id .. '" clientid="' .. cfg.clientIds[key] .. '"', 1, true) ~= nil,
		"fragment has " .. key .. " with id " .. id .. " and client byte " .. cfg.clientIds[key])
end
for _, f in ipairs({"necromancer/raise_dead", "necromancer/bone_spear", "necromancer/withering_curse",
		"lich/soul_rot", "lich/life_siphon", "lich/corpse_explosion",
		"bonelord/bone_golem", "bonelord/banner_of_bones", "bonelord/bone_offering"}) do
	ok(readFile("data/spells/chaos/" .. f .. ".lua") ~= nil, "spell script " .. f)
end
-- the three summon spells: ids, words, levels, mana, cooldown, classes, scripts line up with spells_chaos.xml
local allIds, allWords = {}, {}
for a in xml:gmatch("<instant ([^>]*)>") do
	local id, w = a:match('spellid="(%d+)"'), a:match('words="([^"]+)"')
	allIds[id] = (allIds[id] or 0) + 1
	allWords[w] = (allWords[w] or 0) + 1
end
local stock = readFile("data/spells/stock_spells.csv") or ""
local prev
for _, kind in ipairs({"warrior", "archer", "mage"}) do
	local sp = cfg.summonSpells[kind]
	local id = cfg.spellIds[sp.spell]
	ok(id and id < 256, kind .. ": spell id below 256")
	local e = xml:match('<instant [^>]*spellid="' .. tostring(id) .. '"[^>]*>.-</instant>') or ""
	eq(e:match('name="([^"]+)"'), sp.name, kind .. ": name")
	eq(e:match('words="([^"]+)"'), sp.words, kind .. ": words")
	eq(tonumber(e:match('level="(%d+)"')), sp.level, kind .. ": level")
	eq(tonumber(e:match('mana="(%d+)"')), sp.mana, kind .. ": mana")
	eq(tonumber(e:match('cooldown="(%d+)"')), sp.cooldownMs, kind .. ": cooldown")
	eq(e:match('group="(%a+)"'), "support", kind .. ": support group")
	eq(e:match('premium="(%d)"'), "0", kind .. ": premium 0")
	eq(e:match('aggressive="(%d)"'), "0", kind .. ": not aggressive")
	eq(e:match('selftarget="(%d)"'), "1", kind .. ": selftarget")
	eq(e:match('script="chaos/necromancer/([%w_]+)%.lua"'), "raise_" .. kind, kind .. ": script")
	ok(readFile("data/spells/chaos/necromancer/raise_" .. kind .. ".lua") ~= nil, kind .. ": script file")
	for _, v in ipairs({"Necromancer", "Lich", "Bone Lord"}) do
		ok(e:find('<vocation name="' .. v .. '" />', 1, true), kind .. ": for the " .. v)
	end
	local n = 0
	for _ in e:gmatch("<vocation ") do n = n + 1 end
	eq(n, 3, kind .. ": the line only")
	eq(allIds[tostring(id)], 1, kind .. ": id used once"); eq(allWords[sp.words], 1, kind .. ": words used once")
	ok(not stock:find("\n" .. id .. ",", 1, true), kind .. ": id is no stock spell of stock_spells.csv")
	ok(sp.level >= 8, kind .. ": not below the start level 8 of the first spell")
	ok(not prev or sp.level > prev, kind .. ": unlock levels rise (warrior, archer, mage)")
	prev = sp.level
	ok(sp.mana > 0 and sp.mana < 150 and sp.cooldownMs >= 2000 and sp.cooldownMs <= 10000, kind .. ": sensible mana and cooldown")
end
-- the level-8 rule: Bone Spear is still the Necromancer line's attack spell at 8
eq(tonumber(xml:match('name="Bone Spear"[^>]*level="(%d+)"') or xml:match('level="(%d+)"[^>]*name="Bone Spear"')), 8, "Bone Spear stays at level 8")
for _, kind in ipairs(N.kinds) do
	local found
	for _, f in ipairs({"necro_risen_skeleton", "necro_lich_shade", "necro_bone_golem", "necro_risen_warrior",
			"necro_risen_archer", "necro_risen_mage"}) do
		local t = readFile("data/monster/monsters/chaos/" .. f .. ".xml") or ""
		if t:find('<monster name="' .. cfg.minions[kind].monster .. '"', 1, true) then
			found = t
		end
	end
	ok(found ~= nil, "monster XML of the " .. kind)
	if found then
		eq(tonumber(found:match('<flag targetdistance="(%d+)"')), cfg.minions[kind].range,
			kind .. ": the XML targetdistance = the config range")
	end
	local hp = found and tonumber(found:match('<health now="%d+" max="(%d+)"'))
	ok(hp and hp < 50, kind .. ": XML health below the monster tiers' minimum (no tier roll)")
	ok(found and not found:find("<attacks>", 1, true), kind .. ": no attacks of its own (hits are dealt as the owner)")
end

-- ------------------------------------------------------------------ minion spells (beta 2026-10-22)
local EFFECTS = {hitarea = true, energyhit = true, mortarea = true, drawblood = true, groundshaker = true,
	energyarea = true, blackspark = true}
local ANIS = {death = true, arrow = true, energy = true}
local names = {}
for kind in pairs({skeleton = 1, shade = 1, golem = 1, warrior = 1, archer = 1, mage = 1}) do
	local sp = cfg.minionSpells[kind]
	ok(sp and sp.single and sp.area, kind .. ": a single target and an area spell")
	for _, which in ipairs({"single", "area"}) do
		local s = sp[which]
		ok(not names[s.name], s.name .. ": one name per spell")
		names[s.name] = true
		ok(s.mult > 1 and s.cooldownMs >= cfg.minions[kind].intervalMs, s.name .. ": stronger than a hit, slower")
		ok(EFFECTS[s.hitEffect], s.name .. ": known hitEffect")
		ok(s.ani == nil or ANIS[s.ani], s.name .. ": known ani")
	end
	ok(sp.area.radius >= 1 and (sp.area.center == "self" or sp.area.center == "target"), kind .. ": area shape")
	ok(EFFECTS[sp.area.areaEffect], kind .. ": known areaEffect")
	ok(sp.area.mult < sp.single.mult, kind .. ": the area hits each enemy for less than the single one")
	if sp.area.center == "self" then
		ok(cfg.minions[kind].range == 1, kind .. ": a self centred area only on a melee kind")
	end
end
eq(N.minionSpell(cfg, "warrior", 1000, {}, 3), "area", "both ready, a crowd: the area spell")
eq(N.minionSpell(cfg, "warrior", 1000, {}, 1), "single", "one enemy: the single target spell")
eq(N.minionSpell(cfg, "warrior", 1000, {single = 2000}, 1), nil, "single cooling down, one enemy: the hit")
eq(N.minionSpell(cfg, "warrior", 1000, {area = 2000}, 5), "single", "area cooling down: the single one")
eq(N.minionSpell(cfg, "warrior", 1000, {area = 2000, single = 2000}, 5), nil, "both cooling down: the hit")
eq(N.minionSpell(cfg, "warrior", 2000, {area = 2000, single = 9000}, 2), "area", "ready again at its time")
eq(N.minionSpell(cfg, "nosuch", 1000, {}, 5), nil, "a kind without spells: the hit")
eq(N.minionSpell(cfg, "mage", 0, nil, 0), "single", "no timers yet: ready")
local a, b = N.minionSpellHit(cfg, "warrior", "single", 100, 200)
eq(a, math.floor(100 * cfg.minionSpells.warrior.single.mult), "single spell min")
eq(b, math.floor(200 * cfg.minionSpells.warrior.single.mult), "single spell max")
ok(cfg.minions.warrior.tauntMs and cfg.minions.warrior.tauntRadius >= 1, "the summoned warrior taunts")
ok(not cfg.minions.archer.tauntMs and not cfg.minions.mage.tauntMs, "the ranged ones do not")
local libSrc = readFile("data/scripts/chaos/necro_lib.lua")
for e in pairs(EFFECTS) do
	ok(libSrc:find("\n\t*" .. e .. " = CONST_ME_") or libSrc:find("[{ ]" .. e .. " = CONST_ME_"), e .. ": in necro_lib EFFECT")
end

print(string.format("necro_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
