-- Recording mock engine of tools/ci/check_spell_fx.py: runs one chaos spell script's onCastSpell against a permissive
-- mock of the engine and prints every effect it sends, with the real libraries of server/data/lib and
-- server/data/scripts/chaos (the swap layers: skins, the effects pass, pair 29, 36, class, pair 27).
-- usage (cwd = a folder with data/lib, data/scripts/chaos and data/spells/scripts/chaos linked in):
--   lua5.3 spell_fx_probe.lua VOCID SPELLID SCRIPT_REL_TO_SPELLS_SCRIPTS [CASTER_LEVEL] [TARGET_DX]
-- Output lines (tab separated):  ME id tx ty (abs pos minus target pos) cx cy (minus caster pos) delay via
--                                ANI id from_dx to_dx ...
--                                COMBAT effect distance cells w h
--                                CANCEL text   (a cancel puff that follows it is not a cast effect)
-- The Monk finisher is given chi (its cast needs a storage the mock does not hold). Nothing is written anywhere.
local vocId, spellId, script = tonumber(arg[1]), tonumber(arg[2]), arg[3]
local level = tonumber(arg[4]) or 300
local out = {}
local pname = {}
local function rec(...) local t = {...}; for i = 1, select('#', ...) do t[i] = tostring(t[i]); if t[i]:match('^10%d%d$') and pname[tonumber(t[i])] then t[i] = pname[tonumber(t[i])] end end; out[#out + 1] = table.concat(t, "\t") end

------------------------------------------------------------------ Any proxy
local Any
local anyMT = {}
anyMT.__index = function(t, k) if type(k) == "number" then return nil end return Any end
anyMT.__call = function() return Any end
anyMT.__add = function() return 0 end
anyMT.__sub = function() return 0 end
anyMT.__mul = function() return 0 end
anyMT.__div = function() return 0 end
anyMT.__mod = function() return 0 end
anyMT.__unm = function() return 0 end
anyMT.__idiv = function() return 0 end
anyMT.__pow = function() return 0 end
anyMT.__concat = function(a, b) return (type(a) == "string" and a or "") .. (type(b) == "string" and b or "") end
anyMT.__len = function() return 0 end
anyMT.__lt = function() return false end
anyMT.__le = function() return false end
anyMT.__eq = function() return false end
anyMT.__tostring = function() return "any" end
Any = setmetatable({}, anyMT)

------------------------------------------------------------------ constants
local CONST_ME = {NONE=0,DRAWBLOOD=1,LOSEENERGY=2,POFF=3,BLOCKHIT=4,EXPLOSIONAREA=5,EXPLOSIONHIT=6,FIREAREA=7,YELLOW_RINGS=8,GREEN_RINGS=9,HITAREA=10,TELEPORT=11,ENERGYHIT=12,MAGIC_BLUE=13,MAGIC_RED=14,MAGIC_GREEN=15,HITBYFIRE=16,HITBYPOISON=17,MORTAREA=18,SOUND_GREEN=19,SOUND_RED=20,POISONAREA=21,SOUND_YELLOW=22,SOUND_PURPLE=23,SOUND_BLUE=24,SOUND_WHITE=25,BUBBLES=26,CRAPS=27,GIFT_WRAPS=28,FIREWORK_YELLOW=29,FIREWORK_RED=30,FIREWORK_BLUE=31,STUN=32,SLEEP=33,WATERCREATURE=34,GROUNDSHAKER=35,HEARTS=36,FIREATTACK=37,ENERGYAREA=38,SMALLCLOUDS=39,HOLYDAMAGE=40,BIGCLOUDS=41,ICEAREA=42,ICETORNADO=43,ICEATTACK=44,STONES=45,SMALLPLANTS=46,CARNIPHILA=47,PURPLEENERGY=48,YELLOWENERGY=49,HOLYAREA=50,BIGPLANTS=51,CAKE=52,GIANTICE=53,WATERSPLASH=54,PLANTATTACK=55,TUTORIALARROW=56,TUTORIALSQUARE=57,MIRRORHORIZONTAL=58,MIRRORVERTICAL=59,SKULLHORIZONTAL=60,SKULLVERTICAL=61,ASSASSIN=62,STEPSHORIZONTAL=63,BLOODYSTEPS=64,STEPSVERTICAL=65,YALAHARIGHOST=66,BATS=67,SMOKE=68,INSECTS=69,DRAGONHEAD=70,ORCSHAMAN=71,ORCSHAMAN_FIRE=72,THUNDER=73,FERUMBRAS=74,CONFETTI_HORIZONTAL=75,CONFETTI_VERTICAL=76,BLACKSMOKE=77,REDSMOKE=78,YELLOWSMOKE=79,GREENSMOKE=80,PURPLESMOKE=81,EARLY_THUNDER=82,RAGIAZ_BONECAPSULE=83,CRITICAL_DAMAGE=173,PLUNGING_FISH=175}
local CONST_ANI = {NONE=0,SPEAR=1,BOLT=2,ARROW=3,FIRE=4,ENERGY=5,POISONARROW=6,BURSTARROW=7,THROWINGSTAR=8,THROWINGKNIFE=9,SMALLSTONE=10,DEATH=11,LARGEROCK=12,SNOWBALL=13,POWERBOLT=14,POISON=15,INFERNALBOLT=16,HUNTINGSPEAR=17,ENCHANTEDSPEAR=18,REDSTAR=19,GREENSTAR=20,ROYALSPEAR=21,SNIPERARROW=22,ONYXARROW=23,PIERCINGBOLT=24,WHIRLWINDSWORD=25,WHIRLWINDAXE=26,WHIRLWINDCLUB=27,ETHEREALSPEAR=28,ICE=29,EARTH=30,HOLY=31,SUDDENDEATH=32,FLASHARROW=33,FLAMMINGARROW=34,SHIVERARROW=35,ENERGYBALL=36,SMALLICE=37,SMALLHOLY=38,SMALLEARTH=39,EARTHARROW=40,EXPLOSION=41,CAKE=42,TARSALARROW=43,VORTEXBOLT=44,PRISMATICBOLT=45,CRYSTALLINEARROW=46,DRILLBOLT=47,ENVENOMEDARROW=48,GLOOTHSPEAR=49,SIMPLEARROW=50,LEAFSTAR=51,DIAMONDARROW=52,SPECTRALBOLT=53,ROYALSTAR=54}
CONST_ANI.WEAPONTYPE = 254
for k, v in pairs(CONST_ME) do _G["CONST_ME_" .. k] = v end
for k, v in pairs(CONST_ANI) do _G["CONST_ANI_" .. k] = v end
NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
local nextConst = 1000
-- area shapes of data/lib/core/constants (TFS 1.4): tile counts by name, a square or a circle of the radius named
local AREA_DIM = {CIRCLE1X1 = {3, 3, 5}, CIRCLE2X2 = {5, 5, 13}, CIRCLE3X3 = {7, 7, 37}, CIRCLE5X5 = {11, 11, 97}, CIRCLE6X6 = {13, 13, 129},
	SQUAREWAVE5 = {5, 5, 25}, SQUAREWAVE6 = {7, 7, 49}, WAVE4 = {5, 5, 12}, WAVE6 = {7, 7, 20}, WAVE8 = {9, 9, 32}, BEAM1 = {1, 1, 1},
	BEAM5 = {1, 5, 5}, BEAM7 = {1, 7, 7}, BEAM8 = {1, 8, 8}, WALL = {1, 3, 3}, CROSS1X1 = {3, 3, 5}, CROSS5X5 = {11, 11, 21}, CROSS6X6 = {13, 13, 25}}
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
for _, n in ipairs({"Condition","Container","Outfit","Variant","Teleport","Party","Guild","House","Town","Group","Spell","NetworkMessage","ModalWindow","Waypoint","Item","ItemType","Tile","Vocation","DBResult","MonsterType","Loot","Mount","Resource"}) do rawset(_G, n, rawget(_G, n) or Any) end
-- the names of the combat parameters we care about get stable ids
COMBAT_PARAM_EFFECT = 7001; COMBAT_PARAM_DISTANCEEFFECT = 7002; COMBAT_PARAM_TYPE = 7003
VARIANT_NUMBER, VARIANT_POSITION, VARIANT_TARGETPOSITION, VARIANT_STRING = 1, 2, 3, 4

------------------------------------------------------------------ positions
local tileObj
local CASTER_POS, TARGET_POS = {x = 100, y = 100, z = 7}, {x = 100 + (tonumber(arg[5]) or 5), y = 100, z = 7}
local Pmt = {}
local function Position(x, y, z)
	if type(x) == "table" then x, y, z = x.x, x.y, x.z end
	return setmetatable({x = x or 0, y = y or 0, z = z or 7}, Pmt)
end
local function relT(p) return (p.x - TARGET_POS.x) .. "\t" .. (p.y - TARGET_POS.y) end
local function relC(p) return (p.x - CASTER_POS.x) .. "\t" .. (p.y - CASTER_POS.y) end
local delay = 0
local via = ""
Pmt.__index = {
	sendMagicEffect = function(self, id) rec("ME", id, relT(self), relC(self), delay, via) end,
	sendDistanceEffect = function(self, to, id) rec("ANI", id, relC(self), relC(to), relT(to), delay, via) end,
	getDistanceTo = function(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end,
	isSightClear = function() return true end,
	getTile = function() return tileObj end,
	getNextPosition = function(self, dir, steps) return self end,
	isWalkable = function() return true end,
	toString = function(self) return self.x .. "," .. self.y end,
	getZ = function(self) return self.z end,
	getX = function(self) return self.x end,
	getY = function(self) return self.y end,
}
Pmt.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
Pmt.__add = function(a, b) return Position(a.x + (b.x or 0), a.y + (b.y or 0), a.z + (b.z or 0)) end
Pmt.__sub = function(a, b) return Position(a.x - (b.x or 0), a.y - (b.y or 0), a.z - (b.z or 0)) end
Pmt.__tostring = function(self) return self.x .. "," .. self.y end
_G.Position = Position

------------------------------------------------------------------ creatures
local function makeCreature(id, pos, isPlayer)
	local c = {_id = id, _pos = pos}
	local voc = setmetatable({getId = function() return vocId end, getBase = function() return Any end, getName = function() return "voc" end}, {__index = function() return function() return Any end end})
	local methods = {
		getId = function() return id end, getName = function() return isPlayer and "Caster" or "Target" end,
		getPosition = function() return Position(pos) end,
		isPlayer = function() return isPlayer end, isMonster = function() return not isPlayer end, isCreature = function() return true end,
		isNpc = function() return false end, isItem = function() return false end, isTile = function() return false end,
		getLevel = function() return level end, getMagicLevel = function() return level end, getSkillLevel = function() return level end,
		getVocation = function() return voc end,
		getDirection = function() return EAST end,
		getHealth = function() return 5000 end, getMaxHealth = function() return 10000 end,
		getMana = function() return 5000 end, getMaxMana = function() return 10000 end,
		getTarget = function() return not isPlayer and nil or nil end,
		getStorageValue = function() return -1 end,
		getSpeed = function() return 200 end, getBaseSpeed = function() return 200 end,
		getSex = function() return 1 end,
		getParty = function() return nil end, getGuild = function() return nil end,
		getMaster = function() return nil end, getSummons = function() return {} end,
		getOutfit = function() return {lookType = 128} end,
		getSpectators = function() return {} end,
		getCondition = function() return nil end, hasCondition = function() return false end,
		isInGhostMode = function() return false end, isRemoved = function() return false end,
		getAccountId = function() return 1 end, getGuid = function() return 1 end,
		getItemCount = function() return 0 end, getSlotItem = function() return nil end,
		getCapacity = function() return 1000 end, getFreeCapacity = function() return 1000 end,
		getZone = function() return 0 end, getTile = function() return Any end,
		getSkull = function() return 0 end, getType = function() return Any end,
		canSee = function() return true end, canSeeCreature = function() return true end,
		sendCancelMessage = function(self, m) rec("CANCEL", tostring(m), (debug.traceback("",2):gsub("\n"," | "):sub(1,400))) end,
		say = function() return true end, sendTextMessage = function() return true end,
		getMaxSummons = function() return 5 end,
		getPlayer = function(self) if isPlayer then return self end return nil end,
		getMonster = function(self) if not isPlayer then return self end return nil end,
		getCreature = function(self) return self end,
		getHealthPercent = function() return 100 end,
		isPzLocked = function() return false end, isInPz = function() return false end,
		getPlayerBlocked = function() return false end, canAttack = function() return true end,
		isAttackable = function() return true end, isHostile = function() return true end,
		getFriendList = function() return {} end, getOnlinePlayers = function() return {} end,
		getStamina = function() return 2520 end, getExperience = function() return 1e6 end,
		getHealthMax = function() return 10000 end,
		getIp = function() return 1 end, getPremiumDays = function() return 100 end,
		getGroup = function() return setmetatable({getId = function() return 1 end, getAccess = function() return false end}, {__index = function() return function() return false end end}) end,
		getTown = function() return Any end,
		getFightingTargets = function() return {} end,
		getAttackedCreature = function() return nil end,
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
	getItems = function() return {} end, getGround = function() return nil end, isWalkable = function() return true end, getItemCount = function() return 0 end,
	getTopVisibleCreature = function() return nil end, getThingCount = function() return 0 end, getItemById = function() return nil end, queryAdd = function() return 0 end},
	{__index = function() return function() return nil end end})
function Tile() return tileObj end
function Item() return Any end
function ItemType() return Any end
function Vocation() return Any end

------------------------------------------------------------------ combat
local Cmt = {}
local function Combat()
	return setmetatable({params = {}, area = nil, callbacks = {}}, Cmt)
end
Cmt.__index = {
	setParameter = function(self, k, v) self.params[k] = v end,
	getParameter = function(self, k) return self.params[k] end,
	setArea = function(self, a) self.area = a end,
	setCallback = function(self, k, v) end,
	setFormula = function() end, addCondition = function() end, setOrigin = function() end,
	setCondition = function() end,
	execute = function(self, creature, variant)
		local a = self.area
		local cells = a and (a.cells or 1) or 1
		local w, h = a and a.w or 1, a and a.h or 1
		local e = self.params[COMBAT_PARAM_EFFECT]
		local d = self.params[COMBAT_PARAM_DISTANCEEFFECT]
		rec("COMBAT", e or 0, d or 0, cells, w, h, a and a.name or "single", delay, via)
		-- the engine sends the impact effect on every tile of the area (centre only is shown here): one ME at the target
		if e and e ~= 0 and e ~= CONST_ME_NONE then rec("ME", e, "0\t0", "5\t0", delay, "combat_area_" .. cells) end
		if d and d ~= 0 and d ~= CONST_ANI_NONE then rec("ANI", d, "0\t0", "5\t0", "0\t0", delay, "combat_distance") end
		return true
	end,
}
_G.Combat = Combat
function createCombatArea(t, ext)
	if type(t) == "table" and t._area then return t end
	local cells, h, w = 0, #t, 0
	for _, row in ipairs(t) do w = math.max(w, #row); for _, v in ipairs(row) do if v ~= 0 then cells = cells + 1 end end end
	return {_area = true, w = w, h = h, cells = cells, name = "custom"}
end
function doSendMagicEffect(pos, id) Position(pos):sendMagicEffect(id) end
function doSendDistanceShoot(from, to, id) Position(from):sendDistanceEffect(Position(to), id) end
function doAreaCombat() return true end
function doTargetCombat() return true end
function doAreaCombatHealth(cid, ct, pos, area, mn, mx, e)
	local c = (type(area) == "table" and area.cells) or 1
	rec("COMBAT", e or 0, 0, c, area and area.w or 1, area and area.h or 1, area and area.name or "single", delay, "doAreaCombatHealth")
	if e and e ~= 0 then rec("ME", e, "0\t0", "5\t0", delay, "combat_area_" .. c) end
	return true
end
doCombat = function() return true end

-- scheduling: run at once, remember the delay so a later effect is told apart
local depth = 0
function addEvent(fn, ms, ...)
	if depth > 6 or type(fn) ~= "function" then return 0 end
	local old = delay
	delay = delay + (tonumber(ms) or 0)
	depth = depth + 1
	pcall(fn, ...)
	depth = depth - 1
	delay = old
	return 1
end
function stopEvent() end
os.time = os.time
Game = setmetatable({}, {__index = function(t, k)
	return function() return nil end
end})
function Game.getSpectators() return {} end
function Game.createMonster() return nil end
function Game.getWorldTime() return 0 end

-- the cast context of data/spells/chaos/_supports.lua (not loaded: it wraps the engine's script loading)
ChaosSupportsSpell = {wrapped = 0, cast = function() return 1, spellId end, rawAddEvent = addEvent}
-- the real constants file (Chaos.classes, storages, opcodes); a permissive stand-in when it does not load
local okc, errc = pcall(dofile, "data/scripts/chaos/chaos_constants.lua")
if not okc or type(rawget(_G, "Chaos")) ~= "table" then
	rec("NOTE", "chaos_constants did not load: " .. tostring(errc):sub(1, 120))
	Chaos = setmetatable({classes = {baseOf = setmetatable({}, {__index = function(t, k) return k end})}}, {__index = function(t, k) return Any end})
end
function playSound() end
function doPlaySound() end

------------------------------------------------------------------ run
local base = "data/spells/scripts/"
pcall(dofile, base .. "chaos/_monk.lua")
if rawget(_G, "MonkSpell") then MonkSpell.finisher = function() return 5 end end
local ok, err = pcall(dofile, base .. script)
if not ok then rec("LOADFAIL", tostring(err):sub(1, 160)) end
local f = rawget(_G, "onCastSpell")
if f then
	local variant = {number = 2, type = VARIANT_NUMBER}
	-- spells without a target: variant by position
	local ok2, res = xpcall(f, function(e) return debug.traceback(tostring(e), 2):sub(1, 220) end, caster, variant, false)
	rec("RESULT", tostring(ok2), tostring(res):gsub("\n", " | "):sub(1, 200))
	-- second run with a self variant (spells that need no target or fail on the first call)
	local fx1 = 0
	for _, l in ipairs(out) do if l:match('^ME') or l:match('^ANI') then fx1 = fx1 + 1 end end
	if fx1 == 0 then
		local ok3, res3 = xpcall(f, function(e) return debug.traceback(tostring(e), 2):sub(1, 220) end, caster, {number = 0, type = VARIANT_POSITION, x = 105, y = 100, z = 7}, false)
		rec("RESULT2", tostring(ok3), tostring(res3):gsub("\n", " | "):sub(1, 200))
	end
else
	rec("NOCAST")
end
print(table.concat(out, "\n"))
