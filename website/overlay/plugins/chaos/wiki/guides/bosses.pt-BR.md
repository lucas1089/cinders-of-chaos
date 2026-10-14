# Raids, chefes e eventos

Conteúdo de grupo com horário marcado: chefes do mundo, a raid semanal, os desafios Ascended e os eventos do calendário.

## Chefes do mundo

::: if worldboss.on
São {{worldboss.count}} [chefes do mundo](wiki:boss:world), um a cada {{worldboss.interval}} horas: {{worldboss.times}} (horário do servidor). Portais abrem ao lado dos templos. Nível {{worldboss.minLevel}} ou mais, até {{worldboss.maxPlayers}} jogadores. Sua pontuação soma dano, cura nos outros e dano aguentado. Quem pontua bem ganha ouro, orbes e uma chance de item de chefe.
::: end

## A raid semanal

::: if raid.on
[{{raid.name}}](wiki:boss:raid) é uma raid para {{raid.minPlayers}} a {{raid.maxPlayers}} jogadores do nível {{raid.minLevel}} ou mais, com {{raid.bosses}} chefes. O loot é pessoal, uma vez por semana por chefe. Reinício semanal: {{raid.resetPt}}, horário do servidor. Um golpe fatal não mata de verdade: você volta para a entrada.
::: end

## Ascended Omens e o Cinderheart

::: if ascended.on
O desafio mais alto. Fragmentos dos guardiões Omen formam sigilos que abrem as arenas [Ascended](wiki:boss:ascended), para até {{ascended.maxPlayers}} jogadores. Uma relíquia de cada Omen abre a arena do Cinderheart.
::: end

## O chefe semanal da guilda

::: if guildboss.on
Membros alimentam a Summoning Stone no salão da guilda e invocam o [chefe da guilda](wiki:boss:guild) numa arena própria. Nível {{guildboss.minLevel}} ou mais.
::: end

## Eventos

- O [calendário](wiki:event:calendar) tem {{events.count}} dias de bônus fixos: experiência, loot, monstros raros e pontos da torre.
- [Treasure goblins](wiki:event:goblin) aparecem em qualquer lugar e fogem com o loot. Pegue antes que escapem.

::: if invasion.on
- [Invasões](wiki:event:invasion): ondas de invasores numa cidade ou área de caça, e depois o chefe deles. Nível {{invasion.minLevel}} ou mais para as recompensas.
::: end
::: if siege.on
- [Guild Siege](wiki:event:siege): toda semana, {{siege.whenPt}} no horário do servidor, guildas lutam pelo Chaos Obelisk. Ninguém morre de verdade lá dentro.
::: end
