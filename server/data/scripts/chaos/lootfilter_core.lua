-- Loot filter: pure logic (no engine calls), shared by lootfilter.lua and server/tests/lootfilter_test.lua.
--   ChaosLootFilter.defaults()               a fresh settings table (see below)
--   ChaosLootFilter.pack(s) / unpack(v)       settings <-> one int32 storage value (unset / negative = defaults)
--   ChaosLootFilter.sanitize(t)               settings from client input (clamped, unknown keys dropped)
--   ChaosLootFilter.applyPreset(name)         settings of a preset ("all", "hunter", "strict"), or nil
--   ChaosLootFilter.classify(info, s)         "highlight" | "normal" | "dim" for one item
--   ChaosLootFilter.autoloot(info, s, onList, unlocked)  "take" | "keep" | nil (nil = leave it to the stock autoloot)
--   ChaosLootFilter.rayEffect(info, cfg)      effect name of the loot ray for an item, or nil
--   ChaosLootFilter.signature(info)           key used to match a tracked entry to an item still in the corpse
--   ChaosLootFilter.reconcile(entries, present)  remaining count per tracked entry, given what the corpse holds now
--   ChaosLootFilter.inReach(from, to, range)  same floor and within range.x / range.y squares
--   ChaosLootFilter.label(info)               "[Legendary] Dawnforged Helmet" / "[Unique] Soulreaper" / "Gold Coin"
-- info = {id, rarity = 0..15, unique = bool, orb = bool, category = "equipment"|"currency"|"supplies"|"other", name, count}
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosLootFilter = ChaosLootFilter or {}
local F = ChaosLootFilter

-- The base server's rarity table (data/scripts/eventcallbacks/monster/default_onDropLoot.lua): ids 1..15.
-- Colours are ours (the client module game_lootfilter has the same list); the ray bands follow them.
F.RARITY = {
	{name = "Common", color = "#c8c8c8"},
	{name = "Uncommon", color = "#5ccf5c"},
	{name = "Rare", color = "#4a90ff"},
	{name = "Epic", color = "#a35cf0"},
	{name = "Legendary", color = "#ffd040"},
	{name = "Exotic", color = "#f5b13a"},
	{name = "Mythic", color = "#ff5a5a"},
	{name = "Chaos", color = "#e02424"},
	{name = "Eternal", color = "#ff8a70"},
	{name = "Divine", color = "#c8e8ff"},
	{name = "Phantasmal", color = "#9ad8ff"},
	{name = "Celestial", color = "#e4f2ff"},
	{name = "Cosmic", color = "#b878ff"},
	{name = "Abyssal", color = "#9a4ce0"},
	{name = "Transcendent", color = "#e070ff"}
}
F.MAX_RARITY = #F.RARITY
F.UNIQUE_COLOR = "#e07b24"
F.ORB_COLOR = "#4fd8d0"
F.CATEGORIES = {"equipment", "currency", "supplies", "other"}

-- ---------------------------------------------------------------- settings
-- highlight  equipment with rarity >= highlight gets a glow (0 = no rarity glow; uniques and orbs always glow)
-- dim        equipment with rarity < dim is dimmed (0 = nothing dimmed by rarity; rarity 0 = no rarity at all)
-- lootMin    store unlock: autoloot-list equipment with rarity < lootMin stays in the corpse (0 = off)
-- lootFrom   store unlock: equipment with rarity >= lootFrom (and uniques) is autolooted even when not on the list (0 = off)
-- show       per category; a category switched off is dimmed (equipment at or above `highlight` still glows)
-- icons      the Loot console tab shows item icons (click to loot) instead of the text lines
-- notify     the "Rare drop: [Legendary] ..." line for highlighted items
function F.defaults()
	return {highlight = 3, dim = 0, lootMin = 0, lootFrom = 0,
		show = {equipment = true, currency = true, supplies = true, other = true}, icons = true, notify = true}
end

F.PRESETS = {
	{key = "all", name = "Show all", desc = "Rare+ glows, nothing is dimmed, autoloot as on your list."},
	{key = "hunter", name = "Hunter", desc = "Epic+ glows, Common and plain gear dimmed; Rarity Autoloot picks up Epic+."},
	{key = "strict", name = "Strict", desc = "Legendary+ glows, gear below Epic dimmed, supplies and other dimmed; Rarity Autoloot: nothing below Epic, picks up Legendary+."}
}

function F.applyPreset(name)
	local s = F.defaults()
	if name == "all" then
		return s
	elseif name == "hunter" then
		s.highlight, s.dim, s.lootMin, s.lootFrom = 4, 2, 0, 4
		return s
	elseif name == "strict" then
		s.highlight, s.dim, s.lootMin, s.lootFrom = 5, 4, 4, 5
		s.show.supplies, s.show.other = false, false
		return s
	end
	return nil
end

local function clampRarity(v, default)
	v = tonumber(v)
	if not v or v ~= v then
		return default
	end
	v = math.floor(v)
	if v < 0 then
		return 0
	end
	if v > F.MAX_RARITY then
		return F.MAX_RARITY
	end
	return v
end

local function bool(v, default)
	if v == nil then
		return default
	end
	return v == true or v == 1 or v == "1" or v == "true"
end

function F.sanitize(t)
	local d = F.defaults()
	if type(t) ~= "table" then
		return d
	end
	local s = {
		highlight = clampRarity(t.highlight, d.highlight),
		dim = clampRarity(t.dim, d.dim),
		lootMin = clampRarity(t.lootMin, d.lootMin),
		lootFrom = clampRarity(t.lootFrom, d.lootFrom),
		show = {},
		icons = bool(t.icons, d.icons),
		notify = bool(t.notify, d.notify)
	}
	local show = type(t.show) == "table" and t.show or {}
	for _, c in ipairs(F.CATEGORIES) do
		s.show[c] = bool(show[c], true)
	end
	return s
end

-- bits: highlight 0-3, dim 4-7, lootMin 8-11, lootFrom 12-15, show 16-19 (CATEGORIES order), icons 20, notify 21.
-- Arithmetic only (no bit library: Lua 5.1 and 5.3 both run it). Fits easily in a positive int32 storage value.
function F.pack(s)
	s = F.sanitize(s)
	local v = s.highlight + s.dim * 16 + s.lootMin * 256 + s.lootFrom * 4096
	local bit = 65536
	for _, c in ipairs(F.CATEGORIES) do
		if s.show[c] then
			v = v + bit
		end
		bit = bit * 2
	end
	if s.icons then
		v = v + 1048576
	end
	if s.notify then
		v = v + 2097152
	end
	return v
end

function F.unpack(v)
	v = tonumber(v)
	if not v or v < 0 or v ~= v then
		return F.defaults()
	end
	v = math.floor(v)
	local function field(shift, size)
		return math.floor(v / shift) % size
	end
	local s = {highlight = field(1, 16), dim = field(16, 16), lootMin = field(256, 16), lootFrom = field(4096, 16), show = {}}
	local bit = 65536
	for _, c in ipairs(F.CATEGORIES) do
		s.show[c] = field(bit, 2) == 1
		bit = bit * 2
	end
	s.icons = field(1048576, 2) == 1
	s.notify = field(2097152, 2) == 1
	return F.sanitize(s)
end

-- ---------------------------------------------------------------- rules
function F.classify(info, s)
	if info.unique or info.orb then
		return "highlight"
	end
	local category = info.category or "other"
	local shown = not (s.show and s.show[category] == false)
	if category == "equipment" then
		local r = tonumber(info.rarity) or 0
		if s.highlight > 0 and r >= s.highlight then
			return "highlight"
		end
		if not shown or r < s.dim then
			return "dim"
		end
		return "normal"
	end
	return shown and "normal" or "dim"
end

function F.color(info)
	if info.unique then
		return F.UNIQUE_COLOR
	end
	local r = F.RARITY[tonumber(info.rarity) or 0]
	if r then
		return r.color
	end
	if info.orb then
		return F.ORB_COLOR
	end
	return nil
end

function F.autoloot(info, s, onList, unlocked)
	if not unlocked then
		return nil
	end
	local r = tonumber(info.rarity) or 0
	local gear = info.category == "equipment" and not info.unique
	if onList then
		if gear and s.lootMin > 0 and r < s.lootMin then
			return "keep"
		end
		return nil
	end
	if s.lootFrom > 0 and (info.unique or (gear and r > 0 and r >= s.lootFrom)) then
		return "take"
	end
	return nil
end

-- cfg = {rayUniques = bool, rayMinRarity = n, rayUniqueEffect = name, rayBands = {{from = n, effect = name}, ...}}
function F.rayEffect(info, cfg)
	if info.unique then
		return cfg.rayUniques and cfg.rayUniqueEffect or nil
	end
	local r = tonumber(info.rarity) or 0
	if r < 1 or r < (cfg.rayMinRarity or math.huge) then
		return nil
	end
	local best, bestFrom
	for _, band in ipairs(cfg.rayBands or {}) do
		if r >= band.from and (not bestFrom or band.from > bestFrom) then
			best, bestFrom = band.effect, band.from
		end
	end
	return best
end

-- ---------------------------------------------------------------- tracking
function F.signature(info)
	return string.format("%d:%d:%s", tonumber(info.id) or 0, tonumber(info.rarity) or 0, info.unique and (info.name or "?") or "")
end

-- entries = {{sig, count}, ...} (the kill as it dropped, in corpse order); present = {[sig] = count still in the corpse}.
-- Identical items are interchangeable, so the earliest entries keep what is left. Returns {remaining, ...}.
function F.reconcile(entries, present)
	local left = {}
	for k, v in pairs(present) do
		left[k] = v
	end
	local out = {}
	for i, e in ipairs(entries) do
		local avail = left[e.sig] or 0
		local take = math.min(e.count or 1, avail)
		out[i] = take
		left[e.sig] = avail - take
	end
	return out
end

function F.inReach(from, to, range)
	if not from or not to or from.z ~= to.z then
		return false
	end
	return math.abs(from.x - to.x) <= range.x and math.abs(from.y - to.y) <= range.y
end

function F.label(info)
	local name = info.name or "item"
	if info.unique then
		return "[Unique] " .. name
	end
	local r = F.RARITY[tonumber(info.rarity) or 0]
	if r then
		return "[" .. r.name .. "] " .. name
	end
	return name
end

-- "Rare drop" line for an item, or nil when it is not worth a line under these settings.
function F.dropLine(info, s)
	if not s.notify or F.classify(info, s) ~= "highlight" then
		return nil
	end
	if info.orb and not info.unique then
		return nil -- orbs glow, but a line per orb would spam the chat
	end
	local count = tonumber(info.count) or 1
	local prefix = info.unique and "Unique drop: " or "Rare drop: "
	return prefix .. (count > 1 and (count .. "x ") or "") .. F.label(info)
end

return F
