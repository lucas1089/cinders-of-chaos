-- Run from the server/ folder: luajit tests/opcode_fuzz_test.lua (and lua5.3; CI runs both). Mock of the engine API.
-- Protocol fuzzer: loads every script under data/scripts against a mocked engine and feeds every extended opcode
-- handler (each onExtendedOpcode registered), under a fixed seed:
--   * malformed, truncated and non-JSON buffers, deep nesting, huge strings and arrays
--   * every action the module knows plus unknown ones, with every field it reads missing or of the wrong type
--     (negative, zero, fractional, NaN, +-inf, 2^53, huge strings, arrays, objects, booleans)
--   * database rows that belong to another character (ids of things the player does not own)
--   * repeated rapid calls with the clock frozen, and calls after logout and after death
-- It checks that no handler (or anything it schedules with addEvent) raises a Lua error, that the player is granted
-- nothing (items, gold, bank, coins, experience, outfits, ...), that no answer is over the 8192-byte extended opcode
-- limit, that no client string reaches SQL unescaped, that rate limited actions stay limited, and that every handler
-- answers on the opcode chaos_constants.lua names (no two modules on one opcode).
-- Every failure is listed with the payload that found it (one per handler and place). FUZZ_VERBOSE=1 also lists the
-- actions and fields found per handler and the engine calls the mock does not know.

local VERBOSE = os.getenv("FUZZ_VERBOSE") == "1"
local realPrint = print
local checks = 0
local failures, failureSeen = {}, {}
-- a failure is kept once per (kind, handler, where): the same bug found by many payloads is one entry
local function failure(kind, handler, where, detail)
	local key = kind .. "|" .. handler .. "|" .. tostring(where)
	if failureSeen[key] then
		return
	end
	failureSeen[key] = true
	if type(detail) == "function" then
		detail = detail()
	end
	failures[#failures + 1] = string.format("[%s] %s: %s\n      %s", kind, handler, tostring(where), detail)
end
local function check(cond, kind, handler, where, detail)
	checks = checks + 1
	if not cond then
		failure(kind, handler, where, detail)
	end
end

-- ---------------------------------------------------------------- fixed seed (Park-Miller: the same sequence in
-- LuaJIT and Lua 5.3, every product is exact in a double)
local seed = 20261013
local function rnd(n)
	seed = (seed * 16807) % 2147483647
	return seed % n + 1
end

-- ---------------------------------------------------------------- JSON, as the base server's json.lua behaves:
-- decode errors on anything malformed (Chaos.decode catches it), null is nil, numbers go through tonumber (1e999 is
-- inf); encode errors on NaN / inf, sparse arrays, mixed keys, cycles and functions
local json = {}
do
	local escapes = {['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t"}
	local function utf8char(c)
		if c < 0x80 then
			return string.char(c)
		elseif c < 0x800 then
			return string.char(0xC0 + math.floor(c / 64), 0x80 + c % 64)
		end
		return string.char(0xE0 + math.floor(c / 4096), 0x80 + math.floor(c / 64) % 64, 0x80 + c % 64)
	end
	local function fail(i, msg)
		error(string.format("%s at char %d", msg, i), 0)
	end
	local function skip(s, i)
		local _, e = s:find("^[ \n\r\t]*", i)
		return e + 1
	end
	local function str(s, i)
		local out, j = {}, i + 1
		while true do
			local k = s:find('["\\%c]', j)
			if not k then
				fail(i, "expected closing quote for string")
			end
			out[#out + 1] = s:sub(j, k - 1)
			local c = s:sub(k, k)
			if c == '"' then
				return table.concat(out), k + 1
			elseif c == "\\" then
				local e = s:sub(k + 1, k + 1)
				if e == "u" then
					local hex = s:match("^%x%x%x%x", k + 2)
					if not hex then
						fail(k, "invalid unicode escape in string")
					end
					out[#out + 1] = utf8char(tonumber(hex, 16))
					j = k + 6
				elseif escapes[e] then
					out[#out + 1] = escapes[e]
					j = k + 2
				else
					fail(k, "invalid escape char '" .. e .. "' in string")
				end
			else
				fail(k, "control character in string")
			end
		end
	end
	local value
	value = function(s, i)
		i = skip(s, i)
		local c = s:sub(i, i)
		if c == "{" then
			local t = {}
			i = skip(s, i + 1)
			if s:sub(i, i) == "}" then
				return t, i + 1
			end
			while true do
				i = skip(s, i)
				if s:sub(i, i) ~= '"' then
					fail(i, "expected string for key")
				end
				local k
				k, i = str(s, i)
				i = skip(s, i)
				if s:sub(i, i) ~= ":" then
					fail(i, "expected ':' after key")
				end
				t[k], i = value(s, i + 1)
				i = skip(s, i)
				local d = s:sub(i, i)
				i = i + 1
				if d == "}" then
					return t, i
				elseif d ~= "," then
					fail(i, "expected '}' or ','")
				end
			end
		elseif c == "[" then
			local t, n = {}, 1
			i = skip(s, i + 1)
			if s:sub(i, i) == "]" then
				return t, i + 1
			end
			while true do
				t[n], i = value(s, i)
				n = n + 1
				i = skip(s, i)
				local d = s:sub(i, i)
				i = i + 1
				if d == "]" then
					return t, i
				elseif d ~= "," then
					fail(i, "expected ']' or ','")
				end
			end
		elseif c == '"' then
			return str(s, i)
		end
		local lit = s:match("^[^ \n\r\t,%]}]+", i)
		if not lit then
			fail(i, "unexpected character '" .. c .. "'")
		elseif lit == "true" then
			return true, i + 4
		elseif lit == "false" then
			return false, i + 5
		elseif lit == "null" then
			return nil, i + 4
		end
		local n = tonumber(lit)
		if not n then
			fail(i, "invalid number '" .. lit .. "'")
		end
		return n, i + #lit
	end
	json.decodeString = function(s)
		if type(s) ~= "string" then
			error("expected argument of type string, got " .. type(s))
		end
		local v, i = value(s, 1)
		i = skip(s, i)
		if i <= #s then
			fail(i, "trailing garbage")
		end
		return v
	end

	local escOut = {['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r",
		["\t"] = "\\t"}
	local function escChar(c)
		return escOut[c] or string.format("\\u%04x", c:byte())
	end
	local out, n, stack -- the answer being built
	local huge, format, concat = math.huge, string.format, table.concat
	local encode
	encode = function(v)
		local t = type(v)
		if t == "string" then
			if v:find('[%c"\\]') then
				v = v:gsub('[%c"\\]', escChar)
			end
			n = n + 1
			out[n] = '"' .. v .. '"'
		elseif t == "number" then
			if v ~= v or v == huge or v == -huge then
				error("unexpected number value '" .. tostring(v) .. "'")
			end
			n = n + 1
			out[n] = format("%.14g", v)
		elseif t == "table" then
			if stack[v] then
				error("circular reference")
			end
			stack[v] = true
			if rawget(v, 1) ~= nil or next(v) == nil then
				local count = 0
				for k in pairs(v) do
					if type(k) ~= "number" then
						error("invalid table: mixed or invalid key types")
					end
					count = count + 1
				end
				if count ~= #v then
					error("invalid table: sparse array")
				end
				n = n + 1
				out[n] = "["
				for i = 1, count do
					if i > 1 then
						n = n + 1
						out[n] = ","
					end
					encode(v[i])
				end
				n = n + 1
				out[n] = "]"
			else
				n = n + 1
				out[n] = "{"
				local first = true
				for k, x in pairs(v) do
					if type(k) ~= "string" then
						error("invalid table: mixed or invalid key types")
					end
					if not first then
						n = n + 1
						out[n] = ","
					end
					first = false
					encode(k)
					n = n + 1
					out[n] = ":"
					encode(x)
				end
				n = n + 1
				out[n] = "}"
			end
			stack[v] = nil
		elseif v == nil then
			n = n + 1
			out[n] = "null"
		elseif t == "boolean" then
			n = n + 1
			out[n] = v and "true" or "false"
		else
			error("unexpected type '" .. t .. "'")
		end
	end
	json.encode = function(v)
		local saved = {out, n, stack} -- encode can be re-entered from a __tostring or a nested call
		out, n, stack = {}, 0, {}
		local ok, err = pcall(encode, v)
		local result = ok and concat(out, "", 1, n) or nil
		out, n, stack = saved[1], saved[2], saved[3]
		if not ok then
			error("json.lua: " .. tostring(err), 2)
		end
		return result
	end
end
rawset(_G, "json", {encode = json.encode, decode = json.decodeString})

-- ---------------------------------------------------------------- engine mock
-- Upper-case globals (engine enums such as CONST_SLOT_BACKPACK or RETURNVALUE_NOERROR) get one number each; the
-- engine classes nobody defines below (Condition, Combat, Spell, GlobalEvent, ...) are callable tables whose objects
-- accept any method. Every method the mock does not know returns nil and is counted (FUZZ_VERBOSE lists them).
local missing = {}
local function noted(kind, name)
	local k = kind .. ":" .. tostring(name)
	if not missing[k] and os.getenv("FUZZ_TRACE") == k then
		realPrint(debug.traceback(k, 2))
	end
	missing[k] = (missing[k] or 0) + 1
	return function() return nil end
end
local function object(kind, fields)
	return setmetatable(fields or {}, {__index = function(_, k) return noted(kind, k) end})
end
local function class(kind, ctor)
	return setmetatable({}, {__call = function(_, ...)
		if ctor then
			return ctor(...)
		end
		return object(kind)
	end})
end
local enumN = 1000
local baseTables = {DUNGEON_SYSTEM = true, GM_HANDBOOK = true, MAP_GUIDE = true} -- base server tables: absent here
setmetatable(_G, {__index = function(t, k)
	if type(k) ~= "string" then
		return nil
	end
	if k:match("^[A-Z][A-Z0-9_]+$") and not baseTables[k] then
		enumN = enumN + 1
		rawset(t, k, enumN)
		return enumN
	end
	if k:match("^[A-Z]") and not k:match("^Chaos") then
		local c = class(k)
		rawset(t, k, c)
		return c
	end
	return nil
end})
RETURNVALUE_NOERROR = 0
CONST_SLOT_FIRST, CONST_SLOT_LAST = 1, 10
for i, n in ipairs({"HEAD", "NECKLACE", "BACKPACK", "ARMOR", "RIGHT", "LEFT", "LEGS", "FEET", "RING", "AMMO"}) do
	_G["CONST_SLOT_" .. n] = i
end
TALKTYPE_MONSTER_SAY, MESSAGE_STATUS_SMALL, MESSAGE_INFO_DESCR = 36, 21, 22
SKULL_NONE, SKULL_WHITE, SKULL_RED, SKULL_BLACK = 0, 3, 4, 5
ACCOUNT_TYPE_NORMAL, ACCOUNT_TYPE_GOD = 1, 5
WORLD_TYPE_NO_PVP, WORLD_TYPE_PVP, WORLD_TYPE_PVP_ENFORCED = 1, 2, 3
GAME_STATE_NORMAL = 1

function createCombatArea() return {} end
function createConditionObject() return object("Condition") end

local T0 = 1790000000
local clock = T0 * 1000
local realTime = os.time
os.time = function(t)
	if t then
		return realTime(t)
	end
	return math.floor(clock / 1000)
end
os.mtime = function() return clock end

-- what the player gets: every call here is a grant (the fuzz player owns nothing and can afford nothing)
local grants = {}
local function granted(what, ...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	grants[#grants + 1] = what .. "(" .. table.concat(parts, ", ") .. ")"
end
local badCalls = {} -- engine calls with arguments the C++ side would mangle (NaN / inf / fractions as integers)
local function finiteInt(n)
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge and n == math.floor(n)
end

local itemTypes = {}
local function itemType(id)
	local n = tonumber(id)
	local valid = finiteInt(n) and n >= 100 and n <= 40000
	local key = valid and n or 0
	if itemTypes[key] then
		return itemTypes[key]
	end
	local it = object("ItemType", {
		getId = function() return key end, getClientId = function() return key end,
		getName = function() return valid and ("item " .. key) or "" end,
		getPluralName = function() return valid and ("items " .. key) or "" end,
		getArticle = function() return "a" end, getDescription = function() return "" end,
		isStackable = function() return false end, isContainer = function() return false end,
		isPickupable = function() return valid end, isMovable = function() return valid end,
		isRune = function() return false end, isFluidContainer = function() return false end,
		isCorpse = function() return false end, isDoor = function() return false end,
		getWeaponType = function() return 0 end, getSlotPosition = function() return 0 end,
		getWeight = function() return 100 end, getCapacity = function() return 0 end,
		getAttack = function() return 0 end, getDefense = function() return 0 end, getArmor = function() return 0 end,
		getExtraDefense = function() return 0 end, getHitChance = function() return 0 end,
		getShootRange = function() return 0 end, getCharges = function() return 0 end,
		getDuration = function() return 0 end, getLevelDoor = function() return 0 end,
		getVocationString = function() return "" end, getMinReqLevel = function() return 0 end,
		getMinReqMagicLevel = function() return 0 end, getTransformEquipId = function() return 0 end,
		getTransformDeEquipId = function() return 0 end, getDecayId = function() return 0 end,
		getElementType = function() return 0 end, getElementDamage = function() return 0 end,
		getAbilities = function() return {} end, hasSubType = function() return false end,
		getType = function() return 0 end, getGroup = function() return 0 end, isWritable = function() return false end,
		isReadable = function() return false end, isBlocking = function() return false end,
		isGroundTile = function() return false end, isMagicField = function() return false end,
		isUseable = function() return false end, getWorth = function() return 0 end,
	})
	itemTypes[key] = it
	return it
end
ItemType = class("ItemType", itemType)

local uid = 70000
local makeContainer, makeItem
local itemMethods = {}
local itemMt = {__index = function(_, k) return itemMethods[k] or noted("Item", k) end}
local I = itemMethods
function I:isItem() return true end
function I:isContainer() return self.items ~= nil end
function I:isCreature() return false end
function I:isPlayer() return false end
function I:isTeleport() return false end
function I:getId() return self.id end
function I:getUniqueId() return self.uid end
function I:getCount() return self.count end
function I:getSubType() return self.count end
function I:getCharges() return 0 end
function I:getActionId() return 0 end
function I:getType() return itemType(self.id) end
function I:getName() return itemType(self.id):getName() end
function I:getArticle() return "a" end
function I:getPluralName() return itemType(self.id):getPluralName() end
function I:getWeight() return 100 end
function I:getWorth() return 0 end
function I:hasAttribute(k) return self.attrs[k] ~= nil end
function I:getAttribute(k) return self.attrs[k] end
function I:setAttribute(k, v) self.attrs[k] = v; return true end
function I:removeAttribute(k) self.attrs[k] = nil; return true end
function I:getCustomAttribute(k) return self.custom[k] end
function I:setCustomAttribute(k, v) self.custom[k] = v; return true end
function I:removeCustomAttribute(k) self.custom[k] = nil; return true end
function I:getClientAttributes() return {} end
function I:getDescription() return "" end
function I:getPosition() return Position(1000, 1000, 7) end
function I:getTile() return nil end
function I:getParent() return nil end
function I:getTopParent() return nil end
function I:remove() self.removed = true; return true end
function I:moveTo() return true end
function I:clone() return makeItem(self.id, self.count) end
function I:transform() return true end
function I:decay() return true end
function I:setActionId() return true end
function I:split() return nil end
function I:getRarity() return 0 end
-- containers (all empty)
function I:getItems() return {} end
function I:getSize() return 0 end
function I:getCapacity() return 20 end
function I:getEmptySlots() return 20 end
function I:getItem() return nil end
function I:getItemHoldingCount() return 0 end
function I:getItemCountById() return 0 end
function I:getContentDescription() return "nothing" end
function I:hasItem() return false end
function I:addItem(id, count)
	if self.owner then
		granted(self.kind .. ":addItem", id, count)
	end
	return makeItem(id, count, self.owner)
end
function I:addItemEx(item)
	if self.owner then
		granted(self.kind .. ":addItemEx", item and item.id, item and item.count)
	end
	return RETURNVALUE_NOERROR
end
makeItem = function(id, count, owner)
	uid = uid + 1
	return setmetatable({id = tonumber(id) or 0, count = tonumber(count) or 1, owner = owner, uid = uid, attrs = {},
		custom = {}}, itemMt)
end
Item = class("Item", function() return nil end)
Container = class("Container", function() return nil end)
Teleport = class("Teleport", function() return nil end)

makeContainer = function(owner, kind)
	local c = makeItem(1988, 1, owner)
	c.items, c.kind = {}, kind
	return c
end

local positionMt
Position = setmetatable({}, {__call = function(_, x, y, z, s)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return setmetatable({x = x or 0, y = y or 0, z = z or 0, stackpos = s}, positionMt)
end})
positionMt = {
	__index = function(_, k)
		local m = rawget(Position, k)
		if m then
			return m
		end
		return noted("Position", k)
	end,
	__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end,
	__add = function(a, b) return Position(a.x + b.x, a.y + b.y, a.z + (b.z or 0)) end,
	__sub = function(a, b) return Position(a.x - b.x, a.y - b.y, a.z - (b.z or 0)) end,
	__tostring = function(p) return string.format("(%d, %d, %d)", p.x, p.y, p.z) end,
	__concat = function(a, b) return tostring(a) .. tostring(b) end,
}
function Position.getDistance(a, b) return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y)) end
function Position.getTile(p) return Tile(p) end
function Position.getPosition(p) return p end
function Position.sendMagicEffect() return true end
function Position.sendDistanceEffect() return true end
function Position.isSightClear() return true end
function Position.isInRange(p, a, b)
	return p.x >= a.x and p.x <= b.x and p.y >= a.y and p.y <= b.y and p.z >= a.z and p.z <= b.z
end
function Position.getNextPosition(p) return p end
function Position.moveUpstairs(p) return p end

local tileMethods = {
	getPosition = function(t) return Position(t.pos) end, getHouse = function() return nil end,
	getItems = function() return {} end, getItemCount = function() return 0 end,
	getThingCount = function() return 0 end, getThing = function() return nil end,
	getCreatures = function() return {} end, getCreatureCount = function() return 0 end,
	getTopCreature = function() return nil end, getTopVisibleCreature = function() return nil end,
	getTopTopItem = function() return nil end, getTopDownItem = function() return nil end,
	getItemById = function() return nil end, getItemByType = function() return nil end,
	getFieldItem = function() return nil end, getGround = function() return nil end,
	hasFlag = function() return false end, hasProperty = function() return false end,
	isWalkable = function() return true end, isHouse = function() return false end,
	isPz = function() return false end, getZone = function() return {} end,
	queryAdd = function() return RETURNVALUE_NOERROR end,
}
local tileMt = {__index = function(_, k) return tileMethods[k] or noted("Tile", k) end}
local function makeTile(pos)
	return setmetatable({pos = pos}, tileMt)
end
Tile = class("Tile", function(x, y, z)
	if type(x) == "table" then
		return makeTile(x)
	end
	return makeTile(Position(x, y, z))
end)

local vocation = object("Vocation", {
	getId = function() return 1 end, getClientId = function() return 1 end, getName = function() return "Sorcerer" end,
	getDescription = function() return "a sorcerer" end, getBase = function(self) return self end,
	getPromotion = function() return nil end, getDemotion = function() return nil end,
	getBaseSpeed = function() return 220 end, getCapacityGain = function() return 10 end,
	getHealthGain = function() return 5 end, getManaGain = function() return 30 end,
	getRequiredSkillTries = function() return 50 end, getRequiredManaSpent = function() return 1600 end,
	allowsPvp = function() return true end, getAttackSpeed = function() return 2000 end,
})
Vocation = class("Vocation", function() return vocation end)
local group = object("Group", {
	getId = function() return 1 end, getName = function() return "Player" end, getAccess = function() return false end,
	hasFlag = function() return false end, getMaxDepotItems = function() return 2000 end,
	getMaxVipEntries = function() return 100 end, hasCustomFlag = function() return false end,
})
Group = class("Group", function() return group end)
local town = object("Town", {
	getId = function() return 1 end, getName = function() return "Ashford" end,
	getTemplePosition = function() return Position(1000, 1000, 7) end,
})
Town = class("Town", function() return town end)

-- the players: the fuzzer (guid 7777, account 8888) and one other character online
local GUID, ACCOUNT, NAME = 7777, 8888, "Fuzzer"
local online = {}
local players = {}
local makePlayer
Player = setmetatable({}, {__call = function(_, x)
	if type(x) == "table" then
		return (x.isPlayer and x:isPlayer() and online[x.cid]) and x or nil
	end
	for _, p in pairs(online) do
		if p.cid == x or p.name == x or (type(x) == "string" and p.name:lower() == x:lower()) then
			return p
		end
	end
	return nil
end})
Creature = setmetatable({}, {__call = function(_, x)
	if type(x) == "table" then
		return x
	end
	return Player(x)
end})
Monster = class("Monster", function() return nil end)
Npc = class("Npc", function() return nil end)
Party = class("Party", function() return nil end)
Guild = class("Guild", function() return nil end)
House = class("House", function() return nil end)
MonsterType = class("MonsterType", function() return nil end)

local playerMt = {__index = function(self, k)
	local m = rawget(Player, k)
	if m ~= nil then
		return m
	end
	m = rawget(Creature, k)
	if m ~= nil then
		return m
	end
	if k == "x" or k == "y" or k == "z" then
		-- a player handed to code that wants a position (the engine's userdata has no .x / .y / .z: nil)
		local at = debug.traceback("", 2):match("(data/[%w_/%.]+:%d+)")
		badCalls[#badCalls + 1] = "player used as a position (." .. k .. ") at " .. tostring(at)
		return nil
	end
	return noted("Player", k)
end}

makePlayer = function(cid, guid, account, name)
	local p = setmetatable({cid = cid, guid = guid, account = account, name = name, storage = {}, bank = 0,
		health = 185, maxHealth = 185, mana = 35, maxMana = 35, level = 8, pos = Position(1000, 1000, 7),
		events = {}}, playerMt)
	local own = p
	p.inbox = makeContainer(own, "inbox")
	p.depot = makeContainer(own, "depot")
	p.storeInbox = makeContainer(own, "storeInbox")
	p.backpack = makeContainer(own, "backpack")
	return p
end
local P = {}
function P:isPlayer() return true end
function P:isMonster() return false end
function P:isNpc() return false end
function P:isCreature() return true end
function P:isItem() return false end
function P:isRemoved() return online[self.cid] == nil end
function P:getId() return self.cid end
function P:getGuid() return self.guid end
function P:getAccountId() return self.account end
function P:getName() return self.name end
function P:getAccountType() return ACCOUNT_TYPE_NORMAL end
function P:getGroup() return group end
function P:getVocation() return vocation end
function P:getTown() return town end
function P:getLevel() return self.level end
function P:getExperience() return 4200 end
function P:getMagicLevel() return 0 end
function P:getBaseMagicLevel() return 0 end
function P:getSkillLevel() return 10 end
function P:getEffectiveSkillLevel() return 10 end
function P:getSkillTries() return 0 end
function P:getManaSpent() return 0 end
function P:getHealth() return self.health end
function P:getMaxHealth() return self.maxHealth end
function P:getMana() return self.mana end
function P:getMaxMana() return self.maxMana end
function P:getSoul() return 0 end
function P:getCapacity() return 40000 end
function P:getFreeCapacity() return 40000 end
function P:getStamina() return 2520 end
function P:getSex() return 0 end
function P:getIp() return 16777343 end
function P:isPremium() return false end
function P:getPremiumDays() return 0 end
function P:getPosition() return Position(self.pos) end
function P:getDirection() return 0 end
function P:getSpeed() return 220 end
function P:getBaseSpeed() return 220 end
function P:getOutfit() return {lookType = 128, lookHead = 0, lookBody = 0, lookLegs = 0, lookFeet = 0, lookAddons = 0,
	lookMount = 0} end
function P:getSkull() return SKULL_NONE end
function P:getSkullTime() return 0 end
function P:getParty() return nil end
function P:getGuild() return nil end
function P:getGuildLevel() return 0 end
function P:getGuildNick() return "" end
function P:getHouse() return nil end
function P:getTarget() return nil end
function P:getSummons() return {} end
function P:getMaster() return nil end
function P:getCondition() return nil end
function P:hasCondition() return false end
function P:isPzLocked() return false end
function P:isInGhostMode() return false end
function P:canSee() return true end
function P:getTile() return Tile(self.pos) end
function P:getFightMode() return 1 end
function P:getLastLoginSaved() return T0 - 3600 end
function P:getLastLogout() return T0 - 7200 end
function P:getEnergyShield() return 0 end
function P:getMaxEnergyShield() return 0 end
function P:getEnergyShieldRecharge() return 0 end
function P:getCharacterStat() return 0 end
function P:getClientGuard() return nil end
function P:isUsingOtClient() return true end
function P:getClient() return {version = 1098, os = 2} end
function P:hasOutfit() return false end
function P:hasMount() return false end
function P:hasBlessing() return false end
function P:hasLearnedSpell() return false end
function P:getInstantSpells() return {} end
function P:getContainerById() return nil end
function P:getContainerIndex() return nil end
function P:getSlotItem(slot)
	if slot == CONST_SLOT_BACKPACK then
		return self.backpack
	end
	return nil
end
function P:getInbox() return self.inbox end
function P:getStoreInbox() return self.storeInbox end
function P:getDepotChest() return self.depot end
function P:getDepotLocker() return self.depot end
function P:getItemCount() return 0 end
function P:getItemById() return nil end
function P:getMoney() return 0 end
function P:getTotalMoney() return 0 end
function P:getBankBalance() return self.bank end
function P:getStorageValue(k)
	if not finiteInt(k) then
		badCalls[#badCalls + 1] = "getStorageValue(" .. tostring(k) .. ")"
	end
	local v = self.storage[k]
	return v == nil and -1 or v
end
function P:setStorageValue(k, v)
	if not finiteInt(k) or (v ~= nil and not finiteInt(v)) then
		badCalls[#badCalls + 1] = "setStorageValue(" .. tostring(k) .. ", " .. tostring(v) .. ")"
	end
	self.storage[k] = v
	return true
end
-- what costs something: the fuzz player has nothing, so it always fails; a negative or broken amount is recorded
local function cost(what, n)
	if not finiteInt(n) or n < 0 then
		badCalls[#badCalls + 1] = what .. "(" .. tostring(n) .. ")"
	end
	return n == 0
end
function P:removeMoney(n) return cost("removeMoney", n) end
function P:removeTotalMoney(n) return cost("removeTotalMoney", n) end
function P:removeItem(id, n) return cost("removeItem", n or 1) and false end
function P:removeExperience() return true end
function P:removeMana() return true end
function P:setBankBalance(n)
	if not finiteInt(n) or n < 0 then
		badCalls[#badCalls + 1] = "setBankBalance(" .. tostring(n) .. ")"
	end
	if type(n) ~= "number" or n ~= n or n > self.bank then
		granted("setBankBalance", self.bank, n)
	end
	self.bank = n
	return true
end
function P:addItem(id, count) granted("addItem", id, count); return makeItem(id, count, self) end
function P:addItemEx(item) granted("addItemEx", item and item.id, item and item.count); return RETURNVALUE_NOERROR end
function P:addMoney(n) granted("addMoney", n); return true end
function P:addExperience(n) if type(n) ~= "number" or n ~= n or n > 0 then granted("addExperience", n) end; return true end
for _, name in ipairs({"addPremiumDays", "addOutfit", "addOutfitAddon", "addMount", "addBlessing", "addSkillTries",
	"addManaSpent", "addAura", "addWings", "addShader", "setVocation", "addSoul", "setMaxHealth", "setMaxMana",
	"setMaxEnergyShield", "setCapacity"}) do
	P[name] = function(_, ...) granted(name, ...); return true end
end
for _, name in ipairs({"sendTextMessage", "sendCancelMessage", "popupFYI", "showTextDialog", "say", "registerEvent",
	"unregisterEvent", "teleportTo", "addCondition", "removeCondition", "save", "setSkull", "setSkullTime",
	"changeSpeed", "setTarget", "setOutfit", "addHealth", "addMana", "setHealth", "setStamina", "setSex",
	"setEnergyShield", "setEnergyShieldRecharge", "setCharacterStat", "removeAura", "feed", "clientGuardFail",
	"sendChannelMessage", "sendPrivateMessage", "setGhostMode", "setDirection", "setMovementBlocked", "remove",
	"getStorageValueByName", "openChannel", "sendTutorial", "learnSpell", "forgetSpell", "setFollowCreature",
	"setDropLoot", "setSkillLoss", "removePremiumDays", "removeOutfit", "removeOutfitAddon", "removeMount",
	"removeBlessing", "setGuildNick", "setGuildLevel", "setGuild", "sendHouseWindow", "addAttachedEffect"}) do
	P[name] = function() return true end
end
P.getStorageValueByName = function() return -1 end
P.remove = nil
for k, v in pairs(P) do
	Player[k] = v
end

local fuzzer = makePlayer(0x10000001, GUID, ACCOUNT, NAME)
local other = makePlayer(0x10000002, 4242, 4343, "Bystander")
online[fuzzer.cid], online[other.cid] = fuzzer, other
players = {fuzzer, other}

-- Game
local gstorage = {}
Game = {
	getPlayers = function()
		local list = {}
		for _, p in ipairs(players) do
			if online[p.cid] then
				list[#list + 1] = p
			end
		end
		return list
	end,
	getPlayerCount = function() return 2 end,
	getMonsterCount = function() return 0 end,
	getNpcCount = function() return 0 end,
	getPlayerByGUID = function(g)
		for _, p in ipairs(players) do
			if p.guid == g and online[p.cid] then
				return p
			end
		end
		return nil
	end,
	getStorageValue = function(k) return gstorage[k] end,
	setStorageValue = function(k, v) gstorage[k] = v end,
	getSpectators = function() return {} end,
	getTowns = function() return {town} end,
	getHouses = function() return {} end,
	getWorldType = function() return WORLD_TYPE_PVP end,
	getExperienceStage = function() return 1 end,
	getGameState = function() return GAME_STATE_NORMAL end,
	getReturnMessage = function() return "Sorry, not possible." end,
	getMonsterTypes = function() return {} end,
	broadcastMessage = function() return true end,
	createItem = function(id, count, pos)
		if pos then
			granted("Game.createItem on the map", id, count)
		end
		return makeItem(id, count)
	end,
	createItemWithRarity = function(id, count) return makeItem(id, count) end,
	createContainer = function(id) return makeContainer(nil, "loose") end,
	createMonster = function() return nil end,
	createNpc = function() return nil end,
	createTile = function(p) return makeTile(p) end,
	createMonsterType = function() return nil end,
	startRaid = function() return false end,
	setGameState = function() end,
	setWorldTime = function() end,
	setSpawnIntervalPercent = function() end,
	setSpawnIntervalZones = function() end,
	reload = function() end,
	getClientVersion = function() return {min = 1098, max = 1098, string = "10.98"} end,
}
setmetatable(Game, {__index = function(_, k) return noted("Game", k) end})

configManager = object("configManager", {
	getNumber = function() return 0 end, getBoolean = function() return false end,
	getString = function() return "" end,
})
configKeys = setmetatable({}, {__index = function(t, k) return k end})

-- database: nothing is stored for the fuzzer; in "foreign" mode every other SELECT finds one row that belongs to
-- another character (owner ids 999, a name that is not the fuzzer's)
local dbMode = "empty"
local queries = {}
local MARK = "fz'q" -- planted in client strings: it must reach SQL only escaped
local function mine(q)
	return q:find(tostring(GUID), 1, true) or q:find(tostring(ACCOUNT), 1, true) or q:find(NAME, 1, true)
end
local results = {}
local nextResult = 0
db = {
	escapeString = function(s)
		s = tostring(s)
		return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("%z", "\\0") .. "'"
	end,
	escapeBlob = function(s, n) return "'" .. tostring(s):gsub("'", "\\'") .. "'" end,
	query = function(q) queries[#queries + 1] = q; return true end,
	asyncQuery = function(q) queries[#queries + 1] = q; return true end,
	storeQuery = function(q)
		queries[#queries + 1] = q
		if dbMode == "foreign" and not mine(q) and q:upper():find("^%s*SELECT") then
			nextResult = nextResult + 1
			results[nextResult] = {rows = 1}
			return nextResult
		end
		return false
	end,
	asyncStoreQuery = function(q, cb) queries[#queries + 1] = q; if cb then cb(false) end; return true end,
	lastInsertId = function() return 1 end,
	tableExists = function() return true end,
	index = function() return 1 end,
}
local function foreignValue(col)
	col = tostring(col):lower()
	if col:find("name") or col:find("text") or col:find("title") or col:find("json") or col:find("data") then
		return nil
	end
	return 999
end
result = {
	getNumber = function(id, col)
		if not results[id] then
			return false
		end
		return foreignValue(col) or 0
	end,
	getString = function(id, col)
		if not results[id] then
			return false
		end
		return foreignValue(col) and "999" or "Other"
	end,
	getStream = function(id) return results[id] and "" or false end,
	getDataInt = function(id, col) return results[id] and 999 or false end,
	getDataString = function(id) return results[id] and "Other" or false end,
	next = function(id)
		local r = results[id]
		if not r then
			return false
		end
		r.rows = r.rows - 1
		return r.rows > 0
	end,
	free = function(id) results[id] = nil; return true end,
}

-- events: everything registered is kept by type; addEvent queues (run after each call, see drain)
local registered = {} -- {type, name, object, source}
local function eventClass(kind)
	return class(kind, function(name)
		local source
		for level = 2, 8 do
			local info = debug.getinfo(level, "S")
			if info and info.source:find("data/", 1, true) then
				source = info.source
				break
			end
		end
		local o = {name = name, kind = kind, source = source}
		function o:type(t) self.etype = t end
		function o:register()
			registered[#registered + 1] = self
			return true
		end
		return setmetatable(o, {__index = function(_, k) return noted(kind, k) end})
	end)
end
CreatureEvent = eventClass("CreatureEvent")
GlobalEvent = eventClass("GlobalEvent")
TalkAction = eventClass("TalkAction")
Action = eventClass("Action")
MoveEvent = eventClass("MoveEvent")
Spell = eventClass("Spell")
Weapon = eventClass("Weapon")
EventCallback = setmetatable({register = function() return true end}, {__index = function(_, k)
	return noted("EventCallback", k)
end, __call = function() return object("EventCallback", {register = function() return true end}) end})

local queue, eventId = {}, 0
function addEvent(fn, delay, ...)
	eventId = eventId + 1
	queue[#queue + 1] = {id = eventId, fn = fn, args = {n = select("#", ...), ...}}
	return eventId
end
function stopEvent(id)
	for i, e in ipairs(queue) do
		if e.id == id then
			table.remove(queue, i)
			return true
		end
	end
	return false
end

-- every answer goes through the real Player.sendExtendedOpcode (extended_opcode.lua) into this NetworkMessage
local sent = {}
local NM = {}
NM.__index = NM
function NetworkMessage() return setmetatable({bytes = {}}, NM) end
function NM:addByte(b) self.bytes[#self.bytes + 1] = b end
function NM:addU16(b) self.bytes[#self.bytes + 1] = b end
function NM:addU32(b) self.bytes[#self.bytes + 1] = b end
function NM:addString(s)
	if #s > 8192 then
		return
	end
	self.bytes[#self.bytes + 1] = s
end
function NM:sendToPlayer(player)
	if self.bytes[1] == 0x32 then
		sent[#sent + 1] = {opcode = self.bytes[2], buffer = self.bytes[3], to = player}
	end
end
function NM:delete() end
local warnings = {}
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	warnings[#warnings + 1] = table.concat(parts, "\t")
end
io.write = function() end

-- ---------------------------------------------------------------- load every script with an opcode handler
local function readFile(path)
	local h = io.open(path, "r")
	if not h then
		return nil
	end
	local s = h:read("*a")
	h:close()
	return s
end
local function listFiles()
	local files, all = {}, {}
	local p = io.popen('find data/scripts -name "*.lua" | LC_ALL=C sort')
	for line in p:lines() do
		local src = readFile(line)
		all[#all + 1] = line
		if src and src:find("onExtendedOpcode", 1, true) then
			files[#files + 1] = line
		end
	end
	p:close()
	return files, all
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/ratelimit.lua")
dofile("data/scripts/chaos/extended_opcode.lua")
local handlerFiles, allFiles = listFiles()
local loadErrors = {}
for _, f in ipairs(allFiles) do
	local ok, err = pcall(dofile, f)
	if not ok then
		loadErrors[#loadErrors + 1] = f .. ": " .. tostring(err)
	end
end
for _, e in ipairs(loadErrors) do
	failure("load", "-", e, "the script must load")
end
-- the Auto Seller unlocked (store), so its window actions (pouches.lua opcode 226 -> autosell.lua) read their fields
if Chaos.storage and Chaos.storage.shopAutoSeller then
	fuzzer.storage[Chaos.storage.shopAutoSeller] = 1
end

local handlers = {}
for _, ev in ipairs(registered) do
	if type(rawget(ev, "onExtendedOpcode")) == "function" then
		local file = tostring(ev.source):gsub("^@", "")
		-- the file and what it loads (its core files; not chaos_constants.lua or the *_config.lua numbers)
		local src = readFile(file) or ""
		local parts = {src}
		for dep in src:gmatch('dofile%("(data/scripts/chaos/[%w_]+%.lua)"%)') do
			if not dep:find("_config.lua", 1, true) and not dep:find("chaos_constants", 1, true) then
				parts[#parts + 1] = readFile(dep) or ""
			end
		end
		handlers[#handlers + 1] = {name = ev.name, file = file, fn = ev.onExtendedOpcode, source = table.concat(parts, "\n")}
	end
end

-- ---------------------------------------------------------------- which opcodes each handler answers
-- A handler answers an opcode when, for that opcode, it touches the buffer, the player or the JSON decoder at all.
local touched = false
local stringMt = getmetatable("")
local realStringIndex = stringMt.__index
local realDecode, realChaosDecode = json.decode, Chaos.decode
local probePlayer = setmetatable({}, {__index = function(_, k)
	touched = true
	return function(_, ...) return fuzzer[k](fuzzer, ...) end
end})
local function probe(h, opcode)
	touched = false
	stringMt.__index = function(_, k) touched = true; return realStringIndex[k] end
	json.decode = function(...) touched = true; return realDecode(...) end
	Chaos.decode = function(...) touched = true; return realChaosDecode(...) end
	local ok = pcall(h.fn, probePlayer, opcode, '{"action":"__probe"}')
	stringMt.__index = realStringIndex
	json.decode, Chaos.decode = realDecode, realChaosDecode
	queue = {}
	return touched or not ok
end
local known = {} -- opcode -> constant name
for k, v in pairs(ChaosOpcodes) do
	known[v] = known[v] and (known[v] .. "/" .. k) or k
end
local opcodeOwners = {} -- opcode -> handler names
for _, h in ipairs(handlers) do
	h.opcodes = {}
	for op = 0, 255 do
		if probe(h, op) then
			h.opcodes[#h.opcodes + 1] = op
			opcodeOwners[op] = opcodeOwners[op] or {}
			table.insert(opcodeOwners[op], h.name)
		end
	end
end
queue = {}

-- ---------------------------------------------------------------- one call: run the handler, then what it scheduled
local tokens, tokenN = {}, 0 -- prepared payloads: a token buffer decodes to a fresh copy of its table
-- the message and msg.data are copied for every call; deeper tables (the big ones) are shared
local function deepCopy(v, depth)
	depth = depth or 0
	if type(v) ~= "table" or depth > 1 then
		return v
	end
	local t = {}
	for k, x in pairs(v) do
		t[k] = deepCopy(x, depth + 1)
	end
	return t
end
local function token(t)
	tokenN = tokenN + 1
	local key = "\1fuzz" .. tokenN
	tokens[key] = t
	return key
end
local decoded = {} -- raw buffers are sent to every handler: decode each once
json.decode = function(buffer)
	local t = tokens[buffer]
	if t ~= nil then
		return deepCopy(t)
	end
	local d = type(buffer) == "string" and decoded[buffer]
	if not d then
		local ok, v = pcall(realDecode, buffer)
		d = {ok = ok, v = v}
		if type(buffer) == "string" then
			decoded[buffer] = d
		end
	end
	if not d.ok then
		error(d.v, 0)
	end
	return deepCopy(d.v)
end
_G.json.decode = json.decode
realDecode = json.decodeString

local seq = {} -- db queries, answers and refused rate limits of the current call, in order
local dbQuery, dbStore, dbAsync = db.query, db.storeQuery, db.asyncQuery
db.query = function(q) seq[#seq + 1] = "db"; return dbQuery(q) end
db.storeQuery = function(q) seq[#seq + 1] = "db"; return dbStore(q) end
db.asyncQuery = function(q) seq[#seq + 1] = "db"; return dbAsync(q) end
local rawAllow = ChaosRateLimit.allow
ChaosRateLimit.allow = function(player, key, ms)
	local ok = rawAllow(player, key, ms)
	seq[#seq + 1] = ok and "allow" or "refused"
	return ok
end
local sendToPlayer = NM.sendToPlayer
function NM:sendToPlayer(player) seq[#seq + 1] = "send"; return sendToPlayer(self, player) end

-- where an error comes from: the first frame in data/ (a frame in this file means the mock misses something)
local unpackArgs = unpack or table.unpack
local function traced(m)
	return {msg = tostring(m), tb = debug.traceback("", 2)}
end
local function locate(err)
	local first = err.msg:match("^([^:]*data/[^:]+:%d+):")
	if first then
		return first
	end
	for line in err.tb:gmatch("[^\n]+") do
		local at = line:match("(data/[%w_/%.]+:%d+):")
		if at then
			return at .. " (" .. err.msg:sub(1, 80) .. ")"
		end
	end
	return "mock: " .. err.msg:sub(1, 120)
end

local function describe(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "string" then
		if #v > 40 then
			return string.format("<string %d bytes>", #v)
		end
		return string.format("%q", v)
	elseif t == "number" then
		if v ~= v then
			return "NaN"
		end
		return tostring(v)
	elseif t ~= "table" then
		return tostring(v)
	end
	if depth > 2 then
		return "{...}"
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	if #keys > 6 then
		return string.format("<table %d entries>", #keys)
	end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = tostring(k) .. "=" .. describe(v[k], depth + 1)
	end
	return "{" .. table.concat(parts, ", ") .. "}"
end

local currentPlayer = fuzzer
local slowCalls = {}
local function drain(h, label)
	local ran = 0
	while #queue > 0 and ran < 40 do
		local e = table.remove(queue, 1)
		ran = ran + 1
		local ok, err = xpcall(function() return e.fn(unpackArgs(e.args, 1, e.args.n)) end, traced)
		if not ok then
			failure("error in addEvent", h.name, locate(err), label() .. "\n      " .. err.msg)
		end
	end
	queue = {}
end

local function run(h, player, opcode, buffer, makeLabel)
	grants, badCalls, sent, warnings, seq = {}, {}, {}, {}, {}
	local function label()
		return type(makeLabel) == "function" and makeLabel() or tostring(makeLabel)
	end
	local q0 = #queries
	local t0 = os.clock()
	local ok, err = xpcall(function() return h.fn(player, opcode, buffer) end, traced)
	local dt = os.clock() - t0
	checks = checks + 1
	if not ok then
		failure("error", h.name, locate(err), label() .. "\n      " .. err.msg)
	end
	drain(h, label)
	if dt > 0.25 then
		slowCalls[#slowCalls + 1] = string.format("%s %s: %.2f s", h.name, label(), dt)
	end
	check(#grants == 0, "granted", h.name, grants[1], label)
	check(#badCalls == 0, "bad engine argument", h.name, badCalls[1], label)
	for _, w in ipairs(warnings) do
		local at = w:match("(data/[%w_/%.]+:%d+):") or w:match("([%w_]+%.lua:%d+):")
		check(not at, "error caught by the module", h.name, at, function() return label() .. "\n      " .. w:sub(1, 200) end)
		check(not w:find("use Chaos.sendChunked", 1, true), "answer over 8192 bytes", h.name, w:sub(1, 90), label)
	end
	for i = q0 + 1, #queries do
		check(not queries[i]:find(MARK, 1, true), "unescaped SQL", h.name, queries[i]:sub(1, 100), label)
	end
	for _, m in ipairs(sent) do
		check(#m.buffer <= Chaos.extendedOpcodeMax, "answer over 8192 bytes", h.name, m.opcode, label)
	end
	return ok
end

local function resetLimits()
	ChaosRateLimit.last, ChaosRateLimit.keys = {}, {}
	if ChaosAdmin and ChaosAdmin.lastRequest then
		ChaosAdmin.lastRequest = {}
	end
	clock = clock + 5001
end

-- ---------------------------------------------------------------- bad values
local function nested(depth)
	local t = {}
	local cur = t
	for _ = 1, depth do
		cur[1] = {}
		cur = cur[1]
	end
	return t
end
local bigArray = {}
for i = 1, 5000 do
	bigArray[i] = i
end
local bigMap = {}
for i = 1, 2000 do
	bigMap["k" .. i] = i
end
local HUGE = string.rep("A", 60000)
local NAN = 0 / 0
local garbage = {
	{"absent", nil}, {"true", true}, {"false", false}, {"0", 0}, {"-1", -1}, {"1", 1}, {"0.5", 0.5}, {"-0.5", -0.5},
	{"2^31", 2147483648}, {"-2^31-1", -2147483649}, {"2^53", 9007199254740992}, {"1e308", 1e308}, {"-1e308", -1e308},
	{"inf", math.huge}, {"-inf", -math.huge}, {"NaN", NAN}, {"empty string", ""}, {"'1'", "1"}, {"'-5'", "-5"},
	{"'abc'", "abc"}, {"sql", MARK .. "); DROP TABLE players; --"}, {"60 KB string", HUGE}, {"nul byte", "a\0b"},
	{"'1e999'", "1e999"}, {"'nan'", "nan"}, {"format string", "%s%d%n%%"}, {"pattern", "(%w+)[^"},
	{"empty table", {}}, {"array", {1, 2, 3}}, {"string array", {"a", "b"}}, {"array with hole", {1, nil, 3}},
	{"object", {a = 1, id = 1}}, {"array of tables", {{}, {id = 1}}}, {"5000 entries", bigArray},
	{"2000 keys", bigMap}, {"deep 300", nested(300)}, {"mixed table", {1, a = 2}},
}
-- msg.data itself is replaced by these
local dataGarbage = {}
for _, g in ipairs(garbage) do
	local n = g[1]
	if n == "true" or n == "0" or n == "-1" or n == "inf" or n == "NaN" or n == "'abc'" or n == "60 KB string"
		or n == "empty table" or n == "array" or n == "array with hole" or n == "5000 entries" or n == "2000 keys"
		or n == "deep 300" or n == "mixed table" or n == "string array" then
		dataGarbage[#dataGarbage + 1] = g
	end
end
-- every field gets these; the whole list goes into the random mixes
local fieldGarbage = {}
for _, g in ipairs(garbage) do
	local n = g[1]
	if n == "absent" or n == "true" or n == "0" or n == "-1" or n == "0.5" or n == "2^31" or n == "2^53" or n == "inf"
		or n == "-inf" or n == "NaN" or n == "empty string" or n == "'abc'" or n == "sql" or n == "60 KB string"
		or n == "nul byte" or n == "empty table" or n == "array" or n == "object" or n == "5000 entries"
		or n == "deep 300" then
		fieldGarbage[#fieldGarbage + 1] = g
	end
end

local function sortedKeys(set)
	local list = {}
	for k in pairs(set) do
		list[#list + 1] = k
	end
	table.sort(list, function(a, b) return tostring(a) < tostring(b) end)
	return list
end

-- buffers that are not a JSON object at all (sent to every handler on every opcode it answers)
local rawBuffers = {"", " ", "{", "}", "[", "null", "true", "0", "-1", "1e999", '"text"', "[]", "[1,2,3]",
	'{"action":', '{"action":"open"', '{"action":"open",}', '{"action":"open"}}', "{'action':'open'}",
	'{"action":"\\u0000"}', '{"action":"\\ud800"}', '{"action":1}', '{"action":null}', '{"action":{}}',
	'{"action":[]}', '{"data":{}}', '{"action":"open","data":null}', '{"action":"open","data":"x"}',
	'{"action":"open","data":1e999}', '{"action":"open","data":[' .. string.rep("1,", 3000) .. '1]}',
	string.rep("[", 3000) .. string.rep("]", 3000), string.rep('{"a":', 2000) .. "1" .. string.rep("}", 2000),
	'{"action":"' .. string.rep("x", 60000) .. '"}', string.rep("\255", 100), "\0\0\0", "S{", "P}", "E",
	"accept_invite|x|y|z", "accept_invite|" .. string.rep("x", 5000), "start_catacomb|solo|-1|fire",
	"start_catacomb|solo|1e999|" .. MARK, "start_catacomb||nan|", "leave_queue", "decline_invite|" .. MARK}

-- ---------------------------------------------------------------- what each handler reads
-- Actions: the strings its file compares with (`== "x"`) and the keys of its action tables; fields: what the handler
-- reads from the message and from msg.data, found by handing it tables that record every read.
local function staticActions(src)
	local set = {}
	for a in src:gmatch('==%s*"([%a_][%w_%.%-]*)"') do
		set[a] = true
	end
	for a in src:gmatch('~=%s*"([%a_][%w_%.%-]*)"') do
		set[a] = true
	end
	for a in src:gmatch("\n%s*([%a_][%w_]*)%s*=%s*function") do
		set[a] = true
	end
	for a in src:gmatch('%[%s*"([%a_][%w_]*)"%s*%]%s*=%s*function') do
		set[a] = true
	end
	for a in src:gmatch("[%.:]([%a_][%w_]*)%s*=%s*function") do
		set[a] = true
	end
	for a in src:gmatch("function%s+[%w_]*[Aa]ctions?[%.:]([%a_][%w_]*)") do
		set[a] = true
	end
	for a in src:gmatch("function%s+[%w_]*[Hh]andlers?[%.:]([%a_][%w_]*)") do
		set[a] = true
	end
	for a in src:gmatch("\n%s*([%a_][%w_]*)%s*=%s*{") do
		set[a] = true
	end
	return set
end
-- fields the code compares with strings (data.make == "Redeem", m.phase == "start"): field -> list of the strings
local function fieldLiterals(src)
	local map = {}
	for field, lit in src:gmatch('[%w_]%.([%a_][%w_]*)%s*==%s*"([^"\n]+)"') do
		if field ~= "action" then
			map[field] = map[field] or {}
			map[field][lit] = true
		end
	end
	for field, set in pairs(map) do
		map[field] = sortedKeys(set)
	end
	return map
end
-- action tables of other modules that a handler hands requests to (ChaosSalvage.actions, ChaosParagon.actions, ...)
local function dynamicActions(src, set)
	for name, g in pairs(_G) do
		if type(name) == "string" and name:match("^Chaos") and type(g) == "table" and src:find(name, 1, true) then
			-- AUTOSELL_ACTIONS: the Auto Seller window's actions that pouches.lua (opcode 226) hands to autosell.lua (a set)
			for _, field in ipairs({"actions", "extraActions", "handlers", "AUTOSELL_ACTIONS"}) do
				local t = rawget(g, field)
				if type(t) == "table" then
					for k, v in pairs(t) do
						if type(k) == "string" and (type(v) == "function" or v == true) then
							set[k] = true
						end
					end
				end
			end
		end
	end
end

local function recorder(store, prefix)
	return setmetatable({}, {__index = function(_, k)
		if k ~= nil then
			store[prefix .. tostring(k)] = k
		end
		return nil
	end})
end

-- one call with recording tables: the fields it read, and whether it did anything for this action at all
local function footprint(h, opcode, msg)
	local reads = {}
	local top = recorder(reads, "msg.")
	local m = setmetatable({}, getmetatable(top))
	for k, v in pairs(msg) do
		rawset(m, k, v)
	end
	if type(msg.data) == "table" then
		local d = recorder(reads, "data.")
		for k, v in pairs(msg.data) do
			rawset(d, k, v)
		end
		rawset(m, "data", d)
	end
	local key = "\1probe"
	tokens[key] = m
	local decodeBefore = json.decode
	json.decode = function(b) if b == key then return m end; return decodeBefore(b) end
	_G.json.decode = json.decode
	resetLimits()
	grants, badCalls, sent, warnings, seq = {}, {}, {}, {}, {}
	local q0 = #queries
	local used = 0
	local probeP = setmetatable({}, {__index = function(_, k)
		used = used + 1
		return function(_, ...) return fuzzer[k](fuzzer, ...) end
	end})
	pcall(h.fn, probeP, opcode, key)
	json.decode = decodeBefore
	_G.json.decode = json.decode
	tokens[key] = nil
	queue = {}
	local n = 0
	for _ in pairs(reads) do
		n = n + 1
	end
	local effect = used + (#queries - q0) + #sent
	return reads, effect + n, effect
end


local function setField(msg, key, raw, v)
	if key:sub(1, 5) == "data." then
		if type(msg.data) ~= "table" then
			msg.data = {}
		end
		msg.data[raw] = v
	elseif raw ~= "data" and raw ~= "action" then
		msg[raw] = v
	end
end

-- a request: the action, the strings that pick a sub-action (data.make = "Redeem"), the fields it reads
local function build(entry, override, value)
	local msg = {action = entry.action, data = {}}
	for _, f in ipairs(entry.fields) do
		setField(msg, f.key, f.raw, 1)
	end
	for key, v in pairs(entry.fixed) do
		setField(msg, key, v.raw, v.value)
	end
	if override then
		setField(msg, override.key, override.raw, value)
	end
	return msg
end

local fill = {1, "a", true, {1}, 0}
local function learn(h, opcode, entry, base)
	local seen = {}
	local reads, act = footprint(h, opcode, build(entry))
	local active = act ~= base
	for round = 1, #fill do
		local n = 0
		for k, raw in pairs(reads) do
			if not seen[k] and not entry.fixed[k] then
				seen[k] = raw
				n = n + 1
			end
		end
		if n == 0 and round > 1 then
			break
		end
		local msg = build(entry)
		for k, raw in pairs(seen) do
			setField(msg, k, raw, fill[round])
		end
		reads, act = footprint(h, opcode, msg)
		active = active or act ~= base
	end
	entry.fields = {}
	for k, raw in pairs(seen) do
		if raw ~= "action" and not (k == "msg.data") then
			entry.fields[#entry.fields + 1] = {key = k, raw = raw}
		end
	end
	table.sort(entry.fields, function(x, y) return x.key < y.key end)
	return active, act
end

local function discover(h, opcode)
	local set = staticActions(h.source)
	dynamicActions(h.source, set)
	local literals = fieldLiterals(h.source)
	-- what an unknown action does and reads: an action is only kept when it does or reads something else
	local unknown = {action = "__unknown_action__", fixed = {}, fields = {}}
	local _, base = footprint(h, opcode, build(unknown))
	learn(h, opcode, unknown, base)
	local baseFields = {}
	for _, f in ipairs(unknown.fields) do
		baseFields[f.key] = true
	end
	local entries = {}
	for _, a in ipairs(sortedKeys(set)) do
		local entry = {action = a, fixed = {}, fields = {}}
		local active, act = learn(h, opcode, entry, base)
		local own = false
		for _, f in ipairs(entry.fields) do
			own = own or not baseFields[f.key]
		end
		if active or own then
			entries[#entries + 1] = entry
			-- sub-actions: a field the code compares with strings gets each of those strings once
			for _, f in ipairs(entry.fields) do
				local lits = literals[f.raw]
				if lits and type(f.raw) == "string" then
					for i = 1, math.min(#lits, 30) do
						local sub = {action = a, fixed = {[f.key] = {raw = f.raw, value = lits[i]}}, fields = {}}
						local _, subAct = learn(h, opcode, sub, act)
						if subAct ~= act then
							entries[#entries + 1] = sub
						end
					end
				end
			end
		end
	end
	entries[#entries + 1] = unknown
	return entries
end

local function entryName(e)
	local parts = {describe(e.action)}
	for k, v in pairs(e.fixed) do
		parts[#parts + 1] = k .. "=" .. describe(v.value)
	end
	return table.concat(parts, " ")
end

local rawChars = '{}[]",:0123456789.-eE truefalsnul\\|'
local function randomRaw()
	local n = rnd(60)
	local out = {}
	for i = 1, n do
		local k = rnd(#rawChars)
		out[i] = rawChars:sub(k, k)
	end
	return table.concat(out)
end

local function fuzzHandler(h, opcode)
	for i, raw in ipairs(rawBuffers) do
		resetLimits()
		run(h, fuzzer, opcode, raw, "raw buffer #" .. i .. " " .. describe(raw))
	end
	for _ = 1, 8 do
		local raw = randomRaw()
		resetLimits()
		run(h, fuzzer, opcode, raw, "random buffer " .. describe(raw))
	end
	h.actions = discover(h, opcode)
	for _, e in ipairs(h.actions) do
		local name = entryName(e)
		local function go(msg, what)
			resetLimits()
			run(h, fuzzer, opcode, token(msg), function()
				return "action " .. name .. ", " .. what .. ": " .. describe(msg)
			end)
		end
		go({action = e.action}, "no data")
		for _, g in ipairs(dataGarbage) do
			local msg = build(e)
			msg.data = g[2]
			go(msg, "data = " .. g[1])
		end
		for _, f in ipairs(e.fields) do
			for _, g in ipairs(fieldGarbage) do
				go(build(e, f, g[2]), f.key .. " = " .. g[1])
			end
		end
		for _ = 1, (#e.fields > 0 and 5 or 0) do
			local msg = build(e)
			local what = {}
			for _, f in ipairs(e.fields) do
				local g = garbage[rnd(#garbage)]
				what[#what + 1] = f.key .. " = " .. g[1]
				setField(msg, f.key, f.raw, g[2])
			end
			go(msg, table.concat(what, ", "))
		end
		-- someone else's things: every row the database returns belongs to another character
		dbMode = "foreign"
		for i, v in ipairs({999, -999, "Other"}) do
			if i > 1 and #e.fields == 0 then
				break
			end
			local msg = build(e)
			for _, f in ipairs(e.fields) do
				setField(msg, f.key, f.raw, v)
			end
			go(msg, "rows of another character, every field " .. describe(v))
		end
		dbMode = "empty"
	end
end

-- ---------------------------------------------------------------- creature events (login, logout, death)
local function fire(kind, ...)
	for _, ev in ipairs(registered) do
		local fn = rawget(ev, kind)
		if type(fn) == "function" then
			grants, badCalls, sent, warnings = {}, {}, {}, {}
			local ok, err = xpcall(fn, traced, ...)
			if not ok then
				failure("error in " .. kind, ev.name or "?", locate(err), err.msg)
			end
			drain({name = ev.name or "?"}, function() return kind end)
		end
	end
	queue = {}
end

-- the fuzzer logs in like every player does (the modules set up their per-player state here)
fire("onLogin", fuzzer)
fire("onLogin", other)

local t0 = os.clock()
for _, h in ipairs(handlers) do
	for _, op in ipairs(h.opcodes) do
		fuzzHandler(h, op)
	end
end

-- ---------------------------------------------------------------- regressions
-- The requests that failed before the fixes, sent every run whatever the random draw. Errors, inf / NaN echoed into
-- json.encode, answers over 8192 bytes and SQL with a float id are caught by run() like every other case.
local byName = {}
for _, h in ipairs(handlers) do
	byName[h.name] = h
end
local function regression(name, opcode, msg, label)
	local h = byName[name]
	check(h ~= nil, "regression", name, label, "the handler is gone")
	if h then
		resetLimits()
		run(h, fuzzer, opcode, token(msg), "regression: " .. label)
	end
end
local INF = math.huge
local regressions = {
	-- msg.data true: indexed as a table
	{"ChaosInvasionOpcode", ChaosOpcodes.invasion, {action = "calendar", data = true}, "invasion calendar, data true"},
	-- the client's seq / request number echoed into the answer: inf, NaN or a table broke json.encode
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "orders", data = {seq = INF}}, "market orders, seq inf"},
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "orders", data = {seq = {1, nil, 3}}}, "market orders, seq table"},
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "browse", data = {seq = -INF}}, "market browse, seq -inf"},
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "prices", data = {id = 1, sid = 1, seq = INF}},
		"market prices, seq inf"},
	{"ChaosItemLinkExtended", ChaosOpcodes.itemLink, {action = "register", data = {n = INF, items = {{}}}},
		"item link register, n inf"},
	{"ChaosLootFilterExtended", ChaosOpcodes.lootfilter, {action = "take", data = {k = INF}}, "loot filter take, k inf"},
	-- ids past 2^53 (no exact integer): "%d" in the SQL failed under Lua 5.3, -2^63 under LuaJIT
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "cancel", data = {id = 1e308}}, "market cancel, id 1e308"},
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "tip", data = {id = 1e308}}, "market tip, id 1e308"},
	{"ChaosOrbExchangeExtended", ChaosOpcodes.orbExchange, {action = "cancel", data = {id = -1e308}},
		"orb exchange cancel, id -1e308"},
	{"ChaosMentorExtended", ChaosOpcodes.mentor, {action = "choose", data = {guid = 1e308}}, "mentor choose, guid 1e308"},
	{"ChaosMentorExtended", ChaosOpcodes.mentor, {action = "accept", data = {guid = 1e308}}, "mentor accept, guid 1e308"},
	{"ChaosHideoutOpcode", ChaosOpcodes.hideout, {action = "like", data = {owner = 0.5}}, "hideout like, owner 0.5"},
	-- NaN as a table key (not reachable through JSON, which has no NaN; kept as a guard)
	{"ChaosTransmogExtended", ChaosOpcodes.transmog, {action = "apply", data = {look = NAN, slot = 1}},
		"transmog apply, look NaN"},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "trialChoose", data = {pair = NAN, side = 1}},
		"trial choose, pair NaN"},
	-- a long client string echoed made the answer too big to send
	{"ChaosCommandsExtended", ChaosOpcodes.info, {action = "run", page = HUGE, ids = {}}, "commands run, page 60 KB"},
	{"ChaosCraftingExtended", ChaosOpcodes.crafting, {action = "apply", data = {orb = HUGE, path = 1, id = 1}},
		"crafting apply, orb 60 KB"},
}
for _, r in ipairs(regressions) do
	regression(r[1], r[2], r[3], r[4])
end

-- requests that read the database on every call before: from the third rapid call on, none may
local rapid = {
	{"ChaosStashExtended", ChaosOpcodes.stash, {action = "Stash", data = {make = "Stash", UpdateList = true, Pos = 1}}},
	-- a real item the stash refuses (the equipped backpack), named again and again: the echo is limited too
	{"ChaosStashExtended", ChaosOpcodes.stash, {action = "Stash", data = {make = "Stash", UpdateList = true,
		Pos = {x = 65535, y = CONST_SLOT_BACKPACK, z = 0}}}},
	{"ChaosCraftingExtended", ChaosOpcodes.crafting, {action = "apply", data = {path = 1, id = 1}}},
	{"ChaosCraftingExtended", ChaosOpcodes.crafting, {action = "gem", data = {path = 1, id = 1}}},
	{"ChaosShopExtended", ChaosOpcodes.shop, {action = "init", data = {}}},
	{"ChaosShopExtended", ChaosOpcodes.shop, {action = "get_page", data = {category = 1, page = 1}}},
	{"ChaosShopExtended", ChaosOpcodes.shop, {action = "preview", data = {category = 1, page = 1, offer = 1}}},
	{"ChaosMarketExtended", ChaosOpcodes.market, {action = "wallet", data = {}}},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "requestPoints"}},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "requestNodesUnlocked"}},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "refund"}},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "refundNode", data = {id = 1}}},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "resetPreset", data = 1}},
	{"ChaosPassiveTreeExtended", ChaosOpcodes.passivetree, {action = "buildExport"}},
	{"ChaosGuildWarOpcode", ChaosOpcodes.guildWar, {action = "bossGold", data = {amount = 1}}},
}
for _, r in ipairs(rapid) do
	local h = byName[r[1]]
	check(h ~= nil, "regression", r[1], r[3].action, "the handler is gone")
	if h then
		resetLimits()
		local buffer = token(r[3])
		for i = 1, 6 do
			local q0 = #queries
			run(h, fuzzer, r[2], buffer, "rapid " .. r[3].action)
			if i >= 3 then
				check(#queries == q0, "no rate limit", h.name, r[3].action, "call " .. i .. " of 6 within the same ms " ..
					"read the database: " .. tostring(queries[q0 + 1]):sub(1, 90))
			end
		end
	end
end

-- the limiter's own table: keys are made of client action names, so their number per player is capped
resetLimits()
local bounty = byName.ChaosBountyExtended
for i = 1, 2000 do
	run(bounty, fuzzer, ChaosOpcodes.bounty, token({action = "made-up-" .. i}), "made-up action " .. i)
end
local keys = 0
for _ in pairs(ChaosRateLimit.last[fuzzer.cid] or {}) do
	keys = keys + 1
end
check(keys <= ChaosRateLimit.maxKeys, "rate limit table", "ratelimit.lua", keys, "keys of one player not capped")
check(ChaosRateLimit.allowAt(1, string.rep("k", 200), 100, 1) == false, "rate limit table", "ratelimit.lua",
	"long key", "a 200-byte key was stored")
ChaosRateLimit.forget(fuzzer.cid)
check(ChaosRateLimit.keys[fuzzer.cid] == nil, "rate limit table", "ratelimit.lua", "forget", "count not cleared")

-- ---------------------------------------------------------------- rate limits: the same request again and again
-- with the clock stopped. Once a limit refuses a request, that request must not reach the database or answer.
local unlimited = {}
for _, h in ipairs(handlers) do
	for _, op in ipairs(h.opcodes) do
		for _, e in ipairs(h.actions) do
			resetLimits()
			local buffer = token(build(e))
			local label = "rapid calls, action " .. entryName(e)
			run(h, fuzzer, op, buffer, label)
			local limited, dbEveryTime = false, true
			local lastQuery
			for _ = 1, 5 do
				local q0 = #queries
				run(h, fuzzer, op, buffer, label)
				lastQuery = queries[q0 + 1] or lastQuery
				local refusedAt, hasDb = nil, false
				for i, ev in ipairs(seq) do
					if ev == "refused" and not refusedAt then
						refusedAt = i
					elseif ev == "db" then
						hasDb = true
						check(not refusedAt, "rate limit bypassed", h.name, entryName(e),
							"database query after the rate limit refused the request")
					end
				end
				limited = limited or refusedAt ~= nil
				dbEveryTime = dbEveryTime and hasDb
			end
			if dbEveryTime and not limited then
				unlimited[#unlimited + 1] = {h.name .. " " .. entryName(e), tostring(lastQuery):sub(1, 100)}
			end
		end
	end
end
-- every request that reads or writes the database on each call must be rate limited
for _, u in ipairs(unlimited) do
	failure("no rate limit", u[1], "a database query on every one of 5 rapid calls", u[2])
end

-- ---------------------------------------------------------------- after logout and after death
-- requests already queued when the player logs out (or dies), and what the handlers scheduled, must not fail
fire("onLogout", fuzzer)
for _, h in ipairs(handlers) do
	for _, op in ipairs(h.opcodes) do
		for _, e in ipairs(h.actions) do
			resetLimits()
			run(h, fuzzer, op, token(build(e)), "after logout, action " .. entryName(e))
			resetLimits()
			online[fuzzer.cid] = nil -- the events it scheduled fire after the player is gone
			run(h, fuzzer, op, token({action = e.action}), "player removed, action " .. entryName(e))
			online[fuzzer.cid] = fuzzer
		end
	end
end
fire("onLogin", fuzzer)
fuzzer.health = 0
fire("onPrepareDeath", fuzzer, nil)
fire("onDeath", fuzzer, nil, nil, nil, false, false)
for _, h in ipairs(handlers) do
	for _, op in ipairs(h.opcodes) do
		for _, e in ipairs(h.actions) do
			resetLimits()
			run(h, fuzzer, op, token(build(e)), "dead player, action " .. entryName(e))
		end
	end
end
fuzzer.health = fuzzer.maxHealth

-- ---------------------------------------------------------------- opcodes
-- server/README.md "Extended opcodes" lists every opcode: its ChaosOpcodes key, the server scripts and the client
-- module. Every handler answers exactly the opcode(s) of its rows, every key matches chaos_constants.lua, no two
-- keys share a number, nothing takes an opcode of the base server or a base client module, and the handlers that
-- share one opcode never both answer the same action.
local rows = {}
local inTable = false
for line in (readFile("README.md") or ""):gmatch("([^\n]*)\n") do
	if line:find("^| Opcode | `ChaosOpcodes` key |") then
		inTable = true
	elseif inTable and not line:find("^|") then
		inTable = false
	end
	local op, key, servers, client = line:match("^| (%d+) | ([^|]+) | ([^|]+) | ([^|]+) |")
	if inTable and op then
		rows[tonumber(op)] = {key = key:match("^`([%w_]+)`"), servers = servers, client = client:match("`([%w_]+)`")}
	end
end
check(next(rows) ~= nil, "opcodes", "README.md", "opcode table", "server/README.md has no opcode table")
local reserved = {1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 144, 145, 146}
local byValue = {}
for key, op in pairs(ChaosOpcodes) do
	check(byValue[op] == nil, "opcodes", "ChaosOpcodes", op, key .. " and " .. tostring(byValue[op]) .. " share it")
	byValue[op] = key
	check(rows[op] and rows[op].key == key, "opcodes", "ChaosOpcodes", key, "server/README.md has no row " .. op ..
		" for it")
	for _, r in ipairs(reserved) do
		check(op ~= r, "opcodes", "ChaosOpcodes", key, op .. " is used by the base server or client")
	end
end
for op, row in pairs(rows) do
	if row.key then
		check(ChaosOpcodes[row.key] == op, "opcodes", "README.md", op, "ChaosOpcodes." .. row.key .. " is " ..
			tostring(ChaosOpcodes[row.key]))
	end
end
for _, h in ipairs(handlers) do
	local base = h.file:match("data/scripts/chaos/(.+)$") or h.file
	check(#h.opcodes > 0, "opcodes", h.name, h.file, "answers no opcode")
	for _, op in ipairs(h.opcodes) do
		local row = rows[op]
		check(row ~= nil and row.servers:find("`" .. base .. "`", 1, true) ~= nil, "opcodes", h.name, op,
			base .. " answers it but server/README.md does not list it there")
		check(byValue[op] ~= nil or op == CHAOS_ADMIN_OPCODE, "opcodes", h.name, op, "not a ChaosOpcodes value")
	end
end
-- `ChaosOpcodes.x or 123` and `ChaosOpcodes.x or cfg.opcode`: the fallback must be the same number
for _, f in ipairs(handlerFiles) do
	local src = readFile(f)
	for key, n in src:gmatch("ChaosOpcodes%.([%w_]+)%)?%s+or%s+(%d+)") do
		check(ChaosOpcodes[key] == tonumber(n), "opcodes", f, key, "falls back to " .. n .. ", ChaosOpcodes has " ..
			tostring(ChaosOpcodes[key]))
	end
	for key in src:gmatch("ChaosOpcodes%.([%w_]+)%)?%s+or%s+cfg%.opcode") do
		local dep = f:gsub("%.lua$", "_config.lua") -- cfg is the module's own <name>_config.lua
		local n = (readFile(dep) or ""):match("\n%s*opcode%s*=%s*(%d+)")
		if n then
			check(ChaosOpcodes[key] == tonumber(n), "opcodes", dep, key, "opcode = " .. n .. ", ChaosOpcodes has " ..
				tostring(ChaosOpcodes[key]))
		end
	end
end
-- handlers on one opcode: an action reaches one of them (the map markers' hello is answered by both on purpose)
local sharedOk = {[ChaosOpcodes.mapMarkers] = {hello = true}}
for op, names in pairs(opcodeOwners) do
	if #names > 1 then
		local group = {}
		for _, h in ipairs(handlers) do
			for _, o in ipairs(h.opcodes) do
				if o == op then
					group[#group + 1] = h
				end
			end
		end
		for _, a in ipairs(group) do
			for _, e in ipairs(a.actions) do
				if e.action ~= "__unknown_action__" and not (sharedOk[op] and sharedOk[op][e.action]) then
					for _, b in ipairs(group) do
						if b ~= a then
							local _, _, none = footprint(b, op, build({action = "__unknown_action__", fixed = {}, fields = e.fields}))
							local _, _, act = footprint(b, op, build(e))
							check(act == none, "opcodes", a.name, op, "action " .. entryName(e) .. " is answered by " ..
								b.name .. " too")
						end
					end
				end
			end
		end
	end
end
if VERBOSE then
	for _, h in ipairs(handlers) do
		local names = {}
		for _, a in ipairs(h.actions or {}) do
			names[#names + 1] = entryName(a) .. "(" .. #a.fields .. ")"
		end
		realPrint(h.name, table.concat(h.opcodes, ","), table.concat(names, " "))
	end
	for _, k in ipairs(sortedKeys(missing)) do
		realPrint("mock has no", k, missing[k])
	end
	for _, line in ipairs(slowCalls) do
		realPrint("slow", line)
	end
end
print = realPrint
if #failures > 0 then
	for _, f in ipairs(failures) do
		print(f)
	end
	error(string.format("opcode_fuzz_test: %d failures (FUZZ_VERBOSE=1 for the handlers and the mock)", #failures), 0)
end
local requests = 0
for _, h in ipairs(handlers) do
	requests = requests + #(h.actions or {})
end
print(string.format("opcode_fuzz_test: %d handlers, %d actions, %d checks passed (%.1f s)", #handlers, requests, checks,
	os.clock() - t0))
