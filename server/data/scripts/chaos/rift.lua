-- Rifts (roadmap item 8): consumable Rift Keys open a timed instance with random modifiers.
-- Numbers: rift_config.lua. Pure logic (tested by tests/rift_test.lua): rift_core.lua. Overview: server/README.md "Rifts".
--
-- Flow
--   use a Rift Key (item 10155 "shadow orb" + action id 47401, attributes rift_tier / rift_mods) in a protection zone, out of combat,
--   not multi-clienting -> the party within partyRange (up to 4) comes along -> a free slot of the rift grid is built
--   with Game.createTile (the footprint must be empty on first use, as worldboss.lua checks) or reused, themed, 2-4 of
--   its side rooms opened -> packs from the bounty pool's level window of the tier (elites through monster_tiers.lua)
--   -> after bossAt % of the kills the boss appears -> boss dead in time: reward chest (each finisher once), maybe a
--   new key, Omen Fragments from tier 6; time up: everyone out, key lost. Shared lives (3, +1 per extra player): a
--   death inside is the normal death and costs one; the next login puts the character back at the rift's entrance;
--   the last life lost collapses the rift. Logout inside: removed from the run.
--   Omens: 60 Omen Fragments bind an Omen Key (item 32072, attribute omen_kind) that opens a guardian arena in the
--   same slot grid (every side room shut, one guardian, the same lives, timer and chest flow).
--   The key is consumed at the start; a "run in progress" marker (storages Chaos.storage.riftRun ..+4) refunds it at
--   the next login when the server stopped or crashed during the run.
--
-- Exports: ChaosRift.isInside(player), ChaosRift.lootMult(ctx) (loot_config.lua rateMult),
-- ChaosRift.onBountyPaid(player, contract) (bounty.lua), ChaosRift.createKey / giveKey.
-- Client: game_rift, extended opcode ChaosOpcodes.rift (server -> client {"action": "start"|"update"|"end", "data"}).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end
dofile("data/scripts/chaos/rift_core.lua")
ChaosRiftConfig = dofile("data/scripts/chaos/rift_config.lua")
dofile("data/lib/chaos_dark_paint.lua")

ChaosRift = ChaosRift or {}
local RF = ChaosRift
local R = ChaosRiftCore
local OPCODE = ChaosOpcodes.rift
local ST = Chaos.storage.riftRun -- +0 tier, +1..+3 packed modifiers, +4 start time

-- the dark tile set (rift_config.lua `dark`): when it is installed, the walls and hub lights switch to it and every
-- theme with a `darkStyle` is painted by ChaosDarkPaint (main ground, patches with borders, decoration); otherwise
-- the stock ids of the config are used unchanged
local function resolveDark(cfg)
	cfg.darkActive = false
	local d = cfg.dark
	if not (d and d.enabled and ChaosDarkPaint and ChaosDarkTiles) then
		return
	end
	local wall, basin = ChaosDarkTiles.id(d.wall), ChaosDarkTiles.id(d.basin)
	if not wall or not basin then
		return
	end
	local any = false
	for _, th in ipairs(cfg.themes) do
		if th.darkStyle and ChaosDarkPaint.ready(th.darkStyle) then
			th.stockGrounds = th.stockGrounds or th.grounds
			th.grounds = ChaosDarkPaint.groundIds(th.darkStyle)
			th.dark = true
			any = true
		end
	end
	if any then
		cfg.stockWallId, cfg.stockBasinId = cfg.wallId, cfg.basinId
		cfg.wallId, cfg.basinId, cfg.darkActive = wall, basin, true
	end
end

local function C()
	local c = ChaosRiftConfig
	if c.darkActive == nil then
		resolveDark(c)
	end
	return c
end

local function rand(a, b)
	return math.random(a, b)
end

RF.runs = RF.runs or {} -- slot -> run
RF.runOf = RF.runOf or {} -- player id -> run
RF.monsterRun = RF.monsterRun or {} -- monster id -> run
RF.built = RF.built or {} -- slot -> true once its tiles exist (they stay for the server's lifetime and are reused)
RF.bad = RF.bad or {} -- slot -> reason (footprint not empty)
RF.pending = RF.pending or {} -- guid -> list of {run data} rewards for finishers who were offline at the exit
RF.nextId = RF.nextId or 0
RF.echo = RF.echo or {} -- monster id -> true: Echoing Spoils copies its loot (set at death, used by onDropLoot)
RF.noRefund = RF.noRefund or {} -- guid -> true: the key of an interrupted run was spent (left without a logout event)
RF.revive = RF.revive or {} -- guid -> run: died inside with lives left; the next login puts the character back

-- ======================================================================== pool
local rawPool = dofile("data/scripts/chaos/bounty_pool.lua")
RF.poolLevel = {}
for _, e in ipairs(rawPool.hunt or {}) do
	RF.poolLevel[e.name:lower()] = e.level
end

local knownCache = {}
local function known(name)
	local k = name:lower()
	if knownCache[k] == nil then
		local ok = false
		local mt = MonsterType(name)
		if mt and not (ChaosTierConfig and ChaosTierConfig.skip and ChaosTierConfig.skip[k]) then
			local okBoss, isBoss = pcall(function() return mt:isBoss() end)
			ok = not (okBoss and isBoss)
		end
		knownCache[k] = ok
	end
	return knownCache[k]
end

-- ======================================================================== helpers
local function P(t)
	return Position(t.x, t.y, t.z)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function playerOf(creature)
	if not creature then
		return nil
	end
	if creature:isPlayer() then
		return creature
	end
	local master = creature:getMaster()
	return master and master:isPlayer() and master or nil
end

local function groundId(tile)
	local g = tile:getGround()
	if type(g) == "number" then
		return g
	end
	return g and g:getId() or nil
end

local function itemName(id)
	local it = ItemType(id)
	return it and it:getName() or tostring(id)
end

local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		rest = rest - n
	end
	return true
end

local function giveEx(player, item)
	if player:addItemEx(item, false) ~= RETURNVALUE_NOERROR then
		local inbox = player:getInbox()
		if inbox then
			inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		return true
	end
	return false
end

local function say(run, text)
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
		end
	end
end

-- ======================================================================== keys
function RF.readKey(item)
	if not item or item:getActionId() ~= C().key.actionId then
		return nil
	end
	local tier = tonumber(item:getCustomAttribute("rift_tier"))
	if not tier then
		return nil
	end
	return {tier = R.clampTier(C(), tier), mods = R.decodeMods(C(), item:getCustomAttribute("rift_mods") or "")}
end

function RF.applyKey(item, key)
	local cfg = C()
	item:setActionId(cfg.key.actionId)
	item:setCustomAttribute("rift_tier", key.tier)
	item:setCustomAttribute("rift_mods", R.encodeMods(key.mods))
	item:setAttribute(ITEM_ATTRIBUTE_NAME, R.keyName(cfg, key.tier))
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "a")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, R.describe(cfg, key))
	return item
end

function RF.createKey(key)
	local item = Game.createItem(C().key.itemId, 1)
	if item then
		RF.applyKey(item, key)
	end
	return item
end

-- returns true when the key went to the inbox (backpack full)
function RF.giveKey(player, key, why)
	local item = RF.createKey(key)
	if not item then
		return false
	end
	local inbox = giveEx(player, item)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: %s (%s).%s", why or "You received a key",
		R.keyName(C(), key.tier), #key.mods > 0 and R.encodeMods(key.mods):gsub(",", ", ") or "no modifiers",
		inbox and " It is in your inbox." or ""))
	return inbox
end

-- ======================================================================== omen fragments and keys
local function omenItemReady(id)
	local it = id and ItemType(id)
	return it ~= nil and it:getId() ~= 0
end
RF.omenItemReady = omenItemReady

-- the kind key ("bloodmoon") of an Omen Key item, or nil
function RF.readOmenKey(item)
	local o = C().omen
	if not item or item:getId() ~= o.key.id then
		return nil
	end
	local kind = item:getCustomAttribute("omen_kind")
	return R.omenKind(C(), kind) and kind or nil
end

function RF.applyOmenKey(item, kind)
	local cfg = C()
	local d = R.omenKind(cfg, kind)
	item:setCustomAttribute("omen_kind", d.key)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, R.omenKeyName(cfg, d.key))
	item:setAttribute(ITEM_ATTRIBUTE_ARTICLE, "an")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, string.format("It hums with the name %s. Opens the %s guardian's arena " ..
		"(level %d+, %d minutes). Use it in a protection zone; your party within %d sqm comes along.", d.boss, d.name,
		cfg.omen.minLevel, math.floor(cfg.omen.timeLimit / 60), cfg.partyRange))
	return item
end

-- gives an Omen Key of `kind` (nil: a random kind); returns the kind or nil
function RF.giveOmenKey(player, kind, why)
	local cfg = C()
	if not omenItemReady(cfg.omen.key.id) then
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "Omen Keys are not installed on this server (tools/install_omens.py).")
		return nil
	end
	kind = kind or cfg.omen.kinds[rand(1, #cfg.omen.kinds)].key
	local item = Game.createItem(cfg.omen.key.id, 1)
	if not item then
		return nil
	end
	RF.applyOmenKey(item, kind)
	local inbox = giveEx(player, item)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: %s.%s", why or "You received an Omen Key",
		R.omenKeyName(cfg, kind), inbox and " It is in your inbox." or ""))
	return kind
end

-- ======================================================================== crash refund marker
local function setMarker(player, key)
	player:setStorageValue(ST, key.omen and R.markerTier(C(), key.omen) or key.tier)
	for i = 1, 3 do
		player:setStorageValue(ST + i, key.mods[i] and R.packMod(C(), key.mods[i]) or 0)
	end
	player:setStorageValue(ST + 4, os.time())
	player:save()
end

local function clearMarker(player)
	if player:getStorageValue(ST) > 0 then
		for i = 0, 4 do
			player:setStorageValue(ST + i, 0)
		end
		player:save()
	end
end

local function refundMarker(player)
	local tier = player:getStorageValue(ST)
	if tier <= 0 then
		return false
	end
	if RF.noRefund[player:getGuid()] or RF.runOf[player:getId()] or RF.revive[player:getGuid()] then
		RF.noRefund[player:getGuid()] = nil
		clearMarker(player)
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "You left your rift: its key is spent.")
		return false
	end
	local mods = {}
	for i = 1, 3 do
		local m = R.unpackMod(C(), player:getStorageValue(ST + i))
		if m then
			mods[#mods + 1] = m
		end
	end
	for i = 0, 4 do
		player:setStorageValue(ST + i, 0)
	end
	local omen = R.markerOmen(C(), tier)
	if omen then
		RF.giveOmenKey(player, omen, "Your last omen arena was interrupted by a server restart, so its key is returned")
	else
		RF.giveKey(player, {tier = R.clampTier(C(), tier), mods = mods},
			"Your last rift was interrupted by a server restart, so its key is returned")
	end
	player:save()
	return true
end
RF.refundMarker = refundMarker

-- ======================================================================== instance
local allGrounds
local function groundSet()
	if not allGrounds then
		allGrounds = {}
		for _, t in ipairs(C().themes) do
			for _, id in ipairs(t.grounds) do
				allGrounds[id] = true
			end
		end
	end
	return allGrounds
end

local function keepIds()
	return {[C().wallId] = true, [C().basinId] = true}
end

local function placeItem(pos, id)
	local tile = Tile(pos)
	if tile and not tile:getItemById(id) then
		return Game.createItem(id, 1, pos)
	end
	return tile and tile:getItemById(id)
end

-- builds the slot on first use (refused when a tile of the footprint exists and is not ours); returns L or nil, reason
local function buildSlot(slot)
	local cfg = C()
	local L = R.layout(cfg, slot)
	if RF.built[slot] then
		return L
	end
	local ours = groundSet()
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, t in ipairs(list) do
			local tile = Tile(P(t))
			if tile and (not ours[groundId(tile) or 0] or (tile.getHouse and tile:getHouse())) then
				return nil, string.format("tile %d,%d,%d already exists in the map", t.x, t.y, t.z)
			end
		end
	end
	local base = cfg.themes[1].grounds[1]
	for _, list in ipairs({L.floorList, L.wallList}) do
		for _, t in ipairs(list) do
			local pos = P(t)
			local tile = Game.createTile(pos, true)
			if tile and not tile:getGround() then
				Game.createItem(base, 1, pos)
			end
		end
	end
	for _, t in ipairs(L.wallList) do
		placeItem(P(t), cfg.wallId)
	end
	for _, t in ipairs(L.basins) do
		placeItem(P(t), cfg.basinId)
	end
	RF.built[slot] = true
	return L
end

-- monsters and loose items (corpses, drops, fields, the chest) on every floor tile of the slot
local function cleanSlot(L)
	local keep = keepIds()
	for _, t in ipairs(L.floorList) do
		local tile = Tile(P(t))
		if tile then
			for _, c in ipairs(tile:getCreatures() or {}) do
				if c:isMonster() then
					RF.monsterRun[c:getId()] = nil
					c:remove()
				end
			end
			for _, item in ipairs(tile:getItems() or {}) do
				if not keep[item:getId()] then
					item:remove()
				end
			end
		end
	end
end

local function theme(L, th, open)
	local cfg = C()
	local doorTiles = {}
	for _, d in ipairs(R.DIRS) do
		for _, t in ipairs(L.doors[d.name]) do
			doorTiles[t.x .. "," .. t.y] = true
		end
	end
	if th.dark then
		local reserved = {L.start, L.bossSpawn}
		for _, b in ipairs(L.basins) do
			reserved[#reserved + 1] = b
		end
		for _, d in ipairs(R.DIRS) do
			for _, t in ipairs(L.doors[d.name]) do
				reserved[#reserved + 1] = t
			end
		end
		ChaosDarkPaint.apply(ChaosDarkPaint.plan(L.floorList, th.darkStyle, rand, {walls = L.walls, reserved = reserved}),
			L.center.z)
	end
	for _, t in ipairs(th.dark and {} or L.floorList) do
		local tile = Tile(P(t))
		if tile then
			local want = th.grounds[rand(1, #th.grounds)]
			local g = tile:getGround()
			if g and type(g) ~= "number" then
				if g:getId() ~= want then
					g:transform(want)
				end
			elseif not g then
				Game.createItem(want, 1, P(t))
			end
		end
	end
	local isOpen = {}
	for _, name in ipairs(open) do
		isOpen[name] = true
	end
	for _, d in ipairs(R.DIRS) do
		for _, t in ipairs(L.doors[d.name]) do
			local tile = Tile(P(t))
			local wall = tile and tile:getItemById(cfg.wallId)
			if isOpen[d.name] then
				if wall then
					wall:remove()
				end
			elseif tile and not wall then
				Game.createItem(cfg.wallId, 1, P(t))
			end
		end
	end
end

-- ======================================================================== HUD
local function hudData(run)
	local mods = {}
	for _, m in ipairs(run.key.mods) do
		local def = R.modDef(C(), m.key)
		mods[#mods + 1] = {name = def and def.name or m.key, text = R.modText(C(), m), boon = def and def.boon or nil,
			tier = def and R.modTier(def, m.value) or nil}
	end
	-- live lines of the map modifiers (coffer, goblin, twin guardians)
	local notes = {}
	local cf = run.coffer
	if cf then
		if cf.state == "closed" then
			notes[#notes + 1] = string.format("A sealed coffer waits in the %s room.", cf.room == "hub" and "central" or cf.room)
		elseif cf.state == "guarded" then
			notes[#notes + 1] = string.format("Coffer guards: %d left.", cf.waveLeft)
		elseif cf.state == "open" then
			notes[#notes + 1] = "The coffer is open."
		end
	end
	if run.goblin == "out" and not Monster(run.goblinId) then
		run.goblin = "gone" -- slain or escaped
	end
	if run.goblin == "out" then
		notes[#notes + 1] = "A Treasure Goblin is loose!"
	end
	if (run.guardians or 1) > 1 and run.boss == "alive" then
		notes[#notes + 1] = string.format("Guardians left: %d.", run.guardians - (run.guardiansKilled or 0))
	end
	local waiting = 0
	for _ in pairs(run.revive or {}) do
		waiting = waiting + 1
	end
	if waiting > 0 and run.state == "running" then
		notes[#notes + 1] = string.format("%d fallen player%s may still return.", waiting, waiting == 1 and "" or "s")
	end
	return {tier = run.key.tier, theme = run.themeName, left = R.timeLeft(run, os.time()), limit = run.limit or C().timeLimit,
		total = run.total, killed = run.killed, bossAt = run.bossAt, boss = run.boss, state = run.state,
		bossName = run.plan.boss, mods = mods, bonus = run.bonus, notes = notes, lives = run.lives,
		livesMax = run.livesMax, omen = run.omen and R.omenKind(C(), run.omen).name or nil,
		title = run.omen and ("Omen - " .. R.omenKind(C(), run.omen).name) or nil}
end

local function sendHud(run, action, player)
	local data = hudData(run)
	if player then
		Chaos.send(player, OPCODE, action, data)
		return
	end
	for id in pairs(run.players) do
		local p = Player(id)
		if p then
			Chaos.send(p, OPCODE, action, data)
		end
	end
end

-- ======================================================================== withering (no health regeneration)
local function wither(player, entry)
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if not cond then
		entry.withered = false -- ours ran out; food eaten later creates a normal one, converted on the next tick
		return
	end
	if entry.withered then
		return
	end
	local ticks = cond:getTicks()
	player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	local voc = player:getVocation()
	local c = Condition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	c:setTicks(ticks)
	c:setParameter(CONDITION_PARAM_HEALTHGAIN, 0)
	c:setParameter(CONDITION_PARAM_HEALTHTICKS, 60000)
	c:setParameter(CONDITION_PARAM_MANAGAIN, voc:getManaGainAmount())
	c:setParameter(CONDITION_PARAM_MANATICKS, voc:getManaGainTicks() * 1000)
	player:addCondition(c)
	entry.withered = true
end

local function unwither(player, entry)
	if not entry.withered then
		return
	end
	entry.withered = false
	local cond = player:getCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
	if cond then
		local seconds = math.floor(cond:getTicks() / 1000)
		player:removeCondition(CONDITION_REGENERATION, CONDITIONID_DEFAULT)
		if seconds > 0 then
			player:feed(seconds)
		end
	end
end

-- ======================================================================== run end
local finishExit

local function removePlayer(run, id, mode)
	local entry = run.players[id]
	if not entry then
		return
	end
	run.players[id] = nil
	RF.runOf[id] = nil
	local player = Player(id)
	if player then
		unwither(player, entry)
		player:unregisterEvent("ChaosRiftPlayerDeath")
		player:unregisterEvent("ChaosRiftPlayerHit")
		player:unregisterEvent("ChaosRiftPlayerMana")
		if mode == "out" or mode == "logout" then
			player:teleportTo(entry.entry)
			player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
		end
		if mode ~= "logout" then
			local running = run.state == "running"
			local text = running and (mode == "dead" and "You fell in the rift." or "You left the rift.") or run.endText
			if mode == "dead" and running and RF.revive[entry.guid] == run then
				text = string.format("You fell: %d %s left. You return at the rift's entrance when you log in again.",
					run.lives, run.lives == 1 and "life" or "lives")
			end
			Chaos.send(player, OPCODE, "end", {result = running and "left" or run.state, text = text})
		end
		if entry.guid == run.openerGuid then
			clearMarker(player) -- the key is spent once its owner leaves the run (or the run ended)
		end
	elseif entry.guid == run.openerGuid then
		-- gone without a logout event (lost connection, kicked): no refund at the next login while this server runs;
		-- only a crash or a restart (which empties this table) refunds the key
		RF.noRefund[entry.guid] = true
	end
	-- a fallen player who may still return keeps a running rift open (until the time runs out)
	if next(run.players) == nil and not run.ended and not (run.state == "running" and next(run.revive or {}) ~= nil) then
		if run.state == "running" then
			run.state = "failed"
			run.endText = "Everyone left the rift."
		end
		finishExit(run)
	end
end
RF._removePlayer = removePlayer

finishExit = function(run)
	if run.ended then
		return
	end
	run.ended = true
	-- unclaimed chest shares: delivered now (online) or at the next login
	if run.state == "success" then
		for guid, f in pairs(run.finishers or {}) do
			if not run.claimed[guid] then
				run.claimed[guid] = true
				local p = Player(f.name)
				if p and p:getGuid() == guid then
					RF.deliver(p, run, true)
				else
					RF.pending[guid] = RF.pending[guid] or {}
					table.insert(RF.pending[guid], {tier = run.key.tier, bonus = run.bonus, types = run.typeNames, boss = run.plan.boss,
						omen = run.omen})
				end
			end
		end
	end
	for guid in pairs(run.revive or {}) do
		if RF.revive[guid] == run then
			RF.revive[guid] = nil
		end
	end
	run.revive = {}
	for id in pairs(run.players) do
		removePlayer(run, id, "out")
	end
	for mid, r in pairs(RF.monsterRun) do
		if r == run then
			RF.monsterRun[mid] = nil
		end
	end
	cleanSlot(run.L)
	if RF.runs[run.slot] == run then
		RF.runs[run.slot] = nil
	end
	print(string.format("[ChaosRift] run %d (slot %d, tier %d) ended: %s", run.id, run.slot, run.key.tier, run.state))
end

local function fail(run, text)
	run.state = "failed"
	run.endText = text .. (run.omen and " The arena collapses and the key is lost." or " The rift collapses and the key is lost.")
	say(run, run.endText)
	finishExit(run)
end
RF._fail = fail

-- ======================================================================== rewards
-- every unique of ChaosUniqueItems without its monster list (the omen guardians' pool); rebuilt when the list changes
local omenUniqueCache, omenUniqueFrom
local function omenUniques()
	if omenUniqueFrom ~= ChaosUniqueItems then
		omenUniqueFrom = ChaosUniqueItems
		omenUniqueCache = {}
		for k, e in pairs(ChaosUniqueItems or {}) do
			if type(e) == "table" then
				local c = {}
				for f, v in pairs(e) do
					c[f] = v
				end
				c.monsters = nil
				c.name = c.name or (type(k) == "string" and k) or nil
				omenUniqueCache[#omenUniqueCache + 1] = c
			end
		end
	end
	return omenUniqueCache
end

-- the item level of a rift's chest and coffer gear (chaos_item_mods.lua M.sourceLevel): the level of the rift's boss
-- (its hunting level, else the top of the tier's level window), the rift tier and the Omen bonus
function RF.itemLevel(tier, bossName, omen, kind)
	local M = ChaosItemMods
	if not M then
		return nil
	end
	local level = bossName and RF.poolLevel[tostring(bossName):lower()] or R.tierInfo(C(), tier).pick[2]
	return M.sourceLevel({monsterLevel = level, tier = kind or "boss", riftTier = tier, omen = omen and true or false})
end

local function riftGear(id, rarity, ilvl)
	if ChaosCrafting and ChaosCrafting.createItem then
		return ChaosCrafting.createItem(id, rarity, ilvl)
	end
	return Game.createItem(id, 1)
end

-- one finisher's chest. auto = true when it was not opened before the exit
function RF.deliver(player, run, auto)
	local cfg = C()
	local data = run.key and {tier = run.key.tier, bonus = run.bonus, types = run.typeNames, boss = run.plan.boss,
		omen = run.omen} or run
	local r = data.omen and R.omenReward(cfg) or R.reward(cfg, data.tier, data.bonus, rand)
	local asTier = data.omen and cfg.omen.reward.asTier or data.tier
	local inbox = false
	if r.gold > 0 then
		player:setBankBalance(player:getBankBalance() + r.gold)
	end
	inbox = giveStack(player, cfg.reward.items.chaos, r.chaos) or inbox
	inbox = giveStack(player, cfg.reward.items.divine, r.divine) or inbox
	local found = {}
	local stacks, order = {}, {} -- non-gear drops merged per item id
	local function stack(id, count)
		if not stacks[id] then
			stacks[id] = 0
			order[#order + 1] = id
		end
		stacks[id] = stacks[id] + count
	end
	local L = ChaosLoot
	if L then
		local itemFind = L.itemFindMult(player)
		local ctx = {tier = r.lootTier, player = player, level = 0, itemFind = itemFind}
		-- each roll draws ONE entry of a random rift monster's loot table, weighted by its loot chance
		for _ = 1, r.rolls do
			local name = data.types[rand(1, #data.types)]
			local mt = MonsterType(name)
			local loot = mt and mt:getLoot() or {}
			local rows = {}
			for _, e in ipairs(loot) do
				if e.itemId and (e.chance or 0) > 0 then
					rows[#rows + 1] = {e, e.chance}
				end
			end
			local e = R.weighted(rows, rand)
			if e then
				if L.isGearId(e.itemId) then
					local rarity = L.upgradeRarity(r.lootTier, L.stockRarity(), itemFind * r.rarityMult)
					local item = riftGear(e.itemId, rarity, RF.itemLevel(asTier, data.boss, data.omen))
					if item then
						inbox = giveEx(player, item) or inbox
						local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names
						found[#found + 1] = (rarity > 0 and ("[" .. (names and names[rarity] or rarity) .. "] ") or "") .. itemName(e.itemId)
					end
				else
					local maxC = math.max(e.maxCount or 1, e.minCount or 1)
					stack(e.itemId, math.max(1, math.floor(rand(e.minCount or 1, maxC) * r.countMult)))
				end
			end
		end
		for _, c in ipairs(L.rollCurrency(r.lootTier, ctx)) do
			stack(c.id, c.count)
		end
		-- gems (data/lib/chaos_gems_config.lua rewards.rift: count and quality by the rift tier)
		for _, g in ipairs(ChaosGems and ChaosGems.rewardGems("rift", {tier = asTier}, rand) or {}) do
			stack(g.id, g.count)
		end
		-- spell support runes (data/lib/chaos_supports_config.lua rewards.rift)
		for _, g in ipairs(ChaosSupports and ChaosSupports.rewardRunes("rift", {tier = asTier}, rand) or {}) do
			stack(g.id, g.count)
		end
		local uniques = {}
		if data.omen then
			-- the guardian: uniqueRolls rolls at the boss tier over every unique, x uniqueFind
			for _ = 1, r.uniqueRolls do
				for _, e in ipairs(L.rollUniques("boss", data.boss, 0, itemFind * r.rarityMult * r.uniqueFind, omenUniques(),
						player)) do
					uniques[#uniques + 1] = e
				end
			end
		else
			uniques = L.rollUniques(r.lootTier, data.boss, 0, itemFind * r.rarityMult)
		end
		for _, e in ipairs(uniques) do
			local item = Game.createItem(e.id, 1)
			if item then
				if ChaosMakeUnique then
					ChaosMakeUnique(item)
				end
				inbox = giveEx(player, item) or inbox
				found[#found + 1] = "{" .. e.name .. "}"
			end
		end
	end
	-- Omen Fragments from a sealed rift of omen.minTier or more
	local frags = not data.omen and R.omenFragments(cfg, data.tier, data.bonus, rand) or 0
	if frags > 0 and omenItemReady(cfg.omen.fragment.id) then
		stack(cfg.omen.fragment.id, frags)
	end
	for _, id in ipairs(order) do
		local n = stacks[id]
		if L and not L.isStackableId(id) then
			for _ = 1, n do
				local item = Game.createItem(id, 1)
				if item then
					inbox = giveEx(player, item) or inbox
				end
			end
		else
			inbox = giveStack(player, id, n) or inbox
		end
		found[#found + 1] = (n > 1 and (n .. "x ") or "") .. itemName(id)
	end
	local list = table.concat(found, ", ", 1, math.min(#found, 25)) .. (#found > 25 and (" and " .. (#found - 25) .. " more") or "")
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("%s: %d gold to your bank, %d Chaos Orb%s, %d Divine Orb%s%s%s.%s",
		auto and ((data.omen and "Guardian's reward" or "Rift reward") .. " (the chest was not opened, it was sent to you)")
			or (data.omen and "Guardian's chest" or "Rift chest"),
		r.gold, r.chaos, r.chaos == 1 and "" or "s", r.divine, r.divine == 1 and "" or "s",
		#found > 0 and ", " or "", list, inbox and " Your backpack was full: the rest is in your inbox." or ""))
	player:getPosition():sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	return r, found
end

local function success(run, pos)
	local cfg = C()
	run.endText = string.format(run.omen and "The guardian falls! Open its chest within %d seconds."
		or "The rift is sealed! Open the chest within %d seconds.", cfg.exitDelay)
	-- what is left of the rift dies with it
	for mid, r in pairs(RF.monsterRun) do
		if r == run then
			RF.monsterRun[mid] = nil
			local m = Monster(mid)
			if m then
				m:getPosition():sendMagicEffect(CONST_ME_POFF)
				m:remove()
			end
		end
	end
	RF.cofferOnSeal(run)
	run.finishers, run.claimed = {}, {}
	-- fallen players who could still return count as finishers (their share comes at the exit or the next login)
	for guid, f in pairs(run.revive or {}) do
		run.finishers[guid] = {name = f.name}
	end
	for id, e in pairs(run.players) do
		run.finishers[e.guid] = {name = e.name}
		if run.omen then
			if ChaosAchievements and ChaosAchievements.progress then
				local p = Player(id)
				pcall(ChaosAchievements.progress, p, "omen_kills", 1)
				pcall(ChaosAchievements.progress, p, "omen_" .. run.omen, 1)
			end
		elseif ChaosLeaderboard and ChaosLeaderboard.record then
			pcall(ChaosLeaderboard.record, "rift", Player(id) or {guid = e.guid, name = e.name}, run.key.tier) -- weekly Rifts board
		end
	end
	-- the chest (on the boss's tile, or the hub centre)
	local chestPos = pos or P(run.L.bossSpawn)
	run.chestPos = chestPos
	local chest = Game.createItem(cfg.chest.itemId, 1, chestPos)
	if chest then
		chest:setActionId(cfg.chest.actionId)
		chest:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, run.omen and "The guardian's hoard. Every finisher may open it once."
			or "The spoils of the rift. Every finisher may open it once.")
		chestPos:sendMagicEffect(CONST_ME_FIREWORK_RED)
	end
	-- the next key: to the player who used the key, else a random finisher
	local drop = not run.omen and R.rollKeyDrop(cfg, run.key.tier, #run.key.mods, rand) or nil
	if drop then
		local target
		for id, e in pairs(run.players) do
			if e.guid == run.openerGuid then
				target = Player(id)
			end
		end
		if not target then
			local ids = {}
			for id in pairs(run.players) do
				ids[#ids + 1] = id
			end
			target = #ids > 0 and Player(ids[rand(1, #ids)]) or nil
		end
		if target then
			RF.giveKey(target, drop, drop.tier > run.key.tier and "The rift leaves a stronger key behind" or "The rift leaves a key behind")
			if drop.tier > run.key.tier then
				say(run, string.format("%s found a %s!", target:getName(), R.keyName(cfg, drop.tier)))
			end
		end
	end
	local secs = os.time() - run.startTime
	if run.omen then
		say(run, string.format("The %s guardian falls in %d:%02d. %s", R.omenKind(cfg, run.omen).name, math.floor(secs / 60),
			secs % 60, run.endText))
	else
		say(run, string.format("Rift tier %d sealed in %d:%02d. %s", run.key.tier, math.floor(secs / 60), secs % 60, run.endText))
	end
	sendHud(run, "update")
	for id, e in pairs(run.players) do
		Chaos.send(Player(id), OPCODE, "end", {result = "success", text = run.endText, exitIn = cfg.exitDelay})
		if e.guid == run.openerGuid then
			clearMarker(Player(id))
		end
	end
	addEvent(function(slot, rid)
		local r = RF.runs[slot]
		if r and r.id == rid and not r.ended then
			finishExit(r)
		end
	end, cfg.exitDelay * 1000, run.slot, run.id)
end

-- ======================================================================== spawning
local function randomIn(rect, margin)
	margin = margin or 1
	return {x = rand(rect.x1 + margin, rect.x2 - margin), y = rand(rect.y1 + margin, rect.y2 - margin), z = rect.z}
end

local function spawnOne(run, name, pos, tier, boss)
	local m = Game.createMonster(name, P(pos), true, false) or Game.createMonster(name, P(pos), true, true)
	if not m then
		return nil
	end
	local base = m:getMaxHealth()
	if tier and ChaosApplyTier then
		ChaosApplyTier(m, tier)
	end
	local hp
	if boss and run.omen then
		hp = math.floor(base * R.omenHealthMult(C(), run.size))
	elseif boss then
		hp = math.floor(base * R.guardianHealthMult(C(), run.fx, run.size)) -- + Dread Guardian, Twin Guardians share
	else
		hp = math.floor(m:getMaxHealth() * run.fx.health)
	end
	if hp ~= m:getMaxHealth() and hp > 0 then
		m:setMaxHealth(hp)
		m:setHealth(hp)
	end
	if run.fx.speed ~= 0 then
		m:changeSpeed(run.fx.speed)
	end
	m:registerEvent("ChaosRiftMonsterDeath")
	m:registerEvent("ChaosRiftMonsterHealth")
	RF.monsterRun[m:getId()] = run
	return m
end

local function spawnPacks(run)
	local spawned = 0
	local hubNorth = {x1 = run.L.hub.x1, y1 = run.L.hub.y1, x2 = run.L.hub.x2, y2 = run.L.center.y - 2, z = run.L.center.z}
	for _, pack in ipairs(run.plan.packs) do
		local rect = pack.room == "hub" and hubNorth or run.L.rooms[pack.room].rect
		rect = {x1 = rect.x1, y1 = rect.y1, x2 = rect.x2, y2 = rect.y2, z = run.L.center.z}
		local center = randomIn(rect, 2)
		local spread = C().packs.spread
		for k = 1, pack.count do
			local pos = {x = center.x + rand(-spread, spread), y = center.y + rand(-spread, spread), z = center.z}
			if spawnOne(run, pack.name, pos, pack.elites[k] or nil, false) then
				spawned = spawned + 1
			end
		end
	end
	return spawned
end

local function spawnBoss(run)
	local cfg = C()
	run.bossIds = run.bossIds or {}
	local first
	for i = 1, run.guardians or 1 do
		local at = run.L.bossSpawn
		if i > 1 then
			at = {x = at.x + cfg.twin.offset, y = at.y, z = at.z}
		end
		local m = spawnOne(run, run.plan.boss, at, not run.omen and cfg.boss.tier or nil, true)
		if m then
			run.bossIds[m:getId()] = true
			run.bossId = run.bossId or m:getId()
			first = first or m
			P(at):sendMagicEffect(CONST_ME_MORTAREA)
		end
	end
	if not first and run.omen then
		print("[ChaosRift] omen guardian " .. tostring(run.plan.boss) .. " could not be created; the key is returned")
		for _, e in pairs(run.players) do
			if e.guid == run.openerGuid and Player(e.id) then
				RF.giveOmenKey(Player(e.id), run.omen, "The guardian did not answer, so your key is returned")
			end
		end
		run.omen = nil
		fail(run, "The guardian did not answer.")
		return
	end
	if not first then
		print("[ChaosRift] boss " .. tostring(run.plan.boss) .. " could not be created; the rift counts as sealed")
		run.boss = "alive"
		run.guardians, run.guardiansKilled = 1, 0
		if R.onBossKilled(run, os.time()) == "success" then
			success(run, nil)
		end
		return
	end
	local made = 0
	for _ in pairs(run.bossIds) do
		made = made + 1
	end
	run.guardians = made -- a twin that could not be created does not have to be killed
	if run.omen then
		say(run, string.format("%s answers the omen!", first:getName()))
	elseif made > 1 then
		say(run, string.format("Twin guardians %s tear through the veil!", first:getName()))
	else
		say(run, string.format("The rift guardian %s tears through the veil!", first:getName()))
	end
	sendHud(run, "update")
end

-- ======================================================================== map modifiers
-- a free floor tile in a room rect (nil after a few tries)
local function freeTileIn(rect, z, margin)
	for _ = 1, 20 do
		local p = randomIn({x1 = rect.x1, y1 = rect.y1, x2 = rect.x2, y2 = rect.y2, z = z}, margin or 1)
		local tile = Tile(P(p))
		if tile and tile:getGround() and tile:getCreatureCount() == 0 and not tile:getItemById(C().wallId)
				and not tile:getItemById(C().basinId) and tile:getTopDownItem() == nil then
			return p
		end
	end
	return nil
end

local function roomRect(run, room)
	if room == "hub" or not run.L.rooms[room] then
		return run.L.hub
	end
	return run.L.rooms[room].rect
end

-- Gilded Trail: a Treasure Goblin (treasure_goblin.lua) in a random open room
local function spawnGoblin(run)
	run.goblin = "tried"
	if not (ChaosTreasureGoblin and ChaosTreasureGoblin.spawn) then
		return
	end
	local rooms = {"hub"}
	for _, r in ipairs(run.rooms) do
		rooms[#rooms + 1] = r
	end
	local pos = freeTileIn(roomRect(run, rooms[rand(1, #rooms)]), run.L.center.z, 2)
	if not pos then
		return
	end
	local level = RF.poolLevel[run.plan.boss:lower()] or R.tierInfo(C(), run.key.tier).pick[2]
	local ok, m = pcall(ChaosTreasureGoblin.spawn, P(pos), {level = level, name = run.plan.boss})
	if ok and m then
		run.goblin = "out"
		run.goblinId = m:getId()
		say(run, "A Treasure Goblin slips out of the rift with its hoard. Catch it before it escapes!")
	end
end

-- Sealed Coffer: placed at the start of the run
local function placeCoffer(run)
	local cfg = C()
	local room = run.plan.coffer
	local pos = room and freeTileIn(roomRect(run, room), run.L.center.z, 2)
	if not pos then
		return
	end
	local item = Game.createItem(cfg.coffer.itemId, 1, P(pos))
	if item then
		item:setActionId(cfg.coffer.actionId)
		item:setAttribute(ITEM_ATTRIBUTE_NAME, "sealed coffer")
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "A coffer sealed by the rift. Breaking the seal wakes its guards.")
		run.coffer = {state = "closed", room = room, pos = pos, waveLeft = 0, wave = {}}
	end
end

local function cofferItem(run)
	local tile = run.coffer and Tile(P(run.coffer.pos))
	return tile and tile:getItemById(C().coffer.itemId) or nil
end

-- rolls one item of a random rift monster's loot table (as the reward chest does) into the container
local function rollInto(container, types, lootTier, itemFind, rarityMult, countMult, found, ilvl)
	local L = ChaosLoot
	if not L then
		return
	end
	local mt = MonsterType(types[rand(1, #types)])
	local rows = {}
	for _, e in ipairs(mt and mt:getLoot() or {}) do
		if e.itemId and (e.chance or 0) > 0 then
			rows[#rows + 1] = {e, e.chance}
		end
	end
	local e = R.weighted(rows, rand)
	if not e then
		return
	end
	if L.isGearId(e.itemId) then
		local rarity = L.upgradeRarity(lootTier, L.stockRarity(), itemFind * rarityMult)
		local item = riftGear(e.itemId, rarity, ilvl)
		if item and container:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT) == RETURNVALUE_NOERROR then
			found[#found + 1] = itemName(e.itemId)
		end
	else
		local maxC = math.max(e.maxCount or 1, e.minCount or 1)
		local n = math.max(1, math.floor(rand(e.minCount or 1, maxC) * countMult))
		if not L.isStackableId(e.itemId) then
			n = math.min(n, 3)
		end
		for _ = 1, L.isStackableId(e.itemId) and 1 or n do
			container:addItem(e.itemId, L.isStackableId(e.itemId) and math.min(n, 100) or 1, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
		found[#found + 1] = itemName(e.itemId)
	end
end

local function openCoffer(run)
	local cfg = C()
	local cf = run.coffer
	local item = cofferItem(run)
	cf.state = "open"
	if not item or not item:isContainer() then
		return
	end
	local r = R.cofferLoot(cfg, run.key.tier, run.bonus, rand)
	for _, c in ipairs(R.coins(r.gold)) do
		item:addItem(c[1], c[2], INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	if r.chaos > 0 then
		item:addItem(cfg.reward.items.chaos, r.chaos, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	if r.divine > 0 then
		item:addItem(cfg.reward.items.divine, r.divine, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
	end
	local found = {}
	for _ = 1, r.rolls do
		rollInto(item, run.typeNames, r.lootTier, 1, r.rarityMult, r.countMult, found,
			RF.itemLevel(run.key.tier, nil, false, "legendary"))
	end
	item:setAttribute(ITEM_ATTRIBUTE_NAME, "opened coffer")
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "The seal is broken. Its spoils are free for the taking.")
	P(cf.pos):sendMagicEffect(CONST_ME_FIREWORK_YELLOW)
	say(run, string.format("The coffer's seal breaks: %d gold, %d Chaos Orb%s, %d Divine Orb%s and %d more item%s inside.",
		r.gold, r.chaos, r.chaos == 1 and "" or "s", r.divine, r.divine == 1 and "" or "s", #found, #found == 1 and "" or "s"))
end
RF._openCoffer = openCoffer

local function wakeCoffer(run, player)
	local cfg = C()
	local cf = run.coffer
	local n = R.cofferWaveSize(cfg, run.size)
	local spread = cfg.coffer.wave.spread
	cf.state, cf.waveLeft, cf.wave = "guarded", 0, {}
	for _ = 1, n do
		local pos = {x = cf.pos.x + rand(-spread, spread), y = cf.pos.y + rand(-spread, spread), z = cf.pos.z}
		local tierName = R.eliteTier(cfg, run.fx, run.key.tier, rand)
		if not tierName or tierName == "magic" then
			tierName = cfg.coffer.waveTier
		end
		local m = spawnOne(run, run.typeNames[rand(1, #run.typeNames)], pos, tierName, false)
		if m then
			cf.wave[m:getId()] = true
			cf.waveLeft = cf.waveLeft + 1
		end
	end
	P(cf.pos):sendMagicEffect(CONST_ME_MORTAREA)
	say(run, string.format("%s breaks the coffer's seal: %d guards answer!", player:getName(), cf.waveLeft))
	if cf.waveLeft == 0 then
		openCoffer(run)
	end
	sendHud(run, "update")
end

-- the coffer at the seal of the rift: a woken one opens (its guards vanished with the rift), an untouched one crumbles
function RF.cofferOnSeal(run)
	local cf = run.coffer
	if not cf then
		return
	end
	if cf.state == "guarded" then
		openCoffer(run)
	elseif cf.state == "closed" then
		cf.state = "gone"
		local item = cofferItem(run)
		if item then
			P(cf.pos):sendMagicEffect(CONST_ME_POFF)
			item:remove()
		end
	end
end

function RF.useCoffer(player, item)
	local slot = R.slotOfPos(C(), item:getPosition())
	local run = slot and RF.runs[slot]
	local cf = run and run.coffer
	if not cf or run.ended or not run.players[player:getId()] then
		player:sendCancelMessage("The coffer does not answer you.")
		return true
	end
	if cf.state == "closed" then
		if run.state ~= "running" then
			player:sendCancelMessage("The coffer's seal has gone cold.")
			return true
		end
		wakeCoffer(run, player)
		return true
	elseif cf.state == "guarded" then
		player:sendCancelMessage(string.format("The coffer is still sealed: %d guard%s left.", cf.waveLeft,
			cf.waveLeft == 1 and "" or "s"))
		return true
	end
	return false -- open: the engine opens the container
end

-- Cinderdeath: the burst of a slain monster hits the players next to it after a short delay
local function cinderBurst(run, pos, maxHealth)
	local cfg = C()
	local dmg = R.cinderDamage(cfg, maxHealth, run.fx.cinder, run.key.tier)
	if dmg <= 0 then
		return
	end
	pos:sendMagicEffect(CONST_ME_HITBYFIRE)
	local rid, slot = run.id, run.slot
	addEvent(function(p, amount)
		local r = RF.runs[slot]
		if not r or r.id ~= rid or r.ended or r.state ~= "running" then
			return
		end
		local at = Position(p.x, p.y, p.z)
		at:sendMagicEffect(CONST_ME_FIREAREA)
		local rad = cfg.cinder.radius
		for _, pl in ipairs(Game.getSpectators(at, false, true, rad, rad, rad, rad)) do
			if r.players[pl:getId()] then
				doTargetCombatHealth(0, pl, COMBAT_FIREDAMAGE, -amount, -amount, CONST_ME_FIREAREA)
			end
		end
	end, cfg.cinder.delayMs, {x = pos.x, y = pos.y, z = pos.z}, dmg)
end

-- ======================================================================== tick
local function tick(slot, rid)
	local run = RF.runs[slot]
	if not run or run.id ~= rid or run.ended then
		return
	end
	local now = os.time()
	if R.tick(run, now) == "fail" then
		fail(run, "Time is up!")
		return
	end
	-- the omen guardian comes startDelay seconds after the party arrived
	if run.omen and run.boss == "waiting" and now >= (run.bossDueAt or 0) then
		run.boss = "alive"
		spawnBoss(run)
		if run.ended then
			return
		end
	end
	-- players who left the instance some other way (GM teleport, ...) are out of the run
	for id, entry in pairs(run.players) do
		local p = Player(id)
		if not p then
			removePlayer(run, id, "none")
		elseif R.slotOfPos(C(), p:getPosition()) ~= run.slot then
			removePlayer(run, id, "none")
		elseif run.fx.noRegen and run.state == "running" then
			wither(p, entry)
		end
		if run.ended then
			return
		end
	end
	if run.state == "running" and now >= (run.hudAt or 0) then
		run.hudAt = now + C().hudEvery
		sendHud(run, "update")
	end
	addEvent(tick, 1000, slot, rid)
end

-- ======================================================================== opening
local exhaust = {}

local function insideOther(player)
	return (ChaosDungeonIsInside and ChaosDungeonIsInside(player))
		or (ChaosTowerRun and ChaosTowerRun.isInside and ChaosTowerRun.isInside(player))
		or (ChaosWorldBoss and ChaosWorldBoss.inside and ChaosWorldBoss.inside(player:getPosition()))
end

local function memberProblem(m, t)
	if RF.runOf[m:getId()] or RF.revive[m:getGuid()] then
		return "is already inside a rift"
	end
	if m:getLevel() < t.minLevel then
		return t.omen and string.format("needs level %d for an omen arena", t.minLevel)
			or string.format("needs level %d for a tier %d rift", t.minLevel, t.tier)
	end
	if Chaos.isMultiClient(m) then
		return "has another character from the same connection online"
	end
	if inCombat(m) then
		return "is in a fight"
	end
	if insideOther(m) then
		return "is inside a dungeon, the tower or the world boss arena"
	end
	return nil
end

local function groupOf(player)
	local cfg = C()
	local members = {player}
	local party = player:getParty()
	if not party then
		return members
	end
	local list = {party:getLeader()}
	for _, m in ipairs(party:getMembers() or {}) do
		list[#list + 1] = m
	end
	local pos = player:getPosition()
	for _, m in ipairs(list) do
		if m and m:getId() ~= player:getId() and #members < cfg.maxPlayers then
			local mp = m:getPosition()
			if mp.z == pos.z and mp:getDistance(pos) <= cfg.partyRange then
				members[#members + 1] = m
			end
		end
	end
	return members
end

-- the rules of the key user; t = {minLevel, tier} or {minLevel, omen = true}. Returns true or false (message sent)
local function openerOk(player, t)
	local cfg = C()
	if RF.runOf[player:getId()] or RF.revive[player:getGuid()] then
		player:sendCancelMessage("You are already inside a rift.")
		return false
	end
	if cfg.needProtectionZone and not inProtectionZone(player) then
		player:sendCancelMessage(t.omen and "You must stand in a protection zone to open an omen arena."
			or "You must stand in a protection zone to open a rift.")
		return false
	end
	if inCombat(player) then
		player:sendCancelMessage("You cannot open a rift while you are in a fight.")
		return false
	end
	if Chaos.isMultiClient(player) then
		player:sendCancelMessage(Chaos.multiClient.msgDungeon)
		return false
	end
	if insideOther(player) then
		player:sendCancelMessage("You cannot open a rift from here.")
		return false
	end
	if player:getLevel() < t.minLevel then
		player:sendCancelMessage(t.omen and string.format("You need level %d to open an omen arena.", t.minLevel)
			or string.format("You need level %d to open a tier %d rift.", t.minLevel, t.tier))
		return false
	end
	return true
end

-- the opener and the members of the party who may come along (the others are told why not)
local function gather(player, t)
	local group = {player}
	for i, m in ipairs(groupOf(player)) do
		if i > 1 then
			local why = memberProblem(m, t)
			if why then
				player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%s stays behind: %s.", m:getName(), why))
				m:sendTextMessage(MESSAGE_INFO_DESCR, string.format("You stay behind from %s's rift: you %s.", player:getName(),
					why:gsub("^is ", "are "):gsub("^needs ", "need "):gsub("^has ", "have ")))
			else
				group[#group + 1] = m
			end
		end
	end
	return group
end

-- a free slot, built (or buildable); L or nil (message sent)
local function takeSlot(player)
	local cfg = C()
	while true do
		local slot = R.allocSlot(cfg, RF.runs, RF.bad)
		if not slot then
			player:sendCancelMessage("Every rift is open right now. Try again in a moment.")
			return nil
		end
		local L, why = buildSlot(slot)
		if L then
			return slot, L
		end
		RF.bad[slot] = why
		print(string.format("[ChaosRift] slot %d not usable: %s", slot, why))
	end
end

-- teleports the group in and registers the run's events
local function enter(run, group)
	local L = run.L
	for i, m in ipairs(group) do
		local entryPos = m:getPosition()
		run.players[m:getId()] = {id = m:getId(), guid = m:getGuid(), name = m:getName(), entry = entryPos, xp = {base = 0}}
		RF.runOf[m:getId()] = run
		m:registerEvent("ChaosRiftPlayerDeath")
		m:registerEvent("ChaosRiftPlayerHit")
		m:registerEvent("ChaosRiftPlayerMana")
		entryPos:sendMagicEffect(CONST_ME_TELEPORT)
		local off = ({{0, 0}, {1, 0}, {-1, 0}, {0, 1}})[i] or {0, 0}
		m:teleportTo(Position(L.start.x + off[1], L.start.y + off[2], L.start.z))
		m:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	end
end

function RF.open(player, item)
	local cfg = C()
	local key = RF.readKey(item)
	if not key then
		player:sendCancelMessage("This rift key is broken.")
		return false
	end
	local t = R.tierInfo(cfg, key.tier)
	if not openerOk(player, t) then
		return false
	end
	local group = gather(player, t)
	local types = R.pickTypes(cfg, rawPool.hunt, key.tier, rand, known)
	if #types == 0 then
		player:sendCancelMessage("No monsters answer this rift. Tell a gamemaster.")
		return false
	end
	local slot, L = takeSlot(player)
	if not slot then
		return false
	end
	cleanSlot(L)
	local th = cfg.themes[rand(1, #cfg.themes)]
	local rooms = R.pickRooms(cfg, rand)
	theme(L, th, rooms)

	-- the key is spent now; the marker refunds it after a crash or a restart during the run
	if not item:remove(1) then
		player:sendCancelMessage("The key could not be used.")
		return false
	end
	setMarker(player, key)

	RF.nextId = RF.nextId + 1
	local fx = R.effects(cfg, key.mods, key.tier)
	local plan = R.plan(cfg, key.tier, fx, #group, types, rooms, rand)
	local run = R.newRun(cfg, os.time(), plan.total, plan.bossAt, fx)
	run.id, run.slot, run.L, run.key, run.fx, run.plan = RF.nextId, slot, L, key, fx, plan
	run.bonus = R.bonuses(cfg, key.mods, key.tier)
	run.players, run.size, run.themeName, run.rooms = {}, #group, th.name, rooms
	run.lives = R.startLives(cfg, #group, fx)
	run.livesMax, run.deaths, run.revive = run.lives, 0, {}
	run.openerGuid = player:getGuid()
	run.typeNames = {}
	for _, e in ipairs(types) do
		run.typeNames[#run.typeNames + 1] = e.name
	end
	RF.runs[slot] = run

	enter(run, group)
	local spawned = spawnPacks(run)
	run.total = spawned
	run.bossAt = math.max(1, math.ceil(spawned * cfg.bossAt / 100))
	if plan.gildedAt then
		plan.gildedAt = math.min(plan.gildedAt, math.max(1, spawned))
	end
	placeCoffer(run)
	local names = {}
	for _, m in ipairs(key.mods) do
		names[#names + 1] = R.modLabel(cfg, m) .. ": " .. R.modText(cfg, m)
	end
	say(run, string.format("Rift tier %d (%s): %d monsters, the guardian appears after %d kills. %d minutes, %d shared lives. Modifiers: %s.",
		key.tier, th.name, run.total, run.bossAt, math.floor(run.limit / 60), run.lives,
		#names > 0 and table.concat(names, "; ") or "none"))
	sendHud(run, "start")
	run.hudAt = os.time() + cfg.hudEvery
	addEvent(tick, 1000, slot, run.id)
	print(string.format("[ChaosRift] %s opened run %d: slot %d, tier %d, %s, %d player(s), %d monsters (%s), rooms %s",
		player:getName(), run.id, slot, key.tier, R.encodeMods(key.mods), #group, run.total,
		table.concat(run.typeNames, "/"), table.concat(rooms, "/")))
	if run.total == 0 then
		run.killed, run.bossAt = 0, 0
		run.boss = "alive"
		spawnBoss(run)
	end
	return true
end

-- an Omen Key: the guardian arena (the hub of a slot, every side room shut)
function RF.openOmen(player, item)
	local cfg = C()
	local o = cfg.omen
	local kind = RF.readOmenKey(item)
	local def = kind and R.omenKind(cfg, kind)
	if not def then
		player:sendCancelMessage("This omen key is silent.")
		return false
	end
	local t = {minLevel = o.minLevel, omen = true}
	if not openerOk(player, t) then
		return false
	end
	if not MonsterType(def.boss) then
		player:sendCancelMessage("The guardian does not answer. Tell a gamemaster.")
		return false
	end
	local group = gather(player, t)
	local slot, L = takeSlot(player)
	if not slot then
		return false
	end
	cleanSlot(L)
	local th = cfg.themes[def.theme] or cfg.themes[1]
	theme(L, th, {})
	if not item:remove(1) then
		player:sendCancelMessage("The key could not be used.")
		return false
	end
	local key = {tier = cfg.maxTier, mods = {}, omen = def.key}
	setMarker(player, key)

	RF.nextId = RF.nextId + 1
	local fx = R.effects(cfg, {}, 1)
	local now = os.time()
	local run = R.newRun(cfg, now, 0, 0, fx)
	run.limit = o.timeLimit
	run.deadline = now + o.timeLimit
	run.bossDueAt = now + o.startDelay
	run.id, run.slot, run.L, run.key, run.fx = RF.nextId, slot, L, key, fx
	run.plan = {types = {}, packs = {}, total = 0, bossAt = 0, boss = def.boss, guardians = 1}
	run.omen = def.key
	run.bonus = {quantity = 0, rarity = 0, experience = 0}
	run.players, run.size, run.themeName, run.rooms = {}, #group, th.name, {}
	run.lives = R.startLives(cfg, #group, fx)
	run.livesMax, run.deaths, run.revive = run.lives, 0, {}
	run.openerGuid = player:getGuid()
	run.typeNames = {def.boss}
	RF.runs[slot] = run
	enter(run, group)
	say(run, string.format("The %s omen: %s comes in %d seconds. %d minutes, %d shared lives.", def.name, def.boss,
		o.startDelay, math.floor(run.limit / 60), run.lives))
	sendHud(run, "start")
	run.hudAt = now + cfg.hudEvery
	addEvent(tick, 1000, slot, run.id)
	print(string.format("[ChaosRift] %s opened omen run %d: slot %d, %s, %d player(s)", player:getName(), run.id, slot,
		def.key, #group))
	return true
end

function RF.isInside(player)
	return player ~= nil and RF.runOf[player:getId()] ~= nil
end

-- loot_config.lua rateMult: the Quantity bonus of the rift the corpse owner / chest opener is in
function RF.lootMult(ctx)
	local p = ctx and ctx.player
	local run = p and RF.runOf[p:getId()]
	if not run then
		return 1
	end
	return 1 + (run.bonus.quantity or 0) / 100
end

-- bounty.lua: a completed (paid) contract may give a tier-1 key
function RF.onBountyPaid(player, contract)
	local cfg = C()
	local p = cfg.bountyKey[contract and contract.type or "hunt"] or 0
	if player:getLevel() >= cfg.tiers[1].minLevel and math.random(100) <= p then
		RF.giveKey(player, R.rollKey(cfg, 1, rand), "Bounty bonus")
	end
end

function RF.status(player)
	local run = RF.runOf[player:getId()]
	if not run then
		return nil
	end
	local left = R.timeLeft(run, os.time())
	if run.omen then
		return string.format("Omen arena (%s): %s, %d:%02d left, guardian %s, %d / %d lives.", R.omenKind(C(), run.omen).name,
			run.state, math.floor(left / 60), left % 60, run.boss, run.lives or 0, run.livesMax or 0)
	end
	return string.format("Rift tier %d (%s): %s, %d:%02d left, %d / %d monsters, guardian %s, %d / %d lives.",
		run.key.tier, run.themeName, run.state, math.floor(left / 60), left % 60, run.killed, run.total,
		run.boss == "waiting" and ("after " .. run.bossAt .. " kills") or run.boss, run.lives or 0, run.livesMax or 0)
end

-- ======================================================================== events
local keyAction = Action()
function keyAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local now = os.time()
	if (exhaust[player:getId()] or 0) > now then
		player:sendCancelMessage("You are exhausted.")
		return true
	end
	exhaust[player:getId()] = now + C().useCooldown
	if not RF.open(player, item) then
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
	end
	return true
end
keyAction:aid(C().key.actionId)
keyAction:register()

-- Omen Fragments: using them (with keyCost or more in the backpack) binds an Omen Key of a random kind
function RF.useFragments(player)
	local o = C().omen
	local have = player:getItemCount(o.fragment.id)
	if have < o.keyCost then
		player:sendCancelMessage(string.format("You need %d omen fragments to bind an Omen Key (you carry %d).", o.keyCost, have))
		return false
	end
	if not omenItemReady(o.key.id) then
		player:sendCancelMessage("Omen Keys are not installed on this server.")
		return false
	end
	if not player:removeItem(o.fragment.id, o.keyCost) then
		player:sendCancelMessage("The fragments could not be bound.")
		return false
	end
	local kind = RF.giveOmenKey(player, nil, string.format("%d omen fragments bind together", o.keyCost))
	player:getPosition():sendMagicEffect(CONST_ME_MAGIC_RED)
	return kind ~= nil
end

if omenItemReady(C().omen.fragment.id) then
	local fragmentAction = Action()
	function fragmentAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		local now = os.time()
		if (exhaust[player:getId()] or 0) > now then
			player:sendCancelMessage("You are exhausted.")
			return true
		end
		exhaust[player:getId()] = now + 1
		RF.useFragments(player)
		return true
	end
	fragmentAction:id(C().omen.fragment.id)
	fragmentAction:register()
end

if omenItemReady(C().omen.key.id) then
	local omenAction = Action()
	function omenAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
		local now = os.time()
		if (exhaust[player:getId()] or 0) > now then
			player:sendCancelMessage("You are exhausted.")
			return true
		end
		exhaust[player:getId()] = now + C().useCooldown
		if not RF.openOmen(player, item) then
			player:getPosition():sendMagicEffect(CONST_ME_POFF)
		end
		return true
	end
	omenAction:id(C().omen.key.id)
	omenAction:register()
else
	print("[ChaosRift] the omen items (" .. C().omen.fragment.id .. ", " .. C().omen.key.id ..
		") are not in items.otb: run tools/install_omens.py; omens are off")
end

-- the reward chest: every finisher takes their share once
function RF.useChest(player, item)
	local slot = R.slotOfPos(C(), item:getPosition())
	local run = slot and RF.runs[slot]
	if not run or run.state ~= "success" or run.ended then
		player:sendCancelMessage("The chest is empty.")
		return true
	end
	local guid = player:getGuid()
	if not run.finishers[guid] then
		player:sendCancelMessage("This chest is not yours.")
		return true
	end
	if run.claimed[guid] then
		player:sendCancelMessage("You already took your share.")
		return true
	end
	run.claimed[guid] = true
	RF.deliver(player, run, false)
	return true
end

local chestAction = Action()
function chestAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	return RF.useChest(player, item)
end
chestAction:aid(C().chest.actionId)
chestAction:register()

local monsterDeath = CreatureEvent("ChaosRiftMonsterDeath")
function monsterDeath.onDeath(creature, corpse, killer, mostDamageKiller)
	local mid = creature:getId()
	local run = RF.monsterRun[mid]
	RF.monsterRun[mid] = nil
	if not run or run.ended or run.state ~= "running" then
		return true
	end
	-- Echoing Spoils: the loot is copied in the onDropLoot callback below (the engine drops loot after this event)
	if run.fx.echo > 0 and R.chance(run.fx.echo, rand) then
		RF.echo[mid] = true
	end
	if run.bossIds and run.bossIds[mid] then
		run.bossIds[mid] = nil
		local res = R.onBossKilled(run, os.time())
		if res == "success" then
			success(run, creature:getPosition())
		elseif res == "twin" then
			say(run, "One guardian falls. Its twin still stands!")
			sendHud(run, "update")
		else
			fail(run, "Time is up!")
		end
		return true
	end
	if run.fx.cinder > 0 then
		cinderBurst(run, creature:getPosition(), creature:getMaxHealth())
	end
	-- Sealed Coffer guards do not count towards the guardian
	local cf = run.coffer
	if cf and cf.wave[mid] then
		cf.wave[mid] = nil
		cf.waveLeft = math.max(0, cf.waveLeft - 1)
		if cf.waveLeft == 0 and cf.state == "guarded" then
			openCoffer(run)
		end
		sendHud(run, "update")
		return true
	end
	-- rare / legendary monsters may carry a key of the rift's tier
	local dead = ChaosTierDead and ChaosTierDead[mid]
	local tierName = dead and dead.tier or (ChaosTierOf and ChaosTierOf(creature)) or "normal"
	local p = C().eliteKeyChance[tierName]
	if p and corpse and corpse.addItem and R.chance(p, rand) then
		local key = R.rollKey(C(), run.key.tier, rand)
		local item = corpse:addItem(C().key.itemId, 1)
		if item then
			RF.applyKey(item, key)
			say(run, string.format("The %s monster dropped a %s!", tierName, R.keyName(C(), key.tier)))
		end
	end
	-- rare / legendary monsters of a rift of omen.minTier or more may carry an Omen Fragment
	local o = C().omen
	local fp = run.key.tier >= o.minTier and o.eliteChance[tierName]
	if fp and corpse and corpse.addItem and omenItemReady(o.fragment.id) and R.chance(fp, rand) then
		corpse:addItem(o.fragment.id, 1)
	end
	local spawnGuardian = R.onKill(run) == "boss"
	if run.plan.gildedAt and not run.goblin and run.killed >= run.plan.gildedAt then
		spawnGoblin(run)
	end
	if spawnGuardian then
		spawnBoss(run)
	else
		sendHud(run, "update")
	end
	return true
end
monsterDeath:register()

-- the Sealed Coffer
local cofferAction = Action()
function cofferAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	return RF.useCoffer(player, item)
end
cofferAction:aid(C().coffer.actionId)
cofferAction:register()

-- Echoing Spoils: every item in the corpse once more (after the Chaos loot layer at 1, before the auto seller at 2;
-- the engine rolls the stats of rarity items after all callbacks, so each copy gets its own). Rift Keys are not copied.
local echoCb = EventCallback
echoCb.onDropLoot = function(monster, corpse)
	local mid = monster:getId()
	if not RF.echo[mid] then
		return
	end
	RF.echo[mid] = nil
	local ok, err = pcall(function()
		if not corpse or not corpse:isContainer() then
			return
		end
		local keyAid = C().key.actionId
		local copies = {}
		for _, item in ipairs(corpse:getItems(false) or {}) do
			if item:getActionId() ~= keyAid then
				copies[#copies + 1] = item:clone()
			end
		end
		-- no effect of its own: the loot snapshot (lootfilter.lua, index 2.5) sees the copies and sends the loot rays
		for _, c in ipairs(copies) do
			corpse:addItemEx(c, INDEX_WHEREEVER or -1, FLAG_NOLIMIT)
		end
	end)
	if not ok then
		print("[ChaosRift] echo onDropLoot failed: " .. tostring(err))
	end
end
echoCb:register(1.5)

-- damage taken by rift monsters: Warding (elemental resistance), Reflection
local reflecting = false
local monsterHealth = CreatureEvent("ChaosRiftMonsterHealth")
function monsterHealth.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	local run = RF.monsterRun[creature:getId()]
	if not run or not attacker or primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local fx = run.fx
	if fx.resist > 0 then
		if primaryType ~= COMBAT_PHYSICALDAMAGE then
			primaryDamage = math.floor(primaryDamage * (1 - fx.resist))
		end
		if secondaryType ~= COMBAT_PHYSICALDAMAGE and secondaryType ~= COMBAT_NONE then
			secondaryDamage = math.floor(secondaryDamage * (1 - fx.resist))
		end
	end
	local p = playerOf(attacker)
	if fx.reflect > 0 and p and not reflecting then
		-- of the damage that lands (overkill is not reflected)
		local landed = math.min(math.abs(primaryDamage) + math.abs(secondaryDamage), creature:getHealth())
		local amount = math.floor(landed * fx.reflect)
		if amount > 0 then
			reflecting = true
			doTargetCombatHealth(creature:getId(), p, COMBAT_PHYSICALDAMAGE, -amount, -amount, CONST_ME_NONE)
			reflecting = false
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
monsterHealth:register()

-- damage taken by players from rift monsters: Brutality and the tiers above the table
local function scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
	local run = attacker and not reflecting and RF.monsterRun[attacker:getId()]
	if run and primaryType ~= COMBAT_HEALING then
		-- a player back from a lost life: rift monsters cannot hurt it for lives.shieldSeconds
		local entry = run.players[creature:getId()]
		if entry and (entry.shieldUntil or 0) > os.time() then
			return 0, primaryType, 0, secondaryType
		end
		local mult = run.fx.damage
		if run.bossIds and run.bossIds[attacker:getId()] then
			mult = mult * run.fx.boss -- Dread Guardian
		end
		if mult ~= 1 then
			primaryDamage = math.floor(primaryDamage * mult)
			secondaryDamage = math.floor(secondaryDamage * mult)
		end
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end

local playerHit = CreatureEvent("ChaosRiftPlayerHit")
function playerHit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		-- Blighted Mending: less healing (spells, potions, runes; food regeneration is not a heal event)
		local run = RF.runOf[creature:getId()]
		if run and run.state == "running" and run.fx.healMult < 1 then
			primaryDamage = math.floor(primaryDamage * run.fx.healMult)
		end
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	return scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
playerHit:register()

local playerMana = CreatureEvent("ChaosRiftPlayerMana")
function playerMana.onManaChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	return scaleHit(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType)
end
playerMana:register()

-- a death inside: the normal death of the engine (losses, blessings, the death window), one shared life less. With lives
-- left the character comes back at the rift's entrance at its next login (login below); the last life collapses it.
local playerDeath = CreatureEvent("ChaosRiftPlayerDeath")
function playerDeath.onDeath(player)
	local run = RF.runOf[player:getId()]
	if not run then
		return true
	end
	local left = R.loseLife(run)
	local guid = player:getGuid()
	if left and left > 0 then
		run.revive[guid] = {name = player:getName(), entry = run.players[player:getId()].entry}
		RF.revive[guid] = run
		say(run, string.format("%s has fallen: %d shared %s left.", player:getName(), left, left == 1 and "life" or "lives"))
		sendHud(run, "update") -- the fallen player too (removed next)
		removePlayer(run, player:getId(), "dead")
	elseif left == 0 then
		say(run, player:getName() .. " has fallen, and with them the rift's last life.")
		-- the dying player leaves first (no teleport inside the death event), then the rift collapses
		run.state = "failed"
		run.endText = "No lives are left!" .. (run.omen and " The arena collapses and the key is lost."
			or " The rift collapses and the key is lost.")
		say(run, run.endText)
		sendHud(run, "update")
		removePlayer(run, player:getId(), "dead")
		if not run.ended then
			finishExit(run)
		end
	else
		say(run, player:getName() .. " has fallen in the rift.")
		removePlayer(run, player:getId(), "dead") -- after the seal: normal death rules, the engine sends them to the temple
	end
	return true
end

-- the next login after a death with lives left: back at the rift's entrance
local function revive(player)
	local guid = player:getGuid()
	local run = RF.revive[guid]
	if not run then
		return false
	end
	RF.revive[guid] = nil
	local f = run.revive and run.revive[guid]
	if run.revive then
		run.revive[guid] = nil
	end
	if not f or run.ended or run.state ~= "running" or RF.runs[run.slot] ~= run then
		return false
	end
	local id = player:getId()
	run.players[id] = {id = id, guid = guid, name = player:getName(), entry = f.entry, xp = {base = 0},
		shieldUntil = os.time() + C().lives.shieldSeconds}
	RF.runOf[id] = run
	player:registerEvent("ChaosRiftPlayerDeath")
	player:registerEvent("ChaosRiftPlayerHit")
	player:registerEvent("ChaosRiftPlayerMana")
	local L = run.L
	player:teleportTo(Position(L.start.x, L.start.y, L.start.z))
	player:getPosition():sendMagicEffect(CONST_ME_TELEPORT)
	say(run, string.format("%s returns to the rift (%d shared %s left).", player:getName(), run.lives,
		run.lives == 1 and "life" or "lives"))
	-- the client asks for the HUD at game start too; this one covers a client that is already loaded
	addEvent(function(cid, slot, rid)
		local p, r = Player(cid), RF.runs[slot]
		if p and r and r.id == rid and not r.ended then
			sendHud(r, "start", p)
		end
	end, 1000, id, run.slot, run.id)
	return true
end
RF._revive = revive
playerDeath:register()

local logout = CreatureEvent("ChaosRiftLogout")
function logout.onLogout(player)
	local run = RF.runOf[player:getId()]
	if run then
		say(run, player:getName() .. " left the rift.")
		removePlayer(run, player:getId(), "logout")
	end
	return true
end
logout:register()

local login = CreatureEvent("ChaosRiftLogin")
function login.onLogin(player)
	player:registerEvent("ChaosRiftLogout")
	player:registerEvent("ChaosRiftExtended")
	revive(player)
	if R.slotOfPos(C(), player:getPosition()) and not RF.runOf[player:getId()] then
		local temple = player:getTown():getTemplePosition()
		player:teleportTo(temple)
	end
	refundMarker(player)
	local list = RF.pending[player:getGuid()]
	if list then
		RF.pending[player:getGuid()] = nil
		for _, data in ipairs(list) do
			RF.deliver(player, data, true)
		end
	end
	return true
end
login:register()

-- client asks for the state (after a module reload)
local ext = CreatureEvent("ChaosRiftExtended")
function ext.onExtendedOpcode(player, opcode, buffer)
	if opcode ~= OPCODE then
		return
	end
	local msg = Chaos.decode(buffer)
	local run = RF.runOf[player:getId()]
	if msg and msg.action == "query" and run then
		sendHud(run, "start", player)
	end
end
ext:type("extendedopcode")
ext:register()

-- experience: the cap (rift_core.lua R.capFactor) and the Experience bonus of the modifiers
local xp = EventCallback
xp.onGainExperience = function(player, source, exp, rawExp)
	local run = RF.runOf[player:getId()]
	if not run or not source or not source:isMonster() or exp <= 0 then
		return exp
	end
	local base = rawExp or exp
	local okLevel, lvl = pcall(function() return source:getMonsterLevel() end)
	local bonus = okLevel and tonumber(lvl) and lvl * 0.03 or 0
	if bonus > 1 then
		base = base * bonus
	end
	base = base * (Game.getExperienceStage(player:getLevel()) or 1)
	-- magic / rare / legendary experience counts against the cap too (the tier state still exists here)
	local tier = ChaosTierOf and ChaosTierOf(source)
	if tier and ChaosTiers and ChaosTiers[tier] then
		base = base * (ChaosTiers[tier].xp or 1)
	end
	local entry = run.players[player:getId()]
	local factor = R.capFactor(C(), entry.xp, player:getLevel(), base, (os.time() - run.startTime) / 60)
	if factor < 1 and not entry.capNotice then
		entry.capNotice = true
		player:sendTextMessage(MESSAGE_STATUS_SMALL, "The rift's experience is spent for now: kills give less until more time passes.")
	end
	return math.floor(exp * factor * (1 + (run.bonus.experience or 0) / 100))
end
xp:register(100) -- after the other experience callbacks (stages, tiers, passive tree, buffs)

-- tier-1 keys from normal level-appropriate kills (not inside a rift)
local drop = EventCallback
drop.onDropLoot = function(monster, corpse)
	local ok, err = pcall(function()
		local owner = Player(corpse:getCorpseOwner())
		if not owner or R.slotOfPos(C(), corpse:getPosition()) then
			return
		end
		local level = RF.poolLevel[monster:getName():lower()]
		if not level then
			return
		end
		local dead = ChaosTierDead and ChaosTierDead[monster:getId()]
		local tierName = dead and dead.tier or (ChaosTierOf and ChaosTierOf(monster)) or "normal"
		local chance = R.monsterKeyChance(C(), level, owner:getLevel(), tierName)
		if chance > 0 and math.random(100000) <= chance then
			local key = R.rollKey(C(), 1, rand)
			local item = corpse:addItem(C().key.itemId, 1)
			if item then
				RF.applyKey(item, key)
				owner:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("A %s drops from %s!", R.keyName(C(), 1),
					monster:getType():getNameDescription()))
			end
		end
	end)
	if not ok then
		print("[ChaosRift] onDropLoot failed: " .. tostring(err))
	end
end
drop:register(2) -- after the Chaos loot layer (1), before autoloot (3)

-- ======================================================================== commands
local function keysOf(player)
	local list = {}
	local cfg = C()
	local function scan(container)
		local okItems, items = pcall(function() return container:getItems(true) end)
		for _, it in ipairs(okItems and items or {}) do
			if it:getId() == cfg.key.itemId and it:getActionId() == cfg.key.actionId then
				list[#list + 1] = RF.readKey(it)
			end
		end
	end
	for slot = CONST_SLOT_HEAD or 1, CONST_SLOT_AMMO or 10 do
		local it = player:getSlotItem(slot)
		if it then
			if it:isContainer() then
				scan(it)
			elseif it:getId() == cfg.key.itemId and it:getActionId() == cfg.key.actionId then
				list[#list + 1] = RF.readKey(it)
			end
		end
	end
	return list
end

local function onRift(player, words, param)
	local cfg = C()
	local args = {}
	for w in (param or ""):gmatch("%S+") do
		args[#args + 1] = w:lower()
	end
	local gm = player:getGroup():getAccess()
	if gm and args[1] == "key" then
		local tier = R.clampTier(cfg, tonumber(args[2]) or 1)
		local key
		if args[3] and tonumber(args[3]) then
			key = {tier = tier, mods = R.rollMods(cfg, tonumber(args[3]), rand, tier)}
		elseif args[3] then
			key = {tier = tier, mods = R.decodeMods(cfg, args[3])}
		else
			key = R.rollKey(cfg, tier, rand)
		end
		RF.giveKey(player, key, "GM key")
		return false
	elseif gm and args[1] == "status" then
		local n = 0
		for slot, run in pairs(RF.runs) do
			n = n + 1
			local names = {}
			for _, e in pairs(run.players) do
				names[#names + 1] = e.name
			end
			player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("slot %d: run %d tier %d %s, %d/%d, %ds left, players %s",
				slot, run.id, run.key.tier, run.state, run.killed, run.total, R.timeLeft(run, os.time()), table.concat(names, ", ")))
		end
		local bad = {}
		for slot, why in pairs(RF.bad) do
			bad[#bad + 1] = slot .. " (" .. why .. ")"
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format("%d rift(s) running, %d slot(s) built, unusable: %s", n,
			(function() local c = 0; for _ in pairs(RF.built) do c = c + 1 end; return c end)(),
			#bad > 0 and table.concat(bad, ", ") or "none"))
		return false
	elseif gm and args[1] == "fail" then
		local run = RF.runOf[player:getId()]
		if run then
			fail(run, "A gamemaster closed the rift.")
		end
		return false
	elseif gm and args[1] == "omen" then
		local kind = args[2] and (R.omenKind(cfg, tonumber(args[2]) or args[2])) or nil
		RF.giveOmenKey(player, kind and kind.key or nil, "GM omen key")
		return false
	elseif gm and args[1] == "fragments" then
		local n = math.max(1, math.min(1000, tonumber(args[2]) or cfg.omen.keyCost))
		if omenItemReady(cfg.omen.fragment.id) then
			giveStack(player, cfg.omen.fragment.id, n)
			player:sendTextMessage(MESSAGE_INFO_DESCR, n .. " omen fragments.")
		end
		return false
	elseif gm and args[1] == "lives" then
		local run = RF.runOf[player:getId()]
		if run and tonumber(args[2]) then
			run.lives = math.max(1, math.floor(tonumber(args[2])))
			sendHud(run, "update")
		end
		return false
	end
	local lines = {}
	local status = RF.status(player)
	if status then
		lines[#lines + 1] = status
	end
	local keys = keysOf(player)
	for i, k in ipairs(keys) do
		if i > 5 then
			lines[#lines + 1] = string.format("... and %d more key(s).", #keys - 5)
			break
		end
		lines[#lines + 1] = R.keyName(cfg, k.tier) .. ": " .. R.describe(cfg, k)
	end
	if #keys == 0 then
		lines[#lines + 1] = "You carry no Rift Key. Tier 1 keys drop from monsters of your level and from bounties; a sealed rift may leave a key of its tier or the next."
	end
	local o = cfg.omen
	if omenItemReady(o.fragment.id) then
		lines[#lines + 1] = string.format("Omen fragments: %d / %d (rifts of tier %d+ give them; use %d to bind an Omen Key " ..
			"that opens a guardian's arena).", player:getItemCount(o.fragment.id), o.keyCost, o.minTier, o.keyCost)
	end
	player:showTextDialog(cfg.key.itemId, table.concat(lines, "\n\n"))
	return false
end

-- staff only (players open the window from the menu)
local talk = TalkAction("/rift")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() then
		return false -- players open it from the menu
	end
	return onRift(player, words, param)
end
talk:separator(" ")
talk:register()
-- players: the run status and the keys carried, from the menu (Info & Services, commands_ui.lua)
ChaosCommands.register("rift", function(player)
	return onRift(player, "", "")
end)
