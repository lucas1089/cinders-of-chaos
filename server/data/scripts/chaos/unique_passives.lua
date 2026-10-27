-- unique_passives.lua: the engine glue of the unique item passives (O278; server/README.md "Unique passives").
-- Rules: unique_passives_core.lua (pure, tested by tests/unique_passives_test.lua), numbers: unique_passives_config.lua.
--   * who wears what: the worn items with the custom attribute chaos_unique whose id has a passive; refreshed at login,
--     on every inventory move and every refreshMs (an item that left a slot without a move event);
--   * ChaosUPDealt (onHealthChange) on the wild monsters a character attacks: damage dealt (multipliers, convert, extra
--     hits, ward gain, marks, stacks, spread bookkeeping);
--   * ChaosUPTaken (onHealthChange) on the character: damage taken (immunity, caps, mana shield, ward, panic), the
--     riposte and the hurt nova, the healing price;
--   * ChaosUPKill (onKill): kill stacks, ward, feast, kill nova, spread;
--   * a one second tick: the ward fades, mend heals, the equipment check;
--   * the Necromancer's minion factors (ChaosNecro.minionFactor) are wrapped for the minion pact.
-- Guards: a passive's own damage is a proc (ChaosKeystones.depth / ChaosSpellFactor.depth up, the own guard flag up):
-- no passive, keystone, class factor or power reacts to it, and a hit that is a proc of another system gets no passive
-- either. Only wild monsters (no summon, no hunt-room display) are ever hit, never a player.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ChaosUniquePassivesConfig = ChaosUniquePassivesConfig or dofile("data/scripts/chaos/unique_passives_config.lua")
if not ChaosUniquePassivesText then
	dofile("data/scripts/chaos/unique_passives_text.lua")
end
if not ChaosUniquePassivesCore then
	dofile("data/scripts/chaos/unique_passives_core.lua")
end
ChaosKeystones = ChaosKeystones or {}
ChaosSpellFactor = ChaosSpellFactor or {}
ChaosUniquePassives = ChaosUniquePassives or {}
local M = ChaosUniquePassives
local C = ChaosUniquePassivesCore
local CFG = ChaosUniquePassivesConfig

local guard = false
local states = {} -- player id -> {S = core state, act = {entries}, key = "ids", line = "warrior", at = ms}
M.states = states

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local SLOTS = {}
for _, s in ipairs({"CONST_SLOT_HEAD", "CONST_SLOT_NECKLACE", "CONST_SLOT_ARMOR", "CONST_SLOT_RIGHT", "CONST_SLOT_LEFT",
		"CONST_SLOT_LEGS", "CONST_SLOT_FEET", "CONST_SLOT_RING", "CONST_SLOT_BADGE"}) do
	if _G[s] then
		SLOTS[#SLOTS + 1] = _G[s]
	end
end

local TYPE_NAME, NAME_TYPE = {}, {}
for name, key in pairs({physical = "COMBAT_PHYSICALDAMAGE", fire = "COMBAT_FIREDAMAGE", ice = "COMBAT_ICEDAMAGE",
		energy = "COMBAT_ENERGYDAMAGE", earth = "COMBAT_EARTHDAMAGE", death = "COMBAT_DEATHDAMAGE",
		holy = "COMBAT_HOLYDAMAGE", drown = "COMBAT_DROWNDAMAGE"}) do
	if _G[key] then
		TYPE_NAME[_G[key]] = name
		NAME_TYPE[name] = _G[key]
	end
end
NAME_TYPE.poison = NAME_TYPE.earth
NAME_TYPE.bleed = NAME_TYPE.physical

local function originName(origin)
	if origin == ORIGIN_MELEE then
		return "melee"
	elseif origin == ORIGIN_RANGED or (ORIGIN_WAND and origin == ORIGIN_WAND) then
		return "ranged"
	elseif origin == ORIGIN_SPELL then
		return "spell"
	end
	return "other"
end

local function scale(v, mult)
	local a = math.floor(math.abs(v) * mult + 0.5)
	return v < 0 and -a or a
end

local function wild(c)
	if not c or not c:isMonster() or c:getMaster() then
		return false
	end
	local HT = ChaosHuntTeleports
	return not (HT and HT.isDisplay and HT.isDisplay(c))
end

local function isProc()
	return guard or (ChaosKeystones.depth or 0) > 0 or (ChaosSpellFactor.depth or 0) > 0
end

local function label(pos, text, color)
	if ChaosCombatFx and ChaosCombatFx.label then
		pcall(ChaosCombatFx.label, pos, text, color or 205)
	end
end

local function labelOnce(st, key, pos, text, t)
	local last = st.S.labels[key]
	if not last or t - last >= CFG.labelMs then
		st.S.labels[key] = t
		label(pos, text)
	end
end

-- ------------------------------------------------------------------------------------------------ who wears what
local function stateOf(player)
	local id = player:getId()
	local st = states[id]
	if not st then
		st = {S = C.newState(), act = {}, key = "", at = 0}
		states[id] = st
	end
	return st
end

function M.refresh(player)
	local st = stateOf(player)
	local ids = {}
	for _, slot in ipairs(SLOTS) do
		local item = player:getSlotItem(slot)
		if item and CFG.passives[item:getId()] then
			local ok, mark = pcall(item.getCustomAttribute, item, "chaos_unique")
			if ok and mark and mark ~= 0 then
				ids[#ids + 1] = item:getId()
			end
		end
	end
	local voc = player:getVocation()
	st.line = ChaosClasses and ChaosClasses.lineKey and voc and ChaosClasses.lineKey(voc:getId()) or nil
	st.act = st.line and C.activeSet(CFG, ids, st.line) or {}
	st.key = C.key(st.act)
	st.at = now()
	if #st.act == 0 then
		st.S.ward = 0
	end
	return st
end

-- the state of a player; the equipment check runs when it is older than refreshMs
local function actOf(player)
	local st = states[player:getId()]
	if not st then
		return nil
	end
	if now() - st.at > CFG.refreshMs * 2 then
		M.refresh(player)
	end
	return #st.act > 0 and st or nil
end

-- ------------------------------------------------------------------------------------------------ damage of its own
local function inSight(pos, c)
	if not pos.isSightClear then
		return true
	end
	local ok, clear = pcall(pos.isSightClear, pos, c:getPosition(), true)
	return not ok or clear ~= false
end

local function monstersAround(pos, radius, limit, skip)
	local out = {}
	for _, c in ipairs(Game.getSpectators(pos, false, false, radius, radius, radius, radius) or {}) do
		if #out >= limit then
			break
		end
		if c ~= skip and wild(c) and c:getHealth() > 0 and inSight(pos, c) then
			out[#out + 1] = c
		end
	end
	return out
end

local function strike(player, target, ctype, amount, fx)
	if not target or target:getHealth() <= 0 or amount <= 0 or not wild(target) then
		return
	end
	local K, SF = ChaosKeystones, ChaosSpellFactor
	guard = true
	K.depth = (K.depth or 0) + 1
	SF.depth = (SF.depth or 0) + 1
	local PW = ChaosPowers
	if PW then
		PW.depth = (PW.depth or 0) + 1
	end
	local ok, err = pcall(doTargetCombatHealth, player:getId(), target:getId(), ctype or COMBAT_PHYSICALDAMAGE,
		-math.abs(amount), -math.abs(amount), fx or CONST_ME_NONE)
	if PW then
		PW.depth = PW.depth - 1
	end
	SF.depth = SF.depth - 1
	K.depth = K.depth - 1
	guard = false
	if not ok then
		print("[ChaosUniquePassives] " .. tostring(err))
	end
end

local function heal(creature, amount, mult)
	amount = math.floor(amount * (mult or 1))
	if amount > 0 then
		guard = true
		pcall(Chaos.heal, creature, amount)
		guard = false
	end
end

-- a price in health (never kills: the plans keep minHealth), taken without the passives reacting to it
local function selfCost(p, n)
	guard = true
	local before = p:getHealth()
	pcall(p.addHealth, p, "damage", n) -- this engine: (type, amount); the stock signature takes a negative amount
	if p:getHealth() == before then
		pcall(p.addHealth, p, -n)
	end
	guard = false
end

local function pct(p)
	return p:getMaxHealth() > 0 and math.floor(p:getHealth() * 100 / p:getMaxHealth()) or 100
end

local function statsOf(p)
	local sh = 0
	if SKILL_SHIELD and p.getEffectiveSkillLevel then
		local ok, v = pcall(p.getEffectiveSkillLevel, p, SKILL_SHIELD)
		sh = ok and v or 0
	end
	local speed = 0
	if p.getSpeed then
		local ok, v = pcall(p.getSpeed, p)
		speed = ok and v or 0
	end
	return {maxMana = p:getMaxMana(), maxHealth = p:getMaxHealth(), magicLevel = p:getMagicLevel(), speed = speed,
		shield = sh, level = p:getLevel()}
end

-- the monsters near a character (not the target), cached crowdCacheMs
local function crowd(st, p, target, t)
	local c = st.crowd
	if c and t - c.at < CFG.crowdCacheMs then
		return c.n
	end
	local radius = (C.find(st.act, "crowd") or {}).radius
	if not radius then
		return 0
	end
	local n = #monstersAround(p:getPosition(), radius, 12, target)
	st.crowd = {at = t, n = n}
	return n
end

-- ------------------------------------------------------------------------------------------------ hits you deal
local dealt = CreatureEvent("ChaosUPDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	if guard or primaryType == COMBAT_HEALING or not attacker or not attacker:isPlayer() or not wild(creature) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st = actOf(attacker)
	if not st then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local t, S, act = now(), st.S, st.act
	local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if total <= 0 then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local ctx = {now = t, origin = originName(origin), elem = TYPE_NAME[primaryType] or "other", crit = critical == true,
		proc = isProc(), dot = origin == ORIGIN_CONDITION, targetId = creature:getId(), targetPlayer = false,
		targetPct = pct(creature), selfPct = pct(attacker), damage = total, stats = statsOf(attacker),
		manaPct = attacker:getMaxMana() > 0 and math.floor(attacker:getMana() * 100 / attacker:getMaxMana()) or 0,
		maxHealth = attacker:getMaxHealth(), health = attacker:getHealth(), maxMana = attacker:getMaxMana(),
		mana = attacker:getMana()}
	if ctx.dot then
		-- a condition tick of yours on a monster: bookkeeping for the spread, no multiplier
		C.noteAfflict(CFG, S, act, creature:getId(), total, t)
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if ctx.proc then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	ctx.others = C.find(act, "crowd") and crowd(st, attacker, creature, t) or 0
	local m = C.dealt(CFG, S, act, ctx)
	local plan = C.convertPlan(act, ctx)
	if plan and primaryType == COMBAT_PHYSICALDAMAGE then
		local part = math.floor(math.abs(primaryDamage) * plan.share)
		if part > 0 then
			primaryDamage = scale(primaryDamage, 1 - plan.share)
			local extra = math.floor(part * plan.mult * m)
			local target = creature
			local pid = attacker:getId()
			strike(attacker, target, NAME_TYPE[plan.elem], extra, CONST_ME_NONE)
		end
	end
	if m ~= 1 then
		primaryDamage, secondaryDamage = scale(primaryDamage, m), scale(secondaryDamage, m)
	end
	total = math.abs(primaryDamage) + math.abs(secondaryDamage)
	ctx.damage = total
	C.landed(CFG, S, act, ctx)
	C.wardGain(CFG, S, act, "hit", total, ctx.maxHealth, t)
	local ch = C.critHeal(CFG, S, act, ctx)
	if ch > 0 then
		heal(attacker, ch)
	end
	if total < creature:getHealth() then
		local ex = C.extraPlan(CFG, S, act, ctx)
		if ex then
			if ex.costKind == "health" and ex.cost > 0 then
				selfCost(attacker, ex.cost)
			elseif ex.costKind == "mana" and ex.cost > 0 then
				attacker:addMana(-ex.cost)
			end
			local ctype = ex.elem and NAME_TYPE[ex.elem] or primaryType
			for _, mon in ipairs(monstersAround(creature:getPosition(), ex.radius, ex.targets, creature)) do
				strike(attacker, mon, ctype, ex.damage, CONST_ME_NONE)
			end
		end
		if critical then
			local nv = C.novaPlan(CFG, S, act, "crit", ctx)
			if nv then
				M.nova(attacker, creature:getPosition(), nv)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

function M.nova(player, pos, nv)
	if nv.cost > 0 then
		selfCost(player, nv.cost)
	end
	local ctype = NAME_TYPE[nv.elem] or COMBAT_FIREDAMAGE
	for _, mon in ipairs(monstersAround(pos, nv.radius, nv.targets)) do
		strike(player, mon, ctype, nv.damage, CONST_ME_FIREAREA)
	end
	if pos.sendMagicEffect then
		pos:sendMagicEffect(CONST_ME_FIREAREA or CONST_ME_EXPLOSIONAREA)
	end
end

local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
end
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if not guard and creature and target and creature:isPlayer() and target:isMonster() then
		local st = actOf(creature)
		if st then
			st.S.fightAt = now()
			if not (Chaos.eventKnown and Chaos.eventKnown(target, "ChaosUPDealt")) then
				registerOnce(target, "ChaosUPDealt")
			end
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- ------------------------------------------------------------------------------------------------ hits you take
local taken = CreatureEvent("ChaosUPTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if not creature:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st = actOf(creature)
	if not st then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local t = now()
	if primaryType == COMBAT_HEALING then
		if not guard then
			local hm = C.healMult(st.S, st.act, t)
			if hm ~= 1 then
				primaryDamage = math.floor(primaryDamage * hm)
			end
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if total <= 0 or guard then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local fromMonster = attacker ~= nil and attacker:isMonster() and attacker:getMaster() == nil
	local ctx = {now = t, dmg = total, elem = TYPE_NAME[primaryType] or "other", dot = origin == ORIGIN_CONDITION,
		fromMonster = fromMonster, maxHealth = creature:getMaxHealth(), health = creature:getHealth(),
		maxMana = creature:getMaxMana(), mana = creature:getMana(), level = creature:getLevel()}
	local out = C.incoming(CFG, st.S, st.act, ctx)
	if out.dmg ~= total then
		if secondaryDamage == 0 then
			primaryDamage = -out.dmg
		else
			local pa = math.floor(math.abs(primaryDamage) * out.dmg / total + 0.5)
			primaryDamage, secondaryDamage = -pa, -math.max(0, out.dmg - pa)
		end
	end
	if out.mana > 0 then
		pcall(creature.addMana, creature, -out.mana)
	end
	if out.absorbed > 0 then
		labelOnce(st, "ward", creature:getPosition(), "Ward", t)
	end
	if out.panic then
		labelOnce(st, "panic", creature:getPosition(), "Panic", t)
	end
	if fromMonster and attacker:getHealth() > 0 then
		local rep = C.ripostePlan(CFG, st.S, st.act, ctx)
		local nova = C.novaPlan(CFG, st.S, st.act, "hurt", ctx)
		local rid, aid, pid = out.reflect, attacker:getId(), creature:getId()
		if rep or nova or rid > 0 then
			addEvent(function() -- after the hit: never inside the damage call
				local p, a = Player(pid), Creature(aid)
				if not (p and p:getHealth() > 0) then
					return
				end
				if a and a:getHealth() > 0 then
					if rep then
						strike(p, a, NAME_TYPE[rep.elem] or COMBAT_PHYSICALDAMAGE, rep.damage, CONST_ME_HITAREA)
					end
					if rid > 0 then
						strike(p, a, COMBAT_PHYSICALDAMAGE, rid, CONST_ME_NONE)
					end
				end
				if nova then
					M.nova(p, p:getPosition(), nova)
				end
			end, 0)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- ------------------------------------------------------------------------------------------------ kills
local function spreadOut(player, dead, plan)
	local pid, pos = player:getId(), dead:getPosition()
	local ctype = NAME_TYPE[plan.elem] or COMBAT_EARTHDAMAGE
	for _, mon in ipairs(monstersAround(pos, plan.radius, plan.targets, dead)) do
		local mid = mon:getId()
		for k = 1, plan.ticks do
			addEvent(function()
				local p, m = Player(pid), Creature(mid)
				if p and m and m:getHealth() > 0 then
					strike(p, m, ctype, plan.damage, CONST_ME_NONE)
				end
			end, k * plan.tickMs)
		end
	end
end

local kill = CreatureEvent("ChaosUPKill")
function kill.onKill(player, target)
	if guard or not wild(target) then
		return true
	end
	local st = actOf(player)
	if not st then
		return true
	end
	local t = now()
	local ctx = {now = t, maxHealth = player:getMaxHealth(), maxMana = player:getMaxMana(), health = player:getHealth(),
		level = player:getLevel()}
	local out = C.kill(CFG, st.S, st.act, ctx)
	if out.heal > 0 then
		heal(player, out.heal)
	end
	if out.mana > 0 then
		pcall(player.addMana, player, out.mana)
	end
	local nv = C.novaPlan(CFG, st.S, st.act, "kill", ctx)
	if nv then
		M.nova(player, target:getPosition(), nv)
	end
	local rec = st.S.afflict[target:getId()]
	st.S.afflict[target:getId()] = nil
	local sp = C.spreadPlan(CFG, st.S, st.act, rec, t)
	if sp then
		spreadOut(player, target, sp)
	end
	return true
end
kill:register()

-- ------------------------------------------------------------------------------------------------ tick
local function partyOf(player, radius)
	local out = {player}
	local party = player:getParty()
	if not party then
		return out
	end
	local pos = player:getPosition()
	local members = party:getMembers() or {}
	members[#members + 1] = party:getLeader()
	for _, m in ipairs(members) do
		if m and m ~= player and m:getHealth() > 0 and m:getPosition().z == pos.z
				and math.abs(m:getPosition().x - pos.x) <= radius and math.abs(m:getPosition().y - pos.y) <= radius then
			out[#out + 1] = m
		end
	end
	return out
end

local function tick()
	local t = now()
	for _, player in ipairs(Game.getPlayers()) do
		local ok, err = pcall(function()
			local st = states[player:getId()]
			if not st then
				return
			end
			if t - st.at >= CFG.refreshMs then
				M.refresh(player)
			end
			if #st.act == 0 or player:getHealth() <= 0 then
				return
			end
			C.wardFade(CFG, st.S, st.act, player:getMaxHealth(), t)
			local plan = C.mendPlan(CFG, st.S, st.act, t)
			if plan then
				for _, m in ipairs(partyOf(player, plan.radius)) do
					local mst = states[m:getId()]
					local hm = mst and #mst.act > 0 and C.healMult(mst.S, mst.act, t) or 1
					heal(m, m:getMaxHealth() * plan.pct / 100, hm)
				end
			end
		end)
		if not ok then
			print("[ChaosUniquePassives] " .. tostring(err))
		end
	end
	addEvent(tick, CFG.tickMs)
end

local startup = GlobalEvent("ChaosUPStartup")
function startup.onStartup()
	addEvent(tick, CFG.tickMs)
	return true
end
startup:register()

-- ------------------------------------------------------------------------------------------------ Necromancer pact
-- ChaosNecro.minionFactor(player, kind, field): the minion pact adds its hit and health factors (wrapped once)
local function wrapNecro()
	local N = ChaosNecro
	if not N or not N.minionFactor or N._upWrapped then
		return
	end
	N._upWrapped = true
	local base = N.minionFactor
	N.minionFactor = function(player, kind, field)
		local f = base(player, kind, field)
		local st = actOf(player)
		if st then
			local hit, health = C.minion(st.act)
			f = f * (field == "hit" and hit or health)
		end
		return f
	end
end
local wrapEv = GlobalEvent("ChaosUPWrapNecro")
function wrapEv.onStartup()
	addEvent(wrapNecro, 1000)
	return true
end
wrapEv:register()

-- ------------------------------------------------------------------------------------------------ equipment, login
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	local inv = CONTAINER_POSITION or 0xFFFF
	if fromPosition.x == inv or toPosition.x == inv then
		local pid = player:getId()
		addEvent(function()
			local p = Player(pid)
			if p then
				M.refresh(p)
			end
		end, 0)
	end
end
moved:register()

local login = CreatureEvent("ChaosUPLogin")
function login.onLogin(player)
	player:registerEvent("ChaosUPTaken")
	player:registerEvent("ChaosUPKill")
	player:registerEvent("ChaosUPLogout")
	local pid = player:getId()
	addEvent(function()
		local p = Player(pid)
		if p then
			M.refresh(p)
		end
	end, 0)
	return true
end
login:register()

local logout = CreatureEvent("ChaosUPLogout")
function logout.onLogout(player)
	states[player:getId()] = nil
	return true
end
logout:register()
