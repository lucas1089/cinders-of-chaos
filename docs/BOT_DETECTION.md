# Detecção de bots: plano e o que está no código (O722)

Plano do dono (2026-11-22: "instale o md e as ferramentas que ele recomendar"), adaptado ao nosso código. O servidor é o fork do TFS 1.4.2 (`server/src-patches`, até a 0093) e o client é o nosso (`client/base-patches`, até a 0207, e os módulos de `client/overlay`). Detalhes de código, números de custo e comandos: `server/README.md`, seção "Bot detection events and scores (O722)".

## Objetivo

Descobrir se há jogadores usando bots externos (programas que leem a memória do client ou simulam teclado e mouse) ou bots internos (módulos de bot dentro do client) no servidor.

O foco é **detectar e gerar relatórios para revisão humana**. Nenhuma heurística é prova sozinha; vale a combinação de vários sinais ao longo de horas. **Nada aqui bane, desconecta, move ou pune ninguém.** Todo sinal só vira um evento ou um número. A decisão é da staff.

## Por que a detecção fica no servidor

Todo bot, interno ou externo, manda as ações ao servidor pelos mesmos pacotes de um jogador normal. O servidor não sabe como a ação foi gerada, mas vê o padrão. As proteções do client ajudam e geram mais um sinal, mas quem controla a própria máquina sempre pode contorná-las. A camada principal é o comportamento.

## O que já existia (e continua)

| Peça | Onde | O que faz |
|---|---|---|
| Presença e score que decai | `antibot.lua`, `antibot_core.lua`, `antibot_config.lua`, client `game_antibot`, opcode 211 | ritmo de ações, reação instantânea, voltas andadas, loot; pede um teste de presença (quatro figuras). Nunca bane. |
| Revisão diária | `botreview.lua`, `botreview_core.lua`, `sql/chaos_bot.sql`, `/botreview`, página da staff no site | nota por personagem e dia, sinais de automação e de "ninguém no teclado", fila de revisão. |
| Guard do client | `clientguard.lua`, src-patch 0021, client base patch 0035, módulo `game_chaosguard` (opcode 190) | só aceita o client oficial; o módulo diz "olá" com o build e quantos módulos nossos estão carregados. |
| Ticket do launcher | client base patch 0198, `launcher/` | o jogo só abre pelo launcher (dissuasão, não segurança). |
| Bots de teste | `testers.lua`, `tools/testers.py`, bots de jornada (`chaos-ctl.sh journey`); "Tester Xxx" | são bots por desenho: **ficam de fora de tudo** (ver abaixo). |
| Métricas | `metrics.lua`, `chaos-ctl.sh metrics` | contadores anônimos de progresso; não leem comportamento por personagem. |

O O722 **soma** a isto: guarda os eventos brutos por 7 dias para a staff e calcula as seis heurísticas do plano por hora, com os números que explicam cada nota. As três camadas (presença, revisão diária, O722) não leem as notas umas das outras; se duas apontam o mesmo personagem, é um indício a mais para a staff.

## Quem fica de fora

- **Testers** (bots de teste, bots de jornada): `Chaos.isTester(player)`. Não são coletados, não têm nota. Já eram excluídos de antibot e botreview.
- **Staff** (grupo 4 ou mais, `staffGroup` do config): não são coletados.
- Um personagem staff que joga como jogador comum também não é coletado: use outro personagem para testar.

## Parte 1: coleta (servidor)

Em memória por personagem (anéis com tamanho fixo), gravada em lote a cada 5 minutos e no logout. Arquivos: `botdet.lua` (motor), `botdet_core.lua` (lógica pura), `botdet_config.lua` (números), `sql/chaos_botdet.sql`.

| Evento | Dados | De onde vem |
|---|---|---|
| Posição | x, y, z e hora, uma amostra por segundo; só mudança de tile é guardada | `GlobalEvent` de 1 s (`getPosition` de cada personagem coletado) |
| Passo | passos de teclado, comandos de caminho (clique no mapa ou minimapa, com o número de passos) | **src-patch 0093**: `Game::playerMove`, `Game::playerAutoWalk`; Lua `player:getBotSignals()` |
| Magia | id, hora, % de vida e mana, se foi lançada no instante em que o cooldown acabou | `ChaosSpellEvents` `cast` e `cooldown` (src-patch 0008, já existe) |
| Cura e poção | % de vida antes da cura | evento `healthchange` com o próprio personagem como autor (feitiço, runa, poção) |
| Alvo | tempo entre a criatura entrar na tela e o primeiro ataque | **src-patch 0093**: `Player::onCreatureMove` (monstro que estava fora da vista e agora está dentro) e `Game::playerSetAttackedCreature` |
| Sessão | login, logout, pausas de 5 minutos ou mais sem nenhuma ação | login/logout e a última ação |
| Client | resumo dos módulos e o código de ferramenta conhecida | opcode **169**, módulo `game_chaosguard` (parte 4) |

Por que o src-patch 0093: o Lua do servidor não vê se o passo veio de uma tecla ou de um caminho do client, nem quando uma criatura entrou na vista. O patch só **conta** (um contador por jogador e um anel de 64 criaturas esperando); não muda nada em como o jogador anda ou ataca, e nada é salvo. Sem o patch, as heurísticas de reação e de caminho ficam sem dados e as outras quatro carregam a nota.

Tabelas (o servidor também as cria ao iniciar):

- `chaos_botdet_events`: `player_id`, `type` (`pos`, `walk`, `spell`, `heal`, `react`, `session`, `integrity`, `tool`), `data` (JSON com listas compactas), `created_at`. **7 dias**, limpeza diária em pedaços de 5000 linhas.
- `chaos_botdet_scores`: uma linha por personagem e hora, com as seis notas, o total, o bônus, a marca (`flagged`) e o texto com os números. **90 dias**, mesma limpeza.

Não usa storage de jogador (nenhum bloco de 7100000-7127999 foi tomado). Opcode 169: livre no servidor de referência, nos `ExtendedIds` do client base, em todo `ChaosOpcodes` e em todo módulo do client (`tests/botdet_test.lua` confere).

## Parte 2: as heurísticas

Rodam uma vez por hora por personagem (espalhadas pelo `guid`), sobre os anéis em memória (até 2 horas de posições, 160 intervalos por magia, 160 curas, 128 reações). Lógica pura em `botdet_core.lua`, números em `botdet_config.lua`. Cada uma dá 0 a 100 e diz os números que usou.

| # | Heurística | Peso | Como mede | Limites iniciais |
|---|---|---|---|---|
| 1 | Rota repetida | 30 | o trajeto vira células de 6 x 6 tiles; acha o menor período cujas células voltam (4 a 400 células, pelo menos 5 células diferentes); conta voltas, quanto das células volta e o desvio médio em sqm entre uma volta e a anterior | voltas: 0 em 3, 100 em 20; coincidência de 60% a 90%; desvio de 1 a 4 sqm; precisa de 30 min de caminhada |
| 2 | Regularidade | 25 | coeficiente de variação (desvio padrão / média) dos intervalos de cada magia e das curas que não são magia; magia lançada no instante exato do cooldown (tecla segurada) não conta | humano 0,25 ou mais (nota 0); bot 0,08 ou menos (nota 100); 30 amostras para pontuar, 100 para valer inteira |
| 3 | Reação ao alvo | 20 | mediana dos milissegundos entre a criatura entrar na tela e o primeiro ataque | 120 ms ou menos: 100; 260 ms ou mais: 0; 20 amostras, 50 para valer inteira |
| 4 | Limiar de cura | 15 | desvio padrão do % de vida em cada cura (cura com 96% ou mais é "completar", não conta) | 2 pontos ou menos: 100; 6 ou mais: 0; 30 amostras |
| 5 | Sessão sem pausa | 10 | maior sequência sem pausa de 5 minutos e horas com alguma ação nas últimas 24 | sequência de 5 h (0) a 8 h (100); dia de 14 h (0) a 20 h (100) |
| 6 | Precisão de caminho | bônus | parte dos passos que veio de comando de caminho longo (média de passos por comando) | só soma até 10 pontos; sozinha nunca marca |

**Nota total** = soma ponderada das heurísticas que **têm dados** dividida pelo peso delas, vezes `min(1, peso com dados / 60)` (se quase nada tem dados, a nota é cortada), mais o bônus, no máximo 100. **Marca para revisão acima de 70.**

Mudanças em relação ao plano, e por quê:

- A "rota repetida" não exige 20 voltas em 2 horas para pontuar: a nota sobe de 3 a 20 voltas **e** exige que as células voltem e o desvio seja pequeno. Assim um circuito longo (3 voltas por hora) pontua menos e um curto, mais.
- A regularidade ignora o cast "no instante do cooldown": o **helper permitido do nosso client** lança assim e isso não é bot. Um jogador com o helper, mesmo que regularidade e cura dessem 100, soma no máximo 40 dos 100 pontos (pesos 25 e 15), então nunca chega a 70 sozinho: o teste `tests/botdet_test.lua` mantém isso (nos traços de teste o helper fica perto de 11).
- A "precisão de caminho" aproxima o plano ("sempre o menor caminho, sem correções") por parcela de passos de caminho e comprimento médio, porque o servidor não recalcula o menor caminho por comando. Fica como bônus, como o plano pediu.

Os limites foram ajustados só com **traços sintéticos**: seis humanos (errando de caminho, ritmo solto, cura em qualquer %), quatro jogadores com o helper (todos abaixo de 55, nenhum marcado), quatro cavebots (todos acima de 90) e três bots com ruído (acima de 40, a maioria marcada). **Os limites não foram calibrados com jogadores reais.** Veja "Plano de teste" abaixo.

## Parte 3: relatório e ferramentas para a staff

- **`/botcheck <nome>`** (grupo 4+): nota total e por heurística das últimas horas, com os números ("coeficiente de variação 0,05 em 160 intervalos"). Personagem online: números ao vivo. Offline: a hora de maior nota nas últimas 24 h, com o mesmo texto. Também mostra os últimos sinais do client (`integrity`, `tool`) dos últimos 7 dias.
- **`/botcheck top [N]`**: as N maiores notas das últimas 24 h.
- **`/botcheck ask <nome>`** (opcional): manda ao jogador online o **teste de presença** que já existe (`ChaosAntibot.forceCheck`, modal com figuras). Só pergunta e observa; quem decide é a staff.
- **Lista diária**: às 4 h (configurável) o servidor escreve as 20 maiores notas em `data/logs/botdet_top.log` e faz a limpeza.
- **`chaos-ctl.sh botcheck-top [N]`**: lê `chaos_botdet_scores` (só leitura) e mostra as N maiores notas das últimas 24 h, uma linha por personagem. **Painel de admin (app Android, aba Comandos, card "Detecção de bots", botões Top 20 e Top 50; app desktop, Jogadores > Detecção de bots)** chamam o mesmo comando. No painel do jogo, "Segurança" tem "Bot detection: top of the day" e "Bot detection: character".
- **Nunca banir automaticamente.** Nenhum código de O722 chama kick, ban, mute, teleporte ou mudança de personagem.

## Parte 4: proteções no client

Camada secundária; pega ferramentas prontas e dá mais um sinal. Tudo entra como **evento**, não como desconexão.

1. **Integridade dos módulos** (`game_chaosguard/integrity.lua`, opcode 169). Seis segundos depois do login o client calcula, em fatias de 40 arquivos a cada 30 ms, o SHA-256 dos arquivos `.lua .otui .otmod .otml .json` de cada pasta de `/modules` e `/mods`, junta numa linha por arquivo (`caminho:hash`), ordena e tira o SHA-256 do texto: é o resumo do módulo. Manda `{módulo, resumo}` em mensagens de até 60 itens. O servidor compara com `server/data/lib/chaos_module_hashes.lua`, gerado **na release** por `client/tools/gen_module_hashes.py CLIENT_DIR` (mesma regra, teste com os dois lados). Módulo que a lista não conhece = **extra** (um bot interno é um); resumo diferente = **alterado**. Grava um evento `integrity`. A lista que vai no repositório está **vazia** (não compara nada) até a release gerar a real. O tamanho de 169 e os limites por mensagem estão no config (`integrity`).
2. **Ferramentas conhecidas** (client base patch **0207**, só Windows). A staff mantém, em `botdet_config.lua` `tools.list`, uma tabela `{code, hashes}`: o código curto (3 a 16 letras ou números) e o hash FNV-1a 64 (16 dígitos hexa) do nome do processo em minúsculas, do nome sem extensão ou de uma palavra do título de janela. O servidor manda ao client só `{code, hash}`. O client olha os nomes dos processos (sem caminho, sem id) e os títulos das janelas visíveis, compara os hashes e responde **só com os códigos** achados (`g_game.chaosScanTools`). Nunca sai nome de processo, título de janela nem a lista deles; nada é guardado, registrado ou enviado além dos códigos. Fora do Windows responde vazio. A lista vem **vazia** (a staff escolhe o que vigiar). O ramo do Windows do header (`chaostoolscan.h`) nunca foi compilado nem rodado aqui; a parte pura tem teste.
3. **Acesso externo à memória: NÃO feito, de propósito.** O plano mandava tratar como sinal fraco; dá falso positivo com antivírus, gravadores de tela e overlays do Discord, e exige abrir handles de outros processos. Fica para depois, se a staff quiser.
4. **Os sinais vão para a mesma base**: `integrity` e `tool` são eventos em `chaos_botdet_events` e aparecem no `/botcheck`; o aviso do Rumo (parte 5) muda só como o relatório o descreve.

## Parte 5: política (decisão do dono)

O **Rumo** é o cavebot externo do dono, com o módulo `game_rumolink`. Se ele for liberado a jogadores, a detecção vai marcar quem o usa. A decisão é do dono; o código traz um **interruptor** em `botdet_config.lua`, `rumo.policy`, agora **"forbidden" (proibido)**, decisão do dono em 2026-11-22: nenhum cavebot é liberado e qualquer ferramenta externa é proibida. Valores possíveis:

| Valor | Efeito no relatório (nunca uma ação) |
|---|---|
| `"flag"` (padrão) | o personagem é marcado como de sempre e o `/botcheck` diz que a ferramenta foi vista |
| `"allowed"` | `/botcheck` diz "allowed"; rota, regularidade e sessão ficam **fora** da nota total e o personagem não é marcado |
| `"forbidden"` | `/botcheck` diz "forbidden"; marcado como qualquer outro |
| `"areas"` | permitido dentro de `rumo.areas` (caixas `{x1, y1, x2, y2, z}` pela última posição), marcado fora delas |

O Rumo é visto pelo módulo `game_rumolink` na lista de módulos (`rumo.moduleNames`) ou pelo código `rumo` (`rumo.toolCode`) da varredura de ferramentas, se a staff o puser na lista.

### Perguntas em aberto (do dono)

1. ~~O Rumo será liberado, proibido ou liberado só em áreas?~~ Decidido (2026-11-22): proibido, como todo cavebot e toda ferramenta externa.
2. Se liberado em áreas, quais caixas do mapa? Mudar a lista exige recarregar o config (reiniciar o servidor).
3. Quais ferramentas entram na lista de `tools.list`? Quem calcula os hashes (`fnv1a64` em minúsculas, o vetor está em `client/tools/chaostoolscan_test.cpp`)?
4. Os limites (voltas, 0,25 / 0,08, 120 / 260 ms, 2 / 6 pontos de cura, 5 / 8 horas) valem para o jogo real? Só os dados de jogadores conhecidos e de uma conta com cavebot dizem. A reação depende do ping: uma conexão lenta empurra a mediana para cima (fica mais difícil marcar, não mais fácil).
5. Quanto tempo guardar? Padrão do plano: eventos 7 dias, notas 90 dias (já assim).
6. O que a staff faz com uma marca? O GM Handbook (seção 3a) trata a revisão do `botreview`; falta dizer se `/botcheck` entra no mesmo fluxo e quem pode escalar.
7. O memorial e rankings seguram contas marcadas (`chaos_antibot_holds`); as notas do O722 **não** seguram nada. Quer ligar?
8. A varredura de ferramentas lê nomes de processos e títulos de janelas do jogador, só no Windows e só para comparar hashes. Isto é dado pessoal sensível para algumas leis: precisa estar nas regras e na política de privacidade antes de ligar uma lista (rascunho abaixo).

### Rascunho do aviso para as regras do site (monitoramento)

> **Monitoramento contra bots.** Para manter o jogo justo, o servidor registra o comportamento do seu personagem (posições, passos, uso de magias e poções, alvos e pausas) por até 7 dias e calcula notas por hora, guardadas por até 90 dias. O client envia um resumo dos arquivos dos módulos do jogo e, no Windows, pode dizer ao servidor um código curto quando encontra no seu computador um programa de uma lista de ferramentas proibidas; ele não envia a lista de programas, nomes de janelas nem nenhum arquivo seu. Essas informações só são vistas pela equipe, nunca banem ninguém sozinhas e servem para a equipe revisar casos. Quem usar programas que automatizam o jogo fora das regras pode ter o personagem avaliado, advertido ou banido por decisão da equipe. Para saber mais ou pedir a remoção dos seus dados, fale com a equipe.

(É só um rascunho para o dono revisar com a política de privacidade; não foi publicado no site.)

## Plano de teste (a fazer com o servidor de verdade)

1. Coletar de 3 a 5 jogadores conhecidos por algumas horas (`/botcheck Nome` depois): as notas devem ficar abaixo de 40 (jogadores com o helper, abaixo de 55).
2. Rodar uma conta de teste com um cavebot (o Rumo ou outro bot público) por 2 horas na mesma caverna, **como personagem comum, não "Tester"** (testers são ignorados por desenho): a nota deve passar de 70, principalmente em rota e regularidade.
3. Ajustar os limites em `botdet_config.lua` até separar bem os dois grupos.
4. Custo: medido num servidor simulado (400 jogadores, meia hora, motor falso): ver `server/README.md`. O custo real do motor (as chamadas `getPosition`, o `getBotSignals`) só se mede no servidor cheio.

## Critérios de pronto

- [x] Coleta dos eventos da parte 1 e gravação em lote (testada contra um motor falso; **não** rodada em servidor real).
- [x] As heurísticas principais por hora, com notas salvas (testadas com traços sintéticos).
- [x] `/botcheck <nome>` para GMs.
- [x] Lista diária das 20 maiores notas (arquivo de log) e `chaos-ctl.sh botcheck-top`, com botões nos apps de admin.
- [ ] Teste com jogadores reais e com uma conta de bot, limites ajustados (precisa do servidor com jogadores).
- [ ] Política sobre bots (incluindo o Rumo) definida pelo dono e publicada nas regras.
- [ ] Servidor reconstruído com o src-patch 0093 e client reconstruído com o base patch 0207 (nenhum dos dois foi aplicado a uma árvore real; ver as notas dos patches).
- [ ] Lista oficial de módulos gerada na release (`gen_module_hashes.py`) e lista de ferramentas escolhida pela staff.
