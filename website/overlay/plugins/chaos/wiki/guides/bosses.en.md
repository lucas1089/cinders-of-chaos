# Raids, bosses and events

Group content on a schedule: world bosses, the weekly raid, the Ascended challenges and the calendar events.

## World bosses

::: if worldboss.on
There are {{worldboss.count}} [world bosses](wiki:boss:world), one every {{worldboss.interval}} hours: {{worldboss.times}} (server time). Portals open next to the temples. Level {{worldboss.minLevel}} or more, up to {{worldboss.maxPlayers}} players. Your score adds up damage, healing on others and damage taken. A good score pays gold, orbs and a chance at boss gear.
::: end

## The weekly raid

::: if raid.on
[{{raid.name}}](wiki:boss:raid) is a raid for {{raid.minPlayers}} to {{raid.maxPlayers}} players of level {{raid.minLevel}} or more, with {{raid.bosses}} bosses. Loot is personal, once a week per boss. The week resets on {{raid.reset}} (server time). A lethal hit does not really kill: you go back to the entry hall.
::: end

## Ascended Omens and the Cinderheart

::: if ascended.on
The top challenge. Shards from the Omen guardians make sigils that open the [Ascended](wiki:boss:ascended) arenas, for up to {{ascended.maxPlayers}} players. One relic of each Omen opens the Cinderheart's arena.
::: end

## The weekly guild boss

::: if guildboss.on
Members feed the Summoning Stone in the guild hall and summon the [guild boss](wiki:boss:guild) into its own arena. Level {{guildboss.minLevel}} or more.
::: end

## Events

- The [calendar](wiki:event:calendar) has {{events.count}} recurring bonus days: experience, loot, rare monsters and tower points.
- [Treasure goblins](wiki:event:goblin) appear anywhere and run off with loot. Catch them before they escape.
- Your **Nemesis**: a monster that kills you (level 50 or more) may come back for you, by name. It returns while you hunt its kind and grows each time it kills you again. Slay it for a trophy with its name and the title Avenger of Self.

::: if invasion.on
- [Invasions](wiki:event:invasion): waves of invaders at a town or hunting ground, then their boss. Level {{invasion.minLevel}} or more for the rewards.
::: end
::: if siege.on
- [Guild Siege](wiki:event:siege): every {{siege.when}} (server time), guilds fight for the Chaos Obelisk. Nobody really dies inside.
::: end
