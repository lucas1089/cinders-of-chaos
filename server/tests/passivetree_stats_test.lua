-- Run from the server/ folder: luajit tests/passivetree_stats_test.lua (and lua5.3; CI runs both). Mock engine API.
-- The stat help of the passive tree (passivetree_stats_config.lua, passivetree_stats_core.lua, passivetree_stats.lua):
--   * every stat key any node can give has a description and a name (English) and a pt-BR for both: a new stat cannot be
--     added to the tree without them; the texts carry the numbers the effects use (passivetree_effects.lua);
--   * every class has Primary / Secondary / irrelevant lists made of known stats, primary first, no stat in two of them;
--   * the statInfo message: the stats of the class, 10 a part, tags, the header; the opcode handler sends it.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

-- the effects file (for its numbers), loaded against the same mock as passivetree_effects_test.lua
Chaos = {storage = {}, tables = {}, passive = {}}
function Chaos.load() end
ChaosOpcodes = {}
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_last", {k, v}) end})
rawset(EventCallback, "register", function() end)
function CreatureEvent() local o = {}; function o:register() end; return o end
function Condition() return {setTicks = function() end, setParameter = function() end} end
function addEvent() end
dofile("data/scripts/chaos/passivetree_effects.lua")
local E = ChaosPassiveEffectsConfig
local mult = ChaosPassiveStatMultiplier
Chaos, ChaosOpcodes, ChaosPassiveTree = nil, nil, nil
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/passivetree_stats_config.lua")
dofile("data/scripts/chaos/passivetree_stats_core.lua")
local cfg, C = ChaosPassiveStatsConfig, PassiveStatsCore
-- a tiny encoder: only the size matters
local function encode(v)
	if type(v) == "table" then
		local out = {}
		for k, x in pairs(v) do out[#out + 1] = tostring(k) .. ":" .. encode(x) end
		return "{" .. table.concat(out, ",") .. "}"
	end
	return tostring(v)
end
local tree = dofile("data/scripts/chaos/passivetree_data.lua")
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]

-- ------------------------------------------------------------------------------------------------ every stat
local all = {}
for _, id in ipairs((function() local t = {} for k in pairs(tree.nodes) do t[#t + 1] = k end table.sort(t) return t end)()) do
	for stat in pairs(C.nodeStats(tree.nodes[id])) do
		all[stat] = true
	end
end
local count = 0
for stat in pairs(all) do
	count = count + 1
	local s = cfg.stats[stat]
	check(s and s[1] ~= "" and s[2] ~= "", "stat " .. stat .. " has a name and a description")
	if s then
		check(pt[s[1]] ~= nil and pt[s[1]] ~= "", "stat " .. stat .. " name has a pt-BR")
		check(pt[s[2]] ~= nil and pt[s[2]] ~= "", "stat " .. stat .. " description has a pt-BR")
	end
end
check(count > 40, "the tree gives " .. count .. " plain stats")
for stat in pairs(cfg.stats) do
	check(all[stat], "config stat " .. stat .. " is given by a node (remove dead entries)")
end
for key, name in pairs(cfg.groupNames) do
	check(cfg.groups[key] and pt[name], "group " .. key .. " has a label and a pt-BR")
end

-- ------------------------------------------------------------------------------------------------ the numbers
local function has(stat, text)
	return cfg.stats[stat][2]:find(text, 1, true) ~= nil
end
check(E.charStatCap.strength == 120 and has("strength", "120 points") and has("intelligence", "120 points"), "strength / intelligence cap")
check(E.charStatScale.strength == 0.5 and has("strength", "0.5 x points") and E.charStatScale.intelligence == 0.5
	and has("intelligence", "0.5 x points"), "strength / intelligence worth of a point")
check(E.charStatCap.dexterity == 80 and has("dexterity", "80 points") and E.charStatScale.dexterity == 0.25
	and has("dexterity", "0.25 x points"), "dexterity cap and worth of a point")
check(E.charStatCap.vitality == 100 and has("vitality", "100 points") and E.charStatCap.spirit == 100 and has("spirit", "100 points"),
	"vitality / spirit cap")
check(E.charStatScale.vitality == 0.5 and has("vitality", "+0.5 percent") and E.charStatScale.spirit == 0.5
	and has("spirit", "+0.5 percent"), "vitality / spirit worth of a point")
-- the maximum effect the texts name, from the real functions at the cap
check(has("vitality", "(+50%)") and ChaosPassiveMaxPercent({vitality = E.charStatCap.vitality}, "vitality") == 50, "vitality: +50% at the cap")
check(has("spirit", "(+50%)") and ChaosPassiveMaxPercent({spirit = E.charStatCap.spirit}, "spirit") == 50, "spirit: +50% at the cap")
check(has("dexterity", "(+25%)") and math.abs(mult({dexterity = E.charStatCap.dexterity}, COMBAT_PHYSICALDAMAGE, ORIGIN_MELEE) - 1.25) < 1e-9,
	"dexterity: x1.25 at the cap")
-- the Auto build generator scores with the same caps and point worth (passive_builds_config.lua)
local B = dofile("data/scripts/chaos/passive_builds_config.lua")
for _, stat in ipairs({"strength", "intelligence", "dexterity", "vitality", "spirit"}) do
	check(B.caps[stat] == E.charStatCap[stat] and B.statScale[stat] == E.charStatScale[stat], "builds config " .. stat .. " = effects")
end
-- 2026-10-22: the Thief's and Ninja's most taken 10-point Attribute lanes give all-element resistance, not dexterity
for vk, ids in pairs({thief = {130, 132, 157, 173, 238}, ninja = {130, 132, 238}}) do
	for _, id in ipairs(ids) do
		local v = tree.nodes[id].v and tree.nodes[id].v[vk]
		check(v and v.absorbAllElements == 2 and v.dexterity == nil, vk .. " node " .. id .. ": absorbAllElements 2")
	end
	check(C.classInfo(cfg, vk).tag.absorbAllElements == "secondary", vk .. ": absorbAllElements is secondary")
end
check(E.maxAbsorb == 75 and has("absorbFire", "75 percent") and has("absorbAllElements", "75 percent"), "absorb cap")
check(E.maxDamagePercent == 150 and has("incrementFire", "+150 percent"), "damage cap")
check(E.maxSpeed == 80 and has("speed", "+80"), "speed cap")
check(E.lootPerPoint == 0.2 and has("loot", "+0.2") and E.rarityLootPerPoint == 1.0 and has("rarityLoot", "+1 per"), "item find rates")
-- the divisor 230 and the dexterity formula, from the real function
local m = mult({strength = 23}, COMBAT_PHYSICALDAMAGE, nil)
check(math.abs(m - (1 + 0.5 * 23 / 230)) < 1e-9 and has("strength", "/ 230") and has("intelligence", "/ 230"),
	"strength: x (1 + 0.5 x points / 230)")
check(math.abs(mult({strength = 120}, COMBAT_PHYSICALDAMAGE, nil) - (1 + 60 / 230)) < 1e-9 and has("strength", "(+26%)"), "26% at the cap")

-- ------------------------------------------------------------------------------------------------ the class lists
local classes = Chaos.classes.ids
local nclasses = 0
for classKey in pairs(classes) do
	nclasses = nclasses + 1
	local info = C.classInfo(cfg, classKey)
	check(info ~= nil, "class " .. classKey .. " has lists")
	if info then
		check(#info.primary >= 3 and #info.secondary >= 3, classKey .. ": primary and secondary are not empty")
		for _, list in ipairs({info.primary, info.secondary, info.irrelevant}) do
			for _, stat in ipairs(list) do
				check(cfg.stats[stat] ~= nil, classKey .. ": " .. stat .. " is a known stat")
			end
		end
		for _, stat in ipairs(info.irrelevant) do
			check(info.tag[stat] == nil, classKey .. ": " .. stat .. " is irrelevant and also tagged")
		end
		check(info.tag[info.primary[1]] == "primary", classKey .. ": the first primary is primary")
		local tagged = 0
		local total = 0
		for id, node in pairs(tree.nodes) do
			if not node.c or node.c[classKey] then
				total = total + 1
				if C.nodeTag(C.nodeStats(node), info) then
					tagged = tagged + 1
				end
			end
		end
		check(tagged / total > 0.25 and tagged / total < 0.9, classKey .. ": " .. tagged .. " of " .. total .. " nodes are tagged")
	end
end
check(nclasses == 21, "21 classes")
for classKey in pairs(cfg.classes) do
	check(classes[classKey] ~= nil, "lists for a class that does not exist: " .. classKey)
end

-- ------------------------------------------------------------------------------------------------ the message
local parts = C.parts(cfg, "necromancer", tree, function(t) return "<" .. t .. ">" end)
check(#parts >= 4, "the necromancer's stats come in parts: " .. #parts)
local seen, tags = {}, 0
for i, p in ipairs(parts) do
	check(p.part == i and p.parts == #parts and #p.stats <= 10, "part " .. i)
	for _, row in ipairs(p.stats) do
		seen[row.k] = true
		tags = tags + (row.t and 1 or 0)
		check(row.n:sub(1, 1) == "<" and row.d:sub(1, 1) == "<", "texts go through the translation")
	end
end
check(seen.magicSkill and seen.swordSkill and not seen.incrementDrown, "the stats of the tree, no more")
check(parts[1].header and parts[1].header.primary:find("<Magic level>", 1, true) and parts[1].header.secondary ~= "", "the header")
check(parts[2].header == nil, "only the first part has the header")
check(tags >= 10, "tags are sent")
for classKey in pairs(classes) do
	local ps = C.parts(cfg, classKey, tree, function(t) return t end)
	local bytes = 0
	for _, p in ipairs(ps) do
		local size = #encode(p)
		check(size < 8000, classKey .. ": a part fits one message (" .. size .. ")")
	end
end

-- the Templar line casts and leeches mana: mana leech is never a wasted stat for it (owner report)
for _, classKey in ipairs({"templar", "inquisitor", "sentinel"}) do
	local info = C.classInfo(cfg, classKey)
	check(not info.bad.manaLeechChance and not info.bad.manaLeechAmount, classKey .. ": mana leech is not wasted")
end
for _, classKey in ipairs({"templar", "sentinel"}) do
	check(C.classInfo(cfg, classKey).tag.manaLeechAmount == "secondary", classKey .. ": mana leech is secondary")
end

if failures > 0 then
	error(failures .. " of " .. checks .. " checks failed")
end
print("passivetree_stats_test: " .. checks .. " checks OK")
