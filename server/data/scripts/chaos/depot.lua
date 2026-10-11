-- Depot tabs (depot_config.lua, depot_core.lua; client game_depottabs; tools/patch_base_depot.py).
--
-- The depot chest of every town holds one box per tab (tab n = depot_config.lua boxIds[n], "depot tab n", 100 slots).
-- An account may fill tabs 1..ChaosDepot.tabs(player): free + Chaos Pact + bought (pact_config.lua limit depotTabs,
-- store category "Depot Tabs") + achievement tabs, at most the number of boxes. A tab holds 100 items, a container
-- counting as 1 plus its contents. Higher tabs are withdraw-only. Nothing is ever deleted.
--
--   ChaosDepot.onOpenLocker(player, locker)   called by the base locker Action (hook by patch_base_depot.py): the boxes
--                                             are made, loose items of before tabs are sorted into tabs, the box
--                                             descriptions and the client are updated
--   ChaosDepot.onMoveItem(...)                called first in Player:onMoveItem (hook by patch_base_depot.py): refuses
--                                             a move that adds to a locked or full tab, or loose into the chest
--   ChaosDepot.checkAdd(player, container, item, count)  the same rule for a script that adds into a container
--   ChaosDepot.tabs(player)                   the account's tab count
--   ChaosDepot.onLimitsChanged(player)        pact.lua calls it after a store purchase of tabs
--
-- The inbox stays unlimited: the engine (market, mail, house transfer) and the scripts deliver there; the engine never
-- adds to a depot box itself (server/README.md "Depot tabs", coverage).
--
-- Protocol (extended opcode ChaosOpcodes.depotTabs = 111, JSON {action, data}), server -> client only:
--   tabs {tabs, max, size, used = [n per tab] (missing: unchanged), ids = [client id per tab], chest = [client ids],
--         hint}
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/depot_core.lua")
Chaos.depotConfig = dofile("data/scripts/chaos/depot_config.lua")

ChaosDepot = ChaosDepot or {}
local Depot = ChaosDepot
local Core = ChaosDepotCore
local cfg = Chaos.depotConfig
local OPCODE = ChaosOpcodes.depotTabs or 111
local NOERR = RETURNVALUE_NOERROR or 0
local NOTPOSSIBLE = RETURNVALUE_NOTPOSSIBLE or 1
local NOROOM = RETURNVALUE_CONTAINERNOTENOUGHROOM or NOTPOSSIBLE
local CONTAINER_POS = CONTAINER_POSITION or 0xFFFF
local WARN = MESSAGE_STATUS_WARNING or MESSAGE_INFO_DESCR

Depot.achTabs = Depot.achTabs or {} -- account id -> achievement tabs (loaded at login and at every locker opening)

-- ------------------------------------------------------------------ engine accessors (depot_core.lua `acc`)
local function isContainer(n)
	if type(n) ~= "userdata" and type(n) ~= "table" then -- engine objects are userdata (tables in the tests)
		return false
	end
	local ok, res = pcall(function() return n.isContainer ~= nil and n:isContainer() end)
	return ok and res == true
end

local acc = {
	id = function(n) return n:getId() end,
	parent = function(n)
		local ok, p = pcall(n.getParent, n)
		if ok and isContainer(p) then
			return p
		end
		return nil
	end,
	isContainer = isContainer,
	itemAt = function(n, slot) return n:getItem(slot) end,
	capacity = function(n) return n:getCapacity() end,
	same = function(a, b)
		if a == nil or b == nil then
			return false
		end
		local ok, res = pcall(function() return a == b end)
		return ok and res == true
	end
}

local function children(n)
	if isContainer(n) then
		return n:getItems(false)
	end
	return nil
end

local warned = {}
local function warnOnce(key, text)
	if not warned[key] then
		warned[key] = true
		print("[Warning - Chaos depot] " .. text)
	end
end

-- ------------------------------------------------------------------ the account's tabs
local function pactFree()
	local pc = Chaos.pactConfig
	if not pc then
		local ok, res = pcall(dofile, "data/scripts/chaos/pact_config.lua")
		pc = ok and res or nil
	end
	local l = pc and pc.limits and pc.limits[cfg.limitKey]
	return l and l.free or 0
end

local function loadAchievementTabs(accountId)
	local ids = {}
	for _, a in ipairs(cfg.achievementTabs) do
		ids[#ids + 1] = db.escapeString(a)
	end
	if #ids == 0 then
		return 0
	end
	local r = Chaos.select(string.format("SELECT COUNT(DISTINCT a.`achievement`) AS `n` FROM `chaos_achievements` a " ..
		"JOIN `players` p ON p.`id` = a.`player_id` WHERE p.`account_id` = %d AND a.`achievement` IN (%s)",
		accountId, table.concat(ids, ", ")), {{"n", "n"}})[1]
	local n = r and r.n or 0
	Depot.achTabs[accountId] = n
	return n
end

function Depot.tabs(player)
	local limit
	if ChaosPact and ChaosPact.limit then
		local ok, res = pcall(ChaosPact.limit, player, cfg.limitKey)
		limit = ok and res or nil
	end
	limit = limit or pactFree()
	local accountId = player:getAccountId()
	local ach = Depot.achTabs[accountId]
	if ach == nil then
		ach = loadAchievementTabs(accountId)
	end
	return Core.tabCount(cfg, limit, ach)
end

-- ------------------------------------------------------------------ the chest
-- {[tab] = box}, {loose items} of a depot chest
local function scan(chest)
	local boxes, loose = {}, {}
	for _, it in ipairs(chest:getItems(false) or {}) do
		local t = Core.tabOf(cfg, it:getId())
		if t and not boxes[t] then
			boxes[t] = it
		else
			loose[#loose + 1] = it
		end
	end
	return boxes, loose
end

local function usedOf(boxes)
	local used = {}
	for t, box in pairs(boxes) do
		used[t] = Core.holding(box, children)
	end
	return used
end

-- the boxes that are missing (in reverse, so that tab 1 comes first: a container adds at the front)
function Depot.ensure(chest)
	local boxes = scan(chest)
	local made = 0
	for t = Core.maxTabs(cfg), 1, -1 do
		if not boxes[t] then
			local box = chest:addItem(cfg.boxIds[t], 1, INDEX_WHEREEVER or -1, FLAG_NOLIMIT or 1)
			if not box then
				warnOnce("ensure", "a depot tab could not be made (item " .. cfg.boxIds[t] .. "): run tools/patch_base_depot.py " ..
					"(the boxes must be pickupable in items.otb)")
				return made
			end
			made = made + 1
		end
	end
	return made
end

-- loose items of the chest of before tabs go into tabs (open ones first, then locked ones); nil when there were none
function Depot.migrate(chest, tabs)
	local boxes, loose = scan(chest)
	local items = {}
	local movable = {}
	for _, it in ipairs(loose) do
		local okType, canMove = pcall(function() return it:getType():isMovable() end)
		if not okType or canMove then
			movable[#movable + 1] = it
			items[#items + 1] = {key = #movable, weight = Core.weight(it, children)}
		end
	end
	if #items == 0 then
		return nil
	end
	local moves, counts = Core.layout(cfg, tabs, usedOf(boxes), items)
	for _, m in ipairs(moves) do
		local box = boxes[m.tab]
		local it = movable[m.key]
		if box and it and not it:moveTo(box) then
			counts.loose = counts.loose + 1
			if m.tab <= tabs then
				counts.open = counts.open - 1
			else
				counts.locked = counts.locked - 1
			end
		end
	end
	counts.loose = counts.loose + (#loose - #movable)
	return counts
end

local clientIds
local function ids()
	if not clientIds then
		clientIds = {tabs = {}, chest = {}}
		for i, id in ipairs(cfg.boxIds) do
			clientIds.tabs[i] = ItemType(id):getClientId()
		end
		for i, id in ipairs(cfg.chestIds) do
			clientIds.chest[i] = ItemType(id):getClientId()
		end
	end
	return clientIds
end

local function sendTabs(player, tabs, used)
	local list
	if used then
		list = {}
		for t = 1, Core.maxTabs(cfg) do
			list[t] = used[t] or 0
		end
	end
	local i = ids()
	Chaos.send(player, OPCODE, "tabs", {tabs = tabs, max = Core.maxTabs(cfg), size = cfg.tabSize, used = list, ids = i.tabs,
		chest = i.chest, hint = cfg.messages.hint})
end

-- box descriptions (look text) and the client's counts
function Depot.refresh(player, chest, tabs)
	local boxes = scan(chest)
	local used = usedOf(boxes)
	for t, box in pairs(boxes) do
		local text = Core.description(cfg, t, tabs, used[t] or 0)
		local okGet, old = pcall(box.getAttribute, box, ITEM_ATTRIBUTE_DESCRIPTION)
		if not okGet or old ~= text then
			box:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, text)
		end
	end
	sendTabs(player, tabs, used)
	return used
end

function Depot.onOpenLocker(player, locker)
	local ok, err = pcall(function()
		local depotId = getDepotId(locker:getUniqueId())
		if not depotId then
			return
		end
		local chest = player:getDepotChest(depotId, true)
		if not chest then
			return
		end
		loadAchievementTabs(player:getAccountId())
		Depot.ensure(chest)
		-- the rest waits until the engine has opened the locker: a chest the engine has not put into its locker yet has
		-- no parent, and the engine treats its contents as removed (Item:moveTo does nothing)
		local cid = player:getId()
		addEvent(function()
			local p = Player(cid)
			if p then
				Depot.afterOpen(p, depotId)
			end
		end, 0)
	end)
	if not ok then
		print("[Chaos depot] locker: " .. tostring(err))
	end
end

function Depot.afterOpen(player, depotId)
	local ok, err = pcall(function()
		local chest = player:getDepotChest(depotId, false)
		if not chest then
			return
		end
		local tabs = Depot.tabs(player)
		local counts = Depot.migrate(chest, tabs)
		Depot.refresh(player, chest, tabs)
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, Core.openText(cfg, tabs))
		if counts and (counts.open + counts.locked) > 0 then
			player:sendTextMessage(MESSAGE_INFO_DESCR, Core.sortedText(cfg, counts))
			print(string.format("[Chaos depot] %s: depot %d sorted into tabs (%d open, %d locked, %d loose)", player:getName(),
				depotId, counts.open, counts.locked, counts.loose))
		end
	end)
	if not ok then
		print("[Chaos depot] locker: " .. tostring(err))
	end
end

-- ------------------------------------------------------------------ the move rule
-- nil when allowed, else the refusal {code, text}. dest: the container the item goes into (after the engine's own
-- choice of a slot's container); from: the container it comes from (nil: inventory or ground)
local function refusal(player, item, count, dest, from)
	local to = Core.locate(cfg, dest, acc)
	if to.kind == "other" then
		return nil
	end
	local where = Core.locate(cfg, isContainer(from) and from or nil, acc)
	local split = false
	local okS, stackable = pcall(function() return item:getType():isStackable() end)
	if okS and stackable and count and count < item:getCount() then
		split = true
	end
	local m = {to = to, from = where, split = split, tabs = Depot.tabs(player),
		sameChest = where.chest ~= nil and acc.same(where.chest, to.chest),
		sameTab = where.kind == "tab" and to.kind == "tab" and where.tab == to.tab and acc.same(where.chest, to.chest)}
	if to.kind == "tab" then
		m.used = Core.holding(to.box, children)
		m.weight = split and 1 or Core.weight(item, children)
	end
	return Core.decide(cfg, m)
end

function Depot.onMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not toPosition or toPosition.x ~= CONTAINER_POS or not isContainer(toCylinder) then
		return NOERR
	end
	local ok, why = pcall(function()
		local dest = Core.destination(toCylinder, toPosition.z, acc)
		return refusal(player, item, count, dest, fromCylinder)
	end)
	if not ok then
		print("[Chaos depot] move check: " .. tostring(why))
		return NOERR
	end
	if why then
		player:sendTextMessage(WARN, why.text)
		return why.code == "full" and NOROOM or NOTPOSSIBLE
	end
	return NOERR
end

-- for scripts that put an item into a container that may be a depot tab: RETURNVALUE_NOERROR or the refusal
function Depot.checkAdd(player, container, item, count)
	local ok, why = pcall(refusal, player, item, count or item:getCount(), container, item:getParent())
	if ok and why then
		return why.code == "full" and NOROOM or NOTPOSSIBLE, why.text
	end
	return NOERR
end

function Depot.onLimitsChanged(player)
	sendTabs(player, Depot.tabs(player), nil)
end

-- after a move into or out of the depot: box descriptions and the client's counts
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if (not fromPosition or fromPosition.x ~= CONTAINER_POS) and (not toPosition or toPosition.x ~= CONTAINER_POS) then
		return
	end
	local ok, err = pcall(function()
		for _, cyl in ipairs({toCylinder, fromCylinder}) do
			if isContainer(cyl) then
				local loc = Core.locate(cfg, cyl, acc)
				if loc.chest then
					Depot.refresh(player, loc.chest, Depot.tabs(player))
					return
				end
			end
		end
	end)
	if not ok then
		print("[Chaos depot] refresh: " .. tostring(err))
	end
end
moved:register(13)

-- ------------------------------------------------------------------ login, hooks
local login = CreatureEvent("ChaosDepotLogin")
function login.onLogin(player)
	local cid = player:getId()
	pcall(loadAchievementTabs, player:getAccountId())
	addEvent(function()
		local p = Player(cid)
		if p then
			pcall(function() sendTabs(p, Depot.tabs(p), nil) end)
		end
	end, 2000)
	return true
end
login:register()

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

-- the base locker Action calls onOpenLocker (patch_base_depot.py); without that file our own Action does
local lockerText = readFile(cfg.lockerScript)
if not lockerText then
	local open = Action()
	function open.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		Depot.onOpenLocker(player, item)
		return false -- the engine opens the locker as usual
	end
	for _, id in ipairs(cfg.lockerIds) do
		open:id(id)
	end
	open:register()
elseif not lockerText:find("ChaosDepot.onOpenLocker", 1, true) then
	warnOnce("locker", cfg.lockerScript .. " does not call ChaosDepot.onOpenLocker: no depot tabs are made. Run tools/patch_base_depot.py.")
end
local playerText = readFile("data/events/scripts/player.lua")
if playerText and not playerText:find("ChaosDepot.onMoveItem", 1, true) then
	warnOnce("move", "Player:onMoveItem does not call ChaosDepot.onMoveItem: depot tab limits are not enforced. Run tools/patch_base_depot.py.")
end
