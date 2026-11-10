-- Run from the server/ folder: luajit tests/spell_masteries_test.lua (and lua5.3; CI runs both)
-- Spell modifier masteries (O451): the choices of data/lib/chaos_spell_masteries_config.lua against the passive tree data
-- (nodes, effect positions, old effects unchanged), the free support (tier, reduced strength, never above a Common rune, no
-- price so reduced), the merge rules with real runes (the stronger one counts, never a sum, one brand), the kinds the supports
-- fit, the tree stat through the core, the listener, and the client's names. The gains of the choices are
-- server/tools/spell_mastery_model.py (spell_mastery_model_test.py).

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "expected true", 2)
	end
end

dofile("data/lib/chaos_supports.lua")
local S = ChaosSupports
local M = S.mastery
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local Core = dofile("data/scripts/chaos/passivetree_core.lua")
local ptCfg = dofile("data/scripts/chaos/passivetree_config.lua")

-- ---------------------------------------------------------------- the config
eq(M.tier, 1, "the lowest tier: a Common rune")
eq(M.strength, 75, "reduced to 75%")
ok(M.strength < 100, "no support has a price, so the effect is reduced")
eq(#M.choices, 20, "20 choices")
local byNode, lines = {}, {}
for i, c in ipairs(M.choices) do
	eq(c.id, i, "ids are 1.. in order, never reused")
	ok(S.byKey[c.support], c.name .. ": a support that exists")
	ok(M.reduce[c.support], c.name .. ": the support has a reduced field")
	byNode[c.node] = byNode[c.node] or {}
	table.insert(byNode[c.node], c)
	lines[c.line] = (lines[c.line] or 0) + 1
end
local nodeLine = {[665] = "thief", [666] = "necromancer", [667] = "monk", [668] = "templar", [703] = "warrior", [704] = "ranger",
	[705] = "mystic"}
local oldCount = {[665] = 4, [666] = 3, [667] = 4, [668] = 3, [703] = 4, [704] = 4, [705] = 4}
local nodes = 0
for node, line in pairs(nodeLine) do
	nodes = nodes + 1
	local rows = byNode[node]
	ok(rows and #rows >= 2 and #rows <= 3, line .. ": two or three spell modifier choices")
	eq(lines[line], #rows, line .. ": every row of the line is on its node")
	ok(tree.nodes[node] and Core.isMastery(tree.nodes[node]), node .. " is a mastery node")
	eq(#tree.nodes[node].m, oldCount[node] + #rows, node .. ": the old effects stay, the choices are added")
	for k, c in ipairs(rows) do
		eq(c.line, line, c.name .. ": the line of the node")
		eq(c.effect, oldCount[node] + k, c.name .. ": appended after the old effects, in order")
		local effect = tree.nodes[node].m[c.effect]
		local n = 0
		for stat, value in pairs(effect) do
			n = n + 1
			eq(stat, "spellMod", c.name .. ": the one stat")
			eq(value, c.id, c.name .. ": the id")
		end
		eq(n, 1, c.name .. ": nothing else")
	end
end
eq(nodes, 7, "seven mastery nodes, seven lines")
ok(#tree.nodes[665].m <= ptCfg.maxMasteryChoices, "within the node limit")
eq(ptCfg.maxMasteryChoices, 7, "the effects per node: 4 before O451, 7 now")
-- a character holds one choice per mastery node: a spell modifier is one effect of a node, whatever the id
for _, c in ipairs(M.choices) do
	local stats = Core.nodeStats(tree.nodes[c.node], nil, c.effect)
	eq(stats.spellMod, c.id, c.name .. ": the chosen effect's stat")
	eq(Core.nodeStats(tree.nodes[c.node], nil, nil), nil, "no effect without a choice")
end
-- the old effects, pinned: an existing choice keeps its id and meaning (the saved trees and the build codes read the position)
local pinned = {
	[665] = {"criticalHitAmount=5,criticalHitChance=2", "dexterity=3,speed=200", "absorbPhysical=2,vitality=4",
		"incrementEarth=6,incrementPhysical=3"},
	[666] = {"incrementDeath=6,magicSkill=1", "absorbPhysical=3,vitality=3", "absorbDeath=2,spirit=5"},
	[667] = {"incrementPhysical=6,strength=2", "criticalHitAmount=4,criticalHitChance=2", "incrementHealth=6,spirit=3",
		"absorbPhysical=2,vitality=4"},
	[668] = {"incrementHoly=6,strength=2", "absorbAllElements=1,absorbPhysical=2,shieldingSkill=2", "incrementHealth=6,vitality=3"},
	[703] = {"incrementPhysical=6,strength=1", "absorbPhysical=2,vitality=4", "criticalHitAmount=4,criticalHitChance=2",
		"absorbPhysical=2,shieldingSkill=2"},
	[704] = {"criticalHitAmount=5,criticalHitChance=2", "dexterity=3,speed=200", "absorbPhysical=2,vitality=4",
		"dexterity=2,incrementPhysical=5"},
	[705] = {"incrementFire=6,magicSkill=1", "incrementIce=6,magicSkill=1", "incrementEnergy=6,magicSkill=1",
		"incrementHealth=5,spirit=2"}
}
for node, list in pairs(pinned) do
	for i, text in ipairs(list) do
		local keys = {}
		for stat, value in pairs(tree.nodes[node].m[i]) do
			keys[#keys + 1] = stat .. "=" .. value
		end
		table.sort(keys)
		eq(table.concat(keys, ","), text, node .. " effect " .. i .. " is unchanged")
	end
end

-- ---------------------------------------------------------------- the free support: never above a Common rune
local expected = {fork = {1, 26}, breadth = {1, 26}, shatter = {15}, quickening = {4}, hex = {2}, echo = {11, 50}, dawnbrand = {15},
	gravebrand = {15}, stormbrand = {15}}
for _, c in ipairs(M.choices) do
	local free = S.freeEffect(c.support)
	local rune = S.byKey[c.support]
	ok(free and free.free, c.name .. ": a free effect")
	eq(free.level, 1, c.name .. ": tier 1")
	eq(free.key, c.support, c.name .. ": the support")
	ok(free.value <= rune.values[1], c.name .. ": value never above the Common rune")
	ok(free.value2 == nil or free.value2 <= rune.values2[1], c.name .. ": value2 never above the Common rune")
	-- a price would make the effect whole; none of these supports has one, so a number is strictly below the rune's
	local cut = false
	for _, f in ipairs(M.reduce[c.support]) do
		local v, r = free[f], f == "value" and rune.values[1] or rune.values2[1]
		ok(v >= 1 and v < r, c.name .. ": " .. f .. " is reduced")
		cut = true
	end
	ok(cut, c.name .. ": reduced")
	local e = expected[c.support]
	eq(free.value, e[1], c.name .. ": value")
	if e[2] then
		eq(free.value2, e[2], c.name .. ": value2")
	end
end
ok(S.freeEffect("hex").value <= 3 and S.freeEffect("quickening").value <= 6, "below the caps of the supports")
eq(S.freeEffect("keenedge"), nil, "a support the config does not reduce gives nothing")
eq(S.freeEffect("nope"), nil, "an unknown support gives nothing")
-- the element of a brand stays
eq(S.freeEffect("dawnbrand").element, "holy", "dawnbrand: holy"); eq(S.freeEffect("gravebrand").element, "death", "gravebrand: death")

-- the kinds: Fork, Shatter fit single only, Breadth area only; a spell the override does not name must take a support that fits
-- both damage kinds (its kind comes from the spellbook parse, the strikes and spells of the Chaos kit are damage)
for _, c in ipairs(M.choices) do
	local t = S.byKey[c.support]
	local kind = S.config.kindOverride[c.spell]
	if kind then
		ok(t.fitsSet[kind], c.name .. ": the support fits " .. kind)
	else
		ok(t.fitsSet.single and t.fitsSet.area, c.name .. ": a spell of unknown kind needs a support for both damage kinds")
	end
	for _, id in ipairs(S.config.none) do
		ok(id ~= c.spell, c.name .. ": the spell takes supports")
	end
end

-- ---------------------------------------------------------------- the merge rules (pure)
local function player(storageValue, level)
	local st = {[M.storage] = storageValue}
	return {getStorageValue = function(_, k) return st[k] or -1 end, setStorageValue = function(_, k, v) st[k] = v end,
		getLevel = function() return level or 1000 end, st = st}
end
eq(S.masteryChoice(player(-1)), nil, "none")
eq(S.masteryChoice(player(0)), nil, "zero is none")
eq(S.masteryChoice(player(99)), nil, "an unknown id is none")
eq(S.masteryChoice(player(1)).name, "Gore Fork", "choice 1")
eq(S.masteryChoice({}), nil, "a player without storage calls is none")
-- the spell id is the only one that gets it
local p = player(1)
local fx = S.spellEffects(p, 2, 130)
ok(fx.fork and fx.fork.free and fx.fork.value == 1 and fx.fork.value2 == 26, "Gorehook: Fork 1 / 26%")
eq(next(S.spellEffects(p, 225, 260)), nil, "Colossus Fall: nothing for choice 1")
eq(next(S.spellEffects(player(2), 2, 130)), nil, "Gorehook: nothing for choice 2 (Colossus Fall)")
eq(next(S.spellEffects(player(-1), 2, 130)), nil, "Gorehook without the choice: nothing")
-- it takes no rune slot: the sockets of the spell are untouched
local sock = S.read(p, 2)
eq(sock.runes[1] + sock.runes[2] + sock.runes[3], 0, "no rune stored")
eq(S.socketCount(1000, 130, false), 2, "the socket count is the rune rules'")
-- a real rune of the same support: the stronger one counts, never a sum
local function withRunes(choiceId, spellId, runes, level)
	local pl = player(choiceId, level)
	for i, id in ipairs(runes) do
		pl.st[S.storageKey(spellId, i)] = id
	end
	return pl
end
local function fork(l) return S.runeId(S.byKey.fork.index, l) end
local function quick(l) return S.runeId(S.byKey.quickening.index, l) end
fx = S.spellEffects(withRunes(1, 2, {fork(1)}), 2, 130)
eq(fx.fork.value2, 35, "real Common Fork 35% over the free 26%"); eq(fx.fork.value, 1, "not 2 enemies"); ok(not fx.fork.free, "the rune")
fx = S.spellEffects(withRunes(1, 2, {fork(5)}), 2, 130)
eq(fx.fork.value, 3, "real Mythic Fork: 3 enemies"); eq(fx.fork.value2, 55, "55%"); ok(not fx.fork.free, "the rune stays")
fx = S.spellEffects(withRunes(1, 2, {fork(1), fork(5)}), 2, 130)
ok(fx.fork.value <= 4, "two real forks follow the old sum rule, the free one does not join")
-- Quickening: free 4% on Quick Heel (Whirling Heel, choice 17); a real Common rune 6%: the rune; never 10%
fx = S.spellEffects(player(17), 65, 50)
eq(fx.quickening.value, 4, "Quick Heel: -4% cooldown")
fx = S.spellEffects(withRunes(17, 65, {quick(1)}), 65, 50)
eq(fx.quickening.value, 6, "a real Common Quickening 6%, not 10%")
fx = S.spellEffects(withRunes(17, 65, {quick(5), quick(4)}), 65, 50)
ok(fx.quickening.value <= S.config.caps.quickening, "under the cap of the support")
-- Echo: free 11% on Echoing Slam (Colossus Fall, choice 2); a real Common Echo is 15%
fx = S.spellEffects(player(2), 225, 260)
eq(fx.echo.value, 11, "Echoing Slam: 11% chance"); eq(fx.echo.value2, 50, "the second strike stays 50%")
fx = S.spellEffects(withRunes(2, 225, {S.runeId(S.byKey.echo.index, 1)}), 225, 260)
eq(fx.echo.value, 15, "a real Common Echo 15%, not 26%"); ok(not fx.echo.free, "the rune")
-- a brand: one brand per spell; the free one never joins a real brand of another element, and never a second one
local function rune(key, l) return S.runeId(S.byKey[key].index, l) end
fx = S.spellEffects(withRunes(20, 128, {rune("emberbrand", 1)}), 128, 160)
ok(fx.emberbrand and not fx.dawnbrand, "a real Emberbrand: the free Dawnbrand does not join it")
fx = S.spellEffects(withRunes(20, 128, {rune("dawnbrand", 1)}), 128, 160)
eq(fx.dawnbrand.value, 20, "the real Common Dawnbrand 20% over the free 15%")
fx = S.spellEffects(withRunes(20, 128, {rune("keenedge", 1)}), 128, 160)
ok(fx.dawnbrand and fx.dawnbrand.free and fx.keenedge, "another support: both")
-- a spell the character cannot socket yet (level below the spell) is no concern: the free effect is the same effect table
eq(S.effects({}, 3).fork, nil, "S.effects itself knows nothing of the mastery")

-- ---------------------------------------------------------------- the listener
ChaosPassiveTree = nil
Chaos = Chaos or {}
dofile("data/scripts/chaos/spell_masteries.lua")
local L = ChaosSpellMasteries
eq(L.idOf({}), -1, "no stat: none"); eq(L.idOf({spellMod = 0}), -1, "zero"); eq(L.idOf({spellMod = 21}), -1, "id 21 does not exist")
eq(L.idOf({spellMod = 20}), 20, "the last id"); eq(L.idOf(nil), -1, "no table")
eq(#ChaosPassiveTree.listeners, 1, "one listener of the tree")
local refreshed = 0
local realRefresh = S.refreshActive
S.refreshActive = function() refreshed = refreshed + 1 end
local pl = player(-1)
eq(L.apply(pl, {spellMod = 3}), 3, "applied"); eq(pl.st[M.storage], 3, "stored"); eq(refreshed, 1, "the supports' view refreshed")
L.apply(pl, {spellMod = 3})
eq(refreshed, 2, "a held choice refreshes at every apply (a level up or a login)")
L.apply(pl, {})
eq(pl.st[M.storage], -1, "dropped to -1"); eq(refreshed, 3, "refreshed after the change")
L.apply(pl, {})
eq(refreshed, 3, "nothing held, nothing changed: no work")
ChaosPassiveTree.listeners[1](pl, {spellMod = 5})
eq(pl.st[M.storage], 5, "the tree listener writes it")
S.refreshActive = realRefresh

-- ---------------------------------------------------------------- the client's names and texts
local f = io.open("../client/overlay/modules/game_passivetree/treedata/nodes.lua", "r")
if f then
	f:close()
	function getTreeNodes() end
	dofile("../client/overlay/modules/game_passivetree/treedata/nodes.lua")
	local cnodes = getTreeNodes()
	for _, c in ipairs(M.choices) do
		local effect = cnodes[c.node].masteries[c.effect]
		eq(effect.name, c.name, c.name .. ": the client's name")
		eq(effect.customStats.spellMod, c.id, c.name .. ": the client's stat")
	end
else
	print("note: client data not found, the client's names were not compared")
end

print(string.format("spell_masteries_test: %d checks OK", checks))
