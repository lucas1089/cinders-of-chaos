# Ideas for later

Ideas kept for future work (owner, 2026-10-13). None is planned yet. The full research, with sources, links and
licences, is in the owner's Drive folder `ots` ("pesquisa OTLand (2026-10-13)"). Outside code without a clear licence
is ideas only: we write our own. The big 12-month plan is in `docs/MOONSHOT.md`.

## Client
- Item search across inbox and stash in one field (`game_stash`).
- Backpack layout and window positions remembered per character.
- Streamer mode: hides private messages, the character name in the window title and private chat.
- Automatic screenshot on level up, death, legendary drop and boss kill.
- Click on the minimap to walk there (pathfinding).
- Backpack preview in the item tooltip.
- UI scale for 4K screens.
- Minimap preview of Town Portal and waystone destinations.
- Own quest log, linked to the Seasonal Journey and the Codex. (Partly done: Next Goals, ROADMAP #176, is the level path with a link to the Journey.)
- Full minimap generated from the OTBM and delivered by the updater.
- Background music per region with fades, set per area on the server. Own, CC0 or CC BY tracks only.

## Server
- Monsters that fight each other by faction, in invasions and open PvP.
- One queue for arena, battleground, raid and dungeons, with a party ready check.
- A tower of floors with a two-player cooperative challenge, built with our area generator.
- Character auctions between players on the website (owner decision: fraud risk; season characters blocked).

## Website and wiki
- Quest map in the wiki, generated from NPCs and scripts.

## Art
- A CC BY 4.0 community sprite pack (items, 24 outfits, effects): credit required, check each artist, palette pass.
- CC0 32x32 fish, ore and clothing sprites for Angling and Delving: find the licence file first.
- Commissioned dark art from forum artists, with a written transfer of rights.
- Two small free 10.98 maps (a dungeon, five small areas): ask the authors for written permission first.

## Future content (owner, 2026-11-19)

Status: todo. Nothing here is built yet. Ideas from the owner; the combo list below the first one was written out at
the owner's request ("desenvolva mais coisas do tipo").

### Gauntlet (party boss run)
- A boss run for a party of 4 or 5, level 1000 and up.
- 3 rounds. Rounds 1 and 2: two bosses at the same time. Round 3: three bosses at once, or one very hard boss.
- Built on what exists: boss copies, pocket boss arenas, `boss_mechanics_config.lua` telegraphs, the boss length model
  (`boss_length_model.py`) for the clock of each round, closed so testers never share a run with players.
- Open for the owner: rewards (Gauntlet tokens, a weekly chest), a short break between rounds or none, deaths
  allowed per run, a weekly boss rotation, a ladder by clear time.

### Status combos (reactions)
A target that carries one status and receives a second one triggers a reaction. Both statuses are consumed. Default
rules for every combo: monsters only at first (PvP later, at a reduced share); one reaction per target per few seconds;
the damage reads the caster's level and magic level (CLAUDE.md spell rule); every reaction has its own effect and
coloured number; a new model holds the reactions to a share of class damage, like `spell_mastery_model.py` does for masteries.
The game has no "chaos" damage type in the engine; a chaos reaction would be death or arcane damage with its own
colour, or a new type through an engine patch.

1. Poison + Burn = **Plague Burst**: the target explodes, necrotic (death) or chaos damage in a 3x3 area (owner's idea).
2. Burn + Frozen = **Thermal Shatter**: a big physical hit on the target, and shards slow monsters around it.
3. Shock + Frozen = **Superconduct**: the target and its neighbours lose part of their resistances for a few seconds.
4. Bleed + Burn = **Cauterize**: ends the bleed at once and deals all of its remaining ticks in one hit.
5. Poison + Shock = **Toxic Arc**: the poison chains to 3 nearby monsters with half its remaining ticks.
6. Bleed + Poison = **Hemotoxin**: the bleed ticks twice as fast and the target heals 50% less.
7. Curse/Hex + Mark = **Doom Seal**: after 3 s the target takes a share of all damage dealt to it during those 3 s again,
   as death damage (the player's "Dark Souls" moment).
8. Frozen + physical crit = **Shatter**: a frozen monster under a set health share breaks and dies; a boss takes a
   big hit instead of dying.
9. Burn + Burn from two different casters = **Wildfire**: the fire spreads to every monster in the area once.
10. Holy hit on a Cursed target = **Purge**: removes the curse and heals the party around for part of the damage.
11. Root + Poison = **Bog**: the rooted target leaves a poison pool on its tile for a few seconds.
12. Shock + Bleed = **Galvanic Bleed**: every bleed tick also deals a small energy hit to one neighbour.
13. Three different statuses at once = **Overload**: a chaos burst that grows with the number of statuses (3, 4, 5+), and
    the target is dazed for 1 s (boss: no daze, more damage).
14. Slow + Frozen = **Deep Freeze**: the target is stunned for 1 s (boss: immune, takes extra ice damage instead).
15. Fear + any damage over time = **Panic**: the feared monster runs and spreads its dots to the monsters it passes.

Hooks for the rest of the game:
- Passive tree keystones and spell masteries that change a reaction (bigger area, no consume, a second reaction).
- Uniques and cards built around one reaction ("your Plague Bursts leave a poison pool").
- Monsters and bosses that use reactions on players (a boss that burns, then poisons: dodge the second).
- Rift and Descent curses that make a reaction stronger or turn it against the party.
- A combo journal in the Codex: each reaction is found the first time a player triggers it.
- Class identity: each class can start at least two statuses so every class has a combo of its own.
