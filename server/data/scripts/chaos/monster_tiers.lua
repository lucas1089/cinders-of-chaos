-- Monster tiers (normal / magic / rare / legendary / boss), modifiers, shaders and the monster bar
-- (extended opcode 125).
--
-- * Tiers: a monster can be created as magic, rare or legendary (health, speed, damage and
--   experience multipliers in ChaosTiers). Bosses are MonsterType:isBoss() or listed in cfg.bosses.
-- * Modifiers: every non-normal monster rolls modifiers (magic 1-2, rare 2-3, legendary 3-4,
--   boss 4-5, see cfg.modCount) from ChaosMods: burning hits, venom, vampiric, stoneskin, ...
-- * Shaders: the monster is drawn with the outfit shader of its strongest modifier (ids 1-17 of
--   data/XML/shaders.xml, registered by the client). A rotating magic effect shows the others.
-- * Roll on spawn: every spawned monster rolls cfg.spawnChance (per 10000). The tier is applied at its first think,
--   after the placement (the engine gives a monster its id there); see "natural roll on spawn" below.
-- * Ambush on kill: when a player kills a monster there is a chance that a magic, rare or
--   legendary copy of it appears next to the corpse (cfg.ambush).
-- * Client (game_monsterbar): {"action":"query","data":{"cid":N}} when the player targets a creature,
--   answered with {"action":"info","data":{"cid","tier","label","role","level","mods":["Blazing",..],"mult":{..}}}
--   (role: "guardian" for a rift guardian, "omen" for an Omen guardian; level: ChaosLoot.monsterLevel).
--
-- Not verified on a running server. Assumed engine API: EventCallback onSpawn (Monster:onSpawn in
-- data/events/scripts/monster.lua), onGainExperience (arg 3 modifiable), CreatureEvent "death" and
-- "healthchange" (damages may arrive positive or negative: math.abs is used where the sign matters),
-- Creature:setMaxHealth/changeSpeed/setOutfit with lookShader, Condition(), Game.createMonster.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
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
	-- modifiers that never come together: two sources of healing made a monster that could not be brought below 90% (beta
	-- report 2026-10-20: Vampiric + Juggernaut + Regenerating)
	exclusive = {{"vampiric", "regenerating"}},
	tickMs = 2500, -- ambient effect / regeneration step
	announceLegendary = true,
	-- the spawn chance multipliers (event day x Chaos Storm ...) multiply, at most this much together
	maxSpawnMult = 3.0
}
ChaosTierConfig = cfg

-- A training monster (a trainer or a dummy: names with "train" or "dummy") never gets a tier or its modifiers; its
-- health and behaviour have to stay what the training room says (owner 2026-10-17: trainers spawned with monster
-- modifiers). cfg.skip lists exact names; this adds the training names without listing each one.
local function isSkipped(name)
	name = tostring(name or ""):lower()
	return cfg.skip[name] == true or name:find("train", 1, true) ~= nil or name:find("dummy", 1, true) ~= nil
end
ChaosTierIsSkipped = isSkipped

-- the multiplier on spawnChance at a position: the Chaos Rift day (events_schedule.lua) x the Chaos Storm
-- (worldevents.lua), capped at cfg.maxSpawnMult (2 x 1.5 x 3 was 9x)
function ChaosTierSpawnMult(position)
	local m = ChaosEvents and ChaosEvents.bonus("tierChance") or 1
	m = m * (ChaosWorldEvents and ChaosWorldEvents.tierMult and ChaosWorldEvents.tierMult(position) or 1)
	local cap = tonumber(cfg.maxSpawnMult)
	if cap and m > cap then
		m = cap
	end
	return m
end

-- World bosses (worldboss.lua): boss tier for the client (their XML also has isboss="1"; this is the fallback) but
-- no random modifiers: Regenerating, Juggernaut or Explosive (5% of max health on death) would wreck the tuned fight.
for _, b in ipairs(Chaos.worldBoss and Chaos.worldBoss.bosses or {}) do
	cfg.bosses[b.name:lower()] = true
	cfg.skip[b.name:lower()] = true
end

-- Modifiers. shader = id in data/XML/shaders.xml, power decides which modifier colours the monster.
-- hp/speed/damage are multipliers or additions applied when the modifier is rolled; the on* hooks
-- are called by the handlers below.
local function heal(monster, amount)
	if amount > 0 then
		Chaos.heal(monster, amount)
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
		onHit = function(m, p, dmg) heal(m, math.floor(dmg * 0.15)) end},
	berserker = {name = "Berserker", shader = 11, power = 4, effect = CONST_ME_HITAREA,
		damage = function(m) return m:getHealth() < m:getMaxHealth() * 0.5 and 1.5 or 1.0 end},
	brutal = {name = "Brutal", shader = 3, power = 2, effect = CONST_ME_DRAWBLOOD, damage = 1.4},
	stoneskin = {name = "Stoneskin", shader = 7, power = 2, effect = CONST_ME_STONES, taken = 0.7},
	reflective = {name = "Reflective", shader = 13, power = 4, effect = CONST_ME_MAGIC_BLUE,
		onTaken = function(m, attacker, dmg)
			if attacker and attacker:isPlayer() then
				if ChaosCombatFx then
					ChaosCombatFx.reflect(m) -- shield flash on the reflecting monster (combat_fx.lua, throttled)
				end
				doTargetCombatHealth(m, attacker, COMBAT_PHYSICALDAMAGE, -math.floor(dmg * 0.15), -math.floor(dmg * 0.15), CONST_ME_NONE)
			end
		end},
	regenerating = {name = "Regenerating", shader = 2, power = 1, effect = CONST_ME_MAGIC_GREEN,
		onTick = function(m) heal(m, math.floor(m:getMaxHealth() * 0.01)) end},
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
-- older versions applied the natural roll inside onSpawn, before the monster had an id, and left an entry under id 0
-- (the table outlives a reload); no monster has id 0, drop it
state[0] = nil
local pendingTier -- set around the creation of an ambush copy (no natural roll for it)

local function isBoss(monster)
	local name = typeNameOf(monster):lower() -- a renamed rift monster or invader is still its type
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

-- a display monster of the hunt teleport room (hunt_teleports.lua): no tier, no modifiers
local function isDisplaySpot(pos)
	local HT = ChaosHuntTeleports
	return pos ~= nil and HT ~= nil and HT.isDisplaySpot ~= nil and HT.isDisplaySpot(pos) == true
end

local function eligible(monster, position)
	if monster:getMaster() or isDisplaySpot(position or monster:getPosition()) then
		return false
	end
	if isSkipped(typeNameOf(monster)) or isBoss(monster) then
		return false
	end
	-- a monster of a running Vocation Trial (O187): the trial counts its kills, no tier and no ambush copy of it
	if ChaosTrials and ChaosTrials.isTrialMonster and ChaosTrials.isTrialMonster(monster) then
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
		local key = table.remove(pool, math.random(#pool))
		picked[#picked + 1] = key
		for _, group in ipairs(cfg.exclusive or {}) do
			local inGroup = false
			for _, k in ipairs(group) do
				inGroup = inGroup or k == key
			end
			if inGroup then
				for i = #pool, 1, -1 do -- the rest of its group leaves the pool
					for _, k in ipairs(group) do
						if pool[i] == k then
							table.remove(pool, i)
							break
						end
					end
				end
			end
		end
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

-- the monster bar's role of a creature: "omen" (an Omen guardian) or "guardian" (a rift guardian), read from
-- rift.lua's run of the monster (ChaosRift.monsterRun, run.bossIds); nil for every other monster
local function roleOf(creature)
	local rift = ChaosRift
	local run = rift and rift.monsterRun and rift.monsterRun[creature:getId()]
	if run and run.bossIds and run.bossIds[creature:getId()] then
		return run.omen and "omen" or "guardian"
	end
	return nil
end

-- the level the monster bar shows: the one the item level uses (loot.lua ChaosLoot.monsterLevel)
local function levelOf(creature)
	if not (ChaosLoot and ChaosLoot.monsterLevel) then
		return nil
	end
	local ok, level = pcall(ChaosLoot.monsterLevel, creature)
	return ok and tonumber(level) and math.floor(level) or nil
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
		role = roleOf(creature),
		level = levelOf(creature),
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
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "A legendary %s appears!", monster:getName()))
		end
	end
end

-- other scripts (infinitytower_run.lua) force a tier on a monster they created
function ChaosApplyTier(monster, tier)
	if ChaosTiers[tier] and tier ~= "boss" and eligible(monster) and not state[monster:getId()] then
		applyTier(monster, tier, 0)
		return true
	end
	return false
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

-- shown names (Chaos.createMonsterNamed: rift monsters, their ambush copies): renamed before the placement and before
-- every other onSpawn callback, so the first creature packet and "A legendary ... appears!" carry the name
local nameCb = EventCallback
nameCb.onSpawn = function(self, position, startup, artificial)
	local name = Chaos.spawnName
	if name then
		Chaos.spawnName = nil -- one monster per call; a creature made inside another callback keeps its own name
		self:rename(name, Chaos.nameDescriptionOf and Chaos.nameDescriptionOf(name) or name:lower())
	end
	return true
end
nameCb:register(-100)

-- natural roll on spawn. The engine runs onSpawn before the placement and gives a monster its id at the placement, so
-- the roll is decided here and applied at the monster's first think (a think event per tier that removes itself), where
-- the monster has its id: tier state, the modifier tick and the monster bar are keyed by that id. A map respawn thinks
-- right after it is placed; a startup spawn once a player comes near.
local rollEvent = {}
for _, tier in ipairs({"magic", "rare", "legendary", "boss"}) do
	local name = "ChaosTierRoll" .. tier:sub(1, 1):upper() .. tier:sub(2)
	rollEvent[tier] = name
	local ev = CreatureEvent(name)
	function ev.onThink(creature, interval)
		creature:unregisterEvent(name)
		-- a tier set in between (ChaosApplyTier: rift, invasion, tower) wins over the natural roll
		if creature:isMonster() and creature:getId() ~= 0 and not state[creature:getId()]
				and (tier == "boss" or eligible(creature)) then
			applyTier(creature, tier, 0)
		end
		return true
	end
	ev:register()
end

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	if pendingTier then
		-- an ambush copy: no roll of its own; the ambush applies its tier once it is placed
		pendingTier = nil
		return true
	end
	if isDisplaySpot(position) then
		return true
	end
	if eligible(self, position) then
		local roll = math.random(10000)
		local eventMult = ChaosTierSpawnMult(position or self:getPosition())
		-- the store's World Hunt raises magic and rare (not legendary), on top of the capped event multiplier
		local hunt = ChaosShopServices and ChaosShopServices.buffMult and ChaosShopServices.buffMult("hunt") or 1
		for _, tier in ipairs({"legendary", "rare", "magic"}) do
			if roll <= cfg.spawnChance[tier] * eventMult * (tier == "legendary" and 1 or hunt) then
				self:registerEvent(rollEvent[tier])
				return true
			end
		end
	elseif cfg.bossMods and not self:getMaster() and not isSkipped(typeNameOf(self)) and isBoss(self) then
		self:registerEvent(rollEvent.boss)
	end
	return true
end
spawnCb:register()

-- applyTier registers the death event for tiered monsters; every eligible one gets it here as well (a second
-- registration is a no-op), so that killing a normal monster can also bring an ambush. No tier state is read here:
-- the monster has no id yet.
local normalDeath = EventCallback
normalDeath.onSpawn = function(self, position, startup, artificial)
	if eligible(self, position) then
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
	-- the loot callback runs after this event: keep tier and modifiers for a few seconds (ChaosTierDead[id])
	ChaosTierDead = ChaosTierDead or {}
	ChaosTierDead[id] = {tier = ChaosTierOf(creature), mods = s and s.mods or {}}
	ChaosTierDead[id].depth = s and s.depth or 0 -- > 0: an ambush copy (achievements.lua counts ambushes survived)
	addEvent(function(cid) ChaosTierDead[cid] = nil end, 10000, id)
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
	local ambushMult = ChaosEvents and ChaosEvents.bonus("ambush") or 1
	-- pack combat (pace.lua): kills come faster, so the per-kill chance is x the monster's loot factor
	local paced = ChaosPace and ChaosPace.isPaced and ChaosPace.isPaced(creature)
	if paced then
		ambushMult = ambushMult * ChaosPace.lootMultOf(creature)
	end
	if math.random(10000) > (cfg.ambush[tier] or 0) * ambushMult then
		return true
	end
	local newTier = pickWeighted(cfg.ambushTier)
	local pos = creature:getPosition()
	-- no ambush copy inside a running dungeon: every monster of the run stands there from the start (O179)
	if ChaosDungeons and ChaosDungeons.runAt and ChaosDungeons.runAt(pos) then
		return true
	end
	-- nor inside a running Vocation Trial chamber (O187: "the Marked Cutthroat keeps reviving")
	if ChaosTrials and ChaosTrials.runAt and ChaosTrials.runAt(pos) then
		return true
	end
	addEvent(function(typeName, shown, position, nt, d, look, wasPaced)
		if ChaosDungeons and ChaosDungeons.runAt and ChaosDungeons.runAt(position) then
			return -- the 600 ms delay: the position lies in a dungeon that opened meanwhile
		end
		if ChaosTrials and ChaosTrials.runAt and ChaosTrials.runAt(position) then
			return
		end
		pendingTier = nt
		local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
		local copy = create(typeName, position, true, false, shown) -- a rift name carries over
		pendingTier = nil
		if copy and eligible(copy) then
			applyTier(copy, nt, d)
		end
		-- the copy of a paced monster is paced as well (at its first think)
		if copy and wasPaced and ChaosPace and ChaosPace.mark then
			ChaosPace.mark(copy)
		end
		-- the copy wears what the original wore (a rift look), with its own tier's shader
		if copy and look and copy:getOutfit().lookType ~= look.lookType then
			look.lookShader = copy:getOutfit().lookShader
			copy:setOutfit(look)
		end
	end, 600, typeNameOf(creature), creature:getName(), pos, newTier, depth + 1, creature:getOutfit(), paced or false)
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

-- the damage multiplier of a tiered monster's hits (tier x modifiers); nil for a monster without a tier
local function tierHitMult(attacker)
	local s = state[attacker:getId()]
	if not s then
		return nil
	end
	local mult = ChaosTiers[s.tier].damage
	for _, key in ipairs(s.mods or {}) do
		local d = ChaosMods[key].damage
		if type(d) == "function" then
			d = d(attacker)
		end
		mult = mult * (d or 1.0)
	end
	return mult, s
end

-- the modifiers' on-hit effects of a hit that landed on a player
local function tierOnHit(s, attacker, creature, total)
	for _, key in ipairs(s.mods or {}) do
		local mod = ChaosMods[key]
		if mod.onHit then
			mod.onHit(attacker, creature, total)
		end
	end
end

-- damage dealt TO players by a tiered monster (tier and modifier multipliers, on-hit effects). A hit a mana shield took
-- was scaled by the mana event already (manashield.lua): the rest is left as it is.
local hit = CreatureEvent("ChaosTierHit")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if attacker and attacker:isMonster() then
		local mult, s = tierHitMult(attacker)
		if mult then
			if not (ChaosManaShield and ChaosManaShield.scaled(creature, attacker, "tiers")) then
				primaryDamage = math.floor(primaryDamage * mult)
				secondaryDamage = math.floor(secondaryDamage * mult)
			end
			if creature:isPlayer() then
				tierOnHit(s, attacker, creature, math.abs(primaryDamage) + math.abs(secondaryDamage))
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

-- the mana shield part of the hit (manashield.lua): the same multiplier, the on-hit effects when the mana took it all
if not ChaosManaShield or not ChaosManaShield.provide then
	dofile("data/scripts/chaos/manashield_core.lua")
end
ChaosManaShield.provide("tiers", {
	hit = function(player, attacker, amount)
		local mult = attacker:isMonster() and tierHitMult(attacker)
		return mult and math.floor(amount * mult) or nil
	end,
	absorbed = function(player, attacker, amount)
		local _, s = tierHitMult(attacker)
		if s then
			tierOnHit(s, attacker, player, amount)
		end
	end
})

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
	local pp, cp = player:getPosition(), creature:getPosition()
	if pp.z ~= cp.z or pp:getDistance(cp) > 15 or not player:canSeeCreature(creature) then
		return
	end
	sendInfo(player, creature)
end
query:register()
