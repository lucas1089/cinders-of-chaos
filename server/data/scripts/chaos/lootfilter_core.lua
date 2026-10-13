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
--   ChaosLootFilter.ruleHits / countHits      which filter rules (F.RULES) an item / a kill matched (the rule counters)
--   ChaosLootFilter.packSound / unpackSound   sound per rule, volume, mute, hunt tracker flag <-> one int32 storage value
--   ChaosLootFilter.pickSound(hits, snd)      the alert sound of a kill;  resetPlan(scope, rule)  what a reset clears
--   ChaosLootFilter.look(outfit, shaders, fallback) / parseShaders(xml)   the monster icon of a loot row (client outfit table)
-- info = {id, rarity = 0..15, unique = bool, orb = bool, power = bool (a legendary power: always glows), category = "equipment"|"currency"|"supplies"|"other", name, count,
--         level = item level, bestTier = the best modifier tier on it (0 = none)}
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
-- tier       equipment with a modifier of this tier or better glows whatever its rarity (0 = off, 1..8 = T1..T8)
function F.defaults()
	return {highlight = 3, dim = 0, lootMin = 0, lootFrom = 0,
		show = {equipment = true, currency = true, supplies = true, other = true}, icons = true, notify = true, tier = 0}
end
F.MAX_TIER = 8

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
		notify = bool(t.notify, d.notify),
		tier = math.max(0, math.min(F.MAX_TIER, math.floor(tonumber(t.tier) or d.tier)))
	}
	if s.tier ~= s.tier then
		s.tier = d.tier
	end
	local show = type(t.show) == "table" and t.show or {}
	for _, c in ipairs(F.CATEGORIES) do
		s.show[c] = bool(show[c], true)
	end
	return s
end

-- bits: highlight 0-3, dim 4-7, lootMin 8-11, lootFrom 12-15, show 16-19 (CATEGORIES order), icons 20, notify 21,
-- tier 22-25.
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
	return v + s.tier * 4194304
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
	s.tier = field(4194304, 16)
	return F.sanitize(s)
end

-- ---------------------------------------------------------------- rules
function F.classify(info, s)
	if info.unique or info.orb or info.power then
		return "highlight"
	end
	local category = info.category or "other"
	local shown = not (s.show and s.show[category] == false)
	if category == "equipment" then
		local r = tonumber(info.rarity) or 0
		if s.highlight > 0 and r >= s.highlight then
			return "highlight"
		end
		if (s.tier or 0) > 0 and (tonumber(info.bestTier) or 0) >= s.tier then
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

-- sightClear (optional): false = a wall, door or bars between them; only the squares next to the player skip it
function F.inReach(from, to, range, sightClear)
	if not from or not to or from.z ~= to.z then
		return false
	end
	local dx, dy = math.abs(from.x - to.x), math.abs(from.y - to.y)
	if sightClear == false and (dx > 1 or dy > 1) then
		return false
	end
	return dx <= range.x and dy <= range.y
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

-- ---------------------------------------------------------------- rule counters and sounds
-- The filter's rules (the reasons an item glows), in priority order: the first matched rule with a sound plays it.
--   unique  a unique item            power  a legendary power (not on a unique)
--   rarity  gear at or above the "Glow on gear from" rarity (off when that is Off)
--   tier    gear with a modifier of the "Glow on a modifier of" tier or better (off when that is Off)
--   orb     an orb (currency that always glows)
-- An item can match several rules (a Legendary with a power counts for power and rarity). Counts are items: a stack
-- of 3 orbs adds 3.
F.RULES = {
	{key = "unique", name = "Uniques"},
	{key = "power", name = "Legendary powers"},
	{key = "rarity", name = "Rarity glow"},
	{key = "tier", name = "Modifier tier"},
	{key = "orb", name = "Orbs"}
}
-- alert sounds (client game_lootfilter/sounds/<file>.ogg, made by client/tools/gen_lootfilter_sounds.py); 0 = none
F.SOUNDS = {
	{key = "chime", name = "Chime"},
	{key = "bell", name = "Bell"},
	{key = "ping", name = "Ping"},
	{key = "drum", name = "Drum"},
	{key = "fanfare", name = "Fanfare"}
}
F.MAX_SOUND = 7 -- 3 bits per rule in the packed value

function F.ruleHits(info, s)
	local out = {}
	if info.unique then
		out[#out + 1] = "unique"
		return out
	end
	if info.power then
		out[#out + 1] = "power"
	end
	if info.category == "equipment" then
		local r = tonumber(info.rarity) or 0
		if (s.highlight or 0) > 0 and r >= s.highlight then
			out[#out + 1] = "rarity"
		end
		if (s.tier or 0) > 0 and (tonumber(info.bestTier) or 0) >= s.tier then
			out[#out + 1] = "tier"
		end
	end
	if info.orb then
		out[#out + 1] = "orb"
	end
	return out
end

-- {rule = items} of a list of item infos (one kill); rules that matched nothing are absent
function F.countHits(infos, s)
	local hits = {}
	for _, info in ipairs(infos or {}) do
		local n = math.max(1, math.floor(tonumber(info.count) or 1))
		for _, k in ipairs(F.ruleHits(info, s)) do
			hits[k] = (hits[k] or 0) + n
		end
	end
	return hits
end

local COUNTER_MAX = 2000000000 -- a storage value is an int32

function F.addCounts(counts, hits)
	for _, r in ipairs(F.RULES) do
		local n = tonumber(hits[r.key]) or 0
		if n > 0 then
			counts[r.key] = math.min(COUNTER_MAX, (tonumber(counts[r.key]) or 0) + n)
		end
	end
	return counts
end

-- every rule present (0 when nothing counted)
function F.counts(c)
	local out = {}
	for _, r in ipairs(F.RULES) do
		local v = tonumber(c and c[r.key]) or 0
		out[r.key] = v > 0 and math.floor(v) or 0
	end
	return out
end

function F.isRule(key)
	for _, r in ipairs(F.RULES) do
		if r.key == key then
			return true
		end
	end
	return false
end

-- sound settings: sound per rule (0 = none, 1..#F.SOUNDS), volume 0..100, mute all, show the counters in the hunt tracker
function F.soundDefaults()
	return {rules = {unique = 5, power = 1, rarity = 0, tier = 0, orb = 0}, vol = 70, mute = false, hunt = true}
end

function F.sanitizeSound(t)
	local d = F.soundDefaults()
	if type(t) ~= "table" then
		return d
	end
	local out = {rules = {}, vol = d.vol, mute = bool(t.mute, d.mute), hunt = bool(t.hunt, d.hunt)}
	local rules = type(t.rules) == "table" and t.rules or {}
	for _, r in ipairs(F.RULES) do
		local v = tonumber(rules[r.key])
		if not v or v ~= v then
			out.rules[r.key] = d.rules[r.key]
		else
			v = math.floor(v)
			out.rules[r.key] = (v >= 0 and v <= #F.SOUNDS) and v or 0
		end
	end
	local vol = tonumber(t.vol)
	if vol and vol == vol then
		out.vol = math.max(0, math.min(100, math.floor(vol)))
	end
	return out
end

-- bits: the rules' sounds 3 bits each (F.RULES order) 0-14, volume 15-21, mute 22, hunt 23
function F.packSound(t)
	t = F.sanitizeSound(t)
	local v, mul = 0, 1
	for _, r in ipairs(F.RULES) do
		v = v + t.rules[r.key] * mul
		mul = mul * 8
	end
	v = v + t.vol * 32768
	if t.mute then
		v = v + 4194304
	end
	if t.hunt then
		v = v + 8388608
	end
	return v
end

function F.unpackSound(v)
	v = tonumber(v)
	if not v or v < 0 or v ~= v then
		return F.soundDefaults()
	end
	v = math.floor(v)
	local out = {rules = {}}
	local mul = 1
	for _, r in ipairs(F.RULES) do
		out.rules[r.key] = math.floor(v / mul) % 8
		mul = mul * 8
	end
	out.vol = math.floor(v / 32768) % 128
	out.mute = math.floor(v / 4194304) % 2 == 1
	out.hunt = math.floor(v / 8388608) % 2 == 1
	return F.sanitizeSound(out)
end

-- the sound a kill plays: the first rule (F.RULES order) that matched and has a sound; nil when muted or silent
function F.pickSound(hits, snd)
	if not snd or snd.mute or (tonumber(snd.vol) or 0) <= 0 then
		return nil
	end
	for _, r in ipairs(F.RULES) do
		local id = tonumber(snd.rules and snd.rules[r.key]) or 0
		if (tonumber(hits and hits[r.key]) or 0) > 0 and id > 0 and F.SOUNDS[id] then
			return F.SOUNDS[id].key, r.key
		end
	end
	return nil
end

-- reset: scope "session" | "total" | "all", rule nil = every rule. Returns the rules whose counters were cleared
function F.resetPlan(scope, rule)
	if scope ~= "session" and scope ~= "total" and scope ~= "all" then
		return nil
	end
	if rule ~= nil and rule ~= "" and not F.isRule(rule) then
		return nil
	end
	local rules = {}
	for _, r in ipairs(F.RULES) do
		if rule == nil or rule == "" or rule == r.key then
			rules[#rules + 1] = r.key
		end
	end
	return {session = scope ~= "total", total = scope ~= "session", rules = rules}
end

-- ---------------------------------------------------------------- the monster icon of a loot row
-- data/XML/shaders.xml text -> {[id] = name} (the client knows a shader by its name; the engine's Lua has no lookup)
function F.parseShaders(xml)
	local out = {}
	if type(xml) ~= "string" then
		return out
	end
	for tag in xml:gmatch("<shader%s[^>]*>") do
		local id = tonumber(tag:match('%sid%s*=%s*"(%d+)"'))
		local name = tag:match('%sname%s*=%s*"([^"]*)"')
		if id and name and name ~= "" then
			out[id] = name
		end
	end
	return out
end

-- the look of a killed monster for the client's UICreature (outfit table names), from Creature:getOutfit()
-- (or MonsterType:getOutfit()); nil when it has none. `fallback` is used when `o` has neither a look type nor an item look.
-- Item looks (lookTypeEx) go as auxType; mounts are left out (the icon is item sized); a tier shader goes by name.
function F.look(o, shaderNames, fallback)
	local function n(v, max)
		v = math.floor(tonumber(v) or 0)
		if v ~= v or v < 0 or v > max then
			return 0
		end
		return v
	end
	if type(o) ~= "table" or (n(o.lookType, 65535) == 0 and n(o.lookTypeEx, 65535) == 0) then
		if fallback ~= nil then
			return F.look(fallback, shaderNames)
		end
		return nil
	end
	local t = {type = n(o.lookType, 65535), head = n(o.lookHead, 255), body = n(o.lookBody, 255),
		legs = n(o.lookLegs, 255), feet = n(o.lookFeet, 255), addons = n(o.lookAddons, 3)}
	local aux = n(o.lookTypeEx, 65535)
	if aux > 0 then
		t.type, t.auxType = 0, aux
	end
	local shader = n(o.lookShader, 65535)
	if shader > 0 and type(shaderNames) == "table" and shaderNames[shader] then
		t.shader = shaderNames[shader]
	end
	return t
end

return F
