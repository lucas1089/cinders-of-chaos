# A defesa tem uma nova ordem: quatro resistências, armadura que depende do golpe
Date: 2026-11-21
Kind: news

<!-- RASCUNHO. Não aparece para os jogadores. Por que aqui: o servidor mostra um arquivo de notas assim que ele é instalado,
seja qual for a data, então este arquivo fica fora de server/data/patchnotes até a mudança entrar no ar.
Para publicar: copie para server/data/patchnotes/AAAA-MM-DD.pt-br.md (e o par em inglês), remova todo comentário, rode
install_all.py. Teste: cd server && luajit tests/patchnotes_test.lua.
Fatos usados: server/README.md "Player defence (O464)". Não rodou em servidor de verdade: confirme os números numa caçada de teste. -->

O jeito como o seu personagem se defende mudou. Leia isto antes de caçar.

**Quatro resistências.** Fire é fogo. Cold é gelo, água e afogamento. Lightning é energia, sagrado e arcano. Chaos é terra,
morte, drenagem de vida e drenagem de mana. Tudo o que dava resistência antes continua valendo, pelo valor inteiro:
equipamento, conjuntos, gemas e amuletos. A árvore passiva e o Paragon agora contam metade dos seus pontos para uma resistência, e no máximo 30 da árvore: o equipamento cobre o resto. Uma resistência para em 75. Dano físico não é uma
resistência: ele tem armadura.

**Uma penalidade por nível.** A partir do nível 250 toda resistência perde 30 pontos, a partir do nível 500 perde 60. Você é
avisado ao entrar e ao subir de nível de 240 a 249 e de 490 a 499, e recebe uma mensagem ao passar da marca. Uma resistência
pode ficar abaixo de zero: aí você sofre mais dano daquele tipo. Aumente suas resistências com equipamento e árvore antes
das marcas.

**A armadura depende do golpe.** A armadura tira uma parte grande de um golpe pequeno e uma parte pequena de um golpe grande.
Um personagem com um conjunto completo de peças de armadura sofre cerca de 85% menos de um golpe típico de monstro, e cerca
de metade de um golpe de chefe. A redução física do equipamento e da árvore soma com ela. Armadura e redução juntas nunca
tiram mais de 90%.

**A ordem de um golpe.** Primeiro ele pode errar você: esquiva e bloqueio param ataques (não feitiços, queimaduras ou
veneno), e a supressão de magia reduz um feitiço à metade. Depois a armadura e a redução física agem sobre um golpe físico e
a sua resistência sobre os outros tipos. Last Breath age depois de tudo.

**Modificadores novos e mudados.** Novos: Armour, Spell Suppression, Resistência a Fogo, Frio, Raio e Caos, Todas as
Resistências Elementais. As nove absorções elementais antigas não caem mais; a física continua (só em armaduras e escudos).
Esquiva, bloqueio, penetração e recarga do escudo de energia têm números novos, e nenhum deles tem limite próprio agora:
esquiva e bloqueio contam até 75, supressão de magia até 100. A penetração tira pontos da armadura do monstro ou da
resistência dele, até abaixo de zero.

**Seus itens antigos.** Quando você tocar de novo num item que tinha uma absorção, ele vira a resistência do grupo dela, no
mesmo tier. Duas absorções do mesmo grupo viram uma, a de tier maior. Únicos, peças de conjunto e itens da loja não mudam.

**Fendas.** Um modificador novo, Frayed Wards, reduz a resistência máxima dos jogadores lá dentro.

**Onde ver.** Character Info e Inspect Player mostram cada resistência com as fontes, a penalidade e o resultado, e a sua
armadura, esquiva, bloqueio e supressão de magia. Segure Alt sobre um item para ver o que cada linha faz.
