# Chaos spells (the base server, TFS 1.4.2 / protocol 10.98)

77 custom spells, dark-fantasy flavour: 7 sorcerer, 7 druid, 6 paladin, 6 knight, 6 illusionist, 4 shared utility spells, 9 for the
Thief line (Thief, Ninja, Samurai; see "Thief line" below), 4 for the Berserker and the Beastmaster (see "Classes" below), 9 for the
Necromancer line (Necromancer, Lich, Bone Lord; see "Necromancer line"), 10 for the Monk line (Monk, Shadowfist, Iron Sage; see
"Monk line") and 9 for the Templar line (Templar, Inquisitor, Sentinel; see "Templar line"). The last three lines are built but not
tested in game yet (phase A); their numbers are formula estimates until measured. Since the
class rework (docs/CLASSES.md) the old kits belong to the new classes; the folder names keep the old vocation names.
**Status: written and smoke-tested against a hand-written Lua mock only. Nothing has been run on a real TFS server.**

## Layout

```
server/data/spells/chaos/
  spells_chaos.xml            the 77 <instant> lines (script="chaos/<line>/<spell>.lua")
  _common.lua                 shared helpers (global table ChaosSpell)
  _fx_fallback.lua            20-line stub: defines Fx()/FxMissile() only if data/lib/chaos_fx.lua did not
  sorcerer/ druid/ paladin/ knight/ illusionist/ shared/   one .lua per spell
  thief/ ninja/ samurai/                                  the Thief line (classes, docs/CLASSES.md)
  necromancer/ lich/ bonelord/                            the Necromancer line (_necro.lua: its helpers)
  monk/ shadowfist/ ironsage/                             the Monk line (_monk.lua: its helpers)
  templar/ inquisitor/ sentinel/                          the Templar line (_templar.lua: its helpers)
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

Vocations (the classes, docs/CLASSES.md): W Warrior, J Juggernaut, B Berserker, R Ranger, D Deadeye, BM Beastmaster, M Mystic,
E Elementalist, I Illusionist (the old kits: sorcerer -> M, E; druid -> I, the first three also M; paladin -> R, D, BM; knight -> W, J,
B; illusionist -> M, I). The table below still names the old vocations in the section rows; the "Vocations" column is current.
All have `groupcooldown=2000`, `needlearn=0` (everyone of the vocation and level can cast, no scroll/NPC teaching), `premium=1` from level 60 up.

| id | Name | Words | Vocations | Lvl | Mana | Cooldown | What it does |
|---|---|---|---|---|---|---|---|
| **sorcerer** | | | | | | | |
| 200 | Rime Bloom | `drai hyr rhim` | M, E | 20 | 120 | 8s | Ice burst (7x7 circle) around you; hit enemies are slowed 40% for 4s. |
| 201 | Witchfire Bolt | `kah pyr vesh` | M, E | 30 | 70 | 4s | Fire bolt at one target that also leaves it burning (4 ticks). |
| 202 | Forked Storm | `kah zhul zarn` | M, E | 50 | 200 | 7s | Energy bolt that jumps to up to 3 more monsters within 3 sqm (70% damage per jump). |
| 203 | Crimson Covenant | `tor nyx cruor` | M, E | 90 | 50 | 30s | Sacrifice 15% max health: restore 1.5x that as mana and +15% magic level for 12s. |
| 204 | Falling Pyre | `drai gal vas infr` | M, E | 150 | 700 | 20s | Marks the target position; 1.2s later a meteor hits a 5x5 area for heavy fire damage and ignites enemies. |
| 205 | Frozen Crypt | `drai gal vas hyr krypt` | E | 220 | 900 | 30s | Ice zone (5x5) on the target for 6 pulses over 5s; enemies inside are slowed 70%. |
| 206 | Doomtide | `drai zhul infr doma` | E | 300 | 1500 | 45s | Three waves (fire, energy, fire) over a 13x13 circle around you. |
| **druid** | | | | | | | |
| 207 | Blightswarm | `drai vex kriv` | M, I | 25 | 110 | 8s | Poison cloud (7x7) around you: earth damage plus a poison condition. |
| 208 | Purifying Wellspring | `saen vas aquen` | M, I | 40 | 160 | 6s | Heals you, party members and your summons within 3 sqm and cures poison/fire/energy/bleeding/curse/freeze/dazzle/drown. |
| 209 | Ironbark Hide | `tor ael skar` | M, I | 60 | 140 | 25s | +20% max health and regeneration for 20s. |
| 210 | Briar Prison | `drai thral brin` | I | 70 | 240 | 14s | Thorns erupt around the target (3x3, 3 pulses) and root enemies (90% slow) for 5s. |
| 211 | Moonfang Pack | `vael luth wyrd` | I | 120 | 450 | 30s | Summons 2 wolves (3 from level 200) for 40s; max 4 summons. |
| 212 | Verdant Sanctuary | `saen gal vas vert` | I | 180 | 600 | 30s | Healing zone on your tile: 8 pulses (1/s) heal allies within 3 sqm. |
| 213 | Primordial Squall | `drai gal vas stoma` | I | 250 | 1200 | 35s | Three waves (earth, ice, earth) over an 11x11 circle; the ice wave slows 50%. |
| **paladin** | | | | | | | |
| 214 | Dawnpiercer | `kah sol aurr` | R, D, BM | 30 | 60 | 3s | Holy bolt at one target, the paladin filler; scales mainly with distance skill. |
| 215 | Skewering Line | `kah sag lanc` | R, D, BM | 60 | 150 | 8s | 7 sqm line of spears in your facing direction; scales with distance skill. |
| 216 | Blessed Earth | `drai vas sol hal` | R, D, BM | 100 | 350 | 24s | Consecrates your tile for 6s: holy damage to enemies within 2 sqm each second, allies are healed half as much. |
| 217 | Lightward | `tor sol ghar` | R, D, BM | 140 | 300 | 30s | Cleanses harmful conditions (incl. paralyze) and gives 8s of strong health/mana regeneration. |
| 218 | Final Verdict | `kah gal sol judh` | D | 200 | 450 | 14s | Heavy holy strike (distance skill); +50% damage against targets under 25% health. |
| 219 | Hail of Dawn | `drai gal vas sol volv` | R, D | 280 | 800 | 24s | 3 volleys of 4 holy arrows, every arrow strikes the target (distance skill). |
| **knight** | | | | | | | |
| 220 | Reaping Gyre | `kah spir` | W, J, B | 30 | 80 | 6s | Three spinning strikes (0/0.4/0.8s) against adjacent enemies; uses weapon attack and skill. |
| 221 | Earthbreaker | `kah grund krak` | W, J, B | 60 | 150 | 10s | Shockwave (5x5) with physical damage; staggers enemies (60% slow, 3s). |
| 222 | Red Frenzy | `vyr ira cruor` | W, J, B | 100 | 300 | 40s | +30% melee skill, -30% shield skill for 12s. |
| 223 | Iron Bellow | `vok vas rhov` | W, J | 120 | 200 | 20s | Taunts all monsters within 4 sqm and slows them 25% for 6s; Iron Will: you take 25% less damage and get +15% shielding for 8s. |
| 224 | Vaulting Cleave | `kah brak skai` | W, J, B | 170 | 250 | 12s | Jump next to the target and strike it with weapon attack and skill. |
| 225 | Colossus Fall | `kah gal vas tyr` | W, J, B | 260 | 650 | 30s | Two crushing blows (0/0.6s) in a 7x7 circle; enemies slowed 70% for 4s. |
| **illusionist** | | | | | | | |
| 226 | Hall of Mirrors | `drai spek` | M, I | 40 | 250 | 30s | Up to 3 decoy clones in your outfit for 10s (needs the Clone monster). |
| 227 | Umbral Stride | `ruan nyx umh` | M, I | 70 | 120 | 8s | Teleport to the far side of the target and stab it for death damage. |
| 228 | Shattered Psyche | `kah mynd frak` | M, I | 110 | 200 | 6s | Death bolt plus cursing damage-over-time and a 30% slow for 2.5s. |
| 229 | Wraithshroud | `fen wrai` | M, I | 150 | 350 | 35s | 8s invisibility plus speed boost. |
| 230 | Nightburst | `drai gal vas umh` | I | 210 | 900 | 25s | After 0.9s shadows erupt in a 7x7 circle (death damage, 40% slow). |
| 231 | Tear in the Weave | `drai zhul riv` | I | 280 | 1300 | 40s | Pulls monsters within 5 sqm next to you, then two death implosions (0.6s, 1.2s). |
| 96 | Mirror Mend | `saen spek ["Name"]` | I | 60 | 180 | 2s | Heals the most hurt party member within 7 sqm (or the named one): level x 0.3 + ml x 11-17 + 40-80; a mirror heals the next most hurt (you included) for 25% of it. Healer pass, see "Healing". |
| 97 | Lucid Reverie | `reth vas spek` | I | 120 | 300 | 20s | You and every party member within 7 sqm: 5 heals, one every 2 s (level x 0.16 + ml x 0.9-1.3 + 10-20 each); follows them up to 10 sqm. Healer pass. |
| **shared** | | | | | | | |
| 232 | Flickerdash | `ash flik` | every class | 35 | 80 | 6s | Dash up to 4 sqm in your facing direction, stops at obstacles; 2.5s speed boost. |
| 233 | Banner Call | `tor vas vant` | every class | 60 | 250 | 35s | You and party members within 5 sqm: +10% melee/distance/magic and speed for 12s. |
| 234 | Soulward | `tor anh` | every class | 80 | 150 | 40s | Mana shield for 15s with mana regeneration (stock Magic Shield has none). |
| 235 | Hunter's Instinct | `ash senn` | every class | 25 | 40 | 10s | Marks monsters within 12 sqm (max 15) and tells the nearest one's direction. |
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
| **berserker** (B) / **beastmaster** (BM) | | | | | | | |
| 246 | Skyfall Cleave | `drai skai hrun` | B | 100 | 300 | 10s | Leap next to the target (range 5) and slam a 3x3 square around it: (level/5 + skill x attack x 0.060..0.105 + 20..40) x 0.7 physical, 30% slow 2 s. Needs a weapon. |
| 247 | Bloodrage | `vyr sang khar` | B | 120 | 200 | 30s | Costs 10% of the current health; 12 s: Rage +10% and every melee weapon hit also strikes up to 4 other enemies next to you for 40% of it. |
| 248 | Wild Bond | `vael ferh` | BM | 100 | 300 | 10s | Calls the companion (a War Wolf; 2 from level 400): health 500 + 15 x level; companions already out come back to you and heal 50%. |
| 249 | Feral Command | `kah ferh` | BM | 110 | 200 | 8s | Every companion leaps to the target (range 7) and mauls it for 1.5 bites. |
| **necromancer** (N Necromancer, L Lich, BL Bone Lord; formula estimates, not measured) | | | | | | | |
| 180 | Raise Dead | `vael oss` | N, L, BL | 20 | 60 | 2s | Raises a minion from an empty corpse (never one with loot), else one from nothing for twice the mana; skeletons, the Lich's shade. |
| 181 | Bone Spear | `kah oss lanc` | N, L, BL | 15 | 40 | 2s | The filler: a bone spear at the target (range 5) that pierces to the creature behind. |
| 182 | Withering Curse | `kah nyx maled` | N, L, BL | 40 | 120 | 8s | The target takes +15% damage from everyone and rots (Lich: +25%, spreads to 2 more; monsters only, players just rot). |
| 183 | Soul Rot | `kah nyx putr` | L | 100 | 220 | 6s | 6 s death damage over time that jumps to a new host when the target dies. |
| 184 | Life Siphon | `kah sang nyx` | L | 130 | 260 | 8s | Death damage to the target; heals the Lich for 50% of it. |
| 185 | Corpse Explosion | `drai kadh krak` | L | 160 | 400 | 6s | Corpses near the target burst (needs corpses). |
| 186 | Bone Golem | `vael gal oss` | BL | 100 | 500 | 30s | Raises the Bone Golem: slams everything next to it, taunts the monsters within 3 sqm. |
| 187 | Banner of Bones | `tor vas oss` | BL | 120 | 300 | 30s | 20 s: minions +30% damage, -25% damage taken, 3% regeneration per second. |
| 188 | Bone Offering | `drai sang oss` | BL | 150 | 250 | 12s | A skeleton bursts in 2 sqm; the Bone Lord takes 20% less damage for 6 s. |
| **monk** (Mo Monk, SF Shadowfist, IS Iron Sage; finishers need 1 chi and spend all, "5 chi" values; formula estimates, not measured) | | | | | | | |
| 63 | Ashen Fist | `kah dhun` | Mo, SF, IS | 15 | 30 | 2s | Quick strike at the target next to you; +2 chi. The builder. |
| 64 | Sundering Palm | `kah gal dhun` | Mo, SF, IS | 30 | 80 | 6s | Finisher: heavy palm strike, x(0.30 + 0.14 per chi). |
| 65 | Whirling Heel | `drai spir dhun` | Mo, SF, IS | 50 | 120 | 8s | Finisher: spinning kick on everything next to you (3x3), x chi scale. |
| 66 | Kindled Breath | `saen qhal` | Mo, SF, IS | 40 | 100 | 8s | Finisher: heals (level x 2 + fist x 6) x chi scale; the Iron Sage also heals 60% more over 6 s. |
| 67 | Mistborne Step | `ash qhal` | Mo, SF, IS | 35 | 60 | 10s | Roll up to 3 sqm forward; +25% dodge for 2 s. |
| 68 | Pressure Points | `kah mynd dhun` | SF | 100 | 120 | 4s | Strike + 1 chi + a stack on the target (max 5, 8 s): +5% damage taken from Monks per stack. |
| 69 | Shadowfist Flurry | `kah gal umh dhun` | SF | 150 | 300 | 12s | Finisher: 2 + 1 per chi hits, one every 0.2 s, while the target stays next to you. |
| 70 | Chi Ward | `tor qhal ["Name"]` | IS | 100 | 200 | 12s | Finisher: shield absorbing (level x 2.5 + fist x 8) x chi scale for 8 s on a party member within 5 sqm (the named one, or the most hurt; you without a party). |
| 71 | Iron Palm | `kah brak dhun` | IS | 120 | 200 | 8s | Finisher: strike x chi scale; stuns a monster 0.6 s + 0.4 s per chi (cannot move or attack), then 4 s immune; >50000 max health: only slowed 50%. |
| 72 | Mantra of Stone | `tor vas qhal` | IS | 150 | 400 | 30s | 12 s aura: you and party members within 6 sqm take 8% less damage. |
| **templar** (T Templar, I Inquisitor, Se Sentinel; P = weapon power, see "Templar line"; formula estimates, not measured) | | | | | | | |
| 189 | Radiant Smite | `kah sol dyr` | T, I, Se | 20 | 60 | 4s | Holy strike on one target within 3 sqm: P x 0.10-0.16 + ml x 1-1.5 + 30-60. The filler. |
| 190 | Consecration | `drai sol haln` | T, I, Se | 40 | 200 | 20s | Holy ground (circle 2) for 6 pulses: P x 0.025-0.04 + ml x 0.4-0.6 + 10-20 per pulse; allies in it healed 30% of a pulse. |
| 191 | Vow of Mending | `saen tor fidh` | T, I, Se | 30 | 150 | 8s | Self heal: 8% max health + level/5 + ml x 4 (±10%). |
| 198 | Judgement | `kah sol vehm` | I | 100 | 250 | 12s | Holy strike (range 5): P x 0.08-0.12 + ml x 1-1.5 + 20-40; the target takes +20% holy damage from everyone for 8 s. |
| 199 | Purging Nova | `drai gal sol orr` | I | 120 | 350 | 8s | Holy circle of 3 sqm: P x 0.08-0.13 + ml x 1-1.5 + 20-40; heals 10% of the damage, at most 5% max health. |
| 250 | Zealotry | `vyr sol zel` | I | 150 | 200 | 30s | 20 s: each melee weapon hit adds a stack, +4% to all damage per stack (max 10); stacks drop 3 s after the last hit. |
| 251 | Rebuke | `vok sol kal` | Se | 100 | 150 | 12s | Taunts every monster within 4 sqm, 25% slow for 6 s. |
| 252 | Aegis of Faith | `tor gal sol aeg` | Se | 120 | 150 | 25s | With a shield: -40% damage taken for 5 s. |
| 253 | Lay on Hands | `saen gal manh "Name"` | Se | 150 | 400 | 60s | Party member (named, or the lowest health share) or itself within 5 sqm: 35% max health + ml x 10. |

Damage formulas follow the stock style: `level/5 + magicLevel*a + b` (min/max with different a, b); knight spells use the stock
skill*attack callback, paladin spells scale mainly with the distance skill (plus a little magic level).

### Classes (Berserker, Beastmaster; the class rework, docs/CLASSES.md)

- **Rage** (Berserker, passive, `data/scripts/chaos/berserker_combat.lua`): every damage the Berserker deals is x(1 + 0.30 x
  min(1, missing health / 70%)): nothing at full health, +15% at 65%, +30% at 30% health and below (`Chaos.classes.rage`). Bloodrage adds
  +10% on top. Keystone extra hits and the Bloodrage cleave get no Rage of their own.
- **Companion** (Beastmaster, `data/scripts/chaos/beastmaster.lua`, `Chaos.classes.companion`): a War Wolf (look type 3; the Wolf if the
  server has none), the player's summon, so the engine makes it follow the owner and attack the owner's target. Every 2 s it bites the
  owner's target when next to it: physical damage dealt as the owner, avg = 0.12 x level + 0.6 x distance skill, +-20% (level 1000,
  distance 154: ~212). Health 500 + 15 x level. 1 companion, 2 from level 400. It drops no loot, the owner's own hits (arrow splash,
  area spells) do not hurt it, it is brought back when more than 7 sqm away or on another floor, and it goes when the character stops
  being a Beastmaster. The base server's familiar (`!summonfamiliar`) refuses while a companion is out (one summon of any kind).
- The Berserker uses two-handed melee weapons (the knight's area spells, Skyfall Cleave, Bloodrage, and the Cleaving Arc keystone); the
  Beastmaster bows and arrows (arrow splash, the Ricochet keystone).

Sanity measurement at level 1000 (`ztest/classrot.lua` on the test server: 90 s, auto attack on the main dummy, spells on cooldown,
buffs kept up, the knight / paladin level 1000 equipment, melee skills 140 / distance 141, **no passive tree points**, so lower than the
tables above; both classes of a line measured with the same character and gear):

| Class | Weapon | Kit in the rotation | Total single target | Total 5 targets | Mana/min |
|---|---|---|---|---|---|
| Juggernaut | Dawnforged Longsword (2h) | Colossus Fall, Earthbreaker, Vaulting Cleave, Reaping Gyre, Red Frenzy | 743 | 1765 | 4610 |
| Berserker | same | + Skyfall Cleave, Bloodrage | 927 | 2456 | 6480 |
| Deadeye | crossbow + bolts | Hail of Dawn, Final Verdict, Dawnpiercer | 1130 | 1130 | 4950 |
| Beastmaster | bow + arrows | Wild Bond, Feral Command, Dawnpiercer (2 companions) | 1064 | 2262 | 2680 |

The Berserker does ~1.4x the Juggernaut's area damage and ~1.25x its single target with full health (Rage near 0; Bloodrage costs
health, so Rage was ~+10% late in the run); the Juggernaut keeps Iron Bellow / Iron Will, Bulwark and more defence. With the 2h
knight's level 1000 tree numbers (1957 / 3664) that puts the Berserker around 2400 / 5100, under the Elementalist's 6427 area damage.
The Beastmaster stays under the Deadeye in single target (its companions are ~230 of the 1064: measured alone 292 per second before the
last tuning, x0.8 since) and above it on packs (arrow splash). Rage alone, auto attack only (40 s): 413 per second at full health, 559 at
30% health (+35%; the formula is +30%, the auto attack varies by ~15%). Before tuning the first runs gave the Berserker 2507 on 5
targets (cleave 50%, weapon hits x1.1, Skyfall x0.8) and the Beastmaster 1338 single target (bites 0.30 x level + 1.5 x skill, 3 bites
per Feral Command, Hail of Dawn in the kit, and companions killed by the owner's own arrow splash).

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

Roles as measured before the class rework (the old vocations; the classes that took the kits over are in docs/CLASSES.md):

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

### Healing (the Illusionist healer pass)

The Illusionist is the best healer, for one ally and for the party, and keeps its party attack buffs (docs/CLASSES.md). Rules and
numbers: `data/scripts/chaos/healing_rules_core.lua` (`ChaosHealing.cfg`), glue `healing_rules.lua`, tests
`server/tests/healing_rules_test.lua`.

- **Weaver's Grace** (Illusionist passive): heals it casts on another player are +5% (stock heals included; its self heals are not).
- **Mirror Mend** (96) and **Lucid Reverie** (97): the table above. Ids 96 and 97 are free in the base server's spells.xml, the
  client's stock spell list and the Chaos block, and outside the class lines' reserved ranges.
- **Shared Phantasm** (keystone 621): party members also heal for 4% of the damage they deal to a marked enemy (healed by the
  Illusionist, collected per server tick); the +12% damage stays.
- **PvP healing reduction** (every class): a player in PvP combat receives 30% less healing (any heal that passes onHealthChange:
  spells, potions, Shared Phantasm; not regeneration conditions or auras). PvP combat = damaged by or damaging a player (or a
  player's summon) in the last 10 s, fight-locked by a player attack, in an arena match, or in the siege arena during a match.

Measured on the test server, every heal cast through its script by one character (intelligence 20, which the engine adds to
every non-physical value, so heals are x1.2 for every class), on itself and on a second player in its party: a same-level
Juggernaut (5562 health at level 300, 18162 at level 1000). Magic level 100 / 140 for the casters (Illusionist, Mystic, Lich),
Sentinel ml 25 / 40 and sword 110 / 140, Iron Sage fist 110 / 140, Ranger line ml 30 / 40, Warrior line ml 10 / 12; no passive
tree, no gear. 4 to 16 casts per spell (12-16 for the Illusionist's kit and the stock heals); Circle of Mending by its words in
the game client (its stock script finds no targets from the harness). Rotation model on those averages: 60 s, every spell on
its cooldown, one lock per spell group (healing / attack / support), always the ready spell with the most healing per second of
lock; mana not limited (Mana/min shows the cost). "Group" = 4 allies in range of every party heal (a party heal heals each
the same). Formula-only parts: the Sentinel aura (0.4% of the ally's max health per second, per ally), the Iron Sage's Kindled
Breath heal over time (+60%), Chi Ward (an absorb shield, counted as healing on the ally). Not in the numbers: potions (any class,
one per second; mages only have the weak health potions), Shared Phantasm (depends on the party's damage: ~4% of it), the
Beastmaster's Wild Bond (heals companions only) and the Bone Lord's banner (minions only).

| Level | Class | On another player /s | Heal per mana | Group, 4 allies /s | Mana/min (group) | Self /s | Biggest single cast on an ally |
|---|---|---|---|---|---|---|---|
| 300 | Illusionist (before) | 1570 | 10.1 | 3950 | 8280 | 1555 | 3140 |
| 300 | **Illusionist (after)** | 1797 | 10.3 | 4429 | 9320 | 1538 | 3261 |
| 300 | Mystic (base class) | 1473 | 10.2 | 3363 | 7660 | 1456 | 3140 |
| 300 | Lich (Necromancer line, same stock heals) | 1473 | 10.2 | 2811 | 8960 | 1547 | 3140 |
| 300 | Elementalist | 0 | 0.0 | 0 | 0 | 1456 | 0 |
| 300 | Sentinel (+ aura 0.4%/s) | 92 | 4.2 | 235 | 1000 | 150 | 2668 |
| 300 | Iron Sage (Chi Ward = absorb) | 136 | 8.2 | 136 | 1000 | 302 | 1630 |
| 300 | Ranger line | 0 | 0.0 | 0 | 0 | 798 | 0 |
| 300 | Warrior line | 0 | 0.0 | 0 | 0 | 359 | 0 |
| 1000 | Illusionist (before) | 2205 | 14.2 | 5738 | 8280 | 2222 | 4595 |
| 1000 | **Illusionist (after)** | 2722 | 15.7 | 6780 | 9290 | 2317 | 4736 |
| 1000 | Mystic (base class) | 2039 | 14.1 | 4812 | 7660 | 2048 | 4595 |
| 1000 | Lich (Necromancer line, same stock heals) | 2039 | 14.1 | 4091 | 8960 | 2267 | 4595 |
| 1000 | Elementalist | 0 | 0.0 | 0 | 0 | 2048 | 0 |
| 1000 | Sentinel (+ aura 0.4%/s) | 309 | 14.2 | 825 | 1000 | 373 | 8218 |
| 1000 | Iron Sage (Chi Ward = absorb) | 302 | 18.1 | 302 | 1000 | 682 | 3620 |
| 1000 | Ranger line | 0 | 0.0 | 0 | 0 | 1180 | 0 |
| 1000 | Warrior line | 0 | 0.0 | 0 | 0 | 733 | 0 |

Before -> after for the Illusionist: on another player +14% / +23% (level 300 / 1000), the party +12% / +18%, heal per mana up,
self heal unchanged. Lead after: on another player +22% / +33% over the next class (the Mystic and the Necromancer line share the
stock Kindred Mend), the party +32% / +41% over the base Mystic and +58% / +66% over the Lich (the next ascended class: the
Necromancer line has the Mystic's stock heals, Circle of Mending and Kindred Mend included). The biggest single cast on an ally
stays the Sentinel's Lay on Hands at level 1000 (35% of the ally's max health, every 60 s): its emergency heal and tank-support
identity; at level 300 Heartwood Embrace is bigger. The Sentinel (aura, Lay on Hands, Consecration) and the Iron Sage (Chi
Ward, Kindled Breath) stay far behind as healers (a tank-support and a bruiser).

PvP check (two clients, level 300): a real auto attack from the second player fight-locks it and puts both in PvP combat;
heals then land at x0.70 (a flat 1000 heal: 1200 -> 840 on the Illusionist, 1260 -> 882 with Weaver's Grace on the other
player), and are back to full 10 s after the last hit. So the Illusionist heals less in PvP than before this pass: about
1260 per second on a partner and 1080 on itself at level 300 (1570 / 1555 before), against the engine's halved player damage
(e.g. Hail of Dawn ~1830 per cast on a level 300 player): a focused Illusionist still dies; arena and siege rules unit-tested
(not run in a live match).

### Thief line (Thief, Ninja, Samurai)

Ascension at level 100 (the Ascendant Oracle, data/scripts/chaos/ascension.lua). The kit's mechanics are scripted in
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

### Necromancer line (Necromancer, Lich, Bone Lord)

**Phase A: built, not tested in game. Every number below is a formula estimate until measured (phase B).**
Ascension at level 100 (the Ascendant Oracle), behind the store unlock of the Necromancer (`class_unlocks.lua`). Numbers:
`data/scripts/chaos/necro_config.lua`, rules: `necro_core.lua`, minions: `necro_minions.lua`, curse and bone shield:
`necromancer_combat.lua`.

- **Minions** are summons (Game.createMonster + setMaster) of three monster types without attacks of their own
  (`monster/monsters/chaos/necro_*.xml`): Risen Skeleton (Necromancer, Bone Lord; melee), Lich Shade (Lich; death bolts
  from 4 sqm), Bone Golem (Bone Lord; slams everything next to it and taunts the monsters within 3 sqm). Every 2 s
  (golem 2.5 s) a minion that reaches the owner's target hits it, and the hit is **dealt as the owner**: it counts like
  the owner's own damage for experience (the engine would give half for a summon's share), loot (the engine skips the
  rarity roll when a summon lands the last hit), corpse ownership, bounties, leaderboards, the hunt tracker and curses.
  Hit: (level x 0.24 + magic level x 0.5) x class factor (Necromancer 1, Lich shade 2.4, Bone Lord skeleton 0.6 + 75%
  splash on the enemies next to the target, golem 1.8); health: (200 + level x 9 + magic level x 6) x class factor
  (1 / 2.5 / 1.2 / golem 4). Caps: Necromancer 1 / 2 (level 40) / 3 (80) / 4 (200) skeletons; Lich 1 shade; Bone Lord
  5 / 6 (400) skeletons + the golem.
- **Raise Dead** uses empty corpses only (never destroys loot; yours, your party's or nobody's), else raises one from
  nothing for twice the mana. Minions follow and are brought back past 7 sqm or across floors, rest while the owner
  stands in a protection zone (monsters cannot enter one) and rise again outside, and go with the owner's logout or death.
- **Withering Curse** (+15% damage taken from everyone, the Lich's +25% and spread to 2 more; monsters only, players
  just rot), **Soul Rot** (6 s death DoT that jumps on death), **Life Siphon** (heals 50% of the damage),
  **Corpse Explosion** (needs corpses), **Banner of Bones** (+30% minion damage, -25% taken, 3% regen/s for 20 s),
  **Bone Offering** (a skeleton bursts in 2 sqm; -20% damage taken for 6 s).
- **Soul Hoard** (Lich): +25% spell damage while the shade slot is empty: the Lich plays with its shade or without.
- **Level factor**: the line's spells x (1 + (level - 300) / 2800), at most 1.25 (x1.25 at level 1000), a stand-in for
  the passive tree the line does not have yet (minions scale on their own formula). Re-tune both with the tree.

Planned numbers (formula model, not measured yet): a 60 s rotation with the 2 s group cooldown, every spell on its
cooldown, the curse always up, minions hitting all the time, the wand's auto attack from the mage tables (110 / 380 per
second), no passive tree, magic level 100 at level 300 and 140 at level 1000. 5 targets: the five dummies side by side
(the minions' main target plus four neighbours). Corpse Explosion is not in the numbers (the dummies leave no corpses).

| Level | Class | Minions | Total single target | Total 5 targets | Mana/min | Max health (no gear) |
|---|---|---|---|---|---|---|
| 300 | Lich (with its shade) | 1 | **~1000** | ~1280 | ~5050 | 2229 |
| 300 | Lich (no shade, Soul Hoard) | 0 | ~990 | ~1360 | ~5050 | 2229 |
| 300 | Bone Lord | 5 + golem | ~830 | **~2110** | ~3850 | 2813 |
| 300 | Necromancer | 4 | ~640 | ~640 | ~1600 | 2521 |
| 1000 | Lich (with its shade) | 1 | **~2670** | ~3580 | ~5050 | 7129 |
| 1000 | Lich (no shade, Soul Hoard) | 0 | ~2640 | ~3830 | ~5050 | 7129 |
| 1000 | Bone Lord | 6 + golem | ~2330 | **~5780** | ~3850 | 9113 |
| 1000 | Necromancer | 4 | ~1760 | ~1720 | ~1600 | 8121 |

Against the tables above: the Lich sits in the single-target bracket (Ninja 1050 / 2837, Paladin 1074 / 2770); the Bone
Lord is second in area damage behind the Elementalist (2815 / 6427) and below the Lich on one target; the Necromancer
before its ascension is at the Thief's level (728 / 1802). To be measured with the dummy harness (phase B).

### Monk line (Monk, Shadowfist, Iron Sage)

**Phase A: built, not tested in game. Every number below is a formula estimate until measured (phase B).**
Ascension at level 100 (the Ascendant Oracle), behind the store unlock of the Monk (`class_unlocks.lua`). Rules and every number:
`ChaosMonk` in `data/scripts/chaos/monk_chi_core.lua`; combat glue `data/scripts/chaos/monk_combat.lua`.

- **Unarmed**: the engine's fist hit (attack 7, no vocation multiplier) is rescaled for a Monk to a fist attack of 40 + level x 0.025 (max 60)
  x meleeDamage 1.2 (Iron Sage 1.1); about x5 at level 300. Attack speed: the vocation's (1500 / 1300 / 1700 ms) minus dexterity.
- **Chi** (max 5, gone after 12 s untouched): +1 per melee hit (at most one per 2 s), +2 Ashen Fist, +1 Pressure Points. Finishers spend all of
  it and do x(0.30 + 0.14 x chi) of their 5-chi value (0.44 at 1 chi). The kit's damage is ORIGIN_SPELL; physical, blocked like a spell.
- **Strike formula** (like the Thief line's): (level / 5 + power x a + b) x the level factor (Chaos.classes.spellLevelScale, x2 at level 1000),
  power = fist skill x fist attack (a staff: club skill x its attack).
- **Shadowfist**: a finisher opens a 4 s focus: weapon hits and strikes crit (x1.5) with 8% per chi spent. Pressure Points: +5% per stack.
- **Evasion**: 6% Monk, 8% Shadowfist, 4% Iron Sage against melee and ranged hits; +25% for 2 s after Mistborne Step.

**Estimate, not measured** (`ztest`-style rotation computed from the formulas: 90 s, the auto attack averaged from the formula, dexterity 20,
the 2 s group cooldown, best ready spell, finishers at 4+ chi, Pressure Points kept at 5 stacks; no passive tree; skill 110 at level 300, 140 at
level 1000; no armour on the target). The "5 targets" column is the area-first rotation (Whirling Heel before the single-target finishers).

| Level | Class | Auto attack | Total single target | Total 5 targets | Mana/min | Max health (est.) |
|---|---|---|---|---|---|---|
| 300 | Shadowfist | 414 | **~1020** | ~1340 | ~3400 | ~4430 |
| 300 | Monk | 255 | ~590 | ~880 | ~1700 | ~4430 |
| 300 | Iron Sage | 208 | ~530 | ~750 | ~2100 | ~5010 |
| 1000 | Shadowfist | 743 | **~2930** | ~4020 | ~3400 | ~14500 |
| 1000 | Monk | 458 | ~1600 | ~2590 | ~1700 | ~14500 |
| 1000 | Iron Sage | 374 | ~1490 | ~2220 | ~2100 | ~16490 |

Target: the Shadowfist in the single-target bracket with the Ninja (1050 / 2837) and the crossbow Deadeye (1074 / 2770); the Iron Sage tanky with
modest damage, below the knight (639 / 1957), paid back by Chi Ward (~1630 absorb at level 300, ~3620 at level 1000, every 12 s), Mantra of
Stone (-8% for the party) and the stun. The Shadowfist's area value at level 1000 (~4020, Whirling Heel with the focus crit) is above the
Ninja's 3710: watch it in phase B (lower `whirlingHeel` or exclude area strikes from the focus crit if it holds).

### Templar line (Templar, Inquisitor, Sentinel)

**Phase A: built, not tested in game. Every number below is a formula estimate until measured (phase B).**
Ascension at level 100 (the Ascendant Oracle). Locked behind the store's class unlock (docs/CLASSES.md, "Class lock").
Mechanics in `data/scripts/chaos/templar_combat.lua`, ids, numbers and rules in `templar_aura_core.lua` (`ChaosTemplar.cfg`).
Power P = the best of sword, club and axe skill x the main-hand weapon's attack; strikes are
`(level/5 + P x a + magic level x b + c) x level factor` (x1 up to level 300, x2 at level 1000, at most x2.2: the Thief line's
stand-in for the missing passive tree). The spells are in the table above.

Passives: the defence aura (Templar -6% within 4 sqm, Inquisitor -4% within 3, Sentinel -12% within 5 and 0.4% max health per
second; the strongest aura counts) and Radiant Strikes (a holy strike for 15% / 25% / 10% of each melee weapon hit).

Formula estimates, with the gear and skills of the Thief-line runs (level 300: sword 110, a one-handed blade of attack 55, magic
level ~25; level 1000: sword 140, attack 65, magic level ~40), no passive tree points, the auto attack scaled from the Thief's
measured one (attack speed 2000 instead of 1600, weapon hits x1.0) plus Radiant Strikes, a 90 s rotation with the 2 s group
cooldowns, Judgement and Zealotry at their uptime (2/3):

| Level | Class | Auto attack (+ Radiant) | Total single target | Total 5 targets | Mana/min | Base max health |
|---|---|---|---|---|---|---|
| 300 | Templar | ~245 | ~560 | ~900 | 1500 | 4273 |
| 300 | Inquisitor | ~270 | ~940 | ~1770 | 5800 | 3981 |
| 300 | Sentinel | ~210 | ~530 | ~870 | 1500 | 4273 |
| 1000 | Templar | ~450 | ~1510 | ~2780 | 1500 | 14073 |
| 1000 | Inquisitor | ~490 | ~2640 | ~5550 | 5800 | 13081 |
| 1000 | Sentinel | ~390 | ~1450 | ~2720 | 1500 | 14073 |

Toughness against weapon attacks (estimate): Juggernaut x0.765 damage taken (Iron Will -25% at 40% uptime, Bulwark 15% block),
15 hp per level -> 19.6 effective hp per level; Sentinel x0.81 (own aura -12%, Aegis of Faith -40% at 20% uptime) with 14 hp per
level -> 17.3, about 88% of the Juggernaut, plus 0.4% max health per second. A party member next to a Sentinel takes 12% less
damage and regenerates 0.4% per second (next to a Templar 6% less).

Targets for the measurement (phase B): the Inquisitor's 5-target total near the Berserker's, the Templar in the knight's range,
the Sentinel the lowest damage of the line; and the party test: the same level 300 Mystic among four Behemoths for 60 s without
healing, alone and with a Sentinel 3 sqm away (expected: ~12% less damage taken plus the regeneration).

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
- spellid: 200-249 without 237 (the base server's Duelist's Oath has 237), a block no other stock spell (server or client) uses. Ids must stay below 256: the 10.98 cooldown packet
  (`ProtocolGame::sendSpellCooldown`) sends the id as one byte, so an id like 410 arrives as 154 and the client (action bar,
  helper) puts the cooldown on the wrong spell. A few stock spells of the base server (ids 258-268) already wrap that way.
  The stock file also has a duplicate spellid (106) not related to this work.
  The new lines use ids that are free in the base server's spells.xml and in the client's stock spell list: 180-188 (the
  Necromancer line), 63-72 (the Monk line; 73, 74 kept free), 189-191, 198, 199 and 250-253 (the Templar line).
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
The client side is done in `client/overlay/modules/game_chaosspells` (spell list, action bar, icons); regenerate its data with `python3 -I client/tools/gen_spell_data.py` after changing `spells_chaos.xml`. The icons (cells 201..277, drawn by `client/tools/gen_spell_icons.py`) live in the complete generated spell icon sheets in `client/overlay/data/images/game/spells/`; rebuild those with `client/tools/gen_all_spell_icons.py`. See `client/MANIFEST.md`.
