-- Travel to an NPC: a "Go to NPC" button on every client panel that fronts an NPC's service (Factions, the Gambler, the stash,
-- Boss Spawns, Candlemarks, Professions, ...). Numbers and the NPC list: npc_travel_config.lua; pure logic:
-- npc_travel_core.lua (server/tests/npc_travel_test.lua); client module game_npctravel. Overview: server/README.md
-- "Travel to an NPC".
--
-- Protocol (JSON {action, data}) on ChaosOpcodes.npcTravel = 121:
--   client -> server  travel {k}   (k: a key of npc_travel_config.lua npcs)
-- The answer is a normal game message (cancel message on a refusal, a status line on success): the panel needs no handler.
-- A new panel adds one line to its .otui: @onClick: modules.game_npctravel.travel('<key>').
--
-- The same safety as the Town Portal (townportal.lua blockFacts: no arena, rift, dungeon, Infinity Tower, hideout, instance,
-- tutorial island), no combat (pz lock or in-fight condition), no skull, a cooldown (cooldownSeconds), a rate limit.
-- No storage, no table: the cooldown lives in memory (a restart resets it).
-- Assumed engine API (TFS 1.4): Creature(name), Town(id):getTemplePosition, Tile, Player:teleportTo/isPzLocked/hasCondition/
-- getSkull/sendCancelMessage/sendTextMessage. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosNpcTravelCore then
	dofile("data/scripts/chaos/npc_travel_core.lua")
end
if not ChaosNpcBoothsCore then
	dofile("data/scripts/chaos/npc_booths_core.lua")
end

ChaosNpcTravel = ChaosNpcTravel or {}
local T = ChaosNpcTravel
local K = ChaosNpcTravelCore
local cfg = dofile("data/scripts/chaos/npc_travel_config.lua")
T.cfg = cfg
local OPCODE = (ChaosOpcodes and ChaosOpcodes.npcTravel) or 121

T.last = T.last or {} -- guid -> os.time() of the last journey

local function log(text)
	print("[Chaos npc travel] " .. text)
end

local function now()
	return os.time()
end

local function tr(player, key, ...)
	return Chaos.t(player, key, ...)
end

local function pos3(p)
	return p and {x = p.x, y = p.y, z = p.z} or nil
end

local function P(p)
	return Position(p.x, p.y, p.z)
end

-- the live NPC of that name anywhere on the map
local function liveNpc(name)
	local ok, c = pcall(Creature, name)
	if ok and c and c.isNpc and c:isNpc() then
		local okP, p = pcall(function() return c:getPosition() end)
		return okP and pos3(p) or nil
	end
	return nil
end

local function templeOf(townId)
	local ok, p = pcall(function()
		local town = Town(townId)
		return town and town:getTemplePosition() or nil
	end)
	if ok and p and p.x and p.x > 0 then
		return pos3(p)
	end
	return nil
end

local function booths()
	local ok, list = pcall(function() return ChaosNpcBoothsCore.booths(ChaosNpcBoothsCore.cfg()) end)
	return ok and list or {}
end

-- where the NPC of a key is (K.resolve with the engine's probes)
function T.locate(key)
	return K.resolve(cfg, booths(), key, {live = liveNpc, temple = templeOf})
end

-- the text of a panel: "Warden Ysolde, in the market of the teleport room in Cinderhold" (in the player's language), or nil
function T.where(player, key)
	local e = K.entry(cfg, key)
	return e and tr(player, e.where) or nil
end

-- ---------------------------------------------------------------- the landing tile
local function standable(p)
	local tile = Tile(P(p))
	if not tile or not tile:getGround() then
		return false
	end
	local okH, house = pcall(function() return tile:getHouse() end)
	if okH and house then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH)
		or tile:hasProperty(CONST_PROP_IMMOVABLEBLOCKSOLID) then
		return false
	end
	if tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT) or tile:hasFlag(TILESTATE_MAGICFIELD) then
		return false
	end
	if tile:getTopCreature() then
		return false
	end
	return true
end

local function landing(where)
	if where.via == "temple" then
		-- the NPC is not found and only the temple is known: the temple's own tile first, then around it
		local list = K.candidates(where.npc, nil, (cfg.maxRing or 2) + 2, false)
		table.insert(list, 1, where.npc)
		for _, p in ipairs(list) do
			if standable(p) then
				return p
			end
		end
		return nil
	end
	for _, p in ipairs(K.candidates(where.npc, where.hint, cfg.maxRing, where.front)) do
		if standable(p) then
			return p
		end
	end
	return nil
end

-- ---------------------------------------------------------------- where it is refused
local function try(fn)
	local ok, res = pcall(fn)
	return ok and res or nil
end

local function facts(player)
	local f = {}
	local TP = ChaosTownPortal
	if TP and TP.blockFacts then
		local ok, tf = pcall(TP.blockFacts, player)
		if ok and type(tf) == "table" then
			for _, k in ipairs({"tutorial", "arena", "worldBoss", "siege", "rift", "dungeon", "tower", "hideout", "marches", "instance", "skull"}) do
				f[k] = tf[k]
			end
			f.casting = tf.casting
		end
	elseif Chaos.inAnyInstance then
		f.instance = select(2, Chaos.inAnyInstance(player))
	end
	f.disabled = cfg.enabled == false
	f.inFight = try(function() return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT) end) and true or false
	f.cooldownLeft = K.cooldownLeft(cfg, now(), T.last[player:getGuid()])
	return f
end

function T.blockReason(player)
	return K.blockReason(facts(player), function(k, ...) return tr(player, k, ...) end, cfg.labels)
end

-- ---------------------------------------------------------------- the journey
-- true | false, text (already in the player's language)
function T.go(player, key)
	local e = K.entry(cfg, key)
	if not e then
		return false, tr(player, "That place is not on the map.")
	end
	local why = T.blockReason(player)
	if why then
		return false, why
	end
	local where, reason = T.locate(key)
	if not where then
		log(e.name .. " (" .. tostring(key) .. "): not found (" .. tostring(reason) .. ")")
		return false, tr(player, "%s is not at their post right now.", e.name)
	end
	local here = pos3(player:getPosition())
	if where.via ~= "temple" and K.near(here, where.npc, cfg.nearRange) then
		return false, tr(player, "You are already next to %s.", e.name)
	end
	local dest = landing(where)
	if not dest then
		return false, tr(player, "There is no free spot in front of %s right now. Try again in a moment.", e.name)
	end
	local from = player:getPosition()
	T.last[player:getGuid()] = now()
	player:teleportTo(P(dest))
	pcall(function()
		from:sendMagicEffect(CONST_ME_TELEPORT)
		P(dest):sendMagicEffect(CONST_ME_TELEPORT)
	end)
	if where.via == "temple" then
		return true, tr(player, "%s was not found: you stand at the temple of the town.", e.name)
	end
	return true, tr(player, "You stand before %s.", e.name)
end

-- ---------------------------------------------------------------- the opcode
local ext = CreatureEvent("ChaosNpcTravelExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "travel" then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "npctravel.travel", cfg.requestMs or 1000) then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local ok, text = T.go(player, type(data.k) == "string" and data.k or "")
	if ok then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, text)
	else
		player:sendCancelMessage(text)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosNpcTravelLogin")
function login.onLogin(player)
	player:registerEvent("ChaosNpcTravelExtended")
	return true
end
login:register()

local startup = GlobalEvent("ChaosNpcTravelStartup")
function startup.onStartup()
	for _, problem in ipairs(K.validate(cfg, booths())) do
		log("config: " .. problem)
	end
	return true
end
startup:register()
