-- Seasons (roadmap item 12, phase 1): fresh-start season characters with their own ladder, season-only uniques and an
-- account-wide cosmetic reward track. Rules and numbers: season_config.lua; pure logic: season_core.lua; client
-- game_season (extended opcode ChaosOpcodes.season); tables sql/chaos_season.sql. Overview: server/README.md "Seasons".
--
--   Adventure > Season    the window (players): the season, time left, your milestones; Join, then the confirmation
--   /season start [id]|end|status   gods only: start the next season now, end the running one now (migration), state
--   (there is no chat join: the window is the only way in, and its confirmation closes by itself once the character
--   cannot join any more, e.g. after a level up past join.maxLevel)
--
-- Isolation while a season runs (realm = 0 for standard characters, the season id for season characters):
--   trade window and house trade (EventCallback onTradeRequest / onTradeAccept; tools/patch_season_events.py enables
--   them in events.xml), items on the ground, in corpses, in houses and mail (ChaosSeason.onMoveItem, called first in
--   Player:onMoveItem by the same tool; the realm of whoever dropped an item / killed a monster / died is written on
--   the item or corpse as the custom attribute chaos_realm), parties (EventCallback onJoin), the Chaos bank transfer
--   (bank.lua asks ChaosSeason.transferBlocked), the NPC bank transfer (Player.transferMoneyTo asks
--   ChaosSeason.npcTransferBlocked), the market (separate season markets, market.lua; gold only, ChaosMarket wrapped
--   here). Account-wide Chaos Coins: the store (shop.lua asks ChaosSeason.storeProblem), the season pass items
--   (seasonpass.lua asks ChaosSeason.passClaimProblem), the world buffs (shop_services.lua). See README.
-- End of season: once the season's finish has passed (or /season end), its characters are migrated to standard:
--   chaos_season_players.migrated_at is set (once, logged); they keep everything and trade normally.
-- Leaderboards: leaderboard.lua asks ChaosSeason.leaderboardMeta / ChaosSeason.sendBoard for the "Season" view.
-- Season stats: ChaosLeaderboard.record is wrapped (bounty contracts, rift tiers, world bosses, goblins).
-- Season uniques: ChaosUniqueItems entries with `season = <id>`; loot.lua asks ChaosSeason.uniqueBlocked.
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.season:
--   client -> server  open | join {confirm?}
--   server -> client  state {open, season, mine, track, unlocked} | confirm {text}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/season_core.lua")

Chaos.seasonConfig = dofile("data/scripts/chaos/season_config.lua")
local cfg = Chaos.seasonConfig
local S = ChaosSeason
local OPCODE = ChaosOpcodes.season or 246
local T = cfg.tables
local iso = cfg.isolation
local NOERR = RETURNVALUE_NOERROR or 0
local NOTPOSSIBLE = RETURNVALUE_NOTPOSSIBLE or 1
local CONTAINER_POS = CONTAINER_POSITION or 0xFFFF

S.ov = S.ov or {} -- [seasonId] = {start, finish} from server_config (/season start|end)
S.rows = S.rows or {} -- guid -> row {season, migrated, account} | false (online characters, and offline lookups)
S.rowAt = S.rowAt or {} -- guid -> os.time of an offline lookup (cached offlineCacheSeconds)
S.stats = S.stats or {} -- guid -> {[stat] = value} (season stats of online season characters)
S.reached = S.reached or {} -- accountId -> list of {season, key, by, at}
S.members = S.members or {} -- guid -> true: characters of the running season (not migrated)
S.pending = S.pending or {} -- guid -> os.time the join confirmation expires
S.ladderCache = {}
local offlineCacheSeconds = 60

local function log(text)
	print("[Chaos season] " .. text)
end

local function now()
	return os.time()
end

local function seasons()
	return cfg.seasons
end

function S.current()
	return S.active(cfg.seasons, now(), S.ov)
end

local function trackOf(season)
	return (season and season.track) or cfg.track
end

local function staff(player)
	return player:getGroup():getId() >= iso.exemptGroup
end

local function hasGlobal(name)
	return _G[name] ~= nil
end

-- ---------------------------------------------------------------- server_config
local function getConfig(key)
	local id = db.storeQuery("SELECT `value` FROM `server_config` WHERE `config` = " .. db.escapeString(key))
	if not id then
		return nil
	end
	local v = result.getString(id, "value")
	result.free(id)
	return tonumber(v)
end

local function setConfig(key, value)
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE " ..
		"`value` = VALUES(`value`)", db.escapeString(key), db.escapeString(tostring(value))))
end

function S.loadOverrides()
	local ov = {}
	for _, s in ipairs(seasons()) do
		local start = getConfig(cfg.configPrefix .. s.id .. "_start")
		local finish = getConfig(cfg.configPrefix .. s.id .. "_end")
		if start or finish then
			ov[s.id] = {start = start, finish = finish}
		end
	end
	S.ov = ov
	return ov
end

local function logEvent(season, guid, event, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `season`, `player_id`, `event`, `detail`) VALUES (%d, %d, %d, %s, %s)",
		T.log, now(), season or 0, guid or 0, db.escapeString(event), db.escapeString(tostring(detail or ""):sub(1, 255))))
	log(string.format("%s: season %s, player %s %s", event, tostring(season), tostring(guid), tostring(detail or "")))
end

-- ---------------------------------------------------------------- the season flag (realms)
local function readRow(guid)
	local id = db.storeQuery(string.format("SELECT `season`, `migrated_at`, `account_id` FROM `%s` WHERE `player_id` = %d",
		T.players, guid))
	if not id then
		return false
	end
	local row = {season = result.getNumber(id, "season"), migrated = result.getNumber(id, "migrated_at"),
		account = result.getNumber(id, "account_id")}
	result.free(id)
	return row
end

-- row of a character (nil when it never joined a season)
function S.rowOf(guid)
	guid = tonumber(guid)
	if not guid then
		return nil
	end
	local row = S.rows[guid]
	if row == nil or (S.rowAt[guid] and now() - S.rowAt[guid] > offlineCacheSeconds) then
		row = readRow(guid)
		S.rows[guid] = row
		S.rowAt[guid] = now()
	end
	return row or nil
end

function S.realmOfGuid(guid)
	return S.realm(S.rowOf(guid), now(), seasons(), S.ov)
end

function S.realmOf(player)
	return S.realmOfGuid(player:getGuid())
end

local function realmByName(name)
	local guid = Chaos.findPlayer(name)
	if not guid then
		return nil
	end
	return S.realmOfGuid(guid)
end

function S.loadMembers()
	local members = {}
	local season = S.current()
	if season then
		local rows = Chaos.select(string.format("SELECT `player_id` FROM `%s` WHERE `season` = %d AND `migrated_at` = 0",
			T.players, season.id), {{"player_id", "n"}})
		for _, r in ipairs(rows) do
			members[r.player_id] = true
		end
	end
	S.members = members
	return members
end

-- ---------------------------------------------------------------- isolation
local function message(player, key)
	player:sendCancelMessage(iso.messages[key] or iso.messages.move)
end

-- a refused item move: the engine then shows its own "Sorry, not possible." as the cancel message, so the reason goes
-- to the console / screen as a text message (at most every 2 seconds per player)
local lastNotice = {}
local function notice(player, key)
	local id = player:getId()
	if (lastNotice[id] or 0) + 2 > now() then
		return
	end
	lastNotice[id] = now()
	player:sendTextMessage(MESSAGE_STATUS_WARNING or MESSAGE_INFO_DESCR, iso.messages[key] or
		(cfg.modes and cfg.modes.messages[key]) or iso.messages.move) -- modes: season_modes.lua
end

-- tags of a thing and of every container around it; returns the tile when it lies on the ground (else nil)
local function chainTags(thing, out)
	local guard = 0
	while thing and type(thing) ~= "boolean" and guard < 24 do
		guard = guard + 1
		if thing:isTile() then
			return thing
		end
		if not thing:isItem() then
			return nil -- a creature: the player's own inventory
		end
		local tag = S.tagRealm(thing:getCustomAttribute(iso.tagKey), now(), seasons(), S.ov)
		if tag ~= nil then
			out[#out + 1] = tag
		end
		thing = thing:getParent()
	end
	return nil
end

local function houseRealm(tile)
	local house = tile and tile:getHouse()
	if not house then
		return nil
	end
	local owner = house:getOwnerGuid()
	if not owner or owner == 0 then
		return nil
	end
	return S.realmOfGuid(owner)
end

local mailboxSet = {}
for _, id in ipairs(iso.mailboxIds) do
	mailboxSet[id] = true
end

local function isMailboxTile(tile)
	for _, it in ipairs(tile:getItems() or {}) do
		if mailboxSet[it:getId()] then
			return true
		end
	end
	return false
end

-- receiver name of a parcel (its label) or letter, or nil
local function receiverOf(item)
	local id = item:getId()
	if id == iso.letterId then
		return S.mailReceiver(item:getAttribute(ITEM_ATTRIBUTE_TEXT))
	end
	if id == iso.parcelId and item:isContainer() then
		for _, it in ipairs(item:getItems() or {}) do
			if it:getId() == iso.labelId then
				local name = S.mailReceiver(it:getAttribute(ITEM_ATTRIBUTE_TEXT))
				if name then
					return name
				end
			end
		end
	end
	return nil
end

-- called first in Player:onMoveItem (tools/patch_season_events.py); returns a RETURNVALUE
function S.onMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not S.current() or staff(player) then
		return NOERR
	end
	local m = {mover = S.realmOf(player), tags = {}}
	-- source: the item, the containers around it, the house it lies in
	local fromTile = chainTags(item, m.tags)
	m.houseFrom = houseRealm(fromTile)
	-- destination
	if toPosition.x ~= CONTAINER_POS then
		local tile = Tile(toPosition)
		if tile then
			m.houseTo = houseRealm(tile)
			if isMailboxTile(tile) then
				local name = receiverOf(item)
				if name then
					m.mail = realmByName(name)
				end
			end
		end
	elseif toCylinder and type(toCylinder) ~= "boolean" and toCylinder:isItem() then
		local toTile = chainTags(toCylinder, m.tags)
		m.houseTo = houseRealm(toTile)
	end
	local ok, why = S.moveCheck(m)
	if ok and S.modesMove then -- season modes (season_modes.lua): Self-Found items, loot and mail
		ok, why = S.modesMove(player, item, toPosition, toCylinder)
	end
	if ok then
		return NOERR
	end
	notice(player, why)
	return NOTPOSSIBLE
end

-- tag what lands on the ground with the dropper's realm; untag own items that reach the inventory (they stack again)
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item or not S.current() or staff(player) then
		return
	end
	if toPosition.x ~= CONTAINER_POS then
		local it = ItemType(item:getId())
		if it and it:isPickupable() then
			item:setCustomAttribute(iso.tagKey, S.realmOf(player))
		end
	elseif item:getCustomAttribute(iso.tagKey) ~= nil and item:getTopParent() == player then
		item:removeCustomAttribute(iso.tagKey)
	end
end
moved:register(50)

local trade = EventCallback
trade.onTradeRequest = function(player, target, item)
	if not S.current() or S.tradeAllowed(S.realmOf(player), S.realmOf(target), staff(player), staff(target)) then
		return true
	end
	message(player, "trade")
	return false
end
trade:register(50)

local accept = EventCallback
accept.onTradeAccept = function(player, target, item, targetItem)
	if not S.current() or S.tradeAllowed(S.realmOf(player), S.realmOf(target), staff(player), staff(target)) then
		return true
	end
	message(player, "trade")
	message(target, "trade")
	return false
end
accept:register(50)

local partyJoin = EventCallback
partyJoin.onJoin = function(party, player)
	local leader = party:getLeader()
	if not leader or not S.current() then
		return true
	end
	if S.partyAllowed(S.realmOf(leader), S.realmOf(player), staff(leader), staff(player)) then
		return true
	end
	message(player, "party")
	leader:sendTextMessage(MESSAGE_INFO_DESCR, iso.messages.party)
	return false
end
partyJoin:register(50)

-- monster corpses: the realm of the corpse owner (the engine's most damage player)
local drop = EventCallback
drop.onDropLoot = function(monster, corpse)
	if not corpse or not S.current() then
		return
	end
	local ok, ownerId = pcall(function() return corpse:getCorpseOwner() end)
	local owner = ok and ownerId and ownerId ~= 0 and Player(ownerId) or nil
	if owner and not staff(owner) then
		corpse:setCustomAttribute(iso.tagKey, S.realmOf(owner))
	end
end
drop:register(50)

-- Chaos bank transfer (bank.lua): true when the gold may not go to that character
function S.transferBlocked(player, targetGuid)
	if not S.current() or staff(player) then
		return false
	end
	S.transferBlockedText = iso.messages.bank
	if S.modesTransferBlocked and S.modesTransferBlocked(player, targetGuid) then -- season modes (season_modes.lua)
		S.transferBlockedText = cfg.modes.messages.bank
		return true
	end
	return S.realmOf(player) ~= S.realmOfGuid(targetGuid)
end
S.transferBlockedText = iso.messages.bank

-- the NPC bank transfer (Player.transferMoneyTo of data/lib/core/player.lua, every bank NPC): refused between realms.
-- tools/patch_season_events.py puts the call into that function; without the patch it is wrapped here at runtime
function S.npcTransferBlocked(player, targetGuid)
	local ok, blocked = pcall(S.transferBlocked, player, tonumber(targetGuid) or 0)
	if ok and blocked then
		player:sendCancelMessage(S.transferBlockedText or "You cannot transfer gold to that character.")
		return true
	end
	return false
end
if not ChaosSeasonTransferPatched and Player and Player.transferMoneyTo and not S.transferWrapped then
	S.transferWrapped = true
	local stockTransfer = Player.transferMoneyTo
	Player.transferMoneyTo = function(self, target, amount)
		if target and S.npcTransferBlocked(self, target.guid) then
			return false
		end
		return stockTransfer(self, target, amount)
	end
	print("[Warning - Chaos season] data/lib/core/player.lua is not patched (tools/patch_season_events.py): the NPC bank transfer is guarded at runtime")
end

-- season uniques (loot.lua rollUniques): true when this season unique may not drop for `owner` (a Player or nil)
function S.uniqueBlocked(uniqueSeason, owner)
	local realm = owner and S.realmOf(owner) or nil
	return not S.uniqueAllowed(uniqueSeason, realm, now(), seasons(), S.ov)
end

-- ---------------------------------------------------------------- account-wide Chaos Coins
-- the store (shop.lua): why `target` (a Player, or the guid of an offline gift receiver) may not get `offer`, or nil.
-- gift: bought by another character (name = the receiver's name for the text)
function S.storeProblem(target, offer, gift, name)
	if not S.current() or not cfg.store then
		return nil
	end
	local realm
	if type(target) == "number" then
		realm = S.realmOfGuid(target)
	else
		if staff(target) then
			return nil
		end
		realm = S.realmOf(target)
		name = name or target:getName()
	end
	return S.storeText(realm, offer, cfg.store, gift, name)
end

-- the season pass (seasonpass.lua): why this character may not claim `reward` now, or nil
function S.passClaimProblem(player, reward)
	if not S.current() or staff(player) or S.passClaimAllowed(reward, S.realmOf(player), cfg.passItems) then
		return nil
	end
	return cfg.passItems and cfg.passItems.message or "Season characters cannot claim this now."
end

-- the market (market.lua, no change there): a season character lists, buys and posts buy orders for gold only.
-- ChaosMarket.list / buy / orderPost are wrapped (again after a /reload of market.lua), as ChaosLeaderboard.record is
local MARKET_CURRENCY = {
	list = function(d) return (tonumber(d.coins) or 0) > 0 and "coins" or "gold" end,
	buy = function(d) return d.cur == "coins" and "coins" or "gold" end,
	orderPost = function(d) return d.cur == "coins" and "coins" or "gold" end,
	fill = function() return "gold" end -- wrapped for the season modes only (Self-Found: no market)
}
S.marketWrapped = S.marketWrapped or {}
function S.marketRefusal(player, action, d)
	local pick = MARKET_CURRENCY[action]
	if not pick or not S.current() or staff(player) then
		return nil
	end
	local modes = S.modesMarketRefusal and S.modesMarketRefusal(player, action) -- season modes (season_modes.lua)
	if modes then
		return modes
	end
	local ok, currency = pcall(pick, type(d) == "table" and d or {})
	if ok and not S.marketCurrencyAllowed(S.realmOf(player), currency, cfg.market) then
		return cfg.market and cfg.market.message or "Season markets trade for gold only."
	end
	return nil
end

function S.wrapMarket()
	local MK = ChaosMarket
	if not MK then
		return
	end
	for action in pairs(MARKET_CURRENCY) do
		local fn = MK[action]
		if type(fn) == "function" and fn ~= S.marketWrapped[action] then
			local original = fn
			local wrapped = function(player, d, ...)
				local why = S.marketRefusal(player, action, d)
				if why then
					Chaos.sendChunked(player, ChaosOpcodes.market or 221, json.encode({action = "error", data = {text = why}}))
					return false
				end
				return original(player, d, ...)
			end
			S.marketWrapped[action] = wrapped
			MK[action] = wrapped
		end
	end
end

-- season modifier: experience
local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	local season = S.current()
	local mult = season and season.modifier and season.modifier.expMult
	if mult and mult ~= 1 and source and source:isMonster() and S.realmOf(player) == season.id then
		return math.floor(exp * mult)
	end
	return exp
end
xp:register()

-- ---------------------------------------------------------------- stats and the reward track
local function loadStats(guid, season)
	local stats = {}
	local rows = Chaos.select(string.format("SELECT `stat`, `value` FROM `%s` WHERE `season` = %d AND `player_id` = %d",
		T.progress, season, guid), {{"stat", "s"}, {"value", "n"}})
	for _, r in ipairs(rows) do
		stats[r.stat] = r.value
	end
	return stats
end

local function loadReached(account)
	local list = Chaos.select(string.format("SELECT `season`, `milestone`, `player_name`, `reached_at` FROM `%s` WHERE " ..
		"`account_id` = %d", T.rewards, account), {{"season", "n"}, {"milestone", "s"}, {"player_name", "s"}, {"reached_at", "n"}})
	local out = {}
	for _, r in ipairs(list) do
		out[#out + 1] = {season = r.season, key = r.milestone, by = r.player_name, at = r.reached_at}
	end
	S.reached[account] = out
	return out
end

local function reachedMap(account, seasonId)
	local map = {}
	for _, r in ipairs(S.reached[account] or {}) do
		if r.season == seasonId then
			map[r.key] = {by = r.by, at = r.at}
		end
	end
	return map
end

local function milestoneDef(seasonId, key)
	local season = S.byId(seasons(), seasonId)
	for _, m in ipairs(trackOf(season)) do
		if m.key == key then
			return m
		end
	end
	return nil
end

-- give every reward of the account this character does not have yet; returns the names of what was added
function S.deliverRewards(player)
	local added = {}
	local female = player:getSex() == PLAYERSEX_FEMALE
	for _, r in ipairs(S.reached[player:getAccountId()] or {}) do
		local m = milestoneDef(r.season, r.key)
		local reward = m and m.reward
		if reward then
			if reward.kind == "outfit" or reward.kind == "addon" then
				local addons = reward.kind == "addon" and (reward.addons or 3) or 0
				local mine = S.rewardLook(reward, female)
				local fresh = not player:hasOutfit(mine, addons)
				-- both looks, so a sex change keeps the reward
				for _, look in ipairs({reward.male, reward.female}) do
					if look and not player:hasOutfit(look, addons) then
						if addons > 0 then
							player:addOutfitAddon(look, addons)
						else
							player:addOutfit(look)
						end
					end
				end
				if fresh then
					added[#added + 1] = reward.name or "an outfit"
				end
			elseif reward.kind == "mount" then
				if not player:hasMount(reward.id) then
					player:addMount(reward.id)
					added[#added + 1] = reward.name or "a mount"
				end
			end
		end
	end
	if #added > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Season rewards of your account: " .. table.concat(added, ", ") .. ".")
	end
	return added
end

-- account titles (title rewards) -> {{title, rankName}} for the look text / window
function S.titlesOf(account)
	local out = {}
	for _, r in ipairs(S.reached[account] or {}) do
		local m = milestoneDef(r.season, r.key)
		if m and m.reward.kind == "title" then
			local season = S.byId(seasons(), r.season)
			out[#out + 1] = {title = m.reward.title, rankName = season and season.name or ("Season " .. r.season)}
		end
	end
	return out
end

-- milestones newly reached by this season character -> unlocked for the account, delivered to its online characters
function S.checkMilestones(player)
	local season = S.current()
	if not season or S.realmOf(player) ~= season.id then
		return
	end
	local guid, account = player:getGuid(), player:getAccountId()
	local stats = {}
	for k, v in pairs(S.stats[guid] or {}) do
		stats[k] = v
	end
	stats.level = player:getLevel()
	local due = S.milestonesDue(trackOf(season), stats, reachedMap(account, season.id), hasGlobal)
	if #due == 0 then
		return
	end
	for _, m in ipairs(due) do
		db.query(string.format("INSERT IGNORE INTO `%s` (`account_id`, `season`, `milestone`, `player_id`, `player_name`, " ..
			"`reached_at`) VALUES (%d, %d, %s, %d, %s, %d)", T.rewards, account, season.id, db.escapeString(m.key), guid,
			db.escapeString(player:getName()), now()))
		logEvent(season.id, guid, "milestone", m.key)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s milestone: %s. Unlocked for your whole account: %s.",
			season.name, m.name, S.rewardText(m.reward)))
	end
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_BLUE)
	loadReached(account)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == account then
			S.deliverRewards(p)
			S.sendState(p, false)
		end
	end
end

-- one ChaosLeaderboard.record call -> the season stat of a season character
function S.onRecord(board, who, value)
	local mode = cfg.stats[board]
	local season = S.current()
	if not mode or not season then
		return
	end
	local guid
	if type(who) == "userdata" then
		guid = who:getGuid()
	elseif type(who) == "table" then
		guid = tonumber(who.guid)
	else
		guid = tonumber(who)
	end
	if not guid or S.realmOfGuid(guid) ~= season.id then
		return
	end
	value = math.max(0, math.floor(tonumber(value) or 0))
	local expr = mode == "max" and string.format("GREATEST(`value`, %d)", value)
		or (mode == "count" and "`value` + 1" or string.format("`value` + %d", value))
	local first = mode == "count" and 1 or value
	db.query(string.format("INSERT INTO `%s` (`season`, `player_id`, `stat`, `value`, `updated_at`) VALUES (%d, %d, %s, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `value` = %s, `updated_at` = VALUES(`updated_at`)", T.progress, season.id, guid,
		db.escapeString(board), first, now(), expr))
	local player = Player(guid)
	if player then
		local stats = S.stats[guid] or {}
		stats[board] = S.mergeStat(mode, stats[board], value)
		S.stats[guid] = stats
		S.checkMilestones(player)
	end
end

-- wrap ChaosLeaderboard.record (again after a /reload of leaderboard.lua)
function S.wrapLeaderboard()
	local LB = ChaosLeaderboard
	if not LB or not LB.record or LB.record == S.wrappedRecord then
		return
	end
	local original = LB.record
	S.wrappedRecord = function(board, who, value, mode)
		local entry = original(board, who, value, mode)
		local ok, err = pcall(S.onRecord, board, who, value)
		if not ok then
			log("season stat failed: " .. tostring(err))
		end
		return entry
	end
	LB.record = S.wrappedRecord
end

-- ---------------------------------------------------------------- migration (end of season)
local function migrateRow(guid, seasonId, why)
	if S.modesMigrated then -- season modes (season_modes.lua): reset the mode, the end-of-season achievements
		pcall(S.modesMigrated, guid, seasonId, why)
	end
	db.query(string.format("UPDATE `%s` SET `migrated_at` = %d WHERE `player_id` = %d AND `migrated_at` = 0",
		T.players, now(), guid))
	S.rows[guid] = nil
	S.members[guid] = nil
	logEvent(seasonId, guid, "migrate", why)
	local p = Player(guid)
	if p and why == "fallen" then -- a fallen Hardcore character (season_modes.lua tells it)
		S.rowOf(guid)
		S.sendState(p, false)
	elseif p then
		local season = S.byId(seasons(), seasonId)
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s has ended. This character is now a standard character: " ..
			"it keeps its level, skills, items and passive tree and can trade with everyone.", season and season.name or "The season"))
		S.rowOf(guid)
		S.sendState(p, false)
	end
end

S.migrateRow = migrateRow -- season modes (season_modes.lua): a fallen Hardcore character migrates at once

-- migrate every season character whose season has ended; idempotent. Returns the number migrated.
function S.migrateAll(why)
	local rows = Chaos.select(string.format("SELECT `player_id`, `season`, `migrated_at` FROM `%s` WHERE `migrated_at` = 0",
		T.players), {{"player_id", "n"}, {"season", "n"}, {"migrated_at", "n"}})
	for _, r in ipairs(rows) do
		r.migrated = r.migrated_at
	end
	local plan = S.migrationPlan(rows, now(), seasons(), S.ov)
	for _, r in ipairs(plan) do
		migrateRow(r.player_id, r.season, why or "season ended")
	end
	if #plan > 0 then
		log(string.format("migrated %d season character(s) to standard (%s)", #plan, why or "season ended"))
	end
	return #plan
end

-- ---------------------------------------------------------------- joining
local function countItems(container)
	if not container then
		return 0
	end
	local n = 0
	for _, it in ipairs(container:getItems(true) or {}) do
		if not it:isContainer() then
			n = n + 1
		end
	end
	return n
end

local function storedItems(player)
	local n = countItems(player:getInbox())
	if player.getStoreInbox then
		n = n + countItems(player:getStoreInbox())
	end
	for id = 0, 50 do
		n = n + countItems(player:getDepotChest(id, false))
	end
	return n
end

function S.joinInfo(player)
	return {level = player:getLevel(), row = S.rowOf(player:getGuid()), items = storedItems(player),
		party = player:getParty() ~= nil, house = player:getHouse() ~= nil}
end

local function joinTerms(season)
	local jc = cfg.join
	local parts = {}
	if jc.wipeInventory then
		parts[#parts + 1] = "every item you carry is destroyed"
	end
	if jc.wipeBank then
		parts[#parts + 1] = "your bank balance and supply stash are emptied"
	end
	return string.format("Join %s %s? This cannot be undone: %s. Until the season ends this character can only trade, " ..
		"mail and party with %s characters. At the end it becomes a standard character and keeps everything.",
		season.name, season.tag or "", table.concat(parts, ", "), season.name)
end

local function doJoin(player, season)
	local jc = cfg.join
	if jc.wipeInventory then
		for slot = 1, 20 do
			local ok, item = pcall(function() return player:getSlotItem(slot) end)
			if ok and item then
				item:remove()
			end
		end
	end
	if jc.wipeBank then
		player:setBankBalance(0)
		db.query("UPDATE `" .. (Chaos.tables.bank or "chaos_bank") .. "` SET `stars` = 0 WHERE `player_id` = " .. player:getGuid())
		db.query("DELETE FROM `" .. (Chaos.tables.stash or "chaos_stash") .. "` WHERE `player_id` = " .. player:getGuid())
	end
	local guid = player:getGuid()
	db.query(string.format("INSERT INTO `%s` (`player_id`, `account_id`, `season`, `joined_at`, `migrated_at`) VALUES " ..
		"(%d, %d, %d, %d, 0)", T.players, guid, player:getAccountId(), season.id, now()))
	S.rows[guid], S.rowAt[guid] = nil, nil
	S.members[guid] = true
	S.stats[guid] = {}
	S.ladderCache = {}
	logEvent(season.id, guid, "join", player:getName() .. " level " .. player:getLevel())
	local NP = ChaosNewPlayer
	if jc.regiveKit and NP and NP.giveKit and NP.getS and (tonumber(NP.getS(player, "kit")) or 0) > 0 then
		pcall(NP.giveKit, player)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Welcome to %s! %s is now a season character %s. " ..
		"The season ends in %s. Adventure > Season shows your milestones.", season.name, player:getName(), season.tag or "",
		S.formatDuration(select(2, S.times(season, S.ov)) - now())))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED or CONST_ME_MAGIC_BLUE)
	pcall(function() player:save() end)
end

-- confirm = false: check and ask for the confirmation; true: join when the confirmation is still open
function S.join(player, confirm, modeKey)
	local guid = player:getGuid()
	local season, reason = S.joinCheck(S.joinInfo(player), cfg, now(), S.ov)
	if not season then
		S.pending[guid] = nil
		player:sendTextMessage(MESSAGE_INFO_DESCR, reason)
		Chaos.send(player, OPCODE, "notice", {text = reason})
		return false
	end
	if confirm and S.pending[guid] and S.pending[guid] >= now() then
		local mode -- season modes (season_modes.lua): the mode picked in the confirmation (nil key = Standard)
		if S.modesPick then
			local why
			mode, why = S.modesPick(modeKey)
			if not mode then
				player:sendTextMessage(MESSAGE_INFO_DESCR, why)
				return false
			end
		end
		S.pending[guid] = nil
		doJoin(player, season)
		if mode and S.modesJoined then
			S.modesJoined(player, season, mode)
		end
		S.sendState(player, false)
		return true
	end
	S.pending[guid] = now() + cfg.join.confirmSeconds
	local text = joinTerms(season)
	player:sendTextMessage(MESSAGE_INFO_DESCR, text .. string.format(" Confirm in the Season window within %d seconds.",
		cfg.join.confirmSeconds))
	Chaos.send(player, OPCODE, "confirm", {text = text, seconds = cfg.join.confirmSeconds,
		modes = S.modesChoices and S.modesChoices() or nil}) -- season modes (season_modes.lua)
	return false
end

-- ---------------------------------------------------------------- window state
local function seasonInfo(season)
	if not season then
		return nil
	end
	local start, finish = S.times(season, S.ov)
	local t = now()
	local st = S.status(season, t, S.ov)
	return {id = season.id, name = season.name, tag = season.tag, status = st, start = start, finish = finish,
		startsIn = st == "upcoming" and (start - t) or nil, endsIn = st == "active" and (finish - t) or nil,
		modifier = season.modifier and {name = season.modifier.name, description = season.modifier.description} or nil}
end

-- the season the window shows: the running one, else the next, else the last that ended
local function shownSeason()
	local t = now()
	local s = S.active(seasons(), t, S.ov) or S.upcoming(seasons(), t, S.ov)
	if s then
		return s
	end
	local last, lastEnd
	for _, x in ipairs(seasons()) do
		local _, finish = S.times(x, S.ov)
		if finish and (not lastEnd or finish > lastEnd) then
			last, lastEnd = x, finish
		end
	end
	return last
end

function S.stateOf(player)
	local season = shownSeason()
	local guid, account = player:getGuid(), player:getAccountId()
	local row = S.rowOf(guid)
	local realm = S.realmOf(player)
	local _, reason = S.joinCheck(S.joinInfo(player), cfg, now(), S.ov)
	local mine = {realm = realm, seasonal = realm > 0, veteran = row and realm == 0 or false,
		joinedSeason = row and row.season or nil, eligible = reason == nil, reason = reason, level = player:getLevel()}
	if S.modesMine then -- season modes (season_modes.lua): mode, fallen, heartbeat
		S.modesMine(player, mine)
	end
	local stats = {}
	if season and realm == season.id then
		for k, v in pairs(S.stats[guid] or {}) do
			stats[k] = v
		end
		stats.level = player:getLevel()
	end
	local track = season and S.trackView(trackOf(season), stats, reachedMap(account, season.id), hasGlobal) or {}
	local titles = {}
	for _, t in ipairs(S.titlesOf(account)) do
		titles[#titles + 1] = t.title
	end
	return {season = seasonInfo(season), mine = mine, track = track, titles = titles}
end

function S.sendState(player, open)
	local data = S.stateOf(player)
	data.open = open and true or false
	Chaos.send(player, OPCODE, "state", data)
end

local function infoText(player)
	local d = S.stateOf(player)
	local s = d.season
	if not s then
		return "No season is configured."
	end
	local lines = {}
	if s.status == "active" then
		lines[#lines + 1] = string.format("%s %s is running: %s left.", s.name, s.tag or "", S.formatDuration(s.endsIn))
	elseif s.status == "upcoming" then
		lines[#lines + 1] = string.format("%s %s starts in %s.", s.name, s.tag or "", S.formatDuration(s.startsIn))
	else
		lines[#lines + 1] = string.format("%s has ended.", s.name)
	end
	if s.modifier and s.status ~= "ended" then
		lines[#lines + 1] = string.format("Modifier %s: %s", s.modifier.name, s.modifier.description)
	end
	if d.mine.seasonal then
		lines[#lines + 1] = "This character is a season character."
	elseif d.mine.eligible then
		lines[#lines + 1] = "This character can join: Adventure > Season."
	elseif s.status == "active" then
		lines[#lines + 1] = "Join: " .. tostring(d.mine.reason)
	end
	for _, m in ipairs(d.track) do
		lines[#lines + 1] = string.format("  [%s] %s (%d/%d) - %s", m.unlocked and "x" or " ", m.name, m.progress, m.value,
			m.reward)
	end
	return table.concat(lines, "\n")
end

-- ---------------------------------------------------------------- look text
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() then
		local pronoun = thing:getId() == self:getId() and "You" or (thing:getSex() == PLAYERSEX_FEMALE and "She" or "He")
		local line = S.lookLine(S.rowOf(thing:getGuid()), now(), seasons(), S.ov, pronoun)
		if line then
			description = (description or "") .. "\n" .. line
		end
		local titles = S.titlesOf(thing:getAccountId())
		if #titles > 0 then
			local parts = {}
			for _, t in ipairs(titles) do
				parts[#parts + 1] = string.format("%s (%s)", t.title, t.rankName)
			end
			description = (description or "") .. string.format("\n%s %s the season title%s %s.", pronoun,
				pronoun == "You" and "hold" or "holds", #parts > 1 and "s" or "", table.concat(parts, ", "))
		end
	end
	return description
end
-- after the base default_onLook (0) and the leaderboard titles (100)
look:register(101)

-- ---------------------------------------------------------------- leaderboards ("Season" view)
local function lbCfg()
	return Chaos.leaderboardConfig
end

-- added to the leaderboard meta while a season runs (the client shows the Season toggle)
function S.leaderboardMeta(player)
	local season = S.current()
	if not season or not ChaosLeaderboard or not lbCfg() then
		return nil
	end
	return {id = season.id, name = season.name, tag = season.tag,
		modes = S.modesLadderTabs and S.modesLadderTabs() or nil} -- season modes (season_modes.lua)
end

local function vocationName(id)
	local v = Vocation(id)
	return v and v:getName() or ("Vocation " .. id)
end

local function boardTitle(guid, board)
	local LB = ChaosLeaderboard
	local t = LB.titlesOf and LB.titlesOf(guid)
	if not t or #t == 0 then
		return nil
	end
	local pick = t[1]
	for _, x in ipairs(t) do
		if x.board == board then
			pick = x
		end
	end
	return #t > 1 and string.format("%s +%d", pick.title, #t - 1) or pick.title
end

local function ladderWhere(g, seasonId)
	return string.format("p.`vocation` IN (%s) AND p.`group_id` < %d AND p.`deletion` = 0 AND sp.`season` = %d AND " ..
		"sp.`migrated_at` = 0", table.concat(g.ids, ","), cfg.ladder.staffGroup, seasonId) ..
		(ChaosAntibot and ChaosAntibot.heldClause and ChaosAntibot.heldClause("p.") or "") -- anti-bot review holds (antibot.lua)
end

local function seasonLadderRows(g, seasonId)
	local key = seasonId .. ":" .. g.key
	local c = S.ladderCache[key]
	if c and now() - c.at < cfg.ladder.cacheSeconds then
		return c.rows
	end
	local rows = Chaos.select(string.format("SELECT p.`id`, p.`name`, p.`level`, p.`vocation` FROM `players` p JOIN `%s` sp " ..
		"ON sp.`player_id` = p.`id` WHERE %s ORDER BY p.`experience` DESC, p.`id` ASC LIMIT %d", T.players,
		ladderWhere(g, seasonId), cfg.ladder.rows), {{"id", "n"}, {"name", "s"}, {"level", "n"}, {"vocation", "n"}})
	for i, r in ipairs(rows) do
		r.rank = i
	end
	S.ladderCache[key] = {at = now(), rows = rows}
	return rows
end

local function groupOf(player, groupKey)
	local LB = ChaosLeaderboard
	local groups = LB.classGroups()
	local key = tonumber(groupKey)
	local vocId = player:getVocation():getId()
	local own
	for _, g in ipairs(groups) do
		if key and g.key == key then
			return g
		end
		for _, v in ipairs(g.ids) do
			if v == vocId then
				own = g
			end
		end
	end
	return own or groups[1], own
end
S.ladderHelpers = {where = ladderWhere, groupOf = groupOf, vocationName = vocationName, boardTitle = boardTitle} -- modes

-- the Season view of a leaderboard (called by leaderboard.lua). Returns true when it answered.
function S.sendBoard(player, key, groupKey, mode)
	local season, LB, lc = S.current(), ChaosLeaderboard, lbCfg()
	if not season or not LB or not lc then
		return false
	end
	if mode and mode ~= "all" and S.modesSendBoard then -- season modes (season_modes.lua): one mode's tab
		return S.modesSendBoard(player, key, groupKey, mode)
	end
	local data
	if key == lc.ladder.key then
		local g = groupOf(player, groupKey)
		if not g then
			return false
		end
		local rows = {}
		for _, r in ipairs(seasonLadderRows(g, season.id)) do
			rows[#rows + 1] = {rank = r.rank, name = r.name, value = r.level, level = r.level,
				vocation = vocationName(r.vocation), title = boardTitle(r.id)}
		end
		local own
		local _, mine = groupOf(player, nil)
		if mine and mine.key == g.key and S.realmOf(player) == season.id and not staff(player) then
			local exp = player:getExperience()
			local id = db.storeQuery(string.format("SELECT COUNT(*) AS `n` FROM `players` p JOIN `%s` sp ON sp.`player_id` = " ..
				"p.`id` WHERE %s AND p.`id` <> %d AND (p.`experience` > %d OR (p.`experience` = %d AND p.`id` < %d))", T.players,
				ladderWhere(g, season.id), player:getGuid(), exp, exp, player:getGuid()))
			local ahead = 0
			if id then
				ahead = result.getNumber(id, "n")
				result.free(id)
			end
			own = {rank = ahead + 1, value = player:getLevel()}
		end
		data = {key = lc.ladder.key, group = g.key, rows = rows, own = own}
	else
		local b
		for _, x in ipairs(lc.boards) do
			if x.key == key then
				b = x
			end
		end
		b = b or lc.boards[1]
		local ranked = {}
		for _, e in ipairs(LB.rankedBoard(b.key)) do
			if S.members[e.guid] then
				ranked[#ranked + 1] = e
			end
		end
		local rows, own = {}, nil
		for i, e in ipairs(ranked) do
			if i <= lc.rows then
				rows[#rows + 1] = {rank = i, name = e.name, value = e.value, count = e.count, title = boardTitle(e.guid, b.key)}
			end
			if e.guid == player:getGuid() then
				own = {rank = i, value = e.value, count = e.count}
			end
		end
		data = {key = b.key, rows = rows, total = #ranked, champions = {}, own = own}
	end
	local t = LB.now and LB.now() or now()
	data.week = LB.current and LB.current.week or nil
	data.resetIn = math.max(0, LB.nextReset(t, lc.resetHour) - t)
	data.season = {id = season.id, name = season.name, tag = season.tag}
	Chaos.send(player, ChaosOpcodes.leaderboard or 229, "board", data)
	return true
end

-- ---------------------------------------------------------------- events
local lastActive -- id of the season running at the last check (start / end announcements)

local function checkSeasons(startup)
	S.wrapLeaderboard()
	S.wrapMarket()
	local season = S.current()
	local id = season and season.id or 0
	if not startup and lastActive ~= nil and id ~= lastActive then
		if season then
			Game.broadcastMessage(string.format("%s %s has begun! New characters can join in Adventure > Season.", season.name,
				season.tag or ""), MESSAGE_EVENT_ADVANCE)
			logEvent(season.id, 0, "start", "season started")
		end
		local old = S.byId(seasons(), lastActive)
		if old then
			Game.broadcastMessage(string.format("%s has ended. Its characters are now standard characters.", old.name),
				MESSAGE_EVENT_ADVANCE)
			logEvent(old.id, 0, "end", "season ended")
		end
		S.ladderCache = {}
	end
	lastActive = id
	S.migrateAll("season ended")
	S.loadMembers()
end

local startup = GlobalEvent("ChaosSeasonStartup")
function startup.onStartup()
	S.loadOverrides()
	checkSeasons(true)
	local season = S.current()
	log(season and string.format("%s running, %d season character(s)", season.name, (function()
		local n = 0
		for _ in pairs(S.members) do
			n = n + 1
		end
		return n
	end)()) or "no season running")
	-- the isolation hooks live in base files (tools/patch_season_events.py): warn when they are missing
	local f = io.open("data/events/scripts/player.lua", "r")
	if f then
		local text = f:read("*a")
		f:close()
		if not text:find("ChaosSeason.onMoveItem", 1, true) then
			log("WARNING: Player:onMoveItem does not call ChaosSeason.onMoveItem: items on the ground, in corpses, houses " ..
				"and mail are NOT isolated. Run server/tools/patch_season_events.py")
		end
	end
	f = io.open("data/events/events.xml", "r")
	if f then
		local text = f:read("*a")
		f:close()
		if not text:find('method="onTradeRequest" enabled="1"', 1, true) then
			log("WARNING: onTradeRequest is disabled in data/events/events.xml: the trade window is NOT isolated. Run " ..
				"server/tools/patch_season_events.py")
		end
	end
	return true
end
startup:register()

local think = GlobalEvent("ChaosSeasonCheck")
function think.onThink(interval)
	checkSeasons(false)
	return true
end
think:interval(cfg.checkSeconds * 1000)
think:register()

local login = CreatureEvent("ChaosSeasonLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSeasonExtended")
	player:registerEvent("ChaosSeasonAdvance")
	player:registerEvent("ChaosSeasonDeath")
	local guid, account = player:getGuid(), player:getAccountId()
	S.rows[guid], S.rowAt[guid] = nil, nil
	local row = S.rowOf(guid)
	if row and S.migrationDue(row, now(), seasons(), S.ov) then
		migrateRow(guid, row.season, "login after the season ended")
		row = S.rowOf(guid)
	end
	local season = S.current()
	S.stats[guid] = (season and row and row.season == season.id) and loadStats(guid, season.id) or {}
	loadReached(account)
	addEvent(function(cid)
		local p = Player(cid)
		if not p then
			return
		end
		S.deliverRewards(p)
		S.checkMilestones(p)
		local s = S.current()
		if s then
			if S.realmOf(p) == s.id then
				p:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s %s: %s left. Adventure > Season shows your milestones.",
					s.name, s.tag or "", S.formatDuration(select(2, S.times(s, S.ov)) - now())))
			elseif not S.rowOf(p:getGuid()) and p:getLevel() <= cfg.join.maxLevel then
				p:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s is running. This character can still join it: " ..
					"Adventure > Season in the menu.", s.name))
			end
		end
		S.sendState(p, false)
	end, 2000, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSeasonLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	S.rows[guid], S.rowAt[guid], S.stats[guid], S.pending[guid] = nil, nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

local advance = CreatureEvent("ChaosSeasonAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		S.checkMilestones(player)
		-- the window's level progress and the Join button (level) stay current while it is open
		if shownSeason() then
			S.sendState(player, false)
		end
	end
	return true
end
advance:type("advance")
advance:register()

-- player corpses: the realm of the character that died (its dropped items stay in that realm)
local death = CreatureEvent("ChaosSeasonDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if corpse and type(corpse) ~= "boolean" and corpse.isItem and corpse:isItem() and S.current() and not staff(creature) then
		corpse:setCustomAttribute(iso.tagKey, S.realmOf(creature))
	end
	return true
end
death:type("death")
death:register()

local ext = CreatureEvent("ChaosSeasonExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if msg.action == "open" then
		S.sendState(player, true)
	elseif msg.action == "join" then
		S.join(player, data.confirm == true, type(data.mode) == "string" and data.mode or nil)
	end
end
ext:type("extendedopcode")
ext:register()

-- ---------------------------------------------------------------- commands
local function godOnly(player)
	return player:getAccountType() >= (ACCOUNT_TYPE_GOD or 5)
end

local function adminStatus()
	local t = now()
	local lines = {}
	for _, s in ipairs(seasons()) do
		local start, finish = S.times(s, S.ov)
		lines[#lines + 1] = string.format("%d %s: %s, %s - %s%s", s.id, s.name, S.status(s, t, S.ov),
			start and os.date("%Y-%m-%d %H:%M", start) or "?", finish and os.date("%Y-%m-%d %H:%M", finish) or "?",
			S.ov[s.id] and " (overridden)" or "")
	end
	local n = 0
	for _ in pairs(S.members) do
		n = n + 1
	end
	lines[#lines + 1] = string.format("%d character(s) in the running season.", n)
	return table.concat(lines, "\n")
end

local function onAdmin(player, param)
	local cmd, arg = param:match("^(%S*)%s*(.*)$")
	local t = now()
	if cmd == "start" then
		if S.current() then
			player:sendTextMessage(MESSAGE_INFO_DESCR, S.current().name .. " is already running.")
			return
		end
		local s = tonumber(arg) and S.byId(seasons(), tonumber(arg)) or S.upcoming(seasons(), t, S.ov)
		if not s then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "No upcoming season in season_config.lua (add one, or give its id).")
			return
		end
		local _, finish = S.times(s, S.ov)
		if not finish or finish <= t then
			player:sendTextMessage(MESSAGE_INFO_DESCR, s.name .. "'s end date has passed: change it in season_config.lua.")
			return
		end
		setConfig(cfg.configPrefix .. s.id .. "_start", t)
		S.loadOverrides()
		logEvent(s.id, player:getGuid(), "admin", "start by " .. player:getName())
		checkSeasons(false)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Started.\n" .. adminStatus())
	elseif cmd == "end" then
		local s = S.current()
		if not s then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "No season is running. Migration check: " .. S.migrateAll("admin") ..
				" character(s) migrated.")
			return
		end
		setConfig(cfg.configPrefix .. s.id .. "_end", t)
		S.loadOverrides()
		logEvent(s.id, player:getGuid(), "admin", "end by " .. player:getName())
		checkSeasons(false)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Ended.\n" .. adminStatus())
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, adminStatus())
	end
end

local function onCommand(player, words, param)
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if words == "/season" then
		if not godOnly(player) then
			return true
		end
		onAdmin(player, param)
		return false
	end
	if param == "join" then
		S.join(player, false)
	elseif param == "join confirm" then
		S.join(player, true)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, infoText(player))
		S.sendState(player, true)
	end
	return false
end

-- staff only (players open the window from the menu)
local talk = TalkAction("/season")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	return onCommand(player, words, param)
end
talk:separator(" ")
talk:register()
