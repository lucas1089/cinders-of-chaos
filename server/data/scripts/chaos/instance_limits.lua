-- Instance limits (server/README.md "Instance limits"): the shared glue every instance uses for its warnings before the
-- time runs out, idle closing, the "all busy" message with a wait estimate and the waiting line; the staff command
-- /instances; and the base server's lever boss rooms (ChaosBossRooms, wired by tools/patch_base_bossrooms.py).
-- Rules: instance_limits_core.lua (tests/instance_limits_test.lua); numbers: instance_limits_config.lua and each
-- system's `limits` block. Lua 5.1 / LuaJIT and 5.3.
--
-- API for the systems (all calls are optional: a system works the same when this file is not loaded):
--   ChaosInstanceLimits.warn(run, left, players, label, limits)  each tick: tells the players at the warnAt marks
--   ChaosInstanceLimits.idle(run, occupied, limits) -> true       an empty run past its grace should close
--   ChaosInstanceLimits.busy(player, key, what, lefts, limits)    -> the "all busy" text (and a place in line)
--   ChaosInstanceLimits.freed(key, what)                          a slot of `key` is free: the first in line is told
--   ChaosInstanceLimits.capped(key, running, limits) -> true      the type's maxRuns is reached
-- The registry of chaos_constants.lua (Chaos.registerInstance) takes two more optional fields for the staff:
--   runs = function() return {{id =, what =, left = seconds | nil, players = n, idle = seconds | nil, note =}} end
--   close = function(id) return ok, text end    (the system's own failure rule: nobody gets a reward for it)

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not (ChaosInstanceLimitsCore and ChaosInstanceLimitsCore.warning) then
	dofile("data/scripts/chaos/instance_limits_core.lua")
end
Chaos.instanceLimitsConfig = dofile("data/scripts/chaos/instance_limits_config.lua")

ChaosInstanceLimits = ChaosInstanceLimits or {}
local IL = ChaosInstanceLimits
local K = ChaosInstanceLimitsCore
IL.core = K
IL.lines = IL.lines or {} -- [type key] = the waiting line (kept over /reload scripts)

local function C()
	return Chaos.instanceLimitsConfig
end

local function msgWarn()
	return MESSAGE_STATUS_WARNING or MESSAGE_EVENT_ADVANCE
end

function IL.limits(own)
	return K.limits(C().defaults, own)
end

-- Player objects of a run's member map ([player id] = anything)
function IL.playersOf(map)
	local list = {}
	for id in pairs(map or {}) do
		local p = Player(id)
		if p then
			list[#list + 1] = p
		end
	end
	return list
end

-- ------------------------------------------------------------------ warnings and idle
function IL.warn(run, left, players, label, limits)
	if type(run) ~= "table" or type(left) ~= "number" then
		return nil
	end
	local l = IL.limits(limits)
	run._limits = run._limits or {}
	local mark = K.warning(run._limits, left, l.warnAt)
	if not mark then
		return nil
	end
	-- each player's language: the label is a key too ("Arena", "Infinity Tower", a boss room's name stays as it is)
	for _, p in ipairs(players or {}) do
		local lang = Chaos.lang(p)
		local name = Chaos.t(p, label or "Instance")
		local leftText = K.leftText(mark, lang)
		p:sendTextMessage(msgWarn(), Chaos.t(p, "%s: %s. Everyone inside is sent out when the time runs out.", name, leftText))
		if mark >= 60 and ChaosNotify and ChaosNotify.send then
			ChaosNotify.send(p, name, leftText)
		end
	end
	return mark
end

function IL.idle(run, occupied, limits, now)
	if type(run) ~= "table" then
		return false
	end
	run._limits = run._limits or {}
	return K.idle(run._limits, now or os.time(), occupied, IL.limits(limits).idleSeconds)
end

function IL.idleLeft(run, limits, now)
	return run and run._limits and K.idleLeft(run._limits, now or os.time(), IL.limits(limits).idleSeconds) or nil
end

-- ------------------------------------------------------------------ caps and the waiting line
function IL.capped(key, running, limits)
	return K.capReached(running, IL.limits(limits).maxRuns)
end

function IL.line(key)
	IL.lines[key] = IL.lines[key] or {}
	return IL.lines[key]
end

-- what: plural ("rifts"); lefts: seconds left of the running instances. Returns the text (the caller sends it the way
-- it always did); with the waiting line on, the player is in line and the text says where.
function IL.busy(player, key, what, lefts, limits)
	local l = IL.limits(limits)
	local pos
	if l.waitlist and player then
		pos = K.waitAdd(IL.line(key), player:getGuid(), os.time(), (l.waitMinutes or 15) * 60, player:getName(), l.waitMax)
	end
	return K.busyText(what, K.eta(lefts, pos or 1), pos, player and Chaos.lang(player) or nil)
end

function IL.leaveLine(key, player)
	return player ~= nil and K.waitRemove(IL.line(key), player:getGuid())
end

-- one slot of `key` is free: the first in line who is online and not inside an instance is told (and taken off)
function IL.freed(key, what)
	local list = IL.lines[key]
	if not list or #list == 0 then
		return nil
	end
	local state = Game and Game.getGameState and Game.getGameState()
	if state ~= nil and (state == GAME_STATE_SHUTDOWN or state == GAME_STATE_CLOSED) then
		return nil -- a closing server frees every slot at once; nobody is told
	end
	local now = os.time()
	while #list > 0 do
		local e = K.waitNext(list, now)
		if not e then
			return nil
		end
		local p = e.name and Player(e.name)
		if p and p:getGuid() == e.id and not (Chaos.inAnyInstance and Chaos.inAnyInstance(p)) then
			local text = Chaos.t(p, "A place in %s is free now. Go ahead before someone else takes it.", Chaos.t(p, what or "the instance"))
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
			if ChaosNotify and ChaosNotify.send then
				ChaosNotify.send(p, Chaos.t(p, "Your turn"), text)
			end
			return p
		end
	end
	return nil
end

-- ------------------------------------------------------------------ staff: /instances
function IL.runs()
	local out = {}
	for _, key in ipairs(Chaos.instanceOrder or {}) do
		local def = Chaos.instances[key]
		if def and type(def.runs) == "function" then
			local ok, list = pcall(def.runs)
			if ok and type(list) == "table" then
				for _, r in ipairs(list) do
					r.key = key
					out[#out + 1] = r
				end
			elseif not ok then
				print("[ChaosInstances] " .. key .. ".runs failed: " .. tostring(list))
			end
		end
	end
	return out
end

function IL.describe(r)
	local parts = {string.format("%s %s", r.key, tostring(r.id))}
	if r.what then
		parts[#parts + 1] = r.what
	end
	parts[#parts + 1] = r.left and (K.clock(r.left) .. " left") or "no time limit"
	parts[#parts + 1] = string.format("%d player(s)", r.players or 0)
	if r.idle then
		parts[#parts + 1] = "empty, closes in " .. K.clock(r.idle)
	end
	if r.note then
		parts[#parts + 1] = r.note
	end
	return table.concat(parts, ", ")
end

function IL.close(key, id, reason)
	local def = Chaos.instances[key]
	if not def or type(def.close) ~= "function" then
		return false, "Unknown type (or it cannot be closed from here): " .. tostring(key)
	end
	local ok, done, text = pcall(def.close, id, reason or "A gamemaster closed it.")
	if not ok then
		return false, "Close failed: " .. tostring(done)
	end
	return done ~= false, text or (done ~= false and "Closed." or "Not found.")
end

local function onInstances(player, words, param)
	local args = {}
	for w in (param or ""):gmatch("[^%s,]+") do
		args[#args + 1] = w
	end
	local sub = (args[1] or "list"):lower()
	if sub == "close" then
		if not args[2] or not args[3] then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Usage: /instances close <type> <id>   (ids from /instances)"))
			return false
		end
		local id = tonumber(args[3]) or args[3]
		local ok, text = IL.close(args[2]:lower(), id, "A gamemaster closed it.")
		player:sendTextMessage(MESSAGE_INFO_DESCR, (ok and "" or "Not closed: ") .. tostring(text))
		print(string.format("[ChaosInstances] %s: /instances close %s %s -> %s", player:getName(), args[2], tostring(args[3]),
			tostring(text)))
		return false
	elseif sub == "line" then
		local n = 0
		for key, list in pairs(IL.lines) do
			K.waitPrune(list, os.time())
			if #list > 0 and (not args[2] or args[2]:lower() == key) then
				local names = {}
				for _, e in ipairs(list) do
					names[#names + 1] = e.name or tostring(e.id)
				end
				player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%s line: %s", key, table.concat(names, ", ")))
				n = n + 1
			end
		end
		if n == 0 then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "Nobody is waiting."))
		end
		return false
	end
	local list = IL.runs()
	local filter = sub ~= "list" and sub or args[2] and args[2]:lower() or nil
	local shown = 0
	for _, r in ipairs(list) do
		if not filter or r.key == filter then
			player:sendTextMessage(MESSAGE_INFO_DESCR, IL.describe(r))
			shown = shown + 1
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, Chaos.t(player, "%d instance(s) running%s. /instances close <type> <id> ends one (everyone out, no reward, the system's failure rule); /instances line shows who waits.", shown,
		filter and (" of " .. filter) or ""))
	return false
end
IL._onInstances = onInstances

if TalkAction then
	local talk = TalkAction("/instances")
	function talk.onSay(player, words, param)
		local allowed, staff = Chaos.staffCommand(player, words, param)
		if not staff then
			return true -- plain chat for players
		end
		if allowed then
			onInstances(player, words, param)
		end
		return false
	end
	talk:separator(" ")
	talk:register()
end

-- ======================================================================== base lever boss rooms
-- tools/patch_base_bossrooms.py makes each recognised room script (a lever room, or a step-in room of the miniboss files)
-- call:
--   ChaosBossRoomsPending[key] = config                      at load (key = "aid" .. the lever's / tile's action id)
--   ChaosBossRooms.leverUse(player, key, config) -> false   at the start of the lever's onUse (the tile's onStepIn): the
--                                                            room is in use, or a monster stepped on the tile
--   ChaosBossRooms.started(key, config, participants)        after the group went in and the boss was made
-- tools/patch_base_eventrooms.py wires the soul pit and the tower defence the same way, with a room config of its own
-- (config.chaosRoom: the time from bossRooms.ownSeconds; config.chaosOnClose(players, why): resets the place's state at
-- the end) and ChaosBossRooms.finished(key) when the place ends by its own rule (completed, won or lost).
-- The script keeps its own checks (participants, level, cooldown, a player in the room), its boss and its exit after a
-- kill. This side adds: the lever is locked while a group's session runs; the time limit (the script's own kick time,
-- at most bossRooms.maxSeconds) with warnings and a countdown over the entrance and the lever; at the end everyone inside
-- goes to the script's exitPosition and the monsters in the room are removed; an empty room unlocks after idleSeconds;
-- a character who logs in inside a room that is not its group's running fight goes to the exit.
ChaosBossRooms = ChaosBossRooms or {}
local BR = ChaosBossRooms
BR.rooms = BR.rooms or {}       -- [key] = config of the base script
BR.sessions = BR.sessions or {} -- [key] = {id, key, startedAt, endsAt, limit, guids, bossId, state}
BR.nextId = BR.nextId or 1
ChaosBossRoomsPending = ChaosBossRoomsPending or {}

local function RC()
	return C().bossRooms or {}
end

function BR.collect()
	for key, config in pairs(ChaosBossRoomsPending) do
		BR.rooms[key] = config
	end
end

function BR.register(key, config)
	if type(key) == "string" and type(config) == "table" and config.bossArea then
		BR.rooms[key] = config
	end
end

local function areaOf(config)
	local f, t = config.bossArea.fromPos, config.bossArea.toPos
	return math.min(f.x, t.x), math.max(f.x, t.x), math.min(f.y, t.y), math.max(f.y, t.y), f.z
end

function BR.inRoom(config, pos)
	if not pos or not config or not config.bossArea then
		return false
	end
	local x1, x2, y1, y2, z = areaOf(config)
	return pos.z == z and pos.x >= x1 and pos.x <= x2 and pos.y >= y1 and pos.y <= y2
end

function BR.roomAt(pos)
	BR.collect()
	for key, config in pairs(BR.rooms) do
		if BR.inRoom(config, pos) then
			return key, config
		end
	end
	return nil
end

-- creatures in the room (players, monsters)
local function creaturesIn(config)
	local x1, x2, y1, y2, z = areaOf(config)
	local rx, ry = math.ceil((x2 - x1) / 2), math.ceil((y2 - y1) / 2)
	local players, monsters = {}, {}
	for _, c in ipairs(Game.getSpectators(Position(x1 + rx, y1 + ry, z), false, false, rx, rx, ry, ry) or {}) do
		if BR.inRoom(config, c:getPosition()) then
			if c:isPlayer() then
				players[#players + 1] = c
			elseif c:isMonster() then
				monsters[#monsters + 1] = c
			end
		end
	end
	return players, monsters
end
BR.creaturesIn = creaturesIn

function BR.limitOf(config)
	local own = tonumber(config.kickParticipantAfterSeconds) or tonumber((RC().ownSeconds or {})[config.chaosRoom]) or 600
	local cap = tonumber(RC().maxSeconds) or 0
	if cap > 0 then
		return math.min(own, cap)
	end
	return own
end

local function nameOf(config)
	local n = tostring(config.bossName or "the boss")
	return (n:gsub("^%l", string.upper))
end

local function setBars(key, config, s)
	if not (RC().bar and ChaosTileBars and ChaosTileBars.set) then
		return
	end
	local left = math.max(1, s.endsAt - os.time())
	local e = config.bossArea.entrancePos
	if e then
		ChaosTileBars.set("room:" .. key .. ":in", {pos = {x = e.x, y = e.y, z = e.z}, label = s.state == "won" and "Room closes"
			or "Time left", endsIn = left, total = s.limit, color = "#d05030"})
	end
	local lever = config.participantsPos and config.participantsPos[1]
	if lever then
		ChaosTileBars.set("room:" .. key .. ":lever", {pos = {x = lever.x, y = lever.y, z = lever.z}, label = "Room in use",
			endsIn = left, total = s.limit, color = "#a0a0a0"})
	end
end

local function clearBars(key)
	if ChaosTileBars and ChaosTileBars.removePrefix then
		ChaosTileBars.removePrefix("room:" .. key .. ":")
	end
end

-- a player on one of the room's participant tiles (the stock lever takes its group from them: config.participantsPos)?
-- true for a room without such tiles (the soul pit, the tower defence)
function BR.groupReady(player, config)
	local list = config and config.participantsPos
	-- only the stock lever template; the event rooms (config.chaosRoom) use participantsPos for other spots
	if type(list) ~= "table" or #list == 0 or config.chaosRoom then
		return true
	end
	local at = player:getPosition()
	for _, pos in ipairs(list) do
		if at and at.x == pos.x and at.y == pos.y and at.z == pos.z then
			return true
		end
		local ok, c = pcall(function()
			local tile = Tile(pos)
			return tile and tile:getTopVisibleCreature(player)
		end)
		if ok and c and c.isPlayer and c:isPlayer() then
			return true
		end
	end
	return false
end

-- the lever (or the entry tile of a step-in room): false (and a message) while the room's session runs; a monster or a
-- summon walking onto an entry tile never starts a fight (the stock step-in would make the boss for it); false when
-- nobody stands on the participant tiles (the stock lever then made the boss, sent nobody in and locked the room:
-- player report 2026-10-22, a Waystone III room "in use" with the player outside)
function BR.leverUse(player, key, config)
	BR.register(key, config)
	if not (player and player.isPlayer and player:isPlayer()) then
		return false
	end
	if not BR.groupReady(player, config) then
		player:sendCancelMessage(Chaos.t(player, "Stand on the tile in front of the lever to pull it (your group on the tiles behind you)."))
		local first = config.participantsPos[1]
		if first and first.sendMagicEffect then
			pcall(function() first:sendMagicEffect(CONST_ME_MAGIC_BLUE) end)
		end
		return false
	end
	if not RC().enabled then
		return true
	end
	local s = BR.sessions[key]
	if not s then
		return true
	end
	local left = math.max(0, s.endsAt - os.time())
	local idle = IL.idleLeft(s, {idleSeconds = RC().idleSeconds})
	if idle then
		left = math.min(left, idle)
	end
	if s.guids[player:getGuid()] then
		-- the group's own run (a lever inside the room, as in the tower defence)
		player:sendCancelMessage(Chaos.t(player, "Your run is still going: %s left.", (K.about(left, Chaos.lang(player)):gsub("^~", ""))))
		return false
	end
	player:sendCancelMessage(Chaos.t(player, "A group is fighting in there. The room frees up in %s at the latest.",
		K.about(left, Chaos.lang(player))))
	return false
end

local tick

-- a tile of the room a player can stand on: a ground, nothing that blocks, no creature
local function freeTile(config, pos)
	if not BR.inRoom(config, pos) then
		return false
	end
	local ok, free = pcall(function()
		local tile = Tile(pos)
		return tile ~= nil and tile:getGround() ~= nil and not tile:hasProperty(CONST_PROP_BLOCKSOLID)
			and tile:getTopCreature() == nil
	end)
	return ok and free == true
end

-- a participant still outside the room after the script's teleport goes to the free tile nearest to the entrance
function BR.bringIn(config, player)
	local e = config.bossArea and config.bossArea.entrancePos
	if not (e and player and player.getPosition) or BR.inRoom(config, player:getPosition()) then
		return false
	end
	for r = 0, 3 do
		for dy = -r, r do
			for dx = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local pos = Position(e.x + dx, e.y + dy, e.z)
					if freeTile(config, pos) then
						player:teleportTo(pos)
						return BR.inRoom(config, player:getPosition())
					end
				end
			end
		end
	end
	return false
end

function BR.started(key, config, participants)
	BR.register(key, config)
	config = config or BR.rooms[key]
	if not RC().enabled or not config then
		return nil
	end
	-- no list (a place entered before the start, as the tower defence): the players in the room
	local given = participants ~= nil
	participants = participants or creaturesIn(config)
	-- the script's own kick timer would also hit the next group (it is never stopped when the room empties): this
	-- session's end replaces it
	if config.kickEventId and stopEvent then
		stopEvent(config.kickEventId)
		config.kickEventId = nil
	end
	-- a group the script's teleport did not bring in (its entrance on a tile that blocks): onto the nearest free tile
	-- of the room next to the entrance
	for _, p in pairs(participants) do
		BR.bringIn(config, p)
	end
	if given and next(participants) == nil then
		-- the lever's group is empty: nobody went in: no lock, the boss the script made goes again
		BR.rooms[key] = config
		BR.close(key, "idle")
		return nil
	end
	local now = os.time()
	local limit = BR.limitOf(config)
	local s = {id = BR.nextId, key = key, startedAt = now, endsAt = now + limit, limit = limit, guids = {}, state = "fight"}
	BR.nextId = BR.nextId + 1
	for _, p in pairs(participants or {}) do
		s.guids[p:getGuid()] = true
	end
	local boss = tostring(config.bossName or ""):lower()
	local _, monsters = creaturesIn(config)
	for _, m in ipairs(monsters) do
		if m:getName():lower() == boss then
			s.bossId = m:getId()
			break
		end
	end
	BR.sessions[key] = s
	setBars(key, config, s)
	for _, p in pairs(participants or {}) do
		p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "%s: you have %s. Then everyone in the room is sent out.",
			nameOf(config), (K.about(limit, Chaos.lang(p)):gsub("^~", ""))))
	end
	addEvent(tick, 1000, key, s.id)
	return s
end

-- the place's own end (a completed soul pit, the tower defence won or lost): as after a boss kill, the room closes
-- 65 s later, at once when it is empty
function BR.finished(key)
	local s = BR.sessions[key]
	local config = BR.rooms[key]
	if not s or not config or s.state ~= "fight" then
		return false
	end
	s.state = "won"
	s.endsAt = math.min(s.endsAt, os.time() + (tonumber(config.teleportRemoveSeconds) or 60) + 5)
	setBars(key, config, s)
	return true
end

-- why: "time" | "idle" | "won" | "staff" | "shutdown"
local OUT_TEXT = {
	time = "Time is up: you were sent out of the boss room.",
	staff = "A gamemaster closed the boss room.",
	won = "The boss room closes.",
	idle = "The boss room closes.",
	shutdown = "The boss room closes for a restart."
}

function BR.close(key, why)
	local s = BR.sessions[key]
	local config = BR.rooms[key]
	BR.sessions[key] = nil
	clearBars(key)
	if not config then
		return false
	end
	local players, monsters = creaturesIn(config)
	if config.chaosOnClose then
		-- the place's own state (its waves, its counters) is reset before everyone goes out
		local ok, err = pcall(config.chaosOnClose, players, why)
		if not ok then
			print("[ChaosBossRooms] " .. key .. " close hook: " .. tostring(err))
		end
	end
	local exit = config.bossArea.exitPosition
	for _, p in ipairs(players) do
		if not (Chaos.isStaff and Chaos.isStaff(p)) and exit then
			p:teleportTo(exit)
			if exit.sendMagicEffect then
				exit:sendMagicEffect(CONST_ME_TELEPORT)
			end
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, OUT_TEXT[why] or OUT_TEXT.time))
		end
	end
	for _, m in ipairs(monsters) do
		m:remove()
	end
	if s then
		print(string.format("[ChaosBossRooms] %s (%s) closed: %s after %d s", key, nameOf(config), tostring(why),
			os.time() - s.startedAt))
	end
	return true
end

tick = function(key, sid)
	local s = BR.sessions[key]
	local config = BR.rooms[key]
	if not s or s.id ~= sid or not config then
		return
	end
	local now = os.time()
	local players = creaturesIn(config)
	if s.state == "fight" and s.bossId and not Monster(s.bossId) then
		-- the boss is down: the script's own exit runs (its teleport, its kick teleportRemoveSeconds later); the session
		-- ends then, or as soon as the room is empty
		s.state = "won"
		s.endsAt = math.min(s.endsAt, now + (tonumber(config.teleportRemoveSeconds) or 60) + 5)
		setBars(key, config, s)
	end
	local left = s.endsAt - now
	if left <= 0 then
		BR.close(key, s.state == "won" and "won" or "time")
		return
	end
	if s.state == "fight" then
		IL.warn(s, left, players, nameOf(config), {warnAt = (C().defaults or {}).warnAt})
	end
	local grace = s.state == "won" and 0 or RC().idleSeconds
	if IL.idle(s, #players > 0, {idleSeconds = grace}, now) then
		BR.close(key, "idle")
		return
	end
	addEvent(tick, 1000, key, sid)
end
BR._tick = tick

function BR.isInside(player)
	local guid = player:getGuid()
	for key, s in pairs(BR.sessions) do
		if s.guids[guid] and BR.inRoom(BR.rooms[key], player:getPosition()) then
			return true
		end
	end
	return false
end

-- the running room the player stands in: key, config, session (any player in it, not only its group); nil: none
function BR.roomOf(player)
	local pos = player:getPosition()
	for key, s in pairs(BR.sessions) do
		local config = BR.rooms[key]
		if config and BR.inRoom(config, pos) then
			return key, config, s
		end
	end
	return nil
end

-- "Leave Boss Room" (Info & Services > Services, command "leaveroom"): out to the room's exit (the tower defence: its
-- drop), refused outside a running room, in a fight (pz lock or battle, as the dungeon queue) and within
-- bossRooms.leaveCooldown seconds of the last leave. The last one out closes the room as the idle rule does (boss and
-- monsters removed, the lever free). Returns true when the player went out.
BR.leftAt = BR.leftAt or {} -- [guid] = os.time() of the last leave
function BR.leave(player)
	local key, config, s = BR.roomOf(player)
	local now = os.time()
	local guid = player:getGuid()
	local cd = tonumber(RC().leaveCooldown) or 0
	local reason, n = K.leaveReason({
		inside = key ~= nil and RC().enabled ~= false,
		fight = player:isPzLocked() or (CONDITION_INFIGHT ~= nil and player:hasCondition(CONDITION_INFIGHT)),
		cooldownLeft = BR.leftAt[guid] and (BR.leftAt[guid] + cd - now) or 0
	})
	if reason then
		player:sendCancelMessage(Chaos.t(player, reason, n))
		return false
	end
	local exit = config.bossArea.exitPosition
	if not exit then
		local town = player:getTown()
		exit = town and town:getTemplePosition()
	end
	if not exit then
		player:sendCancelMessage(Chaos.t(player, "You are not in a boss room."))
		return false
	end
	BR.leftAt[guid] = now
	if s and s.guids then
		s.guids[guid] = nil -- back in later only through the lever, like anyone else
	end
	player:teleportTo(exit)
	if exit.sendMagicEffect then
		exit:sendMagicEffect(CONST_ME_TELEPORT)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "You left the boss room."))
	local left = creaturesIn(config)
	if #left == 0 then
		BR.close(key, "idle")
	end
	return true
end

if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
ChaosCommands.register("leaveroom", function(player)
	BR.leave(player)
end)

-- login: a character inside a room that is not its group's running session goes to the room's exit
function BR.onLogin(player)
	if not RC().loginOut then
		return
	end
	local key, config = BR.roomAt(player:getPosition())
	if not key then
		return
	end
	local s = BR.sessions[key]
	if s and s.guids[player:getGuid()] then
		return -- back in its own running fight
	end
	local exit = config.bossArea.exitPosition
	if exit then
		player:teleportTo(exit)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(player, "The boss room you were in has closed: you are at its exit."))
	end
end

Chaos.registerInstance("bossroom", {label = "a boss room", inside = BR.isInside, at = function(pos)
	return BR.roomAt(pos) ~= nil
end, runs = function()
	local out, now = {}, os.time()
	for key, s in pairs(BR.sessions) do
		local players = creaturesIn(BR.rooms[key])
		out[#out + 1] = {id = key, what = nameOf(BR.rooms[key]) .. (s.state == "won" and " (slain)" or ""),
			left = math.max(0, s.endsAt - now), players = #players, idle = IL.idleLeft(s, {idleSeconds = RC().idleSeconds}, now)}
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end, close = function(id)
	if not BR.sessions[id] then
		return false, "No running boss room " .. tostring(id) .. "."
	end
	BR.close(id, "staff")
	return true, "Boss room " .. tostring(id) .. " closed."
end})

if CreatureEvent then
	local login = CreatureEvent("ChaosBossRoomsLogin")
	function login.onLogin(player)
		local ok, err = pcall(BR.onLogin, player)
		if not ok then
			print("[ChaosBossRooms] login: " .. tostring(err))
		end
		return true
	end
	login:type("login")
	login:register()

	local logout = CreatureEvent("ChaosInstanceLimitsLogout")
	function logout.onLogout(player)
		for key in pairs(IL.lines) do
			IL.leaveLine(key, player)
		end
		return true
	end
	logout:type("logout")
	logout:register()
end

if GlobalEvent then
	-- a clean shutdown: the running rooms close first (everyone to the exit, saved there by the kick)
	local shutdown = GlobalEvent("ChaosBossRoomsShutdown")
	function shutdown.onShutdown()
		for key in pairs(BR.sessions) do
			BR.close(key, "shutdown")
		end
		return true
	end
	shutdown:register()
end
