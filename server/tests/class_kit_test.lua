-- Run from the server/ folder: luajit tests/class_kit_test.lua (no engine needed; CI runs it with luajit and lua5.3)
-- Covers the class kit pass (docs/CLASSES.md "Phase 2b"): the Thief line's Shadow Mend (formula, spell entry), the class
-- looks (class_looks_core.lua) and the test kit's classes (admin/testkit.lua, with a stubbed engine).
WEAPON_SWORD, WEAPON_CLUB, WEAPON_DISTANCE = 1, 2, 5
SLOTP_TWO_HAND = 2048

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/classes.lua")
local C = ChaosClasses
local cfg = Chaos.classes

local checks = 0
local function eq(a, b, m)
	checks = checks + 1
	if a ~= b then error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end
end
local function ok(v, m) eq(not not v, true, m) end

-- ------------------------------------------------------------------ Shadow Mend
do
	local h = cfg.shadowMend
	-- level 300, magic level 30, 4426 health (the Thief's numbers in server/data/spells/README.md)
	local avg = 300 * h.perLevel + 30 * h.perMagicLevel + 4426 * h.maxHealthShare
	local mn, mx = C.shadowMendRange(4426, 300, 30, false)
	eq(mn, math.floor(avg * 0.9), "min at level 300"); eq(mx, math.floor(avg * 1.1), "max at level 300")
	local vmn, vmx = C.shadowMendRange(4426, 300, 30, true)
	eq(vmn, math.floor(avg * h.veiledMultiplier * 0.9), "veiled min"); eq(vmx, math.floor(avg * h.veiledMultiplier * 1.1), "veiled max")
	ok(vmx > mx, "the veil makes it stronger")
	local l1, h1 = C.shadowMendRange(14506, 1000, 40, false)
	ok(l1 > mn * 2, "grows with level")
	eq(C.shadowMendRange(0, 0, 0, false), 0, "nothing from nothing")
	-- under the Illusionist's self heal per second (1538 / 2317 measured, x1.2 intelligence, every 2 s)
	ok((mn + mx) / 2 * 1.2 / 2 < 1538, "level 300 below the Illusionist")
	ok((l1 + h1) / 2 * 1.2 / 2 < 2317, "level 1000 below the Illusionist")

	-- the spell entry: id 98, healing group, the three classes of the line
	local xml = io.open("data/spells/chaos/spells_chaos.xml"):read("*a")
	local block = xml:match('<instant [^>]*name="Shadow Mend"[^>]*>.-</instant>')
	ok(block, "Shadow Mend in spells_chaos.xml")
	eq(block:match('spellid="(%d+)"'), "98", "spell id"); eq(block:match('words="([^"]+)"'), "saen umh", "words")
	eq(block:match('group="(%a+)"'), "healing", "healing group")
	eq(block:match('script="([^"]+)"'), "chaos/thief/shadow_mend.lua", "script")
	for _, v in ipairs({"Thief", "Ninja", "Samurai"}) do
		ok(block:find('<vocation name="' .. v .. '" />', 1, true), "for the " .. v)
	end
	local n = 0
	for id in xml:gmatch('spellid="(%d+)"') do
		if id == "98" then n = n + 1 end
	end
	eq(n, 1, "id 98 used once")
	ok(io.open("data/spells/chaos/thief/shadow_mend.lua"), "script file")
end

-- ------------------------------------------------------------------ class looks
dofile("data/scripts/chaos/class_looks_core.lua")
local L = ChaosClassLooks
do
	-- every class id has a look; a class's look differs from the other classes' looks
	local seen = {}
	for vocId in pairs(cfg.baseOf) do
		local e = L.looks[vocId]
		ok(e, "look for vocation " .. vocId)
		ok(e.male and e.female and e.name, "both sexes and a name for " .. vocId)
		ok(not seen[e.male], "male look of " .. vocId .. " not shared"); seen[e.male] = true
		ok(not seen[e.female] or e.female == e.male, "female look of " .. vocId .. " not shared"); seen[e.female] = true
	end
	for vocId in pairs(L.looks) do
		ok(cfg.baseOf[vocId], "look only for class ids (" .. vocId .. ")")
	end
	-- none of the looks the store, the achievements or the seasons sell or give
	local rewards = {}
	for _, f in ipairs({"shop_config.lua", "achievements_data.lua", "season_config.lua"}) do
		local text = io.open("data/scripts/chaos/" .. f):read("*a")
		for n in text:gmatch("male%s*=%s*(%d+)") do rewards[tonumber(n)] = f end
		for n in text:gmatch("looktype%s*=%s*(%d+)") do rewards[tonumber(n)] = f end
		for n in text:gmatch("lookfemale%s*=%s*(%d+)") do rewards[tonumber(n)] = f end
	end
	for vocId, e in pairs(L.looks) do
		ok(not rewards[e.male], "male look of " .. vocId .. " is a reward in " .. tostring(rewards[e.male]))
		ok(not rewards[e.female], "female look of " .. vocId .. " is a reward in " .. tostring(rewards[e.female]))
	end
	-- not the donor art class outfits either
	for _, list in pairs(cfg.outfits) do
		for _, o in ipairs(list) do
			for _, e in pairs(L.looks) do
				ok(e.male ~= o.lookType and e.female ~= o.lookType, "stock look, not " .. o.name)
			end
		end
	end

	eq(L.lookFor(4, L.MALE), 2073, "warrior male"); eq(L.lookFor(4, L.FEMALE), 2074, "warrior female")
	eq(select(2, L.lookFor(15, L.MALE)), "Beastmaster Class", "name")
	-- the new looks are the class looks' own: never a former class look, and the names are unique
	local retired, names = {}, {}
	for _, e in ipairs(L.retired) do retired[e.male] = true; retired[e.female] = true end
	for vocId, e in pairs(L.looks) do
		ok(not retired[e.male] and not retired[e.female], "class " .. vocId .. " uses a former class look")
		ok(not names[e.name], "name " .. e.name .. " used once"); names[e.name] = true
	end
	-- no stock art of the client pair: every class look is an imported look type (2039 and up)
	for vocId, e in pairs(L.looks) do
		ok(e.male >= 2039 and e.female >= 2039, "class " .. vocId .. " uses an imported look")
	end
	-- the sources CSV lists every look (licence tracing)
	local csv = io.open("../client/tools/outfit_art/class_looks_sources.csv")
	if csv then
		local listed = {}
		for line in csv:lines() do
			local look = line:match("^%d+,[^,]*,[^,]*,(%d+),")
			if look then listed[tonumber(look)] = true end
		end
		csv:close()
		for vocId, e in pairs(L.looks) do
			ok(listed[e.male] and listed[e.female], "class " .. vocId .. " looks listed in class_looks_sources.csv")
		end
	end
	eq(L.lookFor(0, L.MALE), nil, "vocation 0"); eq(L.lookFor(2, L.MALE), nil, "retired id")
	-- an ascended class gets its look and its base class's
	local u = L.unlocksFor(12, L.MALE)
	eq(#u, 2, "ninja: two looks"); eq(u[1], L.looks[12].male, "own first"); eq(u[2], L.looks[11].male, "then the thief's")
	eq(#L.unlocksFor(11, L.FEMALE), 1, "a base class: its own")
	eq(L.unlocksFor(11, L.FEMALE)[1], L.looks[11].female, "female look")
	eq(#L.unlocksFor(0, L.MALE), 0, "nothing for vocation 0")

	-- wearing keeps the colours and the mount, drops the addons
	local cur = {lookType = 128, lookHead = 78, lookBody = 69, lookLegs = 58, lookFeet = 76, lookAddons = 3, lookMount = 5}
	local w = L.wearOutfit(cur, 24, L.FEMALE)
	eq(w.lookType, 2077, "inquisitor female"); eq(w.lookAddons, 0, "no addons"); eq(w.lookHead, 78, "colours kept")
	eq(w.lookMount, 5, "mount kept"); eq(cur.lookType, 128, "the given table is not changed")
	eq(L.wearOutfit({lookType = 2077, lookAddons = 0}, 24, L.FEMALE), nil, "already worn")
	eq(L.wearOutfit(cur, 0, L.MALE), nil, "no class look")
	eq(L.isFirstLogin(0), true, "first login"); eq(L.isFirstLogin(1700000000), false, "later login")
end

-- ------------------------------------------------------------------ test kit (stubbed engine)
do
	CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_BACKPACK, CONST_SLOT_ARMOR, CONST_SLOT_RIGHT, CONST_SLOT_LEFT,
		CONST_SLOT_LEGS, CONST_SLOT_FEET, CONST_SLOT_RING, CONST_SLOT_AMMO = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
	SKILL_FIST, SKILL_CLUB, SKILL_SWORD, SKILL_AXE, SKILL_DISTANCE, SKILL_SHIELD = 0, 1, 2, 3, 4, 5
	local stub = setmetatable({}, {__index = function() return function() end end})
	TalkAction = function() return stub end
	dofile("data/scripts/chaos/admin/testkit.lua")
	local K = ChaosTestKit
	for vocId in pairs(cfg.baseOf) do
		local kind = K.kindFor(vocId)
		ok(K.kits[kind], "test kit for vocation " .. vocId)
	end
	eq(K.kindFor(14), "berserker", "berserker"); eq(K.kindFor(15), "beastmaster", "beastmaster")
	eq(K.kindFor(11), "thief", "thief"); eq(K.kindFor(12), "ninja", "ninja"); eq(K.kindFor(13), "thief", "samurai")
	eq(K.kindFor(18), "monk", "shadowfist"); eq(K.kindFor(22), "necromancer", "bone lord"); eq(K.kindFor(25), "templar", "sentinel")
	eq(K.kindFor(99), "mage", "unknown vocation")
	local b = K.kits.berserker
	eq(b.slots[CONST_SLOT_RIGHT], nil, "berserker: no shield"); eq(b.slots[CONST_SLOT_LEFT], 2440, "two-handed axe")
	eq(K.kits.knight.slots[CONST_SLOT_RIGHT], 10318, "the knight kit keeps its shield")
	eq(K.kits.beastmaster.quiver.id, 28050, "beastmaster quiver"); eq(K.kits.paladin.quiver.id, 29566, "paladin quiver")
	eq(K.kits.beastmaster.ammo, nil, "no arrows"); eq(K.kits.paladin.ammo, nil, "no bolts")
	eq(K.kits.ninja.slots[CONST_SLOT_RIGHT], 11395, "ninja off-hand"); eq(K.kits.thief.slots[CONST_SLOT_RIGHT], nil, "thief: none")
	eq(K.kits.thief.quiver, false, "thief: no quiver"); eq(K.kits.thief.extra[1].id, 7368, "assassin stars")
	eq(K.kits.monk.slots[CONST_SLOT_LEFT], nil, "monk: unarmed"); eq(K.kits.monk.skills[SKILL_FIST], 120, "fist")
	eq(K.kits.necromancer.druidWeapon, false, "necromancer keeps the wand")
	eq(K.kits.templar.slots[CONST_SLOT_RIGHT], 10318, "templar shield"); eq(K.kits.templar.magic, 25, "templar magic level")
end

print("class_kit_test: OK (" .. checks .. " checks)")
