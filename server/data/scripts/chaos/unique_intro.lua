-- unique_intro.lua: the engine glue of the one-time unique line (O467; rule: unique_intro_core.lua, numbers:
-- unique_intro_config.lua, tests: tests/unique_intro_test.lua). ChaosUniqueIntro.found(player) is called where a player is
-- handed a unique (see the config header). The first call of a character sends one text message in its language, through
-- the path the first-unique message uses (MESSAGE_EVENT_ADVANCE, Chaos.t); every later call does nothing.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosI18n then
	dofile("data/scripts/chaos/i18n_core.lua")
end
ChaosUniqueIntroConfig = ChaosUniqueIntroConfig or dofile("data/scripts/chaos/unique_intro_config.lua")
if not ChaosUniqueIntroCore then
	dofile("data/scripts/chaos/unique_intro_core.lua")
end

ChaosUniqueIntro = ChaosUniqueIntro or {}
local M = ChaosUniqueIntro

function M.found(player)
	local cfg, K = ChaosUniqueIntroConfig, ChaosUniqueIntroCore
	if not player or not player.getStorageValue then
		return false
	end
	if not K.due(cfg, player:getStorageValue(cfg.storage)) then
		return false
	end
	player:setStorageValue(cfg.storage, K.SHOWN)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or 19, Chaos.t(player, cfg.text))
	return true
end
