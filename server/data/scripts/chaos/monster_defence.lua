-- Monster defence: how a monster takes a hit from a player (or a player's summon or companion), O462.
-- server/README.md "Monster defence (O462)". Rules: monster_defence_core.lua (pure, tested by
-- server/tests/monster_defence_test.lua), numbers: defence_config.lua (shared with the player stage) and
-- monster_defence_config.lua.
--
-- * What: ONE healthchange event, "ChaosMonsterDefence", on every monster. It runs after the engine's immunity, flat
--   armour / defence and element percent, and before every other Lua event of the monster (tier modifiers, boss
--   scripts, item modifier penetration, rift Warding ...): 1 block (Bulwark), 2 armour by hit size on the physical part,
--   3 the one cap on the element resistance. The older multipliers follow unchanged.
-- * Order: a creature's events run in registration order. A monster gets the event in an onSpawn callback at index -150,
--   the first thing any Chaos script registers on it (XML <script> events of the monster file are registered by the
--   engine before onSpawn and so run first: only the treasure goblins and one harvest boss have them). A monster that
--   never passes onSpawn (a summon of a monster, a raid monster) gets the event at the first hit that targets it (the
--   onTargetCombat callback below), behind the events it already has: they have none of the Chaos ones.
-- * Who: the attacker is a player, or a monster whose master is a player (necromancer minions, companions, convinced
--   monsters). Monsters hurting monsters are left alone.
-- * Armour A is not the XML armor: it is computed from the monster's level and class so that the median class hit of
--   that level loses 25% (normal and magic), 40% (rare, legendary, nemesis) or 50% (bosses: monster type flag isboss,
--   world bosses, rift and Omen guardians, tower bosses, waystone tier bosses). Weapon hits and spells, never a
--   condition tick (a field is one). The XML armor and defence stay the engine's flat subtraction (under 1% of a late hit).
-- * Penetration (O464): the attacking player's item modifiers physpen and elepen. Elemental penetration is taken off the
--   monster's effective resistance AFTER its cap, down to -100; physical penetration is taken off the armour share, down to
--   0. item_mods.lua no longer has a penetration of its own.
--
-- Exports: ChaosMonsterDefence.effectiveResist(monster, combatType, penetration), .armourOf(monster), .classOf(monster),
-- .levelOf(monster), .isBossLike(monster), .playerAbsorb(player, combatType) (the ONE reader of a player's absorb for
-- the element a modifier adds; the player stage replaces it).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
Chaos.defence = dofile("data/scripts/chaos/defence_config.lua")
Chaos.monsterDefence = dofile("data/scripts/chaos/monster_defence_config.lua")
ChaosMonsterDefenceConfig = Chaos.monsterDefence -- monster_tiers.lua reads the same table (Ruthless, the draw)
dofile("data/scripts/chaos/monster_defence_core.lua")
if not ChaosMonsterDamageCore then
	dofile("data/scripts/chaos/monster_damage_core.lua")
end

ChaosMonsterDefence = ChaosMonsterDefence or {}
local MD = ChaosMonsterDefence
local C = ChaosMonsterDefenceCore

local K = C.engineConstants()
MD.K = K
local ELEMENT_NAME = {}
for _, name in ipairs({"fire", "ice", "energy", "earth", "death", "holy"}) do
	ELEMENT_NAME[K[name]] = name
end

local function def()
	return Chaos.defence
end

local function cfg()
	return Chaos.monsterDefence
end

local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end

-- the player behind an attacker: the player, or the master of a summon or companion; nil for anything else
local function playerOf(attacker)
	if not attacker then
		return nil
	end
	if attacker:isPlayer() then
		return attacker
	end
	local master = attacker:getMaster()
	return master and master:isPlayer() and master or nil
end
MD.playerOf = playerOf

-- monster id -> {level, boss, armour = {class = A}} (a monster's level and boss status do not change)
local cache = ChaosMonsterDamageCore.newCache(Chaos.monsterDefence.cacheSize or 32768)
MD.cache = cache

local function try(fn)
	local ok, res = pcall(fn)
	if ok then
		return res
	end
	return nil
end

local function bossLike(monster, id)
	if ChaosTierOf and ChaosTierOf(monster) == "boss" then
		return true
	end
	if try(function() return monster:getType():isBoss() end) then
		return true
	end
	local run = ChaosRift and ChaosRift.monsterRun and ChaosRift.monsterRun[id]
	if run and run.bossIds and run.bossIds[id] then
		return true -- a rift guardian or an Omen guardian
	end
	if ChaosTowerRun and ChaosTowerRun.isBoss and try(function() return ChaosTowerRun.isBoss(monster) end) then
		return true
	end
	if ChaosWaystoneTiers and ChaosWaystoneTiers.entryOf then
		local e = try(function() return ChaosWaystoneTiers.entryOf(monster) end)
		if e and e.boss then
			return true -- a waystone tier boss
		end
	end
	local wb = ChaosWorldBoss and ChaosWorldBoss.state
	return wb ~= nil and wb.bossId == id
end

-- the hunting level of a monster: the nameplate level (set at spawn: hunting level, or the level a rift, area or
-- waystone map scaled it to), else the level of the damage layer (bounty pool, tower floor, invasion area); the higher
-- of the two when both exist
local function levelOf(monster)
	local shown = try(function() return monster:getDisplayLevel() end)
	local level = tonumber(shown) or 0
	if ChaosMonsterDamage and ChaosMonsterDamage.levelOf then
		level = math.max(level, tonumber(try(function() return ChaosMonsterDamage.levelOf(monster) end)) or 0)
	end
	if level <= 0 then
		level = tonumber(try(function() return monster:getMonsterLevel() end)) or 0
	end
	return math.max(1, level)
end

-- MonsterType:getElementList of a type name: combat type -> percent (what the engine applied already)
local elementLists = {}
local function listOf(monster)
	local name = typeNameOf(monster):lower()
	local list = elementLists[name]
	if list == nil then
		list = try(function() return monster:getType():getElementList() end)
		list = type(list) == "table" and list or false
		elementLists[name] = list
	end
	return list
end

local function entryOf(monster)
	local id = monster:getId()
	local e = cache.get(id)
	if not e then
		e = {level = levelOf(monster), boss = bossLike(monster, id) and true or false, armour = {}, list = listOf(monster)}
		cache.put(id, e)
	end
	return e
end

function MD.isBossLike(monster)
	return entryOf(monster).boss
end

function MD.levelOf(monster)
	return entryOf(monster).level
end

-- the rank of a monster: the tier of ChaosTierState (monster_tiers.lua), "normal" without one
local function tierOf(monster)
	local s = ChaosTierState and ChaosTierState[monster:getId()]
	return s and s.tier or "normal"
end

local function classIn(e, monster)
	return e.boss and "boss" or C.rankClass(cfg(), tierOf(monster), false)
end

-- "boss", "elite" or "normal"
function MD.classOf(monster)
	return classIn(entryOf(monster), monster)
end

local function armourIn(e, monster, class)
	local a = e.armour[class]
	if not a then
		a = C.armourValue(def(), cfg(), e.level, class, typeNameOf(monster))
		e.armour[class] = a
	end
	return a
end

function MD.armourOf(monster)
	local e = entryOf(monster)
	return armourIn(e, monster, classIn(e, monster))
end

-- the monster's element percent for a combat type (what the engine applied already)
local function baseResist(monster, ctype)
	local list = entryOf(monster).list
	return list and tonumber(list[ctype]) or 0
end
MD.baseResist = baseResist

-- the modifier flags of a tiered monster (ChaosTierState), cached on its state
local function modSetOf(monster)
	local state = ChaosTierState and ChaosTierState[monster:getId()]
	if not state then
		return nil
	end
	local set = state._set
	if set == nil then
		set = C.modSet(state.mods, state.draw) or false
		state._set = set
	end
	return set or nil
end

-- the effective resistance (percent) of a monster against a damage type, penetration pen (percent points) off the capped
-- value: min(resistCap, the monster's percent + the rank bonus, or the Resistant modifier's number for its element) - pen.
-- The ONE function every resistance of a monster goes through; penetration is the player stage's.
function MD.effectiveResist(monster, ctype, pen)
	local set = modSetOf(monster)
	local bonus = MD.classOf(monster) == "elite" and cfg().rankResistBonus or 0
	local modValue = set and set.resist and set.resist == ELEMENT_NAME[ctype] and cfg().mods.resist or nil
	return C.effectiveResist(def(), baseResist(monster, ctype), bonus, modValue, pen or 0)
end

-- A player's absorb (percent) for the element a modifier adds to a hit: the worn items' absorbPercent, each applied to
-- what the previous one left, as the engine's Player::blockHit does. The storages (gear rolls, passive tree) and the
-- gems, charms and sets are the later events of the player, which see the added part as a typed secondary and reduce it
-- like any other. O464: the player defence layer reduces the added part itself, so this returns 0 while the layer is on.
local WORN_SLOTS = {1, 2, 4, 5, 6, 7, 8, 9, 10, 13}
local function absorbIndex(ctype)
	local i = 1
	while ctype > 1 do
		ctype = math.floor(ctype / 2)
		i = i + 1
	end
	return i
end
function MD.playerAbsorb(player, ctype)
	-- O464: with the player defence layer on, the added part is a typed secondary like any other and the layer (the next
	-- healthchange event of the player) takes the resistance of its group off it: taking the worn pieces' absorb here as well
	-- would reduce it twice
	if ChaosPlayerDefence and ChaosPlayerDefence.active and ChaosPlayerDefence.active() then
		return 0
	end
	local idx = absorbIndex(ctype)
	local keep = 1
	for _, slot in ipairs(WORN_SLOTS) do
		local p = try(function()
			local item = player:getSlotItem(slot)
			local ab = item and ItemType(item:getId()):getAbilities()
			return type(ab) == "table" and type(ab.absorbPercent) == "table" and tonumber(ab.absorbPercent[idx]) or 0
		end)
		if p and p ~= 0 then
			keep = keep * (1 - p / 100)
		end
	end
	return (1 - keep) * 100
end

local ctxBox = {k = K}
local function penetrationOf(player, key)
	local IM = ChaosItemMods
	return player and IM and IM.playerBonus and tonumber(IM.playerBonus(player, key)) or 0
end
local function rand(n)
	return math.random(n)
end

local ev = CreatureEvent("ChaosMonsterDefence")
function ev.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not attacker or cfg().enabled == false then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if not playerOf(attacker) or attacker:getId() == creature:getId() then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local set = modSetOf(creature)
	local e = entryOf(creature)
	local class = classIn(e, creature)
	local ctx = ctxBox
	ctx.def, ctx.cfg, ctx.set = def(), cfg(), set
	ctx.A = armourIn(e, creature, class)
	ctx.bonus = class == "elite" and cfg().rankResistBonus or 0
	-- penetration (O464): the attacking player's (or its summon's master's) item modifiers. Elemental: points off the capped
	-- resistance, physical: points off the armour share
	local p = playerOf(attacker)
	ctx.pen, ctx.physPen = penetrationOf(p, "elepen"), penetrationOf(p, "physpen")
	local list = e.list
	ctx.resistOf = function(ctype) return list and tonumber(list[ctype]) or 0 end
	ctx.elementName = function(ctype) return ELEMENT_NAME[ctype] end
	ctx.rand = rand
	-- O474: a scripted tick of a dot spell is a damage over time tick: it skips the armour as an engine condition does and
	-- still meets the resistance (a direct hit is unchanged)
	local hitOrigin = origin
	if origin ~= ORIGIN_CONDITION and ChaosDot and ChaosDot.isTick(origin, p, creature) then
		hitOrigin = ORIGIN_CONDITION
	end
	local pd, sd, info = C.defend(ctx, {primary = primaryDamage, ptype = primaryType, secondary = secondaryDamage,
		stype = secondaryType, origin = hitOrigin})
	if info.blocked and CONST_ME_BLOCKHIT then
		creature:getPosition():sendMagicEffect(CONST_ME_BLOCKHIT)
	end
	return pd, primaryType, sd, secondaryType
end
ev:register()

-- onSpawn at -150: the first event registered on a monster by any Chaos script (the name callback of
-- monster_tiers.lua is at -100)
local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	self:registerEvent("ChaosMonsterDefence")
	return true
end
spawnCb:register(-150)

-- a monster that never passed onSpawn (a monster's summon, a raid monster) gets it at the first hit that targets it
local targetCb = EventCallback
targetCb.onTargetCombat = function(creature, target)
	if target and target:isMonster() and not (Chaos.eventKnown and Chaos.eventKnown(target, "ChaosMonsterDefence")) then
		if Chaos.registerOnce then
			Chaos.registerOnce(target, "ChaosMonsterDefence")
		else
			target:registerEvent("ChaosMonsterDefence")
		end
	end
	return RETURNVALUE_NOERROR
end
targetCb:register()
