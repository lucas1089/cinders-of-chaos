-- Run from the server/ folder: luajit tests/weapons800_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- The 34 weapons above level 800 (data/lib/chaos_weapons800.lua, data/scripts/chaos/weapons800.lua): the data is complete and
-- on the equipment sets' curve of each level, the weapons are class loot bases of their family and NOT in the sets' level gear
-- pool, the own loot rows reach the monster types once (mocked MonsterType / ItemType / Loot) and are skipped while the items
-- are not installed (the client pair guard), and the weapon audit counts them.
dofile("data/scripts/chaos/chaos_constants.lua")
local W = dofile("data/lib/chaos_weapons800.lua")
local CL = dofile("data/lib/chaos_class_loot.lua")
local G = dofile("data/lib/chaos_gear_sets.lua")
local cfg = dofile("tools/weapon_coverage_config.lua")

local function eq(a, b, m) if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

-- ------------------------------------------------------------------ the data
eq(#W.ids, 34, "34 weapons")
eq(W.first, 48412, "first id"); eq(W.last, 48445, "last id")
local n, lastLevel = 0, 0
local byType = {}
for i, id in ipairs(W.ids) do
	local it = W.items[id]
	eq(it ~= nil, true, "item data for " .. id)
	eq(id >= W.first and id <= W.last, true, "id in the block")
	eq(it.level > 800 and it.level >= lastLevel, true, it.name .. ": above 800, sorted by level")
	lastLevel = it.level
	byType[it.type] = (byType[it.type] or 0) + 1
	n = n + 1
	-- the same power as the equipment sets at the weapon's level (weapon_coverage_config curves, 100% of the tier)
	local st = it.stats
	local power, tier
	if it.type == "wand" or it.type == "rod" then
		power = (st.wandMin + st.wandMax) / 2
		tier = cfg.curves.wand
	end
	local function curve(name)
		local xs, ys = cfg.anchors, cfg.curves[name]
		if it.level <= xs[1] then return ys[1] end
		for k = 2, #xs do
			if it.level <= xs[k] then
				return ys[k - 1] + (ys[k] - ys[k - 1]) * (it.level - xs[k - 1]) / (xs[k] - xs[k - 1])
			end
		end
		return ys[#ys]
	end
	if it.type == "wand" or it.type == "rod" then
		tier = curve("wand")
	elseif it.type == "bow" then
		power, tier = st.attack, curve("bow")
	elseif it.type == "crossbow" then
		power, tier = st.attack, curve("bow") + 3
	else
		power = st.attack + (st.elementFire or 0) + (st.elementIce or 0) + (st.elementEarth or 0) + (st.elementEnergy or 0)
			+ (st.elementDeath or 0) + (st.elementHoly or 0)
		tier = curve("attack") + 3
	end
	eq(math.abs(power - tier) <= 1, true, it.name .. ": power " .. power .. " against the tier " .. tier)
	eq(#it.classes > 0, true, it.name .. ": a class list")
end
eq(byType.bow, 9); eq(byType.crossbow, 4); eq(byType.wand, 9); eq(byType.rod, 9)
eq(byType.sword2, 1); eq(byType.axe2, 1); eq(byType.club2, 1)

-- ------------------------------------------------------------------ class loot bases, not level gear
local inBases = {}
for _, kind in ipairs(CL.KINDS) do
	for _, b in ipairs(CL.bases[kind]) do
		inBases[b[1]] = kind
	end
end
for _, id in ipairs(W.ids) do
	eq(inBases[id], W.items[id].family, W.items[id].name .. " is a class loot base of its family")
end
for _, p in ipairs(G.items.pieces) do
	eq(p.id >= W.first and p.id <= W.last, false, "no set piece in the weapons800 id block")
end
-- a scaled hunt of level 1000 reaches a new weapon for the class that wields it (the roll picks among the window's bases)
local always = function(a, b) return a end
local got = {}
for pick = 1, 40 do
	for _, id in ipairs(CL.rollScaled(1000, "Ranger", "normal", 1, function(a, b) return b > 100 and a or math.min(b, pick) end)) do
		got[id] = true
	end
end
local sawNew = false
for id in pairs(got) do
	if W.items[id] then sawNew = true end
end
eq(sawNew, true, "a Ranger's scaled roll at 1000 can pick a weapon above level 800")
for _, id in ipairs(CL.rollScaled(1000, "Berserker", "normal", 1, always)) do
	eq(inBases[id], "melee2h", "a Berserker rolls two-handed weapons")
end

-- ------------------------------------------------------------------ loot rows added once (mocked engine)
local types, added = {["frost maiden"] = {}, ["dawn strayer"] = {}}, {}
function MonsterType(name)
	local t = types[name:lower()]
	if not t then return nil end
	return {addLoot = function(_, loot) added[#added + 1] = {name, loot.id, loot.chance, loot.max}; return true end}
end
local installed = {[48412] = true, [48413] = true}
function ItemType(id) return {getId = function() return installed[id] and id or 0 end} end
function Loot()
	local l = {}
	function l:setId(v) self.id = v end
	function l:setChance(v) self.chance = v end
	function l:setMaxCount(v) self.max = v end
	return l
end
GlobalEvent = function() return {register = function() end} end
local printed = print
print = function() end
dofile("data/scripts/chaos/weapons800.lua")
local a, s = ChaosWeapons800Loot.addAll({{"Frost Maiden", 48412, 150}, {"Dawn Strayer", 48413, 150}, {"Nobody", 48412, 5},
	{"Frost Maiden", 48445, 150}})
print = printed
eq(a, 2, "two rows added"); eq(s, 2, "a missing monster and a missing item (client pair guard) are skipped")
eq(added[1][1], "Frost Maiden"); eq(added[1][2], 48412); eq(added[1][3], 150); eq(added[1][4], 1)
eq(select(1, ChaosWeapons800Loot.addAll()), 0, "only once per server run")
for _, row in ipairs(W.loot) do
	local it = W.items[row[2]]
	eq(it ~= nil, true, "loot of a weapon of the lib: " .. row[1])
	eq(row[3] == 150 or row[3] == 1200, true, "150 on a hunt monster, 1200 on a boss")
end

-- ------------------------------------------------------------------ the weapon audit counts them (every class 6+ from 700 up)
WEAPON_COVERAGE_NO_MAIN = true
local C = dofile("tools/weapon_coverage.lua")
local D = C.load(cfg)
local A = C.audit(cfg, D)
for _, row in ipairs(A.rows) do
	for i = 7, #cfg.bands do
		eq(row.cells[i].n >= 6, true, row.class .. " has 6 weapons in " .. cfg.bands[i][3] .. ", has " .. row.cells[i].n)
	end
end
print("weapons800_test: ok")
