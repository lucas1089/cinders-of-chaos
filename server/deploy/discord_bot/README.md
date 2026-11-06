# Bot do Discord: bugs e patch notes

Um bot para o seu servidor do Discord. Ele lê o canal de bugs, usa o Claude para separar bug de conversa, junta relatos repetidos, avisa você quando o bug é crítico e ajuda a escrever os patch notes. Roda na VPS do jogo como serviço do systemd. Chama-se `chaos-discordbot`.

Código: `bot.py` é a camada fina do Discord. As regras estão em `bot_core.py` e as chamadas ao Claude em `claude_client.py`. `changes_export.py` roda como root e lê as mudanças do jogo no repositório (seção 5). Os testes são `bot_core_test.py` e `claude_client_test.py`.

## O que ele faz

No canal de bugs o bot lê toda mensagem, inclusive prints anexados. O Claude vê as imagens.

| Caso | O que o bot faz |
|---|---|
| Bug novo | Reage com 🐞 e responde ao jogador com o número do bug |
| Bug repetido | Reage com 🔁 e soma o relato ao bug que já existe. O mesmo jogador conta uma vez só |
| Bug crítico | Manda DM para você na hora. Vale para crash, exploit e perda de item |
| Sugestão ou conversa | Não faz nada. O bot fica em silêncio |

Ao iniciar, o bot lê o que foi postado no canal de bugs enquanto ele estava desligado. Lê até 48 horas para trás e até
100 mensagens por canal ou post do fórum. O que ele já respondeu fica de fora. Os **Logs** mostram
`catch-up: N message(s) read`.

Todo dia às 09:00 de São Paulo você recebe um resumo por DM.

O bot também entrega por DM os relatórios do servidor. Hoje: o relatório de equilíbrio da season (Painel > Relatório de
equilíbrio > Enviar por DM, e o automático no fim de cada season). Textos longos chegam em várias mensagens.

Comandos. Só você e quem tem o cargo de admin, se você definir um, conseguem usar. As respostas são só suas.

| Comando | Para quê |
|---|---|
| `/bugs lista [status]` | Lista por gravidade e número de relatos |
| `/bugs ver id` | Detalhes de um bug |
| `/bugs status id novo_status [duplicado_de] [nota]` | Muda o status: aberto, confirmado, em andamento, corrigido, não é bug, duplicado |
| `/bugs exportar [incluir_fechados]` | Baixa um arquivo Markdown |
| `/bugs resumo` | O Claude sugere prioridades e bugs que provavelmente têm a mesma causa |
| `/patch gerar versao [extras]` | Escreve os patch notes com as mudanças do jogo desde o último patch, os bugs corrigidos e os extras. Mostra a prévia com Publicar, Editar e Cancelar |
| `/patch escrever [versao]` | Abre um formulário para escrever à mão, com prévia |

Regras de status. Um bug corrigido só volta para aberto ou confirmado. Duplicado pede o número do bug original, e os relatos vão para ele. Um bug entra em um `/patch gerar` uma vez só.

No formulário do patch, escreva um item por linha. `Destaque :: texto` dá um destaque em negrito ao item.

## 1. Criar o app no Discord

1. Abra https://discord.com/developers/applications e clique em **New Application**. Dê um nome, por exemplo "Cinders Bugs".
2. Aba **Bot**. Clique em **Reset Token** e copie o token. Ele só aparece uma vez. O token é uma senha: quem o tem controla o bot.
3. Ainda na aba **Bot**, ligue **Message Content Intent**. Sem isso o bot não lê o texto das mensagens.
4. Deixe **Public Bot** desligado. Assim só você convida o bot.
5. Aba **General Information**. Copie o **Application ID**.
6. Convide o bot para o seu servidor abrindo este endereço, com o Application ID no lugar de `SEU_APPLICATION_ID`:

```
https://discord.com/oauth2/authorize?client_id=SEU_APPLICATION_ID&permissions=274878024768&scope=bot%20applications.commands
```

Os escopos são `bot` e `applications.commands`. O número 274878024768 são estas permissões: Ver Canais, Enviar Mensagens, Enviar Mensagens em Threads (respostas nos posts de um canal de fórum), Inserir Links, Anexar Arquivos, Ver Histórico de Mensagens e Adicionar Reações. O canal de bugs pode ser um canal de texto ou de fórum: num fórum o bot lê o título e o texto do post.

7. No canal de bugs e no canal de patch notes, confira que o cargo do bot pode ver o canal, enviar mensagens, ver o histórico e adicionar reações. No canal de patch notes ele também precisa de Inserir Links.
8. Para receber DM do bot, você precisa estar no mesmo servidor e deixar ligada a opção "Permitir mensagens diretas de membros do servidor" nas configurações de privacidade do servidor.

## 2. Pegar os ids

1. No Discord: Configurações de usuário, Avançado, ligue **Modo desenvolvedor**.
2. Clique com o botão direito no seu nome e em **Copiar ID do usuário**. É o `DISCORD_OWNER_ID`.
3. Botão direito no canal de bugs, **Copiar ID do canal**. É o `DISCORD_BUGS_CHANNEL_ID`.
4. Botão direito no canal de patch notes. É o `DISCORD_PATCH_CHANNEL_ID`.
5. Botão direito no ícone do servidor, **Copiar ID do servidor**. É o `DISCORD_GUILD_ID`. É opcional, mas sem ele os comandos `/bugs` e `/patch` podem levar até uma hora para aparecer.
6. Opcional: o id de um cargo de admin, `DISCORD_ADMIN_ROLE_ID`. Quem tem o cargo também usa os comandos.

## 3. Chave da API da Anthropic

1. Entre em https://console.anthropic.com e crie uma conta de API. Ela é separada da assinatura do Claude.
2. Em **Billing** coloque crédito e, se quiser, um limite de gasto mensal.
3. Em **API keys** crie uma chave e copie. Começa com `sk-ant-`.

O bot usa o modelo `claude-sonnet-5-5`. Para trocar, salve `DISCORD_BOT_MODEL`.

## 4. Instalar na VPS

Pré-requisitos. A VPS tem o repositório em `/opt/chaos/repo`, o mesmo que o app usa em Atualizar servidor. O `install` instala o `python3-venv` sozinho com o `apt-get` quando falta (desde 2026-10-30). Se o `apt-get` falhar, rode `sudo apt-get install python3-venv`.

### Pelo app de admin

No app Android: aba **Comandos**, cartão **Bot do Discord (bugs e patch notes)**. No app de desktop: aba **Comandos**, grupo **Bot do Discord**.

1. Botão **Instalar ou atualizar**. Leva alguns minutos. Cria o usuário `chaosbot`, o ambiente Python e o serviço.
2. Cole cada valor no campo e toque em **Salvar**. São cinco obrigatórios: token, chave da Anthropic, seu id, canal de bugs e canal de patch notes. O id do servidor é recomendado. Os valores vão pelo SSH para `/etc/chaos/discord-bot.env`, modo 600, e o app não os mostra de volta. No desktop use **Guardar ajuste**.
3. Botão **Iniciar**. Se faltar algum valor, o app diz o nome do que falta.
4. **Estado** mostra se o serviço está ativo e quais valores existem, sem mostrar nenhum. **Logs** mostra as últimas linhas, com tokens e chaves cobertos. **Reiniciar** e **Parar** fazem o que dizem.

O **Atualizar servidor** já atualiza o bot no fim, quando ele está instalado. Ele copia o código novo e reinicia o bot se estiver ligado. Para atualizar só o bot, toque em **Instalar ou atualizar** de novo.

### Pelo terminal

Só se o app não puder. Use o `chaos-ctl.sh` da VPS.

```
CTL=/opt/chaos/repo/server/deploy/chaos-ctl.sh
sudo $CTL discord-bot install
read -rs V; printf '%s\n' "$V" | sudo $CTL discord-bot set DISCORD_TOKEN; unset V
read -rs V; printf '%s\n' "$V" | sudo $CTL discord-bot set ANTHROPIC_API_KEY; unset V
read -r V; printf '%s\n' "$V" | sudo $CTL discord-bot set DISCORD_OWNER_ID; unset V
```

Repita o `set` para `DISCORD_BUGS_CHANNEL_ID`, `DISCORD_PATCH_CHANNEL_ID` e `DISCORD_GUILD_ID`. Depois:

```
sudo $CTL discord-bot start
sudo $CTL discord-bot status
sudo $CTL discord-bot logs 80
```

O `read -rs` não deixa a senha no histórico do shell. O arquivo de ajustes é `/etc/chaos/discord-bot.env`. Dá para editar à mão com `sudoedit`, a partir do modelo `.env.example`, e depois rodar `restart`.

### O que a instalação faz

- Cria o usuário de sistema `chaosbot`, sem login e sem acesso aos arquivos do jogo.
- Copia o código para `/opt/chaos/discord-bot/app` e cria o ambiente em `/opt/chaos/discord-bot/venv` com as versões fixas de `requirements.txt`. O arquivo vale do Python 3.10 ao 3.13: as linhas com `; python_full_version` escolhem a versão certa para o Python da VPS (gerado com `uv pip compile --universal --python-version 3.10`; o `audioop-lts` só entra no 3.13).
- Cria `/etc/chaos/discord-bot.env`, modo 600, dono root. O systemd lê o arquivo antes de baixar os privilégios.
- Instala `chaos-discordbot.service` com as proteções de sandbox dos outros serviços. O bot só escreve em `/var/lib/chaos/discord-bot`.
- Instala e liga `chaos-discordbot-sync.timer`, de 5 em 5 minutos, como root. Ele grava as mudanças do jogo para o bot e leva os patch notes publicados para o jogo (seção 5). Log: `/var/log/chaos/discord-bot-sync.log`.
- Roda de novo sem estragar nada.

## 5. Patch notes no site e no jogo

### De onde vêm as mudanças

O bot puxa sozinho as mudanças do jogo. A cada 5 minutos o `chaos-discordbot-sync.timer` lê o histórico do git do repositório da VPS (`/opt/chaos/repo`) e grava `/var/lib/chaos/discord-bot/changes.json`. Só regrava quando o repositório mudou, ou seja, depois de um **Atualizar servidor**.

Entram só commits do que o jogador recebe: dados do servidor, patches do motor, SQL, passos de instalação, cliente e site. Ficam de fora docs, testes, CI, ferramentas, o app de admin e o próprio bot. Commits de merge também. Assuntos que parecem internos ou privados (endereço, caminho, chave) caem fora inteiros. O texto do commit vai sem caminhos de arquivo e sem ids como O123. São no máximo 120 dias e 400 commits.

O `/patch gerar` usa as mudanças que nenhum patch publicado cobriu ainda. No primeiro patch, as dos últimos 14 dias, no máximo 60. O Claude transforma as mensagens dos commits em notas para o jogador, em português e inglês, agrupadas por tema. Nada de hash, caminho, id interno ou jargão. A entrada vai até 12 mil caracteres, as mais novas primeiro; a prévia diz quantas entraram, desde quando e quantas ficaram de fora. Se não há mudança nova, nem bug corrigido, nem extras, o bot diz "Nada novo desde DD/MM/AAAA". Se o Claude não acha nada que o jogador note, ele avisa e não monta patch.

Ao publicar, o bot marca essas mudanças como cobertas. O próximo patch começa depois delas. Um `/patch escrever` publicado também conta.

### Patch automático depois de cada atualização

Você não precisa rodar nada. Quando o `changes.json` muda e tem mudança nova para o jogador, o bot escreve o patch sozinho. A versão é a data, `AAAA-MM-DD`. Os bugs corrigidos sem patch entram junto. Três modos, no ajuste `DISCORD_BOT_PATCH_AUTO`:

| Modo | O que acontece |
|---|---|
| `preview` | O bot manda a prévia por DM, com Publicar, Editar e Cancelar. Os botões continuam valendo depois de reiniciar o bot. Uma prévia nova substitui a anterior |
| `publish` (padrão) | O bot publica direto no canal de patch notes, grava os arquivos do site e manda uma DM curta com o link do canal. Todas as vezes, a primeira também |
| `off` | Só com `/patch gerar` |

Se o Claude disser que nada muda para o jogador, o bot não manda nada e escreve uma linha nos **Logs**. O mesmo conjunto de mudanças nunca vira dois patches: o bot guarda o último estado do repositório que já tratou. Se a prévia ficou velha porque outro patch saiu antes, o Publicar dela recusa e manda usar `/patch gerar`.

Para escolher o modo, uma vez só. No app Android: **Comandos** > **Bot do Discord** > botões **Prévia**, **Publicar** ou **Desligado**. No app de desktop: **Comandos** > **Bot do Discord** > **Guardar ajuste**, ajuste `DISCORD_BOT_PATCH_AUTO`, valor `preview`, `publish` ou `off`. O bot reinicia sozinho com o ajuste novo. Pelo terminal, só se o app não puder: `printf 'publish\n' | sudo $CTL discord-bot set DISCORD_BOT_PATCH_AUTO`.

Bot instalado antes de 2026-11-03? Toque uma vez em **Instalar ou atualizar** para ganhar o timer.

### Os arquivos

O `/patch gerar`, o `/patch escrever` e o patch automático publicam o embed no canal de patch notes. O bot também grava dois arquivos no formato que o jogo e o site já leem:

- `/var/lib/chaos/discord-bot/patchnotes/AAAA-MM-DD.md`, em inglês
- `/var/lib/chaos/discord-bot/patchnotes/AAAA-MM-DD.pt-br.md`, em português

O Claude escreve as duas versões juntas. Se você edita ou escreve à mão, ele traduz para o inglês na hora de publicar. Se o dia já tem um arquivo, o novo vira `AAAA-MM-DD-2` e nada é sobrescrito.

O timer leva os arquivos novos para `data/patchnotes` do servidor em até 5 minutos. Nada é sobrescrito. O jogo lista essa pasta a cada minuto no máximo. Para levar agora: **Levar patch notes ao jogo** no app, ou `sudo $CTL discord-bot patchnotes`. Esse botão também atualiza as mudanças do jogo na hora. Depois copie os arquivos para `server/data/patchnotes` no repositório e faça o commit. Se um update trocar a pasta do servidor, o timer copia de novo os que faltarem.

**Estado** mostra `patch_auto`, `sync_timer` e a hora do `changes_file`.

## 6. Dados e privacidade

- O banco é um arquivo SQLite: `/var/lib/chaos/discord-bot/bugs.sqlite3`, modo 600. Inclua esse arquivo no seu backup.
- O texto das mensagens dos jogadores não é guardado. O bot guarda o título, o resumo e os passos que o Claude escreveu, o id do autor, o id da mensagem e o link dela.
- Os logs têm só ids e contadores. Nunca o texto de uma mensagem, o token ou a chave.
- O texto de cada mensagem do canal de bugs e seus prints vão para a API da Anthropic. Avise isso na política de privacidade e no topo do canal de bugs.
- Um jogador gera no máximo 20 chamadas ao Claude por hora. Muda com `DISCORD_BOT_USER_LIMIT_HOUR`.
- O bot nunca menciona ninguém além do autor da mensagem que ele responde. `@everyone` e menções vindas do Claude são neutralizadas.

## 7. Custo por mês

Estimativa. Confira no console da Anthropic nas primeiras semanas.

O `claude-sonnet-5-5` custa US$ 2 por milhão de tokens de entrada e US$ 10 por milhão de saída. Uma mensagem do canal de bugs leva a instrução, até 60 bugs abertos para achar duplicados e a mensagem. Dá de 1.000 a 4.000 tokens de entrada e uns 600 de saída. Isso custa de US$ 0,01 a US$ 0,02 por mensagem. Cada print soma uns 1.500 tokens de entrada, cerca de US$ 0,003.

| Mensagens por dia no canal | Por mês |
|---|---|
| 10 | US$ 3 a 6 |
| 50 | US$ 15 a 30 |
| 200 | US$ 60 a 120 |

Mensagens curtas demais e sem print não chamam o Claude. Cada `/patch gerar` e `/bugs resumo` custa uns US$ 0,03. O resumo diário não usa o Claude. Para gastar menos, troque o modelo por um menor em `DISCORD_BOT_MODEL` e ponha um limite de gasto no console.

## 8. Problemas comuns

| Sintoma | O que fazer |
|---|---|
| O bot está online e ignora as mensagens | Veja **Logs** logo depois de **Reiniciar**. Ao iniciar, o bot confere os dois canais e escreve uma linha por canal: `bugs channel ...9494: text, ok` ou o que falta. Se algo falta, ele também manda DM. Confira também **Message Content Intent** na aba Bot. Uma linha `message in channel X ignored: the bugs channel is Y` quer dizer que o id salvo não é o do canal: salve X em `DISCORD_BUGS_CHANNEL_ID`. Sem nenhuma linha `ready as bot id` o bot nem conectou: veja o erro logo acima |
| Salvei um ajuste e nada mudou | Desde 2026-11-03, **Guardar ajuste** reinicia o bot sozinho quando ele está rodando. Antes era preciso clicar em **Reiniciar** |
| Os comandos não aparecem | Salve `DISCORD_GUILD_ID`, reinicie e confira o convite com `applications.commands`. Sem o id do servidor pode levar uma hora |
| `403 Forbidden (error code: 50001): Missing Access` ao iniciar | O bot não está no servidor de `DISCORD_GUILD_ID`, ou foi convidado sem `applications.commands`, ou o id não é de servidor. Convide de novo com o link da seção 1 (pode convidar por cima). Para o id: modo desenvolvedor ligado, clique direito no nome do servidor > Copiar ID do servidor, e salve com **Guardar ajuste**. Depois **Reiniciar**. Desde 2026-10-31 o bot segue rodando sem os comandos e explica isso nos **Logs** |
| "Integration requires code grant" ao abrir o link de convite | Na aba **Bot**, desligue **Requires OAuth2 Code Grant**, salve e abra o link de novo |
| Não chega DM | Você precisa dividir um servidor com o bot e aceitar DM de membros dele |
| `config-missing` ao iniciar | O app lista os nomes que faltam. Salve esses valores |
| O bot reage mas não responde | Falta a permissão de enviar mensagens (num fórum: enviar mensagens em threads) ou ver o histórico no canal |
| Você recebe "Falha ao classificar" | Veja **Logs**. Quase sempre é chave inválida, sem crédito ou limite de uso. O aviso vem no máximo uma vez por hora |
| O patch automático não chega | **Estado**: `patch_auto` não pode ser `off`, `sync_timer` deve ser `active` e `changes_file` não pode ser `missing`. Sem timer, toque em **Instalar ou atualizar**. Os **Logs** dizem `auto patch: ...` a cada tentativa |
| `python3-venv-missing` | o `apt-get` não conseguiu instalar: `sudo apt-get install python3-venv` e instale de novo |

## Testes

```
python3 -I server/deploy/discord_bot/bot_core_test.py
python3 -I server/deploy/discord_bot/claude_client_test.py
python3 -I server/deploy/chaos_ctl_test.py
```

Nenhum usa rede, Discord ou chave.
