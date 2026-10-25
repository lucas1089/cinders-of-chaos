-- Run from the server/ folder: luajit tests/pack29_scan_test.lua (and lua5.3; CI runs both)
-- data/scripts/chaos/pack29_vfx.lua, the players' aura scan (O199): the engine constants are looked up once, the
-- rows still pick the same auras as the per-tick _G lookups did.
local failures = 0
local function eq(a, b, what)
	if a ~= b then failures = failures + 1; print("FAIL " .. what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end
end

CONDITION_PARALYZE, CONDITION_DRUNK, CONDITION_REGENERATION, CONDITIONID_COMBAT = 1, 2, 3, 9
local events, players = {}, {}
local function ctor() return function(name) local e = {name = name}; function e:register() events[name] = self end
	function e:interval() end return e end end
GlobalEvent, CreatureEvent = ctor(), ctor()
Game = {getPlayers = function() return players end}
dofile("data/lib/chaos_pack29_vfx.lua")
local V = ChaosPack29Vfx
local shown = {}
V.live = function() return true end
V.show = function(player, state) shown[#shown + 1] = player.name .. ":" .. state end
dofile("data/scripts/chaos/pack29_vfx.lua")

local function player(name, conds)
	return {name = name,
		hasCondition = function(_, t) return conds[t] and true or false end,
		getCondition = function(_, t, id) return conds[t] and conds[t] == id and {} or nil end}
end
players[1] = player("a", {[CONDITION_PARALYZE] = true})
players[2] = player("b", {[CONDITION_DRUNK] = true, [CONDITION_REGENERATION] = CONDITIONID_COMBAT})
players[3] = player("c", {[CONDITION_REGENERATION] = 77}) -- the food regeneration: no aura
players[4] = player("d", {})
for pass = 1, 3 do -- the later passes answer from the resolved rows
	shown = {}
	events.ChaosPack29VfxScan.onThink(1000)
	eq(table.concat(shown, ","), "a:slowed,b:confused,b:regeneration", "scan pass " .. pass)
end

-- a not live pack scans nothing
V.live = function() return false end
shown = {}
events.ChaosPack29VfxScan.onThink(1000)
eq(#shown, 0, "not live: nothing")
V.live = function() return true end

-- a changed V.scan is resolved again; an unknown constant name drops its row, an unknown condition id never matches
V.scan = {{"CONDITION_DRUNK", nil, "confused"}, {"CONDITION_NOPE", nil, "x"}, {"CONDITION_REGENERATION", "CONDITIONID_NOPE", "y"}}
shown = {}
events.ChaosPack29VfxScan.onThink(1000)
eq(table.concat(shown, ","), "b:confused", "new rows")

if failures > 0 then print(failures .. " failure(s)"); os.exit(1) end
print("pack29_scan_test: OK")
