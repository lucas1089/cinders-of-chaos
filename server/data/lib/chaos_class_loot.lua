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
		{23719, 1}, {23721, 1}, {2182, 7}, {2190, 7}, {2186, 13}, {2191, 13}, {2185, 19}, {2188, 19}, {8911, 22},
		{8921, 22}, {2181, 26}, {2189, 26}, {2183, 33}, {2187, 33}, {8912, 37}, {8920, 37}, {13760, 37}, {24839, 37},
		{13872, 40}, {13880, 40}, {8910, 42}, {8922, 42}, {18390, 65}, {18409, 65}, {18411, 65}, {25421, 65},
		{25422, 100}, {26756, 100}, {26757, 100}, {27649, 150}, {27650, 150}, {27193, 180}, {28717, 220},
		{27194, 230}, {27665, 250}, {27666, 250}, {27671, 250}, {27688, 250}, {27689, 250},
		{18412, 300}, {27197, 300}, {27198, 300},
		{28110, 300}, {29487, 300}, {29489, 300}, {29490, 300}, {28132, 330}, {28133, 330},
		{28376, 350}, {27385, 400}, {27386, 400}, {28042, 400}, {29571, 400}, {27476, 600},
		{27479, 600}, {27480, 600}, {29866, 1000}
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

L.KINDS = {"bow", "crossbow", "wand", "quiver", "book"}

L.config = {
	-- chance per kill (per 100000, the loot unit) that one piece of the family drops, shared by the eligible bases of the
	-- family, before the boost below. The stock tables give a melee class 12 to 230 usable weapons per 1000 kills in the
	-- hunting bands (tools/gear_coverage.lua --fairness); a bow gets 1.6%, a crossbow 1.2%, wands and rods 2% (every
	-- caster line wears them), quivers and spellbooks 0.8% (one hand each)
	monsterChance = {bow = 1600, crossbow = 1200, wand = 2000, quiver = 800, book = 800},
	-- the stock tables drop more and more weapons per kill with the monster's level (the hunting bands 100 to 1000 give a
	-- melee class 12 to 230 usable weapons per 1000 kills): the monster chance grows by 1 + level / perLevel, up to cap
	boost = {perLevel = 400, cap = 3},
	-- a boss of the bounty pool: a third of the sets' boss chance per family, so a boss kill is a real chance
	bossChance = {bow = 4000, crossbow = 3000, wand = 5000, quiver = 2000, book = 2000},
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

-- the loot rows {monster name, item id, chance per 100000} of a bounty pool ({hunt = {...}, bosses = {...}}).
-- levelOf(entry) -> hunting level (pace_core.lua P.entryLevel); without it the pool level.
function L.lootRows(pool, levelOf, cfg)
	cfg = cfg or L.config
	levelOf = levelOf or function(e) return tonumber(e.level) or 1 end
	local rows = {}
	local boost = cfg.boost or {perLevel = 1e9, cap = 1}
	for gi, group in ipairs({{pool and pool.hunt or {}, cfg.monsterChance}, {pool and pool.bosses or {}, cfg.bossChance}}) do
		for _, e in ipairs(group[1]) do
			local level = levelOf(e)
			local mult = gi == 1 and math.min(boost.cap, 1 + level / boost.perLevel) or 1
			for _, kind in ipairs(L.KINDS) do
				local list = L.eligible(kind, level, cfg)
				local total = math.floor((tonumber(group[2][kind]) or 0) * mult)
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
