-- retired_spells.lua: at login, forgets the learned rows of the retired stock spells and tells the classes that lost a
-- support what replaced it, once (owner beta report 2026-10-23: "some of my support spells disappeared"; O145). Rules:
-- retired_spells_core.lua, numbers: retired_spells_config.lua. Every Chaos class spell is needlearn="0", so a character
-- has no row for most spells it lost: the notice is by class and level, the forget only cleans old rows.
-- Tests: tests/retired_spells_test.lua. server/README.md "Retired spells (O145)".
if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosRetiredSpellsCore then
	dofile("data/scripts/chaos/retired_spells_core.lua")
end
if not ChaosI18n then
	dofile("data/scripts/chaos/i18n_core.lua")
end

ChaosRetiredSpells = ChaosRetiredSpells or {}
local R = ChaosRetiredSpells
R.cfg = R.cfg or dofile("data/scripts/chaos/retired_spells_config.lua")

-- forgets the retired rows; returns the names forgotten
function R.clean(player)
	local forgotten = {}
	local names = ChaosRetiredSpellsCore.forgetList(R.cfg.names, function(name)
		local ok, has = pcall(player.hasLearnedSpell, player, name)
		return ok and has
	end)
	for _, name in ipairs(names) do
		if pcall(player.forgetSpell, player, name) then
			forgotten[#forgotten + 1] = name
		end
	end
	return forgotten
end

-- tells the notices the character is owed; the version is marked first, so a failure never repeats a notice
function R.notify(player)
	local c = R.cfg
	local told = player:getStorageValue(c.storage)
	local due = ChaosRetiredSpellsCore.due(c.notices, c.version, told, player:getVocation():getId(), player:getLevel())
	if told < c.version then
		player:setStorageValue(c.storage, c.version)
	end
	for _, n in ipairs(due) do
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t and Chaos.t(player, n.text) or n.text)
	end
	return #due
end

local login = CreatureEvent("ChaosRetiredSpellsLogin")
function login.onLogin(player)
	R.clean(player)
	addEvent(function(pid)
		local p = Player(pid)
		if p then
			R.notify(p)
		end
	end, R.cfg.delayMs, player:getId())
	return true
end
login:type("login")
login:register()
