-- Everfull potions: engine helpers with no event registration, so the potion sellers' NPC states can load them too
-- (the ShopModule hook of server/tools/install_potions.py) as well as data/scripts/chaos/potions.lua.
-- Rules: data/scripts/chaos/potions_core.lua; numbers: potions_config.lua; README "Potions".
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not ChaosPotionsCore then
	dofile("data/scripts/chaos/potions_core.lua")
end
if not ChaosPotionsConfig then
	dofile("data/scripts/chaos/potions_config.lua")
end

ChaosPotions = ChaosPotions or {}
local PT = ChaosPotions
local K = ChaosPotionsCore
local NOERR = RETURNVALUE_NOERROR or 0

function PT.cfg()
	return ChaosPotionsConfig
end

function PT.everfull(id)
	return K.everfull(PT.cfg(), id)
end

-- the Everfull item is in items.otb (install_potions.py ran)
function PT.installed(id)
	local ok, it = pcall(ItemType, id)
	return ok and it ~= nil and it:getId() ~= 0
end

local function itemId(item)
	local ok, id = pcall(function() return item:getId() end)
	return ok and id or nil
end

local function walk(roots, fn)
	local queue, i = {}, 1
	for _, r in ipairs(roots) do
		queue[#queue + 1] = r
	end
	while i <= #queue and i < 2000 do
		local item = queue[i]
		i = i + 1
		if fn(item) then
			return true
		end
		if item:isContainer() then
			for _, inner in ipairs(item:getItems() or {}) do
				queue[#queue + 1] = inner
			end
		end
	end
	return false
end

local function roots(player)
	local out = {}
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			out[#out + 1] = item
		end
	end
	-- the purse (store inbox): where the store delivers
	if player.getStoreInbox then
		local okP, purse = pcall(function() return player:getStoreInbox() end)
		if okP and purse then
			out[#out + 1] = purse
		end
	end
	local inbox = player.getInbox and player:getInbox()
	if inbox then
		out[#out + 1] = inbox
	end
	local okT, towns = pcall(Game.getTowns)
	for _, town in ipairs(okT and towns or {}) do
		local ok, chest = pcall(function() return player:getDepotChest(town:getId(), false) end)
		if ok and chest then
			out[#out + 1] = chest
		end
	end
	return out
end

-- the character has this Everfull potion somewhere (inventory, inbox, depots)
function PT.owned(player, id)
	return walk(roots(player), function(item)
		return itemId(item) == id
	end)
end

-- every Everfull item of the character (any tier, inventory, purse, inbox, depots): a list of {item = , id = }
function PT.everfullItems(player)
	local out = {}
	walk(roots(player), function(item)
		local id = itemId(item)
		if id and K.everfull(PT.cfg(), id) then
			out[#out + 1] = {item = item, id = id}
		end
		return false
	end)
	return out
end

-- the character has an Everfull item of this slot ("health" or "mana"), of any tier or line
function PT.ownedSlot(player, slot)
	for _, x in ipairs(PT.everfullItems(player)) do
		if K.everfull(PT.cfg(), x.id).key == slot then
			return true
		end
	end
	return false
end

-- a new Everfull potion, store-bound and locked (not traded, sold, dropped or lost on death). `from`: an old Everfull
-- item whose bound and lock attributes it keeps (a tier swap); the lock never drops below the bind value's rule (any
-- value but 0 locks, the client draws only 1 grey, so 1 becomes the bind value).
function PT.create(id, from)
	local c = PT.cfg()
	local item = Game.createItem(id, 1)
	if not item then
		return nil
	end
	local bound, lock = 1, K.bindLock(c)
	if from then
		local okB, b = pcall(function() return from:getCustomAttribute(c.attr.storebound) end)
		local okL, l = pcall(function() return from:getCustomAttribute(c.attr.lock) end)
		if okB and tonumber(b) and tonumber(b) ~= 0 then
			bound = b
		end
		if okL and tonumber(l) and tonumber(l) ~= 0 and tonumber(l) ~= 1 then
			lock = l
		end
	end
	item:setCustomAttribute(c.attr.storebound, bound)
	item:setCustomAttribute(c.attr.lock, lock) -- bound, but drawn in its colours (potions_config.lua bindLock)
	return item
end

-- every Everfull potion of the character with the old lock value gets cfg.bindLock (sent again to the client, which
-- stops drawing it grey). Returns how many changed.
function PT.rebind(player)
	local c = PT.cfg()
	local n = 0
	walk(roots(player), function(item)
		local id = itemId(item)
		if id and K.everfull(c, id) then
			local ok, v = pcall(function() return item:getCustomAttribute(c.attr.lock) end)
			if ok and K.needsRebind(c, v) then
				item:setCustomAttribute(c.attr.lock, K.bindLock(c))
				if item.sendUpdate then
					pcall(item.sendUpdate, item)
				end
				n = n + 1
			end
		end
		return false
	end)
	return n
end

-- an item into `container` (the kit backpack) or the inventory, else the inbox: "backpack" | "inbox" | nil
function PT.place(player, item, container)
	if container and container.addItemEx and container:addItemEx(item) == NOERR then
		return "backpack"
	end
	if player:addItemEx(item, false) == NOERR then
		return "backpack"
	end
	local inbox = player.getInbox and player:getInbox()
	if inbox and inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1) == NOERR then
		return "inbox"
	end
	return nil
end

function PT.give(player, id, container)
	local item = PT.create(id)
	if not item then
		return nil
	end
	local where = PT.place(player, item, container)
	if not where then
		pcall(function() item:remove() end)
	end
	return where
end

-- every tier 1 Everfull potion the character does not have yet (the starter kit, the login grant); sets the grant flag.
-- A slot that holds any tier counts as held (an upgraded character never gets a second flask). Returns the number given.
function PT.giveAll(player, container)
	local c = PT.cfg()
	local n = 0
	for _, e in ipairs(c.everfull) do
		if (e.tier or 1) == 1 and PT.installed(e.id) and not PT.ownedSlot(player, e.key) and PT.give(player, e.id, container) then
			n = n + 1
		end
	end
	player:setStorageValue(c.storage.granted, 1)
	return n
end

-- the player's stored language (an NPC state never sees the client's hello; i18n_core.lua "NPC scripts")
local function say(player, text, ...)
	if not (ChaosI18n and ChaosI18n.npcText) then
		pcall(dofile, "data/scripts/chaos/i18n_core.lua")
	end
	if ChaosI18n and ChaosI18n.npcText then
		local ok, t = pcall(ChaosI18n.npcText, player, text, ...)
		if ok and type(t) == "string" then
			text = t
		end
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR or MESSAGE_STATUS_SMALL, text)
end

-- a potion seller's trade window sells an Everfull potion (ShopModule:callbackOnBuy hook, install_potions.py): one
-- store-bound copy whatever amount was asked, paid like any purchase. Returns true when sold.
function PT.npcBuy(cid, id)
	local player = Player(cid)
	if not player then
		return false
	end
	if not ChaosPay then
		dofile("data/lib/chaos_pay.lua")
	end
	local money = ChaosPay.total(player)
	local e = PT.everfull(id)
	local r = K.npcBuy(PT.cfg(), {id = id, owned = e ~= nil and PT.ownedSlot(player, e.key),
		better = e ~= nil and K.restoreFor(PT.cfg(), e.key, {}, PT.earned(player)) ~= nil, money = money})
	if not r.ok then
		if r.text then
			say(player, r.text)
		end
		return false
	end
	-- paid first (carried coins, then the bank); a potion that finds no room gives the gold back to the bank
	if not ChaosPay.pay(player, r.price) then
		say(player, "You do not have enough gold (carried and in the bank).")
		return false
	end
	local where = PT.give(player, id)
	if not where then
		if r.price > 0 then
			player:setBankBalance(player:getBankBalance() + r.price)
		end
		say(player, "You have no room for it.")
		return false
	end
	say(player, "Kills and the temple refill its charges: each drink costs one.")
	return true
end

-- one drink of a health or mana potion (the stock potion script, patched by install_potions.py, and potions.lua):
-- the fixed roll + a percent of the target's maximum (potions_config.lua amount). Health: the tree's Healing applies
-- through the heal event, as for every heal. Mana: the drinker's tree Healing here (a storage, any Lua state).
function PT.amount(player, target, kind, range, level)
	local who = target
	if not (type(who) == "userdata" and who.isPlayer and who:isPlayer()) then
		who = player
	end
	local cfg = PT.cfg()
	if kind == "health" then
		return K.amount(cfg, range, level, who:getMaxHealth(), 0)
	end
	local pct = math.max(0, player:getStorageValue(cfg.storage.healingPct) or 0)
	return K.amount(cfg, range, level, who:getMaxMana(), pct)
end

-- ---------------------------------------------------------------- flask charges (README "Potions", "Flask charges")
-- The charges are the character's, in storage (potions_config.lua storage.healthCharges / manaCharges), in hundredths
-- of a charge; a flask item carries none. -1 (never set) is a full flask.
local function storageOf(kind)
	return kind == "mana" and PT.cfg().storage.manaCharges or PT.cfg().storage.healthCharges
end

function PT.treeExtra(player)
	return math.max(0, tonumber(player:getStorageValue(PT.cfg().storage.treeMaxCharges)) or 0)
end

function PT.treeGain(player)
	return math.max(0, tonumber(player:getStorageValue(PT.cfg().storage.treeGainPct)) or 0)
end

function PT.maxCharges(player, kind)
	return K.maxCharges(PT.cfg(), kind, PT.treeExtra(player))
end

-- hundredths of a charge the flask holds now
function PT.charges(player, kind)
	return K.read(PT.cfg(), kind, player:getStorageValue(storageOf(kind)), PT.treeExtra(player))
end

function PT.setCharges(player, kind, hundredths)
	player:setStorageValue(storageOf(kind), math.max(0, math.floor(hundredths)))
end

-- "3/5"
function PT.label(player, kind)
	return K.label(PT.cfg(), kind, PT.charges(player, kind), PT.treeExtra(player))
end

-- one drink: false when the flask is empty (nothing changes), else the charge is spent
function PT.spend(player, kind)
	local c = PT.cfg()
	local have = PT.charges(player, kind)
	if not K.canDrink(c, have) then
		return false
	end
	PT.setCharges(player, kind, K.spend(c, have))
	return true
end

-- both pools to full. Returns true when something changed.
function PT.fill(player)
	local changed = false
	for _, pool in ipairs(PT.cfg().pools) do
		local top = PT.maxCharges(player, pool) * 100
		if PT.charges(player, pool) < top then
			PT.setCharges(player, pool, top)
			changed = true
		end
	end
	return changed
end

-- a kill's refill for both flasks. Returns the whole charges gained by the health and the mana flask
-- (a table kind -> whole charges more than before) and whether anything was added.
function PT.addKill(player, tier, xp)
	local c = PT.cfg()
	local gained, any = {}, false
	local treeExtra, treeGain = PT.treeExtra(player), PT.treeGain(player)
	for _, pool in ipairs(c.pools) do -- one refill per pool, whatever tiers the character holds
		local before = PT.charges(player, pool)
		local gain = K.killGain(c, {tier = tier, xp = xp, treeGainPct = treeGain, kind = pool})
		local after = K.add(c, pool, before, gain, treeExtra)
		if after ~= before then
			PT.setCharges(player, pool, after)
			any = true
		end
		gained[pool] = K.whole(after) - K.whole(before)
	end
	return gained, any
end

-- one drink of a flask that spends several pools (a spirit potion): every pool needs a whole charge, then each pays one;
-- false and nothing spent when one is short
function PT.spendPools(player, pools)
	local c = PT.cfg()
	for _, pool in ipairs(pools) do
		if not K.canDrink(c, PT.charges(player, pool)) then
			return false
		end
	end
	for _, pool in ipairs(pools) do
		PT.spend(player, pool)
	end
	return true
end

-- "3/5" for a health or mana flask, "3/5 + 4/8" (health, mana) for a spirit flask
function PT.labelOf(player, entry)
	local pools = K.poolsOf(PT.cfg(), entry)
	if #pools == 1 then
		return PT.label(player, pools[1])
	end
	local parts = {}
	for _, pool in ipairs(pools) do
		parts[#parts + 1] = PT.label(player, pool)
	end
	return table.concat(parts, " + ") -- health + mana, in the order of the pools
end

-- an Everfull potion slot ("health" / "mana") of a server id
function PT.kindOf(id)
	local e = K.everfull(PT.cfg(), id)
	return e and e.key or nil
end

-- the first carried stock potion of this id (the flask's source potion) in the inventory, not the inbox or depots
function PT.findStock(player, sourceId)
	local found
	local list = {}
	for slot = CONST_SLOT_FIRST or 1, CONST_SLOT_LAST or 10 do
		local item = player:getSlotItem(slot)
		if item then
			list[#list + 1] = item
		end
	end
	walk(list, function(item)
		if itemId(item) == sourceId then
			found = item
			return true
		end
		return false
	end)
	return found
end

-- ---------------------------------------------------------------- higher tiers (README "Potions", "Higher tiers", O245)
function PT.stockName(e)
	return (tostring(e.name):gsub("^everfull ", ""))
end

local function flagOf(player, e)
	return player:getStorageValue(K.upgradeStorage(PT.cfg(), e.id)) == 1
end

-- the tiers the character has earned (their storage flag is set): a list of entries
function PT.earned(player)
	local out = {}
	for _, e in ipairs(K.upgradeTargets(PT.cfg())) do
		if flagOf(player, e) then
			out[#out + 1] = e
		end
	end
	return out
end

local function heldIds(items)
	local ids = {}
	for _, x in ipairs(items) do
		ids[#ids + 1] = x.id
	end
	return ids
end

-- the swap check for one tier, nothing changes. mode "quest" counts the stock potions, "store" does not.
function PT.upgradeCheck(player, targetId, mode)
	local c = PT.cfg()
	local e = K.everfull(c, targetId)
	if not e then
		return K.upgradeCheck(c, {id = targetId})
	end
	local items = PT.everfullItems(player)
	return K.upgradeCheck(c, {id = targetId, mode = mode, installed = PT.installed(targetId),
		level = player:getLevel(), done = K.upgradeStorage(c, targetId) ~= nil and flagOf(player, e), held = heldIds(items),
		materials = mode == "quest" and player:getItemCount(e.sourceId) or nil, materialName = PT.stockName(e) .. "s"}), items
end

-- The swap, for Veyra's task (mode "quest": takes the stock potions of the tier) and for the store (mode "store": the
-- coins are taken by the store only after this returns true, and refunded by it on any other result). Returns true, or
-- false, text, args (English key and format arguments for Chaos.t / ChaosI18n.npcText).
-- Atomic: the new item is placed first (no room: nothing changed); then the materials, the done flag and the old item
-- go; on any failure or error what was done is undone, so a character never holds two tiers of a slot and never pays
-- without the swap. The charges are the character's storage and are not read or written here.
function PT.upgrade(player, targetId, mode)
	local c = PT.cfg()
	local r, items = PT.upgradeCheck(player, targetId, mode)
	if not r.ok then
		return false, r.text, r.args
	end
	local e = K.everfull(c, targetId)
	local old
	for _, x in ipairs(items) do
		if x.id == r.from then
			old = x.item
		end
	end
	if not old then
		return false, "Carry your Everfull potion in your backpack, your inbox or a depot: the upgrade replaces it."
	end
	local flagKey = K.upgradeStorage(c, targetId)
	local st = {}
	local ok, err = pcall(function()
		local new = PT.create(targetId, old)
		if not new then
			st.fail = "This offer is not available."
			return
		end
		if not PT.place(player, new) then
			pcall(function() new:remove() end)
			st.fail = "You have no room for it."
			return
		end
		st.new = new
		if r.materials > 0 then
			if not player:removeItem(e.sourceId, r.materials) then
				st.fail = "Bring me %d %s and your flask."
				st.args = {r.materials, PT.stockName(e) .. "s"}
				return
			end
			st.materials = true
		end
		player:setStorageValue(flagKey, 1)
		st.flag = true
		if old:remove() == false then
			st.fail = "Something went wrong. Nothing was taken."
			return
		end
		st.oldGone = true
	end)
	if ok and not st.fail and st.oldGone then
		return true
	end
	-- undo (the old item is still there: it is only gone when oldGone is set)
	if not st.oldGone then
		if st.flag then
			player:setStorageValue(flagKey, 0)
		end
		if st.materials then
			pcall(function() player:addItem(e.sourceId, r.materials) end)
		end
		if st.new then
			pcall(function() st.new:remove() end)
		end
	end
	if not ok then
		print("[potions] upgrade of " .. tostring(player:getName()) .. " to " .. tostring(targetId) .. " failed: " .. tostring(err))
	end
	return false, st.fail or "Something went wrong. Nothing was taken.", st.args
end

-- the tiers Veyra can offer now: the previous tier held, not done, whatever the level or the materials. Entries.
function PT.upgradeOffers(player)
	local out = {}
	for _, e in ipairs(K.upgradeTargets(PT.cfg())) do
		local r = PT.upgradeCheck(player, e.id, "quest")
		if r.ok or r.why == "level" or r.why == "materials" then
			out[#out + 1] = e
		end
	end
	return out
end

-- A lost flask (not carried anywhere, though a tier was earned): Veyra gives the highest tier earned for that slot back
-- for its price in gold. Returns true, entry | false, text, args.
function PT.restore(cid, slot)
	local player = Player(cid)
	if not player then
		return false, "This offer is not available."
	end
	local c = PT.cfg()
	local items = PT.everfullItems(player)
	local e = K.restoreFor(c, slot, heldIds(items), PT.earned(player))
	if not e or not PT.installed(e.id) then
		return false, "I have nothing to give back."
	end
	if (tonumber(player:getLevel()) or 0) < (e.level or 0) then
		return false, "This flask is for level %d and up, and you are not there yet.", {e.level}
	end
	if not ChaosPay then
		dofile("data/lib/chaos_pay.lua")
	end
	if ChaosPay.total(player) < e.price then
		return false, "You do not have enough money."
	end
	if not ChaosPay.pay(player, e.price) then
		return false, "You do not have enough gold (carried and in the bank)."
	end
	local where = PT.give(player, e.id)
	if not where then
		player:setBankBalance(player:getBankBalance() + e.price)
		return false, "You have no room for it."
	end
	return true, e
end

-- the slots a character lost a flask in: a list of {slot = , entry = }
function PT.restorable(player)
	local out = {}
	local held, earned = heldIds(PT.everfullItems(player)), PT.earned(player)
	for _, slot in ipairs(PT.cfg().pools) do
		local e = K.restoreFor(PT.cfg(), slot, held, earned)
		if e then
			out[#out + 1] = {slot = slot, entry = e}
		end
	end
	return out
end
