-- Run from the server/ folder: luajit tests/npc_currency_test.lua (CI runs it with LuaJIT and Lua 5.3)
-- NPCs that trade for something other than gold (owner beta 2026-10-24; server/README.md "NPC currencies"):
--   data/lib/chaos_npc_currency.lua   balance, payload, encode, announce, wrap, setsReply
-- against a mocked player and item type: the balance of an item and of a storage (never negative), the payload names
-- (the item type's name, the script's own name, the code), the JSON text (escapes, key order, no item for a storage), the
-- announce on opcode 113, the wrapped shop callbacks (the balance after the original ran, its result kept, no player no
-- send), the azure NPC's reply in English and pt-BR, and that opcode 113 is free (ChaosOpcodes, no two share a number).
local fails, checks = 0, 0
local function ok(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL " .. what)
	end
end
local function eq(a, b, what) ok(a == b, what .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end

-- ---------------------------------------------------------------- the mocked engine
local sent, items, storages, names = {}, {[26780] = 42}, {[48079] = 17}, {[26780] = "Azure Coin", [28697] = "dark chocolate coin"}
local function makePlayer(id)
	return {
		id = id,
		getItemCount = function(_, item) return items[item] or 0 end,
		getStorageValue = function(_, key) return storages[key] or -1 end,
		sendExtendedOpcode = function(_, op, text) sent[#sent + 1] = {op = op, text = text} end,
	}
end
local players = {[1] = makePlayer(1)}
function Player(cid) return players[cid] end
function ItemType(id) return {getName = function() return names[id] or "" end} end

dofile("data/lib/chaos_npc_currency.lua")
local C = ChaosNpcCurrency
local p = players[1]

-- ---------------------------------------------------------------- balance
eq(C.balance(p, {code = "AZ", item = 26780}), 42, "an item currency: the item count")
eq(C.balance(p, {code = "H", storage = 48079}), 17, "a storage currency: the storage value")
eq(C.balance(p, {code = "H", storage = 99999}), 0, "an unset storage (-1) is 0")
eq(C.balance(p, {code = "X"}), 0, "no item and no storage: 0")
eq(C.balance(nil, {item = 1}), 0, "no player: 0")

-- ---------------------------------------------------------------- payload and JSON
local pay = C.payload(p, {code = "AZ", item = 26780})
eq(pay.name, "Azure Coin", "the name of an item currency is the item type's")
eq(pay.amount, 42, "payload amount")
eq(C.payload(p, {code = "H", storage = 48079, name = "quillfall coins"}).name, "quillfall coins", "a storage currency keeps its own name")
eq(C.payload(p, {code = "Q", storage = 5}).name, "Q", "no name: the code")
eq(C.payload(p, {code = "ZZ", item = 123456}).name, "ZZ", "an item without a name: the code")
eq(C.encode(pay), '{"action":"currency","data":{"code":"AZ","name":"Azure Coin","item":26780,"amount":42}}', "item currency JSON")
eq(C.encode({code = "H", name = 'a "q"\\ b\n', amount = 3}),
	'{"action":"currency","data":{"code":"H","name":"a \\"q\\"\\\\ b\\n","amount":3}}', "storage currency JSON: escapes, no item")
eq(C.encode({code = "H", name = "x\1y", amount = 0}), '{"action":"currency","data":{"code":"H","name":"x\\u0001y","amount":0}}',
	"control characters")

-- ---------------------------------------------------------------- announce and wrap
eq(C.OPCODE, 113, "opcode")
ok(C.announce(p, {code = "AZ", item = 26780}), "announce returns true")
eq(#sent, 1, "one packet")
eq(sent[1].op, 113, "sent on opcode 113")
eq(sent[1].text, C.encode(pay), "the payload text")
ok(not C.announce(nil, {code = "AZ"}), "no player: nothing sent")
eq(#sent, 1, "still one packet")

local calls = {}
local function shopFn(cid, item, subType, amount)
	calls[#calls + 1] = {cid, item, amount}
	items[26780] = 12 -- the purchase took coins
	return "result", true
end
local wrapped = C.wrap(shopFn, {code = "AZ", item = 26780})
local r1, r2 = wrapped(1, 26761, 0, 2)
eq(r1, "result", "the wrapper keeps the callback's first result")
eq(r2, true, "and its second")
eq(#calls, 1, "the callback ran once")
eq(calls[1][3], 2, "with its arguments")
eq(#sent, 2, "a balance packet after the callback")
ok(sent[2].text:find('"amount":12', 1, true) ~= nil, "it carries the balance after the callback: " .. tostring(sent[2].text))
ok(sent[2].text:find('"again":true', 1, true) ~= nil, "and says it is an update")
ok(sent[1].text:find("again", 1, true) == nil, "the first announce is not an update")
wrapped(77, 26761, 0, 1) -- a player who left
eq(#sent, 2, "no player: the callback ran, nothing sent")
eq(#calls, 2, "the callback still ran")

-- ---------------------------------------------------------------- the azure NPC's reply
local lines = C.setsReply(1, "blightwoven", "ironwrath", "netherwave", "ashborne")
eq(#lines, 2, "two lines: the sets and the source")
eq(lines[1], "Stuff for every class: Blightwoven and Ironwrath for Warriors, Netherwave for Mystics and Ashborne for Rangers.",
	"English reply, names capitalised")
ok(lines[2]:find("Azure Coins drop", 1, true) ~= nil, "the second line says where the coins drop")
ok(not lines[1]:lower():find("knight") and not lines[1]:lower():find("sorcerer") and not lines[1]:lower():find("druid")
	and not lines[1]:lower():find("paladin") and not lines[1]:lower():find("vocation"), "no stock vocation word")

-- pt-BR (the stored language: storage 7101830 = 1)
storages[7101830] = 1
local pt = C.setsReply(1, "blightwoven", "ironwrath", "netherwave", "ashborne")
eq(pt[1], "Equipamento para todas as classes: Blightwoven e Ironwrath para Warriors, Netherwave para Mystics e Ashborne para Rangers.",
	"pt-BR reply")
ok(pt[2]:find("Azure Coins caem", 1, true) ~= nil, "pt-BR source line")
storages[7101830] = nil
ok(ChaosI18n and ChaosI18n.npcText, "the library loaded i18n_core.lua for the NPC state")

-- without i18n at all the English pattern still comes out
ChaosI18n = nil
local savedDofile = dofile
dofile = function() error("no i18n here") end
local plain = C.setsReply(1, "a", "b", "c", "d")
dofile = savedDofile
eq(plain[1], "Stuff for every class: A and B for Warriors, C for Mystics and D for Rangers.", "no i18n: English")

-- ---------------------------------------------------------------- the opcode
dofile("data/scripts/chaos/chaos_constants.lua")
eq(ChaosOpcodes.npcCurrency, 113, "ChaosOpcodes.npcCurrency")
local seen = {}
for k, v in pairs(ChaosOpcodes) do
	if type(v) == "number" then
		ok(not seen[v] or seen[v] == k, "opcode " .. v .. " taken by " .. k .. " and " .. tostring(seen[v]))
		seen[v] = k
	end
end
ok(ChaosOpcodes.monsterbar ~= C.OPCODE and ChaosOpcodes.monsterbar == 125, "the monster bar keeps 125")

print("npc_currency tests OK (" .. checks .. " checks)")
if fails > 0 then
	os.exit(1)
end
