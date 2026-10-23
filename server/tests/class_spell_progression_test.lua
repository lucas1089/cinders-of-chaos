-- Run from the server/ folder: luajit tests/class_spell_progression_test.lua (no engine needed; CI runs luajit and lua5.3)
-- C6 audit (owner 2026-10: "Juggernaut, level 520, still has the level 300 skills"): which spells does each ascended class
-- get over the base class, and up to which level? Reads data/spells/chaos/spells_chaos.xml and data/spells/stock_spells.csv.
-- State pinned here so it cannot drift unnoticed:
--   * every ascended class has at least one spell of its own and at most MAX_OWN (15);
--   * the stock cure (status cleansing) spells are gone, their ids carry the late spells (tools/retire_cure_spells.py):
--     Juggernaut Bastion Cry 340 and Anvil Fall 380 (460 until O141), Deadeye Twin Verdict 400, Berserker Rampage Leap 380, Beastmaster Pack
--     Frenzy 320 (380 until O141), Elementalist Glacial Doom 420, Ninja Shuriken Tempest 270 (360 until O141);
--   * not done (no free spell id left): Illusionist, Samurai, Lich, Bone Lord, Shadowfist, Iron Sage, Inquisitor, Sentinel have
--     nothing above 300 (Illusionist 280 since the 15-spell cap, Samurai 200, Shadowfist / Iron Sage / Inquisitor /
--     Sentinel 150). The 15-spell cap (2026-10-20, tools/patch_spell_cap.py) moved Elementalist and Illusionist rows:
--     the base Mystic kept fewer of their spells.
-- When a spell is added for a class, this test fails on the pinned row: update the row and server/README.md "Spell
-- progression audit".
local BASE_OF = {
	Juggernaut = "Warrior", Berserker = "Warrior", Deadeye = "Ranger", Beastmaster = "Ranger",
	Elementalist = "Mystic", Illusionist = "Mystic", Ninja = "Thief", Samurai = "Thief",
	Lich = "Necromancer", ["Bone Lord"] = "Necromancer", Shadowfist = "Monk", ["Iron Sage"] = "Monk",
	Inquisitor = "Templar", Sentinel = "Templar",
}
-- ascended class -> {spells of its own over its base class, highest level of any of its spells}
-- (counts and top levels include the attack kit, 2026-10-23)
local PINNED = {
	Juggernaut = {2, 380}, Berserker = {3, 380}, Deadeye = {2, 400}, Beastmaster = {4, 320}, Elementalist = {7, 420},
	Illusionist = {12, 280}, Ninja = {4, 270}, Samurai = {4, 230}, Lich = {3, 300}, ["Bone Lord"] = {4, 300},
	Shadowfist = {3, 250}, ["Iron Sage"] = {4, 190}, Inquisitor = {5, 200}, Sentinel = {6, 230},
}
local MAX_OWN = 15 -- owner 2026-10-20: an ascended class has at most 15 spells of its own
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end

local spells = {} -- vocation -> {name -> level}
local function add(voc, name, level)
	spells[voc] = spells[voc] or {}
	spells[voc][name] = level
end
local xml = io.open("data/spells/chaos/spells_chaos.xml"):read("*a"):gsub("<!%-%-.-%-%->", "")
for block in xml:gmatch("<instant.-</instant>") do
	local head = block:match("<instant([^>]*)>")
	local name, level = head:match('name="([^"]+)"'), tonumber(head:match('level="(%d+)"'))
	for voc in block:gmatch('<vocation name="([^"]+)"') do add(voc, name, level) end
end
local first = true
for line in io.lines("data/spells/stock_spells.csv") do
	if first then first = false else
		local f = {}
		for col in (line .. ","):gmatch("([^,]*),") do f[#f + 1] = col end
		-- id,name,words,group,level,mana,cooldown,groupcooldown,secondarygroup,secondarygroupcooldown,params,vocations
		local name, level, vocs = f[2], tonumber(f[5]), f[#f]
		for voc in vocs:gmatch("[^;]+") do add(voc, name, level) end
	end
end

for _, cure in ipairs({"Purge Venom", "Wash Taint", "Staunch Blood", "Douse Embers", "Ground Static", "Lift Hex", "Break Glamour"}) do
	for voc, list in pairs(spells) do
		if list[cure] then error(voc .. " still has the retired cure spell " .. cure) end
	end
end
for asc, base in pairs(BASE_OF) do
	local own, top = 0, 0
	for name, level in pairs(spells[asc] or {}) do
		if not (spells[base] or {})[name] then own = own + 1 end
		if level > top then top = level end
	end
	if own < 1 or own > MAX_OWN then error(asc .. ": " .. own .. " spells of its own (1.." .. MAX_OWN .. ")") end
	eq(own, PINNED[asc][1], asc .. ": spells over " .. base)
	eq(top, PINNED[asc][2], asc .. ": highest spell level")
end
-- the seven late spells: id of a retired cure spell, level 250-520, script on disk that starts with its description
local LATE = {
	{"Bastion Cry", 29, 340}, {"Anvil Fall", 58, 380}, {"Twin Verdict", 144, 400}, {"Rampage Leap", 145, 380},
	{"Glacial Doom", 146, 420}, {"Pack Frenzy", 147, 320}, {"Shuriken Tempest", 164, 270},
}
for _, e in ipairs(LATE) do
	local block = xml:match('<instant [^>]*name="' .. e[1] .. '"[^>]*>')
	eq(block ~= nil, true, e[1] .. " in spells_chaos.xml")
	eq(tonumber(block:match('spellid="(%d+)"')), e[2], e[1] .. " spell id")
	eq(tonumber(block:match('level="(%d+)"')), e[3], e[1] .. " level")
	eq(e[3] > 250 and e[3] <= 520, true, e[1] .. " between 250 and 520")
	local f = io.open("data/spells/" .. block:match('script="([^"]+)"'))
	eq(f ~= nil, true, e[1] .. " script file")
	eq(f:read("*l"):find("^%-%- " .. e[1] .. ":") ~= nil, true, e[1] .. " script starts with its description")
	f:close()
end
print("class_spell_progression_test: " .. checks .. " checks ok (every ascension has its own spells)")
