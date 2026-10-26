-- Transmog: pure logic (no engine calls), used by transmog.lua and server/tests/transmog_test.lua.
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
--   K.kindOf(cfg, t)                     kind key of an item type, or nil. t = {cid, pickupable, stackable, container,
--                                        fluid, weaponType, slotBits} (what transmog.lua reads from ItemType)
--   K.kindDef(cfg, key)                  the kinds entry
--   K.setOfLook(cfg, id) / K.setByKey(cfg, key) / K.setOfUnlock(cfg, unlockName) / K.unlockName(set)
--   K.isExcluded(cfg, id)
--   K.unlockableFromItem(cfg, id, kind)  a look an item of this id unlocks by being carried (a kind, not excluded, not
--                                        a set's look)
--   K.ownedLooks(cfg, lookIds, setKeys)  set of look ids the account has: its rows + the looks of its sets
--   K.progress(cfg, catalogue, owned)    {kinds = {[key] = {unlocked, total}}, unlocked, total}; catalogue[id] = kind
--   K.fee(cfg, itemLevel, action)        gold for "apply" / "remove"
--   K.applyCheck(cfg, a)                 nil, fee  or  reason. a = {item = {id, kind, look, level}, look = {id, kind},
--                                        owned = set, money = gold the player can pay}
--   K.removeCheck(cfg, a)                nil, fee  or  reason. a = {item = {id, look, level}, money}
--   K.setSyncs(cfg, facts, ownedSets)    keys of the achievement / season sets the account now has but no row yet;
--                                        facts.hasAchievement(id), facts.seasonOwned(key)
--   K.setHow(set)                        the window's line on how a set is obtained
--   K.validate(cfg, describe, shopConfig, achievementsData) -> problems, warnings
--   K.sqlCreate(cfg) / K.sqlSelectLooks / K.sqlSelectSets / K.sqlInsertLook / K.sqlInsertSet / K.sqlDeleteSet
--   K.request(msg)                       a decoded client message -> action, data (nil when malformed)

ChaosTransmogCore = ChaosTransmogCore or {}
local K = ChaosTransmogCore

-- boss: a rare personal drop of a boss (exclusives.lua grants it through ChaosTransmog.grantSet; boss = the boss's name)
local SOURCES = {store = true, achievement = true, season = true, exclusive = true, boss = true}
K.SOURCES = SOURCES

local function hasBit(value, bitValue)
	value = tonumber(value) or 0
	return math.floor(value / bitValue) % 2 == 1
end

function K.kindDef(cfg, key)
	for _, k in ipairs(cfg.kinds) do
		if k.key == key then
			return k
		end
	end
	return nil
end

function K.kindOf(cfg, t)
	if type(t) ~= "table" or (tonumber(t.cid) or 0) <= 0 or not t.pickupable or t.stackable or t.container or t.fluid then
		return nil
	end
	local wt = tonumber(t.weaponType) or 0
	if wt > 0 then
		for _, k in ipairs(cfg.kinds) do
			if k.weaponType == wt then
				return k.key
			end
		end
		return nil -- ammunition and other weapon types
	end
	for _, k in ipairs(cfg.kinds) do
		if k.slotBit and hasBit(t.slotBits, k.slotBit) then
			return k.key
		end
	end
	return nil
end

-- ---------------------------------------------------------------- sets
local setIndexCache = setmetatable({}, {__mode = "k"})
local function setIndex(cfg)
	local idx = setIndexCache[cfg]
	if not idx then
		idx = {byLook = {}, byKey = {}}
		for _, s in ipairs(cfg.sets or {}) do
			idx.byKey[s.key] = s
			for _, id in ipairs(s.looks or {}) do
				idx.byLook[id] = idx.byLook[id] or s
			end
		end
		setIndexCache[cfg] = idx
	end
	return idx
end

function K.setOfLook(cfg, id)
	return setIndex(cfg).byLook[tonumber(id) or -1]
end

function K.setByKey(cfg, key)
	return setIndex(cfg).byKey[key or ""]
end

function K.unlockName(set)
	return "transmog_" .. set.key
end

function K.setOfUnlock(cfg, unlockName)
	local key = type(unlockName) == "string" and unlockName:match("^transmog_([%w_]+)$")
	local s = key and K.setByKey(cfg, key)
	if s and s.source == "store" then
		return s
	end
	return nil
end

function K.setHow(set)
	if set.source == "store" then
		return "Store, " .. tostring(set.price or "?") .. " Chaos Coins"
	elseif set.source == "achievement" then
		return set.how or "Achievement reward"
	elseif set.source == "boss" then
		return "Boss: " .. tostring(set.boss or "a boss") .. " (rare drop)"
	elseif set.source == "season" then
		return "Season reward"
	end
	return "Exclusive: events and rewards"
end

-- ---------------------------------------------------------------- catalogue and ownership
function K.isExcluded(cfg, id)
	id = tonumber(id) or 0
	for _, x in ipairs(cfg.exclude or {}) do
		if x == id then
			return true
		end
	end
	for _, r in ipairs(cfg.excludeRanges or {}) do
		if id >= r[1] and id <= r[2] then
			return true
		end
	end
	return false
end

function K.unlockableFromItem(cfg, id, kind)
	return kind ~= nil and not K.isExcluded(cfg, id) and K.setOfLook(cfg, id) == nil
end

function K.ownedLooks(cfg, lookIds, setKeys)
	local owned = {}
	for id in pairs(lookIds or {}) do
		owned[id] = true
	end
	for key in pairs(setKeys or {}) do
		local s = K.setByKey(cfg, key)
		for _, id in ipairs(s and s.looks or {}) do
			owned[id] = true
		end
	end
	return owned
end

function K.progress(cfg, catalogue, owned)
	local out = {kinds = {}, unlocked = 0, total = 0}
	for _, k in ipairs(cfg.kinds) do
		out.kinds[k.key] = {unlocked = 0, total = 0}
	end
	for id, kind in pairs(catalogue) do
		local p = out.kinds[kind]
		if p then
			p.total = p.total + 1
			out.total = out.total + 1
			if owned[id] then
				p.unlocked = p.unlocked + 1
				out.unlocked = out.unlocked + 1
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- apply / remove
function K.fee(cfg, itemLevel, action)
	local f = cfg.fee or {}
	if action == "remove" then
		return math.max(0, math.floor(tonumber(f.remove) or 0))
	end
	local level = math.max(0, math.floor(tonumber(itemLevel) or 0))
	local fee = (tonumber(f.apply) or 0) + (tonumber(f.perItemLevel) or 0) * level
	if f.maxApply then
		fee = math.min(fee, f.maxApply)
	end
	return math.max(0, math.floor(fee))
end

function K.applyCheck(cfg, a)
	local item, look = a.item, a.look
	if not item or not item.id then
		return "There is no item in that slot."
	end
	if not item.kind then
		return "This item cannot change its look."
	end
	if not look or not look.id or not look.kind then
		return "Unknown appearance."
	end
	if look.kind ~= item.kind then
		local def = K.kindDef(cfg, item.kind)
		return string.format("That appearance is not of the same kind (%s).", def and def.name or item.kind)
	end
	if look.id == item.id then
		return "That is the item's own look: use Remove to restore it."
	end
	if (tonumber(item.look) or 0) == look.id then
		return "The item already has that look."
	end
	if not (a.owned or {})[look.id] then
		return "You have not unlocked that appearance yet."
	end
	local fee = K.fee(cfg, item.level, "apply")
	if (tonumber(a.money) or 0) < fee then
		return string.format("You need %d gold (backpack and bank) to change the look.", fee)
	end
	return nil, fee
end

function K.removeCheck(cfg, a)
	local item = a.item
	if not item or not item.id then
		return "There is no item in that slot."
	end
	if (tonumber(item.look) or 0) <= 0 then
		return "The item already shows its own look."
	end
	local fee = K.fee(cfg, item.level, "remove")
	if (tonumber(a.money) or 0) < fee then
		return string.format("You need %d gold to restore the look.", fee)
	end
	return nil, fee
end

-- ---------------------------------------------------------------- sets that come from other systems
function K.setSyncs(cfg, facts, ownedSets)
	local out = {}
	for _, s in ipairs(cfg.sets or {}) do
		if not (ownedSets or {})[s.key] then
			if s.source == "achievement" and s.achievement and facts.hasAchievement and facts.hasAchievement(s.achievement) then
				out[#out + 1] = s.key
			elseif s.source == "season" and facts.seasonOwned and facts.seasonOwned(s.key) then
				out[#out + 1] = s.key
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- consistency
-- describe(id) -> {kind, name} of an item type, or nil when the id does not exist (transmog.lua: from ItemType; the
-- test: from items.xml). shopConfig and achievementsData are optional.
function K.validate(cfg, describe, shopConfig, achievementsData)
	local problems, warnings = {}, {}
	local function bad(fmt, ...)
		problems[#problems + 1] = string.format(fmt, ...)
	end
	if type(cfg.opcode) ~= "number" then
		bad("opcode missing")
	end
	local kinds = {}
	for _, k in ipairs(cfg.kinds or {}) do
		if kinds[k.key] then
			bad("kind %s twice", k.key)
		end
		kinds[k.key] = true
		if not k.weaponType and not k.slotBit then
			bad("kind %s has neither weaponType nor slotBit", k.key)
		end
	end
	local keys, lookOwner = {}, {}
	for _, s in ipairs(cfg.sets or {}) do
		if type(s.key) ~= "string" or not s.key:match("^[%w_]+$") then
			bad("set key %s", tostring(s.key))
		elseif keys[s.key] then
			bad("set %s twice", s.key)
		end
		keys[s.key or ""] = true
		if not SOURCES[s.source or ""] then
			bad("set %s: unknown source %s", tostring(s.key), tostring(s.source))
		end
		if type(s.name) ~= "string" or s.name == "" then
			bad("set %s has no name", tostring(s.key))
		end
		if type(s.looks) ~= "table" or #s.looks == 0 then
			bad("set %s has no looks", tostring(s.key))
		end
		for _, id in ipairs(s.looks or {}) do
			if lookOwner[id] then
				bad("look %d in sets %s and %s", id, lookOwner[id], tostring(s.key))
			end
			lookOwner[id] = s.key
			if describe then
				local d = describe(id)
				if not d then
					bad("set %s: item %d does not exist", tostring(s.key), id)
				elseif not d.kind then
					bad("set %s: item %d (%s) has no transmog kind", tostring(s.key), id, tostring(d.name))
				end
			end
		end
		if s.source == "store" and (tonumber(s.price) or 0) <= 0 then
			bad("store set %s has no price", tostring(s.key))
		end
		if s.source == "boss" and (type(s.boss) ~= "string" or s.boss == "") then
			bad("boss set %s names no boss", tostring(s.key))
		end
		if s.source == "achievement" then
			if type(s.achievement) ~= "string" then
				bad("achievement set %s names no achievement", tostring(s.key))
			elseif achievementsData then
				local found = false
				for _, a in ipairs(achievementsData.list or {}) do
					if a.id == s.achievement then
						found = true
					end
				end
				if not found then
					bad("set %s: achievement %s does not exist", tostring(s.key), s.achievement)
				end
			end
		end
	end
	-- the store offers (shop_config.lua): a store set's offer must carry the set's price; a missing offer only warns
	if shopConfig then
		local offers = {}
		for _, cat in ipairs(shopConfig.categories or {}) do
			for _, o in ipairs(cat.offers or {}) do
				if o.kind == "unlock" and type(o.unlock) == "string" and o.unlock:match("^transmog_") then
					offers[o.unlock] = o
				end
			end
		end
		for _, s in ipairs(cfg.sets or {}) do
			local o = offers[K.unlockName(s)]
			if s.source == "store" then
				if not o then
					warnings[#warnings + 1] = "store set " .. s.key .. " has no offer in shop_config.lua yet"
				elseif o.cost ~= s.price then
					bad("set %s: store price %s, config price %s", s.key, tostring(o.cost), tostring(s.price))
				end
			elseif o then
				bad("set %s is sold in the store but its source is %s", s.key, tostring(s.source))
			end
			offers[K.unlockName(s)] = nil
		end
		for name in pairs(offers) do
			bad("store offer %s names no transmog set", name)
		end
	end
	return problems, warnings
end

-- ---------------------------------------------------------------- SQL
local function num(v)
	return string.format("%d", math.floor(tonumber(v) or 0))
end

function K.sqlCreate(cfg)
	return {
		"CREATE TABLE IF NOT EXISTS `" .. cfg.tables.looks .. "` (`account_id` int(11) NOT NULL, `item_id` int(11) NOT NULL, "
			.. "`created` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `item_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
		"CREATE TABLE IF NOT EXISTS `" .. cfg.tables.sets .. "` (`account_id` int(11) NOT NULL, `set_key` varchar(32) NOT NULL, "
			.. "`source` varchar(32) NOT NULL DEFAULT '', `created` bigint(20) NOT NULL DEFAULT 0, "
			.. "PRIMARY KEY (`account_id`, `set_key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
	}
end

function K.sqlSelectLooks(cfg, accountId)
	return "SELECT `item_id` FROM `" .. cfg.tables.looks .. "` WHERE `account_id` = " .. num(accountId)
end

function K.sqlSelectSets(cfg, accountId)
	return "SELECT `set_key` FROM `" .. cfg.tables.sets .. "` WHERE `account_id` = " .. num(accountId)
end

function K.sqlInsertLook(cfg, accountId, itemId, now)
	return "INSERT IGNORE INTO `" .. cfg.tables.looks .. "` (`account_id`, `item_id`, `created`) VALUES (" .. num(accountId)
		.. ", " .. num(itemId) .. ", " .. num(now) .. ")"
end

-- the key and source are checked against the config before (only [%w_] characters)
function K.sqlInsertSet(cfg, accountId, key, source, now)
	return "INSERT IGNORE INTO `" .. cfg.tables.sets .. "` (`account_id`, `set_key`, `source`, `created`) VALUES (" .. num(accountId)
		.. ", '" .. tostring(key):gsub("[^%w_]", "") .. "', '" .. tostring(source or ""):gsub("[^%w_]", "") .. "', " .. num(now) .. ")"
end

function K.sqlDeleteSet(cfg, accountId, key)
	return "DELETE FROM `" .. cfg.tables.sets .. "` WHERE `account_id` = " .. num(accountId) .. " AND `set_key` = '"
		.. tostring(key):gsub("[^%w_]", "") .. "'"
end

-- ---------------------------------------------------------------- requests
local ACTIONS = {open = true, looks = true, apply = true, remove = true, close = true}
function K.request(msg)
	if type(msg) ~= "table" or not ACTIONS[msg.action] then
		return nil
	end
	local d = type(msg.data) == "table" and msg.data or {}
	local out = {}
	if msg.action == "looks" then
		if type(d.kind) ~= "string" then
			return nil
		end
		out.kind = d.kind
	elseif msg.action == "apply" or msg.action == "remove" then
		out.slot = math.floor(tonumber(d.slot) or 0)
		if out.slot < 1 or out.slot > 10 then
			return nil
		end
		if msg.action == "apply" then
			out.look = math.floor(tonumber(d.look) or 0)
			if out.look <= 0 then
				return nil
			end
		end
	end
	return msg.action, out
end
