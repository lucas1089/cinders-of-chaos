-- Regenerates client/overlay/modules/game_howitworks/howitworks_data.lua: the "How it works" cards that every feature
-- window and every "New" unlock window of the client shows (who it is for, monster levels, what drops, what a death
-- costs, how often). The numbers come from the real server config files; the plain sentences (English and pt-BR) are in
-- tools/howitworks_config.lua. Run from the server/ folder (the configs dofile() their neighbours relative to it):
--   luajit tools/gen_howitworks_data.lua            write the client file
--   luajit tools/gen_howitworks_data.lua --check    exit 1 when the client file differs from what the data gives (CI)
--   lua5.3 works the same; the output is byte-identical under both (CI checks both).
-- Derived (from the configs): every number, level, time, count, price and weekday of a sentence; the level of every unlock;
-- the death rule (gentledeath_config.lua); the cards of the unlock entries that have no hand-written card (crafting, pets,
-- market, passive tree, salvage): their two lines and their level are the unlock entry's own.
-- Hand-written (tools/howitworks_config.lua): the sentences, the window of a card, the unlock and goal keys it answers.
-- A {name} with no value, or a value no sentence uses, stops the run. No clock, no random, no pairs() order.
-- Pure helpers are exported for tests/howitworks_gen_test.lua: set HOWITWORKS_GEN_NO_MAIN = true before dofile().

local Gen = {}
local floor = math.floor

local OUT_DEFAULT = "../client/overlay/modules/game_howitworks/howitworks_data.lua"
Gen.SOURCES = {"tools/howitworks_config.lua", "data/scripts/chaos/unlocks_config.lua", "data/scripts/chaos/goals_config.lua",
	"data/scripts/chaos/gentledeath_config.lua", "data/scripts/chaos/infinitytower_balance_config.lua",
	"data/scripts/chaos/infinitytower_run.lua", "data/scripts/chaos/rift_config.lua", "data/scripts/chaos/arena_config.lua",
	"data/scripts/chaos/battleground_config.lua", "data/scripts/chaos/bossspawns_config.lua",
	"data/scripts/chaos/chaos_constants.lua", "data/scripts/chaos/pocketboss_config.lua",
	"data/scripts/chaos/descent_config.lua", "data/scripts/chaos/raid_config.lua", "data/scripts/chaos/siege_config.lua",
	"data/scripts/chaos/invasion_config.lua", "data/scripts/chaos/bounty_config.lua", "data/scripts/chaos/daily_config.lua",
	"data/scripts/chaos/weeklychest_config.lua", "data/scripts/chaos/embercache_config.lua",
	"data/scripts/chaos/season_config.lua", "data/scripts/chaos/factions_config.lua", "data/scripts/chaos/gamble_config.lua"}

-- ---------------------------------------------------------------------------------------------------------------
-- pure helpers
-- ---------------------------------------------------------------------------------------------------------------
function Gen.num(v)
	v = tonumber(v) or 0
	if v == floor(v) and math.abs(v) < 2 ^ 53 then
		return string.format("%d", v)
	end
	local s = string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", "")
	return s
end

function Gen.quote(s)
	s = tostring(s)
	s = s:gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
	return "\"" .. s .. "\""
end

local WEEKDAYS = {
	{en = "Sunday", pt = "domingo"}, {en = "Monday", pt = "segunda-feira"}, {en = "Tuesday", pt = "terça-feira"},
	{en = "Wednesday", pt = "quarta-feira"}, {en = "Thursday", pt = "quinta-feira"}, {en = "Friday", pt = "sexta-feira"},
	{en = "Saturday", pt = "sábado"}
}
local MONTHS = {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

-- the helpers the feature value functions get (H)
function Gen.helpers(C)
	local H = {}
	function H.round(v)
		return floor(v + 0.5)
	end
	-- linear interpolation in {{x, y}, ...}, flat beyond the ends, rounded
	function H.curve(points, x)
		if x <= points[1][1] then
			return H.round(points[1][2])
		end
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			if x <= b[1] then
				return H.round(a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]))
			end
		end
		return H.round(points[#points][2])
	end
	function H.hhmm(h, m)
		return string.format("%02d:%02d", h, m or 0)
	end
	-- 1 = Sunday .. 7 = Saturday (os.date wday)
	function H.weekday(n)
		return WEEKDAYS[n] or error("no weekday " .. tostring(n))
	end
	-- 50000 -> {en = "50,000", pt = "50.000"}
	function H.big(n)
		local s = Gen.num(n)
		local en = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
		local pt = en:gsub(",", ".")
		return {en = en, pt = pt}
	end
	-- 20261120 -> {en = "20 Nov 2026", pt = "20/11/2026"}
	function H.date(yyyymmdd)
		local y, m, d = floor(yyyymmdd / 10000), floor(yyyymmdd / 100) % 100, yyyymmdd % 100
		return {en = string.format("%d %s %d", d, MONTHS[m], y), pt = string.format("%02d/%02d/%d", d, m, y)}
	end
	-- {{en, pt}, ...} -> "a and b" / "a e b" / "a, b and c"
	function H.join(list)
		local out = {}
		for _, lang in ipairs({"en", "pt"}) do
			local parts = {}
			for i, v in ipairs(list) do
				parts[i] = type(v) == "table" and v[lang] or tostring(v)
			end
			local word = lang == "en" and " and " or " e "
			out[lang] = #parts <= 1 and (parts[1] or "") or (table.concat(parts, ", ", 1, #parts - 1) .. word .. parts[#parts])
		end
		return out
	end
	-- the level of an unlocks_config.lua entry (its own test ties it to the system's gate)
	function H.unlock(key)
		for _, e in ipairs(C.unlocks.entries) do
			if e.key == key then
				return e.level
			end
		end
		error("no unlock entry " .. tostring(key))
	end
	-- `every` of the first-clear rule that pays an item (infinitytower_balance_config.lua rewards)
	function H.rewardEvery(balance, itemId)
		for _, r in ipairs(balance.rewards.firstClear) do
			if r.id == itemId then
				return r.every
			end
		end
		error("no reward rule for item " .. tostring(itemId))
	end
	return H
end

-- {name} places of a text filled from `values`; a value may be {en, pt} (the language is picked). `used` collects names.
function Gen.fill(text, values, lang, used, where)
	return (text:gsub("{(%w+)}", function(name)
		local v = values[name]
		if v == nil then
			error(where .. ": the text uses {" .. name .. "} but the feature gives no such value", 0)
		end
		used[name] = true
		if type(v) == "table" then
			v = v[lang] or error(where .. ": value " .. name .. " has no " .. lang, 0)
		end
		return type(v) == "number" and Gen.num(v) or tostring(v)
	end))
end

-- the number of a `name = 123` line (one tab deep) in a file that needs the engine to load (infinitytower_run.lua)
local function scanNumbers(path, names)
	local f = assert(io.open(path, "rb"), path)
	local text = f:read("*a")
	f:close()
	local out = {}
	for _, n in ipairs(names) do
		local v = text:match("\n\t" .. n .. "%s*=%s*(%d+)")
		if not v then
			error(path .. ": no line '" .. n .. " = <number>' (one tab deep)", 0)
		end
		out[n] = tonumber(v)
	end
	return out
end

local function loadConfig(name)
	return dofile("data/scripts/chaos/" .. name .. ".lua")
end

-- every config the cards read, by the name the value functions use
function Gen.load()
	dofile("data/scripts/chaos/chaos_constants.lua")
	local C = {
		unlocks = loadConfig("unlocks_config"), goals = loadConfig("goals_config"), gentle = loadConfig("gentledeath_config"),
		tower = loadConfig("infinitytower_balance_config"), rift = loadConfig("rift_config"), arena = loadConfig("arena_config"),
		bg = loadConfig("battleground_config"), bossspawns = loadConfig("bossspawns_config"),
		pocket = loadConfig("pocketboss_config"), descent = loadConfig("descent_config"), raid = loadConfig("raid_config"),
		siege = loadConfig("siege_config"), invasion = loadConfig("invasion_config"), bounty = loadConfig("bounty_config"),
		daily = loadConfig("daily_config"), weeklychest = loadConfig("weeklychest_config"),
		embercache = loadConfig("embercache_config"), season = loadConfig("season_config"),
		factions = loadConfig("factions_config"), gamble = loadConfig("gamble_config"), worldBoss = Chaos.worldBoss
	}
	C.towerRun = scanNumbers("data/scripts/chaos/infinitytower_run.lua",
		{"maxPartySize", "floorTimeLimit", "bossFloorTimeMult", "runTimeLimit"})
	return C
end

-- the numbers of the death rule (gentledeath_config.lua)
function Gen.deathValues(C)
	local g = C.gentle
	assert(g.keepItems, "the cards say nobody loses items on death: gentledeath_config.lua keepItems is off")
	local x = g.xpLoss
	return {free = x[2].level, half = x[3].level, full = x[4].level}
end

-- ---------------------------------------------------------------------------------------------------------------
-- build
-- ---------------------------------------------------------------------------------------------------------------
local function pair(t, lang)
	return t[lang == "en" and 1 or 2]
end

function Gen.build(C, P)
	local H = Gen.helpers(C)
	local death = Gen.deathValues(C)
	local gentle = {}
	for _, lang in ipairs({"en", "pt"}) do
		gentle[lang] = Gen.fill(P.gentle[lang], death, lang, {}, "gentle")
	end

	local features, byKey, claimed = {}, {}, {}
	for _, f in ipairs(P.features) do
		assert(not byKey[f.key], "duplicate feature " .. f.key)
		byKey[f.key] = f
		local values = f.values and f.values(C, H) or {}
		values.gentle = gentle
		local used = {gentle = true}
		local card = {key = f.key, title = {en = f.title[1], pt = f.title[2]}, window = f.window, unlocks = f.unlocks,
			goals = f.goals, rows = {}}
		for _, id in ipairs(P.rows) do
			local t = f[id]
			if t then
				local where = f.key .. "." .. id
				card.rows[#card.rows + 1] = {id = id, en = Gen.fill(t[1], values, "en", used, where),
					pt = Gen.fill(t[2], values, "pt", used, where)}
			end
		end
		local names = {}
		for k in pairs(values) do
			names[#names + 1] = k
		end
		table.sort(names)
		for _, k in ipairs(names) do
			if not used[k] then
				error(f.key .. ": the value {" .. k .. "} is not used by any sentence", 0)
			end
		end
		for _, u in ipairs(f.unlocks or {}) do
			claimed[u] = f.key
		end
		features[#features + 1] = card
	end

	-- the unlock entries without a hand-written card: a card made from the entry (level, and its two lines)
	for _, e in ipairs(C.unlocks.entries) do
		if not claimed[e.key] then
			local lvl = {en = "Level " .. e.level .. "+.", pt = "Nível " .. e.level .. "+."}
			features[#features + 1] = {key = e.key, title = {en = e.title[1], pt = e.title[2]},
				window = P.unlockWindows[e.key], unlocks = {e.key}, rows = {
					{id = "what", en = e.why[1][1] .. " " .. e.why[2][1], pt = e.why[1][2] .. " " .. e.why[2][2]},
					{id = "who", en = lvl.en, pt = lvl.pt}
				}}
		end
	end
	return {features = features}
end

-- goal keys of the cards must exist in goals_config.lua; unlock keys in unlocks_config.lua
function Gen.validate(data, C)
	local goals, unlocks = {}, {}
	for _, g in ipairs(C.goals.goals or {}) do
		goals[g.key] = true
	end
	for _, e in ipairs(C.unlocks.entries) do
		unlocks[e.key] = true
	end
	local seen = {}
	for _, f in ipairs(data.features) do
		assert(not seen[f.key], "duplicate card " .. f.key)
		seen[f.key] = true
		assert(#f.rows > 0, f.key .. ": a card with no rows")
		for _, g in ipairs(f.goals or {}) do
			assert(goals[g], f.key .. ": unknown goal " .. g)
		end
		for _, u in ipairs(f.unlocks or {}) do
			assert(unlocks[u], f.key .. ": unknown unlock " .. u)
		end
	end
end

-- ---------------------------------------------------------------------------------------------------------------
-- writer
-- ---------------------------------------------------------------------------------------------------------------
local function list(items)
	local parts = {}
	for i, v in ipairs(items) do
		parts[i] = Gen.quote(v)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

function Gen.render(data)
	local out = {
		"-- GENERATED by server/tools/gen_howitworks_data.lua from the server config files and tools/howitworks_config.lua.",
		"-- Do not edit: cd server && luajit tools/gen_howitworks_data.lua (CI checks it with --check, under LuaJIT and Lua 5.3).",
		"-- Format and use: client/overlay/modules/game_howitworks/howcore.lua. pt-BR texts are UTF-8 (the module turns them into cp1252).",
		"HowData = {", "\tfeatures = {"
	}
	for _, f in ipairs(data.features) do
		out[#out + 1] = "\t\t{key = " .. Gen.quote(f.key) .. ", title = {en = " .. Gen.quote(f.title.en) .. ", pt = " ..
			Gen.quote(f.title.pt) .. "}" .. (f.window and (", window = " .. Gen.quote(f.window)) or "") ..
			(f.unlocks and (", unlocks = " .. list(f.unlocks)) or "") .. (f.goals and (", goals = " .. list(f.goals)) or "") ..
			", rows = {"
		for _, r in ipairs(f.rows) do
			out[#out + 1] = "\t\t\t{id = " .. Gen.quote(r.id) .. ", en = " .. Gen.quote(r.en) .. ", pt = " .. Gen.quote(r.pt) .. "},"
		end
		out[#out] = out[#out]:gsub(",$", "")
		out[#out + 1] = "\t\t}},"
	end
	out[#out] = out[#out]:gsub(",$", "")
	out[#out + 1] = "\t}"
	out[#out + 1] = "}"
	out[#out + 1] = "return HowData"
	out[#out + 1] = ""
	return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------------------------------------------
-- main
-- ---------------------------------------------------------------------------------------------------------------
local function readFile(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

function Gen.make()
	local C = Gen.load()
	local P = dofile("tools/howitworks_config.lua")
	local data = Gen.build(C, P)
	Gen.validate(data, C)
	return data, C, P
end

function Gen.main(args)
	local check, out = false, OUT_DEFAULT
	for _, a in ipairs(args or {}) do
		if a == "--check" then
			check = true
		else
			out = a
		end
	end
	local data = Gen.make()
	local text = Gen.render(data)
	if check then
		if readFile(out) ~= text then
			io.stderr:write(out .. " is stale: run  cd server && luajit tools/gen_howitworks_data.lua\n")
			os.exit(1)
		end
		print("how it works data up to date (" .. #data.features .. " cards)")
		return
	end
	local f = assert(io.open(out, "wb"))
	f:write(text)
	f:close()
	print("wrote " .. out .. " (" .. #data.features .. " cards)")
end

if not HOWITWORKS_GEN_NO_MAIN then
	Gen.main(arg)
end

return Gen
