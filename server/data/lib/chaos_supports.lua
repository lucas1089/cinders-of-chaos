-- Spell supports (ChaosSupports): the pure part. Every spell has 1-3 support sockets; support runes (20 kinds, levels
-- 1-5) sit in them and change how the spell works. The sockets belong to the character and are keyed by spell id
-- (player storages), never by class, so any spell with an id can carry them (stock spells, Chaos spells, and later
-- spells that come from items). Numbers: data/lib/chaos_supports_config.lua. Design and the full list:
-- data/scripts/chaos/SUPPORTS.md.
--
-- Loaded in two Lua states, so no engine call happens at load time and nothing here needs another Chaos file:
--   scripts state  data/scripts/chaos/supports.lua   window, socketing, hit effects, drops and rewards
--   spell state    data/spells/chaos/_supports.lua   cast context, mana refund, cooldown
-- Gem machinery reused where it fits (ChaosGems, data/lib/chaos_gems.lua, when it is loaded): the weighted pick, the
-- monster-level weights of the drops, the band weights of the bounty rewards, the gold payment of a removal.
-- Tested by server/tests/supports_test.lua. Lua 5.1 / LuaJIT and Lua 5.3.

ChaosSupports = ChaosSupports or {}
local S = ChaosSupports

S.config = dofile("data/lib/chaos_supports_config.lua")
local cfg = S.config
local floor = math.floor

S.random = function(a, b)
	return math.random(a, b)
end

local function clamp(v, lo, hi)
	if v < lo then
		return lo
	end
	if v > hi then
		return hi
	end
	return v
end

local function capital(s)
	return (s:gsub("^%l", string.upper))
end

-- ---------------------------------------------------------------------------------------------------------------
-- rune ids
-- ---------------------------------------------------------------------------------------------------------------
S.LEVELS = cfg.levels
S.TYPES = #cfg.supports
S.byKey = {}
for i, t in ipairs(cfg.supports) do
	t.index = i
	t.fitsSet = {}
	for _, k in ipairs(t.fits) do
		t.fitsSet[k] = true
	end
	S.byKey[t.key] = t
end

function S.runeId(typeIndex, level)
	return cfg.firstId + (typeIndex - 1) * S.LEVELS + (level - 1)
end

S.lastId = S.runeId(S.TYPES, S.LEVELS)

-- {type = <support table>, level = n} of a rune server id, or nil
function S.runeOf(id)
	id = tonumber(id)
	if not id or id < cfg.firstId or id > S.lastId or id ~= floor(id) then
		return nil
	end
	local n = id - cfg.firstId
	return {type = cfg.supports[floor(n / S.LEVELS) + 1], level = n % S.LEVELS + 1}
end

function S.isRune(id)
	return S.runeOf(id) ~= nil
end

-- "Epic Fork Rune" (texts); items.xml has the lower-case "epic fork rune"
function S.runeName(id)
	local r = S.runeOf(id)
	if not r then
		return "unknown rune"
	end
	return cfg.levelNames[r.level] .. " " .. r.type.name .. " Rune"
end

function S.itemName(typeIndex, level, plural)
	local t = cfg.supports[typeIndex]
	return (cfg.levelNames[level] .. " " .. t.name .. (plural and " runes" or " rune")):lower()
end

function S.levelColor(id)
	local r = S.runeOf(id)
	return r and cfg.levelColors[r.level] or "#d6c9ae"
end

function S.spriteOf(typeIndex)
	return cfg.sprites[cfg.supports[typeIndex].sprite] or cfg.sprites[1]
end

-- value, value2 of a rune
function S.values(id)
	local r = S.runeOf(id)
	if not r then
		return 0, nil
	end
	return r.type.values[r.level] or 0, r.type.values2 and r.type.values2[r.level] or nil
end

local function fill(text, v1, v2)
	return (text:gsub("%%(%d)", function(n)
		return tostring(n == "1" and v1 or v2 or "")
	end):gsub("%%%%", "%%"))
end

-- the effect of a rune, one sentence without the final stop: "The hit forks to 2 more enemies within 3 sqm for 45% of it"
function S.effectText(id)
	local r = S.runeOf(id)
	if not r then
		return ""
	end
	local v1, v2 = S.values(id)
	return fill(r.type.text, v1, v2)
end

-- the effect of a support at every level ("20/30/40/50/60%"), for docs and the window
function S.levelsText(key)
	local t = S.byKey[key]
	if not t then
		return ""
	end
	local a, b = {}, {}
	for i = 1, S.LEVELS do
		a[i] = tostring(t.values[i])
		b[i] = t.values2 and tostring(t.values2[i]) or nil
	end
	local function join(list)
		for i = 2, #list do
			if list[i] ~= list[1] then
				return table.concat(list, "/")
			end
		end
		return list[1]
	end
	return fill(t.text, join(a), t.values2 and join(b) or nil)
end

function S.fitsText(t)
	local parts = {}
	for _, k in ipairs(t.fits) do
		parts[#parts + 1] = cfg.kindNames[k] or k
	end
	return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------------------------------------------
-- spells: which ones get sockets, what kind they are
-- ---------------------------------------------------------------------------------------------------------------
local ENTITIES = {amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'"}

-- the <instant> lines of a spells.xml: {id, name, words, script, level, mana, manaPercent, cooldown, group, tag}
function S.parseSpellsXml(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	text = text:gsub("<!%-%-.-%-%->", "")
	for tag, attrText in text:gmatch("<(%a+)(%s[^>]-)/?>") do
		tag = tag:lower()
		if tag == "instant" or tag == "conjure" or tag == "rune" then
			local a = {}
			for k, v in attrText:gmatch("([%w_]+)%s*=%s*\"([^\"]*)\"") do
				a[k:lower()] = (v:gsub("&(%a+);", function(e) return ENTITIES[e] or ("&" .. e .. ";") end))
			end
			out[#out + 1] = {tag = tag, id = tonumber(a.spellid), name = a.name, words = a.words, script = a.script,
				level = tonumber(a.level or a.lvl) or 0, mana = tonumber(a.mana) or 0, manaPercent = tonumber(a.manapercent),
				cooldown = tonumber(a.cooldown or a.exhaustion) or 0, group = a.group}
		end
	end
	return out
end

-- spell id -> entry for the spells that may carry sockets
function S.eligible(entries)
	local count, byId = {}, {}
	for _, e in ipairs(entries) do
		if e.id then
			count[e.id] = (count[e.id] or 0) + 1
		end
	end
	local none = {}
	for _, id in ipairs(cfg.none or {}) do
		none[id] = true
	end
	for _, e in ipairs(entries) do
		local script = (e.script or ""):lower()
		local ok = e.tag == "instant" and e.id and e.id > 0 and e.id <= cfg.maxSpellId and count[e.id] == 1
			and not none[e.id] and e.words and e.words:sub(1, 1) ~= "#" and not script:find("^house/")
			and not script:find("^conjuring/") and (cfg.stockSpells or script:find("^chaos/"))
		if ok then
			byId[e.id] = e
		end
	end
	return byId
end

-- the support kind of a spell from the spellbook's classification (type, target) or the override
function S.kindOf(spellId, bookType, bookTarget)
	local o = cfg.kindOverride[spellId]
	if o then
		return o
	end
	if bookType == "damage" then
		return bookTarget == "single" and "single" or "area"
	elseif bookType == "heal" then
		return "heal"
	elseif bookType == "conjure" then
		return nil
	end
	return "buff"
end

-- ---------------------------------------------------------------------------------------------------------------
-- sockets (player storages)
-- ---------------------------------------------------------------------------------------------------------------
function S.storageKey(spellId, slot)
	return cfg.storageBase + spellId * 4 + (slot or 0)
end

local function storage(player, key)
	local ok, v = pcall(function() return player:getStorageValue(key) end)
	return ok and tonumber(v) or -1
end

-- {opened = bool (3rd socket), runes = {[1..3] = id or 0}}; nil for a spell id out of range
function S.read(player, spellId)
	spellId = tonumber(spellId)
	if not spellId or spellId < 0 or spellId > cfg.maxSpellId then
		return nil
	end
	local out = {opened = storage(player, S.storageKey(spellId, 0)) == 1, runes = {}}
	for i = 1, cfg.maxSockets do
		local id = storage(player, S.storageKey(spellId, i))
		out.runes[i] = S.isRune(id) and id or 0
	end
	return out
end

function S.setRune(player, spellId, slot, id)
	player:setStorageValue(S.storageKey(spellId, slot), (id and id > 0) and id or -1)
end

function S.setOpened(player, spellId)
	player:setStorageValue(S.storageKey(spellId, 0), 1)
end

-- how many sockets a spell has: level = character level, spellLevel = the spell's level, opened = 3rd socket bought
function S.socketCount(level, spellLevel, opened)
	level, spellLevel = tonumber(level) or 0, tonumber(spellLevel) or 0
	if level < spellLevel then
		return 0
	end
	local n = 1
	if level >= math.max(cfg.second.min, spellLevel + cfg.second.add) then
		n = 2
		if opened and level >= math.max(cfg.third.min, spellLevel + cfg.third.add) then
			n = 3
		end
	end
	return n
end

function S.secondLevel(spellLevel)
	return math.max(cfg.second.min, (tonumber(spellLevel) or 0) + cfg.second.add)
end

function S.thirdLevel(spellLevel)
	return math.max(cfg.third.min, (tonumber(spellLevel) or 0) + cfg.third.add)
end

S.reasons = {
	notRune = "That is not a support rune.",
	noSpell = "That spell cannot carry supports.",
	kind = "That support does not fit this spell (%s; the spell is %s).",
	same = "This spell already has a %s rune.",
	group = "This spell already has a brand; one brand per spell.",
	full = "This spell has no free socket. Take a rune out first.",
	locked = "That socket is not open yet.",
	empty = "There is no rune in that socket.",
	mythic = "Mythic runes are the best there are; they cannot be combined.",
	needThree = "You need three runes of the same support and level to combine them.",
	opened = "The third socket of this spell is open already.",
	level3 = "The third socket needs level %d for this spell."
}

-- may rune `id` go into `slot` (or the first free one) of a spell of kind `kind` with sockets `sock` and `count`
-- open sockets? Returns slot or nil, reason
function S.canSocket(sock, count, id, kind, slot)
	local r = S.runeOf(id)
	if not r then
		return nil, S.reasons.notRune
	end
	if not kind then
		return nil, S.reasons.noSpell
	end
	if not r.type.fitsSet[kind] then
		return nil, string.format(S.reasons.kind, S.fitsText(r.type), cfg.kindNames[kind] or kind)
	end
	for i = 1, count do
		local other = S.runeOf(sock.runes[i])
		if other and i ~= slot then
			if other.type.key == r.type.key then
				return nil, string.format(S.reasons.same, r.type.name)
			end
			if r.type.group and other.type.group == r.type.group then
				return nil, S.reasons.group
			end
		end
	end
	if slot then
		if slot < 1 or slot > count then
			return nil, S.reasons.locked
		end
		if sock.runes[slot] ~= 0 then
			return nil, S.reasons.full
		end
		return slot
	end
	for i = 1, count do
		if sock.runes[i] == 0 then
			return i
		end
	end
	return nil, S.reasons.full
end

-- the summed, capped effects of a list of rune ids (only the first `count` count; nil = all):
-- key -> {value, value2, element, level}
function S.effects(runes, count)
	local out = {}
	for i, id in ipairs(runes or {}) do
		if not count or i <= count then
			local r = S.runeOf(id)
			if r then
				local v1, v2 = S.values(id)
				local e = out[r.type.key]
				if e then
					e.value = e.value + v1
					e.value2 = math.max(e.value2 or 0, v2 or 0)
					e.level = math.max(e.level, r.level)
				else
					out[r.type.key] = {value = v1, value2 = v2, element = r.type.element, level = r.level, key = r.type.key}
				end
			end
		end
	end
	for key, e in pairs(out) do
		local cap = cfg.caps[key]
		if cap then
			e.value = math.min(e.value, cap)
		end
	end
	return out
end

-- the effects of a player's spell, the open sockets only (level = character level, spellLevel = the spell's)
function S.spellEffects(player, spellId, spellLevel)
	local sock = S.read(player, spellId)
	if not sock then
		return {}
	end
	local level = 0
	pcall(function() level = player:getLevel() end)
	return S.effects(sock.runes, S.socketCount(level, spellLevel or 0, sock.opened))
end

-- ---------------------------------------------------------------------------------------------------------------
-- the cast context (spell state -> scripts state through a player storage)
-- ---------------------------------------------------------------------------------------------------------------
function S.ctxEncode(serial, spellId)
	return (serial % 1000000) * 1000 + spellId
end

-- serial, spell id (nil when no context)
function S.ctxDecode(v)
	v = tonumber(v)
	if not v or v <= 0 then
		return nil
	end
	return floor(v / 1000), v % 1000
end

-- ---------------------------------------------------------------------------------------------------------------
-- combat maths (damage values may have either sign; results keep it, rounded toward zero)
-- ---------------------------------------------------------------------------------------------------------------
function S.scale(value, pct)
	local a = floor(math.abs(value) * (100 + pct) / 100 + 1e-6)
	return value < 0 and -a or a
end

local function part(value, pct)
	local a = floor(math.abs(value) * pct / 100 + 1e-6)
	return value < 0 and -a or a
end
S.part = part

-- a hit after the target's resistance rOld (percent, may be negative), as if it had been rNew instead
function S.reresist(value, rOld, rNew)
	rOld, rNew = rOld or 0, rNew or 0
	if rOld >= 100 then
		return value
	end
	local raw = math.abs(value) * 100 / (100 - rOld)
	local a = floor(raw * math.max(0, 100 - rNew) / 100 + 1e-6)
	return value < 0 and -a or a
end

-- brand: pct of the primary part becomes element `etype`. Returns pd, pt, sd, st. resOf(ctype) = the target's
-- resistance in percent (nil = 0): the moved part loses the old element's resistance and takes the new one's.
-- Nothing changes when the secondary part holds another element already or the primary already is the element.
function S.convert(pd, pt, sd, st, pct, etype, resOf)
	if pct <= 0 or pd == 0 or pt == etype then
		return pd, pt, sd, st
	end
	if sd ~= 0 and st ~= etype then
		return pd, pt, sd, st
	end
	local moved = part(pd, math.min(100, pct))
	pd = pd - moved
	if resOf then
		moved = S.reresist(moved, resOf(pt), resOf(etype))
	end
	return pd, pt, sd + moved, etype
end

-- sunder: a hit of resistance r (percent) with pen points ignored (never below 0 resistance; immune stays immune)
function S.penetrate(value, r, pen)
	r = r or 0
	if r <= 0 or r >= 100 or pen <= 0 then
		return value
	end
	return S.reresist(value, r, math.max(0, r - pen))
end

-- chance in percent
function S.roll(chance, rand)
	return chance > 0 and (rand or S.random)(1, 100) <= chance
end

-- ---------------------------------------------------------------------------------------------------------------
-- combining, removing
-- ---------------------------------------------------------------------------------------------------------------
function S.combineResult(id)
	local r = S.runeOf(id)
	if not r then
		return nil, "notRune"
	end
	if r.level >= S.LEVELS then
		return nil, "mythic"
	end
	return S.runeId(r.type.index, r.level + 1)
end

function S.removeCost(id)
	local r = S.runeOf(id)
	return r and (cfg.removeCost[r.level] or 0) or 0
end

-- ---------------------------------------------------------------------------------------------------------------
-- drops and rewards
-- ---------------------------------------------------------------------------------------------------------------
local function gems()
	return ChaosGems
end

local function pick(weights, rand)
	local G = gems()
	if G and G.pickIndex then
		return G.pickIndex(weights, rand)
	end
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
S.pick = pick

local typeWeights
local function randomType(rand)
	if not typeWeights then
		typeWeights = {}
		for i, t in ipairs(cfg.supports) do
			typeWeights[i] = t.weight or 1
		end
	end
	return pick(typeWeights, rand)
end

function S.randomRune(levelWeights, rand)
	rand = rand or S.random
	local level = pick(levelWeights, rand)
	local t = level and randomType(rand)
	return t and S.runeId(t, level) or nil
end

-- level weights by monster level: the gems' drop table
function S.levelWeights(level)
	local G = gems()
	if G and G.levelWeights then
		return G.levelWeights(level)
	end
	return {85, 15, 0, 0, 0}
end

-- a monster kill: list of rune ids (0 or 1). tier = monster tier, level = monster level (or the killer's),
-- scale = the loot layer's rate x item find
function S.rollDrop(tier, level, scale, rand)
	rand = rand or S.random
	local chance = (cfg.drop.chance[tier] or 0) * (tonumber(scale) or 1)
	if chance <= 0 or rand(1, 1000000) > chance * 100 then
		return {}
	end
	local id = S.randomRune(S.levelWeights(level), rand)
	if not id then
		return {}
	end
	local up = cfg.drop.tierUp[tier] or 0
	if up > 0 and rand(1, 100) <= up then
		id = S.combineResult(id) or id
	end
	return {id}
end

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

-- reward runes: list of {id, count} merged by id.
--   "rift"       opts = {tier = n}
--   "bounty"     opts = {type = "hunt"|"elite"|"boss", band = 1..6} (level weights: the gems' bounty band table)
--   "worldboss"  opts = {share = 0..1}
function S.rewardRunes(kind, opts, rand)
	rand = rand or S.random
	opts = opts or {}
	local r = cfg.rewards
	local count, weights = 0, nil
	if kind == "rift" then
		local tier = math.max(1, tonumber(opts.tier) or 1)
		count = fractional(r.rift.base + r.rift.perTier * tier, rand)
		weights = rowWeights(r.rift.tierWeights, tier)
	elseif kind == "bounty" then
		if rand(1, 100) <= (r.bounty.chance[opts.type or "hunt"] or 0) then
			count = r.bounty.count
		end
		local G = gems()
		local bands = G and G.config and G.config.rewards and G.config.rewards.bounty.bandWeights
		weights = bands and bands[clamp(tonumber(opts.band) or 1, 1, #bands)] or {80, 20, 0, 0, 0}
	elseif kind == "worldboss" then
		count = r.worldboss.count + fractional((r.worldboss.countShare or 0) * clamp(tonumber(opts.share) or 0, 0, 1), rand)
		weights = r.worldboss.weights
	end
	local merged, order = {}, {}
	for _ = 1, count do
		local id = weights and S.randomRune(weights, rand)
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

-- "2 Rare Fork Runes, Epic Hex Rune"
function S.listText(list)
	local parts = {}
	for _, e in ipairs(list) do
		if S.isRune(e.id) then
			local name = S.runeName(e.id)
			parts[#parts + 1] = (e.count or 1) > 1 and (e.count .. " " .. name .. "s") or name
		end
	end
	return table.concat(parts, ", ")
end

-- the item description (items.xml, install_supports.py writes it from the same text)
function S.description(typeIndex, level)
	local t = cfg.supports[typeIndex]
	local id = S.runeId(typeIndex, level)
	local effect = S.effectText(id)
	local text = string.format("A support rune for a spell socket: %s. Fits %s spells.", effect:sub(1, 1):lower()
		.. effect:sub(2), S.fitsText(t))
	if level < S.LEVELS then
		text = text .. " Three of them combine into one of the next level."
	end
	return text .. " Use it to open the spell supports (Character > Spell Supports)."
end

return S
