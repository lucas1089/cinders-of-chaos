# Playtest: new player, levels 8-50 (O379)

One session of about 1 to 1.5 hours. Goal: find where a new player gets stuck, bored or lost.
Written in pt-BR for the owner. Everything below was built in O368-O377 and never ran in a client.

## Antes de começar

- Servidor de teste com o PR 245 instalado: `install_all.py` inteiro, depois reiniciar.
  - Pelo app de admin: Painel > Atualizar servidor.
  - Pela shell, se o app falhar: `sudo chaos-ctl.sh update-apply`.
- Cliente montado com o mesmo commit.
- Crie um personagem novo. Não use GM. Não leia o código antes.
- Ligue a gravação de performance: System > Developer > Performance > "Gravar 60 s".
  Repita perto do fim, numa hunt cheia.
- Tenha um bloco de notas aberto. Anote a hora de cada item.

## O que anotar sempre

- Cada vez que você não soube o que fazer: onde estava e quanto tempo levou.
- Cada janela que abriu sozinha e atrapalhou.
- Cada texto em inglês no cliente em pt-BR.
- Cada botão "?" que cobre outro botão.
- Cada erro vermelho no terminal do cliente (Ctrl+T).

## Roteiro

| # | Passo | O que conferir |
|---|---|---|
| 1 | Login no nível 8 em Cinderhold | Caminho de boas-vindas aparece no rastreador: "Welcome Path 1/7". Mensagem e buff "Newcomer" (+50% XP). |
| 2 | Lançar uma magia (ou Auto setup) | Passo 1 conclui, 300 gold. Clicar na linha abre o Helper. |
| 3 | Matar 20 monstros | Passo 2 conclui. Poções da sua classe chegam. Minutos por nível perto de 0,4 a 0,6. |
| 4 | Equipar um item que não é do kit | Passo 3 conclui. Segure Alt em cima do item: cada linha explicada. Solte: tooltip curto com a dica do Alt. |
| 5 | Abrir o top menu | Só os sistemas do nível aparecem. O próximo bloqueado fica cinza com "Nível N". |
| 6 | Alt+F, buscar "como subir de nivel" e "gems" | Respostas certas. Clicar abre o card ou o Codex. |
| 7 | Morrer de propósito numa hunt alta | Janela de morte com "O que fazer": dica de nível e de poção. |
| 8 | Nível 10: Season Pass abre | Card "Como funciona" abre sozinho na primeira vez. A caixa desliga isso. |
| 9 | Nível 12: primeiro ponto passivo | Passo 4 conclui. Árvore: tooltip curto, com Alt a explicação. Oferta de mentor aparece, uma vez só. |
| 10 | Pegar e terminar um Bounty | Passo 5 conclui: 1.000 gold e 2 orbs. |
| 11 | Nível 15: Loadouts e Charms abrem | Janela "Novo" aparece. Cards certos. |
| 12 | Nível 20: bancada de crafting | Botão Guia: aba Orbs e aba Gemas fazem sentido? Usar um orb: passo 6 conclui. |
| 13 | Nível 20: pesquisa | Janela com 3 perguntas. Responda de verdade. Pular também deve funcionar em outra conta. |
| 14 | Abrir Próximos objetivos | Passo 7 conclui. Caminho termina com 4.600 gold no total. |
| 15 | Nível 30 e 40 | Transmog e Hideout no 30; Gambler e Facções no 40. NPCs dizem "Volte no nível N" antes. |
| 16 | Nível 50 | Pesquisa 2. Proteção PvP termina. Arena abre. |

## Tempos esperados (modelo, com bônus de novato)

- Nível 8 a 20: cerca de 6 minutos.
- Nível 20 a 50: cerca de 20 minutos.
- Muito mais rápido ou muito mais lento que isso: anote. O modelo pode estar errado.

## Depois

- Mande para o Claude: suas notas, os dois arquivos `chaos-perf-*.txt` (ou "Copiar resumo") e prints do que estranhou.
- Pelo app de admin: Painel > Novos jogadores > Pesquisa. Sua resposta deve aparecer lá.
- Pelo app de admin: Painel > Novos jogadores > Funil. Seu personagem conta no funil (contas abaixo de 5 aparecem como "<5").
