-- Run from the server/ folder: luajit tests/infinitytower_season_test.lua (or lua5.3; CI runs both)
-- Infinity Tower seasons and the season-end top 3 chests: infinitytower_core.lua (season numbers and ends, the epoch
-- table, ranking, ties, staff left out, awards, pending seasons, texts) and infinitytower.lua against a mocked engine
-- and an in-memory database (the payout once per season, a second check and a restart pay nothing again, online
-- delivery into the inbox, offline delivery at the next login, a new server, several ended seasons, /towerseason, the
-- client payload's podium, the configured chests and items).
local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then n = n + 1; rawset(t, k, n); return n end
end})
loadstring = loadstring or load
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/infinitytower_core.lua")
local K = ChaosTowerCore
local cfg = Chaos.tower

local failures, count = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ---------------------------------------------------------------- config
do
	local se = cfg.seasonEnd
	check(se and #se.chests == 3, "three chests")
	eq(se.chests[1].name, "Gold Tower Chest", "1st: the client's Gold Tower Chest")
	eq(se.chests[2].name, "Silver Tower Chest", "2nd: Silver")
	eq(se.chests[3].name, "Copper Tower Chest", "3rd: Copper")
	-- the orbs of the milestones (install_orbs.py), the chests stock pickupable containers of the 10.98 items
	local known = {[29856] = "Orb of Upheaval", [29857] = "Orb of Fate"}
	local containers = {[1746] = 10, [1740] = 15, [1738] = 10}
	for place, chest in ipairs(se.chests) do
		check(containers[chest.chestId] and #chest.items <= containers[chest.chestId], "chest " .. place .. " is a known container")
		for _, it in ipairs(chest.items) do
			eq(known[it.id], it.name, "chest " .. place .. " item " .. it.id)
			check(it.count > 0 and it.count <= 100, "chest " .. place .. " stack fits one slot")
		end
		if place > 1 then
			check(chest.items[1].count < se.chests[place - 1].items[1].count, "a better place gets more (" .. place .. ")")
		end
	end
	check(#se.configKey > 0 and not se.configKey:match("^chaos_season_"), "marker key outside the realm season's prefix")
end

-- ---------------------------------------------------------------- seasons
do
	local c = {seasonEpoch = 1000000, seasonLengthDays = 30}
	local L = 30 * 86400
	local s, start, finish = K.seasonOf(c, 1000000)
	eq(s, 1, "first second of the epoch")
	eq(start, 1000000, "start")
	eq(finish, 1000000 + L, "end")
	s = K.seasonOf(c, 1000000 + L - 1)
	eq(s, 1, "last second of season 1")
	s, start, finish = K.seasonOf(c, 1000000 + L)
	eq(s, 2, "season 2 begins at the end of season 1")
	eq(start, 1000000 + L, "season 2 start")
	eq(finish, 1000000 + 2 * L, "season 2 end")
	s, start, finish = K.seasonOf(c, 5)
	eq(s, 1, "before the epoch: season 1")
	eq(finish, 1000000 + L, "and it ends 30 days after the epoch")
	-- the configured epoch is a table in server local time
	local e = K.epoch(cfg)
	eq(e, os.time({year = 2026, month = 11, day = 20, hour = 15, min = 0, sec = 0}), "epoch table: the launch")
	eq(os.date("%Y-%m-%d %H:%M", e), "2026-11-20 15:00", "launch date")
	eq(K.epoch({seasonEpoch = 1735689600}), 1735689600, "a unix number still works")
	eq((K.seasonOf(cfg, e + 45 * 86400)), 2, "45 days after the launch: season 2")
end

-- ---------------------------------------------------------------- ranking and ties
do
	local rows = {
		{guid = 1, name = "A", floor = 30, time = 900},
		{guid = 2, name = "B", floor = 32, time = 2000},
		{guid = 3, name = "C", floor = 30, time = 800},
		{guid = 4, name = "GM", floor = 99, time = 1, group = 6},
		{guid = 5, name = "D", floor = 0, time = 0},
		{guid = 6, name = "E", floor = 28, time = 100}
	}
	local r = K.places(rows, 4)
	eq(#r, 4, "staff and floor 0 left out")
	eq(r[1].name, "B", "highest floor first")
	eq(r[2].name, "C", "same floor: faster first")
	eq(r[3].name, "A", "then the slower")
	eq(r[2].place, 2, "place 2")
	eq(r[4].place, 4, "place 4")
	local a = K.awards(r, cfg.seasonEnd)
	eq(#a, 3, "three awards")
	eq(a[1].chest.name, "Gold Tower Chest", "gold to 1st")
	eq(a[3].guid, 1, "copper to 3rd")

	-- ties: equal floor and time share the place, the next place is skipped (1, 1, 3)
	r = K.places({
		{guid = 10, name = "T1", floor = 40, time = 500},
		{guid = 11, name = "T2", floor = 40, time = 500},
		{guid = 12, name = "T3", floor = 40, time = 501},
		{guid = 13, name = "T4", floor = 39, time = 10}
	}, 4)
	eq(r[1].place, 1, "tie: first")
	eq(r[2].place, 1, "tie: shares 1st")
	eq(r[3].place, 3, "after a tie for 1st comes 3rd")
	eq(r[4].place, 4, "4th")
	a = K.awards(r, cfg.seasonEnd)
	eq(#a, 3, "two gold, one copper")
	eq(a[1].chest.name .. "|" .. a[2].chest.name .. "|" .. a[3].chest.name, "Gold Tower Chest|Gold Tower Chest|Copper Tower Chest",
		"tied 1st both get gold, no silver")
	-- a tie for 3rd: both get copper
	r = K.places({
		{guid = 1, floor = 50, time = 1}, {guid = 2, floor = 49, time = 1}, {guid = 3, floor = 48, time = 7},
		{guid = 4, floor = 48, time = 7}, {guid = 5, floor = 48, time = 8}}, 4)
	a = K.awards(r, cfg.seasonEnd)
	eq(#a, 4, "tie for 3rd: four awards")
	eq(a[4].chest.name, "Copper Tower Chest", "both 3rd get copper")
	-- order of the input does not matter
	local r2 = K.places({{guid = 4, floor = 48, time = 7}, {guid = 5, floor = 48, time = 8}, {guid = 3, floor = 48, time = 7},
		{guid = 2, floor = 49, time = 1}, {guid = 1, floor = 50, time = 1}}, 4)
	eq(r2[3].guid .. r2[4].guid .. r2[5].guid, "345", "stable order")
	eq(#K.awards(K.places({}, 4), cfg.seasonEnd), 0, "nobody climbed: no awards")

	-- pending seasons
	eq(K.pendingSeasons(nil, 5), nil, "new server: nothing")
	eq(#K.pendingSeasons(4, 5), 0, "previous season already paid")
	local p = K.pendingSeasons(1, 5)
	eq(#p, 3, "three ended seasons")
	eq(p[1] .. p[2] .. p[3], "234", "oldest first")
	eq(#K.pendingSeasons(0, 1), 0, "season 1 running: nothing ended")

	eq(K.chestText(cfg.seasonEnd.chests[1]), "Gold Tower Chest (20 Orb of Fate, 40 Orb of Upheaval)", "chest text")
	local top = K.topRewards(cfg.seasonEnd, function(id) return id + 732 end)
	eq(#top, 3, "podium of three")
	eq(top[1].id, 1746 + 732, "chest look as client id")
	eq(top[2].name, "Silver Tower Chest", "podium names")
	check(top[3].text:find("Orb of Fate", 1, true) ~= nil, "podium tooltip lists the contents")
end

-- ---------------------------------------------------------------- infinitytower.lua against a mocked engine
do
	-- in-memory tables
	local DB = {config = {}, rewards = {}, tower = {}, players = {}}
	local queries = {}
	local function rewardRow(season, guid)
		for _, r in ipairs(DB.rewards) do
			if r.season == season and r.player_id == guid then return r end
		end
	end
	local stored, nextResult = {}, 0
	db = {
		query = function(q)
			queries[#queries + 1] = q
			local s, g, pl, f, t, chest, at = q:match("^INSERT IGNORE INTO `chaos_tower_season_rewards`.-VALUES %((%d+), (%d+), (%d+), (%d+), (%d+), '([^']*)', 0, (%d+)%)")
			if s then
				s, g = tonumber(s), tonumber(g)
				if not rewardRow(s, g) then
					DB.rewards[#DB.rewards + 1] = {season = s, player_id = g, place = tonumber(pl), best_floor = tonumber(f),
						best_time = tonumber(t), chest = chest, rewarded = 0}
				end
				return true
			end
			local ds, rs, rg = q:match("^UPDATE `chaos_tower_season_rewards` SET `rewarded` = 1, `delivered_at` = (%d+) WHERE `season` = (%d+) AND `player_id` = (%d+) AND `rewarded` = 0")
			if ds then
				local r = rewardRow(tonumber(rs), tonumber(rg))
				if r then r.rewarded = 1 end
				return true
			end
			local key, value = q:match("^INSERT INTO `server_config`.-VALUES %('([^']*)', '([^']*)'%)")
			if key then
				DB.config[key] = value
				return true
			end
			return true
		end,
		storeQuery = function(q)
			local key = q:match("^SELECT `value` FROM `server_config` WHERE `config` = '([^']*)'")
			if key then
				if DB.config[key] == nil then return false end
				nextResult = nextResult + 1
				stored[nextResult] = {{value = DB.config[key]}}
				return nextResult
			end
			return false
		end,
		escapeString = function(s) return "'" .. tostring(s):gsub("'", "\\'") .. "'" end
	}
	result = {getString = function(id, col) return stored[id][1][col] end, free = function(id) stored[id] = nil end}
	json = {encode = function(t) return t end}
	local globals, talks, events = {}, {}, {}
	function CreatureEvent(name)
		local e = {type = function() end, register = function() end}
		events[name] = e
		return e
	end
	function GlobalEvent(name)
		local e = {interval = function() end, type = function() end, register = function() end}
		globals[name] = e
		return e
	end
	function TalkAction(words)
		local e = {separator = function() end, register = function() end}
		talks[words] = e
		return e
	end
	function ItemType(id) return {getId = function() return id end, getClientId = function() return id + 732 end,
		getName = function() return "item " .. id end} end
	-- items: created chests are containers that hold up to their size in stacks
	local made = {}
	Game = {
		createItem = function(id, cnt)
			local it = {id = id, count = cnt, attrs = {}, contents = {}}
			function it:setAttribute(k, v) self.attrs[k] = v end
			function it:getUniqueId() return it end
			made[#made + 1] = it
			return it
		end,
		getPlayers = function() return DB.online end,
		broadcastMessage = function(text) DB.broadcast = text end
	}
	function Container(it)
		return {addItem = function(_, id, c)
			if #it.contents >= 10 then return nil end
			it.contents[#it.contents + 1] = {id = id, count = c}
			return true
		end}
	end
	Chaos.select = function(q, cols)
		local out = {}
		local season = q:match("FROM `chaos_tower_players` t JOIN `players` p ON p.`id` = t.`player_id` WHERE t.`season` = (%d+)")
		if season then
			for _, r in ipairs(DB.tower) do
				if r.season == tonumber(season) and r.best_floor > 0 then
					local p = DB.players[r.player_id]
					out[#out + 1] = {player_id = r.player_id, name = p.name, group_id = p.group, best_floor = r.best_floor,
						best_time = r.best_time}
				end
			end
			return out
		end
		local guid = q:match("FROM `chaos_tower_season_rewards` WHERE `player_id` = (%d+) AND `rewarded` = 0")
		if guid then
			for _, r in ipairs(DB.rewards) do
				if r.player_id == tonumber(guid) and r.rewarded == 0 then
					out[#out + 1] = {season = r.season, place = r.place, best_floor = r.best_floor, chest = r.chest}
				end
			end
			table.sort(out, function(a, b) return a.season < b.season end)
			return out
		end
		return out
	end
	local P = {}
	P.__index = P
	local function mk(guid, name, group)
		local p = setmetatable({guid = guid, name = name, group = group or 1, msgs = {}, inbox = {}, events = {}}, P)
		DB.players[guid] = p
		return p
	end
	function P:getGuid() return self.guid end
	function P:getName() return self.name end
	function P:registerEvent(e) self.events[e] = true end
	function P:sendTextMessage(kind, text) self.msgs[#self.msgs + 1] = text end
	function P:getPosition() return {sendMagicEffect = function() end} end
	function P:getGroup() local g = self.group return {getAccess = function() return g >= 4 end} end
	function P:getInbox()
		local me = self
		return {
			addItemEx = function(_, item) me.inbox[#me.inbox + 1] = item return true end,
			addItem = function(_, id, c) me.inbox[#me.inbox + 1] = {id = id, count = c, contents = {}, attrs = {}} return true end
		}
	end
	local notified = {}
	ChaosNotify = {send = function(player, title, text) notified[#notified + 1] = {player.name, title, text} end}
	ChaosTower = nil
	dofile("data/scripts/chaos/infinitytower.lua")
	local CT = ChaosTower
	check(globals.ChaosTowerSeasonStartup and globals.ChaosTowerSeasonThink, "startup and periodic check registered")
	check(talks["/towerseason"], "staff command")

	local epoch = K.epoch(cfg)
	local L = cfg.seasonLengthDays * 86400
	local alice, bob, cara, dan, gm = mk(1, "Alice"), mk(2, "Bob"), mk(3, "Cara"), mk(4, "Dan"), mk(5, "Gamemaster", 6)
	DB.online = {alice, gm}

	-- a new server in season 1: the marker is set, nothing paid
	eq(CT.checkSeasons(true, epoch + 10), 0, "new server: nothing paid")
	eq(DB.config.chaos_tower_season_done, "0", "marker = current - 1")

	-- season 1 results
	local function run(guid, season, floor, time)
		DB.tower[#DB.tower + 1] = {player_id = guid, season = season, best_floor = floor, best_time = time}
	end
	run(1, 1, 25, 1500) -- Alice 2nd (online)
	run(2, 1, 30, 2400) -- Bob 1st (offline)
	run(3, 1, 25, 1500) -- Cara ties Alice: 2nd too (offline)
	run(4, 1, 20, 100) -- Dan 4th: no chest
	run(5, 1, 99, 1) -- staff: never

	-- still season 1: nothing
	eq(CT.checkSeasons(false, epoch + L - 1), 0, "season 1 not over")
	eq(#DB.rewards, 0, "no rows yet")

	-- season 2 starts: season 1 is paid
	eq(CT.checkSeasons(false, epoch + L + 5), 1, "season 1 paid at its end")
	eq(DB.config.chaos_tower_season_done, "1", "marker for season 1")
	eq(#DB.rewards, 3, "three rows: Bob, Alice, Cara")
	eq(rewardRow(1, 2).chest, "Gold Tower Chest", "Bob gold")
	eq(rewardRow(1, 1).chest, "Silver Tower Chest", "Alice silver")
	eq(rewardRow(1, 3).chest, "Silver Tower Chest", "Cara shares 2nd: silver")
	eq(rewardRow(1, 4), nil, "Dan 4th: none (the tie took 2nd and 3rd)")
	eq(rewardRow(1, 5), nil, "staff none")
	check(DB.broadcast and DB.broadcast:find("Season 1 has ended", 1, true) and DB.broadcast:find("1st Bob (floor 30)", 1, true),
		"broadcast names the winners: " .. tostring(DB.broadcast))

	-- online: delivered at once into the inbox, with a message and a notification
	eq(#alice.inbox, 1, "Alice's chest in the inbox")
	local chest = alice.inbox[1]
	eq(chest.id, 1740, "the Silver Tower Chest look")
	eq(chest.attrs[ITEM_ATTRIBUTE_NAME], "Silver Tower Chest", "named")
	check(tostring(chest.attrs[ITEM_ATTRIBUTE_DESCRIPTION]):find("Season 1, place 2", 1, true), "described")
	eq(#chest.contents, 2, "two stacks inside")
	eq(chest.contents[1].id .. "x" .. chest.contents[1].count, "29857x12", "Orbs of Fate")
	eq(chest.contents[2].id .. "x" .. chest.contents[2].count, "29856x25", "Orbs of Upheaval")
	check(alice.msgs[#alice.msgs]:find("Your Silver Tower Chest (12 Orb of Fate, 25 Orb of Upheaval) is in your inbox", 1, true),
		"message: " .. tostring(alice.msgs[#alice.msgs]))
	eq(notified[#notified][2], "Infinity Tower", "notification sent")
	eq(rewardRow(1, 1).rewarded, 1, "Alice marked delivered")
	eq(rewardRow(1, 2).rewarded, 0, "Bob still owed (offline)")
	eq(#gm.inbox, 0, "staff online: nothing")

	-- once only: another check, a restart, a staff "pay"
	eq(CT.checkSeasons(false, epoch + L + 100), 0, "second check: nothing")
	eq(CT.checkSeasons(true, epoch + L + 200), 0, "restart: nothing")
	DB.config.chaos_tower_season_done = "0" -- even with the marker lost, the rows are not written twice
	CT.checkSeasons(false, epoch + L + 300)
	eq(#DB.rewards, 3, "INSERT IGNORE: still three rows")
	eq(#alice.inbox, 1, "Alice not paid twice")
	CT.deliverPending(alice)
	eq(#alice.inbox, 1, "delivered rows are not delivered again")

	-- offline: Bob logs in later and gets it then
	events.ChaosTowerLogin.onLogin(bob)
	eq(#bob.inbox, 1, "Bob's chest at login")
	eq(bob.inbox[1].attrs[ITEM_ATTRIBUTE_NAME], "Gold Tower Chest", "gold")
	eq(bob.inbox[1].contents[1].count, 20, "20 Orbs of Fate")
	check(bob.events.ChaosTowerExtended, "login still registers the opcode event")
	events.ChaosTowerLogin.onLogin(bob)
	eq(#bob.inbox, 1, "second login: nothing more")
	events.ChaosTowerLogin.onLogin(dan)
	eq(#dan.inbox, 0, "4th place: nothing")

	-- a long downtime: seasons 2 and 3 ended while the server was off; both paid at startup, oldest first, no broadcast
	run(3, 2, 40, 900) -- Cara wins season 2
	run(4, 3, 41, 950) -- Dan wins season 3
	DB.broadcast = nil
	DB.online = {}
	eq(CT.checkSeasons(true, epoch + 3 * L + 10), 2, "two seasons paid at startup")
	eq(DB.config.chaos_tower_season_done, "3", "marker at season 3")
	eq(DB.broadcast, nil, "no broadcast at startup")
	events.ChaosTowerLogin.onLogin(cara)
	eq(#cara.inbox, 2, "Cara: season 1 silver and season 2 gold at one login")
	eq(cara.inbox[1].attrs[ITEM_ATTRIBUTE_NAME] .. "|" .. cara.inbox[2].attrs[ITEM_ATTRIBUTE_NAME], "Silver Tower Chest|Gold Tower Chest",
		"oldest season first")
	events.ChaosTowerLogin.onLogin(dan)
	eq(#dan.inbox, 1, "Dan: season 3 gold")

	-- a chest that cannot hold everything: the rest goes into the inbox loose
	local realContainer = Container
	Container = function() return {addItem = function() return nil end} end
	DB.rewards[#DB.rewards + 1] = {season = 9, player_id = 1, place = 3, best_floor = 5, chest = "Copper Tower Chest", rewarded = 0}
	local before = #alice.inbox
	CT.deliverPending(alice)
	eq(#alice.inbox, before + 3, "chest plus two loose stacks")
	eq(alice.inbox[before + 3].id, 29856, "loose orbs in the inbox")
	Container = realContainer

	-- the window's payload carries the podium
	local sent
	function P:sendExtendedOpcode(op, payload) sent = payload end
	function P:getStorageValue() return -1 end
	CT.open(alice)
	check(sent and sent.topRewards and #sent.topRewards == 3, "payload topRewards")
	eq(sent.topRewards[1].id, 1746 + 732, "podium: chest client id from ItemType")
	eq(sent.topRewards[3].name, "Copper Tower Chest", "podium names")
	eq(sent.seasonNum, 1, "the payload season (real clock: before the epoch)")

	-- staff command
	talks["/towerseason"].onSay(gm, "/towerseason", "")
	check(gm.msgs[#gm.msgs]:find("Last season paid out: 3", 1, true), "status: " .. gm.msgs[#gm.msgs])
	eq(talks["/towerseason"].onSay(alice, "/towerseason", "pay"), true, "players: plain chat")
end

-- ---------------------------------------------------------------- reward claim: mark first, give second
do
	local ms = {points = 100, items = {{id = 1, count = 2}, {id = 2, count = 1}}}
	local function mkapi(opts)
		local a = {bits = 0, gave = {}, took = {}, logs = {}}
		a.mark = function(bit)
			if opts.markFails then return false end
			a.bits = a.bits + bit
			return true
		end
		a.unmark = function(bit) a.bits = a.bits - bit; return not opts.unmarkFails end
		a.give = function(item)
			-- the bit must already be set while items are handed over
			a.bitAtGive = a.bits
			if opts.short == item.id then return item.count - 1 end
			a.gave[#a.gave + 1] = item.id
			return item.count
		end
		a.take = function(id, c) a.took[#a.took + 1] = id .. "x" .. c end
		a.log = function(t) a.logs[#a.logs + 1] = t end
		return a
	end
	local a = mkapi({})
	eq(K.claimReward(a, {claimed_mask = 0, points = 100}, 3, ms), "claimed", "claim ok")
	eq(a.bits, 4, "claim: bit 3 is set")
	eq(a.bitAtGive, 4, "claim: bit set before items are given")
	eq(#a.gave, 2, "claim: both items given")

	a = mkapi({})
	eq(K.claimReward(a, {claimed_mask = 4, points = 100}, 3, ms), "already", "second claim refused")
	eq(#a.gave, 0, "second claim gives nothing")
	eq(a.bits, 0, "second claim marks nothing")
	eq(K.claimReward(a, {claimed_mask = 0, points = 99}, 3, ms), "points", "too few points")

	a = mkapi({markFails = true})
	eq(K.claimReward(a, {claimed_mask = 0, points = 100}, 1, ms), "db", "mark fails: db")
	eq(#a.gave, 0, "mark fails: nothing given")

	a = mkapi({short = 2})
	eq(K.claimReward(a, {claimed_mask = 0, points = 100}, 2, ms), "room", "no room")
	eq(a.bits, 0, "no room: bit cleared again")
	eq(a.took[1], "1x2", "no room: first item taken back")

	a = mkapi({short = 2, unmarkFails = true})
	eq(K.claimReward(a, {claimed_mask = 0, points = 100}, 2, ms), "room", "no room, unmark fails")
	eq(#a.logs, 1, "failed unmark is logged")
end

print(string.format("infinitytower_season_test: %d checks, %d failed", count, failures))
if failures > 0 then
	os.exit(1)
end
