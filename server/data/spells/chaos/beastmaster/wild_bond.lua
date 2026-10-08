-- Wild Bond: call your companion (a war wolf; 2 from level 400). Companions already out are called back to your side
-- and healed for half their health.
--
-- The Beastmaster's companion: its health scales with your level, its bites with your level and distance skill, and
-- it attacks your target (data/scripts/chaos/beastmaster.lua, numbers in Chaos.classes.companion).
dofile('data/spells/scripts/chaos/_common.lua')
ChaosSpell.loadClasses()

local function companionType()
	for _, name in ipairs(Chaos.classes.companion.monsters) do
		if MonsterType(name) then
			return name
		end
	end
	return nil
end

local function isCompanion(summon)
	if not summon:isMonster() then
		return false
	end
	local name = summon:getName():lower()
	for _, n in ipairs(Chaos.classes.companion.monsters) do
		if n:lower() == name then
			return true
		end
	end
	return false
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	if player:getSkull() == SKULL_BLACK then
		return ChaosSpell.cancel(player)
	end
	local name = companionType()
	if not name then
		return ChaosSpell.cancel(player, "No companion monster is defined on this server.")
	end
	local C = ChaosClasses
	local pos = player:getPosition()
	local have = {}
	for _, s in ipairs(player:getSummons()) do
		if isCompanion(s) then
			have[#have + 1] = s
		end
	end
	-- the ones already out: back to your side, half their health back
	for _, s in ipairs(have) do
		local spos = s:getPosition()
		if spos.z ~= pos.z or math.max(math.abs(spos.x - pos.x), math.abs(spos.y - pos.y)) > 1 then
			local spots = ChaosSpell.freeAround(pos, pos)
			if spots[1] then
				s:teleportTo(spots[1].pos, true)
			end
		end
		s:addHealth("healing", math.floor(s:getMaxHealth() / 2)) -- this engine: (damage type, amount)
		ChaosSpell.fx(s:getPosition(), "heal_sparkle", CONST_ME_MAGIC_GREEN)
	end
	local want = C.companionCap(player:getLevel()) - #have
	local created = 0
	if want > 0 then
		local hp = C.companionHealth(player:getLevel())
		for _, spot in ipairs(ChaosSpell.freeAround(pos, pos)) do
			if created >= want then
				break
			end
			local m = Game.createMonster(name, spot.pos, false, true)
			if m then
				m:setMaster(player)
				m:setDropLoot(false)
				m:registerEvent("ChaosCompanionGuard")
				m:setMaxHealth(hp)
				m:addHealth("healing", hp)
				local speed = player:getBaseSpeed() - m:getBaseSpeed()
				if speed > 0 then
					m:changeSpeed(speed)
				end
				ChaosSpell.fx(spot.pos, "summon_portal", CONST_ME_TELEPORT)
				created = created + 1
			end
		end
		if created == 0 and #have == 0 then
			return ChaosSpell.cancel(player, RETURNVALUE_NOTENOUGHROOM)
		end
	end
	ChaosSpell.fx(pos, "summon_portal", CONST_ME_MAGIC_GREEN)
	return true
end
