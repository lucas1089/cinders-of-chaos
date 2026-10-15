-- Restock (restock.lua, restock_core.lua; client game_hunt, the Restock button; server/README.md "Restock"): every
-- number. Plain table, loaded with
--     ChaosRestockConfig = dofile("data/scripts/chaos/restock_config.lua")
-- Lua 5.1 / LuaJIT and Lua 5.3 compatible.
--
-- Owner goal 2026-10-15: fewer dead trips. Back in town, one button in the Hunt Tracker buys back the potions, runes
-- and spears the hunt session used, at the NPC price (hunt_supplies.lua, generated from the base NPC shops), paid
-- from the gold carried and then the bank. No walk from NPC to NPC.
return {
	enabled = true,

	-- x the NPC price: a small convenience fee for the walk it saves (owner answer 2026-10-15: +10%), shown in the quote
	priceMult = 1.10,

	-- the character must stand in a protection zone (a town, a depot) and outside every instance
	needPz = true,

	-- at most this many supply units are bought with one click
	maxUnits = 5000,

	-- a stack of a stackable supply holds at most this many
	stackSize = 100,

	-- a quote is kept this long (seconds): the purchase is the quote the player saw, never more
	quoteSeconds = 60
}
