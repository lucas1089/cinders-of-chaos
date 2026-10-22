-- instance_limits_core.lua: the shared rules of time limits, warnings, idle closing, caps and the waiting line of every
-- instance (rift, Descent, raid, Ascended Omens, guild boss, trials, tower, dungeons, base boss rooms, ...). Pure Lua,
-- no engine calls; glue: instance_limits.lua; numbers: instance_limits_config.lua and each system's *_config.lua
-- (`limits`). Tests: tests/instance_limits_test.lua. server/README.md "Instance limits". Lua 5.1 / LuaJIT and 5.3.
--
--   K.warning(state, left, marks)       -> the mark (seconds) to announce now, or nil. Each mark once per run; a mark
--                                          already behind at the first call is never announced (a 3 minute run gets no
--                                          "5 minutes left"); two marks crossed in one call give the smaller one.
--   K.idle(state, now, occupied, grace) -> true when nobody was inside for grace seconds (state keeps emptySince)
--   K.eta(lefts, position)              -> seconds until the position-th place in line can enter (lefts: seconds left
--                                          of each running instance; nil when unknown)
--   K.busyText(what, eta, position)     -> "All rifts are busy. Try again in ~4 min. You are 2nd in line: ..."
--   K.leftText(sec), K.clock(sec), K.about(sec)
--   K.waitAdd / waitRemove / waitPos / waitNext / waitPrune(list, ...)   a waiting line per instance type
--   K.limits(defaults, own)             -> the system's limits table over the shared defaults

ChaosInstanceLimitsCore = ChaosInstanceLimitsCore or {}
local K = ChaosInstanceLimitsCore

-- K.about, K.leftText and K.busyText take an optional last `lang` ("pt-BR" | "en"): through ChaosI18n (i18n_core.lua)
-- when it is loaded, else English
local function T(lang, key, ...)
	if ChaosI18n and ChaosI18n.text then
		return ChaosI18n.text(lang, key, ...)
	end
	if select("#", ...) == 0 then
		return key
	end
	return string.format(key, ...)
end

local floor, max, min = math.floor, math.max, math.min

-- ------------------------------------------------------------------ numbers
function K.limits(defaults, own)
	local out = {}
	for k, v in pairs(defaults or {}) do
		out[k] = v
	end
	for k, v in pairs(own or {}) do
		out[k] = v
	end
	return out
end

-- ------------------------------------------------------------------ texts
function K.clock(sec)
	sec = max(0, floor(tonumber(sec) or 0))
	if sec >= 3600 then
		return string.format("%d:%02d:%02d", floor(sec / 3600), floor(sec % 3600 / 60), sec % 60)
	end
	return string.format("%d:%02d", floor(sec / 60), sec % 60)
end

-- a rough wait for a message: "under a minute", "~4 min", "~1 h 10 min"
function K.about(sec, lang)
	sec = max(0, floor(tonumber(sec) or 0))
	if sec < 60 then
		return T(lang, "under a minute")
	end
	local m = floor((sec + 59) / 60)
	if m < 60 then
		return "~" .. m .. " min"
	end
	local h = floor(m / 60)
	m = m % 60
	return m > 0 and string.format("~%d h %d min", h, m) or string.format("~%d h", h)
end

function K.leftText(sec, lang)
	sec = max(0, floor(tonumber(sec) or 0))
	if sec >= 120 and sec % 60 == 0 then
		return T(lang, "%s minutes left", floor(sec / 60))
	elseif sec == 60 then
		return T(lang, "1 minute left")
	elseif sec == 1 then
		return T(lang, "1 second left")
	end
	return T(lang, "%s seconds left", sec)
end

local function ordinal(n)
	local tens = n % 100
	if tens >= 11 and tens <= 13 then
		return n .. "th"
	end
	local last = n % 10
	return n .. (last == 1 and "st" or last == 2 and "nd" or last == 3 and "rd" or "th")
end
K.ordinal = ordinal

-- what: "rifts", "Descent halls", ... (plural; a key too)
function K.busyText(what, eta, position, lang)
	local text = T(lang, "All %s are busy.", T(lang, tostring(what or "instances")))
	if eta then
		text = text .. (eta < 60 and T(lang, " One frees up in under a minute.") or T(lang, " Try again in %s.", K.about(eta, lang)))
	else
		text = text .. T(lang, " Try again in a moment.")
	end
	if position then
		-- "2nd" in English, "2º" in pt-BR
		local nth = (ChaosI18n and ChaosI18n.normalize and ChaosI18n.normalize(lang) == "pt-BR") and (position .. "º") or ordinal(position)
		text = text .. T(lang, " You are %s in line: you will be told when one is free.", nth)
	end
	return text
end

-- ------------------------------------------------------------------ warnings
-- state: any table kept per run (the glue keeps it as run._limits). marks: seconds, any order.
function K.warning(state, left, marks)
	if type(state) ~= "table" or type(left) ~= "number" then
		return nil
	end
	local last = state.lastLeft
	state.lastLeft = left
	state.warned = state.warned or {}
	if last == nil then
		-- the first look: marks at or above the time left are behind already
		for _, m in ipairs(marks or {}) do
			if m >= left then
				state.warned[m] = true
			end
		end
		return nil
	end
	local pick
	for _, m in ipairs(marks or {}) do
		if not state.warned[m] and left <= m then
			state.warned[m] = true
			if not pick or m < pick then
				pick = m
			end
		end
	end
	return pick
end

-- ------------------------------------------------------------------ idle
-- occupied: somebody of the run is inside (or may come back right now). Returns true when the run should close.
function K.idle(state, now, occupied, grace)
	if type(state) ~= "table" then
		return false
	end
	if occupied then
		state.emptySince = nil
		return false
	end
	state.emptySince = state.emptySince or now
	return now - state.emptySince >= (grace or 0)
end

-- seconds an empty run has left before it closes (nil when it is not empty)
function K.idleLeft(state, now, grace)
	if type(state) ~= "table" or not state.emptySince then
		return nil
	end
	return max(0, (grace or 0) - (now - state.emptySince))
end

-- ------------------------------------------------------------------ caps
-- lefts: seconds left of each running instance (any order; nil / negative entries count as "soon"). position 1 is the
-- next in line. With n instances the k-th place waits for the k-th to end; past n it waits a whole round more (the
-- longest run seen), a rough guess that is never shorter than the truth for runs that use their whole time.
function K.eta(lefts, position, full)
	local list = {}
	for _, v in ipairs(lefts or {}) do
		list[#list + 1] = max(0, tonumber(v) or 0)
	end
	if #list == 0 then
		return nil
	end
	table.sort(list)
	position = max(1, floor(tonumber(position) or 1))
	local n = #list
	local round = floor((position - 1) / n)
	local idx = (position - 1) % n + 1
	return list[idx] + round * (tonumber(full) or list[n])
end

-- running: number of instances of the type; cap: the configured most (0 / nil = the grid alone decides)
function K.capReached(running, cap)
	cap = tonumber(cap) or 0
	return cap > 0 and (tonumber(running) or 0) >= cap
end

-- ------------------------------------------------------------------ the waiting line
-- list: an array of {id = key (player guid), name, at = os.time, untilAt}. ttl: seconds an entry stays.
function K.waitPrune(list, now)
	for i = #list, 1, -1 do
		if list[i].untilAt and now >= list[i].untilAt then
			table.remove(list, i)
		end
	end
end

function K.waitPos(list, id)
	for i, e in ipairs(list) do
		if e.id == id then
			return i
		end
	end
	return nil
end

-- adds (or keeps) the entry; returns its position
function K.waitAdd(list, id, now, ttl, name, max_)
	K.waitPrune(list, now)
	local pos = K.waitPos(list, id)
	if pos then
		list[pos].untilAt = ttl and now + ttl or nil
		return pos
	end
	if max_ and #list >= max_ then
		return nil
	end
	list[#list + 1] = {id = id, name = name, at = now, untilAt = ttl and now + ttl or nil}
	return #list
end

function K.waitRemove(list, id)
	local pos = K.waitPos(list, id)
	if pos then
		table.remove(list, pos)
		return true
	end
	return false
end

-- the first live entry, taken off the line (the glue tells that player, who may then enter like anyone else)
function K.waitNext(list, now)
	K.waitPrune(list, now)
	return table.remove(list, 1)
end

-- "Leave Boss Room" (Info & Services > Services, command id "leaveroom"; instance_limits.lua ChaosBossRooms.leave).
-- f: {inside (a running room holds the player), fight (pz lock or in battle: no free escape from a lost fight, as the
-- dungeon queue and the arena), cooldownLeft (seconds)}. The reason it is refused (a text for Chaos.t and its number),
-- or nil: the player may go out.
function K.leaveReason(f)
	f = f or {}
	if not f.inside then
		return "You are not in a boss room."
	end
	if f.fight then
		return "You cannot leave the boss room while you are in a fight."
	end
	local left = tonumber(f.cooldownLeft) or 0
	if left > 0 then
		return "You can leave the boss room again in %d s.", math.ceil(left)
	end
	return nil
end

return K
