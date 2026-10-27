-- Player reports: pure logic (no engine API). reports.lua stores them (chaos_reports), tests/antibot_test.lua checks
-- this file. Numbers: antibot_config.lua `reports`.
--   R.validate(cfg, input, reporter)            the dialog's fields -> clean {target, reason, note} or nil, error key
--   R.allow(state, cfg, reporter, targetGuid, now)  cooldowns and limits against abuse -> true or nil, error key
--   R.chatPush(state, cfg, guid, channel, text, now) / R.chatLines(state, guid)   last public-channel lines
--   R.discordPayload(row), R.validWebhook(url)  the optional webhook post (no chat lines, no note)
--   R.validateBug(bcfg, message, category) / R.allowBug / R.recordBug / R.bugPosition / R.bugDetails   bug reports
--                                               (System > Report a Bug; tests/bugreport_test.lua)
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
	same = "You already reported this character recently. Staff will look at it.",
	bugdisabled = "Bug reports are switched off. Please report the bug on our Discord.",
	bugshort = "Describe the bug in a few words (at least 6 characters).",
	bugrapid = "Please wait a moment before sending another bug report.",
	bugday = "You sent the most bug reports allowed today. Thank you; staff will read them."
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
	if row.reason == "bug" then
		-- the category and the place, never the player's text (it can hold anything)
		return {content = string.format("New bug report #%d (%s) from %s at %d, %d, %d.", row.id or 0,
			R.bugCategory(row.category), row.reporter_name or "?", row.pos_x or 0, row.pos_y or 0, row.pos_z or 0),
			allowed_mentions = {parse = {}}}
	end
	return {content = string.format("New player report #%d: %s - %s reported %s.", row.id or 0, row.reason or "?",
		row.reporter_name or "?", row.target_name or "?"), allowed_mentions = {parse = {}}}
end

-- ---------------------------------------------------------------- bug reports
-- System > Report a Bug in the client -> Player:onReportBug(message, position, category) (tools/patch_base_events.py
-- step 12) -> reports.lua RP.reportBug. Stored as a chaos_reports row: reason "bug", target = the reporter itself,
-- note "[category] text", the position (the reported map tile for a map report, else the character's), and in `chat`
-- the detail lines of R.bugDetails. cfg = antibot_config.lua reports.bugs.
-- 4 "suggestion": the base dialog has no such entry (base patch 0040 sends 0..3), so a player writes the prefix
-- "suggestion:" / "sugestao:" / "sugestão:" in the text (R.suggestionPrefix); a client that sends 4 is accepted too.
R.bugCategories = {[0] = "map", [1] = "typo", [2] = "technical", [3] = "other", [4] = "suggestion"}

-- the category name of a client category number (or of a name already given)
function R.bugCategory(category)
	for _, name in pairs(R.bugCategories) do
		if category == name then
			return name
		end
	end
	return R.bugCategories[tonumber(category) or 3] or "other"
end

-- a leading "suggestion:" / "suggestao:" / "sugestao:" / "sugestão:" (any case, UTF-8 or not) -> the text without it, or nil
function R.suggestionPrefix(message)
	if type(message) ~= "string" then
		return nil
	end
	local m = message:gsub("^%s+", ""):lower()
	for _, p in ipairs({"suggestion:", "sugestao:", "sugest\195\163o:", "sugest\195\131o:"}) do
		if m:sub(1, #p) == p then
			return (message:gsub("^%s+", ""):sub(#p + 1))
		end
	end
	return nil
end

-- message from the client -> {category, text, note, shortened} or nil, error key
function R.validateBug(cfg, message, category)
	if not cfg or cfg.enabled == false then
		return nil, "bugdisabled"
	end
	local stripped = R.suggestionPrefix(message)
	if stripped and R.bugCategory(category) == "other" then
		message, category = stripped, "suggestion"
	end
	local text = R.clean(message)
	if #text < (cfg.textMin or 6) then
		return nil, "bugshort"
	end
	local max = cfg.textMax or 240
	local shortened = #text > max
	if shortened then
		text = text:sub(1, max)
	end
	local cat = R.bugCategory(category)
	return {category = cat, text = text, note = "[" .. cat .. "] " .. text, shortened = shortened}
end

-- per account: cooldownSeconds between two, perDay a day (state.bugs; the per-character Chaos.limited is in reports.lua)
function R.allowBug(state, cfg, account, now)
	state.bugs = state.bugs or {}
	local r = state.bugs[account]
	if not r then
		return true
	end
	if r.last and now - r.last < (cfg.cooldownSeconds or 0) then
		return nil, "bugrapid"
	end
	if r.day == dayOf(now) and r.count >= (cfg.perDay or 10) then
		return nil, "bugday"
	end
	return true
end

function R.recordBug(state, account, now)
	state.bugs = state.bugs or {}
	local r = state.bugs[account]
	if not r or r.day ~= dayOf(now) then
		r = {day = dayOf(now), count = 0}
		state.bugs[account] = r
	end
	r.count = r.count + 1
	r.last = now
end

local function validPos(p)
	return type(p) == "table" and tonumber(p.x) and tonumber(p.y) and tonumber(p.z) and p.x > 0 and p.y > 0 and true or false
end

-- the stored position: the reported tile of a map report when the client sent one, else the character's
function R.bugPosition(category, reported, own)
	if R.bugCategory(category) == "map" and validPos(reported) then
		return {x = reported.x, y = reported.y, z = reported.z}, "reported tile"
	end
	return {x = own.x, y = own.y, z = own.z}, "character"
end

-- the detail lines stored in `chat`; info = {category, pos, posKind, own, level, vocation, at}
function R.bugDetails(info, fmtTime)
	local lines = {"Category: " .. info.category,
		string.format("Character position: %d, %d, %d", info.own.x, info.own.y, info.own.z)}
	if info.posKind == "reported tile" then
		lines[#lines + 1] = string.format("Reported map tile: %d, %d, %d", info.pos.x, info.pos.y, info.pos.z)
	end
	lines[#lines + 1] = string.format("Level %d, %s", info.level or 0, R.clean(tostring(info.vocation or "?"), 32))
	lines[#lines + 1] = "Sent " .. (fmtTime and fmtTime(info.at) or tostring(info.at))
	if info.shortened then
		lines[#lines + 1] = "(the text was shortened)"
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------- staff text
function R.statusText(status)
	return status == "closed" and "closed" or "open"
end

function R.listLine(row, fmtTime)
	if row.reason == "bug" then
		local note = tostring(row.note or "")
		if #note > 60 then
			note = note:sub(1, 57) .. "..."
		end
		return string.format("#%d %s %s: bug from %s at %d, %d, %d: %s", row.id, R.statusText(row.status),
			fmtTime and fmtTime(row.created_at) or tostring(row.created_at), row.reporter_name, row.pos_x or 0,
			row.pos_y or 0, row.pos_z or 0, note)
	end
	return string.format("#%d %s %s: %s reported %s%s", row.id, R.statusText(row.status),
		fmtTime and fmtTime(row.created_at) or tostring(row.created_at), row.reporter_name, row.target_name,
		string.format(" (%s, suspicion %d)", row.reason, row.suspicion or 0))
end

return R
