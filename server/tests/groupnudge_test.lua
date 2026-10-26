-- Run from the server/ folder: luajit tests/groupnudge_test.lua (CI runs it with luajit and lua5.3)
-- The group nudge (groupnudge_core.lua, groupnudge_config.lua, groupnudge.lua; server/README.md "The group nudge (O261)"):
-- who is counted as looking for a group (listings with open slots that cover the content, the quick-join queue, not the
-- player's own party, realms), the labels, the ten minute cooldown, then groupnudge.lua on a mocked engine with the real
-- Party Finder state, and the two call sites in dungeons.lua and rift.lua.

local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, tostring(label or "check") .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/i18n_core.lua")
local pfCfg = dofile("data/scripts/chaos/party_finder_config.lua")
dofile("data/scripts/chaos/party_finder_core.lua")
dofile("data/scripts/chaos/groupnudge_core.lua")
local PF, N = ChaosPartyFinderCore, ChaosGroupNudgeCore
local cfg = dofile("data/scripts/chaos/groupnudge_config.lua")
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")

local ids = Chaos.classes.ids
local sources = {riftMaxTier = riftCfg.maxTier, dungeons = {}, worldBosses = {}, omens = {}, trials = {}}
for i = 1, 4 do sources.dungeons[i] = Chaos.dungeons.extra[i].title end
local acts = PF.buildActivities(pfCfg, sources)

local function who(guid, voc, level, extra)
	local w = {guid = guid, cid = 1000 + guid, name = "P" .. guid, level = level or 300, voc = voc or ids.juggernaut,
		vocName = "voc", realm = 0, staff = false}
	for k, v in pairs(extra or {}) do w[k] = v end
	return w
end
local now = 100000
local st = PF.newState()
local lead = who(1, ids.juggernaut, 400)
local L = PF.post(st, pfCfg, acts, lead, {a = "rift", lo = 5, hi = 8, want = {tank = 0, healer = 1, dps = 2}, minLevel = 250,
	note = "", exp = 30, role = "tank"}, now)
check(L ~= nil, "a rift listing T5-8")
local me = who(50, ids.deadeye, 300)

-- ---------------------------------------------------------------- counting
local count, label = N.looking(st, pfCfg, acts, me, "rift", 5)
eq(count, 1, "the leader looks for a group"); eq(label, "Rift T5", "label")
eq((N.looking(st, pfCfg, acts, me, "rift", 8)), 1, "top of the range")
eq((N.looking(st, pfCfg, acts, me, "rift", 9)), 0, "tier above the listing")
eq((N.looking(st, pfCfg, acts, me, "rift", 4)), 0, "tier below the listing")
eq((N.looking(st, pfCfg, acts, me, "rift", nil)), 1, "no tier given: any rift listing")
eq((N.looking(st, pfCfg, acts, me, "dungeon", "Bones Dungeon")), 0, "another content")
-- the crew of the leader's party count: they are all looking
local crewLead = who(2, ids.sentinel, 400, {party = {leader = true, members = {who(3, ids.elementalist, 400), who(4, ids.deadeye, 400)}}})
PF.post(st, pfCfg, acts, crewLead, {a = "dungeon", t = 1, want = {tank = 0, healer = 0, dps = 2}, minLevel = 100, note = "",
	exp = 30, role = "tank"}, now + 1)
local dn, dl = N.looking(st, pfCfg, acts, me, "dungeon", "Bones Dungeon")
eq(dn, 3, "the leader and its two party members"); eq(dl, "Dungeon: Bones Dungeon", "dungeon label")
eq((N.looking(st, pfCfg, acts, me, "dungeon", "Another Crypt")), 0, "a listing for another dungeon")
local anyD = PF.post(st, pfCfg, acts, who(5, ids.deadeye, 400), {a = "dungeon", t = 0, want = {tank = 0, healer = 0, dps = 1},
	minLevel = 100, note = "", exp = 30, role = "dps"}, now + 2)
check(anyD ~= nil, "a listing for any dungeon")
eq((N.looking(st, pfCfg, acts, me, "dungeon", "Another Crypt")), 1, "any dungeon covers it")
eq((N.looking(st, pfCfg, acts, me, "dungeon", "Bones Dungeon")), 4)
eq(N.label(acts, "dungeon", nil), "Dungeon", "label without detail"); eq(N.label(acts, "nope"), "nope")
-- the player's own listing and party do not count
eq((N.looking(st, pfCfg, acts, lead, "rift", 5)), 0, "not the player's own listing")
local inParty = who(60, ids.deadeye, 300, {party = {leader = false, members = {lead}}})
eq((N.looking(st, pfCfg, acts, inParty, "rift", 5)), 0, "not the player's own party's listing")
eq(N.groupSize(me), 1); eq(N.groupSize(inParty), 2)
-- realms: a season group is not shown to the standard realm
local season = PF.post(st, pfCfg, acts, who(7, ids.deadeye, 400, {realm = 2}), {a = "rift", lo = 1, hi = 15,
	want = {tank = 1, healer = 0, dps = 0}, minLevel = 100, note = "", exp = 30, role = "dps"}, now + 3)
check(season ~= nil, "a season listing")
eq((N.looking(st, pfCfg, acts, me, "rift", 5)), 1, "another realm is left out")
eq((N.looking(st, pfCfg, acts, who(51, ids.deadeye, 300, {realm = 2}), "rift", 5)), 1, "the same realm sees only its own group")
-- a full listing does not count
local full = PF.post(st, pfCfg, acts, who(8, ids.juggernaut, 400), {a = "rift", lo = 5, hi = 5, want = {tank = 0, healer = 0, dps = 1},
	minLevel = 100, note = "", exp = 30, role = "tank"}, now + 4)
eq((N.looking(st, pfCfg, acts, me, "rift", 5)), 2, "one more listing open")
full.members[#full.members + 1] = {guid = 99, cid = 1099, name = "P99", level = 300, voc = ids.deadeye, vocName = "voc", role = "dps", st = "joined", at = now}
eq((N.looking(st, pfCfg, acts, me, "rift", 5)), 1, "a listing without an open slot is not counted")
-- the quick-join queue
PF.queueJoin(st, pfCfg, acts, who(70, ids.deadeye, 300), "dps", "rift", now)
PF.queueJoin(st, pfCfg, acts, who(71, ids.deadeye, 300), "dps", "dungeon", now)
PF.queueJoin(st, pfCfg, acts, who(72, ids.deadeye, 300), "dps", "", now)
eq((N.looking(st, pfCfg, acts, me, "rift", 5)), 2, "one queued for a rift")
eq((N.looking(st, pfCfg, acts, who(70, ids.deadeye, 300), "rift", 5)), 1, "not the player itself")
-- junk in
check(pcall(N.looking, st, pfCfg, acts, me, "rift", 0 / 0), "NaN tier")
check(pcall(N.looking, PF.newState(), pfCfg, acts, me, "rift", "x"), "an empty state")
eq((N.looking(PF.newState(), pfCfg, acts, me, "rift", 5)), 0, "nobody looking")

-- ---------------------------------------------------------------- the cooldown
local last = {}
check(N.due(last, 1, 1000, 600), "first time"); check(not N.due(last, 1, 1599, 600), "within ten minutes")
check(N.due(last, 1, 1600, 600), "after ten minutes"); check(N.due(last, 2, 1601, 600), "another player")
N.sweep(last, 5000, 600); eq(next(last), nil, "swept")
eq(cfg.cooldownSeconds, 600, "ten minutes in the config"); check(cfg.activities.rift and cfg.activities.dungeon, "rift and dungeon")

-- ================================================================ groupnudge.lua on a mocked engine
local clock = 500000
local realTime = os.time
os.time = function(t) if t then return realTime(t) end return clock end
local sent = {}
json = {encode = function(t) sent[#sent + 1] = t return "#" .. #sent end}
local function mkPlayer(guid, party)
	local p = {guid = guid, ops = {}}
	function p:getGuid() return self.guid end
	function p:getParty() return self.party end
	function p:sendExtendedOpcode(op, s) self.ops[#self.ops + 1] = op return true end
	p.party = party
	return p
end
Chaos.partyFinderConfig = pfCfg
local solo = mkPlayer(50)
ChaosPartyFinder = {state = st, acts = function() return acts end,
	who = function(p) return who(p.guid, ids.deadeye, 300, {party = p.party and {leader = true, members = {who(99)}} or nil}) end}
dofile("data/scripts/chaos/groupnudge.lua")
local G = ChaosGroupNudge
eq(G.onEnter(solo, "rift", 5), 2, "a nudge: the T5-8 listing and one queued player")
eq(#sent, 1, "one message"); eq(sent[1].action, "nudge"); eq(sent[1].data.n, 2); eq(sent[1].data.a, "rift")
eq(sent[1].data.text, "2 players look for a group for Rift T5.", "text")
eq(solo.ops[1], 208, "on the Party Finder opcode")
eq(G.onEnter(solo, "rift", 5), nil, "not again within ten minutes")
eq(G.onEnter(solo, "dungeon", "Bones Dungeon"), nil, "any content shares the cooldown")
clock = clock + 601
eq(G.onEnter(solo, "dungeon", "Bones Dungeon"), 5, "after ten minutes: the dungeon groups and a queued player")
clock = clock + 601
eq(G.onEnter(solo, "rift", 12), 1, "T12: only the queued player, who takes any tier")
eq(G.onEnter(solo, "raid"), nil, "a content that does not nudge")
clock = clock + 601
eq(G.onEnter(mkPlayer(50, true), "rift", 5), nil, "a player in a party is not nudged")
local one = mkPlayer(80)
st.queue[70], st.queueOrder = nil, {}
for i = #st.order, 1, -1 do PF.close(st, st.order[i], "closed") end
eq(G.onEnter(one, "rift", 5), nil, "no open group: no nudge (and no cooldown spent, see below)")
-- the text for one player
local L2 = PF.post(st, pfCfg, acts, who(9, ids.deadeye, 400), {a = "rift", lo = 5, hi = 5, want = {tank = 1, healer = 0, dps = 0},
	minLevel = 100, note = "", exp = 30, role = "dps"}, clock)
check(L2 ~= nil, "a new listing")
eq(G.onEnter(one, "rift", 5), 1, "one player")
eq(sent[#sent].data.text, "1 player looks for a group for Rift T5.", "text for one")
for _, key in ipairs({"1 player looks for a group for %s.", "%d players look for a group for %s."}) do
	check(ChaosI18n.strings["pt-BR"][key], "pt-BR entry: " .. key)
end

-- the two call sites are guarded and pass what the nudge needs
local function read(path) local f = assert(io.open(path)) local s = f:read("*a") f:close() return s end
local d = read("data/scripts/chaos/dungeons.lua")
check(d:find('ChaosGroupNudge.onEnter, players[1], "dungeon"', 1, true) ~= nil, "dungeons.lua calls the nudge for a lone player")
check(d:find("#players == 1", 1, true) ~= nil, "dungeons.lua: alone only")
local r = read("data/scripts/chaos/rift.lua")
check(r:find('ChaosGroupNudge.onEnter, player, "rift", key.tier', 1, true) ~= nil, "rift.lua calls the nudge")
check(r:find("#group == 1", 1, true) ~= nil, "rift.lua: alone only")

print(string.format("groupnudge_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
