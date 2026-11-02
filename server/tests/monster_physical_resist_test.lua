-- Run from the server/ folder: luajit tests/monster_physical_resist_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Bug 2026-11-02: the Thief line could not hurt a Phantasm in the Infinity Tower. Its kit is physical and the base
-- Phantasm is immune to physical. Rule (tools/monster_physical_resist.py): no hunt monster is immune to physical, a
-- formerly immune one has a resistance of PHYSICAL_RESIST_PERCENT (30, as fire in C7). The base server's monsters are
-- fixed at install (tools/patch_base_monsters.py, step basemonsters). This test keeps our own monsters to the rule:
-- every attackable one that is not immune to every damage type but fire can take physical damage. The pets
-- (monsters/chaos/pets) are allies and never a target, they keep their immunity.
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

local mod = read("tools/monster_physical_resist.py")
local PCT = tonumber(mod:match("PHYSICAL_RESIST_PERCENT%s*=%s*(%d+)"))
eq(PCT, 30, "the resistance: 30 (damage taken 70%)")
eq(mod:find("import monster_physical_resist", 1, true), nil, "the module does not import itself")
eq(read("tools/patch_base_monsters.py"):find("import monster_physical_resist as phys", 1, true) ~= nil, true,
	"patch_base_monsters.py applies the rule")

-- the damage types of the "invulnerable by design" test (fire left out: C7 already removed every fire immunity)
local KINDS = {
	{xml = {"physical"}, pct = {"physicalPercent"}, lua = {"physical"}, const = "COMBAT_PHYSICALDAMAGE"},
	{xml = {"energy"}, pct = {"energyPercent"}, lua = {"energy"}, const = "COMBAT_ENERGYDAMAGE"},
	{xml = {"earth", "poison"}, pct = {"earthPercent", "poisonPercent"}, lua = {"earth", "poison"}, const = "COMBAT_EARTHDAMAGE"},
	{xml = {"ice"}, pct = {"icePercent"}, lua = {"ice"}, const = "COMBAT_ICEDAMAGE"},
	{xml = {"holy"}, pct = {"holyPercent"}, lua = {"holy"}, const = "COMBAT_HOLYDAMAGE"},
	{xml = {"death"}, pct = {"deathPercent"}, lua = {"death"}, const = "COMBAT_DEATHDAMAGE"},
}

local function xmlImmune(t, k)
	for _, n in ipairs(k.xml) do
		for tag in t:gmatch("<immunity%s[^>]*>") do
			if tag:find("%s" .. n .. '%s*=%s*"[1ty]') or tag:find('%sname%s*=%s*"' .. n .. '"') then return true end
		end
	end
	for _, p in ipairs(k.pct) do
		for v in t:gmatch(p .. '%s*=%s*"(%-?%d+)"') do
			if tonumber(v) >= 100 then return true end
		end
	end
	return false
end

local function luaImmune(t, k)
	for e in t:gmatch("%b{}") do
		local ty = e:match('type%s*=%s*"(%w+)"')
		for _, n in ipairs(k.lua) do
			if ty == n and e:find("combat%s*=%s*true") then return true end
		end
	end
	for v in t:gmatch(k.const .. "%s*,%s*percent%s*=%s*(%-?%d+)") do
		if tonumber(v) >= 100 then return true end
	end
	return false
end

local function leftAlone(t, immune, noAttack)
	if t:find(noAttack) then return true end
	for _, k in ipairs(KINDS) do
		if not immune(t, k) then return false end
	end
	return true
end

local xmls = list("find data/monster/monsters/chaos -name '*.xml' | sort")
local luas = list("find data/monster/lua/chaos -name '*.lua' | sort")
eq(#xmls > 100, true, "monster files found")
local scanned, invulnerable = 0, {}
for _, f in ipairs(xmls) do
	if not f:find("/pets/", 1, true) then
		scanned = scanned + 1
		local t = read(f):gsub("<!%-%-.-%-%->", "")
		if leftAlone(t, xmlImmune, '<flag%s+attackable%s*=%s*"[0fn]') then
			if xmlImmune(t, KINDS[1]) then invulnerable[#invulnerable + 1] = f:match("[^/]+$") end
		else
			eq(xmlImmune(t, KINDS[1]), false, f .. ": immune to physical")
		end
	end
end
for _, f in ipairs(luas) do
	scanned = scanned + 1
	local t = read(f):gsub("%-%-[^\n]*", "")
	if not leftAlone(t, luaImmune, "attackable%s*=%s*false") then
		eq(luaImmune(t, KINDS[1]), false, f .. ": immune to physical")
	end
end
-- Plant: the fire-only target (immune to every other damage type) stays as it is
eq(table.concat(invulnerable, ","), "plant.xml", "the only invulnerable-by-design monster of ours")
eq(read("data/monster/monsters/chaos/plant.xml"):find('<immunity physical="1"/>', 1, true) ~= nil, true, "plant kept")

print(("monster_physical_resist_test: ok (%d files, %d checks)"):format(scanned, checks))
