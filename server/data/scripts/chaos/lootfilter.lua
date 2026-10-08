-- Loot filter, loot channel and loot rays (client game_lootfilter, extended opcode ChaosOpcodes.lootfilter, !lootfilter).
-- Rules and packing: lootfilter_core.lua (tested by server/tests/lootfilter_test.lua). Tunables: lootfilter_config.lua.
--
-- client -> server  {"action":"open"}                         settings + open the window
--                   {"action":"sync"}                         settings only (the client asks when the game starts)
--                   {"action":"set","data":{settings}}         save (sanitized) settings
--                   {"action":"preset","data":{"name":"hunter"}}
--                   {"action":"peek","data":{"cid":N}}         rarity data of an open container (client container id)
--                   {"action":"take","data":{"k":kill,"n":entry,"id":clientId,"one":bool}}   click to loot
-- server -> client  settings {s, unlocked, presets, samples, open}
--                   peek {cid, corpse, items = [{i (0-based index), id (client id), r, u, o, g}]}
--                   kill {k, m (monster), p (corpse position), items = [{n, id, c, r, u, o, g, nm, left}], drops = [{text, color, rank}]}
--                   update {k, left = [remaining count per entry]}      decay {k}      msg {text} (a refused click)
--
-- onDropLoot (lower index first): 0 stock loot, 1 Chaos loot layer, 2 auto seller, 2.5 SNAPSHOT + hold back list items
-- below the Rarity Autoloot minimum, 3 base autoloot, 3.5 RARITY PICKUP, 4 loot pouch, 4.5 FINISH (held items back into
-- the corpse, loot row, rare-drop lines, rays). Every step runs in pcall and returns nothing, so the chain never stops.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/lootfilter_core.lua")
dofile("data/scripts/chaos/lootfilter_config.lua")
if not ChaosFx then
	pcall(dofile, "data/lib/chaos_fx.lua") -- effect ids of the loot rays (generated, see README_FX.md)
end

local F = ChaosLootFilter
local OPCODE = ChaosOpcodes.lootfilter
local ST = Chaos.storage
local HOLD_BAG = 1987 -- bag; holds the items kept back from the base autoloot for the length of one onDropLoot chain

local function cfg()
	return ChaosLootFilterConfig
end

-- state survives /reload scripts
ChaosLootFilterState = ChaosLootFilterState or {kills = {}, byGuid = {}, nextId = 1, tick = 0, event = nil}
local state = ChaosLootFilterState

-- ---------------------------------------------------------------- settings
local function settingsOf(player)
	return F.unpack(player:getStorageValue(ST.lootFilter))
end

local function unlocked(player)
	return player:getStorageValue(ST.shopRarityAutoloot) > 0
end

local function sendSettings(player, open)
	local presets = {}
	for _, p in ipairs(F.PRESETS) do
		presets[#presets + 1] = {key = p.key, name = p.name, desc = p.desc}
	end
	-- example items for the preview row of the window (client ids)
	local function cid(id)
		local it = ItemType(id)
		return it and it:getId() ~= 0 and it:getClientId() or 0
	end
	local samples = {gear = cid(2392), unique = cid(ChaosUniqueItems and ChaosUniqueItems[1] and ChaosUniqueItems[1].id or 2400),
		orb = cid(29856), coin = cid(2152), supply = cid(7618), other = cid(2229)}
	Chaos.send(player, OPCODE, "settings", {s = settingsOf(player), unlocked = unlocked(player), presets = presets,
		samples = samples, open = open and true or false})
end

local function saveSettings(player, s)
	player:setStorageValue(ST.lootFilter, F.pack(s))
end

-- ---------------------------------------------------------------- item info
local function customAttr(item, key)
	local ok, v = pcall(function() return item:getCustomAttribute(key) end)
	if ok then
		return v
	end
	return nil
end

local orbSet, coinSet
local function sets()
	if not orbSet then
		orbSet, coinSet = {}, {}
		for _, id in ipairs(cfg().orbIds or {}) do
			orbSet[id] = true
		end
		local lc = ChaosLootConfig
		for _, e in ipairs(lc and lc.currency and lc.currency.entries or {}) do
			if e.id then
				orbSet[e.id] = true
			end
		end
		for _, id in ipairs(cfg().coinIds or {}) do
			coinSet[id] = true
		end
	end
	return orbSet, coinSet
end

local function hasBit(value, b)
	return math.floor((value or 0) / b) % 2 == 1
end

local GEAR_SLOTS = {1, 2, 8, 64, 128, 256} -- SLOTP_HEAD, NECKLACE, ARMOR, LEGS, FEET, RING

local function categoryOf(itemType, info)
	local orbs, coins = sets()
	if orbs[info.id] or coins[info.id] or info.orb then
		return "currency"
	end
	if info.unique or info.rarity > 0 then
		return "equipment"
	end
	if itemType:isRune() or itemType:getAmmoType() ~= 0 or itemType:isFluidContainer() then
		return "supplies"
	end
	local weapon = itemType:getWeaponType()
	if (weapon ~= 0 and weapon ~= WEAPON_AMMO) or itemType:getArmor() > 0 then
		return "equipment"
	end
	local slots = itemType:getSlotPosition()
	for _, b in ipairs(GEAR_SLOTS) do
		if hasBit(slots, b) then
			return "equipment"
		end
	end
	local lname = (info.name or ""):lower()
	for _, w in ipairs(cfg().supplyWords or {}) do
		if lname:find("%f[%a]" .. w .. "s?%f[%A]") then
			return "supplies"
		end
	end
	return "other"
end

local function itemInfo(item)
	local itemType = item:getType()
	local id = item:getId()
	local info = {
		id = id,
		clientId = itemType:getClientId(),
		count = item:getCount(),
		name = item:getName(),
		rarity = tonumber(customAttr(item, "rarity")) or 0,
		unique = customAttr(item, "chaos_unique") ~= nil
	}
	if info.rarity < 0 or info.rarity > F.MAX_RARITY then
		info.rarity = 0
	end
	local orbs = sets()
	local lname = (info.name or ""):lower()
	info.orb = orbs[id] or (not info.unique and info.rarity == 0 and itemType:isStackable()
		and (lname:find("%f[%a]orb$") or lname:find("^orb of ")) and true) or false
	info.category = categoryOf(itemType, info)
	return info
end
ChaosLootFilter.itemInfo = itemInfo

local function wire(info, extra)
	local t = {id = info.clientId, c = info.count, r = info.rarity, u = info.unique and 1 or 0, o = info.orb and 1 or 0,
		g = info.category}
	for k, v in pairs(extra or {}) do
		t[k] = v
	end
	return t
end

-- ---------------------------------------------------------------- corpse helpers
local function autolootSet(player)
	local limit = player:isPremium() and Chaos.autoloot.premiumLimit or Chaos.autoloot.freeLimit
	local set = {}
	for i = 1, limit do
		local id = player:getStorageValue(ST.autolootBase + i)
		if id and id > 0 then
			set[id] = true
		end
	end
	return set
end

-- into the backpack (and the bags inside it, breadth first) with capacity checks. Never into an equipment slot:
-- the engine's own "anywhere" would put a looted armor on an empty armor slot and equip its stats.
local function intoBags(player, item)
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if bp and bp:isContainer() then
		local queue, i = {bp}, 1
		while i <= #queue and i <= 30 do
			local c = queue[i]
			i = i + 1
			if item:moveTo(c, 0) then
				return true
			end
			for _, sub in ipairs(c:getItems()) do
				if sub:isContainer() then
					queue[#queue + 1] = sub
				end
			end
		end
	end
	return false
end

local function canLoot(player, corpse)
	local owner = corpse:getCorpseOwner()
	if owner == 0 or owner == player:getId() then
		return true
	end
	local party = player:getParty()
	if not party then
		return false
	end
	local leader = party:getLeader()
	if leader and leader:getId() == owner then
		return true
	end
	for _, member in ipairs(party:getMembers() or {}) do
		if member:getId() == owner then
			return true
		end
	end
	return false
end

local function findCorpse(kill)
	local tile = Tile(kill.pos)
	if not tile then
		return nil
	end
	for _, item in ipairs(tile:getItems() or {}) do
		if item:isContainer() and tonumber(customAttr(item, cfg().corpseAttribute)) == kill.id then
			return item
		end
	end
	return nil
end

local function presentOf(corpse)
	local present = {}
	for _, item in ipairs(corpse:getItems()) do
		local sig = F.signature(itemInfo(item))
		present[sig] = (present[sig] or 0) + item:getCount()
	end
	return present
end

local function sameList(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

local function stopTracking(kill)
	state.kills[kill.id] = nil
	local list = state.byGuid[kill.guid]
	if list then
		for i, id in ipairs(list) do
			if id == kill.id then
				table.remove(list, i)
				break
			end
		end
	end
end

-- Re-reads the corpse; sends "update" when something left it and "decay" when the corpse is gone.
local function refresh(kill)
	local player = Player(kill.ownerId)
	local corpse = findCorpse(kill)
	if not corpse then
		stopTracking(kill)
		if player then
			Chaos.send(player, OPCODE, "decay", {k = kill.id})
		end
		return nil
	end
	local left = F.reconcile(kill.entries, presentOf(corpse))
	if not sameList(left, kill.left) then
		kill.left = left
		if player then
			Chaos.send(player, OPCODE, "update", {k = kill.id, left = left})
		end
	end
	local any = false
	for _, n in ipairs(left) do
		if n > 0 then
			any = true
			break
		end
	end
	if not any then
		stopTracking(kill) -- nothing left to grey later
	end
	return corpse
end

-- ---------------------------------------------------------------- rays + decay timer
local function rayViewers(kill, owner)
	local list = {owner}
	if cfg().rayVisibleTo == "all" then
		return nil
	end
	local party = owner:getParty()
	if party then
		local seen = {[owner:getId()] = true}
		local leader = party:getLeader()
		for _, p in ipairs({leader}) do
			if p and not seen[p:getId()] then
				seen[p:getId()] = true
				list[#list + 1] = p
			end
		end
		for _, p in ipairs(party:getMembers() or {}) do
			if not seen[p:getId()] then
				seen[p:getId()] = true
				list[#list + 1] = p
			end
		end
	end
	return list
end

local function emitRay(kill, owner)
	local effect, best = nil, -1 -- one beam per corpse: a unique wins, else the highest rarity still inside
	for i, e in ipairs(kill.entries) do
		if e.ray and (kill.left[i] or 0) > 0 then
			local rank = e.info.unique and 100 or e.info.rarity
			if rank > best then
				effect, best = e.ray, rank
			end
		end
	end
	if not effect then
		kill.rayUntil = nil
		return
	end
	local id = ChaosFx and ChaosFx[effect]
	if not id then
		return
	end
	local pos = Position(kill.pos.x, kill.pos.y, kill.pos.z)
	local viewers = rayViewers(kill, owner)
	if not viewers then
		pos:sendMagicEffect(id)
		return
	end
	for _, p in ipairs(viewers) do
		local pp = p:getPosition()
		if pp.z == pos.z and math.abs(pp.x - pos.x) <= 9 and math.abs(pp.y - pos.y) <= 7 then
			pos:sendMagicEffect(id, p)
		end
	end
end

local sweep
local function ensureTimer()
	if not state.event then
		state.event = addEvent(sweep, cfg().sweepMs)
	end
end

sweep = function()
	state.event = nil
	state.tick = state.tick + 1
	local now = os.time()
	local decayTick = state.tick % math.max(1, cfg().decayCheckEvery) == 0
	local ids = {}
	for id in pairs(state.kills) do
		ids[#ids + 1] = id
	end
	for _, id in ipairs(ids) do
		local kill = state.kills[id]
		if kill then
			local owner = Player(kill.ownerId)
			if not owner then
				stopTracking(kill)
			else
				local rays = kill.rayUntil and now <= kill.rayUntil
				if rays or decayTick then
					local ok, err = pcall(refresh, kill)
					if not ok then
						print("[Chaos lootfilter] refresh failed: " .. tostring(err))
						stopTracking(kill)
					elseif rays and state.kills[id] then
						emitRay(kill, owner)
					end
				end
			end
		end
	end
	if next(state.kills) then
		ensureTimer()
	end
end

-- ---------------------------------------------------------------- onDropLoot steps
local current -- the drop in progress (one onDropLoot chain; all steps run in the same dispatcher task)

local function snapshot(monster, corpse)
	current = nil
	if not corpse:getType():isContainer() then
		return
	end
	local owner = Player(corpse:getCorpseOwner())
	if not owner then
		return
	end
	local s, unlock = settingsOf(owner), unlocked(owner)
	local list = unlock and s.lootMin > 0 and autolootSet(owner) or {}
	local entries, keep = {}, {}
	for _, item in ipairs(corpse:getItems()) do
		local info = itemInfo(item)
		entries[#entries + 1] = info
		if F.autoloot(info, s, list[info.id], unlock) == "keep" then
			keep[#keep + 1] = item
		end
	end
	local pos = corpse:getPosition()
	current = {ownerId = owner:getId(), pos = {x = pos.x, y = pos.y, z = pos.z}, corpseId = corpse:getId(),
		monster = monster:getName(), entries = entries, s = s, unlock = unlock}
	if #keep > 0 then
		-- the bag lies on the corpse tile for the rest of this chain only; if a later callback raised an error the
		-- items would stay in that bag on the ground instead of vanishing
		local bag = Game.createItem(HOLD_BAG, 1, pos)
		if bag then
			for _, item in ipairs(keep) do
				item:moveTo(bag)
			end
			current.bag = bag
		end
	end
end

local function pickup(monster, corpse)
	if not current or not current.unlock or current.s.lootFrom <= 0 then
		return
	end
	local owner = Player(current.ownerId)
	if not owner then
		return
	end
	local list = autolootSet(owner)
	local taken, stashed, failed = {}, 0, 0
	for _, item in ipairs(corpse:getItems()) do
		local info = itemInfo(item)
		if F.autoloot(info, current.s, list[info.id], true) == "take" then
			local label = F.label(info)
			if intoBags(owner, item) then
				taken[#taken + 1] = label
			elseif owner:getStorageValue(ST.shopLootPouch) > 0 and ((ChaosStash and ChaosStash.storeItem(owner, item))
				or (owner:getInbox() and item:moveTo(owner:getInbox()))) then
				stashed = stashed + 1
				taken[#taken + 1] = label
			else
				failed = failed + 1
			end
		end
	end
	if #taken > 0 then
		owner:sendTextMessage(MESSAGE_INFO_DESCR, "Rarity autoloot: " .. table.concat(taken, ", ")
			.. (stashed > 0 and string.format(" (%d to your stash or inbox)", stashed) or "") .. ".")
	end
	if failed > 0 then
		owner:sendTextMessage(MESSAGE_INFO_DESCR, "Rarity autoloot: no room or capacity, left in the corpse.")
	end
end

local function finish(monster, corpse)
	local drop = current
	current = nil
	if not drop then
		return
	end
	if drop.bag then
		for _, item in ipairs(drop.bag:getItems()) do
			item:moveTo(corpse)
		end
		drop.bag:remove()
	end
	local owner = Player(drop.ownerId)
	if not owner or #drop.entries == 0 then
		return
	end
	local c = cfg()
	local id = state.nextId
	state.nextId = id + 1
	corpse:setCustomAttribute(c.corpseAttribute, id)

	local kill = {id = id, guid = owner:getGuid(), ownerId = drop.ownerId, pos = drop.pos, entries = {}, left = {}}
	local rows, drops = {}, {}
	local hasRay = false
	for i, info in ipairs(drop.entries) do
		local ray = F.rayEffect(info, c)
		hasRay = hasRay or ray ~= nil
		kill.entries[i] = {sig = F.signature(info), count = info.count, info = info, ray = ray}
		local line = F.dropLine(info, drop.s)
		if line then
			drops[#drops + 1] = {text = line, color = F.color(info) or "#ffffff", rank = info.unique and 100 or info.rarity}
		end
	end
	kill.left = F.reconcile(kill.entries, presentOf(corpse))
	for i, e in ipairs(kill.entries) do
		rows[i] = wire(e.info, {n = i, nm = e.info.name, left = kill.left[i]})
	end

	state.kills[id] = kill
	local list = state.byGuid[kill.guid] or {}
	state.byGuid[kill.guid] = list
	list[#list + 1] = id
	while #list > c.historySize do
		local old = state.kills[table.remove(list, 1)]
		if old then
			state.kills[old.id] = nil
		end
	end
	if hasRay then
		kill.rayUntil = os.time() + c.rayDurationS
		emitRay(kill, owner)
	end
	Chaos.send(owner, OPCODE, "kill", {k = id, m = drop.monster, p = drop.pos, items = rows, drops = drops})
	ensureTimer()
end

local function step(name, fn, index)
	local cb = EventCallback
	cb.onDropLoot = function(self, corpse)
		local ok, err = pcall(fn, self, corpse)
		if not ok then
			print("[Chaos lootfilter] " .. name .. " failed: " .. tostring(err))
		end
	end
	cb:register(index)
end
step("snapshot", snapshot, cfg().snapshotIndex)
step("pickup", pickup, cfg().pickupIndex)
step("finish", finish, cfg().finishIndex)

-- items taken out of (or put into) a tracked corpse by hand, by another script or by another party member
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	for _, cyl in ipairs({fromCylinder, toCylinder}) do
		if cyl and cyl.isContainer and cyl:isContainer() then
			local id = tonumber(customAttr(cyl, cfg().corpseAttribute))
			local kill = id and state.kills[id]
			if kill then
				pcall(refresh, kill)
			end
		end
	end
end
moved:register(11)

-- ---------------------------------------------------------------- click to loot
local function reply(player, text)
	player:sendCancelMessage(text)
	Chaos.send(player, OPCODE, "msg", {text = text}) -- shown by the client next to the loot channel
end

local function take(player, data)
	local c = cfg()
	local kill = state.kills[Chaos.toInt(data.k, 1) or 0]
	if not kill or kill.guid ~= player:getGuid() then
		Chaos.send(player, OPCODE, "decay", {k = tonumber(data.k) or 0})
		return reply(player, "That loot is gone.")
	end
	local n = Chaos.toInt(data.n, 1, #kill.entries)
	local entry = n and kill.entries[n]
	if not entry or Chaos.toInt(data.id, 1) ~= entry.info.clientId then
		return reply(player, "That item is not in this corpse.")
	end
	local corpse = refresh(kill)
	if not corpse then
		return reply(player, "The corpse is gone.")
	end
	if not canLoot(player, corpse) then
		return reply(player, "You are not the owner.")
	end
	if not F.inReach(player:getPosition(), kill.pos, c.reach) then
		return reply(player, "The corpse is too far away.")
	end
	local left = kill.left[n] or 0
	if left <= 0 then
		return reply(player, "Already looted.")
	end
	local item
	for _, it in ipairs(corpse:getItems()) do
		if F.signature(itemInfo(it)) == entry.sig then
			item = it
			break
		end
	end
	if not item then
		refresh(kill)
		return reply(player, "Already looted.")
	end
	local want = data.one and 1 or math.min(left, item:getCount())
	local moving = item
	if item:getType():isStackable() and want < item:getCount() then
		moving = item:split(want)
		if not moving then
			return reply(player, "Sorry, not possible.")
		end
	end
	local ok = intoBags(player, moving)
	if not ok and player:getStorageValue(ST.shopLootPouch) > 0 then
		ok = (ChaosStash and ChaosStash.storeItem(player, moving))
			or (player:getInbox() and moving:moveTo(player:getInbox())) or false
		if ok then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "Loot pouch: your backpack is full, sent to your stash or inbox.")
		end
	end
	if not ok then
		if moving ~= item then
			moving:moveTo(corpse) -- the split part goes back onto its stack
		end
		reply(player, "You do not have enough capacity or room.")
	end
	refresh(kill)
	if state.kills[kill.id] then
		ensureTimer()
	end
end

-- ---------------------------------------------------------------- peek (container highlight data)
local MAX_PEEK = 250

local function peek(player, data)
	local cid = Chaos.toInt(data.cid, 0, 255)
	local container = cid and player:getContainerById(cid)
	if not container then
		return
	end
	local isCorpse = container:getCorpseOwner() ~= 0 or container:getType():isCorpse()
	local rows = {}
	for i, item in ipairs(container:getItems()) do
		if i > MAX_PEEK then
			break
		end
		rows[#rows + 1] = wire(itemInfo(item), {i = i - 1})
	end
	Chaos.send(player, OPCODE, "peek", {cid = cid, corpse = isCorpse, items = rows})
end

-- ---------------------------------------------------------------- events
local LoginEvent = CreatureEvent("ChaosLootFilterLogin")
function LoginEvent.onLogin(player)
	player:registerEvent("ChaosLootFilterExtended")
	player:registerEvent("ChaosLootFilterLogout")
	addEvent(function(cid)
		local p = Player(cid)
		if p then
			sendSettings(p, false)
		end
	end, 1500, player:getId())
	return true
end
LoginEvent:type("login")
LoginEvent:register()

local LogoutEvent = CreatureEvent("ChaosLootFilterLogout")
function LogoutEvent.onLogout(player)
	local guid = player:getGuid()
	for _, id in ipairs(state.byGuid[guid] or {}) do
		state.kills[id] = nil
	end
	state.byGuid[guid] = nil
	return true
end
LogoutEvent:type("logout")
LogoutEvent:register()

local ExtendedEvent = CreatureEvent("ChaosLootFilterExtended")
function ExtendedEvent.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	if not msg then
		return
	end
	local data = type(msg.data) == "table" and msg.data or {}
	local ok, err = pcall(function()
		if msg.action == "open" then
			sendSettings(player, true)
		elseif msg.action == "sync" then
			sendSettings(player, false)
		elseif msg.action == "set" then
			saveSettings(player, F.sanitize(data.s or data))
			sendSettings(player, false)
		elseif msg.action == "preset" then
			local s = F.applyPreset(data.name)
			if s then
				local old = settingsOf(player)
				s.icons, s.notify = old.icons, old.notify -- presets change the rules, not the display options
				saveSettings(player, s)
			end
			sendSettings(player, false)
		elseif msg.action == "peek" then
			peek(player, data)
		elseif msg.action == "take" then
			take(player, data)
		end
	end)
	if not ok then
		print("[Chaos lootfilter] opcode failed: " .. tostring(err))
	end
end
ExtendedEvent:type("extendedopcode")
ExtendedEvent:register()

local talk = TalkAction("!lootfilter")
function talk.onSay(player, words, param)
	local name = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if name ~= "" then
		local s = F.applyPreset(name)
		if not s then
			player:sendCancelMessage("Presets: all, hunter, strict.")
			return false
		end
		local old = settingsOf(player)
		s.icons, s.notify = old.icons, old.notify
		saveSettings(player, s)
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Loot filter: preset " .. name .. ".")
		sendSettings(player, false)
		return false
	end
	sendSettings(player, true)
	return false
end
talk:separator(" ")
talk:register()
