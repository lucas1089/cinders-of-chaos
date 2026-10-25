-- Run from the server/ folder: luajit tests/opcode_dispatch_test.lua (and lua5.3; CI runs both)
-- The extended opcode dispatch of chaos_constants.lua (server/README.md "Stress test", "Extended opcode dispatch"):
-- an extended opcode runs only the handlers of its opcode (plus the ones without an opcode guard), in the order they
-- were defined, for the players that registered them; a request over Chaos.opcodeRequestMax is dropped before any
-- handler sees it; one failing handler does not stop the next. The engine is mocked the way TFS binds revscripts
-- (CreatureEvent class table, the compat __newindex, register() only for a scripted event, Player:registerEvent by
-- name, every registered extendedopcode event called for every opcode). The stock way (no dispatch) calls every
-- handler of the player for every opcode, so the "not called" checks fail without it.
-- Also: every handler under data/scripts whose body uses OPCODE starts with its guard, since the dispatch files a
-- handler under the opcode of its OPCODE upvalue.
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

-- ---------------------------------------------------------------- engine mock
local engineEvents = {} -- name -> event object registered with the engine
local metatables = {}
function rawgetmetatable(name)
	return metatables[name]
end
CreatureEvent = {}
local instanceMT = {__index = CreatureEvent}
metatables.CreatureEvent = instanceMT
setmetatable(CreatureEvent, {__call = function(self, name)
	return setmetatable({_name = name}, instanceMT)
end})
function CreatureEvent.type(self, t) rawset(self, "_type", t) end
local function callback(self, fn) rawset(self, "_fn", fn) return true end
CreatureEvent.onExtendedOpcode = callback
CreatureEvent.onLogout = callback
CreatureEvent.onLogin = callback
function CreatureEvent.register(self)
	if not rawget(self, "_fn") then
		return false
	end
	engineEvents[self._name] = self
	return true
end
-- data/lib/compat/compat.lua
instanceMT.__newindex = function(self, key, value)
	if key == "onExtendedOpcode" then
		self:type("extendedopcode")
		self:onExtendedOpcode(value)
		return
	elseif key == "onLogout" then
		self:type("logout")
		self:onLogout(value)
		return
	end
	rawset(self, key, value)
end

Creature = {}
function Creature.registerEvent(self, name)
	if not engineEvents[name] then
		return false
	end
	for _, n in ipairs(self.events) do
		if n == name then
			return false
		end
	end
	self.events[#self.events + 1] = name
	return true
end
function Creature.unregisterEvent(self, name)
	for i, n in ipairs(self.events) do
		if n == name then
			table.remove(self.events, i)
			return true
		end
	end
	return false
end
Player = setmetatable({}, {__index = Creature})
local playerMT = {__index = Player}
local function newPlayer(id)
	return setmetatable({id = id, events = {}}, playerMT)
end
function Player.getId(self) return self.id end
function Player.getName(self) return "Tester" .. self.id end

-- Game::parsePlayerExtendedOpcode: every registered extendedopcode event, in registration order
local function sendOpcode(player, opcode, buffer)
	for _, name in ipairs(player.events) do
		local ev = engineEvents[name]
		if ev and ev._type == "extendedopcode" then
			local done, err = pcall(ev._fn, player, opcode, buffer) -- the engine reports an error and goes on
			if not done then
				print("Lua Script Error: " .. tostring(err))
			end
		end
	end
end
local function logout(player)
	for _, name in ipairs(player.events) do
		local ev = engineEvents[name]
		if ev and ev._type == "logout" then
			ev._fn(player)
		end
	end
end

local printed = {}
local realPrint = print
print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	printed[#printed + 1] = table.concat(parts, " ")
end

-- a base event registered with the engine before the Chaos scripts load stays with the engine
local calls, seen = {}, {}
local base = CreatureEvent("BaseOpcode")
function base.onExtendedOpcode(player, opcode, buffer)
	calls.Base = (calls.Base or 0) + 1
end
base:register()

dofile("data/scripts/chaos/chaos_constants.lua")

-- handlers as the modules write them
local function module(name, opcode)
	local OPCODE = opcode
	local ev = CreatureEvent(name)
	function ev.onExtendedOpcode(player, op, buffer)
		calls[name] = (calls[name] or 0) + 1 -- counts every call, also the ones the guard ends
		if op ~= OPCODE then
			return
		end
		seen[#seen + 1] = name
		if buffer == "boom" and name == "Bank" then
			error("boom")
		end
	end
	ev:type("extendedopcode")
	ev:register()
end
module("Bank", 60)
module("Dungeons", 109)
module("Season", 246)
-- no OPCODE upvalue: handles two opcodes by their global names (as notifications.lua)
local notify = CreatureEvent("Notify")
function notify.onExtendedOpcode(player, opcode, buffer)
	calls.Notify = (calls.Notify or 0) + 1
	if opcode == 151 or opcode == 152 then
		seen[#seen + 1] = "Notify"
	end
end
notify:register()
module("SeasonJourney", 246)

local p = newPlayer(1)
for _, n in ipairs({"BaseOpcode", "Bank", "Dungeons", "Season", "Notify", "SeasonJourney"}) do
	ok(p:registerEvent(n) == true, "registerEvent " .. n)
end

local function reset()
	calls, seen = {}, {}
end

reset()
sendOpcode(p, 60, '{"action":"openBank"}')
ok(seen[1] == "Bank" and #seen == 1, "opcode 60 reaches the bank handler")
ok(calls.Bank == 1 and calls.Dungeons == nil and calls.Season == nil and calls.SeasonJourney == nil,
	"handlers of other opcodes are not called at all")
ok(calls.Notify == 1, "a handler without an opcode guard still sees every opcode")
ok(calls.Base == 1, "the base server's own event stays with the engine")

reset()
sendOpcode(p, 246, "{}")
ok(seen[1] == "Season" and seen[2] == "SeasonJourney" and #seen == 2, "a shared opcode runs its handlers in order")
reset()
sendOpcode(p, 151, "accept_invite|1")
ok(seen[1] == "Notify" and #seen == 1 and calls.Bank == nil, "opcode 151 only for the handler without a guard")

-- a player who did not register a handler does not get it
local q = newPlayer(2)
q:registerEvent("Dungeons")
reset()
sendOpcode(q, 60, "{}")
ok(calls.Bank == nil, "not registered: not called")
sendOpcode(q, 109, "{}")
ok(seen[1] == "Dungeons", "registered: called")
q:unregisterEvent("Dungeons")
reset()
sendOpcode(q, 109, "{}")
ok(calls.Dungeons == nil, "unregistered: not called")

-- size cap: dropped before any handler, one console line a minute per player
reset()
printed = {}
sendOpcode(p, 60, string.rep("x", Chaos.opcodeRequestMax + 1))
sendOpcode(p, 60, string.rep("x", Chaos.opcodeRequestMax + 1))
ok(calls.Bank == nil and calls.Notify == nil, "an oversize request reaches no handler")
local warnings = 0
for _, line in ipairs(printed) do
	if line:find("over " .. Chaos.opcodeRequestMax, 1, true) then
		warnings = warnings + 1
	end
end
ok(warnings == 1, "one warning for the player, not one per request: " .. warnings)
reset()
sendOpcode(p, 60, string.rep("x", Chaos.opcodeRequestMax))
ok(calls.Bank == 1, "a request of exactly the limit goes through")
ok(Chaos.opcodeRequestMax >= 8192, "the cap is above the engine's 8192-byte string limit")

-- request budget (O220): a bucket per player, dropped over it with one console line a minute, refilled over time,
-- separate per player, cleared at logout
do
	local D = Chaos.opcodeDispatch
	local burst, rate = Chaos.opcodeBudget.burst, Chaos.opcodeBudget.perSecond
	ok(burst >= 100 and rate >= 50, "the budget is looser than the engine's 50 packets a second and a login burst")
	local now = 5000000
	local allowed = 0
	for _ = 1, burst + 40 do
		if D.take(900, now) then allowed = allowed + 1 end
	end
	ok(allowed == burst, "a burst of " .. burst .. " passes, the rest of the same instant does not: " .. allowed)
	ok(D.take(901, now), "another player has a budget of their own")
	ok(not D.take(900, now + 5), "5 ms later still empty")
	ok(D.take(900, now + 1000), "a second later " .. rate .. " more are allowed")
	local again = 1
	while D.take(900, now + 1000) do again = again + 1 end
	ok(again == rate, "exactly the refill: " .. again)
	ok(not D.take(900, now - 10000), "a clock that goes back gives nothing")
	for _ = 1, 5 do D.take(900, now + 100000) end
	local full = 0
	while D.take(900, now + 100000) do full = full + 1 end
	ok(full <= burst, "the bucket never holds more than the burst: " .. full)
	D.forget(900)
	ok(D.bucket[900] == nil and D.warnedRate[900] == nil, "logout clears the bucket")

	-- through dispatch: a flood reaches the handlers only up to the budget, with one warning
	reset()
	printed = {}
	D.bucket[p:getId()] = nil
	for _ = 1, burst + 100 do sendOpcode(p, 60, "{}") end
	ok(calls.Bank and calls.Bank <= burst and calls.Bank >= burst - 5, "a flood reaches Bank " .. tostring(calls.Bank) .. " times")
	local rateWarnings = 0
	for _, line in ipairs(printed) do
		if line:find("requests a second", 1, true) then rateWarnings = rateWarnings + 1 end
	end
	ok(rateWarnings == 1, "one rate warning, not one per request: " .. rateWarnings)
	D.bucket[p:getId()] = nil
end

-- JSON nesting (O220): Chaos.jsonDepthOk and the json.decode guard
do
	local lim = Chaos.jsonMaxDepth
	ok(lim >= 8 and lim <= 128, "a nesting limit between real messages (2-6) and a stack overflow")
	ok(Chaos.jsonDepthOk("{}") and Chaos.jsonDepthOk("[]") and Chaos.jsonDepthOk(""), "empty containers pass")
	ok(Chaos.jsonDepthOk('{"a":[1,{"b":[2,3]}],"c":"x"}'), "a normal message passes")
	ok(Chaos.jsonDepthOk(string.rep("[", lim) .. string.rep("]", lim)), "exactly the limit passes")
	ok(not Chaos.jsonDepthOk(string.rep("[", lim + 1)), "one over fails")
	ok(not Chaos.jsonDepthOk(string.rep("{\"a\":", lim + 1)), "objects count too")
	ok(not Chaos.jsonDepthOk(string.rep("[", Chaos.opcodeRequestMax)), "a request of nothing but [ fails")
	ok(Chaos.jsonDepthOk(string.rep("[]", 5000)), "many siblings are depth 1")
	ok(Chaos.jsonDepthOk('"' .. string.rep("[", 500) .. '"'), "brackets inside a string do not count")
	ok(Chaos.jsonDepthOk('"\\\\"' .. "[]"), "an escaped backslash ends the string at the next quote")
	ok(Chaos.jsonDepthOk('["a\\\\"]'), "a string ending in an escaped backslash")
	ok(Chaos.jsonDepthOk('["a\\\\"' .. string.rep("[", lim + 1)) == false, "an escaped backslash does not hide what follows")
	ok(Chaos.jsonDepthOk('["a\\\\"' .. string.rep("[", lim - 2) .. "]") == true, "a string and a normal depth after it")
	ok(Chaos.jsonDepthOk('["a\\\\" ]]]]]]]]') == true, "more closers than openers do not go negative")
	ok(Chaos.jsonDepthOk('["a') == true, "an unterminated string is left to the decoder")
	ok(Chaos.jsonDepthOk(nil) == true and Chaos.jsonDepthOk(12) == true, "non-strings are left to the decoder")
	-- the wrapper
	local calls_ = 0
	json = {decode = function(text) calls_ = calls_ + 1 return text end}
	Chaos.jsonGuarded = nil
	ok(Chaos.guardJson() == true, "wraps json.decode")
	ok(Chaos.guardJson() == false, "and only once")
	ok(json.decode("[1]") == "[1]" and calls_ == 1, "a shallow text reaches the real decoder")
	local okc, err = pcall(json.decode, string.rep("[", lim + 1))
	ok(not okc and tostring(err):find("nested too deeply", 1, true) and calls_ == 1, "a deep text is refused before it")
	ok(Chaos.decode(string.rep("[", lim + 1)) == nil, "Chaos.decode answers nil for it")
	json = nil
	Chaos.jsonGuarded = nil
	ok(Chaos.guardJson() == false, "no json library: nothing to wrap")
end

-- an error in one handler: reported, the next handler still runs
reset()
printed = {}
sendOpcode(p, 60, "boom")
ok(calls.Notify == 1, "after a failing handler the next one still runs")
ok(printed[1] and printed[1]:find("Bank", 1, true) and printed[1]:find("boom", 1, true), "the error is reported")

-- no record of the player's registrations (a reload of the scripts while online): every handler
local r = newPlayer(3)
r:registerEvent("Bank")
Chaos.opcodeDispatch.players[3] = nil
reset()
sendOpcode(r, 109, "{}")
ok(seen[1] == "Dungeons", "no record: every handler of the opcode")

-- logout forgets the player
logout(p)
ok(Chaos.opcodeDispatch.players[1] == nil, "logout forgets the player's registrations")

print = realPrint

-- ---------------------------------------------------------------- the sources: an OPCODE upvalue means its guard
local function listLua(dir)
	local h = io.popen('find "' .. dir .. '" -name "*.lua" 2>/dev/null')
	local out = {}
	for line in h:lines() do
		out[#out + 1] = line
	end
	h:close()
	return out
end
local handlers, guarded = 0, 0
for _, path in ipairs(listLua("data/scripts")) do
	local f = io.open(path, "r")
	local text = f:read("*a")
	f:close()
	for header, params, body in text:gmatch("\n(function [%w_%.:]+%.onExtendedOpcode%(([^)]*)%)[^\n]*)\n(.-)\nend") do
		handlers = handlers + 1
		local codeParam = params:match("^%s*[%w_]+%s*,%s*([%w_]+)")
		if body:find("%f[%w_]OPCODE%f[^%w_]") then
			local first = body:match("^%s*([^\n]*)")
			-- "if code ~= OPCODE then" or "if code ~= OPCODE or <more> then": any other opcode returns at once
			local lead = codeParam and ("if " .. codeParam .. " ~= OPCODE ")
			ok(lead and first:sub(1, #lead) == lead and (first == lead .. "then" or first:sub(#lead + 1, #lead + 3) == "or "),
				path .. ": " .. header
				.. " uses OPCODE but does not start with its guard (the dispatch files it under that opcode)")
			guarded = guarded + 1
		end
	end
end
ok(handlers >= 70 and guarded >= 70, "the sources were read: " .. handlers .. " handlers, " .. guarded .. " guarded")

if fails > 0 then
	print(string.format("opcode_dispatch_test: %d of %d checks failed", fails, checks))
	os.exit(1)
end
print(string.format("opcode_dispatch_test: all %d checks passed", checks))
