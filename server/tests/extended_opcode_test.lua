-- Run from the server/ folder: luajit tests/extended_opcode_test.lua (and lua5.3; CI runs both)
-- Extended opcode messages over the engine's 8192-byte string limit: Player.sendExtendedOpcode
-- (data/scripts/chaos/extended_opcode.lua) never writes the broken "32 <opcode>" fragment that made the client drop the
-- rest of the network message at every admin login, and Chaos.splitExtended / Chaos.sendChunked (chaos_constants.lua)
-- cut a big payload into the S/P/E parts that the client's ProtocolGame.registerExtendedJSONOpcode joins again.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- engine mock
-- NetworkMessage as the engine does it: addString refuses (silently) strings over 8192 bytes
local wire = {} -- bytes of every message sent, one string per sendToPlayer
local NM = {}
NM.__index = NM
function NetworkMessage()
	return setmetatable({bytes = {}}, NM)
end
function NM:addByte(b) self.bytes[#self.bytes + 1] = string.char(b % 256) end
function NM:addString(s)
	if #s > 8192 then
		return
	end
	self.bytes[#self.bytes + 1] = string.char(#s % 256, math.floor(#s / 256)) .. s
end
function NM:sendToPlayer(player) wire[#wire + 1] = table.concat(self.bytes) end
function NM:delete() end

Player = {}
local player = {name = "Tester", otc = true}
function player:isUsingOtClient() return self.otc end
function player:getName() return self.name end
setmetatable(player, {__index = Player})

local printed = {}
local realPrint = print
print = function(s) printed[#printed + 1] = s end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/extended_opcode.lua")

-- the client's parser: 0x32, u8 opcode, u16 length, bytes; returns the opcodes and payloads, or nil and an error
local function parse(msg)
	local out, i = {}, 1
	while i <= #msg do
		if msg:byte(i) ~= 0x32 or i + 3 > #msg then
			return nil, "bad header at " .. i
		end
		local op, len = msg:byte(i + 1), msg:byte(i + 2) + msg:byte(i + 3) * 256
		if i + 3 + len > #msg then
			return nil, "eof reached at " .. i
		end
		out[#out + 1] = {op = op, buffer = msg:sub(i + 4, i + 3 + len)}
		i = i + 4 + len
	end
	return out
end

-- the client's join (modules/gamelib/protocolgame.lua, the registerExtendedJSONOpcode path)
local function join(buffers)
	local acc
	for _, buffer in ipairs(buffers) do
		local status, data = buffer:sub(1, 1), buffer:sub(2)
		if status ~= "E" and status ~= "P" then
			acc = ""
		end
		if status ~= "S" and status ~= "P" and status ~= "E" then
			acc = buffer
		else
			acc = acc .. data
		end
	end
	return acc
end

-- ---------------------------------------------------------------- the bug, with the base Lua version
local function baseSend(self, opcode, buffer)
	local m = NetworkMessage()
	m:addByte(0x32)
	m:addByte(opcode)
	m:addString(buffer)
	m:sendToPlayer(self)
end
local big = "{" .. string.rep("x", 20265) .. "}" -- the size of the admin catalog
wire = {}
baseSend(player, 120, big)
baseSend(player, 89, "0")
local bundled = table.concat(wire) -- both land in one network message
eq(bundled, "\50\120\50\89\1\0\48", "base version: 32 78, then the 89 reply (32 59 01 00 30)")
local parsed, err = parse(bundled)
eq(parsed, nil, "the client cannot read it")
eq(err, "eof reached at 1", "length read as 0x5932")

-- ---------------------------------------------------------------- guard
wire = {}
eq(player:sendExtendedOpcode(120, big), false, "too big: refused")
eq(#wire, 0, "nothing written")
eq(#printed, 1, "one warning")
eq(printed[1]:find("extended opcode 120 to Tester: 20267 bytes", 1, true) ~= nil, true, "the warning names it")
eq(player:sendExtendedOpcode(89, 0), true, "a number is sent as text")
eq(wire[1], "\50\89\1\0\48", "32 59 01 00 30")
eq(player:sendExtendedOpcode(5, nil), true, "nil is the empty string")
eq(wire[2], "\50\5\0\0", "32 05 00 00")
local exact = string.rep("y", 8192)
eq(player:sendExtendedOpcode(7, exact), true, "8192 bytes still fit")
eq(#wire[3], 8196, "header and all of it")
player.otc = false
eq(player:sendExtendedOpcode(7, "a"), false, "not an OTClient")
player.otc = true

-- ---------------------------------------------------------------- split and send
eq(#Chaos.splitExtended("{}"), 1, "small: one part")
eq(Chaos.splitExtended("{}")[1], "{}", "unchanged")
eq(#Chaos.splitExtended(exact), 1, "exactly the limit: unchanged")
local parts = Chaos.splitExtended(big)
eq(#parts, 3, "20267 bytes in parts of 8000")
eq(parts[1]:sub(1, 2), "S{", "start")
eq(parts[2]:sub(1, 1), "P", "part")
eq(parts[3]:sub(1, 1), "E", "end")
for _, p in ipairs(parts) do
	eq(#p <= Chaos.extendedOpcodeMax, true, "every part fits")
end
eq(join(parts), big, "the client gets the payload back")
eq(#Chaos.splitExtended(string.rep("z", 8193)), 2, "one byte over: start and end")
eq(join(Chaos.splitExtended(string.rep("z", 8193))), string.rep("z", 8193), "start + end joined")
eq(#Chaos.splitExtended(string.rep("z", 9000), 100000), 2, "a part size over the limit is capped")

wire = {}
eq(Chaos.sendChunked(player, 120, big), true, "sent in parts")
eq(player:sendExtendedOpcode(89, "0"), true, "the reply after it")
local all = parse(table.concat(wire))
eq(all ~= nil, true, "the client reads the whole network message")
eq(#all, 4, "three parts and the reply")
eq(all[4].op, 89, "the reply is not lost")
eq(join({all[1].buffer, all[2].buffer, all[3].buffer}), big, "catalog joined")
eq(Chaos.sendChunked(nil, 120, big), false, "no player")

print = realPrint
print(string.format("extended_opcode_test: %d checks passed", checks))
