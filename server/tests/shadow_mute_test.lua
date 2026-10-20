-- Run from the server/ folder: luajit tests/shadow_mute_test.lua (and lua5.3; CI runs both).
-- shadow_mute_core.lua (the pure state) and the channel patch tool (tools/patch_shadow_mute.py) output shape.
local fails = 0
local function eq(a, b, what)
	if a ~= b then print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b)); fails = fails + 1 end
end
dofile("data/scripts/chaos/shadow_mute_core.lua")
local C = ChaosShadowMuteCore
local s, NOW = C.newState(), 1000

eq(C.isMuted(s, 7, NOW), false, "nobody muted at first")
eq(C.mute(s, 7, 10, NOW), NOW + 600, "mute for 10 minutes")
eq(C.isMuted(s, 7, NOW + 599), true, "still muted")
eq(C.remaining(s, 7, NOW + 100), 500, "remaining")
eq(C.isMuted(s, 7, NOW + 600), false, "ended exactly at the end time")
eq(s.untilAt[7], nil, "an ended mute is forgotten")
eq(C.mute(s, 7, 99999, NOW), NOW + 1440 * 60, "capped at 24 h")
eq(C.mute(s, 7, 0, NOW), NOW + 60, "at least one minute")
eq(C.mute(s, 7, 10, NOW, 5), NOW + 300, "own cap")
eq(C.mute(s, nil, 10, NOW), nil, "no guid")
eq(C.mute(s, 0, 10, NOW), nil, "bad guid")
eq(C.mute(nil, 1, 10, NOW), nil, "no state")
eq(C.unmute(s, 7), true, "unmute")
eq(C.unmute(s, 7), false, "unmute again")
eq(C.unmute(s, nil), false, "unmute nil")
C.mute(s, 1, 20, NOW); C.mute(s, 2, 5, NOW); C.mute(s, 3, 1, NOW)
local l = C.list(s, NOW + 61)
eq(#l, 2, "list drops the ended mute")
eq(l[1].guid, 2, "shortest first")
eq(C.remaining(nil, 1, NOW), 0, "nil state")
eq(C.remaining(s, 1, nil), 0, "nil time")

-- the patch tool, on a copy of a channel script
local f = io.popen("python3 -I tools/patch_shadow_mute.py 2>&1")
local usage = f:read("*a"); f:close()
eq(usage:find("usage", 1, true) ~= nil, true, "tool prints its usage")
local dir = os.tmpname(); os.remove(dir)
os.execute("mkdir -p " .. dir .. "/chatchannels/scripts")
local x = io.open(dir .. "/chatchannels/chatchannels.xml", "w")
x:write('<channels><channel id="3" name="World Chat" public="1" script="world.lua"/><channel id="9" name="Private" script="p.lua"/></channels>')
x:close()
local sc = io.open(dir .. "/chatchannels/scripts/world.lua", "w")
sc:write("function onSpeak(player, type, message)\n\treturn type\nend\n")
sc:close()
os.execute("python3 -I tools/patch_shadow_mute.py " .. dir .. " >/dev/null 2>&1")
sc = io.open(dir .. "/chatchannels/scripts/world.lua"); local text = sc:read("*a"); sc:close()
eq(text:find("ChaosShadowMute.onChannelSpeak(player, 3, type, message)", 1, true) ~= nil, true, "hook with the channel id")
eq(text:find("return false", 1, true) ~= nil, true, "returns false when swallowed")
os.execute("python3 -I tools/patch_shadow_mute.py " .. dir .. " >/dev/null 2>&1")
sc = io.open(dir .. "/chatchannels/scripts/world.lua"); local again = sc:read("*a"); sc:close()
eq(again, text, "idempotent")
os.execute("rm -rf " .. dir)

if fails > 0 then os.exit(1) end
print("shadow_mute_test OK")
