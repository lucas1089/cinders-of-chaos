# Project Chaos

> *The world was not ended. It was broken, and the pieces still bleed.*

Project Chaos is a dark fantasy Open Tibia server (protocol 10.98) with its own client. It keeps the classic top-down
hunt-and-loot game and adds the depth of an action RPG: classes with ascensions, a huge passive tree, items with
rarities and modifiers, crafting orbs, monsters that roll affixes, and endgame systems built for weeks of play rather
than days.

---

## At a glance

| | |
|---|---|
| Protocol | 10.98, with our own client (custom UI skin, top menu, windows for every system) |
| Classes | 4 base classes, each with 2 ascensions (8 ascended classes) |
| Level cap | 1000, then Paragon levels. Reaching 1000 takes roughly 100 hours of hunting |
| Items | 15 rarities from Common to Transcendent, item levels, random modifiers, about 50 uniques |
| Endgame | world bosses, bounties, rifts with keys and modifiers, the Infinity Tower, dungeons, arena, guild siege, weekly leaderboards |
| Fair play | multi-client rules, staff characters left out of every leaderboard |

---

## Your first steps

- **Tutorial island:** new characters start on a small island with five stations: fight, cast your first spell, spend
  a passive point, use a Chaos Orb, and learn about keystones, bounties and the store. Each station opens the next
  gate. You can skip it any time (`!skiptutorial`), and nobody can die there.
- **Starter kit per class:** weapon, armour, potions, food, tools, a temple teleport scroll and some gold, chosen for
  your class: arrows for Rangers, a second dagger for Ninjas, and so on.
- **Milestone gifts** at levels 20, 50, 100 and 200: potions for your role and Chaos Orbs.

## Classes

You start as one of four base classes. At level 100 you **ascend** into one of two specialisations (`!ascend`).

| Base class | Plays as | Ascensions |
|---|---|---|
| **Warrior** | melee, heavy armour, most health | **Juggernaut**: the tank, with taunts, damage reduction and block/reflect · **Berserker**: two-handed area damage; *Rage* hits harder the lower your health, *Skyfall Cleave* leaps in and slams the ground |
| **Ranger** | bows and crossbows | **Deadeye**: the best single-target damage in the game, with crossbows, marks and crits · **Beastmaster**: fights beside a *War Wolf* companion that grows with you (two wolves from level 400) |
| **Mystic** | spells, wands and rods | **Elementalist**: the best area damage, with fire, ice and energy combos · **Illusionist**: the support; buffs the party's attack, weakens enemies and heals |
| **Thief** | fast light weapons, shurikens, stealth | **Ninja**: dual-wields daggers with a scripted off-hand strike, plus Shadow Step · **Samurai**: one sword, counter stance, Iaijutsu draw strike and Bushido crit stacks |

Every class has its own Chaos spells with custom names, icons and effects, and the spellbook (`!spells`) lists them all.
Balance is measured on test dummies at levels 300 and 1000, so every class keeps a clear role in a group.

## Passive tree and Paragon

- **Passive tree:** over 600 nodes, with points from levels and not enough to take everything, so every build is a
  choice. Class **keystones** change how you play:
  - *Cleaving Arc*: two-handed hits strike everything around you
  - *Ricochet*: arrows bounce to another target
  - *Arcane Echo*: spells can cast a second time
  - Illusionist party auras
- **Build codes:** export your tree as a short code (`!build export`) and import someone else's. The tree previews it
  first, with the points needed against the points you have.
- **Respec:** right-click a node to refund just that node, or reset the whole tree. Both are priced by your level: a
  full reset costs about 35-40 minutes of hunting gold. Resets are free below level 50 and once after a class change.
- **Paragon:** after level 1000 every level gives a Paragon point. You spend them on small, capped bonuses in four
  categories, so there is always something to gain.

## Items and loot

- **15 rarities**: Common, Uncommon, Rare, Epic, Legendary, Exotic, Mythic, Chaos, Eternal, Divine, Phantasmal,
  Celestial, Cosmic, Abyssal and Transcendent.
- **Item levels and modifiers:** elemental damage, absorbs, skills, critical hits, life and mana leech.
- **About 50 uniques** with fixed, build-defining stats. Some only drop from bosses.
- **Monster tiers:** every spawn can roll **Magic, Rare or Legendary**, each tougher and better-rewarded. Tiered
  monsters get modifiers such as *Blazing, Chilling, Venomous, Vampiric* or *Berserker*. Killing one can trigger an
  **ambush**.
- **Treasure goblins:** a very rare, cowardly goblin that flees, blinks away and taunts you, then escapes 18 seconds
  after the first hit. Catch it in time for a hoard of gold, orbs and rarity gear.
- **Loot filter** (`!lootfilter`): items glow in their rarity colour in corpses, and junk below your chosen rarity is
  dimmed. You can switch whole categories off, or pick a preset: Show all, Hunter or Strict.
- **Loot channel with icons:** every kill gets a row of item icons. Click an icon to loot it (Shift+click for one from
  a stack). Looted items grey out.
- **Loot rays:** a beam of light rises from corpses holding a unique or a Legendary-or-better item, coloured by
  rarity.
- **Rarity Autoloot** (store unlock): pick up gear by rarity even when it isn't on your autoloot list, and leave the
  junk behind.
- **Autoloot, auto seller, bank and stash** so you spend your time hunting, not walking.

## Crafting

Orbs reshape your gear at the **Crafting Bench** (`!craft`):

| Orb | What it does |
|---|---|
| Orb of Transmutation | a normal item becomes Common or Uncommon |
| Orb of Alchemy | a normal item becomes Rare, Epic or Legendary |
| Exalted Orb | adds one modifier, up to the rarity's limit |
| Orb of Annulment | removes one random modifier |
| Orb of Scouring | turns the item back into a normal item |
| Chaos Orb | rerolls the item with the same rarity |
| Divine Orb | rerolls the item with a new random rarity |

Orbs drop from monsters (more from tiered ones and bosses), from bounties and the weekly chest, and can be bought in
the store. Uniques can't be crafted, so they stay unique.

## Endgame

- **World bosses:** a server-wide event. A portal opens at every temple and one of five colossal bosses appears:
  - Kaelgor the Infernal Warlord
  - Skaldra the Rime Queen
  - The Rotmother
  - Nyxareth the Void Archon
  - Vharok the Blood Colossus

  Each has phases and 15 to 24 million health. Everyone who does real damage gets a reward, not only the last hit.
- **Bounty board** (`!bounty`): daily "kill X in Y" contracts per level band that pay orbs. Finish seven in a week
  for the weekly bounty chest.
- **Rifts** (`!rift`): use a **Rift Key** to open a 10-minute instance for you and up to 3 party members.
  - Each key has a tier (1-15) and 1-3 random modifiers, such as *Vitality, Brutality, Haste, Elites, Reflection,
    Warding, Withering* or *Swarm*. Harder modifiers raise the rewards: item quantity, rarity and experience.
  - Clear the packs and the **Guardian** appears. Kill it to seal the rift, and its chest pays gold, Chaos and Divine
    Orbs and gear for every finisher.
  - A sealed rift can drop the next tier's key. Keys also drop from tiered monsters and bounties.
  - A crash refunds your key.
- **Infinity Tower** (`!tower`): climb floor after floor alone or with a party of up to 4, against the clock.
- **Dungeons:** instanced runs with their own progress.
- **Late game:** 17 level-scaled Chaos monsters (levels 650-1000) live in the deepest hunting grounds. Experience
  stages are tuned so the road to 1000 stays rewarding.
- **Events calendar:**
  - *Blood Moon* weekends: +50% experience
  - *Chaos Rift* Wednesdays: double tiered spawns
  - *Loot Frenzy* Fridays
  - a daily boosted creature and boss

## PvP

- **Ranked arena** (`!arena`): **1v1 and 2v2** with an Elo rating per mode.
  - Matchmaking pairs players of close rating and similar level.
  - Nobody really dies and there are no skulls: a lethal hit sends the loser to the gallery.
  - Each win pays a Chaos Orb, and the first win of the day pays a bonus.
- **Guild Siege** (`!siege`): every Saturday at 20:00, up to four guilds per arena fight over the **Chaos Obelisk**.
  - You score by striking enemies down and by holding the obelisk.
  - Nobody really dies.
  - The winners become **Siege Champions** for a week: a title and +5% experience.

## Leaderboards and titles

Weekly boards (`!leaderboard`) reset every Monday:
- World Boss damage
- Bounty Hunter
- Rifts
- Goblin Slayer
- Guild Siege
- Arena 1v1 and 2v2

The top 3 of each board earn a **title** for the next week (Bossbane, Warden of the Hunt, Riftwalker, Goblin Slayer,
Siegebreaker, Duelist, Gladiator) and orbs. The all-time **Class Ladder** ranks the highest characters of every class.

## Quality of life

- **Combat visuals:** crits, dodges and reflects get their own sprites. Elemental weapon damage shows as a separate
  coloured number with its element's effect. Big numbers are shortened (12.4k).
- **Patch notes in the client:** a window with every week's changes. It opens once at login when there is something
  new, after the daily reward.
- **Daily rewards**, **waystones** with account upgrades (experience, loot, rarity), and toast notifications for
  everything that matters.
- **Store** (Chaos Coins):
  - stamina refill, temple teleport, bottomless loot pouch, auto seller
  - training weapons, server-wide world buffs
  - name, vocation and sex change, blessings, skull removal
  - passive tree reset, crafting orbs

## Coming soon

Being built right now:
- **Hunt tracker:** experience and profit per hour, kills and loot of your session.
- **Login streaks** with milestones.
- **Seasons:** fresh-start season characters with their own economy, ladder, season uniques and cosmetic rewards that
  carry over.
- **New classes:** the **Necromancer** (Lich / Bone Lord), the **Monk** (Shadowfist / Iron Sage) and the **Templar**
  (Inquisitor / Sentinel).
- **Name plates:** title, guild and name above every player.

The full priority list is in [ROADMAP.md](ROADMAP.md).

---

## For developers

| Document | What's in it |
|---|---|
| [server/README.md](server/README.md) | layout, install steps, every Chaos system and its settings |
| [client/README.md](client/README.md), [client/MANIFEST.md](client/MANIFEST.md) | client modules, base patches, build |
| [docs/CLASSES.md](docs/CLASSES.md) | class design and implementation status |
| [server/data/spells/README.md](server/data/spells/README.md) | spells and balance tables |
| [ROADMAP.md](ROADMAP.md) | what's done, in progress and planned |

This page is kept up to date as features are merged: new systems move from *Coming soon* into their sections.
