# Chaos spells (the base server, TFS 1.4.2 / protocol 10.98)

45 custom spells, dark-fantasy flavour: 7 sorcerer, 7 druid, 6 paladin, 6 knight, 6 illusionist, 4 shared utility spells and 9 for the
Thief line (Thief, Ninja, Samurai; see "Thief line" below).
**Status: written and smoke-tested against a hand-written Lua mock only. Nothing has been run on a real TFS server.**

## Layout

```
server/data/spells/chaos/
  spells_chaos.xml            the 36 <instant> lines (script="chaos/<line>/<spell>.lua")
  _common.lua                 shared helpers (global table ChaosSpell)
  _fx_fallback.lua            20-line stub: defines Fx()/FxMissile() only if data/lib/chaos_fx.lua did not
  sorcerer/ druid/ paladin/ knight/ illusionist/ shared/   one .lua per spell
  thief/ ninja/ samurai/                                  the Thief line (classes, docs/CLASSES.md)
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
| 200 | Rime Bloom | `drai hyr rhim` | S, MS | 20 | 120 | 8s | Ice burst (7x7 circle) around you; hit enemies are slowed 40% for 4s. |
| 201 | Witchfire Bolt | `kah pyr vesh` | S, MS | 30 | 70 | 4s | Fire bolt at one target that also leaves it burning (4 ticks). |
| 202 | Forked Storm | `kah zhul zarn` | S, MS | 50 | 200 | 7s | Energy bolt that jumps to up to 3 more monsters within 3 sqm (70% damage per jump). |
| 203 | Crimson Covenant | `tor nyx cruor` | S, MS | 90 | 50 | 30s | Sacrifice 15% max health: restore 1.5x that as mana and +15% magic level for 12s. |
| 204 | Falling Pyre | `drai gal vas infr` | S, MS | 150 | 700 | 20s | Marks the target position; 1.2s later a meteor hits a 5x5 area for heavy fire damage and ignites enemies. |
| 205 | Frozen Crypt | `drai gal vas hyr krypt` | MS | 220 | 900 | 30s | Ice zone (5x5) on the target for 6 pulses over 5s; enemies inside are slowed 70%. |
| 206 | Doomtide | `drai zhul infr doma` | MS | 300 | 1500 | 45s | Three waves (fire, energy, fire) over a 13x13 circle around you. |
| **druid** | | | | | | | |
| 207 | Blightswarm | `drai vex kriv` | D, ED | 25 | 110 | 8s | Poison cloud (7x7) around you: earth damage plus a poison condition. |
| 208 | Purifying Wellspring | `saen vas aquen` | D, ED | 40 | 160 | 6s | Heals you, party members and your summons within 3 sqm and cures poison/fire/energy/bleeding/curse/freeze/dazzle/drown. |
| 209 | Ironbark Hide | `tor ael skar` | D, ED | 60 | 140 | 25s | +20% max health and regeneration for 20s. |
| 210 | Briar Prison | `drai thral brin` | D, ED | 70 | 240 | 14s | Thorns erupt around the target (3x3, 3 pulses) and root enemies (90% slow) for 5s. |
| 211 | Moonfang Pack | `vael luth wyrd` | D, ED | 120 | 450 | 30s | Summons 2 wolves (3 from level 200) for 40s; max 4 summons. |
| 212 | Verdant Sanctuary | `saen gal vas vert` | D, ED | 180 | 600 | 30s | Healing zone on your tile: 8 pulses (1/s) heal allies within 3 sqm. |
| 213 | Primordial Squall | `drai gal vas stoma` | ED | 250 | 1200 | 35s | Three waves (earth, ice, earth) over an 11x11 circle; the ice wave slows 50%. |
| **paladin** | | | | | | | |
| 214 | Dawnpiercer | `kah sol aurr` | P, RP | 30 | 60 | 3s | Holy bolt at one target, the paladin filler; scales mainly with distance skill. |
| 215 | Skewering Line | `kah sag lanc` | P, RP | 60 | 150 | 8s | 7 sqm line of spears in your facing direction; scales with distance skill. |
| 216 | Blessed Earth | `drai vas sol hal` | P, RP | 100 | 350 | 24s | Consecrates your tile for 6s: holy damage to enemies within 2 sqm each second, allies are healed half as much. |
| 217 | Lightward | `tor sol ghar` | P, RP | 140 | 300 | 30s | Cleanses harmful conditions (incl. paralyze) and gives 8s of strong health/mana regeneration. |
| 218 | Final Verdict | `kah gal sol judh` | P, RP | 200 | 450 | 14s | Heavy holy strike (distance skill); +50% damage against targets under 25% health. |
| 219 | Hail of Dawn | `drai gal vas sol volv` | P, RP | 280 | 800 | 24s | 3 volleys of 4 holy arrows, every arrow strikes the target (distance skill). |
| **knight** | | | | | | | |
| 220 | Reaping Gyre | `kah spir` | K, EK | 30 | 80 | 6s | Three spinning strikes (0/0.4/0.8s) against adjacent enemies; uses weapon attack and skill. |
| 221 | Earthbreaker | `kah grund krak` | K, EK | 60 | 150 | 10s | Shockwave (5x5) with physical damage; staggers enemies (60% slow, 3s). |
| 222 | Red Frenzy | `vyr ira cruor` | K, EK | 100 | 300 | 40s | +30% melee skill, -30% shield skill for 12s. |
| 223 | Iron Bellow | `vok vas rhov` | K, EK | 120 | 200 | 20s | Taunts all monsters within 4 sqm and slows them 25% for 6s; Iron Will: you take 25% less damage and get +15% shielding for 8s. |
| 224 | Vaulting Cleave | `kah brak skai` | K, EK | 170 | 250 | 12s | Jump next to the target and strike it with weapon attack and skill. |
| 225 | Colossus Fall | `kah gal vas tyr` | K, EK | 260 | 650 | 30s | Two crushing blows (0/0.6s) in a 7x7 circle; enemies slowed 70% for 4s. |
| **illusionist** | | | | | | | |
| 226 | Hall of Mirrors | `drai spek` | I, AI | 40 | 250 | 30s | Up to 3 decoy clones in your outfit for 10s (needs the Clone monster). |
| 227 | Umbral Stride | `ruan nyx umh` | I, AI | 70 | 120 | 8s | Teleport to the far side of the target and stab it for death damage. |
| 228 | Shattered Psyche | `kah mynd frak` | I, AI | 110 | 200 | 6s | Death bolt plus cursing damage-over-time and a 30% slow for 2.5s. |
| 229 | Wraithshroud | `fen wrai` | I, AI | 150 | 350 | 35s | 8s invisibility plus speed boost. |
| 230 | Nightburst | `drai gal vas umh` | AI | 210 | 900 | 25s | After 0.9s shadows erupt in a 7x7 circle (death damage, 40% slow). |
| 231 | Tear in the Weave | `drai zhul riv` | AI | 280 | 1300 | 40s | Pulls monsters within 5 sqm next to you, then two death implosions (0.6s, 1.2s). |
| **shared** | | | | | | | |
| 232 | Flickerdash | `ash flik` | all | 35 | 80 | 6s | Dash up to 4 sqm in your facing direction, stops at obstacles; 2.5s speed boost. |
| 233 | Banner Call | `tor vas vant` | all | 60 | 250 | 35s | You and party members within 5 sqm: +10% melee/distance/magic and speed for 12s. |
| 234 | Soulward | `tor anh` | all | 80 | 150 | 40s | Mana shield for 15s with mana regeneration (stock Magic Shield has none). |
| 235 | Hunter's Instinct | `ash senn` | all | 25 | 40 | 10s | Marks monsters within 12 sqm (max 15) and tells the nearest one's direction. |
| **thief** (T Thief, N Ninja, Sa Samurai) | | | | | | | |
| 236 | Shuriken Toss | `kah shur` | T, N, Sa | 20 | 50 | 3s | Throws a shuriken (range 5): ranged weapon strike, the better of sword and distance skill x the star in hand (or a default star). The Thief's filler. |
| 238 | Shadow Veil | `fen umh` | T, N, Sa | 40 | 120 | 20s | 4 s stealth: monsters drop you and cannot pick you; dealing damage or taking a hit ends it; the first weapon hit out of it crits (x2). |
| 239 | Poison Blades | `vyr vex thyss` | T, N, Sa | 60 | 150 | 30s | 20 s: weapon hits and weapon strikes poison the target, 60% of the hit as earth damage over 4 s. |
| 240 | Shadow Step | `ash umh` | N | 100 | 150 | 8s | Teleport behind the target (range 5) and stab it: melee weapon strike, the off-hand follows. |
| 241 | Smoke Bomb | `drai nebh` | N | 130 | 300 | 20s | Smoke 5x5 around you: monsters lose their target and cannot pick a player for 3 s, slowed 30% (bosses only drop the target once). |
| 242 | Shuriken Barrage | `drai vas shur` | N | 180 | 400 | 10s | A shuriken at the target and up to 4 more monsters within 3 sqm of it. |
| 243 | Counter Stance | `tor ryx` | Sa | 100 | 100 | 8s | For 2 s the next melee hit taken is parried (no damage) and answered with 1.5x the parried hit. |
| 244 | Iaijutsu | `kah gal kaen` | Sa | 120 | 350 | 10s | 0.8 s charge, then one heavy melee weapon strike on the target if it is still within 2 sqm. |
| 245 | Bushido Focus | `vyr mynd` | Sa | 150 | 200 | 30s | 30 s: +3% crit chance per second without taking damage (3 at once, max 10 stacks = 30%), crits do x1.5; a hit taken resets the stacks. |

Damage formulas follow the stock style: `level/5 + magicLevel*a + b` (min/max with different a, b); knight spells use the stock
skill*attack callback, paladin spells scale mainly with the distance skill (plus a little magic level).

## Names (all spells)

Every player spell has a Chaos name, the stock ones included: `spell_names.csv` (old name, new name, words, rune item) lists the stock spells and
runes; the Chaos spells are named in `chaos/spells_chaos.xml`. Their words change too (see Words below). On the server run once
`python3 -I server/tools/rename_spells.py <server>/data --sql rename_spells.sql` and apply the SQL to the game database: it renames the spells in
spells.xml, the rune items in items.xml (and every other item carrying an old rune name), monster attacks and loot that name them, the NPC spell
teachers and shop lists, and the spells players already learned. It is idempotent and lists any other place that still quotes an old name
(NPC keyword lists are left as they are). The client renames its own spell entries at runtime from the same csv (`ChaosSpellNames` in
`game_chaosspells/spelldata.lua`, generated by `client/tools/gen_spell_data.py`). Monster-only spells and house commands keep their names.

## Words (all spells)

Incantations use one Chaos spell language: every word part of the old words maps to one Chaos part (`spell_words.csv`,
with what each part means), so families stay recognisable: `kah` strikes one target, `drai` evokes an area, `saen` heals,
`puir` cures, `tor` wards, `ruan` hastens, `rhun`/`rhuv`/`rhus`... conjure runes; `gal` greater, `vas` mass, `zar` supreme,
`ti`/`tin` lesser; elements `pyr` fire, `hyr` ice, `zhul` energy, `gor` earth, `nyx` death, `sol` holy, `vex` poison,
`brak` physical, `sang` blood, `ael` life. For example `drai gal vas pyr` is the great fire area spell, `saen gal vas vert`
the druid's Verdant Sanctuary. `rename_spells.py` translates the stock spells' words on the server, `spells_chaos.xml` holds
the Chaos spells' words, and the client changes its own entries at runtime. Parameters work as before
(`saen kin "Name"`, `sekh "Name"`, `ash ul "up"`, `vael kal "creature"`).

## Roles and balance

| Vocation | Role | Tools |
|---|---|---|
| Sorcerer | area damage | Rime Bloom, Forked Storm, Falling Pyre, Frozen Crypt, Doomtide |
| Paladin | ranged single-target damage | Dawnpiercer filler, Final Verdict, Hail of Dawn (all arrows on the target); Skewering Line and Blessed Earth for packs |
| Knight | tank | most health, Iron Bellow taunt + Iron Will (-25% damage taken, +15% shielding), modest damage |
| Druid | healer | Purifying Wellspring (party burst heal + cleanse), Verdant Sanctuary (party heal zone), stock Mass Healing / Heal Friend |
| Illusionist | not decided yet | burst/control kit (Shattered Psyche, Umbral Stride, Hall of Mirrors, Wraithshroud, Tear in the Weave); numbers sit between the others |

Measured on a test server: every spell cast through its script against 5 stationary dummies, 2 casts per spell averaged, stats 20
(stat window maximum). Rotation DPS = 60s, 2s attack group cooldown, always the strongest ready spell, plus the weapon's auto attack
(measured over 30-90s; it hits one target, arrows also splash). Summons (Moonfang Pack) are not counted.

Level 300: 73 passive points; mages magic level 100 with a level 250 wand/rod; knight sword 110 / shielding 100 with a magic longsword;
paladin distance 110 / magic level 30 with a royal crossbow and infernal bolts.

| Vocation | Spells, single target | Weapon | Total single target | Total 5 targets | Mana/min |
|---|---|---|---|---|---|
| Paladin | 666 | 409 | **1074** | 1322 | 6320 |
| Illusionist | 731 | 124 | 855 | 1761 | 7820 |
| Sorcerer | 747 | 107 | 854 | **2815** | 9410 |
| Knight | 208 | 431 | 639 | 1157 | 4090 |
| Druid | 372 | 98 | 471 | 1963 | 4240 |

Level 1000: 248 passive points, the best level 1000 equipment of the server; mages magic level 140; knight sword 140 / shielding 130;
paladin distance 140 / magic level 40.

| Build | Spells, single target | Weapon | Total single target | Total 5 targets | Mana/min |
|---|---|---|---|---|---|
| Paladin, crossbow + bolts | 1404 | 1366 | **2770** | 3648 | 6320 |
| Sorcerer | 1758 | 372 | 2130 | **6427** | 9410 |
| Paladin, bow + arrows | 1231 | ~845 (+ splash) | ~2080 | ~4520 | 6320 |
| Knight, two-handed | 674 | 1283 | 1957 | 3664 | 3940 |
| Illusionist | 1364 | 400 | 1764 | 3257 | 8020 |
| Knight, one-handed + shield | 660 | 1090 | 1750 | 3166 | 4100 |
| Druid | 859 | 383 | 1242 | 4687 | 4240 |

Level 1000 tuning (from the first level 1000 run): knight spells x0.7, sorcerer spells x1.2, druid attack spells x0.85, illusionist
spells x1.4 (the `scale` argument of `ChaosSpell.mlValues` or a factor on the formula), and the passive tree's dexterity cap 40 -> 20
(weapon hits x1.25 instead of x1.67; at 40 knights out-damaged every other class). The bow's single-target weapon number is estimated:
its arrows splash half of each hit on the 4 other dummies, and the test cannot separate the two.

Weapons count twice for knights and paladins: the auto attack, and the spells (knight spells use the engine's skill x weapon attack callback;
paladin spells use distance skill x bow/crossbow + ammunition attack, `ChaosSpell.distanceAttack`). With a weak crossbow (attack 30 instead
of 77) the paladin's Final Verdict drops from ~1840 to ~860, Dawnpiercer from ~520 to ~310 and the auto attack from 185 to 111 per second.

Healing (formula averages, magic level 100, per target): Purifying Wellspring ~1800 every 6s to the whole party within 3 sqm, Verdant Sanctuary ~4800 over 8s
every 30s; for comparison stock Grand Mending ~1100 (self), Circle of Mending ~880.

### Thief line (Thief, Ninja, Samurai)

Ascension at level 100 (`!ascend ninja|samurai`, data/scripts/chaos/ascension.lua). The kit's mechanics are scripted in
`data/scripts/chaos/thief_combat.lua` (rules in `classes.lua`, numbers in `Chaos.classes`, chaos_constants.lua):

- **Evasion** (passive): 8% Thief, 12% Ninja, 5% Samurai chance to dodge a melee or ranged hit (monster attacks and player weapons),
  shown with `ChaosCombatFx.dodge`. Measured: 4 dodges in a 20 s fight against three Behemoths.
- **Weapon strikes**: the damaging spells deal their physical damage with a weapon origin (melee or ranged), so the weapon rules apply to
  them too: the stealth crit, Poison Blades, the Bushido crit, and the Ninja's off-hand strike after Shadow Step.
- **Dual wield** (Ninja): a one-handed sword in each hand (the shield hand takes it only with `server/src-patches/0002`); every melee hit of
  the main hand is followed 0.15 s later by an off-hand strike for 50% of it x (off-hand attack / main-hand attack, clamped 0.5-1.25).
- **Level factor**: the line's spell strikes are x(1 + (level - 300) / 700), at most 2.2 (x2 at level 1000). It stands in for the passive
  tree the line does not have yet (the numbers of the other classes carry 73 / 248 tree points); re-tune it with the tree.

Measured on the dummies like the tables above, but as a timed rotation (`ztest/thiefrot.lua`: 90 s, auto attack on the main dummy,
spells on cooldown with the 2 s group cooldowns, buffs kept up) and **without any passive tree points**; auto attack alone over 60 s.
Level 300: sword 110, embersage sword (atk 55, 1800 ms) and for the Ninja a second one in the off hand. Level 1000: sword 140, the
level 1000 paladin armour set (the line wears what the Paladin wears) and the Dawnforged Blade (atk 65), two for the Ninja.

| Level | Class | Auto attack | Total single target | Total 5 targets | Mana/min | Max health |
|---|---|---|---|---|---|---|
| 300 | Ninja | 609 | **1050** | 1385 | 4600 | 4426 |
| 300 | Samurai | 309 | 968 | 968 | 3800 | 4777 |
| 300 | Thief | 321 | 728 | 728 | 1470 | 4426 |
| 1000 | Ninja | 1010 | **2837** | 3710 | 4600 | 14506 |
| 1000 | Samurai | 491 | 2376 | 2376 | 3800 | 15697 |
| 1000 | Thief | 588 | 1802 | 1802 | 1470 | 14506 |

Against the tables above: the Ninja is at the paladin's crossbow level (1074 / 2770), the Samurai a little below in sustained damage with
more health (Iaijutsu averages ~1700 at level 300 and ~5300 at level 1000 before crits, formula values; Counter Stance answers are not in these numbers: measured
7 parries of 8 stances against two Behemoths), and the Thief in the middle (between the knight and the illusionist at level 300).
The auto attack alone is noisy (a 30 s sample varies by ~15%).

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
- spellid: 200-245 without 237 (the base server's Duelist's Oath has 237), a block no other stock spell (server or client) uses. Ids must stay below 256: the 10.98 cooldown packet
  (`ProtocolGame::sendSpellCooldown`) sends the id as one byte, so an id like 410 arrives as 154 and the client (action bar,
  helper) puts the cooldown on the wrong spell. A few stock spells of the base server (ids 258-268) already wrap that way.
  The stock file also has a duplicate spellid (106) not related to this work.
- Word prefixes: many words start with existing words (`kah ...` vs Reaver's Spin `kah`, `saen gal vas vert` vs `saen gal`, ...). TFS picks the longest match and none of the shorter spells takes parameters, so this
  should be fine. No chaos words start with the words of a parameterised spell (sekh, ash ul, vael kal, saen kin, alana sio).
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
The client side is done in `client/overlay/modules/game_chaosspells` (spell list, action bar, icons); regenerate its data with `python3 -I client/tools/gen_spell_data.py` after changing `spells_chaos.xml`. The icons (cells 201..245, drawn by `client/tools/gen_spell_icons.py`) live in the complete generated spell icon sheets in `client/overlay/data/images/game/spells/`; rebuild those with `client/tools/gen_all_spell_icons.py`. See `client/MANIFEST.md`.
