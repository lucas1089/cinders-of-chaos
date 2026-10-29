# Cinders Admin: o app Android do servidor

Controla a VPS pelo celular. Nada fica aberto na internet: o app fala SSH com a sua VPS, com uma chave que nasce e fica
só no celular. Código em `android/`, parte do servidor em `server/deploy/chaos-ctl.sh`.

## O que o app faz

Visual escuro com dourado e brasa, nas cores do jogo e do site. Quatro abas embaixo:

| Aba | Para quê |
|---|---|
| Painel | Estado do servidor com selo colorido (no ar, parado, falhou, ligando, sem serviço), há quanto tempo está no ar, jogadores (toque: quem está online, com a classe), erros desde o último início (toque: abre os erros), memória e disco com barra, carga, último backup. Puxe para baixo para atualizar; atualiza sozinho a cada 30 s (muda em Config). Botões grandes: Ligar, Desligar, Salvar, Reiniciar, Reiniciar em… (1 a 15 min, com aviso aos jogadores), Backup. Os perigosos pedem confirmação; a resposta aparece num cartão, em português, com os detalhes escondidos e os botões **Copiar** e **Compartilhar** (uma resposta grande, como o log dos testers, vai como arquivo .txt para salvar ou anexar). Cartão **Atualizar servidor** (abaixo) |
| Comandos | Ações rápidas: aviso para todos, expulsar, abrir e fechar o login, versão por tag (layout padrão), **Taxa de XP**, **Par do cliente**, **Contas** (criar, trocar senha), **Saúde e espaço** (verificar, limpar sobras, ver backups), **Servidor como usuário chaos** (Ver, Corrigir, Corrigir e reiniciar, Log do reinício), **Testers** (iniciar, parar, status, relatório, log das ações, apagar), **Site e update do client** (reinstalar o site, publicar o update de uma release). Painel do jogo: todos os comandos do painel de admin, por categoria, com busca e formulário (Chaos Coins: Store > Give Chaos Coins; grupo/GM: Players > Set group) |
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
  Ações rápidas > cartão Bot do Discord (bugs e patch notes); no desktop, aba Comandos > grupo Bot do Discord): lê o canal de
  bugs com o Claude, avisa por DM os bugs críticos e ajuda a escrever os patch notes. Instalar cria o usuário `chaosbot`, o
  virtualenv com as versões fixas e o `chaos-discordbot.service`; Salvar grava um valor em `/etc/chaos/discord-bot.env` (modo
  600): o token e a chave da API vão pela entrada do comando, nunca na linha de comando nem em log, e o app não os mostra de
  volta. Iniciar recusa com `config-missing` e os nomes que faltam. Levar patch notes ao jogo copia os arquivos novos para
  `data/patchnotes`. Passo a passo para o dono: `server/deploy/discord_bot/README.md`. O app precisa ser recompilado para ter o cartão.
- **Saúde e espaço** (`health`, `cleanup [--yes]`, `backups`): servidor, banco, serviços web (nginx, apache, php-fpm),
  disco e memória. Limpar mostra a lista e pede confirmação antes de apagar: pastas de trabalho de atualizações e
  publicações em `/var/tmp` com mais de um dia, pastas `srvNN` lá, `tfs.antes-*` além dos 2 mais novos,
  `config.lua.before-*` além dos 5 mais novos. Backups: lista os dumps e arquivos; restaurar continua sendo pela VPS.
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
- **Site e update do client** (`site-install`, `site-log`, `publish-update TAG`, `publish-log`). "Trocar os downloads do site" (`update-downloads`, O165) põe o pacote completo mais novo (Windows e Linux) na pasta `dl/` do site sem reiniciar o servidor; "Log da atualização" mostra o andamento. `publish-update` publica só a atualização assinada, não os pacotes.
- **Mapas pedidos** (`areas-publish [--pictures] [--rotate]`, O192; Comandos > card "Mapas pedidos"). "Publicar áreas" monta, a partir das áreas pendentes e aprovadas da pasta `server/tools/areaplan/inbox/` do repositório na VPS (traga com Painel > Atualizar servidor depois de unir na main), os arquivos do editor de mapas em `dl/areas-TOKEN/` do site e mostra a linha `url=`; copie-a (botão de copiar do resultado) e rode `fetch-areas.bat` no Windows. "Novo endereço" (`--rotate`) cria outro TOKEN e apaga a pasta antiga. O site não tem login para arquivos estáticos: o TOKEN (32 dígitos hexa, `/var/lib/chaos/areas/token`) é a proteção. Não reinicia nem altera o mapa do jogo. docs/MAP_GUIDE.md "Map inbox".
- **Logs de GM** (aba Logs, GM; `gm-logs [N] [NOME]`).
- **Métricas dos jogadores** (aba Painel, card "Métricas dos jogadores", botão "Atualizar métricas"; `metrics [--json]`, O253). Só
  leitura. Mostra por faixa de nível quantos personagens pararam de jogar (sem login há 14 dias ou mais), as 10 áreas e os 10
  monstros com mais mortes, a duração da primeira sessão de personagens novos e o tempo mediano jogado até os níveis 10, 25,
  50, 100 e 200. São contadores anônimos (sem nomes, contas nem IPs; testers e GMs ficam de fora), lidos da tabela
  `chaos_progress_metrics`; server/README.md "Progress metrics (O253)". Precisa do passo `sql` do `install_all.py` (ou o
  servidor cria a tabela ao ligar) e de um app recompilado para o card; o comando funciona pelo SSH sem isso.
  O258: o card "Funil dos jogadores" (logo abaixo, preenchido pelo mesmo botão) mostra a volta dos personagens novos nos dias 1, 3 e 7 por semana de entrada, quando cada sistema (masmorra, fenda, torre, mercado, guilda...) é usado pela primeira vez e as áreas onde ficaram os personagens que pararam; níveis até 2000 entram no tempo mediano. server/README.md "Funnel metrics (O258)".
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
`panel NOME ACAO JSON`, `update TAG now|at-save` e `rollback now|at-save` (layout padrão; no kit, `rollback now` é
`update-rollback`), `update-check`, `update-apply [--no-client] [--no-downloads] [--no-site] [--no-map]`, `update-status`,
`update-rollback`, `update-log`, `publish-update TAG` (atualização do cliente, docs/LAUNCH.md "Publishing a client
update"), `publish-log`, `site-install`, `site-log`, `areas-publish [--pictures] [--rotate]`, `xp-rate`, `client-pair [show | set N]`, `beta-mode [status | on | off] [restart]`, `clientservices-impl [status | rust | python]`, `health`, `cleanup [--yes]`, `account-create NOME`,
`account-password NOME`, `discord-set CANAL` (URL no stdin) | `discord-enable` | `discord-disable` | `discord-test [CANAL|all]` | `discord-status`, `discord-bot status | install | set NOME | start | stop | restart | logs [N] | patchnotes`, `install-admin`, `spectate NOME`, `spectate-pair [status | fetch | log [N]]`. Todos com argumentos conferidos (números, nomes, tags de release), nada de
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
