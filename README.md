![Project Chaos](docs/images/banner.png)

# Project Chaos

> *The world was not ended. It was broken, and the pieces still bleed.*

> Once there was one world. Then the sky split, and the **Chaos** came through the wound.
> It did not end the world. It broke it into drifting shards, and through every crack it still bleeds: into the beasts
> of the deep hunting grounds, into the orbs that reshape steel, into the **rifts** that open wherever a Rift Key turns.
> Five colossi came with it. Kaelgor, Skaldra, the Rotmother, Nyxareth and Vharok still answer every portal that opens
> at the temples, and the guilds still bleed for the **Chaos Obelisk**.
> Against them stand those who take up the sword, the bow, the spell or the shadow. At the hundredth step of their road
> the **Ascendant Oracle** shows them two paths, and they leave as something more than they came.
> The ash is still falling. This is the **Season of Ash**.

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

> *"Nobody dies on the island. It is the last kindness this world will show you."*
> (from the Chronicle of the Broken World)

- **Tutorial island:** new characters start on a small island with five stations: fight, cast your first spell, spend
  a passive point, use a Chaos Orb, and learn about keystones, bounties and the store. Each station opens the next
  gate. You can skip it any time (`!skiptutorial`), and nobody can die there.
- **Starter kit per class:** weapon, armour, potions, food, tools, a temple teleport scroll and some gold, chosen for
  your class: arrows for Rangers, a second dagger for Ninjas, and so on.
- **Milestone gifts** at levels 20, 50, 100 and 200: potions for your role and Chaos Orbs.

## Classes

> *"Steel, string, spell or shadow. Choose one. At the hundredth step I will ask you to choose again."*
> (the Ascendant Oracle)

![Classes and ascensions: Warrior, Ranger, Mystic and Thief](docs/images/feature_classes.png)

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

> *"Six hundred stars, and never enough light to reach them all. No two heroes draw the same constellation."*
> (from the Chronicle of the Broken World)

![The passive tree and the Paragon window](docs/images/feature_passive_tree.png)

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

> *"The Chaos seeps into everything it touches. Most of it is rust. Some of it glows."*
> (a scavenger of the deep hunting grounds)

![The fifteen rarities and the loot filter](docs/images/feature_loot.png)

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

> *"Every orb is a splinter of the break. Press it to steel, and the steel forgets what it was."*
> (from the Chronicle of the Broken World)

![The Crafting Bench and its seven orbs](docs/images/feature_crafting.png)

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

> *"Five came through the first wound. Whenever the portals open at the temples, they come back, and never weaker."*
> (from the Chronicle of the Broken World, the Book of the Five)

![The five world bosses and a sealed rift](docs/images/feature_endgame.png)

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

## Seasons

> *"The ash falls, the ladder is swept clean, and new names climb it. The ash remembers who reached the top."*
> (from the Chronicle of the Broken World, on the Season of Ash)

![Seasons: the Season of Ash and its reward track](docs/images/feature_seasons.png)

Start fresh with a **season character** (`!season join` on a new character) and race on the season ladder.
- **Own economy:** season characters trade, mail, party and loot only with their own season.
- **Season uniques:** some uniques drop only for season characters while the season runs, then for everyone.
- **Reward track:** outfits, addons, mounts and titles for milestones (level 100 / 300 / 600 / 1000, bounties, world
  bosses, rifts), unlocked for your whole account and kept forever.
- **Season end:** season characters join the normal world with everything they earned.

## PvP

> *"The Obelisk does not care whose banner flies over it. It only counts the seconds you hold it."*
> (a Siege Champion)

![The ranked arena and the guild siege](docs/images/feature_pvp.png)

- **Ranked arena** (`!arena`): **1v1 and 2v2** with an Elo rating per mode.
  - Matchmaking pairs players of close rating and similar level.
  - Nobody really dies and there are no skulls: a lethal hit sends the loser to the gallery.
  - Each win pays a Chaos Orb, and the first win of the day pays a bonus.
- **Guild Siege** (`!siege`): every Saturday at 20:00, up to four guilds per arena fight over the **Chaos Obelisk**.
  - You score by striking enemies down and by holding the obelisk.
  - Nobody really dies.
  - The winners become **Siege Champions** for a week: a title and +5% experience.

## Leaderboards and titles

> *"Every Monday the stone is wiped and the names are carved anew. Only the titles linger, for one week."*
> (from the Chronicle of the Broken World)

![The weekly leaderboards and a title above a name plate](docs/images/feature_leaderboards.png)

Weekly boards (`!leaderboard`) reset every Monday:
- World Boss damage
- Bounty Hunter
- Rifts
- Goblin Slayer
- Guild Siege
- Arena 1v1 and 2v2

The top 3 of each board earn a **title** for the next week (Bossbane, Warden of the Hunt, Riftwalker, Goblin Slayer,
Siegebreaker, Duelist, Gladiator) and orbs. The all-time **Class Ladder** ranks the highest characters of every class.

### Name plates and titles

Above every player floats a name plate: their **title** on top, their **guild** in braces below it, and their **name**
on a small framed plate. Titles come from the leaderboards (gold), the guild siege (Siege Champions, orange, with a
crimson plate), seasons, login streaks and achievements; staff wear red titles on a gold plate. Hold several? `!title`
lists them, `!title <name>` picks one, `!title none` hides it. Monsters and NPCs keep their plain names.

## Achievements

> *"I write down every deed. A few of them I may not write down until someone has done them."*
> (the Chronicler)

![The achievements window](docs/images/feature_achievements.png)

Over 90 achievements (`!achievements`, or Chaos -> Achievements) give you goals in every corner of the game:
- **What counts:** levels and Paragon, magic, rare and legendary kills, ambushes, Treasure Goblins, each world boss, rift
  tiers and modifiers, bounty contracts and weekly chests, uniques and rarities found, orbs used at the Crafting Bench,
  arena wins and ratings, guild sieges, and a few secrets that stay hidden as **???** until you find them.
- **Points:** every achievement is worth points. Your account total counts each achievement once, whichever character
  earned it.
- **Titles:** many achievements give a title to show above your name. Pick one in the window or with `!title`.
- **Rewards:** some pay orbs, others an outfit with its addons or a mount.
- **Already a veteran?** Levels, Paragon, ascension, bounties and arena results you had before are counted the next time
  you log in.
- The window shows your progress on each one, and a toast pops up the moment you unlock one.

## Quality of life

> *"Count your kills, count your coin, and come back tomorrow. The Chaos is patient. So are its rewards."*
> (from the Chronicle of the Broken World)

![The hunt tracker and the daily reward](docs/images/feature_qol.png)

- **Combat visuals:** crits, dodges and reflects get their own sprites. Elemental weapon damage shows as a separate
  coloured number with its element's effect. Big numbers are shortened (12.4k).
- **Patch notes in the client:** a window with every week's changes. It opens once at login when there is something
  new, after the daily reward.
- **Hunt tracker** (`!hunt`): experience, loot, supplies and profit per hour for your session, counted by the server.
  It also shows kills per monster, every item looted and its value, damage and healing per second, and your Chaos
  drops. Pause, reset or copy a summary.
- **Daily rewards and login streaks:** one claim a day per account. Your streak counter shows your current and best
  streak. Milestones at 7, 14, 30, 60, 100 and 180 days pay orbs, and titles at 30, 100 and 180 days ("the Devoted",
  "the Relentless", "the Undying"). Grace charges save your streak when you miss a day.
- **Waystones** with account upgrades (experience, loot, rarity), and toast notifications for
  everything that matters.
- **Store** (Chaos Coins):
  - stamina refill, temple teleport, bottomless loot pouch, auto seller
  - training weapons, server-wide world buffs
  - name, vocation and sex change, blessings, skull removal
  - passive tree reset, crafting orbs

## Coming soon

Being built right now:
- **New classes:** the **Necromancer** (Lich / Bone Lord), the **Monk** (Shadowfist / Iron Sage) and the **Templar**
  (Inquisitor / Sentinel).

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
| [docs/LAUNCH.md](docs/LAUNCH.md) | **Running a server**: install (`server/tools/install_all.py`), production config, systemd, backups, monitoring, launch checklist |
| [website/README.md](website/README.md) | the website (ZnoteX with our layout and plugin): installer, class lock on character creation, leaderboards / patch notes / seasons pages, banners and art |

This page is kept up to date as features are merged: new systems move from *Coming soon* into their sections.
