-- Run from the server/ folder: luajit tests/party_finder_test.lua (or lua5.3; CI runs both)
-- Party Finder (LFG): roles by class, the activities from the live configs, the note filter, posting and its checks,
-- applications, accept / decline, the engine reconcile (joined, left, unanswered invite, leader gone, expiry, full),
-- realms and staff, the quick-join queue, the payloads, and party_finder.lua against a mocked engine (opcode ->
-- listing -> application -> party invite -> join -> full -> logout).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
local cfg = dofile("data/scripts/chaos/party_finder_config.lua")
dofile("data/scripts/chaos/party_finder_core.lua")
local K = ChaosPartyFinderCore
local riftCfg = dofile("data/scripts/chaos/rift_config.lua")
local trialsCfg = dofile("data/scripts/chaos/trials_config.lua")

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

-- ---------------------------------------------------------------- opcode
eq(ChaosOpcodes.partyFinder, 208, "opcode 208")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	check(not seen[v], "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
-- the base server's opcodes (server/README.md "Opcode collision check")
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202}) do
	check(seen[v] == nil or v == 89, "no Chaos opcode on base opcode " .. v)
end

-- ---------------------------------------------------------------- roles (docs/CLASSES.md "Roles in a group")
local ids = Chaos.classes.ids
for name, id in pairs(ids) do
	check(cfg.classRoles[id] ~= nil, name .. " has roles")
	for _, r in ipairs(cfg.classRoles[id] or {}) do
		check(K.isRole(cfg, r), name .. " role " .. r .. " exists")
	end
end
eq(K.mainRole(cfg, ids.juggernaut), "tank", "Juggernaut tanks")
check(K.canFill(cfg, ids.sentinel, "tank"), "Sentinel tanks")
check(K.canFill(cfg, ids.samurai, "tank"), "Samurai off-tanks")
eq(K.mainRole(cfg, ids.illusionist), "healer", "Illusionist heals")
eq(K.mainRole(cfg, ids.ironsage), "healer", "Iron Sage heals")
check(not K.canFill(cfg, ids.deadeye, "tank"), "Deadeye does not tank")
check(not K.canFill(cfg, ids.elementalist, "healer"), "Elementalist does not heal")
eq(K.mainRole(cfg, 999), "dps", "unknown vocation: DPS")
check(not K.isRole(cfg, "bard"), "no bard role")

-- ---------------------------------------------------------------- activities
local sources = {riftMaxTier = riftCfg.maxTier, omens = {}, trials = {}, worldBosses = {}, dungeons = {}}
for _, k in ipairs(riftCfg.omen.kinds) do sources.omens[#sources.omens + 1] = k.boss end
for _, t in ipairs(trialsCfg.tiers) do sources.trials[#sources.trials + 1] = t.name end
for _, b in ipairs(Chaos.worldBoss.bosses) do sources.worldBosses[#sources.worldBosses + 1] = b.name end
for i = 1, 4 do sources.dungeons[i] = Chaos.dungeons.extra[i].title end
local acts = K.buildActivities(cfg, sources)
eq(#acts, 8, "eight activities")
eq(K.activity(acts, "rift").range.max, riftCfg.maxTier, "rift max tier from rift_config.lua")
eq(#K.activity(acts, "omen").targets, 3, "three omen guardians")
eq(#K.activity(acts, "worldboss").targets, 5, "five world bosses")
eq(K.activity(acts, "dungeon").targets[1], "Bones Dungeon", "dungeon names")
eq(K.activity(acts, "trial").targets[2], "Cruel", "trial tiers")
check(K.activity(acts, "other").title, "other takes a title")
local bare = K.buildActivities(cfg, {})
eq(K.activity(bare, "dungeon").targets[4], "Rootkraken", "dungeon fallback")
eq(#K.activity(bare, "worldboss").targets, 0, "no world boss list without the config")
eq(K.activity(bare, "rift").range.max, 15, "rift config default")
for i, k in ipairs(riftCfg.omen.kinds) do
	eq(K.activity(bare, "omen").targets[i], k.boss, "omen fallback matches rift_config.lua " .. i)
end
eq(K.activityText(acts, {a = "rift", lo = 5, hi = 8}), "Rift T5-8", "rift text")
eq(K.activityText(acts, {a = "tower", lo = 20, hi = 20}), "Infinity Tower F20", "tower text")
eq(K.activityText(acts, {a = "omen", t = 1}), "Omen: Sangrith the Bloodmoon Herald", "omen text")
eq(K.activityText(acts, {a = "dungeon", t = 0}), "Dungeon", "any dungeon")
eq(K.activityText(acts, {a = "other", title = "Quest help"}), "Other: Quest help", "other text")
eq(K.activityText(acts, {a = "nope"}), "?", "unknown activity")

-- ---------------------------------------------------------------- the note filter
eq(K.cleanText("  hello\n\tworld  ", 80, cfg), "hello world", "spaces and controls")
eq(K.cleanText("caf\195\169 ok", 80, cfg), "caf ok", "non-ASCII dropped")
eq(K.cleanText("you SHIThead", 80, cfg), "you ****head", "bad word censored")
eq(K.cleanText("join www.example.com now", 80, cfg), "join *** now", "www link cut")
eq(K.cleanText("see http://x.y/z", 80, cfg), "see ***", "url cut")
eq(K.cleanText("visit mysite.gg", 80, cfg), "visit ***", "domain cut")
eq(K.cleanText("lvl 300+ e.k. ok", 80, cfg), "lvl 300+ e.k. ok", "abbreviations stay")
eq(#K.cleanText(string.rep("a", 200), 80, cfg), 80, "cut to the limit")
eq(K.cleanText(nil, 80, cfg), "", "nil note")

-- ---------------------------------------------------------------- posting
local function who(guid, voc, level, extra)
	local w = {guid = guid, cid = 1000 + guid, name = "P" .. guid, level = level or 300, voc = voc,
		vocName = "voc" .. voc, realm = 0, staff = false}
	for k, v in pairs(extra or {}) do w[k] = v end
	return w
end
local st = K.newState()
local now = 100000
local tank = who(1, ids.juggernaut, 400)
local good = {a = "rift", lo = 5, hi = 8, want = {tank = 0, healer = 1, dps = 2}, minLevel = 250, note = "need heals",
	exp = 30, role = "tank"}
local function copy(t, over)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	for k, v in pairs(over or {}) do c[k] = v end
	return c
end
local function refused(input, reason, label, w)
	local L, why = K.post(st, cfg, acts, w or tank, input, now)
	check(L == nil, label .. " refused")
	eq(why, reason, label .. " reason")
end
refused(copy(good, {a = "picnic"}), "activity", "unknown activity")
refused(copy(good, {lo = 0}), "range", "tier 0")
refused(copy(good, {lo = 9, hi = 8}), "range", "lo over hi")
refused(copy(good, {hi = 16}), "range", "past the max tier")
refused(copy(good, {a = "omen", t = 4}), "target", "omen index")
refused(copy(good, {a = "other", title = "   "}), "title", "other without title")
refused(copy(good, {a = "other", title = "shit"}), "title", "a title that is only a bad word")
refused(copy(good, {role = "healer"}), "role", "Juggernaut cannot heal")
refused(copy(good, {role = "wizard"}), "role", "unknown role")
refused(copy(good, {want = {tank = 0, healer = 0, dps = 0}}), "want", "nobody wanted")
refused(copy(good, {want = {tank = 0, healer = 7, dps = 0}}), "perRole", "too many healers")
refused(copy(good, {want = {tank = -1, healer = 1, dps = 0}}), "perRole", "negative")
refused(copy(good, {want = {tank = 3, healer = 3, dps = 4}}), "size", "past a full party")
refused(copy(good, {minLevel = 0}), "minLevel", "level 0")
refused(copy(good, {minLevel = 99999}), "minLevel", "level too high")
refused(good, "notLeader", "a party member", who(9, ids.juggernaut, 400, {party = {leader = false, members = {}}}))
cfg.enabled = false
refused(good, "disabled", "switched off")
cfg.enabled = true

local L, status = K.post(st, cfg, acts, tank, copy(good, {exp = 7, note = "need heals, see www.x.com"}), now)
check(L ~= nil, "posted")
eq(status, "posted", "status posted")
eq(L.expMin, cfg.defaultExpiry, "unknown expiry -> default")
eq(L.note, "need heals, see ***", "note filtered")
eq(L.expires, now + cfg.defaultExpiry * 60, "expires")
local open, total = K.open(cfg, L)
eq(open.healer, 1, "one healer open")
eq(total, 3, "three slots open")
eq(K.size(L), 1, "the leader alone")
-- the update keeps the listing and its id
local L2, st2 = K.post(st, cfg, acts, tank, copy(good, {exp = 60}), now + 1)
eq(st2, "cooldown", "update cooldown")
L2, st2 = K.post(st, cfg, acts, tank, copy(good, {exp = 60}), now + 5)
eq(L2, L, "same listing")
eq(st2, "updated", "status updated")
eq(L.expMin, 60, "expiry changed")
-- a second leader within the post cooldown of its own last post
local healerLead = who(2, ids.illusionist, 500)
local H = K.post(st, cfg, acts, healerLead, {a = "omen", t = 2, want = {tank = 1, dps = 1}, role = "healer"}, now)
check(H ~= nil, "second listing")
K.close(st, H.id, "closed")
refused({a = "omen", t = 2, want = {tank = 1}, role = "healer"}, "cooldown", "post cooldown", healerLead)
check(K.post(st, cfg, acts, healerLead, {a = "omen", t = 2, want = {tank = 1, dps = 1}, role = "healer"}, now + cfg.postCooldown) ~= nil,
	"post after the cooldown")
local Hid = st.byLeader[2]
-- a leader whose party already has members: they are the crew, and count against the party size
local withParty = who(3, ids.sentinel, 300, {party = {leader = true, members = {who(31, ids.deadeye), who(32, ids.ironsage)}}})
local C = K.post(st, cfg, acts, withParty, {a = "tower", lo = 10, hi = 20, want = {dps = 2}, role = "tank"}, now)
eq(#C.crew, 2, "crew")
eq(C.crew[2].role, "healer", "crew role = main role")
check(C.hadParty, "a crew means a party")
refused({a = "tower", lo = 10, hi = 20, want = {dps = 6, healer = 2}, role = "tank"}, "size", "crew counts", withParty)

-- ---------------------------------------------------------------- applications
local healer = who(10, ids.illusionist, 300)
local dps1 = who(11, ids.deadeye, 260)
local dps2 = who(12, ids.ninja, 255)
local low = who(13, ids.elementalist, 100)
local function ap(w, id, role, label, reason, at)
	local app, why = K.apply(st, cfg, w, id, role, at or now)
	if reason then
		check(app == nil, label .. " refused")
		eq(why, reason, label .. " reason")
	else
		check(app ~= nil, label .. " (" .. tostring(why) .. ")")
	end
	return app, why
end
ap(tank, L.id, "tank", "own listing", "own")
ap(healer, 999, "healer", "no listing", "gone")
ap(healer, L.id, "tank", "Illusionist as tank", "role")
ap(low, L.id, "dps", "under the minimum level", "level")
ap(who(14, ids.juggernaut, 400), L.id, "tank", "no tank wanted", "full")
ap(who(15, ids.deadeye, 400, {party = {leader = true, members = {}}}), L.id, "dps", "in a party", "inParty")
ap(who(16, ids.deadeye, 400, {realm = 2}), L.id, "dps", "a season character", "realm")
ap(who(17, ids.deadeye, 400, {realm = 2, staff = true}), L.id, "dps", "staff of another realm")
K.withdraw(st, 17, L.id)
local a1 = ap(healer, L.id, "healer", "healer applies")
eq(a1.quick, false, "not quick")
local _, again = ap(healer, L.id, "dps", "healer changes role")
eq(again, "updated", "re-apply updates")
eq(L.apps[10].role, "dps", "role changed")
ap(healer, L.id, "healer", "back to healer")
ap(dps1, L.id, "dps", "dps 1")
ap(dps2, L.id, "dps", "dps 2")
eq(#L.appOrder, 3, "three applications")
eq(K.appCount(st, 10), 1, "the healer's applications")
-- a character's application cap
local busy = who(20, ids.berserker, 400)
for i = 1, cfg.maxApplications do
	local leadI = who(100 + i, ids.warrior, 300)
	local Li = K.post(st, cfg, acts, leadI, {a = "raid", want = {dps = 1}, role = "dps"}, now)
	ap(busy, Li.id, "dps", "application " .. i)
end
local extra = K.post(st, cfg, acts, who(120, ids.warrior, 300), {a = "raid", want = {dps = 1}, role = "dps"}, now)
ap(busy, extra.id, "dps", "too many applications", "tooMany")
eq(#K.withdrawAll(st, 20), cfg.maxApplications, "withdraw all")
eq(K.appCount(st, 20), 0, "none left")

-- ---------------------------------------------------------------- decide
local ok, why = K.decide(st, cfg, 99, L.id, 10, true, now)
eq(why, "notYours", "someone else's listing")
ok, why = K.decide(st, cfg, 1, L.id, 77, true, now)
eq(why, "noApp", "no such application")
ok, why = K.decide(st, cfg, 1, L.id, 12, false, now)
eq(why, "declined", "declined")
ap(dps2, L.id, "dps", "declined a moment ago", "declined")
ap(dps2, L.id, "dps", "after the decline cooldown", nil, now + cfg.declineCooldown)
-- the healer also applied elsewhere: accepting withdraws that one
ap(healer, Hid, "dps", "healer applies to a second group")
local app, others
ok, why, app, others = K.decide(st, cfg, 1, L.id, "10", true, now)
check(ok, "accepted")
eq(why, "accepted", "accepted reason")
eq(app.name, "P10", "the application")
eq(#others, 1, "withdrawn from the other group")
eq(st.listings[Hid].apps[10], nil, "gone from the other group")
eq(L.members[1].st, "invited", "invited")
open = K.open(cfg, L)
eq(open.healer, 0, "healer slot taken")
eq(K.size(L), 2, "leader + invited")
-- an application for a role that is now filled cannot be accepted
local otherHealer = who(18, ids.ironsage, 400)
L.want.healer = 2
ap(otherHealer, L.id, "healer", "second healer")
L.want.healer = 1
ok, why = K.decide(st, cfg, 1, L.id, 18, true, now)
eq(why, "full", "role filled meanwhile")
-- an update may not ask for fewer than taken
refused(copy(good, {want = {tank = 0, healer = 0, dps = 2}}), "wantBelow", "below taken", tank)

-- ---------------------------------------------------------------- reconcile
local function info(over)
	local i = {leaderOnline = true, leaderInParty = false, leaderIsLeader = false, party = {}, crew = {}}
	for k, v in pairs(over or {}) do i[k] = v end
	return i
end
local events, closed = K.reconcile(st, cfg, L.id, info({leaderInParty = true, leaderIsLeader = true}), now + 10)
eq(#events, 0, "nothing yet")
check(closed == nil, "still open")
check(not L.hadParty, "an invite alone is no party")
events, closed = K.reconcile(st, cfg, L.id, info({leaderInParty = true, leaderIsLeader = true, party = {[10] = true},
	crew = {healer}}), now + 20)
eq(#events, 1, "one event")
eq(events[1].kind, "joined", "joined")
eq(L.members[1].st, "joined", "member joined")
eq(#L.crew, 0, "a listing member is not crew")
check(L.hadParty, "now a party")
-- dps 1 accepted but never answers the invite
K.decide(st, cfg, 1, L.id, 11, true, now + 20)
events = K.reconcile(st, cfg, L.id, info({leaderInParty = true, leaderIsLeader = true, party = {[10] = true}}),
	now + 20 + cfg.inviteSeconds)
eq(events[1] and events[1].kind, "inviteExpired", "invite ran out")
eq(#L.members, 1, "slot open again")
-- the healer leaves the party
events = K.reconcile(st, cfg, L.id, info({leaderInParty = true, leaderIsLeader = true, party = {}}), now + 200)
eq(events[1] and events[1].kind, "left", "left")
eq(K.open(cfg, L).healer, 1, "healer slot open again")
-- the party broke up (leader alone, not in a party any more)
events, closed = K.reconcile(st, cfg, L.id, info({leaderInParty = false}), now + 210)
eq(closed and closed.closed, "disbanded", "party broke up")
check(st.listings[L.id] == nil, "removed")
eq(st.byLeader[1], nil, "leader free")
eq(K.appCount(st, 12), 0, "applications of a closed listing are gone")

local function fresh(guid, voc, input)
	local w = who(guid, voc, 400)
	return K.post(st, cfg, acts, w, input, now), w
end
local E = fresh(40, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank", exp = 15})
_, closed = K.reconcile(st, cfg, E.id, info(), now + 15 * 60)
eq(closed and closed.closed, "expired", "expired")
local O = fresh(41, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank"})
_, closed = K.reconcile(st, cfg, O.id, info({leaderOnline = false}), now + 1)
eq(closed and closed.closed, "offline", "leader offline")
local P = fresh(42, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank"})
_, closed = K.reconcile(st, cfg, P.id, info({leaderInParty = true, leaderIsLeader = false}), now + 1)
eq(closed and closed.closed, "leaderLeft", "leader no longer leads")
-- full: every slot joined
local F = fresh(43, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank"})
local d = who(44, ids.deadeye, 400)
ap(d, F.id, "dps", "the last slot")
K.decide(st, cfg, 43, F.id, 44, true, now)
_, closed = K.reconcile(st, cfg, F.id, info({leaderInParty = true, leaderIsLeader = true}), now + 1)
check(closed == nil, "not full while the invite is pending")
_, closed = K.reconcile(st, cfg, F.id, info({leaderInParty = true, leaderIsLeader = true, party = {[44] = true}}), now + 2)
eq(closed and closed.closed, "full", "full")
eq(#K.reconcile(st, cfg, 4242, info(), now), 0, "unknown listing: no events")

-- close by leader and staff, logout
local G = fresh(45, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank"})
local _, cwhy = K.closeBy(st, who(46, ids.warrior), G.id)
eq(cwhy, "notYours", "not the leader")
local closedBy = K.closeBy(st, who(47, ids.warrior, 1, {staff = true}), G.id)
eq(closedBy and closedBy.closed, "staff", "staff closes")
G = fresh(48, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank"})
eq(K.closeBy(st, who(48, ids.warrior), nil).closed, "closed", "the leader closes its own")
G = fresh(49, ids.warrior, {a = "raid", want = {dps = 2}, role = "tank"})
ap(who(50, ids.deadeye), G.id, "dps", "applies before the logout")
local gone, gids = K.dropPlayer(st, 49)
eq(gone and gone.closed, "offline", "logout closes")
eq(#gids, 0, "the leader had no applications")
G = fresh(51, ids.warrior, {a = "raid", want = {dps = 2}, role = "tank"})
ap(who(52, ids.deadeye), G.id, "dps", "applicant")
gone, gids = K.dropPlayer(st, 52)
check(gone == nil, "an applicant's logout closes nothing")
eq(gids[1], G.id, "its application is gone")
eq(#G.appOrder, 0, "listing has no application")

-- ---------------------------------------------------------------- realms in the list, the payload
local S1 = fresh(60, ids.warrior, {a = "rift", lo = 1, hi = 3, want = {dps = 1, healer = 1}, role = "tank", note = "hi"})
local seasonLead = who(61, ids.warrior, 400, {realm = 3})
local S2 = K.post(st, cfg, acts, seasonLead, {a = "rift", lo = 1, hi = 3, want = {dps = 1}, role = "tank"}, now)
local function idsIn(list)
	local set = {}
	for _, r in ipairs(list.rows) do set[r.id] = r end
	return set
end
local viewer = who(62, ids.illusionist, 300)
local seen1 = idsIn(K.list(st, cfg, acts, viewer, now + 30))
check(seen1[S1.id] ~= nil, "standard listing shown")
check(seen1[S2.id] == nil, "season listing hidden from a standard character")
local seen2 = idsIn(K.list(st, cfg, acts, who(63, ids.deadeye, 300, {realm = 3}), now))
check(seen2[S2.id] ~= nil and seen2[S1.id] == nil, "season character sees its realm only")
eq(seen2[S2.id].season, true, "season mark")
local seen3 = idsIn(K.list(st, cfg, acts, who(64, ids.deadeye, 300, {staff = true}), now))
check(seen3[S1.id] ~= nil and seen3[S2.id] ~= nil, "staff see every realm")
local row = seen1[S1.id]
eq(row.an, "Rift T1-3", "row activity text")
eq(row.ld, "P60", "row leader")
eq(row.comp[1].r, "tank", "leader's role")
eq(row.comp[1].st, "leader", "leader mark")
eq(row.open.healer, 1, "open healer")
eq(row.left, cfg.defaultExpiry * 60 - 30, "time left")
eq(row.note, "hi", "note")
check(not row.mine, "not mine")
ap(viewer, S1.id, "healer", "viewer applies")
local mineList = K.list(st, cfg, acts, who(60, ids.warrior, 400), now + 40)
eq(mineList.badge, 1, "badge")
eq(mineList.mine.apps[1].n, "P62", "applicant in mine")
eq(mineList.mine.apps[1].ago, 40, "applied 40 s ago")
eq(mineList.mine.input.role, "tank", "the form values")
eq(idsIn(K.list(st, cfg, acts, viewer, now))[S1.id].ap, "healer", "applied mark")
-- a listing with no open slot is hidden from others
local Full = fresh(65, ids.warrior, {a = "raid", want = {dps = 1}, role = "tank"})
ap(who(66, ids.deadeye), Full.id, "dps", "fills")
K.decide(st, cfg, 65, Full.id, 66, true, now)
check(idsIn(K.list(st, cfg, acts, viewer, now))[Full.id] == nil, "no open slot: hidden")
check(idsIn(K.list(st, cfg, acts, who(65, ids.warrior), now))[Full.id] ~= nil, "but the leader sees it")
local init = K.init(cfg, acts, who(70, ids.ironsage, 321))
eq(init.my[1], "healer", "init: my roles")
eq(init.lv, 321, "init: level")
eq(#init.roles, 3, "init: roles")
eq(init.lim.note, cfg.noteMax, "init: note limit")

-- ---------------------------------------------------------------- quick join
st = K.newState() -- (no other listing to match into)
local q, qwhy = K.queueJoin(st, cfg, acts, who(80, ids.deadeye, 300, {party = {leader = true, members = {}}}), "dps", "", now)
eq(qwhy, "inParty", "queue: in a party")
q, qwhy = K.queueJoin(st, cfg, acts, who(80, ids.deadeye, 300), "tank", "", now)
eq(qwhy, "role", "queue: wrong role")
q, qwhy = K.queueJoin(st, cfg, acts, who(80, ids.deadeye, 300), "dps", "picnic", now)
eq(qwhy, "activity", "queue: bad activity")
check(K.queueJoin(st, cfg, acts, who(80, ids.deadeye, 300), "dps", "tower", now) ~= nil, "queued for the tower")
check(K.queueJoin(st, cfg, acts, who(81, ids.illusionist, 300), "healer", "", now) ~= nil, "queued as healer")
check(K.queueJoin(st, cfg, acts, who(82, ids.elementalist, 50), "dps", "", now) ~= nil, "low level queued")
local T = fresh(83, ids.juggernaut, {a = "tower", lo = 1, hi = 50, want = {dps = 1, healer = 1}, role = "tank", minLevel = 100,
	auto = true})
local matches = K.match(st, cfg, now + 5)
eq(#matches, 2, "two matched")
local byGuid = {}
for _, m in ipairs(matches) do byGuid[m.guid] = m end
check(byGuid[80] and byGuid[80].id == T.id or false, "dps into the tower group")
check(byGuid[81] and byGuid[81].auto or false, "auto accept flag")
eq(T.apps[80].quick, true, "quick application")
check(byGuid[82] == nil, "the low level stays queued")
check(st.queue[80] == nil and st.queue[81] == nil, "matched characters left the queue")
check(st.queue[82] ~= nil, "still queued")
matches = K.match(st, cfg, now + cfg.queueMinutes * 60)
eq(matches[1] and matches[1].expired, true, "queue entry ran out")
eq(matches[1] and matches[1].who.name, "P82", "with its entry")
check(K.queueLeave(st, 82) == false, "already gone")
local list = K.list(st, cfg, acts, who(84, ids.deadeye), now)
eq(list.queue, nil, "not queued")
K.queueJoin(st, cfg, acts, who(84, ids.deadeye), "dps", "", now)
eq(K.list(st, cfg, acts, who(84, ids.deadeye), now + 9).queue.since, 9, "queued 9 s")

-- ---------------------------------------------------------------- raid listings of 15 (one engine party, raid.lua groupOf)
do
	local raidCfg = dofile("data/scripts/chaos/raid_config.lua")
	local R = K.activity(acts, "raid")
	eq(R.max, raidCfg.maxPlayers, "a raid listing holds the raid's maxPlayers")
	eq(R.max, 15, "raid: 15")
	eq(K.activity(acts, "rift").max, cfg.maxParty, "other activities: maxParty")
	eq(K.activity(acts, "rift").max, 10, "rift: 10")
	eq(R.per.tank, 3, "raid: up to 3 tanks wanted")
	eq(R.per.healer, 4, "raid: up to 4 healers wanted")
	eq(R.per.dps, 12, "raid: up to 12 DPS wanted")
	eq(K.activity(acts, "dungeon").per.dps, cfg.maxPerRole, "dungeon: maxPerRole")
	eq(K.activity(acts, "rift").suggest, nil, "no suggestion for a rift")
	eq(1 + R.suggest.tank + R.suggest.healer + R.suggest.dps, 15, "the raid suggestion fills 15")
	check(R.max >= raidCfg.minPlayers, "a full raid listing can open the raid")
	local rs = K.newState()
	local lead = who(300, ids.juggernaut, 900)
	local function rpost(w, input)
		return K.post(rs, cfg, acts, w, input, now)
	end
	local function rrefused(input, reason, label)
		local Lr, whyR = rpost(lead, input)
		check(Lr == nil, label .. " refused")
		eq(whyR, reason, label .. " reason")
	end
	rrefused({a = "raid", want = {tank = 3, healer = 4, dps = 8}, role = "tank"}, "size", "raid of 16")
	rrefused({a = "raid", want = {tank = 4, healer = 3, dps = 7}, role = "tank"}, "perRole", "raid: 4 tanks wanted")
	rrefused({a = "raid", want = {tank = 2, healer = 5, dps = 7}, role = "tank"}, "perRole", "raid: 5 healers wanted")
	rrefused({a = "raid", want = {tank = 0, healer = 0, dps = 13}, role = "tank"}, "perRole", "raid: 13 DPS wanted")
	rrefused({a = "rift", lo = 1, hi = 2, want = {tank = 1, healer = 3, dps = 6}, role = "tank"}, "size", "rift of 11")
	rrefused({a = "rift", lo = 1, hi = 2, want = {dps = 7}, role = "tank"}, "perRole", "rift: 7 DPS")
	check(K.post(K.newState(), cfg, acts, who(301, ids.deadeye, 900), {a = "raid", want = {tank = 2, dps = 12}, role = "dps"},
		now) ~= nil, "raid: 2 tanks and 12 DPS")
	-- a raid with a party of 3 already: the crew counts against the 15
	local withCrew = who(302, ids.sentinel, 900, {party = {leader = true, members = {who(303, ids.deadeye, 900),
		who(304, ids.ninja, 900), who(305, ids.ironsage, 900)}}})
	check(K.post(K.newState(), cfg, acts, withCrew, {a = "raid", want = {tank = 1, healer = 2, dps = 8}, role = "tank"}, now)
		~= nil, "raid: 4 in the party + 11 wanted")
	local _, whyC = K.post(K.newState(), cfg, acts, withCrew, {a = "raid", want = {tank = 1, healer = 2, dps = 9},
		role = "tank"}, now)
	eq(whyC, "size", "raid: 4 in the party + 12 wanted")

	local RL = rpost(lead, {a = "raid", t = 1, want = {tank = 2, healer = 3, dps = 9}, minLevel = 800, role = "tank"})
	check(RL ~= nil, "raid of 15 posted")
	eq(RL.max, 15, "listing max 15")
	eq(K.maxOf(cfg, RL), 15, "maxOf")
	eq(K.maxOf(cfg, {}), cfg.maxParty, "maxOf without a max")
	local _, openTotal = K.open(cfg, RL)
	eq(openTotal, 14, "14 open slots")
	local row = K.row(cfg, acts, RL, lead, now)
	eq(row.max, 15, "row max")
	eq(row.an, "Raid: " .. raidCfg.name, "row names the raid")
	-- 14 applicants (2 tanks, 3 healers, 9 DPS), all accepted
	local vocs = {tank = ids.juggernaut, healer = ids.illusionist, dps = ids.deadeye}
	local order = {"tank", "tank", "healer", "healer", "healer"}
	for _ = 1, 9 do order[#order + 1] = "dps" end
	local party, crewList = {}, {}
	for i, role in ipairs(order) do
		local w = who(310 + i, vocs[role], 900)
		local app = K.apply(rs, cfg, w, RL.id, role, now)
		check(app ~= nil, "raid applicant " .. i)
		if i == 14 then
			-- an outsider the leader invited by hand fills the 15th place: the last accept is refused
			local outsider = who(399, ids.berserker, 900)
			K.reconcile(rs, cfg, RL.id, info({leaderInParty = true, leaderIsLeader = true, party = party,
				crew = {outsider}}), now + 1)
			eq(K.size(RL), 15, "13 invited + leader + outsider")
			local okF, whyF = K.decide(rs, cfg, 300, RL.id, w.guid, true, now + 1)
			check(not okF, "16th refused")
			eq(whyF, "partyFull", "raid party full at 15")
			K.reconcile(rs, cfg, RL.id, info({leaderInParty = true, leaderIsLeader = true, party = party}), now + 2)
			eq(K.size(RL), 14, "the outsider left")
		end
		local okA = K.decide(rs, cfg, 300, RL.id, w.guid, true, now + 2)
		check(okA, "raid accept " .. i)
		party[w.guid] = true
		crewList[#crewList + 1] = w
	end
	eq(K.size(RL), 15, "15 on their way")
	eq(#K.row(cfg, acts, RL, lead, now).comp, 15, "15 in the row's composition")
	_, openTotal = K.open(cfg, RL)
	eq(openTotal, 0, "no slot open")
	-- 13 joined, one invite pending: the listing stays
	local partial = {}
	for i = 1, 13 do partial[crewList[i].guid] = true end
	local evs, closedR = K.reconcile(rs, cfg, RL.id, info({leaderInParty = true, leaderIsLeader = true, party = partial,
		crew = {(table.unpack or unpack)(crewList, 1, 13)}}), now + 3)
	local joined = 0
	for _, m in ipairs(RL.members) do
		if m.st == "joined" then joined = joined + 1 end
	end
	eq(joined, 13, "13 joined")
	eq(#evs, 0, "they joined on the earlier reconcile")
	eq(closedR, nil, "one invite pending: still listed")
	eq(#RL.crew, 0, "listing members are not crew")
	-- an update to a rift is refused: 15 do not fit in 10
	local _, whyU = K.post(rs, cfg, acts, lead, {a = "rift", lo = 1, hi = 2, want = {tank = 2, healer = 3, dps = 9},
		role = "tank"}, now + 10)
	eq(whyU, "perRole", "15 do not fit a rift")
	_, whyU = K.post(rs, cfg, acts, lead, {a = "rift", lo = 1, hi = 2, want = {tank = 2, healer = 3, dps = 6},
		role = "tank"}, now + 10)
	eq(whyU, "size", "12 do not fit a rift")
	eq(RL.a, "raid", "still a raid")
	evs, closedR = K.reconcile(rs, cfg, RL.id, info({leaderInParty = true, leaderIsLeader = true, party = party,
		crew = crewList}), now + 4)
	eq(#evs, 1, "the 14th joined")
	eq(closedR and closedR.closed, "full", "raid of 15 full and closed")
	local init = K.init(cfg, acts, lead)
	eq(init.lim.party, cfg.maxParty, "init: default size")
	eq(K.activity(init.acts, "raid").max, 15, "init: the raid's size")
end

-- ---------------------------------------------------------------- party_finder.lua against a mocked engine
ChaosPartyFinderCore = nil
dofile("data/scripts/chaos/party_finder_core.lua")
local registry, globalEvents = {}, {}
function CreatureEvent(name)
	local e = {name = name, type = function() end, register = function() end}
	registry[name] = e
	return e
end
function GlobalEvent(name)
	local e = {name = name, interval = function() end, register = function() end}
	globalEvents[name] = e
	return e
end
local decodeQueue = {}
json = {encode = function(t) return t end, decode = function(s) return decodeQueue[s] end}
local sent = {}
Chaos.sendChunked = function(player, opcode, payload)
	sent[#sent + 1] = {to = player.name, op = opcode, action = payload.action, data = payload.data}
	return true
end
local players = {}
local Pmeta = {}
Pmeta.__index = Pmeta
local function mkPlayer(guid, name, voc, level, group)
	local p = setmetatable({guid = guid, id = 5000 + guid, name = name, voc = voc, level = level, group = group or 1,
		messages = {}, events = {}}, Pmeta)
	players[p.id] = p
	return p
end
function Pmeta:getGuid() return self.guid end
function Pmeta:getId() return self.id end
function Pmeta:getName() return self.name end
function Pmeta:getLevel() return self.level end
function Pmeta:getVocation() local v = self.voc return {getId = function() return v end, getName = function() return "Voc" .. v end} end
function Pmeta:getGroup() local g = self.group return {getId = function() return g end} end
function Pmeta:getParty() return self.party end
function Pmeta:sendTextMessage(kind, text) self.messages[#self.messages + 1] = text end
function Pmeta:registerEvent(name) self.events[name] = true end
function Player(cid) return players[cid] end
local PartyMeta = {}
PartyMeta.__index = PartyMeta
function Party(leader)
	local party = setmetatable({leader = leader, members = {}, invites = {}}, PartyMeta)
	leader.party = party
	return party
end
function PartyMeta:getLeader() return self.leader end
function PartyMeta:getMembers() return self.members end
function PartyMeta:addInvite(p) self.invites[#self.invites + 1] = p return true end
function PartyMeta:join(p) self.members[#self.members + 1] = p p.party = self end
Game = {getPlayers = function() local l = {} for _, p in pairs(players) do l[#l + 1] = p end return l end}
ChaosRateLimit = nil
ChaosSeason = nil

dofile("data/scripts/chaos/party_finder.lua")
local PF = ChaosPartyFinder
check(registry.ChaosPartyFinderExtended ~= nil, "opcode event registered")
check(globalEvents.ChaosPartyFinderThink ~= nil, "think registered")
local function op(player, action, data)
	local key = tostring(#sent) .. action .. player.name
	decodeQueue[key] = {action = action, data = data}
	registry.ChaosPartyFinderExtended.onExtendedOpcode(player, ChaosOpcodes.partyFinder, key)
end
local function last(name, action)
	for i = #sent, 1, -1 do
		if sent[i].to == name and (not action or sent[i].action == action) then return sent[i] end
	end
	return nil
end
local lead = mkPlayer(1, "Brannoc", ids.juggernaut, 400)
local healP = mkPlayer(2, "Seris", ids.illusionist, 350)
local dpsP = mkPlayer(3, "Kael", ids.deadeye, 320)
local gm = mkPlayer(4, "Warden", ids.warrior, 100, 4)
registry.ChaosPartyFinderLogin.onLogin(lead)
check(lead.events.ChaosPartyFinderExtended and lead.events.ChaosPartyFinderLogout, "login registers the events")

op(lead, "open", {})
eq(last("Brannoc", "init").op, 208, "init on opcode 208")
eq(#last("Brannoc", "init").data.acts, 8, "init activities")
eq(last("Brannoc", "list").data.mine, nil, "no listing yet")
op(lead, "post", {a = "dungeon", t = 1, want = {tank = 0, healer = 1, dps = 1}, minLevel = 300, note = "fast run", exp = 30,
	role = "tank"})
local mine = last("Brannoc", "list").data.mine
check(mine ~= nil, "listing posted")
eq(mine.an, "Dungeon: Bones Dungeon", "posted activity")
local id = mine.id
op(lead, "post", {a = "dungeon", t = 1, want = {healer = 1}, role = "healer"})
eq(last("Brannoc", "notice").data.kind, "error", "Juggernaut cannot lead as healer")

op(healP, "open", {})
local rows = last("Seris", "list").data.rows
eq(#rows, 1, "healer sees the listing")
op(healP, "apply", {id = id, role = "healer"})
local note = last("Brannoc", "notice")
eq(note.data.kind, "apply", "leader is told")
check(note.data.text:find("Seris", 1, true) ~= nil, "applicant named")
check(lead.messages[#lead.messages]:find("applied", 1, true) ~= nil, "console line for the leader")
eq(last("Brannoc", "badge").data.n, 1, "badge 1")
op(dpsP, "apply", {id = id, role = "tank"})
eq(last("Kael", "notice").data.kind, "error", "Deadeye cannot tank")
op(dpsP, "apply", {id = id, role = "dps"})
eq(last("Brannoc", "badge").data.n, 2, "badge 2")

op(lead, "decline", {id = id, g = 3})
check(last("Kael", "notice").data.text:find("declined", 1, true) ~= nil, "applicant told about the decline")
eq(last("Brannoc", "badge").data.n, 1, "badge back to 1")
op(lead, "accept", {id = id, g = 2})
check(lead.party ~= nil, "a party was started")
eq(lead.party.invites[1], healP, "real party invite")
eq(last("Seris", "notice").data.kind, "accepted", "applicant told to accept")
-- the healer accepts the engine invite
lead.party:join(healP)
PF.tick()
eq(PF.state.listings[id].members[1].st, "joined", "tick saw the join")
-- the declined DPS may not apply again at once; another DPS fills the last slot
op(dpsP, "apply", {id = id, role = "dps"})
eq(last("Kael", "notice").data.kind, "error", "declined: wait")
local dps3 = mkPlayer(5, "Ilya", ids.ninja, 330)
op(dps3, "queue", {role = "dps"})
PF.tick()
eq(PF.state.listings[id].apps[5].quick, true, "quick join application")
check(last("Brannoc", "notice").data.text:find("Quick join", 1, true) ~= nil, "leader told about the quick join")
op(lead, "accept", {id = id, g = 5})
lead.party:join(dps3)
PF.tick()
eq(PF.state.listings[id], nil, "full listing closed")
check(last("Brannoc", "notice").data.text:find("full", 1, true) ~= nil, "leader told it is full")

-- staff close of another listing; the logout of a leader
op(dpsP, "post", {a = "raid", want = {tank = 1}, role = "dps"})
local raidId = PF.state.byLeader[3]
check(raidId ~= nil, "second listing")
op(gm, "unlist", {id = raidId})
eq(PF.state.listings[raidId], nil, "staff closed it")
-- (post cooldown) a fresh leader posts and logs out
local other = mkPlayer(6, "Rhea", ids.sentinel, 280)
op(other, "post", {a = "omen", t = 3, want = {dps = 2}, role = "tank"})
local omenId = PF.state.byLeader[6]
check(omenId ~= nil, "omen listing")
op(healP, "open", {})
registry.ChaosPartyFinderLogout.onLogout(other)
eq(PF.state.listings[omenId], nil, "logout closed it")
PF.tick()
check(last("Seris", "list") ~= nil, "open window was pushed the change")
op(healP, "hide", {})
eq(PF.watch[healP.id], nil, "hidden window not watched")
op(healP, "bogus", {})
op(healP, "apply", {id = "x", role = 5})
eq(last("Seris", "notice").data.kind, "error", "garbage refused")

if failures > 0 then
	print(string.format("party_finder_test: %d of %d checks failed", failures, count))
	os.exit(1)
end
print(string.format("party_finder_test: OK (%d checks)", count))
