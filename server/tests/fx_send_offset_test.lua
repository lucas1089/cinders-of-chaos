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

-- the owner's report (2026-10-22): Banner Call's holy_spiral 405, a 5x5 judgement pillar kept as 4x4, two tiles off
local x, y = M.shift(100, 200, 405, T)
eq(x, 102, "405 sent two tiles right")
eq(y, 202, "405 sent two tiles down")
-- a 3x3 art one tile, a 2x2 art (stock size) and an unknown id not at all, no table: nothing
x, y = M.shift(100, 200, 15, T)
eq(x * 1000 + y, 101 * 1000 + 201, "15 (3x3) one tile")
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
for name, e in pairs(ChaosVfx or {}) do
  check(T[e.id] == nil, "ChaosVfx." .. name .. " (" .. e.id .. ") not shifted twice")
end

if fails > 0 then
  print(fails .. " of " .. count .. " checks failed")
  os.exit(1)
end
print("fx_send_offset_test: " .. count .. " checks passed")
