-- Player reports: pure logic (no engine API). reports.lua stores them (chaos_reports), tests/antibot_test.lua checks
-- this file. Numbers: antibot_config.lua `reports`.
--   R.validate(cfg, input, reporter)            the dialog's fields -> clean {target, reason, note} or nil, error key
--   R.allow(state, cfg, reporter, targetGuid, now)  cooldowns and limits against abuse -> true or nil, error key
--   R.chatPush(state, cfg, guid, channel, text, now) / R.chatLines(state, guid)   last public-channel lines
--   R.discordPayload(row), R.validWebhook(url)  the optional webhook post (no chat lines, no note)
-- Privacy: only public channels reach chatPush (reports.lua checks the channel), never private messages; the lines of a
-- character are kept in memory only and leave it chatKeepMinutes after its logout.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosReportsCore = ChaosReportsCore or {}
local R = ChaosReportsCore

R.errors = {
	disabled = "Player reports are switched off.",
	name = "Type the name of the character you want to report.",
	self = "You cannot report yourself.",
	unknown = "There is no character with that name.",
	staff = "Staff members cannot be reported here; write to another staff member.",
	reason = "Choose a reason.",
	note = "Describe the problem in the note (reason Other).",
	level = "You need a higher level to send reports.",
	cooldown = "Please wait a moment before sending another report.",
	day = "You sent the most reports allowed today. Thank you; staff will look at them.",
	same = "You already reported this character recently. Staff will look at it."
}

function R.reasonOf(cfg, key)
	for _, r in ipairs(cfg.reasons) do
		if r.key == key then
			return r
		end
	end
	return nil
end

-- printable ASCII, one line, at most `max` characters
function R.clean(text, max)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("[%c]", " "):gsub("[\128-\255]", ""):gsub("%s+", " ")
	text = text:gsub("^%s+", ""):gsub("%s+$", "")
	if max and #text > max then
		text = text:sub(1, max)
	end
	return text
end

-- character names: letters, space, apostrophe, hyphen; 2..29
function R.validName(name)
	return type(name) == "string" and #name >= 2 and #name <= 29 and name:match("^[A-Za-z][A-Za-z '%-]*$") ~= nil
end

-- input = {name, reason, note}; reporter = {guid, name, level}
function R.validate(cfg, input, reporter)
	if cfg.enabled == false then
		return nil, "disabled"
	end
	input = type(input) == "table" and input or {}
	local name = R.clean(input.name, 29)
	if not R.validName(name) then
		return nil, "name"
	end
	if reporter and reporter.name and name:lower() == tostring(reporter.name):lower() then
		return nil, "self"
	end
	if reporter and (reporter.level or 0) < (cfg.minLevel or 0) then
		return nil, "level"
	end
	local reason = R.reasonOf(cfg, input.reason)
	if not reason then
		return nil, "reason"
	end
	local note = R.clean(input.note, cfg.noteMax)
	if reason.key == "other" and #note < 3 then
		return nil, "note"
	end
	return {name = name, reason = reason.key, note = note}
end

-- ---------------------------------------------------------------- limits
function R.newState()
	return {byReporter = {}, chat = {}}
end

local function dayOf(now)
	return math.floor(now / 86400)
end

-- reporter = {account (limits are per account), guid}
function R.allow(state, cfg, reporter, targetGuid, now)
	local key = reporter.account or reporter.guid
	local r = state.byReporter[key]
	if not r then
		return true
	end
	if r.last and now - r.last < cfg.cooldownSeconds then
		return nil, "cooldown"
	end
	if r.day == dayOf(now) and r.count >= cfg.perDay then
		return nil, "day"
	end
	local t = r.targets[targetGuid]
	if t and now - t < cfg.sameTargetHours * 3600 then
		return nil, "same"
	end
	return true
end

function R.record(state, cfg, reporter, targetGuid, now)
	local key = reporter.account or reporter.guid
	local r = state.byReporter[key]
	if not r then
		r = {targets = {}, count = 0, day = dayOf(now)}
		state.byReporter[key] = r
	end
	if r.day ~= dayOf(now) then
		r.day, r.count = dayOf(now), 0
	end
	r.count = r.count + 1
	r.last = now
	r.targets[targetGuid] = now
	-- forget targets past the window (bounded memory)
	for g, t in pairs(r.targets) do
		if now - t >= cfg.sameTargetHours * 3600 then
			r.targets[g] = nil
		end
	end
end

-- ---------------------------------------------------------------- public chat lines
function R.chatPush(state, cfg, guid, channel, text, now)
	local list = state.chat[guid]
	if not list then
		list = {lines = {}}
		state.chat[guid] = list
	end
	list.lines[#list.lines + 1] = {at = now, ch = R.clean(channel, 24), text = R.clean(text, cfg.chatLineMax)}
	while #list.lines > cfg.chatLines do
		table.remove(list.lines, 1)
	end
	list.gone = nil
end

function R.chatLines(state, guid, fmtTime)
	local out = {}
	local list = state.chat[guid]
	for _, l in ipairs(list and list.lines or {}) do
		out[#out + 1] = string.format("[%s] %s: %s", fmtTime and fmtTime(l.at) or tostring(l.at), l.ch, l.text)
	end
	return out
end

-- logout: the lines stay chatKeepMinutes (a report right after the target left still has them)
function R.chatGone(state, guid, now)
	local list = state.chat[guid]
	if list then
		list.gone = now
	end
end

function R.chatSweep(state, cfg, now)
	for guid, list in pairs(state.chat) do
		if list.gone and now - list.gone >= cfg.chatKeepMinutes * 60 then
			state.chat[guid] = nil
		end
	end
end

-- ---------------------------------------------------------------- webhook
function R.validWebhook(url)
	if type(url) ~= "string" then
		return false
	end
	return url:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+$") ~= nil or
		url:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+$") ~= nil
end

function R.discordPayload(row)
	return {content = string.format("New player report #%d: %s - %s reported %s.", row.id or 0, row.reason or "?",
		row.reporter_name or "?", row.target_name or "?"), allowed_mentions = {parse = {}}}
end

-- ---------------------------------------------------------------- staff text
function R.statusText(status)
	return status == "closed" and "closed" or "open"
end

function R.listLine(row, fmtTime)
	return string.format("#%d %s %s: %s reported %s%s", row.id, R.statusText(row.status),
		fmtTime and fmtTime(row.created_at) or tostring(row.created_at), row.reporter_name, row.target_name,
		string.format(" (%s, suspicion %d)", row.reason, row.suspicion or 0))
end

return R
