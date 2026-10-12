-- Run from the server/ folder: luajit tests/kitewalk_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers "Keep attacking while moving" (server/README.md): the opcode and the storage block, the client option's message
-- (kitewalk_core.lua), the storage the engine reads (src-patch 0028, Game::playerMove / playerAutoWalk), the engine
-- patch's shape (the chase waits for the player's own walk, the steps keep the attack task, the end of the walk starts
-- the chase again), and the glue (kitewalk.lua) against a mocked engine: the login registers the opcode event,
-- {on = false} turns it off, {on = true} back on, a repeated message writes nothing, another opcode and junk are
-- ignored. The walking and attacking themselves are C++ and were tested live (server/README.md).
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/kitewalk_core.lua")
local K = ChaosKiteWalk

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what)
	ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

-- ------------------------------------------------------------------ opcode and storage
eq(ChaosOpcodes.kiteWalk, 186, "opcode")
local seen = {}
for name, v in pairs(ChaosOpcodes) do
	ok(seen[v] == nil, "opcode " .. v .. " used twice (" .. name .. ", " .. tostring(seen[v]) .. ")")
	seen[v] = name
end
for _, v in ipairs({1, 67, 73, 89, 91, 92, 99, 106, 107, 136, 181, 201, 202, 140, 144, 145, 146, 210, 212, 213, 230, 246}) do
	ok(ChaosOpcodes.kiteWalk ~= v, "not a base opcode " .. v)
end
eq(Chaos.storage.kiteWalkOff, 7101820, "storage")
for name, v in pairs(Chaos.storage) do
	if type(v) == "number" and name ~= "kiteWalkOff" then
		ok(v < 7101820 or v > 7101829, "storage block 7101820 - 7101829 is free of " .. name)
	end
end

-- ------------------------------------------------------------------ the engine patch
local patch
local f = io.open("src-patches/0028-kite-walk.patch", "r")
if f then
	patch = f:read("*a")
	f:close()
end
ok(patch ~= nil, "the kite walk src-patch is present")
if patch then
	ok(patch:find("CHAOS_KITE_WALK_OFF = 7101820;", 1, true) ~= nil, "engine storage key matches")
	ok(patch:find("off == 1", 1, true) ~= nil, "engine: only 1 turns it off")
	ok(patch:find("+\tplayer->setKiteWalk(chaosKiteWalkOn(player));", 1, true) ~= nil, "a key step is a kite walk")
	ok(patch:find("+\tplayer->setKiteWalk(!listDir.empty() && !player->isMovementBlocked() && chaosKiteWalkOn(player));", 1,
		true) ~= nil, "a click path is a kite walk")
	ok(patch:find("followCreature == attackedCreature && isKiteWalking()", 1, true) ~= nil,
		"the chase of the target waits for the walk")
	ok(patch:find("!keepsWalkPathOnFollow(creature)", 1, true) ~= nil, "a new chase keeps the path")
	ok(patch:find("if (!creature && !kiteWalk) {", 1, true) ~= nil, "losing the target keeps the path")
	ok(patch:find("+\tendKiteWalk();", 1, true) ~= nil, "the end of the walk starts the chase again")
	ok(patch:find("Game::updateCreatureWalk", 1, true) ~= nil, "the chase starts again by itself")
	-- the steps of a kite walk with a target leave the attack task alone; the stock lines stay for every other walk
	local onWalk = patch:match("void Player::onWalk%(Direction& dir%)(.-)\n }\n")
	ok(onWalk ~= nil, "Player::onWalk is patched")
	if onWalk then
		local skip = onWalk:find("if (attackedCreature) {", 1, true)
		local stock = onWalk:find(" \tsetNextActionTask(nullptr);", 1, true)
		ok(skip ~= nil and stock ~= nil and skip < stock, "the kite step returns before the stock cancel")
	end
	-- monsters keep their chase: only the player overrides the hook
	ok(patch:find("virtual bool keepsWalkPathOnFollow(const Creature*) const {\n+\t\t\treturn false;", 1, true) ~= nil,
		"the creature default keeps the stock behaviour")
end

-- ------------------------------------------------------------------ the message
eq(K.storageValue({on = false}), K.OFF, "off")
eq(K.storageValue({on = true}), K.ON, "on")
eq(K.storageValue({on = 0}), K.OFF, "0 is off")
eq(K.storageValue({on = "1"}), K.ON, "text 1")
eq(K.storageValue({on = "true"}), K.ON, "text true")
eq(K.storageValue({action = "set", data = {on = false}}), K.OFF, "the action / data form")
eq(K.storageValue({on = "maybe"}), nil, "junk value")
eq(K.storageValue({}), nil, "no value")
eq(K.storageValue(nil), nil, "no message")
eq(K.storageValue("on"), nil, "not a table")

-- the engine's reading: unset (-1) and 0 are on, only 1 is off
eq(K.isOn(-1), true, "unset is on")
eq(K.isOn(nil), true, "nil is on")
eq(K.isOn(0), true, "0 is on")
eq(K.isOn(1), false, "1 is off")
eq(K.isOn(2), true, "anything else is on")

eq(K.update(-1, {on = true}), nil, "on while on: no write")
eq(K.update(-1, {on = false}), K.OFF, "off while on: write")
eq(K.update(1, {on = false}), nil, "off while off: no write")
eq(K.update(1, {on = true}), K.ON, "on while off: write")
eq(K.update(1, nil), nil, "junk: no write")

-- ------------------------------------------------------------------ glue against a mocked engine
local events = {}
function CreatureEvent(name)
	local e = {name = name}
	function e:type(t) self.kind = t end
	function e:register() events[self.name] = self end
	return e
end
json = json or {}
json.decode = function(s)
	if s == '{"on":false}' then return {on = false} end
	if s == '{"on":true}' then return {on = true} end
	error("bad json")
end
dofile("data/scripts/chaos/kitewalk.lua")
ok(events.ChaosKiteWalkLogin and events.ChaosKiteWalkLogin.kind == "login", "login event")
ok(events.ChaosKiteWalkOpcode and events.ChaosKiteWalkOpcode.kind == "extendedopcode", "opcode event")

local store, writes, registered = {}, 0, {}
local pl = {}
function pl:registerEvent(n) registered[#registered + 1] = n end
function pl:getStorageValue(k) return store[k] or -1 end
function pl:setStorageValue(k, v) store[k] = v; writes = writes + 1 end
ok(events.ChaosKiteWalkLogin.onLogin(pl), "login returns true")
eq(registered[1], "ChaosKiteWalkOpcode", "login registers the opcode event")

local on = events.ChaosKiteWalkOpcode.onExtendedOpcode
on(pl, 186, '{"on":true}')
eq(writes, 0, "on at login with nothing stored: no write")
on(pl, 186, '{"on":false}')
eq(store[7101820], 1, "off stored")
on(pl, 186, '{"on":false}')
eq(writes, 1, "off again: no second write")
on(pl, 188, '{"on":true}')
eq(store[7101820], 1, "another opcode is ignored")
on(pl, 186, 'not json')
eq(store[7101820], 1, "junk is ignored")
on(pl, 186, '{"on":true}')
eq(store[7101820], 0, "back on")

print(string.format("kitewalk_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
