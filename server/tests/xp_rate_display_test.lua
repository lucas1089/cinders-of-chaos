-- Run from the server/ folder: luajit tests/xp_rate_display_test.lua (CI runs it with LuaJIT and Lua 5.3)
dofile("data/scripts/chaos/xp_rate_display_core.lua")
local R = ChaosXpRateDisplay
local fails = 0
local function eq(a, b, what)
	if a ~= b then fails = fails + 1 print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
end
eq(R.percent(100, 100), 100, "no bonus is 100%")
eq(R.percent(250, 100), 250, "bonuses add up")
eq(R.percent(5, 100), 5, "a small rate")
eq(R.percent(10, 0), nil, "no base: unknown")
eq(R.percent(0, 100), nil, "no experience: unknown")
eq(R.percent(1e12, 1), R.MAX, "capped at uint16")
eq(R.baseGain(150, 100), 150, "no stamina bonus: as is")
eq(R.baseGain(150, 150), 100, "stamina x1.5 taken out of the base")
eq(R.baseGain(nil, 100), nil, "nil in, nil out")
eq(R.baseGain(0, 100), R.MIN, "never zero")
-- O774: the standing rate before a kill (the Pact's +10% showed 100%)
eq(R.product({1.1}), 1.1, "one provider")
eq(R.product({1.1, 1.5, "x", -2, 0}), 1.1 * 1.5, "bad multipliers count as 1")
eq(R.product({}), 1, "no provider")
eq(R.refreshGain(nil, nil, 1.1), 110, "the Pact alone before a kill: 110%")
eq(R.refreshGain(nil, nil, 1), 100, "nothing: 100%")
eq(R.refreshGain(287, 1, 1.1), 316, "a kill known: its rate moved by the new Pact")
eq(R.refreshGain(316, 1.1, 1), 287, "the Pact ended: back to the kill's rate without it")
eq(R.refreshGain(nil, nil, 1e9), R.MAX, "capped")

-- the engine file on a mock: the login refresh sends the Pact's 110 through Player:setBaseXpGain (engine patch 0096)
do
	local cbMeta = {}
	cbMeta.__index = cbMeta
	function cbMeta:register() end
	local events = {}
	CreatureEvent = function(name)
		local e = {}
		function e:type(t) self.t = t end
		function e:register() end
		events[name] = e
		return e
	end
	local queued = {}
	addEvent = function(fn, ms, ...) queued[#queued + 1] = {fn, {...}} end
	local sent = {}
	local player = {id = 7}
	function player:getId() return self.id end
	function player:setBaseXpGain(v) sent[#sent + 1] = v return true end
	Player = function(cid) return cid == 7 and player or nil end
	R.providers.pact = function() return 1.1 end
	-- EventCallback is a fresh object on every read in the engine
	setmetatable(_G, {__index = function(_, k) if k == "EventCallback" then return setmetatable({}, cbMeta) end end})
	dofile("data/scripts/chaos/xp_rate_display.lua")
	setmetatable(_G, nil)
	events["ChaosXpRateLogin"].onLogin(player)
	eq(#queued, 1, "login queues the refresh")
	queued[1][1]((table.unpack or unpack)(queued[1][2]))
	eq(sent[1], 110, "the Pact's 110% is sent at login")
	eq(R.refresh(player), 110, "refresh again: the same")
	eq(#sent, 1, "an unchanged rate is not resent")
	R.providers.pact = nil
	eq(R.refresh(player), 100, "the Pact ended")
	eq(sent[2], 100, "100% sent")
end

print(string.format("xp_rate_display_test: %d failures", fails))
if fails > 0 then os.exit(1) end
