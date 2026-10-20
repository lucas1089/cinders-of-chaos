-- Run from the server/ folder: luajit tests/leech_real_damage_test.lua (and lua5.3; CI runs both)
-- Leech from real damage only (engine patch 0048, server/README.md "Leech from real damage"). A Lua mirror of the
-- engine's leech rule in Combat::doTargetCombat (one target: weapon hit or spell) and Combat::doAreaCombat (area spell),
-- before (patches 0004/0011/0015) and after patch 0048, plus checks that the patch carries the guards the mirror has.
-- Zero damage and a target that cannot be attacked must not heal, must not take the leech window and must not divide by 0.

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function round(x) return math.floor(x + 0.5) end

-- p: skill (percent of the damage), dmg (damage + absorbed), attackable, windowOpen
-- returns healed, windowTaken
local function single(fixed, p)
	if fixed and not p.attackable then return 0, false end
	local value = round(p.dmg * (p.skill / 100))
	if fixed and value <= 0 then return 0, false end
	if not p.windowOpen then return 0, false end
	-- old engine: the window is taken at the roll, the heal is value (0 when the damage was 0)
	return value, true
end

-- targets: list of {dmg=, attackable=}; returns healed, windowTaken
local function area(fixed, p, targets)
	local maxDmg, n = 0, 0
	for _, t in ipairs(targets) do
		if not fixed or (t.dmg > 0 and t.attackable) then
			if t.dmg > maxDmg then maxDmg = t.dmg end
			n = n + 1
		end
	end
	if not (n > 0 and maxDmg > 0) then return 0, false end -- the engine's own guard before the leech block
	if not p.windowOpen then return 0, false end
	local base = maxDmg * (p.skill / 100)
	local final = round(base + base * 0.05 * (n > 1 and n - 1 or 0))
	if fixed then return final, final > 0 end
	return final, true
end

local base = {skill = 10, attackable = true, windowOpen = true}
local function with(t) local r = {} for k, v in pairs(base) do r[k] = v end for k, v in pairs(t) do r[k] = v end return r end

for _, fixed in ipairs{false, true} do
	-- a normal weapon hit and a normal spell hit leech the same (both rules)
	local h, w = single(fixed, with{dmg = 200})
	eq(h, 20, "weapon hit heals 10%") eq(w, true)
	-- the window is shared by weapon and spell: a second hit inside it heals nothing
	h = single(fixed, with{dmg = 200, windowOpen = false})
	eq(h, 0, "inside the window")
	-- area: one target, three targets (+5% of the base for each extra one)
	h = area(fixed, with{}, {{dmg = 100, attackable = true}})
	eq(h, 10)
	h = area(fixed, with{}, {{dmg = 100, attackable = true}, {dmg = 80, attackable = true}, {dmg = 60, attackable = true}})
	eq(h, 11, "10 + 2 x 0.5")
end

-- zero damage: no heal and the window stays free (the bug: the window was taken for a 0 heal)
local h, w = single(true, with{dmg = 0})
eq(h, 0) eq(w, false, "zero damage keeps the window free")
h, w = single(false, with{dmg = 0})
eq(w, true, "old rule: the window was burned by a 0 roll (the bug)")
-- a tiny hit that rounds to 0 is the same
h, w = single(true, with{dmg = 4})
eq(h, 0) eq(w, false)

-- immune / unattackable target (the engine reports its damage as done): no heal
h, w = single(true, with{dmg = 200, attackable = false})
eq(h, 0) eq(w, false, "not attackable")
h = single(false, with{dmg = 200, attackable = false})
eq(h, 20, "old rule: healed from a target that cannot be attacked (the bug)")

-- area: zero-damage and unattackable targets are not counted
local mix = {{dmg = 100, attackable = true}, {dmg = 0, attackable = true}, {dmg = 500, attackable = false}}
h = area(true, with{}, mix)
eq(h, 10, "only the target that took damage")
h = area(false, with{}, mix)
eq(h, 55, "old rule: 500 from the unattackable target plus 2 x 5% (the bug)")
-- all zero: no division, no heal, no window
h, w = area(true, with{}, {{dmg = 0, attackable = true}, {dmg = 0, attackable = true}})
eq(h, 0) eq(w, false)
h, w = area(true, with{}, {})
eq(h, 0) eq(w, false)
-- the area window is only taken when something heals
h, w = area(true, with{skill = 1}, {{dmg = 10, attackable = true}})
eq(h, 0) eq(w, false, "10 x 1% rounds to 0: window kept")
h, w = area(false, with{skill = 1}, {{dmg = 10, attackable = true}})
eq(w, true, "old rule: window burned")

-- ---------------------------------------------------------------- the patch carries the guards
local f = assert(io.open("src-patches/0048-leech-real-damage.patch", "r"), "patch 0048 missing")
local patch = f:read("*a")
f:close()
local function has(s) return patch:find(s, 1, true) ~= nil end
eq(has("damage.origin != ORIGIN_CONDITION && target->isAttackable())"), true, "single: attackable")
eq(has("int32_t leechValue = std::round(totalDamage * (skill / 100.));"), true, "single: value first")
eq(has("leechValue > 0 && casterPlayer->canLeech(false)"), true, "single life: value > 0")
eq(has("leechValue > 0 && casterPlayer->canLeech(true)"), true, "single mana: value > 0")
eq(has("if (dmgDealt > 0 && creature->isAttackable())"), true, "area: counted targets")
eq(has("+\t\t\t\t\t\tcasterPlayer->setLeeched(false);"), true, "area life: window after the check")
eq(has("+\t\t\t\t\t\tcasterPlayer->setLeeched(true);"), true, "area mana: window after the check")
eq(has("-\t\t\t\t\tcasterPlayer->setLeeched(false);"), true, "area life: old window removed")
eq(has("-\t\t\t\t\tcasterPlayer->setLeeched(true);"), true, "area mana: old window removed")

print(string.format("leech_real_damage_test: %d checks OK", checks))
