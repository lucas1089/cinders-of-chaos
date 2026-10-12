-- Level-up wings (client game_levelwings, extended opcode ChaosOpcodes.levelWings = 191; server/README.md
-- "Level-up wings"). When a character gains a level, every player who sees it is sent
--   play {id = creature id, lv = new level, n = levels gained}
-- and the client opens a pair of golden wings behind that creature for about 1.8 s. The stock level-up text and
-- effect stay the engine's. Rules and throttles: levelwings_core.lua (tests/levelwings_test.lua); numbers:
-- levelwings_config.lua. Several levels from one experience gain are one onAdvance call, so they play once.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosLevelWings or not ChaosLevelWings.decide then
	dofile("data/scripts/chaos/levelwings_core.lua")
end
ChaosLevelWingsConfig = dofile("data/scripts/chaos/levelwings_config.lua")

local L = ChaosLevelWings
local OPCODE = ChaosOpcodes.levelWings or 191
L.state = L.state or L.newState()

local function cfg()
	return ChaosLevelWingsConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- sends the play to everyone who sees the player; returns how many were sent
function L.broadcast(player, oldLevel, newLevel)
	local now = nowMs()
	local c = cfg()
	L.prune(L.state, c, now)
	local payload = L.decide(L.state, c, player:getId(), oldLevel, newLevel, now)
	if not payload then
		return 0
	end
	local byId, ids = {}, {}
	for _, spectator in ipairs(Game.getSpectators(player:getPosition(), c.multifloor and true or false, true) or {}) do
		local id = spectator:getId()
		byId[id] = spectator
		ids[#ids + 1] = id
	end
	local sent = 0
	for _, id in ipairs(L.recipients(L.state, c, ids, now)) do
		if Chaos.send(byId[id], OPCODE, "play", payload) then
			sent = sent + 1
		end
	end
	return sent
end

local login = CreatureEvent("ChaosLevelWingsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosLevelWingsAdvance")
	player:registerEvent("ChaosLevelWingsLogout")
	return true
end
login:register()

local advance = CreatureEvent("ChaosLevelWingsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		local ok, err = pcall(L.broadcast, player, oldLevel, newLevel)
		if not ok then
			print("[ChaosLevelWings] " .. tostring(err))
		end
	end
	return true
end
advance:register()

local logout = CreatureEvent("ChaosLevelWingsLogout")
function logout.onLogout(player)
	L.forget(L.state, player:getId())
	return true
end
logout:register()
