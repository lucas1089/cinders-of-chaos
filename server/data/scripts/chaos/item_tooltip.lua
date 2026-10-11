-- Rich item tooltips (client game_itemtooltip, extended opcode ChaosOpcodes.itemTooltip). The client hovers an item in
-- its inventory or an open container and asks for its tooltip; holding Ctrl it also asks for the equipped items the
-- tooltip names in `cmp` and shows them side by side with the differences. What a tooltip holds is built by
-- item_tooltip_core.lua (ChaosItemTooltip.build); see server/README.md "Item attributes and rich tooltips".
--
-- Protocol (JSON {action, data}):
--   client -> server  get {items = [{pos = {x, y, z, s}, iid}]}        up to ChaosItemTooltip.config.maxItems items
--   server -> client  tips {items = [{pos, iid, tip} | {pos, iid, gone = true}]}
-- pos is the client's position of the item: {0xFFFF, slot, 0} for the inventory, {0xFFFF, 0x40 + container id, slot}
-- for an open container (slot on the current page), a map position with the stack position `s` for the ground. iid
-- is the item's per-item id from its client attributes as a decimal string (0 when it has none; a JSON number would lose
-- digits: ids reach 2^51): when it is set and the item found at pos
-- has another one, the answer is `gone` (the item moved). Nothing outside the player's own inventory, the containers
-- the engine has open for this player and visible map tiles next to the player is ever read.
-- Every request spends one token per item from a budget of ChaosItemTooltip.config.bucketSize, refilled at
-- bucketPerSecond; a request over the budget is dropped (the client asks again on the next hover).
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCrafting then
	dofile("data/lib/chaos_crafting.lua")
end
if not ChaosItemTooltip then
	dofile("data/scripts/chaos/item_tooltip_core.lua")
end

local T = ChaosItemTooltip
local OPCODE = ChaosOpcodes.itemTooltip or 242
local budget = {} -- player id -> {tokens, at}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function itemAt(player, pos)
	local p = T.decodePos(pos)
	if not p then
		return nil
	end
	if p.kind == "slot" then
		return player:getSlotItem(p.slot)
	elseif p.kind == "container" then
		local container = player:getContainerById(p.cid) -- only containers the engine has open for this player
		if not container then
			return nil
		end
		local first = tonumber(player:getContainerIndex(p.cid)) or 0
		return container:getItem(first + p.index)
	end
	local target = Position(p.x, p.y, p.z)
	if not T.mapAllowed(player:getPosition(), target, player:canSee(target)) then
		return nil
	end
	local tile = Tile(target)
	local thing = tile and tile:getThing(p.stackpos)
	if thing and thing.isItem and thing:isItem() then
		return thing
	end
	return nil
end

local function equippedIds(player)
	local ids = {}
	for slot = T.SLOT_FIRST, T.SLOT_LAST do
		local item = player:getSlotItem(slot)
		if item then
			ids[item:getId()] = true
		end
	end
	return ids
end

local function answer(player, data)
	local list = type(data.items) == "table" and data.items or {}
	local n = math.min(#list, T.config.maxItems)
	if n == 0 then
		return
	end
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not T.allow(budget[pid], nowMs(), n) then
		return
	end
	local equipped = equippedIds(player)
	-- the viewer's worn set pieces (itemsets.lua): the set block of a piece's tooltip
	local setState = ChaosItemSets and ChaosItemSets.stateOf and ChaosItemSets.stateOf(player) or nil
	-- the viewer's attack speed inputs for "Your Attack Interval" on weapons (attack speed cap, engine patch 0011)
	local voc = player:getVocation()
	local wielder = {voc = voc and voc:getAttackSpeed() or 2000,
		dex = CHARSTAT_DEXTERITY and player.getCharacterStat and player:getCharacterStat(CHARSTAT_DEXTERITY) or 0}
	local out = {}
	for i = 1, n do
		local req = type(list[i]) == "table" and list[i] or {}
		local iid = tonumber(req.iid) or 0
		local row = {pos = req.pos, iid = type(req.iid) == "string" and req.iid:sub(1, 20) or iid} -- echoed as sent
		local item = itemAt(player, req.pos)
		if item and iid > 0 then
			local own = tonumber(ChaosCrafting.customNumber(item, "chaos_iid")) or 0
			if own ~= iid then
				item = nil
			end
		end
		if item then
			local attrs
			if item.getClientAttributes then
				local ok, a = pcall(item.getClientAttributes, item)
				attrs = ok and a or nil
			end
			local ok, tip = pcall(T.build, item, {equippedIds = equipped, attrs = attrs, wielder = wielder, setState = setState})
			if ok then
				row.tip = tip
			else
				row.gone = true
				print("[item_tooltip] " .. tostring(tip))
			end
		else
			row.gone = true
		end
		out[#out + 1] = row
	end
	Chaos.send(player, OPCODE, "tips", {items = out})
end

local ext = CreatureEvent("ChaosItemTooltipExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or msg.action ~= "get" or type(msg.data) ~= "table" then
		return
	end
	answer(player, msg.data)
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosItemTooltipLogin")
function login.onLogin(player)
	player:registerEvent("ChaosItemTooltipExtended")
	player:registerEvent("ChaosItemTooltipLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosItemTooltipLogout")
function logout.onLogout(player)
	budget[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()
