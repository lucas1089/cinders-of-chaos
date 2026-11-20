-- Spell Forms, the engine side (O686 phase 4; docs/SPELL_UPGRADES.md section 2; server/README.md "Spell Forms (O686 phase 4)").
-- Rules and numbers: spell_forms_core.lua, the Form table data/spells/forms.csv, the read API data/lib/chaos_spell_forms.lua,
-- tests: server/tests/spell_forms_test.lua (this file on a mocked engine).
--
-- * Nothing here acts while spell_ranks_config.lua `enabled` is false, below the rank of a tier (10 / 20) or for a spell with no pick:
--   ChaosSpellForms.active answers an empty list.
-- * The hits. ChaosSpellFormsHit sits on whatever a player with a Form hits (the onTargetCombat callback below, after the supports
--   and the passive tree, so it sees the ranked hit). It reads the cast context the spell side writes (serial * 1000 + spell id), gives
--   the hit the factor of its Forms (SPLIT, REND, DELAY, ... the main hit changes), changes the damage type of a conversion
--   (SHIFT:E, ASCEND:E) and collects the hits of the cast. One tick later (addEvent 0) the cast is over and the extra hits are planned
--   over all of them (ChaosSpellFormsCore.planAll) and run.
-- * Extra hits are hits OF THE SPELL for Brand, Sunder, Keen Edge and Hex: they run inside the spell's cast context, with the proc guard up
--   (ChaosKeystones.depth: no passive tree bonus twice, FE.depth: no Form again), and ChaosSupports.formDepth tells the supports' hit event
--   not to collect them, so Echo, Fork, Breadth, Shatter, Deathburst, Surge, Reprisal, Bloodthirst and Siphon never trigger on them.
--   The spell's own supports run once, on the first hit. Monsters only, except when the main hit was on a player (PvP, numbers halved).
-- * Pick and change: opcode 168 `pick` {spell, tier, pick}; first pick free, a change costs gold (bank first), the last pick may be
--   changed free within 30 minutes (core F.decide).
-- Assumed engine API (TFS 1.4.2): CreatureEvent onHealthChange, EventCallback onTargetCombat, doTargetCombat, Game.getSpectators,
-- addEvent, Player:get/setStorageValue/getBankBalance/setBankBalance/removeMoney/getMoney, Creature:teleportTo. Lua 5.1 / LuaJIT and
-- Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSpellFormsCore or not ChaosSpellFormsCore.plan then
	dofile("data/scripts/chaos/spell_forms_core.lua")
end
if not ChaosSpellRanksCore or not ChaosSpellRanksCore.power then
	dofile("data/scripts/chaos/spell_ranks_core.lua")
end
ChaosSpellRanksConfig = ChaosSpellRanksConfig or dofile("data/scripts/chaos/spell_ranks_config.lua")
dofile("data/lib/chaos_spell_ranks.lua")
dofile("data/lib/chaos_spell_forms.lua")
if not ChaosSupports then
	dofile("data/lib/chaos_supports.lua")
end
if not ChaosSpellEvents or not ChaosSpellEvents.set then
	pcall(dofile, "data/lib/chaos_spell_events.lua")
end

local FE = ChaosSpellForms
local F = ChaosSpellFormsCore
local R = ChaosSpellRanks
local S = ChaosSupports
local cfg = ChaosSpellRanksConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.spellRanks) or cfg.opcode
local floor, max, min = math.floor, math.max, math.min

FE.depth = FE.depth or 0 -- > 0 while a Form's own hit runs
S.formDepth = S.formDepth or 0

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function log(text)
	print("[Chaos spell forms] " .. text)
end

local function try(label, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(label .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function say(player, text)
	if player and player.sendTextMessage then
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, text)
	end
end

local function tr(player, fmt, ...)
	if Chaos.t then
		return Chaos.t(player, fmt, ...)
	end
	return string.format(fmt, ...)
end

-- ---------------------------------------------------------------- guard and context
local function guarded(fn, ...)
	FE.depth = FE.depth + 1
	S.formDepth = S.formDepth + 1
	local K = rawget(_G, "ChaosKeystones")
	if K then
		K.depth = (K.depth or 0) + 1
	end
	local ok, err = pcall(fn, ...)
	if K then
		K.depth = K.depth - 1
	end
	S.formDepth = S.formDepth - 1
	FE.depth = FE.depth - 1
	if not ok then
		log(tostring(err))
	end
end

-- run fn inside the cast context of (serial, spell id), so the supports' hit event knows the spell of a Form hit
local function withContext(player, serial, spellId, fn)
	local W = rawget(_G, "ChaosSupportsSpell")
	local value = S.ctxEncode(serial, spellId)
	if W and W.run then
		return W.run(player:getId(), {pid = player:getId(), value = value, spell = spellId}, fn)
	end
	local key = S.config.storageContext
	local old = player:getStorageValue(key)
	player:setStorageValue(key, value)
	local ok, err = pcall(fn)
	player:setStorageValue(key, old)
	if not ok then
		error(err, 0)
	end
end

local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

-- ---------------------------------------------------------------- creatures
local function isFoe(attacker, c, pvp)
	if not c or c:getId() == attacker:getId() or c:getHealth() <= 0 then
		return false
	end
	local tile = c:getTile()
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false
	end
	if c:isMonster() then
		local master = c:getMaster()
		return not pvp and not (master and (master:getId() == attacker:getId() or master:isPlayer()))
	end
	if pvp and c:isPlayer() then
		-- a player is a target only when the main hit was on a player; never a party member
		local party = attacker:getParty()
		if party and c:getParty() == party then
			return false
		end
		return true
	end
	return false
end

local function foesNear(attacker, pos, radius, pvp)
	local list = {}
	local center = Position(pos.x, pos.y, pos.z)
	for _, c in ipairs(Game.getSpectators(center, false, pvp and true or false, radius, radius, radius, radius) or {}) do
		if isFoe(attacker, c, pvp) then
			list[#list + 1] = {id = c:getId(), pos = copyPos(c:getPosition()), health = c:getHealth(), creature = c}
		end
	end
	return list
end

local function alliesNear(player, pos, radius)
	local list = {}
	local party = player:getParty()
	for _, c in ipairs(Game.getSpectators(Position(pos.x, pos.y, pos.z), false, true, radius, radius, radius, radius) or {}) do
		if c:isPlayer() and c:getHealth() > 0 and (c:getId() == player:getId() or (party and c:getParty() == party)) then
			list[#list + 1] = {id = c:getId(), pos = copyPos(c:getPosition()), health = c:getHealth(), maxHealth = c:getMaxHealth()}
		end
	end
	return list
end

local resistFn = FE.resistFn

local function combatTypeOf(el)
	return el and FE.combatTypes[el] and rawget(_G, FE.combatTypes[el]) or nil
end

-- ---------------------------------------------------------------- the picks of a player, cached for the target callback
local anyCache = {}
local function hasForms(player)
	local pid = player:getId()
	local c = anyCache[pid]
	local t = nowMs()
	if c and t - c.t < 5000 then
		return c.v
	end
	local v = FE.any(player)
	anyCache[pid] = {t = t, v = v}
	return v
end

-- ---------------------------------------------------------------- the hit buffer
local buffers = {} -- pid -> {spellId, serial, hits = {}, index = {}, pvp}
local flush

-- damage dealt by a Form (never to oneself, never a heal here): a hit of the spell, guarded
local function dealHit(player, target, ctype, amount, effectRole, element)
	amount = floor(math.abs(amount))
	if amount <= 0 or not target or target:getHealth() <= 0 then
		return
	end
	if effectRole and FE.sendFx then
		FE.sendFx(target:getPosition(), element or "physical", effectRole)
	end
	guarded(doTargetCombat, player, target, ctype or COMBAT_PHYSICALDAMAGE, -amount, -amount, CONST_ME_NONE, ORIGIN_SPELL)
end

local function dealHeal(player, target, amount)
	amount = floor(math.abs(amount))
	if amount <= 0 or not target or target:getHealth() <= 0 then
		return
	end
	guarded(doTargetCombat, player, target, COMBAT_HEALING, amount, amount, CONST_ME_NONE, ORIGIN_SPELL)
end

-- the shield a Form gives (Ward, Cleanse): player id -> {amount, until}
FE.shields = FE.shields or {}
local function addShield(target, amount, secs)
	local id = target:getId()
	local s = FE.shields[id]
	local t = nowMs()
	if not s or s.untilMs < t then
		s = {amount = 0}
		FE.shields[id] = s
	end
	s.amount = s.amount + floor(amount)
	-- `secs` (the awakening signature, O686 phase 7): how long this shield lasts, at most the 10 s of the Forms; the later end holds
	s.untilMs = max(s.untilMs or 0, t + (secs and min(10000, secs * 1000) or 10000))
end

local function removeOneDebuff(target)
	for _, name in ipairs({"CONDITION_POISON", "CONDITION_FIRE", "CONDITION_ENERGY", "CONDITION_FREEZING", "CONDITION_CURSED",
			"CONDITION_PARALYZE", "CONDITION_BLEEDING", "CONDITION_DROWN", "CONDITION_DAZZLED"}) do
		local ct = rawget(_G, name)
		if ct and target:hasCondition(ct) then
			target:removeCondition(ct)
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- running the actions of a plan
local runAction

local function targetFor(player, a, pvp)
	local c = Creature(a.id)
	if c and c:getHealth() > 0 and isFoe(player, c, pvp) then
		return c
	end
	return nil
end

-- a delayed hit lands on the enemy while it still stands within a tile of where it was hit
local function stillThere(c, pos)
	return not pos or F.dist(c:getPosition(), pos) <= 1
end

local function laterRun(pid, serial, spellId, pvp, element, ctype, a)
	local player = Player(pid)
	if player then
		try("later", withContext, player, serial, spellId, function() runAction(player, serial, spellId, pvp, element, ctype, a, true) end)
	end
end

local ground = {} -- pid -> count of grounds now (cap)

runAction = function(player, serial, spellId, pvp, element, ctype, a, delayed)
	local pid = player:getId()
	if a.delay and a.delay > 0 and not delayed then
		addEvent(laterRun, a.delay, pid, serial, spellId, pvp, element, ctype, a)
		return
	end
	local role = a.fx == "ground" and "ground" or ((a.fx == "aftermath" or a.fx == "delay" or a.fx == "overcharge") and "burst" or "hit")
	local el = a.element or element or "physical"
	local ct = combatTypeOf(a.element or element) or ctype
	if a.t == "hit" then
		local c = targetFor(player, a, pvp)
		if c and (a.delay == nil or a.delay == 0 or stillThere(c, a.pos)) then
			if a.from and FE.missiles[el] then
				local ani = rawget(_G, FE.missiles[el])
				if ani and a.fx ~= "split" then
					Position(a.from.x, a.from.y, a.from.z):sendDistanceEffect(c:getPosition(), ani)
				end
			end
			dealHit(player, c, ct, a.amount, role, el)
		end
	elseif a.t == "dot" then
		local c = targetFor(player, a, pvp)
		if c then
			local ticks, every = a.ticks or 1, a.every or 1000
			local function tick(left)
				local p = Player(pid)
				local t = Creature(a.id)
				if p and t and t:getHealth() > 0 and left > 0 then
					try("dot", withContext, p, serial, spellId, function() dealHit(p, t, ct, a.amount, nil, el) end)
					addEvent(tick, every, left - 1)
				end
			end
			addEvent(tick, every, ticks)
			FE.sendFx(c:getPosition(), el, "status")
		end
	elseif a.t == "burst" then
		local foes = foesNear(player, a.pos, a.radius or 1, pvp)
		for i, f in ipairs(foes) do
			if i > cfg.forms.extraCap then
				break
			end
			dealHit(player, f.creature, ct, a.amount, i == 1 and role or nil, el)
		end
	elseif a.t == "ground" then
		ground[pid] = (ground[pid] or 0) + 1
		if ground[pid] <= cfg.forms.groundCap then
			local function tick(left)
				local p = Player(pid)
				if p and left > 0 then
					try("ground", withContext, p, serial, spellId, function()
						local foes = foesNear(p, a.pos, a.radius or 1, pvp)
						FE.sendFx(Position(a.pos.x, a.pos.y, a.pos.z), el, "ground")
						for i, f in ipairs(foes) do
							if i > cfg.forms.extraCap then
								break
							end
							dealHit(p, f.creature, ct, a.amount, nil, el)
						end
					end)
					addEvent(tick, a.every or 1000, left - 1)
				else
					ground[pid] = max(0, (ground[pid] or 1) - 1)
				end
			end
			tick(a.seconds or 1)
		else
			ground[pid] = ground[pid] - 1
		end
	elseif a.t == "pull" then
		local c = Creature(a.id)
		if c and c:isMonster() and c:getHealth() > 0 then
			for dx = -a.within, a.within do
				for dy = -a.within, a.within do
					local to = Position(a.to.x + dx, a.to.y + dy, a.to.z)
					local tile = Tile(to)
					if tile and tile:getTopCreature() == nil and not tile:hasFlag(TILESTATE_BLOCKSOLID)
							and not tile:hasFlag(TILESTATE_PROTECTIONZONE) then
						c:teleportTo(to, true)
						return
					end
				end
			end
		end
	elseif a.t == "selfheal" then
		local cap = floor(player:getMaxHealth() * a.capPct / 100)
		local heal = min(a.amount, cap)
		if heal > 0 then
			Chaos.heal(player, heal)
		end
	elseif a.t == "selfmana" then
		local cap = floor(player:getMaxMana() * a.capPct / 100)
		local mana = min(a.amount, cap)
		if mana > 0 then
			player:addMana(mana)
		end
	elseif a.t == "heal" then
		local c = Creature(a.id)
		if c and c:getHealth() > 0 then
			if not a.onlyBelow or c:getHealth() * 100 < c:getMaxHealth() * a.onlyBelow then
				FE.sendFx(c:getPosition(), "holy", "hit")
				dealHeal(player, c, a.amount)
			end
		end
	elseif a.t == "hot" then
		local function tick(left)
			local p, c = Player(pid), Creature(a.id)
			if p and c and c:getHealth() > 0 and left > 0 then
				try("hot", withContext, p, serial, spellId, function() dealHeal(p, c, a.amount) end)
				addEvent(tick, a.every or 1000, left - 1)
			end
		end
		addEvent(tick, a.every or 1000, a.ticks or 1)
	elseif a.t == "groundheal" then
		local function tick(left)
			local p = Player(pid)
			if p and left > 0 then
				try("sanctuary", withContext, p, serial, spellId, function()
					FE.sendFx(Position(a.pos.x, a.pos.y, a.pos.z), "holy", "ground")
					for _, ally in ipairs(alliesNear(p, a.pos, a.radius or 1)) do
						dealHeal(p, Creature(ally.id), a.amount)
					end
				end)
				addEvent(tick, a.every or 1000, left - 1)
			end
		end
		tick(a.seconds or 1)
	elseif a.t == "shield" then
		local c = Creature(a.id)
		if c and c:isPlayer() then
			addShield(c, a.amount)
		end
	elseif a.t == "cleanse" then
		local c = Creature(a.id)
		if c and c:isPlayer() then
			removeOneDebuff(c)
		end
	end
end

-- the cooldown of a spell shortened by a percent of its base (Second Wind), the way Quickening does it
local function shortenCooldown(player, spellId, pct)
	local info = R.catalog and R.catalog[spellId]
	local base = info and info.cooldownMs or 0
	if base <= 0 or not pct or pct <= 0 then
		return
	end
	local c = player:getCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, spellId)
	if c then
		local left = c:getTicks()
		local ticks = max(min(left, 1000), left - floor(base * pct / 100))
		if ticks < left then
			player:removeCondition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT, spellId, true)
			if ticks > 0 then
				local n = Condition(CONDITION_SPELLCOOLDOWN, CONDITIONID_DEFAULT)
				n:setParameter(CONDITION_PARAM_SUBID, spellId)
				n:setParameter(CONDITION_PARAM_TICKS, ticks)
				player:addCondition(n)
			end
		end
	end
end
FE.shortenCooldown = shortenCooldown

-- the helpers the awakening signature runs on (spell_awakening.lua, O686 phase 7): the same guard, cast context, hits and shield as a Form's
FE.ops = {guarded = guarded, withContext = withContext, dealHit = dealHit, dealHeal = dealHeal, addShield = addShield, foesNear = foesNear,
	alliesNear = alliesNear, copyPos = copyPos}

-- ---------------------------------------------------------------- the end of a cast
local function lineBehind(player, main, foes)
	local pp, mp = player:getPosition(), main.pos
	local dx = mp.x > pp.x and 1 or (mp.x < pp.x and -1 or 0)
	local dy = mp.y > pp.y and 1 or (mp.y < pp.y and -1 or 0)
	local out = {}
	if dx == 0 and dy == 0 then
		return out
	end
	for step = 1, 3 do
		local x, y = mp.x + dx * step, mp.y + dy * step
		for _, f in ipairs(foes) do
			if f.pos.x == x and f.pos.y == y and f.pos.z == mp.z and f.id ~= main.id then
				out[#out + 1] = f
			end
		end
	end
	return out
end

flush = function(pid)
	local b = buffers[pid]
	buffers[pid] = nil
	local player = Player(pid)
	if not b or not player or #b.hits == 0 then
		return
	end
	local specs = FE.active(player, b.spellId)
	if #specs == 0 then
		return
	end
	local entry = FE.entry(b.spellId)
	local heal = entry and entry.heal
	local main = b.hits[1]
	for _, h in ipairs(b.hits) do
		if h.orig > main.orig then
			main = h
		end
	end
	local pvp = (not heal) and main.player == true
	local hits = {}
	for _, h in ipairs(b.hits) do
		hits[#hits + 1] = {id = h.id, pos = h.pos, amount = h.orig, kill = h.kill, health = h.health, maxHealth = h.maxHealth,
			player = h.player, overheal = h.overheal}
	end
	local foes, allies = {}, {}
	if heal then
		allies = alliesNear(player, main.pos, 3)
	else
		foes = foesNear(player, main.pos, 3, pvp)
	end
	local mainCreature = Creature(main.id)
	local cast = {hits = hits, foes = foes, allies = allies, line = lineBehind(player, main, foes), pvp = pvp,
		pvpShare = cfg.pvp.forms, resist = resistFn(mainCreature)}
	local plan = F.planAll(specs, cast)
	local element = FE.conversion(specs, cast.resist) or (entry and entry.element) or nil
	local ctype = combatTypeOf(element) or main.ctype or COMBAT_PHYSICALDAMAGE
	try("run", withContext, player, b.serial, b.spellId, function()
		for _, a in ipairs(plan.actions) do
			try("action", runAction, player, b.serial, b.spellId, pvp, element, ctype, a)
		end
	end)
	if plan.cooldownCutPct then
		shortenCooldown(player, b.spellId, plan.cooldownCutPct)
	end
	-- O686 phase 7: the signature effect of an awakened spell (spell_awakening.lua), after the Forms, from the same hit buffer
	local AW = rawget(_G, "ChaosSpellAwakening")
	if AW and AW.onCast then
		try("awakening", AW.onCast, player, b, {heal = heal == true, pvp = pvp, hits = hits, element = element, ctype = ctype, mainId = main.id,
			mainPos = main.pos, allies = allies})
	end
end
FE.flush = flush

local function record(pid, spellId, serial, creature, hit)
	local b = buffers[pid]
	if not b or b.serial ~= serial then
		if b then
			flush(pid)
		end
		b = {spellId = spellId, serial = serial, hits = {}, index = {}}
		buffers[pid] = b
		addEvent(flush, 0, pid)
	end
	local cid = creature:getId()
	local i = b.index[cid]
	if i then
		local h = b.hits[i]
		h.orig = h.orig + hit.orig
		h.kill = h.kill or hit.kill
	else
		b.hits[#b.hits + 1] = hit
		b.index[cid] = #b.hits
	end
	return #b.hits == 1 and not i
end

-- ---------------------------------------------------------------- the damage event
local event = CreatureEvent("ChaosSpellFormsHit")
function event.onHealthChange(creature, attacker, pd, pt, sd, st, origin, critical)
	if not creature or not attacker or FE.depth > 0 or cfg.enabled ~= true or origin ~= ORIGIN_SPELL then
		return pd, pt, sd, st
	end
	if (S.depth or 0) > 0 then
		return pd, pt, sd, st
	end
	local K = rawget(_G, "ChaosKeystones")
	if K and (K.depth or 0) > 0 then
		return pd, pt, sd, st
	end
	if not attacker.isPlayer or not attacker:isPlayer() then
		return pd, pt, sd, st
	end
	local serial, spellId = S.ctxDecode(attacker:getStorageValue(S.config.storageContext))
	if not serial then
		return pd, pt, sd, st
	end
	local specs = FE.active(attacker, spellId)
	if #specs == 0 then
		return pd, pt, sd, st
	end
	local entry = FE.entry(spellId)
	local isHeal = pt == COMBAT_HEALING
	if (entry and entry.heal) ~= isHeal then
		return pd, pt, sd, st
	end
	if not isHeal and attacker:getId() == creature:getId() then
		return pd, pt, sd, st
	end
	local pvp = creature:isPlayer() and creature:getId() ~= attacker:getId() and not isHeal
	local amount = math.abs(pd) + math.abs(sd)
	local health = creature:getHealth()
	local maxHealth = creature:getMaxHealth()
	local hit = {id = creature:getId(), pos = copyPos(creature:getPosition()), orig = amount, kill = (not isHeal) and amount >= health,
		health = health, maxHealth = maxHealth, player = creature:isPlayer(), ctype = pt,
		overheal = isHeal and max(0, health + amount - maxHealth) or 0}
	local first = record(attacker:getId(), spellId, serial, creature, hit)
	-- the SEEK decision needs the enemies near the hit now
	local foes
	for _, spec in ipairs(specs) do
		if spec.kind == "SEEK" and not isHeal then
			foes = foesNear(attacker, hit.pos, 3, pvp)
		end
	end
	local f = F.hitFactor(specs, {id = hit.id, pos = hit.pos, amount = amount, health = health, maxHealth = maxHealth}, first, pvp,
		cfg.pvp.forms, foes)
	if f ~= 1 then
		pd, sd = floor(pd * f), floor(sd * f)
	end
	-- the element of a conversion, on a damage hit only
	if not isHeal then
		local el = FE.conversion(specs, resistFn(creature))
		local ct = combatTypeOf(el)
		if ct then
			pt = ct
			if sd ~= 0 then
				st = ct
			end
		end
	end
	return pd, pt, sd, st
end
event:register()

-- registered on what a player with a Form hits (after the supports and the passive tree: they see the hit first), and on every
-- player at login: heals land on allies
local function registerOnce(creature, name)
	local f = Chaos and Chaos.registerOnce
	if f then
		return f(creature, name)
	end
	creature:registerEvent(name)
	return true
end
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if cfg.enabled == true and creature and target and creature:isPlayer() and hasForms(creature) then
		registerOnce(target, "ChaosSpellFormsHit")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(2)

-- ---------------------------------------------------------------- the shield of Ward and Cleanse (absorbs damage a player takes)
local shieldEvent = CreatureEvent("ChaosSpellFormsShield")
function shieldEvent.onHealthChange(creature, attacker, pd, pt, sd, st, origin, critical)
	local s = creature and FE.shields[creature:getId()]
	if not s or pt == COMBAT_HEALING then
		return pd, pt, sd, st
	end
	if s.untilMs < nowMs() or s.amount <= 0 then
		FE.shields[creature:getId()] = nil
		return pd, pt, sd, st
	end
	local function absorb(v)
		if v >= 0 or s.amount <= 0 then
			return v
		end
		local take = min(s.amount, -v)
		s.amount = s.amount - take
		return v + take
	end
	pd = absorb(pd)
	sd = absorb(sd)
	return pd, pt, sd, st
end
shieldEvent:register()

local login = CreatureEvent("ChaosSpellFormsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSpellFormsHit")
	player:registerEvent("ChaosSpellFormsShield")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSpellFormsLogout")
function logout.onLogout(player)
	local id = player:getId()
	anyCache[id], FE.shields[id], buffers[id], ground[id] = nil, nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- the cooldown of a Twin cast
if ChaosSpellEvents and ChaosSpellEvents.set then
	ChaosSpellEvents.set("cooldown", "spellforms", function(player, name, id, group, aggressive, cooldownType, ms)
		if cfg.enabled == true and cooldownType == "spell" and FE.entry(id) then
			for _, spec in ipairs(FE.active(player, id)) do
				if spec.kind == "TWIN" then
					ms = ms + F.params("TWIN", spec.over).cd
				end
			end
		end
		return ms
	end)
end

-- ---------------------------------------------------------------- pick and change (opcode 168 `pick`)
local function forgetCache(player)
	anyCache[player:getId()] = nil
end

-- the picks of a character for the client: {[spell id] = {f1, f2}} for spells with a pick
function FE.picksOf(player)
	local list = {}
	local rows = FE.table()
	for id in pairs(rows) do
		local rank, f1, f2 = FE.state(player, id)
		if f1 > 0 or f2 > 0 then
			list[#list + 1] = {id, f1, f2}
		end
	end
	table.sort(list, function(a, b) return a[1] < b[1] end)
	return list
end

-- the answer of a pick: {ok, why, price, spell, tier, pick, f1, f2}
function FE.pick(player, spellId, tier, pick)
	spellId, tier, pick = tonumber(spellId), tonumber(tier), tonumber(pick)
	local entry = spellId and FE.entry(spellId)
	if cfg.enabled ~= true then
		return {ok = false, why = "off"}
	end
	if not entry or not tier or not pick or not entry[tier] or not entry[tier][pick] then
		return {ok = false, why = "spell"}
	end
	local rank, f1, f2 = FE.state(player, spellId)
	local k = cfg.storage
	local st = {rank = rank, f1 = f1, f2 = f2, level = player:getLevel(), spellId = spellId, now = os.time(),
		lastAt = player:getStorageValue(k.lastPickAt), lastWhat = player:getStorageValue(k.lastPickWhat)}
	local d = F.decide(st, tier, pick, cfg)
	if not d.ok or d.noop then
		d.spell, d.tier, d.pick, d.f1, d.f2 = spellId, tier, pick, f1, f2
		return d
	end
	if d.price > 0 then
		local bank = player.getBankBalance and player:getBankBalance() or 0
		local carried = player.getMoney and player:getMoney() or 0
		local split = F.split(d.price, bank, carried)
		if not split then
			return {ok = false, why = "gold", price = d.price}
		end
		-- the bank first, then the coins; all or nothing
		if split.fromBank > 0 then
			player:setBankBalance(bank - split.fromBank)
		end
		if split.fromCoins > 0 and not player:removeMoney(split.fromCoins) then
			player:setBankBalance(bank)
			return {ok = false, why = "gold", price = d.price}
		end
	end
	local packed = player:getStorageValue(k.rankBase + spellId)
	local rk, a, b, aw = ChaosSpellRanksCore.unpack(packed)
	if tier == 1 then
		a = pick
	else
		b = pick
	end
	player:setStorageValue(k.rankBase + spellId, ChaosSpellRanksCore.pack(rk, a, b, aw))
	if d.why == "paid" then
		local n = player:getStorageValue(k.formChanges)
		player:setStorageValue(k.formChanges, max(0, tonumber(n) or 0) + 1)
	end
	if d.why ~= "window" then
		player:setStorageValue(k.lastPickAt, os.time())
		player:setStorageValue(k.lastPickWhat, spellId * 10 + tier)
	end
	forgetCache(player)
	d.spell, d.tier, d.pick, d.f1, d.f2 = spellId, tier, pick, a, b
	return d
end

-- opcode 168 messages the Forms answer: pick {spell, tier, pick} -> pick {ok, why, price, spell, tier, pick, f1, f2}
function FE.receive(player, msg)
	if type(msg) ~= "table" or msg.action ~= "pick" then
		return false
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "spellforms", 500) then
		return false
	end
	local data = type(msg.data) == "table" and msg.data or msg
	local res = FE.pick(player, data.spell, data.tier, data.pick)
	Chaos.send(player, OPCODE, "pick", res)
	if res.ok and not res.noop then
		say(player, tr(player, "Form chosen."))
	end
	return true
end

return FE
