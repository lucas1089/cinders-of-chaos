-- class_tree.lua: the class part of the passive tree (docs/CLASSES.md "Phase 2b"), ChaosClassTree.
--
-- The tree (passivetree_data.lua, generated from the client's treedata/nodes.lua) has, next to the shared nodes:
--   * per-class keystone variants on nodes 621 (Wrath) and 624 (Resolve) for the Warrior, Ranger and Mystic lines
--     (ChaosClasses.keystoneKey: the base classes keep the old vocation's pair, the Juggernaut, Berserker, Deadeye and
--     Beastmaster swap one keystone for one of their own), and since 2026-10-12 the Iron Sage's Overgrowth on 621 and
--     the Sentinel's Thorns on 624 (the old druid pair; keyed by the class key);
--   * a class section for the Thief, Necromancer, Monk and Templar lines (nodes 625-664): a start node of the line,
--     three line nodes and two ascended paths of three nodes, each ending in the ascended class's keystone. The start
--     node is not a node of the server's data: its edges are the root's (node 1), so the section grows from the start
--     like any other branch and every connectivity check (save, refund, build codes) works unchanged.
--   * a second keystone for each of those four lines, for the base class and both ascended classes, on main tree
--     leaves (383 Blackblood Creed, 369 Covenant of the Grave, 390 Scarred Discipline, 376 Penitent's Wrath).
--   Nodes a class may hold are marked in the data (`c` = {[class key] = true}); nodes without `c` are for everyone.
--
-- What the class nodes do: their stats are flags (`ks...` keystones, `ct...` class notables) or ordinary tree stats.
-- The numbers of the flags live here (fx below); the combat scripts read them through ChaosClassTree.value(player, key).
-- The flags are kept in one player storage (a bit per key), written by passivetree.lua after every apply, because the
-- spells run in another Lua state than the scripts and the storage is what both see.
--
-- Pure apart from has()/value()/write(), which only use getStorageValue / setStorageValue. Loaded by the scripts
-- (passivetree.lua, the class combat scripts) and the spells (dofile). Tests: server/tests/class_tree_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosClassTree = ChaosClassTree or {}
local M = ChaosClassTree

-- the player storage of the flags (Chaos.storage.passiveClassFx)
M.storage = 7100022

-- bit order of the flags: append only (a stored value is re-written at every login anyway)
M.keys = {
	-- keystones of the old lines' ascended classes (nodes 621 / 624 variants)
	"ksImmovable", "ksUndyingRage", "ksHuntersFocus", "ksPackAlpha",
	-- keystones of the class sections
	"ksLivingShadow", "ksWayOfTheBlade", "ksHoardedSouls", "ksBoneColossus", "ksHundredHands", "ksFlowingMercy",
	"ksDivineVerdict", "ksBastion",
	-- class notables
	"ctTwinFangs", "ctFleetShadow", "ctIronParry", "ctSpreadingBlight", "ctLingeringRot", "ctLegion", "ctBannerBearer",
	"ctNerveStrike", "ctDeepMantra", "ctBurningZeal", "ctSanctuary",
	-- the second keystone of the Thief, Necromancer, Monk and Templar lines (any class of the line; main tree nodes 383,
	-- 369, 390, 376, converted from mythic leaves in 2026-10)
	"ksBlackbloodCreed", "ksGraveCovenant", "ksScarredDiscipline", "ksPenitentWrath"
}
M.bit = {}
for i, key in ipairs(M.keys) do
	M.bit[key] = i - 1
end

-- the numbers (the client tooltips in treedata/nodes.lua repeat them; class_tree_test.lua checks that)
M.fx = {
	-- Juggernaut (621): damage taken -reduction, -lowReduction while below lowHealth of the maximum health
	ksImmovable = {reduction = 0.08, lowReduction = 0.16, lowHealth = 0.5},
	-- Berserker (624): melee weapon hits heal heal x the damage dealt, lowHeal below lowHealth
	ksUndyingRage = {heal = 0.04, lowHeal = 0.08, lowHealth = 0.5},
	-- Deadeye (621): distance weapon hits on the same target +perHit each, at most maxBonus; another target resets
	ksHuntersFocus = {perHit = 0.04, maxBonus = 0.20, resetMs = 6000},
	-- Beastmaster (624): companion bites and Feral Command x (1 + bonus); companions take -reduction damage
	ksPackAlpha = {bonus = 0.35, reduction = 0.20},
	-- Ninja: a dodge or leaving Shadow Veil opens a window of durationMs: weapon hits and strikes +bonus
	ksLivingShadow = {bonus = 0.25, durationMs = 4000},
	-- Samurai: Counter Stance parries every melee hit while it lasts (not only the first); a hit taken keeps keepShare of
	-- the Bushido stacks (instead of none)
	ksWayOfTheBlade = {keepShare = 0.5},
	-- Lich: Soul Hoard +perFreeSlot per empty shade slot (instead of the base 25%), and +withShade while the shade is out
	ksHoardedSouls = {perFreeSlot = 0.40, withShade = 0.15},
	-- Bone Lord: the Bone Golem hits x (1 + hit) and has x (1 + health) health
	ksBoneColossus = {hit = 0.60, health = 0.50},
	-- Shadowfist: a focus crit adds a chi, at most one every icdMs
	ksHundredHands = {chi = 1, icdMs = 1000},
	-- Iron Sage (the line's healer): Kindled Breath also heals the next most hurt party member for `share` of it
	ksFlowingMercy = {share = 0.40},
	-- Inquisitor: a Radiant Strike has chance to judge its target (Judgement's full effect and duration)
	ksDivineVerdict = {chance = 0.20},
	-- Sentinel: aura +reduction and +radius; Aegis of Faith also covers the party members under the aura at partyShare
	ksBastion = {reduction = 0.04, radius = 1, partyShare = 0.5},
	-- Ninja notables
	ctTwinFangs = {offhandShare = 0.15}, -- the off-hand strike: 50% -> 65% of the hit
	ctFleetShadow = {evasion = 0.04}, -- evasion +4%
	-- Samurai notable: Counter Stance answers x (1 + bonus), the stance window +windowMs
	ctIronParry = {bonus = 0.5, windowMs = 1000},
	-- Lich notables
	ctSpreadingBlight = {spread = 1}, -- Withering Curse spreads to one more enemy
	ctLingeringRot = {bonus = 0.25}, -- Soul Rot +25%
	-- Bone Lord notables
	ctLegion = {skeletons = 1}, -- one more skeleton
	ctBannerBearer = {damage = 0.15}, -- Banner of Bones: minions +15% damage more (30% -> 45%)
	-- Shadowfist notable: Pressure Points +perStack per stack more (5% -> 6%)
	ctNerveStrike = {perStack = 0.01},
	-- Iron Sage notable: Mantra of Stone takes reduction off instead of 8%
	ctDeepMantra = {reduction = 0.11},
	-- Inquisitor notable: Radiant Strikes +share of the hit (25% -> 30%)
	ctBurningZeal = {share = 0.05},
	-- Sentinel notable: the aura's regeneration +regen of the maximum health per second (0.4% -> 0.5%)
	ctSanctuary = {regen = 0.001},
	-- The line keystones (one per line, for the base class and both ascended classes; each has a price):
	-- Thief line (383): every weapon hit poisons as Poison Blades does (buff or not), the poison x (1 + poisonBonus);
	-- evasion x evasionScale. poisonBonus was 0.60 until 2026-10-12: measured, the gain at level 1000 was twice the
	-- computed one and put the Ninja level with the Deadeye (server/data/spells/README.md "Line keystones, masteries
	-- and weapons measured in game")
	ksBlackbloodCreed = {poisonBonus = 0.30, evasionScale = 0.5},
	-- Necromancer line (369): minion hits x (1 + minionHit), minion health x (1 + minionHealth); the own spells
	-- x (1 - ownSpell) (necro_lib.lua ChaosNecro.values; the wand's auto attack and the heals are not spells of the line).
	-- classMinionHit: minionHit of a class instead of the line's (the Bone Lord's damage is 60-65% minions: +50% put it
	-- ahead of the Deadeye on one target, measured 2026-10-12)
	ksGraveCovenant = {minionHit = 0.50, minionHealth = 0.50, ownSpell = 0.25, classMinionHit = {bonelord = 0.20}},
	-- Monk line (390): no evasion; a hit taken from a creature gives `chi` (at most one every icdMs); while holding
	-- minChi or more, damage taken x (1 - reduction)
	ksScarredDiscipline = {chi = 1, icdMs = 2000, minChi = 3, reduction = 0.10},
	-- Templar line (376): a melee / ranged hit taken is answered with a holy strike on the attacker for share x the
	-- damage taken + perMagicLevel x magic level, at most one every icdMs; the own defence aura's reduction x auraScale
	ksPenitentWrath = {share = 0.40, perMagicLevel = 4, icdMs = 500, auraScale = 0.5},
}

-- The lines that were tuned without a tree (their kits matched the other classes' numbers with tree points): every
-- damage they deal is x the factor of their level (linear between the points, the end values outside), applied with the
-- tree's damage bonuses (passivetree_effects.lua). It replaces the level factors that stood in for the tree (the Thief
-- line's spellLevelScale, the Monk's, the Templar's, necro_config.lua levelScale). Keyed by class key, else by the line's
-- key. Measured: server/data/spells/README.md "Classes with the passive trees". Classes without an entry: 1.
M.classDamage = {
	thief = {{300, 0.48}, {1000, 0.53}},
	ninja = {{300, 0.45}, {1000, 0.57}},
	samurai = {{300, 0.30}, {1000, 0.37}}, -- the duelist off-tank: damage at the Juggernaut's
	-- the Necromancer and the Bone Lord at level 300: 1.0 / 0.75 until 2026-10-12; a build that takes the path to Covenant
	-- of the Grave (physical nodes the C4 build skipped) put both level with or ahead of the Deadeye (README "Line keystones,
	-- masteries and weapons measured in game")
	necromancer = {{300, 0.93}, {1000, 0.64}},
	lich = {{300, 0.50}, {1000, 0.57}},
	bonelord = {{300, 0.63}, {1000, 0.61}},
	monk = {{300, 0.63}, {1000, 0.75}},
	shadowfist = {{300, 0.49}, {1000, 0.69}},
	ironsage = {{300, 0.61}, {1000, 0.75}}, -- the second healer: damage below the Warrior's
	templar = {{300, 0.78}, {1000, 0.60}},
	inquisitor = {{300, 0.65}, {1000, 0.58}},
	sentinel = {{300, 0.73}, {1000, 0.60}},
	-- the leaders keep a lead of 8-10% (the owner, 2026-10): the Berserker's area damage passed the Elementalist's at
	-- level 300 with tree builds (3441 against 3349), the Beastmaster's came within 4% at level 1000
	berserker = {{300, 0.78}, {1000, 1.0}},
	beastmaster = {{300, 1.0}, {1000, 0.95}},
	ranger = {{300, 1.0}, {1000, 0.95}},
}
function M.damageFactor(classKey, lineKey, level)
	local pts = (classKey and M.classDamage[classKey]) or (lineKey and M.classDamage[lineKey])
	if not pts then
		return 1
	end
	level = level or 0
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- ------------------------------------------------------------------------------------------------ classes and nodes
-- a node `node` of the data ({n, s, v, c}) may be held by class `classKey` (ChaosClasses.classKey)
function M.allowed(node, classKey)
	if not node then
		return false
	end
	if not node.c then
		return true
	end
	return classKey ~= nil and node.c[classKey] == true
end

-- Keep only the nodes of `ids` this class may hold and that still connect to the root through each other.
-- Returns kept (list, in the order of ids), removed (list of {id, why = "unknown" | "class" | "disconnected"}).
function M.sanitize(tree, ids, classKey)
	local removed, set, order = {}, {}, {}
	for _, raw in ipairs(ids or {}) do
		local id = tonumber(raw)
		local node = id and tree.nodes[id]
		if id and id ~= tree.root and not set[id] then
			if not node then
				removed[#removed + 1] = {id = id, why = "unknown"}
			elseif not M.allowed(node, classKey) then
				removed[#removed + 1] = {id = id, why = "class"}
			else
				set[id] = true
				order[#order + 1] = id
			end
		end
	end
	local reached, queue, head = {[tree.root] = true}, {tree.root}, 1
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		for _, neighbour in ipairs(tree.nodes[current].n or {}) do
			if set[neighbour] and not reached[neighbour] then
				reached[neighbour] = true
				queue[#queue + 1] = neighbour
			end
		end
	end
	local kept = {}
	for _, id in ipairs(order) do
		if reached[id] then
			kept[#kept + 1] = id
		else
			removed[#removed + 1] = {id = id, why = "disconnected"}
		end
	end
	return kept, removed
end

-- ------------------------------------------------------------------------------------------------ the flags
local function hasBit(value, b)
	return math.floor(value / 2 ^ b) % 2 == 1
end

-- the storage value for a bonus table (summed node stats): one bit per flag key present
function M.mask(bonuses)
	local v = 0
	for key, b in pairs(M.bit) do
		if bonuses and (bonuses[key] or 0) > 0 then
			v = v + 2 ^ b
		end
	end
	return math.floor(v)
end

function M.maskHas(mask, key)
	local b = M.bit[key]
	return b ~= nil and (mask or 0) > 0 and hasBit(mask, b)
end

function M.write(player, bonuses)
	local v = M.mask(bonuses)
	if player:getStorageValue(M.storage) ~= v then
		player:setStorageValue(M.storage, v)
	end
	return v
end

-- the player holds the node with this flag
function M.has(player, key)
	if not player or not player.getStorageValue then
		return false
	end
	return M.maskHas(player:getStorageValue(M.storage), key)
end

-- the number `field` of the flag `key` when the player holds it, else `default` (0 when not given; an explicit nil
-- stays nil)
function M.value(player, key, field, ...)
	if M.has(player, key) then
		return M.fx[key][field]
	end
	if select("#", ...) > 0 then
		return (...)
	end
	return 0
end

return M
