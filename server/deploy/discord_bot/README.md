# Bot do Discord: bugs e patch notes

Um bot para o seu servidor do Discord. Ele lê o canal de bugs, usa o Claude para separar bug de conversa, junta relatos repetidos, avisa você quando o bug é crítico e ajuda a escrever os patch notes. Roda na VPS do jogo como serviço do systemd. Chama-se `chaos-discordbot`.

Código: `bot.py` é a camada fina do Discord. As regras estão em `bot_core.py` e as chamadas ao Claude em `claude_client.py`. Os testes são `bot_core_test.py` e `claude_client_test.py`.

## O que ele faz

No canal de bugs o bot lê toda mensagem, inclusive prints anexados. O Claude vê as imagens.

| Caso | O que o bot faz |
|---|---|
| Bug novo | Reage com 🐞 e responde ao jogador com o número do bug |
| Bug repetido | Reage com 🔁 e soma o relato ao bug que já existe. O mesmo jogador conta uma vez só |
| Bug crítico | Manda DM para você na hora. Vale para crash, exploit e perda de item |
| Sugestão ou conversa | Não faz nada. O bot fica em silêncio |

Todo dia às 09:00 de São Paulo você recebe um resumo por DM.

Comandos. Só você e quem tem o cargo de admin, se você definir um, conseguem usar. As respostas são só suas.

| Comando | Para quê |
|---|---|
| `/bugs lista [status]` | Lista por gravidade e número de relatos |
| `/bugs ver id` | Detalhes de um bug |
| `/bugs status id novo_status [duplicado_de] [nota]` | Muda o status: aberto, confirmado, em andamento, corrigido, não é bug, duplicado |
| `/bugs exportar [incluir_fechados]` | Baixa um arquivo Markdown |
| `/bugs resumo` | O Claude sugere prioridades e bugs que provavelmente têm a mesma causa |
| `/patch gerar versao [extras]` | Escreve os patch notes com os bugs corrigidos, mostra a prévia com Publicar, Editar e Cancelar |
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
https://discord.com/oauth2/authorize?client_id=SEU_APPLICATION_ID&permissions=117824&scope=bot%20applications.commands
```

Os escopos são `bot` e `applications.commands`. O número 117824 são estas permissões: Ver Canais, Enviar Mensagens, Inserir Links, Anexar Arquivos, Ver Histórico de Mensagens e Adicionar Reações.

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

Para atualizar o bot depois de um update do repositório, toque em **Instalar ou atualizar** de novo. Ele copia o código novo e reinicia o bot se estiver ligado.

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
- Roda de novo sem estragar nada.

## 5. Patch notes no site e no jogo

O `/patch gerar` e o `/patch escrever` publicam o embed no canal de patch notes. O bot também grava dois arquivos no formato que o jogo e o site já leem:

- `/var/lib/chaos/discord-bot/patchnotes/AAAA-MM-DD.md`, em inglês
- `/var/lib/chaos/discord-bot/patchnotes/AAAA-MM-DD.pt-br.md`, em português

O Claude escreve as duas versões juntas. Se você edita ou escreve à mão, ele traduz para o inglês na hora de publicar. Se o dia já tem um arquivo, o novo vira `AAAA-MM-DD-2` e nada é sobrescrito.

Os arquivos não vão sozinhos para o jogo, porque o bot não tem acesso à pasta do servidor. Toque em **Levar patch notes ao jogo** no app, ou rode `sudo $CTL discord-bot patchnotes`. Isso copia só os arquivos que o servidor ainda não tem para `data/patchnotes`. O jogo lista essa pasta a cada minuto no máximo. Depois copie os arquivos para `server/data/patchnotes` no repositório e faça o commit, para o próximo update não perdê-los.

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
| O bot está online e ignora as mensagens | Ligue **Message Content Intent** na aba Bot e reinicie |
| Os comandos não aparecem | Salve `DISCORD_GUILD_ID`, reinicie e confira o convite com `applications.commands`. Sem o id do servidor pode levar uma hora |
| `403 Forbidden (error code: 50001): Missing Access` ao iniciar | O bot não está no servidor de `DISCORD_GUILD_ID`, ou foi convidado sem `applications.commands`, ou o id não é de servidor. Convide de novo com o link da seção 1 (pode convidar por cima). Para o id: modo desenvolvedor ligado, clique direito no nome do servidor > Copiar ID do servidor, e salve com **Guardar ajuste**. Depois **Reiniciar**. Desde 2026-10-31 o bot segue rodando sem os comandos e explica isso nos **Logs** |
| "Integration requires code grant" ao abrir o link de convite | Na aba **Bot**, desligue **Requires OAuth2 Code Grant**, salve e abra o link de novo |
| Não chega DM | Você precisa dividir um servidor com o bot e aceitar DM de membros dele |
| `config-missing` ao iniciar | O app lista os nomes que faltam. Salve esses valores |
| O bot reage mas não responde | Falta a permissão de enviar mensagens ou ver o histórico no canal |
| Você recebe "Falha ao classificar" | Veja **Logs**. Quase sempre é chave inválida, sem crédito ou limite de uso. O aviso vem no máximo uma vez por hora |
| `python3-venv-missing` | o `apt-get` não conseguiu instalar: `sudo apt-get install python3-venv` e instale de novo |

## Testes

```
python3 -I server/deploy/discord_bot/bot_core_test.py
python3 -I server/deploy/discord_bot/claude_client_test.py
python3 -I server/deploy/chaos_ctl_test.py
```

Nenhum usa rede, Discord ou chave.
