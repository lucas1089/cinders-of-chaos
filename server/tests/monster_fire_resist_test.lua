-- Run from the server/ folder: luajit tests/monster_fire_resist_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- C7 (owner 2026-10): no monster is immune to fire any more, so Pyre Oath (Righteous Fire style: the player burns for a
-- share of the maximum health every second) never burns the player for nothing. Monsters that were immune to fire have a
-- fire resistance of FIRE_RESIST_PERCENT (30: they take 70% of the fire damage). The pets (monsters/chaos/pets) are
-- allies, never targets of the aura, and keep their immunity. Rules: tools/monster_fire_resist.py (chaos files by
-- tools/tune_monsters.py, the base server's by tools/patch_base_monsters.py).
local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function read(p)
	local f = assert(io.open(p, "rb"), p)
	local t = f:read("*a")
	f:close()
	return t
end
local function list(cmd)
	local out = {}
	local p = io.popen(cmd)
	for l in p:lines() do out[#out + 1] = l end
	p:close()
	return out
end

local mod = read("tools/monster_fire_resist.py")
local PCT = tonumber(mod:match("FIRE_RESIST_PERCENT%s*=%s*(%d+)"))
eq(PCT, 30, "the resistance: 30 (damage taken 70%)")

local xmls = list("find data/monster/monsters/chaos -name '*.xml' | sort")
local luas = list("find data/monster/lua/chaos -name '*.lua' | sort")
eq(#xmls > 100, true, "monster files found")
local scanned, resisted = 0, 0
for _, f in ipairs(xmls) do
	if not f:find("/pets/", 1, true) then
		scanned = scanned + 1
		local t = read(f):gsub("<!%-%-.-%-%->", "")
		for tag in t:gmatch("<immunity%s[^>]*>") do
			eq(tag:find('fire%s*=%s*"[1ty]'), nil, f .. ": still immune to fire: " .. tag)
		end
		for v in t:gmatch('firePercent%s*=%s*"(%-?%d+)"') do
			eq(tonumber(v) < 100, true, f .. ": firePercent " .. v .. " is an immunity")
		end
	end
end
for _, f in ipairs(luas) do
	scanned = scanned + 1
	local t = read(f):gsub("%-%-[^\n]*", "")
	eq(t:find('type%s*=%s*"fire"'), nil, f .. ": fire immunity")
	for v in t:gmatch("COMBAT_FIREDAMAGE%s*,%s*percent%s*=%s*(%-?%d+)") do
		eq(tonumber(v) < 100, true, f .. ": fire percent " .. v .. " is an immunity")
	end
end
-- the two chaos monsters that were immune now resist exactly PCT
local plant = read("data/monster/monsters/chaos/plant.xml")
eq(plant:match('firePercent="(%d+)"'), tostring(PCT), "plant.xml fire resistance")
local oee = read("data/monster/lua/chaos/overcharged_energy_elemental.lua")
eq(oee:match("COMBAT_FIREDAMAGE%s*,%s*percent%s*=%s*(%d+)"), tostring(PCT), "overcharged energy elemental fire resistance")
-- the pets keep the immunity (allies of the player)
eq(read("data/monster/monsters/chaos/pets/ash_cat.xml"):find('<immunity fire="1"', 1, true) ~= nil, true, "pets stay immune")
print("monster_fire_resist_test: " .. scanned .. " chaos monster files, " .. checks .. " checks ok")
