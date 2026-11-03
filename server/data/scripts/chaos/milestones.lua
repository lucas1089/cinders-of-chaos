-- Level milestones (O378; server/README.md "Level milestones (O378)"; rules milestones_core.lua, numbers
-- milestones_config.lua; tests/milestones_test.lua). Every 100 levels from 800 to 2200: the Milestone Cache (orbs, once
-- per character, only for milestones reached from now on), the LEVEL MILESTONE toast (game_chaosnotify kind
-- "milestone") and one short server broadcast. The title, the points and the cosmetics are the level achievements'
-- (achievements_data.lua category "milestones"); the challenge and the next milestone are Next Goals lines.
-- No opcode of its own, no table: one player storage (cfg.storage).
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/advance, Player:getLevel/getName/getStorageValue/
-- setStorageValue/getInbox/addItem/getItemCount/sendTextMessage, Container:addItem, Chaos.broadcast, ChaosNotify.send.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosI18n then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosMilestonesCore or not ChaosMilestonesCore.plan then
	dofile("data/scripts/chaos/milestones_core.lua")
end

ChaosMilestones = ChaosMilestones or {}
local M = ChaosMilestones
local K = ChaosMilestonesCore
local cfg = dofile("data/scripts/chaos/milestones_config.lua")
M.cfg = cfg
local KEY = cfg.storage

local function log(text)
	print("[Chaos milestones] " .. text)
end

local function try(label, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		log(label .. ": " .. tostring(err))
	end
	return ok
end

local function achData()
	local A = ChaosAchievements
	if A and A.data then
		return A.data
	end
	M.ach = M.ach or dofile("data/scripts/chaos/achievements_data.lua")
	return M.ach
end

local function isStaff(player)
	return player:getGroup():getId() >= (cfg.staffGroup or 4)
end

local function itemName(id, fallback)
	local it = ItemType and ItemType(id)
	return (it and it:getId() ~= 0 and it:getName()) or fallback or ("item " .. tostring(id))
end

-- the orbs: backpack first, the rest to the inbox (as the achievement rewards). Returns true when the inbox was used.
local function giveCache(player, m)
	local inbox = false
	for _, it in ipairs(K.cacheItems(cfg, m)) do
		local rest = it.count - Chaos.giveItem(player, it.id, it.count)
		if rest > 0 then
			inbox = true
			local box = player:getInbox()
			while box and rest > 0 do
				local n = math.min(rest, 100)
				box:addItem(it.id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
				rest = rest - n
			end
		end
	end
	return inbox
end

local function cacheText(player, m)
	local parts = {}
	for _, it in ipairs(K.cacheItems(cfg, m)) do
		parts[#parts + 1] = it.count .. " " .. itemName(it.id, it.name)
	end
	return table.concat(parts, ", ")
end

local function toast(player, m, inbox)
	local tr = function(key, ...)
		return Chaos.t(player, key, ...)
	end
	local nextM = K.next(cfg, m.level)
	local header, text = K.toast(cfg, m, K.titleOf(achData(), m.level), cacheText(player, m), nextM and nextM.level, tr)
	if inbox then
		text = text .. " " .. Chaos.t(player, cfg.texts.inbox)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, header .. ": " .. text)
	if ChaosNotify and ChaosNotify.send then
		ChaosNotify.send(player, header, text, "milestone")
	end
end

local function broadcast(player, m)
	local b = cfg.broadcast or {}
	if not b.enabled or m.level < (b.minLevel or 0) or Chaos.isTester(player) then
		return
	end
	local title = K.titleOf(achData(), m.level) or ""
	Chaos.broadcast(MESSAGE_EVENT_ADVANCE, cfg.texts.broadcast, player:getName(), m.level, title)
end

-- apply a plan: the mark first (a crash after it never gives a cache twice), then the caches, one toast and one
-- broadcast for the highest milestone of this advance
local function apply(player, plan)
	player:setStorageValue(KEY, plan.paid)
	local inbox = false
	for _, m in ipairs(plan.pay) do
		inbox = giveCache(player, m) or inbox
		log(string.format("%s reached level %d: cache %s", player:getName(), m.level, K.cacheText(cfg, m)))
	end
	if plan.top then
		toast(player, plan.top, inbox)
		broadcast(player, plan.top)
	end
end

function M.onLogin(player)
	player:registerEvent("ChaosMilestonesAdvance")
	local plan = K.plan(cfg, {paid = player:getStorageValue(KEY), level = player:getLevel(), login = true})
	if plan.paid ~= player:getStorageValue(KEY) then
		player:setStorageValue(KEY, plan.paid)
	end
end

function M.onAdvance(player, oldLevel, newLevel)
	if not cfg.enabled then
		return
	end
	local plan = K.plan(cfg, {paid = player:getStorageValue(KEY), level = newLevel, oldLevel = oldLevel,
		staff = isStaff(player)})
	if plan.paid ~= player:getStorageValue(KEY) or #plan.pay > 0 then
		apply(player, plan)
	end
end

local login = CreatureEvent("ChaosMilestonesLogin")
function login.onLogin(player)
	try("login", M.onLogin, player)
	return true
end
login:type("login")
login:register()

local advance = CreatureEvent("ChaosMilestonesAdvance")
function advance.onAdvance(player, skill, oldLevel, newLevel)
	if skill == SKILL_LEVEL and newLevel > oldLevel then
		try("advance", M.onAdvance, player, oldLevel, newLevel)
	end
	return true
end
advance:type("advance")
advance:register()
