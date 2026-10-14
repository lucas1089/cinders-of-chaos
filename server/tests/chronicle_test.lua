-- Run from the server/ folder: luajit tests/chronicle_test.lua (or lua5.3; CI runs both)
-- The Ashen Chronicle: the config and the story text (EN and PT-BR for every field, keys, goals, world changes, ranges),
-- chapters advancing with events (only the open chapter, goals capped, no points for a met goal, contributions only),
-- the level thresholds, the records' runs mapped to events, the ranking and the season record, the world replayed from
-- the written chapters and its diff, the payload, the texts; then chronicle.lua against a mocked engine: the season
-- start, the records / raid / invasion hooks (staff left out, a raid run and an invasion counted once), the level
-- events, a chapter written (broadcast, Discord row, town decoration, global flags, the gate portal and its step-in),
-- privacy of the top lists, the window, a restart (the world placed again), the season's end (the record), the next
-- season's start (the world reset), the staff command.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/chronicle_config.lua")
local TXT = dofile("data/scripts/chaos/chronicle_text.lua")
dofile("data/scripts/chaos/chronicle_core.lua")
local K = ChaosChronicleCore

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
local function deep(t)
	local c = {}
	for k, v in pairs(t) do
		c[k] = type(v) == "table" and deep(v) or v
	end
	return c
end

-- ---------------------------------------------------------------- config and text
local problems = K.validate(cfg, TXT)
eq(#problems, 0, "the shipped config and text validate" .. (problems[1] and (" (" .. problems[1] .. ")") or ""))
eq(K.arcOf(cfg, 1), "s1", "season 1 tells s1")
eq(K.arcOf(cfg, 2), nil, "no arc for season 2")
eq(#K.chapters(cfg, "s1"), 5, "five chapters")
eq(cfg.opcode, 171, "opcode 171")
check(cfg.globalStorage.base == 7102100 and cfg.globalStorage.done == 7102110 and cfg.globalStorage.season == 7102111,
	"global storages in the reserved block")
-- the opcode is free: not a ChaosOpcodes value of another module, not the base server's or the base client's
for key, op in pairs(ChaosOpcodes) do
	check(key == "chronicle" or op ~= 171, "171 is not taken by " .. key)
end
for _, op in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	check(op ~= 171, "171 is no base opcode " .. op)
end
-- every text: en and pt, no em or en dashes, no empty paragraph; titles numbered
local arc = TXT.arcs.s1
for _, f in ipairs({"title", "intro", "ending"}) do
	check(type(arc[f].en) == "string" and type(arc[f].pt) == "string" and #arc[f].pt > 10, "arc " .. f .. " en and pt")
end
local function noDash(s, where)
	check(not s:find("\226\128\148") and not s:find("\226\128\147"), where .. ": no em / en dash")
end
for ci, ch in ipairs(arc.chapters) do
	eq(ch.key, cfg.chapters.s1[ci].key, "chapter " .. ci .. " key matches the config")
	for _, lang in ipairs({"en", "pt"}) do
		check(#ch.text[lang] >= 2, "chapter " .. ci .. " " .. lang .. ": two paragraphs")
		for _, p in ipairs(ch.text[lang]) do
			check(#p > 60, "chapter " .. ci .. " " .. lang .. " paragraph")
			noDash(p, "chapter " .. ci)
		end
		for _, f in ipairs({"title", "done", "world", "npc"}) do
			check(type(ch[f][lang]) == "string" and #ch[f][lang] > 5, "chapter " .. ci .. " " .. f .. " " .. lang)
			noDash(ch[f][lang], "chapter " .. ci .. " " .. f)
		end
	end
	check(ch.title.en:match("^[IV]+%. ") ~= nil and ch.title.pt:match("^[IV]+%. ") ~= nil, "chapter " .. ci .. " numbered")
end
eq(TXT.pick({en = "a", pt = "b"}, "pt-BR"), "b", "pick pt-BR")
eq(TXT.pick({en = "a", pt = "b"}, "de"), "a", "pick falls back to en")
eq(TXT.npcLine("s1", 0, "en"), TXT.npcStart.en, "npc line before any chapter")
eq(TXT.npcLine("s1", 2, "pt"), arc.chapters[2].npc.pt, "npc line after two chapters (pt)")
eq(TXT.npcLine("s1", 9, "en"), arc.chapters[5].npc.en, "npc line past the end")
eq(TXT.npcLine("nope", 3, "en"), TXT.npcStart.en, "npc line of an unknown arc")
-- the validator catches mistakes
local bad = deep(cfg)
bad.chapters.s1[2].goals[1].kind = "dragons"
bad.chapters.s1[3].world.open = {"atlantis"}
bad.chapters.s1[1].goals[2].band = "b9"
bad.gateAid = 47000
local badText = deep(TXT)
badText.arcs.s1.chapters[4].done.pt = nil
local found = table.concat(K.validate(bad, badText), "\n")
check(found:find("unknown kind dragons"), "validate: unknown goal kind")
check(found:find("unknown area atlantis"), "validate: unknown area")
check(found:find("unknown band b9"), "validate: unknown band")
check(found:find("gateAid"), "validate: gate action ids")
check(found:find("done needs en and pt"), "validate: missing pt")
local short = deep(cfg)
short.chapters.s1 = {short.chapters.s1[1], short.chapters.s1[2], short.chapters.s1[3]}
check(table.concat(K.validate(short, TXT), "\n"):find("3 chapters"), "validate: 4 to 6 chapters")

-- ---------------------------------------------------------------- events and chapters
local c = deep(cfg)
c.chapters.s1[1].goals = {{kind = "level", level = 100, target = 2}, {kind = "rift", band = "b1", target = 3}}
c.chapters.s1[2].goals = {{kind = "worldboss", target = 1}, {kind = "rift", band = "b2", target = 1}}
local st = K.newState(c, "s1", 1, 1000)
eq(st.chapter, 1, "new state: chapter 1")
eq(K.doneCount(c, st), 0, "nothing written")
local A, B, Cc = {guid = 1, name = "Vexa"}, {guid = 2, name = "Mira"}, {guid = 3, name = "Bryn"}
local r = K.addEvent(c, st, {kind = "worldboss"}, {A, B}, 1001)
check(not r.matched, "a later chapter's goal does not count yet")
eq(st.progress[2][1], 0, "chapter 2 untouched")
r = K.addEvent(c, st, {kind = "rift", band = "b2"}, {A}, 1001)
check(not r.matched, "another band does not count")
r = K.addEvent(c, st, {kind = "rift", band = "b1"}, {A, B}, 1002)
check(r.matched and r.points == cfg.points.rift_b1, "a sealed rift of the band")
eq(st.progress[1][2], 1, "one rift")
eq(st.contrib[1][1].points, 1, "Vexa 1 point")
eq(st.contrib[1][2].points, 1, "Mira 1 point")
K.addEvent(c, st, {kind = "rift", band = "b1", count = 5}, {Cc}, 1003)
eq(st.progress[1][2], 3, "goal capped at its target")
eq(st.contrib[1][3].points, 5, "Bryn 5 points")
r = K.addEvent(c, st, {kind = "rift", band = "b1"}, {A}, 1004)
check(not r.matched, "a met goal takes no more")
eq(st.contrib[1][1].points, 1, "and gives no more points")
eq(K.chapterPct(c, st, 1), 50, "half of the chapter (one of two goals)")
r = K.addEvent(c, st, {kind = "level", level = 100}, {B}, 1005)
eq(K.chapterPct(c, st, 1), 75, "goals averaged")
r = K.addEvent(c, st, {kind = "level", level = 100}, {A}, 1006, {progress = false})
check(r.matched and st.progress[1][1] == 1, "contributions only: no progress")
eq(st.contrib[1][1].points, 1 + cfg.points.level, "but the points")
r = K.addEvent(c, st, {kind = "level", level = 100}, {Cc}, 1007)
eq(r.completed, 1, "chapter 1 written")
eq(st.chapter, 2, "chapter 2 open")
eq(st.doneAt[1], 1007, "written at")
eq(K.doneCount(c, st), 1, "one written")
eq(K.chapterPct(c, st, 1), 100, "a written chapter is 100%")
r = K.addEvent(c, st, {kind = "worldboss"}, {A, B, Cc}, 1010)
check(r.matched and not r.completed, "chapter 2: the world boss")
r = K.addEvent(c, st, {kind = "rift", band = "b2"}, {A}, 1011)
eq(r.completed, 2, "chapter 2 written")
local top = K.top(st.contrib[1], 5)
eq(top[1].name, "Bryn", "top: most points")
eq(top[2].name, "Mira", "then Mira (6, reached first)")
eq(top[3].name, "Vexa", "then Vexa (6, later)")
-- ties: the earlier, then the lower guid
local tie = K.top({[9] = {name = "Late", points = 5, at = 20}, [4] = {name = "Early", points = 5, at = 10},
	[2] = {name = "Same", points = 5, at = 10}, [7] = {name = "Zero", points = 0}}, 9)
eq(#tie, 3, "no zero rows")
eq(tie[1].name .. "," .. tie[2].name .. "," .. tie[3].name, "Same,Early,Late", "ties by time, then guid")
local rows = K.recordRows(c, st, 2)
eq(#rows, 4, "record: two places per chapter with contributors")
eq(rows[1].chapter .. ":" .. rows[1].place .. ":" .. rows[1].name, "1:1:Bryn", "record row")
-- levels crossed
local st2 = K.newState(cfg, "s1", 1, 0)
eq(#K.levelsCrossed(cfg, st2, 99, 100), 1, "99 -> 100 crosses 100")
eq(#K.levelsCrossed(cfg, st2, 100, 101), 0, "100 -> 101 crosses nothing")
eq(#K.levelsCrossed(cfg, st2, 90, 99), 0, "below")
st2.chapter = 5
eq(K.levelsCrossed(cfg, st2, 590, 650)[1], 600, "chapter 5 counts level 600")
-- the records' runs
eq(K.eventsOfRun(cfg, {board = "wb_time"})[1].kind, "worldboss", "world boss run")
local ev = K.eventsOfRun(cfg, {board = "rift_tier", value = 12})[1]
eq(ev.kind .. ev.band, "riftb3", "tier 12: band b3")
eq(K.eventsOfRun(cfg, {board = "rift_tier", value = 15})[1].band, "t15", "tier 15")
eq(#K.eventsOfRun(cfg, {board = "rift_tier", value = 0}), 0, "no tier, no event")
eq(K.eventsOfRun(cfg, {board = "ascended", variant = "cinder"})[1].kind, "cinderheart", "the Cinderheart")
eq(K.eventsOfRun(cfg, {board = "ascended", variant = "bloodmoon"})[1].kind, "ascended", "an Ascended Omen")
eq(K.eventsOfRun(cfg, {board = "omen", variant = "x"})[1].kind, "omen", "an Omen guardian")
eq(#K.eventsOfRun(cfg, {board = "arena"}), 0, "the arena is no chapter goal")
eq(K.bandOf(cfg, 5), "b1", "band of 5")
eq(K.bandOf(cfg, 6), "b2", "band of 6")
-- labels
eq(K.goalLabel(cfg, {kind = "rift", band = "b2"}), "Rifts sealed, tiers 6-10", "label rift band")
eq(K.goalLabel(cfg, {kind = "rift", band = "t15"}), "Rifts sealed, tier 15", "label tier 15")
eq(K.goalLabel(cfg, {kind = "level", level = 600}), "Characters reaching level 600", "label level")
eq(K.goalLabel(cfg, {kind = "event", event = "invasion"}), "Invasions repelled", "label invasion")
eq(K.goalLabelPt(cfg, {kind = "level", level = 100}), "Personagens chegando ao nível 100", "label pt")

-- ---------------------------------------------------------------- the world
local w0 = K.worldOf(cfg, "s1", 0)
check(next(w0.open) == nil and next(w0.town) == nil and w0.flags == 0, "nothing before a chapter")
local w1 = K.worldOf(cfg, "s1", 1)
check(w1.town.ashfall and not w1.open.cinderscar_breach, "chapter 1: ash")
local w2 = K.worldOf(cfg, "s1", 2)
check(w2.town.ashfall and w2.town.rubble and w2.open.cinderscar_breach, "chapter 2: rubble and the Breach")
local w5 = K.worldOf(cfg, "s1", 5)
check(not w5.town.ashfall and not w5.town.rubble and w5.town.rebuilt and w5.town.wardfires, "chapter 5: rebuilt")
check(w5.open.cinderscar_breach and w5.open.ossuary_stair and w5.flags == 5, "both areas open after five")
local d = K.worldDiff(w2, w5)
eq(table.concat(d.addSets, ","), "rebuilt,wardfires", "diff: sets to add")
eq(table.concat(d.removeSets, ","), "ashfall,rubble", "diff: sets to remove")
eq(table.concat(d.openAreas, ","), "ossuary_stair", "diff: area to open")
local back = K.worldDiff(w5, w0)
eq(table.concat(back.closeAreas, ","), "cinderscar_breach,ossuary_stair", "reset: every area closes")
eq(table.concat(back.removeSets, ","), "rebuilt,wardfires", "reset: every set goes")
eq(#K.worldDiff(w5, w5).addSets + #K.worldDiff(w5, w5).removeSets, 0, "no diff from itself")
-- areas
check(K.arrivalOf(cfg.areas[1]) == nil, "an area without `at` has no arrival")
local placed = {key = "x", at = {x = 1000, y = 2000, z = 7}, arrival = {31, 40, 0}, gate = {x = 5, y = 6, z = 7}}
local ar = K.arrivalOf(placed)
check(ar and ar.x == 1031 and ar.y == 2040 and ar.z == 7, "arrival = at + offset")
check(K.gateOf(placed).x == 5 and K.gateOf({gate = {1, 2}}) == nil, "the gate")

-- ---------------------------------------------------------------- payload and texts
local pl = K.payload(c, TXT, st, {now = 5, seasonName = "Season of Ash", tops = {[1] = {{name = "Bryn", points = 5}}},
	mine = {[1] = 6}, areaReady = {cinderscar_breach = false}})
eq(#pl.chapters, 5, "payload: five chapters")
eq(pl.chapters[1].state, "done", "chapter 1 done")
eq(pl.chapters[3].state, "open", "chapter 3 open")
eq(pl.chapters[4].state, "locked", "chapter 4 locked")
check(pl.chapters[4].text == nil and pl.chapters[3].text and #pl.chapters[3].text.pt == 2, "locked chapters keep their text")
check(pl.chapters[2].world and pl.chapters[2].world.pt, "a written chapter says what changed")
eq(pl.chapters[2].pending and pl.chapters[2].pending[1], "cinderscar_breach", "an unplaced area is pending")
eq(pl.chapters[1].top[1].n, "Bryn", "payload top")
eq(pl.chapters[1].mine, 6, "payload: own points")
eq(pl.chapters[1].goals[2].t, 3, "payload goal target")
eq(pl.done, 2, "payload: chapters written")
check(pl.title.pt:find("Crônica das Cinzas"), "the title in Portuguese")
check(K.payload(cfg, TXT, nil, {seasonName = ""}).active == false, "no season: inactive payload")
check(K.chapterText(TXT, "s1", 2, "en"):find("Cinderscar Breach"), "chapter 2 broadcast")
check(K.loginLine(c, TXT, st):find("III%. Omens in the Ashfall is open"), "login line")
local dr = K.discordRow(c, TXT, st, 1, {{name = "Bryn"}, {name = "Vexa"}})
check(dr.kind == "chronicle" and dr.channel == "announce" and dr.title:find("I%. The Ash Thickens"), "Discord row")
eq(dr.fields[2].value, "Bryn, Vexa", "Discord row: who carried it")
check(K.discordSeasonRow(c, TXT, st, true).text:find("closes the book"), "Discord row of the season's end")
eq(K.fmt(1234567), "1,234,567", "fmt")

-- ---------------------------------------------------------------- the Codex / wiki pages (tools/chronicle_pages.lua)
local CP = dofile("tools/chronicle_pages.lua")
local pages = CP.entries("#c9a27a")
eq(#pages, 1 + #arc.chapters + 1, "pages: the overview, every chapter, the Memorial")
local pageIds = {}
for _, e in ipairs(pages) do
	check(not pageIds[e.id], "page id " .. e.id .. " once")
	pageIds[e.id] = true
	check(e.id:match("^lore:") and e.group == "chronicle" and e.f.group == "chronicle" and e.color == "#c9a27a", e.id .. ": a Lore entry")
	local pt = false
	for _, sec in ipairs(e.sections) do
		pt = pt or sec.h == "Em portugu\195\170s"
		for _, para in ipairs(sec.p or {}) do
			noDash(para, e.id)
		end
	end
	check(pt, e.id .. ": a Portuguese section")
end
check(pageIds["lore:chronicle_s1_2"] and pages[3].name == "II. The Wound Beside the Walls", "chapter pages in order")
check(pages[3].sections[2].rows[1][1] == "World bosses slain" and pages[3].sections[2].rows[1][2] == "30", "the goals table")
check(pages[3].sections[4].p[1]:find("The Cinderscar Breach opens %(level 400"), "what changes: the area")
eq(CP.KIND.key, "chronicle", "the Lore kind")

-- ---------------------------------------------------------------- chronicle.lua against a mocked engine
local registry, globals, talks, moves = {}, {}, {}, {}
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
function TalkAction(words)
	local o = {}
	function o:separator() end
	function o:register() talks[words] = o end
	return o
end
function MoveEvent()
	local o = {aids = {}}
	function o:type() end
	function o:aid(...) for _, a in ipairs({...}) do self.aids[#self.aids + 1] = a end end
	function o:register() moves[#moves + 1] = o end
	return o
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
local selectRows = function() return {} end
Chaos.select = function(qq, cols) return selectRows(qq) or {} end
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "{}" end, decode = function(s) return s end}
Chaos.decode = function(b) return type(b) == "table" and b or nil end
local clock = 1800000000
local realTime = os.time
os.time = function(tt) if tt then return realTime(tt) end return clock end
local broadcasts, globalStore = {}, {}
-- the map: tiles by "x,y,z"
local tiles = {}
local function tkey(p) return p.x .. "," .. p.y .. "," .. p.z end
Position = function(x, y, z)
	return {x = x, y = y, z = z, sendMagicEffect = function() end}
end
local function mkItem(id, pos)
	local it = {id = id, pos = pos, attrs = {}}
	function it:getId() return self.id end
	function it:getActionId() return self.aid or 0 end
	function it:setActionId(a) self.aid = a end
	function it:setAttribute(k, v) self.attrs[k] = v end
	function it:transform(nid) self.id = nid end
	function it:remove()
		local t = tiles[tkey(self.pos)]
		for i, x in ipairs(t.items) do
			if x == self then table.remove(t.items, i) return true end
		end
	end
	return it
end
local function mkTile(x, y, z, blocked)
	local t = {items = {}, blocked = blocked}
	t.ground = mkItem(100, {x = x, y = y, z = z})
	tiles[x .. "," .. y .. "," .. z] = t
	return t
end
for x = 80, 120 do
	for y = 80, 120 do
		mkTile(x, y, 7, (x == 96 and y == 97)) -- one wall west of the temple
	end
end
mkTile(500, 500, 7) -- the Breach's gate
Tile = function(pos)
	local t = tiles[tkey(pos)]
	if not t then return nil end
	return {getGround = function() return t.ground end,
		hasProperty = function(_, p) return t.blocked == true end,
		getTopCreature = function() return nil end, hasFlag = function() return false end,
		getItems = function() local c2 = {} for i, x in ipairs(t.items) do c2[i] = x end return c2 end}
end
Game = {
	broadcastMessage = function(text) broadcasts[#broadcasts + 1] = text end,
	setStorageValue = function(k, v) globalStore[k] = v end,
	getStorageValue = function(k) return globalStore[k] end,
	createItem = function(id, nn, pos)
		local t = tiles[tkey(pos)]
		if not t then return nil end
		local it = mkItem(id, {x = pos.x, y = pos.y, z = pos.z})
		t.items[#t.items + 1] = it
		return it
	end
}
Town = function(id) return id == 1 and {getTemplePosition = function() return {x = 100, y = 100, z = 7} end} or nil end
local players = {}
local nextId = 1000
local function mkPlayer(name, guid, group, level)
	nextId = nextId + 1
	local p = {id = nextId, name = name, guid = guid, group = group or 1, level = level or 300, msgs = {}, ops = {}, events = {},
		pos = Position(100, 100, 7)}
	function p:getId() return self.id end
	function p:getGuid() return self.guid end
	function p:getName() return self.name end
	function p:getLevel() return self.level end
	function p:isPlayer() return true end
	function p:getPlayer() return self end
	function p:getGroup() local g = self.group return {getId = function() return g end, getAccess = function() return g >= 4 end} end
	function p:getPosition() return self.pos end
	function p:teleportTo(pos) self.pos = Position(pos.x, pos.y, pos.z) end
	function p:sendCancelMessage(t) self.cancel = t end
	function p:sendTextMessage(_, text) self.msgs[#self.msgs + 1] = text end
	function p:sendExtendedOpcode(op, data) self.ops[#self.ops + 1] = {op, data} return true end
	function p:registerEvent(ev) self.events[ev] = true end
	players[#players + 1] = p
	return p
end
Player = function(x)
	if type(x) == "table" then return x end
	for _, p in ipairs(players) do
		if p.id == x or p.name == x or p.guid == x then return p end
	end
	return nil
end
local season = {id = 1, name = "Season of Ash"}
ChaosSeason = {current = function() return season end}
Chaos.seasonConfig = {seasons = {{id = 1, name = "Season of Ash"}, {id = 2, name = "Season of Embers"}}}
local submitOk = true
ChaosRecords = {submit = function(run) return submitOk, "slot" end}
local achieved = {}
ChaosAchievements = {progress = function(who, key, amount) achieved[#achieved + 1] = key return true end}
local raidRun = {}
ChaosRaid = {runOf = {}}
local delivered = 0
ChaosInvasion = {deliver = function(player, r) delivered = delivered + 1 end}
local discordRows = {}
ChaosDiscord = {queue = function(ev) discordRows[#discordRows + 1] = {kind = ev.kind, row = ev} return true end}
ChaosDiscordConfig = {channels = {chronicle = "announce"}}
local hidden = {}
ChaosMemorial = {showsRecords = function(guid) return not hidden[guid] end}
local logged = {}
local print_ = print
print = function(s) logged[#logged + 1] = s end
dofile("data/scripts/chaos/chronicle.lua")
local X = ChaosChronicle
local XC = Chaos.chronicleConfig -- the live config (tests shrink the targets)
check(registry.ChaosChronicleLogin and registry.ChaosChronicleExtended and registry.ChaosChronicleAdvance and
	registry.ChaosChronicleLogout, "events registered")
eq(registry.ChaosChronicleAdvance.t, "advance", "the advance event")
check(talks["/chronicle"] and moves[1] and moves[1].aids[1] == 47920 and moves[1].aids[2] == 47921, "staff command and gates")
eq(ChaosOpcodes.chronicle, 171, "ChaosOpcodes.chronicle")
check(ChaosWrapChain.has(ChaosAchievements.progress, "chronicle"), "the raid hook is on at load")
-- a second install wraps nothing again
X.installHooks()
check(ChaosWrapChain.has(ChaosRecords.submit, "chronicle"), "records hook on")
local afterOnce = ChaosRecords.submit
X.installHooks()
eq(ChaosRecords.submit, afterOnce, "installed only once")
-- shrink the targets for the test
local s1 = XC.chapters.s1
s1[1].goals[1].target, s1[1].goals[2].target = 2, 2
s1[2].goals[1].target, s1[2].goals[2].target = 1, 1
s1[4].goals[1].target, s1[4].goals[2].target = 1, 1
-- startup: tables, a new season state, the intro
globals.ChaosChronicleStartup.onStartup()
check(queried("CREATE TABLE IF NOT EXISTS `chaos_chronicle_state`") and queried("chaos_chronicle_levels") and
	queried("CREATE TABLE IF NOT EXISTS `chaos_chronicle_chapters`"), "tables created")
check(X.state and X.state.season == 1 and X.state.arc == "s1" and X.state.chapter == 1, "season 1: the Chronicle begins")
check(broadcasts[1] and broadcasts[1]:find("The Ashen Chronicle"), "the intro broadcast")
check(queried("INSERT INTO `chaos_chronicle_state`.-%(1, 's1', 1, 0"), "the state row")
eq(discordRows[1] and discordRows[1].kind, "chronicle", "a Discord row at the start")
eq(globalStore[7102110], 0, "flag: nothing written")
eq(globalStore[7102111], 1, "flag: the season")
-- logins
local hero = mkPlayer("Hero", 501, 1, 99)
local mira = mkPlayer("Mira", 502, 1, 300)
local gm = mkPlayer("Gamemaster", 900, 5, 99)
registry.ChaosChronicleLogin.onLogin(hero)
check(hero.events.ChaosChronicleExtended and hero.events.ChaosChronicleAdvance, "player events at login")
check(hero.msgs[1] and hero.msgs[1]:find("I%. The Ash Thickens is open"), "login line")
-- a Portuguese player: the login line in Portuguese (i18n.lua's Chaos.lang)
local luso = mkPlayer("Luso", 504, 1, 99)
Chaos.lang = function(p) return p == luso and "pt-BR" or "en" end
registry.ChaosChronicleLogin.onLogin(luso)
check(luso.msgs[1] and luso.msgs[1]:find("I%. As Cinzas se Adensam está aberto") and luso.msgs[1]:find("Aventura > Crônica"),
	"login line in Portuguese")
-- broadcasts go out in each player's language when i18n.lua is there
local perLang = {}
Chaos.broadcast = function(kind, fn) perLang.en, perLang.pt = fn("en"), fn("pt-BR") broadcasts[#broadcasts + 1] = perLang.en return perLang.en end
-- records: a sealed tier 3 rift with Hero and Mira; a refused run counts nothing
ChaosRecords.submit({board = "rift_tier", value = 3, members = {hero, mira}})
eq(X.state.progress[1][2], 1, "the rift counted")
eq(X.state.contrib[1][501].points, 1, "Hero's point")
submitOk = false
ChaosRecords.submit({board = "rift_tier", value = 3, members = {hero}})
eq(X.state.progress[1][2], 1, "a refused run counts nothing")
submitOk = true
ChaosRecords.submit({board = "rift_tier", value = 9, members = {hero}})
eq(X.state.progress[1][2], 1, "another band counts nothing")
-- members by guid only: the name comes from the database
selectRows = function(qq)
	if qq:find("FROM `players` WHERE `id` IN %(777%)") then return {{id = 777, name = "Offline Olga"}} end
	return {}
end
ChaosRecords.submit({board = "rift_tier", value = 2, members = {777}})
eq(X.state.contrib[1][777].name, "Offline Olga", "a member by guid gets its name")
eq(X.state.progress[1][2], 2, "rift goal met")
selectRows = function() return {} end
-- levels: Hero 99 -> 100 counts once; the GM never
registry.ChaosChronicleAdvance.onAdvance(gm, SKILL_LEVEL, 99, 100)
eq(X.state.progress[1][1], 0, "staff never count")
registry.ChaosChronicleAdvance.onAdvance(hero, SKILL_LEVEL, 99, 100)
eq(X.state.progress[1][1], 1, "Hero reached 100")
check(queried("INSERT IGNORE INTO `chaos_chronicle_levels`.-%(1, 501, 100%)"), "the level row")
registry.ChaosChronicleAdvance.onAdvance(hero, SKILL_LEVEL, 99, 100) -- died and levelled again
eq(X.state.progress[1][1], 1, "a character counts once")
registry.ChaosChronicleAdvance.onAdvance(hero, SKILL_MAGLEVEL or 999, 99, 100)
eq(X.state.progress[1][1], 1, "magic level is no level")
local nb = #broadcasts
registry.ChaosChronicleAdvance.onAdvance(mira, SKILL_LEVEL, 98, 101)
-- chapter 1 written
eq(X.state.chapter, 2, "chapter 1 written")
check(broadcasts[nb + 1] and broadcasts[nb + 1]:find("first chapter of the Ashen Chronicle is written"), "the chapter broadcast")
check(perLang.pt and perLang.pt:find("O primeiro capítulo da Crônica das Cinzas está escrito"), "the chapter broadcast in Portuguese")
check(perLang.en and perLang.en:find("The first chapter"), "and in English")
Chaos.broadcast = nil
eq(globalStore[7102101], 1, "flag: chapter 1")
eq(globalStore[7102102], 0, "flag: not chapter 2")
eq(globalStore[7102110], 1, "flag: one chapter written")
local ash = 0
for _, t in pairs(tiles) do
	for _, it in ipairs(t.items) do
		if it.aid == 47929 and (it.id == 2249 or it.id == 7349 or it.id == 22509 or it.id == 25834) then ash = ash + 1 end
	end
end
eq(ash, #XC.town.sets.ashfall.pieces, "the ashfall placed around the temple")
check(discordRows[#discordRows].row.title:find("I%. The Ash Thickens"), "the Discord row of the chapter")
check(queried("INSERT INTO `chaos_chronicle_progress`.-%(1, 1, 1, 'Characters reaching level 100', 2, 2, " .. clock), "progress rows")
check(queried("INSERT INTO `chaos_chronicle_chapters`.-%(1, 1, 'ash_thickens', 'I%. The Ash Thickens', 'I%. As Cinzas se Adensam', 'Ash drifts"),
	"the chapter row for the website, with what changed")
check(queried("INSERT INTO `chaos_chronicle_chapters`.-%(1, 3, 'omens_ashfall', 'III%. Omens in the Ashfall', '.-', '', '', 0%)"),
	"an unwritten chapter's row says nothing about the world")
-- the window: open, privacy of the top list
hidden[777] = true
sent = {}
registry.ChaosChronicleExtended.onExtendedOpcode(hero, 171, {action = "open"})
local state = sent[#sent] and sent[#sent].data
check(state and state.action == nil and sent[#sent].action == "state", "the state goes out")
state = sent[#sent].data
eq(state.chapters[1].state, "done", "window: chapter 1 done")
local names = {}
for _, e in ipairs(state.chapters[1].top) do names[#names + 1] = e.n end
check(table.concat(names, ","):find("A hero who keeps their name"), "a hidden name stays hidden")
check(not table.concat(names, ","):find("Olga"), "and is not sent")
eq(state.chapters[1].mine, X.state.contrib[1][501].points, "own points")
eq(hero.ops[#hero.ops][1], 171, "on opcode 171")
registry.ChaosChronicleExtended.onExtendedOpcode(hero, 170, {action = "open"})
eq(#sent, 1, "another opcode is ignored")
-- chapter 2: the world boss and a tier 7 rift; the Breach is not placed yet
ChaosRecords.submit({board = "wb_time", value = 300, members = {hero, mira}})
ChaosRecords.submit({board = "rift_tier", value = 7, members = {mira}})
eq(X.state.chapter, 3, "chapter 2 written")
check(X.world.open.cinderscar_breach, "the Breach is open in the story")
local warned = false
for _, l in ipairs(logged) do warned = warned or l:find("The Cinderscar Breach is open in the story but not placed") ~= nil end
check(warned, "the console says the area is not placed")
-- the owner places it: the next tick puts the gate portal
XC.areas[1].at = {x = 2000, y = 2000, z = 7}
XC.areas[1].gate = {x = 500, y = 500, z = 7}
globals.ChaosChronicleTick.onThink(60000)
local gateItem = tiles["500,500,7"].items[1]
check(gateItem and gateItem.id == 1387 and gateItem.aid == 47920, "the gate portal")
-- stepping in: below the level, then the arrival
local low = mkPlayer("Lowbie", 503, 1, 50)
moves[1].onStepIn(low, gateItem, Position(500, 500, 7), Position(500, 501, 7))
check(low.pos.y == 501 and low.cancel:find("level 400"), "too low: pushed back")
moves[1].onStepIn(hero, gateItem, Position(500, 500, 7), Position(500, 501, 7))
hero.level = 450
moves[1].onStepIn(hero, gateItem, Position(500, 500, 7), Position(500, 501, 7))
check(hero.pos.x == 2063 and hero.pos.y == 2082, "the arrival of the Breach")
-- chapter 3: the Omens; the raid comes through its clear, once per run
ChaosRecords.submit({board = "raid", value = 900, members = {hero}})
eq(X.state.progress[3][1], 0, "the records' raid board does not count (the clear does)")
-- raid in chapter 4: jump there with the staff command (group 5)
local god = mkPlayer("God", 901, 6)
talks["/chronicle"].onSay(god, "/chronicle", "complete")
eq(X.state.chapter, 4, "staff: chapter 3 written")
ChaosRaid.runOf[hero.id] = raidRun
ChaosRaid.runOf[mira.id] = raidRun
ChaosAchievements.progress(hero, "raid_clears", 1)
ChaosAchievements.progress(mira, "raid_clears", 1)
eq(X.state.progress[4][1], 1, "one raid run, counted once")
eq(X.state.contrib[4][502].points, XC.points.raid, "every member gets the points")
ChaosAchievements.progress(hero, "raid_kills", 1)
eq(#achieved, 3, "achievements still run")
-- chapter 4's Ascended
ChaosRecords.submit({board = "ascended", variant = "bloodmoon", value = 200, members = {hero}})
eq(X.state.chapter, 5, "chapter 4 written")
check(X.world.open.ossuary_stair, "the Ossuary Stair opens (story)")
-- chapter 5: invasions count once per invasion and not on a liberation
s1[5].goals[3].target = 2
ChaosInvasion.deliver(hero, {areaName = "North Gate", liberation = false})
ChaosInvasion.deliver(mira, {areaName = "North Gate", liberation = false})
eq(delivered, 2, "the invasion still delivers")
eq(X.state.progress[5][3], 1, "one invasion")
ChaosInvasion.deliver(hero, {areaName = "East Gate", liberation = true})
eq(X.state.progress[5][3], 1, "a liberation is no repelled invasion")
ChaosInvasion.deliver(gm, {areaName = "West Gate"})
eq(X.state.progress[5][3], 1, "staff deliveries count nothing")
-- ChaosChronicle.event: the public API
X.event("invasion", {hero})
eq(X.state.progress[5][3], 2, "the event API")
-- a restart: the world is placed again from the tables
local savedState = X.state
X.world = {open = {}, town = {}}
for _, t in pairs(tiles) do t.items = {} end
X.applyWorld()
local rubble = 0
for _, t in pairs(tiles) do
	for _, it in ipairs(t.items) do
		if it.aid == 47929 then rubble = rubble + 1 end
	end
end
check(rubble > 0 and tiles["500,500,7"].items[1] and tiles["500,500,7"].items[1].aid == 47920, "a restart places the world again")
-- the season ends: the record, the world stays
X.flush()
local q0 = #queries
season = nil
globals.ChaosChronicleTick.onThink(60000)
check(X.state == nil and X.idle and X.idle.done == 4, "the season ended: idle with 4 chapters written")
check(queried("INSERT IGNORE INTO `chaos_chronicle_record`.-%(1, 1, 1, ", q0), "the record rows")
check(queried("`finished_at`", q0), "the state finished")
check(tiles["500,500,7"].items[1] ~= nil, "the world stays between seasons")
local closing = false
for _, b in ipairs(broadcasts) do closing = closing or b:find("closes the book") ~= nil end
check(closing, "the closing broadcast")
-- the next season with an arc: the world resets
XC.arcs[2] = "s1"
season = {id = 2, name = "Season of Embers"}
selectRows = function() return {} end
globals.ChaosChronicleTick.onThink(60000)
check(X.state and X.state.season == 2 and X.state.chapter == 1, "season 2 begins")
eq(#tiles["500,500,7"].items, 0, "the gate portal is gone")
local left = 0
for _, t in pairs(tiles) do
	for _, it in ipairs(t.items) do
		if it.aid == 47929 then left = left + 1 end
	end
end
eq(left, 0, "every decoration is gone")
eq(globalStore[7102101], 0, "flags reset")
eq(globalStore[7102111], 2, "flag: season 2")
-- a season that ended while the server was down is finished at the next start
local q2 = #queries
selectRows = function(qq)
	if qq:find("WHERE `finished_at` = 0 AND `season` <> 2") then return {{season = 1}} end
	if qq:find("SELECT `arc`, `chapter`, `started_at`, `finished_at` FROM `chaos_chronicle_state` WHERE `season` = 1") then
		return {{arc = "s1", chapter = 3, started_at = 1, finished_at = 0}}
	end
	if qq:find("FROM `chaos_chronicle_contrib` WHERE `season` = 1") then
		return {{chapter = 1, player_id = 501, name = "Hero", points = 7, updated_at = 1}}
	end
	return {}
end
X.finishOld()
check(queried("INSERT IGNORE INTO `chaos_chronicle_record`.-%(1, 1, 1, 501, 'Hero', 7, ", q2), "an old season's record at startup")
eq(X.state.season, 2, "the running season stays")
selectRows = function() return {} end
-- staff command: status works for a counsellor, complete needs group 5
local tutor = mkPlayer("Tutor", 902, 4)
talks["/chronicle"].onSay(tutor, "/chronicle", "status")
check(tutor.msgs[1] and tutor.msgs[1]:find("season 2, arc s1: chapter 1 of 5"), "status")
talks["/chronicle"].onSay(tutor, "/chronicle", "complete")
check(tutor.msgs[#tutor.msgs]:find("needs group 5"), "complete needs group 5")
eq(X.state.chapter, 1, "nothing written by a counsellor")
-- a broken hook never breaks the wrapped function
local ok = pcall(ChaosRecords.submit, {board = "rift_tier", value = "nonsense", members = {{}}})
check(ok, "a strange run does not raise")
print = print_

print(string.format("chronicle_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
