-- craft_bonus_config.lua: every number of the crafting bonus of the base crafting tables (craft_bonus.lua,
-- craft_bonus_core.lua; server/README.md "Crafting bonus"). Plain table, loaded with
--     ChaosCraftBonusConfig = dofile("data/scripts/chaos/craft_bonus_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts (or restart).
--
-- "Mastery" below is the crafter's skill in the recipe's category minus the recipe's required skill level (never below
-- 0). Both bonuses grow with it, so a recipe pays off more the further the crafter has outgrown it.

return {
	-- the engine skill of each category (the base script's SKILL_* numbers)
	skills = {herbalist = 10, woodcutting = 8, mining = 9, generalcrafting = 7, armorsmith = 11, weaponsmith = 12,
		jewelsmith = 13},

	-- 1. rarity of crafted equipment (every result our item modifiers roll on: ChaosCrafting.isGear, one item a craft).
	-- The rarities are the item system's 1..15 (Common .. Transcendent; ChaosCrafting.config.rarityNames).
	gear = {
		-- chance in percent of each rarity at mastery 0; the rest is a plain item
		odds = {
			{rarity = 1, chance = 12.0}, -- Common
			{rarity = 2, chance = 6.0}, -- Uncommon
			{rarity = 3, chance = 3.0}, -- Rare
			{rarity = 4, chance = 1.2}, -- Epic
			{rarity = 5, chance = 0.4} -- Legendary
		},
		-- every chance x (1 + mastery x perPoint), at most x (1 + maxBonus)
		perPoint = 0.01,
		maxBonus = 0.5,
		-- never above this rarity (Legendary). A legendary monster's gear has floor 5 and bosses floor 6 (loot_config.lua
		-- gear.minRarity), so a craft never beats a boss drop; tests/craft_bonus_test.lua checks it.
		maxRarity = 5,
		-- all rarities together never above this (percent)
		maxTotal = 35,
		-- item level: recipe level + mastery x perMastery, never below what the item type's own required level gives a
		-- plain item (ChaosCrafting.orbLevel), at most `max` (below the T6 gate of 95 in chaos_item_mods.lua tierLevels)
		itemLevel = {perMastery = 0.5, max = 90},
		-- tools stay the stock way: an item our modifiers would call "other" (chaos_item_mods.lua kindOf) that fits no slot
		-- but these (left and right hand: the profession scissors, pickaxes, axes, root hammer and sickle, the mount
		-- scroll). Gloves and belts (their own slot bit) and anything in the ammo slot are equipment.
		toolSlots = 48
	},

	-- 2. bonus yield of potions and runes: on top of the recipe's count. At most one step hits a craft, the best first.
	yield = {
		-- the potions the herbalist tables make (exalted, advanced, divine, mythic health / mana / spirit)
		ids = {28076, 28077, 28078, 28079, 28080, 28081, 28082, 28083, 28088, 28089, 28090, 28091},
		-- any rune (ItemType:isRune) counts too; no stock recipe makes one today
		runes = true,
		-- extra = ceil(count x mult); chance in percent = base + mastery x perPoint, at most max
		steps = {
			{mult = 1.0, base = 0, perPoint = 0.08, max = 8}, -- double
			{mult = 0.5, base = 5, perPoint = 0.25, max = 25} -- +50%
		},
		-- bonus items that do not fit the backpack go to the store inbox
		inboxStack = 100
	}
}
