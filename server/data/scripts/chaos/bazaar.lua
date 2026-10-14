-- Character Bazaar, the game server's part: a character listed on the website's Character Bazaar cannot log in while
-- its auction runs or is being settled (bazaar_config.lua lockStatuses), so nothing of it can move during the sale
-- (items, gold, the character itself). The auction (bids, escrow, fee, transfer) is the website's: website/overlay/
-- plugins/chaos/bazaar_lib.php, pages/bazaar.php; the transfer changes players.account_id while the character is
-- offline and locked.
--   onLogin      a locked character is refused (onLogin returns false: the engine kicks it before it can act) and
--                the refusal is logged in chaos_bazaar_log; the player reads why in the client's login error box
--                (engine patch 0039 player:refuseLogin, in the character's language); staff characters (group >=
--                adminGroup) are never locked
--   sweep        every cfg.sweepSeconds, a listed character that is online (it logged in during the listing call) is
--                saved and removed
-- Tables: server/sql/chaos_bazaar.sql (the website's install.sql creates them too; this file creates them at startup
-- for a server started before the site). See server/README.md "Character Bazaar". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/bazaar_core.lua")
Chaos.bazaarConfig = dofile("data/scripts/chaos/bazaar_config.lua")

ChaosBazaar = ChaosBazaar or {}
local BZ = ChaosBazaar
local Core = ChaosBazaarCore
local cfg = Chaos.bazaarConfig
local T = cfg.tables

local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_bazaar_listings` (`id` int(11) NOT NULL AUTO_INCREMENT, `player_id` int(11) NOT NULL,
	`seller_account_id` int(11) NOT NULL, `min_price` int(11) NOT NULL, `buyout` int(11) NOT NULL DEFAULT 0,
	`current_bid` int(11) NOT NULL DEFAULT 0, `current_bid_id` int(11) NOT NULL DEFAULT 0, `bidder_account_id` int(11) NOT NULL DEFAULT 0,
	`bids` int(11) NOT NULL DEFAULT 0, `fee_pct` tinyint(3) unsigned NOT NULL DEFAULT 0, `fee` int(11) NOT NULL DEFAULT 0,
	`status` varchar(10) NOT NULL DEFAULT 'active', `reason` varchar(64) NOT NULL DEFAULT '', `created_at` int(10) unsigned NOT NULL,
	`ends_at` int(10) unsigned NOT NULL, `settled_at` int(10) unsigned NOT NULL DEFAULT 0, `player_name` varchar(255) NOT NULL DEFAULT '',
	`level` int(11) NOT NULL DEFAULT 0, `vocation` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`id`),
	KEY `chaos_bazaar_listings_player` (`player_id`, `status`), KEY `chaos_bazaar_listings_status` (`status`, `ends_at`),
	KEY `chaos_bazaar_listings_seller` (`seller_account_id`, `status`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_bazaar_bids` (`id` int(11) NOT NULL AUTO_INCREMENT, `listing_id` int(11) NOT NULL,
	`account_id` int(11) NOT NULL, `amount` int(11) NOT NULL, `escrow` int(11) NOT NULL DEFAULT 0, `buyout` tinyint(1) NOT NULL DEFAULT 0,
	`state` varchar(10) NOT NULL DEFAULT 'leading', `created_at` int(10) unsigned NOT NULL, `ip` varchar(64) NOT NULL DEFAULT '',
	PRIMARY KEY (`id`), KEY `chaos_bazaar_bids_listing` (`listing_id`, `state`), KEY `chaos_bazaar_bids_account` (`account_id`, `created_at`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_bazaar_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `at` int(10) unsigned NOT NULL,
	`listing_id` int(11) NOT NULL DEFAULT 0, `account_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0,
	`action` varchar(16) NOT NULL, `detail` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY `chaos_bazaar_log_listing` (`listing_id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]]
}

local function log(listingId, accountId, playerId, action, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `listing_id`, `account_id`, `player_id`, `action`, `detail`) VALUES (%d, %d, %d, %d, %s, %s)",
		T.log, os.time(), listingId or 0, accountId or 0, playerId or 0, db.escapeString(action), db.escapeString(tostring(detail or ""):sub(1, 255))))
end

-- the listing that locks character `guid`, or nil
function BZ.lockOf(guid)
	local rows = Chaos.select(string.format("SELECT `id`, `status`, `ends_at` FROM `%s` WHERE `player_id` = %d AND `status` IN ('active', 'settling')",
		T.listings, guid), {{"id", "n"}, {"status", "s"}, {"ends_at", "n"}})
	return Core.locks(rows, cfg)
end

local function exempt(player)
	return player:getGroup():getId() >= (cfg.adminGroup or 5)
end

-- the player reads why (live test 2026-10-14: only "connection lost"): the client's login error box, sent at once by
-- engine patch 0039 (player:refuseLogin; anything sent the normal way is dropped with the kick). The character's
-- language (Chaos.lang: the stored one, the client tells it every session); never told (a first login): English and
-- pt-BR together. Without the patch the text goes the normal way (the client still says "connection lost").
function BZ.refusalText(player, row)
	local I = ChaosI18n
	local text = I and I.text or function(_, p, ...) return string.format(p, ...) end
	local lang
	if I and I.STORAGE and Chaos.lang then
		local okS, stored = pcall(function() return player:getStorageValue(I.STORAGE) end)
		if okS and tonumber(stored) and tonumber(stored) >= 0 then
			lang = Chaos.lang(player)
		end
	end
	return Core.refusalText(row, cfg, lang, text)
end

function BZ.tellRefusal(player, row)
	local ok, text = pcall(BZ.refusalText, player, row)
	if not ok then
		text = Core.lockMessage(row, cfg)
	end
	if player.refuseLogin then
		local sent = pcall(function() return player:refuseLogin(text) end)
		if sent then
			return true
		end
	end
	pcall(function() player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text) end)
	return false
end

local login = CreatureEvent("ChaosBazaarLogin")
function login.onLogin(player)
	if not cfg.enabled or exempt(player) then
		return true
	end
	local ok, row = pcall(BZ.lockOf, player:getGuid())
	if not ok then
		print("[Chaos bazaar] login check failed: " .. tostring(row))
		return true -- the tables are missing (a server without the site): nothing can be listed
	end
	if row then
		print(string.format("[Chaos bazaar] %s refused: listed (listing %d, %s)", player:getName(), row.id, row.status))
		log(row.id, player:getAccountId(), player:getGuid(), "login_refused", Core.lockMessage(row, cfg))
		BZ.tellRefusal(player, row)
		return false -- the engine kicks the character before its first action (Player::onPlacedCreature)
	end
	return true
end
login:type("login")
login:register()

-- a character listed while it was online (the website checks players_online, a login can still race it)
function BZ.sweep()
	local n = 0
	for _, p in ipairs(Game.getPlayers()) do
		if not exempt(p) then
			local row = BZ.lockOf(p:getGuid())
			if row then
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, cfg.messages.kicked)
				log(row.id, p:getAccountId(), p:getGuid(), "kicked", "online while listed")
				if p.save then
					p:save()
				end
				p:remove()
				n = n + 1
			end
		end
	end
	return n
end

local startup = GlobalEvent("ChaosBazaarStartup")
function startup.onStartup()
	for _, sql in ipairs(SCHEMA) do
		db.query(sql)
	end
	local problems = Core.validate(cfg)
	for _, p in ipairs(problems) do
		print("[Chaos bazaar] config: " .. p)
	end
	return true
end
startup:register()

local sweep = GlobalEvent("ChaosBazaarSweep")
function sweep.onThink(interval)
	if cfg.enabled then
		local ok, err = pcall(BZ.sweep)
		if not ok then
			print("[Chaos bazaar] sweep: " .. tostring(err))
		end
	end
	return true
end
sweep:interval(math.max(10, cfg.sweepSeconds or 60) * 1000)
sweep:register()
