-- Gems and sockets (ChaosGems): the pure part. Gear carries 0-3 sockets, gems of seven types and five tiers sit in
-- them and give one effect each, chosen by the kind of item they sit in (weapon / armour / jewellery).
-- Numbers: data/lib/chaos_gems_config.lua. Runtime: data/scripts/chaos/gems.lua (use-with, the effects on the
-- character) plus hooks in chaos_crafting.lua (description, Orb of Sockets, the bench), item_mods.lua (totals) and
-- loot.lua / bounty.lua / rift.lua / worldboss.lua (drops and rewards). Overview: server/README.md "Gems and sockets".
-- Tested by server/tests/gems_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible; no engine calls apart from item
-- attributes and ItemType reads.
--
-- Storage on the item (custom attributes, whole numbers):
--   chaos_sockets      number of sockets (absent = 0; a unique has config.uniqueSockets without the attribute)
--   chaos_gem1 .. 3    server id of the gem in that socket (absent = empty)
-- The description gets one section at its end: "Sockets (1/2): Flawless Ruby (Fire Damage +9%), empty."

ChaosGems = ChaosGems or {}
local G = ChaosGems
if not ChaosItemMods then
	dofile("data/lib/chaos_item_mods.lua")
end
local M = ChaosItemMods

G.config = dofile("data/lib/chaos_gems_config.lua")
local cfg = G.config

G.ATTR_SOCKETS = "chaos_sockets"
G.ATTR_GEM = "chaos_gem" -- .. index
G.MAX_SOCKETS = 3

-- random source; tests replace it (a, b inclusive, like math.random)
G.random = function(a, b)
	return math.random(a, b)
end

local floor = math.floor

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function num(v)
	if type(v) == "number" then
		return v
	end
	if type(v) == "userdata" or type(v) == "table" then
		local ok, n = pcall(function() return tonumber(v.value) end)
		return ok and n or nil
	end
	return tonumber(v)
end

local function customNumber(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	return ok and floor(num(v) or 0) or 0
end

local function capital(s)
	return (s:gsub("^%l", string.upper))
end

-- ---------------------------------------------------------------------------------------------------------------
-- gem ids
-- ---------------------------------------------------------------------------------------------------------------
G.TIERS = #cfg.tiers
G.TYPES = #cfg.types
G.byKey = {}
for i, t in ipairs(cfg.types) do
	t.index = i
	G.byKey[t.key] = t
end

function G.gemId(typeIndex, tier)
	return cfg.firstId + (typeIndex - 1) * G.TIERS + (tier - 1)
end

G.lastId = G.gemId(G.TYPES, G.TIERS)

-- {type = <type table>, tier = n} of a gem server id, or nil
function G.gemOf(id)
	id = tonumber(id)
	if not id or id < cfg.firstId or id > G.lastId then
		return nil
	end
	local n = id - cfg.firstId
	return {type = cfg.types[floor(n / G.TIERS) + 1], tier = n % G.TIERS + 1}
end

function G.isGem(id)
	return G.gemOf(id) ~= nil
end

function G.clientIdOf(typeIndex, tier)
	local t = cfg.types[typeIndex]
	if t.clientIdHigh and tier >= (cfg.highFrom or 99) then
		return t.clientIdHigh
	end
	return t.clientId
end

-- "Flawless Ruby" (title case, for texts); items.xml has the lower-case name
function G.gemName(id)
	local g = G.gemOf(id)
	if not g then
		return "unknown gem"
	end
	return cfg.tiers[g.tier] .. " " .. capital(g.type.name)
end

function G.itemName(typeIndex, tier, plural)
	local t = cfg.types[typeIndex]
	return (cfg.tiers[tier] .. " " .. (plural and t.plural or t.name)):lower()
end

-- ---------------------------------------------------------------------------------------------------------------
-- slot groups and effects
-- ---------------------------------------------------------------------------------------------------------------
-- weapon (any weapon), jewel (amulets, rings), armour (everything else that is gear: shields, helmets, armours,
-- legs, boots, gloves, belts...). nil when the item is no equipment.
function G.groupOfKind(kind)
	if kind == nil then
		return nil
	elseif kind == "weapon" then
		return "weapon"
	elseif kind == "jewel" then
		return "jewel"
	end
	return "armour"
end

function G.groupOf(item)
	return G.groupOfKind(M.kindOf(item))
end

-- the effect a gem gives in a slot group: {key, value, value2, def}
function G.effectOf(id, group)
	local g = G.gemOf(id)
	if not g or not group then
		return nil
	end
	local e = g.type[group]
	if not e then
		return nil
	end
	return {key = e.effect, value = e.values[g.tier] or 0, value2 = e.values2 and e.values2[g.tier] or nil,
		def = cfg.effects[e.effect]}
end

function G.effectText(key, value, value2)
	local def = cfg.effects[key]
	if not def then
		return tostring(key)
	end
	if def.fmt == "flat" then
		return string.format("%s +%d", def.label, value)
	elseif def.fmt == "pair" then
		return string.format("%s +%d%%, %s +%d%%", def.label, value, def.label2, value2 or 0)
	end
	return string.format("%s +%d%%", def.label, value)
end

-- "Flawless Ruby (Fire Damage +9%)"
function G.gemText(id, group)
	local e = G.effectOf(id, group)
	if not e then
		return G.gemName(id)
	end
	return string.format("%s (%s)", G.gemName(id), G.effectText(e.key, e.value, e.value2))
end

-- the three effects of a gem, one line ("weapon: Fire Damage +9%; armour: Max Health +130; jewellery: ...")
function G.gemSummary(id)
	local parts = {}
	for _, group in ipairs({"weapon", "armour", "jewel"}) do
		local e = G.effectOf(id, group)
		if e then
			parts[#parts + 1] = string.format("%s: %s", group == "jewel" and "jewellery" or group,
				G.effectText(e.key, e.value, e.value2))
		end
	end
	return table.concat(parts, "; ")
end

-- ---------------------------------------------------------------------------------------------------------------
-- sockets of an item
-- ---------------------------------------------------------------------------------------------------------------
local function isUnique(item)
	if ChaosCrafting and ChaosCrafting.isUnique then
		return ChaosCrafting.isUnique(item)
	end
	local ok, v = pcall(function() return item:getCustomAttribute("chaos_unique") end)
	return ok and v ~= nil
end
G.isUnique = isUnique

local function isGear(item)
	if ChaosCrafting and ChaosCrafting.isGear then
		return ChaosCrafting.isGear(item)
	end
	return M.kindOf(item) ~= nil
end

local function rarityOf(item)
	return clamp(customNumber(item, "rarity"), 0, 15)
end

local function twoHanded(item)
	local ok, slots = pcall(function() return ItemType(item:getId()):getSlotPosition() end)
	local bit = SLOTP_TWO_HAND or 2048
	return ok and floor((tonumber(slots) or 0) / bit) % 2 == 1
end

-- rarity tier for the socket tables: 1 = no rarity, 2 = Common-Rare ... 6 = Cosmic-Transcendent
function G.rarityIndex(rarity)
	rarity = clamp(floor(tonumber(rarity) or 0), 0, 15)
	if rarity == 0 then
		return 1
	end
	return math.ceil(rarity / 3) + 1
end

-- the most sockets this item may have (0 = none: not gear)
function G.maxSockets(item)
	if not item or not isGear(item) then
		return 0
	end
	if isUnique(item) then
		return cfg.uniqueSockets
	end
	local kind = M.kindOf(item)
	if not kind then
		return 0
	end
	if kind == "weapon" and twoHanded(item) then
		kind = "weapon2h"
	end
	local byKind = cfg.kindMax[kind] or cfg.kindMax.other or 1
	local byRarity = cfg.rarityMax[G.rarityIndex(rarityOf(item))] or 1
	return math.min(byKind, byRarity, G.MAX_SOCKETS)
end

function G.count(item)
	if not item then
		return 0
	end
	local n = customNumber(item, G.ATTR_SOCKETS)
	if n == 0 and isUnique(item) then
		n = cfg.uniqueSockets
	end
	return clamp(n, 0, G.MAX_SOCKETS)
end

-- gem id in socket i (0 = empty)
function G.gemAt(item, i)
	local id = customNumber(item, G.ATTR_GEM .. i)
	return G.isGem(id) and id or 0
end

-- {count, gems = {[i] = id or 0}, filled}
function G.read(item)
	local n = G.count(item)
	local out = {count = n, gems = {}, filled = 0}
	for i = 1, n do
		local id = G.gemAt(item, i)
		out.gems[i] = id
		if id > 0 then
			out.filled = out.filled + 1
		end
	end
	return out
end

-- set the number of sockets; gems stay in order (packed to the front), gems past the new count are returned
function G.setCount(item, n)
	n = clamp(floor(n), 0, G.MAX_SOCKETS)
	local gems = {}
	for i = 1, G.MAX_SOCKETS do
		local id = G.gemAt(item, i)
		if id > 0 then
			gems[#gems + 1] = id
		end
		pcall(function() item:removeCustomAttribute(G.ATTR_GEM .. i) end)
	end
	local dropped = {}
	for i, id in ipairs(gems) do
		if i <= n then
			item:setCustomAttribute(G.ATTR_GEM .. i, id)
		else
			dropped[#dropped + 1] = id
		end
	end
	if n > 0 then
		item:setCustomAttribute(G.ATTR_SOCKETS, n)
	else
		pcall(function() item:removeCustomAttribute(G.ATTR_SOCKETS) end)
	end
	return dropped
end

function G.firstFree(item)
	for i = 1, G.count(item) do
		if G.gemAt(item, i) == 0 then
			return i
		end
	end
	return nil
end

-- put a gem in the first free socket; returns the socket index or nil
function G.insert(item, gemId)
	if not G.isGem(gemId) then
		return nil
	end
	local i = G.firstFree(item)
	if not i then
		return nil
	end
	if isUnique(item) and customNumber(item, G.ATTR_SOCKETS) == 0 then
		item:setCustomAttribute(G.ATTR_SOCKETS, G.count(item))
	end
	item:setCustomAttribute(G.ATTR_GEM .. i, gemId)
	return i
end

-- take the gem out of socket i; returns its id or nil
function G.take(item, i)
	i = tonumber(i)
	if not i or i < 1 or i > G.count(item) then
		return nil
	end
	local id = G.gemAt(item, i)
	if id == 0 then
		return nil
	end
	item:removeCustomAttribute(G.ATTR_GEM .. i)
	return id
end

-- copy sockets and gems to another item (the orbs that remake an item, the loot layer's rolled copy)
function G.copy(from, to)
	local n = customNumber(from, G.ATTR_SOCKETS)
	if n <= 0 then
		return
	end
	to:setCustomAttribute(G.ATTR_SOCKETS, clamp(n, 0, G.MAX_SOCKETS))
	for i = 1, G.MAX_SOCKETS do
		local id = G.gemAt(from, i)
		if id > 0 then
			to:setCustomAttribute(G.ATTR_GEM .. i, id)
		end
	end
end

-- sum of the attack speed gems of a weapon (its own attack interval, chaos_item_mods.lua M.syncAttackSpeed)
function G.attackSpeedOf(item)
	if G.groupOf(item) ~= "weapon" then
		return 0
	end
	local total = 0
	for i = 1, G.count(item) do
		local e = G.effectOf(G.gemAt(item, i), "weapon")
		if e and e.key == "attackspeed" then
			total = total + e.value
		end
	end
	return total
end

-- ---------------------------------------------------------------------------------------------------------------
-- totals of a character
-- ---------------------------------------------------------------------------------------------------------------
-- every key present (0 when none); pairs as key and key .. "2"; res_all spread over its resistances; capped.
-- attackspeed is not a character total (it is the weapon's own interval).
function G.totals(items)
	local t = {}
	for key, def in pairs(cfg.effects) do
		if not def.spread and key ~= "attackspeed" then
			t[key] = 0
			if def.fmt == "pair" then
				t[key .. "2"] = 0
			end
		end
	end
	for _, item in ipairs(items or {}) do
		local group = G.groupOf(item)
		for i = 1, G.count(item) do
			local e = G.effectOf(G.gemAt(item, i), group)
			if e and e.key ~= "attackspeed" then
				if e.def and e.def.spread then
					for _, k in ipairs(e.def.spread) do
						t[k] = t[k] + e.value
					end
				elseif t[e.key] then
					t[e.key] = t[e.key] + e.value
					if e.def.fmt == "pair" then
						t[e.key .. "2"] = t[e.key .. "2"] + (e.value2 or 0)
					end
				end
			end
		end
	end
	for key, def in pairs(cfg.effects) do
		if t[key] and def.cap then
			t[key] = clamp(t[key], 0, def.cap)
		end
		if def.fmt == "pair" and def.cap2 and t[key .. "2"] then
			t[key .. "2"] = clamp(t[key .. "2"], 0, def.cap2)
		end
	end
	return t
end

-- a damage value scaled by percent, toward zero (may be negative): 100 * (100 + 10) / 100 = 110
function G.scale(value, pct)
	local a = floor(math.abs(value) * (100 + pct) / 100 + 1e-6)
	return value < 0 and -a or a
end

-- ---------------------------------------------------------------------------------------------------------------
-- description
-- ---------------------------------------------------------------------------------------------------------------
-- "Sockets (1/2): Flawless Ruby (Fire Damage +9%), empty."
function G.sectionText(item)
	local s = G.read(item)
	if s.count == 0 then
		return ""
	end
	local group = G.groupOf(item)
	local parts = {}
	for i = 1, s.count do
		parts[i] = s.gems[i] > 0 and G.gemText(s.gems[i], group) or "empty"
	end
	return string.format("Sockets (%d/%d): %s.", s.filled, s.count, table.concat(parts, ", "))
end

local SECTION = "%s*Sockets %(%d+/%d+%):[^%.]*%."

-- remove the sockets section from a description (anything around it stays)
function G.strip(text)
	text = text or ""
	local out = text:gsub(SECTION, "")
	return out
end

function G.append(text, item)
	local section = G.sectionText(item)
	text = G.strip(text):gsub("%s+$", "")
	if section == "" then
		return text
	end
	if text == "" then
		return section
	end
	-- after the engine's text ("... Element: Fire +5% dmg") a full stop, after a sentence a space
	return text .. (text:find("[%.!?]$") and " " or ". ") .. section
end

local function descriptionOf(item)
	local ok, d = pcall(function() return item:getAttribute(ITEM_ATTRIBUTE_DESCRIPTION) end)
	if ok and type(d) == "string" then
		return d
	end
	return ""
end

-- write the sockets section of an item's description. Items with a rarity text ("Level: N") go through
-- ChaosCrafting.rewriteDescription (which appends the section itself); others keep their own text (the items.xml
-- description when the item has none of its own) and get the section at the end.
function G.writeDescription(item)
	local old = descriptionOf(item)
	if (old:find("Level:%s*%-?%d+") or rarityOf(item) > 0) and ChaosCrafting and ChaosCrafting.rewriteDescription then
		return ChaosCrafting.rewriteDescription(item)
	end
	if old == "" then
		local ok, d = pcall(function() return ItemType(item:getId()):getDescription() end)
		old = ok and type(d) == "string" and d or ""
	end
	local text = G.append(old, item)
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
	M.sendUpdate(item) -- the client gets the new socket count (client attributes)
	return text
end

-- one line for tooltips ("Sockets 1/2: Flawless Ruby (Fire Damage +9%), empty"), "" without sockets
function G.summary(item)
	local s = G.sectionText(item)
	return (s:gsub("^Sockets %((%d+/%d+)%):", "Sockets %1:"):gsub("%.$", ""))
end

-- ---------------------------------------------------------------------------------------------------------------
-- rolls
-- ---------------------------------------------------------------------------------------------------------------
-- index of a weighted pick from a list of weights (nil when every weight is 0)
function G.pickIndex(weights, rand)
	rand = rand or G.random
	local total = 0
	for _, w in ipairs(weights) do
		total = total + w
	end
	if total <= 0 then
		return nil
	end
	local roll, acc = rand(1, total), 0
	for i, w in ipairs(weights) do
		acc = acc + w
		if roll <= acc then
			return i
		end
	end
	return #weights
end

-- sockets of a new gear drop with a rarity (before the item's maximum)
function G.rollDropCount(rarity, rand)
	local idx = G.rarityIndex(rarity) - 1
	if idx < 1 then
		return 0
	end
	local w = cfg.dropWeights[idx] or cfg.dropWeights[#cfg.dropWeights]
	return (G.pickIndex(w, rand) or 1) - 1
end

-- give a new drop its sockets (only an item without any); returns the count given
function G.rollDropSockets(item, rand)
	if not item or customNumber(item, G.ATTR_SOCKETS) > 0 or isUnique(item) then
		return 0
	end
	local max = G.maxSockets(item)
	if max <= 0 then
		return 0
	end
	local n = math.min(max, G.rollDropCount(rarityOf(item), rand))
	if n > 0 then
		item:setCustomAttribute(G.ATTR_SOCKETS, n)
	end
	return n
end

-- the Orb of Sockets: can it be used, and the range of the new count
G.reasons = {
	notGear = "This item cannot have sockets.",
	unique = "A unique item has a fixed socket; orbs cannot change it.",
	stack = "Orbs work on a single item.",
	same = "This item already has the most sockets it can have.",
	noSockets = "This item has no sockets.",
	noGem = "There is no gem in that socket.",
	full = "This item has no free socket. Take a gem out at the crafting bench (!craft) first.",
	notGem = "That is not a gem.",
	perfect = "Perfect gems are the best there are; they cannot be combined.",
	needThree = "You need three gems of the same kind and quality to combine them."
}

function G.orbRange(item)
	local max = G.maxSockets(item)
	local lo = math.max(1, G.read(item).filled)
	return lo, max
end

function G.orbCheck(item)
	if not item or not isGear(item) then
		return false, "notGear"
	end
	if isUnique(item) then
		return false, "unique"
	end
	local okCount, count = pcall(function() return item:getCount() end)
	if okCount and tonumber(count) and count > 1 then
		return false, "stack"
	end
	local lo, max = G.orbRange(item)
	if max <= 0 then
		return false, "notGear"
	end
	if lo >= max and G.count(item) == max then
		return false, "same"
	end
	return true
end

-- roll the new count (weights orbWeights, inside lo..max); returns new count, old count
function G.orbApply(item, rand)
	local lo, max = G.orbRange(item)
	local w = {}
	for n = 1, max do
		w[n] = n >= lo and (cfg.orbWeights[n] or 1) or 0
	end
	local old = G.count(item)
	local n = G.pickIndex(w, rand) or lo
	G.setCount(item, n)
	return n, old
end

function G.orbPreview(item)
	local lo, max = G.orbRange(item)
	if lo == max then
		return string.format("%d -> %d sockets", G.count(item), max)
	end
	return string.format("%d -> %d-%d sockets", G.count(item), lo, max)
end

-- ---------------------------------------------------------------------------------------------------------------
-- combining and removing
-- ---------------------------------------------------------------------------------------------------------------
-- three gems of id -> one of the next tier; returns the new id or nil, reason
function G.combineResult(id)
	local g = G.gemOf(id)
	if not g then
		return nil, "notGem"
	end
	if g.tier >= G.TIERS then
		return nil, "perfect"
	end
	return G.gemId(g.type.index, g.tier + 1)
end

function G.removeCost(id)
	local g = G.gemOf(id)
	return g and (cfg.removeCost[g.tier] or 0) or 0
end

-- ---------------------------------------------------------------------------------------------------------------
-- drops and rewards
-- ---------------------------------------------------------------------------------------------------------------
local function randomGem(weights, rand)
	rand = rand or G.random
	local tier = G.pickIndex(weights, rand)
	if not tier then
		return nil
	end
	return G.gemId(rand(1, G.TYPES), tier)
end
G.randomGem = randomGem

function G.levelWeights(level)
	level = tonumber(level) or 0
	for _, row in ipairs(cfg.drop.levelWeights) do
		if level <= row[1] then
			return row[2]
		end
	end
	return cfg.drop.levelWeights[#cfg.drop.levelWeights][2]
end

-- a monster kill: list of gem ids (0 or 1). tier = monster tier (normal .. boss), level = monster level (or the
-- killer's), scale = the loot layer's rate x item find
function G.rollDrop(tier, level, scale, rand)
	rand = rand or G.random
	local chance = (cfg.drop.chance[tier] or 0) * (tonumber(scale) or 1) -- in 1/10000
	if chance <= 0 or rand(1, 1000000) > chance * 100 then
		return {}
	end
	local id = randomGem(G.levelWeights(level), rand)
	if not id then
		return {}
	end
	local up = cfg.drop.tierUp[tier] or 0
	if up > 0 and rand(1, 100) <= up then
		local better = G.combineResult(id)
		id = better or id
	end
	return {id}
end

-- count with a fractional part: the fraction is the chance of one more
local function fractional(x, rand)
	local n = floor(x)
	local frac = x - n
	if frac > 0 and rand(1, 10000) <= floor(frac * 10000 + 0.5) then
		n = n + 1
	end
	return n
end

local function rowWeights(rows, value)
	for _, row in ipairs(rows) do
		if value <= row[1] then
			return row[2]
		end
	end
	return rows[#rows][2]
end

-- reward gems: list of {id = , count = } merged by id.
--   "bounty"        opts = {type = "hunt"|"elite"|"boss", band = 1..6}
--   "bountyWeekly"  opts = {band = 1..6}
--   "rift"          opts = {tier = n}
--   "worldboss"     opts = {share = 0..1}
function G.rewardGems(kind, opts, rand)
	rand = rand or G.random
	opts = opts or {}
	local r = cfg.rewards
	local count, weights = 0, nil
	if kind == "bounty" then
		local chance = r.bounty.chance[opts.type or "hunt"] or 0
		if rand(1, 100) <= chance then
			count = r.bounty.count
		end
		weights = r.bounty.bandWeights[clamp(tonumber(opts.band) or 1, 1, #r.bounty.bandWeights)]
	elseif kind == "bountyWeekly" then
		count = r.bountyWeekly.count
		weights = r.bounty.bandWeights[clamp(tonumber(opts.band) or 1, 1, #r.bounty.bandWeights)]
	elseif kind == "rift" then
		local tier = math.max(1, tonumber(opts.tier) or 1)
		count = fractional(r.rift.base + r.rift.perTier * tier, rand)
		weights = rowWeights(r.rift.tierWeights, tier)
	elseif kind == "worldboss" then
		count = r.worldboss.count + fractional((r.worldboss.countShare or 0) * clamp(tonumber(opts.share) or 0, 0, 1), rand)
		weights = r.worldboss.weights
	end
	local merged, order = {}, {}
	for _ = 1, count do
		local id = weights and randomGem(weights, rand)
		if id then
			if not merged[id] then
				merged[id] = 0
				order[#order + 1] = id
			end
			merged[id] = merged[id] + 1
		end
	end
	local out = {}
	for _, id in ipairs(order) do
		out[#out + 1] = {id = id, count = merged[id]}
	end
	return out
end

-- "2 Chipped Rubies, 1 Polished Onyx"
function G.listText(list)
	local parts = {}
	for _, e in ipairs(list) do
		local g = G.gemOf(e.id)
		if g then
			local name = cfg.tiers[g.tier] .. " " .. capital(e.count > 1 and g.type.plural or g.type.name)
			parts[#parts + 1] = e.count > 1 and (e.count .. " " .. name) or name
		end
	end
	return table.concat(parts, ", ")
end

return G
