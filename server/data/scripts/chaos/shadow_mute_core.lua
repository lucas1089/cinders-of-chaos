-- Shadow mute, pure logic (unit tested by tests/shadow_mute_test.lua). A shadow-muted character keeps seeing its own
-- lines in the public chat channels, but nobody else does, so a spammer does not notice the mute and does not switch
-- to a new account. State: state.until[guid] = os.time() when the mute ends. Lua 5.1 / LuaJIT / 5.3 compatible.
ChaosShadowMuteCore = {}
local M = ChaosShadowMuteCore

M.MAX_MINUTES = 1440 -- same ceiling as the staff ladder's mute (actions_players.lua)

function M.newState()
	return {untilAt = {}}
end

-- minutes clamped to 1 .. maxMinutes; returns the end time, or nil + reason for a bad guid
function M.mute(state, guid, minutes, now, maxMinutes)
	guid, now = tonumber(guid), tonumber(now)
	if not state or not guid or guid <= 0 or not now then
		return nil, "bad arguments"
	end
	local cap = tonumber(maxMinutes) or M.MAX_MINUTES
	local m = math.floor(tonumber(minutes) or 0)
	if m < 1 then m = 1 end
	if m > cap then m = cap end
	state.untilAt[guid] = now + m * 60
	return state.untilAt[guid]
end

function M.unmute(state, guid)
	guid = tonumber(guid)
	if not state or not guid or not state.untilAt[guid] then
		return false
	end
	state.untilAt[guid] = nil
	return true
end

-- seconds left (0 = not muted); an ended mute is forgotten on the way
function M.remaining(state, guid, now)
	guid, now = tonumber(guid), tonumber(now)
	local e = state and guid and state.untilAt[guid]
	if not e or not now then
		return 0
	end
	if now >= e then
		state.untilAt[guid] = nil
		return 0
	end
	return e - now
end

function M.isMuted(state, guid, now)
	return M.remaining(state, guid, now) > 0
end

-- guids and seconds left of every active mute, shortest first (for the staff list)
function M.list(state, now)
	local out = {}
	if state then
		for guid in pairs(state.untilAt) do
			local left = M.remaining(state, guid, now)
			if left > 0 then out[#out + 1] = {guid = guid, left = left} end
		end
	end
	table.sort(out, function(a, b) if a.left ~= b.left then return a.left < b.left end return a.guid < b.guid end)
	return out
end

return M
