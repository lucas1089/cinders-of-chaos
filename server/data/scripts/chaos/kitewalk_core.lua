-- kitewalk_core.lua: the rules of "Keep attacking while moving" (engine src-patch 0028, client game_kitewalk, extended
-- opcode ChaosOpcodes.kiteWalk = 186; the glue is kitewalk.lua; server/README.md "Keep attacking while moving").
-- Pure Lua, no engine calls; tests/kitewalk_test.lua.
--
-- The engine lets a walk the player asks for (a key, a map or minimap click) win over the chase of the attacked
-- creature, and its steps neither cancel nor delay the next attack. The client option turns that off for the character:
--   client -> server  {on = true | false}
-- and the storage Chaos.storage.kiteWalkOff holds 1 while it is off (unset or anything else: on, the default).
-- Lua 5.1 / LuaJIT and 5.3.

ChaosKiteWalk = ChaosKiteWalk or {}
local K = ChaosKiteWalk

K.OFF = 1 -- the storage value the engine reads as "turned off"
K.ON = 0

local function truthy(v)
	if v == true or v == 1 or v == "1" or v == "true" then
		return true
	elseif v == false or v == 0 or v == "0" or v == "false" then
		return false
	end
	return nil
end

-- the storage value a decoded client message asks for, or nil when the message is not one
function K.storageValue(msg)
	if type(msg) ~= "table" then
		return nil
	end
	local on = msg.on
	if on == nil and type(msg.data) == "table" then
		on = msg.data.on -- {action = ..., data = {on = ...}} as the other modules send
	end
	local b = truthy(on)
	if b == nil then
		return nil
	end
	return b and K.ON or K.OFF
end

-- true when the stored value means "on" (the engine's reading: only K.OFF turns it off)
function K.isOn(stored)
	return tonumber(stored) ~= K.OFF
end

-- the value to write, or nil when nothing changes (the client sends the option at every login)
function K.update(stored, msg)
	local want = K.storageValue(msg)
	if want == nil or K.isOn(stored) == (want == K.ON) then
		return nil
	end
	return want
end

return K
