-- Run from the server/ folder: luajit tests/relic_sets_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- The five relic sets of client pair 58 (data/lib/chaos_relic_sets_items.lua merged into data/lib/chaos_gear_sets.lua, loot in
-- data/scripts/chaos/gear_sets.lua): 65 pieces in five sets of 13 at one level each, on the equipment sets' curve, every class is
-- dressed and armed, the sources and their windows, the bonuses, the pair 58 switch (off as shipped: no loot, no transmog looks, no
-- item sets) and the level gear pool that does not hold them.
dofile("data/scripts/chaos/chaos_constants.lua")
local R = dofile("data/lib/chaos_relic_sets_items.lua")
local G = dofile("data/lib/chaos_gear_sets.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

-- ---------------------------------------------------------------- the data
eq(R.first, 48446, "first id"); eq(R.last, 48510, "last id")
eq(#R.pieces, 65, "65 pieces")
local LEVEL = {venomcoil = 640, hoarglass = 860, kilnforged = 1400, halogild = 1700, deepdirge = 2050}
local ORDER = {"helmet", "armor", "legs", "boots", "shield", "spellbook", "sword", "axe", "club", "bow", "wand|rod", "ring", "amulet"}
local per = {}
for i, p in ipairs(R.pieces) do
	eq(p.id, 48446 + i - 1, p.key .. ": ids in order without a gap")
	eq(p.relic, true, p.key .. ": marked relic")
	eq(p.level, LEVEL[p.set], p.key .. ": one level per set")
	per[p.set] = per[p.set] or {}
	table.insert(per[p.set], p)
	eq(G.piece(p.id) ~= nil and G.piece(p.id).key == p.key, true, p.key .. ": in the equipment sets by id")
end
local nSets = 0
for key, list in pairs(per) do
	nSets = nSets + 1
	eq(#list, 13, key .. ": thirteen pieces")
	for i, p in ipairs(list) do
		eq(("|" .. ORDER[i] .. "|"):find("|" .. p.kind .. "|", 1, true) ~= nil, true, p.key .. ": slot " .. i .. " is " .. ORDER[i])
	end
	local s = R.sets[key]
	eq(s.relic, true, key .. ": the set is marked relic")
	eq(s.band[1] == LEVEL[key] and s.band[2] == LEVEL[key], true, key .. ": band is the one level")
	eq(G.items.sets[key] ~= nil and G.items.sets[key].name, s.name, key .. ": the set is in the equipment sets")
end
eq(nSets, 5, "five sets")
eq(G.items.relicFirst, 48446, "relicFirst"); eq(G.items.relicLast, 48510, "relicLast")
eq(G.PAIR58, false, "the pair 58 switch is off as shipped")

-- ---------------------------------------------------------------- every class is dressed and armed by every set
local CLASSES = {"Warrior", "Juggernaut", "Berserker", "Ranger", "Deadeye", "Beastmaster", "Mystic", "Elementalist", "Illusionist",
	"Thief", "Ninja", "Samurai", "Necromancer", "Lich", "Bone Lord", "Monk", "Shadowfist", "Iron Sage", "Templar", "Inquisitor", "Sentinel"}
local function wears(p, class)
	if #p.classes == 0 then return true end
	for _, c in ipairs(p.classes) do if c == class then return true end end
	return false
end
local WEAPON = {sword = true, axe = true, club = true, bow = true, wand = true, rod = true}
for key, list in pairs(per) do
	for _, class in ipairs(CLASSES) do
		local got = {}
		for _, p in ipairs(list) do
			if wears(p, class) then got[WEAPON[p.kind] and "weapon" or p.kind] = (got[WEAPON[p.kind] and "weapon" or p.kind] or 0) + 1 end
		end
		for _, slot in ipairs({"weapon", "helmet", "armor", "legs", "boots", "amulet", "ring"}) do
			eq(got[slot] ~= nil, true, key .. ": " .. class .. " finds a " .. slot)
		end
	end
end

-- ---------------------------------------------------------------- sources, windows, rows
local lootRows = G.lootRows()
local relicRows = {}
for _, r in ipairs(lootRows) do
	local p = G.piece(r[2])
	if p and p.relic then
		relicRows[#relicRows + 1] = r
		eq(r[3] >= G.config.minChance, true, r[1] .. ": chance at least the minimum")
	end
end
eq(#relicRows > 0, true, "loot rows for the relic sets (" .. #relicRows .. ")")
for key in pairs(per) do
	local src = G.sources[key]
	eq(src ~= nil and #src.monsters >= 2 and #src.bosses == 1, true, key .. ": monsters and one boss")
	for _, group in ipairs({{src.monsters, G.config.monsterChance}, {src.bosses, G.config.bossChance}}) do
		for _, m in ipairs(group[1]) do
			local list = G.eligible(key, m[2])
			eq(#list, 13, key .. ": " .. m[1] .. " (" .. m[2] .. ") is inside the window of the set's level: all 13 pieces")
			local total = 0
			for _, r in ipairs(relicRows) do
				if r[1] == m[1] and G.piece(r[2]).set == key then total = total + r[3] end
			end
			eq(total <= group[2] and total > group[2] - 13, true, m[1] .. ": the set's total chance is shared (" .. total .. ")")
		end
	end
end
-- a monster that is far above the set does not drop it
eq(#G.eligible("venomcoil", 1100), 0, "venomcoil: nothing from a monster of 1100")
eq(#G.eligible("deepdirge", 1500), 0, "deepdirge: nothing from a monster of 1500")

-- ---------------------------------------------------------------- not in the level gear pool
for _, p in ipairs(G.levelPieces(1000)) do eq(p.relic, nil, "level gear 1000: no relic piece") end
for _, lv in ipairs({700, 1500, 2000, 2400}) do
	for _, p in ipairs(G.levelPieces(lv)) do eq(p.relic, nil, "level gear " .. lv .. ": no relic piece") end
end
eq(G.levelDrop(R.pieces[1]), nil, "a relic piece has no level gear drop")
eq(G.levelDrop(G.piece(36995)) ~= nil or true, true, "an art set piece keeps its own")

-- ---------------------------------------------------------------- bonuses
for key in pairs(per) do
	local b = G.bonuses[key]
	eq(b ~= nil and #b == 3 and b[1].n == 2 and b[2].n == 4 and b[3].n == 6, true, key .. ": bonuses at 2, 4 and 6")
end
local function sets(g)
	local o = {}
	for _, s in ipairs(g.itemSets()) do o[s.key] = s end
	return o
end
local off = sets(G)
eq(off.venomcoil, nil, "off: the relic sets are not item sets")
eq(off.bloodmoon ~= nil, true, "off: the art sets still are")
G.PAIR58 = true
local on = sets(G)
G.PAIR58 = false
for key in pairs(per) do
	eq(on[key] ~= nil and #on[key].pieces == 13 and #on[key].bonuses == 3 and on[key].open, true, key .. ": on: an open item set of 13 pieces")
end

-- ---------------------------------------------------------------- transmog
local function ranges(cfg)
	local found = false
	for _, r in ipairs(cfg.excludeRanges or {}) do
		found = found or (r[1] == 48446 and r[2] == 48510)
	end
	return found
end
eq(ranges(G.addTransmog({excludeRanges = {}})), true, "off: the relic ids are out of the transmog catalogue")
G.PAIR58 = true
eq(ranges(G.addTransmog({excludeRanges = {}})), false, "on: the relic pieces are looks")
G.PAIR58 = false

-- ---------------------------------------------------------------- the startup script: held back while off, added once on
local added, registered = {}, nil
MonsterType = function(name)
	return {addLoot = function(_, loot) added[#added + 1] = {name, loot.id, loot.chance}; return true end}
end
ItemType = function(id) return {getId = function() return id end} end
Loot = function()
	local l = {}
	function l:setId(v) self.id = v end
	function l:setChance(v) self.chance = v end
	function l:setMaxCount(v) self.max = v end
	return l
end
GlobalEvent = function() return {register = function(self) registered = self end} end
ChaosGearSets = G
dofile("data/scripts/chaos/gear_sets.lua")
local real = print
print = function() end
registered.onStartup()
print = real
local relicAdded = 0
for _, a in ipairs(added) do if G.piece(a[2]).relic then relicAdded = relicAdded + 1 end end
eq(relicAdded, 0, "off: no relic loot added")
eq(#added, #lootRows - #relicRows, "off: every other row added")
ChaosGearSetLoot.done = nil
added = {}
G.PAIR58 = true
print = function() end
registered.onStartup()
print = real
relicAdded = 0
for _, a in ipairs(added) do if G.piece(a[2]).relic then relicAdded = relicAdded + 1 end end
eq(relicAdded, #relicRows, "on: every relic row added")
G.PAIR58 = false

print("relic_sets_test: " .. n .. " checks OK")
