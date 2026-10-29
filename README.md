# Cinders of Chaos: painel do dono

Nota pessoal. O que falta, o que lembrar, onde achar cada coisa.
O guia do jogo para jogadores agora está em [docs/GAME_GUIDE.md](docs/GAME_GUIDE.md).

## Datas

| Data | O quê |
|---|---|
| 31/10/2026 15:00 | Beta, primeiro fim de semana |
| 07/11/2026 15:00 | Beta, segundo fim de semana |
| Entre o beta e o lançamento | Wipe completo do beta (a tabela `chaos_beta_testers` fica) |
| 20/11/2026 15:00 | Lançamento. Começam a Season 1, a Season 1 de PvP e o Founder Pack |
| 18/12/2026 15:00 | Fim do Founder Pack, nunca mais volta |
| 20/12/2026 | Fim do bônus de 15% dos criadores (30 dias depois do lançamento) |
| 15/01/2027 | Fim da Season 1 de PvP |
| 19/02/2027 | Fim da Season 1 |
| 20/02/2027 15:00 | Season 2 (planejada) |

Patch notes toda quarta. Weekend Ritual toda sexta 18:00 até domingo 23:59, boss no sábado 19:00.

## Só eu posso fazer

### Antes do beta (31/10)
- [ ] Servidor do beta com o código do título "Beta Tester" desde o primeiro fim de semana.
- [ ] Fuso do VPS em São Paulo: `sudo timedatectl set-timezone America/Sao_Paulo` (o app admin ainda não tem botão).
- [ ] Mandar a posição (x, y, z) ou a área das escadas sem descida.

### Antes do lançamento (20/11)
- [ ] Testar ao vivo o que entrou em 29/10: Loot Bag com mais de 250 itens (páginas), janela de cosméticos, TRY ON da loja, `/weekend status|off|on`, stash sem piscar, salvage de um clique.
- [ ] Certificado de assinatura de código (SSL.com IV ou OV com eSigner). Credenciais só como secrets do GitHub.
- [ ] Testar o launcher no Windows. Instalar fora de `C:\Program Files`.
- [ ] Testar "Publicar update" no app admin com um update que troca o `chaos.pack` (timeout de 30 s).
- [ ] Baixar e testar o app de gestão: GitHub > Releases > `admin-desktop-v0.1.0` > `cinders-admin.exe`.
- [ ] Advogado: Termos de Doação seção 7 (15% dos criadores na janela de lançamento) e as outras cláusulas de [docs/OWNER_TODO.md](docs/OWNER_TODO.md).
- [ ] Discord: criar o servidor, ativar Comunidade, colocar o ícone e o banner (`website/art/`), webhooks do jogo, link em `CHAOS_DISCORD_URL`.
- [ ] Domínio, hospedagem com proteção DDoS, SMTP, reCAPTCHA, Mercado Pago e PayPal ao vivo, chaves do updater e do client. Lista completa em [docs/OWNER_TODO.md](docs/OWNER_TODO.md).
- [ ] Lugar no hub para assinantes: precisa de tiles novos no mapa.

### APK (depois do lançamento)
- [ ] Conta de desenvolvedor do Google com verificação (regra de apps fora da loja no Brasil desde 09/2026).
- [ ] Guardar o backup offline da keystore de release do APK.

## Em andamento

| Item | Estado |
|---|---|
| O312 App de gestão no PC | Fase 1 pronta. Falta: ao vivo, cards de status e métricas, reload por arquivo, updates assinados |
| O313 APK do jogo | Fase 2: build Android. Plano em [docs/ANDROID_CLIENT.md](docs/ANDROID_CLIENT.md). Uns 3 a 4 meses até jogável |
| O314 Launcher | Pronto no código, com abas de notícias e changelog. Falta testar no Windows |
| O320 Criadores | Kit de streamer sendo feito (overlays, banners, guia) |
| O323 Hunts | Avisos de caveira nas passagens para áreas mais fortes |
| 147 Tradução | Todo texto do client por `tr()`, pt-BR |
| O110 Bots de teste | Cobertura em andamento |
| O86, O186 | Bugs sem causa achada (summons, Auto setup) |
| 113, 188 | Shaders e prévia de cosméticos sem teste num client real |

Lista completa: [ROADMAP.md](ROADMAP.md).

## Ideias para depois
- Bot próprio do Discord (canais, cargos e avisos automáticos).
- Nível mínimo nas passagens de hunt extremas (ver docs/HUNT_TRANSITIONS.md quando existir).
- Pair 57 para restaurar as 13 roupas das rifts.
- Prévia da moldura de nome no mapa já existe. Ícone na lista de online: o client não tem lista.
- Mais ideias em [docs/IDEAS.md](docs/IDEAS.md).

## Lembretes
- Preços: 1 coin vale uns R$ 0,10. Tabela em [docs/PRICES.md](docs/PRICES.md).
- Pacto Completo 499 / 1350 / 2500 coins (30 / 90 / 180 dias). Pact ou Premium sozinho 299.
- Não pay to win: a loja nunca vende poder, orbs de sorte nem itens prontos ([página de fair-play](website/overlay/plugins/chaos/fairplay/fairplay_data.json)).
- Personagem permanente nunca sofre wipe depois do lançamento. Temporadas são personagens separados e opcionais.
- Para cada passo no VPS, procurar primeiro o botão no app admin ([docs/ADMIN_APP.md](docs/ADMIN_APP.md)).
- Bugs dos jogadores: app admin > Painel > Bugs e sugestões > Copiar tudo, e colar para o Claude.
- Nunca nomes de outros jogos ou servidores no repo (`check_names.py`).

## Onde está cada coisa

| Assunto | Arquivo |
|---|---|
| Tarefas do dono para o lançamento | [docs/OWNER_TODO.md](docs/OWNER_TODO.md) |
| Plano e passos do lançamento | [docs/LAUNCH.md](docs/LAUNCH.md), [docs/BETA.md](docs/BETA.md) |
| Segurança | [docs/SECURITY_CHECKLIST.md](docs/SECURITY_CHECKLIST.md) |
| Classes | [docs/CLASSES.md](docs/CLASSES.md) |
| Sistemas do servidor | [server/README.md](server/README.md) |
| Módulos do client | [client/MANIFEST.md](client/MANIFEST.md) |
| Site | [website/README.md](website/README.md) |
| Launcher | [launcher/README.md](launcher/README.md) |
| App de gestão no PC | [desktop/README.md](desktop/README.md) |
| GMs | [docs/GM_HANDBOOK.md](docs/GM_HANDBOOK.md) |
| Créditos | [docs/CREDITS.md](docs/CREDITS.md) |
| Comandos e checagens da CI | [CLAUDE.md](CLAUDE.md) |
