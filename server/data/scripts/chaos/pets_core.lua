-- Pets: pure logic (no engine calls), shared by pets.lua and server/tests/pets_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible (integers through math.floor). Numbers: pets_config.lua.
--
-- Species
--   K.species(key, cfg)                  the species entry (nil when unknown)
--   K.speciesByMonster(name, cfg)        the species whose monster type is `name` (any case)
-- Levels (the stored value is the pet's total XP)
--   K.xpNeed(level, cfg)                 XP from `level` to level + 1 (nil at the max level)
--   K.totalFor(level, cfg)               XP from level 1 to `level`
--   K.levelOf(xp, cfg)                   level, XP into the level, XP the level needs (0 at max), percent
--   K.capXp(xp, cfg)                     xp clamped to [0, total of the max level]
--   K.killXp(info, cfg)                  pet XP of one kill {tier, monsterExp, ownerLevel, summon}
-- Abilities
--   K.abilityValue(key, petLevel, ownerLevel, cfg)    the number shown / used (percent, squares or damage)
--   K.abilitiesOf(species, petLevel, ownerLevel, cfg) the species' abilities for the window, with unlock state
--   K.hasAbility(species, key, petLevel, cfg)         true when that ability is unlocked
--   K.auraDamage(ownerLevel, petLevel, cfg)           min, max of one aura hit
--   K.mendAmount(petLevel, maxHealth, cfg)            health healed by Mend
--   K.zoneRule(flags, cfg)                            "banned" | "utility" | "full" for {arena, siege, pvpZone, rift, ...}
--   K.abilityActive(kind, rule, inPvp)                may an ability of `kind` work now
-- Obtaining
--   K.dropChance(species, monsterName, tier, counted) chance of one kill to drop that species
--   K.rollDrop(monsterName, tier, rand, cfg, counted) the species key a kill drops, or nil
--   K.grantKind(owned, key)                           "new" or "xp" (a duplicate)
-- Gold
--   K.coins(value)                       {crystal, platinum, gold} of a gold value
--   K.goldBonus(value, pct, rand)        extra gold of Gold Sniffer for a corpse
-- Following
--   K.distance(a, b)                     squares between two positions (math.huge on another floor)
--   K.blocking(petPos, ownerPos, threats, cfg)   anti-block: should the pet step away
--   K.restReason(s), K.restText(reason)  why the pet rests now (pz, zone, summons, hidden) and the message
-- Rules and texts
--   K.validName(raw, cfg, reserved)      name or nil, reason
--   K.cooldownLeft(readyAt, now)         whole seconds left (0 when ready)
--   K.summonError(s, cfg)                nil or why the pet cannot be summoned now
--   K.view(row, ownerLevel, now, cfg)    one pet for the window
--   K.number(v)                          "7.5" / "12" (one decimal at most)

ChaosPetsCore = ChaosPetsCore or {}
local K = ChaosPetsCore

local floor = math.floor

-- ---------------------------------------------------------------- species
function K.species(key, cfg)
	for _, s in ipairs(cfg.species) do
		if s.key == key then
			return s
		end
	end
	return nil
end

function K.speciesByMonster(name, cfg)
	name = (name or ""):lower()
	for _, s in ipairs(cfg.species) do
		if s.monster:lower() == name then
			return s
		end
	end
	return nil
end

-- ---------------------------------------------------------------- levels
function K.xpNeed(level, cfg)
	if not level or level < 1 or level >= cfg.maxLevel then
		return nil
	end
	return floor(cfg.curve.base * level ^ cfg.curve.power)
end

function K.totalFor(level, cfg)
	local sum = 0
	for l = 1, math.min(level, cfg.maxLevel) - 1 do
		sum = sum + K.xpNeed(l, cfg)
	end
	return sum
end

function K.capXp(xp, cfg)
	xp = floor(tonumber(xp) or 0)
	if xp < 0 then
		return 0
	end
	return math.min(xp, K.totalFor(cfg.maxLevel, cfg))
end

function K.levelOf(xp, cfg)
	xp = K.capXp(xp, cfg)
	local level = 1
	while level < cfg.maxLevel do
		local need = K.xpNeed(level, cfg)
		if xp < need then
			return level, xp, need, floor(xp * 100 / need)
		end
		xp = xp - need
		level = level + 1
	end
	return cfg.maxLevel, 0, 0, 100
end

function K.killXp(info, cfg)
	if type(info) ~= "table" or info.summon then
		return 0
	end
	local tier = info.tier or "normal"
	local bonus = cfg.xp.tier[tier] or 0
	if bonus == 0 and (info.monsterExp or 0) < (info.ownerLevel or 1) * cfg.xp.minExpPerLevel then
		return 0
	end
	return cfg.xp.perKill + bonus
end

-- ---------------------------------------------------------------- abilities
local function round1(v)
	return floor(v * 10 + 0.5) / 10
end

function K.auraDamage(ownerLevel, petLevel, cfg)
	local a = cfg.abilities.aura
	local base = (ownerLevel or 1) * a.levelFactor + (petLevel or 1) * a.petFactor
	return floor(base * (1 - a.spread)), floor(base * (1 + a.spread))
end

function K.abilityValue(key, petLevel, ownerLevel, cfg)
	local a = cfg.abilities[key]
	if not a then
		return 0
	end
	petLevel = math.max(1, math.min(petLevel or 1, cfg.maxLevel))
	if key == "aura" then
		local lo, hi = K.auraDamage(ownerLevel, petLevel, cfg)
		return floor((lo + hi) / 2)
	elseif key == "fetch" then
		return floor(a.base + a.perLevel * (petLevel - 1))
	end
	return round1(a.base + a.perLevel * (petLevel - 1))
end

function K.number(v)
	v = tonumber(v) or 0
	if v == floor(v) then
		return string.format("%d", v)
	end
	return string.format("%.1f", v)
end

function K.unlockLevel(index, cfg)
	return index == 1 and 1 or cfg.secondAt
end

function K.hasAbility(species, key, petLevel, cfg)
	for i, k in ipairs(species and species.abilities or {}) do
		if k == key then
			return (petLevel or 1) >= K.unlockLevel(i, cfg)
		end
	end
	return false
end

function K.abilitiesOf(species, petLevel, ownerLevel, cfg)
	local out = {}
	for i, key in ipairs(species and species.abilities or {}) do
		local a = cfg.abilities[key]
		if a then
			local value = K.abilityValue(key, petLevel, ownerLevel, cfg)
			out[#out + 1] = {key = key, name = a.name, kind = a.kind, value = value,
				desc = string.format(a.desc, K.number(value)), unlockAt = K.unlockLevel(i, cfg),
				unlocked = (petLevel or 1) >= K.unlockLevel(i, cfg), cooldown = a.cooldown or 0}
		end
	end
	return out
end

function K.mendAmount(petLevel, maxHealth, cfg)
	return floor((maxHealth or 0) * K.abilityValue("mend", petLevel, 1, cfg) / 100)
end

local ZONE_ORDER = {"arena", "siege", "pvpZone", "rift", "worldBoss", "tower", "dungeon"}
function K.zoneRule(flags, cfg)
	local rule = "full"
	for _, z in ipairs(ZONE_ORDER) do
		if flags and flags[z] then
			local r = cfg.zones[z] or "full"
			if r == "banned" then
				return "banned", z
			elseif r == "utility" then
				rule = "utility"
			end
		end
	end
	return rule
end

function K.abilityActive(kind, rule, inPvp)
	if rule == "banned" then
		return false
	end
	if kind == "combat" then
		return rule == "full" and not inPvp
	end
	return true
end

-- ---------------------------------------------------------------- obtaining
-- counted: the kill counts for pet XP (K.killXp > 0); a drop from any monster needs it, a drop from listed monsters
-- only needs a kill that gave experience (the caller does not ask for summons or monsters without experience)
function K.dropChance(species, monsterName, tier, counted)
	local d = species and species.source and species.source.drop
	if not d then
		return 0
	end
	if d.monsters then
		local name, hit = (monsterName or ""):lower(), false
		for _, m in ipairs(d.monsters) do
			if m:lower() == name then
				hit = true
				break
			end
		end
		if not hit then
			return 0
		end
	elseif not counted then
		return 0
	end
	local mult = d.tierMult and d.tierMult[tier or "normal"] or 1
	return math.min(1, d.chance * mult)
end

function K.rollDrop(monsterName, tier, rand, cfg, counted)
	rand = rand or math.random
	for _, s in ipairs(cfg.species) do
		local c = K.dropChance(s, monsterName, tier, counted)
		if c > 0 and rand() < c then
			return s.key
		end
	end
	return nil
end

-- what a source gives: "new" (a new pet) or "xp" (a duplicate: duplicateXp for the pet already owned)
function K.grantKind(owned, key)
	return owned and owned[key] and "xp" or "new"
end

-- ---------------------------------------------------------------- gold
-- coins of a gold value, largest first: crystal (10,000), platinum (100), gold (1)
function K.coins(value)
	value = floor(tonumber(value) or 0)
	if value <= 0 then
		return {crystal = 0, platinum = 0, gold = 0}
	end
	local crystal = floor(value / 10000)
	value = value - crystal * 10000
	local platinum = floor(value / 100)
	return {crystal = crystal, platinum = platinum, gold = value - platinum * 100}
end

-- extra gold of Gold Sniffer for a corpse holding `value` gold: value x pct / 100, the fraction rolled
-- (12.5 -> 12, or 13 half the time)
function K.goldBonus(value, pct, rand)
	value, pct = tonumber(value) or 0, tonumber(pct) or 0
	if value <= 0 or pct <= 0 then
		return 0
	end
	local exact = value * pct / 100
	local whole = floor(exact)
	if (rand or math.random)() < exact - whole then
		whole = whole + 1
	end
	return whole
end

-- ---------------------------------------------------------------- following and blocking
function K.distance(a, b)
	if not a or not b or a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- anti-block: true when a monster that targets the owner stands within block.range of the pet but is not next to
-- the owner (the pet may be in its way). threats = {{pos = position}, ...} of monsters targeting the owner.
function K.blocking(petPos, ownerPos, threats, cfg)
	for _, t in ipairs(threats or {}) do
		if K.distance(t.pos, petPos) <= cfg.block.range and K.distance(t.pos, ownerPos) > 1 then
			return true
		end
	end
	return false
end

-- why the pet rests now (nil = it may be out). s = {inPz, zone = "banned"|..., zoneName, otherSummons, hiddenUntil, now}
local REST_TEXT = {
	pz = "Your pet waits for you outside the protection zone.",
	zone = "Pets are not allowed here; yours waits until you leave.",
	summons = "Your pet stays back while you have other summons.",
	hidden = "Your pet steps out of the way."
}
function K.restReason(s)
	if s.zone == "banned" then
		return "zone"
	elseif s.inPz then
		return "pz"
	elseif s.otherSummons then
		return "summons"
	elseif (s.hiddenUntil or 0) > (s.now or 0) then
		return "hidden"
	end
	return nil
end

function K.restText(reason)
	return REST_TEXT[reason or ""]
end

-- ---------------------------------------------------------------- rules and texts
-- reserved(name) -> true when the name may not be used (a monster type of the server); optional
function K.validName(raw, cfg, reserved)
	if type(raw) ~= "string" then
		return nil, "Give a name."
	end
	local name = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	if #name < cfg.name.min or #name > cfg.name.max then
		return nil, string.format("A pet name has %d to %d letters.", cfg.name.min, cfg.name.max)
	end
	if not name:match("^[A-Za-z][A-Za-z ]*[A-Za-z]$") then
		return nil, "A pet name has only letters and single spaces."
	end
	-- capitalise every word: "ember" -> "Ember", "mister whiskers" -> "Mister Whiskers"
	name = name:lower():gsub("(%a)(%a*)", function(a, b) return a:upper() .. b end)
	if reserved and reserved(name) then
		return nil, "That name belongs to a creature of this world. Pick another one."
	end
	return name
end

function K.cooldownLeft(readyAt, now)
	local left = (readyAt or 0) - (now or 0)
	if left <= 0 then
		return 0
	end
	return math.ceil(left)
end

-- s = {owned, now, summonReady, deathReady, zone, zoneName, inPz, dead}
function K.summonError(s, cfg)
	if not s.owned then
		return "You do not own that pet."
	end
	if s.zone == "banned" then
		return "Pets are not allowed here" .. (s.zoneName and (" (" .. s.zoneName .. ")") or "") .. "."
	end
	local death = K.cooldownLeft(s.deathReady, s.now)
	if death > 0 then
		return string.format("Your pet is still recovering from your death: %d s.", death)
	end
	local cd = K.cooldownLeft(s.summonReady, s.now)
	if cd > 0 then
		return string.format("Wait %d s before calling a pet again.", cd)
	end
	return nil
end

function K.view(row, ownerLevel, now, cfg)
	local species = K.species(row.species, cfg)
	if not species then
		return nil
	end
	local level, into, need, pct = K.levelOf(row.xp, cfg)
	return {
		id = row.id, species = species.key, speciesName = species.name, name = row.name ~= "" and row.name or species.name,
		look = species.look, element = species.element, level = level, maxLevel = cfg.maxLevel, xp = row.xp, into = into,
		need = need, pct = pct, active = row.active == 1 or row.active == true, source = row.source or "",
		abilities = K.abilitiesOf(species, level, ownerLevel, cfg)
	}
end

return K
