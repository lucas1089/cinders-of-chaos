-- Run from the server/ folder: luajit tests/archetypes_test.lua (and lua5.3; CI runs both)
-- The build archetypes (docs/BUILDS.md, server/README.md "Build archetypes"):
--   * the pure rules (archetypes_core.lua): prices, Pyre Oath, the leech cap, the reflect with its PvP and boss rules,
--     Open Hand, the chain queue budget, the spreads, Cascade, Stormstring, the shatter, effigies, sigils, Aether Edge,
--     the relic;
--   * the data: the keystone nodes in the generated tree (leaves, flags, classes), the client tooltips state the
--     config's numbers, the rework lists (refund and build codes), the uniques (XML, specs, drop table, config);
--   * the engine glue (archetypes.lua) against a mocked engine: the prices on a hit, the leech, the reflect and its
--     guard, the healing price, Open Hand, a poison chain through a pack within the budget, the shatter, Cascade,
--     Stormstring, an effigy from an area cast and its pulse, a sigil, Aether Edge's health condition, Pyre Oath's
--     tick and the relic;
--   * the second round (2026-10-12): the prices of Snarewright's Creed (snare hits spared) and Covenant of Vigils, the
--     vigils' hit multipliers, Hollow Vessel (its health condition, the energy shield modifier, the immunities, the
--     early recharge, the rifts' percent base). The snares and the vigils have their own tests (snares_test.lua,
--     vigils_test.lua).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local count, failures = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what) check(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, what) check(math.abs(a - b) < 1e-6, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/archetypes_config.lua")
dofile("data/scripts/chaos/archetypes_core.lua")
local C, A = ChaosArchetypesConfig, ChaosArchetypesCore

-- ------------------------------------------------------------------------------------------------ core: prices
eq(#A.FLAGS, 16, "sixteen keystones (twelve, then four of the second round)")
local all = {}
for _, f in ipairs(A.FLAGS) do all[f] = true end
local f1 = A.flagsOf({arPyreOath = 1, strength = 3})
check(f1.arPyreOath and not f1.arSanguine, "flagsOf")
check(select(2, A.flagsOf({strength = 2})) == false, "no flags")
near(A.hitFactor({arPyreOath = true}, {origin = "melee"}), 0.75, "pyre price")
near(A.hitFactor({arPyreOath = true}, {origin = "spell", source = "pyre"}), 1, "the aura has no price")
near(A.hitFactor({arContagion = true}, {origin = "melee"}), 0.9, "contagion: weapon hits")
near(A.hitFactor({arContagion = true}, {origin = "spell"}), 1, "contagion: spells free")
near(A.hitFactor({arCascade = true}, {origin = "melee", critical = true}), 1, "cascade: crits free")
near(A.hitFactor({arCascade = true}, {origin = "melee"}), 0.95, "cascade: non-crit")
near(A.hitFactor({arCascade = true}, {origin = "condition"}), 1, "cascade: damage over time free")
near(A.hitFactor({arStormstring = true}, {origin = "ranged", bow = true}), 0.9, "stormstring: bow hit")
near(A.hitFactor({arStormstring = true}, {origin = "ranged", bow = false}), 1, "stormstring: a spear")
near(A.hitFactor({arEffigy = true}, {origin = "spell"}), 0.65, "effigy: spells")
near(A.hitFactor({arThornbound = true, arReliquary = true}, {origin = "melee"}), 0.81, "two prices multiply")
near(A.hitFactor({arReliquary = true}, {origin = "spell", source = "relic"}), 1, "the relic's own pulse")
-- the second round's prices
near(A.hitFactor({arSnarewright = true}, {origin = "ranged"}), 0.85, "snarewright: a weapon hit")
near(A.hitFactor({arSnarewright = true}, {origin = "spell", snare = true}), 1, "snarewright: a snare's hit")
near(A.hitFactor({arSnarewright = true}, {origin = "condition"}), 1, "snarewright: damage over time free")
near(A.hitFactor({arVigils = true}, {origin = "spell"}), 0.9, "covenant of vigils: own damage")
near(A.hitFactor({arIronTithe = true, arHollowVessel = true}, {origin = "melee"}), 1, "tithe and hollow: no damage price")
near(A.typeFactor({arWinterLattice = true}, "fire"), 0.7, "lattice: fire")
near(A.typeFactor({arWinterLattice = true}, "ice"), 1, "lattice: ice")
near(A.typeFactor({arCinderSigil = true}, "physical"), 0.8, "sigil: physical")
near(A.typeFactor({arCinderSigil = true}, "holy"), 1, "sigil: holy")
near(A.typeFactor({arCinderSigil = true}, "physical", {source = "sigil"}), 1, "sigil's own")

-- Pyre Oath
eq(A.pyreAura(6000), 240, "aura 4% of 6000")
eq(A.pyreAura(6000, true), 288, "aura with the mantle")
eq(A.pyreBurn(6000, 5000, 0), 150, "burn 2.5%")
eq(A.pyreBurn(6000, 100, 0), 99, "never lethal")
eq(A.pyreBurn(6000, 1, 0), 0, "at 1 health no burn")
eq(A.pyreBurn(6000, 50, 60), 109, "the shield counts")
eq(A.pyreRegen(6000), 120, "regen 2%")
check(A.pyreActive(false, true, false) and A.pyreActive(false, false, true), "active in a fight or near an enemy")
check(not A.pyreActive(true, true, true) and not A.pyreActive(false, false, false), "not in pz, not idle")

-- Sanguine Covenant
local ls = {}
eq(A.leech(ls, 1000, 1000, 5000), 50, "5% of the hit")
eq(A.leech(ls, 1200, 10000, 5000), 250, "capped at 6% a second (300)")
eq(A.leech(ls, 1900, 1000, 5000), 0, "cap reached")
eq(A.leech(ls, 2100, 1000, 5000), 50, "a new second")
eq(A.leech({}, 0, 1000, 5000, true), 60, "the unique: 6%")
eq(A.healingTaken(-1000), -700, "healing taken 70%")

-- Thornbound Oath
eq(A.reflect({landed = 1000, ownMaxHealth = 5000}), 200, "20% of what landed")
eq(A.reflect({landed = 1000, ownMaxHealth = 5000, itemReflect = 10}), 300, "item reflect counted again")
eq(A.reflect({landed = 1000, ownMaxHealth = 5000, unique = true}), 300, "the unique +10%")
eq(A.reflect({landed = 100000, ownMaxHealth = 5000}), 2500, "at most half the own health")
eq(A.reflect({landed = 3000, ownMaxHealth = 5000, pvp = true, targetMaxHealth = 10000}), 200, "PvP: a third")
eq(A.reflect({landed = 30000, ownMaxHealth = 50000, pvp = true, targetMaxHealth = 4000}), 200, "PvP: 5% of their health")
local bs = {}
eq(A.reflect({landed = 1000, ownMaxHealth = 5000, boss = true, bossState = bs, ownLevel = 300, now = 0}), 100, "boss: half")
eq(A.reflect({landed = 10000, ownMaxHealth = 50000, boss = true, bossState = bs, ownLevel = 300, now = 100}), 500,
	"boss: 2 x level a second (600)")
eq(A.reflect({landed = 10000, ownMaxHealth = 50000, boss = true, bossState = bs, ownLevel = 300, now = 500}), 0, "spent")
eq(A.reflect({landed = 1000, ownMaxHealth = 5000, boss = true, bossState = bs, ownLevel = 300, now = 1200}), 100,
	"next second")

-- Open Hand Creed
near(A.fistAttack(300), 47.5, "fist attack at 300")
near(A.fistAttack(2000), 60, "capped at 60")
eq(A.openHandFactor(300, 50, 110, 1, false, false), nil, "neither keystone nor unique")
local ohK = A.openHandFactor(300, 50, 110, 1, true, false)
local want = A.maxWeaponDamage(300, 110, 47.5, 1) * 1.1 / A.maxWeaponDamage(300, 50, 7, 1)
near(ohK, want, "keystone factor: best skill, fist attack, +10%")
near(A.openHandFactor(300, 50, 110, 1, false, true), want / 1.1 * 1.1 * 0.8, "unique alone: 80%")
near(A.openHandFactor(300, 50, 110, 1, true, true), want * 1.1, "both: +10% more")
check(ohK > 3, "the fist hit grows a lot (" .. ohK .. ")")

-- the flag storage (the spells' state) and Open Hand's attack for the strike spells
local mask = A.mask({arOpenHand = true, arReliquary = true})
check(A.maskHas(mask, "arOpenHand") and A.maskHas(mask, "arReliquary") and not A.maskHas(mask, "arPyreOath"), "mask")
check(not A.maskHas(-1, "arOpenHand"), "no storage")
check(mask < 2 ^ 31, "fits a storage")
near(A.openHandAttack(300, true, false), 47.5 * 1.1, "strikes: fist attack +10%")
near(A.openHandAttack(300, false, true), 47.5 * 1.1 * 0.8, "strikes: the ring alone")
eq(A.openHandAttack(300, false, false), nil, "strikes: nothing")
local sp = {getStorageValue = function() return A.mask({arOpenHand = true}) end, getLevel = function() return 1000 end,
	getSlotItem = function() return nil end}
near(A.spellOpenHandAttack(sp), 66, "the spells read the storage (level 1000: 60 x 1.1)")

-- the chain queue
local q = A.newQueue()
for i = 1, 45 do A.enqueue(q, {chain = 1, i = i}) end
eq(#q.items, C.chain.perChain, "one chain at most perChain")
check(A.enqueue(q, {chain = 2}), "another chain still fits")
local first = A.drain(q)
eq(#first, C.chain.perTick, "perTick a tick")
eq(first[1].i, 1, "oldest first")
local q2 = A.newQueue()
for i = 1, 300 do A.enqueue(q2, {chain = i}) end
eq(#q2.items, C.chain.queueMax, "the queue is bounded")
A.drain(q2, 1000)
A.forgetChains(q2)
check(next(q2.perChain) == nil, "budgets forgotten when empty")

-- Contagion Rite
local sp = A.contagionSpread({owner = 7, tick = 40, at = 1000, gen = 0}, 2000)
check(sp and sp.tick == 40 and sp.ticks == 5 and sp.gen == 1 and sp.targets == 3 and sp.radius == 2, "a spread")
eq(A.contagionSpread({owner = 7, tick = 40, at = 1000}, 9000), nil, "too old")
eq(A.contagionSpread({owner = 7, tick = 40, at = 1000, gen = 4}, 1000), nil, "4 deep at most")
local spu = A.contagionSpread({owner = 7, tick = 40, at = 1000, gen = 4}, 1000, true)
check(spu and spu.gen == 5 and spu.targets == 4, "the unique: one deeper, one more target")

-- Cascade, Stormstring, Lattice
eq(A.cascadeAmount(1000), 600, "cascade 60%")
eq(A.cascadeAmount(1000, true), 850, "with the unique 85%")
eq(A.cascadeIcd(), 800, "icd")
eq(A.cascadeIcd(true), 600, "unique icd")
eq(A.cascadeElement({incrementFire = 3, incrementIce = 5}), "ice", "strongest element")
eq(A.cascadeElement({}), "energy", "energy without one")
local arcs, share = A.stormArcs(true, false)
check(arcs == 3 and share == 0.40, "storm arcs")
arcs, share = A.stormArcs(false, true)
check(arcs == 1 and share == 0.25, "the bow alone")
eq(A.stormArcs(false, false), nil, "nothing")
eq(A.shatterAmount(20000, 300), 1200, "6% of 20000")
eq(A.shatterAmount(200000, 300), 3600, "at most 12 x level")
eq(A.shatterRadius(true), 3, "the wand: +1 sqm")

-- Effigy Covenant
eq(A.effigyCast({{id = 1, amount = 100, type = "ice"}}), nil, "one target: no effigy")
local cast = A.effigyCast({{id = 1, amount = 100, type = "ice"}, {id = 2, amount = 300, type = "ice"}, {id = 3, amount = 50, type = "fire"}})
check(cast and cast.count == 3 and cast.average == 150 and cast.type == "ice", "a cast")
eq(A.effigyPulse(cast), 33, "22% of the average")
local list = {}
eq(#A.effigyAdd(list, {n = 1}), 0, "first")
eq(#A.effigyAdd(list, {n = 2}), 0, "second")
local gone = A.effigyAdd(list, {n = 3})
check(#gone == 1 and gone[1].n == 1 and #list == 2, "the oldest goes")
eq(#A.effigyAdd(list, {n = 4}, true), 0, "the idol: a third may stand")

-- Sigil of Cinders
local tick, ticks, tickMs = A.igniteTick(1000)
check(tick == 37 and ticks == 4 and tickMs == 1000, "ignite 15% over 4 ticks")
eq(A.sigilPulse(1000), 50, "pulse 5%")
eq(A.sigilPulse(1000, true), 62, "pulse with the helmet")
local bsp = A.burnSpread({owner = 1, tick = 50, at = 1000, gen = 0}, 1500)
check(bsp and bsp.targets == 2 and bsp.gen == 1, "burn spread")
eq(A.burnSpread({owner = 1, tick = 50, at = 1000, gen = 3}, 1500), nil, "3 deep at most")

-- Aether Edge, Reliquary Vow
eq(A.aetherAmount(800), 48, "6% of the shield")
eq(A.aetherAmount(800, true), 80, "10% with the plate")
eq(A.aetherHealthPercent(), 80, "health 80%")
eq(A.relicHeal(10000, 30), 120, "0.6% + 2 x ml")
eq(A.relicDamage(300, 30), 270, "0.6 x level + 3 x ml")
near(A.relicBuff({[5] = 2000}, 5, 1500), 1.05, "buffed")
near(A.relicBuff({[5] = 2000}, 5, 2500), 1, "expired")

-- Hollow Vessel
local H = C.arHollowVessel
eq(A.hollowCut(5000, 0), 5000 - H.health, "cut: down to the fixed health")
eq(A.hollowCut(H.health, 4900), 4900, "cut: the applied one is part of the maximum")
eq(A.hollowCut(60, 0), 0, "below the fixed health: nothing")
eq(A.hollowShield(740, 0, false, false), 740, "no keystone: the items' shield")
eq(A.hollowShield(740, 1874, true, false), math.floor(740 * (1 + H.more) + 1874 * H.fromHealth), "items +50%, half the health")
eq(A.hollowShield(740, 1874, true, true), math.floor(740 * (1 + H.more + H.uniqueMore) + 1874 * H.fromHealth),
	"the robe: the items' part +40% more")
eq(A.hollowRecharge(true, false), H.recharge, "recharge")
eq(A.hollowRecharge(true, true), H.recharge + H.diademRecharge, "recharge with the diadem")
eq(A.hollowRecharge(false, true), H.diademRecharge, "the diadem alone")
check(A.hollowImmune("earth", "condition") and A.hollowImmune("lifedrain", "melee"), "immune: poison, life drain")
check(not A.hollowImmune("earth", "spell") and not A.hollowImmune("fire", "condition"), "not immune: an earth spell, a burn")
eq(A.earlyRecharge(0, 2000, 350, 1500, 1000, 2000), math.floor(2000 * 350 * 500 / 1000000), "half a second early")
eq(A.earlyRecharge(0, 2000, 350, 2600, 1000, 2000), math.floor(2000 * 350 * 400 / 1000000), "the part before the delay")
eq(A.earlyRecharge(0, 2000, 350, 800, 1000, 2000), 0, "too soon")
eq(A.earlyRecharge(0, 2000, 350, 4000, 1000, 2000), 0, "the engine's part")
eq(A.earlyRecharge(1990, 2000, 350, 1500, 1000, 2000), 10, "never past the maximum")
eq(A.percentBase(100, 2000, true), 2100, "percent base: health + shield")
eq(A.percentBase(5000, 2000, false), 5000, "percent base: health alone")
local mflags = A.flagsOfMask(A.mask({arHollowVessel = true, arVigils = true}))
check(mflags.arHollowVessel and mflags.arVigils and not mflags.arSnarewright, "flags of a mask")

-- ------------------------------------------------------------------------------------------------ data
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local ids = {}
for _, node in ipairs(C.nodes) do
	local t = tree.nodes[node.id]
	ids[#ids + 1] = node.id
	check(t ~= nil, "node " .. node.id .. " exists")
	if t then
		eq(t.s[node.flag], 1, node.id .. " holds " .. node.flag)
		eq(#t.n, 1, node.id .. " is a leaf")
		local list = C.classes[node.flag]
		if list then
			local nc = 0
			for _ in pairs(t.c or {}) do nc = nc + 1 end
			eq(nc, #list, node.id .. ": classes")
			for _, k in ipairs(list) do eq(t.c[k], true, node.id .. " for " .. k) end
		else
			eq(t.c, nil, node.id .. ": every class")
		end
	end
end
check(not A.classMay("arOpenHand", "monk") and A.classMay("arOpenHand", "warrior"), "Open Hand: not the Monk line")
check(A.classMay("arSanguine", "lich"), "Sanguine: every class")
-- refund and build codes
dofile("data/scripts/chaos/passivetree_config.lua")
local rw = ChaosPassiveTreeConfig.reworked
local refunded = {}
for _, entry in ipairs(rw) do
	for _, id in ipairs(entry.ids) do refunded[id] = entry.version end
end
eq(rw[2].version, 2, "rework version 2")
eq(rw[3].version, 3, "rework version 3")
dofile("data/scripts/chaos/buildshare_core.lua")
for i, id in ipairs(ids) do
	-- the first twelve came with rework 2 and code format 4, the second round with rework 3 and format 5
	local round2 = i > 12
	eq(refunded[id], round2 and 3 or 2, "refunded once: " .. id)
	eq(ChaosBuildShare.REWORKED[id], round2 and 5 or 4, "older codes leave out " .. id)
end
-- client tooltips state the numbers
local TD = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"
local fh = io.open(TD)
if fh then
	fh:close()
	dofile(TD)
	local nodes = getTreeNodes()
	local function has(id, text)
		local all = table.concat(nodes[id].stats or {}, " ")
		check(all:find(text, 1, true) ~= nil, id .. " tooltip says '" .. text .. "': " .. all)
	end
	local function pct(v) return math.floor(v * 100 + 0.5) .. "%" end
	has(108, C.arPyreOath.radius .. " sqm"); has(108, pct(C.arPyreOath.auraShare)); has(108, "2.5%")
	has(108, pct(C.arPyreOath.regen)); has(108, pct(1 - C.arPyreOath.ownDamage) .. " less")
	has(81, pct(C.arSanguine.share)); has(81, pct(C.arSanguine.capPerSecond)); has(81, pct(1 - C.arSanguine.healingTaken) .. " less")
	has(77, pct(C.arThornbound.share)); has(77, pct(C.arThornbound.ownCap)); has(77, pct(C.arThornbound.pvpCap))
	has(77, C.arThornbound.bossPerLevel .. " x your level"); has(77, pct(1 - C.arThornbound.ownDamage) .. " less")
	has(109, C.arOpenHand.attackBase .. " + level / " .. math.floor(1 / C.arOpenHand.attackPerLevel + 0.5))
	has(109, "at most " .. C.arOpenHand.attackMax); has(109, "+" .. pct(C.arOpenHand.damage - 1))
	has(107, C.arContagion.targets .. " monsters"); has(107, C.arContagion.radius .. " sqm"); has(107, C.arContagion.ticks .. " ticks")
	has(107, C.arContagion.maxGenerations .. " deep"); has(107, pct(1 - C.arContagion.weaponDamage) .. " less")
	has(78, C.arCascade.radius .. " sqm"); has(78, pct(C.arCascade.share)); has(78, string.format("%g", C.arCascade.icdMs / 1000) .. " s")
	has(78, pct(1 - C.arCascade.nonCrit) .. " less")
	has(82, C.arStormstring.arcs .. " other"); has(82, C.arStormstring.radius .. " sqm"); has(82, pct(C.arStormstring.share))
	has(82, pct(1 - C.arStormstring.mainDamage) .. " less")
	has(355, math.floor(C.arWinterLattice.recentMs / 1000) .. " s"); has(355, C.arWinterLattice.radius .. " sqm")
	has(355, pct(C.arWinterLattice.share)); has(355, C.arWinterLattice.perLevel .. " x your level")
	has(355, pct(1 - C.arWinterLattice.otherElements) .. " less")
	has(262, C.arEffigy.minTargets .. " or more"); has(262, "at most " .. C.arEffigy.max); has(262, math.floor(C.arEffigy.lifeMs / 1000) .. " s")
	has(262, "Every " .. math.floor(C.arEffigy.pulseMs / 1000) .. " s"); has(262, C.arEffigy.radius .. " sqm")
	has(262, pct(C.arEffigy.share)); has(262, pct(1 - C.arEffigy.ownSpell) .. " less")
	has(106, pct(C.arCinderSigil.igniteShare)); has(106, math.floor(C.arCinderSigil.igniteTicks * C.arCinderSigil.igniteTickMs / 1000) .. " s")
	has(106, math.floor(C.arCinderSigil.durationMs / 1000) .. " s"); has(106, C.arCinderSigil.pulseRadius .. " sqm")
	has(106, pct(C.arCinderSigil.pulseShare)); has(106, C.arCinderSigil.spreadTargets .. " more")
	has(106, pct(1 - C.arCinderSigil.otherDamage) .. " less")
	has(362, pct(C.arAetherEdge.share)); has(362, pct(1 - C.arAetherEdge.maxHealth) .. " less")
	has(253, math.floor(C.arReliquary.pulseMs / 1000) .. " s"); has(253, C.arReliquary.healRadius .. " sqm")
	has(253, string.format("%g", C.arReliquary.healShare * 100) .. "%"); has(253, C.arReliquary.healPerMagicLevel .. " x your magic")
	has(253, "+" .. pct(C.arReliquary.partyDamage)); has(253, math.floor(C.arReliquary.buffMs / 1000) .. " s")
	has(253, C.arReliquary.damageRadius .. " sqm"); has(253, string.format("%g", C.arReliquary.damagePerLevel) .. " x level")
	has(253, C.arReliquary.damagePerMagicLevel .. " x magic"); has(253, pct(1 - C.arReliquary.ownDamage) .. " less")
	-- the second round
	local SC, VC = A.snaresConfig(), A.vigilsConfig()
	has(105, SC.keystone.traps .. " more traps"); has(105, SC.keystone.mines .. " more"); has(105, pct(SC.keystone.armFactor))
	has(105, pct(SC.keystone.damage) .. " harder"); has(105, pct(1 - SC.keystone.otherDamage) .. " less")
	has(99, pct(1 - VC.keystone.reserve) .. " less"); has(99, VC.keystone.radius .. " sqm"); has(99, pct(VC.keystone.party) .. " more")
	has(99, pct(1 - VC.keystone.ownDamage) .. " less")
	has(102, pct(VC.tithe.healthShare)); has(102, pct(VC.tithe.self - 1) .. " stronger"); has(102, "Hollow Vessel")
	has(96, "health is " .. C.arHollowVessel.health); has(96, "+" .. pct(C.arHollowVessel.more))
	has(96, pct(C.arHollowVessel.fromHealth) .. " of the health"); has(96, pct(C.arHollowVessel.recharge / 1000))
	has(96, math.floor(C.arHollowVessel.earlyMs / 1000) .. " s after")
	for _, node in ipairs(C.nodes) do
		local cn = nodes[node.id]
		check(cn.isKeystone and cn.isDivine and cn.icon == node.flag, node.id .. " drawn as a keystone with its icon")
		local list = C.classes[node.flag]
		eq(cn.classes and #cn.classes or 0, list and #list or 0, node.id .. " client classes")
	end
	-- the client names every flag
	local src = io.open("../client/overlay/modules/game_passivetree/passivetree.lua"):read("*a")
	for _, f in ipairs(A.FLAGS) do check(src:find(f .. " = \"", 1, true) ~= nil, "client name of " .. f) end
	local icons = io.open("../client/overlay/modules/game_passivetree/treedata/icons.lua"):read("*a")
	for _, f in ipairs(A.FLAGS) do check(icons:find(f .. " = {", 1, true) ~= nil, "icon of " .. f) end
else
	print("(client tree not found: tooltip check skipped)")
end
-- the uniques: XML -> specs -> config -> drop table
local xml = io.open("data/items/chaos_items.xml"):read("*a")
local seen = 0
for id, key in pairs(C.uniques) do
	seen = seen + 1
	check(xml:find('<item id="' .. id .. '"', 1, true) ~= nil, "unique " .. id .. " in the XML")
	local block = xml:match('<item id="' .. id .. '".-</item>') or ""
	check(block:find('key="archetype" value="' .. key .. '"', 1, true) ~= nil, "unique " .. id .. " is " .. key)
end
eq(seen, 18, "eighteen archetype uniques (twelve, then six of the second round)")
local specs = io.open("data/lib/chaos_unique_specs.lua"):read("*a")
for id, key in pairs(C.uniques) do
	check(specs:find("[" .. id .. "] = {", 1, true) ~= nil and specs:find('archetype = "' .. key .. '"', 1, true) ~= nil,
		"spec of " .. id)
end
local drops = io.open("data/lib/chaos_unique_items.lua"):read("*a")
for id in pairs(C.uniques) do check(drops:find("id = " .. id .. ",", 1, true) ~= nil, "drop entry of " .. id) end
local _, dupes = xml:gsub('<item id="8881"', "")
eq(dupes, 1, "one unique per base id")

-- ------------------------------------------------------------------------------------------------ engine glue (mocked)
NOW = 100000
os.mtime = function() return NOW end
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, at = NOW + (delay or 0)} end
local function runEvents(untilTime)
	local guard = 0
	while true do
		table.sort(queue, function(a, b) return a.at < b.at end)
		local e = queue[1]
		if not e or e.at > (untilTime or NOW) then break end
		table.remove(queue, 1)
		local saved = NOW
		NOW = math.max(NOW, e.at)
		e.fn((table.unpack or unpack)(e.args))
		guard = guard + 1
		assert(guard < 2000, "event loop")
	end
end
local registered, callbacks = {}, {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
local callbackIndex = {}
rawset(EventCallback, "register", function(self, index)
	local l = rawget(self, "_last"); callbacks[l[1]] = callbacks[l[1]] or {}; table.insert(callbacks[l[1]], l[2])
	callbackIndex[l[2]] = tonumber(index) or 0
end)
function CreatureEvent(name) local o = {}; function o:register() registered[name] = o end; return o end
function GlobalEvent(name) local o = {}; function o:interval() end; function o:register() registered[name] = o end; return o end
bit = bit or {band = function(a, b) return (a % (2 * b) >= b) and b or 0 end}

local creatures, nextId = {}, 1
local conditionsAdded = {}
local dealt = {}
local function P(x, y, z) return {x = x, y = y, z = z or 7} end
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	local p = {x = x, y = y, z = z}
	return setmetatable(p, {__index = {sendMagicEffect = function() end, sendDistanceEffect = function() end,
		isSightClear = function() return true end}})
end
local function mk(kind, opt)
	nextId = nextId + 1
	local c = {id = nextId, kind = kind, hp = opt.hp or 1000, maxHp = opt.maxHp or opt.hp or 1000, pos = opt.pos or P(100, 100),
		name = opt.name or kind, level = opt.level or 300, ml = opt.ml or 30, es = opt.es or 0, events = {}, conds = {},
		slots = opt.slots or {}, boss = opt.boss, skills = opt.skills or {}, voc = opt.voc or 4}
	local m = {}
	function m:getId() return c.id end
	function m:isPlayer() return c.kind == "player" end
	function m:isMonster() return c.kind == "monster" end
	function m:getPlayer() return c.kind == "player" and self or nil end
	function m:getHealth() return c.hp end
	function m:getMaxHealth()
		local v = c.maxHp
		for _, cd in ipairs(c.conds) do v = v + (cd.params and cd.params[CONDITION_PARAM_STAT_MAXHITPOINTS] or 0) end
		return v
	end
	function m:getPosition() return Position(c.pos) end
	function m:getMaster() return c.master end
	function m:getName() return c.name end
	function m:getLevel() return c.level end
	function m:getMagicLevel() return c.ml end
	function m:getEnergyShield() return c.es end
	function m:setEnergyShield(v) c.es = math.max(0, math.min(v, c.maxEs or 0)) end
	function m:getMaxEnergyShield() return c.maxEs or 0 end
	function m:setMaxEnergyShield(v) c.maxEs = v; c.es = math.min(c.es, v) end
	function m:getEnergyShieldRecharge() return c.esRecharge or 200 end
	function m:setEnergyShieldRecharge(v) c.esRecharge = v end
	function m:getTile() return {hasFlag = function() return c.pz == true end} end
	function m:registerEvent(name) c.events[name] = true end
	function m:getSlotItem(slot) return c.slots[slot] end
	function m:getEffectiveSkillLevel(s) return c.skills[s] or 10 end
	function m:getFightMode() return 1 end
	c.storage = {}
	function m:getStorageValue(k) return c.storage[k] or -1 end
	function m:setStorageValue(k, v) c.storage[k] = v end
	function m:getVocation() return {getId = function() return c.voc end} end
	function m:getParty() return c.party end
	function m:getType() return {isBoss = function() return c.boss == true end} end
	function m:getCondition(t, id, sub)
		for _, cd in ipairs(c.conds) do if cd.type == t and (sub == nil or cd.sub == sub) then return cd end end
		if t == CONDITION_INFIGHT and c.inFight then return {} end
		return nil
	end
	function m:addCondition(cd) c.conds[#c.conds + 1] = cd; conditionsAdded[#conditionsAdded + 1] = {target = c.id, cond = cd} end
	function m:removeCondition(t, id, sub)
		for i = #c.conds, 1, -1 do if c.conds[i].type == t and c.conds[i].sub == sub then table.remove(c.conds, i) end end
	end
	function m:setMaster(p) c.master = p end
	function m:setDropLoot() end
	function m:remove() creatures[c.id] = nil end
	function m:isRemoved() return creatures[c.id] == nil end
	function m:teleportTo(p) c.pos = P(p.x, p.y, p.z) end
	m.c = c
	creatures[c.id] = m
	return m
end
Creature = function(id) if type(id) == "table" then return id end return creatures[id] end
Player = function(id)
	local c = type(id) == "table" and id or creatures[id]
	return c and c:isPlayer() and c or nil
end
Game = {getSpectators = function(center, a, b, rx)
	local out = {}
	for _, c in pairs(creatures) do
		local p = c.c.pos
		if p.z == center.z and math.abs(p.x - center.x) <= rx and math.abs(p.y - center.y) <= rx then out[#out + 1] = c end
	end
	table.sort(out, function(a, b) return a:getId() < b:getId() end)
	return out
end, createMonster = function(name, pos) return mk("monster", {name = name, pos = P(pos.x, pos.y, pos.z), hp = 10}) end}
ChaosSpell = {canAttack = function(a, t) return t:isPlayer() and t.c.pvpOk == true end,
	isEnemy = function(a, t) return t:isMonster() and t:getMaster() == nil end}
Chaos = {heal = function(c, amount) local before = c.c.hp; c.c.hp = math.min(c.c.maxHp, c.c.hp + amount); return c.c.hp - before end}
function doTargetCombat(attacker, target, ctype, a, b, effect, origin)
	dealt[#dealt + 1] = {attacker = attacker and attacker:getId(), target = target:getId(), type = ctype, amount = -a,
		origin = origin, depth = ChaosKeystones.depth, source = ChaosArchetypes.source}
	local ev = registered.ChaosArchetypesHit
	local pd = a
	if ev and target.c.events.ChaosArchetypesHit then
		pd = ev.onHealthChange(target, attacker, a, ctype, 0, COMBAT_NONE, origin)
	end
	if ctype == COMBAT_HEALING then
		target.c.hp = math.min(target.c.maxHp, target.c.hp + math.abs(pd))
	else
		target.c.hp = target.c.hp - math.abs(pd)
		if target.c.hp <= 0 and target:isMonster() then
			target.c.hp = 0
			if registered.ChaosArchetypesDeath and target.c.events.ChaosArchetypesDeath then
				registered.ChaosArchetypesDeath.onDeath(target)
			end
			creatures[target:getId()] = nil
		end
	end
	return true
end
function doTargetCombatHealth(aid, target, ctype, a, b)
	dealt[#dealt + 1] = {attacker = aid, target = target:getId(), type = ctype, amount = -a, selfBurn = true}
	target.c.hp = target.c.hp - math.abs(a)
end
function Condition(t)
	local cd = {type = t, params = {}}
	function cd:setParameter(k, v) self.params[k] = v; if k == CONDITION_PARAM_SUBID then self.sub = v end end
	function cd:addDamage(rounds, ms, value) self.rounds, self.ms, self.value = rounds, ms, value end
	return cd
end
function ItemType(id)
	return {getWeaponType = function() return id == 2400 and WEAPON_SWORD or (id == 8851 and WEAPON_DISTANCE or WEAPON_SHIELD) end,
		getSlotPosition = function() return id == 8851 and SLOTP_TWO_HAND or 0 end, getId = function() return id end}
end
WEAPON_NONE = 0
ChaosArchery = {kindOfType = function(it) return it:getId() == 8851 and "crossbow" or nil end}
ChaosPassiveCache = {}
ChaosItemModsCache = {}

dofile("data/scripts/chaos/archetypes.lua")
local M = ChaosArchetypes
local hitEv = registered.ChaosArchetypesHit
check(hitEv and registered.ChaosArchetypesDeath and registered.ChaosArchetypesThink, "events registered")
check(#ChaosPassiveTree.listeners >= 1, "a passive tree listener")
local listener = ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners]

local function hitBy(attacker, target, amount, ctype, origin, critical)
	target.c.events.ChaosArchetypesHit = true
	-- a spell hit runs inside a cast (the supports' cast context); everything else outside one
	attacker.c.storage[7109990] = (origin == ORIGIN_SPELL) and 1001 or -1
	local pd = hitEv.onHealthChange(target, attacker, -amount, ctype or COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE,
		origin or ORIGIN_MELEE, critical)
	return math.abs(pd)
end
local function setTree(p, bonuses)
	ChaosPassiveCache[p:getId()] = bonuses
	listener(p, bonuses)
end

-- a Warrior with Sanguine Covenant and Thornbound Oath
local sword = {getId = function() return 2400 end}
local war = mk("player", {hp = 4000, maxHp = 5000, slots = {[CONST_SLOT_LEFT] = sword}})
setTree(war, {arSanguine = 1, arThornbound = 1})
local mob = mk("monster", {hp = 50000, pos = P(101, 100)})
eq(hitBy(war, mob, 1000), 900, "Thornbound: own damage 90%")
runEvents()
eq(war.c.hp, 4045, "leeched 5% of 900")
-- healing price
local healed = hitEv.onHealthChange(war, war, 1000, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)
eq(healed, 700, "healing received 70%")
-- reflect: a monster hits the Warrior
dealt = {}
war.c.events.ChaosArchetypesHit = true
hitEv.onHealthChange(war, mob, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
runEvents()
eq(#dealt, 1, "one reflect")
check(dealt[1] and dealt[1].amount == 200 and dealt[1].target == mob:getId() and dealt[1].depth == 1, "20% reflected, guarded")
dealt = {}
hitEv.onHealthChange(war, mob, -1000, COMBAT_EARTHDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION)
runEvents()
eq(#dealt, 0, "damage over time is not reflected")
-- a boss: half, capped per second
war.c.hp, war.c.maxHp = 50000, 50000
local boss = mk("monster", {hp = 900000, pos = P(99, 100), boss = true})
dealt = {}
hitEv.onHealthChange(war, boss, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
hitEv.onHealthChange(war, boss, -10000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
runEvents()
local toBoss = 0
for _, d in ipairs(dealt) do if d.target == boss:getId() then toBoss = toBoss + d.amount end end
eq(toBoss, 600, "boss: at most 2 x level a second")

-- Open Hand: an unarmed Warrior with the keystone
local fists = mk("player", {hp = 5000, skills = {[SKILL_FIST] = 50, [SKILL_SWORD] = 110}})
setTree(fists, {arOpenHand = 1})
local mob2 = mk("monster", {hp = 50000, pos = P(140, 140)})
local f = A.openHandFactor(300, 50, 110, 1, true, false)
eq(hitBy(fists, mob2, 100), math.floor(100 * f + 1e-6), "fist hit scaled")
check(A.maskHas(fists.c.storage[C.storage], "arOpenHand"), "the flag storage written")
-- not with a weapon in the hands
fists.c.slots[CONST_SLOT_LEFT] = sword
eq(hitBy(fists, mob2, 100), 100, "a weapon: no scaling")

-- Contagion: a poison chain through a pack of 30, within the budget
creatures = {}
local thief = mk("player", {hp = 4000, pos = P(200, 200)})
setTree(thief, {arContagion = 1})
local pack = {}
for i = 0, 29 do pack[#pack + 1] = mk("monster", {hp = 30, pos = P(201 + (i % 6), 201 + math.floor(i / 6))}) end
for _, m in ipairs(pack) do m.c.events.ChaosArchetypesDeath = true end
conditionsAdded = {}
hitBy(thief, pack[1], 20, COMBAT_EARTHDAMAGE, ORIGIN_CONDITION) -- a poison tick of the thief
pack[1].c.hp = 0
registered.ChaosArchetypesDeath.onDeath(pack[1])
runEvents(NOW + 60)
local poisoned = 0
for _, ca in ipairs(conditionsAdded) do if ca.cond.type == CONDITION_POISON then poisoned = poisoned + 1 end end
eq(poisoned, 3, "the first death poisons 3")
for _, ca in ipairs(conditionsAdded) do check(ca.cond.value == -20 and ca.cond.rounds == 5, "5 ticks of the last tick") end
-- kill everything poisoned in waves: the chain stops at 4 generations and within its budget
local wave = 0
repeat
	wave = wave + 1
	local killed = 0
	for _, m in ipairs(pack) do
		if creatures[m:getId()] and m:getCondition(CONDITION_POISON) then
			hitBy(thief, m, 20, COMBAT_EARTHDAMAGE, ORIGIN_CONDITION)
			m.c.hp = 0
			registered.ChaosArchetypesDeath.onDeath(m)
			creatures[m:getId()] = nil
			killed = killed + 1
		end
	end
	NOW = NOW + 100
	runEvents(NOW)
until killed == 0 or wave > 20
local spreads = 0
for _, ca in ipairs(conditionsAdded) do if ca.cond.type == CONDITION_POISON then spreads = spreads + 1 end end
check(spreads <= 3 + 9 + 27 + 81 and spreads <= C.chain.perChain * 3, "bounded spreads (" .. spreads .. ")")
check(wave <= 6, "the chain ends (" .. wave .. " waves)")

-- the shatter: an ice-hit monster that dies bursts on its neighbours
creatures, dealt = {}, {}
local mage = mk("player", {hp = 2000, pos = P(300, 300), level = 300})
setTree(mage, {arWinterLattice = 1})
local m1 = mk("monster", {hp = 100, maxHp = 20000, pos = P(301, 300)})
local m2 = mk("monster", {hp = 5000, pos = P(302, 300)})
m2.c.events.ChaosArchetypesHit = true
eq(hitBy(mage, m1, 100, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 70, "lattice: fire 70%")
hitBy(mage, m1, 100, COMBAT_ICEDAMAGE, ORIGIN_SPELL)
registered.ChaosArchetypesDeath.onDeath(m1)
creatures[m1:getId()] = nil
NOW = NOW + 100
runEvents(NOW)
local shatter
for _, d in ipairs(dealt) do if d.target == m2:getId() and d.source == "shatter" then shatter = d end end
check(shatter and shatter.amount == 1200 and shatter.type == COMBAT_ICEDAMAGE, "shatter 6% of 20000 as ice")

-- Cascade Edge and Stormstring: a crossbow crit
creatures, dealt = {}, {}
local bowItem = {getId = function() return 8851 end}
local ranger = mk("player", {hp = 3000, pos = P(400, 400), slots = {[CONST_SLOT_LEFT] = bowItem}})
setTree(ranger, {arCascade = 1, arStormstring = 1})
ChaosPassiveCache[ranger:getId()] = {arCascade = 1, arStormstring = 1, incrementFire = 4}
local t1 = mk("monster", {hp = 90000, pos = P(403, 400)})
local t2 = mk("monster", {hp = 90000, pos = P(404, 400)})
local t3 = mk("monster", {hp = 90000, pos = P(405, 401)})
eq(hitBy(ranger, t1, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED, true), 900, "crit: no cascade price, storm 90%")
runEvents()
local burst, arcsHit = 0, 0
for _, d in ipairs(dealt) do
	if d.type == COMBAT_FIREDAMAGE then burst = burst + 1; check(d.amount == 540 and d.depth == 1 and d.target ~= t1:getId(), "burst 60% of 900, fire, guarded, not the target") end
	if d.type == COMBAT_ENERGYDAMAGE then arcsHit = arcsHit + 1; check(d.amount == 360 and d.target ~= t1:getId(), "arc 40%") end
end
eq(burst, 1, "burst on the neighbour only")
eq(arcsHit, 2, "arcs to the two others")
dealt = {}
eq(hitBy(ranger, t1, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED, true), 900, "second crit")
runEvents()
local again = 0
for _, d in ipairs(dealt) do if d.type == COMBAT_FIREDAMAGE then again = again + 1 end end
eq(again, 0, "cascade on cooldown")
eq(hitBy(ranger, t1, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED, false), 855, "non-crit: 95% x 90%")

-- Effigy: an area cast raises one, its pulse repeats the average hit
creatures, dealt = {}, {}
local caster = mk("player", {hp = 2000, pos = P(500, 500)})
setTree(caster, {arEffigy = 1})
local e1 = mk("monster", {hp = 90000, pos = P(501, 500)})
local e2 = mk("monster", {hp = 90000, pos = P(502, 500)})
eq(hitBy(caster, e1, 1000, COMBAT_ICEDAMAGE, ORIGIN_SPELL), 650, "effigy price: spells 65%")
hitBy(caster, e2, 1000, COMBAT_ICEDAMAGE, ORIGIN_SPELL)
runEvents()
local st = M.state[caster:getId()]
check(st and #st.effigies == 1 and st.effigies[1].cast.average == 650 and st.effigies[1].cast.count == 2, "one effigy")
check(st.effigies[1].id and creatures[st.effigies[1].id] and creatures[st.effigies[1].id]:getMaster() == caster, "a summon")
NOW = NOW + 2100
registered.ChaosArchetypesThink.onThink(1000)
local pulses = 0
for _, d in ipairs(dealt) do if d.amount == 143 and d.type == COMBAT_ICEDAMAGE and d.depth == 1 then pulses = pulses + 1 end end
eq(pulses, 2, "the pulse hits both for 22% of 650")
NOW = NOW + 12000
registered.ChaosArchetypesThink.onThink(1000)
eq(#M.state[caster:getId()].effigies, 0, "gone after its life")
-- a "spell" hit outside a cast (an item reflect, a proc of another system): no price, no effigy
caster.c.storage[7109990] = -1
e1.c.events.ChaosArchetypesHit, e2.c.events.ChaosArchetypesHit = true, true
eq(math.abs(hitEv.onHealthChange(e1, caster, -1000, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)), 1000, "not a cast: no price")
hitEv.onHealthChange(e2, caster, -1000, COMBAT_ICEDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)
runEvents()
eq(#M.state[caster:getId()].effigies, 0, "not a cast: no effigy")

-- Sigil of Cinders: a one-target fire spell ignites and brands; the sigil pulses
creatures, dealt, conditionsAdded = {}, {}, {}
local inq = mk("player", {hp = 4000, pos = P(600, 600)})
setTree(inq, {arCinderSigil = 1})
local s1 = mk("monster", {hp = 90000, pos = P(601, 600)})
local s2 = mk("monster", {hp = 90000, pos = P(602, 600)})
eq(hitBy(inq, s1, 1000, COMBAT_FIREDAMAGE, ORIGIN_SPELL), 1000, "fire is free")
eq(hitBy(inq, s2, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE), 800, "physical 80%")
runEvents()
local ign = 0
for _, ca in ipairs(conditionsAdded) do if ca.cond.type == CONDITION_FIRE then ign = ign + 1; eq(ca.cond.value, -37, "ignite tick") end end
eq(ign, 1, "one ignite")
check(M.state[inq:getId()] and M.state[inq:getId()].sigil and M.state[inq:getId()].sigil.bearer == s1:getId(), "branded")
NOW = NOW + 1100
dealt = {}
registered.ChaosArchetypesThink.onThink(1000)
local sp2 = 0
for _, d in ipairs(dealt) do if d.type == COMBAT_FIREDAMAGE and d.amount == 50 then sp2 = sp2 + 1 end end
eq(sp2, 2, "the sigil burns the bearer and its neighbour for 5%")
-- the bearer dies: the sigil jumps
s1.c.events.ChaosArchetypesDeath = true
registered.ChaosArchetypesDeath.onDeath(s1)
creatures[s1:getId()] = nil
eq(M.state[inq:getId()].sigil.bearer, s2:getId(), "the sigil jumped")

-- Aether Edge: the health condition and the energy on a hit
creatures, dealt = {}, {}
local monk = mk("player", {hp = 4000, es = 600, voc = 18})
setTree(monk, {arAetherEdge = 1})
local cond = monk:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, C.arAetherEdge.subId)
check(cond and cond.params[CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT] == 80, "max health 80%")
local am = mk("monster", {hp = 90000, pos = P(101, 100)})
hitBy(monk, am, 500, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE)
runEvents()
check(dealt[1] and dealt[1].amount == 36 and dealt[1].type == COMBAT_ENERGYDAMAGE and dealt[1].source == "aether",
	"6% of the shield as energy")
setTree(monk, {})
check(monk:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, C.arAetherEdge.subId) == nil, "removed with the keystone")

-- Pyre Oath: the tick burns, regenerates and hurts the enemies around
creatures, dealt = {}, {}
local jug = mk("player", {hp = 5000, maxHp = 6000, pos = P(700, 700)})
jug.c.inFight = true
setTree(jug, {arPyreOath = 1})
local pm = mk("monster", {hp = 90000, pos = P(702, 700)})
mk("monster", {hp = 90000, pos = P(704, 700)}) -- out of reach
registered.ChaosArchetypesThink.onThink(1000)
local burnSelf, aura = 0, 0
for _, d in ipairs(dealt) do
	if d.selfBurn then burnSelf = d.amount end
	if d.target == pm:getId() then aura = aura + 1; check(d.amount == 240 and d.source == "pyre" and d.type == COMBAT_FIREDAMAGE, "aura 4%") end
end
eq(burnSelf, 150, "burns 2.5%")
eq(aura, 1, "only the enemy in reach")
eq(jug.c.hp, 5000 + 120 - 150, "regenerated 2%, burnt 2.5%")
jug.c.pz = true
dealt = {}
registered.ChaosArchetypesThink.onThink(1000)
eq(#dealt, 0, "nothing in a protection zone")

-- Reliquary Vow: the warden heals the party and burns enemies
creatures, dealt = {}, {}
local sen = mk("player", {hp = 4000, maxHp = 10000, pos = P(800, 800), ml = 30})
local ally = mk("player", {hp = 1000, maxHp = 10000, pos = P(801, 800)})
local party = {getMembers = function() return {ally} end, getLeader = function() return sen end}
sen.c.party, ally.c.party = party, party
setTree(sen, {arReliquary = 1})
local rm = mk("monster", {hp = 90000, pos = P(801, 801)})
registered.ChaosArchetypesThink.onThink(1000)
local relic = M.state[sen:getId()].relic
check(relic and creatures[relic] and creatures[relic]:getMaster() == sen, "the warden follows")
eq(ally.c.hp, 1000 + 120, "the ally healed 0.6% + 2 x ml")
local holy
for _, d in ipairs(dealt) do if d.target == rm:getId() then holy = d end end
check(holy and holy.amount == 270 and holy.source == "relic", "holy 0.6 x level + 3 x ml")
eq(hitBy(ally, rm, 1000), 1050, "the ally deals +5%")
eq(hitBy(sen, rm, 1000), 900, "the owner pays 10%")
sen.c.pos = P(900, 900)
NOW = NOW + 2100
registered.ChaosArchetypesThink.onThink(1000)
eq(creatures[relic].c.pos.x, 900, "brought back past 7 sqm")
setTree(sen, {})
check(creatures[relic] == nil, "gone with the keystone")

-- ------------------------------------------------------------------------------------------------ the second round
-- Snarewright's Creed: the price spares the hits the spells' side marks as a snare's
creatures, dealt = {}, {}
local bowItem2 = {getId = function() return 8851 end}
local trapper = mk("player", {hp = 3000, pos = P(1000, 1000), slots = {[CONST_SLOT_LEFT] = bowItem2}})
setTree(trapper, {arSnarewright = 1})
local tm = mk("monster", {hp = 90000, pos = P(1001, 1000)})
eq(hitBy(trapper, tm, 1000, COMBAT_PHYSICALDAMAGE, ORIGIN_RANGED), 850, "snarewright: a bolt 85%")
trapper.c.storage[A.snaresConfig().storage.hit] = 1
tm.c.events.ChaosArchetypesHit = true
eq(math.abs(hitEv.onHealthChange(tm, trapper, -1000, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_SPELL)), 1000,
	"snarewright: a snare's hit is spared")
trapper.c.storage[A.snaresConfig().storage.hit] = -1
-- Covenant of Vigils: own damage 90%; the vigils' multipliers (vigils.lua) on a holder without other keystones
local herald = mk("player", {hp = 3000, pos = P(1000, 1002)})
setTree(herald, {arVigils = 1})
eq(hitBy(herald, tm, 1000), 900, "covenant: own damage 90%")
local plain = mk("player", {hp = 3000, maxHp = 3000, pos = P(1000, 1003)})
ChaosVigils = {any = function(pid) return pid == plain:getId() end, dealt = function() return 1.05 end,
	taken = function() return 0.94 end}
eq(hitBy(plain, tm, 1000), 1050, "a covered player deals 5% more")
plain.c.events.ChaosArchetypesHit = true
eq(math.abs(hitEv.onHealthChange(plain, tm, -1000, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)), 940,
	"a covered player takes 6% less")
eq(math.abs(hitEv.onHealthChange(plain, tm, 500, COMBAT_HEALING, 0, COMBAT_NONE, ORIGIN_SPELL)), 500, "heals untouched")
ChaosVigils = nil

-- Hollow Vessel: the health condition, the shield, the immunities, the early recharge, the rifts' base
creatures, dealt = {}, {}
local applied = {}
ChaosEnergyShield = {apply = function(player, totals)
	local maximum, recharge = 740, 200
	for _, fn in pairs(ChaosEnergyShieldModifiers) do maximum, recharge = fn(player, totals, maximum, recharge) end
	player:setMaxEnergyShield(maximum)
	player:setEnergyShieldRecharge(recharge)
	applied[#applied + 1] = {maximum, recharge}
end}
local lich = mk("player", {hp = 1974, maxHp = 1974, pos = P(1100, 1100), es = 0, voc = 21})
setTree(lich, {arHollowVessel = 1})
local hc = lich:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, C.arHollowVessel.subId)
check(hc and hc.params[CONDITION_PARAM_STAT_MAXHITPOINTS] == -(1974 - 100), "health cut to 100")
eq(lich:getMaxHealth(), 100, "maximum health 100")
eq(lich:getMaxEnergyShield(), math.floor(740 * 1.5 + 1874 * 0.5), "shield: items +50% and half the health")
eq(lich:getEnergyShieldRecharge(), 200 + 150, "recharge +15% a second")
-- a level up: the maximum without the cut grows by 30; the think renews the cut
lich.c.maxHp = 2004
registered.ChaosArchetypesThink.onThink(1000)
eq(lich:getMaxHealth(), 100, "still 100 after a level")
eq(M.hollow[lich:getId()].cut, 1904, "the cut follows")
-- immunities: poison and life drain do nothing, a burn does
local foe = mk("monster", {hp = 90000, pos = P(1101, 1100)})
lich.c.events.ChaosArchetypesHit = true
eq(hitEv.onHealthChange(lich, foe, -300, COMBAT_EARTHDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), 0, "poison: nothing")
eq(hitEv.onHealthChange(lich, foe, -300, COMBAT_LIFEDRAIN, 0, COMBAT_NONE, ORIGIN_SPELL), 0, "life drain: nothing")
eq(hitEv.onHealthChange(lich, foe, -300, COMBAT_FIREDAMAGE, 0, COMBAT_NONE, ORIGIN_CONDITION), -300, "a burn hurts")
-- the early recharge: 1.5 s after that hit the think adds the part from 1 s on
lich.c.es = 0
NOW = NOW + 1500
registered.ChaosArchetypesThink.onThink(1000)
eq(lich.c.es, math.floor(lich:getMaxEnergyShield() * 350 * 500 / 1000000), "half a second of early recharge")
-- the rifts' percent hits count health and shield
eq(M.percentBase(lich), 100 + lich:getMaxEnergyShield(), "percent base of a holder")
eq(M.percentBase(foe), 90000, "anyone else: the health")
-- the one shared helper every percent hit uses (chaos_constants.lua Chaos.percentBase): the rift, the raid, the
-- Ascended Omens and the guild boss
do
	local mockChaos = Chaos
	Chaos = nil
	dofile("data/scripts/chaos/chaos_constants.lua")
	local percentBase = Chaos.percentBase
	Chaos = mockChaos
	eq(percentBase(lich), 100 + lich:getMaxEnergyShield(), "Chaos.percentBase: health + shield for a holder")
	eq(percentBase(foe), 90000, "Chaos.percentBase: the health for anyone else")
	ChaosArchetypes = nil
	eq(percentBase(lich), 100, "Chaos.percentBase without the archetypes module: the health")
	ChaosArchetypes = {percentBase = function() error("boom") end}
	eq(percentBase(foe), 90000, "Chaos.percentBase: a failing module falls back to the health")
	ChaosArchetypes = M
	for _, f in ipairs({"rift.lua", "raid.lua", "uber.lua", "guildboss.lua"}) do
		local h = assert(io.open("data/scripts/chaos/" .. f, "r"))
		local src = h:read("*a")
		h:close()
		check(src:find("Chaos.percentBase(", 1, true) ~= nil, f .. ": its percent hits use Chaos.percentBase")
		check(src:find("shareDamage(player:getMaxHealth()", 1, true) == nil and src:find("percentHit(p:getMaxHealth()", 1, true) == nil,
			f .. ": no percent hit reads the health alone")
	end
end
-- the robe and the diadem
local robe = {getId = function() return 27390 end, getCustomAttribute = function() return 1 end}
lich.c.slots[CONST_SLOT_ARMOR] = robe
M.refreshUniques(lich)
runEvents()
eq(lich:getMaxEnergyShield(), math.floor(740 * 1.9 + 1904 * 0.5), "the robe: the items' part 90% more")
-- the keystone goes: the health comes back, the shield is the items' again
setTree(lich, {})
check(lich:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, C.arHollowVessel.subId) == nil, "the cut removed")
eq(lich:getMaxHealth(), 2004, "the full health back")
eq(lich:getMaxEnergyShield(), 740, "the items' shield back")
-- the diadem alone: recharge and the early start
local diadem = {getId = function() return 27668 end, getCustomAttribute = function() return 1 end}
local sage = mk("player", {hp = 4000, maxHp = 4000, pos = P(1200, 1200), es = 0})
sage.c.slots[CONST_SLOT_HEAD] = diadem
M.refreshUniques(sage)
runEvents()
eq(sage:getEnergyShieldRecharge(), 300, "the diadem: +10% a second")
eq(sage:getMaxEnergyShield(), 740, "the diadem: no more shield")
sage.c.events.ChaosArchetypesHit = true
hitEv.onHealthChange(sage, foe, -100, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE)
NOW = NOW + 1800
registered.ChaosArchetypesThink.onThink(1000)
eq(sage.c.es, math.floor(740 * 300 * 800 / 1000000), "the diadem's early start without the keystone")
ChaosEnergyShield = nil

-- ------------------------------------------------------------------------------------------------ spawn registration
-- the engine runs onSpawn before the placement: the monster's id is 0 until it is placed. The events must still land on
-- it (before the fix the callback looked the monster up by id 0 a tick later, found nothing, and no monster got the
-- hit event, so the vigils did nothing for players without a keystone or unique)
eq(#(callbacks.onSpawn or {}), 1, "one spawn callback")
local spawning = mk("monster", {hp = 500, pos = P(1300, 1300)})
local realId = spawning.c.id
creatures[realId] = nil
spawning.c.id = 0
for _, cb in ipairs(callbacks.onSpawn or {}) do
	check(cb(spawning, P(1300, 1300), false, false) ~= false, "the spawn goes on")
	check(callbackIndex[cb] > 0, "the spawn callback runs after the passive tree's (index 0)")
end
spawning.c.id = realId
creatures[realId] = spawning
runEvents()
check(spawning.c.events.ChaosArchetypesHit, "a new monster gets the hit event")
check(spawning.c.events.ChaosArchetypesDeath, "a new monster gets the death event")

print(string.format("archetypes_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
