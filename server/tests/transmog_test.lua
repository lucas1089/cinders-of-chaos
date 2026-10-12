-- Run from the server/ folder: luajit tests/transmog_test.lua (and lua5.3; CI runs both)
-- Transmog (transmog_core.lua) with the real transmog_config.lua, shop_config.lua and achievements_data.lua: the
-- shipped config and its sets, item kinds, which items unlock a look, ownership and collection progress, the fee,
-- apply / remove refusals, sets from achievements and the season pass, the store unlock names, the SQL and requests,
-- the opcode and attribute key in chaos_constants.lua, the engine and client patches, and that no set look is dropped,
-- sold or given anywhere else in the repo.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/transmog_core.lua")
local K = ChaosTransmogCore
local cfg = dofile("data/scripts/chaos/transmog_config.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")
local achievements = dofile("data/scripts/chaos/achievements_data.lua")

local n = 0
local function eq(a, b, m)
	n = n + 1
	if a ~= b then
		error((m or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2)
	end
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

-- the set looks as the base server's items.xml has them (checked in game by transmog.lua's startup validation)
local FIXTURE = {
	[27195] = {name = "talon circlet", kind = "helmet"}, [27200] = {name = "talon plate", kind = "armor"},
	[27201] = {name = "talon greaves", kind = "legs"}, [27401] = {name = "lion spangenhelm", kind = "helmet"},
	[27402] = {name = "lion plate", kind = "armor"}, [27399] = {name = "lion shield", kind = "shield"},
	[27398] = {name = "lion spellbook", kind = "shield"}, [27674] = {name = "spiritthorn helmet", kind = "helmet"},
	[27673] = {name = "spiritthorn armor", kind = "armor"}, [21696] = {name = "icicle bow", kind = "distance"},
	[21697] = {name = "runic ice shield", kind = "shield"}, [27679] = {name = "Arboreal Crown", kind = "helmet"},
	[27680] = {name = "Arboreal Tome", kind = "shield"}, [27677] = {name = "arcanomancer regalia", kind = "helmet"},
	[27678] = {name = "Arcanomancer Folio", kind = "shield"},
	-- the second store sets, the achievement and the boss sets (exclusives_config.lua)
	[26708] = {name = "skeletal helmet", kind = "helmet"}, [26709] = {name = "skeletal armor", kind = "armor"},
	[26710] = {name = "skeletal legs", kind = "legs"}, [26711] = {name = "skeletal boots", kind = "boots"},
	[27389] = {name = "soulshell", kind = "armor"}, [27387] = {name = "soulshanks", kind = "legs"},
	[27392] = {name = "pair of soulwalkers", kind = "boots"}, [27394] = {name = "soulbastion", kind = "shield"},
	[27391] = {name = "soulshroud", kind = "armor"}, [27388] = {name = "soulstrider", kind = "legs"},
	[27393] = {name = "pair of soulstalkers", kind = "boots"}, [28382] = {name = "Moist Helmet", kind = "helmet"},
	[28383] = {name = "Moist Armor", kind = "armor"}, [28384] = {name = "Moist Legs", kind = "legs"},
	[28385] = {name = "Moist Boots", kind = "boots"}, [27213] = {name = "cobra hood", kind = "helmet"},
	[27214] = {name = "cobra sword", kind = "sword"}, [27208] = {name = "cobra wand", kind = "wand"},
	[27209] = {name = "cobra rod", kind = "wand"}, [27400] = {name = "lion longsword", kind = "sword"},
	[27404] = {name = "lion axe", kind = "axe"}, [27405] = {name = "lion hammer", kind = "club"},
	[27395] = {name = "lion longbow", kind = "distance"}, [27396] = {name = "lion rod", kind = "wand"},
	[27397] = {name = "lion wand", kind = "wand"}, [27459] = {name = "grand sanguine blade", kind = "sword"},
	[27461] = {name = "grand sanguine cudgel", kind = "club"},
	[27463] = {name = "grand sanguine hatchet", kind = "axe"},
	[27472] = {name = "grand sanguine bow", kind = "distance"}, [27477] = {name = "grand sanguine coil", kind = "wand"},
	[28390] = {name = "Moist Coiff", kind = "helmet"}, [28391] = {name = "Moist Vestment", kind = "armor"},
	[28392] = {name = "Moist Breeches", kind = "legs"}, [28393] = {name = "Moist Greaves", kind = "boots"},
	[29564] = {name = "Haloed Bolter", kind = "distance"}, [29565] = {name = "Haloed Bow", kind = "distance"},
	[29469] = {name = "maliceforged helmet", kind = "helmet"}, [29472] = {name = "demonfang mask", kind = "helmet"},
	[8886] = {name = "molten plate", kind = "armor"}, [29486] = {name = "arcane pyrarch blade", kind = "sword"},
	[29482] = {name = "arcane pyrarch battleaxe", kind = "axe"},
	[29484] = {name = "arcane pyrarch mace", kind = "club"},
	[29478] = {name = "arcane pyrarch bow", kind = "distance"},
	[29488] = {name = "arcane pyrarch wand", kind = "wand"}, [29556] = {name = "Deathlord Cleaver", kind = "axe"},
	[29557] = {name = "Deathlord Mace", kind = "club"}, [29558] = {name = "Deathlord Blade", kind = "sword"},
	[27655] = {name = "gilded eldritch claymore", kind = "sword"},
	[27657] = {name = "gilded eldritch warmace", kind = "club"},
	[27659] = {name = "gilded eldritch greataxe", kind = "axe"},
	[27662] = {name = "gilded eldritch bow", kind = "distance"},
	[27672] = {name = "gilded eldritch rod", kind = "wand"}
}
local function describe(id)
	return FIXTURE[id]
end

-- ---------------------------------------------------------------- shipped config
local problems, warnings = K.validate(cfg, describe, shop, achievements)
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
eq(#problems, 0, "shipped config validates")
for _, w in ipairs(warnings) do
	print("note: " .. w)
end
eq(cfg.opcode, ChaosOpcodes.transmog, "opcode in chaos_constants.lua")
eq(cfg.opcode, 212, "opcode 212")
eq(Chaos.itemAttr.appearance, 8, "item attribute key 8")
local used = {}
for name, op in pairs(ChaosOpcodes) do
	eq(used[op], nil, "opcode " .. op .. " used twice (" .. name .. ")")
	used[op] = name
end
local sources = {}
for _, s in ipairs(cfg.sets) do
	sources[s.source] = (sources[s.source] or 0) + 1
	for _, id in ipairs(s.looks) do
		eq(FIXTURE[id] ~= nil, true, "fixture knows look " .. id)
	end
end
eq(sources.store, 9, "nine store sets") eq(sources.achievement, 4, "four achievement sets")
eq(sources.season, 1, "one season set") eq(sources.exclusive, 1, "one exclusive set")
eq(sources.boss, 4, "four boss sets (exclusives_config.lua drops)")
eq(K.setHow(K.setByKey(cfg, "deathlord")), "Boss: Varkhul the Ashen Sovereign (rare drop)", "a boss set's line")
eq(K.setHow(K.setByKey(cfg, "haloed")):find("Achievement: Lifeline", 1, true) ~= nil, true, "an achievement set's own line")
eq(K.setOfUnlock(cfg, "transmog_deathlord"), nil, "a boss set is no store unlock")
eq(cfg.fee.apply > 0 and cfg.fee.apply <= 5000, true, "a small apply fee")
eq(#cfg.slots, 6, "six slots")

-- the validator catches mistakes
do
	local bad = {opcode = 1, kinds = cfg.kinds, tables = cfg.tables, sets = {
		{key = "a", name = "A", source = "store", looks = {1}}, -- no price
		{key = "a", name = "B", source = "nowhere", looks = {1}}, -- twice, bad source, shared look
		{key = "c", name = "C", source = "achievement", achievement = "no_such", looks = {2}}
	}}
	local p = K.validate(bad, function(id) return id == 1 and {name = "x", kind = "helmet"} or nil end, nil, achievements)
	local text = table.concat(p, "\n")
	eq(text:find("no price") ~= nil, true, "store set without price")
	eq(text:find("set a twice") ~= nil, true, "duplicate key")
	eq(text:find("unknown source") ~= nil, true, "unknown source")
	eq(text:find("look 1 in sets") ~= nil, true, "look in two sets")
	eq(text:find("item 2 does not exist") ~= nil, true, "missing item")
	eq(text:find("no_such does not exist") ~= nil, true, "unknown achievement")
	-- the store: a wrong price, an offer for a set that is not a store set, an offer for no set
	local fakeShop = {categories = {{offers = {
		{kind = "unlock", unlock = "transmog_falconer", cost = 1},
		{kind = "unlock", unlock = "transmog_spiritthorn", cost = 10},
		{kind = "unlock", unlock = "transmog_nothing", cost = 10}
	}}}}
	local p2, w2 = K.validate(cfg, describe, fakeShop, achievements)
	local t2 = table.concat(p2, "\n")
	eq(t2:find("store price 1") ~= nil, true, "price mismatch")
	eq(t2:find("spiritthorn is sold") ~= nil, true, "achievement set sold")
	eq(t2:find("transmog_nothing names no") ~= nil, true, "offer without set")
	eq(#w2, 8, "the other store sets' offers missing: warnings only")
end

-- ---------------------------------------------------------------- kinds
local function T(over)
	local t = {cid = 100, pickupable = true, stackable = false, container = false, fluid = false, weaponType = 0, slotBits = 0}
	for k, v in pairs(over) do
		t[k] = v
	end
	return t
end
eq(K.kindOf(cfg, T({weaponType = 1, slotBits = 48})), "sword", "sword")
eq(K.kindOf(cfg, T({weaponType = 2, slotBits = 2096})), "club", "two-handed club")
eq(K.kindOf(cfg, T({weaponType = 3})), "axe", "axe")
eq(K.kindOf(cfg, T({weaponType = 4})), "shield", "shield")
eq(K.kindOf(cfg, T({weaponType = 5})), "distance", "bow")
eq(K.kindOf(cfg, T({weaponType = 6})), "wand", "wand")
eq(K.kindOf(cfg, T({weaponType = 7})), nil, "ammunition has no kind")
eq(K.kindOf(cfg, T({slotBits = 1})), "helmet", "head")
eq(K.kindOf(cfg, T({slotBits = 8})), "armor", "body")
eq(K.kindOf(cfg, T({slotBits = 64})), "legs", "legs")
eq(K.kindOf(cfg, T({slotBits = 128})), "boots", "feet")
eq(K.kindOf(cfg, T({slotBits = 2})), nil, "necklace")
eq(K.kindOf(cfg, T({slotBits = 256})), nil, "ring")
eq(K.kindOf(cfg, T({slotBits = 48})), nil, "a hand item without weapon type")
eq(K.kindOf(cfg, T({weaponType = 1, stackable = true})), nil, "stackable (throwing weapons)")
eq(K.kindOf(cfg, T({slotBits = 8, container = true})), nil, "container")
eq(K.kindOf(cfg, T({slotBits = 1, fluid = true})), nil, "fluid")
eq(K.kindOf(cfg, T({slotBits = 1, pickupable = false})), nil, "not pickupable")
eq(K.kindOf(cfg, T({slotBits = 1, cid = 0})), nil, "no client id")
eq(K.kindOf(cfg, nil), nil, "nothing")
eq(K.kindDef(cfg, "boots").name, "Boots", "kind name")

-- ---------------------------------------------------------------- sets and unlocking
eq(K.setOfLook(cfg, 27200).key, "falconer", "set of a look")
eq(K.setOfLook(cfg, 2463), nil, "a stock look is in no set")
eq(K.setByKey(cfg, "lionguard").name, "Lionguard", "set by key")
eq(K.unlockName(K.setByKey(cfg, "falconer")), "transmog_falconer", "unlock name")
eq(K.setOfUnlock(cfg, "transmog_falconer").key, "falconer", "store unlock")
eq(K.setOfUnlock(cfg, "transmog_spiritthorn"), nil, "an achievement set is not a store unlock")
eq(K.setOfUnlock(cfg, "portal_emberforge"), nil, "another unlock")
eq(K.setOfUnlock(cfg, nil), nil, "no name")
eq(K.setHow(K.setByKey(cfg, "falconer")):find("300") ~= nil, true, "store line has the price")
eq(K.unlockableFromItem(cfg, 2463, "armor"), true, "a stock armor unlocks its look")
eq(K.unlockableFromItem(cfg, 27200, "armor"), false, "a set look is never unlocked by carrying it")
eq(K.unlockableFromItem(cfg, 2463, nil), false, "no kind")
do
	local c = {exclude = {5}, excludeRanges = {{10, 20}}, sets = {}}
	eq(K.isExcluded(c, 5), true, "excluded id") eq(K.isExcluded(c, 15), true, "excluded range")
	eq(K.isExcluded(c, 21), false, "not excluded")
	eq(K.unlockableFromItem(c, 12, "armor"), false, "an excluded look")
end

-- ownership and progress
local owned = K.ownedLooks(cfg, {[2463] = true, [2457] = true}, {falconer = true})
eq(owned[2463], true, "own row") eq(owned[27195], true, "set look") eq(owned[27201], true, "set look 3")
eq(owned[27401], nil, "another set")
local catalogue = {[2463] = "armor", [2457] = "helmet", [2465] = "armor", [27195] = "helmet", [27200] = "armor",
	[27201] = "legs", [27401] = "helmet"}
local p = K.progress(cfg, catalogue, owned)
eq(p.kinds.armor.unlocked, 2, "armors unlocked") eq(p.kinds.armor.total, 3, "armors total")
eq(p.kinds.helmet.unlocked, 2, "helmets unlocked") eq(p.kinds.helmet.total, 3, "helmets total")
eq(p.kinds.legs.unlocked, 1, "legs") eq(p.kinds.boots.total, 0, "no boots")
eq(p.unlocked, 5, "all unlocked") eq(p.total, 7, "all")

-- sets from other systems
local syncs = K.setSyncs(cfg, {
	hasAchievement = function(id) return id == "level_500" end,
	seasonOwned = function(key) return key == "arboreal" end
}, {})
table.sort(syncs)
eq(#syncs, 2, "two sets to sync") eq(syncs[1], "arboreal", "season set") eq(syncs[2], "spiritthorn", "achievement set")
eq(#K.setSyncs(cfg, {hasAchievement = function() return true end}, {spiritthorn = true, rimebound = true,
	thornmoth = true, haloed = true}), 0, "already owned sets are not synced again")
eq(#K.setSyncs(cfg, {hasAchievement = function() return true end, seasonOwned = function() return true end}, {}), 5,
	"the four achievement sets and the season set; boss sets only through exclusives.lua")
eq(#K.setSyncs(cfg, {}, {}), 0, "no facts: nothing")

-- ---------------------------------------------------------------- fee, apply and remove
local c = {fee = {apply = 2000, perItemLevel = 10, maxApply = 20000, remove = 0}, kinds = cfg.kinds}
eq(K.fee(c, 0, "apply"), 2000, "base fee") eq(K.fee(c, 300, "apply"), 5000, "item level 300")
eq(K.fee(c, 5000, "apply"), 20000, "capped") eq(K.fee(c, nil, "apply"), 2000, "no level")
eq(K.fee(c, 300, "remove"), 0, "remove is free") eq(K.fee(c, -5, "apply"), 2000, "negative level")
local function A(over)
	local a = {item = {id = 2463, kind = "armor", look = 0, level = 0}, look = {id = 2465, kind = "armor"},
		owned = {[2465] = true}, money = 10000}
	for k, v in pairs(over or {}) do
		a[k] = v
	end
	if a.noItem then
		a.item = nil
	end
	if a.noLook then
		a.look = nil
	end
	return a
end
local reason, fee = K.applyCheck(c, A())
eq(reason, nil, "apply allowed") eq(fee, 2000, "apply fee")
eq(K.applyCheck(c, A({noItem = true})):find("no item") ~= nil, true, "empty slot")
eq(K.applyCheck(c, A({item = {id = 2160, kind = nil}})):find("cannot change") ~= nil, true, "item without kind")
eq(K.applyCheck(c, A({noLook = true})):find("Unknown") ~= nil, true, "unknown look")
eq(K.applyCheck(c, A({look = {id = 2457, kind = "helmet"}, owned = {[2457] = true}})):find("same kind") ~= nil, true,
	"another kind")
eq(K.applyCheck(c, A({look = {id = 2463, kind = "armor"}, owned = {[2463] = true}})):find("own look") ~= nil, true,
	"its own look")
eq(K.applyCheck(c, A({item = {id = 2463, kind = "armor", look = 2465}})):find("already") ~= nil, true, "same look again")
eq(K.applyCheck(c, A({owned = {}})):find("not unlocked") ~= nil, true, "locked look")
eq(K.applyCheck(c, A({money = 1999})):find("2000 gold") ~= nil, true, "not enough gold")
eq(K.applyCheck(c, A({item = {id = 2463, kind = "armor", look = 0, level = 400}, money = 5999})):find("6000") ~= nil,
	true, "the fee grows with the item level")
reason, fee = K.removeCheck(c, {item = {id = 2463, look = 2465}, money = 0})
eq(reason, nil, "remove allowed") eq(fee, 0, "remove fee")
eq(K.removeCheck(c, {item = {id = 2463, look = 0}, money = 0}):find("own look") ~= nil, true, "nothing to remove")
eq(K.removeCheck(c, {item = nil}):find("no item") ~= nil, true, "remove: empty slot")
eq(K.removeCheck({fee = {remove = 50}}, {item = {id = 1, look = 2}, money = 10}):find("50 gold") ~= nil, true,
	"a remove fee is charged when set")

-- ---------------------------------------------------------------- SQL and requests
local creates = K.sqlCreate(cfg)
eq(#creates, 2, "two tables")
eq(creates[1]:find("CREATE TABLE IF NOT EXISTS `chaos_transmog`", 1, true) ~= nil, true, "looks table")
eq(creates[2]:find("`chaos_transmog_sets`", 1, true) ~= nil, true, "sets table")
eq(K.sqlInsertLook(cfg, 7, 2463, 100), "INSERT IGNORE INTO `chaos_transmog` (`account_id`, `item_id`, `created`) VALUES (7, 2463, 100)",
	"insert look")
eq(K.sqlInsertSet(cfg, 7, "fal'coner", "st;ore", 1):find("'falconer', 'store'", 1, true) ~= nil, true, "set key sanitised")
eq(K.sqlDeleteSet(cfg, 7, "x' OR 1=1"):find("'xOR11'", 1, true) ~= nil, true, "delete sanitised")
eq(K.sqlSelectLooks(cfg, "3 OR 1"), "SELECT `item_id` FROM `chaos_transmog` WHERE `account_id` = 0", "account id is a number")
local sqlFile = readFile("sql/chaos_transmog.sql")
eq(sqlFile ~= nil and sqlFile:find("`chaos_transmog_sets`", 1, true) ~= nil, true, "sql/chaos_transmog.sql")

local action, data = K.request({action = "apply", data = {slot = 4, look = 2465}})
eq(action, "apply", "apply request") eq(data.slot, 4, "slot") eq(data.look, 2465, "look")
eq(K.request({action = "apply", data = {slot = 4}}), nil, "apply without look")
eq(K.request({action = "apply", data = {slot = 11, look = 1}}), nil, "bad slot")
eq(K.request({action = "remove", data = {slot = "6"}}), "remove", "remove request")
eq(K.request({action = "looks", data = {kind = "armor"}}), "looks", "looks request")
eq(K.request({action = "looks", data = {}}), nil, "looks without kind")
eq(K.request({action = "open"}), "open", "open")
eq(K.request({action = "drop"}), nil, "unknown action")
eq(K.request("x"), nil, "not a table")

-- ---------------------------------------------------------------- engine and client patches
local engine = readFile("src-patches/0019-transmog-appearance.patch")
eq(engine ~= nil, true, "engine patch 0019")
eq(engine:find("CHAOS_ITEM_KEY_APPEARANCE = 8", 1, true) ~= nil, true, "engine key 8")
eq(engine:find('"chaos_tmog"', 1, true) ~= nil, true, "engine reads chaos_tmog")
local client = readFile("../client/base-patches/0030-transmog-appearance.patch")
eq(client ~= nil, true, "client patch 0030")
eq(client:find("ITEM_CUSTOM_ATTR_APPEARANCE = 8", 1, true) ~= nil, true, "client key 8")
local lua = readFile("data/scripts/chaos/transmog.lua")
eq(lua:find('local ATTR = "chaos_tmog"', 1, true) ~= nil, true, "transmog.lua writes chaos_tmog")
-- the look survives the market escrow without engine patch 0017 and the guild depot (their attribute key lists)
eq(readFile("data/scripts/chaos/market.lua"):find('"chaos_tmog"', 1, true) ~= nil, true, "market keeps the look")
eq(readFile("data/scripts/chaos/guild_config.lua"):find('"chaos_tmog"', 1, true) ~= nil, true, "guild depot keeps the look")

-- ---------------------------------------------------------------- set looks are given nowhere else
local setLooks = {}
for _, s in ipairs(cfg.sets) do
	for _, id in ipairs(s.looks) do
		setLooks[id] = s.key
	end
end
local function scan(path)
	local text = readFile(path)
	if not text then
		return
	end
	-- the store offers of the store sets (shop_config.lua) and the season pass reward of the season set
	-- (seasonpass_config.lua kind "transmog") show a set look as their icon: the set's own source, a picture
	text = text:gsub("[^\n]*unlock = \"transmog_[%w_]+\"[^\n]*", ""):gsub("[^\n]*kind = \"transmog\"[^\n]*", "")
	for num in text:gmatch("%f[%d](%d%d%d%d%d)%f[%D]") do
		if setLooks[tonumber(num)] then
			error(path .. " names the set look " .. num .. " (set " .. setLooks[tonumber(num)] .. ")")
		end
	end
end
local ok, pipe = pcall(io.popen, "find data/monster data/npc data/scripts data/lib data/XML -type f \\( -name '*.lua' -o -name '*.xml' \\) 2>/dev/null")
local scanned = 0
if ok and pipe then
	for path in pipe:lines() do
		if not path:find("transmog", 1, true) then
			scan(path)
			scanned = scanned + 1
		end
	end
	pipe:close()
end
eq(scanned > 100, true, "repo data scanned (" .. scanned .. " files)")

print("transmog_test: " .. n .. " checks OK")
