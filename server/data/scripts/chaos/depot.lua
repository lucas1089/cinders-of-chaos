-- The depot, retired (O316; depot_config.lua, depot_core.lua; tools/patch_base_depot.py). The stash is the only item
-- storage; the depot chest of every town is withdraw-only and its content moves into the stash. What this file keeps:
--
--   ChaosDepot.onOpenLocker(player, locker, depotId)  called by the base locker Action (hook by patch_base_depot.py) and
--                                             by the hideout locker: the depot chest is loaded, and once the engine has
--                                             opened the locker the depot moves into the stash (ChaosStash.migrateDepot),
--                                             the stash window opens and the client closes the locker window
--   ChaosDepot.onMoveItem(...)                called first in Player:onMoveItem (hook by patch_base_depot.py): refuses a
--                                             move that adds to the depot chest or one of its boxes
--   ChaosDepot.checkAdd(player, container, item, count)  the same rule for a script that adds into a container
--   ChaosDepot.transition()                   stash_config.lua `depot` (withdrawOnly, migrate, version, openStash)
--
-- The inbox and the market item stay in the lockers for the engine (mail, house transfers, the market): the engine and
-- the scripts deliver into the inbox; players take it through the stash window (ChaosStash.collectInbox). No depot
-- window, no tab boxes, no depot tab store offers (server/README.md "Depot (retired)").
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/depot_core.lua")
Chaos.depotConfig = dofile("data/scripts/chaos/depot_config.lua")

ChaosDepot = ChaosDepot or {}
local Depot = ChaosDepot
local Core = ChaosDepotCore
local cfg = Chaos.depotConfig
local NOERR = RETURNVALUE_NOERROR or 0
local NOTPOSSIBLE = RETURNVALUE_NOTPOSSIBLE or 1
local CONTAINER_POS = CONTAINER_POSITION or 0xFFFF
local WARN = MESSAGE_STATUS_WARNING or MESSAGE_INFO_DESCR

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

-- the depot transition (stash_config.lua `depot`): migrate moves the character's depots into the stash at a locker
-- opening (stash.lua ChaosStash.migrateDepot); openStash opens the stash window
local stashCfg
function Depot.transition()
	local sc = Chaos.stashConfig or stashCfg
	if not sc then
		local ok, res = pcall(dofile, "data/scripts/chaos/stash_config.lua")
		stashCfg = ok and type(res) == "table" and res or {}
		sc = stashCfg
	end
	return sc.depot or {}
end

local warned = {}
local function warnOnce(key, text)
	if not warned[key] then
		warned[key] = true
		print("[Warning - Chaos depot] " .. text)
	end
end

-- ------------------------------------------------------------------ the locker
local clientLockerIds
local function lockerClientIds()
	if not clientLockerIds then
		clientLockerIds = {}
		for i, id in ipairs(cfg.lockerIds) do
			clientLockerIds[i] = ItemType(id):getClientId()
		end
	end
	return clientLockerIds
end

-- The depot chest is loaded (the engine writes it with the character from then on), the engine opens the locker as it
-- always did, and one event later - the chest now has its parent - the migration runs, the stash opens and the client
-- closes the locker window. depotId nil: read from the locker's unique id (the base depot lockers).
function Depot.onOpenLocker(player, locker, depotId)
	local ok, err = pcall(function()
		depotId = depotId or getDepotId(locker:getUniqueId())
		if not depotId then
			return
		end
		local chest = player:getDepotChest(depotId, true)
		if not chest then
			return
		end
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
		local tr = Depot.transition()
		local shown = Core.lockerOpen(cfg, tr)
		-- the engine writes the depot with the character from now on (a locker was opened this session): the depots can
		-- move into the stash safely
		if tr.migrate and ChaosStash and ChaosStash.migrateDepot then
			local okM, errM = pcall(ChaosStash.migrateDepot, player)
			if not okM then
				print("[Chaos depot] migration: " .. tostring(errM))
			end
		end
		player:sendTextMessage(MESSAGE_STATUS_DEFAULT or MESSAGE_INFO_DESCR, Chaos.t(player, shown.text))
		if shown.stash and ChaosStash and ChaosStash.openWindow then
			ChaosStash.openWindow(player, lockerClientIds())
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
	local m = {to = to, from = where, split = split,
		sameChest = where.chest ~= nil and acc.same(where.chest, to.chest),
		sameTab = where.kind == "tab" and to.kind == "tab" and where.tab == to.tab and acc.same(where.chest, to.chest)}
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
		player:sendTextMessage(WARN, Chaos.t(player, why.text))
		return NOTPOSSIBLE
	end
	return NOERR
end

-- for scripts that put an item into a container that may be the depot chest or a box: RETURNVALUE_NOERROR or the refusal
function Depot.checkAdd(player, container, item, count)
	local ok, why = pcall(refusal, player, item, count or item:getCount(), container, item:getParent())
	if ok and why then
		return NOTPOSSIBLE, why.text
	end
	return NOERR
end

-- ------------------------------------------------------------------ hooks
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
	warnOnce("locker", cfg.lockerScript .. " does not call ChaosDepot.onOpenLocker: the depot does not move into the stash. Run tools/patch_base_depot.py.")
end
local playerText = readFile("data/events/scripts/player.lua")
if playerText and not playerText:find("ChaosDepot.onMoveItem", 1, true) then
	warnOnce("move", "Player:onMoveItem does not call ChaosDepot.onMoveItem: the depot chest still takes items. Run tools/patch_base_depot.py.")
end
