-- Ground pickups: the shared framework of the health / mana globes (globes.lua) and the Ember Blessings' ember
-- (blessings.lua). A pickup is a non-pickupable, non-moveable item (items 32088-32090, tools/install_pickups.py) on a
-- tile, a record in memory (pickups_core.lua) and a callback. Rules: pickups_core.lua; numbers: pickups_config.lua;
-- overview server/README.md "Ground pickups and globes".
--
--   ChaosPickups.drop(spec)       spec {itemKey, kind, pos, ownerId, ttlMs, ownerWindowMs, onTake(player, entry), name,
--                                 desc, data} -> entry | nil, why. Picks a free tile near pos, creates the item.
--   ChaosPickups.installed(key)   the item is in items.otb (install_pickups.py ran)
--   ChaosPickups.blocked(player)  reason | nil: a place without globes (config `blocked`)
--   ChaosPickups.countOf(ownerId, kind)
--   stepping on it   MoveEvent stepin on the item ids: the owner (and the owner's party after the owner window) takes it:
--                    onTake runs once; a stranger gets a message; a monster or summon walks over it untouched. An item
--                    with no record (a crash, a reload) is removed and grants nothing.
--   under the feet   a pickup that lands on a tile where a player stands is taken at once by whoever may (no step event
--                    fires for a player already there).
--   the look-out     GlobalEvent every tickMs: runs out -> the item is removed with a fade effect; the glow pulses; a sweep
--                    removes any item of ours whose record is gone (every tile an item was put on is tracked).
-- State is in memory only: a restart or reload forgets every pickup, and an item left on the map is removed by the
-- first step on it (or by its failsafe decay). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
ChaosPickupsConfig = dofile("data/scripts/chaos/pickups_config.lua")
dofile("data/scripts/chaos/pickups_core.lua")

ChaosPickups = ChaosPickups or {}
local X = ChaosPickups
local K = ChaosPickupsCore
X.reg = X.reg or K.new()
X.tracked = X.tracked or {} -- every tile an item of ours was put on, until the sweep finds it empty (pickups_core.lua)

local function cfg()
	return ChaosPickupsConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function itemRow(key)
	for _, row in ipairs(cfg().items) do
		if row.key == key then
			return row
		end
	end
	return nil
end
X.itemRow = itemRow

function X.installed(key)
	local row = itemRow(key)
	if not row then
		return false
	end
	local ok, it = pcall(ItemType, row.id)
	return ok and it ~= nil and it:getId() ~= 0
end

function X.countOf(ownerId, kind)
	return K.countOf(X.reg, ownerId, kind)
end

local function effectId(name)
	return name and rawget(_G, name) or nil
end

local function sendEffect(x, y, z, name)
	local e = effectId(name)
	if e then
		pcall(function() Position(x, y, z):sendMagicEffect(e) end)
	end
end
X.sendEffect = sendEffect

-- ---------------------------------------------------------------- where nothing drops
local function inBox(pos, b)
	return pos.z == (b[5] or pos.z) and pos.x >= b[1] and pos.x <= b[3] and pos.y >= b[2] and pos.y <= b[4]
end

function X.blocked(player)
	local c = cfg().blocked or {}
	local ok, pos = pcall(function() return player:getPosition() end)
	if ok and pos then
		for _, b in ipairs(c.boxes or {}) do
			if inBox(pos, b) then
				return "box"
			end
		end
	end
	if Chaos.inAnyInstance then
		local okI, key = pcall(Chaos.inAnyInstance, player)
		if okI and key and (c.instances or {})[key] then
			return key
		end
	end
	local B = rawget(_G, "ChaosBlessings")
	if B and B.pvpPlace then
		local okP, place = pcall(B.pvpPlace, player)
		if okP and place then
			return place
		end
	end
	return nil
end

-- ---------------------------------------------------------------- placing
local function freeTile(pos)
	for _, off in ipairs(cfg().placeOffsets) do
		local p = Position(pos.x + off[1], pos.y + off[2], pos.z)
		local tile = Tile(p)
		if tile and tile:getGround() and not (TILESTATE_BLOCKSOLID and tile:hasFlag(TILESTATE_BLOCKSOLID))
				and #K.at(X.reg, p.x, p.y, p.z) == 0 then
			return p
		end
	end
	return nil
end

function X.drop(spec)
	local c = cfg()
	if c.enabled == false then
		return nil, "disabled"
	end
	local row = itemRow(spec.itemKey)
	if not row or not X.installed(spec.itemKey) then
		return nil, "not installed"
	end
	local pos = freeTile(spec.pos)
	if not pos then
		return nil, "no tile"
	end
	local item = Game.createItem(row.id, 1, pos)
	if not item then
		return nil, "no item"
	end
	pcall(function()
		if spec.name then
			item:setAttribute(ITEM_ATTRIBUTE_NAME, spec.name)
		end
		if spec.desc then
			item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, spec.desc)
		end
		item:decay() -- the failsafe (items.xml decayTo 0 after cfg.failsafeSeconds)
	end)
	local entry = K.add(X.reg, {
		kind = spec.kind or spec.itemKey, itemKey = spec.itemKey, x = pos.x, y = pos.y, z = pos.z,
		ownerId = spec.ownerId, ttlMs = spec.ttlMs, ownerWindowMs = spec.ownerWindowMs, onTake = spec.onTake,
		data = spec.data
	}, nowMs())
	K.track(X.tracked, entry)
	sendEffect(pos.x, pos.y, pos.z, row.glow)
	X.refreshAt(pos)
	X.takeUnderFeet(entry, item, pos)
	return entry
end

-- O349 (src-patch 0084): the tile goes to every player who sees it whole again after a pickup is put down or taken. A
-- creation or a removal by stack position misses on a client whose tile holds a thing the server's does not (a dead
-- monster still drawn, O352): the own character was taken off its tile (invisible) and the globe stayed. No-op on an
-- engine without the patch.
local function refreshAt(pos)
	local tile = pos and Tile(pos)
	if tile and tile.refresh then
		pcall(tile.refresh, tile)
	end
end
X.refreshAt = refreshAt

local function removeItemAt(entry)
	local row = itemRow(entry.itemKey)
	local tile = row and Tile(Position(entry.x, entry.y, entry.z))
	local removed = false
	-- a stackable look can lie twice on a tile (two creations merge or stack): take every one
	for _ = 1, 4 do
		local item = tile and tile:getItemById(row.id)
		if not item then
			break
		end
		item:remove()
		removed = true
	end
	if removed then
		refreshAt(Position(entry.x, entry.y, entry.z))
	end
	return removed
end

-- ---------------------------------------------------------------- taking
local function sameParty(ownerId, taker)
	local owner = Player(ownerId)
	if not owner then
		return false
	end
	local pa, pb = owner:getParty(), taker:getParty()
	return pa ~= nil and pb ~= nil and pa:getLeader():getId() == pb:getLeader():getId()
end

-- the take of one entry by one player (a step onto the tile, or a pickup that lands under a player's feet)
local function attempt(player, item, entry, position, now)
	local ok, why = K.canTake(entry, player:getId(), sameParty(entry.ownerId, player), now)
	if not ok then
		if why == "expired" then
			K.take(X.reg, entry.uid)
			item:remove()
			refreshAt(position)
		else
			player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, Chaos.t(player, cfg().notYours))
		end
		return false
	end
	K.take(X.reg, entry.uid) -- out of the record first: it can be taken once
	local keep = false
	if entry.onTake then
		local okCb, res = pcall(entry.onTake, player, entry)
		if not okCb then
			print("[Chaos pickups] onTake " .. tostring(entry.itemKey) .. ": " .. tostring(res))
		elseif res == false then
			keep = true
		end
	end
	if keep then
		K.restore(X.reg, entry)
		return false
	end
	local row = itemRow(entry.itemKey)
	sendEffect(position.x, position.y, position.z, row and row.take)
	item:remove()
	refreshAt(position)
	return true
end

-- A pickup that lands on a tile where a player stands: no step event will ever fire for that player (it fires on entering a
-- tile), so the pickup used to lie under the feet until the player left and came back (owner report 2026-10-30: "the buff did
-- not disappear after I picked it up"). The owner, else the first party member who may take it, takes it now.
function X.takeUnderFeet(entry, item, pos)
	local tile = Tile(pos)
	local okC, creatures = pcall(function() return tile and tile:getCreatures() end)
	if not okC or type(creatures) ~= "table" then
		return false
	end
	local who, byId = {}, {}
	for _, c in ipairs(creatures) do
		local p = c.getPlayer and c:getPlayer()
		if p then
			who[#who + 1] = {id = p:getId(), sameParty = sameParty(entry.ownerId, p)}
			byId[p:getId()] = p
		end
	end
	local now = nowMs()
	local id = K.firstTaker(entry, who, now)
	if not id then
		return false
	end
	return attempt(byId[id], item, entry, pos, now)
end

local step = MoveEvent()
step:type("stepin")
function step.onStepIn(creature, item, position, fromPosition)
	local player = creature and creature:getPlayer()
	if not player then
		return true -- a monster or a summon walks over it
	end
	local now = nowMs()
	local entry
	for _, e in ipairs(K.at(X.reg, position.x, position.y, position.z)) do
		local row = itemRow(e.itemKey)
		if row and row.id == item:getId() then
			entry = e
			break
		end
	end
	if not entry then
		item:remove() -- not in the record: left over, grants nothing
		refreshAt(position)
		return true
	end
	attempt(player, item, entry, position, now)
	return true
end
local registered = 0
for _, row in ipairs(cfg().items) do
	if X.installed(row.key) then
		step:id(row.id)
		registered = registered + 1
	end
end
if registered > 0 then
	step:register()
end

-- ---------------------------------------------------------------- the look-out
local think = GlobalEvent("ChaosPickupsThink")
function think.onThink(interval)
	local now = nowMs()
	local ok, err = pcall(function()
		for _, e in ipairs(K.expired(X.reg, now)) do
			if removeItemAt(e) then
				sendEffect(e.x, e.y, e.z, cfg().fadeEffect)
			end
		end
		-- the sweep: an item whose record is gone (taken, ended, a refused removal) and that still lies on its tile
		for _, t in ipairs(K.strays(X.reg, X.tracked)) do
			removeItemAt(t)
		end
		for _, e in ipairs(K.pulses(X.reg, now, cfg().pulseMs)) do
			local row = itemRow(e.itemKey)
			sendEffect(e.x, e.y, e.z, row and row.glow)
		end
	end)
	if not ok then
		print("[Chaos pickups] tick: " .. tostring(err))
	end
	return true
end
think:interval(cfg().tickMs or 500)
think:register()
