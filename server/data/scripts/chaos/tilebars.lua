-- Progress bars over tiles (client game_tileoverlays, extended opcode ChaosOpcodes.tileBars = 156; server/README.md
-- "Progress bars over tiles"). Rules and the protocol: tilebars_core.lua (tests/tilebars_test.lua); numbers:
-- tilebars_config.lua. This file is the engine glue: the API for other scripts, the send loop, login / logout and the
-- client's hello.
--
-- API (any script; ids are strings up to 64 characters, one bar per id):
--   ChaosTileBars.set(id, {pos = {x, y, z}, label = "...", progress = 0..1, color = "#rrggbb"})       a bar
--   ChaosTileBars.set(id, {pos, label, endsIn = seconds [, total = seconds], color [, keep = true]})  a countdown; it
--       goes away by itself when it ends unless keep
--   owner = player (or {name, guid}): only that player sees it
--   ChaosTileBars.set again with the same id updates it; ChaosTileBars.progress(id, v) changes the progress alone
--   ChaosTileBars.remove(id), ChaosTileBars.removePrefix("bg:12:") (every bar of one match), ChaosTileBars.get(id)
-- Players get a bar while they are on its floor within rangeX / rangeY tiles; changes are sent on the next tick (the
-- progress alone at most every progressMs). Engine API used: Game.getSpectators, Player(id | name), GlobalEvent,
-- CreatureEvent login / logout / extendedopcode. Lua 5.1 / LuaJIT.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not (ChaosTileBarsCore and ChaosTileBarsCore.plan) then
	dofile("data/scripts/chaos/tilebars_core.lua")
end
Chaos.tileBarsConfig = dofile("data/scripts/chaos/tilebars_config.lua")

ChaosTileBars = ChaosTileBars or {}
local B = ChaosTileBars
local K = ChaosTileBarsCore
local OPCODE = ChaosOpcodes.tileBars or 156
B.state = B.state or K.newState() -- kept over /reload scripts
B.warned = B.warned or {}

local function C()
	return Chaos.tileBarsConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function warn(key, text)
	if not B.warned[key] then
		B.warned[key] = true
		print("[Warning - Chaos] tile bars: " .. text)
	end
end

local function ownerOf(o)
	if o == nil then
		return nil
	end
	if type(o) == "userdata" or (type(o) == "table" and type(o.getGuid) == "function") then
		return {name = o:getName(), guid = o:getGuid()}
	end
	if type(o) == "table" then
		return {name = o.name, guid = o.guid}
	end
	return nil
end

-- set or update a bar; true when it is (or stays) there
function B.set(id, def)
	if not C().enabled or type(def) ~= "table" then
		return false
	end
	local d = {}
	for k, v in pairs(def) do
		d[k] = v
	end
	d.owner = ownerOf(def.owner)
	local r, err = K.set(B.state, id, d, C(), nowMs())
	if r == false then
		warn(tostring(err), tostring(err) .. " (bar " .. tostring(id) .. ")")
		return false
	end
	return true
end

function B.progress(id, v)
	if not C().enabled then
		return false
	end
	return K.setProgress(B.state, id, v, C(), nowMs()) ~= false
end

function B.remove(id)
	return K.remove(B.state, id)
end

function B.removePrefix(prefix)
	return K.removePrefix(B.state, prefix)
end

function B.get(id)
	return B.state.bars[id]
end

local function viewerOf(p)
	return {cid = p:getId(), name = p:getName(), guid = p:getGuid(), pos = p:getPosition(), player = p}
end

-- the send loop
function B.tick()
	local st, c = B.state, C()
	local t = nowMs()
	K.expire(st, c, t)
	if st.count == 0 and next(st.known) == nil then
		return
	end
	local viewers, byCid = {}, {}
	local function add(p)
		local cid = p:getId()
		if not byCid[cid] then
			local v = viewerOf(p)
			byCid[cid] = v
			viewers[#viewers + 1] = v
		end
	end
	for _, b in pairs(st.bars) do
		if b.owner and b.owner.name then
			local p = Player(b.owner.name)
			if p then
				add(p)
			end
		else
			local specs = Game.getSpectators(Position(b.pos.x, b.pos.y, b.pos.z), false, true, c.rangeX, c.rangeX,
				c.rangeY, c.rangeY)
			for _, p in ipairs(specs or {}) do
				add(p)
			end
		end
	end
	for _, cid in ipairs(K.knownViewers(st)) do
		if not byCid[cid] then
			local p = Player(cid)
			if p then
				add(p)
			else
				K.forget(st, cid)
			end
		end
	end
	for _, e in ipairs(K.plan(st, viewers, c, t)) do
		local v = byCid[e.cid]
		for _, data in ipairs(K.messages(e, c)) do
			Chaos.send(v.player, OPCODE, "bars", data)
		end
	end
end

local loop = GlobalEvent("ChaosTileBars")
function loop.onThink(interval)
	local ok, err = pcall(B.tick)
	if not ok then
		warn("tick", "tick error: " .. tostring(err))
	end
	return true
end
loop:interval(C().tickMs or 250)
loop:register()

local login = CreatureEvent("ChaosTileBarsLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTileBarsOpcode")
	player:registerEvent("ChaosTileBarsLogout")
	K.forget(B.state, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosTileBarsLogout")
function logout.onLogout(player)
	K.forget(B.state, player:getId())
	return true
end
logout:type("logout")
logout:register()

local opcode = CreatureEvent("ChaosTileBarsOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	if K.clientAction(Chaos.decode(buffer)) == "hello" then
		-- the client (a new game or a reloaded module) starts empty: everything near it goes out on the next tick
		K.forget(B.state, player:getId())
		Chaos.send(player, OPCODE, "clear", {})
	end
end
opcode:type("extendedopcode")
opcode:register()
