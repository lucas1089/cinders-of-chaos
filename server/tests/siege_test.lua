-- Run from the server/ folder: luajit tests/siege_test.lua (and lua5.3; CI runs both)
-- Pure logic of the guild siege (siege_core.lua) with the real siege_config.lua: the weekly schedule, sign-up rules,
-- brackets, the arena geometry, capture-point control, scoring order, rewards and the champion title.
dofile("data/scripts/chaos/siege_core.lua")
local S = ChaosSiege
local cfg = dofile("data/scripts/chaos/siege_config.lua")

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	eq(not not v, true, m)
end
local function copy(t, over)
	local c = {}
	for k, v in pairs(t) do
		c[k] = v
	end
	for k, v in pairs(over or {}) do
		c[k] = v
	end
	return c
end

-- ---------------------------------------------------------------- schedule
local thu = os.time({year = 2026, month = 10, day = 8, hour = 10, min = 0, sec = 0}) -- Thursday
eq(os.date("*t", thu).wday, 5, "fixture is a Thursday")
local at = S.nextStart(thu, cfg)
local d = os.date("*t", at)
eq(d.wday, cfg.weekday, "next start on the configured weekday")
eq(d.hour, cfg.hour, "at the configured hour")
eq(d.min, cfg.minute, "and minute")
eq(d.day, 10, "Saturday 10 October")
-- on the day before the time, the same day; at or after the time, a week later
local satMorning = os.time({year = 2026, month = 10, day = 10, hour = 9, min = 0, sec = 0})
eq(S.nextStart(satMorning, cfg), at, "same day before the start")
eq(os.date("*t", S.nextStart(at, cfg)).day, 17, "at the start time: the next week")
eq(os.date("*t", S.nextStart(at + 60, cfg)).day, 17, "after the start: the next week")
local sunday = S.nextStart(thu, copy(cfg, {weekday = 1, hour = 18, minute = 30}))
eq(os.date("*t", sunday).wday, 1, "other weekday")
eq(os.date("*t", sunday).min, 30, "other minute")
eq(os.date("*t", sunday).day, 11, "Sunday 11 October")
-- month boundary
local endOfMonth = os.time({year = 2026, month = 10, day = 29, hour = 12})
eq(os.date("*t", S.nextStart(endOfMonth, cfg)).month, 10, "Saturday 31 October")
eq(os.date("*t", S.nextStart(endOfMonth + 3 * 86400, cfg)).month, 11, "into November")
eq(S.whenText(at), "Saturday 20:00", "when text")
-- sign-ups close signupCloseMinutes before
ok(S.signupsOpen(at - cfg.signupCloseMinutes * 60 - 1, at, cfg), "open just before the close")
ok(not S.signupsOpen(at - cfg.signupCloseMinutes * 60, at, cfg), "closed at the close")
eq(S.durationText(2 * 86400 + 3 * 3600 + 59), "2d 3h", "duration days")
eq(S.durationText(5 * 3600 + 12 * 60), "5h 12m", "duration hours")
eq(S.durationText(59), "0m", "duration minutes")
eq(S.clock(725), "12:05", "clock")

-- ---------------------------------------------------------------- sign-up rules
local good = {guildId = 7, guildName = "Iron Wolves", rank = 3, members = cfg.minMembers, signed = false, count = 0,
	open = true, running = false}
eq(S.signupError(good, cfg), nil, "leader with enough members")
eq(S.signupError(copy(good, {rank = 2}), cfg), nil, "vice-leader may sign up")
ok(S.signupError(copy(good, {rank = 1}), cfg):find("leader"), "a member may not")
ok(S.signupError(copy(good, {guildId = 0}), cfg):find("not in a guild"), "no guild")
ok(S.signupError(copy(good, {members = cfg.minMembers - 1}), cfg):find("at least " .. cfg.minMembers), "too few members")
ok(S.signupError(copy(good, {signed = true}), cfg):find("already"), "already signed up")
ok(S.signupError(copy(good, {open = false}), cfg):find("closed"), "closed")
ok(S.signupError(copy(good, {running = true}), cfg):find("running"), "while a siege runs")
eq(S.capacity(cfg), cfg.perBracket * cfg.maxBrackets, "capacity")
ok(S.signupError(copy(good, {count = S.capacity(cfg)}), cfg):find("full"), "full")
eq(S.signupError(copy(good, {count = S.capacity(cfg) - 1}), cfg), nil, "last place")
ok(S.signupError(copy(good, {rank = 2}), copy(cfg, {signupRank = 3})):find("Only the guild leader can"), "leader only")
-- withdrawing
eq(S.leaveError(copy(good, {signed = true}), cfg), nil, "leader withdraws")
ok(S.leaveError(good, cfg):find("not signed up"), "not signed up")
ok(S.leaveError(copy(good, {signed = true, rank = 1}), cfg):find("leader"), "member cannot withdraw")
ok(S.leaveError(copy(good, {signed = true, open = false}), cfg):find("closed"), "too late to withdraw")

-- ---------------------------------------------------------------- brackets
local function guilds(n)
	local list = {}
	for i = 1, n do
		list[i] = {id = 100 + i, name = "G" .. i, order = i}
	end
	return list
end
local function sizes(br)
	local t = {}
	for i, b in ipairs(br) do
		t[i] = #b
	end
	return table.concat(t, ",")
end
local br, wait = S.brackets(guilds(1), cfg)
eq(#br, 0, "one guild: no siege")
eq(#wait, 1, "it waits")
br, wait = S.brackets(guilds(2), cfg)
eq(sizes(br), "2", "two guilds, one arena")
br = S.brackets(guilds(4), cfg)
eq(sizes(br), "4", "four guilds, one arena")
br = S.brackets(guilds(5), cfg)
eq(sizes(br), "3,2", "five: 3 + 2")
br = S.brackets(guilds(9), cfg)
eq(sizes(br), "3,3,3", "nine: 3 + 3 + 3")
br, wait = S.brackets(guilds(14), cfg)
eq(sizes(br), "4,4,4", "fourteen: three full arenas")
eq(#wait, 2, "two wait")
eq(wait[1].name, "G13", "first come: the late ones wait")
eq(br[1][1].name, "G1", "sign-up order kept")
br, wait = S.brackets(guilds(5), copy(cfg, {minGuilds = 3}))
eq(sizes(br), "4", "minGuilds 3: no arena of 2")
eq(#wait, 1, "the fifth waits")
br = S.brackets(guilds(6), copy(cfg, {minGuilds = 3}))
eq(sizes(br), "3,3", "six with minGuilds 3")
br = S.brackets(guilds(7), copy(cfg, {maxBrackets = 1}))
eq(sizes(br), "4", "one arena only")

-- ---------------------------------------------------------------- geometry
local a = cfg.arena
local L = S.layout(a, 1)
eq(L.arena.x2 - L.arena.x1, a.inner + 1, "arena width")
eq(L.center.x, L.arena.x1 + (a.inner + 1) / 2, "centre x")
eq(L.center.y, L.arena.y1 + (a.inner + 1) / 2, "centre y")
eq(L.box.x1, a.origin.x, "box starts at the origin")
local L2 = S.layout(a, 2)
eq(L2.box.x1, L.box.x2 + 1 + a.bracketGap, "bracket 2 after the gap")
eq(L2.center.y, L.center.y, "same row")
local foot = S.footprint(L, cfg.capture.radius)
local seen, walls, points, basesN = {}, 0, 0, 0
for _, t in ipairs(foot) do
	local k = t.x .. "," .. t.y
	ok(not seen[k], "footprint tile listed once " .. k)
	seen[k] = t
	ok(t.x >= L.box.x1 and t.x <= L.box.x2 and t.y >= L.box.y1 and t.y <= L.box.y2, "inside the box")
	if t.wall then
		walls = walls + 1
	end
	if t.ground == "point" then
		points = points + 1
	end
end
eq(points, (2 * cfg.capture.radius + 1) ^ 2, "capture area")
local function at2(p)
	return seen[p.x .. "," .. p.y]
end
ok(not at2(L.center).wall, "obelisk tile is floor")
for i, b in ipairs(L.bases) do
	local w, slot = S.where(b.spawn, L)
	eq(w, "base", "spawn in a base " .. i)
	eq(slot, i, "spawn in its own base " .. i)
	eq(S.where(b.gate, L), "base", "gate in the base " .. i)
	eq(S.where(b.exit, L), "base", "exit in the base " .. i)
	eq(S.where(b.out, L), "arena", "gate leads into the arena " .. i)
	ok(not at2(b.spawn).wall and not at2(b.gate).wall and not at2(b.exit).wall and not at2(b.out).wall, "walkable " .. i)
	-- the gate is next to the shared wall, the tile between the gate and the out tile is that wall
	local mid = {x = math.floor((b.gate.x + b.out.x) / 2), y = math.floor((b.gate.y + b.out.y) / 2)}
	ok(at2(mid).wall, "a wall separates base and arena " .. i)
	eq(math.abs(b.gate.x - b.out.x) + math.abs(b.gate.y - b.out.y), 2, "gate and out face each other " .. i)
	ok(b.exit.x ~= b.gate.x or b.exit.y ~= b.gate.y, "exit is not the gate " .. i)
	for _, p in ipairs(b.flags) do
		ok(not at2(p).wall and S.where(p, L) == "base", "flag in the room " .. i)
		ok((p.x ~= b.exit.x or p.y ~= b.exit.y) and (p.x ~= b.spawn.x or p.y ~= b.spawn.y), "flag not on exit/spawn " .. i)
	end
	for _, p in ipairs(b.basins) do
		ok(not at2(p).wall and S.where(p, L) == "base", "basin in the room " .. i)
		ok(p.x ~= b.gate.x or p.y ~= b.gate.y, "basin not on the gate " .. i)
	end
	-- a base room is closed: every tile of its rect border is a wall
	local r = b.rect
	for x = r.x1, r.x2 do
		ok(seen[x .. "," .. r.y1].wall and seen[x .. "," .. r.y2].wall, "base wall row " .. i)
	end
	for y = r.y1, r.y2 do
		ok(seen[r.x1 .. "," .. y].wall and seen[r.x2 .. "," .. y].wall, "base wall column " .. i)
	end
end
for _, p in ipairs(L.pillars) do
	eq(S.where(p, L), "arena", "pillar in the arena")
	ok(not S.onPoint(p, L, cfg.capture.radius), "pillar not on the point")
	for _, b in ipairs(L.bases) do
		ok(p.x ~= b.out.x or p.y ~= b.out.y, "pillar not in front of a gate")
	end
end
ok(#L.pillars >= 4, "some cover")
eq(S.where({x = L.center.x, y = L.center.y, z = L.z + 1}, L), nil, "other floor")
eq(S.where({x = L.box.x1, y = L.box.y1, z = L.z}, L), nil, "box corner is outside every room")
ok(S.onPoint({x = L.center.x + cfg.capture.radius, y = L.center.y - cfg.capture.radius, z = L.z}, L, cfg.capture.radius), "point corner")
ok(not S.onPoint({x = L.center.x + cfg.capture.radius + 1, y = L.center.y, z = L.z}, L, cfg.capture.radius), "off the point")

-- ---------------------------------------------------------------- capture point
local h, c = S.control({}, false)
eq(h, nil, "empty point")
eq(c, false, "not contested")
h, c = S.control({[7] = 2}, false)
eq(h, 7, "alone holds")
h = S.control({[7] = 3, [8] = 1}, false)
eq(h, 7, "majority holds")
h, c = S.control({[7] = 2, [8] = 2}, false)
eq(h, nil, "tie: nobody")
eq(c, true, "tie: contested")
h, c = S.control({[7] = 2, [8] = 2, [9] = 3}, false)
eq(h, 9, "three-way, the biggest holds")
h, c = S.control({[7] = 3, [8] = 1}, true)
eq(h, nil, "exclusive: any enemy contests")
eq(c, true, "exclusive contested")
h = S.control({[7] = 0, [8] = 1}, true)
eq(h, 8, "zero counts are absent")

-- ---------------------------------------------------------------- scoring order and winner
local list = S.standings({
	{id = 1, name = "A", score = 300, kills = 2, order = 1},
	{id = 2, name = "B", score = 420, kills = 1, order = 2},
	{id = 3, name = "C", score = 300, kills = 5, order = 3},
	{id = 4, name = "D", score = 0, kills = 0, order = 4}})
eq(list[1].name, "B", "highest score first")
eq(list[2].name, "C", "same score: more kills")
eq(list[3].name, "A", "then A")
eq(list[4].place, 4, "places")
eq(S.winner(list).name, "B", "winner")
list = S.standings({{id = 1, name = "A", score = 100, kills = 3, order = 2}, {id = 2, name = "B", score = 100, kills = 3, order = 1}})
eq(list[1].place, 1, "full tie shares the place")
eq(list[2].place, 1, "full tie shares the place 2")
eq(list[1].name, "B", "earlier sign-up listed first")
eq(S.winner(list), nil, "full tie: no winner")
eq(S.winner(S.standings({{id = 1, name = "A", score = 0, kills = 0, order = 1}, {id = 2, name = "B", score = 0, kills = 0, order = 2}})), nil, "nobody scored")
-- a match: 25 min, one guild holds the point 15 min and kills 4, the other kills 10
local holdA = 15 * 60 * cfg.points.holdPerSecond + 4 * cfg.points.kill
local killsB = 10 * cfg.points.kill
ok(holdA > killsB, "holding the point outweighs a few more kills")

-- ---------------------------------------------------------------- rewards
local kind, r = S.rewardFor(true, cfg.minPresenceSeconds, cfg)
eq(kind, "winner", "winner reward")
eq(r.bankGold, cfg.reward.winner.bankGold, "winner gold")
kind, r = S.rewardFor(false, cfg.minPresenceSeconds + 100, cfg)
eq(kind, "others", "participant reward")
ok(r.bankGold < cfg.reward.winner.bankGold, "smaller for the others")
kind = S.rewardFor(true, cfg.minPresenceSeconds - 1, cfg)
eq(kind, nil, "too short in the siege: nothing")
ok(cfg.minPresenceSeconds < cfg.matchMinutes * 60, "presence reachable in a match")

-- ---------------------------------------------------------------- champion title and buff
local now = 1000000
local champs = {[7] = {name = "Iron Wolves", untilAt = now + 10}}
eq(S.championOf(champs, 7, now).name, "Iron Wolves", "champion")
eq(S.championOf(champs, 7, now + 10), nil, "title expired")
eq(S.championOf(champs, 8, now), nil, "other guild")
eq(S.championOf(champs, nil, now), nil, "no guild")
ok(cfg.buff.xp > 0 and cfg.buff.xp <= 0.1, "small buff")

-- ---------------------------------------------------------------- calendar entry
local ev = S.calendarEvent(cfg)
eq(ev.id, "guildsiege", "calendar id")
eq(ev.weekdays[1], cfg.weekday, "calendar weekday")
ok(ev.description:find("Guild Siege", 1, true), "calendar tells how to sign up")

print(string.format("siege tests OK (%d checks)", checks))
