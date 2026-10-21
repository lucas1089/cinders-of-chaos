-- Retired badges (server/README.md "Retired badges"): the glue the base scripts call after tools/patch_badges.py.
--   the base catalyst action (badges_upgrade.lua)  ChaosBadges.onCatalystUse(player, item, target): explains, keeps
--                                                  the catalyst and the target as they are
--   Player:onMoveItem (data/events/scripts/player.lua)  ChaosBadges.onMoveItem(player, item, toPosition): refuses a
--                                                  badge into the deck or badge slot (12, 13)
-- Rules: badges_core.lua (tests/badges_test.lua). Lua 5.1 / LuaJIT compatible.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end
if not Chaos.t then
	dofile("data/scripts/chaos/i18n_core.lua")
end
if not ChaosBadgesCore or not ChaosBadgesCore.refusesMove then
	dofile("data/scripts/chaos/badges_core.lua")
end

ChaosBadges = ChaosBadges or {}
local B = ChaosBadges
local K = ChaosBadgesCore

local function langOf(player)
	return Chaos.lang and Chaos.lang(player) or nil
end

local function priceOf(item)
	local P = rawget(_G, "ChaosItemPrices")
	if not (P and P.sellPrice) then
		return 0
	end
	local ok, price = pcall(P.sellPrice, item, 1)
	return ok and tonumber(price) or 0
end

-- the base action's onUse hands over here first; true = handled (nothing is used up or changed)
function B.onCatalystUse(player, item, target)
	if not (player and item and K.isCatalyst(item:getId())) then
		return false
	end
	player:sendTextMessage(MESSAGE_INFO_DESCR, K.catalystText(priceOf(item), langOf(player)))
	player:getPosition():sendMagicEffect(CONST_ME_POFF)
	return true
end

-- RETURNVALUE_NOTPOSSIBLE for a badge into slot 12 or 13, nil for every other move
function B.onMoveItem(player, item, toPosition)
	if not (item and K.refusesMove(item:getId(), toPosition)) then
		return nil
	end
	if player then
		player:sendTextMessage(MESSAGE_INFO_DESCR, K.equipText(langOf(player)))
	end
	return RETURNVALUE_NOTPOSSIBLE
end

return B
