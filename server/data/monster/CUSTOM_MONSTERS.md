# Custom monsters

**Loading.** Lua monsters: drop a `.lua` anywhere under `data/monster/` (the server loads the whole folder, see `_template.lua.example` in `lua/chaos/`). XML monsters: put the file in `monsters/chaos/` and run `python3 -I server/tools/register_monsters.py data/monster/monsters.xml data/monster/monsters/chaos`, which adds the missing entries (safe to re-run).

**Checking.** `python3 -I server/tools/check_monsters.py items.otb 1465 data/monster` flags a lookType above the outfit count of your `Tibia.dat` (no sprite on the client), corpse or loot ids missing from `items.otb`, and, with `--known names.txt`, undefined summons.

**Importing from another server.** `server/tools/adapt_monsters.py` replaces unknown corpse ids with a fallback and drops loot lines whose item does not exist here. It does not touch lookType.

## What was imported
Our map (`exodus-spawn.xml`, `newcity-spawn.xml`) spawns 958 monster names. 98 of them (19,530 spawns) had no definition in the Exodus package, so those spawns were silent. Found definitions for 90: 85 XML from the Evolisca server (`monsters/chaos/`) and 5 Lua from Hellgrave v6 (`lua/chaos/`). Still undefined: demon (goblin), horse1, horse3, labirint, litle devil, nomadfemale, training monk, yalaharimonster (1,389 spawns; they look like placeholder names).

Adaptations (`adapt_report.txt`): 147 changes, mostly Evolisca's corpse id 41162 (not in our items) replaced by 6068, and loot lines for items that do not exist here removed. A common one is item 40407 in almost every Evolisca monster, which looks like a server-specific token: its drops are gone until we decide what it is.

**Open: sprites.** 26 of the imported monsters use a lookType above the 1465 outfits in our `Tibia.dat` (`needs_sprites.txt`). Until their sprites are merged into our dat/spr they will be invisible or wrong on the client. Whether the lower lookTypes show the same creature as in the source server is also still unverified.

**Not checked:** attack and spell names against our spells, and balance (stats were copied as is).
