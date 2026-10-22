-- Run from the server/ folder: luajit tests/tales_test.lua (CI runs it with luajit and lua5.3)
-- Covers the tales (tales_core.lua, tales_config.lua), the lore data (lore_data.lua) and tales.lua against a mocked
-- engine: config sanity (storages in the blocks, both languages, monsters that exist, places on the hunting marks,
-- NPCs of ours), language choice, states, kill credit (type and shown name, steps, party share, no double credit),
-- visit and talk steps, chains, accept and turn in (next to the NPC only, deliveries), rewards (experience share capped
-- at the band, bank, items, faction hook, the lore book) and the windows.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/tales_core.lua")
local M = ChaosTalesCore
local cfg = M.cfg()
local lore = M.lore()

-- ------------------------------------------------------------------ config and lore data
eq(type(cfg), "table", "config loaded")
eq(#M.problems(), 0, "config sound: " .. table.concat(M.problems(), "; "))
local seen, slots = {}, {}
local function noDash(s, what) assert(not tostring(s):find("\226\128\148", 1, true), "no em dash: " .. what) end
for _, t in ipairs(cfg.tales) do
	assert(not slots[t.slot], "slot used once: " .. t.key); slots[t.slot] = true
	for _, k in ipairs({M.stateKey(t), M.countKey(t)}) do
		local inBase = k > cfg.storage.base and k <= cfg.storage.last
		local inExt = k >= cfg.storage.ext.base and k <= cfg.storage.ext.last
		assert(inBase or inExt, "storage in the blocks: " .. t.key)
		assert(not (k >= 7101550 and k <= 7101559), "not the first hour's block: " .. t.key)
		assert(not seen[k], "storage distinct"); seen[k] = true
	end
	assert(t.name.en and t.name.pt and t.story.en and t.story.pt, "both languages: " .. t.key)
	assert(t.outro.en and t.outro.pt, "outro in both languages: " .. t.key)
	noDash(t.story.en .. t.story.pt .. t.outro.en .. t.outro.pt, t.key)
	for _, s in ipairs(t.steps) do
		assert(s.text.en and s.text.pt, "step text in both languages: " .. t.key)
		assert(M.KINDS[s.kind], "known step kind " .. tostring(s.kind))
		if s.kind == "kill" then assert(s.count >= 1 and #s.monsters >= 1, "kill step") end
		if s.kind == "talk" then
			assert(s.reply.en and s.reply.pt, "talk reply in both languages: " .. t.key); noDash(s.reply.en .. s.reply.pt, t.key)
		end
	end
	assert(not M.FIELD[t.steps[#t.steps].kind], "ends at the Archivist: " .. t.key)
	if t.rewards.book then assert(M.loreEntry(t.rewards.book), "the book exists: " .. t.key) end
	assert(cfg.factions[t.faction], "faction known: " .. t.key)
	assert(t.band[1] <= t.minLevel and t.band[2] > t.minLevel, "band: " .. t.key)
	assert(t.rewards.xpLevels > 0 and t.rewards.xpLevels <= 1 and t.rewards.gold > 0 and t.rewards.rep > 0, "rewards: " .. t.key)
end
assert(not seen[M.langKey()], "language storage distinct"); assert(M.langKey() == cfg.storage.base)
assert(#cfg.tales >= 25, "the tales of 2026-10-22: at least 21 more than the first 4")
for k, v in pairs(cfg.ui) do assert(v.en and v.pt, "ui text " .. k .. " in both languages") end

-- the storage layout: slots 1-19 in the first block, 20 on in the second (never moved: a slot keeps its storages)
eq(M.stateKey({slot = 1}), 7101502); eq(M.countKey({slot = 1}), 7101522)
eq(M.stateKey({slot = 19}), 7101520); eq(M.countKey({slot = 19}), 7101540)
eq(M.stateKey({slot = 20}), 7101560); eq(M.countKey({slot = 20}), 7101580)
eq(M.stateKey({slot = 39}), 7101579); eq(M.countKey({slot = 39}), 7101599)
eq(M.stateKey(M.tale("bone_choir")), 7101502, "the first tales keep their storages")
eq(M.stateKey(M.tale("last_ember")), 7101505); eq(M.countKey(M.tale("last_ember")), 7101525)

-- every band from 8 to 2000 has a tale; low and mid levels the most
local bands = {{8, 100}, {100, 300}, {300, 700}, {700, 1300}, {1300, 2000}}
for _, b in ipairs(bands) do
	local n = 0
	for _, t in ipairs(cfg.tales) do if t.minLevel >= b[1] and t.minLevel < b[2] or (b[2] == 2000 and t.minLevel == 2000) then n = n + 1 end end
	assert(n >= 3, "tales in " .. b[1] .. "-" .. b[2] .. ": " .. n)
end
local low = 0
for _, t in ipairs(cfg.tales) do if t.minLevel < 200 then low = low + 1 end end
assert(low >= 12, "most new tales below 200: " .. low)
-- chains: at least four tales need another first
local chained = 0
for _, t in ipairs(cfg.tales) do if t.requires then chained = chained + 1 end end
assert(chained >= 4, "chains")

-- the problems the check finds
local badCfg = {storage = cfg.storage, tales = {
	{key = "a", slot = 1, minLevel = 10, steps = {{kind = "kill", count = 1, monsters = {"Rat"}}}},
	{key = "b", slot = 1, minLevel = 5, requires = "a", steps = {{kind = "visit"}, {kind = "talk", npc = "X"}, {kind = "fly"},
		{kind = "report"}}},
	{key = "c", slot = 2, minLevel = 5, requires = "nope", steps = {{kind = "deliver", items = {}}}}}}
local probs = table.concat(M.problems(badCfg), "\n")
for _, want in ipairs({"a: the last step must be done at the Archivist", "b: slot used twice", "b: step 1: a visit needs pos",
	"b: step 2: a talk needs npc and reply", "b: step 3 kind fly", "b: requires a tale of a higher level",
	"c: requires an unknown tale nope", "c: step 1: a delivery needs items"}) do
	assert(probs:find(want, 1, true), "problem found: " .. want)
end

-- every visit is at a hunting mark of the map (data/chaos_poi.lua); every talk names one of our NPCs (data/npc)
local poi = dofile("data/chaos_poi.lua")
for _, t in ipairs(cfg.tales) do
	for _, s in ipairs(t.steps) do
		if s.kind == "visit" then
			local hits = {}
			for _, m in ipairs(poi.marks) do
				if (m.k == "hunt" or m.k == "boss") and M.atPlace(s, m) then hits[#hits + 1] = m.n end
			end
			assert(#hits > 0, "the place of " .. t.key .. " is a hunting mark")
			-- the mark's monsters are the next kill step's
			local nextKill
			for i, o in ipairs(t.steps) do if o == s then nextKill = t.steps[i + 1] end end
			if nextKill and nextKill.kind == "kill" then
				local any, names = false, table.concat(hits, "; ")
				for _, mon in ipairs(nextKill.monsters) do any = any or names:find(mon, 1, true) ~= nil end
				assert(any, "the place of " .. t.key .. " holds the monsters of its kill step")
			end
		elseif s.kind == "talk" then
			local f = io.open("data/npc/" .. s.npc .. ".xml", "r")
			assert(f, "the NPC exists: " .. s.npc); f:close()
			local factions = dofile("data/scripts/chaos/factions_config.lua")
			local mine = false
			for _, fa in ipairs(factions.factions) do mine = mine or fa.npc.name == s.npc end
			assert(mine, "a faction NPC (its script does the talk step): " .. s.npc)
		end
	end
end

local ids = {}
for _, e in ipairs(lore.entries) do
	assert(not ids[e.id], "lore id once: " .. e.id); ids[e.id] = true
	assert(e.name and #e.en > 0 and #e.pt > 0 and #e.keywords > 0, "lore entry " .. e.id)
	local n1, n2 = 0, 0
	for _, p in ipairs(e.en) do n1 = n1 + #p; assert(not p:find("\226\128\148"), "no em dash: " .. e.id) end
	for _, p in ipairs(e.pt) do n2 = n2 + #p; assert(not p:find("\226\128\148"), "no em dash: " .. e.id) end
	assert(n1 <= 900 and n2 <= 900, "short enough for a book: " .. e.id)
	local kindOk = false
	for _, k in ipairs(lore.kinds) do kindOk = kindOk or k.key == e.kind end
	assert(kindOk, "kind known: " .. e.id)
	local title, text = M.book(e.id, "pt")
	assert(title == e.name and #text <= 1023, "book fits: " .. e.id)
end
-- the main bosses, rifts and Omens have an entry
for _, id in ipairs({"cinders", "rifts", "rift_abyssal", "rift_obsidian", "rift_ashen", "rift_sanctum", "omens", "omen_bloodmoon",
	"omen_hollow", "omen_storm", "omen_ascended", "cinderheart", "sepulchre", "wb_kaelgor", "wb_skaldra", "wb_rotmother",
	"wb_nyxareth", "wb_vharok", "descent", "deep_wardens"}) do
	assert(ids[id], "lore for " .. id)
end

-- every kill target is a monster of our data (a monster file or the bounty pool) or a shown boss name of our configs
local function readAll(path)
	local f = io.open(path, "rb"); if not f then return "" end
	local s = f:read("*a"); f:close(); return s
end
local pool = readAll("data/scripts/chaos/bounty_pool.lua")
local areagen = readAll("data/scripts/chaos/areagen_config.lua")
local ls = io.popen("ls data/monster/monsters/chaos/*/*.xml data/monster/monsters/chaos/*.xml 2>/dev/null")
local monsterFiles = ls and ls:read("*a") or ""
if ls then ls:close() end
local function known(name)
	if pool:find('name = "' .. name .. '"', 1, true) or areagen:find('name = "' .. name .. '"', 1, true) then return true end
	for path in monsterFiles:gmatch("[^\n]+") do
		if readAll(path):find('<monster name="' .. name .. '"', 1, true) then return true end
	end
	return false
end
for _, t in ipairs(cfg.tales) do
	for _, s in ipairs(t.steps) do
		for _, m in ipairs(s.monsters or {}) do assert(known(m), "monster known: " .. m) end
	end
end

-- ------------------------------------------------------------------ language
eq(M.lang(-1, nil), "en"); eq(M.lang(2, nil), "pt"); eq(M.lang(1, "pt"), "pt", "the hook wins"); eq(M.lang(2, "en"), "en")
eq(M.lang(2, "pt-BR"), "pt"); eq(M.langCode("pt"), 2); eq(M.langCode("en"), 1)
eq(M.langWord("Português, por favor"), "pt"); eq(M.langWord("portugues"), "pt"); eq(M.langWord("english please"), "en")
eq(M.langWord("inglês"), "en"); eq(M.langWord("hello"), nil)
eq(M.t({en = "a", pt = "b"}, "pt"), "b"); eq(M.t({en = "a"}, "pt"), "a"); eq(M.t("x", "pt"), "x")
assert(M.asksTales("any tales?") and M.asksTales("quero uma missão") and M.asksTales("histórias") and not M.asksTales("hi"))
eq(M.loreFor("tell me about sangrith").id, "omen_bloodmoon"); eq(M.loreFor("o coração de brasa").id, "cinderheart")
eq(M.loreFor("the weather"), nil)
assert(M.loreTopics("en"):find("cinders", 1, true))

-- ------------------------------------------------------------------ states and steps
local choir, tithe, requiem, ember = M.tale("bone_choir"), M.tale("wyrm_tithe"), M.tale("ash_requiem"), M.tale("last_ember")
assert(choir and tithe and requiem and ember)
eq(M.state(choir, -1), 0); eq(M.state(choir, 1), 1); eq(M.state(choir, 9), 2, "clamped to the steps"); eq(M.state(choir, 100), 100)
eq(M.status(choir, 0), "new"); eq(M.status(choir, 1), "on"); eq(M.status(choir, 2), "ready"); eq(M.status(choir, 100), "done")
eq(M.status(tithe, 2), "ready", "a deliver step is done at the Archivist")
local ok, why = M.accept(choir, 0, 150); eq(ok, false); eq(why, "level")
ok, why = M.accept(choir, 1, 250); eq(ok, false); eq(why, "taken")
local st; ok, st = M.accept(choir, -1, 200); eq(ok, true); eq(st, 1)

-- kills: by type, by shown name, case-insensitive; other monsters do not count
local s, c, ev = M.addKill(choir, 1, 0, "Deathrattle", "Deathrattle"); eq(s, 1); eq(c, 1); eq(ev, "progress")
s, c, ev = M.addKill(choir, 1, 5, "Rat", "Rat"); eq(ev, nil); eq(c, 5)
s, c, ev = M.addKill(choir, 1, 39, "doombone", "x"); eq(ev, "step"); eq(s, 2); eq(c, 0)
s, c, ev = M.addKill(choir, 2, 0, "Doombone", "Doombone"); eq(ev, nil, "a report step takes no kill")
s, c, ev = M.addKill(choir, 0, 0, "Doombone", "Doombone"); eq(ev, nil, "not taken")
s, c, ev = M.addKill(choir, 100, 0, "Doombone", "Doombone"); eq(ev, nil, "done")
s, c, ev = M.addKill(ember, 1, 0, "Grindmaw the Mauler", "The Emberdeep Maw"); eq(ev, "step", "shown name of a deep warden"); eq(s, 2)
s, c, ev = M.addKill(ember, 1, 0, "Grindmaw the Mauler", "Grindmaw the Mauler"); eq(ev, nil, "the plain type does not count")
s, c, ev = M.addKill(ember, 2, 0, "Ascended Morvane", "Ascended Morvane"); eq(s, 3); eq(ev, "step")
s, c, ev = M.addKill(requiem, 2, 0, "Morwen the Ash-Sister", "Morwen the Ash-Sister"); eq(s, 3)

-- turn in
ok, why = M.turnIn(choir, 1, 3, nil); eq(ok, false); eq(why, "kill")
local done, take, fin
ok, done, take, fin = M.turnIn(choir, 2, 0, nil); eq(ok, true); eq(done, 100); eq(fin, true); eq(#take, 0)
local held = {[32051] = 12}
local it, short
ok, why, it, short = M.turnIn(tithe, 2, 0, function(id) return held[id] or 0 end); eq(ok, false); eq(why, "missing")
eq(it.id, 32051); eq(short, 8)
held[32051] = 25
ok, done, take, fin = M.turnIn(tithe, 2, 0, function(id) return held[id] or 0 end); eq(ok, true); eq(done, 100); eq(fin, true)
eq(take[1][1], 32051); eq(take[1][2], 20)
ok, done, take, fin = M.turnIn(ember, 3, 0, nil); eq(fin, true)
ok, why = M.turnIn(ember, 0, 0, nil); eq(ok, false); eq(why, "state")

-- rewards
eq(M.expForLevel(1), 0); eq(M.expForLevel(2), 100); eq(M.expForLevel(8), 4200)
eq(M.xpFor(1, 1), 100); eq(M.xpFor(200, 0), 0)
assert(M.xpFor(250, 0.5) > 1000000 and M.xpFor(250, 0.5) < 2000000, "half a level at 250")
eq(M.money(1234567), "1,234,567"); eq(M.money(150000), "150,000"); eq(M.money(12), "12")
local lines = M.rewardLines(choir, "pt", 200)
assert(lines[1]:find("experiência", 1, true) and lines[2]:find("150,000", 1, true), "pt reward lines")
assert(table.concat(lines, ","):find("Vigil", 1, true), "faction line")

-- the experience is measured at most at the top of the tale's band (a level 2000 character took half of ITS level)
eq(M.xpLevel(choir, 230), 230); eq(M.xpLevel(choir, 2000), 299); eq(M.xpLevel({}, 2000), 2000, "no band, no cap")
eq(M.taleXp(choir, 2000), M.xpFor(299, 0.5)); eq(M.taleXp(choir, 230), M.xpFor(230, 0.5))
local cellar = M.tale("cellar_teeth")
assert(M.taleXp(cellar, 2000) == M.xpFor(30, 1.0) and M.taleXp(cellar, 2000) < 100000, "a level 8 tale stays a level 8 tale")
assert(M.rewardLines(cellar, "en", 2000)[1]:find(M.money(M.xpFor(30, 1.0)), 1, true), "the window shows the capped number")

-- rewards against the first four: gold and orbs grow with the level, and a band's tale never pays less than one below it
local byLevel = {}
for _, t in ipairs(cfg.tales) do byLevel[#byLevel + 1] = t end
table.sort(byLevel, function(a, b) return a.minLevel < b.minLevel end)
for i = 2, #byLevel do
	local a, b = byLevel[i - 1], byLevel[i]
	if b.minLevel > a.minLevel then
		assert(b.rewards.gold >= a.rewards.gold, "gold grows with the level: " .. a.key .. " " .. b.key)
	end
	local perLevel = b.rewards.gold / b.minLevel
	assert(perLevel >= 150 and perLevel <= 3000, "gold per level like the first tales: " .. b.key)
end

-- the advance guard: a field step never ends a tale without its reward
local lone = {key = "lone", slot = 99, minLevel = 1, steps = {{kind = "kill", count = 1, monsters = {"Rat"}}}}
eq(M.advance(lone, 1), 1, "stays on its last step"); s, c, ev = M.addKill(lone, 1, 0, "Rat", "Rat"); eq(s, 1); eq(ev, "step")
eq(M.advance(choir, 1), 2); eq(M.advance(choir, 0), 0, "not taken"); eq(M.advance(choir, 100), 100, "done")

-- visit steps
local deserters = M.tale("anvildeep_deserters")
local place = deserters.steps[1].pos
eq(M.current(deserters, 1, "visit"), deserters.steps[1]); eq(M.current(deserters, 2, "visit"), nil); eq(M.current(deserters, 0, "visit"), nil)
assert(M.atPlace(deserters.steps[1], {x = place.x + 8, y = place.y - 8, z = place.z}), "within the radius")
assert(not M.atPlace(deserters.steps[1], {x = place.x + 9, y = place.y, z = place.z}), "outside the radius")
assert(not M.atPlace(deserters.steps[1], {x = place.x, y = place.y, z = place.z - 1}), "another floor")
assert(not M.atPlace(deserters.steps[2], place), "not a visit step"); assert(not M.atPlace(deserters.steps[1], nil))
s, ev = M.visit(deserters, 1, place); eq(s, 2); eq(ev, "step")
s, ev = M.visit(deserters, 1, {x = 0, y = 0, z = 7}); eq(s, 1); eq(ev, nil)
s, ev = M.visit(deserters, 2, place); eq(s, 2); eq(ev, nil, "only while the visit is the step")
s, ev = M.visit(deserters, 0, place); eq(ev, nil, "not taken")
ok, why = M.turnIn(deserters, 1, 0, nil); eq(ok, false); eq(why, "visit", "a visit is done in the field")
assert(M.visiting(function(t) return t.key == "anvildeep_deserters" and 1 or -1 end))
assert(not M.visiting(function(t) return t.key == "anvildeep_deserters" and 2 or -1 end))

-- talk steps (the NPC's script calls talkTo in its own Lua state)
local toll = M.tale("troll_toll")
local talkStates = {troll_toll = 2, lantern_road = 1, lost_souls = 2, gravecage = 1}
local function tsOf(t) return talkStates[t.key] or -1 end
local written = {}
local got = M.talkTo("forgemaster brannoc", tsOf, function(t, v) written[t.key] = v end)
eq(#got, 1, "only the tale whose current step names this NPC"); eq(got[1].tale, toll); eq(got[1].state, 3); eq(written.troll_toll, 3)
got = M.talkTo("Warden Ysolde", tsOf, function(t, v) written[t.key] = v end)
eq(#got, 2, "lantern road step 1 and lost souls step 2; the gravecage waits for its boss")
eq(written.lantern_road, 2); eq(written.lost_souls, 3); eq(written.gravecage, nil)
eq(#M.talkTo("Cantor Velith", tsOf), 0)
ok, why = M.turnIn(toll, 2, 0, nil); eq(ok, false); eq(why, "talk")

-- chains: a tale that needs another shows and opens only once that one is done
local road = M.tale("lantern_road")
eq(road.requires, "cellar_teeth")
local chainStates = {}
local function chOf(t) return chainStates[t.key] or -1 end
eq(M.unlocked(road, chOf), false); eq(M.unlocked(road, nil), false); eq(M.unlocked(cellar, nil), true)
ok, why = M.accept(road, -1, 50, chOf); eq(ok, false); eq(why, "requires")
ok, why = M.accept(road, -1, 5, chOf); eq(ok, false); eq(why, "level")
chainStates.cellar_teeth = 2
ok, why = M.accept(road, -1, 50, chOf); eq(why, "requires", "in progress is not done")
chainStates.cellar_teeth = 100
ok, st = M.accept(road, -1, 50, chOf); eq(ok, true); eq(st, 1)
local tv = M.taleView(road, 0, 0, "en", 50, function() return -1 end); eq(#tv.buttons, 0, "no accept button while locked")
tv = M.taleView(road, 0, 0, "en", 50, chOf); eq(tv.buttons[1], "accept")

-- views
local states = {}
local function stateOf(t) return states[t.key] or -1 end
local v = M.listView(5, stateOf, "en"); eq(#v.choices, 0); assert(v.text:find(" 8.", 1, true), "next level named")
v = M.listView(520, stateOf, "pt")
local open520 = 0
for _, t in ipairs(cfg.tales) do if t.minLevel <= 520 and not t.requires then open520 = open520 + 1 end end
eq(#v.choices, open520, "the tales of the level, chains closed")
assert(v.choices[1].label:find("Dentes", 1, true), "by level: the cellars first")
for _, ch in ipairs(v.choices) do assert(M.tale(ch.key).minLevel <= 520) end
states.ash_requiem = 1
states.cellar_teeth = 100
v = M.listView(520, stateOf, "en"); eq(#v.choices, open520 + 2, "a taken tale shows below its level too; the chain opens")
eq(v.choices[1].key, "ash_requiem", "in progress first"); eq(v.choices[#v.choices].key, "cellar_teeth", "done last")
eq(v.choices[2].key, "lantern_road", "the chain's next tale, by level")
v = M.listView(5000, function() return -1 end, "en")
eq(#v.choices, #cfg.tales - chained, "every tale but the locked chains at the top")
tv = M.taleView(choir, 1, 7, "en", 230); assert(tv.text:find("(7 / 40)", 1, true)); eq(#tv.buttons, 0)
tv = M.taleView(choir, 0, 0, "en", 230); eq(tv.buttons[1], "accept")
tv = M.taleView(choir, 2, 0, "pt", 230); eq(tv.buttons[1], "turnin"); assert(tv.title:find("Nível 200", 1, true))
tv = M.taleView(choir, 100, 0, "en", 230); eq(#tv.buttons, 0); assert(tv.text:find("Rest, rest", 1, true), "outro when done")
eq(M.statusLine(300, function() return -1 end, function() return 0 end, "en"), nil)
assert(M.statusLine(300, function(t) return t.key == "bone_choir" and 1 or -1 end, function() return 12 end, "en"):find("12 / 40", 1, true))

-- ------------------------------------------------------------------ tales.lua against a mocked engine
local events, talks, modals, messages = {}, {}, {}, {}
local function reg(kind)
	return function(name)
		local o = {name = name}
		function o:register() events[name] = self end
		function o:type() end
		return o
	end
end
CreatureEvent, GlobalEvent = reg("creature"), reg("global")
function TalkAction(words) local o = {}; function o:register() talks[words] = self end; return o end
function addEvent(fn) fn() end
function ModalWindow(id, title, text)
	local w = {id = id, title = title, text = text, choices = {}, buttons = {}}
	function w:addChoice(i, c) self.choices[i] = c end
	function w:addButton(i, b) self.buttons[#self.buttons + 1] = {i, b} end
	function w:setDefaultEnterButton() end
	function w:setDefaultEscapeButton() end
	function w:sendToPlayer() modals[#modals + 1] = self end
	return w
end
ITEM_ATTRIBUTE_TEXT, ITEM_ATTRIBUTE_WRITER = 101, 102
local function pos(x, y, z) return {x = x, y = y, z = z} end
Position = pos
local npcHere = true
local npc = {isNpc = function() return true end, getName = function() return "Archivist Maelis" end,
	isPlayer = function() return false end}
Game = {getSpectators = function() return npcHere and {npc} or {} end, createNpc = function() return npc end}
-- the main city only (townIds[1]): two towns on one mocked temple would place the Archivist twice
Town = function(id) return id == cfg.npc.townIds[1] and {getTemplePosition = function() return pos(100, 100, 7) end} or nil end
Tile = function() return nil end
Chaos = {storage = {}, monsterTypeName = function(c) return c.type end}
local factionGains = {}
ChaosFactions = {gain = function(p, key, amount) factionGains[#factionGains + 1] = {key, amount} end}

local function mkPlayer(id, level, at)
	local p = {id = id, level = level, st = {}, items = {}, bank = 0, xp = 0, at = at or pos(50, 50, 7), msgs = {}}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:isPlayer() return true end
	function p:getMaster() return nil end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:getPosition() return self.at end
	function p:getParty() return self.party end
	function p:getItemCount(id) return self.items[id] or 0 end
	function p:removeItem(id, count) if (self.items[id] or 0) < count then return false end; self.items[id] = self.items[id] - count; return true end
	function p:addItem(id, count)
		self.items[id] = (self.items[id] or 0) + count
		local it = {id = id, attr = {}}
		function it:setAttribute(k, v) self.attr[k] = v end
		self.lastItem = it
		return it
	end
	function p:addExperience(x) self.xp = self.xp + x end
	function p:getBankBalance() return self.bank end
	function p:setBankBalance(v) self.bank = v end
	function p:sendExtendedOpcode() end
	function p:registerEvent() end
	return p
end
local function mkMonster(id, typeName, shown, at)
	return {id = id, type = typeName, getId = function() return id end, isMonster = function() return true end,
		getMaster = function() return nil end, getName = function() return shown or typeName end,
		getPosition = function() return at or pos(50, 50, 7) end}
end

dofile("data/scripts/chaos/tales.lua")
local T = ChaosTales
assert(events.ChaosTalesKill and events.ChaosTalesModal and events.ChaosTalesLogin and events.ChaosTalesStartup)
eq(next(talks), nil, "no spoken command")
eq(T.placeNpcs(), 1, "the Archivist already near the temple is kept (npc_place.lua)")
npcHere = false
eq(T.placeNpcs(), 0, "no free tile next to the mocked temple")
npcHere = true

local hero = mkPlayer(1, 230)
local friend = mkPlayer(2, 210, pos(60, 55, 7))
local far = mkPlayer(3, 220, pos(500, 500, 7))
local party = {getMembers = function() return {friend, far} end, getLeader = function() return hero end}
hero.party, friend.party, far.party = party, party, party

-- the list, read, accept
T.sendList(hero)
local w = modals[#modals]; eq(w.id, cfg.modal.list)
local choirAt
for i, label in ipairs(w.choices) do if label:find("Bone Choir", 1, true) then choirAt = i end end
assert(choirAt, "the Bone Choir in the list")
events.ChaosTalesModal.onModalWindow(hero, cfg.modal.list, 1, choirAt)
w = modals[#modals]; eq(w.id, cfg.modal.tale); eq(w.buttons[1][2], "Accept")
npcHere = false
events.ChaosTalesModal.onModalWindow(hero, cfg.modal.tale, 1, 0)
eq(hero:getStorageValue(M.stateKey(choir)), -1, "not accepted away from the Archivist")
npcHere = true
events.ChaosTalesModal.onModalWindow(hero, cfg.modal.tale, 1, 0)
eq(hero:getStorageValue(M.stateKey(choir)), 1, "accepted")
friend:setStorageValue(M.stateKey(choir), 1); far:setStorageValue(M.stateKey(choir), 1)

-- kills: killer and most damage both fire, the party member in range shares, the far one does not, once per monster
local bone = mkMonster(900, "Bonecleaver")
events.ChaosTalesKill.onKill(hero, bone)
events.ChaosTalesKill.onKill(friend, bone)
eq(hero:getStorageValue(M.countKey(choir)), 1); eq(friend:getStorageValue(M.countKey(choir)), 1, "shared once")
eq(far:getStorageValue(M.countKey(choir)), -1, "out of range")
for i = 1, 39 do events.ChaosTalesKill.onKill(hero, mkMonster(1000 + i, "Skullshade")) end
eq(hero:getStorageValue(M.stateKey(choir)), 2, "kill step done"); eq(hero:getStorageValue(M.countKey(choir)), 0)
events.ChaosTalesKill.onKill(hero, mkMonster(2000, "Rat"))

-- turn in: rewards
T.open[hero:getId()] = "bone_choir"
events.ChaosTalesModal.onModalWindow(hero, cfg.modal.tale, 3, 0)
eq(hero:getStorageValue(M.stateKey(choir)), 100, "done")
eq(hero.bank, 150000); eq(hero.items[29856], 3); eq(hero.xp, M.xpFor(230, 0.5)); eq(hero.items[1950], 1, "the book")
eq(hero.lastItem.attr[ITEM_ATTRIBUTE_TEXT]:sub(1, 12), "Ashen Crypt\n", "the book's text"); eq(factionGains[1][1], "vigil")
eq(factionGains[1][2], 600)
events.ChaosTalesModal.onModalWindow(hero, cfg.modal.tale, 3, 0)
eq(hero.bank, 150000, "no second reward")

-- Portuguese, a delivery
local ana = mkPlayer(4, 560)
ana:setStorageValue(M.langKey(), 2)
ana:setStorageValue(M.stateKey(tithe), 2)
T.open[ana:getId()] = "wyrm_tithe"
ana.items[32051] = 5
events.ChaosTalesModal.onModalWindow(ana, cfg.modal.tale, 3, 0)
eq(ana:getStorageValue(M.stateKey(tithe)), 2, "missing shards"); assert(ana.msgs[#ana.msgs]:find("Faltam 15", 1, true), "pt message")
ana.items[32051] = 21
events.ChaosTalesModal.onModalWindow(ana, cfg.modal.tale, 3, 0)
eq(ana:getStorageValue(M.stateKey(tithe)), 100); eq(ana.items[32051], 1, "20 taken"); eq(ana.items[29857], 2)
assert(ana.lastItem.attr[ITEM_ATTRIBUTE_TEXT]:find("Um salão de mármore negro", 1, true), "the book in Portuguese")

-- the hook decides when it exists
Chaos.lang = function() return "pt" end
eq(T.langOf(hero), "pt"); Chaos.lang = nil; eq(T.langOf(hero), "en")

-- the status line (the list window's text source)
assert(M.statusLine(hero:getLevel(), function(t) return hero:getStorageValue(M.stateKey(t)) end,
	function(t) return hero:getStorageValue(M.countKey(t)) end, "en"):find("The Bone Choir (done)", 1, true))

-- ------------------------------------------------------------------ the experience cap in the engine
local elder = mkPlayer(10, 2000)
elder:setStorageValue(M.stateKey(cellar), 3)
T.open[elder:getId()] = "cellar_teeth"
events.ChaosTalesModal.onModalWindow(elder, cfg.modal.tale, 3, 0)
eq(elder:getStorageValue(M.stateKey(cellar)), 100); eq(elder.xp, M.xpFor(30, 1.0), "measured at the top of the band")
eq(elder.bank, 1500)
events.ChaosTalesModal.onModalWindow(elder, cfg.modal.tale, 3, 0)
eq(elder.bank, 1500, "no second reward"); eq(elder.xp, M.xpFor(30, 1.0))

-- ------------------------------------------------------------------ a chain and a visit, through the engine
local online = {}
Player = function(id) return online[id] end
Game.getPlayers = function() local out = {} for _, p in pairs(online) do out[#out + 1] = p end return out end
local revealed = {}
ChaosPoi = {all = poi.marks, key = function(m) return m.x .. ":" .. m.y .. ":" .. m.z end, seen = {}, dirty = {}, watch = {}}
Chaos.send = function(p, op, action, data) revealed[#revealed + 1] = {action, data} end
ChaosOpcodes = {mapMarkers = 153}
local mira = mkPlayer(11, 12, pos(100, 100, 7))
function mira:getGuid() return 511 end
online[11] = mira
ChaosPoi.seen[511] = {}; ChaosPoi.watch[11] = true
events.ChaosTalesLogin.onLogin(mira)
eq(T.watch[11], nil, "nothing to visit yet")
-- the chain is closed: the road is not in the list, and a forged accept does nothing
T.sendList(mira)
for _, label in ipairs(modals[#modals].choices) do assert(not label:find("Lantern", 1, true), "the chain is closed") end
T.open[11] = "lantern_road"
events.ChaosTalesModal.onModalWindow(mira, cfg.modal.tale, 1, 0)
eq(mira:getStorageValue(M.stateKey(road)), -1, "a forged accept of a closed chain")
-- the cellars: accept starts a visit wait and shows the place on the map
T.open[11] = "cellar_teeth"
events.ChaosTalesModal.onModalWindow(mira, cfg.modal.tale, 1, 0)
eq(mira:getStorageValue(M.stateKey(cellar)), 1); eq(T.watch[11], true, "on the watch list")
eq(revealed[#revealed][1], "reveal"); assert(revealed[#revealed][2].marks[1].n:find("Rat", 1, true), "the cellars' mark")
assert(ChaosPoi.dirty[511], "the mark is saved with the character")
-- away from the place: nothing; there: the step moves on, the message names the next step
events.ChaosTalesVisit.onThink()
eq(mira:getStorageValue(M.stateKey(cellar)), 1)
local cp = cellar.steps[1].pos
mira.at = pos(cp.x + 3, cp.y - 2, cp.z)
events.ChaosTalesVisit.onThink()
eq(mira:getStorageValue(M.stateKey(cellar)), 2, "visited"); eq(T.watch[11], nil, "off the list")
assert(mira.msgs[#mira.msgs]:find("Next: Kill 25 rats", 1, true), "the next step named")
for i = 1, 25 do events.ChaosTalesKill.onKill(mira, mkMonster(3000 + i, i % 2 == 0 and "Rat" or "Cave Rat")) end
eq(mira:getStorageValue(M.stateKey(cellar)), 3)
assert(mira.msgs[#mira.msgs]:find("Return to the Archivist", 1, true))
T.open[11] = "cellar_teeth"
events.ChaosTalesModal.onModalWindow(mira, cfg.modal.tale, 3, 0)
eq(mira:getStorageValue(M.stateKey(cellar)), 100); eq(mira.bank, 1500)
-- now the road opens: accept it, the talk step waits for Warden Ysolde
T.sendList(mira)
local roadAt
for i, label in ipairs(modals[#modals].choices) do if label:find("Lantern", 1, true) then roadAt = i end end
assert(roadAt, "the chain opened")
events.ChaosTalesModal.onModalWindow(mira, cfg.modal.list, 1, roadAt)
events.ChaosTalesModal.onModalWindow(mira, cfg.modal.tale, 1, 0)
eq(mira:getStorageValue(M.stateKey(road)), 1, "the road taken")
T.open[11] = "lantern_road"
events.ChaosTalesModal.onModalWindow(mira, cfg.modal.tale, 3, 0)
eq(mira:getStorageValue(M.stateKey(road)), 1, "a talk step is not turned in at the Archivist")
-- a stale watch entry of a player who left is dropped; logout clears the lists
T.watch[999] = true
events.ChaosTalesVisit.onThink()
eq(T.watch[999], nil)
events.ChaosTalesLogout.onLogout(mira)
eq(T.open[11], nil)

-- ------------------------------------------------------------------ the talk step in the faction NPC's own script
local said, callbacks = {}, {}
KeywordHandler = {new = function() return {} end}
NpcHandler = {new = function()
	local h = {}
	function h:isFocused() return true end
	function h:say(text) said[#said + 1] = text end
	function h:setCallback(k, f) callbacks[k] = f end
	function h:addModule() end
	function h:onCreatureAppear() end
	function h:onCreatureDisappear() end
	function h:onCreatureSay() end
	function h:onThink() end
	return h
end}
NpcSystem = {parseParameters = function() end}
FocusModule = {new = function() return {} end}
ChaosNpcFocus = {hears = function() return true end}
ChaosI18n = {npcText = function(_, s, ...) return select("#", ...) > 0 and string.format(s, ...) or s end,
	npcMessages = function() end, langOf = function() return "en" end}
FACTION_KEY = "vigil"
local opened = 0
function mira:sendExtendedOpcode() opened = opened + 1 end
dofile("data/npc/scripts/chaos_faction_npc.lua")
local say = callbacks[CALLBACK_MESSAGE_DEFAULT]
assert(say, "the faction NPC's dialogue")
online[11] = mira
eq(say(11, 1, "tell me the tale"), true)
eq(mira:getStorageValue(M.stateKey(road)), 2, "the talk step done by Warden Ysolde")
assert(said[#said]:find("The Archivist sent you", 1, true), "her reply")
assert(mira.msgs[#mira.msgs]:find("Next: Put down 30", 1, true), "the next step named")
eq(opened, 0, "the faction window stays closed")
-- nothing pending: the faction's own dialogue answers as before
local before = #said
say(11, 1, "any task?")
eq(opened, 1, "the faction window"); eq(mira:getStorageValue(M.stateKey(road)), 2)
assert(#said == before + 1 and not said[#said]:find("Archivist sent", 1, true))
-- a Portuguese character hears the Portuguese reply
local bia = mkPlayer(12, 1100)
online[12] = bia
bia:setStorageValue(M.langKey(), 2)
local gc = M.tale("gravecage")
bia:setStorageValue(M.stateKey(gc), 2)
eq(say(12, 1, "arquivista"), true); eq(bia:getStorageValue(M.stateKey(gc)), 3)
assert(said[#said]:find("Aberta?", 1, true), "the reply in Portuguese")
-- the wrong NPC does nothing for that tale
FACTION_KEY = "compact"
dofile("data/npc/scripts/chaos_faction_npc.lua")
bia:setStorageValue(M.stateKey(gc), 2)
callbacks[CALLBACK_MESSAGE_DEFAULT](12, 1, "tale")
eq(bia:getStorageValue(M.stateKey(gc)), 2, "Brannoc is not Ysolde")

print("tales_test: OK")
