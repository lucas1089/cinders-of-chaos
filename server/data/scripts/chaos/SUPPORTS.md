# Spell supports (supports.lua / data/lib/chaos_supports*.lua)

Spell supports change **how** a class spell works without changing **which** spells a class has. The class kits stay
fixed; every spell gets 1 to 3 support sockets, and support runes (a loot item, like gems) go into them. Every number is
in `data/lib/chaos_supports_config.lua`; this file is the design and the reference list.

Design rule for a later step ("option 2", extra spells from items in a shared pool): nothing here knows about classes.
Sockets are stored per character **keyed by spell id**, a spell's kind (single / area / heal / buff) comes from the
spell itself, and the wrapper works on any spell script with an id. A spell that later comes from an item only needs an
id and a `spells.xml` line to get sockets.

## Sockets

| socket | opens when | cost |
| --- | --- | --- |
| 1st | the character may cast the spell (its level) | - |
| 2nd | character level >= spell level + 60, at least 80 | - |
| 3rd | character level >= spell level + 150, at least 200 | 2 Orbs of Sockets, once per spell and character |

Examples: Witchfire Bolt (level 30): 2nd at 90, 3rd at 200. Doomtide (level 300): 2nd at 360, 3rd at 450.
The Orb of Sockets is the gem orb (24692, `chaos_gems_config.lua socketOrb`, sold in the store for 25 Chaos Currency
and dropped by the loot layer), so the third socket costs the same currency as re-rolling gear sockets.

Rules at socketing (all on the server):
- the rune must fit the spell's kind (table below);
- one rune of a support per spell; one **brand** (elemental imbue) per spell;
- the socket must be open and empty. A rune in a socket that is no longer open (e.g. a lower level after a reset)
  stays there but does nothing until the socket opens again.

Taking a rune out works like a gem at the crafting bench: **Remove** gives it back for gold by level
(2 000 / 6 000 / 20 000 / 60 000 / 200 000, bank first, then the backpack), **Shatter** destroys it for free.
Three runes of one support and level **combine** into one of the next level (window button, or use a rune on a rune of
the same kind), like three gems.

## The runes

Server ids 32101..32200: `firstId + (support - 1) * 5 + (level - 1)`. Item name `<level> <support> rune`
("epic fork rune"). Levels carry our rarity names and colours: 1 Common, 2 Rare, 3 Epic, 4 Legendary, 5 Mythic.
The items are copies of the unused stock rune stones (stackable, use-with), so the client needs no new sprite; the
window and the action bar use our own procedural icons (`client/tools/gen_support_icons.py`).

Kinds: **single** = damage to one target (also spells that jump from it), **area** = damage in an area,
**heal**, **buff** = everything else (buffs, summons, utility). Taken from the spellbook parser (`spellbook.lua`), with
`kindOverride` for the few it reads wrong. Conjuring spells get no sockets.

| # | support | effect (level 1/2/3/4/5) | fits | ids |
| --- | --- | --- | --- | --- |
| 1 | Emberbrand | 20/30/40/50/60% of the spell's damage becomes fire damage | single, area | 32101-32105 |
| 2 | Rimebrand | the same, ice | single, area | 32106-32110 |
| 3 | Dawnbrand | the same, holy | single, area | 32111-32115 |
| 4 | Gravebrand | the same, death | single, area | 32116-32120 |
| 5 | Stormbrand | the same, energy | single, area | 32121-32125 |
| 6 | Quickening | cooldown -6/9/12/15/18% (never below 1 s) | all | 32126-32130 |
| 7 | Thrift | mana cost -6/9/12/15/20%, refunded right after the cast (the full cost must be there) | all | 32131-32135 |
| 8 | Keen Edge | +2/3/5/6/8% chance per hit to strike critically for +50% (rolled uniformly, two thirds like every crit chance since patch 0004) | single, area | 32136-32140 |
| 9 | Echo | 15/20/25/30/35% chance per cast that its hits strike again 0.5 s later for 50% | single, area | 32141-32145 |
| 10 | Fork | the hit forks to 1/1/2/2/3 more enemies within 3 sqm for 35/40/45/50/55% of it | single | 32146-32150 |
| 11 | Breadth | enemies within 1 (level 5: 2) sqm of the hit ones that the spell missed take 35/40/45/50/55% of the average hit, max 6 | area | 32151-32155 |
| 12 | Shatter | enemies next to the target take 20/25/30/35/40% of the hit, max 4 | single | 32156-32160 |
| 13 | Deathburst | a kill by the spell bursts the corpse: enemies within 2 sqm take 25/30/35/40/50% of the killing hit, once per cast | single, area | 32161-32165 |
| 14 | Surge | a critical hit of the spell blasts the enemies next to the target for 30/35/40/50/60% of it, once per cast | single, area | 32166-32170 |
| 15 | Reprisal | for 8 s after the cast, a monster's hit on you has 25% to strike it back for 40/55/70/85/100% of the hit (1 s apart, at most 25% of your max health) | all | 32171-32175 |
| 16 | Bloodthirst | heals you for 2/3/4/5/6% of the spell's damage, at most 8% of max health per cast | single, area | 32176-32180 |
| 17 | Siphon | 10/15/20/25/30 mana per 1000 damage of the spell, at most 5% of max mana per cast | single, area | 32181-32185 |
| 18 | Sunder | ignores 5/8/11/14/18 points of a monster's resistance to the hit's element (never below 0; immune stays immune) | single, area | 32186-32190 |
| 19 | Hex | monsters hit take +3/4/5/6/8% damage from everyone for 4 s (the strongest hex counts, no stacking) | single, area | 32191-32195 |
| 20 | Mercy | the spell heals 5/8/11/14/18% more | heal | 32196-32200 |

Caps on the summed value of one support on one spell (they matter once option 2 adds other sources): Quickening 30,
Thrift 30, Keen Edge 13, Echo 40, Bloodthirst 8, Siphon 40, Sunder 25, Hex 10, Mercy 25.

Balance frame: a Perfect gem gives +12% element damage to one element; a Mythic support is worth roughly that much on
one spell (Echo 35% x 50% = +17.5% expected on that spell, Fork 3 x 55% only with packs, Keen Edge 8% x 50% = +4% plus
the Surge trigger). Brands add no damage by themselves: they turn damage into an element the monster resists less
(the moved part loses the old element's resistance and takes the new one's), and they let element gems count.

Extra hits (Echo, Fork, Breadth, Shatter, Deathburst, Surge, Reprisal) only hit monsters (never players or a player's
summon), use ORIGIN_SPELL, and run with the proc guard up, so they never trigger supports, keystones or another extra
hit. Brand, Sunder, Keen Edge, Hex and Mercy work on the spell's own hits, in PvP too (Hex marks monsters only).

## Where runes come from

- **Monsters** (the Chaos loot layer, `loot.lua` step 3c): chance per kill in 1/10000 by tier, normal 10, magic 60,
  rare 200, legendary 700, boss 1500 (gems: 25 / 150 / 500 / 1500 / 3000), x the layer's rate x item find. Level by
  the monster's level with the gems' table (`chaos_gems_config.lua drop.levelWeights`); legendary 25% / boss 40% one
  level better. The support is random, weighted (brands 6 each, Quickening / Thrift 10, the rest 6-9).
- **Rift chest** (`rift.lua`): 0.3 + 0.1 x tier runes (a fraction is the chance of one more), levels by rift tier.
- **Bounties** (`bounty.lua`, see "Hooks" below): 10 / 20 / 50% for a hunt / elite / boss contract, level by the
  contract's band (the gems' band table).
- **Store**: no runes. Gems are not sold either; the store keeps selling the Orb of Sockets, which opens third sockets.

## How it works

Two Lua states are involved: spells run in their own state, everything else in the scripts state.

1. **Spell state** (`data/spells/chaos/_supports.lua`, loaded by `_common.lua`, and by `data/spells/lib/spells.lua`
   once `install_supports.py` added its line, so stock spells are covered too). A `__newindex` on `_G` sees each
   script define `onCastSpell`, reads the script's path from the defining chunk, looks up its spell id in
   `spells.xml` and stores a wrapper. For a player the wrapper writes `serial * 1000 + spell id` into storage
   7109990 while the script runs and while every `addEvent` callback the script started runs (the global is swapped
   during the call), then clears it. After a cast that went through, one tick later (after the engine took the mana
   and set the cooldown): Thrift refunds mana, Quickening re-adds the spell's cooldown condition shorter (the client
   gets the new cooldown). Reprisal stores the spell id and the end of its window (7109991 / 7109992).
2. **Scripts state** (`supports.lua`). `onHealthChange` "ChaosSupportsHit" sits on the targets of players with runes
   (onTargetCombat), on every player (heals received, Reprisal) and on hexed monsters. A hit whose attacker has a
   context gets brand, Sunder, Keen Edge and Hex at once; its amount is collected per cast until the end of the
   server tick, then the extra hits, Bloodthirst and Siphon are dealt. Per-cast limits (Echo roll, Deathburst, Surge,
   leech caps) use the serial.

Storage: 7110000 + spell id x 4 + 0 (third socket opened) / + 1..3 (rune server id per socket), spell ids 0..499.

Window: client `game_spellsupports` (Chaos -> Spell Supports, `!supports`, using a rune, or the Supports button of the
spellbook), extended opcode 243. The action bar gets coloured pips (one per rune, the level colour) on spell buttons and
the runes in the button tooltip; the spellbook adds a "Supports:" line under the description.

## Install

`python3 -I server/tools/install_supports.py <server>/data` (items.otb nodes, items.xml block, the spell-library line).
Then the usual files step copies `scripts/chaos/supports.lua`, `lib/chaos_supports*.lua` and `spells/chaos/_supports.lua`
(register_spells.py copies it to `data/spells/scripts/chaos/`). Restart (spells and items need a restart).

## Hooks in other files

- `loot.lua` 3c, `rift.lua` chest: call `ChaosSupports.lootDrop` / `ChaosSupports.rewardRunes("rift", ...)`.
- `bounty.lua` (contract reward, next to the gems): `ChaosSupports.rewardRunes("bounty", {type = c.type, band = c.band})`.
- `chaos_constants.lua`: `ChaosOpcodes.supports = 243`, the storage note.
- `_common.lua`: loads `_supports.lua`. Client: `game_spellbook` (line and button), `client_chaos_topbar` (menu entry).

## Honest caveats

- Damage that a spell leaves to a condition (burning, poison ticks) is not a hit of the spell: no supports on it.
- Damage a spell deals through a summon (minions, companions) belongs to the summon: no supports.
- A spell script that keeps a local copy of `addEvent` from load time would not pass the context to its delayed hits
  (none of ours does; the unit test covers the swap).
- Quickening shortens the cooldown condition after the engine set it; the group cooldown (2 s) stays.
- Thrift refunds after the cast: the full cost must be there to cast.
- Spells sharing a spell id (three pairs among the stock spells) and conjuring spells get no sockets.
