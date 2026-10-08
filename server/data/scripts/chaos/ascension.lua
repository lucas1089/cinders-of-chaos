-- ascension.lua: the choice between the two ascended classes of a base class (docs/CLASSES.md).
--
--   !ascend              tells the player the choices
--   !ascend ninja        a Thief of level 100+ in a protection zone, out of combat, becomes a Ninja
--   !ascend samurai      ... or a Samurai
--
-- The engine knows one promotion per vocation (fromvoc), so the two-way choice is this script: it sets the vocation
-- directly. The choice is final; only the store's Vocation Change (!changevocation ninja|samurai, shop_services.lua)
-- changes it later. Rules: ChaosClasses.ascensionFor (classes.lua), numbers: Chaos.classes.ascension.
--
-- Health, mana and capacity follow the new vocation's gains (ChaosShopServices.recomputeStats, as the vocation
-- change does). The client learns the new vocation from a fresh basic-data packet (0x9F, the one the server sends at
-- login), so its spell list and action bar switch without a relog.

if not ChaosClasses then
	dofile("data/scripts/chaos/classes.lua")
end
local C = ChaosClasses

local function inProtectionZone(player)
	local tile = Tile(player:getPosition())
	return tile ~= nil and tile:hasFlag(TILESTATE_PROTECTIONZONE)
end

local function inCombat(player)
	return player:isPzLocked() or player:hasCondition(CONDITION_INFIGHT)
end

-- the login packet's basic data (ProtocolGame::sendBasicData of the 10.98 server): premium, vocation, spell list
function C.sendBasicData(player)
	if not NetworkMessage then
		return false
	end
	local msg = NetworkMessage()
	msg:addByte(0x9F)
	msg:addByte(player:isPremium() and 1 or 0)
	msg:addU32(0)
	msg:addByte(player:getVocation():getClientId())
	msg:addU16(0xFF)
	for spellId = 0, 0xFE do
		msg:addByte(spellId)
	end
	msg:sendToPlayer(player)
	if msg.delete then
		msg:delete()
	end
	return true
end

-- set a vocation and recount health, mana and capacity from the gains (shared with the store's vocation change)
function C.applyVocation(player, newVoc)
	local current = player:getVocation()
	local S = ChaosShopServices
	local stats
	if S and S.recomputeStats then
		stats = S.recomputeStats(player:getLevel(), Chaos.shopServices.vocationBaseLevel, player:getCapacity(),
			{hp = current:getHealthGain(), mana = current:getManaGain(), cap = current:getCapacityGain()},
			{hp = newVoc:getHealthGain(), mana = newVoc:getManaGain(), cap = newVoc:getCapacityGain()})
	end
	player:setVocation(newVoc)
	if stats then
		player:setMaxHealth(stats.health)
		player:setMaxMana(stats.mana)
		player:setCapacity(stats.cap)
	end
	-- setHealth stops at the base maximum; this engine's addHealth takes (damage type, amount) (see shop_services.lua)
	player:setHealth(player:getMaxHealth())
	local missing = player:getMaxHealth() - player:getHealth()
	if missing > 0 then
		pcall(player.addHealth, player, "healing", missing)
	end
	player:addMana(player:getMaxMana())
	C.syncDualWield(player)
	C.sendBasicData(player)
end

local talk = TalkAction("!ascend")
function talk.onSay(player, words, param)
	local voc = player:getVocation()
	local newId, err = C.ascensionFor(voc:getId(), player:getLevel(), param, inProtectionZone(player), inCombat(player))
	if not newId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, err)
		return false
	end
	local newVoc = Vocation(newId)
	if not newVoc then
		player:sendCancelMessage("That vocation does not exist on this server.")
		return false
	end
	C.applyVocation(player, newVoc)
	player:setStorageValue(Chaos.classes.storage.ascended, os.time())
	player:save()
	local pos = player:getPosition()
	pos:sendMagicEffect(CONST_ME_HOLYAREA)
	pos:sendMagicEffect(C.isNinja(newId) and CONST_ME_MORTAREA or CONST_ME_GROUNDSHAKER)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"You have ascended: you are now %s. The choice is final; only the store's Vocation Change can undo it.",
		newVoc:getDescription()))
	Game.broadcastMessage(string.format("%s has ascended to %s.", player:getName(), newVoc:getName()), MESSAGE_EVENT_ADVANCE)
	return false
end
talk:separator(" ")
talk:register()
