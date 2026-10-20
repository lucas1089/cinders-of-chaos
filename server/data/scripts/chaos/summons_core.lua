-- summons_core.lua: whose side a creature is on, for the player summons (the Beastmaster's wolves, the Moonfang Pack,
-- the Necromancer's minions, the Cinder Effigy and the Reliquary Warden, the Mirror Image clones, the pets). Pure
-- rules on creature-like tables (isPlayer, getMaster, getParty, getId, getPosition); tests: server/tests/summons_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Loaded by the scripts (summons.lua) and the spells (dofile).
--
-- Owner report 2026-10-17: "the wolf and the player take each other for enemies: the wolf attacks the owner and the
-- player keeps it as a target; the only skill the wolf has (the red claw, Feral Command) is used on the player instead
-- of the monsters". Every summon is made as Game.createMonster + setMaster, and nothing kept the sides apart beyond the
-- engine's own master rule:
--   * the monster is created before its master is set, so the owner standing next to it is in its target list from that
--     moment (M.bind clears it);
--   * a player could take its own summon (or a party member's) as its attack target, and Feral Command and the
--     companions' bites then went at that target (M.isAlly: refused in summons.lua and in Feral Command, which picks the
--     nearest enemy instead).
ChaosSummonsCore = ChaosSummonsCore or {}
local M = ChaosSummonsCore

local function same(a, b)
	if a == b then
		return true
	end
	if a and b and a.getId and b.getId then
		return a:getId() == b:getId()
	end
	return false
end

-- the player behind a creature: itself, or the player master of a summon; nil for a wild monster or an npc
function M.ownerOf(creature)
	if not creature then
		return nil
	end
	if creature.isPlayer and creature:isPlayer() then
		return creature
	end
	local master = creature.getMaster and creature:getMaster()
	if master and master.isPlayer and master:isPlayer() then
		return master
	end
	return nil
end

-- `other` stands on the side of `player`: the player, its summons, its party and the party's summons
function M.isAlly(player, other)
	if not player or not other then
		return false
	end
	if same(player, other) then
		return true
	end
	local owner = M.ownerOf(other)
	if not owner then
		return false
	end
	if same(owner, player) then
		return true
	end
	local party = player.getParty and player:getParty()
	return party ~= nil and party == (owner.getParty and owner:getParty())
end

-- is `creature` a summon of `player` or of a party member (a creature the player must never target)
function M.isAllySummon(player, creature)
	if not creature or not creature.getMaster or not creature:getMaster() then
		return false
	end
	return M.isAlly(player, creature)
end

local function dist(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

-- The nearest enemy of `player` among `creatures` within `range` of `from` (a position): a living monster that is not an
-- ally, not a summon of anyone (a wild monster), attackable. `canSee(creature)` (optional) filters by the caller's rule.
-- Ties go to the lower creature id, so the pick does not jump between ticks.
function M.nearestEnemy(player, creatures, from, range, canSee)
	local best, bestDist, bestId
	for _, c in ipairs(creatures or {}) do
		if c.isMonster and c:isMonster() and not M.isAlly(player, c) and not (c.getMaster and c:getMaster())
				and c:getHealth() > 0 and (c.isAttackable == nil or c:isAttackable()) and (not canSee or canSee(c)) then
			local d = dist(from, c:getPosition())
			if d <= range and (not best or d < bestDist or (d == bestDist and c:getId() < bestId)) then
				best, bestDist, bestId = c, d, c:getId()
			end
		end
	end
	return best
end

-- Makes `monster` the summon of `player` and clears what its creation left behind: the owner next to it was a target of
-- the monster until now, so its attack and follow target go. Returns the monster. Every call is guarded (an engine without
-- one of them is not an error).
function M.bind(player, monster)
	monster:setMaster(player)
	if monster.setTarget then
		pcall(monster.setTarget, monster, nil)
	end
	if monster.setFollowCreature then
		pcall(monster.setFollowCreature, monster, nil)
	end
	return monster
end
