-- Passive tree effects: turns the summed node stats (ChaosPassiveTree.getBonuses) into real bonuses.
--
-- Registered as a listener of passivetree.lua, so it runs after every save, reset and login:
--   * character stats (strength ... wisdom): added on top of the stat window values, capped (charStatCap)
--   * skills, magic level, critical hit, leech: a permanent CONDITION_ATTRIBUTES (sub ids 7200+)
--   * absorbs: the second absorb storage of each damage type (977562-977573) that the stock absorb
--     event already reads (the first one belongs to equipment)
--   * damage dealt (incrementX, multiIncrement, incrementHealth): CreatureEvent on the target
--   * experience: EventCallback onGainExperience
--   * loot / rarity loot: the item-find storage that loot.lua reads
--   * speed: Creature:changeSpeed by the difference to what was applied before
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
	maxAbsorb = 80,           -- percent, passive absorbs only (equipment adds on top)
	maxDamagePercent = 150,
	-- the stat window formulas are percentages (vitality = % health, dexterity = % damage taken less):
	charStatCap = {strength = 60, intelligence = 60, dexterity = 40, vitality = 50, spirit = 50, wisdom = 40},
	checkMs = 5000
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
function ChaosPassiveDamagePercent(bonuses, combatType)
	local stat = INCREMENT[combatType]
	if not stat then
		return 0
	end
	local pct = bonuses[stat] or 0
	if IS_ELEMENT[combatType] then
		pct = pct + (bonuses.multiIncrement or 0)
	end
	return clamp(pct, 0, cfg.maxDamagePercent)
end

function ChaosPassiveAbsorbPercent(bonuses, statName)
	local v = bonuses[statName] or 0
	for _, name in ipairs(ELEMENT_ABSORB) do
		if name == statName then
			v = v + (bonuses.absorbAllElements or 0)
		end
	end
	return clamp(v, 0, cfg.maxAbsorb)
end

function ChaosPassiveExperienceMultiplier(bonuses)
	return 1 + (bonuses.experience or 0) * cfg.experiencePerPoint / 100
end

function ChaosPassiveItemFind(bonuses)
	return math.floor((bonuses.loot or 0) * cfg.lootPerPoint + (bonuses.rarityLoot or 0) * cfg.rarityLootPerPoint)
end

function ChaosPassiveSpeed(bonuses)
	return clamp(math.floor((bonuses.speed or 0) * cfg.speedPerPoint), 0, cfg.maxSpeed)
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

local function applyCharStats(player, bonuses, state)
	state.stats = state.stats or {}
	for name, index in pairs(STAT_INDEX) do
		local want = clamp(bonuses[name] or 0, 0, cfg.charStatCap[name])
		local s = state.stats[name] or {applied = 0, last = nil}
		local current = player:getCharacterStat(index)
		if s.last ~= nil and current ~= s.last then
			s.applied = 0 -- the stat window rewrote the value: our part is gone
		end
		local newValue = current - s.applied + want
		if newValue ~= current then
			player:setCharacterStat(index, newValue)
		end
		s.applied, s.last = want, newValue
		state.stats[name] = s
	end
end

local function applyAll(player, bonuses)
	local id = player:getId()
	local state = applied[id] or {speed = 0}
	applied[id] = state
	ChaosPassiveCache[id] = bonuses

	for stat in pairs(CONDITIONS) do
		setCondition(player, stat, math.floor(bonuses[stat] or 0))
	end
	for stat, info in pairs(ABSORB) do
		player:setStorageValue(info[2], ChaosPassiveAbsorbPercent(bonuses, stat))
	end
	local find = (ChaosLootConfig and ChaosLootConfig.itemFindStorage) or 7100040
	if find then
		player:setStorageValue(find, ChaosPassiveItemFind(bonuses))
	end
	applyCharStats(player, bonuses, state)
	local speed = ChaosPassiveSpeed(bonuses)
	if speed ~= state.speed then
		player:changeSpeed(speed - state.speed)
		state.speed = speed
	end
end
ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners + 1] = applyAll

-- the stat window may rewrite a character stat later: re-sync every few seconds
local function check(playerId)
	local player = Player(playerId)
	if not player then
		applied[playerId] = nil
		ChaosPassiveCache[playerId] = nil
		return
	end
	local state, bonuses = applied[playerId], ChaosPassiveCache[playerId]
	if state and bonuses then
		applyCharStats(player, bonuses, state)
	end
	addEvent(check, cfg.checkMs, playerId)
end

-- ---------------------------------------------------------------- damage dealt / healing
local dealt = CreatureEvent("ChaosPassiveDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and attacker:isPlayer() then
		local bonuses = ChaosPassiveCache[attacker:getId()]
		if bonuses then
			local p1 = ChaosPassiveDamagePercent(bonuses, primaryType)
			local p2 = ChaosPassiveDamagePercent(bonuses, secondaryType)
			if p1 > 0 then
				primaryDamage = scale(primaryDamage, 1 + p1 / 100)
			end
			if p2 > 0 then
				secondaryDamage = scale(secondaryDamage, 1 + p2 / 100)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

-- register the event on whatever a passive-tree player attacks (same approach as the equipment scripts)
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and ChaosPassiveCache[creature:getId()] then
		target:registerEvent("ChaosPassiveDealt")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

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
	addEvent(check, cfg.checkMs, player:getId())
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
