# Owner to-do for launch

These items need the owner: a decision, an account, a key or a text. Everything else is in `docs/LAUNCH.md`.
Never put keys, passwords or tokens in the repo. They go in the server's env files or in GitHub secrets.

## Decisions

- [ ] **Dates.**
  - Proposal: launch on 20 Nov 2026 at 15:00 (UTC-3).
  - Open betas on the weekends of 31 Oct and 7 Nov.
  - The Season 1 start (now 1 Nov) moves to the launch date.
- [ ] **The beta plan.** Who joins, the wipe before launch, coins and donations in the beta, the Season 1 start and
  the staff schedule: every decision is in [docs/BETA.md](BETA.md) (draft), each marked "Owner decides" with a
  recommendation.
- [ ] **Donation prices.** Every coin pack's price is a placeholder in USD (`usdCents` in
  `server/data/scripts/chaos/shop_coins_config.lua`). Pix is not priced on its own: it charges the USD price x 5 in
  BRL (`brlPerUsd = 5`). Set the USD prices, and check that `brlPerUsd` gives the BRL prices you want.
- [ ] **Class unlock price.** The Necromancer, the Monk and the Templar cost 750 Chaos Coins each (account-wide), a
  placeholder in `server/data/scripts/chaos/class_unlocks_core.lua` and in the store offers of `shop_config.lua`
  (category "Classes"; change both). Decide the price, or another way to unlock them (the unlock method is
  pluggable: ROADMAP C8).
- [x] **Staff rules.** Decided 2026-10-12: the recommended rules of [docs/GM_HANDBOOK.md](GM_HANDBOOK.md) (see
  "Decided" below).

## Accounts and services

- [ ] **Domain.** The site address must be `https://...` (`CHAOS_SITE_URL`).
- [ ] **Hosting with DDoS protection** for the game server, the website and the database.
  - Researched options, prices and three setups (budget, recommended, premium): [HOSTING.md](HOSTING.md) (2026-10-12).
  - Required: the database (MariaDB) on a local NVMe or SSD of the game server's machine, not a network or shared
    disk (decided 2026-10-12; `innodb_flush_log_at_trx_commit` stays 1). Each autosave step's COMMIT waits for the
    disk flush on the game loop: a slow shared disk gave 0.3-0.8 s freezes. Steps: [LAUNCH.md](LAUNCH.md) section 2.
- [ ] **2 or 3 gateway VPS** with DDoS filtering in front of the game server, a DNS name with one A record per
  gateway, and a backend IP that was never public. Steps: [LAUNCH.md](LAUNCH.md) "Gateways and DDoS".
- [ ] **SMTP** for website mail: account recovery links and the website 2FA codes. Get an SMTP relay with TLS (port
  587) and fill in `site.env`: `CHAOS_SMTP_HOST`, `CHAOS_SMTP_USER`, `CHAOS_SMTP_PASSWORD` (in single quotes) and
  `CHAOS_MAIL_FROM` (e.g. `no-reply@<your domain>`). `CHAOS_SMTP_PORT=587`, `CHAOS_SMTP_TLS=starttls` and
  `CHAOS_MAIL_FROM_NAME` are already set. Add SPF, DKIM and DMARC for the From domain. Then run
  `website/install_site.sh` again. Steps: website/README.md "Mail".
- [ ] **reCAPTCHA keys:** `CHAOS_RECAPTCHA_SITE_KEY` and `CHAOS_RECAPTCHA_SECRET` in `site.env`.
- [ ] **Discord invite link** for the website and the client.
- [ ] **Payment accounts:** Mercado Pago (Pix) and PayPal, with live credentials in `payments.env`.

## Keys

- [ ] **Signed updater key ceremony.** Generate the Ed25519 key offline and keep the private key off the server. See `docs/LAUNCH.md` "Client updates".
- [ ] **Official client key.** Set the GitHub secret `CHAOS_CLIENT_KEY` and the matching server env value. See server/README.md "Client guard".

## Texts

- [ ] **Legal texts:** terms of use, privacy policy and donation terms. Drafts in Portuguese and English are in
  [docs/legal/](legal/README.md) and on the website (footer, account creation checkbox, donation page). Left for the
  owner: fill in the placeholders (name, CPF or CNPJ, contact and DPO e-mail, city, providers, prices, notice periods,
  minimum age), have a lawyer review the texts and the "Check" list of docs/legal/README.md, then run
  `website/install_site.sh` again. Donations say they are voluntary before and after payment (the site sends no mail
  after a donation).
- [ ] **Moderation record period:** pick `[PRAZO DOS REGISTROS DE MODERAÇÃO]` (Privacy Policy section 4) and set the
  same number of days in `server/data/scripts/chaos/moderation_purge_config.lua` `days` (default 730 = 2 years). The
  daily purge is built (server/README.md "Moderation record purge").
- [ ] **Rules page 7.9 on a site installed before 2026-10-12:** the installer adds the Rules page once and never
  overwrites it. Paste line 7.9 (chargeback fraud) of `website/setup/rules.bbcode` in Admin Panel > Pages > Rules.

## On the live server

- [ ] Machine timezone `America/Sao_Paulo` (`timedatectl set-timezone America/Sao_Paulo`). Weekly resets, events and the Gambler's 4-hour refresh use server time.
- [ ] `expose_php = Off` in php.ini.
- [ ] The nginx server block, the `limit_req_zone` lines and `fastcgi_param HTTPS on` from website/README.md "Web server".
- [ ] No `mock` provider in `payments.env`.
- [ ] Behind a proxy, pass the real client address through to PHP. The register limit and the login lock use it.

## Decided

- Staff rules (2026-10-12): the recommendations of docs/GM_HANDBOOK.md, now its rules. Groups: gamemasters 4, one or
  two administrators 5, owner and lead developer 6. Staff give nothing to players; refunds through an administrator.
  The ladder (over 90 days) is on the Rules page; mutes at most 24 h, bans of 30 days or more and permanent bans by an
  administrator (enforced by the admin panel). Appeals on Discord to an administrator who did not give the penalty.
  Self-reported bugs never punished; rewards case by case. Escalation levels 1-4 as in the handbook.
- Moderation records (2026-10-12): purged daily after a configurable period (`moderation_purge_config.lua`); records
  behind an open report, an active ban or a ban that ended less than 30 days ago (appeals) are kept.
- Existing accounts and the terms (2026-10-12): the website asks every account without an acceptance of the current
  texts at its next login (the same checkbox and row as sign-up, no IP); the game shows such an account a notice with
  the link at login (the client login is not held).
- Chargeback fraud (2026-10-12): coins taken back, what they bought removed, the account locked until the dispute is
  settled; fraud again: permanent, by an administrator (GM handbook ladder, Rules 7.9, Donation Terms section 6).

- Sprite pair 16 (mount rider seats): approved and pushed to `windows-assets` (1cae7c3).
- Sprite pair 17 (achievement wings): approved and pushed to `windows-assets` (854d34c).
- Rift atlas: the orb nodes stay cut about 3x (a full Hall atlas with Lone Ember lands at about 10.6x hunting orbs).
- Lone Ember and Fleeting Sanctum raise gold and item rolls, not orbs: kept.
- Guild boss orbs (3 Upheaval + 1 Fate per participant): kept.

- Crafting: when a removal fails partway, the craft gives back what that attempt took, and gives no item. This is already implemented, see server/README.md "Base crafting script".
- Rift density (2026-10-12): orbs per hour stay as they come out of the new density (tier 15: 4-5 runs an hour, up
  to +34% orbs for very fast runs). The chest orb rates are not cut.
- Instance limits (2026-10-12, server/README.md "Instance limits"): kept as built. The raid's 150 minute session, the
  Infinity Tower's 60 minute run, the 30 minute cap of the base lever boss rooms, and the 1 hour dungeon cooldown for
  a relog inside a dungeon.
- Class looks pair 19 (2026-10-12): approved and pushed to `windows-assets` (b36204f2); the six new class looks go live
  with the switch in `class_looks_core.lua`.
- maxPlayers (2026-10-12): 300 for the beta (`prod_config.py --max-players 300`), 400 at launch (the default).
- Database disk (2026-10-12): MariaDB on a local NVMe, not `innodb_flush_log_at_trx_commit = 2`. Hosting requirement
  in [LAUNCH.md](LAUNCH.md) section 2.
- Base upgrade-slot check (2026-10-12): once a second per player in 12 groups, and at once on an equip or unequip
  move, instead of every 100 ms (server/README.md "Game loop stalls").
