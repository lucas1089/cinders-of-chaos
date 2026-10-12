-- Run from the server/ folder: luajit tests/snares_test.lua (and lua5.3; CI runs both)
-- The snares (docs/BUILDS.md "Snares", server/README.md "Snares"):
--   * the pure rules (snares_core.lua): the element choice, caps, arming, life and fuse, the damage, the list with its
--     per-owner and global caps, the owner checks, the scheduler's round robin and burst budget, Detonate Mines;
--   * the spells' glue (data/spells/chaos/_snares.lua) against a mocked engine: a trap thrown at the target, armed,
--     set off by a monster, its burst within the radius and in sight, the snare marker on the owner during its hits,
--     the element (spoken, remembered, from a brand rune), burn / slow / poison / drain, mines with Detonate Mines and
--     the fuse, the caps, the protection zone, the cleanup at logout, death, a floor change and the leash, the
--     scheduler's work per tick with 400 snares.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local count, failures = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what) check(a == b, (what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

dofile("data/scripts/chaos/snares_config.lua")
dofile("data/scripts/chaos/snares_core.lua")
local C, S = ChaosSnaresConfig, ChaosSnaresCore

-- ------------------------------------------------------------------------------------------------ core
-- elements
eq(S.parseElement("fire"), "fire", "fire")
eq(S.parseElement(' "Frost '), "ice", "an alias, quotes and spaces")
eq(S.parseElement("poison"), "earth", "poison is earth")
eq(S.parseElement("banana"), nil, "not an element")
eq(S.parseElement(nil), nil, "no text")
local e, remember = S.chooseElement("holy", 2, 1)
check(e == "holy" and remember == S.elementIndex("holy"), "the spoken word wins and is remembered")
e, remember = S.chooseElement("", S.elementIndex("ice"), 1)
check(e == "ice" and remember == nil, "the remembered element next")
e = S.chooseElement("", -1, 4)
eq(e, "death", "then the brand rune (Gravebrand)")
eq(S.chooseElement("", -1, nil), "physical", "else physical")
eq(S.chooseElement("", -1, 9), "physical", "a rune that is not a brand")
eq(S.supportOfRune(32101), 1, "Emberbrand level 1")
eq(S.supportOfRune(32125), 5, "Stormbrand level 5")
eq(S.supportOfRune(32126), 6, "Quickening")
eq(S.supportOfRune(-1), nil, "an empty socket")

-- caps, arming, life
eq(S.cap("trap", {}), 3, "3 traps")
eq(S.cap("mine", {}), 5, "5 mines")
eq(S.cap("trap", {keystone = true, snarewalker = true}), 3 + 2 + 1, "traps: keystone and greaves")
eq(S.cap("mine", {keystone = true, fusewright = true}), 5 + 3 + 2, "mines: keystone and charm")
eq(S.armMs("trap", {}), 600, "trap arms in 0.6 s")
eq(S.armMs("trap", {keystone = true}), 300, "keystone: half")
eq(S.armMs("trap", {keystone = true, snarewalker = true}), 0, "and the greaves: at once")
eq(S.armMs("mine", {keystone = true}), 400, "mine with the keystone")
eq(S.lifeMs("trap", {}), 20000, "a trap lasts 20 s")
eq(S.lifeMs("mine", {fusewright = true}), 12000, "the charm: a longer fuse")

-- damage
local D = C.damage
local baseMin = 300 * D.min.perLevel + 5000 * D.min.perPower + D.min.base
local baseMax = 300 * D.max.perLevel + 5000 * D.max.perPower + D.max.base
eq(baseMin, 300 * 0.4 + 5000 * 0.09 + 20, "the formula's numbers")
local min, max = S.damage(300, 5000, "trap", "fire", {})
eq(min, math.floor(baseMin), "trap min")
eq(max, math.floor(baseMax), "trap max")
local mmin = S.damage(300, 5000, "mine", "fire", {})
eq(mmin, math.floor(baseMin * 1.15), "a mine: x1.15")
local kmin = S.damage(300, 5000, "trap", "fire", {keystone = true, snarewalker = true})
eq(kmin, math.floor(baseMin * 1.1 * 1.25), "keystone x1.25, greaves x1.1")
local pmin = S.damage(300, 5000, "trap", "physical", {})
eq(pmin, math.floor(baseMin * 1.15), "physical x1.15")
local emin = S.damage(300, 5000, "trap", "energy", {})
eq(emin, math.floor(baseMin * 0.85), "energy x0.85")
eq(S.burstRadius("trap", "energy"), 3, "energy reaches 1 sqm farther")
eq(S.burstRadius("mine", "fire"), 2, "fire: 2 sqm")
local fx = S.elementEffect("fire", 400)
check(fx.burn and fx.burn.tick == 30 and fx.burn.ticks == 4, "burn: 30% over 4 s")
fx = S.elementEffect("earth", 600)
check(fx.poison and fx.poison.tick == 36 and fx.poison.ticks == 6, "poison: 36% over 6 s")
fx = S.elementEffect("ice", 600)
check(fx.slow and fx.slow.percent == 0.4 and fx.slow.ms == 3000, "slow 40% for 3 s")
eq(S.elementEffect("death", 1000).drain, 40, "drain 4%")
check(S.elementEffect("holy", 1000).holy == 0.02, "holy heals 2%")
check(next(S.elementEffect("physical", 1000)) == nil, "physical: nothing more")

-- the list: per-owner caps, the oldest goes
local st = S.newState()
local function snare(owner, kind, x, armedAt, untilTime)
	return {kind = kind or "trap", owner = owner, pos = {x = x or 100, y = 100, z = 7}, element = "fire", min = 10,
		max = 20, armedAt = armedAt or 0, untilTime = untilTime or 100000}
end
for i = 1, 4 do assert(S.add(st, snare(7, "trap", 100 + i), 3)) end
eq(S.count(st, 7, "trap"), 3, "at most 3")
eq(st.list[1].pos.x, 102, "the first one went")
local ok, gone = S.add(st, snare(7, "mine"), 5)
check(ok and #gone == 0 and S.count(st, 7) == 4, "a mine does not push a trap out")
-- the global cap
local big = S.newState()
for i = 1, C.globalCap do S.add(big, snare(i, "trap"), 3) end
local okBig, why = S.add(big, snare(99999, "trap"), 3)
check(okBig == nil and why == "global", "the global cap")
-- clearing an owner
local st2 = S.newState()
S.add(st2, snare(1), 3); S.add(st2, snare(2), 3); S.add(st2, snare(1, "mine"), 5)
S.queueBurst(st2, st2.list[3], 0)
local cleared = S.clearOwner(st2, 1)
check(#cleared == 2 and #st2.list == 1 and #st2.bursts == 0, "every snare of the owner and its bursts")
-- the owner checks
local s0 = snare(1, "trap", 100)
check(S.ownerKeeps(s0, {alive = true, pos = {x = 110, y = 100, z = 7}}), "near: kept")
check(not S.ownerKeeps(s0, nil), "logged out")
check(not S.ownerKeeps(s0, {alive = false, pos = {x = 100, y = 100, z = 7}}), "dead")
check(not S.ownerKeeps(s0, {alive = true, pos = {x = 100, y = 100, z = 6}}), "another floor")
check(not S.ownerKeeps(s0, {alive = true, pos = {x = 131, y = 100, z = 7}}), "past the leash")
check(not S.ownerKeeps(s0, {alive = true, inPz = true, pos = {x = 100, y = 100, z = 7}}), "in a protection zone")
-- visits
eq(S.visit(snare(1, "trap", 100, 500, 2000), 400), nil, "not armed yet")
eq(S.visit(snare(1, "trap", 100, 500, 2000), 600), "check", "an armed trap is checked")
eq(S.visit(snare(1, "trap", 100, 500, 2000), 2000), "expire", "a trap ends")
eq(S.visit(snare(1, "mine", 100, 500, 2000), 600), nil, "a mine waits")
eq(S.visit(snare(1, "mine", 100, 500, 2000), 2000), "fuse", "its fuse")
-- triggering
check(S.triggered({pos = {x = 100, y = 100, z = 7}}, {{id = 1, pos = {x = 101, y = 101, z = 7}}}), "a monster next to it")
check(not S.triggered({pos = {x = 100, y = 100, z = 7}}, {{id = 1, pos = {x = 102, y = 100, z = 7}}}), "2 sqm: no")
local picked = S.pickTargets({{id = 5, pos = {x = 102, y = 100, z = 7}}, {id = 3, pos = {x = 101, y = 100, z = 7}},
	{id = 4, pos = {x = 103, y = 100, z = 7}}, {id = 2, pos = {x = 101, y = 100, z = 6}}}, {x = 100, y = 100, z = 7}, 2, 8)
check(#picked == 2 and picked[1].id == 3 and picked[2].id == 5, "nearest first, in the radius, on the floor")
-- Detonate Mines: armed ones, staggered
local st3 = S.newState()
S.add(st3, snare(1, "mine", 100, 0, 9000), 5); S.add(st3, snare(1, "mine", 101, 0, 9000), 5)
S.add(st3, snare(1, "mine", 102, 5000, 9000), 5); S.add(st3, snare(2, "mine", 103, 0, 9000), 5)
eq(S.detonate(st3, 1, 1000), 2, "two armed mines of the owner")
eq(S.detonate(st3, 1, 1000), 0, "not twice")
eq(#S.drainBursts(st3, 1000), 1, "the first at once")
eq(#S.drainBursts(st3, 1050), 0, "the next one 0.1 s later")
eq(#S.drainBursts(st3, 1100), 1, "then the second")
eq(#st3.list, 2, "the burst ones are gone from the list")
-- the scheduler's budget: 400 snares, perTick a tick, every snare visited within ceil(400 / perTick) ticks
local st4 = S.newState()
for i = 1, 400 do S.add(st4, snare(i, "trap", i), 3) end
local visited, ticks = {}, 0
repeat
	ticks = ticks + 1
	local batch = S.batch(st4)
	check(#batch <= C.scan.perTick, "at most perTick a tick")
	for _, s in ipairs(batch) do visited[s.id] = true end
	local all = 0
	for _ in pairs(visited) do all = all + 1 end
until all == 400 or ticks > 20
eq(ticks, math.ceil(400 / C.scan.perTick), "a full round in ceil(400 / perTick) ticks")
for i = 1, 40 do S.queueBurst(st4, st4.list[i], 0) end
eq(#S.drainBursts(st4, 0), C.scan.burstsPerTick, "at most burstsPerTick bursts a tick")
eq(#st4.bursts, 40 - C.scan.burstsPerTick, "the rest waits")

-- ------------------------------------------------------------------------------------------------ the spells' glue (mocked)
NOW = 100000
os.mtime = function() return NOW end
local queue = {}
function addEvent(fn, delay, ...) queue[#queue + 1] = {fn = fn, args = {...}, at = NOW + (delay or 0)} end
local function runEvents(untilTime)
	local guard = 0
	while true do
		table.sort(queue, function(a, b) return a.at < b.at end)
		local ev = queue[1]
		if not ev or ev.at > (untilTime or NOW) then break end
		table.remove(queue, 1)
		NOW = math.max(NOW, ev.at)
		ev.fn((table.unpack or unpack)(ev.args))
		guard = guard + 1
		assert(guard < 5000, "event loop")
	end
end
local function advance(ms)
	runEvents(NOW + ms)
	NOW = NOW + 0
end

local creatures, nextId = {}, 1
local dealt, added, effects = {}, {}, {}
local pzTiles = {}
local function P(x, y, z) return {x = x, y = y, z = z or 7} end
local PosMeta = {}
PosMeta.__index = {
	sendMagicEffect = function(p, e) effects[#effects + 1] = {pos = p, e = e} end,
	sendDistanceEffect = function() end,
	isSightClear = function(a, b) return not (a.wall or b.wall) end,
}
Position = function(x, y, z)
	local wall
	if type(x) == "table" then x, y, z, wall = x.x, x.y, x.z, x.wall end
	return setmetatable({x = x, y = y, z = z, wall = wall}, PosMeta)
end
Tile = function(pos)
	return {hasFlag = function(_, flag) return flag == TILESTATE_PROTECTIONZONE and pzTiles[pos.x .. ":" .. pos.y] == true end,
		getGround = function() return true end}
end
local function mk(kind, opt)
	nextId = nextId + 1
	local c = {id = nextId, kind = kind, hp = opt.hp or 1000, maxHp = opt.maxHp or opt.hp or 1000, pos = opt.pos or P(100, 100),
		level = opt.level or 300, storage = {}, slots = opt.slots or {}, conds = {}, dir = opt.dir or EAST}
	local m = {c = c}
	function m:getId() return c.id end
	function m:isPlayer() return c.kind == "player" end
	function m:isMonster() return c.kind == "monster" end
	function m:getPlayer() return c.kind == "player" and self or nil end
	function m:getHealth() return c.hp end
	function m:getMaxHealth() return c.maxHp end
	function m:addHealth(v) c.hp = math.min(c.maxHp, c.hp + v) end
	function m:getPosition() return Position(c.pos) end
	function m:getDirection() return c.dir end
	function m:getTarget() return c.target end
	function m:getMaster() return c.master end
	function m:getLevel() return c.level end
	function m:getStorageValue(k) return c.storage[k] or -1 end
	function m:setStorageValue(k, v) c.storage[k] = v end
	function m:getSlotItem(slot) return c.slots[slot] end
	function m:getEffectiveSkillLevel() return 110 end
	function m:addCondition(cd) c.conds[#c.conds + 1] = cd; added[#added + 1] = {target = c.id, cond = cd} end
	function m:sendTextMessage(_, text) c.lastText = text end
	function m:sendCancelMessage(text) c.cancel = text end
	creatures[c.id] = m
	return m
end
Creature = function(id) return creatures[id] end
Player = function(id)
	local c = creatures[id]
	return c and c:isPlayer() and c or nil
end
Game = {getSpectators = function(center, a, b, rx)
	local out = {}
	for _, c in pairs(creatures) do
		local p = c.c.pos
		if p.z == center.z and math.abs(p.x - center.x) <= rx and math.abs(p.y - center.y) <= rx then out[#out + 1] = c end
	end
	table.sort(out, function(x, y) return x:getId() < y:getId() end)
	return out
end}
local markerSeen = {}
function doTargetCombat(attacker, target, ctype, a, b, effect, origin)
	markerSeen[#markerSeen + 1] = attacker:getStorageValue(C.storage.hit)
	dealt[#dealt + 1] = {attacker = attacker:getId(), target = target:getId(), type = ctype, min = -a, max = -b, origin = origin}
	target.c.hp = target.c.hp - math.floor((-a - b) / 2)
	if target.c.hp <= 0 then creatures[target:getId()] = nil end
	return true
end
function Condition(t)
	local cd = {type = t, params = {}}
	function cd:setParameter(k, v) self.params[k] = v end
	function cd:addDamage(rounds, ms, value) self.rounds, self.ms, self.value = rounds, ms, value end
	return cd
end
local slowed = {}
local DIR = {[EAST] = {1, 0}, [WEST] = {-1, 0}, [NORTH] = {0, -1}, [SOUTH] = {0, 1}}
ChaosSpell = {
	isEnemy = function(caster, t) return t:isMonster() and t:getMaster() == nil end,
	distanceAttack = function() return 45 end, bladePower = function() return 1000 end,
	shurikenPower = function() return 2000 end,
	stepPos = function(pos, dir, steps) local d = DIR[dir] or {0, 0}; return Position(pos.x + d[1] * steps, pos.y + d[2] * steps, pos.z) end,
	slow = function(target, ms, percent) slowed[#slowed + 1] = {id = target:getId(), ms = ms, percent = percent} end,
	cancel = function(player, text) player.c.cancel = text; return false end,
	alliesAround = function(caster, pos, radius) return {caster} end,
}
dofile("data/scripts/chaos/archetypes_core.lua")
local A = ChaosArchetypesCore
dofile("data/spells/chaos/_snares.lua")
local G = ChaosSnares

local function cast(player, kind, param)
	return G.cast(player, kind, {string = param or ""})
end
local function reset()
	creatures, dealt, added, effects, markerSeen, slowed, queue = {}, {}, {}, {}, {}, {}, {}
	G.state = S.newState()
	G.tick() -- stops the old scheduler
	queue = {}
end

-- a Ranger throws a fire trap at its target; a monster walks in, the trap bursts
reset()
local ranger = mk("player", {hp = 3000, pos = P(100, 100), level = 300})
local target = mk("monster", {hp = 90000, pos = P(103, 100)})
ranger.c.target = target
check(cast(ranger, "trap", "fire"), "the trap is thrown")
eq(#G.state.list, 1, "one trap")
local trap = G.state.list[1]
check(trap.pos.x == 103 and trap.element == "fire" and trap.armedAt == NOW + 600, "on the target, fire, arms in 0.6 s")
eq(ranger.c.storage[C.storage.element], S.elementIndex("fire"), "the element is remembered")
local tmin, tmax = S.damage(300, 110 * 45, "trap", "fire", {})
check(trap.min == tmin and trap.max == tmax, "the trap's hit from the bow's power")
local near = mk("monster", {hp = 90000, pos = P(105, 100)})
local far = mk("monster", {hp = 90000, pos = P(106, 100)})
advance(400)
eq(#dealt, 0, "not armed yet")
advance(400)
check(#dealt == 2, "armed: the burst hits the target and the one 2 sqm away (" .. #dealt .. ")")
for _, d in ipairs(dealt) do
	check(d.target ~= far:getId(), "not the one 3 sqm away")
	check(d.type == COMBAT_FIREDAMAGE and d.min == tmin and d.origin == ORIGIN_SPELL, "fire, the trap's hit")
end
for _, v in ipairs(markerSeen) do eq(v, 1, "the snare marker is set during the hit") end
eq(ranger.c.storage[C.storage.hit], -1, "and cleared after")
local burns = 0
for _, a in ipairs(added) do if a.cond.type == CONDITION_FIRE then burns = burns + 1; check(a.cond.rounds == 4, "a 4 s burn") end end
eq(burns, 2, "both burn")
eq(#G.state.list, 0, "the trap is spent")

-- the remembered element; a wall between the trap and a monster; ice slows
reset()
ranger = mk("player", {hp = 3000, pos = P(100, 100)})
ranger.c.storage[C.storage.element] = S.elementIndex("ice")
target = mk("monster", {hp = 90000, pos = P(102, 100)})
local behind = mk("monster", {hp = 90000, pos = P(103, 101)})
behind.c.pos.wall = true
ranger.c.target = target
cast(ranger, "trap")
eq(G.state.list[1].element, "ice", "the remembered element")
advance(1000)
check(#dealt == 1 and dealt[1].target == target:getId(), "the monster behind a wall is not hit")
check(#slowed == 1 and slowed[1].percent == 0.4, "ice slows")

-- a brand rune picks the element; straight ahead without a target; the cap of 3
reset()
ranger = mk("player", {hp = 3000, pos = P(100, 100), dir = SOUTH})
ranger.c.storage[7110000 + C.spells.trap * 4 + 2] = 32118 -- Gravebrand level 3 in the second socket
cast(ranger, "trap")
local t1 = G.state.list[1]
check(t1.element == "death" and t1.pos.y == 104 and t1.pos.x == 100, "Gravebrand: death; 4 sqm ahead")
cast(ranger, "trap", "holy"); cast(ranger, "trap"); cast(ranger, "trap")
eq(S.count(G.state, ranger:getId(), "trap"), 3, "at most 3 traps")
check(G.state.list[1].id ~= t1.id, "the oldest went")
-- the throw stops before a protection zone; standing in one (the engine refuses aggressive spells there anyway): no snare
pzTiles["100:103"] = true
cast(ranger, "trap")
eq(G.state.list[#G.state.list].pos.y, 102, "the throw stops before a protection zone")
pzTiles["100:100"], pzTiles["100:101"] = true, true
check(not cast(ranger, "trap"), "refused in a protection zone")
check(ranger.c.cancel and ranger.c.cancel:find("protection zone"), "with a message")
pzTiles["100:100"], pzTiles["100:101"], pzTiles["100:103"] = nil, nil, nil

-- death drains, holy heals
reset()
local thief = mk("player", {hp = 1000, maxHp = 3000, pos = P(100, 100)})
target = mk("monster", {hp = 90000, pos = P(102, 100)})
thief.c.target = target
cast(thief, "trap", "death")
advance(700)
local drain = S.elementEffect("death", math.floor((G.state.list[1] or {min = 0, max = 0}).min)).drain
check(thief.c.hp > 1000, "death drains health (" .. thief.c.hp .. ")")
eq(dealt[1].min, select(1, S.damage(300, 110 * 45, "trap", "death", {})), "the best power (the bow's here)")

-- mines: thrown, armed, detonated together; the fuse; the keystone and the charm
reset()
local ninja = mk("player", {hp = 3000, pos = P(200, 200)})
ninja.c.storage[ChaosArchetypesConfig.storage] = A.mask({arSnarewright = true})
local charm = {getId = function() return 7890 end, getCustomAttribute = function() return 1 end}
ninja.c.slots[CONST_SLOT_NECKLACE] = charm
target = mk("monster", {hp = 900000, pos = P(202, 200)})
ninja.c.target = target
for _ = 1, 12 do cast(ninja, "mine", "earth") end
eq(S.count(G.state, ninja:getId(), "mine"), 5 + 3 + 2, "mines: 5 + keystone 3 + charm 2")
local mm = G.state.list[1]
local kmin2 = S.damage(300, 110 * 45, "mine", "earth", {keystone = true, fusewright = true})
eq(mm.min, kmin2, "the mine's hit with the keystone and the charm")
eq(mm.untilTime - mm.armedAt, 12000, "the charm's longer fuse")
check(not G.detonate(ninja), "nothing armed yet")
advance(400)
check(G.detonate(ninja), "Detonate Mines")
advance(2000)
eq(#dealt, 10, "ten mines went off, one hit each")
local poisons = 0
for _, a in ipairs(added) do if a.cond.type == CONDITION_POISON then poisons = poisons + 1 end end
eq(poisons, 10, "earth poisons")
eq(#G.state.list, 0, "all spent")
-- the fuse
dealt = {}
cast(ninja, "mine", "fire")
advance(400 + 12000 + 400)
eq(#dealt, 1, "the fuse sets it off")

-- cleanup: logout, death, a floor change, the leash; the scheduler stops when nothing is left
reset()
local p1 = mk("player", {hp = 3000, pos = P(300, 300)})
local p2 = mk("player", {hp = 3000, pos = P(400, 400)})
local p3 = mk("player", {hp = 3000, pos = P(500, 500)})
local p4 = mk("player", {hp = 3000, pos = P(600, 600)})
for _, p in ipairs({p1, p2, p3, p4}) do cast(p, "trap"); cast(p, "mine") end
eq(#G.state.list, 8, "eight snares")
creatures[p1:getId()] = nil -- logged out
p2.c.hp = 0 -- died
p3.c.pos = P(500, 500, 6) -- another floor
p4.c.pos = P(640, 600) -- past the leash
advance(400)
eq(#G.state.list, 0, "all of them gone")
queue = {}
advance(1000)
eq(#queue, 0, "the scheduler stopped")
-- the scripts' side clears at once (a shared Lua state)
local p5 = mk("player", {hp = 3000, pos = P(700, 700)})
cast(p5, "trap"); cast(p5, "mine")
G.clearOwner(p5:getId())
eq(#G.state.list, 0, "clearOwner")

-- the scheduler's work with 400 snares: at most perTick checks (spectator queries) a tick
reset()
local queries = 0
local realSpectators = Game.getSpectators
Game.getSpectators = function(...) queries = queries + 1; return realSpectators(...) end
for i = 1, 100 do
	local p = mk("player", {hp = 3000, pos = P(1000 + i * 10, 1000)})
	for _ = 1, 3 do cast(p, "trap") end
	cast(p, "mine")
end
eq(#G.state.list, 400, "400 snares out")
advance(700) -- all armed
queries = 0
runEvents(NOW + C.scan.tickMs)
check(queries <= C.scan.perTick, "one tick: at most perTick spectator queries (" .. queries .. ")")
-- the global cap
local extra = mk("player", {hp = 3000, pos = P(5000, 5000)})
check(not cast(extra, "trap"), "the 401st snare is refused")
check(extra.c.cancel and extra.c.cancel:find("too many"), "with a message")
Game.getSpectators = realSpectators

-- the spells and the data
local xml = io.open("data/spells/chaos/spells_chaos.xml"):read("*a")
for key, id in pairs(C.spells) do
	local block = xml:match('<instant[^>]-spellid="' .. id .. '".-</instant>')
	check(block ~= nil, key .. " spell " .. id .. " in spells_chaos.xml")
	if block then
		check(block:find('script="chaos/shared/', 1, true) ~= nil, key .. ": a shared script")
		if key ~= "detonate" then
			check(block:find('params="1"', 1, true) and not block:find('selftarget="1"', 1, true), key .. ": a parameter, no selftarget")
		end
		for _, v in ipairs({"Ranger", "Deadeye", "Beastmaster", "Thief", "Ninja", "Samurai"}) do
			check(block:find('"' .. v .. '"', 1, true) ~= nil, key .. " for the " .. v)
		end
		check(not block:find('"Warrior"', 1, true), key .. ": not the Warrior")
	end
end
local SC = dofile("data/lib/chaos_supports_config.lua")
check(SC.kindOverride[C.spells.trap] == "area" and SC.kindOverride[C.spells.mine] == "area", "brand runes fit the snares")
eq(SC.firstId, 32101, "the rune ids the element reads")
eq(SC.storageBase, 7110000, "the socket storages the element reads")
dofile("data/scripts/chaos/chaos_constants.lua")
eq(Chaos.storage.snareElement, C.storage.element, "the element storage in chaos_constants.lua")
eq(Chaos.storage.snareHit, C.storage.hit, "the marker storage in chaos_constants.lua")

print(string.format("snares_test: %d checks, %d failures", count, failures))
if failures > 0 then os.exit(1) end
