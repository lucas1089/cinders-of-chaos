# Chaos spells (Hellgrave Exodus, TFS 1.4.2 / protocol 10.98)

36 custom spells, dark-fantasy flavour: 7 sorcerer, 7 druid, 6 paladin, 6 knight, 6 illusionist and 4 shared utility spells.
**Status: written and smoke-tested against a hand-written Lua mock only. Nothing has been run on a real TFS server.**

## Layout

```
server/data/spells/chaos/
  spells_chaos.xml            the 36 <instant> lines (script="chaos/<line>/<spell>.lua")
  _common.lua                 shared helpers (global table ChaosSpell)
  _fx_fallback.lua            20-line stub: defines Fx()/FxMissile() only if data/lib/chaos_fx.lua did not
  sorcerer/ druid/ paladin/ knight/ illusionist/ shared/   one .lua per spell
server/tools/register_spells.py
```

## Install

```
python3 -I server/tools/register_spells.py [path/to/data]      # default: server/data next to the tool
python3 -I server/tools/register_spells.py path/to/data --dry-run
```

It (1) copies `data/spells/chaos/**/*.lua` to **`data/spells/scripts/chaos/**`** (required: the XML `script=` paths are relative to
`data/spells/scripts` and every spell does `dofile('data/spells/scripts/chaos/_common.lua')`), and (2) inserts the XML between
`<!-- BEGIN chaos spells -->` / `<!-- END chaos spells -->` markers before `</spells>` of `data/spells/spells.xml`.
Re-running replaces that block (idempotent). It exits with an error and changes nothing if a chaos spellid, words or name is already
used by another spell. Copy to a real server: run it with the server's data folder as argument (the `spells/chaos` source folder must exist there too),
or copy `spells/chaos` to `data/spells/scripts/chaos` and paste `spells_chaos.xml` by hand. Restart the server (or `/reload spells`).

## Effects

Spells call `Fx("fire_nova", CONST_ME_FIREAREA)` / `FxMissile("fire_bolt", CONST_ANI_FIRE)`. When `data/lib/chaos_fx.lua` (other task) defines
them, custom ids are used; otherwise `_fx_fallback.lua` returns the standard fallback shown in the call. Effect names used: fire_nova,
frost_burst, chain_lightning, blood_rune, shadow_smoke, poison_cloud, holy_smite, arcane_circle, summon_portal, aura_ring, heal_sparkle,
ground_slam; missiles fire_bolt, ice_shard, arcane_orb, shadow_bolt, holy_arrow, blood_spear, lightning_orb, poison_dart.
`chaos_fx.lua` must be loaded before spells (data/lib is, via lib.lua; add a `dofile` line there).

## Spells

Vocations: S Sorcerer, MS Master Sorcerer, D Druid, ED Elder Druid, P Paladin, RP Royal Paladin, K Knight, EK Elite Knight, I Illusionist, AI Arch Illusionist.
All have `groupcooldown=2000`, `needlearn=0` (everyone of the vocation and level can cast, no scroll/NPC teaching), `premium=1` from level 60 up.

| id | Name | Words | Vocations | Lvl | Mana | Cooldown | What it does |
|---|---|---|---|---|---|---|---|
| **sorcerer** | | | | | | | |
| 410 | Frost Nova | `exevo frigo nova` | S, MS | 20 | 120 | 8s | Ice burst (7x7 circle) around you; hit enemies are slowed 40% for 4s. |
| 411 | Hexfire Bolt | `exori flam hex` | S, MS | 30 | 70 | 4s | Fire bolt at one target that also leaves it burning (4 ticks). |
| 412 | Chain Lightning | `exori vis catena` | S, MS | 50 | 200 | 7s | Energy bolt that jumps to up to 3 more monsters within 3 sqm (70% damage per jump). |
| 413 | Blood Pact | `utamo mort sanguis` | S, MS | 90 | 50 | 30s | Sacrifice 15% max health: restore 1.5x that as mana and +15% magic level for 12s. |
| 414 | Meteor Strike | `exevo gran mas pyra` | S, MS | 150 | 700 | 20s | Marks the target position; 1.2s later a meteor hits a 5x5 area for heavy fire damage and ignites enemies. |
| 415 | Glacial Tomb | `exevo gran mas frigo tumba` | MS | 220 | 900 | 30s | Ice zone (5x5) on the target for 6 pulses over 5s; enemies inside are slowed 70%. |
| 416 | Cataclysm | `exevo vis pyra cataclysmus` | MS | 300 | 1500 | 45s | Three waves (fire, energy, fire) over a 13x13 circle around you. |
| **druid** | | | | | | | |
| 417 | Venom Swarm | `exevo pox vermis` | D, ED | 25 | 110 | 8s | Poison cloud (7x7) around you: earth damage plus a poison condition. |
| 418 | Cleansing Spring | `exura mas fons` | D, ED | 40 | 160 | 6s | Heals you, party members and your summons within 3 sqm and cures poison/fire/energy/bleeding/curse/freeze/dazzle/drown. |
| 419 | Barkskin | `utamo vita cortex` | D, ED | 60 | 140 | 25s | +20% max health and regeneration for 20s. |
| 420 | Thorn Cage | `exevo vinculum spina` | D, ED | 70 | 240 | 14s | Thorns erupt around the target (3x3, 3 pulses) and root enemies (90% slow) for 5s. |
| 421 | Spirit Wolves | `utevo lupus spiritus` | D, ED | 120 | 450 | 30s | Summons 2 wolves (3 from level 200) for 40s; max 4 summons. |
| 422 | Rejuvenating Grove | `exura gran mas silva` | D, ED | 180 | 600 | 40s | Healing zone on your tile: 8 pulses (1/s) heal allies within 3 sqm. |
| 423 | Ancient Tempest | `exevo gran mas tempestas` | ED | 250 | 1200 | 35s | Three waves (earth, ice, earth) over an 11x11 circle; the ice wave slows 50%. |
| **paladin** | | | | | | | |
| 424 | Holy Smite | `exori san ictus` | P, RP | 30 | 60 | 3s | Holy bolt at one target; scales with level, magic level and distance skill. |
| 425 | Piercing Volley | `exori con transfixio` | P, RP | 60 | 150 | 8s | 7 sqm line of spears in your facing direction; scales with distance skill. |
| 426 | Consecration | `exevo mas san sacratum` | P, RP | 100 | 350 | 24s | Consecrates your tile for 6s: holy damage to enemies within 2 sqm each second, allies are healed half as much. |
| 427 | Divine Ward | `utamo san aegis` | P, RP | 140 | 300 | 30s | Cleanses harmful conditions (incl. paralyze) and gives 8s of strong health/mana regeneration. |
| 428 | Judgement | `exori gran san iudex` | P, RP | 200 | 450 | 14s | Heavy holy strike; +50% damage against targets under 25% health. |
| 429 | Sanctified Barrage | `exevo gran mas san sagitta` | P, RP | 280 | 1000 | 30s | 3 volleys of 5 holy arrows raining within 2 sqm of the target. |
| **knight** | | | | | | | |
| 430 | Whirlwind | `exori gyro` | K, EK | 30 | 80 | 6s | Three spinning strikes (0/0.4/0.8s) against adjacent enemies; uses weapon attack and skill. |
| 431 | Ground Slam | `exori terra fragor` | K, EK | 60 | 150 | 10s | Shockwave (5x5) with physical damage; staggers enemies (60% slow, 3s). |
| 432 | Crimson Fury | `utito tempo sanguis` | K, EK | 100 | 300 | 40s | +30% melee skill, -30% shield skill for 12s. |
| 433 | Warcry | `exeta mas clamor` | K, EK | 120 | 200 | 20s | Taunts all monsters within 4 sqm and slows them 25% for 6s. |
| 434 | Leaping Strike | `exori ico saltus` | K, EK | 170 | 250 | 12s | Jump next to the target and strike it with weapon attack and skill. |
| 435 | Titan's Wrath | `exori gran mas ruina` | K, EK | 260 | 650 | 30s | Two crushing blows (0/0.6s) in a 7x7 circle; enemies slowed 70% for 4s. |
| **illusionist** | | | | | | | |
| 436 | Mirror Image | `exevo spectrum` | I, AI | 40 | 250 | 30s | Up to 3 decoy clones in your outfit for 10s (needs the Clone monster). |
| 437 | Shadow Step | `utani mort umbra` | I, AI | 70 | 120 | 8s | Teleport to the far side of the target and stab it for death damage. |
| 438 | Mind Fracture | `exori mens fractura` | I, AI | 110 | 200 | 6s | Death bolt plus cursing damage-over-time and a 30% slow for 2.5s. |
| 439 | Phantom Veil | `utana phantasma` | I, AI | 150 | 350 | 35s | 8s invisibility plus speed boost. |
| 440 | Umbral Eruption | `exevo gran mas umbra` | AI | 210 | 900 | 25s | After 0.9s shadows erupt in a 7x7 circle (death damage, 40% slow). |
| 441 | Reality Rift | `exevo vis rift` | AI | 280 | 1300 | 40s | Pulls monsters within 5 sqm next to you, then two death implosions (0.6s, 1.2s). |
| **shared** | | | | | | | |
| 442 | Blink Dash | `exani celer` | all | 35 | 80 | 6s | Dash up to 4 sqm in your facing direction, stops at obstacles; 2.5s speed boost. |
| 443 | Rallying Cry | `utamo mas vox` | all | 60 | 250 | 35s | You and party members within 5 sqm: +10% melee/distance/magic and speed for 12s. |
| 444 | Soul Aegis | `utamo anima` | all | 80 | 150 | 40s | Mana shield for 15s with mana regeneration (stock Magic Shield has none). |
| 445 | Sense Prey | `exani sensus` | all | 25 | 40 | 10s | Marks monsters within 12 sqm (max 15) and tells the nearest one's direction. |

Damage formulas follow the stock style: `level/5 + magicLevel*a + b` (min/max with different a, b); knight spells use the stock
skill*attack callback, paladin spells add the distance skill. Rough power at level 300 / magic level 90: single-target nukes ~400-750, big area spells ~800-1100 per hit.
These numbers are untested guesses and need balancing in play.

## Honest notes / limitations

- **Not run on a real server.** Syntax checked with `luac5.3 -p`; every script was cast once (with and without target, with and without a fake `chaos_fx.lua`)
  against a mock of Combat/Condition/Creature/Position, which only proves the code paths and argument shapes I assumed. API details (e.g. `doAreaCombat`,
  `Game.getSpectators`, `Creature:setMaster`, `doChallengeCreature`) were taken from the reference server's scripts and TFS 1.4 knowledge, not from engine source.
- spellid: ids 410-445 are above 397 (highest in the stock list). Stock spells.xml already uses ids >255; if the engine stores ids in 8 bits, ids would wrap
  (that would already affect stock ones). Also the stock file has a duplicate spellid (106) not related to this work.
- Word prefixes: many words start with existing words (`exori ...` vs Berserk `exori`, `exura gran mas silva` vs `exura gran`, ...). TFS picks the longest match and none of the shorter spells takes parameters, so this
  should be fine, but it is untested. No chaos words start with a parameterised spell (exiva, exani hur, utevo res, exura sio, alana sio).
- Manually looped spells (chain lightning jumps, warcry, pulls, ticks) only affect monsters that are not player summons; direct area combats follow the engine's normal PvP rules.
  PvP behaviour of the whole set is untested, and slows/pulls can be used on bosses (Reality Rift skips monsters with more than 20000 max health; others rely on monster immunities).
- Spirit Wolves tries "Spirit Wolf", "Winter Wolf", "Wolf" in that order (summoning needs one of them to exist). Mirror Image needs the "Clone" monster
  (reference: `data/monster/lua/clones/clone.lua`); both spells cancel with a message otherwise. Wolves/clones are removed after 40s/10s via addEvent.
- Warcry has no damage-reduction debuff (vanilla conditions cannot lower a monster's damage); it taunts and slows. Blood Pact/Rallying Cry/Crimson Fury use
  `CONDITION_ATTRIBUTES` with distinct sub ids so they stack with each other and with stock buffs.
- "Crimson Fury" is deliberately not called Blood Rage (that name exists in stock). No stock `playSound` calls are made, so the spells are silent unless you add them.
- Ticking zones (Consecration, Grove, Glacial Tomb) store the position at cast time and stop when the caster dies or logs out.
- Knight spells need a wielded weapon (`needweapon=1`); Leaping Strike teleports through anything that is not a blocking tile, it does not path-check.

## Client side (not implemented)

The server only needs the files above. Spell list and action bar come from the client:
- OTClient: add entries for the 36 spells to the client's spell list data (in the stock OTClient `modules/gamelib/spells.lua`, `SpellInfo`/`SpellIcons` tables:
  name, words, spellid, icon, level, mana, group, vocations) and provide icons in the matching sprite/image folder, otherwise they show without icon. Exact files differ per client fork.
- Official Tibia 10.98 client: its spell list is built in and cannot be extended; the spells still work by typing the words or via hotkeys/text hotkeys.
Use the spellid column above as the id, and the words as the spell's words.
