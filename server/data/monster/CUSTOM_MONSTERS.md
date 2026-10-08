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
- Still without a sprite: Golden Dragon (kept on our outfit 1445 in `outfit_mapping.csv`), Scaleborn (art rejected), both in `needs_sprites.txt`, and 5 names with no lookType.
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
  render with their art. Dawn Strayer (lookType 1036) draws as a broken striped image, so it is not spawned; Cunning Hyaena
  (1051) draws a green tentacled creature that does not read as a hyaena, also left out.

**Treasure Goblin.** `monsters/chaos/treasure_goblin.xml` is our own (lookType 297, the stock goblin scavenger, checked in the
test client). Its health, speed, experience and loot are set by `data/scripts/chaos/treasure_goblin.lua` from the area level, and
its `runonhealth` must stay equal to `runThreshold` in `treasure_goblin_config.lua` (the flee-on-first-hit trick). It spawns only
by replacing a rare natural respawn; never put it in a spawn file. See `server/README.md` "Treasure goblins".
