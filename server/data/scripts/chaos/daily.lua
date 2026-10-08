-- game_daily (extended opcode 207): daily reward, login streaks and the order of the windows that open at login
--
-- Client contract (client/overlay/modules/game_daily/daily.lua):
--   server -> client  {"action":"OpenDailyWindow",
--                      "data":{"Day":d, "TakenReward":0|1, "NextIn":seconds,
--                              "DAILY_REWARDS":[{"ClientID":id,"Count":n} x7],
--                              -- login streaks (an older client ignores these):
--                              "Streak":n, "Best":n, "Grace":n, "GraceMax":n, "GraceUse":n, "Broken":0|1,
--                              "Title":"..."|nil, "Next":{"Days":n, "In":n, "Reward":"...", "Title":"..."|nil}|nil,
--                              "Login":1|nil (opened by itself at login: the client waits for other login windows)}}
--   client -> server  {"action":"calim","data":v}      ("calim" is the client's spelling)
--   client -> server  {"action":"open"}                (window opened from the menu: send the data)
--   client -> server  {"action":"closed"}              (window closed: the next login window may open)
--
-- Quirks of the shipped client that this file compensates for:
--   * the client does Day = Day + 2 on receipt, so we send Day = slot - 2.
--   * the client answers a claim with v = map[slot] where map = {6,7,1,2,3,4,5}; we invert
--     that to get the slot back: slot = ((v + 1) % 7) + 1.
--   * DAILY_REWARDS[i] is drawn in slot i, so it is sent in plain slot order 1..7.
--
-- State: one row per ACCOUNT in chaos_daily_account (sql/chaos.sql), cached in memory and written through: the
-- streak (consecutive claim days), the best streak, grace charges and the day of the last claim. One claim a day per
-- account, whichever character claims it. The 7-slot cycle follows the streak (day 8 is slot 1 again). The first
-- login of an account after the update builds the row from the old per-character storages (dailyStreakDay /
-- dailyLastClaim) of all its characters, the best one (daily_core.lua D.migrate). Rules: daily_core.lua; settings:
-- Chaos.daily (rewards, chaos_constants.lua) and daily_config.lua (milestones, grace, login order).
--
-- Staff: /daily (state of the own account), /daily shift <days> (move the daily clock, tests; 0 = real time),
-- /daily set <streak> [grace] (set the own account's streak as if it was claimed yesterday).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/daily_core.lua")

Chaos.dailyStreak = dofile("data/scripts/chaos/daily_config.lua")
local OPCODE = ChaosOpcodes.daily
local cfg = Chaos.daily
local SC = Chaos.dailyStreak
local S = Chaos.storage
local DC = ChaosDailyCore

ChaosDaily = ChaosDaily or {}
local DY = ChaosDaily
DY.accounts = DY.accounts or {} -- account id -> record (see daily_core.lua)
DY.offsetDays = DY.offsetDays or 0 -- staff test clock (/daily shift)

local function itemName(id)
	return ItemType(id):getName()
end

function DY.today()
	return Chaos.dayKey(os.time() + DY.offsetDays * 86400)
end

-- ---------------------------------------------------------------- login windows (the one place for the order)
-- Windows that open by themselves at login go through this queue, so they never stack on top of each other:
--   ChaosLoginWindows.register(key, order, wants, open)
--       order  lower opens first (Chaos.dailyStreak.loginOrder: daily = 20; put another window before it with less)
--       wants(player) -> true when the window should open by itself at this login
--       open(player)  sends it (mark it as a login opening, e.g. "Login":1, so the client waits for modal dialogs)
--   ChaosLoginWindows.closed(player, key)
--       call it when the client reports that window closed: the next window of the queue is sent
-- At login, after Chaos.daily.openDelayMs, the wanted windows are sent one at a time in order. If the client never
-- reports a window closed, the next one is sent after Chaos.dailyStreak.loginWindowMaxWaitMs.
-- The client waits too: an auto-opened window is shown only when no server modal dialog (the new-player welcome,
-- the tutorial) is on screen (client game_daily daily.lua, waitForOtherWindows).
ChaosLoginWindows = ChaosLoginWindows or {entries = {}, state = {}}
local LW = ChaosLoginWindows

function LW.register(key, order, wants, open)
	for i = #LW.entries, 1, -1 do
		if LW.entries[i].key == key then
			table.remove(LW.entries, i)
		end
	end
	LW.entries[#LW.entries + 1] = {key = key, order = order or 50, wants = wants, open = open}
end

local function entryOf(key)
	for _, e in ipairs(LW.entries) do
		if e.key == key then
			return e
		end
	end
	return nil
end

function LW.next(player)
	local pid = player:getId()
	local st = LW.state[pid]
	if not st then
		return
	end
	local key = table.remove(st.queue, 1)
	if not key then
		LW.state[pid] = nil
		return
	end
	st.current = key
	st.token = st.token + 1
	local token = st.token
	local e = entryOf(key)
	local ok, err = pcall(e.open, player)
	if not ok then
		print("[Chaos login windows] " .. key .. ": " .. tostring(err))
	end
	addEvent(function()
		local p = Player(pid)
		local s = LW.state[pid]
		if p and s and s.token == token then
			LW.next(p)
		end
	end, SC.loginWindowMaxWaitMs or 90000)
end

function LW.closed(player, key)
	local st = LW.state[player:getId()]
	if st and st.current == key then
		LW.next(player)
	end
end

function LW.start(player)
	addEvent(function(pid)
		local p = Player(pid)
		if not p then
			return
		end
		local wanted = {}
		for _, e in ipairs(LW.entries) do
			local ok, w = pcall(e.wants, p)
			if ok and w then
				wanted[e.key] = true
			end
		end
		LW.state[pid] = {queue = DC.loginOrder(LW.entries, wanted), token = 0}
		LW.next(p)
	end, cfg.openDelayMs or 3000, player:getId())
end

-- ---------------------------------------------------------------- account record
local warned = false
local function save(accountId, rec)
	local ok = db.query(string.format("INSERT INTO `%s` (`account_id`, `streak`, `best`, `grace`, `last_claim`, `claims`) " ..
		"VALUES (%d, %d, %d, %d, %d, %d) ON DUPLICATE KEY UPDATE `streak` = VALUES(`streak`), `best` = VALUES(`best`), " ..
		"`grace` = VALUES(`grace`), `last_claim` = VALUES(`last_claim`), `claims` = VALUES(`claims`)",
		SC.table, accountId, rec.streak, rec.best, rec.grace, rec.last, rec.claims))
	if not ok and not warned then
		warned = true
		print("[Chaos daily] could not write " .. SC.table .. ": run server/sql/chaos.sql (streaks are kept in memory only)")
	end
end

-- the old per-character storages of every character of the account (online characters: their live values)
local function oldStorages(player)
	local accountId = player:getAccountId()
	local byPlayer = {}
	local rows = Chaos.select(string.format("SELECT `ps`.`player_id`, `ps`.`key`, `ps`.`value` FROM `player_storage` `ps` " ..
		"INNER JOIN `players` `p` ON `p`.`id` = `ps`.`player_id` WHERE `p`.`account_id` = %d AND `ps`.`key` IN (%d, %d)",
		accountId, S.dailyStreakDay, S.dailyLastClaim), {{"player_id", "n"}, {"key", "n"}, {"value", "n"}})
	for _, r in ipairs(rows) do
		local e = byPlayer[r.player_id] or {}
		if r.key == S.dailyStreakDay then
			e.slot = r.value
		else
			e.last = r.value
		end
		byPlayer[r.player_id] = e
	end
	for _, p in ipairs(Game.getPlayers()) do
		if p:getAccountId() == accountId then
			byPlayer[p:getGuid()] = {slot = p:getStorageValue(S.dailyStreakDay), last = p:getStorageValue(S.dailyLastClaim)}
		end
	end
	local list = {}
	for _, e in pairs(byPlayer) do
		list[#list + 1] = e
	end
	return list
end

function DY.record(player)
	local accountId = player:getAccountId()
	local rec = DY.accounts[accountId]
	if rec then
		return rec
	end
	local rows = Chaos.select(string.format("SELECT `streak`, `best`, `grace`, `last_claim`, `claims` FROM `%s` " ..
		"WHERE `account_id` = %d", SC.table, accountId),
		{{"streak", "n"}, {"best", "n"}, {"grace", "n"}, {"last_claim", "n"}, {"claims", "n"}})
	if rows[1] then
		local r = rows[1]
		rec = {streak = r.streak, best = r.best, grace = r.grace, last = r.last_claim, claims = r.claims}
	else
		rec = DC.migrate(oldStorages(player))
		save(accountId, rec)
	end
	DY.accounts[accountId] = rec
	return rec
end

local function getState(player)
	local rec = DY.record(player)
	return DC.view(rec, DY.today(), SC), rec
end

-- ---------------------------------------------------------------- window
local function sendWindow(player, login)
	local v, rec = getState(player)
	local rewards = {}
	for i = 1, 7 do
		local reward = cfg.rewards[i]
		local itemType = ItemType(reward.itemId)
		rewards[i] = {ClientID = itemType:getClientId(), Count = reward.count}
	end
	local now = os.time()
	local d = os.date("*t", now)
	local midnight = os.time({year = d.year, month = d.month, day = d.day + 1, hour = 0, min = 0, sec = 0})
	local nextM = DC.nextMilestone(SC, v.achieved)
	local title = DC.titleFor(SC, rec.best)
	Chaos.send(player, OPCODE, "OpenDailyWindow", {
		Day = v.slot - 2,
		TakenReward = v.taken and 1 or 0,
		NextIn = math.max(0, midnight - now), -- seconds until the server day rolls over
		DAILY_REWARDS = rewards,
		Streak = v.taken and v.next or v.streak,
		Best = rec.best,
		Grace = rec.grace,
		GraceMax = SC.graceMax,
		GraceUse = v.graceUse,
		Broken = v.broken and 1 or 0,
		Title = title,
		Next = nextM and {Days = nextM.days, In = nextM.days - v.achieved, Reward = DC.milestoneText(nextM, itemName),
			Title = nextM.title} or nil,
		Login = login and 1 or nil
	})
end
DY.sendWindow = sendWindow

local function claim(player, value)
	local v = Chaos.toInt(value, 1, 7)
	if not v then
		return
	end
	local claimedSlot = ((v + 1) % 7) + 1
	local state, rec = getState(player)

	if state.taken then
		player:sendCancelMessage("Your account already collected today's daily reward.")
		sendWindow(player)
		return
	end
	if claimedSlot ~= state.slot then
		-- stale window (e.g. opened before midnight): resync instead of paying the wrong day
		sendWindow(player)
		return
	end

	local today = DY.today()
	local newRec, res = DC.claim(rec, today, SC)
	local reward = cfg.rewards[res.slot]
	local list = {reward}
	if res.week then
		for _, bonus in ipairs(cfg.weekBonus or {}) do
			list[#list + 1] = bonus
		end
	end
	if res.milestone then
		for _, it in ipairs(res.milestone.items or {}) do
			list[#list + 1] = it
		end
	end
	-- all or nothing: if any stack does not fit, take back what was already given
	local givenList, ok = {}, true
	for _, r in ipairs(list) do
		local given = Chaos.giveItem(player, r.itemId, r.count)
		givenList[#givenList + 1] = {itemId = r.itemId, given = given}
		if given < r.count then
			ok = false
			break
		end
	end
	if not ok then
		for _, g in ipairs(givenList) do
			if g.given > 0 then
				player:removeItem(g.itemId, g.given)
			end
		end
		player:sendCancelMessage("You do not have enough room or capacity for the reward.")
		sendWindow(player)
		return
	end

	local accountId = player:getAccountId()
	DY.accounts[accountId] = newRec
	save(accountId, newRec)
	-- the old per-character storages, kept in step (nothing reads them any more)
	player:setStorageValue(S.dailyStreakDay, res.slot)
	player:setStorageValue(S.dailyLastClaim, today)

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Daily reward (day %d, streak %d): %dx %s.", res.slot,
		res.streak, reward.count, itemName(reward.itemId)))
	if res.week and #(cfg.weekBonus or {}) > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Week completed! Bonus reward collected.")
	end
	if res.graceUsed > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("A grace charge kept your streak alive (%d left).",
			newRec.grace))
	end
	if res.graceGained > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("You earned a grace charge (%d of %d): a missed day " ..
			"will not break your streak.", newRec.grace, SC.graceMax))
	end
	local m = res.milestone
	if m then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Login streak of %d days! Milestone reward: %s.", m.days,
			DC.milestoneText(m, itemName)))
		if m.title and (rec.best or 0) < m.days then
			Game.broadcastMessage(string.format("%s reached a login streak of %d days and earned the title %s!",
				player:getName(), m.days, m.title), MESSAGE_EVENT_ADVANCE)
		end
		player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_RED)
	end
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	sendWindow(player)
end

-- ---------------------------------------------------------------- the daily window in the login order
LW.register("daily", SC.loginOrder and SC.loginOrder.daily or 20, function(player)
	if not cfg.openOnLogin then
		return false
	end
	local v = getState(player)
	return not v.taken
end, function(player)
	sendWindow(player, true)
end)

-- ---------------------------------------------------------------- look text: the login streak title
local look = EventCallback
look.onLook = function(self, thing, position, distance, description)
	if thing and thing:isPlayer() then
		local rec = DY.accounts[thing:getAccountId()]
		local title, days = DC.titleFor(SC, rec and rec.best or 0)
		if title then
			local pronoun = thing:getId() == self:getId() and "You" or (thing:getSex() == PLAYERSEX_FEMALE and "She" or "He")
			description = (description or "") .. "\n" .. DC.lookText(title, days, pronoun)
		end
	end
	return description
end
look:register(101) -- after the leaderboard titles (100)

-- ---------------------------------------------------------------- events
local LoginEvent = CreatureEvent("ChaosDailyLogin")

function LoginEvent.onLogin(player)
	player:registerEvent("ChaosDailyExtended")
	player:registerEvent("ChaosDailyLogout")
	local ok, err = pcall(DY.record, player)
	if not ok then
		print("[Chaos daily] " .. tostring(err))
	end
	LW.start(player)
	return true
end

local LogoutEvent = CreatureEvent("ChaosDailyLogout")
function LogoutEvent.onLogout(player)
	LW.state[player:getId()] = nil
	return true
end

local ExtendedEvent = CreatureEvent("ChaosDailyExtended")

function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if msg.action == "calim" then
		claim(player, msg.data)
	elseif msg.action == "open" then
		sendWindow(player)
	elseif msg.action == "closed" then
		LW.closed(player, "daily")
	end
end

LoginEvent:type("login")
LoginEvent:register()
LogoutEvent:type("logout")
LogoutEvent:register()
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

local function onSay(player, words, param)
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if words == "/daily" and player:getGroup():getAccess() and param ~= "" then
		local cmd, a, b = param:match("^(%S+)%s*(%S*)%s*(%S*)$")
		if cmd == "shift" then
			DY.offsetDays = math.floor(tonumber(a) or 0)
		elseif cmd == "set" then
			local rec = DY.record(player)
			rec.streak = math.max(0, math.floor(tonumber(a) or 0))
			rec.best = math.max(rec.best, rec.streak)
			rec.grace = math.max(0, math.floor(tonumber(b) or rec.grace))
			rec.last = rec.streak > 0 and Chaos.dayKey(os.time() + (DY.offsetDays - 1) * 86400) or 0
			save(player:getAccountId(), rec)
		end
		local v, rec = getState(player)
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Daily: today %d (shift %d), streak %d, best %d, grace %d, " ..
			"last %d, taken %s, next %d, slot %d, grace use %d.", DY.today(), DY.offsetDays, rec.streak, rec.best, rec.grace,
			rec.last, tostring(v.taken), v.next, v.slot, v.graceUse))
		return false
	end
	sendWindow(player)
	return false
end

for _, words in ipairs({"!daily", "/daily"}) do
	local talk = TalkAction(words)
	talk.onSay = onSay
	talk:separator(" ")
	talk:register()
end
