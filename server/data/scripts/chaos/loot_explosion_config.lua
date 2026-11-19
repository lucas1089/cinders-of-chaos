-- Loot explosion (O669; loot_explosion_core.lua, loot_explosion.lua, server/README.md "Loot explosion (O669)"). Returned as a
-- table, loaded as Chaos.lootExplosionConfig. Owner 2026-11-19 (pt-BR): "em vez dos monstros dropar o loot no corpo, da pra fazer
-- eles dropar no chao em volta, uma explosao de loot". The loot bag (corpse_config.lua, O435) is still made and still filled
-- by every loot step; at the end of the chain (onDropLoot index `index`) what is left in it flies out onto the tiles around the
-- death tile. Lua 5.1 / LuaJIT compatible.
return {
	-- the switch: false = the bag as before (every kill leaves its loot in the sack; a /reload is enough, no rebuild)
	enabled = true,

	-- EventCallback onDropLoot index: after the loot layer 1, the auto seller 2, the pouches 2.7, the autoloot 3 / 3.5, the loot
	-- filter's finish 4.5 and the globes 8 (so the autoloot, the Loot Bag and the Rarity Autoloot take their items from the bag
	-- first, as before), before the empty corpse check (loot_config.lua emptyCorpseIndex 99) and the loot line (100)
	index = 98,

	-- where the items land: free walkable tiles within this many tiles of the death tile (1 or 2). A tile with no wall, no water,
	-- no stairs / teleport / magic field, no protection zone and no house is free; one that the death tile cannot see is skipped
	radius = 2,

	-- the pile rules: the cost of a tile is the ring it lies on (ring 2 costs `ringPenalty` more than ring 1), the items already
	-- on it (`occupiedPenalty` each, up to 3), the items this kill already sent there (`pilePenalty` each) and a random share up
	-- to `jitter`. Items take the cheapest tile in turn, so the loot spreads before any tile gets a second item.
	ringPenalty = 0.35,
	occupiedPenalty = 1.0,
	pilePenalty = 2.0,
	jitter = 0.6,
	-- the death tile itself is a last resort: only when no other tile is free (its cost, above every ring tile's)
	originPenalty = 6.0,

	-- caps. A kill puts at most `maxItems` things on the ground (all its gold counts as one, in one stack per tile); the rest
	-- stays in the small bag on the death tile (the lowest rarities stay, the rarest fly). A pull cannot flood a place: at most
	-- `maxPerAreaSecond` items in one `areaSize` x `areaSize` square of tiles per second and `maxPerSecond` on the whole map;
	-- a kill over a cap leaves everything in its bag, as before.
	maxItems = 14,
	maxPerAreaSecond = 40,
	areaSize = 8,
	maxPerSecond = 160,

	-- the show: item i leaves the death tile `staggerMinMs` .. `staggerMaxMs` after item i - 1 (the rarest last), flies with the
	-- distance effect of its group for `flightBaseMs` + `flightPerTileMs` per tile and lands there. burst = the effect on the
	-- death tile when the loot flies. Names are the engine constants without the CONST_ prefix (a missing name = no effect).
	staggerMinMs = 50,
	staggerMaxMs = 80,
	-- O677: a flight is long enough to read as an arc (the client animation, game_lootburst, draws it): flightBaseMs + flightPerTileMs per
	-- tile, times the group's `flightMul` (the rarer, the higher and longer it flies). The real item lands exactly when it ends.
	flightBaseMs = 180,
	flightPerTileMs = 45,
	flightMul = {gold = 1.0, plain = 1.0, rare = 1.15, epic = 1.4, unique = 1.75},
	burst = "ME_POFF",
	-- the distance effect by group: gold, plain (rarity Common / Uncommon / none), rare (Magic and Rare), epic (Legendary and
	-- Divine), unique. The landing sparkle of the rare groups is the `land` row, the beam over them is the client's (O569)
	missiles = {gold = "ANI_SMALLSTONE", plain = "ANI_SMALLSTONE", rare = "ANI_ENERGY", epic = "ANI_ENERGY", unique = "ANI_FIRE"},
	land = {rare = "ME_MAGIC_BLUE", epic = "ME_MAGIC_GREEN", unique = "ME_FIREWORK_YELLOW"},
	-- the rank (ChaosRarity.rank of the item's rarity, 1 Common .. 6 Divine; a unique counts 100) from which an item is in the
	-- rare group (Magic) and the epic group (Legendary)
	rareRank = 3, epicRank = 5,
	-- the rank of Divine (ChaosRarity.rank 6): the client's beam group "divine" (the epic group is Legendary and Divine together)
	divineRank = 6,

	-- the client animation (O677, game_lootburst; opcode 230 action "explode"): true = a player whose client says it draws the burst
	-- (opcode 230 `burst {on = 1}`, sent at login and when the option changes) gets ONE message with every flight of the kill, and the
	-- stock distance effects, the landing sparkles and the poff are left out for that player (the others keep them). false = the stock
	-- effects for everyone, nothing sent. viewX / viewY: who sees the death tile (the owner and the party members within these squares).
	clientAnim = true,
	viewX = 9, viewY = 7,

	-- ownership. The killer and the party (the corpse owner rule, as the bag had it) may take the items; no other player may
	-- while the rule lasts. ownerSeconds: how long that is for plain items (nil = the bag's whole life, corpse_config.lua
	-- seconds: the same timings the bag had; a smaller number frees the plain items to anyone after that many seconds). An item
	-- with one of strictAttributes (uniques, set pieces, main quest items) or an id in strictIds keeps the rule for the whole
	-- life. decaySeconds: how long an item lies before it vanishes (nil = the bag's `seconds`).
	ownerSeconds = nil,
	decaySeconds = nil,
	strictAttributes = {"chaos_unique", "chaos_set", "chaos_mq"},
	strictIds = {},
	-- attributes the loot layers write on the bag that the items must carry on the ground too (the season isolation and the
	-- Self-Found owner: season_config.lua isolation.tagKey, modes.ownerKey)
	inheritAttributes = {"chaos_realm", "chaos_owner"},

	-- kills inside an instance (rift, dungeon, tower, arena, raid, boss rooms: Chaos.instanceAt) keep the bag: the instance
	-- ends and clears its area, and what lay on the floor would go with it. true = explode there too.
	inInstances = false,

	-- the sweeper that makes the items vanish (the engine decays no loose item): looks at the tiles that hold loot every
	-- `sweepSeconds`; one timer, only while a tile is watched
	sweepSeconds = 2,

	-- Loot all (client key / button in game_groundlabels, opcode 230 `lootall`): the items of yours within this reach
	-- (tiles, like the loot channel's click to loot) go into the backpack in one action. At most `lootAllMax` items a time.
	reachX = 7,
	reachY = 5,
	lootAllMax = 40,
}
