-- Run from the server/ folder: luajit tests/globes_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Ground pickups and globes: the pure rules (pickups_core.lua, globes_core.lua + configs): the take rule (owner, party
-- after the owner window, nobody else, expiry), taking once, the chance curve, the flat chance by tier, the cooldown, the
-- heal amount; then the engine files (pickups.lua, globes.lua) against a mocked engine: a kill at low health drops a
-- globe near the corpse, the step restores a share of the maximum (the party too, strangers not), the globe goes out
-- after its lifetime with the fade effect, a leftover item grants nothing, nothing drops for summons, blocked places,
-- trivial monsters or without stamina, and the per-killer limits hold.
local pcfg = dofile("data/scripts/chaos/pickups_config.lua")
local gcfg = dofile("data/scripts/chaos/globes_config.lua")
dofile("data/scripts/chaos/pickups_core.lua")
dofile("data/scripts/chaos/globes_core.lua")
local PK, G = ChaosPickupsCore, ChaosGlobesCore

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function near(a, b, what)
	ok(math.abs(a - b) < 1e-9, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function low(a, b) return a end
local function high(a, b) return b end

-- ------------------------------------------------------------------ the config
do
	local ids, keys = {}, {}
	for _, row in ipairs(pcfg.items) do
		ok(not ids[row.id] and not keys[row.key], "item once: " .. row.key)
		ids[row.id], keys[row.key] = true, true
		ok(row.id >= 32088 and row.id <= 32090, row.key .. " id in the block")
		ok(row.glow and row.take, row.key .. " has glow and take effects")
		if row.key == "ember" then eq(row.glow, "CONST_ME_PURPLEENERGY", "the ember glows violet, like its portal look") end
		local want = {health_globe = {44397, 7618}, mana_globe = {44398, 7620}, ember = {44396, 25045}}
		eq(row.clientId, want[row.key][1], row.key .. " wears its own look (pair 55)")
		eq(row.stockClientId, want[row.key][2], row.key .. " node is copied from the stock client id")
		eq(row.stackable, true, row.key .. " is stackable (the look reads a count)")
	end
	ok(keys.health_globe and keys.mana_globe and keys.ember, "three items")
	ok(pcfg.failsafeSeconds > gcfg.lifetimeMs / 1000, "the failsafe outlasts a globe")
	ok(#pcfg.placeOffsets >= 9 and pcfg.placeOffsets[1][1] == 0 and pcfg.placeOffsets[1][2] == 0, "the corpse tile first")
	for _, kind in ipairs({"health", "mana"}) do
		local c = gcfg.curve[kind]
		eq(c[1][2], 0, kind .. ": no chance at the top of the curve")
		for i = 2, #c do
			ok(c[i][1] < c[i - 1][1] and c[i][2] >= c[i - 1][2], kind .. ": the curve falls in share and rises in chance")
		end
	end
	ok(gcfg.lifetimeMs >= 10000 and gcfg.lifetimeMs <= 30000, "a globe lasts 10-30 s")
	ok(gcfg.healthPct >= 15 and gcfg.healthPct <= 20 and gcfg.manaPct >= 15 and gcfg.manaPct <= 20, "15-20% restored")
end

-- ------------------------------------------------------------------ the take rule
do
	local reg = PK.new()
	local e = PK.add(reg, {kind = "k", itemKey = "health_globe", x = 1, y = 2, z = 7, ownerId = 10, ttlMs = 15000,
		ownerWindowMs = 5000}, 1000)
	eq(e.untilMs, 16000, "dies after the lifetime")
	ok(PK.canTake(e, 10, false, 1000), "the owner at once")
	local okT, why = PK.canTake(e, 11, true, 3000)
	ok(not okT and why == "party", "a party member waits for the owner window")
	ok(PK.canTake(e, 11, true, 6000), "a party member after the window")
	okT, why = PK.canTake(e, 12, false, 6000)
	ok(not okT and why == "owner", "a stranger never")
	okT, why = PK.canTake(e, 12, false, 15999)
	ok(not okT and why == "owner", "a stranger never, even at the end")
	okT, why = PK.canTake(e, 10, false, 16000)
	ok(not okT and why == "expired", "nobody after the lifetime")
	eq(#PK.at(reg, 1, 2, 7), 1, "found on its tile")
	eq(#PK.at(reg, 1, 2, 8), 0, "not on another floor")
	eq(PK.countOf(reg, 10, "k"), 1, "counted for its owner")
	eq(PK.take(reg, e.uid), e, "taken")
	eq(PK.take(reg, e.uid), nil, "taken once: the second take finds nothing")
	PK.restore(reg, e)
	eq(PK.countOf(reg, 10), 1, "restored")
	eq(#PK.expired(reg, 15000), 0, "not expired yet")
	eq(#PK.expired(reg, 16000), 1, "expired at its time")
	eq(PK.countOf(reg, 10), 0, "and out of the record")
	local e0 = PK.add(reg, {kind = "k", itemKey = "x", x = 1, y = 1, z = 7, ownerId = 1, ttlMs = 10000, ownerWindowMs = 0}, 0)
	ok(PK.canTake(e0, 2, true, 0), "window 0: the party takes it at once")
	eq(#PK.pulses(reg, 1000, 1500), 0, "no glow before the pulse time")
	eq(#PK.pulses(reg, 1500, 1500), 1, "a glow at the pulse time")
	eq(#PK.pulses(reg, 1600, 1500), 0, "and not again at once")
end

-- ------------------------------------------------------------------ the chance curve
do
	near(G.chance(gcfg, "health", 0.9, "normal"), 0, "full health: 0")
	near(G.chance(gcfg, "health", 0.60, "normal"), 0, "60%: 0")
	near(G.chance(gcfg, "health", 0.45, "normal"), 17.5, "45%: half way to 35")
	near(G.chance(gcfg, "health", 0.30, "normal"), 35, "30%: 35")
	near(G.chance(gcfg, "health", 0.20, "normal"), 42.5, "20%")
	near(G.chance(gcfg, "health", 0.10, "normal"), 50, "10%: 50")
	near(G.chance(gcfg, "health", 0.01, "normal"), 50, "below the last point it stays")
	ok(G.chance(gcfg, "health", 0.5, "normal") < G.chance(gcfg, "health", 0.4, "normal"), "rises as health falls")
	near(G.chance(gcfg, "mana", 0.30, "normal"), 35, "mana: the same rule")
	-- the flat chance for rare and better
	near(G.chance(gcfg, "health", 0.9, "rare"), 3, "rare: a flat 3% at full health")
	near(G.chance(gcfg, "health", 0.9, "boss"), 10, "boss: a flat 10%")
	near(G.chance(gcfg, "health", 0.9, "magic"), 0, "magic: none")
	near(G.chance(gcfg, "health", 0.10, "boss"), 60, "capped")
	near(G.chance(gcfg, "mana", nil, "boss"), 0, "no mana pool: no flat chance either")
	eq(G.lowest({0.9, 0.4, 0.7}), 0.4, "the lowest share")
	eq(G.lowest({}), nil, "empty")
	-- rolls
	local r = G.rollKinds(gcfg, {health = 0.2, mana = 0.9}, "normal", low)
	ok(r.health and not r.mana, "a low roll hits health only")
	r = G.rollKinds(gcfg, {health = 0.2, mana = 0.2}, "normal", high)
	ok(not r.health and not r.mana, "a high roll misses")
	r = G.rollKinds(gcfg, {health = 0.9, mana = 0.9}, "normal", low)
	ok(not r.health and not r.mana, "nothing above 60%, whatever the roll")
	-- the long run over many kills at 30%: about 35%
	local s, hits = 7, 0
	local function rng(a, b) s = (s * 16807) % 2147483647 return a + s % (b - a + 1) end
	for _ = 1, 20000 do
		if G.rollKinds(gcfg, {health = 0.30}, "normal", rng).health then hits = hits + 1 end
	end
	ok(hits > 6500 and hits < 7500, "about 35% of 20000 kills at 30% health: " .. hits)
end

-- ------------------------------------------------------------------ amounts, level gap, cooldown
do
	eq(G.amount(gcfg, "health", 1000, 0), 180, "18% of 1000 health")
	eq(G.amount(gcfg, "mana", 500, 0), 90, "18% of 500 mana")
	eq(G.amount(gcfg, "mana", 500, 20), 108, "the tree's Healing +20% on mana")
	eq(G.amount(gcfg, "health", 1, 0), 1, "at least 1")
	ok(G.levelOk(gcfg, 100, 95), "close monsters count")
	ok(G.levelOk(gcfg, 100, 60), "share 0.6 counts")
	ok(not G.levelOk(gcfg, 100, 30), "a trivial monster does not")
	ok(G.levelOk(gcfg, 100, 0), "no known level counts")
	local st = {}
	ok(G.cooldownOk(st, 1, "health", gcfg, 0), "first drop allowed")
	G.noteDrop(st, 1, "health", 1000)
	ok(not G.cooldownOk(st, 1, "health", gcfg, 1000 + gcfg.cooldownMs.health - 1), "cooldown")
	ok(G.cooldownOk(st, 1, "health", gcfg, 1000 + gcfg.cooldownMs.health), "cooldown over")
	ok(G.cooldownOk(st, 1, "mana", gcfg, 1001), "per kind")
	ok(G.cooldownOk(st, 2, "health", gcfg, 1001), "per killer")
end

-- ================================================================== the engine files against a mocked engine
local T = 1000000
os.mtime = function() return T end
local n = 0
for _, name in ipairs({"CONST_ME_MAGIC_RED", "CONST_ME_MAGIC_BLUE", "CONST_ME_HEARTS", "CONST_ME_STUN", "CONST_ME_FIREAREA", "CONST_ME_PURPLEENERGY",
	"CONST_ME_HITBYFIRE", "CONST_ME_POFF", "MESSAGE_STATUS_SMALL", "MESSAGE_INFO_DESCR", "MESSAGE_STATUS_DEFAULT",
	"TILESTATE_BLOCKSOLID", "TILESTATE_PVPZONE", "COMBAT_HEALING", "COMBAT_MANADRAIN", "ITEM_ATTRIBUTE_NAME",
	"ITEM_ATTRIBUTE_DESCRIPTION"}) do
	n = n + 1
	_G[name] = n
end

local effects = {}
local function posKey(p) return p.x .. ":" .. p.y .. ":" .. p.z end
local function Pos(x, y, z)
	local p = {x = x, y = y, z = z}
	function p:sendMagicEffect(id) effects[#effects + 1] = {id = id, x = self.x, y = self.y, z = self.z} end
	return p
end
Position = Pos
local tiles = {}
local function mkTile(x, y, z, solid)
	local t = {_items = {}, _solid = solid}
	function t:getGround() return {} end
	function t:hasFlag(f) return (f == TILESTATE_BLOCKSOLID and self._solid) or false end
	function t:getItemById(id)
		for _, it in ipairs(self._items) do
			if it._id == id then return it end
		end
		return nil
	end
	tiles[x .. ":" .. y .. ":" .. z] = t
	return t
end
for x = 90, 110 do
	for y = 90, 110 do
		mkTile(x, y, 7, false)
	end
end
function Tile(p) return tiles[posKey(p)] end

local installed = {}
for _, r in ipairs(pcfg.items) do installed[r.id] = true end
function ItemType(id) return {getId = function() return installed[id] and id or 0 end} end
local created = {}
Game = {}
function Game.createItem(id, count, pos)
	local it = {_id = id, _attrs = {}, _pos = pos}
	function it:getId() return self._id end
	function it:setAttribute(k, v) self._attrs[k] = v end
	function it:decay() self._decay = true end
	function it:remove()
		local t = tiles[posKey(self._pos)]
		for i, x in ipairs(t._items) do
			if x == self then table.remove(t._items, i) break end
		end
		self._removed = true
	end
	local t = tiles[posKey(pos)]
	t._items[#t._items + 1] = it
	created[#created + 1] = it
	return it
end

local moves, globals, callbacks = {}, {}, {}
function MoveEvent()
	local e = {_ids = {}}
	function e:type() end
	function e:id(...) for _, i in ipairs({...}) do self._ids[i] = true end end
	function e:register() moves[#moves + 1] = e end
	return e
end
function GlobalEvent(name)
	local e = {}
	function e.interval() end
	function e.register() globals[name] = e end
	return e
end
EventCallback = setmetatable({}, {__newindex = function(t, k, v) rawset(t, "_pending", {k, v}) end})
rawset(EventCallback, "register", function(self, index)
	local p = rawget(self, "_pending")
	callbacks[p[1]] = callbacks[p[1]] or {}
	table.insert(callbacks[p[1]], {fn = p[2], index = index or 0})
	rawset(self, "_pending", nil)
end)

local heals = {}
function doTargetCombat(attacker, target, ctype, lo, hi)
	heals[#heals + 1] = {target = target, ctype = ctype, v = lo}
	if ctype == COMBAT_HEALING then
		target._hp = math.min(target._maxhp, target._hp + lo)
	else
		target._mp = math.min(target._maxmp, target._mp + lo)
	end
	return true
end

local players, parties = {}, {}
local function mkPlayer(id, x, y)
	local p = {_id = id, _x = x or 100, _y = y or 100, _hp = 1000, _maxhp = 1000, _mp = 500, _maxmp = 500, _level = 100,
		_stamina = 2520, _msgs = {}, _storage = {}}
	function p:getId() return self._id end
	function p:isPlayer() return true end
	function p:isMonster() return false end
	function p:getPlayer() return self end
	function p:getMaster() return nil end
	function p:getPosition() return Pos(self._x, self._y, self._z or 7) end
	function p:getHealth() return self._hp end
	function p:getMaxHealth() return self._maxhp end
	function p:getMana() return self._mp end
	function p:getMaxMana() return self._maxmp end
	function p:getLevel() return self._level end
	function p:getStamina() return self._stamina end
	function p:getParty() return self._party end
	function p:getStorageValue(k) return self._storage[k] or -1 end
	function p:sendTextMessage(t, text) self._msgs[#self._msgs + 1] = text end
	players[id] = p
	return p
end
function Player(id)
	if type(id) == "table" then return id end
	return players[id]
end
local function mkParty(leader, ...)
	local party = {_leader = leader, _members = {...}}
	function party:getLeader() return self._leader end
	function party:getMembers() local t = {} for _, m in ipairs(self._members) do t[#t + 1] = m end return t end
	leader._party = party
	for _, m in ipairs({...}) do m._party = party end
	return party
end
local function mkMonster(id, tier, level)
	local m = {_id = id, _tier = tier or "normal", _level = level or 100}
	function m:getId() return self._id end
	function m:isPlayer() return false end
	function m:isMonster() return true end
	function m:getPlayer() return nil end
	function m:getMaster() return self._master end
	function m:getMonsterLevel() return self._level end
	return m
end
local function mkCorpse(ownerId, x, y)
	local c = {_owner = ownerId, _x = x or 100, _y = y or 100}
	function c:getCorpseOwner() return self._owner end
	function c:getPosition() return Pos(self._x, self._y, self._z or 7) end
	return c
end
ChaosTierOf = function(m) return m._tier end

dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.inAnyInstance = function(player) return player._instance end
dofile("data/scripts/chaos/pickups.lua")
dofile("data/scripts/chaos/globes.lua")
local P, X = ChaosPickups, ChaosGlobes
ok(P and X, "engine files loaded")
eq(#moves, 1, "one step event")
for _, r in ipairs(pcfg.items) do ok(moves[1]._ids[r.id], r.key .. " registered for the step") end
eq(callbacks.onDropLoot[1].index, 8, "drop callback")
local step = function(who, item, pos) return moves[1].onStepIn(who, item, pos or item._pos, Pos(1, 1, 7)) end
local function itemsOn(x, y) return tiles[x .. ":" .. y .. ":7"]._items end
local tick = function() globals.ChaosPickupsThink.onThink(500) end
local function kill(monster, ownerId, x, y, rand)
	return X.onKill(monster, mkCorpse(ownerId, x, y), players[ownerId], rand or low)
end

-- ---- a kill at low health drops a health globe on the corpse
local hero = mkPlayer(1)
hero._hp, hero._mp = 200, 500 -- 20% health, full mana
local dropped = kill(mkMonster(500), 1)
eq(#dropped, 1, "one globe")
eq(dropped[1], "health", "a health globe (mana is full)")
local globe = itemsOn(100, 100)[1]
ok(globe ~= nil and globe._id == 32088, "the health globe lies on the corpse tile")
ok(globe._decay, "the failsafe decay was started")
eq(P.countOf(1, "health_globe"), 1, "recorded")
ok(#effects > 0 and effects[#effects].id == CONST_ME_MAGIC_RED, "it glows red at once")
-- the cooldown and the limit: a second kill right after drops nothing
eq(#kill(mkMonster(501), 1), 0, "no second globe inside the cooldown")
T = T + gcfg.cooldownMs.health
dropped = kill(mkMonster(502), 1)
eq(#dropped, 1, "a second globe after the cooldown")
eq(P.countOf(1, "health_globe"), 2, "two on the ground")
ok(itemsOn(100, 100)[1] == globe and #itemsOn(100, 100) == 1, "the second landed on another tile (one pickup a tile)")
T = T + gcfg.cooldownMs.health
eq(#kill(mkMonster(503), 1), 0, "the limit of two on the ground")

-- ---- the step: a monster walks over it, a stranger is refused, the owner restores a share of the maximum
eq(step(mkMonster(900), globe), true, "a monster steps over it")
ok(not globe._removed, "and it stays")
local stranger = mkPlayer(2)
step(stranger, globe)
ok(not globe._removed and stranger._msgs[#stranger._msgs]:find("not meant for you"), "a stranger cannot take it")
eq(stranger._hp, 1000, "and is not healed")
local before = hero._hp
step(hero, globe)
ok(globe._removed, "the owner takes it")
eq(hero._hp, before + 180, "restores 18% of the maximum health")
eq(heals[#heals].ctype, COMBAT_HEALING, "through the healing combat (the heal event applies the tree's Healing)")
ok(hero._msgs[#hero._msgs]:find("restores 180 health"), "the message")
eq(P.countOf(1, "health_globe"), 1, "out of the record")
step(hero, globe) -- the item is gone from the tile; a second step event on it cannot heal again
eq(hero._hp, before + 180, "no second heal from the same globe")

-- ---- an item with no record (a restart left it) grants nothing and is removed
local orphan = Game.createItem(32088, 1, Pos(95, 95, 7))
hero._hp = 100
step(hero, orphan)
ok(orphan._removed and hero._hp == 100, "a leftover globe is removed and heals nothing")

-- ---- a full bar leaves the globe for someone who needs it
T = T + 100000
for _, e in pairs(P.reg.byUid) do e.untilMs = T + 1 end
local hero2 = mkPlayer(3, 105, 105)
hero2._hp, hero2._mp = 150, 500
local dropped2 = kill(mkMonster(510), 3, 105, 105)
eq(dropped2[1], "health", "hero2 drops a globe")
local g2 = itemsOn(105, 105)[1]
hero2._hp = hero2._maxhp
step(hero2, g2)
ok(not g2._removed, "full health: the globe stays")

-- ---- the party: the killer at full health, a member near it low -> a globe; any member takes it
local leader = mkPlayer(10, 98, 98)
local mate = mkPlayer(11, 100, 98)
local far = mkPlayer(12, 98, 108)
local out = mkPlayer(13, 99, 99)
mkParty(leader, mate, far)
mate._hp = 200
for _, e in pairs(P.reg.byUid) do P.reg.byUid[e.uid] = nil end
T = T + 100000
dropped = kill(mkMonster(520), 10, 98, 98)
eq(dropped[1], "health", "a low party member near the killer counts")
local pg = itemsOn(98, 98)[1]
step(mate, pg)
ok(pg._removed and mate._hp == 200 + 180, "the party member takes it and is healed")
-- a low member too far away does not count
mate._hp = 1000
far._hp = 100
far._y = 120
T = T + 100000
eq(#kill(mkMonster(521), 10, 98, 98), 0, "a low member out of range does not count")
-- a stranger cannot take a party globe
far._hp = 1000
mate._hp = 200
T = T + 100000
dropped = kill(mkMonster(522), 10, 98, 98)
local pg2 = itemsOn(98, 98)[1]
step(out, pg2)
ok(not pg2._removed, "a player outside the party cannot take it")

-- ---- mana
local mage = mkPlayer(20, 92, 92)
mage._mp = 100 -- 20% mana
T = T + 100000
dropped = kill(mkMonster(530), 20, 92, 92)
eq(dropped[1], "mana", "a mana globe")
local mg = itemsOn(92, 92)[1]
eq(mg._id, 32089, "the mana globe item")
mage._storage[gcfg.healingStorage] = 20
step(mage, mg)
eq(mage._mp, 100 + 108, "18% of the maximum mana x1.2 (the tree's Healing)")
eq(heals[#heals].ctype, COMBAT_MANADRAIN, "mana restored")

-- ---- the lifetime: after 15 s the globe goes out with the fade effect and grants nothing
local runner = mkPlayer(30, 94, 94)
runner._hp = 100
T = T + 100000
kill(mkMonster(540), 30, 94, 94)
local lg = itemsOn(94, 94)[1]
ok(lg ~= nil, "a globe to expire")
T = T + gcfg.lifetimeMs - 1
tick()
ok(not lg._removed, "still there just before the end")
local effBefore = #effects
T = T + 1
tick()
ok(lg._removed, "gone after its lifetime")
eq(effects[#effects].id, CONST_ME_POFF, "with the fade effect")
eq(P.countOf(30, "health_globe"), 0, "out of the record")
step(runner, lg)
eq(runner._hp, 100, "an expired globe heals nothing")
-- the glow pulses
runner._hp = 100
T = T + 100000
kill(mkMonster(541), 30, 94, 94)
local cnt = #effects
T = T + pcfg.pulseMs
tick()
ok(#effects > cnt and effects[#effects].id == CONST_ME_MAGIC_RED, "the glow pulses")

-- ---- nothing drops for ...
local weak = mkPlayer(40, 96, 96)
weak._hp = 100
local function reset() T = T + 100000 end
reset()
local summoned = mkMonster(550)
summoned._master = mkPlayer(41)
eq(#kill(summoned, 40, 96, 96), 0, "a summon's death drops nothing")
eq(#kill(mkMonster(551, "normal", 20), 40, 96, 96), 0, "a trivial monster drops nothing")
weak._stamina = 0
eq(#kill(mkMonster(552), 40, 96, 96), 0, "no globe without stamina for loot")
weak._stamina = 2520
weak._instance = "arena"
eq(#kill(mkMonster(553), 40, 96, 96), 0, "no globe in the arena")
weak._instance = "tower"
eq(#kill(mkMonster(554), 40, 96, 96), 0, "no globe in the Infinity Tower")
weak._instance = "dungeon"
eq(#kill(mkMonster(555), 40, 96, 96), 1, "a dungeon is no blocked place")
reset()
weak._instance = nil
local tdBox = ChaosPickupsConfig.blocked.boxes[1] -- the shipped Tower Defense room
ok(tdBox and tdBox[1] == 31180 and tdBox[2] == 32239 and tdBox[3] == 31236 and tdBox[4] == 32277 and tdBox[5] == 8,
	"the Tower Defense room box is configured")
ChaosPickupsConfig.blocked.boxes[1] = nil
ChaosPickupsConfig.blocked.boxes[1] = {90, 90, 97, 97, 7} -- a test room
eq(#kill(mkMonster(556), 40, 96, 96), 0, "no globe in a configured box")
ChaosPickupsConfig.blocked.boxes[1] = tdBox
-- the shipped box: a kill on its corners and edges drops nothing, one tile outside or on another floor does
local tdp = mkPlayer(42, 31180, 32239)
tdp._hp = 100
tdp._z = 8
for i, c in ipairs({{31180, 32239}, {31236, 32277}, {31208, 32258}, {31236, 32239}}) do
	reset()
	tdp._x, tdp._y = c[1], c[2]
	eq(#kill(mkMonster(570 + i), 42, c[1], c[2]), 0, "no globe in the Tower Defense room at " .. c[1] .. "," .. c[2])
end
for i, c in ipairs({{31179, 32258, 8}, {31237, 32258, 8}, {31208, 32238, 8}, {31208, 32278, 8}, {31208, 32258, 7}}) do
	reset()
	mkTile(c[1], c[2], c[3])
	tdp = mkPlayer(60 + i, c[1], c[2]) -- a new killer each time (cooldown, limit on the ground)
	tdp._hp, tdp._z = 100, c[3]
	local corpse = mkCorpse(60 + i, c[1], c[2])
	corpse._z = c[3]
	eq(#X.onKill(mkMonster(580 + i), corpse, tdp, low), 1, "a globe just outside the room at " .. c[1] .. "," .. c[2] .. "," .. c[3])
end
ChaosBlessings = {pvpPlace = function() return "pvp zone" end}
eq(#kill(mkMonster(557), 40, 96, 96), 0, "no globe in a PvP place")
ChaosBlessings = nil
-- a high roll: a healthy player at full bars gets nothing even from a rare monster at the lowest roll except the flat chance
local fit = mkPlayer(50, 91, 91)
eq(#kill(mkMonster(560, "normal"), 50, 91, 91, low), 0, "full health, full mana, normal monster: nothing")
reset()
ok(#kill(mkMonster(561, "boss"), 50, 91, 91, low) >= 1, "a boss has a flat chance even at full health")
-- no free tile: no globe
reset()
for x = 80, 120 do for y = 80, 120 do if tiles[x .. ":" .. y .. ":7"] then tiles[x .. ":" .. y .. ":7"]._solid = true end end end
eq(#kill(mkMonster(570), 40, 96, 96), 0, "no free tile: no globe")
-- items not installed: no globe
for x = 80, 120 do for y = 80, 120 do if tiles[x .. ":" .. y .. ":7"] then tiles[x .. ":" .. y .. ":7"]._solid = false end end end
installed[32088] = nil
reset()
eq(#kill(mkMonster(571), 40, 96, 96), 0, "items not installed: nothing")
installed[32088] = true
-- the callback never throws
local owner = players[40]
callbacks.onDropLoot[1].fn(mkMonster(580), mkCorpse(99999, 96, 96))
callbacks.onDropLoot[1].fn(mkMonster(581), mkCorpse(40, 96, 96))
ok(true, "the callback survives")

print(string.format("globes_test: %d checks, %d failed", checks, fails))
os.exit(fails == 0 and 0 or 1)
