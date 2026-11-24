-- Run from the server/ folder: luajit tests/collection_log_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Collection log (O753): the opcode (free in every list), the core (groups, catalog, states, summary, merge, SQL), the real
-- catalog of chaos_unique_items.lua, and collection_log.lua on a mocked engine: note at drop time, the sync handler, the
-- payload (rows, groups, pity), the rate limit and another opcode ignored. server/README.md "Collection log (O753)".
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function read(path)
	local f = io.open(path, "r")
	if not f then
		return ""
	end
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/collection_log_config.lua")
dofile("data/scripts/chaos/collection_log_core.lua")
local CL = ChaosCollectionLogCore

-- ================================================================ the opcode
eq(ChaosOpcodes.collectionLog, 170, "opcode 170")
eq(cfg.opcode, 170, "the config names 170")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 113, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(v ~= 170, "170 is not the reference opcode " .. v)
end
local count170 = 0
for _ in read("data/scripts/chaos/chaos_constants.lua"):gmatch("ChaosOpcodes%.[%w_]+%s*=%s*170%f[%D]") do
	count170 = count170 + 1
end
eq(count170, 1, "the constants name 170 once")
-- no client module but game_collectionlog names 170 as its opcode
local p = io.popen('grep -rlE "OPCODE *= *170([^0-9]|$)" ../client/overlay/modules 2>/dev/null')
if p then
	local found = p:read("*a") or ""
	p:close()
	for line in found:gmatch("[^\n]+") do
		ok(line:find("game_collectionlog", 1, true) ~= nil, "only game_collectionlog uses 170: " .. line)
	end
end
eq(Chaos.storage.chasePity, 7106600, "the chase pity block")
ok(read("sql/chaos_collection_log.sql"):find("chaos_collection_log", 1, true) ~= nil, "the sql file has the table")
ok(read("deploy/launch_wipe_tables.json"):find('"chaos_collection_log"', 1, true) ~= nil, "the launch wipe names the table")

-- ================================================================ core
local pin = {[2216] = true}
eq(CL.groupOf({id = 2216, bossOnly = true}, pin), "pinnacle", "a pinnacle unique")
eq(CL.groupOf({id = 1, set = "embers"}), "set:embers", "a set piece")
eq(CL.groupOf({id = 1, ascended = true, bossOnly = true}), "ascended", "an Ascended unique")
eq(CL.groupOf({id = 1, bossOnly = true}), "boss", "a boss unique")
eq(CL.groupOf({id = 1, minMonsterLevel = 1000}), "endgame", "an endgame unique")
eq(CL.groupOf({id = 1}), "hunt", "a hunting unique")
local order = {}
for i, g in ipairs(cfg.groupOrder) do
	order[g] = i
end
local cat = CL.catalog({
	uniques = {{id = 10, name = "Bravo"}, {id = 11, name = "Alpha", monsters = {"Rat"}}, {id = 12, name = "Sig", bossOnly = true},
		{id = 13, name = "Piece", set = "embers"}, {id = 10, name = "Bravo again"}, {id = 0, name = "bad"}},
	raid = {{id = 20, name = "Crown"}}, cards = {{id = 30, name = "Minor Card"}}, pinnacle = {}, order = order})
eq(#cat, 6, "six rows: a double and a bad id left out")
eq(cat[1].g, "raid", "raid before boss")
eq(cat[2].g, "boss", "boss")
eq(cat[3].g, "set:embers", "the set group by its prefix")
eq(cat[4].name, "Alpha", "hunting sorted by name")
eq(cat[6].g, "card", "cards last")
local mine = {owned = CL.merge({{item_id = 10, count = 3, first_at = 500}}, {{item_id = 10, at = 400}, {item_id = 30, at = 900}}),
	killed = {rat = true}}
eq(mine.owned[10].count, 3, "merge: the log's count")
eq(mine.owned[10].at, 400, "merge: the earlier date of either")
eq(mine.owned[30].count, 1, "merge: a seen row alone is one")
local rows = CL.rows(cat, mine)
local byId = {}
for _, r in ipairs(rows) do
	byId[r.i] = r
end
eq(byId[10].s, 2, "owned")
eq(byId[10].k, 3, "its count")
eq(byId[10].d, 400, "its first date")
eq(byId[11].s, 1, "seen: a monster that lists it was killed")
eq(byId[12].s, 0, "not yet")
local sum = CL.summary(rows)
eq(sum.total, 6, "summary total")
eq(sum.owned, 2, "summary owned")
eq(sum.seen, 1, "summary seen")
eq(sum.byGroup.hunt.total, 2, "per group")
local groups = CL.groups(cfg, cat, {embers = "Embers of the Pyre"})
eq(groups[3].k, "set:embers", "the set group")
eq(groups[3].l, "Set: %s", "its label pattern")
eq(groups[3].a, "Embers of the Pyre", "its argument: the set's name")
ok(CL.sqlCreate("t"):find("PRIMARY KEY (`player_id`, `item_id`)", 1, true) ~= nil, "sql create")
ok(CL.sqlNote("t", 5, 6, 1, 99):find("ON DUPLICATE KEY UPDATE `count` = `count` + 1", 1, true) ~= nil, "sql note adds")
ok(CL.sqlSelect("t", 5):find("`player_id` = 5", 1, true) ~= nil, "sql select")

-- ================================================================ the real catalog
ChaosUniqueSpecs = ChaosUniqueSpecs or {}
do
	local realDofile = dofile
	dofile = function(path)
		if tostring(path):find("chaos_effect_compat", 1, true) then
			return
		end
		return realDofile(path)
	end
	realDofile("data/lib/chaos_unique_items.lua")
	dofile = realDofile
end
local pcfg = dofile("data/scripts/chaos/pinnacle_config.lua")
local pins = {}
for _, b in ipairs(pcfg.bosses) do
	pins[b.unique.id] = true
end
local real = CL.catalog({uniques = ChaosUniqueItems, pinnacle = pins, order = order})
ok(#real >= 150, "every unique is listed (" .. #real .. ")")
local pinCount, setCount = 0, 0
for _, r in ipairs(real) do
	if r.g == "pinnacle" then pinCount = pinCount + 1 end
	if r.g:find("^set:") then setCount = setCount + 1 end
end
eq(pinCount, #pcfg.bosses, "the four pinnacle uniques")
ok(setCount > 10, "the set pieces (" .. setCount .. ")")

-- ================================================================ collection_log.lua on a mocked engine
local queries, sent = {}, {}
db = {query = function(q) queries[#queries + 1] = q return true end, storeQuery = function() return false end}
local registered = {}
CreatureEvent = function(name)
	local e = {name = name}
	function e:type() end
	function e:register() registered[name] = self end
	return e
end
GlobalEvent = CreatureEvent
ItemType = function(id)
	return {getName = function() return "item " .. id end, getClientId = function() return id + 1000 end}
end
Chaos.send = function(player, opcode, action, data)
	sent[#sent + 1] = {opcode = opcode, action = action, data = data}
	return true
end
Chaos.decode = function(buffer)
	if buffer == "sync" then return {action = "sync"} end
	if buffer == "other" then return {action = "other"} end
	return nil
end
local limited = false
Chaos.limited = function() return limited end
Chaos.isTester = function(pl) return pl.tester == true end
local rowsByQuery = {}
Chaos.select = function(q)
	for k, v in pairs(rowsByQuery) do
		if q:find(k, 1, true) then return v end
	end
	return {}
end
rowsByQuery["chaos_conquest_seen"] = {{item_id = 2216, at = 111}}
rowsByQuery["chaos_bestiary"] = {}
Chaos.pinnacleConfig = pcfg
ChaosRaidConfig = {uniques = {{id = 7422, name = "Gravewarden's Verdict"}}}
ChaosCardsCore = {cardIds = function() return {27482, 27483} end}
ChaosCardDeck = {owned = function(_, id) return id == 27482 and 2 or 0 end}
ChaosChasePity = {view = function() return {{k = "rift", l = "Rift chest: set piece", d = 37, n = 114}} end}
ChaosItemSets = {sets = {}}
dofile("data/scripts/chaos/collection_log.lua")
local X = ChaosCollectionLog
ok(registered.ChaosCollectionLogExtended and registered.ChaosCollectionLogLogin and registered.ChaosCollectionLogLogout,
	"the events are registered")
local pl = {guid = 77}
function pl:getGuid() return self.guid end
-- a drop is written at once
ok(X.note(pl, 2412, 1), "a note")
ok(queries[#queries]:find("INSERT INTO `chaos_collection_log`", 1, true) and queries[#queries]:find("2412", 1, true), "the row is written")
local tester = {guid = 78, tester = true}
function tester:getGuid() return self.guid end
ok(not X.note(tester, 2412, 1), "a tester bot is not logged")
-- the sync
local ext = registered.ChaosCollectionLogExtended
ext.onExtendedOpcode(pl, 170, "sync")
eq(#sent, 1, "sync answers")
local d = sent[1] and sent[1].data or {}
eq(sent[1] and sent[1].action, "state", "the state")
eq(sent[1] and sent[1].opcode, 170, "on 170")
ok(d.total and d.total >= 150, "every row")
local got = {}
for _, r in ipairs(d.rows or {}) do
	got[r.i] = r
end
eq(got[2216] and got[2216].s, 2, "a drop of before (conquest seen) is owned")
eq(got[2216] and got[2216].d, 111, "with its date")
eq(got[2216] and got[2216].c, 3216, "and its client id")
eq(got[27482] and got[27482].s, 2, "a card with a Deck copy is owned")
eq(got[27482] and got[27482].k, 2, "its copies")
eq(got[27483] and got[27483].s, 0, "a card without one is not")
eq(got[7422] and got[7422].g, "raid", "the raid unique")
eq(d.pity and d.pity[1].n, 114, "the pity rows")
ok(type(d.groups) == "table" and #d.groups >= 5, "the groups")
-- a note after the sync shows in the next one (the cache)
X.note(pl, 7422, 1)
ext.onExtendedOpcode(pl, 170, "sync")
local d2 = sent[2] and sent[2].data or {}
for _, r in ipairs(d2.rows or {}) do
	if r.i == 7422 then
		eq(r.s, 2, "the new drop is owned")
		eq(r.k, 1, "once")
	end
end
-- the rate limit, another opcode, another action
limited = true
ext.onExtendedOpcode(pl, 170, "sync")
eq(#sent, 2, "rate limited")
limited = false
ext.onExtendedOpcode(pl, 171, "sync")
ext.onExtendedOpcode(pl, 170, "other")
ext.onExtendedOpcode(pl, 170, "garbage")
eq(#sent, 2, "another opcode, action or a bad buffer: nothing")
-- logout forgets the cache
registered.ChaosCollectionLogLogout.onLogout(pl)
eq(X.cache[77], nil, "logout clears the cache")

print(string.format("collection_log_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
