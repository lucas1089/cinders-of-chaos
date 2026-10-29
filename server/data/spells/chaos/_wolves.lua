-- Shared cast of the Beastmaster's wolf spells (O332): Feral Command, Pack Frenzy, Pack Howl and Rending Pounce. Each
-- spell script is three lines:
--   dofile('data/spells/scripts/chaos/_wolves.lua')
--   function onCastSpell(creature, variant, isHotkey) return Wolves.cast('<key>', creature, variant) end
-- The numbers are Chaos.classes.companion.spells[<key>] (chaos_constants.lua): `mauls` (what one companion deals to what
-- the spell hits, in spell bites; a bite is ChaosClasses.biteValuesFor: level, distance skill and the owner's wolf factor, so
-- Pack Alpha and the Trials' minion damage count) and, for an area spell, `radius` (a circle around the target).
--
-- Every companion leaps next to the target (the same rule as before), then deals its mauls to every monster the spell hits.
-- The damage is dealt as the owner (it counts for the owner: experience, loot, kill credit), physical, ORIGIN_SPELL like any
-- spell (the class spell factor and the owner's damage rules apply). A bite never hits an ally: the nearest enemy takes it
-- instead (owner report 2026-10-17: Feral Command went at the player's own wolf).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()
if not ChaosAttackKitCore then
	dofile('data/scripts/chaos/attack_kit_core.lua')
end
if Wolves then
	return
end

local Sides = ChaosSpell.loadSummons()
local K = ChaosAttackKitCore
Wolves = {}
local W = Wolves

-- how each spell looks: the effect at the target (a pack effect, else the named chaos effect), and the leap's missile
W.look = {
	feral = {vfx = "claw_rake", directional = true, fx = nil},
	frenzy = {vfx = "claw_rake", directional = true, fx = nil},
	howl = {vfx = "aura_burst_gold", fx = "shockwave"},
	pounce = {vfx = "heavy_cleave", directional = true, fx = "ground_slam"}
}

function W.cfg()
	return Chaos.classes.companion
end

-- the player's companions (summons of the companion monster types)
function W.pack(player)
	local out = {}
	for _, s in ipairs(player:getSummons()) do
		if s:isMonster() then
			local name = s:getName():lower()
			for _, n in ipairs(W.cfg().monsters) do
				if n:lower() == name then
					out[#out + 1] = s
				end
			end
		end
	end
	return out
end

-- the target of the cast: the one aimed at, or the nearest enemy when it is an ally; nil and a message when there is none
function W.target(player, variant)
	local target = ChaosSpell.targetOf(variant)
	if not target or target == player then
		return nil, RETURNVALUE_YOUCANONLYUSEITONCREATURES
	end
	if Sides.isAlly(player, target) then
		local pos = player:getPosition()
		target = Sides.nearestEnemy(player, ChaosSpell.spectators(pos, 7), pos, 7, function(c)
			return ChaosSpell.canAttack(player, c)
		end)
		if not target then
			return nil, "No enemy in range."
		end
	end
	if not ChaosSpell.canAttack(player, target) then
		return nil, RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return target
end

-- every companion leaps next to the target (a missile and a teleport when it stands farther than one tile) and takes it
local function leap(pack, target)
	local tpos = target:getPosition()
	for _, s in ipairs(pack) do
		local spos = s:getPosition()
		if spos.z ~= tpos.z or math.max(math.abs(spos.x - tpos.x), math.abs(spos.y - tpos.y)) > 1 then
			local spots = ChaosSpell.freeAround(tpos, spos)
			if spots[1] then
				ChaosSpell.shoot(spos, spots[1].pos, "shadow_bolt", CONST_ANI_WHIRLWINDCLUB)
				s:teleportTo(spots[1].pos, true)
			end
		end
		s:setTarget(target)
	end
end

-- the monsters (and the players PvP allows) of a circle around the target, the target first
function W.victims(player, target, radius)
	if not radius then
		return {target}
	end
	local tpos = target:getPosition()
	local set = K.tileSet({shape = "circle", radius = radius}, tpos, nil, false)
	local list = {target}
	for _, c in ipairs(ChaosSpell.spectators(tpos, radius + 1)) do
		local p = c:getPosition()
		if c ~= target and c ~= player and p.z == tpos.z and set[p.x .. ":" .. p.y] then
			if ChaosSpell.isEnemy(player, c) or (c:isPlayer() and ChaosSpell.canAttack(player, c)) then
				list[#list + 1] = c
			end
		end
	end
	return list
end

local function burst(player, key, tpos)
	local look = W.look[key] or W.look.feral
	local shown = false
	if look.directional then
		shown = ChaosSpell.vfxDir(tpos, look.vfx, ChaosSpell.dirTo(player:getPosition(), tpos))
	elseif look.vfx then
		shown = ChaosSpell.vfx(tpos, look.vfx)
	end
	if look.fx then
		ChaosSpell.fx(tpos, look.fx, CONST_ME_HITAREA)
	elseif not shown then
		tpos:sendMagicEffect(CONST_ME_HITAREA)
	end
end

function W.cast(key, creature, variant)
	local player = creature:getPlayer()
	local spell = W.cfg().spells[key]
	if not player or not spell then
		return false
	end
	local target, why = W.target(player, variant)
	if not target then
		return ChaosSpell.cancel(player, why)
	end
	local pack = W.pack(player)
	if #pack == 0 then
		return ChaosSpell.cancel(player, "You have no companion out. Call it with Wild Bond.")
	end
	leap(pack, target)
	local min, max = ChaosClasses.maulValuesFor(player, key) -- with the wolf factor (Pack Alpha, the Trials' minion damage)
	local victims = W.victims(player, target, spell.radius)
	for _ = 1, #pack do
		for _, v in ipairs(victims) do
			ChaosSpell.damageTarget(player, v, COMBAT_PHYSICALDAMAGE, min, max, CONST_ME_DRAWBLOOD)
		end
	end
	burst(player, key, target:getPosition())
	return true
end
