# Chaos spells (the base server, TFS 1.4.2 / protocol 10.98)

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
| 200 | Rime Bloom | `exevo frigo nova` | S, MS | 20 | 120 | 8s | Ice burst (7x7 circle) around you; hit enemies are slowed 40% for 4s. |
| 201 | Witchfire Bolt | `exori flam hex` | S, MS | 30 | 70 | 4s | Fire bolt at one target that also leaves it burning (4 ticks). |
| 202 | Forked Storm | `exori vis catena` | S, MS | 50 | 200 | 7s | Energy bolt that jumps to up to 3 more monsters within 3 sqm (70% damage per jump). |
| 203 | Crimson Covenant | `utamo mort sanguis` | S, MS | 90 | 50 | 30s | Sacrifice 15% max health: restore 1.5x that as mana and +15% magic level for 12s. |
| 204 | Falling Pyre | `exevo gran mas pyra` | S, MS | 150 | 700 | 20s | Marks the target position; 1.2s later a meteor hits a 5x5 area for heavy fire damage and ignites enemies. |
| 205 | Frozen Crypt | `exevo gran mas frigo tumba` | MS | 220 | 900 | 30s | Ice zone (5x5) on the target for 6 pulses over 5s; enemies inside are slowed 70%. |
| 206 | Doomtide | `exevo vis pyra cataclysmus` | MS | 300 | 1500 | 45s | Three waves (fire, energy, fire) over a 13x13 circle around you. |
| **druid** | | | | | | | |
| 207 | Blightswarm | `exevo pox vermis` | D, ED | 25 | 110 | 8s | Poison cloud (7x7) around you: earth damage plus a poison condition. |
| 208 | Purifying Wellspring | `exura mas fons` | D, ED | 40 | 160 | 6s | Heals you, party members and your summons within 3 sqm and cures poison/fire/energy/bleeding/curse/freeze/dazzle/drown. |
| 209 | Ironbark Hide | `utamo vita cortex` | D, ED | 60 | 140 | 25s | +20% max health and regeneration for 20s. |
| 210 | Briar Prison | `exevo vinculum spina` | D, ED | 70 | 240 | 14s | Thorns erupt around the target (3x3, 3 pulses) and root enemies (90% slow) for 5s. |
| 211 | Moonfang Pack | `utevo lupus spiritus` | D, ED | 120 | 450 | 30s | Summons 2 wolves (3 from level 200) for 40s; max 4 summons. |
| 212 | Verdant Sanctuary | `exura gran mas silva` | D, ED | 180 | 600 | 30s | Healing zone on your tile: 8 pulses (1/s) heal allies within 3 sqm. |
| 213 | Primordial Squall | `exevo gran mas tempestas` | ED | 250 | 1200 | 35s | Three waves (earth, ice, earth) over an 11x11 circle; the ice wave slows 50%. |
| **paladin** | | | | | | | |
| 214 | Dawnpiercer | `exori san ictus` | P, RP | 30 | 60 | 3s | Holy bolt at one target, the paladin filler; scales mainly with distance skill. |
| 215 | Skewering Line | `exori con transfixio` | P, RP | 60 | 150 | 8s | 7 sqm line of spears in your facing direction; scales with distance skill. |
| 216 | Blessed Earth | `exevo mas san sacratum` | P, RP | 100 | 350 | 24s | Consecrates your tile for 6s: holy damage to enemies within 2 sqm each second, allies are healed half as much. |
| 217 | Lightward | `utamo san aegis` | P, RP | 140 | 300 | 30s | Cleanses harmful conditions (incl. paralyze) and gives 8s of strong health/mana regeneration. |
| 218 | Final Verdict | `exori gran san iudex` | P, RP | 200 | 450 | 14s | Heavy holy strike (distance skill); +50% damage against targets under 25% health. |
| 219 | Hail of Dawn | `exevo gran mas san sagitta` | P, RP | 280 | 800 | 24s | 3 volleys of 4 holy arrows, every arrow strikes the target (distance skill). |
| **knight** | | | | | | | |
| 220 | Reaping Gyre | `exori gyro` | K, EK | 30 | 80 | 6s | Three spinning strikes (0/0.4/0.8s) against adjacent enemies; uses weapon attack and skill. |
| 221 | Earthbreaker | `exori terra fragor` | K, EK | 60 | 150 | 10s | Shockwave (5x5) with physical damage; staggers enemies (60% slow, 3s). |
| 222 | Red Frenzy | `utito tempo sanguis` | K, EK | 100 | 300 | 40s | +30% melee skill, -30% shield skill for 12s. |
| 223 | Iron Bellow | `exeta mas clamor` | K, EK | 120 | 200 | 20s | Taunts all monsters within 4 sqm and slows them 25% for 6s; Iron Will: you take 25% less damage and get +15% shielding for 8s. |
| 224 | Vaulting Cleave | `exori ico saltus` | K, EK | 170 | 250 | 12s | Jump next to the target and strike it with weapon attack and skill. |
| 225 | Colossus Fall | `exori gran mas ruina` | K, EK | 260 | 650 | 30s | Two crushing blows (0/0.6s) in a 7x7 circle; enemies slowed 70% for 4s. |
| **illusionist** | | | | | | | |
| 226 | Hall of Mirrors | `exevo spectrum` | I, AI | 40 | 250 | 30s | Up to 3 decoy clones in your outfit for 10s (needs the Clone monster). |
| 227 | Umbral Stride | `utani mort umbra` | I, AI | 70 | 120 | 8s | Teleport to the far side of the target and stab it for death damage. |
| 228 | Shattered Psyche | `exori mens fractura` | I, AI | 110 | 200 | 6s | Death bolt plus cursing damage-over-time and a 30% slow for 2.5s. |
| 229 | Wraithshroud | `utana phantasma` | I, AI | 150 | 350 | 35s | 8s invisibility plus speed boost. |
| 230 | Nightburst | `exevo gran mas umbra` | AI | 210 | 900 | 25s | After 0.9s shadows erupt in a 7x7 circle (death damage, 40% slow). |
| 231 | Tear in the Weave | `exevo vis rift` | AI | 280 | 1300 | 40s | Pulls monsters within 5 sqm next to you, then two death implosions (0.6s, 1.2s). |
| **shared** | | | | | | | |
| 232 | Flickerdash | `exani celer` | all | 35 | 80 | 6s | Dash up to 4 sqm in your facing direction, stops at obstacles; 2.5s speed boost. |
| 233 | Banner Call | `utamo mas vox` | all | 60 | 250 | 35s | You and party members within 5 sqm: +10% melee/distance/magic and speed for 12s. |
| 234 | Soulward | `utamo anima` | all | 80 | 150 | 40s | Mana shield for 15s with mana regeneration (stock Magic Shield has none). |
| 235 | Hunter's Instinct | `exani sensus` | all | 25 | 40 | 10s | Marks monsters within 12 sqm (max 15) and tells the nearest one's direction. |

Damage formulas follow the stock style: `level/5 + magicLevel*a + b` (min/max with different a, b); knight spells use the stock
skill*attack callback, paladin spells scale mainly with the distance skill (plus a little magic level).

## Names (all spells)

Every player spell has a Chaos name, the stock ones included: `spell_names.csv` (old name, new name, words, rune item) lists the stock spells and
runes; the Chaos spells are named in `chaos/spells_chaos.xml`. Words stay the same. On the server run once
`python3 -I server/tools/rename_spells.py <server>/data --sql rename_spells.sql` and apply the SQL to the game database: it renames the spells in
spells.xml, the rune items in items.xml (and every other item carrying an old rune name), monster attacks and loot that name them, the NPC spell
teachers and shop lists, and the spells players already learned. It is idempotent and lists any other place that still quotes an old name
(NPC keyword lists are left as they are). The client renames its own spell entries at runtime from the same csv (`ChaosSpellNames` in
`game_chaosspells/spelldata.lua`, generated by `client/tools/gen_spell_data.py`). Monster-only spells and house commands keep their names.

## Roles and balance

| Vocation | Role | Tools |
|---|---|---|
| Sorcerer | area damage | Rime Bloom, Forked Storm, Falling Pyre, Frozen Crypt, Doomtide |
| Paladin | ranged single-target damage | Dawnpiercer filler, Final Verdict, Hail of Dawn (all arrows on the target); Skewering Line and Blessed Earth for packs |
| Knight | tank | most health, Iron Bellow taunt + Iron Will (-25% damage taken, +15% shielding), modest damage |
| Druid | healer | Purifying Wellspring (party burst heal + cleanse), Verdant Sanctuary (party heal zone), stock Mass Healing / Heal Friend |
| Illusionist | not decided yet | burst/control kit (Shattered Psyche, Umbral Stride, Hall of Mirrors, Wraithshroud, Tear in the Weave); numbers sit between the others |

Measured on a test server (cast through the spell scripts against 5 stationary dummies; 3 casts per spell averaged), level 300 reference
characters: mages magic level 100 with a level 250 wand/rod; knight sword 110 / shielding 100 with a magic longsword; paladin distance 110 /
magic level 30 with a royal crossbow and infernal bolts. Rotation DPS = 60s, 2s attack group cooldown, always the strongest ready spell,
plus the weapon's auto attack (measured: knight 165, paladin 185, wands/rods ~60 per second; it hits one target). Summons (Moonfang Pack)
are not counted.

| Vocation | Spells, single target | Weapon | Total single target | Total 5 targets | Mana/min |
|---|---|---|---|---|---|
| Paladin | 503 | 185 | **688** | 864 | 7170 |
| Sorcerer | 381 | 59 | 440 | **1415** | 9410 |
| Illusionist | 324 | 63 | 387 | 733 | 8020 |
| Knight | 205 | 165 | 370 | 857 | 4090 |
| Druid | 158 | 63 | 221 | 853 | 4370 |

Weapons count twice for knights and paladins: the auto attack, and the spells (knight spells use the engine's skill x weapon attack callback;
paladin spells use distance skill x bow/crossbow + ammunition attack, `ChaosSpell.distanceAttack`). With a weak crossbow (attack 30 instead
of 77) the paladin's Final Verdict drops from ~1840 to ~860, Dawnpiercer from ~520 to ~310 and the auto attack from 185 to 111 per second.

Healing (formula averages, magic level 100, per target): Purifying Wellspring ~1800 every 6s to the whole party within 3 sqm, Verdant Sanctuary ~4800 over 8s
every 30s; for comparison stock Grand Mending ~1100 (self), Circle of Mending ~880.

### PvP (tested with two characters on the test server)

- Damage to players is halved by the engine (spell and weapon alike); measured per cast against a level 300 knight with no armour, e.g.
  Hail of Dawn ~1830, Final Verdict ~1080, Frozen Crypt ~990, Doomtide ~1000, Colossus Fall ~620, Dawnpiercer ~260.
- Spells that deal damage from the script (Final Verdict, Hail of Dawn, Umbral Stride, Forked Storm, Vaulting Cleave) check the same rules as the
  engine before hitting a player (`ChaosSpell.canAttack`): no damage in or out of protection zones / no-PvP zones, below the protection level,
  inside the party, on no-PvP worlds, or against a player in secure mode (this server's `Creature:onTargetCombat` rule). Verified: with the
  target in secure mode or in a protection zone they are cancelled with no damage; without, they hit.
- Iron Will reduces any damage the knight takes (players included) by 25%, after the engine's PvP halving.
- Loops that only pick monsters (Forked Storm jumps, Iron Bellow taunt/slow, Tear in the Weave pull, slows from area ticks) never touch players.

### Helper

The client's helper only offers spells from its own per-vocation id lists; `game_chaosspells` adds the Chaos spells to them at game start
(attack spells to the shooter, healing spells to the healing list, support spells to the support list). Tested: a druid's helper heals with
Purifying Wellspring at 80% health, and the shooter casts Rime Bloom / Blightswarm on cooldown without "You are exhausted" spam.

## Honest notes / limitations

- Tested on the base server (TFS 1.4 based, protocol 10.98) with the real client: every spell was cast through its script against dummies and
  against a second player, see "Roles and balance". Not tested: party rules (needs two clients in one party), very large crowds.
- spellid: 200-235, a block no stock spell (server or client) uses. Ids must stay below 256: the 10.98 cooldown packet
  (`ProtocolGame::sendSpellCooldown`) sends the id as one byte, so an id like 410 arrives as 154 and the client (action bar,
  helper) puts the cooldown on the wrong spell. A few stock spells of the base server (ids 258-268) already wrap that way.
  The stock file also has a duplicate spellid (106) not related to this work.
- Word prefixes: many words start with existing words (`exori ...` vs Berserk `exori`, `exura gran mas silva` vs `exura gran`, ...). TFS picks the longest match and none of the shorter spells takes parameters, so this
  should be fine, but it is untested. No chaos words start with a parameterised spell (exiva, exani hur, utevo res, exura sio, alana sio).
- Manually looped spells (chain lightning jumps, warcry, pulls, ticks) only affect monsters that are not player summons; direct area combats follow the engine's normal PvP rules
  (see PvP above). Party protection could not be tested (needs two clients in one party). Slows/pulls can be used on bosses (Tear in the Weave skips monsters with more than 20000 max health; others rely on monster immunities).
- Moonfang Pack tries "Spirit Wolf", "Winter Wolf", "Wolf" in that order (summoning needs one of them to exist). Hall of Mirrors needs the "Clone" monster
  (reference: `data/monster/lua/clones/clone.lua`); both spells cancel with a message otherwise. Wolves/clones are removed after 40s/10s via addEvent.
- Iron Bellow has no damage-reduction debuff on monsters (vanilla conditions cannot lower a monster's damage); it taunts and slows, and the knight's own
  Iron Will is applied by `data/scripts/chaos/spell_guard.lua` (an onHealthChange event that checks the condition sub id 71009). Crimson Covenant/Banner Call/Red Frenzy use
  `CONDITION_ATTRIBUTES` with distinct sub ids so they stack with each other and with stock buffs.
- No stock `playSound` calls are made, so the spells are silent unless you add them.
- Ticking zones (Blessed Earth, Grove, Frozen Crypt) store the position at cast time and stop when the caster dies or logs out.
- Knight spells need a wielded weapon (`needweapon=1`); Vaulting Cleave teleports through anything that is not a blocking tile, it does not path-check.

## Client side (not implemented)

The server only needs the files above. Spell list and action bar come from the client:
- OTClient: add entries for the 36 spells to the client's spell list data (in the stock OTClient `modules/gamelib/spells.lua`, `SpellInfo`/`SpellIcons` tables:
  name, words, spellid, icon, level, mana, group, vocations) and provide icons in the matching sprite/image folder, otherwise they show without icon. Exact files differ per client fork.
- Official Tibia 10.98 client: its spell list is built in and cannot be extended; the spells still work by typing the words or via hotkeys/text hotkeys.
Use the spellid column above as the id, and the words as the spell's words.

## Client side
The client side is done in `client/overlay/modules/game_chaosspells` (spell list, action bar, icons); regenerate its data with `python3 -I client/tools/gen_spell_data.py` after changing `spells_chaos.xml`. The icons (cells 201..236, drawn by `client/tools/gen_spell_icons.py`) live in the complete generated spell icon sheets in `client/overlay/data/images/game/spells/`; rebuild those with `client/tools/gen_all_spell_icons.py`. See `client/MANIFEST.md`.
