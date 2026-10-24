-- NPCs that trade for something other than gold (owner beta 2026-10-24: "broken window. Where do players get azure
-- coins?"). The base NPC scripts (the azure NPC, the four mining-crafting NPCs that pay in town coins, the sweets NPC,
-- the token NPC) open a stock shop window, which a 10.98 client always shows as "Currency: Gold Coin" with the
-- player's gold, and told the old client the currency by two extended opcodes (125 "AZ", 126 the amount) that ours
-- never read: 125 is the monster bar's opcode, 126 nobody's.
-- tools/patch_npc_currency.py turns those lines into
--     local chaosCurrency = {code = "AZ", item = 26780}                (or storage = 48079, name = "hallowfall coins")
--     ChaosNpcCurrency.announce(player, chaosCurrency)                 before openShopWindow
--     openShopWindow(cid, shop, ChaosNpcCurrency.wrap(onBuy, chaosCurrency), ChaosNpcCurrency.wrap(onSell, chaosCurrency))
-- and the client module game_npctradewindow shows the currency (name, icon, the balance) in that window.
--   ChaosNpcCurrency.balance(player, spec)    the player's amount: the item count, or the storage value (never below 0)
--   ChaosNpcCurrency.payload(player, spec)    {code, name, item?, amount}: the name is the item type's name or spec.name
--   ChaosNpcCurrency.encode(t)                the JSON text of a payload (own encoder: the NPC Lua state has no json)
--   ChaosNpcCurrency.announce(player, spec, again)  sends the payload on ChaosNpcCurrency.OPCODE, JSON {action = "currency"};
--                                             again = true marks a balance update of an open window
--   ChaosNpcCurrency.wrap(fn, spec)           a shop callback that runs fn, then sends the new balance
--   ChaosNpcCurrency.setsReply(cid, ...)      the azure NPC's "which set for whom" line, in the player's language
-- Runs in the NPC scripts' Lua state (dofile) and in server/tests/npc_currency_test.lua. Lua 5.1 / LuaJIT and 5.3.
ChaosNpcCurrency = ChaosNpcCurrency or {}
local C = ChaosNpcCurrency

C.OPCODE = 113 -- ChaosOpcodes.npcCurrency (chaos_constants.lua); the client is game_npctradewindow

local function itemName(id)
	local ok, name = pcall(function()
		local t = ItemType(id)
		return t and t:getName() or ""
	end)
	return ok and type(name) == "string" and name or ""
end

function C.balance(player, spec)
	if not player or type(spec) ~= "table" then
		return 0
	end
	local n
	if tonumber(spec.item) then
		n = player:getItemCount(tonumber(spec.item))
	elseif tonumber(spec.storage) then
		n = player:getStorageValue(tonumber(spec.storage))
	end
	n = tonumber(n) or 0
	if n < 0 then
		n = 0
	end
	return math.floor(n)
end

function C.payload(player, spec)
	local name = tostring(spec.name or "")
	if name == "" and tonumber(spec.item) then
		name = itemName(tonumber(spec.item))
	end
	if name == "" then
		name = tostring(spec.code or "")
	end
	return {code = tostring(spec.code or ""), name = name, item = tonumber(spec.item), amount = C.balance(player, spec)}
end

local ESC = {['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t"}

local function str(s)
	return '"' .. tostring(s):gsub('[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", c:byte())
	end) .. '"'
end

-- keys in a fixed order, so the text is the same on every run (and the test can compare it)
function C.encode(p)
	local parts = {'"code":' .. str(p.code), '"name":' .. str(p.name)}
	if p.item then
		parts[#parts + 1] = '"item":' .. string.format("%d", p.item)
	end
	parts[#parts + 1] = '"amount":' .. string.format("%d", p.amount or 0)
	if p.again then
		parts[#parts + 1] = '"again":true' -- the balance after a purchase or a sale (the client ignores it without an open window)
	end
	return '{"action":"currency","data":{' .. table.concat(parts, ",") .. "}}"
end

function C.announce(player, spec, again)
	if not player or not player.sendExtendedOpcode then
		return false
	end
	local p = C.payload(player, spec)
	p.again = again and true or nil
	player:sendExtendedOpcode(C.OPCODE, C.encode(p))
	return true
end

function C.wrap(fn, spec)
	return function(cid, ...)
		local a, b, c, d = fn(cid, ...)
		local player = Player(cid)
		if player then
			C.announce(player, spec, true)
		end
		return a, b, c, d
	end
end

-- ---------------------------------------------------------------- the azure NPC's reply
-- The base line named the stock vocations ("Stuff for all vocations, X and Y for knights, Z for sorcerers and
-- druids and W for paladins."): the sets of the first two are worn by the Warrior line, the third by the Mystic line,
-- the fourth by the Ranger line (their movement lists were rewritten by add_vocations.py). Class names stay English in
-- pt-BR (server/README.md "Server texts in pt-BR"). Where the coins come from is said too: the owner asked.
C.SETS_KEY = "Stuff for every class: %s and %s for Warriors, %s for Mystics and %s for Rangers."
C.SOURCE_KEY = "Azure Coins drop from the boss of the Azure portals and the Forbidden Chevalier, and some hunting tasks pay them."

local function cap(s)
	s = tostring(s or "")
	return (s:gsub("^%l", string.upper))
end

local function text(cid, key, ...)
	if ChaosI18n and ChaosI18n.npcText then
		local ok, res = pcall(ChaosI18n.npcText, cid, key, ...)
		if ok and type(res) == "string" and res ~= "" then
			return res
		end
	end
	return string.format(key, ...)
end

-- a table of lines for npcHandler:say
function C.setsReply(cid, warriorA, warriorB, mystic, ranger)
	if not (ChaosI18n and ChaosI18n.npcText) then
		pcall(dofile, "data/scripts/chaos/i18n_core.lua") -- the NPC state never loaded it: the language is the stored one
	end
	return {text(cid, C.SETS_KEY, cap(warriorA), cap(warriorB), cap(mystic), cap(ranger)), text(cid, C.SOURCE_KEY)}
end

return C
