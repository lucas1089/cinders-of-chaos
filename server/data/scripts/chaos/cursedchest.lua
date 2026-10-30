-- Cursed Chest (server/README.md "Cursed Chest", O244): a monster kill may leave a cursed chest at the corpse. Its owner
-- (the corpse owner) and their party may use it: that wakes five hordes of the area's monsters, one at a time, scaled to
-- the opener. When the fifth is dead the chest unseals and every player who took part takes one loot roll of their own.
-- Rules: cursedchest_core.lua (tests/cursedchest_test.lua), numbers: cursedchest_config.lua.
--
--   the chance      EventCallback onDropLoot (index 5, after the stock loot, the Chaos loot layer, the gold bonus and
--                   autoloot): one roll per kill for the corpse owner. No roll for summons, in PvP places, in any
--                   instance (Chaos.instanceAt / inAnyInstance), in protection zones, for monsters of other systems
--                   (treasure goblins, rifts, invasions, generated areas, this event's own) or without stamina.
--   the chest       a map item (one of cfg.chest.itemIds at random, else cfg.chest.itemId; action id
--                   cfg.chest.actionId) on the corpse's tile; it crumbles unopened after cfg.spawn.expireSec.
--                   A dark effect loops over it (GlobalEvent, cfg.chest.loopMs).
--   the event       addEvent chain (cfg.event.tickMs) per chest. Monsters are husks (Monster:setDropLoot(false): no
--                   corpse loot, so no Cursed Chest, treasure goblin, blessing or Chaos roll from them), paced like a
--                   hunt (ChaosPace.apply: experience and health follow the hunt's model), scaled to the opener (health
--                   here, damage through ChaosAreaGen.scaled's hit hook) and tagged (CC.tagged).
--   fail / success  cursedchest_core.lua K.step. A failed event removes its monsters and the chest. A won chest waits
--                   cfg.event.claimSec; each participant (creature id, recorded at the use) takes one roll, once.
-- State is in memory only (CC.chests, CC.tagged): a restart leaves no monster and no chest worth anything. A chest item
-- that survives on the map (or a /reload) is unknown to the table and crumbles at the next use.
-- Assumed engine API (TFS 1.4.2 + patches as the rest of the Chaos scripts): Game.createItem / createMonster, Tile,
-- Monster:setDropLoot / setMaxHealth / setHealth, Player:getParty, EventCallback onDropLoot, Action:aid, GlobalEvent.
-- Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not ChaosI18n then
	dofile("data/scripts/chaos/i18n_core.lua")
end
ChaosCursedChestConfig = dofile("data/scripts/chaos/cursedchest_config.lua")
dofile("data/scripts/chaos/cursedchest_core.lua")

ChaosCursedChest = ChaosCursedChest or {}
local CC = ChaosCursedChest
local K = ChaosCursedChestCore
CC.chests = CC.chests or {} -- "x:y:z" -> chest record
CC.tagged = CC.tagged or {} -- monster id -> chest record (the event's monsters)
CC.levels = CC.levels or {} -- monster id -> the hunting level the chest scaled it to (CC.levelOf)
CC.state = CC.state or K.newState()
CC.seq = CC.seq or 0

local function cfg()
	return ChaosCursedChestConfig
end

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function rand(a, b)
	return math.random(a, b)
end

local function try(what, fn, ...)
	local ok, a, b = pcall(fn, ...)
	if not ok then
		print("[Chaos cursed chest] " .. what .. ": " .. tostring(a))
		return nil
	end
	return a, b
end

local function posKey(pos)
	return string.format("%d:%d:%d", pos.x, pos.y, pos.z)
end

local function P(pos)
	return Position(pos.x, pos.y, pos.z)
end

local function constant(name)
	return name and rawget(_G, name) or nil
end

local function fx(pos, name)
	local id = constant(name)
	if id then
		P(pos):sendMagicEffect(id)
	end
end

local function say(player, text, ...)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, Chaos.t(player, text, ...))
end

local function toast(player, text, ...)
	if ChaosNotify and ChaosNotify.gmBroadcast then
		pcall(ChaosNotify.gmBroadcast, player, Chaos.t(player, text, ...))
	end
end

-- a text with a toast, for the players of an event that are online
local function tellAll(ev, text, ...)
	for pid in pairs(ev.participants) do
		local p = Player(pid)
		if p then
			say(p, text, ...)
			toast(p, text, ...)
		end
	end
end

-- ------------------------------------------------------------------ places and exclusions
function CC.pvpPlace(player)
	local pos = player:getPosition()
	local function check(fn)
		local ok, v = pcall(fn)
		return ok and v and true or false
	end
	if check(function() return ChaosBattleground and ChaosBattleground.isInside(player) end) then
		return "battleground"
	end
	if check(function() return ChaosArena and ChaosArena.isInside and ChaosArena.isInside(player) end) then
		return "arena"
	end
	if check(function() return ChaosSiege and ChaosSiege.locate and ChaosSiege.locate(pos) ~= nil end) then
		return "siege"
	end
	if check(function()
		local tile = Tile(pos)
		return TILESTATE_PVPZONE and tile and tile:hasFlag(TILESTATE_PVPZONE)
	end) then
		return "pvp zone"
	end
	if check(function()
		local Z = rawget(_G, "ChaosPvpZone")
		return Z and ((Z.isInside and Z.isInside(player)) or (Z.inZone and Z.inZone(pos)))
	end) then
		return "pvp zone"
	end
	return nil
end

-- the key of an instance the player or the position is in (Chaos.registerInstance), a rift run, a Tower run, a
-- world boss room ...
local function instanceOf(player, pos)
	local ok, key = pcall(function() return Chaos.inAnyInstance(player) or Chaos.instanceAt(pos) end)
	if ok and key then
		return key
	end
	if ChaosTreasureGoblin and ChaosTreasureGoblin.excludedAt and try("excludedAt", ChaosTreasureGoblin.excludedAt, pos) then
		return "excluded area"
	end
	local runOf = ChaosRift and ChaosRift.runOf
	if runOf and runOf[player:getId()] then
		return "rift"
	end
	return nil
end

-- a monster made by a system with its own rewards, or this event's own
local function taggedMonster(monster)
	local id = monster:getId()
	if CC.tagged[id] then
		return true
	end
	if ChaosTreasureGoblin and ChaosTreasureGoblin.alive and ChaosTreasureGoblin.alive[id] then
		return true
	end
	if ChaosRift and ChaosRift.monsterRun and ChaosRift.monsterRun[id] then
		return true
	end
	if ChaosInvasion and ChaosInvasion.invaders and ChaosInvasion.invaders[id] then
		return true
	end
	if ChaosAreaGen and ChaosAreaGen.pointOf and ChaosAreaGen.pointOf[id] then
		return true
	end
	if Chaos.eventKnown then
		for _, name in ipairs(cfg().spawn.excludeEvents or {}) do
			if Chaos.eventKnown(monster, name) then
				return true
			end
		end
	end
	return false
end

local function monsterLevel(monster)
	if ChaosLoot and ChaosLoot.monsterLevel then
		local ok, lvl = pcall(ChaosLoot.monsterLevel, monster)
		if ok and tonumber(lvl) then
			return tonumber(lvl)
		end
	end
	local ok, lvl = pcall(function() return monster:getMonsterLevel() end)
	return ok and tonumber(lvl) or 0
end

-- gear ids of a monster type's loot table
local function gearOf(mt)
	local out, seen = {}, {}
	if not mt or not ChaosLoot or not ChaosLoot.isGearId then
		return out
	end
	local ok, loot = pcall(function() return mt:getLoot() end)
	for _, e in ipairs(ok and loot or {}) do
		local id = e.itemId
		if id and not seen[id] and ChaosLoot.isGearId(id) then
			seen[id] = true
			out[#out + 1] = id
		end
	end
	return out
end

-- ------------------------------------------------------------------ the chest
local function chestAt(pos)
	return CC.chests[posKey(pos)]
end

local function usableTile(pos)
	local tile = Tile(P(pos))
	if not tile or not tile:getGround() then
		return false
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:getHouse() then
		return false
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:hasFlag(TILESTATE_FLOORCHANGE) or tile:hasFlag(TILESTATE_TELEPORT) then
		return false
	end
	return chestAt(pos) == nil
end

-- the corpse's tile, else the nearest usable one within the radius
local function placeFor(center)
	local r = cfg().spawn.placeRadius
	local best, bestD
	for dx = -r, r do
		for dy = -r, r do
			local pos = {x = center.x + dx, y = center.y + dy, z = center.z}
			local d = dx * dx + dy * dy
			if (not bestD or d < bestD) and usableTile(pos) then
				best, bestD = pos, d
			end
		end
	end
	return best
end

-- is this item type on the server? (an id that is not in items.otb has type id 0)
local function itemExists(id)
	local ok, res = pcall(function() return ItemType(id):getId() end)
	return ok and res ~= nil and res ~= 0
end

-- the chest's item on its tile, whichever look it wears (the look it was made with first)
local function chestItem(ch)
	local tile = Tile(P(ch.pos))
	if not tile then
		return nil
	end
	local item = ch.itemId and tile:getItemById(ch.itemId)
	if item then
		return item
	end
	for _, id in ipairs(K.allChestIds(cfg())) do
		item = tile:getItemById(id)
		if item then
			return item
		end
	end
	return nil
end

-- takes a chest out of the world: the item, the table and the server's count
local function remove(ch, effectName)
	if ch.state == "gone" then
		return
	end
	ch.state = "gone"
	local item = chestItem(ch)
	if item then
		fx(ch.pos, effectName or cfg().chest.crumbleEffect)
		item:remove()
	end
	CC.chests[ch.key] = nil
	K.markGone(CC.state, ch.ownerId)
end

-- creates the chest for a kill; returns the record or nil
function CC.spawnChest(owner, center, info)
	local c = cfg()
	local pos = placeFor(center)
	if not pos then
		return nil
	end
	local itemId = K.pickChestId(c, itemExists, rand)
	local item = Game.createItem(itemId, 1, P(pos))
	if not item then
		return nil
	end
	item:setActionId(c.chest.actionId)
	item:setAttribute(ITEM_ATTRIBUTE_NAME, c.chest.name)
	item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, c.chest.description)
	CC.seq = CC.seq + 1
	local ch = {
		id = CC.seq, key = posKey(pos), pos = pos, itemId = itemId, state = "idle", ownerId = owner:getGuid(), ownerName = owner:getName(),
		bornAt = nowMs(), expiresAt = nowMs() + c.spawn.expireSec * 1000, killed = info.name, pool = info.pool,
		gear = info.gear, monsterLevel = info.monsterLevel, tier = info.tier
	}
	CC.chests[ch.key] = ch
	K.markSpawn(c, CC.state, ch.ownerId, os.time())
	fx(pos, c.chest.openEffect)
	return ch
end

-- ------------------------------------------------------------------ the chance of a kill
local function pool(center, killedName, level)
	local c = cfg()
	local names = {}
	local r = c.event.pool.nearRadius
	local skip = {}
	for _, n in ipairs(c.spawn.excludeNames or {}) do
		skip[n] = true
	end
	for _, m in ipairs(Game.getSpectators(P(center), false, false, r, r, r, r) or {}) do
		if m:isMonster() and not m:getMaster() and not taggedMonster(m) then
			local mt = m:getType()
			local boss = mt and try("boss", function() return mt:isBoss() end)
			if not boss and not (ChaosTierConfig and ChaosTierConfig.bosses and ChaosTierConfig.bosses[m:getName():lower()]) then
				names[#names + 1] = m:getName()
			end
		end
	end
	return K.buildPool(c, killedName, names, level, skip)
end

-- the rolled kill: returns the chest record or nil
function CC.onKill(monster, owner, corpse)
	local c = cfg()
	if c.enabled == false then
		return nil
	end
	local pos = corpse:getPosition()
	local tile = Tile(pos)
	local mt = monster:getType()
	local minStamina = ChaosLootConfig and ChaosLootConfig.minStamina or 0
	local tier = type(ChaosTierOf) == "function" and ChaosTierOf(monster) or "normal"
	local info = {
		ownerId = owner:getGuid(), tier = tier, name = monster:getName(), summon = monster:getMaster() ~= nil,
		tagged = taggedMonster(monster), maxHealth = monster:getMaxHealth(), pos = pos,
		place = CC.pvpPlace(owner), instance = instanceOf(owner, pos),
		protectionZone = tile and tile:hasFlag(TILESTATE_PROTECTIONZONE) or false,
		house = tile and tile:getHouse() ~= nil or false, stamina = owner:getStamina() > minStamina,
		playerLevel = owner:getLevel(), monsterLevel = monsterLevel(monster)
	}
	if mt and info.tier ~= "boss" and try("isBoss", function() return mt:isBoss() end) then
		info.tier = "boss"
	end
	local now = os.time()
	K.prune(CC.state, now)
	if not K.eligible(c, info, CC.state, now) or not K.roll(c, info, rand) then
		return nil
	end
	local level = K.areaLevel(c, info.monsterLevel, info.playerLevel)
	local ch = CC.spawnChest(owner, pos, {
		name = info.name, pool = pool(pos, info.name, level), gear = gearOf(mt), monsterLevel = level, tier = tier
	})
	if not ch then
		return nil
	end
	ch.level = level
	CC.announceSpawn(ch, owner)
	return ch
end

function CC.announceSpawn(ch, owner)
	local c = cfg()
	local seen = {}
	local r = c.spawn.announceRadius
	local function tellOne(p)
		if not seen[p:getId()] then
			seen[p:getId()] = true
			say(p, "A cursed chest rises where the %s fell! Use it within %d seconds if you dare: five hordes guard its loot.",
				ch.killed, c.spawn.expireSec)
			toast(p, "A cursed chest rises where the %s fell! Use it within %d seconds if you dare: five hordes guard its loot.",
				ch.killed, c.spawn.expireSec)
		end
	end
	tellOne(owner)
	if ChaosCombatFx and ChaosCombatFx.label then
		pcall(ChaosCombatFx.label, ch.pos, function(p) return Chaos.t(p, "CURSED CHEST") end, c.chest.labelColor)
	end
end

-- ------------------------------------------------------------------ the party
local function inPartyWith(a, b)
	if a:getId() == b:getId() then
		return true
	end
	local ok, same = pcall(function()
		local pa, pb = a:getParty(), b:getParty()
		if not pa or not pb then
			return false
		end
		local lead = pa:getLeader()
		local function has(party, id)
			if party:getLeader() and party:getLeader():getId() == id then
				return true
			end
			for _, m in ipairs(party:getMembers() or {}) do
				if m:getId() == id then
					return true
				end
			end
			return false
		end
		return (lead ~= nil and has(pb, lead:getId())) or has(pb, a:getId())
	end)
	return ok and same == true
end

local function mayUse(player, ch)
	if player:getGuid() == ch.ownerId then
		return true
	end
	-- the owner's party: live, the owner must be online (the owner's chest is theirs and their party's)
	for _, p in ipairs(Game.getPlayers() or {}) do
		if p:getGuid() == ch.ownerId then
			return inPartyWith(player, p)
		end
	end
	return false
end

local function near(player, pos, radius)
	local pp = player:getPosition()
	return pp.z == pos.z and math.abs(pp.x - pos.x) <= radius and math.abs(pp.y - pos.y) <= radius
end

-- the opener and the opener's party within the join radius, by creature id
local function gatherParticipants(opener, ch)
	local out = {[opener:getId()] = true}
	local radius = cfg().event.joinRadius
	local ok, party = pcall(function() return opener:getParty() end)
	if ok and party then
		local list = {}
		local lead = party:getLeader()
		if lead then
			list[#list + 1] = lead
		end
		for _, m in ipairs(party:getMembers() or {}) do
			list[#list + 1] = m
		end
		for _, m in ipairs(list) do
			if m:getHealth() > 0 and near(m, ch.pos, radius) and not CC.pvpPlace(m) then
				out[m:getId()] = true
			end
		end
	end
	return out
end

-- ------------------------------------------------------------------ the hordes
local function randomSpot(ch)
	local e = cfg().event
	-- spawn_tile_core.lua: ground, no water (a land horde never left it), not blocked, no protection zone, house or
	-- floor change; nil (the monster is skipped) when 14 tries find none
	return ChaosSpawnTile.find(ch.pos, {radius = e.spreadMax, minRadius = e.spreadMin, tries = 14, rand = rand, occupied = true})
end

local TIER_EVENTS = {"ChaosTierRollMagic", "ChaosTierRollRare", "ChaosTierRollLegendary"}

-- one monster of the event; returns it or nil
local function spawnMonster(ev, ch, name, tier, plan, target)
	local pos = randomSpot(ch)
	if not pos then
		return nil
	end
	local create = Chaos.createMonsterNamed or function(t, p, e, f) return Game.createMonster(t, p, e, f) end
	local m = create(name, P(pos), true, false, nil, target)
	if not m then
		return nil
	end
	local id = m:getId()
	CC.tagged[id] = ch
	CC.levels[id] = target
	ev.monsters[id] = true
	m:registerEvent("ChaosCursedChestDeath")
	if m.setDropLoot then
		m:setDropLoot(false) -- a husk: experience only, no corpse loot and so no second chest, goblin or blessing
	end
	-- the natural tier roll off; the plan's tier on (ChaosApplyTier), or normal
	for _, name2 in ipairs(TIER_EVENTS) do
		pcall(function() m:unregisterEvent(name2) end)
	end
	if tier ~= "normal" and ChaosApplyTier then
		pcall(ChaosApplyTier, m, tier)
	end
	if ChaosPace and ChaosPace.apply then
		pcall(ChaosPace.apply, m, true) -- the hunt's pace: experience and health as a map spawn of the monster's level
	end
	local sc = K.levelScale(cfg(), monsterLevel(m), target)
	local hp = math.floor(m:getMaxHealth() * sc.health * plan.health)
	if hp > 0 and hp ~= m:getMaxHealth() then
		m:setMaxHealth(hp)
		m:setHealth(hp)
	end
	if ChaosAreaGen and ChaosAreaGen.scaled then
		-- areagen's hit hook (ChaosAreaGenPlayerHit, on every player) scales the monster's damage; experience stays 1
		ChaosAreaGen.scaled[id] = {damage = sc.damage * plan.damage, experience = 1}
	end
	P(pos):sendMagicEffect(constant("CONST_ME_MORTAREA") or constant("CONST_ME_TELEPORT"))
	return m
end

-- the hunting level a chest monster was scaled to (health and damage follow it, the nameplate shows it), nil for any
-- other monster. The monster's own level stays the type's, so a counter that reads levels (the Ascension Proof of
-- Strength, ascension_quest.lua) asks here: a rare Rotworm of a chest for a level 200 player is a level 180 beast.
-- Kept a few seconds past the death (the kill events of the players run around the death event).
function CC.levelOf(monster)
	local ok, id = pcall(function() return monster:getId() end)
	return ok and CC.levels[id] or nil
end

local function aliveCount(ev)
	local n = 0
	for id in pairs(ev.monsters) do
		local m = Monster(id)
		if m and m:getHealth() > 0 then
			n = n + 1
		else
			ev.monsters[id] = nil
			CC.tagged[id] = nil
			if not m then
				CC.levels[id] = nil
			end
			if ChaosAreaGen and ChaosAreaGen.scaled then
				ChaosAreaGen.scaled[id] = nil
			end
		end
	end
	return n
end

local function spawnHorde(ev, ch, n)
	local c = cfg()
	local total = K.hordeCount(c)
	local plan = K.hordePlan(c, n, ev.players, rand)
	local target = K.targetLevel(c, ev.openerLevel)
	local made = 0
	for i = 1, plan.count do
		local name = K.pickKind(ev.pool, rand)
		if name and spawnMonster(ev, ch, name, plan.tiers[i], plan, target) then
			made = made + 1
		end
	end
	K.spawned(ev, n, nowMs())
	if plan.leader == "legendary" then
		tellAll(ev, "Horde %d/%d: a legendary leader leads it!", n, total)
	elseif plan.leader then
		tellAll(ev, "Horde %d/%d: a rare leader leads it!", n, total)
	else
		tellAll(ev, "Horde %d/%d!", n, total)
	end
	if ChaosCombatFx and ChaosCombatFx.label then
		pcall(ChaosCombatFx.label, ch.pos, function(p) return Chaos.t(p, "HORDE %d/%d", n, total) end, c.chest.labelColor)
	end
	fx(ch.pos, "CONST_ME_MORTAREA")
	try("aura", CC.syncAuras)
	return made
end

-- ------------------------------------------------------------------ the monsters' aura (O341)
-- Tells each player which event monsters they can see, so the client draws the chest's smoke under them. Only when a
-- viewer's list changed; runs from the think loop (1.5 s), after a horde spawns and when an event ends.
CC.auraSent = CC.auraSent or {}
local AURA_VIEW = {x = 10, y = 8}

function CC.syncAuras()
	local monsters = {}
	for id in pairs(CC.tagged) do
		local m = Monster(id)
		if m and m:getHealth() > 0 then
			monsters[#monsters + 1] = {id = id, pos = m:getPosition()}
		end
	end
	if #monsters == 0 and next(CC.auraSent) == nil then
		return
	end
	local op = (ChaosOpcodes and ChaosOpcodes.templarAura) or 118
	local online = {}
	for _, p in ipairs(Game.getPlayers()) do
		local pid = p:getId()
		online[pid] = true
		local ids = K.auraList({id = pid, pos = p:getPosition()}, monsters, AURA_VIEW)
		local out = K.auraDecide(CC.auraSent, pid, ids)
		if out then
			try("aura sync", function()
				if Chaos and Chaos.send then
					return Chaos.send(p, op, "cursed", {c = out})
				end
				return p:sendExtendedOpcode(op, json.encode({action = "cursed", data = {c = out}}))
			end)
		end
	end
	K.auraPrune(CC.auraSent, online)
end

-- ------------------------------------------------------------------ the end
local function clearMonsters(ev, despawn)
	for id in pairs(ev.monsters) do
		local m = Monster(id)
		if m and despawn then
			fx(m:getPosition(), "CONST_ME_POFF")
			m:remove()
		end
		CC.tagged[id] = nil
		CC.levels[id] = nil
		if ChaosAreaGen and ChaosAreaGen.scaled then
			ChaosAreaGen.scaled[id] = nil
		end
	end
	ev.monsters = {}
end

function CC.failEvent(ch, reason)
	local ev = ch.ev
	if not ev or ev.state ~= "running" then
		return
	end
	K.fail(ev, reason)
	clearMonsters(ev, true)
	try("aura", CC.syncAuras)
	if reason == "time" then
		tellAll(ev, "The curse wins: time is up. The cursed chest crumbles and its hordes fade.")
	else
		tellAll(ev, "Nobody is left to fight. The cursed chest crumbles and its hordes fade.")
	end
	remove(ch)
end

function CC.winEvent(ch)
	local c = cfg()
	local ev = ch.ev
	K.win(c, ev, nowMs())
	clearMonsters(ev, false)
	try("aura", CC.syncAuras)
	ch.state = "won"
	local item = chestItem(ch)
	if item then
		item:setAttribute(ITEM_ATTRIBUTE_NAME, c.chest.nameOpened)
		item:setAttribute(ITEM_ATTRIBUTE_DESCRIPTION, "The curse is lifted. Use it to take your share.")
	end
	fx(ch.pos, c.chest.openEffect)
	tellAll(ev, "All five hordes are dead! The cursed chest unseals: use it within %d seconds to take your loot.",
		c.event.claimSec)
end

-- one step of an event (addEvent chain)
local tickInner
function CC.tick(key)
	local ok, err = pcall(tickInner, key)
	if not ok then
		-- a broken step must not leave monsters or a locked chest behind: the event ends
		print("[Chaos cursed chest] tick: " .. tostring(err))
		local ch = CC.chests[key]
		if ch and ch.ev and ch.ev.state == "running" then
			pcall(CC.failEvent, ch, "abandoned")
		end
	end
end

function tickInner(key)
	local c = cfg()
	local ch = CC.chests[key]
	local ev = ch and ch.ev
	if not ev or ev.state ~= "running" then
		return
	end
	local now = nowMs()
	local inside = 0
	for pid in pairs(ev.participants) do
		local p = Player(pid)
		if p and p:getHealth() > 0 and near(p, ch.pos, c.event.leaveRadius) then
			inside = inside + 1
		end
	end
	local actions = K.step(c, ev, {alive = aliveCount(ev), inside = inside}, now)
	for _, a in ipairs(actions) do
		if a[1] == "spawn" then
			if try("horde", spawnHorde, ev, ch, a[2]) == nil then
				K.spawned(ev, a[2], now) -- a horde that failed to build counts as spawned: the event moves on
			end
		elseif a[1] == "warn" then
			tellAll(ev, "You are leaving the cursed chest! Go back or the curse wins in %d seconds.",
				c.event.emptyGraceSec - c.event.warnSec)
		elseif a[1] == "fail" then
			CC.failEvent(ch, a[2])
			return
		elseif a[1] == "win" then
			CC.winEvent(ch)
			return
		end
	end
	addEvent(CC.tick, c.event.tickMs, key)
end

function CC.startEvent(player, ch)
	local c = cfg()
	local ev = K.newEvent(c, {
		ownerId = ch.ownerId, openerId = player:getId(), level = ch.level, openerLevel = player:getLevel(), pool = ch.pool,
		gear = ch.gear, killed = ch.killed, pos = ch.pos, participants = gatherParticipants(player, ch)
	}, nowMs())
	ev.monsters = {}
	ch.ev, ch.state = ev, "running"
	fx(ch.pos, "CONST_ME_MORTAREA")
	tellAll(ev, "%s opens the cursed chest! Five hordes will come, one after another.", player:getName())
	addEvent(CC.tick, c.event.tickMs, ch.key)
end

-- ------------------------------------------------------------------ the loot
local function itemName(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	return ok and name or tostring(id)
end

-- where the rest of a loot went when it did not fit the backpack: "inbox", or "ground" when the inbox could not take it
-- either (the player is told in both cases; nothing is lost)
local function dropAt(player, id, n)
	local item = Game.createItem(id, n, player:getPosition())
	return item ~= nil
end

-- stack to the player's backpack; the rest to the inbox, else to the ground under the player. Returns "inbox",
-- "ground" or false (everything fitted).
local function giveStack(player, id, count)
	if count <= 0 then
		return false
	end
	local rest = count - Chaos.giveItem(player, id, count)
	if rest <= 0 then
		return false
	end
	local where = "inbox"
	local inbox = player:getInbox()
	while inbox and rest > 0 do
		local n = math.min(rest, 100)
		if not inbox:addItem(id, n, INDEX_WHEREEVER or -1, FLAG_NOLIMIT) then
			break
		end
		rest = rest - n
	end
	while rest > 0 do
		local n = math.min(rest, 100)
		if not dropAt(player, id, n) then
			break
		end
		where = "ground"
		rest = rest - n
	end
	return where
end

local function giveEx(player, item)
	if player:addItemEx(item, false) == (RETURNVALUE_NOERROR or 0) then
		return false
	end
	local inbox = player:getInbox()
	if inbox and inbox:addItemEx(item, INDEX_WHEREEVER or -1, FLAG_NOLIMIT) == (RETURNVALUE_NOERROR or 0) then
		return "inbox"
	end
	if item.moveTo then
		item:moveTo(player:getPosition())
	end
	return "ground"
end

local function stackText(id, n)
	return (n > 1 and (n .. "x ") or "") .. itemName(id)
end

-- one player's roll. Returns the text pieces and where the rest went when the backpack was full ("inbox", "ground" or
-- false). Every part is its own step: one that breaks (a missing item type, a crafting error) is logged and the other
-- parts are still given, so a loot never ends empty and silent because of one bad roll.
function CC.giveLoot(player, ch)
	local c = cfg()
	local ev = ch.ev
	local L = ChaosLoot
	local level, players = ch.level, ev.players
	local itemFind = try("itemFind", function() return L and L.itemFindMult and L.itemFindMult(player) or 1 end) or 1
	local parts, spill = {}, false
	local function note(where)
		if where == "ground" or (where and not spill) then
			spill = where
		end
	end
	local function stack(id, n)
		if n > 0 then
			note(giveStack(player, id, n))
			parts[#parts + 1] = stackText(id, n)
		end
	end
	try("gold", function()
		local value = K.goldValue(c, level, players, rand)
		if value > 0 then
			for _, coin in ipairs(K.coins(value)) do
				note(giveStack(player, coin.id, coin.count))
			end
			parts[#parts + 1] = value .. " gold"
		end
	end)
	try("orbs", function()
		stack(c.loot.chaosOrb.id, K.chaosOrbs(c, level, players, rand))
		if K.divineOrb(c, itemFind, players, rand) then
			stack(c.loot.divineOrb.id, 1)
		end
	end)
	try("shards", function() stack(c.loot.shards.id, K.shardCount(c, level, players, rand)) end)
	try("crafting orbs", function()
		local orbCounts, order = {}, {}
		for _, key in ipairs(K.orbKeys(c, rand)) do
			local orb = ChaosCrafting and ChaosCrafting.orbByKey and ChaosCrafting.orbByKey[key]
			if orb then
				if not orbCounts[orb.id] then
					order[#order + 1] = orb.id
				end
				orbCounts[orb.id] = (orbCounts[orb.id] or 0) + 1
			end
		end
		for _, id in ipairs(order) do
			stack(id, orbCounts[id])
		end
	end)
	local ilvl = try("item level", function()
		return ChaosItemMods and ChaosItemMods.sourceLevel and ChaosItemMods.sourceLevel({monsterLevel = level, tier = "rare"})
	end)
	for _, id in ipairs(K.pickGear(c, level, ev.gear, K.itemCount(c, players, rand), rand)) do
		try("gear", function()
			local t = K.pickItemTier(c, rand)
			local r = t.floor or 0
			if L and L.upgradeRarity then
				r = math.max(r, L.upgradeRarity(t.tier, L.stockRarity(), itemFind * c.loot.rarityMult, level))
			end
			local item = try("forge", function()
				return ChaosCrafting and ChaosCrafting.createItem and ChaosCrafting.createItem(id, r, ilvl)
			end)
			item = item or Game.createItem(id, 1)
			if item then
				note(giveEx(player, item))
				parts[#parts + 1] = itemName(id)
			end
		end)
	end
	if L and L.rollUniques then
		local uniques = try("uniques", L.rollUniques, c.loot.unique.tier, ev.killed or "", level, itemFind * c.loot.unique.mult) or {}
		for _, e in ipairs(uniques) do
			try("unique", function()
				local item = Game.createItem(e.id, 1)
				if item then
					if ChaosMakeUnique then
						ChaosMakeUnique(item)
					end
					note(giveEx(player, item))
					parts[#parts + 1] = "{" .. e.name .. "}"
				end
			end)
		end
	end
	return parts, spill
end

-- the one message of a claim, on screen (MESSAGE_LOOT lines are kept off the game screen by game_lootscreen, so the
-- chest's outcome is an event line plus a toast; the loot line of the console follows)
local function claimReport(player, parts, spill)
	local text
	if #parts == 0 then
		text = Chaos.t(player, "The cursed chest held nothing for you this time.")
	else
		local tail = ""
		if spill == "ground" then
			tail = Chaos.t(player, " Your backpack and inbox were full: the rest lies on the ground at your feet.")
		elseif spill == "inbox" then
			tail = Chaos.t(player, " Your backpack was full: the rest is in your inbox.")
		end
		text = Chaos.t(player, "Cursed Chest loot: %s.%s", table.concat(parts, ", "), tail)
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE or MESSAGE_INFO_DESCR, text)
	if ChaosNotify and ChaosNotify.gmBroadcast then
		pcall(ChaosNotify.gmBroadcast, player, text)
	end
end

local function claim(player, ch)
	local c = cfg()
	local ev = ch.ev
	local ok, why = K.canClaim(ev, player:getId(), nowMs())
	if not ok then
		if why == "claimed" then
			player:sendCancelMessage(Chaos.t(player, "You already took your share of the cursed chest."))
		elseif why == "not a participant" then
			player:sendCancelMessage(Chaos.t(player, "You were not there when the curse was lifted."))
		else
			player:sendCancelMessage(Chaos.t(player, "The cursed chest crumbles to dust."))
		end
		return
	end
	if not near(player, ch.pos, c.event.leaveRadius) then
		player:sendCancelMessage(Chaos.t(player, "You are too far from the cursed chest."))
		return
	end
	if not K.claim(ev, player:getId()) then -- the mark first: nothing below can run twice for one player
		return
	end
	local okLoot, parts, spill = pcall(CC.giveLoot, player, ch)
	if not okLoot then
		-- the whole roll broke: the mark goes back so the player can use the chest again, and is told
		print("[Chaos cursed chest] loot: " .. tostring(parts))
		K.unclaim(ev, player:getId())
		player:sendCancelMessage(Chaos.t(player, "The cursed chest could not give its loot. Use it again."))
		return
	end
	claimReport(player, parts, spill)
	fx(player:getPosition(), c.chest.openEffect)
end

-- ------------------------------------------------------------------ the use
function CC.use(player, item)
	local c = cfg()
	local ch = chestAt(item:getPosition())
	if not ch or ch.state == "gone" then
		-- a chest the table does not know (a restart, a /reload): nothing to open
		fx(item:getPosition(), c.chest.crumbleEffect)
		item:remove()
		player:sendCancelMessage(Chaos.t(player, "The cursed chest crumbles to dust."))
		return true
	end
	if not mayUse(player, ch) then
		player:sendCancelMessage(Chaos.t(player, "This cursed chest is not yours."))
		return true
	end
	if ch.state == "idle" then
		local place = CC.pvpPlace(player) or instanceOf(player, ch.pos)
		if place then
			player:sendCancelMessage(Chaos.t(player, "You cannot open a cursed chest in %s.", place))
			return true
		end
		CC.startEvent(player, ch)
	elseif ch.state == "running" then
		player:sendCancelMessage(Chaos.t(player, "The cursed chest is awake: horde %d/%d is upon you.", ch.ev.horde,
			K.hordeCount(c)))
	elseif ch.state == "won" then
		claim(player, ch)
	end
	return true
end

local useAction = Action()
function useAction.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	local ok, res = pcall(CC.use, player, item)
	if not ok then
		print("[Chaos cursed chest] use: " .. tostring(res))
		pcall(function() player:sendCancelMessage(Chaos.t(player, "The cursed chest could not be used. Try again.")) end)
	end
	return true
end
useAction:aid(ChaosCursedChestConfig.chest.actionId)
useAction:register()

-- ------------------------------------------------------------------ engine hooks
local drop = EventCallback
drop.onDropLoot = function(self, corpse)
	local owner = corpse and Player(corpse:getCorpseOwner())
	if not owner then
		return
	end
	try("kill", CC.onKill, self, owner, corpse)
end
-- after the stock loot (0), the Chaos loot layer (1), the gold bonus (2) and autoloot (3)
drop:register(5)

local death = CreatureEvent("ChaosCursedChestDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local id = creature:getId()
	local ch = CC.tagged[id]
	if ch and ch.ev then
		ch.ev.monsters[id] = nil
	end
	CC.tagged[id] = nil
	if CC.levels[id] then
		addEvent(function(cid) CC.levels[cid] = nil end, 10000, id)
	end
	if ChaosAreaGen and ChaosAreaGen.scaled then
		ChaosAreaGen.scaled[id] = nil
	end
	return true
end
death:register()

-- the loop over every chest: a dark effect, the expiry of an unopened chest and of an open one nobody takes
local loopCount = 0
local think = GlobalEvent("ChaosCursedChestThink")
function think.onThink(interval)
	local c = cfg()
	loopCount = loopCount + 1
	local now = nowMs()
	local expired = {}
	for _, ch in pairs(CC.chests) do
		if ch.state == "idle" and now >= ch.expiresAt then
			expired[#expired + 1] = ch
		elseif ch.state == "won" and K.claimDone(ch.ev, now) then
			expired[#expired + 1] = ch
		elseif not chestItem(ch) then
			expired[#expired + 1] = ch
		elseif ch.ev and ch.ev.state == "won" and not ch.ev.reminded and ch.ev.claimUntil - now <= (c.event.remindSec or 30) * 1000 then
			ch.ev.reminded = true
			for _, pid in ipairs(K.unclaimed(ch.ev)) do
				local p = Player(pid)
				if p then
					say(p, "The cursed chest still holds your share: use it within %d seconds or it crumbles.",
						math.max(1, math.floor((ch.ev.claimUntil - now) / 1000)))
				end
			end
			fx(ch.pos, (loopCount % 3 == 0) and c.chest.loopEffectAlt or c.chest.loopEffect)
		else
			fx(ch.pos, (loopCount % 3 == 0) and c.chest.loopEffectAlt or c.chest.loopEffect)
		end
	end
	try("aura", CC.syncAuras)
	for _, ch in ipairs(expired) do
		local ev = ch.ev
		if ev and ev.state == "running" then
			clearMonsters(ev, true)
			K.fail(ev, "lost")
			tellAll(ev, "The cursed chest vanished. Its hordes fade.")
		elseif ev and ev.state == "won" then
			-- nobody is left unserved without being told
			for _, pid in ipairs(K.unclaimed(ev)) do
				local p = Player(pid)
				if p then
					say(p, "The cursed chest crumbled before you took your share.")
					toast(p, "The cursed chest crumbled before you took your share.")
				end
			end
		end
		remove(ch)
	end
	return true
end
think:interval(ChaosCursedChestConfig.chest.loopMs or 1500)
think:register()

-- ------------------------------------------------------------------ staff
-- /cursedchest              a chest next to you (the pool is your own area's monsters and the themed list)
-- /cursedchest roll <tier>, <monster level>[, <n>]   the chance for you and n simulated kills (nothing is created)
local talk = TalkAction("/cursedchest")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getAccountType() < ACCOUNT_TYPE_GOD then
		return true
	end
	local c = cfg()
	param = (param or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if param == "" then
		local level = K.areaLevel(c, player:getLevel(), player:getLevel())
		local ch = CC.spawnChest(player, player:getPosition(), {
			name = "Test Monster", pool = pool(player:getPosition(), "Rotworm", level), gear = {}, monsterLevel = level, tier = "normal"
		})
		if not ch then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "No free tile next to you.")
			return false
		end
		ch.level = level
		CC.announceSpawn(ch, player)
		return false
	end
	local tier, level, n = param:match("^roll%s+(%a+)%s*,%s*(%d+)%s*,?%s*(%d*)$")
	if tier then
		n = math.min(tonumber(n) or 10000, 1000000)
		local pct = K.chance(c, tier, player:getLevel(), tonumber(level))
		local hits = 0
		for _ = 1, n do
			if K.roll(c, {tier = tier, playerLevel = player:getLevel(), monsterLevel = tonumber(level)}, rand) then
				hits = hits + 1
			end
		end
		player:sendTextMessage(MESSAGE_INFO_DESCR, string.format(
			"Cursed Chest chance %.2f%% per kill (%s, level %s vs %d); %d chests in %d kills.", pct, tier, level,
			player:getLevel(), hits, n))
		return false
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, "/cursedchest | /cursedchest roll <tier>, <monster level>[, <n>]")
	return false
end
talk:separator(" ")
talk:register()
