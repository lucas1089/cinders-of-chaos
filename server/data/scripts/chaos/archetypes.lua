-- archetypes.lua: the engine glue of the build archetype keystones and uniques (ChaosArchetypes; docs/BUILDS.md,
-- server/README.md "Build archetypes"). Rules: archetypes_core.lua (pure, tested), numbers: archetypes_config.lua.
--
-- What it hooks:
--   * ChaosArchetypesHit (onHealthChange) on every monster (at spawn and when a player attacks it) and on every
--     player (login): the prices, Open Hand, Aether Edge, Cascade Edge, Stormstring, the marks for the spreads and the
--     shatter, ignites and sigils, the effigy casts, the leech, the reflect, the healing price, the relic's buff.
--   * ChaosArchetypesDeath (onDeath) on the same monsters: poison and burn spread, shatter, the sigil's jump.
--   * a listener of the passive tree (ChaosPassiveTree.listeners, after every save, reset and login): who holds what,
--     the Aether Edge health condition.
--   * a one second think (GlobalEvent) over the players holding a ticking archetype: Pyre Oath, effigies, sigils, the
--     Reliquary Warden, Hollow Vessel's health and early recharge; and a queue for the chain reactions, drained
--     chain.perTick at a time (archetypes_config.lua).
--   * the second round (2026-10-12): Snarewright's Creed (its price spares the snares' hits, which the spells' side marks
--     in a storage, snares_config.lua storage.hit), Covenant of Vigils (its price), the vigils' hit multipliers
--     (vigils.lua ChaosVigils.dealt / taken) and Hollow Vessel (its health condition, the energy shield modifier read
--     by data/lib/chaos_energy_shield.lua, the immunities, the early recharge, ChaosArchetypes.percentBase for the
--     rifts' percent-of-health hits).
--
--   * the third round (2026-10-20, Warrior and Ranger lines): Executioner's Verdict, Earthbreaker, Rampage (a kill
--     stack, the monster's death event), Last Stand (a hit taken is cut, the healing price), Longshot, Barbed Quiver (a
--     bleed condition), Opening Shot and Hobbling Shot (a slow condition and a mark per target).
--
-- Damage of the archetypes, and the guards:
--   * shares of a hit (Cascade, arcs, effigy and sigil pulses, the reflect) are dealt with ChaosKeystones.depth up, like
--     the keystone procs: no passive bonus a second time, no keystone, no archetype reacts to them;
--   * damage of its own (the Pyre aura, the relic, the shatter, Aether Edge) is dealt as a spell of the player with
--     `source` set: the tree bonuses and the class factor apply as to a spell, the archetype's own price does not, and
--     only the leech and the marks react to it (no cascade, no arcs, no effigy, no sigil from it);
--   * spreads are conditions with the player as owner (their ticks are the player's damage over time).
-- Targets: monsters that are not a player's summon; players only where ChaosSpell.canAttack allows (PvP rules).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ChaosArchetypesConfig = ChaosArchetypesConfig or dofile("data/scripts/chaos/archetypes_config.lua")
if not ChaosArchetypesCore then
	dofile("data/scripts/chaos/archetypes_core.lua")
end
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua") -- canAttack / isEnemy (PvP rules), Fx
end
if not ChaosSummonsCore then
	pcall(dofile, "data/scripts/chaos/summons_core.lua") -- bind: a summon starts as an ally of its owner
end
local function bindSummon(player, monster)
	if ChaosSummonsCore then
		return ChaosSummonsCore.bind(player, monster)
	end
	monster:setMaster(player)
	return monster
end
ChaosKeystones = ChaosKeystones or {}
ChaosKeystones.depth = ChaosKeystones.depth or 0
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.listeners = ChaosPassiveTree.listeners or {}
ChaosPassiveCache = ChaosPassiveCache or {}
ChaosItemModsCache = ChaosItemModsCache or {}

ChaosArchetypes = ChaosArchetypes or {}
local M = ChaosArchetypes
local A = ChaosArchetypesCore
local function cfg()
	return ChaosArchetypesConfig
end

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function fx(name, fallback)
	if Fx then
		local ok, v = pcall(Fx, name, fallback)
		if ok and v then
			return v
		end
	end
	return fallback
end

local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

local TYPE_NAME = {}
local NAME_TYPE = {}
for name, key in pairs({physical = "COMBAT_PHYSICALDAMAGE", fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE",
		energy = "COMBAT_ENERGYDAMAGE", earth = "COMBAT_EARTHDAMAGE", death = "COMBAT_DEATHDAMAGE",
		holy = "COMBAT_HOLYDAMAGE", drown = "COMBAT_DROWNDAMAGE", lifedrain = "COMBAT_LIFEDRAIN",
		manadrain = "COMBAT_MANADRAIN"}) do
	local v = _G[key]
	if v then
		TYPE_NAME[v] = name
		NAME_TYPE[name] = v
	end
end
local function typeName(t)
	return TYPE_NAME[t] or "other"
end

local function originName(origin)
	if origin == ORIGIN_MELEE then
		return "melee"
	elseif origin == ORIGIN_RANGED or (ORIGIN_WAND and origin == ORIGIN_WAND) then
		return "ranged"
	elseif origin == ORIGIN_SPELL then
		return "spell"
	elseif origin == ORIGIN_CONDITION then
		return "condition"
	end
	return "other"
end

-- ------------------------------------------------------------------------------------------------ who holds what
M.flags = {} -- player id -> {flag = true} (only players holding one)
M.uniques = {} -- player id -> {key = true} (equipped archetype uniques)

local function flagsOf(pid)
	return M.flags[pid]
end

local function hasUnique(pid, key)
	local u = M.uniques[pid]
	return u ~= nil and u[key] == true
end

local SLOTS = {}
for _, s in ipairs({"CONST_SLOT_HEAD", "CONST_SLOT_NECKLACE", "CONST_SLOT_ARMOR", "CONST_SLOT_RIGHT", "CONST_SLOT_LEFT",
		"CONST_SLOT_LEGS", "CONST_SLOT_FEET", "CONST_SLOT_RING", "CONST_SLOT_BADGE"}) do
	if _G[s] then
		SLOTS[#SLOTS + 1] = _G[s]
	end
end

local function refreshShieldLater(player)
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p and ChaosEnergyShield and ChaosEnergyShield.apply then
			pcall(ChaosEnergyShield.apply, p, ChaosItemModsCache[pid] or {})
		end
	end, 0)
end

function M.refreshUniques(player)
	local list, any = {}, false
	for _, slot in ipairs(SLOTS) do
		local item = player:getSlotItem(slot)
		local key = item and cfg().uniques[item:getId()]
		if key then
			local ok, mark = pcall(item.getCustomAttribute, item, "chaos_unique")
			if ok and mark and mark ~= 0 then
				list[key] = true
				any = true
			end
		end
	end
	local before = M.uniques[player:getId()]
	M.uniques[player:getId()] = any and list or nil
	-- the shield uniques change the energy shield's maximum and recharge
	local was = before and (before.stillheart or before.hollowglass)
	if was or list.stillheart or list.hollowglass then
		refreshShieldLater(player)
	end
end

-- the passive tree listener: after every save, reset and login
local function onTree(player, bonuses)
	local flags, any = A.flagsOf(bonuses)
	local pid = player:getId()
	M.flags[pid] = any and flags or nil
	local mask = A.mask(flags)
	if player:getStorageValue(cfg().storage) ~= mask then
		player:setStorageValue(cfg().storage, mask) -- for the spells' Lua state (Open Hand)
	end
	M.syncAether(player)
	M.syncHollow(player)
	if not flags.arReliquary then
		M.dismissRelic(pid)
	end
	local s = M.state[pid]
	if s and not flags.arEffigy then
		for _, e in ipairs(s.effigies) do
			M.removeEffigy(e)
		end
		s.effigies = {}
	end
	if s and not flags.arCinderSigil then
		s.sigil = nil
	end
end
ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners + 1] = onTree

-- ------------------------------------------------------------------------------------------------ targets and damage
local function validTarget(attacker, c)
	if not c or c:getHealth() <= 0 or (attacker and c:getId() == attacker:getId()) then
		return false
	end
	if c:isPlayer() then
		return attacker ~= nil and ChaosSpell ~= nil and ChaosSpell.canAttack(attacker, c)
	end
	if ChaosSpell and attacker then
		return ChaosSpell.isEnemy(attacker, c)
	end
	local master = c:getMaster()
	return c:isMonster() and not (master and master:isPlayer())
end

local function around(attacker, pos, radius, needSight)
	local list = {}
	local center = Position(pos.x, pos.y, pos.z)
	for _, c in ipairs(Game.getSpectators(center, false, false, radius, radius, radius, radius) or {}) do
		if validTarget(attacker, c) then
			local cp = c:getPosition()
			if not needSight or center:isSightClear(cp, true) then
				list[#list + 1] = {id = c:getId(), pos = copyPos(cp)}
			end
		end
	end
	return list
end

M.source = nil -- the archetype whose own damage is being dealt (see the top)

-- a share of a hit: the keystone guard up (nothing reacts to it)
local function dealProc(attacker, target, ctype, amount, effect)
	amount = math.floor(amount or 0)
	if amount <= 0 or not target or target:getHealth() <= 0 then
		return
	end
	ChaosKeystones.depth = ChaosKeystones.depth + 1
	local ok, err = pcall(doTargetCombat, attacker, target, ctype, -amount, -amount, effect or CONST_ME_NONE, ORIGIN_SPELL)
	ChaosKeystones.depth = ChaosKeystones.depth - 1
	if not ok then
		print("[ChaosArchetypes] " .. tostring(err))
	end
end

-- damage of an archetype's own (tree bonuses apply, as to a spell)
local function dealOwn(source, attacker, target, ctype, amount, effect)
	amount = math.floor(amount or 0)
	if amount <= 0 or not target or target:getHealth() <= 0 then
		return
	end
	local before = M.source
	M.source = source
	local ok, err = pcall(doTargetCombat, attacker, target, ctype, -amount, -amount, effect or CONST_ME_NONE, ORIGIN_SPELL)
	M.source = before
	if not ok then
		print("[ChaosArchetypes] " .. tostring(err))
	end
end

-- ------------------------------------------------------------------------------------------------ the chain queue
local queue = A.newQueue()
local queueRunning = false
local chainSeq = 0
local function newChain()
	chainSeq = chainSeq + 1
	return chainSeq
end

local marks = {poison = {}, burn = {}, ice = {}} -- monster id -> record
local hobbleMarks = {} -- creature id -> time the slow of Hobbling Shot ends

local function addPoisonLike(kind, owner, target, spread)
	local ctype = kind == "poison" and CONDITION_POISON or CONDITION_FIRE
	if not ctype or not Condition then
		return
	end
	local c = Condition(ctype)
	c:setParameter(CONDITION_PARAM_OWNER, owner:getId())
	c:setParameter(CONDITION_PARAM_DELAYED, true)
	c:addDamage(spread.ticks, spread.tickMs, -spread.tick)
	target:addCondition(c)
	marks[kind][target:getId()] = {owner = owner:getId(), tick = spread.tick, at = now(), gen = spread.gen,
		chain = spread.chain}
	target:getPosition():sendMagicEffect(kind == "poison" and (CONST_ME_HITBYPOISON or CONST_ME_POFF)
		or (CONST_ME_HITBYFIRE or CONST_ME_POFF))
end

local function runSpread(item)
	local owner = Player(item.owner)
	if not owner then
		return
	end
	if item.kind == "shatter" then
		local pos = Position(item.pos.x, item.pos.y, item.pos.z)
		pos:sendMagicEffect(fx("ice_shatter", CONST_ME_ICEAREA or CONST_ME_POFF))
		for _, t in ipairs(A.pickNear(around(owner, item.pos, item.radius, true), item.pos, item.radius, nil, 8)) do
			local c = Creature(t.id)
			if c then
				marks.ice[t.id] = {owner = item.owner, at = now(), gen = item.gen, chain = item.chain}
				dealOwn("shatter", owner, c, COMBAT_ICEDAMAGE, item.amount, CONST_ME_ICEATTACK or CONST_ME_NONE)
			end
		end
		return
	end
	-- poison / burn: to the nearest monsters that do not carry this chain's mark yet
	local exclude = {[item.from] = true}
	for id, r in pairs(marks[item.kind]) do
		if r.chain == item.chain and r.gen >= item.gen then
			exclude[id] = true
		end
	end
	for _, t in ipairs(A.pickNear(around(owner, item.pos, item.radius, true), item.pos, item.radius, exclude, item.targets)) do
		local c = Creature(t.id)
		if c and c:isMonster() then
			addPoisonLike(item.kind, owner, c, item)
		end
	end
end

local function processQueue()
	local items = A.drain(queue)
	for _, item in ipairs(items) do
		local ok, err = pcall(runSpread, item)
		if not ok then
			print("[ChaosArchetypes] spread: " .. tostring(err))
		end
	end
	if #queue.items > 0 then
		addEvent(processQueue, cfg().chain.tickMs)
	else
		queueRunning = false
		A.forgetChains(queue)
	end
end

local function enqueue(item)
	if A.enqueue(queue, item) and not queueRunning then
		queueRunning = true
		addEvent(processQueue, cfg().chain.tickMs)
	end
end

-- ------------------------------------------------------------------------------------------------ hands and weapons
local function handWeapon(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local it = ItemType(item:getId())
			local wt = it:getWeaponType()
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO and wt ~= (WEAPON_QUIVER or 8) then
				return it
			end
		end
	end
	return nil
end

local function isBow(it)
	if not it or it:getWeaponType() ~= WEAPON_DISTANCE then
		return false
	end
	if not ChaosArchery then
		pcall(dofile, "data/lib/chaos_archery_core.lua")
	end
	if ChaosArchery and ChaosArchery.kindOfType then
		local kind = ChaosArchery.kindOfType(it)
		return kind == "bow" or kind == "crossbow"
	end
	return bit and SLOTP_TWO_HAND and bit.band(it:getSlotPosition(), SLOTP_TWO_HAND) ~= 0 or false
end

local function isMonkLine(player)
	local voc = player:getVocation()
	return voc ~= nil and ChaosMonk ~= nil and ChaosMonk.isMonkLine ~= nil and ChaosMonk.isMonkLine(voc:getId())
end

local function attackFactor(player)
	local mode = player.getFightMode and player:getFightMode() or 1
	if mode == 2 then
		return 1.2
	elseif mode == 3 then
		return 2.0
	end
	return 1.0
end

local function bestMeleeSkill(player)
	local best = 0
	for _, s in ipairs({SKILL_FIST, SKILL_SWORD, SKILL_AXE, SKILL_CLUB}) do
		if s then
			best = math.max(best, player:getEffectiveSkillLevel(s))
		end
	end
	return best
end

-- ------------------------------------------------------------------------------------------------ per player state
local state = {} -- player id -> {leech, cascadeAt, effigies, sigil, relic, relicAt, castBuffer, bosses}
local function stateOf(pid)
	local s = state[pid]
	if not s then
		s = {leech = {}, effigies = {}, bosses = {}, slam = {}, rampage = {}, lastStand = {}}
		state[pid] = s
	end
	return s
end
M.state = state

local relicBuffs = {} -- member id -> until time
M.hollow = M.hollow or {} -- player id -> {cut = the health given up} (Hollow Vessel)
M.lastHit = M.lastHit or {} -- player id -> ms of the last hit taken (Hollow Vessel, Hollowglass Diadem)

-- ------------------------------------------------------------------------------------------------ Aether Edge
function M.syncAether(player)
	local flags = flagsOf(player:getId())
	local a = cfg().arAetherEdge
	local has = player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, a.subId) ~= nil
	if flags and flags.arAetherEdge then
		if not has and Condition then
			local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
			c:setParameter(CONDITION_PARAM_SUBID, a.subId)
			c:setParameter(CONDITION_PARAM_TICKS, -1)
			c:setParameter(CONDITION_PARAM_STAT_MAXHITPOINTSPERCENT, A.aetherHealthPercent())
			player:addCondition(c)
		end
	elseif has then
		player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, a.subId)
	end
end

-- ------------------------------------------------------------------------------------------------ Hollow Vessel
local function refreshShield(player)
	if ChaosEnergyShield and ChaosEnergyShield.apply then
		pcall(ChaosEnergyShield.apply, player, ChaosItemModsCache[player:getId()] or {})
	end
end

-- the maximum health of a holder: a condition that brings it to arHollowVessel.health, sized from the maximum without it
-- and renewed whenever that changes (level, items, tree, Aether Edge); the energy shield follows
function M.syncHollow(player)
	local pid = player:getId()
	local flags = flagsOf(pid)
	local h = cfg().arHollowVessel
	local st = M.hollow[pid]
	local has = player:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, h.subId) ~= nil
	local applied = (st and has) and st.cut or 0
	if flags and flags.arHollowVessel then
		local cut = A.hollowCut(player:getMaxHealth(), applied)
		if cut ~= applied or (cut > 0 and not has) or not st then
			if has then
				player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, h.subId)
			end
			if cut > 0 and Condition then
				local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
				c:setParameter(CONDITION_PARAM_SUBID, h.subId)
				c:setParameter(CONDITION_PARAM_TICKS, -1)
				c:setParameter(CONDITION_PARAM_STAT_MAXHITPOINTS, -cut)
				player:addCondition(c)
			end
			M.hollow[pid] = {cut = cut}
			refreshShield(player)
		end
	elseif has or st then
		if has then
			player:removeCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, h.subId)
		end
		M.hollow[pid] = nil
		refreshShield(player)
	end
end

-- the energy shield modifier (data/lib/chaos_energy_shield.lua ChaosEnergyShieldModifiers): the keystone's maximum and
-- recharge, the Hollowglass Diadem's recharge
ChaosEnergyShieldModifiers = ChaosEnergyShieldModifiers or {}
ChaosEnergyShieldModifiers.archetypes = function(player, totals, maximum, recharge)
	local pid = player:getId()
	local flags = flagsOf(pid)
	local keystone = flags ~= nil and flags.arHollowVessel == true
	local diadem = hasUnique(pid, "hollowglass")
	if not keystone and not diadem then
		return maximum, recharge
	end
	local cut = keystone and M.hollow[pid] and M.hollow[pid].cut or 0
	return A.hollowShield(maximum, cut, keystone, hasUnique(pid, "stillheart")), recharge + A.hollowRecharge(keystone, diadem)
end

local function engineDelay()
	local ok, v = pcall(function()
		return configManager.getNumber(configKeys.ENERGY_SHIELD_RECHARGE_DELAY)
	end)
	return ok and tonumber(v) or 2000
end

-- the early recharge: the part of the last second between earlyMs and the engine's delay after the last hit
local function earlyRecharge(player, t)
	local pid = player:getId()
	local last = M.lastHit[pid]
	if not last or not player.getEnergyShield then
		return
	end
	local gain = A.earlyRecharge(player:getEnergyShield(), player:getMaxEnergyShield(), player:getEnergyShieldRecharge(),
		t - last, cfg().arPyreOath.thinkMs, engineDelay())
	if gain > 0 then
		player:setEnergyShield(player:getEnergyShield() + gain)
	end
	if t - last > 10000 then
		M.lastHit[pid] = nil
	end
end

-- the base of the rifts' percent-of-maximum-health hits: health + maximum shield for a Hollow Vessel
function M.percentBase(player)
	local flags = player and flagsOf(player:getId())
	local keystone = flags ~= nil and flags.arHollowVessel == true
	return A.percentBase(player:getMaxHealth(), keystone and player.getMaxEnergyShield and player:getMaxEnergyShield() or 0,
		keystone)
end

-- ------------------------------------------------------------------------------------------------ effigies
local function effigyRemove(e)
	local c = e.id and Creature(e.id)
	if c then
		c:getPosition():sendMagicEffect(CONST_ME_POFF)
		c:remove()
	end
end
M.removeEffigy = effigyRemove

local function raiseEffigy(player, cast)
	local pid = player:getId()
	local s = stateOf(pid)
	local pos = player:getPosition()
	local e = {pos = copyPos(pos), untilTime = now() + cfg().arEffigy.lifeMs, nextPulse = now() + cfg().arEffigy.pulseMs,
		cast = cast}
	local ok, m = pcall(Game.createMonster, cfg().arEffigy.monster, pos, false, true)
	if ok and m then
		bindSummon(player, m)
		if m.setDropLoot then
			m:setDropLoot(false)
		end
		e.id = m:getId()
		e.pos = copyPos(m:getPosition())
	end
	Position(e.pos.x, e.pos.y, e.pos.z):sendMagicEffect(fx("arcane_circle", CONST_ME_MAGIC_RED or CONST_ME_POFF))
	for _, gone in ipairs(A.effigyAdd(s.effigies, e, hasUnique(pid, "effigyIdol"))) do
		effigyRemove(gone)
	end
end

local function pulseEffigies(player, s, t)
	local keep = {}
	for _, e in ipairs(s.effigies) do
		local c = e.id and Creature(e.id)
		if t >= e.untilTime or (e.id and not c) then
			effigyRemove(e)
		else
			if c then
				e.pos = copyPos(c:getPosition())
			end
			if t >= e.nextPulse then
				e.nextPulse = t + cfg().arEffigy.pulseMs
				local amount = A.effigyPulse(e.cast)
				local ctype = NAME_TYPE[e.cast.type] or COMBAT_PHYSICALDAMAGE
				Position(e.pos.x, e.pos.y, e.pos.z):sendMagicEffect(fx("arcane_burst", CONST_ME_FIREAREA or CONST_ME_POFF))
				for _, v in ipairs(A.pickNear(around(player, e.pos, cfg().arEffigy.radius, true), e.pos,
						cfg().arEffigy.radius, nil, e.cast.count)) do
					dealProc(player, Creature(v.id), ctype, amount, CONST_ME_NONE)
				end
			end
			keep[#keep + 1] = e
		end
	end
	s.effigies = keep
end

-- ------------------------------------------------------------------------------------------------ sigils
local function brand(player, target, hit)
	local s = stateOf(player:getId())
	s.sigil = {bearer = target:getId(), hit = hit, untilTime = now() + cfg().arCinderSigil.durationMs,
		nextPulse = now() + cfg().arCinderSigil.pulseMs}
	target:getPosition():sendMagicEffect(fx("holy_cross", CONST_ME_HOLYDAMAGE or CONST_ME_POFF))
end

local function pulseSigil(player, s, t)
	local sg = s.sigil
	if not sg then
		return
	end
	local bearer = Creature(sg.bearer)
	if t >= sg.untilTime or not bearer then
		s.sigil = nil
		return
	end
	if t < sg.nextPulse then
		return
	end
	sg.nextPulse = t + cfg().arCinderSigil.pulseMs
	local bp = copyPos(bearer:getPosition())
	local amount = A.sigilPulse(sg.hit, hasUnique(player:getId(), "ashenChoir"))
	bearer:getPosition():sendMagicEffect(CONST_ME_FIREAREA or CONST_ME_HITBYFIRE or CONST_ME_POFF)
	local list = A.pickNear(around(player, bp, cfg().arCinderSigil.pulseRadius, false), bp, cfg().arCinderSigil.pulseRadius,
		nil, 9)
	for _, v in ipairs(list) do
		dealProc(player, Creature(v.id), COMBAT_FIREDAMAGE, amount, CONST_ME_NONE)
	end
end

-- the bearer died: the sigil jumps to the nearest enemy within jumpRadius (keeps its time)
local function sigilJump(deadId, pos)
	for pid, s in pairs(state) do
		if s.sigil and s.sigil.bearer == deadId then
			local player = Player(pid)
			local next = player and A.pickNear(around(player, pos, cfg().arCinderSigil.jumpRadius, true), pos,
				cfg().arCinderSigil.jumpRadius, {[deadId] = true}, 1)[1]
			if next then
				s.sigil.bearer = next.id
				Position(pos.x, pos.y, pos.z):sendDistanceEffect(Position(next.pos.x, next.pos.y, next.pos.z),
					CONST_ANI_FIRE or 4)
			else
				s.sigil = nil
			end
		end
	end
end

-- ------------------------------------------------------------------------------------------------ spell casts
-- hits of one cast are collected until the end of the tick (an area spell hits every target at once)
local castBuffer = {}
local function flushCast(pid)
	local buffer = castBuffer[pid]
	castBuffer[pid] = nil
	local player = Player(pid)
	if not buffer or not player then
		return
	end
	local flags = flagsOf(pid) or {}
	if flags.arEffigy then
		local cast = A.effigyCast(buffer.hits)
		if cast then
			raiseEffigy(player, cast)
		end
	end
	if flags.arCinderSigil and #buffer.hits == 1 then
		local h = buffer.hits[1]
		local target = Creature(h.id)
		if target and target:getHealth() > 0 then
			brand(player, target, h.amount)
		end
	end
end

local function recordCast(pid, creature, amount, ctype)
	local buffer = castBuffer[pid]
	if not buffer then
		buffer = {hits = {}, index = {}}
		castBuffer[pid] = buffer
		addEvent(flushCast, 0, pid)
	end
	local cid = creature:getId()
	local i = buffer.index[cid]
	if i then
		buffer.hits[i].amount = buffer.hits[i].amount + amount
	else
		buffer.hits[#buffer.hits + 1] = {id = cid, amount = amount, type = typeName(ctype)}
		buffer.index[cid] = #buffer.hits
	end
end

-- ------------------------------------------------------------------------------------------------ the hit event
local function isBoss(creature)
	if not creature:isMonster() then
		return false
	end
	local ok, boss = pcall(function()
		local mt = creature:getType()
		return mt and mt:isBoss()
	end)
	return ok and boss == true
end

local reflecting = false

-- Rampage's extra damage taken and Last Stand: the hit (pd, sd <= 0) on a player holding either keystone. Last Stand is
-- not used against players (PvP). A hit a mana shield took got Rampage's multiplier in the mana event already
-- (manashield.lua): the rest is left as it is.
function M.warriorDefence(player, flags, attacker, pd, sd)
	local pid = player:getId()
	local t = now()
	local s = stateOf(pid)
	if flags.arRampage and not (attacker and ChaosManaShield and ChaosManaShield.scaled(player, attacker, "rampage")) then
		local stacks = A.rampageStacks(s.rampage, t)
		if stacks > 0 then
			local m = A.rampageTaken(stacks)
			pd, sd = A.scale(pd, m), A.scale(sd, m)
		end
	end
	if flags.arLastStand and not (attacker and attacker:isPlayer()) then
		local triggered
		pd, sd, triggered = A.lastStandHit(s.lastStand, t, player:getHealth(),
			player.getEnergyShield and player:getEnergyShield() or 0, player:getMaxHealth(), pd, sd)
		if triggered then
			player:getPosition():sendMagicEffect(fx("arcane_circle", CONST_ME_MAGIC_RED or CONST_ME_POFF))
		end
	end
	return pd, sd
end

-- a player is hit: Thornbound Oath, Sanguine Covenant's healing price, Hollow Vessel's immunities
local function defend(player, flags, attacker, pd, pt, sd, st, origin)
	if pt == COMBAT_HEALING then
		if flags.arSanguine then
			pd, sd = A.healingTaken(pd), A.healingTaken(sd)
		end
		if flags.arLastStand then
			pd, sd = A.lastStandHealing(pd), A.lastStandHealing(sd)
		end
		return pd, sd
	end
	if flags.arHollowVessel then
		local oname = originName(origin)
		if A.hollowImmune(typeName(pt), oname) then
			pd = 0
		end
		if A.hollowImmune(typeName(st), oname) then
			sd = 0
		end
	end
	if flags.arRampage or flags.arLastStand then
		pd, sd = M.warriorDefence(player, flags, attacker, pd, sd)
	end
	if not flags.arThornbound or reflecting or not attacker or attacker:getId() == player:getId() then
		return pd, sd
	end
	if origin == ORIGIN_CONDITION or not (origin == ORIGIN_MELEE or origin == ORIGIN_RANGED or origin == ORIGIN_SPELL) then
		return pd, sd
	end
	local master = attacker:getMaster()
	if master and master:getId() == player:getId() then
		return pd, sd
	end
	local shield = player.getEnergyShield and player:getEnergyShield() or 0
	local landed = math.min(math.abs(pd) + math.abs(sd), player:getHealth() + shield)
	local pid, aid = player:getId(), attacker:getId()
	local s = stateOf(pid)
	local boss = isBoss(attacker)
	if boss then
		s.bosses[aid] = s.bosses[aid] or {}
	end
	local amount = A.reflect({landed = landed, itemReflect = (ChaosItemModsCache[pid] or {}).reflect or 0,
		ownMaxHealth = player:getMaxHealth(), ownLevel = player:getLevel(), unique = hasUnique(pid, "spitethorn"),
		pvp = attacker:isPlayer(), targetMaxHealth = attacker:getMaxHealth(), boss = boss,
		bossState = boss and s.bosses[aid] or nil, now = now()})
	if amount > 0 then
		addEvent(function()
			local p, a = Player(pid), Creature(aid)
			if p and a and validTarget(p, a) then
				reflecting = true
				dealProc(p, a, COMBAT_PHYSICALDAMAGE, amount, CONST_ME_EXPLOSIONHIT or CONST_ME_NONE)
				reflecting = false
			end
		end, 0)
	end
	return pd, sd
end

-- the hit belongs to a spell the player cast: the spell supports' cast context (data/spells/chaos/_supports.lua wraps
-- every spell script and writes serial * 1000 + spell id while it runs). Other "spell" hits (item reflect, procs of
-- other systems, minions dealt as their owner) are not casts: no effigy, no sigil, no ignite, no spell price.
local CONTEXT = (ChaosSupports and ChaosSupports.config and ChaosSupports.config.storageContext) or 7109990
local function castContext(player)
	local v = tonumber(player:getStorageValue(CONTEXT))
	return v ~= nil and v > 0
end

-- Barbed Quiver: a bleed of the player's on the target (a stronger one replaces a weaker: the engine's rule)
local function addBleed(owner, target, tick, ticks, tickMs)
	if not (Condition and CONDITION_BLEEDING) then
		return
	end
	local c = Condition(CONDITION_BLEEDING)
	c:setParameter(CONDITION_PARAM_OWNER, owner:getId())
	c:setParameter(CONDITION_PARAM_DELAYED, true)
	c:addDamage(ticks, tickMs, -tick)
	target:addCondition(c)
	target:getPosition():sendMagicEffect(CONST_ME_DRAWBLOOD or CONST_ME_POFF)
end

-- Hobbling Shot: the slow (the engine's paralyze condition, a fraction of the speed); the mark only when it took
local function hobble(target, t)
	if not (Condition and CONDITION_PARALYZE) then
		return
	end
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, cfg().arHobble.durationMs)
	c:setFormula(-cfg().arHobble.slow, 0, -cfg().arHobble.slow, 0)
	if target:addCondition(c) then
		A.hobbleMark(hobbleMarks, target:getId(), t)
		target:getPosition():sendMagicEffect(CONST_ME_ICEAREA or CONST_ME_POFF)
	end
end

-- a player hits: everything else
local function attack(player, flags, creature, pd, pt, sd, st, origin, critical)
	local pid = player:getId()
	local source = M.source
	local oname = originName(origin)
	if oname == "spell" and not source and not castContext(player) then
		oname = "other"
	end
	local weapon = (oname == "melee" or oname == "ranged") and handWeapon(player) or nil

	-- Open Hand Creed: a fist hit (no weapon in the hands) of a non-Monk
	if oname == "melee" and not source and not weapon and (flags.arOpenHand or hasUnique(pid, "openHand"))
			and not isMonkLine(player) then
		local m = A.openHandFactor(player:getLevel(), player:getEffectiveSkillLevel(SKILL_FIST), bestMeleeSkill(player),
			attackFactor(player), flags.arOpenHand, hasUnique(pid, "openHand"))
		if m and m ~= 1 then
			pd, sd = A.scale(pd, m), A.scale(sd, m)
		end
	end

	-- the prices
	local bow = weapon ~= nil and oname == "ranged" and isBow(weapon)
	local snare = flags.arSnarewright and player:getStorageValue(A.snaresConfig().storage.hit) == 1 or false
	local ctx = {origin = oname, bow = bow, critical = critical == true, source = source, snare = snare}
	local t0 = now()
	local cid0 = creature:getId()
	-- the third round: what the Warrior and Ranger keystones read of the hit
	local isMonsterTarget = creature:isMonster()
	local doSlam = false
	if not source then
		ctx.rampage = flags.arRampage and A.rampageStacks(stateOf(pid).rampage, t0) or nil
		if isMonsterTarget then
			local maxHealth = creature:getMaxHealth()
			ctx.targetFraction = maxHealth > 0 and creature:getHealth() / maxHealth or nil
			ctx.full = maxHealth > 0 and creature:getHealth() >= maxHealth
		end
		if weapon ~= nil and oname == "ranged" and weapon:getWeaponType() == WEAPON_DISTANCE then
			ctx.distWeapon = true
			ctx.distance = A.distance(player:getPosition(), creature:getPosition())
			ctx.hobbled = flags.arHobble and A.hobbled(hobbleMarks, cid0, t0) or false
		end
	end
	local m = A.hitFactor(flags, ctx)
	if flags.arEarthbreaker and oname == "melee" and not source then
		local slamMult
		slamMult, doSlam = A.slamStep(stateOf(pid).slam, t0)
		m = m * slamMult
	end
	local m1, m2 = m * A.typeFactor(flags, typeName(pt), ctx), m * A.typeFactor(flags, typeName(st), ctx)
	-- the Reliquary Warden's party buff and the vigils (Wrath)
	local rb = A.relicBuff(relicBuffs, pid, now())
	if ChaosVigils and ChaosVigils.any(pid) then
		rb = rb * ChaosVigils.dealt(player)
	end
	m1, m2 = m1 * rb, m2 * rb
	if m1 ~= 1 then
		pd = A.scale(pd, m1)
	end
	if m2 ~= 1 then
		sd = A.scale(sd, m2)
	end
	-- Executioner's Verdict: a melee hit or a spell hit that would leave a monster at 15% of its health or less kills it
	-- (spells too since 2026-10-21, player report "so funciona com attack normal, nao com magias")
	if flags.arExecutioner and (oname == "melee" or oname == "spell") and not source and isMonsterTarget and validTarget(player, creature) then
		local executed
		pd, sd, executed = A.executeHit(creature:getHealth(), creature:getMaxHealth(), pd, sd, isBoss(creature))
		if executed then
			creature:getPosition():sendMagicEffect(fx("blood_slash", CONST_ME_DRAWBLOOD or CONST_ME_POFF))
		end
	end
	local amount = math.abs(pd) + math.abs(sd)
	if amount <= 0 then
		return pd, sd
	end
	local cid = creature:getId()
	local t = now()

	-- the marks the deaths read (any origin, own sources too)
	if creature:isMonster() then
		if flags.arWinterLattice and (pt == COMBAT_ICEDAMAGE or st == COMBAT_ICEDAMAGE) then
			local old = marks.ice[cid]
			marks.ice[cid] = {owner = pid, at = t, gen = old and old.gen or 0, chain = old and old.chain or nil}
		end
		if oname == "condition" and pt == COMBAT_EARTHDAMAGE and flags.arContagion then
			local old = marks.poison[cid]
			marks.poison[cid] = {owner = pid, tick = math.abs(pd), at = t, gen = old and old.gen or 0,
				chain = old and old.chain or nil}
		end
		if oname == "condition" and pt == COMBAT_FIREDAMAGE and flags.arCinderSigil then
			local old = marks.burn[cid]
			marks.burn[cid] = {owner = pid, tick = math.abs(pd), at = t, gen = old and old.gen or 0,
				chain = old and old.chain or nil}
		end
	end

	-- Sanguine Covenant: the leech, on the damage that really landed (read from the target's health a tick later)
	if flags.arSanguine and oname ~= "condition" then
		local before = creature:getHealth()
		local unique = hasUnique(pid, "sanguineVein")
		addEvent(function()
			local p = Player(pid)
			if not p or p:getHealth() <= 0 then
				return
			end
			local target = Creature(cid)
			local landed = A.landed(amount, before, target and target:getHealth() or 0)
			local give = A.leech(stateOf(pid).leech, now(), landed, p:getMaxHealth(), unique)
			if give > 0 and Chaos and Chaos.heal then
				Chaos.heal(p, give)
			end
		end, 0)
	end

	if source then
		return pd, sd -- nothing else reacts to an archetype's own damage
	end

	local tpos = copyPos(creature:getPosition())

	-- Aether Edge: weapon and fist hits add energy from the energy shield
	if flags.arAetherEdge and (oname == "melee" or oname == "ranged") then
		local extra = A.aetherAmount(player.getEnergyShield and player:getEnergyShield() or 0, hasUnique(pid, "aetherPlate"))
		if extra > 0 then
			addEvent(function()
				local p, c = Player(pid), Creature(cid)
				if p and c and validTarget(p, c) then
					dealOwn("aether", p, c, COMBAT_ENERGYDAMAGE, extra, CONST_ME_ENERGYHIT or CONST_ME_NONE)
				end
			end, 0)
		end
	end

	-- Earthbreaker: the fourth melee hit slams the ground
	if doSlam then
		local slam = A.slamAmount(amount)
		local radius = cfg().arEarthbreaker.radius
		addEvent(function()
			local p = Player(pid)
			if not p then
				return
			end
			Position(tpos.x, tpos.y, tpos.z):sendMagicEffect(CONST_ME_GROUNDSHAKER or CONST_ME_POFF)
			for _, v in ipairs(A.pickNear(around(p, tpos, radius, true), tpos, radius, {[cid] = true},
					cfg().arEarthbreaker.maxTargets)) do
				dealProc(p, Creature(v.id), COMBAT_PHYSICALDAMAGE, slam, CONST_ME_GROUNDSHAKER or CONST_ME_NONE)
			end
		end, 0)
	end

	-- Barbed Quiver: a distance weapon hit bleeds
	if flags.arBarbed and ctx.distWeapon then
		local tick, ticks, tickMs = A.bleedOf(amount)
		if tick then
			addEvent(function()
				local p, c = Player(pid), Creature(cid)
				if p and c and validTarget(p, c) then
					addBleed(p, c, tick, ticks, tickMs)
				end
			end, 0)
		end
	end

	-- Hobbling Shot: a distance weapon hit may slow its target
	if flags.arHobble and ctx.distWeapon and A.hobbleRoll(hobbleMarks, cid, t) then
		addEvent(function()
			local p, c = Player(pid), Creature(cid)
			if p and c and validTarget(p, c) then
				hobble(c, now())
			end
		end, 0)
	end

	-- Cascade Edge: a critical hit bursts
	if flags.arCascade and critical and oname ~= "condition" then
		local s = stateOf(pid)
		local unique = hasUnique(pid, "splinteredInstant")
		if (s.cascadeAt or 0) <= t then
			s.cascadeAt = t + A.cascadeIcd(unique)
			local burst = A.cascadeAmount(amount, unique)
			local ctype = NAME_TYPE[A.cascadeElement(ChaosPassiveCache[pid])] or COMBAT_ENERGYDAMAGE
			addEvent(function()
				local p = Player(pid)
				if not p then
					return
				end
				Position(tpos.x, tpos.y, tpos.z):sendMagicEffect(fx("arcane_burst", CONST_ME_ENERGYAREA or CONST_ME_POFF))
				for _, v in ipairs(A.pickNear(around(p, tpos, cfg().arCascade.radius, true), tpos, cfg().arCascade.radius,
						{[cid] = true}, 8)) do
					dealProc(p, Creature(v.id), ctype, burst, CONST_ME_NONE)
				end
			end, 0)
		end
	end

	-- Stormstring: bow hits arc
	if bow then
		local arcs, share = A.stormArcs(flags.arStormstring, hasUnique(pid, "stormcaller"))
		if arcs then
			local arc = math.floor(amount * share)
			addEvent(function()
				local p = Player(pid)
				if not p then
					return
				end
				for _, v in ipairs(A.pickNear(around(p, tpos, cfg().arStormstring.radius, true), tpos,
						cfg().arStormstring.radius, {[cid] = true}, arcs)) do
					Position(tpos.x, tpos.y, tpos.z):sendDistanceEffect(Position(v.pos.x, v.pos.y, v.pos.z),
						CONST_ANI_ENERGY or 5)
					dealProc(p, Creature(v.id), COMBAT_ENERGYDAMAGE, arc, CONST_ME_ENERGYHIT or CONST_ME_NONE)
				end
			end, 0)
		end
	end

	-- spells: the effigy and sigil casts, the ignite
	if oname == "spell" then
		if flags.arEffigy or flags.arCinderSigil then
			recordCast(pid, creature, amount, pt)
		end
		if flags.arCinderSigil and creature:isMonster() and (pt == COMBAT_FIREDAMAGE or pt == COMBAT_HOLYDAMAGE) then
			local tick, ticks, tickMs = A.igniteTick(amount)
			local old = marks.burn[cid]
			addPoisonLike("burn", player, creature, {tick = tick, ticks = ticks, tickMs = tickMs,
				gen = old and old.gen or 0, chain = old and old.chain or nil})
		end
	end
	return pd, sd
end

-- the mana shield part of a hit (manashield.lua): Rampage's extra damage taken
if not ChaosManaShield or not ChaosManaShield.provide then
	dofile("data/scripts/chaos/manashield_core.lua")
end
ChaosManaShield.provide("rampage", {
	hit = function(player, attacker, amount)
		if ChaosKeystones.depth > 0 then
			return nil
		end
		local flags = flagsOf(player:getId())
		if not flags or not flags.arRampage then
			return nil
		end
		local stacks = A.rampageStacks(stateOf(player:getId()).rampage, now())
		return stacks > 0 and A.scale(amount, A.rampageTaken(stacks)) or amount
	end
})

local hit = CreatureEvent("ChaosArchetypesHit")
function hit.onHealthChange(creature, attacker, pd, pt, sd, st, origin, critical)
	if ChaosKeystones.depth > 0 or not creature then
		return pd, pt, sd, st
	end
	if creature:isPlayer() then
		local cpid = creature:getId()
		local flags = flagsOf(cpid)
		if flags then
			pd, sd = defend(creature, flags, attacker, pd, pt, sd, st, origin)
		end
		if pt ~= COMBAT_HEALING then
			-- the vigils (Iron) on the player taking the hit
			if ChaosVigils and ChaosVigils.any(cpid) then
				local m = ChaosVigils.taken(creature)
				if m ~= 1 then
					pd, sd = A.scale(pd, m), A.scale(sd, m)
				end
			end
			-- the last hit taken, for Hollow Vessel's early recharge
			if (flags and flags.arHollowVessel) or hasUnique(cpid, "hollowglass") then
				if math.abs(pd) + math.abs(sd) > 0 then
					M.lastHit[cpid] = now()
				end
			end
		end
	end
	if pt == COMBAT_HEALING or not attacker or attacker:getId() == creature:getId() then
		return pd, pt, sd, st
	end
	local player = attacker:isPlayer() and attacker or nil
	if player then
		local pid = player:getId()
		local flags = flagsOf(pid)
		if flags or M.uniques[pid] or relicBuffs[pid] or (ChaosVigils and ChaosVigils.any(pid)) then
			pd, sd = attack(player, flags or {}, creature, pd, pt, sd, st, origin, critical)
		end
	end
	return pd, pt, sd, st
end
hit:register()

-- ------------------------------------------------------------------------------------------------ deaths
local death = CreatureEvent("ChaosArchetypesDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local cid = creature:getId()
	local pos = copyPos(creature:getPosition())
	local t = now()
	-- Rampage: the player who killed a monster (not a summon) gets a stack
	local k = killer and killer.isPlayer and killer:isPlayer() and killer
		or (mostDamageKiller and mostDamageKiller.isPlayer and mostDamageKiller:isPlayer() and mostDamageKiller) or nil
	if k and creature:isMonster() and not creature:getMaster() then
		local kf = flagsOf(k:getId())
		if kf and kf.arRampage then
			A.rampageKill(stateOf(k:getId()).rampage, t)
		end
	end
	hobbleMarks[cid] = nil
	local p = marks.poison[cid]
	if p then
		local owner = Player(p.owner)
		local flags = owner and flagsOf(p.owner)
		local spread = flags and flags.arContagion and A.contagionSpread(p, t, hasUnique(p.owner, "rotbloom"))
		if spread then
			spread.kind, spread.pos, spread.from = "poison", pos, cid
			spread.chain = spread.chain or newChain()
			enqueue(spread)
		end
	end
	local b = marks.burn[cid]
	if b then
		local flags = Player(b.owner) and flagsOf(b.owner)
		local spread = flags and flags.arCinderSigil and A.burnSpread(b, t)
		if spread then
			spread.kind, spread.pos, spread.from = "burn", pos, cid
			spread.chain = spread.chain or newChain()
			enqueue(spread)
		end
	end
	local ice = marks.ice[cid]
	if ice and t - ice.at <= cfg().arWinterLattice.recentMs then
		local owner = Player(ice.owner)
		local flags = owner and flagsOf(ice.owner)
		if flags and flags.arWinterLattice then
			local unique = hasUnique(ice.owner, "longWinter")
			enqueue({kind = "shatter", owner = ice.owner, pos = pos, from = cid, gen = (ice.gen or 0) + 1,
				chain = ice.chain or newChain(), radius = A.shatterRadius(unique),
				amount = A.shatterAmount(creature:getMaxHealth(), owner:getLevel(), unique)})
		end
	end
	marks.poison[cid], marks.burn[cid], marks.ice[cid] = nil, nil, nil
	sigilJump(cid, pos)
	return true
end
death:register()

-- ------------------------------------------------------------------------------------------------ registration
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
	if creature and target and creature:isPlayer() and not eventKnown(target, "ChaosArchetypesDeath") then
		local cid = creature:getId()
		if M.flags[cid] or M.uniques[cid] then
			registerOnce(target, "ChaosArchetypesHit")
			if target:isMonster() then
				registerOnce(target, "ChaosArchetypesDeath")
			end
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(1)

-- area hits reach monsters nobody targeted: every monster gets the events when it appears (like the passive tree's).
-- The engine runs onSpawn before the placement and gives the monster its id only there (getId() is 0 here; see
-- monster_tiers.lua), so the events go straight onto the creature, as the passive tree's, bestiary's and bounty's do; no
-- id and no timer. Index 10 runs after the passive tree's callback (index 0), so its event comes first on the monster
-- and the shares are taken of the hit with its bonuses (equal indices have no fixed order).
local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	self:registerEvent("ChaosArchetypesHit")
	self:registerEvent("ChaosArchetypesDeath")
	return true
end
spawnCb:register(10)

local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	local inv = CONTAINER_POSITION or 0xFFFF
	if fromPosition.x == inv or toPosition.x == inv then
		local pid = player:getId()
		addEvent(function()
			local p = Player(pid)
			if p then
				M.refreshUniques(p)
			end
		end, 0)
	end
end
moved:register()

local login = CreatureEvent("ChaosArchetypesLogin")
function login.onLogin(player)
	local pid = player:getId()
	addEvent(function() -- after the other login events
		local p = Player(pid)
		if p then
			p:registerEvent("ChaosArchetypesHit")
			M.refreshUniques(p)
		end
	end, 0)
	return true
end
login:register()

function M.dismissRelic(pid)
	local s = state[pid]
	if s and s.relic then
		local c = Creature(s.relic)
		if c then
			c:getPosition():sendMagicEffect(CONST_ME_POFF)
			c:remove()
		end
		s.relic = nil
	end
end

local function cleanup(pid)
	local s = state[pid]
	if s then
		for _, e in ipairs(s.effigies) do
			effigyRemove(e)
		end
		M.dismissRelic(pid)
	end
	state[pid], M.flags[pid], M.uniques[pid], castBuffer[pid], relicBuffs[pid] = nil, nil, nil, nil, nil
	hobbleMarks[pid] = nil
	M.hollow[pid], M.lastHit[pid] = nil, nil
	-- the snares live on the spells' side; when it shares this Lua state they go at once (else at its next visit)
	if ChaosSnares and ChaosSnares.clearOwner then
		pcall(ChaosSnares.clearOwner, pid)
	end
end

local logout = CreatureEvent("ChaosArchetypesLogout")
function logout.onLogout(player)
	cleanup(player:getId())
	return true
end
logout:register()

local playerDeath = CreatureEvent("ChaosArchetypesPlayerDeath")
function playerDeath.onDeath(player)
	local pid = player:getId()
	local s = state[pid]
	if s then
		for _, e in ipairs(s.effigies) do
			effigyRemove(e)
		end
		s.effigies, s.sigil = {}, nil
		M.dismissRelic(pid)
	end
	if ChaosSnares and ChaosSnares.clearOwner then
		pcall(ChaosSnares.clearOwner, pid)
	end
	return true
end
playerDeath:register()
local deathLogin = CreatureEvent("ChaosArchetypesDeathLogin")
function deathLogin.onLogin(player)
	player:registerEvent("ChaosArchetypesPlayerDeath")
	return true
end
deathLogin:register()

-- ------------------------------------------------------------------------------------------------ the think
local function inPz(creature)
	local tile = creature:getTile()
	return tile ~= nil and TILESTATE_PROTECTIONZONE ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function pyreTick(player)
	local p = cfg().arPyreOath
	local pos = player:getPosition()
	local enemies = around(player, pos, p.radius, true)
	local inFight = CONDITION_INFIGHT ~= nil and player:getCondition(CONDITION_INFIGHT) ~= nil
	if not A.pyreActive(inPz(player), inFight, #enemies > 0) then
		return
	end
	local maxHealth = player:getMaxHealth()
	local shield = player.getEnergyShield and player:getEnergyShield() or 0
	local regen = A.pyreRegen(maxHealth)
	if regen > 0 and Chaos and Chaos.heal then
		Chaos.heal(player, regen)
	end
	local burn = A.pyreBurn(maxHealth, player:getHealth(), shield)
	if burn > 0 then
		pcall(doTargetCombatHealth, 0, player, COMBAT_FIREDAMAGE, -burn, -burn, CONST_ME_NONE)
	end
	local aura = A.pyreAura(maxHealth, hasUnique(player:getId(), "pyreMantle"))
	pos:sendMagicEffect(fx("fire_ring", CONST_ME_FIREAREA or CONST_ME_POFF))
	for _, v in ipairs(enemies) do
		dealOwn("pyre", player, Creature(v.id), COMBAT_FIREDAMAGE, aura, CONST_ME_HITBYFIRE or CONST_ME_NONE)
	end
end

local function relicTick(player, s, t)
	local r = cfg().arReliquary
	local pid = player:getId()
	if inPz(player) then
		M.dismissRelic(pid)
		return
	end
	local relic = s.relic and Creature(s.relic)
	local ppos = player:getPosition()
	if not relic then
		local ok, m = pcall(Game.createMonster, r.monster, ppos, false, true)
		if not ok or not m then
			return
		end
		bindSummon(player, m)
		if m.setDropLoot then
			m:setDropLoot(false)
		end
		s.relic = m:getId()
		relic = m
		ppos:sendMagicEffect(fx("holy_spiral", CONST_ME_HOLYAREA or CONST_ME_POFF))
	elseif A.distance(relic:getPosition(), ppos) > r.leashSqm then
		relic:teleportTo(ppos)
	end
	if (s.relicAt or 0) > t then
		return
	end
	s.relicAt = t + r.pulseMs
	local unique = hasUnique(pid, "reliquaryCenser")
	local rpos = copyPos(relic:getPosition())
	Position(rpos.x, rpos.y, rpos.z):sendMagicEffect(fx("holy_spiral", CONST_ME_HOLYAREA or CONST_ME_POFF))
	-- the party (and the owner) within healRadius
	local members = {player}
	local party = player:getParty()
	if party then
		members = party:getMembers() or {}
		members[#members + 1] = party:getLeader()
	end
	local seen = {}
	for _, member in ipairs(members) do
		if member and not seen[member:getId()] and A.distance(member:getPosition(), rpos) <= r.healRadius
				and member:getHealth() > 0 then
			seen[member:getId()] = true
			local heal = A.relicHeal(member:getMaxHealth(), player:getMagicLevel(), unique)
			if heal > 0 then
				ChaosKeystones.depth = ChaosKeystones.depth + 1
				pcall(doTargetCombat, player, member, COMBAT_HEALING, heal, heal, CONST_ME_NONE, ORIGIN_SPELL)
				ChaosKeystones.depth = ChaosKeystones.depth - 1
			end
			if member:getId() ~= pid then
				relicBuffs[member:getId()] = t + r.buffMs
			end
		end
	end
	local dmg = A.relicDamage(player:getLevel(), player:getMagicLevel(), unique)
	for _, v in ipairs(around(player, rpos, r.damageRadius, true)) do
		dealOwn("relic", player, Creature(v.id), COMBAT_HOLYDAMAGE, dmg, CONST_ME_HOLYDAMAGE or CONST_ME_NONE)
	end
end

local function think(player, t)
	local pid = player:getId()
	local flags = flagsOf(pid)
	local s = state[pid]
	if flags and flags.arPyreOath then
		pyreTick(player)
	end
	if s then
		if #s.effigies > 0 then
			pulseEffigies(player, s, t)
		end
		if s.sigil then
			pulseSigil(player, s, t)
		end
	end
	if flags and flags.arReliquary then
		relicTick(player, stateOf(pid), t)
	end
	if flags and flags.arHollowVessel then
		M.syncHollow(player)
	end
	if (flags and flags.arHollowVessel) or hasUnique(pid, "hollowglass") then
		earlyRecharge(player, t)
	end
end

local thinkEvent = GlobalEvent("ChaosArchetypesThink")
function thinkEvent.onThink(interval)
	local t = now()
	for pid in pairs(M.flags) do
		local player = Player(pid)
		if player then
			local ok, err = pcall(think, player, t)
			if not ok then
				print("[ChaosArchetypes] think: " .. tostring(err))
			end
		else
			cleanup(pid)
		end
	end
	-- the Hollowglass Diadem without a keystone: the early recharge only
	for pid, u in pairs(M.uniques) do
		if u.hollowglass and not M.flags[pid] then
			local player = Player(pid)
			if player then
				pcall(earlyRecharge, player, t)
			end
		end
	end
	-- forget marks of monsters that are gone and old ones
	for _, map in pairs(marks) do
		for id, r in pairs(map) do
			if t - (r.at or 0) > 10000 or not Creature(id) then
				map[id] = nil
			end
		end
	end
	for id, untilTime in pairs(relicBuffs) do
		if untilTime < t then
			relicBuffs[id] = nil
		end
	end
	return true
end
thinkEvent:interval(cfg().arPyreOath.thinkMs)
thinkEvent:register()

return M
