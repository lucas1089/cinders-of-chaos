-- Run from the server/ folder: luajit tests/fx_send_offset_engine_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- An engine with src-patch 0070 (Game.setFxSendOffsets) takes the send offsets table and shifts every effect packet
-- itself; the Lua guard of Position:sendMagicEffect then sends at the target tile, so nothing is shifted twice.
local fails, count = 0, 0
local function check(cond, what)
	count = count + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

-- the pure part first: no engine table, an engine without the patch, a broken one
dofile("data/scripts/chaos/fx_send_offset_core.lua")
local M = ChaosFxSendOffsetCore
local T = M.load()
check(M.applyEngine(nil) == false and M.engine == false, "no Game: the Lua guard shifts")
check(M.applyEngine({}) == false and M.engine == false, "an engine without 0070: the Lua guard shifts")
check(M.luaShifts(405, T) == true, "without 0070 the Lua guard shifts 405")
check(M.luaShifts(40, T) == false, "40 (2x2) is never shifted")
check(M.applyEngine({setFxSendOffsets = function() error("boom") end}) == false and M.engine == false,
	"an engine call that fails: the Lua guard shifts")
check(M.applyEngine({setFxSendOffsets = function() return 0 end}) == true and M.engine == true,
	"an engine that took the table: M.engine")
check(M.luaShifts(405, T) == false, "with 0070 the Lua guard does not shift 405")
M.engine = false

-- the engine mock: Game.setFxSendOffsets keeps the table as the C++ side does (ids 1..65535, offsets not 0, 0)
local engineTable, handed = nil, 0
Game = {setFxSendOffsets = function(t)
	handed = handed + 1
	engineTable = {}
	local n = 0
	for id, o in pairs(t or {}) do
		if type(id) == "number" and type(o) == "table" and (o[1] ~= 0 or o[2] ~= 0) then
			engineTable[id] = {o[1], o[2]}
			n = n + 1
		end
	end
	return n
end}
local at = {}
Position = setmetatable({sendMagicEffect = function(self, effect)
	at[#at + 1] = {x = self.x, y = self.y, z = self.z, effect = effect}
	return true
end}, {__call = function(_, x, y, z) return {x = x, y = y, z = z} end})
local realPrint = print
print = function() end -- luacheck: ignore
dofile("data/scripts/chaos/chaos_constants.lua")
print = realPrint -- luacheck: ignore

check(handed == 1, "the table is handed to the engine at load")
check(M.engine == true, "the engine shifts")
local n = 0
for id, o in pairs(T) do
	n = n + 1
	local e = engineTable and engineTable[id]
	check(e ~= nil and e[1] == o[1] and e[2] == o[2], "engine has " .. tostring(id))
end
check(n > 0 and engineTable[405][1] == 2 and engineTable[405][2] == 2, "405 is 2, 2 in the engine")
-- the guard sends at the target tile: the engine centres it (no second shift)
check(Position.sendMagicEffect({x = 100, y = 200, z = 7}, 405) == true and at[1].x == 100 and at[1].y == 200
	and at[1].z == 7, "405 sent at the target tile by Lua, the engine shifts it")
print = function() end -- luacheck: ignore
local refused = Position.sendMagicEffect({x = 100, y = 200, z = 7}, 0) == false
print = realPrint -- luacheck: ignore
check(refused and #at == 1, "effect 0 still refused")

-- a reload (Chaos already set) hands the table again, read anew
dofile("data/scripts/chaos/chaos_constants.lua")
check(handed == 2, "a reload hands the table again")
check(M.engine == true, "still the engine after a reload")

if fails > 0 then
	print(fails .. " of " .. count .. " checks failed")
	os.exit(1)
end
print("fx_send_offset_engine_test: " .. count .. " checks passed")
