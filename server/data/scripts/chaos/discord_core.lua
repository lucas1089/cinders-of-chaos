-- discord_core.lua: the Discord announcements without engine calls (discord.lua; tests: server/tests/discord_test.lua).
-- An event is {kind, channel, title, text, fields = {{name, value, inline}}}; the worker (website plugins/chaos/
-- discord_worker.php) turns a queue row into a Discord embed with the brand colour of its kind.
-- Lua 5.1 / LuaJIT and Lua 5.3.
--
--   ChaosDiscordCore.enabled(cfg, kind)                 the switch of an event type
--   ChaosDiscordCore.allow(state, cfg, kind, now)       the per-minute rate limit (state.window, state.dropped)
--   ChaosDiscordCore.record / first / worldBossSpawn / bossKill / level / season / status   the events
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

-- O260, the drop feed: a legendary, divine or unique drop. kind: "legendary" | "divine" | "unique"; item = the item's name
function D.drop(cfg, name, level, item, kind)
	local title = {legendary = "Legendary find", divine = "Divine find", unique = "Unique find"}
	return event(cfg, "drop", title[kind] or "Rare find", string.format("%s (Lv %d) found %s!", tostring(name),
		floor(tonumber(level) or 0), tostring(item)))
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
