-- Run from the server/ folder: luajit tests/metrics_test.lua (or lua5.3; CI runs both)
-- Progress metrics (O253): level bands, buckets, the in-memory counters and their flush SQL, the churn SQL and rows,
-- area naming, the milestone mask, the exclusion of tester bots and staff, privacy (no name reaches a counter), and
-- metrics.lua against a mocked engine (login -> death -> advance -> logout -> flush -> shutdown). All data is synthetic.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
SKILL_LEVEL = 8
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/metrics_config.lua")
dofile("data/scripts/chaos/metrics_core.lua")
local M = ChaosMetrics

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

-- ---------------------------------------------------------------- bands
local e = cfg.bands
eq(M.bandOf(1, e), "1-5", "level 1")
eq(M.bandOf(5, e), "1-5", "level 5")
eq(M.bandOf(6, e), "6-10", "level 6")
eq(M.bandOf(30, e), "26-30", "level 30")
eq(M.bandOf(31, e), "31-40", "level 31")
eq(M.bandOf(900, e), "701-900", "level 900")
eq(M.bandOf(901, e), "901+", "level 901")
eq(M.bandOf(5000, e), "901+", "level 5000")
eq(M.bandOf(0, e), "1-5", "level 0 counts as 1")
eq(M.bandOf("12", e), "11-15", "a numeric string")
eq(M.bandOf(7, {10, 20}), "1-10", "custom edges")
eq(M.bandOf(25, {10, 20}), "21+", "custom edges, open band")
for i = 2, #e do check(e[i] > e[i - 1], "bands ascend at " .. i) end
eq(M.bandCaseSql("`level`", {5, 10}), "CASE WHEN `level` <= 5 THEN 1 WHEN `level` <= 10 THEN 2 ELSE 3 END", "band CASE")

-- ---------------------------------------------------------------- buckets
eq(M.bucketLabel(0, cfg.sessionBuckets), "5", "0 minutes")
eq(M.bucketLabel(5, cfg.sessionBuckets), "5", "5 minutes (upper limit inclusive)")
eq(M.bucketLabel(6, cfg.sessionBuckets), "10", "6 minutes")
eq(M.bucketLabel(480, cfg.sessionBuckets), "480", "480 minutes")
eq(M.bucketLabel(481, cfg.sessionBuckets), "inf", "481 minutes")
eq(M.sessionMinutes(59), 0, "59 s")
eq(M.sessionMinutes(125), 2, "125 s")
eq(M.sessionMinutes(-5), 0, "negative")

-- ---------------------------------------------------------------- who counts
check(M.eligible(1, false, cfg), "a player counts")
check(M.eligible(0, false, cfg), "group 0 counts")
check(not M.eligible(2, false, cfg), "group 2 (staff) does not")
check(not M.eligible(6, false, cfg), "group 6 does not")
check(not M.eligible(1, true, cfg), "a tester bot does not")

-- ---------------------------------------------------------------- names, areas
eq(M.killerName("monster", "Dragon", cfg), "Dragon", "a monster")
eq(M.killerName("monster", "Dragon\n\1x", cfg), "Dragon  x", "control characters cut")
eq(M.killerName("monster", string.rep("a", 100), cfg), string.rep("a", cfg.nameMax), "long names cut")
eq(M.killerName("player", "Aldric", cfg), cfg.killerPlayer, "a player is never named")
eq(M.killerName("summon", "Skeleton", cfg), cfg.killerSummon, "a summon")
eq(M.killerName("other", nil, cfg), cfg.killerOther, "unknown")
eq(M.killerName("monster", "", cfg), cfg.killerOther, "empty monster name")
local spots = {{name = "Ember Caves", x = 100, y = 100, z = 7}, {name = "Frost Hold", x = 150, y = 100, z = 7},
	{name = "Deep Mine", x = 100, y = 100, z = 9}}
eq(M.areaFor({x = 110, y = 95, z = 7}, nil, spots, cfg), "Ember Caves", "near a hunt")
eq(M.areaFor({x = 140, y = 100, z = 7}, nil, spots, cfg), "Frost Hold", "the nearer of two")
eq(M.areaFor({x = 100, y = 100, z = 9}, nil, spots, cfg), "Deep Mine", "same floor only")
eq(M.areaFor({x = 100, y = 100, z = 8}, nil, spots, cfg), "Outside hunts, floor 8", "another floor")
eq(M.areaFor({x = 300, y = 100, z = 7}, nil, spots, cfg), "Outside hunts, floor 7", "too far")
eq(M.areaFor({x = 100, y = 100, z = 7}, "Arena", spots, cfg), "Arena", "an instance wins")
eq(M.areaFor({x = 100, y = 100, z = 7}, nil, nil, cfg), "Outside hunts, floor 7", "no spots")

-- ---------------------------------------------------------------- counters and flush
local st = M.newState()
check(M.add(st, "death_area", "Ember Caves", "6-10", 1, cfg), "add")
M.add(st, "death_area", "Ember Caves", "6-10", 1, cfg)
M.add(st, "death_area", "Ember Caves", "11-15", 1, cfg)
M.add(st, "session1", "10", "", 1, cfg)
eq(st.keys, 3, "three keys")
local rows = M.rows(st)
eq(#rows, 3, "three rows")
eq(rows[1].kind .. rows[1].k1 .. rows[1].k2 .. rows[1].n, "death_areaEmber Caves11-151", "sorted, first row")
eq(rows[2].n, 2, "two deaths summed")
local esc = function(s) return "'" .. s:gsub("'", "''") .. "'" end
local q = M.flushSql(st, "chaos_progress_metrics", esc)
eq(#q, 1, "one statement")
check(q[1]:find("ON DUPLICATE KEY UPDATE `n` = `n` + VALUES(`n`)", 1, true) ~= nil, "adds on duplicate")
check(q[1]:find("('death_area', 'Ember Caves', '6-10', 2)", 1, true) ~= nil, "row text")
eq(st.keys, 0, "state cleared by the flush")
eq(#M.flushSql(st, "t", esc), 0, "an empty state gives no statement")
local big = M.newState()
for i = 1, 450 do M.add(big, "death_monster", "m" .. i, "1-5", 1, cfg) end
eq(#M.flushSql(big, "t", esc), 3, "450 rows in chunks of 200")
local small = M.newState()
local capCfg = {maxKeys = 2}
check(M.add(small, "a", "1", "", 1, capCfg) and M.add(small, "a", "2", "", 1, capCfg), "under the cap")
check(not M.add(small, "a", "3", "", 1, capCfg), "a new key over the cap is dropped")
check(M.add(small, "a", "1", "", 1, capCfg), "an existing key still counts over the cap")
eq(M.setSql({}, "t", esc), nil, "no rows, no set statement")
check(M.setSql({{kind = "churn", k1 = "1-5", k2 = "gone", n = 4}}, "t", esc):find("`n` = VALUES(`n`)", 1, true) ~= nil, "set statement")
check(M.createSql("t"):find("PRIMARY KEY (`kind`, `k1`, `k2`)", 1, true) ~= nil, "create sql")

-- ---------------------------------------------------------------- churn
local sql = M.churnSql(cfg, 2000000, "NOT EXISTS (SELECT 1 FROM `player_storage` ts)")
check(sql:find("`players`.`group_id` <= 1", 1, true) ~= nil, "staff left out in SQL")
check(sql:find("NOT EXISTS", 1, true) ~= nil, "testers left out in SQL")
check(sql:find("`lastlogin` > 0", 1, true) ~= nil, "never-logged-in left out")
check(sql:find("< " .. (2000000 - 14 * 86400), 1, true) ~= nil, "cutoff is churnDays back")
check(sql:find("GROUP BY `band`", 1, true) ~= nil, "aggregated in SQL")
check(not sql:find("`name`", 1, true) and not sql:find("account_id", 1, true) and not sql:find("lastip", 1, true),
	"the churn query never reads a name, account or IP")
local crows = M.churnRows({{band = 1, gone = 7, active = 3}, {band = 3, gone = 1, active = 0}}, cfg, 2000000)
eq(#crows, 2 * (#cfg.bands + 1) + 2, "every band present plus two meta rows")
eq(crows[1].k1 .. crows[1].k2 .. crows[1].n, "1-5gone7", "band 1 gone")
eq(crows[2].k1 .. crows[2].k2 .. crows[2].n, "1-5active3", "band 1 active")
eq(crows[3].n, 0, "an empty band is 0")
eq(crows[5].k1 .. crows[5].k2 .. crows[5].n, "11-15gone1", "band 3 gone")
eq(crows[#crows - 1].k1 .. crows[#crows - 1].n, "churn_at2000000", "meta churn_at")
eq(crows[#crows].k1 .. crows[#crows].n, "churn_days14", "meta churn_days")

-- ---------------------------------------------------------------- milestones
local c, mask = M.milestonesCrossed(9, 10, 0, cfg)
eq(#c, 1, "10 crossed"); eq(c[1], 10, "milestone 10"); eq(mask, 1, "bit 1")
c, mask = M.milestonesCrossed(9, 10, mask, cfg)
eq(#c, 0, "10 counts once"); eq(mask, 1, "mask unchanged")
c, mask = M.milestonesCrossed(10, 9, mask, cfg)
eq(#c, 0, "a level lost counts nothing")
c, mask = M.milestonesCrossed(20, 60, mask, cfg)
eq(#c, 2, "a jump past 25 and 50"); eq(c[1], 25, "25 first"); eq(c[2], 50, "then 50"); eq(mask, 7, "bits 1-3")
eq(M.maskAtLogin(30, 0, cfg), 3, "at login a level 30 character has 10 and 25 recorded silently")
eq(M.maskAtLogin(1, 0, cfg), 0, "a new character has none")
eq(M.maskAtLogin(500, 0, cfg), 31, "all five")
c, mask = M.milestonesCrossed(1, 5, -1, cfg)
eq(#c, 0, "an unset storage (-1) reads as 0"); eq(mask, 0, "mask 0")

-- ---------------------------------------------------------------- the engine file against a mock
local registry = {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) self.t = t end
	function o:register() registry[name] = self end
	return o
end
function GlobalEvent(name)
	local o = {name = name}
	function o:type() end
	function o:interval(i) self.i = i end
	function o:register() registry[name] = self end
	return o
end
local queries, tbl = {}, {}
local function apply(q, replace)
	q = q:gsub("\\'", "\2") -- an escaped quote
	for kind, k1, k2, v in q:gmatch("%('([^']*)', '([^']*)', '([^']*)', (%d+)%)") do
		local key = (kind .. "|" .. k1 .. "|" .. k2):gsub("\2", "'")
		tbl[key] = replace and tonumber(v) or (tbl[key] or 0) + tonumber(v)
	end
end
local playersOnline = {onlinetime = {[8] = 7200}}
db = {}
function db.escapeString(s) return "'" .. s:gsub("'", "\\'") .. "'" end
function db.query(q)
	queries[#queries + 1] = q
	if q:find("^INSERT") then apply(q, q:find("`n` = VALUES", 1, true) ~= nil) end
	return true
end
db.asyncQuery = db.query
local results, rid = {}, 0
function db.storeQuery(q)
	queries[#queries + 1] = q
	local list
	local guid = q:match("SELECT `onlinetime` AS `t` FROM `players` WHERE `id` = (%d+)")
	if guid then
		list = {{t = playersOnline.onlinetime[tonumber(guid)] or 0}}
	elseif q:find("GROUP BY `band`", 1, true) then
		list = {{band = 1, gone = 5, active = 2}, {band = 2, gone = 1, active = 1}}
	else
		error("unexpected select " .. q)
	end
	rid = rid + 1
	results[rid] = {list = list, i = 1}
	return rid
end
result = {
	getNumber = function(r, col) return results[r].list[results[r].i][col] end,
	getString = function(r, col) return results[r].list[results[r].i][col] end,
	next = function(r) results[r].i = results[r].i + 1 return results[r].i <= #results[r].list end,
	free = function(r) results[r] = nil end,
}
local clock = 1000000
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return clock end
local function mk(def)
	local c = def
	c.events, c.storage = {}, c.storage or {}
	function c:getId() return self.id end
	function c:getGuid() return self.guid end
	function c:getName() return self.name end
	function c:isPlayer() return self.player == true end
	function c:isMonster() return not self.player end
	function c:getMaster() return self.master end
	function c:getLevel() return self.level end
	function c:getPosition() return self.pos end
	function c:getGroup() local g = self.group return {getId = function() return g end} end
	function c:getLastLoginSaved() return self.lastLogin end
	function c:registerEvent(ev) self.events[ev] = true end
	function c:getStorageValue(k) return self.storage[k] or -1 end
	function c:setStorageValue(k, v) self.storage[k] = v end
	return c
end

Chaos.registerInstance("arena", {label = "Arena", inside = function(p) return p.inArena == true end})
Chaos.testerGuids = {}
dofile("data/scripts/chaos/metrics.lua")
for _, name in ipairs({"ChaosMetricsDeath", "ChaosMetricsAdvance", "ChaosMetricsLogin", "ChaosMetricsLogout",
	"ChaosMetricsStartup", "ChaosMetricsThink", "ChaosMetricsShutdown"}) do
	check(registry[name] ~= nil, "registered " .. name)
end
eq(registry.ChaosMetricsThink.i, 60000, "think interval")
ChaosMetrics.spots = {{name = "Ember Caves", x = 100, y = 100, z = 7}}
registry.ChaosMetricsStartup.onStartup()
ChaosMetrics.spots = {{name = "Ember Caves", x = 100, y = 100, z = 7}} -- (startup read no places file)
check(queries[1]:find("CREATE TABLE IF NOT EXISTS `chaos_progress_metrics`", 1, true) ~= nil, "table created at startup")

local newbie = mk({id = 1, guid = 7, name = "Synthetic One", player = true, level = 1, group = 1, lastLogin = 0, pos = {x = 105, y = 100, z = 7}})
local vet = mk({id = 2, guid = 8, name = "Synthetic Two", player = true, level = 40, group = 1, lastLogin = 999, pos = {x = 500, y = 500, z = 7}})
local bot = mk({id = 3, guid = 9, name = "Tester Abc", player = true, level = 8, group = 1, lastLogin = 5, pos = {x = 105, y = 100, z = 7},
	storage = {[Chaos.storage.tester] = 1}})
local gm = mk({id = 4, guid = 10, name = "Staff Morgan", player = true, level = 8, group = 3, lastLogin = 5, pos = {x = 105, y = 100, z = 7}})
local dragon = mk({id = 100, name = "Dragon"})
local wolf = mk({id = 101, name = "War Wolf", master = vet})

for _, p in ipairs({newbie, vet, bot, gm}) do registry.ChaosMetricsLogin.onLogin(p) end
check(newbie.events.ChaosMetricsDeath and newbie.events.ChaosMetricsAdvance and newbie.events.ChaosMetricsLogout, "events registered on the player")
eq(vet.storage[cfg.storage], 3, "login: a level 40 character has 10 and 25 recorded silently")
check(newbie.storage[cfg.storage] == nil, "login: a new character has nothing to mark")
check(bot.storage[cfg.storage] == nil and gm.storage[cfg.storage] == nil, "login: a tester and staff are not touched")
eq(next(ChaosMetrics.sessions) ~= nil and (ChaosMetrics.sessions[3] == nil and ChaosMetrics.sessions[4] == nil), true,
	"no session state for a tester or staff")

local advance = registry.ChaosMetricsAdvance.onAdvance
local death = registry.ChaosMetricsDeath.onDeath
local logout = registry.ChaosMetricsLogout.onLogout
local function key(kind, k1, k2) return tbl[kind .. "|" .. k1 .. "|" .. (k2 or "")] end
local function flushAll()
	clock = clock + cfg.flushSeconds
	registry.ChaosMetricsThink.onThink(60000)
end

-- the new character: 10 minutes to level 12, 40 minutes to level 30, dies, logs out after 45 minutes
clock = clock + 600; newbie.level = 12
advance(newbie, SKILL_LEVEL, 1, 12)
clock = clock + 1800; newbie.level = 30
advance(newbie, SKILL_LEVEL, 12, 30)
eq(newbie.storage[cfg.storage], 3, "mask saved: 10 and 25")
advance(newbie, SKILL_LEVEL, 12, 13) -- not a milestone
advance(newbie, 3, 1, 50) -- a skill, not the level
death(newbie, nil, dragon, nil)
clock = clock + 300
logout(newbie)
-- a level lost and gained again counts once
newbie.level = 24
advance(newbie, SKILL_LEVEL, 24, 26)
-- (the session ended at the logout: nothing more is counted for it)

-- the veteran: a summon kills it, a player kills it, an arena defeat; reaches 50
death(vet, nil, wolf, nil)
death(vet, nil, bot, nil) -- a tester bot as the killer is a player
vet.inArena = true
death(vet, nil, dragon, nil)
vet.inArena = false
vet.level = 60
advance(vet, SKILL_LEVEL, 40, 60)
logout(vet)

-- tester bot and staff: nothing at all
for _, p in ipairs({bot, gm}) do
	death(p, nil, dragon, nil)
	advance(p, SKILL_LEVEL, 8, 30)
	logout(p)
end
death(dragon, nil, nil, nil) -- a monster's death is no business of the player event
check(next(ChaosMetrics.state.counts) ~= nil, "counters in memory")
eq(next(tbl), nil, "nothing written before the flush")
flushAll()
check(next(ChaosMetrics.state.counts) == nil, "memory cleared by the flush")
eq(key("ttl", "10", "10"), 1, "newbie: level 10 after 10 minutes")
eq(key("ttl", "25", "45"), 1, "newbie: level 25 after 40 minutes (bucket 45)")
eq(key("ttl", "50", "180"), 1, "veteran: level 50 after 7200 + 1000 s = 136 min (bucket 180)")
eq(key("ttl", "10", "5"), nil, "no other ttl rows for 10")
eq(key("death_area", "Ember Caves", "26-30"), 1, "death near the hunt")
eq(key("death_monster", "Dragon", "26-30"), 1, "killed by a dragon")
eq(key("death_monster", "Player's summon", "31-40"), 1, "killed by a summon")
eq(key("death_monster", "Player (PvP)", "31-40"), 1, "killed by a player")
eq(key("death_area", "Outside hunts, floor 7", "31-40"), 2, "two deaths outside hunts")
eq(key("death_area", "Arena", "31-40"), 1, "a death in an instance")
eq(key("death_monster", "Dragon", "31-40"), 1, "dragon, arena")
eq(key("session1", "45"), 1, "first session of 2700 s in the 45 minute bucket")
local sessions = 0
for k in pairs(tbl) do if k:find("^session1") then sessions = sessions + 1 end end
eq(sessions, 1, "only the new character has a first session")
local total = 0
for k, v in pairs(tbl) do if k:find("^death_area") then total = total + v end end
eq(total, 4, "4 deaths counted: the tester's and the staff's are left out")

-- a second flush adds, never double counts
local before = key("death_area", "Ember Caves", "26-30")
flushAll()
eq(key("death_area", "Ember Caves", "26-30"), before, "an empty flush changes nothing")
death(newbie, nil, dragon, nil) -- no session any more: not counted
check(next(ChaosMetrics.state.counts) == nil, "a character without a session is not counted")
registry.ChaosMetricsLogin.onLogin(newbie)
death(newbie, nil, dragon, nil)
flushAll()
eq(key("death_area", "Ember Caves", "11-15") or key("death_area", "Ember Caves", "21-25"), 1, "later deaths are added")
eq(key("death_monster", "Dragon", "21-25"), 1, "level 24 is band 21-25")

-- churn: computed once after the start delay, then daily, written as it is (not added)
eq(key("churn", "1-5", "gone"), 5, "churn snapshot written")
eq(key("churn", "1-5", "active"), 2, "churn active")
eq(key("churn", "6-10", "gone"), 1, "churn band 2")
eq(key("churn", "11-15", "gone"), 0, "an empty band is written as 0")
eq(key("meta", "churn_days"), 14, "meta days")
local at = key("meta", "churn_at")
check(at ~= nil and at >= 1000000, "meta time")
clock = clock + cfg.churnEverySeconds
registry.ChaosMetricsThink.onThink(60000)
eq(key("churn", "1-5", "gone"), 5, "the daily snapshot replaces, not adds")
check(key("meta", "churn_at") > at, "meta time moved")

-- shutdown flushes at once (db.query)
registry.ChaosMetricsLogin.onLogin(vet)
death(vet, nil, dragon, nil)
registry.ChaosMetricsShutdown.onShutdown()
eq(key("death_monster", "Dragon", "51-60"), 1, "shutdown flush")

-- privacy: no player name, id or IP in any statement
local all = table.concat(queries, "\n")
for _, bad in ipairs({"Synthetic", "Tester Abc", "Staff Morgan", "lastip", "account_id", "`name`"}) do
	check(not all:find(bad, 1, true), "no '" .. bad .. "' in any statement")
end

-- disabled
Chaos.metricsConfig.enabled = false
local off = mk({id = 9, guid = 99, name = "Synthetic Off", player = true, level = 5, group = 1, lastLogin = 0, pos = {x = 1, y = 1, z = 7}})
registry.ChaosMetricsLogin.onLogin(off)
death(off, nil, dragon, nil)
check(next(ChaosMetrics.state.counts) == nil, "disabled: nothing counted")
Chaos.metricsConfig.enabled = true

if failures == 0 then
	print(string.format("metrics_test: %d checks passed", count))
else
	print(string.format("metrics_test: %d of %d checks FAILED", failures, count))
	os.exit(1)
end
