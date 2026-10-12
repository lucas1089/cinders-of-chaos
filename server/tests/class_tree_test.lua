-- Run from the server/ folder: luajit tests/class_tree_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the class part of the passive tree (docs/CLASSES.md "Phase 2b", data/scripts/chaos/class_tree.lua): the flag
-- storage (mask / has / value), the save-data check (sanitize: other classes' nodes, unknown and disconnected nodes),
-- the generated data (class sections 625-664: start nodes folded into the root, one keystone per ascended class, the
-- 621 / 624 variants and their class lists, the tree still too big to complete), the client tooltips stating the
-- numbers of class_tree.lua, and the class rules that read the tree: Thief line (off-hand share, evasion, Living Shadow,
-- Iron Parry, Way of the Blade), Necromancer line (Legion, Banner Bearer, Bone Colossus, Hoarded Souls), Monk line
-- (Nerve Strike, Deep Mantra, Hundred Hands), Templar line (Burning Zeal, Sanctuary, Bastion), Pack Alpha; the line
-- keystones of the main tree (383 Blackblood Creed, 369 Covenant of the Grave, 390 Scarred Discipline, 376 Penitent's
-- Wrath): the data, the tooltips and their rules.
WEAPON_SWORD, WEAPON_CLUB, WEAPON_DISTANCE = 1, 2, 5
SLOTP_TWO_HAND = 2048

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
local C = ChaosClasses
local CT = ChaosClassTree
local tree = dofile("data/scripts/chaos/passivetree_data.lua")

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function near(a, b, m)
	checks = checks + 1
	if math.abs(a - b) > 1e-9 then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

-- ------------------------------------------------------------------ the flags
eq(CT.storage, Chaos.storage.passiveClassFx, "storage id in chaos_constants")
eq(#CT.keys < 31, true, "the flags fit a 32-bit storage")
for _, key in ipairs(CT.keys) do
	eq(type(CT.fx[key]), "table", "numbers of " .. key)
end
local mask = CT.mask({ksBastion = 1, ctTwinFangs = 1, strength = 5, ksCleavingArc = 1})
eq(CT.maskHas(mask, "ksBastion"), true); eq(CT.maskHas(mask, "ctTwinFangs"), true)
eq(CT.maskHas(mask, "ksImmovable"), false); eq(CT.maskHas(mask, "strength"), false)
eq(CT.mask({}), 0); eq(CT.mask(nil), 0)
local all = {}
for _, key in ipairs(CT.keys) do all[key] = 1 end
local full = CT.mask(all)
for _, key in ipairs(CT.keys) do eq(CT.maskHas(full, key), true, "every flag " .. key) end
-- a player mock
local function mkPlayer(storage)
	local p = {st = storage or {}}
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	return p
end
local p = mkPlayer()
eq(CT.has(p, "ksBastion"), false, "unset storage (-1): nothing")
eq(CT.value(p, "ctTwinFangs", "offhandShare"), 0, "default 0")
eq(CT.value(p, "ksWayOfTheBlade", "critMultiplier", nil), nil, "default nil")
CT.write(p, {ctTwinFangs = 1, ksWayOfTheBlade = 1})
eq(CT.has(p, "ctTwinFangs"), true)
near(CT.value(p, "ctTwinFangs", "offhandShare"), 0.15)
near(CT.value(p, "ksWayOfTheBlade", "keepShare", nil), 0.5)
CT.write(p, {})
eq(p.st[CT.storage], 0, "a reset clears the flags"); eq(CT.has(p, "ctTwinFangs"), false)

-- ------------------------------------------------------------------ generated data
local SECTIONS = {
	thief = {first = 625, classes = {"thief", "ninja", "samurai"}, a = "ninja", b = "samurai", ka = "ksLivingShadow", kb = "ksWayOfTheBlade"},
	necromancer = {first = 635, classes = {"necromancer", "lich", "bonelord"}, a = "lich", b = "bonelord", ka = "ksHoardedSouls", kb = "ksBoneColossus"},
	monk = {first = 645, classes = {"monk", "shadowfist", "ironsage"}, a = "shadowfist", b = "ironsage", ka = "ksHundredHands", kb = "ksFlowingMercy"},
	templar = {first = 655, classes = {"templar", "inquisitor", "sentinel"}, a = "inquisitor", b = "sentinel", ka = "ksDivineVerdict", kb = "ksBastion"},
}
local rootLinks = {}
for _, id in ipairs(tree.nodes[tree.root].n) do rootLinks[id] = true end
for line, sec in pairs(SECTIONS) do
	local f = sec.first
	eq(tree.nodes[f], nil, line .. ": the start node is not a server node")
	eq(rootLinks[f + 1], true, line .. ": the first line node hangs on the root")
	for i = 1, 3 do
		for _, k in ipairs(sec.classes) do eq(tree.nodes[f + i].c[k], true, line .. " line node " .. (f + i) .. " " .. k) end
	end
	for i = 4, 6 do
		eq(tree.nodes[f + i].c[sec.a], true, sec.a .. " path " .. (f + i))
		eq(tree.nodes[f + i].c[sec.b], nil, sec.b .. " not on " .. (f + i))
		eq(tree.nodes[f + i + 3].c[sec.b], true, sec.b .. " path " .. (f + i + 3))
		eq(tree.nodes[f + i + 3].c[sec.a], nil, sec.a .. " not on " .. (f + i + 3))
	end
	eq(tree.nodes[f + 6].s[sec.ka], 1, sec.a .. " keystone"); eq(#tree.nodes[f + 6].n, 1, "keystone ends the path")
	eq(tree.nodes[f + 9].s[sec.kb], 1, sec.b .. " keystone"); eq(#tree.nodes[f + 9].n, 1, "keystone ends the path")
	-- one keystone per ascended class in the section, none for the base class
	for _, k in ipairs(sec.classes) do
		local ks = 0
		for id = f, f + 9 do
			local node = tree.nodes[id]
			if node and CT.allowed(node, k) then
				for stat in pairs(node.s or {}) do
					if stat:sub(1, 2) == "ks" then ks = ks + 1 end
				end
			end
		end
		eq(ks, k == line and 0 or 1, "keystones of " .. k)
	end
end
-- every flag of class_tree.lua is on a node (or a 621 / 624 variant)
local onNodes = {}
for _, node in pairs(tree.nodes) do
	for stat in pairs(node.s or {}) do onNodes[stat] = true end
	for _, v in pairs(node.v or {}) do for stat in pairs(v) do onNodes[stat] = true end end
end
for _, key in ipairs(CT.keys) do eq(onNodes[key], true, "flag on a node: " .. key) end
-- the line keystones: one per line of the class sections, on a main tree leaf, for the base class and both ascended
-- classes of that line only
local LINE_KS = {
	{id = 383, key = "ksBlackbloodCreed", classes = {"thief", "ninja", "samurai"}},
	{id = 369, key = "ksGraveCovenant", classes = {"necromancer", "lich", "bonelord"}},
	{id = 390, key = "ksScarredDiscipline", classes = {"monk", "shadowfist", "ironsage"}},
	{id = 376, key = "ksPenitentWrath", classes = {"templar", "inquisitor", "sentinel"}},
}
local lineOf = {}
for _, ks in ipairs(LINE_KS) do
	local node = tree.nodes[ks.id]
	eq(node.s[ks.key], 1, ks.key .. " on " .. ks.id); eq(#node.n, 1, ks.id .. " is a leaf")
	local n = 0
	for _ in pairs(node.c) do n = n + 1 end
	eq(n, 3, ks.id .. ": three classes")
	for _, k in ipairs(ks.classes) do eq(node.c[k], true, ks.id .. " for " .. k); lineOf[k] = ks.id end
	for _, k in ipairs({"warrior", "deadeye", "illusionist"}) do eq(CT.allowed(node, k), false, ks.id .. " not for " .. k) end
end
-- every class of the four lines now has a keystone it may take as its base class too
for k in pairs(lineOf) do
	local ks = 0
	for _, node in pairs(tree.nodes) do
		if node.c and CT.allowed(node, k) then
			for stat in pairs(node.s or {}) do if stat:sub(1, 2) == "ks" then ks = ks + 1 end end
		end
	end
	eq(ks, (k == "thief" or k == "necromancer" or k == "monk" or k == "templar") and 1 or 2, "keystones " .. k .. " may take")
end
-- 621 / 624: only the Warrior, Ranger and Mystic lines, a variant for each
for _, id in ipairs({621, 624}) do
	for _, k in ipairs({"warrior", "juggernaut", "berserker", "ranger", "deadeye", "beastmaster", "mystic", "elementalist", "illusionist"}) do
		eq(tree.nodes[id].c[k], true, id .. " for " .. k)
	end
	for _, k in ipairs({"thief", "ninja", "lich", "monk", "sentinel"}) do eq(tree.nodes[id].c[k], nil, id .. " not for " .. k) end
	for v = 1, 25 do
		local cls = C.classKey(v)
		if cls and tree.nodes[id].c[cls] then
			eq(type(tree.nodes[id].v[C.keystoneKey(v)]), "table", id .. ": a variant for vocation " .. v)
		end
	end
end
-- the tree still cannot be completed: every class can hold far more nodes than the 248 points of level 1000
local pointsAt1000 = math.floor((1000 - Chaos.passive.startLevel) / Chaos.passive.levelsPerPoint)
for v = 1, 25 do
	local cls = C.classKey(v)
	if cls then
		local n = 0
		for id, node in pairs(tree.nodes) do
			if id ~= tree.root and CT.allowed(node, cls) then n = n + 1 end
		end
		eq(n > 2 * pointsAt1000, true, cls .. " holds " .. n .. " nodes")
	end
end

-- ------------------------------------------------------------------ the save-data check
local kept, removed = CT.sanitize(tree, {2, 9, 626, 627, 628, 629, 632}, "ninja")
eq(#kept, 6, "ninja keeps its own"); eq(removed[1].id, 632); eq(removed[1].why, "class")
kept, removed = CT.sanitize(tree, {626, 627, 628, 629, 630, 631, 2}, "warrior")
eq(#kept, 1, "a warrior keeps only the shared node"); eq(#removed, 6)
kept, removed = CT.sanitize(tree, {626, 627, 628, 629}, "samurai")
eq(#kept, 3); eq(removed[1].id, 629)
-- a node behind a removed one goes too (disconnected)
kept, removed = CT.sanitize(tree, {619, 620, 621, 600, 601}, "thief")
local why = {}
for _, r in ipairs(removed) do why[r.id] = r.why end
eq(why[621], "class", "621 is not the thief's")
kept, removed = CT.sanitize(tree, {2, 9, 99999, 11}, "warrior")
eq(#removed, 1); eq(removed[1].why, "unknown")
kept, removed = CT.sanitize(tree, {626, 627}, nil)
eq(#kept, 0, "no class: no class nodes")
-- disconnected: the second line node without the first
kept, removed = CT.sanitize(tree, {627, 628}, "thief")
eq(#kept, 0); eq(removed[1].why, "disconnected")
-- duplicates and the root are ignored
kept = CT.sanitize(tree, {1, 2, 2}, "warrior")
eq(#kept, 1)

-- ------------------------------------------------------------------ client tooltips state the numbers
local nodesFile = "../client/overlay/modules/game_passivetree/treedata/nodes.lua"
local fh = io.open(nodesFile)
if fh then
	fh:close()
	local saved = getTreeNodes
	dofile(nodesFile)
	local nodes = getTreeNodes()
	getTreeNodes = saved
	local function text(id, variant)
		local n = nodes[id]
		if variant then n = n[variant] end
		return table.concat(n.stats or {}, " ")
	end
	local function has(id, variant, s)
		checks = checks + 1
		assert(text(id, variant):find(s, 1, true), id .. " " .. tostring(variant) .. ": '" .. s .. "' in '" .. text(id, variant) .. "'")
	end
	local fx = CT.fx
	has(621, "juggernaut", math.floor(fx.ksImmovable.reduction * 100) .. "%")
	has(621, "juggernaut", math.floor(fx.ksImmovable.lowReduction * 100) .. "%")
	has(624, "berserker", math.floor(fx.ksUndyingRage.heal * 100) .. "%")
	has(624, "berserker", math.floor(fx.ksUndyingRage.lowHeal * 100) .. "%")
	has(621, "deadeye", "+" .. math.floor(fx.ksHuntersFocus.perHit * 100) .. "%")
	has(621, "deadeye", "+" .. math.floor(fx.ksHuntersFocus.maxBonus * 100 + 0.5) .. "%")
	has(624, "beastmaster", "+" .. math.floor(fx.ksPackAlpha.bonus * 100 + 0.5) .. "%")
	has(624, "beastmaster", math.floor(fx.ksPackAlpha.reduction * 100 + 0.5) .. "% less")
	has(629, nil, math.floor((Chaos.classes.dualWield.share + fx.ctTwinFangs.offhandShare) * 100 + 0.5) .. "%")
	has(630, nil, math.floor(fx.ctFleetShadow.evasion * 100 + 0.5) .. "%")
	has(631, nil, "+" .. math.floor(fx.ksLivingShadow.bonus * 100) .. "%")
	has(631, nil, math.floor(fx.ksLivingShadow.durationMs / 1000) .. " s")
	has(633, nil, "+" .. math.floor(fx.ctIronParry.bonus * 100) .. "%")
	has(633, nil, math.floor(fx.ctIronParry.windowMs / 1000) .. " s")
	has(634, nil, "every melee hit")
	has(640, nil, "+" .. math.floor(fx.ctLingeringRot.bonus * 100) .. "%")
	has(641, nil, "+" .. math.floor(fx.ksHoardedSouls.perFreeSlot * 100 + 0.5) .. "%")
	has(641, nil, "+" .. math.floor(fx.ksHoardedSouls.withShade * 100 + 0.5) .. "%")
	has(643, nil, "+" .. math.floor((0.30 + fx.ctBannerBearer.damage) * 100 + 0.5) .. "%")
	has(644, nil, "+" .. math.floor(fx.ksBoneColossus.hit * 100) .. "%")
	has(644, nil, "+" .. math.floor(fx.ksBoneColossus.health * 100) .. "%")
	has(650, nil, "+" .. math.floor((0.05 + fx.ctNerveStrike.perStack) * 100 + 0.5) .. "%")
	has(653, nil, math.floor(fx.ctDeepMantra.reduction * 100 + 0.5) .. "%")
	has(654, nil, math.floor(fx.ksFlowingMercy.share * 100 + 0.5) .. "%")
	has(660, nil, math.floor((0.25 + fx.ctBurningZeal.share) * 100 + 0.5) .. "%")
	has(661, nil, math.floor(fx.ksDivineVerdict.chance * 100 + 0.5) .. "%")
	has(663, nil, "0." .. math.floor((0.004 + fx.ctSanctuary.regen) * 1000 + 0.5) .. "%")
	has(664, nil, math.floor(fx.ksBastion.reduction * 100 + 0.5) .. "%")
	has(664, nil, fx.ksBastion.radius .. " sqm")
	-- the line keystones (main tree)
	has(383, nil, "+" .. math.floor(fx.ksBlackbloodCreed.poisonBonus * 100 + 0.5) .. "%")
	has(383, nil, fx.ksBlackbloodCreed.evasionScale == 0.5 and "halved" or "?")
	has(369, nil, "+" .. math.floor(fx.ksGraveCovenant.minionHit * 100 + 0.5) .. "% damage")
	has(369, nil, "+" .. math.floor(fx.ksGraveCovenant.minionHealth * 100 + 0.5) .. "% health")
	has(369, nil, math.floor(fx.ksGraveCovenant.ownSpell * 100 + 0.5) .. "% less")
	has(390, nil, fx.ksScarredDiscipline.chi .. " chi")
	has(390, nil, math.floor(fx.ksScarredDiscipline.icdMs / 1000) .. " s")
	has(390, nil, fx.ksScarredDiscipline.minChi .. " chi or more")
	has(390, nil, math.floor(fx.ksScarredDiscipline.reduction * 100 + 0.5) .. "% less")
	has(376, nil, math.floor(fx.ksPenitentWrath.share * 100 + 0.5) .. "% of the damage")
	has(376, nil, fx.ksPenitentWrath.perMagicLevel .. " x magic level")
	has(376, nil, (fx.ksPenitentWrath.icdMs / 1000) .. " s")
	has(376, nil, fx.ksPenitentWrath.auraScale == 0.5 and "halved" or "?")
	for _, id in ipairs({369, 376, 383, 390}) do
		eq(nodes[id].isKeystone and nodes[id].isDivine, true, id .. " is drawn as a keystone")
		for _, k in ipairs(nodes[id].classes) do eq(tree.nodes[id].c[k], true, "client classes of " .. id .. ": " .. k) end
	end
	-- class lists on the client nodes match the server data
	for id = 625, 664 do
		local n, s = nodes[id], tree.nodes[id]
		if n.isStartNode then
			eq(s, nil, "start " .. id)
		else
			for _, k in ipairs(n.classes) do eq(s.c[k], true, "client classes of " .. id .. ": " .. k) end
		end
	end
else
	print("(client tree not found: tooltip check skipped)")
end

-- ------------------------------------------------------------------ Thief line rules
local cfg = Chaos.classes
eq(C.offhandDamage(1000, 50, 50, false), 500, "base share")
eq(C.offhandDamage(1000, 50, 50, false, 0.15), 650, "Twin Fangs")
near(C.dodgeChance(12, 0.04), 0.16, "Fleet Shadow on the Ninja"); eq(C.dodgeChance(4, 0.04), 0, "no evasion class")
eq(C.dodges(12, true, 0.15, 0.04), true); eq(C.dodges(12, true, 0.15), false)
eq(C.counterDamage(1000), 1500); eq(C.counterDamage(1000, 0.5), 2250, "Iron Parry")
C.livingOpen(7, 1000)
near(C.livingFactor(7, 1500), 1.25, "in the window"); near(C.livingFactor(7, 5000), 1, "after it"); near(C.livingFactor(8, 1500), 1)
C.clear(7); near(C.livingFactor(7, 1500), 1, "cleared")
C.bushidoState[5] = {untilMs = 100000, base = 10, since = 0}
C.bushidoOnDamaged(5, 1000, 0.5)
eq(C.bushidoStacks(5, 1000), 5, "Way of the Blade keeps half")
C.bushidoOnDamaged(5, 1000)
eq(C.bushidoStacks(5, 1000), 0, "without it: none")
C.bushidoState[5] = {untilMs = 100000, base = 10, since = 0}
eq(C.bushidoRoll(5, 1000, 0.01), cfg.bushido.critMultiplier)
-- the Samurai's guard: every hit the stance does not parry
near(C.counterGuard(1000), 1 - cfg.counter.guard, "guard in the stance"); near(C.counterGuard(0), 1, "no stance")
eq(cfg.counter.windowMs, 3000); eq(cfg.counter.tauntRadius > 0, true, "the stance taunts")

-- Pack Alpha
local a1, b1 = C.biteValues(1000, 150)
local a2, b2 = C.biteValues(1000, 150, 1.35)
eq(math.abs(b2 / b1 - 1.35) < 0.01, true, "Pack Alpha bites")
local bm = mkPlayer()
bm.getLevel = function() return 1000 end
bm.getEffectiveSkillLevel = function() return 150 end
SKILL_DISTANCE = 4
eq(select(2, C.biteValuesFor(bm)), b1, "no keystone")
CT.write(bm, {ksPackAlpha = 1})
eq(select(2, C.biteValuesFor(bm)), b2, "with the keystone")

-- ------------------------------------------------------------------ Necromancer line rules
local ncfg = dofile("data/scripts/chaos/necro_config.lua")
dofile("data/scripts/chaos/necro_core.lua")
local N = ChaosNecroCore
eq(N.minionCap(ncfg, "bonelord", "skeleton", 300, 1), 6, "Legion"); eq(N.minionCap(ncfg, "bonelord", "skeleton", 300), 5)
eq(N.minionCap(ncfg, "lich", "skeleton", 300, 1), 0, "Legion adds nothing the class does not raise")
eq(N.minionCap(ncfg, "bonelord", "golem", 300, 1), 1, "the golem stays one")
eq(N.raisePlan(ncfg, "bonelord", 300, 5, 0), nil, "army complete")
eq(N.raisePlan(ncfg, "bonelord", 300, 5, 0, 1).raise, 1, "Legion: one more")
eq(#N.overCap(ncfg, "bonelord", 300, {{kind = "skeleton"}, {kind = "skeleton"}, {kind = "skeleton"}, {kind = "skeleton"},
	{kind = "skeleton"}, {kind = "skeleton"}}, 1), 0, "six with Legion")
local ha = select(2, N.minionHit(ncfg, "bonelord", "skeleton", 300, 100, true))
local hb = select(2, N.minionHit(ncfg, "bonelord", "skeleton", 300, 100, 0.45))
eq(math.abs(hb / ha - 1.45 / 1.30) < 0.01, true, "Banner Bearer")
local g1 = select(2, N.minionHit(ncfg, "bonelord", "golem", 300, 100, false))
local g2 = select(2, N.minionHit(ncfg, "bonelord", "golem", 300, 100, false, 1.6))
eq(math.abs(g2 / g1 - 1.6) < 0.01, true, "Bone Colossus hit")
eq(N.minionHealth(ncfg, "bonelord", "golem", 300, 100, 1.5), math.floor(N.minionHealth(ncfg, "bonelord", "golem", 300, 100) * 1.5 + 0.5) - 0, "Bone Colossus health")
near(N.soulHoard(ncfg, "lich", 1, 0), 1.25, "base Soul Hoard"); near(N.soulHoard(ncfg, "lich", 1, 1), 1)
near(N.soulHoard(ncfg, "lich", 1, 0, CT.fx.ksHoardedSouls), 1.40, "Hoarded Souls, no shade")
near(N.soulHoard(ncfg, "lich", 1, 1, CT.fx.ksHoardedSouls), 1.15, "Hoarded Souls, shade out")
near(N.soulHoard(ncfg, "bonelord", 1, 0, CT.fx.ksHoardedSouls), 1, "only the Lich")

-- ------------------------------------------------------------------ Monk line rules
dofile("data/scripts/chaos/monk_chi_core.lua")
local M = ChaosMonk
near(M.pressureMultiplier(5, 0.01), 1.30, "Nerve Strike"); near(M.pressureMultiplier(5), 1.25)
eq(M.mantraDamage(-1000, 0.11), 890, "Deep Mantra"); eq(M.mantraDamage(-1000), 920)
eq(M.ids.subId.mantraDeep ~= M.ids.subId.mantra, true)
eq(M.critGivesChi(3, 1000, 1000), true); eq(M.critGivesChi(3, 1500, 1000), false, "Hundred Hands cooldown")
eq(M.critGivesChi(3, 2000, 1000), true); M.clear(3); eq(M.critGivesChi(3, 2100, 1000), true, "cleared")
-- the Iron Sage heals (the second healer)
local h300, t300 = M.sageBreathHeal(300, 110, 5)
eq(h300, math.floor(300 * M.cfg.sageBreath.perLevel + 110 * M.cfg.sageBreath.perFist), "breath on an ally, 5 chi")
eq(t300, math.floor(h300 * M.cfg.breath.hotShare / M.cfg.breath.hotTicks), "its heal over time")
eq(M.mantraHeal(1000, 140), math.floor(1000 * M.cfg.mantra.heal.perLevel + 140 * M.cfg.mantra.heal.perFist), "mantra pulse")
eq(M.sageBreathHeal(300, 110, 1) < h300, true, "fewer chi, less heal")

-- ------------------------------------------------------------------ Templar line rules
dofile("data/scripts/chaos/templar_aura_core.lua")
local T = ChaosTemplar
eq(T.radiantDamage(24, 1000, false), 250); eq(T.radiantDamage(24, 1000, false, 0.05), 300, "Burning Zeal")
local bastion = {reduction = 0.04, radius = 1, bastion = true}
local aura = T.auraOf(25, bastion)
eq(aura.radius, 6); near(aura.reduction, 0.16); eq(aura.bastion, true)
eq(T.auraOf(25).radius, 5, "the config is untouched")
near(T.auraOf(25, {regenPct = 0.001}).regenPct, 0.005, "Sanctuary")
local players = {{id = 1, pos = {x = 0, y = 0, z = 7}, party = 9}, {id = 2, pos = {x = 6, y = 0, z = 7}, party = 9}}
local got = T.collectAuras({{id = 1, voc = 25, pos = players[1].pos, party = 9, bonus = bastion}}, players, 0)
eq(got[2] ~= nil, true, "Bastion reaches 6 sqm"); eq(got[2].bastion, true)
got = T.collectAuras({{id = 1, voc = 25, pos = players[1].pos, party = 9}}, players, 0)
eq(got[2], nil, "5 sqm without it")
near(T.damageTakenFactor(nil, true, 0.5), 0.8, "Aegis at half for the party"); near(T.damageTakenFactor(nil, true), 0.6)

-- ------------------------------------------------------------------ the line keystones (rules)
-- Blackblood Creed (Thief line): every weapon hit poisons, the poison +60%, evasion halved
local creed = CT.fx.ksBlackbloodCreed
local hit = 1000
local plainTick = C.poisonTick(hit)
eq(plainTick, math.floor(hit * cfg.poisonBlades.share / cfg.poisonBlades.ticks + 0.5), "Poison Blades tick")
eq(C.poisonTick(hit, creed.poisonBonus), math.floor(hit * cfg.poisonBlades.share * 1.6 / cfg.poisonBlades.ticks + 0.5), "+60%")
eq(C.poisonTick(hit, 0), plainTick, "no bonus")
eq(C.weaponPoisons(true, false, true), true, "the keystone poisons without the buff")
eq(C.weaponPoisons(true, true, false), true, "the buff alone"); eq(C.weaponPoisons(true, false, false), false, "neither")
eq(C.weaponPoisons(false, true, true), false, "spells never poison")
near(C.dodgeChance(12, 0, creed.evasionScale), 0.06, "Ninja 12% -> 6%")
near(C.dodgeChance(12, 0.04, creed.evasionScale), 0.08, "Fleet Shadow is halved too")
eq(C.dodges(11, true, 0.05, 0, creed.evasionScale), false, "Thief 8% -> 4%: a roll of 0.05 hits")
eq(C.dodges(11, true, 0.05), true, "without the keystone it is a dodge")
-- Covenant of the Grave (Necromancer line): minions +50% hit and health, the own spells -25%
local cv = CT.fx.ksGraveCovenant
local ch, chh, co = N.covenant(cv)
near(ch, 1.5); near(chh, 1.5); near(co, 0.75)
local a1n, b1n, c1n = N.covenant(nil)
eq(a1n + b1n + c1n, 3, "without it: 1, 1, 1")
local s1 = select(2, N.minionHit(ncfg, "necromancer", "skeleton", 300, 100, false))
local s2 = select(2, N.minionHit(ncfg, "necromancer", "skeleton", 300, 100, false, ch))
eq(math.abs(s2 / s1 - 1.5) < 0.01, true, "a skeleton hit +50%")
eq(math.abs(N.minionHealth(ncfg, "lich", "shade", 300, 100, chh) / N.minionHealth(ncfg, "lich", "shade", 300, 100) - 1.5) < 0.01,
	true, "the shade's health +50%")
local f = {scale = 1, mlMin = 1, mlMax = 1, baseMin = 0, baseMax = 0}
local v1a, v1b = N.values(ncfg, f, 300, 100, 1)
local v2a, v2b = N.values(ncfg, f, 300, 100, co)
eq(math.abs(v2b / v1b - 0.75) < 0.01, true, "an own spell -25%")
-- the glue of necro_lib.lua (both Lua states use it): minion factors and the own spells
local okLib = pcall(dofile, "data/scripts/chaos/necro_lib.lua")
if okLib and ChaosNecro and ChaosNecro.minionFactor then
	local NL = ChaosNecro
	local nec = mkPlayer()
	nec.getVocation = function() return {getId = function() return 20 end} end
	nec.getLevel = function() return 300 end
	nec.getMagicLevel = function() return 100 end
	nec.getSummons = function() return {} end
	near(NL.minionFactor(nec, "skeleton", "hit"), 1, "no keystone: skeleton 1")
	near(NL.ownSpellFactor(nec), 1, "no keystone: own spells 1")
	CT.write(nec, {ksGraveCovenant = 1})
	near(NL.minionFactor(nec, "skeleton", "hit"), 1.5, "Covenant: skeleton hits")
	near(NL.minionFactor(nec, "shade", "health"), 1.5, "Covenant: the shade's health")
	CT.write(nec, {ksGraveCovenant = 1, ksBoneColossus = 1})
	near(NL.minionFactor(nec, "golem", "hit"), 1.5 * 1.6, "Covenant and Bone Colossus multiply on the golem")
	near(NL.ownSpellFactor(nec), 0.75, "own spells -25%")
	near(NL.spellFactor(nec), 0.75, "a Necromancer has no Soul Hoard: 0.75")
	local a0 = select(2, N.values(ncfg, f, 300, 100, 1))
	eq(select(2, NL.values(nec, f)), select(2, N.values(ncfg, f, 300, 100, 0.75)), "a spell's values with the keystone")
	eq(a0 > select(2, NL.values(nec, f)), true, "lower than without")
else
	print("(necro_lib.lua not loadable without the engine here: its glue check skipped)")
end
-- Scarred Discipline (Monk line): no dodge, chi from hits taken (one every 2 s), -10% at 3+ chi
local sc = CT.fx.ksScarredDiscipline
eq(M.dodges(17, true, false, 0.0), true, "a Monk dodges a roll of 0"); eq(M.dodges(17, true, false, 0.0, true), false, "not with it")
eq(M.scarGivesChi(4, 10000, sc), true); eq(M.scarGivesChi(4, 11999, sc), false, "one every 2 s")
eq(M.scarGivesChi(4, 12000, sc), true); M.clear(4); eq(M.scarGivesChi(4, 12100, sc), true, "cleared")
near(M.scarFactor(2, sc), 1, "2 chi: nothing"); near(M.scarFactor(3, sc), 0.9, "3 chi: -10%"); near(M.scarFactor(5, sc), 0.9)
near(M.scarFactor(5, nil), 1, "without it")
-- Penitent's Wrath (Templar line): the answer, its cooldown, the halved aura
local pw = CT.fx.ksPenitentWrath
eq(T.penitentDamage(-1000, 25, pw), 400 + 100, "40% of 1000 + 4 x 25")
eq(T.penitentDamage(0, 25, pw), 0, "nothing taken, no answer"); eq(T.penitentDamage(1000, 25, nil), 0, "without it")
eq(T.penitentReady(8, 1000, pw), true); eq(T.penitentReady(8, 1499, pw), false, "one every 0.5 s")
eq(T.penitentReady(8, 1500, pw), true); T.clear(8); eq(T.penitentReady(8, 1600, pw), true, "cleared")
near(T.auraOf(23, {scale = pw.auraScale}).reduction, 0.03, "the Templar's aura 6% -> 3%")
near(T.auraOf(25, {reduction = 0.04, radius = 1, bastion = true, scale = pw.auraScale}).reduction, 0.08,
	"with Bastion: (12% + 4%) halved")
eq(T.auraOf(23, {scale = pw.auraScale}).radius, 4, "the radius stays")
got = T.collectAuras({{id = 1, voc = 23, pos = players[1].pos, party = 9, bonus = {scale = 0.5}},
	{id = 3, voc = 24, pos = players[1].pos, party = 9}}, {players[1]}, 0)
near(got[1].reduction, 0.04, "an Inquisitor's full 4% beats a halved Templar aura (3%)")

-- ------------------------------------------------------------------ the class damage factor
local saved = CT.classDamage
CT.classDamage = {thief = {{300, 0.5}, {1000, 0.4}}, samurai = {{300, 0.3}, {1000, 0.2}}}
near(CT.damageFactor("ninja", "thief", 300), 0.5, "the line's factor"); near(CT.damageFactor("ninja", "thief", 650), 0.45, "linear")
near(CT.damageFactor("ninja", "thief", 100), 0.5, "below the first point"); near(CT.damageFactor("ninja", "thief", 2000), 0.4)
near(CT.damageFactor("samurai", "thief", 1000), 0.2, "a class entry wins"); near(CT.damageFactor("warrior", "warrior", 1000), 1)
CT.classDamage = saved

print("class_tree_test: " .. checks .. " checks, OK")
