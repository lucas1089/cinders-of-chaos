# Teste do VPS em um dia: ficar, fazer upgrade ou pedir reembolso

Primeira versão 2026-10-16. Para o VPS de jogo da Hypehost em São Paulo (docs/HOSTING.md).

- **Plano do teste: Magic Sword.** 6 vCPU Ryzen 9, 16 GB de RAM, 200 GB NVMe, R$ 359/mês.
- **Upgrade possível: Golden Boots.** 10 vCPU Ryzen 9, 32 GB, 340 GB NVMe.
- **Reembolso integral em 7 dias.** O suporte não diz se as vCPUs são dedicadas. O Ryzen pode ser de 5900X até 9950X. Este teste responde as duas coisas.
- O upgrade da Hypehost mantém o mesmo tipo de máquina. Então um bom resultado de núcleo único no Magic Sword vale também para o Golden Boots. O upgrade só traz mais vCPU, RAM e disco.

Ferramentas:
- `server/tools/host_trial.sh`: o teste do host. Gera `host_trial_report.txt` e `host_trial_report.json`.
- `server/tools/host_trial.sh load`: o teste de carga do servidor do jogo no próprio VPS (chama `server/tools/host_trial_load.sh`). Gera `host_trial_load_report.txt`.
- `server/tools/host_trial.py`: faz as medições e os vereditos. Testes: `server/tools/host_trial_test.py`, que roda no CI.

## 1. Prazo do reembolso

**Cancele antes do dia 7.** Se contratou na segunda, o último dia seguro é o domingo seguinte. Peça o reembolso por escrito, pelo ticket, e guarde o número do ticket.

Anote agora:
- Data da contratação: ____
- Último dia para cancelar (data + 6 dias): ____
- Lembrete no celular para o dia 5: ____

Se o resultado for UPGRADE ou BORDERLINE, decida até o dia 5. Não deixe para o último dia.

## 2. Antes de começar

Você precisa de:
- acesso root por SSH ao VPS, com Ubuntu 22.04 ou 24.04, ou Debian 12;
- uma cópia deste repositório no seu PC;
- os arquivos da release `winpkg-35` (GitHub, Releases): `CindersOfChaos-Server-Linux.tar.gz` e o cliente, `CindersOfChaos-Client-Windows.zip` ou `CindersOfChaos-Client-Linux.tar.gz`;
- um PC em casa com o cliente, para o teste do filtro.

Não instale painel, antivírus ou outros serviços antes do teste. Eles mudam os números.

## 3. Dia 1, passo a passo

Total: umas 3 horas de máquina e 30 minutos seus. Rode o teste do host duas vezes: de manhã e no horário de pico, entre 20h e 23h. Vizinhos barulhentos aparecem mais à noite.

| Quando | O que fazer | Duração |
|---|---|---|
| Manhã | Passo A: copiar as ferramentas. Passo B: teste do host | 40 min |
| Manhã | Passo C: instalar o servidor. Passo D: teste de carga com 300 e 400 bots | 1 h |
| Tarde | Passo E: teste do filtro com o cliente de casa, 5 minutos jogando | 20 min |
| 20h a 23h | Passo B de novo, com outra pasta de saída | 35 min |
| Depois | Passo F: me enviar os relatórios. Passo G: decidir pela tabela | 10 min |

### Passo A: copiar as ferramentas para o VPS

Mais fácil: baixar tudo direto no VPS. Não precisa do PC.

```
apt-get update && apt-get install -y git screen curl
mkdir -p /opt/chaos /opt/chaos-trial
git clone --depth 1 https://github.com/lucas1089/cinders-of-chaos.git /opt/chaos/repo
curl -L -o /root/CindersOfChaos-Server-Linux.tar.gz \
  https://github.com/lucas1089/cinders-of-chaos/releases/download/winpkg-35/CindersOfChaos-Server-Linux.tar.gz
screen -S teste
```

Ou, a partir do seu PC, na pasta do repositório:

```
git archive --format=tar.gz -o chaos-repo.tar.gz HEAD
scp chaos-repo.tar.gz CindersOfChaos-Server-Linux.tar.gz root@IP_DO_VPS:/root/
```

No VPS:

```
mkdir -p /opt/chaos/repo /opt/chaos-trial
tar -xzf /root/chaos-repo.tar.gz -C /opt/chaos/repo
apt-get install -y screen
screen -S teste
```

Use o `screen`. Se a conexão SSH cair, o teste continua. Para voltar: `screen -r teste`.

### Passo B: teste do host, 35 minutos

```
cd /root
sudo bash /opt/chaos/repo/server/tools/host_trial.sh --install-tools --out /root/trial-manha
```

- `--install-tools` instala `fio` e `luajit` com apt-get. É a única mudança no sistema. Sem isso o teste funciona, mas mede o disco com um laço em Python.
- Ensaio rápido de 3 minutos, só para ver se roda: acrescente `--quick`. O veredito vale só para a rodada completa.
- À noite: `--out /root/trial-noite`.
- Já com o Golden Boots: acrescente `--plan golden-boots`.

O que ele faz:
- lê o modelo da CPU, MHz, flags e a contagem de vCPU;
- deixa um laço de CPU, com prioridade baixa, em cada vCPU por 30 minutos e mede o steal a cada 10 segundos. Uma VM parada esconde o steal, por isso o laço;
- roda 7 vezes um benchmark fixo de núcleo único, preso a uma vCPU com `taskset`, espalhado pelos 30 minutos;
- mede o fsync do disco, o que mais importa para os COMMITs do MariaDB, e a escrita sequencial;
- mede a banda de memória e a RAM;
- faz ping em alguns endereços públicos no Brasil.

Ele só escreve numa pasta temporária em `/var/tmp`, que apaga no fim. Não faz teste de carga contra outra máquina.

Código de saída: 0 KEEP, 1 BORDERLINE, 2 UPGRADE, 3 REFUND.

### Passo C: instalar o servidor do jogo

Caminho recomendado: o pacote Linux da release `winpkg-35`. Ele traz o motor compilado e o próprio MariaDB.

```
tar -xzf /root/CindersOfChaos-Server-Linux.tar.gz -C /opt/chaos-trial --strip-components=1
cd /opt/chaos-trial
ls    # deve mostrar start-server.sh, server/, mariadb/
./start-server.sh -d
tail -f logs/server.log     # espere "Server Online", depois Ctrl+C no tail
```

O arquivo tem uma pasta `CindersOfChaos-Server-Linux/` por cima. O `--strip-components=1` tira essa pasta.

A primeira partida cria o banco e a conta staff. A senha fica em `first-start-account.txt`. Não envie esse arquivo para ninguém.

Caminho alternativo, mais longo: o servidor base com `install_all.py`, como na produção. Siga docs/LAUNCH.md seções 1 a 3: compilar o motor com os patches, criar o banco e rodar `python3 -I server/tools/install_all.py /opt/chaos/server`. O script de carga deste teste só conhece o pacote. No caminho alternativo, rode `loadtest.py` à mão como em server/README.md "Load test on the full map".

### Passo D: teste de carga com 300 e 400 bots

```
sudo bash /opt/chaos/repo/server/tools/host_trial.sh load --pkg /opt/chaos-trial --out /root/trial-carga
```

- Dura uns 35 minutos: para cada contagem, a entrada dos bots, 10 minutos de carga e 1 minuto de pausa.
- Os bots e o servidor rodam no mesmo VPS e falam só por 127.0.0.1.
- Ele instala o probe de lag e o script de caça dos bots, que são só para teste, liga o `slowTaskLogMs = 100` e sobe o `maxPlayers` para caber 400 bots. No fim apaga os bots, tira os scripts, devolve o `config.lua` e reinicia o servidor.
- Com `--classes`: bots com as classes de área e as magias reais, como em server/README.md "Load test with area classes". É mais pesado e mais realista. Rode depois do teste normal, se sobrar tempo.
- Se algo parar no meio: `sudo bash /opt/chaos/repo/server/tools/host_trial_load.sh --pkg /opt/chaos-trial --cleanup-only`.

O relatório de carga mostra, para cada contagem:
- quantos bots entraram;
- o lag do game loop, que vem do probe: média, pior janela de 5 s, máximo e travadas de 500 ms ou mais;
- quanto do núcleo o thread do game loop usou;
- steal com carga;
- uso das vCPUs sem contar os bots;
- RAM livre mínima e crescimento do swap;
- tarefas lentas e COMMITs lentos, do slow task log, com o mesmo padrão do `chaos_health.py`.

Referência da máquina antiga, 4 vCPU Xeon 2.1 GHz, com bots na mesma máquina: 300 bots com lag de 59 ms; 400 bots com lag de 70 a 73 ms e 2 a 5 travadas. Um núcleo classe 7950X deve ficar abaixo de 65 ms com 400.

### Passo E: teste do filtro com o cliente real, 5 minutos

O filtro anti-DDoS da Hypehost é feito para o jogo original. Ele pode derrubar o nosso cliente 10.98.

1. No VPS, coloque o IP do VPS no `ip = "..."` de `/opt/chaos-trial/server/config.lua` e reinicie: `./stop-server.sh` e `./start-server.sh -d`.
2. Se o firewall estiver ligado, abra as portas só durante o teste: `ufw allow 7171/tcp` e `ufw allow 7172/tcp`.
3. Crie uma conta: `./add-account.sh teste UMA_SENHA_LONGA "Trial Knight" warrior`.
4. No PC de casa, aponte o cliente para o IP do VPS. Na pasta do cliente, onde está `init.lua`: `python3 -I client/tools/set_server_host.py PASTA_DO_CLIENTE IP_DO_VPS`.
5. Entre, ande, lute com monstros e use magias por 5 minutos. Troque de andar e use uma escada.
6. Anote:
   - entrou na primeira tentativa? sim / não
   - quedas ou desconexões: ____
   - travadas ou teletransportes estranhos: ____
   - ping que o cliente mostra: ____ ms
7. Depois, feche as portas de novo: `ufw delete allow 7171/tcp` e `ufw delete allow 7172/tcp`.

Se o cliente não entra, ou cai em menos de 5 minutos, abra um ticket. Peça para liberar TCP 7171 e 7172 para um cliente próprio do protocolo 10.98. Se não resolverem antes do dia 5, peça o reembolso.

Não divulgue esse IP. Se este VPS virar o backend, o IP dele não pode aparecer em lugar nenhum (docs/HOSTING.md seção 3).

### Teste do PROXY v2, para depois, quando houver gateways

Os gateways mandam um cabeçalho PROXY v2 antes dos dados do jogo. O filtro do jogo da Hypehost pode derrubar isso. Sem gateways ainda, deixe para depois. Quando existir um gateway:

1. Do gateway, com o servidor rodando no backend:
   ```
   python3 -I server/tools/host_trial.py proxy-probe IP_DO_BACKEND 7172
   ```
   Ele manda um único cabeçalho PROXY v2 e diz se veio resposta.
2. No console do backend, `logs/server.log`, deve aparecer uma linha `[PROXY protocol]`. Se o gateway ainda não está em `proxyProtocolTrusted`, é a linha `PROXY header from an address that is not in proxyProtocolTrusted, refused`. Essa linha prova que o cabeçalho passou pelo filtro.
3. Se nada aparece no console, o filtro derrubou a conexão. Peça à Hypehost para liberar os IPs dos gateways.
4. Depois siga docs/LAUNCH.md "Check it": IPs reais no banco, conexão direta recusada, cabeçalho falso recusado, e uma entrada com o cliente pelo gateway.

## 4. Como ler o relatório

O começo do `host_trial_report.txt` é uma tabela: item, veredito e detalhe. Depois vem `OVERALL` e a linha `DECISAO` em português. Abaixo estão os números completos.

| Item | O que mede | Bom |
|---|---|---|
| CPU model | o modelo que a VM vê. "passed through" = modelo real. "generic model" = a Hypehost esconde o modelo; aí vale o benchmark. A família e o modelo AMD ainda indicam Zen 3, Zen 4 ou Zen 5 | só informação |
| steal time | tempo em que a vCPU quis rodar e o host deu a CPU a outro cliente. Média, p95 e máximo, no geral e por vCPU | média até 2%, p95 até 5% |
| single-core | velocidade de um núcleo como fração de um Ryzen 9 7950X. Mediana e pior rodada. "worst run X% slower" mostra vizinhos barulhentos | 0,85 ou mais; pior rodada até 15% mais lenta |
| vCPU count | quantas vCPUs a VM tem, contra o plano | igual ao plano |
| RAM | RAM total, contra o plano, e o `innodb_buffer_pool_size` que cabe ao lado do servidor do jogo | o pool cabe |
| disk fsync | latência de escrita de 4 KiB com fsync, como um COMMIT do MariaDB. p50 e p99 | p99 até 5 ms |
| disk sequential | escrita sequencial | 300 MB/s ou mais |
| disk size | tamanho do disco, contra o plano | igual ao plano |
| memory bandwidth | cópia de memória num núcleo | 4 GB/s ou mais |
| network | velocidade da porta, se a VM mostrar, e o melhor ping para o Brasil | até 15 ms, sem perda |

Velocidade esperada de um núcleo, aproximada, de benchmarks públicos de núcleo único:

| CPU | Fração de um 7950X |
|---|---|
| Ryzen 9 9950X ou 9900X (Zen 5) | 1,09 a 1,10 |
| Ryzen 9 7950X ou 7900X (Zen 4) | 0,98 a 1,00 |
| Ryzen 9 5950X, 5900XT ou 5900X (Zen 3) | 0,81 a 0,82 |
| Ryzen 5 5500 (Zen 3) | 0,71 |
| Xeon 2.1 GHz do teste de carga antigo | 0,50 |

O benchmark é um laço fixo em LuaJIT, Lua e Python. A referência foi calibrada numa máquina conhecida e convertida pelas proporções públicas. Então ela é aproximada, uns 10% para cima ou para baixo. Use a tabela para separar um 5900X de um 9950X, não para diferenças pequenas. O veredito usa o LuaJIT quando existe, porque o motor do jogo roda Lua com LuaJIT.

Se o modelo diz 9950X mas o benchmark dá 0,6, o núcleo está sendo dividido com outros clientes. Isso é REFUND.

Buffer pool do MariaDB: o relatório diz quanto cabe. Com 16 GB: o jogo usa uns 6 GB com 400 jogadores, o sistema e os serviços uns 2 GB, e o pool fica com 3,5 a 4 GB. Com 32 GB: 8 GB, que é o máximo útil para o nosso banco. Na produção, coloque esse valor em `innodb_buffer_pool_size` no MariaDB do sistema.

Todos os limites podem ser mudados. Veja `python3 -I server/tools/host_trial.py run --help`. Exemplos: `--steal-mean-max 2`, `--steal-p95-max 5`, `--single-min 0.85`, `--fsync-p99-max 5`. Um valor até o dobro do limite é BORDERLINE; acima do dobro é REFUND.

## 5. Tabela de decisão

Use as duas rodadas do teste do host, manhã e noite, mais o teste de carga e o teste do filtro.

| Resultado | Decisão |
|---|---|
| Tudo KEEP, carga com 400 bots KEEP, filtro sem quedas | **Ficar** no Magic Sword |
| CPU e disco KEEP, mas RAM ou vCPU no limite: o teste diz UPGRADE, ou a carga mostra pouca RAM livre, swap crescendo ou todas as vCPUs ocupadas | **Upgrade para o Golden Boots.** É a mesma máquina, então o bom resultado de núcleo único continua valendo |
| CPU e disco KEEP, carga com 300 KEEP mas com 400 o lag passa de 65 ms ou o thread do jogo passa de 85% | Ficar, com `maxPlayers` 300. O upgrade não ajuda: o game loop usa um núcleo, e o núcleo é o mesmo |
| steal acima do limite em uma rodada e ok na outra | BORDERLINE. Rode o teste do host de novo no dia 2 ou 3, no pico. Se repetir, **reembolso** |
| single-core entre 0,70 e 0,85, um Zen 3 como o 5900X | BORDERLINE. Aguenta 300 jogadores, provavelmente não 400. Pergunte se existe um plano Zen 4 ou Zen 5. Sem isso, **reembolso** |
| steal acima do dobro do limite, single-core abaixo de 0,70, ou pior rodada mais de 30% lenta | **Reembolso.** O núcleo é lento ou dividido. O upgrade não resolve |
| fsync p99 acima de 10 ms | **Reembolso.** COMMITs lentos travam o jogo inteiro, docs/LAUNCH.md seção 2 |
| fsync p99 entre 5 e 10 ms | BORDERLINE. Rode de novo. Se repetir, pergunte à Hypehost se o disco é local. Disco de rede ou dividido é reembolso |
| O cliente não entra ou cai no teste do filtro, e o suporte não resolve até o dia 5 | **Reembolso** |
| vCPU, RAM ou disco menor que o anunciado | Ticket. Se não corrigirem, **reembolso** |

A regra do script: REFUND só por CPU ou disco ruim. UPGRADE só quando o steal e o núcleo único estão bons e o limite é RAM ou quantidade de vCPU.

## 6. O que me enviar

Envie só estes arquivos:
- `/root/trial-manha/host_trial_report.txt` e `.json`
- `/root/trial-noite/host_trial_report.txt` e `.json`
- `/root/trial-carga/host_trial_load_report.txt`, e os `host_trial_load_*.json` se puder
- suas anotações do teste do filtro: entrou, quedas, ping

Os relatórios não têm IP nem senha. Mesmo assim:
- **nunca** envie `chaos.env`, `first-start-account.txt`, `config.lua` ou senhas;
- **nunca** coloque o IP do VPS em lugar público: Discord, fórum, issue, site;
- mande por mensagem privada ou anexe numa issue privada do repositório.

## 7. Depois do teste

- Se for pedir reembolso: pare tudo com `cd /opt/chaos-trial && ./stop-server.sh`, abra o ticket, e não use mais o VPS.
- Se for ficar: o pacote de teste não é a produção. Siga docs/LAUNCH.md do começo: usuário próprio, MariaDB do sistema com o buffer pool do relatório, systemd, backups, monitoramento e o firewall do backend. Apague `/opt/chaos-trial` depois.
- Se for fazer upgrade: peça o Golden Boots, depois rode o Passo B de novo com `--plan golden-boots`. O núcleo único deve dar o mesmo resultado; a RAM e as vCPUs devem bater com o plano novo.
