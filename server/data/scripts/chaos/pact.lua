-- Chaos Pact (monthly subscription) and account storage extras (pact_config.lua, pact_core.lua; client game_pact).
--
-- Everything is per account: the Pact (chaos_pact), the one-time extras bought in the store (chaos_account_extras) and
-- the saved passive tree builds (chaos_build_slots). Other systems ask for their limit:
--     ChaosPact.limit(player, key)    key of pact_config.lua `limits` (stashSlots, stashRemote, marketListings,
--                                     marketAccount, buildSlots, lootRules, charSlots)
--     ChaosPact.limits(player)        every limit
--     ChaosPact.stashKind(itemId)     "orbs" | "gems" | "keys" | nil (stash.lua ChaosStash.kindOf)
--     ChaosPact.state(accountId)      the cached account state (pact_core.lua)
--     ChaosPact.frameOf(player)       the name plate frame while the Pact is active (nameplate.lua), else nil
--     ChaosPact.checkDays(player, days)  why `days` more Pact days cannot be added now (the cap), or nil (store bundles)
--     ChaosPact.addMonthExp(player, n)   count n experience the +10% added (pact_perks.lua), flushed once a minute
--
-- Store: offers of kind "service" with service "pact" and "pactExtra" (pact_config.lua `store`, inserted by
-- shop_config.lua); the handlers are put into ChaosShopServices.services at startup, at every login and after a reload.
--
-- Protocol (extended opcode ChaosOpcodes.pact = 222, JSON {action, data}):
--   client -> server  open | claim | marksBuy {key} | buildSave {slot?, name} | buildRename {slot, name} |
--                     buildDelete {slot} | buildLoad {slot}
--   server -> client  status {...see sendStatus...} (open = true when the window should show) |
--                     buildCode {slot, code} (load: the client opens the passive tree and previews the code) |
--                     message {text, error}
--
-- Character slots: the website refuses to create more characters than ChaosPact.limit(charSlots) (lib.php reads the
-- same tables); at login a character past the account's slots (by creation order) is told so and logged out (staff
-- excepted). Accounts that already had more characters when this was installed get the difference once
-- (extra "charSlotsLegacy", server_config chaos_pact_legacy).
--
-- Store bundles: ChaosPact.grantDays(player, days, source) (shop_config.lua `pact`), premium days in proportion. The
-- Pacto Completo (pact_config.lua store.complete) is such a bundle: Pact days here, premium days through the store.
-- Pact Marks (O317): 5 a day while the Pact runs, claimed in the window like the coins were; they buy only the cosmetics
-- of pact_config.lua marks.shelf (table chaos_pact_marks). Expiry warnings (3 days, 1 day) at login and online; the
-- window also shows the experience the +10% gave this month (table chaos_pact_xp).
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
	[[CREATE TABLE IF NOT EXISTS `chaos_pact_marks` (`account_id` int(11) NOT NULL, `balance` int(11) NOT NULL DEFAULT 0,
	`earned` int(11) NOT NULL DEFAULT 0, `spent` int(11) NOT NULL DEFAULT 0, `updated` bigint(20) NOT NULL DEFAULT 0,
	PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
	[[CREATE TABLE IF NOT EXISTS `chaos_pact_xp` (`player_id` int(11) NOT NULL, `month` int(11) NOT NULL,
	`exp` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY (`player_id`, `month`)) ENGINE=InnoDB DEFAULT CHARSET=utf8]],
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

-- why `days` more Pact days cannot be added (the stacking cap), or nil: the store asks before it takes the coins of a bundle
function Pact.checkDays(player, days)
	local _, err = Core.extendPact(cfg, Pact.load(player:getAccountId()).pactEnds, os.time(), days)
	return err
end

-- the name plate frame of an active Pact (nameplate.lua): below a frame the player wears, above the default one
function Pact.frameOf(player)
	if Pact.active(player) then
		return cfg.pact.frame
	end
	return nil
end

-- ------------------------------------------------------------------ Pact Marks
function Pact.loadMarks(accountId)
	local r = Chaos.select(string.format("SELECT `balance`, `earned`, `spent` FROM `%s` WHERE `account_id` = %d", T.marks, accountId),
		{{"balance", "n"}, {"earned", "n"}, {"spent", "n"}})[1]
	return r or {balance = 0, earned = 0, spent = 0}
end

function Pact.marksOf(accountId)
	return Pact.loadMarks(accountId).balance
end

local function addMarks(accountId, n)
	return db.query(string.format("INSERT INTO `%s` (`account_id`, `balance`, `earned`, `updated`) VALUES (%d, %d, %d, %d) " ..
		"ON DUPLICATE KEY UPDATE `balance` = LEAST(`balance` + %d, %d), `earned` = `earned` + %d, `updated` = %d",
		T.marks, accountId, n, n, os.time(), n, cfg.marks.maxBalance, n, os.time()))
end

-- takes n Marks when the account has them (one guarded UPDATE); true when taken
local function takeMarks(accountId, n)
	if not db.query(string.format("UPDATE `%s` SET `balance` = `balance` - %d, `spent` = `spent` + %d, `updated` = %d " ..
			"WHERE `account_id` = %d AND `balance` >= %d", T.marks, n, n, os.time(), accountId, n)) then
		return false
	end
	local r = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	return r ~= nil and r.n == 1
end

-- ------------------------------------------------------------------ experience the +10% added (per character, per server month)
local function monthKey(t)
	local d = os.date("*t", t or os.time())
	return d.year * 100 + d.month
end

Pact.xpPending = Pact.xpPending or {} -- guid -> {month, exp}: not written yet

function Pact.addMonthExp(player, n)
	n = math.floor(tonumber(n) or 0)
	if n <= 0 then
		return
	end
	local guid, month = player:getGuid(), monthKey()
	local p = Pact.xpPending[guid]
	if p and p.month ~= month then
		Pact.flushXp(guid)
		p = nil
	end
	if not p then
		p = {month = month, exp = 0}
		Pact.xpPending[guid] = p
	end
	p.exp = p.exp + n
end

-- writes the pending experience of one character (guid) or of everybody
function Pact.flushXp(only)
	for guid, p in pairs(Pact.xpPending) do
		if (only == nil or only == guid) and p.exp > 0 then
			if db.query(string.format("INSERT INTO `%s` (`player_id`, `month`, `exp`) VALUES (%d, %d, %d) ON DUPLICATE KEY UPDATE `exp` = `exp` + %d",
					T.xp, guid, p.month, p.exp, p.exp)) then
				Pact.xpPending[guid] = nil
			end
		elseif only == nil or only == guid then
			Pact.xpPending[guid] = nil
		end
	end
end

-- {character, account} experience the +10% added this month (written rows plus what is pending)
function Pact.monthExp(player)
	local month = monthKey()
	local guid, accountId = player:getGuid(), player:getAccountId()
	local mine = Core.monthExp(Chaos.select(string.format("SELECT `month`, `exp` FROM `%s` WHERE `player_id` = %d AND `month` = %d",
		T.xp, guid, month), {{"month", "n"}, {"exp", "n"}}), month)
	local all = Core.monthExp(Chaos.select(string.format("SELECT x.`month` AS `month`, x.`exp` AS `exp` FROM `%s` x JOIN `players` p ON p.`id` = x.`player_id` " ..
		"WHERE p.`account_id` = %d AND x.`month` = %d", T.xp, accountId, month), {{"month", "n"}, {"exp", "n"}}), month)
	local p = Pact.xpPending[guid]
	if p and p.month == month then
		mine, all = mine + p.exp, all + p.exp
	end
	-- what the account's other characters online have not written yet (at most a minute of it)
	for _, other in ipairs(Game and Game.getPlayers and Game.getPlayers() or {}) do
		local q = other:getAccountId() == accountId and other:getGuid() ~= guid and Pact.xpPending[other:getGuid()]
		if q and q.month == month then
			all = all + q.exp
		end
	end
	return mine, all, month
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
		tabSize = sc.slots and sc.slots.free or sc.tabSize
		local owned = {}
		if ChaosStash and ChaosStash.viewOf then
			local okV, view = pcall(ChaosStash.viewOf, player)
			owned = okV and view and view.owned or {}
		end
		for _, a in ipairs(sc.affinities or {}) do
			special[#special + 1] = {name = a.name, owned = owned[a.key] ~= nil, source = owned[a.key]}
		end
	end
	local marks = Pact.loadMarks(accountId)
	local owned = ChaosCosmetics and ChaosCosmetics.owns
	local shelf = {}
	for _, it in ipairs(cfg.marks.shelf) do
		shelf[#shelf + 1] = {key = it.key, marks = it.marks, name = Pact.cosmeticName(it.key), owned = owned and owned(accountId, it.key) == true or false}
	end
	local monthMine, monthAll, monthNo = Pact.monthExp(player)
	send(player, "status", {
		open = open == true,
		name = cfg.pact.name, active = active, endsAt = st.pactEnds,
		ends = st.pactEnds > 0 and os.date("%Y-%m-%d %H:%M", st.pactEnds) or "",
		daysLeft = Core.daysLeft(st.pactEnds, now), totalDays = st.totalDays,
		dailyMarks = cfg.pact.dailyMarks, canClaim = canClaim, claimedTotal = st.claimedTotal,
		marks = marks.balance, marksEarned = marks.earned, shelf = shelf,
		monthExp = monthMine, monthExpAccount = monthAll, month = monthNo,
		premiumDays = player:getPremiumDays(), coins = ChaosShop and ChaosShop.getCoins and ChaosShop.getCoins(accountId) or 0,
		title = active and cfg.pact.title.text or "", titleText = cfg.pact.title.text,
		limits = Core.breakdown(cfg, st, now), tabSize = tabSize, special = special,
		buildLimit = lim.buildSlots, builds = builds
	})
end
Pact.sendStatus = sendStatus

-- the name of a shelf cosmetic for the window (cosmetics_config.lua); the key when the config is not loaded
function Pact.cosmeticName(key)
	if not Pact.cosNames then
		Pact.cosNames = {}
		local ok, cc = pcall(dofile, "data/scripts/chaos/cosmetics_config.lua")
		if ok and type(cc) == "table" then
			for _, c in ipairs(cc.cosmetics or {}) do
				Pact.cosNames[c.key] = c.name
			end
		end
	end
	return Pact.cosNames[key] or key
end

-- ------------------------------------------------------------------ store services
local function refreshPlayer(player)
	if ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
	if ChaosStash and ChaosStash.onLimitsChanged then
		pcall(ChaosStash.onLimitsChanged, player) -- the stash window's slot counts (O316)
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

-- grants an extra without a purchase (stash.lua grandfathering, O316): the account ends with at least `amount` of it
-- and never less; true when the row is written
function Pact.grantExtra(accountId, key, amount, source)
	amount = math.floor(tonumber(amount) or 0)
	if amount <= 0 or not cfg.extras[key] then
		return false
	end
	local now = os.time()
	if not db.query(string.format("INSERT INTO `%s` (`account_id`, `extra_key`, `amount`, `updated`) VALUES (%d, %s, %d, %d) " ..
			"ON DUPLICATE KEY UPDATE `amount` = GREATEST(`amount`, %d), `updated` = %d", T.extras, accountId, q(key), amount, now, amount, now)) then
		return false
	end
	Pact.load(accountId)
	log(accountId, 0, source or "grant", key, amount)
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
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Your Chaos Pact runs until %s. Claim your %d Pact Marks every day in Character > Chaos Pact.",
			os.date("%Y-%m-%d %H:%M", ends), cfg.pact.dailyMarks))
		refreshPlayer(player)
		return true
	end
}

-- offer.amount: how many of the extra one purchase adds (default 1; pact_config.lua sells a pack of 4 stash slot expansions)
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

-- ------------------------------------------------------------------ daily Pact Marks
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
	addMarks(accountId, amount)
	log(accountId, player:getGuid(), "claim", tostring(day), amount)
	message(player, ChaosI18n.msg(MSG.claimed, amount))
	sendStatus(player, false)
end

-- ------------------------------------------------------------------ the Marks shelf
-- Marks buy the cosmetics of cfg.marks.shelf, nothing else (Core.shelfCheck refuses any other key)
local function marksBuy(player, data)
	local key = tostring(data.key or "")
	local accountId = player:getAccountId()
	local C = ChaosCosmetics
	if not (C and C.grant and C.owns) then
		return message(player, "Cosmetics are not available.", true)
	end
	local err = Core.shelfCheck(cfg, Pact.marksOf(accountId), {[key] = C.owns(accountId, key) or nil}, key)
	if err then
		return message(player, err, true)
	end
	local item = Core.shelfItem(cfg, key)
	if not takeMarks(accountId, item.marks) then
		return message(player, ChaosI18n.msg(MSG.marksShort, item.marks, Pact.marksOf(accountId)), true)
	end
	local ok, why = C.grant(accountId, key, "marks")
	if not ok then
		addMarks(accountId, item.marks) -- the Marks go back (the grant said no)
		db.query(string.format("UPDATE `%s` SET `earned` = `earned` - %d, `spent` = `spent` - %d WHERE `account_id` = %d",
			T.marks, item.marks, item.marks, accountId))
		return message(player, why or "Something went wrong. Your Marks were refunded.", true)
	end
	log(accountId, player:getGuid(), "marks", key, item.marks)
	if C.sendState then
		pcall(C.sendState, player, false)
	end
	message(player, ChaosI18n.msg(MSG.marksBought, Pact.cosmeticName(key), item.marks))
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
	marksBuy = {RATE.claim, marksBuy},
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

-- ------------------------------------------------------------------ expiry warnings (O317)
-- 3 days, then 1 day before the Pact ends (Core.expiry): a chat line and a toast (game_chaosnotify, kind "pact"), in the
-- player's language. At login every time in the window; while online once when the level changes. When the premium days
-- end in the same window the text names both and the Pacto Completo that renews them.
Pact.warned = Pact.warned or {} -- guid -> {ends, level} of the last warning in this session

local function toast(player, text)
	if ChaosNotify and ChaosNotify.send then
		ChaosNotify.send(player, "", text, "pact")
	elseif json and ChaosOpcodes and ChaosOpcodes.notifications then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "pact", message = text}))
	end
end

function Pact.expiryText(player, w)
	if w.both then
		if w.level <= 1 then
			return Chaos.t(player, "Your Chaos Pact and your Premium end within 24 hours. The Pacto Completo renews both: Store > Premium & Services.")
		end
		return Chaos.t(player, "Your Chaos Pact and your Premium end in %d days. The Pacto Completo renews both: Store > Premium & Services.", w.days)
	end
	if w.level <= 1 then
		return Chaos.t(player, "Your Chaos Pact ends within 24 hours. Renew it in Store > Premium & Services.")
	end
	return Chaos.t(player, "Your Chaos Pact ends in %d days. Renew it in Store > Premium & Services.", w.days)
end

-- atLogin: send whenever a warning is due; online: only when the level fell since the last one. Returns true when sent.
function Pact.warnExpiry(player, atLogin)
	local now = os.time()
	local st = Pact.state(player:getAccountId())
	local w = Core.expiry(cfg, st.pactEnds, player:getPremiumDays(), now)
	local guid = player:getGuid()
	local last = Pact.warned[guid]
	if not w then
		Pact.warned[guid] = nil
		return false
	end
	if not atLogin and last and last.ends == st.pactEnds and last.level <= w.level then
		return false
	end
	Pact.warned[guid] = {ends = st.pactEnds, level = w.level}
	local text = Pact.expiryText(player, w)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	toast(player, text)
	return true
end

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
		local text = Chaos.t(player, left == 1 and "Your Chaos Pact runs for %d more day." or "Your Chaos Pact runs for %d more days.", left)
		if Core.claim(cfg, st, now, Chaos.dayKey(now)) then
			text = text .. " " .. Chaos.t(player, "Today's %d Pact Marks wait in Character > Chaos Pact.", cfg.pact.dailyMarks)
		end
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, text)
		Pact.warnExpiry(player, true)
	elseif st.pactEnds > 0 and now - st.pactEnds < 14 * 86400 then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, Chaos.t(player,
			"Your Chaos Pact has ended. Nothing is lost: stash slots beyond your own expansions are withdraw-only, extra market offers run until they end, extra saved builds can be loaded or deleted."))
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

-- online players: the warning when the window opens (or the level falls), and the experience counters written once a minute
local think = GlobalEvent("ChaosPactThink")
local thinkTicks = 0
function think.onThink(interval)
	thinkTicks = thinkTicks + 1
	pcall(Pact.flushXp)
	if thinkTicks % 10 == 0 then
		for _, p in ipairs(Game.getPlayers()) do
			pcall(Pact.warnExpiry, p, false)
		end
	end
	return true
end
think:interval(60000)
think:register()

local logout = CreatureEvent("ChaosPactLogout")
function logout.onLogout(player)
	pcall(Pact.flushXp, player:getGuid())
	Pact.warned[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

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
		player:sendCancelMessage(Chaos.t(player, "Usage: /pact <player>, info | days <n> | end | extra <key> <amount> | claimreset"))
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
		player:sendCancelMessage(Chaos.t(player, "Usage: /pact <player>, info | days <n> | end | extra <key> <amount> | claimreset"))
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
