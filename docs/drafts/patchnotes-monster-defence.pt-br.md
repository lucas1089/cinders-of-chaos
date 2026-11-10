# Monstros mais duros, novos modificadores
Date: 2026-11-20
Kind: news

<!-- RASCUNHO. Os jogadores não veem este arquivo. Por que está aqui: o servidor mostra uma nota assim que ela é
instalada, qualquer que seja a data, então este arquivo fica fora de server/data/patchnotes até a mudança entrar no ar.
Para publicar: copie para server/data/patchnotes/AAAA-MM-DD.pt-br.md (com o par em inglês), tire todos os comentários e
rode o install_all.py. As confirmações antes de publicar estão no arquivo em inglês (patchnotes-monster-defence.md). -->

Os monstros agora se defendem, e os fortes ficaram mais fortes. Monstros de elite, chefes e guardiões de fenda demoram mais
para morrer. As caçadas comuns continuam parecidas.

## Mudou

- **A armadura depende do tamanho do seu golpe.** A armadura do monstro tira uma parte de cada golpe físico: golpes pequenos
  perdem muito, golpes grandes perdem pouco. Golpes de arma e magias físicas são reduzidos. Fogo, gelo, energia e os outros
  elementos, dano ao longo do tempo e campos ignoram a armadura. O chefe tem mais armadura, o monstro raro ou lendário
  menos, o monstro comum o mínimo.
- **As resistências têm um teto.** Um monstro comum resiste a um elemento em no máximo 40%, um chefe em no máximo 75%.
  Nenhum monstro comum é imune a um elemento. Monstros raros e lendários resistem 15% a mais. As fraquezas continuam.
- **Muitos monstros de nível alto resistiam a tudo em 30%.** Agora resistem só a três dos sete tipos, e os três mudam de
  monstro para monstro. Olhe o monstro antes de escolher o seu elemento.
- **Monstros mágicos, raros e lendários têm mais vida e batem diferente.** Vida: mágico x2,48, raro x4,90, lendário x7,98.
  Dano: mágico +30%, raro +50%, lendário +70% (o lendário era +100%).
- **Os bônus de dano de monstros e de fendas agora valem primeiro.** O golpe de um monstro mais forte e os bônus de dano de
  uma fenda chegam até você antes da sua própria proteção, então a proteção age sobre o golpe de verdade.

## Novo

- **Sete modificadores de monstro** para monstros mágicos, raros, lendários e chefes. Cada um tem um ícone na barra do
  monstro.
  - **Emberforged, Frostforged, Stormforged:** metade de cada golpe físico é somada como dano de fogo, gelo ou energia. A sua
    resistência e proteção contra esse elemento reduzem a parte somada.
  - **Plated:** recebe metade do dano físico.
  - **Resistant:** resiste a um elemento em 75%. O elemento é sorteado quando o monstro aparece.
  - **Ruthless:** um golpe em cinco é crítico e causa 150%.
  - **Bulwark:** metade dos golpes de arma contra ele não causam dano. Magias e dano ao longo do tempo nunca são bloqueados.

## Conhecido

- Guardiões de fenda e chefes demoram cerca do dobro para morrer com classes físicas. Vamos acompanhar os números e ajustar.
