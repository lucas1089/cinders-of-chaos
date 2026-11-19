-- Waystone endgame (O666; server/README.md "Waystone endgame (O666)"): the engine part. Numbers: waystone_endgame_config.lua; pure
-- logic: waystone_endgame_core.lua (tests/waystone_endgame_test.lua); balance: tools/waystone_endgame_model.py.
--
-- * Band bosses: when the map's own boss dies in a run, the band boss of the run's band may appear on its tile (always at the last tier
--   of the band, else the opener's atlas `bossChance`). It is a real monster of the waystone_bosses folder; WT.entryOf asks
--   E.bandEntry for it, so its level, health, damage and drops follow the run's tier through the same hooks as a map boss
--   (waystone_tiers.lua, content_rewards.lua branch `band`).
-- * First clear and the endgame atlas: the first kill of a tier's map boss gives every player in the map one point (storage block
--   Chaos.storage.waystoneEndgame, +0 bit mask of the tiers paid). Points buy ranks of density / bossChance / chestChance /
--   fragmentChance (+1 the ranks). The opener's ranks shape the run: density clones, the band boss chance, the chest of orbs, and the
--   fragment chance that ChaosWaystoneTiers.onRunCleared hands to O667 (pinnacle fragments; not built here).
-- * Corruption: the Void Orb on a waystone with modifiers (waystone_mods_core.lua W.orbApply -> E.voidApply): it breaks, or the waystone
--   is corrupted for good (attribute ws_corrupt, merged into the run by WM.take).
-- * Actions on the Waystone Atlas opcode (waystone_atlas.lua): eg_open, eg_spend {key}, eg_reset (no talk action: players get no spoken commands).
-- Assumed engine API (TFS 1.4.2): Game.createMonster, Player storage, Position:sendMagicEffect, addEvent.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
dofile("data/scripts/chaos/waystone_endgame_core.lua")

ChaosWaystoneEndgame = ChaosWaystoneEndgame or {}
local E = ChaosWaystoneEndgame
local K = ChaosWaystoneEndgameCore
E.config = dofile("data/scripts/chaos/waystone_endgame_config.lua")
local cfg = E.config
E.bandIds = E.bandIds or {} -- creature id -> {map, run, row}
E.cloneIds = E.cloneIds or {} -- creature id -> map (density clones)
E.cloneCount = E.cloneCount or {} -- map -> clones alive
local OPCODE = ChaosOpcodes and ChaosOpcodes.waystoneAtlas or 159

local function STORE()
	return (Chaos.storage and Chaos.storage.waystoneEndgame) or cfg.storage.base
end

local function TC()
	if ChaosWaystoneTiers and ChaosWaystoneTiers.config then
		return ChaosWaystoneTiers.config
	end
	ChaosWaystoneTiersConfig = ChaosWaystoneTiersConfig or dofile("data/scripts/chaos/waystone_tiers_config.lua")
	return ChaosWaystoneTiersConfig
end

local function log(text)
	print("[Chaos waystone endgame] " .. text)
end

local function rand(a, b)
	return math.random(a, b)
end

-- ======================================================================== the character's state
local function readStorage(player, offset)
	local v = player:getStorageValue(STORE() + offset)
	return (v and v > 0) and v or 0
end

function E.state(player)
	local mask = readStorage(player, 0)
	local ranks = K.ranks(cfg, readStorage(player, 1))
	return {mask = mask, ranks = ranks, points = K.points(mask), free = K.free(cfg, mask, ranks), spent = K.spent(cfg, ranks)}
end

function E.fxOfPlayer(player)
	if not player then
		return K.effects(cfg, {})
	end
	return K.effects(cfg, E.state(player).ranks)
end

-- the opener's effects of a map (the player whose waystone the device took, waystone_atlas.lua WA.runs)
function E.openerOf(map)
	local WA = ChaosWaystoneAtlas
	local run = WA and WA.runs and WA.runs[map]
	local guid = run and run.opener
	local id = guid and WA.online and WA.online[guid]
	local p = id and Player(id)
	return p, guid
end

function E.fxOfMap(map)
	local p = E.openerOf(map)
	return E.fxOfPlayer(p)
end

-- the fragment chance (percent) a cleared run of the map carries, for O667 (the pinnacle fragments): the opener's rank
function E.fragmentChance(map)
	return E.fxOfMap(map).fragmentChance or 0
end

-- ======================================================================== band bosses
-- an entry (waystone_tiers_core.lua K.classify's shape) for a spawned band boss, or nil. native: the level of the tier the file's
-- health was made for (K.factors scales from it to the run's level); boss: it counts as a boss for every hook
function E.bandEntry(monster)
	local info = monster and E.bandIds[monster:getId()]
	if not info then
		return nil
	end
	local tcfg = TC()
	local m = tcfg.maps[info.map]
	return {tier = m and m.tier or 1, boss = true, band = true, map = info.map, run = info.run,
		native = ChaosWaystoneTiersCore.tierLevel(tcfg, info.row.tier), row = info.row}
end

local function spawnTile(pos)
	if ChaosSpawnTile and ChaosSpawnTile.find then
		local spot = ChaosSpawnTile.find(pos, {radius = 3, minRadius = 1, reachFrom = pos, maxPath = 10, box = 5})
		if spot then
			return Position(spot.x, spot.y, spot.z)
		end
	end
	return pos
end

-- the band boss of tier `run` appears on `pos` of map `map`. Returns the monster or nil
function E.spawnBandBoss(map, run, row, pos)
	local at = spawnTile(pos)
	local m = Game.createMonster(row.monster, at, false, true)
	if not m then
		log("could not create " .. tostring(row.monster))
		return nil
	end
	E.bandIds[m:getId()] = {map = map, run = run, row = row}
	pcall(function() at:sendMagicEffect(CONST_ME_TELEPORT or CONST_ME_MAGIC_BLUE) end)
	-- it takes the run's level now, as a map boss at the first think (waystone_tiers.lua init event)
	pcall(function() m:registerEvent("ChaosWaystoneTierInit") end)
	local id = m:getId()
	addEvent(function(cid)
		local c = Creature(cid)
		if c and E.bandIds[cid] and #(ChaosWaystoneAtlas and ChaosWaystoneAtlas.playersInMap and ChaosWaystoneAtlas.playersInMap(map) or {}) == 0 then
			E.bandIds[cid] = nil
			c:remove()
		end
	end, (cfg.bandBossSeconds or 600) * 1000, id)
	return m
end

-- ======================================================================== clears
local function playersOf(map)
	local WA = ChaosWaystoneAtlas
	if WA and WA.playersInMap then
		return WA.playersInMap(map)
	end
	return {}
end

-- ChaosWaystoneTiers.onRunCleared(info) is the hook O667 (pinnacle fragments) reads: see waystone_tiers.lua
local function fire(info)
	local WT = ChaosWaystoneTiers
	if WT and WT.onRunCleared then
		local ok, err = pcall(WT.onRunCleared, info)
		if not ok then
			log("onRunCleared: " .. tostring(err))
		end
	end
end

local function give(player, plan)
	local parts = {}
	for _, o in ipairs(plan) do
		local ok = pcall(function() player:addItem(o.id, o.count) end)
		if ok then
			parts[#parts + 1] = string.format("%dx %s", o.count, o.name)
		end
	end
	return parts
end

-- first clear: a point per player in the map for a tier not paid yet. Returns the number of players credited
function E.creditFirstClear(map, tier)
	local n = 0
	for _, p in ipairs(playersOf(map)) do
		local mask = readStorage(p, 0)
		if not K.tierPaid(mask, tier) then
			p:setStorageValue(STORE(), K.markPaid(mask, tier))
			p:setStorageValue(STORE() + 2, readStorage(p, 2) + 1)
			n = n + 1
			p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "Waystone endgame: first clear of tier %d, +1 atlas point (%d to spend).",
				tier, K.free(cfg, K.markPaid(mask, tier), K.ranks(cfg, readStorage(p, 1)))))
		end
	end
	return n
end

-- WT death event of a map's own boss (e: waystone_tiers_core.lua entry): the first clear, the chest, the band boss, the hook
function E.onMapBossDeath(e, creature)
	if cfg.enabled == false or not e or not e.boss or not tonumber(e.run) then
		return
	end
	if e.band then
		E.bandIds[creature:getId()] = nil
		fire({map = e.map, tier = e.run, level = ChaosWaystoneTiersCore.tierLevel(TC(), e.run), band = true, boss = creature:getName(),
			opener = select(2, E.openerOf(e.map)), fragmentChance = E.fragmentChance(e.map), corrupted = false})
		return
	end
	local opener, guid = E.openerOf(e.map)
	local fx = E.fxOfPlayer(opener)
	local credited = E.creditFirstClear(e.map, e.run)
	local pos = creature:getPosition()
	-- the chest of orbs for everyone in the map
	local chest = false
	if (fx.chestChance or 0) > 0 and rand(1, 100) <= fx.chestChance then
		chest = true
		for _, p in ipairs(playersOf(e.map)) do
			local parts = give(p, K.chestPlan(cfg, e.run, rand))
			if #parts > 0 then
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "The map boss leaves a chest: %s.", table.concat(parts, ", ")))
			end
		end
	end
	local band = false
	if K.bandSpawns(cfg, TC(), e.run, fx.bossChance, rand(1, 100)) then
		local row = K.bandBossOfBand(cfg, TC(), e.run)
		if row then
			addEvent(function(map, run, r, x, y, z)
				E.spawnBandBoss(map, run, r, Position(x, y, z))
			end, 1500, e.map, e.run, row, pos.x, pos.y, pos.z)
			band = true
			for _, p in ipairs(playersOf(e.map)) do
				p:sendTextMessage(MESSAGE_EVENT_ADVANCE, Chaos.t(p, "%s answers the fall of the map's boss.", row.monster))
			end
		end
	end
	fire({map = e.map, tier = e.run, level = ChaosWaystoneTiersCore.tierLevel(TC(), e.run), band = false, boss = creature:getName(),
		opener = guid, fragmentChance = fx.fragmentChance or 0, bandBoss = band, chest = chest, firstClears = credited,
		corrupted = (ChaosWaystoneMods and ChaosWaystoneMods.runOf and (function()
			local r = ChaosWaystoneMods.runOf(e.map)
			return r and r.mods and r.mods.corrupted or false
		end)()) or false})
end

-- density: a dead map monster is replaced by one more (opener's atlas), at most maxAlive of them alive in the map
function E.onMonsterDeath(e, creature)
	if cfg.enabled == false or not e or e.boss then
		return
	end
	local id = creature:getId()
	local wasClone = E.cloneIds[id]
	if wasClone then
		E.cloneIds[id] = nil
		E.cloneCount[wasClone] = math.max(0, (E.cloneCount[wasClone] or 1) - 1)
		return
	end
	local fx = E.fxOfMap(e.map)
	if (fx.density or 0) <= 0 or rand(1, 100) > fx.density or (E.cloneCount[e.map] or 0) >= (cfg.density.maxAlive or 40) then
		return
	end
	local pos = creature:getPosition()
	local name = creature:getName()
	addEvent(function(map, n, x, y, z)
		if (E.cloneCount[map] or 0) >= (cfg.density.maxAlive or 40) then
			return
		end
		local p = Position(x, y, z)
		local spot = ChaosSpawnTile and ChaosSpawnTile.find and ChaosSpawnTile.find(p, {radius = 2, minRadius = 1, reachFrom = p, maxPath = 8, box = 4})
		local m = spot and Game.createMonster(n, Position(spot.x, spot.y, spot.z), false, false)
		if m then
			E.cloneIds[m:getId()] = map
			E.cloneCount[map] = (E.cloneCount[map] or 0) + 1
		end
	end, cfg.density.delayMs or 600, e.map, name, pos.x, pos.y, pos.z)
end

-- ======================================================================== corruption (the Void Orb on a waystone)
-- waystone_mods_core.lua W.orbApply: returns the result list {broken = bool, corrupt = {...}} for ws (mods, tier)
function E.voidApply(wmCfg, ws, defOf, conflict)
	return K.corrupt(cfg, ws.mods, defOf, rand, conflict)
end

function E.bonus()
	return cfg.corrupt.bonus
end

-- ======================================================================== the atlas actions
function E.payload(player, msg)
	local st = E.state(player)
	local stats = {}
	for _, s in ipairs(cfg.atlas.stats) do
		stats[#stats + 1] = {key = s.key, rank = st.ranks[s.key] or 0, max = s.maxRank, per = s.per, text = string.format(s.text, s.per * (st.ranks[s.key] or 0))}
	end
	local paid = {}
	for t = 1, #TC().tiers do
		paid[#paid + 1] = K.tierPaid(st.mask, t) and 1 or 0
	end
	return {points = st.points, spent = st.spent, free = st.free, stats = stats, paid = paid, respec = cfg.atlas.respecGold, msg = msg}
end

local function send(player, msg)
	Chaos.send(player, OPCODE, "eg_state", E.payload(player, msg and Chaos.tx and Chaos.tx(player, msg) or msg))
end

function E.spend(player, key)
	local st = E.state(player)
	local ok, why, ranks = K.spend(cfg, st.mask, st.ranks, key)
	if not ok then
		return false, why == "points" and "You have no atlas point to spend." or (why == "maxed" and "That stat is at its top rank." or "No such stat.")
	end
	player:setStorageValue(STORE() + 1, K.packRanks(cfg, ranks))
	return true
end

function E.reset(player)
	local st = E.state(player)
	if st.spent == 0 then
		return false, "Your endgame atlas is empty."
	end
	local price = cfg.atlas.respecGold or 0
	if price > 0 then
		local paid
		if Chaos.pay then
			paid = Chaos.pay(player, price, true)
		else
			paid = player:removeMoney(price)
		end
		if not paid then
			return false, string.format("A respec costs %d gold.", price)
		end
	end
	player:setStorageValue(STORE() + 1, 0)
	return true
end

function E.onAction(player, action, data)
	if action == "eg_open" then
		send(player)
	elseif action == "eg_spend" then
		local ok, why = E.spend(player, data and data.key)
		send(player, ok and "Rank bought." or why)
	elseif action == "eg_reset" then
		local ok, why = E.reset(player)
		send(player, ok and "Every rank refunded." or why)
	else
		return false
	end
	return true
end

-- ======================================================================== the tester bots' view (tools/tester_helper.lua `!tester wsendgame`)
-- Reads only: whether the engine loaded each band boss's monster file, the tiers, the corruption pool and the atlas of the asker, the hook
function E.probe(player)
	local WT = ChaosWaystoneTiers
	local out = {enabled = cfg.enabled ~= false, tiers = #TC().tiers, bands = #TC().bands, bossTypes = {}, hook = WT ~= nil and WT.onRunCleared ~= nil,
		listeners = WT and WT.clearListeners and #WT.clearListeners or 0}
	for _, b in ipairs(cfg.bandBosses) do
		local okT, mt = pcall(function() return MonsterType(b.monster) end)
		out.bossTypes[#out.bossTypes + 1] = {tier = b.tier, name = b.monster, loaded = okT and mt ~= nil}
	end
	local pool, known = 0, 0
	for _, row in ipairs(cfg.corrupt.pool) do
		pool = pool + 1
		local okD = ChaosRiftCore and ChaosWaystoneMods and ChaosWaystoneMods.config and ChaosRiftCore.modDef(ChaosWaystoneMods.config, row[1])
		known = known + (okD and 1 or 0)
	end
	out.corrupt = {pool = pool, known = known, orbLoaded = ChaosCrafting ~= nil and ChaosCrafting.orbByKey ~= nil and ChaosCrafting.orbByKey[cfg.corrupt.orbKey] ~= nil}
	local st = E.state(player)
	out.atlas = {points = st.points, free = st.free, spent = st.spent, stats = #cfg.atlas.stats}
	return out
end

return E
