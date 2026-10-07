-- Monster tiers (normal / magic / rare / legendary / boss), modifiers, shaders and the monster bar
-- (extended opcode 125).
--
-- * Tiers: a monster can be created as magic, rare or legendary (health, speed, damage and
--   experience multipliers in ChaosTiers). Bosses are MonsterType:isBoss() or listed in cfg.bosses.
-- * Modifiers: every non-normal monster rolls modifiers (magic 1-2, rare 2-3, legendary 3-4,
--   boss 4-5, see cfg.modCount) from ChaosMods: burning hits, venom, vampiric, stoneskin, ...
-- * Shaders: the monster is drawn with the outfit shader of its strongest modifier (ids 1-17 of
--   data/XML/shaders.xml, registered by the client). A rotating magic effect shows the others.
-- * Roll on spawn: every spawned monster rolls cfg.spawnChance (per 10000).
-- * Ambush on kill: when a player kills a monster there is a chance that a magic, rare or
--   legendary copy of it appears next to the corpse (cfg.ambush).
-- * Client (game_monsterbar): {"action":"query","data":{"cid":N}} when the player targets a creature,
--   answered with {"action":"info","data":{"cid","tier","label","mods":["Blazing",..],"mult":{..}}}.
--
-- Not verified on a running server. Assumed engine API: EventCallback onSpawn (Monster:onSpawn in
-- data/events/scripts/monster.lua), onGainExperience (arg 3 modifiable), CreatureEvent "death" and
-- "healthchange" (damages may arrive positive or negative: math.abs is used where the sign matters),
-- Creature:setMaxHealth/changeSpeed/setOutfit with lookShader, Condition(), Game.createMonster.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

local OPCODE = ChaosOpcodes.monsterbar

ChaosTiers = {
	magic = {label = "Magic", hp = 2.0, speed = 10, damage = 1.25, xp = 2.0, effect = CONST_ME_MAGIC_BLUE},
	rare = {label = "Rare", hp = 3.5, speed = 20, damage = 1.5, xp = 4.0, effect = CONST_ME_YELLOWENERGY or CONST_ME_MAGIC_GREEN},
	legendary = {label = "Legendary", hp = 6.0, speed = 30, damage = 2.0, xp = 10.0, effect = CONST_ME_FIREAREA},
	-- bosses keep their own stats; the multipliers here only apply when cfg.bossScaling is on
	boss = {label = "Boss", hp = 1.0, speed = 0, damage = 1.0, xp = 1.0, effect = CONST_ME_MORTAREA}
}

local cfg = {
	spawnChance = {magic = 600, rare = 150, legendary = 25}, -- out of 10000
	ambush = {normal = 400, magic = 800, rare = 1500, legendary = 2500}, -- out of 10000 per kill
	ambushTier = {magic = 70, rare = 25, legendary = 5}, -- weights of the copy's tier
	maxChain = 2,
	minMaxHealth = 50,
	skip = {}, -- lowercase monster names that never get a tier or an ambush
	bosses = {}, -- lowercase names treated as boss even without the isboss flag
	bossMods = true, -- bosses get modifiers (and their shader)
	modCount = {magic = {1, 2}, rare = {2, 3}, legendary = {3, 4}, boss = {4, 5}},
	tickMs = 2500, -- ambient effect / regeneration step
	announceLegendary = true
}
ChaosTierConfig = cfg

-- Modifiers. shader = id in data/XML/shaders.xml, power decides which modifier colours the monster.
-- hp/speed/damage are multipliers or additions applied when the modifier is rolled; the on* hooks
-- are called by the handlers below.
local function heal(monster, amount)
	if amount > 0 then
		monster:addHealth(math.min(amount, monster:getMaxHealth() - monster:getHealth()))
	end
end

local function dot(player, ctype, total, rounds)
	local c = Condition(ctype)
	c:setParameter(CONDITION_PARAM_DELAYED, 1)
	c:addDamage(rounds, 2000, -math.max(1, math.floor(total / rounds)))
	player:addCondition(c)
end

ChaosMods = {
	blazing = {name = "Blazing", shader = 14, power = 3, effect = CONST_ME_HITBYFIRE,
		onHit = function(m, p, dmg) if math.random(100) <= 30 then dot(p, CONDITION_FIRE, dmg * 0.6, 5) end end},
	chilling = {name = "Chilling", shader = 10, power = 3, effect = CONST_ME_ICEAREA,
		onHit = function(m, p, dmg)
			if math.random(100) <= 25 then
				local c = Condition(CONDITION_PARALYZE)
				c:setParameter(CONDITION_PARAM_TICKS, 3000)
				c:setFormula(-0.7, 56, -0.7, 56)
				p:addCondition(c)
			end
		end},
	venomous = {name = "Venomous", shader = 16, power = 3, effect = CONST_ME_POISONAREA,
		onHit = function(m, p, dmg) if math.random(100) <= 30 then dot(p, CONDITION_POISON, dmg * 0.6, 6) end end},
	shocking = {name = "Shocking", shader = 12, power = 3, effect = CONST_ME_ENERGYAREA,
		onHit = function(m, p, dmg) if math.random(100) <= 25 then dot(p, CONDITION_ENERGY, dmg * 0.8, 3) end end},
	vampiric = {name = "Vampiric", shader = 9, power = 4, effect = CONST_ME_MAGIC_RED,
		onHit = function(m, p, dmg) heal(m, math.floor(dmg * 0.3)) end},
	berserker = {name = "Berserker", shader = 11, power = 4, effect = CONST_ME_HITAREA,
		damage = function(m) return m:getHealth() < m:getMaxHealth() * 0.5 and 1.5 or 1.0 end},
	brutal = {name = "Brutal", shader = 3, power = 2, effect = CONST_ME_DRAWBLOOD, damage = 1.4},
	stoneskin = {name = "Stoneskin", shader = 7, power = 2, effect = CONST_ME_STONES, taken = 0.7},
	reflective = {name = "Reflective", shader = 13, power = 4, effect = CONST_ME_MAGIC_BLUE,
		onTaken = function(m, attacker, dmg)
			if attacker and attacker:isPlayer() then
				doTargetCombatHealth(m, attacker, COMBAT_PHYSICALDAMAGE, -math.floor(dmg * 0.15), -math.floor(dmg * 0.15), CONST_ME_NONE)
			end
		end},
	regenerating = {name = "Regenerating", shader = 2, power = 1, effect = CONST_ME_MAGIC_GREEN,
		onTick = function(m) heal(m, math.floor(m:getMaxHealth() * 0.02)) end},
	swift = {name = "Swift", shader = 17, power = 1, effect = CONST_ME_POFF, speed = 40},
	explosive = {name = "Explosive", shader = 15, power = 3, effect = CONST_ME_FIREATTACK,
		onDeath = function(m)
			local pos = m:getPosition()
			local dmg = math.max(50, math.floor(m:getMaxHealth() * 0.05))
			pos:sendMagicEffect(CONST_ME_EXPLOSIONAREA)
			for _, p in ipairs(Game.getSpectators(pos, false, true, 2, 2, 2, 2)) do
				doTargetCombatHealth(m, p, COMBAT_FIREDAMAGE, -dmg, -dmg, CONST_ME_EXPLOSIONHIT)
			end
		end},
	juggernaut = {name = "Juggernaut", shader = 6, power = 2, effect = CONST_ME_STUN, hp = 1.6}
}
ChaosModList = {}
for key in pairs(ChaosMods) do
	ChaosModList[#ChaosModList + 1] = key
end
table.sort(ChaosModList)

-- creature id -> {tier = "rare", depth = 0, mods = {"blazing", ...}, step = 0}
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

local function rollMods(tier)
	local range = cfg.modCount[tier]
	if not range then
		return {}
	end
	local count = math.random(range[1], range[2])
	local pool = {}
	for i, key in ipairs(ChaosModList) do
		pool[i] = key
	end
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		picked[#picked + 1] = table.remove(pool, math.random(#pool))
	end
	return picked
end

local function primaryMod(mods)
	local best
	for _, key in ipairs(mods) do
		if not best or ChaosMods[key].power > ChaosMods[best].power then
			best = key
		end
	end
	return best
end

local function applyMods(monster, mods)
	local hp, speed = 1.0, 0
	for _, key in ipairs(mods) do
		local m = ChaosMods[key]
		hp = hp * (m.hp or 1.0)
		speed = speed + (m.speed or 0)
	end
	if hp ~= 1.0 then
		local maxHealth = math.floor(monster:getMaxHealth() * hp)
		monster:setMaxHealth(maxHealth)
		monster:setHealth(maxHealth)
	end
	if speed ~= 0 then
		monster:changeSpeed(speed)
	end
	local main = primaryMod(mods)
	if main then
		local outfit = monster:getOutfit()
		outfit.lookShader = ChaosMods[main].shader
		monster:setOutfit(outfit)
	end
	monster:registerEvent("ChaosModTaken")
end

-- one "info" message for a creature (used for the monster bar query and for the in-world labels)
local function sendInfo(player, creature)
	local cid = creature:getId()
	local tier = ChaosTierOf(creature)
	local t = ChaosTiers[tier]
	local s = state[cid]
	local names = {}
	for _, key in ipairs(s and s.mods or {}) do
		names[#names + 1] = ChaosMods[key].name
	end
	Chaos.send(player, OPCODE, "info", {
		cid = cid,
		tier = tier,
		name = creature:getName(),
		label = (t and tier ~= "boss") and t.label or nil,
		mods = names,
		mult = t and {hp = t.hp, damage = t.damage, xp = t.xp} or nil
	})
end

local function tick(id)
	local monster = Monster(id)
	local s = state[id]
	if not monster or not s or not s.mods then
		return
	end
	s.step = (s.step or 0) + 1
	local key = s.mods[(s.step - 1) % #s.mods + 1]
	local m = ChaosMods[key]
	monster:getPosition():sendMagicEffect(m.effect)
	-- push the tier and modifiers to players in view (resent every 15 s) so the client can label the monster
	s.sent = s.sent or {}
	local now = os.time()
	for _, p in ipairs(Game.getSpectators(monster:getPosition(), false, true, 10, 10, 8, 8)) do
		local pid = p:getId()
		if not s.sent[pid] or now - s.sent[pid] >= 15 then
			s.sent[pid] = now
			sendInfo(p, monster)
		end
	end
	for _, k in ipairs(s.mods) do
		local mod = ChaosMods[k]
		if mod.onTick then
			mod.onTick(monster)
		end
	end
	addEvent(tick, cfg.tickMs, id)
end

local function applyTier(monster, tier, depth)
	local t = ChaosTiers[tier]
	if not t then
		return
	end
	if tier ~= "boss" then
		local maxHealth = math.floor(monster:getMaxHealth() * t.hp)
		monster:setMaxHealth(maxHealth)
		monster:setHealth(maxHealth)
		monster:changeSpeed(t.speed)
	end
	local mods = rollMods(tier)
	state[monster:getId()] = {tier = tier, depth = depth or 0, mods = mods, step = 0}
	monster:registerEvent("ChaosTierDeath")
	applyMods(monster, mods)
	monster:getPosition():sendMagicEffect(t.effect)
	if #mods > 0 then
		addEvent(tick, cfg.tickMs, monster:getId())
	end
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
				return true
			end
		end
	elseif cfg.bossMods and not self:getMaster() and not cfg.skip[self:getName():lower()] and isBoss(self) then
		applyTier(self, "boss", 0)
	end
	return true
end
spawnCb:register()

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

-- death: modifiers, then the ambush
local death = CreatureEvent("ChaosTierDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local id = creature:getId()
	local s = state[id]
	state[id] = nil
	if s and s.mods then
		for _, key in ipairs(s.mods) do
			local mod = ChaosMods[key]
			if mod.onDeath then
				mod.onDeath(creature)
			end
		end
	end
	local credit = mostDamageKiller or killer
	if not credit or not credit:isPlayer() then
		return true
	end
	local tier = s and s.tier or "normal"
	local depth = s and s.depth or 0
	if tier == "boss" or depth >= cfg.maxChain or not eligible(creature) then
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

-- damage taken BY a tiered monster (stoneskin, reflective)
local taken = CreatureEvent("ChaosModTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local s = state[creature:getId()]
	if s and s.mods and attacker and attacker:isPlayer() then
		local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
		for _, key in ipairs(s.mods) do
			local mod = ChaosMods[key]
			if mod.taken then
				primaryDamage = math.floor(primaryDamage * mod.taken)
				secondaryDamage = math.floor(secondaryDamage * mod.taken)
			end
			if mod.onTaken then
				mod.onTaken(creature, attacker, total)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- damage dealt TO players by a tiered monster (tier and modifier multipliers, on-hit effects)
local hit = CreatureEvent("ChaosTierHit")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and attacker:isMonster() then
		local s = state[attacker:getId()]
		if s then
			local mult = ChaosTiers[s.tier].damage
			for _, key in ipairs(s.mods or {}) do
				local d = ChaosMods[key].damage
				if type(d) == "function" then
					d = d(attacker)
				end
				mult = mult * (d or 1.0)
			end
			primaryDamage = math.floor(primaryDamage * mult)
			secondaryDamage = math.floor(secondaryDamage * mult)
			if creature:isPlayer() then
				local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
				for _, key in ipairs(s.mods or {}) do
					local mod = ChaosMods[key]
					if mod.onHit then
						mod.onHit(attacker, creature, total)
					end
				end
			end
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
	sendInfo(player, creature)
end
query:register()
