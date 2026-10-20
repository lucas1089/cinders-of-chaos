-- Run from the server/ folder: luajit tests/party_xp_test.lua (and lua5.3; CI runs both)
-- Party shared experience (owner report 2026-10-17: "Exp share nao parece estar funcionando"): the engine's rule that
-- every member must pass level range, distance and activity at once (party_xp_core.lua), the diagnosis, the notices
-- (one per party and reason per interval) and party_xp.lua on a mocked engine (the experience is never changed).
local count, failures = 0, 0
local function check(cond, label)
	count = count + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

dofile("data/scripts/chaos/party_xp_core.lua")
local K = ChaosPartyXpCore

-- ---------------------------------------------------------------- the rules
eq(K.minLevel(300), 200, "two thirds of 300") eq(K.minLevel(100), 67, "ceil(66.67)") eq(K.minLevel(1000), 667, "ceil(666.67)")
local function m(name, level, x, fighting)
	return {name = name, level = level, pos = {x = x or 100, y = 100, z = 7}, fighting = fighting ~= false}
end
check(K.inRange({x = 100, y = 100, z = 7}, {x = 130, y = 70, z = 8}), "30 tiles and one floor: in range")
check(not K.inRange({x = 100, y = 100, z = 7}, {x = 131, y = 100, z = 7}), "31 tiles: out")
check(not K.inRange({x = 100, y = 100, z = 7}, {x = 100, y = 100, z = 9}), "two floors: out")
check(not K.inRange(nil, {x = 1, y = 1, z = 1}), "no position: out")

local function diag(over)
	local f = {active = true, enabled = false, leader = m("Lead", 400), members = {m("Ana", 400), m("Bob", 380)}}
	for k, v in pairs(over or {}) do f[k] = v end
	return K.diagnose(f)
end
local d = diag({enabled = true})
check(d.ok and d.reason == "working" and #d.problems == 0, "a working share is not diagnosed")
d = diag({active = false})
eq(d.reason, "off", "the leader never switched it on")
d = diag({members = {}})
eq(d.reason, "alone", "no other member: nothing to share")
eq(K.diagnose(nil).reason, "alone", "no facts")
d = diag({members = {m("Ana", 400), m("Bob", 100)}})
eq(d.reason, "problems", "one member too low a level") eq(#d.problems, 1, "only that member") eq(d.problems[1].name, "Bob", "Bob") eq(d.problems[1].kind, "level", "level") eq(d.problems[1].need, 267, "needs 267")
d = diag({members = {m("Ana", 400, 140), m("Bob", 380)}})
eq(d.problems[1].kind, "range", "Ana is 40 tiles away") eq(#d.problems, 1, "one problem")
d = diag({members = {m("Ana", 400, 100, false), m("Bob", 380)}})
eq(d.problems[1].kind, "idle", "Ana has not fought: a buff-only support") eq(d.problems[1].name, "Ana", "Ana named")
d = diag({leader = m("Lead", 400, 100, false)})
eq(d.problems[1].name, "Lead", "an idle leader is named too") eq(d.problems[1].kind, "idle", "idle")
d = diag({members = {m("Ana", 100, 200, false), m("Bob", 380)}})
eq(#d.problems, 3, "level, range and idle at once: three problems")
-- levels are measured against the highest of the party, the leader included
d = diag({leader = m("Lead", 600), members = {m("Ana", 399), m("Bob", 400)}})
eq(#d.problems, 1, "399 < ceil(2/3 x 600) = 400") eq(d.problems[1].name, "Ana", "Ana")

-- ---------------------------------------------------------------- the lines
local lines = K.lines(diag({active = false}))
check(lines and #lines == 1 and lines[1]:find("turn it on", 1, true), "the off hint")
check(K.lines(diag({enabled = true})) == nil, "working: no line") check(K.lines(diag({members = {}})) == nil, "alone: no line")
lines = K.lines(diag({members = {m("Ana", 400, 140), m("Bob", 100)}}))
check(lines and #lines == 2 and lines[2]:find("Ana is too far", 1, true) and lines[2]:find("Bob is below level 267", 1, true), "problems named: " .. tostring(lines and lines[2]))

-- ---------------------------------------------------------------- notices are rare
local state = {}
check(K.due(state, 1, "problems", 1000), "first notice") check(not K.due(state, 1, "problems", 1100), "again in 100 s: no")
check(K.due(state, 1, "problems", 1121), "after 121 s: yes") check(K.due(state, 2, "problems", 1121), "another party: yes")
check(K.due(state, 1, "off", 1130), "another reason: yes") check(not K.due(state, 1, "off", 1130 + 1799), "the off hint is rarer")
check(K.due(state, 1, "off", 1130 + 1801), "but comes back")
K.sweep(state, 100000, 3600)
check(next(state) == nil, "old entries are swept")

-- ---------------------------------------------------------------- party_xp.lua on a mocked engine
do
	MESSAGE_STATUS_DEFAULT, MESSAGE_INFO_DESCR = 20, 22
	CONDITION_INFIGHT, CONDITIONID_DEFAULT = 8, 0
	dofile("data/scripts/chaos/chaos_constants.lua")
	Chaos.t = function(_, key, ...) if select("#", ...) > 0 then return string.format(key, ...) end return key end
	local callback
	EventCallback = setmetatable({}, {__newindex = rawset})
	EventCallback.register = function(self, idx) callback = self.onGainExperience end
	local nextId = 0
	local function player(name, level, x, fighting)
		nextId = nextId + 1
		local p = {id = nextId, name = name, level = level, x = x or 100, fighting = fighting ~= false, msgs = {}}
		function p:getId() return self.id end
		function p:getName() return self.name end
		function p:getLevel() return self.level end
		function p:getPosition() return {x = self.x, y = 100, z = 7} end
		function p:getCondition() return self.fighting and {} or nil end
		function p:getParty() return self.party end
		function p:sendTextMessage(_, t) self.msgs[#self.msgs + 1] = t end
		return p
	end
	local lead, ana, bob = player("Lead", 400), player("Ana", 400), player("Bob", 390)
	local party = {active = true, enabled = false}
	function party:getLeader() return lead end
	function party:getMembers() return {ana, bob} end
	function party:isSharedExperienceActive() return self.active end
	function party:isSharedExperienceEnabled() return self.enabled end
	lead.party, ana.party, bob.party = party, party, party
	dofile("data/scripts/chaos/party_xp.lua")
	check(callback ~= nil, "the callback is registered")
	local monster = {isMonster = function() return true end}
	local playerSource = {isMonster = function() return false end}
	local realTime = os.time
	local now = 5000000
	os.time = function() return now end

	eq(callback(ana, monster, 1234, 1000), 1234, "the experience is never changed")
	eq(#lead.msgs, 0, "everyone fights and is near: nothing to say (the engine should have it working)")
	ana.fighting = false
	eq(callback(bob, monster, 500, 400), 500, "unchanged")
	eq(#lead.msgs, 2, "Ana idle: the leader is told (two lines)")
	check(lead.msgs[2]:find("Ana has not attacked a monster", 1, true) ~= nil, "naming Ana: " .. tostring(lead.msgs[2]))
	eq(#ana.msgs + #bob.msgs, 0, "only the leader is told")
	callback(bob, monster, 500, 400)
	eq(#lead.msgs, 2, "the second kill 0 s later: no new notice")
	now = now + 121
	callback(bob, monster, 500, 400)
	eq(#lead.msgs, 4, "after two minutes: again")
	-- a working share, a player source and zero experience say nothing
	party.enabled = true
	now = now + 500
	callback(bob, monster, 500, 400)
	callback(bob, playerSource, 500, 400)
	eq(#lead.msgs, 4, "working: silent")
	party.enabled = false
	callback(bob, monster, 0, 0)
	callback(bob, playerSource, 500, 400)
	eq(#lead.msgs, 4, "zero experience and player sources: silent")
	-- sharing never switched on: a rare hint
	party.active = false
	now = now + 500
	callback(bob, monster, 500, 400)
	eq(#lead.msgs, 5, "off: one hint") check(lead.msgs[5]:find("turn it on", 1, true) ~= nil, "the hint")
	now = now + 500
	callback(bob, monster, 500, 400)
	eq(#lead.msgs, 5, "off: not again for half an hour")
	-- no party: nothing, no error
	bob.party = nil
	eq(callback(bob, monster, 500, 400), 500, "no party: unchanged")
	-- an engine error never breaks the experience
	party.active = true
	function party:getMembers() error("boom") end
	bob.party = party
	eq(callback(bob, monster, 700, 600), 700, "an error in the diagnosis does not change the experience")
	os.time = realTime
end

if failures > 0 then
	error(failures .. " of " .. count .. " checks failed")
end
print("party_xp_test: " .. count .. " checks OK")
