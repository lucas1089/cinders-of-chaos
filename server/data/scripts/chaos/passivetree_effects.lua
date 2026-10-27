-- Passive tree effects: turns the summed node stats (ChaosPassiveTree.getBonuses) into real bonuses.
--
-- Registered as a listener of passivetree.lua, so it runs after every save, reset and login:
--   * character stats (strength ... spirit), turned into a value by a two-tier curve up to a cap (ChaosPassiveCharStat),
--     with the same effect the engine gives the stat window's points but WITHOUT writing the character stats (those
--     are saved with the player and are the stat window's points: writing them made the bonus stack on every login
--     and let the stat window refund it as free points). `value` below is the curve's:
--       strength / intelligence: damage dealt x (1 + value/230) for physical / every other type (engine formula)
--       dexterity: weapon hits (melee, distance, wand) x 1 / (1 - value/100), the damage equal of the engine's
--         "attack time - value%" (a script cannot change the attack speed)
--       vitality / spirit: max health / max mana + value% (condition)
--       wisdom: no effect (the engine gives none)
--   * skills, magic level, critical hit, leech: a permanent CONDITION_ATTRIBUTES (sub ids 7200+)
--   * absorbs: the second absorb storage of each damage type (977562-977573) that the stock absorb
--     event already reads (the first one belongs to equipment)
--   * damage dealt (incrementX, multiIncrement, incrementHealth): CreatureEvent on the target
--   * experience: EventCallback onGainExperience
--   * loot / rarity loot: the item-find storage that loot.lua reads
--   * speed: Creature:changeSpeed by the difference to what was applied before
-- Paragon (paragon.lua) adds its percentages to the same bonus table (keys paragonX) and they are summed here with the
-- tree's, never applied on their own: damage (a multiplier after the tree's), crit damage (+ criticalHitAmount, one
-- condition), max health / mana (+ vitality / spirit, one condition each, sub ids 7220 / 7221), damage reduction
-- (+ every absorb storage), item find (+ the item-find storage), speed (% of base speed + the tree's flat speed).
-- Gold find is paragon.lua's own onDropLoot.
-- All numbers that turn a node value into a game value are in cfg below. Not run on a server.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.listeners = ChaosPassiveTree.listeners or {}
ChaosPassiveCache = ChaosPassiveCache or {}

local cfg = {
	experiencePerPoint = 0.1, -- node value 30 = +3.0% experience
	lootPerPoint = 0.2,       -- node value 10 = +2.0% item find
	rarityLootPerPoint = 1.0, -- node value 10 = +10% (added to item find)
	speedPerPoint = 0.1,      -- node value 600 = +60 speed, before the cap
	maxSpeed = 80,
	maxAbsorb = 75,           -- percent, passive absorbs only (equipment adds on top)
	maxDamagePercent = 150,
	-- the stat window formulas are percentages (vitality = % health, dexterity = % damage taken less).
	-- A character stat's value (what those formulas take) follows two straight lines (ChaosPassiveCharStat):
	--   up to charStatKnee points: charStatKneeShare (80%) of charStatMax, the same share per point;
	--   from the knee to charStatCap points: the other 20%; nothing above the cap.
	-- charStatMax is the old maximum, so the effect at the cap is unchanged (strength / intelligence 60 = +26%,
	-- dexterity 20 = weapon hits x1.25, vitality / spirit 50 = +50%). 2026-10-22: the path nodes alone had filled the old
	-- caps (60 / 60 / 20 / 50 / 50, now the knees) after 50-100 points; the caps doubled (dexterity x4) and the points
	-- past the knee give the last 20%. Dexterity's maximum stays 20 (at 40 knights out-damaged everyone at level 1000).
	-- Wisdom has no effect (its numbers are unused).
	charStatKnee = {strength = 60, intelligence = 60, dexterity = 20, vitality = 50, spirit = 50, wisdom = 40},
	charStatCap = {strength = 120, intelligence = 120, dexterity = 80, vitality = 100, spirit = 100, wisdom = 40},
	charStatMax = {strength = 60, intelligence = 60, dexterity = 20, vitality = 50, spirit = 50, wisdom = 40},
	charStatKneeShare = 0.8,
	-- Soft caps (O146, beta feedback "everything over the cap is wasted"): the caps above and maxDamagePercent are where the
	-- full value ends, not a wall. Past a cap the extra raw points go through ChaosSoftCap:
	--   effective = cap + H x ln(1 + (raw - cap) / H)      (raw > cap; below the cap effective = raw)
	-- It is continuous, never decreasing, has slope 1 at the cap (the first extra point is worth as much as the last point
	-- below the cap would be in a straight line) and the slope falls to H / (H + extra): never zero, no upper limit.
	-- charStat: H in points (= the cap, so twice the cap in points counts as 1.69 x the cap effective), then the value goes
	-- on along the slope the curve had at the cap (strength 280 points: 120 + 120 ln(2.33) = 221 effective points). damagePercent: H in percent points; at +150 raw the full 150, at +300 raw
	-- 150 + 60 ln(3.5) = 225, at +400 raw 150 + 60 ln(5.17) = 248, +1000 raw 150 + 60 ln(15.2) = 313.
	-- dexterityValueCeiling: the dexterity value is a divisor (1 / (1 - value / 100)); it stays under this whatever the points
	softCap = {
		charStatH = {strength = 120, intelligence = 120, dexterity = 80, vitality = 100, spirit = 100, wisdom = 40},
		damagePercentH = 60,
		dexterityValueCeiling = 50
	}
}
ChaosPassiveEffectsConfig = cfg


local STAT_INDEX = {
	strength = CHARSTAT_STRENGTH, intelligence = CHARSTAT_INTELLIGENCE, dexterity = CHARSTAT_DEXTERITY,
	vitality = CHARSTAT_VITALITY, spirit = CHARSTAT_SPIRIT, wisdom = CHARSTAT_WISDOM
}

-- tree stat -> {condition parameter, sub id}
local CONDITIONS = {
	swordSkill = {CONDITION_PARAM_SKILL_SWORD, 7200},
	axeSkill = {CONDITION_PARAM_SKILL_AXE, 7201},
	clubSkill = {CONDITION_PARAM_SKILL_CLUB, 7202},
	distanceSkill = {CONDITION_PARAM_SKILL_DISTANCE, 7203},
	shieldingSkill = {CONDITION_PARAM_SKILL_SHIELD, 7204},
	skillShield = {CONDITION_PARAM_SKILL_SHIELD, 7205},
	craftingSkill = {CONDITION_PARAM_SKILL_CRAFTING, 7206},
	woodcuttingSkill = {CONDITION_PARAM_SKILL_WOODCUTTING, 7207},
	miningSkill = {CONDITION_PARAM_SKILL_MINING, 7208},
	herbalistSkill = {CONDITION_PARAM_SKILL_HERBALIST, 7209},
	armorsmithSkill = {CONDITION_PARAM_SKILL_ARMORSMITH, 7210},
	weaponsmithSkill = {CONDITION_PARAM_SKILL_WEAPONSMITH, 7211},
	jewelsmithSkill = {CONDITION_PARAM_SKILL_JEWELSMITH, 7212},
	magicSkill = {CONDITION_PARAM_STAT_MAGICPOINTS, 7213},
	criticalHitChance = {CONDITION_PARAM_SPECIALSKILL_CRITICALHITCHANCE, 7214},
	criticalHitAmount = {CONDITION_PARAM_SPECIALSKILL_CRITICALHITAMOUNT, 7215},
	lifeLeechChance = {CONDITION_PARAM_SPECIALSKILL_LIFELEECHCHANCE, 7216},
	lifeLeechAmount = {CONDITION_PARAM_SPECIALSKILL_LIFELEECHAMOUNT, 7217},
	manaLeechChance = {CONDITION_PARAM_SPECIALSKILL_MANALEECHCHANCE, 7218},
	manaLeechAmount = {CONDITION_PARAM_SPECIALSKILL_MANALEECHAMOUNT, 7219}
}

-- absorb stat -> {combat type, storage}; elements are also raised by absorbAllElements
local ABSORB = {
	absorbFire = {COMBAT_FIREDAMAGE, 977562}, absorbPhysical = {COMBAT_PHYSICALDAMAGE, 977563},
	absorbEnergy = {COMBAT_ENERGYDAMAGE, 977564}, absorbEarth = {COMBAT_EARTHDAMAGE, 977565},
	absorbDrown = {COMBAT_DROWNDAMAGE, 977566}, absorbIce = {COMBAT_ICEDAMAGE, 977567},
	absorbHoly = {COMBAT_HOLYDAMAGE, 977568}, absorbDeath = {COMBAT_DEATHDAMAGE, 977569},
	absorbWater = {COMBAT_WATERDAMAGE, 977570}, absorbArcane = {COMBAT_ARCANEDAMAGE, 977571},
	absorbLife = {COMBAT_LIFEDRAIN, 977573}, absorbMana = {COMBAT_MANADRAIN, 977575}
}
local ELEMENT_ABSORB = {"absorbFire", "absorbEnergy", "absorbEarth", "absorbDrown", "absorbIce", "absorbHoly",
	"absorbDeath", "absorbWater", "absorbArcane"}

-- damage dealt: combat type -> tree stat; multiIncrement adds to the elements only
local INCREMENT = {
	[COMBAT_PHYSICALDAMAGE] = "incrementPhysical", [COMBAT_FIREDAMAGE] = "incrementFire",
	[COMBAT_ICEDAMAGE] = "incrementIce", [COMBAT_ENERGYDAMAGE] = "incrementEnergy",
	[COMBAT_EARTHDAMAGE] = "incrementEarth", [COMBAT_DEATHDAMAGE] = "incrementDeath",
	[COMBAT_HOLYDAMAGE] = "incrementHoly", [COMBAT_DROWNDAMAGE] = "incrementDrown",
	[COMBAT_WATERDAMAGE] = "incrementWater", [COMBAT_ARCANEDAMAGE] = "incrementArcane",
	[COMBAT_LIFEDRAIN] = "incrementLifeDrain", [COMBAT_MANADRAIN] = "incrementManaDrain",
	[COMBAT_HEALING] = "incrementHealth"
}
local IS_ELEMENT = {
	[COMBAT_FIREDAMAGE] = true, [COMBAT_ICEDAMAGE] = true, [COMBAT_ENERGYDAMAGE] = true,
	[COMBAT_EARTHDAMAGE] = true, [COMBAT_DEATHDAMAGE] = true, [COMBAT_HOLYDAMAGE] = true,
	[COMBAT_DROWNDAMAGE] = true, [COMBAT_WATERDAMAGE] = true, [COMBAT_ARCANEDAMAGE] = true
}

-- per player id: what this script added last time {speed = n, stats = {name = {applied, last}}}
local applied = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
-- scale a damage value (it may be negative) rounding toward zero
local function scale(v, m)
	local a = math.floor(math.abs(v * m) + 1e-6) -- epsilon: 100 * 1.13 may come out as 112.99999999999999
	return v < 0 and -a or a
end

-- ---------------------------------------------------------------- pure part (testable)
-- Soft cap: full value up to `cap`, then cap + H ln(1 + (raw - cap) / H) (see cfg.softCap). Pure, monotonic, unbounded.
function ChaosSoftCap(raw, cap, H)
	raw = raw or 0
	if raw <= cap then
		return raw
	end
	return cap + H * math.log(1 + (raw - cap) / H)
end

-- the damage percent a combat type gets from the tree before the soft cap (the sum the stat window shows as raw)
function ChaosPassiveDamageRaw(bonuses, combatType)
	local stat = INCREMENT[combatType]
	if not stat then
		return 0
	end
	local pct = bonuses[stat] or 0
	if IS_ELEMENT[combatType] then
		pct = pct + (bonuses.multiIncrement or 0)
	end
	return math.max(0, pct)
end

function ChaosPassiveDamagePercent(bonuses, combatType)
	return ChaosSoftCap(ChaosPassiveDamageRaw(bonuses, combatType), cfg.maxDamagePercent, cfg.softCap.damagePercentH)
end

-- Paragon damage: every damage type, not healing (multiplies after the tree's own bonuses)
function ChaosParagonDamageMultiplier(bonuses, combatType)
	local pct = bonuses.paragonDamage or 0
	if pct <= 0 or combatType == COMBAT_HEALING or combatType == COMBAT_NONE then
		return 1
	end
	return 1 + pct / 100
end

-- tree absorb + Paragon damage reduction (all types), whole percent: the absorb event reads integer storages
function ChaosPassiveAbsorbPercent(bonuses, statName)
	local v = bonuses[statName] or 0
	for _, name in ipairs(ELEMENT_ABSORB) do
		if name == statName then
			v = v + (bonuses.absorbAllElements or 0)
		end
	end
	v = v + (bonuses.paragonReduction or 0)
	return math.floor(clamp(v, 0, cfg.maxAbsorb) + 1e-6)
end

function ChaosPassiveExperienceMultiplier(bonuses)
	return 1 + (bonuses.experience or 0) * cfg.experiencePerPoint / 100
end

function ChaosPassiveItemFind(bonuses)
	return math.floor((bonuses.loot or 0) * cfg.lootPerPoint + (bonuses.rarityLoot or 0) * cfg.rarityLootPerPoint
		+ (bonuses.paragonItemFind or 0) + 1e-6)
end

function ChaosPassiveSpeed(bonuses)
	return clamp(math.floor((bonuses.speed or 0) * cfg.speedPerPoint), 0, cfg.maxSpeed)
end

-- Paragon speed: percent of the base speed (vocation base + 2 per level), added to the tree's flat speed
function ChaosParagonSpeed(bonuses, baseSpeed)
	return math.floor((baseSpeed or 0) * (bonuses.paragonSpeed or 0) / 100 + 1e-6)
end

-- the effect value of a character stat from its tree points: charStatKneeShare of charStatMax spread evenly over the
-- points up to the knee, the rest over the points from the knee to the cap, and above the cap the soft cap (O146): the
-- value goes on with the slope it had at the cap, shrinking as cap + H ln(1 + extra / H) (see cfg.softCap). Rounded to
-- 1e-6 so the knee and the cap give exact numbers (60 x 0.8 = 48, not 47.99999999999999).
function ChaosPassiveCharStat(points, stat)
	local knee, cap, max = cfg.charStatKnee[stat], cfg.charStatCap[stat], cfg.charStatMax[stat]
	local share = cfg.charStatKneeShare
	local raw = math.max(0, points or 0)
	local p = math.min(raw, cap)
	local v
	if p <= knee then
		v = max * share * p / knee
	else
		v = max * share + max * (1 - share) * (p - knee) / (cap - knee)
	end
	if raw > cap then
		local slope = cap > knee and max * (1 - share) / (cap - knee) or 0
		v = v + slope * (ChaosSoftCap(raw, cap, cfg.softCap.charStatH[stat]) - cap)
		if stat == "dexterity" then
			v = math.min(v, cfg.softCap.dexterityValueCeiling)
		end
	end
	return math.floor(v * 1e6 + 0.5) / 1e6
end

-- max health / mana percent: tree vitality / spirit (capped, scaled) + Paragon health / mana
local PARAGON_PERCENT = {vitality = "paragonHealth", spirit = "paragonMana"}
-- the share of the stat that comes from a held Vocation Trial node (trials.lua addBonuses writes it next to the summed
-- stat): outside the tree's cap, like the Paragon share. A character at the tree's +50% got nothing from Steelblood (+8%)
-- when the cap cut the sum.
local TRIAL_PERCENT = {vitality = "trialVitality", spirit = "trialSpirit"}
function ChaosPassiveMaxPercent(bonuses, stat)
	local trial = math.max(0, bonuses[TRIAL_PERCENT[stat] or ""] or 0)
	return ChaosPassiveCharStat((bonuses[stat] or 0) - trial, stat) + trial + (bonuses[PARAGON_PERCENT[stat]] or 0)
end

-- condition stats that Paragon adds to (one condition for both, so neither overwrites the other)
local PARAGON_CONDITION = {criticalHitAmount = "paragonCritDamage"}
function ChaosPassiveConditionValue(bonuses, stat)
	local v = (bonuses[stat] or 0) + (bonuses[PARAGON_CONDITION[stat] or ""] or 0)
	return math.floor(v + 1e-6)
end

-- ---------------------------------------------------------------- applying
local function setCondition(player, stat, value)
	local info = CONDITIONS[stat]
	player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, info[2], true)
	if value > 0 then
		local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
		c:setTicks(-1)
		c:setParameter(CONDITION_PARAM_SUBID, info[2])
		c:setParameter(info[1], value)
		player:addCondition(c)
	end
end

-- vitality / spirit (+ Paragon health / mana) as % max health / mana (sub ids next to the skill conditions).
-- One condition per stat holds the tree's and the Paragon share together. Whole percents use the engine's percent
-- parameter; a fractional sum (Paragon has 0.5% steps) uses the flat parameter with the same formula the engine uses
-- for the percent one (the maximum at the moment the condition starts, without this condition, x percent / 100).
local PERCENT = {
	vitality = {CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT, 7220, CONDITION_PARAM_STAT_MAXHITPOINTS, "getMaxHealth"},
	spirit = {CONDITION_PARAM_STAT_MAXMANAPOINTSPERCENT, 7221, CONDITION_PARAM_STAT_MAXMANAPOINTS, "getMaxMana"},
}

-- the flat parameter is an int32 in the engine (getNumber<int32_t>): a character whose maximum was inflated earlier
-- (536 million mana seen live, 2026-10-24) made max x percent pass 2^31 and the whole opcode died in setParameter.
-- Clamped into the range; a non-number or NaN maximum gives 0.
local INT32_MAX = 2147483647
function ChaosPassiveFlatMax(base, percent)
	local v = math.floor((tonumber(base) or 0) * (tonumber(percent) or 0) / 100)
	if v ~= v then
		return 0
	end
	return math.max(0, math.min(INT32_MAX, v))
end

local function applyCharStats(player, bonuses)
	for stat, info in pairs(PERCENT) do
		local value = ChaosPassiveMaxPercent(bonuses, stat)
		player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT, info[2], true)
		if value > 0 then
			local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_DEFAULT)
			c:setTicks(-1)
			c:setParameter(CONDITION_PARAM_SUBID, info[2])
			local whole = math.floor(value + 1e-6)
			if math.abs(value - whole) < 1e-6 then
				c:setParameter(info[1], 100 + whole)
			else
				c:setParameter(info[3], ChaosPassiveFlatMax(player[info[4]](player), value))
			end
			player:addCondition(c)
		end
	end
end

-- Older versions wrote the bonus into the character stats, which the server saves: clamp them back to what the
-- stat window allows (StatsMaxValues of the base server's stat window script), once per character.
local function fixLegacyStats(player)
	local key = Chaos.storage.passiveStatsFixed
	if not key or player:getStorageValue(key) == 1 then
		return
	end
	if StatsMaxValues then
		for _, index in pairs(STAT_INDEX) do
			local max = StatsMaxValues[index]
			if max and player:getCharacterStat(index) > max then
				player:setCharacterStat(index, max)
			end
		end
	end
	player:setStorageValue(key, 1)
end
ChaosPassiveFixLegacyStats = fixLegacyStats

local WEAPON_ORIGIN = {}
if ORIGIN_MELEE then
	WEAPON_ORIGIN[ORIGIN_MELEE], WEAPON_ORIGIN[ORIGIN_RANGED], WEAPON_ORIGIN[ORIGIN_WAND] = true, true, true
end

-- damage multiplier from strength / intelligence / dexterity (pure, testable)
function ChaosPassiveStatMultiplier(bonuses, combatType, origin)
	local m
	if combatType == COMBAT_PHYSICALDAMAGE then
		m = 1 + ChaosPassiveCharStat(bonuses.strength, "strength") / 230
	else
		m = 1 + ChaosPassiveCharStat(bonuses.intelligence, "intelligence") / 230
	end
	if WEAPON_ORIGIN[origin] then
		m = m / (1 - ChaosPassiveCharStat(bonuses.dexterity, "dexterity") / 100)
	end
	return m
end

-- tree flat speed + Paragon percent of the base speed
local function totalSpeed(player, bonuses)
	local speed = ChaosPassiveSpeed(bonuses)
	if (bonuses.paragonSpeed or 0) > 0 then
		speed = speed + ChaosParagonSpeed(bonuses, player:getBaseSpeed())
	end
	return speed
end

local function applyAll(player, bonuses)
	local id = player:getId()
	local state = applied[id] or {speed = 0}
	applied[id] = state
	ChaosPassiveCache[id] = bonuses
	-- the tree's Healing for the potion scripts (another Lua state): potions_config.lua storage.healingPct
	if not ChaosPotionsConfig then
		pcall(dofile, "data/scripts/chaos/potions_config.lua")
	end
	local potionStorage = ChaosPotionsConfig and ChaosPotionsConfig.storage and ChaosPotionsConfig.storage.healingPct
	if potionStorage then
		player:setStorageValue(potionStorage, math.floor(ChaosPassiveDamagePercent(bonuses, COMBAT_HEALING)))
	end
	for stat in pairs(CONDITIONS) do
		setCondition(player, stat, ChaosPassiveConditionValue(bonuses, stat))
	end
	for stat, info in pairs(ABSORB) do
		player:setStorageValue(info[2], ChaosPassiveAbsorbPercent(bonuses, stat))
	end
	local find = (ChaosLootConfig and ChaosLootConfig.itemFindStorage) or 7100040
	if find then
		player:setStorageValue(find, ChaosPassiveItemFind(bonuses))
	end
	applyCharStats(player, bonuses)
	local speed = totalSpeed(player, bonuses)
	if speed ~= state.speed then
		player:changeSpeed(speed - state.speed)
		state.speed = speed
	end
end
ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners + 1] = applyAll

-- the Paragon speed share follows the base speed, which grows with every level (paragon.lua calls this on level up)
function ChaosPassiveRefreshSpeed(player)
	local id = player:getId()
	local state, bonuses = applied[id], ChaosPassiveCache[id]
	if not state or not bonuses then
		return
	end
	local speed = totalSpeed(player, bonuses)
	if speed ~= state.speed then
		player:changeSpeed(speed - state.speed)
		state.speed = speed
	end
end

-- the class factor of a player's damage (class_tree.lua classDamage by class or line, and level), 1 for the others
if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
function ChaosPassiveLineFactor(player)
	local vocation = player.getVocation and player:getVocation()
	if not vocation or not ChaosClassTree or not player.getLevel then
		return 1
	end
	local id = vocation:getId()
	return ChaosClassTree.damageFactor(ChaosClasses.classKey(id), ChaosClasses.lineKey(id), player:getLevel())
end

-- the class factor on spell damage (spell_factor_config.lua, spell_factor_core.lua)
if not ChaosSpellFactorConfig then
	dofile("data/scripts/chaos/spell_factor_config.lua")
end
if not ChaosSpellFactor or not ChaosSpellFactor.factor then
	dofile("data/scripts/chaos/spell_factor_core.lua")
end

-- ---------------------------------------------------------------- damage dealt / healing
local dealt = CreatureEvent("ChaosPassiveDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	-- keystone procs (passivetree_keystones.lua) are a share of a hit that already had these bonuses
	local procActive = ChaosKeystones and ChaosKeystones.depth and ChaosKeystones.depth > 0
	if attacker and attacker:isPlayer() and not procActive then
		-- the class spell factor (server/README.md "Class spell factor"): spell damage only, never healing
		local vocation = attacker.getVocation and attacker:getVocation()
		local vocId = vocation and vocation:getId() or 0
		local level = attacker.getLevel and attacker:getLevel() or nil
		local f1 = ChaosSpellFactor.factor(vocId, origin, primaryType, ORIGIN_SPELL, COMBAT_HEALING, procActive, nil, level)
		local f2 = ChaosSpellFactor.factor(vocId, origin, secondaryType, ORIGIN_SPELL, COMBAT_HEALING, procActive, nil, level)
		if f1 ~= 1 then
			primaryDamage = scale(primaryDamage, f1)
		end
		if f2 ~= 1 then
			secondaryDamage = scale(secondaryDamage, f2)
		end
		local bonuses = ChaosPassiveCache[attacker:getId()]
		if bonuses then
			-- the factor of the classes tuned without a tree (class_tree.lua classDamage); not on healing
			local line = ChaosPassiveLineFactor(attacker)
			local m1 = (1 + ChaosPassiveDamagePercent(bonuses, primaryType) / 100) * ChaosPassiveStatMultiplier(bonuses, primaryType, origin)
				* ChaosParagonDamageMultiplier(bonuses, primaryType) * (primaryType == COMBAT_HEALING and 1 or line)
			local m2 = (1 + ChaosPassiveDamagePercent(bonuses, secondaryType) / 100) * ChaosPassiveStatMultiplier(bonuses, secondaryType, origin)
				* ChaosParagonDamageMultiplier(bonuses, secondaryType) * (secondaryType == COMBAT_HEALING and 1 or line)
			if m1 ~= 1 then
				primaryDamage = scale(primaryDamage, m1)
			end
			if m2 ~= 1 then
				secondaryDamage = scale(secondaryDamage, m2)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

-- register the event on whatever a passive-tree player attacks (same approach as the equipment scripts)
-- Chaos.registerOnce / eventKnown (chaos_constants.lua): register on a monster once, not at every hit
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local function eventKnown(creature, name)
	local f = Chaos and Chaos.eventKnown
	return f ~= nil and f(creature, name)
end
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and ChaosPassiveCache[creature:getId()] then
		registerOnce(target, "ChaosPassiveDealt")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- every monster gets the event when it appears: an area spell also hits monsters the player never targeted, and their
-- damage must carry the tree's bonuses too (before, only the attacked target was registered, so area hits on the others
-- had no tree bonus and no class damage factor)
local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	self:registerEvent("ChaosPassiveDealt")
	return true
end
spawnCb:register()

-- experience
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	local bonuses = ChaosPassiveCache[self:getId()]
	if bonuses and source then
		return math.floor(exp * ChaosPassiveExperienceMultiplier(bonuses))
	end
	return exp
end
xpCb:register()

local login = CreatureEvent("ChaosPassiveEffectsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPassiveDealt") -- own heals and heals from others pass through the target's events
	fixLegacyStats(player)
	return true
end
login:register()

local logout = CreatureEvent("ChaosPassiveEffectsLogout")
function logout.onLogout(player)
	applied[player:getId()] = nil
	ChaosPassiveCache[player:getId()] = nil
	return true
end
logout:register()
