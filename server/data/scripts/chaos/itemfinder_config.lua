-- Item finder ("where does this drop"): every number and list of the system. Engine part: itemfinder.lua; pure logic:
-- itemfinder_core.lua (index, search, paging, the shop and spawn parsers) and itemfinder_sources.lua (what the other
-- systems' configs give); tests: server/tests/itemfinder_test.lua; client game_itemfinder; overview: server/README.md
-- "Item finder". Lua 5.1 / LuaJIT and Lua 5.3 compatible. Edit here, then /reload scripts and /itemfinder rebuild.
local C = {}

C.enabled = true
C.opcode = 155 -- ChaosOpcodes.itemFinder (chaos_constants.lua); client game_itemfinder
C.requestMs = 200 -- one request per player per 200 ms (Chaos.limited); the window waits 350 ms after a key first
C.staffGroup = 4 -- /itemfinder (stats, rebuild) needs this group or higher

-- ------------------------------------------------------------------ search and paging
C.minQuery = 2 -- shorter searches are refused (an empty list comes back)
C.maxQuery = 40 -- longer searches are cut
C.perPage = 12 -- items per page of the search
C.rowsPerPage = 15 -- rows per page of one section of an item
C.maxPage = 500 -- page numbers above this are clamped

-- ------------------------------------------------------------------ the sections of an item, in this order
-- k = the row kind the index keeps; the client has the titles (itemfinderlogic.lua) and shows only sections with rows
C.sections = {
	"drop",    -- the Chaos loot layer: the global drop tables (currency, gems, keys), uniques; first: any monster drops
	           -- them (live test winpkg-35: an orb from a Rat named only two monsters)
	"monster", -- monsters and bosses whose loot list has it (the engine's MonsterType:getLoot(), chance x the loot rate)
	"reward",  -- chests and rewards: rifts, the tower, world bosses, invasions, arena, daily reward, achievements, ...
	"craft",   -- recipes that make it: the crafting tables, salvage, gem combining, faction recipes, sigils and keys
	"shop",    -- NPCs that sell it (buy price, NPC, town)
	"store",   -- the Chaos store (Chaos Coins) and the other vendors (honor, embers)
	"gamble",  -- the Gambler's sealed pieces
	"gather",  -- the gathering professions
	"usedin",  -- recipes that need it
	"sellto",  -- NPCs that buy it (sell price, NPC, town)
	"use"      -- other uses (guild boss embers, ...)
}

-- ------------------------------------------------------------------ what players may not see
-- server item ids, monster names and NPC names (lower case) left out of the index; source labels (the row name, lower
-- case) left out too. Achievements marked hidden (achievements_data.lua) are never listed: their rewards are secrets.
C.hidden = {
	items = {},
	monsters = {},
	npcs = {},
	sources = {}
}
-- monsters left out like the bestiary leaves them out (scenery, summons, dummies): bestiary_config.lua minExp,
-- excludeNames and excludePatterns are used when the bestiary is loaded; these patterns are used as well
C.hiddenMonsterPatterns = {"dummy", "^training ", "summon$"}

-- ------------------------------------------------------------------ monsters
C.monstersXml = "data/monster/monsters.xml" -- the names (this engine loads a monster type on first use)
C.lootRate = true -- multiply the loot list chances by the server's loot rate (capped at 100%)
C.areasShown = 2 -- spawn places shown per monster (bestiary_spawns.lua), the busiest first

-- ------------------------------------------------------------------ NPCs
-- NPC shops come from the NPC files of the map's spawn file: <spawn centerx centery centerz><npc name x y z/>, each
-- data/npc/<name>.xml (its name attribute is the shown name, renamed at install), its shop_buyable / shop_sellable
-- parameters and its script (shopModule:addBuyableItem / addSellableItem, or a table of {id, buy, sell}).
-- nil = data/world/<mapName>-spawn.xml (config.lua mapName)
C.spawnFile = nil
C.npcDir = "data/npc/"
C.townNear = 60 -- "in <town>" within this many tiles of its temple, else "near <town>"
C.townsShown = 3 -- places shown per NPC

-- ------------------------------------------------------------------ the base crafting tables (Crafting[category])
C.craftStations = {
	herbalist = "Herbalist table", woodcutting = "Woodcutting table", mining = "Mining table",
	generalcrafting = "Crafting table", jewelsmith = "Jewelsmith table", armorsmith = "Armorsmith table",
	weaponsmith = "Weaponsmith table"
}
C.craftOrder = {"herbalist", "woodcutting", "mining", "generalcrafting", "jewelsmith", "armorsmith", "weaponsmith"}

return C
