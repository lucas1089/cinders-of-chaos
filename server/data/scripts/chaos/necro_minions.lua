-- necro_minions.lua: the Necromancer line's minions (docs/CLASSES.md "Necromancer"; numbers in necro_config.lua,
-- rules in necro_core.lua, engine helpers in necro_lib.lua).
--
-- Minions are raised by the spells (Raise Dead, Bone Golem, Raise Bone Warrior / Mage) as the player's summons: the engine makes them follow
-- the owner and go for the owner's target. This file does the rest, every Chaos minions.thinkMs:
--   * Hits: the monster types have no attacks of their own. A minion that reaches the owner's target (or its own)
--     hits it every intervalMs, and the hit is dealt as the owner (doTargetCombat with the owner as attacker), so it
--     counts for the owner like the owner's own damage: full experience (the engine would give a summon's share at
--     half), the Chaos loot layer and rarity rolls (the engine skips them when a summon lands the last hit), corpse
--     ownership, bounties, leaderboards, hunt tracker, curses. PvP rules: ChaosSpell.canAttack.
--     Bone Lord skeletons splash a share of each hit onto the other enemies next to the target; the Bone Golem slams
--     every enemy next to it and taunts the monsters around it, and so does the summoned Risen Warrior.
--   * Spells: every kind has a single target spell and an area spell (necro_config.lua minionSpells); a ready one is
--     cast in place of the hit.
--   * Banner of Bones (owner condition): minions hit harder, take less damage (the guard below) and regenerate.
--   * Leash: a minion farther than leashRange from its owner or on another floor is brought next to it.
--   * Protection zones: monsters cannot enter them, so a minion would stand in the way at the door. When the owner
--     stands in a protection zone its minions are put to rest (removed, kind and health kept); they rise next to it
--     when it steps out (within restKeepSeconds).
--   * Caps: minions over the class's cap or of a kind the class does not raise (vocation change, level loss) are
--     dismissed. The total cap (all kinds together; necro_config.lua minions.classes[].total) is enforced when a minion is
--     raised (necro_lib.lua M.raise: the oldest goes first) and here as a safety net.
--   * Logout and death: the engine removes summons with their owner; the rest and the timers are forgotten.
-- The minions' own guard: the owner's hits and those of its other summons do not hurt them (area spells).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosNecro then
	dofile("data/scripts/chaos/necro_lib.lua")
end
local L = ChaosNecro
local N = ChaosNecroCore
local function cfg()
	return ChaosNecroConfig
end

ChaosNecroMinions = ChaosNecroMinions or {}
local M = ChaosNecroMinions
M.nextHit = M.nextHit or {} -- minion id -> os.mtime of its next hit
M.nextTaunt = M.nextTaunt or {} -- golem / warrior id -> os.mtime of its next taunt
M.spellAt = M.spellAt or {} -- minion id -> {single = ms, area = ms}: when each spell is ready again
M.lastFight = M.lastFight or {} -- player id -> os.mtime a monster last hit one of its minions (regeneration, O160)
M.nextRegen = M.nextRegen or {} -- player id -> os.mtime of the next Banner of Bones regeneration
M.rest = M.rest or {} -- player id -> {at, list = {{kind, ratio}}} (necro_core restPut / restTake)

local now = os.mtime or function() return os.time() * 1000 end

local function inPz(creature)
	local tile = Tile(creature:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function info(creature)
	if not creature or creature:isRemoved() then
		return nil
	end
	return {id = creature:getId(), pos = creature:getPosition(), alive = creature:getHealth() > 0, creature = creature}
end

-- dismiss every minion of a player (vocation change away from the line, death)
function M.dismissAll(player)
	for _, m in ipairs(L.minions(player)) do
		M.nextHit[m.creature:getId()] = nil
		L.dismiss(m.creature)
	end
	M.rest[player:getId()] = nil
end

-- after a vocation change (ascension.lua / shop_services.lua call it when present): a character that left the
-- line loses its minions; the think below trims the rest to the new class's caps
function M.onVocationChange(player)
	if not L.classOf(player) then
		M.dismissAll(player)
	end
end

local function restAll(player, list)
	local rested = {}
	for _, m in ipairs(list) do
		local c = m.creature
		rested[#rested + 1] = {kind = m.kind, ratio = c:getHealth() / math.max(1, c:getMaxHealth())}
		M.nextHit[c:getId()] = nil
		c:getPosition():sendMagicEffect(CONST_ME_POFF)
		c:remove()
	end
	N.restPut(M.rest, player:getId(), os.time(), rested)
	if #rested > 0 then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, Chaos.t(player, "Your minions rest until you leave the protection zone."))
	end
end

local function wake(player, classKey)
	local list = N.restTake(cfg(), M.rest, player:getId(), os.time())
	if not list then
		return
	end
	list = N.restFilter(cfg(), classKey, player:getLevel(), list, L.capBonus(player))
	local pos = player:getPosition()
	for _, m in ipairs(list) do
		L.raise(player, m.kind, pos, m.ratio)
	end
end

-- one hit of a minion on `target`, dealt as the owner. ORIGIN_SPELL, not ORIGIN_NONE: the engine runs no
-- onHealthChange event for ORIGIN_NONE damage (Game::combatChangeHealth), so the curse, the item modifiers and every
-- other damage rule never saw a minion hit (found in game: no onHealthChange event saw them)
local function hit(owner, classKey, minion, kind, target, aura)
	local level, ml = owner:getLevel(), owner:getMagicLevel()
	local min, max = N.minionHit(cfg(), classKey, kind, level, ml, L.hitBonus(owner, aura),
		L.minionFactor(owner, kind, "hit"))
	if max <= 0 then
		return
	end
	local k = cfg().minions[kind]
	local ctype = L.combatType(k.combat)
	local mpos = minion:getPosition()
	if k.slam then
		-- the golem: every enemy next to it
		mpos:sendMagicEffect(Fx("ground_slam", CONST_ME_GROUNDSHAKER))
		for _, e in ipairs(L.enemiesAround(owner, mpos, 1, true)) do
			L.damage(owner, e, ctype, min, max, CONST_ME_HITAREA, ORIGIN_SPELL)
		end
		return
	end
	if k.range > 1 then
		-- the shade's skull orb; the mage's energy bolt (config `ani`, no Chaos missile)
		local ani = k.ani and L.animation(k) or FxMissile("skull_orb", CONST_ANI_DEATH)
		mpos:sendDistanceEffect(target:getPosition(), ani)
	end
	local effect = L.hitEffect(k)
	local tpos = target:getPosition()
	local dealt = L.damage(owner, target, ctype, min, max, effect, ORIGIN_SPELL)
	local share = N.splashShare(cfg(), classKey, kind)
	if share > 0 and dealt > 0 then
		for _, e in ipairs(L.enemiesAround(owner, tpos, 1, false)) do
			if e ~= target then
				local v = math.max(1, math.floor(dealt * share))
				-- a share of a hit that had the passive tree's bonuses already: guarded like the keystone procs
				local K = ChaosKeystones
				if K then K.depth = (K.depth or 0) + 1 end
				pcall(L.damage, owner, e, ctype, v, v, CONST_ME_BLOCKHIT, ORIGIN_SPELL)
				if K then K.depth = K.depth - 1 end
			end
		end
	end
end

-- a minion spell (necro_config.lua minionSpells[kind][which]) on `target`, dealt as the owner
local function cast(owner, classKey, minion, kind, target, aura, which)
	local level, ml = owner:getLevel(), owner:getMagicLevel()
	local min, max = N.minionHit(cfg(), classKey, kind, level, ml, L.hitBonus(owner, aura),
		L.minionFactor(owner, kind, "hit"))
	if max <= 0 then
		return
	end
	min, max = N.minionSpellHit(cfg(), kind, which, min, max)
	local k = cfg().minions[kind]
	local s = cfg().minionSpells[kind][which]
	local ctype = L.combatType(k.combat)
	local effect = L.hitEffect({hitEffect = s.hitEffect, combat = k.combat})
	local mpos, tpos = minion:getPosition(), target:getPosition()
	if which == "single" then
		if s.ani then
			mpos:sendDistanceEffect(tpos, L.animation(s))
		end
		L.damage(owner, target, ctype, min, max, effect, ORIGIN_SPELL)
		return
	end
	local center = s.center == "target" and tpos or mpos
	if s.ani and center ~= mpos then
		mpos:sendDistanceEffect(center, L.animation(s))
	end
	local area = L.effect(s.areaEffect)
	if area then
		for dx = -s.radius, s.radius do
			for dy = -s.radius, s.radius do
				Position(center.x + dx, center.y + dy, center.z):sendMagicEffect(area)
			end
		end
	end
	for _, e in ipairs(L.enemiesAround(owner, center, s.radius, false)) do
		L.damage(owner, e, ctype, min, max, effect, ORIGIN_SPELL)
	end
end

-- the minion's action when its hit is due: a ready spell (the area one when enough enemies stand in it) or the hit
local function act(owner, classKey, minion, kind, target, aura, t)
	local spells = cfg().minionSpells and cfg().minionSpells[kind]
	if spells then
		local id = minion:getId()
		local timers = M.spellAt[id] or {}
		local near = 0
		if spells.area and (timers.area or 0) <= t then
			local center = spells.area.center == "target" and target:getPosition() or minion:getPosition()
			near = #L.enemiesAround(owner, center, spells.area.radius, false)
		end
		local which = N.minionSpell(cfg(), kind, t, timers, near)
		if which then
			timers[which] = t + spells[which].cooldownMs
			M.spellAt[id] = timers
			return cast(owner, classKey, minion, kind, target, aura, which)
		end
	end
	return hit(owner, classKey, minion, kind, target, aura)
end

-- the golem's and the summoned warrior's taunt (Bone Challenge): the monsters within tauntRadius turn on the minion.
-- Returns false when no monster stands in reach (nothing shown, the taunt stays ready).
local function taunt(owner, minion, kind)
	local mpos = minion:getPosition()
	local r = cfg().minions[kind].tauntRadius or 1
	local turned = false
	for _, e in ipairs(L.enemiesAround(owner, mpos, r, false)) do
		if e:isMonster() then
			turned = true
			if e:getTarget() ~= minion then
				e:selectTarget(minion)
			end
		end
	end
	if turned then
		-- a red flash on the minion, the war cry on each monster it pulled (only a sound effect before: not seen, O346)
		mpos:sendMagicEffect(CONST_ME_MAGIC_RED)
		mpos:sendMagicEffect(CONST_ME_SOUND_RED)
	end
	return turned
end

-- the enemies within `range` of a minion as N.minionTarget's `nearby`
local function nearbyInfo(owner, pos, range)
	local out = {}
	for _, e in ipairs(L.enemiesAround(owner, pos, range, false)) do
		out[#out + 1] = info(e)
	end
	return out
end

local function think(player, t)
	local classKey = L.classOf(player)
	local list = L.minions(player)
	if not classKey then
		if #list > 0 then
			M.dismissAll(player)
		end
		return
	end
	if inPz(player) then
		if #list > 0 then
			restAll(player, list)
		end
		return
	end
	if M.rest[player:getId()] then
		wake(player, classKey)
		list = L.minions(player)
	end
	-- caps (vocation change, level loss)
	for _, i in ipairs(N.overCap(cfg(), classKey, player:getLevel(), list, L.capBonus(player))) do
		M.nextHit[list[i].creature:getId()] = nil
		L.dismiss(list[i].creature)
		table.remove(list, i)
	end
	if #list == 0 then
		return
	end
	local aura = L.hasCond(player, cfg().subId.boneAura)
	local regen = false
	if aura and (M.nextRegen[player:getId()] or 0) <= t then
		M.nextRegen[player:getId()] = t + 1000
		regen = true
	end
	local opos = player:getPosition()
	local ownerTarget = info(player:getTarget())
	-- regeneration (O160): idle once no monster hit a minion for a while and the owner has no target
	local sinceHit = M.lastFight[player:getId()] and (t - M.lastFight[player:getId()]) or nil
	local idle = not ownerTarget and N.minionIdle(cfg(), sinceHit)
	local healSec = cfg().minions.regen and 1 or 0
	for _, m in ipairs(list) do
		local c, kind = m.creature, m.kind
		local id = c:getId()
		local cpos = c:getPosition()
		if N.leash(cfg(), cpos, opos) == "teleport" then
			local spot = L.spotAt(opos, opos)
			if spot then
				c:teleportTo(spot, true)
				cpos = spot
			end
		end
		-- the shown level and the maximum health follow the owner (level up, magic level, passive tree)
		L.refresh(player, classKey, c, kind)
		if regen then
			Chaos.heal(c, math.floor(c:getMaxHealth() * cfg().bannerOfBones.regen))
		end
		if healSec > 0 then
			Chaos.heal(c, N.minionRegen(cfg(), c:getMaxHealth(), idle, cfg().minions.thinkMs))
		end
		local k = cfg().minions[kind]
		-- the taunt fires whenever monsters stand in reach, the owner's target or not (O346)
		if k.tauntMs and (M.nextTaunt[id] or 0) <= t and taunt(player, c, kind) then
			M.nextTaunt[id] = t + k.tauntMs
		end
		if M.nextHit[id] == nil then
			-- a freshly raised minion: its first hit comes after the class's first strike delay
			M.nextHit[id] = t + N.firstStrike(cfg(), classKey)
		end
		if (M.nextHit[id] or 0) <= t then
			local target = N.minionTarget(cpos, k.range, ownerTarget, info(c:getTarget()), nearbyInfo(player, cpos, k.range))
			if target and target.creature ~= c and not (target.creature:getMaster() == player) then
				M.nextHit[id] = t + k.intervalMs
				-- a minion's hit is no spell of the class's damage model: the class spell factor stays off
				-- (spell_factor_core.lua)
				local SF = ChaosSpellFactor
				if SF then
					SF.depth = (SF.depth or 0) + 1
				end
				local ok, err = pcall(act, player, classKey, c, kind, target.creature, aura, t)
				if SF then
					SF.depth = SF.depth - 1
				end
				if not ok then
					print("[ChaosNecro] minion hit: " .. tostring(err))
				end
			end
		end
	end
end

-- the minions' guard: no damage from their owner or its other summons; Banner of Bones reduces what they take
local guard = CreatureEvent("ChaosNecroMinionGuard")
function guard.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local owner = creature:getMaster()
	if not owner or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if attacker and (attacker == owner or attacker:getMaster() == owner) then
		return 0, primaryType, 0, secondaryType
	end
	-- a monster hits a minion as it would hit the owner (O160): x its pace damage curve; a summon of a player is no monster here
	if attacker and attacker:isMonster() and not attacker:getMaster() and owner:isPlayer() then
		local pm = ChaosPace and ChaosPace.damageMultOf and ChaosPace.damageMultOf(attacker) or 1
		primaryDamage = N.minionTaken(cfg(), primaryDamage, pm)
		secondaryDamage = N.minionTaken(cfg(), secondaryDamage, pm)
		M.lastFight[owner:getId()] = now()
	end
	if owner:isPlayer() and L.hasCond(owner, cfg().subId.boneAura) then
		primaryDamage = N.minionDamageTaken(cfg(), primaryDamage, true)
		secondaryDamage = N.minionDamageTaken(cfg(), secondaryDamage, true)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
guard:register()

local tick = GlobalEvent("ChaosNecroMinions")
function tick.onThink(interval)
	local t = now()
	for _, player in ipairs(Game.getPlayers()) do
		if #player:getSummons() > 0 or M.rest[player:getId()] then
			local ok, err = pcall(think, player, t)
			if not ok then
				print("[ChaosNecroMinions] " .. tostring(err))
			end
		end
	end
	-- forget minions and players that are gone
	for _, map in ipairs({M.nextHit, M.nextTaunt, M.nextRegen, M.spellAt, M.lastFight}) do
		for id in pairs(map) do
			if not Creature(id) then
				map[id] = nil
			end
		end
	end
	return true
end
tick:interval(ChaosNecroConfig.minions.thinkMs)
tick:register()

-- logout and death: the engine removes the summons with the player; forget the rest and the timers
local function forget(player)
	M.rest[player:getId()] = nil
	M.nextRegen[player:getId()] = nil
	M.lastFight[player:getId()] = nil
end

local login = CreatureEvent("ChaosNecroMinionsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosNecroMinionsLogout")
	player:registerEvent("ChaosNecroMinionsDeath")
	return true
end
login:register()

local logout = CreatureEvent("ChaosNecroMinionsLogout")
function logout.onLogout(player)
	forget(player)
	return true
end
logout:register()

local death = CreatureEvent("ChaosNecroMinionsDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local player = creature:getPlayer()
	if player then
		for _, m in ipairs(L.minions(player)) do
			L.dismiss(m.creature)
		end
		forget(player)
	end
	return true
end
death:register()
