# Build guide: the archetypes (2026-10)

The owner asked for the most played build styles of the genre to be possible here, at least two per class line.
This page lists them in our own words. Each one is playable with the base class. Each one fits one ascended class best.

Numbers live in code. Keystones and uniques: `server/data/scripts/chaos/archetypes_config.lua`. Rules:
`archetypes_core.lua`, tested by `server/tests/archetypes_test.lua`. Engine glue: `archetypes.lua`.
Computed damage at levels 300 and 1000: `server/data/spells/README.md` "Build archetypes". Those numbers are
computed, not measured in game. Server details: `server/README.md` "Build archetypes".

## The new keystones

Twelve small leaves of the main tree became keystones. No node moved and no link changed. Whoever held one of
those leaves gets it refunded once, for free, at the next login. Build codes older than format 4 leave them out.
Every keystone has a price.

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

All chain reactions share one work budget: 24 spreads a server tick, 40 per chain, a queue of 200. A packed
screen cannot stall the game loop. See `server/README.md` "Game loop stalls" for the numbers behind it.

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
| Bone army | Necromancer | Bone Lord | Covenant of the Grave, Legion, Bone Colossus; Raise Dead, Bone Golem, Banner of Bones | the existing minion army | safe, minions take the hits | own spells weaker | spirit, minion nodes |
| **Grave Effigies** (new) | Necromancer | Necromancer or Lich | Effigy Covenant or Winter's Lattice with an ice wand; Bone Spear, Corpse Explosion | plant effigies on corpse piles | area for a line short of it | single target drops | an ice wand for the Lattice; the Idol |
| Rot curser | Necromancer | Lich | Hoarded Souls, Spreading Blight; Soul Rot, Withering Curse, Life Siphon | the existing damage over time | strong single target | slow start | magic level, death nodes |
| **Storm Palm** (new) | Monk | Shadowfist or Monk | Aether Edge, Hundred Hands; Aetherbound Plate; Maximum Energy Shield mods; Ashen Fist, Shadowfist Flurry | a fist fighter that burns its energy shield into its blows | hits harder as the shield grows | 20% less health; the shield must stay up | 300: four Maximum Energy Shield mods. 1000: the Plate, recharge mods |
| **Hundred-Fist Cascade** (new) | Monk | Shadowfist | focus crits, Hundred Hands, Cascade Edge; Pressure Points, Flurry | crits from spent chi burst on the pack | turns a burst class into a clearer | non-crits 5% weaker | crit, Swift Palm mastery |
| Chi healer | Monk | Iron Sage | Flowing Mercy, Deep Mantra; Kindled Breath, Mantra of Stone | the existing second healer | heals while fighting | modest damage | healing, vitality |
| **Reliquary Keeper** (new) | Templar | Sentinel | Reliquary Vow, Bastion; Reliquary Censer; Rebuke, Lay on Hands | a guardian relic heals and buffs the party and burns the pack | the best party support of the line | own damage 10% lower | 300: magic level and holy nodes. 1000: the Censer |
| **Iron Pilgrim** (new) | Templar, or any but Monk | Templar or Sentinel | Open Hand Creed; Knuckles of the Unbound; a shield; Radiant Smite, Consecration | bare fists and a shield; Radiant Strikes ride on every punch | no weapon to chase; strong shield play | the Warrior's skill spells see no weapon | 300: fist skill trains with use. 1000: the Knuckles |
| Holy area | Templar | Inquisitor | Divine Verdict, Burning Zeal; Judgement, Purging Nova, Zealotry | the existing holy area | area with self heals | needs a group to shine | holy nodes |

Cross-line picks: Sanguine Covenant, Thornbound Oath and Cascade Edge are open to every class. Pyre Oath also suits
the Templar line. Aether Edge also suits the Inquisitor.

## Leveling notes

- Keystones need their paths. The leaves at 8 or 9 points are early picks; 253, 262, 355 and 362 take 18 to 21.
- Uniques drop from monsters of their themes. The Codex lists where. Two of them work without the keystone.
- A changed tree is a respec. The free refund only covers the twelve converted leaves, once.

## What the engine allows, and what is left out

- Everything here is Lua on the current engine. No new source patch.
- A real spell fired by a critical hit: the engine has no Lua call that casts a spell by name. Cascade Edge releases its own
  elemental burst instead. A patch for a real spell cast was looked at and not made: it would skip mana, cooldowns
  and the spell checks, so each trigger would need its own rules.
- Traps and mines, aura stacking with reserved mana and a build that lives on its energy shield alone need new spells or a reserve
  system. They are not in this round.
- Effigies are summons that cannot move or be attacked. Monsters ignore them.
