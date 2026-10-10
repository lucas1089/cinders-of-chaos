-- Bounty board (client game_bounty, extended opcode ChaosOpcodes.bounty)
--
-- Every day at Chaos.bountyConfig.rollHour the board rolls 4 contracts per level band (hunt, hunt, elite, boss), the
-- same for everyone: the roll is seeded from the date (bounty_core.lua), so a restart gives the same board. Monsters
-- come from bounty_pool.lua (tools/gen_bounty_pool.py: only monsters that spawn on the loaded map).
-- A player sees the band of their level and the ones next to it, accepts up to maxActive contracts; kills count when
-- the player made the kill (last hit or most damage, summons for their master) or a party member within partyRange
-- did. A finished contract pays at once: gold to the bank, Orbs of Upheaval and Fate to the backpack (inbox when full), a
-- little experience. weeklyNeed contracts in a bounty week give a chest of orbs. Contracts expire at the next roll.
-- State: table chaos_bounty (server/sql/chaos.sql), one row per accepted contract; the weekly bonus week in storage
-- Chaos.storage.bountyWeekBonus. Multi-client: see mcReward in bounty_config.lua.
--
-- Protocol (JSON {action, data}):
--   client -> server  open | accept {key} | abandon {key}
--   server -> client  board {day, nextIn, open, band, active, maxActive, week = {done, need, claimed}, bands = [{index,
--                            label, own, contracts = [{key, type, name, count, tier, level, look, outfit, reward =
--                            {gold, chaos, divine, exp}, state = open|active|done, progress}]}]}
--                     progress {key, progress, count, state}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
dofile("data/scripts/chaos/bounty_core.lua")

Chaos.bountyConfig = dofile("data/scripts/chaos/bounty_config.lua")
local cfg = Chaos.bountyConfig
local B = ChaosBounty
local OPCODE = ChaosOpcodes.bounty
local TABLE = cfg.table

-- ---------------------------------------------------------------- pool (only monsters this server knows)
-- The scripts load before the monsters, so the pool is checked against MonsterType at the first roll, not here.
local rawPool = dofile("data/scripts/chaos/bounty_pool.lua")

local function filterPool(raw)
	local pool, missing = {hunt = {}, bosses = {}}, 0
	for _, list in ipairs({"hunt", "bosses"}) do
		for _, e in ipairs(raw[list] or {}) do
			if MonsterType(e.name) then
				table.insert(pool[list], e)
			else
				missing = missing + 1
			end
		end
	end
	if missing > 0 then
		print(string.format("[ChaosBounty] %d pool monster(s) unknown to this server were left out", missing))
	end
	return pool
end

-- names of every pool monster (they get the death event when they spawn)
B.names = {}
for _, list in ipairs({rawPool.hunt or {}, rawPool.bosses or {}}) do
	for _, e in ipairs(list) do
		B.names[e.name:lower()] = true
	end
end
-- reset on every script load, so /reload scripts picks up a regenerated pool (the board is rolled again)
B.pool, B.current = nil, nil

function B.board()
	local day = B.day(os.time(), cfg)
	if not B.current or B.current.day ~= day then
		B.pool = B.pool or filterPool(rawPool)
		B.current = B.roll(day, cfg, B.pool)
	end
	return B.current
end

-- ---------------------------------------------------------------- player state
-- B.players[guid] = {day = bounty day, entries = {[key] = {key, day, monster, progress, required, status, mc}},
--                    weekDone = n (completed this bounty week)}
B.players = B.players or {}

local function weekDone(guid, week)
	local resultId = db.storeQuery(string.format(
		"SELECT COUNT(*) AS `n` FROM `%s` WHERE `player_id` = %d AND `status` = 1 AND `mc` = 0 AND `day` >= %d",
		TABLE, guid, week))
	if not resultId then
		return 0
	end
	local n = result.getNumber(resultId, "n")
	result.free(resultId)
	return n
end

local function loadPlayer(player)
	local guid = player:getGuid()
	local day = B.day(os.time(), cfg)
	-- drop unfinished contracts of past days and history older than two weeks
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND ((`status` = 0 AND `day` < %d) OR `day` < %d)",
		TABLE, guid, day, Chaos.dayKey(os.time() - 15 * 86400)))
	local entries = {}
	for _, row in ipairs(Chaos.select(string.format(
		"SELECT `contract`, `monster`, `progress`, `required`, `status`, `mc` FROM `%s` WHERE `player_id` = %d AND `day` = %d",
		TABLE, guid, day), {{"contract", "s"}, {"monster", "s"}, {"progress", "n"}, {"required", "n"}, {"status", "n"}, {"mc", "n"}})) do
		entries[row.contract] = {key = row.contract, day = day, monster = row.monster, progress = row.progress,
			required = row.required, status = row.status, mc = row.mc}
	end
	local week = B.week(os.time(), cfg)
	local st = {day = day, week = week, entries = entries, weekDone = weekDone(guid, week)}
	B.players[guid] = st
	return st
end
B.loadPlayer = loadPlayer -- (GM / test use: reloads a player's contracts from the database)

local function stateOf(player)
	local st = B.players[player:getGuid()]
	local day = B.day(os.time(), cfg)
	if not st then
		return loadPlayer(player)
	end
	if st.day ~= day then
		-- the board rolled: contracts of the old day expire
		B.expire(st.entries, day)
		local week = B.week(os.time(), cfg)
		if week ~= st.week then
			st.week, st.weekDone = week, weekDone(player:getGuid(), week)
		end
		st.day = day
	end
	return st
end

-- ---------------------------------------------------------------- window
local function contractView(c, st, level)
	local e = st.entries[c.key]
	local outfit = {type = c.look}
	if c.outfit then
		for k, v in pairs(c.outfit) do
			outfit[k] = v
		end
	end
	return {
		key = c.key, type = c.type, name = c.name, count = c.count, tier = c.tier, level = c.level,
		look = c.look, outfit = outfit, reward = B.reward(c, cfg, level),
		state = not e and "open" or (e.status == 1 and "done" or "active"),
		progress = e and e.progress or 0
	}
end

-- open = true: the client shows the window (menu, !bounty); otherwise it only refreshes an open window
function B.sendBoard(player, open)
	local board = B.board()
	local st = stateOf(player)
	local level = player:getLevel()
	local visible, own = B.visibleBands(level, cfg)
	local bands = {}
	for _, i in ipairs(visible) do
		local band = board.bands[i]
		local list = {}
		for _, c in ipairs(band.contracts) do
			list[#list + 1] = contractView(c, st, level)
		end
		bands[#bands + 1] = {index = i, label = band.label, own = (i == own), contracts = list}
	end
	local now = os.time()
	Chaos.send(player, OPCODE, "board", {
		day = board.day,
		nextIn = math.max(0, B.nextRoll(now, cfg) - now),
		band = own,
		active = B.activeCount(st.entries, board.day),
		maxActive = cfg.maxActive,
		open = open and true or false,
		week = {done = st.weekDone, need = cfg.weeklyNeed,
			claimed = player:getStorageValue(Chaos.storage.bountyWeekBonus) == B.week(now, cfg)},
		bands = bands
	})
end

local function notify(player, message, look)
	player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "bounty", message = message,
		monsterLookType = (look and look > 0) and look or nil}))
end

-- ---------------------------------------------------------------- rewards
local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

local function giveWeekly(player, bandIndex)
	local r = B.weeklyReward(bandIndex, cfg)
	local chest = Game.createItem(cfg.weeklyChestId, 1)
	if not chest then
		return
	end
	if cfg.weeklyChestName then
		chest:setAttribute(ITEM_ATTRIBUTE_NAME, cfg.weeklyChestName)
	end
	local container = Container(chest:getUniqueId())
	-- the chest holds only a few stacks (a present: 5): what does not fit goes to the backpack / inbox afterwards
	local overflow = {}
	local function put(id, count)
		if not container:addItem(id, count) then
			overflow[#overflow + 1] = {id = id, count = count}
		end
	end
	if r.chaos > 0 then
		put(cfg.items.chaos, r.chaos)
	end
	if r.divine > 0 then
		put(cfg.items.divine, r.divine)
	end
	local extra = {}
	for _, e in ipairs(cfg.weeklyExtra or {}) do
		put(e.id, e.count)
		extra[#extra + 1] = string.format(", %d %s", e.count, e.name)
	end
	-- gems (data/lib/chaos_gems_config.lua rewards.bountyWeekly)
	local gems = ChaosGems and ChaosGems.rewardGems("bountyWeekly", {band = bandIndex}) or {}
	for _, g in ipairs(gems) do
		put(g.id, g.count)
	end
	if #gems > 0 then
		extra[#extra + 1] = ", " .. ChaosGems.listText(gems)
	end
	local inbox = false
	if player:addItemEx(chest, false) ~= RETURNVALUE_NOERROR then
		local box = player:getInbox()
		if box then
			box:addItemEx(chest, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
			inbox = true
		end
	end
	for _, o in ipairs(overflow) do
		inbox = giveStack(player, o.id, o.count) or inbox
	end
	player:setStorageValue(Chaos.storage.bountyWeekBonus, B.week(os.time(), cfg))
	local text = string.format("Weekly bounty bonus: a %s with %d Orbs of Upheaval and %d Orbs of Fate%s.%s",
		cfg.weeklyChestName or "chest", r.chaos, r.divine, table.concat(extra), inbox and " It is in your inbox." or "")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
	notify(player, text)
end

local function payContract(player, c, e)
	if e.mc == 1 and not cfg.mcReward then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"Bounty completed: %s. Another character from your connection was online during the hunt: no reward.", c.name))
		return false
	end
	local r = B.reward(c, cfg, player:getLevel())
	if r.gold > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	local inbox = giveStack(player, cfg.items.chaos, r.chaos)
	inbox = giveStack(player, cfg.items.divine, r.divine) or inbox
	-- gems (data/lib/chaos_gems_config.lua rewards.bounty: chance by contract type, quality by the level band)
	local gems = ChaosGems and ChaosGems.rewardGems("bounty", {type = c.type, band = c.band}) or {}
	for _, g in ipairs(gems) do
		inbox = giveStack(player, g.id, g.count) or inbox
	end
	-- spell support runes (data/lib/chaos_supports_config.lua rewards.bounty)
	local runes = ChaosSupports and ChaosSupports.rewardRunes("bounty", {type = c.type, band = c.band}) or {}
	for _, g in ipairs(runes) do
		inbox = giveStack(player, g.id, g.count) or inbox
	end
	if r.exp > 0 then
		player:addExperience(r.exp, true)
	end
	local parts = {}
	if r.gold > 0 then
		parts[#parts + 1] = r.gold .. " gold (bank)"
	end
	if r.chaos > 0 then
		parts[#parts + 1] = r.chaos .. (r.chaos > 1 and " Orbs of Upheaval" or " Orb of Upheaval")
	end
	if r.divine > 0 then
		parts[#parts + 1] = r.divine .. (r.divine > 1 and " Orbs of Fate" or " Orb of Fate")
	end
	if #gems > 0 then
		parts[#parts + 1] = ChaosGems.listText(gems)
	end
	if #runes > 0 then
		parts[#parts + 1] = ChaosSupports.listText(runes)
	end
	if r.exp > 0 then
		parts[#parts + 1] = r.exp .. " experience"
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Bounty completed: %s. Reward: %s.%s", c.name,
		table.concat(parts, ", "), inbox and " Your backpack was full: the orbs are in your inbox." or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	if ChaosRift and ChaosRift.onBountyPaid then
		ChaosRift.onBountyPaid(player, c) -- a chance of a tier-1 Rift Key (rift_config.lua bountyKey)
	end
	return true
end

-- ---------------------------------------------------------------- accept / abandon
local function accept(player, key)
	if type(key) ~= "string" then
		return
	end
	local board = B.board()
	local st = stateOf(player)
	local ok, c = B.canAccept(board, st.entries, key, (B.visibleBands(player:getLevel(), cfg)), cfg)
	if not ok then
		player:sendCancelMessage(c)
		B.sendBoard(player)
		return
	end
	local now = os.time()
	local mc = Chaos.isMultiClient(player) and 1 or 0
	st.entries[key] = {key = key, day = board.day, monster = c.name, progress = 0, required = c.count, status = 0, mc = mc}
	db.asyncQuery(string.format("INSERT INTO `%s` (`player_id`, `day`, `contract`, `monster`, `progress`, `required`, " ..
		"`status`, `mc`, `accepted_at`) VALUES (%d, %d, %s, %s, 0, %d, 0, %d, %d) ON DUPLICATE KEY UPDATE `progress` = 0, " ..
		"`required` = VALUES(`required`), `status` = 0, `mc` = VALUES(`mc`), `accepted_at` = VALUES(`accepted_at`)",
		TABLE, player:getGuid(), board.day, db.escapeString(key), db.escapeString(c.name), c.count, mc, now))
	local what = c.type == "elite" and string.format("%d %s+ %s", c.count, c.tier, c.name)
		or string.format("%d x %s", c.count, c.name)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Bounty accepted: " .. what .. ". It expires at the next roll.")
	if mc == 1 and not cfg.mcReward then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
			"Another character from your connection is online: you may hunt, but this contract will pay no reward.")
	end
	B.sendBoard(player)
end

local function abandon(player, key)
	local st = stateOf(player)
	local e = type(key) == "string" and st.entries[key]
	if not e or e.status ~= 0 then
		return
	end
	st.entries[key] = nil
	db.asyncQuery(string.format("DELETE FROM `%s` WHERE `player_id` = %d AND `day` = %d AND `contract` = %s",
		TABLE, player:getGuid(), e.day, db.escapeString(key)))
	player:sendTextMessage(MESSAGE_INFO_DESCR, "Bounty abandoned: " .. e.monster .. ".")
	B.sendBoard(player)
end

-- ---------------------------------------------------------------- kills
local function creditKill(player, c, tierName)
	local st = stateOf(player)
	local e = st.entries[c.key]
	if not e or e.status ~= 0 or e.day ~= B.current.day then
		return
	end
	if e.mc == 0 and Chaos.isMultiClient(player) then
		e.mc = 1
	end
	local crossed, done = B.addKill(e, cfg.progressNotices)
	if not crossed then
		return
	end
	db.asyncQuery(string.format("UPDATE `%s` SET `progress` = %d, `status` = %d, `mc` = %d, `completed_at` = %d " ..
		"WHERE `player_id` = %d AND `day` = %d AND `contract` = %s", TABLE, e.progress, e.status, e.mc,
		done and os.time() or 0, player:getGuid(), e.day, db.escapeString(c.key)))
	Chaos.send(player, OPCODE, "progress", {key = c.key, progress = e.progress, count = e.required,
		state = done and "done" or "active"})
	if done then
		local paid = payContract(player, c, e)
		notify(player, string.format("Bounty completed: %s (%d/%d).%s", c.name, e.progress, e.required,
			paid and "" or " No reward (multi-client)."), c.look)
		if paid then
			if ChaosLeaderboard and ChaosLeaderboard.record then ChaosLeaderboard.record("bounty", player, 1) end -- leaderboard.lua
			st.weekDone = st.weekDone + 1
			local week = B.week(os.time(), cfg)
			if st.weekDone >= cfg.weeklyNeed and player:getStorageValue(Chaos.storage.bountyWeekBonus) ~= week then
				giveWeekly(player, B.bandOf(player:getLevel(), cfg))
			end
		end
		B.sendBoard(player)
		return
	end
	player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_STATUS_SMALL,
		string.format("Bounty: %s %d/%d.", c.name, e.progress, e.required))
	for _, pct in ipairs(crossed) do
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("Bounty %s: %d%% done (%d/%d).", c.name, pct, e.progress,
			e.required))
		if pct == 50 then
			notify(player, string.format("Bounty halfway: %s %d/%d.", c.name, e.progress, e.required), c.look)
		end
	end
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	if master and master:isPlayer() then
		return master
	end
	return nil
end

function B.onKill(creature, killer, mostDamageKiller)
	local list = B.board().byName[typeNameOf(creature):lower()]
	if not list then
		return
	end
	local id = creature:getId()
	local dead = ChaosTierDead and ChaosTierDead[id]
	local tier = dead and dead.tier or (ChaosTierOf and ChaosTierOf(creature)) or "normal"
	local killers, seen = {}, {}
	for _, k in ipairs({playerOf(killer), playerOf(mostDamageKiller)}) do
		if k and not seen[k:getId()] then
			seen[k:getId()] = true
			killers[#killers + 1] = k
		end
	end
	if #killers == 0 then
		return
	end
	local credited = B.credit(killers, function(p)
		local party = p:getParty()
		if not party then
			return nil
		end
		local members = party:getMembers()
		members[#members + 1] = party:getLeader()
		return members
	end, function(p) return p:getPosition() end, cfg.partyRange, function(p) return p:getId() end)
	for _, c in ipairs(list) do
		if B.matches(c, typeNameOf(creature), tier) then
			for _, p in ipairs(credited) do
				creditKill(p, c, tier)
			end
		end
	end
end

local death = CreatureEvent("ChaosBountyDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	B.onKill(creature, killer, mostDamageKiller)
	return true
end
death:register()

-- only monsters of the pool get the death event
local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if B.names[typeNameOf(self):lower()] and not self:getMaster() then
		self:registerEvent("ChaosBountyDeath")
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- the daily roll
local roll = GlobalEvent("ChaosBountyRoll")
function roll.onThink(interval)
	local before = B.current and B.current.day
	local board = B.board()
	if before and before ~= board.day then
		for _, player in ipairs(Game.getPlayers()) do
			stateOf(player)
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "The bounty board has new contracts (Adventure > Bounty Board).")
		end
	end
	return true
end
roll:interval(60000)
roll:register()

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosBountyLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBountyExtended")
	player:registerEvent("ChaosBountyLogout")
	loadPlayer(player)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosBountyLogout")
function logout.onLogout(player)
	B.players[player:getGuid()] = nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosBountyExtended")
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
		B.sendBoard(player, true)
	elseif msg.action == "accept" then
		accept(player, data.key)
	elseif msg.action == "abandon" then
		abandon(player, data.key)
	end
end
ext:type("extendedopcode")
ext:register()

