-- Party markers (client game_mapmarkers, extended opcode ChaosOpcodes.mapMarkers = 153; server/README.md "Map markers")
--
-- Every cfg.tickMs the parties with at least one watching member are looked at; each watcher is sent where the
-- members of its party are (name, position, floor, health in steps) when that changed. The rules (who sees whom, the
-- diff, the throttle) are in partymarkers_core.lua (tests/partymarkers_test.lua); the numbers in partymarkers_config.lua.
-- Joining, leaving, a disbanded party, a member logging in or out: seen by the next tick (at most cfg.tickMs later).
-- The client's hello (sent at login and when the option changes) gets an answer at once.
--
-- Protocol (JSON {action, data}; poi.lua shares the opcode and answers the same hello):
--   client -> server  hello {party = true|false, poi = true|false} | set {party = true|false}
--   server -> client  party {m = [{i, n, x, y, z, p}]}     (m empty: no party, or nobody to show)
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/partymarkers_core.lua")

local P = ChaosPartyMarkers
P.cfg = dofile("data/scripts/chaos/partymarkers_config.lua")
local OPCODE = ChaosOpcodes.mapMarkers or 153
P.watch = P.watch or {} -- creature id -> true while the client wants party markers
P.state = P.state or P.newState()
P.stats = P.stats or {ticks = 0, totalMs = 0, maxMs = 0, sends = 0, last = nil}

-- wall time in ms (os.mtime: whole ms, unbiased on average over many ticks; os.clock would count every thread's CPU)
local function clockMs()
	return os.mtime and os.mtime() or os.clock() * 1000
end

-- the scope of a member (partymarkers_core.lua): a battleground match keeps its positions inside its team
local function scopeOf(id)
	local B = ChaosBattleground
	local m = B and B.matchOf and B.matchOf[id]
	local e = m and m.players and m.players[id]
	if e then
		return "bg:" .. tostring(m.id) .. ":" .. tostring(e.team)
	end
	return nil
end

local function plain(player)
	local pos = player:getPosition()
	local id = player:getId()
	return {id = id, name = player:getName(), x = pos.x, y = pos.y, z = pos.z, hp = player:getHealth(),
		hpMax = player:getMaxHealth(), ghost = player:isInGhostMode() == true, scope = scopeOf(id)}
end

-- the members of a party, the leader first: {Player...}
local function membersOf(party)
	local list = {party:getLeader()}
	for _, member in ipairs(party:getMembers() or {}) do
		list[#list + 1] = member
	end
	return list
end

local function encode(list)
	return json.encode({action = "party", data = {m = list}})
end

local function sendTo(ids, list)
	local buffer = encode(list)
	for _, id in ipairs(ids) do
		local p = Player(id)
		if p then
			p:sendExtendedOpcode(OPCODE, buffer)
		end
	end
end

local function clear(id)
	local p = Player(id)
	if p and P.watch[id] then
		p:sendExtendedOpcode(OPCODE, encode({}))
	end
end

local partyOf = {} -- party key -> engine Party, for this tick
local io = {
	read = function(key)
		local party = partyOf[key]
		if not party then
			return nil
		end
		local list = {}
		for _, member in ipairs(membersOf(party)) do
			list[#list + 1] = plain(member)
		end
		return list
	end,
	send = sendTo,
	clear = clear
}

-- watchers grouped by party: key -> {watchers = {id...}}
local function collect()
	local parties = {}
	partyOf = {}
	for id in pairs(P.watch) do
		local player = Player(id)
		local party = player and player:getParty()
		local leader = party and party:getLeader()
		if leader then
			local key = leader:getId()
			local g = parties[key]
			if not g then
				g = {watchers = {}}
				parties[key] = g
				partyOf[key] = party
			end
			g.watchers[#g.watchers + 1] = id
		elseif not player then
			P.watch[id] = nil
		end
	end
	return parties
end

function P.runTick()
	local t0 = clockMs()
	local stats = P.tick(P.state, collect(), io, P.cfg)
	partyOf = {}
	local ms = clockMs() - t0
	local S = P.stats
	S.ticks, S.totalMs, S.sends, S.last = S.ticks + 1, S.totalMs + ms, S.sends + stats.sends, stats
	if ms > S.maxMs then
		S.maxMs = ms
	end
	return stats
end

-- at once, to one watcher (login, option switched on)
function P.sendNow(player)
	local id = player:getId()
	local party = player:getParty()
	local leader = party and party:getLeader()
	if not leader then
		P.state.sent[id] = nil
		player:sendExtendedOpcode(OPCODE, encode({}))
		return
	end
	local members = {}
	for _, member in ipairs(membersOf(party)) do
		members[#members + 1] = plain(member)
	end
	for _, msg in ipairs(P.plan(P.state.sent, members, {id}, P.cfg, true)) do
		sendTo(msg.ids, msg.list)
	end
end

local think = GlobalEvent("ChaosPartyMarkersThink")
function think.onThink(interval)
	local ok, err = pcall(P.runTick)
	if not ok then
		print("[Chaos party markers] " .. tostring(err))
	end
	return true
end
think:interval(P.cfg.tickMs)
think:register()

local login = CreatureEvent("ChaosPartyMarkersLogin")
function login.onLogin(player)
	player:registerEvent("ChaosPartyMarkersExtended")
	player:registerEvent("ChaosPartyMarkersLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosPartyMarkersLogout")
function logout.onLogout(player)
	local id = player:getId()
	P.watch[id] = nil
	P.state.sent[id] = nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosPartyMarkersExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or (msg.action ~= "hello" and msg.action ~= "set") then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	if data.party == nil then
		return
	end
	if msg.action == "set" and ChaosRateLimit and not ChaosRateLimit.allow(player, "markers.set", P.cfg.setMs) then
		return
	end
	local id = player:getId()
	if data.party == true then
		P.watch[id] = true
		P.sendNow(player)
	else
		P.watch[id] = nil
		P.state.sent[id] = nil
	end
end
ext:type("extendedopcode")
ext:register()
