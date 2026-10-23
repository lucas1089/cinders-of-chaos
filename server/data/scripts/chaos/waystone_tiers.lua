-- Waystone tier maps (server/README.md "Waystone tiers"): 15 tiers from level 1100 to 2500 in three bands of maps; a
-- run's tier sets the level of the monsters of the map it opened, the tier bosses hit harder, the two pillar bosses stay
-- killable away from their pillar, the blocked ways to the tier IV boss levers are cleared at startup, and waystones
-- drop by the run's tier. Numbers and the lists: waystone_tiers_config.lua; pure logic: waystone_tiers_core.lua
-- (tests/waystone_tiers_test.lua).
--
-- * Runs: the base device (tier_maps.lua, patched by tools/patch_waystone_hideout.py part 3) asks WT.optionsFor for the
--   maps of a tier (its band's) and WT.tablets for the tier items VII-XV, and calls WT.startRun when the pads open:
--   the map counts at that tier from then on, and every monster already standing in it is rescaled.
-- * Level: a base tier's monster (or boss) inside a map of that base tier counts at its run's level
--   (ChaosWaystoneTiers.levelOf, read by loot.lua ChaosLoot.monsterLevel: the shown level, the item level of drops,
--   the late-game damage boost, pack combat). The shown level is passed to monster_levels.lua at the spawn
--   (Chaos.spawnLevel, before the placement, index 40 < 50).
-- * Health: at the monster's first think (it has its id there), max health x the engine's level factor; experience:
--   onGainExperience x target / native; damage to players: monster_damage.lua x ChaosWaystoneTiers.damageMultOf.
--   A monster: from its hunting level; a boss: from the level of its band's first tier (its base health), damage also
--   x bossDamage of its base tier.
-- * Drops: loot.lua calls WT.retierDrops: a dropped waystone becomes the tier of the run (or Tier I outside), the
--   run's boss adds one of the next tier. Inside a run each gets a rarity and modifiers (waystone_mods.lua).
-- * Modifiers: the waystone's (waystone_mods.lua) ride on the run: startRun passes them to ChaosWaystoneMods.begin,
--   rescale is followed by ChaosWaystoneMods.applyMonster, experience x its bonus.
-- * Pillar bosses: tools/patch_waystone_bosses.py makes their health event call ChaosWaystoneTiers.shielded.
-- Without this file every waystone monster is as in the base. Assumed engine API (TFS 1.4.2): EventCallback onSpawn /
-- onGainExperience, CreatureEvent think / death, GlobalEvent startup, Game.getSpectators, Tile:getItemById,
-- Item:remove, Container:addItem, Monster:setMaxHealth, Monster:setDisplayLevel (engine patch 0040, optional).

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/waystone_tiers_core.lua")

ChaosWaystoneTiers = ChaosWaystoneTiers or {}
local WT = ChaosWaystoneTiers
local K = ChaosWaystoneTiersCore
WT.config = dofile("data/scripts/chaos/waystone_tiers_config.lua")
WT.index = K.index(WT.config)
WT.active = WT.active or {} -- map index -> the tier of its last run (kept over a script reload)
WT.applied = WT.applied or {} -- creature id -> the level its health was set to

local INIT = "ChaosWaystoneTierInit"
local DEATH = "ChaosWaystoneTierDeath"

local function typeName(m)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(m) or m:getName()
end

-- {tier, boss, map, run} of a monster (at `pos`, else where it stands), or nil
function WT.entryOf(monster, pos)
	if not monster then
		return nil
	end
	local ok, e = pcall(function()
		if not monster:isMonster() or monster:getMaster() then
			return nil
		end
		return K.classify(WT.config, WT.index, typeName(monster), pos or monster:getPosition(), WT.active)
	end)
	return ok and e or nil
end

local function baseLevel(monster)
	local f = ChaosLoot and (ChaosLoot.baseMonsterLevel or ChaosLoot.monsterLevel)
	if not f then
		return nil
	end
	local ok, lv = pcall(f, monster)
	return ok and tonumber(lv) or nil
end

-- the level of a waystone map's monster or boss (its run's tier). nil: not one.
function WT.levelOf(monster, base, pos)
	return K.level(WT.config, WT.entryOf(monster, pos))
end

-- x on its damage to players (1 for anything else)
function WT.damageMultOf(attacker)
	local e = WT.entryOf(attacker)
	if not e then
		return 1
	end
	return K.damageMult(WT.config, e, not e.boss and baseLevel(attacker) or nil)
end

function WT.tierLevel(t)
	return K.tierLevel(WT.config, t)
end

-- the tier items the base window does not know (VII-XV): {key = server id}; the key is what the window sends back
-- (tier_maps.lua clientToServer; the base keys its six by their client ids, ours by the server id)
function WT.tablets()
	local out = {}
	for _, e in ipairs(WT.config.tiers or {}) do
		if not e.base then
			out[e.item] = e.item
		end
	end
	return out
end

-- the maps a waystone (server id) may open: the base mapping's entries of its band's base tiers, or nil (not a tier)
function WT.optionsFor(serverId, mapping)
	if WT.config.enabled == false then
		return nil
	end
	local t = K.tierOfItem(WT.config, serverId)
	if not t or type(mapping) ~= "table" then
		return nil
	end
	local out = {}
	for _, bt in ipairs(K.baseTiersOf(WT.config, t)) do
		local base = WT.config.tiers[bt]
		for _, opt in ipairs(base and mapping[base.item] or {}) do
			if not K.isRetired(WT.config, opt.area and opt.area.fromPos) then
				out[#out + 1] = opt
			end
		end
	end
	return #out > 0 and out or nil
end

-- sets a monster's health for its level `target` (from `from`: its last level, else its native level); returns true
local function rescale(monster, e, target)
	local id = monster:getId()
	local from = WT.applied[id]
	local f
	if from then
		f = K.scale(WT.config, from, target)
	else
		f = K.factors(WT.config, e, baseLevel(monster))
	end
	if not f then
		return false
	end
	local max = monster:getMaxHealth()
	local hp = K.health(max, f.health)
	if hp and hp ~= max then
		local okH, now = pcall(function() return monster:getHealth() end)
		now = okH and tonumber(now) or max
		monster:setMaxHealth(hp)
		monster:setHealth(from and math.max(1, math.floor(now * hp / max + 0.5)) or hp)
	end
	WT.applied[id] = target
	if monster.setDisplayLevel then
		pcall(function() monster:setDisplayLevel(target) end)
	end
	return true
end

-- the run's modifiers on a monster of its map (waystone_mods.lua): health, speed, Elites at the first think
local function applyMods(monster, e, first)
	if ChaosWaystoneMods and ChaosWaystoneMods.applyMonster then
		local ok, err = pcall(ChaosWaystoneMods.applyMonster, monster, e, first)
		if not ok then
			print("[ChaosWaystoneTiers] modifiers: " .. tostring(err))
		end
	end
end

-- the pads of a run opened (tier_maps.lua, after the waystone was taken): the map of `area` counts at the waystone's
-- tier, the monsters standing in it get that level now; mods: the waystone's modifiers (patch part 4, waystone_mods.lua),
-- the run carries them. Returns the number rescaled (nil: not a waystone map)
function WT.startRun(area, serverId, mods)
	local t = K.tierOfItem(WT.config, serverId)
	local i = area and K.mapOfArea(WT.config, area.fromPos or area.from)
	if not t or not i then
		return nil
	end
	WT.active[i] = t
	-- the opener's Waystone Atlas first (waystone_atlas.lua): the modifiers' bonuses read it
	if ChaosWaystoneAtlas and ChaosWaystoneAtlas.beginRun then
		pcall(ChaosWaystoneAtlas.beginRun, i, t, type(mods) == "table" and mods or {})
	end
	if ChaosWaystoneMods and ChaosWaystoneMods.begin then
		pcall(ChaosWaystoneMods.begin, i, t, type(mods) == "table" and mods or {})
	end
	local m = WT.config.maps[i]
	local cx, cy = math.floor((m.from.x + m.to.x) / 2), math.floor((m.from.y + m.to.y) / 2)
	local hx, hy = math.ceil(math.abs(m.to.x - m.from.x) / 2), math.ceil(math.abs(m.to.y - m.from.y) / 2)
	local n = 0
	local okS, specs = pcall(Game.getSpectators, Position(cx, cy, m.from.z), false, false, hx, hx, hy, hy)
	for _, c in ipairs(okS and specs or {}) do
		if c:isMonster() and WT.applied[c:getId()] then
			local e = WT.entryOf(c)
			local target = K.level(WT.config, e)
			if target and target ~= WT.applied[c:getId()] and rescale(c, e, target) then
				n = n + 1
			end
			applyMods(c, e, false)
		end
	end
	return n
end

-- one waystone of tier t into the corpse; inside a run it gets a rarity and modifiers (waystone_mods.lua), and the
-- run's waystone bonus may bring one more of the same tier
local function addWaystone(corpse, t, monster, inside, extra)
	local e = WT.config.tiers[t]
	if not e then
		return
	end
	local ok, item = pcall(function() return corpse:addItem(e.item, 1) end)
	local WM = ChaosWaystoneMods
	if ok and item and inside and WM and WM.rollDrop then
		pcall(WM.rollDrop, item, t, true, monster)
	end
	if extra ~= false and inside and WM and WM.extraWaystone then
		local okX, more = pcall(WM.extraWaystone, monster)
		if okX and more then
			addWaystone(corpse, t, monster, inside, false)
		end
	end
end

WT.addWaystone = addWaystone -- content_rewards.lua: the boss table's and the trickle's waystones

-- loot.lua, after the level gate: every waystone in the corpse becomes one of the run's tier (Tier I outside the
-- maps; inside, each with a rarity and modifiers); the run's boss adds one of the next tier. isWaystone(item): loot.lua
-- L.isWaystone. Returns the number changed.
function WT.retierDrops(corpse, monster, isWaystone)
	if WT.config.enabled == false or not corpse or not isWaystone then
		return 0
	end
	local e = WT.entryOf(monster)
	local run = e and e.run or nil
	-- the map opener's Waystone Atlas (waystone_atlas.lua): tier step / tierUp, lost drops, the boss's extra ones
	local am
	if e and ChaosWaystoneAtlas and ChaosWaystoneAtlas.fxOfMap then
		local okA, fx = pcall(ChaosWaystoneAtlas.fxOfMap, e.map)
		am = okA and fx or nil
	end
	local WC = ChaosWaystoneAtlasCore
	local maxTier = #WT.config.tiers
	local changed = 0
	for slot = corpse:getSize() - 1, 0, -1 do
		local item = corpse:getItem(slot)
		if item and isWaystone(item) then
			local t = K.dropTier(WT.config, run, math.random(100))
			if am and t and WC then
				t = WC.dropTier(am, t, maxTier, math.random(100))
			end
			local want = t and WT.config.tiers[t]
			if want and (e or item:getId() ~= want.item) then
				local count = item:getCount() or 1
				item:remove()
				for _ = 1, math.max(1, count) do
					if not (am and not e.boss and (am.dropLoss or 0) > 0 and math.random(100) <= am.dropLoss) then
						addWaystone(corpse, t, monster, e ~= nil)
					end
				end
				changed = changed + 1
			end
		end
	end
	if e and e.boss then
		local next = K.bossDrop(WT.config, run)
		if next and am and WC then
			next = WC.dropTier(am, next, maxTier, nil)
		end
		local n = next and 1 or 0
		if am then
			if am.noBossDrop then
				n = 0
			end
			n = n + (am.bossExtraFlat or 0)
			if (am.bossExtra or 0) > 0 and math.random(100) <= am.bossExtra then
				n = n + 1
			end
			next = next or (run and math.min(run + 1, maxTier))
		end
		for _ = 1, n do
			if next then
				addWaystone(corpse, next, monster, true)
				changed = changed + 1
			end
		end
	end
	return changed
end

-- a pillar boss's hit away from its pillar (patch_waystone_bosses.py): the share it keeps; the attacker is told why
local hinted = {}
function WT.shielded(target, source, primary, secondary)
	local p, s = K.shielded(WT.config, primary, secondary)
	local player = source and source.isPlayer and source:isPlayer() and source or nil
	if not player and source and source.getMaster then
		local m = source:getMaster()
		player = m and m:isPlayer() and m or nil
	end
	if player then
		local now = os.time()
		local id = player:getId()
		if not hinted[id] or now - hinted[id] >= (tonumber(WT.config.hintSeconds) or 20) then
			hinted[id] = now
			local boss = target and target:getName() or "The boss"
			player:sendTextMessage(MESSAGE_STATUS_SMALL or MESSAGE_STATUS_DEFAULT,
				Chaos.t(player, "%s is shielded: fight it next to its pillar for full damage.", boss))
		end
	end
	return p, s
end

if EventCallback then
	-- the level shown after the name (monster_levels.lua reads Chaos.spawnLevel at index 50) and the health at the
	-- first think
	local spawnCb = EventCallback
	spawnCb.onSpawn = function(self, position, startup, artificial)
		local e = WT.entryOf(self, position)
		if e then
			local lv = K.level(WT.config, e)
			if lv and Chaos.spawnLevel == nil then
				Chaos.spawnLevel = lv
			end
			pcall(function() self:registerEvent(INIT) end)
		end
		return true
	end
	spawnCb:register(40)

	local xpCb = EventCallback
	xpCb.onGainExperience = function(self, source, exp, rawExp)
		if source and source.isMonster and source:isMonster() then
			local e = WT.entryOf(source)
			if e then
				local f = K.factors(WT.config, e, not e.boss and baseLevel(source) or nil)
				-- x the run's experience bonus (waystone_mods.lua)
				local WM = ChaosWaystoneMods
				local okM, mult = true, 1
				if WM and WM.expMult then
					okM, mult = pcall(WM.expMult, source)
				end
				mult = (f and f.experience or 1) * (okM and tonumber(mult) or 1)
				if mult ~= 1 then
					return math.floor(exp * mult + 1e-9)
				end
			end
		end
		return exp
	end
	xpCb:register(1)
end

if CreatureEvent then
	local init = CreatureEvent(INIT)
	function init.onThink(creature, interval)
		creature:unregisterEvent(INIT)
		local e = WT.entryOf(creature)
		local target = K.level(WT.config, e)
		if target and not WT.applied[creature:getId()] then
			if rescale(creature, e, target) then
				pcall(function() creature:registerEvent(DEATH) end)
				applyMods(creature, e, true)
			end
		end
		return true
	end
	init:register()

	local death = CreatureEvent(DEATH)
	function death.onDeath(creature)
		WT.applied[creature:getId()] = nil
		-- a map's boss: the Waystone Atlas credits everyone inside (waystone_atlas.lua)
		if ChaosWaystoneAtlas and ChaosWaystoneAtlas.onBossDeath then
			local e = WT.entryOf(creature)
			if e and e.boss then
				local ok, err = pcall(ChaosWaystoneAtlas.onBossDeath, e)
				if not ok then
					print("[ChaosWaystoneTiers] atlas: " .. tostring(err))
				end
			end
		end
		return true
	end
	death:type("death")
	death:register()

	local logout = CreatureEvent("ChaosWaystoneTiersLogout")
	function logout.onLogout(player)
		hinted[player:getId()] = nil
		return true
	end
	logout:type("logout")
	logout:register()
end

-- the blocked ways to the tier IV boss levers: the config's items come off the map (each start; skipped when gone)
function WT.clearPaths()
	local n = 0
	for _, c in ipairs(WT.config.clearPath or {}) do
		local tile = Tile(Position(c.x, c.y, c.z))
		local item = tile and tile:getItemById(c.item)
		if item then
			item:remove()
			n = n + 1
		end
	end
	return n
end

if GlobalEvent then
	local startup = GlobalEvent("ChaosWaystoneTiersStartup")
	function startup.onStartup()
		local ok, n = pcall(WT.clearPaths)
		print("[ChaosWaystoneTiers] " .. (ok and (tostring(n) .. " blocking item(s) cleared on the way to the tier IV levers")
			or ("clear paths failed: " .. tostring(n))))
		return true
	end
	startup:register()
end
