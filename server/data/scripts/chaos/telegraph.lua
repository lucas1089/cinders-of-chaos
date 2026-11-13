-- Floor telegraphs (client game_telegraph, extended opcode ChaosOpcodes.monsterbar = 125, actions floor / floorclear /
-- floorhello; server/README.md "Floor telegraphs (O549)"). Rules and the protocol: telegraph_core.lua
-- (tests/telegraph_test.lua); numbers: telegraph_config.lua. This file is the engine glue: the API for the boss scripts,
-- the loop, login / logout and the client's hello.
--
-- API (the boss scripts; every call is safe when this file is not loaded: they check `ChaosTelegraph` first):
--   local h = ChaosTelegraph.open(id, tiles, {ms = ms to the hit, color = "orange", user = "bossMechanics"})
--       tiles = list of {x, y, z}; id = a string up to 64 characters, one mark per id ("bm:<boss id>:<n>"); returns the
--       mark, or nil when the switch is off, the area is too big or the id is bad (draw the sprite marks for everybody then)
--   ChaosTelegraph.move(h, tiles [, ms])     a follow circle moved or locked: everybody near gets the whole area again
--   ChaosTelegraph.draw(h, function(who) ... end)
--       draws the sprite marks of a pulse: who = nil sends them to everybody (nobody near has game_telegraph, or h is nil),
--       who = a player sends them to that one player (position:sendMagicEffect(effect, who)); nothing is called when every
--       player near has game_telegraph
--   ChaosTelegraph.close(id), ChaosTelegraph.closePrefix("bm:12:")     the hit was cancelled / the fight ended
-- A mark ends by itself at its hit time (plus graceMs). Engine API used: Game.getSpectators, Player(id), GlobalEvent,
-- CreatureEvent login / logout / extendedopcode. Lua 5.1 / LuaJIT. Not run on a live server.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not (ChaosTelegraphCore and ChaosTelegraphCore.plan) then
	dofile("data/scripts/chaos/telegraph_core.lua")
end
Chaos.telegraphConfig = dofile("data/scripts/chaos/telegraph_config.lua")

ChaosTelegraph = ChaosTelegraph or {}
local T = ChaosTelegraph
local K = ChaosTelegraphCore
local OPCODE = ChaosOpcodes.monsterbar or 125
T.state = T.state or K.newState() -- kept over /reload scripts
T.warned = T.warned or {}

local function C()
	return Chaos.telegraphConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function warn(key, text)
	if not T.warned[key] then
		T.warned[key] = true
		print("[Warning - Chaos] floor telegraphs: " .. text)
	end
end

-- the players that can see a mark now (its floor, its bounding box and the client's view)
local function spectatorsOf(m)
	if not (Game and Game.getSpectators and Position) then
		return {}
	end
	local c = C()
	local rx, ry = m.hx + (c.rangeX or 9), m.hy + (c.rangeY or 7)
	return Game.getSpectators(Position(m.cx, m.cy, m.z), false, true, rx, rx, ry, ry) or {}
end

local function send(cid, action, data)
	local p = Player(cid)
	if p then
		pcall(Chaos.send, p, OPCODE, action, data)
	end
end

local function deliver(list)
	for _, e in ipairs(list) do
		send(e.cid, e.action or "floorclear", e.data or K.clearPayload(e.id))
	end
end

-- what each capable player near a mark has to be told (the marks are told about once; new viewers get them later)
local function flush()
	local st = T.state
	if st.count == 0 then
		return
	end
	deliver(K.plan(st, function(m)
		local seeing = {}
		for _, p in ipairs(spectatorsOf(m)) do
			local cid = p:getId()
			if K.isCapable(st, cid) then
				seeing[cid] = true
			end
		end
		return seeing
	end, nowMs()))
end

function T.open(id, tiles, opts)
	local c = C()
	if not c.enabled then
		return nil
	end
	if opts and opts.user and c[opts.user] == false then
		return nil
	end
	local m, why = K.open(T.state, id, tiles, opts and opts.ms, nowMs(), c, opts)
	if not m then
		if why == "too many tiles" or why == "too many marks" then
			warn(why, why .. " (mark " .. tostring(id) .. "): its sprite marks go to everybody")
		end
		return nil
	end
	flush()
	return m
end

function T.move(h, tiles, ms)
	if not h or not C().enabled then
		return false
	end
	if T.state.marks[h.id] ~= h then
		return false
	end
	local m = K.move(T.state, h.id, tiles, nowMs(), C(), ms)
	if not m then
		return false
	end
	flush()
	return true
end

function T.draw(h, fn)
	if not h then
		fn(nil)
		return
	end
	local capableN, legacy = 0, {}
	for _, p in ipairs(spectatorsOf(h)) do
		if K.isCapable(T.state, p:getId()) then
			capableN = capableN + 1
		else
			legacy[#legacy + 1] = p
		end
	end
	local mode = K.spriteMode(capableN, #legacy)
	if mode == "all" then
		fn(nil)
	elseif mode == "some" then
		for _, p in ipairs(legacy) do
			fn(p)
		end
	end
end

-- the pulse's sprite effects for one player (who from draw): an effect by name (chaos_vfx, pack and big ids; the offset
-- Vfx adds is added here, Vfx itself has no player argument), else the stock constant (a number or the name of a global)
function T.effectTo(who, pos, name, fallback)
	if not (who and pos) then
		return false
	end
	if name and ChaosBigFx and ChaosBigFx.live then
		pcall(ChaosBigFx.live) -- loads the big ids into ChaosVfx once
	end
	local e = name and ChaosVfx and ChaosVfx[name]
	if e then
		Position(pos.x + e.dx, pos.y + e.dy, pos.z):sendMagicEffect(e.id, who)
		return true
	end
	local stock = fallback
	if type(fallback) == "string" then
		stock = rawget(_G, fallback) -- the name of a constant that this engine may not have
	end
	if stock then
		Position(pos.x, pos.y, pos.z):sendMagicEffect(stock, who)
		return true
	end
	return false
end

-- the warning circle over a round telegraph, for one player: the pair 27 circle when it is on, else the big one
-- (boss_mechanics.lua draws both kinds of circle; the Ascended, guild and raid bosses only the big one: pair27 = false)
function T.circleTo(who, tiles, pair27)
	local P27, B = ChaosPack27Fx, ChaosBigFx
	if pair27 and P27 and P27.PAIR27_FX and P27.live and P27.live() and P27.telegraphCentre then
		local centre = P27.telegraphCentre(tiles)
		if centre then
			return T.effectTo(who, centre, P27.telegraphName)
		end
	end
	if B and B.live and B.live() and B.circleOf then
		local centre, size = B.circleOf(tiles)
		if centre then
			return T.effectTo(who, centre, "big_telegraph_" .. size)
		end
	end
	return false
end

function T.close(id)
	deliver(K.close(T.state, id))
end

function T.closePrefix(prefix)
	deliver(K.closePrefix(T.state, prefix))
end

-- the loop: marks that reached their hit go (and are cleared on the clients), players who came into view get the marks
local loop = GlobalEvent("ChaosTelegraph")
function loop.onThink(interval)
	local ok, err = pcall(function()
		local st = T.state
		if st.count == 0 then
			return
		end
		deliver(K.expire(st, nowMs(), C()))
		flush()
	end)
	if not ok then
		warn("tick", "tick error: " .. tostring(err))
	end
	return true
end
loop:interval(C().tickMs or 250)
loop:register()

local login = CreatureEvent("ChaosTelegraphLogin")
function login.onLogin(player)
	player:registerEvent("ChaosTelegraphOpcode")
	player:registerEvent("ChaosTelegraphLogout")
	K.forget(T.state, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosTelegraphLogout")
function logout.onLogout(player)
	K.forget(T.state, player:getId())
	return true
end
logout:type("logout")
logout:register()

local opcode = CreatureEvent("ChaosTelegraphOpcode")
function opcode.onExtendedOpcode(player, code, buffer)
	if code ~= OPCODE then
		return
	end
	if K.clientHello(Chaos.decode(buffer)) then
		-- this client draws floor marks (a new game or a reloaded module): what is up near it goes out now
		K.forget(T.state, player:getId())
		K.setCapable(T.state, player:getId(), true)
		flush()
	end
end
opcode:type("extendedopcode")
opcode:register()
