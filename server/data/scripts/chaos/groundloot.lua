-- Ground loot labels (client game_groundlabels, extended opcode ChaosOpcodes.groundLoot = 230). The client sees the
-- items lying on the tiles around it but not their names, categories or decay; it asks for the tiles whose items
-- changed and draws a label per item in the rarity colour, following the player's loot filter.
-- Pure rules: groundloot_core.lua (tested by server/tests/groundloot_test.lua). Item classification is the loot
-- filter's (ChaosLootFilter.itemInfo, lootfilter.lua), so the labels and the corpse highlights always agree.
--
-- client -> server  look {t = [[x, y, z], ...]}           up to 30 tiles (same floor, within 8 x 6 squares)
--                   tip {p = [x, y, z], s, id}            rich tooltip of one ground item (s = index on the tile)
--                   raise {p, s, id, c, iid}              put that item on top of its pile (the client then moves it)
-- server -> client  tiles {t = [{p = [x, y, z], i = [item | corpse, ...]}]}   every asked tile is answered (i may be [])
--                       item   {s, id (client id), c, nm, r, u, o, pw, g, t, il, e}
--                       corpse {s, id, k = 1, n (items in it), i = [{c, nm, r, u, o, pw, g, t}, ...], e}
--                       (e = seconds until it decays, for a corpse until its loot is gone: the decay stages that
--                       are still containers summed; absent when it does not decay)
--                   tip {p, s, id, tip} | {p, s, id, gone = 1}   (tip as item_tooltip.lua builds it)
--                   raised {p, id} | {p, id, err = "far" | "sight" | "gone" | "fixed"}
--
-- What is never revealed: tiles outside the player's view or on another floor, items in a house the player does not
-- own, and the contents of a corpse the player may not open (another player's kill outside the party, the same rule
-- as the loot channel: ChaosLootFilter.canLoot). Picking an item up is not done here: the client moves it with the
-- normal move packet, so the engine checks range (walking there first), capacity, room, the corpse owner and every move
-- rule (Player:onMoveItem, season isolation) itself; "raise" only reorders a pile (see below).
-- Ground items have no owner in this engine and are never cleaned on a timer (cleanMap only runs from /clean or the
-- admin panel; the server save's clean is off): only items that decay (corpses, fields, some special items) expire,
-- and that is the time `e` carries.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/groundloot_core.lua")

local G = ChaosGroundLoot
local OPCODE = ChaosOpcodes.groundLoot
local budget = {} -- player id -> {tokens, at}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function pos3(p)
	return {p.x, p.y, p.z}
end

local function attr(item, key)
	local ok, v = pcall(function() return item:getAttribute(key) end)
	return ok and v or nil
end

local function expiryOf(item)
	if not ITEM_ATTRIBUTE_DECAYSTATE then
		return nil
	end
	return G.expiry(attr(item, ITEM_ATTRIBUTE_DECAYSTATE), attr(item, ITEM_ATTRIBUTE_DURATION))
end

-- the stages a corpse decays into after the current one (at most 8), for G.lootExpiry
local function stagesAfter(itemType)
	local chain = {}
	local id = itemType:getDecayId()
	for _ = 1, 8 do
		if not id or id <= 0 then
			chain[#chain + 1] = {container = false} -- decays to nothing
			break
		end
		local t = ItemType(id)
		if not t or t:getId() == 0 then
			break
		end
		local nextId = t:getDecayId()
		chain[#chain + 1] = {container = t:isContainer(), seconds = (nextId and nextId >= 0) and t:getDuration() or 0}
		if not t:isContainer() then
			break
		end
		id = nextId
	end
	return chain
end

local function lootExpiryOf(corpse)
	local first = expiryOf(corpse)
	if not first then
		return nil
	end
	local ok, chain = pcall(stagesAfter, corpse:getType())
	return G.lootExpiry(first, ok and chain or {})
end

local function houseAllowed(player, tile)
	local house = tile:getHouse()
	return not house or house:getOwnerGuid() == player:getGuid()
end

local function corpseOf(item)
	if not item:isContainer() then
		return false
	end
	local owner = item:getCorpseOwner()
	return G.isCorpse({container = true, corpseType = item:getType():isCorpse(), owner = owner})
end

local function describeTile(player, pos)
	local F = ChaosLootFilter
	local out = {}
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	if not tile or not F or not F.itemInfo or not houseAllowed(player, tile) then
		return out
	end
	for _, item in ipairs(tile:getItems() or {}) do
		if #out >= G.config.maxItemsPerTile then
			break
		end
		local itemType = item:getType()
		local s = tile:getThingIndex(item)
		if corpseOf(item) then
			if F.canLoot and F.canLoot(player, item) then
				local infos = {}
				for _, inside in ipairs(item:getItems() or {}) do
					infos[#infos + 1] = F.itemInfo(inside)
				end
				if #infos > 0 then
					out[#out + 1] = G.wireCorpse(s, itemType:getClientId(), infos, lootExpiryOf(item))
				end
			end
		elseif itemType:isPickupable() and itemType:isMovable() then
			out[#out + 1] = G.wireItem(F.itemInfo(item), s, expiryOf(item))
		end
	end
	return out
end

local function look(player, data)
	local req = G.parseTiles(data.t, player:getPosition())
	local cost = #req.valid + #req.refused
	if cost == 0 then
		return
	end
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not G.allow(budget[pid], nowMs(), cost) then
		return -- the client asks again for tiles left unanswered
	end
	local tiles = {}
	for _, p in ipairs(req.valid) do
		local ok, items = pcall(describeTile, player, p)
		if not ok then
			print("[Chaos groundloot] " .. tostring(items))
			items = {}
		end
		tiles[#tiles + 1] = {p = pos3(p), i = items}
	end
	for _, p in ipairs(req.refused) do
		tiles[#tiles + 1] = {p = pos3(p), i = {}}
	end
	for _, payload in ipairs(G.pack(tiles, json.encode)) do
		player:sendExtendedOpcode(OPCODE, payload)
	end
end

local function tip(player, data)
	local p = G.parsePos(data.p)
	local s = Chaos.toInt(data.s, 0, 255)
	local id = Chaos.toInt(data.id, 1, 0xFFFF)
	if not p or not s or not id then
		return
	end
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not G.allow(budget[pid], nowMs(), 2) then
		return
	end
	local reply = {p = pos3(p), s = s, id = id}
	local target = Position(p.x, p.y, p.z)
	local tile = G.inView(player:getPosition(), p) and player:canSee(target) and Tile(target)
	local item = tile and houseAllowed(player, tile) and tile:getThing(s)
	if not item or not item.isItem or not item:isItem() or item:getType():getClientId() ~= id or corpseOf(item)
		or not ChaosItemTooltip or not ChaosItemTooltip.build then
		reply.gone = 1
		return Chaos.send(player, OPCODE, "tip", reply)
	end
	local attrs
	if item.getClientAttributes then
		local ok, a = pcall(item.getClientAttributes, item)
		attrs = ok and a or nil
	end
	local T = ChaosItemTooltip
	local equipped = {}
	for _, slot in ipairs(T.SLOTS or {1, 2, 3, 4, 5, 6, 7, 8, 9, 13}) do
		local worn = player:getSlotItem(slot)
		if worn then
			equipped[worn:getId()] = true
		end
	end
	-- the viewer's attack speed inputs for "Your Attack Interval" on weapons, as item_tooltip.lua passes them
	local voc = player:getVocation()
	local wielder = {voc = voc and voc:getAttackSpeed() or 2000,
		dex = CHARSTAT_DEXTERITY and player.getCharacterStat and player:getCharacterStat(CHARSTAT_DEXTERITY) or 0}
	local ok, built = pcall(T.build, item, {equippedIds = equipped, attrs = attrs, wielder = wielder})
	if ok and type(built) == "table" then
		local tip = built -- the display scale of the item's level requirement (display_scale_core.lua DS.itemTip)
		reply.tip = (ChaosDisplayScale and ChaosDisplayScale.itemTip and ChaosDisplayScale.itemTip(tip) or tip)
	else
		reply.gone = 1
		print("[Chaos groundloot] tooltip: " .. tostring(built))
	end
	Chaos.send(player, OPCODE, "tip", reply)
end

-- ---------------------------------------------------------------- raise (click to pick up from a pile)
-- The engine only ever moves the TOP item of a ground pile (Game::internalGetThing, STACKPOS_MOVE), so a label of an
-- item lower in the pile cannot be picked with the move packet. "raise" puts that one item on top of its own tile
-- (through a bag that exists for this call only) and the client then sends the normal move: the engine walks there,
-- checks capacity and room, and every move rule (Player:onMoveItem, season isolation) still applies. Nothing leaves
-- the tile here. Checked: the tile is in view and on the player's floor, the player can see it and has a line of
-- sight to it (or stands next to it), it is not another player's house, the item is still there with the same client
-- id, count and per-item id, it can be picked up, it is not a corpse and has no unique id.
local RAISE_BAG = 1987

local function iidOf(item)
	local ok, v = pcall(function() return item:getCustomAttribute("chaos_iid") end)
	return ok and tonumber(v) or 0
end

local function sameItem(item, id, count, iid)
	if not item or not item.isItem or not item:isItem() then
		return false
	end
	if item:getType():getClientId() ~= id or item:getCount() ~= count then
		return false
	end
	return iid == 0 or iidOf(item) == iid
end

-- the index of the top item of the pile: the first item (not the ground) that is not always on top (borders, walls)
local function topDownItem(tile)
	local ok, item = pcall(function() return tile:getTopDownItem() end)
	return ok and item or nil
end

local function raise(player, data)
	local p = G.parsePos(data.p)
	local s = Chaos.toInt(data.s, 0, 255)
	local id = Chaos.toInt(data.id, 1, 0xFFFF)
	local count = Chaos.toInt(data.c, 1, 0xFFFF)
	local iid = G.parseIid(data.iid)
	if not p or not s or not id or not count or not iid then
		return
	end
	local pid = player:getId()
	budget[pid] = budget[pid] or {}
	if not G.allow(budget[pid], nowMs(), 4) then
		return
	end
	local reply = {p = pos3(p), id = id}
	local function refuse(why)
		reply.err = why
		Chaos.send(player, OPCODE, "raised", reply)
	end
	local me = player:getPosition()
	local target = Position(p.x, p.y, p.z)
	if not G.inView(me, p) or not player:canSee(target) then
		return refuse("far")
	end
	local near = math.abs(me.x - p.x) <= 1 and math.abs(me.y - p.y) <= 1
	local okSight, sight = pcall(function() return me:isSightClear(target, true) end)
	if not near and not (okSight and sight) then
		return refuse("sight")
	end
	local tile = Tile(target)
	if not tile or not houseAllowed(player, tile) then
		return refuse("gone")
	end
	-- the item at its index, else the same item anywhere on the tile (the pile changed since the client asked)
	local item = tile:getThing(s)
	if not sameItem(item, id, count, iid) then
		item = nil
		for _, it in ipairs(tile:getItems() or {}) do
			if sameItem(it, id, count, iid) then
				item = it
				break
			end
		end
	end
	if not item then
		return refuse("gone")
	end
	local itemType = item:getType()
	-- a map unique id (quest items); Item:getUniqueId() would hand out a temporary script id for any other item
	local okUid, hasUid = pcall(function() return ITEM_ATTRIBUTE_UNIQUEID and item:hasAttribute(ITEM_ATTRIBUTE_UNIQUEID) end)
	if not itemType:isPickupable() or not itemType:isMovable() or corpseOf(item) or (okUid and hasUid) then
		return refuse("fixed")
	end
	if topDownItem(tile) ~= item then
		local bag = Game.createItem(RAISE_BAG, 1)
		if not bag or not item:moveTo(bag) then
			return refuse("gone")
		end
		if not item:moveTo(target, FLAG_NOLIMIT) then
			bag:moveTo(target, FLAG_NOLIMIT) -- never lose it: the bag (with the item) stays on the tile
			return refuse("gone")
		end
	end
	Chaos.send(player, OPCODE, "raised", reply)
end

local ext = CreatureEvent("ChaosGroundLootExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.data) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		if msg.action == "look" then
			look(player, msg.data)
		elseif msg.action == "tip" then
			tip(player, msg.data)
		elseif msg.action == "raise" then
			raise(player, msg.data)
		end
	end)
	if not ok then
		print("[Chaos groundloot] opcode failed: " .. tostring(err))
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosGroundLootLogin")
function login.onLogin(player)
	player:registerEvent("ChaosGroundLootExtended")
	player:registerEvent("ChaosGroundLootLogout")
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosGroundLootLogout")
function logout.onLogout(player)
	budget[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()
