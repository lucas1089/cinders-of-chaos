# Cinders of Chaos website

The account site of Cinders of Chaos: accounts, character creation with the classes and the class lock, highscores,
leaderboards, patch notes, seasons, server info, rules and downloads. It is [ZnoteX](https://github.com/Open-Games-Community/ZnoteX)
(a PHP account manager for TFS servers) with our own layout and plugin on top. ZnoteX itself is never copied into this
repository: the installer clones it at a pinned commit and lays our files over it.

| Path | What it is |
|---|---|
| `install_site.sh` | installs or updates the site (idempotent) |
| `site.env.example` | the installer's settings, with the placeholders the owner fills in |
| `setup/write_config.php` | writes ZnoteX's `config.local.php` from the environment |
| `setup/chaos_setup.php` | database step: ZnoteX schema and migrations, plugin, layout, menu, Rules page |
| `setup/rules.bbcode` | the first version of the Rules page (then edited in the admin panel) |
| `setup/router.php` | router for PHP's built-in server (local tests only) |
| `overlay/layouts/chaos/` | our layout: a child of ZnoteX's purple layout "Void", re-coloured to the client |
| `overlay/plugins/chaos/` | our plugin: class names and class lock, character slots, starter depot boxes, the referral code field (`referral.php`), Leaderboards / Patch Notes / Seasons pages |
| `overlay/engine/function/chaos_password.php` | salted PBKDF2 passwords, the game server's format (see "Passwords") |
| `patches/znotex-chaos-passwords.patch` | ZnoteX's password and login code switched to it, per-account login throttling |
| `overlay/updates/.htaccess` | the client update folder: static files only, cache headers (see "Client updates") |
| `tests/chaos_password_test.php` | `php website/tests/chaos_password_test.php` (php-cli only) |
| `tests/chaos_slots_test.php` | `php website/tests/chaos_slots_test.php`: the character slot limit (php-cli only, a fake database) |
| `tests/chaos_season_modes_test.php` | `php website/tests/chaos_season_modes_test.php`: the season mode tabs and fallen marks of the Seasons page (php-cli only, a fake database) |
| `tests/chaos_referral_test.php` | `php website/tests/chaos_referral_test.php`: the referral code field (php-cli only, a fake database) |
| `overlay/plugins/chaos/pay/`, `pages/coins.php` | donations for Chaos Coins: Pix (Mercado Pago) and PayPal, the worker, the donation page (see "Donations") |
| `overlay/chaos_pay_webhook.php` | the Mercado Pago / PayPal webhook of the donations |
| `payments.env.example` | the donation settings (the credentials stay outside the repository) |
| `tests/chaos_pay_test.php`, `tests/chaos_donation_page_test.php` | the donation flow and page (php-cli with pdo_sqlite, a mocked provider) |
| `overlay/plugins/chaos/pages/reports.php`, `reports_lib.php` | staff only (the admin accounts of `CHAOS_ADMIN_ACCOUNTS`): player reports from the game (filters, close / note / reopen with a CSRF token) and the anti-bot log (server/README.md "Anti-bot and player reports"); the leaderboards leave out accounts held for an anti-bot review (`chaos_antibot_hold_sql`, only when the server's `holdLeaderboards` wrote holds) |
| `tests/chaos_reports_page_test.php` | `php website/tests/chaos_reports_page_test.php`: the reports page (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/community_lib.php`, `pages/community.php` | the community goal and the week's world modifiers (read only, from the game's `chaos_community_*` tables): a block on the front page and `page.php?plugin=chaos&p=community` (menu The World > Community) |
| `tests/chaos_community_page_test.php` | `php website/tests/chaos_community_page_test.php`: the block and the page (php-cli with pdo_sqlite) |
| `tools/recolor_layout.py` | turns Void's stylesheets into ours at install time |
| `tools/gen_site_art.py` | draws the site art and the promotion material |
| `art/` | promotion material: banners, social image, Discord banner and icon, class showcase, features infographic |

## Install

Needs git, PHP 8.1+ with mysqli, python3 and curl (or wget), and the game database with the game server's
`schema.sql` (and `server/sql/*.sql`) already imported.

```
sudo cp website/site.env.example /etc/chaos/site.env && sudo chmod 600 /etc/chaos/site.env   # fill it in
website/install_site.sh /etc/chaos/chaos.env /etc/chaos/site.env
```

`/etc/chaos/chaos.env` is the game server's settings file (`server/deploy/chaos.env.example`): the site reads its
`CHAOS_DB_HOST`, `CHAOS_DB_PORT`, `CHAOS_DB_USER`, `CHAOS_DB_PASS` and `CHAOS_DB_NAME`. Without files, the same
variables can come from the environment (`CHAOS_DB_PASSWORD` is accepted for the password too). Then point the web
server (Apache with `.htaccess`, or nginx with PHP-FPM) at `CHAOS_SITE_DIR`. Run the installer again after pulling the
repository or changing a setting; a second run changes nothing in the database.

What it does, in order:

1. **ZnoteX** is cloned shallow at the pinned commit (`ZNOTEX_COMMIT` in the script, ZnoteX 2.0.5) into
   `CHAOS_SITE_DIR`, which must be outside the repository; an existing checkout is moved to the pin.
2. **The purple layout "Void"** comes from ZnoteX's layout catalogue (branch `layouts`), pinned to a commit and
   checked against a SHA-256, and goes to `layouts/void/` (only when the pin changed).
3. **Our overlay** (`overlay/`) is copied over the checkout; `layouts/chaos/` and `plugins/chaos/` are replaced as a
   whole, so nothing else of ZnoteX is touched. `tools/recolor_layout.py` then writes the re-coloured stylesheets.
   `patches/*.patch` are applied to the checkout (skipped when already in; a ZnoteX file changed by hand stops the
   installer), see "Passwords".
4. **`config.local.php`** (mode 600; ZnoteX reads it after its own `config.php`) is written from the environment:
   database, site title "Cinders of Chaos", site URL, admin accounts, the classes, the towns, new characters, the
   download links and our plugin's settings. Credentials only ever live there and in the env files, never here.
   The web installer of ZnoteX is locked (`install/installed.lock`).
5. **The database**, with `setup/chaos_setup.php`: ZnoteX's `znote_*` tables (`CREATE TABLE IF NOT EXISTS`, seed rows
   only into empty tables), every pending ZnoteX migration (recorded with its checksum), our plugin installed and
   enabled (its `install.sql` creates `chaos_class_unlocks` if the server has not yet), the layout switched on, the
   menu entries "The World" (Server Info, Patch Notes, Leaderboards, Seasons, Rules, Community) and "Donate" (the donation page
   `page.php?plugin=chaos&p=coins`) and the Rules page added once.
   Menu entries and the Rules page are never overwritten, so the owner's edits in the admin panel stay.

Settings (`site.env.example` has them all): `CHAOS_SITE_DIR`, `CHAOS_SITE_URL`, `CHAOS_ADMIN_ACCOUNTS` (account names
with the admin panel), `CHAOS_SERVER_DATA` (the game server's `data/` folder: patch notes, season and leaderboard
settings; default `server/data` of this repository), `CHAOS_START_TOWNS`, `CHAOS_GAME_HOST`, `CHAOS_GAME_PORT`,
`CHAOS_DISCORD_URL`, `CHAOS_CLIENT_WINDOWS_URL`, `CHAOS_CLIENT_LINUX_URL`, `CHAOS_WEB_USER`, `CHAOS_LAYOUT`
(`void` shows the original purple layout), `CHAOS_DEPOT_BOXES`, `CHAOS_PASSWORD_ITERATIONS` (see "Passwords").

**Placeholders the owner sets before launch:** the site address (`CHAOS_SITE_URL`), the game address shown on the
downloads page (`CHAOS_GAME_HOST`), the client download links (empty = "Coming soon"), the Discord invite (empty =
no Discord button), the admin account names. The Rules page is a first draft to edit in Admin Panel > Pages.

Local test (what was used to check it): `php -S 127.0.0.1:8095 -t "$CHAOS_SITE_DIR" website/setup/router.php`.

## Game data

- **Classes.** `$config['vocations']` holds the 12 classes and the 9 of the three locked lines
  (`server/data/scripts/chaos/chaos_constants.lua`, `Chaos.classes.ids`): Warrior 4 / Juggernaut 8 / Berserker 14,
  Ranger 3 / Deadeye 7 / Beastmaster 15, Mystic 1 / Elementalist 5 / Illusionist 10, Thief 11 / Ninja 12 / Samurai 13,
  Monk 17 / Shadowfist 18 / Iron Sage 19, Necromancer 20 / Lich 21 / Bone Lord 22, Templar 23 / Inquisitor 24 /
  Sentinel 25. The retired ids 2, 6 and 9 show as the class they are moved to. Every class is its own highscore group
  (ZnoteX groups one promotion per base vocation, and ours have two); the class lines together are on the
  Leaderboards page (Class Ladder).
- **Character creation** offers the four base classes. The plugin adds the Monk (17), Necromancer (20) and Templar (23)
  for an account with a row in `chaos_class_unlocks` (`class_key` monk / necromancer / templar, see
  `class_unlocks_core.lua`; staff accounts of type 5+ always). It does so by narrowing `$config['available_vocations']`
  on every request before `createcharacter.php` validates the form, so a forged form for a locked class is refused by
  the server ("wrong vocation"), not only hidden. The game server checks the lock again at login.
- **New characters** are level 1 with `lastlogin = 0` and no items, at position 0,0,0 of the chosen home town: the
  server's tutorial island (`newplayer_tutorial.lua`) takes them at the first login and gives the class kit, and the
  island's exit leads to that town's temple. Home towns: `CHAOS_START_TOWNS`, checked against the `towns` table (the
  server fills it at its first start). The base server's starter depot boxes (its `ADD_DEPOT_BOXES_NEW_PLAYERS`
  snippet) are off: `!season join` needs an empty depot. `CHAOS_DEPOT_BOXES=1` puts one of each box in every town's depot.
- **Character slots.** Each account may have `characters.free` characters of the server's `pact_config.lua` (5; read
  when `CHAOS_SERVER_DATA` points at it, else 5), plus the Character Slots bought in the game store and the slots the game
  server gave once to accounts that already had more (`chaos_account_extras` keys `charSlots`, at most `maxExtra` 10, and
  `charSlotsLegacy`). The plugin sets `$config['max_characters']` to that number on every request
  (`chaos_character_limit`), so ZnoteX's `createcharacter.php` (and its API) refuse one more character on the server side;
  admins (`is_admin`) are not limited, as in ZnoteX. The page shows "Character slots: x of y used" and points to the
  store when they are all used. The game server checks the same limit at login (`pact.lua`; server/README.md "Chaos Pact
  and account storage").
- **Leaderboards** read `chaos_leaderboard` (this week's boards; week key and tie rules of `leaderboard_core.lua`),
  `chaos_leaderboard_titles` (the holders of the last scored week) and the players table (Class Ladder). Board names
  and titles come from the server's `leaderboard_config.lua` when `CHAOS_SERVER_DATA` points at it.
- **Patch notes** are the server's `data/patchnotes/*.md`, parsed with the rules of `patchnotes_core.lua` (title,
  `Date:`, intro, the New / Changes / Fixes / Balance sections and their colours, bullets, sub-bullets, bold leads,
  comments, the same limits), newest first.
- **Seasons** come from the server's `season_config.lua` (names, dates, modifier, reward track) with the
  `/season start|end` overrides of `server_config`; the season ladder reads `chaos_season_players`, with a tab per season
  mode (`&mode=all|standard|ssf|hc|hcssf|fallen`, table `chaos_season_modes`) and a skull for fallen Hardcore characters
  (also on the Leaderboards page's Class Ladder). Test: `php website/tests/chaos_season_modes_test.php` (php-cli, a fake
  database).
- **Community goal** (`community_lib.php`): the goal of the running period (`chaos_community_goal`, one bar per realm when the
  server counts Season realms separately), the stage buffs open now (`chaos_community_buffs`), the top contributors
  (`chaos_community_contrib`), the week's world modifiers (`chaos_community_week`, seeded or set by staff) and the latest stage
  and period lines (`chaos_community_history`). The game server writes every table (server/README.md "Community goals and
  the weekly world modifier"); the site only reads them, so the block shows nothing until the server has written a goal.

All plugin queries are prepared statements through ZnoteX's `db()`, none is built from request input, and every value
printed is escaped.

## Passwords

Accounts use the game server's salted password format (engine patch 0014, `server/README.md` "Account passwords"):
`pbkdf2-sha256$<iterations>$<salt base64>$<key base64>` in `accounts.password`, PBKDF2-HMAC-SHA256 with a 16-byte
`random_bytes` salt, compared with `hash_equals`. `overlay/engine/function/chaos_password.php` has the functions;
`patches/znotex-chaos-passwords.patch` points ZnoteX's code at them:

- **Writes**: registration (`user_create_account`), password change and the admin panel's reset (`user_change_password`),
  the e-mailed new password of `recovery.php`. The password is hashed as typed: ZnoteX used to hash the HTML-escaped
  form (`array_sanitize`), so a password with `< > & ' "` never worked in the game.
- **Checks**: login, the current password on the change page, `recovery.php`, the character auction, and the JSON login
  service (`login_web_service`, for 12.x clients; switched off in `config.local.php`, ours log in through the game's
  login server). An old 40-hex-digit SHA-1 still works and is replaced by a PBKDF2 hash at that login, as in the game.
  ZnoteX's website-only bcrypt copy (`znote_accounts.password_hash`) is no longer used and is cleared whenever a
  password is written, so `accounts.password` is the one password of an account.
- **Unknown accounts**: the login answers "Username and password combination is wrong." (ZnoteX said the account was
  not found) after a dummy hash of the same cost, so neither the text nor the time shows which names exist.
- **Throttling**: ZnoteX's login guard (`znote_login_attempts`) locks an IP out after 5 failures in 15 minutes; the
  patch adds a lock per account name after 10 failures from any address in 15 minutes (website login only; the game is
  not locked). Settings in `config.local.php` (`login_guard`, written by `setup/write_config.php`); the setup adds an
  index on the account name. The IP is `REMOTE_ADDR`: behind a reverse proxy every visitor has the proxy's address, so
  pass the client address through to PHP there.
- `CHAOS_PASSWORD_ITERATIONS` (default 120000) is the cost of new hashes; keep it equal to `passwordHashIterations` in
  the server's config.lua. `setup/chaos_setup.php` widens `accounts.password` to VARCHAR(255) if the server's
  `server/sql/chaos_passwords.sql` was not imported yet.
- `serverinfo.php`: ZnoteX 2.0.5 already parses config.lua values without `eval()` (`serverdata_eval_number`, digits
  and `+ - * / ( )` only), and none of our files uses `eval()`.

## Layout

ZnoteX's ready-made purple layout is **Void** (layout catalogue, by the ZnoteX authors). Ours, `layouts/chaos`, names
it as its parent in `theme.json`, so the page shell comes from Void and an update of ZnoteX or Void never touches our
folder. The changes:

- `tools/recolor_layout.py` maps every violet colour of Void's three stylesheets to the client palette
  (`client/tools/gen_theme_art.py`): near-black violets to the iron blacks (`#050405` .. `#241f27`), lavender text to
  the client's parchment (`#d6c9ae`), violet accents to crimson (`#8a1010` .. `#e03a1e`), and the named variables to
  gold (`#d9a53a`, headings `#f6cf72`). Void's brand webfonts are dropped for serif stacks.
- `assets/css/chaos.css` (appended to the last generated stylesheet) gives the windows the client's frame (iron band,
  black groove, gold trim, crimson etch) with the client's gold corner ornaments, crimson buttons with a gold edge,
  the iron menu bar, and the styles of our pages.
- The header is the client's login scene (`header.png`, from the client background), with rising embers
  (`assets/js/shadow-particles.js`) instead of violet motes; the logo is the client's CHAOS wordmark.
- Views: the home page (pitch, classes, features, latest patch notes, news), character creation as class cards,
  highscores with class names grouped by line, downloads, server info (the README for players); the right column ranks
  characters with their class badge. `locale/en.php` replaces stock texts that name another game's client.

ZnoteX's own credits stay in the footer ("Powered by ZnoteX") and on `credits.php`; ZnoteX's license is in the
installed checkout.

## Art

`python3 -I website/tools/gen_site_art.py [theme classes social discord otlist showcase features]` (Pillow + numpy).
It reuses the client generator (palette, glyph badges, CHAOS wordmark, corner ornaments, login background), so site
and client stay one look. Text uses the first serif font it finds (`CHAOS_ART_FONTS` adds folders); the committed
PNGs were drawn with Crimson Pro. All art is procedural: no screenshots, logos or third-party art.

| File | Size | Use |
|---|---|---|
| `overlay/layouts/chaos/assets/img/logo.png` | 640x300 | site logo / wordmark with the tagline |
| `overlay/layouts/chaos/assets/img/header.png` | 1280x448 | header background |
| `overlay/layouts/chaos/assets/img/favicon.png`, `apple-touch-icon.png` | 64, 180 | browser icon |
| `overlay/layouts/chaos/assets/img/frame-*.png`, `iron.png` | | window ornaments, background texture |
| `overlay/plugins/chaos/assets/img/class-*.png` | 64x64 | the 7 class badges |
| `art/social-share-1200x630.png` | 1200x630 | link preview image |
| `art/discord-banner-960x540.png`, `art/discord-icon-512.png` | 960x540, 512x512 | Discord server banner and icon |
| `art/otlist-468x60.png`, `art/otlist-88x31.png` | 468x60, 88x31 | server list banners |
| `art/class-showcase-1400x900.png` | 1400x900 | the 4 base classes and their ascensions |
| `art/features-1200x1560.png` | 1200x1560 | features infographic |

## Referral codes

The account creation form has an optional **Referral code** field (the game server's referral program, server/README.md
"Referral program"). A shared link `register.php?ref=CODE` fills it in.

- `plugins/chaos/referral.php` (loaded by `plugin.php`): reads `enabled`, `code` and `entryDays` from the server's
  `referral_config.lua` (`CHAOS_SERVER_DATA`; defaults without it), checks the posted code's format and that an account
  owns it (`chaos_referral_codes`), and after the account is created writes a `pending` row into `chaos_referrals` with the
  registration IP (`account.registered` hook). Every other rule (staff, same IP, same e-mail domain, monthly caps, bans) is
  the game server's, at the new account's first login; the player sees the result in game.
- A wrong code stops the registration with a message. ZnoteX empties `$errors` after the plugins load, so the message is
  added by our `layouts/chaos/views/register_header.php` (register.php renders it after its own checks and before it
  creates the account).
- `layouts/chaos/views/register_form.php` is ZnoteX's default form with the field added; keep it in step with
  `layouts/default/views/register_form.php` when ZnoteX is updated. With `CHAOS_LAYOUT=void` the field is not shown.
- Tables: the game server creates them (`server/sql/chaos_referral.sql`, or at its start). Without them no code can be
  found, so a filled field is refused; an empty field works as before.
- Tested on a local install (`php -S`, own database copy): the field pre-filled from `?ref=`, an unknown code refused on
  the form, a known one recorded as pending and accepted by the game server at the first login.

## Donations (Chaos Coins)

**Chaos Coins are a thank-you for a voluntary donation. Nobody is required to donate; the game is fully playable for
free.** Every payment surface says so before a pack is picked, in English and Portuguese ("Voluntary donation: it helps
keep the server running. Nobody is required to donate; the game is fully playable for free." / "Doação voluntária:
ajuda a manter o servidor. Ninguém é obrigado a doar; o jogo é totalmente jogável de graça."). The buttons say "Donate".
The Mercado Pago and PayPal descriptions say "voluntary donation". The thank-you after the donation repeats it
("Thank you for your voluntary donation! You received X Chaos Coins as a thank-you." / "Obrigado pela sua doação
voluntária! Você recebeu X Chaos Coins como agradecimento.").

Two methods: **Pix** through Mercado Pago (BRL) and **PayPal** (USD). The packs, bonuses and prices are the game
server's (`server/data/scripts/chaos/shop_coins_config.lua`): one USD table in integer cents (`usdCents`), Pix =
USD x `brlPerUsd` (5), so the two prices never drift. The game server credits every paid order (server/README.md
"Store"). Players donate in the client (Store > Donate) or on the page `page.php?plugin=chaos&p=coins` (menu entry "Donate", added by
`setup/chaos_setup.php`).

### How an order flows

1. **Order.** The client asks the game server (opcode 218, `pay_create`), or the logged-in player posts the page. A
   `pending` row goes into `chaos_coin_orders` (account, pack, method, credit preview) and `chaos_coin_payments`
   (amount in cents and currency from the server config, a random token). Limits: one open donation per account, six
   started per hour, the starter pack once (the same rules in `shop_payments_core.lua` and `pay/Service.php`).
2. **Charge.** The game server has no HTTPS client, so the **worker** (`plugins/chaos/pay/worker.php`, a systemd
   service) makes the charge. Pix: Mercado Pago `POST /v1/payments` (`X-Idempotency-Key` = token, 30-minute
   `date_of_expiration`, the account's e-mail as `payer.email`, which Mercado Pago requires; passed through, not stored
   again). PayPal: `POST /v2/checkout/orders` (item category DONATION, `PayPal-Request-Id` = token). It stores the Pix
   copy-and-paste code or the PayPal approval link and the expiry, and marks the order `open`. The page makes the
   charge itself at once.
3. **QR code.** The client draws the QR code of the Pix code (or of the PayPal link, which it also opens in the browser)
   with widgets (`game_shop/qrcode.lua`). It shows the copy-and-paste text with a Copy button and a countdown, and asks
   for the order's state every 3 s.
4. **Confirmation.** The provider calls `chaos_pay_webhook.php`. Mercado Pago: `x-signature`, HMAC-SHA256 with the
   webhook secret over `id:<data.id>;request-id:<x-request-id>;ts:<ts>;`. PayPal: `POST /v1/notifications/verify-webhook-signature`
   with the transmission headers and the webhook id. A bad signature is refused (401), an id we never charged too (404).
   The charge is then **fetched again** from the provider (`GET /v1/payments/{id}`, `GET /v2/checkout/orders/{id}`;
   PayPal is captured here once the payer approved). It is checked against the order: provider id, our token, amount in
   cents, currency, status approved. Only then the order becomes `paid`, with one conditional UPDATE, so a repeated
   webhook changes nothing. The worker checks open orders every `CHAOS_PAY_RECONCILE_SECONDS` too: a lost webhook only
   delays.
5. **Coins.** The game server sees the `paid` row within 3 s (`shop_payments.lua` poll). It credits it in one transaction
   (`shop.lua` re-reads the row locked first) and pushes the thank-you: toast and balance in the client, no relog.
6. **Ends.** Not paid by the expiry: `expired` (checked once more first, then cancelled at the provider). Cancelled by
   the player: `cancelled` (a Mercado Pago charge is cancelled; a PayPal order is simply never captured). A refund or
   chargeback before crediting: `refunded`. After crediting: flagged on the row; the game server takes back the coins
   still unspent (`removeCoinsOnReversal`) and staff see it in the admin panel (Store > Donations: refunds and
   chargebacks). No charge after 10 minutes (worker down): `failed`.

The provider is an adapter (`plugins/chaos/pay/Provider.php`: create, fetch, capture, cancel, webhook). Mercado Pago,
PayPal and a mock are the three classes. Another PSP (another Pix provider, for example) is one more class and one more
case in `bootstrap.php`. The hook `chaos_coin_order_paid` (`lib.php`) stays for payments confirmed elsewhere; staff record
a donation by hand with the admin panel (Store > Record a donation).

### Setup

1. Accounts, the operator's own: a **Mercado Pago** account with Pix keys and an application with the Payments API; a
   **PayPal Business** account and a REST app. docs/LAUNCH.md "Donations" has the legal notes (taxes, refund policy,
   PayPal's donation category) and the go-live checklist.
2. Credentials **never** go into the repository or the web root. Copy `website/payments.env.example` to
   `/etc/chaos/payments.env` (owner root, group www-data, mode 640; another path in `CHAOS_PAY_ENV`) and fill it in:

   | Variable | What |
   |---|---|
   | `CHAOS_PAY_PIX_PROVIDER` | `mercadopago`, `mock` or `off` |
   | `CHAOS_PAY_PAYPAL_PROVIDER` | `paypal`, `mock` or `off` |
   | `CHAOS_MP_ACCESS_TOKEN`, `CHAOS_MP_WEBHOOK_SECRET` | Mercado Pago access token, webhook secret |
   | `CHAOS_MP_NOTIFICATION_URL`, `CHAOS_MP_SIGNATURE_TOLERANCE` | optional: per-payment notification URL; max age of a signature in s |
   | `CHAOS_PAYPAL_CLIENT_ID`, `CHAOS_PAYPAL_CLIENT_SECRET`, `CHAOS_PAYPAL_WEBHOOK_ID` | PayPal app credentials and its webhook's id |
   | `CHAOS_PAYPAL_ENV`, `CHAOS_PAYPAL_CATEGORY`, `CHAOS_PAYPAL_BRAND` | `sandbox` / `live`; `DONATION` / `DIGITAL_GOODS`; the name on PayPal's page |
   | `CHAOS_PAY_SITE_URL` | the site address for PayPal's return links (default `CHAOS_SITE_URL`) |
   | `CHAOS_PAY_PAYER_EMAIL` | Pix payer e-mail for accounts without one, with `{account}` (e.g. `donor+{account}@your-domain`) |
   | `CHAOS_PAY_RECONCILE_SECONDS`, `CHAOS_PAY_LOG` | how often open orders are checked (60); log file (order ids and amounts only) |
   | `CHAOS_PAY_MOCK_*` | the mock provider (tests and demos only) |

   A variable in the real environment wins over the file. The webhook and the worker read the same file.
3. Webhook URLs, set in each dashboard: `https://<site>/chaos_pay_webhook.php?psp=mercadopago` (Mercado Pago, topic
   Payments) and `https://<site>/chaos_pay_webhook.php?psp=paypal` (PayPal events CHECKOUT.ORDER.APPROVED,
   PAYMENT.CAPTURE.COMPLETED / DENIED / PENDING / REFUNDED / REVERSED, CUSTOMER.DISPUTE.CREATED). Without `psp` the
   endpoint tells the provider by its headers.
4. The worker: `server/deploy/chaos-payworker.service` (`worker.php --site /var/www/chaos --loop`, a round every 2 s).
   Cron works too (`* * * * * www-data php /var/www/chaos/plugins/chaos/pay/worker.php --site /var/www/chaos --once`),
   but then the QR code can take up to a minute to appear. `--status` prints the methods that are on.
5. Tables: `chaos_coin_orders` and `chaos_coin_payments` (`install.sql`, `server/sql/chaos.sql`; the game server also
   creates them at startup).

**Mock mode** (`CHAOS_PAY_*_PROVIDER=mock`): no network, no money. A charge approves itself after
`CHAOS_PAY_MOCK_APPROVE_AFTER` seconds (Pix: a well-formed EMV code with its CRC; PayPal: a fake link, then captured).
`worker.php --mock-refund <order id>` / `--mock-dispute <order id>` simulate a refund or chargeback after crediting.
Never on a live server.

**Tests** (php-cli with pdo_sqlite, no network, no credentials): `php website/tests/chaos_pay_test.php` (prices, order
rules, the charge requests, signatures good / bad / missing, unknown ids, amount / currency / reference checks,
idempotency, expiry, cancel, refunds and chargebacks before and after crediting, PayPal capture, the mock, the settings
loader); `php website/tests/chaos_donation_page_test.php` (the page: the notice in both languages before the packs,
"Donate" and never "Buy", a Pix donation, the thank-you, the history labelled "Donation", CSRF);
`php website/tests/chaos_coins_test.php`.

## Client updates

The client's signed updater (client/MANIFEST.md "Signed updater", docs/LAUNCH.md "Client updates") downloads from a
plain static folder of the site. Nothing in it runs on the server: no PHP, no database.

```
<CHAOS_SITE_DIR>/updates/.htaccess                 (from overlay/, Apache: static only, cache headers)
<CHAOS_SITE_DIR>/updates/live/manifest.json         the signed manifest, the only file that changes per update
<CHAOS_SITE_DIR>/updates/live/files/ab/ab12...ef    one file per distinct content, named by its SHA-256
```

The client's `init.lua` points at `https://<site>/updates/live/manifest.json` (`Services.update.manifest`,
`client/tools/set_update_config.py`). Publish with `client/tools/make_update_manifest.py build <client> --out
<CHAOS_SITE_DIR>/updates/live --key <private key outside the site and the repository>`: it copies new blobs first and
writes `manifest.json` last, so a client never sees a manifest whose files are not there yet. Old blobs can stay
(clients in the middle of an update still find them); delete blobs no manifest names any more after a day or two.

- **HTTPS only in production.** The manifest is signed and every file is hash-checked, so a changed file is refused
  anyway, but HTTPS keeps the update private and stops a network from cutting it off. The client warns in its log when
  the manifest URL is plain HTTP; `client/tools/serve_updates.py` (plain HTTP, local) is for tests only.
- **Range requests** must work (Apache and nginx serve them for static files by default): the large `Tibia.spr` is
  fetched in 8 MB parts, in parallel, and an interrupted download resumes. Files over 512 MB cannot come in one piece.
- **Caching**: `manifest.json` no-cache; blobs `immutable` (their name is their hash). A CDN in front is fine.
- nginx (the `.htaccess` is Apache only):

```
location ^~ /updates/ {
    location ~ \.(php|phtml|phar)$ { deny all; }
    location ~ /manifest\.json$ { add_header Cache-Control "no-cache"; default_type application/json; }
    location ~ /files/[0-9a-f]{2}/[0-9a-f]{64}$ { add_header Cache-Control "public, max-age=31536000, immutable";
                                                  default_type application/octet-stream; }
    autoindex off;
}
```

`install_site.sh` copies `overlay/updates/.htaccess` and never touches `updates/live/`.

## Not done / for later

- The outfit images of ZnoteX (an external image service) are off; turn them on in `config.local.php` if wanted.
- Achievements (`chaos_achievements`) and name plate titles have no page yet.
- Other languages: the layout's wording is English only (the language selector is off).
