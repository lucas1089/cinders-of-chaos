-- class_spells_core.lua: which spells a character knows after a class change (pure rules, no engine calls; tests:
-- server/tests/class_spells_test.lua). Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A spell with needlearn="1" is castable only once the character has learned it (player_spells). Every spell of the
-- Chaos classes has needlearn="0" (the vocation and the level decide, nothing is taught), so for them a class change
-- needs no teaching: the engine looks at the new vocation at once. A needlearn spell that ever exists (a stock entry, a
-- later reward) must not stay with the old class: the plan below forgets what the new class does not list and teaches
-- what it lists and the level allows, the same rule as for a new character. ChaosClassSpells (class_spells.lua) runs it.
ChaosClassSpellsCore = ChaosClassSpellsCore or {}
local M = ChaosClassSpellsCore

local function lists(spell, vocationId)
	local ids = spell.vocations
	if type(ids) ~= "table" or #ids == 0 then
		return false
	end
	for _, id in ipairs(ids) do
		if id == vocationId then
			return true
		end
	end
	return false
end
M.lists = lists

-- spells: the spellbook's list ({name, level, needLearn, vocations = {ids}}); vocationId, level: the character's;
-- knows(name) -> bool. quest (optional): {isQuest(name) -> bool, unlocked(name) -> bool}, the line spell quests'
-- spells (spellquest.lua): they are needlearn spells the vocations of the line list, but only the quest teaches them, so
-- they are never taught here; the done ones are taught again by the quest's own sync (ChaosSpellQuest.sync), and the
-- forgetting below still applies (a spell of another line goes). Returns {forget = {names}, learn = {names}, keep = n}
-- (names sorted).
function M.plan(spells, vocationId, level, knows, quest)
	local forget, learn, keep = {}, {}, 0
	for _, spell in ipairs(spells or {}) do
		if spell.needLearn and spell.name then
			local known = knows(spell.name) and true or false
			local mine = lists(spell, vocationId)
			if known and not mine then
				forget[#forget + 1] = spell.name
			elseif mine and not known and (tonumber(spell.level) or 0) <= (tonumber(level) or 0)
					and not (quest and quest.isQuest(spell.name)) then
				learn[#learn + 1] = spell.name
			elseif known then
				keep = keep + 1
			end
		end
	end
	table.sort(forget)
	table.sort(learn)
	return {forget = forget, learn = learn, keep = keep}
end
