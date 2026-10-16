-- Run from the server/ folder: luajit tests/pz_guard_test.lua (or lua5.3; CI runs both)
-- PZ guard (data/scripts/chaos/pz_guard_core.lua): scripted damage never lands on a player in a protection zone.
-- Unit checks of the guard, its install through chaos_constants.lua, and static checks over every Chaos script:
-- a script that keeps doTargetCombat / doTargetCombatHealth in a local at load time loads chaos_constants.lua (and so
-- the guard) first, and direct health removal (addHealth with a negative amount) is only in the reviewed places.
local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end

-- ================================================================== a mocked engine
TILESTATE_PROTECTIONZONE = 1
COMBAT_HEALING = 128
COMBAT_EARTHDAMAGE = 2
COMBAT_MANADRAIN = 64
PlayerFlag_IgnoreProtectionZone = 4096
local pz = {}
local function key(p) return p.x .. "," .. p.y .. "," .. p.z end
local Tl = {}
Tl.__index = Tl
function Tl:hasFlag(f) return f == TILESTATE_PROTECTIONZONE and pz[key(self.p)] == true end
function Tile(p) return setmetatable({p = p}, Tl) end
local creatures = {}
local Cr = {}
Cr.__index = Cr
function Cr:getId() return self.id end
function Cr:isPlayer() return self.player == true end
function Cr:getPosition() return self.pos end
function Cr:hasFlag(f) return self.flags ~= nil and self.flags[f] == true end
local function make(id, o)
	o.id = id
	creatures[id] = setmetatable(o, Cr)
	return creatures[id]
end
function Creature(id) return creatures[id] end

local landed = {}
local function rawHit(caster, target, ctype, min, max)
	landed[#landed + 1] = {caster = caster, target = target, min = min}
	return true
end
doTargetCombat = rawHit
doTargetCombatHealth = rawHit

local carpet = {x = 31648, y = 32256, z = 6}
local cell = {x = 31648, y = 32253, z = 6}
pz[key(carpet)] = true
local wyrm = make(0x40000001, {pos = cell})
local lowbie = make(0x10000001, {player = true, pos = carpet})
local hunter = make(0x10000002, {player = true, pos = cell})
local gm = make(0x10000003, {player = true, pos = carpet, flags = {[PlayerFlag_IgnoreProtectionZone] = true}})

-- ================================================================== the core
dofile("data/scripts/chaos/pz_guard_core.lua")
local Z = ChaosPzGuard
check(Z.inPz(lowbie) and not Z.inPz(hunter), "inPz reads the tile flag")
check(Z.inPz(lowbie.id), "inPz takes a creature id")
check(not Z.inPz(nil) and not Z.inPz(0), "no creature: not in PZ")
check(Z.blocks(wyrm, lowbie, COMBAT_EARTHDAMAGE, -58, -58), "a monster's scripted hit on a player in PZ is dropped")
check(Z.blocks(wyrm.id, lowbie.id, COMBAT_EARTHDAMAGE, -58, -58), "ids work as well as creatures")
check(Z.blocks(0, lowbie, COMBAT_EARTHDAMAGE, -58, -58), "a hit with no caster is dropped too")
check(Z.blocks(hunter, lowbie, COMBAT_EARTHDAMAGE, -10, -10), "another player's scripted hit is dropped")
check(Z.blocks(wyrm, lowbie, COMBAT_MANADRAIN, -10, -10), "a mana drain is dropped")
check(not Z.blocks(wyrm, hunter, COMBAT_EARTHDAMAGE, -58, -58), "off the PZ it lands")
check(not Z.blocks(hunter, wyrm, COMBAT_EARTHDAMAGE, -58, -58), "a monster target is never guarded")
check(not Z.blocks(lowbie, lowbie, COMBAT_HEALING, 50, 50), "healing passes")
check(not Z.blocks(wyrm, lowbie, COMBAT_MANADRAIN, 30, 30), "mana gain passes")
check(not Z.blocks(lowbie, lowbie, COMBAT_EARTHDAMAGE, -5, -5), "a self cost passes")
check(not Z.blocks(gm, lowbie, COMBAT_EARTHDAMAGE, -5, -5), "staff with IgnoreProtectionZone pass")

-- ================================================================== the install (through chaos_constants.lua)
Chaos = nil
dofile("data/scripts/chaos/chaos_constants.lua")
check(doTargetCombat ~= rawHit and doTargetCombatHealth ~= rawHit, "chaos_constants installs the guard")
local wrapped = doTargetCombat
dofile("data/scripts/chaos/chaos_constants.lua")
check(doTargetCombat == wrapped, "a second load keeps the same wrapper")
landed = {}
check(doTargetCombat(wyrm.id, lowbie, COMBAT_EARTHDAMAGE, -58, -58) == false, "doTargetCombat drops the PZ hit")
check(#landed == 0, "nothing reached the engine")
doTargetCombatHealth(wyrm.id, hunter, COMBAT_EARTHDAMAGE, -58, -58, 0)
check(#landed == 1 and landed[1].min == -58, "a hit off the PZ reaches the engine with its arguments")
-- a later wrapper (combatlog.lua keeps the guarded function as its raw one) still drops PZ hits
local outer = doTargetCombat
doTargetCombat = function(...) return outer(...) end
landed = {}
doTargetCombat(wyrm.id, lowbie, COMBAT_EARTHDAMAGE, -58, -58)
check(#landed == 0, "a wrapper over the guard still drops PZ hits")

-- ================================================================== static checks over every Chaos script
local function listLua(dir)
	local out = {}
	local ok, p = pcall(io.popen, 'find "' .. dir .. '" -name "*.lua"')
	if ok and p then
		for line in p:lines() do
			out[#out + 1] = line
		end
		p:close()
	end
	table.sort(out)
	return out
end
local function read(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local files = listLua("data/scripts/chaos")
check(#files > 100, "the Chaos scripts are listed (" .. #files .. ")")
-- direct health removal reviewed against the PZ (path suffix -> why it cannot reach a player in PZ)
local addHealthOk = {
	["/raid.lua"] = "hurt(): raid monsters and bosses only",
	["/descent.lua"] = "hurt(): monsters, and the shrine's self cost the player chose (never lethal)",
	["/trials.lua"] = "the trial boss's own health"
}
for _, path in ipairs(files) do
	local src = read(path) or ""
	local code = src:gsub("%-%-[^\n]*", "") -- comments out
	-- a load-time copy of the combat functions comes after chaos_constants.lua (the guard) is loaded
	local at = nil
	for pos, nextChar in code:gmatch("()=%s*doTargetCombat%a*%s*(%S)") do
		if nextChar ~= "(" and not at then
			at = pos -- a copy (`local hit = doTargetCombat or ...`), not a call
		end
	end
	if at and not path:find("pz_guard_core%.lua$") and not path:find("chaos_constants%.lua$") then
		local loads = code:find('chaos_constants%.lua"%)')
		check(loads ~= nil and loads < at, path .. " copies doTargetCombat after loading chaos_constants.lua")
	end
	-- no script reaches past the guard to the raw engine function
	if not path:find("pz_guard_core%.lua$") then
		check(not code:find("ChaosPzGuard%.raw"), path .. " does not use the unguarded combat functions")
	end
	if code:find("addHealth%(%s*%-") or code:find("addHealth%(%s*\"%a+\"%s*,%s*%-") then
		local ok = false
		for suffix in pairs(addHealthOk) do
			ok = ok or path:sub(-#suffix) == suffix
		end
		check(ok, path .. " removes health directly: guard it with a PZ check and list it in pz_guard_test.lua")
	end
end
local consts = read("data/scripts/chaos/chaos_constants.lua") or ""
check(consts:find("ChaosPzGuard%.install%(%)") ~= nil, "chaos_constants.lua installs the guard")

print(string.format("pz_guard_test: %d checks, %d failures", count, failures))
if failures > 0 then
	os.exit(1)
end
