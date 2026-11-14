-- Run from the server/ folder: luajit tests/mainquest_boss_attacks_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Vael Ashmourn's own attacks (O554): the tile sets of the six shapes, the windup, the phase mapping, the fairness (a safe tile in
-- reach), and on a mocked engine that no attack goes off without a floor mark before it and that only a character on a marked tile
-- takes the hit (the resistance of the phase's element, a dodged attack does nothing).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z][A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then fails = fails + 1; print("FAIL " .. what) end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/boss_mechanics_core.lua")
dofile("data/scripts/chaos/mainquest_boss_attacks_core.lua")
local A, G = ChaosVaelAttacks, ChaosBossMechCore
local cfg = A.cfg()
ok(cfg ~= nil and cfg.enabled == true, "the config loads")

-- ------------------------------------------------------------------ the table
ok(#cfg.attacks >= 4 and #cfg.attacks <= 6, "four to six attacks: " .. #cfg.attacks)
local seenKey, usedInPhase = {}, {}
for _, a in ipairs(cfg.attacks) do
	ok(not seenKey[a.key], "unique key " .. a.key)
	seenKey[a.key] = true
	ok(type(a.name) == "table" and a.name.en and a.name.pt, a.key .. ": a name in English and pt-BR")
	ok(type(a.say) == "table" and a.say.en and a.say.pt and type(a.tip) == "table" and a.tip.en and a.tip.pt, a.key .. ": say and tip in both languages")
	ok(a.windMs >= 1800 and A.windMs(cfg, a) >= cfg.minWindMs, a.key .. ": a windup of at least 1.8 s to react")
	ok(#a.parts >= 1 and #a.parts <= 2, a.key .. ": one or two shapes")
	for _, p in ipairs(a.parts) do
		ok(p.share > 0 and p.share <= 0.24, a.key .. ": a part share within the tier's zone / pyre share")
	end
	for _, ph in ipairs(a.phases) do
		ok(ph >= 1 and ph <= 4, a.key .. ": a real phase")
		usedInPhase[ph] = true
	end
end
for ph = 1, 4 do
	ok(usedInPhase[ph] and #A.phaseList(cfg, ph) >= 1, "phase " .. ph .. " has an attack")
end
-- the phases are the boss's four (mainquest_config.lua boss.phases)
local MQ = dofile("data/scripts/chaos/mainquest_config.lua")
eq(#MQ.boss.phases, 4, "four phases")
for color, _ in pairs(cfg.color) do ok(true, color) end
for _, ph in ipairs(MQ.boss.phases) do
	ok(cfg.color[ph.element] ~= nil and cfg.hitEffect[ph.element] ~= nil, ph.element .. ": a floor colour and a hit effect")
end
local tcfg = dofile("data/scripts/chaos/telegraph_config.lua")
for el, color in pairs(cfg.color) do ok(tcfg.colors[color], el .. ": the colour " .. color .. " is a floor mark colour") end

-- the last phase mixes two shapes; the first phase has the cone
local mixed = false
for _, a in ipairs(A.phaseList(cfg, 4)) do
	if #a.parts == 2 and a.parts[1].kind ~= a.parts[2].kind then mixed = true end
end
ok(mixed, "the last phase has an attack of two different shapes")
ok(A.byKey(cfg, "cinder_breath") ~= nil and A.byKey(cfg, "cinder_breath").parts[1].kind == "cone", "the cone is the first phase's")
local kinds = {}
for _, a in ipairs(cfg.attacks) do for _, p in ipairs(a.parts) do kinds[p.kind] = true end end
for _, k in ipairs({"cone", "ring", "line", "cross", "puddles"}) do ok(kinds[k], "the shape " .. k .. " is used") end

-- ------------------------------------------------------------------ timing
local rr = {}
for _, a in ipairs(cfg.attacks) do
	for ph = 1, 4 do
		local d, e = A.delayAfter(cfg, ph, false, a), A.delayAfter(cfg, ph, true, a)
		ok(d >= A.windMs(cfg, a) + cfg.gapMs, a.key .. " phase " .. ph .. ": the next one starts a quiet gap after the hit")
		ok(e >= A.windMs(cfg, a) + cfg.gapMs and e <= d, a.key .. " phase " .. ph .. ": enraged is no slower and keeps the gap")
	end
end
ok(A.delayAfter(cfg, 1, false, cfg.attacks[1]) >= A.delayAfter(cfg, 4, false, cfg.attacks[1]), "the later phases come faster")
-- pick: never the same twice while the phase has another, always one of the phase's
for ph = 1, 4 do
	local list = A.phaseList(cfg, ph)
	local last
	for i = 1, 40 do
		local a = A.pick(cfg, ph, last, function(lo, hi) return lo + (i * 7) % (hi - lo + 1) end)
		local inList = false
		for _, b in ipairs(list) do if b == a then inList = true end end
		ok(inList, "phase " .. ph .. ": the pick is of the phase")
		if #list > 1 then ok(a.key ~= last, "phase " .. ph .. ": not the same twice") end
		last = a.key
	end
end

-- ------------------------------------------------------------------ the tile sets
local C0 = {x = 100, y = 100, z = 7}
local function room(c, r)
	local list = {}
	for y = c.y - r, c.y + r do for x = c.x - r, c.x + r do list[#list + 1] = {x = x, y = y, z = c.z} end end
	return G.grid(list)
end
local grid = room(C0, 10) -- 21 x 21 like the Trials' room
local function setOf(tiles)
	local s, cnt = {}, 0
	for _, t in ipairs(tiles) do s[t.x .. "," .. t.y] = true; cnt = cnt + 1 end
	return s, cnt
end
local function shape(spec, target, boss)
	return G.shape(spec, {grid = grid, boss = boss or C0, size = 1, target = target, players = {target}, rand = function() return 1 end, z = 7})
end
-- cone to the south: 33 tiles, widening
do
	local tiles = shape(A.byKey(cfg, "cinder_breath").parts[1], {x = 100, y = 105, z = 7})
	local s, cnt = setOf(tiles)
	eq(cnt, 33, "the cone: 3+3+3+5+5+7+7 tiles")
	ok(s["100,101"] and s["99,101"] and s["101,101"], "the cone's first row is 3 wide")
	ok(s["103,107"] and s["97,107"] and not s["104,107"], "the cone's last row is 7 wide")
	ok(not s["100,100"] and not s["100,108"] and not s["100,99"], "nothing on Vael, past the length or behind him")
	ok(not s["102,101"], "the first row is not wider than 3")
	-- turned to the east, the same area turned
	local e, ecnt = setOf(shape(A.byKey(cfg, "cinder_breath").parts[1], {x = 105, y = 100, z = 7}))
	eq(ecnt, 33, "the cone to the east has the same size")
	ok(e["107,103"] and e["107,97"] and not e["107,104"] and not e["99,100"], "the cone follows the target")
end
-- ring: 2 to 6 tiles from Vael, the middle safe
do
	local s, cnt = setOf(shape(A.byKey(cfg, "ashen_ring").parts[1], {x = 100, y = 103, z = 7}))
	local want = 0
	for y = 90, 110 do for x = 90, 110 do
		local d2 = (x - 100) ^ 2 + (y - 100) ^ 2
		local inside = d2 >= 4 and d2 <= 36
		if inside then want = want + 1 end
		ok(inside == (s[x .. "," .. y] == true), "the ring at " .. x .. "," .. y)
	end end
	eq(cnt, want, "the ring tile count")
	ok(not s["101,101"] and not s["100,101"] and not s["99,99"], "the middle (next to Vael) is safe")
	ok(not s["107,100"] and not s["100,107"], "past the outer edge is safe")
end
-- line: the beam to the east, 3 wide, to the wall
do
	local s, cnt = setOf(shape(A.byKey(cfg, "oath_lance").parts[1], {x = 104, y = 100, z = 7}))
	eq(cnt, 30, "the lance: 10 tiles to the wall, 3 wide")
	ok(s["101,99"] and s["110,101"] and not s["100,100"] and not s["111,100"] and not s["105,102"] and not s["99,100"], "the lance's edges")
end
-- cross: the row and the column, 3 wide
do
	local s, cnt = setOf(shape(A.byKey(cfg, "warden_cross").parts[1], {x = 100, y = 104, z = 7}))
	eq(cnt, 117, "the cross: two bands of 63 less the 9 shared")
	ok(s["90,100"] and s["110,101"] and s["100,90"] and s["99,110"] and s["101,101"], "the cross's arms")
	ok(not s["102,102"] and not s["98,98"] and not s["103,103"], "the corners between the arms are safe")
end
-- puddles: circles, one under the character
do
	local spec = A.byKey(cfg, "ember_rain").parts[1]
	local target = {x = 104, y = 103, z = 7}
	local tiles = shape(spec, target)
	local s, cnt = setOf(tiles)
	ok(s["104,103"] and s["105,104"] and s["106,103"] and s["103,102"], "a circle (radius 2, 13 tiles) lands on the character")
	ok(cnt >= 13 and cnt <= 13 * spec.count, "between one and count circles of 13 tiles")
	local r = G.shape(spec, {grid = grid, boss = C0, size = 1, target = target, players = {target}, rand = function(a, b) return math.floor((a + b) / 2) end, z = 7})
	local _, c2 = setOf(r)
	ok(c2 > 13 and c2 <= 13 * spec.count, "the rain scatters")
end

-- ------------------------------------------------------------------ fairness: a safe tile in reach for every attack
do
	local bosses = {C0, {x = 95, y = 96, z = 7}, {x = 106, y = 104, z = 7}}
	local straight, diag = G.stepCosts(cfg.fair)
	local trapped, plans = 0, 0
	for _, a in ipairs(cfg.attacks) do
		local budget = G.budget(A.windMs(cfg, a), {reactionMs = cfg.reactionMs})
		for _, b in ipairs(bosses) do
			for y = 90, 110, 4 do
				for x = 90, 110, 4 do
					if not (x == b.x and y == b.y) then
						local target = {x = x, y = y, z = 7}
						local seed = x * 31 + y * 17
						local plan = A.plan(cfg, a, {grid = grid, boss = b, target = target, players = {target},
							rand = function(lo, hi) seed = (seed * 1103515245 + 12345) % 2147483648; return lo + seed % (hi - lo + 1) end})
						plans = plans + 1
						local union = G.tileSet(plan.tiles)
						local safe = G.safeSpot(grid, union, target, budget, straight, diag)
						if not safe then trapped = trapped + 1 end
						ok(#plan.tiles <= 0.5 * #grid.list, a.key .. ": at most half of the room is marked (" .. #plan.tiles .. ")")
						ok(plan.fair == (safe ~= nil), a.key .. ": fair means a safe tile in reach")
						ok(safe ~= nil, a.key .. ": a safe tile in reach of " .. x .. "," .. y .. " (boss " .. b.x .. "," .. b.y .. ")")
					end
				end
			end
		end
	end
	ok(plans > 500 and trapped == 0, "no attack traps the character: " .. plans .. " plans, " .. trapped .. " trapped")
end
-- a plan that cannot be made fair says so (nothing to cast)
do
	local tight = room({x = 100, y = 100, z = 7}, 1) -- a 3 x 3 box: the cross covers all of it
	local target = {x = 101, y = 101, z = 7}
	local plan = A.plan(cfg, A.byKey(cfg, "warden_cross"), {grid = tight, boss = C0, target = target, players = {target}, rand = function() return 1 end})
	ok(plan.fair == false or #plan.tiles < 9, "a box the shape fills is cut or refused")
end

-- ------------------------------------------------------------------ damage only on tiles hit
do
	local target = {x = 100, y = 104, z = 7}
	local plan = A.plan(cfg, A.byKey(cfg, "warden_cross"), {grid = grid, boss = C0, target = target, players = {{x = 95, y = 95, z = 7}}, rand = function() return 1 end})
	local share = A.byKey(cfg, "warden_cross").parts[1].share
	eq(A.shareAt(cfg, plan, {x = 100, y = 95, z = 7}, false), share, "on the cross: its share")
	eq(A.shareAt(cfg, plan, {x = 95, y = 95, z = 7}, false), 0, "between the arms: nothing")
	eq(A.shareAt(cfg, plan, nil, false), 0, "no position: nothing")
	ok(math.abs(A.shareAt(cfg, plan, {x = 100, y = 95, z = 7}, true) - share * cfg.enrage.damageMult) < 1e-9, "enraged: the damage factor")
	-- two shapes: the shares of the parts the character stands in
	local fo = A.byKey(cfg, "final_oath")
	local both = {parts = {{set = {["1,1"] = true, ["2,2"] = true}, share = 0.11}, {set = {["1,1"] = true}, share = 0.10}}}
	ok(math.abs(A.shareAt(cfg, both, {x = 1, y = 1}, false) - 0.21) < 1e-9, "in both shapes: both shares")
	ok(math.abs(A.shareAt(cfg, both, {x = 2, y = 2}, false) - 0.11) < 1e-9, "in one shape: its share")
	eq(A.shareAt(cfg, both, {x = 3, y = 3}, false), 0, "in none: nothing")
	ok(fo ~= nil, "final_oath")
	-- the resistance rule is mainquest_core.lua hitAmount
	dofile("data/scripts/chaos/chaos_constants.lua")
	dofile("data/scripts/chaos/mainquest_core.lua")
	local K = ChaosMainQuestCore
	for _, r in ipairs({-150, -40, 0, 30, 75, 90}) do
		local want = K.hitAmount(10000, 0.2, r, 75)
		local got = math.max(1, math.floor(10000 * A.effectiveShare(0.2, 1, r, 75)))
		ok(math.abs(want - got) <= 1, "resistance " .. r .. ": the same hit as hitAmount (" .. want .. " / " .. got .. ")")
	end
	ok(A.effectiveShare(0.2, 0.5, 0, 75) == 0.1, "the tier's hit scale")
end

-- ------------------------------------------------------------------ the engine glue on a mocked engine
local registered, globals = {}, {}
local function eventMock(kind)
	return function(name)
		local e = setmetatable({name = name, kind = kind}, {__index = function() return function() end end})
		e.register = function() registered[#registered + 1] = e; globals[name] = e end
		e.interval = function(self, ms) self.ms = ms end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = eventMock("creature"), eventMock("global"), eventMock("talk")
EventCallback = setmetatable({}, {__index = function() return function() end end})
function EventCallback.register() end
ChaosTierConfig = {skip = {}}
Game = {}
dofile("data/lib/chaos_spell_events.lua")
dofile("data/scripts/chaos/trials_core.lua")
assert(pcall(dofile, "data/scripts/chaos/trials.lua"))
assert(pcall(dofile, "data/scripts/chaos/trials_effects.lua"))
local T, M = ChaosTrials, ChaosTrialsCore
local K = ChaosMainQuestCore
Chaos.lang = function() return "en" end

local unpack = table.unpack or unpack
local clock = 1000000
os.mtime = function() return clock end
local queue = {}
function addEvent(fn, ms, ...)
	queue[#queue + 1] = {at = clock + ms, fn = fn, args = {...}}
end
local function runUntil(t)
	while true do
		local best
		for i, e in ipairs(queue) do
			if e.at <= t and (not best or e.at < queue[best].at) then best = i end
		end
		if not best then break end
		local e = table.remove(queue, best)
		clock = e.at
		e.fn(unpack(e.args))
	end
	clock = t
end

local effects = {}
Position = function(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return {x = x, y = y, z = z, sendMagicEffect = function(self, fx, who) effects[#effects + 1] = {x = x, y = y, fx = fx, who = who, at = clock} end}
end
local log = {} -- every open / hurt in order
ChaosTelegraph = {
	open = function(id, tiles, opts) log[#log + 1] = {what = "open", id = id, n = #tiles, ms = opts.ms, color = opts.color, at = clock, tiles = tiles}; return {id = id} end,
	draw = function(h, fn) fn(nil) end,
	closePrefix = function(prefix) log[#log + 1] = {what = "close", prefix = prefix} end
}
T.hurt = function(tr, player, share, effect) log[#log + 1] = {what = "hurt", share = share, at = clock, effect = effect} end
local okB, eB = pcall(dofile, "data/scripts/chaos/mainquest_boss.lua")
ok(okB, "mainquest_boss.lua loads: " .. tostring(eB))
local B = ChaosMainQuestBoss
ok(globals.ChaosMainQuestBossAttacks ~= nil and globals.ChaosMainQuestBossAttacks.ms == cfg.tickMs, "the attack loop is registered")
eq(T.questOwnsFloor({spell = "mq"}), true, "Vael owns the floor of the trial")
eq(T.questOwnsFloor({spell = "s1"}), false, "another trial keeps its family's mechanics")
eq(T.questOwnsFloor({}), false, "a tier trial too")

local L = M.layout(1)
local players, hp = {}, {v = 100}
local pl = {id = 77, pos = {x = L.center.x, y = L.center.y + 3, z = L.z}}
function pl:getId() return self.id end
function pl:getPosition() return self.pos end
function pl:sendTextMessage(_, t) self.msgs = self.msgs or {}; self.msgs[#self.msgs + 1] = t end
Player = function(id) return id == 77 and pl or nil end
local said = {}
local boss = {pos = {x = L.center.x, y = L.center.y - 2, z = L.z}}
function boss:getHealth() return hp.v end
function boss:getMaxHealth() return 100 end
function boss:getPosition() return self.pos end
function boss:say(t) said[#said + 1] = t end
Monster = function(id) return id == 9000 and boss or nil end
local resist = {fire = 0, ice = 0, energy = 0, earth = 0}
ChaosPlayerDefence = {resistOfElement = function(_, el) return resist[el] end}
local function newRun()
	local tr = {pid = 77, over = false, bossId = 9000, spell = "mq", phase = "fight", stage = {kind = "boss"}, L = L,
		scale = {hit = 0.09}, tierDef = {hit = 0.09}}
	T.runs[77] = tr
	return tr
end
local function clear() log = {}; effects = {}; queue = {}; said = {}; pl.msgs = nil end
local function count(what) local c = 0 for _, e in ipairs(log) do if e.what == what then c = c + 1 end end return c end
local function seq(rand) return function(lo, hi) return lo + (rand() % (hi - lo + 1)) end end

-- the first attack waits for the delay; then the floor marks open before the hit, the hit comes after the windup and the lag
do
	clear()
	local tr = newRun()
	local r = 0
	B.attackTick(seq(function() r = r + 1; return r end))
	eq(#log, 0, "the first tick only sets the first delay")
	ok(tr.mqNext and tr.mqNext >= clock + cfg.firstDelayMs, "the first attack is firstDelayMs away")
	clock = clock + cfg.firstDelayMs - 1
	B.attackTick(seq(function() r = r + 1; return r end))
	eq(#log, 0, "nothing before the delay")
	clock = clock + 1
	B.attackTick(seq(function() r = r + 1; return r end))
	ok(count("open") >= 1, "the floor mark opens when the attack starts")
	eq(count("hurt"), 0, "no damage at the start of the windup")
	local pending = tr.mqPending
	ok(pending ~= nil, "an attack is pending")
	local wind = pending.plan.windMs
	ok(wind >= 1800, "the windup is at least 1.8 s: " .. wind)
	for _, e in ipairs(log) do if e.what == "open" then eq(e.ms, wind, "the mark lasts the windup"); ok(e.id:find("^mq:77:"), "the mark id is of the run") end end
	eq(#pending.marks, #pending.plan.parts, "a floor mark per shape")
	local started = clock
	-- a second tick while pending starts nothing
	local opens = count("open")
	B.attackTick(seq(function() return 1 end))
	eq(count("open"), opens, "one attack at a time")
	-- the character stands still where it was aimed: it is on the attack's tiles or not; move it onto a marked tile to test the hit
	local hitTile
	for _, t in ipairs(pending.plan.tiles) do hitTile = t; break end
	pl.pos = {x = hitTile.x, y = hitTile.y, z = hitTile.z}
	runUntil(started + wind + cfg.lagMs - 1)
	eq(count("hurt"), 0, "no hit before the windup and the lag are over")
	runUntil(started + wind + cfg.lagMs)
	eq(count("hurt"), 1, "one hit on a marked tile")
	for _, e in ipairs(log) do
		if e.what == "hurt" then
			local want = A.shareAt(cfg, pending.plan, pl.pos, false)
			ok(math.abs(e.share - want) < 1e-9, "the hit is the share of the parts it stands in: " .. e.share .. " / " .. want)
			ok(e.at >= started + wind, "the hit is after every mark opened")
		end
	end
	ok(tr.mqPending == nil, "the attack is over")
	ok(#said >= 1 and said[1] == pending.attack.say.en, "Vael calls the attack")
	ok(pl.msgs and pl.msgs[#pl.msgs]:find(pending.attack.tip.en, 1, true) ~= nil, "the first time, the tip too")
	local nextAt = tr.mqNext
	ok(nextAt >= started + wind + cfg.gapMs, "the next attack is a quiet gap after the hit")
end

-- dodged: off the tiles at the hit, nothing happens; the resistance counts when it hits
do
	clear()
	local tr = newRun()
	tr.mqNext = clock
	local r = 0
	B.attackTick(seq(function() r = r + 3; return r end))
	local pending = tr.mqPending
	ok(pending ~= nil, "an attack started")
	-- a tile of the room that is not on the attack
	local free
	for y = L.y1, L.y2 do for x = L.x1, L.x2 do
		if not free and not pending.plan.set[x .. "," .. y] then free = {x = x, y = y, z = L.z} end
	end end
	ok(free ~= nil, "a safe tile exists")
	pl.pos = free
	runUntil(clock + pending.plan.windMs + cfg.lagMs)
	eq(count("hurt"), 0, "a dodged attack does nothing")
	-- the same plan, standing on it, with fire resistance 50 in the fire phase
	clear()
	tr.mqPending = nil; tr.mqNext = clock
	resist.fire = 50; hp.v = 100
	r = 0
	B.attackTick(seq(function() r = r + 3; return r end))
	pending = tr.mqPending
	local t = pending.plan.tiles[1]
	pl.pos = {x = t.x, y = t.y, z = t.z}
	local share = A.shareAt(cfg, pending.plan, pl.pos, false)
	runUntil(clock + pending.plan.windMs + cfg.lagMs)
	eq(count("hurt"), 1, "a hit")
	for _, e in ipairs(log) do if e.what == "hurt" then ok(math.abs(e.share - share * 0.5) < 1e-9, "fire resistance 50 halves the fire phase's hit") end end
	resist.fire = 0
	-- a character that fell (a life taken), or is shielded after it, takes nothing
	clear()
	tr.mqPending = nil; tr.mqNext = clock; tr.fallen = true
	B.attackTick(seq(function() r = r + 3; return r end))
	pending = tr.mqPending
	t = pending.plan.tiles[1]
	pl.pos = {x = t.x, y = t.y, z = t.z}
	runUntil(clock + pending.plan.windMs + cfg.lagMs)
	eq(count("hurt"), 0, "a fallen character takes nothing")
	tr.fallen = false
	clear()
	tr.mqPending = nil; tr.mqNext = clock; tr.shieldUntil = clock + 5000
	B.attackTick(seq(function() return 1 end))
	eq(#log, 0, "no attack starts while the monsters cannot touch the character")
	ok(tr.mqNext >= tr.shieldUntil + 1000, "the next one waits a second past the shield")
	-- the boss dead before the hit: no damage, the marks are cleared
	clear()
	tr.shieldUntil = 0; tr.mqPending = nil; tr.mqNext = clock
	B.attackTick(seq(function() r = r + 3; return r end))
	pending = tr.mqPending
	t = pending.plan.tiles[1]
	pl.pos = {x = t.x, y = t.y, z = t.z}
	tr.bossId = nil
	runUntil(clock + pending.plan.windMs + cfg.lagMs)
	eq(count("hurt"), 0, "no hit after Vael is gone")
	ok(count("close") >= 1, "the marks are closed")
	tr.bossId = 9000
	-- the run over: nothing
	clear()
	tr.mqPending = nil; tr.mqNext = clock
	B.attackTick(seq(function() r = r + 3; return r end))
	pending = tr.mqPending
	tr.over = true
	runUntil(clock + pending.plan.windMs + cfg.lagMs)
	eq(count("hurt"), 0, "no hit after the run is over")
	tr.over = false
end

-- the phases choose the attacks; every attack that starts has its marks open first; no attack is cast without a telegraph
do
	local tr = newRun()
	local fractions = {[1] = 0.9, [2] = 0.6, [3] = 0.4, [4] = 0.2}
	for ph = 1, 4 do
		local keys = {}
		for _, a in ipairs(A.phaseList(cfg, ph)) do keys[a.key] = true end
		local cast = {}
		for i = 1, 30 do
			clear()
			hp.v = fractions[ph] * 100
			tr.mqPending = nil; tr.mqNext = clock; tr.mqLast = nil
			pl.pos = {x = L.center.x + (i % 5) - 2, y = L.center.y + 3, z = L.z}
			local r = i * 5
			B.attackTick(seq(function() r = r + 7; return r end))
			local pending = tr.mqPending
			ok(pending ~= nil, "phase " .. ph .. ": an attack starts")
			if pending then
				ok(keys[pending.attack.key], "phase " .. ph .. ": " .. pending.attack.key .. " belongs to the phase")
				cast[pending.attack.key] = true
				local opens = count("open")
				eq(opens, #pending.plan.parts, "phase " .. ph .. " " .. pending.attack.key .. ": a floor mark for every shape, before the hit")
				for _, e in ipairs(log) do if e.what == "open" then ok(e.at == clock and e.ms >= 1800, "marks open now with 1.8 s or more") end end
				eq(count("hurt"), 0, "no hit before the windup")
				ok(pending.phase.element == MQ.boss.phases[ph].element, "phase " .. ph .. ": the element of the phase")
				ok(log[1].color == cfg.color[pending.phase.element], "phase " .. ph .. ": the mark's colour is the element's")
				if ph == 4 and #pending.plan.parts == 2 then ok(pending.plan.parts[1].kind ~= pending.plan.parts[2].kind, "two different shapes") end
			end
			queue = {}
		end
		local nk = 0
		for _ in pairs(keys) do nk = nk + 1 end
		local nc = 0
		for _ in pairs(cast) do nc = nc + 1 end
		eq(nc, nk, "phase " .. ph .. ": every attack of the phase comes up")
	end
	-- enraged under 30%
	clear()
	hp.v = 20; tr.mqPending = nil; tr.mqNext = clock
	local r = 0
	B.attackTick(seq(function() r = r + 7; return r end))
	ok(tr.mqPending and tr.mqPending.enraged == true, "below 30% the attack is enraged")
	hp.v = 100
end

-- no floor telegraph module: the sprite marks go out before the hit (the old way), still a warning for everybody
do
	local saved = ChaosTelegraph
	ChaosTelegraph = nil
	clear()
	local tr = newRun()
	hp.v = 90; tr.mqPending = nil; tr.mqNext = clock
	local r = 0
	B.attackTick(seq(function() r = r + 7; return r end))
	local pending = tr.mqPending
	ok(pending ~= nil, "an attack starts without the module")
	local t0 = clock
	runUntil(t0 + pending.plan.windMs + cfg.lagMs - 1)
	local warned = 0
	for _, e in ipairs(effects) do if e.at < t0 + pending.plan.windMs then warned = warned + 1 end end
	ok(warned > 0, "sprite marks before the hit: " .. warned)
	ChaosTelegraph = saved
end

-- an attack that cannot be made fair is not cast
do
	clear()
	local tr = newRun()
	hp.v = 90; tr.mqPending = nil; tr.mqNext = clock
	local realPlan = A.plan
	A.plan = function(c, a, ctx) local p = realPlan(c, a, ctx); p.fair = false; return p end
	B.attackTick(seq(function() return 1 end))
	A.plan = realPlan
	eq(#log, 0, "an unfair plan opens no mark and hits nothing")
	ok(tr.mqPending == nil and tr.mqNext > clock, "tried again later")
	runUntil(clock + 10000)
	eq(count("hurt"), 0, "and nothing hits")
end

-- the trial's own tick leaves the family's floor mechanics off for Vael (trials.lua ownsFloor)
do
	local src = io.open("data/scripts/chaos/trials.lua"):read("*a")
	ok(src:find('M.hasMech(tr.famKey, "stillness") and not ownsFloor(tr)', 1, true) ~= nil, "stillness is off for Vael")
	ok(src:find('M.hasMech(tr.famKey, "zones") and not ownsFloor(tr)', 1, true) ~= nil, "zones are off for Vael")
	ok(src:find('M.hasMech(tr.famKey, "pyre") and not ownsFloor(tr)', 1, true) ~= nil, "the pyre is off for Vael")
end

T.runs[77] = nil
if fails > 0 then print("mainquest_boss_attacks_test: " .. fails .. " failure(s)"); os.exit(1) end
print(string.format("mainquest_boss_attacks_test: %d checks ok", checks))
