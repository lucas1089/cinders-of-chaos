-- spell_masteries.lua: the passive tree side of the spell modifier masteries (O451). A mastery effect with the tree stat
-- spellMod = <id> (data/lib/chaos_spell_masteries_config.lua) gives one named spell a free support effect. The effect itself is
-- read where every spell reads its supports (data/lib/chaos_supports.lua S.spellEffects); this file only writes the id of the
-- held choice to the player storage that both Lua states read, after every apply of the tree (login, save, reset, a changed
-- mastery effect, a loadout switch), and drops the supports' cached effects of the player.
-- Rules and tests: server/tests/spell_masteries_test.lua. Numbers and choices: chaos_spell_masteries_config.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosSupports then
	dofile("data/lib/chaos_supports.lua")
end
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.listeners = ChaosPassiveTree.listeners or {}

ChaosSpellMasteries = ChaosSpellMasteries or {}
local M = ChaosSpellMasteries

-- the choice id of a summed bonus table (none: -1). An id the config does not know counts as none.
function M.idOf(bonuses)
	local id = bonuses and tonumber(bonuses.spellMod) or 0
	if id and id > 0 and ChaosSupports.masteryById[id] then
		return id
	end
	return -1
end

-- writes the storage when it changed and refreshes the supports' view of the player
function M.apply(player, bonuses)
	local key = ChaosSupports.mastery.storage
	local id = M.idOf(bonuses)
	local changed = player:getStorageValue(key) ~= id
	if changed then
		player:setStorageValue(key, id)
	end
	if ChaosSupports.refreshActive and (changed or id > 0) then
		ChaosSupports.refreshActive(player)
	end
	return id
end

ChaosPassiveTree.listeners[#ChaosPassiveTree.listeners + 1] = function(player, bonuses)
	M.apply(player, bonuses)
end
