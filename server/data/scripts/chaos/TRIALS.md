# Vocation Trials (special nodes behind a challenge)

A second layer on top of the passive tree. Every vocation has a **Trial**: a solo, runtime-built instance with three
difficulties (Normal, Cruel, Merciless). The first clear of a difficulty opens one **pair** of special nodes for that
vocation, so a character ends up with three pairs (six nodes) and holds **one node of each pair, never both**. The nodes
are strong, build-defining and used to carry a price; since the owner decision they are pure gains (the downsides were removed from all 126 nodes). Holding another node of a pair later costs a Trial Token and gold. Ascension nodes have no downside (owner decision): every node is a pure gain.

The special nodes are **not** passive points: they have their own storage, are not touched by the tree's resets
(refund, full reset, build codes, store reset), and need no connection to the tree.

Code: `trials_config.lua` (every number), `trials_nodes.lua` (the 126 nodes), `trials_core.lua` (pure rules, tested by
`server/tests/trials_test.lua`), `trials.lua` (instance, storage, rewards, opcode), `trials_effects.lua` (what the nodes do
in combat); NPC `data/npc/Keeper of Trials.xml`; monsters `data/monster/monsters/chaos/trials/`; client
`game_passivetree/trials.lua`, `trials.otui`, `trialsmath.lua`.

## Rules

| | |
|---|---|
| Who | Every vocation of `Chaos.classes` (7 base classes and both ascensions of each: 21). A base class that has not ascended has its own trial and nodes; after ascending, the ascended vocation has another set (progress is kept per vocation id). |
| Entry | The tree window's **Trials** button (the menu), or the **Keeper of Trials** in a stall of the hub (the market of Cinderhold's teleport room, `npc_booths_config.lua`; "trials": a window lists the three difficulties; not on the greeting, which would hide the Ascendant Oracle's Choice window next to it). In a protection zone, out of combat, not multi-clienting, not in a rift / the ascension trial. **Solo**: a party does not come along. |
| Level gate | Normal 100, Cruel 250, Merciless 400. A tier needs the one before it cleared (as that vocation). |
| Time and lives | 8 / 9 / 10 minutes. 3 / 3 / 2 lives. A lethal hit is **caught** (no death, no experience or item loss): it costs a life, heals the character, puts it back at the start with 4 s of shield. No life left, the time, leaving the room or logging out fail the run. Nothing is lost on a failed run; the door closes for 60 s. |
| Difficulty | The guardian's health is `hp x (level / tier level) ^ 1.5` (level clamped to the tier's window, a vocation variant multiplies it). The size of every hit the trial's monsters deal is a **share of the character's maximum health** (7% / 9% / 12% for the guardian, 2.5% / 3.5% / 5% for thralls), so the fight is the same for a weak and a strong build: it tests movement and the mechanics, not gear alone. The character's own damage nodes, absorbs and mitigation nodes still apply. |
| First clear | Opens that tier's pair of nodes for the vocation, pays gold to the bank (4000 x level x tier), Orbs of Upheaval (2 / 4 / 8) and Orbs of Fate (0 / 1 / 3). |
| Clear again | One **Trial Token** (held up to 10) and a small reward (800 x level x tier gold, 1 / 2 / 3 Orbs of Upheaval, 1 Orb of Fate on Merciless), the reward at most 5 times per week; the token always comes. |
| Choosing | The first node of a pair is free. Choosing one locks the other. |
| Changing | **Rule: one Trial Token + level x 250 gold** (carried gold, then the bank) to move to the other node of a pair or to give a pair up (the **Clear** button of the pair's row in the Trials window). Not in combat, not during a trial. Tokens come only from clearing a tier you have already cleared (so changing a build is a small challenge, not only a gold sink). |
| Crash / restart | A run in progress writes a marker storage. At the next login a character found with it (or standing in a trial room) is moved to the temple, the marker is cleared and the failed-attempt cooldown is not applied: the attempt does not count. Nothing was spent to enter, so there is nothing to give back. |
| Anti-abuse | Everything is checked on the server again (level, tier order, vocation, zone, combat, multi-client, other runs, slot, cooldown); one run per character; the win needs the guardian to die while the character is alive in the room and the fight to have lasted a few seconds; rewards are paid once from `finish`; actions are rate-limited; the room cannot be entered by walking (its own far-away grid) and a character found in it without a run is moved out. GM test commands (`/trial`) are access-gated. |
| Achievements | Trial by Fire / No Mercy Asked / Merciless (the three tiers), Three Choices (hold a node of every pair), Pilgrim of Trials (10 clears), Changed Mind (first change). A leaderboard hook was left out (not trivial). |
| Build codes | The special nodes are **not** in the build code (CB1): they depend on clears and switching costs a token, so a pasted code must never change them. |

## The trials (one per class family)

All monsters are two XMLs with existing looks (`Trial Warden` for the guardian, `Trial Thrall` for the rest), renamed and
dressed per family at run time (`trials_config.lua families`), like the ascension trial's Warden. The mechanics are
composed from a small set: **waves** of thralls (4 / 5 / 6 per wave, one extra wave per tier above Normal), **stillness**
(standing on one tile for 3 s with the guardian alive is punished by a slam), **zones** (marked tiles burst after 1.5 s),
**adds** (the guardian calls thralls), **enrage** (+50% hits below 30% health), **seals** (stand on the named seal for
2.5 s), **marks** (fast targets that must die in 16 / 13 / 10 s or they escape and cost 20 s of the clock), **pyre** (every
11 s the fire sweeps the room; a sanctuary light protects those within one tile), **rise** (a dead thrall stands up once
with 60% health, 60% of the time). Stillness, zones, adds and enrage only run in the guardian fight.

| Family | Vocations | Trial | Stages and mechanics | Hint |
|---|---|---|---|---|
| Warrior | Warrior, Juggernaut, Berserker | The Iron Gauntlet | 2 waves (+1 / +2), the Gauntlet Champion; stillness, enrage. Juggernaut: guardian hits +15%, fewer thralls. Berserker: more thralls. | Do not stand still against the Champion. |
| Ranger | Ranger, Deadeye, Beastmaster | The Hollow Moon Hunt | 2 waves of fast Moon Hounds, the Moon Stalker; zones, stillness. Deadeye: sturdier stalker. Beastmaster: more hounds. | Read the marks before the volley lands. |
| Mystic | Mystic, Elementalist, Illusionist | The Seals of the Elements | 3 / 4 / 5 seals broken in the order the HUD names (fire, ice, energy, earth by colour; a wrong seal burns you), thralls harass; the Keeper of the Seals; zones, adds. | Puzzle first, fight second. Illusionist: a gentler keeper. |
| Thief | Thief, Ninja, Samurai | The Night Run | 3 / 4 / 5 marks against the clock (a mark that escapes costs 20 s), the Master of Shadows; zones, stillness. | Speed. |
| Monk | Monk, Shadowfist, Iron Sage | The Silent Ascent | 2 waves of acolytes, the Warden of the Still Fist; stillness, zones. | Keep moving. |
| Necromancer | Necromancer, Lich, Bone Lord | The Grave Tithe | 2 waves whose dead rise once more, the Tithe Collector; adds, zones, rise. Bone Lord: more thralls. | Break them twice. |
| Templar | Templar, Inquisitor, Sentinel | The Trial of Fire | 1 wave (+1 / +2), the Pyre Warden; the pyre sweeps the room throughout, enrage. | Stand next to a sanctuary light when the fire breaks. |

The run HUD is the rift HUD (title, clock, lives, progress, the live note: wave, next seal, mark timer).

## The nodes

Pair 1 opens with Normal, pair 2 with Cruel, pair 3 with Merciless. Numbers are first-pass balance. Percent keys add up
(damage dealt is one multiplier, bounded 0.25 .. 2.5; damage taken 0.3 .. 2.0). Keys and their meaning
(`ChaosTrialsCore.KEYS`):

| Group | Keys |
|---|---|
| Damage dealt | `dealAll`, `dealMelee`, `dealRanged`, `dealSpell`, `dealDot`, `dealMinion` (hits of your summons), `dealPhysical/Fire/Ice/Energy/Earth/Death/Holy`, `dealLowHp` (below 35% own health), `dealHighHp` (above 90%), `dealFirst` (target above 90%), `dealExecute` (target below 30%) |
| Damage taken | `takeAll`, `takeMelee` (melee and ranged), `takeMagic` (spells and damage over time), `takeLowHp` |
| Defence | `evade` (avoid a melee or ranged hit, capped 35%), `reflect` (melee, capped 50%), `manaShield` (part of a hit paid from mana, capped 50%), `lastStandCd` (survive a lethal hit with 1 health, cooldown in seconds) |
| Procs | `echoChance/echoPct` (a hit strikes again after 0.35 s), `novaChance/novaPct/novaRadius` (a hit bursts on enemies around the target), `killStackPct/Max/Ms` (each kill adds damage for a time), `killHeal`, `killMana`, `leechMelee/Spell/All` (capped 20%) |
| Healing | `healOut`, `healIn` |
| Spell events (engine patch 0008, `ChaosSpellEvents`) | `spellCost`, `spellCd` (cost bounded -60%, cooldown -50% and never below 1 s). Without the patch these two parts of a node do nothing; the nodes still work for their other key. |
| Passive-tree stats | `criticalHitChance`, `criticalHitAmount`, `vitality`, `spirit`, `absorbPhysical/Fire/Ice/Energy/Holy`, `absorbAllElements`: applied by `passivetree_effects.lua` as for any node (positive only) |

How it is wired: `passivetree.lua applyBonuses` calls `ChaosTrials.addBonuses(player, bonuses)` next to the Paragon, which sums
the held nodes of the player's vocation into the bonus table (`ChaosPassiveCache`). The tree's stats flow through the existing
machinery; the rest is read by `trials_effects.lua` (one `onHealthChange` event on what the player hits and on the player,
a kill event, and the spell events). Extra hits (echo, nova, reflect) are dealt with the keystones' guard raised, so
they never trigger further procs or bonuses.


## Client

The passive tree window has a **Trials** button (next to Paragon and Build Code) that opens the Vocation Trials window:
the trial's name and story, three **Enter** buttons (tooltips: level, minutes, lives, the guardian's health, why it is
closed), the Trial Token line with the change price, and the three pairs as **two cards side by side**: name, the gains
(green) and the price (red), a one-line flavour text, and a button (Choose / Switch / Held / Locked). A locked pair says
"Locked: clear on Cruel" and hides its effects. Every box has an explicit size and fixed single lines (the texts are
shortened by `TrialsMath.fit`, the longest line is 46 characters), the tooltip carries the long text. Choosing or switching
asks for a confirmation that lists the gain and the price. Protocol: `trialRequest`, `trialChoose {pair, side}`,
`trialEnter {tier}`, `trialLeave` and the answer `trialState` on the passive tree's opcode (65).

## GM commands (access group)

`/trial clear <0-3>` set the cleared tier of the current vocation, `/trial tokens <n>`, `/trial fast` (the next guardian has
200 health), `/trial reset`, `/trial enter <tier>`, `/trial status` (held nodes and the summed node bonuses), `/trial win` (kills the guardian).

## Balance caveats

* The guardian's health is the one number that cannot be derived from the damage a build deals; it is set by level
  (`hp` per tier in `trials_config.lua`) and will need tuning with play data. Hits are a share of the maximum health, so only
  the kill time can be wrong, never an unwinnable one-shot.
* Several nodes are strong on purpose (Avatar of Iron, Frenzy +35% below 35% health, Cataclysm +25% spell damage, Final Verdict +40% to enemies
  under 30%). With the downsides gone, the pair choice is only a choice between two different gains; watch for a node that is better for everyone.
* Nodes that scale with target health (`dealFirst`, `dealExecute`) work against bosses only through the 90% / 30% windows.
* `dealMinion` only affects hits whose attacker is a summon with a player master; the necromancer lines whose minions hit
  "as their owner" (necromancer scripts) get the Necromancer's `dealSpell` instead if the hit is attributed to the player.
* The special nodes stack with the keystones and Paragon (multipliers are separate: the nodes are one additional multiplier
  after the passive tree's); the bounds above are the safety net.
* Spell events (patch 0008): 3 nodes name a cost or cooldown part (Thrifty Weave, Arcane Haste, Lucid Mind); they are marked in the table.
* After an ascension the new vocation's nodes apply at the next passive tree apply (login, a tree save); the old set stays stored.
* Test numbers: merciless guardian health at level 1000 is about 500k; thrall health 9-10% of it.

## Data-only / not done

* Leaderboard hook, build-code integration (deliberately left out), a separate sound/visual for the pyre and seals (they use
  stock magic effects), a per-vocation boss look (family looks only).
* Node icons: the cards are text only (no new sprites).

## Tests and verification

* `server/tests/trials_test.lua`: the node tables of all 21 vocations (126 nodes, names, no downsides, signs, line lengths), packing,
  choosing and switching rules, tiers and scaling, rewards and the weekly cap, the combat maths, the run mechanics, the room
  geometry (no overlap with the rift grid or the ascension trial), the client state. `server/tests/trials_flow_test.lua`:
  trials.lua / trials_effects.lua with a mocked engine (load, names, the choose / switch / bonus flow, the spell events).
  `client/overlay/modules/game_passivetree/trialsmath_test.lua`: the cards and buttons of the window.
* In game (a test server and client, Berserker, level 600): the Keeper's window and the tree window's button start a run; a wave
  and the guardian appear, the HUD shows the clock, lives and wave; four lethal hits in one tick cost one life (the player is
  healed and put back at the start); the first clear of Normal opened pair 1, choosing Bloodlust applied its stats
  (`killStack*`, `takeAll`) and a 1000-point melee hit grew 1200, 1248, 1296, 1344, 1392 over five kills; the other node was refused
  without a token (button disabled and the server's own message); a second clear paid a token and the repeat reward; the switch
  took the token and 150000 gold and applied Cleaver's Hunger (`leechMelee`, `takeMelee`); the tree's reset left the picks; a
  hard kill of the server inside a run was recovered at the next login (moved out, no cooldown); the first clear of Cruel opened pair 2.

## The table of all vocations

#### Warrior - The Iron Gauntlet

Waves of iron-bound thralls, then the Champion. Do not stand still against it: it crushes whoever plants their feet.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Warrior | 1 (Normal) | **Reckless Blows**. Gives: +15% melee damage. | **Steady Guard**. Gives: -12% melee and ranged damage taken. |
|  | 2 (Cruel) | **Second Wind**. Gives: 2.5% of max health restored per kill. | **Iron Hide**. Gives: +6% physical damage absorbed. |
|  | 3 (Merciless) | **Warlord's Rage**. Gives: Each kill: +3% damage for 8 s, up to 8 times. | **Last Bastion**. Gives: Survive a lethal hit (once per 90 s). |
| Juggernaut | 1 (Normal) | **Bulwark of Ages**. Gives: -10% damage taken. | **Thornwall**. Gives: 18% of melee damage is reflected back. |
|  | 2 (Cruel) | **Rallying Roar**. Gives: 3% of max health restored per kill. | **Steelblood**. Gives: +8% maximum health. |
|  | 3 (Merciless) | **Immortal Stand**. Gives: Survive a lethal hit (once per 75 s). | **Wall Unbroken**. Gives: -30% damage taken below 35% health. |
| Berserker | 1 (Normal) | **Bloodlust**. Gives: Each kill: +4% damage for 6 s, up to 6 times. | **Cleaver's Hunger**. Gives: 4% of melee damage returned as health. |
|  | 2 (Cruel) | **Frenzy**. Gives: +35% damage below 35% health. | **Rend Flesh**. Gives: +30% damage over time. |
|  | 3 (Merciless) | **Avatar of Iron**. Gives: +20% damage below 35% health; -25% damage taken below 35% health. | **Deathless Fury**. Gives: +20% damage below 35% health; Survive a lethal hit (once per 100 s). |

#### Ranger - The Hollow Moon Hunt

A fast pack, then the Stalker, whose volleys mark the ground before they land. Read the marks.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Ranger | 1 (Normal) | **Steady Aim**. Gives: +14% ranged damage. | **Quick Draw**. Gives: 15% chance: a hit strikes again for 50%. |
|  | 2 (Cruel) | **Hunter's Instinct**. Gives: +25% damage vs enemies over 90% health. | **Fleet Footed**. Gives: +8% chance to avoid a melee or ranged hit. |
|  | 3 (Merciless) | **Death From Afar**. Gives: +30% damage vs enemies under 30% health. | **Pack Leader**. Gives: 12% chance: a hit bursts within 2 sqm for 40%. |
| Deadeye | 1 (Normal) | **Dead Center**. Gives: +25% critical hit damage; +4% critical hit chance. | **Called Shot**. Gives: +30% damage vs enemies over 90% health. |
|  | 2 (Cruel) | **Marksman's Patience**. Gives: +22% damage above 90% health. | **Hair Trigger**. Gives: 18% chance: a hit strikes again for 60%. |
|  | 3 (Merciless) | **Final Verdict**. Gives: +40% damage vs enemies under 30% health. | **Ghost Quiver**. Gives: 3% of max health restored per kill; 3% of max mana restored per kill. |
| Beastmaster | 1 (Normal) | **Alpha Bond**. Gives: +25% minion damage. | **Wild Volley**. Gives: 14% chance: a hit bursts within 2 sqm for 45%. |
|  | 2 (Cruel) | **Pack Hide**. Gives: -8% damage taken. | **Feral Surge**. Gives: Each kill: +3% damage for 8 s, up to 6 times. |
|  | 3 (Merciless) | **Apex Predator**. Gives: +40% minion damage. | **Spirit Hunter**. Gives: 3% of all damage returned as health. |

#### Mystic - The Seals of the Elements

Four seals burn in four colours. Break them in the order the Keeper speaks, or the wrong one will punish you.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Mystic | 1 (Normal) | **Overchannel**. Gives: +15% spell damage. | **Thrifty Weave** *(needs patch 0008)*. Gives: -20% mana cost of spells. |
|  | 2 (Cruel) | **Mana Ward**. Gives: 25% of damage taken is paid from mana. | **Arcane Haste** *(needs patch 0008)*. Gives: -15% spell cooldowns. |
|  | 3 (Merciless) | **Elemental Surge**. Gives: 15% chance: a hit strikes again for 50%. | **Archmage's Poise**. Gives: +25% damage above 90% health. |
| Elementalist | 1 (Normal) | **Pyromania**. Gives: +22% fire damage. | **Glacial Focus**. Gives: +22% ice damage. |
|  | 2 (Cruel) | **Stormcaller**. Gives: +22% energy damage. | **Chain Reaction**. Gives: 15% chance: a hit bursts within 2 sqm for 45%. |
|  | 3 (Merciless) | **Cataclysm**. Gives: +25% spell damage. | **Prismatic Ward**. Gives: +10% energy damage absorbed; +10% fire damage absorbed; +10% ice damage absorbed. |
| Illusionist | 1 (Normal) | **Mender's Gift**. Gives: +20% healing you cast. | **Lucid Mind** *(needs patch 0008)*. Gives: -25% mana cost of spells. |
|  | 2 (Cruel) | **Warding Veil**. Gives: -10% damage taken. | **Phantom Strike**. Gives: +20% spell damage. |
|  | 3 (Merciless) | **Wellspring**. Gives: 3% of max health restored per kill; 3% of max mana restored per kill. | **Grand Illusion**. Gives: Survive a lethal hit (once per 80 s). |

#### Thief - The Night Run

Marked cutthroats come one after another, fast. Each that slips away costs you time. Then the Master.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Thief | 1 (Normal) | **Cutpurse's Edge**. Gives: +14% melee damage. | **Slippery**. Gives: +10% chance to avoid a melee or ranged hit. |
|  | 2 (Cruel) | **Opportunist**. Gives: +28% damage vs enemies over 90% health. | **Poison Craft**. Gives: +30% damage over time. |
|  | 3 (Merciless) | **Kingpin's Backstab**. Gives: +30% critical hit damage; +4% critical hit chance. | **Vanishing Act**. Gives: Survive a lethal hit (once per 80 s). |
| Ninja | 1 (Normal) | **Twin Fangs**. Gives: 20% chance: a hit strikes again for 50%. | **Shadow Flurry**. Gives: +20% melee damage. |
|  | 2 (Cruel) | **Smoke Cloak**. Gives: +12% chance to avoid a melee or ranged hit. | **Venom Dance**. Gives: +40% damage over time. |
|  | 3 (Merciless) | **Shadow Clones**. Gives: 15% chance: a hit bursts within 2 sqm for 50%. | **Assassinate**. Gives: +40% damage vs enemies under 30% health; +20% damage vs enemies over 90% health. |
| Samurai | 1 (Normal) | **Iaijutsu Edge**. Gives: +35% damage vs enemies over 90% health. | **Way of the Counter**. Gives: 22% of melee damage is reflected back. |
|  | 2 (Cruel) | **Bushido Resolve**. Gives: +25% critical hit damage; +4% critical hit chance. | **Parry Master**. Gives: +12% chance to avoid a melee or ranged hit. |
|  | 3 (Merciless) | **Heavenly Strike**. Gives: +28% melee damage. | **Last Honour**. Gives: +40% damage below 35% health; Survive a lethal hit (once per 100 s). |

#### Monk - The Silent Ascent

Two waves of acolytes, then the Warden. Stillness is the lesson: keep your feet moving against it.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Monk | 1 (Normal) | **Quick Palm**. Gives: +14% melee damage. | **Flowing Water**. Gives: +10% chance to avoid a melee or ranged hit. |
|  | 2 (Cruel) | **Inner Fire**. Gives: 2% of max health restored per kill; 3% of max mana restored per kill. | **Stone Breath**. Gives: -8% damage taken. |
|  | 3 (Merciless) | **Hundred Fists**. Gives: 20% chance: a hit strikes again for 50%. | **Enlightened**. Gives: +4% critical hit chance; 3% of melee damage returned as health. |
| Shadowfist | 1 (Normal) | **Pressure Point**. Gives: +20% damage vs enemies under 30% health; +25% damage vs enemies over 90% health. | **Focus Break**. Gives: +25% critical hit damage; +5% critical hit chance. |
|  | 2 (Cruel) | **Flurry Master**. Gives: 22% chance: a hit strikes again for 55%. | **Ghost Step**. Gives: +14% chance to avoid a melee or ranged hit. |
|  | 3 (Merciless) | **Killing Touch**. Gives: +30% melee damage. | **Soul Siphon**. Gives: 3% of max mana restored per kill; 6% of melee damage returned as health. |
| Iron Sage | 1 (Normal) | **Mantra of Stone**. Gives: -10% damage taken. | **Iron Palm Echo**. Gives: 14% chance: a hit bursts within 2 sqm for 40%. |
|  | 2 (Cruel) | **Chi Reservoir**. Gives: 30% of damage taken is paid from mana. | **Warden's Breath**. Gives: +25% healing you cast. |
|  | 3 (Merciless) | **Mountain Stance**. Gives: Survive a lethal hit (once per 70 s). | **Avatar of Calm**. Gives: -30% damage taken below 35% health. |

#### Necromancer - The Grave Tithe

The dead here stand up a second time. Break them again, and the Collector who calls for more.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Necromancer | 1 (Normal) | **Grave Pact**. Gives: +22% minion damage. | **Bone Spear Mastery**. Gives: +10% death damage; +18% spell damage. |
|  | 2 (Cruel) | **Corpse Harvest**. Gives: 3% of max health restored per kill; 3% of max mana restored per kill. | **Withering Aura**. Gives: +30% damage over time. |
|  | 3 (Merciless) | **Lord of Rot**. Gives: +25% death damage. | **Deathless Servant**. Gives: 25% of damage taken is paid from mana. |
| Lich | 1 (Normal) | **Soul Rot**. Gives: +40% damage over time. | **Phylactery**. Gives: Survive a lethal hit (once per 80 s). |
|  | 2 (Cruel) | **Siphon Spirit**. Gives: 5% of spell damage returned as health. | **Doom Whisper**. Gives: +25% death damage. |
|  | 3 (Merciless) | **Corpse Cascade**. Gives: 18% chance: a hit bursts within 2 sqm for 55%. | **Eternal Hunger**. Gives: Each kill: +3% damage for 8 s, up to 8 times. |
| Bone Lord | 1 (Normal) | **Marrow Banner**. Gives: +30% minion damage. | **Ossified Plate**. Gives: -8% damage taken. |
|  | 2 (Cruel) | **Bone Shrapnel**. Gives: 15% chance: a hit bursts within 2 sqm for 40%. | **Grave Tithe**. Gives: 3% of max health restored per kill; 2% of max mana restored per kill. |
|  | 3 (Merciless) | **Colossus Slam**. Gives: +45% minion damage. | **Sacrifice Rite**. Gives: Survive a lethal hit (once per 100 s); 30% of damage taken is paid from mana. |

#### Templar - The Trial of Fire

The fire sweeps the whole room. Stand beside a sanctuary light when it breaks, and keep fighting between the waves.

| Vocation | Pair | Node A | Node B |
|---|---|---|---|
| Templar | 1 (Normal) | **Radiant Strikes**. Gives: +18% holy damage. | **Shieldbearer**. Gives: -8% damage taken. |
|  | 2 (Cruel) | **Vow of Mending**. Gives: +15% healing you cast; 2% of max health restored per kill. | **Zeal**. Gives: Each kill: +3% damage for 8 s, up to 8 times. |
|  | 3 (Merciless) | **Consecrated Ground**. Gives: 15% chance: a hit bursts within 2 sqm for 45%. | **Martyr's Grace**. Gives: +10% holy damage absorbed; Survive a lethal hit (once per 80 s). |
| Inquisitor | 1 (Normal) | **Judgement**. Gives: +25% holy damage. | **Purging Fire**. Gives: +12% holy damage; 12% chance: a hit bursts within 2 sqm for 40%. |
|  | 2 (Cruel) | **Zealotry**. Gives: Each kill: +4% damage for 6 s, up to 6 times. | **Penance**. Gives: 20% of melee damage is reflected back. |
|  | 3 (Merciless) | **Wrath of Dawn**. Gives: +40% damage vs enemies under 30% health. | **Light's Retribution**. Gives: 20% chance: a hit strikes again for 55%. |
| Sentinel | 1 (Normal) | **Aegis of Faith**. Gives: -12% damage taken. | **Rebuke**. Gives: 25% of melee damage is reflected back. |
|  | 2 (Cruel) | **Lay on Hands**. Gives: +25% healing you cast. | **Vigil**. Gives: 25% of damage taken is paid from mana. |
|  | 3 (Merciless) | **Unyielding Faith**. Gives: Survive a lethal hit (once per 70 s). | **Beacon**. Gives: +6% elemental damage absorbed; +12% holy damage absorbed. |
