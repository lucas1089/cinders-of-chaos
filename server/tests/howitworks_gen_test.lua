-- Run from the server/ folder: luajit tests/howitworks_gen_test.lua (and lua5.3; CI runs both)
-- The "How it works" generator (tools/gen_howitworks_data.lua): its pure helpers, the placeholder rules, then the whole
-- build on the real config files: every feature has its card, every unlock entry too, windows are real client modules,
-- both languages use the same {places}, a changed config changes the text (the numbers are derived, not typed), and the
-- output is byte-stable and equal to the committed client file.

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	if not v then
		error(m or "expected true", 2)
	end
end
local function fails(fn, pattern, m)
	local good, err = pcall(fn)
	ok(not good, (m or "") .. ": expected an error")
	ok(tostring(err):find(pattern, 1, true), (m or "") .. ": error '" .. tostring(err) .. "' should mention '" .. pattern .. "'")
end

HOWITWORKS_GEN_NO_MAIN = true
local Gen = dofile("tools/gen_howitworks_data.lua")
local checks = 0
local function count()
	checks = checks + 1
end

-- ---------------------------------------------------------------- helpers
local C0 = Gen.load()
local H = Gen.helpers(C0)
eq(Gen.num(4 / 2), "2", "whole float"); count()
eq(Gen.num(12.5), "12.5", "decimal"); count()
eq(H.round(2.5), 3, "round"); count()
eq(H.hhmm(6, 0), "06:00", "hhmm"); count()
eq(H.hhmm(20), "20:00", "hhmm minute default"); count()
eq(H.weekday(1).en, "Sunday", "weekday 1"); count()
eq(H.weekday(7).pt, "sábado", "weekday 7"); count()
fails(function() H.weekday(9) end, "no weekday", "weekday 9"); count()
eq(H.big(50000).en, "50,000", "big en"); count()
eq(H.big(50000).pt, "50.000", "big pt"); count()
eq(H.big(500).en, "500", "big small"); count()
eq(H.big(1234567).en, "1,234,567", "big million"); count()
eq(H.date(20261120).en, "20 Nov 2026", "date en"); count()
eq(H.date(20261120).pt, "20/11/2026", "date pt"); count()
eq(H.join({"a"}).en, "a", "join one"); count()
eq(H.join({"a", "b"}).pt, "a e b", "join two"); count()
eq(H.join({"a", "b", "c"}).en, "a, b and c", "join three"); count()
local pts = {{1, 100}, {11, 300}, {21, 500}}
eq(H.curve(pts, 1), 100, "curve start"); count()
eq(H.curve(pts, 6), 200, "curve middle"); count()
eq(H.curve(pts, 11), 300, "curve point"); count()
eq(H.curve(pts, 99), 500, "curve beyond"); count()
eq(H.curve(pts, 0), 100, "curve before"); count()
eq(H.unlock("tower"), 100, "unlock level"); count()
fails(function() H.unlock("nope") end, "no unlock entry", "unknown unlock"); count()

-- ---------------------------------------------------------------- placeholders
local used = {}
eq(Gen.fill("Level {min}+ {x}", {min = 100, x = {en = "a", pt = "b"}}, "pt", used, "t"), "Level 100+ b", "fill"); count()
ok(used.min and used.x, "fill marks used"); count()
fails(function() Gen.fill("{nope}", {}, "en", {}, "t.who") end, "t.who", "missing value names the text"); count()
fails(function() Gen.fill("{x}", {x = {en = "a"}}, "pt", {}, "t") end, "no pt", "value without a language"); count()

local fakeP = {gentle = {en = "d {free}", pt = "m {free}"}, rows = {"who"}, unlockWindows = {}, features = {
	{key = "f", title = {"F", "F"}, who = {"A {a}", "B {a}"}, values = function() return {a = 1, extra = 2} end}}}
local fakeC = {unlocks = C0.unlocks, gentle = C0.gentle}
fails(function() Gen.build(fakeC, fakeP) end, "{extra}", "an unused value is an error"); count()
fakeP.features[1].values = function() return {a = 1} end
local built = Gen.build(fakeC, fakeP)
eq(built.features[1].rows[1].pt, "B 1", "build fills pt"); count()
eq(#built.features, 1 + #C0.unlocks.entries, "unlock entries without a card get one"); count()

-- ---------------------------------------------------------------- the real data
local data, C, P = Gen.make()
local byKey = {}
for _, f in ipairs(data.features) do
	byKey[f.key] = f
end
for _, key in ipairs({"tower", "rift", "arena", "battleground", "dungeons", "bosses", "descent", "raid", "siege", "invasion",
		"bounty", "daily", "weeklychest", "embercache", "season", "factions", "gamble", "goals"}) do
	ok(byKey[key], "card " .. key); count()
end
-- every unlock entry opens a card
local unlockCard = {}
for _, f in ipairs(data.features) do
	for _, u in ipairs(f.unlocks or {}) do
		unlockCard[u] = f.key
	end
end
for _, e in ipairs(C.unlocks.entries) do
	ok(unlockCard[e.key], "unlock entry " .. e.key .. " has a card"); count()
end
-- every goal key of a card exists, and the goal is not listed twice
local goalOwner = {}
for _, f in ipairs(data.features) do
	for _, g in ipairs(f.goals or {}) do
		ok(not goalOwner[g], "goal " .. g .. " on one card only"); count()
		goalOwner[g] = f.key
	end
end
-- the windows are client modules
local listing = io.popen("ls ../client/overlay/modules")
local modules = {}
for name in listing:lines() do
	modules[name] = true
end
listing:close()
for _, f in ipairs(data.features) do
	ok(not f.window or modules[f.window], f.key .. ": window module " .. tostring(f.window)); count()
end
-- both languages of a hand sentence use the same {places}
local function places(text)
	local set = {}
	for n in text:gmatch("{(%w+)}") do
		set[n] = true
	end
	local list = {}
	for n in pairs(set) do
		list[#list + 1] = n
	end
	table.sort(list)
	return table.concat(list, ",")
end
for _, f in ipairs(P.features) do
	for _, id in ipairs(P.rows) do
		if f[id] then
			eq(places(f[id][1]), places(f[id][2]), f.key .. "." .. id .. ": same places in en and pt"); count()
		end
	end
end
eq(places(P.gentle.en), places(P.gentle.pt), "gentle: same places"); count()
-- every card answers who, drops and often or death; the fight cards have all five
local function rowText(key, id, lang)
	for _, r in ipairs(byKey[key].rows) do
		if r.id == id then
			return r[lang]
		end
	end
end
ok(rowText("tower", "levels", "en"):find("level 100", 1, true), "tower: floor 1 level"); count()
ok(rowText("tower", "who", "en"):find("up to 4", 1, true), "tower: party size from the run file"); count()
ok(rowText("rift", "who", "pt"):find("Nível 100+", 1, true), "rift: pt level"); count()
ok(rowText("arena", "often", "en"):find("10 rewarded wins", 1, true), "arena: daily wins"); count()
ok(rowText("raid", "often", "en"):find("Monday at 06:00", 1, true), "raid: weekly reset"); count()
ok(rowText("siege", "often", "en"):find("Saturday at 20:00", 1, true), "siege: day and time"); count()
ok(rowText("siege", "often", "pt"):find("sábado às 20:00", 1, true), "siege: pt day"); count()
ok(rowText("invasion", "often", "en"):find("Wednesday 19:30 and Sunday 17:30", 1, true), "invasion: schedule"); count()
ok(rowText("bosses", "often", "en"):find("03:00, 09:00, 15:00, 21:00", 1, true), "world boss hours"); count()
ok(rowText("tower", "death", "en"):find("never lose items", 1, true), "death rule text"); count()
ok(rowText("season", "often", "pt"):find("20/11/2026", 1, true), "season dates"); count()
ok(rowText("descent", "often", "pt"):find("50.000", 1, true), "pt thousands"); count()
ok(rowText("pets", "what", "en"):find("companion", 1, true), "unlock card text is the entry's own"); count()

-- the numbers are derived: change a config, the text follows
do
	local C2 = Gen.load()
	C2.arena.minLevel = 77
	C2.arena.reward.maxRewardedWinsPerDay = 33
	C2.siege.weekday = 2
	C2.towerRun.maxPartySize = 9
	local d2 = Gen.build(C2, P)
	local cards = {}
	for _, f in ipairs(d2.features) do
		cards[f.key] = f
	end
	local function row(key, id)
		for _, r in ipairs(cards[key].rows) do
			if r.id == id then
				return r.en
			end
		end
	end
	ok(row("arena", "who"):find("Level 77+", 1, true), "arena level follows the config"); count()
	ok(row("arena", "often"):find("33 rewarded wins", 1, true), "arena wins follow the config"); count()
	ok(row("siege", "often"):find("Monday at 20:00", 1, true), "siege day follows the config"); count()
	ok(row("tower", "who"):find("up to 9", 1, true), "tower party follows the run file value"); count()
end
-- the death text refuses a server that takes items
do
	local C3 = Gen.load()
	C3.gentle.keepItems = false
	fails(function() Gen.build(C3, P) end, "keepItems", "items lost on death"); count()
end

-- stable and equal to the committed file
local text = Gen.render(data)
eq(Gen.render(select(1, Gen.make())), text, "byte-stable"); count()
local f = assert(io.open("../client/overlay/modules/game_howitworks/howitworks_data.lua", "rb"))
local committed = f:read("*a")
f:close()
eq(committed, text, "client file is up to date: run luajit tools/gen_howitworks_data.lua"); count()
ok(not text:find("\226\128\148"), "no em-dash"); count()

print(string.format("howitworks_gen: %d checks ok", checks))
