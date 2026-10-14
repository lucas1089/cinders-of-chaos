# Content list

Everything the game already has, in one place. Written for the owner on 2026-10-14.

Rules for this list:

- Only items marked `done` or `in progress` in ROADMAP.md. In-progress items say so.
- "Done" in the roadmap often means "unit tested, not run on a live server". This list does not repeat every test
  note. See ROADMAP.md for the exact status of each row.
- Counts were taken from the files on 2026-10-14. Where a count comes from a doc, the doc is named.

## 1. Summary

| What | Count | Source |
|---|---|---|
| Base classes | 7 | docs/CLASSES.md |
| Ascended classes | 14 (two per base class) | docs/CLASSES.md |
| Vocations in all | 21 | server/README.md "Vocation Trials" |
| Chaos spells | 88 | `game_chaosspells/spelldata.lua`, `data/spells/chaos/` |
| Spell supports | 20 | Codex "Supports" |
| Custom monster types (XML) | 182 | `data/monster/monsters/chaos/` |
| of these: pets | 15 | `monsters/chaos/pets/` |
| Custom monsters (Lua) | 4 | `data/monster/lua/chaos/` (plus one example file) |
| World bosses | 5 | `monsters/chaos/world_bosses/` |
| Our own boss types | 20 | world 5, Omens 3, Ascended 4, Sepulchre 5, guild 1, ascension 1, trials 1 |
| Bosses tracked in the Boss Spawns window (fixed list) | 66 | `bossspawns_config.lua` |
| Dungeons (queue) | 5 | 4 base dungeons + The Hollow Vault |
| Generated hunting areas | 3 | `areagen_config.lua` |
| Rift themes | 4 | `rift_config.lua` |
| Rift modifiers | 36 | `rift_config.lua` `mods` |
| Rift Atlas nodes | 81 | `atlas_config.lua` |
| Item rarities | 15 | Codex data |
| Item modifiers | 77 | Codex "Modifiers" |
| Legendary powers | 12 | Codex "Powers" |
| Uniques | 106 | Codex "Uniques" |
| Item sets | 10 | Codex "Sets" |
| Orbs, keys and currencies | 24 | Codex "Orbs" |
| Gems | 7 (+ sockets) | Codex "Gems" |
| Profession materials | 20 | Codex "Materials" |
| Passive tree nodes | 663 (root included) | `passivetree_data.lua` |
| of these: notables / keystone entries / masteries | 123 / 46 / 4 | wiki "Passive tree" tab |
| Paragon stats | 8 | server/README.md "Paragon" |
| Charm kinds | 4 shapes + 4 uniques | server/README.md "Charms" |
| Achievements | 173 in 10 categories | server/README.md "Achievements" |
| World hunts per band | see section 4 | docs/CONTENT.md |
| Tales (story quests of our own) | 4 | docs/CONTENT.md |
| Base quest lines | 35 lines, 310 missions | docs/CONTENT.md |
| Seasonal Journey chapters | 8 | docs/CONTENT.md |
| Lore entries | 29 | Codex "Lore" |
| Store offers | 456 in 35 categories | `shop_config.lua` (loaded and counted) |
| Cosmetics (account unlocks) | 91 | `cosmetics_config.lua` |
| Never-sold exclusives | 39 | `exclusives_config.lua` |
| Transmog appearance sets | 37 | `transmog_config.lua` |
| Hideout themes / decorations | 4 / 54 | `hideout_config.lua` |
| Client modules (overlay) | 102 | `client/overlay/modules/` |
| Website plugin pages | 18 | `website/overlay/plugins/chaos/pages/` |
| Wiki tabs / guides | 19 / 14 | `wiki/wiki_data.json`, `wiki/guides/` |
| Languages | 2 (English, Portuguese Brazil) | pt-BR client is in progress |

## 2. Classes and progression

Seven class lines. Each picks one of two ascended classes through the Ascension quest.

| Base class | Plays as | Ascended A | Ascended B |
|---|---|---|---|
| Warrior | melee, heavy armour | Juggernaut (tank) | Berserker (two-handed area) |
| Ranger | bows and crossbows | Deadeye (best single target) | Beastmaster (pet, arrow splash) |
| Mystic | spells, wands, rods | Elementalist (best area) | Illusionist (best healer, party buffs) |
| Thief | fast light weapons, stealth | Ninja (burst, dual wield) | Samurai (duelist off-tank) |
| Necromancer | summoner | Lich (curses, drain) | Bone Lord (skeleton army) |
| Monk | fists, chi | Shadowfist (burst) | Iron Sage (second healer) |
| Templar | holy melee, party aura | Inquisitor (holy area) | Sentinel (tank-support) |

Status per class item (ROADMAP.md "Then: class rework"):

- C1 Vocations and scripted ascension: done.
- C2 Thief, Ninja, Samurai: **in progress**. Kit, healing, gear, passive tree done.
- C3 Rework of the old kits: **in progress**. Phase 2a done.
- C4 Passive trees, icons, effects, outfits: passive trees done. Class looks in pairs 19 and 20, live.
- C5 Necromancer, C6 Monk, C7 Templar: **phase B**. Tested in game, level 300 measured.
- C8 Store unlock for Necromancer, Monk, Templar: **phase B**. Tested in game. Final unlock method open.
- C9 Ascension quest: done. The Ascendant Oracle, Proof of Strength, a class Trial, the Choice.
- C3a Illusionist healer pass: done.

Progression systems:

- **Passive tree.** 663 nodes, about 248 points at level 1000. Class sections, keystones, notables.
- **Keystones per class.** Two per line where planned (#2, #106). Done.
- **Path notables.** 27 small nodes turned into named notables (#105). Done.
- **Mastery nodes.** 4, pick one effect each (#103). Done.
- **Tree planner.** Plan, search, apply once, inspect other trees (#103). Done.
- **Build sharing.** Export and import a tree code (#18). Done.
- **Build archetypes.** At least two per class line, two rounds (#110, #111). Done.
- **Snares and vigils.** Archetype mechanics with reserved mana (#111). Done.
- **Paragon.** One point per level after 1000, 8 small stats (#9). Done.
- **Respec.** Cost scales with level (#19). Done.
- **Loadouts (Armory).** Save whole builds and switch (#65). Done.
- **Vocation Trials.** Solo arenas per class, Normal / Cruel / Merciless. 7 families. Done.
- **Class looks and signature effects.** An outfit per class line, 35 signature effects. Done.
- **Experience curve.** Smoothed after 700; late game spawns (#4, #5). Done.
- **Experience cap and display scale.** Damage shown in millions at the end game (#128). Done.
- **Level-up wings.** Golden wings on level up (#84). Done.
- **Waystone upgrades.** Experience, Loot, Rarity upgrades fixed (#6). Done.

## 3. Combat and spells

- **88 Chaos spells** across 20 spell folders (one per class and a shared set).
- **20 spell supports.** Socketed into spells (Fork, Echo, Siphon, brands and more).
- **Cast-time spells** with a cast bar. Done.
- **Combat visuals.** Elemental damage numbers, crit, dodge and reflect sprites (#3). Done.
- **Energy shield.** Engine patch 0015, pure energy shield build (#111). Done.
- **Percent armour.** Engine patch 0016. Done.
- **Attack speed cap, uniform crit and leech rolls.** Engine patches. Done.
- **Movement speed.** Players walk 15-30% faster. Done.
- **Infinite arrows and quivers.** Bows fire without ammo; quivers in the off-hand (#87, #90). Done.
- **Second ring slot.** The ammunition slot holds a ring (#90). Done.
- **Fist weapons** for the Monk. Done.
- **Keep attacking while moving** (#95). Done.
- **Rotations of at most 5 spells** per class (#140). Done.
- **Helper rotation** that waits for the server (#138). Done.
- **No conjuring.** Runes come from vendors and crafting (#130). Done except two blocked hunks.
- **Boss mechanics.** Telegraphs, adds phases, enrage, soaks, channels, pillars (#129). Done.
- **Large spell effects** 5x5 to 9x9 tiles (#116). In pair 24, on since 2026-10-13.
- **Spell effect opacity slider** (#117). Done.
- **Display scale** for big numbers (#128). Done.

## 4. World and hunts

From docs/CONTENT.md (measured with `tools/content_audit.py` on the loaded map).

| Band | World hunts | Spawn entries | Parties at once | Other areas | Story quest |
|---|---|---|---|---|---|
| 1-20 | 526 | 18,486 | 727 | tutorial island | tutorial, base lines |
| 20-50 | 403 | 12,801 | 508 | - | base lines |
| 50-100 | 218 | 10,005 | 360 | - | base lines |
| 100-200 | 156 | 5,569 | 204 | - | Ascension, Trials |
| 200-300 | 32 | 805 | 35 | 2 planned | The Bone Choir |
| 300-500 | 105 | 3,537 | 138 | - | world boss and faction lines |
| 500-700 | 14 | 280 | 14 | 3 planned | The Wyrm Tithe |
| 700-1000 | 10 | 212 | 10 | Hollow Vault, 3 planned | Requiem for the Ash-Sister |
| 1000+ | 0 | 0 | 0 | 3 generated, 6 planned | The Last Ember |

The whole loaded map: 5.36 million walkable tiles, 74,071 spawn entries, 1,195 hunting areas (ROADMAP #89).

World content:

- **Tutorial island.** Five stations: passive tree, orbs, keystones (#22). Done.
- **New-player kit** per vocation (#21). Done.
- **First hour hints.** Nearest hunts marked on the map at set levels. Done.
- **Late game spawns.** 17 imported monsters in four level 500+ areas (#4). Done.
- **Spawn density and respawn** tuned for launch (#89). Done.
- **Generated areas** for 1000-1300 (#109). Done, entrances on the full map not run:
  - Emberdeep Hollows (cave), boss The Emberdeep Maw, level 1100.
  - Sunken Ossuary (dungeon), boss The Ossuary Warden, level 1200.
  - Cinderfall Wastes (waste), boss Cinderwing, level 1300.
- **Own town, item, monster and NPC names** for the base world (#88). Done.
- **Dark tile set** of our own (#33). Done.
- **Pack items, monsters and tiles** from the art sets (#38). Done.
- **Custom monster families.** Goblin tribe (15 types), Wildwood (24 types). Done.
- **Treasure goblins.** Rare fleeing monster with a hoard (#24). Done.
- **Bestiary and kill tasks** with a task tracker, 18 categories (#35). Done.
- **Map markers.** Party members and points of interest (#94). Done.
- **Town Portal** and hideout travel. Done.
- **Ember Blessings.** 10 one-minute kill blessings (#74). Done.
- **Nemesis.** A monster that kills you may become your Nemesis (#141). Done.

Quests:

- **Tales.** Four story quests from Archivist Maelis (#142). Done, not run on a live server.

| Tale | From level |
|---|---|
| The Bone Choir | 200 |
| The Wyrm Tithe | 500 |
| Requiem for the Ash-Sister | 800 |
| The Last Ember | 1000 |

- **Ascension quest** at level 100 (C9). Done.
- **Vocation Trials** at 100-250, 250-500, 400-1000. Done.
- **Base quest lines.** 35 lines, 310 missions, renamed at install.
- **Lore.** 29 entries in the Codex and wiki Lore tabs, and as books.

## 5. Bosses

Our own bosses (own monster files):

| Group | Bosses | Where |
|---|---|---|
| World bosses (5) | Kaelgor the Infernal Warlord, Skaldra the Rime Queen, The Rotmother, Nyxareth the Void Archon, Vharok the Blood Colossus | world boss arena, every 6 hours from level 300 |
| Omens (3) | Sangrith the Bloodmoon Herald, Morvane the Hollow Crown, Thalcyra the Stormbound Seer | Omen Keys, level 800 |
| Ascended Omens (4) | Ascended Sangrith, Ascended Morvane, Ascended Thalcyra, Ysgrath the Cinderheart | Ascended sigils and relics, 900 / 1000 |
| Ashen Sepulchre (5) | Gravewarden Ulthar, Morwen the Ash-Sister, The Marrow Colossus, Vhoss the Hexmaw, Varkhul the Ashen Sovereign | weekly raid, 5-15 players |
| Guild boss (1) | Gorvath the Banner-Eater | guild hall Summoning Stone, weekly |
| Ascension (1) | Ascension Warden | Ascension Trial |
| Trials (1 type, 7 faces) | Gauntlet Champion, Moon Stalker, Keeper of the Seals, Master of Shadows, Warden of the Still Fist, Tithe Collector, Pyre Warden | Vocation Trials |

Other bosses in the game:

| Group | Count | Notes |
|---|---|---|
| Rift Guardian | 1 per rift | any Rift Key; 4 big guardian looks (#115) |
| Twin and Dread guardians | rift modifiers | Twin Guardians, Dread Guardian, Wrathful Guardian |
| Ember Descent boss | 1 per run | last room of the Descent |
| Generated area bosses | 4 | Emberdeep Maw, Ossuary Warden, Cinderwing, Vault Keeper Ossrim |
| Base dungeon bosses | 4 | Prince Skeletal, Master of the Elements, Forbidden Chevalier, The Rootmaw |
| Infinity Tower bosses | 12 | every 10th floor |
| Invasion bosses | 8 | one or two per faction, by area level |
| Island bosses (base) | 10 | once a week each |
| Raid bosses (base) | 25 | random base raids |
| Lair bosses (base) | 15 | map spawns with a timer |
| Rare spawn | 1 | Treasure Goblin |

Boss systems:

- **World boss roles.** Damage, healer and tank podiums and titles (#13, #32). Done.
- **Boss Spawns window.** Every boss by category, place and respawn (#52). Done.
- **Boss mechanics** on the key bosses (#129). Done.
- **Solo kill times** computed for every boss group (#127). Done, computed only.
- **Competitive records.** Fastest kills of every boss group (#135). Done.

## 6. Dungeons, rifts, raid, tower and other instances

| Instance | What it is | Status |
|---|---|---|
| Dungeons (5) | Queue alone or in a party; 6 difficulties; speed and flawless challenges | done |
| The Hollow Vault | Generated dungeon 5, level 800, boss Vault Keeper Ossrim | done |
| Rifts | Rift Keys open a timed generated map; 4 themes, 10 tiers and beyond, 1-3 of 36 modifiers (#8) | done |
| Rift Atlas | Completion grid and an 81-node map (#54) | done, not run live |
| Omen arenas | Three Omen guardians from Omen Keys | done |
| Ascended Omens and the Cinderheart | Top challenge above the Omens (#57) | done, party fights not run |
| The Ember Descent | Roguelike run of 8-12 rooms; 16 boons, 5 curses, a merchant, a boss (#59) | done |
| The Ashen Sepulchre | Weekly raid, 5-15 players, loot lockout (#61) | done, a real group not run |
| Infinity Tower | Wave floors, a boss every 10th floor, 30-day tower seasons, top 3 chests (#93) | done |
| Vocation Trials | Solo class challenge, three tiers | done |
| Ascension Trial | The trial of the Ascension quest | done |
| World boss arena | Built at runtime, 40 players | done |
| Guild hall and guild boss | Guild instance and weekly boss (#30, #70) | done |
| Personal hideout | Instanced room per character (#72) | done |
| Instance limits | Time limits, warnings and waiting lines for every instance (#108) | done, not run in game |

## 7. Endgame systems

- **Bounty board.** Daily "kill X" contracts in six tiers, paid in orbs (#10). Done.
- **Seasons.** Fresh-start season characters, season uniques, ladders (#12). Phase 1 done.
- **Season modes.** Self-Found and Hardcore (#62). Done.
- **Seasonal Journey.** 8 chapters per season character (#67). Done, not run live.
- **Season pass.** Free and premium track, 50 tiers (#44, #131). Done.
- **Factions.** Four factions with ranks and contracts (#58). Done, not run live.
  - Ashen Vigil, Cinderforge Compact, Veiled Choir, Thornbound Circle.
- **Community goals** and a weekly world modifier (#60). Done, not run live.
- **Charms.** 5x4 charm grid, four shapes, four unique charms (#76). Done.
- **Professions.** Delving, Wortcunning, Flaying, Angling; 20 materials (#78). Done.
- **The Gambler.** Sealed gear for gold, stock refreshes every 4 hours (#83). Done.
- **Achievements.** 173 in 10 categories, 4,170 points; reward track (#26, #75). Done.
- **Leaderboards.** Weekly boards: world boss, healer, tank, bounty, rifts, class ladder (#13). Done.
- **Competitive records** for bosses, dungeons and the tower (#135). Done.
- **The Ashen Chronicle.** Server-wide story per season (#145). Done, not run live.
- **The Capital Memorial.** Statues and stones for realm firsts and fallen Hardcore (#146). Done, plaza not placed.

## 8. Items and crafting

- **Item rarities.** 15, from Common to Transcendent.
- **Item modifiers.** 77 prefixes and suffixes with tiers by item level.
- **Legendary powers.** 12 powers on Legendary or better items.
- **Uniques.** 106 uniques, some with their own equip rules.
- **Item sets.** 10 sets of 4-6 pieces, bonuses at 2, 4 and 6 (#68). Done.
- **Veiled modifiers.** Revealed by the Orb of Unveiling, pick 1 of 3 (#73). Done.
- **Gems and sockets.** 7 gems: Ruby, Sapphire, Emerald, Amethyst, Topaz, Diamond, Onyx (#36). Done.
- **Crafting orbs.** Codex lists 24 orbs, keys and currencies (#11, #31). Done.
  - Crafting: Awakening, Gilding, Grafting, Unmaking, Erasure, Upheaval, Fate, Sockets,
    Tempering, Binding, Excision, Reforging, Ruin, Unveiling, Echoes, and the Whetstone.
  - Keys and currencies: Rift Key, Omen Key, Omen Fragment, Rune Shard, waystone orbs.
- **Crafting bench** in the client. Done.
- **Salvage and the item lock.** Gear into Rune Shards (#39). Done.
- **Crafting Table window.** 7 categories, 275 base recipes (#79). Done.
- **Crafting bonus.** Crafted gear rolls a Chaos rarity (#80). Done.
- **Rune supply.** 36 runes from vendors and crafting (#130). Done.
- **Item prices.** Every item has a sell price, rarer items worth more (#139). Done.
- **Rich tooltips** with an equipped-item compare (#40). Done.
- **Item links in chat.** Done.
- **Item finder.** "Where does this drop" (#100). Done.
- **Codex.** In-client encyclopedia: modifiers, powers, orbs, gems, uniques, sets, rift, lore. Done.
- **Themed art.** Ten equipment sets, two auras, runic wings, grounds (#112). Built, switch on, not run in a client.

## 9. Events and seasons

- **Event calendar.** Four recurring server days (#29). Done.
  - Blood Moon (weekends, +50% XP), Chaos Rift (Wednesday), Loot Frenzy (Friday),
    Tower Ascension (days 1-3 and 15-17).
- **Invasions.** Six factions attack 5 areas in waves (#29). Done.
  - Orc Warband, Undead Legion, Infernal Host, Minotaur Horde, Goblin Tribe, Wildwood Uprising.
- **World events.** Chaos Storm, Golden Hour, Wandering Merchant. Done.
- **World bosses** every 6 hours: 03:00, 09:00, 15:00, 21:00. Done.
- **Weekly world modifier.** For example Ember Tides, Dragonfall, Gilded Week. Done.
- **Guild siege.** Weekly war for the Chaos Obelisk (#15). Done.
- **Seasons, season modes, pass, journey, chronicle, memorial.** See section 7.
- **Daily reward and login streaks** (#20). Done.
- **Boosted creature and boss** on the login screen. Done.

## 10. Social, guild and PvP

- **Guild levels and guild halls.** Levels 1-20, 16 perks, hall upgrades (#30). Done.
- **Guild wars in game.** Declare, stakes, anti-farming rules, war board (#69). Done.
- **Weekly guild boss** (#70). Done.
- **Guild siege** (#15). Done.
- **Arena.** Ranked 1v1, 2v2, 3v3 with ratings (#14, #71). Done.
- **Battleground "Ember Wells".** 5v5 to 10v10 objective map; PvP seasons (#71). Done, 5v5+ on mocks only.
- **The Scorched Marches.** Open-world PvP zone with embers and a faction pledge (#77). Done.
- **Party Finder.** Post a group, apply with a role (#53). Done, not run live.
- **Party frames and buff bar.** Done.
- **Mentors.** Veterans guide new characters (#66). Done, not run live.
- **Referral program.** Codes, welcome gift, titles (#46, #133). Done.
- **Name plates and titles** over every player (#25). Done.
- **Inspect Player.** Gear, tree, achievements of another player. Done.
- **Hideouts** with visits, likes and a showcase (#72). Done.
- **Pets.** 15 species, two abilities each (#34). Done.
- **Discord announcements** by webhook (#144). Done.

## 11. Economy and store

- **Player market** for gold and Chaos Coins (#42). Done.
- **Market buy orders** (#49) and **price history** (#64). Done.
- **Orb Exchange.** Order book for the crafting orbs (#55). Done.
- **Loot Buyer** and the **Auto Seller**. Done.
- **Depot tabs.** 4 free tabs of 100 items, more with the Pact or the store (#85). Done.
- **Chaos Pact.** Subscription and account storage: stash tabs, slots, saved builds (#43). Done.
- **Store pouches.** Loot Bag (255 slots, weightless), orb and key pouches (#41). Done.
- **Everfull Ration.** Infinite food in the store (#136). Done.
- **Donations** for Chaos Coins: Pix and PayPal (#47). Done, live accounts not connected.
- **Creator codes** for streamers (#132). Done.
- **Character Bazaar.** Character auctions for coins on the website (#134). Done.
- **Transmog.** Account-wide wardrobe, 37 appearance sets (#48). Done.
- **Cosmetics.** 91 cosmetics: spell skins, kill effects, loot labels, chat colours, footprints, outlines (#51, #86). Done.
- **Exclusives.** 39 never-sold visuals from achievements and boss drops (#86). Done.

Store: 456 offers in 35 categories (counted from `shop_config.lua`). Prices are placeholders (#137).

| Category | Offers | Category | Offers |
|---|---|---|---|
| Starter | 3 | Hideout Decorations | 9 |
| Bundles | 6 | Appearances | 9 |
| Outfits | 56 | Pets | 7 |
| Outfit Addons | 9 | Crafting | 3 |
| Mounts | 125 | Supplies | 5 |
| Wings | 15 | Runes | 29 |
| Auras | 24 | Boosts | 5 |
| Outfit Shaders | 16 | World Buffs | 3 |
| Name Plates | 13 | Services | 5 |
| Themed Sets (rotation only) | 12 | Convenience | 6 |
| Portal Styles | 6 | Classes | 3 |
| Spell Effects | 12 | Training | 21 |
| Kill Effects | 5 | Chaos Pact | 1 |
| Loot Labels | 4 | Storage & Slots | 6 |
| Chat Colours | 5 | Depot Tabs | 2 |
| Footprints | 9 | Season Pass | 4 |
| Outlines | 9 | Premium Time | 3 |
| Chaos Shaders | 6 | | |

## 12. Quality of life and client features

102 modules in `client/overlay/modules/`. The main player-facing ones:

- **Hunt tracker.** Exp/h, profit/h, supplies (#17). Done.
- **DPS meter and combat log** (#63). Done.
- **Death recap.** Who hit you in the last seconds (#99). Done.
- **Loot filter.** Hide or highlight by rarity, loot channel, rule counters and sounds (#16, #50). Done.
- **Ground loot labels** in rarity colours. Done.
- **Autoloot** with rarity autoloot. Done.
- **Right-click equips** (#91). Done.
- **Field timers** over magic walls and similar fields (#101). Done.
- **Progress bars over tiles** (#102). Done.
- **Spellbook** with search and area grid. Done.
- **Notifications.** Item sold and achievements as toasts (#81). Done.
- **Patch notes window** (#23). Done.
- **Login scene** from game tiles and our monsters (#119). Done.
- **New character select** with cards and in-client creation (#122). Done.
- **Bitmap fonts** at several sizes (#120). Done.
- **Sprite shards** for faster sprite updates (#118). Done, not in the Windows build.
- **Big creatures clickable** on any visible pixel (#126). Done.
- **Painted icons** (#114). Done behind a client setting, off.
- **Shader polish.** Rarity outlines, liquid orbs, frame shine (#113). **In progress**, not run in a client.
- **Signed client updater.** Done.
- **Autosave without the freeze** (#92). Done.
- **Game loop stalls and login reads** fixed (#96, #97, #108). Done.

## 13. Website

ZnoteX with our own layout and plugin (#28). Plugin pages in `website/overlay/plugins/chaos/pages/`:

| Page | What it is |
|---|---|
| wiki | Player wiki, Portuguese and English, search (#121, #123) |
| leaderboards | Weekly boards and records |
| seasons | Seasons with mode tabs and fallen marks |
| patchnotes | Patch notes |
| community | Community goal and world modifiers |
| chronicle | The Ashen Chronicle |
| memorial | The Capital Memorial archive |
| guildwars | Running and past guild wars |
| mentors | Mentors who opted in |
| bazaar | Character Bazaar |
| coins | Donations for Chaos Coins |
| creator | Creator codes |
| legal | Terms, Privacy Policy, Donation Terms |
| accept | Terms acceptance for existing accounts |
| notused | Note shown for stock pages we do not use |
| reports | Staff: player reports and anti-bot log |
| botreview | Staff: bot review |
| telemetry | Staff: balance telemetry charts |

Other website parts:

- Account creation with the classes and the class lock. Done.
- Salted passwords, recovery mail, rate limits. Done.
- Client account API for the character select. Done.
- Item and outfit images from our own client pair (#124). Done.
- Referral code field. Done.
- Wiki art: icons, heroes, banners (#123). Done.

Wiki tabs (19): Classes, Spells, Passive tree, Basics, Modifiers, Powers, Uniques, Sets, Orbs, Gems,
Supports, Rift, Dungeons, Bosses, Events, Monsters, Materials, Lore, Store.

Wiki guides (14, each in two languages): start, classes, tree, items, rifts, dungeons, bosses, seasons,
pvp, social, economy, store, rules, faq.

## 14. Languages

- **English.** Everywhere.
- **Portuguese (Brazil).** Partial. ROADMAP #147 is **in progress**.
  - Client: every Chaos overlay text through `tr()`, choice in Options.
  - Server: about 190 broadcast and message keys through `Chaos.t`.
  - Website: wiki, legal, donation, bazaar, creator, leaderboards pages.
  - Tales, lore and the Chronicle text are in both languages.
  - Left: store messages, NPC dialogue, quest and achievement texts, codex content, tree texts.

## 15. Staff tools

- **Admin panel** in the client (`game_admin`): players, server, world, economy, events, store, tools. Audit log.
- **GM commands.** 28 rows of staff commands in docs/GM_HANDBOOK.md section 2.
- **`/instances`.** List and close any running instance.
- **Test kit.** Gear kits for balance tests. Removed from the live server.
- **Player reports and anti-bot** (#56). Done, not run live.
- **Bot detection and GM review** (#148). Done.
- **Balance telemetry** for staff (#143). Done.
- **Passive tree pick statistics** (#107). Done.
- **Moderation record purge.** Done.
- **Client guard.** Only the official client may play (#82). Done.
- **Launch tools.** Install script, backups, health checks, systemd units (#27). Done.
- **Load and stress tests** on the full map. Done.
- **Area planner.** Compiles semantic area plans to map pieces (#125). Done.
- **Sprite tools.** Outfit composer and pair checker (#104). Done.
- **Content audit.** `tools/content_audit.py` for hunts per band (#142). Done.

## 16. Built but not yet placed on the map

These are finished as plans or code. The owner still has to place them in the map editor.

Planned hunting areas (14, in `server/tools/areaplan/plans/`, docs/CONTENT.md):

| Plan | Levels | Biome |
|---|---|---|
| bonechoir_catacomb | 200-290 | catacomb |
| sulphur_gallery | 215-299 | lava |
| widowmere | 480-640 | swamp |
| wyrmspine_hollows | 500-640 | cave |
| pyrarch_crucible | 520-690 | lava |
| hexwood_thicket | 720-840 | forest |
| corsairs_reach | 780-900 | cave |
| mirefang_basin | 880-999 | swamp |
| rimecrown_depths | 1000-1120 | ice |
| cinderglass_sanctum | 1120-1300 | sanctum, 2 floors |
| slagmourn_foundry | 1000-1150 | lava |
| hollowmass_reliquary | 1150-1300 | crypt, 2 floors |
| gallowfen_mire | 1300-1450 | swamp |
| voidscar_chasm | 1400-1500 | abyss, 2 floors |
| gravehorn_deeps | 1500-1750 | crypt, 2 floors |
| duskmarrow_crater | 1750-2000 | lava, 2 floors |

Each is four times the first draft (2026-10-14); the four 1000-1500 plans and the two 1500-2000 plans were added the
same day. Placed, they lift 500-700 from 14 to about 50 parties at once, 700-1000 from 10 to about 46, 1000+ from 0 to
about 96.

Hunting monsters of 1300-2000 (2026-10-14), one every 100 levels, our own on unused looks of the live pair:
Gloamfang Ravager, Rimeshroud Revenant, Cinderskull Reaver, Bloodantler Fiend, Cinderhorn Juggernaut, Wraithbone
Stalker, Mirecoil Wyrm, Pyrewing Tyrant (server/README.md "Late game").

Chronicle and memorial areas (in `server/tools/areaplan/chronicle/`):

- **Cinderscar Breach.** Waste, 128x104, levels 440-560. Chronicle area.
- **Ossuary Stair.** Crypt, 120x104, levels 400-520. Chronicle area.
- **Capital Memorial plaza.** Hall, 48x40, in the capital. Statues and stones placed by script.

Other open placement work (docs/CONTENT.md "For the owner"):

- Signposts by the first temple.
- Check the art of dormant monsters before their plans go live.
- 32 level-scaled monsters of 650-1300 still spawn nowhere. The plans give 29 of them a home.

## Not verified

- Many systems are "done" on unit and mocked-engine tests only. ROADMAP.md says which ones.
- The 66 Boss Spawns entries count the fixed list only. World, tower, trial, dungeon and invasion bosses are added at runtime.
- Keystone entries (46) include variants: some keystones appear once per class.
- The Codex "Orbs" count (24) mixes crafting orbs, keys and currencies.
- Achievements (173) and base quest lines (35 / 310) are taken from the docs, not recounted.
