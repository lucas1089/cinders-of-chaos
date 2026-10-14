# Social: guildas, grupos e mentores

Jogar junto rende mais. Guildas, grupos, mentores e facções dão motivos para isso.

## Guildas

- Guildas são criadas no site. No jogo, abra Social > Guild.
- A guilda ganha experiência com o que os membros já fazem e sobe do nível 1 ao {{guild.maxLevel}}, liberando bônus pequenos.
- No nível {{guild.hallLevel}} a guilda pode comprar um salão próprio.

::: if guildwar.on
- Guerras de guilda são declaradas no jogo, em Social > Guild Wars, com limite de abates e duração. Só contam vítimas do nível {{guildwar.minVictim}} ou mais. O site mostra as [guerras](page:guildwars).
::: end

## Grupos

O Social > Party Finder lista grupos procurando gente para rifts, masmorras, chefes, raid e mais. O líder posta, você se candidata com um papel: tanque, cura ou dano.

## Mentores

::: if mentor.on
Veteranos podem guiar personagens novos em Social > Mentors. O aprendiz começa até o nível {{mentor.apprenticeMax}}. Caçando perto do mentor, ele ganha {{mentor.exp}}% a mais de experiência e toma {{mentor.damage}}% menos dano de monstros. No nível {{mentor.graduation}} ele se forma e os dois ganham uma recompensa. O site lista os [mentores](page:mentors).
::: end

## Facções

::: if factions.on
Há {{factions.count}} facções: {{factions.names}}. Cada uma tem um NPC que vende equipamento, orbes, receitas e cosméticos. A reputação é por personagem e sobe com caça, contratos e eventos. Cuidado com as rivalidades: ganhar reputação com uma facção baixa um pouco a da rival.
::: end

## Conquistas

Character > Achievements mostra metas de longo prazo em todos os sistemas, com títulos e recompensas.
