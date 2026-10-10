# Classes (design, agreed; phase 1, the Thief line, and phase 2a, the other three lines, implemented; the Necromancer, Monk and Templar built, phase A)

Four base classes. At promotion each picks one of two ascended classes, like Path of Exile ascendancies.
The Necromancer, the Monk and the Templar are classes five to seven (tested in game, phase B: level 300 measured); they are
locked behind a store unlock for now (see "Class lock").

| Base class | Plays as | Ascended choice A | Ascended choice B |
|---|---|---|---|
| **Warrior** | melee, heavy armour, most health | **Juggernaut**: tank. Taunts, damage reduction, shield block/reflect | **Berserker**: two-handed area damage. Cleave, rage that grows as health drops |
| **Ranger** | bows and crossbows | **Deadeye**: top single-target damage. Crossbow, marks, crit | **Beastmaster**: pets that fight beside you, bow with arrow splash |
| **Mystic** | spells, wands and rods | **Elementalist**: top area damage. Fire/ice/energy combos | **Illusionist**: the best healer, plus party attack buffs. Mirror Mend, Lucid Reverie, weakens targets |
| **Thief** | fast light-weapon attacks, shurikens, stealth | **Ninja**: dual-wields daggers, very fast hits, shadow step | **Samurai**: one katana-style sword, slower heavy strikes, counters and parries |
| **Necromancer** | summoner: skeletons and spirits, curses, corpses | **Lich**: curses, damage over time, life drain, corpse explosion; one strong shade or none | **Bone Lord**: the army: more skeletons, the Bone Golem, an aura, sacrifices |
| **Monk** | unarmed (or a staff), chi / combo points, evasion | **Shadowfist**: single-target burst. Pressure Points, Flurry, crits from spent chi | **Iron Sage**: bruiser and support. Chi Ward on a party member, stuns, Mantra of Stone aura |
| **Templar** | holy melee: sword or mace and shield, heavy armour, a party defence aura | **Inquisitor**: holy area damage. Judgement, Purging Nova, Zealotry | **Sentinel**: tank-support. A stronger aura with regeneration, Rebuke (taunt), Aegis of Faith, Lay on Hands |

## Roles in a group

- Tank: Juggernaut; Sentinel (tank-support: a little less tough, the party takes less damage); Iron Sage (off-tank, party
  chi shield and damage-reduction aura)
- Single target: Deadeye, Ninja, Samurai, Lich, Shadowfist
- Area damage: Elementalist, Berserker, Bone Lord, Inquisitor
- Healer and support: Illusionist (the best healer, for one ally and for the party, plus party attack buffs); the Templar
  line's aura (all three: party damage reduction; the Sentinel's also heals, and Lay on Hands is the biggest emergency heal)
- Pets: Beastmaster, Bone Lord (the army)

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
- **Illusionist**: the best healer, plus party attack buffs (Inspiring Illusion, Shared Phantasm: party members also heal
  for 4% of what they deal to a marked enemy), target debuffs. Heals: Weaver's Grace (passive: +5% on heals on other
  players), Mirror Mend (the most hurt ally, a mirror heals the next), Lucid Reverie (party heal over time), and the
  Druid-style heals (Purifying Wellspring, Verdant Sanctuary). See "Illusionist healer pass" below.

**Necromancer** (base): Raise Dead (skeletons from empty corpses, or one from nothing for twice the mana), Bone Spear
(the filler; pierces to the creature behind), Withering Curse (the target takes +15% damage and rots). Minions hit as
their owner, so their damage counts for it.
- **Lich**: Soul Rot (a DoT that jumps when the host dies), Life Siphon (heals half the damage), Corpse Explosion; the
  curse is stronger (+25%) and spreads to 2 more. One Lich Shade (ranged death bolts) instead of skeletons, and Soul Hoard:
  +25% spell damage while the shade slot is empty.
- **Bone Lord**: 5-6 skeletons whose hits splash onto the enemies next to the target, the Bone Golem (slams, taunts),
  Banner of Bones (minion aura), Bone Offering (a skeleton bursts; a bone shield for the Bone Lord).

**Monk** (base): fights unarmed (or with a staff), builds chi with basic strikes (max 5) and spends it on finishers that
grow with the chi spent; evasion; light armour.
- **Shadowfist**: Pressure Points (a stacking debuff: the target takes more from Monks), Shadowfist Flurry (2 + 1 hit per chi),
  focus: after a finisher, crit chance 2.5% per chi spent for 4 s (12.5% at 5 chi).
- **Iron Sage**: Chi Ward (an absorb shield on a party member or itself), Iron Palm (a stun), Mantra of Stone (party aura: -8%
  damage taken), Kindled Breath also heals over time; more health and armour.

**Templar** (base): holy melee with a one-handed sword or mace and a shield; a party defence aura and Radiant Strikes (each
melee hit adds a holy strike). Radiant Smite, Consecration, Vow of Mending.
- **Inquisitor**: Judgement (the target takes +20% holy damage), Purging Nova (holy area that heals a little), Zealotry
  (stacking damage while hitting).
- **Sentinel**: a stronger aura with regeneration, Rebuke (taunt), Aegis of Faith (-40% damage taken with a shield), Lay on Hands.

## How existing characters move over

| Today | Becomes |
|---|---|
| Knight / Elite Knight | Warrior / Juggernaut, with a free switch to Berserker |
| Paladin / Royal Paladin | Ranger / Deadeye, with a free switch to Beastmaster |
| Sorcerer / Master Sorcerer | Mystic / Elementalist |
| Druid / Elder Druid | Mystic / Illusionist |
| Illusionist / Arch Illusionist | Mystic / Illusionist |

The store's vocation change token and Character > Services must learn the new names. Passive trees reset once,
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
  - starting gear and a new-player kit: done in `newplayer_config.lua`, keyed by these class ids. A new class adds a row there or
    calls `ChaosNewPlayer.setKit(name, def, {ids})`; `ChaosNewPlayer.kitFor(vocationId)` returns a class's kit (own row, then its
    base class, then `default`). See server/README.md "New players".
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
  the Ascendant Oracle, level 100+, in a protection zone, out of combat. It sets the vocation directly (the engine's single
  promotion per vocation is not used), recounts health / mana / capacity and resends the vocation to the client (no relog). Final:
  the Ascendant Oracle refuses an ascended character; only the store's Vocation Change (`Character > Services ninja|samurai`) changes it. The table
  `Chaos.classes.ascension.choices` is keyed by base vocation, so the other base classes are added there in phase 2.
- **Client** (`client/base-patches/0016-chaos-vocation-ids.patch`): bytes 6 / 16 / 26 become server ids 11 / 12 / 13; Thief, Ninja and
  Samurai are named wherever the client names vocations; the helper treats the line as its class 6.
- **Kit**: 9 spells (ids 236, 238-245; `server/data/spells/chaos/thief|ninja|samurai`), evasion, stealth, Poison Blades, scripted dual
  wield, counter stance, Bushido stacks (`server/data/scripts/chaos/thief_combat.lua`). Spells, numbers and the balance measurement
  are in `server/data/spells/README.md` ("Thief line"). Shurikens are the base server's throwing star (2399) and assassin star (7368),
  open to every vocation already; the shuriken spells use them when they are in hand.
- **Outfits** (look types 1505-1510, from a third donor sprite set, see `server/data/monster/CUSTOM_MONSTERS.md`): Ninja gets
  Shadow Ninja, Crimson Ninja and Masked Ninja (colourable); Samurai gets Oni Samurai, Ronin and Dark Samurai. Ascending gives the
  class's three and puts on the first; characters already in the class get them at their next login (look unchanged). They stay
  after a class change. List in `Chaos.classes.outfits` (`chaos_constants.lua`), code in `ascension.lua`
  (`giveClassOutfits`), outfits.xml entries for both sexes by `server/tools/install_outfits.py` (install step `outfits`).

Limits of phase 1:
- Stealth is scripted: monsters drop the player and cannot attack it while it lasts, but area attacks aimed at someone else still hit
  (and end it). A monster that sees invisible creatures is handled the same way.
- Dual wield needs the engine patch; without it a Ninja fights with one blade and gets no off-hand strike. Both blades' item bonuses
  count. A character that stops being a Ninja keeps a sword already in the shield hand until it moves it (it then cannot put it back).
- The line has no healing spells of its own. Potions: since the class pass of 2026-10 `add_vocations.py` adds the line (11-13) to
  the Royal Paladin's potion lists (the line wears what the Paladin wears; see "Item, spell and potion lists"); before, the
  strongest potions refused it. The shared Chaos spells (Flickerdash, Banner Call, Soulward, Hunter's
  Instinct) and the stock spells do not list the line either. These were left alone in phase 1 (existing spells and base scripts).
- Spell strikes have a level factor (`Chaos.classes.spellLevelScale`) that stands in for the missing passive tree.

### Phase 2a (done): Warrior, Ranger and Mystic on the framework, the migration, Berserker and Beastmaster

- **Vocation ids** (`server/data/XML/chaos_vocations.xml`, installed by `server/tools/add_vocations.py`). Ids that map 1:1 keep their
  number, so items, spells, NPCs, potions and the database keep working; 2, 6 and 9 are retired (gone from `vocations.xml`, their
  characters moved by the migration below). The client byte is the base slot + 10 for the first ascended class, + 20 for the second.

  | id | Class | base (fromvoc) | was | client byte | hp / mana / cap per level | weapon hits | keystone variant |
  |---|---|---|---|---|---|---|---|
  | 4 | Warrior | 4 | Knight | 1 | 15 / 5 / 25 | 1.0 | knight |
  | 8 | Juggernaut | 4 | Elite Knight | 11 | 15 / 5 / 25 | 1.0 | knight |
  | 14 | Berserker | 4 | (new) | 21 | 14 / 6 / 25, defense / armor 0.9 | melee 1.05 | knight |
  | 3 | Ranger | 3 | Paladin | 2 | 10 / 15 / 20 | 1.0 | paladin |
  | 7 | Deadeye | 3 | Royal Paladin | 12 | 10 / 15 / 20 | 1.0 | paladin |
  | 15 | Beastmaster | 3 | (new) | 22 | 11 / 14 / 21 | distance 0.9 | paladin |
  | 1 | Mystic | 1 | Sorcerer | 3 | 5 / 30 / 10 | 1.0 | sorcerer |
  | 5 | Elementalist | 1 | Master Sorcerer | 13 | 5 / 30 / 10 | 1.0 | sorcerer |
  | 10 | Illusionist | 1 | Arch Illusionist | 23 | 7 / 27 / 12 | 1.0 | illusionist |
  | 11 / 12 / 13 | Thief / Ninja / Samurai | 11 | (phase 1) | 6 / 16 / 26 | see phase 1 | | none yet |
  | 2, 6, 9 | retired (Druid, Elder Druid, Illusionist) | | | | | | |

  Not used by the class rework (reserved for parallel work): vocation ids 17-25, client byte slots 7, 8 and 9, spell ids 63-74,
  180-191, 198-199 and 250-253.
- **Item, spell and potion lists** (`add_vocations.py`, once, marked by a comment after the root tag): every `<vocation>` list of the
  stock `spells.xml`, `weapons.xml` and `movements.xml` is rewritten: Knight -> Warrior, Juggernaut, Berserker; Elite Knight ->
  Juggernaut, Berserker; Paladin -> Ranger, Deadeye, Beastmaster; Royal Paladin -> Deadeye, Beastmaster; Sorcerer -> Mystic,
  Elementalist; Master Sorcerer -> Elementalist; Druid -> Mystic, Illusionist; Elder Druid -> Illusionist; Illusionist (old 9) ->
  Mystic, Illusionist; Arch Illusionist -> Illusionist. The Berserker is only added to two-handed swords, axes and clubs among the
  weapons and hand items and never to shields; the Beastmaster only to bows and arrows among weapons, hand items and ammunition.
  `potions.lua`: a potion of the Elite Knight (8) also lists the Berserker (14), one of the Royal Paladin (7) the Beastmaster (15),
  the Thief line (11-13) and the Monk line (17-19), one of either the Templar line (23-25), one of the Elementalist (5) the
  Necromancer line (20-22); the refusal texts name our classes ("Only Warriors and Templars of level 80 or above may drink this
  fluid."). The mastermind potion (`strengthening_potions.lua`, `Player.isMage`: Sorcerer and Druid ids only) also takes the
  Illusionist and the Necromancer line ("Only Mystics and Necromancers ..."). Unit test `server/tests/potions_patch_test.lua`;
  in game: a Ninja, a Necromancer and a Templar drink theirs and are refused the others;
  `lib/core/player.lua`: `Player.isKnight` / `isPaladin` count them too. Weapons without a vocation list stay open to everyone.
- **Ascension**: the Ascendant Oracle (Warrior), `deadeye|beastmaster` (Ranger), `elementalist|illusionist` (Mystic),
  `ninja|samurai` (Thief); level 100, protection zone, out of combat, final. The store's Character > Services takes the new words
  (`warrior|juggernaut|berserker|ranger|deadeye|beastmaster|mystic|elementalist|illusionist|thief|ninja|samurai`; the base word asks
  an ascended character to name the ascended class). The passive tree's keystone variant follows the line
  (`ChaosClasses.keystoneKey`): Warrior line knight, Ranger line paladin, Mystic / Elementalist sorcerer, Illusionist illusionist;
  the druid variants (Overgrowth, Thorns) belong to no class now.
- **Migration** (`server/data/scripts/chaos/class_migration.lua`, rules in `classes.lua`, numbers in `Chaos.classes.migration`):
  at startup, once (server_config `chaos_class_migration` = 1), before anyone can log in, it runs `ChaosClasses.migrationSql`:
  1. `player_storage` 7100202 = the old vocation, for every character of vocations 1-10;
  2. `player_storage` 7100203 = 14 for old Elite Knights, 15 for old Royal Paladins (the free switch);
  3. their passive tree presets are emptied (free reset);
  4. `UPDATE players SET vocation = 1 WHERE vocation = 2`, `= 10 WHERE vocation = 6`, `= 1 WHERE vocation = 9`.
  At the next login health, mana and capacity are recounted from the new gains when they changed (old Druid / Illusionist gains are in
  `oldGains`), and the player gets a message and a popup: what the vocation became, that the tree was reset, the free switch
  (the Ascendant Oracle / the Ascendant Oracle, once, any level, protection zone, out of combat) or, for a base class, the ascension
  words. The store's vocation change spends the free switch. Old Knights / Paladins (unascended) simply choose at the Ascendant Oracle.
- **Kits**: see `server/data/spells/README.md` ("Classes"). New: Berserker Rage (passive), Skyfall Cleave (246), Bloodrage (247);
  Beastmaster companion (War Wolf, else Wolf), Wild Bond (248), Feral Command (249).
- **Client** (`client/base-patches/0016-chaos-vocation-ids.patch`): the class byte maps to the server ids (1/11/21 -> 4/8/14, 2/12/22 ->
  3/7/15, 3/13/23 -> 1/5/10, 6/16/26 -> 11/12/13; the retired druid / illusionist bytes read as Mystic / Illusionist); the names, the
  item / market / wheel mappings, `Creature:isKnight/isPaladin/isSorcerer/isDruid`, and the helper (its class 1 is the Warrior line, 2
  the Ranger line, 3 Mystic / Elementalist, 4 the Illusionist with the druid's heals, 6 the Thief line). `game_chaosspells` adds the
  Mystic / Illusionist / Berserker / Beastmaster to the client's stock spell entries (druid spells -> Mystic, Illusionist; knight
  spells -> Berserker; paladin spells -> Beastmaster) so the spell list matches the server.

Tested on the test server: the migration on 12 characters of the old vocations 1-10 (SQL result checked, storages, trees, the retired
ids), the login popup of an old Elite Knight and of an old (level 150) Illusionist (health 895 / mana 4350 recounted from the Mystic's
gains), the free switch (refused outside a protection zone, refused for another line's class, then Juggernaut -> Berserker), casting
Wild Bond by its words, and the level 1000 sanity measurement in `server/data/spells/README.md`.

### Necromancer (C5, phase B: tested in game)

- **Vocations** (`server/data/XML/chaos_vocations_necro.xml`, installed with the other classes by
  `server/tools/add_vocations.py DATA_DIR`): 20 Necromancer (client byte 7; hp 8 / mana 26 / cap 13), 21 Lich (17; 7 / 28 / 12),
  22 Bone Lord (27; 9 / 24 / 15, defense / armor 1.05). Skills and magic level like the Mystic; the casters' wands, rods,
  gear, stock heals and mana potions (`add_vocations.py`). Locked behind the store's class unlock (`class_unlocks.lua`,
  key "necromancer").
- **Ascension**: the Ascendant Oracle (`Chaos.classes.ascension.choices[20]`).
- **Kit**: 9 spells (ids 180-188; `server/data/spells/chaos/necromancer|lich|bonelord`, helpers `_necro.lua`);
  minions `necro_minions.lua`, curse and bone shield `necromancer_combat.lua`, engine helpers `necro_lib.lua`, pure
  rules `necro_core.lua` (tests `server/tests/necro_test.lua`), numbers `necro_config.lua`; minion monsters
  `server/data/monster/monsters/chaos/necro_*.xml` (looks: skeleton 33, ghost 48, demon skeleton 37). New-player kit: the
  Mystic's (`newplayer_config.lua`).
- **Summons**: capped per class and level, scale with the owner's level and magic level, follow (brought back past
  7 sqm or across floors), rest in protection zones and rise outside, go at logout and death, pushable. Their hits are
  dealt as the owner (full experience, the Chaos loot layer, bounty / leaderboard / hunt credit through the owner);
  the engine alone would credit a summon's share at half experience and skip the rarity loot when a summon lands the
  last hit (`Creature::onGainExperience`, `Monster::dropLoot`).
- **Balance**: planned numbers in `server/data/spells/README.md` ("Necromancer line"); measured in phase B.

Open for the Necromancer:
- **Passive tree for the Necromancer, Lich and Bone Lord** (a start and two ascended paths with keystones:
  Lich: curse / DoT / Soul Hoard; Bone Lord: army size / aura / golem). The tree has per-vocation keystone variants
  only (`ChaosClasses.keystoneKey`), no per-class starts yet, so the line has no tree entry, like the Thief line.
  Until then `necro_config.lua levelScale` stands in for it.
- New effects (`bone_spear`, `bone_burst`, `bone_aura`) are proposed, not generated; the spells use existing ones.
- Outfits, the line in `admin/testkit.lua`.
- Minions in the arena, the guild siege and rifts follow those modes' summon rules (not checked).

### Monk (C6, phase B: tested in game)

- **Vocations** (`server/data/XML/chaos_vocations_monk.xml`, installed by `add_vocations.py`):

  | id | Name | from | client byte | hp / mana / cap per level | attackspeed | base speed | fist hits |
  |---|---|---|---|---|---|---|---|
  | 17 | Monk | 17 | 8 | 12 / 10 / 22 | 1500 | 230 | x1.2 |
  | 18 | Shadowfist | 17 | 18 | 12 / 10 / 22 | 1300 | 232 | x1.2 |
  | 19 | Iron Sage | 17 | 28 | 14 / 9 / 25 (defense / armor 1.15) | 1700 | 228 | x1.1 |

  Skills: fist fighting and club 1.1, sword / axe / distance 1.3, shielding 1.2 (Iron Sage 1.1), magic level 2.0. the Ascendant Oracle
  at level 100. All ids (vocations, client bytes, spells 63-72, storages 7100800-7100809, condition sub ids 71030-71044, opcode 247) are in
  `ChaosMonk.ids` (`server/data/scripts/chaos/monk_chi_core.lua`). Equipment (`add_vocations.py`): two-handed clubs (staves) and
  whatever the Ranger may wear; the Royal Paladin's potions. New-player kit: light armour, no weapon.
- **Unarmed combat on this engine**: without a weapon the engine hits with fists (`Weapon::useFist`): fist fighting skill, a fixed attack
  value of 7, the vocation's attackspeed (minus the dexterity stat), the usual weapon formula and the fight mode factor, but **not** the
  vocation's meleeDamage multiplier, and there is no "fist" weapon type in the item types. So the Monk's unarmed damage is scripted on the
  weapon hook, without an engine patch: `monk_combat.lua` scales a Monk's fist hit (melee origin, nothing in the hands) by (formula with
  the Monk's fist attack x meleeDamage) / (formula with attack 7). The fist attack grows with level: 40 + level x 0.025, at most 60
  (level 300: 47.5). Fist weapons: listed in `ChaosMonk.cfg.unarmed.fistWeapons` (none exist yet: they need new items). Staves are
  ordinary weapons (club skill, the two-handed factor of `weapon_styles.lua`, the attack speed patch 0002).
- **Chi**: a player storage (shared by the spells' and the scripts' Lua states) with the time of its last change; gone after 12 s untouched.
  +1 per melee hit (at most one per 2 s), +2 Ashen Fist, +1 Pressure Points; a finisher needs 1 chi and spends all of it, x(0.30 + 0.14 per
  chi) of its 5-chi value. HUD: client module `game_monkchi` (5 pips; extended opcode 247).
- **Kit**: 10 spells (ids 63-72; `server/data/spells/chaos/monk|shadowfist|ironsage`, helpers `_monk.lua`), evasion (6% / 8% / 4%, +25% for
  2 s after Mistborne Step), the Shadowfist focus crit, Pressure Points, Chi Ward, Mantra of Stone and the Iron Palm stun in
  `monk_combat.lua`. Spells, numbers and the estimate are in `server/data/spells/README.md` ("Monk line"). Unit tests: `server/tests/monk_test.lua`,
  `client/overlay/modules/game_monkchi/chimath_test.lua`.

Open for the Monk:
- Balance: measured at level 300 (`server/data/spells/README.md` "Monk line"): the Shadowfist was ~26% above the Ninja on one
  target (the focus crit, 8% per chi, on the auto attack); with 2.5% per chi it is 1078 against the Ninja's 1001 (+8%, a
  burst class's lead). Level 1000 by formula only (~3060 against the Ninja's 2837), not measured yet.
- **Passive tree**: no per-class trees exist yet. Proposal when the tree is reworked: a Monk start, a Shadowfist path ending in a keystone
  "Hundred Hands" (focus crits also add a chi) and an Iron Sage path ending in "Stone Body" (Chi Ward on yourself is 50% stronger and
  Mantra of Stone also gives 10% attack speed). Until then `keystoneKey` is nil for 17-19 and the level factor stands in for the tree.
- Fist weapons (new items), outfits, a stun on players (only monsters are stunned), the line in `admin/testkit.lua`.

### Templar (C7, phase B: tested in game)

Holy melee with a party defence aura; the tank-support alternative to the Juggernaut. Ascension with the Ascendant Oracle
at level 100+ (the same rules as the other classes).

| id | Name | client byte | hp / mana / cap per level | weapon hits | defense / armor |
|---|---|---|---|---|---|
| 23 | Templar | 9 | 14 / 8 / 25 | 1.0 | 1.05 |
| 24 | Inquisitor | 19 | 13 / 10 / 24 | 1.0 | 1.0 |
| 25 | Sentinel | 29 | 14 / 7 / 25 | 0.9 | 1.15 |

Skills: sword and club 1.1 (as the Warrior), axe and fist 1.2, distance 1.4, shielding 1.1, magic level 2.5. Equipment
(`server/data/XML/chaos_vocations_templar.xml`, installed by `add_vocations.py`): one-handed swords and clubs, shields,
everything the Warrior wears; potions of the Elite Knight and the Royal Paladin. New-player kit: the Warrior's.

**Kit** (9 spells, ids 189-191, 198, 199, 250-253; numbers in `server/data/spells/README.md`, "Templar line"):
- Passive, all three: **Defence aura**. Every second each Templar-line player covers itself and its party members on its floor
  within range: Templar 4 sqm, -6% damage taken; Inquisitor 3 sqm, -4%; Sentinel 5 sqm, -12% and 0.4% of the maximum health
  regenerated per second. Auras do not stack (the strongest counts). **Radiant Strikes**: every melee weapon hit is followed by a
  holy strike for 15% of it (Inquisitor 25%, Sentinel 10%); monster holy resistances apply.
- Templar (all three): Radiant Smite (holy strike, range 3), Consecration (holy ground for 6 s, heals allies in it), Vow of
  Mending (self heal).
- Inquisitor: Judgement (holy strike; the target takes +20% holy damage from everyone for 8 s), Purging Nova (holy circle of
  3 sqm, heals 10% of the damage dealt, at most 5% max health per cast), Zealotry (20 s: each melee hit adds a stack, +4%
  damage per stack up to +40%, gone 3 s after the last hit).
- Sentinel: Rebuke (taunt within 4 sqm, 25% slow), Aegis of Faith (with a shield: -40% damage taken for 5 s), Lay on Hands
  (a party member or itself within 5 sqm: 35% of its maximum health + magic level x 10; 60 s cooldown).

Files: `templar_aura_core.lua` (every id and number, and the rules: aura, strikes, Judgement, Zealotry, heals; tested in
`server/tests/templar_test.lua`), `templar_combat.lua` (the aura check, onHealthChange), the spells in
`server/data/spells/chaos/templar|inquisitor|sentinel` with `_templar.lua`.

Open for the Templar:
- Passive tree: no per-class start or ascended paths yet, so the Templar has no tree entry (like the Thief line). Planned: a
  Templar start and two paths with a keystone each: Inquisitor "Divine Verdict" (Radiant Strikes have a chance to apply
  Judgement), Sentinel "Bastion" (aura +4% and +1 sqm, Aegis of Faith also covers the party at half strength). Until then the
  line's spells carry the level factor of the Thief line (x1 at level 300 to x2 at level 1000).
- Outfits, the line in `admin/testkit.lua`.
- The aura is invisible to the client except for a holy effect every 4 s around the Templar; a status icon needs client work.

### Illusionist healer pass

The owner's call: the Illusionist is the best healer class, plus party attack buffs. Done by adding to its kit, not by cutting
other classes' heals (numbers and the measurement: `server/data/spells/README.md`, "Healing"):
- **Weaver's Grace** (passive): heals the Illusionist casts on another player +5%.
- **Mirror Mend** (spell 96, `saen spek ["Name"]`): the most hurt party member within 7 sqm, and a mirror heal for 25% on the
  next most hurt. **Lucid Reverie** (spell 97, `reth vas spek`): a party heal over time (5 pulses in 10 s).
- **Shared Phantasm** (keystone): party members also heal for 4% of what they deal to the marked enemy; the +12% stays.
- **PvP**: every heal on a player in PvP combat (player damage either way in the last 10 s, a fight lock, an arena match, the
  siege arena) is -30%, for every class, so healers do not make fights endless.
- Measured lead: party healing +32% / +41% (level 300 / 1000) over the next class (the base Mystic) and +58% / +66% over the
  next ascended one (the Lich), single target on another player +22% / +33%. The Sentinel keeps the biggest emergency heal
  (Lay on Hands) and stays a tank-support, the Iron Sage a bruiser.
- Open: the Necromancer line has the Mystic's stock heals (Circle of Mending, Kindred Mend, Heartwood Embrace) and is the
  second healer through them; worth a look when that line is balanced.

### Class lock (C8: the store unlock)

The Necromancer, the Monk and the Templar can only be played on an account that has unlocked them. For now the unlock is
bought in the store (category "Classes", 750 Chaos Coins each: **a placeholder price**). The owner may change the method
later; it is one table, `ChaosClassUnlocksCore.config` in `server/data/scripts/chaos/class_unlocks_core.lua`:
per class key the vocation ids, `locked`, and the unlock methods (`store`, `level`, `quest`, `achievement`, or a new kind
registered with `registerMethod`), without touching the gate code.

- Unlocks are per account (every character), in the table `chaos_class_unlocks` (`server/sql/chaos_class_unlocks.sql`, also
  created at startup). The engine's account storage was not used: it is kept in memory and written only at server save,
  so a paid unlock could be lost by a crash.
- API (`class_unlocks.lua`, stable): `isUnlocked(player or accountId, classKey)`, `classOfVocation(vocId)`,
  `canUseVocation(player, vocId)` -> ok, message; also `grant`, `revoke`, `isRestricted`, `storeUnlock`.
- Gates: the store's Character > Services and the Ascendant Oracle refuse a locked class (the vocation change token is kept);
  the login check covers everything else (characters made on the website, staff tools): a character on a locked vocation
  logs in, goes to its temple, cannot attack and gains no experience or skills, and a window says how to unlock; the store
  works in that state, so buying the unlock ends the restriction at once. (`login.mode = "kick"` logs it out instead.)
  Staff (group 4+, or account type 5+) is never locked.
- Characters are created on the website: the base server has no account manager and no in-game character creation (the
  engine never inserts into `players`; its login only reads the character list). The website should offer the three classes
  only to accounts with a row in `chaos_class_unlocks`; the login check holds even if it does not.
- Character > Character Info shows the account's state; staff: `/classunlock <character>, <class>[, revoke]`.

### Ascension quest (C9, done)

Ascension is earned through a quest, not claimed with a command. The stock promotion is off: King Tibianus and every other
promotion NPC of the base server used to promote premium accounts at level 20 to `Vocation:getPromotion()`, which skipped the
class system and picked one of the two ascended classes more or less at random. `server/tools/patch_promotion.py` (run by
`install_class_ascension.py`) makes them refuse with a line that points to the quest (server/README.md, install step 4b).

Decided defaults (numbers in `server/data/scripts/chaos/ascension_quest_config.lua`):

- **Who**: every base class with ascension choices, at `Chaos.classes.ascension.minLevel` (100). The lines and their two ascended
  classes are read at run time from `Chaos.classes.ascension.choices`, so Warrior, Ranger, Mystic, Thief, Monk, Necromancer and
  Templar all have it, and a new line works without code changes (it gets the default guardian until it has its own entry).
- **The Ascendant Oracle**, an NPC placed next to the temple of the starting town (town 1 by default), starts and ends it.
  1. **The Calling**: talk to the Oracle ("ascension", "quest"); it describes the two paths of your class.
  2. **Proof of Strength**: 10 points from rare (1) and legendary (3) monsters at your level: the monster's hunting level
     (as the bounty pool estimates it) must be at least 0.6 x your level (a Hydra, 73, counts at level 100; a Dragon, 42, does not).
     Magic monsters, bosses and normal monsters do not count. Progress: Character > Character Info or the Oracle.
  3. **The Trial**: alone in a runtime-built room against your class's guardian, an existing monster look scaled to levels
     100-130 (6000 health at 100, x1.3 at 130 and above; its hits scale the same way), 180 seconds. The guardians and their
     mechanics: Warden of Iron (Warrior: punishes standing still, enrages), Warden of the Hunt (Ranger: hounds, punishes
     standing still), Warden of the Veil (Mystic: marked burning tiles, phantasms), Warden of Shadows (Thief: marked tiles,
     punishes standing still), Warden of the Still Fist (Monk: standing still, marked tiles), Warden of Bones (Necromancer:
     raises skeletons, marked tiles), Warden of Dawn (Templar: marked tiles, enrages). A lethal hit is caught: nobody dies in
     the Trial and nothing is lost. Death, the time limit, leaving or logging out fail the attempt; retry after 10 minutes.
  4. **The Choice**: back at the Oracle, a window lists the two ascended classes with their descriptions, then asks for a
     confirmation. The ascension is `ChaosAscension.ascend` (ascension_quest.lua): the class lock first
     (`ChaosClassUnlocks.canUseVocation`), then the existing vocation change of ascension.lua (health, mana and capacity
     recounted, the vocation resent to the client, dual wield synced). Rewards: the name plate title "Ascended <class>"
     (titles.lua), a toast and a broadcast.
- **the Ascendant Oracle** is staff-only now; players are told to speak with the Ascendant Oracle in the temple. The one free switch of
  migrated Elite Knights / Royal Paladins (the Ascendant Oracle) still works. The store's Vocation Change is unchanged
  (a character it takes back to a base class may choose again at the Oracle).
- **Existing characters**: ascended characters keep their class (and get the title). Staff can restore a character the old
  login bug demoted with `/ascendset <player>, <ascended class>` (same line only; the class lock still applies).
- Tests: `server/tests/ascension_quest_test.lua`. Tested in game: see server/README.md "Ascension quest". The guardian's numbers
  are first estimates, not yet measured against geared characters.

### Phase 2b (todo)

- **Passive tree for the Thief, Ninja and Samurai** (`game_passivetree`, `passivetree_data.lua`, `passivetree*.lua`,
  `server/tools/gen_passivetree_data.lua`): a Thief start and two ascended paths with keystones (Ninja: off-hand share, evasion,
  shadow; Samurai: crit, parry, Bushido). Until then the vocation has no class entry in the tree. When it exists, re-tune or drop
  `Chaos.classes.spellLevelScale` and measure again at levels 300 and 1000. Per-ascended keystone variants (Juggernaut vs Berserker,
  Deadeye vs Beastmaster) would need new variants in the tree data; today both classes of a line share their old vocation's.
- Healing for the Thief line (a spell; the potions are done: the Royal Paladin's), starting gear for every class,
  outfits, the classes in `admin/testkit.lua` (it already sorts Berserker / Beastmaster with the knight / paladin kits).
- The full rebalance at levels 300 and 1000 with passive trees; the client's passive tree class texts (`vocationSpecials`) still
  describe the old vocations; base server scripts that test vocation ids by number (e.g. the familiar system, `firstitems.lua`, NPCs
  with `isDruid`) were not reviewed.

## More class ideas for later

- **Warlock / Hexblade**: curses and damage over time, life drain; melee caster.
- **Shaman**: totems that pulse buffs, heals or damage in an area; a stationary support.
- **Blood Knight**: spells cost health instead of mana; huge life leech; high risk, high reward.
- **Chronomancer**: slows, hastes and rewinds (restore health and position from 3 seconds ago).
- **Engineer / Gunslinger**: turrets, traps and a heavy ranged weapon (needs new art).
- **Spellblade**: melee hits charge spell power, and spells empower the next weapon hits.
