# Build guide: the archetypes (2026-10)

The owner asked for the most played build styles of the genre to be possible here, at least two per class line.
This page lists them in our own words. Each one is playable with the base class. Each one fits one ascended class best.

Numbers live in code. Keystones and uniques: `server/data/scripts/chaos/archetypes_config.lua`. Rules:
`archetypes_core.lua`, tested by `server/tests/archetypes_test.lua`. Engine glue: `archetypes.lua`.
Computed damage at levels 300 and 1000: `server/data/spells/README.md` "Build archetypes". Those numbers are
computed, not measured in game. Server details: `server/README.md` "Build archetypes".

A second round (2026-10-12) added the three families left out at first: snares (traps and mines), vigils (auras
that reserve mana) and a build that lives on its energy shield alone. Their numbers: `snares_config.lua`,
`vigils_config.lua` and `archetypes_config.lua` `arHollowVessel`. Computed numbers: `server/data/spells/README.md`
"Snares, vigils and Hollow Vessel". Server details: `server/README.md` "Snares" and "Vigils".

## The new keystones

Sixteen small leaves of the main tree became keystones: twelve in the first round, four in the second. No node moved
and no link changed. Whoever held one of those leaves gets it refunded once, for free, at the next login. Build codes
older than format 4 leave the first twelve out, codes older than format 5 the last four. Every keystone has a price.

| Keystone | Node | Who may take it | What it does | Price | Unique that pushes it |
|---|---|---|---|---|---|
| Pyre Oath | 108 | Warrior and Templar lines | in a fight, enemies within 2 sqm take 4% of your maximum health as fire damage each second; you burn for 2.5% of it a second and regenerate 2% | your other damage -25% | Pyreheart Mantle: aura +20% |
| Sanguine Covenant | 81 | every class | every hit leeches 5% as health, at most 6% of your maximum health a second | healing you receive -30% | Vein of the Unsated: +1% leech, +3% cap |
| Thornbound Oath | 77 | every class | hits taken reflect 20% of what landed, plus your item Reflect Damage once more; a third against players, half against bosses with a cap | your damage -10% | Spitethorn Bulwark: +10% reflect |
| Open Hand Creed | 109 | every line but the Monk's | with no weapon in hand, fists hit with the Monk's fist attack and your best melee skill, +36% (was +10%); strike spells that read the weapon use it too, but the Thief line's keep their weapon attack | none; you hold no weapon | Knuckles of the Unbound: works at 80% of the old +10% without the keystone, +10% more with it |
| Contagion Rite | 107 | Thief line | a monster that dies poisoned by you passes the poison to 3 more within 2 sqm, up to 4 steps deep | weapon hits -10% | Rotbloom Phial: one more target, one step deeper |
| Cascade Edge | 78 | every class | a critical hit bursts on the other enemies within 1 sqm of the target for 60% of the hit, in your strongest tree element; once per 0.8 s | non-critical hits -5% | Splintered Instant: +25% burst, 0.2 s sooner |
| Stormstring | 82 | Ranger line | bow and crossbow hits arc to 3 other enemies within 3 sqm for 40% as energy | the main hit -10% | Stormcaller Recurve: one more arc; alone, one arc of 25% |
| Winter's Lattice | 355 | Mystic and Necromancer lines | a monster that dies within 2 s of your ice hit shatters for 5% (was 6%) of its maximum health on enemies within 2 sqm; kills chain | fire and energy damage -30% | Shard of the Long Winter: +2%, +1 sqm |
| Effigy Covenant | 262 | Mystic and Necromancer lines | an area attack spell raises a Cinder Effigy on your tile; it repeats that cast every 2 s for 24% of its average hit, at most 2, for 12 s | your spells -25% | Effigy Carver's Idol: a third effigy |
| Sigil of Cinders | 106 | Mystic and Templar lines | fire and holy spell hits ignite; a one-target spell brands the target, the brand burns its neighbours every second and jumps when the bearer dies; burns spread on death | damage that is not fire or holy -20% | Brand of the Ashen Choir: brand +25% |
| Aether Edge | 362 | Monk and Templar lines | weapon and fist hits add 33% (was 6%) of your current energy shield as energy damage; 6% when you also hold Hollow Vessel | maximum health -20% | Aetherbound Plate: +4% of the shield |
| Reliquary Vow | 253 | Templar line | a Reliquary Warden follows you; every 2 s it heals the party around it, gives the others +5% damage and burns enemies with holy damage | your own damage -10% | Reliquary Censer: pulses +25% |
| Snarewright's Creed | 105 | Ranger and Thief lines | 2 more traps and 3 more mines may be out; they arm in half the time and hit 25% harder | your other hits (weapon, spells; not damage over time) -15% | Snarewalker Greaves: +1 trap, armed 0.3 s sooner, +10%. Fusewright's Charm: +2 mines, +10%, a 4 s longer fuse. Both work without it |
| Covenant of Vigils | 99 | Mystic, Necromancer and Templar lines | vigils reserve 30% less, reach 3 sqm farther and give the party 20% more of every effect | your own damage -10% | Choirmaster's Circlet: reservation -15%. Oathkeeper's Standard: -10% and 2 sqm farther |
| Iron Tithe | 102 | Warrior, Monk and Templar lines | vigils reserve maximum health instead of mana, at 60% of their share, and work 50% stronger on you | they cover you alone; no effect next to Hollow Vessel | the vigil uniques above |
| Hollow Vessel | 96 | Mystic, Necromancer, Monk and Templar lines | maximum health is 100; energy shield: the items' +50%, plus 110% of the health given up (the full health, the tree's percent included; half of it with Aether Edge, the Hollow Palm); it recharges 15% of its maximum a second faster and starts 1 s after a hit; no poison and no life drain hurt you | heals, potions, leech and regeneration fill only the 100 health; the pool is 11% to 17% bigger than health and shield before (measured), and it only comes back by recharge | Stillheart Robe: the items' shield +40% more. Hollowglass Diadem: recharge +10% a second and the 1 s start, also without it |

Open Hand Creed and weapon keystones. With no weapon in the hands, a keystone that acts on a weapon's hits gives
nothing. The Ranger line's Longshot, Barbed Quiver, Opening Shot, Hobbling Shot and Stormstring read a bow, crossbow or
thrown weapon hit, and a fist is none. The tooltips do not say so.

All chain reactions share one work budget: 24 spreads a server tick, 40 per chain, a queue of 200. A packed
screen cannot stall the game loop. See `server/README.md` "Game loop stalls" for the numbers behind it. The snares
have the same kind of budget (below).

## Snares: traps and mines

Three spells for the Ranger and Thief lines. A snare is a spot on the map that the server remembers. Nothing is put on
the tile, so nothing can be picked up and nothing is saved.

| Spell | Words | Level | What it does |
|---|---|---|---|
| Snare Trap | `drai snar` | 40 | throws a trap up to 4 sqm, onto your target or straight ahead; it arms after 0.6 s; the first monster within 1 sqm sets it off; the burst hits up to 8 enemies within 2 sqm. At most 3; a trap lasts 20 s |
| Seeker Mine | `kah snar` | 60 | throws a mine the same way; it arms after 0.8 s and waits for Detonate Mines or its 8 s fuse; its burst is 1.15 times a trap's. At most 5 |
| Detonate Mines | `vok snar` | 60 | every armed mine of yours goes off, 0.1 s apart. Ranger and Deadeye hold both mines again since O455, the Beastmaster as extras; the Mine-layer numbers predate the spell cap |

- **The element.** Say it after the words: `drai snar "fire"`. Fire burns, ice slows by 40%, energy reaches 1 sqm
  farther at 85% of the hit, earth poisons, death drains 4% of the damage as health, holy heals you and party
  members near the snare by 2% of their health, physical hits 15% harder. The choice is remembered. Without one, a
  brand rune socketed in the spell picks it (Emberbrand fire, Rimebrand ice, Dawnbrand holy, Gravebrand death,
  Stormbrand energy). Otherwise physical.
- **The hit** scales with your best of bow, blade or shuriken power and your level. It is about one and a half
  Skewering Line hits: a snare costs a cast and waits for a monster. Halved on 2026-10-13 after the in-game measure;
  the new rows are computed (`server/data/spells/README.md` "Snares, vigils and Hollow Vessel").
- **Gone** when you log out, die, change floor, walk 30 sqm away or step into a protection zone. Only monsters set
  them off and only monsters are hit, never players.
- **The game loop.** One scheduler looks at 60 snares every 0.2 s and fires at most 16 bursts. All players together
  may have 400 snares out. A full screen of snares costs about 2 ms a tick at most.
- **Measured in game (2026-10-13), before the halving.** The snares hit much harder than computed: a Ranger or Deadeye
  snare build dealt 40-90% more than its computed row and passed the Elementalist in area at both levels, even
  against a moving pack (a third less). On one target the Mine-layer Deadeye passed the Deadeye's own build. The
  Thief, Ninja and Beastmaster rows stayed below the leaders. The hit was then halved (applied, owner approved).
  Measured again after it: the Mine-layer Deadeye 1046 / 3372 at level 300 and the Mine-layer Ranger 3252 / 10536 at
  level 1000 (one / five targets), just under the leaders. `server/data/spells/README.md` "Snares, vigils and Hollow
  Vessel measured in game". Caps, arming, the element and the DPS meter names work as written.

## Vigils: auras that reserve mana

Four spells for every class. Each one switches its vigil on or off. While a vigil is on it reserves a share of your
maximum mana: your maximum mana is that much lower, so reserved mana cannot be spent, not by spells, not by the mana
shield, not by the Trials' Mana Ward. A vigil covers you and your party members within 5 sqm on your floor. It stays
on through logout and death until you switch it off.

| Spell | Words | Level | Reserves | Effect on everyone covered |
|---|---|---|---|---|
| Vigil of Wrath | `vigh vyr` | 60 | 35% | +5% damage. Not on top of Inspiring Illusion: the stronger counts |
| Vigil of Iron | `vigh tor` | 60 | 35% | -6% damage taken. Not on top of the Templar line's defence aura: the stronger counts |
| Vigil of Haste | `vigh ruan` | 40 | 20% | +15% speed |
| Vigil of Clarity | `vigh lum` | 40 | 20% | 1% of the maximum mana back every second. Nothing in a rift with Parched Veins |

All four together reserve 110%, so they do not fit without help. Covenant of Vigils takes them to 77%; with the
Choirmaster's Circlet to 65%. Two holders' vigils of one kind do not add up: the strongest counts. A vigil that no
longer fits (a unique taken off) is switched off, the last one first, with a message.
Every vigil that covers you shows on the buff bar with its effect in percent, and says whether it is yours or a party
member's. With Iron Tithe an "Iron Tithe" entry shows the health your vigils reserve.

Measured in game (2026-10-13): every reservation, effect and range above is exact (35 / 70 / 90%, Clarity refused at
110%; Covenant 77%, with the Circlet 65%; Iron Tithe 21% + 12% of the health, Wrath +7.5%, Iron -9%, Haste +22%; the
party +5% / +6% with Covenant, out of range at 6 / 9 sqm). One bug was found: Vigil of Wrath works only on a monster
that carries the archetypes' hit event, and no spawned monster got it, so a holder or party member without an
archetype keystone or unique got no +5%. Fixed 2026-10-13 (applied, owner approved): every monster gets the event at
spawn; measured again, +5.0%. `server/data/spells/README.md` "Snares, vigils and Hollow Vessel measured in game".

## Hollow Vessel: a life on the energy shield

The keystone sets your maximum health to 100 and gives you a large energy shield that comes back fast. Health
regeneration, heals, potions and leech fill only those 100 points. Poison and life drain cannot hurt you.

- **The shield**: the items' maximum (the three energy shield modifiers) +50%, plus half of the health you give up.
  An Elementalist at level 300 (1,974 health, items 740) gets 2,047 shield; at level 1000 about 5,400.
- **The recharge**: 35% of the maximum a second instead of 20%, and it starts 1 s after a hit instead of 2 s.
- **The price**: the pool is smaller (an Elementalist 2,147 against 2,714 at level 300; a Templar line class about
  -36%). One hit that breaks the shield kills. A login starts with an empty shield, as for everyone.
- **With our other rules**: health leech and Sanguine Covenant have nothing to fill; Pyre Oath's aura and burn and
  Thornbound Oath's cap read the 100 health, so they do not suit it. The mana shield and the Trials' Mana Ward still
  come first and work as before. The percent-of-health hits of the rifts (Scorched Earth, Rimefloor, Veilstorm, the
  Wrathful Guardian's nova), the raid, the Ascended Omens and the guild boss count your health plus your maximum
  shield. Festering Wounds is poison: no effect. The
  hexes (Searing, Flaying, Sapping) work as on anyone. Parched Veins does not touch the shield. Iron Tithe has no
  effect next to it.
- **Measured in game (2026-10-13).** Shield sizes within 3% of the numbers above, health 100, recharge 35% a second
  (45% with the Diadem) from about 1 s after a hit, full again 2.75-4.75 s after a break; poison and life drain do
  nothing; a rift percent hit takes 10% of health + maximum shield. Against one monster hitting every 2 s the shield
  never breaks; against two (a hit every second) it never starts its recharge, and the character dies as fast as
  without the keystone. At level 1000 the pool is 51-56% smaller for the Lich, the Shadowfist and the Inquisitor, more
  than the 20-40% above (flag, not applied). The base items' equip rules kept the Robe at level 400 and the Diadem off
  the Elementalist; fixed 2026-10-13 (applied, the uniques' own equip rules): measured again, an Elementalist at level
  300 wears both, shield 2,343, recharge 45%. The Hollow Palm with the Plate passes the Deadeye at level 1000 (5,342
  against 4,670-4,685; strong, kept as it is by the owner on 2026-11-09, not recommended by default). `server/data/spells/README.md` "Snares, vigils and Hollow Vessel measured
  in game".

## The archetypes per class line

Two or more per line. "New" marks an archetype these keystones made possible. The others already worked.

Since 2026-10-12 two main tree keystones have a Monk and a Templar class: the Iron Sage may take **Overgrowth** on
the Wrath keystone (621: heals on others heal 10% more over 6 s) and the Sentinel **Thorns** on the Resolve keystone
(624: melee and ranged attackers take 30% of their hit + 2 x magic level back as earth damage). Each is about 25
points from the start, so it suits a build of level 300 or more. Computed, not measured
(`server/data/spells/README.md` "Overgrowth and Thorns for the Iron Sage and the Sentinel"): Overgrowth +8-9% healing
for the Iron Sage, the Illusionist still 10-28% ahead; Thorns about 330 earth back per 750 hit at level 300 (magic
level 25), 816 per 2000 hit at level 1000 (magic level 40), still far below the damage classes in area.

| Archetype | Line | Class to aim for | Core: keystones, items, spells | Play style | Strengths | Weaknesses | Gear checkpoints |
|---|---|---|---|---|---|---|---|
| **Pyre Walker** (new) | Warrior | Juggernaut; Warrior works | Pyre Oath, Immovable, Bulwark; Pyreheart Mantle; Iron Bellow to pull packs in, Earthbreaker | walk into a pack and stand there; the aura does the killing | clears packs with no clicks; very tough | weak on one target; needs fire absorbs and regeneration | 300: fire absorb 40%+, Health Regeneration mods, vitality nodes. 1000: the Mantle, fire absorb 60%+ |
| **Bloodsworn Reaver** (new) | Warrior | Berserker | Sanguine Covenant, Undying Rage, Cleaving Arc; Vein of the Unsated; Skyfall Cleave, Bloodrage | two-handed cleaves that feed on every hit | sustain grows with the pack; no potions needed | heals from others are 30% weaker; leech cap per second | 300: a two-hander, life leech items. 1000: the Vein, Health on Hit |
| **Iron Bastion** (new) | Warrior | Juggernaut | Bulwark, Immovable, Thornbound Oath; Spitethorn Bulwark; Iron Bellow | hold the pack, let them break on you | the tankiest; damage grows with the hits taken | slow alone; half reflect and a cap on bosses | 300: shield, Block Chance and Reflect Damage mods. 1000: Spitethorn Bulwark, reflect 15% |
| Two-handed cleaver | Warrior | Berserker | Cleaving Arc, Undying Rage; Skyfall Cleave, Colossus Fall | the existing area melee | second best area at 300 | squishier than the Juggernaut | a two-hander, crit nodes |
| **Stormquiver** (new) | Ranger | Deadeye; Ranger works | Stormstring, Hunter's Focus; Stormcaller Recurve; Dawnpiercer, Skewering Line | every arrow chains lightning through the pack | clears from range; keeps a strong single target | the main hit is 10% weaker | 300: the Recurve, energy nodes. 1000: crit and distance skill |
| Marked crossbow | Ranger | Deadeye | Hunter's Focus, Deadeye; crossbow; Final Verdict, Hail of Dawn | the existing single-target killer | best single target | weak on packs | crossbow, crit |
| Pack hunter | Ranger | Beastmaster | Pack Alpha, Ricochet; Wild Bond, Pack Howl, Rending Pounce, Feral Command | the existing companion bow | wolves are most of the damage (47% plain, 54% with Pack Alpha, 66% with the Trials' Alpha Bond and Apex Predator, computed at 750), they clear packs and hold the line | single target is the class's weak side (boss ratio 0.74 of the Deadeye) | Pack Alpha, Vocation Trials minion damage, bow, companion health |
| **Rime Orb** (new) | Mystic | Elementalist | Winter's Lattice, Arcane Echo; Shard of the Long Winter; Rime Bloom, Frozen Crypt | freeze the pack; every kill shatters into the next | the best pack clear; chains through dense rifts | fire and energy spells are 30% weaker; plain on bosses | 300: ice nodes, the Shard. 1000: magic level, ice increments |
| **Effigy Caller** (new) | Mystic | Elementalist; Mystic works | Effigy Covenant, Elemental Overload; Effigy Carver's Idol; Rime Bloom, Falling Pyre, Forked Storm | cast once, plant the effigy, keep moving or stand behind it | damage while repositioning; strong area with the Idol | single target is poor; effigies stay where you cast | 300: area spells, mana. 1000: the Idol |
| **Ember Brand** (new; an Inquisitor and Templar keystone, a poor pick for an Elementalist: -11% to -19% measured, O452) | Mystic or Templar | Elementalist or Inquisitor | Sigil of Cinders; Brand of the Ashen Choir; Witchfire Bolt or Judgement to brand, Falling Pyre or Purging Nova to ignite | brand the big one, burn the rest | good on bosses and packs at once | ice, energy and weapon damage are 20% weaker | 300: fire or holy nodes. 1000: the Brand |
| Healer and support | Mystic | Illusionist | Shared Phantasm, Inspiring Illusion; Mirror Mend, Lucid Reverie | the existing best healer | party attack buffs | low own damage | healing, mana |
| **Plaguebearer** (new) | Thief | Thief or Ninja | Blackblood Creed, Contagion Rite; Rotbloom Phial; Poison Blades, Shuriken Barrage | poison the pack, let the deaths spread it | packs melt while you keep moving | weapon hits 10% weaker; bosses do not chain | 300: earth nodes, Chance to Poison. 1000: the Phial, Damage over Time |
| **Twin-Fang Cascade** (new) | Thief | Ninja | Living Shadow, Cascade Edge; Splintered Instant; Shadow Step, Smoke Bomb | dual-wield crits that burst on everything near | fast pack clear for a single-target class | needs crit chance; non-crits 5% weaker | 300: crit nodes, Keen Edge mastery. 1000: Splintered Instant |
| Duelist | Thief | Samurai | Way of the Blade, Iron Parry; Counter Stance, Iaijutsu | the existing off-tank | parries and taunts | lower damage | a sword, absorbs |
| Bone army | Necromancer | Bone Lord | Covenant of the Grave (minions +20% damage for the Bone Lord, +50% health), Legion, Bone Colossus; Raise Dead, Bone Golem, Banner of Bones | the existing minion army | safe, minions take the hits | own spells weaker | spirit, minion nodes |
| **Grave Effigies** (new) | Necromancer | Necromancer or Lich | Effigy Covenant or Winter's Lattice with an ice wand; Bone Spear, Corpse Explosion | plant effigies on corpse piles | area for a line short of it | single target drops | an ice wand for the Lattice; the Idol |
| Rot curser | Necromancer | Lich | Hoarded Souls, Spreading Blight; Soul Rot, Withering Curse, Life Siphon | the existing damage over time | strong single target | slow start | magic level, death nodes |
| **Storm Palm** (new) | Monk | Shadowfist or Monk | Aether Edge, Hundred Hands; Aetherbound Plate; Maximum Energy Shield mods; Ashen Fist, Shadowfist Flurry | a fist fighter that burns its energy shield into its blows | hits harder as the shield grows | 20% less health; the shield must stay up | 300: four Maximum Energy Shield mods. 1000: the Plate, recharge mods |
| **Hundred-Fist Cascade** (new) | Monk | Shadowfist | focus crits, Hundred Hands, Cascade Edge; Pressure Points, Flurry | crits from spent chi burst on the pack | turns a burst class into a clearer | non-crits 5% weaker | crit, Swift Palm mastery |
| Chi healer | Monk | Iron Sage | Flowing Mercy, Deep Mantra, Overgrowth (since 2026-10-12); Kindled Breath, Mantra of Stone | the existing second healer | heals while fighting | modest damage | healing, vitality; 1000: the path to Overgrowth |
| **Reliquary Keeper** (new) | Templar | Sentinel | Reliquary Vow, Bastion; Reliquary Censer; Rebuke, Lay on Hands | a guardian relic heals and buffs the party and burns the pack | the best party support of the line | own damage 10% lower | 300: magic level and holy nodes. 1000: the Censer |
| **Iron Pilgrim** (new) | Templar, or any but Monk | Templar or Sentinel | Open Hand Creed; Knuckles of the Unbound; a shield; Radiant Smite, Consecration | bare fists and a shield; Radiant Strikes ride on every punch | no weapon to chase; strong shield play | the Warrior's skill spells see no weapon | 300: fist skill trains with use. 1000: the Knuckles |
| Holy area | Templar | Inquisitor | Divine Verdict, Burning Zeal; Judgement, Purging Nova, Zealotry | the existing holy area | area with self heals | needs a group to shine | holy nodes |
| **Trapper** (new, round 2) | Ranger | Deadeye; Ranger works | Snarewright's Creed, Hunter's Focus; Snarewalker Greaves; Snare Trap with fire or ice, Skewering Line | throw traps into the pack's path and keep shooting | strong pack clear from range; ice traps slow the pack | single target 40-50% below the line's own (computed) | 300: bow power, the Greaves. 1000: distance skill, fire nodes |
| **Mine-layer** (new, round 2) | Ranger or Thief | Deadeye or Ninja | Snarewright's Creed; Fusewright's Charm; Seeker Mine, Detonate Mines | lay five to ten mines, set them all off at once | the best burst of the snares; the Ninja gets an area tool | needs set-up; mines waste when the pack moves | 300: the Charm, earth for poison. 1000: crit and blade power. Measured before the spell cap; the Ranger line gets the mines back in O455 |
| **Choir Herald** (new, round 2) | Templar, Mystic or Necromancer | Sentinel, Illusionist or Bone Lord | Covenant of Vigils; Choirmaster's Circlet, Oathkeeper's Standard; Vigil of Wrath, Haste, Clarity | run three vigils for the party | +6% damage, +18% speed and mana for the whole party | own damage 10% lower; about half the mana is reserved | 300: maximum mana, the Circlet. 1000: the Standard |
| **Tithebound** (new, round 2) | Warrior, Monk or Templar | Berserker, Shadowfist or Inquisitor | Iron Tithe; Vigil of Wrath and Haste on health | a fighter that pays its auras in blood | +7.5% damage and +22% speed for itself, the mana stays free | a third of the health reserved; no party buff | 300: health nodes. 1000: the uniques |
| **Hollow Caster** (new, round 2) | Mystic or Necromancer | Elementalist or Lich | Hollow Vessel; Stillheart Robe, Hollowglass Diadem; four Maximum Energy Shield mods | cast from behind a shield that comes back in three seconds | immune to poison and life drain; heals not needed | a burst through the shield kills | 300: four T5 shield mods. 1000: the Robe, recharge mods |
| **Hollow Palm** (new, round 2) | Monk | Shadowfist | Hollow Vessel and Aether Edge; Aetherbound Plate | Storm Palm with three times the shield | Storm Palm's single target +12% / +19% (level 300 / 1000, with the Plate; computed). Measured 1392 / 5342 with the Plate | as the Hollow Caster | 300: shield mods. 1000: the Plate and the Hollowglass Diadem (the Robe is body armour like the Plate, so not both) |

Cross-line picks: Sanguine Covenant, Thornbound Oath and Cascade Edge are open to every class. Pyre Oath also suits
the Templar line. Aether Edge also suits the Inquisitor. The vigils are open to every class without a keystone; a
Warrior or a Ranger can run Vigil of Wrath on mana alone. Hollow Vessel also suits the Inquisitor and the Iron Sage.

New options per line in round 2: Warrior Tithebound; Ranger Trapper and Mine-layer; Mystic Choir Herald and Hollow
Caster; Thief Mine-layer and Trapper; Necromancer Choir Herald (Bone Lord) and Hollow Caster (Lich); Monk Tithebound
and Hollow Palm; Templar Choir Herald, Tithebound and Hollow Vessel.

## Recommended builds (O442)

The Auto build button of the passive tree offers three Recommended builds per class (`passive_builds_config.lua` `roles`).
Since O442 they are three different ways to play, not three stat fills: each walks to its own one to three keystones,
and no two builds of a class hold the same set (`tests/passive_builds_test.lua`). The Focus list reaches every other
keystone a class may hold, three at most in one build (five new themes: Traps and mines, Party support, Retaliation, Area clearing, Single target). The
list shows the build's line under its name: what it does and what it costs. The tank build of a class, where it had one,
is as it was: the survival model takes the median of the role builds. Several other builds use the Hybrid fill (health and
resistances with the damage nodes) for the same reason; the Ranger, Deadeye and Inquisitor live longer than before, and
no class lives shorter.

These builds are legal, different from each other and free of the known traps. No model measures the damage of a keystone
choice, so none of them is proven strong. Left out of every Recommended build: Open Hand Creed, Aether Edge and Hollow
Vessel (a price for no gain, or a pool that does not hold; the Hollow Palm that combines the last two stays as it is,
strong and not recommended by default), Sigil of Cinders for the Elementalist, poison for the Samurai, and mine builds for
the Ranger line (the spells come back in O455). The first keystone of a build arrives within 23 points for 47 of the 63 builds and by 30 points for
all 62 that hold one; the last keystone of any build arrives by 73 points.

| Class | Build | Keystones | What it is for | Price |
|---|---|---|---|---|
| Mystic | **Arcanist** (area) | Arcane Echo, Elemental Overload | Arcane Echo repeats area spells, Elemental Overload primes the next element. | Overload pays only if you change element. |
|  | **Mana Weaver** (support) | Covenant of Vigils | Covenant of Vigils: vigils for the party on a deep mana pool. | your own damage is 10% weaker. |
|  | **Warded Mage** (tank) | Elemental Overload | Elemental Overload with health and resistances. | low damage. |
| Ranger | **Sharpshooter** (single) | Deadeye, Longshot | Deadeye crossbow shots and the Longshot range bonus for one target. | hits within 2 sqm are 15% weaker. |
|  | **Stormquiver** (area) | Stormstring, Ricochet | Stormstring arcs and Ricochet bounces clear packs from range. | the main bow hit is 10% weaker. |
|  | **Barbed Hunter** (dot) | Barbed Quiver | Barbed Quiver makes every shot bleed: strong in long fights. | the hit itself is 10% weaker. |
| Warrior | **Slayer** (area) | Cleaving Arc, Earthbreaker | Two-hander cleaves and Earthbreaker slams for packs. | other melee hits are 10% weaker. |
|  | **Bulwark** (tank) | Bulwark | Shield, health and resistances: Bulwark blocks and reflects. | needs a shield, kills come slowly. |
|  | **Bloodied** (sustain) | Sanguine Covenant, Rampage | Sanguine leech and Rampage kill stacks. | you receive 30% less healing and take more damage per stack. |
| Elementalist | **Overloaded** (single) | Elemental Overload | Elemental Overload: a spell of a new element hits harder. | it pays only if you change element every cast. |
|  | **Effigy Caller** (area) | Effigy Covenant | Cinder Effigies repeat your area spell every 2 seconds. | your spells are 25% weaker, one target gains nothing. |
|  | **Vigil Keeper** (support) | Covenant of Vigils | Covenant of Vigils: vigils for the party on a deep mana pool. | your own damage is 10% weaker. |
| Deadeye | **Marked Target** (single) | Deadeye, Hunter's Focus, Longshot | Deadeye shots, Hunter's Focus stacks and Longshot: one target dies fast. | slow on packs. |
|  | **Stormquiver** (area) | Stormstring | Stormstring arcs lightning through the pack. | the main bow hit is 10% weaker. |
|  | **Cascade Hunter** (crit) | Cascade Edge | Cascade Edge bursts on the neighbours of every crit. | non-critical hits are 5% weaker. |
| Juggernaut | **Unbreakable** (tank) | Immovable, Bulwark | Immovable and Bulwark: the toughest way to stand. | kills come slowly. |
|  | **Pyre Walker** (area) | Pyre Oath, Bulwark | Pyre Oath burns the pack around you while you stand tough. | your other damage is 25% weaker and you burn too. |
|  | **Heavy Hitter** (single) | Earthbreaker, Executioner's Verdict | Earthbreaker slams and Executioner finishes. | most hits are 10% weaker and no tank keystone. |
| Illusionist | **Support Weaver** (support) | Shared Phantasm, Inspiring Illusion | Shared Phantasm and Inspiring Illusion: your party hits harder and heals. | needs a party, little own damage. |
|  | **Vigil Keeper** (support) | Covenant of Vigils | Covenant of Vigils: vigils for the party on a deep mana pool. | your own damage is 10% weaker. |
|  | **Illusory Striker** (area) | Effigy Covenant | An area caster: Cinder Effigies repeat each cast. | your spells are 25% weaker, one target gains nothing. |
| Thief | **Venomblade** (dot) | Blackblood Creed, Contagion Rite, Viper's Verdict | Poison on every attack that spreads when the pack dies. | evasion halved, weapon hits weaker. |
|  | **Cutthroat** (crit) | Shadow Twin, Cascade Edge | Shadow Twin sometimes strikes twice, Cascade Edge bursts on crits. | you take 6% more damage, non-crits 5% weaker. |
|  | **Mine-layer** (snares) | Snarewright's Creed | Traps and mines for the pack, set off by hand. | your other hits are 15% weaker and it needs set-up. |
| Ninja | **Twin Fangs** (crit) | Living Shadow, Cascade Edge | Living Shadow opens a damage window after a dodge, Cascade Edge bursts on crits. | non-crits are 5% weaker. |
|  | **Phantom** (single) | Shadow Twin | Shadow Twin sometimes strikes twice, Fleet Shadow adds dodge. | you take 6% more damage. |
|  | **Plaguebearer** (dot) | Blackblood Creed, Contagion Rite, Viper's Verdict | Poison on every attack that spreads when the pack dies. | evasion halved, weapon hits weaker. |
| Samurai | **Duelist** (tank) | Way of the Blade | Way of the Blade: Counter Stance parries every melee hit. | low damage. |
|  | **Iaido Striker** (crit) | Shadow Twin, Cascade Edge | Shadow Twin and Cascade Edge for crit duels. | you take 6% more damage, non-crits 5% weaker. |
|  | **Bloodblade** (sustain) | Way of the Blade, Sanguine Covenant | Way of the Blade parries, Sanguine leeches on every hit. | healing from others is 30% lower. |
| Berserker | **Rage Engine** (area) | Undying Rage, Cleaving Arc | Cleaving Arc hits the pack, Undying Rage heals on every blow. | Cleaving Arc needs a two-hander. |
|  | **Bloodrunner** (sustain) | Sanguine Covenant, Undying Rage | Sanguine and Undying Rage: leech and heal on every hit. | healing from others is 30% lower. |
|  | **Crusher** (crit) | Earthbreaker, Cascade Edge | Earthbreaker slams and Cascade Edge bursts on crits. | other hits 10% weaker, non-crits 5% weaker. |
| Beastmaster | **Pack Leader** (summons) | Pack Alpha, Stormstring | Pack Alpha wolves and Stormstring arcs. | the main bow hit is 10% weaker. |
|  | **Wild Volley** (area) | Ricochet, Longshot | Ricochet and Longshot: the bow bounces through a pack. | the wolves are filler, close hits are 15% weaker. |
|  | **Hardy Warden** (tank) | Pack Alpha | Pack Alpha with health and resistances for safe solo hunts. | low damage. |
| Monk | **Iron Body** (tank) | Scarred Discipline | Scarred Discipline: every hit you take builds chi and cuts damage. | no evasion. |
|  | **Fist Flurry** (single) | Seventh Palm | Seventh Palm: every 5th hit lands double and shocks its neighbours. | the other hits are 10% weaker. |
|  | **Palm Piercer** (area) | Piercing Palm, Scarred Discipline | Piercing Palm hits pass through to the next two enemies, Scarred Discipline cuts damage taken. | no evasion, each hit is 5% weaker. |
| Shadowfist | **Hundred Fists** (crit) | Hundred Hands, Cascade Edge | Hundred Hands feeds chi from crits, Cascade Edge bursts on them. | non-crits are 5% weaker. |
|  | **Pressure Points** (single) | Seventh Palm | Seventh Palm: every 5th hit lands double. | the other hits are 10% weaker. |
|  | **Shadow Step** (mobility) | Hundred Hands, Iron Tithe | Hundred Hands and Iron Tithe: vigils paid in health give speed. | part of your health is reserved. |
| Iron Sage | **Chi Healer** (support) | Flowing Mercy, Overgrowth | Flowing Mercy and Overgrowth: your heals reach a second ally and keep healing. | little damage. |
|  | **Stone Sage** (tank) | Scarred Discipline | Scarred Discipline: every hit you take builds chi and cuts damage. | no evasion. |
|  | **Healing Fist** (sustain) | Flowing Mercy, Sanguine Covenant | Flowing Mercy with Sanguine leech: a healer that fights. | healing you receive is 30% lower. |
| Necromancer | **Grave Caller** (summons) | Covenant of the Grave | Covenant of the Grave: minions hit harder and last longer. | your own spells are 25% weaker. |
|  | **Death Mage** (single) | Reaper's Toll, Corpse Detonation | Reaper's Toll doubles hits on weak monsters, Corpse Detonation blasts every kill. | your hits are weaker on healthy monsters. |
|  | **Grave Effigies** (area) | Effigy Covenant | Cinder Effigies repeat your area spell every 2 seconds. | your spells are 25% weaker, one target gains nothing. |
| Lich | **Rot Curser** (dot) | Hoarded Souls | Hoarded Souls with the rot and curse nodes: damage over time. | a slow start. |
|  | **Soul Reaper** (single) | Reaper's Toll, Corpse Detonation | Reaper's Toll doubles hits on weak monsters, Corpse Detonation blasts every kill. | your hits are weaker on healthy monsters. |
|  | **Lifedrinker** (sustain) | Sanguine Covenant | Sanguine leech with Life Siphon. | healing from others is 30% lower. |
| Bone Lord | **Bone Army** (summons) | Bone Colossus, Covenant of the Grave | Bone Colossus and Covenant of the Grave: a big army. | your own spells are 25% weaker. |
|  | **Bone Warden** (tank) | Bone Colossus | Bone Colossus with health and resistances. | low damage. |
|  | **Ossuary Fury** (area) | Reaper's Toll, Corpse Detonation | Reaper's Toll doubles hits on weak monsters, Corpse Detonation blasts every kill of your minions. | your hits are weaker on healthy monsters. |
| Templar | **Zealot** (damage) | Dawnchain, Penitent's Wrath | Dawnchain chains holy light, Penitent's Wrath answers every hit. | your spells are 10% weaker, your aura is halved. |
|  | **Shield Wall** (tank) | none (kept tank role) | Shield, resistances and the Templar aura. | little damage. |
|  | **Pyre Walker** (area) | Pyre Oath | Pyre Oath burns the pack around you. | your other damage is 25% weaker and you burn too. |
| Inquisitor | **Judge** (area) | Divine Verdict, Dawnchain | Divine Verdict lets Radiant Strikes judge, Dawnchain chains holy light. | your spells are 10% weaker. |
|  | **Ember Brand** (single) | Sigil of Cinders | Sigil of Cinders brands one target and burns its neighbours. | damage that is not fire or holy is 20% weaker. |
|  | **Rebuker** (tank) | Radiant Rebuke | Radiant Rebuke: a shield blocks one hit in five and answers with a holy nova. | weapon hits are 10% weaker. |
| Sentinel | **Bastion** (tank) | Bastion | Bastion widens your aura and covers the party. | little damage. |
|  | **Reliquary Keeper** (support) | Reliquary Vow | A Reliquary Warden follows you: it heals and buffs the party and burns enemies. | your own damage is 10% weaker. |
|  | **Retributor** (retaliation) | Thorns, Thornbound Oath, Penitent's Wrath | Thorns, Thornbound Oath and Penitent's Wrath: attackers pay for every hit. | your damage is 10% weaker, your aura is halved. |

## Keystone cap (O447)

Owner decision of 2026-11-09: a character holds at most 3 keystones. The rule is in before the beta wipe of 2026-11-18,
so no refund event is needed beyond the login refund below. The number is `keystoneMax` in `passivetree_config.lua`.

- **What counts.** Every node the tree data marks as a keystone, 38 nodes (44 since O449, 47 since O450). 24 archetype keystones (the three rounds), the
  pair 621 and 624 (one keystone per class), the 4 line keystones (369, 376, 383, 390) and the 8 class section keystones (14 since O449).
  Masteries and class notables do not count. The code reads the data (`passivetree_core.lua` `keystoneKind`) and the
  client marks the same 38 nodes (44 since O449, 47 since O450). Paragon, Vocation Trial nodes and the Rift Atlas (its own cap of 1) are not tree keystones.
- **Where it is checked.** One core function, `checkKeystones`, at every door that writes a tree: a plain save, a plan,
  a build code import, an Auto build, a loadout load. Apply on top of a tree adds the build to the keystones you hold, so it
  can be refused; Reset and apply always fits. A refused action changes nothing and says "You can hold at most 3
  keystones. Refund one to take another."
- **Old saves.** A loadout or build code that holds 4 or more is refused whole, never trimmed. A character over the cap at
  login gets its whole tree back for free, once, with a message. The trending builds list no build over the cap.
- **Builds.** The generator never takes a fourth keystone, for any point budget (`tests/passive_builds_test.lua`).
  Recommended builds hold 1 to 3; the Templar Shield Wall holds none, as it was. Two Focus builds took a fourth keystone
  before and stop at 3 now: Deadeye Single target and Juggernaut Retaliation.
- **Hollow Palm.** Hollow Vessel and Aether Edge are 2 keystones. It stays legal and as it is.
- **The window.** "Keystones 2/3" sits beside the points. A keystone you cannot take says why in its tooltip.

## Class sections for every line (O449)

Nine classes had no class section: Warrior, Juggernaut, Berserker, Ranger, Deadeye, Beastmaster, Mystic, Elementalist,
Illusionist. Now all 21 classes have a start node, line nodes, an ascended path with a keystone and a mastery (docs/CLASSES.md
"Class sections for every line (O449)"). The six new keystones count toward the cap of 3, so a section keystone is a real pick:

| Class | Keystone | Play style |
|---|---|---|
| Juggernaut | Unbroken Line | stand in a pack with a shield: less damage taken for each enemy next to you |
| Berserker | Open Veins | two-handed hits that bleed |
| Deadeye | Lone Mark | one isolated target, away from the pack |
| Beastmaster | Wolfbond | let the wolves do the work: they hit more, your bow less |
| Elementalist | Convergence | elemental spells into a crowd |
| Illusionist | Phantom Double | spells that strike twice |

- **Same numbers rule as the other sections.** Notables, line nodes and masteries are plain tree stats at or below the median
  of the older sections; each keystone has a price. Each of these keystones alone stays under +40% of the class default in
  its specialty: the largest direct gain is +20% (Wolfbond, on the wolves' share of the damage only). Held with an older
  keystone a build can pass it: Wolfbond multiplies Pack Alpha, x1.62 on the wolves together.
- **Builds.** The Auto build generator takes the new nodes where they lie on a path. 153 of the 464 builds changed: 22 of the
  63 Recommended roles and 131 Focus builds, all of the nine classes and every one on a path with a new line node or notable
  (a build that takes the first line node is shifted behind it). The 311 builds of the other twelve classes are the same bytes as
  before. Every build still holds 1 to 3 keystones. No Recommended build holds a section keystone: the roles are not changed here.
  Each new keystone is in the Focus build of one theme (`keystoneThemes`: Unbroken Line, Convergence and Wolfbond `pack`, Open
  Veins and Lone Mark `physical`, Phantom Double `single`), a theme that no Recommended role of that class fills with. A role
  that would now want a section keystone, for the owner of the roles: Juggernaut Unbreakable or Pyre Walker (Unbroken Line),
  Berserker Crusher (Open Veins), Deadeye Marked Target (Lone Mark), Beastmaster Pack Leader (Wolfbond), Elementalist
  Overloaded (Convergence), Illusionist Illusory Striker (Phantom Double).
- **Saved trees and build codes.** Nothing moved, no id was reused: no refund, no version bump (`reworked` stays at 6, build
  code format 6). A tree or loadout saved before stays valid. The class check at login still strips nodes of another line.
- **Not done.** No round 4 keystone (O450), no spell modifier mastery (O451). Computed, not measured in game.

## Round 4 keystones (O450)

The owner approved speed builds ("Speed builds go ahead: Momentum") and wants several ways to play each class. Three new keystones
open play styles the tree did not have: a build that runs, a build that casts one element, a bleed for fists and one-handed
weapons. Each is a thin reuse of a hook that exists, each has a price, each counts toward the cap of 3 (47 keystones in the tree
now, 27 of the archetype kind). Computed, not measured in game.

| Keystone | Node | Who can take it | Gain | Price | Worst stack against +40% |
|---|---|---|---|---|---|
| Momentum | 706 | Ranger, Thief and Monk lines | your hits deal 1% more for every 5% of movement speed above your base, 10% at most | you take 8% more damage | 1.10 x 1.12 x 1.12 = 1.380, +38.0% |
| Attunement | 707 | Mystic, Necromancer and Templar lines | the element your tree favours most deals 11% more | every other element (fire, ice, energy, earth, death, holy) deals 15% less | 1.11 x 1.12 x 1.12 = 1.392, +39.2% |
| Open Wounds | 708 | Monk and Templar lines | melee hits with bare fists or a one-handed weapon bleed for 40% of the hit over 4 s | those hits deal 8% less | 1.104 x 1.12 x 1.12 = 1.385, +38.5% |

- **The stack.** A character holds 3 keystones, so the worst legal stack is the keystone and two others of the median size of the
  flat damage gains of the rounds before (Lone Mark and Convergence, +12% each). The test builds it from the configs
  (`tests/round4_keystones_test.lua`). The gain of each is its net factor in its own specialty: Momentum at the fastest legal
  speed, Attunement for a build of one element, Open Wounds on one target over a long fight with a hit every 2 s (the next hit
  replaces the bleed, so 2 s of 4 s pay out: 0.92 x (1 + 0.40 x 0.5)). Older keystones can pass +40% alone or together
  (Longshot +30% with Hobbling Shot +20%); that is not changed here.
- **Momentum.** Hook: the `statscale` family of the unique items (`unique_passives_core.lua`), fed with the speed above the base
  in percent of the base, whole steps of 5% like the uniques. The speed in use is the clamped walk speed, the base is the
  engine's (`data/lib/chaos_speed.lua`: vocation 220 + 50 + 2.5 a level to 300, then 1 a level). The gain is the same at every
  level because it follows the percent. A speed-scaling unique (Short Ways Home to Endless Road, +20% to +40%) and Momentum do
  not add: the larger counts, so the keystone adds nothing on top of one. Against players a third of the gain.
  The price is on the damage you take, also through the mana shield (the provider `momentum`, like Rampage's).
- **The fastest legal speed.** Every source in a fight, in percent of the base: items, gems and sets 12 (`movespeed` cap),
  Paragon 10 (20 points x 0.5%), Vigil of Haste 15, Banner Call 10 for 12 s, Ember of Haste 25, the tree's speed nodes 80 speed
  points (`maxSpeed`). Charms add speed out of combat only. Mounts add a flat speed in the stock mounts file, which this
  repository does not hold: the cap of the gain and the engine's top walk speed (`maxPlayerSpeed` 2600) hold whatever they add.

  | Level | Base speed | Sustained (items, Paragon, vigil, tree) | Gain | With Banner Call and Ember | Gain |
  |---|---|---|---|---|---|
  | 100 | 517 | 52.5% above | +10% | 87.5% | +10% |
  | 500 | 1217 | 43.6% | +8% | 78.6% | +10% |
  | 1000 | 1717 | 41.7% | +8% | 51.4% (the engine's top speed) | +10% |

- **Attunement.** Hook: the price rule of Winter's Lattice (a factor on the type of each damage half, `A.typeFactor`), now with a
  gain for one element. The locked element is the largest `incrementX` of your tree (fire, ice, energy, earth, death, holy; the
  first of that list on a tie), so no window is needed and the Auto builds of an element theme lock that element. A tree with
  no element increment locks nothing: no gain, no price. Physical and drain are not elements. A kit of four elements in equal
  parts loses (1.11 + 3 x 0.85) / 4 = 0.915, so the keystone asks for one element.
- **Open Wounds.** Hook: the bleed of Barbed Quiver (`addBleed`, a stronger bleed replaces a weaker). It is the Monk and Templar
  lines' bleed: Open Veins is the Berserker's and needs a two-handed weapon, so no class holds both. The Warrior line gets no
  second bleed keystone: it differs from Open Veins in numbers only.
- **Where they sit.** Three new nodes appended, ids 706 to 708, each in a group of its own (109 to 111), each a side branch of an
  existing node out in the open: 706 of the Speed node 120, 707 of Frostbitten Will 219, 708 of Iron Communion 161. The three
  parents gained one link each; no node moved, no node was converted. Icons are cells that exist (Hobbling Shot's, Covenant of
  Vigils', Undying Rage's): no new PNG.
- **Saved trees and build codes.** Nothing changed that a saved tree reads: `reworked` stays at 6, build code format 6, no
  refund, no old code is touched. A whole-tree code is 130 characters, as before. Converting an existing leaf instead would
  have needed version 7 and format 7: every character holding the leaf is refunded at its next login and old codes would
  drop it.
- **Builds.** Each is tagged for Focus themes that no Recommended role of a class that may hold it fills with (a role takes the
  keystones of its fill's theme, and no role may change): Momentum for single target and area clearing, Attunement for fire,
  ice, energy and earth (not holy: Radiant Rebuke, Dawnchain and Sigil of Cinders fill the three places of a Templar line holy
  build already), Open Wounds for physical. 55 of the 464 builds changed, all Focus builds, each now holds one of the new
  keystones (Momentum 13 builds, Attunement 36, Open Wounds 6); the 63 Recommended builds are the same bytes as before.
  Every build still holds 1 to 3 keystones. Roles that would now want one, for the owner of the roles: Momentum in Shadowfist
  Shadow Step (it fills with the mobility theme), Ranger Sharpshooter, Ninja Phantom, Thief Cutthroat, Monk Fist Flurry;
  Attunement in Necromancer Death Mage (death theme), Elementalist Overloaded, Mystic Arcanist, Inquisitor Ember Brand;
  Open Wounds in Monk Fist Flurry and Templar Zealot.
- **Left out.** Lone Wolf and Pack Tactics for the Beastmaster: how many wolves are out belongs to the companion spells and
  `companion_balance_config.lua`, which `companion_model.py` bounds, and Wolfbond already trades the own bow for the wolves; a
  second choice would need a spell change. Conjured Host for the Mystic line: no class of the line holds a summon (the
  Illusionist's Hall of Mirrors is three decoys for 10 s), and a summon system is not for this close to launch.

## Weapon families (O454)

Sword, axe and club hit the same before (one melee skill). Now each has a trait on the basic melee attack and a price, for the
Warrior, Thief and Templar lines. Spells, fists and the Monk line stay as they are. Class damage does not move: on one target every
family is within 3% of before and none is 5% above another; the axe gives at most +12% of the basic attack on a pack, which is under
+5% of any class's damage on 5 targets (computed, not measured).

| Family | Trait | Number | Price | Boss | Against players |
|---|---|---|---|---|---|
| Sword | Tempo: hits on the same target speed up the swing, each hit is lighter by the same share | up to +20% attack speed in 5 steps, +2% damage at full stacks, a new target or 3 s without a hit starts over | none | the same | half the stacks |
| Axe | Cleave: part of the hit is split among the monsters next to the target | 14% of the hit in all, split among up to 8 neighbours | 2.5% less damage | the same | nothing is split, no price |
| Club | Impact: a hit may daze a monster | 25% a hit, it cannot attack for 0.7 s, then 3 s of rest | 2.5% less damage | only slowed (25% for 1 s, 15% a hit, 8 s of rest) | no daze, no price |

Pick: sword to kill one big target, axe to clear packs, club to take less damage from the monsters in front of you. The tooltip of
the weapon has the line. Every affected class has three or more weapons of at least two families in every level band except the
Berserker (two-handed only: levels 1-20, 1000-1300 and 1700-2400+ have one family with three or more). The table of weapons per
family per band: server/README.md "Weapon families (O454)".

## Card sets (O453)

A card swaps the element of one spell. That was numbers only. Now three cards of one element give a small bonus, so a
second element is a choice.

- You turn on at most 5 cards. A set needs **3 cards of one element**, one for each spell line your class casts. The highest
  card of a line that is on gives the line its element. A lower card of the same line, a second copy of a card, a card of a
  spell your class cannot cast, a card that is off or sits outside the deck: none of them counts.
- **One tier only.** 4 or 5 cards give the bonus of 3. **One set at a time:** five slots hold no second set of three.
- A heal, melee, widen, bow or legendary card has no element. Ice (no class has three Ice lines) and Drown have no set.
- Character Info (Character > Character Info) names the set and shows the progress, for example "2 of 3 cards". Turning a
  card on or off tells you when the set turns on or off. The card text names its set.

| Set | You get | Number | Cards that carry it | Who can reach it |
|---|---|---|---|---|
| Fire | Fire hits deal more | +4% of the Fire part of the hit | tier 1 of 7 lines | Ranger, Mystic, Necromancer, Monk and Templar lines, Elementalist |
| Earth | Earth hits poison | 4% of the hit over 4 s | tier 1 to 3 | Warrior, Ranger and Templar lines |
| Death | Death hits heal you | 1.5% of the damage, at most 1% of your health a hit | tier 3 to 4 | every class |
| Holy | Holy hits heal you | 0.5% of your health, once every 3 s | tier 1 to 2 | Elementalist |
| Energy | Energy hits slow the target | 15% for 1.5 s | tier 3 to 4 | Mystic, Necromancer line, Elementalist |

Each number is smaller than the snare of the same element (burn 30%, poison 36% over 6 s, leech 4%, party heal 2%, ice slow
40% for 3 s). A damage part never goes over +6% of its own element and never touches another element. Damage over time is
never changed. Against players the damage and poison are a third; the slow does not work on players.

**Price.** A set takes 3 of your 5 slots and locks the three lines of your class to one element. Most classes have exactly
3 lines, so a set uses all of them and leaves 2 slots for the legendary card and one buff or heal card. Death and Energy
need the rarer tier 3 and 4 cards. In damage the set costs little: against the best mixed build at level 500 (computed, see
`server/README.md` "Card sets (O453)") the Warrior line is 0.5 to 0.8% behind, the Templar line 1.1 to 2.0%, the Illusionist
2.2% to 3.4%; eleven classes are level with it because their card spells are not in their rotation or the bonus is not damage;
the Beastmaster and Mystic lead by less than half a point. The worst case, all of a class's damage being of the set's
element, is 6% of its damage per second. Nothing here was measured in game.

## Spell modifier masteries (O451)

A spell changes how it plays through support runes. They come from loot. Now the passive tree has a second way: a mastery
effect that gives **one named spell a free support effect**. No luck needed.

- Each of the seven mastery nodes (Thief 665, Necromancer 666, Monk 667, Templar 668, Warrior 703, Ranger 704, Mystic 705)
  gets two or three new effects after the old ones. 20 in all. The old effects keep their place and meaning. A character
  still holds one effect per mastery node, and one mastery node per line.
- The spell is one that all three classes of the line cast, so the choice works for the base class and both ascensions. The
  Mystic line has two: only two attack spells are shared by Mystic, Elementalist and Illusionist.
- The effect is a **Common rune** of the support, the lowest tier, which drops at every level band. No support has a price,
  so the number the rune gives in percent is cut to 75% (Fork 35% becomes 26%, Echo 15% becomes 11%). The tooltip says it:
  "A reduced Fork rune, free." The count of Fork and the radius of Breadth stay.
- It takes **no rune socket**. A real rune of the same support on that spell counts when it is stronger. The two never add.
  A brand never joins a real brand: one brand per spell, as in the window.
- The tree stat is `spellMod`. The tree listener writes the held choice to one storage and the spells read it where they read
  their supports. No new opcode, no engine patch, no new art. Numbers and choices: `server/data/lib/chaos_spell_masteries_config.lua`.
- Saved trees, build codes and loadouts stay valid: the effects are appended, so an old id means the same. No version bump, no
  refund. The limit of effects per node is 7, it was 4. The Recommended builds are unchanged: none of them picks a
  spell modifier.

Every choice opens a play style. A single target spell forks to the pack, an area spell reaches the enemies it missed, a spell
echoes, a hit curses, a spell carries an element.

| Class line | Choice | Spell | Support | Tier | Price | Spell gain 1T / 5T | Class gain 1T / 5T |
|---|---|---|---|---|---|---|---|
| Warrior | Gore Fork | Gorehook | Fork | Common | none, reduced: 26 instead of 35 | +0% / +26% | +0.0% / +1.8% |
| Warrior | Echoing Slam | Colossus Fall | Echo | Common | none, reduced: 11 instead of 15 | +5% / +5% | +1.2% / +1.8% |
| Warrior | Wide Cry | Bastion Cry | Breadth | Common | none, reduced: 26 instead of 35 | +0% / +17% | +0.0% / +3.0% |
| Ranger | Splintering Spear | Sunspear | Shatter | Common | none, reduced: 15 instead of 20 | +0% / +60% | +0.0% / +4.7% |
| Ranger | Hallowed Ground | Blessed Earth | Dawnbrand | Common | none, reduced: 15 instead of 20 | +15% / +15% | +2.3% / +5.4% |
| Ranger | Hunter's Mark | Dawnpiercer | Hex | Common | none, reduced: 2 instead of 3 | +0% / +0% | +1.3% / +0.3% |
| Mystic | Crimson Fork | Crimson Covenant | Fork | Common | none, reduced: 26 instead of 35 | +0% / +26% | +0.0% / +2.4% |
| Mystic | Storm Rupture | Prismatic Rupture | Stormbrand | Common | none, reduced: 15 instead of 20 | +15% / +15% | +2.1% / +3.2% |
| Thief | Twin Toss | Shuriken Toss | Fork | Common | none, reduced: 26 instead of 35 | +0% / +26% | +0.0% / +11.2% |
| Thief | Wide Smoke | Smoke Bomb | Breadth | Common | none, reduced: 26 instead of 35 | +0% / +17% | +0.0% / +3.2% |
| Thief | Echoing Flurry | Blade Flurry | Echo | Common | none, reduced: 11 instead of 15 | +5% / +5% | +0.8% / +2.4% |
| Necromancer | Cursed Marrow | Marrow Bolt | Hex | Common | none, reduced: 2 instead of 3 | +0% / +0% | +1.0% / +0.2% |
| Necromancer | Grave Wail | Gravewail | Gravebrand | Common | none, reduced: 15 instead of 20 | +15% / +15% | +2.3% / +4.7% |
| Necromancer | Splintered Rot | Blightbrand | Shatter | Common | none, reduced: 15 instead of 20 | +0% / +60% | +0.0% / +5.3% |
| Monk | Wide Mist | Mistborne Strike | Breadth | Common | none, reduced: 26 instead of 35 | +0% / +17% | +0.0% / +4.1% |
| Monk | Splitting Palm | Sundering Palm | Shatter | Common | none, reduced: 15 instead of 20 | +0% / +60% | +0.0% / +5.5% |
| Monk | Quick Heel | Whirling Heel | Quickening | Common | none, reduced: 4 instead of 6 | +4% / +4% | +1.6% / +1.8% |
| Templar | Echoing Ground | Consecration | Echo | Common | none, reduced: 11 instead of 15 | +5% / +5% | +1.2% / +2.9% |
| Templar | Marked Cut | Hallowed Cut | Hex | Common | none, reduced: 2 instead of 3 | +0% / +0% | +1.0% / +0.2% |
| Templar | Bell of Dawn | Bell of Reckoning | Dawnbrand | Common | none, reduced: 15 instead of 20 | +15% / +15% | +2.4% / +3.7% |

**Gain.** Computed, not measured. No tool measures supports, so the numbers come from the support's own numbers on the rotation
simulator (`server/tools/spell_mastery_model.py`, `server/data/spells/README.md` "Spell modifier masteries (O451)"). Spell
gain is one cast of the spell on 1 target and on the pack of 5. Class gain is the best set of at most 5 spells that holds the
spell, at level 100, 500 and 1000: what the effect adds, as a share of the damage of the default set, times the share that is
not the auto attack. Hex raises every hit, so its class gain is the share of the damage on the hexed monsters. The largest class
gain of any choice is +11% (Twin Toss, Thief line, level 100, 5 targets). **Limit of the model: +15% of the class damage per
choice, tested.** The owner cap of +40% in a specialty holds with room for the keystones.

The Quickening choice does little in a rotation that casts on the 2 s attack group: 4% of a cooldown rarely moves a cast to an
earlier tick. It is the one choice that is mostly for hand casting. Fork on one target and Breadth and Shatter on a lone target
give nothing: they are for packs.

## Starter builds guide and Save to a loadout slot (O448)

The build audit found that the game says builds exist but not what to do with them. Two answers, both words and plain actions, no
new numbers.

- **The guide.** A website page, `page?plugin=chaos&p=starterbuilds`, English and pt-BR. Per class, its three Recommended builds:
  name and kind, what it does (the build's own line, up to its price), how it plays (two or three short sentences), the price
  in words, the keystones by name with the point of the build each one arrives at, the spells to lean on (from the class kit),
  what to wear (the sword, axe or club of the Warrior, Thief and Templar lines, O454), a card set that fits when one is
  reachable (O453) and four import codes. The data is generated: `cd server && luajit tools/gen_starter_builds.lua` writes
  `website/overlay/plugins/chaos/guide/starter_builds_data.json` from the build data and `tools/starter_builds_config.lua`, the
  hand-written words. `--check` is in CI. The page is `starter_builds_lib.php` and `pages/starterbuilds.php`. The wiki tree
  guide links it, the How it works Passive Tree card and the help search name it.
- **No figures.** The guide is qualitative: a percent sign or the letters DPS in a text stops the generator and the tests. The
  price line of a Recommended build in the game has percent figures, so the guide writes its own price in words. A point or a
  level is a plain fact and is allowed (a keystone arrives at point 25).
- **The codes.** Each build is cut at 23, 73, 123 and 248 points, levels 100, 300, 500 and 1000. A code is the first N nodes of the
  build in order, written with `ChaosBuildShare.encode` (format CB6, the Build Code window imports it). Every cut is checked
  with the tree rules of the loadouts (`PassiveBuildsCore.planSlot`: known nodes, the class's own, each node touching the start
  or an earlier node, at most 3 keystones) and decoded again. A cut that is not a legal tree would be dropped and listed;
  none is dropped today: 63 builds, 252 codes. The class mark of a code is the class line (Warrior, Ranger, Mystic, Thief);
  the Monk, Necromancer and Templar lines share mark 0, so the game accepts such a code on any of those three lines and stops
  the nodes the class cannot hold.
- **Save to a loadout slot.** The Auto build panel of the passive tree has a button for the picked build. The player picks a slot,
  the build's tree cut to the character's points is written into it, named after the build. The live tree does not change, and
  only the tree of the slot is written: its gear, runes, Paragon and icon stay as they were (the panel says so). A slot that
  holds something is replaced only after a confirm. Refused, with nothing changed: another class's build, a build over the
  keystone cap, a slot that does not exist or is not earned, the active slot (it holds the live build and is written over on the
  next switch), no passive points yet, below the loadouts' level. No new opcode: the actions `autobuildSlots` and
  `autobuildSaveSlot` of the passive tree's opcode 65, reusing the loadouts' own checks. server/README.md "Loadouts".

## Rotation variants (O446)

The helper's Auto setup and Auto rotation cast one list of at most 5 attack spells. You can now pick another list, so that a build
plays with low attention. In the helper window, left of the Auto setup button, a small choice shows **Default**, **One target**,
**Groups** and **Mines** (only what your class has). One line next to it gives the price in numbers, for example "Bosses +9%, groups
-16%"; the tip has the long text. The choice is saved per character. Press Auto setup or Auto rotation to apply it.

- **Default**: the balanced list. It does not change.
- **One target**: the best list against a boss. Groups pay the price.
- **Groups**: the best list against a pack of five. One target pays the price.
- **Mines** (Ranger, Deadeye, Beastmaster, Thief, Ninja, Samurai): throws Seeker Mine every 6 s and lets the fuse set it off, with the
  best attack spells around it. For mine builds. The burst comes up to 9 s late and a pack that keeps moving costs a third of the
  mine damage.

No variant is more than +40% over the default in its specialty (computed). A level or class with no variant uses the default; the Lich
has none. Every list casts on every 2 s group cooldown and the helper rules stay: a variant is a different list, not a faster bot. The
numbers are computed, not measured (`server/data/spells/README.md` "Rotation variants (O446)"). The Unity player uses the default.

## Leveling notes

- Keystones need their paths. The leaves at 8 or 9 points are early picks (96, 99, 102 and 105 too); 253, 262, 355 and
  362 take 18 to 21.
- Uniques drop from monsters of their themes. The Codex lists where. Two of them work without the keystone.
- The second round's six uniques have their own equip rule (2026-10-13): the level of the unique and the classes of
  its archetype. Greaves 120 and Charm 150: Ranger and Thief lines. Circlet 200 and Standard 180: Warrior, Mystic,
  Necromancer, Monk and Templar lines. Diadem 250 and Robe 300: Mystic, Necromancer, Monk and Templar lines. A stock
  copy of the same base item keeps the base rule. Details: `server/README.md` "Unique equip rules".
- A changed tree is a respec. The free refund only covers the converted leaves, once per round.
- Snare Trap comes at level 40, Seeker Mine and Detonate Mines at 60. The vigils come at 40 and 60.

## What the engine allows, and what is left out

- Everything here is Lua on the current engine. No new source patch.
- A real spell fired by a critical hit: the engine has no Lua call that casts a spell by name. Cascade Edge releases its own
  elemental burst instead. A patch for a real spell cast was looked at and not made: it would skip mana, cooldowns
  and the spell checks, so each trigger would need its own rules.
- Traps and mines are spots in memory with a budgeted scheduler, not items with movement events: an item would be
  saved, moved or picked up, and a step event only sees its own tile, while a trap must see 1 sqm around it.
- Reserved mana is a condition that lowers the maximum mana (and the health, Iron Tithe). The engine has no reserve of
  its own. A level up or new gear changes the maximum; the next second the reservation follows.
- Hollow Vessel's early recharge is added by the archetypes' one second think; the engine's own delay stays 2 s for
  everyone else.
- Effigies are summons that cannot move or be attacked. Monsters ignore them.

## Third round: Warrior and Ranger lines (2026-10-20)

Warrior, Juggernaut, Berserker: Executioner's Verdict (melee and spells finish monsters under 15%), Earthbreaker (every 4th hit
slams), Rampage (kill stacks, 5 at most), Last Stand (survive one lethal hit per 90 s). Ranger, Deadeye, Beastmaster:
Longshot (distance bonus), Barbed Quiver (bleed), Opening Shot (first hit on a full monster), Hobbling Shot (slow). Each
has a price on the other hits. Numbers: `server/data/spells/README.md` "Warrior and Ranger line keystones".
