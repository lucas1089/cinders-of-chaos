-- Treasure goblins: a cowardly, very rare monster that replaces a natural respawn, never attacks, flees and blinks
-- once hit, escapes through a portal after ~18 s, and drops a hoard (gold, Orbs of Upheaval, a chance of an Orb of Fate,
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
-- * Variants (cfg.variants, by weight): the Hoarder ("Treasure Goblin", the hoard above), the Gem Goblin (gems and
--   Orbs of Sockets) and the Shard Goblin (Rune Shards and orbs); one monster XML each, same behaviour.
-- * Treasure Goblin Chance: the Chaos item modifier "goblinchance" (chaos_item_mods.lua) of the players near a respawn
--   raises its roll (the highest total within cfg.spoor.radius tiles counts, at most +100%).
--
-- Config: treasure_goblin_config.lua. Pure logic: treasure_goblin_core.lua (tests: server/tests/treasure_goblin_test.lua).
-- Exports: ChaosTreasureGoblin.spawn(pos[, opts]) (staff / tests; opts.variant = "hoarder" | "gem" | "shard"),
-- ChaosTreasureGoblin.alive (id -> state), ChaosTreasureGoblin.isGoblinName(name), ChaosTreasureGoblin.spoorAt(pos),
-- ChaosTreasureGoblin.trySpawnRoll(info) (the respawn path, for a scripted test).
-- Optional hooks, called guarded, never created here: ChaosLeaderboard.record(board, player, 1, "add") when Chaos.leaderboardConfig has the board
-- (cfg.leaderboard.board, "goblin"); ChaosNotify.gmBroadcast(player, text) for the appear toast.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
ChaosTreasureGoblinConfig = dofile("data/scripts/chaos/treasure_goblin_config.lua")
dofile("data/scripts/chaos/treasure_goblin_core.lua")
if not ChaosSpeed then
	dofile("data/lib/chaos_speed.lua") -- the speed a player really walks at (engine patch 0018 clamps it)
end

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

function TG.isGoblinName(name)
	return G.isGoblinName(cfg(), name)
end

local function variantOf(keyOrName)
	return G.variant(cfg(), keyOrName) or G.variants(cfg())[1]
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
		for _, v in ipairs(G.variants(cfg())) do
			ChaosTierConfig.skip[v.name:lower()] = true
		end
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
	local variant = variantOf(data.variant or monster:getName())
	local st = {
		id = monster:getId(), level = level, real = real, bornAt = nowMs(), seen = {}, attackers = {},
		replaced = data.name, replacedExp = data.experience or 0, gear = data.gear or {}, variant = variant,
		goblinName = variant.name, spoor = data.spoor or 0
	}
	TG.alive[st.id] = st
	local dormant = G.dormantHealth(c, real)
	monster:setMaxHealth(dormant)
	monster:setHealth(dormant)
	local shader = variant.shader or c.behaviour.shader or 0
	if shader > 0 then
		local outfit = monster:getOutfit()
		outfit.lookShader = shader
		monster:setOutfit(outfit)
	end
	monster:registerEvent("ChaosTreasureGoblinHit")
	monster:registerEvent("ChaosTreasureGoblinDeath")
	effect(pos, "summon_portal", CONST_ME_TELEPORT)
	addEvent(TG.tick, c.behaviour.tickMs, st.id)
	print(string.format("[Chaos goblin] %s at %d,%d,%d (area level %d, health %d, replaced %s, chance bonus %d%%)",
		variant.name, pos.x, pos.y, pos.z, level, real, tostring(data.name), st.spoor))
	return st
end

-- create a goblin at pos (staff command, rifts, tests). opts = setup data (opts.variant: a variant key or name,
-- default the first, the Hoarder); returns the monster or nil
function TG.spawn(pos, opts)
	keepOutOfTiers()
	local variant = variantOf(opts and opts.variant)
	local monster = Game.createMonster(variant.name, pos, true, false)
	if not monster then
		return nil
	end
	local data = {}
	for k, v in pairs(opts or {}) do
		data[k] = v
	end
	data.variant = variant.key
	setup(monster, data)
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
		tell(pos, c.behaviour.announceRadius, string.format(c.escapeText, st.goblinName or c.name))
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
			local text = string.format(c.appearText, st.goblinName or c.name)
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
			if c.behaviour.toast and ChaosNotify and ChaosNotify.gmBroadcast then
				pcall(ChaosNotify.gmBroadcast, p, text)
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
	local delta = G.fleeSpeedDelta(c, monster:getSpeed(), attacker and ChaosSpeed.effective(attacker) or 0)
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
	local c = G.forVariant(cfg(), st.variant)
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

	-- Gem Goblin: gems (tier by area level, as monster gem drops) and Orbs of Sockets
	local gems = G.gemCount(c, level, rand)
	if gems > 0 and ChaosGems and ChaosGems.randomGem then
		local counts, order = {}, {}
		for _ = 1, gems do
			local id = ChaosGems.randomGem(ChaosGems.levelWeights(level), rand)
			if id and rand(1, 100) <= (c.loot.gems.tierUp or 0) then
				id = ChaosGems.combineResult(id) or id
			end
			if id then
				if not counts[id] then
					counts[id] = 0
					order[#order + 1] = id
				end
				counts[id] = counts[id] + 1
			end
		end
		for _, id in ipairs(order) do
			local before = #bonus
			addStack(corpse, id, counts[id], bonus)
			if #bonus > before and ChaosGems.gemName then
				bonus[#bonus] = (counts[id] > 1 and (counts[id] .. "x ") or "") .. ChaosGems.gemName(id)
			end
		end
	end
	local sockets = G.socketOrbs(c, rand)
	if sockets > 0 and ChaosGems and ChaosGems.config and ChaosGems.config.socketOrb then
		local before = #bonus
		addStack(corpse, ChaosGems.config.socketOrb.id, sockets, bonus)
		if #bonus > before then
			bonus[#bonus] = (sockets > 1 and (sockets .. "x ") or "") .. ChaosGems.config.socketOrb.name
		end
	end

	-- Shard Goblin: Rune Shards and crafting orbs
	local shards = G.shardCount(c, level, rand)
	if shards > 0 then
		-- stacks of at most 100 (the cap is 60 anyway)
		addStack(corpse, c.loot.shards.id, math.min(shards, 100), bonus)
	end
	local orbCounts = {}
	for _, key in ipairs(G.orbKeys(c, rand)) do
		local orb = ChaosCrafting and ChaosCrafting.orbByKey and ChaosCrafting.orbByKey[key]
		if orb then
			orbCounts[orb.id] = (orbCounts[orb.id] or 0) + 1
		end
	end
	for id, n in pairs(orbCounts) do
		addStack(corpse, id, n, bonus)
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
		if r > 0 and ChaosCrafting and ChaosCrafting.createItem then
			-- rolled now at the goblin's item level (its area level, as a legendary kill) and kept as text through the
			-- engine's rarity pass of this corpse (ChaosCrafting.shield; item_mods.lua gives it back a tick later)
			local ilvl = ChaosItemMods.sourceLevel({monsterLevel = level, tier = "legendary"})
			local item = ChaosCrafting.createItem(id, r, ilvl)
			if item then
				ChaosCrafting.shield(item)
				if corpse:addItemEx(item) == RETURNVALUE_NOERROR then
					placed = true
					bonus[#bonus + 1] = string.format("[%s] %s", rarityName(r), itemName(id))
					if ChaosItemMods.afterDrop then
						ChaosItemMods.afterDrop(corpse)
					end
				end
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
	tell(pos, c.behaviour.announceRadius, string.format(c.killText, owner:getName(), st.goblinName or c.name))

	local xp = G.experience(c, st.replacedExp, st.level)
	if xp > 0 then
		owner:addExperience(xp, true)
	end

	if corpse and corpse:isContainer() then
		local ok, bonus, kind = pcall(TG.fillCorpse, corpse, st, owner)
		if not ok then
			print("[Chaos goblin] loot failed: " .. tostring(bonus))
		elseif #bonus > 0 then
			local text = (st.goblinName or c.name) .. " hoard: " .. table.concat(bonus, ", ")
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
			print(string.format("[Chaos goblin] %s killed a %s (area level %d): %s", owner:getName(), st.goblinName or c.name,
				st.level, text))
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
-- Treasure Goblin Chance of the players near pos: mult (>= 1), the best bonus in percent, that player's name
function TG.spoorAt(pos)
	local c = cfg()
	local sp = c.spoor
	if not sp or not (ChaosItemMods and ChaosItemMods.playerBonus) then
		return 1, 0, nil
	end
	local r = sp.radius or 24
	local bonuses, bestName, best = {}, nil, 0
	for _, p in ipairs(Game.getSpectators(pos, false, true, r, r, r, r)) do
		local b = ChaosItemMods.playerBonus(p, sp.modKey or "goblinchance") or 0
		bonuses[#bonuses + 1] = b
		if b > best then
			best, bestName = b, p:getName()
		end
	end
	local mult, pct = G.spoorMult(c, bonuses)
	return mult, pct, bestName
end

-- The respawn path without the engine's spawn callback (staff test, /goblin roll): info as G.eligible's, plus
-- rand (optional). Returns the outcome ("goblin", or the reason it did not happen), the roll's 1-in-N and the bonus.
function TG.rollAt(info, rand_)
	local c = cfg()
	TG.spawnState.alive = countAlive()
	local ok, why = G.eligible(c, info, TG.spawnState, os.time())
	if not ok then
		return why, 0, 0
	end
	local mult = tonumber(ChaosEvents and ChaosEvents.bonus and call(ChaosEvents.bonus, "goblin") or 1) or 1
	local hit, oneIn, pct = G.rollWithSpoor(c, rand_ or rand, mult, function()
		local m, p = TG.spoorAt(info.pos)
		return m, p
	end)
	if not hit then
		return "miss", oneIn, pct
	end
	if TG.excludedAt(info.pos) then
		return "area", oneIn, pct
	end
	return "goblin", oneIn, pct
end

-- place a goblin for a respawn that rolled one (after the replaced spawn was cancelled)
local function replaceSpawn(position, data)
	local c = cfg()
	G.markSpawn(c, TG.spawnState, position, os.time())
	TG.pending = (TG.pending or 0) + 1
	local pos = Position(position.x, position.y, position.z)
	local variant = G.pickVariant(c, rand)
	data.variant = variant.key
	addEvent(function()
		TG.pending = math.max(0, (TG.pending or 1) - 1)
		keepOutOfTiers()
		local monster = Game.createMonster(variant.name, pos, true, false)
		if monster then
			setup(monster, data)
		end
	end, c.spawn.delayMs or 50)
end

local spawnCb = EventCallback
spawnCb.onSpawn = function(self, position, startup, artificial)
	local c = cfg()
	if artificial or TG.isGoblinName(self:getName()) then
		return true
	end
	local mt = self:getType()
	local info = {
		name = self:getName(), pos = position, natural = not artificial, startup = startup,
		summon = self:getMaster() ~= nil, boss = isBoss(self), hostile = isHostile(self), maxHealth = self:getMaxHealth()
	}
	local outcome, _, spoorPct = TG.rollAt(info)
	if outcome ~= "goblin" then
		return true
	end
	local level = call(function() return self:getMonsterLevel() end) or 0
	replaceSpawn(position, {
		level = G.areaLevel(c, level, nearbyPlayerLevels(position, c.level.playerRadius), info.maxHealth),
		maxHealth = info.maxHealth, name = info.name, gear = gearOf(mt), spoor = spoorPct,
		experience = mt and call(function() return mt:getExperience() end) or 0
	})
	-- cancel the replaced spawn; its spawn block tries again after its normal interval
	return false
end
spawnCb:register(-10)

-- staff helper (god accounts only):
--   /goblin [hoarder|gem|shard] [level]   one goblin next to the GM
--   /goblin roll <monster name>[, n]       n scripted respawn rolls of that monster 2 tiles ahead (default 1):
--                                         reports the 1-in-N after the Treasure Goblin Chance bonus and the outcomes;
--                                         a hit places a goblin as a real respawn would (variant by weight)
--   /goblin dry <monster name>[, n]        the same rolls, nothing placed or marked (measures the odds)
local talk = TalkAction("/goblin")
function talk.onSay(player, words, param)
	if not player:getGroup():getAccess() or player:getAccountType() < ACCOUNT_TYPE_GOD then
		return true
	end
	local c = cfg()
	local pos = player:getPosition()
	pos:getNextPosition(player:getDirection(), 2)
	local mode, roll = param:match("^(%a+)%s+(.+)$")
	if mode ~= "roll" and mode ~= "dry" then
		roll = nil
	end
	if roll then
		local name, n = roll:match("^(.-)%s*,%s*(%d+)$")
		name, n = name or roll, math.min(tonumber(n) or 1, 100000)
		local mt = MonsterType(name)
		if not mt then
			player:sendTextMessage(MESSAGE_INFO_DESCR, "No monster type " .. name .. ".")
			return false
		end
		local hp = call(function() return mt:getMaxHealth() end) or 1000
		local counts, oneIn, pct = {}, 0, 0
		for _ = 1, n do
			local info = {name = mt:getName(), pos = pos, natural = true, startup = false, summon = false, boss = false,
				hostile = true, maxHealth = hp}
			local outcome
			outcome, oneIn, pct = TG.rollAt(info)
			counts[outcome] = (counts[outcome] or 0) + 1
			if outcome == "goblin" and mode == "roll" then
				replaceSpawn(pos, {level = G.areaLevel(c, 0, nearbyPlayerLevels(pos, c.level.playerRadius), hp),
					maxHealth = hp, name = mt:getName(), gear = gearOf(mt), spoor = pct,
					experience = call(function() return mt:getExperience() end) or 0})
			end
		end
		local parts = {}
		for k, v in pairs(counts) do
			parts[#parts + 1] = k .. " " .. v
		end
		table.sort(parts)
		local m
		m, pct = TG.spoorAt(pos)
		oneIn = (c.spawn.oneIn or 0) / m / (tonumber(ChaosEvents and ChaosEvents.bonus and call(ChaosEvents.bonus, "goblin") or 1) or 1)
		local text = string.format("Goblin " .. mode .. " x%d: 1 in %.0f (Treasure Goblin Chance +%d%%): %s", n, oneIn, pct,
			table.concat(parts, ", "))
		player:sendTextMessage(MESSAGE_INFO_DESCR, text)
		print("[Chaos goblin] " .. text)
		return false
	end
	local key, level = param:match("^(%a+)%s*(%d*)$")
	local variant = key and G.variant(c, key)
	if not variant then
		level = param:match("^(%d+)$")
	end
	level = tonumber(level)
	local opts = {variant = variant and variant.key or nil, level = level}
	local monster = TG.spawn(pos, opts)
	player:sendTextMessage(MESSAGE_INFO_DESCR, monster and (monster:getName() .. " spawned.") or "Could not place the goblin.")
	return false
end
talk:separator(" ")
talk:register()
