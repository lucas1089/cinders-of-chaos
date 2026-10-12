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
- [ ] **Staff rules.** Groups, ban and mute ladder, what staff may never do: [docs/GM_HANDBOOK.md](GM_HANDBOOK.md)
  (draft, decisions marked "Owner decides").

## Accounts and services

- [ ] **Domain.** The site address must be `https://...` (`CHAOS_SITE_URL`).
- [ ] **Hosting with DDoS protection** for the game server, the website and the database.
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

- [ ] **Legal texts:** terms of use, privacy policy and donation terms. Donations must say they are voluntary, before and after payment.

## On the live server

- [ ] Machine timezone `America/Sao_Paulo` (`timedatectl set-timezone America/Sao_Paulo`). Weekly resets, events and the Gambler's 4-hour refresh use server time.
- [ ] `expose_php = Off` in php.ini.
- [ ] The nginx server block, the `limit_req_zone` lines and `fastcgi_param HTTPS on` from website/README.md "Web server".
- [ ] No `mock` provider in `payments.env`.
- [ ] Behind a proxy, pass the real client address through to PHP. The register limit and the login lock use it.

## Decided

- Sprite pair 16 (mount rider seats): approved and pushed to `windows-assets` (1cae7c3).
- Sprite pair 17 (achievement wings): approved and pushed to `windows-assets` (854d34c).
- Rift atlas: the orb nodes stay cut about 3x (a full Hall atlas with Lone Ember lands at about 10.6x hunting orbs).
- Lone Ember and Fleeting Sanctum raise gold and item rolls, not orbs: kept.
- Guild boss orbs (3 Upheaval + 1 Fate per participant): kept.

- Crafting: when a removal fails partway, the craft gives back what that attempt took, and gives no item. This is already implemented, see server/README.md "Base crafting script".
