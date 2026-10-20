-- Shadow mute for the PUBLIC chat channels (World Chat, English Chat, Advertising, Help ...): the staff actions
-- players.shadow_mute / players.shadow_unmute (admin/actions_players.lua) mark a character; its lines are then shown to
-- itself only. Pure logic: shadow_mute_core.lua (tests/shadow_mute_test.lua); overview: server/README.md "Shadow mute".
-- The hook is added to the channel scripts by tools/patch_shadow_mute.py. Normal speech (say, yell, whisper) and private
-- messages are engine paths without a Lua hook and are not covered: use the plain mute for those.
-- The mute is kept in memory: a restart clears it. Lua 5.1 / LuaJIT compatible.

if not ChaosShadowMuteCore then
	dofile("data/scripts/chaos/shadow_mute_core.lua")
end

ChaosShadowMute = ChaosShadowMute or {}
local SM = ChaosShadowMute
local C = ChaosShadowMuteCore
SM.state = SM.state or C.newState()

function SM.mute(player, minutes, maxMinutes)
	return C.mute(SM.state, player:getGuid(), minutes, os.time(), maxMinutes)
end

function SM.unmute(player)
	return C.unmute(SM.state, player:getGuid())
end

function SM.remaining(player)
	return C.remaining(SM.state, player:getGuid(), os.time())
end

-- Called first in onSpeak of every public channel script (tools/patch_shadow_mute.py): true = the line was swallowed
-- (the caller returns false), after the speaker got its own line back as if it had been sent.
function SM.onChannelSpeak(player, channelId, talkType, message)
	if not player or type(message) ~= "string" or not C.isMuted(SM.state, player:getGuid(), os.time()) then
		return false
	end
	pcall(function() player:sendChannelMessage(player:getName(), message, talkType, channelId) end)
	return true
end
