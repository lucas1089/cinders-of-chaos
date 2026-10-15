-- Time-friendly progression (catchup_core.lua rules, catchup_config.lua numbers; server/README.md "Time-friendly
-- progression (catchup)"). The engine glue:
--   login             the rested pool grows by the offline time (storage), the account's returning boost is started
--                     or read (table chaos_catchup), the account's best level is read; short messages say what holds
--   EventCallback     onGainExperience at cfg.xpIndex: stamina factor, returning, alt catch-up and rested experience
--   advance           a new best level of the account is remembered (the alts' bonus shrinks)
--   logout            the pool goes back to its storage
-- API for other scripts (all guarded by their callers):
--   ChaosCatchup.lootMult(player)          Chaos loot layer factor (loot.lua): stamina x returning
--   ChaosCatchup.staminaLootMult(player)   the stock loot pass (tools/patch_base_events.py step 16)
--   ChaosCatchup.offlineStaminaMult(player) offline stamina regeneration (tools/patch_base_events.py step 17)
--   ChaosCatchup.tokenMult(player)         token drop chance factor (factions.lua; other token systems may ask)
--   ChaosCatchup.isReturning(player)       the returning boost holds
--   ChaosCatchup.buffItem(player, part)    the buff bar (data/lib/chaos_buffs.lua source "catchup")
-- The welcome back message points at the Next Goals panel when it is loaded (ChaosGoals, goals.lua) and asks it for a
-- hint when it defines ChaosGoals.hint(player, why) (why = "returning").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosCatchupCore or not ChaosCatchupCore.xpGain then
	dofile("data/scripts/chaos/catchup_core.lua")
end
ChaosCatchupConfig = dofile("data/scripts/chaos/catchup_config.lua")

local K = ChaosCatchupCore
local function C()
	return ChaosCatchupConfig
end

ChaosCatchup = ChaosCatchup or {}
local CU = ChaosCatchup
CU.players = CU.players or {} -- player id -> {pool, account, season}
CU.accounts = CU.accounts or {} -- account id -> {untilAt, best}

local MSG = MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR

local function now()
	return os.time()
end

local function seasonal(player)
	local S = ChaosSeason
	if not (S and S.realmOf) then
		return false
	end
	local ok, realm = pcall(S.realmOf, player)
	return ok and (tonumber(realm) or 0) > 0
end

local function seasonalGuid(guid)
	local S = ChaosSeason
	if not (S and S.realmOfGuid) then
		return false
	end
	local ok, realm = pcall(S.realmOfGuid, guid)
	return ok and (tonumber(realm) or 0) > 0
end

-- ---------------------------------------------------------------- the account table
local tableReady = false
function CU.ensureTable()
	if tableReady then
		return true
	end
	if not db or not db.query then
		return false
	end
	tableReady = db.query("CREATE TABLE IF NOT EXISTS `" .. C().table .. "` (`account_id` int(11) NOT NULL, " ..
		"`returning_until` int(10) unsigned NOT NULL DEFAULT 0, `returned_at` int(10) unsigned NOT NULL DEFAULT 0, " ..
		"PRIMARY KEY (`account_id`)) ENGINE=InnoDB DEFAULT CHARSET=utf8") and true or false
	return tableReady
end

-- the latest logout of any character of the account (0 = none ever logged out)
local function accountLastSeen(account, selfGuid)
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == account and p:getGuid() ~= selfGuid then
			return now() -- another character is online right now
		end
	end
	local rows = Chaos.select(string.format("SELECT MAX(`lastlogout`) AS `t` FROM `players` WHERE `account_id` = %d",
		account), {{"t", "n"}})
	return rows[1] and tonumber(rows[1].t) or 0
end

local function accountBest(account)
	local best = 0
	for _, r in ipairs(Chaos.select(string.format("SELECT `id`, `level` FROM `players` WHERE `account_id` = %d", account),
			{{"id", "n"}, {"level", "n"}})) do
		if (r.level or 0) > best and not seasonalGuid(r.id) then
			best = r.level
		end
	end
	return best
end

local function readUntil(account)
	if not CU.ensureTable() then
		return 0
	end
	local rows = Chaos.select(string.format("SELECT `returning_until` FROM `%s` WHERE `account_id` = %d", C().table,
		account), {{"returning_until", "n"}})
	return rows[1] and tonumber(rows[1].returning_until) or 0
end

local function writeUntil(account, untilAt)
	if not CU.ensureTable() then
		return
	end
	db.query(string.format("INSERT INTO `%s` (`account_id`, `returning_until`, `returned_at`) VALUES (%d, %d, %d) ON " ..
		"DUPLICATE KEY UPDATE `returning_until` = VALUES(`returning_until`), `returned_at` = VALUES(`returned_at`)",
		C().table, account, untilAt, now()))
end

-- ---------------------------------------------------------------- state
local function stateOf(player)
	local st = CU.players[player:getId()]
	if st then
		return st
	end
	local pool = player:getStorageValue(C().storage.rested)
	st = {pool = math.max(0, (tonumber(pool) or 0)) / 100, account = player:getAccountId(), season = seasonal(player)}
	CU.players[player:getId()] = st
	return st
end

local function accountOf(account)
	return CU.accounts[account] or {untilAt = 0, best = 0}
end

local function facts(player)
	local st = stateOf(player)
	local a = accountOf(st.account)
	return {level = player:getLevel(), stamina = player:getStamina(), pool = st.pool, best = a.best,
		returning = (a.untilAt or 0) > now(), season = st.season}
end

local function savePool(player, st)
	player:setStorageValue(C().storage.rested, math.floor((st.pool or 0) * 100 + 0.5))
end

-- ---------------------------------------------------------------- API
function CU.lootMult(player)
	return K.lootMult(C(), facts(player))
end

function CU.staminaLootMult(player)
	if C().enabled == false then
		return K.staminaLow(C(), player:getStamina()) and 0 or 1
	end
	return K.staminaLootMult(C(), player:getStamina())
end

function CU.offlineStaminaMult(player)
	if C().enabled == false then
		return 1
	end
	return math.max(1, tonumber(C().stamina.offlineMult) or 1)
end

function CU.tokenMult(player)
	return K.tokenMult(C(), facts(player))
end

function CU.isReturning(player)
	local f = facts(player)
	return f.returning and not (f.season and not C().seasonCharacters)
end

function CU.restedMinutes(player)
	return stateOf(player).pool or 0
end

-- the Rested Vial (Candlemarks shop: candlemarks_config.lua call {"ChaosRested", "addVials", n}): + vialMinutes each,
-- never past the cap. false (the shop gives the marks back) when nothing fits or the character does not rest
function CU.addVials(player, n)
	local c = C()
	local st = stateOf(player)
	if c.enabled == false or c.rested.enabled == false or (st.season and not c.seasonCharacters) then
		return false, "Season characters do not rest."
	end
	local pool, added = K.addVials(c, st.pool, n)
	if added < 1 then
		return false, "Your rest is already full."
	end
	st.pool = pool
	savePool(player, st)
	player:sendTextMessage(MSG, Chaos.t(player, "Rested Vial: +%d minutes of rested hunting (%d in all).",
		math.floor(added + 0.5), math.floor(pool)))
	return true
end
ChaosRested = ChaosRested or {}
ChaosRested.addVials = CU.addVials

-- the buff bar: part "rested" | "returning" | "alt" | "low" -> {name, desc, leftMs, stacks} or nil
function CU.buffItem(player, part)
	local c = C()
	if c.enabled == false then
		return nil
	end
	local f = facts(player)
	local own = not (f.season and not c.seasonCharacters)
	if part == "low" then
		if K.staminaLow(c, f.stamina) then
			return {desc = string.format("Below %d hours of stamina: %d%% experience and %d%% loot. Stamina comes back "
				.. "faster while you are offline.", math.floor(c.stamina.lowAt / 60), math.floor(c.stamina.xpMult * 100 + 0.5),
				math.floor(c.stamina.lootMult * 100 + 0.5))}
		end
	elseif part == "rested" then
		local minutes = math.floor(f.pool or 0)
		if own and minutes >= 1 and c.rested.enabled ~= false then
			return {stacks = minutes, desc = string.format("+%d%% experience from monsters until your rest is spent: about "
				.. "%d minutes of hunting left.", c.rested.bonusPct, minutes)}
		end
	elseif part == "returning" then
		local a = accountOf(stateOf(player).account)
		if own and (a.untilAt or 0) > now() then
			return {leftMs = (a.untilAt - now()) * 1000, desc = string.format("Welcome back: +%d%% experience, +%d%% loot "
				.. "and +%d%% token drops.", c.returning.xpPct, c.returning.lootPct, c.returning.tokenPct)}
		end
	elseif part == "alt" then
		local pct = own and K.altPct(c, f.level, f.best) or 0
		if pct >= 1 then
			return {stacks = math.floor(pct), desc = string.format("+%d%% experience from monsters: your account's best "
				.. "character is level %d. The bonus shrinks as you get close.", math.floor(pct), f.best)}
		end
	end
	return nil
end

-- ---------------------------------------------------------------- login, advance, logout
-- the Next Goals panel (goals.lua, global ChaosGoals; ChaosNextGoals is accepted too): asked for a hint when it has one
local function nextGoalsHint(player)
	local G = ChaosNextGoals or ChaosGoals
	if not G then
		return
	end
	if G.hint then
		pcall(G.hint, player, "returning")
	end
	player:sendTextMessage(MSG, Chaos.t(player, "Not sure where to start? Open Next Goals in the top menu."))
end

function CU.onLogin(player)
	local c = C()
	if c.enabled == false then
		return
	end
	local st = stateOf(player)
	local t = now()
	local lastLogout = tonumber(player.getLastLogout and player:getLastLogout() or 0) or 0
	local own = not (st.season and not c.seasonCharacters)
	-- the account: returning boost and best level
	local acc = CU.accounts[st.account]
	if not acc then
		acc = {untilAt = readUntil(st.account), best = accountBest(st.account)}
		local lastSeen = accountLastSeen(st.account, player:getGuid())
		if K.isReturning(c, lastSeen, t) and acc.untilAt <= t then
			acc.untilAt = K.returningUntil(c, t)
			writeUntil(st.account, acc.untilAt)
		end
		CU.accounts[st.account] = acc
	end
	if not st.season and player:getLevel() > (acc.best or 0) then
		acc.best = player:getLevel()
	end
	if not own then
		return
	end
	-- the rested pool
	if lastLogout > 0 then
		local before = st.pool
		st.pool = K.restedAfter(c, st.pool, t - lastLogout)
		savePool(player, st)
		if math.floor(st.pool) >= 1 and st.pool > before then
			player:sendTextMessage(MSG, Chaos.t(player, "You are rested: +%d%% experience from monsters for about %d minutes of hunting.", c.rested.bonusPct, math.floor(st.pool)))
		end
	end
	-- the welcome back, once per boost and character
	if (acc.untilAt or 0) > t and player:getStorageValue(c.storage.returningSeen) ~= acc.untilAt then
		player:setStorageValue(c.storage.returningSeen, acc.untilAt)
		player:sendTextMessage(MSG, Chaos.t(player, "Welcome back! For %d days: +%d%% experience, +%d%% loot and +%d%% token drops.", c.returning.durationDays, c.returning.xpPct, c.returning.lootPct, c.returning.tokenPct))
		nextGoalsHint(player)
	end
	local pct = K.altPct(c, player:getLevel(), acc.best)
	if pct >= 1 then
		player:sendTextMessage(MSG, Chaos.t(player, "Catch-up: +%d%% experience from monsters until you near level %d, your account's best.", math.floor(pct), acc.best))
	end
end

-- once a day at most: what low stamina does now
local function lowNotice(player)
	local c = C()
	local day = tonumber(os.date("%Y%m%d", now()))
	if player:getStorageValue(c.storage.lowNotice) == day then
		return
	end
	player:setStorageValue(c.storage.lowNotice, day)
	player:sendTextMessage(MSG, Chaos.t(player, "Your stamina is below %d hours: monsters give %d%% experience and %d%% loot. Stamina comes back faster while you are offline.", math.floor(c.stamina.lowAt / 60),
		math.floor(c.stamina.xpMult * 100 + 0.5), math.floor(c.stamina.lootMult * 100 + 0.5)))
end

function CU.onGainExperience(player, source, exp)
	if not source or not source.isMonster or not source:isMonster() or (tonumber(exp) or 0) <= 0 then
		return exp
	end
	local c = C()
	if c.enabled == false then
		return exp
	end
	local f = facts(player)
	if K.staminaLow(c, f.stamina) then
		lowNotice(player)
	end
	f.xpPerMin = K.xpPerMinute(c, f.level)
	local out, spent = K.xpGain(c, exp, f)
	if spent > 0 then
		local st = stateOf(player)
		st.pool = math.max(0, st.pool - spent)
		savePool(player, st)
	end
	return out
end

function CU.onAdvance(player, newLevel)
	local st = stateOf(player)
	if st.season then
		return
	end
	local acc = CU.accounts[st.account]
	if acc and (tonumber(newLevel) or 0) > (acc.best or 0) then
		acc.best = newLevel
	end
end

function CU.onLogout(player)
	local st = CU.players[player:getId()]
	if st then
		savePool(player, st)
		CU.players[player:getId()] = nil
	end
	-- the account cache goes when its last character leaves (the next login reads it again)
	local account = player:getAccountId()
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == account and p:getId() ~= player:getId() then
			return
		end
	end
	CU.accounts[account] = nil
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosCatchupLogin")
function login.onLogin(player)
	player:registerEvent("ChaosCatchupLogout")
	player:registerEvent("ChaosCatchupAdvance")
	local ok, err = pcall(CU.onLogin, player)
	if not ok then
		print("[Chaos catchup] login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosCatchupLogout")
function logout.onLogout(player)
	pcall(CU.onLogout, player)
	return true
end
logout:type("logout")
logout:register()

local advance = CreatureEvent("ChaosCatchupAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL then
		pcall(CU.onAdvance, player, newLevel)
	end
	return true
end
advance:type("advance")
advance:register()

local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	local ok, out = pcall(CU.onGainExperience, player, source, exp)
	if ok and tonumber(out) then
		return out
	end
	return exp
end
xp:register(C().xpIndex or 87)
