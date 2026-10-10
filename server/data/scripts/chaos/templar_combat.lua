-- templar_combat.lua: the combat glue of the Templar line (Templar, Inquisitor, Sentinel; docs/CLASSES.md).
-- Ids, numbers and the rules: templar_aura_core.lua (ChaosTemplar, ChaosTemplar.cfg).
--
--   * Defence aura (passive, all three): every second each Templar-line player covers itself and its party members
--     within range; covered players take less damage, and the Sentinel's aura also regenerates health. The strongest
--     aura counts, they do not stack.
--   * Radiant Strikes (passive, all three): a melee weapon hit is followed by a holy strike for a share of it.
--   * Judgement (Inquisitor spell): a timer condition on the target; holy damage it takes, from anyone, is raised.
--   * Zealotry (Inquisitor spell): a timer condition on the Inquisitor; melee weapon hits add stacks, each stack raises
--     all its damage. The stacks fall off a few seconds after the last hit.
--   * Aegis of Faith (Sentinel spell): a timer condition on the Sentinel; damage taken is cut for its duration.
-- Scripted strikes (the holy strike) are dealt with origin ORIGIN_SPELL inside a guard flag, so they never trigger the
-- weapon-hit rules again (nor Zealotry a second time: the strike is a share of a hit Zealotry already raised). Not
-- ORIGIN_NONE: the engine runs no onHealthChange event for it, so Judgement and the curse never saw the strike.

if not ChaosTemplar then
	dofile("data/scripts/chaos/templar_aura_core.lua")
end
-- ChaosSpell.canAttack (the PvP rules of scripted strikes) lives with the spells; load it into this state too
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end
local T = ChaosTemplar
local function cfg()
	return T.cfg
end
local SUB = T.cfg.ids.subId

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
	scripted = true
	local ok, err = pcall(doTargetCombat, attacker, target, COMBAT_HOLYDAMAGE, -amount, -amount,
		CONST_ME_HOLYDAMAGE, ORIGIN_SPELL)
	scripted = false
	if not ok then
		print("[ChaosTemplar] " .. tostring(err))
	end
end

-- damage `creature` takes from a Templar-line attacker: Zealotry, Radiant Strikes
local function onOffence(creature, player, primaryDamage, secondaryDamage, origin)
	local voc = player:getVocation():getId()
	if not T.isTemplarLine(voc) then
		return primaryDamage, secondaryDamage
	end
	local amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if amount == 0 or scripted then
		return primaryDamage, secondaryDamage
	end
	local now = T.now()
	local isMeleeHit = origin == ORIGIN_MELEE and not scripted
	if T.isInquisitor(voc) then
		local buff = hasTimer(player, SUB.zealotry)
		if buff and isMeleeHit then
			T.zealHit(player:getId(), now)
		end
		local mult = T.zealMultiplier(player:getId(), now, buff)
		if mult ~= 1 then
			primaryDamage = T.scale(primaryDamage, mult)
			secondaryDamage = T.scale(secondaryDamage, mult)
			amount = math.abs(primaryDamage) + math.abs(secondaryDamage)
		end
	end
	if isMeleeHit then
		local value = T.radiantDamage(voc, amount, creature:isPlayer())
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
			local f = T.damageTakenFactor(T.activeAura(creature:getId(), T.now()), aegis)
			if f ~= 1 then
				p, s = T.scale(p, f), T.scale(s, f)
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
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and T.isTemplarLine(creature:getVocation():getId()) then
		target:registerEvent("ChaosTemplarCombat")
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
