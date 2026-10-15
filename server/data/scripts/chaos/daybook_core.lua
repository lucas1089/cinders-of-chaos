-- daybook_core.lua: the pure rules of the day book (server/README.md "Ember Cache, Daily Spark and the day book"): what
-- a character did today, kept in player storages (embercache_config.lua `daybook`). No engine calls; embercache.lua is
-- the engine side. Tests: server/tests/embercache_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- A book: {day = YYYYMMDD, xp, kills, loot (gold), sup (gold of supplies used), orbs, uniques, rares (items with a
-- rarity), deaths, levelStart, seconds (played, closed sessions), points (Ember points counted)}
-- Experience and gold can pass 2^31 in a day at the end game, so each is kept in two storages (hi x 1e9 + lo).

ChaosDayBookCore = ChaosDayBookCore or {}
local D = ChaosDayBookCore

local floor, max = math.floor, math.max
local SPLIT = 1000000000

D.FIELDS = {"kills", "orbs", "uniques", "rares", "deaths", "seconds", "points"}
D.BIG = {xp = {"xpHi", "xpLo"}, loot = {"lootHi", "lootLo"}, sup = {"supHi", "supLo"}}

local function num(v)
	v = tonumber(v)
	if not v or v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return v
end

function D.split(v)
	v = max(0, floor(num(v)))
	return floor(v / SPLIT), v % SPLIT
end

function D.join(hi, lo)
	return max(0, floor(num(hi))) * SPLIT + max(0, floor(num(lo)))
end

function D.new(day, level)
	return {day = day or 0, xp = 0, kills = 0, loot = 0, sup = 0, orbs = 0, uniques = 0, rares = 0, deaths = 0,
		levelStart = level or 1, seconds = 0, points = 0}
end

-- true when the book holds anything worth telling
function D.used(b)
	return b ~= nil and (b.xp > 0 or b.kills > 0 or b.loot > 0 or b.points > 0 or b.deaths > 0 or b.seconds > 0)
end

-- a new day: returns the old book (or nil) and the new one
function D.roll(b, day, level)
	if b and b.day == day then
		return nil, b
	end
	return b, D.new(day, level)
end

function D.add(b, field, n)
	n = num(n)
	if n > 0 and b[field] ~= nil then
		b[field] = b[field] + floor(n)
	end
end

function D.load(cfg, get)
	local s = cfg.daybook
	local function v(off)
		return max(0, floor(num(get(off))))
	end
	local b = D.new(v(s.day), max(1, v(s.levelStart)))
	for _, f in ipairs(D.FIELDS) do
		b[f] = v(s[f])
	end
	for f, pair in pairs(D.BIG) do
		b[f] = D.join(v(s[pair[1]]), v(s[pair[2]]))
	end
	return b
end

function D.save(cfg, b, set)
	local s = cfg.daybook
	set(s.day, b.day)
	set(s.levelStart, b.levelStart)
	for _, f in ipairs(D.FIELDS) do
		set(s[f], b[f])
	end
	for f, pair in pairs(D.BIG) do
		local hi, lo = D.split(b[f])
		set(s[pair[1]], hi)
		set(s[pair[2]], lo)
	end
end

-- 1234 -> "1.2k", 1234567 -> "1.2M", 2.5e9 -> "2.5B"
function D.short(n)
	n = floor(num(n))
	local units = {{1e12, "T"}, {1e9, "B"}, {1e6, "M"}, {1e3, "k"}}
	for _, u in ipairs(units) do
		if n >= u[1] then
			local v = n / u[1]
			local s = v >= 100 and string.format("%d", floor(v)) or string.format("%.1f", floor(v * 10) / 10)
			return (s:gsub("%.0$", "")) .. u[2]
		end
	end
	return tostring(n)
end

-- YYYYMMDD -> "YYYY-MM-DD"
function D.date(key)
	key = floor(num(key))
	return string.format("%04d-%02d-%02d", floor(key / 10000), floor(key / 100) % 100, key % 100)
end

-- the client's view: numbers only. live = seconds of the running session not in b.seconds yet
function D.view(b, level, live)
	return {xp = b.xp, lv = max(0, floor(num(level)) - b.levelStart), kills = b.kills, loot = b.loot, sup = b.sup,
		orbs = b.orbs, uniq = b.uniques, rares = b.rares, deaths = b.deaths, secs = b.seconds + max(0, floor(num(live))),
		pts = b.points}
end

return D
