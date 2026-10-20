# Chaos loot layer (loot.lua / loot_config.lua)

A second `EventCallback.onDropLoot` that post-processes the corpse after the stock
`data/scripts/eventcallbacks/monster/default_onDropLoot.lua`. All numbers are in `loot_config.lua`.

## How it hooks

`EventCallback:register(index)` appends to `EventCallbackData[type]` and sorts ascending by index, so a
**lower index runs first**.

| callback | index | role |
| --- | --- | --- |
| `default_onDropLoot.lua` | 0 (no index given) | builds the loot, rolls gear rarity, waystones, sends "Loot of ..." |
| **chaos loot.lua** | **1** (`ChaosLootConfig.priority`) | extra rolls, gear quality, currency, uniques |
| `creaturescripts/autoloot.lua` | 3 | moves items to autolooting players |

Keep our index strictly between 0 and 3: above 3 the autoloot would run before us and the bonus items would never be
auto-picked. The callback returns nothing, so the chain continues; all work runs inside `pcall`, an error is printed
as `[Chaos loot] onDropLoot failed: ...` and never breaks autoloot.

It bails out exactly like the stock one when `RATE_LOOT == 0` or when there is no corpse owner player. Low stamina
(<= `minStamina`, 840) no longer stops it: `ChaosCatchup.lootMult(owner)` (catchup.lua) multiplies the rate after the
`maxRate` cap, x0.5 at low stamina and x1.25 for a returning player. The stock callback is patched the same way
(`tools/patch_base_events.py` step 16: its loot chances x0.5 instead of nothing). Without catchup.lua the old rule holds.

The tier comes from `ChaosTierDead[monster:getId()].tier` (set by monster_tiers.lua's death event, kept 10 s), else
`ChaosTierOf(monster)`, else `"normal"`.

## What it does per kill

1. **Extra rolls** (`extraRolls`): magic 1 (chance x0.5), rare 1, legendary 2, boss 2 additional passes (lowered 2026-10-17, README "Chaos loot rate caps") over `MonsterType:getLoot()`
   using the stock chance test `getLootRandom() <= lootData.chance`. Counts: `random(min,max) * levelCountMult(stock
   table, by Monster:getMonsterLevel()) * extraCountMult[tier]`, floor, min 1; non-stackables always 1. The rate
   scales the chance only (rate x count squared the bonus).
   Extra gear gets the stock rarity roll (copied) so it is comparable with stock gear.
2. **Gear quality**: every top-level corpse item that is gear (weapon/armor/hit/absorb/skill/special stats like the stock
   `hasRelevantStats`, or a quiver of `data/lib/chaos_archery_config.lua`, which has no stats of its type; not ammo, stackable, container, not in `gear.excludedItems` (boats 27797-27802), not a unique
   from `ChaosUniqueItems`) gets `L.upgradeRarity(tier, current, itemFind)`: floor (rare 3 Magic, legendary 4 Rare, boss 5 Legendary, with
   `ensureChance`), then `bonusChance` % for +1..+3 steps up the order Common, Uncommon, Magic, Rare, Legendary (`bonusSteps` weights; the step is one rarity, not one old id), capped at `maxRarity` (5, Legendary), then `divineChance` (rare 5%, legendary 30%, boss 150%: more than one roll) may make it Divine (10). The stock roll of the base script is `ChaosRarity.stockRolls` (patch_base_events.py step 21): 33% of drops carry a rarity (Common 10.5%, Uncommon 8.3%, Magic 6.1%, Rare 4.5%, Legendary 2.84%, Divine 0.38%). Seven rarities since 2026-10-18 (server/README.md "Item rarities"); old ids 6-9 and 11-15 map to 5 and 10. Never
   downgrades. If the target is higher, `Game.createItemWithRarity(id, 1, target)` (target a stored id) is made, checked
   (`getCustomAttribute("rarity") == target`), added with `corpse:addItemEx`, and only then the old item is removed. On any
   failure the original stays.
3. **Currency**: `currency.entries` (stock orbs 29857 Divine, 29856 Chaos; add your own) with `chance[tier]` per 10000,
   plus `guaranteed[tier]` weighted draws (legendary 1, boss 1), count scaled by `countMult[tier]`. The chance scale
   (rate x item find x orb find x Ember of the Forge) is capped at `currency.maxScale` (3.0). Orbs drop only from monsters
   of level `currency.minMonsterLevel` (100) or more (bosses exempt); waystones are taken out of a corpse of a monster below
   `waystone.minMonsterLevel` (150) by `L.gateWaystones`.
   3b. **Gems** (`data/lib/chaos_gems_config.lua` `drop`): chance by tier per 10000 x the rate x item find, quality by the
   monster's level; gear with a rarity also gets its sockets in step 2b. See server/README.md "Gems and sockets".
4. **Uniques**: see contract below.
5. **Item find**: `player:getStorageValue(ChaosLootConfig.itemFindStorage)` (default 7100040) = +N % (clamped to
   `itemFindMaxPercent`, 300) on extra-roll chance, currency chance, unique chance, gear bonus chance. Corpse owner only.
6. A single line `Chaos bonus loot of <monster>: ...` goes to the owner / party (MESSAGE_LOOT). Gear upgraded to
   rarity >= `announceRarityFrom` (10, Divine) is announced to nearby players like a unique find.

`ChaosLootConfig.rateMult` (number or `function(ctx)`, ctx = `{tier, monster, player, level, itemFind}`) multiplies
extra-roll chance and currency chance. loot.lua caps the result (guild wrapper included) at `ChaosLootConfig.maxRate`
(3.0); `ChaosLoot.rateMult(ctx)` is the capped value. Unique chance is only scaled by tier and item find.

## Contract: ChaosUniqueItems (defined by the items agent)

Global, optional (nil is fine). Array of entries (a name-keyed map `{Soulreaper = {...}}` also works, key = name):

```lua
ChaosUniqueItems = {
	{ name = "Soulreaper", id = 1234, minTier = "legendary", chance = 150, -- per 10000 per kill, BEFORE tier mult
	  monsters = {"demon", "hellhound"}, -- optional; nil/empty = any monster; compared case-insensitively to monster:getName()
	  bossOnly = false,                  -- true: only tier "boss"
	  level = 100 },                     -- informational (item level); not used for dropping
}
```

* `id` (number > 0) is required; entries without it are ignored.
* `minTier`: `normal|magic|rare|legendary|boss`, ranks 0..4 (`unique.tierRank`); a boss satisfies "legendary".
  If absent, the first element of an optional `tiers = {...}` list is used, else `"normal"`.
* Optional extra: `minMonsterLevel` (checked against `Monster:getMonsterLevel()`).
* Effective chance = `chance * unique.tierMult[tier]` (normal 0, magic 1, rare 2, legendary 4, boss 6) `* itemFind`,
  clamped to `unique.maxChance`. `normal` kills never drop uniques (multiplier 0; change in config).
* At most `unique.maxPerKill` (1) per kill; if several hit, one is picked at random.
* The item is added to the corpse with `corpse:addItem(id, 1)` (no rarity roll; the gear pass skips it). Players within
  `viewRangeX/Y` of the corpse get a `MESSAGE_EVENT_ADVANCE` text and the effect is shown on the corpse; players within
  `broadcastRangeX/Y` (multifloor) get "<owner> found <name>!".

## Diagnostic

```lua
local r = ChaosLootRoll("Demon", "legendary", 10000)      -- table, see below
print(ChaosLootReport("Demon", "boss", 10000))            -- formatted string
ChaosLootRoll(name, tier, kills, {lootTable=, level=, itemFind=, uniques=, rand=function(a,b) end})
```

Result: `{monster, tier, kills, items={[id]=n}, gear, rarity={[stored id 0,1,2,3,4,5,10]=n}, upgraded, extraItems, currency={[id]=n},
uniques={[name]=n}}`. It uses `MonsterType(name):getLoot()` (fallback `sim.fallbackLoot`), mimics the stock pass (loot chance
and stock rarity roll), then the same functions as the real callback, without corpse or players. `kills` is capped at
`sim.maxKills`. The only random source is the local `randomFn` (`ChaosLoot.setRandom(fn)` swaps it; tests use this).

## Tuning

Everything is in `loot_config.lua`; `/reload scripts` re-runs it (loot.lua always re-`dofile`s the config). Typical
levers: `extraRolls`, `gear.minRarity/bonusChance`, `currency.entries[].chance`, `unique.tierMult`. Check with
`ChaosLootReport`. Note the engine also auto-loads `loot_config.lua` as a script because it lives under `data/scripts`; it
only returns a table so this is harmless (loot.lua reads the global `ChaosLootConfig` at runtime, not a cached copy).

## Honest caveats

* Nothing here has run on a real server. Tested only with a Lua 5.3 mock harness (EventCallback, corpse, MonsterType,
  `Game.createItemWithRarity`, spectators). APIs assumed from the base server 3.7.5 source: `Container:addItemEx`
  returning `RETURNVALUE_NOERROR`, `Game.getSpectators(pos, multifloor, onlyPlayers, minX, maxX, minY, maxY)`,
  `Monster:getMonsterLevel()`, `Item:getCustomAttribute("rarity")`, `ItemType(id):getAbilities()`.
* The stock pass only stores the custom attribute `rarity` on its items; `Game.createItemWithRarity` additionally rolls the
  stats in C++ (`applyRarityEffects`). So our upgraded items carry real rolled stats while stock-rarity items may not; check
  how the equip code treats both before relying on it.
* Only top-level corpse items are processed (not items inside containers). Replaced items lose any other attributes.
* Stock `getLootRandom() <= chance` has a quirk (chance 0 can hit at roll 0); we require a positive threshold.
* Stock pass runs the same loot for every kill; its ammo/stack/container rules are copied, not shared, so keep them in
  sync if the stock script changes. Boat ids are copied from `customs/rarity/reroll_rarity_stats.lua`.
* `ChaosTierDead` lives 10 s; if the death event does not fire (monster without the registered event) the tier falls back to
  `ChaosTierOf` and then `normal`.
* Item find storage 7100040 is just a free key in the Chaos range; nothing sets it yet.
* Arrows and bolts (bows fire without them, server/README.md "Infinite arrows and quivers"): `processKill` removes them from the
  corpse first and the extra rolls skip them, for a monster whose loot table still lists them.
