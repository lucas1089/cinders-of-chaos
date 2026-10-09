-- ascension.lua: the choice between the two ascended classes of a base class (docs/CLASSES.md).
--
--   !ascend              tells the player the choices
--   !ascend <class>      a base class of level 100+ in a protection zone, out of combat, becomes that ascended class:
--                        Warrior: juggernaut | berserker, Ranger: deadeye | beastmaster, Mystic: elementalist |
--                        illusionist, Thief: ninja | samurai, Monk: shadowfist | ironsage, Necromancer: lich |
--                        bonelord, Templar: inquisitor | sentinel (the last three need the account's class unlock,
--                        class_unlocks.lua)
--
-- The engine knows one promotion per vocation (fromvoc), so the two-way choice is this script: it sets the vocation
-- directly. The choice is final; only the store's Vocation Change (!changevocation <class>, shop_services.lua)
-- changes it later. One exception: a character the class migration moved from Elite Knight / Royal Paladin
-- (class_migration.lua) may switch once, for free, to Berserker / Beastmaster (storage Chaos.classes.storage.freeSwitch).
-- Rules: ChaosClasses.ascensionFor (classes.lua), numbers: Chaos.classes.ascension.
--
-- Health, mana and capacity follow the new vocation's gains (ChaosShopServices.recomputeStats, as the vocation
-- change does). The client learns the new vocation from a fresh basic-data packet (0x9F, the one the server sends at
-- login), so its spell list and action bar switch without a relog.
if not ChaosCommands then
	dofile("data/scripts/chaos/commands_ui_core.lua")
end

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
	C.afterVocationChange(player)
end

-- the class's outfits (Chaos.classes.outfits) for both sexes; with wear, the first one is put on when the character had
-- none of them yet (on a class change; at login only the unlock, the look stays the player's)
function C.giveClassOutfits(player, wear)
	local list = Chaos.classes.outfits and Chaos.classes.outfits[player:getVocation():getId()]
	if not list then
		return 0
	end
	local added, hadOne, names = 0, false, {}
	for _, o in ipairs(list) do
		names[#names + 1] = o.name
		if player:hasOutfit(o.lookType) then
			hadOne = true
		else
			player:addOutfit(o.lookType)
			if player:hasOutfit(o.lookType) then
				added = added + 1
			end
		end
	end
	if added > 0 then
		if wear and not hadOne then
			local look = player:getOutfit()
			look.lookType = list[1].lookType
			player:setOutfit(look)
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "New outfits: " .. table.concat(names, ", ") .. ".")
	end
	return added
end

-- after any vocation change (ascension, the free switch, the store's change): the Ninja's off-hand rule, companions
-- go when the character is no Beastmaster any more, and the client learns the vocation without a relog
function C.afterVocationChange(player)
	C.syncDualWield(player)
	C.giveClassOutfits(player, true)
	if ChaosBeastmaster and ChaosBeastmaster.dismissIfNotBeastmaster then
		ChaosBeastmaster.dismissIfNotBeastmaster(player)
	end
	-- the Necromancer's minions go when the character leaves the line (necro_minions.lua also trims them to the new
	-- class's caps on its own every 0.5 s; this makes it immediate)
	if ChaosNecroMinions and ChaosNecroMinions.onVocationChange then
		ChaosNecroMinions.onVocationChange(player)
	end
	-- the Monk chi HUD (monk_chi_core.lua): shown for the Monk line, hidden when the character left it
	if ChaosMonk and ChaosMonk.sendChi and ChaosMonk.getChi then
		ChaosMonk.sendChi(player, ChaosMonk.getChi(player), true)
	end
	C.sendBasicData(player)
end

local EFFECT = {[8] = CONST_ME_GROUNDSHAKER, [14] = CONST_ME_DRAWBLOOD, [7] = CONST_ME_HOLYDAMAGE,
	[15] = CONST_ME_MAGIC_GREEN, [5] = CONST_ME_FIREAREA, [10] = CONST_ME_PURPLEENERGY, [12] = CONST_ME_MORTAREA,
	[13] = CONST_ME_GROUNDSHAKER, [18] = CONST_ME_MORTAREA, [19] = CONST_ME_STONES, [21] = CONST_ME_MORTAREA,
	[22] = CONST_ME_GROUNDSHAKER, [24] = CONST_ME_HOLYAREA, [25] = CONST_ME_BLOCKHIT}

local talk = {} -- reached from the menu: Info & Services window (commands_ui.lua, id "ascend")
function talk.onSay(player, words, param)
	-- the ascension quest (ascension_quest.lua): players ascend at the Ascendant Oracle; staff and the free switch keep this
	if ChaosAscensionQuest and ChaosAscensionQuest.commandAllowed and not ChaosAscensionQuest.commandAllowed(player) then
		return false
	end
	local voc = player:getVocation()
	local key = Chaos.classes.storage.freeSwitch
	local freeTo = player:getStorageValue(key)
	local newId, how = C.ascensionFor(voc:getId(), player:getLevel(), param, inProtectionZone(player), inCombat(player),
		freeTo > 0 and freeTo or nil)
	if not newId then
		player:sendTextMessage(MESSAGE_INFO_DESCR, how)
		return false
	end
	local newVoc = Vocation(newId)
	if not newVoc then
		player:sendCancelMessage("That vocation does not exist on this server.")
		return false
	end
	-- the class lock (class_unlocks.lua): the Monk, the Necromancer and the Templar need the account's unlock
	if ChaosClassUnlocks and ChaosClassUnlocks.canUseVocation then
		local allowed, lockMessage = ChaosClassUnlocks.canUseVocation(player, newId)
		if not allowed then
			player:sendTextMessage(MESSAGE_INFO_DESCR, lockMessage or "That class is locked. Unlock it in the store.")
			return false
		end
	end
	C.applyVocation(player, newVoc)
	if how == true then
		-- the free switch of the migration is spent (both classes of a line use the same keystones: the tree stays)
		player:setStorageValue(key, -1)
	else
		player:setStorageValue(Chaos.classes.storage.ascended, os.time())
	end
	player:save()
	local pos = player:getPosition()
	pos:sendMagicEffect(CONST_ME_HOLYAREA)
	pos:sendMagicEffect(EFFECT[newId] or CONST_ME_GROUNDSHAKER)
	if how == true then
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
			"You switched for free: you are now %s. This was your only free switch; from now on only the store's Vocation Change changes it.",
			newVoc:getDescription()))
		return false
	end
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format(
		"You have ascended: you are now %s. The choice is final; only the store's Vocation Change can undo it.",
		newVoc:getDescription()))
	Game.broadcastMessage(string.format("%s has ascended to %s.", player:getName(), newVoc:getName()), MESSAGE_EVENT_ADVANCE)
	return false
end
ChaosCommands.register("ascend", function(player, param) return talk.onSay(player, "", param) end)

-- characters that were Ninja or Samurai before the class outfits existed get them at their next login
local outfitLogin = CreatureEvent("ChaosClassOutfitsLogin")
function outfitLogin.onLogin(player)
	pcall(C.giveClassOutfits, player, false)
	return true
end
outfitLogin:register()
