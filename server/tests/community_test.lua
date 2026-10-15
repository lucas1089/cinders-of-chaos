-- Run from the server/ folder: luajit tests/community_test.lua (or lua5.3; CI runs both)
-- Community goals and the weekly world modifier: the config, weeks and periods, points and the daily caps, Brazier
-- donations, stages and their buff windows, the ranking and the period rewards, the seeded draw of the week's modifiers
-- (fixed expected draws, so LuaJIT and Lua 5.3 must agree), staff overrides, every hook neutral when nothing is active
-- (and the shared hook points: rift_core.lua, loot_config.lua, chaos_buffs.lua), the hooks when active; then
-- community.lua against a mocked engine (kills, the leaderboard / world boss wraps, orbs and Forgefire, the Brazier,
-- stage unlocks, the week's runtime events, the buff bar, the opcode, the staff command, a period's end and its rewards).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/community_config.lua")
dofile("data/scripts/chaos/community_core.lua")
local K = ChaosCommunityCore

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function at(y, m, d, h, mi)
	return os.time({year = y, month = m, day = d, hour = h or 12, min = mi or 0, sec = 0})
end

-- ---------------------------------------------------------------- the config and the opcode
local problems = K.validate(cfg)
eq(#problems, 0, "config problems (" .. table.concat(problems, "; ") .. ")")
eq(ChaosOpcodes.community, 203, "opcode registered in chaos_constants.lua")
eq(cfg.opcode, ChaosOpcodes.community, "config opcode")
for name, op in pairs(ChaosOpcodes) do
	check(name == "community" or op ~= 203, "opcode 203 used only by community (" .. name .. ")")
end
for _, op in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(op ~= 203, "not a reference server opcode")
end
eq(#cfg.goal.stages, 4, "four stages")
eq(cfg.goal.stages[1].pct .. "/" .. cfg.goal.stages[2].pct .. "/" .. cfg.goal.stages[3].pct .. "/" .. cfg.goal.stages[4].pct,
	"25/50/75/100", "stage percents")
-- a broken config is reported
local bad = dofile("data/scripts/chaos/community_config.lua")
bad.goal.stages[2].pct = 10
bad.week.pool[1].riftMods, bad.week.pool[1].riftReward = nil, nil
bad.goal.realms = "both"
check(#K.validate(bad) >= 3, "validate finds rising percents, a modifier without effect and the realm option")
-- the bestiary families the modifiers name exist
local bcfg = dofile("data/scripts/chaos/bestiary_config.lua")
local cats = {}
for _, c in ipairs(bcfg.categories) do cats[c.key] = true end
for _, m in ipairs(cfg.week.pool) do
	if m.family then check(cats[m.family], m.key .. ": family " .. m.family .. " is a bestiary category") end
end
-- the brazier's daily gold matches its source cap
local bs = K.source(cfg, "brazier")
eq(cfg.brazier.dailyGold, bs.dailyCap / bs.points * bs.perGold, "brazier dailyGold = dailyCap x perGold")

-- ---------------------------------------------------------------- weeks, periods, days
eq(K.week(at(2026, 10, 10), 6), 20261005, "Saturday -> its Monday")
eq(K.week(at(2026, 10, 12, 5, 59), 6), 20261005, "Monday before the reset hour: last week")
eq(K.week(at(2026, 10, 12, 6, 0), 6), 20261012, "Monday at the reset hour: the new week")
eq(K.weekEnd(at(2026, 10, 10), 6), at(2026, 10, 12, 6), "the week ends Monday 06:00")
local pk, ps, pf = K.period(cfg, at(2026, 10, 10))
eq(pk, 20261005, "week period key")
eq(ps, at(2026, 10, 5, 6), "week period start")
eq(pf, at(2026, 10, 12, 6), "week period finish")
local c3 = dofile("data/scripts/chaos/community_config.lua")
c3.goal.periodDays = 3
local k1, s1, f1 = K.period(c3, at(2026, 1, 5, 7))
eq(k1, 20260105, "3-day period: the epoch")
eq(f1, at(2026, 1, 8, 6), "3-day period: its end")
local k2 = K.period(c3, at(2026, 1, 8, 6))
eq(k2, 20260108, "3-day period: the next one starts at its reset hour")
eq(K.period(c3, at(2026, 1, 8, 5)), 20260105, "an hour before: still the first")
local k3, s3 = K.period(c3, at(2026, 10, 10))
check(s3 <= at(2026, 10, 10) and at(2026, 10, 10) < s3 + 3 * 86400 + 3600, "3-day period of a later date contains it")
eq(K.day(at(2026, 10, 10, 5), 6), 20261009, "the cap day turns at the reset hour")
eq(K.realmOf(cfg, 7), 0, "together: every realm counts as 0")
local sep = dofile("data/scripts/chaos/community_config.lua")
sep.goal.realms = "separate"
eq(K.realmOf(sep, 7), 7, "separate: the season realm")

-- ---------------------------------------------------------------- points and caps
eq(K.points(cfg, "kill", 1), 1, "a normal kill")
eq(K.points(cfg, "kill", 1, {tier = "rare"}), 4, "a rare kill")
eq(K.points(cfg, "kill", 1, {tier = "legendary"}), 8, "a legendary kill")
eq(K.points(cfg, "rift", 1, {riftTier = 10}), 120 + 150, "a tier 10 rift")
eq(K.points(cfg, "invasion", 5), 200, "five waves")
eq(K.points(cfg, "worldboss", 1), 400, "a world boss")
eq(K.points(cfg, "orb", 3), 36, "three orbs")
eq(K.points(cfg, "brazier", 25500), 25, "gold: whole thousands")
eq(K.points(cfg, "nope", 1), 0, "unknown source")
eq(K.points(cfg, "kill", -3), 0, "no negative units")
local e = K.newEntry()
local g1, capped = K.credit(cfg, e, "kill", 3990, 20261010, 100)
eq(g1, 3990, "kills under the source cap")
check(not capped, "not capped")
local g2, capped2 = K.credit(cfg, e, "kill", 50, 20261010, 101)
eq(g2, 10, "the kill cap (4000 a day) cuts")
check(capped2, "capped")
eq(K.credit(cfg, e, "rift", 3000, 20261010, 102), 3000, "a rift day")
eq(K.credit(cfg, e, "worldboss", 2000, 20261010, 103), 2000, "a world boss day")
eq(K.credit(cfg, e, "invasion", 2500, 20261010, 104), 2500, "invasions: 11500 so far")
eq(K.credit(cfg, e, "orb", 1000, 20261010, 105), 500, "the character's daily cap (12000) cuts across sources")
eq(e.dayTotal, 12000, "the day total")
eq(e.points, 12000, "the period total")
eq(K.roomToday(cfg, e, "brazier", 20261010), 0, "no room left today")
eq(K.credit(cfg, e, "kill", 100, 20261011, 200), 100, "a new day: the caps start again")
eq(e.points, 12100, "the period total keeps growing")
eq(e.daySrc.kill, 100, "per-source counts of the new day")
eq(e.at, 200, "when it last changed")
eq(K.encodeSrc({rift = 300, kill = 120, orb = 0}), "kill:120,rift:300", "encode the day's sources")
eq(K.decodeSrc("kill:120,rift:300").rift, 300, "decode")
eq(next(K.decodeSrc("garbage")), nil, "decode garbage: empty")

-- ---------------------------------------------------------------- Brazier donations
local d = K.newEntry()
eq(K.donation(cfg, d, 999, 1), 0, "under the minimum")
eq(K.donation(cfg, d, 25500, 1), 25000, "whole thousands")
eq(K.donation(cfg, d, 99999999, 1), 5000000, "the daily gold")
eq(K.donation(cfg, d, 50000, 1, 20000), 0, "more than carried")
K.credit(cfg, d, "brazier", 4990, 1, 1)
eq(K.donation(cfg, d, 1000000, 1), 10000, "the rest of today's room")
K.credit(cfg, d, "brazier", 10, 1, 1)
local zero, why = K.donation(cfg, d, 5000, 1)
eq(zero, 0, "nothing more today")
check(why and why:find("today"), "says why")

-- ---------------------------------------------------------------- stages and buff windows
local target = cfg.goal.target
eq(K.stageAt(cfg, 0), 0, "no stage at 0")
eq(K.stageAt(cfg, target * 0.25), 1, "stage 1 at 25%")
eq(K.stageAt(cfg, target * 2), 4, "stage 4 past 100%")
eq(K.pct(cfg, target * 3), 100, "percent stops at 100")
local cr = K.crossed(cfg, target * 0.2, target * 0.8)
eq(#cr .. ":" .. cr[1] .. ":" .. cr[2] .. ":" .. cr[3], "3:1:2:3", "three stages crossed at once")
eq(#K.crossed(cfg, target * 0.3, target * 0.4), 0, "none between stages")
local st = K.steps(cfg, target * 0.05, target * 0.12)
eq(#st == 1 and st[1], 10, "announce step 10%")
local buffs, now0 = {}, at(2026, 10, 10)
K.openWindow(cfg, buffs, 1, now0, 20261005)
K.openWindow(cfg, buffs, 4, now0, 20261005)
eq(#K.activeStages(cfg, buffs, now0 + 3600), 2, "two windows open")
eq(math.floor(K.stageBonus(cfg, buffs, now0 + 3600, "xp") * 100 + 0.5), 15, "xp: 10% + 5%")
eq(K.stageBonus(cfg, buffs, now0 + 3600, "rep"), 0.20, "rep 20%")
eq(#K.activeStages(cfg, buffs, now0 + 30 * 3600), 1, "the 24 h window closed, the 48 h one runs")
eq(K.stageBonus(cfg, buffs, now0 + 49 * 3600, "xp"), 0, "all closed")
eq(K.openWindow(cfg, buffs, 9, now0), nil, "no stage 9")

-- ---------------------------------------------------------------- ranking and rewards
local list = {
	{guid = 1, name = "Ash", points = 3000, at = 50},
	{guid = 2, name = "Bryn", points = 9000, at = 70},
	{guid = 3, name = "Cael", points = 3000, at = 40},
	{guid = 4, name = "Staff", points = 99999, at = 1},
	{guid = 5, name = "Dree", points = 1000, at = 10},
	{guid = 6, name = "Nil", points = 0, at = 1},
	{guid = 7, name = "Eon", points = 1500, at = 10}}
local ranked = K.rank(list, {[4] = true})
eq(#ranked, 5, "staff and zero left out")
eq(ranked[1].name .. "," .. ranked[2].name .. "," .. ranked[3].name, "Bryn,Cael,Ash", "points, then who got there first")
local rw = K.periodRewards(cfg, ranked)
eq(rw[2].place, 1, "first place")
eq(rw[1].place, 3, "third place")
check(rw[7] and rw[7].place == 0 and rw[7].token, "1500 points: the token, no place")
eq(rw[5], nil, "1000 points: nothing")
local title = K.titleOf(cfg, 1, at(2026, 10, 12, 6), at(2026, 10, 14))
check(title and title.text == cfg.goal.rewards.title, "the title while it lasts")
eq(K.titleOf(cfg, 1, at(2026, 10, 12, 6), at(2026, 10, 19, 7)), nil, "the title runs out")
eq(K.titleOf(cfg, 0, at(2026, 10, 12, 6), at(2026, 10, 14)), nil, "no place, no title")

-- ---------------------------------------------------------------- the week's modifiers (seeded)
eq(K.hash("abc"), 193485963, "hash: the same in both interpreters")
eq(K.weekSeed(cfg, 20261005), 518561481, "the week's seed")
local expected = {
	[20261005] = "restless_dead,forgefire", [20261012] = "restless_dead,banner_week",
	[20261019] = "restless_dead,banner_week", [20261026] = "ember_tides,ambush_season", [20261102] = "forgefire",
	[20261109] = "ember_tides", [20261116] = "champions_week,forgefire", [20261123] = "restless_dead,tower_echoes"}
for w, keys in pairs(expected) do
	eq(table.concat(K.pickModifiers(cfg, w), ","), keys, "draw of week " .. w)
	eq(table.concat(K.pickModifiers(cfg, w), ","), keys, "again: the same draw of week " .. w)
end
local counts, groupsOk, freq = {}, true, {}
local t0 = at(2026, 1, 5)
for i = 0, 519 do
	local keys = K.pickModifiers(cfg, K.week(t0 + i * 7 * 86400, 6))
	counts[#keys] = (counts[#keys] or 0) + 1
	local groups = {}
	for _, k in ipairs(keys) do
		local m = K.mod(cfg, k)
		if groups[m.group] then groupsOk = false end
		groups[m.group] = true
		freq[k] = (freq[k] or 0) + 1
	end
end
check(groupsOk, "never two modifiers of one group")
check((counts[1] or 0) > 150 and (counts[2] or 0) > 150 and not counts[0] and not counts[3], "one or two modifiers a week")
for _, m in ipairs(cfg.week.pool) do
	check((freq[m.key] or 0) > 30, m.key .. " comes up (" .. tostring(freq[m.key]) .. " of 520 weeks)")
end
-- overrides
local keys, err = K.checkKeys(cfg, "ember_tides, gilded_week")
eq(keys and table.concat(keys, ","), "ember_tides,gilded_week", "staff keys")
check(not K.checkKeys(cfg, "champions_week,ambush_season"), "two of one group refused")
check(not K.checkKeys(cfg, "nope"), "unknown refused")
check(not K.checkKeys(cfg, ""), "empty refused")
local ow = K.encodeOverride(20261005, {"gilded_week"})
eq(ow, "20261005:gilded_week", "override text")
local defs, src = K.weekModifiers(cfg, 20261005, ow)
eq(#defs .. defs[1].key .. src, "1gilded_weekstaff", "the override for its week")
defs, src = K.weekModifiers(cfg, 20261012, ow)
eq(table.concat((function() local o = {} for _, m in ipairs(defs) do o[#o + 1] = m.key end return o end)(), ",") .. src,
	"restless_dead,banner_weekseed", "an old override is ignored: the seed")
defs, src = K.weekModifiers(cfg, 20261005, "20261005:nope")
eq(src, "seed", "an invalid override falls back to the seed")

-- ---------------------------------------------------------------- hooks: neutral when nothing is active
local none, nobuffs = {}, {}
eq(K.xpMult(cfg, nobuffs, none, now0, "undead"), 1, "xp neutral")
eq(K.lootMult(cfg, nobuffs, none, now0, "undead"), 1, "loot neutral")
eq(K.repMult(cfg, nobuffs, none, now0), 1, "reputation neutral")
eq(K.riftWorld(cfg, nobuffs, none, now0), nil, "rift neutral")
eq(K.orbKeep(none), 0, "orbs neutral")
eq(K.eventBonus(none), nil, "no runtime event bonus")
eq(#K.buffItems(cfg, nobuffs, none, now0, now0 + 100, "stage"), 0, "no stage items")
eq(#K.buffItems(cfg, nobuffs, none, now0, now0 + 100, "week"), 0, "no modifier items")
-- every modifier on its own changes only what it names
for _, m in ipairs(cfg.week.pool) do
	local mods = {m}
	local fam = m.family
	local other = fam == "undead" and "dragons" or "undead"
	eq(K.xpMult(cfg, nobuffs, mods, now0, other), 1, m.key .. ": xp of another family untouched")
	eq(K.lootMult(cfg, nobuffs, mods, now0, nil), 1, m.key .. ": loot of a monster without family untouched")
	if not m.rep then eq(K.repMult(cfg, nobuffs, mods, now0), 1, m.key .. ": reputation untouched") end
	if not (m.riftMods or m.riftReward) then eq(K.riftWorld(cfg, nobuffs, mods, now0), nil, m.key .. ": rifts untouched") end
	if not m.orbKeep then eq(K.orbKeep(mods), 0, m.key .. ": orbs untouched") end
	if not m.events then eq(K.eventBonus(mods), nil, m.key .. ": no calendar bonus") end
end
-- the shared hook points with no hook installed: rift_core.lua, chaos_buffs.lua, loot_config.lua
local rcfg = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/scripts/chaos/rift_core.lua")
local R = ChaosRiftCore
local fakePlayer = {}
eq(R.atlasMods(fakePlayer, {}), nil, "rift: no atlas, no world hook -> nil")
R.hooks.atlasMods = function() return {density = 10} end
local am = R.atlasMods(fakePlayer, {})
check(am and am.density == 10 and am.keyChance == nil, "rift: the atlas answer unchanged without a world hook")
R.hooks.world = function() return nil end
local am2 = R.atlasMods(fakePlayer, {})
check(am2 and am2.density == 10 and am2.keyChance == nil and am2.rewardMult == nil, "rift: a nil world answer changes nothing")
local key = {tier = 5, mods = {{key = rcfg.mods[1].key, value = 10}}}
eq(#R.worldKeyMods(rcfg, fakePlayer, key, function(a) return a end), 0, "rift: no extra modifiers")
eq(#key.mods, 1, "rift: the key unchanged")
local same = {x = 1}
check(R.mergeWorld(same, nil) == same and R.mergeWorld(nil, nil) == nil, "mergeWorld without wm returns am itself")
check(R.mergeWorld(same, {keyChance = 0, rewardMult = 0, extraMods = 1}) == same, "mergeWorld: only extraMods -> am itself")
-- the odds with the atlas only equal the odds with a neutral world hook
local o1 = R.keyOdds(rcfg, 2, R.hooks.atlasMods())
local o2 = R.keyOdds(rcfg, 2, R.atlasMods(fakePlayer, {}))
eq(o1.chance .. "/" .. o1.nextTier, o2.chance .. "/" .. o2.nextTier, "key odds unchanged")
R.hooks.atlasMods, R.hooks.world = nil, nil
-- loot_config.lua rateMult: the same without the module, with it inactive
local lcfg = dofile("data/scripts/chaos/loot_config.lua")
local base = lcfg.rateMult({tier = "normal"})
ChaosCommunity = {lootMult = function() return 1 end}
eq(lcfg.rateMult({tier = "normal"}), base, "loot rateMult unchanged by an inactive community")
ChaosCommunity = {lootMult = function() return 1.1 end}
eq(math.floor(lcfg.rateMult({tier = "normal"}) * 1000 + 0.5), math.floor(base * 1100 + 0.5), "loot rateMult x community")
ChaosCommunity = nil
-- chaos_buffs.lua: the registry entries are valid and the source is quiet without the module
dofile("data/lib/chaos_buffs.lua")
local BF = ChaosBuffs
check(BF.byKey.community_goal and BF.byKey.wmod_week and BF.byKey.wmod_week.week, "registry entries")
eq(#BF.validate(), 0, "the buff registry validates")
eq(BF.sources.community({}, 0, BF.byKey.community_goal), nil, "buff source quiet without community.lua")

-- ---------------------------------------------------------------- hooks: active
local undead = {K.mod(cfg, "restless_dead")}
eq(K.xpMult(cfg, nobuffs, undead, now0, "undead"), 1.3, "Restless Dead: +30% xp from undead")
eq(K.lootMult(cfg, nobuffs, undead, now0, "undead"), 1.3, "Restless Dead: +30% loot from undead")
eq(math.floor(K.xpMult(cfg, buffs, undead, now0 + 60, "undead") * 1000 + 0.5), 1495, "stage xp 15% x family 30%")
eq(K.familyOf(cfg, "Skeleton Warrior"), "undead", "family by word without the bestiary")
eq(K.familyOf(cfg, "Frost Dragon Hatchling"), "dragons", "dragons by word")
eq(K.familyOf(cfg, "Rat"), nil, "no family")
eq(K.familyOf(cfg, "Skeleton", function() return "constructs" end), "constructs", "the bestiary wins")
local beacon = {}
K.openWindow(cfg, beacon, 3, now0, 1)
local wm = K.riftWorld(cfg, beacon, {K.mod(cfg, "ember_tides")}, now0 + 10)
check(wm and wm.keyChance == 5 and wm.rewardMult == 15 and wm.extraMods == 1, "Rift Beacon and Ember Tides")
R.hooks.world = function() return wm end
local merged = R.atlasMods(fakePlayer, {})
check(merged and merged.keyChance == 5 and merged.rewardMult == 15, "rift: merged into the atlas modifiers")
local odds = R.keyOdds(rcfg, 0, merged)
eq(odds.chance, rcfg.keyDrop.base + 5, "rift: +5 key chance")
local chest = R.atlasReward(rcfg, {gold = 1000, chaos = 2, divine = 0, rolls = 2}, nil, merged, function(a) return a end)
eq(chest.gold, 1150, "rift: chests 15% richer")
local key2 = {tier = 5, mods = {{key = rcfg.mods[1].key, value = 10}}}
local seed = 7
local added = R.worldKeyMods(rcfg, fakePlayer, key2, function(a, b) seed = (seed * 16807) % 2147483647 return a + seed % (b - a + 1) end)
eq(#added, 1, "rift: Ember Tides adds a modifier")
eq(#key2.mods, 2, "rift: the key has two now")
R.hooks.world = nil
eq(K.orbKeep({K.mod(cfg, "forgefire")}), 20, "Forgefire keeps 20%")
local eb = K.eventBonus({K.mod(cfg, "champions_week"), K.mod(cfg, "gilded_week")})
check(eb and eb.tierChance == 1.5 and eb.goblin == 2, "calendar bonuses merged")
eq(math.floor(K.repMult(cfg, buffs, {K.mod(cfg, "banner_week")}, now0 + 60) * 100 + 0.5), 140, "rep: Ablaze 20% + Banner 20%")
local items = K.buffItems(cfg, buffs, undead, now0 + 60, now0 + 3600, "stage")
eq(#items, 2, "two stage items")
eq(items[1].icon, "buff:community_kindled", "stage icon")
local witems = K.buffItems(cfg, buffs, undead, now0 + 60, now0 + 3600, "week")
eq(witems[1].icon .. ":" .. witems[1].leftMs, "buff:wmod_restless_dead:3540000", "modifier item with the week's time")
-- every stage and modifier has its icon file
for _, s in ipairs(cfg.goal.stages) do
	local f = io.open("../client/overlay/data/images/game/buffs/community_" .. s.key .. ".png", "rb")
	check(f ~= nil, "icon community_" .. s.key)
	if f then f:close() end
end
for _, m in ipairs(cfg.week.pool) do
	local f = io.open("../client/overlay/data/images/game/buffs/wmod_" .. m.key .. ".png", "rb")
	check(f ~= nil, "icon wmod_" .. m.key)
	if f then f:close() end
end
-- payload and login lines
local pl = K.payload(cfg, {now = now0, period = 20261005, finish = now0 + 7200, progress = target * 0.6, buffs = buffs,
	mods = undead, modSource = "seed", weekEnd = now0 + 7200, entry = e, day = 20261011, rank = 2,
	top = {{name = "Bryn", points = 9000}}, near = true, gold = 123456})
eq(pl.goal.pct, 60, "payload percent")
check(pl.stages[2].done and not pl.stages[3].done, "payload stages reached")
check(pl.stages[1].left and pl.stages[1].left > 0, "payload: the open window's time")
eq(pl.mine.today, 100, "payload: today's points")
eq(pl.week.mods[1].k, "restless_dead", "payload: the week")
eq(pl.brazier.near, true, "payload: near the Brazier")
eq(pl.top[1].n, "Bryn", "payload: the top")
local lines = K.loginLines(cfg, target * 0.6, buffs, undead, now0, now0 + 7200)
check(lines[1]:find("60%%") and lines[1]:find("Kindled Brazier"), "login line: percent and the open stage")
check(lines[2]:find("Restless Dead"), "login line: the week")

-- ---------------------------------------------------------------- community.lua against a mocked engine
local registry, globals, talks, actions, xpCbs = {}, {}, {}, {}, {}
function CreatureEvent(name)
	local o = {}
	function o:type() end
	function o:register() registry[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:register() globals[name] = o end
	function o:interval() end
	return o
end
function TalkAction(words)
	local o = {}
	function o:separator() end
	function o:register() talks[words] = o end
	return o
end
function Action()
	local o = {}
	function o:aid(id) self.id = id end
	function o:register() actions[self.id] = o end
	return o
end
EventCallback = setmetatable({register = function() end},
	{__newindex = function(_, k, v) if k == "onGainExperience" then xpCbs[#xpCbs + 1] = v end end})
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}} return #queue end
local function runEvents()
	while #queue > 0 do
		local ev = table.remove(queue, 1)
		ev.fn((table.unpack or unpack)(ev.args))
	end
end
local queries = {}
db = {query = function(qq) queries[#queries + 1] = qq return true end, escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	storeQuery = function() return false end}
db.asyncQuery = db.query
local function queried(pattern)
	for _, qq in ipairs(queries) do
		if qq:find(pattern) then return qq end
	end
	return nil
end
local selectRows = function() return {} end
Chaos.select = function(qq, cols) return selectRows(qq) or {} end
local encoded = {}
json = {encode = function(t) encoded[#encoded + 1] = t return "{}" end, decode = function(s) return s end}
Chaos.decode = function(b) return b end
local clock = at(2026, 10, 10, 14)
local realTime = os.time
os.time = function(tt) if tt then return realTime(tt) end return clock end
local rolls = 100
math.random = function(a, b) return rolls end
local broadcasts = {}
local created = {}
Position = function(x, y, z) return {x = x, y = y, z = z, sendMagicEffect = function() end} end
local players = {}
local nextId = 1000
local function mkPlayer(name, guid, group, pos)
	nextId = nextId + 1
	local p = {id = nextId, name = name, guid = guid, group = group or 1, pos = pos or Position(100, 100, 7), level = 300,
		money = 2000000, bank = 0, items = {}, msgs = {}, ops = {}, events = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getMaster() return nil end
	function p:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function p:getPosition() return self.pos end
	function p:getMoney() return self.money end
	function p:getBankBalance() return self.bank end
	function p:removeTotalMoney(g) if self.money < g then return false end self.money = self.money - g return true end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:sendExtendedOpcode(op, data) self.ops[#self.ops + 1] = {op, data} return true end
	function p:registerEvent(ev) self.events[ev] = true end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:addItem(id, nn) self.items[id] = (self.items[id] or 0) + (nn or 1) return true end
	function p:getInbox() return nil end
	players[#players + 1] = p
	return p
end
Player = function(x)
	if type(x) == "table" then return x end
	for _, p in ipairs(players) do
		if p.id == x or p.name == x then return p end
	end
	return nil
end
Game = {
	broadcastMessage = function(text) broadcasts[#broadcasts + 1] = text end,
	getPlayers = function() return players end,
	createItem = function(id, nn, pos)
		local it = {id = id, pos = pos, attrs = {}}
		function it:setActionId(a) self.aid = a end
		function it:getActionId() return self.aid end
		function it:setAttribute(k, v) self.attrs[k] = v end
		function it:getPosition() return self.pos end
		created[#created + 1] = it
		return it
	end
}
Town = function(id) return id == cfg.brazier.townId and {getTemplePosition = function() return {x = 100, y = 100, z = 7} end} or nil end
Tile = function(pos)
	return {getGround = function() return true end, hasProperty = function() return false end,
		getTopCreature = function() return nil end, hasFlag = function() return false end, getItems = function() return {} end}
end
ChaosCommands = {register = function() end}
local titleSources = {}
ChaosTitles = {register = function(source, fn) titleSources[source] = fn end}
local recorded = {}
ChaosLeaderboard = {record = function(board, who, value, mode) recorded[#recorded + 1] = board return {} end,
	recordShares = function(shares) recorded[#recorded + 1] = "shares" end}
ChaosInvasion = {state = {waves = 5}}
ChaosBestiary = {cat = function()
	return {byKey = {["skeleton warrior"] = {cat = "undead", level = 200}, ["rat"] = {cat = "beasts", level = 4},
		["dragon"] = {cat = "dragons", level = 150}}}
end}
ChaosTierOf = function(m) return m.tier or "normal" end
-- the event calendar (real file) for the runtime events and its experience callback
Chaos.events.list = {}
dofile("data/scripts/chaos/events_schedule.lua")
local logged = {}
local print_ = print
print = function(s) logged[#logged + 1] = s end
dofile("data/scripts/chaos/community.lua")
local X = ChaosCommunity
check(registry.ChaosCommunityLogin and registry.ChaosCommunityExtended and registry.ChaosCommunityKill
	and registry.ChaosCommunityLogout, "events registered")
check(talks["/community"] and actions[cfg.brazier.actionId], "staff command and the Brazier action")
check(#xpCbs == 2, "experience callbacks: the calendar's and ours")
check(ChaosRiftCore.hooks.world ~= nil, "the rift hook")
-- startup: the week (seed), its runtime events, the goal, the Brazier
globals.ChaosCommunityStartup.onStartup()
runEvents()
check(queried("CREATE TABLE IF NOT EXISTS `chaos_community_goal`") and queried("chaos_community_history"), "tables created")
eq(X.week.key, 20261005, "the week")
eq(#X.week.mods, 2, "this week's draw: two modifiers")
eq(X.week.mods[1].key .. "," .. X.week.mods[2].key, "restless_dead,forgefire", "the seeded week")
check(queried("INSERT INTO `chaos_community_week`.-restless_dead,forgefire"), "the week written for the website")
check(queried("INSERT INTO `chaos_community_week`.-, 'seed', %d+, %d+%)"), "the week's source written as a quoted string")
check(ChaosEvents.dynamic.community_restless_dead and ChaosEvents.dynamic.community_forgefire, "runtime events in !events")
eq(ChaosEvents.bonus("tierChance"), 1, "no calendar bonus from these two")
eq(created[1] and created[1].aid, cfg.brazier.actionId, "the Brazier placed with its action id")
eq(X.brazierPos and X.brazierPos.x, 103, "next to the temple")
check(titleSources.community ~= nil and ChaosLeaderboard.communityWrapped and ChaosLeaderboard.communitySharesWrapped, "hooks")
-- a player logs in: lines, events
local hero = mkPlayer("Hero", 501, 1, Position(103, 99, 7))
local gm = mkPlayer("Gamemaster", 900, 5)
registry.ChaosCommunityLogin.onLogin(hero)
check(hero.events.ChaosCommunityKill and hero.events.ChaosCommunityExtended, "player events at login")
check(hero.msgs[1] and hero.msgs[1]:find("Community goal"), "login line")
-- kills: a rare undead, a trivial rat (nothing), a summon (nothing); staff adds nothing
local function mkMonster(name, tier, master)
	nextId = nextId + 1
	local m = {id = nextId, name = name, tier = tier}
	function m:getId() return self.id end
	function m:isMonster() return true end
	function m:isPlayer() return false end
	function m:getMaster() return master end
	function m:getName() return self.name end
	function m:getType() local nn = self.name return {name = function() return nn end} end
	return m
end
registry.ChaosCommunityKill.onKill(hero, mkMonster("Skeleton Warrior", "rare"))
registry.ChaosCommunityKill.onKill(hero, mkMonster("Rat"))
registry.ChaosCommunityKill.onKill(hero, mkMonster("Skeleton Warrior", nil, hero))
registry.ChaosCommunityKill.onKill(gm, mkMonster("Skeleton Warrior", "rare"))
eq(X.entries[501].points, 4, "a rare kill = 4 points; rats, summons and staff nothing")
eq(X.entries[900], nil, "staff never ranked")
eq(X.goals[0].progress, 4, "the goal grew")
-- the experience of an undead kill: Restless Dead +30%, a rat untouched (our callback is the second)
local ourXp = xpCbs[2]
eq(ourXp(hero, mkMonster("Skeleton Warrior"), 1000, 1000), 1300, "undead +30% experience")
eq(ourXp(hero, mkMonster("Rat"), 1000, 1000), 1000, "a rat: unchanged")
eq(ourXp(hero, nil, 1000, 1000), 1000, "no source: unchanged")
eq(math.floor(X.lootMult({monster = mkMonster("Skeleton Warrior"), player = hero}) * 100 + 0.5), 130, "undead loot")
eq(X.lootMult({monster = mkMonster("Rat"), player = hero}), 1, "rat loot unchanged")
eq(X.repMult(hero), 1, "no reputation bonus this week")
eq(X.riftWorld(hero), nil, "no rift change this week")
-- the leaderboard wraps: a sealed tier 8 rift, a defended invasion (5 waves), a world boss share
ChaosLeaderboard.record("rift", hero, 8, "max")
eq(X.entries[501].points, 4 + 120 + 120, "rift tier 8 = 240 points")
ChaosLeaderboard.record("defender", {guid = 501, name = "Hero"}, 30, "add")
eq(X.entries[501].points, 244 + 200, "five waves = 200 points")
ChaosLeaderboard.recordShares({{guid = 501, name = "Hero"}, {guid = 777, name = "Offline"}})
eq(X.entries[501].points, 444 + 400, "a world boss share = 400 points; offline shares skipped")
eq(#recorded, 3, "the original functions still ran")
ChaosLeaderboard.record("goblin", hero, 1, "add")
eq(X.entries[501].points, 844, "other boards add nothing")
-- orbs: Forgefire keeps one when the roll is low enough
rolls = 100
eq(X.onOrbUsed(hero, "fate"), false, "a high roll: the orb is used")
rolls = 5
eq(X.onOrbUsed(hero, "fate"), true, "a low roll: Forgefire keeps it")
eq(X.entries[501].points, 844 + 24, "two orbs = 24 points either way")
-- the buff bar: the week's modifiers, no stage yet
local wk = X.buffItems(hero, {week = true})
eq(#wk, 2, "two modifier items")
eq(#X.buffItems(hero, {}), 0, "no stage window yet")
local viaRegistry = BF.sources.community(hero, 0, BF.byKey.wmod_week)
eq(viaRegistry and #viaRegistry, 2, "through the buff registry")
-- the Brazier: too far, then next to it
local far = mkPlayer("Far", 502, 1, Position(150, 150, 7))
registry.ChaosCommunityLogin.onLogin(far)
encoded = {}
registry.ChaosCommunityExtended.onExtendedOpcode(far, 203, {action = "donate", data = {gold = 50000}})
check(encoded[#encoded] and encoded[#encoded].action == "msg" and encoded[#encoded].data.text:find("Stand next to"), "too far")
eq(far.money, 2000000, "no gold taken")
registry.ChaosCommunityExtended.onExtendedOpcode(hero, 203, {action = "donate", data = {gold = 150500}})
eq(hero.money, 2000000 - 150000, "whole thousands taken")
eq(X.entries[501].points, 868 + 150, "150 points")
local st1 = nil
for _, enc in ipairs(encoded) do if enc.action == "state" then st1 = enc.data end end
check(st1 and st1.brazier.near and st1.mine.p == 1018, "the window state after a donation")
registry.ChaosCommunityExtended.onExtendedOpcode(gm, 203, {action = "donate", data = {gold = 50000}})
eq(gm.money, 2000000, "staff gold not taken")
-- using the Brazier opens the dialog
encoded = {}
actions[cfg.brazier.actionId].onUse(far, created[1], created[1].pos)
check(encoded[1] and encoded[1].action == "brazier" and encoded[2] and encoded[2].action == "state", "the Brazier opens the dialog")
-- a stage: the staff command adds points past 25%
broadcasts = {}
talks["/community"].onSay(gm, "/community", "add " .. math.floor(target * 0.25))
check(broadcasts[1] and broadcasts[1]:find("25%% reached") and broadcasts[1]:find("Kindled Brazier"), "stage broadcast")
check(queried("INSERT INTO `chaos_community_buffs`"), "the window stored")
eq(#X.buffItems(hero, {}), 1, "the stage on the buff bar")
eq(ourXp(hero, mkMonster("Rat"), 1000, 1000), 1100, "the stage's +10% experience")
eq(ourXp(far, mkMonster("Skeleton Warrior"), 1000, 1000), 1430, "stage x Restless Dead")
-- the staff override: Ember Tides and Gilded Week
broadcasts = {}
talks["/community"].onSay(gm, "/community", "modifier ember_tides,gilded_week")
eq(X.week.source, "staff", "override applied")
eq(ChaosEvents.bonus("goblin"), 2, "Gilded Week through the event calendar")
eq(ChaosEvents.dynamic.community_restless_dead, nil, "the old week's events gone")
check(queried("chaos_community_override.-20261005:ember_tides,gilded_week"), "override stored in server_config")
local rw2 = X.riftWorld(hero)
check(rw2 and rw2.extraMods == 1 and rw2.rewardMult == 15, "Ember Tides reaches the rift hook")
talks["/community"].onSay(gm, "/community", "modifier bloodmoon,ambush_season")
eq(X.week.source, "staff", "two of one group refused: the override stays")
talks["/community"].onSay(gm, "/community", "modifier auto")
eq(X.week.source, "seed", "back to the seed")
eq(ChaosEvents.bonus("goblin"), 1, "Gilded Week gone")
talks["/community"].onSay(hero, "/community", "add 999999")
eq(K.stageAt(cfg, X.goals[0].progress), 1, "players cannot use the staff command")
-- adding points unlocks stages for the whole realm: a gamemaster (group 4) is refused, only an administrator may
local before = X.goals[0].progress
local gm4 = mkPlayer("Gamemaster4", 901, 4)
function gm4:sendCancelMessage(text) self.cancel = text end
talks["/community"].onSay(gm4, "/community", "add 999999")
eq(X.goals[0].progress, before, "a gamemaster cannot add community points")
-- flush, logout
queries = {}
registry.ChaosCommunityKill.onKill(hero, mkMonster("Skeleton Warrior"))
X.flush()
check(queried("INSERT INTO `chaos_community_contrib`.-501.-'Hero'"), "contributions written")
check(queried("INSERT INTO `chaos_community_goal`"), "the goal written")
registry.ChaosCommunityLogout.onLogout(far)
eq(X.entries[502], nil, "logout forgets the entry")
-- the period ends: next Monday 06:00; the rows of the old period rank the rewards
queries, broadcasts = {}, {}
selectRows = function(qq)
	if qq:find("FROM `chaos_community_contrib` WHERE `period` = 20261005 AND `realm` = 0") then
		return {{player_id = 501, name = "Hero", points = 1018, updated_at = 10},
			{player_id = 503, name = "Bryn", points = 4000, updated_at = 20}}
	end
	if qq:find("SELECT `progress` FROM `chaos_community_goal` WHERE `period` = 20261005") then
		return {{progress = math.floor(target * 0.3)}}
	end
	return {}
end
clock = at(2026, 10, 12, 6, 1)
globals.ChaosCommunityThink.onThink(5000)
eq(X.goals[0].period, 20261012, "a new period")
eq(X.goals[0].progress, 0, "starts at 0")
check(queried("UPDATE `chaos_community_contrib` SET `place` = 1, `token` = 1 WHERE `period` = 20261005 AND `player_id` = 503"),
	"Bryn: first place and the token")
check(queried("UPDATE `chaos_community_contrib` SET `place` = 2, `token` = 0 WHERE `period` = 20261005 AND `player_id` = 501"),
	"Hero: second place, under the token threshold")
check(queried("SET `finished` = 1"), "the old period finished")
local ended = false
for _, b in ipairs(broadcasts) do if b:find("ended at 30%%") and b:find("Bryn") then ended = true end end
check(ended, "the end broadcast names the top")
eq(X.week.key, 20261012, "a new week too")
-- the rewards at the next login
selectRows = function(qq)
	if qq:find("`rewarded` = 0") then
		return {{period = 20261005, place = 1, token = 1, points = 4000}}
	end
	if qq:find("`place` > 0 ORDER BY") then
		return {{period = 20261005, place = 1}}
	end
	return {}
end
local bryn = mkPlayer("Bryn", 503, 1)
registry.ChaosCommunityLogin.onLogin(bryn)
eq(bryn.items[29856], 2, "token: 2 Orbs of Upheaval")
eq(bryn.items[29857], 1, "token: an Orb of Fate")
check(queried("SET `rewarded` = 1 WHERE `period` = 20261005 AND `player_id` = 503"), "marked as rewarded")
local tt = titleSources.community(bryn)
check(tt and tt.text == cfg.goal.rewards.title, "the title on the name plate")
check(titleSources.community(hero) == nil, "no title for Hero (not logged in again)")

print = print_
check(logged[1] and logged[1]:find("Great Brazier stands at 103, 98, 7", 1, true), "startup log")
print(string.format("community_test: %s (%d checks)", failures == 0 and "OK" or (failures .. " FAILED"), count))
if failures > 0 then
	os.exit(1)
end
