-- Ember, the Help channel assistant: the pure part (helpai.lua; server/README.md "Help channel assistant").
-- Which Help channel lines are questions, the per-character and server limits, the queue and answer lines shared with
-- server/tools/helpai.py (flat JSON objects, one per line; encoded and decoded here so nothing depends on the engine's
-- json), splitting an answer into chat lines, and whether the channel is too busy for public answers.
-- Tested by tests/helpai_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

ChaosHelpAICore = ChaosHelpAICore or {}
local H = ChaosHelpAICore

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function countWords(s)
	local n = 0
	for _ in s:gmatch("%S+") do
		n = n + 1
	end
	return n
end

-- control characters out, runs of spaces as one
function H.clean(text)
	if type(text) ~= "string" then
		return ""
	end
	text = text:gsub("[%c\127]", " ")
	return trim(text:gsub("%s+", " "))
end

-- a Help channel line -> the question and whether the player called Ember on purpose; nil and a reason otherwise
--   "?how do I ascend"          explicit
--   "Ember, how do I ascend"    explicit (also "Ember: ..." and "@Ember ...")
--   "how do I ascend?"          automatic, when cfg.autoQuestions and the speaker is below tutor
function H.detect(message, cfg, isStaff)
	local text = H.clean(message)
	if text == "" then
		return nil, "empty"
	end
	local bot = (cfg.botName or "Ember"):lower()
	local lower = text:lower()
	local q, explicit
	if text:sub(1, 1) == "?" then
		q, explicit = trim(text:sub(2)), true
	elseif lower:sub(1, #bot + 1) == "@" .. bot then
		q, explicit = trim(text:sub(#bot + 2):gsub("^[,:%s]+", "")), true
	elseif lower:sub(1, #bot) == bot and (text:sub(#bot + 1, #bot + 1)):match("^[,:]$") then
		q, explicit = trim(text:sub(#bot + 1):gsub("^[,:%s]+", "")), true
	elseif cfg.autoQuestions and not isStaff and text:sub(-1) == "?" and countWords(text) >= (cfg.autoMinWords or 3)
			and not text:match("^[!/#@]") then
		q, explicit = text, false
	else
		return nil, "not a question"
	end
	if #q < (cfg.minQuestionChars or 6) then
		return nil, "short", explicit
	end
	if #q > (cfg.maxQuestionChars or 200) then
		return nil, "long", explicit
	end
	return q, explicit
end

function H.newState()
	return {last = {}, day = {}, dayKey = nil, minute = {}, public = {}, pending = {}, nextId = 0}
end

local function prune(list, now, span)
	local out = {}
	for _, t in ipairs(list) do
		if now - t < span then
			out[#out + 1] = t
		end
	end
	return out
end

-- may this character ask now? true, or false and a reason ("pending", "cooldown" with the seconds left, "day",
-- "busy")
function H.allow(state, cfg, guid, now, dayKey)
	if state.dayKey ~= dayKey then
		state.dayKey, state.day = dayKey, {}
	end
	for id, p in pairs(state.pending) do
		if p.guid == guid and now - p.t < (cfg.pendingSeconds or 90) then
			return false, "pending"
		end
	end
	local last = state.last[guid]
	local cd = cfg.cooldownSeconds or 20
	if last and now - last < cd then
		return false, "cooldown", cd - (now - last)
	end
	if (state.day[guid] or 0) >= (cfg.perDay or 30) then
		return false, "day"
	end
	state.minute = prune(state.minute, now, 60)
	if #state.minute >= (cfg.globalPerMinute or 20) then
		return false, "busy"
	end
	return true
end

-- counts the question and remembers it until its answer; returns its id
function H.record(state, guid, name, lang, explicit, now)
	state.nextId = state.nextId + 1
	local id = tostring(now) .. "-" .. tostring(state.nextId)
	state.last[guid] = now
	state.day[guid] = (state.day[guid] or 0) + 1
	state.minute[#state.minute + 1] = now
	state.pending[id] = {guid = guid, name = name, lang = lang, explicit = explicit, t = now}
	return id
end

-- the pending question of an answer (removed), or nil; old ones are forgotten on the way
function H.claim(state, cfg, id, now)
	for pid, p in pairs(state.pending) do
		if now - p.t >= (cfg.pendingSeconds or 90) then
			state.pending[pid] = nil
		end
	end
	local p = state.pending[id]
	state.pending[id] = nil
	return p
end

-- ---------------------------------------------------------------- flat JSON (strings, numbers, booleans)
local ESC = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}

local function encodeString(s)
	s = s:gsub('[%c"\\\127]', function(c)
		return ESC[c] or string.format("\\u%04x", c:byte())
	end)
	return '"' .. s .. '"'
end

-- one object, keys sorted (the same bytes every time)
function H.encode(obj)
	local keys = {}
	for k in pairs(obj) do
		keys[#keys + 1] = tostring(k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		local v = obj[k]
		local s
		if type(v) == "number" then
			s = (v == math.floor(v) and math.abs(v) < 2 ^ 53) and string.format("%d", v) or string.format("%.14g", v)
		elseif type(v) == "boolean" then
			s = v and "true" or "false"
		else
			s = encodeString(tostring(v))
		end
		parts[#parts + 1] = encodeString(k) .. ":" .. s
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function utf8char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
	return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
		0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local SIMPLE = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}

-- reads a string starting at the quote at i; returns the text and the position after the closing quote
local function readString(s, i)
	local out, j = {}, i + 1
	while j <= #s do
		local c = s:sub(j, j)
		if c == '"' then
			return table.concat(out), j + 1
		elseif c == "\\" then
			local e = s:sub(j + 1, j + 1)
			if SIMPLE[e] then
				out[#out + 1] = SIMPLE[e]
				j = j + 2
			elseif e == "u" then
				local hex = s:sub(j + 2, j + 5)
				if not hex:match("^%x%x%x%x$") then
					return nil
				end
				local cp = tonumber(hex, 16)
				j = j + 6
				if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
					local lo = tonumber(s:sub(j + 2, j + 5), 16)
					if lo and lo >= 0xDC00 and lo <= 0xDFFF then
						cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
						j = j + 6
					end
				end
				out[#out + 1] = utf8char(cp)
			else
				return nil
			end
		else
			out[#out + 1] = c
			j = j + 1
		end
	end
	return nil
end

-- one flat object -> table, or nil; nested arrays and objects are refused
function H.decode(line)
	if type(line) ~= "string" then
		return nil
	end
	local i = line:find("%S")
	if not i or line:sub(i, i) ~= "{" then
		return nil
	end
	local obj = {}
	i = line:find("%S", i + 1)
	if i and line:sub(i, i) == "}" then
		return obj
	end
	while i do
		if line:sub(i, i) ~= '"' then
			return nil
		end
		local key, j = readString(line, i)
		if not key then
			return nil
		end
		j = line:find("%S", j)
		if not j or line:sub(j, j) ~= ":" then
			return nil
		end
		j = line:find("%S", j + 1)
		if not j then
			return nil
		end
		local c, value = line:sub(j, j), nil
		if c == '"' then
			value, j = readString(line, j)
			if value == nil then
				return nil
			end
		elseif line:sub(j, j + 3) == "true" then
			value, j = true, j + 4
		elseif line:sub(j, j + 4) == "false" then
			value, j = false, j + 5
		elseif line:sub(j, j + 3) == "null" then
			value, j = nil, j + 4
		else
			local num = line:match("^-?%d+%.?%d*[eE]?[-+]?%d*", j)
			if not num or num == "" or not tonumber(num) then
				return nil
			end
			value, j = tonumber(num), j + #num
		end
		obj[key] = value
		j = line:find("%S", j)
		if not j then
			return nil
		end
		c = line:sub(j, j)
		if c == "}" then
			return obj
		elseif c ~= "," then
			return nil
		end
		i = line:find("%S", j + 1)
	end
	return nil
end

-- true when s is valid UTF-8
function H.isUtf8(s)
	local i, n = 1, #s
	while i <= n do
		local b = s:byte(i)
		local len = b < 0x80 and 1 or (b >= 0xC2 and b <= 0xDF) and 2 or (b >= 0xE0 and b <= 0xEF) and 3
			or (b >= 0xF0 and b <= 0xF4) and 4 or nil
		if not len or i + len - 1 > n then
			return false
		end
		for k = i + 1, i + len - 1 do
			local c = s:byte(k)
			if c < 0x80 or c > 0xBF then
				return false
			end
		end
		i = i + len
	end
	return true
end

-- player text as UTF-8: the client sends its own 8-bit encoding (Latin-1 for the Portuguese letters), the sidecar
-- reads UTF-8; text that is UTF-8 already is kept
function H.toUtf8(s)
	if H.isUtf8(s) then
		return s
	end
	return (s:gsub("[\128-\255]", function(c)
		return utf8char(c:byte())
	end))
end

-- the queue line for one question (server -> sidecar)
function H.queueLine(id, guid, lang, text, now)
	return H.encode({id = id, guid = guid, lang = lang == "pt-BR" and "pt-BR" or "en", text = H.toUtf8(text), t = now})
end

local STATUSES = {ok = true, limit = true, busy = true, off = true, refused = true}

-- the answer file -> list of {id, guid, status, text}; bad lines are skipped (at most maxLines)
function H.parseAnswers(text, maxLines)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	for line in text:gmatch("[^\n]+") do
		if #out >= (maxLines or 50) then
			break
		end
		local a = H.decode(line)
		if a and a.id ~= nil and STATUSES[a.status] then
			out[#out + 1] = {id = tostring(a.id), guid = tonumber(a.guid), status = a.status,
				text = type(a.text) == "string" and a.text or ""}
		end
	end
	return out
end

-- the sidecar's state from helpai.alive: "on", "budget" or "off"; nil when the file is missing, bad or stale
function H.aliveState(text, now, maxAge)
	local a = H.decode(text or "")
	if not a or type(a.t) ~= "number" or now - a.t > (maxAge or 30) or now - a.t < -60 then
		return nil
	end
	if a.state == "on" or a.state == "budget" or a.state == "off" then
		return a.state
	end
	return nil
end

-- ---------------------------------------------------------------- chat lines
-- the last byte where a cut keeps UTF-8 characters whole (a continuation byte is 0x80-0xBF)
local function utf8Cut(s, n)
	while n > 0 and n < #s do
		local b = s:byte(n + 1)
		if b < 0x80 or b >= 0xC0 then
			break
		end
		n = n - 1
	end
	return n
end

-- an answer -> at most maxLines lines of at most maxLen bytes, cut between words (a word longer than a line is cut
-- between characters); "..." marks text that did not fit
function H.split(text, maxLen, maxLines)
	text = H.clean(text)
	maxLen, maxLines = maxLen or 240, maxLines or 4
	local lines = {}
	while #text > 0 do
		if #lines == maxLines then
			local last = lines[#lines]
			if #last + 3 > maxLen then
				last = last:sub(1, utf8Cut(last, maxLen - 3))
			end
			lines[#lines] = last .. "..."
			break
		end
		if #text <= maxLen then
			lines[#lines + 1] = text
			break
		end
		local cut = 0
		for pos in text:sub(1, maxLen + 1):gmatch("()%s") do
			if pos - 1 <= maxLen then
				cut = pos - 1
			end
		end
		if cut < maxLen / 2 then
			cut = utf8Cut(text, maxLen)
		end
		lines[#lines + 1] = trim(text:sub(1, cut))
		text = trim(text:sub(cut + 1))
	end
	return lines
end

-- "public" (everyone in the channel) or "private" (the asker only) for the next answer; public answers are counted
function H.audience(state, cfg, now)
	state.public = prune(state.public, now, 60)
	if #state.public >= (cfg.publicPerMinute or 6) then
		return "private"
	end
	state.public[#state.public + 1] = now
	return "public"
end

-- a fixed reply in the player's language (English when there is none)
function H.text(cfg, lang, key, ...)
	local t = cfg.texts or {}
	local s = (t[lang] and t[lang][key]) or (t.en and t.en[key]) or key
	if select("#", ...) > 0 then
		local ok, out = pcall(string.format, s, ...)
		return ok and out or s
	end
	return s
end

return H
