-- Item sets (ChaosItemSets), the pure part: which item is which set piece, how many pieces of each set a character
-- wears, which bonuses that makes active and what they add up to, the texts of the bonuses, the tooltip block of a
-- piece, the unique entries of the pieces and the chase drops (rifts, raid, Descent, dungeons). No engine calls apart
-- from reading item attributes. The sets themselves are data/lib/chaos_item_sets_config.lua; the game side is
-- data/scripts/chaos/itemsets.lua. Loaded by data/lib/chaos_unique_items.lua (the pieces are uniques), by the Codex
-- generator and by the tests. Tested by server/tests/itemsets_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
-- Overview: server/README.md "Item sets".
--
-- Counting rules (S.count):
--   a piece counts when it is worn where it belongs (the caller passes only fitting slots), its wearer has its level,
--   and it is a different piece: the same piece twice (two copies of one dagger, one in each hand) counts once;
--   a two-handed weapon (hands = 2) counts as two pieces, so a set with one may reach its last bonus with fewer items.

ChaosItemSets = ChaosItemSets or {}
local S = ChaosItemSets
local floor = math.floor

S.ATTR = "chaos_set" -- custom attribute of a set piece: the set key (ChaosMakeUnique writes it)

-- ---------------------------------------------------------------------------------------------------------------
-- the data
-- ---------------------------------------------------------------------------------------------------------------
-- the open sets of client pair 28 (data/lib/chaos_gear_sets.lua ChaosGearSets.itemSets()): only while its switch
-- PAIR28 is on. An open set's pieces are plain items (no unique, no "chaos_set" attribute): a piece is known by its
-- base id, any `cap` pieces of the set reach its last bonus, and the tooltip lists only the pieces worn.
local function gearSets()
	local G = ChaosGearSets
	if type(G) ~= "table" then
		local ok, g = pcall(dofile, "data/lib/chaos_gear_sets.lua")
		G = ok and type(g) == "table" and g or nil
	end
	if G and G.PAIR28 and G.itemSets then
		return G.itemSets()
	end
	return {}
end

function S.load(cfg)
	cfg = cfg or dofile("data/lib/chaos_item_sets_config.lua")
	S.config = cfg
	S.sets, S.byKey, S.pieceById, S.openById = {}, {}, {}, {}
	local all = {}
	for _, set in ipairs(cfg.sets) do
		all[#all + 1] = set
	end
	for _, set in ipairs(gearSets()) do
		all[#all + 1] = set
	end
	for _, set in ipairs(all) do
		set.total = 0
		for _, p in ipairs(set.pieces) do
			p.hands = p.hands or 1
			p.level = p.level or set.level
			p.set = set.key
			set.total = set.total + p.hands
			S.pieceById[p.id] = {set = set, piece = p}
			if set.open then
				S.openById[p.id] = set.key
			end
		end
		if set.open then
			set.total = set.cap
		end
		table.sort(set.bonuses, function(a, b) return a.n < b.n end)
		S.sets[#S.sets + 1] = set
		S.byKey[set.key] = set
	end
	return S
end

S.load()

-- ---------------------------------------------------------------------------------------------------------------
-- pieces
-- ---------------------------------------------------------------------------------------------------------------
-- pcall on named functions, not on a closure made per call: these run for every modifier of every worn item of
-- every player in the equipment check, and the closures were most of its garbage (server/README.md "Game loop stalls")
local function getCustom(item, key)
	return item:getCustomAttribute(key)
end

local function getItemId(item)
	return item:getId()
end

local function custom(item, key)
	local ok, v = pcall(getCustom, item, key)
	if ok then
		return v
	end
	return nil
end

-- the set key an item carries: its "chaos_set" attribute; a unique made before the sets existed (the Embers pieces)
-- by its spec. nil for every other item, also for a stock copy of a piece's base item.
function S.setKeyOf(item)
	if not item then
		return nil
	end
	local key = custom(item, S.ATTR)
	if type(key) == "string" and key ~= "" then
		return key
	end
	if custom(item, "chaos_unique") ~= nil then
		local ok, id = pcall(getItemId, item)
		local spec = ok and ChaosUniqueSpecs and ChaosUniqueSpecs[id]
		return spec and spec.set or nil
	end
	if next(S.openById) then
		local ok, id = pcall(getItemId, item)
		return ok and S.openById[id] or nil
	end
	return nil
end

-- the set and the piece of an item, nil when it is no piece (the key and the base id must agree)
function S.pieceOf(item)
	local key = S.setKeyOf(item)
	if not key then
		return nil
	end
	local ok, id = pcall(getItemId, item)
	local e = ok and S.pieceById[id]
	if e and e.set.key == key then
		return e.set, e.piece
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------------------------
-- counting
-- ---------------------------------------------------------------------------------------------------------------
-- entries: the worn pieces as {id = base id, set = set key} (only items in a slot they fit; S.pieceOf decided);
-- level: the wearer's level. Returns the state:
--   {sets = {key -> {count, worn = {id -> true}, low = {id -> level needed}}}, level}
function S.count(entries, level)
	level = tonumber(level) or 0
	local state = {sets = {}, level = level}
	for _, e in ipairs(entries or {}) do
		local p = S.pieceById[e.id]
		if p and p.set.key == e.set then
			local st = state.sets[e.set]
			if not st then
				st = {count = 0, worn = {}, low = {}}
				state.sets[e.set] = st
			end
			if level < p.piece.level then
				st.low[e.id] = p.piece.level
			elseif not st.worn[e.id] then
				st.worn[e.id] = true
				st.count = st.count + p.piece.hands
			end
		end
	end
	return state
end

-- the bonuses of a set that `count` pieces make active
function S.active(set, count)
	local out = {}
	for _, b in ipairs(set.bonuses) do
		if (count or 0) >= b.n then
			out[#out + 1] = b
		end
	end
	return out
end

-- stat key groups
S.COND = {magic = true, skill_sword = true, skill_axe = true, skill_club = true, skill_melee = true, skill_dist = true,
	skill_shield = true, skill_fist = true, maxhealth = true, maxmana = true, maxhealthpct = true, maxmanapct = true}
S.RES = {res_fire = "fire", res_ice = "ice", res_earth = "earth", res_energy = "energy", res_death = "death",
	res_holy = "holy", res_physical = "physical"}

-- one melee skill (server/README.md "One melee skill"): a melee skill bonus (skill_melee, or the older skill_sword,
-- skill_axe, skill_club) raises all three engine skills, so it raises the best of them, the player's Melee
S.MELEE = {skill_melee = true, skill_sword = true, skill_axe = true, skill_club = true}
S.MELEE_ENGINE = {"skill_sword", "skill_axe", "skill_club"}

-- what the active bonuses of a state add up to:
--   {mods = {modifier key -> n}, cond = {key -> n}, res = {element -> percent}, resPvp = {element -> percent},
--    effects = {key -> true}}; resPvp: against players and their summons, a set's resistances x its pvpShare (%, 100
--    when the set names none: the pair 28 sets give half)
function S.totals(state)
	local t = {mods = {}, cond = {}, res = {}, resPvp = {}, effects = {}}
	for _, set in ipairs(S.sets) do
		local st = state and state.sets[set.key]
		if st and st.count > 0 then
			for _, b in ipairs(S.active(set, st.count)) do
				for k, v in pairs(b.stats or {}) do
					if S.MELEE[k] then
						for _, e in ipairs(S.MELEE_ENGINE) do
							t.cond[e] = (t.cond[e] or 0) + v
						end
					elseif S.COND[k] then
						t.cond[k] = (t.cond[k] or 0) + v
					elseif S.RES[k] then
						local el = S.RES[k]
						t.res[el] = (t.res[el] or 0) + v
						t.resPvp[el] = (t.resPvp[el] or 0) + floor(v * (set.pvpShare or 100) / 100)
					else
						t.mods[k] = (t.mods[k] or 0) + v
					end
				end
				if b.effect then
					t.effects[b.effect] = true
				end
			end
		end
	end
	return t
end

-- a short text of what counts (item_mods.lua refreshes the totals when it changes)
function S.signature(state)
	local parts = {}
	for _, set in ipairs(S.sets) do
		local st = state and state.sets[set.key]
		if st and st.count > 0 then
			parts[#parts + 1] = set.key .. "=" .. st.count
		end
	end
	return table.concat(parts, ",")
end

-- ---------------------------------------------------------------------------------------------------------------
-- texts
-- ---------------------------------------------------------------------------------------------------------------
S.LABELS = {
	magic = "Magic Level +%d", skill_melee = "Melee +%d", skill_sword = "Melee +%d", skill_axe = "Melee +%d",
	skill_club = "Melee +%d", skill_dist = "Ranged +%d", skill_shield = "Shielding +%d",
	skill_fist = "Fist Fighting +%d", maxhealth = "Maximum Health +%d", maxmana = "Maximum Mana +%d",
	maxhealthpct = "Maximum Health +%d%%", maxmanapct = "Maximum Mana +%d%%",
	res_fire = "Fire Resistance +%d%%", res_ice = "Ice Resistance +%d%%", res_earth = "Earth Resistance +%d%%",
	res_energy = "Energy Resistance +%d%%", res_death = "Death Resistance +%d%%", res_holy = "Holy Resistance +%d%%",
	res_physical = "Physical Resistance +%d%%"
}

-- the order stats are written in: the condition and resistance keys first (as in S.LABELS), then the modifiers in the
-- catalogue's order, unknown keys by name (no pairs() order: the Codex output must not change between runs)
local LABEL_ORDER = {"magic", "skill_melee", "skill_sword", "skill_axe", "skill_club", "skill_dist", "skill_shield", "skill_fist",
	"maxhealth", "maxhealthpct", "maxmana", "maxmanapct", "res_physical", "res_fire", "res_ice", "res_earth", "res_energy",
	"res_death", "res_holy"}

function S.statText(key, value)
	value = floor(tonumber(value) or 0)
	if S.LABELS[key] then
		return string.format(S.LABELS[key], value)
	end
	local M = ChaosItemMods
	if M and M.byKey and M.byKey[key] and M.text then
		return M.text(key, value)
	end
	return key .. " " .. value
end

function S.statKeys(stats)
	local keys, seen = {}, {}
	for _, k in ipairs(LABEL_ORDER) do
		if stats[k] then
			keys[#keys + 1] = k
			seen[k] = true
		end
	end
	local rest = {}
	for k in pairs(stats) do
		if not seen[k] then
			rest[#rest + 1] = k
		end
	end
	local M = ChaosItemMods
	table.sort(rest, function(a, b)
		local da, db = M and M.byKey and M.byKey[a], M and M.byKey and M.byKey[b]
		local ia, ib = da and da.index or 1e9, db and db.index or 1e9
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	for _, k in ipairs(rest) do
		keys[#keys + 1] = k
	end
	return keys
end

-- an effect's text with its numbers
function S.effectText(key)
	local e = S.config.effects[key]
	if not e then
		return tostring(key)
	end
	return (e.text:gsub("{(%w+)}", function(f) return tostring(e[f] or "?") end))
end

-- the lines of one bonus: every stat, then the effect
function S.bonusLines(b)
	local out = {}
	local stats = b.stats or {}
	for _, k in ipairs(S.statKeys(stats)) do
		out[#out + 1] = S.statText(k, stats[k])
	end
	if b.effect then
		out[#out + 1] = S.effectText(b.effect)
	end
	return out
end

function S.bonusText(b)
	return table.concat(S.bonusLines(b), ", ")
end

-- ---------------------------------------------------------------------------------------------------------------
-- the tooltip block of a piece (item_tooltip_core.lua tip.unique.set)
-- ---------------------------------------------------------------------------------------------------------------
-- {key, name, have, total, pieces = [{n, eq, lv, low}], bonuses = [{n, t, on}]}: have = what counts now (a two-handed
-- piece twice), eq = the viewer wears it and it counts, low = worn but the viewer's level is below lv
function S.tooltip(setKey, state)
	local set = S.byKey[setKey]
	if not set then
		return nil
	end
	local st = state and state.sets and state.sets[setKey] or {count = 0, worn = {}, low = {}}
	local tip = {key = set.key, name = set.name, have = st.count or 0, total = set.total, pieces = {}, bonuses = {}}
	for _, p in ipairs(set.pieces) do
		local row = {n = p.name, lv = p.level}
		if st.worn and st.worn[p.id] then
			row.eq = true
		elseif st.low and st.low[p.id] then
			row.low = true
		end
		if p.hands > 1 then
			row.h = p.hands
		end
		if not set.open or row.eq or row.low then -- an open set lists only the pieces worn
			tip.pieces[#tip.pieces + 1] = row
		end
	end
	local tier = 0
	for _, b in ipairs(set.bonuses) do
		local on = (st.count or 0) >= b.n
		tier = on and tier + 1 or tier
		tip.bonuses[#tip.bonuses + 1] = {n = b.n, t = S.bonusText(b), on = on or nil}
	end
	if set.open then
		tip.have = math.min(tip.have, set.cap)
		tip.tier, tip.tiers = tier, #set.bonuses
	end
	return tip
end

-- look text lines of a piece for the viewer (itemsets.lua onLook)
function S.lookLines(setKey, state)
	local tip = S.tooltip(setKey, state)
	if not tip then
		return {}
	end
	local out = {string.format("Set: %s (%d/%d).", tip.name, tip.have, tip.total)}
	if tip.tiers then
		out[1] = string.format("Set: %s (%d/%d), tier %d of %d.", tip.name, tip.have, tip.total, tip.tier, tip.tiers)
	end
	for _, b in ipairs(tip.bonuses) do
		out[#out + 1] = string.format("(%d) %s%s", b.n, b.t, b.on and " [active]" or "")
	end
	return out
end

-- ---------------------------------------------------------------------------------------------------------------
-- unique entries (data/lib/chaos_unique_items.lua appends them to ChaosUniqueItems)
-- ---------------------------------------------------------------------------------------------------------------
-- one entry per piece of every set with `sources.uniques`, in the format of ChaosUniqueItems (LOOT.md), set = key
function S.uniqueEntries()
	local out = {}
	for _, set in ipairs(S.sets) do
		local u = set.sources and set.sources.uniques
		if u then
			for _, p in ipairs(set.pieces) do
				local monsters = {}
				for i, m in ipairs(u.monsters or {}) do
					monsters[i] = m
				end
				out[#out + 1] = {name = p.name, id = p.id, minTier = u.minTier or "rare", chance = u.chance or 1,
					level = p.level, slot = p.slot, bossOnly = u.bossOnly and true or false, monsters = monsters, set = set.key}
			end
		end
	end
	return out
end

-- add the entries to a unique list and its indexes (an id already listed keeps its entry, which gets the set key)
function S.register(list, byName, byId)
	local have = {}
	for _, e in ipairs(list) do
		have[e.id] = e
	end
	for _, set in ipairs(S.sets) do
		for _, p in ipairs(set.pieces) do
			if have[p.id] and not have[p.id].set then
				have[p.id].set = set.key
			end
		end
	end
	for _, e in ipairs(S.uniqueEntries()) do
		if not have[e.id] then
			list[#list + 1] = e
			have[e.id] = e
			if byName then
				byName[e.name] = e
				byName[e.name:lower()] = e
			end
			if byId then
				byId[e.id] = e
			end
		end
	end
	return list
end

-- ---------------------------------------------------------------------------------------------------------------
-- chase drops
-- ---------------------------------------------------------------------------------------------------------------
local function listed(list, value)
	for _, v in ipairs(list or {}) do
		if v == value then
			return true
		end
	end
	return false
end

-- the chance (per 10000, before item find) of one set from a source, 0 when the set has nothing to do with it.
-- source / key / ctx:
--   "rift", theme name, {tier}                 "raid", boss key, {final = true for the last boss}
--   "descent", nil, {depth, cleared}           "dungeon", nil, {difficulty}
-- ctx.level (the player's level) must be at least the set's level - chase.levelBelow
function S.chaseChance(set, source, key, ctx)
	ctx = ctx or {}
	local c = S.config.chase
	local src = set.sources or {}
	if ctx.level and ctx.level < set.level - (c.levelBelow or 0) then
		return 0
	end
	if source == "rift" then
		local r = src.rift
		local tier = tonumber(ctx.tier) or 0
		if not r or r.theme ~= key or tier < r.minTier then
			return 0
		end
		return math.min(c.rift.max, c.rift.base + c.rift.perTier * (tier - r.minTier))
	elseif source == "raid" then
		if not listed(src.raid, key) then
			return 0
		end
		return ctx.final and c.raid.final or c.raid.boss
	elseif source == "descent" then
		local d = src.descent
		local depth = tonumber(ctx.depth) or 0
		if not d or depth < d.minDepth then
			return 0
		end
		return math.min(c.descent.max, c.descent.base + c.descent.perDepth * (depth - d.minDepth)
			+ (ctx.cleared and c.descent.clear or 0))
	elseif source == "dungeon" then
		if not src.dungeon then
			return 0
		end
		return math.min(c.dungeon.max, c.dungeon.base + c.dungeon.perDifficulty * math.max(0, tonumber(ctx.difficulty) or 0))
	end
	return 0
end

-- one chase roll: every set of the source rolls its chance (x ctx.itemFind, at most 10000); among the sets that hit,
-- one at random, then one of its pieces at random. Returns {set, piece} or nil. rand(a, b) is math.random's contract.
function S.rollChase(source, key, ctx, rand)
	rand = rand or math.random
	ctx = ctx or {}
	local hits = {}
	for _, set in ipairs(S.sets) do
		local chance = S.chaseChance(set, source, key, ctx) * (tonumber(ctx.itemFind) or 1)
		if chance > 0 and rand(1, 10000) <= math.min(10000, chance) then
			hits[#hits + 1] = set
		end
	end
	if #hits == 0 then
		return nil
	end
	local set = hits[rand(1, #hits)]
	return {set = set, piece = set.pieces[rand(1, #set.pieces)]}
end

-- ---------------------------------------------------------------------------------------------------------------
-- effect maths (itemsets.lua)
-- ---------------------------------------------------------------------------------------------------------------
function S.effect(key)
	return S.config.effects[key]
end

-- an internal cooldown: true (and started) when over
function S.ready(cd, key, now, ms)
	if (cd[key] or 0) > now then
		return false
	end
	cd[key] = now + (ms or 0)
	return true
end

-- percent of a hit, whole points, at least 1
function S.share(hit, pct)
	return math.max(1, floor(math.abs(tonumber(hit) or 0) * (tonumber(pct) or 0) / 100 + 1e-9))
end

-- a damage value scaled by percent (toward zero, keeps the sign)
function S.scale(value, pct)
	local a = floor(math.abs(value) * (100 + pct) / 100 + 1e-6)
	return value < 0 and -a or a
end

-- Hanging Verdict: is the monster low enough?
function S.verdict(health, maxHealth)
	health, maxHealth = tonumber(health) or 0, tonumber(maxHealth) or 0
	return maxHealth > 0 and health * 100 < maxHealth * S.config.effects.hangingverdict.below
end

-- a fire / bleed damage over time: damage per tick of `rounds` ticks for a share of a hit
function S.dotTick(hit, pct, rounds)
	return math.max(1, floor(math.abs(tonumber(hit) or 0) * (tonumber(pct) or 0) / 100 / math.max(1, rounds or 1) + 1e-9))
end

return S
