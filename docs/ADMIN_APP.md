# Cinders Admin: o app Android do servidor

Controla a VPS pelo celular. Nada fica aberto na internet: o app fala SSH com a sua VPS, com uma chave que nasce e fica
só no celular. Código em `android/`, parte do servidor em `server/deploy/chaos-ctl.sh`.

## O que o app faz

Visual escuro com dourado e brasa, nas cores do jogo e do site. Quatro abas embaixo:

| Aba | Para quê |
|---|---|
| Painel | Estado do servidor com selo colorido (no ar, parado, falhou, ligando, sem serviço), há quanto tempo está no ar, jogadores (toque: quem está online, com a classe), erros desde o último início (toque: abre os erros), memória e disco com barra, carga, último backup. Puxe para baixo para atualizar; atualiza sozinho a cada 30 s (muda em Config). Botões grandes: Ligar, Desligar, Salvar, Reiniciar, Reiniciar em… (1 a 15 min, com aviso aos jogadores), Backup. Os perigosos pedem confirmação; a resposta aparece num cartão, em português, com os detalhes escondidos. Cartão **Atualizar servidor** (abaixo) |
| Comandos | Ações rápidas: aviso para todos, expulsar, abrir e fechar o login, versão por tag (layout padrão), **Taxa de XP**, **Contas** (criar, trocar senha), **Saúde e espaço** (verificar, limpar sobras, ver backups), **Testers** (iniciar, parar, status, relatório, log das ações, apagar), **Site e update do client** (reinstalar o site, publicar o update de uma release). Painel do jogo: todos os comandos do painel de admin, por categoria, com busca e formulário (Chaos Coins: Store > Give Chaos Coins; grupo/GM: Players > Set group) |
| Logs | Console, Erros, Updates (servidor, publicação do client, instalação do site), GM e Terminal. GM: os logs de comando do staff (`data/logs/<nome> commands.log`, mais novo primeiro) e o registro do painel de admin (tabela `chaos_admin_log`), de todos ou de um membro do staff. Fonte monoespaçada, 50 a 500 linhas, Acompanhar (recarrega a cada 5 s), copiar. Erros: só desde o último início do servidor, linhas iguais juntas com a contagem (×56); "Incluir inícios anteriores" mostra os antigos, cada um com a data do início. Terminal: qualquer comando na VPS, a pasta é guardada, botão `sudo -n` |
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
| 5 instalar | guarda as taxas de XP, checkout do ramo, para o servidor, troca o `tfs` (o antigo fica `tfs.antes-N`), troca o mapa pelo mapa mestre novo (o antigo fica em `$KIT/map-backups/<mapa>.otbm.<data-hora>`, os 3 mais novos), `install_all.py --no-sql`, devolve as taxas, dono da pasta = usuário da unidade |
| 6 banco | liga o servidor (o MariaDB do kit roda dentro da unidade), espera o banco, `install_all.py --only sql`, reinicia (o motor sobe com as tabelas novas) |
| 7 conferir | unidade ativa e "Server Online" no log em até 15 min. Falhou nos passos 5 a 7: volta sozinho (engine, `config.lua` e `data/` do backup, o mapa do `map-backups`, commit anterior), liga e confere de novo |
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
- **Contas** (`account-create NOME`, `account-password NOME`): a senha vai pela entrada do comando (stdin do SSH),
  nunca na linha de comando nem em log, e vira hash PBKDF2 como o site grava. O personagem se cria no client ou no site.
- **Saúde e espaço** (`health`, `cleanup [--yes]`, `backups`): servidor, banco, serviços web (nginx, apache, php-fpm),
  disco e memória. Limpar mostra a lista e pede confirmação antes de apagar: pastas de trabalho de atualizações e
  publicações em `/var/tmp` com mais de um dia, pastas `srvNN` lá, `tfs.antes-*` além dos 2 mais novos,
  `config.lua.before-*` além dos 5 mais novos. Backups: lista os dumps e arquivos; restaurar continua sendo pela VPS.
- **Testers** (`testers start N MINUTOS --restart 300`, `testers stop`, `testers status`, `testers report`, `testers log 400`, `testers cleanup --yes`): os
  testers no servidor ao vivo (server/README.md "Tester bots"). Iniciar reinicia o servidor com 5 minutos de aviso
  só quando o ajudante de teste ainda não carregou. A chave fica em /etc/chaos/tester-client-key (criada pela VPS).
  Status mostra quantos testers estão online agora, o pico da rodada e a contagem do servidor.
- **Site e update do client** (`site-install`, `site-log`, `publish-update TAG`, `publish-log`).
- **Logs de GM** (aba Logs, GM; `gm-logs [N] [NOME]`).

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
- Sem captura de tela e sem miniatura na lista de apps recentes.
- O app não abre porta nenhuma na VPS e nenhum painel na internet. Só SSH, com chave (sem senha).
- Para tirar o acesso: apague `/home/chaosadmin/.ssh/authorized_keys` e `/etc/sudoers.d/chaos-admin` na VPS.
- Perdeu o celular: faça isso na hora, de outro aparelho.
- Recomendado na VPS: `PasswordAuthentication no` e `PermitRootLogin no` (`tools/linux/harden_vps.sh` faz isso).

## Comandos do servidor (`chaos-ctl.sh`)

`status`, `start`, `stop`, `restart [segundos]`, `save`, `backup`, `backups`, `logs [n]`, `errors [n]`,
`gm-logs [n] [NOME]`, `testers start [N] [MINUTOS] [--restart SEGUNDOS] | stop | status | report | cleanup [--yes]` (bots de teste, server/README.md "Tester bots"), `players`, `vocations`, `broadcast TEXTO`, `kick NOME`, `open`, `close`, `catalog NOME`,
`panel NOME ACAO JSON`, `update TAG now|at-save` e `rollback now|at-save` (layout padrão; no kit, `rollback now` é
`update-rollback`), `update-check`, `update-apply [--no-client] [--no-downloads] [--no-site] [--no-map]`, `update-status`,
`update-rollback`, `update-log`, `publish-update TAG` (atualização do cliente, docs/LAUNCH.md "Publishing a client
update"), `publish-log`, `site-install`, `site-log`, `xp-rate`, `health`, `cleanup [--yes]`, `account-create NOME`,
`account-password NOME`, `install-admin`. Todos com argumentos conferidos (números, nomes, tags de release), nada de
shell livre. Rode `chaos-ctl.sh help`. Aviso, expulsar, abrir, fechar e salvar passam pelo arquivo `remote.cmd`
(`server/README.md`, "Remote admin commands"): o servidor do jogo precisa estar com os scripts novos.

## Limites conhecidos

- Nada disso rodou num servidor e num celular de verdade ainda. Testados: o script (`chaos_ctl_test.py`), a
  atualização do kit (`chaos_kit_update_test.py`: repositório, releases, systemctl e banco falsos) e os comandos do
  jogo (`remote_cmd_test.lua`) com motor simulado. O app 2.1 foi compilado; as telas novas (Atualizar servidor, Taxa
  de XP, Contas, Saúde, Logs GM) não foram abertas num aparelho.
- O terminal executa um comando por vez (sem programas interativos como `nano` ou `top`). Use `top -bn1` no lugar de `top`.
- O layout assumido é o de `docs/LAUNCH.md` (`/opt/chaos`, unidade `chaos-server`). Outro layout: veja abaixo.

## Outro layout na VPS (o kit em /opt/chaos-trial)

O `chaos-ctl.sh` roda pelo `sudo -n`, que apaga as variáveis de ambiente: `CHAOS_UNIT=... ` no shell não chega nele.
Os caminhos ficam em `/etc/chaos/ctl.conf` (dono root, sem escrita para grupo e outros; só linhas `CHAVE=valor`, nunca
executado). Para o kit Linux em `/opt/chaos-trial`, como root:

    cp server/deploy/chaos-trial-server.service /etc/systemd/system/chaos-server.service
    # troque User= e Group= pelo dono de /opt/chaos-trial (stat -c '%U %G' /opt/chaos-trial)
    /opt/chaos-trial/stop-server.sh        # se ele estiver rodando à mão
    systemctl daemon-reload && systemctl enable --now chaos-server
    mkdir -p /etc/chaos && cp server/deploy/ctl.conf.trial.example /etc/chaos/ctl.conf && chmod 644 /etc/chaos/ctl.conf

O exemplo aponta o log, o `chaos.env` do kit (banco na porta 3307), o pid do motor (salvar e backup mandam o sinal só
para ele) e o cliente do banco do kit (`/opt/chaos-trial/mariadb/bin/mariadb`; a VPS não tem `mysql`). Detalhes:
`server/README.md`, "Remote admin commands".
