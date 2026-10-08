-- Test kit: strong gear, uniques, supplies and skills for a test character.
--
--   /testkit                 equip yourself (kit chosen by vocation)
--   /testkit <kind>          kind = mage | knight | paladin
--   /testkit <kind>, <name>  give it to another online player
-- Admins only (ChaosAdmin.isAdmin). Scripts can call ChaosTestKit.give(player[, kind]).
-- Item bonuses of rarity/unique items are applied by the stock rarity script on login or when the
-- player moves the item, so the target is asked to relog after receiving the kit.

if not Chaos then
	dofile("data/scripts/chaos/chaos_constants.lua")
end

ChaosTestKit = ChaosTestKit or {}
local K = ChaosTestKit

local SUPPLIES = {
	{id = 7590, count = 100}, -- great mana potion
	{id = 8473, count = 100}, -- ultimate health potion
	{id = 8472, count = 100}, -- great spirit potion
	{id = 2268, count = 100}, -- sudden death rune
	{id = 2273, count = 100}, -- ultimate healing rune
	{id = 2160, count = 100}, -- crystal coin
	{id = 29856, count = 20}, -- Chaos Orb
	{id = 29857, count = 20} -- Divine Orb
}

-- slot -> server item id. Ids with an entry in ChaosUniqueSpecs become that unique.
K.kits = {
	mage = {
		level = 500, skills = {[SKILL_SHIELD] = 60}, magic = 110,
		slots = {
			[CONST_SLOT_HEAD] = 9778, -- yalahari mask (falcon coif is knight/paladin only)
			[CONST_SLOT_ARMOR] = 11355, -- spellweaver's robe
			[CONST_SLOT_LEGS] = 18400, -- gill legs
			[CONST_SLOT_FEET] = 26133, -- Voidwalker Boots (unique)
			[CONST_SLOT_LEFT] = 27665, -- eldritch wand (druids get the rod below)
			[CONST_SLOT_RIGHT] = 8918, -- spellbook of dark mysteries
			[CONST_SLOT_NECKLACE] = 10218, -- Heart of Cinders (unique)
			[CONST_SLOT_RING] = 10314 -- Cinderclaw Band (unique)
		},
		druidWeapon = 27671 -- eldritch rod
	},
	knight = {
		level = 500, skills = {[SKILL_SWORD] = 120, [SKILL_AXE] = 120, [SKILL_CLUB] = 120, [SKILL_SHIELD] = 110}, magic = 12,
		slots = {
			[CONST_SLOT_HEAD] = 27675, -- Visage of the Pale King (unique)
			[CONST_SLOT_ARMOR] = 27295, -- Wraithplate (unique)
			[CONST_SLOT_LEGS] = 28020, -- Voidscale Legguards (unique)
			[CONST_SLOT_FEET] = 27647, -- Bloodstep Boots (unique)
			[CONST_SLOT_LEFT] = 8209, -- Soulreaper (unique)
			[CONST_SLOT_RIGHT] = 10318, -- Obsidian Aegis (unique)
			[CONST_SLOT_NECKLACE] = 10221, -- Heartbleed Pendant (unique)
			[CONST_SLOT_RING] = 21693 -- Hornbinder Ring (unique)
		}
	},
	paladin = {
		level = 500, skills = {[SKILL_DISTANCE] = 125, [SKILL_SHIELD] = 100}, magic = 30,
		slots = {
			[CONST_SLOT_HEAD] = 27196, -- falcon coif
			[CONST_SLOT_ARMOR] = 12607, -- elite draken mail
			[CONST_SLOT_LEGS] = 27693, -- Nightshade Leggings (unique)
			[CONST_SLOT_FEET] = 27288, -- Maw Treads (unique)
			[CONST_SLOT_LEFT] = 8849, -- Gallowsbolt Crossbow (unique)
			[CONST_SLOT_NECKLACE] = 24851, -- Tear of the Void (unique)
			[CONST_SLOT_RING] = 2206 -- Ring of the Last Ember (unique)
		},
		ammo = {id = 6529, count = 100} -- infernal bolt
	}
}

local function kindOf(player)
	local base = player:getVocation()
	local demoted = base and base:getDemotion()
	local id = (demoted and demoted:getId() > 0) and demoted:getId() or (base and base:getId() or 0)
	if id == 4 then
		return "knight"
	elseif id == 3 then
		return "paladin"
	end
	return "mage" -- sorcerer, druid, illusionist (and no vocation)
end

local function isDruid(player)
	local id = player:getVocation():getId()
	return id == 2 or id == 6
end

local function raiseLevel(player, level)
	if player:getLevel() >= level then
		return
	end
	local l = level - 1
	local need = math.floor((50 * l * l * l - 150 * l * l + 400 * l) / 3)
	player:addExperience(need - player:getExperience(), false)
end

local function raiseSkill(player, skill, target)
	local voc = player:getVocation()
	for _ = 1, 400 do
		local current = player:getSkillLevel(skill)
		if current >= target then
			return
		end
		local need = voc:getRequiredSkillTries(skill, current + 1) - player:getSkillTries(skill)
		player:addSkillTries(skill, math.max(1, need))
	end
end

local function raiseMagic(player, target)
	local voc = player:getVocation()
	for _ = 1, 400 do
		local current = player:getBaseMagicLevel()
		if current >= target then
			return
		end
		local need = voc:getRequiredManaSpent(current + 1) - player:getManaSpent()
		player:addManaSpent(math.max(1, need))
	end
end

local function makeItem(player, id, count, slot)
	local item = player:addItem(id, count or 1, false, 1, slot)
	if item and ChaosMakeUnique then
		ChaosMakeUnique(item)
	end
	return item
end

-- returns a short summary
function K.give(player, kind)
	kind = K.kits[kind] and kind or kindOf(player)
	local kit = K.kits[kind]

	-- a fresh backpack first: whatever does not fit an occupied slot goes into it
	local bag = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not bag then
		bag = player:addItem(2365, 1, false, 1, CONST_SLOT_BACKPACK) -- backpack of holding
	end

	local equipped, packed = 0, 0
	for slot, id in pairs(kit.slots) do
		if slot == CONST_SLOT_LEFT and kind == "mage" and isDruid(player) then
			id = kit.druidWeapon
		end
		if player:getSlotItem(slot) then
			local item = bag and bag:addItem(id, 1)
			if item and ChaosMakeUnique then
				ChaosMakeUnique(item)
			end
			packed = packed + 1
		elseif makeItem(player, id, 1, slot) then
			equipped = equipped + 1
		end
	end
	if kit.ammo then
		if player:getSlotItem(CONST_SLOT_AMMO) then
			if bag then bag:addItem(kit.ammo.id, kit.ammo.count) end
		else
			makeItem(player, kit.ammo.id, kit.ammo.count, CONST_SLOT_AMMO)
		end
	end
	if bag then
		local supplies = bag:addItem(2002, 1) -- blue backpack with the supplies
		for _, s in ipairs(SUPPLIES) do
			(supplies or bag):addItem(s.id, s.count)
		end
	end

	raiseLevel(player, kit.level)
	for skill, target in pairs(kit.skills) do
		raiseSkill(player, skill, target)
	end
	raiseMagic(player, kit.magic)
	-- health/mana as the vocation would have them at this level (level 8 sample: 185 / 90)
	local voc, levels = player:getVocation(), math.max(0, player:getLevel() - 8)
	player:setMaxHealth(185 + levels * voc:getHealthGain())
	player:setMaxMana(90 + levels * voc:getManaGain())
	player:addHealth(player:getMaxHealth())
	player:addMana(player:getMaxMana())
	player:getPosition():sendMagicEffect(CONST_ME_HOLYAREA)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE,
		string.format("Test kit (%s): %d items equipped, %d in the backpack, skills raised. Relog to apply item bonuses.", kind, equipped, packed))
	return kind
end

local talk = TalkAction("/testkit")
function talk.onSay(player, words, param)
	if not (ChaosAdmin and ChaosAdmin.isAdmin(player)) then
		return true
	end
	local kind, name = param:match("^%s*([%a]*)%s*,?%s*(.-)%s*$")
	local target = player
	if name and name ~= "" then
		target = Player(name)
		if not target then
			player:sendCancelMessage("Player " .. name .. " is not online.")
			return false
		end
	end
	local given = K.give(target, kind ~= "" and kind:lower() or nil)
	if target ~= player then
		player:sendTextMessage(MESSAGE_INFO_DESCR, "Test kit (" .. given .. ") given to " .. target:getName() .. ".")
	end
	return false
end
talk:separator(" ")
talk:register()
