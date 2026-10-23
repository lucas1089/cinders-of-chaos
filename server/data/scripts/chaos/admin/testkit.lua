-- Test kit: strong gear, uniques, supplies and skills for a test character.
--
--   /testkit                 equip yourself (kit chosen by vocation)
--   /testkit <kind>          kind = mage | knight | berserker | paladin | beastmaster | thief | ninja | monk |
--                            necromancer | templar
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
	{id = 29856, count = 20}, -- Orb of Upheaval
	{id = 29857, count = 20} -- Orb of Fate
}

-- slot -> server item id. Ids with an entry in ChaosUniqueSpecs become that unique.
K.kits = {
	mage = {
		level = 500, skills = {[SKILL_SHIELD] = 60}, magic = 110,
		slots = {
			[CONST_SLOT_HEAD] = 9778, -- hollowspire mask (talon coif is knight/paladin only)
			[CONST_SLOT_ARMOR] = 11355, -- spellweaver's robe
			[CONST_SLOT_LEGS] = 18400, -- gill legs
			[CONST_SLOT_FEET] = 26133, -- Voidwalker Boots (unique)
			[CONST_SLOT_LEFT] = 27665, -- eldritch wand (druids get the rod below)
			[CONST_SLOT_RIGHT] = 8918, -- spellbook of dark mysteries
			[CONST_SLOT_NECKLACE] = 41641, -- Heart of Cinders (unique)
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
			[CONST_SLOT_NECKLACE] = 41642, -- Heartbleed Pendant (unique)
			[CONST_SLOT_RING] = 21693 -- Hornbinder Ring (unique)
		}
	},
	paladin = {
		level = 500, skills = {[SKILL_DISTANCE] = 125, [SKILL_SHIELD] = 100}, magic = 30,
		slots = {
			[CONST_SLOT_HEAD] = 27196, -- talon coif
			[CONST_SLOT_ARMOR] = 12607, -- elite wyrmblood mail
			[CONST_SLOT_LEGS] = 27693, -- Nightshade Leggings (unique)
			[CONST_SLOT_FEET] = 27288, -- Maw Treads (unique)
			[CONST_SLOT_LEFT] = 8849, -- Gallowsbolt Crossbow (unique)
			[CONST_SLOT_NECKLACE] = 24851, -- Tear of the Void (unique)
			[CONST_SLOT_RING] = 41640 -- Ring of the Last Ember (unique)
		},
		-- bows and crossbows fire without ammunition: a Legendary Haloed Quiver in the off-hand (chaos_archery_config.lua)
		quiver = {id = 29566, rarity = 5}
	}
}

-- a kit made from another: the slots of `from` with `slots` changed (false = the slot stays empty), other fields replaced
local function derive(from, change)
	local kit = {}
	for k, v in pairs(K.kits[from]) do
		kit[k] = v
	end
	kit.slots = {}
	for slot, id in pairs(K.kits[from].slots) do
		kit.slots[slot] = id
	end
	for k, v in pairs(change) do
		if k == "slots" then
			for slot, id in pairs(v) do
				kit.slots[slot] = id or nil
			end
		else
			kit[k] = v
		end
	end
	return kit
end

-- the Berserker wields two-handed weapons only and no shield (add_vocations.py)
K.kits.berserker = derive("knight", {slots = {
	[CONST_SLOT_LEFT] = 2440, -- Executioner's Reckoning (unique, two-handed axe)
	[CONST_SLOT_RIGHT] = false}})
-- the Beastmaster shoots bows only
K.kits.beastmaster = derive("paladin", {slots = {
	[CONST_SLOT_LEFT] = 27230}, -- Doomtide Longbow (unique)
	quiver = {id = 28050, rarity = 5}}) -- a Legendary quiver of level 500
-- the Thief line: one-handed swords, the Ranger's armour; the shuriken spells need no star (docs/CLASSES.md). Samurai: the same kit
K.kits.thief = derive("paladin", {
	skills = {[SKILL_SWORD] = 120, [SKILL_DISTANCE] = 110, [SKILL_SHIELD] = 90}, magic = 30,
	slots = {[CONST_SLOT_LEFT] = 8209}, -- Soulreaper (unique)
	quiver = false})
-- the Ninja: a second blade in the shield hand (dual wield, server/src-patches/0002; without it it goes to the backpack)
K.kits.ninja = derive("thief", {slots = {[CONST_SLOT_RIGHT] = 11395}}) -- Bloodmoon Edge (unique)
-- the Monk line fights with its fists in the Ranger's armour: the level 500 fist weapon in the shield hand (36658, pair of
-- cinderforged talons; docs/CLASSES.md "Monk")
K.kits.monk = derive("paladin", {
	skills = {[SKILL_FIST] = 120, [SKILL_CLUB] = 110, [SKILL_SHIELD] = 90}, magic = 30,
	slots = {[CONST_SLOT_LEFT] = false, [CONST_SLOT_RIGHT] = 36658}, quiver = false})
-- the Necromancer line: wands, rods and the casters' gear (the mage kit with the wand)
K.kits.necromancer = derive("mage", {druidWeapon = false})
-- the Templar line: one-handed sword and shield in the Warrior's armour, some magic level for its holy spells
K.kits.templar = derive("knight", {
	skills = {[SKILL_SWORD] = 120, [SKILL_CLUB] = 120, [SKILL_SHIELD] = 110}, magic = 25})

-- vocation id -> kit (Chaos.classes.ids, docs/CLASSES.md)
K.kindByVocation = {
	[4] = "knight", [8] = "knight", [14] = "berserker",
	[3] = "paladin", [7] = "paladin", [15] = "beastmaster",
	[1] = "mage", [5] = "mage", [10] = "mage",
	[11] = "thief", [12] = "ninja", [13] = "thief",
	[17] = "monk", [18] = "monk", [19] = "monk",
	[20] = "necromancer", [21] = "necromancer", [22] = "necromancer",
	[23] = "templar", [24] = "templar", [25] = "templar"
}

-- the kit of a vocation id: its own row, then its base class's (Chaos.classes.baseOf), else the mage kit
function K.kindFor(vocId)
	local kind = K.kindByVocation[vocId]
	if kind then
		return kind
	end
	local base = Chaos.classes and Chaos.classes.baseOf and Chaos.classes.baseOf[vocId]
	return base and K.kindByVocation[base] or "mage"
end

local function kindOf(player)
	local voc = player:getVocation()
	local id = voc and voc:getId() or 0
	if not K.kindByVocation[id] and voc then
		local demoted = voc:getDemotion()
		if demoted and demoted:getId() > 0 then
			id = demoted:getId()
		end
	end
	return K.kindFor(id)
end

-- the Illusionist (10) carries the druid's kit since the class rework (docs/CLASSES.md): it gets the rod
local function isDruid(player)
	local id = player:getVocation():getId()
	return id == 10
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
	local function pack(id)
		local item = bag and bag:addItem(id, 1)
		if item and ChaosMakeUnique then
			ChaosMakeUnique(item)
		end
		packed = packed + 1
	end
	-- the weapon hand before the shield hand (a Ninja's off-hand blade needs the main one first)
	for _, slot in ipairs({CONST_SLOT_HEAD, CONST_SLOT_NECKLACE, CONST_SLOT_ARMOR, CONST_SLOT_LEGS, CONST_SLOT_FEET,
			CONST_SLOT_RING, CONST_SLOT_LEFT, CONST_SLOT_RIGHT}) do
		local id = kit.slots[slot]
		if id and slot == CONST_SLOT_LEFT and kit.druidWeapon and isDruid(player) then
			id = kit.druidWeapon
		end
		if not id then
			-- nothing for this slot
		elseif player:getSlotItem(slot) then
			pack(id)
		elseif makeItem(player, id, 1, slot) then
			equipped = equipped + 1
		else
			pack(id) -- the slot refused it (an off-hand blade without the dual-wield patch)
		end
	end
	if kit.quiver then
		-- worn in the off-hand next to the kit's bow or crossbow (engine patch 0023), else into the backpack
		local q
		if not player:getSlotItem(CONST_SLOT_RIGHT) then
			q = makeItem(player, kit.quiver.id, 1, CONST_SLOT_RIGHT)
		end
		if not q then
			q = bag and bag:addItem(kit.quiver.id, 1)
		end
		-- rolled like a drop of the kit's level (tiers by item level)
		if q and ChaosCrafting and ChaosCrafting.forge and ChaosItemMods then
			ChaosCrafting.forge(q, kit.quiver.rarity or 5, ChaosItemMods.sourceLevel({monsterLevel = kit.level or 500}))
		end
	end
	if bag then
		local supplies = bag:addItem(2002, 1) -- blue backpack with the supplies
		for _, s in ipairs(SUPPLIES) do
			(supplies or bag):addItem(s.id, s.count)
		end
		for _, s in ipairs(kit.extra or {}) do
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
	Chaos.heal(player, player:getMaxHealth())
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
