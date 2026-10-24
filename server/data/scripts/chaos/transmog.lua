-- transmog.lua: the transmog (appearance) system. An equipped helmet, armor, legs, boots, weapon or shield can LOOK
-- like another item of the same kind the account has unlocked; stats, name and tooltip stay the item's own.
-- Config: transmog_config.lua. Pure logic: transmog_core.lua (tests: server/tests/transmog_test.lua).
-- Tables: chaos_transmog (unlocked looks), chaos_transmog_sets (owned appearance sets); server/sql/chaos_transmog.sql,
-- also created here at startup if missing. Both are per account (the wardrobe is account-wide).
--
-- How the look reaches the client: the item's custom attribute "chaos_tmog" = server id of the look. Engine patch
-- server/src-patches/0019-transmog-appearance.patch sends it as item custom attribute 8 (the look's client id) in every
-- item packet; the client (base patch 0030) draws that look. Being an item attribute, the look stays with the item
-- through moves, trades, depots, the market escrow (engine patch 0017, or the key list in market.lua) and the guild
-- depot (guild_config.lua customKeys). Without patch 0019 the look is stored but every client shows the item's own.
--
-- ============================================================== API (other scripts)
--   ChaosTransmog.lookOf(item) -> server id of the look, or 0
--   ChaosTransmog.setLook(item, lookId) / ChaosTransmog.clearLook(item)   no checks, no fee (scripts, staff)
--   ChaosTransmog.isUnlocked(accountId, lookId) -> bool
--   ChaosTransmog.unlockLook(accountId, lookId) -> true when it was new
--   ChaosTransmog.grantSet(accountId, setKey, source) -> true, or false + reason ("exclusive" sets, event rewards)
--   ChaosTransmog.revokeSet(accountId, setKey)
--   ChaosTransmog.ownsSet(accountId, setKey) -> bool
--   ChaosTransmog.storeUnlock(unlockName) -> the store entry of a set: shop_config.lua {kind = "unlock",
--       unlock = "transmog_<set key>"} -> {name, done, owned = fn(player), grant = fn(player)} (shop_services.lua)
--   ChaosTransmog.sendState(player, open)
-- ==============================================================
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.transmog (212), server -> client through Chaos.sendChunked:
--   client -> server  open | looks {kind} | apply {slot, look} | remove {slot} | close
--   server -> client  state {open, money, fee, slots, kinds, total, sets}
--                     looks {kind, rows = [{id, cid, name, set}]}   (the unlocked looks of a kind)
--                     result {ok, text}
-- Staff: /transmog <character>, <set key | all | look id>[, revoke]
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosTransmogCore then
	dofile("data/scripts/chaos/transmog_core.lua")
end

ChaosTransmogConfig = dofile("data/scripts/chaos/transmog_config.lua")
ChaosTransmog = ChaosTransmog or {}
local T = ChaosTransmog
local K = ChaosTransmogCore
local cfg = ChaosTransmogConfig
local OPCODE = (ChaosOpcodes and ChaosOpcodes.transmog) or cfg.opcode
local ATTR = "chaos_tmog"
T.core = K
T.attr = ATTR

-- ---------------------------------------------------------------- item types
local typeInfo = {} -- [id] = {cid, name, kind} (false = no such item)

local function describe(id)
	-- an item id from the client: an integer in the item range, so that no NaN or float key reaches typeInfo and the
	-- cache cannot grow with made-up ids
	id = Chaos.toInt(id, 0, 65535) or 0
	local info = typeInfo[id]
	if info ~= nil then
		return info or nil
	end
	local it = id > 0 and ItemType(id) or nil
	if not it or it:getId() == 0 then
		typeInfo[id] = false
		return nil
	end
	local t = {
		cid = it:getClientId(), pickupable = it:isPickupable(), stackable = it:isStackable(),
		container = it:isContainer(), fluid = it:isFluidContainer(), weaponType = it:getWeaponType(),
		slotBits = it:getSlotPosition()
	}
	info = {id = id, cid = t.cid, name = it:getName(), kind = K.kindOf(cfg, t)}
	typeInfo[id] = info
	return info
end
T.describe = describe

local catalogue -- [id] = kind: every look the wardrobe can hold (progress counts it)
local function getCatalogue()
	if catalogue then
		return catalogue
	end
	catalogue = {}
	local count = 0
	for id = 100, cfg.scanMaxId do
		local d = describe(id)
		if d and d.kind and not K.isExcluded(cfg, id) then
			catalogue[id] = d.kind
			count = count + 1
		end
		if d == nil then
			typeInfo[id] = nil -- keep the cache small: only the ids that exist stay
		end
	end
	print(string.format("[Chaos transmog] %d looks in the catalogue", count))
	return catalogue
end

-- ---------------------------------------------------------------- storage
local tablesReady = false
local function ensureTables()
	if not tablesReady then
		local ok = true
		for _, q in ipairs(K.sqlCreate(cfg)) do
			ok = db.query(q) and ok
		end
		tablesReady = ok
	end
	return tablesReady
end

T.cache = T.cache or {} -- [accountId] = {looks = {[id] = true}, sets = {[key] = true}}

local function wardrobe(accountId)
	accountId = tonumber(accountId) or 0
	local w = T.cache[accountId]
	if w then
		return w
	end
	ensureTables()
	w = {looks = {}, sets = {}}
	local id = db.storeQuery(K.sqlSelectLooks(cfg, accountId))
	if id then
		repeat
			w.looks[result.getNumber(id, "item_id")] = true
		until not result.next(id)
		result.free(id)
	end
	id = db.storeQuery(K.sqlSelectSets(cfg, accountId))
	if id then
		repeat
			w.sets[result.getString(id, "set_key")] = true
		until not result.next(id)
		result.free(id)
	end
	T.cache[accountId] = w
	return w
end

local function ownedOf(accountId)
	local w = wardrobe(accountId)
	return K.ownedLooks(cfg, w.looks, w.sets)
end

-- ---------------------------------------------------------------- API
function T.lookOf(item)
	local v = item and item:getCustomAttribute(ATTR)
	return math.floor(tonumber(v) or 0)
end

local function sendUpdate(item)
	if item.sendUpdate then
		pcall(item.sendUpdate, item) -- engine patch 0003
	end
end

function T.setLook(item, lookId)
	item:setCustomAttribute(ATTR, math.floor(lookId))
	sendUpdate(item)
end

function T.clearLook(item)
	item:removeCustomAttribute(ATTR)
	sendUpdate(item)
end

function T.isUnlocked(accountId, lookId)
	return ownedOf(accountId)[tonumber(lookId) or 0] == true
end

function T.unlockLook(accountId, lookId)
	accountId, lookId = tonumber(accountId) or 0, tonumber(lookId) or 0
	if accountId <= 0 or lookId <= 0 then
		return false
	end
	local w = wardrobe(accountId)
	if w.looks[lookId] then
		return false
	end
	if not db.query(K.sqlInsertLook(cfg, accountId, lookId, os.time())) then
		return false
	end
	w.looks[lookId] = true
	return true
end

function T.ownsSet(accountId, key)
	return wardrobe(accountId).sets[key or ""] == true
end

function T.grantSet(accountId, key, source)
	local s = K.setByKey(cfg, key)
	if not s then
		return false, "Unknown appearance set " .. tostring(key) .. "."
	end
	accountId = tonumber(accountId) or 0
	local w = wardrobe(accountId)
	if w.sets[s.key] then
		return false, "The account already has the " .. s.name .. " appearances."
	end
	if not db.query(K.sqlInsertSet(cfg, accountId, s.key, source or s.source, os.time())) then
		return false, "Could not save the set."
	end
	w.sets[s.key] = true
	return true
end

function T.revokeSet(accountId, key)
	local s = K.setByKey(cfg, key)
	if not s then
		return false, "Unknown appearance set " .. tostring(key) .. "."
	end
	accountId = tonumber(accountId) or 0
	db.query(K.sqlDeleteSet(cfg, accountId, s.key))
	wardrobe(accountId).sets[s.key] = nil
	return true
end

function T.storeUnlock(unlockName)
	local s = K.setOfUnlock(cfg, unlockName)
	if not s then
		return nil
	end
	return {
		name = "the " .. s.name .. " appearances",
		done = "Choose them in Character > Transmog (account-wide, appearance only).",
		owned = function(player)
			return T.ownsSet(player:getAccountId(), s.key)
		end,
		grant = function(player)
			local ok = T.grantSet(player:getAccountId(), s.key, "store")
			if ok then
				T.sendState(player, false)
			end
			return ok
		end
	}
end

-- ---------------------------------------------------------------- unlocking from items
local function announce(player, names)
	if #names == 0 then
		return
	end
	local text = #names == 1 and Chaos.t(player, "New appearance unlocked: %s.", names[1])
		or Chaos.t(player, "New appearances unlocked: %s.", table.concat(names, ", "))
	player:sendTextMessage(MESSAGE_INFO_DESCR, text)
end

local function collect(item, depth, out)
	local d = describe(item:getId())
	if d and K.unlockableFromItem(cfg, d.id, d.kind) then
		out[#out + 1] = d
	end
	-- a container item comes with the Container methods (getItems)
	if depth > 0 and item.getItems then
		for _, child in ipairs(item:getItems() or {}) do
			collect(child, depth - 1, out)
		end
	end
end

-- unlock the looks of these items for the player's account; returns the names that were new
local function unlockFrom(player, items, depth)
	local found = {}
	for _, item in ipairs(items) do
		collect(item, depth, found)
	end
	local names, accountId = {}, player:getAccountId()
	for _, d in ipairs(found) do
		if T.unlockLook(accountId, d.id) then
			names[#names + 1] = d.name
		end
	end
	return names
end

local function equippedItems(player)
	local list = {}
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			list[#list + 1] = item
		end
	end
	return list
end

function T.scan(player, deep)
	local items = equippedItems(player)
	return unlockFrom(player, items, deep and cfg.unlock.scanDepth or 0)
end

-- ---------------------------------------------------------------- sets from other systems
local function facts(player)
	return {
		hasAchievement = function(id)
			local A = ChaosAchievements
			return A and A.has and A.has(player, id) or false
		end,
		seasonOwned = function(key)
			local SP = ChaosSeasonPass
			return SP and SP.ownsTransmog and SP.ownsTransmog(player, key) or false
		end
	}
end

local function syncSets(player)
	local accountId = player:getAccountId()
	local names = {}
	for _, key in ipairs(K.setSyncs(cfg, facts(player), wardrobe(accountId).sets)) do
		local s = K.setByKey(cfg, key)
		if T.grantSet(accountId, key, s.source) then
			names[#names + 1] = s.name
		end
	end
	if #names > 0 then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Appearance set unlocked: %s.", table.concat(names, ", ")))
	end
end

-- ---------------------------------------------------------------- the window
local function money(player)
	return Chaos.totalMoney(player)
end

local function pay(player, amount)
	if amount <= 0 then
		return true
	end
	return Chaos.pay(player, amount) and true or false
end

local function itemLevel(item)
	local ok, v = pcall(function()
		return item:getCustomAttribute("combatPowerLevel")
	end)
	return ok and tonumber(v) or 0
end

local function lookView(id)
	local d = describe(id)
	if not d then
		return nil
	end
	return {id = d.id, cid = d.cid, name = d.name, kind = d.kind}
end

local function slotView(player, s)
	local row = {slot = s.slot, name = s.name}
	local item = player:getSlotItem(s.slot)
	if item then
		local d = describe(item:getId())
		local level = itemLevel(item)
		local def = d and d.kind and K.kindDef(cfg, d.kind)
		row.item = {
			id = item:getId(), cid = d and d.cid or 0, name = item:getName(), kind = d and d.kind or nil,
			kindName = def and def.name or nil, level = level,
			applyFee = K.fee(cfg, level, "apply"), removeFee = K.fee(cfg, level, "remove"),
			look = T.lookOf(item) > 0 and lookView(T.lookOf(item)) or nil
		}
	end
	return row
end

local function send(player, action, data)
	return Chaos.sendChunked(player, OPCODE, json.encode({action = action, data = data}))
end

function T.sendState(player, open)
	local owned = ownedOf(player:getAccountId())
	local progress = K.progress(cfg, getCatalogue(), owned)
	local slots, kinds, sets = {}, {}, {}
	for _, s in ipairs(cfg.slots) do
		slots[#slots + 1] = slotView(player, s)
	end
	for _, k in ipairs(cfg.kinds) do
		local p = progress.kinds[k.key]
		kinds[#kinds + 1] = {key = k.key, name = k.name, unlocked = p.unlocked, total = p.total}
	end
	local w = wardrobe(player:getAccountId())
	for _, s in ipairs(cfg.sets) do
		local looks = {}
		for _, id in ipairs(s.looks) do
			looks[#looks + 1] = lookView(id)
		end
		sets[#sets + 1] = {key = s.key, name = s.name, source = s.source, how = K.setHow(s), desc = s.desc,
			owned = w.sets[s.key] == true, looks = looks}
	end
	return send(player, "state", {
		open = open and true or false, money = money(player), fee = cfg.fee, slots = slots, kinds = kinds,
		total = {unlocked = progress.unlocked, total = progress.total}, sets = sets
	})
end

local function sendLooks(player, kind)
	if not K.kindDef(cfg, kind) then
		return
	end
	local rows = {}
	for id in pairs(ownedOf(player:getAccountId())) do
		local d = describe(id)
		if d and d.kind == kind then
			local s = K.setOfLook(cfg, id)
			rows[#rows + 1] = {id = id, cid = d.cid, name = d.name, set = s and s.name or nil}
		end
	end
	table.sort(rows, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.id < b.id
	end)
	while #rows > cfg.maxLooksSent do
		rows[#rows] = nil
	end
	send(player, "looks", {kind = kind, rows = rows})
end

local function sendResult(player, ok, text)
	send(player, "result", {ok = ok and true or false, text = text})
end

local function apply(player, slot, lookId)
	local item = player:getSlotItem(slot)
	local d = item and describe(item:getId())
	local look = lookView(lookId)
	local reason, fee = K.applyCheck(cfg, {
		item = item and {id = item:getId(), kind = d and d.kind, look = T.lookOf(item), level = itemLevel(item)} or nil,
		look = look and {id = look.id, kind = look.kind} or nil,
		owned = ownedOf(player:getAccountId()), money = money(player)
	})
	if reason then
		return sendResult(player, false, reason)
	end
	if not pay(player, fee) then
		return sendResult(player, false, string.format("You need %d gold to change the look.", fee))
	end
	T.setLook(item, look.id)
	local text = string.format("Your %s now looks like %s%s.", item:getName(), look.name,
		fee > 0 and string.format(" (%d gold)", fee) or "")
	local attrs = item.getClientAttributes and item:getClientAttributes() or nil
	if attrs and not attrs[Chaos.itemAttr.appearance or 8] then
		text = text .. " This server's engine lacks patch 0019: the look is saved but not shown yet."
	end
	sendResult(player, true, text)
	T.sendState(player, false)
end

local function remove(player, slot)
	local item = player:getSlotItem(slot)
	local reason, fee = K.removeCheck(cfg, {
		item = item and {id = item:getId(), look = T.lookOf(item), level = itemLevel(item)} or nil, money = money(player)
	})
	if reason then
		return sendResult(player, false, reason)
	end
	if not pay(player, fee) then
		return sendResult(player, false, string.format("You need %d gold to restore the look.", fee))
	end
	T.clearLook(item)
	sendResult(player, true, string.format("Your %s shows its own look again.", item:getName()))
	T.sendState(player, false)
end

local ext = CreatureEvent("ChaosTransmogExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local action, data = K.request(Chaos.decode(buffer))
	if not action or action == "close" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "transmog." .. action, action == "looks" and 150 or 300) then
		return
	end
	local ok, err = pcall(function()
		if action == "open" then
			if cfg.unlock.scanOnOpen then
				announce(player, T.scan(player, true))
			end
			syncSets(player)
			T.sendState(player, true)
		elseif action == "looks" then
			sendLooks(player, data.kind)
		elseif action == "apply" then
			apply(player, data.slot, data.look)
		elseif action == "remove" then
			remove(player, data.slot)
		end
	end)
	if not ok then
		print("[Chaos transmog] " .. action .. " failed: " .. tostring(err))
	end
end
ext:register()

local login = CreatureEvent("ChaosTransmogLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTransmogExtended")
	if cfg.unlock.onLogin then
		local ok, err = pcall(function()
			announce(player, T.scan(player, false))
		end)
		if not ok then
			print("[Chaos transmog] login scan failed: " .. tostring(err))
		end
	end
	return true
end
login:register()

-- an item moved into the character's inventory (equipment slot or a carried container) unlocks its look
if cfg.unlock.onCarry and EventCallback then
	local moved = EventCallback
	moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
		if not player or not item or not toPosition or toPosition.x ~= (CONTAINER_POSITION or 0xFFFF) then
			return
		end
		local top = item:getTopParent()
		if not top or not top.isPlayer or not top:isPlayer() or top:getId() ~= player:getId() then
			return
		end
		local ok, err = pcall(function()
			announce(player, unlockFrom(player, {item}, cfg.unlock.scanDepth))
		end)
		if not ok then
			print("[Chaos transmog] move unlock failed: " .. tostring(err))
		end
	end
	moved:register()
end

-- ---------------------------------------------------------------- staff
local gm = TalkAction("/transmog")
function gm.onSay(player, words, param)
	if player:getGroup():getId() < cfg.staffGroup then
		return true
	end
	local name, what, mode = param:match("^%s*([^,]+)%s*,%s*([%w_]+)%s*,?%s*(%w*)%s*$")
	if not name then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Usage: /transmog <character>, <set key | all | look id>[, revoke]"))
		return false
	end
	-- staff never give value (docs/GM_HANDBOOK.md section 2): an unlock needs an administrator, revoking a set does not
	local value = not (mode == "revoke" and what ~= "all" and not tonumber(what))
	if not Chaos.staffCommand(player, words, param, value) then
		return false
	end
	local accountId
	local id = db.storeQuery("SELECT `account_id` FROM `players` WHERE `name` = " .. db.escapeString(name))
	if id then
		accountId = result.getNumber(id, "account_id")
		result.free(id)
	end
	if not accountId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "No character named %s.", name))
		return false
	end
	local text
	if what == "all" then
		local n = 0
		for lookId in pairs(getCatalogue()) do
			if K.setOfLook(cfg, lookId) == nil and T.unlockLook(accountId, lookId) then
				n = n + 1
			end
		end
		text = string.format("Unlocked %d looks for the account of %s.", n, name)
	elseif tonumber(what) then
		local d = describe(tonumber(what))
		if not d or not d.kind then
			text = "Item " .. what .. " has no transmog kind."
		else
			T.unlockLook(accountId, d.id)
			text = string.format("Unlocked the look %s for the account of %s.", d.name, name)
		end
	else
		local ok, err
		if mode == "revoke" then
			ok, err = T.revokeSet(accountId, what)
		else
			ok, err = T.grantSet(accountId, what, "gm")
		end
		text = ok and string.format("%s the set %s for the account of %s.", mode == "revoke" and "Removed" or "Granted",
			what, name) or err
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	return false
end
gm:separator(" ")
gm:register()

-- ---------------------------------------------------------------- startup checks
local startup = GlobalEvent("ChaosTransmogStartup")
function startup.onStartup()
	ensureTables()
	local problems, warnings = K.validate(cfg, describe, ChaosShopConfig, ChaosAchievements and ChaosAchievements.data or nil)
	for _, p in ipairs(problems) do
		print("[Warning - Chaos transmog] " .. p)
	end
	for _, w in ipairs(warnings) do
		print("[Chaos transmog] " .. w)
	end
	getCatalogue()
	return true
end
startup:register()
