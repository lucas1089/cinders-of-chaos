# Guia de leveling: do nível 1 ao 1000

Um caminho passo a passo para quem está começando: onde caçar em cada faixa de nível, quais sistemas se abrem e como chegar a cada um no jogo. Os nomes dos menus seguem a barra do topo do cliente (por exemplo **Adventure > Next Goals**). Quando você não souber o que fazer, abra o **Next Goals** (Próximos objetivos): ele mostra os objetivos da sua faixa, e um clique marca o lugar no seu mapa.

=> @create | Crie o personagem | No site ou na tela de seleção de personagens do cliente.
=> @temple | Comece no templo | Você nasce no nível 8 no templo de Cinderhold, com o kit da sua classe.
=> @level | Siga os objetivos | Adventure > Next Goals: {{goals.count}} objetivos em {{goals.bands}} faixas.
=> @ladder | Suba de faixa | Este guia: o que fazer do nível 8 ao 1000, uma faixa por vez.

> [tip] Leia também [Primeiros passos](wiki:guide:start) e [Progressão](wiki:guide:progression). Este guia junta os dois numa linha do tempo.

## Criação do personagem e classes

- Crie o personagem no site ou no cliente. Você começa no **nível 8**, já no templo de Cinderhold.
- As classes livres são {{class.openNamesPt}}. {{class.lockedNamesPt}} se abrem para a conta inteira quando um personagem dela chega ao nível {{class.unlockLevel}}, de graça.
- Cada classe tem duas ascensões, escolhidas no nível {{class.ascensionLevel}}. Veja todas no guia de [Classes](wiki:guide:classes).
- O kit inicial traz equipamento e arma da classe, duas poções Everfull (vida e mana, nunca acabam), comida, corda, pá, um Temple Teleport Scroll com 3 usos e 500 de ouro.
- Presentes de marco chegam nos níveis {{newplayer.giftLevelsPt}}: poções do seu papel, Orbs of Upheaval e, mais tarde, Orbs of Fate, Grafting e Stamina Extensions.

> [note] Não existe mais ilha de tutorial: você entra direto na cidade.

## Controles e janelas que você vai usar sempre

- **System > Helper**: na primeira entrada o botão **Auto setup** pisca. Um clique configura curas, poções, comida, haste e a rotação de ataque com alvo automático.
- **Character > Spellbook** (Alt+S): suas magias. **Character > Passive Tree** (Árvore passiva, Alt+P): seus pontos passivos.
- **Hunt > Hunt Tracker** (Alt+H): experiência e saque por hora. O botão **Restock** recompra os suprimentos gastos, com uma taxa de 10%.
- **Hunt > Bestiary** (Bestiário, Alt+B) e **Hunt > Kill Tasks**: conhecimento dos monstros e tarefas de abate.
- **Adventure > Bounty Board**: contratos diários. **Adventure > Daily Reward** (Recompensa diária): uma série de {{daily.days}} dias para a conta.
- **Economy > Crafting Bench** (Alt+C), **Economy > Item Finder** e **Economy > Codex** (Alt+K): criação, onde cada item cai e todas as regras do jogo.
- **Character > Town Portal**: um portal para a cidade (3 s para abrir, 60 s de espera, dura 5 minutos e o grupo pode usar).

> [tip] Morrer não tira itens. A perda de experiência não existe até o nível 30, é metade no nível 100 e cheia a partir do 250. A primeira morte de cada dia perde só metade disso.

## Nível 8-50: primeiros passos

=> @temple | Salão de teleportes | Os dois grandes teleportes 5 passos ao norte do templo levam ao salão de caçadas.
=> @level | Placas de nível | Cada teleporte tem uma placa: "Nome, levels X-Y". O andar 7 é dos níveis 1-500.
=> @reward | Primeiro contrato | Adventure > Bounty Board: aceite um contrato já no nível 8.
=> @level | Primeiro ponto | Seu primeiro ponto passivo chega no nível 12.

- **Onde caçar.** Na primeira hora, dicas marcam no minimapa as 3 caçadas mais perto do seu nível. Bons começos no salão: Rat (1-6), Orc (5-15), Minotaur (5-15), Cave Rat (5-20), Dwarf Guard (10-25), Haunted Treeling (10-30), Stalker (15-30), Saltkin Mantassin (25-55), Frost Dragon Hatchling (25-75) e Fire Elemental (20-80).
- **Árvore passiva.** Você ganha 1 ponto a cada {{tree.levelsPerPoint}} níveis acima do nível {{tree.startLevel}}. Gaste em Character > Passive Tree. Veja o guia da [Árvore passiva](wiki:guide:tree).
- **Monstros com nível.** Monstros mágicos (azuis), raros (amarelos) e lendários (laranja) soltam equipamento melhor. Use o que for melhor que o seu.
- **Combate em bando.** Abates seguidos, cada um até 3 s depois do anterior, dão bônus de experiência: +10% com 4 abates, +20% com 6, +30% com 8 e +40% com 9.
- **Bounty Board.** Até {{bounty.maxActive}} contratos ao mesmo tempo; o quadro troca todo dia às 06:00. Com {{bounty.weeklyNeed}} contratos numa semana você ganha o baú semanal.
- **Venda e compre.** O Loot Buyer fica na galeria do templo (ala oeste, na parede sul, ao lado da entrada). O **Economy > Market** (Mercado, Alt+E) abre no nível {{market.minLevel}}.
- **Nível 20:** primeira tarefa de abate, primeiro orbe de criação na Crafting Bench, 50 monstros com nível.
::: if invasion.on
- **Nível {{invasion.minLevel}}:** [invasões de cidade](wiki:event:invasion). Veja Adventure > Events.
::: end
::: if mentor.on
- **Mentor.** Até o nível {{mentor.apprenticeMax}} você pode pedir um mentor em Social > Mentors (Mentores): +{{mentor.exp}}% de experiência caçando perto dele, até se formar no nível {{mentor.graduation}}.
::: end

## Nível 50-150: ascensão e as primeiras fendas

- **Onde caçar.** Wyrm (50-80), Rustheap Golem (60-80), Serpent Spawn (35-105), Dawnfire Asura (20-105), Hellspawn (80-135), Blightwalker (95-150), Usurper Archer (110-140) e Demon Outcast (120-140).
- **Arena.** No nível {{arena.minLevel}}, Adventure > Arena. Um dos objetivos da faixa é vencer uma partida.
- **Bestiário.** Cada estágio (Discovered, Studied, Mastered, Completed) dá experiência bônus contra aquela criatura. Junte 25 criaturas no Bestiário.
- **Ascensão no nível {{class.ascensionLevel}}.** Fale com o Ascendant Oracle no Salão de Serviços (o portal no fim sul do templo). Junte a Prova de Força ({{ascension.proofPoints}} pontos: monstro raro vale 1, lendário vale 3) e vença uma prova de {{ascension.trialTime}}. Se perder, tente de novo depois de {{ascension.retry}}.
- **Prova de Vocação.** No Keeper of Trials (Salão de Serviços) ou no botão **Trials** da janela da Árvore passiva. Normal no nível {{trial.normalLevel}}. Cada vitória abre um par especial de nós na árvore.
- **Fendas.** O tier 1 abre no nível {{rift.level1}}. Use a chave numa zona de proteção; até {{rift.maxPlayers}} jogadores. A partir do nível 100, contratos do Bounty Board podem dar uma chave de tier 1. Veja o guia de [Fendas](wiki:guide:rifts).
::: if descent.on
- **{{descent.name}}.** Nível {{descent.minLevel}}, Adventure > Ember Descent. Veja a [página dela](wiki:dungeon:descent).
::: end
- **Masmorras e torre.** Adventure > Dungeons (Alt+J), em {{dungeon.difficulties}} dificuldades: mate 85% dos monstros para abrir o chefe. A [Infinity Tower](wiki:dungeon:tower) fica em Adventure > Infinity Tower.
- **Facções.** Adventure > Factions (Facções). Chegue a Trusted no nível 120 numa delas.

## Nível 150-300: veterano

- **Onde caçar.** Fleshcarver (145-155), Blackblade (150-300), Emerald Mage (180-270), Bonechoir Catacomb (200-290), Sulphur Gallery (215-299) e deathrattle (230-300).
- **Fendas.** Tier 2 no nível {{rift.level2}}, tier 3 no {{rift.level3}}. Leve um grupo: mais jogadores, mais recompensa.
::: if pocket.on
- **Chefes de bolso.** Adventure > Boss Spawns, botão **Pocket**: uma cópia privada de um chefe, {{pocket.charges}} cargas por dia. Chefes de raide a partir do nível {{pocket.raidLevel}}, chefes de ilha a partir do {{pocket.islandLevel}}. Vessa Hollowmark, na galeria do templo, cuida deles.
::: end
- **Classes novas.** No nível {{class.unlockLevel}} {{class.lockedNamesPt}} se abrem para a conta.
- **Charms.** Character > Charms: novas casas abrem nos níveis 200, 400, 600 e 800.
- **Objetivos do nível 200:** fenda tier 4, um item único, 10 andares da Infinity Tower, 25 contratos.
- **Prova Cruel** no nível {{trial.cruelLevel}}, no mesmo Keeper of Trials.

## Nível 300-500: chefes do mundo

- **Onde caçar.** Aeliana (280-310), grothar (300-335), fangclaw (305-390), Hollow Crypt (300-400) e, perto de 500, Widowmere (480-640).
::: if worldboss.on
- **Chefes do mundo.** Nível {{worldboss.minLevel}}. Um por vez às {{worldboss.times}} (horário do servidor); os portais abrem ao lado dos templos. Veja [Chefes](wiki:guide:bosses).
::: end
- **Fendas.** Tier 4 no nível {{rift.level4}}, tier 5 no {{rift.level5}}. A partir do tier {{rift.omenMinTier}} aparecem Omens: {{rift.omenKeyCost}} fragmentos fazem uma chave de Omen.
- **Prova Impiedosa** no nível {{trial.mercilessLevel}}. Nesse nível também vem a primeira Orb of Grafting dos objetivos.
- **Facção:** chegue a Honored. Os intendentes vendem equipamento fixo em Honored e Revered.
- **Árvore:** no nível 300 você já tem {{tree.points300}} pontos. A primeira morte de cada grande chefe dá +1 ponto passivo.

## Nível 500-750: endurecido

- **Andar 6 do salão (níveis 500-1000).** Gloomtooth Caverns (500-615), Wyrmspine Hollows (500-640), Brackwater Sloughs (515-630), Pyrarch Crucible (520-690), Sablemourn Ossuary (530-645), Thornmantle Glade (545-660), Embergut Rift (560-675), Frostvein Reach (575-690), Graveknell Catacombs (590-705), Umbral Sink (605-720), Cinderscour Barrens (620-735), Grimlock Vaults (635-750) e Blackmarble Halls (650-765).
- **Fendas.** Tier 6 no nível {{rift.level6}}, tier 7 no {{rift.level7}}, tier 8 no {{rift.level8}}.
- **Objetivos do nível 500:** 5 chefes do mundo, um item com 5 modificadores, 25 andares da Infinity Tower, 10 criaturas completas no Bestiário.
- **Facção:** Revered no nível 600.
- **Equipamento.** Rerrole e melhore na Crafting Bench (Alt+C). Desmonte o que sobrar em Economy > Salvage. Veja [Itens](wiki:guide:items) e [Economia](wiki:guide:economy).

## Nível 750-1000: rumo ao 1000

- **Onde caçar.** Hexwood Thicket (720-840), Scorchpit Delve (740-855), Bonewright Galleries (770-885), Corsairs' Reach (780-900), Sunderstone Wastes (800-915), Obsidian Colonnade (830-945), Sorrowfen Marsh (875-990), Mirefang Basin (880-999), Pyreglass Chasm (920-1035) e Lanternless Catacombs (950-1050).
- **Fendas.** Tier 9 no nível {{rift.level9}}, tier 10 no {{rift.level10}}. O máximo é o tier {{rift.maxTier}}.
::: if raid.on
- **Raide.** {{raid.name}} no nível {{raid.minLevel}}, para {{raid.minPlayers}} a {{raid.maxPlayers}} jogadores, em Adventure > Raid: Ashen Sepulchre.
::: end
- **Objetivos do nível 800:** um chefe de raide, um Omen, o Hollow Vault, 50 chefes de bolso. No 900: um Ascended Omen, a raide completa, fenda tier 10.
- **Nível {{paragon.startLevel}}.** Começa o Paragon, na janela da Árvore passiva: 1 ponto por nível em atributos pequenos. Você terá {{tree.points1000}} pontos passivos.

## Para qualquer faixa

- **Grupo.** O líder liga a experiência compartilhada no escudo do grupo. Ela só vale se ninguém estiver abaixo de 2/3 do nível mais alto, todos a até 30 passos e todos atacaram ou curaram há pouco.
- **Descanso.** Offline, você junta experiência descansada: +100% enquanto durar, 2,5 minutos por hora offline, até 180 minutos. Quem volta depois de 14 dias ganha 7 dias de +50%.
- **Stamina.** Com stamina baixa o saque cai pela metade.
- **Cartas.** Decks caem de monstros e de recompensas de tarefa. Carregue o deck e use uma carta dentro dele para ligar ou desligar. Veja em Character > Character Info > Card Deck.

## Glossário

- **Faixa:** o intervalo de níveis de uma caçada ou de um grupo de objetivos.
- **Monstro mágico, raro, lendário:** monstros com nível, em azul, amarelo e laranja. Soltam equipamento melhor.
- **Bounty:** contrato diário do Bounty Board.
- **Fenda (rift):** área aleatória aberta com uma chave de tier.
- **Omen:** fenda especial a partir do tier {{rift.omenMinTier}}.
- **Ascensão:** a especialização da classe no nível {{class.ascensionLevel}}.
- **Paragon:** pontos extras a partir do nível {{paragon.startLevel}}.
- **Zona de proteção:** área sem combate, como o templo.
- **Bestiário:** o registro de criaturas; cada estágio dá experiência bônus.
