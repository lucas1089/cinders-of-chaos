-- Run from the server/ folder: luajit tests/welcomepath_test.lua (CI runs luajit and lua5.3)
-- The welcome path (O370): the rules (welcomepath_core.lua), the config (welcomepath_config.lua) and the engine file
-- (welcomepath.lua) on a mocked engine: start, steps, rewards, skip, quiet characters, the goals.lua hooks.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m) checks = checks + 1; if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function check(c, m) checks = checks + 1; if not c then error(m, 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/welcomepath_core.lua")
local K = ChaosWelcomePathCore
local cfg = K.cfg()
check(cfg, "the config loads")
eq(#K.validate(cfg), 0, "the shipped config validates: " .. table.concat(K.validate(cfg), "; "))
eq(cfg.storage.base, Chaos.storage.welcomePath, "the storage base is Chaos.storage.welcomePath")
eq(cfg.storage.base + 9, cfg.storage.last, "a block of 10")

-- the steps the owner asked for, in order
local order = {}
for i, s in ipairs(cfg.steps) do order[i] = s.key end
eq(table.concat(order, ","), "spell,kills,gear,passive,bounty,orb,goals", "the steps")
for _, s in ipairs(cfg.steps) do
	check(s.title.en ~= s.title.pt and s.hint.en ~= s.hint.pt, "both languages: " .. s.key)
	check(s.reward and ((s.reward.gold or 0) > 0), "a gold reward: " .. s.key)
	check((s.reward.gold or 0) <= 1500, "a modest reward: " .. s.key)
	check(type(s.where) == "table", "a click on the row does something: " .. s.key)
end

-- validate catches mistakes
local bad = {storage = {base = 7101000, state = 0, step = 1, kills = 2, flags = 3}, steps = {
	{key = "a", check = "nope", title = {en = "x"}, hint = {en = "y", pt = "z"}},
	{key = "a", check = "stat", title = {en = "x", pt = "y"}, hint = {en = "y", pt = "z"}, reward = {}},
	{key = "k", check = "kills", title = {en = "x", pt = "y"}, hint = {en = "y", pt = "z"}, reward = {}}}}
local probs = table.concat(K.validate(bad), "|")
check(probs:find("storage state outside", 1, true), "storage block")
check(probs:find("unknown check nope", 1, true), "unknown check")
check(probs:find("key twice", 1, true), "a key twice")
check(probs:find("names no stat", 1, true), "a stat check without a stat")
check(probs:find("needs a target", 1, true), "a kills step without a target")
check(probs:find("title needs en and pt", 1, true), "a title without pt")
check(probs:find("no reward", 1, true), "no reward")
check(#K.validate({storage = cfg.storage, steps = {}}) > 0, "no steps")

-- progress of each kind
local S = {}
for _, s in ipairs(cfg.steps) do S[s.key] = s end
local p, t, running = K.progress(S.spell, {level = 8})
eq(p, 0); eq(t, 1); eq(running, true, "a spell step runs")
eq(K.isDone(S.spell, {level = 8, spell = true}), true, "a cast")
eq(select(1, K.progress(S.kills, {level = 8, kills = 7})), 7, "kills count")
eq(select(2, K.progress(S.kills, {level = 8, kills = 7})), 20, "kills target")
eq(select(1, K.progress(S.kills, {level = 8, kills = 99})), 20, "kills capped at the target")
eq(K.isDone(S.kills, {level = 8, kills = 20}), true, "20 kills")
eq(K.isDone(S.gear, {level = 8, gear = false}), false, "the kit only")
eq(K.isDone(S.gear, {level = 8, gear = true}), true, "new gear")
eq(K.isDone(S.orb, {level = 20, stats = {orbs_used = 1}}), true, "an orb used")
eq(K.isDone(S.orb, {level = 20, stats = {}}), false, "no orb yet")
eq(K.isDone(S.orb, {level = 19, stats = {orbs_used = 1}}), false, "the Crafting Bench opens at 20")
eq(S.orb.level, 20, "the orb step waits for the bench's level")
p, t, running = K.progress(S.passive, {level = 10, stats = {passive_spent = 1}})
eq(p, 10, "below level 12: the level as progress"); eq(t, 12); eq(running, false)
eq(K.isDone(S.passive, {level = 10, stats = {passive_spent = 1}}), false, "not done below its level")
eq(K.isDone(S.passive, {level = 12, stats = {passive_spent = 1}}), true, "a point spent at 12")
eq(K.isDone(S.bounty, {level = 9, stats = {bounty_done = 2}}), true, "a contract")
eq(K.isDone(S.goals, {level = 9, flags = 0}), false, "Next Goals not opened")
eq(K.isDone(S.goals, {level = 9, flags = K.FLAG_GOALS}), true, "Next Goals opened")
eq(K.isDone(S.goals, {level = 9, flags = -1}), false, "an unset flags storage")
eq(K.setBit(-1, 1), 1); eq(K.setBit(1, 1), 1, "a bit once"); eq(K.hasBit(3, 2), true)

-- the gear rule
local kit = K.kitSet({equip = {{slot = "left", id = 2190, minLevel = 7, fallback = 23719}, {slot = "head", id = 2461}},
	backpack = {{id = 2120}}})
check(kit[2190] and kit[23719] and kit[2461] and kit[2120], "the kit's ids, fallbacks and backpack rows")
eq(K.gearNew({2190, 2461}, kit), false, "wearing the kit")
eq(K.gearNew({2190, 2461, 2124}, kit), true, "a ring that is not of the kit")
eq(K.gearNew({}, kit), false, "nothing worn")
eq(K.gearNew({2400}, K.kitSet(nil)), true, "no kit (vocation 0): anything worn counts")

-- first sight
eq(K.firstState(cfg, 8), cfg.states.active, "a new character starts")
eq(K.firstState(cfg, cfg.quietAbove), cfg.states.active, "at quietAbove: starts")
eq(K.firstState(cfg, cfg.quietAbove + 1), cfg.states.quiet, "above: quiet")
local function factsAll(f) return function() return f end end
eq(K.skipDone(cfg, 1, factsAll({level = 8, spell = true}), false), 1, "a brand-new character never skips the cast")
eq(K.skipDone(cfg, 1, factsAll({level = 14, gear = true, stats = {orbs_used = 3, passive_spent = 1}}), true), 5,
	"one that played: cast, kills, gear and passive pass; the bounty stops it")
eq(K.skipDone(cfg, 1, factsAll({level = 14, gear = false}), true), 3, "played, no new gear: stops at the gear step")
eq(K.skipDone(cfg, 1, factsAll({level = 15, gear = true, flags = 1, stats = {orbs_used = 1, passive_spent = 1, bounty_done = 1}}),
	true), 6, "level 15: the orb step waits for level 20")
eq(K.skipDone(cfg, 1, factsAll({level = 20, gear = true, flags = 1, stats = {orbs_used = 1, passive_spent = 1, bounty_done = 1}}),
	true), #cfg.steps + 1, "everything done: past the end")

-- rewards
local rw = K.rewardOf(cfg, S.kills, "caster")
eq(rw.gold, 500); eq(#rw.items, 1, "the caster's potions"); eq(rw.items[1][1], 7620); eq(rw.items[1].potion, true)
rw = K.rewardOf(cfg, S.kills, "nonsense")
eq(#rw.items, 2, "an unknown role: the default potions")
rw = K.rewardOf(cfg, S.bounty, "melee")
eq(rw.items[1][1], 29851, "Orbs of Awakening for the orb step"); eq(rw.items[1][2], 2)
eq(K.rewardText(cfg, K.rewardOf(cfg, S.bounty, "melee"), "en", function() return "Orb of Awakening" end),
	"1,000 gold to your bank, 2 Orb of Awakening", "reward line")
eq(K.rewardText(cfg, K.rewardOf(cfg, S.gear, "melee"), "en", nil), "500 gold to your bank", "gold only")
eq(K.rewardText(cfg, K.rewardOf(cfg, S.goals, "melee"), "pt", nil), "1,000 de ouro no seu banco, poções", "reward line pt")
eq(K.int(4600), "4,600"); eq(K.int(100), "100"); eq(K.int(1234567), "1,234,567")
local total = 0
for _, s in ipairs(cfg.steps) do total = total + s.reward.gold end
check(total <= 5000, "the whole path pays at most 5,000 gold: " .. total)

-- the view
local v = K.view(cfg, cfg.states.active, 2, {level = 8, kills = 3}, "en")
eq(v.step, 2); eq(v.count, #cfg.steps); eq(v.title, "Welcome Path")
eq(#v.rows, 1); eq(v.rows[1].key, "kills"); eq(v.rows[1].progress, 3); eq(v.rows[1].target, 20); eq(v.rows[1].state, "open")
eq(v.rows[1].where.k, "hunts", "the row's click")
v = K.view(cfg, cfg.states.active, 4, {level = 9}, "pt")
eq(v.rows[1].title, "Gaste seu primeiro ponto passivo (nível 12)", "below the step's level: named with it")
eq(v.rows[1].progress, 9)
eq(#K.view(cfg, cfg.states.skipped, 2, {}, "en").rows, 0, "skipped: hidden")
eq(#K.view(cfg, cfg.states.active, #cfg.steps + 1, {}, "en").rows, 0, "past the end: hidden")
eq(K.sig({rows = {}}, "en"), "hidden")
check(K.sig(K.view(cfg, 0, 2, {level = 8, kills = 3}, "en"), "en") ~= K.sig(K.view(cfg, 0, 2, {level = 8, kills = 4}, "en"), "en"),
	"progress in the signature")

-- ---------------------------------------------------------------- the engine file on a mocked engine
local events, globals, sent, timers = {}, {}, {}, {}
function CreatureEvent(name)
	local o = {}
	function o:type(t) self.t = t end
	function o:register() events[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:interval(ms) self.ms = ms end
	function o:register() globals[name] = o end
	return o
end
function addEvent(fn, ms, ...) timers[#timers + 1] = {fn = fn, ms = ms, args = {...}} end
local function runTimers()
	local list = timers
	timers = {}
	local unpackArgs = unpack or table.unpack
	for _, t in ipairs(list) do t.fn(unpackArgs(t.args)) end
end
Chaos.send = function(pl, op, action, data) sent[#sent + 1] = {op = op, action = action, data = data, pid = pl:getId()} end
Chaos.lang = function() return "en" end
Chaos.giveItem = function(pl, id, count) pl.items[id] = (pl.items[id] or 0) + count; return count end
json = {encode = function() return "{}" end}
ItemType = function(id) return {getName = function() return id == 29851 and "Orb of Awakening" or "Item" end} end
CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, SPELLGROUP_ATTACK = 77, 0, 1

ChaosNewPlayer = {kitFor = function() return {equip = {{slot = "left", id = 8602}, {slot = "head", id = 2460}}, role = "melee"} end}
ChaosAchievements = {stats = {}}
local byId = {}
local function newPlayer(id, level, group)
	local pl = {id = id, level = level, store = {}, msgs = {}, slots = {}, items = {}, bank = 0, cooldown = false,
		group = group or 1, ext = {}}
	function pl:getId() return self.id end
	function pl:getGuid() return self.id + 100 end
	function pl:getLevel() return self.level end
	function pl:isPlayer() return true end
	function pl:getGroup() local g = self.group; return {getId = function() return g end} end
	function pl:getVocation() return {getId = function() return 1 end} end
	function pl:getStorageValue(k) return self.store[k] or -1 end
	function pl:setStorageValue(k, v) self.store[k] = v end
	function pl:registerEvent() end
	function pl:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function pl:sendExtendedOpcode(op, buf) self.ext[#self.ext + 1] = op end
	function pl:getCondition(ctype, cid, group) return self.cooldown and ctype == CONDITION_SPELLGROUPCOOLDOWN and group == 1 end
	function pl:getSlotItem(slot) local id = self.slots[slot]; return id and {getId = function() return id end} or nil end
	function pl:getBankBalance() return self.bank end
	function pl:setBankBalance(v) self.bank = v end
	byId[id] = pl
	return pl
end
Player = function(id) return byId[id] end
local players = {}
Game = {getPlayers = function() return players end}
local function said(pl, needle)
	for _, m in ipairs(pl.msgs) do
		if m:find(needle, 1, true) then return true end
	end
	return false
end
local function lastSent(pl)
	for i = #sent, 1, -1 do
		if sent[i].pid == pl:getId() then return sent[i] end
	end
end

dofile("data/scripts/chaos/welcomepath.lua")
local W = ChaosWelcomePath
local sweep = globals.ChaosWelcomePathThink
check(events.ChaosWelcomePathLogin and events.ChaosWelcomePathKill and events.ChaosWelcomePathLogout and sweep, "events")
eq(events.ChaosWelcomePathKill.t, "kill", "a kill event")
eq(sweep.ms, cfg.sweepMs, "the sweep interval")
check(events.ChaosWelcomePathExtended == nil, "no second handler on opcode 178 (goals.lua is the one)")
local key = function(name) return cfg.storage.base + cfg.storage[name] end
local monster = {isMonster = function() return true end, getMaster = function() return nil end}
local summon = {isMonster = function() return true end, getMaster = function() return {} end}

-- a brand-new character at level 8, wearing its kit
local p = newPlayer(1, 8)
p.slots = {[1] = 2460, [6] = 8602}
p.store[Chaos.storage.newPlayer] = os.time() -- its kit, just now
players = {p}
events.ChaosWelcomePathLogin.onLogin(p)
eq(#timers, 1, "the first look waits"); eq(timers[1].ms, cfg.firstLookMs)
p.cooldown = true -- a cast in the first seconds is not passed silently
runTimers()
eq(p.store[key("state")], cfg.states.active, "on the path")
eq(p.store[key("step")], 1, "step 1")
check(said(p, "welcome path starts"), "told it starts")
check(said(p, "Next step: Cast a spell"), "told the first step")
local s1 = lastSent(p)
eq(s1.op, 178, "the goals channel"); eq(s1.action, "welcome"); eq(s1.data.rows[1].key, "spell")
-- the sweep sees the cast: step 2, 300 gold
sweep.onThink(1000)
eq(p.store[key("step")], 2, "the cast is step 1")
eq(p.bank, 300, "300 gold to the bank")
check(said(p, "Welcome path 1/7 done: Cast a spell. Reward: 300 gold to your bank."), "the done line")
check(said(p, "Next step: Slay 20 monsters"), "the next step")
eq(lastSent(p).data.rows[1].key, "kills", "the tracker follows")
-- kills: a summon does not count; 20 monsters do
p.cooldown = false
events.ChaosWelcomePathKill.onKill(p, summon)
eq(p.store[key("kills")] or 0, 0, "a summon is no kill")
for _ = 1, 19 do events.ChaosWelcomePathKill.onKill(p, monster) end
local before = #sent
sweep.onThink(1000)
eq(p.store[key("step")], 2, "19 kills: not yet")
eq(#sent, before + 1, "the count changed: sent")
eq(lastSent(p).data.rows[1].progress, 19)
sweep.onThink(1000)
eq(#sent, before + 1, "nothing changed: not sent again")
events.ChaosWelcomePathKill.onKill(p, monster)
sweep.onThink(1000)
eq(p.store[key("step")], 3, "20 kills")
eq(p.store[key("kills")], 0, "the counter starts over")
eq(p.items[7618], 25, "the melee potions")
-- gear: the kit does not count, a new ring does
sweep.onThink(1000)
eq(p.store[key("step")], 3, "still the kit")
p.slots[9] = 2124
sweep.onThink(1000)
eq(p.store[key("step")], 4, "a ring not of the kit")
-- passive: level 12 first
ChaosPassiveTree = {hasAllocation = function() return true end}
sweep.onThink(1000)
eq(p.store[key("step")], 4, "level 8: the passive step waits for level 12")
check(lastSent(p).data.rows[1].title:find("(level 12)", 1, true), "the row names the level")
p.level = 12
sweep.onThink(1000)
eq(p.store[key("step")], 5, "the point spent at level 12")
-- bounty: a Next Goals own stat or an achievement counter
ChaosGoals = {st = {[p:getGuid()] = {stats = {bounty_done = 1}}}}
sweep.onThink(1000)
eq(p.store[key("step")], 6, "a contract")
eq(p.items[29851], 2, "two Orbs of Awakening for the orb step")
check(said(p, "2 Orb of Awakening"), "named in the reward")
-- orb: the achievement counter, from level 20
ChaosAchievements.stats[p:getGuid()] = {orbs_used = 1}
sweep.onThink(1000)
eq(p.store[key("step")], 6, "level 12: the bench is not open yet")
p.level = 20
sweep.onThink(1000)
eq(p.store[key("step")], 7, "an orb used at level 20")
eq(p.items[29856], 2, "two Orbs of Upheaval")
-- the last step: goals.lua "open" marks it
local gsrc = io.open("data/scripts/chaos/goals.lua"):read("*a")
check(gsrc:find('ChaosWelcomePath.mark, player, "goals"', 1, true), "goals.lua marks the window opened")
check(gsrc:find("ChaosWelcomePath.forget", 1, true), "goals.lua resends on tracker")
check(gsrc:find('msg.action == "welcomeSkip"', 1, true) and gsrc:find("ChaosWelcomePath.skip", 1, true), "goals.lua skips")
W.mark(p, "goals")
local bank = p.bank
sweep.onThink(1000)
eq(p.store[key("state")], cfg.states.done, "the path is done")
eq(p.bank, bank + 1000, "the last reward")
check(said(p, "Welcome path complete!"), "told")
eq(#lastSent(p).data.rows, 0, "the section hides")
local after = #sent
sweep.onThink(1000)
eq(#sent, after, "done: quiet")
local total = 0
for _, st in ipairs(cfg.steps) do total = total + st.reward.gold end
eq(p.bank, total, "every gold reward once")
-- a relog after the end: nothing again
p.msgs = {}
events.ChaosWelcomePathLogin.onLogin(p)
runTimers()
eq(#p.msgs, 0, "no message after the end")

-- skip
local q = newPlayer(2, 8)
q.store[Chaos.storage.newPlayer] = os.time()
players = {q}
events.ChaosWelcomePathLogin.onLogin(q)
runTimers()
eq(q.store[key("state")], cfg.states.active)
eq(W.skip(q), true, "skipped")
eq(q.store[key("state")], cfg.states.skipped)
check(said(q, "Welcome path skipped"), "told")
eq(#lastSent(q).data.rows, 0, "the section hides")
eq(W.skip(q), false, "a second skip does nothing")
q.cooldown = true
sweep.onThink(1000)
eq(q.bank, 0, "a skipped path pays nothing")

-- a character that played before this module, above quietAbove: never
local old = newPlayer(3, 300)
players = {old}
local nsent = #sent
events.ChaosWelcomePathLogin.onLogin(old)
runTimers()
eq(old.store[key("state")], cfg.states.quiet, "quiet")
eq(#old.msgs, 0, "no message")
eq(#sent, nsent, "nothing sent")
sweep.onThink(1000)
eq(#sent, nsent, "still nothing")

-- an existing level 14 character below quietAbove that did most of it: those steps pass silently
local mid = newPlayer(4, 14)
mid.slots = {[6] = 8602, [9] = 2124}
ChaosAchievements.stats[mid:getGuid()] = {orbs_used = 5}
ChaosPassiveTree = {hasAllocation = function() return true end}
ChaosGoals = nil
players = {mid}
events.ChaosWelcomePathLogin.onLogin(mid)
runTimers()
eq(mid.store[key("step")], 5, "starts at the bounty step")
eq(mid.bank, 0, "no reward for what it had done")
check(said(mid, "Next step: Finish a Bounty contract"), "told its first open step")

-- staff walk no path
local gm = newPlayer(5, 8, 6)
players = {gm}
events.ChaosWelcomePathLogin.onLogin(gm)
runTimers()
eq(gm.store[key("state")], nil, "staff: untouched")

-- the tracker request resends
W.sent[mid:getId()] = "x"
W.forget(mid)
eq(W.sent[mid:getId()], nil, "forget")
players = {mid, gm}
nsent = #sent
sweep.onThink(1000)
eq(#sent, nsent + 1, "the rows go out again")
eq(lastSent(mid).data.rows[1].where.k, "window", "the bounty row opens the board")
events.ChaosWelcomePathLogout.onLogout(mid)
eq(W.sent[mid:getId()], nil, "logout clears")

print(string.format("welcomepath_test: %d checks ok", checks))
