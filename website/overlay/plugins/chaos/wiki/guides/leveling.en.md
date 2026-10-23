# Leveling guide: level 1 to 1000

A step by step path for new players: where to hunt in each level bracket, which systems open up and how to reach each one in game. Menu names follow the client's top bar (for example **Adventure > Next Goals**). When you don't know what to do, open **Next Goals**: it lists the goals of your bracket, and one click marks the place on your map.

=> @create | Create a character | On the website or in the client's character select.
=> @temple | Start at the temple | You begin at level 8 in the Cinderhold temple, with your class kit.
=> @level | Follow the goals | Adventure > Next Goals: {{goals.count}} goals in {{goals.bands}} bands.
=> @ladder | Move up a bracket | This guide: what to do from level 8 to 1000, one bracket at a time.

> [tip] Read [First steps](wiki:guide:start) and [Progression](wiki:guide:progression) too. This guide puts both on one timeline.

## Character creation and classes

- Create your character on the website or in the client. You start at **level 8**, already in the Cinderhold temple.
- The free classes are {{class.openNames}}. {{class.lockedNames}} open for the whole account once one of its characters reaches level {{class.unlockLevel}}, for free.
- Each class has two ascensions, chosen at level {{class.ascensionLevel}}. See them all in the [Classes](wiki:guide:classes) guide.
- The starter kit has your class gear and weapon, two Everfull potions (health and mana, they never run out), food, a rope, a shovel, a Temple Teleport Scroll with 3 uses and 500 gold.
- Milestone gifts arrive at levels {{newplayer.giftLevels}}: potions for your role, Orbs of Upheaval and later Orbs of Fate, Grafting and Stamina Extensions.

> [note] There is no tutorial island any more: you go straight into town.

## Controls and the windows you will use every day

- **System > Helper**: on your first login the **Auto setup** button blinks. One click sets heals, potions, food, haste and the attack rotation with targeting.
- **Character > Spellbook** (Alt+S): your spells. **Character > Passive Tree** (Alt+P): your passive points.
- **Hunt > Hunt Tracker** (Alt+H): experience and loot per hour. Its **Restock** button buys back the supplies you used, plus a 10% fee.
- **Hunt > Bestiary** (Alt+B) and **Hunt > Kill Tasks**: monster knowledge and kill tasks.
- **Adventure > Bounty Board**: daily contracts. **Adventure > Daily Reward**: a {{daily.days}} day streak for the account.
- **Economy > Crafting Bench** (Alt+C), **Economy > Item Finder** and **Economy > Codex** (Alt+K): crafting, where each item drops and every rule of the game.
- **Character > Town Portal**: a portal back to town (3 s to open, 60 s cooldown, it lasts 5 minutes and your party can use it).

> [tip] Dying never costs items. There is no experience loss up to level 30, half at level 100 and the full loss from 250. The first death of each day loses only half of that.

## Level 8-50: first steps

=> @temple | Teleport hall | The two great teleports 5 tiles north of the temple lead to the hunting hall.
=> @level | Level signs | Every teleport has a sign: "Name, levels X-Y". Floor 7 holds levels 1-500.
=> @reward | First contract | Adventure > Bounty Board: take a contract from level 8.
=> @level | First point | Your first passive point comes at level 12.

- **Where to hunt.** During your first hour, hints mark the 3 nearest hunts of your level on the minimap. Good starts in the hall: Rat (1-6), Orc (5-15), Minotaur (5-15), Cave Rat (5-20), Dwarf Guard (10-25), Haunted Treeling (10-30), Stalker (15-30), Saltkin Mantassin (25-55), Frost Dragon Hatchling (25-75) and Fire Elemental (20-80).
- **Passive tree.** You get 1 point every {{tree.levelsPerPoint}} levels above level {{tree.startLevel}}. Spend it in Character > Passive Tree. See the [Passive tree](wiki:guide:tree) guide.
- **Monster tiers.** Magic (blue), rare (yellow) and legendary (orange) monsters drop better gear. Wear what beats yours.
- **Pack combat.** Chained kills, each within 3 s of the one before, give bonus experience: +10% at 4 kills, +20% at 6, +30% at 8 and +40% at 9.
- **Bounty Board.** Up to {{bounty.maxActive}} contracts at once; the board rolls every day at 06:00. {{bounty.weeklyNeed}} contracts in one week give the weekly chest.
- **Buy and sell.** The Loot Buyer stands in the market of the teleport room (the two great teleports north of the temple lead there). **Economy > Market** (Alt+E) opens at level {{market.minLevel}}.
- **Level 20:** your first kill task, your first crafting orb on the Crafting Bench, 50 monsters with a tier.
::: if invasion.on
- **Level {{invasion.minLevel}}:** [town invasions](wiki:event:invasion). See Adventure > Events.
::: end
::: if mentor.on
- **Mentor.** Up to level {{mentor.apprenticeMax}} you can ask for a mentor in Social > Mentors: +{{mentor.exp}}% experience while hunting near them, until you graduate at level {{mentor.graduation}}.
::: end

## Level 50-150: ascension and your first rifts

- **Where to hunt.** Wyrm (50-80), Rustheap Golem (60-80), Serpent Spawn (35-105), Dawnfire Asura (20-105), Hellspawn (80-135), Blightwalker (95-150), Usurper Archer (110-140) and Demon Outcast (120-140).
- **Arena.** At level {{arena.minLevel}}, Adventure > Arena. One goal of this bracket is to win a match.
- **Bestiary.** Each stage (Discovered, Studied, Mastered, Completed) gives bonus experience against that creature. Fill 25 creatures in the Bestiary.
- **Ascension at level {{class.ascensionLevel}}.** Talk to the Ascendant Oracle in the market of the teleport room. Gather the Proof of Strength ({{ascension.proofPoints}} points: a rare monster is worth 1, a legendary 3) and win a {{ascension.trialTime}} trial. If you lose, try again after {{ascension.retry}}.
- **Vocation Trial.** At the Keeper of Trials (market of the teleport room) or with the **Trials** button of the Passive Tree window. Normal at level {{trial.normalLevel}}. Every clear opens a special node pair in the tree.
- **Rifts.** Tier 1 opens at level {{rift.level1}}. Use the key in a protection zone; up to {{rift.maxPlayers}} players. From level 100, Bounty Board contracts can give a tier 1 key. See the [Rifts](wiki:guide:rifts) guide.
::: if descent.on
- **{{descent.name}}.** Level {{descent.minLevel}}, Adventure > Ember Descent. See [its page](wiki:dungeon:descent).
::: end
- **Dungeons and the tower.** Adventure > Dungeons (Alt+J), in {{dungeon.difficulties}} difficulties: kill 85% of the monsters to open the boss. The [Infinity Tower](wiki:dungeon:tower) is in Adventure > Infinity Tower.
- **Factions.** Adventure > Factions. Reach Trusted with one of them at level 120.

## Level 150-300: veteran

- **Where to hunt.** Fleshcarver (145-155), Ironhorn Slagworks (155-185), Venomthread Fen (165-195), Azuregate Reliquary (180-220), Drownbell Depths (196-240), Blackblade (150-300), Emerald Mage (180-270), Bonechoir Catacomb (200-290), Sulphur Gallery (215-299) and deathrattle (230-300).
- **Rifts.** Tier 2 at level {{rift.level2}}, tier 3 at {{rift.level3}}. Bring a party: more players, more reward.
::: if pocket.on
- **Pocket bosses.** Adventure > Boss Spawns, **Pocket** button: a private copy of a boss, {{pocket.charges}} charges a day. Raid bosses from level {{pocket.raidLevel}}, island bosses from {{pocket.islandLevel}}. Vessa Hollowmark in the market of the teleport room looks after them.
::: end
- **New classes.** At level {{class.unlockLevel}} {{class.lockedNames}} open for the account.
- **Charms.** Character > Charms: new cells open at levels 200, 400, 600 and 800.
- **Level 200 goals:** rift tier 4, a unique item, 10 Infinity Tower floors, 25 contracts.
- **Cruel Trial** at level {{trial.cruelLevel}}, at the same Keeper of Trials.

## Level 300-500: world bosses

- **Where to hunt.** Aeliana (280-310), grothar (300-335), fangclaw (305-390), Hollow Crypt (300-400), Wanwick Cloister (370-430), Brinescar Strand (390-450), Rustcog Warrens (420-480), Mossgrave Tangle (450-506) and, close to 500, Widowmere (480-640).
::: if worldboss.on
- **World bosses.** Level {{worldboss.minLevel}}. One at a time at {{worldboss.times}} (server time); the portals open beside the temples. See [Bosses](wiki:guide:bosses).
::: end
- **Rifts.** Tier 4 at level {{rift.level4}}, tier 5 at {{rift.level5}}. From tier {{rift.omenMinTier}} Omens appear: {{rift.omenKeyCost}} fragments make an Omen key.
- **Merciless Trial** at level {{trial.mercilessLevel}}. That level also brings the first Orb of Grafting goal.
- **Faction:** reach Honored. The quartermasters sell fixed gear at Honored and Revered.
- **Tree:** at level 300 you already have {{tree.points300}} points. The first kill of each major boss gives +1 passive point.

## Level 500-750: hardened

- **Hall floor 6 (levels 500-1000).** Gloomtooth Caverns (500-615), Wyrmspine Hollows (500-640), Brackwater Sloughs (515-630), Pyrarch Crucible (520-690), Sablemourn Ossuary (530-645), Thornmantle Glade (545-660), Embergut Rift (560-675), Frostvein Reach (575-690), Graveknell Catacombs (590-705), Umbral Sink (605-720), Cinderscour Barrens (620-735), Bramblegrave Reach (630-770), Grimlock Vaults (635-750) and Blackmarble Halls (650-765).
- **Rifts.** Tier 6 at level {{rift.level6}}, tier 7 at {{rift.level7}}, tier 8 at {{rift.level8}}.
- **Level 500 goals:** 5 world bosses, an item with 5 modifiers, 25 Infinity Tower floors, 10 completed Bestiary creatures.
- **Faction:** Revered at level 600.
- **Gear.** Reroll and improve it on the Crafting Bench (Alt+C). Break down what you don't need in Economy > Salvage. See [Items](wiki:guide:items) and [Economy](wiki:guide:economy).

## Level 750-1000: the road to 1000

- **Where to hunt.** Hexwood Thicket (720-840), Scorchpit Delve (740-855), Bonewright Galleries (770-885), Corsairs' Reach (780-900), Sunderstone Wastes (800-915), Obsidian Colonnade (830-945), Sorrowfen Marsh (875-990), Mirefang Basin (880-999), Hollowbell Mausoleum (900-1100), Pyreglass Chasm (920-1035) and Lanternless Catacombs (950-1050).
- **Rifts.** Tier 9 at level {{rift.level9}}, tier 10 at {{rift.level10}}. The highest is tier {{rift.maxTier}}.
::: if raid.on
- **Raid.** {{raid.name}} at level {{raid.minLevel}}, for {{raid.minPlayers}} to {{raid.maxPlayers}} players, in Adventure > Raid: Ashen Sepulchre.
::: end
- **Level 800 goals:** a raid boss, an Omen, the Hollow Vault, 50 pocket bosses. At 900: an Ascended Omen, a full raid clear, rift tier 10.
- **Level {{paragon.startLevel}}.** Paragon begins, in the Passive Tree window: 1 point per level into small stats. You will have {{tree.points1000}} passive points.

## For every bracket

- **Party.** The leader turns on shared experience from the party shield. It only works while nobody is below 2/3 of the highest level, everyone is within 30 tiles and everyone attacked or healed recently.
- **Rest.** Offline, you store rested experience: +100% while it lasts, 2.5 minutes per offline hour, up to 180 minutes. Coming back after 14 days away gives 7 days of +50%.
- **Stamina.** Low stamina halves your loot.
- **Cards.** Decks drop from monsters and task rewards. Carry the deck and use a card inside it to turn it on or off. See Character > Character Info > Card Deck.

## Glossary

- **Band:** the level range of a hunt or of a group of goals.
- **Magic, rare, legendary monster:** monsters with a tier, in blue, yellow and orange. They drop better gear.
- **Bounty:** a daily contract from the Bounty Board.
- **Rift:** a random area opened with a tier key.
- **Omen:** a special rift from tier {{rift.omenMinTier}}.
- **Ascension:** your class specialisation at level {{class.ascensionLevel}}.
- **Paragon:** extra points from level {{paragon.startLevel}}.
- **Protection zone:** an area without combat, such as the temple.
- **Bestiary:** the record of creatures; each stage gives bonus experience.
