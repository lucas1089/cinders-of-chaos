# Legal texts

> **Drafts.** These texts were drafted from what the code does. They are not legal advice. A lawyer must review them
> before launch, above all the items under "Check" below. This note stays here only; the public pages do not show it.

| File | Page |
|---|---|
| `terms.pt-BR.md`, `terms.en.md` | Terms of Use: `page.php?plugin=chaos&p=legal&doc=terms` (`&l=en` for English) |
| `privacy.pt-BR.md`, `privacy.en.md` | Privacy Policy (LGPD): `...&doc=privacy` |
| `donations.pt-BR.md`, `donations.en.md` | Donation Terms: `...&doc=donations` |

The Portuguese text is the main one and prevails; the English one is a translation. Keep them in step.

## How they reach the website

- `website/install_site.sh` copies these six files to `plugins/chaos/legal/` of the site. The plugin's page
  `pages/legal.php` renders them (`legal_lib.php`: headings, paragraphs, lists, tables, bold, links; everything
  escaped). Edit here, then run the installer again. It warns while placeholders are left.
- Links: the footer of every page (`layouts/chaos/locale/en.php`), the account creation form, the donation page, and
  section 8 of the Rules page (`website/setup/rules.bbcode`).
- Account creation needs the checkbox "I accept the Terms of Use and the Privacy Policy". The acceptance is stored in
  `chaos_legal_acceptance` with a version: the first 16 hex digits of the SHA-256 of the three Portuguese texts. Any
  edit gives a new version.
- Donations: the donation page says before payment that a donation is voluntary, gives no right to a refund except where
  the law requires one, and is not the purchase of a product. After payment the order says again that it was a
  voluntary donation. No e-mail is sent after a donation (the provider sends its own receipt); if one is ever added, it
  must repeat this.
- Website details: website/README.md "Legal pages". Tests: `php website/tests/chaos_legal_pages_test.php`.

## Placeholders the owner fills in

Same names in both languages. The page highlights any placeholder still there.

| Placeholder | What | Files |
|---|---|---|
| `[NOME DO RESPONSÁVEL]` | the operator: your name or your company's name | all |
| `[CPF OU CNPJ]` | the operator's tax id. A CPF on a public page exposes you; a CNPJ (for example a MEI) is safer | all |
| `[CIDADE/UF]` | city and state, also the court of the Terms | terms, privacy |
| `[E-MAIL DE CONTATO]` | a contact address that someone reads | all |
| `[NOME DO ENCARREGADO]`, `[E-MAIL DO ENCARREGADO]` | the data protection officer (encarregado) or contact channel | privacy |
| `[DATA DE VIGÊNCIA]` | the date the version takes effect | all |
| `[IDADE MÍNIMA]` | minimum age to create an account. Suggestion: 13 | terms |
| `[PRAZO DE AVISO DE WIPE]` | days of notice before a full wipe after launch. Suggestion: 30 | terms, donations |
| `[PRAZO DE AVISO DE ENCERRAMENTO]` | days of notice before the game closes for good. Suggestion: 30 | terms |
| `[PRAZO DOS REGISTROS DE MODERAÇÃO]` | how long reports, bug reports, anti-cheat and staff logs are kept. Suggestion: 2 years, then build the purge (see Check) | privacy |
| `[PROVEDOR DE E-MAIL]` | the SMTP relay (`CHAOS_SMTP_HOST`) | privacy |
| `[PROVEDOR DE HOSPEDAGEM]`, `[PAÍS DA HOSPEDAGEM]` | the host of the game, the site and the database, and its country | privacy |
| `[PROVEDOR ANTI-DDOS]` | the provider of the gateway VPS (docs/LAUNCH.md "Gateways and DDoS") | privacy |
| `[PROVEDOR DE BACKUP]` | the off-site backup target (`CHAOS_BACKUP_REMOTE` / `CHAOS_BACKUP_RSYNC`) | privacy |
| `[PREÇO EM R$]`, `[PREÇO EM US$]` | the pack prices: USD = `usdCents` in `shop_coins_config.lua`, BRL = USD x `brlPerUsd`. Or drop the price columns and keep "the amount shown before payment counts" | donations |

The coin numbers in the donation table come from `shop_coins_config.lua` (the test checks them). Change both together.

## Check (lawyer or owner)

What the code does was read for these texts. These points are not settled by the code, or need a legal opinion:

1. **Moderation records have no deletion.** `chaos_reports` (with the 10 public chat lines), `chaos_antibot_log`,
   `chaos_antibot_holds` and `chaos_admin_log` are never purged. The policy promises
   `[PRAZO DOS REGISTROS DE MODERAÇÃO]`: pick it and build a purge before launch, or change the text.
2. **Other data kept without a limit:** `players.lastip` and the base ban tables (engine), `znote_accounts.ip` (sign-up
   IP), `chaos_referrals.reg_ip`. The policy says "while the account exists". Check this is acceptable.
3. **Marco Civil da Internet, art. 15.** If the operator is a company providing the service for profit, access logs
   (IP, date, time) must be kept for 6 months. The code keeps login IPs for 1 day (website) and console logs 14 days.
   The policy says "for the legal period" if required. Decide whether it applies and, if so, add a 6-month access log.
4. **Gateway logs.** HAProxy on the gateways logs client IPs to syslog (`/var/log/haproxy.log`). Set its logrotate to
   14 days or less to match the policy. The client guard log is now rotated (`server/deploy/chaos.logrotate`).
5. **Off-site backups must be encrypted.** The policy says they are. `backup_offsite.sh` encrypts only when a key is
   set (`CHAOS_BACKUP_AGE_RECIPIENT`, `_GPG_RECIPIENT` or `_PASSPHRASE_FILE`).
6. **Consumer law and refunds.** Whether the Consumer Protection Code applies to a voluntary donation with a thank-you,
   and whether the 7-day right of withdrawal (art. 49) must be offered. The texts promise to honour any refund the law
   gives; a refund takes back only the coins still unspent (`removeCoinsOnReversal`).
7. **Tax treatment of donations.** Income or donation (ITCMD) for the operator, and whether "donation" is the right
   word for a payment that brings coins. PayPal's DONATION category may need a registered nonprofit (docs/LAUNCH.md
   "Donations").
8. **Minors.** The site does not ask for an age. The checkbox text asks under-18s for a guardian's permission. Check the
   minimum age, LGPD art. 14 (children under 12) and the Brazilian statute for children and teenagers in digital
   environments (Lei 15.211/2025, ECA Digital): age checks, parental tools, and its rules on paid random rewards in
   games, against the store, the Gambler and any random reward bought with coins.
9. **Chargeback fraud penalty.** The Donation Terms say the account "may be suspended or banned". The staff ladder has
   no line for it. Decide the penalty and add it to the Rules page and docs/GM_HANDBOOK.md.
10. **Bans and donations.** The texts say a ban for breaking the rules gives no refund. Check this against consumer law.
11. **International transfers.** Google, PayPal, Discord and maybe the host are abroad. The policy relies on the
    providers' contractual clauses (LGPD art. 33). Check the providers' terms and the ANPD rules on standard clauses.
12. **DPO.** A small processing agent may not need a DPO but must give a contact channel (ANPD Resolution 2/2022).
    Decide who it is.
13. **Existing accounts.** Accounts made before the checkbox (the beta accounts kept at launch) have no row in
    `chaos_legal_acceptance`. Ask them to accept at launch (not built) or rely on the notice of the change.
14. **Account deletion.** There is no self-service deletion. Requests go by e-mail and staff delete by hand. Write the
    steps for staff (which tables to clear, which records to keep).
15. **The game client.** Store > Donate in the client shows the voluntary notice and the website's refund sentence
    (no refund except where the law requires one, not the purchase of a product, coins without real-world value);
    once the order is paid or credited, the "voluntary donation, not a purchase" sentence instead. The in-game message
    after crediting carries that one too. Both name where the Donation Terms are, as text and not a link: the website
    page `page.php?plugin=chaos&p=legal&doc=donations`. Check that this is enough in the client.
16. **Discord webhooks.** The reports webhook sends character names to Discord (`CHAOS_REPORTS_WEBHOOK`); the health
    alerts may carry log lines. The policy mentions the reports notices.
