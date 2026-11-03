-- Run from the server/ folder: luajit tests/rumours_test.lua (and lua5.3; CI runs both)
-- Tavern rumours (O394): rumours_core.lua (regions, the hourly plan, the world boss, the candidates, the window, the
-- fee, once per player, false rumours), rumours_run.lua in an NPC state (a mocked player: fee, nothing new, no money),
-- the NPC's dialogue (chaos_service_npc.lua on a mocked NPC library) and rumours.lua (the spawner) on a mocked engine:
-- a true rumour names the monster, the place and a window that holds the minute the spawner creates it.
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		n = n + 1
		rawset(t, k, n)
		return n
	end
end})
loadstring = loadstring or load

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/rumours_core.lua")
local R = ChaosRumoursCore
local cfg = dofile("data/scripts/chaos/rumours_config.lua")

local function T(y, mo, d, h, mi)
	return os.time({year = y, month = mo, day = d, hour = h or 0, min = mi or 0, sec = 0})
end

-- ---------------------------------------------------------------- config
check(cfg.enabled == true, "on")
check(cfg.fee.base > 0 and cfg.fee.max <= 5000, "a small fee")
check(cfg.falseChance > 0 and cfg.falseChance < 50, "false rumours are the exception")
check(cfg.apparitions.chance > 0 and cfg.apparitions.chance <= 100, "appearance chance")
check(#cfg.apparitions.regions >= 1, "fixed regions")
local inv = dofile("data/scripts/chaos/invasion_config.lua")
for _, r in ipairs(cfg.apparitions.regions) do
	local found = false
	for _, a in ipairs(inv.areas) do
		if a.key == r.key and a.target.x == r.point.x and a.target.y == r.point.y and a.target.z == r.point.z then
			found = true
		end
	end
	check(found, r.key .. ": the point is the invasion area's target (read from the real map)")
end

-- ---------------------------------------------------------------- lcg and hours
local g1, g2 = R.lcg(42), R.lcg(42)
for _ = 1, 20 do
	eq(g1(1, 1000), g2(1, 1000), "the generator repeats")
end
local h = T(2026, 11, 3, 14)
eq(R.hourStart(h + 1799), h, "hour start")
eq(R.hourStart(h), h, "an hour start is its own")

-- ---------------------------------------------------------------- regions
local places = {
	places = {
		{id = "ashgrave_barrow", name = "Ashgrave Barrow", level = {120, 180}, arrival = {x = 100, y = 100, z = 7}},
		{id = "nameless", level = {1, 2}, arrival = {x = 1, y = 1, z = 7}},
		{id = "toolow", name = "Puppy Meadow", level = {1, 10}, arrival = {x = 2, y = 2, z = 7}},
		{id = "noarrival", name = "Lost", level = {100, 200}}
	},
	base = {
		{id = "ashgrave_barrow", name = "Ashgrave Barrow", level = {120, 180}, dest = {x = 9, y = 9, z = 7}},
		{id = "b1", name = "Dragon Lair", level = {300, 0}, dest = {x = 200, y = 200, z = 8}}
	}
}
local regions = R.regions(cfg, places)
eq(regions[1].key, "cinderholdfields", "the config's regions first")
eq(#regions, #cfg.apparitions.regions + 2, "named hunts in the level range with a point, each name once")
eq(regions[#cfg.apparitions.regions + 1].name, "Ashgrave Barrow", "a planned hunt")
eq(regions[#cfg.apparitions.regions + 1].level, 150, "its level: the middle of the band")
eq(regions[#regions].level, 300, "an open top band: its floor")
eq(regions[#regions].point.z, 8, "a base hunt by its destination")
eq(#R.regions(cfg, nil), #cfg.apparitions.regions, "no places file: the fixed regions")
eq(#R.regions({apparitions = {regions = {}, huntPlaces = false}}, places), 0, "huntPlaces off")

-- ---------------------------------------------------------------- the hourly plan
local hits, kinds, perRegion = 0, {}, {}
local day = T(2026, 11, 1)
for i = 0, 24 * 60 - 1 do
	local hour = R.hourStart(day + i * 3600 + 60)
	local p = R.planHour(cfg, hour, regions)
	local q = R.planHour(cfg, hour, regions)
	if p then
		hits = hits + 1
		eq(p.key, q.key, "same hour, same plan")
		eq(p.at, q.at, "same minute")
		check(p.at >= hour + cfg.apparitions.minute[1] * 60 and p.at <= hour + cfg.apparitions.minute[2] * 60, "minute in range")
		kinds[p.what] = (kinds[p.what] or 0) + 1
		perRegion[p.place] = true
		eq(p.level, p.region.level, "the region's level")
	else
		eq(q, nil, "no plan twice")
	end
end
local share = hits / (24 * 60)
check(share > cfg.apparitions.chance / 100 - 0.06 and share < cfg.apparitions.chance / 100 + 0.06,
	"about chance% of the hours: " .. share)
check((kinds["Treasure Goblin"] or 0) > (kinds["Gem Goblin"] or 0) and (kinds["Gem Goblin"] or 0) > (kinds["Shard Goblin"] or 0),
	"monsters by weight")
local nRegions = 0
for _ in pairs(perRegion) do
	nRegions = nRegions + 1
end
eq(nRegions, #regions, "every region gets picked")
eq(R.planHour(cfg, h, {}), nil, "no regions: no plan")
eq(R.planHour({apparitions = {chance = 0, monsters = cfg.apparitions.monsters}}, h, regions), nil, "chance 0")
local list = R.apparitions(cfg, day, day + 6 * 3600, regions)
for i = 2, #list do
	check(list[i].at > list[i - 1].at, "appearances in order")
end

-- ---------------------------------------------------------------- the world boss
local wb = Chaos.worldBoss
local nxt = R.worldBossNext(T(2026, 11, 3, 14, 10), wb)
eq(os.date("%H:%M", nxt), "15:00", "next world boss slot 15:00")
eq(os.date("%H:%M", R.worldBossNext(T(2026, 11, 3, 15, 0), wb)), "21:00", "strictly after now")
eq(R.worldBossName(wb, 1, "x"), wb.bosses[2].name, "the rotation's next boss")
eq(R.worldBossName(wb, #wb.bosses, "x"), wb.bosses[1].name, "the rotation wraps")
eq(R.worldBossName(wb, -1, "x"), wb.bosses[1].name, "nothing stored: the first")
eq(R.worldBossName({mode = "random", bosses = wb.bosses}, 1, "beast"), "beast", "random mode: unnamed")

-- ---------------------------------------------------------------- candidates
local now = T(2026, 11, 3, 14, 20)
local src = {regions = {}, invasions = {{at = now + 30 * 60, areaName = "Thornmere", factionName = "Orc Warband"},
	{at = now + 2 * 3600, areaName = "Far", factionName = "Late"}, {at = now + 60, areaName = "Soon", factionName = "Now"}},
	worldBoss = {at = T(2026, 11, 3, 15), name = "Kaelgor"}}
local cands = R.candidates(cfg, now, src)
eq(#cands, 2, "within the horizon and after the lead time")
eq(cands[1].kind, "invasion", "soonest first")
eq(cands[1].place, "Thornmere", "the invaded area")
eq(cands[2].kind, "worldboss", "then the world boss")
eq(#R.candidates({sources = {invasion = false, worldboss = false, apparition = false}}, now, src), 0, "sources off")

-- ---------------------------------------------------------------- the window
local rng = R.lcg(7)
for i = 1, 200 do
	local at = now + i * 97
	local lo, hi = R.window(at, rng, cfg.window)
	check(lo <= at and at <= hi, "the window holds the time")
	check(hi - lo <= (cfg.window.width + cfg.window.round) * 60, "the window is narrow")
	eq(lo % (cfg.window.round * 60), 0, "rounded")
end

-- ---------------------------------------------------------------- fee
eq(R.fee(cfg, 1), cfg.fee.base + cfg.fee.perLevel, "fee at level 1")
eq(R.fee(cfg, 100000), cfg.fee.max, "fee capped")

-- ---------------------------------------------------------------- once per player, false rumours
local heard = {}
local truthful = {falseChance = 0, window = cfg.window, horizonMinutes = 60, leadMinutes = 3, apparitions = cfg.apparitions}
local r1 = R.ask(truthful, heard, 1, now, cands, R.lcg(3), regions)
eq(r1.key, cands[1].key, "the soonest first")
check(not r1.lie, "true")
check(r1.lo <= cands[1].at and cands[1].at <= r1.hi, "the true time in the window")
local r2 = R.ask(truthful, heard, 1, now, cands, R.lcg(3), regions)
eq(r2.key, cands[2].key, "then the next one")
eq(R.ask(truthful, heard, 1, now, cands, R.lcg(3), regions), nil, "nothing new: nothing")
eq(R.ask(truthful, heard, 2, now, cands, R.lcg(3), regions).key, cands[1].key, "another player hears it too")
R.purge(heard, now + 3 * 3600)
eq(next(heard), nil, "past rumours forgotten")
local liar = {falseChance = 100, window = cfg.window, horizonMinutes = 60, leadMinutes = 3, apparitions = cfg.apparitions}
local lie = R.ask(liar, {}, 1, now, cands, R.lcg(5), regions)
check(lie.lie == true, "a false rumour")
eq(lie.kind, "apparition", "it names an appearance")
check(lie.place ~= cands[1].place, "another place")
check(lie.at > now and lie.at <= now + 60 * 60, "a time within the hour")
local lies = 0
for i = 1, 1000 do
	local r = R.ask(cfg, {}, i, now, cands, R.lcg(i * 13), regions)
	if r.lie then
		lies = lies + 1
	end
end
check(lies > 1000 * cfg.falseChance / 100 - 50 and lies < 1000 * cfg.falseChance / 100 + 50, "about falseChance% lies: " .. lies)

-- ---------------------------------------------------------------- the NPC side (rumours_run.lua), mocked engine
local storage = {}
Game = {getStorageValue = function(k) return storage[k] or -1 end, getPlayers = function() return {} end}
local paid = {}
local money = 100000
Chaos.pay = function(player, amount)
	if money < amount then
		return false
	end
	money = money - amount
	paid[#paid + 1] = amount
	return true
end
dofile("data/scripts/chaos/rumours_run.lua")
local M = ChaosRumoursRun
M.regionList = regions -- as if data/lib/chaos_hunt_places.lua were installed
local player = {getGuid = function() return 77 end, getLevel = function() return 300 end}
-- find an hour with an appearance and stand 20 minutes before it
local plan
for i = 0, 200 do
	plan = R.planHour(M.cfg, R.hourStart(day + i * 3600 + 60), regions)
	if plan then
		break
	end
end
check(plan ~= nil, "an appearance in the first days")
local t0 = plan.at - 20 * 60
M.cfg.falseChance = 0
local status, rumour, fee = M.ask(player, t0, R.lcg(1))
eq(status, "told", "told")
eq(fee, R.fee(M.cfg, 300), "the fee for level 300")
eq(paid[1], fee, "paid")
-- the soonest thing within the hour; when it is the appearance it names its monster and place
local cs = R.candidates(M.cfg, t0, M.sources(t0))
eq(rumour.key, cs[1].key, "the soonest candidate")
if rumour.key == plan.key then
	eq(rumour.what, plan.what, "the planned monster")
	eq(rumour.place, plan.place, "the planned place")
end
-- ask until nothing is new: then no fee
local guard = 0
repeat
	status = M.ask(player, t0, R.lcg(2))
	guard = guard + 1
until status == "nothing" or guard > 10
eq(status, "nothing", "nothing new in the end")
local before = #paid
eq(M.ask(player, t0, R.lcg(2)), "nothing", "still nothing")
eq(#paid, before, "no fee for nothing")
-- no money
local poor = {getGuid = function() return 78 end, getLevel = function() return 1 end}
money = 0
local st, f = M.ask(poor, t0, R.lcg(2))
eq(st, "money", "cannot pay")
eq(f, R.fee(M.cfg, 1), "the fee named")
money = 100000
eq((M.ask(poor, t0, R.lcg(2))), "told", "the rumour stayed untold, so it can be bought")
M.cfg.enabled = false
eq(M.ask(poor, t0), "off", "switched off")
M.cfg.enabled = true
-- the world boss from the global storage of the rotation
storage[wb.rotationStorage] = 2
local s2 = M.sources(T(2026, 11, 3, 14, 30))
eq(s2.worldBoss.name, wb.bosses[3].name, "the next boss after the stored one")
-- the invasions of invasion_config.lua (scheduled: Wednesday 19:30), resolved to names
local wed = T(2026, 11, 4, 19, 0) -- a Wednesday
local s3 = M.sources(wed)
local found = false
for _, s in ipairs(s3.invasions) do
	if os.date("%H:%M", s.at) == "19:30" then
		found = s.areaName ~= nil and s.factionName ~= nil
	end
end
check(found, "the scheduled invasion is a source, with its area and faction")

-- ---------------------------------------------------------------- the NPC's dialogue (mocked NPC library)
local said, callbacks = {}, {}
KeywordHandler = {new = function() return {} end}
NpcSystem = {parseParameters = function() end}
FocusModule = {new = function() return {} end}
NpcHandler = {new = function()
	local hd = {messages = {}}
	function hd:setCallback(cb, fn) callbacks[cb] = fn end
	function hd:getCallback(cb) return callbacks[cb] end
	function hd:isFocused() return true end
	function hd:say(text) said[#said + 1] = text end
	function hd:getMessage(t) return self.messages[t] end
	function hd:setMessage(t, m) self.messages[t] = m end
	function hd:addModule() end
	return hd
end}
ChaosNpcFocus = {hears = function() return true end}
local talker = {getGuid = function() return 900 end, getLevel = function() return 50 end,
	getStorageValue = function() return -1 end, getId = function() return 5 end}
Player = function() return talker end
SERVICE_KEY = "rumours"
dofile("data/npc/scripts/chaos_service_npc.lua")
local cb = callbacks[CALLBACK_MESSAGE_DEFAULT]
said = {}
cb(5, 1, "price")
check(said[1] and said[1]:find(tostring(R.fee(M.cfg, 50)), 1, true), "the price: " .. tostring(said[1]))
said = {}
cb(5, 1, "job")
check(said[1] and said[1]:find("Dorrin Alewright", 1, true), "the job")
-- a rumour at the planned hour: told, with the fee
M.heard = {}
local realTime = os.time
os.time = function(tt) if tt then return realTime(tt) end return t0 end
said = {}
eq(cb(5, 1, "any rumours?"), true, "handled")
check(said[1] and said[1]:find("gold, thank you", 1, true) and said[1]:find("server time", 1, true), "a rumour: " .. tostring(said[1]))
said = {}
for _ = 1, 10 do
	cb(5, 1, "rumours")
end
check(said[#said]:find("Nothing new", 1, true), "in the end, nothing new: " .. tostring(said[#said]))
os.time = realTime

-- ---------------------------------------------------------------- the spawner (rumours.lua)
local events, talks = {}, {}
GlobalEvent = function(name)
	local ev = {name = name}
	function ev:interval() end
	function ev:register() events[name] = self end
	return ev
end
TalkAction = function(words)
	local ta = {words = words}
	function ta:separator() end
	function ta:register() talks[words] = self end
	return ta
end
Position = function(x, y, z) return {x = x, y = y, z = z} end
local spawned = {}
ChaosInvasion = {tileOk = function(pos) return (pos.x + pos.y) % 3 == 0 end}
ChaosTreasureGoblin = {spawn = function(pos, opts) spawned[#spawned + 1] = {pos = pos, opts = opts} return {} end}
Game.getPlayers = function() return {{}} end
dofile("data/scripts/chaos/rumours.lua")
local S = ChaosRumours
check(events.ChaosRumoursSpawner ~= nil and events.ChaosRumoursStartup ~= nil, "spawner and startup registered")
check(talks["/rumours"] ~= nil, "staff command registered")
S.check(plan.at - 30)
eq(#spawned, 0, "not before its minute")
S.check(plan.at + 10)
eq(#spawned, 1, "spawned at its minute")
eq(spawned[1].opts.variant, plan.monster.variant, "the planned goblin variant")
eq(spawned[1].opts.level, plan.level, "at the region's level")
local d = math.max(math.abs(spawned[1].pos.x - plan.region.point.x), math.abs(spawned[1].pos.y - plan.region.point.y))
check(d >= M.cfg.apparitions.radius[1] and d <= M.cfg.apparitions.radius[2], "near the region's point: " .. d)
S.check(plan.at + 20)
eq(#spawned, 1, "once")
S.done = {}
S.check(plan.at + M.cfg.apparitions.graceSeconds + 30)
eq(#spawned, 1, "a missed minute is not made up for")
S.done = {}
Game.getPlayers = function() return {} end
S.check(plan.at + 10)
eq(#spawned, 1, "nobody online: no spawn")
-- the staff command is guarded
local denied = {getGroup = function() return {getAccess = function() return false end} end}
eq(talks["/rumours"].onSay(denied, "/rumours", ""), false, "a player's words stay chat")

print(string.format("rumours_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
