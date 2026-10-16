-- Run from the server/ folder: luajit tests/memorial_test.lua (or lua5.3; CI runs both)
-- The Capital Memorial: the season keys, the consent rules (records on, falls off by default), value and date texts,
-- the names of a party with hidden members, the look texts (at most 255 characters), the realm firsts per member, the
-- season's best of each board (ties), the Hardcore falls, the caps, the plaza's pages and their rotation, the slots;
-- then memorial.lua against a mocked engine: the refresh from the records, the firsts and the falls (staff left out),
-- the rows written with `shown`, the statues and stones placed with their look text, a hidden holder, the rotation,
-- a choice changed (every season's rows follow at once, the statues too), the fall hook and the question at the next
-- login (modal window and client), the protocol (wrong types refused), the staff command.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/memorial_config.lua")
dofile("data/scripts/chaos/memorial_core.lua")
local M = ChaosMemorialCore

local failures, count = 0, 0
local say = print
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		say("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- config
eq(cfg.opcode, 171, "the chronicle's opcode")
for _, kind in ipairs({"first", "record", "fallen", "stone"}) do
	local a = cfg.aid[kind]
	check(a and a >= 47940 and a <= 47949, "aid of " .. kind .. " in 47940-47949")
	check(cfg.items[kind] ~= nil, "items of " .. kind)
end
eq(#cfg.slots.first, 8, "eight statues of firsts")
eq(#cfg.slots.record, 8, "eight statues of records")
eq(#cfg.slots.fallen, 12, "twelve memorial stones")
check(cfg.defaults.records == true and cfg.defaults.fallen == false, "records on, falls off by default")
check(cfg.aid.portal and cfg.aid.portal >= 47940 and cfg.aid.portal <= 47949, "aid of the portal in 47940-47949")
check(cfg.plaza.at and cfg.plaza.at.x == 14800 and cfg.plaza.at.y == 14800 and cfg.plaza.at.z == 7,
	"the plaza at its plan's origin (install step contentareas)")
check(cfg.plaza.portal == nil and #cfg.portalTowns == 2 and type(cfg.plaza.arrival) == "table" and cfg.portalItem == 1387,
	"the way in: the Memorial Portal of Cinderhold and Mirewake (cityportals.lua)")
local seen = {}
for kind, list in pairs(cfg.slots) do
	if kind ~= "stone" then
		for _, o in ipairs(list) do
			local key = o[1] .. "," .. o[2]
			check(not seen[key], "slot " .. key .. " used once")
			seen[key] = true
		end
	end
end
check(not seen[cfg.slots.stone[1] .. "," .. cfg.slots.stone[2]], "the stone has its own tile")

-- ---------------------------------------------------------------- core
eq(M.seasonKey({id = 1}), "s1", "season key")
eq(M.seasonKey(nil, os.time({year = 2026, month = 11, day = 2, hour = 12})), "q20264", "quarter key")
eq(M.seasonName("s1", {id = 1, name = "Season of Ash"}), "Season of Ash", "season name")
eq(M.seasonName("q20264"), "Q4 2026", "quarter name")
local d = M.choiceOf(nil, cfg.defaults)
check(d.records and not d.fallen, "no row: records shown, falls not")
local r = M.choiceOf({records = 0, fallen = 1}, cfg.defaults)
check(not r.records and r.fallen, "a row decides")
check(M.shownFor("fallen", {records = true, fallen = false}) == false, "a fall needs its yes")
check(M.shownFor("first", {records = true}) == true, "a first follows records")
eq(M.formatValue("time", 252), "4:12", "time")
eq(M.formatValue("time", 3725), "1:02:05", "hours")
eq(M.formatValue("pct", 4512), "45.12%", "percent")
eq(M.formatValue("pct", 4500), "45%", "whole percent")
eq(M.formatValue(nil, 123456), "123,456", "number")
eq(M.namesText({"Vexa"}, 0), "Vexa", "one name")
eq(M.namesText({"Vexa", "Mira"}, 0), "Vexa and Mira", "two names")
eq(M.namesText({"Vexa", "Mira"}, 2), "Vexa, Mira and 2 others", "hidden members counted")
eq(M.namesText({}, 1), "1 other", "only a hidden one")
eq(M.namesText({}, 0), "heroes who keep their names", "nobody named")
eq(M.namesText({"A", "B", "C", "D", "E"}, 0), "A, B, C, D and 1 other", "at most four names")
local t0 = os.time({year = 2026, month = 11, day = 14, hour = 12})
eq(M.dateText(t0), "14 Nov 2026", "date")
check(#M.firstText({title = string.rep("X", 300), names = {"Vexa"}, hidden = 0, at = t0}, "Season of Ash") <= 255, "texts cut at 255")
-- firsts: one entry per member, staff out, by time
local people = {[1] = {name = "Vexa", class = "Templar", level = 500}, [2] = {name = "Mira", class = "Necromancer"},
	[9] = {name = "GM", staff = true}}
local fr = M.firstEntries({{target = "wb_time:kaelgor", board = "wb_time", name = "Kaelgor", at = 200, value = 300, guids = "1,2,9"},
	{target = "omen:bloodmoon", board = "omen", name = "Sangrith", at = 100, value = 90, guids = "2"}}, people)
eq(#fr, 3, "firsts: the members, no staff")
eq(fr[1].key, "omen:bloodmoon", "firsts by time")
eq(fr[2].name .. fr[3].name, "VexaMira", "both members of the first")
-- records: the best of each board and variant, any size; ties to the earlier, then the lower guid
local boards = {wb_time = {mode = "min", format = "time", title = function(v) return "World Boss Kill, " .. v end},
	tower_floor = {mode = "max", title = function() return "Highest Floor" end},
	battleground = {mode = "add", title = function() return "x" end}}
local rr = M.recordEntries({
	{slot = "wb_time|kaelgor|party", guid = 1, value = 300, at = 50, name = "Vexa"},
	{slot = "wb_time|kaelgor|solo", guid = 2, value = 250, at = 60, name = "Mira"},
	{slot = "wb_time|kaelgor|solo", guid = 3, value = 250, at = 40, name = "Bryn"},
	{slot = "tower_floor|-|-", guid = 1, value = 120, at = 10, name = "Vexa"},
	{slot = "tower_floor|-|-", guid = 4, value = 120, at = 10, name = "Zed"},
	{slot = "battleground|-|-", guid = 1, value = 99, at = 10, name = "Vexa"},
	{slot = "unknown|-|-", guid = 1, value = 5, at = 1, name = "Vexa"}}, boards, {"wb_time", "tower_floor"})
eq(#rr, 2, "records: one per board and variant, no add boards, no unknown boards")
eq(rr[1].name, "Bryn", "fastest, the earlier on a tie")
eq(rr[1].detail, "4:10", "the time")
eq(rr[1].title, "World Boss Kill, kaelgor", "the title")
eq(rr[2].name, "Vexa", "highest, the lower guid on a full tie")
local vr = M.recordEntries({{slot = "wb_time|b|solo", guid = 1, value = 9, at = 1, name = "B"},
	{slot = "wb_time|a|solo", guid = 2, value = 9, at = 1, name = "A"}},
	{wb_time = {mode = "min", variantRank = {b = 1, a = 2}, title = function(v) return v end}}, {"wb_time"})
eq(vr[1].name .. vr[2].name, "BA", "variants in the catalogue's order")
-- falls: highest level first
local fe = M.fallenEntries({{guid = 5, name = "Low", level = 50, at = 1, cause = "killed by a rat"},
	{guid = 6, name = "High", level = 300, at = 2, cause = "killed by a dragon lord", class = "Ranger"}})
eq(fe[1].name, "High", "the highest fall first")
check(M.fallenText(fe[1], "Season of Ash"):find("Here lies High, a level 300 Ranger, killed by a dragon lord on"), "fall text")
-- choices and caps
local all = {}
for _, e in ipairs(fr) do all[#all + 1] = e end
for _, e in ipairs(rr) do all[#all + 1] = e end
for _, e in ipairs(fe) do all[#all + 1] = e end
local choices = {[2] = {records = 0, fallen = 0}, [6] = {records = 1, fallen = 1}}
local applied = M.applyChoices(all, function(g) return M.choiceOf(choices[g], cfg.defaults) end, {first = 1, record = 9, fallen = 9})
local firsts = M.displayList(applied, "first")
eq(#firsts, 1, "cap: one first (counted by thing)")
eq(firsts[1].hidden, 1, "Mira's name hidden on her first")
local falls = M.displayList(applied, "fallen")
eq(#falls, 1, "only the fall that said yes")
eq(falls[1].name, "High", "High said yes")
-- a record whose holder hides stays, without the name
local hiddenRec = {kind = "record", key = "k", guid = 2, name = "Mira", title = "T", detail = "1:00", at = t0, shown = false, ord = 1}
check(not M.recordText(hiddenRec, "S"):find("Mira") and M.recordText(hiddenRec, "S"):find("keeps their name"), "hidden record holder")
-- pages
eq(M.pages(0, 8), 1, "no entries: one page")
eq(M.pages(17, 8), 3, "17 entries on 8 statues: 3 pages")
eq(M.pageIndex(0, 600, 3), 1, "page 1")
eq(M.pageIndex(600, 600, 3), 2, "page 2 after the rotation")
eq(M.pageIndex(1800, 600, 3), 1, "and around")
local pg = M.page({1, 2, 3, 4, 5}, 2, 3)
check(pg[1] == 5 and pg[2] == nil, "the last page")
-- the whole plaza
local many = {}
for i = 1, 10 do
	many[#many + 1] = {kind = "record", key = "r" .. i, guid = i, name = "N" .. i, title = "Board " .. i, detail = "1", at = t0,
		shown = true, ord = i}
end
local plan, page, pages = M.plan(cfg, many, "Season of Ash", 0)
eq(#plan, 8 + 8 + 12 + 1, "an item per slot and the stone")
eq(pages, 2, "two pages of records")
eq(page, 1, "page 1 at time 0")
check(plan[9].entry and plan[9].entry.key == "r1", "record statue 1 holds the first record")
check(plan[1].entry == nil and plan[1].text == nil, "an empty first slot")
check(plan[#plan].text:find("page 1 of 2") and plan[#plan].text:find("10 records"), "the stone says the page")
local plan2 = M.plan(cfg, many, "Season of Ash", 600)
check(plan2[9].entry and plan2[9].entry.key == "r9", "the next page after the rotation")
local pos = M.slotPos({x = 1000, y = 2000, z = 7}, {8, 15})
check(pos.x == 1008 and pos.y == 2015 and pos.z == 7, "slot position")
eq(M.slotPos(nil, {1, 2}), nil, "no plaza, no position")
local pl = M.payload("Season of Ash", {records = true, fallen = false}, true, applied)
check(pl.records == true and pl.fallen == false and pl.ask == true, "payload: choice and question")
eq(#pl.firsts, 1, "payload firsts")
eq(pl.recs[1].n, "Bryn", "payload record holder")
eq(#pl.falls, 1, "payload: shown falls only")
check(M.askText("Mira", 88, "killed by a dragon"):find("Only with your yes"), "the question")

-- ---------------------------------------------------------------- memorial.lua against a mocked engine
local registry, globals, talks = {}, {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) self.t = t end
	function o:register() registry[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:register() globals[name] = o end
	function o:interval() end
	return o
end
local moves = {}
function MoveEvent()
	local o = {aids = {}}
	function o:type(t) self.t = t end
	function o:aid(...) self.aids = {...} end
	function o:register() moves[#moves + 1] = o end
	return o
end
function TalkAction(words)
	local o = {}
	function o:separator() end
	function o:register() talks[words] = o end
	return o
end
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
local function queried(pattern, from)
	for i = from or 1, #queries do
		if queries[i]:find(pattern) then return queries[i] end
	end
	return nil
end
local optinRows = {}
local now0 = os.time({year = 2026, month = 11, day = 20, hour = 12})
local function rowsFor(qq)
	if qq:find("FROM `chaos_memorial_optin`") then
		local out = {}
		for guid, r in pairs(optinRows) do
			out[#out + 1] = {player_id = guid, records = r.records, fallen = r.fallen, asked = r.asked}
		end
		return out
	elseif qq:find("FROM `chaos_records_firsts`") then
		check(qq:find("`season` = 's1'"), "firsts of the season key")
		return {{target = "wb_time:kaelgor", board = "wb_time", name = "Kaelgor", guids = "501,502", value = 300, at = now0 - 500},
			{target = "omen:bloodmoon", board = "omen", name = "Sangrith", guids = "900", value = 60, at = now0 - 400}}
	elseif qq:find("FROM `players` WHERE `id` IN") then
		return {{id = 501, name = "Hero", vocation = 1, level = 400, group_id = 1}, {id = 502, name = "Mira", vocation = 2, level = 380,
			group_id = 1}, {id = 900, name = "Gamemaster", vocation = 1, level = 1, group_id = 5}}
	elseif qq:find("FROM `chaos_records` r JOIN `players`") then
		check(qq:find("r%.`period` = 's1'") and qq:find("p%.`group_id` < 4"), "records of the season, no staff")
		check(qq:find("LIKE 'wb_time|%%'"), "the configured boards")
		local out = {}
		for i = 1, 10 do
			out[#out + 1] = {slot = "wb_time|boss" .. i .. "|solo", player_id = 500 + (i % 2) + 1, value = 100 + i, at = now0 - i,
				name = (i % 2 == 0) and "Hero" or "Mira", vocation = 1, level = 400}
		end
		return out
	elseif qq:find("FROM `chaos_season_modes` sm") then
		check(qq:find("sm%.`season` = 1") and qq:find("`fallen_at` > 0"), "the season's falls")
		return {{player_id = 503, name = "Fallen Fred", vocation = 2, fallen_level = 88, fallen_cause = "killed by a dragon lord",
			fallen_at = now0 - 100}}
	end
	return {}
end
Chaos.select = function(qq) return rowsFor(qq) end
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "{}" end, decode = function(s) return s end}
Chaos.decode = function(b) return type(b) == "table" and b or nil end
local clock = now0
local realTime = os.time
os.time = function(tt) if tt then return realTime(tt) end return clock end
local tiles = {}
local function tkey(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z) return {x = x, y = y, z = z} end
local function mkItem(id, pos)
	local it = {id = id, pos = pos, attrs = {}}
	function it:getId() return self.id end
	function it:getActionId() return self.aid or 0 end
	function it:setActionId(a) self.aid = a end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:remove()
		local t = tiles[tkey(self.pos)]
		for i, x in ipairs(t.items) do
			if x == self then table.remove(t.items, i) return true end
		end
	end
	return it
end
for x = 1000, 1048 do
	for y = 2000, 2040 do
		tiles[x .. "," .. y .. ",7"] = {items = {}}
	end
end
Tile = function(pos)
	local t = tiles[tkey(pos)]
	if not t then return nil end
	return {getGround = function() return true end, getTopCreature = function() return t.creature end,
		getItems = function() local c = {} for i, x in ipairs(t.items) do c[i] = x end return c end}
end
Game = {createItem = function(id, nn, pos)
	local t = tiles[tkey(pos)]
	if not t then return nil end
	local it = mkItem(id, {x = pos.x, y = pos.y, z = pos.z})
	t.items[#t.items + 1] = it
	return it
end}
Vocation = function(id) return {getName = function() return id == 1 and "Templar" or "Necromancer" end} end
local modals = {}
ModalWindow = function(id, title, text)
	local w = {id = id, title = title, text = text, buttons = {}}
	function w:addButton(b, t) self.buttons[#self.buttons + 1] = {b, t} end
	function w:setDefaultEnterButton() end
	function w:setDefaultEscapeButton() end
	function w:sendToPlayer(p) modals[#modals + 1] = {p = p, w = self} end
	return w
end
local players = {}
local nextId = 2000
local function mkPlayer(name, guid, group)
	nextId = nextId + 1
	local p = {id = nextId, name = name, guid = guid, group = group or 1, msgs = {}, ops = {}, events = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:sendExtendedOpcode(op, data) self.ops[#self.ops + 1] = {op, data} return true end
	function p:registerEvent(ev) self.events[ev] = true end
	players[#players + 1] = p
	return p
end
Player = function(x)
	if type(x) == "table" then return x end
	for _, p in ipairs(players) do
		if p.id == x or p.guid == x then return p end
	end
	return nil
end
local season = {id = 1, name = "Season of Ash"}
ChaosSeason = {current = function() return season end, fallenByGuid = {}}
local fell = {}
ChaosSeason.modesFall = function(player, killer, corpse) fell[#fell + 1] = player:getGuid() end
Chaos.seasonConfig = {modes = {table = "chaos_season_modes"}}
Chaos.recordsConfig = dofile("data/scripts/chaos/records_config.lua")
ChaosRecords = {byKey = {wb_time = {name = "World Boss Kill", mode = "min", format = "time", variantByKey = {}},
	omen = {name = "Omen Guardians", mode = "min", format = "time"}}}
local print_ = print
local logged = {}
print = function(s) logged[#logged + 1] = s end
dofile("data/scripts/chaos/memorial.lua")
local X = ChaosMemorial
local XC = Chaos.memorialConfig
-- the mocked world has no tiles there: start as a server without the plaza
local livePlaza = XC.plaza.at
XC.plaza.at = nil
check(registry.ChaosMemorialLogin and registry.ChaosMemorialExtended and registry.ChaosMemorialModal, "events")
eq(registry.ChaosMemorialModal.t, "modalwindow", "the modal event")
check(ChaosWrapChain.has(ChaosSeason.modesFall, "memorial"), "the fall hook")
-- startup without a plaza: entries, nothing placed
globals.ChaosMemorialStartup.onStartup()
check(queried("CREATE TABLE IF NOT EXISTS `chaos_memorial_optin`") and queried("CREATE TABLE IF NOT EXISTS `chaos_memorial_entries`"),
	"tables")
check(queried("DELETE FROM `chaos_memorial_entries` WHERE `season` = 's1'"), "the season's rows written again")
local ins = queried("INSERT IGNORE INTO `chaos_memorial_entries`")
check(ins and ins:find("'first', 'wb_time:kaelgor', 501, 'Hero'") and ins:find("'first', 'wb_time:kaelgor', 502, 'Mira'"), "firsts per member")
check(not ins:find("Gamemaster"), "staff are never on the Memorial")
check(ins:find("'fallen', '503', 503, 'Fallen Fred', 'Hardcore', 'killed by a dragon lord', 88, 'Necromancer'.-, 0, 'Season of Ash'%)"),
	"a fall without its yes is written hidden")
check(ins:find("'record', 'wb_time|boss1', 502, 'Mira', 'World Boss Kill, boss1', '1:41'"), "a record row")
local placedAny = false
for _, t in pairs(tiles) do placedAny = placedAny or #t.items > 0 end
check(not placedAny, "no plaza, nothing placed")
check(logged[#logged]:find("plaza is not placed"), "the console says so")
-- the owner places the plaza
XC.plaza.at = {x = 1000, y = 2000, z = 7}
X.placePlaza(true)
local function at(off) return tiles[(1000 + off[1]) .. "," .. (2000 + off[2]) .. ",7"].items[1] end
local f1 = at(XC.slots.first[1])
check(f1 and f1.aid == 47940 and (f1.id == 8836 or f1.id == 8837), "a guardian statue for the first")
check(f1.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("Realm first of Season of Ash: Kaelgor %(World Boss Kill%), slain by Hero and Mira"),
	"its look text")
eq(at(XC.slots.first[2]) and at(XC.slots.first[2]).attrs[ITEM_ATTRIBUTE_DESCRIPTION] and 1 or 0, 0, "the GM's first has no statue")
local rec1 = at(XC.slots.record[1])
check(rec1 and rec1.aid == 47941 and rec1.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("World Boss Kill, boss%d+: 1:%d+, %a+, Templar"),
	"a record statue")
eq(at(XC.slots.fallen[1]), nil, "no stone for a fall without its yes")
local stone = at(XC.slots.stone)
check(stone and stone.id == 1421 and stone.aid == 47943 and stone.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("page " .. X.page .. " of 2"),
	"the Memorial stone with the page")
-- rotation: ten records on eight statues; start the clock on page 1
clock = clock - clock % 1200
X.placePlaza(true)
eq(X.page, 1, "page 1")
check(at(XC.slots.record[1]).attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("boss1:"), "page 1: the first record")
clock = clock + 600
globals.ChaosMemorialTick.onThink(60000)
eq(X.page, 2, "the next page after rotateSeconds")
local rotated = at(XC.slots.record[1])
check(rotated and rotated.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("boss8:"), "the statues turned to page 2 (catalogue order, else by key)")
eq(at(XC.slots.record[3]), nil, "page 2 holds two records: the third statue is taken away")
-- a choice: Mira hides her records; every season's rows follow, the statues too
local q0 = #queries
local mira = mkPlayer("Mira", 502)
registry.ChaosMemorialExtended.onExtendedOpcode(mira, 171, {action = "memset", data = {records = false, fallen = false}})
check(queried("INSERT INTO `chaos_memorial_optin`.-%(502, 0, 0, 1,", q0), "the choice row")
check(queried("UPDATE `chaos_memorial_entries` SET `shown` = 0 WHERE `player_id` = 502 AND `kind` IN %('first', 'record'%)", q0),
	"every season's records hidden at once")
check(not at(XC.slots.first[1]).attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("Mira"), "the first statue no longer names her")
check(at(XC.slots.first[1]).attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("Hero and 1 other"), "she is counted")
local mem = sent[#sent]
check(mem.action == "mem" and mem.data.records == false, "the answer: the new choice")
eq(X.showsRecords(502), false, "the Chronicle's top lists hide her too")
-- wrong types are refused (no write)
local q1 = #queries
clock = clock + 5
registry.ChaosMemorialExtended.onExtendedOpcode(mira, 171, {action = "memset", data = {records = "yes", fallen = 1}})
eq(#queries, q1, "wrong types: nothing written")
registry.ChaosMemorialExtended.onExtendedOpcode(mira, 171, {action = "open"})
eq(#queries, q1, "the chronicle's actions are not ours")
local gmp = mkPlayer("Gamemaster", 900, 5)
registry.ChaosMemorialExtended.onExtendedOpcode(gmp, 171, {action = "memset", data = {records = true, fallen = true}})
eq(#queries, q1, "staff do not choose")
-- the fall: the hook, then the question at the next login
local fred = mkPlayer("Fallen Fred", 503)
ChaosSeason.fallenByGuid[503] = {season = 1, level = 88, cause = "killed by a dragon lord"}
ChaosSeason.modesFall(fred, nil, nil)
eq(fell[1], 503, "the fall itself ran")
check(queried("INSERT INTO `chaos_memorial_optin`.-%(503, 1, 0, 0,"), "the fall waits for its question")
optinRows[503] = {records = 1, fallen = 0, asked = 0}
registry.ChaosMemorialLogin.onLogin(fred)
runEvents()
check(modals[1] and modals[1].w.id == 7480 and modals[1].w.text:find("level 88 %(killed by a dragon lord%)"), "the modal question")
registry.ChaosMemorialExtended.onExtendedOpcode(fred, 171, {action = "mem"})
check(sent[#sent].action == "mem" and sent[#sent].data.ask == true, "the client's Memorial tab sees the question")
check(modals[1].w.buttons[1][2] == "Remember me", "the buttons")
Chaos.lang = function() return "pt-BR" end
X.ask(fred)
check(modals[2] and modals[2].w.title == "O Memorial das Brasas" and modals[2].w.text:find("caiu no Hardcore no nível 88")
	and modals[2].w.buttons[1][2] == "Lembrar de mim", "the question in Portuguese")
registry.ChaosMemorialModal.onModalWindow(fred, 7480, 1, 0)
check(queried("INSERT INTO `chaos_memorial_optin`.-%(503, 1, 1, 1,"), "yes: the fall is shown")
check(fred.msgs[#fred.msgs]:find("O Memorial vai lembrar da sua queda"), "the answer's line in Portuguese")
Chaos.lang = nil
check(queried("UPDATE `chaos_memorial_entries` SET `shown` = 1 WHERE `player_id` = 503 AND `kind` = 'fallen'"), "every season's falls")
local stone1 = at(XC.slots.fallen[1])
check(stone1 and (stone1.id == 1407 or stone1.id == 1408) and stone1.attrs[ITEM_ATTRIBUTE_DESCRIPTION]:find("Here lies Fallen Fred, a level 88 Necromancer"),
	"the memorial stone of the fall")
registry.ChaosMemorialModal.onModalWindow(fred, 7481, 1, 0)
-- another modal id is not ours (nothing changes)
eq(X.rows[503].fallen, 1, "another modal is ignored")
-- the way in: the portal in the capital leads to the plaza's arrival
check(livePlaza and moves[1] and moves[1].t == "stepin" and moves[1].aids[1] == 47944, "the portal's step-in event")
XC.plaza.portal = {x = 1040, y = 2039, z = 7}
globals.ChaosMemorialTick.onThink(60000)
local portal = tiles["1040,2039,7"].items[1]
check(portal and portal.id == 1387 and portal.aid == 47944, "the portal is placed")
eq(ChaosCityPortals.kindOf(47944), "memorial", "a city portal: look text and effect (cityportals_fx.lua)")
globals.ChaosMemorialTick.onThink(60000)
eq(#tiles["1040,2039,7"].items, 1, "and found again, not doubled")
Chaos.lang = function() return "en" end
local walker = mkPlayer("Walker", 777)
function walker:teleportTo(pos) self.pos = pos end
function walker:getPlayer() return self end
function walker:getPosition() return {sendMagicEffect = function() end} end
moves[1].onStepIn(walker, portal, Position(1040, 2039, 7), Position(1040, 2038, 7))
check(walker.pos and walker.pos.x == 1000 + XC.plaza.arrival[1] and walker.pos.y == 2000 + XC.plaza.arrival[2] and walker.pos.z == 7,
	"stepping in: the plaza's arrival")
check(walker.msgs[#walker.msgs]:find("The Ember Memorial%. The portal beside you"), "the arrival line")
moves[1].onStepIn({getPlayer = function() return nil end}, portal, Position(1040, 2039, 7), Position(1040, 2038, 7))
Chaos.lang = nil
-- staff command
local god = mkPlayer("God", 901, 6)
talks["/memorial"].onSay(god, "/memorial", "status")
check(god.msgs[1] and god.msgs[1]:find("Season of Ash %(s1%)") and god.msgs[1]:find("placed"), "status")
print = print_

print(string.format("memorial_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
