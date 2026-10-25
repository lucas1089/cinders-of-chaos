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
--   the look-out     GlobalEvent every tickMs: runs out -> the item is removed with a fade effect; the glow pulses.
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
	sendEffect(pos.x, pos.y, pos.z, row.glow)
	return entry
end

local function removeItemAt(entry)
	local row = itemRow(entry.itemKey)
	local tile = row and Tile(Position(entry.x, entry.y, entry.z))
	local item = tile and tile:getItemById(row.id)
	if item then
		item:remove()
		return true
	end
	return false
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
		return true
	end
	local ok, why = K.canTake(entry, player:getId(), sameParty(entry.ownerId, player), now)
	if not ok then
		if why == "expired" then
			K.take(X.reg, entry.uid)
			item:remove()
		else
			player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_INFO_DESCR, Chaos.t(player, cfg().notYours))
		end
		return true
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
		return true
	end
	local row = itemRow(entry.itemKey)
	sendEffect(position.x, position.y, position.z, row and row.take)
	item:remove()
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
