-- trials_effects.lua: what the special nodes of the Vocation Trials do in combat (TRIALS.md). The node stats are summed
-- into the passive bonus table by ChaosTrials.addBonuses (trials.lua, called by passivetree.lua), so this file reads
-- them from ChaosPassiveCache like the keystones do (passivetree_keystones.lua). Maths: trials_core.lua.
--
--   hits you deal      damage multiplier (dealX keys), echo / nova procs, leech
--   hits you take      take multiplier, evade, reflect, mana shield, last stand; inside a Trial the run's own scaling comes
--                      first (ChaosTrials.hooks.preHit) and its lethal-hit catch last (ChaosTrials.hooks.catch)
--   kills              kill heal / mana, kill stacks
--   healing            healOut / healIn
--   spell events       spellCost / spellCd through ChaosSpellEvents (engine patch 0008; nothing happens without it)
-- Extra hits (echo, nova, reflect) are dealt from an addEvent with the keystones' guard raised, so the passive tree's
-- bonuses and these nodes are not applied a second time; they use ORIGIN_SPELL like the keystones' extra hits.
-- Not run on a server by the tests; the pure parts are in trials_core.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosTrialsCore then
	dofile("data/scripts/chaos/trials_core.lua")
end
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end

ChaosTrials = ChaosTrials or {}
local T = ChaosTrials
local M = ChaosTrialsCore
T.hooks = T.hooks or {}
T.depth = T.depth or 0
T.nodeState = T.nodeState or {} -- per player id: kill stacks, last stand time (T.state is trials.lua's client state)

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function stateOf(id)
	local s = T.nodeState[id]
	if not s then
		s = {}
		T.nodeState[id] = s
	end
	return s
end

local TYPE_NAME = {}
local function typeNames()
	if next(TYPE_NAME) == nil then
		TYPE_NAME[COMBAT_PHYSICALDAMAGE], TYPE_NAME[COMBAT_FIREDAMAGE], TYPE_NAME[COMBAT_ICEDAMAGE] = "physical", "fire", "ice"
		TYPE_NAME[COMBAT_ENERGYDAMAGE], TYPE_NAME[COMBAT_EARTHDAMAGE], TYPE_NAME[COMBAT_DEATHDAMAGE] = "energy", "earth", "death"
		TYPE_NAME[COMBAT_HOLYDAMAGE] = "holy"
	end
	return TYPE_NAME
end

local function originKind(origin)
	if origin == ORIGIN_MELEE then
		return "melee"
	elseif origin == ORIGIN_RANGED then
		return "ranged"
	elseif origin == ORIGIN_SPELL or (ORIGIN_WAND and origin == ORIGIN_WAND) then
		return "spell"
	elseif origin == ORIGIN_CONDITION then
		return "dot"
	end
	return "other"
end

local function guarded(fn, ...)
	T.depth = T.depth + 1
	local K = ChaosKeystones
	if K then
		K.depth = (K.depth or 0) + 1
	end
	local ok, err = pcall(fn, ...)
	T.depth = T.depth - 1
	if K then
		K.depth = K.depth - 1
	end
	if not ok then
		print("[ChaosTrials] " .. tostring(err))
	end
end

local function validTarget(attacker, c)
	if not c or c:getId() == attacker:getId() or c:getHealth() <= 0 then
		return false
	end
	if c:isPlayer() then
		return ChaosSpell ~= nil and ChaosSpell.canAttack(attacker, c)
	end
	if ChaosSpell then
		return ChaosSpell.isEnemy(attacker, c)
	end
	return c:isMonster() and not c:getMaster()
end

local function procDamage(attacker, target, ctype, amount, effect)
	amount = math.floor(amount)
	if amount > 0 and target and target:getHealth() > 0 then
		guarded(doTargetCombat, attacker, target, ctype, -amount, -amount, effect or CONST_ME_NONE, ORIGIN_SPELL)
	end
end

local function procType(ctype)
	if ctype == nil or ctype == COMBAT_NONE or ctype == COMBAT_HEALING then
		return COMBAT_PHYSICALDAMAGE
	end
	return ctype
end

local function echo(pid, tid, ctype, amount)
	local p, t = Player(pid), Creature(tid)
	if p and t and validTarget(p, t) then
		procDamage(p, t, ctype, amount, CONST_ME_MAGIC_BLUE)
	end
end

local function nova(pid, tid, pos, ctype, amount, radius)
	local p = Player(pid)
	if not p then
		return
	end
	local center = Position(pos.x, pos.y, pos.z)
	center:sendMagicEffect(CONST_ME_HITAREA)
	for _, c in ipairs(Game.getSpectators(center, false, false, radius, radius, radius, radius) or {}) do
		if c:getId() ~= tid and validTarget(p, c) then
			procDamage(p, c, ctype, amount, CONST_ME_NONE)
		end
	end
end

local function reflectBack(pid, aid, amount)
	local p, a = Player(pid), Creature(aid)
	if p and a and validTarget(p, a) then
		procDamage(p, a, COMBAT_PHYSICALDAMAGE, amount, CONST_ME_EXPLOSIONHIT)
	end
end

local function leechHeal(pid, amount)
	local p = Player(pid)
	if p and p:getHealth() > 0 then
		Chaos.heal(p, amount)
	end
end

-- the player behind a hit: a player, or the player who owns the summon that hit
local function ownerOf(attacker)
	if attacker:isPlayer() then
		return attacker, false
	end
	local master = attacker:getMaster()
	if master and master:isPlayer() then
		return master, true
	end
	return nil
end

local function ratio(c)
	local m = c:getMaxHealth()
	return m > 0 and c:getHealth() / m or 1
end

local function bonusesOf(player)
	local b = ChaosPassiveCache[player:getId()]
	return b and (b.trialNodes or 0) > 0 and b or nil
end

-- ---------------------------------------------------------------- the player is hit
local function defend(player, b, attacker, pd, pt, sd, st, origin)
	local kind = originKind(origin)
	local total = math.abs(pd) + math.abs(sd)
	if kind == "melee" or kind == "ranged" then
		if M.roll(M.evadeChance(b, kind)) then
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
			return 0, 0
		end
	end
	local m = M.takeMultiplier(b, {origin = kind, ctype = TYPE_NAME[pt], hpRatio = ratio(player)})
	if m ~= 1 then
		pd, sd = M.scaleDamage(pd, m), M.scaleDamage(sd, m)
		total = math.abs(pd) + math.abs(sd)
	end
	if (b.manaShield or 0) > 0 and total > 0 then
		local rest, paid = M.shieldSplit(b, total, player:getMana())
		if paid > 0 then
			local keep = rest / total
			pd, sd = M.scaleDamage(pd, keep), M.scaleDamage(sd, keep)
			player:addMana(-paid)
			player:getPosition():sendMagicEffect(CONST_ME_MAGIC_BLUE)
			total = math.abs(pd) + math.abs(sd)
		end
	end
	if (b.reflect or 0) > 0 and attacker then
		local back = M.reflectAmount(b, kind, total)
		if back > 0 then
			addEvent(reflectBack, 0, player:getId(), attacker:getId(), back)
		end
	end
	if (b.lastStandCd or 0) > 0 and total > 0 then
		-- health + energy shield (engine patch 0015: the shield takes its part after this event)
		local cut, hit = M.lastStand(b, stateOf(player:getId()), now() / 1000,
			player:getHealth() + (player.getEnergyShield and player:getEnergyShield() or 0), total)
		if hit then
			local keep = total > 0 and cut / total or 0
			pd, sd = M.scaleDamage(pd, keep), M.scaleDamage(sd, keep)
			player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
			player:sendTextMessage(MESSAGE_STATUS_CONSOLE_ORANGE or MESSAGE_INFO_DESCR,
				Chaos.t(player, "Your last stand holds: the lethal blow leaves you standing."))
		end
	end
	return pd, sd
end

-- ---------------------------------------------------------------- the player (or a summon) hits
local function attack(owner, isMinion, b, creature, pd, pt, sd, st, origin)
	local kind = isMinion and "minion" or originKind(origin)
	local s = stateOf(owner:getId())
	local names = typeNames()
	local ctx = {origin = kind, ctype = names[pt], hpRatio = ratio(owner), targetRatio = ratio(creature),
		stacks = M.stackCount(s, b, now())}
	local m1 = M.dealMultiplier(b, ctx)
	ctx.ctype = names[st]
	local m2 = (sd ~= 0) and M.dealMultiplier(b, ctx) or 1
	if m1 ~= 1 then
		pd = M.scaleDamage(pd, m1)
	end
	if m2 ~= 1 then
		sd = M.scaleDamage(sd, m2)
	end
	local amount = math.abs(pd) + math.abs(sd)
	if amount <= 0 or kind == "dot" or kind == "other" then
		return pd, sd
	end
	local pid, cid = owner:getId(), creature:getId()
	local ctype = procType(pt)
	if (b.echoChance or 0) > 0 and not isMinion and M.roll(b.echoChance) then
		addEvent(echo, 350, pid, cid, ctype, amount * (b.echoPct or 50) / 100)
	end
	if (b.novaChance or 0) > 0 and not isMinion and M.roll(b.novaChance) then
		local p = creature:getPosition()
		addEvent(nova, 200, pid, cid, {x = p.x, y = p.y, z = p.z}, ctype, amount * (b.novaPct or 40) / 100, b.novaRadius or 2)
	end
	local leech = (b.leechAll or 0) + (kind == "melee" and (b.leechMelee or 0) or 0) + (kind == "spell" and (b.leechSpell or 0) or 0)
	if leech > 0 then
		local back = math.floor(amount * math.min(leech, 20) / 100)
		if back > 0 then
			addEvent(leechHeal, 0, pid, back)
		end
	end
	return pd, sd
end

local event = CreatureEvent("ChaosTrialNodes")
function event.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	if T.depth > 0 or (ChaosKeystones and (ChaosKeystones.depth or 0) > 0) then
		return pd, pt, sd, st
	end
	typeNames()
	-- healing: healOut of the caster, healIn of the one healed
	if pt == COMBAT_HEALING then
		if attacker and attacker:isPlayer() then
			local b = bonusesOf(attacker)
			if b and (b.healOut or 0) ~= 0 then
				local f = math.max(0.25, 1 + b.healOut / 100)
				pd, sd = M.scaleDamage(pd, f), (st == COMBAT_HEALING) and M.scaleDamage(sd, f) or sd
			end
		end
		if creature:isPlayer() then
			local b = bonusesOf(creature)
			if b and (b.healIn or 0) ~= 0 then
				local f = math.max(0.25, 1 + b.healIn / 100)
				pd, sd = M.scaleDamage(pd, f), (st == COMBAT_HEALING) and M.scaleDamage(sd, f) or sd
			end
		end
		return pd, pt, sd, st
	end
	if creature:isPlayer() then
		-- the Trial's own scaling first (its monsters hit for a share of the maximum health)
		local hooks = T.hooks
		if hooks.preHit and attacker then
			pd, sd = hooks.preHit(creature, attacker, pd, pt, sd, st, origin)
		end
		local b = bonusesOf(creature)
		if b and (not attacker or attacker:getId() ~= creature:getId()) then
			pd, sd = defend(creature, b, attacker, pd, pt, sd, st, origin)
		end
		-- the lethal-hit catch of a Trial comes last
		if hooks.catch then
			pd, sd = hooks.catch(creature, attacker, pd, pt, sd, st, origin)
		end
	end
	if attacker and attacker:getId() ~= creature:getId() then
		local owner, isMinion = ownerOf(attacker)
		local b = owner and bonusesOf(owner)
		if b and not (creature:isPlayer() and owner:getId() == creature:getId()) then
			pd, sd = attack(owner, isMinion, b, creature, pd, pt, sd, st, origin)
		end
	end
	return pd, pt, sd, st
end
event:register()

-- the event sits on whatever a player or a player's summon attacks, and on every player (hits taken, heals received)
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target then
		if creature:isPlayer() then
			if bonusesOf(creature) then
				target:registerEvent("ChaosTrialNodes")
			end
		else
			local master = creature:getMaster()
			if master and master:isPlayer() and bonusesOf(master) then
				target:registerEvent("ChaosTrialNodes")
			end
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(1)

-- ---------------------------------------------------------------- kills
local kill = CreatureEvent("ChaosTrialKill")
function kill.onKill(player, target)
	local b = bonusesOf(player)
	if not b or not target or not target:isMonster() then
		return true
	end
	if target:getMaster() then
		return true
	end
	M.addKill(stateOf(player:getId()), b, now())
	if (b.killHeal or 0) > 0 then
		Chaos.heal(player, math.floor(player:getMaxHealth() * b.killHeal / 100))
	end
	if (b.killMana or 0) > 0 then
		player:addMana(math.floor(player:getMaxMana() * b.killMana / 100))
	end
	return true
end
kill:register()

local login = CreatureEvent("ChaosTrialNodesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTrialKill")
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p then
			p:registerEvent("ChaosTrialNodes")
		end
	end, 0)
	return true
end
login:register()

local logout = CreatureEvent("ChaosTrialNodesLogout")
function logout.onLogout(player)
	T.nodeState[player:getId()] = nil
	return true
end
logout:register()

-- ---------------------------------------------------------------- spell events (engine patch 0008)
if ChaosSpellEvents then
	local E = ChaosSpellEvents
	local function pct(player, key)
		local b = ChaosPassiveCache[player:getId()]
		return b and b.trialNodes and (b[key] or 0) or 0
	end
	E.set("cost", "chaostrials", function(player, name, id, group, aggressive, mana, health)
		local p = pct(player, "spellCost")
		if p ~= 0 and mana > 0 then
			mana = math.max(0, mana + math.floor(mana * math.max(-60, p) / 100))
		end
		return mana, health
	end)
	E.set("cooldown", "chaostrials", function(player, name, id, group, aggressive, cooldownType, ms)
		local p = pct(player, "spellCd")
		if p ~= 0 and ms > 0 then
			ms = math.max(math.min(ms, 1000), ms + math.floor(ms * math.max(-50, p) / 100))
		end
		return ms
	end)
end
