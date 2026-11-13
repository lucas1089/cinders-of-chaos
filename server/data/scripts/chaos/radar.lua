-- Minimap radar (client game_minimapdots, extended opcode ChaosOpcodes.mapMarkers = 153, action `radar`; server/README.md
-- "Minimap radar (O543)")
--
-- Every cfg.intervalMs each player who switched the radar on is sent the monsters (and NPCs, and party members) within
-- cfg.radius tiles on the same floor. The rules (who is listed, the cap, the diff, the scheduler) are in radar_core.lua
-- (tests/radar_test.lua); the numbers, with the plan's mitigations as switches, in radar_config.lua. This file only reads the
-- engine: one Game.getSpectators query of the radius per due watcher, boss names cached per monster type.
--
-- Protocol (JSON {action, data}; partymarkers.lua and poi.lua share the opcode):
--   client -> server  radar {on = true|false}   (sent while the minimap window is visible and the option is on)
--   server -> client  radar {z, r, m = [[x, y, f], ...]}   f: 1 boss, 2 NPC, 4 party member, 0 monster
-- The client sends nothing else; a watcher is dropped at logout. Over 8192 bytes Chaos.send splits the message (the cap keeps it
-- far under that). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/radar_core.lua")

local R = ChaosRadar
R.cfg = R.sanitize(dofile("data/scripts/chaos/radar_config.lua"))
local cfg = R.cfg
local OPCODE = ChaosOpcodes.mapMarkers or 153
R.state = R.state or R.newState()
R.stats = R.stats or {ticks = 0, totalMs = 0, maxMs = 0, sends = 0}
R.bossByName = R.bossByName or {}

local function clockMs()
	return os.mtime and os.mtime() or os.clock() * 1000
end

local function isBoss(monster)
	local name = monster:getName()
	local known = R.bossByName[name]
	if known == nil then
		local ok, res = pcall(function()
			return monster:getType():isBoss()
		end)
		known = ok and res == true
		R.bossByName[name] = known
	end
	return known
end

local function partyMembers(player)
	local party = player:getParty()
	local leader = party and party:getLeader()
	if not leader then
		return {}
	end
	local list = {leader}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	return list
end

local function collect(id)
	local player = Player(id)
	if not player then
		return nil
	end
	local pos = player:getPosition()
	local viewer = {x = pos.x, y = pos.y, z = pos.z}
	if R.inOffArea(pos.x, pos.y, pos.z, cfg.offAreas) then
		return viewer, {}, true
	end
	if cfg.offInInstances and Chaos.inAnyInstance and Chaos.inAnyInstance(player) then
		return viewer, {}, true
	end
	local entries = {}
	local r = cfg.radius
	for _, spec in ipairs(Game.getSpectators(pos, false, false, r, r, r, r) or {}) do
		local isMonster = spec:isMonster()
		if isMonster or (cfg.npcs and spec:isNpc()) then
			local sp = spec:getPosition()
			local e = {x = sp.x, y = sp.y, z = sp.z}
			if isMonster then
				e.boss = cfg.bosses and isBoss(spec) or false
				e.summon = spec:getMaster() ~= nil
			else
				e.npc = true
			end
			entries[#entries + 1] = e
		end
	end
	if cfg.party then
		for _, m in ipairs(partyMembers(player)) do
			if m:getId() ~= id and not m:isInGhostMode() then
				local mp = m:getPosition()
				entries[#entries + 1] = {x = mp.x, y = mp.y, z = mp.z, party = true}
			end
		end
	end
	return viewer, entries, false
end

local io = {
	collect = collect,
	send = function(id, payload)
		local p = Player(id)
		if p then
			Chaos.send(p, OPCODE, "radar", payload)
		end
	end
}

function R.runTick()
	local t0 = clockMs()
	local stats = R.tick(R.state, io, cfg, t0)
	local ms = clockMs() - t0
	local S = R.stats
	S.ticks, S.totalMs, S.sends = S.ticks + 1, S.totalMs + ms, S.sends + stats.sends
	if ms > S.maxMs then
		S.maxMs = ms
	end
	return stats
end

local think = GlobalEvent("ChaosRadarThink")
function think.onThink(interval)
	if next(R.state.watch) then
		local ok, err = pcall(R.runTick)
		if not ok then
			print("[Chaos radar] " .. tostring(err))
		end
	end
	return true
end
think:interval(cfg.tickMs)
think:register()

local login = CreatureEvent("ChaosRadarLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRadarExtended")
	player:registerEvent("ChaosRadarLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosRadarLogout")
function logout.onLogout(player)
	R.setWatch(R.state, player:getId(), false)
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosRadarExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "radar" then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if data.on == nil then
		return
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "radar.set", cfg.setMs) then
		return
	end
	local id = player:getId()
	if data.on == true then
		R.setWatch(R.state, id, true)
	elseif R.setWatch(R.state, id, false) then
		-- one empty list, so the dots on the client vanish at once
		Chaos.send(player, OPCODE, "radar", R.payload(player:getPosition(), {}, cfg))
	end
end
ext:type("extendedopcode")
ext:register()
