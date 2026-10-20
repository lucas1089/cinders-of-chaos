# Cinders Admin: o app Android do servidor

Controla a VPS pelo celular. Nada fica aberto na internet: o app fala SSH com a sua VPS, com uma chave que nasce e fica
só no celular. Código em `android/`, parte do servidor em `server/deploy/chaos-ctl.sh`.

## O que o app faz

Visual escuro com dourado e brasa, nas cores do jogo e do site. Quatro abas embaixo:

| Aba | Para quê |
|---|---|
| Painel | Estado do servidor com selo colorido (no ar, parado, falhou, ligando, sem serviço), há quanto tempo está no ar, jogadores (toque: quem está online, com a classe), erros desde o último início (toque: abre os erros), memória e disco com barra, carga, último backup. Puxe para baixo para atualizar; atualiza sozinho a cada 30 s (muda em Config). Botões grandes: Ligar, Desligar, Salvar, Reiniciar, Reiniciar em… (1 a 15 min, com aviso aos jogadores), Backup. Os perigosos pedem confirmação; a resposta aparece num cartão, em português, com os detalhes escondidos |
| Comandos | Ações rápidas: aviso para todos, expulsar, abrir e fechar o login, atualizar a versão (agora ou no save diário), ver o andamento, voltar a versão. Painel do jogo: todos os comandos do painel de admin, por categoria, com busca e formulário |
| Logs | Console, Erros, Atualização e Terminal. Fonte monoespaçada, 50 a 500 linhas, Acompanhar (recarrega a cada 5 s), copiar. Erros: só desde o último início do servidor, linhas iguais juntas com a contagem (×56); "Incluir inícios anteriores" mostra os antigos, cada um com a data do início. Terminal: qualquer comando na VPS, a pasta é guardada, botão `sudo -n` |
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

`status`, `start`, `stop`, `restart [segundos]`, `save`, `backup`, `logs [n]`, `errors [n]`, `players`,
`broadcast TEXTO`, `kick NOME`, `open`, `close`, `catalog NOME`, `panel NOME ACAO JSON`, `update TAG now|at-save`, `rollback now|at-save`, `update-log`,
`install-admin`. Rode `chaos-ctl.sh help`. Aviso, expulsar, abrir, fechar e salvar passam pelo arquivo `remote.cmd`
(`server/README.md`, "Remote admin commands"): o servidor do jogo precisa estar com os scripts novos.

## Limites conhecidos

- Nada disso rodou num servidor e num celular de verdade ainda. Testados: o script (`chaos_ctl_test.py`) e os comandos
  do jogo (`remote_cmd_test.lua`) com motor simulado. O app 2.0 (visual novo) foi compilado e as quatro abas abertas
  num Android simulado (Robolectric, fora do repositório), não num aparelho de verdade.
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
