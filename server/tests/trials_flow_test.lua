-- Run from the server/ folder: luajit tests/trials_flow_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The Vocation Trials with a mocked engine: trials.lua and trials_effects.lua load without errors and without clashing names
-- (a table of one file was once overwritten by a function of the other), and the choice / switch / bonus flow works
-- against a fake player: first pick free, the other node refused without a token, the switch costs a token and gold, the
-- node stats reach the passive bonus table, the picks survive a "tree reset" and are per vocation.
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

-- engine mocks: only what the two files touch while loading
local registered = {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() registered[#registered + 1] = e end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = eventMock("creature"), eventMock("global"), eventMock("talk")
EventCallback = setmetatable({}, {__index = function() return function() end end})
function EventCallback.register() end
Game = {}
dofile("data/lib/chaos_spell_events.lua")

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/trials_core.lua")
local ok1, e1 = pcall(dofile, "data/scripts/chaos/trials.lua")
ok(ok1, "trials.lua loads: " .. tostring(e1))
local ok2, e2 = pcall(dofile, "data/scripts/chaos/trials_effects.lua")
ok(ok2, "trials_effects.lua loads: " .. tostring(e2))
local T, M = ChaosTrials, ChaosTrialsCore
eq(type(T.state), "function", "T.state is trials.lua's client state")
eq(type(T.nodeState), "table", "T.nodeState is the effects file's per-player table")
eq(type(T.hooks.preHit) .. type(T.hooks.catch), "functionfunction", "the run's combat hooks are set")
eq(type(T.addBonuses), "function", "addBonuses")
ok(#registered >= 8, "events registered: " .. #registered)
-- spell event handlers are registered for cost and cooldown
local found = {}
for _, kind in ipairs({"cost", "cooldown"}) do
	for _, h in ipairs(ChaosSpellEvents.handlers[kind]) do
		if h.key == "chaostrials" then found[kind] = true end
	end
end
ok(found.cost and found.cooldown, "spell event handlers")
local cost = ChaosSpellEvents.handlers.cost[1]
ChaosPassiveCache = {[1] = {trialNodes = 1, spellCost = -20, spellCd = -15}}
local fake = {getId = function() return 1 end}
local mana = select(1, ChaosSpellEvents.onSpellCost(fake, "x", 1, 1, true, 1000, 0))
eq(mana, 800, "spellCost -20% applies")
eq(ChaosSpellEvents.onSpellCooldown(fake, "x", 1, 1, true, 1, 4000), 3400, "spellCd -15% applies")
ChaosPassiveCache = {[1] = {trialNodes = 1, spellCd = -50}}
eq(ChaosSpellEvents.onSpellCooldown(fake, "x", 1, 1, true, 1, 1500), 1000, "a cooldown never drops below 1 s")
ChaosPassiveCache = {}

-- a fake player
local function newPlayer(voc, level, gold)
	local p = {voc = voc, level = level, gold = gold, storage = {}, applied = 0}
	p.getVocation = function() return {getId = function() return p.voc end} end
	p.getLevel = function() return p.level end
	p.getId = function() return 77 end
	p.getStorageValue = function(_, k) return p.storage[k] or -1 end
	p.setStorageValue = function(_, k, v) p.storage[k] = v end
	p.removeTotalMoney = function(_, amount) if p.gold >= amount then p.gold = p.gold - amount return true end return false end
	p.isPzLocked = function() return false end
	p.hasCondition = function() return false end
	p.sendExtendedOpcode = function() end
	return p
end
local applied = 0
ChaosPassiveTree = ChaosPassiveTree or {}
ChaosPassiveTree.apply = function() applied = applied + 1 end
local achieved = {}
ChaosAchievements = {progress = function(_, k, v) achieved[k] = (achieved[k] or 0) + v end, set = function(_, k, v) achieved[k] = v end}

local S = Chaos.trials.storage
local p = newPlayer(8, 300, 1000000) -- a Juggernaut
local done, text = T.choose(p, 1, 1)
ok(not done and text:find("Locked"), "nothing is open before a clear: " .. tostring(text))
p:setStorageValue(S.tierBase + 8, 1) -- Normal cleared
done, text = T.choose(p, 1, 1)
ok(done and text:find("is yours"), "the first pick is free: " .. tostring(text))
eq(p.gold, 1000000, "free: no gold taken"); eq(applied, 1, "bonuses re-applied")
eq(achieved.trial_nodes, 1, "achievement stat: nodes held")
done, text = T.choose(p, 1, 2)
ok(not done and text:find("Trial Token"), "the other node is refused without a token: " .. tostring(text))
eq(T.picks(p, 8)[1], 1, "still holding the first")
-- the node reaches the bonus table
local pre = {takeAll = 3, dealAll = 5}
local bonuses = {takeAll = 3, dealAll = 5}
T.addBonuses(p, bonuses)
local held = M.pairsOf(8)[1].a
for key, v in pairs(held.fx) do eq(bonuses[key], (pre[key] or 0) + v, "fx " .. key .. " summed into the bonus table") end
for key, v in pairs(held.cost) do eq(bonuses[key], (pre[key] or 0) + v, "cost " .. key .. " summed into the bonus table") end
eq(bonuses.trialNodes, 1, "one node held")
-- a token and not enough gold
p:setStorageValue(S.tokens, 1)
p.gold = 100
done, text = T.choose(p, 1, 2)
ok(not done and text:find("gold"), "not enough gold: " .. tostring(text))
eq(p:getStorageValue(S.tokens), 1, "the token is kept when the gold is missing")
p.gold = 1000000
done, text = T.choose(p, 1, 2)
ok(done, "the switch works with a token and gold: " .. tostring(text))
eq(p.gold, 1000000 - 300 * Chaos.trials.switch.goldPerLevel, "gold taken by level")
eq(p:getStorageValue(S.tokens), 0, "token spent")
eq(T.picks(p, 8)[1], 2, "now holding the other node")
eq(achieved.trial_switches, 1, "achievement: a switch")
-- a locked pair, the same node, a bad pair
ok(not T.choose(p, 3, 1), "pair 3 is locked")
ok(not T.choose(p, 1, 2), "holding it already")
ok(not T.choose(p, 9, 1) and not T.choose(p, 1, 5), "out of range")
-- tier 3: all three pairs
p:setStorageValue(S.tierBase + 8, 3)
ok(T.choose(p, 2, 1) and T.choose(p, 3, 2), "free picks of pairs 2 and 3")
local b2 = {}
T.addBonuses(p, b2)
eq(b2.trialNodes, 3, "three nodes held")
eq(achieved.trial_nodes, 3, "three nodes achievement stat")
-- other vocations do not see these picks, the picks survive a tree reset (nothing in the passive tree touches them)
local q = newPlayer(14, 300, 0)
q.storage = p.storage
local b3 = {}
T.addBonuses(q, b3)
eq(b3.trialNodes, nil, "another vocation holds nothing of the Juggernaut's")
local u = newPlayer(99, 300, 0)
local b4 = {}
T.addBonuses(u, b4)
eq(next(b4), nil, "a vocation without a trial gets nothing")
-- giving a pair up costs the same as a switch
p:setStorageValue(S.tokens, 1)
done = T.choose(p, 3, 0)
ok(done and T.picks(p, 8)[3] == 0, "giving a pair up")
eq(p:getStorageValue(S.tokens), 0, "...costs a token")
-- state for the client
local st = T.state(p)
ok(st.supported and st.tier == 3 and #st.pairs == 3, "client state")
-- during a run nothing changes
T.runs[77] = {over = false}
done, text = T.choose(p, 1, 1)
ok(not done and text:find("during a trial"), "no changes during a trial")
T.runs[77] = nil

print(string.format("trials_flow_test: %d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
