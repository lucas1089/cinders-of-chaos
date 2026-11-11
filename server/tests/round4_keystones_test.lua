-- Run from the server/ folder: luajit tests/round4_keystones_test.lua (and lua5.3; CI runs both). No engine.
-- The round 4 keystones of the passive tree (O450): Momentum (706), Attunement (707), Open Wounds (708):
--   * the pure rules (round4_keystones_core.lua): the speed above the base, Momentum's gain as the unique items' statscale
--     family, the larger-of-two rule against a speed-scaling unique, the element lock and its price, the bleed;
--   * the maths of Momentum at the breakpoints of the models (level 100, 500, 1000) with the fastest legal speed, every source
--     checked against the file that holds it, and the hard ceiling of the engine;
--   * the +40% rule of the owner: every keystone stacked with two others of the median size stays at or below +40%
--     (the engine glue against mocked creatures is in archetypes_test.lua);
--   * the data: the nodes in the generated tree (new, appended, one link into the old tree each), the client tooltips state
--     the config's numbers, classes agree, icons exist, the flags and their bits, the labels, the names.
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label) check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, label) check(math.abs(a - b) < 1e-9, label .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/round4_keystones_core.lua")
dofile("data/scripts/chaos/archetypes_config.lua")
dofile("data/scripts/chaos/archetypes_core.lua")
dofile("data/lib/chaos_speed.lua")
local R, cfg, A = ChaosRound4, ChaosRound4Config, ChaosArchetypesCore
local rule = cfg.rule

-- ------------------------------------------------------------------------------------------------ Momentum
near(R.speedAbovePct(1500, 1000), 50, "50% above the base")
near(R.speedAbovePct(1000, 1000), 0, "at the base")
near(R.speedAbovePct(800, 1000), 0, "slowed: 0, never negative")
near(R.speedAbovePct(1000, 0), 0, "no base speed")
near(R.speedAbovePct(nil, nil), 0, "nothing")
near(R.momentumFactor(0), 1, "no speed above the base")
near(R.momentumFactor(4.99), 1, "just under the first step")
near(R.momentumFactor(5), 1.01, "the first step: +1%")
near(R.momentumFactor(24), 1.04, "four steps")
near(R.momentumFactor(50), 1.10, "ten steps: the cap")
near(R.momentumFactor(5000), 1.10, "far above: still the cap")
near(R.momentumFactor(50, true), 1 + 0.10 / 3, "against a player a third of the gain")
near(R.momentumFactor(0, true), 1, "no gain, no PvP scaling")
eq(R.momentumGainPct(50), 10, "gain in percent")
near(R.momentumTaken(), 1.08, "the price: 8% more damage taken")

-- the gain IS the statscale family of the unique items: same maths as unique_passives_core.lua on an entry with the same numbers
local m = cfg.arMomentum
local entry = {family = "statscale", stat = "speed", from = 0, per = m.per, bonusPer = m.bonusPer, cap = m.cap, origin = "any"}
for _, above in ipairs({0, 4, 5, 9, 24, 37, 49, 50, 80, 400}) do
	local f = ChaosUniquePassivesCore.dealt(ChaosUniquePassivesConfig, {}, {entry},
		{now = 0, origin = "melee", elem = "fire", stats = {speed = above}})
	near(R.momentumFactor(above), f, "the statscale family gives the same factor at " .. above .. "% above the base")
end
-- the unique's own breakpoints: a speed-scaling unique saturates sooner than Momentum (per 6 above 200, cap 40)
local uc = ChaosUniquePassivesConfig
local saturated = 0
for _, e in pairs(uc.passives) do
	if e.family == "statscale" and e.stat == "speed" then
		saturated = saturated + 1
		check(e.cap >= 20, "a speed-scaling unique gives at least +20%: Momentum's cap is under it, so Momentum never beats one")
	end
end
check(saturated >= 5, "the unique items have speed-scaling passives (the family Momentum reuses): " .. saturated)

-- the larger of the two counts
near(R.momentumAgainstUnique(1.10, 1), 1.10, "no unique: the keystone's own factor")
near(R.momentumAgainstUnique(1.10, nil), 1.10, "no unique (nil)")
near(R.momentumAgainstUnique(1.10, 1.40), 1, "a unique of +40%: the keystone adds nothing, never a malus")
near(R.momentumAgainstUnique(1.10, 1.10), 1, "equal: nothing on top")
near(R.momentumAgainstUnique(1.10, 1.05), 1.10 / 1.05, "a smaller unique: the part over it")
near(R.momentumAgainstUnique(1, 1.20), 1, "no gain stays none")

-- ------------------------------------------------------------------------------------------------ the legal speed
-- Every source of speed above the base a player can have in a fight, in percent of the base speed (config rule.speed), each
-- checked against the file that holds it; the base speed by level is the engine's (data/lib/chaos_speed.lua).
local function read(path)
	local f = assert(io.open(path, "r"))
	local t = f:read("*a")
	f:close()
	return t
end
local items = read("data/lib/chaos_item_mods.lua")
-- O461: the movement speed modifier has no cap of its own; the boots' top tier is the most the worn items give (one slot)
check(items:match('key = "movespeed"[^\n]-cap = (%d+)') == nil, "the movespeed modifier has no cap")
dofile("data/lib/chaos_item_mods.lua")
eq(ChaosItemMods.byKey.movespeed.tiers[8][2], rule.speed.items, "the items' movespeed: the top tier of the boots")
local consts = read("data/scripts/chaos/chaos_constants.lua")
local per, max = consts:match('key = "speed", name = "Movement Speed", perPoint = ([%d.]+), maxPoints = (%d+)')
near(tonumber(per) * tonumber(max), rule.speed.paragon, "Paragon movement speed")
dofile("data/scripts/chaos/vigils_config.lua")
local haste
for _, v in ipairs(ChaosVigilsConfig.list) do if v.key == "haste" then haste = v.speed end end
near(haste * 100, rule.speed.vigil, "Vigil of Haste")
check(read("data/spells/chaos/shared/rallying_cry.lua"):find("+10%% melee/distance/magic and speed for 12s") ~= nil, "Banner Call gives +10% speed")
eq(rule.speed.banner, 10, "Banner Call in the config")
local blessings = dofile("data/scripts/chaos/blessings_config.lua")
local ember
for _, b in ipairs(blessings.pool) do if b.key == "speed" then ember = b.value end end
eq(ember, rule.speed.ember, "Ember of Haste")
eq(tonumber(read("data/scripts/chaos/passivetree_effects.lua"):match("maxSpeed = (%d+)")), rule.speed.treeFlat, "the tree's speed cap (speed points)")
eq(ChaosSpeed.defaults.maxSpeed, 2600, "the engine's top walk speed")

local function above(level, withBuffs)
	local base = ChaosSpeed.baseSpeed(rule.vocationBase, level)
	local s = rule.speed
	local pct = s.items + s.paragon + s.vigil + s.treeFlat * 100 / base
	if withBuffs then
		pct = pct + s.banner + s.ember
	end
	local step = math.min(ChaosSpeed.defaults.maxSpeed, base * (1 + pct / 100))
	return R.speedAbovePct(step, base), base
end
local table_ = {}
for _, level in ipairs(rule.levels) do
	local sustained, base = above(level, false)
	local peak = above(level, true)
	local gainSustained, gainPeak = R.momentumGainPct(sustained), R.momentumGainPct(peak)
	table_[#table_ + 1] = string.format("level %4d base %4d  sustained %.1f%% -> +%d%%   peak %.1f%% -> +%d%%", level, base, sustained,
		gainSustained, peak, gainPeak)
	check(gainPeak == cfg.arMomentum.cap, "level " .. level .. ": the fastest legal speed reaches the cap")
	check(gainSustained >= 7 and gainSustained <= cfg.arMomentum.cap, "level " .. level .. ": without the buffs the gain is +7% or more, at most the cap")
	check((R.momentumFactor(peak) - 1) <= rule.ownerCap, "level " .. level .. ": the gain is at or below +40%")
end
-- whatever else adds speed (a mount's flat speed, a future source): the gain never passes the cap, and the engine's top speed
-- bounds the percent anyway
for _, level in ipairs(rule.levels) do
	local base = ChaosSpeed.baseSpeed(rule.vocationBase, level)
	local ceiling = R.speedAbovePct(ChaosSpeed.defaults.maxSpeed, base)
	check(R.momentumFactor(ceiling) - 1 <= cfg.arMomentum.cap / 100 + 1e-9, "level " .. level .. ": at the engine's top speed (" .. string.format("%.0f", ceiling) .. "% above) the cap holds")
	check(R.momentumFactor(ceiling * 3) - 1 <= cfg.arMomentum.cap / 100 + 1e-9, "level " .. level .. ": three times that: the cap holds")
end
if os.getenv("ROUND4_PRINT") then
	for _, l in ipairs(table_) do print(l) end
end

-- ------------------------------------------------------------------------------------------------ Attunement
near(R.attunementFactor("fire", "fire"), 1.11, "the favoured element +11%")
near(R.attunementFactor("ice", "fire"), 0.85, "another element -15%")
near(R.attunementFactor("holy", "ice"), 0.85, "holy pays too")
near(R.attunementFactor("physical", "fire"), 1, "physical is no element")
near(R.attunementFactor("lifedrain", "fire"), 1, "drain is no element")
near(R.attunementFactor("fire", nil), 1, "no lock: nothing")
eq(R.lockedElement({incrementFire = 6, incrementIce = 3}), "fire", "the largest increment")
eq(R.lockedElement({incrementFire = 3, incrementIce = 6, incrementHoly = 5}), "ice", "the largest increment (ice)")
eq(R.lockedElement({incrementEnergy = 4, incrementEarth = 4}), "energy", "a tie goes to the first of fire, ice, energy, earth, death, holy")
eq(R.lockedElement({strength = 9, incrementPhysical = 20}), nil, "no element increment: no lock")
eq(R.lockedElement(nil), nil, "no bonuses")
near(R.attunementMix({fire = 1}, "fire"), 1.11, "one element: the gain")
near(R.attunementMix({fire = 1, ice = 1}, "fire"), (1.11 + 0.85) / 2, "two elements in equal parts")
near(R.attunementMix({fire = 1, ice = 1, energy = 1, earth = 1}, "fire"), (1.11 + 3 * 0.85) / 4, "four elements: a net loss")
check(R.attunementMix({fire = 1, ice = 1, energy = 1, earth = 1}, "fire") < 1, "a kit of four elements loses: the price is real")
check(R.attunementMix({fire = 1, physical = 1}, "fire") > 1, "fire and physical: the gain, no price on physical")

-- ------------------------------------------------------------------------------------------------ Open Wounds
local tick, ticks, tickMs = R.bleedOf(920)
eq(tick, 92, "40% of 920 over 4 ticks"); eq(ticks, 4, "ticks"); eq(tickMs, 1000, "tick ms")
eq(R.bleedOf(9), nil, "a hit too small to bleed"); eq(R.bleedOf(-920), 92, "the sign does not matter")
check(R.bleeds("melee", false, false), "bare fists bleed")
check(R.bleeds("melee", true, false), "a one-handed weapon bleeds")
check(not R.bleeds("melee", true, true), "a two-handed weapon does not (Open Veins is the Berserker's)")
check(not R.bleeds("ranged", false, false), "a ranged hit does not")
check(not R.bleeds("spell", false, false), "a spell hit does not")
near(R.openWoundsPrice(), 0.92, "the price")

-- ------------------------------------------------------------------------------------------------ the +40% rule
-- A specialised build is at most +40% over its class default in its specialty. A character holds 3 keystones, so the worst
-- legal stack is the keystone and two more of the median size of the flat damage gains of rounds 1 to 3 and the class sections
-- (Lone Mark and Convergence: +12%): named "keystone + Lone Mark + Convergence". Each keystone's net gain in its own specialty:
local partner = 1 + rule.partnerGain
-- the flat damage gains of the older keystones that the +12% stands for
local sk = dofile("data/scripts/chaos/section_keystones_config.lua")
near(sk.ksLoneMark.alone, partner, "the partner size is Lone Mark's gain")
near(sk.ksConvergence.bonus, partner, "and Convergence's")
local nets = {
	{"Momentum", R.momentumNet(above(1000, true)), "all hits at the fastest legal speed (level 1000)"},
	{"Momentum", R.momentumNet(above(100, true)), "all hits at the fastest legal speed (level 100)"},
	{"Attunement", R.attunementNet(), "a build of one element only"},
	{"Open Wounds", R.openWoundsNet(rule.attackIntervalMs), "one target in a long fight, a hit every " .. rule.attackIntervalMs .. " ms"},
}
local worst = 0
for _, n in ipairs(nets) do
	local stack = n[2] * partner * partner
	worst = math.max(worst, stack)
	check(stack <= 1 + rule.ownerCap + 1e-9, string.format("%s + Lone Mark + Convergence (%s): %.3f is at or below +40%%", n[1], n[3], stack))
	check(n[2] <= partner + 1e-9, string.format("%s is at or below the size of the median keystone (+12%%): %.3f", n[1], n[2]))
end
if os.getenv("ROUND4_PRINT") then
	for _, n in ipairs(nets) do print(string.format("%-12s net %.3f  stack %.3f  %s", n[1], n[2], n[2] * partner * partner, n[3])) end
end
-- a bleed that the next hit does not replace would pass the rule: the number the sustained gain stands on
near(R.openWoundsNet(2000), 0.92 * (1 + 0.40 * 0.5), "Open Wounds at 2 s between hits: half of each bleed pays")
near(R.openWoundsNet(333), 0.92 * (1 + 0.40 * 333 / 4000), "at the 3 attacks a second cap: a twelfth of it")
near(R.openWoundsNet(10000), 0.92 * 1.4, "a hit every 10 s: the whole bleed")
check(R.openWoundsNet(10000) > 1 + rule.ownerCap - 0.12 and R.openWoundsNet(10000) < 1.3, "even then the keystone alone is under +30%")
-- the keystones price themselves: a kit of four elements, the slowed or the standing runner, a two-handed weapon
check(R.attunementMix({fire = 1, ice = 1, energy = 1, earth = 1}, "fire") < R.attunementNet(), "the mixed kit is worse than the mono kit")

-- ------------------------------------------------------------------------------------------------ the data
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local Core = dofile("data/scripts/chaos/passivetree_core.lua") or ChaosPassiveTreeCore
local FLAGS = {[706] = "arMomentum", [707] = "arAttunement", [708] = "arOpenWounds"}
local PARENT = {[706] = 120, [707] = 219, [708] = 161}
for id, flag in pairs(FLAGS) do
	local node = tree.nodes[id]
	check(node ~= nil, "node " .. id .. " is in the tree")
	if node then
		eq(node.s[flag], 1, "node " .. id .. " carries " .. flag)
		eq(#node.n, 1, "node " .. id .. " is a leaf with one link")
		eq(node.n[1], PARENT[id], "node " .. id .. " hangs on " .. PARENT[id])
		local linked = false
		for _, o in ipairs(tree.nodes[PARENT[id]].n) do linked = linked or o == id end
		check(linked, "the parent " .. PARENT[id] .. " links back")
		eq(Core.keystoneKind(node), "archetype", "node " .. id .. " is an archetype keystone for the cap")
		local list = cfg.classes[flag]
		local count = 0
		for _ in pairs(node.c) do count = count + 1 end
		eq(count, #list, "node " .. id .. " class count")
		for _, k in ipairs(list) do eq(node.c[k], true, "node " .. id .. " may be taken by " .. k) end
	end
end
-- the flags and their bits: after the 24 of the rounds 1 to 3, in this order
eq(#A.FLAGS, 27, "27 flags")
eq(A.FLAGS[25], "arMomentum", "bit 25"); eq(A.FLAGS[26], "arAttunement", "bit 26"); eq(A.FLAGS[27], "arOpenWounds", "bit 27")
local all = {}
for _, f in ipairs(A.FLAGS) do all[f] = true end
local mask = A.mask(all)
check(mask < 2 ^ 31, "the flag storage fits 31 bits: " .. mask)
for _, f in ipairs(A.FLAGS) do check(A.maskHas(mask, f), "mask has " .. f) end
local one = A.flagsOfMask(A.mask({arAttunement = true}))
check(one.arAttunement and not one.arMomentum and not one.arOpenWounds, "a mask of one round 4 flag")
for flag, list in pairs(cfg.classes) do
	check(A.classMay(flag, list[1]), flag .. ": its first class may take it")
	check(not A.classMay(flag, "warrior") and not A.classMay(flag, "juggernaut"), flag .. ": the Warrior line may not take it")
end
check(A.classMay("arMomentum", "thief") and A.classMay("arMomentum", "ranger") and A.classMay("arMomentum", "monk")
	and not A.classMay("arMomentum", "mystic") and not A.classMay("arMomentum", "templar"), "Momentum: the Ranger, Thief and Monk lines")
check(A.classMay("arAttunement", "elementalist") and A.classMay("arAttunement", "lich") and A.classMay("arAttunement", "sentinel")
	and not A.classMay("arAttunement", "monk"), "Attunement: the Mystic, Necromancer and Templar lines")
check(A.classMay("arOpenWounds", "monk") and A.classMay("arOpenWounds", "templar") and not A.classMay("arOpenWounds", "berserker"),
	"Open Wounds: the Monk and Templar lines, not the Berserker's")
-- the converted leaves of the rounds 1 to 3 are the same 24, nothing of them moved
eq(#ChaosArchetypesConfig.nodes, 24, "the converted leaves: 24, as before")
local c = ChaosArchetypesConfig
check(c.arMomentum == cfg.arMomentum and c.arAttunement == cfg.arAttunement and c.arOpenWounds == cfg.arOpenWounds,
	"archetypes_config.lua holds the same number tables")

-- the combat log labels and the client names
local labels = dofile("data/scripts/chaos/keystone_labels_config.lua")
for _, f in pairs(FLAGS) do check(labels.flags[f] ~= nil, f .. " has a combat log label") end
eq(labels.flags.arMomentum.name, "Momentum", "label name"); eq(labels.flags.arAttunement.name, "Attunement", "label name")
eq(labels.flags.arOpenWounds.name, "Open Wounds", "label name")
local trends = read("data/scripts/chaos/build_trends_config.lua")
for _, name in ipairs({"Momentum", "Attunement", "Open Wounds"}) do check(trends:find('"' .. name .. '"', 1, true) ~= nil, "the trends list names " .. name) end
local themes = dofile("data/scripts/chaos/passive_builds_config.lua").keystoneThemes
check(themes.arMomentum and themes.arAttunement and themes.arOpenWounds, "each round 4 keystone is in a Focus theme")

-- the client: the tooltip states the config's numbers, classes agree, the icons exist
local fh = io.open("../client/overlay/modules/game_passivetree/treedata/nodes.lua")
if fh then
	fh:close()
	dofile("../client/overlay/modules/game_passivetree/treedata/nodes.lua")
	dofile("../client/overlay/modules/game_passivetree/treedata/groups.lua")
	dofile("../client/overlay/modules/game_passivetree/treedata/icons.lua")
	local nodes, groups, icons = getTreeNodes(), getTreeGroups(), getTreeIcons()
	local function pct(v) return string.format("%d%%", math.floor(v * 100 + 0.5)) end
	local function text(id) return table.concat(nodes[id].stats, " ") end
	local function has(id, s) check(text(id):find(s, 1, true) ~= nil, "node " .. id .. " tooltip says '" .. s .. "': " .. text(id)) end
	has(706, pct(m.bonusPer / 100) .. " more"); has(706, "every " .. m.per .. "% of movement speed above your base")
	has(706, "up to " .. m.cap .. "% more"); has(706, "the larger counts"); has(706, "You take " .. pct(m.taken - 1) .. " more damage")
	local a = cfg.arAttunement
	has(707, "deals " .. pct(a.locked - 1) .. " more"); has(707, "deal " .. pct(1 - a.others) .. " less")
	has(707, "fire, ice, energy, earth, death, holy")
	local o = cfg.arOpenWounds
	has(708, "bleed for " .. pct(o.share) .. " of the hit over " .. math.floor(o.ticks * o.tickMs / 1000) .. " s")
	has(708, "deal " .. pct(1 - o.price) .. " less"); has(708, "fists or a one-handed weapon")
	for id, flag in pairs(FLAGS) do
		local cn = nodes[id]
		check(cn.isKeystone and cn.isDivine, id .. " is drawn as a keystone")
		eq(cn.customStats[flag], 1, id .. " client flag")
		eq(cn.inputs[1], PARENT[id], id .. " client parent")
		local parentOut = false
		for _, o2 in ipairs(nodes[PARENT[id]].out) do parentOut = parentOut or o2 == id end
		check(parentOut, id .. " is drawn from its parent (an `out` entry)")
		eq(#cn.classes, #cfg.classes[flag], id .. " client classes")
		for i, k in ipairs(cn.classes) do eq(k, cfg.classes[flag][i], id .. " class " .. i) end
		check(icons[cn.icon] ~= nil, id .. " icon " .. tostring(cn.icon) .. " exists in icons.lua")
		check(groups[cn.group] ~= nil and #groups[cn.group].nodes == 0, id .. " has a group of its own")
	end
	eq(nodes[706].group, 109, "group 109"); eq(nodes[707].group, 110, "group 110"); eq(nodes[708].group, 111, "group 111")
	-- the client names every flag
	local src = io.open("../client/overlay/modules/game_passivetree/passivetree.lua"):read("*a")
	for _, f in pairs(FLAGS) do check(src:find(f .. " = \"", 1, true) ~= nil, "client name of " .. f) end
	local keystones = 0
	for _, cn in pairs(nodes) do if cn.isKeystone then keystones = keystones + 1 end end
	eq(keystones, 47, "the client marks 47 keystones")
else
	print("(client tree not found: tooltip checks skipped)")
end

-- the cap: Momentum, Attunement and Open Wounds are keystones like any other, three at most
local ids = {706, 707, 708}
eq(Core.countKeystones(tree, ids), 3, "three round 4 keystones count three")
local okAll = Core.checkKeystones(tree, ids)
eq(okAll, true, "three are fine")
local refused = Core.checkKeystones(tree, {706, 707, 708, 77})
eq(refused, nil, "a fourth is refused")

print(string.format("round4_keystones_test: %d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
