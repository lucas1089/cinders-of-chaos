# Social: guilds, parties and mentors

Playing together pays more. Guilds, parties, mentors and factions give you reasons to.

## Guilds

- Guilds are founded on the website. In game, open Social > Guild.
- A guild earns experience from what its members already do and levels from 1 to {{guild.maxLevel}}, unlocking small perks.
- At guild level {{guild.hallLevel}} the guild can buy a hall of its own.

::: if guildwar.on
- Guild wars are declared in game, in Social > Guild Wars, with a kill limit and a duration. Only victims of level {{guildwar.minVictim}} or more count. The website shows the [wars](page:guildwars).
::: end

## Parties

Social > Party Finder lists groups looking for players for rifts, dungeons, bosses, the raid and more. The leader posts, you apply with a role: tank, healer or damage.

## Mentors

::: if mentor.on
Veterans can guide new characters in Social > Mentors. The apprentice starts at level {{mentor.apprenticeMax}} or below. Hunting near the mentor, they get {{mentor.exp}}% more experience and take {{mentor.damage}}% less damage from monsters. At level {{mentor.graduation}} they graduate and both get a reward. The website lists the [mentors](page:mentors).
::: end

## Factions

::: if factions.on
There are {{factions.count}} factions: {{factions.names}}. Each has an NPC who sells gear, orbs, recipes and cosmetics. Reputation is per character and grows with hunting, contracts and events. Mind the rivalries: reputation with one faction lowers your standing with its rival a little.
::: end

## Achievements

Character > Achievements shows long-term goals across every system, with titles and rewards.
