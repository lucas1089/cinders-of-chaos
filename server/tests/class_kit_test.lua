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

	-- wearing keeps the colours and the mount, puts both addons on
	eq(L.ADDONS, 3, "both addons")
	local cur = {lookType = 128, lookHead = 78, lookBody = 69, lookLegs = 58, lookFeet = 76, lookAddons = 0, lookMount = 5}
	local w = L.wearOutfit(cur, 24, L.FEMALE)
	eq(w.lookType, 2077, "inquisitor female"); eq(w.lookAddons, 3, "both addons worn"); eq(w.lookHead, 78, "colours kept")
	eq(w.lookMount, 5, "mount kept"); eq(cur.lookType, 128, "the given table is not changed")
	eq(L.wearOutfit({lookType = 2077, lookAddons = 3}, 24, L.FEMALE), nil, "already worn")
	eq(L.wearOutfit({lookType = 2077, lookAddons = 0}, 24, L.FEMALE).lookAddons, 3, "worn without addons: addons put on")
	eq(L.wearOutfit(cur, 0, L.MALE), nil, "no class look")

	-- logins: the class look is the default, a store outfit stays
	eq(L.loginOutfit(cur, 4, L.MALE, true, {}).lookType, 2073, "first login / class change: the class look")
	eq(L.loginOutfit(cur, 4, L.MALE, true, {}).lookAddons, 3, "with both addons")
	eq(L.loginOutfit(cur, 4, L.MALE, false, {[2073] = true}), nil, "a store outfit stays (addons given meanwhile)")
	eq(L.loginOutfit(nil, 4, L.MALE, true, {}), nil, "no outfit")
	-- an existing character wearing its class look: addons put on once, when they were just given
	local old = {lookType = 2073, lookHead = 1, lookAddons = 0}
	local up = L.loginOutfit(old, 4, L.MALE, false, {[2073] = true})
	eq(up.lookType, 2073, "same look"); eq(up.lookAddons, 3, "addons put on"); eq(up.lookHead, 1, "colours kept")
	eq(L.loginOutfit(old, 4, L.MALE, false, {}), nil, "addons owned before: the player's choice stays")
	eq(L.loginOutfit({lookType = 2073, lookAddons = 3}, 4, L.MALE, false, {[2073] = true}), nil, "already with addons")
	-- an ascended class wearing its base class's look gets that look's addons; another class's look is not touched
	eq(L.loginOutfit({lookType = 2051, lookAddons = 0}, 12, L.MALE, false, {[2051] = true}).lookAddons, 3, "base look")
	eq(L.loginOutfit({lookType = 2073, lookAddons = 0}, 11, L.MALE, false, {[2073] = true}), nil, "not this class's look")
	eq(L.isFirstLogin(0), true, "first login"); eq(L.isFirstLogin(1700000000), false, "later login")
end

-- ------------------------------------------------------------------ class looks: the pair 19 switch
-- Shipped on (things_custom19 on windows-assets since 2026-10-12). The off path (the rollback) is tested on a second
-- copy of the core with the switch line forced to false, loaded into a fresh environment.
local function loadIn(text, name, env)
	if setfenv then -- LuaJIT / Lua 5.1
		local f = assert(loadstring(text, name))
		setfenv(f, env)
		return f
	end
	return assert(load(text, name, "t", env))
end
do
	-- install_outfits.py and gen_shop_cosmetics.py read the switch as this exact line
	local src = io.open("data/scripts/chaos/class_looks_core.lua"):read("*a")
	eq(src:match("\nL%.PAIR19_LOOKS = (%a+)\n"), tostring(L.PAIR19_LOOKS), "the switch is one plain line")
	eq(L.PAIR19_LOOKS, true, "the switch is on: things_custom19 is on windows-assets")
	eq(L.pair19, true, "applied on")

	-- the off copy: same source, the switch line set to false, its own ChaosClassLooks (Chaos from the globals)
	local offSrc, nSub = src:gsub("\nL%.PAIR19_LOOKS = true\n", "\nL.PAIR19_LOOKS = false\n")
	eq(nSub, 1, "the switch line forced off")
	local env = setmetatable({ChaosClassLooks = false}, {__index = _G})
	local O = loadIn(offSrc, "=class_looks_core.lua (off)", env)()
	ok(O ~= L and env.ChaosClassLooks == O, "the off copy is a separate module")
	eq(ChaosClassLooks, L, "the shipped module stays the global one")

	-- off: no class look needs things_custom19, nothing replaced, nothing retired beyond the stock looks
	eq(O.PAIR19_LOOKS, false, "off copy: the switch is off"); eq(O.pair19, false, "off copy: applied off")
	local n18 = #O.retired
	for vocId, e in pairs(O.looks) do
		ok(e.male < 2143 and e.female < 2143, "class " .. vocId .. ": no things_custom19 look with the switch off")
	end
	eq(next(O.replaced), nil, "off: nothing replaced"); eq(next(O.former), nil, "off: nothing kept as (old)")
	eq(O.lookFor(8, O.MALE), 2039, "off: juggernaut on the things_custom18 look")
	eq(O.loginOutfit({lookType = 2161, lookAddons = 0}, 8, O.MALE, false, {}), nil, "switch off: nothing about 2161")
	eq(O.loginOutfit({lookType = 2039, lookAddons = 0}, 8, O.MALE, false, {}), nil, "off: the old look is the class look")
	-- the six new looks: 2161-2172, one class each, both sexes, a class with a look
	local ids, count = {}, 0
	for vocId, n in pairs(O.pair19Looks) do
		ok(O.looks[vocId], "class " .. vocId .. " has a look")
		ids[n.male] = true; ids[n.female] = true; count = count + 1
	end
	eq(count, 6, "six classes")
	for id = 2161, 2172 do ok(ids[id], "look " .. id .. " used") end
	-- the store, achievements and seasons never give them
	for _, f in ipairs({"shop_config.lua", "achievements_data.lua", "season_config.lua", "seasonpass_config.lua",
		"exclusives_config.lua"}) do
		local text = io.open("data/scripts/chaos/" .. f):read("*a")
		for n in text:gmatch("(%d+)") do
			ok(not ids[tonumber(n)] or tonumber(n) < 2161, f .. " names " .. n)
		end
	end

	-- on (the shipped module)
	eq(L.lookFor(8, L.MALE), 2161, "juggernaut male"); eq(L.lookFor(8, L.FEMALE), 2162, "juggernaut female")
	eq(L.lookFor(3, L.MALE), 2163, "ranger"); eq(L.lookFor(15, L.FEMALE), 2166, "beastmaster")
	eq(L.lookFor(22, L.MALE), 2167, "bone lord"); eq(L.lookFor(18, L.FEMALE), 2170, "shadowfist")
	eq(L.lookFor(25, L.MALE), 2171, "sentinel"); eq(L.lookFor(4, L.MALE), 2073, "warrior kept")
	eq(select(2, L.lookFor(8, L.MALE)), "Juggernaut Class", "name kept")
	eq(L.former[8].name, "Juggernaut Class (old)", "replaced look named"); eq(L.former[8].male, 2039, "replaced male")
	eq(L.former[4], nil, "kept class: nothing replaced")
	eq(#L.retired, n18 + 6, "the six replaced looks retired (never sold)")
	eq(L.replaced[2039], 2161, "old -> new"); eq(L.replaced[2041], 2172, "sentinel female old -> new")
	-- on and off differ only in the six classes; the replaced looks are the off copy's looks
	for vocId, e in pairs(O.looks) do
		local n = L.pair19Looks[vocId]
		if n then
			eq(L.looks[vocId].male, n.male, "on: class " .. vocId .. " male is the new look")
			eq(L.looks[vocId].female, n.female, "on: class " .. vocId .. " female is the new look")
			eq(L.former[vocId].male, e.male, "on: class " .. vocId .. " old male kept")
			eq(L.former[vocId].female, e.female, "on: class " .. vocId .. " old female kept")
			eq(L.former[vocId].name, e.name .. " (old)", "on: class " .. vocId .. " old name")
		else
			local k = L.looks[vocId]
			ok(k.male == e.male and k.female == e.female and k.name == e.name, "on: class " .. vocId .. " unchanged")
		end
	end
	-- the rules of the class looks hold with the new ids
	local seen, retired = {}, {}
	for _, e in ipairs(L.retired) do retired[e.male] = true; retired[e.female] = true end
	for vocId in pairs(cfg.baseOf) do
		local e = L.looks[vocId]
		ok(not seen[e.male], "on: male look of " .. vocId .. " not shared"); seen[e.male] = true
		ok(not seen[e.female] or e.female == e.male, "on: female look of " .. vocId .. " not shared"); seen[e.female] = true
		ok(not retired[e.male] and not retired[e.female], "on: class " .. vocId .. " uses a retired look")
	end
	local csv = io.open("../client/tools/outfit_art/class_looks_sources.csv")
	if csv then
		local listed = {}
		for line in csv:lines() do
			local look = line:match("^%d+,[^,]*,[^,]*,(%d+),")
			if look then listed[tonumber(look)] = true end
		end
		csv:close()
		for _, mod in ipairs({L, O}) do
			for vocId, e in pairs(mod.looks) do
				ok(listed[e.male] and listed[e.female], "class " .. vocId .. " looks listed in class_looks_sources.csv")
			end
		end
	end
	-- logins: a replaced look of the character's class becomes the new one, colours kept; a store outfit stays
	local o = L.loginOutfit({lookType = 2039, lookHead = 7, lookAddons = 0, lookMount = 2}, 8, L.MALE, false, {})
	eq(o.lookType, 2161, "juggernaut moved to the new look"); eq(o.lookAddons, 3, "with addons"); eq(o.lookHead, 7, "colours")
	eq(o.lookMount, 2, "mount")
	eq(L.loginOutfit({lookType = 2079, lookAddons = 0}, 7, L.FEMALE, false, {}).lookType, 2164, "deadeye in the old ranger look")
	eq(L.loginOutfit({lookType = 2039, lookAddons = 0}, 4, L.MALE, false, {}), nil, "a warrior in the old juggernaut look")
	eq(L.loginOutfit({lookType = 128, lookAddons = 3}, 8, L.MALE, false, {[2161] = true}), nil, "store outfit stays")
	eq(L.loginOutfit({lookType = 2161, lookAddons = 0}, 8, L.MALE, false, {[2161] = true}).lookAddons, 3, "new look: addons")
	eq(L.loginOutfit({lookType = 2161, lookAddons = 0}, 8, L.MALE, false, {}), nil, "on: the new look worn, addons owned before")
	eq(L.unlocksFor(15, L.MALE)[1], 2165, "beastmaster gets the new look"); eq(L.unlocksFor(15, L.MALE)[2], 2163, "and the ranger's")

	-- usePair19 toggles in place: off gives the off copy's state, on again the shipped one
	L.usePair19(false)
	eq(L.lookFor(8, L.MALE), 2039, "toggled off: juggernaut back"); eq(#L.retired, n18, "toggled off: retired back")
	eq(next(L.replaced), nil, "toggled off: nothing replaced")
	L.usePair19(true)
	eq(L.lookFor(8, L.MALE), 2161, "toggled on again"); eq(#L.retired, n18 + 6, "toggled on: retired again")
end

-- ------------------------------------------------------------------ class looks: the pair 20 switch
-- Shipped OFF until things_custom20 is on windows-assets. The on path is tested on a copy of the core with the
-- switch line forced to true (and one with both switches off), each in a fresh environment.
do
	local src = io.open("data/scripts/chaos/class_looks_core.lua"):read("*a")
	eq(src:match("\nL%.PAIR20_LOOKS = (%a+)\n"), tostring(L.PAIR20_LOOKS), "the pair 20 switch is one plain line")
	eq(L.PAIR20_LOOKS, false, "the pair 20 switch is off: things_custom20 is not on windows-assets yet")
	eq(L.pair20, false, "pair 20 applied off"); eq(L.pair19, true, "pair 19 still on")

	-- the twelve new looks: 2173-2184, six classes, both sexes, none a pair 19 class
	local ids, count = {}, 0
	for vocId, n in pairs(L.pair20Looks) do
		ok(cfg.baseOf[vocId], "pair 20: class " .. vocId .. " is a class")
		ok(not L.pair19Looks[vocId], "pair 20: class " .. vocId .. " is not a pair 19 class")
		ok(n.male ~= n.female, "pair 20: class " .. vocId .. " has a look per sex")
		ok(not ids[n.male] and not ids[n.female], "pair 20: class " .. vocId .. " looks used once")
		ids[n.male] = true; ids[n.female] = true; count = count + 1
	end
	eq(count, 6, "pair 20: six classes")
	for id = 2173, 2184 do ok(ids[id], "pair 20: look " .. id .. " used") end
	for _, f in ipairs({"shop_config.lua", "achievements_data.lua", "season_config.lua", "seasonpass_config.lua",
		"exclusives_config.lua"}) do
		local text = io.open("data/scripts/chaos/" .. f):read("*a")
		for _, pat in ipairs({"[Ll]ook[Tt]ype%s*=%s*(%d+)", "male%s*=%s*(%d+)", "[Ll]ook%s*=%s*(%d+)",
			"lookfemale%s*=%s*(%d+)", "outfit%s*=%s*(%d+)"}) do
			for n in text:gmatch(pat) do
				ok(not ids[tonumber(n)], f .. " gives pair 20 look " .. n)
			end
		end
	end

	-- off (shipped): no class look needs things_custom20; the six classes keep their looks
	for vocId, e in pairs(L.looks) do
		ok(e.male < 2173 and e.female < 2173, "pair 20 off: class " .. vocId .. " uses no things_custom20 look")
	end
	eq(L.lookFor(21, L.FEMALE), 2059, "off: lich female on the one look"); eq(L.lookFor(11, L.MALE), 2051, "off: thief")
	eq(L.loginOutfit({lookType = 2173, lookAddons = 0}, 21, L.MALE, false, {}), nil, "off: nothing about 2173")
	local n19 = #L.retired

	-- on: the core with the pair 20 switch line forced to true (pair 19 as shipped)
	local onSrc, nSub = src:gsub("\nL%.PAIR20_LOOKS = false\n", "\nL.PAIR20_LOOKS = true\n")
	eq(nSub, 1, "the pair 20 switch line forced on")
	local env = setmetatable({ChaosClassLooks = false}, {__index = _G})
	local P = loadIn(onSrc, "=class_looks_core.lua (pair 20 on)", env)()
	ok(P ~= L and env.ChaosClassLooks == P, "the pair 20 copy is a separate module")
	eq(ChaosClassLooks, L, "the shipped module stays the global one")
	eq(P.pair20, true, "on copy: applied on"); eq(P.pair19, true, "on copy: pair 19 on too")
	eq(P.lookFor(21, P.MALE), 2173, "lich male"); eq(P.lookFor(21, P.FEMALE), 2174, "lich female: a matched pair")
	eq(P.lookFor(24, P.MALE), 2181, "inquisitor male"); eq(P.lookFor(24, P.FEMALE), 2182, "inquisitor female")
	eq(P.lookFor(20, P.MALE), 2183, "necromancer male"); eq(P.lookFor(20, P.FEMALE), 2184, "necromancer female")
	eq(P.lookFor(11, P.FEMALE), 2176, "thief"); eq(P.lookFor(12, P.MALE), 2177, "ninja"); eq(P.lookFor(23, P.FEMALE), 2180, "templar")
	eq(P.lookFor(8, P.MALE), 2161, "pair 19 kept: juggernaut"); eq(P.lookFor(4, P.MALE), 2073, "warrior kept")
	eq(P.former[21].name, "Lich Class (old)", "old lich named"); eq(P.former[21].male, 2059, "old lich male")
	eq(P.former[21].female, 2059, "old lich: the one look"); eq(P.former[20].female, 2064, "old necromancer female")
	eq(#P.retired, n19 + 6, "the six replaced looks retired (never sold)")
	eq(P.replaced[2051], 2175, "old -> new"); eq(P.replaced[2059], 2173, "a one-look class: old -> the new male look")
	-- on and off differ only in the six classes
	for vocId, e in pairs(L.looks) do
		local n = P.pair20Looks[vocId]
		if n then
			local k = P.looks[vocId]
			ok(k.male == n.male and k.female == n.female and k.name == e.name, "pair 20 on: class " .. vocId .. " new looks")
			ok(P.former[vocId].male == e.male and P.former[vocId].female == e.female, "pair 20 on: class " .. vocId .. " old kept")
		else
			local k = P.looks[vocId]
			ok(k.male == e.male and k.female == e.female and k.name == e.name, "pair 20 on: class " .. vocId .. " unchanged")
		end
	end
	-- the rules of the class looks hold with the new ids
	local seen, retired = {}, {}
	for _, e in ipairs(P.retired) do retired[e.male] = true; retired[e.female] = true end
	for vocId in pairs(cfg.baseOf) do
		local e = P.looks[vocId]
		ok(not seen[e.male], "pair 20 on: male look of " .. vocId .. " not shared"); seen[e.male] = true
		ok(not seen[e.female] or e.female == e.male, "pair 20 on: female look of " .. vocId .. " not shared"); seen[e.female] = true
		ok(not retired[e.male] and not retired[e.female], "pair 20 on: class " .. vocId .. " uses a retired look")
		ok(e.male ~= e.female, "pair 20 on: class " .. vocId .. " has a look per sex")
	end
	local csv = io.open("../client/tools/outfit_art/class_looks_sources.csv")
	if csv then
		local listed = {}
		for line in csv:lines() do
			local look = line:match("^%d+,[^,]*,[^,]*,(%d+),")
			if look then listed[tonumber(look)] = true end
		end
		csv:close()
		for vocId, e in pairs(P.looks) do
			ok(listed[e.male] and listed[e.female], "pair 20 on: class " .. vocId .. " looks listed in class_looks_sources.csv")
		end
	end
	-- logins: a replaced look becomes the new look of the character's sex, colours and mount kept
	local o = P.loginOutfit({lookType = 2059, lookHead = 9, lookAddons = 3, lookMount = 4}, 21, P.FEMALE, false, {})
	eq(o.lookType, 2174, "a female lich in the one old look gets the female look"); eq(o.lookHead, 9, "colours")
	eq(o.lookMount, 4, "mount"); eq(o.lookAddons, 3, "with addons")
	eq(P.loginOutfit({lookType = 2059, lookAddons = 3}, 21, P.MALE, false, {}).lookType, 2173, "a male lich: the male look")
	eq(P.loginOutfit({lookType = 2077, lookAddons = 3}, 24, P.FEMALE, false, {}).lookType, 2182, "female inquisitor")
	eq(P.loginOutfit({lookType = 2064, lookAddons = 0}, 20, P.FEMALE, false, {}).lookType, 2184, "female necromancer")
	eq(P.loginOutfit({lookType = 2044, lookAddons = 0}, 21, P.MALE, false, {}).lookType, 2183,
		"a lich in the old necromancer look (its base class) gets the new necromancer look")
	eq(P.loginOutfit({lookType = 2051, lookAddons = 0}, 12, P.MALE, false, {}).lookType, 2175,
		"a ninja in the old thief look gets the new thief look")
	eq(P.loginOutfit({lookType = 2051, lookAddons = 0}, 4, P.MALE, false, {}), nil, "a warrior in the old thief look")
	eq(P.loginOutfit({lookType = 2039, lookAddons = 0}, 8, P.MALE, false, {}).lookType, 2161, "pair 19 still moves")
	eq(P.loginOutfit({lookType = 128, lookAddons = 3}, 23, P.MALE, false, {[2179] = true}), nil, "store outfit stays")
	eq(P.loginOutfit({lookType = 2179, lookAddons = 0}, 23, P.MALE, false, {[2179] = true}).lookAddons, 3, "new look: addons")
	eq(P.unlocksFor(21, P.FEMALE)[1], 2174, "lich gets the new look"); eq(P.unlocksFor(21, P.FEMALE)[2], 2184, "and the necromancer's")
	eq(P.replacedFor(2052, P.FEMALE), 2176, "replacedFor: thief female"); eq(P.replacedFor(128, P.MALE), nil, "replacedFor: not replaced")

	-- toggles: pair 20 alone, then both off; pair 19 untouched by usePair20
	P.usePair20(false)
	eq(P.lookFor(21, P.MALE), 2059, "toggled off: lich back"); eq(#P.retired, n19, "toggled off: retired back")
	eq(P.lookFor(8, P.MALE), 2161, "toggled pair 20 off: pair 19 stays")
	P.usePair19(false)
	for vocId, e in pairs(P.looks) do
		ok(e.male < 2143 and e.female < 2143, "both off: class " .. vocId .. " on a things_custom18 look")
	end
	P.applyPairs(true, true)
	eq(P.lookFor(21, P.FEMALE), 2174, "both on again"); eq(P.lookFor(25, P.MALE), 2171, "both on: sentinel")
	-- the shipped module toggles in place and back
	L.usePair20(true)
	eq(L.lookFor(12, L.FEMALE), 2178, "shipped toggled on"); eq(#L.retired, n19 + 6, "shipped toggled on: retired")
	L.usePair20(false)
	eq(L.lookFor(12, L.FEMALE), 2070, "shipped toggled back off"); eq(#L.retired, n19, "shipped back: retired")
	eq(next(L.replaced) ~= nil, true, "pair 19 replacements kept")
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
