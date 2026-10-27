-- summons.lua: player summons are allies of their owner (rules: summons_core.lua; owner report 2026-10-17, see there).
--   * EventCallback onTargetCombat: a summon never acts on its owner, the owner's party or their summons (the base rule
--     of data/events/scripts/creature.lua covers only players), and a player never acts on its own summons or its
--     party's: the hit is refused and the attack target dropped;
--   * a 0.5 s tick drops the attack target of a player holding one of its allies' summons as target (the client's click
--     or auto target), so the owner is not stuck with its wolf and Feral Command and the companions' bites go at monsters.
--   * the same tick purges allies (owner, party, their summons) from the engine target list of each summon (K.purge).
-- Assumed engine API (TFS 1.4): EventCallback onTargetCombat, GlobalEvent think, Game.getPlayers, Player:getSummons,
-- Creature:getTarget/setTarget/getMaster/getParty.
if not ChaosSummonsCore then
	dofile("data/scripts/chaos/summons_core.lua")
end
ChaosSummons = ChaosSummons or {}
local S = ChaosSummons
local K = ChaosSummonsCore
S.core = K

-- the rule of one hit; returns the refusal or nil
function S.refusal(creature, target)
	if not creature or not target then
		return nil
	end
	local owner = K.ownerOf(creature)
	if not owner then
		return nil
	end
	local isSummon = not (creature.isPlayer and creature:isPlayer())
	if isSummon then
		if K.isAlly(owner, target) then
			return RETURNVALUE_YOUMAYNOTATTACKTHISCREATURE
		end
	elseif K.isAllySummon(owner, target) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISCREATURE
	end
	return nil
end

local cb = EventCallback
cb.onTargetCombat = function(creature, target)
	local refused = S.refusal(creature, target)
	if refused then
		if creature.isPlayer and creature:isPlayer() and creature.setTarget then
			pcall(creature.setTarget, creature, nil)
		end
		return refused
	end
	return RETURNVALUE_NOERROR
end
cb:register(-60)

-- drop an ally summon from a player's attack target
function S.dropAllyTarget(player)
	local target = player:getTarget()
	if target and K.isAllySummon(player, target) then
		pcall(player.setTarget, player, nil)
		return true
	end
	return false
end

local tick = GlobalEvent("ChaosSummonsTargets")
function tick.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		-- only a player with summons (or in a party, whose members' summons count too) can hold such a target
		if #player:getSummons() > 0 or player:getParty() then
			local ok, err = pcall(S.dropAllyTarget, player)
			if not ok then
				print("[ChaosSummons] " .. tostring(err))
			end
			-- O86: allies listed as targets of the summons (the engine lists everybody in sight) go out of the list
			local ok2, err2 = pcall(K.purgeAll, player)
			if not ok2 then
				print("[ChaosSummons] " .. tostring(err2))
			end
		end
	end
	return true
end
tick:interval(500)
tick:register()
