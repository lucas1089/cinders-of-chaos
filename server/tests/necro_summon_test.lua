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

print(string.format("necro_summon_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
