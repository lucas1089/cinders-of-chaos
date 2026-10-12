-- Mirror Mend: the Illusionist heals the most hurt party member within 7 sqm (or the one named: saen spek "Name"), and a
-- mirror image of the heal mends the next most hurt (the Illusionist included) for 25% of it. Without a hurt party
-- member it heals the Illusionist. Numbers: ChaosHealing.cfg.mirrorMend (data/scripts/chaos/healing_rules_core.lua).
-- Weaver's Grace and the PvP healing reduction apply through data/scripts/chaos/healing_rules.lua.
dofile('data/spells/scripts/chaos/_common.lua')
if not (ChaosHealing and ChaosHealing.mirrorTargets) then
	dofile('data/scripts/chaos/healing_rules_core.lua')
end

local H = ChaosHealing

local function param(variant)
	local s = variant and (variant.string or (variant.getString and variant:getString())) or ""
	return (tostring(s):gsub('^%s*"?', ''):gsub('"?%s*$', ''))
end

local function entry(c)
	return {id = c:getId(), health = c:getHealth(), maxHealth = c:getMaxHealth()}
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local cfg = H.cfg.mirrorMend
	local pos = player:getPosition()
	local candidates = {}
	for _, ally in ipairs(ChaosSpell.alliesAround(player, pos, cfg.range, false)) do
		if ally:isPlayer() and ally:getHealth() > 0 then
			candidates[#candidates + 1] = entry(ally)
		end
	end
	local namedId
	local name = param(variant)
	if name ~= "" then
		local named = Player(name)
		if not named then
			return ChaosSpell.cancel(player, "That player is not online.")
		end
		local found = false
		for _, c in ipairs(candidates) do
			found = found or c.id == named:getId()
		end
		if not found then
			return ChaosSpell.cancel(player, "Mirror Mend heals only you or a member of your party within 7 sqm.")
		end
		namedId = named:getId()
	end
	local primaryId, mirrorId = H.mirrorTargets(candidates, player:getId(), namedId)
	local primary = primaryId and Creature(primaryId)
	if not primary then
		return ChaosSpell.cancel(player)
	end
	local min, max = H.values(player:getLevel(), player:getMagicLevel(), cfg)
	local amount = math.random(math.floor(min), math.floor(max))
	if primary ~= player then
		ChaosSpell.shoot(pos, primary:getPosition(), "arcane_orb", CONST_ANI_SMALLHOLY)
	end
	ChaosSpell.healTarget(player, primary, amount, amount, Fx("heal_sparkle", CONST_ME_MAGIC_BLUE))
	ChaosSpell.vfx(primary:getPosition(), "regenerating")
	local mirror = mirrorId and Creature(mirrorId)
	if mirror then
		local m = math.floor(amount * cfg.mirror)
		primary:getPosition():sendDistanceEffect(mirror:getPosition(), CONST_ANI_ENERGY)
		ChaosSpell.healTarget(player, mirror, m, m, CONST_ME_PURPLEENERGY)
	end
	return true
end
