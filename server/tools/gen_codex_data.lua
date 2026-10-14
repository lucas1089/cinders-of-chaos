-- Regenerates client/overlay/modules/game_codex/codex_data.lua (the in-client Codex: modifiers, legendary powers, orbs
-- and currency, gems, uniques, item sets, rift modifiers, spell supports and the item basics) from the real server data files.
-- Run from the server/ folder (the libraries dofile() their neighbours relative to it):
--   luajit tools/gen_codex_data.lua            write the client file
--   luajit tools/gen_codex_data.lua --check    exit 1 when the client file differs from what the data gives (CI)
--   lua5.3 works the same; the output is byte-identical under both (CI checks both).
-- The libraries are loaded for real (chaos_item_mods.lua, chaos_powers.lua, chaos_crafting.lua, chaos_orbs*.lua,
-- chaos_gems*.lua, chaos_unique_*.lua, chaos_supports*.lua, rift_core.lua and the *_config.lua files of
-- data/scripts/chaos); only a few engine constants are stubbed. No clock, no random, no pairs() order: the output only
-- changes when the data does. Pure helpers (number and table writers, value texts, odds) are exported for
-- tests/codex_gen_test.lua: set CODEX_GEN_NO_MAIN = true before dofile() to load them without writing anything.

local Gen = {}
local floor = math.floor

local OUT_DEFAULT = "../client/overlay/modules/game_codex/codex_data.lua"
Gen.SOURCES = {
	"data/lib/chaos_item_mods.lua", "data/lib/chaos_powers.lua", "data/lib/chaos_energy_shield.lua", "data/lib/chaos_crafting.lua",
	"data/lib/chaos_orbs.lua", "data/lib/chaos_orbs_config.lua", "data/lib/chaos_gems.lua",
	"data/lib/chaos_gems_config.lua", "data/lib/chaos_unique_items.lua", "data/lib/chaos_unique_specs.lua",
	"data/lib/chaos_supports.lua", "data/lib/chaos_supports_config.lua", "data/scripts/chaos/loot_config.lua",
	"data/scripts/chaos/salvage_config.lua", "data/scripts/chaos/shop_config.lua", "data/scripts/chaos/bounty_config.lua",
	"data/scripts/chaos/rift_config.lua", "data/scripts/chaos/rift_core.lua", "data/scripts/chaos/chaos_constants.lua",
	"data/scripts/chaos/uber_config.lua", "data/lib/chaos_item_sets.lua", "data/lib/chaos_item_sets_config.lua",
	"data/lib/chaos_veiled.lua", "data/lib/chaos_veiled_config.lua", "data/scripts/chaos/professions_config.lua",
	"data/scripts/chaos/lore_data.lua"
}

-- ---------------------------------------------------------------------------------------------------------------
-- pure helpers
-- ---------------------------------------------------------------------------------------------------------------
-- a number as text: whole numbers without a decimal point (Lua 5.3 writes 2.0), others with up to 4 decimals
function Gen.num(v)
	v = tonumber(v) or 0
	if v == floor(v) and math.abs(v) < 2 ^ 53 then
		return string.format("%d", v)
	end
	local s = string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

-- a number with its sign ("+3", "-3", "0")
function Gen.signed(v)
	v = tonumber(v) or 0
	return (v > 0 and "+" or "") .. Gen.num(v)
end

-- a percent from a chance per 10000 ("0.25%", "40%")
function Gen.per10k(v)
	return Gen.num(floor((tonumber(v) or 0) * 100 + 0.5) / 10000) .. "%"
end

-- a share of a total as a percent with one decimal ("12.5%")
function Gen.share(part, total)
	if (tonumber(total) or 0) <= 0 then
		return "0%"
	end
	return Gen.num(floor(part * 1000 / total + 0.5) / 10) .. "%"
end

-- "a-b" or "a" when both ends are the same
function Gen.range(lo, hi)
	if lo == hi then
		return Gen.num(lo)
	end
	return Gen.num(lo) .. "-" .. Gen.num(hi)
end

function Gen.seconds(ms)
	return Gen.num((tonumber(ms) or 0) / 1000) .. " s"
end

-- a Lua string literal that reads the same in Lua 5.1 and 5.3
function Gen.quote(s)
	s = tostring(s)
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	return "\"" .. s .. "\""
end

local function isArray(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

-- keys written first, in this order; the rest sorted by name
local KEY_ORDER = {"id", "name", "h", "color", "sub", "group", "side", "f", "p", "cols", "w", "rows", "links", "tiers",
	"tv", "sections"}
local KEY_RANK = {}
for i, k in ipairs(KEY_ORDER) do
	KEY_RANK[k] = i
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b)
		local ra, rb = KEY_RANK[a] or 1000, KEY_RANK[b] or 1000
		if ra ~= rb then
			return ra < rb
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local IDENT = "^[%a_][%w_]*$"

-- a table as one line of Lua source (nil when it holds something else than numbers, strings, booleans and tables)
function Gen.inline(v)
	local tv = type(v)
	if tv == "number" then
		return Gen.num(v)
	elseif tv == "string" then
		return Gen.quote(v)
	elseif tv == "boolean" then
		return tostring(v)
	elseif tv ~= "table" then
		return nil
	end
	local parts = {}
	if isArray(v) then
		for _, x in ipairs(v) do
			local s = Gen.inline(x)
			if not s then
				return nil
			end
			parts[#parts + 1] = s
		end
	else
		for _, k in ipairs(sortedKeys(v)) do
			local s = Gen.inline(v[k])
			if not s then
				return nil
			end
			local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. Gen.inline(k) .. "]")
			parts[#parts + 1] = key .. " = " .. s
		end
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

-- a value as Lua source; short tables on one line, others one element per line
function Gen.serialize(v, indent)
	indent = indent or ""
	local tv = type(v)
	if tv == "number" then
		return Gen.num(v)
	elseif tv == "string" then
		return Gen.quote(v)
	elseif tv == "boolean" then
		return tostring(v)
	elseif tv ~= "table" then
		error("cannot serialize " .. tv)
	end
	local flat = true
	for _, x in pairs(v) do
		if type(x) == "table" then
			flat = false
			break
		end
	end
	-- short tables on one line (tier ranges, rows of a table, filter values)
	local inline = Gen.inline(v)
	if inline and #inline + #indent * 4 <= 116 then
		return inline
	end
	local parts = {}
	if isArray(v) then
		for _, x in ipairs(v) do
			parts[#parts + 1] = Gen.serialize(x, indent .. "\t")
		end
	else
		for _, k in ipairs(sortedKeys(v)) do
			local key = (type(k) == "string" and k:match(IDENT)) and k or ("[" .. Gen.serialize(k) .. "]")
			parts[#parts + 1] = key .. " = " .. Gen.serialize(v[k], indent .. "\t")
		end
	end
	if #parts == 0 then
		return "{}"
	end
	if flat then
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return "{\n" .. indent .. "\t" .. table.concat(parts, ",\n" .. indent .. "\t") .. "\n" .. indent .. "}"
end

-- ---------------------------------------------------------------------------------------------------------------
-- value texts of modifiers
-- ---------------------------------------------------------------------------------------------------------------
-- the value of a Chaos modifier (chaos_item_mods.lua def) for a range, short: "+1-3%", "+4-8", "-1-2%", "1-2%"
function Gen.chaosValue(def, lo, hi)
	local r = Gen.range(lo, hi)
	if def.text then
		if def.text:find("%%d%%%%") then
			return r .. "%"
		end
		return "+" .. r
	elseif def.fmt == "flat" then
		return "+" .. r
	elseif def.fmt == "less" then
		return "-" .. r .. "%"
	end
	return "+" .. r .. "%"
end

-- the cap of a Chaos modifier as text ("30%", "250")
function Gen.capValue(def)
	local v = Gen.num(def.cap)
	if def.text then
		return def.text:find("%%d%%%%") and (v .. "%") or v
	end
	return def.fmt == "flat" and v or (v .. "%")
end

-- the whole line of a Chaos modifier with a range in place of the number ("Attack Speed +11-14%")
function Gen.chaosLine(def, lo, hi)
	local r = Gen.range(lo, hi)
	if def.text then
		return (def.text:gsub("%%d", r):gsub("%%%%", "%%"))
	elseif def.fmt == "flat" then
		return def.label .. " +" .. r
	elseif def.fmt == "less" then
		return def.label .. " -" .. r .. "%"
	end
	return def.label .. " +" .. r .. "%"
end

-- chance odds of each tier at an item level (ChaosItemMods.tierChances) as text "T8 6.5%, T7 11.9%, ..."
function Gen.oddsText(M, level)
	local rows, chances, out = M.tierRows(level), M.tierChances(level), {}
	for _, r in ipairs(rows) do
		out[#out + 1] = "T" .. r[1] .. " " .. Gen.num(chances[r[1]]) .. "%"
	end
	return table.concat(out, ", ")
end

-- ---------------------------------------------------------------------------------------------------------------
-- loading the data
-- ---------------------------------------------------------------------------------------------------------------
local function stubEngine()
	-- the unique specs use these as table keys; strings make them readable
	local attrs = {ATTACK = "Attack", DEFENSE = "Defense", EXTRADEFENSE = "Extra Defense", ARMOR = "Armor",
		HITCHANCE = "Hit Chance", SHOOTRANGE = "Range", ATTACK_SPEED = "Attack Speed", NAME = "Name",
		ARTICLE = "Article", DESCRIPTION = "Description"}
	for k, v in pairs(attrs) do
		_G["ITEM_ATTRIBUTE_" .. k] = _G["ITEM_ATTRIBUTE_" .. k] or v
	end
end

function Gen.load()
	stubEngine()
	local D = {}
	dofile("data/lib/chaos_item_mods.lua")
	dofile("data/lib/chaos_crafting.lua") -- loads gems, powers and the orbs v2 too
	dofile("data/lib/chaos_unique_items.lua")
	dofile("data/lib/chaos_supports.lua")
	dofile("data/scripts/chaos/rift_core.lua")
	dofile("data/scripts/chaos/chaos_constants.lua")
	D.M, D.C, D.P, D.G, D.O, D.S, D.R = ChaosItemMods, ChaosCrafting, ChaosPowers, ChaosGems, ChaosOrbs, ChaosSupports,
		ChaosRiftCore
	D.loot = dofile("data/scripts/chaos/loot_config.lua")
	D.salvage = dofile("data/scripts/chaos/salvage_config.lua")
	D.shop = dofile("data/scripts/chaos/shop_config.lua")
	D.bounty = dofile("data/scripts/chaos/bounty_config.lua")
	D.rift = dofile("data/scripts/chaos/rift_config.lua")
	D.uber = dofile("data/scripts/chaos/uber_config.lua") -- the Ascended Omens and the Cinderheart (uber.lua)
	D.prof = dofile("data/scripts/chaos/professions_config.lua") -- the professions' materials (professions.lua)
	D.lore = dofile("data/scripts/chaos/lore_data.lua") -- the lore entries (docs/CONTENT.md "Lore")
	D.uniques = ChaosUniqueItems
	D.specs = ChaosUniqueSpecs
	D.itemSets = ChaosItemSets -- data/lib/chaos_item_sets.lua (loaded by chaos_unique_items.lua)
	D.worldBoss = Chaos and Chaos.worldBoss
	return D
end

-- ---------------------------------------------------------------------------------------------------------------
-- shared names
-- ---------------------------------------------------------------------------------------------------------------
Gen.KINDS = {
	{"weapon", "Weapons"}, {"shield", "Shields"}, {"helmet", "Helmets"}, {"armor", "Body armour"}, {"legs", "Legs"},
	{"boots", "Boots"}, {"jewel", "Jewellery (amulets, rings)"}, {"other", "Other gear (gloves, belts...)"},
	{"quiver", "Quivers (with a bow or crossbow)"}
}
local KIND_SHORT = {weapon = "Weapon", shield = "Shield", helmet = "Helmet", armor = "Armour", legs = "Legs",
	boots = "Boots", jewel = "Jewel", other = "Other", quiver = "Quiver"}
-- a modifier open to every kind (no kinds list) rolls on every kind but quivers (chaos_item_mods.lua M.allowed)
local ANY_KINDS = #Gen.KINDS - 1
local TIER_ORDER = {"normal", "magic", "rare", "legendary", "boss"}
local TIER_NAME = {normal = "Normal", magic = "Magic", rare = "Rare", legendary = "Legendary", boss = "Boss"}

local COLORS = {absorb = "#7fa8ff", skill = "#9fdc7f", special = "#f6cf72", element = "#ff8a5a", chaos = "#ff70c0",
	power = "#ff9a3c", orb = "#e8b84a", currency = "#c0a0ff", rift = "#c0a0ff", unique = "#ff9c3a", basics = "#d6c9ae", lore = "#c9a27a"}

local function kindsOf(kinds)
	local out = {}
	for _, k in ipairs(Gen.KINDS) do
		if (kinds == nil and k[1] ~= "quiver") or (kinds ~= nil and kinds[k[1]]) then
			out[#out + 1] = k[1]
		end
	end
	return out
end

local function kindNames(list, short)
	local out = {}
	local names = {}
	for _, k in ipairs(Gen.KINDS) do
		names[k[1]] = short and KIND_SHORT[k[1]] or k[2]
	end
	for _, k in ipairs(list) do
		out[#out + 1] = names[k]
	end
	return out
end

local function sentenceList(list)
	if #list <= 1 then
		return list[1] or ""
	end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

local function orbName(D, key)
	local o = D.C.orbByKey[key]
	return o and o.name or key
end

local function sortByName(list)
	table.sort(list, function(a, b)
		if a.name == b.name then
			return a.id < b.id
		end
		return a.name < b.name
	end)
	return list
end

-- ---------------------------------------------------------------------------------------------------------------
-- modifiers (and powers): one entry per affix of ChaosCrafting.affixes()
-- ---------------------------------------------------------------------------------------------------------------
local function affixName(a)
	if a.group == "absorb" then
		return a.label .. " Absorb"
	elseif a.group == "skill" then
		return a.label == "Magic" and "Magic Level" or (a.label .. " Skill")
	elseif a.group == "special" then
		if a.key:lower():find("critical") then
			return "Critical Hit"
		end
		return a.key:lower():find("mana") and "Mana Leech" or "Life Leech"
	elseif a.group == "element" then
		return a.label .. " Weapon Damage"
	end
	return a.label
end

-- value text of an affix at a range
local function affixValue(D, a, lo, hi)
	if a.group == "chaos" then
		return Gen.chaosValue(a.def, lo, hi)
	elseif a.group == "skill" then
		return "+" .. Gen.range(lo, hi)
	elseif a.group == "special" then
		return Gen.range(D.C.specialChance(lo), D.C.specialChance(hi)) .. "% chance, +" .. Gen.range(lo, hi) .. "%"
	end
	return "+" .. Gen.range(lo, hi) .. "%"
end

local PROFESSIONS = {fishing = true, crafting = true, woodcutting = true, mining = true, herbalist = true,
	armorsmith = true, weaponsmith = true, jewelsmith = true}

local function affixOverview(D, a)
	local M = D.M
	local top = a.tiers[#a.tiers]
	local p = {}
	if a.group == "absorb" then
		p[#p + 1] = string.format("Absorbs a share of the %s damage you take (shown on the item as \"%s +N%%\").",
			a.label:lower(), a.label)
	elseif a.group == "skill" then
		local skill = a.key:match("^rarity_(%a+)Skill$") or ""
		if PROFESSIONS[skill] then
			p[#p + 1] = string.format("Raises the %s profession skill while the item is worn.", a.label)
		elseif a.label == "Magic" then
			p[#p + 1] = "Raises your magic level while the item is worn."
		else
			p[#p + 1] = string.format("Raises your %s skill while the item is worn.", a.label:lower())
		end
	elseif a.group == "special" then
		if a.label == "Critical Chance" then
			p[#p + 1] = "A pair: a chance to hit critically and the extra damage of a critical hit. The amount is the rolled value; the chance is about two thirds of it."
		else
			p[#p + 1] = string.format("A pair: a chance to leech and the share of the damage you deal that comes back as %s. The amount is the rolled value; the chance is about two thirds of it.",
				a.label:find("Mana") and "mana" or "health")
		end
	elseif a.group == "element" then
		p[#p + 1] = string.format("The weapon deals this much extra damage as %s damage.", a.label:lower())
	else
		p[#p + 1] = "On an item: " .. Gen.chaosLine(a.def, top[1], top[2]) .. " (T8)."
	end
	if a.def and a.def.cap then
		p[#p + 1] = "Cap: at most " .. Gen.capValue(a.def) .. " from all equipped items together."
	end
	return p
end

local function affixNotes(D, a, isPower)
	local M, C = D.M, D.C
	local notes = {}
	notes[#notes + 1] = string.format("A %s: a rarity allows only so many prefixes and suffixes (see Basics > Rarity).", a.side)
	notes[#notes + 1] = "An item carries each modifier once at most."
	if a.group == "element" then
		notes[#notes + 1] = string.format("At most %d weapon element per weapon, and only on a weapon with an attack and no element of its own.",
			C.config.maxElements)
	end
	if a.group == "special" then
		notes[#notes + 1] = "Chance and amount roll together and count as one modifier with one tier."
	end
	if isPower then
		notes[#notes + 1] = string.format("A legendary power: only on items of rarity %s or better, %d per item.",
			C.rarityName(M.config.powers.minRarity), M.config.powers.maxPerItem)
	end
	if a.chaosKey == "attackspeed" then
		local cap = D.G.config.effects.attackspeed.cap
		notes[#notes + 1] = string.format("Local to the weapon: it shortens that weapon's attack interval. With topaz gems at most %d%% on one weapon.", cap)
	elseif a.chaosKey == "movespeed" then
		notes[#notes + 1] = string.format("Shares its %d%% cap with the emerald gems' movement speed.", D.G.config.effects.movespeed.cap)
	elseif a.chaosKey == "bleedchance" or a.chaosKey == "ignitechance" or a.chaosKey == "poisonchance" then
		local ail = M.config.ailment
		notes[#notes + 1] = string.format("The ailment deals %d%% of the hit that caused it over %d ticks of %s.", ail.share,
			ail.rounds, Gen.seconds(ail.interval))
	elseif a.chaosKey == "chillchance" then
		local ail = M.config.ailment
		notes[#notes + 1] = string.format("A chilled monster is %d%% slower for %s.", ail.chillSlow, Gen.seconds(ail.chillMs))
	elseif a.chaosKey == "shockchance" then
		local ail = M.config.ailment
		notes[#notes + 1] = string.format("A shocked monster takes %d%% more damage from everyone for %s.", ail.shockPct,
			Gen.seconds(ail.shockMs))
	elseif a.chaosKey == "regen" then
		notes[#notes + 1] = string.format("Paid every %s.", Gen.seconds(M.config.regenEvery))
	end
	return notes
end

-- the chance that a roll on a fresh item of each kind picks this affix (weight / every candidate's weight; powers only
-- on Legendary items, element only on weapons that may have one)
local function rollShares(D, a, isPower)
	local rows = {}
	for _, k in ipairs(kindsOf(a.kinds)) do
		local total = 0
		for _, b in ipairs(D.C.affixes()) do
			local bPower = b.def and D.M.isPower(b.def)
			if D.M.allowed(b, k) and (b.group ~= "element" or k == "weapon") and (not bPower or isPower) then
				total = total + b.weight
			end
		end
		rows[#rows + 1] = {KIND_SHORT[k], Gen.num(a.weight) .. " of " .. Gen.num(total), Gen.share(a.weight, total)}
	end
	return rows
end

local function affixOrbs(D, a, isPower)
	local C, M, O = D.C, D.M, D.O
	local conf = C.config
	local function weights(rows)
		local total, out = 0, {}
		for _, r in ipairs(rows) do
			total = total + r[2]
		end
		for _, r in ipairs(rows) do
			out[#out + 1] = C.rarityName(r[1]) .. " " .. Gen.share(r[2], total)
		end
		return out, total
	end
	local trans = weights(conf.transmutation)
	local alch, alchTotal = weights(conf.alchemy)
	local legendaryShare = 0
	for _, r in ipairs(conf.alchemy) do
		if r[1] >= M.config.powers.minRarity then
			legendaryShare = legendaryShare + r[2]
		end
	end
	local ruin = O.config.ruin
	local q = M.config.quality
	local rows, links = {}, {}
	local function add(key, text)
		rows[#rows + 1] = {orbName(D, key), text}
		links[#links + 1] = "orb:" .. key
	end
	if isPower then
		add("transmutation", "Cannot roll it: the item becomes " .. table.concat(trans, " / ") .. ", below " ..
			C.rarityName(M.config.powers.minRarity) .. ".")
		add("alchemy", "Can roll it only when the item becomes " .. C.rarityName(M.config.powers.minRarity) ..
			" (" .. Gen.share(legendaryShare, alchTotal) .. ").")
		add("exalted", "Adds it at random on a " .. C.rarityName(M.config.powers.minRarity) ..
			" or better item without a power, when a " .. a.side .. " is open.")
	else
		add("transmutation", "Can roll it on a normal item (" .. table.concat(trans, ", ") .. ").")
		add("alchemy", "Can roll it on a normal item (" .. table.concat(alch, ", ") .. ").")
		add("exalted", "Adds it at random when the item has an open " .. a.side .. " and suits it.")
	end
	add("chaos", "Rolls every unbound modifier again: it may come or go.")
	add("divine", "New rarity (often none): every modifier rolled again.")
	add("annulment", "May remove it (one random unbound modifier).")
	add("excision", "Removes it when you pick it on the bench.")
	add("scouring", "Removes it with the rarity and every other modifier.")
	add("tempering", "New value inside its tier (unless bound).")
	add("reforging", "New tier (by item level) and value when you pick it.")
	add("binding", "Binds it: Tempering, Unmaking, Excision, Reforging and Upheaval leave it alone.")
	add("ruin", string.format("%d%% improve (%d%% of those: one tier more on every unbound modifier), %d%% nothing, %d%% ruined.",
		ruin.improve, ruin.tiers, ruin.nothing, ruin.ruin))
	add("whetstone", string.format("Quality multiplies its value: +%d%% per stone, up to %d%% (%d%% from %s).", q.perStone,
		q.cap, q.capHigh, C.rarityName(q.highFrom)))
	return rows, links
end

local function tierSection(D, a)
	local M = D.M
	local rows, tv = {}, {}
	for t, r in ipairs(a.tiers) do
		local v = affixValue(D, a, r[1], r[2])
		tv[t] = v
		rows[t] = {"T" .. t, Gen.num(M.config.tierLevels[t]) .. "+", v, Gen.num(M.config.tierWeights[t])}
	end
	return {h = "Tiers", tiers = true, cols = {"Tier", "Item level", "Value", "Tier weight"}, w = {14, 22, 40, 24},
		rows = rows}, tv
end

function Gen.modifierEntry(D, a)
	local isPower = a.def and D.M.isPower(a.def) or false
	local kinds = kindsOf(a.kinds)
	if a.group == "element" then
		kinds = {"weapon"}
	end
	local name = affixName(a)
	local e = {id = "mod:" .. a.key:lower(), name = name, group = isPower and "power" or a.group, side = a.side,
		color = isPower and COLORS.power or COLORS[a.group]}
	local tiers, tv = tierSection(D, a)
	e.tiers, e.tv = {}, tv
	for t, r in ipairs(a.tiers) do
		e.tiers[t] = {r[1], r[2]}
	end
	local groupName = ({absorb = "Absorb", skill = "Skill", special = "Critical / leech", element = "Weapon element",
		chaos = "Chaos modifier"})[a.group]
	e.sub = string.format("%s, %s. %s (T1) to %s (T8)", a.side == "prefix" and "Prefix" or "Suffix",
		#kinds == ANY_KINDS and "any gear" or table.concat(kindNames(kinds, true), ", "), tv[1], tv[#tv])
	e.f = {side = a.side, kind = kinds, group = isPower and "power" or a.group}
	local overview = affixOverview(D, a)
	if not isPower then
		table.insert(overview, 1, groupName .. ", " .. a.side .. ".")
	end
	local rollsOn
	if a.group == "element" then
		rollsOn = {"Weapons with an attack and no element of their own."}
	else
		rollsOn = {#kinds == ANY_KINDS and "Any gear." or (sentenceList(kindNames(kinds)) .. ".")}
	end
	-- the orb table is the same for every modifier of one side (and powers): one shared copy (CodexData.shared)
	local ref = "orbs:" .. a.side .. (isPower and ":power" or "")
	if D.shared and not D.shared[ref] then
		local orbRows, orbLinks = affixOrbs(D, a, isPower)
		D.shared[ref] = {h = "Orbs", cols = {"Orb", "What it does to this modifier"}, w = {30, 70}, rows = orbRows,
			links = orbLinks}
	end
	e.sections = {
		{h = "Overview", p = overview},
		tiers,
		{h = "Rolls on", p = rollsOn},
		{h = "Chance per roll on a fresh item", p = {isPower and
			"Among every modifier a Legendary item of that kind may roll (weights):" or
			"Among every modifier an item of that kind may roll, powers not counted (weights):"},
			cols = {"Kind", "Weight", "Chance"}, w = {30, 40, 30}, rows = rollShares(D, a, isPower)},
		{h = "Rules", p = affixNotes(D, a, isPower)},
		{ref = ref}
	}
	return e
end

-- the legendary powers' own numbers (chaos_powers.lua P.config) as sentences
local POWER_EFFECT = {
	deathblast = function(c)
		return string.format("On a kill: a fire explosion where the monster died, %d%% of its maximum health (at most %d + %d x your level) to up to %d other monsters within %d sqm.",
			c.hpPct, c.capBase, c.capPerLevel, c.targets, c.radius), "the chance on a kill"
	end,
	frostward = function(c)
		return string.format("When a monster's hit is dodged or blocked: an ice nova around you, %d + %d x your level damage to up to %d monsters within %d sqm, slowed by %d%% for %s.",
			c.base, c.perLevel, c.targets, c.radius, c.slow, Gen.seconds(c.slowMs)), "the chance on a dodge or block"
	end,
	echoshot = function(c)
		return string.format("A ranged hit that lands is shot again after %d ms for %d%% of its damage.", c.delayMs, c.pct),
			"the chance on a ranged hit"
	end,
	critecho = function(c)
		return string.format("A critical hit strikes again after %d ms for %d%% of its damage.", c.delayMs, c.pct),
			"the chance on a critical hit"
	end,
	arclightning = function(c)
		return string.format("A hit arcs to up to %d other monsters within %d sqm for %d%% of it.", c.targets, c.radius, c.pct),
			"the chance on a hit"
	end,
	bloodrush = function(c)
		return string.format("Every kill adds a stack for %s, at most %d stacks; each stack adds the power's value to your damage.",
			Gen.seconds(c.windowMs), c.maxStacks), "percent damage per stack"
	end,
	shattersplash = function(c)
		return string.format("The killing blow bursts onto up to %d monsters within %d sqm for the power's share of the blow.",
			c.targets, c.radius), "percent of the killing blow"
	end,
	crimsonburst = function(c)
		return string.format("A hit heals you for %d%% of your maximum health.", c.healPct), "the chance on a hit"
	end,
	lastbreath = function(c)
		return "A hit that would kill you leaves you at the power's share of your health instead. The cooldown is kept over logout.",
			"the health left, percent of your maximum"
	end,
	emberstep = function(c)
		return string.format("A single hit of at least %d%% of your maximum health blinks you up to %d sqm away and burns where you stood: %d + %d x your level fire damage to up to %d monsters within %d sqm.",
			c.hitPct, c.range, c.base, c.perLevel, c.targets, c.radius), "the chance on a hard hit"
	end,
	hunterrush = function(c)
		return string.format("Haste: +%d speed for %s.", c.speed, Gen.seconds(c.ms)), "the chance on a kill"
	end,
	smolderaura = function(c)
		return string.format("Every %s up to %d monsters within %d sqm burn for the power's value per second.",
			Gen.seconds(c.tickMs), c.targets, c.radius), "fire damage per second"
	end
}

function Gen.powerEntry(D, a)
	local e = Gen.modifierEntry(D, a)
	e.id = "power:" .. a.chaosKey
	local c = D.P.config[a.chaosKey] or {}
	local effect, meaning = "", "the value"
	if POWER_EFFECT[a.chaosKey] then
		effect, meaning = POWER_EFFECT[a.chaosKey](c)
	end
	local top = a.tiers[#a.tiers]
	local limit
	if c.cooldownMs then
		limit = "Internal cooldown: " .. Gen.seconds(c.cooldownMs) .. "."
	elseif c.maxStacks then
		limit = string.format("No cooldown: at most %d stacks.", c.maxStacks)
	elseif c.tickMs then
		limit = "No cooldown: it ticks every " .. Gen.seconds(c.tickMs) .. "."
	end
	local p = {effect, "Value: " .. meaning .. ".", "On an item: " .. Gen.chaosLine(a.def, top[1], top[2]) .. " (T8)."}
	if limit then
		p[#p + 1] = limit
	end
	p[#p + 1] = "Cap: at most " .. Gen.capValue(a.def) .. " from all equipped items together."
	e.sections[1] = {h = "Effect", p = p}
	e.sub = "Legendary power. " .. e.sub
	return e
end

-- ---------------------------------------------------------------------------------------------------------------
-- orbs and currency
-- ---------------------------------------------------------------------------------------------------------------
local function lootRow(D, id)
	for _, row in ipairs(D.loot.currency.entries) do
		if row.id == id then
			return row
		end
	end
	return nil
end

local function shopOffers(D, id)
	local out = {}
	for _, cat in ipairs(D.shop.categories) do
		for _, o in ipairs(cat.offers) do
			if o.kind == "item" and o.id == id then
				local text = string.format("%d for %d Chaos Coins", o.count, o.cost)
				if o.weeklyLimit then
					text = text .. string.format(", %d a week per account", o.weeklyLimit)
				end
				out[#out + 1] = text
			end
		end
	end
	return out
end

local function sourcesOf(D, id, key)
	local rows = {}
	local loot = lootRow(D, id)
	if loot then
		local parts = {}
		for _, t in ipairs(TIER_ORDER) do
			if (loot.chance[t] or 0) > 0 then
				parts[#parts + 1] = TIER_NAME[t] .. " " .. Gen.per10k(loot.chance[t])
			end
		end
		local total = 0
		for _, r in ipairs(D.loot.currency.entries) do
			total = total + r.weight
		end
		rows[#rows + 1] = {"Monster drops", string.format("Per kill by monster tier: %s; %s at a time. Legendary monsters and bosses also drop one guaranteed currency item, this one %s of the time.",
			table.concat(parts, ", "), Gen.range(loot.count[1], loot.count[2]), Gen.share(loot.weight, total))}
	end
	if key then
		for _, r in ipairs(D.salvage.recipes) do
			if r.key == key then
				rows[#rows + 1] = {"Salvage", string.format("Combine %d rune shards into one at the crafting bench.", r.cost)}
			end
		end
		local total, w = 0, 0
		for _, r in ipairs(D.salvage.orbWeights) do
			total = total + r[2]
			if r[1] == key then
				w = r[2]
			end
		end
		if w > 0 then
			rows[#rows + 1] = {"Salvage bonus", string.format("Salvaging gear with a rarity sometimes gives a whole orb (%s-%s per item by rarity); %s of those are this one.",
				Gen.per10k(D.salvage.orbChance[1]), Gen.per10k(D.salvage.orbChance[#D.salvage.orbChance]), Gen.share(w, total))}
		end
	end
	local offers = shopOffers(D, id)
	if #offers > 0 then
		rows[#rows + 1] = {"Store", table.concat(offers, "; ") .. "."}
	end
	for _, x in ipairs(D.bounty.weeklyExtra or {}) do
		if x.id == id then
			rows[#rows + 1] = {"Bounty chest", string.format("%d in every weekly bounty chest (%d contracts in a week).", x.count, D.bounty.weeklyNeed)}
		end
	end
	local which = (id == D.bounty.items.chaos and "chaos") or (id == D.bounty.items.divine and "divine") or nil
	if which then
		local per, weekly = {}, {}
		for _, b in ipairs(D.bounty.bands) do
			per[#per + 1] = Gen.num(b.reward[which])
			weekly[#weekly + 1] = Gen.num(b.weekly[which])
		end
		rows[#rows + 1] = {"Bounty board", string.format("Per contract by level band: %s (x%s for elite and boss contracts); weekly chest: %s.",
			table.concat(per, "/"), Gen.num(D.bounty.typeMult.elite), table.concat(weekly, "/"))}
		local rw = D.rift.reward[which]
		rows[#rows + 1] = {"Rift chest", string.format("%s + %s per rift tier (fractions are a chance of one more), x the key's quantity bonus.",
			Gen.num(rw.base), Gen.num(rw.perTier))}
		local cf = D.rift.coffer[which]
		if cf then
			rows[#rows + 1] = {"Sealed Coffer", string.format("%s + %s per rift tier.", Gen.num(cf.base), Gen.num(cf.perTier))}
		end
		local om = D.rift.omen.reward[which]
		if om then
			rows[#rows + 1] = {"Omen guardian chest", string.format("%s per finisher.", Gen.num(om))}
		end
		local wb = D.worldBoss and D.worldBoss.reward
		if wb then
			local base, pool = 0, 0
			for _, x in ipairs(wb.base or {}) do
				if x.id == id then
					base = base + x.count
				end
			end
			for _, x in ipairs(wb.pool or {}) do
				if x.id == id then
					pool = pool + x.count
				end
			end
			if base + pool > 0 then
				rows[#rows + 1] = {"World boss", string.format("%d for every eligible player, plus a share of %d split by contribution.", base, pool)}
			end
		end
	end
	return rows
end

-- the Orb of Unveiling (data/lib/chaos_veiled.lua): where veiled items and the orb come from, and the veiled pool
function Gen.veiledSections(V)
	local c = V.config
	local names = {rift = string.format("Rifts of tier %d+", c.sources.rift.minTier), omen = "Omen guardian arenas",
		raid = "The raid", descent = string.format("The Descent from depth %d", c.sources.descent.minDepth),
		ascended = "The Ascended fights"}
	local rows = {}
	for _, k in ipairs(c.sourceOrder) do
		local s = c.sources[k]
		rows[#rows + 1] = {names[k], string.format("Veiled slot on Rare to Epic gear %s, Legendary and better %s; the orb from kills %s (x%d from bosses).",
			Gen.per10k(s.chance), Gen.per10k(s.high), Gen.per10k(c.orbDrop.perKill[k]), c.orbDrop.tierMult.boss)}
	end
	rows[#rows + 1] = {"Raid vendor", string.format("%d orbs for %d Sepulchre Marks, once a week.", c.vendorBundle.count,
		c.vendorBundle.price)}
	local pool = {}
	for _, def in ipairs(c.pool) do
		local kinds = {}
		for _, k in ipairs(Gen.KINDS) do
			if def.kinds[k[1]] then
				kinds[#kinds + 1] = KIND_SHORT[k[1]]
			end
		end
		local lo, hi = def.tiers[1][1], def.tiers[#def.tiers][2]
		pool[#pool + 1] = {def.name, V.rangeText(def, lo, hi), table.concat(kinds, ", "),
			(def.minLevel or 1) > 1 and Gen.num(def.minLevel) or "-"}
	end
	local gates = {}
	for t, lv in ipairs(c.tiers.levels) do
		gates[#gates + 1] = string.format("V%d from item level %d", t, lv)
	end
	return rows, {h = "The veiled pool", cols = {"Modifier", "V1 to V4", "Gear", "Item level"}, w = {18, 46, 26, 10},
		rows = pool}, {h = "Veiled tiers", p = {table.concat(gates, ", ") .. string.format(
		". An offer's tier is one of the best %d the item level allows. Uniques and set pieces never have a veiled slot; every other orb keeps it.",
		c.tiers.window)}}
end

local KEY_ORBS = {transmutation = true, alchemy = true, exalted = true, annulment = true, scouring = true, chaos = true,
	divine = true, tempering = true, excision = true}

function Gen.orbEntries(D)
	local C, M, O, G = D.C, D.M, D.O, D.G
	local out = {}
	local reasons = {
		transmutation = "Only a normal item (no rarity, no modifiers).",
		alchemy = "Only a normal item (no rarity, no modifiers).",
		exalted = "Only an item with a rarity and an open prefix or suffix.",
		annulment = "Only an item with a rarity and a modifier that is not bound.",
		scouring = "Any item with a rarity.",
		chaos = "Only an item with a rarity; bound modifiers stay.",
		divine = "Not on an item with a bound modifier.",
		sockets = "Any gear except uniques (their socket count is fixed); gems already socketed stay.",
		tempering = "Only an item with a rarity and a modifier that is not bound.",
		binding = string.format("Only an item with a rarity; bound modifiers per item: %d up to %s, %d from %s.",
			M.config.bind.max[1], C.rarityName(4), M.config.bind.max[5], C.rarityName(5)),
		excision = "Only an item with a rarity and a modifier that is not bound.",
		reforging = "Only an item with a rarity and a modifier that is not bound.",
		ruin = "Only an item with a rarity and a modifier; a ruined item can never be changed again.",
		whetstone = string.format("Only an item with a rarity and a modifier, below its quality cap (%d%%, %d%% from %s).",
			M.config.quality.cap, M.config.quality.capHigh, C.rarityName(M.config.quality.highFrom)),
		unveiling = "Only an item with a veiled modifier that is not revealed yet. The three choices are rolled once and stay the same every time the window opens."
	}
	for _, orb in ipairs(C.config.orbs) do
		local p = {orb.text}
		local rules = {"Uniques, ruined items and stacks are refused; the crafting bench shows what an orb would do before you use it.",
			"Used directly: Use with on the orb, then click the item."}
		if reasons[orb.key] then
			table.insert(rules, 1, reasons[orb.key])
		end
		if orb.key == "sockets" then
			rules = {orb.text, string.format("Sockets by kind at most: %s; by rarity at most %s (Common-Rare .. Cosmic-Transcendent).",
				(function()
					local parts = {}
					for _, k in ipairs({"weapon", "weapon2h", "armor", "shield", "helmet", "legs", "boots", "jewel", "other"}) do
						parts[#parts + 1] = (k == "weapon2h" and "two-handed" or (KIND_SHORT[k] or k):lower()) .. " " .. G.config.kindMax[k]
					end
					return table.concat(parts, ", ")
				end)(), table.concat(G.config.rarityMax, "/", 2)),
				"Spell supports: opening a spell's third support socket costs " .. D.S.config.third.orbs .. " of these."}
		end
		local sections = {{h = "What it does", p = p}, {h = "Rules", p = rules}}
		if orb.keyText then
			sections[#sections + 1] = {h = "On a Rift Key", p = {orb.keyText}}
		end
		local srcRows = sourcesOf(D, orb.id, orb.key)
		if orb.key == "unveiling" and ChaosVeiled then
			local vRows, vPool, vTiers = Gen.veiledSections(ChaosVeiled)
			for _, r in ipairs(vRows) do
				srcRows[#srcRows + 1] = r
			end
			sections[#sections + 1] = vPool
			sections[#sections + 1] = vTiers
		end
		sections[#sections + 1] = {h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = srcRows}
		out[#out + 1] = {id = "orb:" .. orb.key, name = orb.name, color = COLORS.orb, sub = orb.text,
			f = {group = "orb"}, items = {orb.id}, sections = sections}
	end
	-- the base world's renamed currency items without a crafting use
	local crafting = {}
	for _, orb in ipairs(C.config.orbs) do
		crafting[orb.id] = true
	end
	for _, r in ipairs(O.config.renames) do
		if not crafting[r.id] then
			out[#out + 1] = {id = "cur:" .. r.id, name = r.name, color = COLORS.currency,
				sub = "Currency of the character upgrades; no crafting use.", f = {group = "currency"}, items = {r.id},
				sections = {{h = "What it does", p = {"Spent on character upgrades of the base world. No orb effect on items: it never changes or copies an item."}},
					{h = "Sources", p = {"Monster loot lists of the base world."}}}}
		end
	end
	-- rune shards (salvage)
	local sv = D.salvage
	local shardRows = {}
	for r = 1, #sv.baseShards do
		shardRows[#shardRows + 1] = {C.rarityName(r), Gen.num(sv.baseShards[r]), Gen.per10k(sv.orbChance[r])}
	end
	local recipeRows, recipeLinks = {}, {}
	for _, r in ipairs(sv.recipes) do
		recipeRows[#recipeRows + 1] = {orbName(D, r.key), Gen.num(r.cost)}
		recipeLinks[#recipeLinks + 1] = "orb:" .. r.key
	end
	out[#out + 1] = {id = "cur:shard", name = (sv.shard.name:gsub("^%l", string.upper):gsub(" %l", string.upper)),
		color = COLORS.currency, sub = "Salvage gear with a rarity into shards; combine shards into orbs.",
		f = {group = "currency"}, items = {sv.shard.id}, sections = {
			{h = "What it does", p = {sv.shard.description,
				string.format("Shards per item: the rarity's base, up to %d%% more by item level, +%d per modifier of T%d or better, +%d per empty socket. Uniques are never salvaged.",
					floor(sv.levelBonus * 100 + 0.5), sv.perHighTier, sv.highTier, sv.perSocket)}},
			{h = "Salvage by rarity", cols = {"Rarity", "Base shards", "Whole orb chance"}, w = {36, 30, 34}, rows = shardRows},
			{h = "Recipes", cols = {"Orb", "Shards"}, w = {60, 40}, rows = recipeRows, links = recipeLinks}}}
	-- rift and omen items
	local rf, om = D.rift, D.rift.omen
	out[#out + 1] = {id = "cur:riftkey", name = "Rift Key", color = COLORS.rift,
		sub = "Opens a rift of its tier; carries up to " .. rf.key.maxMods .. " map modifiers.", f = {group = "rift"},
		items = {rf.key.itemId},
		sections = {{h = "What it does", p = {string.format("Use it in a protection zone: you and up to %d party members within %d sqm enter a rift of the key's tier (%d tiers). See the Rift tab for its modifiers.",
			rf.maxPlayers - 1, rf.partyRange, rf.maxTier)}}, {h = "More", p = {"Rift tab > Rift Keys has the sources and the orbs that work on keys."},
			links = {"rift:keys"}}}}
	out[#out + 1] = {id = "cur:omenfragment", name = (om.fragment.name:gsub("^%l", string.upper):gsub(" %l", string.upper)),
		color = COLORS.rift, sub = om.fragment.description, f = {group = "rift"}, items = {om.fragment.id},
		sections = {{h = "What it does", p = {om.fragment.description}},
			{h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = {
				{"Rift chest", string.format("Rifts of tier %d or more: %d + %d per tier above %d for every finisher.", om.minTier,
					om.chest.base, om.chest.perTier, om.minTier)},
				{"Rift monsters", string.format("Rare %d%%, legendary %d%% of the time in rifts of tier %d or more.",
					om.eliteChance.rare, om.eliteChance.legendary, om.minTier)}}}}}
	out[#out + 1] = {id = "cur:omenkey", name = (om.key.name:gsub("^%l", string.upper):gsub(" %l", string.upper)),
		color = COLORS.rift, sub = om.key.description, f = {group = "rift"}, items = {om.key.id},
		sections = {{h = "What it does", p = {om.key.description, string.format("Bound from %d omen fragments; it opens one guardian's arena (Rift tab > Omens).", om.keyCost)}}}}
	-- the crafting orbs in the bench's order, then the other currency and the rift items by name
	local orbs, rest = {}, {}
	for _, e in ipairs(out) do
		if e.f.group == "orb" then
			orbs[#orbs + 1] = e
		else
			rest[#rest + 1] = e
		end
	end
	for _, e in ipairs(sortByName(rest)) do
		orbs[#orbs + 1] = e
	end
	return orbs
end

-- ---------------------------------------------------------------------------------------------------------------
-- gems
-- ---------------------------------------------------------------------------------------------------------------
function Gen.gemEntries(D)
	local G = D.G
	local cfg = G.config
	local out = {}
	local function effectCell(e, tier)
		if not e then
			return ""
		end
		return G.effectText(e.effect, e.values[tier], e.values2 and e.values2[tier] or nil)
	end
	local function capText(e)
		local def = cfg.effects[e.effect]
		if def.spread then
			return def.label .. ": spread over each elemental resistance, under their caps"
		elseif def.fmt == "pair" then
			return string.format("%s at most %d%%, %s at most %d%%", def.label, def.cap, def.label2, def.cap2)
		elseif def.fmt == "flat" then
			return string.format("%s at most %d", def.label, def.cap)
		end
		return string.format("%s at most %d%%", def.label, def.cap)
	end
	local dropParts = {}
	for _, t in ipairs(TIER_ORDER) do
		dropParts[#dropParts + 1] = TIER_NAME[t] .. " " .. Gen.per10k(cfg.drop.chance[t])
	end
	for ti, t in ipairs(cfg.types) do
		local name = t.name:gsub("^%l", string.upper)
		-- the server ids of its tiers (chaos_gems_config.lua: firstId + (type - 1) x tiers + tier - 1), for the item finder
		local gemIds = {}
		for tier = 1, #cfg.tiers do
			gemIds[tier] = cfg.firstId + (ti - 1) * #cfg.tiers + (tier - 1)
		end
		local rows = {}
		for tier = 1, #cfg.tiers do
			rows[tier] = {cfg.tiers[tier], effectCell(t.weapon, tier), effectCell(t.armour, tier), effectCell(t.jewel, tier),
				Gen.num(cfg.removeCost[tier])}
		end
		out[#out + 1] = {id = "gem:" .. t.key, name = name, color = t.color,
			sub = string.format("Weapon: %s; armour: %s; jewellery: %s", cfg.effects[t.weapon.effect].label,
				cfg.effects[t.armour.effect].label, cfg.effects[t.jewel.effect].label),
			f = {group = "gem"}, items = gemIds,
			sections = {
				{h = "Effects by tier", p = {"A gem gives one effect, chosen by the item it sits in: weapons, armour (every other gear) or jewellery (amulets and rings). Remove = gold to take it out intact (Shatter is free and destroys it)."},
					cols = {"Tier", "Weapon", "Armour", "Jewellery", "Remove"}, w = {14, 24, 24, 24, 14}, rows = rows},
				{h = "Caps (all gems together)", p = {capText(t.weapon) .. ".", capText(t.armour) .. ".", capText(t.jewel) .. "."}},
				{h = "Combining", p = {string.format("Three gems of one type and tier make one of the next tier (%s).",
					table.concat(cfg.tiers, " > "))}},
				{h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = {
					{"Monster drops", "Per kill by monster tier: " .. table.concat(dropParts, ", ") .. "; the gem type is random, the tier by monster level."},
					{"Bounty board", string.format("Finished contracts: hunt %d%%, elite %d%%, boss %d%% chance of a gem; %d in the weekly chest.",
						cfg.rewards.bounty.chance.hunt, cfg.rewards.bounty.chance.elite, cfg.rewards.bounty.chance.boss,
						cfg.rewards.bountyWeekly.count)},
					{"Rift chest", string.format("%s + %s per rift tier.", Gen.num(cfg.rewards.rift.base), Gen.num(cfg.rewards.rift.perTier))},
					{"World boss", string.format("%d for every eligible player.", cfg.rewards.worldboss.count)}}}
			}}
	end
	-- sockets
	local rarityRows = {{"No rarity", Gen.num(cfg.rarityMax[1])}}
	local names = D.C.config.rarityNames
	for i = 2, #cfg.rarityMax do
		local a, b = (i - 2) * 3 + 1, (i - 1) * 3
		rarityRows[#rarityRows + 1] = {names[a] .. " - " .. names[b], Gen.num(cfg.rarityMax[i])}
	end
	local kindRows = {}
	for _, k in ipairs({"weapon", "weapon2h", "shield", "helmet", "armor", "legs", "boots", "jewel", "other"}) do
		kindRows[#kindRows + 1] = {k == "weapon2h" and "Two-handed weapon" or KIND_SHORT[k], Gen.num(cfg.kindMax[k])}
	end
	local dropRows = {}
	for i, w in ipairs(cfg.dropWeights) do
		local total = w[1] + w[2] + w[3] + w[4]
		local a, b = (i - 1) * 3 + 1, i * 3
		dropRows[#dropRows + 1] = {names[a] .. " - " .. names[b], Gen.share(w[1], total), Gen.share(w[2], total),
			Gen.share(w[3], total), Gen.share(w[4], total)}
	end
	out[#out + 1] = {id = "gem:sockets", name = "Sockets", color = COLORS.basics, sub = "How many sockets gear can have.",
		f = {group = "sockets"},
		sections = {
			{h = "Sockets", p = {string.format("Gear has 0 to %d sockets: the lower of its kind's and its rarity's maximum. Uniques have %d fixed socket. Every orb keeps sockets and gems.",
				G.MAX_SOCKETS, cfg.uniqueSockets), "Socket a gem by Use with on the gem, then click the item."}},
			{h = "Most sockets by kind", cols = {"Kind", "Sockets"}, w = {60, 40}, rows = kindRows},
			{h = "Most sockets by rarity", cols = {"Rarity", "Sockets"}, w = {60, 40}, rows = rarityRows},
			{h = "Sockets on drops", cols = {"Rarity", "0", "1", "2", "3"}, w = {36, 16, 16, 16, 16}, rows = dropRows},
			{h = "Orb of Sockets", p = {cfg.socketOrb.text}, links = {"orb:sockets"}}
		}}
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- uniques
-- ---------------------------------------------------------------------------------------------------------------
local SLOT_KIND = {sword = "weapon", axe = "weapon", club = "weapon", distance = "weapon", wand = "weapon", fist = "weapon",
	head = "helmet", body = "armor", legs = "legs", feet = "boots", necklace = "jewel", ring = "jewel", shield = "shield"}
local SLOT_NAME = {sword = "Sword", axe = "Axe", club = "Club", distance = "Distance weapon", wand = "Wand / rod", fist = "Fist weapon",
	head = "Helmet", body = "Body armour", legs = "Legs", feet = "Boots", necklace = "Amulet", ring = "Ring", shield = "Shield"}
local ATTR_ORDER = {"Attack", "Defense", "Extra Defense", "Armor", "Hit Chance", "Range"}

local function uniqueStats(D, spec)
	local out = {}
	for _, k in ipairs(ATTR_ORDER) do
		local v = spec.attributes[k]
		if v then
			out[#out + 1] = k == "Extra Defense" and ("Extra Defense +" .. v) or (k .. " " .. v)
		end
	end
	local keys = {}
	for k in pairs(spec.custom) do
		keys[#keys + 1] = k
	end
	table.sort(keys, function(a, b) return a:lower() < b:lower() end)
	local done = {}
	for _, k in ipairs(keys) do
		local a = D.C.affixOf(k)
		if a and not done[a.key] then
			done[a.key] = true
			if a.group == "special" then
				local chance = spec.custom[a.key] or spec.custom[a.key:gsub("^rarity_%l", string.upper)] or 0
				local amount = spec.custom[a.key2] or 0
				for ck, cv in pairs(spec.custom) do
					if ck:lower() == a.key:lower() then
						chance = cv
					elseif ck:lower() == a.key2:lower() then
						amount = cv
					end
				end
				out[#out + 1] = string.format("%s: chance %s%%, %s %s%%", affixName(a), Gen.signed(chance),
					a.label == "Critical Chance" and "damage" or "amount", Gen.signed(amount))
			elseif a.group == "absorb" then
				out[#out + 1] = string.format("%s Absorb %s%%", a.label, Gen.signed(spec.custom[k]))
			elseif a.group == "skill" then
				out[#out + 1] = string.format("%s %s", a.label == "Magic" and "Magic Level" or a.label, Gen.signed(spec.custom[k]))
			end
		elseif not a then
			local low = k:lower()
			local skip = false
			for _, s in ipairs(D.C.specials) do
				if s.key2:lower() == low then
					skip = true
				end
			end
			if not skip then
				out[#out + 1] = k .. " " .. tostring(spec.custom[k])
			end
		end
	end
	return out
end

-- "tiers 1-3 magic, 4-6 rare, 7-10 legendary, 11+ boss" (rift_config.lua reward.lootTier)
local function riftLootTiers(D)
	local parts, from = {}, 1
	for _, row in ipairs(D.rift.reward.lootTier) do
		local upTo = math.min(row[1], D.rift.maxTier)
		parts[#parts + 1] = (upTo >= D.rift.maxTier and from < D.rift.maxTier and row[1] > D.rift.maxTier)
			and string.format("%d+ %s", from, row[2]) or string.format("%s %s", Gen.range(from, upTo), row[2])
		from = row[1] + 1
	end
	return "tiers " .. table.concat(parts, ", ")
end

function Gen.uniqueEntries(D)
	local lu = D.loot.unique
	local worldBosses = {}
	for _, b in ipairs(D.worldBoss and D.worldBoss.bosses or {}) do
		worldBosses[b.name] = true
	end
	local setOf = {}
	for _, set in ipairs(D.itemSets and D.itemSets.sets or {}) do
		for _, p in ipairs(set.pieces) do
			setOf[p.id] = set.name
		end
	end
	local out = {}
	for _, u in ipairs(D.uniques) do
		local spec = D.specs[u.id]
		local stats = spec and uniqueStats(D, spec) or {}
		local statLines = #stats > 0 and stats or {"The base item's own stats (no extra stats of its own)."}
		local chances = {}
		for _, t in ipairs(TIER_ORDER) do
			if (lu.tierRank[t] or 0) >= (lu.tierRank[u.minTier] or 0) and (lu.tierMult[t] or 0) > 0
					and (not u.bossOnly or t == "boss") then
				chances[#chances + 1] = TIER_NAME[t] .. " " .. Gen.per10k(math.min(lu.maxChance, u.chance * lu.tierMult[t]))
			end
		end
		local monsters, wbs = {}, {}
		for _, m in ipairs(u.monsters or {}) do
			if worldBosses[m] then
				wbs[#wbs + 1] = m
			else
				monsters[#monsters + 1] = m
			end
		end
		local sources = {}
		sources[#sources + 1] = {"Monster drops", string.format("%s monsters%s: per kill %s (x item find).",
			u.bossOnly and "Boss" or ("Only " .. TIER_NAME[u.minTier]:lower() .. " or stronger"),
			u.bossOnly and "" or "", table.concat(chances, ", "))}
		if #monsters > 0 then
			sources[#sources + 1] = {u.bossOnly and "Bosses" or "Monsters", table.concat(monsters, ", ") .. "."}
		end
		if #wbs > 0 then
			local wb = D.worldBoss.reward
			sources[#sources + 1] = {"World bosses", table.concat(wbs, ", ") .. string.format(": a corpse drop, and every eligible player has %s (+ share x %s) to get a boss-only unique of that boss.",
				Gen.per10k(wb.uniqueChance), Gen.per10k(wb.uniqueShareBonus))}
		end
		if u.ascended and D.uber then
			-- the Ascended uniques: only their bosses (uber.lua), never a rift or Omen chest
			local ra, rc = D.uber.reward.ascended, D.uber.reward.cinder
			sources[#sources + 1] = {"Ascended spoils", string.format("Every finisher of a listed boss: %d unique rolls (x%s find) " ..
				"after an Ascended Omen, %d (x%s find) after the Cinderheart.", ra.uniqueRolls, Gen.num(ra.uniqueFind),
				rc.uniqueRolls, Gen.num(rc.uniqueFind))}
		else
			sources[#sources + 1] = {"Rift chest", "One unique roll at the loot tier of the rift (" .. riftLootTiers(D) .. ")."}
			sources[#sources + 1] = {"Omen guardian chest", string.format("%d unique rolls at the boss tier over every unique, x%s find.",
				D.rift.omen.reward.uniqueRolls, Gen.num(D.rift.omen.reward.uniqueFind))}
		end
		local rules = {setOf[u.id] and string.format("A unique keeps its stats: no orb changes it. As a set piece it salvages for %d rune shards.",
				D.salvage.setPieceShards or 0) or "A unique keeps its stats: no orb changes it and it is never salvaged.",
			string.format("%d socket, fixed (gems may be socketed and taken out).", D.G.config.uniqueSockets)}
		if u.season then
			rules[#rules + 1] = string.format("Season unique: during season %d it drops only for that season's characters, afterwards for everyone.", u.season)
		end
		if setOf[u.id] then
			rules[#rules + 1] = "Part of the set " .. setOf[u.id] .. ": its bonuses are on the Sets tab."
		end
		local kind = SLOT_KIND[u.slot] or "other"
		local itemRows = {{"Slot", SLOT_NAME[u.slot] or u.slot}, {"Required level", Gen.num(u.level)}}
		if spec and spec.equip and spec.equip.lines and #spec.equip.lines > 0 then
			-- a unique with an equip rule of its own (chaos_unique_equip.lua): the class lines that may wear it
			local lines = spec.equip.lines
			local text = #lines == 1 and lines[1] or (table.concat(lines, ", ", 1, #lines - 1) .. " and " .. lines[#lines])
			itemRows[#itemRows + 1] = {"Worn by", text .. " lines"}
		end
		itemRows[#itemRows + 1] = {"Drops from", TIER_NAME[u.minTier] .. (u.bossOnly and " (bosses only)" or " monsters and stronger")}
		local p = {}
		if spec then
			p[#p + 1] = spec.description
		end
		out[#out + 1] = {id = "unique:" .. u.id, name = u.name, color = COLORS.unique,
			sub = string.format("%s, level %d.%s", SLOT_NAME[u.slot] or u.slot, u.level,
				#stats > 0 and (" " .. table.concat(stats, ", ")) or ""),
			f = {kind = {kind}, level = u.level, source = u.bossOnly and "boss" or "monster", season = u.season and "season" or nil},
			items = {u.id},
			sections = {
				{h = "Description", p = p},
				{h = "Stats", p = statLines},
				{h = "Item", cols = {"", ""}, w = {35, 65}, rows = itemRows},
				{h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = sources},
				{h = "Rules", p = rules}
			}}
	end
	return sortByName(out)
end

-- ---------------------------------------------------------------------------------------------------------------
-- item sets (data/lib/chaos_item_sets.lua)
-- ---------------------------------------------------------------------------------------------------------------
local FAMILY_NAME = {melee = "Melee", ranged = "Ranged", caster = "Caster", support = "Healer / support", hybrid = "Hybrid"}
local PIECE_SLOT = {head = "Helmet", body = "Body armour", legs = "Legs", feet = "Boots", necklace = "Amulet", ring = "Ring",
	shield = "Shield", weapon = "Weapon"}

function Gen.setEntries(D)
	local S = D.itemSets
	local out = {}
	if not S then
		return out
	end
	local c = S.config.chase
	local uniqueIds = {}
	for _, u in ipairs(D.uniques) do
		uniqueIds[u.id] = true
	end
	for _, set in ipairs(S.sets) do
		local rows, links = {}, {}
		for _, p in ipairs(set.pieces) do
			rows[#rows + 1] = {p.name, (PIECE_SLOT[p.slot] or p.slot) .. (p.hands > 1 and " (two-handed: 2 pieces)" or ""),
				Gen.num(p.level)}
			links[#links + 1] = uniqueIds[p.id] and ("unique:" .. p.id) or ""
		end
		local bonusRows = {}
		for _, b in ipairs(set.bonuses) do
			bonusRows[#bonusRows + 1] = {Gen.num(b.n) .. " pieces", S.bonusText(b)}
		end
		local sources, src = {}, set.sources or {}
		if src.uniques then
			local u = src.uniques
			sources[#sources + 1] = {u.bossOnly and "World bosses" or "Monsters", table.concat(u.monsters or {}, ", ") ..
				string.format(": %s per kill and piece (x item find)%s.", Gen.per10k(math.min(D.loot.unique.maxChance,
					u.chance * (D.loot.unique.tierMult[u.minTier] or 0))), u.bossOnly
					and ", and the bosses' participation reward rolls them with the other boss uniques" or
					(" from " .. TIER_NAME[u.minTier]:lower() .. " monsters, " .. Gen.per10k(math.min(D.loot.unique.maxChance,
					u.chance * (D.loot.unique.tierMult.boss or 0))) .. " as bosses"))}
		elseif set.key == "embers" then
			sources[#sources + 1] = {"Monsters", "Each piece drops as the unique it always was: see its Uniques page."}
		end
		if src.rift then
			sources[#sources + 1] = {"Rift chest", string.format("%s rifts from key tier %d: %s per finisher's chest, +%s per tier above, at most %s.",
				src.rift.theme, src.rift.minTier, Gen.per10k(c.rift.base), Gen.per10k(c.rift.perTier), Gen.per10k(c.rift.max))}
		end
		if src.raid then
			sources[#sources + 1] = {"Ashen Sepulchre", string.format("Spoils of %s: %s per boss loot, %s from the final boss.",
				table.concat(src.raid, ", "), Gen.per10k(c.raid.boss), Gen.per10k(c.raid.final))}
		end
		if src.descent then
			sources[#sources + 1] = {"Ember Descent", string.format("Leaving from depth %d: %s, +%s per deeper room, +%s on a full clear, at most %s.",
				src.descent.minDepth, Gen.per10k(c.descent.base), Gen.per10k(c.descent.perDepth), Gen.per10k(c.descent.clear),
				Gen.per10k(c.descent.max))}
		end
		if src.dungeon then
			sources[#sources + 1] = {"Dungeons", string.format("Every clear: %s, +%s per difficulty step, at most %s.",
				Gen.per10k(c.dungeon.base), Gen.per10k(c.dungeon.perDifficulty), Gen.per10k(c.dungeon.max))}
		end
		if src.rift or src.raid or src.descent or src.dungeon then
			sources[#sources + 1] = {"Who", string.format("Characters of level %d or more (the set's level - %d); item find raises the chances.",
				math.max(1, set.level - c.levelBelow), c.levelBelow)}
		end
		local rules = {"A piece counts when it is worn in its slot and you have its level; the same piece twice counts once.",
			"A two-handed weapon counts as two pieces.",
			"Number bonuses add to your gear's modifiers under the same caps; a set never lifts a cap.",
			string.format("Pieces are uniques: no orb changes them, they keep one socket; salvage gives %d rune shards; a transmog look keeps the bonus.",
				D.salvage.setPieceShards or 0)}
		out[#out + 1] = {id = "set:" .. set.key, name = set.name, color = "#58c878",
			sub = string.format("%s, level %d, %d pieces. %s.", FAMILY_NAME[set.family] or set.family, set.level, set.total,
				set.classes),
			f = {family = set.family, level = set.level},
			sections = {
				{h = "Description", p = {set.lore}},
				{h = "Pieces", cols = {"Piece", "Slot", "Level"}, w = {40, 45, 15}, rows = rows, links = links},
				{h = "Bonuses", cols = {"Worn", "Bonus"}, w = {18, 82}, rows = bonusRows},
				{h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = sources},
				{h = "Rules", p = rules}
			}}
	end
	return sortByName(out)
end

-- ---------------------------------------------------------------------------------------------------------------
-- rift
-- ---------------------------------------------------------------------------------------------------------------
local function rewardText(r)
	if not r then
		return "none (a boon)"
	end
	local parts = {}
	if r.fixed then
		for _, k in ipairs({"quantity", "rarity", "experience"}) do
			if r.fixed[k] then
				parts[#parts + 1] = string.format("+%d%% %s", r.fixed[k], k)
			end
		end
		return table.concat(parts, ", ") .. " (flat)"
	end
	for _, k in ipairs({"quantity", "rarity", "experience"}) do
		if r[k] then
			parts[#parts + 1] = string.format("+%s%% %s", Gen.num(r[k]), k)
		end
	end
	return table.concat(parts, ", ") .. " per point"
end

function Gen.riftEntries(D)
	local R, cfg = D.R, D.rift
	local out = {}
	local windows = {}
	local lastTier = 0
	for _, w in ipairs(cfg.modTiers.window) do
		windows[#windows + 1] = string.format("keys of tier %d-%d roll %s-%s", lastTier + 1, w[1], R.tierName(cfg, w[2]),
			R.tierName(cfg, w[3]))
		lastTier = w[1]
	end
	for _, m in ipairs(cfg.mods) do
		local rows = {}
		if m.tiers then
			for t = 1, #m.tiers do
				local lo, hi = R.tierBounds(m, t)
				local raise = cfg.modTiers.capRaise[t]
				rows[#rows + 1] = {R.tierName(cfg, t), Gen.range(lo, hi),
					raise and string.format("caps +%d/+%d/+%d", raise.quantity, raise.rarity, raise.experience) or ""}
			end
		end
		local example = m.text:gsub("%%d", Gen.range(m.range[1], m.range[2])):gsub("%%%%", "%%")
		local p = {example .. ".", "Reward bonus: " .. rewardText(m.reward) .. "."}
		if m.boon then
			p[#p + 1] = "A boon: a pure reward without a reward bonus of its own."
		elseif m.side == "prefix" then
			p[#p + 1] = "Prefix: the monsters or the guardian get stronger."
		elseif m.side == "suffix" then
			p[#p + 1] = "Suffix: the players or the area get worse."
		end
		if m.note then
			p[#p + 1] = m.note
		end
		-- the modifiers it never shares a key with (same group, or excluded)
		local never = {}
		for _, o in ipairs(cfg.mods) do
			if R.modConflict and R.modConflict(m, o) then
				never[#never + 1] = o.name
			end
		end
		if #never > 0 then
			p[#p + 1] = "Never on a key with " .. table.concat(never, ", ") .. "."
		end
		p[#p + 1] = string.format("Roll weight %d; on keys of tier %d or higher.", R.modWeight(m), m.minTier or 1)
		local sections = {{h = "Effect", p = p}}
		if #rows > 0 then
			sections[#sections + 1] = {h = "Modifier tiers", p = {"The tier follows from the value; " .. table.concat(windows, ", ") .. "."},
				cols = {"Tier", "Value", "Raises the bonus caps"}, w = {16, 34, 50}, rows = rows}
		else
			sections[#sections + 1] = {h = "Modifier tiers", p = {"No tiers: value " .. Gen.range(m.range[1], m.range[2]) .. "."}}
		end
		out[#out + 1] = {id = "rift:" .. m.key, name = m.name, color = COLORS.rift,
			sub = example, f = {group = m.boon and "boon" or "mod", level = m.minTier or 1}, sections = sections}
	end
	sortByName(out)
	-- keys
	local orbRows, orbLinks = {}, {}
	for _, orb in ipairs(D.C.config.orbs) do
		if orb.keyText and (KEY_ORBS[orb.key] or orb.keyApply or orb.keyCheck) then
			orbRows[#orbRows + 1] = {orb.name, orb.keyText}
			orbLinks[#orbLinks + 1] = "orb:" .. orb.key
		end
	end
	local function weightsText(rows)
		local total, parts = 0, {}
		for _, r in ipairs(rows) do
			total = total + r[2]
		end
		for _, r in ipairs(rows) do
			parts[#parts + 1] = r[1] .. ": " .. Gen.share(r[2], total)
		end
		return table.concat(parts, ", ")
	end
	local mk = cfg.monsterKey
	local tierMult = {}
	for _, t in ipairs(TIER_ORDER) do
		tierMult[#tierMult + 1] = TIER_NAME[t] .. " x" .. Gen.num(mk.tierMult[t])
	end
	out[#out + 1] = {id = "rift:keys", name = "Rift Keys", color = COLORS.basics, sub = "Where keys come from and the orbs that work on them.",
		f = {group = "key"},
		sections = {
			{h = "Keys", p = {string.format("A key has a tier (1-%d) and up to %d modifiers. Modifiers on a drop: %s.", cfg.maxTier,
				cfg.key.maxMods, weightsText(cfg.modCount)),
				string.format("The modifiers make the rift harder and raise its rewards: quantity, rarity, experience, at most +%d%%/+%d%%/+%d%% (raised by tier IV and V modifiers).",
					cfg.bonusCap.quantity, cfg.bonusCap.rarity, cfg.bonusCap.experience)}},
			{h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = {
				{"Finished rift", string.format("%d%% + %d%% per modifier (at most %d%%) for a next key; %d%% + %d%% per modifier of those are one tier higher.",
					cfg.keyDrop.base, cfg.keyDrop.perMod, cfg.keyDrop.max, cfg.keyDrop.nextTier, cfg.keyDrop.nextPerMod)},
				{"Rift monsters", string.format("Rare %d%%, legendary %d%%: a key of the rift's tier.", cfg.eliteKeyChance.rare,
					cfg.eliteKeyChance.legendary)},
				{"Monsters", string.format("Tier-1 keys: %s per kill (%s) from monsters of hunting level %d or more and at least %d%% of yours.",
					Gen.num(mk.chance / 1000) .. "%", table.concat(tierMult, ", "), mk.minMonsterLevel, floor(mk.levelShare * 100 + 0.5))},
				{"Bounty board", string.format("Tier-1 key for a finished contract: hunt %d%%, elite %d%%, boss %d%%.", cfg.bountyKey.hunt,
					cfg.bountyKey.elite, cfg.bountyKey.boss)}}},
			{h = "Orbs on Rift Keys", cols = {"Orb", "On a key"}, w = {30, 70}, rows = orbRows, links = orbLinks}
		}}
	-- tiers
	local tierRows = {}
	for t = 1, #cfg.tiers do
		local row = cfg.tiers[t]
		tierRows[#tierRows + 1] = {Gen.num(t), Gen.num(row.minLevel), Gen.range(row.pick[1], row.pick[2])}
	end
	local rw = cfg.reward
	out[#out + 1] = {id = "rift:tiers", name = "Rift Tiers and Rewards", color = COLORS.basics,
		sub = "Level to enter, monsters and the chest of each tier.", f = {group = "key"},
		sections = {
			{h = "Tiers", p = {string.format("Tiers above %d reuse the last window: +%d levels to enter and +%d%% health, damage and +%d%% rewards per tier.",
				#cfg.tiers, cfg.beyond.minLevelStep, floor(cfg.beyond.health * 100 + 0.5), floor(cfg.beyond.reward * 100 + 0.5))},
				cols = {"Tier", "Level to enter", "Monster levels"}, w = {20, 40, 40}, rows = tierRows},
			{h = "The run", p = {cfg.layout and cfg.layout.enabled and string.format("Every rift is a new generated map: a cave system, an open waste, a ruined complex or a cave with ruined chambers, sometimes on two floors, with the guardian's arena in the far corner. Its size follows the key's tier: %s.",
					(function()
						local parts, from = {}, 1
						for _, row in ipairs(cfg.layout.sizes) do
							parts[#parts + 1] = string.format("tiers %d-%d %d x %d tiles, %d minutes", from, math.min(row[1], cfg.maxTier),
								row[2], row[2], floor(row[3] / 60))
							from = row[1] + 1
						end
						return table.concat(parts, "; ")
					end)()) or "",
				string.format("The guardian comes after %d%% of the monsters; %d shared lives + %d per extra player; up to %d players.",
				cfg.bossAt, cfg.lives.base, cfg.lives.perExtraPlayer, cfg.maxPlayers),
				R.densityOn and R.densityOn(cfg) and string.format("About %d monsters solo at tier 1 up to %d at tier %d on a map of typical size (+%d%% per extra player; a bigger map holds more), in packs of %d-%d over the whole map; about %d-%d alive at once, the rest gather ahead of you as you advance. Most monsters are husks: experience only. Magic and better monsters always carry loot, so a run drops about what fewer, tougher packs did.",
					floor(R.density(cfg, 1, 1).count), floor(R.density(cfg, cfg.maxTier, 1).count), cfg.maxTier,
					floor(cfg.density.count.perExtraPlayer * 100 + 0.5), cfg.density.size[1], cfg.density.size[2],
					R.liveCap(cfg, 1, nil, 1), R.liveCap(cfg, 1, nil, cfg.maxTier)) or "",
				cfg.party and string.format("Each extra player: +%d%% monster health in total (more packs, tougher monsters), +%d%% guardian health, +%d%% damage taken; every finisher's chest +%s%% (at most +%d%%) and +%s%% kill loot (at most +%d%%).",
					floor(cfg.party.healthPerExtraPlayer * 100 + 0.5), floor(cfg.boss.perExtraPlayer * 100 + 0.5),
					floor(cfg.party.damagePerExtraPlayer * 100 + 0.5), Gen.num(cfg.party.rewardPerExtraPlayer), cfg.party.rewardCap,
					Gen.num(cfg.party.lootPerExtraPlayer), cfg.party.lootCap) or nil}},
			{h = "Chest (per player)", p = {
				string.format("Gold: %d x tier squared to the bank.", rw.goldPerTier2),
				string.format("%s: %s + %s per tier; %s: %s + %s per tier.", orbName(D, "chaos"), Gen.num(rw.chaos.base),
					Gen.num(rw.chaos.perTier), orbName(D, "divine"), Gen.num(rw.divine.base), Gen.num(rw.divine.perTier)),
				string.format("Item rolls: %s + %s per tier from the rift monsters' loot, gear with a rarity; one currency roll and one unique roll.",
					Gen.num(rw.rolls.base), Gen.num(rw.rolls.perTier)),
				"Gems and spell supports too (Gems and Supports tabs). Gold, orbs and rolls x (1 + quantity bonus)."}}
		}}
	-- omens
	local om = cfg.omen
	local kindRows = {}
	for _, k in ipairs(om.kinds) do
		kindRows[#kindRows + 1] = {k.name, k.boss}
	end
	out[#out + 1] = {id = "rift:omens", name = "Omens", color = COLORS.basics, sub = "Guardian arenas opened with Omen Keys.",
		f = {group = "key"},
		sections = {
			{h = "Omens", p = {string.format("Rifts of tier %d or more give omen fragments; %d fragments bind an Omen Key of a random kind. The key opens that guardian's arena (level %d, %d minutes, the rift's lives). Omen keys have no modifiers.",
				om.minTier, om.keyCost, om.minLevel, floor(om.timeLimit / 60))}, links = {"cur:omenfragment"}},
			{h = "Guardians", cols = {"Omen", "Guardian"}, w = {35, 65}, rows = kindRows},
			{h = "Reward (per finisher)", p = {string.format("%s gold to the bank, %d %s, %d %s, %d item rolls of the guardian's loot (x%s rarity), %d unique rolls (x%d find), gems and supports as a tier %d rift. Drops in the arena get +%d item level.",
				om.reward.goldPerLevel and (Gen.num(om.reward.goldPerLevel) .. " x your level in") or Gen.num(om.reward.gold), om.reward.chaos, orbName(D, "chaos"), om.reward.divine, orbName(D, "divine"), om.reward.rolls,
				Gen.num(om.reward.rarityMult), om.reward.uniqueRolls, om.reward.uniqueFind, om.reward.asTier, D.M.config.itemLevel.omen)}}
		}}
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- spell supports
-- ---------------------------------------------------------------------------------------------------------------
function Gen.supportEntries(D)
	local S = D.S
	local cfg = S.config
	local out = {}
	local dropParts = {}
	for _, t in ipairs(TIER_ORDER) do
		dropParts[#dropParts + 1] = TIER_NAME[t] .. " " .. Gen.per10k(cfg.drop.chance[t])
	end
	for i, t in ipairs(cfg.supports) do
		local rows = {}
		for lv = 1, cfg.levels do
			rows[lv] = {cfg.levelNames[lv], S.effectText(S.runeId(i, lv))}
		end
		local p = {S.levelsText(t.key) .. ".", "Fits " .. S.fitsText(t) .. " spells."}
		if t.group then
			p[#p + 1] = "One " .. t.group .. " support per spell."
		end
		if cfg.caps[t.key] then
			p[#p + 1] = string.format("Cap on one spell: %d.", cfg.caps[t.key])
		end
		out[#out + 1] = {id = "support:" .. t.key, name = t.name, color = cfg.levelColors[4],
			sub = S.levelsText(t.key), f = {kind = t.fits},
			sections = {
				{h = "Effect", p = p},
				{h = "Levels", cols = {"Level", "Effect"}, w = {22, 78}, rows = rows},
				{h = "Sockets", p = {string.format("Every spell with an id has up to %d support sockets: the first once you may cast it, the second at a character level of the spell's level + %d (at least %d), the third at the spell's level + %d (at least %d), opened once per spell with %d Orbs of Sockets.",
					cfg.maxSockets, cfg.second.add, cfg.second.min, cfg.third.add, cfg.third.min, cfg.third.orbs)}},
				{h = "Sources", cols = {"Source", "How"}, w = {28, 72}, rows = {
					{"Monster drops", "Per kill: " .. table.concat(dropParts, ", ") .. "; the level by monster level."},
					{"Bounty board", string.format("Hunt %d%%, elite %d%%, boss %d%% per finished contract.", cfg.rewards.bounty.chance.hunt,
						cfg.rewards.bounty.chance.elite, cfg.rewards.bounty.chance.boss)},
					{"Rift chest", string.format("%s + %s per rift tier.", Gen.num(cfg.rewards.rift.base), Gen.num(cfg.rewards.rift.perTier))},
					{"World boss", string.format("%d for every eligible player.", cfg.rewards.worldboss.count)}}}
			}}
	end
	return sortByName(out)
end

-- ---------------------------------------------------------------------------------------------------------------
-- basics
-- ---------------------------------------------------------------------------------------------------------------
function Gen.basicsEntries(D)
	local M, C, G = D.M, D.C, D.G
	local out = {}
	local function add(id, name, sub, sections)
		out[#out + 1] = {id = "basics:" .. id, name = name, color = COLORS.basics, sub = sub, sections = sections}
	end
	add("items", "How items work", "Rarity, item level, tiers, prefixes and suffixes in short.", {
		{h = "In short", p = {
			string.format("Gear can carry a rarity: %d of them, from %s to %s. The rarity decides how many modifiers a new item gets and how many prefixes and suffixes it may carry.",
				#C.config.rarityNames, C.config.rarityNames[1], C.config.rarityNames[#C.config.rarityNames]),
			string.format("Every item has an item level (1-%d) from where it dropped. The item level decides which tiers its modifiers can roll: T1 (lowest) to T8 (highest).",
				M.config.itemLevel.max),
			"Prefixes are damage and defence, suffixes utility, resistances and speed.",
			string.format("Orbs change items (Orbs tab); the crafting bench shows what each would do. Legendary powers roll only from %s.",
				C.rarityName(M.config.powers.minRarity)),
			"Uniques have fixed stats and are never changed by orbs."}}})
	local rows = {}
	for r = 1, #C.config.rarityNames do
		local gi = G.rarityIndex and G.rarityIndex(r) or (floor((r + 2) / 3) + 1)
		rows[r] = {C.rarityName(r), Gen.num(M.modCount(r)), Gen.num(M.sideLimit(r)), Gen.num(M.maxMods(r)),
			Gen.num(M.maxBinds(r)), Gen.num(M.qualityCap(r)) .. "%", Gen.num(G.config.rarityMax[gi] or 0)}
	end
	add("rarity", "Rarity", "Modifier counts and limits per rarity.", {
		{h = "Rarity", p = {"New = modifiers on a new item; Sides = most prefixes (and suffixes); Max = what the Orb of Grafting fills up to; Binds = bound modifiers allowed; Quality = Whetstone cap; Sockets = most sockets by rarity."},
			cols = {"Rarity", "New", "Sides", "Max", "Binds", "Quality", "Sockets"}, w = {22, 11, 11, 11, 13, 16, 16}, rows = rows},
		{h = "Powers", p = {string.format("Legendary powers: from %s, %d per item.", C.rarityName(M.config.powers.minRarity),
			M.config.powers.maxPerItem)}}})
	local trows = {}
	for t = 1, M.config.maxTier do
		trows[t] = {"T" .. t, Gen.num(M.config.tierLevels[t]), Gen.num(M.config.tierWeights[t])}
	end
	local odds = {}
	for _, lv in ipairs({1, 15, 30, 50, 70, 95, 120, 140, 150}) do
		odds[#odds + 1] = {Gen.num(lv), Gen.oddsText(M, lv)}
	end
	add("tiers", "Tiers", "T1-T8: the item level each tier needs and the odds.", {
		{h = "Tiers", p = {string.format("A modifier rolls among the best %d tiers its item level allows, weighted (higher tiers are rarer).",
			M.config.tierWindow)}, cols = {"Tier", "Item level", "Weight"}, w = {30, 35, 35}, rows = trows},
		{h = "Odds by item level", cols = {"Item level", "Tier odds"}, w = {22, 78}, rows = odds}})
	local il = M.config.itemLevel
	local crows = {}
	for _, p in ipairs(il.curve) do
		crows[#crows + 1] = {Gen.num(p[1]), Gen.num(p[2])}
	end
	local bonus = {}
	for _, t in ipairs(TIER_ORDER) do
		bonus[#bonus + 1] = TIER_NAME[t] .. " +" .. il.tierBonus[t]
	end
	add("itemlevel", "Item level", "Where the item level of a drop comes from.", {
		{h = "Item level", p = {
			string.format("A drop's item level follows the monster's level along the curve below (straight lines in between), then: %s; inside a rift +%d per rift tier (at most +%d); an Omen arena +%d more; at most %d.",
				table.concat(bonus, ", "), il.riftPerTier, il.riftMax, il.omen, il.max),
			string.format("Fixed: world boss drops and rewards %d, store gear %d, the tutorial's gear %d.", il.worldBoss, il.store, il.tutorial),
			"Orbs keep the item level."},
			cols = {"Monster level", "Item level"}, w = {50, 50}, rows = crows}})
	add("sides", "Prefixes and suffixes", "What a prefix and a suffix are.", {
		{h = "Sides", p = {"Prefixes: damage and defence (skills, critical hits, weapon elements, block, dodge, reflect, thorns, penetration, ailments...).",
			"Suffixes: utility, resistances and speed (absorbs, leech, attack and movement speed, life and mana on kill or hit, find, experience...).",
			"A new item is rolled until its count or both sides are full; the Orb of Grafting only adds on a side that is open. An Orb of Ruin can give one extra slot on one side."}}})
	local q = M.config.quality
	local ruin = D.O.config.ruin
	add("quality", "Quality, binding and ruin", "Whetstones, bound modifiers and the Orb of Ruin.", {
		{h = "Quality", p = {string.format("Each Whetstone adds %d%% quality, up to %d%% (%d%% from %s). Every modifier value is multiplied by (100 + quality) / 100, rounded.",
			q.perStone, q.cap, q.capHigh, C.rarityName(q.highFrom))}, links = {"orb:whetstone"}},
		{h = "Binding", p = {"A bound modifier is left alone by Tempering, Unmaking, Excision, Reforging and Upheaval. Only an Orb of Erasure frees it (and wipes the item). An item with a bound modifier refuses the Orb of Fate."}, links = {"orb:binding"}},
		{h = "Ruin", p = {string.format("The Orb of Ruin: %d%% the item improves (%d%% of those one tier more on every unbound modifier, else an extra modifier above the side limit, once per item), %d%% nothing, %d%% it is ruined: no orb changes it any more.",
			ruin.improve, ruin.tiers, ruin.nothing, ruin.ruin)}, links = {"orb:ruin"}}})
	local bb = {}
	for r = 1, #C.config.baseBonus do
		local b = C.config.baseBonus[r]
		bb[r] = {C.rarityName(r), Gen.range(b[1], b[2])}
	end
	add("basebonus", "Base stat bonus", "Attack, defence, armour and hit chance from the rarity.", {
		{h = "Base stats", p = {"An item with a rarity also gets a small bonus to its attack, defence, armour and hit chance, once: min + item level x (max - min + 1) / 100."},
			cols = {"Rarity", "Bonus (min-max)"}, w = {50, 50}, rows = bb}})
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- the whole codex
-- ---------------------------------------------------------------------------------------------------------------
local function options(list)
	local out = {}
	for _, o in ipairs(list) do
		out[#out + 1] = {o[1], o[2]}
	end
	return out
end

-- drop the options of a tab's filters that no entry has (an empty list is no help); "ilvl" options stay
function Gen.pruneOptions(tab)
	for _, f in ipairs(tab.filters) do
		if f.match ~= "ilvl" then
			local keep = {}
			for i, o in ipairs(f.options) do
				local used = i == 1
				for _, e in ipairs(tab.entries) do
					local v = e.f and e.f[f.key]
					if used then
						break
					elseif f.match == "has" and type(v) == "table" then
						for _, x in ipairs(v) do
							used = used or x == o[1]
						end
					elseif f.match == "max" then
						used = tonumber(v) ~= nil and tonumber(v) <= tonumber(o[1])
					else
						used = v == o[1]
					end
				end
				if used then
					keep[#keep + 1] = o
				end
			end
			f.options = keep
		end
	end
end

-- the professions' materials (professions_config.lua): one entry per material and one about the professions
function Gen.materialEntries(D)
	local P = D.prof
	if not P then
		return {}
	end
	local out = {}
	local names = {}
	for _, p in ipairs(P.professions) do
		names[p.key] = p
	end
	local slots = {}
	for _, v in ipairs(P.demand.slots) do
		slots[#slots + 1] = "x" .. Gen.num(v)
	end
	local b = P.broker
	local bonusRows = {}
	for _, lv in ipairs({10, 25, 50, 75, 100}) do
		bonusRows[#bonusRows + 1] = {Gen.num(lv), Gen.num(math.min(P.bonus.cap, math.floor(4 * (lv - 1) * P.bonus.perLevel * 100 + 0.5) / 100)) .. "%"}
	end
	out[#out + 1] = {id = "mat:professions", name = "The professions", color = COLORS.basics,
		sub = "Gather materials, sell them to a Material Broker, earn an experience bonus", f = {group = "about"},
		sections = {
			{h = "What they are", p = {"Four gathering professions, each with its own level 1-" .. P.maxLevel .. ": " ..
				"Delving (ore veins), Wortcunning (herb patches), Flaying (corpses of beasts and reptiles) and Angling (fishing). " ..
				"They make no gear and no orbs: what you gather is sold to a Material Broker (one stands next to every temple).",
				"Every profession level above 1 adds " .. Gen.num(P.bonus.perLevel) .. "% experience from monsters, all four " ..
				"together at most +" .. Gen.num(P.bonus.cap) .. "% (every profession at " .. P.maxLevel .. ")."}},
			{h = "Experience bonus with all four at a level", cols = {"Level", "Bonus"}, w = {50, 50}, rows = bonusRows},
			{h = "Tiers", cols = {"Tier", "Profession", "Character", "Base price"}, w = {25, 25, 25, 25}, rows = (function()
				local rows = {}
				for _, t in ipairs(P.tiers) do
					rows[#rows + 1] = {t.name, Gen.num(t.profLevel), Gen.num(t.charLevel), Gen.num(t.price)}
				end
				return rows
			end)()},
			{h = "Selling", p = {string.format("Each week every material gets one of the demand multipliers %s (Economy > " ..
				"Professions shows the week's board). Per material and day the broker pays the full price for %d units, " ..
				"then %s of it up to %d, then takes no more until the next day.", table.concat(slots, ", "), b.fullPerDay,
				Gen.num(b.lateMult * 100) .. "%", b.capPerDay)}}
		}}
	for _, m in ipairs(P.materials) do
		local p, t = names[m.prof], P.tiers[m.tier]
		local where = {}
		if m.prof == "flaying" then
			where[#where + 1] = {"Corpses", string.format("Beasts and reptiles of hunting level %d+, flayed once with %s (%d%% " ..
				"chance of a hide).", t.charLevel, p.toolName, math.floor(P.flaying.chance * 100 + 0.5))}
		elseif m.prof == "angling" then
			local list = {}
			for _, a in ipairs(P.areas) do
				if a.fishing and a.tier == m.tier then
					list[#list + 1] = a.name
				end
			end
			if m.tier == P.angling.defaultTier then
				list[#list + 1] = "any other water"
			end
			where[#where + 1] = {"Waters", (#list > 0 and table.concat(list, ", ") or "none yet") .. string.format(
				" (%s; a catch on %d%% of the casts, one roll every %s s).", p.toolName, math.floor(P.angling.chance * 100 + 0.5),
				Gen.num(P.angling.rollMs / 1000))}
		else
			local list = {}
			for _, a in ipairs(P.areas) do
				if a.tier == m.tier and (a.nodes or {})[m.prof] then
					list[#list + 1] = a.name
				end
			end
			where[#where + 1] = {"Nodes", (#list > 0 and table.concat(list, ", ") or "none yet") .. " (" .. p.toolName ..
				"; every node is ready for you again " .. P.respawnMin .. " minutes after you gathered it)."}
		end
		out[#out + 1] = {id = "mat:" .. m.id, name = m.name:gsub("^%l", string.upper), color = t.color,
			sub = string.format("%s, tier %d (%s), base price %d gold", p.name, m.tier, t.name, t.price), f = {group = m.prof},
			items = {m.id},
			sections = {
				{h = "Gathering", p = {string.format("Needs %s %d; a character below level %d gets a lower tier instead.",
					p.name, t.profLevel, t.charLevel), m.description}, cols = {"Where", "How"}, w = {20, 80}, rows = where},
				{h = "Selling", p = {string.format("%d gold at the Material Broker, x the week's demand (%s); the full price " ..
					"for %d a day, then %s up to %d a day.", t.price, table.concat(slots, ", "), b.fullPerDay,
					Gen.num(b.lateMult * 100) .. "%", b.capPerDay)}}
			}}
	end
	return out
end

function Gen.loreOptions(D)
	local out = {{"", "Everything"}}
	for _, k in ipairs(D.lore and D.lore.kinds or {}) do
		out[#out + 1] = {k.key, k.en}
	end
	return out
end

-- the lore of the world (data/scripts/chaos/lore_data.lua): one entry each, English, then Brazilian Portuguese
function Gen.loreEntries(D)
	local L = D.lore
	if not L then
		return {}
	end
	local kinds = {}
	for _, k in ipairs(L.kinds) do
		kinds[k.key] = k
	end
	local out = {}
	for _, e in ipairs(L.entries) do
		local k = kinds[e.kind] or {en = e.kind}
		out[#out + 1] = {id = "lore:" .. e.id, name = e.name, color = COLORS.lore, sub = k.en, group = e.kind, f = {group = e.kind},
			sections = {{h = "Lore", p = e.en}, {h = "Em portugu\195\170s", p = e.pt}}}
	end
	return out
end

function Gen.build(D)
	local M, C = D.M, D.C
	D.shared = {}
	local mods, powers = {}, {}
	for _, a in ipairs(C.affixes()) do
		if a.def and M.isPower(a.def) then
			powers[#powers + 1] = Gen.powerEntry(D, a)
		else
			mods[#mods + 1] = Gen.modifierEntry(D, a)
		end
	end
	sortByName(mods)
	sortByName(powers)
	local kindOpts = {{"", "Any kind"}}
	for _, k in ipairs(Gen.KINDS) do
		kindOpts[#kindOpts + 1] = {k[1], KIND_SHORT[k[1]]}
	end
	local ilvlOpts = {{"", "Any item level"}}
	for t, lv in ipairs(M.config.tierLevels) do
		ilvlOpts[#ilvlOpts + 1] = {Gen.num(lv), "Item level " .. lv .. " (T" .. t .. ")"}
	end
	ilvlOpts[#ilvlOpts + 1] = {Gen.num(M.config.itemLevel.max), "Item level " .. M.config.itemLevel.max}
	local sideOpts = {{"", "Any side"}, {"prefix", "Prefixes"}, {"suffix", "Suffixes"}}
	local groupOpts = {{"", "Any group"}, {"chaos", "Chaos"}, {"absorb", "Absorbs"}, {"skill", "Skills"},
		{"special", "Critical / leech"}, {"element", "Weapon elements"}}
	local uniqueLevels = {{"", "Any level"}}
	for _, lv in ipairs({50, 70, 90, 110, 130, 150}) do
		uniqueLevels[#uniqueLevels + 1] = {Gen.num(lv), "Level " .. lv .. " or lower"}
	end
	local setLevels = {{"", "Any level"}}
	for _, lv in ipairs({100, 200, 300, 400, 800}) do
		setLevels[#setLevels + 1] = {Gen.num(lv), "Level " .. lv .. " or lower"}
	end
	local riftTiers = {{"", "Any key tier"}}
	for t = 1, 4 do
		riftTiers[#riftTiers + 1] = {Gen.num(t), "Key tier " .. t .. (t == 4 and "+" or "")}
	end
	local spellKinds = {{"", "Any spell"}}
	for _, k in ipairs(D.S.config.kinds) do
		spellKinds[#spellKinds + 1] = {k, (D.S.config.kindNames[k]:gsub("^%l", string.upper))}
	end
	local tabs = {
		{id = "modifiers", name = "Modifiers", entries = mods, filters = {
			{key = "side", label = "Side", match = "eq", options = options(sideOpts)},
			{key = "kind", label = "Kind", match = "has", options = kindOpts},
			{key = "group", label = "Group", match = "eq", options = groupOpts},
			{key = "ilvl", label = "Item level", match = "ilvl", options = ilvlOpts}}},
		{id = "powers", name = "Powers", entries = powers, filters = {
			{key = "side", label = "Side", match = "eq", options = options(sideOpts)},
			{key = "kind", label = "Kind", match = "has", options = kindOpts},
			{key = "ilvl", label = "Item level", match = "ilvl", options = ilvlOpts}}},
		{id = "orbs", name = "Orbs", entries = Gen.orbEntries(D), filters = {
			{key = "group", label = "Group", match = "eq", options = {{"", "Everything"}, {"orb", "Crafting orbs"},
				{"currency", "Currency"}, {"rift", "Rift and omen items"}}}}},
		{id = "gems", name = "Gems", entries = Gen.gemEntries(D), filters = {}},
		{id = "uniques", name = "Uniques", entries = Gen.uniqueEntries(D), filters = {
			{key = "kind", label = "Kind", match = "has", options = kindOpts},
			{key = "level", label = "Level", match = "max", options = uniqueLevels},
			{key = "source", label = "Source", match = "eq", options = {{"", "Any source"}, {"monster", "Monsters"},
				{"boss", "Bosses only"}}}}},
		{id = "sets", name = "Sets", entries = Gen.setEntries(D), filters = {
			{key = "family", label = "Family", match = "eq", options = {{"", "Any family"}, {"melee", "Melee"},
				{"ranged", "Ranged"}, {"caster", "Caster"}, {"support", "Healer / support"}, {"hybrid", "Hybrid"}}},
			{key = "level", label = "Level", match = "max", options = setLevels}}},
		{id = "rift", name = "Rift", entries = Gen.riftEntries(D), filters = {
			{key = "group", label = "Group", match = "eq", options = {{"", "Everything"}, {"mod", "Map modifiers"},
				{"boon", "Boons"}, {"key", "Keys, tiers, omens"}}},
			{key = "level", label = "Key tier", match = "max", options = riftTiers}}},
		{id = "supports", name = "Supports", entries = Gen.supportEntries(D), filters = {
			{key = "kind", label = "Spell", match = "has", options = spellKinds}}},
		{id = "materials", name = "Materials", entries = Gen.materialEntries(D), filters = {
			{key = "group", label = "Profession", match = "eq", options = {{"", "Every profession"}, {"about", "About"},
				{"delving", "Delving"}, {"wortcunning", "Wortcunning"}, {"flaying", "Flaying"}, {"angling", "Angling"}}}}},
		{id = "basics", name = "Basics", entries = Gen.basicsEntries(D), filters = {}},
		{id = "lore", name = "Lore", entries = Gen.loreEntries(D), filters = {
			{key = "group", label = "Group", match = "eq", options = Gen.loreOptions(D)}}}
	}
	for _, tab in ipairs(tabs) do
		Gen.pruneOptions(tab)
	end
	return {
		rarities = C.config.rarityNames,
		tierLevels = M.config.tierLevels,
		tierWeights = M.config.tierWeights,
		tierWindow = M.config.tierWindow,
		shared = D.shared,
		tabs = tabs
	}
end

function Gen.render(data)
	local head = {
		"-- GENERATED by server/tools/gen_codex_data.lua from the server data files below. Do not edit by hand:",
		"-- run  cd server && luajit tools/gen_codex_data.lua  after changing them (CI fails when this file is stale).",
		"--   " .. table.concat(Gen.SOURCES, ", "),
		"-- Format: client/overlay/modules/game_codex/codex.lua (top of the file).",
		"CodexData = " .. Gen.serialize(data, ""),
		"return CodexData",
		""
	}
	return table.concat(head, "\n")
end

-- counts per tab (the report and the tests)
function Gen.counts(data)
	local out = {}
	for _, t in ipairs(data.tabs) do
		out[#out + 1] = t.name .. " " .. #t.entries
	end
	return table.concat(out, ", ")
end

-- ---------------------------------------------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------------------------------------------
local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

function Gen.main(args)
	local check, out = false, OUT_DEFAULT
	for _, a in ipairs(args or {}) do
		if a == "--check" then
			check = true
		else
			out = a
		end
	end
	local data = Gen.build(Gen.load())
	local text = Gen.render(data)
	if check then
		if readFile(out) ~= text then
			io.stderr:write(out .. " is stale: run  cd server && luajit tools/gen_codex_data.lua\n")
			os.exit(1)
		end
		print("codex data up to date (" .. Gen.counts(data) .. ")")
		return
	end
	local f = assert(io.open(out, "wb"))
	f:write(text)
	f:close()
	print("wrote " .. out .. " (" .. Gen.counts(data) .. ")")
end

if not CODEX_GEN_NO_MAIN then
	Gen.main(arg)
end

return Gen
