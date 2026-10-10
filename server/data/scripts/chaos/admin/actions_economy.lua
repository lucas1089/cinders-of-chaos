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

reg{id = "stash_give", name = "Add to stash", description = "Add items to a player's stash if the server build supports it (Player:addItemStash).",
	params = {{name = "player", label = "Player", type = "player"}, {name = "item", label = "Item id or name", type = "string", max = 60},
		{name = "count", label = "Count", type = "int", min = 1, max = 100000, default = 1}},
	handler = function(actor, p)
		local t, err = ChaosAdmin.targetOnline(actor, p.player)
		if not t then return false, err end
		local it, e2 = ChaosAdmin.resolveItem(p.item)
		if not it then return false, e2 end
		if type(t.addItemStash) ~= "function" then return false, "Stash API (Player:addItemStash) is not available on this build." end
		local ok, res = pcall(t.addItemStash, t, it:getId(), p.count)
		if not ok then return false, "Stash call failed: " .. tostring(res) end
		return true, string.format("Added %dx %s to %s's stash.", p.count, it:getName(), t:getName())
	end}

reg{id = "stash_info", name = "Stash item count", description = "How many of an item a player has in stash (if supported).",
	params = {{name = "player", label = "Player", type = "player"}, {name = "item", label = "Item id or name", type = "string", max = 60}},
	handler = function(actor, p)
		local t = Player(p.player)
		if not t then return false, "Player is not online." end
		local it, e2 = ChaosAdmin.resolveItem(p.item)
		if not it then return false, e2 end
		if type(t.getStashItemCount) ~= "function" then return false, "Stash API (Player:getStashItemCount) is not available on this build." end
		local ok, n = pcall(t.getStashItemCount, t, it:getId())
		if not ok then return false, "Stash call failed: " .. tostring(n) end
		return true, string.format("%s has %d x %s in stash.", t:getName(), n, it:getName())
	end}
