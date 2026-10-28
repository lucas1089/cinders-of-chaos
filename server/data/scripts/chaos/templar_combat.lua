-- templar_combat.lua: the combat glue of the Templar line (Templar, Inquisitor, Sentinel; docs/CLASSES.md).
-- Ids, numbers and the rules: templar_aura_core.lua (ChaosTemplar, ChaosTemplar.cfg).
--
--   * Defence aura (passive, all three): every second each Templar-line player covers itself and its party members
--     within range; covered players take less damage, and the Sentinel's aura also regenerates health. The strongest
--     aura counts, they do not stack.
--   * Radiant Strikes (passive, all three): a melee weapon hit is followed by a holy strike for a share of it.
--   * Judgement (Inquisitor spell): a timer condition on the target; holy damage it takes, from anyone, is raised.
--   * Aegis of Faith (Sentinel spell): a timer condition on the Sentinel; damage taken is cut for its duration.
--   * Penitent's Wrath (the line's keystone in the main tree, node 376): a melee / ranged hit taken is answered with a
--     holy strike on the attacker (40% of what was taken + 4 x magic level, one every 0.5 s); the own aura's reduction
--     is halved (its party members' too).
-- Scripted strikes (the holy strike) are dealt with origin ORIGIN_SPELL inside a guard flag, so they never trigger the
-- weapon-hit rules again. Not ORIGIN_NONE: the engine runs no onHealthChange event for it, so Judgement and the curse never saw the strike.

if not ChaosTemplar then
	dofile("data/scripts/chaos/templar_aura_core.lua")
end
-- ChaosSpell.canAttack (the PvP rules of scripted strikes) lives with the spells; load it into this state too
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end
local T = ChaosTemplar
if not ChaosClassTree then
	dofile("data/scripts/chaos/class_tree.lua") -- the class nodes of the passive tree
end
local CT = ChaosClassTree
if not ChaosKeystoneLabels then
	dofile("data/scripts/chaos/keystone_labels.lua") -- the combat log's keystone rows (optional)
end
local KL = ChaosKeystoneLabels
local function cfg()
	return T.cfg
end
local SUB = T.cfg.ids.subId
if not ChaosQuestBuffs then
	dofile("data/scripts/chaos/quest_buffs_core.lua") -- Mantle of Dawn (level 800 line spell quest buff)
end
local QB = ChaosQuestBuffs

local scripted = false -- guard: true while this file deals its own strikes

local function hasTimer(creature, subId)
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
end

local function fx(pos, name, fallback)
	if Fx then
		Position(pos):sendMagicEffect(Fx(name, fallback))
	else
		Position(pos):sendMagicEffect(fallback)
	end
end

-- ------------------------------------------------------------------------------------------------ the aura check
local lastFx = {} -- [templar id] = ms of the last aura effect

local function partyKey(player)
	local party = player:getParty()
	if not party then
		return nil
	end
	local leader = party:getLeader()
	return leader and leader:getId() or nil
end

local function auraTick()
	local now = T.now()
	local templars, players, byId = {}, {}, {}
	for _, p in ipairs(Game.getPlayers()) do
		local entry = {id = p:getId(), pos = p:getPosition(), party = partyKey(p), dead = p:getHealth() <= 0,
			voc = p:getVocation():getId()}
		players[#players + 1] = entry
		byId[entry.id] = p
		if T.isTemplarLine(entry.voc) and not entry.dead then
			-- the passive tree: Sanctuary (more regeneration), Bastion (a stronger, wider aura; Aegis covers the party)
			local regen = CT.value(p, "ctSanctuary", "regen")
			local bastion = CT.has(p, "ksBastion") and CT.fx.ksBastion or nil
			-- Penitent's Wrath (the line keystone): the aura's reduction is halved
			local scale = CT.value(p, "ksPenitentWrath", "auraScale", 1)
			if regen > 0 or bastion or scale ~= 1 then
				entry.bonus = {regenPct = T.auraOf(entry.voc).regenPct > 0 and regen or 0,
					reduction = bastion and bastion.reduction or 0, radius = bastion and bastion.radius or 0,
					bastion = bastion ~= nil, scale = scale}
			end
			templars[#templars + 1] = entry
		end
	end
	if #templars == 0 then
		T.applyAuras({}, now)
		return
	end
	local fresh = T.collectAuras(templars, players, now)
	T.applyAuras(fresh, now)
	-- the Sentinel's regeneration and the aura's look. A regeneration condition, refreshed every think, not a heal:
	-- a heal (doTargetCombat) printed "You heal X for 12 hitpoints" to the Sentinel and "healed by" to every covered
	-- member once a second (tested in game); the condition's ticks are silent
	for id, aura in pairs(fresh) do
		local p = byId[id]
		if p and Player(aura.source) then
			local amount = T.regenAmount(p:getHealth(), p:getMaxHealth(), aura)
			if amount > 0 then
				local c = Condition(CONDITION_REGENERATION, CONDITIONID_COMBAT)
				c:setParameter(CONDITION_PARAM_SUBID, SUB.auraRegen)
				c:setParameter(CONDITION_PARAM_TICKS, cfg().aura.holdMs)
				c:setParameter(CONDITION_PARAM_HEALTHGAIN, amount)
				c:setParameter(CONDITION_PARAM_HEALTHTICKS, cfg().aura.thinkMs)
				p:addCondition(c)
			end
		end
	end
	for _, t in ipairs(templars) do
		if now - (lastFx[t.id] or 0) >= cfg().aura.fxMs then
			lastFx[t.id] = now
			fx(t.pos, "holy_spiral", CONST_ME_YELLOW_RINGS)
		end
	end
end

local think = GlobalEvent("ChaosTemplarAura")
function think.onThink(interval)
	local ok, err = pcall(auraTick)
	if not ok then
		print("[ChaosTemplar] aura: " .. tostring(err))
	end
	return true
end
think:interval(T.cfg.aura.thinkMs)
think:register()

-- ------------------------------------------------------------------------------------------------ offence
local function radiantStrike(attackerId, targetId, amount)
	local attacker, target = Player(attackerId), Creature(targetId)
	if not attacker or not target or target:getHealth() <= 0 then
		return
	end
	if target:isPlayer() and ChaosSpell and not ChaosSpell.canAttack(attacker, target) then
		return
	end
	-- Divine Verdict (the passive tree): the strike may judge its target (before it lands, so it counts already)
	if CT.has(attacker, "ksDivineVerdict") and math.random() < CT.fx.ksDivineVerdict.chance then
		local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
		c:setParameter(CONDITION_PARAM_SUBID, SUB.judgement)
		c:setParameter(CONDITION_PARAM_TICKS, cfg().judgement.durationMs)
		target:addCondition(c)
		KL.note(attacker, "ksDivineVerdict", 0)
		fx(target:getPosition(), "holy_spiral", CONST_ME_HOLYAREA)
	end
	scripted = true
	-- a weapon hit's strike, not a spell: the class spell factor stays off (spell_factor_core.lua)
	local SF = ChaosSpellFactor
	if SF then
		SF.depth = (SF.depth or 0) + 1
	end
	local ok, err = pcall(doTargetCombat, attacker, target, COMBAT_HOLYDAMAGE, -amount, -amount,
		CONST_ME_HOLYDAMAGE, ORIGIN_SPELL)
	if SF then
		SF.depth = SF.depth - 1
	end
	scripted = false
	if not ok then
		print("[ChaosTemplar] " .. tostring(err))
	end
end

-- Penitent's Wrath (the line keystone): the holy answer to a hit the Templar took. Dealt like the keystone procs
-- (passivetree_keystones.lua): ChaosKeystones.depth up, so no passive bonus or keystone runs on it, and the own guard.
local function penitentStrike(playerId, attackerId, amount)
	local player, target = Player(playerId), Creature(attackerId)
	if not player or not target or target:getHealth() <= 0 or player:getHealth() <= 0 then
		return
	end
	if ChaosSpell and not ChaosSpell.canAttack(player, target) then
		return
	end
	player:getPosition():sendDistanceEffect(target:getPosition(), CONST_ANI_HOLY)
	local K = ChaosKeystones
	if K then
		K.depth = (K.depth or 0) + 1
	end
	scripted = true
	local ok, err = KL.run("ksPenitentWrath", pcall, doTargetCombat, player, target, COMBAT_HOLYDAMAGE, -amount, -amount,
		CONST_ME_HOLYDAMAGE, ORIGIN_SPELL)
	scripted = false
	if K then
		K.depth = K.depth - 1
	end
	if not ok then
		print("[ChaosTemplar] " .. tostring(err))
	end
end

-- damage `creature` takes from a Templar-line attacker: Radiant Strikes
local function onOffence(creature, player, primaryDamage, secondaryDamage, origin)
	local voc = player:getVocation():getId()
	if not T.isTemplarLine(voc) then
		return primaryDamage, secondaryDamage
	end
	local amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if amount == 0 or scripted then
		return primaryDamage, secondaryDamage
	end
	local isMeleeHit = origin == ORIGIN_MELEE and not scripted
	if isMeleeHit then
		local value = T.radiantDamage(voc, amount, creature:isPlayer(), CT.value(player, "ctBurningZeal", "share"),
			QB.holyFactor(hasTimer(player, QB.cfg().subId.mantle)))
		if value > 0 then
			addEvent(radiantStrike, cfg().radiant.delayMs, player:getId(), creature:getId(), value)
		end
	end
	return primaryDamage, secondaryDamage
end

-- ------------------------------------------------------------------------------------------------ the event
local event = CreatureEvent("ChaosTemplarCombat")
function event.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local ok, a, b = pcall(function()
		local p, s = primaryDamage, secondaryDamage
		local attackerPlayer = attacker and attacker:getPlayer()
		if attackerPlayer and attackerPlayer ~= creature then
			p, s = onOffence(creature, attackerPlayer, p, s, origin)
		end
		-- Judgement: holy damage on a judged creature, from any source
		if hasTimer(creature, SUB.judgement) then
			p = T.scale(p, T.judgementFactor(primaryType == COMBAT_HOLYDAMAGE, true))
			s = T.scale(s, T.judgementFactor(secondaryType == COMBAT_HOLYDAMAGE, true))
		end
		-- the aura and Aegis of Faith on the player taking the hit (conditions included: poison under the aura hurts less)
		if creature:isPlayer() then
			local voc = creature:getVocation():getId()
			local aegis = T.isSentinel(voc) and hasTimer(creature, SUB.aegis)
			local aura = T.activeAura(creature:getId(), T.now())
			local share = 1
			-- Bastion (the passive tree): the Sentinel's Aegis of Faith also covers the members under its aura, at half
			if not aegis and aura and aura.bastion and aura.source ~= creature:getId() then
				local source = Player(aura.source)
				if source and hasTimer(source, SUB.aegis) then
					aegis, share = true, CT.fx.ksBastion.partyShare
				end
			end
			local f = T.damageTakenFactor(aura, aegis, share, QB.takenFactor(hasTimer(creature, QB.cfg().subId.mantle)))
			if f ~= 1 then
				p, s = T.scale(p, f), T.scale(s, f)
			end
			-- Penitent's Wrath: a melee / ranged hit taken from a creature is answered (what is left of it)
			if attacker and attacker ~= creature and not scripted and (origin == ORIGIN_MELEE or origin == ORIGIN_RANGED)
					and T.isTemplarLine(voc) and CT.has(creature, "ksPenitentWrath") then
				local fx = CT.fx.ksPenitentWrath
				local value = T.penitentDamage(math.abs(p) + math.abs(s), creature:getMagicLevel(), fx)
				if value > 0 and T.penitentReady(creature:getId(), T.now(), fx) then
					addEvent(penitentStrike, 0, creature:getId(), attacker:getId(), value)
				end
			end
		end
		return p, s
	end)
	if not ok then
		print("[ChaosTemplar] " .. tostring(a))
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return a, primaryType, b, secondaryType
end
event:register()

-- whatever a Templar-line player attacks gets the event (its weapon hits are seen on the victim)
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
	if creature and target and creature:isPlayer() and not eventKnown(target, "ChaosTemplarCombat")
			and T.isTemplarLine(creature:getVocation():getId()) then
		registerOnce(target, "ChaosTemplarCombat")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(5)

local login = CreatureEvent("ChaosTemplarLogin")
function login.onLogin(player)
	-- every player: a party member of a Templar takes less damage under the aura
	player:registerEvent("ChaosTemplarCombat")
	player:registerEvent("ChaosTemplarLogout")
	return true
end
login:register()

local logout = CreatureEvent("ChaosTemplarLogout")
function logout.onLogout(player)
	T.clear(player:getId())
	lastFx[player:getId()] = nil
	return true
end
logout:register()
