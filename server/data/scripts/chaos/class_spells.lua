-- class_spells.lua: the character's spells after a class change (owner report 2026-10-17: "the Vocation Change scroll
-- changes the vocation but not the spells": a Beastmaster changed to Deadeye kept the Beastmaster spells). Rules:
-- class_spells_core.lua. Called from ChaosClasses.afterVocationChange (ascension.lua: the store's Vocation Change,
-- ascension, the quest, the free switch, staff tools):
--   * needlearn spells: forgotten when the new class does not list them, learned when it does and the level allows;
--   * the Spellbook window of that client gets the new vocation at once (ChaosSpellbook.refresh), so its list, the
--     pickers' "learned" box and the helper do not show the old class until a relog.
-- Every Chaos spell is needlearn="0": the engine lets the new vocation cast them straight away and the old class's
-- spells are refused by the vocation check; only the client's views needed the refresh.
-- Tests: server/tests/class_spells_test.lua.
if not ChaosClassSpellsCore then
	dofile("data/scripts/chaos/class_spells_core.lua")
end

ChaosClassSpells = ChaosClassSpells or {}
local S = ChaosClassSpells

-- Returns {forget = n, learn = n} (what was changed). `quiet`: no refresh of the client's Spellbook.
function S.sync(player, quiet)
	local result = {forget = 0, learn = 0}
	if not player then
		return result
	end
	local book = ChaosSpellbook
	local spells = book and book.get and book.get() or {}
	local plan = ChaosClassSpellsCore.plan(spells, player:getVocation():getId(), player:getLevel(), function(name)
		local ok, has = pcall(player.hasLearnedSpell, player, name)
		return ok and has
	end)
	for _, name in ipairs(plan.forget) do
		if pcall(player.forgetSpell, player, name) then
			result.forget = result.forget + 1
		end
	end
	for _, name in ipairs(plan.learn) do
		if pcall(player.learnSpell, player, name) then
			result.learn = result.learn + 1
		end
	end
	if not quiet and book and book.refresh then
		book.refresh(player)
	end
	return result
end
