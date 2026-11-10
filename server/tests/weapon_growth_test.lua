-- Run from the server/ folder: luajit tests/weapon_growth_test.lua && lua5.3 tests/weapon_growth_test.lua (CI runs both)
-- O472 (2026-11-10, owner: "You can do everything"; the damage design, section B5): the weapon values grow with the level.
--   * the factor W(level) and the attack growth a = 1 + (W - 1) / 0.85 (spell_scaling_config.lua weaponGrowth; the same table is in
--     tools/weapon_growth.py): the rows, monotone, no step above x1.12 per 50 levels, flat above 2000, 1 up to level 100
--   * the weapon curves of the install tools and the audit are the old curves times a at every anchor
--   * the caster factor 1 + (W - 1) x min(1.2, wand / mean wand of the level): a wand of the level's band gives W, none gives 1, a
--     better one up to 20% more of the growth, a weaker one less; healing does not take it
--   * every damage spell of the Mystic, Elementalist, Illusionist and Necromancer lines takes it once (cast on the probe engine), its
--     scripted damage over time ticks too, a heal does not, a weapon class's spell does not
--   * the Monk's fist attack and the Thief's shuriken grow with the level
local checks, fails = 0, 0
local function ok(c, m)
	checks = checks + 1
	if not c then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function near(a, b, tol, m)
	ok(math.abs(a - b) <= (tol or 1e-9), (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
local function readAll(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

dofile("data/scripts/chaos/spell_scaling_config.lua")
dofile("data/scripts/chaos/spell_scaling_core.lua")
local S, cfg = ChaosSpellScaling, ChaosSpellScalingConfig

-- ------------------------------------------------------------------------------------------------ W and a
local ROWS = {{100, 1.00}, {200, 1.14}, {300, 1.26}, {500, 1.42}, {700, 1.55}, {850, 1.85}, {1000, 2.20}, {1500, 2.35}, {2000, 2.60}}
for i, r in ipairs(ROWS) do
	ok(cfg.weaponGrowth[i] and cfg.weaponGrowth[i][1] == r[1] and cfg.weaponGrowth[i][2] == r[2], "the row " .. r[1])
	near(S.weaponW(r[1]), r[2], 1e-9, "W(" .. r[1] .. ")")
end
ok(#cfg.weaponGrowth == #ROWS, "nine rows")
near(S.weaponW(1), 1, 0, "W below 100"); near(S.weaponW(100), 1, 0, "W(100)"); near(S.weaponW(5000), 2.6, 0, "flat above 2000")
near(S.weaponA(500), 1 + 0.42 / 0.85, 1e-9, "a(500)"); near(S.weaponA(1000), 1 + 1.2 / 0.85, 1e-9, "a(1000)")
near(S.weaponA(100), 1, 0, "a(100)")
-- monotone, smooth: no step above x1.12 over 50 levels
local prev, worst = S.weaponW(100), 1
for level = 101, 2100 do
	local w = S.weaponW(level)
	ok(w >= prev - 1e-12, "W never falls (" .. level .. ")")
	prev = w
	if level - 50 >= 100 then
		worst = math.max(worst, w / S.weaponW(level - 50))
	end
end
ok(worst <= 1.12, "no step above x1.12 per 50 levels (widest " .. worst .. ")")
-- the Python side holds the same table
do
	local py = readAll("tools/weapon_growth.py")
	local body = py:match("WEAPON_GROWTH = %((.-)%)\nWEAPON_SKILL_SHARE")
	local n = 0
	for lv, w in body:gmatch("%((%d+), ([%d%.]+)%)") do
		n = n + 1
		ok(cfg.weaponGrowth[n] and cfg.weaponGrowth[n][1] == tonumber(lv) and cfg.weaponGrowth[n][2] == tonumber(w), "tools/weapon_growth.py row " .. n)
	end
	ok(n == #cfg.weaponGrowth, "same number of rows in Python (" .. n .. ")")
	ok(py:match("WEAPON_SKILL_SHARE = 0%.85") and cfg.skillShare == 0.85, "skill share 0.85")
end

-- ------------------------------------------------------------------------------------------------ the curves are old x a
do
	local py = readAll("tools/install_gear_sets.py")
	local function list(block, name)
		local text = py:match("\n" .. block .. " = %{(.-)\n%}")
		local body = text:match("'" .. name .. "':%s*%(([^)]*)%)")
		local t = {}
		for v in body:gmatch("%d+") do t[#t + 1] = tonumber(v) end
		return t
	end
	local function anchors(name)
		local t = {}
		for v in py:match("\n" .. name .. " = %(([^)]*)%)"):gmatch("%d+") do t[#t + 1] = tonumber(v) end
		return t
	end
	local function lin(xs, ys, level)
		if level <= xs[1] then return ys[1] end
		for i = 2, #xs do
			if level <= xs[i] then return ys[i - 1] + (ys[i] - ys[i - 1]) * (level - xs[i - 1]) / (xs[i] - xs[i - 1]) end
		end
		return ys[#ys]
	end
	local oldA, newA = anchors("ANCHORS"), anchors("WEAPON_ANCHORS")
	for _, name in ipairs({"attack", "bow", "wand"}) do
		local old, new = list("OLD_WEAPON_CURVES", name), list("WEAPON_CURVES", name)
		ok(#new == #newA, name .. ": a value per anchor")
		for i, level in ipairs(newA) do
			local want = lin(oldA, old, level) * S.weaponA(level)
			ok(math.abs(new[i] - want) <= 0.51, name .. " at " .. level .. ": " .. new[i] .. " is the old curve x a (" .. want .. ")")
		end
		-- between the anchors a straight line is within 1.5% of the exact growth
		for level = 100, 2000, 7 do
			local exact = lin(oldA, old, level) * S.weaponA(level)
			ok(math.abs(lin(newA, new, level) / exact - 1) <= 0.015, name .. " between the anchors at " .. level)
		end
	end
	-- the audit's curves and the caster factor's mean wand are the same numbers
	local wc = dofile("tools/weapon_coverage_config.lua")
	local wand = list("WEAPON_CURVES", "wand")
	for i, level in ipairs(newA) do
		ok(wc.curves.wand[i] == wand[i] and wc.anchors[i] == level, "weapon_coverage_config wand curve point " .. i)
		ok(cfg.caster.wandMean[i] and cfg.caster.wandMean[i][1] == level and cfg.caster.wandMean[i][2] == wand[i], "caster.wandMean point " .. i)
	end
	ok(#cfg.caster.wandMean == #newA, "same number of wandMean points")
	-- the numbers of the design, the ones that are old x a to the unit
	local attack = list("WEAPON_CURVES", "attack")
	local at = {}
	for i, level in ipairs(newA) do at[level] = attack[i] end
	ok(at[200] == 57 and at[300] == 67 and at[500] == 81 and at[700] == 94 and at[1000] == 147 and at[1500] == 168 and at[2000] == 199,
		"one-hand attack 57 / 67 / 81 / 94 / 147 / 168 / 199 at 200 / 300 / 500 / 700 / 1000 / 1500 / 2000")
end

-- ------------------------------------------------------------------------------------------------ the caster factor
for _, level in ipairs({100, 200, 300, 500, 700, 1000, 1500, 2000}) do
	local mean = S.wandMeanOfLevel(level)
	near(S.casterFactor(level, mean), S.weaponW(level), 1e-12, "a wand of the band gives W at " .. level)
	near(S.casterFactor(level, mean * 5), 1 + (S.weaponW(level) - 1) * 1.2, 1e-12, "a far better wand: at most 20% more of the growth at " .. level)
	near(S.casterFactor(level, mean * 1.1), 1 + (S.weaponW(level) - 1) * 1.1, 1e-12, "10% better: 10% more at " .. level)
	near(S.casterFactor(level, mean * 0.5), 1 + (S.weaponW(level) - 1) * 0.5, 1e-12, "half the wand: half the growth at " .. level)
	near(S.casterFactor(level, 0), 1, 0, "no wand gives 1 at " .. level)
	near(S.casterFactor(level, nil), 1, 0, "nil gives 1 at " .. level)
end
near(S.casterFactor(500, S.wandMeanOfLevel(500)), 1.42, 1e-12, "W(500) = 1.42 for a wand of the band")
near(S.casterFactor(1000, S.wandMeanOfLevel(1000)), 2.2, 1e-12, "W(1000) = 2.2 for a wand of the band")
near(S.casterFactor(50, 100), 1, 1e-12, "below level 100 there is no growth")
-- the wand of a player: the weapon in either hand with the weapon type wand, its mean from the tables, a wand not in them counts as the level's
do
	local WAND, SWORD = 8001, 8002
	_G.ItemType = function(id)
		return {getWeaponType = function() return id == WAND and 7777 or 5555 end}
	end
	_G.WEAPON_WAND, _G.CONST_SLOT_LEFT, _G.CONST_SLOT_RIGHT = 7777, 1, 2
	S.wands = {[WAND] = {min = 100, max = 200}}
	local function player(left, right, level)
		local hands = {[1] = left, [2] = right}
		return {getLevel = function() return level end,
			getSlotItem = function(_, slot) local id = hands[slot]; return id and {getId = function() return id end} or nil end}
	end
	near(S.equippedWandMean(player(WAND, nil, 500)), 150, 0, "the wand's mean damage")
	near(S.equippedWandMean(player(SWORD, WAND, 500)), 150, 0, "the right hand too")
	ok(S.equippedWandMean(player(SWORD, nil, 500)) == nil, "a sword is no wand")
	ok(S.equippedWandMean(player(nil, nil, 500)) == nil, "empty hands")
	near(S.casterForPlayer(player(WAND, nil, 500)), 1 + 0.42 * 150 / 151, 1e-12, "a wand of mean 150 at level 500: 99% of the growth")
	near(S.casterForPlayer(player(nil, nil, 500)), 1, 0, "no wand: 1")
	near(S.casterForPlayer(player(8003, nil, 500)), 1, 0, "an unknown id is no wand (its type says sword)")
	_G.ItemType = function() return {getWeaponType = function() return 7777 end} end
	near(S.casterForPlayer(player(8003, nil, 500)), 1.42, 1e-12, "a wand missing from the tables counts as the level's own: W")
	S.wands = nil
	_G.ItemType, _G.WEAPON_WAND, _G.CONST_SLOT_LEFT, _G.CONST_SLOT_RIGHT = nil, nil, nil, nil
end

-- ------------------------------------------------------------------------------------------------ every caster spell takes it once
local spells = {}
do
	local xml = readAll("data/spells/chaos/spells_chaos.xml")
	for attrs, body in xml:gmatch("<instant ([^>]*)>(.-)</instant>") do
		local s = {id = tonumber(attrs:match('spellid="(%d+)"')), name = attrs:match('name="([^"]+)"'), group = attrs:match('group="([^"]+)"'),
			script = attrs:match('script="([^"]+)"'), vocs = {}}
		for v in body:gmatch('<vocation name="([^"]+)"') do s.vocs[#s.vocs + 1] = v end
		spells[#spells + 1] = s
	end
end
local CASTER = {Mystic = 1, Elementalist = 5, Illusionist = 10, Necromancer = 20, Lich = 21, ["Bone Lord"] = 22}
local OTHER = {Ranger = 3, Warrior = 4, Deadeye = 7, Juggernaut = 8, Thief = 11, Ninja = 12, Samurai = 13, Berserker = 14, Beastmaster = 15,
	Monk = 17, Shadowfist = 18, ["Iron Sage"] = 19, Templar = 23, Inquisitor = 24, Sentinel = 25}
local ANCHORS = {
	ml_caster = {{1, 0}, {100, 60}, {300, 100}, {600, 120}, {1000, 140}},
	ml_other = {{1, 0}, {100, 10}, {300, 25}, {600, 32}, {1000, 40}},
	skill = {{1, 10}, {100, 80}, {300, 110}, {600, 125}, {1000, 140}},
}
local function interp(pts, x)
	if x <= pts[1][1] then return pts[1][2] end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if x <= b[1] then return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1]) end
	end
	return pts[#pts][2]
end

local Probe = dofile("tests/fixtures/spell_probe_engine.lua")
ok(Probe.loadError == nil, "chaos_constants loads on the mock: " .. tostring(Probe.loadError))

local function profile(level, caster)
	local sk = interp(ANCHORS.skill, level)
	return {lvl = level, ml = interp(ANCHORS[caster and "ml_caster" or "ml_other"], level), sword = sk, club = sk, axe = sk, dist = sk, fist = sk,
		shield = 10, atk = 50, hpNow = 3000}
end

-- the wand on the probe: id 9001, weapon type wand; the mean damage of that id is `mean`
local function cast(s, cls, level, wandMean, caster)
	local p = profile(level, caster)
	p.wtype = wandMean and "wand" or "none"
	Probe.set(p)
	Probe.set({voc = cls})
	if ChaosSnares and ChaosSnaresCore then ChaosSnares.state = ChaosSnaresCore.newState() end
	if ChaosSpellScaling then
		ChaosSpellScaling.wands = ChaosSpellScaling.wands or {}
		ChaosSpellScaling.wands[9001] = wandMean and {min = wandMean, max = wandMean} or nil
	end
	local dots = {}
	local res
	if ChaosSpell and ChaosSpell.scriptedDot and not ChaosSpell._wrappedByGrowthTest then
		local real = ChaosSpell.scriptedDot
		ChaosSpell.scriptedDot = function(casterId, targetId, key, ctype, ticks, tickMs, base, effect)
			ChaosSpell._dots[#ChaosSpell._dots + 1] = base
			return real(casterId, targetId, key, ctype, ticks, tickMs, base, effect)
		end
		ChaosSpell._wrappedByGrowthTest = true
	end
	if ChaosSpell then ChaosSpell._dots = dots end
	res = Probe.cast(s.script)
	if ChaosSpell and ChaosSpell._dots ~= dots then dots = ChaosSpell._dots end
	local dmg, heal = Probe.total(res)
	local dot = 0
	for _, v in ipairs(ChaosSpell and ChaosSpell._dots or {}) do dot = dot + v end
	return dmg, heal, dot, res
end

local nDamage, nHeal, nDot = 0, 0, 0
for _, level in ipairs({500, 1000}) do
	local mean = S.wandMeanOfLevel(level)
	local W = S.weaponW(level)
	for _, s in ipairs(spells) do
		local cls, isCaster = s.vocs[1], true
		for _, v in ipairs(s.vocs) do
			if not CASTER[v] then isCaster = false end
		end
		if cls and (CASTER[cls] or OTHER[cls]) then
			local id = CASTER[cls] or OTHER[cls]
			local d0, h0, t0 = cast(s, id, level, nil, isCaster)
			if d0 + h0 + t0 > 0 then
				local d1, h1, t1 = cast(s, id, level, mean, isCaster)
				local d2, h2, t2 = cast(s, id, level, mean * 3, isCaster)
				if isCaster then
					if d0 > 0 then
						nDamage = nDamage + 1
						near(d1 / d0, W, 0.01 * W, s.name .. " (" .. cls .. ", level " .. level .. "): damage takes W with a wand of the band")
						near(d2 / d0, 1 + (W - 1) * 1.2, 0.01 * W, s.name .. " (" .. level .. "): a far better wand gives 20% more of the growth")
					end
					if t0 > 0 then
						nDot = nDot + 1
						near(t1 / t0, W, 0.01 * W, s.name .. " (" .. level .. "): the scripted ticks take W too")
					end
					if h0 > 0 and d0 == 0 then
						nHeal = nHeal + 1
						near(h1, h0, 1e-9, s.name .. " (" .. level .. "): a heal does not take the growth")
						near(h2, h0, 1e-9, s.name .. " (" .. level .. "): a heal does not take a better wand either")
					end
				else
					-- a weapon class's spell never asks for the caster factor: two different wands in the hand (the held weapon type is
					-- the same for both) give the same number
					local wa, ha, ta = cast(s, id, level, mean * 0.3, false)
					near(d2, wa, 1e-9, s.name .. " (" .. cls .. ", " .. level .. "): a spell of a weapon class does not take the caster factor")
					near(h2, ha, 1e-9, s.name .. " (" .. cls .. "): nor its heal")
					near(t2, ta, 1e-9, s.name .. " (" .. cls .. "): nor its ticks")
				end
			end
		end
	end
end
ok(nDamage >= 40, "at least 40 caster damage spells checked at two levels (" .. nDamage .. ")")
ok(nHeal >= 8, "caster heals checked (" .. nHeal .. ")")
ok(nDot >= 3, "scripted damage over time ticks checked (" .. nDot .. ")")

-- the Necromancer line's minions: their hit takes the caster factor, their health and the plain spells' covenant factor do not change
do
	local L = ChaosNecro
	ok(L and L.minionFactor and L.spellFactor, "necro_lib is loaded by the necro spells on the probe")
	if L then
		for _, level in ipairs({500, 1000}) do
			local mean = S.wandMeanOfLevel(level)
			Probe.set(profile(level, true)); Probe.set({voc = 20, wtype = "none"})
			S.wands = S.wands or {}
			S.wands[9001] = nil
			local p = Player(1)
			local hit0, hp0 = L.minionFactor(p, "skeleton", "hit"), L.minionFactor(p, "skeleton", "health")
			local sf0 = L.spellFactor(p)
			Probe.set({wtype = "wand"}); S.wands[9001] = {min = mean, max = mean}
			local hit1, hp1 = L.minionFactor(p, "skeleton", "hit"), L.minionFactor(p, "skeleton", "health")
			near(hit1 / hit0, S.weaponW(level), 1e-9, "a minion's hit takes W at " .. level)
			near(hp1, hp0, 1e-9, "a minion's health does not (" .. level .. ")")
			near(L.spellFactor(p) / sf0, S.weaponW(level), 1e-9, "the own spells' factor takes W at " .. level)
			cfg.caster.minions = false
			near(L.minionFactor(p, "skeleton", "hit"), hit0, 1e-9, "caster.minions = false leaves the minion hit as it was (" .. level .. ")")
			cfg.caster.minions = true
		end
	end
end

-- ------------------------------------------------------------------------------------------------ the Monk's fist and the Thief's shuriken
dofile("data/scripts/chaos/monk_chi_core.lua")
local M = ChaosMonk
for _, level in ipairs({100, 500, 1000, 2000}) do
	near(M.fistAttack(level), math.min(60, 40 + level * 0.025) * S.weaponA(level), 1e-9, "the bare fist at " .. level .. " is the level value x a")
end
ok(M.fistAttack(1000) > 140 and M.fistAttack(1000) < 150, "the bare fist at 1000 is about 145")
near(M.fistAttack(1000, 200), 200, 0, "a better fist weapon still wins")
-- the shuriken's default attack (50) grows by a(level): skill x 50 x a
for _, level in ipairs({100, 500, 1000}) do
	Probe.set(profile(level, false)); Probe.set({voc = 11, wtype = "none"})
	local p = Player(1)
	local skill = math.max(p:getEffectiveSkillLevel(SKILL_SWORD), p:getEffectiveSkillLevel(SKILL_DISTANCE))
	near(ChaosSpell.shurikenPower(p), skill * 50 * S.weaponA(level), 1e-6, "shuriken power at " .. level .. " = skill x 50 x a")
end

if fails > 0 then
	error("weapon_growth_test: " .. fails .. " failure(s)")
end
print("weapon_growth_test: " .. checks .. " checks ok")
