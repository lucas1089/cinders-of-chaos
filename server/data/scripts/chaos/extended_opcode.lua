-- extended_opcode.lua: Player.sendExtendedOpcode that never writes a broken extended opcode message.
--
-- The base version (data/lib/core/player.lua) writes 0x32 and the opcode, then NetworkMessage:addString(buffer). The
-- engine refuses strings over 8192 bytes without an error, so a longer payload went out as the two bytes 32 <opcode>
-- with no length. The client then read the next message's first two bytes as the length, failed ("ProtocolGame parse
-- message exception (... 3 unread, last opcode is 0x32 ...)") and dropped everything after it in that network message.
-- This one sends nothing for such a payload and prints a warning naming the opcode; send big JSON with
-- Chaos.sendChunked (chaos_constants.lua) instead. Everything else is the base behaviour.
if not Chaos then dofile("data/scripts/chaos/chaos_constants.lua") end

function Player.sendExtendedOpcode(self, opcode, buffer)
	if not self:isUsingOtClient() then
		return false
	end
	if buffer == nil then
		buffer = ""
	end
	buffer = tostring(buffer)
	if #buffer > Chaos.extendedOpcodeMax then
		print(string.format("[Warning - Chaos] extended opcode %d to %s: %d bytes is over the engine's %d-byte string "
			.. "limit, not sent (use Chaos.sendChunked)", opcode, self:getName(), #buffer, Chaos.extendedOpcodeMax))
		return false
	end

	local networkMessage = NetworkMessage()
	networkMessage:addByte(0x32)
	networkMessage:addByte(opcode)
	networkMessage:addString(buffer)
	networkMessage:sendToPlayer(self)
	networkMessage:delete()
	return true
end
