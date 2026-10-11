-- Run from the server/ folder: luajit tests/label_colors_test.lua (and lua5.3; CI runs both)
-- Floating labels (ChaosCombatFx.label, opcode 0x84) carry one palette byte as their colour. A "#rrggbb" string there
-- went out as byte 0 (the engine's lua_tonumber of a string), which the client draws black: the legendary power labels
-- were unreadable. This test runs combat_fx.lua against a strict engine whose addByte errors on anything but a byte,
-- checks the hex -> palette mapping, and scans the Chaos scripts and libs for label calls with a hex string colour.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	checks = checks + 1
	if not v then
		error(m or "assertion failed", 2)
	end
end

-- ---------------------------------------------------------------- strict engine mock
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
COMBAT_NONE, COMBAT_PHYSICALDAMAGE, COMBAT_FIREDAMAGE, COMBAT_HEALING = 0, 1, 8, 128
os.mtime = function() return 1000 end
function CreatureEvent() return {register = function() end} end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, k, v) end})
function EventCallback.register() end
local packets = {}
Game = {getSpectators = function() return {{}} end}
function NetworkMessage()
	local m = {bytes = {}}
	function m:addByte(b)
		if type(b) ~= "number" or b % 1 ~= 0 or b < 0 or b > 255 then
			error("addByte: a byte expected, got " .. type(b) .. " " .. tostring(b))
		end
		self.bytes[#self.bytes + 1] = b
	end
	function m:addPosition(p) self.pos = p end
	function m:addString(s) self.text = s end
	function m:sendToPlayer() packets[#packets + 1] = self end
	return m
end
dofile("data/lib/chaos_fx.lua")
dofile("data/scripts/chaos/combat_fx.lua")
local fx = ChaosCombatFx

-- ---------------------------------------------------------------- the palette byte
local function rgb(byte) -- the client's Color::from8bit
	return math.floor(byte / 36) % 6 * 51, math.floor(byte / 6) % 6 * 51, byte % 6 * 51
end
eq(fx.paletteByte(210), 210, "a palette byte passes"); eq(fx.paletteByte(0), 0); eq(fx.paletteByte(255), 255)
eq(fx.paletteByte(nil), fx.defaultColor, "nil: default"); eq(fx.paletteByte("red"), fx.defaultColor, "a name: default")
eq(fx.paletteByte(300), fx.defaultColor, "out of range"); eq(fx.paletteByte(1.5), fx.defaultColor, "not whole")
eq(fx.paletteByte("#ffff00"), 210, "yellow = TEXTCOLOR_YELLOW"); eq(fx.paletteByte("#ff9900"), 198, "TEXTCOLOR_ORANGE")
eq(fx.paletteByte("#FF0000"), 180, "upper case, TEXTCOLOR_RED")
-- every hex colour lands on the nearest cube colour (each channel within half a step)
for _, hex in ipairs({"#ff7a2a", "#7fd8ff", "#f6cf72", "#9fdc7f", "#ffe680", "#ffb347", "#123456", "#fefefe"}) do
	local b = fx.paletteByte(hex)
	ok(b >= 0 and b <= 215, hex .. " in the cube")
	local r, g, bl = rgb(b)
	local want = {tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16)}
	for i, got in ipairs({r, g, bl}) do
		ok(math.abs(got - want[i]) <= 25.5, hex .. " channel " .. i .. " nearest")
	end
end

-- ---------------------------------------------------------------- the label packet
local p = {x = 100, y = 100, z = 7}
ok(fx.label(p, "PARRY", 35), "number colour")
eq(#packets, 1); eq(packets[1].bytes[1], 0x84, "animated text opcode"); eq(packets[1].bytes[2], 35); eq(packets[1].text, "PARRY")
packets = {}
ok(fx.label(p, "Death Blast", "#ff7a2a"), "a hex string no longer reaches addByte")
eq(packets[1].bytes[2], 193, "nearest byte of #ff7a2a")
packets = {}
fx.label(p, "Plain")
eq(packets[1].bytes[2], fx.defaultColor, "no colour: default white")

-- ---------------------------------------------------------------- the legendary power colours (item_powers.lua)
-- the bytes kept the colours the powers were meant to have
local intended = {ember = "#ff7a2a", frost = "#7fd8ff", echo = "#f6cf72", rush = "#9fdc7f", breath = "#ffe680", power = "#ffb347"}
local src = assert(io.open("data/scripts/chaos/item_powers.lua")):read("*a")
for key, hex in pairs(intended) do
	local v = tonumber(src:match("\n\t" .. key .. " = (%d+),"))
	eq(v, fx.paletteByte(hex), "item_powers.lua TEXT." .. key)
end

-- ---------------------------------------------------------------- no hex string where a byte is expected
-- label calls (label / powerLabel / ChaosCombatFx.label / M.label) with a "#rrggbb" literal in the Chaos scripts and libs
local files = {}
local h = assert(io.popen("ls data/scripts/chaos/*.lua data/lib/*.lua 2>/dev/null"))
for f in h:lines() do files[#files + 1] = f end
h:close()
ok(#files > 50, "found the scripts")
local bad = {}
for _, f in ipairs(files) do
	local fh = io.open(f)
	local i = 0
	for line in fh:lines() do
		i = i + 1
		local call = line:match("[%w_]*[Ll]abel%s*%(([^\n]*)")
		if call and call:match("[\"']#%x%x%x%x%x%x[\"']") then
			bad[#bad + 1] = f .. ":" .. i
		end
		if line:match("addByte%s*%(%s*[\"']#") then
			bad[#bad + 1] = f .. ":" .. i
		end
	end
	fh:close()
end
eq(#bad, 0, "hex string colour in a label call: " .. table.concat(bad, ", "))

print("label_colors_test: " .. checks .. " checks OK")
