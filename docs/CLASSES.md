# Classes (design, agreed; phase 1, the Thief line, implemented)

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

## Implementation status

### Phase 1 (done): class framework and the Thief line

- **Vocations** (`server/data/XML/chaos_vocations.xml`, installed by `server/tools/add_vocations.py DATA_DIR [--dry-run]`):

  | id | Name | from | client byte | hp / mana / cap per level | attackspeed | base speed | melee / dist damage |
  |---|---|---|---|---|---|---|---|
  | 11 | Thief | 11 | 6 | 12 / 10 / 22 | 1600 | 230 | 1.2 |
  | 12 | Ninja | 11 | 16 | 12 / 10 / 22 | 1400 | 232 | 1.2 |
  | 13 | Samurai | 11 | 26 | 13 / 9 / 24 (defense / armor 1.1) | 1800 | 230 | 1.3 |

  Skills: swords 1.1 (like the Knight), distance 1.2, other melee 1.3, magic level 2.0. The tool also adds the line to the
  vocation lists of one-handed swords and throwing weapons (`weapons.xml`, hand equip in `movements.xml`) and to everything else the
  Paladin may wear. `server/src-patches/0002` scales a weapon's own attack speed by the vocation's (x attackspeed / 2000), so the line
  stays fast with high-level weapons, and lets a Ninja hold a one-handed sword in the shield hand.
- **Ascension** (`server/data/scripts/chaos/ascension.lua`, rules in `classes.lua`, numbers in `Chaos.classes.ascension`):
  `!ascend ninja|samurai`, level 100+, in a protection zone, out of combat. It sets the vocation directly (the engine's single
  promotion per vocation is not used), recounts health / mana / capacity and resends the vocation to the client (no relog). Final:
  `!ascend` refuses an ascended character; only the store's Vocation Change (`!changevocation ninja|samurai`) changes it. The table
  `Chaos.classes.ascension.choices` is keyed by base vocation, so the other base classes are added there in phase 2.
- **Client** (`client/base-patches/0016-chaos-vocation-ids.patch`): bytes 6 / 16 / 26 become server ids 11 / 12 / 13; Thief, Ninja and
  Samurai are named wherever the client names vocations; the helper treats the line as its class 6.
- **Kit**: 9 spells (ids 236, 238-245; `server/data/spells/chaos/thief|ninja|samurai`), evasion, stealth, Poison Blades, scripted dual
  wield, counter stance, Bushido stacks (`server/data/scripts/chaos/thief_combat.lua`). Spells, numbers and the balance measurement
  are in `server/data/spells/README.md` ("Thief line"). Shurikens are the base server's throwing star (2399) and assassin star (7368),
  open to every vocation already; the shuriken spells use them when they are in hand.

Limits of phase 1:
- Stealth is scripted: monsters drop the player and cannot attack it while it lasts, but area attacks aimed at someone else still hit
  (and end it). A monster that sees invisible creatures is handled the same way.
- Dual wield needs the engine patch; without it a Ninja fights with one blade and gets no off-hand strike. Both blades' item bonuses
  count. A character that stops being a Ninja keeps a sword already in the shield hand until it moves it (it then cannot put it back).
- The line has no healing spells of its own and the base server's potions script (`actions/scripts/other/potions.lua`) does not list
  vocations 11-13, so the strongest potions refuse them; the shared Chaos spells (Flickerdash, Banner Call, Soulward, Hunter's
  Instinct) and the stock spells do not list the line either. These were left alone in phase 1 (existing spells and base scripts).
- Spell strikes have a level factor (`Chaos.classes.spellLevelScale`) that stands in for the missing passive tree.

### Phase 2 (todo)

- Move Knight / Paladin / Sorcerer / Druid / Illusionist onto the framework: base vocations Warrior / Ranger / Mystic with
  `Chaos.classes.ascension.choices` entries, the migration table above, `Chaos.shopServices.vocations` words, the client names.
- **TODO: passive tree for the Thief, Ninja and Samurai** (`game_passivetree`, `passivetree_data.lua`, `passivetree*.lua`,
  `server/tools/gen_passivetree_data.lua`): a Thief start and two ascended paths with keystones (Ninja: off-hand share, evasion,
  shadow; Samurai: crit, parry, Bushido). Until then the vocation has no class entry in the tree. When it exists, re-tune or drop
  `Chaos.classes.spellLevelScale` and measure again at levels 300 and 1000.
- Healing for the Thief line (a spell or the potions script's vocation lists), the shared Chaos spells' vocation lists, a new-player
  kit and starting gear, outfits, the Thief line in `admin/testkit.lua`.

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
