# Modificadores de equipamento, refeitos
Date: 2026-11-20
Kind: news

<!-- RASCUNHO. Os jogadores não veem este arquivo. Por que está aqui: o servidor mostra uma nota assim que ela é instalada,
qualquer que seja a data, então este arquivo fica fora de server/data/patchnotes até a mudança entrar no ar (O461, etapa 1).
Para publicar: copie para server/data/patchnotes/AAAA-MM-DD.pt-br.md (com o par em inglês), ajuste a data, tire todos os
comentários e rode o install_all.py. As observações estão no arquivo em inglês (patchnotes-item-modifiers.md). -->

A maioria dos modificadores do seu equipamento mudou: os números, quais peças os rolam e alguns modificadores novos. Os itens
que você já tem são atualizados na primeira vez que o jogo os lê. Nada se perde.

Achou um bug? Use System > Report a Bug no jogo, ou conte para a gente no Discord. Toda denúncia é lida.

## Novo

- **Modificadores novos.** Maximum Life, Maximum Mana, Mana Regeneration, Strength, Dexterity e Intelligence. Varinhas e
  cajados podem rolar Spell Damage. Espadas, machados, clavas e outras armas que acertam com um valor de ataque podem rolar
  Weapon Damage.
- **Life Leech e Mana Leech.** Eles devolvem uma parte do dano que você causa, em todo golpe, sem chance para rolar. As armas
  têm uma versão própria, mais forte. Eles nunca devolvem mais que um quinto do seu máximo por segundo, e o dano ao longo do
  tempo não conta.

## Mudanças

- **Tiers melhores.** Todo tier que o seu item level permite pode rolar, e cada um é tão provável quanto qualquer outro.
  Antes, só os cinco melhores podiam. O tier mais alto agora vem do item level 130, então chefes de nível 1000 ou mais
  podem derrubá-lo.
- **Faixas limpas.** Um tier mais alto nunca rola menos que o tier abaixo dele.
- **Golpe crítico virou dois modificadores.** Critical Strike Chance e Critical Strike Damage rolam sozinhos. Eles podem
  estar em armas, aljavas, amuletos, anéis e emblemas. Sua árvore passiva continua dando os dois.
- **Números maiores.** Velocidade de ataque, velocidade de movimento, as chances de ailments, vida e mana por morte e por
  golpe, dano ao longo do tempo, redução de recarga, rarity find e os elementos das flechas seguem escadas novas e mais
  altas. A Health Regeneration cresce com a sua vida. O Execute é 10% em todo tier e não acumula. A velocidade de ataque
  que vale enquanto usada (fora da arma) fica só nos emblemas.
- **Sem limite na maioria dos modificadores.** Os limites dos modificadores acima acabaram. O que o próprio jogo limita
  continua: velocidade de ataque, velocidade de movimento, o teto de absorção e coisas assim.
- **Onde eles rolam.** A experiência fica só em amuletos e anéis. Vida e mana por golpe ficam só em armas. A Health
  Regeneration fica em armaduras, calças e escudos. O rarity find fica em capacetes, amuletos, anéis e botas.
- **Qualidade.** Uma Whetstone não aumenta mais os seus modificadores. Ela aumenta o ataque, a defesa e a armadura que a
  raridade do item deu. Um item sem nenhum desses não aceita uma.
- **Gold Find, Item Find e Mana Cost Reduction, e seis skills de ofício** não rolam mais. Os itens que os têm ficam com eles.
  Fishing e Crafting continuam rolando.
- **Seus itens antigos.** Cada modificador mantém o tier e o lugar na faixa. Os antigos modificadores de golpe crítico e de
  leech viram os novos no mesmo tier. Itens únicos, peças de set e equipamentos comprados de vendedores não mudam.
