-- Run from the server/ folder: luajit tests/unlocks_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the level-gated top menu (unlocks_core.lua, unlocks_config.lua, unlocks.lua; O259):
--   * the opcode 115 is free (not the reference server's, the reference client's, a ChaosOpcodes value, any client module's
--     other than client_chaos_topbar) and the storage block 7103000-7103009 is used by this module only;
--   * EVERY entry's level equals the level the system itself enforces: each system's config (or, for the Infinity Tower,
--     its run file) is read here, and the check fails on a mismatch (a mutation of the table is checked to fail too);
--   * the entries: unique keys, the topbar entry and the client module exist, English and Portuguese texts, two lines;
--   * the rules (bits, due, next, silent first masks, later entries) and the glue against a mocked engine: login, the
--     state and new messages, the 75 s pace, seen, staff, a level lost.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function ok(c, m) if not c then error(m or "failed", 2) end end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/unlocks_core.lua")
local M = ChaosUnlocksCore
local cfg = M.cfg()
eq(type(cfg), "table", "config loads")

local function readFile(path)
	local f = io.open(path, "r")
	if not f then return nil end
	local s = f:read("*a")
	f:close()
	return s
end

-- ------------------------------------------------------------------ opcode
eq(ChaosOpcodes.unlocks, 115, "opcode 115")
eq(cfg.opcode, 115, "config opcode")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, -- the reference server
		126, 127, -- its NPC scripts' currency opcodes
		140, 144, 145, 146, 210, 212, 213, 230, 246}) do -- the reference client's own ExtendedIds
	ok(ChaosOpcodes.unlocks ~= v, "not an opcode of the reference server or client: " .. v)
end
local ls = io.popen("ls ../client/overlay/modules 2>/dev/null")
for dir in ls:lines() do
	local ph = io.popen("ls ../client/overlay/modules/" .. dir .. "/*.lua 2>/dev/null")
	for file in ph:lines() do
		local s = readFile(file)
		if s and not file:find("_test.lua", 1, true) and dir ~= "client_chaos_topbar"
				and (s:find("[Oo]pcode[%w_]*%s*=%s*115%f[%D]") or s:find("xtended[%w]*Opcode%(%s*115%f[%D]")) then
			error("opcode 115 also in " .. file)
		end
	end
	ph:close()
end
ls:close()
local topbar = readFile("../client/overlay/modules/client_chaos_topbar/chaos_topbar.lua")
local topbarUnlocks = readFile("../client/overlay/modules/client_chaos_topbar/topbar_unlocks.lua")
ok(topbar and topbarUnlocks, "the topbar module files exist")
ok(topbarUnlocks:find("115", 1, true), "the client listens on 115")

-- ------------------------------------------------------------------ storage: the block is this module's alone
local s = cfg.storage
ok(s.base == 7103000 and s.last == 7103009, "block 7103000-7103009")
ok(s.base + s.unlocked >= s.base and s.base + s.known <= s.last, "storages inside the block")
local ph = io.popen("ls data/scripts/chaos/*.lua data/lib/*.lua 2>/dev/null")
for file in ph:lines() do
	if not file:find("unlocks", 1, true) then
		local text = readFile(file)
		if text and text:find("710300%d") and not file:find("chaos_constants") then
			-- 7103010 and up belong to O260 / O261
			for hit in text:gmatch("710300%d") do error("storage " .. hit .. " also in " .. file) end
		end
	end
end
ph:close()

-- ------------------------------------------------------------------ the entries
ok(#cfg.entries >= 1 and #cfg.entries <= 30, "bits fit 31")
local keys = {}
local function modules()
	local out = {}
	local p = io.popen("ls ../client/overlay/modules")
	for d in p:lines() do out[d] = true end
	p:close()
	return out
end
local clientModules = modules()
for _, e in ipairs(cfg.entries) do
	ok(e.key and not keys[e.key], "unique key " .. tostring(e.key))
	keys[e.key] = true
	ok(type(e.level) == "number" and e.level >= 1, "level of " .. e.key)
	ok(type(e.title) == "table" and e.title[1] and e.title[2], "title in both languages: " .. e.key)
	ok(type(e.why) == "table" and #e.why == 2, "two lines: " .. e.key)
	for _, line in ipairs(e.why) do
		ok(type(line[1]) == "string" and type(line[2]) == "string" and line[1] ~= "" and line[2] ~= "", "both languages: " .. e.key)
		ok(not line[1]:find("\226\128\148") and not line[2]:find("\226\128\148"), "no em dash: " .. e.key)
	end
	ok(type(e.go) == "table" and e.go.open and clientModules[e.go.open], "the client module of Go exists: " .. e.key)
	-- the menu text is an entry of the top menu
	ok(topbar:find("entry('" .. e.menu .. "'", 1, true), "the top menu has an entry '" .. e.menu .. "'")
end

-- ------------------------------------------------------------------ the levels: what each system enforces
-- one reader per key; a reader returns the level the system's own config (or run file) holds
local function fromFile(path, pattern)
	local text = readFile(path)
	ok(text, "readable: " .. path)
	local v = text:match(pattern)
	ok(v, "pattern in " .. path)
	return tonumber(v)
end
local readers = {
	bounty = function() return dofile("data/scripts/chaos/bounty_config.lua").bands[1].min end,
	market = function() return dofile("data/scripts/chaos/market_config.lua").minLevel end,
	passive = function() return Chaos.passive.startLevel + Chaos.passive.levelsPerPoint end, -- the first point
	events = function() return dofile("data/scripts/chaos/invasion_config.lua").minLevel end,
	arena = function() return dofile("data/scripts/chaos/arena_config.lua").minLevel end,
	rifts = function() return dofile("data/scripts/chaos/rift_config.lua").tiers[1].minLevel end,
	siege = function() return dofile("data/scripts/chaos/siege_config.lua").minLevel end,
	tower = function() return fromFile("data/scripts/chaos/infinitytower_run.lua", "\n\tminLevel = (%d+),") end,
	dungeons = function() return dofile("data/scripts/chaos/bossspawns_config.lua").dungeons.defaults[1].level end,
}
-- every entry has a reader and every reader an entry
for _, e in ipairs(cfg.entries) do
	ok(readers[e.key], "a reader for " .. e.key .. ": the level must come from the system's own config")
end
for k in pairs(readers) do
	ok(keys[k], "an entry for the reader " .. k)
end
-- the check itself: a list of the entries whose level differs from the system's
local function mismatches(entries)
	local bad = {}
	for _, e in ipairs(entries) do
		local real = readers[e.key]()
		if real ~= e.level then
			bad[#bad + 1] = e.key .. " " .. e.level .. " ~= " .. tostring(real)
		end
	end
	return bad
end
local bad = mismatches(cfg.entries)
ok(#bad == 0, "levels differ from the systems' own: " .. table.concat(bad, "; "))
-- the check does fail on a mismatch
do
	local copy = {}
	for i, e in ipairs(cfg.entries) do
		local c = {}
		for k, v in pairs(e) do c[k] = v end
		copy[i] = c
	end
	copy[#copy].level = copy[#copy].level + 1
	eq(#mismatches(copy), 1, "a changed level is found")
end

-- ------------------------------------------------------------------ bits, due, next
eq(M.has(-1, 1), false); eq(M.has(0, 1), false); eq(M.has(5, 1), true); eq(M.has(5, 2), false); eq(M.has(5, 3), true)
eq(M.set(-1, 2), 2); eq(M.set(2, 2), 2); eq(M.set(2, 1), 3); eq(M.all(3), 7)
local function indexOf(k) return M.index(k) end
local due = M.due(0, 8)
eq(#due, 2, "bounty and market at level 8"); eq(cfg.entries[due[1]].key, "bounty", "ties by index")
eq(#M.due(0, 7), 0, "nothing below 8")
eq(#M.due(M.set(0, indexOf("bounty")), 8), 1)
eq(#M.due(0, 2000), #cfg.entries, "everything at 2000")
eq(#M.due(M.all(#cfg.entries), 2000), 0)
do
	local nxt = M.nextLocked(0, 8)
	-- 8 is due but not announced: next is the first entry above the level
	eq(nxt.key, "passive"); eq(nxt.level, 12)
	eq(M.nextLocked(M.all(#cfg.entries), 5), nil, "all unlocked: no next")
	eq(M.nextLocked(0, 2000), nil, "no entry above 2000")
	-- a level lost after unlocking: the entry stays unlocked and is not next
	local mask = M.set(0, indexOf("passive"))
	eq(M.nextLocked(mask, 5).key, "bounty", "lowest locked above the level")
	eq(M.nextLocked(M.set(M.set(M.set(0, 1), 2), 3), 8).key, "events", "passive unlocked: events is next")
end
-- silent first masks
do
	local u, sn = M.firstMasks(8)
	eq(u, 0); eq(sn, 0)
	u, sn = M.firstMasks(cfg.quietAbove)
	eq(u, 0, "at quietAbove it is announced")
	u, sn = M.firstMasks(cfg.quietAbove + 1)
	ok(u > 0 and u == sn, "above it silent and seen")
	ok(M.has(u, indexOf("passive")) and not M.has(u, indexOf("events")), "only the entries of its level")
	u = M.firstMasks(500)
	ok(M.has(u, indexOf("arena")) and M.has(u, indexOf("dungeons")) == (500 >= 150), "level 500")
	-- entries added later
	local mask = M.sync(M.all(3), 3, #cfg.entries, function(i) return cfg.entries[i].level end, 100)
	for i, e in ipairs(cfg.entries) do
		eq(M.has(mask, i), i <= 3 or e.level <= 100, "sync " .. e.key)
	end
end
-- the state message
do
	local d = M.state(M.set(0, 1), 0, 8, false)
	eq(#d.entries, #cfg.entries); eq(d.entries[1].key, "bounty"); eq(d.entries[1].menu, "Bounty Board")
	eq(#d.unlocked, 1); eq(d.unlocked[1], "bounty"); eq(#d.seen, 0); eq(d.next.key, "passive"); eq(d.all, nil)
	d = M.state(M.set(M.set(0, 1), 2), M.set(0, 1), 8, true)
	eq(#d.seen, 1); eq(d.all, true)
	d = M.state(M.all(#cfg.entries), 0, 8, false)
	eq(d.next, nil, "no next when all unlocked")
	-- seen counts only unlocked entries
	d = M.state(M.set(0, 1), M.set(0, 2), 8, false)
	eq(#d.seen, 0)
	local a = M.announcement(indexOf("passive"), "pt")
	eq(a.title, "Árvore Passiva"); eq(#a.why, 2); eq(a.menu, "Passive Tree"); eq(a.level, 12)
	eq(M.announcement(indexOf("passive"), "en").title, "Passive Tree")
	do local perRun, gap = M.pace(); eq(perRun, 1); eq(gap, 75000, "the first hour's pace") end
	local fh = dofile("data/scripts/chaos/firsthour_config.lua")
	eq(cfg.pace.gapMs, fh.pace.gapMs, "the same pace as the first hour")
end

-- ------------------------------------------------------------------ unlocks.lua against a mocked engine
local events = {}
local function reg(name)
	local o = {name = name}
	function o:register() events[name] = self end
	function o:type() end
	return o
end
CreatureEvent = reg
local queued = {}
function addEvent(fn, ms) queued[#queued + 1] = {fn = fn, ms = ms} end
local function flush()
	local q = queued
	queued = {}
	local gaps = {}
	for _, e in ipairs(q) do gaps[#gaps + 1] = e.ms; e.fn() end
	return gaps
end
SKILL_LEVEL = 8
Chaos.decode = function(b) return b end
local sent = {}
Chaos.send = function(p, op, action, data) sent[#sent + 1] = {p = p, op = op, action = action, data = data} end
local function take(action)
	local out = {}
	for _, m in ipairs(sent) do if m.action == action then out[#out + 1] = m end end
	return out
end
local players = {}
Player = function(id) return players[id] end
local function mk(id, level, group)
	local p = {id = id, level = level, st = {}, group = group or 1}
	function p:getId() return self.id end
	function p:getLevel() return self.level end
	function p:getStorageValue(k) return self.st[k] or -1 end
	function p:setStorageValue(k, v) self.st[k] = v end
	function p:registerEvent() end
	function p:getGroup() local g = self.group return {getId = function() return g end} end
	players[id] = p
	return p
end
dofile("data/scripts/chaos/unlocks.lua")
local U = ChaosUnlocks
ok(events.ChaosUnlocksLogin and events.ChaosUnlocksAdvance and events.ChaosUnlocksExtended, "events registered")
local S = cfg.storage
local function bits(p, name) return p.st[S.base + S[name]] end

-- a new character at level 8: nothing at login, the state after 1.5 s, the first announcement after 20 s, the next 75 s later
local new = mk(1, 8)
events.ChaosUnlocksLogin.onLogin(new)
eq(bits(new, "unlocked"), 0); eq(bits(new, "known"), #cfg.entries)
local gaps = flush()
eq(gaps[1], 1500); eq(gaps[2], 20000)
local st = take("state")
ok(#st >= 2, "state at login and after the run")
eq(#st[1].data.unlocked, 0, "nothing unlocked in the first state")
local nw = take("new")
eq(#nw, 1, "one per run"); eq(nw[1].data.key, "bounty"); eq(nw[1].data.title, "Bounty Board")
ok(U.pending[1], "the next waits")
eq(st[#st].data.unlocked[1], "bounty", "the state after the announcement")
gaps = flush()
eq(gaps[1], 75000, "75 s later"); eq(#take("new"), 2, "market"); eq(take("new")[2].data.key, "market")
eq(U.pending[1], nil, "none left")
eq(#queued, 0)
-- seen
sent = {}
events.ChaosUnlocksExtended.onExtendedOpcode(new, 115, {action = "seen", data = {key = "bounty"}})
ok(M.has(bits(new, "seen"), indexOf("bounty")), "seen bit")
events.ChaosUnlocksExtended.onExtendedOpcode(new, 115, {action = "seen", data = {key = "arena"}})
ok(not M.has(bits(new, "seen"), indexOf("arena")), "a locked entry cannot be seen")
events.ChaosUnlocksExtended.onExtendedOpcode(new, 115, {action = "seen", data = {key = "nonsense"}})
events.ChaosUnlocksExtended.onExtendedOpcode(new, 114, {action = "seen", data = {key = "market"}})
ok(not M.has(bits(new, "seen"), indexOf("market")), "other opcode ignored")
events.ChaosUnlocksExtended.onExtendedOpcode(new, 115, {action = "hello"})
eq(#take("state"), 1, "hello answers with the state")
eq(take("state")[1].data.seen[1], "bounty")
-- a level up: passive at 12
sent = {}
new.level = 12
events.ChaosUnlocksAdvance.onAdvance(new, SKILL_LEVEL, 11, 12)
eq(take("new")[1].data.key, "passive"); eq(take("new")[1].data.why[1], "Your first passive point is ready.")
eq(take("state")[1].data.next.key, "events")
-- several at once, one per 75 s (a jump from 12 to 100)
sent = {}
new.level = 100
events.ChaosUnlocksAdvance.onAdvance(new, SKILL_LEVEL, 12, 100)
eq(#take("new"), 1, "events first (lowest level)"); eq(take("new")[1].data.key, "events")
local order = {"events"}
for _ = 1, 10 do
	if #queued == 0 then break end
	local g = flush()
	eq(g[1], 75000)
	local t = take("new")
	order[#order + 1] = t[#t].data.key
end
eq(table.concat(order, ","), "events,arena,rifts,siege,tower", "one per gap in level order, ties by index")
eq(take("state")[#take("state")].data.next.key, "dungeons")
-- a level lost: nothing is taken back, the state follows
sent = {}
new.level = 40
events.ChaosUnlocksAdvance.onAdvance(new, SKILL_LEVEL, 100, 40)
eq(#take("new"), 0); eq(#take("state")[1].data.unlocked, 9 - 1, "still unlocked after dying (dungeons not yet)")
-- a veteran: silent
sent = {}
local vet = mk(2, 600)
events.ChaosUnlocksLogin.onLogin(vet)
flush()
eq(#take("new"), 0, "silent"); eq(bits(vet, "unlocked"), bits(vet, "seen"))
ok(M.has(bits(vet, "unlocked"), indexOf("dungeons")))
eq(#take("state")[1].data.unlocked, #cfg.entries)
-- a character with masks from before an entry was added: the passed one silent, the rest at its level
local old = mk(3, 60)
old.st[S.base + S.unlocked] = 3; old.st[S.base + S.seen] = 3; old.st[S.base + S.known] = 2
sent = {}
events.ChaosUnlocksLogin.onLogin(old)
flush()
eq(#take("new"), 0, "entries it passed are silent")
ok(M.has(bits(old, "unlocked"), indexOf("arena")) and not M.has(bits(old, "unlocked"), indexOf("rifts")))
-- staff see the whole menu
sent = {}
local gm = mk(4, 8, 4)
events.ChaosUnlocksLogin.onLogin(gm)
flush()
eq(take("state")[1].data.all, true)
-- the module off: nothing happens at login; the state would carry all = true
cfg.enabled = false
sent = {}
local off = mk(5, 8)
events.ChaosUnlocksLogin.onLogin(off)
eq(off.st[S.base + S.unlocked], nil, "nothing stored while off")
cfg.enabled = true

print("unlocks_test: OK")
