# Chaos spells (the base server, TFS 1.4.2 / protocol 10.98)

77 custom spells, dark-fantasy flavour: 7 sorcerer, 7 druid, 6 paladin, 6 knight, 6 illusionist, 4 shared utility spells, 9 for the
Thief line (Thief, Ninja, Samurai; see "Thief line" below), 4 for the Berserker and the Beastmaster (see "Classes" below), 9 for the
Necromancer line (Necromancer, Lich, Bone Lord; see "Necromancer line"), 10 for the Monk line (Monk, Shadowfist, Iron Sage; see
"Monk line") and 9 for the Templar line (Templar, Inquisitor, Sentinel; see "Templar line"). The last three lines were tested in game
on 2026-10-09/10 (phase B: every spell cast through the client, 60 s rotations at level 300; their sections below). Since the
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
| 206 | Doomtide | `drai zhul infr doma` | E | 300 | 1500 | 45s | **Cast time 1.5 s.** Three waves (fire, energy, fire) over a 13x13 circle around you. |
| **druid** | | | | | | | |
| 207 | Blightswarm | `drai vex kriv` | M, I | 25 | 110 | 8s | Poison cloud (7x7) around you: earth damage plus a poison condition. |
| 208 | Purifying Wellspring | `saen vas aquen` | M, I | 40 | 160 | 6s | Heals you, party members and your summons within 3 sqm and cures poison/fire/energy/bleeding/curse/freeze/dazzle/drown. |
| 209 | Ironbark Hide | `tor ael skar` | M, I | 60 | 140 | 25s | +20% max health and regeneration for 20s. |
| 210 | Briar Prison | `drai thral brin` | I | 70 | 240 | 14s | Thorns erupt around the target (3x3, 3 pulses) and root enemies (90% slow) for 5s. |
| 211 | Moonfang Pack | `vael luth wyrd` | I | 120 | 450 | 30s | Summons 2 wolves (3 from level 200) for 40s; max 4 summons. |
| 212 | Verdant Sanctuary | `saen gal vas vert` | I | 180 | 600 | 30s | Healing zone on your tile: 8 pulses (1/s) heal allies within 3 sqm. |
| 213 | Primordial Squall | `drai gal vas stoma` | I | 250 | 1200 | 35s | **Cast time 1.5 s.** Three waves (earth, ice, earth) over an 11x11 circle; the ice wave slows 50%. |
| **paladin** | | | | | | | |
| 214 | Dawnpiercer | `kah sol aurr` | R, D, BM | 30 | 60 | 3s | Holy bolt at one target, the paladin filler; scales mainly with distance skill. |
| 215 | Skewering Line | `kah sag lanc` | R, D, BM | 60 | 150 | 8s | 7 sqm line of spears in your facing direction; scales with distance skill. |
| 216 | Blessed Earth | `drai vas sol hal` | R, D, BM | 100 | 350 | 24s | Consecrates your tile for 6s: holy damage to enemies within 2 sqm each second, allies are healed half as much. |
| 217 | Lightward | `tor sol ghar` | R, D, BM | 140 | 300 | 30s | Cleanses harmful conditions (incl. paralyze) and gives 8s of strong health/mana regeneration. |
| 218 | Final Verdict | `kah gal sol judh` | D | 200 | 450 | 14s | Heavy holy strike (distance skill); +50% damage against targets under 25% health. |
| 219 | Hail of Dawn | `drai gal vas sol volv` | R, D | 280 | 800 | 24s | **Cast time 1 s.** 3 volleys of 4 holy arrows, every arrow strikes the target (distance skill). |
| **knight** | | | | | | | |
| 220 | Reaping Gyre | `kah spir` | W, J, B | 30 | 80 | 6s | Three spinning strikes (0/0.4/0.8s) against adjacent enemies; uses weapon attack and skill. |
| 221 | Earthbreaker | `kah grund krak` | W, J, B | 60 | 150 | 10s | Shockwave (5x5) with physical damage; staggers enemies (60% slow, 3s). |
| 222 | Red Frenzy | `vyr ira cruor` | W, J, B | 100 | 300 | 40s | +30% melee skill, -30% shield skill for 12s. |
| 223 | Iron Bellow | `vok vas rhov` | W, J | 120 | 200 | 20s | Taunts all monsters within 4 sqm and slows them 25% for 6s; Iron Will: you take 25% less damage and get +15% shielding for 8s. |
| 224 | Vaulting Cleave | `kah brak skai` | W, J, B | 170 | 250 | 12s | Jump next to the target and strike it with weapon attack and skill. |
| 225 | Colossus Fall | `kah gal vas tyr` | W, J, B | 260 | 650 | 30s | **Cast time 1 s** (wind-up). Two crushing blows (0/0.6s) in a 7x7 circle; enemies slowed 70% for 4s. |
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
| 243 | Counter Stance | `tor ryx` | Sa | 100 | 100 | 8s | For 3 s the next melee hit taken is parried (no damage) and answered with 1.5x the parried hit; every other hit taken is 30% smaller; taunts the monsters within 3 sqm (the Samurai is the duelist off-tank). |
| 244 | Iaijutsu | `kah gal kaen` | Sa | 120 | 350 | 10s | 0.8 s charge, then one heavy melee weapon strike on the target if it is still within 2 sqm. |
| 245 | Bushido Focus | `vyr mynd` | Sa | 150 | 200 | 30s | 30 s: +3% crit chance per second without taking damage (3 at once, max 10 stacks = 30%), crits do x1.5; a hit taken resets the stacks. |
| **berserker** (B) / **beastmaster** (BM) | | | | | | | |
| 246 | Skyfall Cleave | `drai skai hrun` | B | 100 | 300 | 10s | Leap next to the target (range 5) and slam a 3x3 square around it: (level/5 + skill x attack x 0.060..0.105 + 20..40) x 0.7 physical, 30% slow 2 s. Needs a weapon. |
| 247 | Bloodrage | `vyr sang khar` | B | 120 | 200 | 30s | Costs 10% of the current health; 12 s: Rage +10% and every melee weapon hit also strikes up to 4 other enemies next to you for 40% of it. |
| 248 | Wild Bond | `vael ferh` | BM | 100 | 300 | 10s | Calls the companion (a War Wolf; 2 from level 400): health 500 + 15 x level; companions already out come back to you and heal 50%. |
| 249 | Feral Command | `kah ferh` | BM | 110 | 200 | 8s | Every companion leaps to the target (range 7) and mauls it for 1.5 bites. |
| **necromancer** (N Necromancer, L Lich, BL Bone Lord; per-cast numbers: formula; rotations measured, see "Necromancer line") | | | | | | | |
| 180 | Raise Dead | `vael oss` | N, L, BL | 20 | 60 | 2s | Raises a minion from an empty corpse (never one with loot), else one from nothing for twice the mana; skeletons, the Lich's shade. |
| 181 | Bone Spear | `kah oss lanc` | N, L, BL | 15 | 40 | 2s | The filler: a bone spear at the target (range 5) that pierces to the creature behind. |
| 182 | Withering Curse | `kah nyx maled` | N, L, BL | 40 | 120 | 8s | The target takes +15% damage from everyone and rots (Lich: +25%, spreads to 2 more; monsters only, players just rot). |
| 183 | Soul Rot | `kah nyx putr` | L | 100 | 220 | 6s | 6 s death damage over time that jumps to a new host when the target dies. |
| 184 | Life Siphon | `kah sang nyx` | L | 130 | 260 | 8s | Death damage to the target; heals the Lich for 50% of it. |
| 185 | Corpse Explosion | `drai kadh krak` | L | 160 | 400 | 6s | Corpses near the target burst (needs corpses). |
| 186 | Bone Golem | `vael gal oss` | BL | 100 | 500 | 30s | Raises the Bone Golem: slams everything next to it, taunts the monsters within 3 sqm. |
| 187 | Banner of Bones | `tor vas oss` | BL | 120 | 300 | 30s | 20 s: minions +30% damage, -25% damage taken, 3% regeneration per second. |
| 188 | Bone Offering | `drai sang oss` | BL | 150 | 250 | 12s | A skeleton bursts in 2 sqm; the Bone Lord takes 20% less damage for 6 s. |
| **monk** (Mo Monk, SF Shadowfist, IS Iron Sage; finishers need 1 chi and spend all, "5 chi" values; rotations measured, see "Monk line") | | | | | | | |
| 63 | Ashen Fist | `kah dhun` | Mo, SF, IS | 15 | 30 | 2s | Quick strike at the target next to you; +2 chi. The builder. |
| 64 | Sundering Palm | `kah gal dhun` | Mo, SF, IS | 30 | 80 | 6s | Finisher: heavy palm strike, x(0.30 + 0.14 per chi). |
| 65 | Whirling Heel | `drai spir dhun` | Mo, SF, IS | 50 | 120 | 8s | Finisher: spinning kick on everything next to you (3x3), x chi scale. |
| 66 | Kindled Breath | `saen qhal` | Mo, SF, IS | 40 | 100 | 8s | Finisher: heals yourself (level x 2 + fist x 6) x chi scale. Iron Sage (the second healer): the most hurt party member within 5 sqm (you without a party) for fist x 33 x chi scale, and 60% more over 6 s. |
| 67 | Mistborne Step | `ash qhal` | Mo, SF, IS | 35 | 60 | 10s | Roll up to 3 sqm forward; +25% dodge for 2 s. |
| 68 | Pressure Points | `kah mynd dhun` | SF | 100 | 120 | 4s | Strike + 1 chi + a stack on the target (max 5, 8 s): +5% damage taken from Monks per stack. |
| 69 | Shadowfist Flurry | `kah gal umh dhun` | SF | 150 | 300 | 12s | Finisher: 2 + 1 per chi hits, one every 0.2 s, while the target stays next to you. |
| 70 | Chi Ward | `tor qhal ["Name"]` | IS | 100 | 200 | 12s | Finisher: shield absorbing (level x 2.5 + fist x 8) x chi scale for 8 s on a party member within 5 sqm (the named one, or the most hurt; you without a party). |
| 71 | Iron Palm | `kah brak dhun` | IS | 120 | 200 | 8s | Finisher: strike x chi scale; stuns a monster 0.6 s + 0.4 s per chi (cannot move or attack), then 4 s immune; >50000 max health: only slowed 50%. A player (when the hit lands): 0.5 s + 0.1 s per chi (no moving, attacks or attack spells), then 6 s immune, half as long within 15 s (server/README.md "Iron Palm stun on players"). |
| 72 | Mantra of Stone | `tor vas qhal` | IS | 150 | 400 | 30s | 12 s aura: you and party members within 6 sqm take 8% less damage, and every 2 s each is healed for level + fist x 26. |
| **templar** (T Templar, I Inquisitor, Se Sentinel; P = weapon power, see "Templar line"; rotations measured there) | | | | | | | |
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

### Cast times (2026-10-10)

Four heavy spells have a cast time (`data/lib/chaos_casting.lua`, server/README.md "Cast-time spells"; client `game_castbar`).
The mana and the cooldown are taken when the cast starts; moving, a new paralysis, casting another spell, opening a town portal,
dying, logging out or cancelling (click the bar) interrupts the cast and gives the mana, health cost and the spell's own cooldown back
(the 2 s group cooldown stays). When the time is up the effect fires; a targeted spell checks its target again (alive, attackable,
in range, in sight) and refunds when it fails. Damage taken does not interrupt. To make up for the wait each got more power:

| Spell | Cast time | Power before | Power now |
|---|---|---|---|
| Doomtide (206, Elementalist) | 1.5 s | x1.20 (`mlValues` scale) | x1.38 (+15%) |
| Primordial Squall (213, Illusionist) | 1.5 s | x0.85 | x0.98 (+15%) |
| Hail of Dawn (219, Ranger, Deadeye) | 1.0 s | x1.00 | x1.10 (+10%) |
| Colossus Fall (225, Warrior, Juggernaut, Berserker) | 1.0 s | x0.70 (skill formula) | x0.77 (+10%) |

Mana, cooldowns and levels are unchanged (`spells_chaos.xml` and the client's `spelldata.lua` are the same). The per-cast numbers in
"Classes" and "PvP" below were measured before this change. Tested in game (Elementalist, Deadeye, Juggernaut, Illusionist):
completion, interrupt by moving / a new paralysis / another spell / death / cancel, target moved out of range at the end; every
interrupt gave the mana and cooldown back once.

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

- **Weaver's Grace** (Illusionist passive): heals it casts on another player are +16% (stock heals included; its self heals are not).
  It was +5% until the role rebalance (2026-10-10): raised so the Illusionist stays at least 12% above the Iron Sage.
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
| 300 | Illusionist (after, Weaver's Grace +5%) | 1797 | 10.3 | 4429 | 9320 | 1538 | 3261 |
| 300 | **Illusionist (Weaver's Grace +16%, 2026-10-11)** | 1985 | 11.4 | 4893 | 9320 | 1538 | 3602 |
| 300 | Mystic (base class) | 1473 | 10.2 | 3363 | 7660 | 1456 | 3140 |
| 300 | Lich (Necromancer line, same stock heals) | 1473 | 10.2 | 2811 | 8960 | 1547 | 3140 |
| 300 | Elementalist | 0 | 0.0 | 0 | 0 | 1456 | 0 |
| 300 | Sentinel (+ aura 0.4%/s) | 92 | 4.2 | 235 | 1000 | 150 | 2668 |
| 300 | Iron Sage (Chi Ward = absorb) | 136 | 8.2 | 136 | 1000 | 302 | 1630 |
| 300 | Iron Sage, the second healer (2026-10-10) | 1591 | | 3709 | 2550 | 1591 | 3744 |
| 300 | **Iron Sage, the second healer (2026-10-11)** | 1765 | | 4039 | 2550 | 1765 | 4356 |
| 300 | Ranger line | 0 | 0.0 | 0 | 0 | 798 | 0 |
| 300 | Thief line (Shadow Mend) | 0 | 12.9 | 0 | 0 | 466 | 0 |
| 300 | Warrior line | 0 | 0.0 | 0 | 0 | 359 | 0 |
| 1000 | Illusionist (before) | 2205 | 14.2 | 5738 | 8280 | 2222 | 4595 |
| 1000 | Illusionist (after, Weaver's Grace +5%) | 2722 | 15.7 | 6780 | 9290 | 2317 | 4736 |
| 1000 | **Illusionist (Weaver's Grace +16%, 2026-10-11)** | 3007 | 17.3 | 7490 | 9290 | 2317 | 5232 |
| 1000 | Mystic (base class) | 2039 | 14.1 | 4812 | 7660 | 2048 | 4595 |
| 1000 | Lich (Necromancer line, same stock heals) | 2039 | 14.1 | 4091 | 8960 | 2267 | 4595 |
| 1000 | Elementalist | 0 | 0.0 | 0 | 0 | 2048 | 0 |
| 1000 | Sentinel (+ aura 0.4%/s) | 309 | 14.2 | 825 | 1000 | 373 | 8218 |
| 1000 | Iron Sage (Chi Ward = absorb) | 302 | 18.1 | 302 | 1000 | 682 | 3620 |
| 1000 | Iron Sage, the second healer (2026-10-10) | 2375 | | 5513 | 2550 | 2375 | 5136 |
| 1000 | **Iron Sage, the second healer (2026-10-11)** | 2525 | | 5867 | 2550 | 2525 | 5544 |
| 1000 | Ranger line | 0 | 0.0 | 0 | 0 | 1180 | 0 |
| 1000 | Thief line (Shadow Mend) | 0 | 10.0 | 0 | 0 | 1201 | 0 |
| 1000 | Warrior line | 0 | 0.0 | 0 | 0 | 733 | 0 |

**Shadow Mend** (spell 98, `saen umh`, the Thief line's self heal; level 25, 2% of the maximum mana, cooldown 2 s, healing group 1 s; Thief,
Ninja, Samurai): level + magic level x 10 + 4% of the maximum health (+-10%), x1.3 while Shadow Veil is up; healing does not
end the veil (`Chaos.classes.shadowMend`, `ChaosClasses.shadowMendRange`, script `chaos/thief/shadow_mend.lua`). Id 98 is free in
the base server's spells.xml, the client's stock spell list and the Chaos block. Measured on the test server by its words in the
game client (a male Thief, intelligence 20, no tree, no gear, hurt to 20% before each cast): level 300 magic level 30 (4485
health) 932 per cast (12 casts, 878-974), 1250 veiled (5 casts); level 1000 magic level 40 (42 with the stat bonus, 14565
health) 2401 (12 casts, 2271-2497), 3140 veiled (4 casts). Every 2 s that is 466 / 1201 per second on itself: about the Ranger
line's self heal (798 / 1180), well below the Illusionist (1538 / 2317 on itself, and the line heals nobody else). Potions stay
the Royal Paladin's. The cost is `manapercent="2"` (2% of the maximum mana; it was a flat 80 mana, 11.6 / 30.0 healed per mana,
far above every other class at level 1000): measured 72 mana at level 300 (3612 mana) and 240 at level 1000 (12012 mana), so
12.9 / 10.0 healed per mana, about the Mystic's stock heals (10.2 / 14.1). The client shows the current cost
(`game_chaosspells` keeps the entry's mana at 2% of the player's maximum mana; the spellbook shows "2%").

Before -> after for the Illusionist: on another player +14% / +23% (level 300 / 1000), the party +12% / +18%, heal per mana up,
self heal unchanged. Lead after: on another player +22% / +33% over the next class (the Mystic and the Necromancer line share the
stock Kindred Mend), the party +32% / +41% over the base Mystic and +58% / +66% over the Lich (the next ascended class: the
Necromancer line has the Mystic's stock heals, Circle of Mending and Kindred Mend included). The biggest single cast on an ally
stays the Sentinel's Lay on Hands at level 1000 (35% of the ally's max health, every 60 s): its emergency heal and tank-support
identity; at level 300 Heartwood Embrace is bigger. The Sentinel (aura, Lay on Hands, Consecration) and the Iron Sage (Chi
Ward, Kindled Breath) stayed far behind as healers (a tank-support and a bruiser). Since the role rebalance (2026-10-10) the Iron
Sage is the second healer (rows in bold: Kindled Breath on the most hurt ally, Mantra of Stone heals the party; Chi Ward as before;
the model of this table, the per-cast heals checked in game), between the Mystic and the Illusionist.

Owner targets (2026-10-11): the Iron Sage about +20-25% over the Mystic, the Illusionist at least ~12% over the Iron Sage, one
ally and group, both levels. Kindled Breath on the Iron Sage is now fist x 33 (was level x 0.5 + fist x 27) and the Mantra of
Stone pulse level + fist x 26 (was x 24); Weaver's Grace +16% (was +5%; the Illusionist rows above are the +5% rows x 1.16/1.05,
the multiplier unit-tested in `healing_rules_test.lua`). Iron Sage over the Mystic: one ally +20% / +24% (level 300 / 1000),
group +20% / +22%. Illusionist over the Iron Sage: one ally +12% / +19%, group +21% / +28%.

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
- **Level factor**: dropped with the class trees (docs/CLASSES.md "Phase 2b"); see "Classes with the passive trees" below for the
  line's damage factor and the numbers measured with tree builds.

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

**Tested in game (phase B); the measured rotation is after the formula table.**
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
- **Level factor**: dropped with the class trees; see "Classes with the passive trees" below.

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
before its ascension is at the Thief's level (728 / 1802).

**Measured in game (phase B, 2026-10-09/10)**, the same way for the three lines: level 300 test characters without passive tree
points (stat window 20 in every stat, as for the tables above), every spell cast through the client (words, cooldowns and mana as
the table above; group cooldowns from the server), a 60 s window after a 12-24 s warm-up (minions raised, buffs up), damage =
health the dummies lost (5 000 000 health, so nothing died), auto attack on the main dummy. 1 target: one dummy; 5 targets: the
main dummy and four around it (east of the caster: (1,0), (1,-1), (1,1), (2,0), (2,-1)), the same rotation. Mana/min = the
spells' mana (a caster's wand costs 25 more per hit). Same harness, the Ninja at level 300 (sword 110, two embersage swords):
**1001** / 1323, mana 4400 (the table above: 1050 / 1385 / 4600), so these numbers sit next to the earlier ones.
Casters: magic level 100 (104 with the test gear), the gilded eldritch wand (level 250, 95-115 fire). Rotation: curse on cooldown,
Raise Dead while below the cap (from nothing when no corpse), the class spells, Bone Spear as the filler; Corpse Explosion is
left out (the dummies leave no corpses).

| Level | Class | Wand | Total single target | Total 5 targets | Mana/min | Max health (no gear) |
|---|---|---|---|---|---|---|
| 300 | Lich (with its shade) | 99 | **1113** | 1678 | 4780 | 2229 |
| 300 | Bone Lord (5 skeletons + golem, Bone Offering on cooldown) | 89 | 928 | **1940** | 4790 | 2813 |
| 300 | Necromancer (4 skeletons) | 92 | 706 | 735 | 1760 | 2521 |

Against the estimate (1000 / 1280, 830 / 2110, 640 / 640): within ~10% on one target; the Lich's 5-target number is higher (the
curse spreads to two more, Soul Rot jumps). The Lich is a little above the Ninja on one target (+11%), the Bone Lord below the
Elementalist's area numbers, the Necromancer at the Thief's level: no change. Single casts (level 400, magic level 109): Bone
Spear ~430 + ~250 on the creature behind, Withering Curse x1.15 on every later hit (minion hits included), Life Siphon ~1400
healing 585, Soul Rot ~2860 over 6 s, Corpse Explosion ~1900 + ~540 per neighbour (refused and no mana spent without corpses).
Seen in game: Raise Dead seals the corpse it used (the green circle) and never touches one with loot, raises from nothing for 120
mana, refuses past the cap (3 skeletons at level 100, 4 at level 300, the Bone Lord 6 + the golem at level 400); minions rest in a
protection zone and rise outside; a kill by a minion gives the owner the full experience and the loot.

### Monk line (Monk, Shadowfist, Iron Sage)

**Tested in game (phase B); the measured rotation is after the estimate table.**
Ascension at level 100 (the Ascendant Oracle), behind the store unlock of the Monk (`class_unlocks.lua`). Rules and every number:
`ChaosMonk` in `data/scripts/chaos/monk_chi_core.lua`; combat glue `data/scripts/chaos/monk_combat.lua`.

- **Unarmed**: the engine's fist hit (attack 7, no vocation multiplier) is rescaled for a Monk to a fist attack of 40 + level x 0.025 (max 60)
  x meleeDamage 1.2 (Iron Sage 1.1); about x5 at level 300. Attack speed: the vocation's (1500 / 1300 / 1700 ms) minus dexterity.
- **Chi** (max 5, gone after 12 s untouched): +1 per melee hit (at most one per 2 s), +2 Ashen Fist, +1 Pressure Points. Finishers spend all of
  it and do x(0.30 + 0.14 x chi) of their 5-chi value (0.44 at 1 chi). The kit's damage is ORIGIN_SPELL; physical, blocked like a spell.
- **Strike formula** (like the Thief line's): (level / 5 + power x a + b), power = fist skill x fist attack (a staff: club skill x
  its attack). The level factor (x2 at level 1000) was dropped with the class trees ("Classes with the passive trees" below).
- **Shadowfist**: a finisher opens a 4 s focus: weapon hits and strikes crit (x1.5) with 2.5% per chi spent (was 8%, see the
  measurement below). Pressure Points: +5% per stack.
- **Evasion**: 6% Monk, 8% Shadowfist, 4% Iron Sage against melee and ranged hits; +25% for 2 s after Mistborne Step.

**Estimate, not measured, with the former focus crit (8% per chi)** (`ztest`-style rotation computed from the formulas: 90 s, the auto attack averaged from the formula, dexterity 20,
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
Ninja's 3710: watch it in phase B (lower `whirlingHeel` or exclude area strikes from the focus crit if it holds). With 2.5% per chi
the same estimate gives Shadowfist 383 / ~930 / ~1210 at level 300 and 687 / ~2660 / ~3620 at level 1000 (auto / one target /
5 targets): the area value is below the Ninja's 3710 now.

**Measured in game (phase B, 2026-10-09/10)**, the same way for the three lines: level 300 test characters without passive tree
points (stat window 20 in every stat, as for the tables above), every spell cast through the client (words, cooldowns and mana as
the table above; group cooldowns from the server), a 60 s window after a 12-24 s warm-up (minions raised, buffs up), damage =
health the dummies lost (5 000 000 health, so nothing died), auto attack on the main dummy. 1 target: one dummy; 5 targets: the
main dummy and four around it (east of the caster: (1,0), (1,-1), (1,1), (2,0), (2,-1)), the same rotation. Mana/min = the
spells' mana (a caster's wand costs 25 more per hit). Same harness, the Ninja at level 300 (sword 110, two embersage swords):
**1001** / 1323, mana 4400 (the table above: 1050 / 1385 / 4600), so these numbers sit next to the earlier ones.
Monks: fist 110, unarmed, magic level 15. Rotation: finishers at 4+ chi (Shadowfist Flurry, then Sundering Palm; Iron Palm
first for the Iron Sage; Whirling Heel first on 5 targets), Pressure Points on cooldown (Shadowfist), Ashen Fist as the builder.

| Level | Class | Auto attack | Total single target | Total 5 targets | Mana/min | Max health (no gear) |
|---|---|---|---|---|---|---|
| 300 | Shadowfist (focus crit 8% per chi, before) | 467 | 1258 | 1258 (area rotation 1228) | 3400 | 3689 |
| 300 | Shadowfist (2.5% per chi, now; see below) | 395 | **1076** | 1076 (area rotation 1023) | 3400 | 3689 |
| 300 | Monk | 282 | 708 | 802 | 1400 | 3689 |
| 300 | Iron Sage | 220 | 602 | 662 | 2170 | 4273 |

Against the estimate (1020 / 1340, 590 / 880, 530 / 750): every Monk deals ~15-25% more on one target than estimated, the area
numbers are lower (Whirling Heel only reaches the dummies next to the Monk: 3 of the 5). **The Shadowfist was above its bracket**:
1258 against the Ninja's 1001 in the same harness (+26%), most of it the focus crit on the auto attack (467 per second). Max health: the Monk's gain is the
Thief's (12 per level), 3689 at level 300 without gear, not the ~4430 the estimate assumed. Seen in game: the chi HUD under the
character (pips, tooltip "Chi n / 5"), chi +1 per melee hit (one per 2 s), +2 Ashen Fist, +1 Pressure Points, gone after 12 s on
the server and the HUD; finishers spend all of it; Chi Ward on a named party member (1630 at level 300, ~1630 estimated) or the
most hurt one, Mantra of Stone -8% on the party member, Iron Palm stops a Behemoth's attacks for the stun, Mistborne Step rolls
3 sqm, Kindled Breath ~1790 at 5 chi (level 400).

**Shadowfist focus crit lowered (2026-10-10)**: `ChaosMonk.cfg.focus.critPerChi` 0.08 -> 0.025 (12.5% at 5 chi instead of 40%),
the auto attack still in the window. The math, same harness (fresh test server, level 300, single-target rotation, 60 s):
- Crit-free total B0 (critPerChi set to 0 live): 1007, 1008 -> **B0 ~ 1008**.
- 0.08: 1253, 1172, 1173 here and 1258 above, mean 1214 = B0 x 1.20. Counted rolls: 123 hits in the focus window in 72 s, 45
  crits (37%), average chi spent 5.0, i.e. the window covers nearly every hit (a finisher every ~6 s, 4 s window, the
  flurry and the next strikes inside it). So total ~ B0 x (1 + 0.5 x 5 x critPerChi), and 0.08 gives +20%.
- Target: a small lead over the Ninja's 1001, ~1050-1100: critPerChi = (T / B0 - 1) / 2.5 = 0.017-0.037; 0.025 for ~1071.
- Measured with 0.025: 1061, 1114, 1062, 1075 (set live) and 1125, 1038, 1057 (the repo value after a restart): **mean 1076**
  (+8% over the Ninja; the run-to-run spread is +-40, the auto attack's random rolls). 0.03 measured 1103 (6 runs).
  Area rotation on 5 dummies: 1023 total (was 1228); the single-target rotation stays the best on 5 (~1076).
- Level 1000 (formula, not measured): the estimate above without crit gives 2535 on one target; scaled by the level 300
  measured / estimated ratio without crit (1008 / 887 = 1.14) that is ~2880, x 1.0625 for the crit = **~3060** against the
  Ninja's 2837 and the Deadeye's 2770 (+8% / +10%, the same lead as at level 300; with 8% it was ~3450, +22%). Area: ~3620
  estimated, below the Ninja's 3710.

### Templar line (Templar, Inquisitor, Sentinel)

**Tested in game (phase B); the measured rotation is after the estimate table.**
Ascension at level 100 (the Ascendant Oracle). Locked behind the store's class unlock (docs/CLASSES.md, "Class lock").
Mechanics in `data/scripts/chaos/templar_combat.lua`, ids, numbers and rules in `templar_aura_core.lua` (`ChaosTemplar.cfg`).
Power P = the best of sword, club and axe skill x the main-hand weapon's attack; strikes are
`(level/5 + P x a + magic level x b + c)` (the level factor, x2 at level 1000, stood in for the passive tree and was dropped with the
class trees; "Classes with the passive trees" below). The spells are in the table above.

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

**Measured in game (phase B, 2026-10-09/10)**, the same way for the three lines: level 300 test characters without passive tree
points (stat window 20 in every stat, as for the tables above), every spell cast through the client (words, cooldowns and mana as
the table above; group cooldowns from the server), a 60 s window after a 12-24 s warm-up (minions raised, buffs up), damage =
health the dummies lost (5 000 000 health, so nothing died), auto attack on the main dummy. 1 target: one dummy; 5 targets: the
main dummy and four around it (east of the caster: (1,0), (1,-1), (1,1), (2,0), (2,-1)), the same rotation. Mana/min = the
spells' mana (a caster's wand costs 25 more per hit). Same harness, the Ninja at level 300 (sword 110, two embersage swords):
**1001** / 1323, mana 4400 (the table above: 1050 / 1385 / 4600), so these numbers sit next to the earlier ones.
Templars: sword 110, embersage sword (attack 55) + blessed shield, magic level 25. Rotation: Zealotry, Judgement, Purging Nova,
Consecration, Radiant Smite (the ones the class has), all on cooldown.

| Level | Class | Auto attack (+ Radiant) | Total single target | Total 5 targets | Mana/min | Max health (no gear) |
|---|---|---|---|---|---|---|
| 300 | Inquisitor | 280 | **969** | **1765** | 4950 | 3981 |
| 300 | Templar | 231 | 652 | 1005 | 1500 | 4273 |
| 300 | Sentinel | 168 | 558 | 1001 | 1500 | 4273 |

Against the estimate (940 / 1770, 560 / 900, 530 / 870): the Inquisitor as estimated, the Templar and the Sentinel ~5-15%
higher; the Inquisitor's 5-target number is the Berserker's range, as targeted. No change. Party test (a Sentinel and a level 300
Elementalist in one party): a hit of 1000 on the Elementalist 2 sqm from the Sentinel took 880 (-12%), 8 sqm away 1000; under the
aura it regenerated 80 in 10 s (0.4% of 1974 per second), out of it 0, and nobody got a heal message for it; Lay on Hands on the
named member healed it (35% + magic level x 10 = 941, x1.2 by the stat window's intelligence 20, which every heal gets) while the
Sentinel itself was lower; Aegis of Faith took a hit of 854 to 512 (-40%); Rebuke slowed and taunted the monsters around.

### Classes with the passive trees (C4, measured 2026-10-11)

Since the class trees (docs/CLASSES.md "Phase 2b") every class is measured **the same way** (the earlier tables above used
different methods per line and must not be compared with this one):
- the test server, a character of the class at level 300 and 1000 (stat window 20 in every stat), skills: melee 110 / 140
  (shielding -10), distance 110 / 140, magic level 100 / 140 for casters, 10-40 for the others; Monks fist 110 / 140;
- gear: level 300 the earlier test sets (wand of inferno, magic longsword for the Warrior line, embersage sword(s) for the Thief line
  and the Templar line with a shield, royal crossbow + infernal bolts, composite hornbow + crystalline arrows for the
  Beastmaster, Monks unarmed); level 1000 the best level 1000 sets (`ztest/gear1000.lua`: mage, knight two-handed / one-handed,
  paladin bolts / arrows; the Thief line Dawnforged Blades, Monks unarmed in the paladin armour);
- **a tree build for every class**: all its points (73 / 248), grown greedily from the start by the best damage per point for
  the class (strength / intelligence / dexterity up to their caps, its damage types, skills, crit), the keystones it can reach
  valued, and the class's own section path first for the four new lines (the build script is test-only: `zz_c4.lua`);
- the rotation harness: the client casts the class's attack spells by their words on cooldown (group cooldowns from the server,
  buffs kept up, minions raised in a 12-24 s warm-up, cast-time spells waited for), auto attack on the main dummy, 60 s, damage =
  health the dummies lost. 1 target: one dummy; 5 targets: the main dummy and four around it, the same rotation.
- healing per second on another player: the "Healing" table above (no tree, its own method), the Iron Sage measured per cast
  in game and put in the same rotation model (Kindled Breath 4356 at 5 chi, level 300, fist 110; in game 4921 in the first
  0.4 s, 3 casts: the cast plus the first heal-over-time tick, 436, and regeneration; the Illusionist with Weaver's
  Grace +16%). The Necromancer and the Bone Lord have the Lich's stock heals. Max health: the vocation's gain, no gear and no tree.
- every area hit gets the tree's damage bonuses and the class factor (the damage event is registered on every monster at spawn;
  before 2026-10-11 only on the attacked one, so the 5-target numbers of the four new lines missed them); procs and splashes that
  deal damage from inside a hit (the Bone Lord's splash, the arrow splash) do not get them twice (`ChaosKeystones.depth`);
- the Monk line's finishers are cast at 5 chi by the harness (earlier level 1000 runs of the Monk and the Iron Sage cast none);
- the spread run to run is about +-5% (up to 10% on one sample): the leads are on the mean of 2-6 samples (Deadeye 6 / 3,
  Elementalist 4 / 1, Berserker 2 / 1, the classes right behind 1-3).

**Class damage factor** (`ChaosClassTree.classDamage`, class_tree.lua): the four new lines were tuned without a tree (their kits matched
the other classes' numbers *with* tree points); with their trees they measured x2 to x3 too high (level 300: Ninja 2741, Samurai
2937, Lich 2371, Shadowfist 2389 against the Deadeye's 1351; level 1000: Ninja 7554, Lich 7408 against 4769). The level factors that
stood in for the tree (Thief / Monk / Templar spellLevelScale, x2 at level 1000; necro_config levelScale, x1.25) are dropped and every
damage of these classes is x a per-class factor, linear between level 300 and 1000 (Thief 0.48 / 0.53, Ninja 0.45 / 0.57, Samurai
0.30 / 0.37, Necromancer 1.0 / 0.64, Lich 0.50 / 0.57, Bone Lord 0.75 / 0.61, Monk 0.63 / 0.75, Shadowfist 0.49 / 0.69, Iron Sage
0.61 / 0.75, Templar 0.78 / 0.60, Inquisitor 0.65 / 0.58, Sentinel 0.73 / 0.60). The owner's targets (2026-10-11: the Deadeye and
the Elementalist at least 8-10% ahead, the classes right behind trimmed rather than the leaders raised) also set Berserker 0.78 /
1.0, Ranger and Beastmaster 1.0 / 0.95. Every number below is with these factors.

| Class | Role | 300: 1 target | 300: 5 targets | 300: heal/s on an ally | 300: max health | 1000: 1 target | 1000: 5 targets | 1000: heal/s on an ally | 1000: max health |
|---|---|---|---|---|---|---|---|---|---|
| Warrior | area / melee | 886 | 2127 | 0 | 4565 | 2351 | 6280 | 0 | 15065 |
| Juggernaut | tank (tankiest) | 781 | 1623 | 0 | 4565 | 2569 | 4424 | 0 | 15065 |
| Berserker | area | 974 | 2932 | 0 | 4273 | 2634 | 8218 | 0 | 14073 |
| Ranger | ranged | 1075 | 1409 | 0 | 3105 | 3673 | 5305 | 0 | 10105 |
| Deadeye | single target (best) | 1312 | 1446 | 0 | 3105 | 4571 | 5385 | 0 | 10105 |
| Beastmaster | pets / single target | 832 | 1919 | 0 | 3397 | 3267 | 9255 | 0 | 11097 |
| Mystic | caster | 803 | 2692 | 1473 | 1645 | 2439 | 8354 | 2039 | 5145 |
| Elementalist | area (best) | 913 | 3442 | 0 | 1645 | 2954 | 11004 | 0 | 5145 |
| Illusionist | healer (best) / support | 765 | 1747 | 1985 | 2229 | 2014 | 5239 | 3007 | 7129 |
| Thief | melee | 870 | 870 | 0 | 3689 | 2391 | 2297 | 0 | 12089 |
| Ninja | single target (burst) | 1121 | 1424 | 0 | 3689 | 3565 | 5101 | 0 | 12089 |
| Samurai | duelist off-tank | 751 | 770 | 0 | 3981 | 2025 | 2018 | 0 | 13081 |
| Necromancer | summoner | 1009 | 1069 | 1473 | 2521 | 2598 | 2622 | 2039 | 8121 |
| Lich | single target | 1164 | 2057 | 1473 | 2229 | 4037 | 7696 | 2039 | 7129 |
| Bone Lord | area / pets | 1158 | 2326 | 1473 | 2813 | 4104 | 7883 | 2039 | 9113 |
| Monk | melee | 955 | 1122 | 0 | 3689 | 2326 | 2794 | 0 | 12089 |
| Shadowfist | single target (burst) | 1181 | 1262 | 0 | 3689 | 3683 | 3948 | 0 | 12089 |
| Iron Sage | healer (second) | 796 | 829 | 1765 | 4273 | 1992 | 2399 | 2525 | 14073 |
| Templar | holy melee / aura | 904 | 1422 | 0 | 4273 | 2103 | 3375 | 0 | 14073 |
| Inquisitor | area | 1086 | 2056 | 0 | 3981 | 3556 | 6192 | 0 | 13081 |
| Sentinel | tank-support | 743 | 1285 | 92 | 4273 | 1948 | 3429 | 309 | 14073 |

Roles (the owner's order): the Deadeye leads single target at both levels (level 300 / 1000: Shadowfist -10% / -19%, Lich
-11% / -12%, Bone Lord -12% / -10%, Ninja -15% / -22%; level 300 1312 on the mean of 6 runs, 1256-1371; level 1000 4571, 3 runs,
4419-4681), the Elementalist leads area (Berserker -15% / -25%, Mystic -22% / -24%, Beastmaster -44% / -16%; level 300 3442 on 4
runs, 3173-3685), the Illusionist is the best healer and the Iron Sage the second (on an ally +20% / +24% over the Mystic's stock
heals, the Illusionist +12% / +19% ahead of it; the group, 4 allies: 4039 / 5867 against the Illusionist's 4893 / 7490 and the
Mystic's 3363 / 4812; "Healing" above). The Samurai deals a bit less than the Juggernaut and is an off-tank: 13 health per level,
5% evasion, Counter Stance (3 s of every 8 s, 4 s with Iron Parry) parries a melee hit and takes 30% off every other hit (checked
in game: a hit of 727 -> 509) and taunts: about 15.4 effective health per level against the Sentinel's 17.3 and the Juggernaut's
19.6 (21.3 with Immovable) in the toughness model of "Templar line". The Iron Sage's damage is below the Warrior's.

### Infinite arrows (bows and crossbows without ammunition, 2026-10-11)

Bows and crossbows fire without ammunition (server/README.md "Infinite arrows and quivers"). The install tool gives each
launcher the attack and hit chance of the ammunition of its level band (`data/lib/chaos_archery_config.lua` `bands`), so the
engine's sum (launcher attack + ammunition attack, ammunition hit chance + launcher hit bonus) is the same number as before.
Measured with the engine's formula (weapons.cpp: max = level / 5 + (skill / 4 + 1) x attack / 3 x 1.03, min = level / 5,
average = (min + max) / 2 x hit chance; the two-handed factor and armour apply alike before and after), a character of each
level band with the launcher of its band and the best ammunition an NPC sold for its own level
(`ARCHERY_REPORT=1 luajit tests/archery_test.lua` prints it; the test holds every row within 20% and the matching rows
equal):

| Level | Distance | Launcher (band level) | Ammunition before | Average hit before | Average hit after | Change |
|---|---|---|---|---|---|---|
| 8 | 30 | bow (0) | arrow 25 | 34.6 | 40.9 | +18.3% |
| 15 | 40 | bow (0) | arrow 25 | 45.5 | 53.9 | +18.5% |
| 25 | 50 | bow (0) | arrow 28 | 66.5 | 67.0 | +0.7% |
| 35 | 58 | bow (0) | arrow 33 | 89.3 | 78.1 | -12.5% |
| 45 | 62 | silkweaver bow (40) | arrow 38 | 113.0 | 113.0 | +0.0% |
| 65 | 70 | an old bow (60) | arrow 38 | 133.5 | 133.5 | +0.0% |
| 150 | 88 | umbral bow (150) | arrow 65 | 302.5 | 302.5 | +0.0% |
| 300 | 102 | falcon bow (300) | arrow 65 | 387.5 | 387.5 | +0.0% |
| 600 | 115 | sanguine bow (600) | arrow 65 | 498.0 | 498.0 | +0.0% |
| 1000 | 125 | seraphic bleeder (1000) | arrow 65 | 593.0 | 593.0 | +0.0% |
| 8 | 30 | crossbow (0) | bolt 30 | 39.6 | 41.8 | +5.5% |
| 20 | 45 | crossbow (0) | bolt 30 | 58.3 | 62.2 | +6.7% |
| 35 | 58 | crossbow (0) | bolt 33 | 82.7 | 80.0 | -3.2% |
| 42 | 60 | crossbow (0) | bolt 36 | 95.7 | 84.0 | -12.2% |
| 50 | 62 | modified crossbow (45) | bolt 36 | 100.8 | 100.8 | +0.0% |
| 95 | 80 | crystal crossbow (90) | bolt 66 | 252.5 | 252.5 | +0.0% |
| 400 | 108 | soulpiercer (400) | bolt 66 | 422.9 | 422.9 | +0.0% |
| 1000 | 125 | seraphic piercer (1000) | bolt 66 | 587.8 | 587.8 | +0.0% |

- From level 40 (bows) and 45 (crossbows) a launcher of its band deals exactly what it did with that band's ammunition.
- The level 0 bow and crossbow are the only launchers below that. They carry the average of what levels 1-39 fired: arrows
  +29 (arrow 25 to level 19, sniper 28 to 29, tarsal 33 to 39), bolts +32 (bolt 30, piercing 33, vortex 36). Levels 1-19
  hit 18% harder, 20-29 the same, 30-39 12% softer until the level 40 bows; crossbows +6% to -12%.
- A launcher below the character's band loses what better ammunition gave (a level 300 character with a level 60 bow had
  crystalline arrows, 65, and gets the onyx band, 38). That is the weapon's level now, like every other weapon.
- The class tables above were measured with a royal crossbow and infernal bolts (72): its band is the prismatic bolt (66), so
  that setup is 6.6% softer at level 300 / distance 110 and 5.5% at 1000 / 140. Infernal bolts were not on sale at a real
  price (300,000 gold each), so the band follows the prismatic bolt. The bow rows (crystalline arrows) are unchanged.
- In game (level 650 Ranger, sanguine bow, attack 9 -> 74 with the band, empty ammunition slot, distance 114, a troll): 42
  hits, average 423 after the troll's armour, highest 686. A Legendary Haloed Quiver (distance +3, attack speed +4%, 19% ice)
  then gave 722 physical and 137 ice per hit (after the two-handed factor).
- The quiver modifiers are new damage on top (critical strike +50%, extra projectile 60%, elemental shares, distance
  fighting, attack speed), capped like every item modifier; a quiver works only while a bow or crossbow is held.

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
