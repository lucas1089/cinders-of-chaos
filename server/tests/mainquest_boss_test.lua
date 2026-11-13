-- Run from the server/ folder: luajit tests/mainquest_boss_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The last page of the main quest (O551, mainquest_boss.lua) with the real Vocation Trials files on a mocked engine: the door, the
-- reward once, the retry cooldown, Vael's lines, and (owner decision D6) that the resistance of the phase's element is applied to the
-- boss's hit in the Trials' own combat hook, which replaces the hit the defence layer had worked out.
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

local registered, globals = {}, {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() registered[#registered + 1] = e; globals[name] = e end
		e.interval = function(self, ms) self.ms = ms end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = eventMock("creature"), eventMock("global"), eventMock("talk")
EventCallback = setmetatable({}, {__index = function() return function() end end})
function EventCallback.register() end
ChaosTierConfig = {skip = {}}
Game = {}
dofile("data/lib/chaos_spell_events.lua")
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/trials_core.lua")
assert(pcall(dofile, "data/scripts/chaos/trials.lua"))
assert(pcall(dofile, "data/scripts/chaos/trials_effects.lua"))
local T, M = ChaosTrials, ChaosTrialsCore

dofile("data/scripts/chaos/mainquest_core.lua")
local K = ChaosMainQuestCore
local cfg = K.cfg()
Chaos.lang = function() return "en" end
Chaos.giveItem = function(pl, id, count) pl.items[id] = (pl.items[id] or 0) + count; return count end
local okB, eB = pcall(dofile, "data/scripts/chaos/mainquest_boss.lua")
ok(okB, "mainquest_boss.lua loads: " .. tostring(eB))
local B = ChaosMainQuestBoss
ok(globals.ChaosMainQuestBossWatch ~= nil, "the watch event")
eq(type(T.hookFor) .. type(T.questHit) .. type(T.bossNameFor), "functionfunctionfunction", "the trial hooks are set")

-- the tier exists and is sized from the models
local idx, tier = M.spellTier("mq")
ok(idx ~= nil, "the spell trial mq")
eq(tier.minLevel, cfg.boss.minLevel, "the trial starts at the boss level")
local scale = M.spellScale("mq", 500, 0)
ok(scale.hp > 250000 and scale.hp < 320000, "about 282,000 health at level 500: " .. tostring(scale.hp))
ok(scale.hit >= 0.08 and scale.hit <= 0.1, "a hit of the Cruel Trial's share")
eq(scale.lives, 3, "3 lives"); ok(scale.time >= 300 and scale.time <= 420, "time limit")

-- a player on a mocked engine
local byId = {}
local function newPlayer(id, level)
	local pl = {id = id, level = level, store = {}, msgs = {}, items = {}, bank = 0, pos = {x = 100, y = 100, z = 7}, maxHealth = 5000}
	function pl:getId() return self.id end
	function pl:getGuid() return self.id + 100 end
	function pl:getLevel() return self.level end
	function pl:getMaxHealth() return self.maxHealth end
	function pl:getStorageValue(k) return self.store[k] or -1 end
	function pl:setStorageValue(k, v) self.store[k] = v end
	function pl:getPosition() return self.pos end
	function pl:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function pl:getBankBalance() return self.bank end
	function pl:setBankBalance(v) self.bank = v end
	byId[id] = pl
	return pl
end
Player = function(id) return byId[id] end
local key = function(name) return cfg.storage.base + cfg.storage[name] end

-- the sheet of the defence layer
local resist = {fire = 30, ice = 0, energy = 0, earth = 0}
local pcts = {fire = 30, ice = 10, energy = 5, earth = 0}
ChaosPlayerDefence = {
	sheet = function() local r = {} for i, g in ipairs({"fire", "ice", "energy", "earth"}) do r[i] = {k = g, sum = pcts[g] + 30, pct = pcts[g]} end return {resist = r} end,
	resistOfElement = function(_, el) return resist[el] end
}
ok(B.sheetSafe(newPlayer(1, 500)), "four results at 0 or more: safe")
pcts.earth = -1
ok(not B.sheetSafe(byId[1]), "one negative result: not safe")
pcts.earth = 0

-- the door
Creature = function(name) return {getPosition = function() return {x = 102, y = 100, z = 7} end} end
local p = newPlayer(2, 500)
p.store[key("state")] = cfg.states.active
p.store[key("step")] = #cfg.steps
eq(B.doorProblem(p), nil, "level 500, safe, on the boss step: open")
p.level = 499; eq(B.doorProblem(p), "door_closed", "level 499")
p.level = 500; pcts.fire = -5; eq(B.doorProblem(p), "door_closed", "an unsafe resistance keeps it shut (strict)")
pcts.fire = 30
p.store[key("step")] = #cfg.steps - 1; eq(B.doorProblem(p), "door_closed", "not on the boss step yet")
p.store[key("state")] = cfg.states.skipped; eq(B.doorProblem(p), nil, "a skipped quest keeps the door")
p.store[key("cooldown")] = os.time() + 30; eq(B.doorProblem(p), "door_cooldown", "after a failed run")
p.store[key("cooldown")] = nil
-- entering: Ysolde must be near, the engine call is the Trials'
local entered
T.enter = function(player, tierIdx, opts) entered = opts; return true end
local okE, text = B.enter(p)
ok(okE and entered and entered.spell == "mq", "the door opens the mq trial"); eq(p.store[key("tries")], 1, "a try")
eq(text, cfg.vael.enter.en, "Vael's first line")
Creature = function() return {getPosition = function() return {x = 200, y = 100, z = 7} end} end
okE, text = B.enter(p)
ok(not okE and text == cfg.ysolde.door_closed.en, "Ysolde must be near")
Creature = function(name) return {getPosition = function() return {x = 102, y = 100, z = 7} end} end
-- the door flag set by Ysolde's script
local name, bit = K.flagPlace(cfg, "door")
p.store[key(name)] = bit
entered = nil
B.sweepDoor(p)
ok(entered ~= nil, "the sweep opens the door"); eq(p.store[key(name)], 0, "the flag is cleared")
ok(p.msgs[#p.msgs - 1]:find("Warden Ysolde: " .. cfg.ysolde.door_open.en, 1, true) ~= nil, "Ysolde opens the door")
ok(p.msgs[#p.msgs]:find("Vael Ashmourn: " .. cfg.vael.enter.en, 1, true) ~= nil, "Vael answers")

local enrageFamily
for k in pairs(M.cfg().families) do
	if M.hasMech(k, "enrage") and (not enrageFamily or k < enrageFamily) then enrageFamily = k end
end
ok(enrageFamily ~= nil, "a family with the enrage mechanic")
-- the boss's hit: the Trials' preHit applies the resistance of the phase's element (D6)
do
	local hp, maxhp = 90, 100
	Monster = function(id) if id == 9000 then return {getHealth = function() return hp end, getMaxHealth = function() return maxhp end, say = function() end} end end
	local pl = newPlayer(501, 500)
	T.runs[501] = {over = false, pid = 501, bossId = 9000, spell = "mq", famKey = enrageFamily, scale = {hit = 0.3, addHit = 0.1}}
	T.monsterRun[9000] = 501
	ChaosArchetypes = {percentBase = function(x) return x:getMaxHealth() end}
	local savedRandom = math.random
	math.random = function() return 0.5 end
	local boss = {getId = function() return 9000 end, isMonster = function() return true end, getMaxHealth = function() return maxhp end,
		getHealth = function() return hp end}
	resist = {fire = 0, ice = 0, energy = 0, earth = 0}
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -1500, "result 0: the design share of 5000")
	resist.fire = 30
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -1050, "fire result 30: 30% less in the fire phase")
	resist.fire = -40
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -2100, "fire result -40: 40% more")
	resist.fire = 0
	hp = 60 -- the cold phase: fire resistance no longer matters, the ice result does
	resist.fire = 75; resist.ice = 20
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -1200, "cold phase: the ice result counts")
	hp = 40; resist.energy = 50
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -750, "lightning phase")
	hp = 10; resist.earth = -100
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -4500, "chaos phase, floor -100: double, and the enrage (x1.5 under 30%) on top")
	-- another trial is untouched by the quest
	hp = 90
	T.runs[501].spell = "s1"
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -1500, "a line spell trial: no resistance here")
	T.runs[501].spell = nil
	eq(T.hooks.preHit(pl, boss, -50, COMBAT_PHYSICALDAMAGE, 0, COMBAT_NONE, ORIGIN_MELEE), -1500, "a tier trial: no resistance here")
	T.runs[501] = nil
	math.random = savedRandom
end
-- the effects file's own event runs the defence layer first and the trial's preHit after it: the order is the reason for T.questHit
do
	local src = io.open("data/scripts/chaos/trials_effects.lua"):read("*a")
	local a = src:find("hooks.preHit(creature, attacker, pd, pt, sd, st, origin)", 1, true)
	ok(a ~= nil, "preHit is called by the trial's health event")
	local tsrc = io.open("data/scripts/chaos/trials.lua"):read("*a")
	ok(tsrc:find("T.questHit", 1, true) and tsrc:find("T.hookFor", 1, true) and tsrc:find("T.bossNameFor", 1, true), "trials.lua calls the quest hooks")
end

-- the hooks and the reward
do
	local pl = newPlayer(600, 500)
	local tr = {spell = "mq"}
	eq(T.hookFor(tr), B.hook, "the quest's hook for the mq trial"); eq(T.hookFor({spell = "s1"}), nil, "none for the line spell trials")
	eq(T.bossNameFor(tr), "Vael Ashmourn", "the boss is named"); eq(T.bossNameFor({spell = "s1"}), nil, "no name for another trial")
	ChaosAchievements = {counters = {}, set = function(who, k, v) ChaosAchievements.counters[k] = v end}
	ChaosFactions = {gain = function(player, f, amount) ChaosFactions.got = {f, amount} end}
	local lines = B.hook.won(pl, tr)
	eq(pl.store[key("won")], 1, "won is stored"); eq(pl.bank, cfg.boss.reward.gold, "the gold")
	eq(pl.items[29857], 2, "two Orbs of Fate"); eq(pl.items[24692], 1, "an Orb of Sockets")
	eq(ChaosAchievements.counters.mainquest_boss, 1, "the achievement counter"); eq(ChaosFactions.got[1], "vigil", "Vigil reputation"); eq(ChaosFactions.got[2], 800, "800 reputation")
	eq(lines[1], cfg.vael.victory.en, "Vael's last line")
	B.hook.won(pl, tr)
	eq(pl.bank, cfg.boss.reward.gold, "paid once")
	local pl2 = newPlayer(601, 500)
	B.hook.failed(pl2, tr, "failed")
	ok(pl2.store[key("cooldown")] and pl2.store[key("cooldown")] > os.time(), "a failed run closes the door")
	ok(pl2.msgs[#pl2.msgs] == cfg.vael.defeat.en, "Vael's defeat line")
	local pl3 = newPlayer(602, 500)
	B.hook.failed(pl3, tr, "logout")
	eq(pl3.store[key("cooldown")], nil, "a cut-short run costs nothing")
end

-- Vael's lines by phase, once each, and the enrage
do
	local said = {}
	local hp = 100
	local boss = {getHealth = function() return hp end, getMaxHealth = function() return 100 end, say = function(_, t) said[#said + 1] = t end}
	Monster = function(id) return id == 7000 and boss or nil end
	local pl = newPlayer(700, 500)
	T.runs[700] = {over = false, pid = 700, bossId = 7000, spell = "mq"}
	B.watch(); B.watch()
	eq(#said, 1, "the first phase once"); eq(said[1], cfg.vael.phase1.en, "phase 1 line")
	hp = 70; B.watch(); eq(said[2], cfg.vael.phase2.en, "phase 2")
	hp = 40; B.watch(); eq(said[3], cfg.vael.phase3.en, "phase 3")
	hp = 20; B.watch(); eq(said[4], cfg.vael.phase4.en, "phase 4")
	ok(said[5] == cfg.vael.enrage.en, "the enrage line below 30%")
	hp = 10; B.watch(); eq(#said, 5, "nothing twice")
	T.runs[700] = nil
end

if fails > 0 then print("mainquest_boss_test: " .. fails .. " failure(s)"); os.exit(1) end
print(string.format("mainquest_boss_test: %d checks ok", checks))
