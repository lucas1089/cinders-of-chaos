-- Guild halls: a guild-owned instance built at runtime (Game.createTile, like the arena, siege and rift slots), one
-- slot per guild that owns a hall. The engine has no call to remove a tile, so built slots stay for the server's
-- lifetime and a slot is reused when it changes owner (its fixtures are rebuilt).
-- Settings: guild_config.lua `hall` / `depot`. Pure rules: guild_core.lua. Runtime of levels / bank / window: guild.lua.
--
--   buying     the leader, at guild level hall.level, for hall.cost gold from the guild bank or their own gold
--   entry      a forcefield next to every temple (action id aid.enter): members of a guild with a hall go to their hall,
--              everyone else is refused; the daily guild hall scroll (level perk) does the same. The exit forcefield
--              (aid.exit) leads to the player's temple. Players cannot attack players inside a hall.
--   upgrades   (leader and vice-leaders, gold from the guild bank) teleport hub (portals to hunting areas), training
--              room (exercise dummies + a damage dummy), crafting bench (opens the crafting window), guild depot,
--              trophy room (statues with the guild's records), decoration tiers (floor and walls change look)
--   rent       weekly, paid from the guild bank when due (once a minute check). A bank that is short gives graceHours;
--              after that the upgrades are locked (their fixtures disappear, the depot is closed) until the rent is
--              paid (!guild rent, the window, or the next automatic try after a deposit). Nothing is deleted.
--   depot      drop an item on the guild depot (the large trunk) inside your hall: it is stored in chaos_guild_depot
--              (item id, count and attributes) and the item is removed; take it back from the Guild window. Every put
--              and take is logged. A take deletes the row first (one conditional DELETE) and only then creates the
--              item, so two fast clicks cannot duplicate it.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/guild_core.lua")
if not Chaos.guildConfig then
	Chaos.guildConfig = dofile("data/scripts/chaos/guild_config.lua")
end
local cfg = Chaos.guildConfig
local H = cfg.hall
ChaosGuild = ChaosGuild or {}
local G = ChaosGuild
local C = ChaosGuildCore
local T = cfg.tables
local OPCODE = ChaosOpcodes.guild or 252

G.halls = G.halls or {} -- guildId -> {slot, boughtAt, paidUntil, upgrades = {key = tier}}
G.built = G.built or {} -- slot -> {gid, sig} (what is built in the slot now)
G.unusable = G.unusable or {} -- slot -> true (a map tile is in the way)
G.dummyOf = G.dummyOf or {} -- slot -> creature id of the damage dummy
G.lockTold = G.lockTold or {} -- guildId -> true once the members were told the upgrades are locked
G.graceTold = G.graceTold or {} -- guildId -> os.time of the last "rent is due" reminder (once an hour)

local function log(text)
	print("[Chaos guild] " .. text)
end

local function now()
	return os.time()
end

local function P(t)
	return Position(t.x, t.y, t.z)
end

-- ---------------------------------------------------------------- state
function G.loadHalls()
	G.halls = {}
	for _, r in ipairs(Chaos.select(string.format("SELECT `guild_id`, `slot`, `bought_at`, `paid_until` FROM `%s`", T.hall),
			{{"guild_id", "n"}, {"slot", "n"}, {"bought_at", "n"}, {"paid_until", "n"}})) do
		G.halls[r.guild_id] = {slot = r.slot, boughtAt = r.bought_at, paidUntil = r.paid_until, upgrades = {}}
	end
	for _, r in ipairs(Chaos.select(string.format("SELECT `guild_id`, `upgrade`, `tier` FROM `%s`", T.upgrades),
			{{"guild_id", "n"}, {"upgrade", "s"}, {"tier", "n"}})) do
		local h = G.halls[r.guild_id]
		if h then
			h.upgrades[r.upgrade] = r.tier
		end
	end
	G.hallsLoaded = true
end

function G.hallOf(gid)
	if not G.hallsLoaded then
		G.loadHalls()
	end
	return gid and G.halls[gid] or nil
end

function G.rentStateOf(gid)
	local h = G.hallOf(gid)
	if not h then
		return nil, 0
	end
	return C.rentState(h.paidUntil, now(), cfg)
end

function G.activeOf(gid)
	local h = G.hallOf(gid)
	if not h then
		return {}
	end
	return C.activeUpgrades(h.upgrades, (G.rentStateOf(gid)))
end

local function guildOfSlot(slot)
	for gid, h in pairs(G.halls) do
		if h.slot == slot then
			return gid, h
		end
	end
	return nil
end

-- ---------------------------------------------------------------- building
local function groundIdOf(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local OUR_GROUNDS, OUR_WALLS = {}, {}
for _, d in pairs(H.decor) do
	OUR_GROUNDS[d.ground] = true
	OUR_WALLS[d.wall] = true
end
-- decoration tiers with a `dark` pair use the dark tile set when it is installed (guild_config.lua); the stock ids
-- stay in OUR_GROUNDS / OUR_WALLS, so halls built before still change look
if not ChaosDarkTiles then
	dofile("data/lib/chaos_dark_tiles.lua")
end
for _, d in pairs(H.decor) do
	if d.dark and not d.stock then
		local g, w = ChaosDarkTiles.id(d.dark.ground), ChaosDarkTiles.id(d.dark.wall)
		if g and w then
			d.stock = {ground = d.ground, wall = d.wall}
			d.ground, d.wall = g, w
			OUR_GROUNDS[g] = true
			OUR_WALLS[w] = true
		end
	end
end

-- create the tiles of a slot once; false + reason when a map tile is in the way (the slot is marked unusable)
function G.buildSlot(slot)
	if G.unusable[slot] then
		return false, "slot unusable"
	end
	local foot = C.footprint(slot, cfg)
	for _, t in ipairs(foot) do
		local tile = Tile(P(t))
		if tile then
			local gid = groundIdOf(tile)
			if not OUR_GROUNDS[gid] or (tile.getHouse and tile:getHouse()) then
				G.unusable[slot] = true
				log(string.format("hall slot %d unusable: tile %d,%d,%d is in the map", slot, t.x, t.y, t.z))
				return false, "tile in the map"
			end
		end
	end
	for _, t in ipairs(foot) do
		local pos = P(t)
		local tile = Tile(pos) or Game.createTile(pos, true)
		if tile then
			if not tile:getGround() then
				Game.createItem(H.ids.ground, 1, pos)
			end
			if t.wall then
				local hasWall = false
				for id in pairs(OUR_WALLS) do
					if tile:getItemById(id) then
						hasWall = true
					end
				end
				if not hasWall then
					Game.createItem(H.ids.wall, 1, pos)
				end
			end
		end
	end
	return true
end

-- every fixture item id (removed from a fixture position when that fixture is not wanted)
local FIXTURES = {[H.ids.portal] = true, [H.ids.basin] = true, [H.ids.flag] = true, [H.ids.bench] = true, [H.ids.depot] = true}
for _, id in ipairs(H.ids.dummies) do
	FIXTURES[id] = true
end
for _, id in ipairs(H.ids.trophies) do
	FIXTURES[id] = true
end

-- make the item at pos exactly `id` with action id `aid` (or nothing when id is nil); returns the item
local function fixture(pos, id, aid, description)
	local tile = Tile(P(pos))
	if not tile then
		return nil
	end
	local keep
	for _, item in ipairs(tile:getItems() or {}) do
		local iid = item:getId()
		if FIXTURES[iid] then
			if id and iid == id and not keep then
				keep = item
			else
				item:remove()
			end
		end
	end
	if id and not keep then
		keep = Game.createItem(id, 1, P(pos))
	end
	if keep then
		if aid then
			keep:setActionId(aid)
		end
		if description then
			keep:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, description)
		end
	end
	return keep
end

local function trophyTexts(gid)
	local s = G.statsOf(gid)
	local r = G.row(gid)
	local top = Chaos.select(string.format("SELECT p.`name`, SUM(c.`amount`) AS `n` FROM `%s` c JOIN `players` p ON p.`id` = c.`player_id` " ..
		"WHERE c.`guild_id` = %d GROUP BY c.`player_id` ORDER BY `n` DESC LIMIT 3", T.contrib, gid), {{"name", "s"}, {"n", "n"}})
	local names = {}
	for _, t in ipairs(top) do
		names[#names + 1] = string.format("%s (%s)", t.name, C.money(t.n))
	end
	return {
		string.format("Guild Siege: %d win%s in %d siege%s.", s.siegeWins or 0, (s.siegeWins or 0) == 1 and "" or "s",
			s.sieges or 0, (s.sieges or 0) == 1 and "" or "s"),
		string.format("World bosses: %d victories shared by the members.", s.worldboss or 0),
		string.format("Records: highest rift tier %d, %d rifts sealed, %d bounties, %d invasions defended.", s.riftBest or 0,
			s.rift or 0, s.bounty or 0, s.invasion or 0),
		string.format("Guild level %d (%s GXP). Top contributors: %s.", r.level, C.money(r.xp),
			#names > 0 and table.concat(names, ", ") or "none yet")
	}
end

local function dummyMonsterName()
	for _, name in ipairs(H.dummyMonsters or {}) do
		if MonsterType(name) then
			return name
		end
	end
	return nil
end

local function setDecor(slot, tier)
	local d = H.decor[tier] or H.decor[0]
	for _, t in ipairs(C.footprint(slot, cfg)) do
		local tile = Tile(P(t))
		if tile then
			local g = tile:getGround()
			if g and type(g) ~= "number" and g:getId() ~= d.ground and OUR_GROUNDS[g:getId()] then
				g:transform(d.ground)
			end
			if t.wall then
				for id in pairs(OUR_WALLS) do
					local w = tile:getItemById(id)
					if w and id ~= d.wall then
						w:transform(d.wall)
					end
				end
			end
		end
	end
end

-- (re)place the fixtures of a guild's hall for the upgrades that work now
function G.furnish(gid)
	local h = G.hallOf(gid)
	if not h then
		return false
	end
	local okBuild = G.buildSlot(h.slot)
	if not okBuild then
		return false
	end
	local L = C.layout(h.slot, cfg)
	local active = G.activeOf(gid)
	local A = H.aid
	setDecor(h.slot, active.decor or 0)
	fixture(L.exit, H.ids.portal, A.exit, "The way back to your temple.")
	for _, p in ipairs(L.basins) do
		fixture(p, H.ids.basin)
	end
	for _, p in ipairs(L.flags) do
		fixture(p, H.ids.flag, nil, "The banner of " .. G.nameOf(gid) .. ".")
	end
	for i, p in ipairs(L.hub) do
		local dest = H.hub[i]
		if active.hub and dest then
			fixture(p, H.ids.portal, A.hub, string.format("Teleport to %s (level %d+).", dest.name, dest.level or 0))
		else
			fixture(p, nil)
		end
	end
	for i, p in ipairs(L.dummies) do
		fixture(p, active.training and H.ids.dummies[(i - 1) % #H.ids.dummies + 1] or nil)
	end
	local cid = G.dummyOf[h.slot]
	local creature = cid and Creature(cid)
	local dname = dummyMonsterName()
	if active.training and dname then
		if not creature then
			local m = Game.createMonster(dname, P(L.dummyMonster), false, true)
			G.dummyOf[h.slot] = m and m:getId() or nil
		end
	elseif creature then
		creature:remove()
		G.dummyOf[h.slot] = nil
	end
	fixture(L.bench, active.crafting and H.ids.bench or nil, A.bench, "The guild's crafting bench. Use it to craft.")
	fixture(L.depot, active.depot and H.ids.depot or nil, A.depot,
		"The guild depot. Drop an item on it to store it for the guild; use it to see what is inside.")
	local texts = active.trophy and trophyTexts(gid) or {}
	for i, p in ipairs(L.trophies) do
		fixture(p, active.trophy and H.ids.trophies[i] or nil, A.trophy, texts[i])
	end
	G.built[h.slot] = {gid = gid, sig = G.signature(gid)}
	return true
end

-- what the furnished slot should look like (changes -> furnish again)
function G.signature(gid)
	local h = G.hallOf(gid)
	if not h then
		return ""
	end
	local active = G.activeOf(gid)
	local keys = {}
	for k, tier in pairs(active) do
		keys[#keys + 1] = k .. tier
	end
	table.sort(keys)
	return table.concat(keys, ",")
end

local function ensureFurnished(gid)
	local h = G.hallOf(gid)
	local b = h and G.built[h.slot]
	if not b or b.gid ~= gid or b.sig ~= G.signature(gid) then
		return G.furnish(gid)
	end
	return true
end

-- ---------------------------------------------------------------- entering and leaving
function G.inHall(pos)
	local slot = C.slotAt(pos, cfg)
	if not slot or not G.built[slot] then
		return nil
	end
	return slot, (guildOfSlot(slot))
end

-- send a member to their guild's hall (staffGid: a staff member to any guild's hall). false when there is none.
function G.enterHall(player, quiet, staffGid)
	local gid = staffGid or G.guildOf(player)
	local h = gid and G.hallOf(gid)
	if not h then
		return false
	end
	if not ensureFurnished(gid) then
		player:sendCancelMessage("The guild hall cannot be built right now. Tell a gamemaster.")
		return false
	end
	local L = C.layout(h.slot, cfg)
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	player:teleportTo(P(L.arrival))
	P(L.arrival):sendMagicEffect(CONST_ME_TELEPORT)
	local state = G.rentStateOf(gid)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Welcome to the hall of %s.%s", G.nameOf(gid),
		state == "locked" and " The rent is unpaid: the upgrades are locked." or
		(state == "grace" and " The rent is due: pay it before the upgrades lock." or "")))
	return true
end

local function templeOf(player)
	if H.exitPosition then
		return P(H.exitPosition)
	end
	local town = player:getTown()
	return town and town:getTemplePosition() or player:getPosition()
end

local function pushBack(player, fromPosition, text)
	player:sendCancelMessage(text)
	player:teleportTo(fromPosition, true)
	fromPosition:sendMagicEffect(CONST_ME_POFF)
end

local enter = MoveEvent()
function enter.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local gid = G.guildOf(player)
	if not gid then
		pushBack(player, fromPosition, "Only guild members may enter a guild hall.")
		return true
	end
	if not G.hallOf(gid) then
		pushBack(player, fromPosition, "Your guild owns no guild hall.")
		return true
	end
	if not G.enterHall(player) then
		pushBack(player, fromPosition, "Your guild hall cannot be entered right now.")
	end
	return true
end
enter:type("stepin")
enter:aid(H.aid.enter)
enter:register()

local exit = MoveEvent()
function exit.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local temple = templeOf(player)
	player:teleportTo(temple)
	temple:sendMagicEffect(CONST_ME_TELEPORT)
	return true
end
exit:type("stepin")
exit:aid(H.aid.exit)
exit:register()

-- the nearest free walkable tile around pos (within 3 tiles)
local function landing(pos)
	for r = 0, 3 do
		for dy = -r, r do
			for dx = -r, r do
				if math.max(math.abs(dx), math.abs(dy)) == r then
					local p = Position(pos.x + dx, pos.y + dy, pos.z)
					local tile = Tile(p)
					if tile and tile:getGround() and not tile:hasProperty(CONST_PROP_BLOCKSOLID)
							and not tile:hasProperty(CONST_PROP_BLOCKPATH) and not tile:getTopCreature()
							and not (tile.getHouse and tile:getHouse()) then
						return p
					end
				end
			end
		end
	end
	return nil
end

local hub = MoveEvent()
function hub.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player then
		return true
	end
	local slot, gid = G.inHall(position)
	if not slot or not G.activeOf(gid).hub then
		pushBack(player, fromPosition, "The teleport hub is locked.")
		return true
	end
	local L = C.layout(slot, cfg)
	local index
	for i, p in ipairs(L.hub) do
		if p.x == position.x and p.y == position.y then
			index = i
		end
	end
	local dest = index and H.hub[index]
	local to = dest and landing(dest.pos)
	if not to then
		pushBack(player, fromPosition, "This portal leads nowhere right now.")
		return true
	end
	player:teleportTo(to)
	to:sendMagicEffect(CONST_ME_TELEPORT)
	player:sendTextMessage(MESSAGE_INFO_DESCR, "The guild portal takes you to " .. dest.name .. ".")
	return true
end
hub:type("stepin")
hub:aid(H.aid.hub)
hub:register()

-- entry forcefields next to the temples (runtime items; created at startup and checked once a minute)
local function spotFree(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() or (tile.getHouse and tile:getHouse()) then
		return false
	end
	if tile:hasProperty(CONST_PROP_BLOCKSOLID) or tile:hasProperty(CONST_PROP_BLOCKPATH) then
		return false
	end
	return not (ITEM_TYPE_TELEPORT and tile:getItemByType(ITEM_TYPE_TELEPORT))
end

function G.placePortals()
	G.portals = G.portals or {}
	local function has(pos)
		local tile = Tile(pos)
		local it = tile and tile:getItemById(H.ids.portal)
		return it and it:getActionId() == H.aid.enter
	end
	local spots = {}
	if H.portalPositions and #H.portalPositions > 0 then
		for _, p in ipairs(H.portalPositions) do
			spots[#spots + 1] = P(p)
		end
	else
		local seen = {}
		for _, town in ipairs(Game.getTowns()) do
			local t = town:getTemplePosition()
			local key = t.x .. "," .. t.y .. "," .. t.z
			if t.x > 0 and not seen[key] and Tile(t) then
				seen[key] = true
				local done = false
				for _, off in ipairs(H.portalOffsets) do
					local p = Position(t.x + off[1], t.y + off[2], t.z)
					if has(p) then
						done = true
						break
					end
				end
				if not done then
					for _, off in ipairs(H.portalOffsets) do
						local p = Position(t.x + off[1], t.y + off[2], t.z)
						if spotFree(p) then
							spots[#spots + 1] = p
							break
						end
					end
				end
			end
		end
	end
	local made = 0
	for _, pos in ipairs(spots) do
		if Tile(pos) and not has(pos) then
			local item = Game.createItem(H.ids.portal, 1, pos)
			if item then
				item:setActionId(H.aid.enter)
				item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "The way to your guild's hall (members of a guild that owns one).")
				made = made + 1
			end
		end
	end
	return made
end

-- ---------------------------------------------------------------- buying
local function rankOf(player)
	local gid, _, rank = G.guildOf(player)
	return gid, rank or 0
end

function G.buyHall(player, from)
	local gid, rank = rankOf(player)
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "guild.money", 1000) then
		return false, "Slow down."
	end
	local blocked = G.seasonBlocked(player)
	if blocked then
		return false, blocked
	end
	local r = gid and G.row(gid) or {}
	local money = (player.getTotalMoney and player:getTotalMoney()) or player:getMoney()
	local err = C.hallBuyError({guildId = gid, rank = rank, level = gid and G.levelOf(gid) or 0, hasHall = gid and G.hallOf(gid) ~= nil,
		from = from, bank = r.bank or 0, money = money}, cfg)
	if err then
		return false, err
	end
	-- a slot first (nothing is charged when none can be built)
	local used = {}
	for _, h in pairs(G.halls) do
		used[h.slot] = true
	end
	local slot
	while true do
		slot = C.allocSlot(used, G.unusable, H.maxSlots)
		if not slot then
			return false, "No guild hall slot is free. Tell a gamemaster."
		end
		if G.buildSlot(slot) then
			break
		end
	end
	-- pay
	local paid
	if from == "bank" then
		paid = G.spend(gid, H.cost)
	else
		paid = G.payFromPlayer(player, H.cost)
	end
	if not paid then
		return false, "Not enough gold."
	end
	local t = now()
	local period = H.rent.periodDays * 86400
	local n = G.exec(string.format("INSERT IGNORE INTO `%s` (`guild_id`, `slot`, `bought_at`, `paid_until`) VALUES (%d, %d, %d, %d)",
		T.hall, gid, slot, t, t + period))
	if n ~= 1 then
		if from == "bank" then
			G.credit(gid, H.cost)
		else
			player:setBankBalance(player:getBankBalance() + H.cost)
		end
		G.logRow(gid, player, "refund", H.cost, 0, 0, "hall purchase failed")
		return false, "The purchase failed; the gold was returned."
	end
	G.halls[gid] = {slot = slot, boughtAt = t, paidUntil = t + period, upgrades = {}}
	G.built[slot] = nil
	G.logRow(gid, player, "hall", H.cost, 0, slot, string.format("bought the guild hall (slot %d, %s)", slot,
		from == "bank" and "guild bank" or "own gold"))
	G.furnish(gid)
	G.tellGuild(gid, string.format("%s bought a guild hall for %s! Enter it through the portal next to the temple.",
		player:getName(), G.nameOf(gid)))
	return true, string.format("Your guild owns a guild hall now. The first week's rent is paid; next rent: %s gold.",
		C.money(C.rentAmount({}, cfg)))
end

function G.buyUpgrade(player, key)
	local gid, rank = rankOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "guild.money", 1000) then
		return false, "Slow down."
	end
	local h = G.hallOf(gid)
	local info = {rank = rank, level = G.levelOf(gid), hasHall = h ~= nil, upgrades = h and h.upgrades or {},
		rentState = h and (G.rentStateOf(gid)) or nil, bank = G.row(gid).bank}
	local err, nextTier, tierNo = C.upgradeError(key, info, cfg)
	if err then
		return false, err
	end
	local def = C.upgradeDef(key, cfg)
	if not G.spend(gid, nextTier.cost) then
		return false, "The guild bank does not hold enough gold."
	end
	local n
	if tierNo == 1 then
		n = G.exec(string.format("INSERT IGNORE INTO `%s` (`guild_id`, `upgrade`, `tier`, `bought_at`) VALUES (%d, %s, 1, %d)",
			T.upgrades, gid, db.escapeString(key), now()))
	else
		n = G.exec(string.format("UPDATE `%s` SET `tier` = %d, `bought_at` = %d WHERE `guild_id` = %d AND `upgrade` = %s AND `tier` = %d",
			T.upgrades, tierNo, now(), gid, db.escapeString(key), tierNo - 1))
	end
	if n ~= 1 then
		G.credit(gid, nextTier.cost)
		G.logRow(gid, player, "refund", nextTier.cost, 0, 0, def.name .. " purchase failed")
		G.loadHalls()
		return false, "The upgrade failed; the gold went back to the guild bank."
	end
	h.upgrades[key] = tierNo
	G.logRow(gid, player, "upgrade", nextTier.cost, 0, tierNo, string.format("%s%s", def.name, #def.tiers > 1 and (" tier " .. tierNo) or ""))
	G.furnish(gid)
	G.tellGuild(gid, string.format("%s added %s%s to the guild hall.", player:getName(), def.name,
		#def.tiers > 1 and (" (tier " .. tierNo .. ")") or ""))
	return true, string.format("%s bought for %s gold. Weekly rent is now %s gold.", def.name, C.money(nextTier.cost),
		C.money(C.rentAmount(h.upgrades, cfg)))
end

-- ---------------------------------------------------------------- rent
-- pay one period from the guild bank; by = the player who paid (nil: automatic)
function G.payRent(gid, by)
	local h = G.hallOf(gid)
	if not h then
		return false, "Your guild has no guild hall."
	end
	local amount = C.rentAmount(h.upgrades, cfg)
	local old = h.paidUntil
	local newUntil = C.rentPaidUntil(old, now(), cfg)
	if not G.spend(gid, amount) then
		return false, string.format("The guild bank holds %s gold; the rent is %s.", C.money(G.row(gid).bank), C.money(amount))
	end
	local n = G.exec(string.format("UPDATE `%s` SET `paid_until` = %d WHERE `guild_id` = %d AND `paid_until` = %d", T.hall, newUntil, gid, old))
	if n ~= 1 then
		G.credit(gid, amount)
		G.logRow(gid, by, "refund", amount, 0, 0, "rent payment failed")
		G.loadHalls()
		return false, "The payment failed; the gold went back to the guild bank."
	end
	h.paidUntil = newUntil
	G.lockTold[gid] = nil
	G.logRow(gid, by or {guid = 0, name = "Guild bank"}, "rent", amount, 0, 0,
		"rent paid until " .. os.date("%d.%m.%Y %H:%M", newUntil))
	ensureFurnished(gid)
	return true, string.format("Rent of %s gold paid; the hall is paid until %s.", C.money(amount), os.date("%d.%m %H:%M", newUntil))
end

function G.payRentBy(player)
	local gid, rank = rankOf(player)
	if not gid then
		return false, "You are not in a guild."
	end
	if rank < H.upgradeRank then
		return false, "Only the guild leader or a vice-leader can pay the rent."
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "guild.money", 1000) then
		return false, "Slow down."
	end
	local h = G.hallOf(gid)
	if h and C.rentState(h.paidUntil, now(), cfg) == "paid" and h.paidUntil - now() > H.rent.periodDays * 86400 then
		return false, "The rent is already paid for more than a week ahead."
	end
	return G.payRent(gid, player)
end

-- staff test helper: due (paid_until = now, in grace), lock (past the grace time), paid (a week ahead)
function G.staffRent(gid, what)
	local h = G.hallOf(gid)
	if not h then
		return "That guild has no hall."
	end
	local t = now()
	local v = what == "lock" and (t - H.rent.graceHours * 3600 - 60) or (what == "due" and t - 60 or t + H.rent.periodDays * 86400)
	db.query(string.format("UPDATE `%s` SET `paid_until` = %d WHERE `guild_id` = %d", T.hall, v, gid))
	h.paidUntil = v
	G.logRow(gid, {guid = 0, name = "Staff"}, "rent", 0, 0, 0, "staff set the rent to " .. what)
	G.hallThink(true)
	return string.format("Rent of %s: %s (paid until %s).", G.nameOf(gid), (G.rentStateOf(gid)), os.date("%d.%m %H:%M", v))
end

-- once a minute: automatic rent, locks, fixtures, players who do not belong in a hall
function G.hallThink(noPay)
	if not G.hallsLoaded then
		G.loadHalls()
	end
	G.placePortals()
	for gid, h in pairs(G.halls) do
		local state = C.rentState(h.paidUntil, now(), cfg)
		if state ~= "paid" and not noPay then
			local ok = G.payRent(gid, nil)
			if ok then
				G.tellGuild(gid, "The guild hall's rent was paid from the guild bank.")
				state = "paid"
			end
		end
		if state == "locked" and not G.lockTold[gid] then
			G.lockTold[gid] = true
			G.tellGuild(gid, string.format("The guild hall's rent (%s gold) is unpaid: its upgrades are locked until it is paid (Social > Guild).",
				C.money(C.rentAmount(h.upgrades, cfg))))
		elseif state == "grace" and not noPay and now() - (G.graceTold[gid] or 0) >= 3600 then
			G.graceTold[gid] = now()
			G.tellGuild(gid, string.format("The guild hall's rent is due and the guild bank is short. The upgrades lock in %s.",
				C.durationText(h.paidUntil + H.rent.graceHours * 3600 - now())), MESSAGE_STATUS_SMALL)
		end
		local b = G.built[h.slot]
		if b and (b.gid ~= gid or b.sig ~= G.signature(gid)) then
			G.furnish(gid)
		end
	end
	for _, p in ipairs(Game.getPlayers()) do
		G.checkInside(p)
	end
end

-- a player inside a hall that is not their guild's goes to the temple
function G.checkInside(player)
	local slot, gid = G.inHall(player:getPosition())
	if not slot or player:getGroup():getAccess() then
		return
	end
	local own = G.guildOf(player)
	if not gid or own ~= gid then
		local temple = templeOf(player)
		player:teleportTo(temple)
		temple:sendMagicEffect(CONST_ME_TELEPORT)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You are not a member of this hall's guild.")
	end
end

function G.onLoginHall(player)
	G.checkInside(player)
end

-- no player-versus-player inside the halls
local pvp = EventCallback
pvp.onTargetCombat = function(creature, target)
	if creature and target and creature:isPlayer() and target:isPlayer() and (G.inHall(target:getPosition()) or G.inHall(creature:getPosition())) then
		return RETURNVALUE_YOUMAYNOTATTACKTHISPLAYER
	end
	return RETURNVALUE_NOERROR
end
pvp:register(60)

-- ---------------------------------------------------------------- crafting bench, depot chest
local bench = Action()
function bench.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local slot, gid = G.inHall(item:getPosition())
	if not slot or not G.activeOf(gid).crafting then
		player:sendCancelMessage("The crafting bench is locked.")
		return true
	end
	Chaos.send(player, OPCODE, "openModule", {name = "game_crafting"})
	return true
end
bench:aid(H.aid.bench)
bench:register()

local depotUse = Action()
function depotUse.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	G.sendState(player, true, "depot")
	return true
end
depotUse:aid(H.aid.depot)
depotUse:register()

-- attributes copied with a depot item
local STD = {
	{"ITEM_ATTRIBUTE_DESCRIPTION", "s"}, {"ITEM_ATTRIBUTE_TEXT", "s"}, {"ITEM_ATTRIBUTE_WRITER", "s"}, {"ITEM_ATTRIBUTE_DATE", "n"},
	{"ITEM_ATTRIBUTE_NAME", "s"}, {"ITEM_ATTRIBUTE_ARTICLE", "s"}, {"ITEM_ATTRIBUTE_PLURALNAME", "s"},
	{"ITEM_ATTRIBUTE_ACTIONID", "n"}, {"ITEM_ATTRIBUTE_ATTACK", "n"}, {"ITEM_ATTRIBUTE_DEFENSE", "n"},
	{"ITEM_ATTRIBUTE_EXTRADEFENSE", "n"}, {"ITEM_ATTRIBUTE_ARMOR", "n"}, {"ITEM_ATTRIBUTE_HITCHANCE", "n"},
	{"ITEM_ATTRIBUTE_SHOOTRANGE", "n"}, {"ITEM_ATTRIBUTE_CHARGES", "n"}, {"ITEM_ATTRIBUTE_DURATION", "n"}
}

local customKeys
local function depotCustomKeys()
	if customKeys then
		return customKeys
	end
	local seen, list = {}, {}
	local function add(k)
		if type(k) == "string" and not seen[k] then
			seen[k] = true
			list[#list + 1] = k
		end
	end
	for _, k in ipairs(cfg.depot.customKeys or {}) do
		add(k)
	end
	if ChaosCrafting then
		for _, v in pairs(ChaosCrafting) do
			if type(v) == "table" then
				for _, e in pairs(v) do
					if type(e) == "table" then
						for _, k in ipairs({e.key, e.key2}) do
							for _, prefix in ipairs(cfg.depot.customPrefixes or {}) do
								if type(k) == "string" and k:sub(1, #prefix) == prefix then
									add(k)
								end
							end
						end
					end
				end
			end
		end
	end
	-- the item level, every modifier and its tier mark (chaos_crafting.lua C.attributeKeys)
	if ChaosCrafting and ChaosCrafting.attributeKeys then
		for _, k in ipairs(ChaosCrafting.attributeKeys()) do
			add(k)
		end
	end
	customKeys = list
	return list
end

local function readAttrs(item)
	local list = {}
	for _, a in ipairs(STD) do
		local c = _G[a[1]]
		if c and item:hasAttribute(c) then
			local v = item:getAttribute(c)
			if v ~= nil and v ~= "" and v ~= 0 then
				list[#list + 1] = {"@" .. a[1], v}
			end
		end
	end
	for _, k in ipairs(depotCustomKeys()) do
		local v = item:getCustomAttribute(k)
		if v ~= nil then
			list[#list + 1] = {k, v}
		end
	end
	return list
end

local function writeAttrs(item, list)
	for _, a in ipairs(list) do
		local k, v = a[1], a[2]
		if k:sub(1, 1) == "@" then
			local c = _G[k:sub(2)]
			if c then
				item:setAttribute(c, v)
			end
		else
			item:setCustomAttribute(k, v)
		end
	end
end

local function depotUsed(gid)
	local r = Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `guild_id` = %d", T.depot, gid), {{"n", "n"}})[1]
	return r and r.n or 0
end

-- put an item into the guild depot; the player must stand in their own hall
function G.depotPut(player, item)
	local gid, rank = rankOf(player)
	local slot, hallGid = G.inHall(player:getPosition())
	local it = ItemType(item:getId())
	local blocked = G.seasonBlocked(player)
	if blocked then
		return false, blocked
	end
	local count = it:isStackable() and item:getCount() or 1
	local err = C.depotPutError({member = gid ~= nil and gid == hallGid and slot ~= nil, active = gid and G.activeOf(gid).depot ~= nil,
		used = gid and depotUsed(gid) or 0, capacity = gid and C.depotCapacity(G.levelOf(gid), cfg) or 0,
		container = item:isContainer(), pickupable = it:isPickupable(), count = count}, cfg)
	if err then
		return false, err
	end
	local attrs = C.encodeAttrs(readAttrs(item))
	local name = item:getName()
	if not db.query(string.format("INSERT INTO `%s` (`guild_id`, `item_id`, `count`, `name`, `attrs`, `added_by`, `added_at`) VALUES (%d, %d, %d, %s, %s, %d, %d)",
			T.depot, gid, item:getId(), count, db.escapeString(name), db.escapeString(attrs), player:getGuid(), now())) then
		return false, "The guild depot could not take it."
	end
	local id = (Chaos.select("SELECT LAST_INSERT_ID() AS `id`", {{"id", "n"}})[1] or {}).id or 0
	if not item:remove() then
		db.query(string.format("DELETE FROM `%s` WHERE `id` = %d", T.depot, id))
		return false, "The item could not be moved into the guild depot."
	end
	G.logRow(gid, player, "put", 0, it:getId(), count, name)
	return true, string.format("You put %d x %s into the guild depot.", count, name)
end

function G.depotTake(player, id)
	local gid, rank = rankOf(player)
	id = Chaos.toInt(id, 1)
	if not gid or not id then
		return false, "Take what?"
	end
	if ChaosRateLimit and not ChaosRateLimit.allow(player, "guild.depot", 500) then
		return false, "Slow down."
	end
	local blocked = G.seasonBlocked(player)
	if blocked then
		return false, blocked
	end
	local row = Chaos.select(string.format("SELECT `item_id`, `count`, `name`, `attrs` FROM `%s` WHERE `id` = %d AND `guild_id` = %d", T.depot, id, gid),
		{{"item_id", "n"}, {"count", "n"}, {"name", "s"}, {"attrs", "s"}})[1]
	local dayStart = os.time({year = tonumber(os.date("%Y")), month = tonumber(os.date("%m")), day = tonumber(os.date("%d")), hour = 0})
	local taken = (Chaos.select(string.format("SELECT COUNT(*) AS `n` FROM `%s` WHERE `guild_id` = %d AND `player_id` = %d AND `action` = 'take' AND `at` >= %d",
		T.log, gid, player:getGuid(), dayStart), {{"n", "n"}})[1] or {n = 0}).n
	local slot, hallGid = G.inHall(player:getPosition())
	local err = C.depotTakeError({member = slot ~= nil and hallGid == gid, active = G.activeOf(gid).depot ~= nil, rank = rank,
		takenToday = taken, exists = row ~= nil}, cfg)
	if err then
		if err:find("members of this guild") then
			err = "Take items at the guild depot in your guild hall."
		end
		return false, err
	end
	-- the row goes first: a second click finds nothing
	if G.exec(string.format("DELETE FROM `%s` WHERE `id` = %d AND `guild_id` = %d", T.depot, id, gid)) ~= 1 then
		return false, "That item is no longer in the guild depot."
	end
	local item = Game.createItem(row.item_id, row.count)
	if not item then
		G.logRow(gid, player, "error", 0, row.item_id, row.count, "could not create " .. row.name .. " (row deleted)")
		return false, "The item could not be created. Tell a gamemaster."
	end
	writeAttrs(item, C.decodeAttrs(row.attrs))
	local where = "backpack"
	if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
		local inbox = player:getInbox()
		if inbox and inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT) == RETURNVALUE_NOERROR then
			where = "inbox"
		else
			db.query(string.format("INSERT INTO `%s` (`id`, `guild_id`, `item_id`, `count`, `name`, `attrs`, `added_by`, `added_at`) VALUES (%d, %d, %d, %d, %s, %s, %d, %d)",
				T.depot, id, gid, row.item_id, row.count, db.escapeString(row.name), db.escapeString(row.attrs), player:getGuid(), now()))
			item:remove()
			return false, "You have no room for it."
		end
	end
	G.logRow(gid, player, "take", 0, row.item_id, row.count, row.name)
	return true, string.format("You took %d x %s from the guild depot (%s).", row.count, row.name, where)
end

-- drop on the depot chest (on its tile, or into it)
local moved = EventCallback
moved.onItemMoved = function(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item or not player then
		return
	end
	local target
	if toCylinder and toCylinder.isItem and toCylinder:isItem() and toCylinder:getActionId() == H.aid.depot then
		target = toCylinder
	elseif toPosition and toPosition.x ~= (CONTAINER_POSITION or 0xFFFF) then
		local tile = Tile(toPosition)
		local chest = tile and tile:getItemById(H.ids.depot)
		if chest and chest:getActionId() == H.aid.depot then
			target = chest
		end
	end
	if not target or item == target then
		return
	end
	local ok, text = G.depotPut(player, item)
	if ok then
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
		G.sendState(player, false, "depot")
	else
		player:sendCancelMessage(text)
		-- back to the player (or it stays where it was dropped)
		if item:getTopParent() ~= player then
			item:moveTo(player)
		end
	end
end
moved:register(70)

-- ---------------------------------------------------------------- window data
function G.hallView(player, gid, rank, level)
	local h = G.hallOf(gid)
	local r = G.row(gid)
	local hall = {owned = h ~= nil, cost = H.cost, level = H.level, canBuy = false, reason = "", rank = rank,
		canManage = rank >= H.upgradeRank}
	if not h then
		local errBank = C.hallBuyError({guildId = gid, rank = rank, level = level, hasHall = false, from = "bank", bank = r.bank}, cfg)
		local money = (player.getTotalMoney and player:getTotalMoney()) or player:getMoney()
		local errSelf = C.hallBuyError({guildId = gid, rank = rank, level = level, hasHall = false, from = "self", money = money}, cfg)
		hall.canBuyBank, hall.canBuySelf = errBank == nil, errSelf == nil
		hall.reason = errBank or ""
		hall.reasonSelf = errSelf or ""
		return hall, {active = false, items = {}, log = {}, used = 0, capacity = C.depotCapacity(level, cfg)}
	end
	local state, left = C.rentState(h.paidUntil, now(), cfg)
	hall.slot = h.slot
	hall.rentState = state
	hall.rentLeft = left
	hall.rent = C.rentAmount(h.upgrades, cfg)
	hall.paidUntil = os.date("%d.%m %H:%M", h.paidUntil)
	hall.graceLeft = state == "grace" and (h.paidUntil + H.rent.graceHours * 3600 - now()) or 0
	hall.upgrades = C.upgradeView({rank = rank, level = level, hasHall = true, upgrades = h.upgrades, rentState = state, bank = r.bank}, cfg)
	local active = C.activeUpgrades(h.upgrades, state)
	for _, u in ipairs(hall.upgrades) do
		u.active = active[u.key] ~= nil
	end
	local hubs = {}
	for _, d in ipairs(H.hub) do
		hubs[#hubs + 1] = d.name
	end
	hall.hub = hubs
	local depot = {active = active.depot ~= nil, owned = (h.upgrades.depot or 0) > 0, items = {}, used = 0,
		capacity = C.depotCapacity(level, cfg)}
	if depot.owned then
		for _, row in ipairs(Chaos.select(string.format("SELECT `id`, `item_id`, `count`, `name` FROM `%s` WHERE `guild_id` = %d ORDER BY `id` LIMIT 200",
				T.depot, gid), {{"id", "n"}, {"item_id", "n"}, {"count", "n"}, {"name", "s"}})) do
			local it = ItemType(row.item_id)
			depot.items[#depot.items + 1] = {id = row.id, name = row.name, count = row.count, clientId = it and it:getClientId() or 0}
		end
		depot.used = #depot.items
		depot.log = G.logLines(gid, {"put", "take"})
	else
		depot.log = {}
	end
	return hall, depot
end

-- ---------------------------------------------------------------- startup
local startup = GlobalEvent("ChaosGuildHallStartup")
function startup.onStartup()
	G.loadHalls()
	local n = G.placePortals()
	log(string.format("%d guild hall(s), %d entry portal(s) placed", (function()
		local c = 0
		for _ in pairs(G.halls) do
			c = c + 1
		end
		return c
	end)(), n))
	return true
end
startup:register()
