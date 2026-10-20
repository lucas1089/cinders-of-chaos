-- Conquest Tokens, the Conquest vendor and bad-luck protection (client game_conquest, extended opcode
-- ChaosOpcodes.conquest = 167; numbers conquest_config.lua; pure rules conquest_core.lua; tests
-- server/tests/conquest_test.lua; overview server/README.md "Conquest Tokens, the Conquest vendor and bad-luck
-- protection"). Everything a character needs has a deterministic path; luck only decides the maximum.
--
-- Tokens: a per-character balance (table chaos_conquest). Every boss kill (the damage map, the last hit, the most
-- damage and their party in range; the source from the Boss Spawns category of the monster type), every sealed rift,
-- dungeon clear, Ember Descent run and invasion reward, and other systems through the public API:
--   ChaosConquest.grant(player, sourceKey, amount) -> tokens given (the daily cap of the source applies; logged)
--   ChaosConquest.reward(player, sourceKey, ctx)    -> grant of the source's amount for ctx (tier, difficulty, ...)
--   ChaosConquest.balance(player)                   -> the balance
--   ChaosConquest.pityMult(player, group)           -> the bad-luck multiplier of a group (monster, boss, set, raid)
--   ChaosConquest.pityRecord(player, group, hit, id) -> a roll of that group missed (+1) or hit (0); a hit is "seen"
--   ChaosConquest.saw(player, itemId)               -> the vendor shows this item to the character from now on
--   ChaosConquest.offerOf(itemId)                   -> the vendor offer of a unique (salvage.lua prices with it)
-- Daily counters and the misses in a row are player storages (Chaos.storage.conquest, 7102640 - 7102689).
--
-- Buying: the item is made first (as a drop: ChaosMakeUnique), then the tokens go with one conditional UPDATE, then
-- the item is given and the character saved. A failed UPDATE removes the item again.
--
-- Protocol (JSON {action, data}; the state through Chaos.sendChunked):
--   client -> server  open | close | buy {k}
--   server -> client  state {bal, level, pz, offers = [{k, id, c, n, g, l, p, s, set, ok, why}], groups, pity,
--                     today, cinder, refine} | result {ok, text} | npc {} (the vendor's NPC script)
-- Lua 5.1 / LuaJIT.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/conquest_core.lua")
if not ChaosBossPointsCore or not ChaosBossPointsCore.killers then
	dofile("data/scripts/chaos/bosspoints_core.lua")
end
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

ChaosConquestConfig = dofile("data/scripts/chaos/conquest_config.lua")
local cfg = ChaosConquestConfig
local K = ChaosConquestCore
local BP = ChaosBossPointsCore
local OPCODE = ChaosOpcodes.conquest or 167
local ST = Chaos.storage.conquest or cfg.storage

ChaosConquest = ChaosConquest or {}
local X = ChaosConquest
X.cfg = cfg
X.bal = X.bal or {} -- guid -> balance (read once, then kept in step with every write)
X.open = X.open or {} -- guid -> the window is open
X.busy = X.busy or {} -- guid -> a purchase is running
X.capNoted = X.capNoted or {} -- "guid:source:day" -> the daily limit was told

local function log(text)
	print("[Chaos conquest] " .. text)
end

local function try(name, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res
end

local function T(name)
	return cfg.tables[name]
end

local function today()
	return Chaos.dayKey and Chaos.dayKey(os.time()) or tonumber(os.date("%Y%m%d"))
end

-- ---------------------------------------------------------------- database
function X.createTables()
	if not db or not db.query then
		return
	end
	db.query("CREATE TABLE IF NOT EXISTS `" .. T("balance") .. "` (`player_id` int(11) NOT NULL, " ..
		"`balance` int(10) unsigned NOT NULL DEFAULT 0, `earned` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"`spent` int(10) unsigned NOT NULL DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T("log") .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, " ..
		"`player_id` int(11) NOT NULL, `source` varchar(32) NOT NULL, `amount` int(11) NOT NULL DEFAULT 0, " ..
		"`balance` int(10) unsigned NOT NULL DEFAULT 0, `detail` varchar(80) NOT NULL DEFAULT '', " ..
		"`at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`id`), KEY `chaos_conquest_log_player` (`player_id`, `at`)) " ..
		"ENGINE=InnoDB DEFAULT CHARSET=utf8")
	db.query("CREATE TABLE IF NOT EXISTS `" .. T("seen") .. "` (`player_id` int(11) NOT NULL, " ..
		"`item_id` int(10) unsigned NOT NULL, `at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`player_id`, `item_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8")
end

local function readBalance(guid)
	local r = Chaos.select(string.format("SELECT `balance` FROM `%s` WHERE `player_id` = %d", T("balance"), guid),
		{{"balance", "n"}})[1]
	return r and math.max(0, math.floor(r.balance or 0)) or 0
end

local function logRow(guid, source, amount, balance, detail)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `source`, `amount`, `balance`, `detail`, `at`) VALUES " ..
		"(%d, %s, %d, %d, %s, %d)", T("log"), guid, db.escapeString(tostring(source):sub(1, 32)), amount,
		math.max(0, balance), db.escapeString(tostring(detail or ""):sub(1, 80)), os.time()))
end

local function credit(guid, n)
	db.query(string.format("INSERT INTO `%s` (`player_id`, `balance`, `earned`, `updated_at`) VALUES (%d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `balance` = `balance` + VALUES(`balance`), `earned` = `earned` + VALUES(`earned`), " ..
		"`updated_at` = VALUES(`updated_at`)", T("balance"), guid, n, n, os.time()))
end

-- one conditional UPDATE (never a read, then a write); true when the balance covered it
local function debit(guid, n)
	db.query(string.format("UPDATE `%s` SET `balance` = `balance` - %d, `spent` = `spent` + %d, `updated_at` = %d " ..
		"WHERE `player_id` = %d AND `balance` >= %d", T("balance"), n, n, os.time(), guid, n))
	local r = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	return r ~= nil and r.n == 1
end

function X.balance(player)
	if not player then
		return 0
	end
	local guid = player:getGuid()
	if X.bal[guid] == nil then
		X.bal[guid] = readBalance(guid)
	end
	return X.bal[guid]
end

-- ---------------------------------------------------------------- income
local function counter(player, key)
	local s = cfg.sources[key]
	local day = player:getStorageValue(ST + cfg.daySlot)
	local used = player:getStorageValue(ST + s.slot)
	return day, used < 0 and 0 or used
end

local function notify(player, text)
	player:sendTextMessage(MESSAGE_LOOT or MESSAGE_INFO_DESCR, text)
end

-- gives `amount` tokens of source `key` (nil: the source's own amount), under the source's daily cap. Safe to call as
-- often as wanted: an unknown source, a non-player or a cap reached gives 0. Returns the tokens given.
function X.grant(player, key, amount, detail)
	if not cfg.enabled or not player or type(key) ~= "string" or not cfg.sources[key] then
		return 0
	end
	local ok, isPlayer = pcall(function() return player:isPlayer() end)
	if not ok or not isPlayer then
		return 0
	end
	amount = tonumber(amount) or K.amount(cfg, key)
	-- the returning-player bonus (H3's catch-up, ChaosCatchup.tokenMult): on earned tokens, not on salvage; rounded
	-- to the nearest token, before the daily cap
	if key ~= "salvage" and amount > 0 then
		local okM, m = pcall(function()
			return ChaosCatchup and ChaosCatchup.tokenMult and ChaosCatchup.tokenMult(player) or 1
		end)
		m = okM and tonumber(m) or 1
		if m and m == m and m > 0 and m < 10 and m ~= 1 then
			amount = math.floor(amount * m + 0.5)
		end
	end
	local day, used = counter(player, key)
	local now = today()
	if day ~= now then
		-- a new day: every counter of the block starts again
		for _, s in pairs(cfg.sources) do
			player:setStorageValue(ST + s.slot, 0)
		end
		player:setStorageValue(ST + cfg.daySlot, now)
		used = 0
	end
	local plan = K.grantPlan(cfg, key, amount, now, now, used)
	local s = cfg.sources[key]
	if plan.give <= 0 then
		-- once per character, source and day
		local note = player:getGuid() .. ":" .. key .. ":" .. now
		if amount > 0 and not X.capNoted[note] then
			X.capNoted[note] = true
			notify(player, Chaos.t(player, "Conquest Tokens: today's limit for %s is reached (%d).", s.label or key, s.cap))
		end
		return 0
	end
	player:setStorageValue(ST + s.slot, plan.used)
	local guid = player:getGuid()
	local bal = X.balance(player) + plan.give
	credit(guid, plan.give)
	X.bal[guid] = bal
	logRow(guid, key, plan.give, bal, detail)
	notify(player, Chaos.t(player, "+%d Conquest Tokens (%s). Balance: %d.", plan.give, s.label or key, bal))
	if X.open[guid] then
		try("send", X.send, player)
	end
	return plan.give
end

function X.reward(player, key, ctx, detail)
	return X.grant(player, key, K.amount(cfg, key, ctx), detail)
end

-- ---------------------------------------------------------------- bad-luck protection
local function pityKey(group)
	local g = cfg.pity[group]
	return g and (ST + cfg.pitySlot + g.slot) or nil
end

function X.pityMisses(player, group)
	local key = player and pityKey(group)
	if not key then
		return 0
	end
	local v = player:getStorageValue(key)
	return v < 0 and 0 or v
end

function X.pityMult(player, group)
	if not cfg.enabled or not player then
		return 1
	end
	return K.pityMult(cfg, group, X.pityMisses(player, group))
end

function X.pityRecord(player, group, hit, itemId)
	local key = cfg.enabled and player and pityKey(group)
	if not key then
		return
	end
	player:setStorageValue(key, K.pityNext(cfg, group, X.pityMisses(player, group), hit))
	if hit and itemId then
		X.saw(player, itemId)
	end
end

-- ---------------------------------------------------------------- seen items
X.seenCache = X.seenCache or {} -- guid -> {[id] = true}
function X.saw(player, itemId)
	itemId = tonumber(itemId)
	if not player or not itemId then
		return
	end
	local guid = player:getGuid()
	local c = X.seenCache[guid]
	if c and c[itemId] then
		return
	end
	if c then
		c[itemId] = true
	end
	db.query(string.format("INSERT IGNORE INTO `%s` (`player_id`, `item_id`, `at`) VALUES (%d, %d, %d)", T("seen"), guid,
		itemId, os.time()))
end

local function seenOf(guid)
	if not X.seenCache[guid] then
		local s = {}
		for _, r in ipairs(Chaos.select(string.format("SELECT `item_id` FROM `%s` WHERE `player_id` = %d", T("seen"), guid),
				{{"item_id", "n"}})) do
			s[r.item_id] = true
		end
		X.seenCache[guid] = s
	end
	return X.seenCache[guid]
end

local function killedOf(guid)
	local k = {}
	local ok = pcall(function()
		for _, r in ipairs(Chaos.select(string.format("SELECT `monster` FROM `chaos_bestiary` WHERE `player_id` = %d AND " ..
				"`kills` > 0", guid), {{"monster", "s"}})) do
			k[tostring(r.monster):lower()] = true
		end
	end)
	return ok and k or {}
end

-- ---------------------------------------------------------------- the catalog
function X.catalog()
	if not X.offers then
		local raidCfg = ChaosRaidConfig
		if not raidCfg then
			local ok, t = pcall(dofile, "data/scripts/chaos/raid_config.lua")
			raidCfg = ok and t or nil
		end
		X.offers = K.catalog(cfg, {uniques = ChaosUniqueItems, sets = ChaosItemSets and ChaosItemSets.sets,
			raid = raidCfg and raidCfg.uniques, specs = ChaosUniqueSpecs})
		X.offerByKey = K.byKey(X.offers)
	end
	return X.offers
end

function X.offerOf(itemId)
	X.catalog()
	return X.offerByKey["u:" .. tostring(itemId)]
end

local function blocked(player, o)
	return o.season ~= nil and ChaosSeason ~= nil and ChaosSeason.uniqueBlocked ~= nil and
		ChaosSeason.uniqueBlocked(o.season, player) and true or false
end

local function inPz(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

function X.near(player)
	local r = cfg.npc.range
	local name = cfg.npc.name:lower()
	for _, c in ipairs(Game.getSpectators(player:getPosition(), false, false, r, r, r, r) or {}) do
		if c:isNpc() and c:getName():lower() == name then
			return true
		end
	end
	return false
end

local function clientId(id)
	local ok, cid = pcall(function() return ItemType(id):getClientId() end)
	return ok and tonumber(cid) or id
end

-- ---------------------------------------------------------------- the Cinderheart chain helpers
local function riftCfg()
	return ChaosRiftConfig
end

local function omenKinds()
	local rc = riftCfg()
	local out = {}
	for _, k in ipairs(rc and rc.omen and rc.omen.kinds or {}) do
		out[#out + 1] = {k = k.key, n = k.name}
	end
	return out
end

local function ascendedKinds()
	local uc = ChaosUberConfig
	local out = {}
	for _, k in ipairs(uc and uc.kinds or {}) do
		if not k.final and uc.items and uc.items.shards and uc.items.shards[k.key] then
			out[#out + 1] = {k = k.key, n = k.name}
		end
	end
	return out
end

local function kindKeys(list)
	local out = {}
	for _, k in ipairs(list) do
		out[#out + 1] = k.k
	end
	return out
end

local function shardsOf(player)
	local have = {}
	local uc = ChaosUberConfig
	for key, s in pairs(uc and uc.items and uc.items.shards or {}) do
		have[key] = player:getItemCount(s.id)
	end
	return have
end

local function relicsOf(player)
	local list = ChaosAscended and ChaosAscended.relicsOf and ChaosAscended.relicsOf(player) or {}
	local have = {}
	for _, r in ipairs(list) do
		have[r[2]] = (have[r[2]] or 0) + 1
	end
	return have, list
end

local function omenKeyItem(player)
	local rc = riftCfg()
	local id = rc and rc.omen and rc.omen.key and rc.omen.key.id
	if not id then
		return nil
	end
	local ok, item = pcall(function() return player:getItemById(id, true) end)
	return ok and item or nil
end

-- ---------------------------------------------------------------- refinement helpers
local SLOTS = {CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT,
	CONST_SLOT_LEFT, CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO}

local function refineInfo(item)
	local C = ChaosCrafting
	local M = ChaosItemMods
	if not item or not C then
		return nil
	end
	return {gear = C.isGear(item), rarity = C.rarityOf(item), unique = C.isUnique(item),
		ruined = M and M.isRuined and M.isRuined(item) or false}
end

local function refineRows(player)
	local rows = {}
	local C = ChaosCrafting
	if not C then
		return rows
	end
	for _, slot in ipairs(SLOTS) do
		local item = slot and player:getSlotItem(slot)
		local info = item and refineInfo(item)
		if info and info.gear and not info.unique and (info.rarity or 0) > 0 then
			local ok, why = K.refineCheck(cfg, info)
			rows[#rows + 1] = {slot = slot, n = C.itemName(item), c = clientId(item:getId()), r = info.rarity,
				rn = C.rarityName(info.rarity), to = C.rarityName(ChaosRarity.idOfRank(ChaosRarity.rank(info.rarity) + 1)), p = K.refinePrice(cfg, info.rarity),
				ok = ok and true or nil, why = why and K.reasons[why] or nil}
		end
	end
	return rows
end

-- ---------------------------------------------------------------- the window
function X.state(player)
	local guid = player:getGuid()
	local ctx = {level = player:getLevel(), seen = seenOf(guid), killed = killedOf(guid),
		blocked = function(o) return blocked(player, o) end}
	local rows = K.payload(cfg, X.catalog(), ctx)
	for _, r in ipairs(rows) do
		r.c = clientId(r.id)
		if r.why then
			r.why = Chaos.t(player, K.reasons[r.why] or r.why)
		end
	end
	local pity = {}
	for _, g in ipairs(cfg.pityOrder) do
		local misses = X.pityMisses(player, g)
		pity[#pity + 1] = {g = g, n = cfg.pity[g].label, m = misses, x = K.pityMult(cfg, g, misses)}
	end
	local day = player:getStorageValue(ST + cfg.daySlot)
	local todayRows = {}
	for key, s in pairs(cfg.sources) do
		local used = day == today() and math.max(0, player:getStorageValue(ST + s.slot)) or 0
		todayRows[#todayRows + 1] = {k = key, n = s.label or key, got = used, cap = s.cap}
	end
	table.sort(todayRows, function(a, b) return cfg.sources[a.k].slot < cfg.sources[b.k].slot end)
	local groups = {}
	for _, g in ipairs(cfg.vendor.groupOrder) do
		groups[#groups + 1] = {g = g, n = cfg.vendor.groups[g].label}
	end
	local c = cfg.cinder
	local shards = shardsOf(player)
	local relics = relicsOf(player)
	return {
		bal = X.balance(player), level = player:getLevel(), pz = inPz(player) or X.near(player), band = cfg.vendor.levelBand,
		offers = rows, groups = groups, pity = pity, today = todayRows,
		cinder = {omenKey = c.omenKey, attune = c.attune, shard = c.shard, convert = c.convert, omens = omenKinds(),
			ascended = ascendedKinds(), shards = shards, relics = relics, hasKey = omenKeyItem(player) ~= nil or nil},
		refine = refineRows(player), refineMax = cfg.refine.maxRarity
	}
end

function X.send(player)
	if not json or not json.encode then
		return
	end
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = X.state(player)}))
end

local function result(player, ok, text)
	text = Chaos.t(player, text)
	Chaos.send(player, OPCODE, "result", {ok = ok and true or false, text = text})
	player:sendTextMessage(ok and (MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR) or (MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR), text)
	return ok
end

local function refuse(player, why)
	return result(player, false, K.reasons[why] or why)
end

local function giveEx(player, item)
	if player:addItemEx(item, false) ~= (RETURNVALUE_NOERROR or 0) then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		return true
	end
	return false
end

-- spends `price` tokens; true when they were there (the balance cache follows)
local function spend(player, price, what)
	local guid = player:getGuid()
	if not debit(guid, price) then
		X.bal[guid] = nil
		return false
	end
	X.bal[guid] = math.max(0, X.balance(player) - price)
	logRow(guid, "buy", -price, X.bal[guid], what)
	return true
end

local function payable(player, price)
	if cfg.vendor.needProtectionZone and not (inPz(player) or X.near(player)) then
		return "pz"
	end
	if X.balance(player) < price then
		return "tokens"
	end
	return nil
end

-- a unique or set piece
local function buyUnique(player, o)
	if not o then
		return refuse(player, "unknown")
	end
	local guid = player:getGuid()
	local ok, why = K.canBuy(cfg, o, {balance = X.balance(player), pz = inPz(player) or X.near(player),
		visible = K.visible(cfg, o, {level = player:getLevel(), seen = seenOf(guid), killed = killedOf(guid)}),
		blocked = blocked(player, o)})
	if not ok then
		return refuse(player, why)
	end
	local item = Game.createItem(o.id, 1)
	if not item then
		return result(player, false, "The vendor's stock is empty for that item. Your tokens are untouched.")
	end
	if ChaosMakeUnique then
		ChaosMakeUnique(item)
	end
	if not spend(player, o.price, o.key) then
		item:remove()
		return refuse(player, "tokens")
	end
	local inbox = giveEx(player, item)
	Chaos.saveCharacter(player)
	X.saw(player, o.id)
	return result(player, true, Chaos.t(player, "You bought %s for %d Conquest Tokens.%s", o.name, o.price,
		inbox and Chaos.t(player, " Your backpack is full: it went to your inbox.") or ""))
end

local function buyOmenKey(player, kind, attune)
	local c = cfg.cinder
	local valid = {}
	for _, k in ipairs(omenKinds()) do
		valid[k.k] = k.n
	end
	if not valid[kind] then
		return refuse(player, "badKind")
	end
	local rc = riftCfg()
	if rc and rc.omen and player:getLevel() < (rc.omen.minLevel or 0) then
		return refuse(player, "level")
	end
	local price = attune and c.attune or c.omenKey
	local why = payable(player, price)
	if why then
		return refuse(player, why)
	end
	if attune then
		local item = omenKeyItem(player)
		if not item or not (ChaosRift and ChaosRift.applyOmenKey) then
			return refuse(player, "noKey")
		end
		if not spend(player, price, "attune:" .. kind) then
			return refuse(player, "tokens")
		end
		ChaosRift.applyOmenKey(item, kind)
		Chaos.saveCharacter(player)
		return result(player, true, Chaos.t(player, "Your Omen Key now opens the %s guardian's arena (%d Conquest Tokens).",
			valid[kind], price))
	end
	if not (ChaosRift and ChaosRift.giveOmenKey) then
		return result(player, false, "Omen Keys are not installed on this server (tools/install_omens.py).")
	end
	if not spend(player, price, "omen:" .. kind) then
		return refuse(player, "tokens")
	end
	if not ChaosRift.giveOmenKey(player, kind, Chaos.t(player, "Bought with Conquest Tokens")) then
		credit(player:getGuid(), price)
		X.bal[player:getGuid()] = nil
		return result(player, false, "The key could not be made. Your tokens are back.")
	end
	Chaos.saveCharacter(player)
	return result(player, true, Chaos.t(player, "You bought an Omen Key (%s) for %d Conquest Tokens.", valid[kind], price))
end

local function buyShard(player, kind)
	local valid = {}
	for _, k in ipairs(ascendedKinds()) do
		valid[k.k] = k.n
	end
	if not valid[kind] or not (ChaosAscended and ChaosAscended.giveShard) then
		return refuse(player, "badKind")
	end
	local price = cfg.cinder.shard
	local why = payable(player, price)
	if why then
		return refuse(player, why)
	end
	if not spend(player, price, "shard:" .. kind) then
		return refuse(player, "tokens")
	end
	if ChaosAscended.giveShard(player, kind, Chaos.t(player, "Bought with Conquest Tokens")) == nil then
		credit(player:getGuid(), price)
		X.bal[player:getGuid()] = nil
		return result(player, false, "Ascended Shards are not installed on this server. Your tokens are back.")
	end
	Chaos.saveCharacter(player)
	return result(player, true, Chaos.t(player, "You bought an Ascended Shard (%s) for %d Conquest Tokens.", valid[kind], price))
end

-- what = "shards" | "relics": count of one kind become one of another (an item swap: no database credit)
local function convert(player, what, from, to)
	local kinds = kindKeys(ascendedKinds())
	local uc = ChaosUberConfig
	local have, list
	if what == "shards" then
		have = shardsOf(player)
	elseif what == "relics" then
		have, list = relicsOf(player)
	else
		return refuse(player, "unknown")
	end
	local ok, need = K.convertCheck(cfg, what, from, to, have, kinds)
	if not ok then
		return refuse(player, need)
	end
	local fee = cfg.cinder.convert.fee or 0
	if fee > 0 then
		local why = payable(player, fee)
		if why then
			return refuse(player, why)
		end
	end
	if what == "shards" then
		if not player:removeItem(uc.items.shards[from].id, need) then
			return result(player, false, "The shards could not be taken.")
		end
	else
		local taken = 0
		for _, r in ipairs(list) do
			if taken < need and r[2] == from and r[1]:remove(1) then
				taken = taken + 1
			end
		end
		if taken < need then
			return result(player, false, "The relics could not be taken.")
		end
	end
	if fee > 0 then
		spend(player, fee, "convert:" .. what)
	end
	if what == "shards" then
		ChaosAscended.giveShard(player, to, Chaos.t(player, "Converted"))
	else
		ChaosAscended.giveRelic(player, to)
	end
	Chaos.saveCharacter(player)
	return result(player, true, Chaos.t(player, "Converted %d %s into one of %s.", need, what, to))
end

local function refine(player, slot)
	slot = Chaos.toInt(slot, 1, 10)
	local item = slot and player:getSlotItem(slot)
	local info = refineInfo(item)
	local ok, why = K.refineCheck(cfg, info)
	if not ok then
		return refuse(player, why)
	end
	local price = K.refinePrice(cfg, info.rarity)
	why = payable(player, price)
	if why then
		return refuse(player, why)
	end
	local C, M = ChaosCrafting, ChaosItemMods
	local id = item:getId()
	if not spend(player, price, "refine:" .. id) then
		return refuse(player, "tokens")
	end
	local rarity = ChaosRarity.idOfRank(ChaosRarity.rank(info.rarity) + 1) -- the next stored id
	item:setCustomAttribute("rarity", rarity)
	local added = ""
	local affix = M.pick(C.candidates(item, rarity), C.random)
	if affix then
		local m = C.rollAffix(item, affix, C.orbLevel(item), C.random)
		added = m and (" " .. Chaos.t(player, "New modifier: %s.", C.modTierText(m))) or ""
	end
	C.rewriteDescription(item)
	M.sendUpdate(item)
	Chaos.saveCharacter(player)
	return result(player, true, Chaos.t(player, "%s is now %s (%d Conquest Tokens).", C.itemName(item), C.rarityName(rarity),
		price) .. added)
end

function X.buy(player, d)
	local guid = player:getGuid()
	if X.busy[guid] then
		return
	end
	if not cfg.enabled then
		return refuse(player, "disabled")
	end
	local k = type(d) == "table" and type(d.k) == "string" and d.k:sub(1, 48) or ""
	X.busy[guid] = true
	local ok, err = pcall(function()
		local a, b, c2, d2 = k:match("^(%w+):([%w_]*):?([%w_]*):?([%w_]*)$")
		if a == "u" then
			X.catalog()
			return buyUnique(player, X.offerByKey[k])
		elseif a == "omen" then
			return buyOmenKey(player, b, false)
		elseif a == "attune" then
			return buyOmenKey(player, b, true)
		elseif a == "shard" then
			return buyShard(player, b)
		elseif a == "conv" then
			return convert(player, b, c2, d2)
		elseif a == "refine" then
			return refine(player, b)
		end
		return refuse(player, "unknown")
	end)
	X.busy[guid] = nil
	if not ok then
		log("buy " .. k .. ": " .. tostring(err))
		result(player, false, "The vendor shakes her head. Try again.")
	end
end

-- ---------------------------------------------------------------- boss kills
local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

local function typeName(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end

local function categoryOf(name)
	local S = ChaosBossSpawns
	local idx = S and (S.index or (S.ensure and select(2, pcall(S.ensure))))
	local list = type(idx) == "table" and idx.byType and idx.byType[name:lower()]
	return list and list[1] and list[1].category or nil
end

local function isBossType(creature)
	local ok, res = pcall(function() return creature:getType():isBoss() end)
	return ok and res == true
end

-- the token source of a monster (nil: none), cached per type name
X.sourceCache = X.sourceCache or {}
function X.sourceOf(creature)
	local name = typeName(creature) or ""
	local key = name:lower()
	local c = X.sourceCache[key]
	if c == nil then
		local src, amount = K.bossSource(cfg, name, categoryOf(name), isBossType(creature))
		c = src and {src, amount} or false
		X.sourceCache[key] = c
	end
	return c or nil
end

function X.onKill(creature, killer, mostDamageKiller)
	local s = X.sourceOf(creature)
	if not s then
		return
	end
	local ids = {}
	for id in pairs(creature:getDamageMap() or {}) do
		ids[#ids + 1] = id
	end
	local function idOf(p) return p:getId() end
	local killers = BP.killers(ids, function(id) return playerOf(Creature(id)) end,
		{playerOf(killer), playerOf(mostDamageKiller)}, idOf)
	local credited = BP.credit(killers, function(p)
		local party = p:getParty()
		if not party then
			return nil
		end
		local members = party:getMembers()
		members[#members + 1] = party:getLeader()
		return members
	end, function(p) return p:getPosition() end, cfg.boss.partyRange or 30, idOf)
	local detail = typeName(creature)
	for _, p in ipairs(credited) do
		X.grant(p, s[1], s[2], detail)
	end
end

local death = CreatureEvent("ChaosConquestDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	if cfg.enabled then
		try("kill", X.onKill, creature, killer, mostDamageKiller)
	end
	return true
end
death:register()

local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if cfg.enabled and not self:getMaster() then
		local ok, src = pcall(X.sourceOf, self)
		if ok and src then
			self:registerEvent("ChaosConquestDeath")
		end
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- the NPC
function X.placeNpcs()
	local placed = 0
	for _, id in ipairs(cfg.npc.towns) do
		local town = Town(id)
		local temple = town and town:getTemplePosition()
		if temple and try("place npc", ChaosNpcPlace.place, cfg.npc.name, temple, cfg.npc.offsets, cfg.npc.place) then
			placed = placed + 1
		end
	end
	if placed == 0 then
		log("no " .. cfg.npc.name .. " placed (data/npc/" .. cfg.npc.name .. ".xml missing: tools/install_conquest.py?); " ..
			"the window still opens from the menu")
	end
	return placed
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosConquestStartup")
function startup.onStartup()
	for _, p in ipairs(K.validate(cfg)) do
		log("config: " .. p)
	end
	try("tables", X.createTables)
	if db and db.query then
		db.query(string.format("DELETE FROM `%s` WHERE `at` < %d", T("log"), os.time() - (cfg.logKeepDays or 60) * 86400))
	end
	if cfg.enabled then
		addEvent(function()
			log(X.placeNpcs() .. " vendor(s) placed, " .. #X.catalog() .. " offers")
		end, cfg.npc.delayMs or 3500)
	end
	return true
end
startup:register()

local login = CreatureEvent("ChaosConquestLogin")
function login.onLogin(player)
	player:registerEvent("ChaosConquestExtended")
	player:registerEvent("ChaosConquestLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosConquestLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	X.bal[guid], X.open[guid], X.busy[guid], X.seenCache[guid] = nil, nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosConquestExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg.enabled then
		return
	end
	if Chaos.limited(player, "conquest", cfg.requestMs) then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	local guid = player:getGuid()
	if m.action == "open" then
		X.open[guid] = true
	elseif m.action == "close" then
		X.open[guid] = nil
		return
	elseif m.action == "buy" then
		try("buy", X.buy, player, d)
	else
		return
	end
	try("send", X.send, player)
end
ext:type("extendedopcode")
ext:register()

-- staff: /conquest Name (balance, pity, today), /conquest Name, give, n (an administrator; logged), /conquest Name, pity
-- (clears the misses)
local talk = TalkAction("/conquest")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < cfg.staffGroup then
		return true
	end
	local name, what, n = param:match("^%s*([^,]+),%s*(%a+),?%s*(%d*)%s*$")
	local target = Player(name or param:match("^%s*(.-)%s*$"))
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/conquest Name [, give, n | , pity]")
		return false
	end
	if what == "give" then
		if not Chaos.staffCommand(player, words, param, true) then
			return false
		end
		local amount = math.max(0, math.min(100000, tonumber(n) or 0))
		local guid = target:getGuid()
		credit(guid, amount)
		X.bal[guid] = nil
		logRow(guid, "staff", amount, X.balance(target), player:getName())
	elseif what == "pity" then
		Chaos.staffCommand(player, words, param)
		for _, g in pairs(cfg.pity) do
			target:setStorageValue(ST + cfg.pitySlot + g.slot, 0)
		end
	end
	local parts = {}
	for _, g in ipairs(cfg.pityOrder) do
		parts[#parts + 1] = string.format("%s %d (x%.2f)", g, X.pityMisses(target, g), X.pityMult(target, g))
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s: %d Conquest Tokens; misses %s.", target:getName(),
		X.balance(target), table.concat(parts, ", ")))
	return false
end
talk:separator(" ")
talk:register()
