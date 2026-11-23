-- Run from the server/ folder: luajit tests/fx_send_offset_test.lua (send offsets of the effects redrawn in place,
-- pair 36; CI runs it with LuaJIT and Lua 5.3)
dofile("data/scripts/chaos/fx_send_offset_core.lua")
local M = ChaosFxSendOffsetCore
local T = M.load()

local fails, count = 0, 0
local function check(cond, name)
  count = count + 1
  if not cond then
    fails = fails + 1
    print("FAIL: " .. name)
  end
end
local function eq(a, b, name)
  check(a == b, name .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

check(type(T) == "table", "chaos_fx_send_offsets.lua loads")

-- the owner's report (2026-10-22): Banner Call's holy_spiral 405, a 5x5 judgement pillar kept as 4x4, up and left of
-- its tile. Its pivot was pulled 47 px, so one tile brings it to 15 px of its place (two tiles to 17 px past it)
local x, y = M.shift(100, 200, 405, T)
eq(x, 101, "405 sent one tile right")
eq(y, 201, "405 sent one tile down")
-- the owner's report (2026-10-23): the blue teleport 11 (streaks into a ring, the login effect) and the yellow holy
-- 201 and 262 sat a tile down and right. Their pivots were pulled only 3-11 px: the art is already where it belongs
for _, id in ipairs({3, 7, 11, 167, 201, 226, 262, 309, 416}) do
  x, y = M.shift(100, 200, id, T)
  eq(x * 1000 + y, 100 * 1000 + 200, "effect " .. id .. " is sent at its own tile")
end
-- a 3x3 art whose pivot was pulled a whole tile one tile, a 2x2 art (stock size) and an unknown id not at all, no
-- table: nothing
x, y = M.shift(100, 200, 15, T)
eq(x * 1000 + y, 101 * 1000 + 201, "15 (3x3, healing) one tile")
x, y = M.shift(100, 200, 40, T)
eq(x * 1000 + y, 100 * 1000 + 200, "40 (2x2) unchanged")
x, y = M.shift(100, 200, 999999, T)
eq(x * 1000 + y, 100 * 1000 + 200, "unknown id unchanged")
x, y = M.shift(100, 200, 405, nil)
eq(x * 1000 + y, 100 * 1000 + 200, "no table: unchanged")

-- every entry: a whole offset of 1..3 tiles on some axis, never negative
local n = 0
for id, o in pairs(T) do
  n = n + 1
  check(type(id) == "number" and id >= 1 and id <= 65535, "id " .. tostring(id))
  check(o[1] >= 0 and o[2] >= 0 and o[1] <= 3 and o[2] <= 3 and o[1] + o[2] > 0, "offset of " .. tostring(id))
end
check(n > 0, "entries")

-- no id that Vfx already sends at its own offset tile: it would be shifted twice
ChaosVfx, ChaosVfxMissile = nil, nil
for _, f in ipairs({"chaos_vfx", "chaos_vfx_art", "chaos_pack_fx_ids", "chaos_pack27_fx_ids", "chaos_pack29_fx_ids",
    "chaos_pack29_vfx_ids", "chaos_pack30_fx_ids", "chaos_pack36_fx_ids", "chaos_class_fx_ids", "chaos_big_fx_ids",
    "chaos_status_fx_ids"}) do
  local ok, err = pcall(dofile, "data/lib/" .. f .. ".lua")
  check(ok, f .. " loads: " .. tostring(err))
end
-- (an O736 row names a ChaosVfx entry that sends at its own tile, dx = dy = 0: shifted once, by the table)
local gatedAll = {}
for id in pairs(ChaosFxSendOffsetFrom or {}) do gatedAll[id] = true end
M.pair = 999
local Tall = M.load(true)
for name, e in pairs(ChaosVfx or {}) do
  check(Tall[e.id] == nil or (e.dx == 0 and e.dy == 0), "ChaosVfx." .. name .. " (" .. e.id .. ") not shifted twice")
end

-- O736 (pair_fixes/fx_send_offsets_extra.csv): pack effects whose art stands a tile up and left in a canvas too tight
-- to move it are sent one tile right and down; 778 only from client pair 82 (its O734 form)
for _, id in ipairs({700, 3965}) do
  x, y = M.shift(100, 200, id, Tall)
  eq(x * 1000 + y, 101 * 1000 + 201, "O736 effect " .. id .. " one tile right and down")
end
check(gatedAll[778] == true and ChaosFxSendOffsetFrom[778] == 82, "778 waits for pair 82")
x, y = M.shift(100, 200, 778, Tall)
eq(x * 1000 + y, 101 * 1000 + 201, "778 at pair 82 or newer: one tile right and down")
M.pair = 81
local T81 = M.load(true)
x, y = M.shift(100, 200, 778, T81)
eq(x * 1000 + y, 100 * 1000 + 200, "778 below pair 82: its own tile")
x, y = M.shift(100, 200, 700, T81)
eq(x * 1000 + y, 101 * 1000 + 201, "700 has no gate")
M.pair = nil
local Tnone = M.load(true)
check(Tnone[778] == nil and Tnone[405] ~= nil, "no pair recorded: the gated rows wait, the others stay")
-- the ids O736 measured and left: no whole tile brings them under 16 px (or it would move the pivot of an in-place
-- effect off its tile, or the foot of a pillar off its tile)
for _, id in ipairs({3, 11, 19, 20, 22, 23, 24, 25, 32, 33, 374, 416, 481, 537, 538, 539, 540}) do
  check(Tall[id] == nil, "O736: effect " .. id .. " is sent at its own tile")
end
eq(Tall[405][1] * 10 + Tall[405][2], 11, "405 keeps one tile (two would put its pivot 17 px past)")
-- the gate, pure
eq(M.parsePair("x = 1\nchaosClientPair = 82 -- shipped\ny = 2\n"), 82, "the pair of a config text")
eq(M.parsePair("-- chaosClientPair = 82\n"), nil, "a commented line is no pair")
local g = M.gate({[1] = {1, 1}, [2] = {0, 1}}, {[1] = 82}, 81)
check(g[1] == nil and g[2] ~= nil, "gate below the pair")
g = M.gate({[1] = {1, 1}}, {[1] = 82}, 82)
check(g[1] ~= nil, "gate at the pair")

if fails > 0 then
  print(fails .. " of " .. count .. " checks failed")
  os.exit(1)
end
print("fx_send_offset_test: " .. count .. " checks passed")
