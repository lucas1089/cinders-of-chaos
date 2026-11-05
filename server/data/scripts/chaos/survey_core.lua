-- New player survey, pure logic (survey.lua; numbers in survey_config.lua; tests/survey_test.lua; server/README.md "New
-- player funnel and survey (O374)"). No engine call here.
--   S.cleanText(text, max)                    one line of valid UTF-8 (1 to 3 bytes a letter), at most `max` letters
--   S.bit(mask, i) / S.setBit(mask, i)        the stage bits of the player storage cfg.storage
--   S.stageIndex(stage, cfg)                  the index of a stage in cfg.stages, or nil
--   S.dueAtLogin(level, mask, cfg)            the stage to offer at a login: the highest stage s with s <= level < s + window
--                                             whose bit is clear, or nil
--   S.dueAtAdvance(old, new, mask, cfg)       the highest stage crossed by a level up whose bit is clear, or nil
--   S.needsLookup(level, mask, cfg)           true when a stage could be due (the login asks the database then)
--   S.maskFromStages(mask, stages, cfg)       the mask with the bits of the stages the account already has rows for
--   S.parse(action, data, offered, cfg)       the client's answer / skip -> row {stage, status, fun, recommend, confused, source}, or nil
--                                             and a reason ("action", "stage", "empty" is no reason: an empty answer is a skip)
--   S.allowGlobal(state, now, cfg)            true while fewer than cfg.perMinute rows were written in this minute; counts it
--   S.createSql(t) / S.migrateSql(t) / S.insertSql(t, accountId, row, level, minutes, now, escape)
--   S.SOURCES                                 keys of "Where did you hear about the game?" (stage S.SOURCE_STAGE)
-- Lua 5.1 / LuaJIT and 5.3 compatible.

ChaosSurveyCore = ChaosSurveyCore or {}
local S = ChaosSurveyCore
local floor = math.floor

-- "Where did you hear about the game?" (asked at the first stage only; client surveylogic.lua L.SOURCES, same keys)
S.SOURCES = {"discord", "forum", "serverlist", "youtube", "shorts", "streamer", "friend", "search", "other"}
S.SOURCE_STAGE = 20
local SOURCE_OK = {}
for _, k in ipairs(S.SOURCES) do
	SOURCE_OK[k] = true
end

-- ---------------------------------------------------------------- text
-- Walks the bytes: keeps ASCII letters 32-126 and well formed 2- and 3-byte sequences (no surrogates, no overlongs);
-- a control character becomes a space, anything else is dropped. Spaces are folded and trimmed; at most `max` letters.
function S.cleanText(text, max)
	if type(text) ~= "string" then
		return ""
	end
	max = max or 200
	local out, letters, i, n = {}, 0, 1, #text
	local lastSpace = true
	while i <= n and letters < max do
		local b = text:byte(i)
		local piece, len
		if b < 32 or b == 127 then
			piece, len = " ", 1
		elseif b < 128 then
			piece, len = string.char(b), 1
		elseif b >= 0xC2 and b <= 0xDF then
			local c = text:byte(i + 1)
			if c and c >= 0x80 and c <= 0xBF then
				piece, len = text:sub(i, i + 1), 2
			end
		elseif b >= 0xE0 and b <= 0xEF then
			local c, d = text:byte(i + 1), text:byte(i + 2)
			local lo, hi = 0x80, 0xBF
			if b == 0xE0 then
				lo = 0xA0
			elseif b == 0xED then
				hi = 0x9F
			end
			if c and d and c >= lo and c <= hi and d >= 0x80 and d <= 0xBF then
				-- U+2028 / U+2029 line breaks and the U+200B - U+200F / U+202A - U+202E / U+2060 - U+2064 format
				-- characters would break a line of the report or turn the text around: dropped
				local cp = (b - 0xE0) * 4096 + (c - 0x80) * 64 + (d - 0x80)
				if not ((cp >= 0x200B and cp <= 0x200F) or (cp >= 0x2028 and cp <= 0x202E) or (cp >= 0x2060 and cp <= 0x2064)
					or cp == 0xFEFF) then
					piece = text:sub(i, i + 2)
				end
				len = 3
			end
		end
		if piece == " " then
			if not lastSpace then
				out[#out + 1] = " "
				letters = letters + 1
				lastSpace = true
			end
		elseif piece then
			out[#out + 1] = piece
			letters = letters + 1
			lastSpace = false
		end
		i = i + (len or 1)
	end
	local s = table.concat(out)
	return (s:gsub("^ +", ""):gsub(" +$", ""))
end

-- ---------------------------------------------------------------- stages
function S.bit(mask, i)
	mask = floor(tonumber(mask) or 0)
	if mask < 0 then
		return false
	end
	return floor(mask / 2 ^ (i - 1)) % 2 == 1
end

function S.setBit(mask, i)
	mask = floor(tonumber(mask) or 0)
	if mask < 0 then
		mask = 0
	end
	if S.bit(mask, i) then
		return mask
	end
	return floor(mask + 2 ^ (i - 1))
end

function S.stageIndex(stage, cfg)
	stage = tonumber(stage)
	for i, s in ipairs(cfg.stages) do
		if s == stage then
			return i
		end
	end
	return nil
end

function S.dueAtLogin(level, mask, cfg)
	level = tonumber(level) or 0
	for i = #cfg.stages, 1, -1 do
		local s = cfg.stages[i]
		if level >= s and level < s + cfg.window and not S.bit(mask, i) then
			return s
		end
	end
	return nil
end

function S.dueAtAdvance(oldLevel, newLevel, mask, cfg)
	oldLevel, newLevel = tonumber(oldLevel) or 0, tonumber(newLevel) or 0
	for i = #cfg.stages, 1, -1 do
		local s = cfg.stages[i]
		if oldLevel < s and newLevel >= s and not S.bit(mask, i) then
			return s
		end
	end
	return nil
end

function S.needsLookup(level, mask, cfg)
	return S.dueAtLogin(level, mask, cfg) ~= nil
end

function S.maskFromStages(mask, stages, cfg)
	for _, st in ipairs(stages or {}) do
		local i = S.stageIndex(st, cfg)
		if i then
			mask = S.setBit(mask, i)
		end
	end
	return floor(tonumber(mask) or 0)
end

-- ---------------------------------------------------------------- the answer
-- data = {s, fun, rec, text, src}; offered = the stage the server opened the window for this character
function S.parse(action, data, offered, cfg)
	if action ~= "answer" and action ~= "skip" then
		return nil, "action"
	end
	data = type(data) == "table" and data or {}
	if not offered or tonumber(data.s) ~= offered or not S.stageIndex(offered, cfg) then
		return nil, "stage"
	end
	local row = {stage = offered, status = "skipped", fun = 0, recommend = -1, confused = "", source = ""}
	if action == "skip" then
		return row
	end
	local fun = tonumber(data.fun)
	if fun and fun == floor(fun) and fun >= 1 and fun <= 5 then
		row.fun = fun
	end
	if data.rec == true then
		row.recommend = 1
	elseif data.rec == false then
		row.recommend = 0
	end
	row.confused = S.cleanText(data.text, cfg.textMax)
	if offered == S.SOURCE_STAGE and type(data.src) == "string" and SOURCE_OK[data.src] then
		row.source = data.src
	end
	if row.fun > 0 or row.recommend >= 0 or row.confused ~= "" or row.source ~= "" then
		row.status = "answered"
	end
	return row
end

function S.allowGlobal(state, now, cfg)
	local minute = floor(now / 60)
	if state.minute ~= minute then
		state.minute, state.count = minute, 0
	end
	if state.count >= (cfg.perMinute or 60) then
		return false
	end
	state.count = state.count + 1
	return true
end

-- ---------------------------------------------------------------- SQL
function S.createSql(t)
	return "CREATE TABLE IF NOT EXISTS `" .. t .. "` (" ..
		"`id` int(10) unsigned NOT NULL AUTO_INCREMENT, `account_id` int(10) unsigned NOT NULL, " ..
		"`stage` smallint(5) unsigned NOT NULL, `status` varchar(8) NOT NULL, `fun` tinyint(3) NOT NULL DEFAULT 0, " ..
		"`recommend` tinyint(3) NOT NULL DEFAULT -1, `confused` varchar(200) NOT NULL DEFAULT '', " ..
		"`source` varchar(16) NOT NULL DEFAULT '', " ..
		"`level` int(10) unsigned NOT NULL DEFAULT 0, `minutes` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`created_at` int(10) unsigned NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `account_stage` (`account_id`, `stage`), " ..
		"KEY `created_at` (`created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

-- a table of the first version gets the source column (MariaDB's ADD COLUMN IF NOT EXISTS)
function S.migrateSql(t)
	return "ALTER TABLE `" .. t .. "` ADD COLUMN IF NOT EXISTS `source` varchar(16) NOT NULL DEFAULT '' AFTER `confused`"
end

-- INSERT IGNORE: the unique key (account, stage) keeps the first row (a second character of the account, a race)
function S.insertSql(t, accountId, row, level, minutes, now, escape)
	local status = row.status == "answered" and "answered" or "skipped"
	return string.format("INSERT IGNORE INTO `%s` (`account_id`, `stage`, `status`, `fun`, `recommend`, `confused`, " ..
		"`source`, `level`, `minutes`, `created_at`) VALUES (%d, %d, %s, %d, %d, %s, %s, %d, %d, %d)", t, floor(accountId),
		floor(row.stage), escape(status), floor(row.fun), floor(row.recommend), escape(row.confused or ""),
		escape(SOURCE_OK[row.source] and row.source or ""),
		math.max(0, floor(tonumber(level) or 0)), math.max(0, floor(tonumber(minutes) or 0)), floor(now))
end

function S.stagesSql(t, accountId)
	return string.format("SELECT `stage` FROM `%s` WHERE `account_id` = %d", t, floor(accountId))
end
