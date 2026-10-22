-- Run from the server/ folder: luajit tests/magic_effect_guard_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Position:sendMagicEffect refuses effect 0 / nil (the client logs "invalid effect id 0") and passes the others on.
local sent = {}
local at = {}
Position = setmetatable({sendMagicEffect = function(self, effect, ...)
	sent[#sent + 1] = effect
	at[#at + 1] = self
	return true
end}, {__call = function(_, x, y, z) return {x = x, y = y, z = z} end})
local realPrint = print
local warnings = 0
print = function(text) -- luacheck: ignore
	if tostring(text):find("refused", 1, true) then warnings = warnings + 1 end
end
dofile("data/scripts/chaos/chaos_constants.lua")
local fails = 0
local function check(cond, what)
	if not cond then fails = fails + 1 realPrint("FAIL " .. what) end
end
check(Position.sendMagicEffect({}, 0) == false, "effect 0 is refused")
check(Position.sendMagicEffect({}, nil) == false, "a missing effect is refused")
check(Position.sendMagicEffect({}, 7) == true and sent[1] == 7, "a real effect is sent")
check(#sent == 1, "only the real effect reached the engine")
-- an effect redrawn in place with art bigger than a tile goes to its offset tile (data/lib/chaos_fx_send_offsets.lua)
check(Position.sendMagicEffect({x = 100, y = 200, z = 7}, 405) == true and at[2].x == 102 and at[2].y == 202
	and at[2].z == 7, "405 (4x4 in place) is sent two tiles right and down")
check(Position.sendMagicEffect({x = 100, y = 200, z = 7}, 40) == true and at[3].x == 100 and at[3].y == 200,
	"40 (2x2) is sent at its tile")
check(warnings >= 1, "the refusal is reported")
print = realPrint -- luacheck: ignore
print(string.format("magic_effect_guard_test: %d failures", fails))
if fails > 0 then os.exit(1) end
