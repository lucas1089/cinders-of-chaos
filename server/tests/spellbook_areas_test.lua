-- Run from the server/ folder: lua5.3 tests/spellbook_areas_test.lua (CI runs it with luajit and lua5.3).
-- Every Chaos attack spell of spells_chaos.xml, built by the Spellbook as the window gets it (O185): typed damage (an
-- "Utility" attack spell fell out of the Attack filter), and a spell the rotation model says hits a pack (t5 of
-- rotation_model.csv, 2 or more targets) carries an area and a target of "area" or "front", one that hits a single
-- target none. Owner report 2026-10-24: Shuriken Tempest read "Utility", "Single target", one tile.

local function disc(r)
	local m = {}
	for y = -r, r do
		local row = {}
		for x = -r, r do row[#row + 1] = (x == 0 and y == 0) and 3 or ((x * x + y * y <= r * r + r) and 1 or 0) end
		m[#m + 1] = row
	end
	return m
end
-- the engine's area tables the spell scripts name
AREA_WAVE4 = {{1, 1, 1, 1, 1}, {0, 1, 1, 1, 0}, {0, 1, 1, 1, 0}, {0, 0, 3, 0, 0}}
AREA_SQUARE1X1 = {{1, 1, 1}, {1, 3, 1}, {1, 1, 1}}
AREA_CIRCLE3X3 = {{0, 0, 1, 1, 1, 0, 0}, {0, 1, 1, 1, 1, 1, 0}, {1, 1, 1, 1, 1, 1, 1}, {1, 1, 1, 3, 1, 1, 1},
	{1, 1, 1, 1, 1, 1, 1}, {0, 1, 1, 1, 1, 1, 0}, {0, 0, 1, 1, 1, 0, 0}}
AREA_CIRCLE2X2, AREA_CIRCLE5X5, AREA_CIRCLE6X6 = disc(2), disc(5), disc(6)
AREA_BEAM7 = {{1}, {1}, {1}, {1}, {1}, {1}, {3}}
MESSAGE_STATUS_CONSOLE_BLUE = 4

function CreatureEvent() local o = {}; function o:register() end; function o:type() end; return o end
function TalkAction() local o = {}; function o:separator() end; function o:register() end; return o end
Vocation = setmetatable({}, {__call = function() end})
ItemType = setmetatable({}, {__call = function() return {getName = function() return "item" end, getClientId = function() return 1 end} end})
json = {encode = function() return "" end}

ChaosSpellbook = {spellsXml = "data/spells/chaos/spells_chaos.xml", scriptsDir = "data/spells/"}
dofile("data/scripts/chaos/chaos_constants.lua")
Chaos.send = function() end
Chaos.decode = function(b) return b end
dofile("data/scripts/chaos/spellbook.lua")
local B = ChaosSpellbook

local function read(path)
	local f = assert(io.open(path, "r"), path)
	local s = f:read("*a")
	f:close()
	return s
end

-- name -> t5 (targets of the 5-dummy pack the spell hits) of the rotation model
local t5 = {}
for line in read("data/spells/rotation_model.csv"):gmatch("[^\n]+") do
	local name, n = line:match('^[^,]*,([^,]*),"[^"]*",([%d%.]+),')
	if not name then name, n = line:match("^[^,]*,([^,]*),[^,\"]*,([%d%.]+),") end
	if name then t5[name] = tonumber(n) end
end

local problems, attack, areas = {}, 0, 0
for _, entry in ipairs(B.parseXml(read(B.spellsXml))) do
	local a = entry.attrs
	if a.group == "attack" and a.script and a.script:find("^chaos/") then
		attack = attack + 1
		local s = B.buildSpell(entry, {})
		local pack = t5[a.name]
		if s.type ~= "damage" then
			problems[#problems + 1] = a.name .. ": typed " .. tostring(s.type) .. ", an attack spell is damage"
		end
		if pack == nil then
			problems[#problems + 1] = a.name .. ": not in rotation_model.csv"
		elseif pack >= 2 then
			areas = areas + 1
			if not s.area or (s.target ~= "area" and s.target ~= "front") then
				problems[#problems + 1] = a.name .. ": hits " .. pack .. " targets of a pack but shows target " .. tostring(s.target) .. (s.area and "" or ", no area")
			elseif #s.area == 1 and #s.area[1] == 1 then
				problems[#problems + 1] = a.name .. ": the area is one tile"
			end
		elseif s.area or s.target == "area" or s.target == "front" then
			problems[#problems + 1] = a.name .. ": hits one target but shows target " .. tostring(s.target)
		end
	end
end
assert(attack >= 90, "read the attack spells of the Chaos XML: " .. attack)
assert(areas >= 30, "pack spells found: " .. areas)

-- the report spell: Shuriken Tempest, target + 8 more within 4 sqm of the target
for _, entry in ipairs(B.parseXml(read(B.spellsXml))) do
	if entry.attrs.name == "Shuriken Tempest" then
		local s = B.buildSpell(entry, {})
		assert(s.type == "damage" and s.target == "area" and s.center == "target", "Shuriken Tempest typed " .. s.type .. "/" .. s.target)
		assert(#s.area == 9 and #s.area[1] == 9, "radius 4 disc, 9 x 9")
		assert(s.area[5][5] == 3, "centre on the target")
	end
end

-- V18 (2026-11-26, seen in a client): an attack kit spell's script only calls AttackKit.cast, so the script text names no
-- element; the Spellbook read "Element -" for Phantom Needles, Mirror Shards, Dreamrot and Crimson Covenant. The kit row's
-- ctype is the element now (as client/tools/gen_spell_data.py reads it for spelldata.lua), and its hit factors give the
-- "Scales" row, which was empty for the same spells.
local kitChecked = 0
for _, entry in ipairs(B.parseXml(read(B.spellsXml))) do
	local a = entry.attrs
	if a.group == "attack" and a.script and a.script:find("^chaos/") then
		local s = B.buildSpell(entry, {})
		local kit = B.kitSpec(a.name)
		if kit and kit.ctype then
			kitChecked = kitChecked + 1
			if s.element ~= kit.ctype then
				problems[#problems + 1] = a.name .. ": element " .. tostring(s.element) .. ", the attack kit says " .. kit.ctype
			end
			-- the same for the "Scales" row: every kit hit reads magic level or a skill, the Spellbook must say which
			if not s.scaling then
				problems[#problems + 1] = a.name .. ": no scaling text, the attack kit hit scales"
			elseif (tonumber(kit.mMax) or 0) > 0 and not s.scaling:find("magic level") then
				problems[#problems + 1] = a.name .. ": scaling " .. s.scaling .. ", the kit hit reads magic level"
			elseif (tonumber(kit.pMax) or 0) > 0 and not s.scaling:find("skill") then
				problems[#problems + 1] = a.name .. ": scaling " .. s.scaling .. ", the kit hit reads a skill"
			end
		end
	end
end
assert(kitChecked >= 40, "attack kit spells checked: " .. kitChecked)
for _, entry in ipairs(B.parseXml(read(B.spellsXml))) do
	if entry.attrs.name == "Mirror Shards" then
		local s = B.buildSpell(entry, {})
		assert(s.element == "ice", "Mirror Shards is an ice spell")
		assert(s.scaling == "magic level", "Mirror Shards scales with magic level: " .. tostring(s.scaling))
	end
end
-- Bewitching Hex reads the caster in its own lines after O468 (patch_stock_spell_inputs.py), no callback token; the
-- installed text, as the patch writes it, must read as magic level too
local hexText = "local caster = creature:getPlayer()\n" ..
	"local baseDamage = caster and math.floor(caster:getLevel() / 5 + caster:getMagicLevel() * 2 + 44.5) or 128\n" ..
	"combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_DEATHDAMAGE)\n"
assert(B.analyzeScript(hexText).scaling == "magic level", "Bewitching Hex text: " .. tostring(B.analyzeScript(hexText).scaling))
assert(B.analyzeScript("combat:setParameter(COMBAT_PARAM_TYPE, COMBAT_FIREDAMAGE)\n").scaling == nil, "no input, no text")

if #problems > 0 then
	error(#problems .. " spells wrong:\n  " .. table.concat(problems, "\n  "), 0)
end
print("spellbook_areas_test: ok (" .. attack .. " attack spells, " .. areas .. " with an area, " .. kitChecked .. " kit elements)")
