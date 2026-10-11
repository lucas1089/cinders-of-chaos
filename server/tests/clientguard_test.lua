-- Run from the server/ folder: luajit tests/clientguard_test.lua (and lua5.3; CI runs both)
-- The client guard's Lua check (clientguard_core.lua, clientguard.lua against a mocked engine): which connections must
-- say hello, the hello's checks, the timeout, logout; the opcodes. The engine half (login gate, HMAC handshake) is C++
-- (src-patch 0021) and was tested end to end (server/README.md "Client guard").
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/clientguard_config.lua")
dofile("data/scripts/chaos/clientguard_core.lua")
local G = ChaosClientGuard
local cfg = Chaos.clientGuard

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

-- ---------------------------------------------------------------- opcodes
eq(ChaosOpcodes.clientGuard, 189, "handshake opcode (engine ClientGuard::HANDSHAKE_OPCODE, client chaosguard::OPCODE)")
eq(ChaosOpcodes.clientGuardHello, 190, "hello opcode (client game_chaosguard)")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	eq(seen[v], nil, "opcode " .. v .. " used twice (" .. name .. ")")
	seen[v] = name
end
for _, v in ipairs({ 1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 144, 145, 146, 210, 212, 213, 230, 246 }) do
	eq(v == 189 or v == 190, false, "base opcode " .. v .. " is not a client guard opcode")
end
-- the engine's numbers are the same in the C++ header the patch adds (read from the patch file)
local patch = io.open("src-patches/0021-client-guard.patch")
if patch then
	local text = patch:read("*a")
	patch:close()
	eq(text:find("HANDSHAKE_OPCODE = 189", 1, true) ~= nil, true, "patch 0021 uses opcode 189")
	eq(text:find("CLIENT_ID_TAG = 0x4343", 1, true) ~= nil, true, "patch 0021 identifier tag")
end

-- ---------------------------------------------------------------- which connections are checked
local function info(state, mode, build)
	return { mode = mode or "enforce", state = state, official = build ~= nil, build = build or 0 }
end
eq(G.shouldCheck(nil, cfg), false, "engine without patch 0021")
eq(G.shouldCheck(info("verified", "off"), cfg), false, "guard off")
eq(G.shouldCheck(info("none"), cfg), false, "state none")
eq(G.shouldCheck(info("bypass"), cfg), false, "staff from a staff IP")
eq(G.shouldCheck(info("failed"), cfg), false, "already failed")
eq(G.shouldCheck(info("pending", "enforce", 7), cfg), true, "pending")
eq(G.shouldCheck(info("verified", "enforce", 7), cfg), true, "verified")
eq(G.shouldCheck(info("logged", "log"), cfg), true, "log mode, stock client")

-- ---------------------------------------------------------------- hello
local function hello(build, modules, action)
	return { action = action or "hello", data = { build = build, modules = modules } }
end
eq(G.login(1, 100, info("pending", "enforce", 7), cfg), true, "watched")
eq(G.expire(1, 100 + cfg.helloTimeout - 1, cfg), nil, "not due yet")
local ok, why = G.hello(1, hello(7, 60), cfg)
eq(ok, true, "good hello")
eq(why, nil, "no reason")
eq(G.expire(1, 1000, cfg), nil, "done: never expires")
ok = G.hello(1, hello(1, 0), cfg)
eq(ok, true, "a second hello is ignored")

G.login(2, 100, info("verified", "enforce", 7), cfg)
ok, why = G.hello(2, hello(6, 60), cfg)
eq(ok, false, "other build")
eq(why, "module hello for build 6, the login said build 7", "build reason")

G.login(3, 100, info("verified", "enforce", 7), cfg)
ok, why = G.hello(3, hello(7, cfg.minModules - 1), cfg)
eq(ok, false, "too few modules")
eq(why:find("only 19 of our client modules", 1, true) ~= nil, true, "modules reason")

G.login(4, 100, info("verified", "enforce", 7), cfg)
eq(select(2, G.hello(4, nil, cfg)), "malformed module hello", "not JSON")
G.login(4, 100, info("verified", "enforce", 7), cfg)
eq(select(2, G.hello(4, hello(7, 60, "hi"), cfg)), "malformed module hello", "other action")
G.login(4, 100, info("verified", "enforce", 7), cfg)
eq(select(2, G.hello(4, { action = "hello", data = { build = "x", modules = 3 } }, cfg)), "malformed module hello", "build not a number")

-- a stock client let in by the log mode has no build to compare: any build passes, the modules still count
G.login(5, 100, info("logged", "log"), cfg)
eq((G.hello(5, hello(99, 60), cfg)), true, "log mode, unknown build")

-- not watched: a hello is ignored
eq((G.hello(77, hello(1, 0), cfg)), true, "unwatched")
eq(G.login(6, 100, info("bypass"), cfg), false, "staff not watched")
eq((G.hello(6, nil, cfg)), true, "staff hello ignored")

-- ---------------------------------------------------------------- timeout and logout
G.login(8, 100, info("verified", "enforce", 7), cfg)
eq(G.expire(8, 100 + cfg.helloTimeout, cfg), "no module hello from the client within 30 s", "overdue")
eq(G.expire(8, 100 + cfg.helloTimeout + 5, cfg), nil, "reported once")
G.login(9, 100, info("verified", "enforce", 7), cfg)
G.logout(9)
eq(G.watch[9], nil, "logout clears")
eq(G.expire(9, 1000, cfg), nil, "nothing after logout")

-- ---------------------------------------------------------------- clientguard.lua against a mocked engine
local events, timers, failures = {}, {}, {}
function CreatureEvent(name)
	local e = { name = name }
	function e:type(t) self.kind = t end
	function e:register() events[self.name] = self end
	return e
end
function addEvent(fn, delay, ...)
	timers[#timers + 1] = { fn = fn, delay = delay, args = { ... } }
end
local now = 1000
local realTime = os.time
os.time = function() return now end -- luacheck: ignore
local decoded = {}
json = { decode = function(s) return assert(decoded[s], "unexpected json " .. tostring(s)) end }
local players = {}
local function newPlayer(id, guard)
	local p = { id = id, guard = guard, registered = {} }
	function p:getId() return self.id end
	function p:getClientGuard() return self.guard end
	function p:registerEvent(n) self.registered[n] = true end
	function p:clientGuardFail(reason) failures[#failures + 1] = { id = self.id, reason = reason } return true end
	players[id] = p
	return p
end
function Player(id) return players[id] end
dofile("data/scripts/chaos/clientguard.lua")
eq(events.ChaosClientGuardLogin.kind, "login", "login event")
eq(events.ChaosClientGuardHello.kind, "extendedopcode", "hello event")
eq(events.ChaosClientGuardLogout.kind, "logout", "logout event")

local a = newPlayer(1001, info("pending", "enforce", 3))
eq(events.ChaosClientGuardLogin.onLogin(a), true, "login goes on")
eq(a.registered.ChaosClientGuardHello, true, "hello event registered")
eq(#timers, 1, "one check scheduled")
eq(timers[1].delay, cfg.helloTimeout * 1000 + 250, "after the timeout")
decoded.good = hello(3, 85)
events.ChaosClientGuardHello.onExtendedOpcode(a, 207, "ignored: another opcode")
events.ChaosClientGuardHello.onExtendedOpcode(a, 190, "good")
now = now + 60
timers[1].fn(table.unpack and table.unpack(timers[1].args) or unpack(timers[1].args))
eq(#failures, 0, "a good hello: no failure")

local b = newPlayer(1002, info("verified", "enforce", 3))
events.ChaosClientGuardLogin.onLogin(b)
now = now + cfg.helloTimeout + 1
timers[2].fn(1002)
eq(#failures, 1, "no hello: failure")
eq(failures[1].reason, "no module hello from the client within 30 s", "reason")

local c = newPlayer(1003, info("verified", "enforce", 3))
events.ChaosClientGuardLogin.onLogin(c)
decoded.few = hello(3, 2)
events.ChaosClientGuardHello.onExtendedOpcode(c, 190, "few")
eq(#failures, 2, "too few modules: failure")
events.ChaosClientGuardLogout.onLogout(c)
eq(G.watch[1003], nil, "logout")

local d = newPlayer(1004, info("bypass"))
events.ChaosClientGuardLogin.onLogin(d)
eq(d.registered.ChaosClientGuardHello, nil, "staff: no hello expected")
eq(#timers, 3, "staff: no check scheduled")

local e = newPlayer(1005, nil) -- engine without the patch / no connection
e.getClientGuard = nil
eq(events.ChaosClientGuardLogin.onLogin(e), true, "engine without patch 0021")
players[1002] = nil
timers[2].fn(1002) -- logged out meanwhile: nothing
eq(#failures, 2, "nothing for a player gone")
os.time = realTime -- luacheck: ignore

print("clientguard_test: " .. checks .. " checks OK")
