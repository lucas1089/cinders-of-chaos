-- Run from the server/ folder: luajit tests/idlehall_test.lua (CI runs it with LuaJIT and Lua 5.3).
-- The Idle Hall (server/README.md "Idle Hall"): idlehall_core.lua (the idle timer, samples, pushes, the engine's idle
-- time, the warning then the move, the town rule, the exemptions, the opcodes, the texts, the config check), then
-- idlehall.lua against a mocked engine: idle in a temple -> warning at 9 min -> moved at 10 with the effect; a step, a
-- turn, an item move, a trade, a window request, a spell, a chat line each start the timer again; being pushed does
-- not; staff, an instance, exercise training, a house, a tile outside a town and a hall missing from the map leave the
-- character alone; the fixtures are placed once; nobody is moved out of the hall.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end
local function eq(a, b, what)
	ok(a == b, (what or "check") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/idlehall_core.lua")
local K = ChaosIdleHallCore
local cfg = dofile("data/scripts/chaos/idlehall_config.lua")
local MIN = 60000

-- ====================================================================== core: config
local problems = K.validate(cfg)
eq(#problems, 0, "the config is valid: " .. table.concat(problems, "; "))
eq(cfg.idleMinutes, 10, "idle 10 minutes by default")
eq(cfg.warnSeconds, 60, "the warning a minute before")
local bad = K.validate({idleMinutes = 1, warnSeconds = 90, slices = 0, aid = {fixture = 1}, hall = {},
	slots = {dummies = {{1, 1}, {1, 1}}, sign = {1, 1}}, items = {}})
ok(#bad >= 6, "a bad config is refused: " .. table.concat(bad, "; "))

-- ====================================================================== core: the timer
local st = K.newState(0)
eq(K.due(cfg, st, 8 * MIN), nil, "8 minutes: nothing")
eq(K.due(cfg, st, 9 * MIN), "warn", "9 minutes: the warning")
local function look(zone, exempt)
	return function() return {zone = zone, exempt = exempt, zoneReason = zone and "town" or "away"} end
end
eq(K.step(cfg, st, 9 * MIN, look(true)), "warn", "step: warn in town")
ok(st.warned, "warned")
eq(K.step(cfg, st, 9 * MIN + 30000, look(true)), nil, "warned: nothing until the time")
eq(K.step(cfg, st, 10 * MIN, look(true)), "move", "10 minutes: the move")
K.moved(st, 10 * MIN)
ok(not st.warned and st.at == 10 * MIN and st.key == nil, "after the move: a fresh start")
-- an action resets the timer and the warning
st = K.newState(0)
K.step(cfg, st, 9 * MIN, look(true))
K.touch(st, 9 * MIN + 10000)
eq(K.due(cfg, st, 10 * MIN), nil, "an action after the warning: no move")
eq(K.due(cfg, st, 18 * MIN + 10000), "warn", "warned again a full idle time later")
-- the move never comes without the warning and never sooner than warnSeconds after it
st = K.newState(0)
eq(K.step(cfg, st, 25 * MIN, look(true)), "warn", "first seen due late: the warning first")
eq(K.step(cfg, st, 25 * MIN + 59000, look(true)), nil, "no move 59 s after the warning")
eq(K.step(cfg, st, 26 * MIN, look(true)), "move", "the move a minute after the warning")
-- outside a town / exempt: nothing, checked again after recheckSeconds
st = K.newState(0)
local a, why = K.step(cfg, st, 9 * MIN, look(false))
ok(a == nil and why == "away", "outside a town: nothing (" .. tostring(why) .. ")")
ok(not st.warned, "no warning outside a town")
local looked = 0
local function counting() looked = looked + 1 return {zone = true} end
eq(K.step(cfg, st, 9 * MIN + 30000, counting), nil, "before the recheck: not looked at")
eq(looked, 0, "the look is skipped until the recheck")
eq(K.step(cfg, st, 10 * MIN, counting), "warn", "after the recheck, in town: the warning")
eq(looked, 1, "looked once")
a, why = K.step(cfg, K.newState(0), 9 * MIN, look(true, "staff"))
ok(a == nil and why == "staff", "staff: nothing")
looked = 0
st = K.newState(0)
K.step(cfg, st, 3 * MIN, counting)
eq(looked, 0, "not due: the town rule is never asked (the cheap path)")

-- ====================================================================== core: samples, pushes, the engine
st = K.newState(0)
local k1, k2 = K.posKey({x = 100, y = 200, z = 7}), K.posKey({x = 101, y = 200, z = 7})
ok(k1 ~= k2 and K.posKey({x = 100, y = 200, z = 6}) ~= k1, "one key per tile")
eq(K.sample(st, k1, 2, 1000), nil, "the first sample is the baseline")
eq(st.at, 0, "the baseline is no action")
eq(K.sample(st, k1, 2, 5 * MIN), nil, "the same tile and direction: nothing")
eq(K.sample(st, k2, 2, 6 * MIN), "moved", "a step")
eq(st.at, 6 * MIN, "a step starts the timer again")
eq(K.sample(st, k2, 3, 7 * MIN), "turned", "a turn")
eq(st.at, 7 * MIN, "a turn starts the timer again")
eq(K.sample(st, k1, 3, 8 * MIN, k1), "pushed", "pushed onto a tile")
eq(st.at, 7 * MIN, "being pushed is no action")
eq(K.sample(st, k1, 3, 9 * MIN), nil, "still there: nothing")
ok(K.engineIdle(st, 10 * MIN, 30000), "the engine saw a newer action")
eq(st.at, 10 * MIN - 30000, "the engine's action counts")
ok(not K.engineIdle(st, 11 * MIN, 5 * MIN), "an older engine action changes nothing")
ok(not K.engineIdle(st, 11 * MIN, nil), "no engine idle time")

-- ====================================================================== core: the town rule
local temples = K.temples(cfg, {{id = 1, pos = {x = 1000, y = 1000, z = 7}}, {id = 2, pos = {x = 5000, y = 5000, z = 7}}})
eq(#temples, 2, "every town")
eq(#K.temples({town = {townIds = {2}}}, {{id = 1, pos = {x = 1, y = 1, z = 7}}, {id = 2, pos = {x = 2, y = 2, z = 7}}}), 1,
	"townIds limits the towns")
local pz, open, house = {pz = true}, {pz = false}, {pz = true, house = true}
local function zone(x, y, z, tile, c)
	local r, reason = K.townZone(c or cfg, {x = x, y = y, z = z}, tile, temples)
	return r, reason
end
ok(zone(1000, 1000, 7, pz), "the temple")
ok(zone(1050, 960, 6, pz), "a depot near the temple, a floor up")
ok(not zone(1061, 1000, 7, pz), "beyond the radius")
ok(not zone(1000, 1000, 10, pz), "three floors down")
eq(select(2, zone(1000, 1001, 7, open)), "nopz", "no protection zone (a hunt, the streets outside)")
eq(select(2, zone(1000, 1001, 7, nil)), "nopz", "no tile")
eq(select(2, zone(1001, 1001, 7, house)), "house", "a house")
local boxed = {town = {radius = 60, floors = 2, exclude = {{from = {x = 990, y = 990, z = 7}, to = {x = 995, y = 995, z = 7}}},
	include = {{from = {x = 3000, y = 3000, z = 7}, to = {x = 3010, y = 3010, z = 7}}}}}
eq(select(2, zone(992, 993, 7, pz, boxed)), "excluded", "an excluded box (a boat)")
ok(zone(3005, 3005, 7, pz, boxed), "an included box far from a temple")
ok(not zone(3005, 3005, 7, open, boxed), "an included box still needs a protection zone")
ok(not zone(cfg.hall.at.x + 22, cfg.hall.at.y + 13, 7, pz), "the hall is no town (nobody is moved out of it)")

-- exemptions, opcodes, texts
eq(K.exempt({staff = true}), "staff", "staff")
eq(K.exempt({instance = true}), "instance", "instance")
eq(K.exempt({training = true}), "training", "training")
eq(K.exempt({}), nil, "a player")
local set = K.opcodeSet(cfg, ChaosOpcodes)
ok(set[ChaosOpcodes.market] and set[ChaosOpcodes.stash] and set[ChaosOpcodes.shop], "market, stash and store count")
ok(not set[ChaosOpcodes.nameplate] and not set[ChaosOpcodes.buffs], "automatic opcodes do not count")
eq(K.slotPos({x = 10, y = 20, z = 7}, {1, 2}).y, 22, "slot position")
local wk = K.warnText(cfg)
ok(wk:find("Idle Hall in 1 minute", 1, true), "the warning says 1 minute")
local wk2, wa2 = K.warnText({warnSeconds = 30})
ok(wk2:find("%d seconds", 1, true) and wa2[1] == 30, "another warning time")
local sign = K.signText()
ok(sign:find("Idle Hall", 1, true) and sign:find("Quem fica parado", 1, true), "the sign in both languages")
-- every text has its pt-BR entry
local strings = dofile("data/scripts/chaos/i18n_strings.lua")
local mk = K.movedText(cfg)
for _, key in ipairs({wk, wk2, mk}) do
	ok(strings["pt-BR"][key], "pt-BR entry for: " .. key)
end

-- ====================================================================== idlehall.lua on a mocked engine
local registry, globals = {}, {}
function CreatureEvent(name)
	local o = {name = name}
	function o:type(t) self.t = t end
	function o:register() registry[name] = o end
	return o
end
function GlobalEvent(name)
	local o = {}
	function o:register() globals[name] = o end
	function o:interval(ms) self.ms = ms end
	return o
end
EventCallback = {register = function() return true end}
MESSAGE_EVENT_ADVANCE, MESSAGE_STATUS_WARNING = 19, 18
TILESTATE_PROTECTIONZONE, ITEM_ATTRIBUTE_TEXT, CONST_ME_TELEPORT = 1, 9, 11
local clock = 0
os.mtime = function() return clock end
local effects = {}
local function pos(x, y, z)
	local p = {x = x, y = y, z = z}
	function p:sendMagicEffect(e) effects[#effects + 1] = {x = self.x, y = self.y, e = e} end
	return p
end
Position = pos
local tiles = {}
local function tkey(p) return p.x .. "," .. p.y .. "," .. p.z end
local function addTile(x, y, z, flags)
	local t = {items = {}, pz = flags.pz, house = flags.house, ground = true, pos = {x = x, y = y, z = z}}
	function t:hasFlag(f) return f == TILESTATE_PROTECTIONZONE and self.pz end
	function t:getHouse() return self.house and {} or nil end
	function t:getGround() return self.ground end
	function t:getItems() return self.items end
	function t:getTopCreature() return self.creature end
	tiles[tkey(t.pos)] = t
	return t
end
function Tile(p) return tiles[tkey(p)] end
local created = {}
Game = {towns = {}, players = {}}
function Game.getTowns() return Game.towns end
function Game.getPlayers() return Game.players end
function Game.createItem(id, n, p)
	local t = tiles[tkey(p)]
	local it = {id = id, attrs = {}}
	function it:getActionId() return self.aid or 0 end
	function it:setActionId(v) self.aid = v end
	function it:setAttribute(k, v) self.attrs[k] = v end
	t.items[#t.items + 1] = it
	created[#created + 1] = it
	return it
end
local function town(id, x, y, z)
	return {getId = function() return id end, getTemplePosition = function() return pos(x, y, z) end}
end
Game.towns = {town(1, 1000, 1000, 7)}
-- the temple and its square (pz), a house, a street, the hall's floor (arrival and slots)
for x = 995, 1005 do
	for y = 995, 1005 do
		addTile(x, y, 7, {pz = true})
	end
end
addTile(1010, 1000, 7, {pz = true, house = true})
addTile(1020, 1000, 7, {pz = false})
local H = cfg.hall.at
local function hallTile(off) return addTile(H.x + off[1], H.y + off[2], H.z, {pz = true}) end
local hallTiles = {hallTile(cfg.hall.arrival), hallTile(cfg.slots.sign)}
for _, o in ipairs(cfg.slots.dummies) do hallTiles[#hallTiles + 1] = hallTile(o) end
for _, o in ipairs(cfg.slots.benches) do hallTiles[#hallTiles + 1] = hallTile(o) end

local nextId = 0
local function newPlayer(x, y, z)
	nextId = nextId + 1
	local p = {id = 0x10000000 + nextId * 10, pos = pos(x, y, z), dir = 2, msgs = {}, storage = {}, access = false, events = {}}
	function p:getId() return self.id end
	function p:getPlayer() return self end
	function p:getPosition() return pos(self.pos.x, self.pos.y, self.pos.z) end
	function p:getDirection() return self.dir end
	function p:getStorageValue(k) return self.storage[k] or -1 end
	function p:getGroup() local me = self return {getAccess = function() return me.access end} end
	function p:registerEvent(n) self.events[n] = true end
	function p:teleportTo(to) self.pos = pos(to.x, to.y, to.z) return true end
	function p:sendTextMessage(t, text) self.msgs[#self.msgs + 1] = {t = t, text = text} end
	Game.players[#Game.players + 1] = p
	registry.ChaosIdleHallLogin.onLogin(p)
	return p
end

dofile("data/scripts/chaos/idlehall.lua")
local IH = ChaosIdleHall
ok(registry.ChaosIdleHallLogin and registry.ChaosIdleHallLogout, "the creature events")
ok(not registry.ChaosIdleHallOpcode, "no opcode handler of its own")
-- two module handlers in the opcode dispatch: the market's (counts) and the name plates' (sent on their own: does not)
local D = Chaos.opcodeDispatch
local marketCalls, plateCalls = 0, 0
do
	local OPCODE = ChaosOpcodes.market
	D.add("TestMarket", function(player, op, buffer) if op ~= OPCODE then return end marketCalls = marketCalls + 1 end)
end
do
	local OPCODE = ChaosOpcodes.nameplate
	D.add("TestPlates", function(player, op, buffer) if op ~= OPCODE then return end plateCalls = plateCalls + 1 end)
end
ok(globals.ChaosIdleHallThink and globals.ChaosIdleHallStartup, "the think and the startup")
ok(type(EventCallback.onItemMoved) == "function" and type(EventCallback.onMoveCreature) == "function"
	and type(EventCallback.onTradeRequest) == "function" and type(EventCallback.onTradeAccept) == "function", "the callbacks")
globals.ChaosIdleHallStartup.onStartup()
eq(#IH.temples, 1, "the temples read at startup")
eq(#created, #cfg.slots.dummies + #cfg.slots.benches + 1, "the dummies, benches and the sign")
local sign = Tile(K.slotPos(H, cfg.slots.sign)).items[1]
ok(sign and sign.id == cfg.items.sign and sign.attrs[ITEM_ATTRIBUTE_TEXT] == K.signText(), "the sign and its text")
eq(Tile(K.slotPos(H, cfg.slots.dummies[1])).items[1].id, 27751, "an exercise dummy")
eq(Tile(K.slotPos(H, cfg.slots.dummies[2])).items[1].id, 27752, "the other dummy")
IH.placeFixtures()
eq(#created, #cfg.slots.dummies + #cfg.slots.benches + 1, "placed once (found again by the action id)")

-- run the think for `ms` of game time (each tick one slice)
local function run(ms)
	local stop = clock + ms
	while clock < stop do
		clock = clock + cfg.thinkMs
		globals.ChaosIdleHallThink.onThink(cfg.thinkMs)
	end
end
local function said(p, pattern)
	for _, m in ipairs(p.msgs) do
		if m.text:find(pattern, 1, true) then
			return m
		end
	end
	return nil
end
local function inHall(p)
	local a = IH.arrival()
	return p.pos.x == a.x and p.pos.y == a.y and p.pos.z == a.z
end

-- idle in the temple: warned at 9 minutes, moved at 10
local idle = newPlayer(1000, 1000, 7)
run(8 * MIN + 30000)
ok(not said(idle, "Idle Hall"), "no warning before 9 minutes")
run(40000)
local w = said(idle, "in 1 minute")
ok(w and w.t == MESSAGE_STATUS_WARNING, "the warning at 9 minutes")
ok(not inHall(idle), "not moved at the warning")
run(50000)
ok(not inHall(idle), "not moved before 10 minutes")
run(25000)
ok(inHall(idle), "moved to the hall at 10 minutes")
ok(said(idle, "were moved to the Idle Hall"), "the message after the move")
local fx = 0
for _, e in ipairs(effects) do
	if e.e == CONST_ME_TELEPORT then fx = fx + 1 end
end
eq(fx, 2, "an effect where it left and where it landed")
run(30 * MIN)
ok(inHall(idle), "nobody is moved out of the hall")
eq(#idle.msgs, 2, "one warning and one move, nothing in the hall")

-- every kind of action starts the timer again
local function stays(name, act)
	local p = newPlayer(1001, 1001, 7)
	run(8 * MIN)
	act(p)
	run(5 * MIN)
	ok(not said(p, "Idle Hall"), name .. ": no warning 5 minutes after it")
	run(5 * MIN)
	ok(said(p, "in 1 minute"), name .. ": warned once idle again")
	p.pos = pos(1003, 1003, 7) -- leave the queue of the next case alone
	return p
end
stays("a step", function(p) p.pos = pos(1002, 1001, 7) end)
stays("a turn", function(p) p.dir = 3 end)
stays("an item moved", function(p) EventCallback.onItemMoved(p) end)
stays("a trade", function(p) eq(EventCallback.onTradeRequest(p, nil, nil), true, "trade allowed") end)
stays("a trade accepted", function(p) eq(EventCallback.onTradeAccept(newPlayer(999, 999, 7), p), true, "accept allowed") end)
stays("the market window", function(p) D.dispatch(p, ChaosOpcodes.market, "{}") end)
eq(marketCalls, 1, "the market's handler still answers")
IH.installHooks()
eq(IH.wrapOpcodes(), 0, "wrapped once")
stays("pushing someone", function(p) eq(EventCallback.onMoveCreature(p, newPlayer(997, 997, 7), nil, pos(998, 997, 7)), true, "push allowed") end)
stays("a spell", function(p)
	for _, h in ipairs(ChaosSpellEvents.handlers.cast) do
		if h.key == "idlehall" then h.fn(p) end
	end
end)
ChaosReports = {onChannelSpeak = function() return true end}
IH.installHooks()
stays("a chat line", function(p) ChaosReports.onChannelSpeak(p, "World Chat", 1, "hi") end)

-- not actions: an automatic opcode, being pushed
local auto = newPlayer(1002, 1002, 7)
run(8 * MIN)
D.dispatch(auto, ChaosOpcodes.nameplate, "{}")
eq(plateCalls, 1, "the name plates' handler answers")
run(MIN + 30000)
ok(said(auto, "in 1 minute"), "an automatic opcode is no action")
local pushed = newPlayer(999, 1000, 7)
run(5 * MIN)
EventCallback.onMoveCreature(newPlayer(998, 998, 7), pushed, pushed:getPosition(), pos(999, 1001, 7))
pushed.pos = pos(999, 1001, 7)
run(4 * MIN + 30000)
ok(said(pushed, "in 1 minute"), "being pushed is no action (the crowded temple)")
run(MIN)
ok(inHall(pushed), "the pushed idle character is moved")

-- left alone: staff, an instance, training, a house, outside a town
local function leftAlone(name, p)
	run(12 * MIN)
	ok(not said(p, "Idle Hall") and not inHall(p), name .. ": left alone")
end
local gm = newPlayer(1004, 1004, 7)
gm.access = true
leftAlone("staff", gm)
local inst = newPlayer(1004, 1003, 7)
Chaos.registerInstance("idletest", {label = "Test", inside = function(pl) return pl == inst end})
leftAlone("an instance", inst)
local trainee = newPlayer(1004, 1002, 7)
trainee.storage[cfg.trainingStorage] = 1
leftAlone("exercise training", trainee)
leftAlone("a house", newPlayer(1010, 1000, 7))
leftAlone("outside a protection zone", newPlayer(1020, 1000, 7))
-- training ends: moved like anyone
trainee.storage[cfg.trainingStorage] = 0
run(2 * MIN + 30000)
ok(inHall(trainee), "after training: moved")

-- logout forgets the character
registry.ChaosIdleHallLogout.onLogout(gm)
eq(IH.states[gm:getId()], nil, "logout forgets")

-- no hall on the map: nobody is warned or moved
for _, t in ipairs(hallTiles) do
	tiles[tkey(t.pos)] = nil
end
local nohall = newPlayer(1005, 1005, 7)
run(15 * MIN)
ok(not said(nohall, "Idle Hall") and nohall.pos.x == 1005, "no hall: nothing happens")

-- the cost: one slice per tick, each character sampled once per slices ticks
local samples = 0
local realCheck = IH.check
IH.check = function(...) samples = samples + 1 return realCheck(...) end
local n = #Game.players
run(cfg.slices * cfg.thinkMs)
IH.check = realCheck
eq(samples, n, "each character once per round of slices")

print(string.format("idlehall_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
