-- Chi Ward: spend all chi on a shield of chi around a party member (or yourself) that absorbs damage for 8 s.
--
-- Finisher: absorbs (level x 2.5 + fist x 8) x the finisher scale. `tor qhal "Name"` shields that party member
-- within 5 sqm; without a name it shields the party member within 5 sqm with the lowest health share (you when you
-- have no party). The shield is a timer condition on the recipient (ChaosMonk.ids.subId.ward) and the amount left a
-- storage on it (ChaosMonk.ids.storage.wardAmount); monk_combat.lua absorbs from it. A new ward replaces the old one.

-- the text in the player's language (Chaos.t, i18n_core.lua); English where the helper is not loaded (unit tests)
local function tr(player, key, ...)
	if Chaos and Chaos.t then
		return Chaos.t(player, key, ...)
	end
	if select("#", ...) > 0 then
		return string.format(key, ...)
	end
	return key
end
dofile('data/spells/scripts/chaos/_monk.lua')

local function inReach(player, other)
	local p, o = player:getPosition(), other:getPosition()
	local r = ChaosMonk.cfg.ward.range
	return p.z == o.z and math.max(math.abs(p.x - o.x), math.abs(p.y - o.y)) <= r
end

local function recipient(player, param)
	local party = player:getParty()
	local name = (param or ""):gsub('^%s*"?', ""):gsub('"?%s*$', "")
	if name ~= "" then
		local other = Player(name)
		if not other then
			return nil, "That player is not online."
		end
		if other ~= player and (not party or other:getParty() ~= party) then
			return nil, "You can only ward yourself or a member of your party."
		end
		if not inReach(player, other) then
			return nil, "That party member is too far away."
		end
		return other
	end
	local best, bestShare = player, player:getHealth() / math.max(1, player:getMaxHealth())
	for _, c in ipairs(ChaosSpell.alliesAround(player, player:getPosition(), ChaosMonk.cfg.ward.range, false)) do
		if c:isPlayer() and c ~= player and inReach(player, c) then
			local share = c:getHealth() / math.max(1, c:getMaxHealth())
			if share < bestShare then
				best, bestShare = c, share
			end
		end
	end
	return best
end

function onCastSpell(creature, variant, isHotkey)
	local player = creature:getPlayer()
	if not player then
		return false
	end
	local M = ChaosMonk
	local param = variant and (variant.string or (variant.getString and variant:getString())) or ""
	local target, why = recipient(player, param)
	if not target then
		player:sendCancelMessage(why)
		player:getPosition():sendMagicEffect(CONST_ME_POFF)
		return false
	end
	local spent = MonkSpell.finisher(player)
	if not spent then
		return false
	end
	local amount = M.wardAmount(player:getLevel(), player:getEffectiveSkillLevel(SKILL_FIST), spent)
	target:setStorageValue(M.ids.storage.wardAmount, amount)
	MonkSpell.timer(target, M.ids.subId.ward, M.cfg.ward.durationMs)
	ChaosSpell.vfxOr(target:getPosition(), "shield_bubble", "reflect_aegis", CONST_ME_MAGIC_BLUE)
	if target ~= player then
		player:getPosition():sendDistanceEffect(target:getPosition(), CONST_ANI_SMALLHOLY)
		target:sendTextMessage(MESSAGE_STATUS_SMALL, tr(target, "%s wards you with chi (%d).", player:getName(), amount))
	end
	return true
end
