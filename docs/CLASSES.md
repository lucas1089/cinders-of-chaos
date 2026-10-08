# Classes (design, agreed; not implemented yet)

Four base classes. At promotion each picks one of two ascended classes, like Path of Exile ascendancies.
The Necromancer is planned as a fifth class once the first eight ascended classes are balanced.

| Base class | Plays as | Ascended choice A | Ascended choice B |
|---|---|---|---|
| **Warrior** | melee, heavy armour, most health | **Juggernaut**: tank. Taunts, damage reduction, shield block/reflect | **Berserker**: two-handed area damage. Cleave, rage that grows as health drops |
| **Ranger** | bows and crossbows | **Deadeye**: top single-target damage. Crossbow, marks, crit | **Beastmaster**: pets that fight beside you, bow with arrow splash |
| **Mystic** | spells, wands and rods | **Elementalist**: top area damage. Fire/ice/energy combos | **Illusionist**: support. Buffs the party's attack, weakens targets, some healing |
| **Thief** | fast light-weapon attacks, shurikens, stealth | **Ninja**: dual-wields daggers, very fast hits, shadow step | **Samurai**: one katana-style sword, slower heavy strikes, counters and parries |

Planned fifth class: **Necromancer**, a summoner with a capped army of skeletons and spirits, corpse explosions and curses.

## Roles in a group

- Tank: Juggernaut
- Single target: Deadeye, Ninja, Samurai
- Area damage: Elementalist, Berserker
- Support: Illusionist (party attack), with healing from Illusionist spells and potions
- Pets: Beastmaster (later also the Necromancer)

Balance target, as today: Deadeye best single target, Elementalist best area damage, Juggernaut the tankiest;
a party with an Illusionist out-damages the same party without one.

## Class kits (first draft)

**Thief** (base): fast attack speed with daggers and light swords; shurikens as a throwing weapon with a
short range; **Shadow Veil** stealth (monsters lose track of you, broken by attacking; the first hit out of
stealth crits); poison blades; evasion (dodge chance).
- **Ninja**: dual wield, where the off-hand dagger adds a second, weaker strike on each attack (scripted:
  the engine has no dual wield); Shadow Step (teleport behind the target); smoke bomb (area blind); a
  shuriken barrage that hits several targets.
- **Samurai**: one sword; Iaijutsu (charged draw strike, big single hit); counter stance (parry the next melee
  hit and strike back); Bushido focus (crit stacks while not taking damage).

**Warrior** (base): today's Knight kit.
- **Juggernaut**: Iron Will, Bulwark (block/reflect), taunts.
- **Berserker**: Cleaving Arc (two-handed hits strike everything adjacent), rage.

**Ranger** (base): today's Paladin kit.
- **Deadeye**: crossbow, Final Verdict, marks.
- **Beastmaster**: a wolf/bear companion that scales with level, arrow splash, Ricochet.

**Mystic** (base): the shared caster kit.
- **Elementalist**: today's Sorcerer area spells, plus Arcane Echo.
- **Illusionist**: party attack buffs (Inspiring Illusion, Shared Phantasm), target debuffs, and Druid-style
  heals (Purifying Wellspring, Verdant Sanctuary).

## How existing characters move over

| Today | Becomes |
|---|---|
| Knight / Elite Knight | Warrior / Juggernaut, with a free switch to Berserker |
| Paladin / Royal Paladin | Ranger / Deadeye, with a free switch to Beastmaster |
| Sorcerer / Master Sorcerer | Mystic / Elementalist |
| Druid / Elder Druid | Mystic / Illusionist |
| Illusionist / Arch Illusionist | Mystic / Illusionist |

The store's vocation change token and `!changevocation` must learn the new names. Passive trees reset once,
for free, at the migration.

## Technical plan

- **Vocations** (`data/XML/vocations.xml`):
  - 4 base + 8 ascended (+ the Necromancer later).
  - The engine supports one promotion per vocation, so the A/B choice is made by script at an ascension NPC
    or shrine.
  - The client gets the names through `client/base-patches/0016-chaos-vocation-ids.patch`.
- **Engine gaps, all scripted:**
  - dual wield: off-hand strike on weapon hits, through the existing `weapon_styles.lua` hook
  - stealth: a condition, plus a monster target-drop when the player is in stealth; broken on attack or when
    hit
  - shurikens: a throwing weapon in `items.xml`, using generated sprites
  - pets and summons: capped summons; their damage counts for the owner
  - counter/parry: an `onHealthChange` window after the stance spell
- **Content per class:**
  - spells (`server/data/spells/chaos/<class>/`)
  - a passive tree (`game_passivetree`, `passivetree_data.lua`)
  - generated spell icons and effects
  - outfits: pick existing 10.98 looks first; new art later
  - starting gear and a new-player kit
- **Balance:** measure every class with the dummy harness at levels 300 and 1000, like the current tables in
  `server/data/spells/README.md`.

## More class ideas for later

- **Warlock / Hexblade**: curses and damage over time, life drain; melee caster.
- **Monk**: fists, combo points, chi that heals or empowers the next strike (the client has a free sixth
  vocation slot).
- **Templar**: holy melee with a party defence aura; a tank-support alternative to the Juggernaut.
- **Shaman**: totems that pulse buffs, heals or damage in an area; a stationary support.
- **Blood Knight**: spells cost health instead of mana; huge life leech; high risk, high reward.
- **Chronomancer**: slows, hastes and rewinds (restore health and position from 3 seconds ago).
- **Engineer / Gunslinger**: turrets, traps and a heavy ranged weapon (needs new art).
- **Spellblade**: melee hits charge spell power, and spells empower the next weapon hits.
