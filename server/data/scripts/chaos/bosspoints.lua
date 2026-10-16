-- Boss passive points: the first kill of each major boss (bosspoints_config.lua: the five world bosses, the Ascension
-- Trial's Warden and four endgame bosses) gives the character +1 passive tree point, once per boss and character.
--
-- Points: one player storage flag per boss (storageBase + id). ChaosBossPoints.count(player) is added to the tree's
-- point budget by passivetree.lua (totalPoints), next to the level points and passiveExtraPoints, so the respec
-- (respec.lua), the build codes (buildshare.lua) and the free over-budget refund at login all see them; a reset never
-- touches them. The Paragon track (paragon.lua) is separate: its points come from levels above 1000 only.
--
-- Credit (as the bestiary and the bounty board, through ChaosBounty.credit): every player in the boss's damage map
-- (summons count for their master), the last hit and the most damage, plus the party members of each of them within
-- partyRange tiles on the same floor. Players who logged out or died before the kill are not credited (the engine
-- has no player for them any more).
--
-- Old kills: at the first login after this feature (and again whenever retroVersion is raised) the character's
-- chaos_bestiary rows, the world boss stats of chaos_achievement_stats and the Ascension Trial stage are checked once
-- and the missing points are given (a table that does not exist is skipped).
--
-- Protocol (passive tree opcode ChaosOpcodes.passivetree, sent with every sendPoints of passivetree.lua):
--   server -> client  {"action":"bossPoints","data":{got, total, label, bosses = [{id, name, label, done}]}}
--   toast: notifications opcode {"action":"bosspoints","message":".."} (client game_chaosnotify)
-- Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/bosspoints_core.lua")

Chaos.bossPoints = dofile("data/scripts/chaos/bosspoints_config.lua")
local cfg = Chaos.bossPoints
local K = ChaosBossPointsCore
local OPCODE = ChaosOpcodes.passivetree
local BASE = cfg.storageBase

ChaosBossPoints = ChaosBossPoints or {}
local B = ChaosBossPoints
B.index = K.build(cfg)
for _, problem in ipairs(B.index.problems) do
	print("[Chaos boss points] config: " .. problem)
end

local function flagOf(player)
	return function(id)
		return player:getStorageValue(BASE + id) == 1
	end
end

function B.has(player, id)
	return player:getStorageValue(BASE + id) == 1
end

function B.count(player)
	if not cfg.enabled or not player then
		return 0
	end
	return K.count(B.index, flagOf(player))
end

function B.state(player)
	return K.state(B.index, flagOf(player))
end

function B.sendInfo(player)
	if cfg.enabled and player then
		Chaos.send(player, OPCODE, "bossPoints", B.state(player))
	end
end

local function toast(player, message)
	if ChaosOpcodes.notifications and json then
		player:sendExtendedOpcode(ChaosOpcodes.notifications, json.encode({action = "bosspoints", message = message}))
	end
end

-- the tree window shows the new free points and the boss list (passivetree.lua sendPoints also sends bossPoints)
local function refresh(player)
	local T = ChaosPassiveTree and ChaosPassiveTree.internal
	if T and T.sendPoints then
		T.sendPoints(player)
	else
		B.sendInfo(player)
	end
end

-- gives the point of `boss` if the character does not own it yet; returns true when it was given
function B.grant(player, boss, quiet)
	if not cfg.enabled or not player or not boss or B.has(player, boss.id) then
		return false
	end
	player:setStorageValue(BASE + boss.id, 1)
	if not quiet then
		local got = B.count(player)
		local text = Chaos.t(player, "First kill of %s: +1 passive point! %s.", boss.name, K.label(got, B.index.total))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		toast(player, text)
		if ChaosPack29Vfx then -- pair 29 (switch off: the stock firework)
			ChaosPack29Vfx.celebrate(player:getPosition(), "boss", CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
		else
			player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_GREEN)
		end
		refresh(player)
	end
	return true
end

-- ---------------------------------------------------------------- kills
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

local function typeName(creature)
	local mType = creature.getType and creature:getType()
	local name = mType and mType.name and mType:name()
	return name or creature:getName()
end

function B.onKill(creature, killer, mostDamageKiller)
	if not cfg.enabled then
		return
	end
	local boss = K.isBoss(B.index, typeName(creature))
	if not boss then
		return
	end
	if ChaosPack29Vfx then -- pair 29 (switch off: nothing): the boss blast on the corpse
		pcall(ChaosPack29Vfx.bossDeath, creature:getPosition(), creature:getMaxHealth())
	end
	local ids = {}
	for id in pairs(creature:getDamageMap() or {}) do
		ids[#ids + 1] = id
	end
	local function idOf(p) return p:getId() end
	local killers = K.killers(ids, function(id) return playerOf(Creature(id)) end,
		{playerOf(killer), playerOf(mostDamageKiller)}, idOf)
	if #killers == 0 then
		return
	end
	local credited = K.credit(killers, function(p)
		local party = p:getParty()
		if not party then
			return nil
		end
		local members = party:getMembers()
		members[#members + 1] = party:getLeader()
		return members
	end, function(p) return p:getPosition() end, cfg.partyRange or 30, idOf)
	for _, p in ipairs(credited) do
		B.grant(p, boss)
	end
end

local death = CreatureEvent("ChaosBossPointsDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	local ok, err = pcall(B.onKill, creature, killer, mostDamageKiller)
	if not ok then
		print("[Chaos boss points] kill: " .. tostring(err))
	end
	return true
end
death:register()

-- only the listed bosses get the death event (map spawns and Game.createMonster: world boss, Trial, invasion, tower)
local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if cfg.enabled and not self:getMaster() and K.isBoss(B.index, typeName(self)) then
		self:registerEvent("ChaosBossPointsDeath")
	end
	return true
end
spawn:register()

-- ---------------------------------------------------------------- old kills (once per character)
local tableCache = {}
local function hasTable(name)
	if tableCache[name] == nil then
		local rows = Chaos.select("SELECT COUNT(*) AS `n` FROM information_schema.tables WHERE table_schema = DATABASE() " ..
			"AND table_name = " .. db.escapeString(name), {{"n", "n"}})
		tableCache[name] = rows[1] ~= nil and (rows[1].n or 0) > 0
	end
	return tableCache[name]
end

local function quoted(list)
	local out = {}
	for _, v in ipairs(list) do
		out[#out + 1] = db.escapeString(v)
	end
	return table.concat(out, ", ")
end

function B.sources(player)
	local guid = player:getGuid()
	local names, stats = {}, {}
	for _, boss in ipairs(B.index.list) do
		if boss.retro.bestiary then
			names[#names + 1] = boss.key
		end
		if boss.retro.stat then
			stats[#stats + 1] = boss.retro.stat
		end
	end
	local sources = {bestiary = {}, stats = {}, storage = function(key) return player:getStorageValue(key) end}
	if #names > 0 and hasTable("chaos_bestiary") then
		for _, row in ipairs(Chaos.select("SELECT `monster`, `kills` FROM `chaos_bestiary` WHERE `player_id` = " .. guid ..
				" AND `monster` IN (" .. quoted(names) .. ")", {{"monster", "s"}, {"kills", "n"}})) do
			sources.bestiary[row.monster:lower()] = row.kills
		end
	end
	if #stats > 0 and hasTable("chaos_achievement_stats") then
		for _, row in ipairs(Chaos.select("SELECT `stat`, `value` FROM `chaos_achievement_stats` WHERE `player_id` = " .. guid ..
				" AND `stat` IN (" .. quoted(stats) .. ")", {{"stat", "s"}, {"value", "n"}})) do
			sources.stats[row.stat] = row.value
		end
	end
	return sources
end

function B.retro(player)
	local version = cfg.retroVersion or 1
	if player:getStorageValue(BASE) >= version then
		return 0
	end
	local given, names = 0, {}
	for _, id in ipairs(K.retroIds(B.index, B.sources(player))) do
		local boss = B.index.byId[id]
		if B.grant(player, boss, true) then
			given = given + 1
			names[#names + 1] = boss.name
		end
	end
	player:setStorageValue(BASE, version)
	if given > 0 then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player,
			"Boss passive points: +%d for bosses you had already slain (%s). %s.", given, table.concat(names, ", "),
			K.label(B.count(player), B.index.total)))
	end
	return given
end

local login = CreatureEvent("ChaosBossPointsLogin")
function login.onLogin(player)
	if cfg.enabled then
		local ok, err = pcall(B.retro, player)
		if not ok then
			print("[Chaos boss points] old kills of " .. player:getName() .. ": " .. tostring(err))
		end
	end
	return true
end
login:type("login")
login:register()
