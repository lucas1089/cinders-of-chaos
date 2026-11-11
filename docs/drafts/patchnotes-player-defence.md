# Defence has a new order: four resistances, armour that depends on the hit
Date: 2026-11-21
Kind: news

<!-- DRAFT. Not shown to players. Why here: the server shows a notes file as soon as it is installed, whatever its
date, so this file stays out of server/data/patchnotes until the change goes live.
To publish: copy it to server/data/patchnotes/YYYY-MM-DD.md (and the .pt-br.md twin), remove every comment, run
install_all.py. Test: cd server && luajit tests/patchnotes_test.lua.
Facts used: server/README.md "Player defence (O464)". Not run on a live server: confirm the numbers after a test hunt. -->

How your character defends has changed. Read this before you hunt.

**Four resistances.** Fire is fire. Cold is ice, water and drowning. Lightning is energy, holy and arcane. Chaos is earth,
death, life drain and mana drain. Everything that gave you a resistance before still counts, at its full value: gear, sets, gems and
charms. The passive tree and Paragon now count half of their points toward a resistance, and at most 30 from the tree: the gear covers the rest. A resistance is held at 75. Physical damage is not a resistance: it has armour.

**A penalty by level.** From level 250 every resistance loses 30 points, from level 500 it loses 60. You get a warning at
login and when you level up from 240 to 249 and from 490 to 499, and a message when you pass the mark. A resistance can go
below zero: you then take more damage from that kind. Raise your resistances with gear and the tree before the marks.

**Armour depends on the hit.** Armour takes a big share off a small hit and a small share off a big one. A character with a
full set of armour pieces takes about 85% less from a typical monster hit, and about half from a boss hit. The physical
reduction of gear and the tree adds to it. Armour and reduction together never take more than 90%.

**The order of a hit.** First it can miss you: dodge and block stop attacks (not spells, burns or poison), and spell
suppression halves a spell. Then armour and the physical reduction work on a physical hit and your resistance on the other
kinds. Last Breath works after everything else.

**New and changed modifiers.** New: Armour, Spell Suppression, Fire, Cold, Lightning and Chaos Resistance, All Elemental
Resistances. The nine old elemental absorbs no longer drop; the physical one stays (armour and shields only). Dodge, block,
penetration and energy shield recharge have new numbers, and none of these has a cap of its own now: dodge and block count
up to 75, spell suppression up to 100. Penetration takes points off the monster's armour or off its resistance, even below
zero.

**Your old items.** When you next touch an item that had an absorb, it becomes the resistance of its group at the same tier.
Two absorbs of one group become one, the higher tier. Uniques, set pieces and store items do not change.

**Rifts.** A new modifier, Frayed Wards, lowers the maximum resistance of the players inside.

**Where to look.** Character Info and Inspect Player show every resistance with its sources, the penalty and the result,
and your armour, dodge, block and spell suppression. Hold Alt on an item for what each line does.
