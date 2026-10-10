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
| `overlay/plugins/chaos/` | our plugin: class names and class lock, character slots, starter depot boxes, Leaderboards / Patch Notes / Seasons pages |
| `overlay/engine/function/chaos_password.php` | salted PBKDF2 passwords, the game server's format (see "Passwords") |
| `patches/znotex-chaos-passwords.patch` | ZnoteX's password and login code switched to it, per-account login throttling |
| `tests/chaos_password_test.php` | `php website/tests/chaos_password_test.php` (php-cli only) |
| `tests/chaos_slots_test.php` | `php website/tests/chaos_slots_test.php`: the character slot limit (php-cli only, a fake database) |
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
   menu entries "The World" (Server Info, Patch Notes, Leaderboards, Seasons, Rules) and the Rules page added once.
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
  `/season start|end` overrides of `server_config`; the season ladder reads `chaos_season_players`.

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

## Chaos Coins

The packs, their bonuses and the one-time starter and first-purchase bonuses live in the game server's
`server/data/scripts/chaos/shop_coins_config.lua`; the server decides every number and credits every order
(server/README.md "Store"). The site only shows them and records paid orders:

- Page `page.php?plugin=chaos&p=coins` (`plugins/chaos/pages/coins.php`): the packs with coins, bonus, total and price,
  the first-purchase bonus and, for a logged-in account, whether it and the starter pack are still open. No menu entry
  yet: payments are not open.
- Hook `chaos_coin_order_paid($accountId, $packKey, $provider, $providerRef)` (`plugins/chaos/lib.php`): call it from a
  payment provider's confirmed-payment callback, after checking the provider's signature there. It writes a `paid` row
  into `chaos_coin_orders` (`install.sql`; unique per provider and reference, so a repeated callback writes nothing); the
  game server credits it within 30 s. **No payment provider is connected and no credentials are here.** Until one is,
  staff record a payment by hand with the in-game admin panel (Store > Record a paid coin order).
- `php website/tests/chaos_coins_test.php` checks that the site reads the packs as the server credits them.

## Not done / for later

- The outfit images of ZnoteX (an external image service) are off; turn them on in `config.local.php` if wanted.
- Achievements (`chaos_achievements`) and name plate titles have no page yet.
- Other languages: the layout's wording is English only (the language selector is off).
