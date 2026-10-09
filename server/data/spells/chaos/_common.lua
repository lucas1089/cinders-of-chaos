-- Shared helpers for the Chaos spells.
-- Loaded by every chaos spell with: dofile('data/spells/scripts/chaos/_common.lua')
-- (path is relative to the server working dir, same convention as the rest of data/).
if not Fx or not FxMissile then
	pcall(dofile, 'data/lib/chaos_fx.lua') -- real ids, once the merged dat/spr is in use
	if not Fx or not FxMissile then
		dofile('data/spells/scripts/chaos/_fx_fallback.lua')
	end
end
-- the spells use a few names the effect catalog spells differently
if ChaosFx then
	ChaosFx.aura_ring = ChaosFx.aura_ring or ChaosFx.arcane_aura
	ChaosFx.poison_cloud = ChaosFx.poison_cloud or ChaosFx.poison_burst
end
if ChaosFxMissile then
	ChaosFxMissile.holy_arrow = ChaosFxMissile.holy_arrow or ChaosFxMissile.holy_bolt
end
if ChaosSpell then
	return
end

ChaosSpell = {}

local DIR_STEP = {
	[NORTH] = {0, -1}, [EAST] = {1, 0}, [SOUTH] = {0, 1}, [WEST] = {-1, 0},
	[NORTHEAST] = {1, -1}, [SOUTHEAST] = {1, 1}, [SOUTHWEST] = {-1, 1}, [NORTHWEST] = {-1, -1},
}

function ChaosSpell.cancel(creature, message)
	if message then
		creature:sendCancelMessage(message)
	else
		creature:sendCancelMessage(RETURNVALUE_NOTPOSSIBLE)
	end
	creature:getPosition():sendMagicEffect(CONST_ME_POFF)
	return false
end

function ChaosSpell.fx(pos, name, fallback)
	Position(pos):sendMagicEffect(Fx(name, fallback))
end

function ChaosSpell.shoot(fromPos, toPos, name, fallback)
	Position(fromPos):sendDistanceEffect(Position(toPos), FxMissile(name, fallback))
end

-- Animated pack effects and missiles (data/lib/chaos_vfx.lua, client/tools/sprites/import_vfx.py). They are bigger
-- than a tile and are sent at an offset tile by Vfx/VfxShoot. Without chaos_vfx.lua these send nothing (vfx/vfxDir)
-- or fall back to the named chaos effect (vfxOr/vshoot).
if not ChaosVfx then
	pcall(dofile, 'data/lib/chaos_vfx.lua')
end

-- direction (NORTH .. NORTHWEST) from one position to another, for the directional effects (VfxDir)
function ChaosSpell.dirTo(fromPos, toPos)
	local dx, dy = toPos.x - fromPos.x, toPos.y - fromPos.y
	if dx == 0 and dy == 0 then
		return SOUTH
	end
	local sx = dx > 0 and 1 or (dx < 0 and -1 or 0)
	local sy = dy > 0 and 1 or (dy < 0 and -1 or 0)
	if math.abs(dx) >= 2 * math.abs(dy) then
		sy = 0
	elseif math.abs(dy) >= 2 * math.abs(dx) then
		sx = 0
	end
	for dir, step in pairs(DIR_STEP) do
		if step[1] == sx and step[2] == sy then
			return dir
		end
	end
	return SOUTH
end

function ChaosSpell.vfx(pos, name)
	return Vfx ~= nil and pos ~= nil and Vfx(Position(pos), name)
end

function ChaosSpell.vfxDir(pos, base, direction)
	return VfxDir ~= nil and pos ~= nil and VfxDir(Position(pos), base, direction)
end

-- pack effect, or the chaos effect `name` / stock `fallback` when the pack effect is not there
function ChaosSpell.vfxOr(pos, vname, name, fallback)
	if not ChaosSpell.vfx(pos, vname) then
		ChaosSpell.fx(pos, name, fallback)
	end
end

function ChaosSpell.vshoot(fromPos, toPos, vname, name, fallback)
	if not (VfxShoot ~= nil and VfxShoot(Position(fromPos), Position(toPos), vname)) then
		ChaosSpell.shoot(fromPos, toPos, name, fallback)
	end
end

-- Damage helper: returns positive min, max from the usual TFS level/magic-level formula, times `scale` (default 1,
-- the per-spell balance factor: the whole value scales, the level part included).
function ChaosSpell.mlValues(player, mlMin, mlMax, baseMin, baseMax, scale)
	local l = player:getLevel() / 5
	local m = player:getMagicLevel()
	scale = scale or 1
	return (l + m * mlMin + baseMin) * scale, (l + m * mlMax + baseMax) * scale
end

-- Damage helper for skill based spells (melee / distance).
function ChaosSpell.skillValues(player, skillId, mult, baseMin, baseMax)
	local s = player:getEffectiveSkillLevel(skillId)
	local l = player:getLevel() / 5
	return l + s * mult * 0.6 + baseMin, l + s * mult + baseMax
end

-- Attack of the wielded distance weapon, the way the engine adds it up: bow/crossbow attack + ammunition attack,
-- or the attack of a throwing weapon. Item attack attributes (rarity rolls) win over the item type value.
-- Never below 20 (an empty hand), so the spells still do something without a weapon.
local function itemAttack(item)
	local a = item:getAttribute(ITEM_ATTRIBUTE_ATTACK)
	if not a or a == 0 then
		a = ItemType(item:getId()):getAttack()
	end
	return a or 0
end

function ChaosSpell.distanceAttack(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local it = item and ItemType(item:getId())
		if it and it:getWeaponType() == WEAPON_DISTANCE then
			local attack = itemAttack(item)
			if it:getAmmoType() ~= 0 then
				local ammo = player:getSlotItem(CONST_SLOT_AMMO)
				if ammo and ItemType(ammo:getId()):getAmmoType() == it:getAmmoType() then
					attack = attack + itemAttack(ammo)
				end
			end
			return math.max(20, attack)
		end
	end
	return 20
end

function ChaosSpell.bestMeleeSkill(player)
	local best = SKILL_SWORD
	local bestValue = -1
	for _, id in ipairs({SKILL_SWORD, SKILL_CLUB, SKILL_AXE}) do
		local v = player:getEffectiveSkillLevel(id)
		if v > bestValue then
			best, bestValue = id, v
		end
	end
	return best
end

function ChaosSpell.spectators(pos, radius, onlyPlayers)
	return Game.getSpectators(Position(pos), false, onlyPlayers or false, radius, radius, radius, radius) or {}
end

-- A monster the caster may hit with manually looped spells (never the caster's own summons).
-- PvP rules for damage the scripts deal themselves (doTargetCombat skips the engine's checks): the same rules as
-- Combat::canDoCombat plus this server's Creature:onTargetCombat (a player in secure mode cannot be attacked,
-- party members cannot hit each other). Monsters and their summons are always fair game here.
function ChaosSpell.canAttack(caster, target)
	if not target or target == caster or target:getHealth() <= 0 then
		return false
	end
	local targetPlayer = target:getPlayer()
	if not targetPlayer then
		return true
	end
	local master = caster:getMaster()
	local casterPlayer = caster:getPlayer() or (master and master:getPlayer())
	if not casterPlayer then
		return true
	end
	if casterPlayer == targetPlayer or Game.getWorldType() == WORLD_TYPE_NO_PVP then
		return false
	end
	-- guild siege arena: its own rules (data/scripts/chaos/siege.lua; nil = not the siege's business)
	local siege = ChaosSiege and ChaosSiege.canAttack and ChaosSiege.canAttack(casterPlayer, targetPlayer)
	if siege ~= nil then
		return siege
	end
	for _, pos in ipairs({targetPlayer:getPosition(), casterPlayer:getPosition()}) do
		local tile = Tile(pos)
		if tile and (tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:hasFlag(TILESTATE_NOPVPZONE)) then
			return false
		end
	end
	local protection = configManager.getNumber(configKeys.PROTECTION_LEVEL)
	if targetPlayer:getLevel() < protection or casterPlayer:getLevel() < protection then
		return false
	end
	local party = casterPlayer:getParty()
	if party and party == targetPlayer:getParty() then
		return false
	end
	if targetPlayer:hasSecureMode() then
		return false
	end
	-- multi-client: a character with another character online from its IP cannot attack players
	-- (data/scripts/chaos/multiclient.lua; same rule, the settings live in chaos_constants.lua)
	local ip = casterPlayer:getIp()
	if ip ~= 0 and casterPlayer:getGroup():getId() < 4 and Game.getStorageValue(7100990) ~= 1 then
		for _, other in ipairs(Game.getPlayers()) do
			if other ~= casterPlayer and other:getIp() == ip then
				return false
			end
		end
	end
	return true
end

function ChaosSpell.isEnemy(caster, target)
	if not target or target == caster or not target:isMonster() then
		return false
	end
	local master = target:getMaster()
	if master and (master == caster or master:isPlayer()) then
		return false
	end
	local tile = target:getTile()
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false
	end
	return true
end

function ChaosSpell.enemiesAround(caster, pos, radius)
	local list = {}
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if ChaosSpell.isEnemy(caster, c) then
			list[#list + 1] = c
		end
	end
	return list
end

-- Caster + party members (+ caster's summons when includeSummons) around pos.
function ChaosSpell.alliesAround(caster, pos, radius, includeSummons)
	local list = {}
	local party = caster:isPlayer() and caster:getParty() or nil
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if c == caster then
			list[#list + 1] = c
		elseif c:isPlayer() then
			if party and c:getParty() == party then
				list[#list + 1] = c
			end
		elseif includeSummons then
			local master = c:getMaster()
			if master and master == caster then
				list[#list + 1] = c
			end
		end
	end
	return list
end

-- Target of a "needtarget" spell. Variants are tables ({number=...}) or userdata depending on build.
function ChaosSpell.targetOf(variant)
	local id
	if type(variant) == 'table' or type(variant) == 'userdata' then
		id = variant.number
		if not id and variant.getNumber then
			id = variant:getNumber()
		end
	elseif type(variant) == 'number' then
		id = variant
	end
	if id and id ~= 0 then
		return Creature(id)
	end
	return nil
end

function ChaosSpell.stepPos(pos, direction, steps)
	local d = DIR_STEP[direction] or {0, 0}
	steps = steps or 1
	return Position(pos.x + d[1] * steps, pos.y + d[2] * steps, pos.z)
end

-- Free to stand on: ground, nothing solid, no creature, no floor change, not protection zone.
function ChaosSpell.isFreeTile(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:hasFlag(TILESTATE_PROTECTIONZONE)
		or tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT)
		or tile:hasFlag(TILESTATE_MAGICFIELD) then
		return false
	end
	if tile:getTopCreature() then
		return false
	end
	return true
end

-- Free tiles around center, ordered by distance to ref (ascending). Set far=true for descending.
function ChaosSpell.freeAround(center, ref, far)
	local list = {}
	for dx = -1, 1 do
		for dy = -1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local p = Position(center.x + dx, center.y + dy, center.z)
				if ChaosSpell.isFreeTile(p) then
					local dist = (p.x - ref.x) ^ 2 + (p.y - ref.y) ^ 2
					list[#list + 1] = {pos = p, dist = dist}
				end
			end
		end
	end
	table.sort(list, function(a, b)
		if far then return a.dist > b.dist end
		return a.dist < b.dist
	end)
	return list
end

-- Run fn(caster, step) now and then every `interval` ms until `count` runs were made.
-- Stops when the caster is gone/dead or fn returns false.
function ChaosSpell.pulse(casterId, count, interval, fn, step)
	step = step or 1
	local caster = Creature(casterId)
	if not caster or caster:getHealth() <= 0 then
		return
	end
	if fn(caster, step) == false then
		return
	end
	if step < count then
		addEvent(ChaosSpell.pulse, interval, casterId, count, interval, fn, step + 1)
	end
end

-- Remove a creature later (summons / clones).
function ChaosSpell.removeLater(creatureId)
	local c = Creature(creatureId)
	if c then
		c:getPosition():sendMagicEffect(CONST_ME_POFF)
		c:remove()
	end
end

-- Slow a creature: ticks ms, percent 0..1 of speed removed.
function ChaosSpell.slow(target, ticks, percent)
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	c:setFormula(-percent, 0, -percent, 0)
	target:addCondition(c)
end

function ChaosSpell.damageTarget(caster, target, ctype, min, max, effect)
	if not ChaosSpell.canAttack(caster, target) then
		return false
	end
	return doTargetCombat(caster, target, ctype, -math.floor(min), -math.floor(max), effect)
end

function ChaosSpell.healTarget(caster, target, min, max, effect)
	doTargetCombat(caster, target, COMBAT_HEALING, math.floor(min), math.floor(max), effect)
end

-- Distinct condition sub ids so several chaos buffs can run together.
ChaosSpell.SUBID = {
	blood_pact = 71001, crimson_fury = 71002, rally = 71003, barkskin = 71004,
	divine_ward = 71005, soul_aegis = 71006, phantom_veil = 71007, dash = 71008, iron_will = 71009,
}

-- ------------------------------------------------------------------------------------------------ Thief line
-- (thief/ ninja/ samurai/; the class rules are data/scripts/chaos/classes.lua, loaded here once)
function ChaosSpell.loadClasses()
	if not ChaosClasses then
		dofile('data/scripts/chaos/classes.lua')
	end
	return ChaosClasses
end

-- attack of the main-hand melee weapon (left hand first, as the engine picks it), never below 20 (an empty hand)
function ChaosSpell.meleeAttack(player)
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local it = item and ItemType(item:getId())
		if it then
			local wt = it:getWeaponType()
			if wt == WEAPON_SWORD or wt == WEAPON_CLUB or wt == WEAPON_AXE then
				return math.max(20, itemAttack(item))
			end
		end
	end
	return 20
end

-- skill x attack of a Thief-line weapon strike: the sword skill and the main-hand blade
function ChaosSpell.bladePower(player)
	return player:getEffectiveSkillLevel(SKILL_SWORD) * ChaosSpell.meleeAttack(player)
end

-- skill x attack of a shuriken: the better of sword and distance skill, the throwing star in hand (any throwing
-- weapon) or Chaos.classes.shuriken.defaultAttack
function ChaosSpell.shurikenPower(player)
	local skill = math.max(player:getEffectiveSkillLevel(SKILL_SWORD), player:getEffectiveSkillLevel(SKILL_DISTANCE))
	local attack = (Chaos and Chaos.classes and Chaos.classes.shuriken.defaultAttack) or 50
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local item = player:getSlotItem(slot)
		local it = item and ItemType(item:getId())
		if it and it:getWeaponType() == WEAPON_DISTANCE and it:getAmmoType() == 0 then
			attack = math.max(attack, itemAttack(item))
		end
	end
	return skill * attack
end

-- A weapon strike dealt by a spell: physical damage with a weapon origin (ORIGIN_MELEE or ORIGIN_RANGED), so the
-- weapon-hit rules of data/scripts/chaos/thief_combat.lua apply to it (stealth ambush crit, Poison Blades, Bushido
-- crit, the Ninja's off-hand strike after a melee strike). PvP rules as ChaosSpell.damageTarget.
-- Level factor of the Thief line's spell strikes (Chaos.classes.spellLevelScale): 1 up to level `from`, then +1 per
-- `per` levels, at most `max`. It stands in for the passive tree the Thief line does not have yet (the other classes'
-- level 1000 numbers carry 248 tree points); re-tune or drop it with the Thief-line tree (docs/CLASSES.md, phase 2).
function ChaosSpell.thiefLevelScale(player)
	local s = Chaos and Chaos.classes and Chaos.classes.spellLevelScale
	if not s or not player.getLevel then
		return 1
	end
	return math.min(s.max, 1 + math.max(0, player:getLevel() - s.from) / s.per)
end

function ChaosSpell.weaponStrike(caster, target, min, max, effect, origin)
	if not ChaosSpell.canAttack(caster, target) then
		return false
	end
	local k = ChaosSpell.thiefLevelScale(caster)
	min, max = min * k, max * k
	return doTargetCombat(caster, target, COMBAT_PHYSICALDAMAGE, -math.floor(min), -math.floor(max), effect,
		origin or ORIGIN_MELEE)
end

-- Make monsters around `pos` let go of `player` (or of every player, when player is nil): drop it as attack and
-- follow target and take it off their target lists. Used by Shadow Veil (stealth) and Smoke Bomb (blind).
function ChaosSpell.dropTarget(monster, player)
	if not monster or not monster:isMonster() then
		return
	end
	local current = monster:getTarget()
	if current and (not player or current == player) then
		monster:setTarget(nil)
		monster:setFollowCreature(nil)
	end
	for _, t in ipairs(monster:getTargetList() or {}) do
		if t:isPlayer() and (not player or t == player) then
			monster:removeTarget(t)
		end
	end
end
