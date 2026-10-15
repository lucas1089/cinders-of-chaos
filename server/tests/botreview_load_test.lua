-- Run from the server/ folder: luajit tests/botreview_load_test.lua [-v] (or lua5.3; CI runs both)
-- Bot review cost under load, against a mocked engine: 400 online characters (the launch maxPlayers; pairs on one IP,
-- parties of four) play half a simulated hour through antibot.lua's hooks with botreview.lua's wrappers, the kill /
-- combat / look callbacks and both ticks. Measures, in CPU time of this machine:
--   the extra cost per hooked event (wrapped minus unwrapped antibot core calls),
--   one botreview tick (10 s) and one evaluation,
--   one cluster pass,
--   memory per character after it.
-- The bounds are loose (a slow CI machine passes); -v prints the numbers. server/README.md "Bot detection" quotes them.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
local verbose = arg and arg[1] == "-v"
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

dofile("data/scripts/chaos/chaos_constants.lua")
local PLAYERS = 400
local HOUR = 1800 -- simulated seconds of play (half an hour keeps CI fast; every character is evaluated 6 times)

-- ---------------------------------------------------------------- a mocked engine
local clockS, clockMs = 1790000000, 1790000000000
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return clockS end
os.mtime = function() return clockMs end
local quiet = print
print = function() end
db = {query = function() return true end, asyncQuery = function() return true end, storeQuery = function() return false end,
	escapeString = function(s) return "'" .. tostring(s) .. "'" end, lastInsertId = function() return 0 end}
result = {free = function() end}
json = {encode = function(t) return t end}
local events, globals, callbacks = {}, {}, {}
function CreatureEvent(name)
	local e = {type = function() end, register = function() end}
	events[name] = e
	return e
end
function GlobalEvent(name)
	local e = {interval = function() end, type = function() end, register = function() end}
	globals[name] = e
	return e
end
function TalkAction() return {separator = function() end, register = function() end} end
EventCallback = setmetatable({}, {__newindex = function(t, k, v)
		callbacks[k] = callbacks[k] or {}
		table.insert(callbacks[k], v)
	end,
	__index = function(t, k) if k == "register" then return function() end end end})
addEvent = function() end
function ItemType(id) return {getClientId = function() return id end, isCorpse = function() return false end} end
function MonsterType() return nil end
Chaos.send = function() return true end
Chaos.select = function() return {} end

local P = {}
P.__index = P
local players, list = {}, {}
local parties = {}
function P:getId() return self.id end
function P:getGuid() return self.guid end
function P:getName() return self.name end
function P:getAccountId() return self.guid end
function P:getIp() return self.ip end
function P:getParty() return self.party end
function P:getHealth() return self.hp end
function P:getMaxHealth() return 1000 end
function P:getDirection() return self.dir end
function P:getGroup() return {getId = function() return 1 end, getAccess = function() return false end} end
function P:getPosition() return {x = self.x, y = self.y, z = 7} end
function P:getStorageValue() return -1 end
function P:setStorageValue() end
function P:registerEvent() end
function P:sendTextMessage() end
function P:getTarget() return nil end
function P:isPlayer() return true end
function P:isMonster() return false end
function P:getMaster() return nil end
function P:isPzLocked() return false end
for i = 1, PLAYERS do
	local p = setmetatable({id = 10000 + i, guid = i, name = "Char" .. i, ip = math.floor((i + 1) / 2), hp = 1000, dir = 0,
		x = 1000 + i * 3, y = 1000, phase = i}, P)
	local pk = math.floor((i - 1) / 4)
	parties[pk] = parties[pk] or {getLeader = function() return list[pk * 4 + 1] end}
	p.party = parties[pk]
	players[p.id] = p
	list[#list + 1] = p
end
function Player(x) return type(x) == "number" and players[x] or nil end
Game = {getPlayers = function() return list end}
local monsters = {}
local function monster(id)
	local m = monsters[id]
	if not m then
		m = {getId = function() return id end, isMonster = function() return true end, isPlayer = function() return false end,
			getMaster = function() return nil end, getName = function() return "Rat" end}
		monsters[id] = m
	end
	return m
end

dofile("data/scripts/chaos/antibot.lua")
local K = ChaosAntibotCore
local orig = {onAction = K.onAction, onDamage = K.onDamage, onSelfHeal = K.onSelfHeal, onPosition = K.onPosition}
dofile("data/scripts/chaos/botreview.lua")
dofile("data/scripts/chaos/reports.lua")
local AB, BV, BR = ChaosAntibot, ChaosBotReview, ChaosBotReviewCore
check(K.onAction ~= orig.onAction and K.onPosition ~= orig.onPosition, "antibot core wrapped")
for _, p in ipairs(list) do
	events.ChaosAntibotLogin.onLogin(p)
	events.ChaosBotReviewLogin.onLogin(p)
end

-- ---------------------------------------------------------------- 1. extra cost per hooked event
local acfg = Chaos.antibotConfig
local function eventLoop(fns, rounds)
	local c0 = os.clock()
	for r = 1, rounds do
		local p = list[r % PLAYERS + 1]
		local st = AB.states[p.guid]
		clockMs = clockMs + 7
		fns.onDamage(st, acfg, clockMs)
		fns.onSelfHeal(st, acfg, clockMs + 3, clockS)
		fns.onAction(st, acfg, clockMs + 5, clockS, "s1", false)
		fns.onPosition(st, acfg, p.x + r % 97, p.y + r % 53, 7, clockS, clockMs)
	end
	return (os.clock() - c0) / (rounds * 4)
end
local ROUNDS = 30000
local base = eventLoop(orig, ROUNDS)
local wrapped = eventLoop(K, ROUNDS)
local perEventUs = math.max(0, wrapped - base) * 1e6

-- ---------------------------------------------------------------- 2. one simulated hour of play
collectgarbage("collect")
local memBefore = collectgarbage("count")
local tickTimes, evals0 = {}, BV.stats.evals
local h = events.ChaosAntibotHealth.onHealthChange
local combat = callbacks.onTargetCombat[#callbacks.onTargetCombat]
local look = callbacks.onLook[#callbacks.onLook]
local kill = events.ChaosBotReviewKill.onKill
local function rate(r) return math.random() < r end
math.randomseed(7)
local hookTime, hookEvents = 0, 0
for s = 1, HOUR do
	clockS = clockS + 1
	clockMs = clockMs + 1000
	local c0 = os.clock()
	for _, p in ipairs(list) do
		-- per second: a hit, a cast, a combat event, now and then a heal, a kill and a look; a step every 2 s
		if rate(0.7) then p.hp = math.max(100, p.hp - 60); h(p, monster(p.guid * 1000 + p.phase), 60, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, 0) end
		if rate(0.6) then K.onAction(AB.states[p.guid], acfg, clockMs + p.phase, clockS, "s1", false) end
		if rate(0.15) then
			kill(p, monster(p.guid * 1000 + p.phase))
			p.phase = p.phase + 1
		end
		if rate(0.8) then combat(p, monster(p.guid * 1000 + p.phase)) end
		if p.hp < 700 and rate(0.5) then h(p, p, 300, COMBAT_HEALING, 0, COMBAT_NONE, 0); p.hp = 1000 end
		if rate(0.003) then look(p, p, {}, 1, "") end
		hookEvents = hookEvents + 3
		if s % 2 == 0 then
			p.x = 1000 + math.floor(60 * math.cos((s + p.guid) / 40))
			p.y = 1000 + math.floor(60 * math.sin((s + p.guid) / 40))
		end
	end
	hookTime = hookTime + (os.clock() - c0)
	if s % 2 == 0 then AB.tick() end
	if s % 10 == 0 then
		local t0 = os.clock()
		BV.tick()
		tickTimes[#tickTimes + 1] = os.clock() - t0
	end
end
for k in pairs(monsters) do monsters[k] = nil end -- the mock's own monster objects are not the bot review's memory
collectgarbage("collect")
local perCharKb = (collectgarbage("count") - memBefore) / PLAYERS
local evals = BV.stats.evals - evals0
table.sort(tickTimes)
local tickSum = 0
if verbose then quiet(string.format("slowest ticks: %.2f %.2f %.2f ms", tickTimes[#tickTimes] * 1000, tickTimes[#tickTimes - 1] * 1000, tickTimes[#tickTimes - 2] * 1000)) end
for _, t in ipairs(tickTimes) do tickSum = tickSum + t end

-- ---------------------------------------------------------------- 3. one evaluation and one cluster pass on their own
local st = BV.states[1]
local e0 = os.clock()
for i = 1, 200 do
	st.nextEval = 0
	BV.evaluate(list[1], st, clockS)
end
local perEvalMs = (os.clock() - e0) / 200 * 1000
-- best of three, each after a full collection: a garbage-collector step from the large tables loaded earlier (the
-- i18n strings) must not land inside a single timed pass on a busy CI machine
local clusterMs, pairsN = math.huge, 0
for _ = 1, 3 do
	collectgarbage("collect")
	local c0 = os.clock()
	pairsN = BV.clusterPass(list)
	clusterMs = math.min(clusterMs, (os.clock() - c0) * 1000)
end

print = quiet
local function line(fmt, ...) if verbose then print(string.format(fmt, ...)) end end
line("characters online                 %d", PLAYERS)
line("extra cost per hooked event       %.2f us (wrapped %.2f us, antibot alone %.2f us)", perEventUs, wrapped * 1e6, base * 1e6)
line("botreview tick (every 10 s)       mean %.2f ms, max %.2f ms (%d ticks, %d evaluations)", tickSum / #tickTimes * 1000,
	tickTimes[#tickTimes] * 1000, #tickTimes, evals)
line("one evaluation                    %.3f ms", perEvalMs)
line("one cluster pass                  %.2f ms (%d pairs; every 300 s)", clusterMs, pairsN)
line("memory per character after %d min  %.1f KB (antibot and bot review together)", HOUR / 60, perCharKb)
line("game-loop share of the bot review %.3f%% (ticks + evaluations; hooks: %.2f us x %d events)",
	(tickSum + perEventUs * 1e-6 * hookEvents) / HOUR * 100, perEventUs, hookEvents)

eq = nil
check(evals >= PLAYERS * HOUR / 300 - PLAYERS and evals <= PLAYERS * HOUR / 300 + PLAYERS, "every character evaluated about every 300 s (" .. evals .. ")")
check(perEventUs < 20, "a wrapped hook adds under 20 us (" .. string.format("%.2f", perEventUs) .. ")")
check(perEvalMs < 5, "one evaluation under 5 ms (" .. string.format("%.3f", perEvalMs) .. ")")
check(tickSum / #tickTimes < 0.02, "a botreview tick under 20 ms on average for 400 characters")
check(clusterMs < 100, "a cluster pass under 100 ms")
check(perCharKb < 200, "under 200 KB per character")
check((tickSum + perEventUs * 1e-6 * hookEvents) / HOUR < 0.01, "under 1% of one core in total")
print(string.format("botreview_load_test: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end
