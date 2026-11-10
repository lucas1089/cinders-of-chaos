# Cinders Admin: o app Android do servidor

Controla a VPS pelo celular. Nada fica aberto na internet: o app fala SSH com a sua VPS, com uma chave que nasce e fica
só no celular. Código em `android/`, parte do servidor em `server/deploy/chaos-ctl.sh`.

## O que o app faz

Visual escuro e quente, a mesma rampa de cinzas do app do PC (`desktop/src/theme.rs`). Brasa só no botão principal e no ponto do servidor no ar; dourado só na aba selecionada. Títulos em texto normal, ícones de traço fino num tamanho só. Quatro abas embaixo:

| Aba | Para quê |
|---|---|
| Painel | Estado do servidor em texto colorido (no ar, parado, falhou, ligando, sem serviço; no ar leva o ponto brasa), há quanto tempo está no ar, jogadores (toque: quem está online, com a classe), erros desde o último início (toque: abre os erros), memória e disco com barra, carga, último backup. Puxe para baixo para atualizar; atualiza sozinho a cada 30 s (muda em Config). Botões grandes: Ligar, Desligar, Salvar, Reiniciar, Reiniciar em… (1 a 15 min, com aviso aos jogadores), Backup. Os perigosos pedem confirmação; a resposta aparece num cartão, em português, com os detalhes escondidos e os botões **Copiar** e **Compartilhar** (uma resposta grande, como o log dos testers, vai como arquivo .txt para salvar ou anexar). Cartões **Atualizar servidor** e **Recompilar engine** (abaixo) |
| Comandos | Ações rápidas: aviso para todos, expulsar, abrir e fechar o login, versão por tag (layout padrão), **Taxa de XP**, **Par do cliente**, **Contas** (criar, trocar senha), **Saúde e espaço** (verificar, limpar sobras, ver backups, ver e ajustar o fuso horário), **Conferir lançamento** (a lista do lançamento contra o servidor instalado), **Servidor como usuário chaos** (Ver, Corrigir, Corrigir e reiniciar, Log do reinício), **Testers** (iniciar, parar, status, relatório, log das ações, apagar), **Site e update do client** (reinstalar o site, publicar o update de uma release). Painel do jogo: todos os comandos do painel de admin, por categoria, com busca e formulário (Chaos Coins: Store > Give Chaos Coins; grupo/GM: Players > Set group) |
| Logs | Console, Erros, Updates (servidor, publicação do client, instalação do site), GM e Terminal. GM: os logs de comando do staff (`data/logs/<nome> commands.log`, mais novo primeiro) e o registro do painel de admin (tabela `chaos_admin_log`), de todos ou de um membro do staff. Fonte monoespaçada, 50 a 500 linhas, Acompanhar (recarrega a cada 5 s), copiar. Erros: só desde o último início do servidor, linhas iguais juntas com a contagem (×56); "Incluir inícios anteriores" mostra os antigos, cada um com a data do início. "Limpar lista" (`errors clear`) zera a lista e o contador do Painel: só contam os erros novos; o log do servidor não é apagado. Terminal: qualquer comando na VPS, a pasta é guardada, botão `sudo -n` |
| Config | Endereço, porta, usuário, caminho do chaos-ctl.sh, personagem admin, intervalo do painel. Chave: gerar, mostrar, copiar, compartilhar, copiar o comando de instalação. Impressão digital da VPS com o botão Esquecer. Testar conexão |

Erros comuns viram frases claras: chave recusada, VPS sem resposta, porta fechada, impressão digital mudou, sem sudo,
script fora do caminho, unidade do systemd que não existe (código 5), cliente do banco ausente (código 127).

## Aba Comandos (o painel de admin inteiro)

Banir, dar itens, premium, spawn, eventos e tudo que o painel de admin do jogo faz. O app pede ao jogo a lista de
comandos do seu grupo e monta o formulário de cada um (texto, número, caixa, escolha, jogador, posição, IP).

1. Aba **Config**, campo **Personagem admin**: o nome de um personagem seu com grupo de admin. Salvar.
2. **O personagem não precisa estar online.** Os comandos rodam como ele, com o grupo dele: grupo 4 ou mais vê
   os comandos, ações perigosas pedem grupo 5 ou 6. Os limites do painel continuam valendo. Offline, só as ações que
   dependem do corpo do personagem no mapa (posição, teleporte, modo fantasma, velocidade) respondem "precisa do
   personagem no jogo"; as outras (banir, itens para outro jogador, premium, eventos, servidor) funcionam normal.
3. Aba **Comandos**, **Painel do jogo**, **Atualizar lista** (até 15 s). Toque numa categoria, depois no comando,
   preencha e **Executar**. A busca procura em todas as categorias.
   Ações marcadas como perigosas pedem confirmação. A resposta do jogo aparece abaixo.

O pedido vai por `chaos-ctl.sh catalog NOME` e `chaos-ctl.sh panel NOME ACAO JSON`: o script grava uma linha em
`remote.cmd`, o jogo executa pelo mesmo caminho do painel (com registro no log de admin) e responde em `remote.result`.

## Atualizar servidor (Painel)

O pedido do dono (2026-10-21): "um botão que busca no GitHub e, se for mais novo, aplica o update e reinicia o
servidor; também o client e os downloads do site". Para o kit Linux (`/opt/chaos-trial`).

1. **Verificar** (`chaos-ctl.sh update-check`): busca o ramo `CHAOS_UPDATE_BRANCH` (padrão `main`) e mostra os commits
   novos (a primeira linha de cada), a release instalada e a mais nova (`winpkg-N` de `CHAOS_RELEASE_REPO`), o update
   do client publicado, a release dos downloads do site, se o site mudou e a linha **Mapa**: a versão do mapa mestre
   (o mapa editado pelo dono, `server/README.md` "Map master") contra a instalada.
2. **Aplicar e reiniciar** (confirmação: os jogadores são desconectados). Caixas, todas marcadas: publicar o update do
   client, trocar os downloads do site, reinstalar o site se o código dele mudou. O app mostra o passo (1 a 10) com uma
   barra e as últimas linhas do log, lendo `update-log` a cada 4 s, e no fim um cartão: concluída, concluída com avisos,
   falhou, ou falhou e voltou à versão anterior. Se o app fechar, o Painel retoma o acompanhamento ao abrir.
3. **Voltar à versão anterior** (`update-rollback`): engine, `config.lua`, `data/`, o mapa (se a última atualização o
   trocou), o commit e os downloads de antes.

O que roda na VPS (`server/deploy/chaos_kit_update.sh`, em segundo plano, com trava: um por vez):

| Passo | O quê |
|---|---|
| 1 verificar | checkout sem mudanças locais e sem commits fora do GitHub; a release `winpkg-N` mais nova com o `CindersOfChaos-Server-Linux.tar.gz` |
| 2 baixar | só quando a release é mais nova que a instalada: download https, tamanho igual ao do GitHub, SHA-256 mostrado e comparado com o do GitHub, só o `server/tfs` sai do tar (caminhos conferidos), `ldd` sem biblioteca faltando. Qualquer falha aqui: nada mudou |
| 3 mapa | o mapa mestre (`world/` do ramo `CHAOS_MAP_BRANCH`, padrão `windows-assets`): se a versão é mais nova que a do mapa instalado, baixa só `world/` (fetch raso sem blobs), confere cada parte com o `SHA256SUMS` e o mapa inteiro com o `MAP_MASTER.json`. Sem mapa mestre: nada. Falhou: nada mudou (`--no-map` pula) |
| 4 backup | `backup.sh` com o servidor no ar (salva antes): dump do banco e `config.lua` + `data/` |
| 5 instalar | guarda as taxas de XP, checkout do ramo, e instala numa **cópia** da pasta do servidor (`server.new`, ao lado dela): troca o `tfs` (o antigo fica `tfs.antes-N`), troca o mapa pelo mapa mestre novo (o antigo fica em `$KIT/map-backups/<mapa>.otbm.<data-hora>`, os 3 mais novos), `install_all.py --no-sql`, devolve as taxas. **O jogo continua no ar nesse passo** (são os minutos do `install_all.py`). Se a instalação falhar na cópia: "falhou", o servidor nunca parou e o checkout volta ao que era. Sem espaço para a cópia (ou `CHAOS_STAGING=0`): o jeito antigo, servidor parado, instalando na pasta de verdade |
| 6 banco | para o servidor (ele salva todo mundo), leva para a cópia o que o jogo mudou na pasta de verdade desde a cópia (arquivos que só o jogo mexeu; um arquivo que o jogo e a instalação mudaram recusa a troca: "falhou", o servidor liga de novo, nada mudou), troca as pastas (`server.new` vira `server`, a antiga fica `server.old`), arquivos auxiliares do kit, dono da pasta = usuário da unidade, liga o servidor (o MariaDB do kit roda dentro da unidade), espera o banco, `install_all.py --only sql`, reinicia (o motor sobe com as tabelas novas). **É aqui que o jogo fica fora do ar** |
| 7 conferir | unidade ativa e "Server Online" no log em até 15 min. Falhou nos passos 6 e 7: volta sozinho (renomeia `server.old` de volta, em segundos; sem troca de pastas: engine, `config.lua` e `data/` do backup, o mapa do `map-backups`), commit anterior, liga e confere de novo |
| 8 client | `publish_client_update.sh winpkg-N` se a release é mais nova que o update publicado |
| 9 downloads | `CindersOfChaos-Client-Windows.zip` e `CindersOfChaos-Client-Linux.tar.gz` em `CHAOS_DL_DIR` (padrão `/var/www/chaos/dl`): nome temporário, tamanho e SHA-256 conferidos, o antigo fica como `NOME.prev`, troca atômica; `NOME.sha256` e `downloads.json` (a página de downloads mostra release, data, tamanho e SHA-256) |
| 10 site | `website/install_site.sh CHAOS_ENV CHAOS_SITE_ENV` se `website/` mudou e `/etc/chaos/site.env` existe |

Passos 8 a 10 nunca desfazem o servidor: uma falha neles termina com "concluída com avisos".

**Taxas de XP.** O passo `lategame` do `install_all.py` reescreve a tabela `experienceStages` do `config.lua` com a da
release, o que apagava um x10 posto à mão. Agora a atualização guarda a tabela e as linhas `rateExp`, `rateSkill`,
`rateLoot`, `rateMagic`, `rateSpawn` antes (`chaos_config_rates.py save`) e devolve depois (`restore`); o log diz o que
voltou. Uma tabela nova da release (`late_game.py`) só entra com Taxa de XP > Voltar ao padrão (ou um x N de novo).

**Banco.** A volta automática não mexe no banco: os arquivos `server/sql/*.sql` só criam tabelas e colunas que faltam,
e a versão anterior roda com elas. Restaurar um dump é o "Incident runbook" do `docs/LAUNCH.md`.

Configuração em `/etc/chaos/ctl.conf` (veja `server/deploy/ctl.conf.trial.example`): `CHAOS_KIT_DIR`,
`CHAOS_UPDATE_BRANCH`, `CHAOS_RELEASE_REPO`, `CHAOS_DL_DIR`, `CHAOS_SITE_DIR`, `CHAOS_SITE_ENV`, `CHAOS_BOOT_TIMEOUT`,
`CHAOS_KIT_STATE` (estado: `/var/lib/chaos/kit-update/state`, com a release instalada). Na primeira vez a release
instalada é desconhecida: o passo 2 baixa a mais nova e, se o `tfs` for igual ao instalado, só anota o número.

## Recompilar engine (Painel)

O pedido do dono (2026-11-08): "Pode montar o botão de recompilar no app". O engine do servidor (o `tfs`, com todos os
patches de `server/src-patches/`, hoje até o 0089, o saco de loot) é compilado no GitHub Actions pelo workflow manual
`windows-package.yml`, que publica a prerelease `winpkg-N` com o `CindersOfChaos-Server-Linux.tar.gz`. Antes, alguém tinha
de abrir a página do workflow e rodá-lo. Agora o cartão **Recompilar engine** (Painel no app do celular; Atualizações >
Recompilar engine no app do PC), logo abaixo de Atualizar servidor, faz isso e acompanha.

O caminho inteiro, sem terminal:

1. **Recompilar** (confirmação: leva de 20 a 60 minutos no GitHub, a primeira vez ou depois de uma mudança grande pode
   passar de uma hora; o jogo segue no ar e nada é trocado no servidor). A VPS pede ao GitHub o workflow na branch
   `CHAOS_UPDATE_BRANCH` (`chaos-ctl.sh engine-build start`).
2. O cartão mostra o estado e se atualiza sozinho a cada 20 s enquanto a rodada está na fila ou rodando: na fila, compilando
   há N min (com o job e o passo), pronto, falhou (com o job e o passo que falharam) ou cancelada. Pode fechar o app: a
   compilação continua no GitHub e o cartão retoma ao abrir. **Atualizar estado** pergunta na hora; **Ver passos** mostra os
   jobs da rodada, os passos que falharam e o histórico das partidas (o log completo fica na página da rodada no GitHub).
3. Terminou e a release é mais nova que a instalada: o cartão diz "Pronto: winpkg-N tem o engine novo" e aponta para
   **Atualizar servidor**. Lá, Verificar mostra `Servidor (engine): winpkg-A → winpkg-N` e Aplicar e reiniciar instala o
   engine com backup, reinicia e confere, como sempre. O botão Recompilar nunca troca nada no servidor.

Só uma rodada por vez: com uma na fila ou rodando, Recompilar é recusado (também quando a rodada foi aberta na página do
GitHub). Se uma rodada falhar, nada mudou; corrija o motivo (o job e o passo estão no cartão) e rode de novo.

### Token do GitHub (uma vez)

A VPS precisa de um token para pedir a compilação. Crie um que só serve para isto:

1. GitHub > sua foto > Settings > Developer settings > Personal access tokens > **Fine-grained tokens** > Generate new token.
2. Nome: `cinders-recompilar`. Expiração: a que preferir (90 dias, por exemplo; ao vencer o cartão diz "O GitHub recusou o
   token" e basta definir outro). Resource owner: a conta dona do repositório.
3. Repository access: **Only select repositories** e escolha só `lucas1089/cinders-of-chaos`.
4. Repository permissions: **Actions: Read and write**. Nenhuma outra (o Metadata de leitura vem sozinho; o repositório é
   público, então ler as releases não pede mais nada).
5. Generate token e copie o `github_pat_...` (ele só aparece uma vez).
6. No app: Painel > Recompilar engine > **Definir token do GitHub**, cole e **Salvar token** (no app do PC: Atualizações >
   Recompilar engine > Definir token do GitHub). Campo vazio apaga o token.

O token vai pelo SSH no stdin do `chaos-ctl.sh engine-build-token-set`, nunca numa linha de comando. A VPS confere o formato,
pergunta ao GitHub se ele alcança o repositório (um token recusado não é guardado), guarda em
`/etc/chaos/engine-build.token` (só root, modo 600, `CHAOS_ENGINE_TOKEN_FILE` no `ctl.conf` muda o caminho) e nunca o mostra:
nem na saída, nem no log, nem na lista de processos (o `curl` lê o cabeçalho de um arquivo de configuração no stdin). O app
mostra só "token: sim ou não". Esse token não lê nem escreve código, só roda e lê workflows deste repositório.

### O número do client (`client_build`)

O workflow tem o input `client_build` (o número que o executável do client carrega e que o servidor confere; também é o
`Services.update.package`). Regra do botão, pensada para o número nunca voltar nem apontar para dois executáveis:

- O padrão é o **número do client publicado**: o `min_package` do manifesto assinado ao vivo
  (`$CHAOS_SITE_DIR/updates/live/manifest.json`), o mesmo que `publish_client_update.sh` usa. Os outros inputs ficam no padrão
  do workflow e `allow_dev_key` é sempre `false` (sem os segredos `CHAOS_CLIENT_KEY` e `CHAOS_RSA_PUBLIC` do repositório a
  rodada falha, e é o certo).
- Com o mesmo número, o executável só é o mesmo se o programa do client não mudou. A VPS compara, com o próprio checkout, o
  commit do client publicado (guardado pelo botão; antes disso, o último commit instalado por Atualizar servidor) com a
  ponta da branch, nos caminhos `client/base-patches`, `client/overlay/src`, `client/tools/chaos_hardening.cmake` e
  `launcher`. Mudou: **recusa** (`client-changed`) e nada é pedido ao GitHub. Mudar só Lua, dados, servidor ou site não
  conta, porque esses vão pelo update assinado e não pelo executável.
- Número menor que o publicado: recusado (`client-build-backwards`). Sem update de client publicado e sem número dado:
  recusado (`client-build-unknown`).
- Programa do client mudou de verdade (é o caso quando o `main` mexeu em `client/base-patches`): o estado traz
  `client_changed=yes` e `client_next=N` (publicado + 1), e o cartão mostra o segundo botão **Recompilar com client
  novo (build N)** (no app do PC: o botão de mesmo nome; `chaos-ctl.sh engine-build start --new-client`). A confirmação
  explica: sai um client novo com o build N, os jogadores o recebem pelo atualizador depois de Atualizar servidor, e o APK
  do Android precisa acompanhar (`android-client.yml` com `client_build` N), senão os celulares ficam sem poder jogar.
  O servidor aceita o N sozinho: ao começar, a VPS põe N na lista `clientGuardBuilds` do `config.lua` (`eb_guard_add`,
  backup `config.lua.before-guard-DATA`, os builds antigos ficam; lista vazia já aceita qualquer build; sem a linha ou sem
  o arquivo, o app avisa para pôr N à mão). Adiantar é inofensivo, porque os antigos continuam aceitos; o servidor lê o
  `config.lua` no próximo início, que o Atualizar servidor faz, e o manifesto publicado no passo 8 (`min_package` N) só
  passa a recusar os builds abaixo de N depois disso. Nada é removido neste passo: tirar os builds antigos da lista é
  decisão sua, depois que os jogadores atualizaram. Recusa `update-running` se uma atualização está rodando (para não
  editar o `config.lua` no meio da instalação). `--client-build N` continua existindo para outro número.
- Com o mesmo número, Atualizar servidor publica o client novo como uma versão nova do manifesto (a versão é o número da
  rodada, sempre maior) com o mesmo `min_package`: ninguém precisa baixar o client de novo, os módulos novos chegam pelo
  update assinado, e `publish_client_update.sh` recusa republicar uma versão que não é maior que a publicada.

### Erros que o cartão traduz

`token-missing` (sem token), `token-refused` (401: vencido ou apagado), `no-access` (o token não alcança o repositório ou
falta Actions leitura e escrita), `build-running`, `client-changed`, `client-build-backwards`, `client-build-unknown`,
`client-check-failed` (sem commit para comparar: rode Atualizar servidor uma vez), `fetch-failed`, `workflow-refused`
(422: a branch não tem o workflow manual), `dispatch-failed` e `github-unreachable`.

Pelo SSH: `chaos-ctl.sh engine-build status | start [--client-build N] | log [N]` e `chaos-ctl.sh engine-build-token-set`
(token no stdin). Testes: `server/deploy/chaos_ctl_test.py` (`test_engine_build`, com um `curl` falso no lugar do GitHub),
`android/.../EngineBuildInfoTest.java` e `desktop/src/engine.rs`.

## Comandos frequentes (Ações rápidas)

- **Taxa de XP** (`xp-rate show | set N | reset [restart]`): x1 a x100 sobre os estágios da release, com backup do
  `config.lua` (`config.lua.before-xp-DATA`). Gravar vale no próximo reinício; Gravar e reiniciar reinicia já.
- **Par do cliente** (`client-pair show | set N`, aba Comandos > cartão Par do cliente > Ver / Gravar): grava no `config.lua` (`chaosClientPair`) o par de sprites do cliente já publicado. O
  Atualizar servidor só instala os itens de um par novo (par 55: globos e brasa; par 56: armas de punho novas e as armas acima
  do nível 800) depois de gravar o número do par, depois de publicar a atualização do cliente. Número menor que o gravado é
  recusado. server/README.md "Client pair guard".
- **Modo beta (testes)** (`beta-mode status | on | off [restart]`, aba Comandos > cartão Modo beta (testes) > Ver / Ligar /
  Desligar / Ligar e reiniciar / Desligar e reiniciar): tira os limites semanais e diários do jogo para os testers
  (trava semanal do raide e do chefe da guilda, tarefas de caça, ofertas semanais do Candlemarks e das facções, teto de
  honra e da comunidade, espera das masmorras; lista em server/README.md "Beta test mode"). Os limites da loja
  (dinheiro real, como a Poção de XP em dobro) não mudam. Edita a linha `enabled` de `beta_mode_config.lua` (backup
  `.before-beta`); vale no próximo reinício ou já com "e reiniciar". Atualizar servidor mantém a chave. Desligue no
  lançamento. O app precisa ser recompilado para ter o cartão; o comando funciona pelo SSH sem isso.
- **Serviços da tela de login (Rust)** (`clientservices-impl status | rust | python`, aba Comandos > cartão Serviços da
  tela de login (Rust) > Ver / Ligar Rust / Voltar ao Python): quem responde a porta 8090 da tela de login (criatura do
  dia, eventos, jogadores online). Padrão: o Python (`server/tools/clientservices.py`). Ligar o Rust compila
  `server/services/clientservices-rs` no servidor (precisa do `cargo`, `--locked`, alguns minutos), instala o binário em
  `/opt/chaos/bin`, grava o drop-in `10-rust.conf` do systemd e reinicia só `chaos-clientservices` (o jogo não
  reinicia). Compilação que falha não muda nada; serviço que não sobe volta sozinho para o Python. Atualizar servidor
  recompila enquanto estiver ligado. O app precisa ser recompilado para ter o cartão; o comando funciona pelo SSH sem isso.
- **Contas** (`account-create NOME`, `account-password NOME`): a senha vai pela entrada do comando (stdin do SSH),
  nunca na linha de comando nem em log, e vira hash PBKDF2 como o site grava. O personagem se cria no client ou no site.
- **Discord** (`discord-set CANAL`, `discord-enable`, `discord-disable`, `discord-test`, `discord-status`; aba Comandos >
  Ações rápidas > cartão Discord (anúncios do jogo) > um campo por canal + Salvar / Ativar / Desativar / Testar /
  Atualizar status): a URL do webhook vai pela entrada do comando (stdin do SSH), nunca na linha de comando nem em log, e
  fica só em `/etc/chaos/discord.env` (modo 600, dono www-data); o app confere o formato antes de enviar e não mostra a URL
  de volta (só o final do id). Ativar instala as unidades `chaos-discord.service/.timer` e o logrotate do repositório e liga
  o timer. Passo a passo: docs/LAUNCH.md "Discord announcements". O app precisa ser recompilado para ter o cartão.
- **Bot do Discord** (`discord-bot status | install | set NOME | start | stop | restart | logs [N] | patchnotes`; aba Comandos >
  Ações rápidas > cartão Bot do Discord (bugs e patch notes); no desktop, Discord > Bot do Discord): lê o canal de
  bugs com o Claude, avisa por DM os bugs críticos e ajuda a escrever os patch notes. Instalar cria o usuário `chaosbot`, o
  virtualenv com as versões fixas e o `chaos-discordbot.service`; Salvar grava um valor em `/etc/chaos/discord-bot.env` (modo
  600): o token e a chave da API vão pela entrada do comando, nunca na linha de comando nem em log, e o app não os mostra de
  volta. Iniciar recusa com `config-missing` e os nomes que faltam. Levar patch notes ao jogo copia os arquivos novos para
  `data/patchnotes`. Passo a passo para o dono: `server/deploy/discord_bot/README.md`. O app precisa ser recompilado para ter o cartão.
- **Pagamentos (doações)** (`pay-status`, `pay-set NOME`, `pay-test`, `pay-enable`, `pay-disable`, O413; aba Comandos >
  Ações rápidas > cartão Pagamentos (doações); no desktop, VPS e manutenção > Pagamentos (doações)): um campo por chave
  com Salvar (Access Token e assinatura do Mercado Pago, Client ID, Secret e Webhook ID do PayPal, endereço do site,
  e-mail para Pix), Ligar / Desligar Pix e PayPal, Sandbox / Live, Categoria, os dois endereços de webhook com Copiar,
  Ativar worker / Desativar, Testar e Estado. O valor vai pela entrada do comando, nunca na linha de comando nem em log,
  e fica só em `/etc/chaos/payments.env` (modo 640, root:www-data; o primeiro Salvar cria o arquivo do exemplo e o salt
  dos pagadores). O app confere o formato antes de enviar; o Estado diz só sim ou não. Testar só lê: `/users/me` do
  Mercado Pago, o token OAuth do PayPal do ambiente salvo e uma chamada sem assinatura a cada webhook (401 = certo).
  Ativar instala o `chaos-payworker.service` do repositório com os caminhos reais. Passo a passo: docs/PAYMENTS.md. O app
  precisa ser recompilado para ter o cartão.
- **Saúde e espaço** (`health`, `cleanup [--yes]`, `backups`): servidor, banco, serviços web (nginx, apache, php-fpm),
  disco e memória. Limpar mostra a lista e pede confirmação antes de apagar: pastas de trabalho de atualizações e
  publicações em `/var/tmp` com mais de um dia, pastas `srvNN` lá, `tfs.antes-*` além dos 2 mais novos,
  `config.lua.before-*` além dos 5 mais novos. Backups: lista os dumps e arquivos; restaurar continua sendo pela VPS.
  Fuso horário (O439; `timezone`, `timezone set`): **Ver fuso horário** mostra o fuso da VPS, a hora de lá, o desvio de UTC e o
  fuso esperado (America/Sao_Paulo, UTC-3), certo ou ERRADO. O jogo usa a hora da VPS (Season 1, Founder Pack, bônus de
  lançamento dos criadores, salvamento das 06:00). **Ajustar para São Paulo** pede confirmação, ajusta com `timedatectl` e diz
  no resultado para reiniciar o jogo em Painel > Servidor: um processo que já roda guarda o fuso antigo. O botão não reinicia
  nada. O app precisa ser recompilado para ter os dois botões. No desktop: VPS e manutenção > Saúde e espaço, os mesmos dois.
- **Conferir lançamento** (`launch-check`; Comandos > Ações rápidas > cartão Conferir lançamento > Conferir; O440): lê o servidor
  instalado e não muda nada. Mostra uma linha de resumo ("3 falhas, 2 avisos" ou "Tudo certo para o lançamento") e as linhas
  com as falhas primeiro: beta e modo beta desligados, cron das moedas de teste ausente, pagamentos sem mock, arquivos de
  teste, fuso horário, `maxPlayers`, a data do lançamento (`launch_config.lua`; "em aberto" é um aviso: "nenhuma data de lançamento
  definida"), datas da Season 1, da temporada PvP, do Founder Pack e do bônus dos criadores contra ela, chave e modo do guarda do client (só presença: a chave nunca aparece), patch notes do lançamento,
  contagens do banco (sem nomes), backup de menos de 24 horas e a versão instalada. Copiar leva o resultado para o
  clipboard. O app precisa ser recompilado para ter o cartão. No desktop: VPS e manutenção > Conferir lançamento > Conferir
  (as linhas do próprio comando). Detalhes das regras: server/README.md "Launch check (O440)".
- **Servidor como usuário chaos** (`server-user status | fix [--restart 300] | rollback | log`; Comandos > Ações rápidas > cartão
  Servidor como usuário chaos > Ver / Corrigir / Corrigir e reiniciar (5 min) / Log do reinício): o motor avisa "executed
  as root user" quando a unidade do systemd roda o jogo como root. **Ver** mostra com que usuário o motor roda, o `User=` da
  unidade, o dono das pastas e se o repositório continua só do root; não muda nada. **Corrigir** cria o usuário `chaos`
  (sem login), passa a ele só as pastas que o jogo grava (no kit: server, database, run, logs, crashes e o chaos.env; nunca o
  repositório), dá ao banco do kit o administrador `chaos` pelo socket, instala a unidade do layout certo com `User=chaos`
  (a antiga fica em `/var/lib/chaos/server-user`) e confere com `systemd-analyze verify`; se algo falha, a unidade antiga
  volta. Não reinicia: o motor segue como root até a unidade reiniciar (o salvamento diário não reinicia a unidade).
  **Corrigir e reiniciar (5 min)** avisa os jogadores, para (salva), passa as pastas de novo, liga como chaos e confere; se
  não subir como chaos, a unidade antiga volta e liga sozinha. Pode ser repetido. A atualização do servidor (Painel >
  Atualizar servidor) avisa quando a unidade ainda roda como root. Detalhes: server/README.md "Server user (O271)".
- **Testers** (`testers start N MINUTOS --restart 300`, com o botão **Iniciar testando a árvore** `testers start N MINUTOS --keystones --restart 300`, `testers stop`, `testers status`, `testers report`, `testers log 400`, `testers cleanup --yes`): os
  testers no servidor ao vivo (server/README.md "Tester bots"). Iniciar reinicia o servidor com 5 minutos de aviso
  só quando o ajudante de teste ainda não carregou. A chave fica em /etc/chaos/tester-client-key (criada pela VPS).
  Status mostra quantos testers estão online agora, o pico da rodada e a contagem do servidor.
  **Iniciar testando a árvore** (O249): cada tester aloca os keystones e masteries da sua classe como um jogador, confere
  se o efeito aparece, anota "não observável" onde o cliente não vê, e zera a árvore; o resultado por nó é uma seção do
  Relatório (server/README.md "Tester bots", Keystones and masteries).
- **VPS** (`vps info`, `vps upgrade`, `vps upgrade-log 200`, `vps reboot MIN`, `vps reboot-cancel`): memória, disco,
  carga, atualizações do sistema pendentes (e quantas são do PHP), o pacote do PHP (php*-fpm ou o mod_php do Apache) e se precisa reiniciar. Atualizar sistema roda `apt-get update` e `upgrade`
  em segundo plano, mantendo os arquivos de configuração. Reiniciar VPS avisa os jogadores, salva o jogo e reinicia a
  máquina em 1 a 60 minutos; dá para cancelar.
- **Serviços** (`services`, `service NOME start|stop|restart`, `service-log NOME 200`): cada unidade `chaos-*`
  (servidor, backup, ajuda, Discord, pagamentos, saúde, watchdog) e o servidor web (apache2, nginx, php-fpm), ligada
  ou não; depois de atualizar o PHP, reinicie o apache2 (ou o php-fpm) aqui; ver log, reiniciar, ligar, desligar.
- **Site e update do client** (`site-install`, `site-log`, `publish-update TAG`, `publish-apk TAG`, `publish-unity TAG`, `publish-log`). "Publicar client Unity" (`publish-unity unity-N`, O433 fase 16; campo "Release do client Unity (beta)") assina o client Unity, do zip anexado a mão a uma release (artefato do workflow Unity prototype), como `updates/unity` do site: o launcher passa a oferecer "Cliente Unity (beta)"; o update do client principal não muda. "Publicar app Android" (`publish-apk android-N`, O313) publica o APK do celular, da release do workflow Android client, como atualização do app: os celulares oferecem a troca ao abrir; "Tirar o app do update" remove a oferta. "Trocar os downloads do site" (`update-downloads`, O165) põe o pacote completo mais novo (Windows e Linux) na pasta `dl/` do site sem reiniciar o servidor; "Log da atualização" mostra o andamento. `publish-update` publica só a atualização assinada, não os pacotes.
- **Mapas pedidos** (`areas-publish [--pictures] [--rotate]`, O192; Comandos > card "Mapas pedidos"). "Publicar áreas" monta, a partir das áreas pendentes e aprovadas da pasta `server/tools/areaplan/inbox/` do repositório na VPS (traga com Painel > Atualizar servidor depois de unir na main), os arquivos do editor de mapas em `dl/areas-TOKEN/` do site e mostra a linha `url=`; copie-a (botão de copiar do resultado) e rode `fetch-areas.bat` no Windows. "Novo endereço" (`--rotate`) cria outro TOKEN e apaga a pasta antiga. O site não tem login para arquivos estáticos: o TOKEN (32 dígitos hexa, `/var/lib/chaos/areas/token`) é a proteção. Não reinicia nem altera o mapa do jogo. docs/MAP_GUIDE.md "Map inbox".
- **Logs de GM** (aba Logs, GM; `gm-logs [N] [NOME]`).
- **Métricas dos jogadores** (aba Painel, card "Métricas dos jogadores", botão "Atualizar métricas"; `metrics [--json]`, O253). Só
  leitura. Mostra por faixa de nível quantos personagens pararam de jogar (sem login há 14 dias ou mais), as 10 áreas e os 10
  monstros com mais mortes, a duração da primeira sessão de personagens novos e o tempo mediano jogado até os níveis 10, 25,
  50, 100 e 200. São contadores anônimos (sem nomes, contas nem IPs; testers e GMs ficam de fora), lidos da tabela
  `chaos_progress_metrics`; server/README.md "Progress metrics (O253)". Precisa do passo `sql` do `install_all.py` (ou o
  servidor cria a tabela ao ligar) e de um app recompilado para o card; o comando funciona pelo SSH sem isso.
  O258: o card "Funil dos jogadores" (logo abaixo, preenchido pelo mesmo botão) mostra a volta dos personagens novos nos dias 1, 3 e 7 por semana de entrada, quando cada sistema (masmorra, fenda, torre, mercado, guilda...) é usado pela primeira vez e as áreas onde ficaram os personagens que pararam; níveis até 2000 entram no tempo mediano. server/README.md "Funnel metrics (O258)".
  O437: o mesmo card "Funil dos jogadores" (no app desktop: Jogadores > "Métricas dos jogadores", tabela "Retenção por dia de criação") mostra, por dia de criação (dia do servidor), quantos personagens novos voltaram no dia 1 (o dia seguinte), nos dias 2 a 7, nos dias 8 a 30 e em algum dia de 1 a 7 e de 1 a 30, com a porcentagem de cada janela e um total dos dias com janela terminada. Cada personagem conta uma vez por janela; "dia 1" mais "dias 2-7" não é o mesmo que "algum dia de 1-7" (o mesmo personagem pode estar nos dois). A porcentagem só aparece com a janela terminada e a partir do dia em que a contagem começou (dias antes disso aparecem como "parcial"); grupos com menos de 5 aparecem como "<5". Sem nomes, contas nem IPs; testers e GMs ficam de fora. Precisa de um app recompilado para a seção nova e do servidor atualizado e reiniciado uma vez (Painel > Atualizar servidor); pelo SSH: `chaos-ctl.sh metrics`. server/README.md "Retention by creation day (O437)".
- **Novos jogadores** (aba Painel > card "Novos jogadores" > botões "Funil", "Pesquisa" e "Copiar"; no app desktop: Jogadores > Novos jogadores > Funil / Pesquisa; `newplayer-funnel [--days N] [--json] [--pt]` e `survey [--days N] [--json] [--pt] [--texts N]`, O374). Só leitura. O campo "Últimos dias" (1 a 3650, padrão 30) escolhe o período. "Funil": dos personagens que entraram pela primeira vez no período, quantos chegaram aos níveis 10, 20, 30, 50 e 100, quantos jogaram 1, 5 e 10 horas, e dos que pararam (sem login há 7 dias ou mais) em que faixa de nível, depois de quantos minutos jogados e depois de qual sistema (masmorra, fenda, mercado... ou "nenhum (só caçou)"). Grupos com menos de 5 aparecem como "<5". "Pesquisa": as respostas da janela que abre no jogo nos níveis 20 e 50 (uma vez por conta): quantos responderam e pularam, a nota média de diversão (1 a 5) e a distribuição, quantos recomendariam, e os textos de "O que te confundiu até agora?" (os mais novos primeiro, com nível e tempo jogado). Sem nomes, contas nem IPs; testers e GMs ficam de fora. "Copiar" copia o relatório para colar no Claude. Precisa do repositório atualizado na VPS (Painel > Atualizar servidor; o comando lê `server/tools/newplayer_report.py`), do passo `sql` do `install_all.py` para a tabela `chaos_survey` (ou o servidor cria ao ligar) e de um app recompilado para o card; pelo SSH: `chaos-ctl.sh newplayer-funnel --pt` e `chaos-ctl.sh survey --pt`. server/README.md "New player funnel and survey (O374)".
- **Saúde do jogo** (aba Painel > card "Saúde do jogo" > botão "Atualizar saúde do jogo"; no app desktop: Jogadores > Saúde do jogo > "Carregar gráficos (7 dias)" ou "Ver como texto"; `game-health [--days N] [--kv | --json] [--pt]`, O397). Só leitura. O campo "Últimos dias" (1 a 90, padrão 7) escolhe o período. Mostra: jogadores online por hora (barras com a média de cada hora; um buraco = servidor sem amostra), a média por hora do dia com a hora mais cheia e a mais vazia, mortes por hora e por hora de jogo, as 10 hunts mais usadas e as 10 menos usadas (horas caçando, personagem-horas, abates, mortes; toda hunt do mapa aparece, mesmo com 0), o ouro que entrou e saiu por fonte, e o funil dos novos jogadores dos últimos 30 dias (o mesmo do card Novos jogadores). Grupos com menos de 5 aparecem como "<5". Sem nomes, contas nem IPs. As hunts só enchem a partir desta atualização. Precisa do repositório atualizado (Painel > Atualizar servidor), do passo `sql` do `install_all.py` para a tabela `chaos_telemetry_area` (ou o servidor cria ao ligar) e de um app recompilado; pelo SSH: `chaos-ctl.sh game-health --pt`. server/README.md "Game health panel (O397)".
- **Relatório de equilíbrio** (aba Painel > card "Relatório de equilíbrio" > botões "Últimos dias", "Season atual", "Enviar por DM", "Último salvo", "Ligar automático", "Desligar" e "Copiar"; no app desktop: Jogadores > Relatório de equilíbrio; `balance-report [--days N | --season ID|current] [--pt] [--json] [--save] [--dm]`, `balance-report last`, `balance-report timer on|off|status`, O398). Compara as classes por faixa de nível: minutos por nível, mortes por hora caçando, dano por hora e a parte de cada classe no dano da faixa, e os 3 feitiços mais usados. Toda classe a mais de 15% da mediana da faixa (mortes: 25%) ganha uma sugestão, por exemplo "uns +6% de dano ou experiência". É só sugestão: nada muda no jogo. Classe com menos de 5 horas caçando na faixa aparece como "<5" e não é comparada. "Últimos dias" usa o campo (1 a 730, padrão 30); "Season atual" usa as datas da season (com os ajustes de `/season start|end`). "Enviar por DM" guarda em `/var/lib/chaos/balance` e o bot do Discord manda por DM em até 1 minuto (precisa do bot instalado e atualizado: Comandos > Bot do Discord > Instalar ou atualizar). "Ligar automático" liga um timer diário: quando uma season termina, o relatório dela é guardado e vai por DM sozinho. "Último salvo" mostra o mais novo guardado. O dano só conta com o log de combate ligado. Pelo SSH: `chaos-ctl.sh balance-report --pt`. server/README.md "Season balance report (O398)".
- **Bugs e sugestões** (aba Painel > card "Bugs e sugestões" > botões "Atualizar", "Copiar tudo" e, em cada relato, "Fechar"; `feedback [--days N] [--all] [--category C] [--names]` e `feedback-close ID [NOTA]`). Mostra o que os jogadores mandaram em System > Report a Bug, os mais novos primeiro: número, data (UTC), categoria (Mapa, Texto errado, Técnico, Outro, Sugestão), o texto, a posição e o nível e a classe de quem mandou. O campo "Últimos dias" (1 a 3650, padrão 30) e a caixa "Incluir os já fechados" filtram. "Copiar tudo" copia a lista em texto simples, com uma linha pedindo ao Claude para classificar e priorizar: cole direto na conversa. "Fechar" (com a nota opcional do campo "Nota ao fechar") marca o relato como fechado. O app nunca pede nomes, e o servidor nunca imprime contas, IPs nem e-mails; sem `--names` o texto copiado não leva dado de jogador. Sugestões: o cliente base não tem a opção, então o jogador escreve `sugestão:` ou `suggestion:` no começo do texto em "Outro" (server/README.md "Bug reports"). Precisa do repositório atualizado na VPS (Painel > Atualizar servidor; o comando lê `server/tools/feedback_format.py`) e de um app recompilado para o card; pelo SSH: `chaos-ctl.sh feedback`.
- **Assistir jogador** (Comandos > Ações rápidas > Assistir jogador). Só leitura: o jogador não é avisado e nada
  muda no jogo.
  - **Ao vivo** (`cast NOME`): o jogo como o jogador vê, em movimento, uns 30 quadros por segundo. Os 15 x 11
    quadrados do andar dele, com itens animados, criaturas andando, magias, projéteis, barras de vida, nomes, falas e
    números de dano. Desenha também os outros andares que o jogo mostra (o de cima some quando há telhado ou teto
    sobre o jogador, como no jogo) e a luz: o escuro da noite e das cavernas, com um brilho redondo em volta de
    tochas, criaturas e magias que brilham. Nível, vida e mana embaixo. Para no botão Parar, ao trocar de aba, ao sair
    do app, num erro e depois de 30 minutos. Uma visão ao vivo por vez. Não desenha a interface do jogo. Precisa do app
    novo e do relay novo juntos para ver andares e luz; um dos dois antigos ainda mostra o andar do jogador.
  - **Tela preta (O265, 2026-10-26):** só nomes e barras de vida apareciam. O escuro do jogo (noite: luz do mundo 40 de
    255; subsolo: 0) era multiplicado sobre o quadro e os nomes são desenhados depois da luz. Agora o mapa nunca fica
    abaixo de uns 40% (botão **Luz clara**; **Luz do jogo** volta ao escuro de verdade) e as luzes dos itens (tochas)
    brilham de fato. Falhas de sprite aparecem na linha de estado: "Sprites: N sprite(s) não vieram (chave: motivo)" (o
    relay manda `sprerr`; o app conta imagens ilegíveis) e "Nenhum sprite chegou da VPS" quando há mapa e nenhuma
    folha. Precisa do app novo (APK) e do `cast_relay.py` novo na VPS (atualizar o repositório em Comandos > Versão do
    servidor).
  - **Ligar a porta de cast (uma vez):** o motor precisa do src-patch 0064 e de `castPort` no `config.lua` (porta só
    em 127.0.0.1, desligada por padrão). No app: Painel > Atualizar servidor com uma versão que tenha o patch 0064. A
    atualização roda o `install_all.py`, e o passo `castport` liga a porta (7179). Sem o app, na VPS:
    `sudo python3 -I /opt/chaos/repo/server/tools/install_all.py /opt/chaos/server --only castport`, depois Painel >
    Reiniciar (ou `chaos-ctl.sh restart`). Sem a porta o Ao vivo avisa "A porta de cast está desligada". Para ver as
    linhas JSON na VPS: `sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh cast NOME` (Ctrl+C para parar).
  - **Foto** (`spectate NOME`): uma imagem só, desenhada na VPS, com nome, nível, vocação, vida, mana e posição
    embaixo. Funciona sem a porta de cast. No máximo uma a cada 0,8 s.
  Antes da primeira vez a VPS precisa do par de sprites do client: no mesmo card, **Baixar sprites** (confirmar;
  `spectate-pair fetch`) baixa o arquivo do ramo `windows-assets`, confere as somas SHA-256 e troca a pasta
  `/opt/chaos/pair` (a mesma do `CHAOS_SPRITE_PAIR` do site); acompanhe em **Log do download**
  (`spectate-pair log`) e confira em **Sprites na VPS** (`spectate-pair status`). Leva alguns minutos e usa uns
  2,3 GB de disco temporário. Sem o app, na VPS: `sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh spectate-pair fetch`.
  A VPS precisa de `python3-numpy` e `python3-pil` (`sudo apt-get install python3-numpy python3-pil`).

## Instalar o app

1. No GitHub: Actions, **Admin app**, Run workflow. No fim, a Release `adminapp-N` tem o `CindersAdmin.apk`.
2. Baixe o APK no celular, permita instalar desta fonte e instale.
3. **Assinatura estável (faça uma vez):** sem ela cada APK novo tem outra assinatura e você precisa desinstalar o app
   antes de instalar o novo (a chave SSH some junto). Crie a chave de assinatura num computador:
   `keytool -genkeypair -keystore admin.jks -alias cinders -keyalg RSA -keysize 3072 -validity 9125`
   e cadastre em Settings, Secrets, Actions: `ANDROID_KEYSTORE_B64` (`base64 -w0 admin.jks`),
   `ANDROID_KEYSTORE_PASS` e `ANDROID_KEY_ALIAS` (`cinders`). Guarde o `admin.jks` num cofre de senhas.

## Ligar o app à VPS (3 minutos)

1. A VPS precisa do repositório em `/opt/chaos/repo` (o mesmo de `docs/LAUNCH.md`). Traga a versão nova:
   `cd /opt/chaos/repo && git fetch origin --tags && git checkout <tag>` (ou `git pull`).
2. App, aba **Config**: endereço da VPS, porta (22), usuário `chaosadmin`. Salvar.
3. **Gerar chave**, depois **Copiar comando do servidor**. Cole esse comando no terminal da VPS (como root ou com sudo).
   Ele cria o usuário `chaosadmin`, instala a chave e libera `sudo` só para o `chaos-ctl.sh`.
4. **Testar conexão**. Na primeira vez o app mostra a impressão digital do servidor: confira com
   `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` na VPS. Daí em diante ela fica fixada; se mudar, o app recusa
   (proteção contra alguém no meio do caminho).

### Acesso total (root)

O padrão é o mínimo: o `chaosadmin` só roda o `chaos-ctl.sh` como root. Isso já cobre o servidor do jogo. Para o
terminal do app ser root de verdade (instalar pacotes, mexer no sistema), rode na VPS, no lugar do passo 3:
`echo 'ssh-rsa AAAA...' | sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh install-admin --full -`
(a chave pública vem de **Copiar chave pública**). Quem pegar o celular desbloqueado fica com a VPS inteira.

O `install-admin` **adiciona** a chave e mantém as que já estão lá (desde 2026-10-30): o celular e o app de admin do
Windows podem ter cada um a sua chave. Rodar de novo com a mesma chave não duplica nada.

## Segurança

- A chave privada fica criptografada com uma chave do Keystore do Android. Não vai para backup da nuvem.
- O app pede a senha, PIN ou digital do celular ao abrir e depois de 1 minuto fora. Sem bloqueio de tela ele avisa.
- Captura de tela: **Config > Tela > Permitir captura de tela**, ligada por padrão (para o dono poder mostrar um erro
  num print). Desligada, o Android bloqueia prints e a miniatura na lista de apps recentes. Em qualquer caso a janela
  fica bloqueada enquanto o campo Senha de Comandos > Contas está em foco ou tem texto. A chave privada nunca aparece
  na tela.
- O app não abre porta nenhuma na VPS e nenhum painel na internet. Só SSH, com chave (sem senha).
- Para tirar o acesso: apague `/home/chaosadmin/.ssh/authorized_keys` e `/etc/sudoers.d/chaos-admin` na VPS.
- Perdeu o celular: faça isso na hora, de outro aparelho.
- Recomendado na VPS: `PasswordAuthentication no` e `PermitRootLogin no` (`tools/linux/harden_vps.sh` faz isso).

## Comandos do servidor (`chaos-ctl.sh`)

`status`, `start`, `stop`, `restart [segundos]`, `save`, `backup`, `backups`, `logs [n]`, `errors [n]`,
`gm-logs [n] [NOME]`, `metrics [--json]`, `testers start [N] [MINUTOS] [--restart SEGUNDOS] [--keystones] | stop | status | report | log [N] | cleanup [--yes]` (bots de teste, server/README.md "Tester bots"), `errors clear`, `vps [info] | upgrade | upgrade-log [N] | reboot MIN | reboot-cancel`, `services`, `service NOME start|stop|restart`, `service-log NOME [N]`, `players`, `vocations`, `broadcast TEXTO`, `kick NOME`, `open`, `close`, `catalog NOME`,
`panel NOME ACAO JSON`, `reload-files`, `reload-file NOME [CONFIG]` (uma tabela `*_config.lua` no jogo sem /reload, grupo 6), `update TAG now|at-save` e `rollback now|at-save` (layout padrão; no kit, `rollback now` é
`update-rollback`), `update-check`, `update-apply [--no-client] [--no-downloads] [--no-site] [--no-map]`, `update-status`,
`update-rollback`, `update-log`, `engine-build [status | start [--client-build N] | log [N]]` e `engine-build-token-set` (token no stdin; recompila o engine no GitHub, O436), `publish-update TAG` (atualização do cliente, docs/LAUNCH.md "Publishing a client
update"), `publish-log`, `site-install`, `site-log`, `areas-publish [--pictures] [--rotate]`, `xp-rate`, `client-pair [show | set N]`, `beta-mode [status | on | off] [restart]`, `clientservices-impl [status | rust | python]`, `health`, `cleanup [--yes]`, `account-create NOME`,
`account-password NOME`, `discord-set CANAL` (URL no stdin) | `discord-enable` | `discord-disable` | `discord-test [CANAL|all]` | `discord-status`, `discord-bot status | install | set NOME | start | stop | restart | logs [N] | patchnotes`, `pay-status`, `pay-set NOME` (valor no stdin), `pay-test`, `pay-enable`, `pay-disable`, `newplayer-funnel`, `survey`, `game-health [--days N] [--kv | --json] [--pt]`, `balance-report [--days N | --season ID|current] [--pt] [--json] [--save] [--dm] | last | auto | timer on|off|status`, `install-admin`, `spectate NOME`, `spectate-pair [status | fetch | log [N]]`. Todos com argumentos conferidos (números, nomes, tags de release), nada de
shell livre. Rode `chaos-ctl.sh help`. Aviso, expulsar, abrir, fechar e salvar passam pelo arquivo `remote.cmd`
(`server/README.md`, "Remote admin commands"): o servidor do jogo precisa estar com os scripts novos.

## Limites conhecidos

- Nada disso rodou num servidor e num celular de verdade ainda. Testados: o script (`chaos_ctl_test.py`), a
  atualização do kit (`chaos_kit_update_test.py`: repositório, releases, systemctl e banco falsos) e os comandos do
  jogo (`remote_cmd_test.lua`) com motor simulado. O app 2.1 foi compilado; as telas novas (Atualizar servidor, Taxa
  de XP, Contas, Saúde, Logs GM) não foram abertas num aparelho.
- Assistir jogador: a Foto foi testada com um motor simulado e sprites sintéticos (`spectate_test.lua`,
  `spectate_render_test.py`, `chaos_ctl_test.py`). O Ao vivo tem testes do relay com quadros sintéticos
  (`cast_relay_test.py`, agora também andares, regra do telhado, luz e efeitos de outros andares) e do motor
  (`chaoscast_test.cpp`); o motor com o patch 0064 compila. O app compila só contra o `android.jar` com o `javac` (a
  máquina de build não tem o Android SDK, então o gradle não rodou); a conta de andares e luz (`CastMath`) rodou numa
  JVM. O card não foi aberto num celular: andares, luz e a regra do telhado nunca foram vistos na tela.
- O terminal executa um comando por vez (sem programas interativos como `nano` ou `top`). Use `top -bn1` no lugar de `top`.
- O layout assumido é o de `docs/LAUNCH.md` (`/opt/chaos`, unidade `chaos-server`). Outro layout: veja abaixo.

## Outro layout na VPS (o kit em /opt/chaos-trial)

O `chaos-ctl.sh` roda pelo `sudo -n`, que apaga as variáveis de ambiente: `CHAOS_UNIT=... ` no shell não chega nele.
Os caminhos ficam em `/etc/chaos/ctl.conf` (dono root, sem escrita para grupo e outros; só linhas `CHAVE=valor`, nunca
executado). Para o kit Linux em `/opt/chaos-trial`, como root:

    cp server/deploy/chaos-trial-server.service /etc/systemd/system/chaos-server.service
    # deixe User=chaos e Group=chaos (nunca o dono de /opt/chaos-trial: se o root extraiu o kit, o jogo rodaria como root).
    # Depois, no app: Comandos > Ações rápidas > Servidor como usuário chaos > Corrigir (cria o usuário e passa as pastas)
    /opt/chaos-trial/stop-server.sh        # se ele estiver rodando à mão
    systemctl daemon-reload && systemctl enable --now chaos-server
    mkdir -p /etc/chaos && cp server/deploy/ctl.conf.trial.example /etc/chaos/ctl.conf && chmod 644 /etc/chaos/ctl.conf

O exemplo aponta o log, o `chaos.env` do kit (banco na porta 3307), o pid do motor (salvar e backup mandam o sinal só
para ele) e o cliente do banco do kit (`/opt/chaos-trial/mariadb/bin/mariadb`; a VPS não tem `mysql`). Detalhes:
`server/README.md`, "Remote admin commands".
