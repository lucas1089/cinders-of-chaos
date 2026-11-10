# Tougher monsters, new monster modifiers
Date: 2026-11-20
Kind: news

<!-- DRAFT. Not shown to players. Why here: the server shows a notes file as soon as it is installed, whatever its
date, so this file stays out of server/data/patchnotes until the change goes live.
To publish: copy it to server/data/patchnotes/YYYY-MM-DD.md (and the .pt-br.md twin), remove every comment, run
install_all.py. Test: cd server && luajit tests/patchnotes_test.lua.
Facts used: server/README.md "Monster defence (O462)". Not run on a live server: confirm the numbers after a test hunt. -->

Monsters now defend themselves, and the strong ones are stronger. Elite monsters, bosses and rift guardians take longer to
kill. Ordinary hunts feel about the same.

## Changed

- **Armour depends on the size of your hit.** A monster's armour takes a share of every physical hit: small hits lose a lot
  of it, big hits lose little. Weapon hits and physical spells are reduced. Fire, ice, energy and the other elements,
  damage over time and fields ignore armour. A boss has the most armour, a rare or legendary monster less, an ordinary
  monster the least.
- **Resistances have a ceiling.** An ordinary monster resists an element by 40% at most, a boss by 75% at most. No ordinary
  monster is immune to an element any more. Rare and legendary monsters resist 15% more. Weaknesses stay.
- **Many high level monsters resisted everything by 30%.** They now resist only three of the seven types, and the three
  differ from monster to monster. Look at the monster before you pick your element.
- **Magic, rare and legendary monsters have more health and hit a little differently.** Health: magic x2.48, rare x4.90,
  legendary x7.98. Damage: magic +30%, rare +50%, legendary +70% (legendary was +100%).
- **Damage multipliers of monsters and rifts now apply first.** A stronger monster's hit and the damage bonuses of a rift
  reach you before your own protection takes its share, so protection works on the real hit.

## New

- **Seven monster modifiers** for magic, rare, legendary and boss monsters. Each has a chip on the monster bar.
  - **Emberforged, Frostforged, Stormforged:** half of each physical hit is added as fire, ice or energy damage. Your
    resistance and protection for that element reduce the added part.
  - **Plated:** takes half the physical damage.
  - **Resistant:** resists one element by 75%. The element is picked when the monster appears.
  - **Ruthless:** one hit in five is a critical hit and deals 150%.
  - **Bulwark:** half of the weapon hits against it deal nothing. Spells and damage over time are never blocked.

## Known

- Rift guardians and bosses take about twice as long to kill with physical classes. We will watch the numbers and adjust.
