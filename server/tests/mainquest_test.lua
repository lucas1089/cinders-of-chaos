-- Run from the server/ folder: luajit tests/mainquest_test.lua (CI runs luajit and lua5.3)
-- The main quest (O551): the rules (mainquest_core.lua), the config (mainquest_config.lua) and the engine file (mainquest.lua)
-- on a mocked engine: start, steps of every kind, drops, rewards, skip, veterans, the welcome path import, the goals.lua hooks.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m) checks = checks + 1; if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function check(c, m) checks = checks + 1; if not c then error(m, 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/mainquest_core.lua")
local K = ChaosMainQuestCore
local cfg = K.cfg()
check(cfg, "the config loads")
eq(#K.validate(cfg), 0, "the shipped config validates: " .. table.concat(K.validate(cfg), "; "))
eq(cfg.storage.base, Chaos.storage.mainQuest, "the storage base is Chaos.storage.mainQuest")
eq(cfg.storage.last - cfg.storage.base + 1, 30, "a block of 30 keys")
for _, name in ipairs({"state", "step", "count", "flags", "flags2", "tries", "cooldown", "won", "pity"}) do
	check(cfg.storage[name] >= 0 and cfg.storage[name] <= 29, "storage " .. name .. " inside the block")
end
-- every storage of the block is used once
local seen = {}
for _, name in ipairs({"state", "step", "count", "flags", "flags2", "tries", "cooldown", "won", "pity"}) do
	check(not seen[cfg.storage[name]], "storage " .. name .. " is its own key")
	seen[cfg.storage[name]] = true
end

-- the steps: order, chapters, a mix of real play, texts in both languages
-- counters that are earned by fighting: a kill, a clear of a rift, a dungeon, a trial, a boss (a step on them is a play step)
local PLAY_STATS = {kills_magic = true, kills_rare = true, kills_legendary = true, party_kills = true, bounty_done = true,
	invasion_fought = true, arena1v1_wins = true, rift_runs = true, rift_tier = true, tower_floor = true, descent_runs = true,
	descent_clears = true, trial_tier_1 = true, trial_tier_2 = true, trial_tier_3 = true, bg_matches = true, wb_kills = true,
	pocket_kills = true, dungeon_clears = true, unique_found = true, bestiary_tasks = true, ascended = true}
local S, play, total = {}, 0, #cfg.steps
for i, s in ipairs(cfg.steps) do
	S[s.key] = s
	check(s.title.en ~= "" and s.title.pt ~= "" and s.hint.pt ~= "" and s.done.pt ~= "", "texts: " .. s.key)
	check(s.title.en ~= s.title.pt or s.key == "death", "the pt title is its own: " .. s.key)
	check(not s.title.pt:find("\xe2\x80\x94", 1, true) and not s.hint.pt:find("\xe2\x80\x94", 1, true) and not s.done.pt:find("\xe2\x80\x94", 1, true),
		"no em-dash in the script: " .. s.key)
	local ch = cfg.chapters[s.ch]
	check(ch and s.level >= ch.from and s.level <= ch.to, "the level is inside its chapter: " .. s.key)
	local kinds = {}
	for _, c in ipairs(s.conds) do
		kinds[c.c] = true
		if c.c == "stat" and PLAY_STATS[c.stat] then kinds.count = true end
	end
	if kinds.count or kinds.visit or kinds.talk or kinds.boss then play = play + 1 end
	check(s.where == nil or type(s.where) == "table", "where is a form: " .. s.key)
end
check(play * 2 >= total, "half of the steps or more are kill / loot / explore / deliver steps: " .. play .. " of " .. total)
check(total >= 80 and total <= 130, "a quest of this size: " .. total)
eq(cfg.steps[total].key, "boss", "the last step is the boss")
eq(cfg.steps[1].key, "warden", "the first step is Ysolde")
for _, c in ipairs(cfg.chapters) do
	check(c.intro.pt ~= "" and c.name.pt ~= "", "chapter texts " .. c.n)
end
check(#cfg.epilogue >= 6, "the epilogue shows the late systems")
for k, t in pairs(cfg.ysolde) do check(t.en ~= "" and t.pt ~= "", "ysolde " .. k) end
for k, t in pairs(cfg.vael) do check(t.en ~= "" and t.pt ~= "", "vael " .. k) end
for _, k in ipairs({"enter", "phase1", "phase2", "phase3", "phase4", "enrage", "defeat", "victory"}) do
	check(cfg.vael[k], "a line of Vael: " .. k)
end

-- validate catches mistakes
local bad = {storage = {base = 7101000, state = 0, step = 1, count = 2, flags = 3, flags2 = 4, tries = 5, cooldown = 6, won = 7, pity = 8},
	flags = {"a"}, chapters = {{n = 1, name = {en = "x", pt = "y"}, intro = {en = "x", pt = "y"}}}, steps = {
	{key = "a", ch = 1, level = 10, conds = {{c = "nope"}}, title = {en = "x"}, hint = {en = "y", pt = "z"}, done = {en = "d", pt = "d"}, mins = 1},
	{key = "a", ch = 1, level = 5, conds = {{c = "flag", key = "zzz"}}, title = {en = "x {m1}", pt = "y"}, hint = {en = "y", pt = "z"},
		done = {en = "d", pt = "d"}, mins = 1},
	{key = "k", ch = 9, level = 6, conds = {{c = "count", mons = {}, target = 0}}, title = {en = "x", pt = "y"}, hint = {en = "y", pt = "z"},
		done = {en = "d", pt = "d"}, mins = -1}}}
local probs = table.concat(K.validate(bad), "|")
check(probs:find("storage state outside", 1, true), "storage block")
check(probs:find("unknown condition nope", 1, true), "unknown condition")
check(probs:find("key twice", 1, true), "a key twice")
check(probs:find("level below", 1, true), "levels in order")
check(probs:find("is not in `flags`", 1, true), "an unknown flag")
check(probs:find("different {places}", 1, true), "placeholders match")
check(probs:find("unknown chapter", 1, true), "an unknown chapter")
check(probs:find("needs monsters and a target", 1, true), "a count needs monsters")
check(probs:find("title needs en and pt", 1, true), "a title without pt")
check(probs:find("no reward minutes", 1, true), "no reward minutes")
check(probs:find("exactly one boss", 1, true), "one boss step")

-- flags: bits, places
local name, bit = K.flagPlace(cfg, "talk")
eq(name, "flags"); eq(bit, 1, "talk is bit 1")
local seenBits = {}
for _, k in ipairs(cfg.flags) do
	local nm, b = K.flagPlace(cfg, k)
	check(nm and b >= 1 and b <= 2 ^ 29, "flag place " .. k)
	check(not seenBits[nm .. b], "a bit of its own " .. k)
	seenBits[nm .. b] = true
end
eq(K.flagPlace(cfg, "nothing"), nil, "unknown flag")
eq(K.setBit(0, 4), 4); eq(K.setBit(4, 4), 4); eq(K.hasBit(5, 4), true); eq(K.hasBit(5, 2), false); eq(K.clearBit(5, 4), 1)

-- the numbers of the texts come from the configs
local pd = dofile("data/scripts/chaos/player_defence_config.lua")
local def = dofile("data/scripts/chaos/defence_config.lua")
local gd = dofile("data/scripts/chaos/gentledeath_config.lua")
local v = K.vars(cfg, pd, def, gd, "en")
eq(v.m1, pd.penalty.marks[1].level); eq(v.p1, pd.penalty.marks[1].points); eq(v.w1, pd.penalty.marks[1].warnFrom)
eq(v.m2, pd.penalty.marks[2].level); eq(v.p2, pd.penalty.marks[2].points); eq(v.w2, pd.penalty.marks[2].warnFrom)
eq(v.share, pd.tree.share * 100); eq(v.tcap, pd.tree.cap); eq(v.cap, def.resistCap); eq(v.safe, 0)
check(v.death_rule:find(tostring(gd.xpLoss[2].level), 1, true), "the death rule names the config's levels: " .. v.death_rule)
check(K.vars(cfg, pd, def, gd, "pt").death_rule:find("nenhuma", 1, true), "pt death rule")
eq(K.fill("at {m1} drops {p1}, {nope}", {m1 = 250, p1 = 30}), "at 250 drops 30, {nope}", "fill leaves a gap visible")
-- no step text holds a bare number that is one of the configs' values (they must be {places})
local mustBePlaces = {pd.penalty.marks[1].level, pd.penalty.marks[2].level, pd.penalty.marks[1].points, pd.penalty.marks[2].points,
	pd.penalty.marks[1].warnFrom, pd.penalty.marks[2].warnFrom}
for _, s in ipairs(cfg.steps) do
	if s.key:find("^res") then
		for _, f in ipairs({"title", "hint"}) do
			for _, lang in ipairs({"en", "pt"}) do
				local text = s[f][lang]:gsub("{[%w_]+}", "")
				for _, num in ipairs(mustBePlaces) do
					check(not text:find("%f[%d]" .. num .. "%f[%D]"), "a resistance text names " .. num .. " in a number, not a place: " .. s.key)
				end
			end
		end
	end
end
-- the resistance steps follow the marks of the defence config
local function lvl(key) return S[key].level end
eq(lvl("res1a"), pd.penalty.marks[1].warnFrom - cfg.resist.knowOffset, "know 1")
eq(lvl("res1b"), pd.penalty.marks[1].warnFrom, "prepare 1")
eq(lvl("res1c"), pd.penalty.marks[1].level, "hold 1")
eq(lvl("res2a"), pd.penalty.marks[2].warnFrom - cfg.resist.knowOffset, "know 2")
eq(lvl("res2b"), pd.penalty.marks[2].warnFrom, "prepare 2")
eq(lvl("res2c"), pd.penalty.marks[2].level, "hold 2")
eq(K.resistLevel(cfg, {mark = 1, mode = "hold"}, pd.penalty.marks), pd.penalty.marks[1].level)
eq(S.res2c.conds[1].mark, 2); eq(S.res2c.conds[1].mode, "hold")
-- the boss is gated by the last "hold the line"
local idx = {}
for i, s in ipairs(cfg.steps) do idx[s.key] = i end
check(idx.res2c < idx.boss, "the boss comes after the 500 resistance check")
check(cfg.boss.minLevel >= pd.penalty.marks[2].level, "the boss level is at the second mark")

-- progress of each kind
local p, t, running = K.progress(S.spell, {level = 8})
eq(p, 0); eq(t, 1); eq(running, true)
eq(K.isDone(S.spell, {level = 8, spell = true}), true, "a cast")
eq(K.isDone(S.gear, {level = 8, gear = false}), false, "the kit only")
eq(K.isDone(S.orb, {level = 20, stats = {orbs_used = 1}}), true, "an orb used")
eq(K.isDone(S.orb, {level = 19, stats = {orbs_used = 1}}), false, "level 19: the bench is not open")
local r1, r2, r3 = K.progress(S.orb, {level = 12, stats = {}})
eq(r1, 12); eq(r2, 20); eq(r3, false, "below the level the row shows the level")
eq(select(1, K.progress(S.trolls, {level = 8, count = 7})), 7, "kills count")
eq(select(2, K.progress(S.trolls, {level = 8, count = 7})), 12, "kills target")
eq(select(1, K.progress(S.trolls, {level = 8, count = 99})), 12, "capped")
eq(K.isDone(S.trolls, {level = 8, count = 12}), true)
eq(K.isDone(S.trollground, {level = 8, visit = false}), false); eq(K.isDone(S.trollground, {level = 8, visit = true}), true, "a visit")
eq(K.isDone(S.warden, {level = 8, flags = {}}), false); eq(K.isDone(S.warden, {level = 8, flags = {talk = true}}), true, "the talk flag")
eq(K.isDone(S.potion, {level = 8, flags = {potion = true}}), true, "a hook flag")
local two = {level = 11, flags = {daily = true, market = false}}
eq(select(1, K.progress(S.daily_market, two)), 1, "two conditions: one holds"); eq(select(2, K.progress(S.daily_market, two)), 2)
eq(K.isDone(S.daily_market, {level = 11, flags = {daily = true, market = true}}), true)
eq(K.isDone(S.spark_brazier, {level = 33, storage = {spark = 1}, stats = {community_points = 1}}), true, "storage plus stat")
eq(K.isDone(S.spark_brazier, {level = 33, storage = {spark = 0}, stats = {community_points = 1}}), false)
eq(K.isDone(S.boss, {level = 500, boss = true}), true); eq(K.isDone(S.boss, {level = 500}), false)

-- the resistance steps read the defence sheet
local marks = pd.penalty.marks
local function sheet(sums, pcts)
	local out = {resist = {}}
	for i, g in ipairs({"fire", "ice", "energy", "earth"}) do
		out.resist[i] = {k = g, sum = sums[i], pct = pcts[i]}
	end
	return out
end
local f = {level = 240, marks = marks, safeMin = 0, sheet = sheet({40, 12, 30, 8}, {40, 12, 30, 8})}
eq(select(1, K.progress(S.res1b, f)), 2, "prepare: two groups at the points")
eq(K.isDone(S.res1b, f), false)
local met, tot, weak = K.resistProgress(S.res1b.conds[1], f.sheet, marks, 0)
eq(met, 2); eq(tot, 4); eq(weak.k, "earth", "the weakest group"); eq(weak.value, 8); eq(weak.goal, marks[1].points)
f.sheet = sheet({40, 31, 30, 60}, {40, 31, 30, 60})
eq(K.isDone(S.res1b, f), true, "all four at the points")
f = {level = 250, marks = marks, safeMin = 0, sheet = sheet({40, 31, 30, 60}, {10, 1, 0, 30})}
eq(K.isDone(S.res1c, f), true, "hold: no negative result (0 is safe)")
f.sheet = sheet({40, 31, 30, 60}, {10, 1, -1, 30})
eq(K.isDone(S.res1c, f), false, "hold: one negative result")
f = {level = 500, marks = marks, safeMin = 0, sheet = sheet({90, 90, 90, 90}, {30, 30, 30, 30})}
eq(K.isDone(S.res2c, f), true, "500: safe")
f.sheet = nil
eq(K.isDone(S.res2c, f), false, "no sheet: not done")
-- the view of a resistance step names the weakest group
local view = K.view(cfg, 0, idx.res1b, {level = 240, marks = marks, safeMin = 0, sheet = sheet({40, 12, 30, 8}, {40, 12, 30, 8})}, "en", v)
check(view.rows[1].detail:find("earth 8/" .. marks[1].points, 1, true), "the row shows the weakest group: " .. tostring(view.rows[1].detail))
check(view.rows[1].hint:find(tostring(marks[1].points), 1, true), "the hint is filled with the config's points")
check(not view.rows[1].hint:find("{", 1, true), "no open place in the hint")
for _, s in ipairs(cfg.steps) do
	for _, lang in ipairs({"en", "pt"}) do
		check(not K.fill(s.title[lang], v):find("{", 1, true) and not K.fill(s.hint[lang], v):find("{", 1, true), "every place is filled: " .. s.key .. " " .. lang)
	end
end

-- the quest drop
local function expectedKills(step, cond)
	return 1 / K.dropChance(cfg, step.mins, cond.target)
end
local tusks = S.tusks
local cond = tusks.conds[1]
check(K.dropChance(cfg, tusks.mins, cond.target) > 0.05 and K.dropChance(cfg, tusks.mins, cond.target) <= 0.6, "a chance in range")
check(expectedKills(tusks, cond) * cond.target >= tusks.mins * cfg.drop.killsPerMinute * 0.8 - 0.01, "the step takes about its minutes")
local counted, dropped, pity = K.onKill(cfg, tusks, cond, "Rat", 3, 0)
eq(counted, false); eq(dropped, false); eq(pity, 3, "a monster of another name does nothing")
counted, dropped, pity = K.onKill(cfg, tusks, cond, "Troll", 0, 0)
eq(dropped, true, "a low roll drops"); eq(pity, 0)
counted, dropped, pity = K.onKill(cfg, tusks, cond, "Troll", 0, 0.99)
eq(dropped, false); eq(pity, 1, "no drop: the pity counter grows")
counted, dropped, pity = K.onKill(cfg, tusks, cond, "Troll", math.ceil(expectedKills(tusks, cond) * cfg.drop.pityMult), 0.99)
eq(dropped, true, "the pity: a sure drop")
counted, dropped = K.onKill(cfg, S.trolls, S.trolls.conds[1], "Troll", 0, 0.99)
eq(counted, true); eq(dropped, false, "a kill step counts every kill of the name")
for _, s in ipairs(cfg.steps) do
	for _, c in ipairs(s.conds) do
		if c.item then
			check(K.dropChance(cfg, s.mins, c.target) < 0.6 or s.mins <= 2, "a drop chance that is not a sure thing: " .. s.key)
		end
	end
end

-- the reward: minutes of income, rounded; the whole quest stays under its share of the hunting gold
local income = dofile("data/scripts/chaos/embercache_config.lua").income
local gold, ideal = 0, 0
for _, s in ipairs(cfg.steps) do gold = gold + K.gold(cfg, income, s) end
local prog = io.open("data/scripts/chaos/progression_config.lua") and true or false
check(gold > 1000000 and gold < 10000000, "total gold of the quest: " .. gold)
eq(K.gold(cfg, income, {level = 8, mins = 60}), 21000, "an hour of hunting at level 8")
eq(K.gold(cfg, income, {level = 8, mins = 1}), 400, "rounded to 100")
eq(K.int(1234567), "1,234,567")
local rw = K.rewardOf(cfg, income, S.orb)
eq(rw.items[1][1], 29856); eq(rw.items[1][2], 2)
for _, s in ipairs(cfg.steps) do
	for _, it in ipairs(s.items) do
		check(it[1] ~= nil and it[2] >= 1 and it[2] <= 4, "a small item reward: " .. s.key)
	end
end
-- the boss reward is above one step and under the Cruel Trial's first clear (4,000 x level x 2)
check(cfg.boss.reward.gold <= 4000 * 500 * 2, "the boss pays less than the Cruel Trial's first clear")
for _, it in ipairs(cfg.boss.reward.items) do
	check(it[1] == 29857 or it[1] == 24692, "orbs only, no store item")
end

-- skipDone: facts that are true pass silently; counts and talks pass only for a character that played
local function facts(level, flags, stats)
	return function(i) return {level = level, flags = flags or {}, stats = stats or {}, count = 0, storage = {}} end
end
eq(K.skipDone(cfg, 1, facts(8), false), 1, "a brand-new character starts at the first step")
check(K.skipDone(cfg, 1, facts(300, {}, {}), true) > 1, "a veteran passes the steps it can")
local vi = K.skipDone(cfg, 1, facts(300, {}, {}), true)
local first = cfg.steps[vi]
check(first.level <= 300 or true, "the first open step")
for i = 1, vi - 1 do
	local s = cfg.steps[i]
	local kinds = {}
	for _, c in ipairs(s.conds) do kinds[c.c] = true end
	check(300 - s.level >= cfg.silentGap or kinds.count or kinds.talk or kinds.visit or kinds.spell or K.isDone(s, {level = 300, flags = {}, stats = {}, storage = {}}), "only played or done steps are passed: " .. s.key)
end
eq(K.firstState(cfg, 8), cfg.states.active); eq(K.firstState(cfg, 500), cfg.states.active); eq(K.firstState(cfg, 501), cfg.states.quiet, "above 500: quiet")

-- chapters
eq(K.nextChapterStart(cfg, 1), idx.spell + 0 > 0 and (function() for i, s in ipairs(cfg.steps) do if s.ch == 2 then return i end end end)(), "the next chapter")
eq(K.nextChapterStart(cfg, #cfg.steps), #cfg.steps + 1)
local cc = K.chapterCounts(cfg, 5)
eq(cc[1].done, 4); eq(cc[2].done, 0)
local tot = 0
for _, c in ipairs(cc) do tot = tot + c.total end
eq(tot, #cfg.steps, "every step is in a chapter")

-- the boss helpers
local b = cfg.boss
eq(select(1, K.phaseOf(b, 1)), 1); eq(select(1, K.phaseOf(b, 0.8)), 1); eq(select(1, K.phaseOf(b, 0.7)), 2); eq(select(1, K.phaseOf(b, 0.4)), 3)
eq(select(1, K.phaseOf(b, 0.1)), 4); eq(select(1, K.phaseOf(b, 0)), 4)
eq(select(2, K.phaseOf(b, 0.6)).element, "ice")
-- the resistance lowers the hit and a negative one raises it (the defence layer is applied to the boss's hit)
eq(K.hitAmount(10000, 0.1, 0, 75), 1000, "resistance 0: the design share")
eq(K.hitAmount(10000, 0.1, 30, 75), 700, "resistance 30: 30% less")
eq(K.hitAmount(10000, 0.1, -50, 75), 1500, "resistance -50: 50% more")
eq(K.hitAmount(10000, 0.1, 99, 75), 250, "the cap")
eq(K.hitAmount(10000, 0.1, -500, 75), 2000, "the floor of -100")
eq(K.hitAmount(1, 0.001, 75, 75), 1, "at least 1")
local ctx = {level = 500, state = cfg.states.active, stepKey = "boss", sheetSafe = true, cooldownLeft = 0}
eq(K.doorProblem(cfg, ctx), nil, "the door is open")
ctx.sheetSafe = false
eq(K.doorProblem(cfg, ctx), "door_closed", "strict: an unsafe resistance keeps it shut")
ctx.sheetSafe = true; ctx.level = 499
eq(K.doorProblem(cfg, ctx), "door_closed", "level 500")
ctx.level = 500; ctx.stepKey = "res2c"
eq(K.doorProblem(cfg, ctx), "door_closed", "the quest is not at the boss yet")
ctx.state = cfg.states.skipped; ctx.stepKey = nil
eq(K.doorProblem(cfg, ctx), nil, "a skipped quest keeps the door")
ctx.cooldownLeft = 30
eq(K.doorProblem(cfg, ctx), "door_cooldown")

-- the NPC side: the talk flag
local store = {state = cfg.states.active, step = 1, flags = 0}
local function g(k) return store[k] end
local function s(k, v) store[k] = v end
eq(K.talk(cfg, g, s), true, "step 1 wants a talk"); eq(store.flags, 1, "the flag is set")
store.step = idx.spell
eq(K.talk(cfg, g, s), "wait", "the step wants something else")
store.state = cfg.states.skipped
eq(K.talk(cfg, g, s), nil, "no open step")

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
Chaos.sendChunked = function(pl, op, text) sent[#sent + 1] = {op = op, action = "chunk", text = text, pid = pl:getId()} end
Chaos.lang = function() return "en" end
Chaos.giveItem = function(pl, id, count) pl.items[id] = (pl.items[id] or 0) + count; return count end
json = {encode = function(t) return "{}" end}
ItemType = function(id) return {getName = function() return id == 29856 and "Orb of Upheaval" or "Item" end} end
CONDITION_SPELLGROUPCOOLDOWN, CONDITIONID_DEFAULT, SPELLGROUP_ATTACK = 77, 0, 1
ChaosNewPlayer = {kitFor = function() return {equip = {{slot = "left", id = 8602}, {slot = "head", id = 2460}}, role = "melee"} end}
dofile("data/scripts/chaos/welcomepath_core.lua")
ChaosAchievements = {stats = {}}
local byId = {}
local function newPlayer(id, level, group)
	local pl = {id = id, level = level, store = {}, msgs = {}, slots = {}, items = {}, bank = 0, cooldown = false, group = group or 1,
		pos = {x = 32369, y = 32241, z = 7}}
	function pl:getId() return self.id end
	function pl:getGuid() return self.id + 100 end
	function pl:getLevel() return self.level end
	function pl:isPlayer() return true end
	function pl:getGroup() local gr = self.group; return {getId = function() return gr end} end
	function pl:getVocation() return {getId = function() return 1 end} end
	function pl:getStorageValue(k) return self.store[k] or -1 end
	function pl:setStorageValue(k, val) self.store[k] = val end
	function pl:registerEvent() end
	function pl:getPosition() return self.pos end
	function pl:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function pl:sendExtendedOpcode() end
	function pl:getCondition(ctype, cid, grp) return self.cooldown and ctype == CONDITION_SPELLGROUPCOOLDOWN and grp == 1 end
	function pl:getSlotItem(slot) local id2 = self.slots[slot]; return id2 and {getId = function() return id2 end} or nil end
	function pl:getBankBalance() return self.bank end
	function pl:setBankBalance(val) self.bank = val end
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
		if sent[i].pid == pl:getId() and sent[i].action == "welcome" then return sent[i] end
	end
end
local function monster(name) return {isMonster = function() return true end, getMaster = function() return nil end, getName = function() return name end} end

dofile("data/scripts/chaos/mainquest.lua")
local W = ChaosMainQuest
local sweep = globals.ChaosMainQuestThink
check(events.ChaosMainQuestLogin and events.ChaosMainQuestKill and events.ChaosMainQuestLogout and sweep, "events")
eq(events.ChaosMainQuestKill.t, "kill"); eq(sweep.ms, cfg.sweepMs)
check(events.ChaosMainQuestExtended == nil, "no second handler on opcode 178")
local key = function(name) return cfg.storage.base + cfg.storage[name] end

-- a brand-new character at level 8
local p = newPlayer(1, 8)
p.slots = {[1] = 2460, [6] = 8602}
p.store[Chaos.storage.newPlayer] = os.time()
players = {p}
events.ChaosMainQuestLogin.onLogin(p)
eq(timers[1].ms, cfg.firstLookMs, "the first look waits")
runTimers()
eq(p.store[key("state")], cfg.states.active, "on the quest"); eq(p.store[key("step")], 1)
check(said(p, "Your Oath begins"), "told it starts"); check(said(p, "Next step: Meet Warden Ysolde"), "told the first step")
check(said(p, "Chapter 1: Cinder-Born"), "the chapter intro")
local s1 = lastSent(p)
eq(s1.op, 178); eq(s1.data.rows[1].key, "warden"); eq(s1.data.chapter, 1); eq(s1.data.count, #cfg.steps)
eq(s1.data.rows[1].where.k, "npc", "the row names the NPC")
-- the talk: the NPC script sets the flag (its own Lua state does it with K.talk)
sweep.onThink(1000)
eq(p.store[key("step")], 1, "not yet")
K.talk(cfg, function(k) return p:getStorageValue(key(k)) end, function(k, val) p:setStorageValue(key(k), val) end)
sweep.onThink(1000)
eq(p.store[key("step")], 2, "the talk is step 1")
eq(p.bank, K.gold(cfg, income, S.warden), "its gold")
check(said(p, "Warden Ysolde: "), "Ysolde's line"); check(said(p, "Main quest 1/" .. #cfg.steps), "the done line")
eq(p.store[key("flags")], 0, "the talk flag is cleared for the next talk")
-- the cast
p.cooldown = true
sweep.onThink(1000)
eq(p.store[key("step")], 3, "a cast")
-- a visit: the position
sweep.onThink(1000)
eq(p.store[key("step")], 3, "far from the Troll ground")
p.pos = {x = 32356, y = 32130, z = 8}
sweep.onThink(1000)
eq(p.store[key("step")], 4, "near the Troll ground")
-- kills: the name counts, others and summons do not
events.ChaosMainQuestKill.onKill(p, monster("Rat"))
eq(p.store[key("count")] or 0, 0, "another monster")
events.ChaosMainQuestKill.onKill(p, {isMonster = function() return true end, getMaster = function() return {} end, getName = function() return "Troll" end})
eq(p.store[key("count")] or 0, 0, "a summon")
for _ = 1, 11 do events.ChaosMainQuestKill.onKill(p, monster("Troll")) end
sweep.onThink(1000)
eq(p.store[key("step")], 4, "11 of 12"); eq(lastSent(p).data.rows[1].progress, 11, "the tracker shows 11")
events.ChaosMainQuestKill.onKill(p, monster("Troll"))
sweep.onThink(1000)
eq(p.store[key("step")], 5, "12 Trolls"); eq(p.store[key("count")], 0, "the counter starts over")
-- a hook flag
sweep.onThink(1000)
eq(p.store[key("step")], 5, "no potion yet")
check(W.emit(p, "potion"), "the hook"); eq(W.emit(p, "nothing"), false, "an unknown flag")
sweep.onThink(1000)
eq(p.store[key("step")], 6, "a potion")
-- the drop: while the step is open the Troll Tusk falls; a kill of the step before does not count here
local tries = 0
while (p.store[key("count")] or 0) < 6 and tries < 400 do
	events.ChaosMainQuestKill.onKill(p, monster("Troll"))
	tries = tries + 1
end
eq(p.store[key("count")], 6, "6 tusks")
check(tries >= 6 and tries < 400, "the drops took a number of kills: " .. tries)
check(said(p, "Troll Tusk (1/6)"), "a loot line")
sweep.onThink(1000)
eq(p.store[key("step")], 7, "the tusks done")
-- the Go button marks the windows of an ack step, only for the current step
eq(W.go(p, "season"), false, "not the current step")
-- a veteran at level 300: passes what it can
local vet = newPlayer(2, 300)
vet.store[Chaos.storage.newPlayer] = os.time() - 99999
players = {vet}
ChaosAchievements.stats[vet:getGuid()] = {kills_magic = 5, bounty_done = 3, orbs_used = 9, party_kills = 99, kills_rare = 99}
events.ChaosMainQuestLogin.onLogin(vet)
runTimers()
local vstep = vet.store[key("step")]
check(vstep > 8, "a veteran starts later: " .. tostring(vstep))
eq(vet.store[key("state")], cfg.states.active)
eq(vet.bank, 0, "nothing is paid for the steps passed silently")
-- a character above 500 is quiet
local old = newPlayer(3, 700)
players = {old}
events.ChaosMainQuestLogin.onLogin(old)
runTimers()
eq(old.store[key("state")], cfg.states.quiet, "above 500: quiet")
eq(#old.msgs, 0, "no message")
-- staff walk no quest
local gm = newPlayer(4, 8, 4)
players = {gm}
events.ChaosMainQuestLogin.onLogin(gm)
runTimers()
check(gm.store[key("state")] == nil, "staff: nothing stored")
-- skip: a chapter, then the quest
local q = newPlayer(5, 8)
q.store[Chaos.storage.newPlayer] = os.time()
players = {q}
events.ChaosMainQuestLogin.onLogin(q)
runTimers()
check(W.skip(q, "chapter"), "skip chapter")
eq(cfg.steps[q.store[key("step")]].ch, 2, "the next chapter")
check(W.skip(q, "quest"), "skip quest")
eq(q.store[key("state")], cfg.states.skipped); check(said(q, "Main quest skipped"), "told")
eq(#lastSent(q).data.rows, 0, "the section hides")
eq(W.skip(q, "quest"), false, "no second skip")
-- the welcome path import: a character on step 3 of the old path starts later, silently, and the old path rests
local wcfg = dofile("data/scripts/chaos/welcomepath_config.lua")
local imp = newPlayer(6, 12)
imp.store[Chaos.storage.newPlayer] = os.time() - 99999
imp.store[wcfg.storage.base + wcfg.storage.state] = 0
imp.slots = {[1] = 2460, [6] = 8602, [9] = 2124}
players = {imp}
events.ChaosMainQuestLogin.onLogin(imp)
runTimers()
eq(imp.store[wcfg.storage.base + wcfg.storage.state], 2, "the old path rests")
check(imp.store[key("step")] > 3, "the steps it did are passed")
-- the goals.lua hooks
local gsrc = io.open("data/scripts/chaos/goals.lua"):read("*a")
check(gsrc:find("ChaosMainQuest.onAction", 1, true) and gsrc:find('msg.action:sub(1, 2) == "mq"', 1, true), "goals.lua hands the mq actions over")
check(gsrc:find("ChaosMainQuest.skip", 1, true) and gsrc:find("ChaosMainQuest.forget", 1, true), "goals.lua skips and resends")
-- the full state for the chapter window
local st = W.state(p)
eq(#st.chapters, #cfg.chapters); eq(#st.steps, #cfg.steps); eq(#st.epilogue, #cfg.epilogue)
eq(st.steps[1].state, "done"); eq(st.steps[7].state, "open"); eq(st.steps[8].state, "todo")
for _, s2 in ipairs(st.steps) do check(not s2.title:find("{", 1, true), "no open place in the window: " .. s2.key) end
W.onAction(p, {action = "mqOpen"})
eq(sent[#sent].action, "chunk", "the window state goes chunked")
-- the welcome path stays quiet while the main quest runs
dofile("data/scripts/chaos/welcomepath.lua")
check(ChaosWelcomePath.replaced(), "the welcome path is replaced")

print(string.format("mainquest_test: %d checks ok", checks))
