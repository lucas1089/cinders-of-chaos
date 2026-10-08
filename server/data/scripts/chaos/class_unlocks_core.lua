-- class_unlocks_core.lua: the rules of the class lock (ChaosClassUnlocksCore), no engine needed.
-- The engine part, the API other scripts call and the full description: class_unlocks.lua.
-- Unit tests: server/tests/class_unlocks_test.lua. Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- The config below is the one table to edit: which classes are locked, their vocation ids, and how a class is
-- unlocked. An unlock is per ACCOUNT (every character of the account) and is stored in the table
-- chaos_class_unlocks (server/sql/chaos_class_unlocks.sql; class_unlocks.lua also creates it at startup).
--
-- Unlock methods are pluggable: `unlock` lists one or more methods by kind; any one of them unlocks the class.
--   store       = {offer = "<shop_config unlock name>", cost = n}   bought in the store (offer kind "unlock")
--   level       = {min = n}                                         any character of the account reaches level n
--   quest       = {storage = key, value = n, text = "..."}          a character has player storage key >= value
--   achievement = {name = "...", text = "..."}                      ChaosAchievements.has(player, name), when such a
--                                                                   module exists
-- A new kind is added with ChaosClassUnlocksCore.registerMethod(kind, {describe = fn, check = fn}) without touching the
-- gate code. The automatic kinds (all but store) are checked at login and on level advance (class_unlocks.lua) and,
-- when met, record the unlock for the account like a purchase does.

ChaosClassUnlocksCore = ChaosClassUnlocksCore or {}
local M = ChaosClassUnlocksCore

M.config = {
	table = "chaos_class_unlocks",
	-- staff never meets the lock: a player of this group id or higher, or an account of this type or higher
	-- (ACCOUNT_TYPE_COMMUNITYMANAGER = 5, ACCOUNT_TYPE_GOD = 6). Group 4 = gamemaster, as the admin panel's minGroup.
	bypass = {minGroup = 4, minAccountType = 5},
	-- a character that logs in on a locked vocation without the unlock (created on the website, or the unlock was
	-- taken back):
	--   "restrict": it logs in, is sent to its temple and cannot attack, gains no experience and no skill; a window
	--               says why and how to unlock (the store works, so it can buy the unlock right there)
	--   "kick":     the same window, then it is logged out after kickAfterMs
	login = {mode = "restrict", kickAfterMs = 10000, remindMs = 300000},
	-- PRICES ARE PLACEHOLDERS (750 Chaos Coins each), to be decided by the owner.
	classes = {
		necromancer = {
			name = "Necromancer", vocations = {20, 21, 22}, locked = true, icon = 2436, -- skull staff
			unlock = {store = {offer = "unlockNecromancer", cost = 750}}
		},
		monk = {
			name = "Monk", vocations = {17, 18, 19}, locked = true, icon = 7422, -- jade hammer
			unlock = {store = {offer = "unlockMonk", cost = 750}}
		},
		templar = {
			name = "Templar", vocations = {23, 24, 25}, locked = true, icon = 2523, -- blessed shield
			unlock = {store = {offer = "unlockTemplar", cost = 750}}
		}
	}
}

local function conf(c)
	return c or M.config
end

-- ------------------------------------------------------------------------------------------------ methods
M.methods = M.methods or {}

-- kind: a key of `unlock`; def.describe(spec, class) -> text for the lock message; def.check(spec, facts) -> true
-- when the method's condition is met (nil for methods that only grant, like the store)
function M.registerMethod(kind, def)
	M.methods[kind] = def
end

M.registerMethod("store", {
	describe = function(spec, class)
		return string.format("buy the %s unlock in the store (Classes, %d Chaos Coins)", class.name, spec.cost or 0)
	end
})
M.registerMethod("level", {
	describe = function(spec)
		return string.format("reach level %d with any character of your account", spec.min or 0)
	end,
	check = function(spec, facts)
		return (facts.level or 0) >= (spec.min or math.huge)
	end
})
M.registerMethod("quest", {
	describe = function(spec)
		return spec.text or "finish its quest"
	end,
	check = function(spec, facts)
		return facts.storage ~= nil and (facts.storage(spec.storage) or -1) >= (spec.value or 1)
	end
})
M.registerMethod("achievement", {
	describe = function(spec)
		return spec.text or ("earn the achievement " .. tostring(spec.name))
	end,
	check = function(spec, facts)
		return facts.achievement ~= nil and facts.achievement(spec.name) == true
	end
})

-- the method kinds of a class, sorted (stable messages)
function M.methodKinds(classKey, c)
	local class = conf(c).classes[classKey]
	local kinds = {}
	for kind in pairs(class and class.unlock or {}) do
		kinds[#kinds + 1] = kind
	end
	table.sort(kinds)
	return kinds
end

-- ------------------------------------------------------------------------------------------------ classes
function M.classOfVocation(vocId, c)
	for key, class in pairs(conf(c).classes) do
		for _, v in ipairs(class.vocations) do
			if v == vocId then
				return key
			end
		end
	end
	return nil
end

function M.isLocked(classKey, c)
	local class = conf(c).classes[classKey]
	return class ~= nil and class.locked == true
end

function M.isBypass(groupId, accountType, c)
	local b = conf(c).bypass
	return (groupId or 0) >= b.minGroup or (accountType or 0) >= b.minAccountType
end

-- the class whose store offer is `offer` (the unlock name of a shop_config offer), or nil
function M.classOfOffer(offer, c)
	for key, class in pairs(conf(c).classes) do
		local s = class.unlock and class.unlock.store
		if s and s.offer == offer then
			return key
		end
	end
	return nil
end

-- "The Templar is locked on this account. To play it, buy ... or reach ..."
function M.lockMessage(classKey, c)
	local class = conf(c).classes[classKey]
	if not class then
		return "This class is locked on this account."
	end
	local ways = {}
	for _, kind in ipairs(M.methodKinds(classKey, c)) do
		local m = M.methods[kind]
		if m and m.describe then
			ways[#ways + 1] = m.describe(class.unlock[kind], class)
		end
	end
	local how = #ways > 0 and (" To play it, " .. table.concat(ways, ", or ") .. ".") or ""
	return string.format("The %s is locked on this account.%s", class.name, how)
end

-- May an account become vocation `vocId`? unlocked = set {[classKey] = true} of the account's unlocks.
-- Returns ok, message (nil when ok), classKey (nil for a vocation of no locked class).
function M.decide(vocId, unlocked, groupId, accountType, c)
	local key = M.classOfVocation(vocId, c)
	if not key or not M.isLocked(key, c) then
		return true, nil, key
	end
	if M.isBypass(groupId, accountType, c) or (unlocked and unlocked[key]) then
		return true, nil, key
	end
	return false, M.lockMessage(key, c), key
end

-- the automatic method that unlocks `classKey` for these facts ({level = n, storage = fn(key), achievement = fn(name)}),
-- or nil
function M.autoUnlock(classKey, facts, c)
	local class = conf(c).classes[classKey]
	if not class or not class.locked then
		return nil
	end
	for _, kind in ipairs(M.methodKinds(classKey, c)) do
		local m = M.methods[kind]
		if m and m.check and m.check(class.unlock[kind], facts or {}) then
			return kind
		end
	end
	return nil
end

-- the locked class keys, sorted
function M.lockedClasses(c)
	local list = {}
	for key, class in pairs(conf(c).classes) do
		if class.locked then
			list[#list + 1] = key
		end
	end
	table.sort(list)
	return list
end

-- ------------------------------------------------------------------------------------------------ storage
local function validKey(key)
	return type(key) == "string" and key:match("^[%w_]+$") ~= nil and #key <= 32
end
M.validKey = validKey

function M.sqlCreate(c)
	return "CREATE TABLE IF NOT EXISTS `" .. conf(c).table .. "` (" ..
		"`account_id` int(11) NOT NULL, `class_key` varchar(32) NOT NULL, `source` varchar(32) NOT NULL DEFAULT '', " ..
		"`created` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `class_key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
end

function M.sqlSelect(accountId, c)
	return string.format("SELECT `class_key` FROM `%s` WHERE `account_id` = %d", conf(c).table, math.floor(accountId))
end

-- nil for a key that is not a plain word (never sent to the database)
function M.sqlInsert(accountId, classKey, source, now, c)
	if not validKey(classKey) or not validKey(source) then
		return nil
	end
	return string.format("INSERT IGNORE INTO `%s` (`account_id`, `class_key`, `source`, `created`) VALUES (%d, '%s', '%s', %d)",
		conf(c).table, math.floor(accountId), classKey, source, math.floor(now or 0))
end

function M.sqlDelete(accountId, classKey, c)
	if not validKey(classKey) then
		return nil
	end
	return string.format("DELETE FROM `%s` WHERE `account_id` = %d AND `class_key` = '%s'", conf(c).table,
		math.floor(accountId), classKey)
end

-- rows = list of {class_key = "..."} -> set {[key] = true}
function M.toSet(rows)
	local set = {}
	for _, r in ipairs(rows or {}) do
		if r.class_key and r.class_key ~= "" then
			set[r.class_key] = true
		end
	end
	return set
end

return M
