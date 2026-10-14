-- Run from the server/ folder: luajit tests/tales_test.lua (CI runs it with luajit and lua5.3)
-- Covers the tales (tales_core.lua, tales_config.lua), the lore data (lore_data.lua) and tales.lua against a mocked
-- engine: config sanity (storages in the block, both languages, monsters that exist), language choice, states, kill
-- credit (type and shown name, steps, party share, no double credit), accept and turn in (next to the NPC only,
-- deliveries), rewards (experience share, bank, items, faction hook, the lore book) and the windows.
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
local seen, slots = {}, {}
for _, t in ipairs(cfg.tales) do
	assert(not slots[t.slot], "slot used once: " .. t.key); slots[t.slot] = true
	for _, k in ipairs({M.stateKey(t), M.countKey(t)}) do
		assert(k >= cfg.storage.base and k <= cfg.storage.last, "storage in the block: " .. t.key)
		assert(not seen[k], "storage distinct"); seen[k] = true
	end
	assert(t.name.en and t.name.pt and t.story.en and t.story.pt, "both languages: " .. t.key)
	assert(t.outro.en and t.outro.pt, "outro in both languages: " .. t.key)
	for _, s in ipairs(t.steps) do
		assert(s.text.en and s.text.pt, "step text in both languages: " .. t.key)
		assert(s.kind == "kill" or s.kind == "deliver" or s.kind == "report", "known step kind " .. tostring(s.kind))
		if s.kind == "kill" then assert(s.count >= 1 and #s.monsters >= 1, "kill step") end
	end
	assert(M.loreEntry(t.rewards.book), "the book exists: " .. t.key)
	assert(cfg.factions[t.faction], "faction known: " .. t.key)
	assert(t.band[1] == t.minLevel or t.band[1] <= t.minLevel, "band")
end
assert(not seen[M.langKey()], "language storage distinct"); assert(M.langKey() == cfg.storage.base)
eq(#cfg.tales >= 3 and #cfg.tales <= 5, true, "3-5 tales")
for k, v in pairs(cfg.ui) do assert(v.en and v.pt, "ui text " .. k .. " in both languages") end

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

-- views
local states = {}
local function stateOf(t) return states[t.key] or -1 end
local v = M.listView(150, stateOf, "en"); eq(#v.choices, 0); assert(v.text:find("200", 1, true), "next level named")
v = M.listView(520, stateOf, "pt"); eq(#v.choices, 2); assert(v.choices[1].label:find("Coro", 1, true))
states.ash_requiem = 1
v = M.listView(520, stateOf, "en"); eq(#v.choices, 3, "a taken tale shows below its level too")
local tv = M.taleView(choir, 1, 7, "en", 230); assert(tv.text:find("(7 / 40)", 1, true)); eq(#tv.buttons, 0)
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
Town = function() return {getTemplePosition = function() return pos(100, 100, 7) end} end
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
eq(T.placeNpcs(), 0, "no free tile next to the mocked temple")

local hero = mkPlayer(1, 230)
local friend = mkPlayer(2, 210, pos(60, 55, 7))
local far = mkPlayer(3, 220, pos(500, 500, 7))
local party = {getMembers = function() return {friend, far} end, getLeader = function() return hero end}
hero.party, friend.party, far.party = party, party, party

-- the list, read, accept
T.sendList(hero)
local w = modals[#modals]; eq(w.id, cfg.modal.list); eq(#w.choices, 1); eq(w.choices[1]:find("Bone Choir", 1, true) ~= nil, true)
events.ChaosTalesModal.onModalWindow(hero, cfg.modal.list, 1, 1)
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

print("tales_test: OK")
