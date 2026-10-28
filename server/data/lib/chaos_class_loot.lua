-- chaos_class_loot.lua: loot rows for the classes the base loot tables forget (server/README.md "Gear coverage").
-- Loaded with
--     ChaosClassLoot = ChaosClassLoot or dofile("data/lib/chaos_class_loot.lua")
-- by data/scripts/chaos/class_loot.lua (the rows) and tools/gear_coverage.lua (the fairness report). Plain Lua, no
-- engine calls at load; tested by tests/class_loot_test.lua. Lua 5.1 / LuaJIT and 5.3.
--
-- Why: the stock monsters drop swords, axes and clubs, but never a bow, a crossbow or a quiver, and wands, rods and
-- spellbooks only rarely. A Ranger found no weapon in the wild and a caster found a tenth of what a Warrior found
-- (tools/gear_coverage.lua --fairness). The rows here give each family a chance per kill that matches the melee
-- weapons of the base tables, on top of them. The chaos loot layer rolls rarity, item level and modifiers as for any
-- gear drop, so the item level carries the power beyond the last base.
--
-- The bases are the stock items of data/items/base_weapons.csv (bows, crossbows, wands and rods, no charges) and of
-- the quiver and spellbook lists of data/lib/chaos_archery_config.lua and tools/gear_coverage_config.lua. The test
-- reads the CSV and checks that every id and level below is still the CSV's.

local L = {}

-- {server id, required level}, sorted by level then id
L.bases = {
	melee1h = {
		{2411, 0}, {2419, 0}, {2422, 0}, {2423, 20}, {2429, 20}, {7385, 20}, {2434, 25}, {7408, 25}, {2392, 30},
		{3962, 30}, {7430, 30}, {2432, 35}, {7451, 35}, {7456, 35}, {3961, 40}, {13871, 40}, {15451, 40}, {2424, 45},
		{2446, 45}, {7412, 45}, {15647, 48}, {7383, 50}, {7409, 50}, {7411, 50}, {7388, 55}, {7410, 55}, {23542, 55},
		{7384, 60}, {7389, 60}, {7415, 60}, {18450, 62}, {7417, 65}, {7421, 65}, {7433, 65}, {7418, 70}, {7420, 70},
		{15492, 70}, {22398, 75}, {22404, 75}, {22410, 75}, {2400, 80}, {7431, 80}, {15404, 80}, {12648, 82}, {12649, 82},
		{2421, 85}, {7435, 85}, {2431, 90}, {15414, 90}, {8928, 100}, {26759, 100}, {26760, 100}, {8924, 110}, {8927, 120},
		{18451, 120}, {22405, 120}, {8925, 130}, {25415, 150}, {25416, 150}, {25418, 150}, {27229, 220}, {28712, 220},
		{28714, 220}, {22400, 250}, {22406, 250}, {22412, 250}, {27210, 270}, {28102, 300}, {28103, 300}, {28104, 300},
		{28373, 350}, {28374, 350}, {28375, 350}, {27377, 400}, {28025, 400}, {28026, 400}, {27458, 600}, {27460, 600},
		{27462, 600}, {29883, 1000}, {29885, 1000}, {29887, 1000}
	},
	melee2h = {
		{2377, 20}, {7425, 20}, {11309, 20}, {2381, 25}, {2387, 25}, {7379, 25}, {7380, 35}, {7392, 35}, {7406, 35},
		{15400, 38}, {7386, 40}, {7413, 40}, {7426, 40}, {7402, 45}, {7427, 45}, {7436, 45}, {2391, 50}, {2447, 50},
		{15454, 50}, {2393, 55}, {2427, 55}, {7428, 55}, {12613, 58}, {2414, 60}, {7382, 60}, {7414, 60}, {2444, 65},
		{2454, 65}, {7403, 65}, {2443, 70}, {2452, 70}, {7405, 70}, {22401, 75}, {22407, 75}, {22413, 75}, {7423, 85},
		{7453, 85}, {2415, 95}, {8929, 100}, {8932, 100}, {2408, 120}, {8926, 120}, {22414, 120}, {2390, 140},
		{27642, 150}, {27285, 180}, {27269, 250}, {27654, 250}, {27656, 250}, {27204, 300}, {27205, 300}, {27683, 300},
		{28128, 330}, {28129, 330}, {28130, 330}, {27378, 400}, {27380, 400}, {28027, 400}, {27465, 600}, {27467, 600},
		{27469, 600}, {29884, 1000}, {29886, 1000}, {29888, 1000}
	},
	fist = {
		{40000, 1}, {36654, 8}, {40001, 35}, {36655, 60}, {40002, 100}, {36656, 150}, {36657, 300}, {36658, 500},
		{40003, 800}, {40004, 1000}, {40005, 1250}, {40006, 1500}, {40007, 1800}, {40008, 2200}
	},
	bow = {
		{2456, 0}, {8857, 40}, {13873, 40}, {8855, 50}, {8856, 60}, {8858, 70}, {22416, 75}, {8854, 80}, {15643, 85},
		{26758, 100}, {26765, 100}, {18454, 105}, {25522, 120}, {22417, 150}, {27646, 150}, {27230, 220},
		{28713, 220}, {22418, 250}, {27661, 250}, {27199, 300}, {28116, 300},
		{29477, 300}, {28131, 330}, {28377, 350}, {27383, 400}, {28052, 400},
		{27471, 600}, {29874, 1000}
	},
	crossbow = {
		{2455, 0}, {8849, 45}, {15644, 50}, {8850, 60}, {21690, 70}, {5803, 75}, {22419, 75}, {8853, 80},
		{18453, 90}, {8852, 100}, {25523, 120}, {8851, 130}, {16111, 150}, {22420, 150}, {28715, 220}, {22421, 250},
		{27212, 270}, {27685, 300}, {29479, 300}, {29480, 300}, {28137, 330}, {28378, 350}, {27384, 400},
		{28051, 400}, {27473, 600}, {27474, 600}, {29875, 1000}
	},
	wand = {
		{23719, 1}, {23721, 1}, {2190, 7}, {2191, 13}, {2188, 19}, {8921, 22}, {2189, 26}, {2187, 33}, {8920, 37},
		{13760, 37}, {13880, 40}, {8922, 42}, {18390, 65}, {18409, 65}, {25421, 65}, {25422, 100}, {26756, 100},
		{27650, 150}, {27193, 180}, {28717, 220}, {27194, 230}, {27665, 250}, {27666, 250}, {27688, 250}, {27198, 300},
		{28110, 300}, {29487, 300}, {28132, 330}, {28376, 350}, {27385, 400}, {28042, 400}, {29571, 400}, {27476, 600},
		{29866, 1000}
	},
	rod = {
		{23719, 1}, {23721, 1}, {2182, 7}, {2186, 13}, {2185, 19}, {8911, 22}, {2181, 26}, {2183, 33}, {8912, 37},
		{24839, 37}, {13872, 40}, {8910, 42}, {18411, 65}, {26757, 100}, {27649, 150}, {27671, 250}, {27689, 250},
		{18412, 300}, {27197, 300}, {29489, 300}, {29490, 300}, {28133, 330}, {27386, 400}, {27479, 600}, {27480, 600}
	},
	quiver = {
		{28693, 20}, {27651, 50}, {27694, 80}, {27696, 120}, {27663, 150}, {27686, 200}, {27676, 250}, {28379, 300},
		{27695, 350}, {29566, 400}, {28050, 500}, {29873, 1000}
	},
	book = {
		{2175, 0}, {8900, 30}, {8901, 40}, {8902, 50}, {8903, 60}, {8904, 70}, {8918, 80}, {22423, 120}, {16112, 150},
		{22424, 250}, {28111, 300}, {29572, 400}, {29865, 1000}
	}
}

L.KINDS = {"melee1h", "melee2h", "fist", "bow", "crossbow", "wand", "rod", "quiver", "book"}

-- the ids of the fist bases (for the audit's tests)
L.fistIds = {}
for _, b in ipairs(L.bases.fist) do
	L.fistIds[b[1]] = true
end

-- the weapon families each class wields, by class name (the loadouts of tools/gear_coverage_config.lua; the Elementalist
-- wields the wands of the sets, the Illusionist their rods, the other casters both; the Berserker fights two-handed; the
-- Monk line wields melee weapons and fights with fists; the Thief line has no throwing weapons, they are out of the game)
L.classKinds = {}
for _, g in ipairs({
	{{"Warrior", "Juggernaut", "Templar", "Inquisitor", "Sentinel", "Samurai", "Thief", "Ninja"}, {"melee1h", "melee2h"}},
	{{"Berserker"}, {"melee2h"}},
	{{"Monk", "Shadowfist", "Iron Sage"}, {"fist", "melee1h", "melee2h"}},
	{{"Ranger", "Deadeye"}, {"bow", "crossbow"}},
	{{"Beastmaster"}, {"bow"}},
	{{"Mystic", "Necromancer", "Lich", "Bone Lord"}, {"wand", "rod"}},
	{{"Elementalist"}, {"wand"}},
	{{"Illusionist"}, {"rod"}}
}) do
	for _, name in ipairs(g[1]) do
		L.classKinds[name] = g[2]
	end
end

L.config = {
	-- chance per kill (per 100000, the loot unit) that one piece of the family drops, shared by the eligible bases of the
	-- family: anchors {hunting level, chance} of a monster, linear between them, flat outside. The anchors of the weapon
	-- families are DERIVED (luajit tools/gear_coverage.lua --derive): every loadout of every class finds the same number
	-- of usable weapons per kill in every hunting band (owner, 2026-10-28, "monk weapons are very rare, they must all be
	-- equal"; tools/gear_coverage_config.lua fairTarget and fairRatio). Quivers and spellbooks: 0.8% at level 0 up to 2.4%
	-- from level 800 (one hand each; they are not weapons)
	chance = {
		melee1h = {{100, 1308}, {300, 3150}, {500, 2948}},
		melee2h = {{100, 1409}, {300, 3547}, {500, 4219}},
		fist = {{100, 2806}, {300, 2656}, {500, 5551}},
		bow = {{100, 5389}, {300, 2823}, {500, 3587}},
		crossbow = {{100, 3981}, {300, 3077}, {500, 3566}},
		wand = {{100, 2963}, {300, 2891}, {500, 3429}},
		rod = {{100, 2800}, {300, 2807}, {500, 4588}},
		quiver = {{0, 800}, {800, 2400}},
		book = {{0, 800}, {800, 2400}}
	},
	-- a boss of the bounty pool: a third of the sets' boss chance per family, so a boss kill is a real chance
	bossChance = {melee1h = 4000, melee2h = 4000, fist = 4000, bow = 4000, crossbow = 3000, wand = 2500, rod = 2500,
		quiver = 2000, book = 2000},
	-- a hunt above the highest base monster of the pool (hunting level 658 and up) is a level-scaled monster: its type carries
	-- the rows of its pool level, so the weapons of the class come from a roll at the kill instead (L.rollScaled, step 1e of
	-- loot.lua): for each family the killer's class wields, the chance below at the hunting level (anchors as above, DERIVED
	-- for the bands 800, 1000 and 1200), times the rate, item find and pack scale of the kill (at most maxScale) and the
	-- tier factor (a boss 3 times as likely, as the rows of the bosses above)
	scaled = {
		minLevel = 658,
		maxScale = 3,
		tierMult = {magic = 1.5, rare = 2, legendary = 3, boss = 3},
		chance = {
			melee1h = {{800, 2549}, {1000, 2651}, {1200, 2777}},
			melee2h = {{800, 2585}, {1000, 2681}, {1200, 2777}},
			fist = {{800, 2800}, {1000, 2800}, {1200, 2800}},
			bow = {{800, 2667}, {1000, 2727}, {1200, 2745}},
			crossbow = {{800, 2711}, {1000, 2727}, {1200, 2800}},
			wand = {{800, 2678}, {1000, 2703}, {1200, 2749}},
			rod = {{800, 2678}, {1000, 2703}, {1200, 2749}}
		}
	},
	-- no single row below this
	minChance = 10,
	-- a base is eligible when its level is at most the monster's hunting level + above and at least its level - below;
	-- a monster above every window drops the `fallback` highest bases
	window = {below = 150, above = 20},
	fallback = 3,
	-- ... but only those within `fallbackSpan` levels of the highest one: above the last base (the stock gear stops at level
	-- 1000) a hunt of level 2000 dropped the three highest bases, a level 400 bow among them, as a hunt of 800 did. Now it
	-- drops the best base only, and the equipment sets' level gear (data/lib/chaos_gear_sets.lua) carries the levels above
	fallbackSpan = 200
}

-- the bases of one family a monster of hunting level `level` may drop (by level, then id): those in the window, else the
-- `fallback` highest below it that are within `fallbackSpan` of the highest
function L.eligible(kind, level, cfg)
	cfg = cfg or L.config
	level = tonumber(level) or 0
	local w = cfg.window
	local inWindow, below = {}, {}
	for _, b in ipairs(L.bases[kind] or {}) do
		if b[2] <= level + w.above then
			below[#below + 1] = b
			if b[2] >= level - w.below then
				inWindow[#inWindow + 1] = b
			end
		end
	end
	if #inWindow > 0 then
		return inWindow
	end
	local out = {}
	local top = #below > 0 and below[#below][2] or 0
	for i = math.max(1, #below - cfg.fallback + 1), #below do
		if not cfg.fallbackSpan or below[i][2] >= top - cfg.fallbackSpan then
			out[#out + 1] = below[i]
		end
	end
	return out
end

-- the value of anchors {{level, value}, ...} at a level: linear between them, flat outside
function L.interpolate(pts, level)
	level = tonumber(level) or 0
	if level <= pts[1][1] then
		return pts[1][2]
	end
	for i = 2, #pts do
		if level <= pts[i][1] then
			local a, b = pts[i - 1], pts[i]
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

-- the chance of a family for a monster of hunting level `level` (per 100000): the anchors of cfg.chance
function L.chanceAt(kind, level, cfg)
	cfg = cfg or L.config
	local pts = cfg.chance and cfg.chance[kind]
	if not pts or #pts == 0 then
		return 0
	end
	return L.interpolate(pts, level)
end

-- the chance per kill (per 100000) of a family at a hunting level of a scaled hunt: the anchors of cfg.scaled.chance
function L.scaledChanceAt(kind, level, cfg)
	cfg = cfg or L.config
	local pts = cfg.scaled and cfg.scaled.chance and cfg.scaled.chance[kind]
	return pts and L.interpolate(pts, level) or 0
end

-- the weapons a kill of a scaled hunt (hunting level `level`, cfg.scaled.minLevel and up) drops for the killer's class:
-- a list of base ids, at most one per family the class wields. tier = the monster tier ("normal", "magic", "rare",
-- "legendary", "boss"), scale = rate x item find x pack scale, rnd(a, b) -> integer in [a, b]
function L.rollScaled(level, className, tier, scale, rnd, cfg)
	cfg = cfg or L.config
	local s = cfg.scaled
	local out = {}
	level = tonumber(level) or 0
	if not s or level < s.minLevel then
		return out
	end
	scale = math.min(s.maxScale, math.max(0, tonumber(scale) or 1)) * (s.tierMult[tier] or 1)
	for _, kind in ipairs(L.classKinds[className] or {}) do
		if rnd(1, 100000) <= L.scaledChanceAt(kind, level, cfg) * scale then
			local list = L.eligible(kind, level, cfg)
			if #list > 0 then
				out[#out + 1] = list[rnd(1, #list)][1]
			end
		end
	end
	return out
end

-- the loot rows {monster name, item id, chance per 100000} of a bounty pool ({hunt = {...}, bosses = {...}}).
-- levelOf(entry) -> hunting level (pace_core.lua P.entryLevel); without it the pool level.
function L.lootRows(pool, levelOf, cfg)
	cfg = cfg or L.config
	levelOf = levelOf or function(e) return tonumber(e.level) or 1 end
	local rows = {}
	for gi, group in ipairs({pool and pool.hunt or {}, pool and pool.bosses or {}}) do
		for _, e in ipairs(group) do
			local level = levelOf(e)
			for _, kind in ipairs(L.KINDS) do
				local list = L.eligible(kind, level, cfg)
				local total = math.floor(gi == 1 and L.chanceAt(kind, level, cfg) or (tonumber(cfg.bossChance[kind]) or 0))
				if #list > 0 and total > 0 then
					local each = math.max(cfg.minChance, math.floor(total / #list))
					for _, b in ipairs(list) do
						rows[#rows + 1] = {e.name, b[1], each}
					end
				end
			end
		end
	end
	return rows
end

return L
