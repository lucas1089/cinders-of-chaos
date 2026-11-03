-- Run from the server/ folder: luajit tests/wandering_merchant_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- The Wandering Merchant NPC (data/npc/scripts/wandering_merchant.lua) against a mocked NPC system and DB: every
-- configured item is buyable, and a seasonBlocked item (the double experience potion) is refused to a character of a
-- running season, in the trade window and by "buy <name>", while standard and migrated characters can buy it.
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end

local cfg = dofile("data/scripts/chaos/invasion_config.lua")
local items = cfg.worldEvents.merchant.items
local potion
for _, it in ipairs(items) do
	if it.id == 28095 then
		potion = it
	end
end
ok(potion and potion.seasonBlocked == true, "the double experience potion is seasonBlocked")

-- ------------------------------------------------------------------ mocks
local said, cancels, buyable, nodes, callbacks = {}, {}, {}, {}, {}
KeywordHandler = {}
function KeywordHandler:new()
	return setmetatable({}, {__index = {addKeyword = function(_, keys, cb)
		nodes[#nodes + 1] = {keys = keys, cb = cb}
	end}})
end
NpcHandler = {}
function NpcHandler:new()
	return setmetatable({}, {__index = {
		addModule = function() end,
		setCallback = function(_, id, fn) callbacks[id] = fn end,
		say = function(_, text, cid) said[#said + 1] = {cid = cid, text = text} end,
		isFocused = function() return true end
	}})
end
NpcSystem = {parseParameters = function() end}
ShopModule = {}
local shopRef
local saleOk = true
function ShopModule:new()
	shopRef = {addBuyableItem = function(_, names, id, price)
		buyable[#buyable + 1] = {name = names[1], id = id, price = price}
		nodes[#nodes + 1] = {keys = {"buy", names[1]}, shop = true}
	end,
	callbackOnBuy = function() return saleOk end}
	return shopRef
end
FocusModule = {new = function() return {} end}
CALLBACK_ONBUY = 10
shop_npcuid = {}

local seasonRows = {} -- guid -> {season, migrated_at}
local config = {} -- server_config
local results, nextId = {}, 0
db = {
	escapeString = function(s) return "'" .. tostring(s) .. "'" end,
	storeQuery = function(q)
		local guid = tonumber(q:match("`player_id` = (%d+)"))
		local row
		if guid then
			row = seasonRows[guid]
		else
			local key = q:match("`config` = '([^']+)'")
			row = config[key] and {value = config[key]}
		end
		if not row then
			return false
		end
		nextId = nextId + 1
		results[nextId] = row
		return nextId
	end
}
result = {
	getNumber = function(id, k) return tonumber(results[id][k]) or 0 end,
	getString = function(id, k) return tostring(results[id][k]) end,
	free = function(id) results[id] = nil end
}
local players = {}
function Player(cid)
	return players[cid]
end
local function makePlayer(cid, guid)
	local store = {}
	players[cid] = {
		store = store,
		getStorageValue = function(_, k) return store[k] or -1 end,
		setStorageValue = function(_, k, v) store[k] = v end,
		getGuid = function() return guid end,
		sendCancelMessage = function(_, text) cancels[#cancels + 1] = text end
	}
end

dofile("data/npc/scripts/wandering_merchant.lua")

-- ------------------------------------------------------------------ the shop
ok(#buyable == #items, "every configured item is buyable")
ok(type(callbacks[CALLBACK_ONBUY]) == "function", "trade window callback set")
local guardIndex, shopIndex
for i, n in ipairs(nodes) do
	if n.keys[2] == potion.name then
		if n.shop then
			shopIndex = i
		else
			guardIndex = i
		end
	end
end
ok(guardIndex and shopIndex and guardIndex < shopIndex, "the season guard node comes before the shop's buy node")

-- season 1 running (override), three characters: standard, season, migrated season
local now = os.time()
config["chaos_season_1_start"] = tostring(now - 3600)
config["chaos_season_1_end"] = tostring(now + 86400)
makePlayer(1, 101)
makePlayer(2, 102)
seasonRows[102] = {season = 1, migrated_at = 0}
makePlayer(3, 103)
seasonRows[103] = {season = 1, migrated_at = now - 60}

local onBuy = callbacks[CALLBACK_ONBUY]
ok(onBuy(1, 28095) == true, "standard character buys the potion")
ok(#said == 0, "no refusal for a standard character")
ok(onBuy(2, 28095) == false, "season character is refused the potion")
ok(#said == 1 and said[1].text:find("Season characters") ~= nil, "the NPC says why")
ok(#cancels == 1, "and a cancel message")
ok(onBuy(2, 29856) == true, "season character still buys orbs")
ok(onBuy(3, 28095) == true, "migrated season character buys the potion")

local guard = nodes[guardIndex].cb
ok(guard(2, "buy double experience potion") == true, "spoken buy refused for the season character")
ok(guard(1, "buy double experience potion") == true, "O399: a spoken buy is sent to the trade window (the limit lives there)")
ok(said[#said].text:find("trade") ~= nil, "the NPC says to trade")

-- no running season: everybody buys
config["chaos_season_1_end"] = tostring(now - 1)
ok(onBuy(2, 28095) == true, "after the season ends the potion is sold")

-- O399: one of each per character and stop
local m = cfg.worldEvents.merchant
ok(m.resident == true and m.moveHours == 3 and m.perStop == 1, "resident, moves every 3 hours, one of each")
ok(#items <= 10 and m.storageBase == 7103070, "the items fit the storage block 7103070 - 7103079")
local orb = items[1]
ok(orb.price >= 100000, "the orb of upheaval costs 100k or more")
makePlayer(4, 104)
ok(onBuy(4, orb.id, 1, 2) == false, "two at once are refused")
ok(said[#said].text:find("One of each") ~= nil, "the NPC says one of each")
ok(onBuy(4, orb.id, 1, 1) == true, "one is fine")
-- the shop's sale marks the item (the wrapped callbackOnBuy)
local shop = shopRef
ok(shop and shop.callbackOnBuy ~= nil, "the shop's buy callback is wrapped")
if shop and shop.callbackOnBuy then
	ok(shop:callbackOnBuy(4, orb.id, 1, 1) == true, "the sale goes through")
	ok(onBuy(4, orb.id, 1, 1) == false, "a second one in the same stop is refused")
	ok(said[#said].text:find("move on in") ~= nil, "the NPC says when he moves on")
	ok(onBuy(4, items[2].id, 1, 1) == true, "another item is still fine")
	saleOk = false
	ok(shop:callbackOnBuy(4, items[2].id, 1, 1) == false, "a failed sale (no gold)")
	ok(onBuy(4, items[2].id, 1, 1) == true, "does not count")
	-- the next stop: the mark is for the old one
	local period = m.moveHours * 3600
	players[4].store[m.storageBase] = math.floor(os.time() / period)
	ok(onBuy(4, orb.id, 1, 1) == true, "a mark of the previous stop does not count")
end

print(string.format("wandering merchant tests: %d checks, %d failed", checks, fails))
if fails > 0 then
	os.exit(1)
end
