# Custom monsters

**Loading.** Lua monsters: drop a `.lua` anywhere under `data/monster/` (the server loads the whole folder, see `_template.lua.example` in `lua/chaos/`). XML monsters: put the file in `monsters/chaos/` and run `python3 -I server/tools/register_monsters.py data/monster/monsters.xml data/monster/monsters/chaos`, which adds the missing entries (safe to re-run).

**World bosses.** `monsters/chaos/world_bosses/` holds the five world bosses of `worldboss.lua` (our own, not imported). Register that folder too: `python3 -I server/tools/register_monsters.py data/monster/monsters.xml data/monster/monsters/chaos/world_bosses`. See `server/README.md` "World bosses".

**Checking.** `python3 -I server/tools/check_monsters.py items.otb 1504 data/monster` flags a lookType above the outfit count of your `Tibia.dat` (no sprite on the client), corpse or loot ids missing from `items.otb`, and, with `--known names.txt`, undefined summons.

**Importing from another server.** `server/tools/adapt_monsters.py` replaces unknown corpse ids with a fallback and drops loot lines whose item does not exist here. It does not touch lookType.

## What was imported
**Correction (they did not spawn).** The figures below were counted over two spawn files, and the 19,530 spawns of the imported
names are almost all in the spawn file of a second map that the server does not load (`mapName` in `config.lua` names the
loaded one). On the loaded map none of the 85 imported XML monsters spawned (only the 5 Lua ones from `lua/chaos/` do,
98 spawns). Since the late game work 17 of the XML ones do, in four
level 500+ areas, with clamped levels and retuned stats: `server/tools/late_game.py` and `server/tools/late_game_spawns.csv`,
see `server/README.md` "Late game". The other imported XML monsters are still registered but spawn nowhere on the loaded map.

The two spawn files together spawn 958 monster names. 98 of them (19,530 spawns) had no definition in the base server package, so those spawns were silent. Found definitions for 90: 85 XML from the donor server (`monsters/chaos/`) and 5 Lua from the second donor server (`lua/chaos/`). Still undefined: demon (goblin), horse1, horse3, labirint, litle devil, nomadfemale, training monk, yalaharimonster (1,389 spawns; they look like placeholder names).

Adaptations (`adapt_report.txt`): 147 changes, mostly the donor server's corpse id 41162 (not in our items) replaced by 6068, and loot lines for items that do not exist here removed. A common one is item 40407 in almost every donor server monster, which looks like a server-specific token: its drops are gone until we decide what it is.

**Sprites (done in the files, one step left for you).** A sprite check (`client/tools/sprites/`, report in `sprite_report.csv`) rendered each monster's lookType from a source `Tibia.dat/spr` and compared it with ours. The source pair is the donor client's 10.98 set; the donor server's own dat was not in the folder, and the donor client art matched the donor server names for nearly everything checked by eye, but two did not (Golden Dragon, Scaleborn: left unmapped). Result for the 98 spawned names: 37 already show the right art, 27 had the wrong art at that lookType in our dat (ids 900 to 1465 differ between servers), 24 were above our 1465 outfits, 5 have no sprite in the source, 5 have no lookType anywhere.
- 36 outfits were appended to a copy of our dat/spr as ids 1466 to 1501 and 12 monsters were pointed at an equal outfit already in our dat. `outfit_mapping.csv` lists every old to new lookType, and the monster XML files here already use the new ids.
- **You must build the merged dat/spr** (the spr is 494 MB, too big for git): `python3 -I client/tools/sprites/merge_outfits.py --src-dat <donor client Tibia.dat> --src-spr <donor client Tibia.spr> --ours-dat <base server Tibia.dat> --ours-spr <base server Tibia.spr> --report server/data/monster/sprite_report.csv --out-dir out/merged`, then use `out/merged/Tibia.dat` and `Tibia.spr` as the `data/things/1098` pair of the client. Without them the remapped monsters show wrong art.
- Verified in the sandbox: the merged dat parses (1501 outfits), the 36 new outfits render pixel-identical to the source, and 60 random original outfits are unchanged. Not verified in a real client. Six custom dat flags (39, 41, 42, 43, 46, 62) were stripped from the copied entries; their meaning is a guess.
- Golden Dragon and Scaleborn have donor B looks since 2026-10 (outfits 1530 and 1531, the first donor set below); 5 names
  still have no lookType.
- **Mercenary, Mercenary Ranger, Mortal Illusion: outfits 1502, 1503, 1504.** Their art comes from a second donor sprite set
  in the OLD 8.60 dat flag layout (dat signature 0x4C2C7993 with frame groups and u32 sprite ids, alpha spr 0x4C220594,
  2799 outfits; donor lookTypes 1719, 1718, 1656). Its entries cannot be copied byte for byte, so
  `client/tools/sprites/import_outfits.py` converts them: flags re-encoded with our 10.98 table, frame groups, patterns,
  layers and animator kept, sprite records appended to our spr. Run it after `set_multiuse.py` and before
  `gen_dark_tiles.py`; the full rebuild chain is merge_outfits.py -> gen_effects.py -> set_multiuse.py -> import_outfits.py
  -> gen_dark_tiles.py:
  `python3 -I client/tools/sprites/import_outfits.py --src-dat <8.60 donor Tibia.dat> --src-spr <8.60 donor Tibia.spr> --ours-dat <pair after set_multiuse>/Tibia.dat --ours-spr <same>/Tibia.spr --looks 1719,1718,1656 --expect-first 1502 --out-dir out/monsters`
  (`--expect-first` stops the run when the input pair does not have exactly 1501 outfits). It verifies its output: every
  sprite slot and frame of the three outfits pixel-identical to the donor, all old entries byte-identical.
- **Ninja and Samurai class outfits: 1505-1510** (docs/CLASSES.md). Donor: a third 10.98 sprite set (dat 0x42A3, spr
  0x57BBD603) whose items carry flags datspr.py does not know, so `client/tools/sprites/donor_subset.py` first cuts a small dat
  with just the wanted outfits (same numbering), then `import_outfits.py` appends them after the three monster outfits:
  `python3 -I client/tools/sprites/donor_subset.py <donor C>.dat out/donorC.dat 4212,4220,3482,4234,4206,1584`, then
  `python3 -I client/tools/sprites/import_outfits.py --src-dat out/donorC.dat --src-spr <donor C>.spr --ours-dat <pair with 1504 outfits>/Tibia.dat --ours-spr <same>/Tibia.spr --looks 4212,4220,3482,4234,4206,1584 --expect-first 1505 --out-dir out/classes`.
  The chain is now merge_outfits.py -> gen_effects.py -> set_multiuse.py -> import_outfits.py (monsters) ->
  donor_subset.py + import_outfits.py (class outfits) -> gen_dark_tiles.py. Verified: the six outfits pixel-identical to the
  donor in every group, phase and direction, all old entries byte-identical, the rebuild reproduces the same md5s
  (dat 6266a15d49e304b6c05c01ecb458d00a, spr 4c66dff2ef6a48870e58d5c30c45707d); checked in the test client (Shadow Ninja worn).
- Checked in the test client (merged pair: 1501 outfits + the Chaos effects), for the late game set: the 17 spawned monsters
  render with their art. Dawn Strayer (lookType 1036) drew as a broken striped image, so it was not spawned (it has art
  2122 now and spawns, see below); Cunning Hyaena (1051) draws a green tentacled creature that does not read as a hyaena,
  also left out.

**Treasure Goblin.** `monsters/chaos/treasure_goblin.xml` is our own (lookType 297, the stock goblin scavenger, checked in the
test client). Its health, speed, experience and loot are set by `data/scripts/chaos/treasure_goblin.lua` from the area level, and
its `runonhealth` must stay equal to `runThreshold` in `treasure_goblin_config.lua` (the flee-on-first-hit trick). It spawns only
by replacing a rare natural respawn; never put it in a spawn file. See `server/README.md` "Treasure goblins".

**Goblins and the wildwood (`monsters/chaos/goblins/`, `monsters/chaos/wildwood/`).** 39 monsters of our own on the new
outfits 2000-2038 (client `import_art_things.py`, server/README.md "Pack items and monsters"), each with its own corpse
(36061-36099) and loot of creature products and food (36010-36060, step `packitems`). They have no `<level>` tag (normal
hunting monsters, no level skull). Not in a spawn file yet: they come with the invasion factions Goblin Tribe and Wildwood
Uprising. Cunning Hyaena now uses the Forest Wolf outfit 2015 (sand colours) instead of the wrong art at 1051. The XML
files were generated from a table (stats per monster: health, experience, speed, armor, attacks scaled by hunting level);
edit them by hand from now on.

**Monster looks 2100-2125 (things_custom11).** A sprite audit against things_custom10 found every lookType inside the
pair, but seven monsters without real art. Saga 1487 showed only a few specks. Gloomfire 1197 and Zaoan Badger 1249 sat
on unrelated stock player outfits (the source pair had no sprite for them). Dawn Strayer 1036 drew broken. Plant 353
was a stock worm, Tarrasque 268 a stock player outfit, and Cunning Hyaena borrowed the Forest Wolf 2015. They now have
donor-library creatures: Saga 2119, Gloomfire 2120, Zaoan Badger 2121, Dawn Strayer 2122, Plant 2123, Tarrasque 2124,
Cunning Hyaena 2125. The Omen guardians got rift-exclusive looks: Sangrith 2116, Morvane 2117, Thalcyra 2118 (Thalcyra
shared 842 with Kroazur). 2100-2115 are the rift family looks that rift.lua puts on rift monsters (server/README.md
"Rifts"). No monster file may use them.
- Picks and sources: `client/tools/sprites/monster_looks/picks.csv` and `sources.csv`; the client pair is built by
  `donor_pick.py` + `import_outfits.py --first-outfit 2100` (client/MANIFEST.md "Monster looks pair").
- `python3 -I server/tools/apply_monster_looks.py` (new) writes the looks of picks.csv into the monster XML files by
  monster name. It removes the colour attributes, which these looks do not use, and keeps the corpse. It is idempotent.
  `--check` changes nothing and also checks that no file uses a rift family look and that `rift_config.lua` matches.
- Shared looks left as they are, on purpose: the elite variants share their base monster's look (Elite Ice Dragon,
  Elite Twisted Shaper, Elite Ice Witch / Frost Maiden), Trial / Ascension Warden 1540, Warden Shade / Trial Thrall 233,
  Phantom Shade / Alptramun 1479, the Gilded Goblin pet / Shard Goblin 61.
- Corpses are unchanged: the generic 6068 for most, and the old stock corpses for Sangrith (22562) and Thalcyra (9780).
  Dawn Strayer (2122, an armoured beast with a burning mane) now spawns: it was left out of `late_game.py` only for
  its broken look, and its file was still the donor's (level 1150-1250, 110k health, a 2,000,000 physical area hit, the
  donor events, "one of" loot lines). It is now tuned like the late-game tier 3 it joins (server/README.md "Late
  game"): level 960-1000, 22,000 / 13,900 / 50 (health / experience / speed, as Malofur Mangrinder), melee 540-820,
  a radius 3 physical burst 300-610, an energy bolt 460-840, a fire wave 380-770 (measured next to Malofur in game, see
  the README table), the late-game elements, the donor events removed, its loot lines split one per item. `late_game_spawns.csv` puts it on 9 Darklight Core entries (three
  packs of three on floors 12, 13 and 14).
- Rift monsters wear the rift names of `rift_config.lua` `looks.names` ("Abyssal Spawn" ... "Sanctum Warden"); no
  monster file may use one of those names either (`tests/rift_test.lua`).

