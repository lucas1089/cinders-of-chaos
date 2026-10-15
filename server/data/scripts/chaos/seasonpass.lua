-- Season pass: an account-wide pass per season with a free and a premium track of 50 tiers, pass XP from play
-- (experience, bosses, bounty contracts, rifts, treasure goblins, invasions, daily and weekly challenges), a claim
-- window in the client (game_battlepass, Adventure > Season Pass) and three season packs.
-- Rules and rewards: seasonpass_config.lua; pure logic: seasonpass_core.lua (tests: server/tests/seasonpass_test.lua);
-- store category: seasonpass_store.lua (included by shop_config.lua); tables: server/sql/chaos_seasonpass.sql (also
-- created at startup). Overview: server/README.md "Season pass".
--
-- The pass of a season runs while that season of season_config.lua runs (season.lua decides; /season start|end moves
-- it too). Every character of the account adds to the same pass, season and standard characters alike; staff
-- (group >= staffGroup) add nothing. Rewards reached can be claimed up to claimGraceDays after the season ended.
--
-- Where the pass XP comes from (nothing of the other systems is edited; hooks are installed at runtime):
--   EventCallback onGainExperience   1 unit per 1% of a level: monster base experience x the level's stage only
--   kill event                       monster kills (challenges)
--   ChaosLeaderboard.record          wrapped: "bounty", "rift" (value = tier), "goblin", "defender" (invasions)
--   ChaosBossPoints.grant            wrapped: every credited kill of a boss of bosspoints_config.lua
-- Store: ChaosShopServices.check / deliver are wrapped for the unlock offers of the pass and the packs.
--
-- Safety: a claim is a row whose primary key is (account, season, tier, track); the row is written with a random
-- token and read back before anything is given, so two characters of the account clicking at once give one reward.
-- The premium pass and the packs work the same way (a lost race refunds the coins).
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.seasonPass (227):
--   client -> server  open | tiers {season} | claim {tier, track} | claimAll
--                     buy {what = "premium" | 1 | 2 | 3, price, gift?}   gift = a character name: bought for its account
--                     giftPrice {what, gift}                             what that account would pay
--                     frame {on}
--   server -> client  state {...} (see stateOf) | tiers {season, first, last, rows} | giftPrice {what, name, price}
--                     notice {text}
-- Gods: /seasonpass status | xp <amount> [character] (test helper; adds pass XP to that character's account).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/seasonpass_core.lua")
if not ChaosSeason or not ChaosSeason.status then
	dofile("data/scripts/chaos/season_core.lua")
end

Chaos.seasonPassConfig = dofile("data/scripts/chaos/seasonpass_config.lua")
local cfg = Chaos.seasonPassConfig
local P = ChaosSeasonPassCore
local OPCODE = (ChaosOpcodes and ChaosOpcodes.seasonPass) or cfg.opcode
local NOTIFY = (ChaosOpcodes and ChaosOpcodes.notifications) or 79
local T = cfg.tables

ChaosSeasonPass = ChaosSeasonPass or {}
local SP = ChaosSeasonPass
SP.acc = SP.acc or {} -- accountId -> account state (while a character of it is online)

local function log(text)
	print("[Chaos season pass] " .. text)
end

local function now()
	return os.time()
end

-- ---------------------------------------------------------------- seasons
local function seasonCfg()
	return Chaos.seasonConfig or dofile("data/scripts/chaos/season_config.lua")
end

local function overrides()
	return ChaosSeason and ChaosSeason.ov or {}
end

-- the season whose pass progresses now (running and with a pass), or nil
function SP.active()
	local s
	if ChaosSeason and ChaosSeason.current and Chaos.seasonConfig then
		s = ChaosSeason.current()
	else
		s = ChaosSeason.active(seasonCfg().seasons, now(), overrides())
	end
	if s and cfg.passes[s.id] then
		return s
	end
	return nil
end

-- the season the window shows: the running one, else the last ended one still in its claim grace, else the next one
function SP.shown()
	local a = SP.active()
	if a then
		return a, "active"
	end
	local t, ov = now(), overrides()
	local best, bestEnd
	for _, s in ipairs(seasonCfg().seasons) do
		if cfg.passes[s.id] and ChaosSeason.status(s, t, ov) == "ended" then
			local _, finish = ChaosSeason.times(s, ov)
			if finish and t < finish + cfg.claimGraceDays * 86400 and (not bestEnd or finish > bestEnd) then
				best, bestEnd = s, finish
			end
		end
	end
	if best then
		return best, "grace"
	end
	local nxt = ChaosSeason.upcoming(seasonCfg().seasons, t, ov)
	if nxt and cfg.passes[nxt.id] then
		return nxt, "upcoming"
	end
	return nil, nil
end

local function staff(player)
	return player:getGroup():getId() >= cfg.staffGroup
end

local function token()
	return string.format("%08x%08x%08x", math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), now() % 0x7fffffff)
end

local function logEvent(account, guid, season, event, detail)
	db.asyncQuery(string.format("INSERT INTO `%s` (`at`, `account_id`, `player_id`, `season`, `event`, `detail`) VALUES " ..
		"(%d, %d, %d, %d, %s, %s)", T.log, now(), account or 0, guid or 0, season or 0, db.escapeString(event),
		db.escapeString(tostring(detail or ""):sub(1, 255))))
end

-- ---------------------------------------------------------------- tables
local DDL = {
	"CREATE TABLE IF NOT EXISTS `chaos_seasonpass` (`account_id` int(11) NOT NULL, `season` smallint(5) unsigned NOT NULL, " ..
		"`xp` int(10) unsigned NOT NULL DEFAULT 0, `premium` tinyint(1) unsigned NOT NULL DEFAULT 0, `premium_paid` int(10) " ..
		"unsigned NOT NULL DEFAULT 0, `premium_token` varchar(32) NOT NULL DEFAULT '', `premium_at` int(10) unsigned NOT NULL " ..
		"DEFAULT 0, `updated_at` int(10) unsigned NOT NULL DEFAULT 0, PRIMARY KEY (`account_id`, `season`)) ENGINE=InnoDB " ..
		"DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `chaos_seasonpass_claims` (`account_id` int(11) NOT NULL, `season` smallint(5) unsigned NOT " ..
		"NULL, `tier` tinyint(3) unsigned NOT NULL, `track` tinyint(1) unsigned NOT NULL, `player_id` int(11) NOT NULL DEFAULT 0, " ..
		"`claimed_at` int(10) unsigned NOT NULL, `token` varchar(32) NOT NULL DEFAULT '', PRIMARY KEY (`account_id`, `season`, " ..
		"`tier`, `track`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `chaos_seasonpass_periods` (`account_id` int(11) NOT NULL, `season` smallint(5) unsigned NOT " ..
		"NULL, `period` int(10) unsigned NOT NULL, `key` varchar(40) NOT NULL, `value` bigint(20) NOT NULL DEFAULT 0, PRIMARY KEY " ..
		"(`account_id`, `season`, `period`, `key`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `chaos_seasonpass_packs` (`account_id` int(11) NOT NULL, `season` smallint(5) unsigned NOT NULL, " ..
		"`pack` tinyint(3) unsigned NOT NULL, `paid` int(10) unsigned NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0, " ..
		"`bought_at` int(10) unsigned NOT NULL, `token` varchar(32) NOT NULL DEFAULT '', PRIMARY KEY (`account_id`, `season`, " ..
		"`pack`)) ENGINE=InnoDB DEFAULT CHARSET=utf8",
	"CREATE TABLE IF NOT EXISTS `chaos_seasonpass_log` (`id` int(10) unsigned NOT NULL AUTO_INCREMENT, `at` int(10) unsigned " ..
		"NOT NULL, `account_id` int(11) NOT NULL DEFAULT 0, `player_id` int(11) NOT NULL DEFAULT 0, `season` smallint(5) unsigned " ..
		"NOT NULL, `event` varchar(16) NOT NULL, `detail` varchar(255) NOT NULL DEFAULT '', PRIMARY KEY (`id`), KEY " ..
		"`chaos_seasonpass_log_account` (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8"
}

-- ---------------------------------------------------------------- account state
-- acc = {id, all = {[season] = {claims = {[0] = {}, [1] = {}}, pack = n}}, season, xp, premium, premiumPaid,
--        day, week, periods = {[period] = {[key] = value}}, dirty = {xp, periods = {[period] = {[key] = true}}}, frac}
local function loadAll(account)
	local all = {}
	local function get(season)
		all[season] = all[season] or {claims = {[0] = {}, [1] = {}}, pack = 0, packs = {}}
		return all[season]
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `season`, `tier`, `track` FROM `%s` WHERE `account_id` = %d",
		T.claims, account), {{"season", "n"}, {"tier", "n"}, {"track", "n"}})) do
		local s = get(r.season)
		s.claims[r.track] = s.claims[r.track] or {}
		s.claims[r.track][r.tier] = true
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `season`, `pack`, `paid` FROM `%s` WHERE `account_id` = %d",
		T.packs, account), {{"season", "n"}, {"pack", "n"}, {"paid", "n"}})) do
		local s = get(r.season)
		s.packs[r.pack] = r.paid
		s.pack = math.max(s.pack, r.pack)
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `season`, `xp`, `premium`, `premium_paid` FROM `%s` WHERE " ..
		"`account_id` = %d", T.accounts, account), {{"season", "n"}, {"xp", "n"}, {"premium", "n"}, {"premium_paid", "n"}})) do
		local s = get(r.season)
		s.xp, s.premium, s.premiumPaid = r.xp, r.premium > 0, r.premium_paid
	end
	return all, get
end

local function loadPeriod(acc, period)
	local map = {}
	if acc.season then
		for _, r in ipairs(Chaos.select(string.format("SELECT `key`, `value` FROM `%s` WHERE `account_id` = %d AND `season` = %d " ..
			"AND `period` = %d", T.periods, acc.id, acc.season, period), {{"key", "s"}, {"value", "n"}})) do
			map[r.key] = r.value
		end
	end
	acc.periods[period] = map
	return map
end

-- the account's state for season (the shown one); loaded once per login of the first character of the account
function SP.account(account, reload)
	local acc = SP.acc[account]
	local season = SP.shown()
	local sid = season and season.id or nil
	if acc and not reload and acc.season == sid then
		return acc
	end
	if acc then
		SP.flush(acc)
	end
	local all, get = loadAll(account)
	acc = {id = account, all = all, season = sid, periods = {}, dirty = {periods = {}}, frac = 0, expUnits = 0}
	if sid then
		local s = get(sid)
		acc.cur = s
		acc.xp = s.xp or 0
		acc.premium = s.premium or false
		acc.premiumPaid = s.premiumPaid or 0
	else
		acc.cur = {claims = {[0] = {}, [1] = {}}, pack = 0, packs = {}}
		acc.xp, acc.premium, acc.premiumPaid = 0, false, 0
	end
	SP.acc[account] = acc
	return acc
end

local function pass(acc)
	return acc and acc.season and cfg.passes[acc.season] or nil
end

local function hasPremium(acc)
	local p = pass(acc)
	return p and P.hasPremium(p, acc.premium, acc.cur.pack) or false
end

-- day / week rollover: the periods of the current day and week are kept in memory. A week period is the YYYYMMDD of
-- its Monday x 10 + 7, so it never equals a day period.
local function periodsOf(acc)
	local t = now()
	local day, week = P.dayKey(t), P.weekKey(t) * 10 + 7
	if acc.day ~= day or acc.week ~= week then
		SP.flush(acc)
		acc.periods = {}
		acc.prev = {}
		acc.day, acc.week = day, week
		loadPeriod(acc, day)
		loadPeriod(acc, week)
	end
	return acc.periods[day], acc.periods[week], day, week
end

local function setPeriod(acc, period, key, value)
	acc.periods[period] = acc.periods[period] or {}
	acc.periods[period][key] = value
	acc.dirty.periods[period] = acc.dirty.periods[period] or {}
	acc.dirty.periods[period][key] = true
end

-- write what changed in memory (absolute values with GREATEST: the values only grow, so a late write is harmless)
function SP.flush(acc)
	if not acc or not acc.season then
		return
	end
	if acc.dirty.xp then
		acc.dirty.xp = false
		db.query(string.format("INSERT INTO `%s` (`account_id`, `season`, `xp`, `updated_at`) VALUES (%d, %d, %d, %d) ON " ..
			"DUPLICATE KEY UPDATE `xp` = GREATEST(`xp`, VALUES(`xp`)), `updated_at` = VALUES(`updated_at`)", T.accounts, acc.id,
			acc.season, math.floor(acc.xp), now()))
	end
	for period, keys in pairs(acc.dirty.periods) do
		local values = {}
		for key in pairs(keys) do
			local v = acc.periods[period] and acc.periods[period][key]
			if v then
				values[#values + 1] = string.format("(%d, %d, %d, %s, %d)", acc.id, acc.season, period, db.escapeString(key),
					math.floor(v))
			end
		end
		if #values > 0 then
			db.query(string.format("INSERT INTO `%s` (`account_id`, `season`, `period`, `key`, `value`) VALUES %s ON DUPLICATE " ..
				"KEY UPDATE `value` = GREATEST(`value`, VALUES(`value`))", T.periods, table.concat(values, ", ")))
		end
	end
	acc.dirty.periods = {}
end

local function accountPlayers(account)
	local list = {}
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == account then
			list[#list + 1] = p
		end
	end
	return list
end

local function toast(player, text)
	if json then
		player:sendExtendedOpcode(NOTIFY, json.encode({action = "seasonpass", message = text}))
	end
end

-- text: the chat line; short (optional): the toast, which shows two short lines. Keys or deferred texts
-- (ChaosI18n.msg): each character reads them in its own language
local function tellAccount(account, text, effect, short)
	for _, p in ipairs(accountPlayers(account)) do
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, text))
		toast(p, Chaos.t(p, short or text))
		if effect then
			p:getPosition():sendMagicEffect(effect)
		end
	end
end

-- ---------------------------------------------------------------- pass XP
local function refreshAccount(account)
	for _, p in ipairs(accountPlayers(account)) do
		SP.sendState(p, false)
	end
end

function SP.addXp(acc, amount, why)
	amount = math.floor(amount or 0)
	if amount <= 0 or not acc.season then
		return 0
	end
	local before = P.tierOf(cfg, acc.xp)
	acc.xp = math.min(P.maxXp(cfg), acc.xp + amount)
	acc.cur.xp = acc.xp
	acc.dirty.xp = true
	local after = P.tierOf(cfg, acc.xp)
	if after > before then
		SP.flush(acc)
		local p = pass(acc)
		local text = after - before == 1 and ChaosI18n.msg("%s: tier %d reached! Claim your rewards in Adventure > Season Pass.",
			p.name, after) or ChaosI18n.msg("%s: tiers %d to %d reached! Claim your rewards in Adventure > Season Pass.",
			p.name, before + 1, after)
		tellAccount(acc.id, text, CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_BLUE,
			ChaosI18n.msg("Tier %d reached! New rewards to claim.", after))
		logEvent(acc.id, 0, acc.season, "tier", string.format("%d -> %d (%s)", before, after, tostring(why or "")))
		refreshAccount(acc.id)
	end
	return amount
end

-- the banked daily cap (cfg.bankDays): the pass XP of capKey on today and the days before, newest first, and how many
-- of those days the season ran. The earlier days are read once per day (acc.prev).
local function capWindow(acc, today, capKey)
	local n = math.max(1, math.floor(tonumber(cfg.bankDays) or 1))
	local t = now()
	local start
	local season = SP.active()
	if season and ChaosSeason and ChaosSeason.times then
		local ok, st = pcall(ChaosSeason.times, season, overrides())
		start = ok and st or nil
	end
	local startKey = start and P.dayKey(start) or 0
	acc.prev = acc.prev or {}
	local used, days = {today[capKey] or 0}, 1
	for i = 1, n - 1 do
		local key = P.dayKey(t - i * 86400)
		if key < startKey then
			break
		end
		if not acc.prev[key] then
			local saved = acc.periods
			acc.periods = {}
			acc.prev[key] = loadPeriod(acc, key)
			acc.periods = saved
		end
		used[#used + 1] = acc.prev[key][capKey] or 0
		days = days + 1
	end
	return used, days
end
SP.capWindow = capWindow

-- one game event of a character: pass XP from the source (daily cap) and the challenges
-- source: exp (value = level units), kill, boss, bounty, rift (value = tier), goblin, invasion
function SP.progress(player, source, value)
	if not player or staff(player) then
		return
	end
	local season = SP.active()
	if not season then
		return
	end
	local acc = SP.account(player:getAccountId())
	if acc.season ~= season.id then
		return
	end
	local today, thisWeek, day, week = periodsOf(acc)
	-- source pass XP
	if cfg.sources[source] then
		local capKey = "cap:" .. source
		local gain
		if source == "exp" then
			acc.frac = acc.frac + (tonumber(value) or 0) * cfg.sources.exp.xp
			local whole = math.floor(acc.frac)
			acc.frac = acc.frac - whole
			local used, days = capWindow(acc, today, capKey)
			gain = P.sourceGain(cfg, "exp", whole / cfg.sources.exp.xp, used, days)
		else
			local used, days = capWindow(acc, today, capKey)
			gain = P.sourceGain(cfg, source, value, used, days)
		end
		if gain > 0 then
			setPeriod(acc, day, capKey, (today[capKey] or 0) + gain)
			SP.addXp(acc, gain, source)
		end
	end
	-- challenges
	local stats = P.statsOf(source, value)
	for _, kind in ipairs({"daily", "weekly"}) do
		local period = kind == "daily" and day or week
		local map = kind == "daily" and today or thisWeek
		for _, c in ipairs(P.challenges(cfg, acc.season, kind, period)) do
			local add = stats[c.stat]
			if add and add > 0 and not map["done:" .. c.key] then
				local key = "ch:" .. c.key
				local v = (map[key] or 0) + add
				setPeriod(acc, period, key, math.min(c.target, v))
				map[key] = math.min(c.target, v)
				if v >= c.target then
					setPeriod(acc, period, "done:" .. c.key, 1)
					local xp = kind == "daily" and cfg.challenges.dailyXp or cfg.challenges.weeklyXp
					local daily = kind == "daily"
					tellAccount(acc.id, ChaosI18n.msg(daily and "Daily challenge done: %s (+%d pass XP)." or
						"Weekly challenge done: %s (+%d pass XP).", ChaosI18n.msg(c.text), xp), nil,
						ChaosI18n.msg("Challenge done: +%d pass XP.", xp))
					logEvent(acc.id, player:getGuid(), acc.season, "challenge", c.key)
					SP.addXp(acc, xp, "challenge " .. c.key)
					refreshAccount(acc.id)
				end
			end
		end
	end
end

-- ---------------------------------------------------------------- cosmetics (account-wide)
local function entitlements(acc)
	local out = {}
	for season, s in pairs(acc.all) do
		local p = cfg.passes[season]
		if p then
			for _, r in ipairs(P.entitlements(p, s.claims, s.pack)) do
				out[#out + 1] = r
			end
		end
	end
	return out
end

-- give every outfit, mount and shader of the account this character lacks; returns the names added
function SP.deliverCosmetics(player)
	local acc = SP.account(player:getAccountId())
	local added = {}
	local shaderBase = Chaos.storage and Chaos.storage.shopShaderBase
	for _, r in ipairs(entitlements(acc)) do
		if r.kind == "outfit" then
			local addons = r.addons or 0
			local mine = player:getSex() == PLAYERSEX_FEMALE and r.female or r.male
			local fresh = not player:hasOutfit(mine, addons)
			for _, look in ipairs({r.male, r.female}) do
				if not player:hasOutfit(look) then
					player:addOutfit(look)
				end
				for _, bit in ipairs({1, 2}) do
					-- addons: 1 = first, 2 = second, 3 = both
					if (addons == bit or addons == 3) and not player:hasOutfit(look, bit) then
						player:addOutfitAddon(look, bit)
					end
				end
			end
			if fresh then
				added[#added + 1] = r.name or "an outfit"
			end
		elseif r.kind == "mount" then
			if not player:hasMount(r.id) then
				player:addMount(r.id)
				added[#added + 1] = r.name or "a mount"
			end
		elseif r.kind == "shader" and player.addShader then
			local key = shaderBase and (shaderBase + r.id)
			if not key or player:getStorageValue(key) < 1 then
				player:addShader(r.id)
				if key then
					player:setStorageValue(key, 1)
				end
				added[#added + 1] = r.name or Chaos.t(player, "a shader")
			end
		end
	end
	if #added > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Season pass cosmetics of your account: %s.",
			table.concat(added, ", ")))
	end
	return added
end

local function deliverAccount(account)
	for _, p in ipairs(accountPlayers(account)) do
		SP.deliverCosmetics(p)
		if ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, p)
		end
	end
end

function SP.titlesOf(player)
	local acc = SP.acc[player:getAccountId()]
	if not acc then
		return nil
	end
	local out = {}
	for _, r in ipairs(entitlements(acc)) do
		if r.kind == "title" then
			out[#out + 1] = {text = r.title, key = "seasonpass:" .. r.title:lower(), color = r.color}
		end
	end
	return out
end

local function ownsKind(player, kind, field, value)
	local acc = SP.acc[player:getAccountId()] or SP.account(player:getAccountId())
	for _, r in ipairs(entitlements(acc)) do
		if r.kind == kind and r[field] == value then
			return true
		end
	end
	return false
end

-- townportal.lua asks for the "season" route styles
function SP.ownsPortal(player, key)
	return ownsKind(player, "portal", "key", key)
end

-- transmog.lua asks for the appearance sets of source "season" (synced when the Transmog window opens)
function SP.ownsTransmog(player, key)
	return ownsKind(player, "transmog", "key", key)
end

function SP.frameOf(player)
	local acc = SP.acc[player:getAccountId()]
	if not acc or player:getStorageValue(cfg.storage.frameOff) == 1 then
		return nil
	end
	for _, r in ipairs(entitlements(acc)) do
		if r.kind == "frame" then
			return r.frame
		end
	end
	return nil
end

-- ---------------------------------------------------------------- claims
local function viewOf(acc, open)
	return {tier = (P.tierOf(cfg, acc.xp)), premium = hasPremium(acc), claimed = acc.cur.claims, open = open}
end

local function claimOpen()
	local s, status = SP.shown()
	return s and (status == "active" or status == "grace") or false
end

local function giveReward(player, acc, r)
	if r.kind == "item" then
		local given = Chaos.giveItem(player, r.id, r.count)
		if given < r.count then
			if given > 0 then
				player:removeItem(r.id, given)
			end
			return false, "You do not have enough room or capacity for " .. P.rewardText(r) .. "."
		end
	elseif r.kind == "coins" then
		if not ChaosShop or not ChaosShop.addCoins then
			return false, "The store is not available: try again later."
		end
		ChaosShop.addCoins(acc.id, r.amount)
	end
	return true
end

-- returns true or false, reason
function SP.claim(player, tier, track, quiet)
	local acc = SP.account(player:getAccountId())
	local p = pass(acc)
	if not p then
		return false, "No season pass is running."
	end
	local r, why = P.claimCheck(p, viewOf(acc, claimOpen()), tier, track)
	if not r then
		return false, why
	end
	-- the pass is the account's: its items (gold, potions) go to standard characters while the season runs
	-- (season_config.lua passItems); they stay claimable
	local seasonal = ChaosSeason and ChaosSeason.passClaimProblem and ChaosSeason.passClaimProblem(player, r)
	if seasonal then
		return false, seasonal
	end
	local tok = token()
	db.query(string.format("INSERT IGNORE INTO `%s` (`account_id`, `season`, `tier`, `track`, `player_id`, `claimed_at`, `token`) " ..
		"VALUES (%d, %d, %d, %d, %d, %d, %s)", T.claims, acc.id, acc.season, tier, track, player:getGuid(), now(),
		db.escapeString(tok)))
	local rows = Chaos.select(string.format("SELECT `token` FROM `%s` WHERE `account_id` = %d AND `season` = %d AND `tier` = %d " ..
		"AND `track` = %d", T.claims, acc.id, acc.season, tier, track), {{"token", "s"}})
	if not rows[1] or rows[1].token ~= tok then
		acc.cur.claims[track][tier] = true
		return false, "Already claimed."
	end
	local ok, err = giveReward(player, acc, r)
	if not ok then
		db.query(string.format("DELETE FROM `%s` WHERE `account_id` = %d AND `season` = %d AND `tier` = %d AND `track` = %d AND " ..
			"`token` = %s", T.claims, acc.id, acc.season, tier, track, db.escapeString(tok)))
		return false, err
	end
	acc.cur.claims[track][tier] = true
	logEvent(acc.id, player:getGuid(), acc.season, "claim", string.format("%d %s %s", tier, track == P.PREMIUM and "premium" or
		"free", P.rewardText(r)))
	if P.COSMETIC[r.kind] then
		deliverAccount(acc.id)
	end
	if not quiet then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Season pass tier %d (%s): %s.", tier,
			Chaos.t(player, track == P.PREMIUM and "premium" or "free"), P.rewardText(r, Chaos.lang(player))))
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN or CONST_ME_MAGIC_BLUE)
	end
	return true, r
end

function SP.claimAll(player)
	local acc = SP.account(player:getAccountId())
	local p = pass(acc)
	if not p then
		return 0, "No season pass is running."
	end
	-- without room for an item, the other items wait (they stay claimable) and coins and cosmetics are still claimed
	local got, names, stop, noRoom = 0, {}, nil, false
	local view = viewOf(acc, claimOpen())
	for _, c in ipairs(P.claimable(p, view)) do
		local reward = P.claimCheck(p, view, c.tier, c.track)
		if not (noRoom and reward and reward.kind == "item") then
			local ok, r = SP.claim(player, c.tier, c.track, true)
			if ok then
				got = got + 1
				names[#names + 1] = P.rewardText(r, Chaos.lang(player))
			else
				stop = r
				noRoom = noRoom or (type(r) == "string" and r:find("room", 1, true) ~= nil)
			end
		end
	end
	if got > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Season pass: claimed %d reward%s: %s.", got,
			got == 1 and "" or "s", table.concat(names, ", ")))
		player:getPosition():sendMagicEffect(CONST_ME_MAGIC_GREEN or CONST_ME_MAGIC_BLUE)
	end
	return got, stop
end

-- A late buyer gets every premium reward of the tiers already reached at once (P.premiumBacklog: cosmetics and coins
-- only, so nothing needs room). Needs a character of the account online (the claim row names it); an account that got
-- the pass as a gift while offline gets them at its next login. Returns how many were claimed.
function SP.claimPremiumBacklog(account)
	local player = accountPlayers(account)[1]
	local acc = SP.acc[account]
	local p = acc and pass(acc)
	if not player or not p then
		return 0
	end
	local got, names = 0, {}
	for _, c in ipairs(P.premiumBacklog(p, viewOf(acc, claimOpen()))) do
		local ok, r = SP.claim(player, c.tier, c.track, true)
		if ok then
			got = got + 1
			names[#names + 1] = P.rewardText(r)
		end
	end
	if got > 0 then
		tellAccount(account, ChaosI18n.msg(got == 1 and "Premium %s: the %d reward of the tiers you already reached is yours: %s." or
			"Premium %s: the %d rewards of the tiers you already reached are yours: %s.", p.name, got, table.concat(names, ", ")), nil,
			ChaosI18n.msg("%d premium reward%s unlocked", got, got == 1 and "" or "s"))
		refreshAccount(account)
	end
	return got
end

-- ---------------------------------------------------------------- premium and packs
-- An account may have no character online (a gift): its state is loaded for the grant and dropped again afterwards.
local function releaseIfOffline(account)
	if #accountPlayers(account) == 0 and SP.acc[account] then
		SP.flush(SP.acc[account])
		SP.acc[account] = nil
	end
end

local function sameSeason(acc)
	local season = SP.active()
	return season and acc.season == season.id
end

-- the premium track for `account` (paid = coins paid for the pass on its own; actorGuid = who bought it).
-- Returns true or false, why
function SP.grantPremium(account, actorGuid, paid, source)
	local acc = SP.account(account)
	if not sameSeason(acc) then
		return false, "The season pass can only be bought while its season runs."
	end
	if hasPremium(acc) then
		return false, ChaosI18n.msg("That account already has the premium %s.", pass(acc).name)
	end
	SP.flush(acc)
	local tok = token()
	db.query(string.format("INSERT INTO `%s` (`account_id`, `season`, `xp`, `premium`, `premium_paid`, `premium_token`, " ..
		"`premium_at`, `updated_at`) VALUES (%d, %d, %d, 1, %d, %s, %d, %d) ON DUPLICATE KEY UPDATE " ..
		"`premium_paid` = IF(`premium` = 0, VALUES(`premium_paid`), `premium_paid`), " ..
		"`premium_token` = IF(`premium` = 0, VALUES(`premium_token`), `premium_token`), " ..
		"`premium_at` = IF(`premium` = 0, VALUES(`premium_at`), `premium_at`), `premium` = 1", T.accounts, acc.id, acc.season,
		math.floor(acc.xp), paid or 0, db.escapeString(tok), now(), now()))
	local rows = Chaos.select(string.format("SELECT `premium_token` FROM `%s` WHERE `account_id` = %d AND `season` = %d",
		T.accounts, acc.id, acc.season), {{"premium_token", "s"}})
	if not rows[1] or rows[1].premium_token ~= tok then
		acc.premium = true
		return false, "That account already has the premium pass."
	end
	acc.premium, acc.premiumPaid = true, paid or 0
	acc.cur.premium, acc.cur.premiumPaid = true, paid or 0
	logEvent(acc.id, actorGuid, acc.season, "premium", string.format("%s, %d coins", tostring(source), paid or 0))
	tellAccount(acc.id, ChaosI18n.msg("The premium %s is unlocked for your whole account. Its rewards wait in Adventure > Season Pass.",
		pass(acc).name), CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_BLUE, "Premium track unlocked!")
	refreshAccount(acc.id)
	SP.claimPremiumBacklog(acc.id)
	return true
end

-- pack `id` for `account` (paid = coins paid for it). Returns true or false, why
function SP.grantPack(account, actorGuid, id, paid, source)
	local acc = SP.account(account)
	if not sameSeason(acc) then
		return false, "Season packs can only be bought while their season runs."
	end
	local p = pass(acc)
	local pk = P.pack(p, id)
	if not pk then
		return false, "This pack does not exist."
	end
	local from = acc.cur.pack
	if from >= id then
		return false, ChaosI18n.msg("That account already owns %s.", pk.name)
	end
	local tok = token()
	db.query(string.format("INSERT IGNORE INTO `%s` (`account_id`, `season`, `pack`, `paid`, `player_id`, `bought_at`, `token`) " ..
		"VALUES (%d, %d, %d, %d, %d, %d, %s)", T.packs, acc.id, acc.season, id, paid or 0, actorGuid or 0, now(),
		db.escapeString(tok)))
	local rows = Chaos.select(string.format("SELECT `token` FROM `%s` WHERE `account_id` = %d AND `season` = %d AND `pack` = %d",
		T.packs, acc.id, acc.season, id), {{"token", "s"}})
	if not rows[1] or rows[1].token ~= tok then
		return false, ChaosI18n.msg("That account already owns %s.", pk.name)
	end
	acc.cur.packs[id] = paid or 0
	acc.cur.pack = id
	logEvent(acc.id, actorGuid, acc.season, "pack", string.format("%d %s, %d coins (%s)", id, pk.name, paid or 0, tostring(source)))
	for _, r in ipairs(P.packGrants(p, from, id)) do
		if r.kind == "coins" and ChaosShop and ChaosShop.addCoins then
			ChaosShop.addCoins(acc.id, r.amount)
		elseif r.kind == "tierskips" then
			SP.addXp(acc, P.skip(cfg, acc.xp, r.count) - acc.xp, "tier skips")
		end
	end
	SP.flush(acc)
	deliverAccount(acc.id)
	tellAccount(acc.id, ChaosI18n.msg("%s is yours: its cosmetics are on every character of your account.", pk.name),
		CONST_ME_FIREWORK_RED or CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_BLUE, ChaosI18n.msg("%s unlocked!", pk.name))
	refreshAccount(acc.id)
	if hasPremium(acc) then
		SP.claimPremiumBacklog(acc.id)
	end
	return true
end

-- the price of an offer of the pass window for this account, or nil and why it cannot be bought
function SP.offerPrice(acc, what)
	local p = pass(acc)
	if not p or not sameSeason(acc) then
		return nil, "Only while the season runs."
	end
	if what == "premium" then
		if hasPremium(acc) then
			return nil, "Owned."
		end
		return p.premium.price
	end
	return P.packPrice(p, tonumber(what) or 0, acc.cur.pack, acc.premiumPaid)
end

local function spendCoins(account, amount)
	if amount <= 0 then
		return true
	end
	local Shop = ChaosShop
	if not Shop or not Shop.getCoins or Shop.getCoins(account) < amount then
		return false
	end
	if Shop.spend then
		return Shop.spend(account, amount) -- shop.lua: counts only when the UPDATE changed the row
	end
	-- the website (Character Bazaar) changes the balance from another process: db.query is true even when the WHERE
	-- matched nothing, so the change is read back (ROW_COUNT)
	if not db.query(string.format("UPDATE `%s` SET `coins` = `coins` - %d WHERE `account_id` = %d AND `coins` >= %d",
			Chaos.tables.shopCoins, amount, account, amount)) then
		return false
	end
	local r = Chaos.select("SELECT ROW_COUNT() AS `n`", {{"n", "n"}})[1]
	return r ~= nil and r.n == 1
end
SP.spendCoins = spendCoins

local function shopHistory(player, title, cost)
	db.asyncQuery(string.format("INSERT INTO `%s` (`account_id`, `player_id`, `title`, `cost`, `created`) VALUES (%d, %d, %s, %d, %d)",
		Chaos.tables.shopHistory, player:getAccountId(), player:getGuid(), db.escapeString(title), cost, now()))
end

local function offerName(acc, what)
	if what == "premium" then
		return "Premium " .. pass(acc).name
	end
	local pk = P.pack(pass(acc), tonumber(what))
	return pk and pk.name or "?"
end

-- a gift target by character name -> account id, name or nil, why
local function giftTarget(player, name)
	local guid, canonical = Chaos.findPlayer(tostring(name or ""))
	if not guid then
		return nil, "There is no character with that name."
	end
	local rows = Chaos.select(string.format("SELECT `account_id`, `group_id` FROM `players` WHERE `id` = %d", guid),
		{{"account_id", "n"}, {"group_id", "n"}})
	local r = rows[1]
	if not r then
		return nil, "There is no character with that name."
	end
	if r.account_id == player:getAccountId() then
		return nil, "That is a character of your own account: use Buy."
	end
	if r.group_id >= cfg.staffGroup then
		return nil, "Gifts cannot go to staff characters."
	end
	return r.account_id, canonical
end

-- a purchase in the pass window, for this account or (giftName) for another character's account. The price is what
-- the window showed (for a gift: what the other account still has to pay); a changed price is refused.
function SP.windowBuy(player, what, shownPrice, giftName)
	local account, targetName = player:getAccountId(), nil
	if giftName then
		local why
		account, why = giftTarget(player, giftName)
		if not account then
			return false, why
		end
		targetName = why
	end
	local acc = SP.account(account)
	local price, why = SP.offerPrice(acc, what)
	if not price then
		releaseIfOffline(account)
		return false, giftName and (why == "Owned." and ChaosI18n.msg("%s already has it.", targetName) or why) or why
	end
	if tonumber(shownPrice) ~= price then
		releaseIfOffline(account)
		return false, giftName and ChaosI18n.msg("The price is %d Chaos Coins for %s. Please confirm again.", price, targetName)
			or ChaosI18n.msg("The price is %d Chaos Coins. Please confirm again.", price)
	end
	local Shop = ChaosShop
	local have = Shop and Shop.getCoins and Shop.getCoins(player:getAccountId()) or 0
	if have < price then
		releaseIfOffline(account)
		return false, ChaosI18n.msg("You need %d Chaos Coins (you have %d).", price, have)
	end
	if not spendCoins(player:getAccountId(), price) then
		releaseIfOffline(account)
		return false, "Could not take the coins. Try again."
	end
	local title = offerName(acc, what) .. (what ~= "premium" and acc.cur.pack > 0 and " (upgrade)" or "")
	local ok, err
	if what == "premium" then
		ok, err = SP.grantPremium(account, player:getGuid(), price, giftName and "gift" or "window")
	else
		ok, err = SP.grantPack(account, player:getGuid(), tonumber(what), price, giftName and "gift" or "window")
	end
	if not ok then
		if price > 0 then
			Shop.addCoins(player:getAccountId(), price) -- refund
		end
		releaseIfOffline(account)
		return false, err
	end
	if giftName then
		title = title .. " (gift to " .. targetName .. ")"
		tellAccount(account, ChaosI18n.msg("%s gave your account %s.", player:getName(), offerName(acc, what)))
		logEvent(player:getAccountId(), player:getGuid(), acc.season, "gift", title)
	end
	shopHistory(player, title, price)
	releaseIfOffline(account)
	return true
end

-- the price another account pays for an offer (the pass window's gift box asks before confirming)
function SP.giftPrice(player, what, giftName)
	local account, name = giftTarget(player, giftName)
	if not account then
		return nil, name
	end
	local acc = SP.account(account)
	local price, why = SP.offerPrice(acc, what)
	releaseIfOffline(account)
	if not price then
		return nil, why == "Owned." and (name .. " already has it.") or why
	end
	return price, name
end

-- ---------------------------------------------------------------- store hook (unlock offers of seasonpass_store.lua)
local function storeTarget(acc, unlock)
	local p = pass(acc)
	if not p then
		return nil
	end
	if p.premium.unlock == unlock then
		return "premium"
	end
	for _, pk in ipairs(p.packs or {}) do
		if pk.unlock == unlock then
			return pk.id
		end
	end
	return nil
end

local function isOurUnlock(unlock)
	if type(unlock) ~= "string" then
		return false
	end
	for _, p in pairs(cfg.passes) do
		if p.premium.unlock == unlock then
			return true
		end
		for _, pk in ipairs(p.packs or {}) do
			if pk.unlock == unlock then
				return true
			end
		end
	end
	return false
end

function SP.storeCheck(player, offer)
	local acc = SP.account(player:getAccountId())
	local what = storeTarget(acc, offer.unlock)
	if not what or not SP.active() then
		return "This season's pass and packs can only be bought while the season runs."
	end
	local price, why = SP.offerPrice(acc, what)
	if not price then
		return why == "Owned." and "Your account already has the premium pass." or why
	end
	if price ~= offer.cost then
		return ChaosI18n.msg("Your account gets this for %d Chaos Coins (the difference to what it already owns): buy it in Adventure > Season Pass, Packs.",
			price)
	end
	return nil
end

function SP.storeDeliver(player, offer)
	local acc = SP.account(player:getAccountId())
	local what = storeTarget(acc, offer.unlock)
	if not what then
		return "This offer is not available."
	end
	local ok, err
	if what == "premium" then
		ok, err = SP.grantPremium(player:getAccountId(), player:getGuid(), offer.cost, "store")
	else
		ok, err = SP.grantPack(player:getAccountId(), player:getGuid(), what, offer.cost, "store")
	end
	return ok and true or (err or "Something went wrong. Your coins were refunded.")
end

function SP.installStoreHook()
	local S = ChaosShopServices
	if not S or not S.check or not S.deliver or S.seasonPassHooked == S.check then
		return
	end
	local check, deliver = S.check, S.deliver
	S.check = function(player, offer)
		if offer and offer.kind == "unlock" and isOurUnlock(offer.unlock) then
			return SP.storeCheck(player, offer)
		end
		return check(player, offer)
	end
	S.deliver = function(player, offer)
		if offer and offer.kind == "unlock" and isOurUnlock(offer.unlock) then
			local ok, res = pcall(SP.storeDeliver, player, offer)
			if not ok then
				log("store deliver failed: " .. tostring(res))
				return "Something went wrong. Your coins were refunded."
			end
			return res
		end
		return deliver(player, offer)
	end
	S.seasonPassHooked = S.check
end

-- ---------------------------------------------------------------- hooks into the other systems
local function playerOf(who)
	if type(who) == "userdata" then
		return who
	elseif type(who) == "table" and who.guid then
		return Player(tonumber(who.guid))
	elseif tonumber(who) then
		return Player(tonumber(who))
	end
	return nil
end

local BOARD_SOURCE = {bounty = "bounty", rift = "rift", goblin = "goblin", defender = "invasion"}

function SP.installHooks()
	-- wrapped once (a flag, as achievements.lua does): season.lua and guild.lua re-wrap whenever LB.record is not their
	-- own wrapper, so wrapping again on top of them would make them wrap again and count twice
	local LB = ChaosLeaderboard
	if LB and LB.record and not LB.seasonPassWrapped then
		LB.seasonPassWrapped = true
		local original = LB.record
		SP.wrappedRecord = function(board, who, value, mode)
			local entry = original(board, who, value, mode)
			local source = BOARD_SOURCE[board]
			if source then
				local ok, err = pcall(function()
					local p = playerOf(who)
					if p then
						SP.progress(p, source, source == "rift" and value or 1)
					end
				end)
				if not ok then
					log("leaderboard hook: " .. tostring(err))
				end
			end
			return entry
		end
		LB.record = SP.wrappedRecord
	end
	local B = ChaosBossPoints
	if B and B.grant and not B.seasonPassWrapped then
		B.seasonPassWrapped = true
		local original = B.grant
		SP.wrappedGrant = function(player, boss, quiet)
			local res = original(player, boss, quiet)
			if not quiet and player then
				local ok, err = pcall(SP.progress, player, "boss", 1)
				if not ok then
					log("boss hook: " .. tostring(err))
				end
			end
			return res
		end
		B.grant = SP.wrappedGrant
	end
	SP.installStoreHook()
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("seasonpass", function(player)
			return SP.titlesOf(player)
		end)
		if ChaosTitles.registerFrame then
			ChaosTitles.registerFrame("seasonpass", function(player)
				return SP.frameOf(player)
			end)
		end
	end
end
SP.installHooks()

local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	if source and source:isMonster() and SP.active() then
		local ok, err = pcall(function()
			local stage = Game.getExperienceStage and Game.getExperienceStage(player:getLevel()) or 1
			SP.progress(player, "exp", P.expUnits(rawExp or exp, stage, player:getLevel()))
		end)
		if not ok then
			log("experience: " .. tostring(err))
		end
	end
	return exp
end
xp:register()

local kill = CreatureEvent("ChaosSeasonPassKill")
function kill.onKill(creature, target)
	if creature and creature:isPlayer() and target and target:isMonster() and not target:getMaster() then
		-- pack combat (pace.lua): a paced monster counts 1 / its kill-goal factor (summed), so the kill tasks take as
		-- long as before
		local n = ChaosPace and ChaosPace.killCredit and ChaosPace.killCredit(creature, target, "pass") or 1
		local ok, err = true, nil
		if n > 0 then
			ok, err = pcall(SP.progress, creature, "kill", n)
		end
		if not ok then
			log("kill: " .. tostring(err))
		end
	end
	return true
end
kill:type("kill")
kill:register()

-- ---------------------------------------------------------------- window state
local function rewardView(r)
	if not r then
		return nil
	end
	local v = {kind = r.kind, text = P.rewardText(r)}
	if r.kind == "item" then
		local it = ItemType(r.id)
		v.item, v.count = it and it:getClientId() or 0, r.count
	elseif r.kind == "coins" then
		v.item, v.count = ItemType(24774):getClientId(), math.min(100, r.amount)
	elseif r.kind == "outfit" then
		v.look, v.addons = r.male, r.addons or 0
	elseif r.kind == "mount" then
		v.look = r.clientid
	elseif r.kind == "title" then
		v.color = r.color
	elseif r.kind == "transmog" and r.icon then
		local it = ItemType(r.icon)
		v.item, v.count = it and it:getClientId() or 0, 1
	end
	return v
end

local function challengeRows(acc, kind, period, map)
	local rows = {}
	for _, c in ipairs(P.challenges(cfg, acc.season, kind, period)) do
		rows[#rows + 1] = {key = c.key, text = c.text, target = c.target,
			progress = math.min(c.target, math.floor(map["ch:" .. c.key] or 0)), done = map["done:" .. c.key] and true or false,
			xp = kind == "daily" and cfg.challenges.dailyXp or cfg.challenges.weeklyXp}
	end
	return rows
end

function SP.stateOf(player)
	local acc = SP.account(player:getAccountId())
	local season, status = SP.shown()
	local p = pass(acc)
	if not season or not p then
		return {season = nil}
	end
	local t = now()
	local start, finish = ChaosSeason.times(season, overrides())
	local tier, into, need = P.tierOf(cfg, acc.xp)
	local data = {
		season = {id = season.id, name = season.name, tag = season.tag, status = status, pass = p.name,
			endsIn = status == "active" and finish - t or nil, startsIn = status == "upcoming" and start - t or nil,
			claimEndsIn = status == "grace" and finish + cfg.claimGraceDays * 86400 - t or nil},
		tier = tier, maxTier = cfg.maxTier, xp = acc.xp, into = into, need = need, premium = hasPremium(acc),
		claimed = {P.claimedString(acc.cur.claims[P.FREE], cfg.maxTier), P.claimedString(acc.cur.claims[P.PREMIUM], cfg.maxTier)},
		staff = staff(player), coins = ChaosShop and ChaosShop.getCoins and ChaosShop.getCoins(acc.id) or 0
	}
	if status == "active" then
		local today, week, day, wk = periodsOf(acc)
		data.daily = {resetIn = P.nextDay(t) - t, list = challengeRows(acc, "daily", day, today)}
		data.weekly = {resetIn = P.nextWeek(t) - t, list = challengeRows(acc, "weekly", wk, week)}
		local sources = {}
		for _, key in ipairs({"exp", "boss", "bounty", "rift", "goblin", "invasion"}) do
			local s = cfg.sources[key]
			-- cap: today's room with the banked days (cfg.bankDays) plus what today already took
			local used, days = capWindow(acc, today, "cap:" .. key)
			local done = today["cap:" .. key] or 0
			sources[#sources + 1] = {key = key, name = s.name, today = done, cap = done + P.sourceRoom(cfg, key, used, days)}
		end
		data.sources = sources
	end
	local offers = {}
	local premiumPrice, premiumWhy = SP.offerPrice(acc, "premium")
	local icon = ItemType(p.premium.icon or 26031)
	offers[#offers + 1] = {what = "premium", name = "Premium " .. p.name, price = premiumPrice, why = premiumWhy,
		owned = hasPremium(acc), full = p.premium.price, text = p.premium.description, item = icon and icon:getClientId() or nil}
	for _, pk in ipairs(p.packs or {}) do
		local price, why = SP.offerPrice(acc, pk.id)
		local contents = {}
		local lower = P.pack(p, pk.id - 1)
		if lower then
			contents[1] = "Everything of the " .. lower.name
		end
		for _, r in ipairs(pk.rewards) do
			contents[#contents + 1] = P.rewardText(r)
		end
		offers[#offers + 1] = {what = pk.id, name = pk.name, price = price, why = why, owned = acc.cur.pack >= pk.id,
			full = pk.price, look = pk.look, contents = contents}
	end
	data.offers = offers
	local frame
	for _, r in ipairs(entitlements(acc)) do
		if r.kind == "frame" then
			frame = r.name
		end
	end
	data.frame = frame and {name = frame, on = player:getStorageValue(cfg.storage.frameOff) ~= 1} or nil
	return data
end

function SP.sendState(player, open)
	local data = SP.stateOf(player)
	data.open = open and true or false
	Chaos.send(player, OPCODE, "state", data)
end

function SP.sendTiers(player, seasonId)
	local p = cfg.passes[tonumber(seasonId) or -1]
	if not p then
		return
	end
	local CHUNK = 10
	for first = 1, #p.tiers, CHUNK do
		local rows = {}
		for t = first, math.min(#p.tiers, first + CHUNK - 1) do
			rows[#rows + 1] = {tier = t, cost = P.tierCost(cfg, t), free = rewardView(p.tiers[t][1]),
				premium = rewardView(p.tiers[t][2])}
		end
		Chaos.send(player, OPCODE, "tiers", {season = tonumber(seasonId), first = first, last = first + #rows - 1,
			total = #p.tiers, rows = rows})
	end
end

local function notice(player, text)
	if text then
		Chaos.send(player, OPCODE, "notice", {text = Chaos.t(player, text)})
	end
end

-- ---------------------------------------------------------------- events
local ext = CreatureEvent("ChaosSeasonPassExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local limited = ChaosRateLimit and not ChaosRateLimit.allow(player, "seasonpass." .. tostring(msg.action), 300)
	if limited then
		return
	end
	if msg.action == "open" then
		SP.sendState(player, true)
	elseif msg.action == "tiers" then
		SP.sendTiers(player, data.season)
	elseif msg.action == "claim" then
		local ok, why = SP.claim(player, Chaos.toInt(data.tier, 1, cfg.maxTier), Chaos.toInt(data.track, 0, 1))
		if not ok then
			notice(player, why)
		end
		SP.sendState(player, false)
	elseif msg.action == "claimAll" then
		local got, why = SP.claimAll(player)
		if got == 0 then
			notice(player, why or "Nothing to claim.")
		elseif why then
			-- no room, or items a season character cannot claim while the season runs: they wait
			notice(player, why:find("room", 1, true) and Chaos.t(player, "%s The other items wait for you.", Chaos.t(player, why)) or why)
		end
		SP.sendState(player, false)
	elseif msg.action == "buy" then
		local what = data.what == "premium" and "premium" or Chaos.toInt(data.what, 1, 9)
		local gift = type(data.gift) == "string" and data.gift ~= "" and data.gift or nil
		local ok, why = false, "Unknown offer."
		if what then
			ok, why = SP.windowBuy(player, what, data.price, gift)
		end
		notice(player, ok and (gift and "Gift sent." or "Purchase complete.") or why)
		SP.sendState(player, false)
	elseif msg.action == "giftPrice" then
		local what = data.what == "premium" and "premium" or Chaos.toInt(data.what, 1, 9)
		local price, name = SP.giftPrice(player, what or 0, type(data.gift) == "string" and data.gift or "")
		if price then
			Chaos.send(player, OPCODE, "giftPrice", {what = what, name = name, price = price})
		else
			notice(player, name)
		end
	elseif msg.action == "frame" then
		player:setStorageValue(cfg.storage.frameOff, data.on == false and 1 or 0)
		if ChaosNameplate and ChaosNameplate.refresh then
			pcall(ChaosNameplate.refresh, player)
		end
		SP.sendState(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosSeasonPassLogin")
function login.onLogin(player)
	player:registerEvent("ChaosSeasonPassExtended")
	player:registerEvent("ChaosSeasonPassKill")
	SP.account(player:getAccountId(), not SP.acc[player:getAccountId()])
	addEvent(function(cid)
		local p = Player(cid)
		if not p then
			return
		end
		SP.deliverCosmetics(p)
		local acc = SP.account(p:getAccountId())
		local pa = pass(acc)
		if pa and SP.active() then
			SP.claimPremiumBacklog(p:getAccountId()) -- a premium pass given while the account was offline
			local n = #P.claimable(pa, viewOf(acc, true))
			if n > 0 then
				p:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(p, "%s: %d reward%s to claim in Adventure > Season Pass.", pa.name,
					n, n == 1 and "" or "s"))
			end
		end
		SP.sendState(p, false)
	end, 2500, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosSeasonPassLogout")
function logout.onLogout(player)
	local account = player:getAccountId()
	local acc = SP.acc[account]
	if acc then
		SP.flush(acc)
		local others = 0
		for _, p in ipairs(accountPlayers(account)) do
			if p:getId() ~= player:getId() then
				others = others + 1
			end
		end
		if others == 0 then
			SP.acc[account] = nil
		end
	end
	return true
end
logout:type("logout")
logout:register()

local startup = GlobalEvent("ChaosSeasonPassStartup")
function startup.onStartup()
	for _, q in ipairs(DDL) do
		db.query(q)
	end
	SP.installHooks()
	if ChaosSeason and ChaosSeason.loadOverrides then
		ChaosSeason.loadOverrides() -- /season start|end rows, also when season.lua's own startup runs after this one
	end
	for _, problem in ipairs(P.validate(cfg)) do
		log("config: " .. problem)
	end
	local s = SP.active()
	log(s and (cfg.passes[s.id].name .. " running (" .. s.name .. ")") or "no season pass running")
	return true
end
startup:register()

local think = GlobalEvent("ChaosSeasonPassFlush")
function think.onThink(interval)
	SP.installHooks() -- again after a /reload of the hooked scripts
	for _, acc in pairs(SP.acc) do
		SP.flush(acc)
	end
	return true
end
think:interval(cfg.flushSeconds * 1000)
think:register()

local shutdown = GlobalEvent("ChaosSeasonPassShutdown")
function shutdown.onShutdown()
	for _, acc in pairs(SP.acc) do
		SP.flush(acc)
	end
	return true
end
shutdown:register()

-- ---------------------------------------------------------------- staff command
local talk = TalkAction("/seasonpass")
function talk.onSay(player, words, param)
	if player:getAccountType() < (ACCOUNT_TYPE_GOD or 5) then
		return true
	end
	local cmd, rest = (param or ""):match("^%s*(%S*)%s*(.-)%s*$")
	if cmd == "xp" then
		local amount, name = rest:match("^(%d+)%s*,?%s*(.*)$")
		local target = (name and name ~= "") and Player(name) or player
		if not amount or not target then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "/seasonpass xp <amount> [character online]")
			return false
		end
		local acc = SP.account(target:getAccountId())
		if not SP.active() or not acc.season then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "No season pass is running.")
			return false
		end
		SP.addXp(acc, tonumber(amount), "admin " .. player:getName())
		SP.flush(acc)
		logEvent(acc.id, target:getGuid(), acc.season, "admin", "xp " .. amount .. " by " .. player:getName())
		SP.sendState(target, false)
	end
	local acc = SP.account(player:getAccountId())
	local s, status = SP.shown()
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Season pass: %s (%s); your account: %d XP, tier %d, premium %s, pack %d.",
		s and s.name or "none", tostring(status), acc.xp or 0, (P.tierOf(cfg, acc.xp or 0)), tostring(hasPremium(acc)), acc.cur.pack))
	return false
end
talk:separator(" ")
talk:register()
