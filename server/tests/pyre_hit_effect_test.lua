-- Run from the server/ folder: luajit tests/pyre_hit_effect_test.lua (CI runs it with luajit and lua5.3)
-- O548: ChaosPack29Vfx.withoutHitEffect, the engine hit effect (src-patch 0045, Game.setHitEffect kind 1) off around Pyre Oath's damage:
-- 0 while the damage runs, exactly what applyEngine set (or stock, -1) after, also when the damage errors, nested calls, other
-- combat types untouched, an engine without the patch runs the function as before.
local failures = 0
local function ok(c, msg)
	if not c then
		failures = failures + 1
		print("FAIL " .. msg)
	end
end
local function eq(a, b, msg)
	ok(a == b, msg .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end

COMBAT_FIREDAMAGE, COMBAT_ICEDAMAGE = 8, 9
dofile("data/lib/chaos_pack29_fx.lua")
dofile("data/lib/chaos_pack29_vfx.lua")
local V = ChaosPack29Vfx

-- no engine patch: the function runs, nothing else
Game = nil
local r1, r2 = V.withoutHitEffect(COMBAT_FIREDAMAGE, function(a, b) return a + b, "x" end, 2, 3)
ok(r1 == true and r2 == 5, "without Game.setHitEffect: runs and returns")
Game = {}
r1 = V.withoutHitEffect(COMBAT_FIREDAMAGE, function() return 1 end)
ok(r1 == true, "a Game without setHitEffect: runs")

-- a mock engine: the table of kind 1 overrides, as the C++ keeps it
local engine, calls = {}, {}
Game = {setHitEffect = function(kind, key, effect, dx, dy)
	calls[#calls + 1] = {kind, key, effect}
	if effect == nil or effect < 0 then engine[kind * 1000 + key] = nil else engine[kind * 1000 + key] = {effect, dx, dy} end
end}
local function cur(ctype) return engine[1000 + ctype] end

-- pair 29 set a blast for fire (applyEngine's record), and one for ice
engine[1000 + COMBAT_FIREDAMAGE] = {811, 0, 0}
engine[1000 + COMBAT_ICEDAMAGE] = {812, 0, 0}
V.engineHits = {[COMBAT_FIREDAMAGE] = {1, COMBAT_FIREDAMAGE, 811, 0, 0}, [COMBAT_ICEDAMAGE] = {1, COMBAT_ICEDAMAGE, 812, 0, 0}}
local seen, seenIce
local good = V.withoutHitEffect(COMBAT_FIREDAMAGE, function()
	seen, seenIce = cur(COMBAT_FIREDAMAGE), cur(COMBAT_ICEDAMAGE)
end)
ok(good == true, "a clean run is true")
eq(seen and seen[1], 0, "fire hit effect is 0 while the damage runs")
eq(seenIce and seenIce[1], 812, "ice untouched meanwhile")
eq(cur(COMBAT_FIREDAMAGE) and cur(COMBAT_FIREDAMAGE)[1], 811, "fire restored to what applyEngine set")
eq(cur(COMBAT_ICEDAMAGE)[1], 812, "ice still the same after")

-- an error: reported, restored
local e1, e2 = V.withoutHitEffect(COMBAT_FIREDAMAGE, function() error("boom") end)
ok(e1 == false and tostring(e2):find("boom"), "an error is returned, not raised")
eq(cur(COMBAT_FIREDAMAGE)[1], 811, "restored after an error")

-- nested: the inner call neither restores early nor leaves 0
local inner
V.withoutHitEffect(COMBAT_FIREDAMAGE, function()
	V.withoutHitEffect(COMBAT_FIREDAMAGE, function() end)
	inner = cur(COMBAT_FIREDAMAGE)[1]
end)
eq(inner, 0, "still 0 after an inner call")
eq(cur(COMBAT_FIREDAMAGE)[1], 811, "restored once at the end")
V.withoutHitEffect(COMBAT_FIREDAMAGE, function() pcall(V.withoutHitEffect, COMBAT_FIREDAMAGE, function() error("inner") end) end)
eq(cur(COMBAT_FIREDAMAGE)[1], 811, "restored after an inner error")

-- the quiet counter is back to zero: a later call sets 0 again
local again
V.withoutHitEffect(COMBAT_FIREDAMAGE, function() again = cur(COMBAT_FIREDAMAGE)[1] end)
eq(again, 0, "a later call works the same")

-- pair 29 off (nothing recorded): stock again after, not 0
engine[1000 + COMBAT_FIREDAMAGE] = nil
V.engineHits = {}
local during
V.withoutHitEffect(COMBAT_FIREDAMAGE, function() during = cur(COMBAT_FIREDAMAGE) end)
eq(during and during[1], 0, "pair 29 off: 0 during")
eq(cur(COMBAT_FIREDAMAGE), nil, "pair 29 off: stock (-1) after, no override left")

-- applyEngine records the rows it sets (kind 1 only)
V.engineHits = nil
Game.clearEffectOverrides = function() engine = {} end
Game.setMissileEffect = function() end
if V.live() then
	V.applyEngine()
	local h = V.engineHits[COMBAT_FIREDAMAGE]
	ok(h ~= nil and h[1] == 1 and h[2] == COMBAT_FIREDAMAGE, "applyEngine records the fire row")
	eq(cur(COMBAT_FIREDAMAGE) and cur(COMBAT_FIREDAMAGE)[1], h and h[3], "and it is what the engine holds")
	V.withoutHitEffect(COMBAT_FIREDAMAGE, function() end)
	eq(cur(COMBAT_FIREDAMAGE) and cur(COMBAT_FIREDAMAGE)[1], h and h[3], "restored to the recorded blast")
end

if failures > 0 then
	print(failures .. " failure(s)")
	os.exit(1)
end
print("pyre_hit_effect_test: ok")
