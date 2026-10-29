-- founder.lua: the Founder Pack's name plate title (O322). Rules: founder_core.lua; data: founder_config.lua; the sale itself is
-- the store (shop.lua: a bundle per tier with a sale window, one per account) and the pieces are exclusives
-- (exclusives.lua, source "founder"). Overview: server/README.md "Founder Pack".
--
-- The title is held while the account owns the tier's first exclusive, which only the pack gives, so it needs no table of
-- its own and survives a reload. The Grand Founder Pack also brings the plate frame `founder` (an exclusive of kind frame).
-- titles.lua builds its tables when it loads (possibly after this file): the source is put in at load, at startup and at every
-- login. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosFounderCore then
	dofile("data/scripts/chaos/founder_core.lua")
end

ChaosFounderConfig = dofile("data/scripts/chaos/founder_config.lua")
ChaosFounder = ChaosFounder or {}
local M = ChaosFounder
local F = ChaosFounderCore
local cfg = ChaosFounderConfig
M.core, M.config = F, cfg

local function source(player)
	local X = ChaosExclusives
	if not (X and X.owns) then
		return nil
	end
	local accountId = player:getAccountId()
	local out = F.titles(cfg, function(key)
		return X.owns(accountId, key)
	end)
	return #out > 0 and out or nil
end
M.titleSource = source

function M.ensureHooks()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("founder", source)
	end
end
M.ensureHooks()

-- ---------------------------------------------------------------- taking a pack back (a reversed donation)
local REV = cfg.revoke.table
db.query("CREATE TABLE IF NOT EXISTS `" .. REV .. "` (`id` int(11) NOT NULL AUTO_INCREMENT, `account_id` int(11) NOT NULL, " ..
	"`tier` varchar(32) NOT NULL, `order_id` int(11) NOT NULL DEFAULT 0, `purchase_id` int(11) NOT NULL DEFAULT 0, " ..
	"`pieces` int(11) NOT NULL DEFAULT 0, `pact_days` int(11) NOT NULL DEFAULT 0, `reason` varchar(64) NOT NULL DEFAULT '', " ..
	"`at` bigint(20) NOT NULL, PRIMARY KEY (`id`), UNIQUE KEY `chaos_founder_revokes_tier` (`account_id`, `tier`)) " ..
	"ENGINE=InnoDB DEFAULT CHARSET=utf8")

-- the tiers of an account taken back before: {[tier key] = true}
function M.revoked(accountId)
	local out = {}
	for _, r in ipairs(Chaos.select("SELECT `tier` FROM `" .. REV .. "` WHERE `account_id` = " .. accountId, {{"tier", "s"}})) do
		out[r.tier] = true
	end
	return out
end

-- takes tier `tierKey` back from an account: its exclusives (and with the first one the title), the plate frame on the
-- characters online, and the Pact days the pack gave. Once per account and tier (the row in `chaos_founder_revokes` is the
-- guard and the log); the sale stays used up. opts = {orderId, purchaseId, reason}. Returns true, summary or false, why.
function M.revoke(accountId, tierKey, opts)
	opts = opts or {}
	local tier = F.tier(cfg, tierKey)
	local X = ChaosExclusives
	if not tier then
		return false, "Unknown Founder tier " .. tostring(tierKey) .. "."
	end
	if not (X and X.revoke) then
		return false, "The exclusives system is not loaded."
	end
	if M.revoked(accountId)[tier.key] then
		return false, "That Founder tier was taken back already."
	end
	-- the guard row first: a second round cannot take it twice
	local reason = (opts.reason or "reversal"):sub(1, 64)
	if not db.query(string.format("INSERT INTO `%s` (`account_id`, `tier`, `order_id`, `purchase_id`, `pieces`, `pact_days`, `reason`, `at`) VALUES (%d, %s, %d, %d, 0, 0, %s, %d)",
			REV, accountId, db.escapeString(tier.key), tonumber(opts.orderId) or 0, tonumber(opts.purchaseId) or 0, db.escapeString(reason), os.time())) then
		return false, "Could not save the record."
	end
	local pieces = 0
	local okC, exclusivesCfg = pcall(dofile, "data/scripts/chaos/exclusives_config.lua")
	for _, key in ipairs(tier.exclusives) do
		if X.owns(accountId, key) then
			X.revoke(accountId, key)
			pieces = pieces + 1
			local e
			for _, x in ipairs(okC and exclusivesCfg.exclusives or {}) do
				if x.key == key then
					e = x
				end
			end
			-- the plate frame lives in a storage of every character; the others stay with the character until it is reloaded
			if e and e.kind == "frame" and ChaosShopCore.frameIndex and ChaosShopCore.frameStorage then
				local idx = ChaosShopCore.frameIndex(e.frame)
				for _, p in ipairs(Game.getPlayers()) do
					if idx and p:getAccountId() == accountId then
						p:setStorageValue(ChaosShopCore.frameStorage(Chaos.storage, idx), 0)
						if p:getStorageValue(Chaos.storage.shopFrameActive) == idx then
							p:setStorageValue(Chaos.storage.shopFrameActive, 0)
						end
						pcall(function() if ChaosNameplate and ChaosNameplate.refresh then ChaosNameplate.refresh(p) end end)
					end
				end
			end
		end
	end
	local days = 0
	if ChaosPact and ChaosPact.revokeDays and tier.pactDays > 0 then
		days = ChaosPact.revokeDays(accountId, tier.pactDays, "founder revoke") or 0
	end
	db.query(string.format("UPDATE `%s` SET `pieces` = %d, `pact_days` = %d WHERE `account_id` = %d AND `tier` = %s", REV, pieces, days, accountId,
		db.escapeString(tier.key)))
	local line = string.format("account %d: %s taken back (%s): %d pieces, %d Pact days, title gone with the first piece",
		accountId, tier.name, reason, pieces, days)
	print("[Chaos founder] " .. line)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "%s was taken back: the donation that paid for it was refunded or charged back.", tier.name))
		end
	end
	return true, line
end

-- the donation reversal calls this (shop_payments.lua processReversals): order = {id, created}, shortfall = coins not taken
-- back from the balance. Returns the lines logged.
function M.onReversal(accountId, order, shortfall)
	local lines = {}
	local purchases = Chaos.select("SELECT `id`, `offer_key`, `created`, `gift_player` FROM `chaos_shop_purchases` WHERE `account_id` = " .. accountId ..
		" AND `offer_key` LIKE 'founder:%' ORDER BY `id`", {{"id", "n"}, {"offer_key", "s"}, {"created", "n"}, {"gift_player", "n"}})
	local rows = {}
	for i, r in ipairs(purchases) do
		rows[i] = {id = r.id, key = r.offer_key, created = r.created, gift = r.gift_player}
	end
	for _, t in ipairs(F.revokeTargets(cfg, order, shortfall, rows, M.revoked(accountId))) do
		local ok, line = M.revoke(accountId, t.key, {orderId = order.id, purchaseId = t.purchase, reason = "donation " .. tostring(order.id) .. " reversed"})
		lines[#lines + 1] = line
	end
	return lines
end

local login = CreatureEvent("ChaosFounderLogin")
function login.onLogin(player)
	M.ensureHooks()
	return true
end
login:register()

local startup = GlobalEvent("ChaosFounderStartup")
function startup.onStartup()
	M.ensureHooks()
	local okX, exclusives = pcall(dofile, "data/scripts/chaos/exclusives_config.lua")
	local okP, pact = pcall(dofile, "data/scripts/chaos/pact_config.lua")
	local limits = dofile("data/scripts/chaos/store_balance_config.lua").founder
	for _, p in ipairs(F.validate(cfg, {exclusives = okX and exclusives or nil, limits = limits,
		pactPrice = okP and pact.store.pact.offers[1].cost or nil})) do
		print("[Warning - Chaos founder] " .. p)
	end
	return true
end
startup:register()
