-- Run from the server/ folder: luajit tests/waystone_layouts_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- Every waystone layout (the 12 maps of waystone_tiers_config.lua) has an audit row and a sane rectangle; the clearPath
-- items lie inside their maps; a retired map leaves the options of its band (K.isRetired) and a band keeps two maps. The
-- walk itself (arrival -> lever -> boss room, spawns) needs the base map: tools/audit_waystone_maps.py (unit test:
-- tools/audit_waystone_maps_test.py).
local checks, fails = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. tostring(what))
	end
end

dofile("data/scripts/chaos/waystone_tiers_core.lua")
local K = ChaosWaystoneTiersCore
local cfg = dofile("data/scripts/chaos/waystone_tiers_config.lua")

ok(#cfg.maps == 12, "12 maps")
ok(#cfg.layouts == #cfg.maps, "one audit row per map")
local perBase = {}
for i, m in ipairs(cfg.maps) do
	local row = cfg.layouts[i]
	ok(row and row.map == i, "layout row " .. i .. " is map " .. i)
	ok(row and (row.status == "ok" or row.status == "retired"), "map " .. i .. ": status ok or retired")
	ok(row and row.name and row.name ~= "", "map " .. i .. ": a name")
	ok(m.to.x > m.from.x and m.to.y > m.from.y and m.from.z == m.to.z, "map " .. i .. ": a proper rectangle")
	ok(m.to.x - m.from.x >= 150 and m.to.y - m.from.y >= 100, "map " .. i .. ": a map of a size to hunt in")
	ok(m.tier >= 1 and m.tier <= 6, "map " .. i .. ": base tier")
	local isRet = K.isRetired(cfg, m.from)
	ok((row.status == "retired") == isRet, "map " .. i .. ": retired status and the retired list agree")
	if not isRet then
		perBase[m.tier] = (perBase[m.tier] or 0) + 1
	end
	for j = i + 1, #cfg.maps do
		local o = cfg.maps[j]
		local apart = m.to.x < o.from.x or o.to.x < m.from.x or m.to.y < o.from.y or o.to.y < m.from.y or m.from.z ~= o.from.z
		ok(apart, "maps " .. i .. " and " .. j .. " do not overlap")
	end
end
for tier = 1, 6 do
	ok((perBase[tier] or 0) >= 1, "base tier " .. tier .. " keeps a map")
end
for bi, b in ipairs(cfg.bands) do
	local n = 0
	for _, bt in ipairs(b.maps) do
		n = n + (perBase[bt] or 0)
	end
	ok(n >= 2, "band " .. bi .. " keeps at least two maps (" .. n .. ")")
end
-- the clearPath items are inside a map each and not twice
local seen = {}
for _, c in ipairs(cfg.clearPath) do
	local inside = false
	for _, m in ipairs(cfg.maps) do
		if c.x >= m.from.x and c.x <= m.to.x and c.y >= m.from.y and c.y <= m.to.y and c.z == m.from.z then
			inside = true
		end
	end
	ok(inside, "clearPath " .. c.x .. "," .. c.y .. " is inside a map")
	local key = c.x .. "," .. c.y .. "," .. c.z .. ":" .. c.item
	ok(not seen[key], "clearPath entry twice: " .. key)
	seen[key] = true
end
local needs = 0
for _, row in ipairs(cfg.layouts) do
	if row.needs == "clearPath" then
		needs = needs + 1
	end
end
ok(needs == 2 and #cfg.clearPath >= 2, "the two maps that need clearPath have entries")
-- retiring works
local copy = setmetatable({retired = {{x = cfg.maps[7].from.x, y = cfg.maps[7].from.y, z = cfg.maps[7].from.z}}}, {__index = cfg})
ok(K.isRetired(copy, cfg.maps[7].from) and not K.isRetired(copy, cfg.maps[8].from), "a retired map is recognised")
ok(not K.isRetired(cfg, nil), "no position: not retired")

print(string.format("waystone_layouts_test: %d checks, %d failures", checks, fails))
os.exit(fails == 0 and 0 or 1)
