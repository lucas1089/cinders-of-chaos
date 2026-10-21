-- Run from the server/ folder: luajit tests/service_npcs_test.lua (and lua5.3; CI runs both)
-- The service NPCs of the Halls of Services (service_npcs_core.lua, service_npcs_run.lua, service_npcs.lua,
-- data/npc/scripts/chaos_service_npc.lua) on a mocked engine: what each NPC understands, the windows it opens (the module's
-- own opcode), the house broker's rules and purchase, a base command run in the sandbox, the booths that name them, and the
-- NPC script itself answering through a mocked NPC library.
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

local n = 0
setmetatable(_G, {__index = function(t, k)
	if type(k) == "string" and k:match("^[A-Z_0-9]+$") then
		n = n + 1
		rawset(t, k, n)
		return n
	end
end})
loadstring = loadstring or load

dofile("data/scripts/chaos/chaos_constants.lua")
dofile("data/scripts/chaos/service_npcs_core.lua")
local K = ChaosServiceNpcsCore
local cfg = dofile("data/scripts/chaos/service_npcs_config.lua")

-- ---------------------------------------------------------------- the config
eq(#K.validate(cfg), 0, "the config validates")
eq(#cfg.order, 5, "five NPCs")
local expect = {"stash", "pocketboss", "banker", "broker", "services"}
for i, key in ipairs(expect) do
	eq(cfg.order[i], key, "owner order " .. i)
end
local opcodes = {stash = "stash", pocketboss = "bossSpawns", banker = "bank", broker = "info", services = "info"}
for key, opName in pairs(opcodes) do
	eq(cfg.npcs[key].window.opcode, opName, key .. ": the module's own opcode")
	check(ChaosOpcodes[opName] ~= nil, key .. ": the opcode exists")
	local op, json = K.openJson(key, cfg)
	eq(op, opName, key .. ": openJson opcode")
	check(json:find('"action":"', 1, true) ~= nil, key .. ": json has an action")
end
check(cfg.npcs.stash.window.json:find('"make":"Toggle"', 1, true) and cfg.npcs.stash.window.json:find('"open":true', 1, true),
	"the stash opens as the depot locker opens it (Toggle, open)")
check(cfg.npcs.broker.window.json:find('"page":"house"', 1, true), "the broker opens the House page")
check(cfg.npcs.services.window.json:find('"page":"services"', 1, true), "the clerk opens the Services page")
eq(K.openJson("nobody", cfg), nil, "an unknown key opens nothing")

-- no new opcode, storage key or table: the config names none
local f = io.open("data/scripts/chaos/service_npcs_config.lua")
local src = f:read("*a")
f:close()
check(not src:find("Storage", 1, true) and not src:find("CREATE TABLE", 1, true), "no storage key, no table")

-- the booths name them: the two slots, then the rest
local B = dofile("data/scripts/chaos/npc_booths_config.lua")
local booth = {}
for _, row in ipairs(B.rows) do
	for _, b in ipairs(row.booths) do
		-- a name, or {[town] = name} (owner 2026-10-21: in Cinderhold they stand at the temple, the booth is Mirewake's)
		for _, n in pairs(type(b.npc) == "table" and b.npc or {b.npc}) do
			if type(n) == "string" then
				booth[n] = row.key
			end
		end
	end
end
for _, key in ipairs(expect) do
	check(booth[cfg.npcs[key].name] ~= nil, cfg.npcs[key].name .. " has a booth in npc_booths_config.lua")
end
for _, row in ipairs(B.rows) do
	if row.key == "economy_north" then
		eq(row.booths[1].slot, "stash keeper", "the stash keeper takes the first slot")
		eq(row.booths[1].npc[1], cfg.npcs.stash.name, "the slot holds the stash keeper (Mirewake)")
		eq(row.booths[2].slot, "pocket boss NPC", "the pocket boss NPC takes the second slot")
		eq(row.booths[2].npc[1], cfg.npcs.pocketboss.name, "the slot holds the pocket boss NPC (Mirewake)")
	end
end
-- the way in of the economy room (x 49-51) and of the progression room (x 11-13) stays open
for _, row in ipairs(B.rows) do
	if row.key:find("north", 1, true) then
		for _, b in ipairs(row.booths) do
			check(not (b.x >= 48 and b.x <= 52 and row.room == "economy") and not (b.x >= 10 and b.x <= 14 and row.room == "progression"),
				row.key .. ": booth " .. b.x .. " keeps the way in free")
		end
		check(row.counterRow == row.npcRow + 1, row.key .. ": the counter lies in front")
	end
end

-- ---------------------------------------------------------------- what they understand
eq(K.intent("stash", "open my stash"), "open", "stash: open")
eq(K.intent("stash", "who are you"), "job", "stash: job")
eq(K.intent("stash", "banana"), nil, "stash: nothing")
eq(K.intent("pocketboss", "how many charges"), "charges", "pocket boss: charges")
eq(K.intent("pocketboss", "show the bosses"), "open", "pocket boss: bosses")
eq(K.intent("banker", "what is my balance"), "balance", "banker: balance")
eq(K.intent("banker", "i want to deposit"), "open", "banker: deposit")
eq(K.intent("broker", "buy house Ash Lane 1"), "buy", "broker: buy")
eq(K.intent("broker", "leave my house"), "leave", "broker: leave")
eq(K.intent("broker", "sell my house to Ana"), "sell", "broker: sell")
eq(K.intent("broker", "free houses"), "list", "broker: list")
eq(K.intent("broker", "which town"), "towns", "broker: towns")
eq(K.intent("services", "change my name"), "name", "services: name")
eq(K.intent("services", "change vocation"), "vocation", "services: vocation")
eq(K.intent("services", "summon familiar"), "familiar", "services: familiar")
eq(K.intent("services", "plate frame"), "frame", "services: frame")
eq(K.intent("services", "my web shop orders"), "webshop", "services: web shop")
eq(K.intent("nobody", "hi"), nil, "an unknown NPC understands nothing")
eq(K.buyName("buy house Ash Lane 1"), "Ash Lane 1", "buyName strips the house")
eq(K.buyName("I want to buy the Red Door"), "Red Door", "buyName strips the article")
eq(K.buyName("buy"), nil, "buyName: nothing after buy")
eq(K.buyName("sell"), nil, "buyName: no buy")
eq(K.afterWord("Sell my house to Ana", {"sell"}), "my house to Ana", "afterWord")

-- ---------------------------------------------------------------- houses
local houses = {
	{id = 1, name = "Ash Lane 1", town = 2, townName = "Cinderhold", owner = 0, tiles = 20},
	{id = 2, name = "Ash Lane 2", town = 2, townName = "Cinderhold", owner = 0, tiles = 10},
	{id = 3, name = "Red Door", town = 2, townName = "Cinderhold", owner = 77, tiles = 8},
	{id = 4, name = "Mire Hut", town = 1, townName = "Mirewake", owner = 0, tiles = 6}
}
local h, why = K.findHouse(houses, "ash lane 2")
eq(h and h.id, 2, "an exact name, any case")
h, why = K.findHouse(houses, "ash lane")
eq(h, nil, "two houses fit")
eq(why, "many", "many")
h = K.findHouse(houses, "mire")
eq(h and h.id, 4, "one house fits a part of the name")
h, why = K.findHouse(houses, "zzz")
eq(why, "none", "none")
local list, total = K.freeHouses(houses, 2, 6, 1000)
eq(total, 2, "two free in town 2")
eq(list[1].id, 2, "the cheapest first")
eq(#K.freeHouses(houses, 2, 1, 1000), 1, "the list is cut")
local towns = K.townCounts(houses, 8)
eq(#towns, 2, "two towns with a free house")
eq(towns[1].name, "Cinderhold", "most free first")
eq(towns[1].free, 2, "the count")
eq(K.price(20, 1000), 20000, "the price")
eq(K.price(-1, 5), 0, "no negative price")
local ok, reason = K.buyCheck({priceOn = true, premium = true, owner = 0, owns = false, price = 100, money = 100})
eq(ok, true, "buyCheck: all fine")
eq(select(2, K.buyCheck({priceOn = false})), "off", "buyCheck: off")
eq(select(2, K.buyCheck({priceOn = true, premium = false})), "premium", "buyCheck: premium")
eq(select(2, K.buyCheck({priceOn = true, premium = true, owner = 5})), "taken", "buyCheck: taken")
eq(select(2, K.buyCheck({priceOn = true, premium = true, owner = 0, owns = true})), "owns", "buyCheck: owns")
eq(select(2, K.buyCheck({priceOn = true, premium = true, owner = 0, price = 101, money = 100})), "money", "buyCheck: money")
for reasonKey in pairs({off = 1, premium = 1, taken = 1, owns = 1, money = 1}) do
	check(K.TEXT[reasonKey] ~= nil, "text of " .. reasonKey)
end

-- ---------------------------------------------------------------- the engine side
local sent = {}
local Cls = {current = nil} -- the engine's Player class table: every method lives here, as in the engine
local Methods = {}
local function newPlayer(o)
	local p = setmetatable({id = o.id or 1, guid = o.guid or 100, premium = o.premium ~= false, money = o.money or 0, bank = o.bank or 0,
		storage = o.storage or {}, house = o.house, lines = {}}, {__index = Methods})
	return p
end
function Cls:getId() return self.id end
function Cls:getGuid() return self.guid end
function Cls:isPremium() return self.premium end
function Cls:getHouse() return self.house end
function Cls:getTotalMoney() return self.money end
function Cls:removeTotalMoney(g) if self.money < g then return false end self.money = self.money - g return true end
function Cls:getBankBalance() return self.bank end
function Cls:setBankBalance(v) self.bank = v return true end
function Cls:getMoney() return self.money end
function Cls:removeMoney(g) if self.money < g then return false end self.money = self.money - g return true end
function Cls:getStorageValue(k) return self.storage[k] or -1 end
function Cls:sendExtendedOpcode(op, json) sent[#sent + 1] = {op = op, json = json} return true end
function Cls:sendTextMessage(t, text) self.lines[#self.lines + 1] = text end
for name, fn in pairs(Cls) do
	if type(fn) == "function" then Methods[name] = fn end
end
Player = setmetatable(Methods, {__call = function(_, id) return Cls.current and Cls.current.id == id and Cls.current or nil end})

local liveHouses = {}
local function mockHouse(row)
	local hs = {owner = row.owner}
	function hs:getId() return row.id end
	function hs:getName() return row.name end
	function hs:getTown() return {getId = function() return row.town end, getName = function() return row.townName end} end
	function hs:getOwnerGuid() return self.owner end
	function hs:setOwnerGuid(g) self.owner = g end
	function hs:getTileCount() return row.tiles end
	liveHouses[row.id] = hs
	return hs
end
local list2 = {}
for _, row in ipairs(houses) do list2[#list2 + 1] = mockHouse(row) end
Game = {getHouses = function() return list2 end, getReturnMessage = function(v) return "ret" .. tostring(v) end}
House = function(id) return liveHouses[id] end
configManager = {getNumber = function() return 1000 end}
configKeys = {HOUSE_PRICE = 1}

dofile("data/scripts/chaos/service_npcs_run.lua")
local R = ChaosServiceNpcsRun

local p = newPlayer({money = 100000})
Cls.current = p
check(R.open(p, "banker"), "open returns true")
eq(sent[1].op, ChaosOpcodes.bank, "the banker sends on the bank opcode")
eq(sent[1].json, '{"action":"npc","data":{}}', "the bank client's npc action")
R.open(p, "stash")
eq(sent[2].op, ChaosOpcodes.stash, "the stash keeper sends on the stash opcode")
R.open(p, "pocketboss")
eq(sent[3].op, ChaosOpcodes.bossSpawns, "the pocket boss NPC sends on the Boss Spawns opcode")
R.open(p, "broker")
eq(sent[4].op, ChaosOpcodes.info, "the broker sends on the Info & Services opcode")
eq(R.open(p, "nobody"), false, "an unknown key sends nothing")
eq(#sent, 4, "four messages")

eq(R.perSqm(), 1000, "the base config's price per tile")
configManager.getNumber = function() return -1 end
eq(R.perSqm(), nil, "-1 is no sale")
configManager.getNumber = function() return 1000 end
local rows = R.houses()
eq(#rows, 4, "four houses read")
eq(rows[1].townName, "Cinderhold", "the town name")
eq(rows[3].owner, 77, "the owner")

local okBuy, why2, price = R.buyHouse(p, rows[1])
eq(okBuy, true, "bought")
eq(price, 20000, "20 tiles at 1000")
eq(p.money, 80000, "the gold is taken")
eq(liveHouses[1].owner, 100, "the house is the player's")
p.house = liveHouses[1]
okBuy, why2 = R.buyHouse(p, rows[2])
eq(why2, "owns", "a second house is refused")
p.house = nil
okBuy, why2 = R.buyHouse(p, rows[1])
eq(why2, "taken", "a sold house is read again, not from the list")
p.premium = false
okBuy, why2 = R.buyHouse(p, rows[2])
eq(why2, "premium", "premium")
p.premium, p.money = true, 5
okBuy, why2, price = R.buyHouse(p, rows[2])
eq(why2, "money", "money")
eq(price, 10000, "the price comes back")
eq(liveHouses[2].owner, 0, "nothing sold")
eq(p.money, 5, "nothing taken")

-- a base command in the sandbox (a revscript talkaction of a temp file), its text caught
local tmp = os.tmpname()
local fh = io.open(tmp, "w")
fh:write('local t = TalkAction("!demo")\nfunction t.onSay(player, words, param)\n\tplayer:sendTextMessage(1, "hello " .. param .. " " .. words)\n\treturn false\nend\nt:register()\n')
fh:close()
ChaosCommandsCore.BASE.demo = {kind = "rev", words = "!demo", file = tmp, index = 1}
eq(R.runBase(p, "demo", "Ana"), "hello Ana !demo", "the sandboxed base command's text")
eq(#p.lines, 0, "the text was caught, not sent")
eq(R.runBase(p, "nothing"), nil, "an unknown command")
ChaosCommandsCore.BASE.gone = {kind = "rev", words = "!gone", file = tmp .. ".missing"}
eq(R.runBase(p, "gone"), nil, "a missing script is not on this server")
os.remove(tmp)

-- ---------------------------------------------------------------- the NPC script on a mocked NPC library
local said = {}
local callbacks = {}
KeywordHandler = {new = function() return {} end}
NpcSystem = {parseParameters = function() end}
FocusModule = {new = function() return {} end}
NpcHandler = {new = function()
	local h = {messages = {}}
	function h:setCallback(cb, fn) callbacks[cb] = fn end
	function h:getCallback(cb) return callbacks[cb] end
	function h:isFocused() return true end
	function h:say(text, cid) said[#said + 1] = text end
	function h:getMessage(t) return self.messages[t] end
	function h:setMessage(t, m) self.messages[t] = m end
	function h:addModule() end
	return h
end}
ChaosNpcFocus = {hears = function() return true end}

local function talk(key, player, msg)
	said = {}
	callbacks = {}
	sent = {}
	SERVICE_KEY = key
	Cls.current = player
	dofile("data/npc/scripts/chaos_service_npc.lua")
	local cb = callbacks[CALLBACK_MESSAGE_DEFAULT]
	local handled = cb(player.id, 1, msg)
	return handled, said[1]
end

local q = newPlayer({money = 50000, bank = 12345, storage = {[Chaos.storage.nameChangeTokens] = 2}})
local handled, text = talk("stash", q, "open my stash")
eq(handled, true, "stash: handled")
check(text and text:find("stash is open", 1, true), "stash: the answer")
eq(sent[1] and sent[1].op, ChaosOpcodes.stash, "stash: the window opens")
handled = talk("stash", q, "banana")
eq(handled, false, "stash: an unknown line is left to the library")
handled, text = talk("banker", q, "my balance")
check(text and text:find("12345", 1, true), "banker: the balance")
eq(#sent, 0, "banker: a balance opens nothing")
handled, text = talk("banker", q, "deposit")
eq(sent[1] and sent[1].op, ChaosOpcodes.bank, "banker: the bank opens")
handled, text = talk("pocketboss", q, "my charges")
check(text and text:find("3", 1, true), "pocket boss: the daily charges")
handled, text = talk("pocketboss", q, "bosses")
eq(sent[1] and sent[1].op, ChaosOpcodes.bossSpawns, "pocket boss: the ledger opens")
handled, text = talk("services", q, "change my name")
check(text and text:find("you have 2", 1, true), "services: the name tokens")
eq(sent[1] and sent[1].json, '{"action":"npc","data":{"page":"services"}}', "services: the Services page")

-- the broker: list, buy with a confirmation, cancel
handled, text = talk("broker", q, "list")
check(text and text:find("Cinderhold (", 1, true), "broker: the towns")
handled, text = talk("broker", q, "list Cinderhold")
check(text and text:find("Ash Lane 2", 1, true), "broker: the houses of a town")
handled, text = talk("broker", q, "buy")
check(text and text:find("Which house", 1, true), "broker: asks which house")
handled, text = talk("broker", q, "buy zzz")
check(text and text:find("no house of that name", 1, true), "broker: unknown house")
handled, text = talk("broker", q, "buy Ash Lane 2")
check(text and text:find("10000", 1, true) and text:find("{yes}", 1, true), "broker: asks to confirm")
eq(q.money, 50000, "broker: nothing taken before the yes")
eq(liveHouses[2].owner, 0, "broker: nothing sold before the yes")
-- the confirmation arrives on the same NPC state: talk() would reload the script, so drive the callback again
local cb = callbacks[CALLBACK_MESSAGE_DEFAULT]
said = {}
handled = cb(q.id, 1, "yes")
eq(handled, true, "broker: yes handled")
check(said[1] and said[1]:find("is yours", 1, true), "broker: bought: " .. tostring(said[1]))
eq(q.money, 40000, "broker: 10,000 gold taken")
eq(liveHouses[2].owner, q.guid, "broker: the house is sold")
said = {}
cb(q.id, 1, "yes")
eq(said[1], nil, "broker: a second yes does nothing here (the library answers)") -- handled false

-- every line they say has a pt-BR text (the script's t(cid, "..."), the core's K.TEXT, the XML greet / farewell lines)
local pt = dofile("data/scripts/chaos/i18n_strings.lua")["pt-BR"]
local function fileText(path)
	local fh = io.open(path)
	local text = fh:read("*a")
	fh:close()
	return text
end
local lines = 0
for key in fileText("data/npc/scripts/chaos_service_npc.lua"):gmatch('t%(cid,%s*"([^"\n]*)"') do
	lines = lines + 1
	check(pt[key] ~= nil, "pt-BR for: " .. key)
end
for _, text in pairs(K.TEXT) do
	lines = lines + 1
	check(pt[text] ~= nil, "pt-BR for: " .. text)
end
for _, npc in pairs(cfg.npcs) do
	for value in fileText("data/npc/" .. npc.name .. ".xml"):gmatch('key="message_%w+" value="([^"]*)"') do
		lines = lines + 1
		check(pt[value] ~= nil, "pt-BR for: " .. value)
	end
end
check(lines >= 40, "the texts were found (" .. lines .. ")")

-- ---------------------------------------------------------------- the placement at startup
local placed = {}
ChaosNpcPlace = {place = function(name, temple, offsets)
	placed[#placed + 1] = name .. "@" .. temple.id
	return name ~= "Pell Ashmere" or temple.id ~= 1 -- one NPC cannot be placed in one town
end}
Town = function(id) return {getTemplePosition = function() return {id = id} end} end
local startups = {}
GlobalEvent = function() local ev = {} function ev:register() startups[#startups + 1] = self end return ev end
addEvent = function(fn) fn() return 1 end
dofile("data/scripts/chaos/service_npcs.lua")
eq(#startups, 1, "one startup event")
startups[1].onStartup()
eq(#placed, 10, "five NPCs in two towns")
eq(placed[1], "Tavish Coldhand@2", "the stash keeper first, in the main city")
eq(placed[2], "Tavish Coldhand@1", "then Mirewake")
eq(placed[9], "Pell Ashmere@2", "the clerk last")
eq(ChaosServiceNpcs.placeNpcs(), 9, "a failed placement is not counted")

print(string.format("service_npcs_test: %d checks, %d failures", checks, failures))
os.exit(failures == 0 and 0 or 1)
