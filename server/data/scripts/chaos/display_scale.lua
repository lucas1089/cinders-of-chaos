-- Display scale, the engine part (server/README.md "Display scale"). The pure part is display_scale_core.lua
-- (ChaosDisplayScale, tests/display_scale_test.lua); numbers in display_scale_config.lua.
--
-- 1. The engine: Game.setDisplayScale(table) (src-patch 0037) gets the factor of every level once at load. The engine
--    then scales, for each receiving player at its own level, the damage / heal text messages (values and the numbers
--    in the text), its own health and mana in the stats packet and the energy shield ("es:" on its opcode). Without
--    the patch (an engine built without it) nothing of that is scaled and the Lua sites below still are.
-- 2. The client (game_chaosscale, extended opcode cfg.opcode = 157):
--      server -> client  scale {level, f}   at login, at a level change (gain or loss) that changes the factor, and as
--                                           the answer to the client's hello
--      client -> server  hello {}           at a game start and when the module loads in game (a reattach to a
--                                           lingering character runs no onLogin)
--    The client scales the numbers it works out itself (the flat mana cost of the spells on the action bar).
-- 3. The Lua sites call ChaosDisplayScale.forPlayer(viewer) and a site function of the core right before they encode
--    (combat log, death recap, party frames, hunt tracker, leaderboards, battleground, guild boss board, bestiary,
--    spellbook, item tooltips, pet heal text).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosDisplayScale or not ChaosDisplayScale.factor then
	dofile("data/scripts/chaos/display_scale_core.lua")
end
Chaos.displayScaleConfig = dofile("data/scripts/chaos/display_scale_config.lua")
local DS = ChaosDisplayScale
DS.configure(Chaos.displayScaleConfig)
local OPCODE = ChaosOpcodes.displayScale or Chaos.displayScaleConfig.opcode

-- the engine's table (src-patch 0037); at every load, so a /reload of a changed curve reaches the engine too
DS.engine = false
if Game and Game.setDisplayScale then
	local ok, err = pcall(Game.setDisplayScale, DS.table())
	DS.engine = ok and true or false
	if not ok then
		print("[Chaos display scale] Game.setDisplayScale: " .. tostring(err))
	end
end

function DS.send(player)
	if not player then
		return false
	end
	local level = player:getLevel()
	return Chaos.send(player, OPCODE, "scale", {level = level, f = DS.factor(level)})
end

local login = CreatureEvent("ChaosDisplayScaleLogin")
function login.onLogin(player)
	player:registerEvent("ChaosDisplayScaleAdvance")
	player:registerEvent("ChaosDisplayScaleOpcode")
	DS.send(player)
	return true
end
login:type("login")
login:register()

-- the client's hello (a game start, a reattach to a lingering character that runs no onLogin, a reloaded module):
-- the factor again
local opcode = CreatureEvent("ChaosDisplayScaleOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if msg and msg.action == "hello" then
		DS.send(player)
	end
end
opcode:type("extendedopcode")
opcode:register()

local advance = CreatureEvent("ChaosDisplayScaleAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and DS.factor(oldLevel) ~= DS.factor(newLevel) then
		DS.send(player)
	end
	return true
end
advance:type("advance")
advance:register()
