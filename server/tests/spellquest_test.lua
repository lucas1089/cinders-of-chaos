-- Run from the server/ folder: luajit tests/spellquest_test.lua (CI runs it with luajit and lua5.3)
-- Line spell quests: the pure rules (spellquest_core.lua: lines, steps, the done flag per line, kill weights, party credit,
-- fragments with pity, the hunt, the trial gate, the reward, the vocation change plan, the staff command) and the engine file
-- (spellquest.lua) on a mocked engine: kill credit, the reward, the Trials hook, the class sync.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks = 0
local function eq(a, b, m) checks = checks + 1; if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function check(c, m) checks = checks + 1; if not c then error(m, 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
dofile("data/scripts/chaos/spellquest_core.lua")
local Q = ChaosSpellQuestCore
local cfg = Q.cfg()
local W, R, MY, TH, NE, MO, TE = 4, 3, 1, 11, 20, 17, 23 -- the base class ids of the seven lines
local JUGG, BERS, DEAD = 8, 14, 7

-- ------------------------------------------------------------------ config
eq(type(cfg), "table", "config in Chaos.spellQuest"); eq(Chaos.spellQuest, cfg)
eq(Q.count(), 3, "three quests")
local lv, ks, fr = {500, 800, 1200}, {400, 700, 1000}, {20, 30, 40}
for i = 1, 3 do
	eq(cfg.quests[i].level, lv[i], "level " .. i); eq(cfg.quests[i].kills, ks[i], "kills " .. i); eq(cfg.quests[i].fragments, fr[i], "fragments " .. i)
end
eq(cfg.quests[1].trial, "s1"); eq(cfg.quests[3].trial, "s3")
eq(cfg.fragments.chance, 0.06); eq(cfg.fragments.tierMultiplier.rare, 2); eq(cfg.fragments.tierMultiplier.legendary, 5)
eq(cfg.fragments.pity, 40); eq(cfg.hunt.bossKills, 25); eq(cfg.reward.goldPerLevel, 2000); eq(cfg.trial.failCooldownSeconds, 60)
eq(cfg.rotationCapExempt[3], true, "quest 3 is exempt from the rotation cap (flag for phase 3)"); eq(cfg.rotationCapExempt[1], false)
eq(#cfg.lines, 7, "seven lines")
local names = {}
for i, line in ipairs(cfg.lines) do
	eq(#line.spells, 3, line.key .. " has three spells")
	check(Chaos.classes.ids[line.class], line.key .. " has a class id")
	for _, s in ipairs(line.spells) do
		check(not names[s:lower()], "spell name once: " .. s); names[s:lower()] = true
		eq(Q.spellInfo(s).line, i, "spellInfo line"); eq(Q.spellInfo(s:upper()).line, i, "spellInfo ignores case")
	end
end
eq(Q.spellInfo("Keepfall").quest, 1); eq(Q.spellInfo("Heaven's Ninth Gate").quest, 3); eq(Q.spellInfo("Fireball"), nil)
eq(cfg.lines[1].spells[1], "Keepfall"); eq(cfg.lines[2].spells[2], "Unblinking Gaze"); eq(cfg.lines[6].spells[3], "Heaven's Ninth Gate")
eq(cfg.npc.name, "Archivist Ysolde")

-- ------------------------------------------------------------------ storage keys
local seen = {}
for q = 1, 3 do
	for name, key in pairs(Q.keys(q)) do
		check(key >= 7101040 and key <= 7101069, "inside the block: " .. name)
		check(not seen[key], "storage keys are distinct: " .. name .. q); seen[key] = true
	end
end
eq(Q.keys(1).step, 7101040); eq(Q.keys(1).kills, 7101041); eq(Q.keys(1).fragments, 7101042); eq(Q.keys(1).pity, 7101043)
eq(Q.keys(1).attempts, 7101044); eq(Q.keys(1).cooldown, 7101045); eq(Q.keys(1).doneAt, 7101046); eq(Q.keys(1).lines, 7101047)
eq(Q.keys(2).step, 7101050); eq(Q.keys(3).step, 7101060); eq(Q.keys(3).lines, 7101067)
-- nothing else uses the block
for _, file in ipairs({"ascension_quest_config.lua", "trials_config.lua", "tales_config.lua", "firsthour_config.lua", "bosspoints_config.lua"}) do
	local f = assert(io.open("data/scripts/chaos/" .. file)); local src = f:read("*a"); f:close()
	for v in src:gmatch("(710[01]%d%d%d)") do
		v = tonumber(v)
		check(v < 7101040 or v > 7101069, file .. " uses " .. v .. " inside the spell quest block")
	end
end

-- ------------------------------------------------------------------ lines and the done flag
eq(Q.lineOf(W), 1); eq(Q.lineOf(JUGG), 1); eq(Q.lineOf(BERS), 1); eq(Q.lineOf(DEAD), 2); eq(Q.lineOf(R), 2)
eq(Q.lineOf(MY), 3); eq(Q.lineOf(TH), 4); eq(Q.lineOf(NE), 5); eq(Q.lineOf(MO), 6); eq(Q.lineOf(TE), 7)
for _, v in ipairs({21, 22, 12, 13, 15, 5, 10, 18, 19, 24, 25}) do check(Q.lineOf(v), "ascended vocation " .. v .. " has a line") end
eq(Q.lineOf(2), nil, "retired id"); eq(Q.lineOf(0), nil, "no vocation")
local mask = 0
check(not Q.lineDone(mask, 1) and not Q.lineDone(-1, 3), "nothing done")
mask = Q.markLine(mask, 1); mask = Q.markLine(mask, 4)
check(Q.lineDone(mask, 1) and Q.lineDone(mask, 4), "marked"); check(not Q.lineDone(mask, 2) and not Q.lineDone(mask, 7), "others open")
eq(Q.markLine(mask, 1), mask, "marking twice changes nothing"); eq(mask, 1 + 8)
eq(Q.effectiveStep(3, 0, 1), 0, "a done step stored from another line reads as not started")
eq(Q.effectiveStep(3, mask, 1), 3, "done on this line"); eq(Q.effectiveStep(1, mask, 1), 3, "the flag wins")
eq(Q.effectiveStep(-1, 0, 1), 0, "never set"); eq(Q.effectiveStep(2, 0, 1), 2); eq(Q.effectiveStep(9, 0, 1), 0)

-- ------------------------------------------------------------------ which quest
local function qs(a, b, c) return {a or {}, b or {}, c or {}} end
local num, step, code = Q.current(JUGG, 499, qs())
eq(code, "level"); eq(num, 1); eq(step, 0)
num, step, code = Q.current(JUGG, 500, qs())
eq(code, "ok"); eq(num, 1)
num, step, code = Q.current(JUGG, 900, qs({step = 1}))
eq(code, "ok"); eq(step, 1)
num, step, code = Q.current(JUGG, 900, qs({step = 3, mask = 1}))
eq(code, "ok"); eq(num, 2, "quest 1 done: quest 2"); eq(step, 0)
num, step, code = Q.current(JUGG, 799, qs({step = 3, mask = 1}))
eq(code, "level"); eq(num, 2, "quest 2 needs level 800")
num, step, code = Q.current(JUGG, 1500, qs({step = 3, mask = 1}, {step = 3, mask = 1}, {step = 3, mask = 1}))
eq(code, "done"); eq(step, 3)
num, step, code = Q.current(DEAD, 900, qs({step = 3, mask = 1}))
eq(code, "ok"); eq(num, 1, "another line: quest 1 again (its own quest)")
num, step, code = Q.current(0, 900, qs())
eq(code, "noline")
-- quest 2 on a line where quest 1 is not done: quest 1 first, never skipped
num, step, code = Q.current(JUGG, 900, qs({}, {step = 3, mask = 1}))
eq(num, 1, "quest 2 done alone does not skip quest 1")
-- the level is checked at every step: a level lowered by death stops the quest
num, step, code = Q.current(JUGG, 480, qs({step = 2}))
eq(code, "level"); eq(step, 2)
cfg.enabled = false
eq(select(3, Q.current(JUGG, 900, qs())), "off", "switched off"); cfg.enabled = true

-- ------------------------------------------------------------------ kill weights
local function k(t) local base = {playerLevel = 600, monsterLevel = 520, hunt = true}; for a, b in pairs(t or {}) do base[a] = b end; return base end
eq(Q.killWeight(1, k()), 1, "a hunt monster of level 520 counts for the level 500 quest")
eq(Q.killWeight(1, k({monsterLevel = 500})), 1, "at the level")
local w, why = Q.killWeight(1, k({monsterLevel = 499})); eq(w, 0); eq(why, "level")
w, why = Q.killWeight(1, k({playerLevel = 499})); eq(w, 0); eq(why, "playerLevel")
w, why = Q.killWeight(1, k({summon = true})); eq(w, 0); eq(why, "summon")
w, why = Q.killWeight(1, k({excluded = true})); eq(w, 0); eq(why, "instance")
w, why = Q.killWeight(1, k({nearProtection = true})); eq(w, 0); eq(why, "protection")
w, why = Q.killWeight(1, k({hunt = false})); eq(w, 0); eq(why, "event")
eq(Q.killWeight(1, k({boss = true, hunt = false})), 25, "a boss counts 25 kills")
eq(Q.killWeight(1, k({boss = true, monsterLevel = 100})), 0, "a boss below the level does not")
eq(Q.killWeight(3, k({playerLevel = 1300, monsterLevel = 1250})), 1, "level scaled monsters of the late areas: their own level")
eq(Q.killWeight(3, k({playerLevel = 1300, monsterLevel = 1199})), 0)
eq(Q.killWeight(3, k({boss = true, playerLevel = 1300, monsterLevel = 1250})), 25)
eq(Q.killWeight(9, k()), 0, "no such quest")

-- ------------------------------------------------------------------ party credit
local function P(id, x) return {id = id, x = x or 0} end
local pid, ppos = function(p) return p.id end, function(p) return {x = p.x, y = 0, z = 7} end
local near = function(a, b) return math.abs(a.x - b.x) <= 30 end
local a, b, c, d = P(1, 0), P(2, 10), P(3, 50), P(4, 5)
local party = {a, b, c}
local function partyOf(p) if p.id == 4 then return nil end return party end
local out = Q.credited({a}, {a, b, c, d}, partyOf, ppos, pid, near)
eq(#out, 2, "the killer and the party member in range who dealt damage"); eq(out[1], a); eq(out[2], b)
out = Q.credited({a}, {a}, partyOf, ppos, pid, near)
eq(#out, 1, "a party member who did no damage does not count")
out = Q.credited({a}, {a, d}, partyOf, ppos, pid, near)
eq(#out, 1, "a stranger who dealt damage but is in no party with the killer does not count")
out = Q.credited({a, d}, {a, d}, partyOf, ppos, pid, near)
eq(#out, 2, "two killers both count"); out = Q.credited({}, {a}, partyOf, ppos, pid, near); eq(#out, 0, "no killer, no credit")
out = Q.credited({a}, {c}, partyOf, ppos, pid, near); eq(#out, 1, "a party member out of range does not count")

-- ------------------------------------------------------------------ fragments
local function rng(v) return function() return v end end
local d1, p1, why1 = Q.fragmentRoll(0, "normal", false, rng(0.059)); eq(d1, true); eq(p1, 0); eq(why1, "roll")
d1, p1 = Q.fragmentRoll(0, "normal", false, rng(0.06)); eq(d1, false, "6% is exclusive"); eq(p1, 1, "pity counts the miss")
d1 = Q.fragmentRoll(0, "rare", false, rng(0.119)); eq(d1, true, "rare x2 = 12%")
d1 = Q.fragmentRoll(0, "rare", false, rng(0.12)); eq(d1, false)
d1 = Q.fragmentRoll(0, "legendary", false, rng(0.299)); eq(d1, true, "legendary x5 = 30%")
d1 = Q.fragmentRoll(0, "legendary", false, rng(0.3)); eq(d1, false)
d1 = Q.fragmentRoll(0, "magic", false, rng(0.059)); eq(d1, true, "magic as normal")
d1, p1, why1 = Q.fragmentRoll(0, "normal", true, rng(0.99)); eq(d1, true, "a boss always drops one"); eq(why1, "boss")
d1, p1, why1 = Q.fragmentRoll(39, "normal", false, rng(0.99)); eq(d1, false, "39 misses so far: no pity yet"); eq(p1, 40)
d1, p1, why1 = Q.fragmentRoll(40, "normal", false, rng(0.99)); eq(d1, true, "pity after 40 kills without one"); eq(why1, "pity"); eq(p1, 0)
d1 = Q.fragmentRoll(-1, "normal", false, rng(0.99)); eq(d1, false, "an unset pity counter reads as 0")
-- the rate over many kills with the real random source is the config's
math.randomseed(12345)
local got, kills, pity = 0, 20000, 0
for _ = 1, kills do
	local dropped; dropped, pity = Q.fragmentRoll(pity, "normal", false, math.random)
	if dropped then got = got + 1 end
end
check(got / kills > 0.06 and got / kills < 0.09, "pity lifts the rate a little over 6%: " .. got / kills)

-- ------------------------------------------------------------------ the hunt
local s = Q.startState(); eq(s.step, 1); eq(s.kills, 0)
local st, info = Q.applyKill({step = 1, kills = 0, fragments = 0, pity = 0}, 1, 1, "normal", false, rng(0.99))
eq(st.kills, 1); eq(st.pity, 1); eq(st.fragments, 0); eq(info.fragment, false); eq(info.huntDone, false)
st, info = Q.applyKill(st, 1, 1, "normal", false, rng(0.0))
eq(st.fragments, 1); eq(st.pity, 0, "pity resets on a fragment"); eq(info.fragment, true)
st, info = Q.applyKill({step = 1, kills = 390, fragments = 3, pity = 0}, 1, 25, "normal", true, rng(0.99))
eq(st.kills, 400, "kills are capped"); eq(info.killsGained, 10, "only what fits is gained"); eq(st.fragments, 4, "boss fragment")
eq(info.huntDone, false, "kills alone do not finish the hunt")
st, info = Q.applyKill({step = 1, kills = 399, fragments = 19, pity = 0}, 1, 1, "normal", false, rng(0.0))
eq(st.step, 2, "both needs met: the trial opens"); eq(info.huntDone, true); eq(st.kills, 400); eq(st.fragments, 20)
st, info = Q.applyKill({step = 1, kills = 100, fragments = 20, pity = 3}, 1, 1, "normal", false, rng(0.0))
eq(st.fragments, 20, "fragments stop at the needed number"); eq(st.pity, 3, "and so does the roll"); eq(info.fragment, false)
st, info = Q.applyKill({step = 0, kills = 0}, 1, 1, "normal", false, rng(0.0)); eq(st.kills, 0, "step 0 counts nothing")
st = Q.applyKill({step = 2, kills = 400, fragments = 20}, 1, 1, "normal", false, rng(0.0)); eq(st.kills, 400, "step 2 counts nothing")
st = Q.applyKill({step = 3, kills = 0}, 1, 1, "normal", false, rng(0.0)); eq(st.kills, 0, "step 3 counts nothing")
st = Q.applyKill({step = 1, kills = 5}, 1, 0, "normal", false, rng(0.0)); eq(st.kills, 5, "weight 0 counts nothing")
st = Q.applyKill({step = -1, kills = -1, fragments = -1, pity = -1}, 1, 1, "normal", false, rng(0.99)); eq(st.step, 0, "unset storage")
-- a whole quest with the real random source stays inside its bounds and finishes
math.randomseed(7)
st = {step = 1, kills = 0, fragments = 0, pity = 0}
local count = 0
while st.step == 1 and count < 5000 do
	st = Q.applyKill(st, 3, 1, "normal", false, math.random); count = count + 1
end
eq(st.step, 2, "quest 3 finishes"); check(count >= 1000 and count < 1500, "about 1000 kills for quest 3 (" .. count .. ")")

-- ------------------------------------------------------------------ the trial gate
local ok, text = Q.canEnterTrial(1, 2, 600, 1000, 0, false); eq(ok, true)
ok, text = Q.canEnterTrial(1, 1, 600, 1000, 0, false); eq(ok, false); check(text:find("hunt"), text)
ok, text = Q.canEnterTrial(1, 3, 600, 1000, 0, false); eq(ok, false); check(text:find("already"), text)
ok = Q.canEnterTrial(1, 2, 499, 1000, 0, false); eq(ok, false, "the level is checked again")
ok = Q.canEnterTrial(1, 2, 600, 1000, 0, true); eq(ok, false, "busy")
ok, text = Q.canEnterTrial(1, 2, 600, 1000, 1060, false); eq(ok, false, "closed 60 s"); check(text:find("1 minute"), text)
ok = Q.canEnterTrial(1, 2, 600, 1061, 1060, false); eq(ok, true, "open again")
ok = Q.canEnterTrial(7, 2, 600, 1000, 0, false); eq(ok, false, "no such quest")
eq(Q.formatWait(30), "30 seconds"); eq(Q.formatWait(1), "1 second"); eq(Q.formatWait(61), "2 minutes")
check(Q.trialText(1):find("5 minutes, 3 lives"), Q.trialText(1)); check(Q.trialText(3):find("7 minutes, 2 lives"), Q.trialText(3))

-- ------------------------------------------------------------------ the reward
local r = Q.reward(1, 1, 612, -1); eq(r.gold, 612 * 2000); eq(r.spell, "Keepfall")
r = Q.reward(3, 6, 1250, 0); eq(r.gold, 1250 * 2000); eq(r.spell, "Heaven's Ninth Gate")
r = Q.reward(2, 3, 900, 1700000000); eq(r.gold, 0, "no gold twice"); eq(r.spell, "Veil of Whispers", "the spell again")

-- ------------------------------------------------------------------ vocation change
local done1 = {{step = 3, mask = Q.lineBit(1)}, {}, {}}
eq(table.concat(Q.unlockedSpells(JUGG, done1), ","), "Keepfall"); eq(table.concat(Q.unlockedSpells(DEAD, done1), ","), "")
eq(#Q.unlockedSpells(0, done1), 0)
local known = {Keepfall = true}
local plan = Q.spellPlan(DEAD, done1, function(nm) return known[nm] end)
eq(table.concat(plan.forget, ","), "Keepfall", "changed to the Ranger line: the Warrior spell is forgotten"); eq(#plan.learn, 0)
known = {}
plan = Q.spellPlan(BERS, done1, function(nm) return known[nm] end)
eq(table.concat(plan.learn, ","), "Keepfall", "changed back (or a Berserker on the line): relearned free"); eq(#plan.forget, 0)
known = {Keepfall = true}
plan = Q.spellPlan(JUGG, done1, function(nm) return known[nm] end); eq(#plan.learn + #plan.forget, 0, "idempotent")
local all = {{mask = 127}, {mask = 127}, {mask = 127}}
eq(#Q.unlockedSpells(TE, all), 3, "all three of a line")
-- the flag survives: quest 1 done on the Warrior line, the character goes Ranger, then back: still done
num, step, code = Q.current(DEAD, 900, done1); eq(num, 1); eq(step, 0, "the Ranger line needs its own quest 1")
num, step, code = Q.current(JUGG, 900, done1); eq(num, 2, "back on the Warrior line quest 1 is still done")
-- progress in a quest is the character's, not the vocation's
num, step = Q.current(DEAD, 900, qs({step = 1})); eq(step, 1, "a running hunt continues after a class change")

-- ------------------------------------------------------------------ staff command
local act, who, args = Q.parseCommand("set Ann, 2, 1, 100, 5")
eq(act, "set"); eq(who, "Ann"); eq(args.quest, 2); eq(args.step, 1); eq(args.kills, 100); eq(args.fragments, 5)
act, who, args = Q.parseCommand("set Ann,3,3"); eq(act, "set"); eq(args.kills, nil)
act, who = Q.parseCommand("show Bob"); eq(act, "show"); eq(who, "Bob")
act, who = Q.parseCommand("reset Bob"); eq(act, "reset")
check(select(2, Q.parseCommand("")):find("Usage"), "empty"); check(select(2, Q.parseCommand("set Ann, 4, 1")):find("Usage"), "quest 4")
check(select(2, Q.parseCommand("set Ann, 1, 7")):find("Usage"), "step 7"); check(select(2, Q.parseCommand("set Ann, x, 1")):find("Usage"), "word")
check(select(2, Q.parseCommand("explode Ann")):find("Unknown"), "unknown action"); check(select(2, Q.parseCommand("show")):find("Usage"), "no name")
local cur = {mask = 0, pity = 4}
local o = Q.applySet(cur, 1, 1, 1, 10, 2); eq(o.step, 1); eq(o.kills, 10); eq(o.fragments, 2); eq(o.pity, 4); eq(o.mask, 0)
o = Q.applySet(cur, 1, 1, 2); eq(o.kills, 400); eq(o.fragments, 20); eq(o.mask, 0)
o = Q.applySet(cur, 2, 1, 3); eq(o.mask, 2, "done: the line's bit"); eq(o.step, 3)
o = Q.applySet({mask = 3}, 1, 1, 0); eq(o.mask, 2, "back to 0 takes the bit away"); eq(o.kills, 0)
o = Q.applySet(cur, 1, 1, 1, 9999, 9999); eq(o.kills, 400, "capped"); eq(o.fragments, 20)

-- ================================================================== the engine file on a mocked engine
local events, registered = {}, {}
local function eventMock(name)
	local e = setmetatable({name = name}, {__index = function() return function() end end})
	e.register = function(self) registered[#registered + 1] = self end
	return e
end
CreatureEvent, GlobalEvent, TalkAction = eventMock, eventMock, eventMock
EventCallback = setmetatable({}, {__index = function() return function() end end})
addEvent = function() return 0 end
Game = {getSpectators = function() return {} end, getPlayers = function() return {} end}
dofile("data/lib/chaos_spell_events.lua")
-- the Trials engine is not loaded: its hook table is the only thing the quest needs
ChaosTrials = {runs = {}}
dofile("data/scripts/chaos/spellquest.lua")
local S = ChaosSpellQuest
local hook = ChaosTrials.spellHook
check(S and hook and hook.won and hook.failed, "the engine file sets the Trials hook")
check(S.isQuestSpell("Keepfall") and not S.isQuestSpell("Fireball"), "isQuestSpell")

local function newPlayer(voc, level)
	local p = {id = 1, store = {}, learned = {}, msgs = {}, bank = 0, voc = voc, level = level, party = nil, pos = {x = 0, y = 0, z = 7}}
	function p:getId() return self.id end
	function p:getName() return "Tester" end
	function p:getStorageValue(key) return self.store[key] or -1 end
	function p:setStorageValue(key, v) self.store[key] = v end
	function p:getVocation() return {getId = function() return self.voc end} end
	function p:getLevel() return self.level end
	function p:sendTextMessage(t, text) self.msgs[#self.msgs + 1] = text end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:hasLearnedSpell(name) return self.learned[name] == true end
	function p:learnSpell(name) self.learned[name] = true; return true end
	function p:forgetSpell(name) self.learned[name] = nil; return true end
	function p:getPosition() return self.pos end
	return p
end
local p = newPlayer(JUGG, 600)
local k1 = Q.keys(1)
local hunt = {boss = false, excluded = false, monsterLevel = 520, hunt = true, tier = "normal", nearProtection = false}

eq(S.credit(p, hunt, rng(0.99)), 0, "step 0: nothing counts")
p:setStorageValue(k1.step, 1); p:setStorageValue(k1.kills, 0); p:setStorageValue(k1.fragments, 0)
eq(S.credit(p, hunt, rng(0.99)), 1); eq(p:getStorageValue(k1.kills), 1); eq(p:getStorageValue(k1.pity), 1)
eq(S.credit(p, hunt, rng(0.0)), 1); eq(p:getStorageValue(k1.fragments), 1)
check(p.msgs[#p.msgs]:find("Quest fragment found: 1 of 20"), p.msgs[#p.msgs])
local before = p:getStorageValue(k1.kills)
eq(S.credit(p, {boss = false, excluded = true, monsterLevel = 520, hunt = true, tier = "normal"}, rng(0.0)), 0, "an excluded monster")
eq(S.credit(p, {boss = false, monsterLevel = 520, hunt = true, tier = "normal", nearProtection = true}, rng(0.0)), 0, "near a protection zone")
eq(S.credit(p, {boss = false, monsterLevel = 300, hunt = true, tier = "normal"}, rng(0.0)), 0, "too low a monster")
p.level = 450
eq(S.credit(p, hunt, rng(0.0)), 0, "a level lowered below the gate: nothing counts")
p.level = 600
eq(p:getStorageValue(k1.kills), before, "storage untouched by the refused kills")
eq(S.credit(p, {boss = true, monsterLevel = 900, tier = "normal"}, rng(0.99)), 25, "a boss")
eq(p:getStorageValue(k1.kills), before + 25); eq(p:getStorageValue(k1.fragments), 2, "and its sure fragment")
-- the hunt ends
p:setStorageValue(k1.kills, 399); p:setStorageValue(k1.fragments, 19)
S.credit(p, hunt, rng(0.0))
eq(p:getStorageValue(k1.step), 2, "the trial is open"); check(p.msgs[#p.msgs]:find("Archivist Ysolde"), p.msgs[#p.msgs])
eq(S.credit(p, hunt, rng(0.0)), 0, "after the hunt nothing more is counted")

-- the trial: the hook completes the quest once
p.bank = 5
local lines = hook.won(p, {spell = "s1"})
eq(p:getStorageValue(k1.step), 3, "done"); check(Q.lineDone(p:getStorageValue(k1.lines), 1), "the line's flag")
eq(p.learned["Keepfall"], true, "the spell is learned"); eq(p.bank, 5 + 600 * 2000, "gold to the bank")
check(p:getStorageValue(k1.doneAt) > 0, "done time"); check(lines[1]:find("Keepfall"), lines[1]); check(lines[2]:find("1200000"), lines[2])
lines = hook.won(p, {spell = "s1"})
eq(p.bank, 5 + 600 * 2000, "a second win pays nothing"); check(lines[1]:find("not yours"), lines[1])
eq(p:getStorageValue(Q.keys(2).step), -1, "quest 2 is not started by quest 1")
eq(#hook.won(p, {spell = "nope"}), 0, "an unknown trial")
-- a failed run closes the door
hook.failed(p, {spell = "s2"}, "death"); check(p:getStorageValue(Q.keys(2).cooldown) > os.time() + 55, "60 s")
local c0 = p:getStorageValue(Q.keys(3).cooldown)
hook.failed(p, {spell = "s3"}, "logout"); eq(p:getStorageValue(Q.keys(3).cooldown), c0, "a logout is no failure")
hook.failed(p, {spell = "s3"}, "abort"); hook.failed(p, {spell = "s3"}, "error"); eq(p:getStorageValue(Q.keys(3).cooldown), c0)
-- unlocked / sync
check(S.unlocked(p, "Keepfall"), "unlocked on its line"); check(not S.unlocked(p, "Moonshard Rain"), "another line's spell is not")
p.learned = {}
local res = S.sync(p); eq(res.learn, 1, "login sync teaches the done spell"); eq(p.learned["Keepfall"], true)
p.voc = DEAD
check(not S.unlocked(p, "Keepfall"), "on the Ranger line the Warrior spell is locked")
res = S.sync(p); eq(res.forget, 1, "the vocation change forgets it"); eq(p.learned["Keepfall"], nil)
p.voc = BERS
res = S.sync(p); eq(res.learn, 1, "and back: free again"); eq(p.learned["Keepfall"], true)
eq(p:getStorageValue(k1.step), 3, "the flag was kept all along")

-- enterTrial refuses: no NPC near, wrong step, and does not call the engine then
local entered = 0
ChaosTrials.enter = function(player, tier, opts) entered = entered + 1; return true end
local p2 = newPlayer(JUGG, 600)
p2:setStorageValue(k1.step, 2)
local okE, why = S.enterTrial(p2); eq(okE, false); check(why:find("Archivist Ysolde"), why); eq(entered, 0, "no Archivist near")
Game.getSpectators = function() return {{isNpc = function() return true end, getName = function() return "Archivist Ysolde" end}} end
okE = S.enterTrial(p2); eq(okE, true); eq(entered, 1); eq(p2:getStorageValue(k1.attempts), 1, "attempt counted")
p2:setStorageValue(k1.step, 1)
okE, why = S.enterTrial(p2); eq(okE, false); eq(entered, 1, "step 1: no trial")
p2:setStorageValue(k1.step, 2); p2:setStorageValue(k1.cooldown, os.time() + 30)
okE = S.enterTrial(p2); eq(okE, false, "the door is shut"); eq(entered, 1)

print("spellquest_test: " .. checks .. " checks OK")
