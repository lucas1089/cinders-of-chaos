-- Run from the server/ folder: luajit tests/summons_test.lua (mock engine API; CI runs it with luajit and lua5.3)
-- Owner report 2026-10-17: the Beastmaster's wolf and its owner took each other for enemies (the wolf at the owner, the
-- owner stuck with the wolf as target, the red claw of Feral Command on the player's own wolf). Covers the side rules
-- (summons_core.lua), the callbacks (summons.lua) and the wiring of every summon spell and script.
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end
local function read(path) local f = assert(io.open(path, "r")); local t = f:read("*a"); f:close(); return t end

-- creature mocks
local nextId = 0
local function mk(kind, o)
	nextId = nextId + 1
	local c = {kind = kind, id = nextId, pos = {x = 100, y = 100, z = 7}, hp = 100, master = nil, party = nil, target = nil,
		attackable = true}
	for k, v in pairs(o or {}) do c[k] = v end
	local m = {c = c}
	function m:getId() return c.id end
	function m:isPlayer() return c.kind == "player" end
	function m:isMonster() return c.kind == "monster" end
	function m:getMaster() return c.master end
	function m:getParty() return c.party end
	function m:getPosition() return c.pos end
	function m:getHealth() return c.hp end
	function m:isAttackable() return c.attackable end
	function m:getTarget() return c.target end
	function m:setTarget(t) c.target = t return true end
	function m:setMaster(p) c.master = p; c.log = (c.log or "") .. "master;" end
	function m:getSummons() return c.summons or {} end
	return m
end

dofile("data/scripts/chaos/summons_core.lua")
local K = ChaosSummonsCore
local ownerA, ownerB, friend = mk("player"), mk("player"), mk("player")
local partyAF = {}
ownerA.c.party, friend.c.party = partyAF, partyAF
local wolf = mk("monster"); wolf.c.master = ownerA
local friendWolf = mk("monster"); friendWolf.c.master = friend
local foeWolf = mk("monster"); foeWolf.c.master = ownerB
local boar = mk("monster", {pos = {x = 104, y = 100, z = 7}}) -- a wild monster
local npc = mk("monster", {kind = "npc"})

eq(K.ownerOf(ownerA), ownerA, "a player is its own owner"); eq(K.ownerOf(wolf), ownerA, "a summon: its master")
eq(K.ownerOf(boar), nil, "a wild monster has no owner"); eq(K.ownerOf(nil), nil, "nothing")
eq(K.isAlly(ownerA, ownerA), true, "itself"); eq(K.isAlly(ownerA, wolf), true, "its summon")
eq(K.isAlly(ownerA, friend), true, "a party member"); eq(K.isAlly(ownerA, friendWolf), true, "a party member's summon")
eq(K.isAlly(ownerA, ownerB), false, "another player"); eq(K.isAlly(ownerA, foeWolf), false, "another player's summon")
eq(K.isAlly(ownerA, boar), false, "a wild monster"); eq(K.isAlly(ownerA, nil), false, "nothing")
eq(K.isAlly(wolf, ownerA), false, "the rule is asked about a player (the summon's side is its owner's)")
eq(K.isAlly(ownerB, wolf), false, "ownerB: not A's wolf")
eq(K.isAllySummon(ownerA, wolf), true, "own summon"); eq(K.isAllySummon(ownerA, friend), false, "a player is not a summon")
eq(K.isAllySummon(ownerA, friendWolf), true, "party summon"); eq(K.isAllySummon(ownerA, boar), false, "wild")
-- a solo player has no party: two nil parties are not a party
eq(K.isAlly(ownerB, mk("player")), false, "two players without a party")

-- nearest enemy
local near, far = mk("monster", {pos = {x = 102, y = 100, z = 7}}), mk("monster", {pos = {x = 105, y = 103, z = 7}})
local otherFloor = mk("monster", {pos = {x = 101, y = 100, z = 8}})
local dead = mk("monster", {pos = {x = 101, y = 101, z = 7}, hp = 0})
local hidden = mk("monster", {pos = {x = 101, y = 99, z = 7}})
local from = {x = 100, y = 100, z = 7}
local all = {wolf, friendWolf, ownerB, boar, near, far, otherFloor, dead, hidden, foeWolf, npc}
eq(K.nearestEnemy(ownerA, all, from, 7), hidden, "the nearest wild monster (own and party summons, players skipped)")
eq(K.nearestEnemy(ownerA, all, from, 7, function(c) return c ~= hidden end), near, "the caller's filter")
local tie = mk("monster", {pos = {x = 98, y = 100, z = 7}})
eq(K.nearestEnemy(ownerA, {tie, near}, from, 7), near, "equal distance: the lower id, whatever the order")
eq(K.nearestEnemy(ownerA, {far}, from, 2), nil, "out of range")
eq(K.nearestEnemy(ownerA, {wolf, friend}, from, 7), nil, "only allies around: none")
eq(K.nearestEnemy(ownerA, {foeWolf}, from, 7), nil, "another player's summon is not picked either (PvP rules decide that)")
eq(K.nearestEnemy(ownerA, nil, from, 7), nil, "no list")

-- bind: the master is set, the creation target and follow state are cleared
local fresh = mk("monster")
fresh.c.target = ownerA
fresh.c.follow = ownerA
function fresh:setFollowCreature(t) fresh.c.follow = t end
eq(K.bind(ownerA, fresh), fresh, "returns the monster")
eq(fresh.c.master, ownerA, "master set"); eq(fresh.c.target, nil, "the owner is no target of its summon"); eq(fresh.c.follow, nil, "nor followed as a target")
local bare = {setMaster = function(self, p) self.m = p end}                         -- an engine without setTarget
K.bind(ownerA, bare); eq(bare.m, ownerA, "bind needs no setTarget")
local failing = {setMaster = function(self, p) self.m = p end, setTarget = function() error("boom") end}
K.bind(ownerA, failing); eq(failing.m, ownerA, "a failing setTarget does not break the summon")

-- ------------------------------------------------------------------ the callbacks
local callbacks, ticks = {}, {}
-- EventCallback is used as `local cb = EventCallback; cb.onTargetCombat = ...; cb:register(-60)`
local shared = {}
function shared:register(prio) callbacks[#callbacks + 1] = {cb = self, prio = prio} end
EventCallback = shared
function GlobalEvent(name) local o = {name = name}; function o:interval(i) self.i = i end; function o:register() ticks[name] = self end; return o end
RETURNVALUE_NOERROR, RETURNVALUE_YOUMAYNOTATTACKTHISCREATURE = 0, 77
local players = {ownerA, ownerB, friend}
Game = {getPlayers = function() return players end}
dofile("data/scripts/chaos/summons.lua")
eq(#callbacks, 1, "one onTargetCombat callback"); eq(callbacks[1].prio, -60, "ahead of the usual hooks")
local hit = callbacks[1].cb.onTargetCombat
eq(hit(wolf, ownerA), 77, "a summon never hits its owner")
eq(hit(wolf, friend), 77, "nor the owner's party")
eq(hit(wolf, friendWolf), 77, "nor a party member's summon")
eq(hit(wolf, boar), 0, "it hits wild monsters")
eq(hit(wolf, ownerB), 0, "and the owner's enemies (PvP rules decide the rest)")
ownerA.c.target = wolf
eq(hit(ownerA, wolf), 77, "a player never hits its own summon"); eq(ownerA.c.target, nil, "and the target is dropped")
eq(hit(ownerA, friendWolf), 77, "nor a party member's summon")
eq(hit(ownerA, boar), 0, "a player hits monsters"); eq(hit(ownerA, ownerB), 0, "players: the base PvP rules")
eq(hit(boar, ownerA), 0, "a wild monster hits players"); eq(hit(nil, ownerA), 0, "nothing")
-- the 0.5 s tick drops an ally summon from the target
eq(ticks.ChaosSummonsTargets.i, 500, "tick every 0.5 s")
ownerA.c.summons = {wolf}
ownerA.c.target = wolf
ticks.ChaosSummonsTargets.onThink(500)
eq(ownerA.c.target, nil, "the tick drops the wolf as target")
ownerA.c.target = boar
ticks.ChaosSummonsTargets.onThink(500)
eq(ownerA.c.target, boar, "and leaves a monster alone")
ownerB.c.target = mk("monster"); ownerB.c.summons = {}
ticks.ChaosSummonsTargets.onThink(500)
eq(ownerB.c.target ~= nil, true, "a player without summons or party is not touched")

-- ------------------------------------------------------------------ O86: the engine target list
-- A monster placed next to players lists them as targets; a player's summon takes everybody but its master for an
-- opponent. Mocks: targets list per monster, a party whose getParty() answers a fresh table each call.
local function withTargets(m, list)
	m.c.targets = list
	function m:getTargetList() return m.c.targets end
	function m:removeTarget(t)
		for i, x in ipairs(m.c.targets) do if x == t then table.remove(m.c.targets, i) return true end end
		return false
	end
	return m
end
local function has(list, x) for _, v in ipairs(list) do if v == x then return true end end return false end

-- creation: the owner and a party member and the owner's other summon stand in the list, a wild boar too
local pOwner, pFriend, pOther = mk("player"), mk("player"), mk("player")
local leaderObj = {}
function leaderObj.getLeader() return pOwner end
pOwner.getParty = function() return {getLeader = leaderObj.getLeader, fresh = {}} end   -- fresh userdata per call
pFriend.getParty = function() return {getLeader = leaderObj.getLeader, fresh = {}} end
eq(pOwner:getParty() == pFriend:getParty(), false, "fresh party objects never compare equal")
eq(K.sameParty(pOwner, pFriend), true, "same leader: same party")
eq(K.isAlly(pOwner, pFriend), true, "a party member is an ally, whatever == says")
eq(K.sameParty(pOwner, pOther), false, "no party: not the same"); eq(K.sameParty(pOwner, nil), false, "nothing")
local pw1 = mk("monster"); pw1.c.master = pOwner
local pwFriend = mk("monster"); pwFriend.c.master = pFriend
local foe = mk("monster")
local cw = withTargets(mk("monster"), {pOwner, pFriend, pw1, pwFriend, foe, pOther})
function cw:setFollowCreature(t) cw.c.follow = t end
cw.c.target = pOwner
K.bind(pOwner, cw)
eq(has(cw.c.targets, pOwner), false, "creation: the owner is out of the target list")
eq(has(cw.c.targets, pFriend), false, "creation: the party member too (fresh party objects)")
eq(has(cw.c.targets, pw1) or has(cw.c.targets, pwFriend), false, "creation: the allies' summons too")
eq(has(cw.c.targets, foe), true, "a wild monster stays a target"); eq(has(cw.c.targets, pOther), true, "a stranger stays one (PvP rules)")
eq(cw.c.target, nil, "creation: no attack target")

-- relog / pet login / teleport / town portal / zone change: the engine lists everybody in sight again; the tick purges
cw.c.targets[#cw.c.targets + 1] = pOwner; cw.c.targets[#cw.c.targets + 1] = pFriend
cw.c.target = pFriend
pOwner.c.summons = {cw}
eq(K.purgeAll(pOwner), 3, "purgeAll: two list entries and the attack target"); eq(cw.c.target, nil, "the party member is no attack target")
eq(has(cw.c.targets, pOwner) or has(cw.c.targets, pFriend), false, "relog / teleport / portal: listed again, purged again")
eq(has(cw.c.targets, foe), true, "wild monster kept")
eq(K.purgeAll(pOwner), 0, "idempotent")
-- a summon follows its master: the follow target is never cleared by the purge
cw.c.follow = pOwner; K.purge(cw, pOwner); eq(cw.c.follow, pOwner, "follow target kept")
-- party join: the friend joins after the wolf exists -> next tick drops him
local late = mk("player"); late.getParty = pOwner.getParty
cw.c.targets[#cw.c.targets + 1] = late
eq(K.purge(cw, pOwner), 1, "party join: the new member is removed on the next tick"); eq(has(cw.c.targets, late), false, "gone")
-- party leave: no longer an ally, so he can be a target again (PvP rules decide the hits)
late.getParty = function() return nil end
cw.c.targets[#cw.c.targets + 1] = late
eq(K.purge(cw, pOwner), 0, "left the party: not purged")
-- skull / secure mode / PvP zones: the purge only ever removes allies, never enemies
local skulled = mk("player"); skulled.c.skull = true
cw.c.targets[#cw.c.targets + 1] = skulled
eq(K.purge(cw, pOwner), 0, "a skulled stranger is not an ally"); eq(has(cw.c.targets, skulled), true, "kept")
-- engines without the list API, or failing: no error
eq(K.purge({}, pOwner), 0, "no API"); eq(K.purge(nil, pOwner), 0, "nothing")
eq(K.purge({getTargetList = function() error("boom") end, removeTarget = function() end}, pOwner), 0, "failing getTargetList")
eq(K.purgeAll({getSummons = function() error("boom") end}), 0, "failing getSummons")
-- the owner's target is a summon of its own: dropped (relog: autotarget)
pOwner.c.target = pw1
players = {pOwner}
Game.getPlayers = function() return players end
ticks.ChaosSummonsTargets.onThink(500)
eq(pOwner.c.target, nil, "the tick drops the own summon as the owner's target")
cw.c.targets[#cw.c.targets + 1] = pOwner
pOwner.c.summons = {cw}
ticks.ChaosSummonsTargets.onThink(500)
eq(has(cw.c.targets, pOwner), false, "the tick purges the summons' target lists")

-- ------------------------------------------------------------------ the wiring
local wild = read("data/spells/chaos/beastmaster/wild_bond.lua")
assert(wild:find("ChaosSpell.bindSummon(player, m)", 1, true) and not wild:find(":setMaster(", 1, true), "Wild Bond binds its companions")
local moon = read("data/spells/chaos/druid/spirit_wolves.lua")
assert(moon:find("ChaosSpell.bindSummon(player, wolf)", 1, true) and not moon:find(":setMaster(", 1, true), "Moonfang Pack binds its wolves")
assert(moon:find("ChaosCompanionGuard", 1, true), "Moonfang wolves take no hits from the owner's area spells")
assert(read("data/spells/chaos/illusionist/mirror_image.lua"):find("bindSummon", 1, true), "Mirror Image binds its clones")
assert(read("data/scripts/chaos/necro_lib.lua"):find("ChaosSpell.bindSummon(player, m)", 1, true), "the Necromancer's minions")
local arch = read("data/scripts/chaos/archetypes.lua")
local _, binds = arch:gsub("bindSummon%(player, m%)", "")
eq(binds, 2, "effigy and reliquary warden bind")
assert(not arch:find("m:setMaster(player)", 1, true), "no raw setMaster left in archetypes.lua")
assert(read("data/scripts/chaos/pets.lua"):find("ChaosSummonsCore.bind(player, pet)", 1, true), "pets")
local feral = read("data/spells/chaos/beastmaster/feral_command.lua")
assert(feral:find("Sides.isAlly(player, target)", 1, true) and feral:find("Sides.nearestEnemy", 1, true),
	"Feral Command never takes an ally for its target")
local beast = read("data/scripts/chaos/beastmaster.lua")
assert(beast:find("ChaosSummonsCore.isAlly(owner, target)", 1, true), "the companion's bite skips an ally target")
local common = read("data/spells/chaos/_common.lua")
assert(common:find("function ChaosSpell.bindSummon", 1, true) and common:find("function ChaosSpell.loadSummons", 1, true), "_common helpers")
print("summons tests OK")
