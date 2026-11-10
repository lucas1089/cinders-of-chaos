# Gear modifiers, rebuilt
Date: 2026-11-20
Kind: news

<!-- DRAFT. Not shown to players. Why here: the server shows a notes file as soon as it is installed, whatever its date, so
this file stays out of server/data/patchnotes until the change goes live (O461, stage 1).
To publish: copy it to server/data/patchnotes/YYYY-MM-DD.md (and the .pt-br.md twin), set the date, remove every comment, run
install_all.py. Test: cd server && luajit tests/patchnotes_test.lua.
Say nothing about the defence modifiers (absorbs, dodge, block, reflect, thorns, penetration, energy shield): they are
stage 2 and not changed yet. If the notes go out after stage 2, add its lines here first.
The numbers are in server/README.md "Equipment modifiers version 2"; the owner asked to see how everything ends up before
the next round, so say that the numbers can still move. -->

Most modifiers on your gear changed: the numbers, which pieces roll them, and a few new ones. Items you already have are
upgraded the first time the game reads them. Nothing is lost.

Found a bug? Use System > Report a Bug in the game, or tell us on Discord. Every report is read.

## New

- **New modifiers.** Maximum Life, Maximum Mana, Mana Regeneration, Strength, Dexterity and Intelligence. Wands and rods
  can roll Spell Damage. Swords, axes, clubs and other weapons that hit with an attack value can roll Weapon Damage.
- **Life Leech and Mana Leech.** They give back a share of the damage you deal, every hit, with no chance to roll.
  Weapons have their own stronger version. They never give back more than a fifth of your maximum a second, and damage
  over time does not count.

## Changes

- **Better tiers.** Every tier your item level allows can roll, and each is as likely as any other. Before, only the best
  five could. The top tier now comes from item level 130, so bosses of level 1000 and up can drop it.
- **Clean ranges.** A higher tier never rolls lower than the tier below it.
- **Critical hits are two modifiers.** Critical Strike Chance and Critical Strike Damage roll on their own. They can be on
  weapons, quivers, amulets, rings and badges. Your passive tree still gives both.
- **Bigger numbers.** Attack speed, movement speed, the ailment chances, life and mana on kill and on hit, damage over time,
  cooldown reduction, rarity find and the arrow elements follow new, higher ladders. Health Regeneration scales with your
  health. Execute is 10% at every tier and does not stack. Attack speed that works while worn (not on the weapon) is only on badges.
- **No more limits on most modifiers.** The caps on the modifiers above are gone. What the game itself limits stays:
  attack speed, movement speed, the absorb ceiling and the like.
- **Where they roll.** Experience is on amulets and rings only. Health and mana on hit are on weapons only. Health
  Regeneration is on armour, legs and shields. Rarity find is on helmets, amulets, rings and boots.
- **Quality.** A Whetstone no longer raises your modifiers. It raises the attack, defence and armour your item's rarity
  added. An item without any of those cannot take one.
- **Gold Find, Item Find and Mana Cost Reduction, and six crafting skills** no longer roll. Items that have them keep
  them. Fishing and Crafting still roll.
- **Your old items.** Each modifier keeps its tier and its place in the range. Old critical hit and leech modifiers turn into
  the new ones at the same tier. Unique items, set pieces and gear bought from vendors do not change.
