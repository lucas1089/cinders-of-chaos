# Doações: Pix e PayPal, passo a passo

Guia do dono para ligar as doações (O413). O código já existe. Falta só conta, chaves e testes.
Tudo pelo app admin. O shell fica só como plano B, no fim.

Como funciona, em resumo:
- O jogo grava o pedido. O worker (`chaos-payworker`) cria a cobrança no Mercado Pago ou no PayPal.
- O provedor avisa o site pelo webhook. O site confere a assinatura e consulta o pagamento de novo.
- O servidor do jogo credita as Chaos Coins.
- As chaves ficam só na VPS, em `/etc/chaos/payments.env`, modo 640, dono root, grupo www-data.
- Nunca ponha uma chave no repositório, num chat ou num print.

Detalhes técnicos: website/README.md "Donations (Chaos Coins)". Notas legais: docs/LAUNCH.md "Donations (Pix / PayPal)".

## 0. Antes de tudo

1. **Textos legais.** Preencha os campos `[...]` de `docs/legal/` e peça a revisão de um advogado.
   Os três textos contam: Termos de Uso, Política de Privacidade e Termos de Doação.
   A lista dos campos e o que conferir: [docs/legal/README.md](legal/README.md).
   Depois: app admin, aba Comandos > cartão Site e update do client > Reinstalar o site.
2. **Site em HTTPS.** Os dois provedores só chamam webhook em `https://`.
3. **Preços.** Os pacotes estão em `server/data/scripts/chaos/shop_coins_config.lua` (`usdCents`, `brlPerUsd`).
   Tabela e decisão: docs/PRICES.md. O menor pacote custa R$ 9,90 no Pix e US$ 1,98 no PayPal.
4. **App admin atualizado.** O cartão Pagamentos (doações) precisa de um app compilado depois do O413.
   A VPS também precisa do `chaos-ctl.sh` novo: Painel > Atualizar servidor > Aplicar e reiniciar.
5. **Endereços de webhook.** App admin, aba Comandos > Ações rápidas > cartão Pagamentos (doações) > Estado.
   Embaixo aparecem os dois endereços, cada um com Copiar:
   - Mercado Pago: `https://SEU-SITE/chaos_pay_webhook.php?psp=mercadopago`
   - PayPal: `https://SEU-SITE/chaos_pay_webhook.php?psp=paypal`

   Sem endereço? Cole o endereço do site no campo "Endereço do site" e toque em Salvar.
   Vazio usa o `CHAOS_SITE_URL` do `site.env`.

## 1. Mercado Pago (Pix)

1. Crie a conta em mercadopago.com.br. Para receber como empresa, use uma conta com CNPJ (um MEI serve).
   Confirme e-mail, celular e documento.
2. Cadastre uma chave Pix na conta. App do Mercado Pago > Pix > Minhas chaves > Cadastrar chave.
   Sem chave Pix a API não gera o QR code.
3. Abra o painel de desenvolvedor: mercadopago.com.br/developers > Suas integrações > Criar aplicação.
   - Nome: Cinders of Chaos.
   - Tipo de solução: pagamentos online, Checkout Transparente (API de pagamentos).
   - Aceite os termos e crie.
4. Na aplicação, abra Credenciais de produção. Preencha o setor e o site, e ative.
   Copie o **Access Token**. Ele começa com `APP_USR-`. É uma senha.
5. Na aplicação, abra Webhooks > Configurar notificações, aba Modo produção.
   - URL: o endereço do Mercado Pago do passo 0.5.
   - Eventos: marque só **Pagamentos**.
   - Salve. Aparece a **assinatura secreta**. Copie. Também é uma senha.
6. Teste do Mercado Pago, sem dinheiro: crie usuários de teste no painel (Contas de teste: um vendedor e um comprador).
   Entre com o vendedor de teste e copie as credenciais dele. Pague com o comprador de teste.
   Um token de teste começa com `TEST-` ou é o `APP_USR-` do vendedor de teste.

## 2. PayPal

1. Crie uma conta **PayPal Business** em paypal.com/br/business. Confirme o e-mail e ligue uma conta bancária.
2. Entre em developer.paypal.com com a mesma conta. Abra Apps & Credentials.
3. **Sandbox primeiro.** Deixe a chave no alto em Sandbox. Create App, tipo Merchant, nome Cinders of Chaos.
   Copie o **Client ID** e o **Secret**. O Secret é uma senha.
4. Na mesma tela do app, desça até Webhooks > Add Webhook.
   - URL: o endereço do PayPal do passo 0.5.
   - Eventos, os que o site confere (`PayPal.php`):
     - Checkout order approved (`CHECKOUT.ORDER.APPROVED`)
     - Payment capture completed (`PAYMENT.CAPTURE.COMPLETED`)
     - Payment capture denied (`PAYMENT.CAPTURE.DENIED`)
     - Payment capture pending (`PAYMENT.CAPTURE.PENDING`)
     - Payment capture refunded (`PAYMENT.CAPTURE.REFUNDED`)
     - Payment capture reversed (`PAYMENT.CAPTURE.REVERSED`)
     - Customer dispute created (`CUSTOMER.DISPUTE.CREATED`)
   - Salve. Copie o **Webhook ID**, por exemplo `1JE4291016473214C`.
5. Testing Tools > Sandbox Accounts: há uma conta pessoal de teste. Use ela para pagar no Sandbox.
6. **Live depois.** Troque a chave para Live e repita os passos 3 e 4. Live tem Client ID, Secret e Webhook ID próprios.
   As chaves do Sandbox não funcionam em Live.
7. Categoria: o site manda a doação como `DONATION`. Em alguns países o PayPal só aceita isso de entidade sem fins
   lucrativos. Se recusar, use `DIGITAL_GOODS`. O item continua escrito "doação voluntária".

## 3. No app admin: a ordem dos campos

Aba Comandos > Ações rápidas > cartão **Pagamentos (doações)**. Um campo por ajuste, cada um com Salvar.
O app confere o formato antes de enviar. O valor vai pelo SSH, no stdin. O app nunca mostra o valor de volta.
Depois de Salvar, o campo diz "Salvo" ou "Vazio".

1. **Endereço do site**, só se o do `site.env` não for o endereço público. Salvar.
2. **Mercado Pago: Access Token**. Salvar.
3. **Mercado Pago: assinatura secreta do webhook**. Salvar.
4. **Ligar Pix**.
5. **Sandbox (teste)**.
6. **PayPal: Client ID**, **PayPal: Secret**, **PayPal: Webhook ID**, os do Sandbox. Salvar em cada um.
7. **Ligar PayPal**.
8. **E-mail para Pix sem e-mail da conta**, se houver contas sem e-mail. Exemplo: `doacao+{account}@seu-dominio`.
   `{account}` vira o número da conta. Salvar.
9. **Ativar worker**. Instala o `chaos-payworker` e liga.
10. **Testar**. Só lê, não cria cobrança. O certo:
    - `pix=200 ok site=MLB`
    - `paypal=200 ok env=sandbox`
    - `webhook_pix=401 ok` e `webhook_paypal=401 ok`: a página existe e recusa chamada sem assinatura.
11. **Estado**. A primeira linha resume. "Falta: ..." diz o que ainda não foi salvo.

O primeiro Salvar cria o arquivo a partir de `website/payments.env.example`. Também cria o `CHAOS_PAY_PAYER_SALT`,
uma vez, ao acaso. Não troque o salt depois.
Cada Salvar reinicia o worker se ele estiver rodando. O webhook lê o arquivo a cada chamada.

O que o Testar quer dizer quando falha:
- `pix=401 fail`: Access Token errado ou revogado. Copie de novo.
- `paypal=401 fail`: Client ID e Secret não batem, ou são do outro modo (Sandbox contra Live).
- `webhook_...=503 fail`: falta a assinatura secreta (Mercado Pago) ou o Webhook ID (PayPal).
- `webhook_...=404 fail`: a página não existe (Reinstalar o site) ou o provedor está desligado.
- `...=000 fail`: sem conexão. Veja DNS, HTTPS e firewall.

No painel do Mercado Pago, "Simular notificação" com a assinatura certa recebe 200 ou 404 ("unknown id": um pagamento
que não é nosso). 401 lá quer dizer assinatura secreta errada.

No app desktop: VPS e manutenção > Pagamentos (doações). Mesmos comandos: Estado, Guardar ajuste, Testar,
Ativar worker, Desativar worker. Os endereços de webhook aparecem na saída do Estado.

## 4. Testes no Sandbox

No client do jogo e no site:
1. Uma doação Pix com o comprador de teste do Mercado Pago. QR code e copia e cola aparecem. O pagamento aprovado
   credita as moedas em segundos. Aparece o aviso e o saldo, sem relogar.
2. Uma doação PayPal com a conta pessoal do Sandbox. O navegador abre, aprova, captura, credita.
3. Cancele uma doação. Deixe outra expirar (30 minutos).
4. Reembolse uma de cada no painel do provedor depois de creditar. As moedas que sobraram voltam.
   O admin do site mostra em Store > Donations: refunds and chargebacks.

## 5. Live e a primeira doação real

1. No PayPal, Live: cole o **Client ID**, o **Secret** e o **Webhook ID** do app Live. Salvar em cada um.
2. Toque em **Live (real)** e confirme.
3. No Mercado Pago, confira que o Access Token é o de produção (`APP_USR-` da sua conta, não do vendedor de teste).
   O Estado mostra "token de teste" quando o token começa com `TEST-`.
4. **Testar** de novo: `paypal=200 ok env=live`.
5. **Doação real**, com sua própria conta de jogador, no menor pacote: R$ 9,90 no Pix e US$ 1,98 no PayPal.
   Não existe pacote de R$ 1 ou US$ 1. Confira as moedas no jogo.
6. **Reembolso** da doação de teste:
   - Mercado Pago: Atividade > o pagamento > Devolver dinheiro.
   - PayPal: Atividade > a transação > Emitir reembolso.
   - Em minutos o jogo tira as moedas que sobraram. O admin do site mostra o reembolso.
   - Taxas do provedor podem não voltar. É o custo do teste.
7. Nos primeiros dias, veja o Estado. As linhas `@log` e `@worker` mostram só ids e valores.

## 6. Desligar

- Um método: Desligar Pix ou Desligar PayPal. O site esconde o método e recusa pedidos novos dele.
- Tudo: Desativar (worker). Doações novas esperam a cobrança até Ativar de novo.
- Nunca use o provedor `mock` num servidor no ar. Ele aprova doação sem dinheiro. O app não oferece `mock`.
  Se o Estado disser "ATENÇÃO: provedor mock", salve Desligado ou o provedor real.

## Plano B: shell na VPS

Só se o app não alcançar a VPS. O valor vai no stdin, nunca na linha de comando:

```
sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh pay-status
read -rs V && printf '%s\n' "$V" | sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh pay-set CHAOS_MP_ACCESS_TOKEN; unset V
echo mercadopago | sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh pay-set CHAOS_PAY_PIX_PROVIDER
sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh pay-enable
sudo /opt/chaos/repo/server/deploy/chaos-ctl.sh pay-test
```

Os nomes que `pay-set` aceita: `chaos-ctl.sh help`.
