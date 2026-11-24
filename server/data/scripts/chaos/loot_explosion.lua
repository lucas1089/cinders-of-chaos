-- Loot explosion, the engine part (O669; server/README.md "Loot explosion (O669)"). The rules are in loot_explosion_core.lua
-- (ChaosLootExplosion, tests/loot_explosion_test.lua), the numbers and the switch in loot_explosion_config.lua.
--
-- A monster still leaves the loot bag (corpse_bag.lua, O435) and every loot step still fills it and takes from it (the loot
-- layer, the auto seller, the pouches, the autoloot, the Rarity Autoloot, the globes). At the end of that chain
-- (EventCallback onDropLoot, index 98) what is left flies out: each item to a free walkable tile within 1-2 tiles of the death
-- tile, gold in one stack, the rarest last, with a distance effect from the death tile. The items carry the custom attribute
-- chaos_loot (owner, owner time, vanish time: X.encode):
--   * ownership: Player:onMoveItem asks ChaosLootExplosion.onMoveItem first (tools/patch_loot_explosion.py writes the call):
--     the killer and the party take their loot, nobody else until the owner time ran out (a unique, a set piece and a quest
--     item never free up). The item leaves the attribute the moment it leaves the ground, so it stacks again.
--   * vanishing: the engine decays no loose item; one sweeper looks at the tiles that hold loot and removes what ran out.
--   * Loot all: opcode 230 `lootall` (groundloot.lua) takes everything of the player's within reach into the backpack.
--   * the client animation (O677): a player whose client draws the burst (game_lootburst: opcode 230 `burst {on = 1}`, X.setAnim) gets one
--     `explode` message with every flight (X.explodePayload) and none of the stock distance effects, landing sparkles and the poff; the
--     other players who see the tile keep those. The flights, delays and landings are the same for both: the real item lands exactly when
--     the client's flight ends.
-- What stays in the bag: the items over the per-kill cap, a kill over the per-area cap, a kill with no free tile, a kill inside
-- an instance, a kill nobody owns, what other scripts add to the bag after the loot step (death events). Players' corpses are
-- never touched. enabled = false in the config and a /reload give the bag back. Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosLootExplosion or not ChaosLootExplosion.plan then
	dofile("data/scripts/chaos/loot_explosion_core.lua")
end
if not ChaosCorpse or not ChaosCorpse.isBag then
	dofile("data/scripts/chaos/corpse_core.lua")
end
Chaos.corpseConfig = Chaos.corpseConfig or dofile("data/scripts/chaos/corpse_config.lua")
Chaos.lootExplosionConfig = dofile("data/scripts/chaos/loot_explosion_config.lua")
local cfg = Chaos.lootExplosionConfig
local corpseCfg = Chaos.corpseConfig
local X = ChaosLootExplosion

local NOERR = RETURNVALUE_NOERROR or 0
local NOTPOSSIBLE = RETURNVALUE_NOTPOSSIBLE or 1
local CONTAINER = CONTAINER_POS or 0xFFFF

local function nowSec()
	return os.time()
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function rng(a, b)
	return math.random(a, b)
end

local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if ok then
		return v
	end
	return nil
end

local function constant(name)
	if type(name) ~= "string" then
		return nil
	end
	return _G["CONST_" .. name]
end

local function say(player, text)
	player:sendCancelMessage(Chaos.tx and Chaos.tx(player, text) or text)
end

-- the engine is not asked about the corpse again once the config is wrong: one line in the log, the bag stays
local problems = X.validate(cfg, corpseCfg)
for _, p in ipairs(problems) do
	print("[Chaos loot explosion] config: " .. p)
end
X.problems = problems
X.gate = X.newGate()
X.seq = X.seq or 0

-- ---------------------------------------------------------------- the sweeper (loose items vanish)
local watched, watchedCount, running = {}, 0, false

local function key(pos)
	return pos.x .. "," .. pos.y .. "," .. pos.z
end

local function sweep()
	local now = nowSec()
	for k, pos in pairs(watched) do
		local tile = Tile(Position(pos.x, pos.y, pos.z))
		local any = false
		if tile then
			for _, item in ipairs(tile:getItems() or {}) do
				local info = X.decode(customAttr(item, X.ATTR))
				if info then
					if X.expired(info, now) then
						item:remove()
					else
						any = true
					end
				end
			end
		end
		if not any then
			watched[k] = nil
			watchedCount = watchedCount - 1
		end
	end
end

local tick
tick = function()
	local ok, err = pcall(sweep)
	if not ok then
		print("[Chaos loot explosion] sweep: " .. tostring(err))
	end
	if watchedCount > 0 then
		addEvent(tick, math.floor(cfg.sweepSeconds * 1000))
	else
		running = false
	end
end

local function watchTile(pos)
	local k = key(pos)
	if not watched[k] then
		watched[k] = {x = pos.x, y = pos.y, z = pos.z}
		watchedCount = watchedCount + 1
	end
	if not running then
		running = true
		addEvent(tick, math.floor(cfg.sweepSeconds * 1000))
	end
end
X.watchTile = watchTile
function X.watched()
	return watchedCount
end

-- ---------------------------------------------------------------- reading an item
local function rankOf(item)
	if customAttr(item, "chaos_unique") ~= nil then
		return 100
	end
	if ChaosRarity and ChaosRarity.rank and ChaosRarity.canon then
		local ok, r = pcall(function() return ChaosRarity.rank(ChaosRarity.canon(customAttr(item, "rarity"))) end)
		if ok and r then
			return r
		end
	end
	return 0
end

local function isSetPiece(item)
	if customAttr(item, "chaos_set") ~= nil then
		return true
	end
	local sets = ChaosItemSets
	if sets and sets.setKeyOf then
		local ok, key = pcall(sets.setKeyOf, item)
		return ok and key ~= nil and key ~= false and key ~= ""
	end
	return false
end

local function dropOf(item)
	local drop = {id = item:getId(), rank = rankOf(item), unique = customAttr(item, "chaos_unique") ~= nil, attrs = {}}
	drop.gold = X.GOLD[drop.id] == true
	drop.set = isSetPiece(item)
	drop.card = ChaosCardsCore ~= nil and ChaosCardsCore.isCard ~= nil and ChaosCardsCore.isCard(drop.id) == true
	for _, name in ipairs(cfg.strictAttributes or {}) do
		if customAttr(item, name) ~= nil then
			drop.attrs[name] = true
		end
	end
	return drop
end

-- O749: true when no auto step may take this item of this corpse (the Loot Bag pouch, the Rarity Autoloot, the base autoloot list,
-- the Auto Seller ask it): the explosion runs (switch on, valid config), the corpse is a loot bag (or none is given) and the item is
-- one of cfg.alwaysExplode (X.mustExplode). O756 (owner 2026-11-24, "Bolsas nas instâncias: sim, volta como antes"): inside an
-- instance nothing explodes (cfg.inInstances false), so the rule does not hold there and every auto step takes as before O749.
function X.mustExplodeItem(item, corpse)
	if not item or not X.active(cfg, corpseCfg) then
		return false
	end
	if corpse then
		local okBag, bag = pcall(function() return ChaosCorpse.isBag(corpseCfg, corpse:getId()) end)
		if not okBag or not bag then
			return false
		end
		if not cfg.inInstances and Chaos.instanceAt then
			local okPos, inside = pcall(function() return Chaos.instanceAt(corpse:getPosition()) end)
			if okPos and inside then
				return false -- O756: in an instance the pouches, the autoloot and the Auto Seller take it as before O749
			end
		end
	end
	local ok, res = pcall(function() return X.mustExplode(cfg, dropOf(item)) end)
	return ok and res == true
end

-- the seconds a loose item still lies (the client's despawn timer, groundloot.lua), nil for anything else
function X.expiryLeft(item)
	local info = X.decode(customAttr(item, X.ATTR))
	return info and X.left(info, nowSec()) or nil
end

-- the loose item's record, nil for an item that is not one
function X.infoOf(item)
	return X.decode(customAttr(item, X.ATTR))
end

-- the item leaves the ground: the attributes go, so it stacks with its like again
function X.release(item)
	pcall(function()
		item:removeCustomAttribute(X.ATTR)
		item:removeCustomAttribute(X.KILL_ATTR)
	end)
end

local function isFriend(player, ownerId)
	if not ownerId or ownerId == 0 then
		return true
	end
	local party = player:getParty()
	if not party then
		return false
	end
	local leader = party:getLeader()
	if leader and leader:getId() == ownerId then
		return true
	end
	for _, member in ipairs(party:getMembers() or {}) do
		if member:getId() == ownerId then
			return true
		end
	end
	return false
end

-- may this player take the item now: ok, why, seconds
function X.mayTake(player, item)
	local info = X.decode(customAttr(item, X.ATTR))
	if not info then
		return true
	end
	if X.expired(info, nowSec()) then
		return false, "gone"
	end
	return X.canTake(info, nowSec(), player:getId(), isFriend(player, info.owner), Chaos.isStaff and Chaos.isStaff(player))
end

-- the labels of other players' loot are not shown (groundloot.lua), as a corpse's contents were not
function X.visibleTo(player, item)
	local info = X.decode(customAttr(item, X.ATTR))
	if not info then
		return true
	end
	return (X.mayTake(player, item))
end

-- ---------------------------------------------------------------- Player:onMoveItem hook
-- The hook takes the record off an item before it is moved into a container. When that move fails, nothing tells the hook; so the
-- record waits in `pending` until the move's onItemMoved clears it, and GUARD_MS later it is put back on the item that still lies on
-- its tile (the same id with no record) and the tile is watched again: the item is neither free nor eternal.
local pending = {}
local GUARD_MS = 200

local function guardMove(pkey)
	local row = pending[pkey]
	if not row then
		return
	end
	pending[pkey] = nil
	local tile = Tile(Position(row.pos.x, row.pos.y, row.pos.z))
	-- the item is found again by its id and its count (a plain stack of the same id may lie on the tile: live run O671, 7 gold of a test took the record of
	-- the 100 gold that stayed); without a match on the count, the first of its id with no record
	local pick
	for _, item in ipairs(tile and tile:getItems() or {}) do
		if item:getId() == row.id and customAttr(item, X.ATTR) == nil then
			if row.count and item:getCount() == row.count then
				pick = item
				break
			end
			pick = pick or item
		end
	end
	if pick then
		pick:setCustomAttribute(X.ATTR, row.raw)
		if row.kill ~= nil then
			pick:setCustomAttribute(X.KILL_ATTR, row.kill)
		end
		watchTile(row.pos)
	end
end
function X.pendingCount()
	local n = 0
	for _ in pairs(pending) do
		n = n + 1
	end
	return n
end

-- called first in Player:onMoveItem (tools/patch_loot_explosion.py); returns a RETURNVALUE
function X.onMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item then
		return NOERR
	end
	local raw = customAttr(item, X.ATTR)
	if raw == nil then
		return NOERR
	end
	local info = X.decode(raw)
	if not info then
		X.release(item)
		return NOERR
	end
	local ok, why, left = X.mayTake(player, item)
	if not ok then
		if why == "wait" then
			say(player, string.format("That loot belongs to someone else for %d more seconds.", math.ceil(left or 0)))
		elseif why == "gone" then
			say(player, "That loot is gone.")
		else
			say(player, "That loot belongs to someone else.")
		end
		return NOTPOSSIBLE
	end
	if toPosition.x == CONTAINER then
		if count >= item:getCount() and fromPosition.x ~= CONTAINER then
			-- before the move, so it stacks with its like in the backpack. If the move then fails (no room, no capacity) the engine
			-- fires no onItemMoved: the record is put back by guardMove below, so a refused item is never left free
			local pkey = key(fromPosition) .. "/" .. item:getId()
			pending[pkey] = {raw = raw, kill = customAttr(item, X.KILL_ATTR), id = item:getId(), count = item:getCount(),
				pos = {x = fromPosition.x, y = fromPosition.y, z = fromPosition.z}}
			X.release(item)
			addEvent(function()
				local ok, err = pcall(guardMove, pkey)
				if not ok then
					print("[Chaos loot explosion] guard: " .. tostring(err))
				end
			end, GUARD_MS)
		end
	else
		watchTile(toPosition) -- moved to another tile: still vanishes on time
	end
	return NOERR
end

-- a part of a stack that was taken (the part got the attributes with its copy): cleaned after the move
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item then
		return
	end
	if toPosition.x == CONTAINER then
		if fromPosition.x ~= CONTAINER then
			local pkey = key(fromPosition) .. "/" .. item:getId()
			local row = pending[pkey]
			pending[pkey] = nil -- the move worked: nothing to put back
			if row and row.kill ~= nil and ChaosLootFilter and ChaosLootFilter.touchKill then
				pcall(ChaosLootFilter.touchKill, tonumber(row.kill)) -- the loot channel's row greys at once
			end
		end
		if customAttr(item, X.ATTR) ~= nil then
			X.release(item)
		end
	end
end
moved:register(60)

-- ---------------------------------------------------------------- the explosion
local BLOCK_FLAGS = {}
for _, name in ipairs({"BLOCKSOLID", "BLOCKPATH", "PROTECTIONZONE", "FLOORCHANGE", "TELEPORT", "MAGICFIELD", "HOUSE", "BED", "DEPOT",
	"MAILBOX", "TRASHHOLDER", "IMMOVABLEBLOCKSOLID"}) do
	local f = _G["TILESTATE_" .. name]
	if f then
		BLOCK_FLAGS[#BLOCK_FLAGS + 1] = f
	end
end
local BAD_GROUND = {"water", "lava", "abyss", "void"}

-- a free tile: a ground, none of the flags above, no house, no water or lava ground
local function tileFree(tile)
	if not tile then
		return false
	end
	local ground = tile:getGround()
	if not ground then
		return false
	end
	for _, f in ipairs(BLOCK_FLAGS) do
		if tile:hasFlag(f) then
			return false
		end
	end
	if tile:getHouse() then
		return false
	end
	local okName, name = pcall(function() return ground:getType():getName():lower() end)
	if okName and name then
		for _, bad in ipairs(BAD_GROUND) do
			if name:find(bad, 1, true) then
				return false
			end
		end
	end
	return true
end

local function factsOf(origin)
	local facts = {}
	for dx = -cfg.radius, cfg.radius do
		for dy = -cfg.radius, cfg.radius do
			local pos = Position(origin.x + dx, origin.y + dy, origin.z)
			local tile = Tile(pos)
			local ring = math.max(math.abs(dx), math.abs(dy))
			if tileFree(tile) and (ring == 0 or origin:isSightClear(pos, true)) then
				facts[#facts + 1] = {dx = dx, dy = dy, ring = ring, items = tile:getItemCount() or 0}
			end
		end
	end
	return facts
end

local function findBags(pos)
	local tile = Tile(Position(pos.x, pos.y, pos.z))
	local out = {}
	if tile then
		for _, item in ipairs(tile:getItems() or {}) do
			if ChaosCorpse.isBag(corpseCfg, item:getId()) and item:isContainer() then
				out[#out + 1] = item
			end
		end
	end
	return out
end

-- the items of one drop still in the bag (found again by their drop number: nothing from before the delay is held)
local function itemsOfDrop(origin, seq)
	local out = {}
	for _, bag in ipairs(findBags(origin)) do
		for slot = 0, bag:getSize() - 1 do
			local item = bag:getItem(slot)
			local info = item and X.decode(customAttr(item, X.ATTR))
			if info and info.seq == seq then
				out[#out + 1] = item
			end
		end
	end
	return out
end

-- ---------------------------------------------------------------- who draws the burst on the client (O677)
-- player id -> true while the client says it draws the animation (opcode 230 `burst {on = 1}`, groundloot.lua); forgotten at logout
X.anim = X.anim or {}

function X.setAnim(player, on)
	X.anim[player:getId()] = on and true or nil
end

function X.clearAnim(player)
	X.anim[player:getId()] = nil
end

-- the owner and the party members who see the death tile and draw the burst: {[player id] = true}
local function animViewers(origin, ownerId)
	if cfg.clientAnim ~= true or next(X.anim) == nil then
		return {}
	end
	local cands, seen = {}, {}
	local function add(p)
		if p and not seen[p:getId()] then
			seen[p:getId()] = true
			local pp = p:getPosition()
			cands[#cands + 1] = {id = p:getId(), x = pp.x, y = pp.y, z = pp.z}
		end
	end
	local owner = Player(ownerId)
	add(owner)
	local party = owner and owner.getParty and owner:getParty()
	if party then
		add(party:getLeader())
		for _, member in ipairs(party:getMembers() or {}) do
			add(member)
		end
	end
	return X.animViewers(cfg, cands, X.anim, origin)
end

-- the stock effects go to the players who see the tile and do not draw the burst themselves (skip = {[player id] = true}); with no
-- skip set the effect goes to everyone as before
local function stockSpectators(pos, skip)
	local out = {}
	local ok, list = pcall(Game.getSpectators, Position(pos.x, pos.y, pos.z), false, true, 9, 9, 7, 7)
	for _, p in ipairs(ok and type(list) == "table" and list or {}) do
		if not skip[p:getId()] then
			out[#out + 1] = p
		end
	end
	return out
end

local function sendMagic(pos, effect, skip)
	if not skip then
		pos:sendMagicEffect(effect)
		return
	end
	for _, p in ipairs(stockSpectators(pos, skip)) do
		pos:sendMagicEffect(effect, p)
	end
end

local function sendDistance(from, to, ani, skip)
	if not skip then
		from:sendDistanceEffect(to, ani)
		return
	end
	for _, p in ipairs(stockSpectators(from, skip)) do
		from:sendDistanceEffect(to, ani, p)
	end
end

local function land(origin, target, seq, group, skip)
	local items = itemsOfDrop(origin, seq)
	if #items == 0 then
		return
	end
	local dest = Position(target.x, target.y, target.z)
	if not tileFree(Tile(dest)) then
		dest = Position(origin.x, origin.y, origin.z)
	end
	local landed = false
	for _, item in ipairs(items) do
		if item:moveTo(dest) or (dest.x ~= origin.x or dest.y ~= origin.y) and item:moveTo(Position(origin.x, origin.y, origin.z)) then
			landed = true
		else
			X.release(item) -- it stays in the bag as it was
		end
	end
	if landed then
		watchTile(dest)
		local effect = constant(cfg.land[group])
		if effect then
			sendMagic(dest, effect, skip)
		end
	end
end

local function launch(origin, target, seq, group, flight, skip)
	local from = Position(origin.x, origin.y, origin.z)
	local to = Position(target.x, target.y, target.z)
	local ani = constant(cfg.missiles[group])
	if ani then
		sendDistance(from, to, ani, skip)
	end
	addEvent(function()
		local ok, err = pcall(land, origin, target, seq, group, skip)
		if not ok then
			print("[Chaos loot explosion] landing: " .. tostring(err))
		end
	end, flight)
end

local function explode(monster, corpse)
	if not X.active(cfg, corpseCfg) or not corpse or not ChaosCorpse.isBag(corpseCfg, corpse:getId()) or not corpse.isContainer
		or not corpse:isContainer() or corpse:getSize() == 0 then
		return
	end
	local ownerId = corpse:getCorpseOwner()
	if ownerId == 0 or not Player(ownerId) then
		return -- nobody owns the kill: the bag as before
	end
	local origin = corpse:getPosition()
	if not origin or origin.x == 0 then
		return
	end
	if not cfg.inInstances and Chaos.instanceAt and Chaos.instanceAt(origin) then
		return
	end
	local items, byKey = {}, {}
	for slot = 0, corpse:getSize() - 1 do
		local item = corpse:getItem(slot)
		if item then
			local drop = dropOf(item)
			items[#items + 1] = {key = slot, rank = X.flyRank(cfg, drop), gold = drop.gold}
			byKey[slot] = {item = item, drop = drop}
		end
	end
	if #items == 0 then
		return
	end
	local facts = factsOf(origin)
	local plan = X.plan(cfg, items, facts, rng)
	if #plan.drops == 0 then
		return
	end
	local flying = 0
	for _, d in ipairs(plan.drops) do
		flying = flying + #d.keys
	end
	if not X.gateTake(cfg, X.gate, X.areaKey(cfg, origin), flying, nowMs()) then
		return -- a pull over the cap of this place: the bag, as before
	end
	local now = nowSec()
	local life = X.decaySeconds(cfg, corpseCfg)
	local ownFor = X.ownerSeconds(cfg, corpseCfg)
	local killId = ChaosLootFilter and ChaosLootFilter.killOf and ChaosLootFilter.killOf(corpse) or nil
	local inherit = {}
	for _, name in ipairs(cfg.inheritAttributes or {}) do
		local v = customAttr(corpse, name)
		if v ~= nil then
			inherit[name] = v
		end
	end
	local tiles = {}
	local schedule = {}
	local flights = {}
	for _, d in ipairs(plan.drops) do
		X.seq = X.seq + 1
		local seq = X.seq
		local f = facts[d.tile]
		local strict = false
		for _, k in ipairs(d.keys) do
			strict = strict or X.isStrict(cfg, byKey[k].drop)
		end
		local group = d.gold and "gold" or X.groupOf(cfg, byKey[d.keys[1]].drop)
		for _, k in ipairs(d.keys) do
			local item = byKey[k].item
			item:setCustomAttribute(X.ATTR, X.encode({owner = ownerId, ownUntil = now + ownFor, expiry = now + life, strict = strict, seq = seq}))
			if killId then
				item:setCustomAttribute(X.KILL_ATTR, killId)
			end
			for name, v in pairs(inherit) do
				item:setCustomAttribute(name, v)
			end
		end
		local target = {x = origin.x + f.dx, y = origin.y + f.dy, z = origin.z}
		tiles[#tiles + 1] = target
		schedule[#schedule + 1] = {delay = d.delay, flight = d.flight, target = target, seq = seq, group = group}
		-- what the client draws: the item (the highest coin of a gold drop), its count, the beam group of the best item of the drop
		local lead, beam = byKey[d.keys[1]].item, nil
		for _, k in ipairs(d.keys) do
			local it = byKey[k].item
			if d.gold and it:getId() > lead:getId() then
				lead = it
			end
			beam = beam or X.beamGroup(cfg, byKey[k].drop)
		end
		local itype = ItemType(lead:getId())
		flights[#flights + 1] = {id = itype and itype:getClientId() or lead:getId(), c = lead:getCount(), to = target, d = d.delay,
			fl = d.flight, g = beam}
	end
	corpse:setCustomAttribute("chaos_exploded", 1)
	if ChaosLootFilter and ChaosLootFilter.onExploded and killId then
		pcall(ChaosLootFilter.onExploded, killId, {x = origin.x, y = origin.y, z = origin.z}, tiles)
	end
	local o = {x = origin.x, y = origin.y, z = origin.z}
	-- the players whose client draws the burst get the one message and no stock effect; with none, the effects go to everyone as before
	local skip = animViewers(o, ownerId)
	if next(skip) == nil then
		skip = nil
	else
		local payload = X.explodePayload(cfg, o, killId, flights)
		for id in pairs(skip) do
			local p = Player(id)
			if payload and p then
				local sent, serr = pcall(Chaos.send, p, (ChaosOpcodes and ChaosOpcodes.groundLoot) or 230, "explode", payload)
				if not sent then
					print("[Chaos loot explosion] explode message: " .. tostring(serr))
				end
			end
		end
	end
	local burst = constant(cfg.burst)
	if burst then
		sendMagic(origin, burst, skip)
	end
	for _, s in ipairs(schedule) do
		if s.delay <= 0 then
			launch(o, s.target, s.seq, s.group, s.flight, skip)
		else
			addEvent(function()
				local ok, err = pcall(launch, o, s.target, s.seq, s.group, s.flight, skip)
				if not ok then
					print("[Chaos loot explosion] launch: " .. tostring(err))
				end
			end, s.delay)
		end
	end
end
X.explode = explode

-- true for a bag whose loot flew out (mainquest.lua giveQuestItem: its quest item then goes to the backpack)
function X.isExploded(corpse)
	return corpse ~= nil and customAttr(corpse, "chaos_exploded") ~= nil
end

local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	local ok, err = pcall(explode, self, corpse)
	if not ok then
		print("[Chaos loot explosion] onDropLoot failed: " .. tostring(err))
	end
end
drop:register(cfg.index)

-- ---------------------------------------------------------------- Loot all
-- every item of the player's within reach goes into the backpack (a carried pouch that collects it first). A part that does not
-- fit stays where it lies, with its attributes. Returns the number taken, the number that did not fit, the number seen.
function X.lootAll(player)
	local me = player:getPosition()
	local F = ChaosLootFilter
	local intoBags = F and F.intoBags
	if not intoBags then
		return 0, 0, 0
	end
	local found = {}
	for dx = -cfg.reachX, cfg.reachX do
		for dy = -cfg.reachY, cfg.reachY do
			local pos = Position(me.x + dx, me.y + dy, me.z)
			local tile = Tile(pos)
			if tile and not tile:getHouse() then
				local near = math.abs(dx) <= 1 and math.abs(dy) <= 1
				local seen = nil
				for _, item in ipairs(tile:getItems() or {}) do
					if X.infoOf(item) and X.mayTake(player, item) then
						if seen == nil then
							local okSight, sight = pcall(function() return me:isSightClear(pos, true) end)
							seen = near or (okSight and sight == true)
						end
						if seen then
							found[#found + 1] = {item = item, d = math.max(math.abs(dx), math.abs(dy))}
						end
					end
				end
			end
		end
	end
	table.sort(found, function(a, b) return a.d < b.d end)
	local took, failed, kills = 0, 0, {}
	for i, row in ipairs(found) do
		if i > cfg.lootAllMax then
			break
		end
		local item = row.item
		local raw, kill = customAttr(item, X.ATTR), customAttr(item, X.KILL_ATTR)
		X.release(item) -- before the move: it stacks with its like in the backpack
		local ok = (ChaosPouches and ChaosPouches.stow and ChaosPouches.stow(player, item)) or intoBags(player, item)
		if ok then
			took = took + 1
			if kill then
				kills[tonumber(kill)] = true
			end
		else
			failed = failed + 1
			item:setCustomAttribute(X.ATTR, raw)
			if kill then
				item:setCustomAttribute(X.KILL_ATTR, kill)
			end
		end
	end
	if F.touchKill then
		for id in pairs(kills) do
			pcall(F.touchKill, id)
		end
	end
	return took, failed, #found
end

-- ---------------------------------------------------------------- tester bots (TEST ONLY, tools/tester_helper.lua `!tester explode`)
-- testerRun(player): a loot bag of the player's own on its tile with known loot (150 gold in two stacks, three potions, a Magic
-- and a Legendary sword), exploded at once by the real rule. testerProbe(player): what lies within 4 tiles of the player, read
-- off the items (the owner, the ring, the tiles, the bag), and whether a stranger would be refused. The bot then asks Loot all
-- (opcode 230) and probes again. Both are only reached by the helper, which answers for "Tester" characters only.
local TEST_ITEMS = {{2148, 100}, {2148, 50}, {7618, 3}, {7620, 2}, {2376, 1, 5}, {2376, 1, 10}} -- a Legendary and a Divine sword (O677: the burst shows both)

X.testerOrigins = X.testerOrigins or {}

-- TEST ONLY: the nearest free tile (within 20) with at least 12 free tiles in its 5 x 5 square and no creature on it, outside a protection zone: where a bot that
-- stands in the temple can drop its test loot (the rule keeps loot out of a protection zone; a bot in its hunt walks into fights and picks the loot up)
local function openSpot(from)
	local best, bestD
	for dx = -20, 20 do
		for dy = -20, 20 do
			local pos = Position(from.x + dx, from.y + dy, from.z)
			local tile = Tile(pos)
			local d = math.max(math.abs(dx), math.abs(dy))
			if (not bestD or d < bestD) and tileFree(tile) and tile:getCreatureCount() == 0 and from:isSightClear(pos, true) then
				local free = 0
				for ex = -2, 2 do
					for ey = -2, 2 do
						if tileFree(Tile(Position(pos.x + ex, pos.y + ey, pos.z))) then
							free = free + 1
						end
					end
				end
				if free >= 12 then
					best, bestD = pos, d
				end
			end
		end
	end
	return best
end

-- mode "set" (O678): a set piece lies among the loot (the `chaos_set` attribute), so the ground rows of groundloot.lua show it with `st`; mode "bag": the same
-- loot (a Legendary sword and a set piece) stays in the bag on the tile, not exploded: the corpse row of groundloot.lua lists it with `st`
function X.testerRun(player, mode)
	if not X.active(cfg, corpseCfg) then
		return nil, "the loot explosion is off"
	end
	local pos = player:getPosition()
	local tile = Tile(pos)
	local moved
	if tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) and Chaos.isTester and Chaos.isTester(player) then
		local spot = openSpot(pos)
		if spot then
			player:teleportTo(spot)
			pos = player:getPosition()
			tile = Tile(pos)
			moved = true
			print(string.format("[Chaos loot explosion] TEST ONLY: tester %s stepped out of a protection zone to %d,%d,%d", player:getName(), pos.x, pos.y, pos.z))
		end
	end
	local bag = tile and Game.createItem(corpseCfg.bagId, 1)
	if not bag then
		return nil, "no bag"
	end
	if tile:addItemEx(bag) ~= (RETURNVALUE_NOERROR or 0) then
		return nil, "no room for the bag"
	end
	if ITEM_ATTRIBUTE_CORPSEOWNER then
		bag:setAttribute(ITEM_ATTRIBUTE_CORPSEOWNER, player:getId())
	end
	for _, row in ipairs(TEST_ITEMS) do
		local item = bag:addItem(row[1], row[2])
		if item and row[3] then
			item:setCustomAttribute("rarity", row[3])
		end
	end
	if mode == "set" or mode == "bag" then
		local piece = bag:addItem(2376, 1)
		if piece then
			piece:setCustomAttribute("rarity", 4)
			piece:setCustomAttribute("chaos_set", "tester_set")
		end
	end
	if mode == "bag" then
		-- an extra Legendary sword beside the set piece; the bag stays as a corpse the owner may read
		local legendary = bag:addItem(2376, 1)
		if legendary then
			legendary:setCustomAttribute("rarity", 5)
		end
		return {items = bag:getSize(), bag = true, x = pos.x, y = pos.y, z = pos.z, moved = moved}
	end
	local before = bag:getSize()
	local seq0 = X.seq
	explode(nil, bag)
	-- the death tile and the drop numbers (one per tile): the probe measures the rings from the tile and reads only this run's loot, whatever the bot did since (O671)
	X.testerOrigins[player:getId()] = {x = pos.x, y = pos.y, z = pos.z, seqFrom = seq0 + 1, seqTo = X.seq}
	if not X.isExploded(bag) then
		bag:remove()
		return nil, "not exploded (a cap, an instance, a tile with nothing free or the owner is not the bot)"
	end
	return {items = before, expected = #TEST_ITEMS, moved = moved, x = pos.x, y = pos.y, z = pos.z}
end

-- TEST ONLY (`!tester explode join NAME`, O671): this tester stands on a free tile beside the tester NAME, the stranger of the loot test that drags
-- the owner's loot with its own hands. Testers only, both online on one floor; a player is never moved. -> {x, y, z, of} or nil + why
function X.testerJoin(player, name)
	if not (Chaos.isTester and Chaos.isTester(player)) then
		return nil, "not a tester"
	end
	local other = name and Player(name)
	if not other or other:getId() == player:getId() or not (Chaos.isTester and Chaos.isTester(other)) then
		return nil, "no such tester online"
	end
	local at = other:getPosition()
	for r = 1, 2 do
		for dx = -r, r do
			for dy = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local pos = Position(at.x + dx, at.y + dy, at.z)
					local tile = Tile(pos)
					if tileFree(tile) and tile:getCreatureCount() == 0 and at:isSightClear(pos, true) then
						player:teleportTo(pos)
						print(string.format("[Chaos loot explosion] TEST ONLY: tester %s joined tester %s", player:getName(), other:getName()))
						return {x = pos.x, y = pos.y, z = pos.z, of = other:getId()}
					end
				end
			end
		end
	end
	return nil, "no free tile beside " .. name
end

function X.testerProbe(player)
	local here = player:getPosition()
	local me = here
	local home = X.testerOrigins[player:getId()]
	-- a bot walks on while the loot flies and lies (a hunting bot took a step in the first live run: ring 3 of its new tile): the rings are read from the death
	-- tile of its last `explode run` while it stands within 4 tiles of it
	local seqFrom, seqTo -- the drop numbers of that run: with them only the loot of that explosion is the asker's to read (ten bots share a temple and a hunt spot)
	if home and home.z == here.z and math.max(math.abs(home.x - here.x), math.abs(home.y - here.y)) <= 4 then
		me = Position(home.x, home.y, home.z)
		seqFrom, seqTo = home.seqFrom, home.seqTo
	end
	local out = {loose = 0, mine = 0, tiles = 0, maxRing = 0, strict = 0, foreign = 0, bagItems = 0, watched = X.watched(), expiry = nil, list = {},
		at = {x = here.x, y = here.y, z = here.z}}
	local seen = {}
	for dx = -4, 4 do
		for dy = -4, 4 do
			local tile = Tile(Position(me.x + dx, me.y + dy, me.z))
			for _, item in ipairs(tile and tile:getItems() or {}) do
				if ChaosCorpse.isBag(corpseCfg, item:getId()) and item:isContainer() and (not seqFrom or item:getCorpseOwner() == player:getId()) then
					out.bagItems = out.bagItems + item:getSize() -- with a run on record only the asker's own bags (a neighbour's bag is not its fault)
				end
				local info = X.infoOf(item)
				if info and seqFrom and (info.owner ~= player:getId() or info.seq < seqFrom or info.seq > seqTo) then
					info = nil -- the loot of another run (an older one of this bot, or another bot's beside it) is not read
				end
				if info then
					out.loose = out.loose + 1
					if info.owner == player:getId() then
						out.mine = out.mine + 1
					else
						out.foreign = out.foreign + 1
					end
					out.strict = out.strict + (info.strict and 1 or 0)
					-- the loose items by place, what a drag names (O671): the tile, the item, its place in the tile's stack. A drag takes the top item
					-- of a tile (the engine's STACKPOS_MOVE), so only the top one of each tile is listed
					local top = tile.getTopDownItem and tile:getTopDownItem() or item
					if #out.list < 8 and top == item then
						local itp = ItemType(item:getId())
						out.list[#out.list + 1] = {x = me.x + dx, y = me.y + dy, z = me.z, id = item:getId(), cid = itp and itp:getClientId() or 0,
							sp = tile.getThingIndex and tile:getThingIndex(item) or 1, n = item:getCount(), mine = info.owner == player:getId() or nil}
					end
					local k = (me.x + dx) .. "," .. (me.y + dy)
					if not seen[k] then
						seen[k] = true
						out.tiles = out.tiles + 1
					end
					out.maxRing = math.max(out.maxRing, math.max(math.abs(dx), math.abs(dy)))
					local left = X.left(info, nowSec())
					out.expiry = out.expiry and math.min(out.expiry, left or 0) or left
				end
			end
		end
	end
	-- a stranger (an id that is nobody's) before the owner time ran out: refused; the owner and a party member: allowed
	local probe = {owner = player:getId(), ownUntil = nowSec() + 60, expiry = nowSec() + 120, strict = false, seq = 0}
	out.strangerRefused = X.canTake(probe, nowSec(), player:getId() + 1000000, false, false) == false
	out.ownerAllowed = X.canTake(probe, nowSec(), player:getId(), false, false) == true
	return out
end
