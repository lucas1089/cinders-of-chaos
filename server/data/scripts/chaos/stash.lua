-- The stash (game_stash, extended opcode ChaosOpcodes.stash = 110): the one item storage of a character. The depot
-- boxes retire into it (stash_config.lua `depot`). Rules: stash_core.lua; numbers and texts: stash_config.lua; tests:
-- server/tests/stash_test.lua (the rules, the journal with crashes, this file against a mocked engine). Overview:
-- server/README.md "Stash".
--
--   deposit   in town (a protection zone or a hideout) for everybody; from anywhere (also mid-hunt) with the remote
--             deposit unlock (store, or while the Chaos Pact runs; stash_core.lua K.canDeposit): drag an item onto the
--             window, Stow Everything, scripts (ChaosStash.storeItem). The depot migration is not a deposit of the player
--   withdraw  only in a protection zone or inside a hideout, for everybody (K.canWithdraw); the client greys both out
--   items     a plain stack (nothing but id and count) merges by type into chaos_stash (player_id, item_id) -> count, tab;
--             any other item is one row of chaos_stash_items with every attribute (item_codec.lua: the engine's blob
--             of patch 0017, else the key list) and comes back exactly as it went in
--   tabs      general tabs (any item) and affinity tabs (one class each: weapons, armor, jewellery, supplies, creature
--             products, materials, orbs, gems, keys, collectibles); a deposit goes to the first owned affinity tab of its
--             class with room, else a general tab. Limits per account (pact_config.lua stashTabs, the extras bought,
--             the Pact, achievements). Withdraw-only tabs keep their items; nothing is deleted when a limit shrinks.
--   journal   every deposit and withdrawal is first a row in a journal state with a serial, saved with the character in
--             one transaction (stash_core.lua "The journal"): no item lost or doubled by a crash or a failed save
--   depot     at the first depot locker opening (the engine saves the depot only once one was opened this session),
--             every item of the character's depots moves into the stash; what fits no tab goes to the withdraw-only
--             Old depot tab. tools/migrate_depot_stash.py does the same offline for every character.
--
-- Client contract (client/overlay/modules/game_stash/stash.lua), {"action":"Stash","data":{"make":...}} both ways:
--   client -> server data.make:
--     SendCategories {sendBlocks=true}  -> addCategorys + forceBlockList
--     SendItems                         -> tabs + addItems stream
--     Stash {Pos={x,y,z,stackpos}, UpdateList=bool}           deposit one item from the map or a container
--     Redeem {item=<server id>, count=N}                       withdraw from a plain stack
--     Redeem {row=<row id>}                                    withdraw one stored item
--     ChangeStash {Pos={...}}           toggle the item type on the "never stash" list
--     ChangeStash {RemoveUI=true, itemId=<server id>}          remove from that list
--     StashAllRequest                   Stow Everything
--     Open                              -> Toggle
--   server -> client data.make:
--     tabs {tabs=[{id, name, used, size, locked, affinity, icon, old, source}], limit, pact, tabSize, canWithdraw,
--           withdrawWhy = "pz" | "hideout" | nil, canDeposit, depositWhy = "pz" | "hideout" | "remote" | nil,
--           remote = "bought" | "pact" | nil (the remote deposit unlock)}
--     addItems {isFirst, isLast, items=[{sprite, count, name, tooltip, id, uniqueId, typee, tab, row?, rarity?}]}
--     addCategorys {list=[{name, value}], remote}   forceBlockList {items}   addBlockItem {status, itemData}
--     Toggle {remote}                   StashAll {status}  (the progress overlay)
--     StowReport {stowed, kept, reasons=[{reason, label, count, names}]}
--     access {canWithdraw} | {canDeposit}   after a refused withdrawal or deposit
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/stash_core.lua")
if not ChaosItemCodec then
	dofile("data/scripts/chaos/item_codec.lua")
end
Chaos.stashConfig = dofile("data/scripts/chaos/stash_config.lua")

ChaosStash = ChaosStash or {}
local S = ChaosStash
local Core = ChaosStashCore
local IC = ChaosItemCodec
local cfg = Chaos.stashConfig
local OPCODE = ChaosOpcodes.stash
local T = (Chaos.tables and Chaos.tables.stash) or cfg.tables.stash
local TB = (Chaos.tables and Chaos.tables.stashBlock) or cfg.tables.block
local TI = cfg.tables.items
local TL = cfg.tables.log
local M = cfg.messages
local NOERR = RETURNVALUE_NOERROR or 0

local function int(v)
	return math.floor(tonumber(v) or 0)
end

local function esc(s)
	return db.escapeString(tostring(s or ""))
end

local function warn(text)
	print("[Chaos stash] " .. text)
end

-- every engine call guarded: tests and scripts hand over items with fewer methods
local function call(obj, method, ...)
	local f = obj and obj[method]
	if not f then
		return nil
	end
	local ok, v = pcall(f, obj, ...)
	if ok then
		return v
	end
	return nil
end

local function custom(item, key)
	local v = call(item, "getCustomAttribute", key)
	if type(v) == "userdata" or type(v) == "table" then
		local ok, n = pcall(function() return v.value end)
		return ok and n or nil
	end
	return v
end

-- the database access, in one place (the tests swap it for an in-memory one and read the real queries)
local store = {}
S.store = store

-- ---------------------------------------------------------------- tables
S.SCHEMA = {
	"ALTER TABLE `" .. T .. "` ADD COLUMN IF NOT EXISTS `tab` smallint(5) unsigned NOT NULL DEFAULT 0",
	"CREATE TABLE IF NOT EXISTS `" .. TI .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL, " ..
		"`item_id` int(11) NOT NULL, `count` int(11) NOT NULL DEFAULT 1, `codec` varchar(8) NOT NULL DEFAULT 'blob', " ..
		"`data` mediumtext NOT NULL, `tab` smallint(5) unsigned NOT NULL DEFAULT 0, `classes` varchar(96) NOT NULL DEFAULT '', " ..
		"`name` varchar(96) NOT NULL DEFAULT '', `info` text NOT NULL, `rarity` tinyint(3) unsigned NOT NULL DEFAULT 0, " ..
		"`state` tinyint(3) unsigned NOT NULL DEFAULT 0, `seq` int(11) NOT NULL DEFAULT 0, `source` varchar(16) NOT NULL DEFAULT '', " ..
		"`created_at` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `player_state` (`player_id`, `state`), " ..
		"CONSTRAINT `chaos_stash_items_players_fk` FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `" .. TL .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL, " ..
		"`action` varchar(16) NOT NULL, `moved` int(11) NOT NULL DEFAULT 0, `overflow` int(11) NOT NULL DEFAULT 0, " ..
		"`kept` int(11) NOT NULL DEFAULT 0, `detail` varchar(255) NOT NULL DEFAULT '', `at` bigint(20) NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`id`), KEY `player_id` (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
}
pcall(function()
	for _, q in ipairs(S.SCHEMA) do
		db.query(q)
	end
end)

local function transaction(fn)
	if not db.query("START TRANSACTION") then
		return false
	end
	local ok, res = pcall(fn)
	if ok and res then
		if db.query("COMMIT") then
			return true
		end
	elseif not ok then
		warn("transaction: " .. tostring(res))
	end
	db.query("ROLLBACK")
	return false
end

local function lastId()
	if db.lastInsertId then
		local ok, id = pcall(db.lastInsertId)
		if ok and tonumber(id) then
			return tonumber(id)
		end
	end
	local r = Chaos.select("SELECT LAST_INSERT_ID() AS `id`", {{"id", "n"}})[1]
	return r and r.id or 0
end

-- ---------------------------------------------------------------- item facts
local sets
local function idSets()
	if sets then
		return sets
	end
	sets = {orbs = {}, keys = {}, material = {}, product = {}, food = {}, cosmetic = {}}
	local ok, pc = pcall(dofile, "data/scripts/chaos/pouches_config.lua")
	if ok and type(pc) == "table" then
		for _, id in ipairs(pc.orbIds or {}) do
			sets.orbs[id] = true
		end
		for _, id in ipairs(pc.omenIds or {}) do
			sets.keys[id] = true
		end
		sets.riftKey = pc.riftKey
	end
	for _, id in ipairs((ChaosLootFilterConfig and ChaosLootFilterConfig.orbIds) or {}) do
		sets.orbs[id] = true
	end
	local okP, prof = pcall(dofile, "data/scripts/chaos/professions_config.lua")
	if okP and type(prof) == "table" then
		for _, m in ipairs(prof.materials or {}) do
			if m.id then
				sets.material[m.id] = true
			end
		end
	end
	for _, id in ipairs(cfg.materialIds or {}) do
		sets.material[id] = true
	end
	for _, id in ipairs(cfg.cosmeticIds or {}) do
		sets.cosmetic[id] = true
	end
	local pk = ChaosPackItems
	for _, id in pairs((pk and pk.products) or {}) do
		sets.product[id] = true
	end
	for id in pairs((pk and pk.foods) or {}) do
		sets.food[id] = true
	end
	return sets
end
S.idSets = function()
	sets = nil
	return idSets()
end

-- "orbs" | "gems" | "keys" | nil: the special kinds (the Orbs Pouch ids, ChaosGems, omen fragments and keys)
function S.kindOf(id)
	local k = idSets()
	if k.orbs[id] then
		return "orbs"
	end
	if ChaosGems and ChaosGems.isGem and ChaosGems.isGem(id) then
		return "gems"
	end
	if k.keys[id] then
		return "keys"
	end
	return nil
end

local typeCache = {}
-- the facts of an item type (cached per id)
function S.typeFacts(id)
	id = int(id)
	local f = typeCache[id]
	if f then
		return f
	end
	local it = ItemType(id)
	f = {id = id, name = tostring(call(it, "getName") or ""):lower()}
	f.stackable = call(it, "isStackable") == true
	f.container = call(it, "isContainer") == true
	f.pickupable = call(it, "isPickupable") ~= false
	f.movable = call(it, "isMovable") ~= false
	f.rune = call(it, "isRune") == true
	f.fluid = call(it, "isFluidContainer") == true
	local weapon = tonumber(call(it, "getWeaponType")) or 0
	f.ammo = (WEAPON_AMMO ~= nil and weapon == WEAPON_AMMO) or (tonumber(call(it, "getAmmoType")) or 0) ~= 0
	if not f.ammo and ChaosItemMods and ChaosItemMods.kindOfType then
		local ok, kind = pcall(ChaosItemMods.kindOfType, it)
		f.gear = ok and kind or nil
	end
	f.key = ITEM_TYPE_KEY ~= nil and tonumber(call(it, "getType")) == ITEM_TYPE_KEY
	local k = idSets()
	f.kind = S.kindOf(id)
	f.material = k.material[id] == true or (ChaosItemPrices and ChaosItemPrices.unsellable and ChaosItemPrices.unsellable(id) == "broker") or nil
	f.product = k.product[id] or nil
	f.cosmetic = k.cosmetic[id] or nil
	if k.food[id] then
		f.food = true
	end
	f.price = ChaosItemPrices and ChaosItemPrices.basePrice and (tonumber(ChaosItemPrices.basePrice(id)) or 0) or 0
	f.clientId = call(it, "getClientId") or id
	f.typeName = call(it, "getName") or ("item " .. id)
	typeCache[id] = f
	return f
end

local blockCache = {} -- guid -> {[item id] = true}
local function blockedSet(guid)
	local b = blockCache[guid]
	if not b then
		b = {}
		for _, id in ipairs(store.blocked(guid)) do
			b[id] = true
		end
		blockCache[guid] = b
	end
	return b
end

local function isBound(item)
	if call(item, "isStoreItem") == true or custom(item, "chaos_storebound") ~= nil then
		return true
	end
	if ChaosDeathKeep and ChaosDeathKeep.kept then
		local ok, kept = pcall(ChaosDeathKeep.kept, item)
		return ok and kept == true
	end
	return false
end

-- the facts of one item the player holds (stash_core.lua)
function S.factsOf(player, item)
	local id = int(call(item, "getId"))
	local f = {}
	for k, v in pairs(S.typeFacts(id)) do
		f[k] = v
	end
	f.count = f.stackable and math.max(1, int(call(item, "getCount"))) or 1
	f.container = f.container or call(item, "isContainer") == true
	f.contents = f.container and int(call(item, "getSize")) or 0
	f.actionId = int(call(item, "getActionId"))
	if f.actionId == 0 and ITEM_ATTRIBUTE_ACTIONID and call(item, "hasAttribute", ITEM_ATTRIBUTE_ACTIONID) then
		f.actionId = int(call(item, "getAttribute", ITEM_ATTRIBUTE_ACTIONID))
	end
	if ITEM_ATTRIBUTE_UNIQUEID and call(item, "hasAttribute", ITEM_ATTRIBUTE_UNIQUEID) then
		f.uniqueId = int(call(item, "getAttribute", ITEM_ATTRIBUTE_UNIQUEID))
	end
	local rk = idSets().riftKey
	f.riftKey = custom(item, "rift_tier") ~= nil or (rk ~= nil and id == rk.itemId and f.actionId == rk.actionId) or nil
	f.bound = isBound(item)
	f.locked = int(custom(item, "chaos_locked")) ~= 0
	f.rarity = ChaosRarity.canon(int(custom(item, "rarity"))) % ChaosRarity.UNIQUE -- a stored id (an old 6 .. 15 is the rarity it became)
	f.blocked = player and blockedSet(player:getGuid())[id] == true or false
	f.plain = f.stackable and IC.isPlain(item)
	local name = call(item, "getName")
	if type(name) == "string" and name ~= "" then
		f.display = name
	end
	return f
end

-- the look text of a stored item (kept with the row: the list never re-creates items)
local function infoOf(item, f)
	local text = call(item, "getDescription", 0)
	if type(text) ~= "string" or text == "" then
		text = f.display or f.typeName
	end
	return text:sub(1, 1000)
end

-- ---------------------------------------------------------------- the account's room
local achCache = {} -- account id -> {set, at}
local function wantedAchievements()
	local ids = {}
	for _, id in ipairs(cfg.generalAchievements or {}) do
		ids[#ids + 1] = id
	end
	for _, a in ipairs(cfg.affinities) do
		for _, id in ipairs(a.achievements or {}) do
			ids[#ids + 1] = id
		end
	end
	return ids
end

local function achievementsOf(accountId, fresh)
	local c = achCache[accountId]
	if c and not fresh and os.time() - c.at < 60 then
		return c.set
	end
	local set, list = {}, {}
	for _, id in ipairs(wantedAchievements()) do
		list[#list + 1] = id
	end
	if #list > 0 then
		for _, id in ipairs(store.achievements(accountId, list)) do
			set[id] = true
		end
	end
	achCache[accountId] = {set = set, at = os.time()}
	return set
end

local pactCfg
local function pactConfig()
	if not pactCfg then
		pactCfg = Chaos.pactConfig
		if not pactCfg then
			local ok, res = pcall(dofile, "data/scripts/chaos/pact_config.lua")
			pactCfg = ok and res or {limits = {}}
		end
	end
	return pactCfg
end

function S.viewOf(player, fresh)
	local accountId = int(call(player, "getAccountId"))
	local pc = pactConfig()
	local ctx = {extras = {}, pact = false}
	local limits = pc.limits or {}
	ctx.stashTabs = limits.stashTabs and limits.stashTabs.free or 0
	if ChaosPact and ChaosPact.limit then
		local ok, lim = pcall(ChaosPact.limit, player, "stashTabs")
		if ok and lim then
			ctx.stashTabs = lim
		end
		local okS, st = pcall(ChaosPact.state, accountId)
		if okS and st then
			ctx.extras = st.extras or {}
		end
		local okA, active = pcall(ChaosPact.active, player)
		ctx.pact = okA and active == true
	end
	local dt = limits.depotTabs
	ctx.depotTabs = math.min(int(ctx.extras.depotTabs), dt and int(dt.maxExtra) or 0)
	ctx.achievements = achievementsOf(accountId, fresh)
	return Core.view(cfg, ctx)
end

-- ---------------------------------------------------------------- the store (database access)

function store.plainRows(guid)
	return Chaos.select("SELECT `item_id`, `count`, `tab` FROM `" .. T .. "` WHERE `player_id` = " .. int(guid) .. " AND `count` > 0",
		{{"item_id", "n"}, {"count", "n"}, {"tab", "n"}})
end

function store.itemRows(guid)
	return Chaos.select("SELECT `id`, `item_id`, `count`, `tab`, `classes`, `name`, `info`, `rarity`, `source` FROM `" .. TI ..
		"` WHERE `player_id` = " .. int(guid) .. " AND `state` IN (0, 9) AND `codec` <> 'plain'",
		{{"id", "n"}, {"item_id", "n"}, {"count", "n"}, {"tab", "n"}, {"classes", "s"}, {"name", "s"}, {"info", "s"},
			{"rarity", "n"}, {"source", "s"}})
end

function store.itemRow(guid, rowId)
	return Chaos.select("SELECT `id`, `item_id`, `count`, `codec`, `data`, `tab`, `name` FROM `" .. TI .. "` WHERE `id` = " .. int(rowId) ..
		" AND `player_id` = " .. int(guid) .. " AND `state` = 0",
		{{"id", "n"}, {"item_id", "n"}, {"count", "n"}, {"codec", "s"}, {"data", "s"}, {"tab", "n"}, {"name", "s"}})[1]
end

function store.plainCount(guid, itemId)
	local r = Chaos.select("SELECT `count`, `tab` FROM `" .. T .. "` WHERE `player_id` = " .. int(guid) .. " AND `item_id` = " .. int(itemId),
		{{"count", "n"}, {"tab", "n"}})[1]
	return r and r.count or 0, r and r.tab or 0
end

function store.pending(guid)
	return Chaos.select("SELECT `id`, `state`, `seq`, `item_id`, `count`, `codec`, `tab` FROM `" .. TI .. "` WHERE `player_id` = " ..
		int(guid) .. " AND `state` IN (8, 9)",
		{{"id", "n"}, {"state", "n"}, {"seq", "n"}, {"item_id", "n"}, {"count", "n"}, {"codec", "s"}, {"tab", "n"}})
end

function store.setTab(guid, e)
	if e.row then
		return db.query("UPDATE `" .. TI .. "` SET `tab` = " .. int(e.tab) .. " WHERE `id` = " .. int(e.row) .. " AND `player_id` = " .. int(guid))
	end
	return db.query("UPDATE `" .. T .. "` SET `tab` = " .. int(e.tab) .. " WHERE `player_id` = " .. int(guid) .. " AND `item_id` = " .. int(e.item))
end

-- a journal row (state, serial) for a deposit (rec.codec / data: the item; "plain" for a plain stack) or a withdrawal
function store.insert(guid, rec, state, seq)
	local ok = db.query(string.format("INSERT INTO `%s` (`player_id`, `item_id`, `count`, `codec`, `data`, `tab`, `classes`, `name`, " ..
		"`info`, `rarity`, `state`, `seq`, `source`, `created_at`) VALUES (%d, %d, %d, %s, %s, %d, %s, %s, %s, %d, %d, %d, %s, %d)",
		TI, int(guid), int(rec.itemId), int(rec.count), esc(rec.codec or "plain"), esc(rec.data or ""), int(rec.tab), esc(rec.classes or ""),
		esc((rec.name or ""):sub(1, 96)), esc(rec.info or ""), math.max(0, math.min(255, int(rec.rarity))), int(state), int(seq),
		esc(rec.source or "deposit"), os.time()))
	if not ok then
		return nil
	end
	local id = lastId()
	return id > 0 and id or nil
end

-- the depositing rows of a serial become entries: plain stacks merge into chaos_stash (moving a stack's entry into the
-- tab of the deposit), the others turn active. One transaction.
function store.activate(guid, seq)
	return transaction(function()
		local g, s = int(guid), int(seq)
		return db.query(string.format("INSERT INTO `%s` (`player_id`, `item_id`, `count`, `tab`) SELECT `player_id`, `item_id`, " ..
			"SUM(`count`), MAX(`tab`) FROM `%s` WHERE `player_id` = %d AND `seq` = %d AND `state` = 9 AND `codec` = 'plain' " ..
			"GROUP BY `player_id`, `item_id` ON DUPLICATE KEY UPDATE `count` = `%s`.`count` + VALUES(`count`), `tab` = VALUES(`tab`)",
			T, TI, g, s, T))
			and db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `seq` = %d AND `state` = 9 AND `codec` = 'plain'", TI, g, s))
			and db.query(string.format("UPDATE `%s` SET `state` = 0 WHERE `player_id` = %d AND `seq` = %d AND `state` = 9", TI, g, s))
	end)
end

function store.drop(guid, id, state)
	return db.query(string.format("DELETE FROM `%s` WHERE `id` = %d AND `player_id` = %d AND `state` = %d", TI, int(id), int(guid), int(state)))
end

-- a plain stack: the amount leaves its entry and becomes a taking row; a stored item: its row turns taking
function store.take(guid, rec, seq)
	local g = int(guid)
	if rec.plain then
		local id
		local ok = transaction(function()
			local have = store.plainCount(g, rec.itemId)
			if have < int(rec.count) then
				return false
			end
			if not db.query(string.format("UPDATE `%s` SET `count` = `count` - %d WHERE `player_id` = %d AND `item_id` = %d",
					T, int(rec.count), g, int(rec.itemId))) then
				return false
			end
			id = store.insert(g, rec, Core.STATE_TAKING, seq)
			return id ~= nil and db.query(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `item_id` = %d AND `count` <= 0",
				T, g, int(rec.itemId)))
		end)
		if ok then
			rec.id = id
		end
		return ok
	end
	if not db.query(string.format("UPDATE `%s` SET `state` = 8, `seq` = %d WHERE `id` = %d AND `player_id` = %d AND `state` = 0",
			TI, int(seq), int(rec.id), g)) then
		return false
	end
	local r = Chaos.select(string.format("SELECT `state` FROM `%s` WHERE `id` = %d AND `player_id` = %d", TI, int(rec.id), g), {{"state", "n"}})[1]
	return r ~= nil and r.state == Core.STATE_TAKING
end

-- a taking row becomes an entry again
function store.untake(guid, rec)
	local g = int(guid)
	if rec.plain then
		return transaction(function()
			return db.query(string.format("INSERT INTO `%s` (`player_id`, `item_id`, `count`, `tab`) VALUES (%d, %d, %d, %d) " ..
				"ON DUPLICATE KEY UPDATE `count` = `count` + %d", T, g, int(rec.itemId), int(rec.count), int(rec.tab), int(rec.count)))
				and store.drop(g, rec.id, Core.STATE_TAKING)
		end)
	end
	return db.query(string.format("UPDATE `%s` SET `state` = 0 WHERE `id` = %d AND `player_id` = %d AND `state` = 8", TI, int(rec.id), g))
end

-- a plain withdrawal that only partly fitted: the taking row keeps what was given, the rest goes back
function store.shrinkTake(guid, rec, given)
	local g = int(guid)
	local back = int(rec.count) - int(given)
	return transaction(function()
		return db.query(string.format("UPDATE `%s` SET `count` = %d WHERE `id` = %d AND `player_id` = %d AND `state` = 8", TI, int(given),
			int(rec.id), g))
			and db.query(string.format("INSERT INTO `%s` (`player_id`, `item_id`, `count`, `tab`) VALUES (%d, %d, %d, %d) " ..
				"ON DUPLICATE KEY UPDATE `count` = `count` + %d", T, g, int(rec.itemId), back, int(rec.tab), back))
	end)
end

function store.blocked(guid)
	local out = {}
	for _, r in ipairs(Chaos.select("SELECT `item_id` FROM `" .. TB .. "` WHERE `player_id` = " .. int(guid), {{"item_id", "n"}})) do
		out[#out + 1] = r.item_id
	end
	return out
end

function store.block(guid, itemId, on)
	if on then
		return db.query("INSERT IGNORE INTO `" .. TB .. "` (`player_id`, `item_id`) VALUES (" .. int(guid) .. ", " .. int(itemId) .. ")")
	end
	return db.query("DELETE FROM `" .. TB .. "` WHERE `player_id` = " .. int(guid) .. " AND `item_id` = " .. int(itemId))
end

-- the achievements of `ids` that any character of the account has
function store.achievements(accountId, ids)
	local list = {}
	for _, id in ipairs(ids) do
		list[#list + 1] = esc(id)
	end
	local out = {}
	if #list == 0 then
		return out
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT DISTINCT a.`achievement` AS `a` FROM `chaos_achievements` a JOIN `players` p " ..
			"ON p.`id` = a.`player_id` WHERE p.`account_id` = %d AND a.`achievement` IN (%s)", int(accountId), table.concat(list, ", ")),
			{{"a", "s"}})) do
		out[#out + 1] = r.a
	end
	return out
end

-- rows of the offline depot migration not described yet
function store.unclassified(guid, limit)
	return Chaos.select("SELECT `id`, `item_id`, `count`, `codec`, `data` FROM `" .. TI .. "` WHERE `player_id` = " .. int(guid) ..
		" AND `state` = 0 AND `source` = 'depot' AND `classes` = '' AND `name` = '' LIMIT " .. int(limit),
		{{"id", "n"}, {"item_id", "n"}, {"count", "n"}, {"codec", "s"}, {"data", "s"}})
end

-- a row that holds a plain stack joins chaos_stash (one transaction)
function store.mergeRow(guid, row)
	return transaction(function()
		return db.query(string.format("INSERT INTO `%s` (`player_id`, `item_id`, `count`, `tab`) VALUES (%d, %d, %d, 0) " ..
			"ON DUPLICATE KEY UPDATE `count` = `count` + %d", T, int(guid), int(row.item_id), int(row.count), int(row.count)))
			and store.drop(guid, row.id, Core.STATE_ACTIVE)
	end)
end

-- count: the tool copies the engine's count column, which is the charges or the fluid of an item that does not stack
-- (the blob keeps those); a whole item that does not stack counts 1
function store.describe(guid, rowId, classes, name, info, rarity, count)
	return db.query(string.format("UPDATE `%s` SET `classes` = %s, `name` = %s, `info` = %s, `rarity` = %d, `count` = %d WHERE `id` = %d " ..
		"AND `player_id` = %d", TI, esc(classes), esc((name or ""):sub(1, 96)), esc(info or ""), math.max(0, math.min(255, int(rarity))),
		math.max(1, int(count)), int(rowId), int(guid)))
end

function store.log(guid, action, moved, overflow, kept, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `action`, `moved`, `overflow`, `kept`, `detail`, `at`) VALUES " ..
		"(%d, %s, %d, %d, %d, %s, %d)", TL, int(guid), esc(action), int(moved), int(overflow), int(kept), esc((detail or ""):sub(1, 255)), os.time()))
end

-- ---------------------------------------------------------------- the journal, bound to a player (stash_core.lua env)
local function giveBack(player, rec)
	if rec.plain then
		player:addItem(rec.itemId, rec.count)
		return
	end
	local item = IC.decode(rec.itemId, rec.count, rec.codec, rec.data)
	if item then
		player:addItemEx(item, true)
	else
		warn(player:getName() .. ": a deposit could not be given back (item " .. tostring(rec.itemId) .. ")")
	end
end

function S.env(player)
	local guid = player:getGuid()
	local key = cfg.storage.seq
	local env = {}
	function env.getSeq()
		return math.max(0, int(player:getStorageValue(key)))
	end
	function env.setSeq(n)
		player:setStorageValue(key, n)
	end
	function env.pending()
		local out = {}
		for _, r in ipairs(store.pending(guid)) do
			out[#out + 1] = {id = r.id, state = r.state, seq = r.seq, itemId = r.item_id, count = r.count, plain = r.codec == "plain", tab = r.tab}
		end
		return out
	end
	function env.insert(rec, seq)
		return store.insert(guid, rec, Core.STATE_DEPOSITING, seq)
	end
	function env.remove(rec)
		if not rec.item then
			return false
		end
		-- a bag goes only empty (its contents are deposits of their own, before it): never an item inside it with it
		if call(rec.item, "isContainer") == true and int(call(rec.item, "getSize")) > 0 then
			return false
		end
		local ok, res = pcall(function()
			if rec.plain or call(rec.item, "isStackable") or S.typeFacts(rec.itemId).stackable then
				return rec.item:remove(rec.count)
			end
			return rec.item:remove()
		end)
		return ok and res ~= false
	end
	function env.restore(rec)
		giveBack(player, rec)
	end
	function env.activate(seq)
		return store.activate(guid, seq)
	end
	function env.drop(row)
		return store.drop(guid, row.id, Core.STATE_DEPOSITING)
	end
	function env.take(rec, seq)
		return store.take(guid, rec, seq)
	end
	function env.give(rec)
		if rec.plain then
			local given = Chaos.giveItem(player, rec.itemId, rec.count)
			if given <= 0 then
				return false
			end
			if given < rec.count then
				store.shrinkTake(guid, rec, given)
				rec.count = given
			end
			return true
		end
		local item, why = IC.decode(rec.itemId, rec.count, rec.codec, rec.data)
		if not item then
			rec.corrupt = why
			return false
		end
		local ret = call(player, "addItemEx", item, false)
		if ret ~= NOERR and ret ~= true then
			call(item, "remove")
			return false
		end
		rec.given = item
		return true
	end
	function env.ungive(rec)
		if rec.plain then
			player:removeItem(rec.itemId, rec.count)
		elseif rec.given then
			call(rec.given, "remove")
		end
	end
	function env.untake(rec)
		return store.untake(guid, rec)
	end
	function env.finish(rec)
		return store.drop(guid, rec.id, Core.STATE_TAKING)
	end
	function env.save()
		return Chaos.saveCharacter(player)
	end
	return env
end

-- ---------------------------------------------------------------- entries and layout
local CATEGORIES = {
	{name = "Runes", value = 3},
	{name = "Ammunition", value = 4},
	{name = "Potions", value = 5},
	{name = "Valuables", value = 6},
	{name = "Other", value = 7},
	{name = "Equipment", value = 8}
}
local VALUABLE_WORDS = {"coin", "coins", "gem", "gems", "pearl", "pearls", "amethyst", "topaz", "sapphire", "ruby", "emerald",
	"diamond", "amber", "nugget", "nuggets"}

local function categoryOf(f)
	if f.rune then
		return 3
	end
	if f.ammo then
		return 4
	end
	if f.gear then
		return 8
	end
	if f.fluid or Core.hasWord(f.name, {"potion", "potions"}) then
		return 5
	end
	if f.kind == "gems" or Core.hasWord(f.name, VALUABLE_WORDS) then
		return 6
	end
	return 7
end

-- every entry of the character ({key, tab, classes, plain | row}), laid out and the moves saved
function S.entries(player, view)
	local guid = player:getGuid()
	local entries = {}
	for _, r in ipairs(store.plainRows(guid)) do
		local f = S.typeFacts(r.item_id)
		entries[#entries + 1] = {key = "s" .. r.item_id, item = r.item_id, count = r.count, tab = r.tab, plain = true,
			classes = Core.classify(cfg, f)}
	end
	for _, r in ipairs(store.itemRows(guid)) do
		entries[#entries + 1] = {key = "i" .. r.id, row = r.id, item = r.item_id, count = r.count, tab = r.tab,
			classes = Core.unpackClasses(cfg, r.classes), name = r.name, info = r.info, rarity = r.rarity, source = r.source}
	end
	-- rows of the depot migration still at tab 0: the Old depot tab takes what fits no tab
	for _, e in ipairs(entries) do
		if int(e.tab) == 0 and e.source == "depot" then
			e.overflow = cfg.oldDepot.tab
		end
	end
	for _, m in ipairs(Core.layout(cfg, view, entries)) do
		for _, e in ipairs(entries) do
			if e.key == m.key then
				store.setTab(guid, e)
			end
		end
	end
	return entries
end

-- rows written by tools/migrate_depot_stash.py (source "depot", no classes yet): described from the item itself, plain
-- stacks merged into chaos_stash (one transaction per row); S.entries then places them (what fits nowhere: Old depot)
function S.normalize(player)
	local guid = player:getGuid()
	local rows = store.unclassified(guid, 500)
	for _, r in ipairs(rows) do
		local item = IC.decode(r.item_id, math.max(1, r.count), r.codec, r.data)
		if item then
			local f = S.factsOf(nil, item)
			if f.plain and f.stackable then
				store.mergeRow(guid, r)
			else
				store.describe(guid, r.id, Core.packClasses(Core.classify(cfg, f)) .. ",", f.display or f.typeName, infoOf(item, f), f.rarity,
					f.stackable and r.count or 1)
			end
			call(item, "remove")
		end
	end
	return #rows
end

-- ---------------------------------------------------------------- the client
local function send(player, data)
	Chaos.send(player, OPCODE, "Stash", data)
end

local function isRemote(player)
	return Chaos.stash.remoteForEveryone or player:getStorageValue(Chaos.storage.stashRemote) > 0
end

function S.place(player)
	local pos = player:getPosition()
	local tile = Tile(pos)
	local pz = tile ~= nil and TILESTATE_PROTECTIONZONE ~= nil and call(tile, "hasFlag", TILESTATE_PROTECTIONZONE) == true
	local hideout = ChaosHideout ~= nil and ChaosHideout.isInside ~= nil and ChaosHideout.isInside(pos) == true
	return {pz = pz, hideout = hideout}
end

function S.canWithdraw(player)
	return Core.canWithdraw(cfg, S.place(player))
end

-- true, why ("pz" | "hideout" | "remote") when the player may deposit here: in town for everybody, anywhere with the
-- remote deposit unlock (bought, or lent by an active Chaos Pact)
function S.depositClosed()
	return cfg.toDepot ~= nil and cfg.toDepot.enabled == true
end

function S.canDeposit(player, view)
	if S.depositClosed() then
		return false, "depot" -- the depot is the storage (stash_config.lua toDepot)
	end
	return Core.canDeposit(cfg, view or S.viewOf(player), S.place(player))
end

local function refuseDeposit(player, quiet)
	if not quiet then
		player:sendCancelMessage(Chaos.t(player, S.depositClosed() and M.depositClosed or M.depositPz))
		send(player, {make = "access", canDeposit = false})
	end
end

local function blockEntry(itemType)
	return {sprite = itemType:getClientId(), name = itemType:getName(), id = itemType:getId()}
end

local function sendCategories(player, withBlocks)
	send(player, {make = "addCategorys", list = CATEGORIES, remote = isRemote(player)})
	if withBlocks then
		local items = {}
		for id in pairs(blockedSet(player:getGuid())) do
			local itemType = ItemType(id)
			if itemType:getId() ~= 0 then
				items[#items + 1] = blockEntry(itemType)
			end
		end
		send(player, {make = "forceBlockList", items = items})
	end
end

function S.sendItems(player)
	Core.settle(S.env(player))
	S.normalize(player)
	local view = S.viewOf(player)
	local entries = S.entries(player, view)
	local list = {}
	for _, e in ipairs(entries) do
		local f = S.typeFacts(e.item)
		if f.clientId and f.clientId ~= 0 then
			local name = e.name and e.name ~= "" and e.name or f.typeName
			list[#list + 1] = {
				sprite = f.clientId, count = e.count, name = name,
				tooltip = e.info and e.info ~= "" and e.info or string.format("%s\nAmount: %d", name, e.count),
				id = e.item, uniqueId = e.item, typee = categoryOf(f), tab = e.tab, row = e.row,
				rarity = (e.rarity or 0) > 0 and e.rarity or nil
			}
		end
	end
	local active = ChaosPact ~= nil and ChaosPact.active ~= nil and ChaosPact.active(player) == true
	local place = S.place(player)
	local can = Core.canWithdraw(cfg, place)
	local canDep, depWhy = Core.canDeposit(cfg, view, place)
	if S.depositClosed() then
		canDep, depWhy = false, "depot"
	end
	local tabList = Core.tabsView(cfg, view, entries)
	for _, t in ipairs(tabList) do
		if t.icon then
			t.icon = S.typeFacts(t.icon).clientId -- the client draws client ids
		end
	end
	send(player, {make = "tabs", tabs = tabList, limit = view.general, pact = active,
		tabSize = cfg.tabSize, canWithdraw = can, withdrawWhy = can and (place.pz and "pz" or "hideout") or nil,
		canDeposit = canDep, depositWhy = depWhy, remote = view.remote, closed = S.depositClosed() or nil})
	if #list == 0 then
		send(player, {make = "addItems", isFirst = true, isLast = true, items = {}})
		return
	end
	-- packets are cut by size as well as by count: a packet over the engine's 8192 byte string limit goes out in
	-- "S/P/E" parts that this window (a plain extended opcode listener) cannot read, so the entries in it were lost
	local size, budget = cfg.chunkSize, cfg.chunkBytes or 6000
	local chunks, chunk, bytes = {}, {}, 0
	for _, entry in ipairs(list) do
		local ok, text = pcall(json.encode, entry)
		local n = ok and type(text) == "string" and #text + 1 or 0
		if #chunk > 0 and (#chunk >= size or bytes + n > budget) then
			chunks[#chunks + 1] = chunk
			chunk, bytes = {}, 0
		end
		chunk[#chunk + 1] = entry
		bytes = bytes + n
	end
	chunks[#chunks + 1] = chunk
	for i, part in ipairs(chunks) do
		send(player, {make = "addItems", isFirst = i == 1, isLast = i == #chunks, items = part})
	end
end

-- ---------------------------------------------------------------- item lookup
local function blocks(t)
	return t ~= nil and t.hasProperty ~= nil and (t:hasProperty(CONST_PROP_BLOCKSOLID) or t:hasProperty(CONST_PROP_BLOCKPROJECTILE))
end

-- a floor tile the player could reach with the hand, not through a wall, bars or a window: the own tile, or a
-- tile that does not block (wall, bars, window) in clear sight; a diagonal one needs one open side (no reaching between
-- two walls at a corner). Item:remove() skips all of the engine's reach rules, so they are checked here.
local function reachable(playerPos, position, tile)
	if position.x == playerPos.x and position.y == playerPos.y then
		return true
	end
	if blocks(tile) then
		return false
	end
	if playerPos.isSightClear and not playerPos:isSightClear(position, true) then
		return false
	end
	if position.x ~= playerPos.x and position.y ~= playerPos.y then
		local a = Tile(Position(position.x, playerPos.y, position.z))
		local b = Tile(Position(playerPos.x, position.y, position.z))
		if (not a or blocks(a)) and (not b or blocks(b)) then
			return false
		end
	end
	return true
end

-- Resolve the {x,y,z,stackpos} the client sends into a real item the player may touch: an open container of the
-- player, an inventory slot (not the backpack itself) or a reachable floor item. Nothing else.
function S.resolveItem(player, pos)
	if type(pos) ~= "table" then
		return nil
	end
	local x, y, z = Chaos.toInt(pos.x, 0), Chaos.toInt(pos.y, 0), Chaos.toInt(pos.z, 0)
	if not x or not y or not z then
		return nil
	end
	if x == 65535 then
		if y >= 64 then
			local container = player:getContainerById(y - 64)
			return container and container:getItem(z) or nil
		end
		return player:getSlotItem(y)
	end
	local position = Position(x, y, z)
	local playerPos = player:getPosition()
	if position.z ~= playerPos.z or math.max(math.abs(position.x - playerPos.x), math.abs(position.y - playerPos.y)) > cfg.maxDistance then
		return nil
	end
	local tile = Tile(position)
	if not tile or not reachable(playerPos, position, tile) then
		return nil
	end
	-- Item:remove() skips the engine's house rule (HouseTile::queryRemove only checks when there is an actor), so a
	-- floor item of a house is reachable only from inside that same house (where only invited players can stand)
	local house = tile:getHouse()
	if house then
		local own = Tile(playerPos)
		local ownHouse = own and own:getHouse()
		if not ownHouse or ownHouse:getId() ~= house:getId() then
			return nil
		end
	end
	local stackpos = Chaos.toInt(pos.stackpos, 0)
	local thing = stackpos and tile:getThing(stackpos) or nil
	-- map decoration and fixed items stay where they are (the engine refuses to move them, Item:remove does not)
	if thing and thing:isItem() and thing:getType():isMovable() then
		return thing
	end
	return nil
end

-- ---------------------------------------------------------------- deposits
-- a deposit record of an item (stash_core.lua K.deposit)
local function recordOf(item, f, tab, classes, source)
	local rec = {item = item, itemId = f.id, count = f.count, tab = tab, classes = Core.packClasses(classes) .. ",",
		plain = Core.entryKey(f) ~= nil, name = f.display or f.typeName, rarity = f.rarity, source = source or "deposit"}
	if rec.plain then
		rec.codec, rec.data = "plain", ""
	else
		rec.codec, rec.data = IC.encode(item)
		rec.info = infoOf(item, f)
	end
	return rec
end

local function tabName(tab)
	local a = Core.affinityByTab(cfg, tab)
	return a and a.name or nil
end

-- items = {{item, facts}} (already checked); returns stowed {{name, count, tab}}, skipped {{name, reason}}
local function depositList(player, items, opts)
	opts = opts or {}
	local env = S.env(player)
	if not Core.settle(env) then
		local skipped = {}
		for _, it in ipairs(items) do
			skipped[#skipped + 1] = {name = it.facts.display or it.facts.typeName, reason = "busy"}
		end
		return {}, skipped
	end
	local view = opts.view or S.viewOf(player)
	local entries = S.entries(player, view)
	local counts = {}
	for _, e in ipairs(entries) do
		if e.plain then
			counts[e.key] = e.count
		end
	end
	local planItems = {}
	for i, it in ipairs(items) do
		it.classes = Core.classify(cfg, it.facts)
		planItems[i] = {ref = i, key = Core.entryKey(it.facts), classes = it.classes, count = it.facts.count, skip = it.skip}
	end
	local plan, skippedPlan = Core.plan(cfg, view, entries, planItems, {counts = counts, overflow = opts.overflow})
	local recs, skipped = {}, {}
	for _, s in ipairs(skippedPlan) do
		local it = items[s.ref]
		skipped[#skipped + 1] = {name = it.facts.display or it.facts.typeName, reason = s.reason}
	end
	for _, p in ipairs(plan) do
		local it = items[p.ref]
		local rec = recordOf(it.item, it.facts, p.tab, it.classes, opts.source)
		rec.ref = p.ref
		recs[#recs + 1] = rec
	end
	if #recs == 0 then
		return {}, skipped
	end
	local done, failed = Core.deposit(env, recs)
	for _, fl in ipairs(failed) do
		skipped[#skipped + 1] = {name = fl.rec.name, reason = fl.reason == "taken" and "fixed" or "busy"}
	end
	local stowed = {}
	for _, rec in ipairs(done) do
		stowed[#stowed + 1] = {name = rec.name, count = rec.count, tab = rec.tab}
	end
	return stowed, skipped
end
S.depositList = depositList

-- one item dragged onto the window (or a script's ChaosStash.storeItem); true when it went in
function S.deposit(player, item, quiet)
	if not S.canDeposit(player) then
		refuseDeposit(player, quiet)
		return false
	end
	local f = S.factsOf(player, item)
	local why = Core.depositRefusal(cfg, f)
	if why then
		if not quiet then
			player:sendCancelMessage(Chaos.t(player, M[why] or M.cannot))
		end
		return false
	end
	local stowed, skipped = depositList(player, {{item = item, facts = f}})
	if #stowed == 0 then
		if not quiet then
			local reason = skipped[1] and skipped[1].reason
			if reason == "limit" then
				player:sendCancelMessage(Chaos.t(player, M.tooMany))
			elseif reason == "full" then
				local view = S.viewOf(player)
				local entries = S.entries(player, view)
				local _, kind = Core.route(cfg, view, Core.counts(entries), nil, Core.classify(cfg, f))
				if kind == "locked" then
					player:sendCancelMessage(Chaos.t(player, ChaosI18n.msg(M.locked, view.general)))
				else
					player:sendCancelMessage(Chaos.t(player, ChaosI18n.msg(M.full, #entries)))
				end
			elseif reason == "fixed" then
				player:sendCancelMessage(Chaos.t(player, M.taken))
			else
				player:sendCancelMessage(Chaos.t(player, M.busy))
			end
		end
		return false
	end
	if not quiet then
		local s = stowed[1]
		local tn = tabName(s.tab)
		if tn then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.stashedTab, s.count, s.name, tn))
		else
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.stashed, s.count, s.name))
		end
	end
	return true
end

-- the items of the backpack, through its bags (not the backpack itself, never an equipped item); bags after their
-- contents
local function backpackItems(player)
	local out = {}
	local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not backpack or call(backpack, "isContainer") ~= true then
		return out
	end
	local function walk(container, depth)
		if depth > 32 then
			return
		end
		for _, it in ipairs(call(container, "getItems", false) or {}) do
			if call(it, "isContainer") == true then
				walk(it, depth + 1)
			end
			out[#out + 1] = it
		end
	end
	walk(backpack, 0)
	return out
end

-- Stow Everything: every item of the backpack into its tab; returns the report (stash_core.lua K.report)
function S.stow(player)
	if not S.canDeposit(player) then
		refuseDeposit(player)
		return nil
	end
	send(player, {make = "StashAll", status = true})
	local items, kept = {}, {}
	for _, it in ipairs(backpackItems(player)) do
		local f = S.factsOf(player, it)
		local skip = Core.stowSkip(cfg, f)
		if skip then
			kept[#kept + 1] = {name = f.display or f.typeName, reason = skip}
		else
			items[#items + 1] = {item = it, facts = f}
		end
	end
	local stowed, skipped = {}, {}
	if #items > 0 then
		stowed, skipped = depositList(player, items)
	end
	for _, s in ipairs(skipped) do
		kept[#kept + 1] = s
	end
	local rep = Core.report(cfg, stowed, kept)
	send(player, {make = "StashAll", status = false})
	send(player, {make = "StowReport", stowed = rep.stowed, kept = rep.kept, reasons = rep.reasons})
	if rep.stowed == 0 and rep.kept == 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.stowNone))
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.stowDone, rep.stowed))
		if rep.kept > 0 then
			local parts = {}
			for _, r in ipairs(rep.reasons) do
				parts[#parts + 1] = string.format("%s %d", Chaos.t(player, r.label), r.count)
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.stowSkipped, rep.kept, table.concat(parts, ", ")))
		end
	end
	return rep
end

-- ---------------------------------------------------------------- withdrawals
local function refuseWithdraw(player)
	player:sendCancelMessage(Chaos.t(player, M.pz))
	send(player, {make = "access", canWithdraw = false})
end

function S.redeem(player, data)
	if not S.canWithdraw(player) then
		refuseWithdraw(player)
		return false
	end
	local guid = player:getGuid()
	local env = S.env(player)
	local rec, name
	local rowId = Chaos.toInt(data.row, 1)
	if rowId then
		local r = store.itemRow(guid, rowId)
		if not r then
			player:sendCancelMessage(Chaos.t(player, M.notThere))
			S.sendItems(player)
			return false
		end
		rec = {id = r.id, itemId = r.item_id, count = math.max(1, r.count), codec = r.codec, data = r.data, tab = r.tab, plain = false}
		name = r.name ~= "" and r.name or S.typeFacts(r.item_id).typeName
	else
		local itemId = Chaos.toInt(data.item, 1)
		local want = Chaos.toInt(data.count, 1)
		local itemType = itemId and ItemType(itemId)
		if not itemType or itemType:getId() == 0 or not want then
			S.sendItems(player)
			return false
		end
		local have, tab = store.plainCount(guid, itemId)
		local amount = math.min(have, want)
		if amount <= 0 then
			player:sendCancelMessage(Chaos.t(player, M.notThere))
			S.sendItems(player)
			return false
		end
		local unitWeight = itemType:getWeight(1) -- 1/100 oz on both sides
		if unitWeight > 0 then
			amount = math.min(amount, math.floor(player:getFreeCapacity() / unitWeight))
		end
		if amount <= 0 then
			player:sendCancelMessage(Chaos.t(player, M.capacity))
			S.sendItems(player)
			return false
		end
		rec = {itemId = itemId, count = amount, tab = tab, plain = true, codec = "plain", data = ""}
		name = itemType:getName()
	end
	local ok, why = Core.withdraw(env, rec)
	if ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.retrieved, rec.count, name))
	elseif rec.corrupt then
		warn(player:getName() .. ": stash row " .. tostring(rec.id) .. " could not be restored: " .. tostring(rec.corrupt))
		player:sendCancelMessage(Chaos.t(player, M.corrupt))
	elseif why == "room" then
		player:sendCancelMessage(Chaos.t(player, rec.plain and M.room or M.capacity))
	else
		player:sendCancelMessage(Chaos.t(player, M.busy))
	end
	S.sendItems(player)
	return ok
end

-- ---------------------------------------------------------------- the never-stash list
local function changeBlock(player, data)
	local guid = player:getGuid()
	local itemType
	if data.RemoveUI then
		local itemId = Chaos.toInt(data.itemId, 1)
		itemType = itemId and ItemType(itemId)
		if itemType and itemType:getId() ~= 0 then
			store.block(guid, itemId, false)
			blockCache[guid] = nil
			send(player, {make = "addBlockItem", status = false, itemData = blockEntry(itemType)})
		end
		return
	end
	local item = S.resolveItem(player, data.Pos)
	if not item then
		return
	end
	itemType = item:getType()
	local itemId = itemType:getId()
	if blockedSet(guid)[itemId] then
		store.block(guid, itemId, false)
		blockCache[guid] = nil
		send(player, {make = "addBlockItem", status = false, itemData = blockEntry(itemType)})
	else
		store.block(guid, itemId, true)
		blockCache[guid] = nil
		send(player, {make = "addBlockItem", status = true, itemData = blockEntry(itemType)})
	end
end

-- ---------------------------------------------------------------- the depot migration (at a depot locker opening)
local function townIds()
	local ids = {}
	local ok, towns = pcall(function() return Game.getTowns() end)
	for _, t in ipairs(ok and towns or {}) do
		local id = call(t, "getId")
		if id then
			ids[#ids + 1] = id
		end
	end
	return ids
end

-- every item of the character's depot chests (not the inbox): the depot tab boxes stay (their contents go), a bag goes
-- after its contents and only when all of them go. Returns {{item, facts}}, kept (stay in the depot)
local function depotItems(player, limit)
	local out, kept = {}, 0
	local isBox = function(id)
		return ChaosDepotCore ~= nil and Chaos.depotConfig ~= nil and ChaosDepotCore.tabOf(Chaos.depotConfig, id) ~= nil
	end
	local function walk(container, depth, top)
		local allGo = true
		for _, it in ipairs(call(container, "getItems", false) or {}) do
			if #out >= limit then
				return false
			end
			local id = int(call(it, "getId"))
			if top and isBox(id) then
				walk(it, depth + 1, false)
			else
				local f = S.factsOf(nil, it)
				local childrenGo = true
				if f.container then
					childrenGo = depth < 32 and walk(it, depth + 1, false)
				end
				if childrenGo and int(f.uniqueId) == 0 and f.movable ~= false and #out < limit then
					f.contents = 0 -- its contents are deposited before it
					out[#out + 1] = {item = it, facts = f}
				else
					kept = kept + 1
					allGo = false
				end
			end
		end
		return allGo
	end
	for _, townId in ipairs(townIds()) do
		local chest = call(player, "getDepotChest", townId, false)
		if chest then
			walk(chest, 0, true)
		end
	end
	return out, kept
end

-- true when the depot transition is on and this character still has to move
function S.migrationDue(player)
	local d = cfg.depot
	return d ~= nil and d.migrate == true and int(player:getStorageValue(cfg.storage.migrated)) < int(d.version)
end

-- moves the depots into the stash (call only after a depot locker was opened this session: the engine writes the depot
-- with the character only then). Returns moved, overflow, kept, done
function S.migrateDepot(player)
	if not S.migrationDue(player) then
		return 0, 0, 0, true
	end
	if not IC.hasBlob() then
		warn("engine patch 0017 missing: the depot migration needs item:serializeAttributes (nothing moved)")
		return 0, 0, 0, false
	end
	local limit = math.max(1, int(cfg.migrationBatch))
	local items, kept = depotItems(player, limit + 1)
	local more = #items > limit
	if more then
		items[#items] = nil
	end
	local stowed, skipped = {}, {}
	if #items > 0 then
		stowed, skipped = depositList(player, items, {overflow = cfg.oldDepot.tab, source = "depot"})
	end
	local overflow = 0
	for _, s in ipairs(stowed) do
		if s.tab == cfg.oldDepot.tab then
			overflow = overflow + 1
		end
	end
	local failed = #skipped
	local done = not more and failed == 0
	if done then
		player:setStorageValue(cfg.storage.migrated, cfg.depot.version) -- saved with the next save; a crash before it
		-- runs the migration again, which finds the depot as the last save left it
	end
	if #stowed > 0 or kept > 0 or failed > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, Chaos.t(player, M.migrated, #stowed, overflow, kept + failed))
		if not done then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.migratedMore))
		end
		store.log(player:getGuid(), "migrate", #stowed, overflow, kept + failed, done and "done" or "partial")
		print(string.format("[Chaos stash] %s: depot -> stash, %d moved (%d to Old depot), %d kept, %s", player:getName(), #stowed,
			overflow, kept + failed, done and "done" or "more next time"))
	end
	return #stowed, overflow, kept + failed, done
end

-- ---------------------------------------------------------------- the stash -> depot migration (at a depot locker opening)
-- true when the migration is on and this character still has to move
function S.toDepotDue(player)
	local t = cfg.toDepot
	return t ~= nil and t.enabled == true and int(player:getStorageValue(cfg.storage.toDepot)) < int(t.version)
end

-- moves stash entries into depot tabs. slots = {{box = container, free = n}} the open tabs with room, in tab order
-- (depot.lua Depot.slots). Every entry is a journalled withdrawal (stash_core.lua K.withdraw) whose destination is a
-- depot box instead of the backpack: a crash or a failed save puts it back. Returns moved, left, done.
function S.migrateToDepot(player, slots)
	if not S.toDepotDue(player) then
		return 0, 0, true
	end
	local t = cfg.toDepot
	local guid = player:getGuid()
	local stack = math.max(1, int(t.stackSize))
	local function freeSlot()
		for _, s in ipairs(slots) do
			if s.free > 0 then
				return s
			end
		end
		return nil
	end
	local env = S.env(player)
	function env.give(rec)
		rec.made = {}
		local stackable = S.typeFacts(rec.itemId).stackable
		if rec.plain then
			local left = int(rec.count)
			while left > 0 do
				local slot = freeSlot()
				if not slot then
					break
				end
				local n = stackable and math.min(stack, left) or 1
				local item = Game.createItem(rec.itemId, n)
				if not item then
					break
				end
				local ret = call(slot.box, "addItemEx", item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)
				if ret ~= NOERR and ret ~= true then
					call(item, "remove")
					break
				end
				slot.free = slot.free - 1
				rec.made[#rec.made + 1] = item
				left = left - n
			end
			local given = int(rec.count) - left
			if given <= 0 then
				return false
			end
			if given < rec.count then
				store.shrinkTake(guid, rec, given)
				rec.count = given
			end
			return true
		end
		local slot = freeSlot()
		if not slot then
			return false
		end
		local item, why = IC.decode(rec.itemId, rec.count, rec.codec, rec.data)
		if not item then
			rec.corrupt = why
			return false
		end
		local ret = call(slot.box, "addItemEx", item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)
		if ret ~= NOERR and ret ~= true then
			call(item, "remove")
			return false
		end
		slot.free = slot.free - 1
		rec.made[1] = item
		return true
	end
	function env.ungive(rec)
		for _, it in ipairs(rec.made or {}) do
			call(it, "remove")
		end
		rec.made = nil
	end
	local rows = {}
	for _, r in ipairs(store.plainRows(guid)) do
		rows[#rows + 1] = {plain = true, itemId = r.item_id, count = r.count, tab = r.tab, codec = "plain", data = "", sort = r.tab * 1e9 + r.item_id}
	end
	for _, r in ipairs(store.itemRows(guid)) do
		rows[#rows + 1] = {plain = false, id = r.id, row = true, sort = r.tab * 1e9 + 5e8 + r.id}
	end
	table.sort(rows, function(a, b) return a.sort < b.sort end)
	local moved, failed, i = 0, 0, 1
	local limit = math.max(1, int(t.batch))
	while i <= #rows and moved + failed < limit and freeSlot() do
		local rec = rows[i]
		i = i + 1
		if rec.row then
			local r = store.itemRow(guid, rec.id)
			if r then
				rec = {id = r.id, itemId = r.item_id, count = math.max(1, r.count), codec = r.codec, data = r.data, tab = r.tab, plain = false}
			else
				rec = nil
			end
		end
		if rec then
			local have = rec.plain and store.plainCount(guid, rec.itemId) or rec.count
			if rec.plain then
				rec.count = have
			end
			local ok = have > 0 and Core.withdraw(env, rec)
			if ok then
				moved = moved + 1
			else
				failed = failed + 1
				if rec.corrupt then
					warn(player:getName() .. ": stash row " .. tostring(rec.id) .. " could not be moved to the depot: " .. tostring(rec.corrupt))
				end
			end
		end
	end
	-- done: every entry tried, or the open tabs are full (what is left waits in the stash, withdraw-only)
	local more = (i <= #rows and freeSlot() ~= nil) or failed > 0 -- a failed entry (save, corrupt row) is tried again
	local left = #store.plainRows(guid) + #store.itemRows(guid) -- what is still in the stash
	if not more then
		player:setStorageValue(cfg.storage.toDepot, t.version)
	end
	if moved > 0 or left > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, Chaos.t(player, M.toDepot, moved, left))
		if more then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, M.toDepotMore))
		end
		store.log(guid, "todepot", moved, 0, left, more and "partial" or "done")
		print(string.format("[Chaos stash] %s: stash -> depot, %d moved, %d left, %s", player:getName(), moved, left,
			more and "more next time" or "done"))
	end
	return moved, left, not more
end

-- ---------------------------------------------------------------- events
local LoginEvent = CreatureEvent("ChaosStashLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosStashExtended")
	-- the journal rows a crash left: the saved serial (just loaded with the character) says which side is true
	local ok, err = pcall(function()
		local env = S.env(player)
		local rows = env.pending()
		if #rows > 0 then
			Core.recover(env, rows, env.getSeq())
			warn(string.format("%s: %d journal row(s) settled at login", player:getName(), #rows))
		end
	end)
	if not ok then
		warn("login: " .. tostring(err))
	end
	return true
end

-- a depot locker opened (depot.lua afterOpen): the stash window opens (it stays open when it already is)
function S.openWindow(player)
	send(player, {make = "Toggle", remote = isRemote(player), open = true})
end

local ExtendedEvent = CreatureEvent("ChaosStashExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "Stash" or type(msg.data) ~= "table" then
		return
	end
	local data = msg.data
	-- list, redeem, stow and block-list requests read the database; a flood of them is dropped (ratelimit.lua). "Stash"
	-- (a deposit) needs a real item each time; its list echo is limited below
	local R = cfg.rate
	local limit = ({SendCategories = R.list, SendItems = R.list, Redeem = R.withdraw, ChangeStash = R.block, Open = R.open,
		StashAllRequest = R.stow})[data.make]
	if limit and ChaosRateLimit and not ChaosRateLimit.allow(player, "stash." .. data.make, limit) then
		return
	end

	if data.make == "SendCategories" then
		sendCategories(player, data.sendBlocks == true)
	elseif data.make == "SendItems" then
		S.sendItems(player)
	elseif data.make == "Stash" then
		local item = S.resolveItem(player, data.Pos)
		local backpack = player.getSlotItem and player:getSlotItem(CONST_SLOT_BACKPACK)
		if item and item ~= backpack then
			S.deposit(player, item)
		end
		-- echo the list, even when rejected (the client relies on this), at most every 100 ms: the list is a database
		-- read, and naming the same item again and again would otherwise read it on every packet
		if data.UpdateList and (not ChaosRateLimit or ChaosRateLimit.allow(player, "stash.echo", R.deposit)) then
			S.sendItems(player)
		end
	elseif data.make == "Redeem" then
		S.redeem(player, data)
	elseif data.make == "ChangeStash" then
		changeBlock(player, data)
	elseif data.make == "Open" then
		send(player, {make = "Toggle", remote = isRemote(player)})
	elseif data.make == "StashAllRequest" then
		S.stow(player)
	end
end

LoginEvent:type("login")
LoginEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

local LogoutEvent = CreatureEvent("ChaosStashLogout")
function LogoutEvent.onLogout(player)
	blockCache[player:getGuid()] = nil
	return true
end
LogoutEvent:type("logout")
LogoutEvent:register()

-- ---------------------------------------------------------------- staff (admin panel economy.stash_*)
-- Read by guid (the character may be offline); writes need the character online, because the journal's serial is a
-- storage saved with the character (the write order above). An item made for the stash was never on the character, so
-- the journal's remove / restore (deposit) and give / ungive (removal) have nothing to do; the rest is the same
-- journal: the row first, the serial saved with the character, then the entry.

local function staffTabName(tab)
	tab = int(tab)
	if tab == 0 then
		return "unplaced"
	end
	if cfg.oldDepot and tab == int(cfg.oldDepot.tab) then
		return cfg.oldDepot.name
	end
	return tabName(tab) or ("Tab " .. tab)
end
S.staffTabName = staffTabName

-- a tab staff may name: a general tab 1..maxGeneralTabs or an affinity tab (never Old depot, which takes no items)
function S.staffTabOk(tab)
	tab = int(tab)
	return (tab >= 1 and tab <= int(cfg.maxGeneralTabs)) or Core.affinityByTab(cfg, tab) ~= nil
end

-- per-tab counts, nothing laid out or written: {{tab, name, entries, items}} sorted by tab, and the totals
function S.staffSummary(guid)
	local byTab, out = {}, {}
	local function add(tab, n)
		tab = int(tab)
		local t = byTab[tab]
		if not t then
			t = {tab = tab, name = staffTabName(tab), entries = 0, items = 0}
			byTab[tab] = t
			out[#out + 1] = t
		end
		t.entries, t.items = t.entries + 1, t.items + math.max(1, int(n))
	end
	for _, r in ipairs(store.plainRows(guid)) do
		add(r.tab, r.count)
	end
	for _, r in ipairs(store.itemRows(guid)) do
		add(r.tab, r.count)
	end
	table.sort(out, function(a, b) return a.tab < b.tab end)
	local entries, items = 0, 0
	for _, t in ipairs(out) do
		entries, items = entries + t.entries, items + t.items
	end
	return out, entries, items
end

-- one item type: the merged stack {count, tab} (count 0 when none) and the whole-item rows {{id, tab, name, count}}
function S.staffFind(guid, itemId)
	local count, tab = store.plainCount(guid, itemId)
	local rows = {}
	for _, r in ipairs(store.itemRows(guid)) do
		if r.item_id == int(itemId) then
			rows[#rows + 1] = {id = r.id, tab = r.tab, name = r.name, count = r.count}
		end
	end
	return {count = count, tab = tab}, rows
end

-- `count` of item `itemId` made into the stash of an online character. tab 0: routed as a deposit; else that tab
-- (S.staffTabOk, with room). A plain stack is one merged entry; an item that does not stack is one row each (at most
-- 100). Returns ok, text, stored ({{name, count, tab}}).
function S.staffGive(player, itemId, count, tab, source)
	itemId, count, tab = int(itemId), int(count), int(tab)
	if itemId <= 0 or int(call(ItemType(itemId), "getId")) ~= itemId then
		return false, "Unknown item."
	end
	local f0 = S.typeFacts(itemId)
	if count < 1 or (not f0.stackable and count > 100) then
		return false, "Count out of range (an item that does not stack: at most 100)."
	end
	if tab ~= 0 and not S.staffTabOk(tab) then
		return false, "No such tab (general 1-" .. int(cfg.maxGeneralTabs) .. " or an affinity tab)."
	end
	local env = S.env(player)
	env.remove = function() return true end
	env.restore = function() end
	if not Core.settle(env) then
		return false, "The stash is busy (an earlier operation is not settled yet)."
	end
	local view = S.viewOf(player)
	local entries = S.entries(player, view)
	local items = {}
	for i = 1, f0.stackable and 1 or count do
		local item = Game.createItem(itemId, f0.stackable and math.min(count, 100) or 1)
		if not item then
			return false, "The item could not be made."
		end
		local f = S.factsOf(nil, item)
		f.count = f0.stackable and count or 1
		items[i] = {item = item, facts = f, classes = Core.classify(cfg, f)}
	end
	local recs = {}
	if tab == 0 then
		local counts, planItems = {}, {}
		for _, e in ipairs(entries) do
			if e.plain then
				counts[e.key] = e.count
			end
		end
		for i, it in ipairs(items) do
			planItems[i] = {ref = i, key = Core.entryKey(it.facts), classes = it.classes, count = it.facts.count}
		end
		local plan, skipped = Core.plan(cfg, view, entries, planItems, {counts = counts})
		if #plan == 0 then
			return false, "No room: " .. tostring(skipped[1] and skipped[1].reason or "full") .. "."
		end
		for _, p in ipairs(plan) do
			local it = items[p.ref]
			recs[#recs + 1] = recordOf(it.item, it.facts, p.tab, it.classes, source or "staff")
		end
	else
		local used = Core.counts(entries)
		local key = Core.entryKey(items[1].facts)
		local own = 0
		for _, e in ipairs(entries) do
			if key and e.key == key and int(e.tab) == tab then
				own = 1
			end
		end
		local need = key and (1 - own) or #items
		if (used[tab] or 0) + need > Core.sizeOf(cfg, tab) then
			return false, string.format("%s is full (%d / %d).", staffTabName(tab), used[tab] or 0, Core.sizeOf(cfg, tab))
		end
		for _, it in ipairs(items) do
			recs[#recs + 1] = recordOf(it.item, it.facts, tab, it.classes, source or "staff")
		end
	end
	for _, rec in ipairs(recs) do
		if rec.plain then
			rec.count = count
		end
	end
	local done, failed = Core.deposit(env, recs)
	if #done == 0 then
		return false, "Not stored: " .. tostring(failed[1] and failed[1].reason or "busy") .. "."
	end
	local stored, n = {}, 0
	for _, rec in ipairs(done) do
		stored[#stored + 1] = {name = rec.name, count = rec.count, tab = rec.tab}
		n = n + rec.count
	end
	store.log(player:getGuid(), "staff", #done, 0, #failed, string.format("%dx %d", n, itemId))
	return true, string.format("%dx %s stored (%s).", n, tostring(done[1].name), staffTabName(done[1].tab)), stored
end

-- an entry taken out of an online character's stash and destroyed, through the journal: what = {row = id} (a whole
-- item) or {item = id, count = n} (from the merged stack, clamped to what is stored). Returns ok, text.
function S.staffRemove(player, what)
	local guid = player:getGuid()
	local rec, name
	if what.row then
		local r = store.itemRow(guid, int(what.row))
		if not r then
			return false, "No such stored item of that character."
		end
		rec = {id = r.id, itemId = r.item_id, count = math.max(1, r.count), codec = r.codec, data = r.data, tab = r.tab, plain = false}
		name = r.name ~= "" and r.name or S.typeFacts(r.item_id).typeName
	else
		local itemId = int(what.item)
		local have, tab = store.plainCount(guid, itemId)
		local amount = math.min(have, math.max(0, int(what.count)))
		if amount <= 0 then
			return false, "None of that item in the stash as a merged stack."
		end
		rec = {itemId = itemId, count = amount, tab = tab, plain = true, codec = "plain", data = ""}
		name = S.typeFacts(itemId).typeName
	end
	local env = S.env(player)
	env.give = function() return true end
	env.ungive = function() end
	local ok, why = Core.withdraw(env, rec)
	if not ok then
		return false, "Not removed: " .. tostring(why) .. "."
	end
	store.log(guid, "staffdel", rec.count, 0, 0, string.format("%dx %d", rec.count, rec.itemId))
	return true, string.format("%dx %s removed from the stash (%s).", rec.count, tostring(name), staffTabName(rec.tab))
end

-- put a loose item (e.g. in a corpse) into the stash, for scripts. Returns true when it was stashed; false when the
-- item may not go in, is blocked or no tab has room.
function ChaosStash.storeItem(player, item)
	return S.deposit(player, item, true)
end
