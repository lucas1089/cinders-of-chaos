-- passivetree_keystones.lua: what the passive tree keystones do (client nodes 621 "Wrath" and 624 "Resolve").
--
-- Every vocation gets its own keystone on the same two nodes (per-vocation customStats, `v` in passivetree_data.lua),
-- so the summed bonuses (ChaosPassiveCache, filled by passivetree.lua) carry one flag per allocated keystone:
--   knight       ksCleavingArc  two-handed melee hits also hit up to 3 other enemies next to the knight for 40%
--                ksBulwark      with a shield: 15% to block a melee/ranged attack fully, 30% of melee damage reflected
--   paladin      ksRicochet     bow/crossbow hits: 30% to bounce to the nearest other enemy (4 sqm) for 65%, then once
--                               more for 65% of that; never the same target twice
--                ksDeadeye      crossbow + bolts: 15% for a Deadeye shot, double damage
--   sorcerer     ksArcaneEcho   a spell that hits 2+ enemies: 35% to echo 0.6 s later on the same spots for 50%, 3 s cooldown
--                ksOverload     a spell hit of one element primes the others: the next spell of another element +20% (8 s)
--   druid        ksOvergrowth   heals on others also heal 30% of the heal again over 6 s (3 pulses)
--                ksThorns       melee/ranged attackers take 30% of their hit + 2 x magic level back as earth damage
--   illusionist  (support: makes the party hit harder, never the illusionist)
--                ksSharedPhantasm    the illusionist's hits mark the enemy for 6 s: other party members deal +12% to it
--                ksInspiringIllusion other party members within 8 sqm (same floor) deal +8% damage
--                Both need a party; multi-client characters neither give nor get them (Chaos.isMultiClient).
-- The numbers are in `cfg` below; the client tooltips (treedata/nodes.lua) repeat them and the unit test checks that.
--
-- Recursion: every extra hit (cleave, ricochet, echo, phantom, reflect, thorns, regrowth) is dealt from an addEvent
-- with ChaosKeystones.depth > 0 around doTargetCombat. All damage events run synchronously inside that call, so this
-- script and passivetree_effects.lua (no second round of passive bonuses) skip it; the extra hits use ORIGIN_SPELL,
-- which weapon_styles.lua ignores (no two-handed factor, no arrow splash). Extra hits never trigger keystones.
-- Targets: monsters that are not a player's summon; players only when ChaosSpell.canAttack allows it (PvP rules).
--
-- Event order: damage events run in the order they were registered on the creature, and every onTargetCombat callback
-- of the server has index 0 (their order among each other is not fixed). This one registers with index 1, so its
-- event comes after the passive tree's and weapon_styles.lua's on a target: it sees the hit with the passive bonuses
-- and the two-handed factor, and the cleave / ricochet share is taken of the hit the target really takes.
-- On players (hits taken, heals received) it is registered one tick after login, after the other login events.

ChaosKeystones = ChaosKeystones or {}
local K = ChaosKeystones
K.depth = K.depth or 0

local cfg = {
	cleave = {percent = 0.40, maxTargets = 3},
	bulwark = {blockChance = 15, reflectPercent = 0.30},
	ricochet = {chance = 30, percent = 0.65, falloff = 0.65, bounces = 2, range = 4, delay = 120},
	deadeye = {chance = 15, multiplier = 2.0},
	echo = {chance = 35, percent = 0.50, delay = 600, cooldown = 3000, minTargets = 2},
	overload = {bonus = 0.20, window = 8000, castWindow = 150},
	overgrowth = {percent = 0.30, pulses = 3, interval = 2000},
	thorns = {percent = 0.30, perMagicLevel = 2},
	phantasm = {bonus = 0.12, duration = 6000},
	inspire = {bonus = 0.08, range = 8},
}
K.cfg = cfg

-- ---------------------------------------------------------------- pure logic (unit tested)
local function rnd(a, b)
	return math.random(a, b)
end

-- chance in percent (0..100)
function K.roll(chance, random)
	return chance > 0 and (random or rnd)(1, 100) <= chance
end

-- scale a damage value keeping its sign, rounding toward zero
function K.scale(v, m)
	local a = math.floor(math.abs(v * m) + 1e-6)
	return v < 0 and -a or a
end

-- tiles between two positions (king moves); different floors are out of reach
function K.distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- cleave victims: candidates {id =, pos =} next to `center`, not the main target, lowest ids first, at most max
function K.cleavePick(candidates, center, mainId, max)
	local list = {}
	for _, c in ipairs(candidates) do
		if c.id ~= mainId and K.distance(c.pos, center) <= 1 then
			list[#list + 1] = c
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	for i = #list, max + 1, -1 do
		list[i] = nil
	end
	return list
end

-- nearest candidate within range that was not hit yet (ties: lowest id)
function K.pickNearest(from, candidates, visited, range)
	local best, bestDist
	for _, c in ipairs(candidates) do
		local d = K.distance(from, c.pos)
		if not visited[c.id] and d <= range and (not best or d < bestDist or (d == bestDist and c.id < best.id)) then
			best, bestDist = c, d
		end
	end
	return best
end

-- ricochet chain from the first target: {{id, from, to, amount}, ...}. candidatesAt(pos) lists {id, pos} around pos.
function K.planRicochet(startPos, startId, base, candidatesAt, c)
	c = c or cfg.ricochet
	local steps, visited, from, amount = {}, {[startId] = true}, startPos, base * c.percent
	for _ = 1, c.bounces do
		local nextTarget = K.pickNearest(from, candidatesAt(from), visited, c.range)
		if not nextTarget or math.floor(amount) <= 0 then
			break
		end
		visited[nextTarget.id] = true
		steps[#steps + 1] = {id = nextTarget.id, from = from, to = nextTarget.pos, amount = math.floor(amount)}
		from, amount = nextTarget.pos, amount * c.falloff
	end
	return steps
end

-- internal cooldowns: state[key] = time the cooldown ends
function K.ready(state, key, now)
	return (state[key] or 0) <= now
end

function K.startCooldown(state, key, now, ms)
	state[key] = now + ms
end

-- Arcane Echo: does this cast (targets = enemies it hit) echo? Starts the cooldown when it does.
function K.echoDecide(state, now, targets, random)
	local c = cfg.echo
	if targets < c.minTargets or not K.ready(state, "echo", now) or not K.roll(c.chance, random) then
		return false
	end
	K.startCooldown(state, "echo", now, c.cooldown)
	return true
end

-- Elemental Overload: damage multiplier for a spell hit of `element` at `now`; keeps the primed element in state.
-- A cast is all hits within castWindow ms of its first boosted hit (an area spell hits every target at once).
function K.overloadStep(state, element, now)
	local c = cfg.overload
	if state.boostAt and now - state.boostAt <= c.castWindow and state.boostElement == element then
		return 1 + c.bonus
	end
	local m = 1
	if state.primed and state.primed ~= element and now <= (state.primedUntil or 0) then
		m = 1 + c.bonus
		state.boostAt, state.boostElement = now, element
	end
	state.primed, state.primedUntil = element, now + c.window
	return m
end

function K.thornsAmount(damage, magicLevel)
	return math.floor(math.abs(damage) * cfg.thorns.percent + (magicLevel or 0) * cfg.thorns.perMagicLevel)
end

function K.overgrowthPulse(heal)
	return math.floor(math.abs(heal) * cfg.overgrowth.percent / cfg.overgrowth.pulses)
end

-- party key: the leader's id (members of one party share it), nil without a party
function K.partyKey(party)
	local leader = party and party:getLeader()
	return leader and leader:getId() or nil
end

-- Illusionist support bonus for a hit by a party member (all plain data, unit tested):
--   hit = {attackerId, party (partyKey), pos, now, multiClient}
--   mark = Shared Phantasm mark on the target {owner, party, untilTime} or nil
--   givers = party members with Inspiring Illusion {{id, pos, multiClient}, ...}
-- Returns the damage multiplier; one Shared Phantasm and one Inspiring Illusion at most (no stacking).
function K.partyMultiplier(hit, mark, givers)
	if not hit.party or hit.multiClient then
		return 1
	end
	local m = 1
	if mark and mark.party == hit.party and mark.owner ~= hit.attackerId and hit.now <= mark.untilTime
			and not mark.multiClient then
		m = m + cfg.phantasm.bonus
	end
	for _, g in ipairs(givers or {}) do
		if g.id ~= hit.attackerId and not g.multiClient and K.distance(g.pos, hit.pos) <= cfg.inspire.range then
			m = m + cfg.inspire.bonus
			break
		end
	end
	return m
end

function K.hasKeystone(bonuses)
	if bonuses then
		for key in pairs(bonuses) do
			if key:sub(1, 2) == "ks" then
				return true
			end
		end
	end
	return false
end

-- ---------------------------------------------------------------- engine side
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua") -- canAttack / isEnemy (PvP rules), chaos_fx effect ids
end

local function fx(name, fallback)
	if Fx then
		return Fx(name, fallback)
	end
	return fallback
end

-- combat_fx.lua (crit / dodge / reflect visuals) when it is loaded; throttled there and safe with nil
local function combatFx(kind, arg)
	if ChaosCombatFx and ChaosCombatFx[kind] then
		pcall(ChaosCombatFx[kind], arg)
	end
end

local ELEMENTS = {}
for _, t in ipairs({COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE, COMBAT_ENERGYDAMAGE, COMBAT_EARTHDAMAGE, COMBAT_DEATHDAMAGE,
		COMBAT_HOLYDAMAGE, COMBAT_DROWNDAMAGE, COMBAT_WATERDAMAGE, COMBAT_ARCANEDAMAGE}) do
	ELEMENTS[t] = true
end

local state = {} -- per player id: cooldowns, overload, effect throttles
local function stateOf(id)
	local s = state[id]
	if not s then
		s = {}
		state[id] = s
	end
	return s
end

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function copyPos(p)
	return {x = p.x, y = p.y, z = p.z}
end

-- weapon in the hands (not a shield, not ammunition), like weapon_styles.lua
local function handWeapon(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item then
			local it = ItemType(item:getId())
			local wt = it:getWeaponType()
			if wt ~= WEAPON_NONE and wt ~= WEAPON_SHIELD and wt ~= WEAPON_AMMO then
				return it
			end
		end
	end
	return nil
end

local function hasShield(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		if item and ItemType(item:getId()):getWeaponType() == WEAPON_SHIELD then
			return true
		end
	end
	return false
end

local function isTwoHanded(it)
	return bit.band(it:getSlotPosition(), SLOTP_TWO_HAND) ~= 0
end

local MELEE_WEAPON = {[WEAPON_SWORD] = true, [WEAPON_CLUB] = true, [WEAPON_AXE] = true}

local function shootsBolts(player, weapon)
	if weapon:getWeaponType() ~= WEAPON_DISTANCE or weapon:getAmmoType() ~= AMMO_BOLT then
		return false
	end
	local ammo = player:getSlotItem(CONST_SLOT_AMMO)
	return ammo ~= nil and ItemType(ammo:getId()):getAmmoType() == AMMO_BOLT
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

local function candidatesAround(attacker, pos, radius, needSight)
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

-- run fn with the proc guard up: every damage event inside sees ChaosKeystones.depth > 0
local function guarded(fn, ...)
	K.depth = K.depth + 1
	local ok, err = pcall(fn, ...)
	K.depth = K.depth - 1
	if not ok then
		print("[ChaosKeystones] " .. tostring(err))
	end
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

-- ---- knight: Cleaving Arc
local function cleave(pid, mainId, amount, ctype)
	local p = Player(pid)
	if not p then
		return
	end
	local center = p:getPosition()
	for _, v in ipairs(K.cleavePick(candidatesAround(p, center, 1, false), center, mainId, cfg.cleave.maxTargets)) do
		procDamage(p, Creature(v.id), ctype, amount, fx("blood_slash", CONST_ME_HITAREA))
	end
end

-- ---- paladin: Ricochet
local function ricochet(pid, mainId, startPos, base, ctype, missile)
	local p = Player(pid)
	if not p then
		return
	end
	local steps = K.planRicochet(startPos, mainId, base, function(pos)
		return candidatesAround(p, pos, cfg.ricochet.range, true)
	end)
	for i, step in ipairs(steps) do
		addEvent(function()
			local a = Player(pid)
			local target = Creature(step.id)
			if a and target and validTarget(a, target) then
				Position(step.from.x, step.from.y, step.from.z):sendDistanceEffect(target:getPosition(), missile)
				procDamage(a, target, ctype, step.amount, CONST_ME_HITAREA)
			end
		end, (i - 1) * cfg.ricochet.delay)
	end
end

-- ---- sorcerer: Arcane Echo (hits of one cast are collected until the end of the server tick)
local echoBuffer = {}
local function runEcho(pid, hits)
	local p = Player(pid)
	if not p then
		return
	end
	for _, h in ipairs(hits) do
		local pos = Position(h.pos.x, h.pos.y, h.pos.z)
		pos:sendMagicEffect(fx("arcane_burst", CONST_ME_ENERGYAREA))
		local c = Creature(h.id)
		if c and validTarget(p, c) and K.distance(c:getPosition(), h.pos) <= 1 then
			procDamage(p, c, h.type, h.amount * cfg.echo.percent, CONST_ME_NONE)
		end
	end
end

local function flushEcho(pid)
	local buffer = echoBuffer[pid]
	echoBuffer[pid] = nil
	if buffer and Player(pid) and K.echoDecide(stateOf(pid), now(), #buffer.hits) then
		addEvent(runEcho, cfg.echo.delay, pid, buffer.hits)
	end
end

local function recordEcho(pid, creature, amount, ctype)
	local buffer = echoBuffer[pid]
	if not buffer then
		buffer = {hits = {}, index = {}}
		echoBuffer[pid] = buffer
		addEvent(flushEcho, 0, pid)
	end
	local cid = creature:getId()
	local i = buffer.index[cid]
	if i then
		buffer.hits[i].amount = buffer.hits[i].amount + amount
	else
		buffer.hits[#buffer.hits + 1] = {id = cid, pos = copyPos(creature:getPosition()), amount = amount, type = ctype}
		buffer.index[cid] = #buffer.hits
	end
end

-- ---- illusionist: Shared Phantasm marks (target id -> mark) and Inspiring Illusion givers
local marks, markCount = {}, 0
local function isMultiClient(player)
	return Chaos and Chaos.isMultiClient and Chaos.isMultiClient(player) or false
end

local function setMark(player, party, target)
	local id, t = target:getId(), now()
	local old = marks[id]
	if not old or old.untilTime < t or old.owner ~= player:getId() then
		target:getPosition():sendMagicEffect(fx("arcane_circle", CONST_ME_PURPLEENERGY))
	end
	marks[id] = {owner = player:getId(), party = K.partyKey(party), untilTime = t + cfg.phantasm.duration,
		multiClient = isMultiClient(player)}
	markCount = markCount + 1
	if markCount > 200 then -- forget marks of dead or old targets now and then
		markCount = 0
		for mid, m in pairs(marks) do
			if m.untilTime < t or not Creature(mid) then
				marks[mid] = nil
			end
		end
	end
end

local function partyBonus(attacker, creature, pd, sd)
	local party = attacker:getParty()
	if not party then
		return pd, sd
	end
	local givers = {}
	local members = party:getMembers() or {}
	members[#members + 1] = party:getLeader()
	for _, member in ipairs(members) do
		local b = member and ChaosPassiveCache[member:getId()]
		if b and b.ksInspiringIllusion then
			givers[#givers + 1] = {id = member:getId(), pos = copyPos(member:getPosition()), multiClient = isMultiClient(member)}
		end
	end
	local mark = marks[creature:getId()]
	if not mark and #givers == 0 then
		return pd, sd
	end
	local m = K.partyMultiplier({attackerId = attacker:getId(), party = K.partyKey(party), pos = copyPos(attacker:getPosition()),
		now = now(), multiClient = isMultiClient(attacker)}, mark, givers)
	if m ~= 1 then
		pd, sd = K.scale(pd, m), K.scale(sd, m)
	end
	return pd, sd
end

-- ---- druid: Overgrowth
local regrowth = {} -- target id -> token of the running regrowth (a new heal replaces it)
local regrowthToken = 0
local function startRegrowth(healerId, targetId, pulse)
	regrowthToken = regrowthToken + 1
	local token = regrowthToken
	regrowth[targetId] = token
	local target = Creature(targetId)
	if target then
		target:getPosition():sendMagicEffect(CONST_ME_SMALLPLANTS)
	end
	for i = 1, cfg.overgrowth.pulses do
		addEvent(function()
			if regrowth[targetId] ~= token then
				return
			end
			if i == cfg.overgrowth.pulses then
				regrowth[targetId] = nil
			end
			local t = Creature(targetId)
			if t and t:getHealth() > 0 then
				local healer = Player(healerId)
				guarded(doTargetCombat, healer or 0, t, COMBAT_HEALING, pulse, pulse, fx("heal_sparkle", CONST_ME_MAGIC_GREEN),
					ORIGIN_SPELL)
			end
		end, i * cfg.overgrowth.interval)
	end
end

-- ---- reflected damage (Bulwark, Thorns)
local function reflect(ownerId, attackerId, ctype, amount, missile, effect)
	local owner, attacker = Player(ownerId), Creature(attackerId)
	if owner and attacker and validTarget(owner, attacker) then
		if missile then
			owner:getPosition():sendDistanceEffect(attacker:getPosition(), missile)
		end
		procDamage(owner, attacker, ctype, amount, effect)
	end
end

-- keystones of the creature that is hit (it is a player)
local function defend(player, b, attacker, pd, pt, sd, st, origin)
	if origin ~= ORIGIN_MELEE and origin ~= ORIGIN_RANGED then
		return pd, sd
	end
	local total = math.abs(pd) + math.abs(sd)
	if b.ksBulwark and hasShield(player) then
		if K.roll(cfg.bulwark.blockChance) then
			player:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
			combatFx("dodge", player)
			return 0, 0
		end
		if origin == ORIGIN_MELEE then
			combatFx("reflect", player)
			addEvent(reflect, 0, player:getId(), attacker:getId(), COMBAT_PHYSICALDAMAGE, total * cfg.bulwark.reflectPercent,
				nil, fx("shockwave", CONST_ME_EXPLOSIONHIT))
		end
	end
	if b.ksThorns then
		combatFx("reflect", player)
		addEvent(reflect, 0, player:getId(), attacker:getId(), COMBAT_EARTHDAMAGE, K.thornsAmount(total, player:getMagicLevel()),
			CONST_ANI_SMALLEARTH, CONST_ME_PLANTATTACK)
	end
	return pd, sd
end

-- keystones of the player who hits
local function attack(player, b, creature, pd, pt, sd, st, origin)
	local pid = player:getId()
	if origin == ORIGIN_CONDITION then
		return pd, sd
	end
	if b.ksSharedPhantasm then
		local party = player:getParty()
		if party then
			setMark(player, party, creature)
		end
	end

	if origin == ORIGIN_MELEE or origin == ORIGIN_RANGED then
		if not (b.ksCleavingArc or b.ksRicochet or b.ksDeadeye) then
			return pd, sd
		end
		local weapon = handWeapon(player)
		if not weapon then
			return pd, sd
		end
		if b.ksDeadeye and origin == ORIGIN_RANGED and shootsBolts(player, weapon) and K.roll(cfg.deadeye.chance) then
			pd, sd = K.scale(pd, cfg.deadeye.multiplier), K.scale(sd, cfg.deadeye.multiplier)
			creature:getPosition():sendMagicEffect(fx("holy_cross", CONST_ME_HOLYDAMAGE))
			combatFx("crit", creature:getPosition())
		end
		local base = math.abs(pd) + math.abs(sd)
		if b.ksCleavingArc and origin == ORIGIN_MELEE and isTwoHanded(weapon) and MELEE_WEAPON[weapon:getWeaponType()] then
			addEvent(cleave, 0, pid, creature:getId(), base * cfg.cleave.percent, procType(pt))
		end
		if b.ksRicochet and origin == ORIGIN_RANGED and weapon:getWeaponType() == WEAPON_DISTANCE
				and K.roll(cfg.ricochet.chance) then
			local missile = weapon:getAmmoType() == AMMO_BOLT and CONST_ANI_BOLT or CONST_ANI_ARROW
			addEvent(ricochet, 0, pid, creature:getId(), copyPos(creature:getPosition()), base, procType(pt), missile)
		end
		return pd, sd
	end

	if origin == ORIGIN_SPELL then
		if b.ksOverload and ELEMENTS[pt] then
			local m = K.overloadStep(stateOf(pid), pt, now())
			if m ~= 1 then
				pd, sd = K.scale(pd, m), K.scale(sd, m)
				local s = stateOf(pid)
				if s.boostFxAt ~= s.boostAt then
					s.boostFxAt = s.boostAt
					player:getPosition():sendMagicEffect(fx("arcane_circle", CONST_ME_MAGIC_BLUE))
				end
			end
		end
		local amount = math.abs(pd) + math.abs(sd)
		if b.ksArcaneEcho then
			recordEcho(pid, creature, amount, procType(pt))
		end
	end
	return pd, sd
end

local event = CreatureEvent("ChaosKeystones")
function event.onHealthChange(creature, attacker, pd, pt, sd, st, origin)
	if K.depth > 0 or not attacker or not creature then
		return pd, pt, sd, st
	end
	local selfHit = attacker:getId() == creature:getId()
	if pt == COMBAT_HEALING then
		local b = attacker:isPlayer() and ChaosPassiveCache[attacker:getId()]
		if b and b.ksOvergrowth and not selfHit and creature:isPlayer() and origin ~= ORIGIN_CONDITION then
			local pulse = K.overgrowthPulse(math.abs(pd) + math.abs(sd))
			if pulse > 0 then
				startRegrowth(attacker:getId(), creature:getId(), pulse)
			end
		end
		return pd, pt, sd, st
	end
	if selfHit then
		return pd, pt, sd, st
	end
	if creature:isPlayer() then
		local b = ChaosPassiveCache[creature:getId()]
		if b and (b.ksBulwark or b.ksThorns) then
			pd, sd = defend(creature, b, attacker, pd, pt, sd, st, origin)
			if pd == 0 and sd == 0 then
				return pd, pt, sd, st
			end
		end
	end
	if attacker:isPlayer() then
		local b = ChaosPassiveCache[attacker:getId()]
		if b and K.hasKeystone(b) then
			pd, sd = attack(attacker, b, creature, pd, pt, sd, st, origin)
		end
		if origin ~= ORIGIN_CONDITION then -- illusionist support of the attacker's party
			pd, sd = partyBonus(attacker, creature, pd, sd)
		end
	end
	return pd, pt, sd, st
end
event:register()

-- the event sits on whatever a player attacks (keystones, and the party bonus of an illusionist in the party),
-- and on every player (hits taken, heals received);
-- index 1: after the index 0 callbacks that register the passive tree and weapon style events (see the top)
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() then
		target:registerEvent("ChaosKeystones")
	end
	return RETURNVALUE_NOERROR
end
targetCb:register(1)

local login = CreatureEvent("ChaosKeystonesLogin")
function login.onLogin(player)
	local pid = player:getId()
	addEvent(function() -- after every other login event has registered its own
		local p = Player(pid)
		if p then
			p:registerEvent("ChaosKeystones")
		end
	end, 0)
	return true
end
login:register()

local logout = CreatureEvent("ChaosKeystonesLogout")
function logout.onLogout(player)
	state[player:getId()] = nil
	echoBuffer[player:getId()] = nil
	return true
end
logout:register()
