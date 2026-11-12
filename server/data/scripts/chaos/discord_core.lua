-- discord_core.lua: the Discord announcements without engine calls (discord.lua; tests: server/tests/discord_test.lua).
-- An event is {kind, channel, title, text, fields = {{name, value, inline}}}; the worker (website plugins/chaos/
-- discord_worker.php) turns a queue row into a Discord embed with the brand colour of its kind.
-- Lua 5.1 / LuaJIT and Lua 5.3.
--
--   ChaosDiscordCore.enabled(cfg, kind)                 the switch of an event type
--   ChaosDiscordCore.allow(state, cfg, kind, now)       the per-minute rate limit (state.window, state.dropped)
--   ChaosDiscordCore.drop(cfg, name, level, item, kind, details)   the drop feed post (O260); details: dropDetails (O519)
--   ChaosDiscordCore.dropDetails(tip, extra)           what a drop post says about an item, from its tooltip (O519)
--   ChaosDiscordCore.record / first / worldBossSpawn / bossKill / level / season / status   the events
--   ChaosDiscordCore.patchnotes(cfg, title, text)      the patch note post (patchnotes.lua, English and pt-BR rows)
--   ChaosDiscordCore.weeklyChallenge(cfg, label, theme, sections)   the Weekly Challenge's week (O390,
--                                                      weekly_challenge.lua): the top 3 of each class
--   ChaosDiscordCore.weeklyClass(cfg, label, boardName, sections)   a weekly class board's week (O409,
--                                                      weekly_class.lua): the podium of each class
--   ChaosDiscordCore.cityInvasion(cfg, phase, info)    an invasion starts, is won or is lost (O393, invasion.lua)
--   ChaosDiscordCore.milestones(old, new, list)        the milestone levels crossed by a level up
--   ChaosDiscordCore.saveTime(xml)                     hour, minute of the server save in globalevents.xml
--   ChaosDiscordCore.isDailyRestart(now, hour, min, window)   a shutdown inside the window after the save time
--   ChaosDiscordCore.insertSql(tbl, ev, now, esc, encode)     the queue INSERT
--   ChaosDiscordCore.schemaSql(tbl)                    CREATE TABLE IF NOT EXISTS (sql/chaos_discord.sql)

ChaosDiscordCore = ChaosDiscordCore or {}
local D = ChaosDiscordCore

local floor = math.floor

local function clip(s, n)
	s = tostring(s or "")
	if #s > n then
		return s:sub(1, n - 3) .. "..."
	end
	return s
end
D.clip = clip

function D.enabled(cfg, kind)
	if not cfg or cfg.enabled == false then
		return false
	end
	return (cfg.events or {})[kind] == true
end

-- at most perMinute[kind] (or .default) rows per kind in a minute; state = {window = {kind = {minute, n}}, dropped}
function D.allow(state, cfg, kind, now)
	state.window = state.window or {}
	local minute = floor((tonumber(now) or 0) / 60)
	local limits = cfg.perMinute or {}
	local limit = limits[kind] or limits.default or 6
	local w = state.window[kind]
	if not w or w.minute ~= minute then
		w = {minute = minute, n = 0}
		state.window[kind] = w
	end
	if w.n >= limit then
		state.dropped = (state.dropped or 0) + 1
		return false
	end
	w.n = w.n + 1
	return true
end

function D.clock(secs)
	secs = floor(tonumber(secs) or 0)
	if secs >= 3600 then
		return string.format("%d:%02d:%02d", floor(secs / 3600), floor(secs % 3600 / 60), secs % 60)
	end
	return string.format("%d:%02d", floor(secs / 60), secs % 60)
end

local function event(cfg, kind, title, text, fields)
	return {kind = kind, channel = (cfg.channels or {})[kind] or "default", title = clip(title, 250),
		text = clip(text, 2000), fields = fields or {}}
end

-- names: a list of character names -> "A, B and C" (at most max, "and N more")
function D.names(names, max)
	max = max or 8
	local list = {}
	for i = 1, math.min(#names, max) do
		list[#list + 1] = tostring(names[i])
	end
	local more = #names - #list
	if more > 0 then
		return table.concat(list, ", ") .. string.format(" and %d more", more)
	end
	if #list <= 1 then
		return list[1] or ""
	end
	return table.concat(list, ", ", 1, #list - 1) .. " and " .. list[#list]
end

-- ---------------------------------------------------------------- events
function D.record(cfg, text)
	return event(cfg, "record", "New record", text)
end

function D.first(cfg, text)
	return event(cfg, "first", "Realm first", text)
end

function D.worldBossSpawn(cfg, bossName, minLevel)
	local fields = {}
	if minLevel then
		fields[1] = {name = "Level", value = tostring(minLevel) .. "+", inline = true}
	end
	return event(cfg, "worldboss_spawn", "World boss: " .. tostring(bossName),
		string.format("%s stirs. The portals next to the temples are open.", tostring(bossName)), fields)
end

-- kind: worldboss_kill | ascended_kill | cinderheart_kill
function D.bossKill(cfg, kind, bossName, secs, names)
	local fields = {{name = "Time", value = D.clock(secs), inline = true},
		{name = "Fighters", value = tostring(#names), inline = true}}
	local verb = kind == "cinderheart_kill" and "extinguished" or "slain"
	return event(cfg, kind, tostring(bossName) .. " " .. verb,
		string.format("%s %s %s in %s.", D.names(names), #names == 1 and "has" or "have", verb == "slain" and
			("slain " .. tostring(bossName)) or "extinguished the Cinderheart", D.clock(secs)), fields)
end

-- O519: the item's data on a drop post. Discord's embed limits: 25 fields, a field name 256, a value 1024, the whole
-- embed 6000 characters (title, description, field names and values, footer). The worker adds the footer, so the
-- game keeps to cfg.dropBudget.
D.LIMITS = {fields = 25, name = 256, value = 1024, total = 6000}

-- the lines that fit in `max` bytes (never a line cut, except a single line longer than max), then "+N more" when some
-- were left out; a cut line never ends inside a UTF-8 character
local function clipLines(lines, max)
	local out, used = {}, 0
	for i, line in ipairs(lines) do
		line = tostring(line)
		local need = #line + (#out > 0 and 1 or 0)
		-- a line that is not the last must leave room for the "+N more" line after it
		local reserve = i < #lines and (#string.format("+%d more", #lines - i) + 1) or 0
		if used + need + reserve > max then
			if #out == 0 then
				local cut = line:sub(1, max - 3)
				while #cut > 0 and cut:byte(#cut) >= 0x80 and cut:byte(#cut) < 0xC0 do
					cut = cut:sub(1, #cut - 1) -- continuation bytes of a character cut in two
				end
				if #cut > 0 and cut:byte(#cut) >= 0xC0 then
					cut = cut:sub(1, #cut - 1) -- its lead byte
				end
				out[1] = cut .. "..."
			else
				out[#out + 1] = string.format("+%d more", #lines - i + 1)
			end
			break
		end
		out[#out + 1] = line
		used = used + need
	end
	return table.concat(out, "\n")
end
D.clipLines = clipLines

local function textLen(ev)
	local n = #ev.title + #ev.text
	for _, f in ipairs(ev.fields) do
		if f.name then
			n = n + #f.name + #f.value
		end
	end
	return n
end

-- the fields of a drop post inside Discord's limits: at most 25 real fields (the thumbnail entry has no name and does
-- not count), names and values clipped, the whole post within `budget` characters (the longest value is cut, a field
-- that would be left with a few characters goes)
function D.fitFields(ev, budget)
	budget = budget or D.LIMITS.total
	local fields, thumb = {}, nil
	for _, f in ipairs(ev.fields or {}) do
		if f.name == nil and f.thumbnail then
			thumb = f
		elseif f.name ~= nil and f.value ~= nil and #fields < D.LIMITS.fields then
			fields[#fields + 1] = {name = clip(f.name, D.LIMITS.name), value = clip(f.value, D.LIMITS.value),
				inline = f.inline and true or false}
		end
	end
	ev.fields = fields
	while #fields > 0 and textLen(ev) > budget do
		local worst = 1
		for i, f in ipairs(fields) do
			if #f.value > #fields[worst].value then
				worst = i
			end
		end
		local keep = #fields[worst].value - (textLen(ev) - budget)
		if keep < 8 then
			table.remove(fields, worst)
		else
			fields[worst].value = clip(fields[worst].value, keep)
		end
	end
	if thumb then
		fields[#fields + 1] = thumb
	end
	return ev
end

local function titleCase(s)
	local small = {of = true, the = true, a = true, an = true, ["and"] = true, ["in"] = true, on = true, to = true}
	local first = true
	return (tostring(s or ""):gsub("(%S+)", function(w)
		local low = w:lower()
		if not first and small[low] then
			return low
		end
		first = false
		return (low:gsub("^%l", string.upper))
	end))
end
D.titleCase = titleCase

local function number(v)
	v = tonumber(v) or 0
	if v == floor(v) then
		return string.format("%.0f", v)
	end
	return string.format("%g", v)
end

-- one row of the tooltip's base block (item_tooltip_core.lua T.baseStats: {k, l, v, fmt}) as a line; nil for the rows that
-- need a viewer (his interval, the estimated damage)
local function statLine(b)
	if type(b) ~= "table" or not b.l or b.v == nil or b.k == "yourinterval" or b.k == "dps" or b.fmt == "est" then
		return nil
	end
	if b.fmt == "pct" then
		return string.format("%s %s%%", b.l, number(b.v))
	elseif b.fmt == "sec" then
		return string.format("%s %ss", b.l, number(b.v))
	elseif b.fmt == "range" and b.lo and b.hi then
		return string.format("%s %s-%s", b.l, number(b.lo), number(b.hi))
	end
	return string.format("%s %s", b.l, number(b.v))
end

-- the modifier lines of a tooltip (tip.mods, quality, sockets, veil) in the words of the in-game tooltip: "Fire +5% dmg
-- (T2)", a corrupted implicit as "Implicit: ...", a bound one ", bound"
local function modLines(tip)
	local lines = {}
	for _, m in ipairs(tip.mods or {}) do
		if m.t and m.t ~= "" then
			local line = tostring(m.t)
			if m.tr then
				line = line .. string.format(" (T%d%s)", m.tr, m.bd and ", bound" or "")
			end
			if m.sd == "i" then
				line = "Implicit: " .. line
			end
			lines[#lines + 1] = line
		end
	end
	if type(tip.quality) == "table" and (tonumber(tip.quality.q) or 0) > 0 then
		lines[#lines + 1] = string.format("Quality +%s%%", number(tip.quality.q))
	end
	if type(tip.sockets) == "table" then
		for i, g in ipairs(tip.sockets.list or {}) do
			if g.name then
				lines[#lines + 1] = string.format("Socket %d: %s%s", i, g.name,
					(g.text and g.text ~= "") and (" (" .. g.text .. ")") or "")
			else
				lines[#lines + 1] = string.format("Socket %d: empty", i)
			end
		end
	end
	if type(tip.veil) == "table" then
		if tip.veil.s == "open" and tip.veil.n then
			lines[#lines + 1] = string.format("Veiled: %s%s", tip.veil.n, tip.veil.t and (", " .. tip.veil.t) or "")
		else
			lines[#lines + 1] = "Veiled modifier unrevealed"
		end
	end
	return lines
end

-- O519: what a drop post says about the item, read from the tooltip the game builds for the item (item_tooltip_core.lua
-- T.build; discord.lua X.dropDetails builds it, this only reads it, so the lines are the in-game ones and no rule is
-- copied). tip = that tooltip; extra = {baseName (the item type's own name), monster, place, iconUrl}. Returns {base,
-- stats = {lines}, reqLevel, reqMagic, classes, mods = {lines}, passive = "Name: rule", monster, place, iconUrl}.
function D.dropDetails(tip, extra)
	tip, extra = type(tip) == "table" and tip or {}, type(extra) == "table" and extra or {}
	local d = {monster = extra.monster, place = extra.place, iconUrl = extra.iconUrl}
	local slot = (type(tip.slot) == "string" and tip.slot ~= "" and tip.slot ~= "Container") and tip.slot or nil
	local base = extra.baseName
	if type(base) == "string" and base ~= "" and titleCase(base):lower() ~= tostring(tip.name or ""):lower() then
		d.base = titleCase(base) .. (slot and (" (" .. slot:lower() .. ")") or "")
	else
		d.base = slot
	end
	d.stats = {}
	for _, b in ipairs(tip.base or {}) do
		local line = statLine(b)
		if line then
			d.stats[#d.stats + 1] = line
		end
	end
	if type(tip.req) == "table" then
		d.reqLevel, d.reqMagic, d.classes = tonumber(tip.req.level), tonumber(tip.req.magic), tip.req.voc
	end
	d.mods = modLines(tip)
	if type(tip.passive) == "table" and tip.passive.name and tip.passive.text then
		d.passive = string.format("%s: %s", tip.passive.name, tip.passive.text)
	end
	return d
end

-- O260, the drop feed: a legendary, divine or unique drop. kind: "legendary" | "divine" | "unique"; item = the item's
-- name. O519 (owner 2026-11-12, "show the item's data"): details (optional, D.dropDetails) adds the fields Base,
-- Requires, Class (short, inline), Stats, Dropped by, Passive, Modifiers; cfg.dropDetails switches each part. The
-- thumbnail (details.iconUrl, the item's image on the website) is an entry {thumbnail = url} in the fields: the worker
-- checks and draws it (a worker without the feature skips an entry with no name). No details: the post of O260.
function D.drop(cfg, name, level, item, kind, details)
	local title = {legendary = "Legendary find", divine = "Divine find", unique = "Unique find"}
	local ev = event(cfg, "drop", title[kind] or "Rare find", string.format("%s (Lv %d) found %s!", tostring(name),
		floor(tonumber(level) or 0), tostring(item)))
	if type(details) ~= "table" then
		return ev
	end
	local on = cfg.dropDetails or {}
	local f = {}
	local function add(switch, n, v, inline)
		if on[switch] ~= false and type(v) == "string" and v ~= "" then
			f[#f + 1] = {name = n, value = v, inline = inline}
		end
	end
	add("base", "Base", details.base, true)
	if tonumber(details.reqLevel) then
		local v = "Level " .. number(details.reqLevel)
		if tonumber(details.reqMagic) then
			v = v .. ", magic level " .. number(details.reqMagic)
		end
		add("level", "Requires", v, true)
	end
	add("classes", "Class", details.classes and tostring(details.classes), true)
	if type(details.stats) == "table" and #details.stats > 0 then
		add("stats", "Stats", clipLines(details.stats, D.LIMITS.value), false)
	end
	local mon, place = details.monster, details.place
	local source
	if mon and mon ~= "" and place and place ~= "" then
		source = string.format("%s in %s", mon, place)
	else
		source = (mon and mon ~= "") and mon or place
	end
	add("source", "Dropped by", source and tostring(source), false)
	add("passive", "Passive", details.passive and tostring(details.passive), false)
	if type(details.mods) == "table" and #details.mods > 0 then
		add("mods", "Modifiers", clipLines(details.mods, D.LIMITS.value), false)
	end
	if on.icon ~= false and type(details.iconUrl) == "string" and details.iconUrl ~= "" then
		f[#f + 1] = {thumbnail = clip(details.iconUrl, 300)}
	end
	ev.fields = f
	return D.fitFields(ev, cfg.dropBudget or (D.LIMITS.total - 200))
end

function D.level(cfg, name, level, className)
	return event(cfg, "level", string.format("Level %d", level),
		string.format("%s%s reached level %d.", tostring(name), className and (" the " .. className) or "", level))
end

-- kind: season_start | season_end
function D.season(cfg, kind, season)
	local name = season and season.name or "The season"
	if kind == "season_start" then
		return event(cfg, kind, name .. " has begun", string.format("%s has begun. New characters can join in " ..
			"Adventure > Season.", name))
	end
	return event(cfg, kind, name .. " has ended", string.format("%s has ended. Its characters are standard " ..
		"characters now and keep everything.", name))
end

-- kind: status_up | status_down | status_restart
function D.status(cfg, kind, serverName)
	local s = tostring(serverName or "The server")
	local text = {status_up = s .. " is online.", status_down = s .. " is going down.",
		status_restart = s .. " is restarting after the daily server save. Back in a few minutes."}
	local title = {status_up = "Server online", status_down = "Server offline", status_restart = "Daily restart"}
	return event(cfg, kind, title[kind] or kind, text[kind] or s)
end

-- the milestone levels in list with old < m <= new (in order)
-- a new patch note (patchnotes.lua; the text is a digest in one language, cut to the embed size by the caller)
function D.patchnotes(cfg, title, text)
	return event(cfg, "patchnotes", title, text)
end

-- O390, the Weekly Challenge at the week's end: label "2026-W45", theme = the layout's theme name, sections = {{name
-- = class, value = "Solo: 1. A 5:12, ...\nParty: ..."}} (weekly_challenge_core.lua W.discordSections); at most 25
-- fields of 1024 characters (Discord's embed limits)
function D.weeklyChallenge(cfg, label, theme, sections)
	local fields = {}
	for i = 1, math.min(#(sections or {}), 25) do
		local s = sections[i]
		fields[i] = {name = clip(s.name, 256), value = clip(s.value, 1024), inline = false}
	end
	local text
	if #fields == 0 then
		text = string.format("Weekly Challenge %s (%s) has ended. Nobody cleared it this week.", tostring(label),
			tostring(theme))
	else
		text = string.format("Weekly Challenge %s (%s) has ended. The fastest clears of each class:", tostring(label),
			tostring(theme))
	end
	return event(cfg, "weekly_challenge", "Weekly Challenge " .. tostring(label), text, fields)
end

-- O409, the weekly class board at the week's end (weekly_class.lua): label "2026-11-02" (the week's Monday), boardName
-- = the board's name, sections = {{name = class, value = "1. A 1.2M\n2. ..."}} (weekly_class_core.lua K.discordSections)
function D.weeklyClass(cfg, label, boardName, sections)
	local fields = {}
	for i = 1, math.min(#(sections or {}), 25) do
		local s = sections[i]
		fields[i] = {name = clip(s.name, 256), value = clip(s.value, 1024), inline = true}
	end
	local text
	if #fields == 0 then
		text = string.format("%s, week of %s: the week has ended. Nobody placed this week.", tostring(boardName),
			tostring(label))
	else
		text = string.format("%s, week of %s: the week has ended. The podium of every class:", tostring(boardName),
			tostring(label))
	end
	return event(cfg, "weekly_class", string.format("%s: week of %s", tostring(boardName), tostring(label)), text, fields)
end

-- O393, an invasion (invasion.lua): phase "start" | "win" | "lost"; info = {area, faction, level, waves, minutes,
-- occupation (minutes), secs (fight time), names (top defenders), defenders (rewarded count)}
function D.cityInvasion(cfg, phase, info)
	info = info or {}
	local area, faction = tostring(info.area or "A town"), tostring(info.faction or "horde")
	if phase == "win" then
		local names = info.names or {}
		local fields = {{name = "Time", value = D.clock(info.secs or 0), inline = true},
			{name = "Defenders rewarded", value = tostring(floor(tonumber(info.defenders) or 0)), inline = true}}
		return event(cfg, "city_invasion", area .. " held", string.format("%s held against the %s.%s", area, faction,
			#names > 0 and (" Top defenders: " .. D.names(names, 5) .. ".") or ""), fields)
	elseif phase == "lost" then
		return event(cfg, "city_invasion", area .. " has fallen", string.format("The %s occupies %s for %d minutes. " ..
			"Slay the occupiers to free it.", faction, area, floor(tonumber(info.occupation) or 30)))
	end
	local fields = {}
	if info.level then
		fields[#fields + 1] = {name = "Level", value = tostring(floor(tonumber(info.level) or 0)), inline = true}
	end
	fields[#fields + 1] = {name = "Time limit", value = string.format("%d min", floor(tonumber(info.minutes) or 20)),
		inline = true}
	return event(cfg, "city_invasion", "Invasion: " .. area, string.format("The %s attacks %s! %d waves, the last one " ..
		"led by their warlord. Every defender is rewarded by their part in the fight.", faction, area,
		floor(tonumber(info.waves) or 5)), fields)
end

function D.milestones(oldLevel, newLevel, list)
	local out = {}
	oldLevel, newLevel = tonumber(oldLevel) or 0, tonumber(newLevel) or 0
	for _, m in ipairs(list or {}) do
		if oldLevel < m and m <= newLevel then
			out[#out + 1] = m
		end
	end
	table.sort(out)
	return out
end

-- ---------------------------------------------------------------- the daily restart
-- the time="HH:MM[:SS]" of the serversave.lua line that is not commented out
function D.saveTime(xml)
	for line in tostring(xml or ""):gmatch("[^\n]+") do
		if line:find("serversave.lua", 1, true) and not line:find("<!--", 1, true) then
			local h, m = line:match('time="(%d+):(%d+)')
			if h then
				return tonumber(h), tonumber(m)
			end
		end
	end
	return nil
end

-- now: {hour, min} (server local time). True when now is within window minutes after hour:min (over midnight too).
function D.isDailyRestart(now, hour, min, window)
	if not hour or not now then
		return false
	end
	local cur = (tonumber(now.hour) or 0) * 60 + (tonumber(now.min) or 0)
	local at = hour * 60 + (min or 0)
	local diff = (cur - at) % 1440
	return diff <= (window or 20)
end

-- ---------------------------------------------------------------- SQL
function D.schemaSql(tbl)
	return string.format("CREATE TABLE IF NOT EXISTS `%s` (`id` int unsigned NOT NULL AUTO_INCREMENT, " ..
		"`created_at` int unsigned NOT NULL, `kind` varchar(32) NOT NULL, `channel` varchar(32) NOT NULL DEFAULT 'default', " ..
		"`title` varchar(256) NOT NULL DEFAULT '', `body` text NOT NULL, `fields` text NOT NULL, " ..
		"`status` varchar(8) NOT NULL DEFAULT 'new', `attempts` int unsigned NOT NULL DEFAULT 0, " ..
		"`next_at` int unsigned NOT NULL DEFAULT 0, `sent_at` int unsigned NOT NULL DEFAULT 0, " ..
		"`error` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `status` (`status`, `next_at`, `id`), " ..
		"KEY `created` (`created_at`)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4", tbl)
end

function D.insertSql(tbl, ev, now, esc, encode)
	return string.format("INSERT INTO `%s` (`created_at`, `kind`, `channel`, `title`, `body`, `fields`) VALUES " ..
		"(%d, %s, %s, %s, %s, %s)", tbl, floor(now), esc(ev.kind), esc(ev.channel), esc(ev.title), esc(ev.text),
		esc(encode(ev.fields or {})))
end

return D
