# Classes (design, agreed; phase 1, the Thief line, and phase 2a, the other three lines, implemented; the Necromancer, Monk and Templar built, phase A)

Seven class lines: four base classes plus the Necromancer, Monk and Templar (unlocked per account at level 200). At promotion each picks one of two ascended classes, like Path of Exile ascendancies.
The Necromancer, the Monk and the Templar are classes five to seven (tested in game, phase B: level 300 measured); they are
unlocked for the account once one of its characters reaches level 200 (see "Class lock").

| Base class | Plays as | Ascended choice A | Ascended choice B |
|---|---|---|---|
| **Warrior** | melee, heavy armour, most health | **Juggernaut**: tank. Taunts, damage reduction, shield block/reflect | **Berserker**: two-handed area damage. Cleave, rage that grows as health drops |
| **Ranger** | bows and crossbows | **Deadeye**: top single-target damage. Crossbow, marks, crit | **Beastmaster**: pets that fight beside you, bow with arrow splash |
| **Mystic** | spells, wands and rods | **Elementalist**: top area damage. Fire/ice/energy combos | **Illusionist**: the best healer, plus party attack buffs. Mirror Mend, Lucid Reverie, weakens targets |
| **Thief** | fast light-weapon attacks, shurikens, stealth | **Ninja**: the line's burst single target. Dual-wields daggers, very fast hits, shadow step | **Samurai**: duelist off-tank. One katana-style sword, a counter stance that parries, guards and taunts |
| **Necromancer** | summoner: skeletons and spirits, curses, corpses | **Lich**: curses, damage over time, life drain, corpse explosion; one strong shade or none | **Bone Lord**: the army: more skeletons, the Bone Golem, an aura, sacrifices |
| **Monk** | unarmed (or a staff), chi / combo points, evasion | **Shadowfist**: single-target burst. Pressure Points, Flurry, crits from spent chi | **Iron Sage**: the second healer, a melee chi healer with some bruiser toughness. Kindled Breath on the most hurt ally, Mantra of Stone heals and shields the party, Chi Ward |
| **Templar** | holy melee: sword or mace and shield, heavy armour, a party defence aura | **Inquisitor**: holy area damage. Judgement, Purging Nova, Zealotry | **Sentinel**: tank-support. A stronger aura with regeneration, Rebuke (taunt), Aegis of Faith, Lay on Hands |

## Roles in a group

Agreed with the owner (2026-10, the role rebalance): the Iron Sage is the second healer, the Samurai a duelist off-tank.

- Tank: Juggernaut (the tankiest); Sentinel (tank-support: a little less tough, the party takes less damage); Samurai (duelist
  off-tank: parries, a guard while countering, taunts; below the Juggernaut and the Sentinel)
- Single target: Deadeye (the best), Ninja, Lich, Shadowfist (the burst classes lead), Beastmaster
- Area damage: Elementalist (the best), Berserker, Bone Lord, Inquisitor
- Healer: Illusionist (the best healer, for one ally and for the party, plus party attack buffs); Iron Sage (the second
  healer: a melee chi healer, below the Illusionist and above every non-healer); the Templar line's aura (all three: party
  damage reduction; the Sentinel's also heals, and Lay on Hands is the biggest emergency heal)
- Pets: Beastmaster, Bone Lord (the army)

Balance target, as today: Deadeye best single target, Elementalist best area damage, Juggernaut the tankiest;
a party with an Illusionist out-damages the same party without one.

## Class kits (first draft)

**Thief** (base): fights with a dagger in each hand (dual wield since 2026-10-23: the kit is two daggers, one in each hand; the
off-hand dagger adds a second strike on each hit) and attacks as fast as the Monk (1500 ms); shuriken spells with a shuriken spells with a
short range (no stars to carry); **Shadow Veil** stealth (monsters lose track of you, broken by attacking; the first hit out of
stealth crits); poison blades (a poison tick is 30% of the hit a second, the Ninja's 18%, 2026-10-17); evasion (dodge chance); Blade Flurry (a spin that strikes every monster next to you,
the line's area strike, 2026-10-15).
- **Ninja**: dual wield (as the Thief since 2026-10-23), where the off-hand dagger adds a second, weaker strike on each attack (scripted:
  the engine has no dual wield); Shadow Step (teleport behind the target); smoke bomb (area blind); a
  shuriken barrage that hits several targets.
- **Samurai** (duelist off-tank): one sword; Iaijutsu (charged draw strike, big single hit); Counter Stance (3 s: parry the
  next melee hit and strike back, every other hit taken 30% smaller, the monsters within 3 sqm turn on the Samurai);
  Bushido focus (crit stacks while not taking damage); Iaido Sweep (a wide draw cut: the target and every monster in
  the 3 x 2 tiles in front, 2026-10-15).

**Warrior** (base): today's Knight kit. The line's guard buff is Ironhold (level 55, +40% shielding for 12 s); the stock
Protector (the spell named Bulwark) it replaced was retired on 2026-10-20 because it pacified the caster for 10 s
(server/README.md "Bulwark and Windrunner retired, Ironhold and Wildstride").
- **Juggernaut**: Iron Will, Bulwark (block/reflect), taunts.
- **Berserker**: Cleaving Arc (two-handed hits strike everything adjacent), rage.

**Ranger** (base): today's Paladin kit. Bows and crossbows fire without ammunition; the off-hand holds a quiver beside the
bow or crossbow (engine src-patch 0023; bows stay two-handed, so no shield; gear with implicit and rolled modifiers that work only while a bow or crossbow is held: distance fighting, attack speed,
critical strike, extra projectiles, elemental shares; server/README.md "Infinite arrows and quivers"). The new-player kit has
the bow and no arrows. Only the Ranger, Deadeye and Beastmaster may wear quivers (the launchers' vocations). Monsters drop
bows, crossbows and quivers for them from level 1 on (server/README.md "Gear coverage"; casters get wands, rods and
spellbooks the same way), and eight Ranger-line quiver uniques fill levels 6 to 1900. Every class
wears one ring and one badge: the badge slot took the place of the second ring slot (server/README.md "Badge slot"). The line's fight buff is
Tautstring (level 60, +25% distance skill for 12 s); the stock Sharpshooter / Hawkeye it replaced was retired on 2026-10-20
because its slow kept the bow from firing (server/README.md "Hawkeye retired, Tautstring"). Its run buff is Wildstride
(level 55, +50% speed for 12 s on top of Haste) in place of the stock Swift Foot / Windrunner, retired the same day: it
pacified the caster for 10 s.
- **Deadeye**: crossbow, Final Verdict, marks.
- **Beastmaster**: a wolf/bear companion that scales with level, arrow splash, Ricochet.
  The companion (Wild Bond) and every other player summon is an ally of its owner and party: it never hits them, they never
  take it as a target, Feral Command goes at the nearest enemy when its target is an ally (server/README.md "Player summons are
  allies"). Wild Bond and Feral Command show in the action bar's and hotkeys' Assign Spell lists (client base patch 0079).
  A class change (Vocation Change, ascension) refreshes the Spellbook and takes the old class's rules out of the Helper.

**Mystic** (base): the shared caster kit.
- **Elementalist**: today's Sorcerer area spells, plus Arcane Echo.
- **Illusionist**: the best healer, plus party attack buffs (Inspiring Illusion, Shared Phantasm: party members also heal
  for 4% of what they deal to a marked enemy), target debuffs. Heals: Weaver's Grace (passive: +16% on heals on other
  players), Mirror Mend (the most hurt ally, a mirror heals the next), Lucid Reverie (party heal over time), and the
  Druid-style heals (Purifying Wellspring, Verdant Sanctuary). See "Illusionist healer pass" below.

**Necromancer** (base): Raise Dead (skeletons from empty corpses, or one from nothing for twice the mana), Bone Spear
(the filler; pierces to the creature behind), Withering Curse (the target takes +15% damage and rots), Grave Nova
(level 50, the Necromancer only: death damage on every enemy within 3 sqm of the caster, 2026-10-22). Minions hit as
their owner, so their damage counts for it. Every minion has two spells, one single target and one area (beta
2026-10-22; table in server/README.md "Necromancer summons"), and the summoned Risen Warrior taunts like the golem.
- **Lich**: Soul Rot (a DoT that jumps when the host dies), Life Siphon (heals half the damage), Corpse Explosion; the
  curse is stronger (+25%) and spreads to 2 more. One Lich Shade (ranged death bolts) instead of skeletons, and Soul Hoard:
  +25% spell damage while the shade slot is empty.
- **Bone Lord**: 5-6 skeletons whose hits splash onto the enemies next to the target, the Bone Golem (slams, taunts),
  Banner of Bones (minion aura), Bone Offering (a skeleton bursts; a bone shield for the Bone Lord).

**Monk** (base): fights unarmed (or with a staff), builds chi with basic strikes (max 5) and spends it on finishers that
grow with the chi spent; evasion; light armour.
- **Shadowfist**: Pressure Points (a stacking debuff: the target takes more from Monks), Shadowfist Flurry (2 + 1 hit per chi),
  focus: after a finisher, crit chance 2.5% per chi spent for 4 s (12.5% at 5 chi).
- **Iron Sage** (the second healer): Kindled Breath heals the most hurt party member (fist x 33 at 5 chi, +60%
  over 6 s), Mantra of Stone (party aura: -8% damage taken, and every 2 s a heal of level + fist x 26 on the party), Chi Ward
  (an absorb shield on a party member or itself), Iron Palm (a stun); more health and armour.

**Templar** (base): holy melee with a one-handed sword or mace and a shield; a party defence aura and Radiant Strikes (each
melee hit adds a holy strike). Radiant Smite, Consecration, Vow of Mending.
- **Inquisitor**: Judgement (the target takes +20% holy damage), Purging Nova (holy area that heals a little), Zealotry
  (stacking damage while hitting).
- **Sentinel**: a stronger aura with regeneration, Rebuke (taunt), Aegis of Faith (-40% damage taken with a shield), Lay on Hands.

**Runes (2026-10-13, owner: "Tire as spells de fazer runa. Deixa as runas serem de vendedores e craft.")**: no class
conjures runes any more. The stock kits of the Mystic, Elementalist, Illusionist and Ranger lose the 36 rune conjure
spells and the blank rune spell (they came from the Sorcerer, Druid, Illusionist and Paladin lists of spells.xml, which
`add_vocations.py` converts); every class still uses runes at their own level and magic level. Runes come from NPC
vendors (Raloth in Mirewake, Isora in Cinderhold, and every base rune seller) and the general crafting tables
(server/README.md "Rune supply"). No Chaos class spell, `LINE_STOCK_SPELLS` entry or tutorial class spell was a conjure
spell; `tools/ci/check_content.py` keeps it so. The other conjure spells went too (owner: "Pode tirar, já que as ammos
são infinitas"): Conjure Rations (the casters' food spell; food stays on sale at the food vendors) and the Ranger's Hallow
Spear and Charge Staff. No class conjures anything now.

**Rotations (2026-10-14, owner: "Faça todas as classes terem até 5 magias na rotação e nunca ficarem 2s sem uma")**:
every class has an attack rotation of at most 5 spells, cast as a priority list (first ready spell first), that never
leaves a window over 2 s with nothing ready (`server/tools/rotation_sim.py`; numbers in `server/data/spells/README.md`
"Rotations"). The Templar line's Radiant Smite went from 4 s to 2 s (its damage scaled down per class) and Sunder Guard's
12 s attack group lock to 2 s. Second pass: the rule holds from level 15 up (below it exempt; a class with no attack
spell yet has no rotation). The snares (Snare Trap, Seeker Mine) are in no preset: players cast them by hand.
Bonebreaker went from 6 s to 2 s (the Warrior line's only attack spell at levels 16-27, a 6 s gap), Shuriken Toss from
3 s to 2 s (damage scaled per class: Thief 1.33, Ninja 1.33 / 1.62 from level 180, Samurai 1.33 / 1.5 from level 120).
The helper's Auto rotation button sets these (client/MANIFEST.md "Helper auto rotation"); a band left out has the set
of the band before. Early (since 2026-10-17 every line starts at level 8, "Level 8 spells" below): Warrior line 8: Bonebreaker, 30:
Reaping Gyre > Bonebreaker; Thief line 8: Shuriken Toss; Ranger line 8: Phantom Javelin, 30: Dawnpiercer > Phantom Javelin. At levels 100 / 300 / 1000:
- **Warrior**: 100: Butcher's Gyre > Earthbreaker > Reaping Gyre > Scything Arc > Bonebreaker; 300: Colossus Fall >
  Earthbreaker > Scything Arc > Headsman's Hurl > Vaulting Cleave; 1000: Colossus Fall > Earthbreaker > Reaping Gyre >
  Scything Arc > Headsman's Hurl.
- **Juggernaut**: 100: Butcher's Gyre > Earthbreaker > Reaping Gyre > Scything Arc > Bonebreaker; 300: Colossus Fall >
  Earthbreaker > Reaping Gyre > Scything Arc > Headsman's Hurl; 1000: Colossus Fall > Anvil Fall > Earthbreaker >
  Scything Arc > Headsman's Hurl.
- **Berserker**: 100: Butcher's Gyre > Skyfall Cleave > Earthbreaker > Scything Arc > Bonebreaker; 300: Colossus Fall >
  Skyfall Cleave > Earthbreaker > Scything Arc > Headsman's Hurl; 1000: Colossus Fall > Rampage Leap > Earthbreaker >
  Scything Arc > Headsman's Hurl.
- **Ranger**: 100: Blessed Earth > Sanctum Burst > Skewering Line > Dawnpiercer > Phantom Javelin; 300: Radiant Shard >
  Sanctum Burst > Hail of Dawn > Skewering Line > Dawnpiercer.
- **Deadeye**: 100: Blessed Earth > Sanctum Burst > Skewering Line > Dawnpiercer > Phantom Javelin; 300: Blessed Earth >
  Hail of Dawn > Final Verdict > Skewering Line > Dawnpiercer; 1000: Blessed Earth > Hail of Dawn > Twin Verdict > Final
  Verdict > Dawnpiercer.
- **Beastmaster**: 100: Blessed Earth > Sanctum Burst > Dawnpiercer > Phantom Javelin; 1000: Blessed Earth > Sanctum
  Burst > Pack Frenzy > Dawnpiercer > Feral Command.
- **Mystic**: 100: Blightswarm > Arcane Ripple > Bewitching Hex; 300: Falling Pyre > Briar Prison > Blightswarm > Arcane
  Ripple > Bewitching Hex; 1000: Falling Pyre > Briar Prison > Blightswarm > Arcane Ripple > Shattered Psyche.
- **Elementalist**: 100: Tempest Fan > Forked Storm > Rime Bloom > Pyre Torrent; 300: Doomtide > Frozen Crypt > Falling
  Pyre > Rime Bloom > Pyre Torrent; 1000: Glacial Doom > Doomtide > Frozen Crypt > Rime Bloom > Pyre Torrent.
- **Illusionist**: 100: Arcane Ripple > Bewitching Hex > Kindling Spark; 300: Tear in the Weave > Nightburst >
  Primordial Squall > Arcane Ripple > Shattered Psyche.
- **Thief**: 100: Blade Flurry > Fan of Knives > Shuriken Toss.
- **Ninja**: 100: Blade Flurry > Shadow Step > Shuriken Toss; 300: Blade Flurry > Shuriken Barrage > Shadow Step >
  Shuriken Toss; 1000: Shuriken Tempest > Blade Flurry > Shuriken Barrage > Shadow Step > Shuriken Toss.
- **Samurai**: 100: Blade Flurry > Shuriken Toss; 300: Blade Flurry > Iaido Sweep > Iaijutsu > Shuriken Toss.
- **Necromancer**: 100: Withering Curse > Bone Shrapnel.
- **Lich**: 100: Withering Curse > Soul Rot > Bone Spear; 300: Withering Curse > Soul Rot > Life Siphon.
- **Bone Lord**: 100: Withering Curse > Bone Spear; 300: Withering Curse > Bone Offering > Bone Spear.
- **Monk**: 100: Whirling Heel > Palm Shockwave > Sundering Palm > Ashen Fist.
- **Shadowfist**: 100: Pressure Points > Whirling Heel > Palm Shockwave > Sundering Palm; 300: Pressure Points > Shadow
  Ricochet > Whirling Heel > Palm Shockwave; 1000: Pressure Points > Shadow Ricochet > Palm Shockwave > Shadowfist
  Flurry > Sundering Palm.
- **Iron Sage**: 100: Whirling Heel > Palm Shockwave > Sundering Palm > Ashen Fist; 300: Whirling Heel > Iron Chain >
  Palm Shockwave.
- **Templar**: 100: Consecration > Sanctified Ground > Radiant Smite.
- **Inquisitor**: 100: Judgement > Consecration > Radiant Smite; 300: Judgement > Consecration > Purging Nova.
- **Sentinel**: 100: Consecration > Radiant Smite; 300: Consecration > Shield Wave > Radiant Smite.

**Cooldown ladder (2026-10-20, owner: "faça todas as magias de ataque terem 2s de diferença, começando pela primeira
delas. assim elas ficam com 2s, 4s, 6s de cooldown, da mais fraca pra mais forte")**: every class's attack spells have
the cooldowns 2, 4, 6 s ... in a ladder: the first spell (the lowest level, the class's level 8 spell, so a 2 s spell is
there from the start) is 2 s, then the others from the weakest to the strongest by the damage of one cast on one target
at level 300 (`server/data/spells/rotation_model.csv` with the class's stats; an area spell by its main-target hit, a
damage over time by its total). Group cooldown 2 s on every attack spell. A spell several classes share has one
cooldown: the rung most of them give it, a tie the lower (listed below). The snares, Feral Command and Corpse Explosion
are attack spells and take their rung too; the cast-time spells (Colossus Fall, Doomtide, Glacial Doom, Primordial
Squall, Tear in the Weave, Hail of Dawn) as well. `server/tools/rotation_sim.py --ladder [--check]` computes it and CI
checks it. Damage per cast unchanged; what it does to the damage per second: server/data/spells/README.md "Cooldown
ladder". The ladders ("rung n": the class's own rung when a shared spell took another):
- **Warrior**: Bonebreaker 2 s < Scything Arc 4 s < Reaping Gyre 6 s < Vaulting Cleave 8 s < Earthbreaker 8 s (rung 5) <
  Butcher's Gyre 12 s < Colossus Fall 14 s < Headsman's Hurl 16 s.
- **Juggernaut**: Bonebreaker 2 s < Scything Arc 4 s < Reaping Gyre 6 s < Earthbreaker 8 s < Butcher's Gyre 12 s (rung
  5) < Anvil Fall 12 s < Colossus Fall 14 s < Headsman's Hurl 16 s.
- **Berserker**: Bonebreaker 2 s < Scything Arc 4 s < Reaping Gyre 6 s < Earthbreaker 8 s < Skyfall Cleave 10 s <
  Butcher's Gyre 12 s < Rampage Leap 14 s < Colossus Fall 14 s (rung 8) < Headsman's Hurl 16 s (rung 9).
- **Ranger**: Phantom Javelin 2 s < Snare Trap 4 s < Dawnpiercer 6 s < Sanctum Burst 8 s < Skewering Line 10 s < Radiant
  Shard 12 s < Blessed Earth 14 s < Hail of Dawn 16 s.
- **Deadeye**: Phantom Javelin 2 s < Snare Trap 4 s < Dawnpiercer 6 s < Sanctum Burst 8 s < Skewering Line 10 s <
  Blessed Earth 14 s (rung 6) < Final Verdict 14 s < Twin Verdict 16 s < Hail of Dawn 16 s (rung 9).
- **Beastmaster**: Phantom Javelin 2 s < Feral Command 4 s < Pack Frenzy 6 s < Snare Trap 4 s (rung 4) < Dawnpiercer 6 s
  (rung 5) < Sanctum Burst 8 s (rung 6) < Blessed Earth 14 s.
- **Mystic**: Kindling Spark 2 s < Rime Bloom 4 s < Blightswarm 6 s < Witchfire Bolt 8 s < Briar Prison 10 s < Arcane
  Ripple 4 s (rung 6) < Umbral Stride 14 s < Bewitching Hex 6 s (rung 8) < Shattered Psyche 12 s (rung 9) < Falling Pyre
  14 s (rung 10).
- **Elementalist**: Kindling Spark 2 s < Pyre Torrent 4 s < Rime Bloom 4 s (rung 3) < Forked Storm 8 s < Witchfire Bolt
  8 s (rung 5) < Tempest Fan 12 s < Falling Pyre 14 s < Frozen Crypt 16 s < Doomtide 18 s < Glacial Doom 20 s.
- **Illusionist**: Kindling Spark 2 s < Arcane Ripple 4 s < Bewitching Hex 6 s < Primordial Squall 8 s < Nightburst 10 s
  < Shattered Psyche 12 s < Tear in the Weave 14 s.
- **Thief**: Shuriken Toss 2 s < Snare Trap 4 s < Seeker Mine 6 s < Blade Flurry 10 s (rung 4) < Fan of Knives 10 s.
- **Ninja**: Shuriken Toss 2 s < Snare Trap 4 s < Seeker Mine 6 s < Shuriken Barrage 8 s < Blade Flurry 10 s < Shadow
  Step 12 s < Shuriken Tempest 14 s.
- **Samurai**: Shuriken Toss 2 s < Snare Trap 4 s < Seeker Mine 6 s < Iaido Sweep 8 s < Blade Flurry 10 s < Iaijutsu 12
  s.
- **Necromancer**: Bone Spear 2 s < Bone Shrapnel 4 s < Grave Nova 6 s < Withering Curse 4 s (rung 4).
- **Lich**: Bone Spear 2 s < Corpse Explosion 4 s < Life Siphon 6 s < Soul Rot 8 s < Withering Curse 4 s (rung 5).
- **Bone Lord**: Bone Spear 2 s < Withering Curse 4 s < Bone Offering 6 s.
- **Monk**: Ashen Fist 2 s < Palm Shockwave 4 s < Whirling Heel 6 s < Sundering Palm 12 s (rung 4).
- **Shadowfist**: Ashen Fist 2 s < Palm Shockwave 4 s < Shadow Ricochet 6 s < Pressure Points 8 s < Whirling Heel 6 s
  (rung 5) < Sundering Palm 12 s < Shadowfist Flurry 14 s.
- **Iron Sage**: Ashen Fist 2 s < Palm Shockwave 4 s < Iron Chain 6 s < Whirling Heel 6 s (rung 4) < Iron Palm 10 s <
  Sundering Palm 12 s.
- **Templar**: Radiant Smite 2 s < Sanctified Ground 4 s < Consecration 6 s.
- **Inquisitor**: Radiant Smite 2 s < Judgement 4 s < Purging Nova 6 s < Consecration 6 s (rung 4).
- **Sentinel**: Radiant Smite 2 s < Shield Wave 4 s < Consecration 6 s.

**Class spell factor (2026-10-20, the owner's decision on the ladder's proposals)**: the ladder raised the damage per
second of the classes built on long-cooldown spells; one factor on all of a class's spell damage brings them back
without changing the ladder's order: Templar and Sentinel x0.6, Inquisitor, Elementalist, Illusionist, Lich, Bone Lord
and Shadowfist x0.7, Necromancer x0.8, Beastmaster x1.25 (it lost most to the ladder). Table:
`server/data/scripts/chaos/spell_factor_config.lua`; spell hits only (not weapon hits, healing, minions, the Templar
line's holy strike on a weapon hit, conditions); numbers: server/data/spells/README.md "Class spell factor". The
balance targets hold: the Deadeye has the best single target, the Elementalist the best area damage.

Shared spells, one cooldown (the rung per class -> the rung taken):
Arcane Ripple Illusionist 2, Mystic 6 -> rung 2 (4 s); Bewitching Hex Illusionist 3, Mystic 8 -> rung 3 (6 s); Blade
Flurry Ninja 5, Samurai 5, Thief 4 -> rung 5 (10 s); Blessed Earth Beastmaster 7, Deadeye 6, Ranger 7 -> rung 7 (14 s);
Butcher's Gyre Berserker 6, Juggernaut 5, Warrior 6 -> rung 6 (12 s); Colossus Fall Berserker 8, Juggernaut 7, Warrior 7
-> rung 7 (14 s); Consecration Inquisitor 4, Sentinel 3, Templar 3 -> rung 3 (6 s); Dawnpiercer Beastmaster 5, Deadeye
3, Ranger 3 -> rung 3 (6 s); Earthbreaker Berserker 4, Juggernaut 4, Warrior 5 -> rung 4 (8 s); Falling Pyre
Elementalist 7, Mystic 10 -> rung 7 (14 s); Hail of Dawn Deadeye 9, Ranger 8 -> rung 8 (16 s); Headsman's Hurl Berserker
9, Juggernaut 8, Warrior 8 -> rung 8 (16 s); Rime Bloom Elementalist 3, Mystic 2 -> rung 2 (4 s); Sanctum Burst
Beastmaster 6, Deadeye 4, Ranger 4 -> rung 4 (8 s); Shattered Psyche Illusionist 6, Mystic 9 -> rung 6 (12 s); Snare
Trap Beastmaster 4, Deadeye 2, Ninja 2, Ranger 2, Samurai 2, Thief 2 -> rung 2 (4 s); Sundering Palm Iron Sage 6, Monk
4, Shadowfist 6 -> rung 6 (12 s); Whirling Heel Iron Sage 4, Monk 3, Shadowfist 5 -> rung 3 (6 s); Witchfire Bolt
Elementalist 5, Mystic 4 -> rung 4 (8 s); Withering Curse Bone Lord 2, Lich 5, Necromancer 4 -> rung 2 (4 s).

## Spell cap

**Raised to 20 on 2026-10-23** (owner: "veja quantas magias de ataque cada classe tem. devem ter a mesma quantidade"): the
attack kit gave every class and ascension **10 attack spells** (37 new spells, 77 class slots; list, levels and balance:
server/data/spells/README.md "Attack spell parity"; CI: `tools/ci/check_attack_counts.py`). The Bone Lord reaches 20, so
`MAX_SPELLS` is 20. The per-class counts in the tables below are from before the kit (15 cap): add the new spells.
Combat pass (O136, 2026-10-23): **Galeborne Stride is retired** (Fleetfoot and Vigil of Haste are universal), so every
class row below that lists it has one support less (Mystic, Elementalist, Thief, Ninja, Samurai, Monk, Shadowfist, Iron Sage,
Necromancer, Lich, Bone Lord); `patch_spell_cap.py` retires 69 stock spells. Class spell damage follows a level curve
(`spell_factor_config.lua` `byLevel`), see `server/data/spells/README.md` "Combat pass (O136)".
Attack spells per class now: Warrior, Juggernaut, Berserker, Ranger, Deadeye, Beastmaster, Mystic, Elementalist,
Illusionist, Thief, Ninja, Samurai, Monk, Shadowfist, Iron Sage, Necromancer, Lich, Bone Lord, Templar, Inquisitor and
Sentinel: 10 each (before: 8, 8, 9, 8, 9, 7, 10, 10, 7, 5, 7, 6, 4, 7, 6, 4, 5, 3, 3, 4, 3). The cooldown ladder now has
ten rungs per class (2 to 20 s), so some older spells moved; Headsman's Hurl is 20 s.

**15 spells per class (2026-10-20, owner: "mysthic tem magias demais. abaixe pra 15. faça isso pra todas as classes")**:
every class and ascension can learn and cast at most 15 spells of its own: attack, healing and support, the stock spells
it kept and the Chaos spells. An ascension's 15 include the base spells it keeps (an ascension may drop a base spell).
Not counted: the 15 spells every character shares (Lantern, Greater Lantern, Bloodtrail, Ghost Rope, Wraith Step,
Fleetfoot, Town Portal, Flickerdash, Hunter's Instinct, Vigil of Clarity / Haste / Iron / Wrath, Banner Call, Soulward)
and Radiant Lantern (a light spell of the casters). They are the same for everyone, so they say nothing about a kit.
Runes are items, not spells. How the kits were cut: a filler single-target spell, one or two area spells, the big
cooldowns, the heals, the class's signature spells, a haste where the class had one, and every spell the helper's Auto
rotation presets used; out went the near-duplicate elemental variants (the stock strike, wave, beam and supreme
families), overlapping buffs and the weak stock spells. A spell other classes keep only loses this class's line. Every
Chaos spell still has a class; 68 stock spells no class keeps are retired. Server: `server/tools/patch_spell_cap.py`
(install step `spells`, after the cure retirement), counted by `server/tools/patch_spell_cap_test.py`; the Chaos spells'
lists are in `spells_chaos.xml` (Briar Prison moved from the Illusionist to the Mystic, so no Chaos spell lost its
last class). Client: `ChaosCappedSpells` (spelldata.lua) cuts the stock entries' class lists and hides the retired
ones. A character that learned a dropped spell keeps the learned row; the server refuses the cast and the spellbook no
longer lists it.

Counts before (stock and Chaos spells the class could learn, without the shared ones) and after; levels after the names:

| Class | Before | After | Attack | Healing | Support |
|---|---|---|---|---|---|
| Warrior | 27 | 15 | Bonebreaker 8, Reaping Gyre 30, Earthbreaker 60, Scything Arc 70, Butcher's Gyre 90, Vaulting Cleave 170, Colossus Fall 260, Headsman's Hurl 300 | Salve of Scars 1, Battle Salve 8, Iron Salve 300 | Ironhold 55, Bloodlust 60, Red Frenzy 100, Iron Bellow 120 |
| Juggernaut | 30 | 15 | Bonebreaker 8, Reaping Gyre 30, Earthbreaker 60, Scything Arc 70, Butcher's Gyre 90, Colossus Fall 260, Headsman's Hurl 300, Anvil Fall 380 | Salve of Scars 1, Battle Salve 8, Iron Salve 300 | Taunt of Iron 20, Ironhold 55, Iron Bellow 120, Bastion Cry 340 |
| Berserker | 30 | 15 | Bonebreaker 8, Reaping Gyre 30, Earthbreaker 60, Scything Arc 70, Butcher's Gyre 90, Skyfall Cleave 190, Colossus Fall 260, Headsman's Hurl 300, Rampage Leap 380 | Salve of Scars 1, Battle Salve 8, Iron Salve 300 | Bloodlust 60, Red Frenzy 100, Bloodrage 120 |
| Ranger | 26 | 15 | Phantom Javelin 8, Dawnpiercer 30, Snare Trap 40, Sanctum Burst 50, Skewering Line 60, Blessed Earth 100, Hail of Dawn 280, Radiant Shard 300 | Minor Mending 8, Dawn's Mending 35, Lightbearer's Grace 60 | Ward of the Mind 14*, Wildstride 55, Tautstring 60, Lightward 140, Hallowed Ground 300 |
| Deadeye | 28 | 15 | Phantom Javelin 8, Dawnpiercer 30, Snare Trap 40, Sanctum Burst 50, Skewering Line 60, Blessed Earth 100, Final Verdict 200, Hail of Dawn 280, Twin Verdict 400 | Minor Mending 8, Dawn's Mending 35, Lightbearer's Grace 60 | Ward of the Mind 14*, Wildstride 55, Tautstring 60, Lightward 140 |
| Beastmaster | 28 | 14 | Phantom Javelin 8, Dawnpiercer 30, Snare Trap 40, Sanctum Burst 50, Blessed Earth 100, Feral Command 110, Pack Frenzy 320 | Minor Mending 8, Dawn's Mending 35, Lightbearer's Grace 60 | Ward of the Mind 14*, Wildstride 55, Tautstring 60, Wild Bond 100, Lightward 140 |
| Mystic | 74 | 15 | Kindling Spark 8, Rime Bloom 20, Blightswarm 25, Witchfire Bolt 30, Arcane Ripple 40, Bewitching Hex 60, Briar Prison 70, Umbral Stride 70, Shattered Psyche 110, Falling Pyre 150 | Minor Mending 8, Grand Mending 30, Purifying Wellspring 40 | Ward of the Mind 14*, Galeborne Stride 20, Ironbark Hide 60 |
| Elementalist | 45 | 14 | Kindling Spark 8, Rime Bloom 20, Witchfire Bolt 30, Pyre Torrent 38, Tempest Fan 38, Forked Storm 50, Falling Pyre 150, Frozen Crypt 220, Doomtide 300, Glacial Doom 420 | Minor Mending 8, Grand Mending 30 | Ward of the Mind 14*, Galeborne Stride 20, Crimson Covenant 90 |
| Illusionist | 57 | 15 | Kindling Spark 8, Arcane Ripple 40, Bewitching Hex 60, Shattered Psyche 110, Nightburst 210, Primordial Squall 250, Tear in the Weave 280 | Minor Mending 8, Purifying Wellspring 40, Mirror Mend 60, Lucid Reverie 120, Verdant Sanctuary 180 | Ward of the Mind 14*, Hall of Mirrors 40, Moonfang Pack 120, Wraithshroud 150 |
| Thief | 10 | 10 | Shuriken Toss 8, Snare Trap 40, Blade Flurry 50, Seeker Mine 60, Fan of Knives 80 | Shadow Mend 25 | Galeborne Stride 20, Shadow Veil 40, Detonate Mines 60, Poison Blades 60 |
| Ninja | 13 | 13 | Shuriken Toss 8, Snare Trap 40, Blade Flurry 50, Seeker Mine 60, Shadow Step 100, Shuriken Barrage 180, Shuriken Tempest 270 | Shadow Mend 25 | Galeborne Stride 20, Shadow Veil 40, Detonate Mines 60, Poison Blades 60, Smoke Bomb 130 |
| Samurai | 13 | 13 | Shuriken Toss 8, Snare Trap 40, Blade Flurry 50, Seeker Mine 60, Iaijutsu 120, Iaido Sweep 200 | Shadow Mend 25 | Galeborne Stride 20, Shadow Veil 40, Detonate Mines 60, Poison Blades 60, Counter Stance 100, Bushido Focus 150 |
| Monk | 7 | 7 | Ashen Fist 8, Sundering Palm 30, Palm Shockwave 50, Whirling Heel 50 | Kindled Breath 40 | Galeborne Stride 20, Mistborne Step 35 |
| Shadowfist | 10 | 10 | Ashen Fist 8, Sundering Palm 30, Palm Shockwave 50, Whirling Heel 50, Pressure Points 100, Shadow Ricochet 150, Shadowfist Flurry 150 | Kindled Breath 40 | Galeborne Stride 20, Mistborne Step 35 |
| Iron Sage | 11 | 11 | Ashen Fist 8, Sundering Palm 30, Palm Shockwave 50, Whirling Heel 50, Iron Palm 120, Iron Chain 150 | Kindled Breath 40 | Galeborne Stride 20, Mistborne Step 35, Chi Ward 100, Mantra of Stone 150 |
| Necromancer | 21 | 12 | Bone Spear 8, Withering Curse 40, Grave Nova 50, Bone Shrapnel 60 | Minor Mending 8, Grand Mending 30, Rebirth of Flesh 300 | Ward of the Mind 14*, Raise Bone Warrior 8, Raise Bone Archer 12, Raise Bone Mage 16, Galeborne Stride 20, Raise Dead 20 |
| Lich | 23 | 13 | Bone Spear 8, Withering Curse 40, Soul Rot 100, Life Siphon 130, Corpse Explosion 160 | Minor Mending 8, Grand Mending 30, Rebirth of Flesh 300 | Ward of the Mind 14*, Raise Bone Warrior 8, Raise Bone Archer 12, Raise Bone Mage 16, Galeborne Stride 20, Raise Dead 20 |
| Bone Lord | 23 | 13 | Bone Spear 8, Withering Curse 40, Bone Offering 150 | Minor Mending 8, Grand Mending 30, Rebirth of Flesh 300 | Ward of the Mind 14*, Raise Bone Warrior 8, Raise Bone Archer 12, Raise Bone Mage 16, Galeborne Stride 20, Raise Dead 20, Bone Golem 100, Banner of Bones 120 |
| Templar | 4 | 4 | Radiant Smite 8, Consecration 40, Sanctified Ground 60 | Vow of Mending 30 |  |
| Inquisitor | 6 | 6 | Radiant Smite 8, Consecration 40, Judgement 100, Purging Nova 120 | Vow of Mending 30 | Zealotry 150 |
| Sentinel | 7 | 7 | Radiant Smite 8, Consecration 40, Shield Wave 150 | Vow of Mending 30, Lay on Hands 150 | Rebuke 100, Aegis of Faith 120 |

* Ward of the Mind (stock Magic Shield, the classic one: the mana takes a hit first, the health only the rest) is
  outside the 15 (`patch_spell_cap.py` `OUTSIDE_CAP`, owner 2026-10-21: "somente pra mages e rangers", the
  Necromancer counted as a mage): the Mystic, Necromancer and Ranger lines have it, no other class. Soulward (level 80, 15 s) stays every class's short mana shield.

Dropped, per line (each spell left the classes named; "retired" = no class keeps it):
- Warrior line: Minor Mending, Warhorse Rush, Cyclone Hurl, Martial Communion, Earthrend, Reaver's Spin, Rending Mark,
  Second Wind, Warlord's Resolve, Greater Second Wind, Ruinous Cleave, Duelist's Oath (all retired but Minor Mending);
  the Juggernaut also Bloodlust, Red Frenzy, Vaulting Cleave; the Berserker also Taunt of Iron, Ironhold, Vaulting Cleave.
- Ranger line: Arcane Stitch, Deep Mending, Unveil, Shielding Communion, Dawnbolt, Second Wind, Greater Second Wind,
  Glare of Dawn, Greater Phantom Javelin (retired), Seeker Mine and Detonate Mines (the Thief line keeps them); the
  Deadeye and Beastmaster also Radiant Shard and Hallowed Ground, the Beastmaster also Skewering Line.
- Mystic line: the level 1 spells (Bog Splatter, Rime Breath, Searing Gust, Static Sting), the strike families (Arc
  Bolt, Riftbolt, Thornlash, Ember Lash, Frostbite, Gravetouch, Hammerfall Palm and their Greater and Supreme ranks),
  the waves and beams (Cinder Fan, Glacier Fan, Greater Glacier Fan, Bramble Fan, Stormlance, Thunder Lance, Lance of the
  Grave), the old area ultimates (Storm Crown's Wrath, Wildwood Ruin, Endless Rime, Infernal Heart, Quakeburst,
  Shatterfrost), the marks and hexes (Smoulder Brand, Galvanic Mark, Blackroot Venom, Hex of Withering, Skyfang, Crossfire
  Hex, Dread, Fading Step, Gravity Snare, Sunder Guard), Arcane Stitch, Deep Mending, Kindred Mend, Circle of Mending,
  Heartwood Embrace, Skinchanger's Guise, Call Thrall, Shroud of Shadows and the communions (all retired); Rebirth of
  Flesh (the Necromancer line keeps it). Ward of the Mind left the Mystic and the Illusionist on 2026-10-20 and
  came back outside the cap on 2026-10-21 (*).
  Between the three classes: the Mystic left Forked Storm, Crimson Covenant, Pyre Torrent, Tempest Fan (Elementalist),
  Hall of Mirrors, Wraithshroud (Illusionist); the Illusionist left Grand Mending, Galeborne Stride, Blightswarm, Ironbark
  Hide, Umbral Stride, Briar Prison (Mystic).
- Necromancer line: Arcane Stitch, Kindred Mend, Deep Mending, Circle of Mending, Heartwood Embrace,
  Skinchanger's Guise, Shroud of Shadows, Arcane Communion, Mending Communion. Ward of the Mind left on 2026-10-20 and
  came back outside the cap on 2026-10-21 (*).
- Thief, Monk and Templar lines: nothing (10-13, 7-11 and 4-7 spells).

## Skills and weapons (owner debug items 46 and 47, 2026-10-17)

The skills of the game are **Melee, Ranged, Magic (wands and rods use the magic level) and Shielding**; Fist Fighting is the Monk
line's bare-hands skill. The engine still stores sword, club and axe, but a hit, a melee spell and the training use the best of
the three (one melee skill: server/README.md "One melee skill"), the three train at the same speed in every vocation, and the
skills window shows one "Melee" row (client `game_simpleskills`); the level-up messages say "melee" and "ranged" too (src-patch 0065, "Skill names in messages"). **Melee items serve every melee class**: any sword, axe or club,
one- or two-handed, is open to the Warrior, Thief, Monk and Templar lines (the Berserker keeps two-handed weapons only, as its
class rule); armour, shields, launchers, wands and rods keep their lists. Of the same tier, a two-handed melee weapon deals 1.07x the
damage per second of one hand + shield at every level (it was +28% at level 8 and +13% from level 75); launchers and the Monk's
early fists are still ahead (server/data/spells/README.md "Weapon damage per second": owner decision).
**Training weapons (owner, 2026-10-23)**: the exercise weapons on a training dummy: one **melee** weapon (the sword, axe and club
ones are the same item now) for the Warrior, Thief, Monk and Templar lines, which trains the melee skill, and **fist fighting for the
Monk line**; a bow for the Ranger and Thief lines (distance); a rod and a wand for the Mystic, Necromancer and Templar lines
(magic level); a shield for every class (shielding). Server/README.md "Training weapons".
**Weapon coverage (owner, 2026-10-23, "veja se todas as classes tem armas o suficiente")**: every class has at least three
weapons it can wield and obtain in each of the nine level bands (1-20, 20-50, 50-100, 100-200, 200-400, 400-700, 700-1000,
1000-1500, 1500-2400+), and the best of them is at least 80% of the tier (the gear set attack curve). A check in CI keeps it
(`server/tools/weapon_coverage.lua --check`; the table and the thresholds: server/README.md "Weapon coverage"). Gaps found:
the Berserker (two-handed melee only) had nothing at 1500+, the Elementalist and Illusionist one weapon, the Beastmaster
(bows only) two bows at 20-50 and at 700-1000, the Ranger line, Mystic and Necromancer line two weapons at 1500+. Filled with
seven uniques (Berserker: Hollow Throne Claymore 1550, Emberhowl Greataxe 1950, Bellringer of the Last Vigil 2200; Ranger
line: Hoarfen Bow 40, Moonlit Gallows Bow 900, Gravetide Arbalest 1800, Wake-Heron Longbow 2100) and by making the level 2000
Gildcrown pieces droppable (wands and rods got their third piece by moving the set to 1250-2000).
Every auto attack scales with its skill (owner, 2026-10-20): swords, axes, clubs, distance weapons and fists by the engine's
formula (the skill is 79-94% of the hit), wands and rods by the magic level since 2026-10-20 (before: a flat roll whatever the
magic level; at the typical magic level of a level the hit is the same as before). server/README.md "Weapon damage scales
with skills".

## Starting stats

New characters start at level 8 (4200 experience) in the temple of Cinderhold, wearing their full kit (owner design
2026-10-16: no tutorial island). Every class has its own level 1 health, mana, capacity (oz) and soul and its gains per
level in `server/data/scripts/chaos/start_stats.lua` (the one source of every creation path: the website and the client,
`add-account.sh`, the test accounts, and the game's one-time login correction of characters below them); the start is
the level 1 row plus 7 levels of gains. The level 1 values follow the vocation gains: more health per level, more health
at level 1, and so on. Ascended classes start like their base class. The class look is worn in the class's start colours
(`class_looks_core.lua` `L.startColors`). The owner approved these stats and start colours on 2026-10-16.

| Class | Level 8 health / mana / capacity | Start colours (head, body, legs, feet) |
|---|---|---|
| Warrior | 290 / 70 / 645 | 57, 113, 114, 116 (grey, crimson, black, brown) |
| Ranger | 235 / 165 / 580 | 116, 120, 116, 115 (browns, forest green) |
| Mystic | 185 / 300 / 470 | 57, 107, 126, 114 (grey, deep blue, navy, black) |
| Thief | 259 / 115 / 609 | 95, 114, 95, 114 (dark grey, black) |
| Monk | 259 / 115 / 609 | 97, 97, 116, 116 (ochre, brown) |
| Necromancer | 211 / 262 / 501 | 114, 128, 114, 114 (black, dark purple) |
| Templar | 278 / 96 / 640 | 79, 0, 79, 57 (gold, white) |

**Level 8 spells (owner debug item 44, 2026-10-17: "A maioria das classes não tem magia no level 8")**: every class and
ascension has an attack spell it can cast at the start level (`needlearn="0"`: no teaching; the spellbook, the action bar and
the Helper's Auto setup list it at the first login). Warrior, Juggernaut, Berserker: Bonebreaker (was level 16); Ranger,
Deadeye, Beastmaster: Phantom Javelin (was 23); Thief, Ninja, Samurai: Shuriken Toss (was 20); Necromancer, Lich, Bone Lord:
Bone Spear (was 15); Monk, Shadowfist, Iron Sage: Ashen Fist (was 15); Templar, Inquisitor, Sentinel: Radiant Smite (was
20); Mystic, Elementalist, Illusionist: Kindling Spark (already). Their mana costs were lowered to what the level 8 pool
sustains: a mana runway of at least 15 s for every class at levels 8-300 (`server/tools/rotation_sim.py --mana`;
server/data/spells/README.md "Mana runway"). Raise Dead, the Necromancer's signature, stays at level 20.
Every spell of every class costs one fixed number of mana at every level (owner 2026-10-21; the client shows the same
number, mana is not in the display scale): the cost table per line and the runway up to level 1000 are in
server/data/spells/README.md "Fixed spell costs".

Level 1 rows:

| Class | Health | Mana | Capacity |
|---|---|---|---|
| Warrior (4, 8, 14) | 185 | 35 | 470 |
| Ranger (3, 7, 15) | 165 | 60 | 440 |
| Mystic (1, 5, 10) | 150 | 90 | 400 |
| Thief (11, 12, 13) | 175 | 45 | 455 |
| Monk (17, 18, 19) | 175 | 45 | 455 |
| Necromancer (20, 21, 22) | 155 | 80 | 410 |
| Templar (23, 24, 25) | 180 | 40 | 465 |

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
  - generated spell icons and effects (class signature effects: one look per line, server/README.md "Class signature
    effects"; pair things_custom22, behind `ChaosClassFx.PAIR22_FX`)
  - outfits: a class look per class, male and female (October 2026: donor library art and free looks of the pair, look types
    2039-2081 of things_custom10b, no stock art; list in `class_looks_core.lua`, sources in
    `client/tools/outfit_art/class_looks_sources.csv`, client/MANIFEST.md "Class looks pair"). Worn with both addons
    (addons 3); the character owns both addons of each class look it is given, and no other outfit's addons. Six looks
    changed with the pair 19 switch (`ChaosClassLooks.PAIR19_LOOKS`, on since 2026-10-12: things_custom19 is live)
    and six more with the pair 20 switch (`ChaosClassLooks.PAIR20_LOOKS`, on since 2026-10-12: things_custom20 is live
    at windows-assets 77b9cc9b; server/README.md "Class looks"). Looks per class (male / female look type; "before" =
    things_custom18, "pair 19 / 20" = live now):

    | Line | Class (id) | Before | Pair 19 / 20 (live) |
    |---|---|---|---|
    | Warrior | Warrior (4) | 2073 / 2074 | kept |
    | | Juggernaut (8) | 2039 / 2040 | 2161 / 2162: gilded plate, tower shield (donor D 997 / 998) |
    | | Berserker (14) | 2075 / 2076 | kept |
    | Ranger | Ranger (3) | 2078 / 2079 | 2163 / 2164: hooded archer (donor H 246 / 247) |
    | | Deadeye (7) | 2045 / 2046 | kept |
    | | Beastmaster (15) | 2047 / 2048 | 2165 / 2166: fur cloak (donor D 166 / 167) |
    | Mystic | Mystic (1) | 2060 / 2061 | kept |
    | | Elementalist (5) | 2062 / 2063 | kept |
    | | Illusionist (10) | 2049 / 2050 | kept |
    | Thief | Thief (11) | 2051 / 2052 | 2175 / 2176: hooded rogue, twin daggers (pair 20, donor D 521 / 522) |
    | | Ninja (12) | 2069 / 2070 | 2177 / 2178: black shinobi, katana (pair 20, donor D 789 / 790) |
    | | Samurai (13) | 2071 / 2072 | kept |
    | Monk | Monk (17) | 2080 / 2081 | kept |
    | | Shadowfist (18) | 2053 / 2054 | 2169 / 2170: claws, violet glow (donor D 1057 / 1058) |
    | | Iron Sage (19) | 2055 / 2056 | kept |
    | Necromancer | Necromancer (20) | 2044 / 2064 | 2183 / 2184: blood hood or witch hat, blood orb, skull (pair 20, D 856 / 857, composed) |
    | | Lich (21) | 2059 (one look) | 2173 / 2174: skeletal lord, skull cape, bone sceptre (pair 20, donor D 219 / 220) |
    | | Bone Lord (22) | 2065 / 2066 | 2167 / 2168: bone wings, skull rack (donor D 508 / 509) |
    | Templar | Templar (23) | 2067 / 2068 | 2179 / 2180: gilded holy knight, kite shield (pair 20, donor D 609 / 610) |
    | | Inquisitor (24) | 2077 (one look) | 2181 / 2182: witch-hunter hat, rapier, holy sceptre (pair 20, D 419 / 420, composed) |
    | | Sentinel (25) | 2042 / 2041 | 2171 / 2172: holy orbs, tower shield (donor D 992 / 993) |

    A replaced look stays owned and wearable as "<class> Class (old)". A character wearing one gets the new look at its
    next login.

    The Lich and the Inquisitor now have a look per sex; a character in the old one look gets the new look of its sex.
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
  | 11 | Thief | 11 | 6 | 12 / 10 / 22 | 1500 (was 1600) | 230 | 1.2 |
  | 12 | Ninja | 11 | 16 | 12 / 10 / 22 | 1300 (was 1400) | 232 | 1.2 |
  | 13 | Samurai | 11 | 26 | 13 / 9 / 24 (defense / armor 1.1) | 1700 (was 1800) | 230 | 1.3 |

  Attack speed since 2026-10-23 (owner: the Thief attacks faster than the other classes, tied with the Monk): Thief = Monk 1500,
  Ninja = Shadowfist 1300, Samurai = Iron Sage 1700 ms; every class outside the two lines keeps 2000. The weapon hits of the
  three are cut by new / old (`Chaos.classes.attackSpeed`), so the auto attack's damage per second is where it was balanced.
  A Thief with a dagger in each hand also gives up the share the off-hand strike adds (main hit x 1 / 1.5 with equal daggers).
  The Thief's starting kit is two daggers (main hand and shield hand); a Thief made before gets the second dagger once at login
  (`Chaos.storage.offhandGranted`, 7100204). Daggers by band: server/README.md "Thief daggers".

  Skills: the three melee skills (sword, club, axe) 1.1 (like the Knight's swords; one melee skill since 2026-10-17), distance 1.2, magic level 2.0. The tool also adds the line to the
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
- **Kit**: 13 spells (ids 236, 238-245, 98 Shadow Mend, the self heal of phase 2b, the area strikes 192 Blade Flurry
  and 193 Iaido Sweep of 2026-10-15, `_blades.lua`, and the Thief's Fan of Knives 136, `_packtools.lua`; `server/data/spells/chaos/thief|ninja|samurai`), evasion, stealth, Poison Blades, scripted dual
  wield, counter stance, Bushido stacks (`server/data/scripts/chaos/thief_combat.lua`). Spells, numbers and the balance measurement
  are in `server/data/spells/README.md` ("Thief line"). The shuriken spells need no star: stackable throwing weapons left the game (owner 2026-10-20, server/README.md "Throwing weapons"),
  the spells use a default attack of 50 (a one-handed distance weapon in hand raises it).
- **Outfits** (look types 1505-1510, from a third donor sprite set, see `server/data/monster/CUSTOM_MONSTERS.md`): Ninja gets
  Shadow Ninja, Crimson Ninja and Masked Ninja (colourable); Samurai gets Oni Samurai, Ronin and Dark Samurai. Ascending gives the
  class's three (since phase 2b the class's stock look is put on instead, see "Class looks"); characters already in the class get them at their next login (look unchanged). They stay
  after a class change. List in `Chaos.classes.outfits` (`chaos_constants.lua`), code in `ascension.lua`
  (`giveClassOutfits`), outfits.xml entries for both sexes by `server/tools/install_outfits.py` (install step `outfits`).
  The Mystic line's donor art outfit 1559 "Archmage" was retired on 2026-10-16. It is not given any more; owners keep it
  as "Archmage (old)", and it is never sold. Its replacement is the pair 29 Archmage (2235 male / 2236 female, our own
  art, both addons given), behind `Chaos.classes.outfitReplacement` (off until pair 29 is live).
  See server/README.md "Class looks".

Limits of phase 1:
- Stealth is scripted: monsters drop the player and cannot attack it while it lasts, but area attacks aimed at someone else still hit
  (and end it). A monster that sees invisible creatures is handled the same way.
- Dual wield needs the engine patch; without it a Ninja fights with one blade and gets no off-hand strike. Both blades' item bonuses
  count. A character that stops being a Ninja keeps a sword already in the shield hand until it moves it (it then cannot put it back).
- The line had no healing spell of its own until Shadow Mend (phase 2b; 2026-10 to 2026-10-21 it cost 2% of the maximum
  mana; since 2026-10-21 a flat 40 mana at every level like every spell, server/README.md "Fixed spell costs": about 28 / 57
  healed per mana at level 300 / 1000; since 2026-10-20 level x 0.5 + magic level x 20 + 5% every 1.5 s, 751 / 1527 per second, server/data/spells/README.md "Healing"). Potions: since the class pass of 2026-10 `add_vocations.py` adds the line (11-13) to
  the Royal Paladin's potion lists (the line wears what the Paladin wears; see "Item, spell and potion lists"); before, the
  strongest potions refused it. The shared Chaos spells (Flickerdash, Banner Call, Soulward, Hunter's
  Instinct) and the stock spells did not list the line either in phase 1; both do now (stock utility spells: see "Item, spell and
  potion lists").
- Spell strikes had a level factor (`Chaos.classes.spellLevelScale`) that stood in for the missing passive tree; dropped with
  the class trees (phase 2b).

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
  (Since "Infinite arrows and quivers", server/README.md, launchers have no ammo type: the tool counts a two-handed distance
  weapon as a bow or crossbow by its missile, and arrows and bolts are gone.)
  `potions.lua`: a potion of the Elite Knight (8) also lists the Berserker (14), one of the Royal Paladin (7) the Beastmaster (15),
  the Thief line (11-13) and the Monk line (17-19), one of either the Templar line (23-25), one of the Elementalist (5) the
  Necromancer line (20-22); the refusal texts name our classes ("Only Warriors and Templars of level 80 or above may drink this
  fluid."). The mastermind potion (`strengthening_potions.lua`, `Player.isMage`: Sorcerer and Druid ids only) also takes the
  Illusionist and the Necromancer line ("Only Mystics and Necromancers ..."). Unit test `server/tests/potions_patch_test.lua`;
  in game: a Ninja, a Necromancer and a Templar drink theirs and are refused the others;
  `lib/core/player.lua`: `Player.isKnight` / `isPaladin` count them too. Weapons without a vocation list stay open to everyone.
  Stock utility spells (`LINE_STOCK_SPELLS`, since 2026-10): the Thief, Monk and Templar lines get what every other class has
  (Lantern, Greater Lantern, Fleetfoot, Bloodtrail, Wraith Step, Ghost Rope, Purge Venom, Wash Taint, Break Glamour); the Thief
  and Monk lines also Galeborne Stride (strong haste), the Monk and Templar lines Staunch Blood (as the Warrior), the Templar
  line Lift Hex (as the Ranger). The Necromancer line already had them all. NPC teachers and the spellbook follow `spells.xml`;
  the client's spell list gets the same ids from `ChaosStockSpellLines` (spelldata.lua). Unit test
  `server/tests/stock_spells_patch_test.lua`; in game a Thief, a Monk and a Templar cast each one (and are refused the others).
- **Ascension**: the Ascendant Oracle (Warrior), `deadeye|beastmaster` (Ranger), `elementalist|illusionist` (Mystic),
  `ninja|samurai` (Thief); level 100, protection zone, out of combat, final. The store's Character > Services takes the new words
  (`warrior|juggernaut|berserker|ranger|deadeye|beastmaster|mystic|elementalist|illusionist|thief|ninja|samurai`; the base word asks
  an ascended character to name the ascended class). The passive tree's keystone variant follows the line
  (`ChaosClasses.keystoneKey`): Warrior line knight, Ranger line paladin, Mystic / Elementalist sorcerer, Illusionist illusionist;
  the druid variants (Overgrowth, Thorns) belonged to no class until 2026-10-12, when they went to the Iron Sage and the Sentinel
  (Phase 2b below). Since phase 2b the Juggernaut, Berserker, Deadeye and Beastmaster have their own variants.
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
  gear, stock heals and mana potions (`add_vocations.py`). Locked behind the account's class unlock at level 200 (`class_unlocks.lua`,
  key "necromancer").
- **Ascension**: the Ascendant Oracle (`Chaos.classes.ascension.choices[20]`).
- **Kit**: 13 spells (ids 180-188, the Necromancer's Bone Shrapnel 197 of 2026-10-15 and the three summon spells Raise Bone Warrior 192 / Archer 193 / Mage 176 of 2026-10-18, `_packtools.lua`; `server/data/spells/chaos/necromancer|lich|bonelord`, helpers `_necro.lua`);
  minions `necro_minions.lua`, curse and bone shield `necromancer_combat.lua`, engine helpers `necro_lib.lua`, pure
  rules `necro_core.lua` (tests `server/tests/necro_test.lua`), numbers `necro_config.lua`; minion monsters
  `server/data/monster/monsters/chaos/necro_*.xml` (looks: skeleton 33, ghost 48, demon skeleton 37). New-player kit: the
  Mystic's (`newplayer_config.lua`).
- **Summon spells** (2026-10-18, support group, all three classes, 4 s cooldown): Raise Bone Warrior (192, `vael oss brak`, level 8, 50 mana; a sturdy melee minion, range 1, physical), Raise Bone Archer (193, `vael oss sag`, level 12, 60 mana; range 5, physical arrows, fragile) and Raise Bone Mage (176, `vael oss mynd`, level 16, 70 mana; range 4, energy, fragile). Each creates ONE minion next to the caster. **Total cap** (all kinds together: skeletons, shades, the golem and these three): Necromancer 3, Lich 1, Bone Lord 6 (7 from level 400), the passive tree's Legion adds to it. At the cap the next summon of any spell dismisses the OLDEST minion first (a puff, no corpse, no loot), then the new one appears. Raise Dead's own per-kind caps stay; the total wins. Numbers: `necro_config.lua` `minions`.
- **Summons**: capped per class and level, scale with the owner's level and magic level, follow (brought back past
  7 sqm or across floors), rest in protection zones and rise outside, go at logout and death, pushable. They show
  their owner's level after the name and follow a level up while out (the level shown and the maximum health, the
  same share of it kept; hits always use the owner's current numbers). The owner walks through its own minions
  (engine patch 0055; other players and the party are still blocked). The owner and its party never target them:
  the helper drops such a lock and attack next skips them (client base patch 0112). No experience, no loot.
  (server/README.md "Summons: targets, walk-through, levels", 2026-10-21.) Their hits are
  dealt as the owner (full experience, the Chaos loot layer, bounty / leaderboard / hunt credit through the owner);
  the engine alone would credit a summon's share at half experience and skip the rarity loot when a summon lands the
  last hit (`Creature::onGainExperience`, `Monster::dropLoot`).
- **Balance**: planned numbers in `server/data/spells/README.md` ("Necromancer line"); measured in phase B.

Open for the Necromancer:
- Passive tree: done in phase 2b (the class section, keystones Hoarded Souls and Bone Colossus); `levelScale` dropped.
- Effects (our own art, client/MANIFEST.md "Fist weapons and bone effects"): Bone Spear flies as the `bone_spear` missile and
  splinters on the target (`bone_spear` effect), Corpse Explosion and Bone Offering burst with `bone_burst`, Banner of Bones
  (each minion) and Bone Offering (the caster) show `bone_aura`. Ids in `data/lib/chaos_vfx_art.lua`; without that file or
  the new pair the spells fall back to the stock effects as before.
- Minions in the arena, the guild siege and rifts follow those modes' summon rules (not checked).

### Monk (C6, phase B: tested in game)

- **Vocations** (`server/data/XML/chaos_vocations_monk.xml`, installed by `add_vocations.py`):

  | id | Name | from | client byte | hp / mana / cap per level | attackspeed | base speed | fist hits |
  |---|---|---|---|---|---|---|---|
  | 17 | Monk | 17 | 8 | 12 / 10 / 22 | 1500 | 230 | x1.2 |
  | 18 | Shadowfist | 17 | 18 | 12 / 10 / 22 | 1300 | 232 | x1.2 |
  | 19 | Iron Sage | 17 | 28 | 14 / 9 / 25 (defense / armor 1.15) | 1700 | 228 | x1.1 |

  Skills: fist fighting and the three melee skills (club, sword, axe) 1.1, distance 1.3, shielding 1.2 (Iron Sage 1.1), magic level 2.0. the Ascendant Oracle
  at level 100. All ids (vocations, client bytes, spells 63-72, storages 7100800-7100809, condition sub ids 71030-71044, opcode 247) are in
  `ChaosMonk.ids` (`server/data/scripts/chaos/monk_chi_core.lua`). Equipment (`add_vocations.py`): every sword, axe and club (staves too) and
  whatever the Ranger may wear, and the fist weapons; the Royal Paladin's potions. New-player kit: light armour and a pair of splinter claws (fist weapon, level 1).
- **Unarmed combat on this engine**: without a weapon the engine hits with fists (`Weapon::useFist`): fist fighting skill, a fixed attack
  value of 7, the vocation's attackspeed (minus the dexterity stat), the usual weapon formula and the fight mode factor, but **not** the
  vocation's meleeDamage multiplier, and there is no "fist" weapon type in the item types. So the Monk's unarmed damage is scripted on the
  weapon hook, without an engine patch: `monk_combat.lua` scales a Monk's fist hit (melee origin, nothing in the hands) by (formula with
  the Monk's fist attack x meleeDamage) / (formula with attack 7). The fist attack grows with level: 40 + level x 0.025, at most 60
  (level 300: 47.5). Fist weapons (`ChaosMonk.cfg.unarmed.fistWeapons`, server/README.md "Fist weapons"): nineteen hand items of weaponType
  "shield" with an attack, worn in the shield hand by the Monk line only, from level 1 to 2200; their attack replaces the level
  value when higher. Plain tiers: splinter claws 41 / level 1 (the starter kit), charred hand wraps 42 / 8, rustiron claws 43 / 35,
  ashbound cestus 44 / 60, ashen steel claws 45 / 100, ember knuckles 46 / 150, ossuary gauntlet 50 / 300, cinderforged talons 55 /
  500, emberhide claws 62 / 800, voidglass claws 63 / 1000, stormforged claws 64 / 1250, wyrmbone claws 65 / 1500, gravewrought claws
  66 / 1800, last-dawn claws 67 / 2200. Uniques: Vigil-Knot Wraps 43 / 14 and Chapel-Iron Knuckles 44 / 26 (leveling, magic), Grasp
  of the Pyre Saint 64 / 650 (legendary), Gravewind Talons 68 / 1400 and Dawnless Gauntlets 70 / 2000 (endgame, rare or better,
  strong monsters), each with Chaos modifiers built in. A plain tier is x1.00 .. x1.12 damage over bare fists (cap 60) at its
  level; the auto attack stays at 53-62% of the Monk's rotation. The fist skill scales the hit like the melee skill does for the
  other classes (`(skill / typical)^0.5`, 0.7 .. 1.6; 1 at the typical skill). The Monk's attack speed is not changed.
  Staves are
  ordinary weapons (club skill, the two-handed factor of `weapon_styles.lua`, the attack speed patch 0002).
- **Chi**: a player storage (shared by the spells' and the scripts' Lua states) with the time of its last change; gone after 12 s untouched.
  +1 per melee hit (at most one per 2 s), +2 Ashen Fist, +1 Pressure Points; a finisher needs 1 chi and spends all of it, x(0.30 + 0.14 per
  chi) of its 5-chi value. HUD: client module `game_monkchi` (5 pips; extended opcode 247).
- **Kit**: 13 spells (ids 63-72 and the pack strikes of 2026-10-15, `_packtools.lua`: Palm Shockwave 194 for all three, Shadow Ricochet 195, Iron Chain 196; `server/data/spells/chaos/monk|shadowfist|ironsage`, helpers `_monk.lua`), evasion (6% / 8% / 4%, +25% for
  2 s after Mistborne Step), the Shadowfist focus crit, Pressure Points, Chi Ward, Mantra of Stone and the Iron Palm stun in
  `monk_combat.lua`. Spells, numbers and the estimate are in `server/data/spells/README.md` ("Monk line"). Unit tests: `server/tests/monk_test.lua`,
  `server/tests/monk_pvp_stun_test.lua`, `client/overlay/modules/game_monkchi/chimath_test.lua`.
- **Iron Palm on players** (since 2026-10; server/README.md "Iron Palm stun on players"): when the strike's damage lands
  (so every PvP rule applies: zones, party, secure mode, multi-client, arena, siege; the hit fight-locks the Monk and puts
  both in PvP combat, where heals are -30%), the player cannot move, auto attack or cast attack spells and runes for 0.5 s
  + 0.1 s per chi (0.6-1 s); healing and potions still work, a cast-time spell is interrupted. Then 6 s of immunity, and a
  stun within 15 s of the last one lasts half as long, so there are no chain-stuns. Engine features only (movement block,
  no-move, `CONDITION_PACIFIED`), no source patch. Shown as "Stunned!" over the victim, a message to both and the
  **Stunned** / **Stun Immunity** rows of the buff bar and party frames. Tested in game with two characters.

Open for the Monk:
- Balance: measured at level 300 (`server/data/spells/README.md` "Monk line"): the Shadowfist was ~26% above the Ninja on one
  target (the focus crit, 8% per chi, on the auto attack); with 2.5% per chi it is 1078 against the Ninja's 1001 (+8%, a
  burst class's lead). Level 1000 by formula only (~3060 against the Ninja's 2837), not measured yet.
- Passive tree: done in phase 2b (keystones Hundred Hands and, after the role rebalance, Flowing Mercy for the Iron Sage
  healer instead of the proposed Stone Body); the level factor dropped. Since 2026-10-12 the Iron Sage may also take
  Overgrowth on the main tree's Wrath keystone (621; "Phase 2b" below).
- A stun on players: done (see "Iron Palm on players" above).

### Templar (C7, phase B: tested in game)

Holy melee with a party defence aura; the tank-support alternative to the Juggernaut. Ascension with the Ascendant Oracle
at level 100+ (the same rules as the other classes).

| id | Name | client byte | hp / mana / cap per level | weapon hits | defense / armor |
|---|---|---|---|---|---|
| 23 | Templar | 9 | 14 / 8 / 25 | 1.0 | 1.05 |
| 24 | Inquisitor | 19 | 13 / 10 / 24 | 1.0 | 1.0 |
| 25 | Sentinel | 29 | 14 / 7 / 25 | 0.9 | 1.15 |

Skills: the three melee skills (sword, club, axe) 1.1 (as the Warrior), fist 1.2, distance 1.4, shielding 1.1, magic level 2.5. Equipment
(`server/data/XML/chaos_vocations_templar.xml`, installed by `add_vocations.py`): one-handed swords and clubs, shields,
everything the Warrior wears; potions of the Elite Knight and the Royal Paladin. New-player kit: the Warrior's.

**Kit** (11 spells, ids 189-191, 198, 199, 250-253 and the pack spells of 2026-10-15, Sanctified Ground 108 for the Templar and Shield Wave 109 for the Sentinel, `_packtools.lua`; numbers in `server/data/spells/README.md`, "Templar line"):
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
  (a party member or itself within 5 sqm: 35% of its maximum health + magic level x 10; 60 s cooldown), Shield Wave (a
  Radiant Smite on the target and 2x it on everything in the 3 x 3 tiles in front, 2026-10-15).
- Templar only: Sanctified Ground (3 holy pulses around the cast tile: the target a third of a Radiant Smite each, the
  rest of the pack 2.5x it, 2026-10-15).

Files: `templar_aura_core.lua` (every id and number, and the rules: aura, strikes, Judgement, Zealotry, heals; tested in
`server/tests/templar_test.lua`), `templar_combat.lua` (the aura check, onHealthChange), the spells in
`server/data/spells/chaos/templar|inquisitor|sentinel` with `_templar.lua`.

Open for the Templar:
- Passive tree: done in phase 2b (keystones Divine Verdict and Bastion); the level factor dropped. Since 2026-10-12 the
  Sentinel may also take Thorns on the main tree's Resolve keystone (624; "Phase 2b" below).
- Aura status icon: done. A covered player has the buff **"<Templar>'s Aura"** (own aura: "Your Sentinel Aura") on the buff bar
  and under its party frame: stacks = the damage reduction in percent, the tooltip names the Templar, its class, the
  reduction, the Sentinel's regeneration per second and Bastion; the party frame's tooltip lists it by name. Sent only when it
  starts, changes (another Templar's aura, other numbers) or ends (server/README.md "Buff bar"). Tested in game in a party.

### Illusionist healer pass

The owner's call: the Illusionist is the best healer class, plus party attack buffs. Done by adding to its kit, not by cutting
other classes' heals (numbers and the measurement: `server/data/spells/README.md`, "Healing"):
- **Weaver's Grace** (passive): heals the Illusionist casts on another player +16% (+5% until the role rebalance of
  2026-10, which made the Iron Sage the second healer: it keeps the Illusionist at least 12% ahead).
- **Mirror Mend** (spell 96, `saen spek ["Name"]`): the most hurt party member within 7 sqm, and a mirror heal for 25% on the
  next most hurt. **Lucid Reverie** (spell 97, `reth vas spek`): a party heal over time (5 pulses in 10 s).
- **Shared Phantasm** (keystone): party members also heal for 4% of what they deal to the marked enemy; the +12% stays.
- **PvP**: every heal on a player in PvP combat (player damage either way in the last 10 s, a fight lock, an arena match, the
  siege arena) is -30%, for every class, so healers do not make fights endless.
- Measured lead: party healing +32% / +41% (level 300 / 1000) over the next class (the base Mystic) and +58% / +66% over the
  next ascended one (the Lich), single target on another player +22% / +33%. The Sentinel keeps the biggest emergency heal
  (Lay on Hands) and stays a tank-support. Since the role rebalance the Iron Sage is the second healer (1765 / 2525 per second on an
  ally, +20% / +24% over the Mystic; the Illusionist 1985 / 3007, at least 12% ahead of it).
- Open: the Necromancer line has the Mystic's stock heals (Circle of Mending, Kindred Mend, Heartwood Embrace) and is the
  second healer through them; worth a look when that line is balanced.

### Class lock (C8: the account unlock)

The Necromancer, the Monk and the Templar can only be played on an account that has unlocked them. For now the unlock is
free for the account once one of its characters reaches level 200 (since 2026-10-15; before, 500 Chaos Coins in the
store or level 500; the classes are no longer sold, docs/PRICES.md). The owner may change the method
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
  works in that state; the unlock ends the restriction at once. (`login.mode = "kick"` logs it out instead.)
  Staff (group 4+, or account type 5+) is never locked.
- Characters are created on the website: the base server has no account manager and no in-game character creation (the
  engine never inserts into `players`; its login only reads the character list). The website should offer the three classes
  only to accounts with a row in `chaos_class_unlocks`; the login check holds even if it does not.
- Character > Character Info shows the account's state; staff: `/classunlock <character>, <class>[, revoke]`.

### Ascension quest (C9, done)

Ascension is earned through a quest, not claimed with a command. The stock promotion is off: King Ormund and every other
promotion NPC of the base server used to promote premium accounts at level 20 to `Vocation:getPromotion()`, which skipped the
class system and picked one of the two ascended classes more or less at random. `server/tools/patch_promotion.py` (run by
`install_class_ascension.py`) makes them refuse with a line that points to the quest (server/README.md, install step 4b).

Decided defaults (numbers in `server/data/scripts/chaos/ascension_quest_config.lua`):

- **Who**: every base class with ascension choices, at `Chaos.classes.ascension.minLevel` (100). The lines and their two ascended
  classes are read at run time from `Chaos.classes.ascension.choices`, so Warrior, Ranger, Mystic, Thief, Monk, Necromancer and
  Templar all have it, and a new line works without code changes (it gets the default guardian until it has its own entry).
- **The Ascendant Oracle**, an NPC in a stall of the market of the teleport room of the main city (Cinderhold, town 2; `npc.townIds`, `npc_booths_config.lua`), starts and ends it.
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

### Phase 2b (done): per-class passive trees (C4)

- **Per-class keystone variants** on the two keystone nodes 621 (Wrath) and 624 (Resolve), for the Warrior, Ranger and Mystic lines
  (`ChaosClasses.keystoneKey`): the base classes keep the old pair; each ascended class of the Warrior and Ranger lines swaps the
  keystone that does not fit it:

  | Class | Wrath (621) | Resolve (624) |
  |---|---|---|
  | Warrior | Cleaving Arc | Bulwark |
  | Juggernaut | **Immovable**: 8% less damage taken, 16% below 50% health | Bulwark |
  | Berserker | Cleaving Arc | **Undying Rage**: melee weapon hits heal 4% of the damage, 8% below 50% health |
  | Ranger | Ricochet | Deadeye |
  | Deadeye | **Hunter's Focus**: bow / crossbow hits on one target +4% each, up to +20% | Deadeye |
  | Beastmaster | Ricochet | **Pack Alpha**: companion bites and Feral Command +35%, companions take 20% less |
  | Mystic, Elementalist | Arcane Echo | Elemental Overload |
  | Illusionist | Shared Phantasm | Inspiring Illusion |
  | Iron Sage (since 2026-10-12) | **Overgrowth**: heals on others heal 10% more over 6 s (3 pulses) | **Piercing Palm** (since 2026-10-20) |
  | Sentinel (since 2026-10-12) | **Radiant Rebuke** (since 2026-10-20) | **Thorns**: melee and ranged attackers take 30% of their hit + 2 x magic level as earth damage |
  | Thief, Ninja, Samurai (2026-10-20) | **Shadow Twin**: weapon hits, 30% for the shadow to strike again 0.3 s later for 60%; you take 6% more damage | **Viper's Verdict**: weapon hits on a poisoned target, 20% for x2; on a target that is not poisoned x0.85 |
  | Necromancer, Lich, Bone Lord (2026-10-20) | **Corpse Detonation**: a monster you or your minions kill explodes for 12% of its maximum health (at most 15 x level) as death on up to 6 within 2 sqm; your and your minions' hits x0.92 | **Reaper's Toll**: your and your minions' hits on a monster at 40% health or less x2, above x0.92 |
  | Monk, Shadowfist (2026-10-20) | **Seventh Palm**: every 5th melee hit (fists or weapon, 4 s) x2.2 and a 50% shockwave on up to 4 next to the target; the other melee hits x0.90 | **Piercing Palm**: melee hits pass through, 70% to the enemy behind the target, 40% to the next; the hit x0.95 |
  | Templar, Inquisitor (2026-10-20) | **Radiant Rebuke**: with a shield, 20% to block a melee/ranged hit; a block sends a holy nova (blocked hit + 4 x magic level, 2 sqm, once a second); weapon hits x0.90 | **Dawnchain**: melee weapon hits chain holy light to 2 more enemies (3 sqm) for 55% and 30%; spells x0.90 |

  Since 2026-10-20 every class may take 621 / 624 (owner: "excellent nodes like Ricochet and Deadeye for all classes";
  server/README.md "Passive tree keystones", numbers `class_keystones_config.lua`, balance `server/data/spells/README.md`
  "Signature keystones of the Thief, Necromancer, Monk and Templar lines"). Before, only the classes above the 2026-10-20
  rows could. The old druid pair (no class's since the class rework) went to the classes it fits (the owner
  approved, 2026-10-12): Overgrowth to the Iron Sage, the second healer, and Thorns to the Sentinel, the tank-support, next to
  the Juggernaut's Bulwark. Each takes only the node of its keystone, in the existing slot: no new node, no tree layout change,
  so the build code format stays, and no character held them before (nothing to refund). Overgrowth is 10% for the Iron Sage
  (30% for the old druid): at 30% the Iron Sage would pass the Illusionist in a group at level 1000. Its pulses are plain
  health, so the healer's bonuses count once (in game they counted again on each pulse: 41% instead of 30%). Computed, not
  measured: `server/data/spells/README.md` "Overgrowth and Thorns for the Iron Sage and the Sentinel".
- **Class sections** for the Thief, Necromancer, Monk and Templar lines (nodes 625-664, top left of the tree; the four lines
  share the place, each player sees only its line's section): a start node of the line, three line nodes (for the base class
  and both ascended classes) and two ascended paths, two notables and a keystone each. A base class sees both paths locked
  ("Requires: Ninja"); after the ascension it may take its own. Six points reach a keystone.

  | Ascended | Notables | Keystone |
  |---|---|---|
  | Ninja | Twin Fangs (the off-hand strike 65% instead of 50%), Fleet Shadow (evasion +4%) | **Living Shadow**: a dodge, or the first hit out of Shadow Veil, opens 4 s of +25% weapon hits and strikes |
  | Samurai (off-tank) | Steel Discipline (health, physical absorb), Iron Parry (Counter Stance answers +50%, the stance +1 s) | **Way of the Blade**: Counter Stance parries every melee hit while it lasts; a hit keeps half of the Bushido stacks |
  | Lich | Spreading Blight (the curse spreads to one more), Lingering Rot (Soul Rot +25%) | **Hoarded Souls**: Soul Hoard +40% per empty shade slot, +15% with the shade out |
  | Bone Lord | Legion (one more skeleton), Banner Bearer (Banner of Bones +45% instead of +30%) | **Bone Colossus**: the Bone Golem hits 60% harder, +50% health |
  | Shadowfist | Precise Strikes (crit), Nerve Strike (Pressure Points 6% a stack) | **Hundred Hands**: focus crits also give a chi (one per second) |
  | Iron Sage (healer) | Healing Hands (healing +8%, health), Deep Mantra (Mantra of Stone -11%) | **Flowing Mercy**: Kindled Breath also heals the next most hurt party member for 40% |
  | Inquisitor | Sacred Fire (holy damage, magic level), Burning Zeal (Radiant Strikes 30%) | **Divine Verdict**: Radiant Strikes judge their target 20% of the time |
  | Sentinel | Steadfast (absorbs), Sanctuary (aura regeneration 0.5%/s) | **Bastion**: aura -16% and 6 sqm; Aegis of Faith covers the party under the aura at half strength (-20%) |

  Line nodes: Thief Light Feet, Venom Craft, Shadow-born; Necromancer Grave Lore, Bone Craft, Dark Pact; Monk Iron Fist, Centered,
  Flowing Chi; Templar Holy Vigor, Shield of Faith, Righteous Arm (plain tree stats).
- **Mastery nodes** (2026-10, nodes 665-668): each class section has one more node above its third line node, for every class
  of the line. It costs a point like any node; the player picks one effect when planning it (free) and can change it later
  for the single-node refund price. Each effect is ordinary tree stats, about one notable's worth:

  | Line | Mastery | Effects |
  |---|---|---|
  | Thief | Shadow Discipline | Keen Edge (crit chance +2, crit amount +5), Light Step (dexterity +3, speed +20), Tough Hide (vitality +4, physical absorb +2), Venom Glands (earth +6, physical +3) |
  | Necromancer | Grave Mastery | Withering Touch (death +6, magic level +1), Ossified Hide (physical absorb +3, vitality +3), Soul Well (spirit +5, death absorb +2) |
  | Monk | Inner Discipline | Iron Knuckles (physical +6, strength +2), Swift Palm (crit chance +2, crit amount +4), Still Water (healing +6, spirit +3), Stone Body (vitality +4, physical absorb +2) |
  | Templar | Sacred Oath | Oath of Flame (holy +6, strength +2), Oath of the Wall (shielding +2, physical absorb +2, all elements absorb +1), Oath of Mercy (healing +6, vitality +3) |

  The Warrior, Ranger and Mystic lines have no class section and no mastery yet. Rules and saved data: server/README.md
  "Passive tree planner and mastery nodes". Measured 2026-10-12 (`server/data/spells/README.md` "Line keystones,
  masteries and weapons measured in game"): each damage choice adds 2-4% to its own damage type (Venom Glands earth
  +5.3%, Withering Touch death +3.9%, Iron Knuckles physical +3.9%, Oath of Flame holy +3.8%; the crit choices about +1%),
  a build 1-3%, below the spread of a rotation run. Light Step's dexterity was over the cap of a typical Thief build at
  level 300 (only its speed counted there); since the attribute caps went up (2026-10-22: dexterity cap 80, the points past
  20 at 1/15 of an old point) it adds about 0.2% to weapon hits there.
- **Line keystones** (2026-10): the Thief, Necromancer, Monk and Templar lines had one keystone per ascended class (in the
  section) and none for the base class, the other three lines two. Each of these lines now has a second keystone for
  another play style, for the base class and both ascended classes, on a converted mythic leaf of the main tree (18-21
  nodes from the start). Each has a price:

  | Line | Keystone (node) | Play style | Gain | Price |
  |---|---|---|---|---|
  | Thief | **Blackblood Creed** (383) | poisoner | every weapon hit poisons (Poison Blades without the buff), the poison +30% (+60% until 2026-10-12) | evasion halved |
  | Necromancer | **Covenant of the Grave** (369) | minion master | minions +50% damage (Bone Lord +20% since 2026-10-12) and +50% health | the own spells -25% |
  | Monk | **Scarred Discipline** (390) | brawler who takes the hits | a hit taken gives a chi (one every 2 s); -10% damage taken at 3+ chi | no evasion at all |
  | Templar | **Penitent's Wrath** (376) | retaliation | a melee / ranged hit taken is answered with a holy strike: 40% of it + 4 x magic level (one every 0.5 s) | the defence aura's reduction halved, for the party too |

  The nodes were wisdom +10, spirit +10, healing +5% and life leech 5 / 7; a character that held one gets it refunded once,
  for free, at the next login. Numbers: `server/data/spells/README.md` "Line keystones and the path notables" (computed)
  and "Line keystones, masteries and weapons measured in game" (measured 2026-10-12, level 300 / 1000, on one build with
  and without the keystone, 1 target):

  | Keystone | Class | Computed | Measured | Note |
  |---|---|---|---|---|
  | Blackblood Creed | Thief | +6% / +6% | poison +8.9% / +14.5% (total +3.7% / +7.1%) | level 1000 over the computed value |
  | | Ninja | +5% / +5% | poison +5.3% / +11.2% (total -0.8% / +11.8%) | level 1000: 4566, level with the Deadeye |
  | | Samurai | +5% / +5% | poison +7.2% / +11.9% (total +8.5% / +5.2%) | |
  | Covenant of the Grave | Necromancer | +8% / +11% | +13% / +15% (5 targets +1% / +8%) | level 300: 1246, level with the Deadeye |
  | | Lich | -10% / -8% | -12% / -10% (5 targets -18% / -20%) | as intended: not a Lich keystone |
  | | Bone Lord | +2.5% / +8% (5 targets +18%) | **+20% / +23%** (5 targets +17% / +23%) | ahead of the Deadeye (1603 / 5113); area within 6% of the Elementalist |
  | Scarred Discipline | Monk line | unchanged on dummies | -1% / +8% (spread) | in game: a chi every 2 s of hits, -10% taken at 3+ chi, no dodge |
  | Penitent's Wrath | Templar line | unchanged on dummies | +5% / +1% (spread) | in game: 600 holy per 922 taken (magic level 30), own aura 4% -> 2% |

  Done 2026-10-12 (owner approved; computed, not measured in game; `server/data/spells/README.md` "Class order fixes"):
  Covenant minion hits +20% for the Bone Lord (Necromancer and Lich +50%), Blackblood Creed's poison +60% -> +30%, and
  the level 300 class factor of the Necromancer 1.0 -> 0.93 and the Bone Lord 0.75 -> 0.63. The keystone alone could
  not fix level 300: the path build to Covenant, without it, was already level with the Deadeye. After (computed,
  level 300 / 1000, 1 target):

  | Keystone | Class | Before (measured) | After (computed) | Deadeye ahead (after) | After, measured in game 2026-10-13 (two samples where near a limit) |
  |---|---|---|---|---|---|
  | Blackblood Creed | Thief | poison +8.9% / +14.5% | poison +5.8% / +8.9% (914 / 2873) | | 891 / 2578 (**flag**: -10.3% at 1000; Deadeye +43% / +81%) |
  | | Ninja | poison +5.3% / +11.2% (1107 / 4566) | poison +3.4% / +7.1% (1154 / 4374) | +9.0% / +8.2% | 1083, 1123 / 4327, 3948 (Deadeye +15% / +13%) |
  | | Samurai | poison +7.2% / +11.9% | poison +4.8% / +7.2% (701 / 2601) | | 654 / 2218 (**flag**: -14.7% at 1000; Deadeye +94% / +111%) |
  | Covenant of the Grave | Necromancer | 1246 / 3105 | 1156 / 3103 | +8.8% / +52% | 1158, 1150 / 2970, 2952 (Deadeye +10% / +58%) |
  | | Bone Lord | 1603 / 5113 (5 targets 3186 / 10287) | 1147 / 4327 (5 targets 2295 / 8705) | +9.6% / +9.4% (Elementalist +47% / +25%) | 1162, 1177 / 4190, 4227 (5 targets 2318 / 8303, 8159; Deadeye +8.6% / +11%, Elementalist +51% / +34%) |

  Measured in game 2026-10-13 (`server/data/spells/README.md` "Class order fixes", the end of the section): every row
  within 10% of the computed one but the Thief and the Samurai with the Creed at level 1000, below it; the class order
  holds. Proposed for the two flags: no number change (far behind the Deadeye); the measured values become their
  reference. The Mystic at level 1000 with the fixed kit: 2455 / 2605 (C4 table 2439).

  The Mystic at level 1000 (1701-1824 measured against 2439) was the test kit: the character had lost levels and the
  kit picked the level 300 wand. No game change; the C4 numbers stand.
- **Path notables** (2026-10): 27 small nodes in runs of three or more along the paths became notables with their own name
  (old stats plus a modest premium, same ids and links): server/README.md "Passive tree notables on the paths".
- **Points** are unchanged (1 per 4 levels: 73 at level 300, 248 at level 1000); every class can hold more than 600 nodes, so
  the tree still cannot be completed. The Paragon track and the Vocation Trials nodes are separate bonus channels and unchanged.
- **Save data**: no node id changed (the new nodes are 625-664). At login every preset loses, for free and with a message, the
  nodes the class may not hold (another line's section, 621 / 624 for the four new lines but the Iron Sage's 621 and the
  Sentinel's 624), unknown ids and the nodes only connected
  through them (`ChaosClassTree.sanitize`). Build codes refuse nodes of another class. Nodes whose meaning changed (the four
  line keystones of 2026-10) are refunded once for every character (`passivetree_config.lua` `reworked`); build codes made
  before them (versions 1 and 2) leave them out.
- **Code**: numbers and flags in `server/data/scripts/chaos/class_tree.lua` (a storage bit per flag, read by the scripts and the
  spells); effects in `passivetree_keystones.lua` (Juggernaut, Berserker, Deadeye), `beastmaster.lua` / `classes.lua` (Pack
  Alpha), `thief_combat.lua` / `classes.lua`, `necro_core.lua` / `necro_lib.lua` / `necro_minions.lua` and the Lich spells,
  `monk_combat.lua` / `monk_chi_core.lua` and the Iron Sage spells, `templar_combat.lua` / `templar_aura_core.lua`. Client:
  `game_passivetree` (class sections, locked nodes, the class texts of "Info & Bonuses" per class), icons by
  `client/tools/gen_keystone_icons.py`. Tests: `server/tests/class_tree_test.lua`. server/README.md "Passive tree: class sections".
- **Balance**: see "Balance with the trees" below.
- **Role rebalance** (2026-10-10, the owner): the Iron Sage path became a healer path (Healing Hands, Deep Mantra, Flowing Mercy) and
  the Samurai path a duelist off-tank path (Steel Discipline, Iron Parry, Way of the Blade: the stance parries every melee hit).

### Build archetypes (2026-10-12)

The owner asked for the genre's most played build styles, at least two per class line. Twelve keystones on converted
small leaves of the main tree (refunded once), twelve uniques that push them, two summons. The guide per line is
docs/BUILDS.md; rules server/README.md "Build archetypes"; computed numbers server/data/spells/README.md "Build
archetypes" (not measured in game). Each line now has at least two archetypes, each playable with the base class:

| Line | Archetypes (new in bold) |
|---|---|
| Warrior | **Pyre Walker** (Pyre Oath, Juggernaut), **Bloodsworn Reaver** (Sanguine Covenant, Berserker), **Iron Bastion** (Thornbound Oath, Juggernaut), two-handed cleaver |
| Ranger | **Stormquiver** (Stormstring, Deadeye), marked crossbow, pack hunter |
| Mystic | **Rime Orb** (Winter's Lattice), **Effigy Caller** (Effigy Covenant), **Ember Brand** (Sigil of Cinders; all Elementalist), healer and support |
| Thief | **Plaguebearer** (Contagion Rite with Blackblood Creed), **Twin-Fang Cascade** (Cascade Edge, Ninja), duelist |
| Necromancer | bone army, **Grave Effigies** (Effigy Covenant or Winter's Lattice), rot curser |
| Monk | **Storm Palm** (Aether Edge, Shadowfist), **Hundred-Fist Cascade** (Cascade Edge), chi healer |
| Templar | **Reliquary Keeper** (Reliquary Vow, Sentinel), **Ember Brand** (Sigil of Cinders, Inquisitor), **Iron Pilgrim** (Open Hand Creed), holy area |

The role order holds: the Deadeye stays the best single target, the Elementalist the best area (its own archetypes
add at most +10%), the Juggernaut the tankiest.

### Build archetypes, second round (2026-10-12)

The three families left out at first: snares (traps and mines), vigils (auras that reserve mana) and a life on the
energy shield alone. Four more keystones on the ends of the four other elemental clusters (96, 99, 102, 105; refunded
once, build code format 5), six uniques, seven spells (Snare Trap, Seeker Mine, Detonate Mines for the Ranger and
Thief lines; four vigils for every class). Guide docs/BUILDS.md; rules server/README.md "Build archetypes", "Snares",
"Vigils"; computed numbers server/data/spells/README.md "Snares, vigils and Hollow Vessel", measured in game
2026-10-13 in "Snares, vigils and Hollow Vessel measured in game".

| Line | New options |
|---|---|
| Warrior | **Tithebound** (Iron Tithe: vigils on health, Berserker) |
| Ranger | **Trapper** and **Mine-layer** (Snarewright's Creed, Deadeye) |
| Mystic | **Choir Herald** (Covenant of Vigils, Illusionist), **Hollow Caster** (Hollow Vessel, Elementalist) |
| Thief | **Mine-layer** (Snarewright's Creed, Ninja), Trapper |
| Necromancer | **Choir Herald** (Bone Lord), **Hollow Caster** (Lich) |
| Monk | **Hollow Palm** (Hollow Vessel with Aether Edge, Shadowfist), **Tithebound** |
| Templar | **Choir Herald** (Sentinel), **Tithebound** (Inquisitor), Hollow Vessel |

The role order holds: the Deadeye and the Elementalist stay the leaders, the Illusionist and the Iron Sage stay the
healers. Measured in game (2026-10-13) the snares passed the Elementalist in area, so the snare hit was halved; the
snare rows are computed again (the best, a Mine-layer Deadeye, now -43% in area on the computed rows and about -3% /
-18% at level 300 / 1000 when the halving is applied to the measured snare share; measured again after the halving:
the Mine-layer Deadeye 3372 in area at level 300, the Mine-layer Ranger 10536 at level 1000, just under the
Elementalist's 3496 / 10837-11275). **Flag (measured, not applied):** the Hollow Palm with the Aetherbound Plate deals
5342 on one target at level 1000, 14% over the Deadeye's 4670-4685 (computed 4367); proposed fix: Aether Edge counts
only the items' part of the shield while Hollow Vessel is held (about 4300 then). The vigils, Iron Tithe and Hollow
Vessel's shield, recharge and immunities measured as written.

### Balance with the trees

Every class measured the same way at levels 300 and 1000 with a tree build (`server/data/spells/README.md` "Classes with the
passive trees"). The level factors that stood in for the tree are dropped; the four new lines' damage is scaled by a per-class
factor (`ChaosClassTree.classDamage`, level 300 to 1000). The owner's targets (2026-10-11): the Deadeye and the Elementalist at
least 8-10% ahead of the next class, met by trimming the classes right behind (Ninja 0.45 / 0.57, Shadowfist 0.49 / 0.69, Lich
0.50 / 0.57, Bone Lord 0.75 / 0.61, Inquisitor 0.65 / 0.58, Berserker 0.78 / 1.0, Ranger and Beastmaster 1.0 / 0.95; level 300 /
1000), not by raising the leaders. 2026-10-12, after the keystone check: Necromancer 1.0 -> 0.93 and Bone Lord 0.75 -> 0.63
at level 300 (Covenant path builds; "Line keystones" above). Result (level 300 / 1000): Deadeye the best single target (1312 / 4571; Shadowfist -10% / -19%,
Lich -11% / -12%, Bone Lord -12% / -10%, Ninja -15% / -22%); Elementalist the best area (3442 / 11004; Berserker -15% / -25%,
Beastmaster -44% / -16%); Illusionist the best healer (1985 / 3007 per second on an ally), Iron Sage the second (1765 / 2525,
+20% / +24% over the Mystic's 1473 / 2039; group +20% / +22%); Samurai a bit under the Juggernaut's damage with off-tank toughness
(about 15.4 effective health per level, Sentinel 17.3, Juggernaut 19.6). Table: `server/data/spells/README.md` "Classes with the
passive trees"; the harness spread is about +-5% per run, so the leads are on means of several runs.

### Pack cleave (2026-10-14, pack combat)

Owner request: players kill packs, not one monster at a time, and the classes stay within reason. The classes with
little area damage (C4 area share under ~30%) get a PvE cleave (`pace_config.lua` `cleave`; server/README.md "Pack combat
(pace)"): a direct hit on a hunting monster also hits the nearest monsters within 1 sqm of it for a share. Thief, Samurai,
Necromancer 25% to 3 monsters; Monk, Iron Sage 20% to 3; Deadeye, Shadowfist 20% to 2; Ninja 15% to 2. Never bosses,
players or summons, no cleave from a cleave, not in the instanced modes (rifts, tower, Descent, arena). Experience per
hour against the median class (pack model, 300 / 800 / 1000): the slowest classes now 0.78-0.90 (were 0.36-0.50); the
strongest area classes (Elementalist, Mystic, Berserker, Beastmaster) stay at 1.3-1.6 (open: owner decision).

Second pass (2026-10-15, owner: every class must farm packs comfortably; RNG and min-maxing decide the top; the top
pack class keeps what it has, every other class is raised to about 0.92 of it; the classes that needed a large cleave
get pack tools of their lore instead): the Thief line's area strikes Blade Flurry (all three, every monster within 2 sqm)
and Iaido Sweep (Samurai), and the pack tools (`_packtools.lua`): Fan of Knives (Thief), Palm Shockwave (Monk line),
Shadow Ricochet (Shadowfist), Iron Chain (Iron Sage), Bone Shrapnel (Necromancer), Sanctified Ground (Templar), Shield
Wave (Sentinel). Each hits its target like the filler it replaces (a boss takes no more) and the rest of the pack 1-2.5x
that; players never take the pack share. Every class but the Elementalist cleaves to 4 monsters, the share growing from
level 300 to 1000: Juggernaut 15-26%, Deadeye 28-21%, Ranger 23-20%, Samurai 17-19%, Illusionist 12-17%, Shadowfist 16%,
Templar 3-16%, Sentinel 6-16%, Iron Sage 11-15%, Necromancer 2-14%, Inquisitor 8-13%, Monk 6-12%, Thief 10-11%, Warrior
6-11%, Ninja 12-6%, Lich 10-7%, Bone Lord 6%, Beastmaster 9-0%, Berserker 0-3%, Mystic 0-2%; a summon's hits cleave by
its master's class. Experience per hour in packs (`server/tools/pack_model.py`): every class 0.93-0.96 of the
Elementalist at 300, 800 and 1000 (was 0.47-1.00); leveling 1-1000 of the median class 169 h -> 132 h. Single-target and
PvP damage unchanged (the cleave never hits a boss or a player; the new spells hit a lone target like the filler).
Table: `server/data/spells/README.md` "Pack farming for every class".

### Late spells, levels 340-460 (C6, 2026-10-20)

Report: ascended classes had no new spell above level 300. The cure (status-cleanse) spells were retired for all classes
(`server/tools/retire_cure_spells.py`) and their 7 ids reused. Numbers are computed (rotation sim), not measured in game.

| Class | Spell | Words | Level | Mana | Cooldown | Effect |
|---|---|---|---|---|---|---|
| Juggernaut | Bastion Cry (29) | vok gal rhov kor | 340 | 500 | 40 s | Taunt radius 6, 35% slow 6 s, Iron Will 12 s, heals 10% max health |
| Juggernaut | Anvil Fall (58) | kah gal brak thun | 380 | 450 | 20 s | 5x5 blow, about 0.8 of Colossus Fall, 90% slow 2.5 s |
| Deadeye | Twin Verdict (144) | kah gal sol judh vael | 400 | 900 | 24 s | Two strikes of 1.3 x Final Verdict, 0.6 s apart |
| Berserker | Rampage Leap (145) | drai skai hrun vas | 380 | 400 | 18 s | Skyfall variant, 5x5, about 1.6x damage, 50% slow 2.5 s |
| Elementalist | Glacial Doom (146) | drai hyr infr doma | 420 | 2200 | 60 s | Doomtide variant, ice/energy/ice, x1.9, 2 s cast |
| Beastmaster | Pack Frenzy (147) | kah ferh vas | 320 | 450 | 20 s | 2.2x the bites of Feral Command |
| Ninja | Shuriken Tempest (164) | kah sai vas hyr | 270 | 600 | 30 s | Target and 8 within 4 sqm, 2 waves of 1.1x |

Not covered, no free id: Illusionist, Samurai, Lich, Bone Lord, Shadowfist, Iron Sage, Inquisitor, Sentinel. Max 15 own spells
per ascension. Pinned by `server/tests/class_spell_progression_test.lua`.

### Phase 2b (open)

- Healing for the Thief line (a spell; the potions are done: the Royal Paladin's), starting gear for every class,
  outfits, the classes in `admin/testkit.lua` (other work).
- Base server scripts that test vocation ids by number (e.g. the familiar system, `firstitems.lua`, NPCs with `isDruid`) were not
  reviewed (other work).

## More class ideas for later

- **Warlock / Hexblade**: curses and damage over time, life drain; melee caster.
- **Shaman**: totems that pulse buffs, heals or damage in an area; a stationary support.
- **Blood Knight**: spells cost health instead of mana; huge life leech; high risk, high reward.
- **Chronomancer**: slows, hastes and rewinds (restore health and position from 3 seconds ago).
- **Engineer / Gunslinger**: turrets, traps and a heavy ranged weapon (needs new art).
- **Spellblade**: melee hits charge spell power, and spells empower the next weapon hits.

### Build archetypes, third round (2026-10-20)

Eight keystones for the lines with the fewest: Warrior, Juggernaut, Berserker (Executioner's Verdict, Earthbreaker,
Rampage, Last Stand) and Ranger, Deadeye, Beastmaster (Longshot, Barbed Quiver, Opening Shot, Hobbling Shot). Refunded
once (build code format 6). Rules server/README.md "Build archetypes"; guide docs/BUILDS.md.
