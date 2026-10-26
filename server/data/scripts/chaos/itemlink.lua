-- Item links in chat (client game_chatlinks, extended opcode ChaosOpcodes.itemLink = 249). The wire format, the cache and
-- the limits are in itemlink_core.lua (ChaosItemLink, tests/itemlink_test.lua); see server/README.md "Item links in chat".
--
-- Protocol (JSON {action, data}):
--   client -> server  register {n, items = [{pos = {x, y, z}, iid}], ctx = {kind, id}}   up to 3 items
--                     get {id}                                                            the snapshot behind a link id
--   server -> client  registered {n, links = [{token, name, rarity}]}  |  refused {n, reason}
--                     link {id, tip, owner, left} | link {id, gone = true}
--                     caps {help = true | false}                      at login: may this player link in the Help channel
-- pos is the client position of the item ({0xFFFF, slot, 0} inventory, {0xFFFF, 0x40 + container id, slot} an open
-- container), iid the item's per-item id (decimal string, see item_tooltip.lua). Only items the player carries are
-- linked: the item's top parent must be the player (inventory and the containers inside it, not the ground, a corpse,
-- a depot or another player's trade window). A locked item is linked like any other.
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
if not ChaosItemLink then
	dofile("data/scripts/chaos/itemlink_core.lua")
end

local K = ChaosItemLink
local T = ChaosItemTooltip
local OPCODE = ChaosOpcodes.itemLink or 249

K.cache = K.cache or K.newCache()
local registerBudget = {} -- player id -> bucket
local getBudget = {}
local strikes = {}

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function nowSec()
	return os.time()
end

-- random bytes from the system, nil when it cannot be read (then math.random is used)
local function systemBytes(n)
	local ok, data = pcall(function()
		local f = io.open("/dev/urandom", "rb")
		if not f then
			return nil
		end
		local s = f:read(n)
		f:close()
		return s
	end)
	return ok and data or nil
end

local function isTutor(player)
	return ACCOUNT_TYPE_TUTOR ~= nil and player:getAccountType() >= ACCOUNT_TYPE_TUTOR
end

local function itemAt(player, pos)
	local p = T.decodePos(pos)
	if not K.linkablePos(p) then
		return nil
	end
	local item
	if p.kind == "slot" then
		item = player:getSlotItem(p.slot)
	else
		local container = player:getContainerById(p.cid) -- only containers the engine has open for this player
		if not container then
			return nil
		end
		local first = tonumber(player:getContainerIndex(p.cid)) or 0
		item = container:getItem(first + p.index)
	end
	if not item then
		return nil
	end
	local ok, top = pcall(function() return item:getTopParent() end)
	if not ok or top ~= player then
		return nil
	end
	return item
end

local function equippedIds(player)
	local ids = {}
	for _, slot in ipairs(T.SLOTS) do
		local item = player:getSlotItem(slot)
		if item then
			ids[item:getId()] = true
		end
	end
	return ids
end

local function reply(player, action, data)
	Chaos.send(player, OPCODE, action, data)
end

local function register(player, data)
	local n = Chaos.toInt(data.n) or 0 -- echoed: never inf
	local function refuse(reason)
		reply(player, "refused", {n = n, reason = reason})
	end
	local list = type(data.items) == "table" and data.items or {}
	if #list == 0 then
		return
	end
	if #list > K.config.perMessage then
		return refuse(string.format("You can link up to %d items in one message.", K.config.perMessage))
	end
	local ok, why = K.contextAllowed(data.ctx, isTutor(player))
	if not ok then
		return refuse(why)
	end
	local pid = player:getId()
	registerBudget[pid] = registerBudget[pid] or {}
	if not K.allowRegister(registerBudget[pid], nowMs(), #list) then
		return refuse("You are linking items too fast.")
	end
	K.purge(K.cache, nowSec())
	local equipped = equippedIds(player)
	local links = {}
	for _, req in ipairs(list) do
		req = type(req) == "table" and req or {}
		local item = itemAt(player, req.pos)
		local iid = tonumber(req.iid) or 0
		if item and iid > 0 and (tonumber(ChaosCrafting.customNumber(item, "chaos_iid")) or 0) ~= iid then
			item = nil -- the item moved since the client looked
		end
		if not item then
			return refuse("You can only link items you carry.")
		end
		local attrs
		if item.getClientAttributes then
			local okAttrs, a = pcall(item.getClientAttributes, item)
			attrs = okAttrs and a or nil
		end
		local okTip, tip = pcall(T.build, item, {equippedIds = equipped, attrs = attrs})
		if not okTip then
			print("[itemlink] " .. tostring(tip))
			return refuse("That item cannot be linked.")
		end
		local entry = K.put(K.cache, {owner = player:getGuid(), ownerName = player:getName(), key = tip.key, tip = tip, now = nowSec(),
			id = K.makeId(systemBytes, math.random)})
		links[#links + 1] = {token = K.token(tip.name, tip.rarity, entry.id, tip.unique ~= nil), name = K.cleanName(tip.name),
			rarity = tip.rarity or 0, unique = tip.unique ~= nil}
	end
	reply(player, "registered", {n = n, links = links})
end

local function get(player, data)
	local id = data.id
	local pid = player:getId()
	getBudget[pid] = getBudget[pid] or {}
	if not K.allowGet(getBudget[pid], nowMs(), 1) then
		return
	end
	strikes[pid] = strikes[pid] or {}
	local t = nowSec()
	if K.blocked(strikes[pid], t) then
		return
	end
	local entry = K.get(K.cache, id, t)
	if not entry then
		K.strike(strikes[pid], t)
		reply(player, "link", {id = type(id) == "string" and id:sub(1, 12) or "", gone = true})
		return
	end
	-- the snapshot stays unscaled; what is sent has the display scale of the item's level requirement (DS.itemTip)
	local tip = entry.tip
	reply(player, "link", {id = entry.id, tip = (ChaosDisplayScale and ChaosDisplayScale.itemTip and ChaosDisplayScale.itemTip(tip) or tip), owner = entry.ownerName, left = K.remaining(entry, t)})
end

-- Help channel (and any channel script): true when the message must be refused. data/chatchannels/scripts/help.lua
-- calls this after tools/patch_help_itemlinks.py.
function K.helpBlocks(player, message)
	return K.hasLink(message) and not isTutor(player)
end

local ext = CreatureEvent("ChaosItemLinkExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg or type(msg.data) ~= "table" then
		return
	end
	if msg.action == "register" then
		register(player, msg.data)
	elseif msg.action == "get" then
		get(player, msg.data)
	end
end
ext:type("extendedopcode")
ext:register()

local login = CreatureEvent("ChaosItemLinkLogin")
function login.onLogin(player)
	player:registerEvent("ChaosItemLinkExtended")
	player:registerEvent("ChaosItemLinkLogout")
	addEvent(function(pid)
		local p = Player(pid)
		if p then
			reply(p, "caps", {help = isTutor(p)})
		end
	end, 2000, player:getId())
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("ChaosItemLinkLogout")
function logout.onLogout(player)
	local pid = player:getId()
	registerBudget[pid], getBudget[pid], strikes[pid] = nil, nil, nil
	return true
end
logout:type("logout")
logout:register()

-- O260 (the drop feed, retention_loot.lua): the link text of an item that is not in the player's hands, for a line the
-- server writes itself ("<name> (Lv N) found [Item]{...}!"). The snapshot is the tooltip as the item is now, owned by
-- `owner` (the finder), kept like any link for `ttl` seconds. Returns the token and the clean name, nil when the tooltip
-- cannot be built (the caller writes the plain name).
function K.linkFor(owner, item)
	local attrs
	if item.getClientAttributes then
		local okAttrs, a = pcall(item.getClientAttributes, item)
		attrs = okAttrs and a or nil
	end
	local okTip, tip = pcall(T.build, item, {equippedIds = {}, attrs = attrs})
	if not okTip or type(tip) ~= "table" then
		return nil
	end
	K.purge(K.cache, nowSec())
	local entry = K.put(K.cache, {owner = owner:getGuid(), ownerName = owner:getName(), key = tip.key, tip = tip, now = nowSec(),
		id = K.makeId(systemBytes, math.random)})
	return K.token(tip.name, tip.rarity, entry.id, tip.unique ~= nil), K.cleanName(tip.name)
end

return K
