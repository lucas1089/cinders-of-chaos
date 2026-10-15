-- Smart loot (smartloot.lua, smartloot_core.lua; server/README.md "Smart loot"): every number. Plain table, loaded with
--     ChaosSmartLootConfig = dofile("data/scripts/chaos/smartloot_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then restart (or /reload scripts).
--
-- Owner goal 2026-10-15: drops should feel relevant. A gear drop that nobody near the corpse can wear (a wand for a
-- Warrior party) may turn into a gear item of the same monster's loot table that one of them can wear. The item keeps
-- its rarity and everything the loot layer gives it later. Items never come from outside the monster's own loot table,
-- so the Item Finder, the wiki loot lists and the drop chances per item stay true.
return {
	-- false: no swaps at all
	enabled = true,

	-- chance (percent) that a gear drop nobody near can wear is swapped. 0 = never, 100 = whenever a swap exists.
	swapChance = 60,

	-- who counts as "near": the corpse owner, plus the owner's party members on the same floor within this many
	-- squares of the corpse (a party hunting together gets drops for any of its classes)
	partyRange = 30,

	-- true: the level an item needs counts too (a level 20 character never gets a level 80 sword). false: only the
	-- class counts, so a drop can be kept for later.
	checkLevel = false,

	-- a swap first looks for an item of the same kind (weapon, shield, head, armour, legs, feet, ring, necklace,
	-- quiver). true: when there is none, any wearable gear of the loot table may be picked.
	anySlotFallback = true,

	-- at most this many swaps per corpse
	maxSwapsPerCorpse = 3,

	-- class weighting (owner answer 2026-10-15: "a Templar gets more Templar items than Thief items"). Among the gear of
	-- the loot table, an item made for the killer's class (its equip rule names the class) weighs classSpecific, an
	-- item any class can wear weighs usable, an item the class cannot wear weighs unusable. Used twice:
	--   the Chaos extra rolls (loot.lua step 1): the gear chances of the table are reweighted for the corpse owner and
	--     scaled back so their sum stays the same (as many gear drops as before, more of them for the class);
	--   the swap above: candidates of the wearers' classes weigh classSpecific, generic ones usable.
	-- The stock loot roll (the base callback) keeps the table's own chances. The Item Finder and the wiki show the
	-- table's chances; for a given class the real chance of an extra-roll item is shifted by these weights.
	weights = {classSpecific = 3, usable = 2, unusable = 1},
	-- the stock chance unit's maximum (MAX_LOOTCHANCE): a reweighted entry never goes over it
	maxChance = 100000
}
