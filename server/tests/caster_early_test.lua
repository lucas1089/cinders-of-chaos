-- Run from the server/ folder: luajit tests/caster_early_test.lua && lua5.3 tests/caster_early_test.lua (CI runs both)
-- O764: the caster early gain (spell_factor_config.lua `early`, spell_factor_core.lua F.earlyGain / F.earlyFor / F.early, applied
-- by the ChaosPassiveDealt event of passivetree_effects.lua): the gain curve, the vocations, the magic level tilt, the scope of
-- the class factor, nothing from level 200 up, and every caster formula shape of server/data/spells/rotation_model.csv still
-- growing with the magic level (the O468 rule: a damage spell reads the level and the magic level).
local checks, fails = 0, 0
local function ok(cond, m)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. (m or ""))
	end
end
local function near(a, b, m, tol)
	ok(math.abs(a - b) <= (tol or 1e-9), (m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end

dofile("data/scripts/chaos/spell_factor_config.lua")
dofile("data/scripts/chaos/spell_factor_core.lua")
local F, C = ChaosSpellFactor, ChaosSpellFactorConfig
local E = C.early
ok(E ~= nil, "spell_factor_config.lua has the early block")

-- the vocations: the Mystic and Necromancer lines (docs/CLASSES.md ids), no other class
local listed = {}
for _, v in ipairs(E.vocations) do
	listed[v] = true
end
for _, v in ipairs({1, 5, 10, 20, 21, 22}) do
	ok(listed[v], "vocation " .. v .. " is a caster of the early gain")
end
local count = 0
for _ in pairs(listed) do
	count = count + 1
end
ok(count == 6, "six caster vocations")

-- the gain: +25% up to level 50, +7% at 100 (the cap of class_dps_model.py at 100), 0 at 200, straight in log level, 0 above
near(F.earlyGain(8), 0.25, "gain at 8")
near(F.earlyGain(50), 0.25, "gain at 50")
near(F.earlyGain(100), 0.07, "gain at 100", 1e-9)
near(F.earlyGain(75), 0.25 - 0.18 * math.log(1.5) / math.log(2), "gain at 75", 1e-9)
near(F.earlyGain(200), 0, "gain at 200")
for _, L in ipairs({201, 300, 500, 1000, 1500, 2000, 2500}) do
	near(F.earlyGain(L), 0, "no gain at " .. L)
	for _, v in ipairs({1, 5, 10, 20, 21, 22}) do
		near(F.earlyFor(v, L, 100), 1, "no change at level " .. L .. " vocation " .. v)
	end
end
local last = 1
for L = 8, 220 do
	local g = F.earlyGain(L)
	ok(g <= last + 1e-12 and g >= 0, "the gain never rises with the level (" .. L .. ")")
	last = g
end

-- refML equals server/tools/rotation_sim.py ANCHORS 'ml_caster' (the typical caster of every balance model)
local py = io.open("tools/rotation_sim.py"):read("*a")
local anchors = py:match("'ml_caster':%s*(%b[])")
ok(anchors ~= nil, "rotation_sim.py has ANCHORS ml_caster")
local i = 0
for lv, ml in anchors:gmatch("%((%d+),%s*(%d+)%)") do
	i = i + 1
	local row = E.refML[i]
	ok(row and row[1] == tonumber(lv) and row[2] == tonumber(ml), "refML row " .. i .. " is the ANCHORS row (" .. lv .. ", " .. ml .. ")")
end
ok(i == #E.refML, "refML has the ANCHORS rows only")

-- the tilt: the typical magic level gains exactly the gain; a caster below it more, above it less, inside the tilt
for _, L in ipairs({8, 20, 35, 50, 75, 100, 150}) do
	local g, ref = F.earlyGain(L), F.earlyRefML(L)
	near(F.earlyFor(1, L, ref), 1 + g, "typical caster at " .. L, 1e-9)
	ok(F.earlyFor(1, L, 0) >= 1 + g, "a caster with no magic level gains at least the gain at " .. L)
	ok(F.earlyFor(1, L, 0) <= 1 + g * E.tilt[2] + 1e-12, "the tilt's top at " .. L)
	ok(F.earlyFor(1, L, ref + 50) < 1 + g, "a caster above the typical magic level gains less at " .. L)
	ok(F.earlyFor(1, L, 500) >= 1 + g * E.tilt[1] - 1e-12, "the tilt's bottom at " .. L)
	-- the weapon classes and the hybrids: nothing
	for _, v in ipairs({3, 4, 7, 8, 11, 12, 13, 14, 15, 17, 18, 19, 23, 24, 25, 0}) do
		near(F.earlyFor(v, L, ref), 1, "vocation " .. v .. " has no early gain at " .. L)
	end
end

-- the scope: ORIGIN_SPELL damage only (not healing, a weapon hit, a proc or a guarded hit)
local SPELL, MELEE, HEAL, FIRE = 1, 2, 64, 8
near(F.early(1, SPELL, FIRE, SPELL, HEAL, false, nil, 20, 12), F.earlyFor(1, 20, 12), "a spell hit")
near(F.early(1, MELEE, FIRE, SPELL, HEAL, false, nil, 20, 12), 1, "a weapon hit")
near(F.early(1, SPELL, HEAL, SPELL, HEAL, false, nil, 20, 12), 1, "a heal")
near(F.early(1, SPELL, 0, SPELL, HEAL, false, nil, 20, 12), 1, "no damage")
near(F.early(1, SPELL, FIRE, SPELL, HEAL, true, nil, 20, 12), 1, "a keystone proc")
near(F.early(1, SPELL, FIRE, SPELL, HEAL, false, nil, 20, 12, true), 1, "a player target (PvP keeps its numbers)")
near(F.early(1, SPELL, FIRE, SPELL, HEAL, false, nil, 20, 12, false), F.earlyFor(1, 20, 12), "a monster target")
local guarded
F.guard(function() guarded = F.early(20, SPELL, FIRE, SPELL, HEAL, false, nil, 20, 12) end)
near(guarded, 1, "a guarded hit (a minion's)")

-- O468: every caster formula shape (ML x c + base) of rotation_model.csv, the level term level / 5 on top, still grows with the
-- magic level at every level 8-200 with the gain on (magic level 0 to 300)
local csv = io.open("data/spells/rotation_model.csv"):read("*a")
local shapes, seen = {}, {}
for c, b in csv:gmatch("ML%*([%d%.]+)%+?([%d%.]*)") do
	local key = c .. "/" .. b
	if not seen[key] then
		seen[key] = true
		shapes[#shapes + 1] = {tonumber(c), tonumber(b) or 0}
	end
end
-- Kindling Spark and Bewitching Hex (stock scripts, patch_stock_spell_inputs.py)
shapes[#shapes + 1] = {0.2, 7.5}
shapes[#shapes + 1] = {0.3, 17}
shapes[#shapes + 1] = {2, 44.5}
ok(#shapes > 50, "the formula shapes of rotation_model.csv were read")
local bad = 0
for _, s in ipairs(shapes) do
	for L = 8, 200, 3 do
		local prev
		for ml = 0, 300 do
			local hit = (L / 5 + ml * s[1] + s[2]) * F.earlyFor(1, L, ml)
			if prev and hit < prev - 1e-9 then
				bad = bad + 1
				break
			end
			prev = hit
		end
	end
end
ok(bad == 0, "every caster formula grows with the magic level (" .. bad .. " shapes and levels do not)")

-- the event applies it: passivetree_effects.lua multiplies both parts of a hit by F.early with the attacker's magic level
local src = io.open("data/scripts/chaos/passivetree_effects.lua"):read("*a")
ok(src:find("f1 = f1 %* ChaosSpellFactor%.early%(vocId, origin, primaryType") ~= nil, "the primary part takes the early gain")
ok(src:find("ml, vsPlayer%)") ~= nil, "the event tells the rule a player target")
ok(src:find("f2 = f2 %* ChaosSpellFactor%.early%(vocId, origin, secondaryType") ~= nil, "the secondary part takes the early gain")

print(string.format("caster_early_test: %d checks, %d failures", checks, fails))
if fails > 0 then
	os.exit(1)
end
