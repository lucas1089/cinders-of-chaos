-- Achievements (client game_achievements, extended opcode ChaosOpcodes.achievements = 250).
-- The list: achievements_data.lua. Pure logic: achievements_core.lua (tests: server/tests/achievements_test.lua).
-- Tables: chaos_achievements, chaos_achievement_stats (server/sql/chaos_achievements.sql; also created at startup).
--
-- ============================================================== API (other scripts)
--   ChaosAchievements.progress(who, key, amount)   add `amount` (default 1) to a counter
--   ChaosAchievements.set(who, key, value)          raise a counter to `value` (counters never go down)
--       who = a Player, a player guid, or {guid = n, name = s}; an offline character's counter is written to the database
--       and its achievements are checked at its next login.
--   ChaosAchievements.has(player, query)            account-wide: query = an achievement id ("rift_t10") or "points:N"
--   ChaosAchievements.unlockedOf(player)            {id = unlock time} of the character
--   ChaosAchievements.pointsOf(player)              character points, account points
--   ChaosAchievements.grant(player, id)             unlock now (staff tools)
--   ChaosAchievements.sendState(player, open)       the window (state, track, list)
--   ChaosAchievements.accountOf(player | account id) {ids, points} of the account
--   ChaosAchievements.syncTrack(player)             reward track: cosmetics.lua grants what the account earned
-- Reward track (server/README.md "Achievements"): account points milestones and category completion give cosmetics of
-- cosmetics_config.lua (source "achievement", points / category) and category titles (achievements_data.lua
-- categoryRewards); the window gets them as "track" (cosmetics_core.lua trackView).
-- A new source is one guarded line in the other script:
--   if ChaosAchievements then ChaosAchievements.progress(player, "my_counter", 1) end
-- plus an entry with stat = "my_counter" in achievements_data.lua.
-- ==============================================================
--
-- Where the counters come from (no edits of the other systems, except one line in monster_tiers.lua):
--   level, paragon, ascended, tutorial, guild, bounty_weeks   login, level up and a 30 s sweep of online players
--   kill event on every player     kills_magic/rare/legendary/tiered, ambush_kills (ChaosTierDead[id].depth, the one line
--                                  in monster_tiers.lua), party_kills, goblin_kills, rat_500, witching_legendary
--   death event                    deaths
--   ChaosLeaderboard.record        wrapped at runtime (like season.lua does): "bounty" -> bounty_done; "rift" ->
--                                  rift_tier/rift_runs/modifiers/flawless (the run from ChaosRift.runOf); "arena1v1" /
--                                  "arena2v2" -> wins and rating (ChaosArena.ratingOf); "siege" -> siege_played/siege_wins
--   ChaosWorldBoss.computeRewards  wrapped: every rewarded player -> wb_kills, wb_<boss>, wb_top (rank 1)
--   ChaosCrafting.apply            wrapped: orbs_used, orb_exalted, orb_binding, ruin_improved, ruin_ruined, quality_max,
--                                  power_found, mods_max (bench and the crafting orbs' use-with; the
--                                  base server's own Upheaval / Fate use-with is not counted)
--   ChaosTreasureGoblin.tick       wrapped: a goblin that escaped after being hit -> goblin_escaped for its attackers
--   onDropLoot (index 2.4)         unique_found, rarity_max, mods_max from the corpse of a kill (before autoloot)
-- Retroactive at login: level, Paragon, ascension, tutorial, guild, bounty contracts (chaos_bounty), the last weekly
-- bounty chest, arena wins and best rating (chaos_arena_ratings).
--
-- Titles: ChaosTitles.register("achievement", ...) (titles.lua) when the name plates are loaded. Class unlocks: the
-- "achievement" method of ChaosClassUnlocksCore is replaced by K.unlockMethod (points or an achievement id); see
-- server/README.md "Achievements". Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end

-- the type behind a shown name (chaos_constants.lua "Monster names"; a renamed rift monster or invader is still its type)
local function typeNameOf(creature)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(creature) or creature:getName()
end
if not ChaosAchievementsCore or not ChaosAchievementsCore.unlockMethod then
	dofile("data/scripts/chaos/achievements_core.lua")
end

ChaosAchievements = ChaosAchievements or {}
local A = ChaosAchievements
local K = ChaosAchievementsCore

A.data = dofile("data/scripts/chaos/achievements_data.lua")
A.index = K.build(A.data)
local index = A.index

local OPCODE = (ChaosOpcodes and ChaosOpcodes.achievements) or 250
local NOTIFY_OPCODE = (ChaosOpcodes and ChaosOpcodes.notifications) or 79
local FLUSH_SECONDS = 30
local CHUNK = 30 -- rows per list message

A.stats = A.stats or {} -- guid -> {stat = value}
A.unlocked = A.unlocked or {} -- guid -> {id = unlock time}
A.dirty = A.dirty or {} -- guid -> {stat = true}
A.accounts = A.accounts or {} -- account id -> {ids, points}

local function log(text)
	print("[ChaosAchievements] " .. text)
end

for _, p in ipairs(index.problems) do
	log("achievements_data.lua: " .. p)
end

-- ---------------------------------------------------------------- storage
local tablesReady = false
local function ensureTables()
	if not tablesReady then
		local ok = true
		for _, q in ipairs(K.sqlCreate()) do
			ok = db.query(q) and ok
		end
		tablesReady = ok and true or false
	end
	return tablesReady
end

local function loadPlayer(guid)
	ensureTables()
	local stats, unlocked = {}, {}
	for _, r in ipairs(Chaos.select("SELECT `stat`, `value` FROM `" .. K.TABLE_STATS .. "` WHERE `player_id` = " .. guid,
		{{"stat", "s"}, {"value", "n"}})) do
		stats[r.stat] = r.value
	end
	for _, r in ipairs(Chaos.select("SELECT `achievement`, `unlocked_at` FROM `" .. K.TABLE_UNLOCKS .. "` WHERE `player_id` = " ..
		guid, {{"achievement", "s"}, {"unlocked_at", "n"}})) do
		unlocked[r.achievement] = r.unlocked_at
	end
	A.stats[guid], A.unlocked[guid], A.dirty[guid] = stats, unlocked, {}
end

local function flush(guid)
	local dirty, stats = A.dirty[guid], A.stats[guid]
	if not dirty or not stats or next(dirty) == nil then
		return
	end
	for key in pairs(dirty) do
		local q = K.sqlSaveStat(guid, key, stats[key] or 0)
		if q then
			db.asyncQuery(q)
		end
	end
	A.dirty[guid] = {}
end

local function account(accountId)
	local acc = A.accounts[accountId]
	if not acc then
		ensureTables()
		local ids = {}
		for _, r in ipairs(Chaos.select(string.format("SELECT DISTINCT a.`achievement` FROM `%s` a INNER JOIN `players` p " ..
			"ON p.`id` = a.`player_id` WHERE p.`account_id` = %d", K.TABLE_UNLOCKS, accountId), {{"achievement", "s"}})) do
			ids[#ids + 1] = r.achievement
		end
		acc = K.accountFromIds(index, ids)
		A.accounts[accountId] = acc
	end
	return acc
end

-- ---------------------------------------------------------------- who
local function online(who)
	if type(who) == "userdata" then
		return who, who:getGuid()
	end
	local guid, name
	if type(who) == "table" then
		guid, name = tonumber(who.guid), who.name
	else
		guid = tonumber(who)
	end
	if not guid then
		return nil, nil
	end
	local p = name and Player(name)
	if p and p:getGuid() == guid then
		return p, guid
	end
	for _, q in ipairs(Game.getPlayers()) do
		if q:getGuid() == guid then
			return q, guid
		end
	end
	return nil, guid
end

-- ---------------------------------------------------------------- unlocking
local function itemName(id)
	local it = ItemType(id)
	return it and it:getId() ~= 0 and it:getName() or ("item " .. tostring(id))
end

local function giveStack(player, id, count)
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

local function giveReward(player, reward)
	if type(reward) ~= "table" then
		return ""
	end
	local inbox = false
	if (reward.gold or 0) > 0 then
		player:setBankBalance(player:getBankBalance() + reward.gold)
	end
	for _, it in ipairs(reward.items or {}) do
		inbox = giveStack(player, it.id, it.count or 1) or inbox
	end
	local o = reward.outfit
	if o then
		for _, look in ipairs({o.female, o.male}) do
			if look then
				if (o.addons or 0) > 0 then
					player:addOutfitAddon(look, o.addons)
				else
					player:addOutfit(look)
				end
			end
		end
	end
	if reward.mount and reward.mount.id then
		player:addMount(reward.mount.id)
	end
	if reward.portal and ChaosTownPortal and ChaosTownPortal.sendState then
		-- a Portal Style window that is open shows the style unlocked at once (open = false: a closed one stays closed);
		-- a moment later, when the unlock is stored
		local pid = player:getId()
		addEvent(function()
			local p = Player(pid)
			if p then
				pcall(ChaosTownPortal.sendState, p, false)
			end
		end, 200)
	end
	return K.rewardText(reward, itemName, Chaos.lang(player)) .. (inbox and Chaos.t(player, " (your backpack was full: see your inbox)") or "")
end

-- a toast with the ACHIEVEMENT UNLOCKED header (notifications.lua ChaosNotify.send; the raw packet when it is not loaded)
local function notify(player, title, text)
	if ChaosNotify and ChaosNotify.send then
		return ChaosNotify.send(player, title, text, "achievement")
	end
	player:sendExtendedOpcode(NOTIFY_OPCODE, json.encode({action = "achievement", message = title .. ": " .. text}))
end

local function checkClassUnlocks(player)
	local U, CK = ChaosClassUnlocks, ChaosClassUnlocksCore
	if not (U and CK and U.isUnlocked and U.grant and CK.autoUnlock and CK.lockedClasses) then
		return
	end
	local facts = {
		level = player:getLevel(),
		storage = function(k) return player:getStorageValue(k) end,
		achievement = function(q) return A.has(player, q) end
	}
	for _, key in ipairs(CK.lockedClasses()) do
		if not U.isUnlocked(player:getAccountId(), key) and CK.autoUnlock(key, facts) == "achievement"
			and U.grant(player:getAccountId(), key, "achievement") then
			local class = CK.config.classes[key]
			player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "Class unlocked for your account: %s.", class and class.name or key))
			notify(player, Chaos.t(player, "Class unlocked"), Chaos.t(player, "%s is open to every character of your account.",
				class and class.name or key))
		end
	end
end

-- unlock one achievement (it must not be unlocked yet); quiet = no toast (the login summary sends one). Returns true and
-- the reward text. The unlock row is written first: when that fails nothing is given or shown (a later check retries),
-- so a relog never finds it locked again and never gives the reward or the toast twice.
local function unlock(player, def, quiet)
	local guid = player:getGuid()
	local unlocked = A.unlocked[guid]
	if not unlocked or unlocked[def.id] then
		return false
	end
	local now = os.time()
	if db.query(K.sqlUnlock(guid, def.id, now)) == false then
		log("unlock " .. def.id .. " of " .. player:getName() .. " not stored: tried again at the next check")
		return false
	end
	unlocked[def.id] = now
	local acc = A.accounts[player:getAccountId()]
	if acc and not acc.ids[def.id] then
		acc.ids[def.id] = true
		acc.points = acc.points + def.points
	end
	local parts = {Chaos.t(player, "Achievement unlocked: %s (+%d points).", def.name, def.points)}
	if def.title then
		parts[#parts + 1] = Chaos.t(player, "Title: %s (pick it in the Achievements window).", def.title)
	end
	local rewardText = ""
	if def.reward then
		local ok, text = pcall(giveReward, player, def.reward)
		parts[#parts + 1] = ok and Chaos.t(player, "Reward: %s.", text) or Chaos.t(player, "The reward could not be given; tell the staff.")
		if ok then
			rewardText = text
		else
			log("reward of " .. def.id .. " for " .. player:getName() .. " failed: " .. tostring(text))
		end
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, table.concat(parts, " "))
	if not quiet then
		notify(player, K.toast(def, rewardText, Chaos.lang(player)))
		if ChaosPack29Vfx then -- pair 29 (switch off: the stock firework)
			ChaosPack29Vfx.celebrate(player:getPosition(), "achievement", CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
		else
			player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
		end
	end
	Chaos.send(player, OPCODE, "unlock", {id = def.id, name = def.name, points = def.points, title = def.title})
	if def.title and ChaosNameplate and ChaosNameplate.refresh then
		pcall(ChaosNameplate.refresh, player)
	end
	return true, rewardText
end

-- check every achievement of an online character; returns the list unlocked now (done.rewards = {[id] = reward text})
function A.evaluate(player, quiet)
	local guid = player:getGuid()
	local stats, unlocked = A.stats[guid], A.unlocked[guid]
	if not stats or not unlocked then
		return {}
	end
	local done = {rewards = {}}
	for _, def in ipairs(K.evaluate(index, stats, unlocked)) do
		local ok, rewardText = unlock(player, def, quiet)
		if ok then
			done[#done + 1] = def
			done.rewards[def.id] = rewardText
		end
	end
	if #done > 0 then
		pcall(checkClassUnlocks, player)
		A.syncTrack(player)
	end
	return done
end

-- the reward track (cosmetics.lua): account points or a completed category may have earned a cosmetic; idempotent
function A.syncTrack(player)
	local M = ChaosCosmetics
	if M and M.sync then
		local ok, err = pcall(M.sync, player)
		if not ok then
			log("reward track sync " .. player:getName() .. ": " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------- public API
local function change(who, key, amount, mode)
	if not K.validKey(key) then
		return false
	end
	local player, guid = online(who)
	if not guid then
		return false
	end
	if player and A.stats[guid] then
		local stats = A.stats[guid]
		local changed
		if mode == "max" then
			changed = K.setMax(stats, key, amount)
		else
			changed = K.add(stats, key, amount)
		end
		if changed then
			A.dirty[guid][key] = true
			A.evaluate(player)
		end
		return changed
	end
	local q = K.sqlOffline(guid, key, amount, mode)
	if q then
		ensureTables()
		db.asyncQuery(q)
	end
	return q ~= nil
end

function A.progress(who, key, amount)
	return change(who, key, amount == nil and 1 or amount, "add")
end

function A.set(who, key, value)
	return change(who, key, value, "max")
end

function A.has(player, query)
	if not player then
		return false
	end
	local accountId = type(player) == "number" and player or player:getAccountId()
	return K.has(account(accountId), query)
end

-- the account's achievements {ids = set, points} (each achievement once, any character); player or account id
function A.accountOf(who)
	local accountId = type(who) == "number" and who or who:getAccountId()
	return account(accountId)
end

function A.unlockedOf(player)
	return A.unlocked[player:getGuid()] or {}
end

function A.pointsOf(player)
	return K.points(index, A.unlockedOf(player)), account(player:getAccountId()).points
end

function A.grant(player, id)
	local def = index.byId[id]
	if not def or not A.unlocked[player:getGuid()] then
		return false
	end
	local ok = unlock(player, def, false)
	if ok then
		A.evaluate(player)
		pcall(checkClassUnlocks, player)
		A.syncTrack(player)
	end
	return ok
end

-- ---------------------------------------------------------------- character state (login, level up, sweep)
local function paragonStart()
	return Chaos.paragon and Chaos.paragon.startLevel or 1000
end

local function isAscended(player)
	local voc = player:getVocation()
	local id = voc:getId()
	local baseOf = Chaos.classes and Chaos.classes.baseOf
	if baseOf and baseOf[id] then
		return baseOf[id] ~= id
	end
	local demo = voc.getDemotion and voc:getDemotion()
	return demo ~= nil and demo:getId() ~= id and demo:getId() ~= 0
end

local function tutorialDone(player)
	local cfg = ChaosNewPlayerConfig
	local base = Chaos.storage and Chaos.storage.newPlayer
	if not base then
		return false
	end
	local offset = cfg and cfg.storage and cfg.storage.stage or 2
	return player:getStorageValue(base + offset) == 100
end

local function countQuery(query, column)
	local ok, rows = pcall(Chaos.select, query, {{column, "n"}})
	return ok and rows[1] and rows[1][column] or 0
end

-- what the character's saved state proves; light = only the in-memory checks (sweep)
local function currentStats(player, light)
	local facts = {
		level = player:getLevel(),
		paragonStart = paragonStart(),
		ascended = isAscended(player),
		tutorialDone = tutorialDone(player),
		guild = player:getGuild() ~= nil
	}
	if not light then
		local guid = player:getGuid()
		facts.bountyDone = countQuery("SELECT COUNT(*) AS `n` FROM `chaos_bounty` WHERE `status` = 1 AND `player_id` = " .. guid, "n")
		facts.arena = {}
		local ok, rows = pcall(Chaos.select, "SELECT `mode`, `wins`, `best` FROM `chaos_arena_ratings` WHERE `player_id` = " .. guid,
			{{"mode", "s"}, {"wins", "n"}, {"best", "n"}})
		for _, r in ipairs(ok and rows or {}) do
			facts.arena[r.mode] = {wins = r.wins, best = r.best}
		end
	end
	local s = K.retroStats(facts)
	s.bounty_weeks = nil -- counted from the week key below (live and retroactive)
	if light then
		s.bounty_done = nil
	end
	return s
end

-- the weekly bounty chest: the storage holds the week key of the last chest; a new key = one more chest
local function checkBountyWeek(player, stats, dirty)
	local key = Chaos.storage and Chaos.storage.bountyWeekBonus
	local week = key and player:getStorageValue(key) or -1
	if week > 0 and week > (stats.bounty_week_last or 0) then
		stats.bounty_week_last = week
		stats.bounty_weeks = (stats.bounty_weeks or 0) + 1
		dirty.bounty_week_last, dirty.bounty_weeks = true, true
	end
end

function A.refreshState(player, light, quiet)
	local guid = player:getGuid()
	local stats, dirty = A.stats[guid], A.dirty[guid]
	if not stats then
		return {}
	end
	for k, v in pairs(currentStats(player, light)) do
		if K.setMax(stats, k, v) then
			dirty[k] = true
		end
	end
	checkBountyWeek(player, stats, dirty)
	return A.evaluate(player, quiet)
end

-- ---------------------------------------------------------------- the window
local function titleInfo(player)
	local T, N = ChaosTitles, ChaosNameplate
	if not (T and T.of and N and N.pick) then
		return false, nil
	end
	local ok, list = pcall(T.of, player)
	if not ok then
		return false, nil
	end
	local active = N.pick(list, N.choice and N.choice[player:getGuid()])
	-- every title the character holds (leaderboards, siege, seasons, staff, achievements): the window's selector
	local held = {}
	for _, t in ipairs(list) do
		held[#held + 1] = {text = t.text}
	end
	return true, active and active.text or nil, held
end

-- the reward track of the window (cosmetics_core.lua trackView): account points milestones and category completion,
-- each with its cosmetic and whether the account owns it. Nothing while cosmetics.lua is not loaded.
function A.sendTrack(player)
	local M, C = ChaosCosmetics, ChaosCosmeticsCore
	if not (M and M.ownedOf and M.config and C and C.trackView) then
		return
	end
	local ok, err = pcall(function()
		local acc = account(player:getAccountId())
		Chaos.send(player, OPCODE, "track", C.trackView(M.config, acc.points, M.ownedOf(player:getAccountId()),
			K.categoryTrack(index, acc.ids)))
	end)
	if not ok then
		log("track " .. player:getName() .. ": " .. tostring(err))
	end
end

function A.sendState(player, open)
	local guid = player:getGuid()
	if not A.unlocked[guid] then
		return
	end
	local unlocked, stats = A.unlocked[guid], A.stats[guid]
	local points, accPoints = A.pointsOf(player)
	local count = 0
	for _ in pairs(unlocked) do
		count = count + 1
	end
	local titlesOn, active, held = titleInfo(player)
	Chaos.send(player, OPCODE, "state", {
		open = open and true or false,
		points = points, accountPoints = accPoints, maxPoints = K.maxPoints(index),
		unlocked = count, total = #index.list,
		categories = K.categorySummary(index, unlocked, Chaos.lang(player)),
		recent = K.recent(index, unlocked, 5),
		titles = K.titlesOf(index, unlocked),
		titlesOn = titlesOn, activeTitle = active or "", heldTitles = held or {}
	})
	A.sendTrack(player)
	local rows = K.view(index, stats, unlocked, itemName, Chaos.lang(player))
	for i = 1, #rows, CHUNK do
		local part = {}
		for j = i, math.min(#rows, i + CHUNK - 1) do
			part[#part + 1] = rows[j]
		end
		Chaos.send(player, OPCODE, "list", {first = i == 1, last = i + CHUNK > #rows, rows = part})
	end
end

-- ---------------------------------------------------------------- hooks into other systems
-- ChaosLeaderboard.record(board, who, value, mode)
local function onRecord(board, who, value)
	if board == "bounty" then
		A.progress(who, "bounty_done", 1)
		local player = online(who)
		if player then
			-- the weekly chest is given right after the record call
			addEvent(function(cid)
				local p = Player(cid)
				if p then
					A.refreshState(p, true)
				end
			end, 200, player:getId())
		end
	elseif board == "rift" then
		local tier = math.floor(tonumber(value) or 0)
		A.set(who, "rift_tier", tier)
		A.progress(who, "rift_runs", 1)
		local player = online(who)
		local run = player and ChaosRift and ChaosRift.runOf and ChaosRift.runOf[player:getId()]
		if run then
			local mods = run.key and run.key.mods or {}
			for _, m in ipairs(mods) do
				if m.key then
					A.progress(player, "rift_mod_" .. m.key, 1)
				end
			end
			if #mods >= 3 then
				A.progress(player, "rift_three", 1)
			end
			local inside = 0
			for _ in pairs(run.players or {}) do
				inside = inside + 1
			end
			if run.size and inside >= run.size and (run.deaths or 0) == 0 then -- rift lives: nobody fell
				A.progress(player, "rift_flawless", 1)
			end
		end
	elseif board == "arena1v1" or board == "arena2v2" then
		local mode = board:sub(6)
		local _, guid = online(who)
		A.set(who, board .. "_rating", value)
		local r = guid and ChaosArena and ChaosArena.ratingOf and ChaosArena.ratingOf(guid, mode)
		if r then
			A.set(who, board .. "_wins", r.wins or 0)
			A.set(who, board .. "_rating", r.best or r.rating or 0)
		end
	elseif board == "siege" then
		A.progress(who, "siege_played", 1)
		local _, guid = online(who)
		local S = ChaosSiege
		local st = S and S.state
		local p = guid and st and st.players and st.players[guid]
		local br = p and st.brackets and st.brackets[p.bracket]
		if br and br.winner and br.winner == p.guildId then
			A.progress(who, "siege_wins", 1)
		end
	end
end

local function onBossShares(shares, boss)
	local name = (boss and boss.name or ""):lower()
	local stat
	for part, s in pairs(index.bossStats) do
		if name:find(part, 1, true) then
			stat = s
		end
	end
	for _, s in ipairs(shares or {}) do
		local who = {guid = s.guid, name = s.name}
		A.progress(who, "wb_kills", 1)
		if stat then
			A.progress(who, stat, 1)
		end
		if s.rank == 1 then
			A.progress(who, "wb_top", 1)
		end
	end
end

local function itemPlayer(item)
	local ok, top = pcall(function() return item:getTopParent() end)
	if ok and top and top.isPlayer and top:isPlayer() then
		return top
	end
	return nil
end

local function onCraft(orbKey, res)
	local item = type(res) == "table" and res.item
	local player = item and itemPlayer(item)
	if not player then
		return
	end
	A.progress(player, "orbs_used", 1)
	if orbKey == "exalted" then
		A.progress(player, "orb_exalted", 1)
	elseif orbKey == "binding" then
		A.progress(player, "orb_binding", 1)
	elseif orbKey == "ruin" then
		if res.outcome == "improve" then
			A.progress(player, "ruin_improved", 1)
		elseif res.outcome == "ruin" then
			A.progress(player, "ruin_ruined", 1)
		end
	elseif orbKey == "whetstone" and res.quality then
		A.set(player, "quality_max", res.quality)
	end
	local C = ChaosCrafting
	if C and C.readMods then
		local ok, mods = pcall(C.readMods, item)
		if ok and type(mods) == "table" then
			A.set(player, "mods_max", #mods)
			for _, m in ipairs(mods) do
				if m.power then
					A.set(player, "power_found", 1) -- an item of the player's with a legendary power
				end
			end
		end
	end
end

function A.installHooks()
	local LB = ChaosLeaderboard
	if LB and LB.record and not LB.achievementsWrapped then
		local original = LB.record
		LB.record = function(board, who, value, mode)
			local entry = original(board, who, value, mode)
			local ok, err = pcall(onRecord, board, who, value)
			if not ok then
				log("leaderboard hook: " .. tostring(err))
			end
			return entry
		end
		LB.achievementsWrapped = true
	end
	local W = ChaosWorldBoss
	if W and W.computeRewards and not W.achievementsWrapped then
		local original = W.computeRewards
		W.computeRewards = function(shares, r, boss, pool, rng, pityOf)
			local out = original(shares, r, boss, pool, rng, pityOf)
			local ok, err = pcall(onBossShares, shares, boss)
			if not ok then
				log("world boss hook: " .. tostring(err))
			end
			return out
		end
		W.achievementsWrapped = true
	end
	local C = ChaosCrafting
	if C and C.apply and not C.achievementsWrapped then
		local original = C.apply
		C.apply = function(orbKey, item, opts)
			local ok, res = original(orbKey, item, opts)
			if ok then
				local fine, err = pcall(onCraft, orbKey, res)
				if not fine then
					log("crafting hook: " .. tostring(err))
				end
			end
			return ok, res
		end
		C.achievementsWrapped = true
	end
	local TG = ChaosTreasureGoblin
	if TG and TG.tick and TG.alive and not TG.achievementsWrapped then
		local original = TG.tick
		TG.tick = function(id)
			local st = TG.alive[id]
			local wasThere = Monster(id) ~= nil
			original(id)
			if st and wasThere and TG.alive[id] == nil and Monster(id) == nil and next(st.attackers or {}) then
				for pid in pairs(st.attackers) do
					local p = Player(pid)
					if p then
						pcall(A.progress, p, "goblin_escaped", 1)
					end
				end
			end
		end
		TG.achievementsWrapped = true
	end
	-- name plate titles
	if ChaosTitles and ChaosTitles.register then
		ChaosTitles.register("achievement", function(player)
			local list = K.titlesOf(index, A.unlocked[player:getGuid()])
			-- category completion titles of the reward track (account-wide)
			local ok, acc = pcall(account, player:getAccountId())
			if ok and acc then
				for _, t in ipairs(K.categoryTitles(index, acc.ids)) do
					list[#list + 1] = t
				end
			end
			return list
		end)
	end
	-- class unlock method "achievement" (points or an achievement id); the classes' configured methods stay as they are
	if ChaosClassUnlocksCore and ChaosClassUnlocksCore.registerMethod then
		ChaosClassUnlocksCore.registerMethod("achievement", K.unlockMethod(index))
	end
end
A.installHooks()

-- ---------------------------------------------------------------- events
local function afterKill(pid, mid, tier)
	local player = Player(pid)
	if not player then
		return
	end
	local dead = ChaosTierDead and ChaosTierDead[mid]
	if dead and (dead.depth or 0) > 0 then
		A.progress(player, "ambush_kills", 1)
		if tier == "legendary" then
			A.progress(player, "ambush_legendary", 1)
		end
	end
end

local kill = CreatureEvent("ChaosAchievementsKill")
function kill.onKill(player, target)
	if not player:isPlayer() or not target or not target:isMonster() or target:getMaster() then
		return true
	end
	local ok, err = pcall(function()
		local name = typeNameOf(target):lower()
		local tier = ChaosTierOf and ChaosTierOf(target) or "normal"
		-- pack combat (pace.lua): a paced monster counts 1 / its kill-goal factor (summed per counter), so the kill
		-- counts take as long as before; ambushes and goblins already come at the old rate
		local function credit(key)
			return ChaosPace and ChaosPace.killCredit and ChaosPace.killCredit(player, target, key) or 1
		end
		local function add(key)
			local n = credit(key)
			if n > 0 then
				A.progress(player, key, n)
			end
		end
		if tier == "magic" or tier == "rare" or tier == "legendary" then
			add("kills_" .. tier)
			add("kills_tiered")
			if tier == "legendary" and tonumber(os.date("%H")) == 0 then
				add("witching_legendary")
			end
		end
		if name == "treasure goblin" or (ChaosTreasureGoblin and ChaosTreasureGoblin.isGoblinName
			and ChaosTreasureGoblin.isGoblinName(name)) then
			A.progress(player, "goblin_kills", 1)
		elseif name == "rat" and player:getLevel() >= 500 then
			A.progress(player, "rat_500", 1)
		end
		local party = player:getParty()
		if party and #(party:getMembers() or {}) >= 1 then
			add("party_kills")
		end
		addEvent(afterKill, 50, player:getId(), target:getId(), tier)
	end)
	if not ok then
		log("kill: " .. tostring(err))
	end
	return true
end
kill:register()

local death = CreatureEvent("ChaosAchievementsDeath")
function death.onDeath(creature)
	if creature:isPlayer() then
		pcall(A.progress, creature, "deaths", 1)
	end
	return true
end
death:register()

local advance = CreatureEvent("ChaosAchievementsAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		pcall(A.refreshState, player, true)
	end
	return true
end
advance:register()

-- the unlocks of the quiet login check: one toast (achievements_core.lua K.summaryToast) with names, points and rewards
local function summaryToast(player, list)
	local title, text = K.summaryToast(list, list.rewards, Chaos.lang(player))
	if title then
		notify(player, title, text)
	end
end
A.summaryToast = summaryToast

local login = CreatureEvent("ChaosAchievementsLogin")
function login.onLogin(player)
	for _, e in ipairs({"ChaosAchievementsKill", "ChaosAchievementsDeath", "ChaosAchievementsAdvance",
		"ChaosAchievementsLogout", "ChaosAchievementsExtended"}) do
		player:registerEvent(e)
	end
	A.installHooks() -- again after a /reload of a hooked script
	local guid = player:getGuid()
	local ok, err = pcall(loadPlayer, guid)
	if not ok then
		log("load " .. player:getName() .. ": " .. tostring(err))
		return true
	end
	A.accounts[player:getAccountId()] = nil
	-- retroactive: what the saved character already proves, checked quietly; one toast a few seconds later
	local okRetro, list = pcall(A.refreshState, player, false, true)
	if okRetro and #list > 0 then
		addEvent(function(cid, names)
			local p = Player(cid)
			if p then
				summaryToast(p, names)
			end
		end, 4000, player:getId(), list)
	elseif not okRetro then
		log("retroactive check " .. player:getName() .. ": " .. tostring(list))
	end
	return true
end
login:register()

local logout = CreatureEvent("ChaosAchievementsLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	flush(guid)
	A.stats[guid], A.unlocked[guid], A.dirty[guid] = nil, nil, nil
	return true
end
logout:register()

local ext = CreatureEvent("ChaosAchievementsExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	local action = type(msg) == "table" and msg.action
	if action == "open" or action == "get" then
		A.sendState(player, action == "open")
	elseif action == "title" then
		-- the title selector: {action = "title", data = {title = "auto" | "none" | <title text>}} (nameplate.lua)
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "achievements.title", 500) then
			return
		end
		local title = type(msg.data) == "table" and msg.data.title
		if ChaosNameplate and ChaosNameplate.setTitle and type(title) == "string" then
			ChaosNameplate.setTitle(player, title:sub(1, 60))
		end
	end
end
ext:register()

-- loot of a kill: uniques, rarity, modifiers (before the base autoloot takes it out of the corpse)
local function scanItem(owner, item, best)
	local okU, unique = pcall(function() return item:getCustomAttribute("chaos_unique") end)
	if okU and unique ~= nil then
		A.progress(owner, "unique_found", 1)
	end
	local okR, rarity = pcall(function() return tonumber(item:getCustomAttribute("rarity")) end)
	rarity = okR and rarity or 0
	if rarity > best.rarity and rarity <= 15 then
		best.rarity = rarity
	end
	if rarity >= 5 and ChaosCrafting and ChaosCrafting.readMods then
		local okM, mods = pcall(ChaosCrafting.readMods, item)
		if okM and type(mods) == "table" then
			if rarity >= 13 and #mods > best.mods then
				best.mods = #mods
			end
			for _, m in ipairs(mods) do
				if m.power then
					best.power = true
				end
			end
		end
	end
end

local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	local ok, err = pcall(function()
		if not corpse or not corpse:getType():isContainer() then
			return
		end
		local owner = Player(corpse:getCorpseOwner())
		if not owner or not A.stats[owner:getGuid()] then
			return
		end
		local best = {rarity = 0, mods = 0, power = false}
		for _, item in ipairs(corpse:getItems()) do
			scanItem(owner, item, best)
			if item:isContainer() then
				for _, inner in ipairs(item:getItems()) do
					scanItem(owner, inner, best)
				end
			end
		end
		if best.rarity > 0 then
			A.set(owner, "rarity_max", best.rarity)
		end
		if best.mods > 0 then
			A.set(owner, "mods_max", best.mods)
		end
		if best.power then
			A.set(owner, "power_found", 1)
		end
	end)
	if not ok then
		log("loot: " .. tostring(err))
	end
end
drop:register(2.4)

-- every 30 s: save the counters, sweep the online characters (guild joined, tutorial finished, weekly bounty chest)
local think = GlobalEvent("ChaosAchievementsThink")
function think.onThink(interval)
	for _, player in ipairs(Game.getPlayers()) do
		if A.stats[player:getGuid()] then
			pcall(A.refreshState, player, true)
		end
	end
	for guid in pairs(A.dirty) do
		flush(guid)
	end
	return true
end
think:interval(FLUSH_SECONDS * 1000)
think:register()

local shutdown = GlobalEvent("ChaosAchievementsShutdown")
function shutdown.onShutdown()
	for guid in pairs(A.dirty) do
		flush(guid)
	end
	return true
end
shutdown:register()

local startup = GlobalEvent("ChaosAchievementsStartup")
function startup.onStartup()
	ensureTables()
	A.installHooks() -- the hooked scripts may load after this one
	log(string.format("%d achievements (%d points), opcode %d%s%s", #index.list, K.maxPoints(index), OPCODE,
		ChaosTitles and ", titles on" or "", ChaosClassUnlocksCore and ", class unlock method registered" or ""))
	return true
end
startup:register()

-- ---------------------------------------------------------------- commands

-- staff: /achievements grant <id> | stat <key> <value> | add <key> <amount> | reset   (on yourself)
local gm = TalkAction("/achievements")
function gm.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return true
	end
	local guid = player:getGuid()
	local cmd, a, b = param:match("^%s*(%w+)%s*([%w_]*)%s*(%-?%d*)")
	-- unlocks and progress pay achievement rewards: an administrator only, logged (docs/GM_HANDBOOK.md section 2)
	if not Chaos.staffCommand(player, words, param, cmd == "grant" or cmd == "add") then
		return false
	end
	if cmd == "grant" and index.byId[a] then
		player:sendTextMessage(MESSAGE_INFO_DESCR, A.grant(player, a) and ("Granted " .. a .. ".") or "Already unlocked.")
	elseif (cmd == "stat" or cmd == "add") and K.validKey(a) and tonumber(b) then
		if cmd == "stat" then
			A.set(player, a, tonumber(b))
		else
			A.progress(player, a, tonumber(b))
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, a .. " = " .. tostring(A.stats[guid][a]))
	elseif cmd == "reset" then
		db.query("DELETE FROM `" .. K.TABLE_UNLOCKS .. "` WHERE `player_id` = " .. guid)
		db.query("DELETE FROM `" .. K.TABLE_STATS .. "` WHERE `player_id` = " .. guid)
		A.stats[guid], A.unlocked[guid], A.dirty[guid] = {}, {}, {}
		A.accounts[player:getAccountId()] = nil
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Achievements and counters of this character cleared (relog for the retroactive check).")
	else
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Usage: /achievements grant <id> | stat <key> <value> | add <key> <n> | reset")
	end
	return false
end
gm:separator(" ")
gm:register()
