-- Run from the server/ folder: luajit tests/necro_summon_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- The Necromancer line's summon cap on a mocked engine (data/scripts/chaos/necro_lib.lua M.raise): the total cap of all
-- kinds together, the oldest minion dismissed first (a puff, no corpse), the new one created after, Raise Dead following
-- the same rule, and the three summon spells (Raise Bone Warrior / Archer / Mage) creating one minion of their kind.
local fails, checks = 0, 0
local function ok(c, what)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ------------------------------------------------------------------ a small engine
COMBAT_PHYSICALDAMAGE, COMBAT_DEATHDAMAGE, COMBAT_ENERGYDAMAGE = 1, 2, 3
CONST_ANI_DEATH, CONST_ANI_ARROW, CONST_ANI_ENERGY = 1, 2, 3
CONST_ME_HITAREA, CONST_ME_ENERGYHIT, CONST_ME_MORTAREA, CONST_ME_POFF = 1, 2, 3, 4
RETURNVALUE_NOTENOUGHROOM, SKULL_BLACK = 9, 5
function Position(p) return {x = p.x, y = p.y, z = p.z} end

local puffs, created, removed = 0, {}, {}
local nextId = 100
local function makeMonster(name)
	local m = {id = nextId, name = name, health = 1, maxHealth = 1, removed = false, pos = {x = 0, y = 0, z = 7}}
	nextId = nextId + 1
	function m:getId() return self.id end
	function m:getName() return self.name end
	function m:isMonster() return true end
	function m:isRemoved() return self.removed end
	function m:getPosition()
		local pos = self.pos
		pos.sendMagicEffect = function() puffs = puffs + 1 end
		return pos
	end
	function m:remove() self.removed = true removed[#removed + 1] = self.name end
	function m:setDropLoot(v) self.drop = v end
	function m:registerEvent() end
	function m:setMaxHealth(v) self.maxHealth = v end
	function m:getHealth() return self.health end
	function m:getMaxHealth() return self.maxHealth end
	function m:addHealth(_, v) self.health = math.min(self.maxHealth, self.health + (v or 0)) end
	function m:getBaseSpeed() return 200 end
	function m:changeSpeed() end
	function m:getMaster() return self.owner end
	-- engine patches 0040 / 0044 / 0056; `sent` counts the level changes the spectators were told about
	function m:setDisplayLevel(v) self.shown = v self.sent = (self.sent or 0) + 1 end
	function m:getDisplayLevel() return self.shown or 0 end
	return m
end
function Game_createMonster(name, pos)
	local m = makeMonster(name)
	m.pos = {x = pos.x, y = pos.y, z = pos.z}
	created[#created + 1] = m
	return m
end
Game = {createMonster = function(name, pos) return Game_createMonster(name, pos) end}

local fxCalls = 0
ChaosSpell = {
	isFreeTile = function() return true end,
	freeAround = function(pos) return {{pos = pos}} end,
	bindSummon = function(player, m) m.owner = player player.summons[#player.summons + 1] = m end,
	fx = function() fxCalls = fxCalls + 1 end,
	vfxOr = function() end,
	cancel = function(player, why) player.cancelled = why or true return false end,
}
ChaosClassTree = {has = function() return false end, value = function() return 0 end, fx = {}}

-- the installed server has the spell helpers under data/spells/scripts/chaos; here they are in data/spells/chaos
local realDofile = dofile
function dofile(path)
	if path:find("_common.lua", 1, true) then
		return nil -- ChaosSpell is the mock above
	end
	return realDofile((path:gsub("^data/spells/scripts/chaos/", "data/spells/chaos/")))
end
dofile("data/scripts/chaos/necro_lib.lua")
local L, N, cfg = ChaosNecro, ChaosNecroCore, ChaosNecroConfig
dofile("data/spells/scripts/chaos/_necro.lua")

local function player(vocId, level)
	local p = {summons = {}, level = level or 50}
	function p:getVocation() return {getId = function() return vocId end} end
	function p:getLevel() return self.level end
	function p:getMagicLevel() return 40 end
	function p:getBaseSpeed() return 220 end
	function p:getPosition() return {x = 10, y = 10, z = 7} end
	function p:getSkull() return self.skull or 0 end
	function p:getSummons()
		local live = {}
		for _, s in ipairs(self.summons) do
			if not s.removed then live[#live + 1] = s end
		end
		self.summons = live
		return live
	end
	return p
end
local function names(p)
	local t = {}
	for _, s in ipairs(p:getSummons()) do t[#t + 1] = s.name end
	return table.concat(t, ",")
end

-- ------------------------------------------------------------------ the cap
local nec = player(cfg.ids.necromancer)
L.raise(nec, "warrior", {x = 10, y = 10, z = 7})
L.raise(nec, "archer", {x = 10, y = 10, z = 7})
L.raise(nec, "mage", {x = 10, y = 10, z = 7})
eq(names(nec), "Risen Warrior,Risen Archer,Risen Mage", "three summons out")
eq(#removed, 0, "none dismissed below the cap")
local before = puffs
L.raise(nec, "skeleton", {x = 10, y = 10, z = 7})
eq(names(nec), "Risen Archer,Risen Mage,Risen Skeleton", "a fourth: the oldest (the warrior) is gone, the new one is out")
eq(removed[#removed], "Risen Warrior", "the warrior was dismissed")
ok(puffs > before, "a puff where it stood")
L.raise(nec, "warrior", {x = 10, y = 10, z = 7})
eq(names(nec), "Risen Mage,Risen Skeleton,Risen Warrior", "a fifth: the archer goes next")
L.raise(nec, "archer", {x = 10, y = 10, z = 7})
eq(names(nec), "Risen Skeleton,Risen Warrior,Risen Archer", "a sixth: the mage goes")
eq(#nec:getSummons(), 3, "always three at most")
for _, m in ipairs(created) do
	eq(m.drop, false, m.name .. ": no loot")
end

-- Raise Dead's kind follows the total cap too (a necromancer's skeleton raised with 3 others out)
local nec2 = player(cfg.ids.necromancer, 100)
for _, k in ipairs({"warrior", "archer", "mage"}) do L.raise(nec2, k, {x = 10, y = 10, z = 7}) end
L.raise(nec2, "skeleton", {x = 10, y = 10, z = 7})
L.raise(nec2, "skeleton", {x = 10, y = 10, z = 7})
eq(names(nec2), "Risen Mage,Risen Skeleton,Risen Skeleton", "two skeletons from Raise Dead push out the two oldest")

-- the Lich keeps one minion, the Bone Lord his army
local lich = player(cfg.ids.lich, 300)
L.raise(lich, "shade", {x = 10, y = 10, z = 7})
L.raise(lich, "warrior", {x = 10, y = 10, z = 7})
eq(names(lich), "Risen Warrior", "the lich: one minion in all, the warrior replaced the shade")
local bl = player(cfg.ids.bonelord, 100)
for _ = 1, 5 do L.raise(bl, "skeleton", {x = 10, y = 10, z = 7}) end
L.raise(bl, "golem", {x = 10, y = 10, z = 7})
eq(#bl:getSummons(), 6, "bone lord: 5 skeletons and the golem")
L.raise(bl, "mage", {x = 10, y = 10, z = 7})
eq(#bl:getSummons(), 6, "bone lord: still 6 (the oldest skeleton went)")
eq(names(bl), "Risen Skeleton,Risen Skeleton,Risen Skeleton,Risen Skeleton,Bone Golem,Risen Mage", "the oldest skeleton")

-- not a necromancer: nothing is raised
local war = player(4)
eq(L.raise(war, "warrior", {x = 1, y = 1, z = 7}), nil, "another class raises nothing")
eq(#created > 0, true, "(engine mock in use)")

-- ------------------------------------------------------------------ the spell scripts
local function cast(file, p)
	dofile(file)
	return onCastSpell({getPlayer = function() return p end}, {}, false)
end
for _, kind in ipairs({"warrior", "archer", "mage"}) do
	local p = player(cfg.ids.necromancer)
	local n = #created
	eq(cast("data/spells/chaos/necromancer/raise_" .. kind .. ".lua", p), true, kind .. " spell: cast")
	eq(#created, n + 1, kind .. " spell: ONE minion")
	eq(created[#created].name, cfg.minions[kind].monster, kind .. " spell: its monster type")
	eq(#p:getSummons(), 1, kind .. " spell: one summon")
	p.skull = SKULL_BLACK
	eq(cast("data/spells/chaos/necromancer/raise_" .. kind .. ".lua", p), false, kind .. " spell: not with a black skull")
	local x = player(4)
	eq(cast("data/spells/chaos/necromancer/raise_" .. kind .. ".lua", x), false, kind .. " spell: not another class")
end

-- ------------------------------------------------------------------ levels follow the owner
-- owner report 2026-10-21: "the risen skeletons' level does not follow the player's"
eq(N.minionLevel(312), 312, "the shown level is the owner's")
eq(N.minionLevel(0), 1, "at least 1")
eq(N.minionLevel(nil), 1, "no level: 1")
eq(N.rescaleHealth(1000, 500, 2000), 1000, "half health stays half")
eq(N.rescaleHealth(1000, 1000, 1200), 1200, "full stays full")
eq(N.rescaleHealth(1000, 1, 500), 1, "never below 1 while alive")
eq(N.rescaleHealth(1000, 0, 2000), 0, "a dead minion stays dead")
eq(N.rescaleHealth(1000, 900, 500), 450, "a smaller maximum keeps the share")
local lv = player(cfg.ids.necromancer, 120)
for _, kind in ipairs({"warrior", "skeleton"}) do
	local m = L.raise(lv, kind, {x = 10, y = 10, z = 7})
	eq(m.shown, 120, kind .. ": shows the owner's level when raised")
	eq(m.maxHealth, L.healthFor(lv, "necromancer", kind), kind .. ": health from the owner's level")
end
local w = lv:getSummons()[1]
local oldMax = w.maxHealth
w.health = math.floor(oldMax / 2)
lv.level = 150 -- a level up while the minion is out
eq(L.refresh(lv, "necromancer", w, "warrior"), true, "a level up refreshes the minion")
eq(w.shown, 150, "the shown level follows the level up")
ok(w.maxHealth > oldMax, "the maximum health grows with the level")
eq(w.maxHealth, N.minionHealth(cfg, "necromancer", "warrior", 150, 40, 1), "the new maximum is the formula's")
ok(math.abs(w.health - w.maxHealth / 2) <= 1, "and the minion keeps half of it")
local sent = w.sent
eq(L.refresh(lv, "necromancer", w, "warrior"), false, "nothing changed: nothing sent")
eq(w.sent, sent, "no packet without a change")
-- an engine without setDisplayLevel: the stats still follow, nothing breaks
local bare = makeMonster("Risen Warrior")
bare.setDisplayLevel = nil
eq(L.showLevel(lv, bare), false, "no engine method: no level shown")

-- ------------------------------------------------------------------ no farming
-- every minion type: no experience and no loot of its own (killing one, the owner's or another player's, gives nothing);
-- the spell turns the loot drop off too (checked above); the owner cannot hurt its minions (necro_minions.lua guard,
-- summons.lua refuses the attack)
for kind, k in pairs(cfg.minions) do
	if type(k) == "table" and k.monster then
		local file = "data/monster/monsters/chaos/necro_" .. k.monster:lower():gsub("^risen ", "risen_"):gsub(" ", "_") .. ".xml"
		local f = io.open(file, "r")
		ok(f ~= nil, kind .. ": " .. file .. " exists")
		if f then
			local xml = f:read("*a")
			f:close()
			eq(xml:match('experience="(%d+)"'), "0", kind .. ": no experience (" .. file .. ")")
			eq(xml:find("<loot", 1, true), nil, kind .. ": no loot table")
		end
	end
end
local guardSrc = io.open("data/scripts/chaos/necro_minions.lua"):read("*a")
ok(guardSrc:find("attacker == owner or attacker:getMaster() == owner", 1, true) ~= nil, "the owner's hits do not hurt its minions")

-- ------------------------------------------------------------------ the engine halves (src-patches)
local function readPatch(name)
	local f = io.open("src-patches/" .. name, "r")
	ok(f ~= nil, name .. " exists")
	if not f then return "" end
	local t = f:read("*a")
	f:close()
	return t
end
local p55 = readPatch("0055-own-summons-walk-through.patch")
local _, walk = p55:gsub("%+[^\n]*creature%->getMaster%(%) == this", "")
eq(walk, 2, "0055: canWalkthrough and canWalkthroughEx let the owner through its own summons")
ok(p55:find("+\tupdateCreatureWalkthrough(creature);", 1, true) ~= nil, "0055: setMaster sends the walk-through state")
ok(readPatch("0056-summon-display-level-refresh.patch"):find("sendUpdateTileCreature(monster)", 1, true) ~= nil,
	"0056: a changed display level reaches the spectators")
ok(readPatch("0057-script-target-drop-tells-client.patch"):find("player->sendCancelTarget()", 1, true) ~= nil,
	"0057: setTarget(nil) on a player tells its client")

print(string.format("necro_summon_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
