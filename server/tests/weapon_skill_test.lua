-- Run from the server/ folder: luajit tests/weapon_skill_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers weapon_skill_core.lua (server/README.md "Weapon damage scales with skills"): the typical stats by level, the
-- engine formula and how much of a hit is the skill's, and the wand / rod factor of the magic level: 1 at the typical
-- magic level of every level (no balance jump), more above, less below, clamped, monotonic.
dofile("data/scripts/chaos/weapon_skill_core.lua")
local S = ChaosWeaponSkill

local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function near(a, b, tol, what)
	ok(math.abs(a - b) <= tol, what .. ": " .. tostring(a) .. " ~ " .. tostring(b))
end

-- ------------------------------------------------------------------ the config
local c = S.config
for _, kind in ipairs({"skill", "magic"}) do
	local pts = c.typical[kind]
	ok(#pts >= 2, kind .. " has anchors")
	for i = 2, #pts do
		ok(pts[i][1] > pts[i - 1][1], kind .. " levels ascend")
		ok(pts[i][2] >= pts[i - 1][2], kind .. " values never drop")
	end
end
ok(c.wand.offset > 0, "wand offset > 0")
ok(c.wand.minFactor > 0 and c.wand.minFactor < 1 and c.wand.maxFactor > 1, "wand clamp around 1")

-- ------------------------------------------------------------------ typical stats
near(S.typical("skill", 100), 80, 1e-9, "skill anchor at 100")
near(S.typical("skill", 200), 95, 1e-9, "skill between 100 and 300")
near(S.typical("skill", 5000), 140, 1e-9, "skill flat above the last anchor")
near(S.typical("magic", 8), 0, 1e-9, "magic level 0 on level 8 (a new character)")
near(S.typical("magic", 1), 0, 1e-9, "flat below the first anchor")
near(S.typical("magic", 300), 100, 1e-9, "magic anchor at 300")
near(S.typical("magic", 450), 110, 1e-9, "magic between 300 and 600")
ok(S.typical("unknown", 100) == 0, "unknown kind: 0")

-- ------------------------------------------------------------------ the engine formula
ok(S.maxHit(100, 100, 60) == math.floor(20 + 26 * 20 * 1.03 + 0.5), "max hit")
ok(S.maxHit(8, 10, 16) == math.floor(1 + 3.5 * (16 / 3) * 1.03 + 0.5), "level / 5 is an integer division")
ok(S.maxHit(100, 100, 60, 2) < S.maxHit(100, 100, 60, 1), "the defensive stance hits less")
ok(S.maxHit(100, 100, 60, 0) == S.maxHit(100, 100, 60, 1), "a bad stance factor is 1")
-- the skill already drives the physical weapons: at the typical skill of levels 50 .. 1000 and the gear's attack, the
-- skill term is most of the maximum hit, and +10 skill is several percent more damage
local attackAt = {[50] = 40, [150] = 47.5, [300] = 51, [500] = 55, [1000] = 61}
for lv, atk in pairs(attackAt) do
	local sk = S.typical("skill", lv)
	local share = S.skillShare(lv, sk, atk)
	ok(share > 0.75, "level " .. lv .. ": the skill is most of the hit (" .. share .. ")")
	local gain = S.maxHit(lv, sk + 10, atk) / S.maxHit(lv, sk, atk)
	ok(gain > 1.05, "level " .. lv .. ": +10 skill is over +5% (" .. gain .. ")")
end
ok(S.skillShare(0, 0, 0) == 0, "no hit: share 0")

-- ------------------------------------------------------------------ the wand factor
for _, lv in ipairs({8, 15, 50, 100, 150, 300, 500, 1000, 2000}) do
	near(S.wandFactor(lv, S.typical("magic", lv)), 1, 1e-9, "level " .. lv .. ": the typical magic level is x1")
	ok(S.wandFactor(lv, S.typical("magic", lv) + 20) > 1, "level " .. lv .. ": more magic level, more damage")
	ok(S.wandFactor(lv, math.max(0, S.typical("magic", lv) - 20)) < 1 or S.typical("magic", lv) == 0,
		"level " .. lv .. ": less magic level, less damage")
end
-- the slope: +10% magic level at level 300 is about +8% (between +5% and +10%)
local f = S.wandFactor(300, 110)
ok(f > 1.05 and f < 1.10, "level 300, magic level 110: " .. f)
near(S.wandFactor(300, 80), 100 / 120, 1e-9, "level 300, magic level 80")
-- monotonic in the magic level, falling in the level
local last = 0
for ml = 0, 200, 5 do
	local v = S.wandFactor(300, ml)
	ok(v >= last, "monotonic at magic level " .. ml)
	last = v
end
ok(S.wandFactor(1000, 100) < S.wandFactor(300, 100), "the same magic level counts less at a higher level")
-- clamped
near(S.wandFactor(1000, 0), c.wand.minFactor, 1e-9, "clamped below")
near(S.wandFactor(8, 500), c.wand.maxFactor, 1e-9, "clamped above")
near(S.wandFactor(8, -5), S.wandFactor(8, 0), 1e-9, "a negative magic level is 0")
near(S.wandFactor(8, nil), S.wandFactor(8, 0), 1e-9, "nil is 0")
-- a new character (level 8, magic level 0) hits as before
near(S.wandFactor(8, 0), 1, 1e-9, "level 8, magic level 0")

print(string.format("weapon_skill_test: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
