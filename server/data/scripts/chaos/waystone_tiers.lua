-- Waystone tier maps (server/README.md "Waystone tiers"): the tiers I-VI of the base waystone system get monsters of
-- their own level, the tier bosses hit harder by tier, the two pillar bosses stay killable away from their pillar, and
-- the blocked ways to the tier IV boss levers are cleared at startup. Numbers and the lists: waystone_tiers_config.lua;
-- pure logic: waystone_tiers_core.lua (tests/waystone_tiers_test.lua).
--
-- * Level: a tier's monster inside a map of its tier counts at its hunting level x levelMult[tier]
--   (ChaosWaystoneTiers.levelOf, read by loot.lua ChaosLoot.monsterLevel: the shown level, the item level of drops,
--   the late-game damage boost, pack combat). The shown level is passed to monster_levels.lua at the spawn
--   (Chaos.spawnLevel, before the placement, index 40 < 50).
-- * Health: at the monster's first think (it has its id there), max health x the engine's level factor; experience:
--   onGainExperience x target / native; damage to players: monster_damage.lua x ChaosWaystoneTiers.damageMultOf.
-- * Bosses: own level and health (the base files rise by tier), damage x bossDamage[tier].
-- * Pillar bosses: tools/patch_waystone_bosses.py makes their health event call ChaosWaystoneTiers.shielded.
-- Without this file every waystone monster is as before. Assumed engine API (TFS 1.4.2): EventCallback onSpawn /
-- onGainExperience, CreatureEvent think, GlobalEvent startup, Tile:getItemById, Item:remove, Monster:setMaxHealth.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
dofile("data/scripts/chaos/waystone_tiers_core.lua")

ChaosWaystoneTiers = ChaosWaystoneTiers or {}
local WT = ChaosWaystoneTiers
local K = ChaosWaystoneTiersCore
WT.config = dofile("data/scripts/chaos/waystone_tiers_config.lua")
WT.index = K.index(WT.config)

local INIT = "ChaosWaystoneTierInit"

local function typeName(m)
	return Chaos.monsterTypeName and Chaos.monsterTypeName(m) or m:getName()
end

-- {tier, boss} of a monster (at `pos`, else where it stands), or nil
function WT.entryOf(monster, pos)
	if not monster then
		return nil
	end
	local ok, e = pcall(function()
		if not monster:isMonster() or monster:getMaster() then
			return nil
		end
		return K.classify(WT.config, WT.index, typeName(monster), pos or monster:getPosition())
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

-- the tier level of a tier's monster (not a boss); base: its hunting level when the caller has it. nil: not one.
function WT.levelOf(monster, base, pos)
	local e = WT.entryOf(monster, pos)
	if not e or e.boss then
		return nil
	end
	return K.level(WT.config, e.tier, base or baseLevel(monster))
end

-- x on its damage to players (1 for anything else)
function WT.damageMultOf(attacker)
	local e = WT.entryOf(attacker)
	if not e then
		return 1
	end
	return K.damageMult(WT.config, e, not e.boss and baseLevel(attacker) or nil)
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
		if e and not e.boss then
			local lv = K.level(WT.config, e.tier, baseLevel(self))
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
			if e and not e.boss then
				local base = baseLevel(source)
				local target = K.level(WT.config, e.tier, base)
				if target and base then
					local f = K.scale(WT.config, base, target).experience
					if f ~= 1 then
						return math.floor(exp * f + 1e-9)
					end
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
		if e and not e.boss then
			local base = baseLevel(creature)
			local target = K.level(WT.config, e.tier, base)
			if target and base then
				local hp = K.health(creature:getMaxHealth(), K.scale(WT.config, base, target).health)
				if hp and hp ~= creature:getMaxHealth() then
					creature:setMaxHealth(hp)
					creature:setHealth(hp)
				end
			end
		end
		return true
	end
	init:register()

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
