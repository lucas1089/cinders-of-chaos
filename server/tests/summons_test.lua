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
