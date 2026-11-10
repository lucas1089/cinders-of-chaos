-- spell_probe_engine.lua: a recording mock engine for server/tests/spell_inputs_test.lua (derived from the O468 audit probe).
-- It runs one real chaos spell script's onCastSpell against a permissive mock of the engine, with the real helpers of
-- data/lib, data/scripts/chaos and data/spells/chaos, and records every number the script hands to the engine
-- (Combat:execute callbacks, doTargetCombat, doAreaCombat, healing). Not a test by itself.
-- usage: local Probe = dofile("tests/fixtures/spell_probe_engine.lua"); Probe.set{lvl = 500, ...}; local res = Probe.cast(script)
-- inputs (Probe.P): voc, lvl, ml, sword, club, axe, dist, fist, shield, atk (attack of the held weapon), wtype (sword|club|axe|distance|wand|none)
-- A script that rolls a value (math.random(min, max)) is measured at the middle of its range.
local P = {voc = 1, lvl = 100, ml = 50, sword = 80, club = 80, axe = 80, dist = 80, fist = 80, shield = 80, atk = 50,
	wtype = "none", tgt = 1, tmax = 100000, hp = 5000, mana = 5000}
math.random = function(a, b)
	if a and b then return math.floor((a + b) / 2) end
	if a then return math.floor((a + 1) / 2) end
	return 0.5
end
local out = {}
local function rec(...)
	local t = {...}
	for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
	out[#out + 1] = table.concat(t, "\t")
end

------------------------------------------------------------------ Any proxy (permissive stand-in)
local Any
local anyMT = {}
anyMT.__index = function(t, k) if type(k) == "number" then return nil end return Any end
anyMT.__call = function() return Any end
for _, m in ipairs({"__add", "__sub", "__mul", "__div", "__mod", "__unm", "__idiv", "__pow"}) do anyMT[m] = function() return 0 end end
anyMT.__concat = function(a, b) return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "") end
anyMT.__len = function() return 0 end
anyMT.__lt = function() return false end
anyMT.__le = function() return false end
anyMT.__eq = function() return false end
anyMT.__tostring = function() return "any" end
Any = setmetatable({}, anyMT)

if not bit then
	local mk = load("return {band = function(a, b) return (a or 0) & (b or 0) end, bor = function(a, b) return (a or 0) | (b or 0) end, "
		.. "bxor = function(a, b) return (a or 0) ~ (b or 0) end, lshift = function(a, b) return a << b end, rshift = function(a, b) return a >> b end}")
	bit = mk and mk() or {band = function() return 0 end}
end
unpack = unpack or table.unpack

------------------------------------------------------------------ constants (unknown ALL_CAPS names become unique numbers)
local nextConst = 1000
local pname = {}
local AREA_DIM = {CIRCLE1X1 = {3, 3, 5}, CIRCLE2X2 = {5, 5, 13}, CIRCLE3X3 = {7, 7, 37}, CIRCLE5X5 = {11, 11, 97}, CIRCLE6X6 = {13, 13, 129},
	SQUAREWAVE5 = {5, 5, 25}, SQUAREWAVE6 = {7, 7, 49}, WAVE4 = {5, 5, 12}, WAVE6 = {7, 7, 20}, WAVE8 = {9, 9, 32}, BEAM1 = {1, 1, 1},
	BEAM5 = {1, 5, 5}, BEAM7 = {1, 7, 7}, BEAM8 = {1, 8, 8}, WALL = {1, 3, 3}, CROSS1X1 = {3, 3, 5}, CROSS5X5 = {11, 11, 21}, CROSS6X6 = {13, 13, 25}}
NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
setmetatable(_G, {__index = function(t, k)
	if type(k) ~= "string" then return nil end
	local a = k:match("^AREA_(.+)$")
	if a then
		local d = AREA_DIM[a] or {3, 3, 9}
		local v = {_area = true, w = d[1], h = d[2], cells = d[3], name = k}
		rawset(t, k, v)
		return v
	end
	if k:match("^[A-Z][A-Z_0-9]*$") then
		nextConst = nextConst + 1
		pname[nextConst] = k
		rawset(t, k, nextConst)
		return nextConst
	end
	return nil
end})
for _, n in ipairs({"Condition", "Container", "Outfit", "Variant", "Teleport", "Party", "Guild", "House", "Town", "Group", "Spell", "NetworkMessage",
	"ModalWindow", "Waypoint", "Item", "Vocation", "DBResult", "MonsterType", "Loot", "Mount", "Resource"}) do rawset(_G, n, rawget(_G, n) or Any) end
VARIANT_NUMBER, VARIANT_POSITION, VARIANT_TARGETPOSITION, VARIANT_STRING = 1, 2, 3, 4
-- force the constants we compare with into existence
local K = {}
for _, n in ipairs({"CALLBACK_PARAM_LEVELMAGICVALUE", "CALLBACK_PARAM_SKILLVALUE", "CALLBACK_PARAM_TARGETCREATURE", "CALLBACK_PARAM_TARGETTILE",
	"COMBAT_FORMULA_LEVELMAGIC", "COMBAT_FORMULA_SKILL", "COMBAT_FORMULA_DAMAGE", "COMBAT_PARAM_TYPE", "COMBAT_PARAM_EFFECT",
	"COMBAT_PARAM_DISTANCEEFFECT", "ORIGIN_SPELL", "ORIGIN_MELEE", "ORIGIN_RANGED", "ORIGIN_CONDITION", "ORIGIN_NONE", "ORIGIN_WAND",
	"COMBAT_HEALING", "COMBAT_PHYSICALDAMAGE", "SKILL_SWORD", "SKILL_CLUB", "SKILL_AXE", "SKILL_DISTANCE", "SKILL_FIST", "SKILL_SHIELD",
	"WEAPON_SWORD", "WEAPON_CLUB", "WEAPON_AXE", "WEAPON_DISTANCE", "WEAPON_WAND", "WEAPON_NONE", "CONST_SLOT_LEFT", "CONST_SLOT_RIGHT",
	"ITEM_ATTRIBUTE_ATTACK", "SLOTP_TWO_HAND", "COMBAT_PARAM_BLOCKARMOR", "COMBAT_PARAM_USECHARGES", "CONDITION_PARAM_TICKS"}) do K[n] = _G[n] end
local ctypeName = {}
for _, n in ipairs({"PHYSICALDAMAGE", "ENERGYDAMAGE", "EARTHDAMAGE", "FIREDAMAGE", "UNDEFINEDDAMAGE", "LIFEDRAIN", "MANADRAIN", "HEALING",
	"DROWNDAMAGE", "ICEDAMAGE", "HOLYDAMAGE", "DEATHDAMAGE", "ARCANEDAMAGE", "WATERDAMAGE"}) do ctypeName[_G["COMBAT_" .. n]] = n:lower():gsub("damage", "") end
local originName = {}
for _, n in ipairs({"SPELL", "MELEE", "RANGED", "CONDITION", "NONE", "WAND"}) do originName[_G["ORIGIN_" .. n]] = n:lower() end

------------------------------------------------------------------ positions
local CASTER_POS, TARGET_POS = {x = 100, y = 100, z = 7}, {x = 100 + P.tgt, y = 100, z = 7}
local Pmt = {}
local function Position(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x or 0, y = y or 0, z = z or 7}, Pmt)
end
local tileObj
local delay = 0
Pmt.__index = {
	sendMagicEffect = function() end, sendDistanceEffect = function() end,
	getDistanceTo = function(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end,
	isSightClear = function() return true end, getTile = function() return tileObj end,
	getNextPosition = function(self) return self end, isWalkable = function() return true end,
	toString = function(self) return self.x .. "," .. self.y end,
}
Pmt.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
Pmt.__add = function(a, b) return Position(a.x + (b.x or 0), a.y + (b.y or 0), a.z + (b.z or 0)) end
Pmt.__sub = function(a, b) return Position(a.x - (b.x or 0), a.y - (b.y or 0), a.z - (b.z or 0)) end
_G.Position = Position

------------------------------------------------------------------ items / weapon
local WT = {sword = K.WEAPON_SWORD, club = K.WEAPON_CLUB, axe = K.WEAPON_AXE, distance = K.WEAPON_DISTANCE, wand = K.WEAPON_WAND}
local weaponItem
do
	weaponItem = setmetatable({getId = function() return 9001 end, getAttribute = function(_, a) if a == K.ITEM_ATTRIBUTE_ATTACK then return P.atk end return 0 end,
		getCustomAttribute = function() return nil end, getName = function() return "weapon" end},
		{__index = function() return function() return Any end end})
end
function ItemType(id)
	if id == 9001 then
		return setmetatable({getWeaponType = function() return WT[P.wtype] end, getAttack = function() return P.atk end,
			getAmmoType = function() return 0 end, getSlotPosition = function() return 0 end, getId = function() return 9001 end},
			{__index = function() return function() return Any end end})
	end
	return Any
end
function Item() return Any end

------------------------------------------------------------------ creatures
local skillKey = {}
skillKey[K.SKILL_SWORD], skillKey[K.SKILL_CLUB], skillKey[K.SKILL_AXE] = "sword", "club", "axe"
skillKey[K.SKILL_DISTANCE], skillKey[K.SKILL_FIST], skillKey[K.SKILL_SHIELD] = "dist", "fist", "shield"
local skillOf = setmetatable({}, {__index = function(t, s) local k = skillKey[s]; return k and P[k] or nil end})
local function makeCreature(id, pos, isPlayer)
	local c = {_id = id}
	local voc = setmetatable({getId = function() return P.voc end, getName = function() return "voc" .. P.voc end, getBase = function() return Any end},
		{__index = function() return function() return Any end end})
	local methods = {
		getId = function() return id end, getName = function() return isPlayer and "Caster" or "Target" end,
		getPosition = function() return Position(pos) end,
		isPlayer = function() return isPlayer end, isMonster = function() return not isPlayer end, isCreature = function() return true end,
		isNpc = function() return false end, isItem = function() return false end, isTile = function() return false end,
		getLevel = function() return P.lvl end, getMagicLevel = function() return P.ml end,
		getBaseMagicLevel = function() return P.ml end,
		getSkillLevel = function(_, s) return skillOf[s] or 10 end, getEffectiveSkillLevel = function(_, s) return skillOf[s] or 10 end,
		getBaseSkill = function(_, s) return skillOf[s] or 10 end,
		getVocation = function() return voc end, getDirection = function() return EAST end,
		getHealth = function() return isPlayer and (P.hpNow or P.hp) or P.tmax end, getMaxHealth = function() return isPlayer and P.hp or P.tmax end,
		getMana = function() return P.mana end, getMaxMana = function() return P.mana end,
		getTarget = function() return nil end, getStorageValue = function() return -1 end,
		getSpeed = function() return 200 end, getBaseSpeed = function() return 200 end, getSex = function() return 1 end,
		getParty = function() return nil end, getGuild = function() return nil end, getMaster = function() return nil end,
		getSummons = function() return {} end, getOutfit = function() return {lookType = 128} end,
		getCondition = function() return nil end, hasCondition = function() return false end,
		isInGhostMode = function() return false end, isRemoved = function() return false end,
		getAccountId = function() return 1 end, getGuid = function() return 1 end, getItemCount = function() return 0 end,
		getSlotItem = function(_, slot) if isPlayer and slot == K.CONST_SLOT_LEFT and WT[P.wtype] then return weaponItem end return nil end,
		getCapacity = function() return 1000 end, getFreeCapacity = function() return 1000 end, getZone = function() return 0 end,
		getTile = function() return tileObj end, getSkull = function() return 0 end, getType = function() return Any end,
		canSee = function() return true end, sendCancelMessage = function(_, m) rec("CANCEL", tostring(m)) end,
		say = function() return true end, sendTextMessage = function() return true end, getMaxSummons = function() return 5 end,
		getPlayer = function(self) if isPlayer then return self end return nil end,
		getMonster = function(self) if not isPlayer then return self end return nil end, getCreature = function(self) return self end,
		getHealthPercent = function() return 100 end, isPzLocked = function() return false end, isInPz = function() return false end,
		hasSecureMode = function() return false end, getIp = function() return 0 end, getPremiumDays = function() return 100 end,
		getGroup = function() return setmetatable({getId = function() return 1 end, getAccess = function() return false end}, {__index = function() return function() return false end end}) end,
		addHealth = function(_, ...) rec("HEAL", "addHealth", tostring((select(2, ...)) or ""), "", delay) end,
		addMana = function() end, getStamina = function() return 2520 end, getExperience = function() return 1e6 end,
		setStorageValue = function() end, addCondition = function() return true end, removeCondition = function() return true end,
		registerEvent = function() end, getTargetList = function() return {} end,
	}
	return setmetatable(c, {__index = function(t, k) if methods[k] then return methods[k] end return function() return Any end end,
		__eq = function(a, b) return rawequal(a, b) or (type(a) == "table" and type(b) == "table" and rawget(a, "_id") == rawget(b, "_id")) end})
end
local caster = makeCreature(1, CASTER_POS, true)
local target = makeCreature(2, TARGET_POS, false)
function Player(id) if id == 1 or id == caster or (type(id) == "table" and id._id == 1) then return caster end return nil end
function Creature(id) if id == 2 or id == target then return target end if id == 1 or id == caster then return caster end if type(id) == "table" then return id end return nil end
function Monster(id) if id == 2 or id == target then return target end return nil end
function Npc() return nil end
tileObj = setmetatable({hasFlag = function() return false end, getTopCreature = function() return nil end, getCreatures = function() return {} end,
	getItems = function() return {} end, getGround = function() return Any end, isWalkable = function() return true end, getItemCount = function() return 0 end,
	getTopVisibleCreature = function() return nil end, getThingCount = function() return 0 end, getItemById = function() return nil end, queryAdd = function() return 0 end},
	{__index = function() return function() return nil end end})
function Tile() return tileObj end
function Vocation() return Any end

------------------------------------------------------------------ combat
local function sgn(v) return v end
local function recHit(via, ctype, lo, hi, origin)
	rec("HIT", via, ctypeName[ctype] or tostring(ctype), tostring(lo), tostring(hi), originName[origin] or tostring(origin or "spell?"), delay)
end
local Cmt = {}
local function Combat() return setmetatable({params = {}, cb = {}, formula = nil}, Cmt) end
Cmt.__index = {
	setParameter = function(self, k, v) self.params[k] = v end, getParameter = function(self, k) return self.params[k] end,
	setArea = function(self, a) self.area = a end,
	setCallback = function(self, k, name) self.cb[k] = name end,
	setFormula = function(self, ftype, a, b, c, d) self.formula = {ftype, a, b, c, d} end,
	addCondition = function(self, c) self.cond = c end, setOrigin = function(self, o) self.origin = o end, setCondition = function() end,
	execute = function(self, creature, variant)
		local lo, hi, via
		local ctype = self.params[K.COMBAT_PARAM_TYPE]
		local f1, f2 = self.cb[K.CALLBACK_PARAM_LEVELMAGICVALUE], self.cb[K.CALLBACK_PARAM_SKILLVALUE]
		if f1 then
			local fn = rawget(_G, f1)
			lo, hi = fn(creature, P.lvl, P.ml)
			via = "cb:levelmagic"
		elseif f2 then
			local fn = rawget(_G, f2)
			local sk = P.wtype == "none" and P.fist or ({sword = P.sword, club = P.club, axe = P.axe, distance = P.dist, wand = P.ml})[P.wtype]
			local atk = P.wtype == "none" and 7 or P.atk
			lo, hi = fn(creature, sk, atk, 1.0)
			via = "cb:skill(skill=" .. tostring(sk) .. ",atk=" .. tostring(atk) .. ")"
		elseif self.formula then
			local ft, a, b, c, d = unpack(self.formula)
			if ft == K.COMBAT_FORMULA_LEVELMAGIC then
				lo = -(P.lvl / 5 + P.ml * a + b)
				hi = -(P.lvl / 5 + P.ml * c + d)
				via = "formula:levelmagic"
			elseif ft == K.COMBAT_FORMULA_SKILL then
				lo, hi, via = 0, 0, "formula:skill(see script)"
			else
				lo, hi, via = a, c, "formula:" .. tostring(ft)
			end
		elseif self.cond then
			via = "condition"
			lo, hi = 0, 0
		else
			via = "combat:none"
			lo, hi = 0, 0
		end
		recHit("combat:execute/" .. via, ctype, lo, hi, self.origin or ORIGIN_SPELL)
		return true
	end,
}
_G.Combat = Combat
function createCombatArea(t) if type(t) == "table" and t._area then return t end return {_area = true, w = 3, h = 3, cells = 9, name = "custom"} end
function doSendMagicEffect() end
function doChallengeCreature() return true end
function doSendDistanceShoot() end
function doAreaCombat(cid, ctype, pos, area, lo, hi, effect, origin) recHit("doAreaCombat", ctype, lo, hi, origin or ORIGIN_SPELL) return true end
function doAreaCombatHealth(cid, ctype, pos, area, lo, hi, effect, origin) recHit("doAreaCombatHealth", ctype, lo, hi, origin or ORIGIN_SPELL) return true end
function doTargetCombat(cid, tgt, ctype, lo, hi, effect, origin)
	if ctype == COMBAT_HEALING then rec("HEAL", "doTargetCombat", tostring(lo), tostring(hi), delay) else recHit("doTargetCombat", ctype, lo, hi, origin or ORIGIN_SPELL) end
	return true
end
doTargetCombatHealth = doTargetCombat
doCombat = function() return true end
local depth = 0
function addEvent(fn, ms, ...)
	if depth > 8 or type(fn) ~= "function" then return 0 end
	local old = delay
	delay = delay + (tonumber(ms) or 0)
	depth = depth + 1
	pcall(fn, ...)
	depth = depth - 1
	delay = old
	return 1
end
function stopEvent() end
Game = setmetatable({}, {__index = function() return function() return nil end end})
function Game.getSpectators() return {caster, target} end
function Game.createMonster() return nil end
function Game.getWorldTime() return 0 end
function Game.getWorldType() return 1 end
function Game.getStorageValue() return -1 end
function Game.getPlayers() return {caster} end
ChaosSupportsSpell = {wrapped = 0, cast = function() return 1, 1 end, rawAddEvent = addEvent}
local okc, errc = pcall(dofile, "data/scripts/chaos/chaos_constants.lua")
if not okc or type(rawget(_G, "Chaos")) ~= "table" then rec("NOTE", "chaos_constants did not load: " .. tostring(errc):sub(1, 160)) end
json = {encode = function() return "{}" end, decode = function() return {} end}
configManager = setmetatable({getNumber = function() return 0 end, getBoolean = function() return false end, getString = function() return "" end}, {__index = function() return function() return 0 end end})
configKeys = setmetatable({}, {__index = function() return 0 end})
function playSound() end
function doPlaySound() end
os.mtime = os.mtime or function() return os.time() * 1000 end


------------------------------------------------------------------ run
-- the installed server keeps the spell scripts in data/spells/scripts/chaos/, the repository in data/spells/chaos/
local realDofile = dofile
dofile = function(path)
	return realDofile((path:gsub("^data/spells/scripts/chaos/", "data/spells/chaos/")))
end

local okc, errc = pcall(realDofile, "data/scripts/chaos/chaos_constants.lua")
local Probe = {P = P, caster = caster, target = target, loadError = (not okc or type(rawget(_G, "Chaos")) ~= "table") and tostring(errc) or nil}
function Probe.set(t) for k, v in pairs(t) do P[k] = v end end

-- cast one script (path relative to data/spells/chaos): {hits = {{via, ctype, lo, hi, origin, delay}}, heals = {{via, lo, hi, delay}}, err = text or nil}
function Probe.cast(script)
	for i = #out, 1, -1 do out[i] = nil end
	delay = 0
	rawset(_G, "onCastSpell", nil)
	local ok, err = pcall(dofile, "data/spells/scripts/" .. script)
	local res = {hits = {}, heals = {}, err = (not ok) and tostring(err):sub(1, 200) or nil}
	local f = rawget(_G, "onCastSpell")
	if not f then res.err = res.err or "no onCastSpell"; return res end
	local function run(variant)
		return xpcall(f, function(e) return debug.traceback(tostring(e), 2):sub(1, 300) end, caster, variant, false)
	end
	local function collect()
		local n = 0
		for _, l in ipairs(out) do
			local fld = {}
			for x in (l .. "\t"):gmatch("([^\t]*)\t") do fld[#fld + 1] = x end
			if fld[1] == "HIT" then
				res.hits[#res.hits + 1] = {via = fld[2], ctype = fld[3], lo = tonumber(fld[4]), hi = tonumber(fld[5]), origin = fld[6], delay = tonumber(fld[7])}
				n = n + 1
			elseif fld[1] == "HEAL" then
				res.heals[#res.heals + 1] = {via = fld[2], lo = tonumber(fld[3]) or 0, hi = tonumber(fld[4]) or tonumber(fld[3]) or 0, delay = tonumber(fld[5]) or 0}
				n = n + 1
			end
		end
		return n
	end
	local ok2, e2 = run({number = 2, type = VARIANT_NUMBER})
	if not ok2 then res.err = tostring(e2) end
	if collect() == 0 then
		res.hits, res.heals = {}, {}
		for i = #out, 1, -1 do out[i] = nil end
		delay = 0
		local ok3, e3 = run({number = 0, type = VARIANT_POSITION, x = 100 + P.tgt, y = 100, z = 7})
		if not ok3 then res.err = tostring(e3) end
		collect()
	end
	return res
end

-- the sum of every damage and heal value of a cast (the middle of each min / max)
function Probe.total(res)
	local dmg, heal = 0, 0
	for _, h in ipairs(res.hits) do dmg = dmg + (math.abs(h.lo) + math.abs(h.hi)) / 2 end
	for _, h in ipairs(res.heals) do heal = heal + (math.abs(h.lo) + math.abs(h.hi)) / 2 end
	return dmg, heal
end

pcall(realDofile, "data/lib/chaos_casting.lua")
if rawget(_G, "ChaosCasting") and ChaosCasting.spell then
	-- cast-time spells fire at once
	ChaosCasting.spell = function(spec)
		return function(creature, variant, isHotkey)
			local player = creature:getPlayer()
			local ctx = {}
			if spec.prepare then
				ctx = spec.prepare(player, variant)
				if not ctx then return false end
			end
			ctx.variant = ctx.variant or variant
			if spec.check then
				local okc2, res = pcall(spec.check, player, ctx)
				if not okc2 or res ~= true then rec("NOTE", "casting check failed: " .. tostring(res)) end
			end
			local r = spec.fire(player, ctx)
			return r ~= false
		end
	end
end
pcall(realDofile, "data/spells/chaos/_monk.lua")
if rawget(_G, "MonkSpell") then
	MonkSpell.finisher = function() return 5 end -- a finisher is given 5 chi
end
return Probe
