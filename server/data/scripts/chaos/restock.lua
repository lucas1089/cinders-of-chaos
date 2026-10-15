-- Restock (server/README.md "Restock"): the Restock button of the Hunt Tracker (client game_hunt) buys back the potions,
-- runes and spears the hunt session used, at the NPC price (hunt_supplies.lua) plus a convenience fee
-- (restock_config.lua priceMult, +10%), paid from the gold carried and then the bank. Rules: restock_core.lua (pure,
-- tests/restock_test.lua); numbers: restock_config.lua.
--
-- Shares the hunt tracker's extended opcode (ChaosOpcodes.hunt = 241) with hunt.lua, with its own actions:
--   client -> server  restockQuote          what a click would buy now
--                     restock               buy the quote the player saw (a changed or old quote is quoted again)
--   server -> client  restockQuote {rows = [[clientId, count, gold, name]], gold, fee (gold of it over the NPC price),
--                     pct (the fee in percent), money, why}
--                     why: "" (can buy), "pz", "instance", "none", "money"
-- Only in a protection zone outside every instance. What was bought back is noted on the hunt session, so a second
-- click buys nothing until more is used; a reset of the session starts over.
-- Assumed engine API (TFS 1.4): Player:getMoney/getBankBalance/removeTotalMoney (data/lib/core/player.lua) or
-- removeMoney, addItem, getInbox, Tile:hasFlag(TILESTATE_PROTECTIONZONE), ItemType. Lua 5.1 / LuaJIT and Lua 5.3.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/restock_core.lua")
ChaosRestockConfig = dofile("data/scripts/chaos/restock_config.lua")

ChaosRestock = ChaosRestock or {}
local RS = ChaosRestock
local R = ChaosRestockCore
local OPCODE = ChaosOpcodes.hunt or 241

RS.prices = RS.prices or dofile("data/scripts/chaos/hunt_supplies.lua")
RS.quotes = RS.quotes or {} -- player id -> {at, rows}
RS.types = RS.types or {} -- id -> {stack, charges, cid, name}

local function cfg()
	return ChaosRestockConfig
end

local function log(text)
	print("[Chaos restock] " .. text)
end

function RS.info(id)
	local t = RS.types[id]
	if not t then
		local ok, res = pcall(function()
			local it = ItemType(id)
			return {stack = it:isStackable(), charges = it:getCharges() or 0, cid = it:getClientId(), name = it:getName()}
		end)
		t = ok and res or {stack = true, charges = 0, cid = id, name = "item " .. id}
		RS.types[id] = t
	end
	return t
end

local function money(player)
	local carried = player.getMoney and player:getMoney() or 0
	local bank = player.getBankBalance and player:getBankBalance() or 0
	return (tonumber(carried) or 0) + (tonumber(bank) or 0)
end

local function pay(player, gold)
	if gold <= 0 then
		return true
	end
	if player.removeTotalMoney then
		return player:removeTotalMoney(gold) and true or false
	end
	return player:removeMoney(gold) and true or false
end

local function inPz(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and TILESTATE_PROTECTIONZONE ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

-- the hunt session and what is left to buy back
local function sessionOf(player)
	local H = ChaosHunt
	local s = H and H.sessions and H.sessions[player:getGuid()]
	if not s or type(s.supplies) ~= "table" then
		return nil
	end
	if not s.restock or s.restock.of ~= s.supplies then
		s.restock = {of = s.supplies, n = {}} -- a reset of the session made a new supplies table: start over
	end
	return s
end

-- why a purchase cannot happen ("" when it can), the affordable rows, their gold and the money
function RS.quote(player)
	local c = cfg()
	if not c.enabled then
		return "none", {}, 0, 0
	end
	if c.needPz and not inPz(player) then
		return "pz", {}, 0, 0
	end
	if Chaos.inAnyInstance and Chaos.inAnyInstance(player) then
		return "instance", {}, 0, 0
	end
	local s = sessionOf(player)
	local used = {}
	for id, row in pairs(s and s.supplies or {}) do
		used[id] = row.n
	end
	local plan = R.plan(R.remaining(used, s and s.restock.n), RS.prices, RS.info, c)
	if #plan == 0 then
		return "none", {}, 0, 0
	end
	local have = money(player)
	local rows, gold = R.afford(plan, have)
	if #rows == 0 then
		return "money", plan, R.total(plan), have
	end
	return "", rows, gold, have
end

local function rowsOut(rows)
	local out = {}
	for _, r in ipairs(rows) do
		local t = RS.info(r.id)
		out[#out + 1] = {t.cid, r.count, r.gold, t.name}
	end
	return out
end

function RS.sendQuote(player)
	local why, rows, gold, have = RS.quote(player)
	RS.quotes[player:getId()] = why == "" and {at = os.time(), rows = rows} or nil
	Chaos.send(player, OPCODE, "restockQuote", {rows = rowsOut(rows), gold = gold, fee = R.fee(rows, RS.prices),
		pct = R.feePercent(cfg()), money = have, why = why})
	return why
end

local function give(player, r)
	local t = RS.info(r.id)
	local toInbox = 0
	local function add(count, subType)
		local ok, item = pcall(function()
			if subType then
				return player:addItem(r.id, 1, false, subType)
			end
			return player:addItem(r.id, count, false)
		end)
		if ok and item then
			return
		end
		local box = player:getInbox()
		local okBox = box and pcall(function() return box:addItem(r.id, subType or count) end)
		if okBox then
			toInbox = toInbox + 1
		else
			log("could not give " .. count .. "x " .. r.id .. " to " .. player:getName())
		end
	end
	if t.stack then
		for _, n in ipairs(R.stacks(r.count, cfg().stackSize)) do
			add(n)
		end
	else
		for _ = 1, r.count do
			add(1, r.charges > 1 and r.charges or nil)
		end
	end
	return toInbox
end

-- buy the quote the player saw
function RS.buy(player)
	local id = player:getId()
	local seen = RS.quotes[id]
	RS.quotes[id] = nil
	local why, rows, gold = RS.quote(player)
	if why == "pz" then
		player:sendCancelMessage(Chaos.t(player, "Restock: stand in a protection zone in town."))
		return false
	elseif why == "instance" then
		player:sendCancelMessage(Chaos.t(player, "Restock: not inside an instance."))
		return false
	elseif why == "none" then
		player:sendCancelMessage(Chaos.t(player, "Restock: nothing used in this hunt session yet."))
		return false
	elseif why == "money" then
		player:sendCancelMessage(Chaos.t(player, "Restock: you need %d gold (carried or in the bank).", gold))
		return false
	end
	if not seen or os.time() - seen.at > (cfg().quoteSeconds or 60) or not R.sameQuote(seen.rows, rows) then
		RS.sendQuote(player) -- something changed: show the new quote first
		return false
	end
	if not pay(player, gold) then
		player:sendCancelMessage(Chaos.t(player, "Restock: you need %d gold (carried or in the bank).", gold))
		return false
	end
	local s = sessionOf(player)
	local inbox, names = 0, {}
	for _, r in ipairs(rows) do
		if s then
			s.restock.n[r.id] = (s.restock.n[r.id] or 0) + r.units
		end
		inbox = inbox + give(player, r)
		names[#names + 1] = r.count .. "x " .. RS.info(r.id).name
	end
	local text = Chaos.t(player, "Restocked %s for %d gold.", table.concat(names, ", "), gold)
	if inbox > 0 then
		text = text .. Chaos.t(player, " Some went to your inbox (no room or capacity).")
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
	return true
end

local ext = CreatureEvent("ChaosRestockExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or (msg.action ~= "restockQuote" and msg.action ~= "restock") then
		return
	end
	if Chaos.limited and Chaos.limited(player, "restock." .. msg.action, 500) then
		return
	end
	local ok, err = pcall(msg.action == "restock" and RS.buy or RS.sendQuote, player)
	if not ok then
		log(msg.action .. ": " .. tostring(err))
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosRestockLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRestockExtended")
	return true
end
login:type("login")
login:register()
