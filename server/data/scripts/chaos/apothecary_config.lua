-- The Apothecary of the hub (apothecary.lua places her; the shop: data/npc/Veyra the Apothecary.xml and
-- data/npc/scripts/veyra_the_apothecary.lua; server/README.md "The Apothecary"). Owner 2026-10-23: "no hub de npcs, nao
-- tem nenhum que venda pots ou coisas do tipo. coloque por favor". The stalls' base shop NPCs were cleared
-- ("Hub NPC booths"), so no one in the hub sold potions, runes or the basics. Plain data, no engine calls
-- (tests/apothecary_test.lua and tools/install_apothecary.py read it). Lua 5.1 / LuaJIT and Lua 5.3.
--
-- The goods are listed twice on purpose: here (name, price, level) and in the NPC's XML `shop_buyable` (ids and prices;
-- the XML is what the potion and rune installers, `install_potions.py` and `install_rune_supply.py`, read and extend).
-- tests/apothecary_test.lua fails when the two differ, when a rune is not at the rune supply's price, when a price is
-- not above what any NPC pays for the item (the item price table), or when a single potion is cheaper than the same
-- potion in a store pack.
local C = {}

C.enabled = true

-- the main city only; her stall in the hub (npc_booths_config.lua) first, else next to the temple (npc_place.lua)
C.towns = {2}
C.delayMs = 4300 -- after the service NPCs (4000)
C.offsets = {{-6, -3}, {6, -3}, {-6, 3}, {6, 3}, {-8, 0}, {8, 0}}
C.npc = "Veyra the Apothecary"

-- Potions: the base server's lowest asking price per potion (hunt_supplies.lua) and docs/PRICES.md. The store's packs of
-- 100 stay the bulk way (15 coins for 100 Great Mana Potions, about 800 gold a coin); a single potion here costs its
-- normal gold price. A buyer below `level` is refused at the counter with a line (the potion script refuses to drink
-- it too, and its vocation rules stay its own). Great Spirit is 190, the price the store's pack is built on
-- (docs/PRICES.md), not the cheapest base NPC's 120. The levels are the stock potions' (the base
-- data/actions/scripts/other/potions.lua); the ones for 26029-26031 and 8704 are the stock values, not read here.
C.potions = {
	{id = 8704, name = "small health potion", price = 20, level = 0},
	{id = 7618, name = "health potion", price = 45, level = 0},
	{id = 7620, name = "mana potion", price = 50, level = 0},
	{id = 7588, name = "strong health potion", price = 100, level = 50},
	{id = 7589, name = "strong mana potion", price = 80, level = 50},
	{id = 7591, name = "great health potion", price = 190, level = 80},
	{id = 7590, name = "great mana potion", price = 120, level = 80},
	{id = 8472, name = "great spirit potion", price = 190, level = 80},
	{id = 8473, name = "ultimate health potion", price = 310, level = 130},
	{id = 26029, name = "ultimate mana potion", price = 350, level = 130},
	{id = 26030, name = "ultimate spirit potion", price = 350, level = 130},
	{id = 26031, name = "supreme health potion", price = 500, level = 200},
	{id = 8474, name = "antidote potion", price = 50, level = 0}
}

-- Runes: the ones the store sells in packs (shop_config.lua RUNE_PACKS), at the rune supply's price per rune
-- (data/lib/chaos_rune_supply.lua; install_rune_supply.py sets every NPC to it). The price is not repeated here: the XML
-- carries it and the test reads the supply table. The other runes and the unscribed rune stay with the rune vendors
-- (Raloth, Isora). Names are the supply table's.
C.runes = {2265, 2273, 2261, 2311, 2288, 2315, 2274, 2304, 2268, 2278}

-- The basics. Each price is at least twice the item price table's sell price (no gold loop).
C.basics = {
	{id = 2120, name = "rope", price = 50},
	{id = 2554, name = "shovel", price = 50},
	{id = 2050, name = "torch", price = 2},
	{id = 1988, name = "backpack", price = 20}
}

-- What she buys: the old empty flasks (no potion leaves one any more, README "Potions"), at the item price table's 5
-- gold (the Loot Buyer and the Auto Seller pay the same).
C.flasks = {
	{id = 7634, name = "empty potion flask", price = 5},
	{id = 7635, name = "empty potion flask", price = 5},
	{id = 7636, name = "empty potion flask", price = 5}
}

return C
