-- Run from the server/ folder: luajit tests/cosmetics_test.lua (and lua5.3; CI runs both)
-- Cosmetics (cosmetics_core.lua, cosmetics_config.lua, cosmetics_store.lua, cosmetics.lua, the skin hook of
-- data/spells/chaos/_common.lua): the shipped config against the real effect catalogues of the client pair (every swap
-- is a recolour inside one family, every variant exists), the spells of each line, the achievements, the store
-- categories, readable colours; ownership, choosing, the spell skin lookup; then cosmetics.lua on a mocked engine
-- (store unlock, choosing, the cast hook, kill effects on the killing blow only, chat name colours for everybody, the
-- label accent, previews to the asking player only) and _common.lua's swap during a cast with the default fallback.
CONST_ME_FIREWORK_YELLOW = CONST_ME_FIREWORK_YELLOW or 29 -- shop_config.lua reads it
dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/cosmetics_core.lua")
local K = ChaosCosmeticsCore
local cfg = dofile("data/scripts/chaos/cosmetics_config.lua")
local shop = dofile("data/scripts/chaos/shop_config.lua")
local achievementsData = dofile("data/scripts/chaos/achievements_data.lua")

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

-- ---------------------------------------------------------------- the client pair's effects (catalogues)
local function csv(path)
	local rows, header = {}, nil
	for line in (readFile(path) or ""):gmatch("[^\r\n]+") do
		local cells, i = {}, 1
		-- simple CSV: quoted cells may hold commas
		while i <= #line do
			if line:sub(i, i) == '"' then
				local j = line:find('"', i + 1, true)
				cells[#cells + 1] = line:sub(i + 1, j - 1)
				i = j + 2
			else
				local j = line:find(",", i, true) or (#line + 1)
				cells[#cells + 1] = line:sub(i, j - 1)
				i = j + 1
			end
		end
		if not header then
			header = cells
		else
			local row = {}
			for k, h in ipairs(header) do
				row[h] = cells[k]
			end
			rows[#rows + 1] = row
		end
	end
	return rows
end
local catalog = {fx = {}, missile = {}, vfx = {}, vmissile = {}}
local style, size = {fx = {}, missile = {}}, {vfx = {}, vmissile = {}}
for _, r in ipairs(csv("data/spells/effects_catalog.csv")) do
	local t = r.category == "missile" and "missile" or "fx"
	catalog[t][r.name] = true
	style[t][r.name] = r.style
end
for _, path in ipairs({"data/spells/vfx_catalog.csv", "data/spells/vfx_art_catalog.csv"}) do
	for _, r in ipairs(csv(path)) do
		local t = r.kind == "missile" and "vmissile" or (r.kind == "effect" and "vfx" or nil)
		if t then
			catalog[t][r.name] = true
			size[t][r.name] = r.size .. "/" .. r.frames
		end
	end
end
eq(catalog.vfx.aura_burst_god, true, "the catalogue was read")
eq(catalog.fx.shadow_ring, true, "the procedural catalogue was read")

-- a recolour family is one picture: the same style (procedural) or the same size and frame count (pack effects)
for t, fams in pairs(cfg.families) do
	for fam, members in pairs(fams) do
		local first
		for _, m in ipairs(members) do
			local shape = (style[t] or size[t])[m]
			eq(shape ~= nil, true, t .. " " .. m .. " is in the pair")
			first = first or shape
			eq(shape, first, "family " .. t .. "." .. fam .. ": " .. m .. " has the shape of the others")
		end
	end
end

-- spells of the lines (spells_chaos.xml): spell id -> {[vocation] = true}
local spellVocations = {}
local xml = readFile("data/spells/chaos/spells_chaos.xml")
for attrs, body in xml:gmatch("<instant ([^>]-)>(.-)</instant>") do
	local id = tonumber(attrs:match('spellid="(%d+)"'))
	if id then
		spellVocations[id] = {}
		for v in body:gmatch('vocation name="([^"]+)"') do
			spellVocations[id][v] = true
		end
	end
end
local achievements = {}
for _, a in ipairs(achievementsData.list) do
	achievements[a.id] = a.name
end

-- ---------------------------------------------------------------- the shipped config
local problems, warnings = K.validate(cfg, {catalog = catalog, achievements = achievements, shop = shop,
	spellVocations = spellVocations})
for _, p in ipairs(problems) do
	print("problem: " .. p)
end
for _, w in ipairs(warnings) do
	print("note: " .. w)
end
eq(#problems, 0, "shipped config validates")
eq(#warnings, 0, "every store cosmetic is sold")
eq(cfg.opcode, ChaosOpcodes.cosmetics, "opcode in chaos_constants.lua")
local usedOpcodes = {}
for name, op in pairs(ChaosOpcodes) do
	eq(usedOpcodes[op], nil, "opcode " .. op .. " used once (" .. name .. ")")
	usedOpcodes[op] = name
end
-- storages in the Chaos range, inside the reserved block, distinct
local st, seen = cfg.storage, {}
for _, key in ipairs({st.killfx, st.lootbeam, st.chatcolor}) do
	eq(key >= 7100940 and key <= 7100949 and not seen[key], true, "storage " .. key)
	seen[key] = true
end
for _, l in ipairs(cfg.lines) do
	local key = st.skinBase + l.slot
	eq(key >= 7100940 and key <= 7100949 and not seen[key], true, "line storage " .. key)
	seen[key] = true
end

-- counts and prices (README "Cosmetics")
local count, store = {}, {}
for _, c in ipairs(cfg.cosmetics) do
	count[c.kind] = (count[c.kind] or 0) + 1
	if c.source == "store" then
		store[c.kind] = store[c.kind] or c.price
		eq(c.price, store[c.kind], "one price per kind: " .. c.key)
	end
end
eq(count.spellskin, 12, "12 spell skins") eq(count.killfx, 8, "8 kill effects (the Cinderheart Crown of uber.lua)")
eq(count.lootbeam, 5, "5 label accents") eq(count.chatcolor, 6, "6 chat colours")
eq(store.spellskin, 250, "skins 250") eq(store.killfx, 200, "kill effects 200")
eq(store.lootbeam, 150, "label accents 150") eq(store.chatcolor, 200, "chat colours 200")
-- every line but the Necromancer's has 2-3 skins of 2-3 spells
for _, l in ipairs(cfg.lines) do
	local skins = K.index(cfg).skinsOfLine[l.key]
	eq(#skins >= 1 and #skins <= 3, true, l.key .. ": skins")
end

-- the validator refuses what is not a recolour, unknown effects, power, unreadable colours, a wrong store price
local function broken(change)
	local copy = {}
	for k, v in pairs(cfg) do
		copy[k] = v
	end
	copy.cosmetics = {}
	for i, c in ipairs(cfg.cosmetics) do
		local cc = {}
		for k, v in pairs(c) do
			cc[k] = v
		end
		copy.cosmetics[i] = cc
	end
	change(copy.cosmetics)
	local p = K.validate(copy, {catalog = catalog, achievements = achievements, shop = shop, spellVocations = spellVocations})
	return table.concat(p, "\n")
end
eq(broken(function(l) l[1].vfx = {aura_burst_gold = "dome_blast_fire"} end):find("not a recolour", 1, true) ~= nil, true,
	"another picture is refused")
eq(broken(function(l) l[1].fx = {blood_rune = "no_such_rune"} end):find("not a recolour", 1, true) ~= nil, true,
	"an unknown variant is refused")
eq(broken(function(l) l[1].damage = 10 end):find("not cosmetic", 1, true) ~= nil, true, "power is refused")
eq(broken(function(l) l[1].spells = {200} end):find("not a spell of", 1, true) ~= nil, true, "a spell of another line")
eq(broken(function(l) l[1].spells = {223, 222, 247, 220} end):find("1 to 3 spells", 1, true) ~= nil, true, "3 spells at most")
eq(broken(function(l) l[13].vfx = "no_such_effect" end):find("not an effect", 1, true) ~= nil, true, "kill effect unknown")
eq(broken(function(l) l[20].accent = "#c0c0c0f0" end):find("unreadable", 1, true) ~= nil, true, "a light accent")
eq(broken(function(l) l[20].accent = "#46180940" end):find("transparent", 1, true) ~= nil, true, "a see-through accent")
eq(broken(function(l) l[25].color = "#303030" end):find("not readable", 1, true) ~= nil, true, "a dark chat colour")
eq(broken(function(l) l[1].price = 999 end):find("store price", 1, true) ~= nil, true, "price mismatch with the store")
eq(broken(function(l) l[18].achievement = "nope" end):find("does not exist", 1, true) ~= nil, true, "unknown achievement")
eq(broken(function(l) l[2].id = 1 end):find("used twice", 1, true) ~= nil, true, "id twice")

-- colours: contrast maths
eq(math.floor(K.contrast("#ffffff", "#000000") + 0.5), 21, "white on black is 21")
eq(K.contrast("#123456", "#123456"), 1, "same colour is 1")
eq(K.contrast("nope", "#000000"), nil, "bad colour")

-- ---------------------------------------------------------------- the store categories (cosmetics_store.lua)
local cats = {}
for _, c in ipairs(shop.categories) do
	cats[c.name] = c
end
for _, k in ipairs(cfg.kinds) do
	local cat = cats[k.store]
	eq(cat ~= nil, true, "store category " .. k.store)
	for _, o in ipairs(cat.offers) do
		local c = K.ofUnlock(cfg, o.unlock)
		eq(c ~= nil and c.kind == k.key, true, "offer " .. o.unlock .. " is a " .. k.key)
		eq(o.gift, false, "not giftable (unlocks run on the buyer)")
		eq(type(o.icon), "number", "icon")
		eq(#o.description <= 140, true, "description fits the offer: " .. o.unlock)
	end
end
eq(K.ofUnlock(cfg, "cosmetic_kill_voidring"), nil, "an achievement cosmetic is no store unlock")
eq(K.ofUnlock(cfg, "transmog_falconer"), nil, "other unlocks are not ours")
eq(cats["Name Plates"] ~= nil and #cats["Name Plates"].offers, 5, "five frames in the store")
-- the transmog store sets (follow-up): offers at the sets' prices
local tm = {}
for _, o in ipairs(cats["Appearances"].offers) do
	tm[o.unlock] = o.cost
end
eq(tm.transmog_falconer, 300, "Falconer's Regalia 300") eq(tm.transmog_lionguard, 350, "Lionguard 350")
-- the three new frames exist everywhere a frame must
dofile("data/scripts/chaos/nameplate_core.lua")
local shopText = readFile("data/scripts/chaos/shop.lua")
for _, f in ipairs({"ember", "verdant", "bone"}) do
	eq(ChaosNameplate.FRAMES[f], true, "nameplate_core frame " .. f)
	eq(shopText:find('"' .. f .. '"', 1, true) ~= nil, true, "shop.lua FRAMES has " .. f)
	eq(readFile("../client/overlay/modules/game_nameplate/images/plate_" .. f .. ".png") ~= nil, true, "art plate_" .. f)
end
-- the store unlock hooks of shop_services.lua
local services = readFile("data/scripts/chaos/shop_services.lua")
eq(services:find("ChaosTransmog.storeUnlock(name)", 1, true) ~= nil, true, "unlockEntry asks the transmog sets")
eq(services:find("ChaosCosmetics.storeUnlock(name)", 1, true) ~= nil, true, "unlockEntry asks the cosmetics")

-- ---------------------------------------------------------------- core rules
local owned = {skin_warrior_void = true, kill_soulspark = true, chat_frost = true}
eq(K.owns(owned, K.byKey(cfg, "kill_soulspark")), true, "owned")
eq(K.owns(owned, K.byKey(cfg, "kill_sunring")), false, "not owned")
local c, why = K.choose(cfg, owned, "killfx", 102)
eq(c, nil, "not owned: refused") eq(why:find("Store > Kill Effects", 1, true) ~= nil, true, "where to get it")
eq(K.choose(cfg, owned, "killfx", 101).key, "kill_soulspark", "owned: chosen")
eq(K.choose(cfg, owned, "killfx", 0), false, "0 = the default")
eq(K.choose(cfg, owned, "chatcolor", 101), nil, "an id of another kind")
eq(K.choose(cfg, owned, "stats", 1), nil, "unknown kind")
c, why = K.choose(cfg, owned, "killfx", 106)
eq(why, "Void Ring is not unlocked yet.", "achievement cosmetic text")
-- the achievement syncs
local syncs = K.syncs(cfg, function(id) return id == "level_300" or id == "goblin_10" end, {loot_gilded = true})
eq(#syncs, 1, "one to grant") eq(syncs[1], "chat_veteran", "Veteran's Gold")
-- spell skins: only the listed spells, only the swapped effects
local void = K.byKey(cfg, "skin_warrior_void")
eq(K.swap(void, 223, "vfx", "aura_burst_gold"), "aura_burst_violet", "Iron Bellow burst")
eq(K.swap(void, 223, "fx", "blood_rune"), "arcane_circle", "Iron Bellow rune")
eq(K.swap(void, 223, "fx", "aura_ring"), nil, "an effect the skin leaves alone")
eq(K.swap(void, 220, "vfx", "aura_burst_gold"), nil, "a spell the skin leaves alone")
eq(K.swap(void, 223, "missile", "aura_burst_gold"), nil, "another effect type")
local chosenLines = {warrior = 1}
eq(K.skinForSpell(cfg, 222, function(line) return chosenLines[line] end), void, "Red Frenzy uses the warrior skin")
eq(K.skinForSpell(cfg, 63, function(line) return chosenLines[line] end), nil, "the monk line has none chosen")
chosenLines.warrior = 8 -- a monk skin stored in the warrior slot is ignored
eq(K.skinForSpell(cfg, 222, function(line) return chosenLines[line] end), nil, "a skin of another line is ignored")
eq(K.lineOfVocation(cfg, "Iron Sage"), "monk", "Iron Sage is the monk line")
eq(K.lineOfVocation(cfg, "Lich"), nil, "the Necromancer line has no skins")
eq(K.storageOf(cfg, "spellskin", "templar"), 7100948, "templar slot storage")
eq(K.storageOf(cfg, "chatcolor"), 7100942, "chat colour storage")
-- previews
local pv = K.previewOf(K.byKey(cfg, "skin_mystic_voidfire"))
eq(#pv, 3, "Voidfire preview: three variants")
eq(K.previewOf(K.byKey(cfg, "kill_shatter"))[1].name, "ice_shatter", "kill effect preview")
eq(#K.previewOf(K.byKey(cfg, "chat_rose")), 0, "a colour has no effect preview")
eq(K.offerPreview(K.byKey(cfg, "chat_rose")).color, "#ff8fb0", "colour preview in the store")
eq(K.offerPreview(K.byKey(cfg, "loot_azure")).accent, "#0f2250f0", "accent preview in the store")
eq(K.offerPreview(K.byKey(cfg, "kill_shatter")).effect, true, "effect preview button")
-- window rows
local rows = K.rows(cfg, owned, {killfx = 101, lines = {warrior = 1}}, {line = "warrior",
	achievementName = function(id) return achievements[id] end})
eq(#rows, #cfg.cosmetics, "a row per cosmetic")
local byKey = {}
for _, r in ipairs(rows) do
	byKey[r.key] = r
end
eq(byKey.kill_soulspark.selected, true, "chosen kill effect") eq(byKey.skin_warrior_void.selected, true, "chosen skin")
eq(byKey.skin_warrior_void.mine, true, "the character's line") eq(byKey.skin_monk_void.mine, nil, "another line")
eq(byKey.kill_voidring.how, "Achievement: Legend's Bane", "how to get it")
eq(byKey.kill_sunring.how, "Store: 200 Chaos Coins", "store price")
eq(byKey.chat_frost.color, "#7fc8ff", "colour in the row")
-- SQL
eq(K.sqlInsert(cfg, 7, "kill';drop", "st;ore", 1):find("'killdrop', 'store'", 1, true) ~= nil, true, "keys sanitised")
eq(K.sqlSelect(cfg, "3 or 1"), "SELECT `cosmetic` FROM `chaos_cosmetics` WHERE `account_id` = 0", "account id numeric")
eq(readFile("sql/chaos_cosmetics.sql"):find("CREATE TABLE IF NOT EXISTS `chaos_cosmetics`", 1, true) ~= nil, true, "sql file")

-- ---------------------------------------------------------------- cosmetics.lua on a mocked engine
local inbox, seq = {}, 0
json = {
	encode = function(t)
		seq = seq + 1
		local k = "{J" .. seq .. "}"
		inbox[k] = t
		return k
	end,
	decode = function(s)
		return inbox[s]
	end
}
local effects, distance, sent = {}, {}, {}
Position = function(x, y, z)
	if type(x) == "table" then
		x, y, z = x.x, x.y, x.z
	end
	return {x = x, y = y, z = z,
		sendMagicEffect = function(self, id, only)
			effects[#effects + 1] = {x = self.x, y = self.y, id = id, only = only and only:getName() or nil}
		end,
		sendDistanceEffect = function(self, to, id, only)
			distance[#distance + 1] = {id = id, only = only and only:getName() or nil}
		end}
end
local storages, players = {}, {}
local function newPlayer(id, name, account, vocation)
	local p = {id = id, name = name, account = account, events = {}}
	storages[id] = storages[id] or {}
	function p:getId() return self.id end
	function p:getName() return self.name end
	function p:getAccountId() return self.account end
	function p:getGuid() return self.id end
	function p:isPlayer() return true end
	function p:getStorageValue(k) return storages[self.id][k] or -1 end
	function p:setStorageValue(k, v) storages[self.id][k] = v end
	function p:getVocation() return {getName = function() return vocation end} end
	function p:getPosition() return Position(100, 100, 7) end
	function p:registerEvent(e) self.events[e] = true end
	function p:getGroup() return {getId = function() return 1 end} end
	function p:sendTextMessage(_, text) sent[#sent + 1] = {to = self.name, text = text} end
	function p:sendExtendedOpcode(op, payload)
		sent[#sent + 1] = {to = self.name, op = op, msg = inbox[payload]}
	end
	players[id] = p
	return p
end
Player = function(id)
	if type(id) == "string" then
		for _, p in pairs(players) do
			if p.name == id then
				return p
			end
		end
		return nil
	end
	return players[id]
end
Game = {getPlayers = function()
	local out = {}
	for _, p in pairs(players) do
		out[#out + 1] = p
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end}
local queries, rows = {}, {} -- rows[account] = {keys}
db = {query = function(q)
	queries[#queries + 1] = q
	local acc, key = q:match("VALUES %((%d+), '([%w_]+)'")
	if acc then
		rows[tonumber(acc)] = rows[tonumber(acc)] or {}
		table.insert(rows[tonumber(acc)], key)
	end
	return true
end, storeQuery = function(q)
	local acc = tonumber(q:match("`account_id` = (%d+)"))
	if acc and rows[acc] and #rows[acc] > 0 then
		return {acc = acc, i = 1}
	end
	return false
end, escapeString = function(s) return "'" .. s .. "'" end}
result = {
	getString = function(r) return rows[r.acc][r.i] end,
	next = function(r) r.i = r.i + 1; return r.i <= #rows[r.acc] end,
	free = function() end
}
local timers = {}
addEvent = function(fn, ms, ...)
	timers[#timers + 1] = {fn = fn, ms = ms, args = {...}}
	return #timers
end
local function runTimers()
	local list = timers
	timers = {}
	for _, t in ipairs(list) do
		t.fn((unpack or table.unpack)(t.args))
	end
end
os.mtime = os.mtime or function() return os.time() * 1000 end
MESSAGE_INFO_DESCR, MESSAGE_EVENT_ADVANCE = 22, 19
local registered = {}
local function event(kind)
	return function(name)
		local e = {name = name}
		function e:register() registered[name] = self end
		function e:type() end
		function e:separator() end
		return e
	end
end
CreatureEvent, GlobalEvent, TalkAction = event("creature"), event("global"), event("talk")
EventCallback = nil -- the onSpawn registration is engine-only
ChaosAchievements = {has = function(player, id) return player.name == "Vet" and id == "level_300" end,
	data = achievementsData}
ChaosRateLimit = nil

dofile("data/scripts/chaos/cosmetics.lua")
local M = ChaosCosmetics
eq(type(M.swapFor), "function", "cosmetics.lua loaded")
eq(registered.ChaosCosmeticsStartup.onStartup(), true, "startup validates") -- prints nothing on the shipped config

local ann = newPlayer(1, "Ann", 10, "Juggernaut")
local bob = newPlayer(2, "Bob", 20, "Monk")
registered.ChaosCosmeticsLogin.onLogin(ann)
registered.ChaosCosmeticsLogin.onLogin(bob)
eq(ann.events.ChaosCosmeticsExtended, true, "opcode event registered")

-- the store unlock (shop_services.lua) and ownership
local u = M.storeUnlock("cosmetic_skin_warrior_void")
eq(u.name, "Voidborn War Cries", "store unlock name")
eq(u.owned(ann), false, "not owned yet")
eq(u.grant(ann), true, "bought")
eq(u.owned(ann), true, "owned now")
eq(M.storeUnlock("cosmetic_kill_voidring"), nil, "achievement cosmetics are not sold")
eq(M.storeUnlock("transmog_falconer"), nil, "not ours")
local ok, err = u.grant(ann)
eq(ok, false, "a second purchase is refused") eq(err:find("already", 1, true) ~= nil, true, "owned already")
M.owned = {} -- the cache is rebuilt from the table
eq(M.owns(10, "skin_warrior_void"), true, "kept in chaos_cosmetics")

-- choosing through the opcode
local function opcode(p, action, data)
	registered.ChaosCosmeticsExtended.onExtendedOpcode(p, cfg.opcode, json.encode({action = action, data = data}))
end
local function lastTo(name, action)
	for i = #sent, 1, -1 do
		local s = sent[i]
		if s.to == name and s.msg and s.msg.action == action then
			return s.msg.data
		end
	end
end
opcode(ann, "open", {})
local state = lastTo("Ann", "state")
eq(state.open, true, "window opens") eq(state.line, "warrior", "Ann's line")
opcode(ann, "select", {kind = "spellskin", id = 9})
eq(lastTo("Ann", "result").ok, false, "a skin not owned is refused")
opcode(ann, "select", {kind = "spellskin", id = 1})
eq(lastTo("Ann", "result").ok, true, "the owned skin is chosen")
eq(storages[1][7100943], 1, "stored in the warrior slot")
eq(M.swapFor(1, 223, "vfx", "aura_burst_gold"), "aura_burst_violet", "Iron Bellow casts violet")
eq(M.swapFor(1, 225, "fx", "ground_slam"), nil, "Colossus Fall unchanged")
eq(M.swapFor(2, 223, "vfx", "aura_burst_gold"), nil, "Bob has no skin")

-- the cast hook in _common.lua: the variant during a cast, the default outside it and when the pair lacks the variant
NORTH, EAST, SOUTH, WEST, SOUTHWEST, SOUTHEAST, NORTHWEST, NORTHEAST = 0, 1, 2, 3, 4, 5, 6, 7
local castPid, castSpell
ChaosSupportsSpell = {cast = function() return castPid, castSpell end}
dofile("data/spells/chaos/_common.lua")
local function lastEffect()
	return effects[#effects].id
end
castPid, castSpell = 1, 223
ChaosSpell.vfx({x = 50, y = 50, z = 7}, "aura_burst_gold")
eq(lastEffect(), ChaosVfx.aura_burst_violet.id, "a cast of Iron Bellow sends the violet burst")
ChaosSpell.fx({x = 50, y = 50, z = 7}, "blood_rune", 1)
eq(lastEffect(), ChaosFx.arcane_circle, "and the arcane rune (Fx is swapped)")
eq(Fx("blood_rune", 1), ChaosFx.arcane_circle, "Fx inside the cast")
castPid, castSpell = 2, 223
ChaosSpell.vfx({x = 50, y = 50, z = 7}, "aura_burst_gold")
eq(lastEffect(), ChaosVfx.aura_burst_gold.id, "another caster: the default")
castPid, castSpell = nil, nil
eq(Fx("blood_rune", 1), ChaosFx.blood_rune, "outside a cast: the default")
castPid, castSpell = 1, 223
local saved = ChaosVfx.aura_burst_violet
ChaosVfx.aura_burst_violet = nil -- a pair without the variant
ChaosSpell.vfx({x = 50, y = 50, z = 7}, "aura_burst_gold")
eq(lastEffect(), ChaosVfx.aura_burst_gold.id, "missing variant: the default effect")
ChaosVfx.aura_burst_violet = saved
castPid, castSpell = nil, nil

-- kill effects: the killing blow only, seen by everybody
local kill = M.storeUnlock("cosmetic_kill_shatter")
kill.grant(ann)
opcode(ann, "select", {kind = "killfx", id = 103})
local monster = {getPosition = function() return Position(200, 200, 7) end}
local before = #effects
registered.ChaosCosmeticsDeath.onDeath(monster, nil, ann, bob)
eq(#effects, before + 1, "Ann's killing blow shows the effect")
eq(effects[#effects].id, ChaosVfx.ice_shatter.id, "Frost Shatter") eq(effects[#effects].only, nil, "everybody sees it")
eq(effects[#effects].x, 200 + ChaosVfx.ice_shatter.dx, "at the monster, at the effect's offset")
before = #effects
registered.ChaosCosmeticsDeath.onDeath(monster, nil, bob, ann)
eq(#effects, before, "Ann did most damage, Bob the last hit: nothing")
registered.ChaosCosmeticsDeath.onDeath(monster, nil, {isPlayer = function() return false end}, ann)
eq(#effects, before, "a monster's last hit: nothing")
opcode(ann, "select", {kind = "killfx", id = 0})
registered.ChaosCosmeticsDeath.onDeath(monster, nil, ann, ann)
eq(#effects, before, "back to the default: nothing")

-- chat name colours: for every online character, sent at login and on a change
M.storeUnlock("cosmetic_chat_frost").grant(bob)
opcode(bob, "select", {kind = "chatcolor", id = 302})
eq(M.colors.Bob, "#7fc8ff", "Bob's name colour")
eq(lastTo("Ann", "colors").names.Bob, "#7fc8ff", "Ann's client learns it")
local carl = newPlayer(3, "Carl", 30, "Ranger")
registered.ChaosCosmeticsLogin.onLogin(carl)
local full = lastTo("Carl", "colors")
eq(full.full, true, "full list at login") eq(full.names.Bob, "#7fc8ff", "with Bob's colour")
opcode(bob, "select", {kind = "chatcolor", id = 0})
eq(lastTo("Carl", "colors").names.Bob, false, "switched off: removed everywhere")
registered.ChaosCosmeticsLogout.onLogout(carl)
eq(M.active[3], nil, "logout clears the cache")

-- the label accent: only the character's own client
M.storeUnlock("cosmetic_loot_azure").grant(bob)
opcode(bob, "select", {kind = "lootbeam", id = 203})
eq(lastTo("Bob", "style").accent, "#0f2250f0", "Bob's accent")
eq(lastTo("Bob", "colors") ~= nil, true, "Bob got colour updates")

-- achievement cosmetics are granted at login
local vet = newPlayer(4, "Vet", 40, "Templar")
registered.ChaosCosmeticsLogin.onLogin(vet)
eq(M.owns(40, "chat_veteran"), true, "Veteran's Gold granted from the achievement")
eq(M.owns(40, "kill_voidring"), false, "not the other ones")

-- previews: to the asking player only, one after the other, rate limited
effects = {}
eq(M.storePreview(ann, "cosmetic_skin_mystic_voidfire"), true, "store preview")
eq(M.storePreview(ann, "cosmetic_skin_mystic_voidfire"), false, "again at once: refused")
runTimers()
eq(#effects, 3, "Voidfire: its three variants")
for _, e in ipairs(effects) do
	eq(e.only, "Ann", "only Ann sees the preview")
end
eq(M.storePreview(bob, "cosmetic_chat_frost"), false, "a colour has no effect preview")
eq(M.offerPreview("cosmetic_chat_frost").color, "#7fc8ff", "the store shows the colour")
eq(M.offerPreview("transmog_falconer"), nil, "nothing for other unlocks")

-- staff
local gm = newPlayer(9, "Gm", 90, "Warrior")
gm.getGroup = function() return {getId = function() return 6 end} end
db.storeQuery = (function(old)
	return function(q)
		if q:find("FROM `players`", 1, true) then
			return {player = q:match("'([^']+)'")}
		end
		return old(q)
	end
end)(db.storeQuery)
result.getNumber = function(r) return Player(r.player) and Player(r.player).account or nil end
registered["/cosmetic"].onSay(gm, "/cosmetic", "Carl, kill_sunring")
eq(M.owns(30, "kill_sunring"), true, "/cosmetic grants")
registered["/cosmetic"].onSay(gm, "/cosmetic", "Carl, kill_sunring, revoke")
eq(M.owns(30, "kill_sunring"), false, "/cosmetic revokes")

-- the client side files exist
for _, f in ipairs({"game_cosmetics/game_cosmetics.otmod", "game_cosmetics/cosmetics.lua", "game_cosmetics/cosmeticslogic.lua"}) do
	eq(readFile("../client/overlay/modules/" .. f) ~= nil, true, "client " .. f)
end

print(string.format("cosmetics_test: %d checks OK", n))
