-- Run from the server/ folder: luajit tests/records_test.lua (and lua5.3; CI runs both)
-- Competitive records (records_core.lua with the real records_config.lua): the catalogue, periods and resets, party
-- size brackets, the anti-abuse validation, merging, ranking and ties, the weekly awards (titles, badge), realm firsts
-- and the texts.
dofile("data/scripts/chaos/records_core.lua")
local K = ChaosRecordsCore
local cfg = dofile("data/scripts/chaos/records_config.lua")

local function eq(a, b, m)
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function t(y, mo, d, hh, mi)
	return os.time({year = y, month = mo, day = d, hour = hh, min = mi or 0, sec = 0})
end

-- ---------------------------------------------------------------- catalogue
local src = {
	worldBosses = {"Kaelgor the Infernal Warlord", "Skaldra the Rime Queen", "The Rotmother"},
	omens = {{key = "bloodmoon", name = "Bloodmoon", boss = "Sangrith the Bloodmoon Herald"},
		{key = "storm", name = "Stormcall", boss = "Thalcyra the Stormbound Seer"}},
	ascended = {{key = "bloodmoon", name = "Bloodmoon", boss = "Ascended Sangrith"},
		{key = "cinder", name = "Cinderheart", boss = "Ysgrath the Cinderheart", final = true}},
	guildBoss = "Gorvath the Banner-Eater",
	trials = {{key = "normal", name = "Normal"}, {key = "cruel", name = "Cruel"}, {key = "merciless", name = "Merciless"}},
	dungeons = {{id = 1, name = "Goblin Warren"}, {id = 2, name = "Hollow Vault"}, {id = 3, name = "Drowned Crypt"}}
}
local boards, byKey = K.catalogue(cfg, src)
eq(boards[1].cat, "bosses", "bosses first (category order)")
eq(#byKey.wb_time.variants, 3, "one variant per world boss")
eq(byKey.wb_time.variants[1].key, "kaelgor", "world boss variant key from the short name")
eq(byKey.wb_time.variants[3].short, "Rotmother", "'The' dropped")
eq(byKey.omen.variants[2].key, "storm", "omen variant keys are the omen kinds")
eq(#byKey.omen.sizes, 3, "solo / 2-3 / 4-5")
eq(byKey.ascended.variants[2].short, "Cinderheart", "the final boss keeps its name")
eq(byKey.guildboss.name, "Gorvath the Banner-Eater", "guild boss named after the boss")
eq(byKey.dungeon_1 ~= nil and byKey.dungeon_3 ~= nil, true, "one board per dungeon")
eq(byKey.dungeon_2, nil, "the Hollow Vault has its own board")
eq(#byKey.hollowvault.variants, 6, "six difficulties")
eq(byKey.hollowvault.variants[4].name, "Difficulty 4", "difficulty names")
eq(#byKey.tower_time.variants, 3, "floors 50 / 100 / 120")
eq(#byKey.rift_band.variants, 4, "three bands and tier 15")
eq(byKey.trials.variants[3].key, "merciless", "trial tiers")
eq(#byKey.arena.variants, 3, "arena brackets")
local seen = {}
for _, b in ipairs(boards) do
	eq(seen[b.key], nil, "board keys are unique: " .. b.key)
	seen[b.key] = true
	eq(b.mode == "min" or b.mode == "max" or b.mode == "add", true, "mode of " .. b.key)
end
local empty = K.catalogue(cfg, {})
for _, b in ipairs(empty) do
	eq(b.key ~= "wb_time" and b.key ~= "omen", true, "a board without its content list is left out: " .. b.key)
end

-- ---------------------------------------------------------------- periods and resets (2026-10-12 is a Monday)
local k = K.periodKeys(t(2026, 10, 14, 12), 6, nil)
eq(k.week, "w20261012", "week key")
eq(k.season, "q20264", "no server season: the calendar quarter")
eq(k.all, "all", "all time")
eq(K.periodKeys(t(2026, 10, 12, 5, 59), 6).week, "w20261005", "Monday 05:59 is last week")
eq(K.periodKeys(t(2026, 10, 12, 6, 0), 6).week, "w20261012", "Monday 06:00: the weekly reset")
eq(K.periodKeys(t(2026, 12, 1, 12), 6, {id = 1, name = "Season of Ash"}).season, "s1", "a running season")
eq(K.seasonKey(nil, t(2027, 1, 2, 12)), "q20271", "new quarter, new season")
eq(K.seasonName("q20264"), "Q4 2026", "quarter name")
eq(K.seasonName("s1", {id = 1, name = "Season of Ash"}), "Season of Ash", "season name")
eq(K.nextReset(t(2026, 10, 14, 12), 6), t(2026, 10, 19, 6), "next reset")

-- ---------------------------------------------------------------- slots and party sizes
eq(K.slot("omen", "storm", "solo"), "omen|storm|solo", "slot")
eq(K.slot("raid"), "raid|-|-", "slot without filters")
local b, v, s = K.parseSlot("omen|storm|small")
eq(b .. v .. s, "omenstormsmall", "parse")
eq(select(2, K.parseSlot("raid|-|-")), nil, "no variant")
eq(K.sizeOf(byKey.omen, 1, cfg), "solo", "1 -> solo")
eq(K.sizeOf(byKey.omen, 3, cfg), "small", "3 -> 2-3")
eq(K.sizeOf(byKey.omen, 5, cfg), "party", "5 -> 4-5")
eq(K.sizeOf(byKey.omen, 6, cfg), nil, "6: over the limit")
eq(K.sizeOf(byKey.omen, 0, cfg), nil, "nobody")
eq(K.sizeOf(byKey.raid, 15, cfg), "-", "raid up to 15")
eq(K.sizeOf(byKey.raid, 16, cfg), nil, "raid over 15")
eq(K.bandOf(cfg, 7), "b2", "tier 7 band")
eq(K.bandOf(cfg, 15), "t15", "tier 15")
eq(K.towerVariant(cfg, 100), "f100", "floor 100")
eq(K.towerVariant(cfg, 99), nil, "floor 99")

-- ---------------------------------------------------------------- validation
local function run(over)
	local r = {board = "omen", variant = "storm", value = 300, members = {{guid = 1, name = "A", group = 1, voc = 4}}}
	for key, val in pairs(over or {}) do
		r[key] = val
	end
	return r
end
local ok, size = K.validate(run(), byKey.omen, cfg)
eq(ok, true, "valid solo run")
eq(size, "solo", "its bracket")
eq(select(2, K.validate(run({debug = true}), byKey.omen, cfg)), "debug run", "debug runs never count")
eq(select(2, K.validate(run({members = {{guid = 1, group = 1}, {guid = 2, group = 4}}}), byKey.omen, cfg)),
	"staff in the group", "a GM in the party voids the run")
eq(select(2, K.validate(run({members = {{guid = 1, group = 1, mc = true}}}), byKey.omen, cfg)), "multi-client character",
	"multi-client")
eq(select(2, K.validate(run({variant = "nope"}), byKey.omen, cfg)), "unknown variant", "unknown boss")
eq(select(2, K.validate(run({variant = "x"}), byKey.raid, cfg)), "variant on a board without variants", "stray variant")
eq(select(2, K.validate(run({size = 6}), byKey.omen, cfg)), "party size outside the board's limits", "party of 6")
eq(select(2, K.validate(run({value = 5}), byKey.omen, cfg)), "time below the minimum", "a 5 s kill")
eq(select(2, K.validate(run({value = 0}), byKey.omen, cfg)), "no value", "no time")
eq(select(2, K.validate(run({value = 0 / 0}), byKey.omen, cfg)), "no value", "NaN")
eq(select(2, K.validate(run({members = {}}), byKey.omen, cfg)), "nobody", "no members")
eq(select(2, K.validate(run(), nil, cfg)), "unknown board", "unknown board")
local hv = run({board = "hollowvault", variant = "d3", difficulty = 3, difficultyStart = 2})
eq(select(2, K.validate(hv, byKey.hollowvault, cfg)), "difficulty changed during the run", "same difficulty")
hv.difficultyStart = 3
eq(K.validate(hv, byKey.hollowvault, cfg), true, "same difficulty counts")
local rt = run({board = "rift_tier", value = 3})
rt.variant = nil
eq(K.validate(rt, byKey.rift_tier, cfg), true, "max boards take small values")

-- ---------------------------------------------------------------- merge
local e = K.merge(nil, 300, "min", 100)
eq(e.value, 300, "first time")
local _, changed = K.merge(e, 320, "min", 200)
eq(changed, false, "slower: kept")
eq(e.at, 100, "at unchanged")
_, changed = K.merge(e, 300, "min", 300)
eq(changed, false, "a tie keeps the earlier time")
eq(e.at, 100, "tie keeps at")
_, changed = K.merge(e, 250, "min", 400)
eq(e.value .. "/" .. e.at, "250/400", "faster replaces")
eq(e.count, 4, "every run counted")
local m = K.merge(nil, 7, "max", 1)
K.merge(m, 5, "max", 2)
eq(m.value, 7, "max keeps the best")
local a = K.merge(nil, 1, "add", 1)
K.merge(a, 1, "add", 2)
eq(a.value .. "/" .. a.at, "2/2", "add sums")

-- ---------------------------------------------------------------- ranking and ties
local ranked = K.rank({
	{guid = 5, value = 300, at = 50}, {guid = 2, value = 280, at = 90}, {guid = 3, value = 300, at = 40},
	{guid = 4, value = 0, at = 1}, {guid = 1, value = 300, at = 40}}, "min")
eq(#ranked, 4, "zero values left out")
eq(ranked[1].guid, 2, "fastest first")
eq(ranked[2].guid, 1, "tie: same time, lower guid")
eq(ranked[3].guid, 3, "tie at 40")
eq(ranked[4].guid, 5, "tie: the later time last")
eq(ranked[4].rank, 4, "ranks never shared")
local hi = K.rank({[10] = {value = 9, at = 5}, [11] = {value = 12, at = 9}, [12] = {value = 9, at = 3}}, "max")
eq(hi[1].guid, 11, "max: highest first (map input)")
eq(hi[2].guid, 12, "max tie: earlier first")
local cls = K.filterClass({{guid = 1, voc = 4, value = 1}, {guid = 2, voc = 5, value = 2}, {guid = 3, voc = 8, value = 3}}, {4, 8})
eq(#cls, 2, "class filter")
eq(cls[2].guid .. "/" .. cls[2].rank, "3/2", "ranked again in the class")
eq(K.find(ranked, 3).rank, 3, "own rank")
eq(K.isRecord(300, 280, "min"), true, "faster beats the record")
eq(K.isRecord(300, 300, "min"), false, "a tie is no record")
eq(K.isRecord(nil, 280, "min"), false, "the first entry is no beaten record")
eq(K.isRecord(14, 15, "max"), true, "higher tier")

-- ---------------------------------------------------------------- weekly awards, titles, badge
local catOf = function(slot)
	return byKey[K.parseSlot(slot)].cat
end
local awards = K.awards({["omen|storm|solo"] = ranked, ["tower_floor|-|-"] = hi}, 3, catOf)
eq(#awards, 6, "top 3 of each slot")
eq(awards[1].slot, "omen|storm|solo", "sorted slots")
eq(awards[4].cat, "tower", "category of the slot")
local held = K.held(awards)
eq(held[2].cats.bosses, 1, "1st on a boss board")
eq(held[11].cats.tower, 1, "1st on the tower")
eq(held[5], nil, "4th holds nothing")
local titles = K.titlesOf(cfg, held[2], nil, 1000)
eq(#titles, 1, "one category title")
eq(titles[1].text, "Bossrunner", "the category title")
eq(titles[1].key, "records:bosses", "stable title key")
local firsts = {{target = "ascended:cinder", short = "Cinderheart", at = 5}}
titles = K.titlesOf(cfg, nil, firsts)
eq(titles[1].text, "First: Cinderheart", "realm first title")
eq(K.firstTitle(cfg, "Thalcyra the Stormbound Seer"), "First: Thalcyra the", "cut at a word within 24 characters")
eq(#K.firstTitle(cfg, string.rep("x", 40)) <= 24, true, "never above 24")

-- ---------------------------------------------------------------- realm firsts
local tgt, short = K.firstTarget(byKey.ascended, "cinder")
eq(tgt .. "/" .. short, "ascended:cinder/Cinderheart", "one first per Ascended")
tgt, short = K.firstTarget(byKey.guildboss, nil)
eq(tgt .. "/" .. short, "guildboss/Gorvath", "guild boss first")
tgt = K.firstTarget(byKey.hollowvault, "d4")
eq(tgt, "hollowvault", "Hollow Vault: one first whatever the difficulty")
tgt = K.firstTarget(byKey.dungeon_1, "d2")
eq(tgt, "dungeon_1", "a dungeon: one first")
eq(K.firstTarget(byKey.tower_floor, nil), nil, "no realm first for the tower")
tgt, short = K.firstTarget(byKey.trials, "cruel", {first = {key = "warrior.cruel", short = "Gauntlet Champion"}})
eq(tgt .. "/" .. short, "trials:warrior.cruel/Gauntlet Champion", "trials: one first per family and tier")

-- the Realm Firsts list names the boss in full (live test 2026-10-14: "Skaldra" instead of the full name)
local wbTarget, wbShort = K.firstTarget(byKey.wb_time, "skaldra")
eq(wbShort, "Skaldra", "the stored short name (titles)")
eq(K.firstDisplay(byKey, wbTarget, wbShort), "Skaldra the Rime Queen", "list: the world boss's full name")
eq(K.firstDisplay(byKey, "ascended:cinder", "Cinderheart"), select(3, K.firstTarget(byKey.ascended, "cinder")),
	"list: the Ascended as announced")
eq(K.firstDisplay(byKey, "guildboss", "Gorvath"), byKey.guildboss.name, "list: a board without variants")
eq(K.firstDisplay(byKey, "trials:warrior.cruel", "Gauntlet Champion"),
	select(3, K.firstTarget(byKey.trials, "cruel", {first = {key = "warrior.cruel", short = "Gauntlet Champion"}})),
	"list: a trials first as announced")
eq(K.firstDisplay(byKey, "gone:x", "Old Boss"), "Old Boss", "list: an unknown board keeps the stored name")

-- ---------------------------------------------------------------- texts
eq(K.valueText(75, "time"), "1:15", "m:ss")
eq(K.valueText(3725, "time"), "1:02:05", "h:mm:ss")
eq(K.valueText(4512, "pct"), "45.12%", "share")
eq(K.valueText(14), "14", "plain")
eq(K.recordText(byKey.omen, "storm", "small", 245, {{name = "Zed"}, {name = "Ann"}}, 300),
	"New record! Omen Guardians, Thalcyra the Stormbound Seer, 2-3: 4:05 by Ann, Zed (was 5:00).", "record text")
eq(K.firstText(select(3, K.firstTarget(byKey.ascended, "cinder")), {{name = "Ann"}}, "Season of Ash"),
	"Realm first of Season of Ash! Ann is the first to defeat Ysgrath the Cinderheart.", "first text")
local many = {}
for i = 1, 8 do
	many[i] = {name = "P" .. i}
end
eq(K.names(many), "P1, P2, P3, P4, P5, 3 more", "long groups shortened")

-- ---------------------------------------------------------------- records.lua on a mocked engine
do
	local queries, broadcasts, sent, registered, titleSources, frameSources = {}, {}, {}, {}, {}, {}
	MESSAGE_EVENT_ADVANCE, MESSAGE_INFO_DESCR = 19, 22
	json = {encode = function(x) return x end}
	dofile("data/scripts/chaos/chaos_constants.lua")
	db = {query = function(q) queries[#queries + 1] = q return true end,
		asyncQuery = function(q) queries[#queries + 1] = q return true end,
		storeQuery = function() return nil end,
		escapeString = function(x) return "'" .. tostring(x):gsub("'", "''") .. "'" end}
	result = {}
	Chaos.isMultiClient = function(p) return p.mc == true end
	local best -- the all-time best the mocked DB answers
	local people = {[1] = {name = "Ann", group_id = 1, vocation = 4}, [2] = {name = "Bob", group_id = 1, vocation = 8},
		[9] = {name = "Gm", group_id = 5, vocation = 1}}
	Chaos.select = function(q)
		if q:find("FROM `players` WHERE `id` = ", 1, true) then
			local p = people[tonumber(q:match("`id` = (%d+)"))]
			return p and {p} or {}
		elseif q:find("period` = 'all' AND `value` > 0", 1, true) then
			return best and {{value = best}} or {}
		end
		return {}
	end
	local function event()
		return function(name)
			local e = {name = name}
			function e:register() registered[name] = self end
			function e:interval() end
			function e:separator() end
			function e:type() end
			return e
		end
	end
	CreatureEvent, GlobalEvent, TalkAction = event(), event(), event()
	ChaosTitles = {register = function(src, fn) titleSources[src] = fn end,
		registerFrame = function(src, fn) frameSources[src] = fn end}
	local players = {}
	local function mkPlayer(guid, name, group, voc)
		local p = {}
		function p:getGuid() return guid end
		function p:getName() return name end
		function p:getId() return guid + 100 end
		function p:getGroup() return {getId = function() return group or 1 end, getAccess = function() return (group or 1) >= 4 end} end
		function p:getVocation() return {getId = function() return voc or 4 end} end
		function p:sendExtendedOpcode(op, msg) sent[#sent + 1] = {op = op, msg = msg} end
		function p:sendTextMessage() end
		players[#players + 1] = p
		return p
	end
	Game = {getPlayers = function() return players end, broadcastMessage = function(text) broadcasts[#broadcasts + 1] = text end}
	Player = function(x)
		for _, p in ipairs(players) do
			if p:getId() == x or p:getName() == x then
				return p
			end
		end
		return nil
	end
	Vocation = function() return {getName = function() return "Knight" end} end
	-- the content scripts the hooks wrap
	ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
	ChaosUberConfig = dofile("data/scripts/chaos/uber_config.lua")
	Chaos.guildBossConfig = dofile("data/scripts/chaos/guildboss_config.lua")
	Chaos.trials = dofile("data/scripts/chaos/trials_config.lua")
	local calls = {}
	ChaosWorldBoss = {state = {fightStart = os.time() - 400},
		computeRewards = function() calls.wb = (calls.wb or 0) + 1 return "rewards" end}
	ChaosRiftCore = {atlasSealed = function() calls.sealed = true end}
	ChaosExclusives = {bossKill = function() return true end}
	ChaosLeaderboard.record = function(board) return board ~= "nope" and {value = 1} or nil end
	ChaosTower = {recordRun = function() end}
	ChaosAchievements = {set = function() end}
	ChaosAscended = {runs = {}}
	ChaosTrials = {runs = {}}
	dofile("data/scripts/chaos/records.lua")
	local R = ChaosRecords
	eq(R.byKey.wb_time ~= nil and #R.byKey.wb_time.variants, 5, "catalogue from the five world bosses")
	eq(#R.byKey.omen.variants, 3, "three omens")
	eq(#R.byKey.ascended.variants, 4, "three Ascended and the Cinderheart")
	eq(titleSources.records ~= nil and frameSources.records ~= nil, true, "title and frame sources registered")
	eq(registered.ChaosRecordsExtended ~= nil, true, "protocol event")

	local ann, bob = mkPlayer(1, "Ann"), mkPlayer(2, "Bob", 1, 8)
	local function upserts(slot)
		local n = 0
		for _, q in ipairs(queries) do
			if q:find("INSERT INTO `chaos_records`", 1, true) and (not slot or q:find("'" .. slot .. "'", 1, true)) then
				n = n + 1
			end
		end
		return n
	end
	-- world boss: the original runs and returns, fight time and damage shares go in
	eq(ChaosWorldBoss.computeRewards({{guid = 1, name = "Ann", damage = 750}, {guid = 2, name = "Bob", damage = 250}}, {},
		{name = "Kaelgor the Infernal Warlord"}), "rewards", "the wrapped function returns its value")
	eq(calls.wb, 1, "the original ran once")
	eq(upserts("wb_time|kaelgor|-"), 6, "both players x three periods")
	eq(upserts("wb_share|kaelgor|-"), 6, "both shares")
	local shareQ
	for _, q in ipairs(queries) do
		if q:find("wb_share", 1, true) and q:find(", 1, 7500,", 1, true) then
			shareQ = q
		end
	end
	eq(shareQ ~= nil, true, "Ann's share 75.00%")
	eq(broadcasts[1], "Realm first of Q" .. (math.floor((os.date("*t").month - 1) / 3) + 1) .. " " .. os.date("*t").year ..
		"! Ann, Bob are the first to defeat Kaelgor the Infernal Warlord.", "realm first broadcast")
	eq(#R.titlesOf(ann), 1, "Ann holds the realm first title")
	-- the Realm Firsts list (rfirsts) names the boss in full, the title keeps the short name
	local sentBefore = #sent
	R.sendFirsts(ann)
	local msg = #sent > sentBefore and sent[#sent].msg or {}
	eq(msg.action, "rfirsts", "rfirsts sent")
	local row = msg.data and msg.data.rows and msg.data.rows[1] or {}
	eq(row.name, "Kaelgor the Infernal Warlord", "the list names the boss in full")
	eq(R.titlesOf(ann)[1].text, "First: Kaelgor", "the title keeps the short name")
	-- the same boss again: no second realm first
	local before = #broadcasts
	ChaosWorldBoss.computeRewards({{guid = 1, name = "Ann", damage = 1}}, {}, {name = "Kaelgor the Infernal Warlord"})
	for i = before + 1, #broadcasts do
		eq(broadcasts[i]:find("Realm first", 1, true), nil, "one realm first per boss and season")
	end
	eq(broadcasts[#broadcasts], "New record! World Boss Damage, Kaelgor the Infernal Warlord: 100.00% by Ann (was 75.00%).",
		"a better damage share is a new record")
	-- the ordering of the UPDATE: everything that compares with the old value before `value` itself
	local q = queries[#queries]
	eq(q:find("`at` = IF", 1, true) < q:find("`value` = IF", 1, true), true, "value assigned last")
	-- a staff character in the group: nothing recorded
	queries = {}
	ChaosRiftCore.atlasSealed({tier = 9, secs = 300, guids = {1, 9}})
	eq(calls.sealed, true, "the original atlasSealed ran")
	eq(upserts(), 0, "a GM in the party voids the run")
	-- a sealed tier 15 rift: highest tier, the tier 15 band (2-3 bracket)
	ChaosRiftCore.atlasSealed({tier = 15, secs = 600, guids = {1, 2}})
	eq(upserts("rift_tier|-|-"), 6, "highest tier for both")
	eq(upserts("rift_band|t15|small"), 6, "fastest tier 15, 2-3")
	-- an Omen guardian
	ChaosRiftCore.atlasSealed({tier = 12, omen = "storm", secs = 240, guids = {1}})
	eq(upserts("omen|storm|solo"), 3, "omen solo")
	-- a beaten all-time record is announced
	best = 500
	R.best = {}
	before = #broadcasts
	ChaosRiftCore.atlasSealed({tier = 12, omen = "storm", secs = 230, guids = {1}})
	eq(broadcasts[#broadcasts], "New record! Omen Guardians, Thalcyra the Stormbound Seer, Solo: 3:50 by Ann (was 8:20).",
		"record broadcast")
	best = nil
	-- the leaderboard sources
	queries = {}
	ChaosLeaderboard.record("descent", ann, 9)
	eq(upserts("descent|-|-"), 3, "Descent depth")
	ChaosLeaderboard.record("arena2v2", ann, 1650)
	eq(upserts("arena|2v2|-"), 3, "arena 2v2 rating")
	ChaosLeaderboard.record("nope", ann, 3)
	eq(upserts("nope"), 0, "a record the leaderboard refused is not taken")
	-- the Ascended: once per run, whoever is the first rewarded player
	local run = {players = {[101] = {guid = 1, name = "Ann"}, [102] = {guid = 2, name = "Bob"}}, size = 2, secs = 420}
	ChaosAscended.runs[1] = run
	ChaosExclusives.bossKill(ann, "ascended_storm")
	ChaosExclusives.bossKill(bob, "ascended_storm")
	eq(upserts("ascended|storm|small"), 6, "the run once, both members")
	-- the tower climb and the trials
	R.towerFloor({[101] = {id = 101, guid = 1}}, 50, 1200)
	eq(upserts("tower_time|f50|solo"), 3, "floor 50")
	R.towerFloor({[101] = {id = 101, guid = 1}}, 51, 1210)
	eq(upserts("tower_time|f51"), 0, "floor 51 is no board")
	ChaosTrials.runs[101] = {tierDef = {time = 480}, deadline = os.time() * 1000 + 180000, famKey = "warrior",
		fam = {boss = {name = "Gauntlet Champion"}}}
	ChaosAchievements.set(ann, "trial_tier_2", 1)
	eq(upserts("trials|cruel|solo"), 3, "trial clear")
	eq(broadcasts[#broadcasts]:find("defeat Gauntlet Champion (Cruel).", 1, true) ~= nil, true, "trial first names the boss")
	-- debug: a shifted clock
	R.offset = 86400
	eq(select(2, R.submit({board = "descent", value = 3, members = {ann}, size = 1})), "debug run", "shifted clock")
	R.offset = 0
	-- dungeons: the pending hook
	eq(R.dungeonClear({dungeonId = 4, title = "Hollow Vault", difficulty = 2, difficultyStart = 2, ms = 610000,
		members = {{guid = 1}}}), true, "Hollow Vault clear")
	eq(R.dungeonClear({dungeonId = 4, title = "Hollow Vault", difficulty = 3, difficultyStart = 2, ms = 610000,
		members = {{guid = 1}}}), false, "difficulty raised mid-run")
	-- the generated dungeon's real title has a leading "The" (areagen_config.lua): still the Hollow Vault board
	eq(ChaosRecordsCore.isHollowVault(cfg, "The Hollow Vault"), true, "'The Hollow Vault' is the Hollow Vault")
	eq(ChaosRecordsCore.isHollowVault(cfg, "Bones Dungeon"), false, "another dungeon is not")
	-- the client view and meta
	sent = {}
	R.sendMeta(ann)
	local cats, metaMsg = 0, nil
	for _, m in ipairs(sent) do
		if m.msg.action == "rcat" then
			cats = cats + 1
			eq(#m.msg.data.boards <= 6, true, "a meta part holds at most 6 boards")
		elseif m.msg.action == "rmeta" then
			metaMsg = m.msg.data
		end
	end
	eq(metaMsg.parts, cats, "every part announced")
	eq(#metaMsg.periods, 3, "week / season / all time")
	local v = R.view(ann, {board = "omen", variant = "storm", size = "party", period = "all"})
	eq(v.board .. v.variant .. v.size .. v.period, "omenstormpartyall", "view filters")
	v = R.view(ann, {board = "omen", variant = "nope", size = "bad", period = "x"})
	eq(v.variant .. v.size .. v.period, "bloodmoonsoloweek", "bad filters fall back to the first")
	-- weekly awards: titles and the badge
	R.held = {week = 20261005, byGuid = K.held({{slot = "omen|storm|solo", cat = "bosses", rank = 2, guid = 1}})}
	eq(R.badgeOf(ann), "laurel", "badge for a weekly top 3")
	eq(R.badgeOf(bob), nil, "no badge")
	local hasCat = false
	for _, tt in ipairs(R.titlesOf(ann)) do
		hasCat = hasCat or tt.text == "Bossrunner"
	end
	eq(hasCat, true, "category title")
end

print("records_test: all passed")
