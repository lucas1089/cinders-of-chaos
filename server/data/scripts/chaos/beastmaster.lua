-- beastmaster.lua: the Beastmaster's companion (docs/CLASSES.md; rules in classes.lua, numbers in
-- Chaos.classes.companion, chaos_constants.lua).
--
-- The companion is a real monster type (the first of Chaos.classes.companion.monsters that exists: War Wolf, else
-- Wolf), summoned by the spell Wild Bond (beastmaster/wild_bond.lua) as the player's summon: the engine makes it
-- follow its owner and attack the owner's target. Its health scales with the owner's level (set by the spell), and
-- its damage too: this file deals a bite every biteMs to the owner's target when the companion stands next to it,
-- physical damage dealt as the owner (ChaosClasses.biteValues: level and distance skill), so it counts for the owner
-- like its own hits would (PvP rules: ChaosSpell.canAttack). The monster's own little melee attack stays.
-- At most ChaosClasses.companionCap(level) companions (1, 2 from level 400). A companion that strays farther than
-- leashRange or onto another floor is brought back next to its owner. A character that stops being a Beastmaster
-- loses its companions (ascension.lua calls dismissIfNotBeastmaster). The engine removes summons at logout.
-- A companion drops no loot, and its owner's own hits (arrow splash, area spells) and those of the owner's other
-- summons do not hurt it (ChaosCompanionGuard, registered by the spell).

if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end
local C = ChaosClasses
local function cfg()
	return Chaos.classes.companion
end

ChaosBeastmaster = ChaosBeastmaster or {}
local B = ChaosBeastmaster
B.nextBite = B.nextBite or {} -- companion id -> os.mtime of its next bite

local function isCompanionName(name)
	name = (name or ""):lower()
	for _, n in ipairs(cfg().monsters) do
		if n:lower() == name then
			return true
		end
	end
	return false
end

-- the player's companions (summons of the companion monster type)
function B.companions(player)
	local list = {}
	for _, s in ipairs(player:getSummons() or {}) do
		if s:isMonster() and isCompanionName(s:getName()) then
			list[#list + 1] = s
		end
	end
	return list
end

function B.dismiss(player)
	for _, s in ipairs(B.companions(player)) do
		B.nextBite[s:getId()] = nil
		s:getPosition():sendMagicEffect(CONST_ME_POFF)
		s:remove()
	end
end

function B.dismissIfNotBeastmaster(player)
	if not C.isBeastmaster(player:getVocation():getId()) then
		B.dismiss(player)
	end
end

local function distance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- a free tile next to `pos` (the owner), or nil
local function spotNear(pos)
	if ChaosSpell and ChaosSpell.freeAround then
		local spots = ChaosSpell.freeAround(pos, pos)
		return spots[1] and spots[1].pos or nil
	end
	return nil
end

local function bite(owner, companion, target)
	if target:isPlayer() and not (ChaosSpell and ChaosSpell.canAttack(owner, target)) then
		return
	end
	local min, max = C.biteValuesFor(owner)
	if max <= 0 then
		return
	end
	local ok, err = pcall(doTargetCombat, owner, target, COMBAT_PHYSICALDAMAGE, -min, -max, CONST_ME_DRAWBLOOD, ORIGIN_NONE)
	if not ok then
		print("[ChaosBeastmaster] " .. tostring(err))
	end
end

local function think(owner, now)
	local target = owner:getTarget()
	local opos = owner:getPosition()
	for _, companion in ipairs(B.companions(owner)) do
		local cpos = companion:getPosition()
		if distance(cpos, opos) > cfg().leashRange then
			local spot = spotNear(opos)
			if spot then
				companion:teleportTo(spot, true)
				cpos = spot
			end
		end
		local id = companion:getId()
		if target and target:getHealth() > 0 and target ~= companion and distance(cpos, target:getPosition()) <= 1
				and (B.nextBite[id] or 0) <= now then
			B.nextBite[id] = now + cfg().biteMs
			bite(owner, companion, target)
		end
	end
end

local guard = CreatureEvent("ChaosCompanionGuard")
function guard.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local owner = creature:getMaster()
	if owner and attacker and primaryType ~= COMBAT_HEALING
			and (attacker == owner or attacker:getMaster() == owner) then
		return 0, primaryType, 0, secondaryType
	end
	-- Pack Alpha (the owner's keystone): companions take less damage
	local cut = owner and owner:isPlayer() and ChaosClassTree.value(owner, "ksPackAlpha", "reduction") or 0
	if cut > 0 and primaryType ~= COMBAT_HEALING then
		primaryDamage = primaryDamage - math.floor(primaryDamage * cut)
		secondaryDamage = secondaryDamage - math.floor(secondaryDamage * cut)
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
guard:register()

local tick = GlobalEvent("ChaosBeastmasterCompanions")
function tick.onThink(interval)
	local now = C.now()
	for _, player in ipairs(Game.getPlayers()) do
		if C.isBeastmaster(player:getVocation():getId()) and #player:getSummons() > 0 then
			local ok, err = pcall(think, player, now)
			if not ok then
				print("[ChaosBeastmaster] " .. tostring(err))
			end
		end
	end
	-- forget companions that are gone
	for id in pairs(B.nextBite) do
		if not Creature(id) then
			B.nextBite[id] = nil
		end
	end
	return true
end
tick:interval(Chaos.classes.companion.thinkMs)
tick:register()
