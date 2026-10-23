-- Late-game monster damage boost: high-level monsters deal more PHYSICAL damage to players, to give back the late-game
-- pressure that the percent armour (engine patch 0016) took away. server/README.md "Percent armour", tools/armor_sim.py.
--
-- * Which hits: a monster's melee and ranged physical attacks (ORIGIN_MELEE / ORIGIN_RANGED: the hits armour reduces)
--   on a player. Not: a player's summon (necromancer minions, companions, convinced monsters), PvP, scripted damage
--   (ORIGIN_SPELL: reflection, Cinderdeath, boss scripts), conditions (bleeding), healing; elemental damage only with
--   cfg.elemental.
-- * How much: x (1 + percent / 100), percent from cfg.points by the monster's level (monster_damage_core.lua):
--   ChaosLoot.monsterLevel (Monster:getMonsterLevel() of a level-scaled monster, else the bounty pool's hunting level,
--   else the experience / health estimate); a monster's summon counts at least at its master's level; an invader
--   (invasion.lua) at least at the invasion area's level.
-- * Order: a healthchange event registered on the player at login by "Chaos0MonsterDamageLogin". The engine runs the
--   login events in name order (std::map) and a creature's events in registration order, so this name puts the boost
--   before every other Chaos healthchange event of the player (resistances, "Damage Taken from Monsters", dodge, block,
--   Last Breath, the monster tier, rift and invasion multipliers, ...) and before the energy shield (engine, after the
--   scripts): the player's reductions all see the boosted hit. Defence and armour run before any script (engine).
-- * Mana shield (cfg.manaShield): the engine gives the whole hit to the onManaChange events first, then what the mana
--   did not take to the onHealthChange events. The mana event scales the hit; when the mana cannot take all of it, the
--   health event of the same hit (same attacker, same millisecond) is not scaled again.
--
-- * Pack combat (pace.lua): a paced monster's hits (every element, conditions and mana shield hits included) are x its
--   damage curve (pace_config.lua damage) on top, in the same event; bosses and player summons are never paced.
-- * Waystone tiers (waystone_tiers.lua): a tier's monster or boss in its tier's map deals x its tier's damage on top
--   (every element), in the same event.
--
-- Config: monster_damage_config.lua (Chaos.monsterDamage). Pure logic: monster_damage_core.lua
-- (tests: server/tests/monster_damage_test.lua). Exports: ChaosMonsterDamage.levelOf(monster),
-- ChaosMonsterDamage.multiplierOf(attacker) (1 when not boosted).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
Chaos.monsterDamage = dofile("data/scripts/chaos/monster_damage_config.lua")
dofile("data/scripts/chaos/monster_damage_core.lua")

ChaosMonsterDamage = ChaosMonsterDamage or {}
local MD = ChaosMonsterDamage
local C = ChaosMonsterDamageCore

local K = {
	physical = COMBAT_PHYSICALDAMAGE, healing = COMBAT_HEALING, undefined = COMBAT_UNDEFINEDDAMAGE, none = COMBAT_NONE,
	manadrain = COMBAT_MANADRAIN, melee = ORIGIN_MELEE, ranged = ORIGIN_RANGED, spell = ORIGIN_SPELL
}
MD.K = K

local function cfg()
	return Chaos.monsterDamage
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- monster id -> level (a monster's level does not change); two generations of cfg.levelCacheSize entries each
-- (monster_damage_core.lua C.newCache): bounded memory, and live monsters stay cached with ~100k alive under pace
local levelCache = C.newCache(Chaos.monsterDamage and Chaos.monsterDamage.levelCacheSize or 32768)
MD.levelCache = levelCache

local function ownLevel(monster)
	if ChaosLoot and ChaosLoot.monsterLevel then
		local ok, lvl = pcall(ChaosLoot.monsterLevel, monster)
		if ok and tonumber(lvl) then
			return tonumber(lvl)
		end
	end
	local ok, lvl = pcall(function() return monster:getMonsterLevel() end)
	if ok and tonumber(lvl) and tonumber(lvl) > 0 then
		return tonumber(lvl)
	end
	if ChaosItemMods and ChaosItemMods.estimateMonsterLevel then
		local mt = monster:getType()
		local okE, exp = pcall(function() return mt:getExperience() end)
		local okH, hp = pcall(function() return mt:getMaxHealth() end)
		return ChaosItemMods.estimateMonsterLevel(okE and exp or 0, okH and hp or 0)
	end
	return 0
end

function MD.levelOf(monster)
	local id = monster:getId()
	local lvl = levelCache.get(id)
	if lvl then
		return lvl
	end
	lvl = ownLevel(monster)
	local inv = ChaosInvasion and ChaosInvasion.invaders and ChaosInvasion.invaders[id]
	if inv and tonumber(inv.areaLevel) then
		lvl = math.max(lvl, tonumber(inv.areaLevel))
	end
	levelCache.put(id, lvl)
	return lvl
end

-- the boost multiplier of an attacker against a player: 1 for anything but a monster that is not a player's summon
function MD.multiplierOf(attacker)
	local c = cfg()
	if not c or c.enabled == false or not attacker or not attacker:isMonster() then
		return 1
	end
	local level = MD.levelOf(attacker)
	local master = attacker:getMaster()
	if master then
		if master:isPlayer() then
			return 1
		end
		if master:isMonster() then
			level = math.max(level, MD.levelOf(master))
		end
	end
	return C.multiplierFor(c, level)
end

-- target id -> {attacker, at}: the hit the mana event scaled and the mana could not take whole
local manaScaled = {}

local function boost(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if not attacker or not creature:isPlayer() then
		return primaryDamage, secondaryDamage
	end
	local mult = MD.multiplierOf(attacker)
	-- pack combat (pace.lua): a paced monster (or its summon) deals x its damage curve, every element and condition
	local pm = ChaosPace and ChaosPace.damageMultOf and ChaosPace.damageMultOf(attacker) or 1
	-- a waystone tier's monster or boss in its tier's map (waystone_tiers.lua): x its tier's damage, every element
	if ChaosWaystoneTiers and ChaosWaystoneTiers.damageMultOf then
		pm = pm * (ChaosWaystoneTiers.damageMultOf(attacker) or 1)
	end
	-- the Infinity Tower (infinitytower_run.lua): a tower monster hits x its floor's damage factor, every element
	if ChaosTowerRun and ChaosTowerRun.damageMultOf then
		pm = pm * (ChaosTowerRun.damageMultOf(attacker) or 1)
	end
	if mult == 1 and pm == 1 then
		return primaryDamage, secondaryDamage
	end
	primaryDamage, secondaryDamage = C.scaleHit(cfg(), K, mult, primaryDamage, primaryType, secondaryDamage,
		secondaryType, origin)
	return C.scalePace(K, pm, primaryDamage, primaryType, secondaryDamage, secondaryType)
end

local health = CreatureEvent("ChaosMonsterDamageHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local id = creature:getId()
	local m = manaScaled[id]
	if m then
		manaScaled[id] = nil
		if attacker and m.attacker == attacker:getId() and m.at == nowMs() then
			return primaryDamage, primaryType, secondaryDamage, secondaryType -- scaled by the mana event already
		end
	end
	primaryDamage, secondaryDamage = boost(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:register()

local mana = CreatureEvent("ChaosMonsterDamageMana")
function mana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local c = cfg()
	if not c or c.manaShield == false then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local p, s = boost(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if (p ~= primaryDamage or s ~= secondaryDamage) and creature:isPlayer() then
		local total = math.abs(p) + math.abs(s)
		if total > creature:getMana() then
			manaScaled[creature:getId()] = {attacker = attacker:getId(), at = nowMs()}
		else
			manaScaled[creature:getId()] = nil
		end
	end
	return p, primaryType, s, secondaryType
end
mana:register()

-- the name sorts before every other Chaos login event (see the header): the boost is the player's first healthchange
local login = CreatureEvent("Chaos0MonsterDamageLogin")
function login.onLogin(player)
	player:registerEvent("ChaosMonsterDamageHealth")
	player:registerEvent("ChaosMonsterDamageMana")
	return true
end
login:register()

local logout = CreatureEvent("ChaosMonsterDamageLogout")
function logout.onLogout(player)
	manaScaled[player:getId()] = nil
	return true
end
logout:register()
