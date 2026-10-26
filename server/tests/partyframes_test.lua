-- Run from the server/ folder: luajit tests/partyframes_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the party frames' rules (data/scripts/chaos/partyframes_core.lua): range by squares and floors, exact numbers
-- only for members in range, rough health for far ones, the flags (leader / fight / dead / connection lost / you), the
-- state for a viewer (leader first, empty when alone or not listed, capped), the signature (a timer ticking is not a
-- change), and the action checks (kick, pass the leadership, invite).
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/partyframes_core.lua")
local P = ChaosPartyFrames

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, tostring(what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

local function member(id, name, x, y, z, hp, extra)
	local m = {id = id, name = name, level = 100 + id, voc = 4, hp = hp or 800, hpMax = 1000, mp = 300, mpMax = 500, x = x, y = y, z = z,
		outfit = {t = 128, h = 1, b = 2, l = 3, f = 4, a = 0}}
	for k, v in pairs(extra or {}) do
		m[k] = v
	end
	return m
end
local viewer = member(1, "Aria", 1000, 1000, 7)

-- ------------------------------------------------------------------ range
local near, dz, d = P.range(viewer, member(2, "B", 1010, 990, 7))
ok(near, "near"); eq(dz, 0, "same floor"); eq(d, 10, "Chebyshev distance")
ok(P.range(viewer, member(2, "B", 1050, 1000, 7)), "at the edge")
ok(not P.range(viewer, member(2, "B", 1051, 1000, 7)), "one square too far")
ok(P.range(viewer, member(2, "B", 1000, 1000, 9)), "two floors down")
ok(not P.range(viewer, member(2, "B", 1000, 1000, 10)), "three floors down")
local _, dz2 = P.range(viewer, member(2, "B", 1000, 1000, 5))
eq(dz2, -2, "up is negative")

-- ------------------------------------------------------------------ health percent
eq(P.pct(500, 1000), 50, "pct"); eq(P.pct(0, 0), 0, "no max"); eq(P.pct(2000, 1000), 100, "capped")
eq(P.farPct(512, 1000), 50, "far health in steps"); eq(P.farPct(1000, 1000), 100, "full is 100")
eq(P.farPct(999, 1000), 90, "hurt is never 100"); eq(P.farPct(3, 1000), 10, "alive is never 0"); eq(P.farPct(0, 1000), 0, "dead is 0")
eq(P.farPct(960, 1000, 5), 95, "step 5")

-- ------------------------------------------------------------------ an entry
local e = P.entry(viewer, member(2, "Boran", 1010, 1000, 7, 400), 1)
eq(e.h, 400, "exact health in range"); eq(e.H, 1000, "max"); eq(e.m, 300, "exact mana in range"); eq(e.d, 10, "distance")
eq(e.p, 40, "percent"); eq(e.far, nil, "not far"); eq(e.lv, 102, "level"); eq(e.o.t, 128, "outfit")
local far = P.entry(viewer, member(3, "Cael", 1500, 1000, 7, 437), 1)
eq(far.h, nil, "no exact health far"); eq(far.m, nil, "no mana far"); eq(far.d, nil, "no distance far"); eq(far.far, 1, "far flag")
eq(far.p, 40, "rough percent far"); eq(far.b, nil, "no buffs far"); eq(far.dz, 0, "floor difference still known")
local floors = P.entry(viewer, member(4, "Dun", 1000, 1000, 12), 1)
eq(floors.far, 1, "other floors far"); eq(floors.dz, 5, "five floors down")
local me = P.entry(viewer, viewer, 1)
eq(me.h, 800, "own numbers"); eq(me.d, 0, "own distance"); ok(me.f % 32 >= 16, "self flag")
local withBuffs = P.entry(viewer, member(5, "Eth", 1001, 1001, 7, 800, {buffs = {{i = "x", t = 0, l = 4000}}}), 1)
eq(#withBuffs.b, 1, "buffs in range")

-- ------------------------------------------------------------------ flags
local F = P.FLAG
eq(P.flags(member(2, "B", 0, 0, 7), 2, 1), F.leader, "leader")
eq(P.flags(member(2, "B", 0, 0, 7, 800, {fight = true}), 1, 1), F.fight, "fight")
eq(P.flags(member(2, "B", 0, 0, 7, 0), 1, 1), F.dead, "dead by health")
eq(P.flags(member(2, "B", 0, 0, 7, 800, {dead = true}), 1, 1), F.dead, "dead flag")
eq(P.flags(member(2, "B", 0, 0, 7, 800, {offline = true}), 1, 1), F.offline, "connection lost")
eq(P.flags(member(1, "A", 0, 0, 7, 800, {fight = true}), 1, 1), F.leader + F.fight + F.self, "all of them add up")

-- ------------------------------------------------------------------ the state
local roster = {member(2, "Boran", 1010, 1000, 7), viewer, member(3, "Cael", 1500, 1000, 7)}
local st = P.state(viewer, roster, 3)
eq(st.leader, 3, "leader"); eq(#st.members, 3, "three members"); eq(st.members[1].i, 3, "leader first")
eq(st.members[2].i, 2, "then the order given"); eq(st.members[1].far, 1, "the far leader is far")
eq(#P.state(viewer, {viewer}, 1).members, 0, "alone: no party")
eq(#P.state(viewer, {member(2, "B", 0, 0, 7), member(3, "C", 0, 0, 7)}, 2).members, 0, "a viewer who is not listed gets nothing")
local big = {}
for i = 1, 30 do
	big[#big + 1] = member(i, "M" .. i, 1000, 1000, 7)
end
eq(#P.state(viewer, big, 1).members, P.cfg.maxMembers, "capped")
-- nothing about an outsider can get in: only what is passed in is listed
for _, m in ipairs(P.state(viewer, roster, 3).members) do
	ok(m.i == 1 or m.i == 2 or m.i == 3, "only roster members listed")
end

-- ------------------------------------------------------------------ signature
local s1 = P.signature(P.state(viewer, roster, 3))
eq(s1, P.signature(P.state(viewer, roster, 3)), "same state, same signature")
local roster2 = {member(2, "Boran", 1010, 1000, 7, 799), viewer, member(3, "Cael", 1500, 1000, 7)}
ok(s1 ~= P.signature(P.state(viewer, roster2, 3)), "a health change changes it")
roster2 = {member(2, "Boran", 1010, 1000, 7, 800, {buffs = {{i = "a", t = 0, l = 9000}}}), viewer, member(3, "Cael", 1500, 1000, 7)}
local s2 = P.signature(P.state(viewer, roster2, 3))
roster2[1].buffs[1].l = 8000
eq(s2, P.signature(P.state(viewer, roster2, 3)), "a buff timer ticking is no change")
roster2[1].buffs[1].i = "b"
ok(s2 ~= P.signature(P.state(viewer, roster2, 3)), "another buff is")
-- far members: tiny health changes inside a step are not sent
local f1 = P.signature(P.state(viewer, {viewer, member(3, "Cael", 1500, 1000, 7, 500)}, 1))
local f2 = P.signature(P.state(viewer, {viewer, member(3, "Cael", 1500, 1000, 7, 504)}, 1))
eq(f1, f2, "a far member's health inside a step does not change the signature")

-- ------------------------------------------------------------------ actions
local ids = {[1] = true, [2] = true, [3] = true}
local okk, why = P.canKick(1, 1, 2, ids)
ok(okk, "the leader kicks a member")
okk, why = P.canKick(2, 1, 3, ids); ok(not okk and why:find("leader"), "a member cannot kick: " .. tostring(why))
okk, why = P.canKick(1, 1, 1, ids); ok(not okk, "the leader cannot kick itself")
okk, why = P.canKick(1, 1, 99, ids); ok(not okk and why:find("not in your party"), "an outsider cannot be kicked: " .. tostring(why))
okk = P.canPassLeadership(1, 1, 2, ids); ok(okk, "pass the leadership")
okk, why = P.canPassLeadership(2, 1, 3, ids); ok(not okk, "only the leader passes it")
okk = P.canPassLeadership(1, 1, 1, ids); ok(not okk, "not to yourself")
okk = P.canPassLeadership(1, 1, 99, ids); ok(not okk, "not to an outsider")

local target = {id = 9, name = "Dara", isSelf = false, inParty = false}
okk = P.canInvite(1, nil, "Dara", target); ok(okk, "anyone may start a party by inviting")
okk, why = P.canInvite(1, {leaderId = 1, members = 3, invited = {}}, "Dara", target); ok(okk, "the leader invites")
okk, why = P.canInvite(2, {leaderId = 1, members = 3, invited = {}}, "Dara", target); ok(not okk and why:find("leader"), "a member does not: " .. tostring(why))
okk, why = P.canInvite(1, nil, "", target); ok(not okk, "an empty name")
okk, why = P.canInvite(1, nil, "Dara", nil); ok(not okk and why:find("online"), "an unknown name: " .. tostring(why))
okk, why = P.canInvite(1, nil, "Dara", {id = 1, name = "Aria", isSelf = true}); ok(not okk, "not yourself")
okk, why = P.canInvite(1, nil, "Dara", {id = 9, name = "Dara", inParty = true}); ok(not okk and why:find("already in a party"), "already in a party: " .. tostring(why))
okk, why = P.canInvite(1, {leaderId = 1, members = 3, invited = {[9] = true}}, "Dara", target); ok(not okk and why:find("already invited"), "already invited: " .. tostring(why))
okk, why = P.canInvite(1, {leaderId = 1, members = P.cfg.maxMembers, invited = {}}, "Dara", target); ok(not okk and why:find("full"), "a full party: " .. tostring(why))
okk = P.canInvite(1, nil, 42, target); ok(not okk, "a name that is not text")

okk, why = P.canInvite(1, nil, "Dara", {id = 9, name = "Dara", isSelf = false, inParty = true, hidden = true})
ok(not okk and why:find("no player called"), "a hidden player answers like an offline one: " .. tostring(why))

-- ---------------------------------------------------------------- the party's XP bonus in the state (O261)
dofile("data/scripts/chaos/party_xp_core.lua")
do
	local X = ChaosPartyXpCore
	local function line(id, l) local m = member(id, "M" .. id, 0, 0, 7) m.line = l return m end
	local roster = {line(1, 4), line(2, 4)}
	local s = P.withShare(P.state(roster[1], roster, 1), roster, true, true)
	eq(s.xp.p, 20, "one class line: +20%"); eq(s.xp.on, 1, "working")
	roster = {line(1, 4), line(2, 3)}
	s = P.withShare(P.state(roster[1], roster, 1), roster, true, false)
	eq(s.xp.p, 30, "two lines: +30%"); eq(s.xp.on, 2, "switched on, not working")
	s = P.withShare(P.state(roster[1], roster, 1), roster, false, false)
	eq(s.xp.on, 0, "not switched on")
	local lonely = P.withShare(P.state(roster[1], {roster[1]}, 1), {roster[1]}, true, true)
	eq(lonely.xp, nil, "no party, no bonus"); eq(#lonely.members, 0)
	local sig1 = P.signature(P.withShare(P.state(roster[1], roster, 1), roster, true, true))
	local sig2 = P.signature(P.withShare(P.state(roster[1], roster, 1), roster, true, false))
	ok(sig1 ~= sig2, "a share that switches off is a change")
	eq(X.bonusPercent(5), 150, "five lines: +150%"); eq(X.bonusPercent(7), 150, "more than five count as five")
	eq(X.bonusPercent(3), 60); eq(X.bonusPercent(0), 0); eq(X.bonusPercent(0 / 0), 0)
end

if fails > 0 then
	print(fails .. " of " .. checks .. " checks FAILED")
	os.exit(1)
end
print("party frames tests OK (" .. checks .. " checks)")
