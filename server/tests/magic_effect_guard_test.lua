-- Run from the server/ folder: luajit tests/magic_effect_guard_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Position:sendMagicEffect refuses effect 0 / nil (the client logs "invalid effect id 0") and passes the others on.
local sent = {}
Position = {sendMagicEffect = function(self, effect, ...) sent[#sent + 1] = effect return true end}
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
check(warnings >= 1, "the refusal is reported")
print = realPrint -- luacheck: ignore
print(string.format("magic_effect_guard_test: %d failures", fails))
if fails > 0 then os.exit(1) end
