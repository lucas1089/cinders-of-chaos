-- Run from the server/ folder: luajit tests/gear_sets_test.lua (and lua5.3; CI runs both)
-- The equipment sets of client pair 28 (data/lib/chaos_gear_sets.lua, chaos_gear_sets_items.lua, scripts/chaos/
-- gear_sets.lua): the switch is off; the generated pieces match the manifest; every set dresses and arms every class
-- inside its level band with levels that only go up along a track; the loot rows (sources, window, chances) and the
-- monsters they name; the transmog catalogue off and on; the startup script on mocks (nothing while off, the rows on).

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local M = dofile("data/lib/chaos_gear_sets.lua")
eq(M.PAIR28, true, "the pair 28 switch is on as shipped (pair 28 is live)")
local P = M.items

-- ---------------------------------------------------------------- pieces against the manifest
local rows = {}
local f = assert(io.open("data/items/gear_sets.csv", "r"))
local header = true
for line in f:lines() do
	if header then
		header = false
	else
		local cid, sid, key, kind = line:match("^(%d+),(%d+),([%w_]+),(%a+),")
		rows[#rows + 1] = {cid = tonumber(cid), sid = tonumber(sid), key = key, kind = kind}
	end
end
f:close()
eq(#rows, 448, "448 pieces in the manifest")
eq(#P.pieces, 448, "448 pieces in chaos_gear_sets_items.lua")
eq(P.first, 36995, "first server id")
eq(P.last, 37442, "last server id")
for i, r in ipairs(rows) do
	local p = P.pieces[i]
	eq(r.sid, r.cid + 3000, r.key .. ": server id = client id + 3000")
	eq(r.sid, 36995 + i - 1, r.key .. ": ids in order without a gap")
	eq(p.id == r.sid and p.key == r.key and p.kind == r.kind, true, r.key .. ": the generated piece")
	eq(M.piece(r.sid), p, r.key .. ": piece by id")
end

-- ---------------------------------------------------------------- every set dresses and arms every class
local CLASSES = {"Warrior", "Juggernaut", "Berserker", "Ranger", "Deadeye", "Beastmaster", "Mystic", "Elementalist",
	"Illusionist", "Thief", "Ninja", "Samurai", "Necromancer", "Lich", "Bone Lord", "Monk", "Shadowfist", "Iron Sage",
	"Templar", "Inquisitor", "Sentinel"}
local WEAPON = {sword = true, axe = true, club = true, bow = true, crossbow = true, wand = true, rod = true}
local function wears(p, class)
	if #p.classes == 0 then
		return true
	end
	for _, c in ipairs(p.classes) do
		if c == class then
			return true
		end
	end
	return false
end
local nSets = 0
for key, s in pairs(P.sets) do
	nSets = nSets + 1
	local has = {}
	local lastOfTrack = {}
	for _, p in ipairs(P.pieces) do
		if p.set == key then
			eq(p.level >= s.band[1] and p.level <= s.band[2], true, p.key .. ": level inside the band")
			local tr = p.kind .. "/" .. p.fit
			eq((lastOfTrack[tr] or 0) <= p.level, true, p.key .. ": levels only go up along a track")
			lastOfTrack[tr] = p.level
			has[p.kind] = true
			if p.kind == "helmet" or p.kind == "armor" or p.kind == "legs" or p.kind == "boots" then
				eq((p.stats.armor or 0) > 0, true, p.key .. ": armour")
			elseif p.kind == "wand" or p.kind == "rod" then
				eq(p.stats.wandMin > 0 and p.stats.wandMin < p.stats.wandMax and p.stats.mana > 0, true, p.key .. ": wand")
			elseif WEAPON[p.kind] then
				eq(p.stats.attack > 0, true, p.key .. ": attack")
			end
		end
	end
	for _, class in ipairs(CLASSES) do
		local got = {}
		for _, p in ipairs(P.pieces) do
			if p.set == key and wears(p, class) then
				got[WEAPON[p.kind] and "weapon" or p.kind] = true
			end
		end
		for _, slot in ipairs({"weapon", "helmet", "armor", "amulet", "ring"}) do
			eq(got[slot], true, key .. ": " .. class .. " finds a " .. slot)
		end
		eq(not has.legs or got.legs, true, key .. ": " .. class .. " finds legs")
		eq(not has.boots or got.boots, true, key .. ": " .. class .. " finds boots")
	end
end
eq(nSets, 7, "seven sets")
eq(P.sets.blightfang.band[1], 8, "the first set starts at level 8 (noob friendly)")
eq(P.sets.gildcrown.band[2], 2000, "the last set reaches level 2000")

-- ---------------------------------------------------------------- loot rows
local known = {}
local pool = assert(io.open("data/scripts/chaos/bounty_pool.lua", "r")):read("*a")
for name in pool:gmatch('name = "([^"]+)"') do
	known[name] = true
end
local p = io.popen("find data/monster/monsters/chaos -name '*.xml' 2>/dev/null")
for path in p:lines() do
	local text = assert(io.open(path, "r")):read("*a")
	local name = text:match('<monster name="([^"]+)"')
	if name then
		known[name] = true
	end
end
p:close()
local lootRows = M.lootRows()
local perMonster = {}
for _, r in ipairs(lootRows) do
	perMonster[r[1]] = perMonster[r[1]] or {total = 0, n = 0}
	perMonster[r[1]].total = perMonster[r[1]].total + r[3]
	perMonster[r[1]].n = perMonster[r[1]].n + 1
	eq(r[3] >= M.config.minChance, true, r[1] .. ": chance at least the minimum")
	eq(M.piece(r[2]) ~= nil, true, r[1] .. ": the row names a piece")
end
for key, src in pairs(M.sources) do
	eq(P.sets[key] ~= nil, true, key .. ": a source of a real set")
	for _, group in ipairs({{src.monsters, M.config.monsterChance}, {src.bosses, M.config.bossChance}}) do
		for _, m in ipairs(group[1]) do
			eq(known[m[1]], true, m[1] .. ": a monster of the installed server (bounty pool or a chaos file)")
			local pm = perMonster[m[1]]
			eq(pm ~= nil, true, m[1] .. ": has loot rows")
			local cap = math.max(group[2], M.config.minChance * pm.n)
			eq(pm.total <= cap and pm.total > group[2] - pm.n, true, m[1] .. ": the total chance is shared")
			for _, piece in ipairs(M.eligible(key, m[2])) do
				eq(piece.set, key, m[1] .. ": only pieces of its set")
				eq(piece.level <= m[2] + M.config.window.above and piece.level >= m[2] - M.config.window.below, true,
					m[1] .. ": pieces near its level")
			end
		end
	end
end
eq(#M.eligible("gildcrown", 100), 0, "no piece far below a set's band")

-- ---------------------------------------------------------------- transmog catalogue
local shipped = dofile("data/scripts/chaos/transmog_config.lua")
local found = false
for _, r in ipairs(shipped.excludeRanges) do
	found = found or (r[1] == 36995 and r[2] == 37442)
end
eq(found, false, "shipped (on): the pieces are in the transmog catalogue")
M.PAIR28 = false
eq(#M.addTransmog({excludeRanges = {}}).excludeRanges, 1, "off: the pieces are out of the catalogue")
M.PAIR28 = true
local c = M.addTransmog({excludeRanges = {}})
eq(#c.excludeRanges, 0, "on: nothing excluded")

-- ---------------------------------------------------------------- the startup script on mocks
local added = {}
local registered
MonsterType = function(name)
	if name == "Fennra" then
		return nil
	end
	return {addLoot = function(_, loot)
		added[#added + 1] = {name, loot.id, loot.chance}
		return true
	end}
end
ItemType = function(id)
	return {getId = function() return id end}
end
Loot = function()
	local l = {}
	function l:setId(v) self.id = v end
	function l:setChance(v) self.chance = v end
	function l:setMaxCount(v) self.max = v end
	return l
end
GlobalEvent = function()
	return {register = function(self) registered = self end}
end
ChaosGearSets = M
M.PAIR28 = false
dofile("data/scripts/chaos/gear_sets.lua")
eq(registered ~= nil, true, "a startup event")
registered.onStartup()
eq(#added, 0, "off: no loot added")
M.PAIR28 = true
local real = print
print = function() end
registered.onStartup()
print = real
local skipped = 0
for _, r in ipairs(lootRows) do
	if r[1] == "Fennra" then
		skipped = skipped + 1
	end
end
eq(#added, #lootRows - skipped, "on: every row added, a missing monster skipped")
eq(added[1][3] >= M.config.minChance, true, "rows carry their chance")
local again = #added
print = function() end
registered.onStartup()
print = real
eq(#added, again, "added once per run")

print("gear_sets_test: " .. n .. " checks OK")
