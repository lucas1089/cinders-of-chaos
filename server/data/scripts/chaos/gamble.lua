-- The Gambler (client game_gamble, extended opcode ChaosOpcodes.gamble = 199): sealed equipment for gold. Each character
-- sees a stock of its own (about 14 pieces: the base type, the slot and the item level shown, the rarity hidden), new at
-- fixed times every 4 hours (00:00, 04:00, ... server time, gamble_config.lua refresh). The stock comes from a seed of the
-- character and the window, so it is the same after a relog or a restart; the window, the level and vocation it was
-- made for, the sold slots and the early refreshes are five player storages (7101900 - 7101904). Buying takes the gold,
-- marks the slot sold and saves the character (Chaos.saveCharacter: the shared "save before a database credit" rule),
-- and only then rolls the rarity with the loot layer's own API (ChaosLoot.stockRarity / upgradeRarity, as monster
-- drops) and forges the piece at its item level (ChaosCrafting.createItem). Numbers: gamble_config.lua; pure logic:
-- gamble_core.lua (tests: server/tests/gamble_test.lua); overview: server/README.md "The Gambler".
--
-- What a character can use: the pool of gamble_config.lua, filtered by the installed data/movements/movements.xml (Equip
-- entries: level, vocations) and data/weapons/weapons.xml (level, vocations), read once; no charges, no duration, no
-- uniques, gear only.
--
-- Protocol (JSON {action, data}; state with Chaos.sendChunked):
--   client -> server  open | close | buy {i, w, id} | reroll {w}
--   server -> client  state {w, items = {{i, id, c, n, s, sn, l, p, sold}}, level, gate, near, money, left, hours, at, tz,
--                     reroll, rerolls, rerollMax, odds = {{r, n, p}}, npc, last} (K.payload)
--                     | result {ok, text, reveal = {r, rn, id, c, n, l, s}} | npc {} (the Gambler's NPC script)
-- Lua 5.1 / LuaJIT.

if not ChaosRarity then
	dofile("data/lib/chaos_rarity.lua")
end

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/gamble_core.lua")
if not ChaosNpcPlace then
	dofile("data/scripts/chaos/npc_place.lua")
end

Chaos.gambleConfig = dofile("data/scripts/chaos/gamble_config.lua")
local cfg = Chaos.gambleConfig
local K = ChaosGambleCore
local OPCODE = ChaosOpcodes.gamble or cfg.opcode
local ST = Chaos.storage.gamble or cfg.storage

ChaosGamble = ChaosGamble or {}
local P = ChaosGamble
P.cfg = cfg
P.cache = P.cache or {} -- guid -> {key, stock}
P.busy = P.busy or {} -- guid -> true while a purchase runs
P.last = P.last or {} -- guid -> the last reveal (for the window, until logout)
P.open = P.open or {} -- guid -> the window is open
P.clockShift = P.clockShift or 0 -- seconds added to the clock (tests, /gamble staff checks)

local function log(text)
	print("[Chaos gamble] " .. text)
end

local function try(name, fn, ...)
	local ok, res = pcall(fn, ...)
	if not ok then
		log(name .. ": " .. tostring(res))
		return nil
	end
	return res
end

local function now()
	return os.time() + (P.clockShift or 0)
end

local function rarityNames() -- by place: Common .. Divine
	return ChaosRarity.storedNames()
end

local function rarityName(r) -- r = a stored id
	return ChaosRarity.name(r) or ("Rarity " .. tostring(r))
end

local function itemName(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	return ok and name and name ~= "" and name or ("item " .. tostring(id))
end

-- ---------------------------------------------------------------- who can use what (movements.xml, weapons.xml)
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local function addRule(rules, id, level, vocs)
	local r = rules[id]
	if not r then
		r = {level = 0}
		rules[id] = r
	end
	r.level = math.max(r.level, level or 0)
	if vocs then
		-- an item listed in both files: the vocations of both must allow it
		if r.vocs then
			local both = {}
			for v in pairs(vocs) do
				if r.vocs[v] then
					both[v] = true
				end
			end
			r.vocs = both
		else
			r.vocs = vocs
		end
	end
end

local function vocationsOf(body)
	local vocs
	for name in (body or ""):gmatch('<vocation%s+name="([^"]+)"') do
		vocs = vocs or {}
		vocs[name:lower()] = true
	end
	return vocs
end

-- id -> {level, vocs = {lower-case name = true} or nil (everyone)}; from the text of movements.xml and weapons.xml
function P.parseRules(movements, weapons)
	local rules = {}
	-- movevents: <movevent event="Equip" itemid="N" | fromid="A" toid="B" slot=".." level="L" ...> <vocation .../> </movevent>
	local pos = 1
	local text = movements or ""
	while true do
		local s, e, attrs, close = text:find("<movevent%s+([^>]-)(/?)>", pos)
		if not s then
			break
		end
		local body = ""
		pos = e + 1
		if close ~= "/" then
			local cs, ce = text:find("</movevent>", pos, true)
			if cs then
				body = text:sub(pos, cs - 1)
				pos = ce + 1
			end
		end
		if attrs:find('event="Equip"', 1, true) then
			local level = tonumber(attrs:match('%f[%w]level="(%d+)"')) or 0
			local vocs = vocationsOf(body)
			local one = tonumber(attrs:match('itemid="(%d+)"'))
			local from, to = attrs:match('fromid="(%d+)"%s+toid="(%d+)"')
			if one then
				addRule(rules, one, level, vocs)
			elseif from then
				for id = tonumber(from), math.min(tonumber(to), tonumber(from) + 2000) do
					addRule(rules, id, level, vocs)
				end
			end
		end
	end
	-- weapons: <melee|distance|wand id="N" level="L" ...> <vocation .../> </...>
	text = weapons or ""
	pos = 1
	while true do
		local s, e, tag, attrs, close = text:find("<(%a+)%s+([^>]-)(/?)>", pos)
		if not s then
			break
		end
		pos = e + 1
		if tag == "melee" or tag == "distance" or tag == "wand" then
			local body = ""
			if close ~= "/" then
				local cs, ce = text:find("</" .. tag .. ">", pos, true)
				if cs then
					body = text:sub(pos, cs - 1)
					pos = ce + 1
				end
			end
			local id = tonumber(attrs:match('%f[%w]id="(%d+)"'))
			if id then
				addRule(rules, id, tonumber(attrs:match('%f[%w]level="(%d+)"')) or 0, vocationsOf(body))
			end
		end
	end
	return rules
end

function P.rules()
	if not P.ruleTable then
		P.ruleTable = P.parseRules(readFile("data/movements/movements.xml"), readFile("data/weapons/weapons.xml"))
	end
	return P.ruleTable
end

local function typeOk(id)
	P.typeOk = P.typeOk or {}
	local v = P.typeOk[id]
	if v ~= nil then
		return v
	end
	v = false
	local ok, res = pcall(function()
		local it = ItemType(id)
		if not it or it:getId() == 0 or it:isStackable() then
			return false
		end
		for _, m in ipairs({"getCharges", "getDuration"}) do
			if it[m] and (tonumber(it[m](it)) or 0) > 0 then
				return false
			end
		end
		return true
	end)
	v = ok and res or false
	if v and ChaosLoot and ChaosLoot.isGearId then
		v = ChaosLoot.isGearId(id) and true or false
	end
	if v then
		if not P.uniqueIds then
			P.uniqueIds = {}
			for _, u in ipairs(ChaosLoot and ChaosLoot.uniqueList and ChaosLoot.uniqueList() or {}) do
				P.uniqueIds[u.id] = true
			end
		end
		v = not P.uniqueIds[id]
	end
	P.typeOk[id] = v
	return v
end

-- the equipment set pieces on offer (none while ChaosGearSets.PAIR28 or cfg.sets.enabled is off)
function P.setEntries()
	if not ChaosGearSets then
		local ok, G = pcall(dofile, "data/lib/chaos_gear_sets.lua")
		ChaosGearSets = ok and G or nil
	end
	return K.setEntries(cfg, ChaosGearSets)
end

-- canUse(id, slot) for a character of this level and vocation name
function P.canUseFor(level, vocName)
	local rules = P.rules()
	vocName = tostring(vocName or ""):lower()
	return function(id)
		if not typeOk(id) then
			return false
		end
		local r = rules[id]
		if not r then
			return true
		end
		if r.level > level then
			return false
		end
		return r.vocs == nil or r.vocs[vocName] == true
	end
end

-- the item level gate of a character level (the drops' own curve)
function P.gate(level)
	if ChaosItemMods and ChaosItemMods.sourceLevel then
		return ChaosItemMods.sourceLevel({monsterLevel = level, tier = cfg.itemLevel.tier})
	end
	return 1
end

-- ---------------------------------------------------------------- the character's window (storages)
local function vocationOf(player)
	local ok, id, name = pcall(function()
		local v = player:getVocation()
		return v:getId(), v:getName()
	end)
	if ok then
		return id, name
	end
	return 0, ""
end

local function vocationName(id)
	local ok, name = pcall(function() return Vocation(id):getName() end)
	return ok and name or ""
end

-- the window the character is in now; a new window takes a new snapshot of the level and vocation
function P.snapshot(player)
	local t = now()
	local offset = K.offset(cfg, t)
	local w = K.window(cfg, t, offset)
	if player:getStorageValue(ST) ~= w then
		local vocId = vocationOf(player)
		player:setStorageValue(ST + 1, player:getLevel())
		player:setStorageValue(ST + 2, vocId)
		player:setStorageValue(ST + 3, 0)
		player:setStorageValue(ST + 4, 0)
		player:setStorageValue(ST, w)
	end
	local S = {
		t = t, offset = offset, window = w, level = math.max(1, player:getStorageValue(ST + 1)),
		voc = player:getStorageValue(ST + 2), mask = math.max(0, player:getStorageValue(ST + 3)),
		rerolls = math.max(0, player:getStorageValue(ST + 4))
	}
	S.gate = P.gate(S.level)
	return S
end

function P.stockOf(player, S)
	S = S or P.snapshot(player)
	local guid = player:getGuid()
	local key = table.concat({S.window, S.rerolls, S.level, S.voc}, ":")
	local c = P.cache[guid]
	if c and c.key == key then
		return c.stock, S
	end
	local stock = K.stock(cfg, {guid = guid, window = S.window, rerolls = S.rerolls, level = S.level, gate = S.gate,
		sets = P.setEntries(), canUse = P.canUseFor(S.level, vocationName(S.voc))})
	P.cache[guid] = {key = key, stock = stock}
	return stock, S
end

-- ---------------------------------------------------------------- money and the NPC
local function money(player)
	local ok, v = pcall(function()
		return Chaos.totalMoney(player)
	end)
	return ok and tonumber(v) or 0
end

local function takeMoney(player, amount)
	return Chaos.pay(player, amount) and true or false
end

local function refund(player, amount)
	player:setBankBalance(player:getBankBalance() + amount)
end

function P.near(player)
	local r = cfg.npc.range
	local name = cfg.npc.name:lower()
	for _, c in ipairs(Game.getSpectators(player:getPosition(), false, false, r, r, r, r) or {}) do
		if c:isNpc() and c:getName():lower() == name then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------- the window
P.oddsTable = nil
function P.odds()
	if not P.oddsTable and ChaosLootConfig and ChaosLootConfig.gear then
		P.oddsTable = K.odds(cfg, ChaosLootConfig.gear)
	end
	return P.oddsTable
end

-- the client id of a server item id (cached; 0 when the item type has none). The reveal asks it too: a purchase can
-- come before this server process sent that stock (a restart while the window stayed open).
function P.clientId(id)
	P.cid = P.cid or {}
	P.names = P.names or {}
	if not P.cid[id] then
		local ok, cid = pcall(function() return ItemType(id):getClientId() end)
		cid = ok and tonumber(cid) or 0
		P.cid[id] = (cid >= 1 and cid <= 65535) and cid or 0
		P.names[id] = itemName(id)
	end
	return P.cid[id]
end

function P.send(player)
	local stock, S = P.stockOf(player)
	for _, e in ipairs(stock) do
		P.clientId(e.id)
	end
	local view = {stock = stock, mask = S.mask, window = S.window, now = S.t, offset = S.offset, level = S.level,
		gate = S.gate, rerolls = S.rerolls, near = P.near(player), money = money(player), names = P.names, cids = P.cid,
		odds = P.odds(), rarityNames = rarityNames(), last = P.last[player:getGuid()]}
	Chaos.sendChunked(player, OPCODE, json.encode({action = "state", data = K.payload(cfg, view)}))
end

local function result(player, ok, text, reveal)
	Chaos.send(player, OPCODE, "result", {ok = ok and true or false, text = text, reveal = reveal})
	if text and text ~= "" then
		player:sendTextMessage(ok and (MESSAGE_INFO_DESCR or MESSAGE_STATUS_DEFAULT) or (MESSAGE_STATUS_SMALL or MESSAGE_STATUS_DEFAULT), text)
	end
	return ok
end

-- ---------------------------------------------------------------- buying
local function deliver(player, item)
	if player:addItemEx(item, false) ~= (RETURNVALUE_NOERROR or 0) then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		return true
	end
	return false
end

local function rollRarity()
	local L = ChaosLoot
	if not (L and L.stockRarity and L.upgradeRarity) then
		return cfg.odds.floor
	end
	return K.rollRarity(cfg, L)
end

local function makeItem(id, rarity, ilvl)
	local item
	if ChaosCrafting and ChaosCrafting.createItem then
		item = ChaosCrafting.createItem(id, rarity, ilvl)
	else
		item = Game.createItem(id, 1)
	end
	if item and ChaosGems and ChaosGems.rollDropSockets then
		pcall(ChaosGems.rollDropSockets, item)
	end
	return item
end

local function buyNow(player, d)
	local stock, S = P.stockOf(player)
	local guid = player:getGuid()
	local ok, text, e = K.checkBuy(cfg, {enabled = cfg.enabled, stock = stock, mask = S.mask, slot = d.i,
		window = S.window, want = {w = d.w, id = d.id}, money = money(player), near = P.near(player)}) -- P.buy holds the lock
	if not ok then
		return result(player, false, text)
	end
	-- 1. the gold, 2. the sold mark, 3. the save; only then the roll and the item
	if not takeMoney(player, e.price) then
		return result(player, false, string.format("You need %s gold for that crate.", K.fmt(e.price)))
	end
	player:setStorageValue(ST + 3, K.markSold(S.mask, e.i))
	if not Chaos.saveCharacter(player) then
		player:setStorageValue(ST + 3, S.mask)
		refund(player, e.price)
		return result(player, false, "The deal could not be written down. Your gold is in your bank account; try again.")
	end
	local rarity = rollRarity()
	local item = makeItem(e.id, rarity, e.ilvl)
	if not item then
		player:setStorageValue(ST + 3, S.mask)
		refund(player, e.price)
		Chaos.saveCharacter(player)
		log("could not create item " .. e.id .. " for " .. player:getName() .. "; refunded " .. e.price)
		return result(player, false, "That crate was empty. Your gold is in your bank account.")
	end
	local inbox = deliver(player, item)
	Chaos.saveCharacter(player)
	local name = itemName(e.id)
	local reveal = {r = rarity, rn = rarityName(rarity), id = e.id, c = P.clientId(e.id), n = name, l = e.ilvl,
		s = e.slot, i = e.i}
	P.last[guid] = reveal
	local line = string.format("The seal breaks: a [%s] %s (item level %d) for %s gold.%s", rarityName(rarity), name, e.ilvl,
		K.fmt(e.price), inbox and " Your backpack is full: it went to your inbox." or "")
	if cfg.announceFrom and rarity >= cfg.announceFrom then
		local around = Game.getSpectators(player:getPosition(), false, true, 8, 8, 6, 6) or {}
		for _, p in ipairs(around) do
			if p ~= player then
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR,
					Chaos.t(p, "%s opened a [%s] %s at the Gambler!", player:getName(), rarityName(rarity), name))
			end
		end
	end
	return result(player, true, line, reveal)
end

function P.buy(player, d)
	local guid = player:getGuid()
	if P.busy[guid] then
		return result(player, false, "One crate at a time.")
	end
	P.busy[guid] = true
	local ok, res = pcall(buyNow, player, type(d) == "table" and d or {})
	P.busy[guid] = nil
	if not ok then
		log("buy: " .. tostring(res))
		return result(player, false, "The Gambler shakes his head. Try again.")
	end
	return res
end

-- a new stock before the 4-hour mark, for gold (gamble_config.lua reroll)
function P.reroll(player, d)
	if not P.near(player) then
		return result(player, false, "Ask the Gambler in person for fresh crates.")
	end
	local S = P.snapshot(player)
	if type(d) == "table" and d.w and tonumber(d.w) ~= S.window then
		return result(player, false, "The stock has changed. Look again.")
	end
	local price = K.rerollPrice(cfg, S.gate, S.rerolls)
	if not price then
		return result(player, false, string.format("No more fresh crates before %s.", K.clock(cfg, S.window + 1)))
	end
	if money(player) < price or not takeMoney(player, price) then
		return result(player, false, string.format("Fresh crates cost %s gold.", K.fmt(price)))
	end
	player:setStorageValue(ST + 4, S.rerolls + 1)
	player:setStorageValue(ST + 3, 0)
	P.last[player:getGuid()] = nil
	return result(player, true, string.format("Fresh crates for %s gold.", K.fmt(price)))
end

-- ---------------------------------------------------------------- the NPC
function P.placeNpcs()
	local placed, missed = 0, {}
	for _, id in ipairs(cfg.npc.towns) do
		local town = Town(id)
		local temple = town and town:getTemplePosition()
		if temple and try("place npc", ChaosNpcPlace.place, cfg.npc.name, temple, cfg.npc.offsets, cfg.npc.place) then
			placed = placed + 1
		else
			missed[#missed + 1] = tostring(id)
		end
	end
	if #missed > 0 then
		log("no " .. cfg.npc.name .. " in town " .. table.concat(missed, ", ") .. " (no free tile near the temple, or data/npc/" ..
			cfg.npc.name .. ".xml is missing: tools/install_gamble.py)")
	end
	return placed
end

-- ---------------------------------------------------------------- events
local startup = GlobalEvent("ChaosGambleStartup")
function startup.onStartup()
	for _, p in ipairs(K.validate(cfg)) do
		log("config: " .. p)
	end
	if cfg.enabled then
		addEvent(function()
			log(P.placeNpcs() .. " Gambler(s) placed")
		end, cfg.npc.delayMs or 3000)
	end
	return true
end
startup:register()

local login = CreatureEvent("ChaosGambleLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGambleExtended")
	player:registerEvent("ChaosGambleLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosGambleLogout")
function logout.onLogout(player)
	local guid = player:getGuid()
	P.cache[guid], P.last[guid], P.open[guid], P.busy[guid] = nil, nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

local ext = CreatureEvent("ChaosGambleExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE or not cfg.enabled then
		return
	end
	local m = Chaos.decode(buffer)
	if not m or type(m.action) ~= "string" then
		return
	end
	if Chaos.limited(player, "gamble", cfg.requestMs) then
		return
	end
	local d = type(m.data) == "table" and m.data or {}
	local guid = player:getGuid()
	if m.action == "open" then
		P.open[guid] = true
	elseif m.action == "close" then
		P.open[guid] = nil
		return
	elseif m.action == "buy" then
		try("buy", P.buy, player, d)
	elseif m.action == "reroll" then
		try("reroll", P.reroll, player, d)
	else
		return
	end
	try("send", P.send, player)
end
ext:type("extendedopcode")
ext:register()

-- staff: /gamble Name (show the window state), /gamble Name, new (a new stock now, the sold marks cleared),
-- /gamble odds (the rarity table)
local talk = TalkAction("/gamble")
function talk.onSay(player, words, param)
	if player:getGroup():getId() < cfg.staffGroup then
		return false
	end
	if param:match("^%s*odds%s*$") then
		local o = P.odds() or {}
		local parts = {}
		for r = 1, ChaosRarity.rank(cfg.odds.maxRarity) do
			if (o[r] or 0) > 0 then
				parts[#parts + 1] = string.format("%s %.2f%%", rarityNames()[r], o[r] * 100)
			end
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Gamble odds: " .. table.concat(parts, ", "))
		return false
	end
	local name, what = param:match("^%s*([^,]+),%s*(%a+)%s*$")
	local target = Player(name or param:match("^%s*(.-)%s*$"))
	if not target then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "/gamble <online character>[, new] | /gamble odds")
		return false
	end
	if what == "new" then
		target:setStorageValue(ST, -1)
	end
	local stock, S = P.stockOf(target)
	player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s: window %d (level %d, item level gate %d), %d pieces, %d sold, " ..
		"%d early refreshes; next stock at %s.", target:getName(), S.window, S.level, S.gate, #stock, K.soldCount(S.mask, #stock),
		S.rerolls, K.clock(cfg, S.window + 1)))
	if P.open[target:getGuid()] then
		P.send(target)
	end
	return false
end
talk:separator(" ")
talk:register()
