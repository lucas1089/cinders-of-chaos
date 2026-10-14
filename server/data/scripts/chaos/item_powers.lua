-- Legendary powers on the character: what the equipped items' powers (data/lib/chaos_powers.lua, modifiers of
-- data/lib/chaos_item_mods.lua with `power = true`) do in the game. The totals of the equipped items come from
-- item_mods.lua (ChaosItemModsCache, capped per power); this script only reads them. Overview: server/README.md "Legendary
-- powers". Tested by server/tests/powers_test.lua against a mocked engine.
--   Death Blast        onKill: a fire explosion around the dead monster (cooldown, damage capped by the character level)
--   Glacial Ward       a dodge or a block (item_mods.lua calls ChaosItemMods.onAvoid): an ice nova that slows
--   Echo Shot          onHealthChange on the target: a ranged hit is repeated a moment later
--   Critical Echo      the same for a critical hit (8th argument of onHealthChange, engine patch 0001)
--   Arc Lightning      a hit arcs to three monsters around the target
--   Crimson Burst      a hit heals a share of the character's health
--   Bloodrush          every kill adds a stack (5, 6 s): more damage dealt
--   Shatter Splash     the killing blow bursts onto monsters around the dead one
--   Last Breath        onHealthChange on the player: a lethal hit leaves the character at a share of the health (5 minutes)
--   Ember Step         onHealthChange on the player: a hard hit blinks the character away and burns where it stood
--   Hunter's Rush      onKill: haste for a few seconds
--   Smoldering Aura    every 3 s fire damage to the monsters next to the character
-- Every proc has an internal cooldown (ChaosPowers.config), the effects never start more procs of their own (guard) and only
-- monsters that are not somebody's summon are hit. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua") -- loads chaos_item_mods.lua and chaos_powers.lua
end

local P = ChaosPowers
local M = ChaosItemMods
local CFG = P.config
ChaosItemModsCache = ChaosItemModsCache or {}
local cache = ChaosItemModsCache

local guard = false -- the damage of a power never starts another power
local states = {} -- player id -> {cd = {key -> ms}, rush = {stacks, last}, kills = {monster id -> {hit, at}}}

local function now()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function stateOf(player)
	local id = player:getId()
	local st = states[id]
	if not st then
		st = {cd = {}, rush = {stacks = 0, last = 0}, kills = {}}
		states[id] = st
	end
	return st
end

-- the capped powers of a player (key -> value), nil when none
local function powersOf(player)
	local totals = cache[player:getId()]
	if not totals then
		return nil
	end
	local active = P.active(totals)
	return next(active) and active or nil
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	return nil
end

-- a monster of the wild (no summon, no pet)
local function wild(creature)
	return creature and creature:isMonster() and not creature:getMaster()
end

-- the monsters within `radius` of pos (not `skip`), up to `limit`
local function monstersAround(pos, radius, limit, skip)
	local out = {}
	for _, c in ipairs(Game.getSpectators(pos, false, false, radius, radius, radius, radius) or {}) do
		if #out >= limit then
			break
		end
		if c ~= skip and wild(c) and c:getHealth() > 0 then
			out[#out + 1] = c
		end
	end
	return out
end

local function effect(pos, id)
	if pos and id then
		pos:sendMagicEffect(id)
	end
end

-- label colours: one byte of the client's 8-bit palette (combat_fx.lua M.label sends it with opcode 0x84; the client
-- draws r*36 + g*6 + b, 51 per step). A "#rrggbb" string here went out as byte 0: black text, unreadable on the map.
local TEXT = {
	ember = 193, -- #ff6633 (Death Blast, Ember Step)
	frost = 101, -- #66ccff (Frost Nova)
	echo = 206, -- #ffcc66 (Echo Shot, Critical Echo)
	rush = 134, -- #99cc66 (Hunter's Rush)
	breath = 213, -- #ffff99 (Last Breath)
	power = 205, -- #ffcc33 (default)
}
P.labelColors = TEXT

local function label(pos, text, color)
	if ChaosCombatFx and ChaosCombatFx.label then
		pcall(ChaosCombatFx.label, pos, text, color)
	end
end

-- damage `target` from `player` (negative values; the guard keeps it from starting more powers)
local function strike(player, target, ctype, amount, fx)
	if not target or target:getHealth() <= 0 then
		return
	end
	guard = true
	local ok, err = pcall(doTargetCombatHealth, player:getId(), target:getId(), ctype, -math.abs(amount), -math.abs(amount), fx or CONST_ME_NONE)
	guard = false
	if not ok then
		print("[ChaosPowers] " .. tostring(err))
	end
end

local function heal(creature, amount)
	if Chaos.heal then
		return Chaos.heal(creature, amount)
	end
	creature:addHealth("healing", amount)
end

local function powerLabel(player, text, color)
	label(player:getPosition(), text, color or TEXT.power)
end

-- ---------------------------------------------------------------- the effects
local function deathBlast(player, dead)
	local c = CFG.deathblast
	local dmg = P.blastDamage(dead:getMaxHealth(), player:getLevel())
	local pos = dead:getPosition()
	effect(pos, CONST_ME_FIREAREA or CONST_ME_EXPLOSIONAREA)
	for _, m in ipairs(monstersAround(pos, c.radius, c.targets, dead)) do
		strike(player, m, COMBAT_FIREDAMAGE, dmg, CONST_ME_FIREAREA)
	end
	label(pos, "Death Blast", TEXT.ember)
end

local function frostNova(player)
	local c = CFG.frostward
	local dmg = P.novaDamage(player:getLevel())
	local pos = player:getPosition()
	effect(pos, CONST_ME_ICEAREA or CONST_ME_ICEATTACK)
	for _, m in ipairs(monstersAround(pos, c.radius, c.targets)) do
		strike(player, m, COMBAT_ICEDAMAGE, dmg, CONST_ME_ICEAREA)
		if m:getHealth() > 0 and CONDITION_PARALYZE and Condition then
			local cond = Condition(CONDITION_PARALYZE)
			cond:setParameter(CONDITION_PARAM_TICKS, c.slowMs)
			cond:setFormula(-c.slow / 100, 0, -c.slow / 100, 0)
			m:addCondition(cond)
		end
	end
	label(pos, "Frost Nova", TEXT.frost)
end

local function repeatHit(player, target, damage, ctype, delay, text)
	local id, pid = target:getId(), player:getId()
	addEvent(function()
		local p, t = Player(pid), Creature(id)
		if p and t and t:getHealth() > 0 then
			strike(p, t, ctype, damage, CONST_ME_NONE)
			label(t:getPosition(), text, TEXT.echo)
		end
	end, delay)
end

local function arc(player, target, hit, ctype)
	local c = CFG.arclightning
	local dmg = P.share(hit, c.pct)
	local from = target:getPosition()
	for _, m in ipairs(monstersAround(from, c.radius, c.targets, target)) do
		strike(player, m, COMBAT_ENERGYDAMAGE or ctype, dmg, CONST_ME_ENERGYHIT or CONST_ME_NONE)
	end
	effect(from, CONST_ME_ENERGYAREA or CONST_ME_ENERGYHIT)
end

local function splash(player, dead, hit, pct)
	local c = CFG.shattersplash
	local dmg = P.share(hit, pct)
	local pos = dead:getPosition()
	effect(pos, CONST_ME_EXPLOSIONHIT or CONST_ME_EXPLOSIONAREA)
	for _, m in ipairs(monstersAround(pos, c.radius, c.targets, dead)) do
		strike(player, m, COMBAT_PHYSICALDAMAGE, dmg, CONST_ME_HITAREA or CONST_ME_NONE)
	end
end

local function haste(player)
	local c = CFG.hunterrush
	if not (Condition and CONDITION_HASTE) then
		return
	end
	local cond = Condition(CONDITION_HASTE)
	cond:setParameter(CONDITION_PARAM_TICKS, c.ms)
	cond:setParameter(CONDITION_PARAM_SPEED, c.speed)
	player:addCondition(cond)
	effect(player:getPosition(), CONST_ME_MAGIC_GREEN)
	powerLabel(player, "Hunter's Rush", TEXT.rush)
end

-- the blink is a step, not a teleport: clear sight and a walking path of a few steps (a path that errors counts as none)
local function reachable(player, from, to, range)
	if from.isSightClear and not from:isSightClear(to, true) then
		return false
	end
	if player.getPathTo then
		local ok, path = pcall(player.getPathTo, player, to, 0, 0, true, true, range * 2)
		if not ok or not path then
			return false
		end
	end
	return true
end

-- a free tile within `range` of the character (not its own), nil when none
local function freeTile(player, range)
	local pos = player:getPosition()
	local tries = {}
	for dx = -range, range do
		for dy = -range, range do
			if (dx ~= 0 or dy ~= 0) and math.max(math.abs(dx), math.abs(dy)) >= 2 then
				tries[#tries + 1] = {dx, dy}
			end
		end
	end
	for i = #tries, 2, -1 do -- shuffle
		local j = math.random(1, i)
		tries[i], tries[j] = tries[j], tries[i]
	end
	for _, d in ipairs(tries) do
		local to = Position(pos.x + d[1], pos.y + d[2], pos.z)
		local tile = Tile(to)
		-- never through a wall, door or bars: the tile must be in clear sight and walkable from here
		if tile and tile:getGround() and tile:getCreatureCount() == 0 and tile:queryAdd(player) == RETURNVALUE_NOERROR
				and not tile:hasFlag(TILESTATE_PROTECTIONZONE) and reachable(player, pos, to, range) then
			return to
		end
	end
	return nil
end

local function emberStep(player)
	local c = CFG.emberstep
	local from = player:getPosition()
	local to = freeTile(player, c.range)
	if not to then
		return false
	end
	local dmg = P.burnDamage(player:getLevel())
	player:teleportTo(to, true)
	effect(from, CONST_ME_FIREAREA or CONST_ME_HITBYFIRE)
	effect(to, CONST_ME_FIREATTACK or CONST_ME_MAGIC_RED)
	for _, m in ipairs(monstersAround(from, c.radius, c.targets)) do
		strike(player, m, COMBAT_FIREDAMAGE, dmg, CONST_ME_HITBYFIRE)
	end
	powerLabel(player, "Ember Step", TEXT.ember)
	return true
end

-- ---------------------------------------------------------------- hits you deal
local dealt = CreatureEvent("ChaosPowersDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin, critical)
	if guard or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p = playerOf(attacker)
	local pw = p and powersOf(p)
	if not pw or not wild(creature) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st, t = stateOf(p), now()
	local stacks = P.rushStacks(st.rush, t)
	if pw.bloodrush and stacks > 0 then
		local pct = P.rushBonus(stacks, pw.bloodrush)
		primaryDamage = M.scale(primaryDamage, pct)
		secondaryDamage = M.scale(secondaryDamage, pct)
	end
	local hit = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if hit > 0 and origin ~= ORIGIN_CONDITION then
		local lethal = hit >= creature:getHealth()
		if lethal and pw.shattersplash then
			st.kills[creature:getId()] = {hit = hit, at = t}
		end
		if not lethal then
			if pw.crimsonburst and P.roll(pw.crimsonburst) and P.ready(st.cd, "crimsonburst", t, CFG.crimsonburst.cooldownMs) then
				heal(p, P.burstHeal(p:getMaxHealth()))
				effect(p:getPosition(), CONST_ME_MAGIC_RED)
			end
			if pw.arclightning and P.roll(pw.arclightning) and P.ready(st.cd, "arclightning", t, CFG.arclightning.cooldownMs) then
				arc(p, creature, hit, primaryType)
			end
			if pw.echoshot and origin == ORIGIN_RANGED and P.roll(pw.echoshot)
					and P.ready(st.cd, "echoshot", t, CFG.echoshot.cooldownMs) then
				repeatHit(p, creature, P.share(hit, CFG.echoshot.pct), primaryType, CFG.echoshot.delayMs, "Echo")
			end
			if pw.critecho and critical and P.roll(pw.critecho) and P.ready(st.cd, "critecho", t, CFG.critecho.cooldownMs) then
				repeatHit(p, creature, P.share(hit, CFG.critecho.pct), primaryType, CFG.critecho.delayMs, "Echo")
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:register()

-- the hit event goes on the monsters you attack, as item_mods.lua does
local POWERS_ON_HIT = {"echoshot", "critecho", "arclightning", "crimsonburst", "bloodrush", "shattersplash"}
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
	if creature and target and target:isMonster() and creature:isPlayer() and not eventKnown(target, "ChaosPowersDealt") then
		local pw = powersOf(creature)
		if pw then
			for _, key in ipairs(POWERS_ON_HIT) do
				if pw[key] then
					registerOnce(target, "ChaosPowersDealt")
					break
				end
			end
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()

-- ---------------------------------------------------------------- kills
local kill = CreatureEvent("ChaosPowersKill")
function kill.onKill(player, target)
	if guard or not wild(target) then
		return true
	end
	local pw = powersOf(player)
	if not pw then
		return true
	end
	local st, t = stateOf(player), now()
	local info = st.kills[target:getId()]
	st.kills[target:getId()] = nil
	if pw.bloodrush then
		P.rushKill(st.rush, t)
	end
	if pw.shattersplash and info and t - info.at < 2000 and P.ready(st.cd, "shattersplash", t, CFG.shattersplash.cooldownMs) then
		splash(player, target, info.hit, pw.shattersplash)
	end
	if pw.deathblast and P.roll(pw.deathblast) and P.ready(st.cd, "deathblast", t, CFG.deathblast.cooldownMs) then
		deathBlast(player, target)
	end
	if pw.hunterrush and P.roll(pw.hunterrush) and P.ready(st.cd, "hunterrush", t, CFG.hunterrush.cooldownMs) then
		haste(player)
	end
	return true
end
kill:register()

-- ---------------------------------------------------------------- hits you take
local taken = CreatureEvent("ChaosPowersTaken")
function taken.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if guard or primaryType == COMBAT_HEALING or not creature:isPlayer() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local pw = powersOf(creature)
	if not pw then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local total = math.abs(primaryDamage) + math.abs(secondaryDamage)
	if total <= 0 then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st, t = stateOf(creature), now()
	if pw.lastbreath then
		-- health + energy shield: the shield (engine patch 0015) takes its part after this event
		local newDamage, healTo = P.lastBreath(creature:getHealth() + (creature.getEnergyShield and creature:getEnergyShield() or 0),
			creature:getMaxHealth(), total, pw.lastbreath)
		local last = tonumber(creature:getStorageValue(CFG.lastbreath.storage)) or -1
		local ready = last < 0 or os.time() - last >= CFG.lastbreath.cooldownMs / 1000
		if newDamage and ready then
			creature:setStorageValue(CFG.lastbreath.storage, os.time())
			primaryDamage, secondaryDamage = newDamage, 0
			local id = creature:getId()
			addEvent(function()
				local p = Player(id)
				if p and p:getHealth() > 0 and p:getHealth() < healTo then
					heal(p, healTo - p:getHealth())
					effect(p:getPosition(), CONST_ME_HOLYAREA or CONST_ME_MAGIC_BLUE)
					powerLabel(p, "Last Breath", TEXT.breath)
				end
			end, 50)
			return primaryDamage, primaryType, secondaryDamage, secondaryType
		end
	end
	if pw.emberstep and attacker and P.hardHit(total, creature:getMaxHealth()) and creature:getHealth() > total
			and P.roll(pw.emberstep) and P.ready(st.cd, "emberstep", t, CFG.emberstep.cooldownMs) then
		local id = creature:getId()
		addEvent(function() -- after the hit: the blink must not run inside the damage call
			local p = Player(id)
			if p and p:getHealth() > 0 then
				emberStep(p)
			end
		end, 0)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
taken:register()

-- item_mods.lua: a dodged or blocked hit (kind "dodge" / "block")
M.onAvoid = function(player, attacker, kind)
	if guard or not attacker or not attacker:isMonster() then
		return
	end
	local pw = powersOf(player)
	if pw and pw.frostward and P.roll(pw.frostward) and P.ready(stateOf(player).cd, "frostward", now(), CFG.frostward.cooldownMs) then
		frostNova(player)
	end
end

-- ---------------------------------------------------------------- the aura
local TICK = CFG.smolderaura.tickMs
local function auraTick()
	for _, player in ipairs(Game.getPlayers()) do
		local pw = powersOf(player)
		if pw and pw.smolderaura and player:getHealth() > 0 then
			local dmg = P.auraTick(pw.smolderaura)
			for _, m in ipairs(monstersAround(player:getPosition(), CFG.smolderaura.radius, CFG.smolderaura.targets)) do
				strike(player, m, COMBAT_FIREDAMAGE, dmg, CONST_ME_HITBYFIRE)
			end
		end
	end
	addEvent(auraTick, TICK)
end

local startup = GlobalEvent("ChaosPowersStartup")
function startup.onStartup()
	addEvent(auraTick, TICK)
	return true
end
startup:register()

-- ---------------------------------------------------------------- login / logout
local login = CreatureEvent("ChaosPowersLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPowersTaken")
	player:registerEvent("ChaosPowersKill")
	player:registerEvent("ChaosPowersLogout")
	return true
end
login:register()

local logout = CreatureEvent("ChaosPowersLogout")
function logout.onLogout(player)
	states[player:getId()] = nil
	return true
end
logout:register()

ChaosPowersState = states -- tests and the admin tools read it
