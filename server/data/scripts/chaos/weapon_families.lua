-- weapon_families.lua: the engine half of the melee weapon families (O454; rules: weapon_families_core.lua, numbers:
-- weapon_families_config.lua, tests: tests/weapon_families_test.lua, server/README.md "Weapon families (O454)").
-- weapon_styles.lua calls ChaosWeaponFamiliesGlue.hit for the basic melee hit of a sword, axe or club (origin melee, not a
-- spell's weapon strike, not an extra hit of a keystone) after its own styling. This file does what the rules decide:
--   * sword: the hit is scaled (the interval it was swung at over the interval without tempo, plus the edge), and the haste of the
--     stacks is set as the "tempo" source of the player attack speed bonus (ChaosItemMods.setPlayerAttackSpeed, engine patch
--     0078); a timer ends it when the hits stop
--   * axe: one look at the tiles next to the target (the call the arrow splash and the extra projectile use), at most
--     ChaosAttackRate 1.5 times a second, then each neighbour takes its share one tick later (ORIGIN_NONE inside the
--     keystone guard: no tree bonus twice, no tempo, no cleave of a cleave)
--   * club: a stun (the condition monk_combat.lua cancels attacks for) or, on a boss, a short slow, one tick later; the rest
--     after it is the condition timer Iron Palm uses, so the two share it
-- The damage dealt from this file (the cleave) shows in the combat log as "Axe cleave" (combatlog_config.lua).
-- Nothing here runs for the Monk line, fists, launchers, wands, spells or a keystone's extra hit.

if not ChaosWeaponFamilies then
	dofile("data/scripts/chaos/weapon_families_core.lua")
end
if not ChaosAttackRate then
	dofile("data/scripts/chaos/attack_rate_core.lua")
end

ChaosWeaponFamiliesGlue = ChaosWeaponFamiliesGlue or {}
local G = ChaosWeaponFamiliesGlue
local F = ChaosWeaponFamilies

local states = {} -- player id -> tempo state (weapon_families_core.lua F.tempoStep)
G.states = states

local function nowMs()
	return os.mtime and os.mtime() or os.time() * 1000
end

local function scale(value, factor)
	local v = math.floor(math.abs(value) * factor + 0.5)
	return value < 0 and -v or v
end

local function vocationId(player)
	local ok, id = pcall(function() return player:getVocation():getId() end)
	return ok and id or nil
end

local function daze()
	return F.config.families.club.daze
end

local function hasTimer(creature, subId)
	return creature:getCondition(CONDITION_ATTRIBUTES, CONDITIONID_COMBAT, subId) ~= nil
end

-- the monsters next to the target (ids, ascending), not a player's summon. The call is the one of the extra projectile in
-- weapon_styles.lua, with the range of the 3x3 around the target.
local function neighbours(target)
	local list = {}
	local id = target:getId()
	for _, c in ipairs(Game.getSpectators(target:getPosition(), false, false, 1, 1, 1, 1) or {}) do
		if c:isMonster() and c:getId() ~= id and c:getHealth() > 0 then
			local master = c:getMaster()
			if not (master and master:isPlayer()) then
				list[#list + 1] = c:getId()
			end
		end
	end
	table.sort(list)
	return list
end

local function isBoss(creature)
	local ok, boss = pcall(function() return creature:getType():isBoss() end)
	return F.isBoss(ok and boss == true, creature:getMaxHealth())
end

-- ------------------------------------------------------------------------------------------------------------------ tempo
-- the swing interval (ms) now and without the tempo haste: the weapon's own interval, the vocation, dexterity and the player
-- attack speed bonus (item_mods.lua effectiveInterval, the engine's Player::getAttackSpeed). nil, nil when it cannot be told.
local function intervals(player, weapon, weaponItem)
	local M = ChaosItemMods
	if not (M and M.effectiveInterval and M.playerSpeed and M.playerAttackSpeed) then
		return nil, nil
	end
	local ok, now, base = pcall(function()
		local voc = player:getVocation()
		local dex = CHARSTAT_DEXTERITY and player.getCharacterStat and player:getCharacterStat(CHARSTAT_DEXTERITY) or 0
		local typeSpeed = weapon:getAttackSpeed() or 0
		local own = weaponItem:getAttribute(ITEM_ATTRIBUTE_ATTACK_SPEED) or 0
		if own == 0 then
			own = typeSpeed
		end
		local row = M.playerSpeed[player:getId()]
		local live = row and row.total or 0
		return (M.effectiveInterval(typeSpeed, own, voc:getAttackSpeed(), dex, nil, live)),
			(M.effectiveInterval(typeSpeed, own, voc:getAttackSpeed(), dex, nil, M.playerAttackSpeed(player)))
	end)
	if ok then
		return now, base
	end
	return nil, nil
end

local function setHaste(player, st, pct)
	if st.applied == pct then
		return
	end
	local M = ChaosItemMods
	if M and M.setPlayerAttackSpeed then
		local ok, err = pcall(M.setPlayerAttackSpeed, player, "tempo", pct)
		if not ok then
			print("[ChaosWeaponFamilies] " .. tostring(err))
			return
		end
	end
	st.applied = pct
end

-- the haste ends when no hit has come for the window: one timer per player, moved on while the hits go on
local function decay(playerId, st)
	if st.timer then
		return
	end
	st.timer = true
	local window = F.config.families.sword.tempo.windowMs
	local function check()
		local player = Player(playerId)
		if not player then
			states[playerId] = nil
			return
		end
		local left = (st.last or 0) + window - nowMs()
		if left > 0 then
			addEvent(check, left + 20)
			return
		end
		st.timer = false
		F.tempoClear(st)
		setHaste(player, st, 0)
		states[playerId] = nil
	end
	addEvent(check, window + 20)
end

-- ------------------------------------------------------------------------------------------------------------ the effects
local guard = false

local function cleave(playerId, ids, amount, ctype)
	local player = Player(playerId)
	if not player then
		return
	end
	for _, id in ipairs(ids) do
		local victim = Creature(id)
		if victim and victim:getHealth() > 0 then
			-- a share of a hit that had the passive tree's bonuses: the keystone guard keeps the tree from applying twice
			local K = ChaosKeystones
			if K then K.depth = (K.depth or 0) + 1 end
			guard = true
			local ok, err = pcall(doTargetCombatHealth, playerId, victim, ctype, -amount, -amount, CONST_ME_HITAREA, ORIGIN_NONE)
			guard = false
			if K then K.depth = K.depth - 1 end
			if not ok then
				print("[ChaosWeaponFamilies] " .. tostring(err))
			end
		end
	end
end

local function timer(creature, subId, ticks)
	local c = Condition(CONDITION_ATTRIBUTES)
	c:setParameter(CONDITION_PARAM_SUBID, subId)
	c:setParameter(CONDITION_PARAM_TICKS, ticks)
	creature:addCondition(c)
end

local function applyDaze(monsterId, plan)
	local monster = Monster(monsterId)
	if not monster or monster:getHealth() <= 0 then
		return
	end
	local d = daze()
	local c = Condition(CONDITION_PARALYZE)
	c:setParameter(CONDITION_PARAM_TICKS, plan.ms)
	if plan.kind == "stun" then
		c:setParameter(CONDITION_PARAM_SUBID, d.stunSubId)
		c:setFormula(-1, 0, -1, 0)
	else
		c:setParameter(CONDITION_PARAM_SUBID, d.bossSlowSubId)
		c:setFormula(-plan.slow, 0, -plan.slow, 0)
	end
	monster:addCondition(c)
	timer(monster, plan.kind == "stun" and d.immuneSubId or d.bossRestSubId, plan.restMs)
	if plan.kind == "stun" then
		monster:getPosition():sendMagicEffect(CONST_ME_STUN)
	end
	if ChaosPack29Vfx then -- pair 29 (switch off: nothing): the stunned or slowed aura while it lasts
		pcall(ChaosPack29Vfx.hold, monster, plan.kind == "stun" and "stunned" or "slowed", plan.ms)
	end
end

-- ----------------------------------------------------------------------------------------------------------------- the hit
-- player, the monster or player hit, the weapon (ItemType) and its item, the weapon type name ("sword", "axe", "club"), the
-- hit after weapon_styles.lua's rules, its damage type. Returns the hit.
function G.hit(player, creature, weapon, weaponItem, typeName, primaryDamage, secondaryDamage, primaryType)
	if guard then
		return primaryDamage, secondaryDamage
	end
	local family = F.familyOf(typeName)
	if not family then
		return primaryDamage, secondaryDamage
	end
	-- the extra hits of the passive tree's keystones are shares of a hit that had its traits
	local K = ChaosKeystones
	if K and (K.depth or 0) > 0 then
		return primaryDamage, secondaryDamage
	end
	local vocId = vocationId(player)
	if not F.affected(vocId) then
		return primaryDamage, secondaryDamage
	end
	local pid = player:getId()
	local st = states[pid]
	if not st then
		st = {}
		-- only a sword keeps a state (the tempo); an axe or a club works on a blank one that ends the tempo, if there is none: nothing
		if family == "sword" then
			states[pid] = st
		end
	end
	local d = daze()
	local now = nowMs()
	local interval, base
	if family == "sword" then
		interval, base = intervals(player, weapon, weaponItem)
	end
	local neighbourIds
	local plan = F.plan(st, {
		family = family, vocId = vocId, pvp = creature:isPlayer(), targetId = creature:getId(), now = now,
		intervalNow = interval, intervalBase = base,
		neighbors = function()
			neighbourIds = neighbours(creature)
			return #neighbourIds
		end,
		gate = function(key) return ChaosAttackRate.gate(pid, key) end,
		boss = function() return isBoss(creature) end,
		immune = function() return hasTimer(creature, d.immuneSubId) end,
		bossRest = function() return hasTimer(creature, d.bossRestSubId) end
	})
	if not plan then
		return primaryDamage, secondaryDamage
	end
	if plan.factor ~= 1 then
		primaryDamage = scale(primaryDamage, plan.factor)
		secondaryDamage = scale(secondaryDamage, plan.factor)
	end
	if plan.haste ~= nil then
		setHaste(player, st, plan.haste)
		if (plan.stacks or 0) > 0 then
			decay(pid, st)
		end
	end
	if plan.cleave and neighbourIds and #neighbourIds > 0 then
		local amount = F.cleaveAmount(math.abs(primaryDamage) + math.abs(secondaryDamage), plan.cleave.share)
		if amount > 0 then
			local ids = neighbourIds
			for i = #ids, plan.cleave.count + 1, -1 do
				ids[i] = nil
			end
			addEvent(cleave, 0, pid, ids, amount, primaryType)
		end
	end
	if plan.daze then
		addEvent(applyDaze, 0, creature:getId(), plan.daze)
	end
	return primaryDamage, secondaryDamage
end

return G
