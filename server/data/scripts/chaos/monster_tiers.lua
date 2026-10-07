-- Monster tiers (normal / magic / rare / legendary / boss) + the monster bar (extended opcode 125)
--
-- * Tiers: a monster can be created as magic, rare or legendary (health, speed, damage and
--   experience multipliers, set in ChaosTiers below). Bosses are MonsterType:isBoss() or listed in cfg.bosses.
-- * Roll on spawn: every spawned monster rolls cfg.spawnChance (per 10000).
-- * Ambush on kill: when a player kills a monster there is a chance that a magic, rare or
--   legendary copy of it appears next to the corpse (cfg.ambush).
-- * Client (game_monsterbar): {"action":"query","data":{"cid":N}} when the player targets a creature,
--   answered with {"action":"info","data":{"cid":N,"tier":"rare","name":"Dragon","mult":{...}}}.
--
-- Not verified on a running server. Assumed engine API: EventCallback onSpawn (Monster:onSpawn in
-- data/events/scripts/monster.lua), onGainExperience (arg 3 modifiable), CreatureEvent "death" and
-- "healthchange", Creature:setMaxHealth/changeSpeed, Game.createMonster(name, pos, extended, force).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.monsterbar

ChaosTiers = {
	magic = {label = "Magic", hp = 2.0, speed = 10, damage = 1.25, xp = 2.0, effect = CONST_ME_MAGIC_BLUE},
	rare = {label = "Rare", hp = 3.5, speed = 20, damage = 1.5, xp = 4.0, effect = CONST_ME_YELLOWENERGY or CONST_ME_MAGIC_GREEN},
	legendary = {label = "Legendary", hp = 6.0, speed = 30, damage = 2.0, xp = 10.0, effect = CONST_ME_FIREAREA}
}

local cfg = {
	-- chance (out of 10000) that a freshly spawned monster is born with a tier; rolled magic->legendary
	spawnChance = {magic = 600, rare = 150, legendary = 25},
	-- ambush: chance (out of 10000) that a kill of a monster with the given tier brings a tiered copy
	ambush = {normal = 400, magic = 800, rare = 1500, legendary = 2500},
	-- which tier the ambush copy will have (weights)
	ambushTier = {magic = 70, rare = 25, legendary = 5},
	maxChain = 2, -- an ambush copy can itself bring at most this many more copies in a row
	minMaxHealth = 50, -- ignore critters
	skip = {}, -- lowercase monster names that never get a tier or an ambush
	bosses = {}, -- lowercase names treated as boss even if the monster file has no isboss flag
	announceLegendary = true
}
ChaosTierConfig = cfg

-- creature id -> {tier = "rare", depth = 0}
ChaosTierState = ChaosTierState or {}
local state = ChaosTierState
local pendingTier, pendingDepth = nil, 0

local function isBoss(monster)
	local name = monster:getName():lower()
	if cfg.bosses[name] then
		return true
	end
	local mt = monster:getType()
	if mt then
		local ok, res = pcall(function() return mt:isBoss() end)
		if ok and res then
			return true
		end
	end
	return false
end

function ChaosTierOf(creature)
	if not creature or not creature:isMonster() then
		return "normal"
	end
	local s = state[creature:getId()]
	if s then
		return s.tier
	end
	return isBoss(creature) and "boss" or "normal"
end

local function eligible(monster)
	if monster:getMaster() then
		return false
	end
	if cfg.skip[monster:getName():lower()] or isBoss(monster) then
		return false
	end
	return monster:getMaxHealth() >= cfg.minMaxHealth
end

local function applyTier(monster, tier, depth)
	local t = ChaosTiers[tier]
	if not t then
		return
	end
	local maxHealth = math.floor(monster:getMaxHealth() * t.hp)
	monster:setMaxHealth(maxHealth)
	monster:setHealth(maxHealth)
	monster:changeSpeed(t.speed)
	state[monster:getId()] = {tier = tier, depth = depth or 0}
	monster:registerEvent("ChaosTierDeath")
	monster:getPosition():sendMagicEffect(t.effect)
	if tier == "legendary" and cfg.announceLegendary then
		for _, p in ipairs(Game.getSpectators(monster:getPosition(), false, true, 9, 9, 7, 7)) do
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, "A legendary " .. monster:getName() .. " appears!")
		end
	end
end

local function pickWeighted(weights)
	local total = 0
	for _, w in pairs(weights) do
		total = total + w
	end
	local roll = math.random(total)
	for name, w in pairs(weights) do
		roll = roll - w
		if roll <= 0 then
			return name
		end
	end
end

-- natural roll on spawn
local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if pendingTier then
		local tier, depth = pendingTier, pendingDepth
		pendingTier = nil
		if eligible(self) then
			applyTier(self, tier, depth)
		end
		return true
	end
	if eligible(self) then
		local roll = math.random(10000)
		for _, tier in ipairs({"legendary", "rare", "magic"}) do
			if roll <= cfg.spawnChance[tier] then
				applyTier(self, tier, 0)
				break
			end
		end
	end
	return true
end
spawnCb:register()

-- ambush on kill + state cleanup
local death = CreatureEvent("ChaosTierDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local s = state[creature:getId()]
	state[creature:getId()] = nil
	local credit = mostDamageKiller or killer
	if not credit or not credit:isPlayer() then
		return true
	end
	local tier = s and s.tier or "normal"
	local depth = s and s.depth or 0
	if depth >= cfg.maxChain or not eligible(creature) then
		return true
	end
	if math.random(10000) > (cfg.ambush[tier] or 0) then
		return true
	end
	local newTier = pickWeighted(cfg.ambushTier)
	local pos = creature:getPosition()
	addEvent(function(name, position, nt, d)
		pendingTier, pendingDepth = nt, d
		Game.createMonster(name, position, true, false)
		pendingTier = nil
	end, 600, creature:getName(), pos, newTier, depth + 1)
	pos:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
death:register()

-- applyTier registers the death event for tiered monsters; normal ones get it here so that
-- killing a normal monster can also bring an ambush.
local normalDeath = EventCallback
normalDeath.onSpawn = function(self, position, startup, artificial)
	if not state[self:getId()] and eligible(self) then
		self:registerEvent("ChaosTierDeath")
	end
	return true
end
normalDeath:register()

-- damage taken by players from tiered monsters
local hit = CreatureEvent("ChaosTierHit")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and attacker:isMonster() then
		local s = state[attacker:getId()]
		if s then
			local m = ChaosTiers[s.tier].damage
			return math.floor(primaryDamage * m), primaryType, math.floor(secondaryDamage * m), secondaryType
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

local login = CreatureEvent("ChaosTierLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTierHit")
	player:registerEvent("ChaosTierQuery")
	return true
end
login:register()

-- experience bonus
local xpCb = EventCallback
xpCb.onGainExperience = function(self, source, exp, rawExp)
	if source and source:isMonster() then
		local s = state[source:getId()]
		if s then
			return math.floor(exp * ChaosTiers[s.tier].xp)
		end
	end
	return exp
end
xpCb:register()

-- monster bar protocol
local query = CreatureEvent("ChaosTierQuery")
function query.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "query" or type(msg.data) ~= "table" then
		return
	end
	local cid = tonumber(msg.data.cid)
	local creature = cid and Creature(cid)
	if not creature or not creature:isMonster() then
		return
	end
	if player:getPosition():getDistance(creature:getPosition()) > 15 then
		return
	end
	local tier = ChaosTierOf(creature)
	local t = ChaosTiers[tier]
	Chaos.send(player, OPCODE, "info", {
		cid = cid,
		tier = tier,
		name = creature:getName(),
		label = t and t.label or nil,
		mult = t and {hp = t.hp, damage = t.damage, xp = t.xp} or nil
	})
end
query:register()
