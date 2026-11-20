# Spell upgrades: design, O686 phase 1

Status: design written, waits for the owner's review. No game code. Every number below is a proposal, computed from the committed models, never measured in game.

Owner 2026-11-20, translated: "upgrade of spells, raise the strength and whatever else of the spells. Think of something cool." Four paths were shown. The owner chose three: Rank by use, now Rank by monster experience, plus Forms; Awakening in the endgame; Combos between spells. Not chosen: tradeable spell tomes. Strength: total spell power gain per character of 50% or more, knowing the endgame must be rebalanced and that a player without upgrades falls far behind.

Owner correction 2026-11-20, translated: "The spell upgrade is not by how much you use it. It is by how much experience you earn from monsters, or how many monsters you kill with each spell. To compensate, we raise the health of all monsters along the game." Section 1 and section 5 follow it. There is no experience per cast and no experience per hit.

## 0. The design in one page

- Every damage and heal spell has a **rank** 0 to 20. A rank grows with **Spell Points**, SP. SP come from the experience of monster kills, split between the spells by the damage each spell dealt to that monster. Nothing else gives SP.
- A rank gives damage or heal, shorter cooldown and lower mana cost. Rank 20 is about +25% spell power.
- At rank **10** and **20** the player picks a **Form** of the spell, one of two each. A Form changes how the spell plays: split, chain, ground, pull, delayed burst, element conversion, and more. Full Form tables for seven classes below, a template for the rest.
- At rank 20, in the endgame, up to **3 spells** per character can be **awakened** with Seals from pinnacle bosses, Greater Rift and waystone tiers XVI to XXV. An awakened spell has a new name, a new look and a signature effect.
- **Combos**: two spells inside 4 s give a bonus hit. Element reactions are free for everyone. Each class has signature combos that open at rank 5.
- Full upgrade is about **+51%** spell power: rank +25%, Forms +6%, awakening +9%, combos +5%, multiplied.
- The compensation is **monster health**, a curve by level: x1.02 at level 100, x1.20 at 1000, x1.38 at 2500. A typical player meets today's kill times. A player with no upgrades kills 17% slower at level 1000 and 27% slower at the cap.
- One storage block 7107000 to 7108099, one opcode 168, one DB table `chaos_spell_ranks` for the account echo. Build in 8 phases, about 37 working days.

## 1. Rank by monster experience

### 1.1 What counts

A rank belongs to a spell id of a character. Which spells have ranks:

- Every spell of the attack group and every heal spell, including the 21 line quest spells.
- Not in phase 1: buffs, shields, supports, conjures, minion spells. They are open question 2. Minion damage is credited to the spell that raised the minion, see 1.3.

SP are earned only from kills of monsters that pay experience. Not counted, each with its reason:

| Not counted | Reason |
|---|---|
| Training dummies and monsters flagged as trainers | they pay no experience, so no SP. The owner's rule, no extra cap needed |
| Players, PvP, arenas, battlegrounds, duels | PvP is not a source of power |
| Tester characters, storage 7102900 | the bots must not bend the curve. Staff command `/spellrank set` gives ranks for tests |
| Summons and clones of monsters | the same rule as the line spell quests |
| The tutorial | nothing to rank at level 1 to 8 |

Everything else that pays experience counts: hunts, rifts, dungeons, the tower, descent, waystone maps, bosses, event monsters.

### 1.2 The unit: Spell Points

One SP is one hour of on-level hunting at 100% damage share. Reference hour: the median experience per hour of the hunts a character of that level farms, from `progression_model.lua` before the stage factor.

For a kill the character receives base experience E from the engine. E is read in the experience callback of `pace.lua`, `onGainExperience` index -9, just after the pace curve and the multikill chain at -10 and before the stage, the boosts and the rested bonus. So boosts, stage and rested time do not buy rank. If the build finds that this order cannot be held, E is divided by the stage and boost factors read from the same layers. This is assumption A1, to be verified in phase 2.

```
K  = E / refXpPerHour(player level)          kill value in hours, about 1/1100 on level
SP = K x share of the spell
```

`refXpPerHour` is a table of points by level in `spell_ranks_config.lua`, generated from the progression model and held by `spell_upgrade_model.py --check`. It uses the player level, never the monster level. A level 1500 character killing level 700 monsters earns about a tenth, because those kills are worth little experience at level 1500. No extra rule against farming weak monsters is needed.

Clamp: K is at most 0.05 hours, 3 minutes, per kill. A boss that pays a huge kill cannot skip ranks. Bosses keep a large reward by giving many pieces of the share, not by one jump.

### 1.3 Who gets the share: damage share, not the kill blow

Chosen: **the share of the damage each spell dealt to that monster**, in the player's own damage. Reasons:

- The kill blow is gameable. A cheap spell fired last gets all SP, and the big spells that did the work get none.
- Damage over time, minions and area spells have no clear kill blow.
- The combat log already knows damage by spell. The server keeps one small table per monster, spell id to damage, at most 16 ids, dropped at death. No new engine patch.

Rules by case:

| Case | Credit |
|---|---|
| Direct hit | the spell id of the hit |
| Damage over time | the origin spell of the tick, the same flag `ChaosDot.run` already sets |
| Support extra hits, Echo, Fork, Breadth, Shatter, Deathburst, Surge, Reprisal | the spell they ride on |
| Form hits and combo hits | the spell that made them. A combo hit credits the second spell |
| Area spell | each monster it hits is a separate kill with its own table. Eight monsters hit make eight small shares. An area spell rewards packs, as its damage does |
| Auto attacks and weapon hits | in the denominator, they earn nothing. A player who mostly auto attacks levels spells slowly. That is correct |
| Minions and wolves | credited to the spell that raised them: Raise Bone Warrior, Bone Golem, Banner of Bones, Feral Command, Pack Howl. A companion with no command spell gives no credit, like an auto attack |
| Party kill | each member who got experience from the engine for that kill gets K from the experience the engine paid that member, split by that member's own spells. A member who dealt under 2% of the monster's health gets no SP, so no leeching |
| Healers | a pool of 20% of K goes to heal spells when a heal restored at least 1% of an ally's health inside the 10 s before the kill, effective heal only, split by effective healing. The ally's kill counts, the healer's own too. With no such heal, damage spells keep 100% |
| Heal pool in PvE only | healing in PvP counts nothing |

Per hour cap: **not needed.** SP follow the experience the engine already paces, so the speed is capped by the progression model. The one clamp is the 3 minute K above. A rank day limit would only punish a good hunter.

### 1.4 The curve

Cost of rank r in SP is `c x r^1.5`, with `c` set so that ranks 1 to 20 cost 42 SP in all. Costs per rank: 0.06, 0.16, 0.29, 0.44, 0.62, 0.81, 1.02, 1.25, 1.49, 1.75, 2.01, 2.29, 2.59, 2.89, 3.21, 3.53, 3.87, 4.22, 4.57, 4.94.

A spell in the main rotation of five spells has about 16% of the damage in a hunt, the rest is auto attacks and the other spells. At 16% share and the progression model's hours:

| Rank | Hunting hours from learning | Character level then |
|---|---|---|
| 5 | 9.7 | 311 |
| 10 | 49 | 659 |
| 15 | 130 | 1070 |
| 20 | 262 | 1738 |

Hours and kills a rank takes at the character level, for a main rotation spell. Kills are monsters killed with the spell at full credit, 1100 kills an hour on level.

| Character level | Rank in work | Hours for that rank | Kill equivalents |
|---|---|---|---|
| 100 | 2 | 1.0 | 170 |
| 500 | 8 | 7.8 | 1400 |
| 1000 | 15 | 20 | 3500 |
| 2000 | 20 | 31 | 5400 |

The target holds: a main rotation reaches rank 20 around level 1740, inside the owner's 1500 to 2000 window. The whole climb is 42 SP, which is 42 hours of full share, or about 46,000 monsters killed by the spell at full credit, or 262 hunting hours at 16%. These are hunting hours of the progression model. A hunting hour is about 1.6 clock hours, because of town, market and travel.

Spell weights. A spell has a share by its cooldown, so its need is scaled by what share it can reach. Cost multipliers `needScale`:

| Spell kind | needScale |
|---|---|
| Cooldown up to 8 s | 1.0 |
| Cooldown 9 to 13 s | 0.8 |
| Ultimate, cooldown 35 s and up | 0.35 |
| Heal spell | 0.7 |

A level 1200 ultimate with 6% share needs 15 SP to rank 20, about 245 hunting hours, level 2300 for a character that learns it at 1200. That is the ultimate's place.

Catch-up:

- A spell more than 4 ranks below the character's best spell of its weight earns SP x2. A spell learned late, or swapped into the rotation, catches up.
- The account echo, see 1.7.

### 1.5 What a rank gives

Damage and heal spells:

| Per rank | Damage spell | Heal spell |
|---|---|---|
| Power | +0.9% to the hit, +18% at rank 20 | +0.6% to the heal, +12% at 20 |
| Cooldown | -2% at ranks 4, 8, 12, 16, 20, -10% at 20 | -3% at the same ranks, -15% at 20 |
| Mana cost | -1% a rank, -20% at 20 | -1.25% a rank, -25% at 20 |
| Area | no change of shape. The shape art stays valid. Forms change the shape | none |

Counted power: damage +18% and cooldown -10% make about +25% spell power on a full rotation, because a 10% shorter cooldown gives about half of it in a rotation held by the 2 s group cooldown. Mana cost is comfort. It is not counted in the +50%.

Heals get less power on purpose. The monsters' damage to players does not rise, so a +25% heal would be a free survival gain. At +12% the survival model's pressure moves by at most 1 / 1.12, inside its limits.

Stacking with supports, masteries and quests, all multiplicative at the point named:

| Existing system | How rank stacks |
|---|---|
| Support runes, `chaos_supports_config.lua` | The rank factor is applied to the hit first. Brands, Fork, Echo and the other extra hits take their share of the ranked hit, so they grow with rank. No cap changes |
| Quickening and cooldown mods | The rank cooldown cut is a separate multiplier outside their cap, applied first. The floor of 1 s is applied last. The 2 s group cooldown is never touched |
| Thrift and mana mods | The rank mana cut multiplies. At most -20% rank and -30% Thrift, so 0.56 of the base cost at best. The `rotation_sim.py --mana` runway check reads it |
| Spell modifier masteries, O451 | Free support of the mastery works as before, on the ranked hit. A Form never replaces it |
| Line spell quests | The quest spells have ranks like any spell. Their done flag and relearning on class change are untouched |
| Spell scaling, O468 | The rank factor multiplies after the level, magic level and weapon skill inputs. A new test casts every spell at rank 20 and fails when a damage path ignores the factor, see 7 |

### 1.6 Retired spell, ascension change, reset

- **Retired spell.** SP and rank stay in storage under the id. A retired spell is not castable, so it does nothing. If a retired id is reused by a new spell, `spell_ranks_config.lua` `reassigned` lists the id with a version. At login a stored version below it clears the rank, SP, Forms, and refunds the Form change gold paid. The existing `patch_spell_ids` step has the list of ids.
- **Ascension or class change.** Ranks are per spell id, not per class. A spell shared by the old and new class keeps its rank and Forms. A spell the new class does not know is dormant, its rank is kept, and returns when the spell is learned again. This follows how `ChaosSpellQuest.sync` relearns quest spells. An awakened spell that is dormant frees its slot at once. The Seals spent are not returned. Awakening the slot again costs Seals again.
- **Reset.** The passive tree reset does not touch ranks. The tutorial reset clears the block 7107000 to 7108099. A Form can be changed for gold, see 2.4. There is no rank refund. Rank is earned play time.
- **Launch.** On the first login after the system is on, each known damage and heal spell gets 70% of the typical SP of the character's level, from the curve in 5.2. The wipe at launch makes this matter for test characters only. See open question 8.

### 1.7 New characters of an old account: the account echo

Without help a new character at level 500 meets monsters sized for rank 7 spells with rank 0 spells, 10% slower. Rule:

- The table `chaos_spell_ranks` keeps, per account and spell id, the best rank any character reached.
- A new or low character gets a **floor** on that spell: `min(10, floor(0.5 x best rank))`. It has the rank effects at once. SP continue from the floor's cost.
- Forms and awakening are not inherited. They are choices and play.
- With the floor, an alt is a little stronger than the curve at levels 100 to 400, at most 12%. That is accepted, alts level faster. The rank still has to be earned past 10.

## 2. Forms

### 2.1 The rule

At rank 10 the character picks Form I of the spell, one of two. At rank 20 the character picks Form II, one of two. The four Forms of a spell are fixed per spell id, so the table is a data file. A Form does not need the other one: four builds per spell.

A Form changes **how** the spell plays, not how strong it is. The budget, held by `spell_upgrade_model.py --check`, measured on `rotation_sim.py` variants like the masteries:

- gain per cast on one target between -5% and +8%
- gain on five targets between -5% and +12%
- the best Form of a spell at most +8% over no Form, in the situation it is for
- a Form under -3% on both counts must name a utility it gives: control, safety, mana
- a Form pair of a spell does not have a Form better on both counts than its twin

Counted power for the +50%: Form I +3%, Form II +3%, so +6% of a full rotation.

### 2.2 Form kinds

Numbers are the standard. A spell row can say a different number in `forms.csv`.

Form I, shape, rank 10:

| Kind | What it does |
|---|---|
| SPLIT | the hit becomes 3 hits of 45%, to the nearest enemies in 3 sqm, total 135% on three, 45% on one |
| CHAIN | the hit jumps to 2 more enemies within 3 sqm for 60% and 40% |
| PIERCE | a single target hit goes through, along the line, for 80% on each extra enemy. Range +1 |
| REND | the hit is 70%, the other 30% and 10% more is a damage over time for 4 s |
| DELAY | no hit now. A marked burst lands after 1.5 s for 170%, area 150%, with a telegraph circle |
| PULL | area spells: enemies in the area are pulled to 1 sqm of the centre, then the hit at 90% |
| GROUND | the area leaves ground for 4 s. Enemies in it take 15% of the hit a second |
| ECHO | area spells: a second hit at 55% after 1 s on the same place |
| SHIFT:E | the spell changes element to E, with a status of that element |

Form II, capstone, rank 20:

| Kind | What it does |
|---|---|
| TWIN | a second cast 0.4 s later at 70%, no extra mana, the cooldown starts after the second |
| CASCADE | a kill by the spell triggers a free hit of 50% on the nearest enemy, once per cast |
| AFTERMATH | when the spell ends, a burst or ground of 45% where it was |
| OVERCHARGE | 0.6 s of cast delay, with a telegraph, +60% |
| SIPHON | heals 4% of damage done, at most 5% of max health per cast, and returns 3% of damage as mana |
| SEEK | the spell chooses the best target by lowest health in range, and ignores the line of sight rule of the area |
| SPREAD | a damage over time or status of the spell jumps to 2 enemies in 3 sqm when it ends or on a kill |
| ASCEND:E | a second conversion: the spell changes to E, with a stronger status, 10% stronger hit |

Heal Form kinds, in the heal rows:

| Heal I | Effect | Heal II | Effect |
|---|---|---|---|
| RIPPLE | the heal jumps to 2 allies, 50% | SECOND WIND | a target under 40% health gets +40% and the cooldown is cut 25% |
| BLOOM | 20% less now, 40% more over 6 s | LINK | after 2 s a second heal of 40% if the target is under 50% |
| WARD | overheal becomes a shield, at most 10% of max health | SANCTUARY | a 5 s ground that heals 3% a second |
| PULSE | an area heal in 3 sqm at 70% | CLEANSE | removes one debuff and gives a 5% shield |

### 2.3 How Forms meet supports, masteries and elements

- **Supports and kind.** Sockets are legal by the spell's base kind. A Form never changes the kind, so no rune is lost when a Form is picked.
- **Hits of a Form.** Split, chain, pierce, ground, echo, twin, cascade and aftermath hits are hits of the spell for Brand, Sunder, Keen Edge and Hex. They never trigger Echo, Fork, Breadth, Shatter, Deathburst, Surge, Reprisal, Bloodthirst or Siphon. This is the guard the supports already use: ORIGIN_SPELL, proc guard, monsters only. The spell's own supports run once, on the first hit.
- **Masteries.** The free support of a mastery stays. The Form comes first, then the support.
- **Element rule, `check_spell_fx.py`.** A spell that sends an effect of another element is a CI failure. A Form that converts the element, SHIFT:E and ASCEND:E, sends effects of E only. `spell_fx_probe.lua` runs every Form of every spell, with the Form storage set, and the effect pass `chaos_fx_pass.lua` swaps the ids by the Form's element. Statuses of a conversion use the `sv_` status layer effects, tagged by element. A Form that adds ground uses the ground effects of its element. The conversion rows go in a new `spell_fx_forms.csv`, with the reason, like `spell_fx_allow.csv`. No Form may use an effect that has no tag.
- **O468.** A Form hit reads level and magic level like the spell. The input test runs each Form.
- **PvP.** Form shapes work in PvP. Their numbers count at the PvP factor of 5.2.

### 2.4 Choosing and changing

- The first pick of each Form is free, made in the spellbook.
- A change costs gold: `max(10 000, 150 x character level)`, paid from the bank first. At level 1000 it is 150,000 gold. A change made in the first 30 minutes after a pick is free, for a misclick.
- No token item in phase 1. Gold is the sink, like removing a rune. Open question 5.

### 2.5 Examples, seven classes

Notation: `Spell [element, shape] | Form I A / B | Form II A / B`. Elements and shapes are from `spelldata.lua`. SHIFT:E and ASCEND:E name the target element. Spells shared by two classes have one row. The same row is the table template for the other 14 classes: copy the spells of the class, pick two Form I and two Form II kinds by the shape, single target kinds for single spells, area kinds for area spells.

Shape guide for a new row: single target gets SPLIT, CHAIN, PIERCE, REND, DELAY. Area and around spells get PULL, GROUND, ECHO, SPLIT. Cast time spells get OVERCHARGE less often, they already wait. Ultimates get DELAY and CASCADE and AFTERMATH. A conversion needs an element the class already has effects for.

#### Elementalist, 13 attack spells

| Spell | Form I | Form II |
|---|---|---|
| Kindling Spark, shared with Illusionist | CHAIN / REND | TWIN / SPREAD |
| Rime Bloom [ice, around 1] | GROUND / ECHO | AFTERMATH / ASCEND:fire |
| Witchfire Bolt [fire, single] | SPLIT / SHIFT:ice | SPREAD / OVERCHARGE |
| Tempest Fan | PIERCE / PULL | SEEK / OVERCHARGE |
| Pyre Torrent | GROUND / REND | TWIN / SIPHON |
| Forked Storm [energy, circle 3] | CHAIN / GROUND | CASCADE / ASCEND:ice |
| Falling Pyre [fire, circle 1] | SPLIT / DELAY | AFTERMATH / ASCEND:ice |
| Crimson Covenant [death, single], shared with Illusionist | CHAIN / REND | SIPHON / SPREAD |
| Frozen Crypt [ice, circle 1] | PULL / GROUND | OVERCHARGE / ASCEND:death |
| Doomtide [fire, around 3, cast] | ECHO / PULL | AFTERMATH / ASCEND:death |
| Glacial Doom [ice, around 3, cast] | ECHO / GROUND | OVERCHARGE / ASCEND:fire |
| Prismatic Rupture [energy, circle 2], shared with Illusionist | SPLIT / DELAY | TWIN / ASCEND:weakest |
| Eclipse of Ruin [ice, circle 5, ultimate], shared with Illusionist | DELAY / ECHO | AFTERMATH / CASCADE |

ASCEND:weakest on Prismatic Rupture picks, at each cast, the element among fire, ice, energy, earth, holy and death the target resists least, and sends that element's effects. The probe runs all six.

#### Illusionist, 9 own attack spells and 5 heals

| Spell | Form I | Form II |
|---|---|---|
| Arcane Ripple | ECHO / CHAIN | TWIN / SPREAD |
| Bewitching Hex | CHAIN / DELAY | SPREAD / SIPHON |
| Shattered Psyche [death, single] | DELAY / CHAIN | OVERCHARGE / SIPHON |
| Phantom Needles [energy, single] | SPLIT / PIERCE | TWIN / SEEK |
| Mirror Shards [ice, around 1] | SPLIT / ECHO | AFTERMATH / CASCADE |
| Nightburst [death, around 1] | ECHO / GROUND | OVERCHARGE / ASCEND:fire |
| Dreamrot [death, single] | REND / CHAIN | SPREAD / SIPHON |
| Primordial Squall [earth, around 2] | GROUND / PULL | AFTERMATH / ASCEND:ice |
| Tear in the Weave [death, around 1] | PULL / DELAY | CASCADE / AFTERMATH |
| Minor Mending | RIPPLE / BLOOM | SECOND WIND / LINK |
| Purifying Wellspring | PULSE / BLOOM | SANCTUARY / CLEANSE |
| Mirror Mend | RIPPLE / WARD | LINK / SECOND WIND |
| Lucid Reverie | PULSE / WARD | SANCTUARY / LINK |
| Verdant Sanctuary | PULSE / BLOOM | SANCTUARY / CLEANSE |

Kindling Spark, Crimson Covenant, Prismatic Rupture and Eclipse of Ruin are in the Elementalist table.

#### Deadeye, 13 attack spells

| Spell | Form I | Form II |
|---|---|---|
| Phantom Javelin | PIERCE / CHAIN | TWIN / SEEK |
| Dawnpiercer [holy, single] | PIERCE / REND | OVERCHARGE / SIPHON |
| Snare Trap, shared with Ninja | GROUND / PULL | TWIN / CASCADE |
| Sanctum Burst | SPLIT / DELAY | AFTERMATH / SIPHON |
| Seeker Mine, shared with Ninja | ECHO / CHAIN | TWIN / CASCADE |
| Blessed Earth [holy, around 1] | GROUND / PULL | AFTERMATH / ASCEND:fire |
| Sunspear [holy, single] | PIERCE / DELAY | OVERCHARGE / SEEK |
| Final Verdict [holy, single] | DELAY / REND | OVERCHARGE / CASCADE |
| Gale Volley [physical, line 6] | SPLIT / PULL | TWIN / ASCEND:energy |
| Hail of Dawn [holy, single] | SPLIT / ECHO | AFTERMATH / SPREAD |
| Twin Verdict [holy, single] | CHAIN / DELAY | TWIN / SIPHON |
| Moonshard Rain [physical, circle 3] | GROUND / SPLIT | AFTERMATH / ASCEND:ice |
| Dawnbreaker Shot [holy, line 8, ultimate] | DELAY / SPLIT | CASCADE / OVERCHARGE |

#### Berserker, 13 attack spells

| Spell | Form I | Form II |
|---|---|---|
| Bonebreaker | CHAIN / REND | TWIN / SIPHON |
| Reaping Gyre [physical, around 1] | PULL / ECHO | AFTERMATH / CASCADE |
| Earthbreaker [physical, around 1] | GROUND / PULL | OVERCHARGE / ASCEND:earth |
| Scything Arc | SPLIT / ECHO | TWIN / SIPHON |
| Butcher's Gyre | PULL / REND | AFTERMATH / SPREAD |
| Gorehook [physical, single] | PULL / REND | CASCADE / SIPHON |
| Skyfall Cleave [physical, around 1] | DELAY / SPLIT | OVERCHARGE / AFTERMATH |
| Colossus Fall [physical, around 1, cast] | GROUND / PULL | AFTERMATH / ASCEND:fire |
| Headsman's Hurl | PIERCE / DELAY | SEEK / CASCADE |
| Bastion Cry [physical, wave 3] | PULL / ECHO | SIPHON / AFTERMATH |
| Rampage Leap [physical, circle 1] | SPLIT / PULL | TWIN / CASCADE |
| Keepfall [physical, circle 2] | GROUND / PULL | OVERCHARGE / ASCEND:ice |
| Judgment of Iron [physical, around 3, ultimate] | DELAY / ECHO | CASCADE / AFTERMATH |

#### Ninja, 11 own attack spells

| Spell | Form I | Form II |
|---|---|---|
| Shuriken Toss | SPLIT / CHAIN | TWIN / SEEK |
| Blade Flurry [around 1] | ECHO / PULL | CASCADE / SIPHON |
| Gutting Slash [physical, single] | REND / CHAIN | TWIN / SIPHON |
| Shadow Step [single, movement] | ECHO / REND | CASCADE / AFTERMATH |
| Razor Rain [physical, circle 2] | SPLIT / GROUND | AFTERMATH / TWIN |
| Venom Spiral [earth, single] | REND / SPLIT | SPREAD / ASCEND:death |
| Shuriken Barrage [circle 3] | SPLIT / ECHO | TWIN / CASCADE |
| Smoke Bomb [earth, around 1] | GROUND / PULL | AFTERMATH / ASCEND:death |
| Shuriken Tempest [circle 4] | GROUND / ECHO | OVERCHARGE / CASCADE |
| Eclipse Edge [physical, line 5] | PIERCE / DELAY | TWIN / SEEK |
| Death Between Heartbeats [physical, single, ultimate] | DELAY / REND | OVERCHARGE / CASCADE |

On Shadow Step, ECHO is a second step back to the start after 1.5 s, CASCADE is a free hit on the nearest enemy after a kill, no cooldown refund. Snare Trap and Seeker Mine are in the Deadeye table.

#### Iron Sage, 13 attack spells and its heal

| Spell | Form I | Form II |
|---|---|---|
| Ashen Fist | CHAIN / REND | TWIN / SIPHON |
| Sundering Palm | DELAY / REND | OVERCHARGE / SIPHON |
| Palm Shockwave [circle 2] | PULL / ECHO | AFTERMATH / SPREAD |
| Whirling Heel [physical, around 1] | PULL / ECHO | CASCADE / AFTERMATH |
| Hollow Knuckle [physical, single] | PIERCE / REND | TWIN / SEEK |
| Quaking Stomp [physical, around 1] | GROUND / PULL | AFTERMATH / OVERCHARGE |
| Iron Palm | DELAY / CHAIN | OVERCHARGE / SIPHON |
| Iron Chain [circle 2] | PULL / CHAIN | CASCADE / AFTERMATH |
| Cleaving Heel [physical, single] | SPLIT / CHAIN | TWIN / SPREAD |
| Tidal Palm [physical, wave 2] | PIERCE / PULL | AFTERMATH / ASCEND:ice |
| Mistborne Strike [physical, wave 3] | ECHO / PIERCE | SIPHON / ASCEND:ice |
| Thousand-Echo Palm [physical, wave 3] | SPLIT / ECHO | TWIN / CASCADE |
| Heaven's Ninth Gate [physical, single, ultimate] | DELAY / SPLIT | OVERCHARGE / CASCADE |
| Kindled Breath, heal | RIPPLE / BLOOM | SECOND WIND / SANCTUARY |

The Iron Sage's Chi Ward and Mantra of Stone are shield and aura spells, outside phase 1.

#### Lich, the chosen extra, 13 attack spells

| Spell | Form I | Form II |
|---|---|---|
| Bone Spear [physical, single] | PIERCE / SPLIT | TWIN / SIPHON |
| Withering Curse | REND / CHAIN | SPREAD / AFTERMATH |
| Marrow Bolt [death, single] | CHAIN / DELAY | OVERCHARGE / SEEK |
| Wraithwind [death, wave 3] | PIERCE / PULL | AFTERMATH / ASCEND:ice |
| Soul Rot [death, single] | REND / CHAIN | SPREAD / SIPHON |
| Gravewail [death, circle 2] | GROUND / ECHO | AFTERMATH / CASCADE |
| Life Siphon [death, single] | CHAIN / REND | TWIN / OVERCHARGE |
| Blightbrand [death, single] | DELAY / REND | SPREAD / CASCADE |
| Corpse Explosion [death, circle 3] | CHAIN / ECHO | CASCADE / AFTERMATH |
| Soulrend Beam [death, line 6] | SPLIT / PULL | OVERCHARGE / SIPHON |
| Splinter Volley [death, circle 1] | SPLIT / ECHO | TWIN / CASCADE |
| Soulflay Wave [death, wave 4] | PULL / PIERCE | SIPHON / AFTERMATH |
| Funeral of Kings [death, circle 5, ultimate] | DELAY / GROUND | CASCADE / AFTERMATH |

Corpse Explosion needs a corpse, so its Forms are measured by the probe with a corpse given. The probe already does this for it.

Count: 85 attack spell rows and 7 heal rows are written above, the rest of the 21 classes follow the template. A CI check, `tools/ci/check_spell_forms.py`, will hold that every attack and heal spell of every class has a `forms.csv` row, two Form I and two Form II, with a pt-BR name for each.

## 3. Awakening

### 3.1 What it is

At rank 20, with both Forms picked, a spell can be **awakened**. A character has 1 to 3 awakened spells: slot 1 and slot 2 and slot 3, each opened by the Seals of the table below. Any spell at rank 20 can be awakened. Phase 7 art is made in kits, see 3.4.

An awakened spell:

- has a **new name**, shown in the spellbook, the action bar and the chat: Doomtide becomes Cataclysm of Cinders
- has a **new look**, a new effect set in the element of the spell
- has +10% damage or heal, and a **signature effect** worth about +5% more, tuned to feel strong and to be mostly shape, control and safety, so the number stays modest: +3% of a class's damage each, +9% with three
- keeps its Forms, which still apply to its hits

### 3.2 Materials

Awakening material is a counter in storage, never an item: it cannot be traded or stolen. This keeps the chosen decision, no tradeable tomes. Three Seals:

| Seal | Source | Rate against the models |
|---|---|---|
| Waystone Seal | 1 for each cleared waystone map of tier XVI to XXV, +1 for the first clear of a tier | a clear is 15 minutes, `pinnacle_model.py`: 4.0 clears an hour, so 4 Seals an hour |
| Rift Seal | 1 for each Greater Rift run that ends at tier 16 or higher, +1 when the run climbs | a run is about 1200 s at the tier it reaches, `greater_rift_model.py`: 3 runs an hour, so 3 Seals an hour |
| Pinnacle Seal | 2 for each kill of an Ascended boss, for each member of the party | `pinnacle_model.py`: a set of fragments is 2.77 hours of top content, 0.36 kills an hour, so 0.72 Seals an hour |

Fragments for the pinnacle bosses come from the waystone maps of tier 12 and up, the rift of tier 15 and the Omen guardian, so one hour of tier XVI waystones feeds both the Waystone Seals and the fragments. Nothing is farmed twice.

| Awakening | Waystone | Rift | Pinnacle | Hours of ideal top content | With 1.4x real efficiency |
|---|---|---|---|---|---|
| 1st | 40 | 36 | 16 | 22 | 31 |
| 2nd | 70 | 60 | 28 | 37.5 | 52 |
| 3rd | 100 | 90 | 40 | 55 | 77 |
| All three | 210 | 186 | 84 | 114.5 | 160 |

Hours are `Waystone / 4 + Rift / 3`, the Pinnacle Seals come along at 0.72 an hour. The rates are re-read from the models by `spell_upgrade_model.py --check`: if the model's clear time moves 20%, the check fails and the cost is retuned.

The first awakening comes about 31 hours of tier XVI+ play after the content opens, level 1900 for the first pinnacle boss, so around level 2000 to 2100. The third comes about 160 hours later, at or near the cap of 2500, since the progression model gives about 100 hunting hours between levels 2000 and 2500 and top content pays experience too. The awakening is the cap content: it does not need extra levels, it needs time in the three endgame contents.

### 3.3 Examples

| Spell | Awakened name | New effect |
|---|---|---|
| Doomtide, Elementalist | Cataclysm of Cinders | after the wave a ring of fire stays 6 s and pulses 3 times for 40%. Each pulse that hits 3 or more enemies returns 3% mana |
| Final Verdict, Deadeye | Verdict Unbound | the shot becomes a line of 6 sqm that hits all, and marks each enemy hit for 6 s. A marked enemy takes the next Deadeye single target spell as a critical, once |
| Judgment of Iron, Berserker | Iron Reckoning | the quake sends 3 rings. Each kill in the next 8 s cuts 1 s of its cooldown, at most 5 s |
| Mirror Mend, Illusionist | Hall of Mends | the mirror heal reflects to every ally in 4 sqm at 50%, and each mirror gives a 4 s shield of 3% max health |

PvP: the signature effect of an awakened spell is off in PvP. The +10% follows the PvP factor.

### 3.4 Look pipeline

The effect pipeline of the repo: own art, drawn by code, like `gen_lightning_fx.py` and `gen_drawn_wings.py`, or our own art from the art tools. Never purchased pack pictures as input to any AI service. Per spell art would be too much, so the looks come in **kits**:

- one kit per element, 8 elements, times 5 shapes, single, circle, around, line, wave, so 40 effects of 10 to 12 frames, plus 8 projectile strips
- a spell takes the kit of its element and shape, with a tint and a new sigil ring. The name is the identity
- new effect ids are appended after the newest effect of the current pair, written by a new `client/tools/sprites/gen_awakened_fx.py` with its table, sums, `check` and `live` commands, the ids file `data/lib/chaos_awakened_fx_ids.lua`, and tags in `spell_fx_elements.csv`
- the server gate is `chaosClientPair >= N` for the pair that adds them. Until then an awakened spell plays the normal effects with the new name
- `check_spell_fx.py` probes the awakened version of each spell

## 4. Combos

### 4.1 The rule

A combo is a pair of spells cast inside a **window of 4 s**, on the same target or inside 2 sqm of the first spell's centre. The second spell's first hit gets the bonus. Order matters. The server never asks for a fixed sequence: a rotation that casts its five spells passes through some pairs by itself, and that is fine. A combo is a reward for what a good player does anyway.

Limits that keep it a reward and not a must-press rotation:

- at most one combo per cast
- the same combo does not fire on the same target again for 6 s
- a global pause of 1.2 s between combos of a player
- the bonus hits are extra hits: proc guard, ORIGIN_SPELL, monsters only
- the target of `spell_upgrade_model.py --check`: the best legal rotation gains at most +6% from combos, and the typical rotation +5%. If the model finds more, the numbers drop
- no combos in PvP

### 4.2 Which combos

Free for every class, element reactions, by the element of the two hits, the first then the second:

| Combo | Pair | Bonus |
|---|---|---|
| Steam Burst | ice then fire | a burst in 1 sqm of 15% of the second hit |
| Thermal Shock | fire then ice | the second hit on the target is +15%, and the target is brittle for 3 s |
| Overload | energy then fire | 15% of the second hit as energy to 3 enemies near |
| Pyre of the Dead | death then fire | enemies that die in the next 3 s burst for 20% of the second hit |
| Mudslide | earth then ice | the target is slowed 30% for 3 s, the second hit +10% |
| Consecrated Ash | fire then holy | the target takes 15% more holy for 3 s |

Signature combos, one to three per class line, open when both spells are at rank 5 or more. Nothing is paid.

| Combo | Pair | Bonus |
|---|---|---|
| Pinned Shot, Deadeye and Ranger | Snare Trap or Seeker Mine, then Final Verdict, Twin Verdict or Sunspear | the second hit is a guaranteed critical |
| Meat Grinder, Berserker | Gorehook, then Reaping Gyre, Butcher's Gyre or Earthbreaker | enemies the hook pulled take the area hit +25% |
| Anvil Chain, Iron Sage | Iron Chain, then Quaking Stomp | +25%, and the stomp stuns 0.5 s |
| Backstab, Ninja | Shadow Step, then Gutting Slash or Death Between Heartbeats | the second hit crits for +50% crit damage |
| Rotting Curse, Lich | Withering Curse, then Soul Rot, Blightbrand or Corpse Explosion | the curse bursts for 25% of the second hit |
| Psychic Shatter, Illusionist | Bewitching Hex, then Shattered Psyche or Dreamrot | the second hit +20%, and the hex time is renewed |
| Echoing Mend, Illusionist | Mirror Mend, then Lucid Reverie | the party's heal over time ticks +25% for 6 s |

Where the tree or supports open more: no support touches combos in phase 1, so a rune never adds a combo. A **combo mastery** can join the seven mastery nodes of O451 as an extra choice, for example window +1.5 s, or the repeat pause -2 s. The node list is at the cap of 7 choices, `maxMasteryChoices`, so this needs the same compatible change as O451 and waits for phase 6b.

### 4.3 Detection

- `ChaosSpellEvents` already gives a `cast` handler: `fn(player, name, id, group, aggressive, mana, health)`. A new handler `spellcombos` keeps a ring of the last four casts per player, spell id, time in ms, target id, position, and the element of the hit.
- A pure core, `spell_combos_core.lua`, takes the ring and the config rows and answers the combo id, or none. Tests `dofile` it on a mock.
- The cast event comes before the hit. The handler writes a pending combo for the player. The first damage event of the second spell, in the same place where `_supports.lua` runs its hit effects, reads and clears it, and runs the bonus with the proc guard. The bonus is a share of the ranked hit that was just dealt, so it grows with rank.
- The element of a hit is the one after a Form conversion. A Form that converts to ice opens the ice reactions.
- The pending combo expires after 1 s without a hit, for a spell that missed.

### 4.4 Client

- The server sends `combo {id, x, y, z}` on opcode 168. The client shows a short label over the target for 0.8 s, "Steam Burst", and plays a short sound. The label is drawn like the ground labels of O669, no new engine call.
- Sounds: two short chimes, made by a script in `client/tools`, synthesized like the region music of `gen_music.py`. No pack audio.
- The Codex gets a Combos page, generated from `spell_combos_config.lua` by the codex generator. Phase 6.

## 5. The +50% and the rebalance

### 5.1 How the total stacks

All factors multiply, spell power of a full rotation at full upgrade:

| Part | Gain | Where it comes from |
|---|---|---|
| Rank 20 | +24.6% | damage +18%, cooldown -10% worth +5.6% |
| Forms | +6.0% | Form I +3%, Form II +3% |
| Awakening | +9.0% | three spells, +3% of class damage each |
| Combos | +5.0% | the typical rotation |
| **Total** | **+51%** | 1.246 x 1.06 x 1.09 x 1.05 = 1.511 |

Without awakening, which is almost every player under level 1900, the total is +39%. That is the owner's "50% or more" at the cap, and the part of it that every player owns, rank and Forms, comes without end content.

These are spell power of the spell part of the damage. The class total is lower: auto attacks, weapons and pets are not ranked. The models use a spell share of 80% of a median class's damage, and each class its own, read from `class_dps_measured.csv`. So the class total at full upgrade is about +41%.

Where the power goes by role:

| Role | Rank 20 | Forms | Awakening | Combos |
|---|---|---|---|---|
| Damage | +18% hit, -10% cooldown | shape, +3% and +3% | +10% and a signature | +5% |
| Heal | +12% heal, -15% cooldown, -25% mana | shape, utility, +3% and +3% | +10% and a signature | echoing mends only |
| Shield, buffs, supports | none in phase 1 | none | none | none |

### 5.2 The PvP rule, owner question 1

Default proposal:

- rank and Form numbers count at **50%** in PvP, so the gap between a rank 0 and a rank 20 is at most +12% of power, not +25%
- Form shapes work as they are
- awakening signature effects are off, and combos are off
- the monsters' health curve does not touch players, so PvP is unchanged for everyone with the same rank
- the arena and the battleground ladders keep their rules

The alternative is to **normalise** the arena and the battleground to rank 10 for every character, for no gap at all. That is cleaner for ladders and removes the 50% rule from them, but a fair match then wastes ranks. It is open question 1.

### 5.3 The compensation: monster health by level

The owner's rule: raise the health of all monsters along the game, so that a typical player, with the typical rank at that level, meets the kill times of today.

Derivation, `spell_upgrade_model.py`. The rank of a main rotation spell at a level comes from the hunting hours of the progression model and the SP curve of section 1.4. The rotation's average rank is 0.88 of it, because spells join later, going to 1.0 at level 2500. Forms count 3% at average rank 10 and 3% more by 20. Combos count 5% from average rank 3 to 10. Awakening: 0 at level 1900, 1 spell at 2100, 1.5 at 2300, 2 at 2500, which is 3% each. Class share of the spell part: 0.80. The health factor is `H = 1 + 0.80 x (P - 1)`, where P is the spell power. The monster's health is multiplied by H, the player's damage by 1 + 0.80 x (P - 1) too, so the kill time stays today's.

| Level | Hunting hours in | Rank, main spell | P, spell power | H, monster health x |
|---|---|---|---|---|
| 100 | 1.1 | 1.8 | 1.019 | 1.02 |
| 200 | 3.8 | 3.2 | 1.035 | 1.03 |
| 300 | 9 | 4.8 | 1.071 | 1.06 |
| 400 | 15.8 | 6.2 | 1.095 | 1.08 |
| 500 | 24.7 | 7.4 | 1.119 | 1.10 |
| 600 | 38 | 9.0 | 1.147 | 1.12 |
| 700 | 57 | 10.6 | 1.189 | 1.15 |
| 800 | 76 | 12.0 | 1.211 | 1.17 |
| 1000 | 117 | 14.3 | 1.252 | 1.20 |
| 1300 | 176 | 17.0 | 1.284 | 1.23 |
| 1600 | 239 | 19.2 | 1.330 | 1.26 |
| 2000 | 307 | 20 | 1.365 | 1.29 |
| 2200 | 347 | 20 | 1.411 | 1.33 |
| 2500 | 406 | 20 | 1.469 | 1.38 |

Below level 100 the factor is 1.00. Between the rows it is linear, like the pace curves. The numbers live in `spell_ranks_config.lua` `health`, one curve, read by every system through `ChaosSpellRanks.healthFactor(level)`.

### 5.4 Where the factor goes

One place per system, the same function, the same curve. The level is the monster's hunting level for hunts, the planned level for fixed content.

| System | Change |
|---|---|
| Hunts and areas, `pace_config.lua` | the `health` curve x H at the hunting level. Experience and loot per kill are unchanged, so for a typical player kills an hour, experience an hour and loot an hour are the same |
| Dungeon monsters and bosses | the health percents of the dungeon difficulty x H at the dungeon level |
| Rift packs and guardians | x H at the level of the tier. `guardian_balance_config.lua` and `rift_config.lua` density |
| Infinity Tower | the floor health curves x H at the tier level, 800 in the model. `curveTol` already holds the gap |
| Ember Descent | the room pack and boss health x H at the planned levels 100, 500, 1000, 1500 |
| Waystone maps | tiers by their level band x H. Tiers XVI to XXV at level 2500: x1.38 over their own factors |
| Pinnacle bosses | health x H at 1900, 2100, 2300, 2500: 1.28, 1.31, 1.35, 1.38 |
| Greater Rift | the tier rule `health x1.06` a tier is unchanged. The tier 15 base health x 1.30 flat, since it serves levels 1500 to 2500. The reached tier stays about the same |
| Raid bosses, arena bosses, Malgrath, Omen guardians, the Cinderheart | health x H at the planned level, the lengths of `boss_length_model.py` stay: dungeon bosses 150 s, rift guardian 55 s, Omen guardian 5:18 |
| Players | no change. Monster damage is unchanged |

Pinnacle health with the factor:

| Boss | Level | Health now | Health with H |
|---|---|---|---|
| Ascended Malgrath | 1900 | 3,475,000 | 4,448,000 |
| Ascended Vhoss | 2100 | 3,876,000 | 5,078,000 |
| Ascended Talath | 2300 | 4,231,000 | 5,712,000 |
| Ascended Varkhul | 2500 | 4,587,000 | 6,330,000 |

### 5.5 How each model moves

One new source, `spell_upgrade_model.py`, holds the rank curve, P and H, and the limits. Its `--check` runs in CI with a test. Each other model reads it.

| Model | Change |
|---|---|
| `class_dps_model.py` | a new step `ranks`: each class's spell damage x P(level), by its own spell share. The limit of +-25% of the median stays. A class with a low spell share loses ground, and the check says which |
| `pack_model.py` | health x H, kills an hour of the median class do not change. `--check` of `packLimits` and the late pack 3x rule keep their limits |
| `boss_model.py`, `boss_length_model.py` | typical damage x P, health x H. The planned seconds stay |
| `tower_model.py` | damage x P, floor curves x H, `curveTol` re-fitted |
| `guardian_model.py` | health x H. Damage to players unchanged. The healing term x the heal gain, so pressure falls by at most 1/1.12 on healers. `warn` and `hitCap` are not touched |
| `survival_model.py` | healing x heal gain. The `sust` limits are re-fitted, the slack is the heal gain only |
| `pvp_model.py` | damage and healing x the PvP factor, the same for every class. Duel results at 100, 500, 1000 do not move |
| `descent_model.py` | health x H, damage x P at the planned levels |
| `waystone_endgame_model.py` | health x H at level 2500, plain run clear time against the hunt stays |
| `pinnacle_model.py` | health x H, typical damage x P, so the kill times, 420 s alone and 300 s with five, stay. Fragments an hour is unchanged |
| `greater_rift_model.py` | tier 15 health x 1.30, so the reached tier at 1500, 2000, 2500, 36, 42, 46, stays within 1 |
| `progression_model.lua` | no change for the typical player. A new line `--no-upgrades` prints minutes per level x H |
| `spell_mastery_model.py` | masteries are on the ranked hit. Their +15% class cap stays |
| `rotation_sim.py` | a rank per spell, for the best sets. A new `--ranks` flag |

CI: `spell_upgrade_model.py --check` fails when a committed curve is not the derivation, or when a model's kill time for the typical player moves more than 3% from today.

### 5.6 What a player without upgrades feels

A character with no ranks, no Forms, no combos and no awakening meets the monsters sized for the typical player. Experience an hour falls to 1 / H:

| Level | Experience an hour | Boss kill time |
|---|---|---|
| 100 | -2% | x1.02 |
| 500 | -9% | x1.10 |
| 1000 | -17% | x1.20 |
| 2000 | -23% | x1.29 |
| 2500 | -27% | x1.38 |

Hours to reach a level: level 500, 27 against 26, +6%. Level 1000, 135 against 118, +14%. Level 1500, 259 against 220, +18%. Level 2000, 373 against 309, +21%. About +24% to the cap.

A median class with no upgrades kills Ascended Varkhul alone in about 580 s. The limit of the weakest class is 566 s. So the pinnacle bosses solo need about rank 12 on the main rotation. With a party of five it is fine. This is the owner's "a player without upgrades falls far behind", and it is paid back by the speed of the climb: ranks come by killing, not by a chore. A player who kills falls behind only if he does not use spells.

New characters of an old account: the account echo of 1.7 gives them a floor of rank 10 on spells the account maxed. At level 500 the alt has about the typical power, so the factor does not block it. Forms and awakening are earned again.

Existing characters at the switch: see the launch grant in 1.6.

## 6. UI

Spellbook, `game_spellbook`, is the home. No new window, so no new hub card:

- each spell row gets a rank number and a thin bar of SP to the next rank, with a number as a tooltip
- the spell detail gets a tab **Upgrades**: the 20 ranks as a strip, what the next rank gives, the SP and kills to go, and an estimate of hours at the character's recent pace
- the Form block: two buttons at rank 10, two at rank 20, with name, text and a note of the cost of a change. A locked Form shows the rank it opens at
- the **Awakening** tab, visible from level 1500: three slots, the Seals as three counters with the cost of the next awakening, and a preview of the awakened name and look
- a **Combos** tab: the combos known, discovered by doing them, with the pair and the bonus. Undiscovered show a question mark
- the action bar shows a small pip for the rank of the spell on the slot, optional in options
- a label and a sound for a combo, see 4.4
- the hub: a badge on the Spellbook card when a Form can be picked or an awakening is paid. The badge mechanism of `topbar_hub.lua` is used, so `check_topbar_tree.py` and `check_topbar_widgets.py` pass without a new card

pt-BR: every tr() key of the new module and every name needs pt-BR, `check_locales.py`. Names needed: 9 Form I kinds, 8 Form II kinds, 8 heal kinds, 85 + 7 spell rows x 4 Form names built from the kind and the spell word, with overrides, the awakened names, the combos' names and texts, the seals. Numbers use `ChaosLocale`, 1.234.567. The server texts that carry names go through `i18n_strings.lua` and the player's language storage. The generated client data file `forms_data.lua` holds the English names, and `pt_br.lua` the translation.

Unity is out of scope. `check_unity_opcodes.py` gets an allowlist line for opcode 168 with the reason.

## 7. Data and files

### 7.1 Storage block

Free block: **7107000 to 7108099** in the 7100000 to 7127999 range. Checked against the table of "Storage keys": the neighbours are 7106400 to 7106459, pinnacle bosses, and 7109990, supports. Name `Chaos.storage.spellRanks`, config key `storage`.

| Key | Meaning |
|---|---|
| +0 .. +499 | the packed state of the spell with that id: bits 0-4 rank, 5-6 Form I pick, 7-8 Form II pick, 9 awakened. The spell scripts state reads these, like the masteries' 7109993 |
| +500 | version of the block |
| +501 | awakened spells held, 0 to 3 |
| +502 | Form changes made |
| +503 | the last launch grant version |
| +510 | Waystone Seals held |
| +511 | Rift Seals held |
| +512 | Pinnacle Seals held |
| +520 .. +529 | awakened spell ids by slot, 3 used |
| +600 .. +1099 | SP in hundredths of an SP for the spell with that id |

Spell ids are below 500, the supports block already holds that range. A test checks the largest id.

### 7.2 DB table

`server/sql/chaos_spell_ranks.sql`:

```
chaos_spell_ranks(account_id INT, spell_id SMALLINT, best_rank TINYINT,
  updated_at INT, PRIMARY KEY (account_id, spell_id))
```

It holds the best rank per account and spell, for the echo. It is written when a rank rises, read at login. It is also the base of a later ladder. A wipe policy line is added to `launch_wipe` like the other `chaos_*` tables, see the wipe tool's table policy test.

### 7.3 Opcode

**168**, `ChaosOpcodes.spellRanks`. Checked: it is not in the base server's list, not a base client `ExtendedIds`, not a value in `ChaosOpcodes`, not registered by a client module. 172 is not free, it was the card border. The build repeats the collision check of README "Opcode collision check", and adds the number there. Payloads over 8192 bytes go through `Chaos.sendChunked`. Messages: `state` the packed ranks and SP, `rank` one spell changed, `pick` a Form, `awaken`, `combo`, and from the client `open`, `pick`, `awaken`.

### 7.4 Files, core, config, engine

Server, `data/scripts/chaos/`:

| File | Role |
|---|---|
| `spell_ranks_core.lua` | pure: SP maths, cost curve, weights, credit split, factors, the echo floor, the health factor. Unit tested |
| `spell_ranks_config.lua` | numbers: the curve, weights, rank gains per role, PvP factor, `health` curve, `refXpPerHour` points, `reassigned`, prices, storage |
| `spell_ranks.lua` | engine: damage table per monster, the experience callback, death credit, storage IO, login sync, opcode 168, the `/spellrank` talkaction for staff |
| `spell_forms_core.lua`, `spell_forms.lua` | Form kinds as pure rules, and the hit hooks |
| `spell_awakening_core.lua`, `spell_awakening_config.lua`, `spell_awakening.lua` | Seals, costs, slots, awakened names, signature effects |
| `spell_combos_core.lua`, `spell_combos_config.lua`, `spell_combos.lua` | the ring, the rows, the detect and the bonus |

Data and lib:

- `data/lib/chaos_spell_ranks.lua`: the read API for the spell scripts state, `ChaosSpellRanks.factor(player, spellId)`, reading storage as the masteries do
- `data/spells/forms.csv`: one row per spell id and Form, with the kind and the overrides
- `data/spells/spell_fx_forms.csv`: element conversions with reasons
- `data/lib/chaos_awakened_fx_ids.lua`

Hooks, where the factor is read. These are the paths of the O468 table: `AttackKit.rawValues`, `ChaosSpell.weaponStrike`, `ChaosSpell.weaponFormula`, `MonkSpell.strike`, `MonkSpell.values`, `MonkSpell.rawValues`, the Kindled Breath and Mantra of Stone heals, the wolf and companion bite helpers, snares and mines at placement. Plus `chaos_supports.lua` `spellEffects` for the Form hit share, and `_supports.lua` for the cooldown and cost handlers on `ChaosSpellEvents`. Plus `pace.lua` and each content system for the health factor.

Tools and checks:

- `server/tools/spell_upgrade_model.py` and `_test.py`, with `--check`, `--table`, `--derive`, `--no-upgrades`
- `tools/ci/check_spell_forms.py` and `_test.py`
- `tests/spell_ranks_test.lua`, `spell_forms_test.lua`, `spell_combos_test.lua`, `spell_awakening_test.lua`
- `tests/spell_ranks_paths_test.lua`: like the part B of O468, it casts every damage and heal spell at rank 20 on the mock engine and fails when a path ignores the factor. `spell_inputs_test.lua` keeps passing, since rank 0 is a factor of 1
- `check_spell_fx.py` and `spell_fx_probe.lua` run the Forms and awakened looks
- `pace_test.lua`, `monster_health_curve_test.lua` read the health factor

Client: `client/overlay/modules/game_spellranks/`, `.otmod`, `.otui`, `spellranks.lua`, pure `ranklogic.lua`, `ranklogic_test.lua`, the spellbook tab, generated `forms_data.lua` from a new `server/tools/gen_forms_data.lua` with `--check`, `pt_br.lua` keys, `check_modules.py`, `check_window_close.py` and the mobile layout rules.

Docs to keep in sync at build: `ROADMAP.md`, a new `server/README.md` section "Spell upgrades (O686)", `client/MANIFEST.md`, `docs/CLASSES.md` for the Forms, `server/data/spells/README.md` for the model numbers, `docs/CREDITS.md` only if a third party asset joins.

The tester bots are not touched here. When the system is built, a bot helper and a `spell_ranks` system check go to the tester work: staff-set ranks, a Form pick, an awakening, a combo.

## 8. Phases and estimates

Working days of one agent session each, with tests and docs. Total about 37 days.

| Phase | Work | Days |
|---|---|---|
| 1 | This design, owner review | done |
| 2 | Rank core: SP credit at death, the per monster damage table, the experience callback, storage, the factor in every O468 path, cooldown and cost handlers, login, echo table and SQL, launch grant, `/spellrank`. Switched off by `enabled = false`. Tests and the path test | 6 |
| 3 | `spell_upgrade_model.py`, the health curve and the factor in `pace`, dungeons, rifts, tower, descent, waystones, pinnacle, greater rift, raid, with each model's step and test. Switched with phase 2 | 6 |
| 4 | Forms: 8 + 8 + 8 kinds in the engine, the table for all 21 classes, `check_spell_forms.py`, probe per Form, `spell_fx_forms.csv`, the model band check | 9 |
| 5 | Client: opcode 168, spellbook tabs, Form picker, rank bars, pt-BR, hub badge, tests, mobile layout | 5 |
| 6 | Combos: core, config, the hit hook, label and sounds, Codex page, 6b combo masteries | 4 |
| 7 | Awakening: Seals from the three contents, costs, slots, signature effects, the kit art tool, UI tab | 6 |
| 8 | Live pass: the tester bots climb ranks, kill times against the models, tune the curve and H, wipe policy, docs | 3 |

Phases 2 and 3 ship together, dark. Phase 4 and 5 can overlap. The health factor and the rank gain go live in the same release, never one without the other.

## 9. Open questions for the owner

1. **PvP.** Ranks and Form numbers at 50% in PvP, awakening effects and combos off, as the default. Or the arena and the battleground normalise every character to rank 10. Or full power in PvP.
2. **Buffs, shields, summons and conjures.** Rank them in a later phase, default, or never. Their share and credit rule would be new.
3. **Rank experience source.** Default: base experience before the stage, boosts and rested bonus, so a boost does not buy rank. Or all experience, so a boost also speeds ranks.
4. **Account echo.** Alts start at half the best rank, at most 10. Yes or no, and the size.
5. **Form change price.** Gold, `max(10 000, 150 x level)`, first 30 minutes free. Or a token item as well.
6. **Awakenable spells.** Any spell at rank 20, default, or a fixed list of five per class so the art and the balance are smaller.
7. **Where the health factor starts.** Default from level 100, factor 1.02. Or from 300, so low levels are not touched at all.
8. **Existing characters at the switch.** 70% of the typical SP as a grant, default, or everyone starts at zero since the launch wipe is near.
9. **Heal gain.** Heals get +12% at rank 20 on purpose. Is that enough, or should healers have the same +18% and the monsters' damage rise to match.
10. **The 3 minute clamp on a kill.** A boss then gives a small share of rank. Keep, or let bosses give a rank bonus.
