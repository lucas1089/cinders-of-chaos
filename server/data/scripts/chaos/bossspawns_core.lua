-- Boss spawns tracker: pure logic (no engine calls). Used by bossspawns.lua, tested by tests/bossspawns_test.lua.
-- Builds the boss list from bossspawns_config.lua and the systems that own some of the bosses, matches spawns and
-- deaths to entries, keeps the alive / last kill state, and computes every entry's respawn status for the window.
-- Times are unix seconds, weekly and slot times in server local time (os.date / os.time). Lua 5.1 / LuaJIT and 5.3.

ChaosBossSpawnsCore = ChaosBossSpawnsCore or {}
local K = ChaosBossSpawnsCore

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

local DAY_NAMES = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
K.DAY_NAMES = DAY_NAMES

local function lower(s)
	return type(s) == "string" and s:lower() or nil
end

local function title(s)
	-- "the grey widow" -> "The Grey Widow"; keeps "of", "the" small after the first word
	local small = {of = true, the = true}
	local i = 0
	return (tostring(s or ""):gsub("(%a)([%w']*)", function(a, b)
		i = i + 1
		local w = (a .. b):lower()
		if i > 1 and small[w] then
			return w
		end
		return a:upper() .. b:lower()
	end))
end
K.title = title

local function copy(t)
	if type(t) ~= "table" then
		return t
	end
	local o = {}
	for k, v in pairs(t) do
		o[k] = copy(v)
	end
	return o
end

-- ======================================================================== building the list

-- world boss entries from Chaos.worldBoss: one per boss of the rotation, in rotation order
function K.worldBossEntries(wb, opts)
	local list = {}
	if type(wb) ~= "table" or type(wb.bosses) ~= "table" then
		return list
	end
	opts = opts or {}
	local a = wb.arena or {}
	local o = a.origin or {x = 5000, y = 5000, z = 7}
	local half = floor(((a.inner or 31) + 1) / 2)
	for i, b in ipairs(wb.bosses) do
		list[#list + 1] = {key = "world_" .. i, category = "world", name = b.name, monster = b.name,
			loc = opts.loc or "World Boss Arena", note = opts.note, level = wb.minLevel or opts.level, pos = {x = o.x + half, y = o.y + half, z = o.z},
			radius = half + 2, rule = {type = "rotation", index = i}}
	end
	return list
end

-- invasion boss entries from invasion_config.lua: one per faction boss (renamed ones by their shown name)
function K.invasionEntries(inv, opts)
	local list = {}
	if type(inv) ~= "table" or type(inv.factions) ~= "table" then
		return list
	end
	opts = opts or {}
	local keys = {}
	for k in pairs(inv.factions) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local seen = {}
	for _, fk in ipairs(keys) do
		local f = inv.factions[fk]
		for _, b in ipairs(f.bosses or {}) do
			local shown = b.rename or b.name
			local key = "invasion_" .. (shown:lower():gsub("[^%w]+", "_"))
			if not seen[key] then
				seen[key] = true
				list[#list + 1] = {key = key, category = "invasion", name = shown, monster = b.name,
					shown = b.rename, faction = f.name, factionKey = fk, level = b.level, loc = opts.loc, note = opts.note,
					anywhere = true, rule = {type = "invasion"}}
			end
		end
	end
	table.sort(list, function(a, b)
		if a.level ~= b.level then
			return (a.level or 0) < (b.level or 0)
		end
		return a.name < b.name
	end)
	return list
end

-- Infinity Tower boss entries: names = the tower's bosses list, one every `every` floors, the list repeats
function K.towerEntries(names, every, opts)
	local list = {}
	opts = opts or {}
	every = every or 10
	local n = type(names) == "table" and #names or 0
	for i, name in ipairs(names or {}) do
		local f1 = i * every
		local floors = string.format("%d, %d, %d...", f1, f1 + n * every, f1 + 2 * n * every)
		list[#list + 1] = {key = "tower_" .. i, category = "tower", name = title(name), monster = name, anywhere = false,
			loc = opts.loc, note = opts.note, floor = f1, rule = {type = "ondemand", how = string.format(opts.how or "Floor %s", floors),
				short = "Floor " .. floors}}
	end
	return list
end

-- Vocation Trial boss entries from trials_config.lua families (sorted by family name)
function K.trialEntries(trials, opts)
	local list = {}
	if type(trials) ~= "table" or type(trials.families) ~= "table" then
		return list
	end
	opts = opts or {}
	local keys = {}
	for k in pairs(trials.families) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local tiers = trials.tiers or {}
	local lv = tiers[1] and tiers[1].minLevel or nil
	for _, k in ipairs(keys) do
		local fam = trials.families[k]
		local b = fam.boss or {}
		local look = b.look and {type = b.look.lookType, head = b.look.lookHead, body = b.look.lookBody, legs = b.look.lookLegs,
			feet = b.look.lookFeet, addons = b.look.lookAddons} or nil
		list[#list + 1] = {key = "trial_" .. k, category = "trial", name = b.name or title(k), look = look, level = lv,
			loc = opts.loc, note = opts.note, rule = {type = "ondemand", how = (fam.name and (fam.name .. ": ") or "") .. (opts.how or "Vocation Trial"),
				short = fam.name or opts.short, cooldown = opts.cooldownStorage}}
	end
	return list
end

-- dungeon boss entries: extra = Chaos.dungeons.extra, base = DUNGEON_SYSTEM.Dungeons (may be nil), defaults by id
function K.dungeonEntries(extra, base, opts)
	local list = {}
	opts = opts or {}
	local ids = {}
	for id in pairs(extra or {}) do
		if type(id) == "number" then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local e = extra[id]
		local b = type(base) == "table" and base[id] or nil
		local d = (opts.defaults or {})[id] or {}
		local p = b and b.DungeonPos
		local pos = p and tonumber(p.x) and {x = p.x, y = p.y, z = p.z} or nil
		list[#list + 1] = {key = "dungeon_" .. id, category = "dungeon", name = d.name or title(e.bossName or ("Dungeon " .. id)),
			monster = e.bossName, loc = (b and b.Name) or e.title, level = (b and b.Level) or d.level, pos = pos,
			party = b and b.NeedParty and (b.AmountParty or 2) or nil,
			rule = {type = "ondemand", how = opts.how or "Dungeon queue", short = opts.short, cooldown = opts.cooldownStorage}}
		if b and b.FromPos and b.ToPos then
			list[#list].areas = {{x1 = b.FromPos.x, y1 = b.FromPos.y, x2 = b.ToPos.x, y2 = b.ToPos.y, z = b.FromPos.z}}
		else
			list[#list].anywhere = false
		end
	end
	return list
end

-- sources = {worldBoss = Chaos.worldBoss, invasion = invasion config, towerBosses = {names}, towerEvery = n,
--            trials = trials config, ascension = true, dungeonsExtra, dungeonsBase, dungeonCooldown = storage}
-- -> index {list, byKey, byType = {[lower type] = {entries}}, categories, catByKey, problems}
function K.build(cfg, sources)
	cfg = cfg or {}
	sources = sources or {}
	local on = cfg.sources or {}
	local idx = {list = {}, byKey = {}, byType = {}, categories = {}, catByKey = {}, problems = {}}
	for i, c in ipairs(cfg.categories or {}) do
		local cat = {key = c.key, name = c.name, color = c.color, text = c.text, order = i}
		idx.categories[#idx.categories + 1] = cat
		idx.catByKey[c.key] = cat
	end
	local function add(e)
		if type(e) ~= "table" or type(e.key) ~= "string" then
			idx.problems[#idx.problems + 1] = "entry without key"
			return
		end
		if idx.byKey[e.key] then
			idx.problems[#idx.problems + 1] = "duplicate key " .. e.key
			return
		end
		if not idx.catByKey[e.category] then
			idx.problems[#idx.problems + 1] = e.key .. ": unknown category " .. tostring(e.category)
			return
		end
		if type(e.rule) ~= "table" or type(e.rule.type) ~= "string" then
			idx.problems[#idx.problems + 1] = e.key .. ": no rule"
			return
		end
		e.order = #idx.list + 1
		idx.list[#idx.list + 1] = e
		idx.byKey[e.key] = e
		local t = lower(e.monster)
		if t then
			idx.byType[t] = idx.byType[t] or {}
			table.insert(idx.byType[t], e)
		end
	end
	if on.worldBoss ~= false and sources.worldBoss then
		for _, e in ipairs(K.worldBossEntries(sources.worldBoss, cfg.worldBoss)) do
			add(e)
		end
	end
	for _, e in ipairs(cfg.bosses or {}) do
		add(copy(e))
	end
	if on.invasion ~= false and sources.invasion then
		for _, e in ipairs(K.invasionEntries(sources.invasion, cfg.invasion)) do
			add(e)
		end
	end
	if on.dungeons ~= false and sources.dungeonsExtra then
		local d = copy(cfg.dungeons or {})
		d.cooldownStorage = sources.dungeonCooldown
		for _, e in ipairs(K.dungeonEntries(sources.dungeonsExtra, sources.dungeonsBase, d)) do
			add(e)
		end
	end
	if on.tower ~= false and sources.towerBosses then
		for _, e in ipairs(K.towerEntries(sources.towerBosses, sources.towerEvery, cfg.tower)) do
			add(e)
		end
	end
	if on.trials ~= false and sources.trials then
		for _, e in ipairs(K.trialEntries(sources.trials, cfg.trials)) do
			add(e)
		end
	end
	if on.ascension ~= false and sources.ascension and cfg.ascension then
		local a = cfg.ascension
		add({key = "ascension_warden", category = "trial", name = a.name, monster = a.monster, look = copy(a.look),
			loc = a.loc, note = a.note, level = sources.ascensionLevel or a.level, anywhere = false,
			rule = {type = "ondemand", how = a.how, short = a.short, cooldown = a.cooldownStorage}})
	end
	return idx
end

-- ======================================================================== base server raids (data/raids/raids.xml)

local function attr(tag, name)
	return tag:match("%f[%w]" .. name .. '%s*=%s*"([^"]*)"')
end

-- raids.xml text -> {{name, file, interval (minutes), margin (minutes), enabled}}
function K.parseRaidList(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	text = text:gsub("<!%-%-.-%-%->", "")
	for tag in text:gmatch("<raid%s[^>]*>") do
		local file = attr(tag, "file")
		if file then
			local enabled = attr(tag, "enabled")
			out[#out + 1] = {name = attr(tag, "name"), file = file,
				interval = tonumber(attr(tag, "interval2")) or tonumber(attr(tag, "interval")),
				margin = tonumber(attr(tag, "margin")) or 0,
				enabled = not (enabled and (enabled == "0" or enabled:lower() == "false" or enabled:lower() == "no"))}
		end
	end
	return out
end

-- one raid file -> {{name, x, y, z}} of its singlespawn lines
function K.parseRaidSpawns(text)
	local out = {}
	if type(text) ~= "string" then
		return out
	end
	text = text:gsub("<!%-%-.-%-%->", "")
	for tag in text:gmatch("<singlespawn%s[^>]*>") do
		local x, y, z = tonumber(attr(tag, "x")), tonumber(attr(tag, "y")), tonumber(attr(tag, "z"))
		local name = attr(tag, "name")
		if name and x and y and z then
			out[#out + 1] = {name = name, x = x, y = y, z = z}
		end
	end
	return out
end

-- raids = {{interval, margin, enabled, spawns = {{name, x, y, z}}}}: every raid entry of the index whose monster is
-- spawned by an enabled raid takes that raid's numbers and position; the raid entries no raid spawns get
-- missing = true (the window leaves them out). Returns the number of entries found.
function K.applyRaids(idx, raids)
	local found = 0
	local byName = {}
	for _, r in ipairs(raids or {}) do
		if r.enabled ~= false and (r.interval or 0) > 0 then
			for _, s in ipairs(r.spawns or {}) do
				local k = s.name:lower()
				if not byName[k] then
					byName[k] = {raid = r, spawn = s}
				end
			end
		end
	end
	for _, e in ipairs(idx.list) do
		if e.rule.type == "raid" then
			local hit = byName[lower(e.monster) or ""]
			if hit then
				e.rule.interval = hit.raid.interval
				e.rule.margin = hit.raid.margin or 0
				e.pos = {x = hit.spawn.x, y = hit.spawn.y, z = hit.spawn.z}
				e.missing = nil
				found = found + 1
			else
				e.missing = true
			end
		end
	end
	return found
end

-- ======================================================================== places

local function dist(a, b)
	return max(abs(a.x - b.x), abs(a.y - b.y))
end

local function inRect(r, pos)
	return pos.x >= min(r.x1, r.x2) and pos.x <= max(r.x1, r.x2) and pos.y >= min(r.y1, r.y2) and pos.y <= max(r.y1, r.y2)
		and (r.z == nil or r.z == pos.z)
end

-- does a spawn / death at pos count for entry e?
function K.inPlace(e, pos, defaultRadius)
	if e.anywhere then
		return true
	end
	if type(pos) ~= "table" then
		return false
	end
	if e.areas then
		for _, r in ipairs(e.areas) do
			if inRect(r, pos) then
				return true
			end
		end
		return false
	end
	if e.pos then
		return abs((pos.z or 0) - (e.pos.z or 0)) <= 1 and dist(pos, e.pos) <= (e.radius or defaultRadius or 40)
	end
	return false
end

-- entries a monster counts for. info = {type = type name, shown = shown name, pos, invasion = true when it is the
-- running invasion's boss}
function K.match(idx, info, defaultRadius)
	local out = {}
	local list = idx.byType[lower(info.type) or ""]
	if not list then
		return out
	end
	for _, e in ipairs(list) do
		if not e.missing then
			if e.rule.type == "invasion" then
				if info.invasion and (not e.shown or lower(e.shown) == lower(info.shown)) then
					out[#out + 1] = e
				end
			elseif not e.shown or lower(e.shown) == lower(info.shown) then
				if K.inPlace(e, info.pos, defaultRadius) then
					out[#out + 1] = e
				end
			end
		end
	end
	return out
end

-- closest town (by its temple) -> name. towns = {{name, pos}}
function K.nearestTown(pos, towns)
	if type(pos) ~= "table" then
		return nil
	end
	local best, bestD
	for _, t in ipairs(towns or {}) do
		if t.pos and t.name then
			local d = dist(pos, t.pos)
			if not bestD or d < bestD then
				best, bestD = t.name, d
			end
		end
	end
	return best
end

-- ======================================================================== state (alive and kills)

function K.newState()
	return {alive = {}, kills = {}, spawned = {}}
end

-- a tracked monster of entry `key` (creature id cid) appeared at `now`
function K.onSpawn(st, key, cid, now)
	st.alive[key] = st.alive[key] or {}
	st.alive[key][cid] = now
	st.spawned[key] = now
end

-- it died (or left: killer nil, counted = false)
function K.onDeath(st, key, cid, now, killer, counted)
	if st.alive[key] then
		st.alive[key][cid] = nil
	end
	if counted == false then
		return nil
	end
	local k = st.kills[key] or {count = 0}
	k.at = now
	k.killer = killer
	k.count = (k.count or 0) + 1
	st.kills[key] = k
	return k
end

-- drop the alive marks of creatures that do not exist any more (exists(cid) -> bool)
function K.prune(st, exists)
	local n = 0
	for key, set in pairs(st.alive) do
		for cid in pairs(set) do
			if not exists(cid) then
				set[cid] = nil
				n = n + 1
			end
		end
		if next(set) == nil then
			st.alive[key] = nil
		end
	end
	return n
end

function K.aliveCount(st, key)
	local n = 0
	for _ in pairs(st.alive[key] or {}) do
		n = n + 1
	end
	return n
end

-- ======================================================================== times

-- next weekly time strictly after now. times = {{day = 1..7 (1 = Sunday), hour, min}}
function K.nextWeekly(times, now)
	local best
	local d = os.date("*t", now)
	for _, t in ipairs(times or {}) do
		for i = 0, 7 do
			local at = os.time({year = d.year, month = d.month, day = d.day + i, hour = t.hour or 0, min = t.min or 0, sec = 0})
			local wday = os.date("*t", at).wday
			if wday == t.day and at > now then
				if not best or at < best then
					best = at
				end
				break
			end
		end
	end
	return best
end

-- first full hour slot after now with (hour - offset) % interval == 0 (as worldboss.lua W.nextStart)
function K.nextSlot(now, intervalHours, offsetHours)
	local interval = max(1, floor(intervalHours or 6))
	local offset = floor(offsetHours or 0) % interval
	local d = os.date("*t", now)
	for i = 0, 24 * 2 + interval do
		local t = os.time({year = d.year, month = d.month, day = d.day, hour = d.hour + i, min = 0, sec = 0})
		local h = os.date("*t", t).hour
		if t > now and (h - offset) % interval == 0 then
			return t
		end
	end
	return now + interval * 3600
end

-- "Wed 19:30"
function K.when(at)
	return os.date("%a %H:%M", at)
end

-- 90 -> "1h 30m", 3 -> "3m", 2880 -> "2d"
function K.minutesText(m)
	m = floor(tonumber(m) or 0)
	if m >= 1440 and m % 1440 == 0 then
		return floor(m / 1440) .. "d"
	end
	if m >= 60 then
		local h, r = floor(m / 60), m % 60
		return r > 0 and string.format("%dh %dm", h, r) or (h .. "h")
	end
	return m .. "m"
end

function K.weeklyText(times)
	local parts = {}
	for _, t in ipairs(times or {}) do
		parts[#parts + 1] = string.format("%s %02d:%02d", DAY_NAMES[t.day] or "?", t.hour or 0, t.min or 0)
	end
	return table.concat(parts, ", ")
end

-- ======================================================================== status

-- Status of one entry. ctx = {now, state, worldBoss = {nextAt, interval, count, nextIndex, mode, enabled,
-- active = {index, phase, spawnAt}}, invasions = {{at, boss}}, invasionText, invasionActive = {boss},
-- cooldowns = {[storage] = until}}
-- -> {st, at (unix, or nil), text}
--   st: alive | respawn (back at `at`) | due (timer over, spawns when nobody watches) | scheduled (at `at`) |
--       random | ondemand | cooldown (the player's own wait until `at`) | unknown
function K.status(e, ctx)
	local now = ctx.now
	local st = ctx.state or K.newState()
	local r = e.rule
	local alive = K.aliveCount(st, e.key)
	local kill = st.kills[e.key]
	if r.type == "rotation" then
		local wb = ctx.worldBoss or {}
		local a = wb.active
		if a and a.index == r.index then
			if a.phase == "gather" and a.spawnAt and a.spawnAt > now then
				return {st = "scheduled", at = a.spawnAt, text = "Portals open: the boss appears soon"}
			end
			return {st = "alive", text = "Event running: portals at every temple"}
		end
		if wb.enabled == false or not wb.nextAt then
			return {st = "ondemand", text = "Started by the staff only (schedule off)", short = "Staff event"}
		end
		local count = max(1, wb.count or 1)
		if wb.mode == "random" then
			return {st = "scheduled", at = wb.nextAt, text = string.format("Random boss every %dh", wb.interval or 6)}
		end
		local nextIndex = wb.nextIndex or 1
		-- nextIndex = the boss of the slot at nextAt (the rotation after the last started boss)
		local steps = (r.index - nextIndex) % count
		return {st = "scheduled", at = wb.nextAt + steps * (wb.interval or 6) * 3600,
			text = string.format("Rotation: every %dh, one boss per slot", (wb.interval or 6) * count)}
	elseif r.type == "weekly" then
		if alive > 0 then
			return {st = "alive", text = "Weekly: " .. K.weeklyText(r.times)}
		end
		local at = K.nextWeekly(r.times, now)
		return {st = "scheduled", at = at, text = "Weekly: " .. K.weeklyText(r.times)}
	elseif r.type == "timer" then
		local text = "Respawn " .. K.minutesText(math.ceil((r.seconds or 0) / 60)) .. " after the kill"
		if alive >= (e.count or 1) or (alive > 0 and not (kill and kill.at)) then
			return {st = "alive", text = text}
		end
		if kill and kill.at then
			local back = kill.at + (r.seconds or 0)
			if back > now then
				return {st = "respawn", at = back, text = text}
			end
			if alive > 0 then
				return {st = "alive", text = text}
			end
			return {st = "due", text = text .. " (when no one is in sight)"}
		end
		return {st = "unknown", text = text}
	elseif r.type == "raid" then
		local text = string.format("Random raid: about every %s, at least %s after the last raid",
			K.minutesText(r.interval or 0), K.minutesText(r.margin or 0))
		if alive > 0 then
			return {st = "alive", text = text}
		end
		return {st = "random", text = text, short = "About every " .. K.minutesText(r.interval or 0)}
	elseif r.type == "invasion" then
		local ia = ctx.invasionActive
		if alive > 0 or (ia and ia.boss and lower(ia.boss) == lower(e.name)) then
			return {st = "alive", text = "Invasion running"}
		end
		for _, inv in ipairs(ctx.invasions or {}) do
			if inv.boss and lower(inv.boss) == lower(e.name) and inv.at and inv.at > now then
				return {st = "scheduled", at = inv.at, text = (inv.text or "Next invasion")}
			end
		end
		return {st = "random", text = ctx.invasionText or "Invasions: area and faction change every time",
			short = ctx.invasionShort or "Picked per invasion"}
	elseif r.type == "chance" then
		if alive > 0 then
			return {st = "alive", text = r.text}
		end
		return {st = "random", text = r.text, short = r.short}
	end
	-- ondemand
	local cds = ctx.cooldowns or {}
	local untilT = r.cooldown and tonumber(cds[r.cooldown]) or nil
	if untilT and untilT > now then
		return {st = "cooldown", at = untilT, text = r.how, short = r.short}
	end
	return {st = "ondemand", text = r.how, short = r.short}
end

-- ======================================================================== payload

local function outfitOf(e)
	local o = e.look or e.outfit
	if type(o) ~= "table" or not tonumber(o.type) then
		return nil
	end
	return {type = o.type, head = o.head, body = o.body, legs = o.legs, feet = o.feet, addons = o.addons, aux = o.aux}
end

-- the window's data: {now, cats = [{k, n, c, t}], rows = [{k, c, n, loc, p | ln, lv, o, st, in, at, tx, ago, by, kills,
-- alive, party, sh}]}  (ln = the place note, sent when there are no coordinates; sh = a short form of the rule text tx)
-- `in` = seconds until `at` (the client counts down from the moment it arrived), at = "Wed 19:30" for long waits
function K.payload(idx, ctx)
	local now = ctx.now
	local st = ctx.state or K.newState()
	local cats, rows, used = {}, {}, {}
	for _, e in ipairs(idx.list) do
		if not e.missing then
			local s = K.status(e, ctx)
			local row = {k = e.key, c = e.category, n = e.name, loc = e.loc or e.autoLoc, lv = e.level, o = outfitOf(e),
				st = s.st, tx = s.text, sh = s.short}
			if e.pos and e.category ~= "world" then
				row.p = {x = e.pos.x, y = e.pos.y, z = e.pos.z}
			elseif e.note then
				row.ln = e.note
			end
			if s.at then
				row["in"] = max(0, s.at - now)
				if s.at - now >= 6 * 3600 then
					row.at = K.when(s.at)
				end
			end
			local kill = st.kills[e.key]
			if kill and kill.at then
				row.ago = max(0, now - kill.at)
				row.by = kill.killer
				row.kills = kill.count
			end
			local n = K.aliveCount(st, e.key)
			if n > 1 then
				row.alive = n
			end
			if e.party then
				row.party = e.party
			end
			rows[#rows + 1] = row
			used[e.category] = true
		end
	end
	for _, c in ipairs(idx.categories) do
		if used[c.key] then
			cats[#cats + 1] = {k = c.key, n = c.name, c = c.color, t = c.text}
		end
	end
	return {now = now, cats = cats, rows = rows}
end

-- ======================================================================== persistence rows

-- SQL rows {boss_key, last_kill, killer, kills} -> state.kills
function K.loadKills(st, rows, idx)
	local n = 0
	for _, r in ipairs(rows or {}) do
		local key = r.boss_key
		if type(key) == "string" and (not idx or idx.byKey[key]) and (tonumber(r.last_kill) or 0) > 0 then
			st.kills[key] = {at = tonumber(r.last_kill), killer = r.killer ~= "" and r.killer or nil, count = tonumber(r.kills) or 0}
			n = n + 1
		end
	end
	return n
end

return K
