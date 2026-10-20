# Cinders Admin: o app Android do servidor

Controla a VPS pelo celular. Nada fica aberto na internet: o app fala SSH com a sua VPS, com uma chave que nasce e fica
só no celular. Código em `android/`, parte do servidor em `server/deploy/chaos-ctl.sh`.

## O que o app faz

| Aba | Para quê |
|---|---|
| Painel | No ar ou fora, desde quando, jogadores, carga, memória, disco, último backup, erros Lua. Ligar, desligar, reiniciar, salvar, backup, logs, erros, jogadores online |
| Admin | Aviso para todos, expulsar personagem, fechar e abrir o login, reinício com contagem, atualizar para uma versão (agora ou no save diário), ver o andamento, voltar a versão |
| Terminal | Qualquer comando na VPS, a pasta atual é guardada entre comandos. Botão `sudo -n` |
| Config | Endereço, porta, usuário, gerar chave, copiar o comando de instalação, testar a conexão |

Banir, dar itens, premium e o resto continuam no painel de admin dentro do jogo e no terminal do app.

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
`broadcast TEXTO`, `kick NOME`, `open`, `close`, `update TAG now|at-save`, `rollback now|at-save`, `update-log`,
`install-admin`. Rode `chaos-ctl.sh help`. Aviso, expulsar, abrir, fechar e salvar passam pelo arquivo `remote.cmd`
(`server/README.md`, "Remote admin commands"): o servidor do jogo precisa estar com os scripts novos.

## Limites conhecidos

- Nada disso rodou num servidor e num celular de verdade ainda. Testados: o script (`chaos_ctl_test.py`) e os comandos
  do jogo (`remote_cmd_test.lua`) com motor simulado. O app foi compilado pelo workflow, não aberto num aparelho.
- O terminal executa um comando por vez (sem programas interativos como `nano` ou `top`). Use `top -bn1` no lugar de `top`.
- O layout assumido é o de `docs/LAUNCH.md` (`/opt/chaos`, unidade `chaos-server`). Outro layout: variáveis `CHAOS_*` no
  topo do `chaos-ctl.sh`.
