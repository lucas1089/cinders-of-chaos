-- Run from the server/ folder: luajit tests/firsthour_test.lua (CI runs it with luajit and lua5.3)
-- Covers the first-hour hints (firsthour_core.lua, firsthour_config.lua) and firsthour.lua against a mocked engine:
-- both languages, bits, due hints and reveals, the hunt pick (level window, distance, floors, seen marks), the reveal
-- into the map markers' discoveries, old characters marked silently, the welcome hook.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

dofile("data/scripts/chaos/firsthour_core.lua")
local M = ChaosFirstHourCore
local cfg = M.cfg()

-- ------------------------------------------------------------------ config
eq(type(cfg), "table")
assert(cfg.storage.base >= 7101550 and cfg.storage.base + cfg.storage.reveals <= cfg.storage.last, "storages in the block")
assert(cfg.storage.last <= 7101559)
local last = 0
for i, h in ipairs(cfg.hints) do
	assert(h.en and h.pt and h.key, "hint " .. i .. " in both languages")
	assert(h.level >= last, "hints sorted by level"); last = h.level
	local a = select(2, h.en:gsub("%%s", "")); local b = select(2, h.pt:gsub("%%s", ""))
	eq(a, b, "same placeholders in both languages: " .. h.key); assert(a <= 1)
	assert(not h.en:find("\226\128\148") and not h.pt:find("\226\128\148"), "no em dash")
end
assert(#cfg.hints <= 30 and #cfg.revealAt <= 30, "masks fit")

-- ------------------------------------------------------------------ bits
eq(M.has(-1, 1), false); eq(M.has(0, 1), false); eq(M.has(5, 1), true); eq(M.has(5, 2), false); eq(M.has(5, 3), true)
eq(M.set(-1, 2), 2); eq(M.set(2, 2), 2); eq(M.set(2, 1), 3); eq(M.all(3), 7); eq(math.type and math.type(M.set(0, 4)) or "integer", "integer")

-- ------------------------------------------------------------------ due
local due = M.dueHints(0, 1); eq(#due, 1); eq(cfg.hints[due[1]].key, "start")
due = M.dueHints(M.set(0, 1), 12); eq(#due, 3, "gear, bounty, passive")
due = M.dueHints(M.all(#cfg.hints), 500); eq(#due, 0)
eq(#M.dueReveals(0, 1), 1); eq(#M.dueReveals(1, 25), 2, "8 and 20"); eq(#M.dueReveals(0, 0), 0)

-- ------------------------------------------------------------------ hunts
eq(select(1, M.bandOf("Hunting: Rat, Snake (level 4-9)")), 4); eq(select(2, M.bandOf("Hunting: Rat (level 4-9)")), 9)
eq(M.bandOf("Temple"), nil)
local marks = {
	{k = "hunt", x = 110, y = 100, z = 7, n = "Hunting: Rat, Snake (level 2-8)"},
	{k = "hunt", x = 300, y = 100, z = 7, n = "Hunting: Troll (level 6-12)"},
	{k = "hunt", x = 105, y = 100, z = 9, n = "Hunting: Cave Rat (level 3-7)"}, -- 5 + 2 floors x 40 = 85
	{k = "hunt", x = 130, y = 100, z = 7, n = "Hunting: Dragon (level 30-60)"},
	{k = "temple", x = 100, y = 100, z = 7, n = "Temple"},
	{k = "hunt", x = 2000, y = 100, z = 7, n = "Hunting: Wolf (level 3-9)"} -- out of range
}
local function key(m) return m.k .. m.x .. ":" .. m.y .. ":" .. m.z end
local got = M.pickHunts(marks, {}, key, {x = 100, y = 100, z = 7}, 5)
eq(#got, 3); eq(got[1].x, 110); eq(got[2].x, 105, "a floor costs 40"); eq(got[3].x, 300)
got = M.pickHunts(marks, {[key(marks[1])] = true}, key, {x = 100, y = 100, z = 7}, 5)
eq(got[1].x, 105, "seen marks are skipped")
got = M.pickHunts(marks, {}, key, {x = 100, y = 100, z = 7}, 26)
eq(#got, 1); eq(got[1].x, 130, "a band starting within the slack")
eq(M.shortName(marks[1]), "Rat, Snake (level 2-8)")
assert(M.text(1, "pt", {"A", "B"}):find("A; B", 1, true)); assert(M.text(1, "en", {}):find(cfg.none.en, 1, true))
assert(not M.text(4, "en"):find("%s", 1, true), "a hint without names")

-- ------------------------------------------------------------------ firsthour.lua against a mocked engine
local events = {}
local function reg(name)
	local o = {name = name}
	function o:register() events[name] = self end
	function o:type() end
	return o
end
CreatureEvent, GlobalEvent = reg, reg
local queued = {}
function addEvent(fn) queued[#queued + 1] = fn end
local function flush() local q = queued; queued = {}; for _, f in ipairs(q) do f() end end
SKILL_LEVEL = 8
Chaos = {storage = {newPlayer = 7100250}}
ChaosOpcodes = {mapMarkers = 153}
local sent = {}
Chaos.send = function(p, op, action, data) sent[#sent + 1] = {op, action, #data.marks} end
ChaosPoi = {all = marks, key = key, seen = {}, dirty = {}, watch = {}}
local players = {}
Player = function(id) return players[id] end

local function mkPlayer(id, level)
	local p = {id = id, level = level, st = {}, msgs = {}}
	function p:getId() return self.id end
	function p:getGuid() return self.id + 100 end
	function p:getLevel() return self.level end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
	function p:sendExtendedOpcode() end
	function p:registerEvent() end
	function p:getTown() return {getTemplePosition = function() return {x = 100, y = 100, z = 7} end} end
	function p:getPosition() return {x = 100, y = 100, z = 7} end
	players[id] = p
	return p
end

ChaosNewPlayer = {showWelcome = function() return true end}
dofile("data/scripts/chaos/firsthour.lua")
local F = ChaosFirstHour
assert(events.ChaosFirstHourLogin and events.ChaosFirstHourAdvance and events.ChaosFirstHourStartup)
events.ChaosFirstHourStartup.onStartup()
assert(ChaosNewPlayer.firstHourWrapped, "the welcome is wrapped")

-- a veteran: everything marked, nothing said
local vet = mkPlayer(1, 300)
events.ChaosFirstHourLogin.onLogin(vet); flush()
eq(#vet.msgs, 0); eq(vet:getStorageValue(cfg.storage.base), M.all(#cfg.hints))

-- a new character on the island: nothing before the kit
local new = mkPlayer(2, 1)
ChaosPoi.seen[new:getGuid()] = {}
events.ChaosFirstHourLogin.onLogin(new); flush()
eq(#new.msgs, 0, "no kit yet")
events.ChaosFirstHourAdvance.onAdvance(new, SKILL_LEVEL, 1, 2)
eq(#new.msgs, 0, "still no kit")
-- the kit and the welcome: the first hint with the hunts, revealed on the map
new.st[7100250] = os.time()
ChaosPoi.watch[new:getId()] = true
ChaosNewPlayer.showWelcome(new); flush()
eq(#new.msgs, 1); assert(new.msgs[1]:find("Rat, Snake (level 2-8)", 1, true), "the hunts named")
assert(ChaosPoi.seen[new:getGuid()][key(marks[1])], "revealed in the discoveries"); assert(ChaosPoi.dirty[new:getGuid()])
eq(sent[1][2], "reveal"); eq(sent[1][1], 153)
-- level 9: the gear and bounty hints; the reveal at 8 finds a new hunt
marks[#marks + 1] = {k = "hunt", x = 150, y = 120, z = 7, n = "Hunting: Orc (level 9-15)"}
new.level = 9
events.ChaosFirstHourAdvance.onAdvance(new, SKILL_LEVEL, 8, 9)
eq(#new.msgs, 3); assert(new.msgs[3]:find("Orc (level 9-15)", 1, true), "new hunts in the bounty hint")
assert(not new.msgs[3]:find("Troll", 1, true), "a revealed hunt is not named again")
events.ChaosFirstHourAdvance.onAdvance(new, SKILL_LEVEL, 9, 10)
eq(#new.msgs, 3, "nothing twice")
-- Portuguese through the tales' language storage
dofile("data/scripts/chaos/tales_core.lua")
new:setStorageValue(ChaosTalesCore.langKey(), 2)
new.level = 12
events.ChaosFirstHourAdvance.onAdvance(new, SKILL_LEVEL, 11, 12)
assert(new.msgs[#new.msgs]:find("Árvore Passiva", 1, true), "pt hint")
-- without the map markers the hints still come
ChaosPoi = nil
new.level = 20
events.ChaosFirstHourAdvance.onAdvance(new, SKILL_LEVEL, 19, 20)
assert(new.msgs[#new.msgs]:find("Bestiário", 1, true))

print("firsthour_test: OK")
