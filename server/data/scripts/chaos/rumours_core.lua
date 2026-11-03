-- Tavern rumours (O394), the pure logic: no engine calls (tests/rumours_test.lua). Config: rumours_config.lua. Used
-- by the NPC's own Lua state (rumours_run.lua, Dorrin Alewright) and by rumours.lua (the spawner), which must agree
-- on the plan: everything that decides a true rumour is computed from the time, the config and the hunt places only.
-- Server local time. Lua 5.1 / LuaJIT and Lua 5.3.
--
--   R.lcg(seed)                               a deterministic generator (the same numbers in both interpreters)
--   R.hourStart(t)                            the start of t's local hour
--   R.regions(cfg, places)                    the places an appearance may pick (config + data/lib/chaos_hunt_places.lua)
--   R.planHour(cfg, hour, regions)            the appearance of that hour, or nil
--   R.apparitions(cfg, fromT, toT, regions)   every planned appearance with at in [fromT, toT]
--   R.worldBossNext(now, wb)                  the next world boss start (the formula of worldboss.lua W.nextStart)
--   R.worldBossName(wb, last, unknown)        the next boss of the rotation, or the unknown name
--   R.candidates(cfg, now, src)               what a rumour may tell now, soonest first
--   R.window(at, rng, w)                      the vague window {lo, hi} that holds `at`
--   R.fee(cfg, level)                         the gold a rumour costs
--   R.ask(cfg, heard, guid, now, cands, rng, regions)   the rumour told to one player (once per rumour), or nothing
--   R.purge(heard, now)                       forget rumours whose time has passed

ChaosRumoursCore = ChaosRumoursCore or {}
local R = ChaosRumoursCore

local floor, max, min = math.floor, math.max, math.min

function R.lcg(seed)
	local s = floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if s == 0 then
		s = 1
	end
	return function(a, b)
		s = (s * 16807) % 2147483647
		if a == nil then
			return (s - 1) / 2147483646
		end
		if b == nil then
			a, b = 1, a
		end
		if b < a then
			return a
		end
		return a + s % (b - a + 1)
	end
end

function R.hourStart(t)
	local d = os.date("*t", t)
	return os.time({year = d.year, month = d.month, day = d.day, hour = d.hour, min = 0, sec = 0})
end

local function isPos(p)
	return type(p) == "table" and type(p.x) == "number" and type(p.y) == "number" and type(p.z) == "number"
end

-- the regions, in a fixed order: the config's first, then the hunt places (planned, then base) as listed in the file.
-- Each {key, name, level, point}. Places without a name or a point are skipped; a key or a name seen twice is kept once.
function R.regions(cfg, places)
	local a = (cfg or {}).apparitions or {}
	local lo, hi = (a.levels or {})[1] or 0, (a.levels or {})[2] or math.huge
	local out, seen = {}, {}
	local function add(key, name, level, point)
		key = tostring(key)
		if type(name) ~= "string" or name == "" or seen[key] or seen["name:" .. name] or not isPos(point) then
			return
		end
		level = floor(tonumber(level) or 0)
		if level < lo or level > hi then
			return
		end
		seen[key], seen["name:" .. name] = true, true
		out[#out + 1] = {key = key, name = name, level = level, point = {x = point.x, y = point.y, z = point.z}}
	end
	for _, r in ipairs(a.regions or {}) do
		add(r.key, r.name, r.level, r.point)
	end
	if a.huntPlaces and type(places) == "table" then
		local function band(l)
			if type(l) ~= "table" then
				return tonumber(l) or 0
			end
			local l1, l2 = tonumber(l[1]) or 0, tonumber(l[2]) or 0
			return l2 > l1 and floor((l1 + l2) / 2) or l1
		end
		for _, e in ipairs(type(places.places) == "table" and places.places or {}) do
			add("hunt:" .. tostring(e.id), e.name, band(e.level), e.arrival)
		end
		for _, e in ipairs(type(places.base) == "table" and places.base or {}) do
			add("base:" .. tostring(e.id), e.name, band(e.level), e.dest)
		end
	end
	return out
end

local function pickWeighted(list, rng)
	local total = 0
	for _, m in ipairs(list or {}) do
		total = total + max(0, m.weight or 0)
	end
	if total <= 0 then
		return nil
	end
	local r = rng(1, total)
	for _, m in ipairs(list) do
		r = r - max(0, m.weight or 0)
		if r <= 0 then
			return m
		end
	end
	return list[#list]
end

-- the appearance of the hour that starts at `hour`: decided by the hour and the salt alone
function R.planHour(cfg, hour, regions)
	local a = (cfg or {}).apparitions
	if not a or not regions or #regions == 0 then
		return nil
	end
	local rng = R.lcg(((tonumber(os.date("%Y%m%d%H", hour)) or 0) * 7919 + (a.salt or 0)) % 2147483647)
	for _ = 1, 3 do -- neighbouring hours have neighbouring seeds: the first draws of the generator follow them
		rng()
	end
	if rng(1, 100) > (a.chance or 0) then
		return nil
	end
	local m1, m2 = (a.minute or {})[1] or 5, (a.minute or {})[2] or 55
	local at = hour + rng(m1, max(m1, m2)) * 60
	local region = regions[rng(1, #regions)]
	local monster = pickWeighted(a.monsters, rng)
	if not monster then
		return nil
	end
	return {key = "app:" .. hour, kind = "apparition", at = at, region = region, place = region.name,
		level = region.level, monster = monster, what = monster.name}
end

function R.apparitions(cfg, fromT, toT, regions)
	local out = {}
	local h = R.hourStart(fromT)
	while h <= toT do
		local p = R.planHour(cfg, h, regions)
		if p and p.at >= fromT and p.at <= toT then
			out[#out + 1] = p
		end
		h = R.hourStart(h + 3600 + 60)
	end
	return out
end

-- the first world boss start strictly after now (worldboss.lua W.nextStart): every hour h with (h - offsetHours) %
-- intervalHours == 0, minute 0
function R.worldBossNext(now, wb)
	wb = wb or {}
	local interval = max(1, floor(wb.intervalHours or 6))
	local offset = floor(wb.offsetHours or 0) % interval
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

-- rotation: the one after `last` (worldboss.lua W.pickBoss); random mode or no list: the unknown name
function R.worldBossName(wb, last, unknown)
	local list = wb and wb.bosses or {}
	if #list == 0 or (wb.mode or "rotation") ~= "rotation" then
		return unknown
	end
	last = tonumber(last) or 0
	local i = (last < 1 or last > #list) and 1 or (last % #list + 1)
	return list[i] and list[i].name or unknown
end

-- what may be told now: src = {regions, invasions = {{at, areaName, factionName}} (invasion_core I.upcoming, resolved),
-- worldBoss = {at, name}}. Only things at least leadMinutes and at most horizonMinutes ahead, soonest first.
function R.candidates(cfg, now, src)
	cfg = cfg or {}
	src = src or {}
	local on = cfg.sources or {}
	local from, to = now + (cfg.leadMinutes or 3) * 60, now + (cfg.horizonMinutes or 60) * 60
	local out = {}
	if on.apparition ~= false then
		for _, p in ipairs(R.apparitions(cfg, from, to, src.regions or {})) do
			out[#out + 1] = p
		end
	end
	if on.invasion ~= false then
		for _, s in ipairs(src.invasions or {}) do
			if s.at >= from and s.at <= to and s.areaName and s.factionName then
				out[#out + 1] = {key = "inv:" .. s.at, kind = "invasion", at = s.at, place = s.areaName, what = s.factionName}
			end
		end
	end
	local wb = src.worldBoss
	if on.worldboss ~= false and wb and wb.at and wb.at >= from and wb.at <= to then
		out[#out + 1] = {key = "wb:" .. wb.at, kind = "worldboss", at = wb.at, place = "the temple portals", what = wb.name}
	end
	table.sort(out, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.key < b.key
	end)
	return out
end

-- a window of w.width minutes that holds `at`, starting w.before minutes earlier (random), rounded down to w.round
function R.window(at, rng, w)
	w = w or {}
	local b1, b2 = (w.before or {})[1] or 5, (w.before or {})[2] or 20
	local width = max(1, w.width or 30)
	b2 = min(max(b1, b2), width - 1)
	b1 = min(b1, b2)
	local round = max(1, w.round or 5) * 60
	local lo = at - rng(b1, b2) * 60
	lo = lo - lo % round
	local hi = lo + width * 60
	if hi < at then -- rounding moved it past the time: keep the time inside
		hi = at + round
	end
	return lo, hi
end

function R.fee(cfg, level)
	local f = (cfg or {}).fee or {}
	local n = (f.base or 0) + (f.perLevel or 0) * max(0, floor(tonumber(level) or 0))
	return max(0, min(f.max or n, floor(n)))
end

-- heard = {[guid] = {[key] = until}}: drop what has passed
function R.purge(heard, now)
	for guid, keys in pairs(heard) do
		local any = false
		for k, untilT in pairs(keys) do
			if untilT < now then
				keys[k] = nil
			else
				any = true
			end
		end
		if not any then
			heard[guid] = nil
		end
	end
end

-- the rumour for one player: the soonest candidate this player has not heard. Returns nil when there is nothing new
-- (no fee then), else {key, kind, lie, what, place, lo, hi, at}. A lie (falseChance) names an appearance of another
-- region and another window inside the horizon; the true candidate counts as heard either way.
function R.ask(cfg, heard, guid, now, cands, rng, regions)
	heard[guid] = heard[guid] or {}
	local mine = heard[guid]
	local pick
	for _, c in ipairs(cands or {}) do
		if not mine[c.key] then
			pick = c
			break
		end
	end
	if not pick then
		return nil
	end
	mine[pick.key] = pick.at + 3600
	local out = {key = pick.key, kind = pick.kind, what = pick.what, place = pick.place, at = pick.at}
	if rng(1, 100) <= (cfg.falseChance or 0) then
		local others = {}
		for _, r in ipairs(regions or {}) do
			if r.name ~= pick.place then
				others[#others + 1] = r
			end
		end
		local monster = pickWeighted(((cfg.apparitions or {}).monsters) or {}, rng)
		if #others > 0 and monster then
			local r = others[rng(1, #others)]
			local fakeAt = now + rng((cfg.leadMinutes or 3) + 10, max((cfg.leadMinutes or 3) + 10, cfg.horizonMinutes or 60)) * 60
			out = {key = pick.key, kind = "apparition", lie = true, what = monster.name, place = r.name, at = fakeAt}
		end
	end
	out.lo, out.hi = R.window(out.at, rng, cfg.window)
	return out
end

return R
