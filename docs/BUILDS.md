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
| Open Hand Creed | 109 | every line but the Monk's | with no weapon in hand, fists hit with the Monk's fist attack and your best melee skill, +10%; strike spells that read the weapon use it too | none; you hold no weapon | Knuckles of the Unbound: works at 80% without the keystone, +10% with it |
| Contagion Rite | 107 | Thief line | a monster that dies poisoned by you passes the poison to 3 more within 2 sqm, up to 4 steps deep | weapon hits -10% | Rotbloom Phial: one more target, one step deeper |
| Cascade Edge | 78 | every class | a critical hit bursts on the other enemies within 1 sqm of the target for 60% of the hit, in your strongest tree element; once per 0.8 s | non-critical hits -5% | Splintered Instant: +25% burst, 0.2 s sooner |
| Stormstring | 82 | Ranger line | bow and crossbow hits arc to 3 other enemies within 3 sqm for 40% as energy | the main hit -10% | Stormcaller Recurve: one more arc; alone, one arc of 25% |
| Winter's Lattice | 355 | Mystic and Necromancer lines | a monster that dies within 2 s of your ice hit shatters for 6% of its maximum health on enemies within 2 sqm; kills chain | fire and energy damage -30% | Shard of the Long Winter: +2%, +1 sqm |
| Effigy Covenant | 262 | Mystic and Necromancer lines | an area attack spell raises a Cinder Effigy on your tile; it repeats that cast every 2 s for 22% of its average hit, at most 2, for 12 s | your spells -35% | Effigy Carver's Idol: a third effigy |
| Sigil of Cinders | 106 | Mystic and Templar lines | fire and holy spell hits ignite; a one-target spell brands the target, the brand burns its neighbours every second and jumps when the bearer dies; burns spread on death | damage that is not fire or holy -20% | Brand of the Ashen Choir: brand +25% |
| Aether Edge | 362 | Monk and Templar lines | weapon and fist hits add 6% of your current energy shield as energy damage | maximum health -20% | Aetherbound Plate: 10% of the shield |
| Reliquary Vow | 253 | Templar line | a Reliquary Warden follows you; every 2 s it heals the party around it, gives the others +5% damage and burns enemies with holy damage | your own damage -10% | Reliquary Censer: pulses +25% |
| Snarewright's Creed | 105 | Ranger and Thief lines | 2 more traps and 3 more mines may be out; they arm in half the time and hit 25% harder | your other hits (weapon, spells; not damage over time) -15% | Snarewalker Greaves: +1 trap, armed 0.3 s sooner, +10%. Fusewright's Charm: +2 mines, +10%, a 4 s longer fuse. Both work without it |
| Covenant of Vigils | 99 | Mystic, Necromancer and Templar lines | vigils reserve 30% less, reach 3 sqm farther and give the party 20% more of every effect | your own damage -10% | Choirmaster's Circlet: reservation -15%. Oathkeeper's Standard: -10% and 2 sqm farther |
| Iron Tithe | 102 | Warrior, Monk and Templar lines | vigils reserve maximum health instead of mana, at 60% of their share, and work 50% stronger on you | they cover you alone; no effect next to Hollow Vessel | the vigil uniques above |
| Hollow Vessel | 96 | Mystic, Necromancer, Monk and Templar lines | maximum health is 100; energy shield: the items' +50%, plus half the health given up; it recharges 15% of its maximum a second faster and starts 1 s after a hit; no poison and no life drain hurt you | heals, leech and regeneration fill only the 100 health; the pool is 20-40% smaller than health and shield before | Stillheart Robe: the items' shield +40% more. Hollowglass Diadem: recharge +10% a second and the 1 s start, also without it |

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
| Detonate Mines | `vok snar` | 60 | every armed mine of yours goes off, 0.1 s apart |

- **The element.** Say it after the words: `drai snar "fire"`. Fire burns, ice slows by 40%, energy reaches 1 sqm
  farther at 85% of the hit, earth poisons, death drains 4% of the damage as health, holy heals you and party
  members near the snare by 2% of their health, physical hits 15% harder. The choice is remembered. Without one, a
  brand rune socketed in the spell picks it (Emberbrand fire, Rimebrand ice, Dawnbrand holy, Gravebrand death,
  Stormbrand energy). Otherwise physical.
- **The hit** scales with your best of bow, blade or shuriken power and your level. It is about three Skewering
  Line hits: a snare costs a cast and waits for a monster.
- **Gone** when you log out, die, change floor, walk 30 sqm away or step into a protection zone. Only monsters set
  them off and only monsters are hit, never players.
- **The game loop.** One scheduler looks at 60 snares every 0.2 s and fires at most 16 bursts. All players together
  may have 400 snares out. A full screen of snares costs about 2 ms a tick at most.

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

## The archetypes per class line

Two or more per line. "New" marks an archetype these keystones made possible. The others already worked.

| Archetype | Line | Class to aim for | Core: keystones, items, spells | Play style | Strengths | Weaknesses | Gear checkpoints |
|---|---|---|---|---|---|---|---|
| **Pyre Walker** (new) | Warrior | Juggernaut; Warrior works | Pyre Oath, Immovable, Bulwark; Pyreheart Mantle; Iron Bellow to pull packs in, Earthbreaker | walk into a pack and stand there; the aura does the killing | clears packs with no clicks; very tough | weak on one target; needs fire absorbs and regeneration | 300: fire absorb 40%+, Health Regeneration mods, vitality nodes. 1000: the Mantle, fire absorb 60%+ |
| **Bloodsworn Reaver** (new) | Warrior | Berserker | Sanguine Covenant, Undying Rage, Cleaving Arc; Vein of the Unsated; Skyfall Cleave, Bloodrage | two-handed cleaves that feed on every hit | sustain grows with the pack; no potions needed | heals from others are 30% weaker; leech cap per second | 300: a two-hander, life leech items. 1000: the Vein, Health on Hit |
| **Iron Bastion** (new) | Warrior | Juggernaut | Bulwark, Immovable, Thornbound Oath; Spitethorn Bulwark; Iron Bellow | hold the pack, let them break on you | the tankiest; damage grows with the hits taken | slow alone; half reflect and a cap on bosses | 300: shield, Block Chance and Reflect Damage mods. 1000: Spitethorn Bulwark, reflect 15% |
| Two-handed cleaver | Warrior | Berserker | Cleaving Arc, Undying Rage; Skyfall Cleave, Colossus Fall | the existing area melee | second best area at 300 | squishier than the Juggernaut | a two-hander, crit nodes |
| **Stormquiver** (new) | Ranger | Deadeye; Ranger works | Stormstring, Hunter's Focus; Stormcaller Recurve; Dawnpiercer, Skewering Line | every arrow chains lightning through the pack | clears from range; keeps a strong single target | the main hit is 10% weaker | 300: the Recurve, energy nodes. 1000: crit and distance skill |
| Marked crossbow | Ranger | Deadeye | Hunter's Focus, Deadeye; crossbow; Final Verdict, Hail of Dawn | the existing single-target killer | best single target | weak on packs | crossbow, crit |
| Pack hunter | Ranger | Beastmaster | Pack Alpha, Ricochet; Wild Bond, Feral Command | the existing companion bow | safe, the wolves hold the line | lower burst | bow, companion nodes |
| **Rime Orb** (new) | Mystic | Elementalist | Winter's Lattice, Arcane Echo; Shard of the Long Winter; Rime Bloom, Frozen Crypt | freeze the pack; every kill shatters into the next | the best pack clear; chains through dense rifts | fire and energy spells are 30% weaker; plain on bosses | 300: ice nodes, the Shard. 1000: magic level, ice increments |
| **Effigy Caller** (new) | Mystic | Elementalist; Mystic works | Effigy Covenant, Elemental Overload; Effigy Carver's Idol; Rime Bloom, Falling Pyre, Forked Storm | cast once, plant the effigy, keep moving or stand behind it | damage while repositioning; strong area with the Idol | single target is poor; effigies stay where you cast | 300: area spells, mana. 1000: the Idol |
| **Ember Brand** (new) | Mystic or Templar | Elementalist or Inquisitor | Sigil of Cinders; Brand of the Ashen Choir; Witchfire Bolt or Judgement to brand, Falling Pyre or Purging Nova to ignite | brand the big one, burn the rest | good on bosses and packs at once | ice, energy and weapon damage are 20% weaker | 300: fire or holy nodes. 1000: the Brand |
| Healer and support | Mystic | Illusionist | Shared Phantasm, Inspiring Illusion; Mirror Mend, Lucid Reverie | the existing best healer | party attack buffs | low own damage | healing, mana |
| **Plaguebearer** (new) | Thief | Thief or Ninja | Blackblood Creed, Contagion Rite; Rotbloom Phial; Poison Blades, Shuriken Barrage | poison the pack, let the deaths spread it | packs melt while you keep moving | weapon hits 10% weaker; bosses do not chain | 300: earth nodes, Chance to Poison. 1000: the Phial, Damage over Time |
| **Twin-Fang Cascade** (new) | Thief | Ninja | Living Shadow, Cascade Edge; Splintered Instant; Shadow Step, Smoke Bomb | dual-wield crits that burst on everything near | fast pack clear for a single-target class | needs crit chance; non-crits 5% weaker | 300: crit nodes, Keen Edge mastery. 1000: Splintered Instant |
| Duelist | Thief | Samurai | Way of the Blade, Iron Parry; Counter Stance, Iaijutsu | the existing off-tank | parries and taunts | lower damage | a sword, absorbs |
| Bone army | Necromancer | Bone Lord | Covenant of the Grave (minions +20% damage for the Bone Lord, +50% health), Legion, Bone Colossus; Raise Dead, Bone Golem, Banner of Bones | the existing minion army | safe, minions take the hits | own spells weaker | spirit, minion nodes |
| **Grave Effigies** (new) | Necromancer | Necromancer or Lich | Effigy Covenant or Winter's Lattice with an ice wand; Bone Spear, Corpse Explosion | plant effigies on corpse piles | area for a line short of it | single target drops | an ice wand for the Lattice; the Idol |
| Rot curser | Necromancer | Lich | Hoarded Souls, Spreading Blight; Soul Rot, Withering Curse, Life Siphon | the existing damage over time | strong single target | slow start | magic level, death nodes |
| **Storm Palm** (new) | Monk | Shadowfist or Monk | Aether Edge, Hundred Hands; Aetherbound Plate; Maximum Energy Shield mods; Ashen Fist, Shadowfist Flurry | a fist fighter that burns its energy shield into its blows | hits harder as the shield grows | 20% less health; the shield must stay up | 300: four Maximum Energy Shield mods. 1000: the Plate, recharge mods |
| **Hundred-Fist Cascade** (new) | Monk | Shadowfist | focus crits, Hundred Hands, Cascade Edge; Pressure Points, Flurry | crits from spent chi burst on the pack | turns a burst class into a clearer | non-crits 5% weaker | crit, Swift Palm mastery |
| Chi healer | Monk | Iron Sage | Flowing Mercy, Deep Mantra; Kindled Breath, Mantra of Stone | the existing second healer | heals while fighting | modest damage | healing, vitality |
| **Reliquary Keeper** (new) | Templar | Sentinel | Reliquary Vow, Bastion; Reliquary Censer; Rebuke, Lay on Hands | a guardian relic heals and buffs the party and burns the pack | the best party support of the line | own damage 10% lower | 300: magic level and holy nodes. 1000: the Censer |
| **Iron Pilgrim** (new) | Templar, or any but Monk | Templar or Sentinel | Open Hand Creed; Knuckles of the Unbound; a shield; Radiant Smite, Consecration | bare fists and a shield; Radiant Strikes ride on every punch | no weapon to chase; strong shield play | the Warrior's skill spells see no weapon | 300: fist skill trains with use. 1000: the Knuckles |
| Holy area | Templar | Inquisitor | Divine Verdict, Burning Zeal; Judgement, Purging Nova, Zealotry | the existing holy area | area with self heals | needs a group to shine | holy nodes |
| **Trapper** (new, round 2) | Ranger | Deadeye; Ranger works | Snarewright's Creed, Hunter's Focus; Snarewalker Greaves; Snare Trap with fire or ice, Skewering Line | throw traps into the pack's path and keep shooting | strong pack clear from range; ice traps slow the pack | single target 20-30% below the line's own | 300: bow power, the Greaves. 1000: distance skill, fire nodes |
| **Mine-layer** (new, round 2) | Ranger or Thief | Deadeye or Ninja | Snarewright's Creed; Fusewright's Charm; Seeker Mine, Detonate Mines | lay five to ten mines, set them all off at once | the best burst of the snares; the Ninja gets an area tool | needs set-up; mines waste when the pack moves | 300: the Charm, earth for poison. 1000: crit and blade power |
| **Choir Herald** (new, round 2) | Templar, Mystic or Necromancer | Sentinel, Illusionist or Bone Lord | Covenant of Vigils; Choirmaster's Circlet, Oathkeeper's Standard; Vigil of Wrath, Haste, Clarity | run three vigils for the party | +6% damage, +18% speed and mana for the whole party | own damage 10% lower; about half the mana is reserved | 300: maximum mana, the Circlet. 1000: the Standard |
| **Tithebound** (new, round 2) | Warrior, Monk or Templar | Berserker, Shadowfist or Inquisitor | Iron Tithe; Vigil of Wrath and Haste on health | a fighter that pays its auras in blood | +7.5% damage and +22% speed for itself, the mana stays free | a third of the health reserved; no party buff | 300: health nodes. 1000: the uniques |
| **Hollow Caster** (new, round 2) | Mystic or Necromancer | Elementalist or Lich | Hollow Vessel; Stillheart Robe, Hollowglass Diadem; four Maximum Energy Shield mods | cast from behind a shield that comes back in three seconds | immune to poison and life drain; heals not needed | a burst through the shield kills | 300: four T5 shield mods. 1000: the Robe, recharge mods |
| **Hollow Palm** (new, round 2) | Monk | Shadowfist | Hollow Vessel and Aether Edge; Aetherbound Plate | Storm Palm with three times the shield | Storm Palm's single target +12% / +19% (level 300 / 1000, with the Plate) | as the Hollow Caster | 300: shield mods. 1000: the Plate and the Robe |

Cross-line picks: Sanguine Covenant, Thornbound Oath and Cascade Edge are open to every class. Pyre Oath also suits
the Templar line. Aether Edge also suits the Inquisitor. The vigils are open to every class without a keystone; a
Warrior or a Ranger can run Vigil of Wrath on mana alone. Hollow Vessel also suits the Inquisitor and the Iron Sage.

New options per line in round 2: Warrior Tithebound; Ranger Trapper and Mine-layer; Mystic Choir Herald and Hollow
Caster; Thief Mine-layer and Trapper; Necromancer Choir Herald (Bone Lord) and Hollow Caster (Lich); Monk Tithebound
and Hollow Palm; Templar Choir Herald, Tithebound and Hollow Vessel.

## Leveling notes

- Keystones need their paths. The leaves at 8 or 9 points are early picks (96, 99, 102 and 105 too); 253, 262, 355 and
  362 take 18 to 21.
- Uniques drop from monsters of their themes. The Codex lists where. Two of them work without the keystone.
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
