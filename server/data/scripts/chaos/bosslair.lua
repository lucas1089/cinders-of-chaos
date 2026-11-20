-- Boss lairs (bosslair_config.lua, pure logic in bosslair_core.lua; server/README.md "Talath's lair (O616)").
-- A lair is a small planned area with a boss's map spawn (server/tools/areaplan/rooms/, install step contentareas).
-- This file is its way in and its gate:
--   * at startup a magic forcefield (action id cfg.aid) goes on the lair's `portal` tile in its hunt, only while the
--     lair is open (config.lua chaosClientPair >= the lair's pair); a forcefield of ours on a closed lair is removed;
--   * stepping on it sends a player of minLevel or more to the lair's arrival; the way back is the plan's exit portal;
--   * the engine's spawn of the boss of a closed lair is refused (EventCallback onSpawn returns false, as dungeons.lua
--     does for a running dungeon), so a client without the boss's look never meets it.
-- Assumed engine API (TFS 1.4): Tile (getGround, getItems), Game.createItem, Item (getActionId, setActionId,
-- setAttribute, remove), MoveEvent stepin by action id, EventCallback onSpawn, Player (getLevel, teleportTo,
-- sendTextMessage), Position:sendMagicEffect. Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/bosslair_core.lua")

Chaos.bossLairConfig = Chaos.bossLairConfig or dofile("data/scripts/chaos/bosslair_config.lua")
local cfg = Chaos.bossLairConfig
local L = ChaosBossLairCore

ChaosBossLair = ChaosBossLair or {}
local X = ChaosBossLair
-- the recorded client pair, read once at load; tests set it by hand
if X.pair == nil then
	X.pair = L.recordedPair() or 0
end

local function log(text)
	print("[Chaos boss lair] " .. text)
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

local function t(player, text, ...)
	if Chaos.t then
		return Chaos.t(player, text, ...)
	end
	return select("#", ...) > 0 and string.format(text, ...) or text
end

local function itemAt(pos)
	local tile = Tile(P(pos))
	for _, it in ipairs(tile and tile:getItems() or {}) do
		if it:getActionId() == cfg.aid then
			return it, tile
		end
	end
	return nil, tile
end

local function same(a, b)
	return a.x == b.x and a.y == b.y and a.z == b.z
end

-- the lair whose portal stands on a position
function X.lairAt(pos)
	for _, lair in ipairs(cfg.lairs or {}) do
		if same(lair.portal, pos) then
			return lair
		end
	end
	return nil
end

-- puts the portal of an open lair on its tile, takes the portal of a closed one away. Returns "placed", "kept",
-- "removed", "closed" or nil with the reason
function X.placePortal(lair)
	local it, tile = itemAt(lair.portal)
	if not L.open(lair, X.pair) then
		if it then
			it:remove()
			return "removed"
		end
		return "closed"
	end
	if it then
		return "kept"
	end
	if not tile or not tile:getGround() then
		return nil, string.format("%s: no tile at %d,%d,%d (run install_all.py --only contentareas)", lair.key, lair.portal.x,
			lair.portal.y, lair.portal.z)
	end
	local arrival = L.arrival(lair)
	local atile = arrival and Tile(P(arrival))
	if not atile or not atile:getGround() then
		return nil, string.format("%s: the lair is not on the map (run install_all.py --only contentareas)", lair.key)
	end
	it = Game.createItem(cfg.portalItem or 1387, 1, P(lair.portal))
	if not it then
		return nil, lair.key .. ": the portal could not be created"
	end
	it:setActionId(cfg.aid)
	if lair.text and ITEM_ATTRIBUTE_DESCRIPTION then
		it:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, lair.text)
	end
	return "placed"
end

function X.placeAll()
	local placed = 0
	if cfg.enabled == false then
		return placed
	end
	for _, lair in ipairs(cfg.lairs or {}) do
		local state, why = X.placePortal(lair)
		if not state then
			log(why)
		elseif state == "placed" or state == "kept" then
			placed = placed + 1
		elseif state == "closed" or state == "removed" then
			log(string.format("%s: closed, the client pair is %d and the lair opens at %d", lair.key, X.pair, lair.pair or 0))
		end
	end
	return placed
end

local startup = GlobalEvent("ChaosBossLairStartup")
function startup.onStartup()
	for _, p in ipairs(L.validate(cfg)) do
		log("config: " .. p)
	end
	X.placeAll()
	return true
end
startup:register()

local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true
	end
	local lair = X.lairAt(position)
	if not lair then
		return true
	end
	local what, to = L.enter(lair, X.pair, player:getLevel())
	if what == "enter" then
		player:teleportTo(P(to))
		P(to):sendMagicEffect(CONST_ME_TELEPORT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, t(player, "%s. The portal beside you leads back to the hunt.", lair.name))
		return true
	end
	player:teleportTo(fromPosition, true)
	if what == "level" then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, t(player, "%s is for level %d and above.", lair.name, lair.minLevel))
	else
		player:sendTextMessage(MESSAGE_STATUS_SMALL, t(player, "The way is sealed."))
	end
	return true
end
step:aid(cfg.aid)
step:register()

-- O686 phase 3: the lair boss takes H of the spell ranks (Chaos.healthFactor, 1 while the ranks are off) at the level its lair is planned
-- for (`healthLevel` of bosslair_config.lua), once, at its first think (the pace layer skips bosses; boss_mechanics.lua scales the maximum
-- by a factor of its own, so the two multiply whichever runs first)
local function lairOfMonster(name)
	name = tostring(name):lower()
	for _, lair in ipairs(cfg.lairs or {}) do
		if tostring(lair.monster):lower() == name then
			return lair
		end
	end
	return nil
end

local lairHealth = CreatureEvent("ChaosBossLairHealth")
function lairHealth.onThink(creature, interval)
	creature:unregisterEvent("ChaosBossLairHealth")
	local lair = creature:isMonster() and lairOfMonster(creature:getName()) or nil
	if lair then
		local max = creature:getMaxHealth()
		local want = Chaos.scaleHealth(max, lair.healthLevel)
		if want ~= max then
			creature:setMaxHealth(want)
			Chaos.heal(creature, want - creature:getHealth())
		end
	end
	return true
end
lairHealth:register()

-- the boss of a closed lair does not spawn (the engine tries again at the spawn's next turn)
local spawn = EventCallback
spawn.onSpawn = function(self, position, startup, artificial)
	if not L.allowSpawn(cfg, self:getName(), X.pair) then
		return false
	end
	if lairOfMonster(self:getName()) then
		self:registerEvent("ChaosBossLairHealth")
	end
	return true
end
spawn:register()
