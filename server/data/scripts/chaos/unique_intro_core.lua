-- unique_intro_core.lua: the pure rule of the one-time unique line (O467; numbers: unique_intro_config.lua, engine glue:
-- unique_intro.lua, tests: tests/unique_intro_test.lua). Lua 5.1 / 5.3 / LuaJIT compatible.

ChaosUniqueIntroCore = ChaosUniqueIntroCore or {}
local K = ChaosUniqueIntroCore

-- is the line due for a character whose storage reads `raw` (nil, -1 and 0 are unset), and is the feature on
function K.due(cfg, raw)
	if type(cfg) ~= "table" or cfg.enabled == false then
		return false
	end
	return (tonumber(raw) or -1) < 1
end

-- the value the storage holds once the line was shown
K.SHOWN = 1

return K
