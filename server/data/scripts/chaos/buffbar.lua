-- Buff / debuff bar (client game_buffbar, extended opcode ChaosOpcodes.buffs = 234)
--
-- Sends the character's active buffs and debuffs to a client that asked for them. What counts as a buff and how it
-- looks is data/lib/chaos_buffs.lua (the registry and the sources: engine conditions, class buffs, world buffs, the
-- Victory buff, world events, trial stacks ...). This file is the glue: a once-per-second look at every watching
-- character, the difference to what was sent last (add / update / remove), a full list now and then, and the opcode.
--
-- Protocol (JSON {action, data}):
--   client -> server  sync (start / restart watching, answered with a full list; at most every cfg.requestMs)
--                     off  (the bar is hidden: stop sending)
--   server -> client  full {list = [entry]} | diff {add = [entry], upd = [{k, l, s}], del = [key]}
--                     entry {k key, n name, d description, i icon, t 0 buff / 1 debuff, l ms left (none: no timer), s stacks}
-- The server is the authority: the client only draws and counts the time down from what it was told.
-- Lua 5.1 / LuaJIT compatible. Rules and tests: data/lib/chaos_buffs.lua, tests/buffs_test.lua.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosBuffs then
	dofile("data/lib/chaos_buffs.lua")
end

local B = ChaosBuffs
local OPCODE = ChaosOpcodes.buffs or 234

ChaosBuffBar = ChaosBuffBar or {}
local Bar = ChaosBuffBar
Bar.watch = Bar.watch or {} -- player id -> {sent = {key -> what the client holds}, lastFull = ms}

local function send(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

-- one look at one character: a full list when due, else the difference
function Bar.update(player, w, now, force)
	local items = B.get(player, now, B.cfg.tickMs * 0.9)
	if force or now - (w.lastFull or 0) >= B.cfg.resyncMs then
		w.lastFull = now
		send(player, "full", B.full(w.sent, items, now))
		return
	end
	local d = B.diff(w.sent, items, now)
	if d then
		send(player, "diff", d)
	end
end

-- every watching character is looked at once per tickMs, spread over SLICES shorter ticks by creature id (a full pass
-- over every online character in one tick made a lag spike under load)
local SLICES = 4
local slice = 0
local think = GlobalEvent("ChaosBuffBarThink")
function think.onThink(interval)
	local now = B.nowMs()
	slice = (slice + 1) % SLICES
	for _, player in ipairs(Game.getPlayers()) do
		local id = player:getId()
		local w = id % SLICES == slice and Bar.watch[id]
		if w then
			local ok, err = pcall(Bar.update, player, w, now, false)
			if not ok then
				print("[Chaos buffs] " .. tostring(err))
			end
		end
	end
	return true
end
think:interval(math.max(50, math.floor(B.cfg.tickMs / SLICES)))
think:register()

local login = CreatureEvent("ChaosBuffBarLogin")
function login.onLogin(player)
	player:registerEvent("ChaosBuffBarExtended")
	player:registerEvent("ChaosBuffBarLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosBuffBarLogout")
function logout.onLogout(player)
	Bar.watch[player:getId()] = nil
	B.forget(player:getId())
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosBuffBarExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local id = player:getId()
	if msg.action == "sync" then
		if ChaosRateLimit and not ChaosRateLimit.allow(player, "buffs.sync", B.cfg.requestMs) then
			return
		end
		local w = {sent = {}, lastFull = 0}
		Bar.watch[id] = w
		Bar.update(player, w, B.nowMs(), true)
	elseif msg.action == "off" then
		Bar.watch[id] = nil
	end
end
ext:type("extendedopcode")
ext:register()
