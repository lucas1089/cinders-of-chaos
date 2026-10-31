-- The Weekly Chest (client game_weeklychest, extended opcode ChaosOpcodes.weeklyChest = 117; server/README.md "The
-- Weekly Chest (O261)"). Rules: weeklychest_core.lua (pure, tests/weeklychest_test.lua); numbers: weeklychest_config.lua.
--
-- Six activities count once each per bounty week: a dungeon, a rift, a waystone run, an Infinity Tower floor, a world boss
-- or invasion share and a bounty contract. 4 of 6 open the chest (gold to the bank, orbs to the backpack, else the inbox,
-- with a toast); all of the unlocked ones add a bonus roll. An activity the character cannot do yet is left out and the
-- needed count drops with it (at least 2).
--
-- Where the activities come from (hooks installed at startup and again every minute, through ChaosWrapChain):
--   counters      ChaosAchievements.progress (wrapped): rift_runs, bounty_done, wb_kills, invasion_fought
--   journey       ChaosSeasonJourney.emit (wrapped): dungeon_clears (dungeons.lua)
--   tower         ChaosTower.recordRun (wrapped): a run with a floor cleared
--   waystone      ChaosWaystoneTiers.startRun (wrapped): the run's opener (mods.opener, waystone_mods.lua)
--
-- Protocol (JSON {action, data}):
--   client -> server  open | close | get
--   server -> client  state {open = 1 | nil, ...} (weeklychest_core.lua K.view)
-- Assumed engine API (TFS 1.4): Player storages, getBankBalance/setBankBalance, addItem, getInbox,
-- CreatureEvent login/logout/extendedopcode, GlobalEvent startup/think. Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/weeklychest_core.lua")
if not (ChaosWrapChain and ChaosWrapChain.wrap) then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end
ChaosWeeklyChestConfig = dofile("data/scripts/chaos/weeklychest_config.lua")

ChaosWeeklyChest = ChaosWeeklyChest or {}
local W = ChaosWeeklyChest
local K = ChaosWeeklyChestCore
local OPCODE = ChaosOpcodes.weeklyChest or 117

W.st = W.st or {} -- player id -> state
W.watch = W.watch or {} -- player id -> true while the window is open
W.pushAt = W.pushAt or {} -- player id -> os.mtime of the last push

local function cfg()
	return ChaosWeeklyChestConfig
end

local function log(text)
	print("[Chaos weekly chest] " .. text)
end

for _, p in ipairs(K.validate(cfg())) do
	log("weeklychest_config.lua: " .. p)
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

-- ---------------------------------------------------------------- state
local function stateOf(player)
	local id = player:getId()
	local st = W.st[id]
	if not st then
		local base = cfg().storage.base
		st = K.load(cfg(), function(off) return player:getStorageValue(base + off) end)
		W.st[id] = st
	end
	return st
end

local function save(player)
	local st = W.st[player:getId()]
	if st then
		local base = cfg().storage.base
		K.save(cfg(), st, function(off, v) player:setStorageValue(base + off, v) end)
	end
end

-- ---------------------------------------------------------------- texts and rewards
local function toast(player, title, text)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
	if ChaosNotify and ChaosNotify.send then
		pcall(ChaosNotify.send, player, "", text, "weeklychest") -- the toast's own header says Weekly Chest
	end
end

local function itemText(list)
	local parts = {}
	for _, it in ipairs(list or {}) do
		local ok, name = pcall(function() return ItemType(it.id):getName() end)
		name = ok and name and name ~= "" and name or ("item " .. it.id)
		parts[#parts + 1] = (it.count > 1 and (it.count .. "x ") or "") .. name
	end
	return table.concat(parts, ", ")
end

local function giveItems(player, list)
	local inbox = 0
	for _, it in ipairs(list or {}) do
		local ok, item = pcall(function() return player:addItem(it.id, it.count, false) end)
		if not ok or not item then
			local box = player:getInbox()
			local okBox = box and pcall(function() return box:addItem(it.id, it.count) end)
			if okBox then
				inbox = inbox + 1
			else
				log("could not give " .. it.count .. "x " .. it.id .. " to " .. player:getName())
			end
		end
	end
	return inbox
end

-- gold to the bank, items to the backpack (else the inbox); returns the reward and the number of stacks in the inbox
local function give(player, def)
	local r = K.reward(cfg(), player:getLevel(), def)
	if r.gold > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	return r, giveItems(player, r.items)
end

local function rewardText(player, r, inbox)
	local items = itemText(r.items)
	local text
	if items ~= "" then
		text = Chaos.t(player, "%d gold to your bank and %s.", r.gold, items)
	else
		text = Chaos.t(player, "%d gold to your bank.", r.gold)
	end
	if inbox > 0 then
		text = text .. " " .. Chaos.t(player, "Your backpack was full: see your inbox.")
	end
	return text
end

-- ---------------------------------------------------------------- the window
local function itemInfo(id)
	local ok, cid, name = pcall(function()
		local it = ItemType(id)
		return it:getClientId(), it:getName()
	end)
	if ok then
		return cid, name
	end
	return id, "item " .. id
end

function W.view(player)
	local st = stateOf(player)
	K.roll(st, os.time(), cfg())
	return K.view(st, cfg(), os.time(), player:getLevel(), itemInfo)
end

local function send(player, open)
	local v = W.view(player)
	if open then
		v.shown = 1 -- the window was just opened; `open` is the count of activities the character can do
	end
	W.pushAt[player:getId()] = nowMs()
	Chaos.send(player, OPCODE, "state", v)
end
W.send = send

local function maybePush(player)
	local id = player:getId()
	if W.watch[id] and nowMs() - (W.pushAt[id] or 0) >= (cfg().pushMs or 2000) then
		send(player, false)
	end
end

-- ---------------------------------------------------------------- crediting
-- an activity done by an online character: marks it once a week, gives the chest and the bonus roll when they are due.
-- Returns true when the activity was new this week.
function W.credit(player, key)
	local c = cfg()
	if not c.enabled or not player or not K.indexOf(c, key) then
		return false
	end
	if Chaos.isTesterGuid and Chaos.isTesterGuid(player:getGuid()) then
		return false
	end
	local st = stateOf(player)
	K.roll(st, os.time(), c)
	if not K.mark(st, c, key) then
		save(player)
		return false
	end
	local level = player:getLevel()
	local due = K.due(st, c, level)
	-- the state is written before anything is given
	if due.chest then
		st.chest, st.chests = 1, st.chests + 1
	end
	if due.bonus then
		st.bonus = 1
	end
	save(player)
	local t = K.targets(st, c, level)
	if not due.chest and st.chest ~= 1 then
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, Chaos.t(player,
			"Weekly Chest: %d of %d activities done this week.", K.doneCount(st, c), t.need))
	end
	if due.chest then
		local r, inbox = give(player, c.chest)
		toast(player, "Weekly Chest", Chaos.t(player, "The Weekly Chest opens: %s", rewardText(player, r, inbox)))
	end
	if due.bonus then
		local _, def = K.bonusOption(c, math.random())
		local r, inbox = give(player, def)
		toast(player, "Weekly Chest", Chaos.t(player, "Bonus roll for every activity of the week: %s",
			rewardText(player, r, inbox)))
	end
	maybePush(player)
	return true
end

-- who: a player, a guid, or {guid, name} (the shapes ChaosAchievements.progress takes) -> the online player or nil
local function online(who)
	if type(who) == "userdata" or (type(who) == "table" and who.getGuid) then
		return who
	end
	local guid = type(who) == "table" and tonumber(who.guid) or tonumber(who)
	if not guid then
		return nil
	end
	for _, p in ipairs(Game.getPlayers()) do
		if p:getGuid() == guid then
			return p
		end
	end
	return nil
end
W.online = online

local function creditMapped(map, who, key, amount)
	local activity = map and map[key]
	if not activity or (amount ~= nil and (tonumber(amount) or 0) <= 0) then
		return
	end
	local p = online(who)
	if p then
		W.credit(p, activity)
	end
end

local function hookLog(e)
	log("hook: " .. tostring(e))
end

function W.installHooks()
	local C = ChaosWrapChain
	C.wrap(ChaosAchievements, "progress", "weeklychest_ach", function(res, who, key, amount)
		creditMapped(cfg().stats, who, key, amount)
	end, hookLog)
	C.wrap(ChaosSeasonJourney, "emit", "weeklychest_emit", function(res, who, stat, value, mode)
		if mode == nil or mode == "add" then
			creditMapped(cfg().emits, who, stat, value)
		end
	end, hookLog)
	C.wrap(ChaosTower, "recordRun", "weeklychest_tower", function(res, player, floorsCleared)
		if player and (tonumber(floorsCleared) or 0) > 0 then
			local p = online(player)
			if p then
				W.credit(p, "tower")
			end
		end
	end, hookLog)
	-- a waystone run: the pads opened (tier_maps.lua after the waystone was taken); mods.opener is the guid of the player
	-- whose waystone the device took
	C.wrap(ChaosWaystoneTiers, "startRun", "weeklychest_waystone", function(res, area, serverId, mods)
		if res[1] ~= nil and type(mods) == "table" and mods.opener then
			local p = online(mods.opener)
			if p then
				W.credit(p, "waystone")
			end
		end
	end, hookLog)
end

-- ---------------------------------------------------------------- login / logout
function W.login(player)
	W.st[player:getId()] = nil
	local st = stateOf(player)
	K.roll(st, os.time(), cfg())
	save(player)
end

function W.logout(player)
	local id = player:getId()
	save(player)
	W.st[id], W.watch[id], W.pushAt[id] = nil, nil, nil
end

local login = CreatureEvent("ChaosWeeklyChestLogin")
function login.onLogin(player)
	player:registerEvent("ChaosWeeklyChestLogout")
	player:registerEvent("ChaosWeeklyChestExtended")
	local ok, err = pcall(W.login, player)
	if not ok then
		log("login: " .. tostring(err))
	end
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosWeeklyChestLogout")
function logout.onLogout(player)
	local ok, err = pcall(W.logout, player)
	if not ok then
		log("logout: " .. tostring(err))
	end
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosWeeklyChestExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	if Chaos.limited and Chaos.limited(player, "weeklychest." .. tostring(msg.action), 300) then
		return
	end
	local action = msg.action
	if action == "open" then
		W.watch[player:getId()] = true
		send(player, true)
	elseif action == "close" then
		W.watch[player:getId()] = nil
	elseif action == "get" then
		send(player, false)
	end
end
ext:type("extendedopcode")
ext:register()

local startup = GlobalEvent("ChaosWeeklyChestStartup")
function startup.onStartup()
	W.installHooks()
	return true
end
startup:register()

-- hooks again after a /reload of a wrapped script; open windows refreshed (a week that turned shows empty)
local think = GlobalEvent("ChaosWeeklyChestThink")
function think.onThink()
	W.installHooks()
	for _, p in ipairs(Game.getPlayers()) do
		if W.watch[p:getId()] then
			pcall(send, p, false)
		end
	end
	return true
end
think:interval(60000)
think:register()
