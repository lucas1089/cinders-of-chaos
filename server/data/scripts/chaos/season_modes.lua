-- Season modes: Self-Found and Hardcore for season characters (roadmap: see ROADMAP.md "Season modes").
-- Rules: season_modes_core.lua (ChaosSeasonModes, tests/season_modes_test.lua); numbers and texts: season_config.lua
-- `modes`; table chaos_season_modes (sql/chaos_season.sql, also created here). Overview: server/README.md "Season modes".
-- It extends season.lua (loaded before this file) through the ChaosSeason.modes* hooks that season.lua calls:
--   join        modesChoices (the confirmation's choices), modesPick (validate), modesJoined (store the mode)
--   isolation   modesMove (Player:onMoveItem, after the realm rule), modesTransferBlocked (bank / NPC bank),
--               modesMarketRefusal (the market wrapper), modesOrbRefusal (orbexchange.lua X.place)
--   migration   modesMigrated (end of season: survival achievements, the mode is reset; a fall migrates at once)
--   window      modesMine (the mode in the Season window state)
--   ladders     modesLadderTabs (leaderboard meta), modesSendBoard (a mode tab), fallenMark (leaderboard.lua rows)
--   loot        modesLootBonus (loot.lua: Item Find / Rarity Find), modesBuffItem (data/lib/chaos_buffs.lua)
-- Its own events: trade request / accept and party join (EventCallback), item moved (the owner tag), drop loot (the
-- corpse owner tag), death (the fall), prepare death + health change (Hardcore protections), the heartbeat on the
-- season opcode (action "beat"), look text, login / logout / level advance, a 1 s watch and the shutdown save.
--
-- Item origin: a custom attribute (modes.ownerKey, "chaos_owner") holds the guid of the character an item on the
-- ground came from (whoever dropped it), of a monster corpse's owner (the engine's corpse owner) and of a dead
-- character's corpse. A Self-Found character only moves items whose chain carries no other owner; nobody else moves
-- an item that carries a Self-Found owner. An item that reaches an inventory loses the tag (it is the holder's now).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not (ChaosSeason and ChaosSeason.realmOf and Chaos.seasonConfig) then
	dofile("data/scripts/chaos/season.lua")
end
dofile("data/scripts/chaos/season_modes_core.lua")

local S = ChaosSeason
local M = ChaosSeasonModes
local cfg = Chaos.seasonConfig
local mc = cfg.modes
local hc = mc.hc
local iso = cfg.isolation
local MSG = mc.messages
local OWNER = mc.ownerKey
local T = mc.table
local OPCODE = ChaosOpcodes.season or 246
local NOERR = RETURNVALUE_NOERROR or 0
local CONTAINER_POS = CONTAINER_POSITION or 0xFFFF

S.modeMap = S.modeMap or {} -- guid -> {ssf, hc, fallen, level, cause} (rows of the running season, not reset)
S.fallenByGuid = S.fallenByGuid or {} -- guid -> {season, level, cause} (every fall, for the ladders' marks)
S.hcState = S.hcState or {} -- creature id -> protection state (M.protection)
local fallenAt = 0 -- os.time of the last fallen cache load

local function now()
	return os.time()
end

local function log(text)
	print("[Chaos season modes] " .. text)
end

local function staff(player)
	return player:getGroup():getId() >= iso.exemptGroup
end

local depotSet = {}
for _, id in ipairs(mc.depotIds or {2589, 2590, 2591, 2592}) do
	depotSet[id] = true
end
local mailboxSet = {}
for _, id in ipairs(iso.mailboxIds) do
	mailboxSet[id] = true
end

-- ---------------------------------------------------------------- table and caches
local CREATE = "CREATE TABLE IF NOT EXISTS `" .. T .. "` (`player_id` int(11) NOT NULL, `season` smallint(5) unsigned NOT NULL, " ..
	"`ssf` tinyint(1) unsigned NOT NULL DEFAULT 0, `hc` tinyint(1) unsigned NOT NULL DEFAULT 0, `chosen_at` int(10) unsigned NOT NULL, " ..
	"`fallen_at` int(10) unsigned NOT NULL DEFAULT 0, `fallen_level` int(10) unsigned NOT NULL DEFAULT 0, " ..
	"`fallen_cause` varchar(64) NOT NULL DEFAULT '', `reset_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`), " ..
	"KEY `chaos_season_modes_season` (`season`, `fallen_at`), CONSTRAINT `chaos_season_modes_fk` FOREIGN KEY (`player_id`) " ..
	"REFERENCES `players` (`id`) ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8"

function S.modesLoad()
	local map = {}
	local season = S.current()
	if season then
		local rows = Chaos.select(string.format("SELECT `player_id`, `ssf`, `hc`, `fallen_at`, `fallen_level`, `fallen_cause` " ..
			"FROM `%s` WHERE `season` = %d AND `reset_at` = 0", T, season.id), {{"player_id", "n"}, {"ssf", "n"}, {"hc", "n"},
			{"fallen_at", "n"}, {"fallen_level", "n"}, {"fallen_cause", "s"}})
		for _, r in ipairs(rows) do
			map[r.player_id] = {ssf = r.ssf, hc = r.hc, fallen = r.fallen_at, level = r.fallen_level, cause = r.fallen_cause}
		end
	end
	S.modeMap = map
	if now() - fallenAt >= 300 then
		local fallen = {}
		for _, r in ipairs(Chaos.select(string.format("SELECT `player_id`, `season`, `fallen_level`, `fallen_cause` FROM `%s` " ..
			"WHERE `fallen_at` > 0", T), {{"player_id", "n"}, {"season", "n"}, {"fallen_level", "n"}, {"fallen_cause", "s"}})) do
			fallen[r.player_id] = {season = r.season, level = r.fallen_level, cause = r.fallen_cause}
		end
		S.fallenByGuid = fallen
		fallenAt = now()
	end
end

-- the mode a character plays now (flags of season_modes_core.lua); staff = exempt
function S.modeFlagsOfGuid(guid)
	local season = S.current()
	local row = S.modeMap[tonumber(guid) or 0]
	if not season or not row then
		return M.flags(nil, 0)
	end
	return M.flags(row, S.members[guid] and season.id or 0)
end

function S.modesOf(player)
	local f = S.modeFlagsOfGuid(player:getGuid())
	if staff(player) then
		local copy = {}
		for k, v in pairs(f) do
			copy[k] = v
		end
		copy.exempt = true
		return copy
	end
	return f
end

local function isSsfGuid(guid)
	return S.modeFlagsOfGuid(guid).ssf == true
end

-- the mark of a fallen character on any ladder: {level, cause} or nil
function S.fallenMark(guid)
	local f = S.fallenByGuid[tonumber(guid) or 0]
	if not f then
		return nil
	end
	return {level = f.level, cause = f.cause}
end

-- ---------------------------------------------------------------- joining
function S.modesChoices()
	return M.choices(mc)
end

function S.modesPick(key)
	return M.pick(mc, key)
end

local function registerHardcore(player)
	player:registerEvent("ChaosSeasonModesHealth")
	player:registerEvent("ChaosSeasonModesPrepare")
end

function S.modesJoined(player, season, mode)
	local guid = player:getGuid()
	db.query(string.format("REPLACE INTO `%s` (`player_id`, `season`, `ssf`, `hc`, `chosen_at`) VALUES (%d, %d, %d, %d, %d)",
		T, guid, season.id, mode.ssf and 1 or 0, mode.hc and 1 or 0, now()))
	S.modeMap[guid] = {ssf = mode.ssf and 1 or 0, hc = mode.hc and 1 or 0, fallen = 0}
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `season`, `player_id`, `event`, `detail`) VALUES (%d, %d, %d, 'mode', %s)",
		cfg.tables.log, now(), season.id, guid, db.escapeString(mode.key)))
	if mode.key ~= "standard" then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Mode: %s. It holds until %s ends.", mode.name, season.name))
	end
	if mode.hc then
		registerHardcore(player)
		S.hcState[player:getId()] = {loginAt = now(), lastBeat = now()}
	end
end

-- the Season window state (season.lua stateOf): mode, fall, heartbeat
function S.modesMine(player, mine)
	local f = S.modeFlagsOfGuid(player:getGuid())
	local d = M.byKey(mc, f.key)
	mine.mode = f.key
	mine.modeName = d and d.name or f.key
	mine.ssf, mine.hc = f.ssf, f.hc
	mine.fallen = S.fallenMark(player:getGuid())
	mine.heartbeat = f.hc and hc.heartbeatSeconds or nil
end

-- ---------------------------------------------------------------- isolation
-- owner tags of a thing and the containers around it; returns the tile it lies on (nil = an inventory)
local function ownerChain(thing, out)
	local guard = 0
	while thing and type(thing) ~= "boolean" and guard < 24 do
		guard = guard + 1
		if thing:isTile() then
			return thing
		end
		if not thing:isItem() then
			return nil
		end
		local tag = tonumber(thing:getCustomAttribute(OWNER))
		if tag and tag > 0 then
			out[#out + 1] = tag
		end
		thing = thing:getParent()
	end
	return nil
end

local function houseOwner(tile)
	local house = tile and tile:getHouse()
	local owner = house and house:getOwnerGuid()
	if not owner or owner == 0 then
		return nil
	end
	return owner
end

local function mailReceiver(item)
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

local function isMailboxTile(tile)
	for _, it in ipairs(tile:getItems() or {}) do
		if mailboxSet[it:getId()] then
			return true
		end
	end
	return false
end

-- season.lua S.onMoveItem, after the realm rule: true or false, reason key (cfg.modes.messages)
function S.modesMove(player, item, toPosition, toCylinder)
	local f = S.modesOf(player)
	if f.exempt then
		return true
	end
	local m = {mover = player:getGuid(), ssf = f.ssf, from = {}, to = {}, isSsf = isSsfGuid}
	m.houseFrom = houseOwner(ownerChain(item, m.from))
	if toPosition.x ~= CONTAINER_POS then
		local tile = Tile(toPosition)
		if tile then
			m.houseTo = houseOwner(tile)
			-- dropped on a tile, an item goes into the container on top of it (a corpse, a bag)
			local top = tile:getTopDownItem()
			if top and top:isContainer() then
				ownerChain(top, m.to)
			end
			local id = item:getId()
			if (id == iso.parcelId or id == iso.letterId) and isMailboxTile(tile) then
				m.mail = true
				local name = mailReceiver(item)
				m.mailTo = name and Chaos.findPlayer(name) or nil
			end
		end
	elseif toCylinder and type(toCylinder) ~= "boolean" and toCylinder:isItem() then
		m.houseTo = houseOwner(ownerChain(toCylinder, m.to))
	end
	return M.moveCheck(m)
end

local function topIsDepot(top)
	return top and type(top) ~= "boolean" and top:isItem() and depotSet[top:getId()] or false
end

-- the owner tag after an allowed move (season.lua's own callback handles the realm tag)
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item or not S.current() or staff(player) then
		return
	end
	local guid = player:getGuid()
	local top = item:getTopParent()
	local inventory = top == player
	local tag = tonumber(item:getCustomAttribute(OWNER))
	local act = M.ownerTagAction({inventory = inventory, depot = not inventory and topIsDepot(top), tag = tag, mover = guid})
	if act == "clear" then
		item:removeCustomAttribute(OWNER)
		if item:isContainer() then
			for _, it in ipairs(item:getItems(true) or {}) do
				if tonumber(it:getCustomAttribute(OWNER)) == guid then
					it:removeCustomAttribute(OWNER) -- own items stack again
				end
			end
		end
	elseif act == "set" then
		local it = ItemType(item:getId())
		if it and it:isPickupable() then
			item:setCustomAttribute(OWNER, guid)
		end
	end
end
moved:register(51)

local function refuse(player, key)
	player:sendCancelMessage(MSG[key] or MSG.trade)
end

local function tradeCheck(player, target)
	if not S.current() then
		return true
	end
	local a, b = S.modesOf(player), S.modesOf(target)
	local ok, why = M.tradeAllowed(a, b)
	if ok then
		return true
	end
	return false, why
end

local trade = EventCallback
trade.onTradeRequest = function(player, target, item)
	local ok, why = tradeCheck(player, target)
	if not ok then
		refuse(player, why)
	end
	return ok
end
trade:register(51)

local accept = EventCallback
accept.onTradeAccept = function(player, target, item, targetItem)
	local ok, why = tradeCheck(player, target)
	if not ok then
		refuse(player, why)
		refuse(target, why)
	end
	return ok
end
accept:register(51)

local partyJoin = EventCallback
partyJoin.onJoin = function(party, player)
	local leader = party:getLeader()
	if not leader or not S.current() then
		return true
	end
	local ok, why = M.partyAllowed(S.modesOf(leader), S.modesOf(player))
	if ok then
		return true
	end
	refuse(player, why)
	leader:sendTextMessage(MESSAGE_INFO_DESCR, MSG[why] or MSG.party)
	return false
end
partyJoin:register(51)

-- monster corpses: the owner (the engine's corpse owner) is the only one who takes its loot when Self-Found
local drop = EventCallback
drop.onDropLoot = function(monster, corpse)
	if not corpse or not S.current() then
		return
	end
	local ok, ownerId = pcall(function() return corpse:getCorpseOwner() end)
	local owner = ok and ownerId and ownerId ~= 0 and Player(ownerId) or nil
	if owner and not staff(owner) then
		corpse:setCustomAttribute(OWNER, owner:getGuid())
	end
end
drop:register(51)

function S.modesTransferBlocked(player, targetGuid)
	if not S.current() then
		return false
	end
	local f = S.modesOf(player)
	return not M.transferAllowed(f, S.modeFlagsOfGuid(tonumber(targetGuid) or 0))
end

function S.modesMarketRefusal(player, action)
	if not S.current() then
		return nil
	end
	local ok, why = M.marketAllowed(S.modesOf(player), action)
	return not ok and MSG[why] or nil
end

function S.modesOrbRefusal(player, action)
	if not S.current() then
		return nil
	end
	local ok, why = M.orbAllowed(S.modesOf(player), action)
	return not ok and MSG[why] or nil
end

-- ---------------------------------------------------------------- loot bonus and the buff bar
function S.modesLootBonus(player)
	if not player or not S.current() then
		return 0, 0
	end
	return M.lootBonus(S.modesOf(player), mc)
end

local WARD_TEXT = {
	login = "Login protection: you cannot be hurt for a few seconds.",
	disconnect = "Your connection is lost: you cannot be hurt and are pulled to the temple.",
	pingloss = "Your connection stalls: you cannot be hurt and are pulled to the temple if it does not come back.",
	restart = "The server is restarting: you cannot die now."
}

-- chaos_buffs.lua source "seasonMode": def.mode "ssf" (the loot bonus) | "ward" (an active Hardcore protection)
function S.modesBuffItem(player, def)
	if not S.current() then
		return nil
	end
	local f = S.modesOf(player)
	if def.mode == "ssf" then
		if not f.ssf then
			return nil
		end
		local find, rarity = M.lootBonus(f, mc)
		return {desc = string.format("No trading; +%d%% Item Find and +%d%% Rarity Find.", find, rarity)}
	end
	if not f.hc then
		return nil
	end
	local p = S.hcProtection(player)
	if not p.protected then
		return nil
	end
	local st = S.hcState[player:getId()] or {}
	local left
	if p.reason == "login" and st.loginAt then
		left = math.max(0, st.loginAt + hc.loginSeconds - now()) * 1000
	end
	return {desc = WARD_TEXT[p.reason] or def.desc, leftMs = left}
end

-- ---------------------------------------------------------------- Hardcore protections
local restart -- {hour, min, notifyMinutes, guardSeconds} of the base server save that restarts the server, or nil

local function readRestart()
	local f = io.open("data/globalevents/globalevents.xml", "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	local hour, min
	for line in text:gmatch("[^\n]+") do
		if line:find("serversave.lua", 1, true) and not line:find("<!--", 1, true) then
			hour, min = M.parseTime(line:match('time="([^"]+)"'))
		end
	end
	if not hour then
		return nil
	end
	local closes, notify = true, 5
	pcall(function()
		closes = configManager.getBoolean(configKeys.SERVER_SAVE_SHUTDOWN) or configManager.getBoolean(configKeys.SERVER_SAVE_CLOSE)
		notify = configManager.getNumber(configKeys.SERVER_SAVE_NOTIFY_DURATION)
	end)
	if not closes then
		return nil
	end
	return {hour = hour, min = min, notifyMinutes = tonumber(notify) or 5, guardSeconds = hc.restartGuardSeconds}
end

local function gameState()
	local ok, st = pcall(function() return Game.getGameState() end)
	if not ok or st == nil or st == GAME_STATE_NORMAL then
		return "normal"
	end
	return "closing"
end

-- the protection of a Hardcore character now: {protected, reason, pull}
function S.hcProtection(player)
	local st = S.hcState[player:getId()]
	if not st then
		st = {loginAt = now()}
		S.hcState[player:getId()] = st
	end
	st.connected = player:getIp() ~= 0
	st.gameState = gameState()
	st.guard = S.shutdownGuard or M.restartGuard(now(), restart)
	return M.protection(st, now(), hc)
end

local function hardcoreNow(player)
	return S.current() and S.modesOf(player).hc and not staff(player)
end

local health = CreatureEvent("ChaosSeasonModesHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING or not creature:isPlayer() or not hardcoreNow(creature) then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	if S.hcProtection(creature).protected then
		return 0, primaryType, secondaryType == COMBAT_HEALING and secondaryDamage or 0, secondaryType
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:register()

-- the safety net: whatever got past the health event (another script's damage after it, a mana shield order)
local prepare = CreatureEvent("ChaosSeasonModesPrepare")
function prepare.onPrepareDeath(creature, killer)
	if not creature:isPlayer() or not hardcoreNow(creature) or not S.hcProtection(creature).protected then
		return true
	end
	if creature:getHealth() < 1 then
		Chaos.heal(creature, 1)
	end
	return false
end
prepare:register()

local function saveHardcore(why)
	local n = 0
	for _, p in ipairs(Game.getPlayers()) do
		if hardcoreNow(p) then
			pcall(function() p:save() end)
			n = n + 1
		end
	end
	if n > 0 then
		log(string.format("saved %d Hardcore character(s): %s", n, why))
	end
end

local function pullToTemple(player, reason)
	local town = player:getTown()
	local pos = town and town:getTemplePosition()
	if not pos then
		return
	end
	player:teleportTo(pos)
	pos:sendMagicEffect(CONST_ME_TELEPORT or CONST_ME_MAGIC_BLUE)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, reason == "pingloss" and
		Chaos.t(player, "Hardcore: your connection stalled, you were pulled to the temple.") or
		Chaos.t(player, "Hardcore: your connection was lost, you were pulled to the temple."))
	log(string.format("%s pulled to the temple (%s)", player:getName(), reason))
end

local guardWas = false
local watch = GlobalEvent("ChaosSeasonModesWatch")
function watch.onThink(interval)
	if not S.current() then
		return true
	end
	local guard = M.restartGuard(now(), restart)
	if guard and not guardWas then
		saveHardcore("restart guard")
	end
	guardWas = guard
	for _, p in ipairs(Game.getPlayers()) do
		if hardcoreNow(p) then
			local st = S.hcState[p:getId()] or {loginAt = now()}
			S.hcState[p:getId()] = st
			local was = st.connected
			st.connected = p:getIp() ~= 0
			if st.connected and was == false then
				-- a client took the character over again (the engine re-attaches it, no login event): a fresh start,
				-- and the state so that the client starts its heartbeat
				st.loginAt, st.lastBeat, st.beatSeen = now(), now(), false
				pcall(S.sendState, p, false)
			end
			local lost, reason = M.lost(st, now(), hc)
			M.trackLoss(st, lost, reason, now(), hc)
			local prot = S.hcProtection(p)
			if prot.pull then
				st.pulled = true
				pullToTemple(p, prot.reason)
			end
		end
	end
	return true
end
watch:interval(1000)
watch:register()

local shutdown = GlobalEvent("ChaosSeasonModesShutdown")
function shutdown.onShutdown()
	S.shutdownGuard = true
	saveHardcore("shutdown")
	return true
end
shutdown:register()

-- ---------------------------------------------------------------- death: the fall
local function causeOf(killer)
	if not killer or type(killer) == "boolean" then
		return M.deathCause(nil)
	end
	local master = killer.getMaster and killer:getMaster()
	if master and master:isPlayer() then
		killer = master
	end
	return M.deathCause({name = killer:getName(), player = killer:isPlayer()})
end

function S.modesFall(player, killer, corpse)
	local season = S.current()
	local guid = player:getGuid()
	local level, cause = player:getLevel(), causeOf(killer)
	db.query(string.format("UPDATE `%s` SET `fallen_at` = %d, `fallen_level` = %d, `fallen_cause` = %s WHERE `player_id` = %d " ..
		"AND `fallen_at` = 0", T, now(), level, db.escapeString(cause:sub(1, 64)), guid))
	local row = S.modeMap[guid] or {}
	row.fallen, row.level, row.cause = now(), level, cause
	S.modeMap[guid] = row
	S.fallenByGuid[guid] = {season = season.id, level = level, cause = cause}
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `season`, `player_id`, `event`, `detail`) VALUES (%d, %d, %d, 'fallen', %s)",
		cfg.tables.log, now(), season.id, guid, db.escapeString(string.format("level %d, %s", level, cause))))
	S.migrateRow(guid, season.id, "fallen") -- a standard character from now on (season.lua)
	if corpse then
		corpse:setCustomAttribute(iso.tagKey, 0) -- its own items: the character can take them back as a standard one
	end
	S.ladderCache = {}
	log(string.format("%s fell at level %d (%s)", player:getName(), level, cause))
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You have fallen. %s is no longer a Hardcore character: it stays on the %s ladder as fallen and plays on as a standard character, with everything it has.", player:getName(),
		season.name))
	if hc.announce then
		Chaos.broadcast(MESSAGE_EVENT_ADVANCE, "%s has fallen in Hardcore at level %d (%s).", player:getName(), level, cause)
	end
end

local death = CreatureEvent("ChaosSeasonModesDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	if not creature:isPlayer() or not S.current() or staff(creature) then
		return true
	end
	if corpse and type(corpse) ~= "boolean" and corpse.isItem and corpse:isItem() then
		corpse:setCustomAttribute(OWNER, creature:getGuid()) -- Self-Found: nobody else's items, nobody takes theirs
	else
		corpse = nil
	end
	local f = S.modesOf(creature)
	if M.deathPlan(f) then
		local ok, err = pcall(S.modesFall, creature, killer or mostDamageKiller, corpse)
		if not ok then
			log("fall failed: " .. tostring(err))
		end
	end
	return true
end
death:register()

-- ---------------------------------------------------------------- end of season (season.lua migrateRow)
function S.modesMigrated(guid, seasonId, why)
	if why == "fallen" then
		return
	end
	local rows = Chaos.select(string.format("SELECT `ssf`, `hc`, `fallen_at` FROM `%s` WHERE `player_id` = %d AND `reset_at` = 0",
		T, guid), {{"ssf", "n"}, {"hc", "n"}, {"fallen_at", "n"}})
	local r = rows[1]
	if not r then
		return
	end
	local f = M.flags({ssf = r.ssf, hc = r.hc, fallen = r.fallen_at}, seasonId)
	local A = ChaosAchievements
	for key, value in pairs(M.survivedStats(f)) do
		if A and A.set then
			pcall(A.set, guid, key, value)
		end
	end
	db.query(string.format("UPDATE `%s` SET `reset_at` = %d WHERE `player_id` = %d AND `reset_at` = 0", T, now(), guid))
	S.modeMap[guid] = nil
end

-- ---------------------------------------------------------------- ladders
function S.modesLadderTabs()
	return M.ladderTabs(mc)
end

local function lbCfg()
	return Chaos.leaderboardConfig
end

local function ladderRows(g, season, mode)
	local key = string.format("%d:%s:%s", season.id, mode, tostring(g.key))
	local c = S.ladderCache[key]
	if c and now() - c.at < cfg.ladder.cacheSeconds then
		return c.rows, c.where
	end
	local where
	if mode == "fallen" then
		where = string.format("p.`vocation` IN (%s) AND p.`group_id` < %d AND p.`deletion` = 0 AND sp.`season` = %d",
			table.concat(g.ids, ","), cfg.ladder.staffGroup, season.id)
	else
		where = S.ladderHelpers.where(g, season.id)
	end
	where = where .. " AND " .. M.ladderClause(mode, "sm")
	local order = mode == "fallen" and "sm.`fallen_level` DESC, sm.`fallen_at` ASC" or "p.`experience` DESC, p.`id` ASC"
	local rows = Chaos.select(string.format("SELECT p.`id`, p.`name`, p.`level`, p.`vocation`, sm.`fallen_level`, sm.`fallen_cause` " ..
		"FROM `players` p JOIN `%s` sp ON sp.`player_id` = p.`id` LEFT JOIN `%s` sm ON sm.`player_id` = p.`id` WHERE %s " ..
		"ORDER BY %s LIMIT %d", cfg.tables.players, T, where, order, cfg.ladder.rows), {{"id", "n"}, {"name", "s"}, {"level", "n"},
		{"vocation", "n"}, {"fallen_level", "n"}, {"fallen_cause", "s"}})
	for i, r in ipairs(rows) do
		r.rank = i
	end
	S.ladderCache[key] = {at = now(), rows = rows, where = where}
	return rows, where
end

-- a mode tab of the season view (season.lua S.sendBoard): returns true when it answered
function S.modesSendBoard(player, key, groupKey, mode)
	local season, LB, lc = S.current(), ChaosLeaderboard, lbCfg()
	if not season or not LB or not lc or not M.ladderClause(mode) then
		return false
	end
	local H = S.ladderHelpers
	local data
	if key == lc.ladder.key then
		local g = H.groupOf(player, groupKey)
		if not g then
			return false
		end
		local _, mine = H.groupOf(player, nil) -- the player's own class line (nil when its class has none)
		local list, where = ladderRows(g, season, mode)
		local rows = {}
		for _, r in ipairs(list) do
			local fallen = mode == "fallen" and {level = r.fallen_level, cause = r.fallen_cause} or nil
			rows[#rows + 1] = {rank = r.rank, name = r.name, value = fallen and r.fallen_level or r.level,
				level = fallen and r.fallen_level or r.level, vocation = H.vocationName(r.vocation), title = H.boardTitle(r.id),
				fallen = fallen}
		end
		local own
		local f = S.modesOf(player)
		if mode ~= "fallen" and mine and mine.key == g.key and not f.exempt and M.memberMatches(mode, f) and
				S.realmOf(player) == season.id then
			local exp = player:getExperience()
			local id = db.storeQuery(string.format("SELECT COUNT(*) AS `n` FROM `players` p JOIN `%s` sp ON sp.`player_id` = p.`id` " ..
				"LEFT JOIN `%s` sm ON sm.`player_id` = p.`id` WHERE %s AND p.`id` <> %d AND (p.`experience` > %d OR " ..
				"(p.`experience` = %d AND p.`id` < %d))", cfg.tables.players, T, where, player:getGuid(), exp, exp, player:getGuid()))
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
			local fallen = S.fallenByGuid[e.guid]
			local f = S.modeFlagsOfGuid(e.guid)
			local member = S.members[e.guid] or (fallen and fallen.season == season.id)
			if member and M.memberMatches(mode, {key = f.key, fallen = fallen and fallen.season == season.id}) then
				ranked[#ranked + 1] = e
			end
		end
		local rows, own = {}, nil
		for i, e in ipairs(ranked) do
			if i <= lc.rows then
				rows[#rows + 1] = {rank = i, name = e.name, value = e.value, count = e.count, title = H.boardTitle(e.guid, b.key),
					fallen = S.fallenMark(e.guid)}
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
	local tab = M.byKey(mc, mode)
	data.season = {id = season.id, name = season.name, tag = season.tag, mode = mode,
		modeName = mode == "fallen" and "Fallen" or (tab and tab.name or mode)}
	if ChaosDisplayScale and ChaosDisplayScale.apply then -- the viewer's display scale: the damage / healing boards
		data = ChaosDisplayScale.apply("leaderboard", player, data)
	end
	Chaos.send(player, ChaosOpcodes.leaderboard or 229, "board", data)
	return true
end

-- ---------------------------------------------------------------- look text, achievements
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() and S.current() then
		local pronoun = thing:getId() == self:getId() and "You" or (thing:getSex() == PLAYERSEX_FEMALE and "She" or "He")
		local fallen = S.fallenMark(thing:getGuid())
		local line = M.lookLine(S.modeFlagsOfGuid(thing:getGuid()), pronoun, fallen)
		if line then
			description = (description or "") .. "\n" .. line
		end
	end
	return description
end
look:register(102)

local function feedAchievements(player)
	local A = ChaosAchievements
	if not (A and A.set) or not S.current() then
		return
	end
	for key, value in pairs(M.achievementStats(S.modesOf(player), player:getLevel())) do
		pcall(A.set, player, key, value)
	end
end

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosSeasonModesExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if msg and Chaos.limited and Chaos.limited(player, "seasonmodes." .. tostring(msg.action), 300) then
		return
	end
	if msg and msg.action == "beat" then
		local st = S.hcState[player:getId()]
		if st then
			st.lastBeat, st.beatSeen = now(), true
		end
	elseif msg and msg.action == "sync" and hardcoreNow(player) then
		S.sendState(player, false) -- a client that (re)connected asks for its state: the heartbeat interval
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosSeasonModesLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSeasonModesExtended")
	player:registerEvent("ChaosSeasonModesDeath")
	player:registerEvent("ChaosSeasonModesAdvance")
	S.hcState[player:getId()] = {loginAt = now(), lastBeat = now()}
	if hardcoreNow(player) then
		registerHardcore(player)
		player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Hardcore: you cannot be hurt for %d seconds after logging in.",
			hc.loginSeconds))
	end
	feedAchievements(player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSeasonModesLogout")
function logout.onLogout(player)
	S.hcState[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local advance = CreatureEvent("ChaosSeasonModesAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		feedAchievements(player)
	end
	return true
end
advance:type("advance")
advance:register()

local startup = GlobalEvent("ChaosSeasonModesStartup")
function startup.onStartup()
	db.query(CREATE)
	restart = readRestart()
	S.modesLoad()
	log(restart and string.format("restart guard: %02d:%02d + %d min, %d s before", restart.hour, restart.min,
		restart.notifyMinutes, restart.guardSeconds) or "no daily restart found: the restart guard only covers a shutdown")
	return true
end
startup:register()

local reload = GlobalEvent("ChaosSeasonModesCheck")
function reload.onThink(interval)
	S.modesLoad()
	return true
end
reload:interval(cfg.checkSeconds * 1000)
reload:register()
