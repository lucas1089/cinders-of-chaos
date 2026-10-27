-- TEST ONLY: never ship this file. It is not under server/data, so install_all.py never copies it.
-- The helper of the tester bots (server/tools/testers.py; server/README.md "Tester bots"). chaos-ctl.sh testers start
-- copies it to data/scripts/zz_tester_helper.lua (and tester_helper_core.lua to zz_tester_helper_core.lua);
-- testers stop and cleanup remove both.
--
-- SAFETY: every action below runs ONLY for a character that has BOTH the tester storage 7102900 = 1 AND a name
-- "Tester Xxx" (ChaosTesterHelperCore.eligible). No other character is ever targeted, moved, given anything or read.
-- The helper never heals and never prevents a death: testers take real damage and really die.
--
-- What it does for a tester:
--   * targets: a tester without a target gets the nearest monster within 5 tiles as its target and faces it (the bots
--     do not parse the map); with chase on the bot walks to it
--   * supplies once (storage +1): a backpack, the plain weapon of its class kit (ChaosTestKit, no unique roll), stock
--     health and mana potions and some gold, so the potion and shop paths run
--   * its hunt spot: the first login position (storage +2/+3/+4, testers.py setup puts it on a hunt)
--   * "!tester town | depot | shop | hunt | info" (the bot says it): teleports to the temple, next to a depot locker,
--     next to an NPC of the town, back to the hunt spot; each answer is a text line
--     "[tester-helper] <kind> <json>" with the client ids and positions the bot needs (its own creature id, the potion
--     client ids, the locker, the NPC's name)
--   * "!tester bag": empties the tester's own backpack of loot (everything but the potions) and tops the potions up
--   * once a minute it counts the testers in game; the server console gets "[tester-helper] testers online: N" when
--     the count changed, and every 5 minutes anyway
--   * anomalies (one console line each, "[tester-anomaly] <json>", testers.py report reads the server log): a hit taken
--     or dealt far above the level, one hit from full health to death, a negative or absurd experience gain, an item
--     with an impossible count or attribute in the tester's backpack (checked once a minute)
-- Assumed engine API (TFS 1.4.2): CreatureEvent login/logout/healthchange/death, EventCallback onGainExperience,
-- TalkAction, addEvent, Game.getSpectators, Creature:setTarget/setDirection/teleportTo,
-- Player:getStorageValue/setStorageValue/addItem/getBankBalance/setBankBalance, ItemType:getClientId, Tile.
if not ChaosTesterHelperCore or not ChaosTesterHelperCore.eligible then
	dofile("data/scripts/zz_tester_helper_core.lua")
end
local H = ChaosTesterHelperCore

local STORE = H.STORAGE
local GROUPS, STEP_MS, RANGE = 4, 500, 5
local SUPPLIES = {{7618, 100}, {7620, 100}} -- stock health / mana potion
local GOLD = 20000 -- into the bank: NPC purchases pay from it (Chaos.pay)
local LOCKERS = {2589, 2590, 2591, 2592} -- depot_config.lua lockerIds
local SEARCH = 30 -- tiles around the temple for an NPC
local LOCKER_SEARCH = 45 -- tiles around the temple for a depot locker (its floor and the ones above and below)
-- NPCs with a trade window, tried first by "shop": the NPC nearest the temple may only talk
local TRADERS = {"Material Broker", "Loot Buyer", "Wandering Merchant"}

TesterHelper = TesterHelper or {ids = {}, step = 0, hits = {}, loginAt = {}}
local T = TesterHelper
T.hits, T.loginAt = T.hits or {}, T.loginAt or {} -- a reload keeps the table of an older version

local function storageOf(player)
	local ok, v = pcall(function() return player:getStorageValue(STORE) end)
	return ok and v or nil
end

-- THE guard: every function below starts with it
local function eligible(creature)
	if not creature or not creature:isPlayer() then
		return false
	end
	return H.eligible(creature:getName(), storageOf(creature))
end
T.eligible = eligible

local function anomaly(rule, data)
	data.rule = rule
	data.t = os.time()
	print(H.ANOMALY .. " " .. H.json(data))
end

local function tell(player, kind, data)
	player:sendTextMessage(MESSAGE_INFO_DESCR, H.encode(kind, data))
end

local function posOf(p)
	return {x = p.x, y = p.y, z = p.z}
end

local function info(player)
	local hp, mp = ItemType(7618), ItemType(7620)
	local data = {cid = player:getId(), level = player:getLevel(), pos = posOf(player:getPosition()),
		potions = {health = hp and hp:getClientId() or 0, mana = mp and mp:getClientId() or 0}}
	local ever = ChaosPotionsConfig and ChaosPotionsConfig.everfull or {}
	for _, e in ipairs(ever) do
		if (e.tier or 1) <= 1 then -- the starting flasks; the O245 tiers share their key
			local it = ItemType(e.id)
			data.potions["everfull_" .. e.key] = it and it:getClientId() or 0
		end
	end
	tell(player, "info", data)
end

local function temple(player)
	local town = player:getTown()
	return town and town:getTemplePosition() or player:getPosition()
end

-- a free tile next to `center`: the four straight neighbours first, then the corners, then two tiles out; never a
-- floor change or a teleport (the tester would land elsewhere). With `npc`: only a tile where that NPC is the one that
-- answers (no other NPC within talk range as near or nearer: data/lib/chaos_npc_focus.lua lets only the nearest answer)
local RINGS = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}, {-1, -1}, {1, -1}, {1, 1}, {-1, 1}}
for dx = -2, 2 do
	for dy = -2, 2 do
		if math.max(math.abs(dx), math.abs(dy)) == 2 then
			RINGS[#RINGS + 1] = {dx, dy}
		end
	end
end

local function nearestNpc(npc, p)
	local mine = math.max(math.abs(npc:getPosition().x - p.x), math.abs(npc:getPosition().y - p.y))
	for _, c in ipairs(Game.getSpectators(p, false, false, 3, 3, 3, 3) or {}) do
		if c:isNpc() and c:getId() ~= npc:getId() then
			local o = c:getPosition()
			if o.z == p.z and math.max(math.abs(o.x - p.x), math.abs(o.y - p.y)) <= mine then
				return false
			end
		end
	end
	return true
end

local function freeNear(center, npc, reach)
	for _, d in ipairs(RINGS) do
		if math.max(math.abs(d[1]), math.abs(d[2])) <= (reach or 2) then
			local p = Position(center.x + d[1], center.y + d[2], center.z)
			local tile = Tile(p)
			if tile and tile:getGround() and not tile:hasFlag(TILESTATE_BLOCKSOLID) and not tile:getTopCreature()
				and not tile:hasFlag(TILESTATE_FLOORCHANGE) and not tile:hasFlag(TILESTATE_TELEPORT)
				and (not npc or nearestNpc(npc, p)) then
				return p
			end
		end
	end
	return nil
end

-- did the teleport put the tester on the tile? (a tile that refuses it leaves the tester where it was, far from the
-- locker or the NPC it is to use: the bot's "There is no way.")
local function landed(player, spot)
	local here = player:getPosition()
	return here.x == spot.x and here.y == spot.y and here.z == spot.z
end

-- the nearest locker round the temple with a free tile next to it: {pos, id, stackpos, spot}
local function findLocker(origin)
	local found = {}
	for dz = -1, 1 do -- the depot is often a floor up or down from the temple
		for dx = -LOCKER_SEARCH, LOCKER_SEARCH do
			for dy = -LOCKER_SEARCH, LOCKER_SEARCH do
				local z = origin.z + dz
				local tile = z >= 0 and z <= 15 and Tile(Position(origin.x + dx, origin.y + dy, z))
				if tile then
					for _, id in ipairs(LOCKERS) do
						local item = tile:getItemById(id)
						if item then
							local ok, index = pcall(function() return tile:getThingIndex(item) end)
							found[#found + 1] = {pos = tile:getPosition(), id = id,
								d = math.max(math.abs(dx), math.abs(dy)) + 10 * math.abs(dz),
								stackpos = ok and type(index) == "number" and index >= 0 and index or 1}
						end
					end
				end
			end
		end
	end
	table.sort(found, function(x, y) return x.d < y.d end)
	for _, l in ipairs(found) do
		l.spot = freeNear(l.pos, nil, 1) -- next to it: a locker opens from an adjacent tile
		if l.spot then
			return l
		end
	end
	return nil
end

local function findNpc(origin)
	local best, bestD
	for _, c in ipairs(Game.getSpectators(origin, false, false, SEARCH, SEARCH, SEARCH, SEARCH)) do
		if c:isNpc() then
			local p = c:getPosition()
			local d = math.max(math.abs(p.x - origin.x), math.abs(p.y - origin.y))
			if not bestD or d < bestD then
				best, bestD = c, d
			end
		end
	end
	return best
end

local function huntPos(player)
	local x, y, z = player:getStorageValue(STORE + 2), player:getStorageValue(STORE + 3), player:getStorageValue(STORE + 4)
	if x > 0 and y > 0 and z >= 0 then
		return Position(x, y, z)
	end
	return nil
end

-- ---------------------------------------------------------------- the commands
local commands = {}

function commands.info(player)
	info(player)
end

function commands.town(player)
	player:teleportTo(temple(player))
	tell(player, "town", {pos = posOf(player:getPosition())})
end

function commands.hunt(player)
	local p = huntPos(player)
	if not p then
		tell(player, "hunt", {err = "no hunt spot"})
		return
	end
	player:teleportTo(p)
	tell(player, "hunt", {pos = posOf(player:getPosition())})
end

function commands.depot(player)
	local locker = findLocker(temple(player))
	local spot = locker and locker.spot
	if not spot then
		tell(player, "depot", {err = "no depot locker near the temple"})
		return
	end
	player:teleportTo(spot)
	if not landed(player, spot) then
		tell(player, "depot", {err = "the teleport next to the locker was refused", pos = posOf(player:getPosition())})
		return
	end
	local it = ItemType(locker.id)
	tell(player, "depot", {pos = posOf(player:getPosition()), locker = posOf(locker.pos), clientId = it:getClientId(),
		stackpos = locker.stackpos})
end

local function findTrader(origin)
	for _, name in ipairs(TRADERS) do
		local npc = Creature(name)
		if npc and npc:isNpc() and freeNear(npc:getPosition(), npc) then
			return npc
		end
	end
	return findNpc(origin)
end

function commands.shop(player)
	local npc = findTrader(temple(player))
	local spot = npc and freeNear(npc:getPosition(), npc)
	if not spot then
		tell(player, "shop", {err = "no NPC near the temple"})
		return
	end
	player:teleportTo(spot)
	if not landed(player, spot) then
		tell(player, "shop", {err = "the teleport next to the NPC was refused", pos = posOf(player:getPosition())})
		return
	end
	tell(player, "shop", {pos = posOf(player:getPosition()), npc = npc:getName(), npcPos = posOf(npc:getPosition())})
end

local function marks()
	return ChaosPoi and ChaosPoi.all or {}
end

-- the counts of the places `enter` knows (map marks by kind)
function commands.places(player)
	tell(player, "places", {counts = H.placeCounts(marks())})
end

-- TEST ONLY: bring this tester to a place, or give it a rift key. Only the tester itself moves and receives; an NPC
-- target must be an NPC (a player's name is refused)
function commands.enter(player, arg)
	local place = H.parsePlace(arg)
	if not place then
		tell(player, "enter", {err = "unknown place", arg = tostring(arg)})
		return
	end
	if place.kind == "rift" then
		local rift, cfg = ChaosRift, ChaosRiftConfig
		if not (rift and rift.giveKey and cfg and cfg.key) then
			tell(player, "enter", {kind = "rift", err = "no rifts on this server"})
			return
		end
		rift.giveKey(player, {tier = place.tier, mods = {}}, "Tester key")
		player:teleportTo(temple(player))
		local it = ItemType(cfg.key.itemId)
		tell(player, "enter", {kind = "rift", tier = place.tier, keyClientId = it and it:getClientId() or 0,
			pos = posOf(player:getPosition())})
		return
	end
	if place.kind == "npc" then
		local npc = Creature(place.name)
		if not npc or not npc:isNpc() then
			tell(player, "enter", {kind = "npc", err = "no such NPC", name = place.name})
			return
		end
		local spot = freeNear(npc:getPosition())
		if not spot then
			tell(player, "enter", {kind = "npc", err = "no free tile", name = place.name})
			return
		end
		player:teleportTo(spot)
		tell(player, "enter", {kind = "npc", npc = npc:getName(), npcPos = posOf(npc:getPosition()),
			pos = posOf(player:getPosition())})
		return
	end
	local mark, count = H.pickMark(marks(), place.kind, place.n)
	local spot = mark and freeNear(Position(mark.x, mark.y, mark.z))
	if not spot then
		tell(player, "enter", {kind = place.kind, err = mark and "no free tile" or "no such place", count = count})
		return
	end
	player:teleportTo(spot)
	tell(player, "enter", {kind = place.kind, name = mark.n, count = count, pos = posOf(player:getPosition())})
end

T.commands = commands

local talk = TalkAction("!tester")
function talk.onSay(player, words, param)
	if not eligible(player) or not T.present() then
		return true -- a player's words are left alone (and a stopped helper does nothing)
	end
	local cmd, arg = H.parseCommand(param)
	if not cmd or not commands[cmd] then
		tell(player, "error", {err = "unknown command", param = tostring(param)})
		return false
	end
	local ok, err = pcall(commands[cmd], player, arg)
	if not ok then
		print("[tester-helper] " .. cmd .. ": " .. tostring(err))
		tell(player, "error", {err = tostring(err), cmd = cmd})
	end
	return false
end
talk:separator(" ")
talk:register()

-- the supplies a tester keeps: id -> number (SUPPLIES)
local WANT = {}
for _, s in ipairs(SUPPLIES) do
	WANT[s[1]] = s[2]
end

-- potions topped up to their number when under half of it (a tester dies about thirty times an hour and loses some)
local function topUp(player)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		return 0
	end
	local held = {}
	for id in pairs(WANT) do
		held[id] = player:getItemCount(id)
	end
	local _, add = H.bagPlan({}, WANT, held)
	for _, a in ipairs(add) do
		bag:addItem(a.id, a.count)
	end
	return #add
end

-- TEST ONLY: empties the backpack of loot (every slot of it that is not a supply; a bag goes with what it holds) and
-- tops up the potions. Only this tester's own backpack. The bots loot and never sell, so the bag fills and every
-- pickup says "There is not enough room."
function commands.bag(player)
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		tell(player, "bag", {err = "no backpack"})
		return
	end
	local list, rows = {}, {}
	for _, item in ipairs(bag:getItems() or {}) do
		list[#list + 1] = {id = item:getId(), count = item:getCount()}
		rows[#rows + 1] = item
	end
	local remove = H.bagPlan(list, WANT, {})
	for _, i in ipairs(remove) do
		rows[i]:remove()
	end
	local ok, added = pcall(topUp, player)
	tell(player, "bag", {removed = #remove, topped = ok and added or 0})
end

-- ---------------------------------------------------------------- login: supplies once, hunt spot, info
local BACKPACK = 1988

local function supplies(player)
	if player:getStorageValue(STORE + 1) == 1 then
		return
	end
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		bag = player:addItem(BACKPACK, 1, false, 1, CONST_SLOT_BACKPACK)
	end
	local K = ChaosTestKit
	local kit = K and K.kits and K.kindFor and K.kits[K.kindFor(player:getVocation():getId())]
	for _, slot in ipairs({CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local id = kit and kit.slots and kit.slots[slot]
		if id and not player:getSlotItem(slot) then
			player:addItem(id, 1, false, 1, slot) -- the plain item: no ChaosMakeUnique
		end
	end
	for _, s in ipairs(SUPPLIES) do
		if bag then
			bag:addItem(s[1], s[2])
		else
			player:addItem(s[1], s[2])
		end
	end
	if player.setBankBalance then
		player:setBankBalance(player:getBankBalance() + GOLD)
	end
	player:setStorageValue(STORE + 1, 1)
end

local login = CreatureEvent("TesterHelperLogin")
function login.onLogin(player)
	if not eligible(player) then
		return true
	end
	player:registerEvent("TesterHelperHealth")
	player:registerEvent("TesterHelperDeath")
	T.ids[player:getId()] = true
	T.hits[player:getId()] = nil
	T.loginAt[player:getId()] = os.time()
	if not huntPos(player) then
		local p = player:getPosition()
		player:setStorageValue(STORE + 2, p.x)
		player:setStorageValue(STORE + 3, p.y)
		player:setStorageValue(STORE + 4, p.z)
	end
	pcall(supplies, player)
	pcall(topUp, player)
	local id = player:getId()
	addEvent(function()
		local p = Player(id)
		if p and eligible(p) then
			info(p)
		end
	end, 1500)
	return true
end
login:type("login")
login:register()

local logout = CreatureEvent("TesterHelperLogout")
function logout.onLogout(player)
	T.ids[player:getId()] = nil
	T.hits[player:getId()] = nil
	T.loginAt[player:getId()] = nil
	return true
end
logout:type("logout")
logout:register()

-- ---------------------------------------------------------------- anomalies
local health = CreatureEvent("TesterHelperHealth")
function health.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and eligible(creature) then
		local dmg = math.max(0, primaryDamage or 0) + math.max(0, secondaryDamage or 0)
		local hit = {kind = "taken", damage = dmg, health = creature:getHealth(), maxHealth = creature:getMaxHealth(),
			level = creature:getLevel()}
		local id = creature:getId()
		T.hits[id] = T.hits[id] or {}
		H.pushHit(T.hits[id], os.time(), {damage = dmg, by = attacker and attacker:getName() or "?"})
		local rule = H.hitAnomaly(hit)
		if rule then
			hit.who = creature:getName()
			hit.by = attacker and attacker:getName() or "?"
			hit.byLevel = attacker and attacker.getMonsterLevel and attacker:getMonsterLevel() or nil
			anomaly(rule, hit)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
health:type("healthchange")
health:register()

-- on monsters a tester hits: damage dealt by a tester (or its summon)
local dealt = CreatureEvent("TesterHelperDealt")
function dealt.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType ~= COMBAT_HEALING and attacker then
		local p = attacker
		if not p:isPlayer() and p:getMaster() then
			p = p:getMaster()
		end
		if eligible(p) then
			local dmg = math.max(0, primaryDamage or 0) + math.max(0, secondaryDamage or 0)
			local hit = {kind = "dealt", damage = dmg, level = p:getLevel()}
			local rule = H.hitAnomaly(hit)
			if rule then
				hit.who = p:getName()
				hit.target = creature:getName()
				anomaly(rule, hit)
			end
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
dealt:type("healthchange")
dealt:register()

local death = CreatureEvent("TesterHelperDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller)
	if eligible(creature) then
		local id = creature:getId()
		local started = T.loginAt[id]
		print("[tester-event] " .. H.json(H.deathRecord(T.hits[id], os.time(), {who = creature:getName(),
			level = creature:getLevel(), killer = killer and killer:getName() or "?", maxHealth = creature:getMaxHealth(),
			online = started and os.time() - started or nil})))
		T.hits[id] = nil
	end
	return true
end
death:type("death")
death:register()

local xp = EventCallback
xp.onGainExperience = function(self, source, exp, rawExp)
	if eligible(self) then
		local rule = H.xpAnomaly(self:getLevel(), exp)
		if rule then
			anomaly(rule, {who = self:getName(), level = self:getLevel(), gained = exp,
				source = source and source:getName() or "?"})
		end
	end
	return exp
end
xp:register(999)

local function scanItems(player)
	local seen = 0
	local function walk(container, depth)
		for i = 0, container:getSize() - 1 do
			local item = container:getItem(i)
			if item then
				seen = seen + 1
				local it = ItemType(item:getId())
				local attrs = {}
				for _, key in ipairs({"attack", "defense", "armor", "extradefense", "hitchance"}) do
					local ok, v = pcall(function() return item:getAttribute(key) end)
					if ok and type(v) == "number" then
						attrs[key] = v
					end
				end
				local rule = H.itemAnomaly({count = item:getCount(), stackable = it:isStackable(), attrs = attrs})
				if rule then
					anomaly(rule, {who = player:getName(), item = it:getName(), id = item:getId(), count = item:getCount()})
				end
				if depth < 3 and item:isContainer() then
					walk(item, depth + 1)
				end
			end
			if seen > 500 then
				return
			end
		end
	end
	local bp = player:getSlotItem(CONST_SLOT_BACKPACK)
	if bp and bp:isContainer() then
		walk(bp, 0)
	end
end

-- ---------------------------------------------------------------- targets
local function nearestMonster(player)
	local pos = player:getPosition()
	local list = {}
	for _, c in ipairs(Game.getSpectators(pos, false, false, RANGE, RANGE, RANGE, RANGE)) do
		if c:isMonster() then
			list[#list + 1] = {pos = c:getPosition(), health = c:getHealth(), owned = c:getMaster() ~= nil, id = c:getId(), c = c}
		end
	end
	local best = H.nearest(pos, list, RANGE)
	return best and best.c
end

local function step()
	T.step = T.step + 1
	local g = T.step % GROUPS
	for id in pairs(T.ids) do
		if id % GROUPS == g then
			local player = Player(id)
			if not player or not eligible(player) then
				T.ids[id] = nil -- gone, or not a tester: never acted on
			else
				if not player:getTarget() then
					local monster = nearestMonster(player)
					if monster then
						monster:registerEvent("TesterHelperDealt")
						player:setTarget(monster)
						player:setDirection(H.directionTo(player:getPosition(), monster:getPosition()))
					end
				end
				if T.step % 120 == g then -- every minute
					pcall(scanItems, player)
				end
			end
		end
	end
	if T.step % 120 == 0 then -- once a minute: the testers in game, on the server console
		local n = 0
		for _ in pairs(T.ids) do
			n = n + 1
		end
		local line = H.onlineLine(n, T.lastOnline, T.step / 120)
		if line then
			print(line)
		end
		T.lastOnline = n
	end
	-- testers stop removed this file: the loop ends (the server restart drops the rest of the helper)
	if T.step % 20 == 0 and not T.present() then
		T.started = false
		print("[tester-helper] stopped: " .. T.FILE .. " is gone")
		return
	end
	addEvent(step, STEP_MS)
end

T.FILE = "data/scripts/zz_tester_helper.lua"
function T.present()
	local f = io.open(T.FILE, "r")
	if f then
		f:close()
		return true
	end
	return false
end

-- the loop starts once, when the script loads (server start, or a reload of the scripts)
if not T.started then
	T.started = true
	addEvent(step, STEP_MS)
end
print("[tester-helper] running (TEST ONLY: chaos-ctl.sh testers stop removes data/scripts/zz_tester_helper*.lua)")

-- a /reload of the scripts while testers are online: pick them up again
for _, p in ipairs(Game.getPlayers and Game.getPlayers() or {}) do
	if eligible(p) then
		T.ids[p:getId()] = true
		p:registerEvent("TesterHelperHealth")
		p:registerEvent("TesterHelperDeath")
	end
end
