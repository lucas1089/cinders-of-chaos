-- The Idle Hall: a character that stood idle in a town for idleMinutes is moved to a calm protected room with exercise
-- dummies, benches and a portal back to its temple, so the temples do not fill up (owner request 2026-10-15). Rules:
-- idlehall_core.lua (server/tests/idlehall_test.lua); numbers: idlehall_config.lua; the room's map:
-- server/tools/areaplan/rooms/idle_hall.json (install step contentareas); overview: server/README.md "Idle Hall".
-- No player storages, no table, no opcode of its own, no command.
--
-- What counts as an action (each one a table write; nothing is stored between logins):
--   sampler    every thinkMs one of cfg.slices groups of characters (by creature id): a new tile or a new direction
--              (a tile someone else pushed the character onto, EventCallback onMoveCreature, does not count)
--   items      EventCallback onItemMoved (an item moved by the player: containers, ground, equipment)
--   trade      EventCallback onTradeRequest / onTradeAccept (never refuses anything)
--   pushing    EventCallback onMoveCreature (the player who pushes)
--   spells     ChaosSpellEvents "cast" (engine patch 0008 with the spell events on)
--   chat       a public channel line (ChaosReports.onChannelSpeak, tools/patch_report_chat.py), wrapped once
--   windows    the extended opcodes of cfg.activityOpcodes (market, store, stash, bank, crafting, ...): their handlers
--              in Chaos.opcodeDispatch are wrapped (IH.wrapOpcodes)
--   engine     Player.getIdleTime when the engine has it (not in the current src-patches): the newer of the two counts
-- A character that is due (idleMinutes - warnSeconds without an action) is checked once: staff, an instance, exercise
-- training, outside a town zone (idlehall_core.lua K.townZone) leave it alone for recheckSeconds. Otherwise it gets the
-- warning, and warnSeconds later, still idle and still in town, it is moved (a teleport effect where it leaves and
-- where it lands). Logging out and in inside the hall is fine; the hall is no town, so nobody is moved out of it.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosWrapChain then
	dofile("data/scripts/chaos/wrapchain_core.lua")
end
dofile("data/scripts/chaos/idlehall_core.lua")
ChaosIdleHallConfig = dofile("data/scripts/chaos/idlehall_config.lua")

ChaosIdleHall = ChaosIdleHall or {}
local IH = ChaosIdleHall
local K = ChaosIdleHallCore
local cfg = ChaosIdleHallConfig
local unpack = unpack or table.unpack

IH.states = IH.states or {} -- creature id -> idle record (K.newState)
IH.pushed = IH.pushed or {} -- creature id -> the tile key someone else pushed it onto (until the next sample)
IH.temples = IH.temples or nil -- the temple positions of the town rule (startup; read again when empty)
IH.moves = IH.moves or 0
IH.warns = IH.warns or 0
local ACTIVE = K.opcodeSet(cfg, ChaosOpcodes)

local function log(text)
	print("[Chaos idle hall] " .. text)
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function try(name, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

-- ---------------------------------------------------------------- activity
function IH.stateOf(player, now)
	local cid = player:getId()
	local st = IH.states[cid]
	if not st then
		st = K.newState(now or nowMs())
		IH.states[cid] = st
	end
	return st
end

function IH.activity(player)
	if not cfg.enabled or not player then
		return
	end
	local st = IH.states[player:getId()]
	if st then
		K.touch(st, nowMs())
	end
end

local function playerOf(creature)
	return creature and creature.getPlayer and creature:getPlayer() or nil
end

-- ---------------------------------------------------------------- the town rule
function IH.loadTemples()
	local towns = {}
	for _, town in ipairs(Game.getTowns() or {}) do
		local ok, id, pos = pcall(function()
			return town:getId(), town:getTemplePosition()
		end)
		if ok and pos then
			towns[#towns + 1] = {id = id, pos = {x = pos.x, y = pos.y, z = pos.z}}
		end
	end
	IH.temples = K.temples(cfg, towns)
	return IH.temples
end

local function training(player)
	local key = (type(Exercise_Training) == "table" and tonumber(Exercise_Training.isTraining)) or cfg.trainingStorage
	return key ~= nil and player:getStorageValue(key) == 1
end

-- the facts of a due character (K.step's look)
function IH.look(player)
	local f = {}
	f.exempt = K.exempt({
		staff = Chaos.isStaff(player),
		instance = Chaos.inAnyInstance and Chaos.inAnyInstance(player) ~= nil,
		training = training(player)
	})
	if f.exempt then
		return f
	end
	local pos = player:getPosition()
	local tile = Tile(pos)
	local facts = tile and {
		pz = tile:hasFlag(TILESTATE_PROTECTIONZONE),
		house = tile:getHouse() ~= nil
	}
	if not IH.temples or #IH.temples == 0 then
		IH.loadTemples()
	end
	f.zone, f.zoneReason = K.townZone(cfg, {x = pos.x, y = pos.y, z = pos.z}, facts, IH.temples)
	return f
end

-- ---------------------------------------------------------------- the hall
function IH.arrival()
	local hall = cfg.hall or {}
	return K.slotPos(hall.at, hall.arrival)
end

local function hallReady()
	local to = IH.arrival()
	local tile = to and Tile(P(to))
	return tile ~= nil and tile:getGround() ~= nil, to
end

local function fixture(off, id, text)
	local pos = K.slotPos(cfg.hall.at, off)
	local tile = pos and Tile(P(pos))
	if not tile or not tile:getGround() then
		return false
	end
	for _, it in ipairs(tile:getItems() or {}) do
		if it:getActionId() == cfg.aid.fixture then
			if text then
				it:setAttribute(ITEM_ATTRIBUTE_TEXT, text)
			end
			return true
		end
	end
	if tile:getTopCreature() then
		return false -- someone stands there: the next tick tries again
	end
	local it = Game.createItem(id, 1, P(pos))
	if not it then
		return false
	end
	it:setActionId(cfg.aid.fixture)
	if text then
		it:setAttribute(ITEM_ATTRIBUTE_TEXT, text)
	end
	return true
end

-- the dummies, benches and the sign on their slots (placed once; found again after a reload)
function IH.placeFixtures()
	if not hallReady() then
		return 0
	end
	local n, items, slots = 0, cfg.items, cfg.slots
	for i, off in ipairs(slots.dummies or {}) do
		if fixture(off, items.dummies[(i - 1) % #items.dummies + 1]) then
			n = n + 1
		end
	end
	for _, off in ipairs(slots.benches or {}) do
		if fixture(off, items.bench) then
			n = n + 1
		end
	end
	if slots.sign and fixture(slots.sign, items.sign, K.signText()) then
		n = n + 1
	end
	return n
end

local function say(player, kind, key, args)
	player:sendTextMessage(kind, Chaos.t(player, key, unpack(args or {})))
end

function IH.moveToHall(player, st, now)
	local ready, to = hallReady()
	if not ready then
		if not IH.missingLogged then
			IH.missingLogged = true
			log("the hall is not on the map (run install_all.py --only contentareas); nobody is moved")
		end
		return false
	end
	local from = player:getPosition()
	if player:teleportTo(P(to)) == false then
		return false
	end
	from:sendMagicEffect(cfg.effect or CONST_ME_TELEPORT)
	player:getPosition():sendMagicEffect(cfg.effect or CONST_ME_TELEPORT)
	local key, args = K.movedText(cfg)
	say(player, MESSAGE_EVENT_ADVANCE, key, args)
	K.moved(st, now)
	IH.moves = IH.moves + 1
	return true
end

-- one character's sample and, when due, its warning or move
function IH.check(player, now)
	local st = IH.stateOf(player, now)
	local cid = player:getId()
	local pos = player:getPosition()
	K.sample(st, K.posKey(pos), player:getDirection(), now, IH.pushed[cid])
	IH.pushed[cid] = nil
	if player.getIdleTime then
		K.engineIdle(st, now, player:getIdleTime())
	end
	local action = K.step(cfg, st, now, function()
		return IH.look(player)
	end)
	if action == "warn" then
		if hallReady() then
			local key, args = K.warnText(cfg)
			say(player, MESSAGE_STATUS_WARNING or MESSAGE_EVENT_ADVANCE, key, args)
			IH.warns = IH.warns + 1
		else
			st.warned = false
			st.nextCheck = now + (cfg.recheckSeconds or 60) * 1000
		end
	elseif action == "move" then
		if not IH.moveToHall(player, st, now) then
			st.nextCheck = now + (cfg.recheckSeconds or 60) * 1000
		end
	end
	return action
end

-- ---------------------------------------------------------------- hooks of other scripts
-- the windows of cfg.activityOpcodes: their handlers in Chaos.opcodeDispatch (by opcode) are wrapped once, so a request
-- counts before the module answers it; no handler of our own (no extra call for the other opcodes). A reload makes new
-- entries: the next installHooks wraps them.
function IH.wrapOpcodes()
	local D = Chaos.opcodeDispatch
	local n = 0
	for op in pairs(ACTIVE) do
		for _, e in ipairs(D and D.byOpcode and D.byOpcode[op] or {}) do
			if not e.idleHall and type(e.fn) == "function" then
				local inner = e.fn
				e.fn = function(player, ...)
					pcall(IH.activity, player)
					return inner(player, ...)
				end
				e.idleHall = true
				n = n + 1
			end
		end
	end
	return n
end

function IH.installHooks()
	IH.wrapOpcodes()
	if ChaosReports and type(ChaosReports.onChannelSpeak) == "function" then
		ChaosWrapChain.wrap(ChaosReports, "onChannelSpeak", "idlehall", function(results, player)
			IH.activity(playerOf(player))
		end, log)
	end
	if not ChaosSpellEvents or not ChaosSpellEvents.set then
		pcall(dofile, "data/lib/chaos_spell_events.lua")
	end
	if ChaosSpellEvents and ChaosSpellEvents.set then
		ChaosSpellEvents.set("cast", "idlehall", function(player)
			IH.activity(playerOf(player))
		end)
	end
end

-- ---------------------------------------------------------------- events
local login = CreatureEvent("ChaosIdleHallLogin")
function login.onLogin(player)
	player:registerEvent("ChaosIdleHallLogout")
	local st = K.newState(nowMs())
	IH.states[player:getId()] = st
	IH.pushed[player:getId()] = nil
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosIdleHallLogout")
function logout.onLogout(player)
	IH.states[player:getId()] = nil
	IH.pushed[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

local movedItem = EventCallback
movedItem.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	IH.activity(playerOf(player))
end
movedItem:register()

local pushCb = EventCallback
pushCb.onMoveCreature = function(player, creature, fromPosition, toPosition)
	IH.activity(playerOf(player))
	local other = playerOf(creature)
	if other and other ~= player and toPosition then
		IH.pushed[other:getId()] = K.posKey(toPosition)
	end
	return true
end
pushCb:register()

local tradeCb = EventCallback
tradeCb.onTradeRequest = function(player, target, item)
	IH.activity(playerOf(player))
	return true
end
tradeCb:register()

local acceptCb = EventCallback
acceptCb.onTradeAccept = function(player, target, item, targetItem)
	IH.activity(playerOf(player))
	IH.activity(playerOf(target))
	return true
end
acceptCb:register()

-- the sampler: one slice of the characters per tick; the fixtures and the hooks once a minute
local slice, ticks = 0, 0
local think = GlobalEvent("ChaosIdleHallThink")
function think.onThink(interval)
	if not cfg.enabled then
		return true
	end
	local slices = math.max(1, cfg.slices or 10)
	slice = (slice + 1) % slices
	ticks = ticks + 1
	if ticks % math.max(1, math.floor(60000 / math.max(1, cfg.thinkMs or 1000))) == 0 then
		try("hooks", IH.installHooks)
		try("fixtures", IH.placeFixtures)
	end
	local now = nowMs()
	for _, player in ipairs(Game.getPlayers()) do
		if player:getId() % slices == slice then
			try("check", IH.check, player, now)
		end
	end
	return true
end
think:interval(math.max(100, cfg.thinkMs or 1000))
think:register()

local startup = GlobalEvent("ChaosIdleHallStartup")
function startup.onStartup()
	if not cfg.enabled then
		return true
	end
	try("hooks", IH.installHooks)
	local temples = try("temples", IH.loadTemples) or {}
	local placed = try("fixtures", IH.placeFixtures) or 0
	local problems = K.validate(cfg)
	for _, p in ipairs(problems) do
		log("idlehall_config.lua: " .. p)
	end
	log(string.format("%d town(s), idle %d min, %d fixture(s)%s", #temples, cfg.idleMinutes, placed,
		hallReady() and "" or "; the hall is not on the map yet (install step contentareas)"))
	return true
end
startup:register()
