-- Economy category.
ChaosAdminPending = ChaosAdminPending or {}
local function reg(def) def.category = "economy"; def.id = "economy." .. def.id; ChaosAdminPending[def.id] = def end

local PLAYER_OPT = {name = "player", label = "Player (empty = me)", type = "player", required = false}

reg{id = "give_gold", name = "Give gold", description = "Add gold coins to the player's inventory (addMoney).",
	params = {PLAYER_OPT, {name = "amount", label = "Amount", type = "int", min = 1, max = 2000000000}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		t:addMoney(p.amount)
		return true, string.format("Gave %d gold to %s.", p.amount, t:getName())
	end}

reg{id = "remove_gold", name = "Remove gold", description = "Remove gold from inventory/bank (removeMoney).", confirm = true,
	params = {{name = "player", label = "Player", type = "player"}, {name = "amount", label = "Amount", type = "int", min = 1, max = 2000000000}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		if not t:removeMoney(p.amount) then return false, "Player does not have that much." end
		return true, string.format("Removed %d gold from %s.", p.amount, t:getName())
	end}

reg{id = "give_bank", name = "Add to bank balance", description = "Add (or subtract with a negative number) gold to the bank balance of an online player.",
	params = {PLAYER_OPT, {name = "amount", label = "Amount (+/-)", type = "int", min = -2000000000, max = 2000000000}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOrSelf(actor, p.player)
		if not t then return false, err end
		local new = t:getBankBalance() + p.amount
		if new < 0 then return false, "Balance would be negative." end
		t:setBankBalance(new)
		return true, string.format("%s bank balance is now %d.", t:getName(), new)
	end}

reg{id = "item_price", name = "Item price lookup", description = "Item details plus lowest/highest sell offers in the market table (if the market is used).",
	params = {{name = "item", label = "Item id or name", type = "string", max = 60}},
	handler = function(actor, p)
		local it, err = ChaosAdmin.resolveItem(p.item)
		if not it then return false, err end
		local lines = {
			string.format("%s  (server id %d, client id %d)", it:getName(), it:getId(), it:getClientId()),
			"Weight " .. (it:getWeight() or 0) / 100 .. " oz  stackable=" .. tostring(it:isStackable()),
		}
		local okW, worth = pcall(function() return it:getWorth() end)
		if okW and worth then lines[#lines + 1] = "Worth/NPC value: " .. tostring(worth) end
		local ok, rid = pcall(db.storeQuery, string.format(
			"SELECT COUNT(*) AS c, MIN(`price`) AS lo, MAX(`price`) AS hi FROM `market_offers` WHERE `itemtype` = %d AND `sale` = 1", it:getId()))
		if ok and rid then
			lines[#lines + 1] = string.format("Market sell offers: %d  lowest %d  highest %d",
				result.getNumber(rid, "c"), result.getNumber(rid, "lo"), result.getNumber(rid, "hi"))
			result.free(rid)
		else
			lines[#lines + 1] = "Market table not available."
		end
		return true, "Item lookup", lines
	end}

reg{id = "market_offers", name = "Player market offers", description = "List active market offers of a player (read only).",
	params = {{name = "player", label = "Player", type = "player"}},
	handler = function(actor, p)
		local d = ChaosAdmin.dbPlayer(p.player)
		if not d then return false, "Player not found." end
		local ok, rid = pcall(db.storeQuery, "SELECT `sale`,`itemtype`,`amount`,`price`,`created` FROM `market_offers` WHERE `player_id` = " .. d.id .. " ORDER BY `created` DESC LIMIT 50")
		if not ok then return false, "Market table not available." end
		local lines = {}
		if rid then
			repeat
				local it = ItemType(result.getNumber(rid, "itemtype"))
				lines[#lines + 1] = string.format("%s  %dx %s @ %d", result.getNumber(rid, "sale") == 1 and "SELL" or "BUY",
					result.getNumber(rid, "amount"), it and it:getName() or "?", result.getNumber(rid, "price"))
			until not result.next(rid)
			result.free(rid)
		end
		return true, #lines .. " offer(s).", lines
	end}

reg{id = "market_buy_orders", name = "Market buy orders", description = "Buy orders of the Chaos market (read only): every active one, or every order of one character, with the escrow held.",
	params = {{name = "player", label = "Player (empty = all active)", type = "player", required = false}},
	handler = function(actor, p)
		local MK = ChaosMarket
		if not MK or not MK.ordersReport then return false, "The Chaos market is not loaded." end
		local guid
		if p.player and p.player ~= "" then
			local d = ChaosAdmin.dbPlayer(p.player)
			if not d then return false, "Player not found." end
			guid = d.id
		end
		local lines, sums = MK.ordersReport(guid, 50)
		return true, string.format("%d buy order(s); active escrow: %d gold, %d Chaos Coins.", #lines, sums.gold or 0, sums.coins or 0), lines
	end}


-- ------------------------------------------------------------------ the stash (stash.lua ChaosStash.staff*; server/README.md "Stash")
-- Whole items, affinity tabs and the crash-safe journal: every write goes through the stash's own journal (the row
-- first, the serial saved with the character, then the entry), so a crash never loses or doubles an item.
local okStash, stashCfg = pcall(dofile, "data/scripts/chaos/stash_config.lua")
local STASH_TABS = {{value = "0", label = "Auto (as a deposit)"}}
if okStash and type(stashCfg) == "table" then
	for t = 1, tonumber(stashCfg.maxGeneralTabs) or 0 do
		STASH_TABS[#STASH_TABS + 1] = {value = tostring(t), label = "General tab " .. t}
	end
	for _, a in ipairs(stashCfg.affinities or {}) do
		STASH_TABS[#STASH_TABS + 1] = {value = tostring(a.tab), label = a.name .. " (" .. a.tab .. ")"}
	end
end

local function stashApi(fn)
	return ChaosAdmin.system("ChaosStash", fn)
end

reg{id = "stash_give", name = "Stash: add item", description = "Make items straight into a tab of an online player's stash, through the stash journal. Auto routes it like a deposit (affinity tab, else a general tab).",
	minGroup = 5,
	params = {{name = "player", label = "Player (online)", type = "player"}, {name = "item", label = "Item id or name", type = "string", max = 60},
		{name = "count", label = "Count (whole items: max 100)", type = "int", min = 1, max = 1000000, default = 1},
		{name = "tab", label = "Tab", type = "select", default = "0", options = STASH_TABS}},
	handler = function(actor, p)
		local S, why = stashApi("staffGive")
		if not S then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err .. " The stash journal needs the character online." end
		local it, e2 = ChaosAdmin.resolveItem(p.item)
		if not it then return false, e2 end
		local ok, text = S.staffGive(t, it:getId(), p.count, tonumber(p.tab) or 0, "staff")
		return ok, t:getName() .. ": " .. tostring(text)
	end}

reg{id = "stash_info", name = "Stash: tabs and search", description = "Entries and items per tab of a player's stash (offline too); with an item, where it is: the merged stack and every stored row (row ids for Stash: remove).",
	params = {{name = "player", label = "Player", type = "player"},
		{name = "item", label = "Search item id or name (optional)", type = "string", max = 60, required = false}},
	handler = function(actor, p)
		local S, why = stashApi("staffSummary")
		if not S then return false, why end
		local t, err = ChaosAdmin.targetAny(actor, p.player)
		if not t then return false, err end
		local tabs, entries, items = S.staffSummary(t.guid)
		local lines = {}
		for _, row in ipairs(tabs) do
			lines[#lines + 1] = string.format("%s: %d entries, %d items", row.name, row.entries, row.items)
		end
		if p.item and p.item ~= "" then
			local it, e2 = ChaosAdmin.resolveItem(p.item)
			if not it then return false, e2 end
			local stack, rows = S.staffFind(t.guid, it:getId())
			lines[#lines + 1] = string.format("-- %s (%d): stack %d%s, %d stored item(s)", it:getName(), it:getId(), stack.count,
				stack.count > 0 and (" in " .. S.staffTabName(stack.tab)) or "", #rows)
			for i, r in ipairs(rows) do
				if i > 40 then lines[#lines + 1] = "..." break end
				lines[#lines + 1] = string.format("row %d: %s x%d in %s", r.id, r.name ~= "" and r.name or it:getName(), r.count,
					S.staffTabName(r.tab))
			end
		end
		return true, string.format("%s: %d entries, %d items in %d tab(s).", t.name, entries, items, #tabs), lines
	end}

reg{id = "stash_remove", name = "Stash: remove item", description = "Take items out of an online player's stash and destroy them, through the stash journal: a stored row (id from Stash: tabs and search) or an amount of a merged stack.",
	dangerous = true,
	params = {{name = "player", label = "Player (online)", type = "player"},
		{name = "row", label = "Row id (0 = use item and count)", type = "int", min = 0, max = 2147483647, default = 0},
		{name = "item", label = "Item id or name (merged stack)", type = "string", max = 60, required = false},
		{name = "count", label = "Count", type = "int", min = 1, max = 2000000000, default = 1}},
	handler = function(actor, p)
		local S, why = stashApi("staffRemove")
		if not S then return false, why end
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err .. " The stash journal needs the character online." end
		local what
		if p.row and p.row > 0 then
			what = {row = p.row}
		else
			if not p.item or p.item == "" then return false, "Give a row id or an item." end
			local it, e2 = ChaosAdmin.resolveItem(p.item)
			if not it then return false, e2 end
			what = {item = it:getId(), count = p.count}
		end
		local ok, text = S.staffRemove(t, what)
		return ok, t:getName() .. ": " .. tostring(text)
	end}
