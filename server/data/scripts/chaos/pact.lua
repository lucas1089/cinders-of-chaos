-- Chaos Pact (monthly subscription) and account storage extras (pact_config.lua, pact_core.lua; client game_pact).
--
-- Everything is per account: the Pact (chaos_pact), the one-time extras bought in the store (chaos_account_extras) and
-- the saved passive tree builds (chaos_build_slots). Other systems ask for their limit:
--     ChaosPact.limit(player, key)    key of pact_config.lua `limits` (stashTabs, stashRemote, depotTabs, marketListings,
--                                     marketAccount, buildSlots, lootRules, charSlots)
--     ChaosPact.limits(player)        every limit
--     ChaosPact.stashKind(itemId)     "orbs" | "gems" | "keys" | nil (stash.lua ChaosStash.kindOf)
--     ChaosPact.state(accountId)      the cached account state (pact_core.lua)
--
-- Store: offers of kind "service" with service "pact" and "pactExtra" (pact_config.lua `store`, inserted by
-- shop_config.lua); the handlers are put into ChaosShopServices.services at startup, at every login and after a reload.
--
-- Protocol (extended opcode ChaosOpcodes.pact = 222, JSON {action, data}):
--   client -> server  open | claim | buildSave {slot?, name} | buildRename {slot, name} | buildDelete {slot} |
--                     buildLoad {slot}
--   server -> client  status {...see sendStatus...} (open = true when the window should show) |
--                     buildCode {slot, code} (load: the client opens the passive tree and previews the code) |
--                     message {text, error}
--
-- Character slots: the website refuses to create more characters than ChaosPact.limit(charSlots) (lib.php reads the
-- same tables); at login a character past the account's slots (by creation order) is told so and logged out (staff
-- excepted). Accounts that already had more characters when this was installed get the difference once
-- (extra "charSlotsLegacy", server_config chaos_pact_legacy).
--
-- Store bundles: ChaosPact.grantDays(player, days, source) (shop_config.lua `pact`), premium days in proportion.
-- Staff: /pact <player>, info | days <n> | end | extra <key> <amount> | claimreset
-- See server/README.md "Chaos Pact and account storage". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/pact_core.lua")
Chaos.pactConfig = dofile("data/scripts/chaos/pact_config.lua")

ChaosPact = ChaosPact or {}
local Pact = ChaosPact
local Core = ChaosPactCore
local cfg = Chaos.pactConfig
local T = cfg.tables
local MSG = cfg.messages
local OPCODE = ChaosOpcodes.pact or 222

Pact.accounts = Pact.accounts or {} -- account id -> state (pact_core.lua), loaded at login

local function q(text)
	return db.escapeString(text)
end

-- ------------------------------------------------------------------ tables
local SCHEMA = {
	[[CREATE TABLE IF NOT EXISTS `chaos_pact` (`account_id` int(11) NOT NULL, `ends_at` bigint(20) NOT NULL DEFAULT 0,
	`started_at` bigint(20) NOT NULL DEFAULT 0, `total_days` int(11) NOT NULL DEFAULT 0, `last_claim` int(11) NOT NULL DEFAULT 0,
	`claimed_total` int(11) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_account_extras` (`account_id` int(11) NOT NULL, `extra_key` varchar(32) NOT NULL,
	`amount` int(11) NOT NULL DEFAULT 0, `updated` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `extra_key`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_build_slots` (`account_id` int(11) NOT NULL, `slot` tinyint(3) unsigned NOT NULL,
	`name` varchar(32) NOT NULL DEFAULT '', `code` varchar(600) NOT NULL DEFAULT '', `class_line` tinyint(3) unsigned NOT NULL DEFAULT 0,
	`nodes` smallint(5) unsigned NOT NULL DEFAULT 0, `saved_by` varchar(64) NOT NULL DEFAULT '', `updated` bigint(20) NOT NULL DEFAULT 0,
	PRIMARY KEY (`account_id`, `slot`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_pact_log` (`id` int(11) NOT NULL AUTO_INCREMENT, `account_id` int(11) NOT NULL,
	`player_id` int(11) NOT NULL DEFAULT 0, `action` varchar(16) NOT NULL, `detail` varchar(64) NOT NULL DEFAULT '',
	`amount` int(11) NOT NULL DEFAULT 0, `at` bigint(20) NOT NULL, PRIMARY KEY (`id`), KEY `account_id` (`account_id`))
	ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[ALTER TABLE `chaos_stash` ADD COLUMN IF NOT EXISTS `tab` smallint(5) unsigned NOT NULL DEFAULT 0]]
}

local function log(accountId, playerId, action, detail, amount)
	db.asyncQuery(string.format("INSERT INTO `%s` (`account_id`, `player_id`, `action`, `detail`, `amount`, `at`) VALUES (%d, %d, %s, %s, %d, %d)",
		T.log, accountId, playerId or 0, q(action), q(detail or ""), amount or 0, os.time()))
end

-- ------------------------------------------------------------------ account state
function Pact.load(accountId)
	local st = {pactEnds = 0, lastClaim = 0, startedAt = 0, totalDays = 0, claimedTotal = 0, extras = {}}
	local r = Chaos.select(string.format("SELECT `ends_at`, `last_claim`, `started_at`, `total_days`, `claimed_total` FROM `%s` WHERE `account_id` = %d",
		T.pact, accountId), {{"ends_at", "n"}, {"last_claim", "n"}, {"started_at", "n"}, {"total_days", "n"}, {"claimed_total", "n"}})[1]
	if r then
		st.pactEnds, st.lastClaim, st.startedAt, st.totalDays, st.claimedTotal = r.ends_at, r.last_claim, r.started_at, r.total_days, r.claimed_total
	end
	for _, e in ipairs(Chaos.select(string.format("SELECT `extra_key`, `amount` FROM `%s` WHERE `account_id` = %d", T.extras, accountId),
			{{"extra_key", "s"}, {"amount", "n"}})) do
		st.extras[e.extra_key] = e.amount
	end
	Pact.accounts[accountId] = st
	return st
end

function Pact.state(accountId)
	return Pact.accounts[accountId] or Pact.load(accountId)
end

local function stateOf(player)
	local st = Pact.state(player:getAccountId())
	st.premium = player:isPremium()
	return st
end

function Pact.limit(player, key)
	return Core.limit(cfg, stateOf(player), key, os.time())
end

function Pact.limits(player)
	return Core.limits(cfg, stateOf(player), os.time())
end

function Pact.active(player)
	return Core.active(Pact.state(player:getAccountId()), os.time())
end

-- ------------------------------------------------------------------ stash kinds
-- "orbs" | "gems" | "keys" | nil (stash.lua ChaosStash.kindOf; kept for scripts that asked here)
function Pact.stashKind(itemId)
	if ChaosStash and ChaosStash.kindOf then
		return ChaosStash.kindOf(itemId)
	end
	return nil
end

-- ------------------------------------------------------------------ client
local function send(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

-- text: a key (Chaos.t) or a deferred text (ChaosI18n.msg): in the player's language
local function message(player, text, isError)
	text = Chaos.t(player, text)
	send(player, "message", {text = text, error = isError == true})
	if isError then
		player:sendCancelMessage(text)
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
	end
end

local function buildRows(accountId)
	return Chaos.select(string.format("SELECT `slot`, `name`, `code`, `class_line`, `nodes`, `updated` FROM `%s` WHERE `account_id` = %d ORDER BY `slot`",
		T.builds, accountId), {{"slot", "n"}, {"name", "s"}, {"code", "s"}, {"class_line", "n"}, {"nodes", "n"}, {"updated", "n"}})
end

local function sendStatus(player, open)
	local now = os.time()
	local accountId = player:getAccountId()
	local st = Pact.load(accountId)
	st.premium = player:isPremium()
	local lim = Core.limits(cfg, st, now)
	local active = Core.active(st, now)
	local canClaim = Core.claim(cfg, st, now, Chaos.dayKey(now)) ~= nil
	local builds = {}
	local B = ChaosBuildShare
	for _, r in ipairs(buildRows(accountId)) do
		builds[#builds + 1] = {slot = r.slot, name = r.name, nodes = r.nodes, cls = B and B.lineName and B.lineName(r.class_line) or "",
			editable = Core.buildEditable(lim, r.slot), updated = r.updated}
	end
	-- the affinity stash tabs (stash_config.lua) and who owns them; the general tab size
	local special, tabSize = {}, nil
	local sc = Chaos.stashConfig
	if not sc then
		local okC, res = pcall(dofile, "data/scripts/chaos/stash_config.lua")
		sc = okC and type(res) == "table" and res or nil
	end
	if sc then
		tabSize = sc.tabSize
		local owned = {}
		if ChaosStash and ChaosStash.viewOf then
			local okV, view = pcall(ChaosStash.viewOf, player)
			owned = okV and view and view.owned or {}
		end
		for _, a in ipairs(sc.affinities or {}) do
			special[#special + 1] = {name = a.name, owned = owned[a.key] ~= nil, source = owned[a.key]}
		end
	end
	send(player, "status", {
		open = open == true,
		name = cfg.pact.name, active = active, endsAt = st.pactEnds,
		ends = st.pactEnds > 0 and os.date("%Y-%m-%d %H:%M", st.pactEnds) or "",
		daysLeft = Core.daysLeft(st.pactEnds, now), totalDays = st.totalDays,
		dailyCoins = cfg.pact.dailyCoins, canClaim = canClaim, claimedTotal = st.claimedTotal,
		premiumDays = player:getPremiumDays(), coins = ChaosShop and ChaosShop.getCoins and ChaosShop.getCoins(accountId) or 0,
		title = active and cfg.pact.title.text or "", titleText = cfg.pact.title.text,
		limits = Core.breakdown(cfg, st, now), tabSize = tabSize, special = special,
		buildLimit = lim.buildSlots, builds = builds
	})
end
Pact.sendStatus = sendStatus

-- ------------------------------------------------------------------ store services
local function refreshPlayer(player)
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
	if ChaosDepot and ChaosDepot.onLimitsChanged then
		pcall(ChaosDepot.onLimitsChanged, player) -- depot tabs (depot.lua): the client's lock marks
	end
	sendStatus(player, false)
end

-- adds `days` of the Pact (stacked on the time left) and premium days in proportion; returns the new end time
local function addDays(player, days, source)
	local now = os.time()
	local accountId = player:getAccountId()
	local st = Pact.load(accountId)
	local ends = math.max(st.pactEnds, now) + days * 86400
	local started = Core.active(st, now) and st.startedAt or now
	if not db.query(string.format("INSERT INTO `%s` (`account_id`, `ends_at`, `started_at`, `total_days`) VALUES (%d, %d, %d, %d) " ..
			"ON DUPLICATE KEY UPDATE `ends_at` = %d, `started_at` = %d, `total_days` = `total_days` + %d",
			T.pact, accountId, ends, started, days, ends, started, days)) then
		return nil
	end
	local premium = math.floor((cfg.pact.premiumDays or 0) * days / cfg.pact.days)
	if premium > 0 then
		player:addPremiumDays(premium)
	end
	Pact.load(accountId)
	log(accountId, player:getGuid(), "pact", source or "", days)
	return ends
end

-- shop_config.lua `pact` = {api = "ChaosPact", fn = "grantDays"}: the Pact days of a store bundle (no stacking cap)
function Pact.grantDays(player, days, source)
	days = math.floor(tonumber(days) or 0)
	if days <= 0 then
		return false
	end
	local ends = addDays(player, days, source or "grant")
	if not ends then
		return false
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%d days of the Chaos Pact added: it runs until %s.", days,
		os.date("%Y-%m-%d %H:%M", ends)))
	pcall(function()
		if ChaosNameplate and ChaosNameplate.refresh then
			ChaosNameplate.refresh(player)
		end
		Pact.sendStatus(player, false)
	end)
	return true
end

local pactService = {
	check = function(player)
		local st = Pact.load(player:getAccountId())
		local _, err = Core.extendPact(cfg, st.pactEnds, os.time())
		return err
	end,
	apply = function(player)
		local st = Pact.load(player:getAccountId())
		local _, err = Core.extendPact(cfg, st.pactEnds, os.time())
		if err then
			return err
		end
		local ends = addDays(player, cfg.pact.days, "store")
		if not ends then
			return "Something went wrong. Your coins were refunded."
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your Chaos Pact runs until %s. Claim your %d Chaos Coins every day in Character > Chaos Pact.",
			os.date("%Y-%m-%d %H:%M", ends), cfg.pact.dailyCoins))
		refreshPlayer(player)
		return true
	end
}

-- offer.amount: how many of the extra one purchase adds (default 1; depot_config.lua sells a pack of 4 depot tabs)
local function offerAmount(offer)
	return math.max(1, math.floor(tonumber(offer.amount) or 1))
end

local extraService = {
	check = function(player, offer)
		return Core.extraCheck(cfg, Pact.load(player:getAccountId()), offer.extra, offerAmount(offer))
	end,
	apply = function(player, offer)
		local accountId = player:getAccountId()
		local amount = offerAmount(offer)
		local problem = Core.extraCheck(cfg, Pact.load(accountId), offer.extra, amount)
		if problem then
			return problem
		end
		if not db.query(string.format("INSERT INTO `%s` (`account_id`, `extra_key`, `amount`, `updated`) VALUES (%d, %s, %d, %d) " ..
				"ON DUPLICATE KEY UPDATE `amount` = `amount` + %d, `updated` = %d", T.extras, accountId, q(offer.extra), amount, os.time(),
				amount, os.time())) then
			return "Something went wrong. Your coins were refunded."
		end
		Pact.load(accountId)
		log(accountId, player:getGuid(), "extra", offer.extra, amount)
		local x = cfg.extras[offer.extra]
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "%s added to your account (%d of %d).",
			amount > 1 and (amount .. " x " .. x.name) or x.name, Pact.state(accountId).extras[offer.extra] or amount,
			Core.extraMax(cfg, offer.extra)))
		refreshPlayer(player)
		return true
	end
}

local function titleSource(player)
	local st = Pact.accounts[player:getAccountId()]
	if st and Core.active(st, os.time()) then
		local t = cfg.pact.title
		return {key = t.key, text = t.text, color = t.color, at = st.startedAt}
	end
	return nil
end

-- shop_services.lua and titles.lua build their tables when they load (possibly after this file): put our entries in
-- at startup, at every login and after a /reload
function Pact.ensureHooks()
	local S = ChaosShopServices
	if S and type(S.services) == "table" then
		S.services.pact = pactService
		S.services.pactExtra = extraService
	end
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("pact", titleSource)
	end
end

-- ------------------------------------------------------------------ daily coins
local function claim(player)
	local now = os.time()
	local accountId = player:getAccountId()
	local st = Pact.load(accountId)
	local day = Chaos.dayKey(now)
	local amount, err = Core.claim(cfg, st, now, day)
	if not amount then
		message(player, err, true)
		return
	end
	-- the WHERE makes a second claim of the day a no-op even if the cache were stale
	db.query(string.format("UPDATE `%s` SET `last_claim` = %d, `claimed_total` = `claimed_total` + %d WHERE `account_id` = %d AND `last_claim` < %d",
		T.pact, day, amount, accountId, day))
	local after = Pact.load(accountId)
	if after.lastClaim ~= day or after.claimedTotal ~= st.claimedTotal + amount then
		message(player, MSG.alreadyClaimed, true)
		return
	end
	if ChaosShop and ChaosShop.addCoins then
		ChaosShop.addCoins(accountId, amount)
	end
	log(accountId, player:getGuid(), "claim", tostring(day), amount)
	message(player, ChaosI18n.msg(MSG.claimed, amount))
	sendStatus(player, false)
end

-- ------------------------------------------------------------------ saved builds
local function cleanName(text, slot)
	local name = tostring(text or ""):gsub("[^%w %-%'_%.]", ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
	name = name:sub(1, cfg.buildNameMax)
	if name == "" then
		name = "Build " .. slot
	end
	return name
end

local function buildSave(player, data)
	local B = ChaosBuildShare
	if not (B and B.exportCode) then
		return message(player, "Build sharing is not available.", true)
	end
	local accountId = player:getAccountId()
	local lim = Pact.limits(player)
	local rows = buildRows(accountId)
	local slot = Chaos.toInt(data.slot, 1, 250)
	if slot then
		if not Core.buildEditable(lim, slot) then
			return message(player, ChaosI18n.msg(MSG.buildLocked, lim.buildSlots), true)
		end
	else
		slot = Core.freeBuildSlot(lim, rows)
		if not slot then
			return message(player, ChaosI18n.msg(MSG.buildFull, lim.buildSlots), true)
		end
	end
	local code, build = B.exportCode(player)
	if #(build.nodes or {}) == 0 and not build.paragon then
		return message(player, "Your passive tree has no allocated nodes to save.", true)
	end
	local name = cleanName(data.name, slot)
	db.query(string.format("REPLACE INTO `%s` (`account_id`, `slot`, `name`, `code`, `class_line`, `nodes`, `saved_by`, `updated`) " ..
		"VALUES (%d, %d, %s, %s, %d, %d, %s, %d)", T.builds, accountId, slot, q(name), q(code), build.classId or 0, #(build.nodes or {}),
		q(player:getName()), os.time()))
	message(player, ChaosI18n.msg("Build saved in slot %d: %s (%d nodes).", slot, name, #(build.nodes or {})))
	sendStatus(player, false)
end

local function buildRename(player, data)
	local slot = Chaos.toInt(data.slot, 1, 250)
	local lim = Pact.limits(player)
	if not slot or not Core.buildEditable(lim, slot) then
		return message(player, ChaosI18n.msg(MSG.buildLocked, lim.buildSlots), true)
	end
	db.query(string.format("UPDATE `%s` SET `name` = %s WHERE `account_id` = %d AND `slot` = %d", T.builds, q(cleanName(data.name, slot)),
		player:getAccountId(), slot))
	sendStatus(player, false)
end

local function buildDelete(player, data)
	local slot = Chaos.toInt(data.slot, 1, 250)
	if not slot then
		return
	end
	db.query(string.format("DELETE FROM `%s` WHERE `account_id` = %d AND `slot` = %d", T.builds, player:getAccountId(), slot))
	message(player, ChaosI18n.msg("Build slot %d is empty now.", slot))
	sendStatus(player, false)
end

-- any saved build can be loaded, also a read-only one: the client opens the passive tree and asks for its preview
-- (buildshare.lua checks the class line and prices the change as for any code)
local function buildLoad(player, data)
	local slot = Chaos.toInt(data.slot, 1, 250)
	local row = slot and Chaos.select(string.format("SELECT `code` FROM `%s` WHERE `account_id` = %d AND `slot` = %d", T.builds,
		player:getAccountId(), slot), {{"code", "s"}})[1]
	if not row then
		return message(player, "That build slot is empty.", true)
	end
	send(player, "buildCode", {slot = slot, code = row.code})
end

-- ------------------------------------------------------------------ opcode
local RATE = cfg.rate
local ACTIONS = {
	open = {RATE.open, function(player) sendStatus(player, true) end},
	sync = {RATE.open, function(player) sendStatus(player, false) end},
	claim = {RATE.claim, claim},
	buildSave = {RATE.build, buildSave},
	buildRename = {RATE.build, buildRename},
	buildDelete = {RATE.build, buildDelete},
	buildLoad = {RATE.build, buildLoad}
}

local ext = CreatureEvent("ChaosPactExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	local a = msg and ACTIONS[msg.action]
	if not a then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "pact." .. msg.action, a[1]) then
		return
	end
	local ok, err = pcall(a[2], player, type(msg.data) == "table" and msg.data or {})
	if not ok then
		print("[Chaos pact] " .. tostring(msg.action) .. " failed: " .. tostring(err))
	end
end
ext:type("extendedopcode")
ext:register()

-- ------------------------------------------------------------------ login: hooks, character slots, notices
local function isStaff(player)
	return player:getGroup():getAccess() or player:getAccountType() >= (cfg.staffAccountType or 5)
end

local function characterAllowed(player)
	if isStaff(player) then
		return true
	end
	local ids = {}
	for _, r in ipairs(Chaos.select("SELECT `id` FROM `players` WHERE `account_id` = " .. player:getAccountId(), {{"id", "n"}})) do
		ids[#ids + 1] = r.id
	end
	local index = Core.characterIndex(ids, player:getGuid())
	local slots = Pact.limit(player, "charSlots")
	return index <= slots, index, slots
end

local login = CreatureEvent("ChaosPactLogin")
function login.onLogin(player)
	Pact.ensureHooks()
	player:registerEvent("ChaosPactExtended")
	local st = Pact.load(player:getAccountId())
	local ok, index, slots = characterAllowed(player)
	if not ok then
		local text = string.format(MSG.charBlocked, slots, index)
		print(string.format("[Chaos pact] %s refused: character %d of account %d, %d slots", player:getName(), index, player:getAccountId(), slots))
		player:popupFYI(text)
		local cid = player:getId()
		addEvent(function()
			local p = Player(cid)
			if p then
				p:remove()
			end
		end, 1500)
		return true
	end
	local now = os.time()
	if Core.active(st, now) then
		local left = Core.daysLeft(st.pactEnds, now)
		local text = string.format("Your Chaos Pact runs for %d more day%s.", left, left == 1 and "" or "s")
		if Core.claim(cfg, st, now, Chaos.dayKey(now)) then
			text = text .. string.format(" Today's %d Chaos Coins wait in Character > Chaos Pact.", cfg.pact.dailyCoins)
		end
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, text)
	elseif st.pactEnds > 0 and now - st.pactEnds < 14 * 86400 then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, "Your Chaos Pact has ended. Nothing is lost: extra stash and depot tabs are " ..
			"withdraw-only, extra market offers run until they end, extra saved builds can be loaded or deleted.")
	end
	return true
end
login:register()

-- ------------------------------------------------------------------ startup: tables, legacy character slots
local function legacyGrant()
	local key = "chaos_pact_legacy"
	local done = Chaos.select(string.format("SELECT `value` FROM `server_config` WHERE `config` = %s", q(key)), {{"value", "s"}})[1]
	if done and tonumber(done.value) and tonumber(done.value) >= cfg.legacyVersion then
		return
	end
	local granted = 0
	for _, r in ipairs(Chaos.select(string.format("SELECT `account_id`, COUNT(*) AS `n` FROM `players` GROUP BY `account_id` HAVING `n` > %d",
			cfg.limits.charSlots.free), {{"account_id", "n"}, {"n", "n"}})) do
		local st = Pact.load(r.account_id)
		local owned = math.min(st.extras.charSlots or 0, cfg.limits.charSlots.maxExtra) + (st.extras[cfg.legacyCharSlots] or 0)
		local n = Core.legacySlots(cfg, r.n, owned)
		if n > 0 then
			db.query(string.format("INSERT INTO `%s` (`account_id`, `extra_key`, `amount`, `updated`) VALUES (%d, %s, %d, %d) " ..
				"ON DUPLICATE KEY UPDATE `amount` = `amount` + %d", T.extras, r.account_id, q(cfg.legacyCharSlots), n, os.time(), n))
			log(r.account_id, 0, "legacy", cfg.legacyCharSlots, n)
			granted = granted + 1
		end
	end
	db.query(string.format("INSERT INTO `server_config` (`config`, `value`) VALUES (%s, %s) ON DUPLICATE KEY UPDATE `value` = %s",
		q(key), q(tostring(cfg.legacyVersion)), q(tostring(cfg.legacyVersion))))
	Pact.accounts = {}
	print(string.format("[Chaos pact] legacy character slots given to %d account(s)", granted))
end

local startup = GlobalEvent("ChaosPactStartup")
function startup.onStartup()
	for _, sql in ipairs(SCHEMA) do
		db.query(sql)
	end
	legacyGrant()
	Pact.ensureHooks()
	return true
end
startup:register()

-- a /reload rebuilds shop_services.lua and titles.lua tables after this file: put the hooks back once all are loaded
addEvent(function()
	Pact.ensureHooks()
end, 0)

-- ------------------------------------------------------------------ staff
local talk = TalkAction("/pact")
function talk.onSay(player, words, param)
	-- days / extra / claimreset create value: administrators only; info: staff. Every use in the audit log.
	local sub = tostring(param or ""):match(",%s*(%S+)")
	local allowed, staff = Chaos.staffCommand(player, words, param, sub ~= nil and sub ~= "info")
	if not allowed then
		return not staff
	end
	local name, rest = param:match("^%s*(.-)%s*,%s*(.-)%s*$")
	local guid, realName = Chaos.findPlayer(name or "")
	if not guid then
		player:sendCancelMessage("Usage: /pact <player>, info | days <n> | end | extra <key> <amount> | claimreset")
		return false
	end
	local accountId = Chaos.select("SELECT `account_id` FROM `players` WHERE `id` = " .. guid, {{"account_id", "n"}})[1].account_id
	local now = os.time()
	local st = Pact.load(accountId)
	local cmd, a, b = rest:match("^(%S+)%s*(%S*)%s*(%S*)")
	if cmd == "days" and tonumber(a) then
		local ends = math.max(st.pactEnds, now) + math.floor(tonumber(a)) * 86400
		db.query(string.format("INSERT INTO `%s` (`account_id`, `ends_at`, `started_at`) VALUES (%d, %d, %d) ON DUPLICATE KEY UPDATE `ends_at` = %d, " ..
			"`started_at` = IF(`ends_at` < %d, %d, `started_at`)", T.pact, accountId, ends, now, ends, now, now))
		log(accountId, 0, "staff", "days " .. a, 0)
	elseif cmd == "end" then
		db.query(string.format("UPDATE `%s` SET `ends_at` = %d WHERE `account_id` = %d", T.pact, now - 1, accountId))
		log(accountId, 0, "staff", "end", 0)
	elseif cmd == "extra" and cfg.extras[a] or (cmd == "extra" and a == cfg.legacyCharSlots) then
		local n = math.max(0, math.floor(tonumber(b) or 0))
		db.query(string.format("INSERT INTO `%s` (`account_id`, `extra_key`, `amount`, `updated`) VALUES (%d, %s, %d, %d) " ..
			"ON DUPLICATE KEY UPDATE `amount` = %d, `updated` = %d", T.extras, accountId, q(a), n, now, n, now))
		log(accountId, 0, "staff", "extra " .. a, n)
	elseif cmd == "claimreset" then
		db.query(string.format("UPDATE `%s` SET `last_claim` = 0 WHERE `account_id` = %d", T.pact, accountId))
	elseif cmd ~= "info" then
		player:sendCancelMessage("Usage: /pact <player>, info | days <n> | end | extra <key> <amount> | claimreset")
		return false
	end
	st = Pact.load(accountId)
	local parts = {}
	for k, v in pairs(st.extras) do
		parts[#parts + 1] = k .. "=" .. v
	end
	table.sort(parts)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s (account %d): Pact %s, %d days bought, last claim %d; extras: %s", realName,
		accountId, Core.active(st, now) and ("until " .. os.date("%Y-%m-%d %H:%M", st.pactEnds)) or "inactive", st.totalDays, st.lastClaim,
		#parts > 0 and table.concat(parts, ", ") or "none"))
	local online = Player(guid)
	if online then
		refreshPlayer(online)
	end
	return false
end
talk:separator(" ")
talk:register()
