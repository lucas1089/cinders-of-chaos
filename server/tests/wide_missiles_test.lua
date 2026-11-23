-- Run from the server/ folder: luajit tests/wide_missiles_test.lua (and lua5.3; CI runs both)
-- Missile ids above 255 (O737, data/lib/chaos_wide_missiles.lua, engine src-patch 0094): the pair gate (config.lua chaosClientPair >= 83
-- and the engine method), the id a script sends (as it is up to 255; above it only with the gate, else the fallback or nothing), the
-- fallback table's rule (the same as the engine's Fallbacks::set, plus 254 never a fallback), the startup apply on a mocked engine, and
-- the numbers held equal to client_pair.py, the patch's header and the Lua binding.
local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end
local function ok(v, m)
	n = n + 1
	if not v then
		error(m or "not true", 2)
	end
end
local function slurp(path)
	local f = assert(io.open(path, "r"), path)
	local text = f:read("*a")
	f:close()
	return text
end

Game = nil
local C = dofile("data/lib/chaos_wide_missiles.lua")
eq(ChaosWideMissiles, C, "the lib registers itself")
eq(C.PAIR, 83, "ids above 255 from pair 83")
eq(C.FIRST_WIDE, 256, "the first wide id")
eq(C.WEAPON_TYPE, 254, "CONST_ANI_WEAPONTYPE")
eq(next(C.FALLBACK), nil, "no missile above 255 in a pair yet: the table is empty")
eq(#C.check(), 0, "the shipped table passes its rule")

-- the numbers held equal elsewhere
ok(slurp("tools/client_pair.py"):find("\nPAIR_MISSILE_U16 = 83 ", 1, true), "client_pair.py PAIR_MISSILE_U16 is C.PAIR")
local patch = slurp("src-patches/0094-wide-missile-ids.patch")
ok(patch:find("+static constexpr uint16_t FIRST_WIDE = 256;", 1, true), "the header's FIRST_WIDE")
ok(patch:find("+static constexpr uint16_t WEAPON_TYPE = 254;", 1, true), "the header's WEAPON_TYPE")
ok(patch:find("id < FIRST_WIDE || id > 0xFFFF || fallback < 0 || fallback > 0xFF", 1, true), "the engine's row rule")
ok(patch:find('registerMethod("Game", "setMissileFallback"', 1, true), "the Lua binding is Game.setMissileFallback")
ok(slurp("data/scripts/chaos/wide_missiles.lua"):find("W.apply", 1, true), "the startup glue applies the table")

-- the gate reads config.lua
eq(C.parsePair("chaosClientPair = 83"), 83, "parse a plain line")
eq(C.parsePair("x = 1\n  chaosClientPair = 82 -- note\n"), 82, "parse a line with a note")
eq(C.parsePair("chaosClientPair = abc"), nil, "no number")
eq(C.recordedPair("/nonexistent/config.lua"), nil, "no file")

-- gate off: pair below 83, or no engine method
C.recorded = 82
Game = {setMissileFallback = function() return true end}
eq(C.on(), false, "pair 82: off")
eq(C.id(42), 42, "a one-byte id as it is")
eq(C.id(255), 255, "255 is still one byte")
eq(C.id(300), nil, "an id above 255 with no fallback: nothing")
eq(C.id(300, 7), 7, "the fallback given")
eq(C.id(300, 254), nil, "254 is never a fallback")
eq(C.id(300, 256), nil, "a fallback must be one byte")
C.FALLBACK[300] = 9
eq(C.id(300), 9, "the table's fallback")
C.FALLBACK[300] = nil
C.recorded = 83
Game = {}
eq(C.on(), false, "pair 83 without the engine patch: off")
eq(C.id(300, 7), 7, "still the fallback")

-- gate on
Game = {setMissileFallback = function() return true end}
eq(C.on(), true, "pair 83 with the engine: on")
eq(C.id(300), 300, "an id above 255 as it is")
eq(C.id(65535), 65535, "the top id")
eq(C.id(65536), nil, "above the top")
eq(C.id(-1), nil, "negative")
eq(C.id(1.5), nil, "not whole")
eq(C.id("300"), nil, "not a number")

-- the table's rule
local p = C.check({[300] = 7, [255] = 7, [400] = 254, [500] = 0, [600] = 256, [70000] = 1, [700] = 1.5})
eq(#p, 6, "six bad rows of seven")
eq(#C.check({[256] = 1, [65535] = 255}), 0, "the edges pass")

-- apply on a mocked engine
local calls = {}
Game = {setMissileFallback = function(id, fb)
	calls[#calls + 1] = id .. ">" .. fb
	return true
end}
eq(C.apply({[300] = 7, [301] = 8, [255] = 1}), 2, "two good rows set, the bad one skipped")
table.sort(calls)
eq(table.concat(calls, ","), "300>7,301>8", "the engine got the good rows")
Game = {}
eq(C.apply({[300] = 7}), 0, "no engine method: nothing")
Game = nil
eq(C.apply({[300] = 7}), 0, "no Game: nothing")

print("wide_missiles_test: " .. n .. " checks ok")
