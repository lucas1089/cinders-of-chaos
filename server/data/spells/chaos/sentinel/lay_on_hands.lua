-- Lay on Hands: a great heal on one party member within 5 sqm: 35% of its maximum health + magic level x 10
-- (ChaosTemplar.cfg.layOnHands). Say a name to choose (saen gal manh "Name"); without one it goes to the party
-- member (or the Sentinel) with the lowest health share. Long cooldown.
dofile('data/spells/scripts/chaos/_templar.lua')
-- status words (data/lib/chaos_status_fx.lua, switch off: nothing more is sent)
if not ChaosStatusFx then
	pcall(dofile, "data/lib/chaos_status_fx.lua")
end

local T = ChaosTemplar
local L = T.cfg.layOnHands

local function inRange(a, b)
	return T.distance(a:getPosition(), b:getPosition()) <= L.range
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local party = player:getParty()
	local target
	local name = TemplarSpell.param(variant)
	if name ~= "" then
		target = Player(name)
		if not target or (target ~= player and (not party or target:getParty() ~= party)) then
			return ChaosSpell.cancel(player, "Lay on Hands heals only you or a member of your party.")
		end
		if not inRange(player, target) then
			return ChaosSpell.cancel(player, RETURNVALUE_TOOFARAWAY)
		end
	else
		local list = {}
		for _, ally in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), L.range, false)) do
			if ally ~= player then
				list[#list + 1] = {id = ally:getId(), health = ally:getHealth(), maxHealth = ally:getMaxHealth()}
			end
		end
		list[#list + 1] = {id = player:getId(), health = player:getHealth(), maxHealth = player:getMaxHealth()}
		local id = T.pickHealTarget(list)
		target = id and Player(id) or player
	end
	local amount = T.layOnHandsAmount(target:getMaxHealth(), player:getMagicLevel())
	ChaosSpell.shoot(player:getPosition(), target:getPosition(), "holy_arrow", CONST_ANI_SMALLHOLY)
	ChaosSpell.healTarget(player, target, amount, amount, Fx("holy_spiral", CONST_ME_HOLYAREA))
	ChaosSpell.vfx(target:getPosition(), "healing_bloom")
	if ChaosStatusFx then
		ChaosStatusFx.send(target:getPosition(), "lay_on_hands", nil, target:getId())
	end
	return true
end
