-- Run from the server/ folder: luajit tests/trials_probe_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- What a person sees of the Vocation Trials, for the tester bots (O595; ChaosTrials.probe, ChaosTrialsCore.guide, ChaosTrials.testerClose; helper
-- `!tester trial`), and the rule of a tester beside the players: the chambers kept for the players.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ------------------------------------------------------------------ engine mocks
local events = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() events[name or (kind .. "#" .. tostring(e))] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction, Action, MoveEvent, ModalWindow = eventMock("creature"), eventMock("global"), eventMock("talk"),
	eventMock("action"), eventMock("move"), eventMock("modal")
EventCallback = setmetatable({}, {__index = function() return function() end end})
GAME_STATE_NORMAL, GAME_STATE_CLOSED, GAME_STATE_SHUTDOWN = 1, 2, 3
db = {query = function() return true end, asyncQuery = function() return true end, storeQuery = function() return false end,
	escapeString = function(s) return "'" .. s .. "'" end}
result = {free = function() end}
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end, getDistance = function(self, o) return math.max(math.abs(self.x - o.x), math.abs(self.y - o.y)) end} end
Game = {
	getGameState = function() return 1 end,
	createItem = function() return nil end,
	getPlayers = function() return {} end,
	getSpectators = function() return {} end,
	getExperienceStage = function() return 1 end,
	getStorageValue = function() return -1 end,
	createTile = function() return nil end,
}
ItemType = function(id) return {getId = function() return id end, getName = function() return "item" .. id end} end
local players = {}
Player = function(id) return players[id] end
local monsters = {}
Monster = function(id) return monsters[id] end
json = {encode = function() return "{}" end, decode = function() return {} end}
local pzTiles = {}
Tile = function(p)
	return {hasFlag = function(_, f) return f == TILESTATE_PROTECTIONZONE and pzTiles[p.x .. "," .. p.y .. "," .. p.z] == true end}
end
addEvent = function() return 0 end
os.mtime = function() return 1000000 end

dofile("data/scripts/chaos/trials.lua")
local T, M, cfg = ChaosTrials, ChaosTrialsCore, ChaosTrialsConfig or ChaosTrialsCore.cfg()
ok(T ~= nil and T.probe ~= nil, "ChaosTrials.probe is there")

-- ------------------------------------------------------------------ the pure guide
do
	local at = {x = 100, y = 100, z = 7}
	local function g(o)
		local a = {inRun = true, phase = "fight", stage = "wave", pos = at, reach = 5}
		for k, v in pairs(o) do a[k] = v end
		return M.guide(a)
	end
	eq(g({inRun = false}).mode, "wait", "outside: wait")
	eq(g({phase = "countdown"}).mode, "wait", "the countdown: wait")
	local r = g({stage = "seals"})
	ok(r.mode == "wait" and r.area == "puzzle", "a seals stage is a puzzle: wait")
	eq(g({stage = "marks"}).area, "puzzle", "a marks stage is a puzzle: wait")
	eq(g({}).mode, "wait", "no monster in sight: wait")
	r = g({monster = {pos = {x = 112, y = 100, z = 7}}})
	ok(r.mode == "walk" and r.goal.x == 112 and r.area == "pack" and r.reach[2] == 5, "a thrall far away: walk to it")
	eq(g({monster = {pos = {x = 104, y = 103, z = 7}}}).mode, "fight", "within 5 tiles: fight")
	eq(g({stage = "boss", monster = {pos = {x = 101, y = 100, z = 7}, boss = true}}).area, "boss", "the guardian")
end

-- ------------------------------------------------------------------ a fake tester and a run
local temple = Position(100, 100, 7)
local function newPlayer(id, name, tester, voc)
	local p = {id = id, guid = id, name = name, storage = {}, msgs = {}, at = Position(1, 1, 7), tester = tester, voc = voc or 1}
	p.getId = function() return p.id end
	p.getGuid = function() return p.guid end
	p.getName = function() return p.name end
	p.getStorageValue = function(_, k) return k == Chaos.storage.tester and (p.tester and 1 or -1) or (p.storage[k] or -1) end
	p.setStorageValue = function(_, k, v) p.storage[k] = v end
	p.sendTextMessage = function(_, _, text) p.msgs[#p.msgs + 1] = text end
	p.sendCancelMessage = function(_, text) p.cancel = text end
	p.getPosition = function() return p.at end
	p.teleportTo = function(_, to) p.at = to end
	p.getTown = function() return {getTemplePosition = function() return temple end} end
	p.getLevel = function() return 150 end
	p.getVocation = function() return {getId = function() return p.voc end} end
	p.getBankBalance = function() return 0 end
	p.getCondition = function() return nil end
	p.registerEvent = function() end
	p.unregisterEvent = function() end
	p.removeCondition = function() end
	p.save = function() end
	p.getMaxHealth = function() return 100 end
	p.getHealth = function() return 100 end
	p.getMaxMana = function() return 100 end
	p.getMana = function() return 100 end
	p.addMana = function() end
	p.sendExtendedOpcode = function() end
	p.addHealth = function() end
	p.getIp = function() return 0 end
	p.getGroup = function() return {getId = function() return 1 end} end
	players[id] = p
	return p
end
local function vocOf(familyKey) return M.cfg().families[familyKey].voc[1] end

do
	local warrior = newPlayer(1, "Tester Aaa", true, vocOf("warrior"))
	pzTiles["1,1,7"] = true
	local pr = T.probe(warrior)
	ok(pr.inside == false and pr.level == 150 and pr.pz == true and pr.run == nil, "outside: level, zone, no run")
	ok(pr.family == "warrior" and pr.tier == 1 and pr.minLevel == M.cfg().tiers[1].minLevel and pr.cleared == 0, "outside: the family and the next tier")
	ok(pr.puzzle == nil and pr.kinds[#pr.kinds] == "boss" and pr.kinds[1] == "wave", "outside: the stages of a wave family, the guardian last")
	eq(pr.free, cfg.limits.maxRuns, "every chamber is free")
	eq(pr.reserve, cfg.tester.reserve, "the reserve is told")
	local mystic = newPlayer(2, "Tester Bbb", true, vocOf("mystic"))
	pr = T.probe(mystic)
	eq(pr.puzzle, true, "a Mystic's trial has a puzzle stage")
	local thief = newPlayer(3, "Tester Ccc", true, vocOf("thief"))
	eq(T.probe(thief).puzzle, true, "a Thief's trial has a puzzle stage")
	local none = newPlayer(4, "Tester Ddd", true, 0)
	ok(T.probe(none).family == nil and T.probe(none).tier == nil, "a character with no trial: no family")
end

-- a run, built by hand as T.enter does
do
	local a = newPlayer(10, "Tester Eee", true, vocOf("warrior"))
	local c = M.cfg()
	local stages = M.stages("warrior", 1)
	local tr = {pid = a.id, slot = 1, voc = a.voc, famKey = "warrior", tier = 1, tierDef = c.tiers[1], stages = stages, stageIdx = 1, stage = stages[1],
		killed = 2, total = 10, lives = 3, livesMax = 3, phase = "fight", bossState = "waiting", over = false, adds = {},
		deadline = 1000000 + 300000, back = Position(1, 1, 7)}
	T.runs[a.id] = tr
	a.at = Position(50, 50, 7)
	local function mon(id, x, y, hp)
		local m = {id = id, hp = hp or 100, at = Position(x, y, 7)}
		function m:getPosition() return self.at end
		function m:getHealth() return self.hp end
		function m:getMaxHealth() return 100 end
		function m:remove() monsters[id] = nil end
		monsters[id] = m
		T.monsterRun[id] = a.id
		return m
	end
	mon(501, 60, 50)
	mon(502, 53, 51)
	local pr = T.probe(a)
	ok(pr.inside and pr.run.tier == 1 and pr.run.phase == "fight" and pr.run.stage == "wave" and pr.run.killed == 2 and pr.run.total == 10, "inside: the counts")
	ok(pr.run.lives == 3 and pr.run.monsters == 2 and pr.run.left == 300 and pr.run.stages == #stages, "the lives, the monsters, the clock")
	ok(pr.guide.mode == "fight" and pr.guide.goal.x == 53, "the nearest thrall is in reach: fight")
	monsters[502] = nil
	T.monsterRun[502] = nil
	pr = T.probe(a)
	ok(pr.guide.mode == "walk" and pr.guide.goal.x == 60, "the next one: walk")
	-- the guardian
	tr.stageIdx, tr.stage, tr.bossId, tr.bossState = #stages, stages[#stages], 501, "alive"
	pr = T.probe(a)
	ok(pr.run.boss == "alive" and pr.run.bossHp == 100 and pr.run.bossPos.x == 60 and pr.guide.area == "boss", "the guardian: health, place, the guide goes for it")
	-- a puzzle stage
	tr.stage = {kind = "seals", count = 3}
	eq(T.probe(a).guide.area, "puzzle", "a seals stage: the guide waits")
	-- the close: only the asker, a failed run with no cooldown
	local b = newPlayer(11, "Tester Fff", true, vocOf("warrior"))
	eq(T.testerClose(b), false, "a bot with no run: nothing to close")
	eq(T.testerClose(a), true, "the asker's own run is closed")
	ok(tr.over, "the run is over")
	eq(T.testerClose(a), false, "twice does nothing")
end

-- ------------------------------------------------------------------ the rule of a tester beside the players
do
	ChaosTesters = {soloRefusal = function(group, free, reserve)
		local flags, any = {}, false
		for i, m in ipairs(group) do flags[i] = m.tester == true; any = any or flags[i] end
		if not any then return nil end
		dofile("data/scripts/chaos/testers_core.lua")
		local why = ChaosTestersCore.soloRefusal(flags, free, reserve)
		return why and ChaosTestersCore.CLOSED_TEXT[why] or nil
	end}
	local t = newPlayer(20, "Tester Ggg", true, vocOf("warrior"))
	pzTiles["1,1,7"] = true
	for i = 1, cfg.limits.maxRuns - cfg.tester.reserve + 1 do T.runs[100 + i] = {over = true} end
	local okT, whyT = T.enter(t, 1)
	eq(okT, false, "a tester is refused when fewer than the reserve would stay free")
	eq(whyT, ChaosTestersCore.CLOSED_TEXT.reserve, "the refusal says the chambers are the players'")
	for i = 1, cfg.limits.maxRuns - cfg.tester.reserve + 1 do T.runs[100 + i] = nil end
end

-- O685: the held nodes in the probe, and the TEST ONLY clear of the tier of a family whose trial is a puzzle (`!tester trial clear`)
do
	local mystic = newPlayer(30, "Tester Fff", true, vocOf("mystic"))
	local pr = T.probe(mystic)
	ok(pr.picks and pr.picks[1] == 0 and pr.picks[2] == 0 and pr.picks[3] == 0, "the probe lists the held node of each pair: none yet")
	local t, why = T.testerClear(mystic)
	eq(t, 3, "testerClear: the last tier by default")
	eq(mystic.storage[M.cfg().storage.tierBase + mystic.voc], 3, "the tier is stored for the vocation of the asker")
	pr = T.probe(mystic)
	ok(pr.cleared == 3 and pr.tier == 3 and pr.maxTier == 3, "the probe reads the cleared tiers")
	t = T.testerClear(mystic, 1)
	eq(t, 1, "testerClear 1: the tier asked")
	eq(T.probe(mystic).cleared, 1, "one tier cleared")
	t, why = T.testerClear(mystic, 4)
	ok(t == nil and why:find("0 to 3", 1, true), "testerClear: a tier above the last is refused with the reason")
	eq(T.probe(mystic).cleared, 1, "and nothing changed")
	t, why = T.testerClear(newPlayer(31, "Tester Ggg", true, 0))
	ok(t == nil and why:find("no trial", 1, true), "testerClear: a vocation with no trial")
	local busy = newPlayer(32, "Tester Hhh", true, vocOf("warrior"))
	T.runs[busy.id] = {pid = busy.id, over = false}
	t, why = T.testerClear(busy)
	ok(t == nil and why:find("inside", 1, true), "testerClear: not inside a trial")
	T.runs[busy.id] = nil
	-- a pick is a held node: the probe shows it after the window's own choose
	local warrior = newPlayer(33, "Tester Iii", true, vocOf("warrior"))
	T.testerClear(warrior, 2)
	local okc = T.choose(warrior, 2, 2)
	ok(okc, "the window's choose takes the B node of the second pair")
	local picks = T.probe(warrior).picks
	ok(picks[1] == 0 and picks[2] == 2 and picks[3] == 0, "the probe shows the held node: pair 2, side B")
end

print(string.format("trials_probe_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
