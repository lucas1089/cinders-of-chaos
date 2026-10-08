-- Treasure goblins: a cowardly, very rare monster that replaces a natural respawn, never attacks, flees and blinks
-- once hit, escapes through a portal after ~18 s, and drops a hoard (gold, Chaos Orbs, a chance of a Divine Orb,
-- 2-4 rarity-rolled gear items through the Chaos loot layer, a raised unique chance) when killed in time.
--
-- * Spawn: own EventCallback.onSpawn (registered first, index -10). A natural map respawn (not a script's
--   Game.createMonster, so rifts, arenas, siege, tower, world boss and ambush copies never roll) of an eligible
--   monster rolls 1 in cfg.spawn.oneIn; on a hit the spawn is cancelled (the spawn block retries after its interval)
--   and a Treasure Goblin is created on that tile, scaled to the replaced monster's level.
-- * Behaviour: the XML makes it non-hostile (it keeps ~4 tiles from players and never attacks) with a runonhealth
--   far above anything; the script keeps its health above that threshold until the first hit, then drops it to the
--   real health, so the engine's own flee logic (keep distance, run from the target) starts exactly on the first hit.
--   A speed boost, blinks (short teleports away from the attackers) and taunts come from the script.
-- * Loot: added to the corpse in the death event (before the engine's onDropLoot, so the stock loot message and
--   autoloot see it), using ChaosLoot (loot.lua) for item find, rarity rolls and uniques.
--
-- Config: treasure_goblin_config.lua. Pure logic: treasure_goblin_core.lua (tests: server/tests/treasure_goblin_test.lua).
-- Exports: ChaosTreasureGoblin.spawn(pos[, opts]) (staff / tests), ChaosTreasureGoblin.alive (id -> state).
-- Optional hooks, called guarded, never created here: ChaosLeaderboard.record(board, player, 1, "add") when Chaos.leaderboardConfig has the board
-- (cfg.leaderboard.board, "goblin"); ChaosNotify.gmBroadcast(player, text) for the appear toast.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ChaosTreasureGoblinConfig = dofile("data/scripts/chaos/treasure_goblin_config.lua")
dofile("data/scripts/chaos/treasure_goblin_core.lua")

ChaosTreasureGoblin = ChaosTreasureGoblin or {}
local TG = ChaosTreasureGoblin
local G = ChaosTreasureGoblinCore
TG.alive = TG.alive or {} -- creature id -> state
TG.spawnState = TG.spawnState or {alive = 0, lastByCell = {}}

local function cfg()
	return ChaosTreasureGoblinConfig
end

local function nowMs()
	if os.mtime then
		return os.mtime()
	end
	return os.time() * 1000
end

local function rand(a, b)
	return math.random(a, b)
end

local function lowerName()
	return cfg().name:lower()
end

local function countAlive()
	local n = 0
	for id in pairs(TG.alive) do
		if Monster(id) then
			n = n + 1
		else
			TG.alive[id] = nil
		end
	end
	return n + (TG.pending or 0)
end

-- monster_tiers.lua must never give the goblin a tier, modifiers or an ambush copy
local function keepOutOfTiers()
	if ChaosTierConfig and ChaosTierConfig.skip then
		ChaosTierConfig.skip[lowerName()] = true
	end
end

-- ------------------------------------------------------------------ area checks
local function call(fn, ...)
	local ok, res = pcall(fn, ...)
	return ok and res
end

-- true when pos is somewhere a goblin must not appear (engine-side part of the exclusions)
function TG.excludedAt(pos)
	local tile = Tile(pos)
	if not tile or not tile:getGround() then
		return true
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) or tile:getHouse() then
		return true
	end
	-- runtime instances built by other modules (guarded: those modules may not be installed)
	if ChaosWorldBoss and ChaosWorldBoss.inside and call(ChaosWorldBoss.inside, pos) then
		return true
	end
	if ChaosRiftCore and ChaosRiftCore.slotOfPos and ChaosRiftConfig and call(ChaosRiftCore.slotOfPos, ChaosRiftConfig, pos) then
		return true
	end
	if ChaosArenaCore and ChaosArenaCore.slotOfPos and Chaos.arenaConfig and call(ChaosArenaCore.slotOfPos, Chaos.arenaConfig, pos) then
		return true
	end
	if ChaosRift and ChaosRift.isInsidePos and call(ChaosRift.isInsidePos, pos) then
		return true
	end
	if ChaosSiege and ChaosSiege.isInsidePos and call(ChaosSiege.isInsidePos, pos) then
		return true
	end
	return false
end

local function isBoss(monster)
	local mt = monster:getType()
	if mt and call(function() return mt:isBoss() end) then
		return true
	end
	local name = monster:getName():lower()
	if ChaosTierConfig and ChaosTierConfig.bosses and ChaosTierConfig.bosses[name] then
		return true
	end
	return false
end

local function isHostile(monster)
	local mt = monster:getType()
	if mt and mt.isHostile then
		local ok, res = pcall(function() return mt:isHostile() end)
		if ok then
			return res and true or false
		end
	end
	return true
end

local function nearbyPlayerLevels(pos, radius)
	local levels = {}
	for _, p in ipairs(Game.getSpectators(pos, false, true, radius, radius, radius, radius)) do
		levels[#levels + 1] = p:getLevel()
	end
	return levels
end

-- gear ids of a monster type's loot table (ChaosLoot.isGearId)
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

-- ------------------------------------------------------------------ messages
local function tell(pos, radius, text, msgType)
	for _, p in ipairs(Game.getSpectators(pos, false, true, radius, radius, radius, radius)) do
		p:sendTextMessage(msgType or MESSAGE_EVENT_ADVANCE, text)
	end
end

local function say(monster, text)
	monster:say(text, TALKTYPE_MONSTER_SAY)
end

local function effect(pos, name, fallback)
	local id = ChaosFx and name and ChaosFx[name] or fallback
	pos:sendMagicEffect(id or CONST_ME_TELEPORT)
end

-- ------------------------------------------------------------------ setup
-- data = {level=, maxHealth=, experience=, name=, gear={ids}} of the replaced monster (all optional)
local function setup(monster, data)
	local c = cfg()
	data = data or {}
	local pos = monster:getPosition()
	local level = data.level or G.areaLevel(c, 0, nearbyPlayerLevels(pos, c.level.playerRadius), data.maxHealth or 0)
	local real = G.realHealth(c, level, data.maxHealth)
	local st = {
		id = monster:getId(), level = level, real = real, bornAt = nowMs(), seen = {}, attackers = {},
		replaced = data.name, replacedExp = data.experience or 0, gear = data.gear or {}
	}
	TG.alive[st.id] = st
	local dormant = G.dormantHealth(c, real)
	monster:setMaxHealth(dormant)
	monster:setHealth(dormant)
	local shader = c.behaviour.shader or 0
	if shader > 0 then
		local outfit = monster:getOutfit()
		outfit.lookShader = shader
		monster:setOutfit(outfit)
	end
	monster:registerEvent("ChaosTreasureGoblinHit")
	monster:registerEvent("ChaosTreasureGoblinDeath")
	effect(pos, "summon_portal", CONST_ME_TELEPORT)
	addEvent(TG.tick, c.behaviour.tickMs, st.id)
	print(string.format("[Chaos goblin] Treasure Goblin at %d,%d,%d (area level %d, health %d, replaced %s)",
		pos.x, pos.y, pos.z, level, real, tostring(data.name)))
	return st
end

-- create a goblin at pos (staff command, tests). opts = setup data; returns the monster or nil
function TG.spawn(pos, opts)
	keepOutOfTiers()
	local monster = Game.createMonster(cfg().name, pos, true, false)
	if not monster then
		return nil
	end
	setup(monster, opts)
	return monster
end

-- ------------------------------------------------------------------ behaviour
local function attackerPositions(st, gpos)
	local list = {}
	for pid in pairs(st.attackers) do
		local p = Player(pid)
		if p and p:getPosition().z == gpos.z then
			list[#list + 1] = p:getPosition()
		end
	end
	if #list == 0 then
		for _, p in ipairs(Game.getSpectators(gpos, false, true, 8, 8, 6, 6)) do
			list[#list + 1] = p:getPosition()
		end
	end
	return list
end

local function blink(monster, st)
	local c = cfg()
	local from = monster:getPosition()
	local r1, r2 = c.behaviour.blinkRange[1], c.behaviour.blinkRange[2]
	local cands = {}
	for dx = -r2, r2 do
		for dy = -r2, r2 do
			local d = math.max(math.abs(dx), math.abs(dy))
			if d >= r1 then
				local p = Position(from.x + dx, from.y + dy, from.z)
				local tile = Tile(p)
				if tile and tile:getGround() and not tile:hasFlag(TILESTATE_PROTECTIONZONE) and tile:getCreatureCount() == 0
					and tile:queryAdd(monster) == RETURNVALUE_NOERROR and from:isSightClear(p, true) then
					cands[#cands + 1] = p
				end
			end
		end
	end
	local to = G.bestBlink(cands, attackerPositions(st, from))
	if not to then
		return false
	end
	from:sendMagicEffect(CONST_ME_POFF)
	monster:teleportTo(to)
	effect(to, nil, CONST_ME_TELEPORT)
	return true
end

local function despawn(monster, st, escaped)
	local c = cfg()
	local pos = monster:getPosition()
	TG.alive[st.id] = nil
	if escaped then
		effect(pos, "summon_portal", CONST_ME_TELEPORT)
		say(monster, c.escapeLine)
		tell(pos, c.behaviour.announceRadius, c.escapeText)
		print(string.format("[Chaos goblin] escaped at %d,%d,%d", pos.x, pos.y, pos.z))
	else
		pos:sendMagicEffect(CONST_ME_POFF)
	end
	monster:remove()
end

local function announce(monster, st)
	local c = cfg()
	local pos = monster:getPosition()
	local r = c.behaviour.announceRadius
	local first = next(st.seen) == nil
	for _, p in ipairs(Game.getSpectators(pos, false, true, r, r, r, r)) do
		local pid = p:getId()
		if not st.seen[pid] then
			st.seen[pid] = true
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, c.appearText)
			if c.behaviour.toast and ChaosNotify and ChaosNotify.gmBroadcast then
				pcall(ChaosNotify.gmBroadcast, p, c.appearText)
			end
		end
	end
	if first and next(st.seen) ~= nil then
		say(monster, c.appearLine)
		effect(pos, nil, CONST_ME_YELLOWENERGY or CONST_ME_MAGIC_GREEN)
	end
end

function TG.tick(id)
	local monster = Monster(id)
	local st = TG.alive[id]
	if not monster or not st then
		TG.alive[id] = nil
		return
	end
	local c = cfg()
	local now = nowMs()
	local due = G.due(c, st, now)
	if due then
		despawn(monster, st, due == "escape")
		return
	end
	announce(monster, st)
	if G.blinkDue(c, st, now, rand) then
		blink(monster, st)
	end
	addEvent(TG.tick, c.behaviour.tickMs, id)
end

-- the first hit: real health (below runonhealth: the engine starts fleeing), speed boost, flee from the attacker
local function wake(monster, st, attacker)
	local c = cfg()
	monster:setMaxHealth(st.real)
	monster:setHealth(st.real)
	local delta = G.fleeSpeedDelta(c, monster:getSpeed(), attacker and attacker:getSpeed() or 0)
	if delta > 0 then
		monster:changeSpeed(delta)
	end
	if attacker then
		pcall(function() monster:selectTarget(attacker) end)
	end
	say(monster, c.taunts[rand(1, #c.taunts)])
	st.lastTaunt = nowMs()
	monster:getPosition():sendMagicEffect(CONST_ME_STUN)
end

local hit = CreatureEvent("ChaosTreasureGoblinHit")
function hit.onHealthChange(creature, attacker, primaryDamage, primaryType, secondaryDamage, secondaryType, origin)
	if primaryType == COMBAT_HEALING then
		return primaryDamage, primaryType, secondaryDamage, secondaryType
	end
	local st = TG.alive[creature:getId()]
	if not st then
		-- a goblin placed without TG.spawn (e.g. /m): scale it now from the players around
		st = setup(creature, nil)
	end
	local c = cfg()
	local now = nowMs()
	local who = attacker and attacker:getMaster() or attacker
	if who and who:isPlayer() then
		st.attackers[who:getId()] = true
	end
	if G.onHit(c, st, now) then
		wake(creature, st, who and who:isPlayer() and who or nil)
	elseif G.tauntDue(c, st, now, rand) then
		say(creature, c.taunts[rand(1, #c.taunts)])
	end
	return primaryDamage, primaryType, secondaryDamage, secondaryType
end
hit:register()

-- ------------------------------------------------------------------ death and loot
local function hasBoard(key)
	local lc = Chaos.leaderboardConfig
	for _, b in ipairs(lc and lc.boards or {}) do
		if b.key == key then
			return true
		end
	end
	return false
end

local function itemName(id)
	local ok, name = pcall(function() return ItemType(id):getName() end)
	return ok and name or tostring(id)
end

local function addStack(corpse, id, count, bonus)
	if count <= 0 then
		return
	end
	local item = corpse:addItem(id, count)
	if item then
		bonus[#bonus + 1] = (count > 1 and (count .. "x ") or "") .. itemName(id)
	end
end

local function rarityName(r)
	local names = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.names
	return names and names[r] or ("Rarity " .. r)
end

-- returns a list of text pieces and the best "kind" for the loot rays (unique / legendary / rare / magic)
function TG.fillCorpse(corpse, st, owner)
	local c = cfg()
	local L = ChaosLoot
	local bonus, kind = {}, "magic"
	local level = st.level
	local itemFind = L and L.itemFindMult and L.itemFindMult(owner) or 1

	for _, coin in ipairs(G.coins(G.goldValue(c, level, rand))) do
		addStack(corpse, coin.id, coin.count, bonus)
	end
	addStack(corpse, c.loot.chaosOrb.id, G.chaosOrbs(c, level, rand), bonus)
	if G.divineOrb(c, itemFind, rand) then
		addStack(corpse, c.loot.divineOrb.id, 1, bonus)
	end

	local maxRarity = ChaosLootConfig and ChaosLootConfig.gear and ChaosLootConfig.gear.maxRarity or 15
	local ids = G.pickGear(c, level, st.gear, G.itemCount(c, rand), rand)
	for _, id in ipairs(ids) do
		local t = G.pickItemTier(c, rand)
		local r = t.floor or 0
		if L and L.upgradeRarity then
			r = math.max(r, L.upgradeRarity(t.tier, L.stockRarity(), itemFind))
		end
		r = math.min(r, maxRarity)
		local placed = false
		if r > 0 and Game.createItemWithRarity then
			local item = Game.createItemWithRarity(id, 1, r)
			if item and corpse:addItemEx(item) == RETURNVALUE_NOERROR then
				placed = true
				bonus[#bonus + 1] = string.format("[%s] %s", rarityName(r), itemName(id))
			end
		end
		if not placed and corpse:addItem(id, 1) then
			bonus[#bonus + 1] = itemName(id)
		end
		if t.tier == "legendary" or (t.tier == "rare" and kind == "magic") then
			kind = t.tier
		end
	end

	-- uniques: the loot layer's roll as a legendary kill of the replaced monster, then the hoard roll
	local uniques = {}
	if L and L.rollUniques then
		uniques = L.rollUniques(c.loot.unique.tier, st.replaced or c.name, level, itemFind * c.loot.unique.mult)
	end
	if #uniques == 0 and L and L.uniqueList and rand(1, 10000) <= c.loot.uniqueHoard.chance * itemFind then
		local cands = G.hoardCandidates(c, L.uniqueList(), level)
		if #cands > 0 then
			uniques = {cands[rand(1, #cands)]}
		end
	end
	for _, e in ipairs(uniques) do
		local item = corpse:addItem(e.id, 1)
		if item then
			if ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			bonus[#bonus + 1] = "{" .. e.name .. "}"
			kind = "unique"
		end
	end
	return bonus, kind
end

local death = CreatureEvent("ChaosTreasureGoblinDeath")
function death.onDeath(creature, corpse, killer, mostDamageKiller, lastHitUnjustified, mostDamageUnjustified)
	local c = cfg()
	local st = TG.alive[creature:getId()]
	TG.alive[creature:getId()] = nil
	if not st then
		return true
	end
	local function asPlayer(cr)
		if cr and cr:getMaster() then
			cr = cr:getMaster()
		end
		return cr and cr:isPlayer() and cr or nil
	end
	local owner = asPlayer(mostDamageKiller) or asPlayer(killer)
	if not owner then
		return true
	end
	local pos = creature:getPosition()
	tell(pos, c.behaviour.announceRadius, string.format(c.killText, owner:getName()))

	local xp = G.experience(c, st.replacedExp, st.level)
	if xp > 0 then
		owner:addExperience(xp, true)
	end

	if corpse and corpse:isContainer() then
		local ok, bonus, kind = pcall(TG.fillCorpse, corpse, st, owner)
		if not ok then
			print("[Chaos goblin] loot failed: " .. tostring(bonus))
		elseif #bonus > 0 then
			local text = "Treasure Goblin hoard: " .. table.concat(bonus, ", ")
			local msgType = _G[c.loot.messageType] or MESSAGE_LOOT or MESSAGE_INFO_DESCR
			local party = owner:getParty()
			if party then
				party:broadcastPartyLoot(text)
			else
				owner:sendTextMessage(msgType, text)
			end
			pos:sendMagicEffect(CONST_ME_GIFT_WRAPS or CONST_ME_FIREWORK_YELLOW or CONST_ME_MAGIC_BLUE)
			-- loot rays: lootfilter.lua reads the corpse in onDropLoot, after this death event, so uniques and
			-- Legendary+ items placed above get their beam without a hook
			print(string.format("[Chaos goblin] %s killed one (area level %d): %s", owner:getName(), st.level, text))
		end
	end

	-- optional hook: leaderboards ("Goblin Slayer" board once Chaos.leaderboardConfig lists it)
	local lb = c.leaderboard
	if lb and ChaosLeaderboard and ChaosLeaderboard.record and hasBoard(lb.board) then
		pcall(ChaosLeaderboard.record, lb.board, owner, 1, lb.mode)
	end
	return true
end
death:register()

-- ------------------------------------------------------------------ the spawn roll
local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	local c = cfg()
	if artificial or self:getName():lower() == lowerName() then
		return true
	end
	local mt = self:getType()
	local info = {
		name = self:getName(), pos = position, natural = not artificial, startup = startup,
		summon = self:getMaster() ~= nil, boss = isBoss(self), hostile = isHostile(self), maxHealth = self:getMaxHealth()
	}
	TG.spawnState.alive = countAlive()
	local ok = G.eligible(c, info, TG.spawnState, os.time())
	if not ok then
		return true
	end
	local mult = ChaosEvents and ChaosEvents.bonus and call(ChaosEvents.bonus, "goblin") or 1
	if not G.rollSpawn(c, rand, tonumber(mult) or 1) then
		return true
	end
	if TG.excludedAt(position) then
		return true
	end
	local level = call(function() return self:getMonsterLevel() end) or 0
	local data = {
		level = G.areaLevel(c, level, nearbyPlayerLevels(position, c.level.playerRadius), info.maxHealth),
		maxHealth = info.maxHealth, name = info.name, gear = gearOf(mt),
		experience = mt and call(function() return mt:getExperience() end) or 0
	}
	G.markSpawn(c, TG.spawnState, position, os.time())
	TG.pending = (TG.pending or 0) + 1
	local pos = Position(position.x, position.y, position.z)
	addEvent(function()
		TG.pending = math.max(0, (TG.pending or 1) - 1)
		keepOutOfTiers()
		local monster = Game.createMonster(c.name, pos, true, false)
		if monster then
			setup(monster, data)
		end
	end, c.spawn.delayMs or 50)
	-- cancel the replaced spawn; its spawn block tries again after its normal interval
	return false
end
spawnCb:register(-10)

-- staff helper: /goblin spawns one next to the GM (god accounts only)
local talk = TalkAction("/goblin")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getAccountType() < ACCOUNT_TYPE_GOD then
		return true
	end
	local pos = player:getPosition()
	pos:getNextPosition(player:getDirection(), 2)
	local level = tonumber(param)
	local monster = TG.spawn(pos, level and {level = level} or nil)
	player:sendTextMessage(MESSAGE_INFO_DESCR, monster and "Treasure Goblin spawned." or "Could not place the goblin.")
	return false
end
talk:separator(" ")
talk:register()
