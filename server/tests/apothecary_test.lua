-- Run from the server/ folder: luajit tests/apothecary_test.lua (and lua5.3; CI runs both)
-- Veyra the Apothecary, the hub's supplies seller (apothecary_config.lua, apothecary.lua, data/npc/Veyra the
-- Apothecary.xml, data/npc/scripts/veyra_the_apothecary.lua; server/README.md "The Apothecary"). Checks: the XML shop
-- lists against the config; every price against the rules (no gold loop with the item price table, runes at the rune
-- supply's price, potions at the hunt supplies' base price or above, the store packs stay the bulk way); her stall in the
-- hub; the NPC script's level gate and talk on a mocked NPC library; the startup placement on a mocked engine.
local checks, failures = 0, 0
local function check(cond, label)
	checks = checks + 1
	if not cond then
		failures = failures + 1
		print("FAIL " .. label)
	end
end
local function eq(a, b, label)
	check(a == b, label .. " (" .. tostring(a) .. " ~= " .. tostring(b) .. ")")
end

local function fileText(path)
	local fh = io.open(path, "rb")
	if not fh then
		return nil
	end
	local text = fh:read("*a")
	fh:close()
	return text
end

local cfg = dofile("data/scripts/chaos/apothecary_config.lua")
local NAME = "Veyra the Apothecary"
eq(cfg.npc, NAME, "the NPC's name")
eq(cfg.towns[1], 2, "the main city")
eq(#cfg.towns, 1, "the main city only")

-- ---------------------------------------------------------------- the XML
local xml = fileText("data/npc/" .. NAME .. ".xml")
check(xml ~= nil, "the NPC's XML")
xml = xml or ""
check(xml:find('<npc name="' .. NAME .. '"', 1, true) ~= nil, "the XML names her")
check(xml:find('walkinterval="0"', 1, true) ~= nil, "she does not walk away from her stall")
local scriptName = xml:match('script="([^"]+)"')
check(scriptName ~= nil and fileText("data/npc/scripts/" .. tostring(scriptName)) ~= nil, "her script exists: " .. tostring(scriptName))

local function list(key)
	local value = xml:match('key="' .. key .. '"%s+value="([^"]*)"') or ""
	local out = {}
	for entry in value:gmatch("[^;]+") do
		local name, id, price = entry:match("^%s*(.-)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
		if name then
			out[#out + 1] = {name = name, id = tonumber(id), price = tonumber(price)}
		else
			check(false, key .. ": a malformed entry: " .. entry)
		end
	end
	return out
end
local buyable, sellable = list("shop_buyable"), list("shop_sellable")
local byId = {}
for _, e in ipairs(buyable) do
	check(byId[e.id] == nil, "sold once: " .. e.name)
	byId[e.id] = e
end

-- the XML is the config: every potion, rune and basic once, at the same price, and nothing else
local R = dofile("data/lib/chaos_rune_supply.lua")
local runeById = {}
for _, r in ipairs(R.runes) do
	runeById[r.id] = r
end
local expected, n = {}, 0
for _, p in ipairs(cfg.potions) do
	expected[p.id] = {name = p.name, price = p.price}
	n = n + 1
end
for _, id in ipairs(cfg.runes) do
	local r = runeById[id]
	check(r ~= nil, "rune " .. id .. " is a rune of the supply table")
	if r then
		expected[id] = {name = r.name, price = r.price}
		n = n + 1
	end
end
for _, b in ipairs(cfg.basics) do
	expected[b.id] = {name = b.name, price = b.price}
	n = n + 1
end
eq(#buyable, n, "the XML sells exactly the config's goods")
for id, e in pairs(expected) do
	local x = byId[id]
	check(x ~= nil, "the XML sells " .. e.name .. " (" .. id .. ")")
	if x then
		eq(x.price, e.price, "XML price of " .. e.name)
		eq(x.name:lower(), e.name:lower(), "XML name of " .. id)
	end
end
eq(#sellable, #cfg.flasks, "she buys the three old flasks")
for i, f in ipairs(cfg.flasks) do
	local x = sellable[i]
	check(x ~= nil and x.id == f.id and x.price == f.price, "she buys flask " .. f.id .. " at " .. f.price)
end

-- ---------------------------------------------------------------- the goods
local potionIds = dofile("data/scripts/chaos/cooldown_channels_config.lua").potionIds
local isPotion = {}
for _, id in ipairs(potionIds) do
	isPotion[id] = true
end
local supplies = dofile("data/scripts/chaos/hunt_supplies.lua")
local P
dofile("data/lib/chaos_item_prices.lua")
P = ChaosItemPrices

local tier = {}
for _, p in ipairs(cfg.potions) do
	check(isPotion[p.id], p.name .. " is a potion of the cooldown channels' list")
	check(p.level >= 0 and p.level == math.floor(p.level), p.name .. ": a whole level")
	tier[p.id] = p
	-- not below what the cheapest base NPC asked (hunt_supplies: the lowest asking price per potion)
	if supplies[p.id] then
		check(p.price >= supplies[p.id], p.name .. " is not below the base price " .. supplies[p.id])
	end
end
-- the health / mana tiers by name keep their order of price and level
local function priceOf(id) return tier[id].price end
check(priceOf(7618) < priceOf(7588) and priceOf(7588) < priceOf(7591) and priceOf(7591) < priceOf(8473) and
	priceOf(8473) < priceOf(26031), "health potions cost more with each tier")
check(priceOf(7620) < priceOf(7589) and priceOf(7589) < priceOf(7590) and priceOf(7590) < priceOf(26029),
	"mana potions cost more with each tier")
check(tier[7618].level <= tier[7588].level and tier[7588].level <= tier[7591].level and tier[7591].level <= tier[8473].level and
	tier[8473].level <= tier[26031].level, "health potions need more level with each tier")
-- every health, mana and spirit potion tier of the store packs and the milestone gifts is on sale
for _, id in ipairs({7618, 7620, 7588, 7589, 7591, 7590, 8472, 8473, 26029, 26030, 26031}) do
	check(byId[id] ~= nil, "potion " .. id .. " is sold")
end

-- no gold loop: she asks at least twice what any NPC pays for the item (the item price table's buyShare), and a flask
-- is bought at the table's price
local share = P.data.buyShare or 0.5
for id, e in pairs(byId) do
	local sell = P.basePrice(id)
	if sell and sell > 0 then
		check(e.price >= sell / share, e.name .. ": asks " .. e.price .. ", an NPC pays " .. sell)
	end
end
for _, f in ipairs(cfg.flasks) do
	eq(P.basePrice(f.id), f.price, "the table pays the same for flask " .. f.id)
end
for _, f in ipairs(sellable) do
	check(byId[f.id] == nil, "a flask is bought, never sold")
end

-- the store's potion packs stay the bulk way: a pack of 100 is worth at least 800 gold a coin at her single price
-- (shop_config.lua: "about 800 gold a coin"), and the single prices are the ones the packs are built on
local shopText = fileText("data/scripts/chaos/shop_config.lua") or ""
local packs = 0
-- POTION_PACKS rows: {potion id, coins for 100, plural name, ...}; bigger packs only get cheaper per potion
for id, cost in shopText:gmatch('\n%s*{(%d+), (%d+), "[%w ]*Potions"') do
	local count
	id, count, cost = tonumber(id), 100, tonumber(cost)
	if tier[id] then
		packs = packs + 1
		check(tier[id].price * count / cost >= 800, "store pack of " .. tier[id].name .. " (" .. cost .. " coins) is not a better deal than gold here")
	end
end
eq(packs, 6, "the six potion packs of the store were found")

-- ---------------------------------------------------------------- her stall in the hub
local booths = dofile("data/scripts/chaos/npc_booths_config.lua").booths
local stall
for _, b in ipairs(booths) do
	if b.npc == NAME then
		stall = b
	end
end
check(stall ~= nil, "she has a stall in the hub")
if stall then
	eq(stall.z, 7, "on the hub's floor")
	check(stall.x >= 31620 and stall.x <= 31675 and (stall.y == 32230 or stall.y == 32236), "inside the market of the hub")
end

-- ---------------------------------------------------------------- the NPC script on a mocked NPC library
local said, callbacks, modules = {}, {}, {}
local playerLevel = 1
KeywordHandler = {new = function() return {} end}
NpcHandler = {new = function()
	local h = {}
	function h:setCallback(kind, fn) callbacks[kind] = fn end
	function h:say(text) said[#said + 1] = text end
	function h:isFocused() return true end
	function h:addModule(m) modules[#modules + 1] = m end
	function h:getMessage() return nil end
	function h:setMessage() end
	function h:getCallback() return nil end
	return h
end}
NpcSystem = {parseParameters = function() end}
ShopModule = {new = function() return {name = "shop"} end}
FocusModule = {new = function() return {name = "focus"} end}
CALLBACK_MESSAGE_DEFAULT, CALLBACK_ONBUY, CALLBACK_GREET, CALLBACK_FAREWELL = 1, 2, 3, 4
CALLBACK_CREATURE_DISAPPEAR, CALLBACK_ONTRADEREQUEST = 5, 6
MESSAGE_GREET, MESSAGE_FAREWELL, MESSAGE_WALKAWAY, MESSAGE_SENDTRADE = 1, 2, 3, 4
Player = function() return {getLevel = function() return playerLevel end} end
ChaosNpcFocus = {hears = function() return true end}
ChaosI18n = {
	npcText = function(_, key, ...) return select("#", ...) > 0 and string.format(key, ...) or key end,
	npcMessages = function() end
}
dofile("data/npc/scripts/veyra_the_apothecary.lua")
eq(#modules, 2, "the shop module and the focus module")
check(type(callbacks[CALLBACK_ONBUY]) == "function", "the level gate")
check(type(callbacks[CALLBACK_MESSAGE_DEFAULT]) == "function", "the talk")

playerLevel = 20
eq(callbacks[CALLBACK_ONBUY](1, 7618, 0, 5), true, "a level 20 buys health potions")
eq(callbacks[CALLBACK_ONBUY](1, 2120, 0, 1), true, "and a rope")
eq(callbacks[CALLBACK_ONBUY](1, 7588, 0, 1), false, "but not a strong health potion (level 50)")
check(said[#said] and said[#said]:find("level 50", 1, true) ~= nil, "she says the level: " .. tostring(said[#said]))
eq(callbacks[CALLBACK_ONBUY](1, 26031, 0, 1), false, "nor a supreme health potion")
check(said[#said]:find("level 200", 1, true) ~= nil, "she says level 200")
playerLevel = 200
eq(callbacks[CALLBACK_ONBUY](1, 26031, 0, 1), true, "a level 200 buys the supreme one")
eq(callbacks[CALLBACK_ONBUY](1, 32085, 0, 1), true, "the Everfull potion (added by the installer) has no gate")
-- every gated potion refuses a buyer one level below and sells at its level
for _, p in ipairs(cfg.potions) do
	if p.level > 0 then
		playerLevel = p.level - 1
		eq(callbacks[CALLBACK_ONBUY](1, p.id, 0, 1), false, p.name .. " refused one level below")
		playerLevel = p.level
		eq(callbacks[CALLBACK_ONBUY](1, p.id, 0, 1), true, p.name .. " sold at its level")
	end
end

local say = callbacks[CALLBACK_MESSAGE_DEFAULT]
said = {}
eq(say(1, 1, "buy great mana potion"), false, "buying is the shop module's, not hers")
eq(say(1, 1, "trade"), false, "so is the trade window")
eq(say(1, 1, "job"), true, "she tells her job")
eq(say(1, 1, "potions"), true, "and about potions")
eq(say(1, 1, "empty flask"), true, "and about flasks")
eq(say(1, 1, "weather"), false, "anything else is for the library")
eq(#said, 3, "three answers")

-- every line she says, and her XML lines, have a pt-BR text
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local lines = 0
for key in (fileText("data/npc/scripts/veyra_the_apothecary.lua") or ""):gmatch('t%(cid,%s*"([^"\n]*)"') do
	lines = lines + 1
	check(pt[key] ~= nil, "pt-BR for: " .. key)
end
for value in xml:gmatch('key="message_%w+" value="([^"]*)"') do
	lines = lines + 1
	check(pt[value] ~= nil, "pt-BR for: " .. value)
end
check(lines >= 8, "her lines were found (" .. lines .. ")")

-- ---------------------------------------------------------------- the placement at startup
local placed = {}
ChaosNpcPlace = {place = function(name, temple, offsets)
	placed[#placed + 1] = name .. "@" .. temple.id
	return true
end}
Chaos = Chaos or {}
Town = function(id) return {getTemplePosition = function() return {id = id} end} end
local startups = {}
GlobalEvent = function() local ev = {} function ev:register() startups[#startups + 1] = self end return ev end
addEvent = function(fn) fn() return 1 end
dofile("data/scripts/chaos/apothecary.lua")
eq(#startups, 1, "one startup event")
startups[1].onStartup()
eq(#placed, 1, "one apothecary")
eq(placed[1], NAME .. "@2", "in the main city")
ChaosNpcPlace.place = function() return nil end
eq(ChaosApothecary.place(), 0, "a failed placement is not counted")

print(string.format("apothecary_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
