-- necro_lib.lua: engine helpers of the Necromancer line (ChaosNecro), shared by both Lua states that need them:
-- the scripts state (necro_minions.lua, necromancer_combat.lua; this file is loaded there like every data/scripts
-- file) and the spells state (the spells in data/spells/chaos/necromancer, lich and bonelord dofile it).
-- It only defines functions: no events are registered here. Numbers: necro_config.lua, pure logic: necro_core.lua.
--
-- Minions are summons of the player (Game.createMonster + setMaster) of the monster types in
-- data/monster/monsters/chaos/necro_*.xml; necro_minions.lua makes them hit, follow and rest.

ChaosNecroConfig = ChaosNecroConfig or dofile("data/scripts/chaos/necro_config.lua")
if not ChaosNecroCore then
	dofile("data/scripts/chaos/necro_core.lua")
end
-- ChaosSpell (PvP rules, free tiles, effects) lives with the spells; load it into this state too
if not ChaosSpell then
	pcall(dofile, "data/spells/scripts/chaos/_common.lua")
end

if not ChaosClassTree then
	dofile("data/scripts/chaos/class_tree.lua") -- the class nodes of the passive tree
end
local CT = ChaosClassTree
if not ChaosQuestBuffs then
	dofile("data/scripts/chaos/quest_buffs_core.lua") -- Dirge of the Legion (level 800 line spell quest buff)
end

ChaosNecro = ChaosNecro or {}
local M = ChaosNecro
local N = ChaosNecroCore
M.cfg = ChaosNecroConfig
M.core = N
local function cfg()
	return M.cfg
end

-- heal a creature by `amount`: Chaos.heal (chaos_constants.lua) where it is loaded (the scripts state); the spells state
-- does not load it, so the same rule here: this engine's addHealth takes (damage type, amount), a one-argument
-- addHealth(amount) heals nothing; the second call covers the stock signature
function M.heal(creature, amount)
	if Chaos and Chaos.heal then
		return Chaos.heal(creature, amount)
	end
	amount = math.min(math.floor(amount or 0), creature:getMaxHealth() - creature:getHealth())
	if amount <= 0 then
		return 0
	end
	local before = creature:getHealth()
	creature:addHealth("healing", amount)
	if creature:getHealth() == before then
		creature:addHealth(amount)
	end
	return creature:getHealth() - before
end

-- player corpses (male, female) of the 10.98 items: never raised or exploded
M.playerCorpses = {[3058] = true, [3065] = true}

local COMBAT = {physical = COMBAT_PHYSICALDAMAGE, death = COMBAT_DEATHDAMAGE, energy = COMBAT_ENERGYDAMAGE}

function M.combatType(name)
	return COMBAT[name] or COMBAT_PHYSICALDAMAGE
end

-- the animations the ranged minions throw (necro_config.lua minions[kind].ani) and the effects on their target
-- (hitEffect); a kind without them throws the death skull and uses the combat type's effect
local ANI = {death = CONST_ANI_DEATH, arrow = CONST_ANI_ARROW, energy = CONST_ANI_ENERGY,
	energyball = CONST_ANI_ENERGYBALL}
local EFFECT = {hitarea = CONST_ME_HITAREA, energyhit = CONST_ME_ENERGYHIT, mortarea = CONST_ME_MORTAREA,
	drawblood = CONST_ME_DRAWBLOOD, groundshaker = CONST_ME_GROUNDSHAKER, energyarea = CONST_ME_ENERGYAREA,
	blackspark = CONST_ME_BLACKSPARK, purpleenergy = CONST_ME_PURPLEENERGY}

-- an effect of EFFECT by name (the minion spells' areaEffect), nil when unknown
function M.effect(name)
	return name and EFFECT[name] or nil
end

function M.animation(k)
	return ANI[k.ani or "death"] or CONST_ANI_DEATH
end

function M.hitEffect(k)
	return EFFECT[k.hitEffect or ""] or (M.combatType(k.combat) == COMBAT_DEATHDAMAGE and CONST_ME_MORTAREA or CONST_ME_HITAREA)
end

-- "necromancer" | "lich" | "bonelord" | nil
function M.classOf(player)
	local voc = player and player:getVocation()
	return voc and N.classOf(cfg(), voc:getId()) or nil
end

-- the store unlock (class_unlocks.lua, another module): may this player become vocation vocId? true when the module
-- is not installed. Returns ok, message.
function M.mayBecome(player, vocId)
	if ChaosClassUnlocks and ChaosClassUnlocks.canUseVocation then
		local ok, msg = ChaosClassUnlocks.canUseVocation(player, vocId)
		if not ok then
			return false, msg or "The Necromancer is not unlocked for your account."
		end
	end
	return true
end

function M.hasCond(creature, subId)
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
end

-- a timer condition (CONDITION_ATTRIBUTES without attributes) with a sub id
function M.addTimer(creature, subId, ticks)
	local c = Condition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT)
	c:setParameter(CONDITION_PARAM_SUBID, subId)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	creature:addCondition(c)
end

-- ------------------------------------------------------------------ minions
-- the player's minions: {creature, kind}, in summon order
function M.minions(player, kind)
	local list = {}
	for _, s in ipairs(player:getSummons() or {}) do
		local k = s:isMonster() and N.kindOf(cfg(), s:getName()) or nil
		if k and (not kind or k == kind) then
			list[#list + 1] = {creature = s, kind = k}
		end
	end
	return list
end

function M.count(player, kind)
	return #M.minions(player, kind)
end

-- a tile a minion may stand on even with a creature there (ground, nothing solid, no protection zone, no stairs,
-- no teleport)
local function standable(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return false
	end
	return not (tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:hasFlag(TILESTATE_PROTECTIONZONE)
		or tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT))
end

-- a standable tile with nobody on it, but a magic field (fire, energy, poison): isFreeTile refuses it
local function fieldOnly(pos)
	local tile = Tile(pos)
	return standable(pos) and tile ~= nil and tile.getTopCreature ~= nil and not tile:getTopCreature()
end

local function inSight(from, to)
	local ok, clear = pcall(function() return Position(from):isSightClear(to, true) end)
	return not ok or clear ~= false
end

-- where a minion of `pos` rises (never a protection zone), or nil: a free tile on or next to `pos`, else a free tile
-- two or three steps away in sight of it, else (beta 2026-10-22: "when the necromancer has no room, the summons are
-- blocked") a tile with a creature on it, `pos` or next to it, then `ref` (the caster's own tile). M.raise creates
-- with force, so the minion shares that tile and walks off.
function M.spotAt(pos, ref)
	ref = ref or pos
	if ChaosSpell.isFreeTile(pos) then
		return Position(pos)
	end
	local spots = ChaosSpell.freeAround(pos, ref)
	if spots[1] then
		return spots[1].pos
	end
	for r = 2, 3 do
		local best, bestD
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local p = Position(pos.x + dx, pos.y + dy, pos.z)
					local d = (p.x - ref.x) ^ 2 + (p.y - ref.y) ^ 2
					if (not best or d < bestD) and ChaosSpell.isFreeTile(p) and inSight(pos, p) then
						best, bestD = p, d
					end
				end
			end
		end
		if best then
			return best
		end
	end
	-- (beta 2026-10-22: "summons do not appear in fields") a field-covered tile with nobody on it, on or next to the
	-- spot; M.raise puts the field out before the minion rises there
	if fieldOnly(pos) then
		return Position(pos)
	end
	for dx = -1, 1 do
		for dy = -1, 1 do
			local p = Position(pos.x + dx, pos.y + dy, pos.z)
			if fieldOnly(p) and inSight(pos, p) then
				return p
			end
		end
	end
	if standable(pos) then
		return Position(pos)
	end
	for dx = -1, 1 do
		for dy = -1, 1 do
			local p = Position(pos.x + dx, pos.y + dy, pos.z)
			if standable(p) and inSight(pos, p) then
				return p
			end
		end
	end
	if standable(ref) then
		return Position(ref)
	end
	return nil
end

-- Create a minion of `kind` for `player` at `pos` with `ratio` (0-1, default 1) of its health; returns it or nil.
-- The class's total cap (necro_config.lua minions.classes[].total, all kinds together) is enforced here, so every
-- spell follows it: when the cap is reached, the OLDEST minion is dismissed (a puff, no corpse, no loot) and then the
-- new one is created.
function M.raise(player, kind, pos, ratio)
	local classKey = M.classOf(player)
	if not classKey then
		return nil
	end
	local spot = M.spotAt(pos, player:getPosition())
	if not spot then
		return nil
	end
	local list = M.minions(player)
	local drop = N.makeRoom(cfg(), classKey, player:getLevel(), list, M.capBonus(player))
	if not drop then
		return nil
	end
	for _, i in ipairs(drop) do
		M.dismiss(list[i].creature)
	end
	-- a magic field on the spot would kill the minion as it rises (its monster type has under 50 health until
	-- setMaxHealth below): the rising minion puts it out
	local tile = Tile and Tile(spot)
	local field = tile and tile.getFieldItem and tile:getFieldItem()
	if field then
		field:remove()
		ChaosSpell.fx(spot, "shadow_smoke", CONST_ME_POFF) -- the field goes out in smoke
	end
	local m = Game.createMonster(cfg().minions[kind].monster, spot, false, true)
	if not m then
		return nil
	end
	ChaosSpell.bindSummon(player, m) -- an ally of its owner: no target of its own from the start
	m:setDropLoot(false)
	m:registerEvent("ChaosNecroMinionGuard")
	local hp = M.healthFor(player, classKey, kind)
	m:setMaxHealth(hp)
	M.showLevel(player, m)
	local want = math.max(1, math.floor(hp * math.min(1, ratio or 1)))
	if want > m:getHealth() then
		M.heal(m, want - m:getHealth())
	end
	local speed = player:getBaseSpeed() - m:getBaseSpeed()
	if speed > 0 then
		m:changeSpeed(speed)
	end
	ChaosSpell.fx(spot, "necro_skull", CONST_ME_MORTAREA)
	return m
end

-- the maximum health of a minion of `kind` for this owner now (level, magic level, class, passive tree)
function M.healthFor(player, classKey, kind)
	return N.minionHealth(cfg(), classKey, kind, player:getLevel(), player:getMagicLevel(), M.minionFactor(player, kind, "health"))
end

-- the owner's level after the minion's name (N.minionLevel; engine patches 0040 / 0044 setDisplayLevel, and 0056 sends
-- a change to the spectators at once). The spawn callback (monster_levels.lua) runs before setMaster, so it gave the
-- minion the level estimate of a wild 10 hp monster; this replaces it. Without the engine method: nothing.
function M.showLevel(player, minion)
	if not minion.setDisplayLevel then
		return false
	end
	local want = N.minionLevel(player:getLevel())
	local shown = minion.getDisplayLevel and minion:getDisplayLevel() or nil
	if shown == want then
		return false
	end
	pcall(minion.setDisplayLevel, minion, want)
	return true
end

-- Keep a living minion in step with its owner (necro_minions.lua, every think): the shown level, and the maximum health
-- when the owner's level, magic level or passive tree changed (the same share of it is kept). Its hits need nothing:
-- each one is computed from the owner's current numbers. Returns true when something changed.
function M.refresh(player, classKey, minion, kind)
	local changed = M.showLevel(player, minion)
	local want = M.healthFor(player, classKey, kind)
	local oldMax = minion:getMaxHealth()
	if want ~= oldMax then
		local health = N.rescaleHealth(oldMax, minion:getHealth(), want)
		minion:setMaxHealth(want) -- the engine caps the health at the new maximum
		if health > minion:getHealth() then
			M.heal(minion, health - minion:getHealth())
		end
		changed = true
	end
	return changed
end

-- remove a minion with a puff (no corpse: minions drop nothing)
function M.dismiss(creature)
	if creature and not creature:isRemoved() then
		creature:getPosition():sendMagicEffect(CONST_ME_POFF)
		creature:remove()
	end
end

-- ------------------------------------------------------------------ corpses
-- ids allowed to own a usable corpse: the player and its party
function M.allowedOwners(player)
	local allowed = {[player:getId()] = true}
	local party = player:getParty()
	if party then
		local leader = party:getLeader()
		if leader then
			allowed[leader:getId()] = true
		end
		for _, m in ipairs(party:getMembers() or {}) do
			allowed[m:getId()] = true
		end
	end
	return allowed
end

-- corpses on the tiles within radius of center: {item, pos, dist, isCorpse, items, owner, playerCorpse, order}
function M.corpsesAround(center, radius)
	local list = {}
	local order = 0
	for dx = -radius, radius do
		for dy = -radius, radius do
			local pos = Position(center.x + dx, center.y + dy, center.z)
			local tile = Tile(pos)
			if tile and not tile:hasFlag(TILESTATE_PROTECTIONZONE) then
				for _, item in ipairs(tile:getItems() or {}) do
					local id = item:getId()
					local it = ItemType(id)
					if it and it:isCorpse() then
						order = order + 1
						local container = item:isContainer() and Container(item.uid) or nil
						list[#list + 1] = {
							item = item, pos = pos, order = order,
							dist = math.max(math.abs(dx), math.abs(dy)),
							isCorpse = true, playerCorpse = M.playerCorpses[id] or false,
							items = container and container:getSize() or 0,
							owner = container and container:getCorpseOwner() or 0,
						}
					end
				end
			end
		end
	end
	return list
end

-- usable corpses for `player` within radius of center, nearest first, at most count
function M.usableCorpses(player, center, radius, count)
	return N.pickCorpses(M.corpsesAround(center, radius), M.allowedOwners(player), count)
end

function M.consumeCorpse(c)
	-- Item has no isRemoved in this engine (only Creature has): remove() of an item already gone is harmless
	local item = c.item
	if item and not (item.isRemoved and item:isRemoved()) then
		item:remove()
	end
end

-- ------------------------------------------------------------------ the passive tree (class_tree.lua)
-- more skeletons (Legion)
function M.capBonus(player)
	return CT.value(player, "ctLegion", "skeletons")
end

-- the Banner of Bones bonus of this owner's minions (the banner's, + Banner Bearer)
function M.bannerBonus(player)
	return cfg().bannerOfBones.damage + CT.value(player, "ctBannerBearer", "damage")
end

-- the bonus on a minion hit: Banner of Bones (`banner` = it is up) plus Dirge of the Legion while it lasts; false for none
-- (N.minionHit takes a number or false)
function M.hitBonus(player, banner)
	local b = banner and M.bannerBonus(player) or 0
	b = b + ChaosQuestBuffs.minionBonus(ChaosQuestBuffs.has(player, "dirge"))
	return b > 0 and b or false
end

-- Covenant of the Grave (the line keystone): its numbers when the player holds it, else nil
local function covenant(player)
	return CT.has(player, "ksGraveCovenant") and CT.fx.ksGraveCovenant or nil
end

-- a minion's hit / health factor (field "hit" | "health"): Bone Colossus (the golem) and Covenant of the Grave (every kind)
function M.minionFactor(player, kind, field)
	local hit, health = N.covenant(covenant(player), M.classOf(player))
	local f = field == "hit" and hit or health
	if kind == "golem" then
		f = f * (1 + CT.value(player, "ksBoneColossus", field))
	end
	return f
end

-- the factor on the player's own spells: Covenant of the Grave takes ownSpell off (1 without it)
function M.ownSpellFactor(player)
	local _, _, own = N.covenant(covenant(player), M.classOf(player))
	return own
end

-- ------------------------------------------------------------------ damage
-- positive min, max of a formula of necro_config for the caster (level scale, Soul Hoard of the Lich, extra)
function M.hoard(player)
	local classKey = M.classOf(player)
	if classKey ~= "lich" then
		return 1
	end
	-- the Lich's slot is its one minion of any kind (a summon spell's minion takes the shade's place)
	local tree = CT.has(player, "ksHoardedSouls") and CT.fx.ksHoardedSouls or nil
	return N.soulHoard(cfg(), classKey, N.totalCap(cfg(), classKey, player:getLevel(), M.capBonus(player)), M.count(player), tree)
end

-- the factor of the own spells' damage: Soul Hoard (Lich) x Covenant of the Grave
function M.spellFactor(player)
	return M.hoard(player) * M.ownSpellFactor(player)
end

function M.values(player, f, extra)
	return N.values(cfg(), f, player:getLevel(), player:getMagicLevel(), (extra or 1) * M.spellFactor(player))
end

-- Deal damage as the caster (it counts for the caster: experience, loot, kill credit). PvP rules of the scripted
-- damage: ChaosSpell.canAttack. Returns the health the target lost (0 when it could not be hit).
function M.damage(caster, target, ctype, min, max, effect, origin)
	if not target or target:isRemoved() or not ChaosSpell.canAttack(caster, target) then
		return 0
	end
	local master = target:getMaster()
	if master and master == caster then
		return 0
	end
	local before = target:getHealth()
	local ok = doTargetCombat(caster, target, ctype, -math.floor(min), -math.floor(max), effect or CONST_ME_NONE,
		origin or ORIGIN_SPELL)
	if not ok then
		return 0
	end
	if target:isRemoved() or target:getHealth() <= 0 then
		return before
	end
	return math.max(0, before - target:getHealth())
end

-- enemies within radius of pos for the caster: monsters that are no player's summons (ChaosSpell.isEnemy), and
-- players the caster may hit (PvP rules) when withPlayers
function M.enemiesAround(caster, pos, radius, withPlayers)
	local list = {}
	for _, c in ipairs(ChaosSpell.spectators(pos, radius)) do
		if ChaosSpell.isEnemy(caster, c) or (withPlayers and c:isPlayer() and ChaosSpell.canAttack(caster, c)) then
			list[#list + 1] = c
		end
	end
	return list
end

return M
