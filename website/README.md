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
| `overlay/plugins/chaos/` | our plugin: class names and class lock, character slots, starter depot boxes, the referral code field (`referral.php`), Leaderboards / Patch Notes / Seasons pages, Creator Codes and the Character Bazaar |
| `overlay/engine/function/chaos_password.php` | salted PBKDF2 passwords, the game server's format (see "Passwords") |
| `patches/znotex-chaos-passwords.patch` | ZnoteX's password and login code switched to it, per-account login throttling |
| `patches/znotex-chaos-escape-output.patch` | guild names, ranks, MOTD and member names (`guilds.php` and its views, `topguilds`) and the character comment (`characterprofile.php`) escaped on output (see "Web server") |
| `patches/znotex-chaos-ratelimit-ipv6.patch` | the login guard counts an IPv6 address by its /64 network (see "Passwords") |
| `overlay/plugins/chaos/session_guard.php` | a logged-in session ends when the account's password changes (see "Passwords") |
| `patches/znotex-chaos-unused-callbacks.patch` | `pagseguro_retorno.php` and `payment_webhook.php` answer 404 (see "Not used on this server") |
| `overlay/.htaccess`, `overlay/special/.htaccess` | Apache 2.4 rules: ZnoteX's character rule plus deny rules for every internal folder and file (see "Web server") |
| `overlay/plugins/chaos/register_guard.php` | the per-IP limit of account creation (see "Account creation") |
| `overlay/plugins/chaos/mail_lib.php`, `recovery_lib.php`, `recovery_page.php` | the site's one mail sender (SMTP, off without settings) and account recovery by a one-time link (see "Mail") |
| `patches/znotex-chaos-recovery-mail.patch` | `recovery.php` hands over to our recovery page; ZnoteX's `Mail` class sends through our sender (see "Mail") |
| `tests/chaos_mail_test.php`, `tests/chaos_recovery_test.php` | `php website/tests/chaos_mail_test.php` / `chaos_recovery_test.php`: the SMTP settings from the environment, mail off, the sender with a fake transport; the recovery answers, limits, link, token and notice (php-cli with pdo_sqlite, no network) |
| `tests/chaos_escape_patch_test.php` | `php website/tests/chaos_escape_patch_test.php`: every line of the escape patch rendered with malicious guild / rank / MOTD / comment values (php-cli only) |
| `tests/chaos_site_security_test.php` | `php website/tests/chaos_site_security_test.php`: `config.local.php` (Secure cookie, HSTS, CSP, reCAPTCHA, PayGol secret), the `.htaccess` and router deny rules, the web root clean-up (php-cli only) |
| `tests/chaos_register_guard_test.php` | `php website/tests/chaos_register_guard_test.php`: the registration limit, the generic e-mail message, reCAPTCHA on the form (php-cli only) |
| `overlay/updates/.htaccess` | the client update folder: static files only, cache headers (see "Client updates") |
| `tests/chaos_password_test.php` | `php website/tests/chaos_password_test.php` (php-cli only) |
| `tests/chaos_slots_test.php` | `php website/tests/chaos_slots_test.php`: the character slot limit (php-cli only, a fake database) |
| `tests/chaos_season_modes_test.php` | `php website/tests/chaos_season_modes_test.php`: the season mode tabs and fallen marks of the Seasons page (php-cli only, a fake database) |
| `tests/chaos_referral_test.php` | `php website/tests/chaos_referral_test.php`: the referral code field (php-cli only, a fake database) |
| `overlay/plugins/chaos/pay/`, `pages/coins.php` | donations for Chaos Coins: Pix (Mercado Pago) and PayPal, the worker, the donation page (see "Donations") |
| `overlay/chaos_pay_webhook.php` | the Mercado Pago / PayPal webhook of the donations |
| `payments.env.example` | the donation settings (the credentials stay outside the repository) |
| `tests/chaos_pay_test.php`, `tests/chaos_donation_page_test.php` | the donation flow and page (php-cli with pdo_sqlite, a mocked provider) |
| `overlay/plugins/chaos/creator_lib.php`, `pages/creator.php` | creator codes: a donor's pick, the creator's totals, the administrators' codes, the account's referral link (see "Creator codes") |
| `tests/chaos_creator_test.php` | `php website/tests/chaos_creator_test.php`: settings from `creator_codes_config.lua`, picks (unknown, off, own code), totals, the admin check and actions, the referral link (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/bazaar_lib.php`, `pages/bazaar.php`, `bazaar_worker.php` | the Character Bazaar: character auctions for Chaos Coins with escrow, fee and transfer (see "Character Bazaar") |
| `tests/chaos_bazaar_test.php` | `php website/tests/chaos_bazaar_test.php`: every blocked listing, bids and escrow, the fee and the transfer, expiry, buyout, cancel, a failed transfer, coins kept whole (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/discord_lib.php`, `discord_worker.php` | Discord announcements: posts the game's queued events and the bazaar's new auctions and sales to channel webhooks from the environment (see "Discord announcements") |
| `tests/chaos_discord_worker_test.php` | `php website/tests/chaos_discord_worker_test.php`: the worker against a mock webhook endpoint (a local `php -S`): embeds, no pings, 429 and rate limit headers, retries, switches, the bazaar scan, cleanup; the downloads page's Discord step (php-cli with pdo_sqlite, nothing leaves the machine) |
| `overlay/plugins/chaos/telemetry_lib.php`, `pages/telemetry.php` | staff only (admin accounts with a group 5+ character): balance telemetry charts, server-drawn SVG (see "Balance telemetry") |
| `tests/chaos_telemetry_page_test.php` | `php website/tests/chaos_telemetry_page_test.php`: access, filters, rates and the small-group rule, every section, the SVG charts (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/pages/reports.php`, `reports_lib.php` | staff only (the admin accounts of `CHAOS_ADMIN_ACCOUNTS`): player reports from the game (filters, close / note / reopen with a CSRF token) and the anti-bot log (server/README.md "Anti-bot and player reports"); the leaderboards leave out accounts held for an anti-bot review (`chaos_antibot_hold_sql`, only when the server's `holdLeaderboards` wrote holds) |
| `tests/chaos_leaderboards_page_test.php` | `php website/tests/chaos_leaderboards_page_test.php`: the Leaderboards page, fastest-time boards ranked lowest first and shown as m:ss, the class tabs of the byClass boards (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/pages/notused.php` | the short note shown instead of the stock pages this server does not use (see "Not used on this server") |
| `tests/chaos_notused_page_test.php` | `php website/tests/chaos_notused_page_test.php`: which stock pages are sent away and the note for each (php-cli only) |
| `tests/chaos_reports_page_test.php` | `php website/tests/chaos_reports_page_test.php`: the reports page (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/botreview_lib.php`, `pages/botreview.php` | staff only (admin accounts with a group 4+ character): flagged bot-review days with signals, explanations and timeline; mark reviewed / false positive / escalate, note, request a presence check. Escalated days need group 5 (server/README.md "Bot detection") |
| `tests/chaos_botreview_page_test.php` | `php website/tests/chaos_botreview_page_test.php`: access, list, day view, actions and CSRF |
| `overlay/plugins/chaos/community_lib.php`, `pages/community.php` | the community goal and the week's world modifiers (read only, from the game's `chaos_community_*` tables): a block on the front page and `page.php?plugin=chaos&p=community` (menu The World > Community) |
| `overlay/plugins/chaos/chronicle_lib.php`, `pages/chronicle.php` | the Ashen Chronicle (read only, from the game's `chaos_chronicle_*` tables): the running season's chapters with goal bars and top contributors, and the record of past seasons, at `page.php?plugin=chaos&p=chronicle` (menu The World > Chronicle); names follow the Memorial choice (`chaos_memorial_optin.records`) |
| `overlay/plugins/chaos/memorial_lib.php`, `pages/memorial.php` | the Capital Memorial (read only, from `chaos_memorial_entries`, rows with `shown` = 1 only): realm firsts, records and the fallen of a season, and the archive of past seasons (`&s=<season key>`), at `page.php?plugin=chaos&p=memorial` (menu The World > Memorial) |
| `tests/chaos_community_page_test.php` | `php website/tests/chaos_community_page_test.php`: the block and the page (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/guildwar_lib.php`, `pages/guildwars.php` | the guild wars declared in game (read only, from the game's `chaos_guildwar` / `chaos_guildwar_kills`): `page.php?plugin=chaos&p=guildwars` (menu The World > Guild Wars): the running wars (score, terms, time left) and the latest ended ones (winner, gold won, end reason, kills the anti-farming rules did not count); see server/README.md "Guild wars in game" |
| `tests/chaos_guildwars_page_test.php` | `php website/tests/chaos_guildwars_page_test.php`: the wars page (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/mentor_lib.php`, `pages/mentors.php` | the mentors who opted in (card, class, graduates, free places) and the totals, read only from the game's `chaos_mentor*` tables: `page.php?plugin=chaos&p=mentors` (menu The World > Mentors; see "Mentors") |
| `overlay/plugins/chaos/legal_lib.php`, `pages/legal.php` | the legal pages: Terms of Use, Privacy Policy, Donation Terms in Portuguese and English, from `docs/legal/` (see "Legal pages") |
| `tests/chaos_legal_pages_test.php` | `php website/tests/chaos_legal_pages_test.php`: the pages, the renderer's escaping, the footer links, the Terms checkbox and its refusal, the acceptance row, the donation notes before and after payment (php-cli only, a fake database) |
| `tests/chaos_legal_accept_test.php` | `php website/tests/chaos_legal_accept_test.php`: existing accounts accept the current texts: the gate (which requests pass), the way back (this site only), the form (token, checkbox), the row (no IP), a new version asking again, the setup writing the version for the game (php-cli only, SQLite in memory) |
| `overlay/chaos_client_api.php`, `overlay/plugins/chaos/client_api_lib.php` | the game client's account API: character looks for the character select, character creation in the client (see "Client API") |
| `overlay/engine/function/chaos_character.php`, `patches/znotex-chaos-character-create.patch` | the character creation checks and insert of ZnoteX's `createcharacter.php`, moved unchanged into two functions that the form and the client API both call (see "Client API") |
| `tests/chaos_client_api_test.php` | `php website/tests/chaos_client_api_test.php`: the API's login, state and creation with every refusal (bad and taken names, locked class, slots, bad token, Terms, season mode, replays, the login guard, the hourly and per-minute limits, a password change), the patch moving the form's lines unchanged, and the class look table against `class_looks_core.lua` (php-cli with pdo_sqlite) |
| `tests/chaos_mentors_page_test.php` | `php website/tests/chaos_mentors_page_test.php`: the Mentors page (php-cli with pdo_sqlite) |
| `overlay/plugins/chaos/wiki_lib.php`, `pages/wiki.php`, `wiki/` | the player wiki: guides in Portuguese and English, the reference generated from the server data by `server/tools/gen_wiki_data.lua`, the search (see "Wiki") |
| `tests/chaos_wiki_page_test.php` | `php website/tests/chaos_wiki_page_test.php`: every wiki page in both languages, the guides, search, escaping and 404s (php-cli only) |
| `tools/recolor_layout.py` | turns Void's stylesheets into ours at install time |
| `tools/gen_site_art.py` | draws the site art and the promotion material |
| `tools/gen_sprite_images.py`, `tools/sprite_owners.csv` | item and outfit images drawn from our client pair at install time, only our art (see "Sprite images") |
| `overlay/chaos_outfit.php`, `overlay/plugins/chaos/sprite_lib.php` | outfit images with the player's colours, addons and mount; item image URLs; the wiki's real sprites (see "Sprite images") |
| `tests/chaos_sprites_test.php`, `tools/gen_sprite_images_test.py` | `php website/tests/chaos_sprites_test.php` (php-cli, zlib only): URLs, placeholder fallback, request values, colours, drawing, cache, wiki; `python3 -I website/tools/gen_sprite_images_test.py`: the colour maths on hand-made masks and a synthetic pair |
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
   `CHAOS_SITE_DIR`, which must be outside the repository; an existing checkout is moved to the pin. Its git data
   is kept **outside the web root** (`CHAOS_SITE_GIT_DIR`, default `/var/www/.chaos.znotex.git` for `/var/www/chaos`);
   a `.git` folder left in the site by an older installer is moved there.
2. **The purple layout "Void"** comes from ZnoteX's layout catalogue (branch `layouts`), pinned to a commit and
   checked against a SHA-256, and goes to `layouts/void/` (only when the pin changed).
3. **Our overlay** (`overlay/`) is copied over the checkout; `layouts/chaos/` and `plugins/chaos/` are replaced as a
   whole, so nothing else of ZnoteX is touched. `tools/recolor_layout.py` then writes the re-coloured stylesheets.
   `patches/*.patch` are applied to the checkout (skipped when already in; a ZnoteX file changed by hand stops the
   installer), see "Passwords" and "Web server". PHPMailer (ZnoteX's mail library, a composer package it does not
   ship) goes to `vendor/phpmailer/phpmailer/`: three source files and its license at a pinned commit, each checked
   against a SHA-256 (see "Mail").
4. **`config.local.php`** (mode 600; ZnoteX reads it after its own `config.php`) is written from the environment:
   database, site title "Cinders of Chaos", site URL, admin accounts, the classes, the towns, new characters, the
   download links and our plugin's settings. Credentials only ever live there and in the env files, never here.
   The web installer of ZnoteX is locked (`install/installed.lock`).
5. **The database**, with `setup/chaos_setup.php`: ZnoteX's `znote_*` tables (`CREATE TABLE IF NOT EXISTS`, seed rows
   only into empty tables), every pending ZnoteX migration (recorded with its checksum), our plugin installed and
   enabled (its `install.sql` creates `chaos_class_unlocks` if the server has not yet), the layout switched on, the
   menu entries "The World" (Server Info, Patch Notes, Leaderboards, Seasons, Rules, Community, Guild Wars, Mentors, Character
   Bazaar, Creator Codes) and "Donate" (the donation page
   `page.php?plugin=chaos&p=coins`), "Player Reports" (staff only, under ZnoteX's Admin Panel entry) and the Rules page
   added once. ZnoteX's own entries of the pages we do not use (Shop, Buy points, Library > Creatures / Spells,
   Community > Forum, and Library, then empty) are switched off once, on a fresh install and at the next run on an
   existing one (marker `chaos:stock_menu_hidden` in `znote_config`).
   Menu entries and the Rules page are never overwritten, so the owner's edits in the admin panel stay.
6. **The web root is cleaned**: ZnoteX's `tests/`, `tools/`, `docker/`, docker and composer files, dot files and the
   `special/` maintenance scripts are deleted from the site (a ZnoteX update brings them back, the next run deletes
   them again). `SQL/` (read by the setup and the admin panel's migrations), `Lua/` and `install/` stay and are denied
   by the web server rules (see "Web server").

Settings (`site.env.example` has them all): `CHAOS_SITE_DIR`, `CHAOS_SITE_URL`, `CHAOS_ADMIN_ACCOUNTS` (account names
with the admin panel), `CHAOS_SERVER_DATA` (the game server's `data/` folder: patch notes, season and leaderboard
settings; default `server/data` of this repository), `CHAOS_START_TOWNS`, `CHAOS_GAME_HOST`, `CHAOS_GAME_PORT`,
`CHAOS_DISCORD_URL`, `CHAOS_CLIENT_WINDOWS_URL`, `CHAOS_CLIENT_LINUX_URL`, `CHAOS_WEB_USER`, `CHAOS_LAYOUT`
(`void` shows the original purple layout), `CHAOS_DEPOT_BOXES`, `CHAOS_PASSWORD_ITERATIONS` (see "Passwords"),
`CHAOS_SITE_GIT_DIR`, `CHAOS_RECAPTCHA_SITE_KEY` / `CHAOS_RECAPTCHA_SECRET` and `CHAOS_REGISTER_PER_IP_HOUR` (see
"Account creation"), `CHAOS_SMTP_*` and `CHAOS_MAIL_FROM*` (see "Mail").

**Placeholders the owner sets before launch:** the site address (`CHAOS_SITE_URL`), the game address shown on the
downloads page (`CHAOS_GAME_HOST`), the client download links (empty = "Coming soon"), the Discord invite (empty =
no Discord button), the admin account names. The Rules page is a first draft to edit in Admin Panel > Pages.

Local test (what was used to check it): `php -S 127.0.0.1:8095 -t "$CHAOS_SITE_DIR" website/setup/router.php`.
The router stands in for the `.htaccess` deny rules; it is for local tests only.

## Web server

ZnoteX keeps its internals in the web root and protects them with `.htaccess` files, which nginx ignores. The site is
hardened on both servers:

- **Not in the web root at all**: ZnoteX's git data (`CHAOS_SITE_GIT_DIR`), `tests/`, `tools/`, `docker/`, the docker
  and composer files and the `special/` scripts (`database2znoteaac.php` and the others ran database conversions for
  anyone who reached them). See "Install", steps 1 and 6.
- **Denied**: `SQL/`, `Lua/`, `install/`, `engine/backups/` (the admin panel's database backups are written there),
  `engine/cache/`, `vendor/`, dot files, `composer.*`, `docker-compose*`, `config.local.php` and files ending in
  `.sql .md .lock .dist .example .bak .yml .env .log .phar`. Apache: `overlay/.htaccess` (Apache 2.4 syntax, copied
  over ZnoteX's root `.htaccess` and keeping its character-name rule) and `overlay/special/.htaccess`
  (`Require all denied`; ZnoteX's own used the 2.2 `allow from localhost` form). ZnoteX's `plugins/.htaccess` and
  `layouts/.htaccess` (no PHP or data files served from there) stay. nginx: the server block below.
- **Output escaping**: `patches/znotex-chaos-escape-output.patch` escapes the guild names (also inside the guild rows'
  `onclick`), MOTD, rank names, nicks and member names of `guilds.php` and its views, the guild names of `topguilds`
  and the character comment of `characterprofile.php`. A value the site already stored escaped is not escaped twice.
- **Headers** (`setup/write_config.php`, sent by ZnoteX on every PHP page): `Content-Security-Policy` (`default-src
  'self'`, images also `data:` and `https:`, YouTube frames for the news BBCode, Google's reCAPTCHA hosts when it is
  on, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `frame-ancestors 'self'`),
  `X-Content-Type-Options: nosniff`, `Referrer-Policy: strict-origin-when-cross-origin`, `X-Frame-Options`.
  **Documented compromise**: `script-src` (and `style-src`) keep `'unsafe-inline'`, because the parent layout Void
  and ZnoteX's pages and admin panel have inline scripts and `onclick` handlers that are not ours to rewrite. The
  policy still blocks scripts from other hosts, plugins, `<base>` hijacking and framing; the escaping above is what
  stops injected inline code.
- **HTTPS**: with `CHAOS_SITE_URL=https://...` the session cookie is `Secure` and HSTS is on (one year). ZnoteX sends
  HSTS only when PHP sees an HTTPS request, so behind a TLS proxy set `fastcgi_param HTTPS on;` (nginx) or
  `SetEnvIf X-Forwarded-Proto https HTTPS=on` (Apache), and pass the client address on (see "Passwords").
- **PHP**: `expose_php = Off` in the php.ini of PHP-FPM / Apache (`/etc/php/8.x/fpm/php.ini`), so no
  `X-Powered-By: PHP/...`; the `.htaccess` and the nginx block also drop the header. Keep `display_errors = Off`.

nginx with PHP-FPM (replace the names, paths and the PHP version; the `limit_req_zone` lines go in the `http {}`
block, e.g. `/etc/nginx/conf.d/chaos-limits.conf`):

```
limit_req_zone $binary_remote_addr zone=chaos_webhook:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=chaos_forms:10m rate=30r/m;

server {
    listen 80;
    server_name www.example.org;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name www.example.org;
    ssl_certificate     /etc/letsencrypt/live/www.example.org/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/www.example.org/privkey.pem;

    root /var/www/chaos;
    index index.php;
    server_tokens off;
    autoindex off;
    client_max_body_size 2m;

    # static files; PHP pages send these themselves (hidden from PHP below so they are not doubled)
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # never served (the same list as overlay/.htaccess); the regex blocks come before the PHP block on purpose
    location ^~ /.well-known/acme-challenge/ { default_type text/plain; }
    location ~ /\. { deny all; }
    location ~ ^/(SQL|Lua|tests|tools|docker|special|install|engine/(backups|cache)|vendor)(/|$) { deny all; }
    location ~ (^|/)(composer\.[^/]*|docker-compose[^/]*|Dockerfile|config\.local\.php)$ { deny all; }
    location ~ \.(sql|md|lock|dist|example|bak|yml|yaml|env|log|phar)$ { deny all; }
    # ZnoteX's plugins/.htaccess and layouts/.htaccess: only assets are served from these folders
    location ~ ^/(plugins|layouts)/.*\.(php|phtml|php[0-9]|inc|sql|json|md|txt|ya?ml|ini|log|bak|dist|example)$ { deny all; }

    # the client updates (README "Client updates")
    location ^~ /updates/ {
        location ~ \.(php|phtml|phar)$ { deny all; }
        location ~ /manifest\.json$ { add_header Cache-Control "no-cache"; default_type application/json; }
        location ~ "/files/[0-9a-f]{2}/[0-9a-f]{64}$" { add_header Cache-Control "public, max-age=31536000, immutable";
                                                        default_type application/octet-stream; }
        autoindex off;
    }

    # the donation webhook: each PayPal call makes the site call PayPal back, so limit it per address
    location = /chaos_pay_webhook.php {
        limit_req zone=chaos_webhook burst=20 nodelay;
        limit_req_status 429;
        include snippets/chaos-php.conf;
    }
    # the client's account API (README "Client API"; it also limits itself per address, account and minute)
    location = /chaos_client_api.php {
        limit_req zone=chaos_forms burst=10 nodelay;
        limit_req_status 429;
        include snippets/chaos-php.conf;
    }
    # account creation and login (the site also limits these itself; this keeps floods off PHP)
    location ~ ^/(register|login|recovery)\.php$ {
        limit_req zone=chaos_forms burst=10 nodelay;
        limit_req_status 429;
        include snippets/chaos-php.conf;
    }
    location ~ \.php$ {
        include snippets/chaos-php.conf;
    }

    # any other path is a character name (ZnoteX's rewrite rule)
    location / {
        try_files $uri $uri/ @character;
    }
    location @character {
        rewrite ^/(.*)$ /characterprofile.php?name=$1 last;
    }
}
```

`/etc/nginx/snippets/chaos-php.conf`:

```
try_files $uri =404;
fastcgi_split_path_info ^(.+\.php)(/.+)$;
include fastcgi_params;
fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
fastcgi_param HTTPS on;            # TLS ends at this server or at a proxy in front: Secure cookie and HSTS from PHP
fastcgi_hide_header X-Powered-By;
fastcgi_hide_header X-Content-Type-Options;   # sent by the server block for every response
fastcgi_hide_header Referrer-Policy;
fastcgi_hide_header X-Frame-Options;
fastcgi_hide_header Strict-Transport-Security;
fastcgi_pass unix:/run/php/php8.3-fpm.sock;
```

`expose_php` is set in php.ini (it cannot be changed per request); the `fastcgi_hide_header` line makes sure the
header never leaves nginx even where php.ini was not changed. Behind a TLS proxy (a load balancer or a CDN
in front of this nginx) keep `HTTPS on` and add `set_real_ip_from <proxy address>; real_ip_header X-Forwarded-For;`
to the server block, so `REMOTE_ADDR` is the visitor's address.

## Account creation

- **Limit per address**: at most 3 accounts per IP address per hour (`CHAOS_REGISTER_PER_IP_HOUR`, 0 = no limit; an
  IPv6 address counts by its /64). `plugins/chaos/register_guard.php` counts the accounts created in
  `chaos_web_registrations` (`install.sql`; rows older than a day are deleted) and the refusal reaches register.php's
  errors through our `register_header` view, before anything is created. The address is `REMOTE_ADDR`, as for the
  login lock (pass the client address on behind a proxy). With `CHAOS_LAYOUT=void` the limit is not applied (the
  view is ours).
- **reCAPTCHA** (v2 checkbox): on when `CHAOS_RECAPTCHA_SITE_KEY` and `CHAOS_RECAPTCHA_SECRET` are both set in
  `site.env` (keys from https://www.google.com/recaptcha/admin, domain = the site's). ZnoteX checks it on the
  account creation form and our recovery page on its form (see "Mail"); our forms load Google's script (ZnoteX's
  never did, so the widget was missing) and the CSP allows Google's hosts then. Needs PHP's curl and openssl extensions (ZnoteX stops otherwise).
- **E-mail**: a taken and a malformed e-mail address get the same answer, "Please use another e-mail address."
  (`locale/en.php`), never "already in use". A taken address still cannot be used twice, so someone who tries many
  addresses can still tell; the limit per address and reCAPTCHA make that slow.

## Legal pages

The Terms of Use, the Privacy Policy and the Donation Terms. Drafts: a lawyer reviews them before launch, and the
owner fills in the placeholders (docs/legal/README.md lists both).

- **Source**: `docs/legal/<doc>.<lang>.md`, doc `terms`, `privacy` or `donations`, lang `pt-BR` (prevails) or `en`.
  `install_site.sh` copies them to `plugins/chaos/legal/` after the overlay (the `.md` deny rule keeps them from being
  served raw) and warns while placeholders such as `[NOME DO RESPONSÁVEL]` are left.
- **Page**: `page.php?plugin=chaos&p=legal&doc=terms|privacy|donations`, Portuguese by default, `&l=en` for English
  (not `lang`, which is ZnoteX's own switch). Tabs for the three texts and the other language. `legal_lib.php` renders
  the Markdown subset the texts use (headings, paragraphs, lists, tables, bold, links); every value is escaped, a link
  goes only to another legal text, a site path (`/...`) or an `https://` address, and a placeholder left in is marked.
- **Links**: the copyright line of every page's footer (`locale/en.php` `void.footer.copyright`, so an edited theme
  footer text keeps them), the account creation form, the donation page and the Rules page (section 8).
- **Account creation**: `register_form.php` has the checkbox "I accept the Terms of Use and the Privacy Policy" (with
  the Portuguese text and the note for under-18s). A post without it gets an error through our `register_header`
  view (as the referral code and the per-IP limit), so register.php creates nothing. With it, the
  `account.registered` hook writes `chaos_legal_acceptance` (`install.sql`: account, version = the first 16 hex digits
  of the SHA-256 of the three Portuguese texts, time; no IP). With `CHAOS_LAYOUT=void` the checkbox and the check are
  not there (the views are ours).
- **Donations**: before payment the donation page adds to the voluntary notice, in English and Portuguese: no right to
  a refund except where the law requires one, not the purchase of a product, Chaos Coins have no real-world value, and
  a link to the Donation Terms. A paid or credited order repeats that it was a voluntary donation and not a purchase. The
  site sends no mail after a donation.
- **Existing accounts**: an account logged in without a `chaos_legal_acceptance` row for the current version (the beta
  accounts made before the checkbox; everyone after the texts change, Terms section 10) is sent by `plugin.php` to
  `page.php?plugin=chaos&p=accept&next=<page>` before any other page (303). The page has the same checkbox and links as
  account creation, a CSRF token, and writes the same row (account, version, time; no IP); then back to the page the
  player wanted (a page of this site only, else `myaccount.php`), or "log out" without accepting. Not gated: the accept
  page, the legal texts, `login.php`, `logout.php`, `register.php`, `recovery.php`, `chaos_pay_webhook.php` and the
  background endpoints listed by path in `chaos_legal_xhr_endpoints()` (the admin panel's updater). An
  `X-Requested-With` header alone passes nothing: any client can send it. `setup/chaos_setup.php` writes the version to the game's `server_config`
  (`chaos_legal_version`); the game server shows an account without it a notice with the link at login
  (server/README.md "Terms acceptance notice"), since the game login cannot be held for a web form.
- Test: `php website/tests/chaos_legal_pages_test.php`, `php website/tests/chaos_legal_accept_test.php`.

## Wiki

A player wiki: short guides and a reference of everything the game has, generated from the server data.

- **Page**: `page.php?plugin=chaos&p=wiki`, Portuguese by default, `&l=en` for English (as the legal pages). `&t=` picks a
  topic: `guide:<slug>`, `tab:<tab id>` or an entry id (`class:warrior`, `spell:254`, `tree:96`, `rift:atlas`, ...). The
  index lists the guides and the reference tabs; every page has breadcrumbs and a link to the other language. An
  unknown topic answers 404. `pages/wiki.php` draws it, `wiki_lib.php` does the rest.
- **Search**: `&q=`, on the server, over the guides of the page's language and every reference entry. Case and accents
  do not matter (`ascensao` finds "ascensão"); the query is cut to 60 characters, at most 40 results, each with a short
  snippet. The query and every snippet are escaped; the match is put in `<mark>` after escaping.
- **Reference data**: `plugins/chaos/wiki/wiki_data.json`, written by `server/tools/gen_wiki_data.lua` from the server's
  data files. It loads the Codex generator (`gen_codex_data.lua`) as a library for the item tabs (modifiers, powers,
  uniques, sets, orbs, gems, supports, rift modifiers and tiers, materials, basics) and adds the classes, ascensions
  and spells (the vocation XML, `spells_chaos.xml` and each spell script's first comment), the passive tree (the client
  tree: keystones, notables, masteries, Paragon), the Rift Atlas, dungeons, the Infinity Tower and the Ember Descent,
  world bosses, the raid, the Ascended Omens, the guild boss, events, the Chaos monsters that spawn somewhere, and the
  store's offers by type (cosmetic, service, convenience, boost, ...). Entries of a system behind an off switch carry
  `soon` and show "Em breve / Coming soon". The names and tables are the game's own (English) in both languages.
  Regenerate after changing server data: `cd server && luajit tools/gen_wiki_data.lua`; CI runs it with `--check`
  under LuaJIT and Lua 5.3 (the same bytes), so a stale file fails the build.
- **Guides**: `plugins/chaos/wiki/guides/<slug>.<pt-BR|en>.md`, the list and titles in `chaos_wiki_guides()`. A small
  Markdown subset: `#` title, `##` headings, paragraphs, `-` lists, `**bold**`, `_italic_`, links to `wiki:<topic>`,
  `legal:<doc>`, `page:<plugin page>`, a site path or `https://` (anything else stays plain text). `{{key}}` is a number
  of the generated `facts` (so a guide never quotes a stale number), and a block between `::: if key` and `::: end`
  shows only while that fact is true; otherwise it reads "em breve / coming soon". The `.md` deny rule keeps them from
  being served raw.
- **Links**: a top-level menu entry "Wiki" (`setup/chaos_setup.php`, added once), the footer's copyright line
  (`locale/en.php`) and the home page's "Read the guide" button.
- **Layout**: the `.chaos-wiki*` rules of `layouts/chaos/assets/css/chaos.css`; on a phone the cards stack, the search
  field and button stack, and wide tables scroll inside their frame.
- Test: `php website/tests/chaos_wiki_page_test.php` (every guide in both languages, their facts and links, every
  guide, tab and entry page in both languages, breadcrumbs, search, escaping, 404s, no PHP notices).

### Wiki art

Icons, hero images and banners make the wiki easier to scan. `server/tools/gen_wiki_data.lua` decides what shows what
(the single source); `website/tools/gen_wiki_art.py` draws it.

- **Data**: every tab and entry of `wiki_data.json` has an `icon` (a path under `plugins/chaos/assets/`), every tab a
  `banner` and a `tone`, and `art.guides` gives each guide a hero image, an emblem, the icons around it and a tone.
  `art.steps` names the icons the guides may use in steps (`@key`, `@bench`, ...) and the callout icons.
- **Images**: `python3 -I website/tools/gen_wiki_art.py` writes `assets/wiki/i/*.png` (48 px icons, 64 px for the pixel
  art items) and `assets/wiki/hero/*.webp` (guide heroes 960x300, tab banners 960x180) and removes images nothing names
  any more; `--check` fails on a stale or extra file (CI, with the pinned Pillow and numpy of the other art checks);
  `--sheet OUT.png` writes a contact sheet of every icon. Run it after `gen_wiki_data.lua` when an icon changes.
- **Sources**, all our own committed art: the Chaos spell icon kit (`client/tools/gen_spell_icons.py`), the painted spell
  icons and painted keystones and masteries (`gen_painted_icons.py`), the support runes (`gen_support_icons.py`), the
  themed set item pieces (`client/tools/sprites/art_import/theme/items_<set>.png`), the client's top menu buttons, the
  site's class badges and backdrop (`gen_site_art.py`); orbs and gems are drawn by the script. A unique's icon is a themed
  piece of its slot, an illustration and not the item's own sprite. No screenshots: the client's screens show base
  sprites, the base game's art, which is never published (donor art is shown only as sprites, see "Sprite images"). No text in the images, so both languages use the same files.
- **Rift art** (`website/tools/wiki_rift_art.py`, imported by `gen_wiki_art.py`): every rift icon is painted for what it
  is, not taken from the spell icon kit. Shapes are masks shaded by a height field lit from the upper left, on one
  framed plate: a modifier's motif says what it does (read from its key; `rm-<side>-<key>`), the frame says who it hits
  (prefix crimson: the monsters, suffix violet: the players or the ground, boon gold: a reward); Rift Keys per tier
  (`rk-<tier>`: the tier band's gem and metal, pips for the tier inside the band); the torn rift, the rift chest
  spilling orbs, the Atlas star map, the shared lives, the Omen Key and fragment, each Omen's emblem and its Ascended
  form; a vignette per rift theme (`rt-*`); Rift Atlas nodes as star map medallions in the branch's colour with the
  node's glyph (`an-*`). Guardian portraits (`rg-*`) and the pack of `rx-clear` are crops of our own rift looks, kept
  as a snapshot in `website/tools/wiki_art_src/rift_creatures.png` (`gen_wiki_art.py import-creatures` refreshes it from
  `client/tools/sprites/art_import/big_bosses/` and `rift_variants/`), so a repaint there never makes `--check` fail.
  The real sprite of a unique, a set or a store offer is drawn only from our own art (see "Sprite images").
  The data adds `icons` to a table section (one per row, shown in its first cell): the key of each rift tier, the Atlas
  nodes, the omens, and the new entry `rift:themes` (themes and guardians).
- **Guides**: a callout box is `> [tip] text`, `> [warn] text` or `> [note] text` (more `> ` lines continue it); a step
  diagram is a run of lines `=> icon | title | text`, the icon `@name` (`art.steps`), an entry id or `tab:<id>`. Steps
  show as a row of numbered cards on a computer and a vertical list on a phone.
- **Page**: guide heroes on top of each guide and as thumbnails on the index cards, tab banners on the tab pages, icons in
  the tab lists, the index, search results, the entry heading and the first cell of every table row that links an entry.
  Every image has alt text, a width and height and `loading="lazy"` (the hero at the top of a page loads at once).

## Sprite images

Item and outfit images for the character page, the online list, the highscores, the wiki (uniques, sets, store offers)
and ZnoteX's item slots, drawn from our own client pair. ZnoteX's own outfit and item image services stay unused.

- **Build** (static, at install time): `tools/gen_sprite_images.py --dat --spr [--otb] --publish --out-dir` reads the
  pair with `client/tools/sprites/datspr.py` and writes `<site>/chaos-sprites/`: `items/<server id>.png` (the item as the
  client draws it alone: all layers, phase 0, count 1; stackables also `-c2` ... `-c50` for the client's stack patterns,
  fluid containers `-f1` ... `-f8` for the client fluid colours), `outfits/<look>.png` (a layer sheet: idle group,
  phase 0, facing south, one column per addon and mount pattern, the art row and the colour template row),
  `outfits/<look>.raw` (the same sheet for PHP: zlib of u16 width, u16 height, RGBA rows), two placeholders and `index.json` (what is ours, each look's
  size, displacement, patterns and rider seat). The server's `items.otb` maps server ids to client ids; without it only
  the items of our manifests (`server/data/items/*.csv`) are known. `--preview DIR` writes contact sheets.
- **Install**: `install_site.sh` step 3d, only when `CHAOS_SPRITE_PAIR` (a folder with `Tibia.dat` and `Tibia.spr`) is
  set; `CHAOS_SPRITE_OTB` defaults to `$CHAOS_SERVER_DATA/items/items.otb`. Rebuilt only when the pair, the otb, the
  setting, the tool or the owners table changed (key in `chaos-sprites/.chaos-key`), into a new folder that is then
  swapped in. Needs python3-numpy and python3-pil on the machine that runs it (about 10 s, under 10 MB). Without a pair
  nothing is built and the outfit images stay off, as before.
- **Why static plus a small renderer**: the pair (600 MB) never goes to the web server and PHP never parses it; the
  build reads it once with the tools the client pipeline already trusts. Items are plain files. Outfits cannot all be
  pre-drawn (133^4 colour choices), so `chaos_outfit.php` colours the pre-cut sheets of one look per request: clamped
  integer parameters only, no database, no ZnoteX bootstrap, PNG out. A render takes a few milliseconds and is cached
  in `engine/cache/chaos-outfits/` (denied by the web server rules; at most 20,000 files, then rendered without
  caching; cleared when the set is rebuilt). PHP needs only zlib: it reads the `.raw` sheets and writes the PNG itself
  (no gd, whose 7-bit alpha would change semi-transparent pixels).
- **Colours**: as the client draws a creature: the template layer's exact yellow / red / green / blue pixels select
  head / body / legs / feet, and the art under them is multiplied by that outfit colour (`(v * c + 127) / 255`); the
  colour table is the client's 19 hues x 7 shades (`outfit_colour`, the same as `client/tools/sprites/compose_outfit.py`);
  addon patterns 1 and 2 are drawn over pattern 0 when worn; a mount is drawn under its rider in the rider's mounted
  pattern, placed as `Outfit::draw` with client base patch 0034 does (rider seat of negative-displacement mounts). The
  idea comes from open-tibia-library (Gesior, MIT); this follows its documented method (four-colour template mask,
  colour table, addon layers). No code of it was read for this or copied. PHP and Python give the same pixels (418 renders
  of every published look, 225 of them mounted, byte for byte).
- **Mounts, checked in our client** (2026-10-13; base patches 0001-0050, pair things_custom23, Xvfb, a 9x9 map at 2x,
  the local player's outfit set by Lua, facing south): each part of our render was found in the screenshot by pixel
  match. Frame top-left relative to the tile, rider / mount: rider 2073 on stock 368: -32,-32 / -32,-32; on 1561:
  -26,-44 / -32,-64; on 2132: -26,-48 / -32,-64; on 2133: -26,-42 / -32,-64; on 2134: -26,-50 / -64,-64; on 2135:
  -26,-48 / -32,-96 (the same for rider 2161; 2173, with no displacement, 8 px right and down). All 18 rider and mount pairs are where
  the renderer puts them. A look without a mounted pattern rides nothing, in the client too. On the donor mounts the
  rider sits high on the back seen from the front: that is the seat of things_custom16 (client/MANIFEST.md "Rider
  seat on donor mounts"), the same in game.
- **Only our art** (`tools/sprite_owners.csv`, client id ranges from client/MANIFEST.md, theme_things.csv, the class looks
  and the monster look sources): `own` (drawn for the project or licensed to it: the dark tiles, the October art sets,
  pouches, fist weapons, themed sets, auras and wings), `donor` (donor-library art the project picked and ships in the
  client: class looks, monster, boss, faction and wings looks, donor B items) and `stock` (the base pair: the commercial
  game's art and the base client's additions, also our recolours or templated copies of it). A later row of the table
  wins, so exceptions follow their range. `CHAOS_SPRITE_PUBLISH` picks the tiers drawn: `own,donor` (default), `own` or
  `all`. Anything not drawn is a neutral placeholder of our own (a dim slot, a grey hooded figure): stock art never
  leaves the pair. **Decision** (owner, 2026-10-13: own,donor): donor art is shown on the website as it is in the public
  client; stock art never (`all` is not used).
- **Where**: `setup/write_config.php` points ZnoteX's `show_outfits` (character page, online list, highscores) at
  `/chaos_outfit.php` and the item images (character equipment, shop) at `/chaos-sprites/items/<id>.png` when the set is
  installed; our highscores view has an outfit column. The wiki: `gen_wiki_data.lua` adds `sprite` ({item: server id})
  to every unique and set and `sprites` to the store's offer tables (items, outfits with addons, mounts, bundle and
  plate icons); `wiki_lib.php` shows the real sprite when it is ours and keeps the themed icon otherwise (today most
  uniques are stock items, so they keep their themed icon; Grasp of the Pyre Saint shows its own).
- **Not done**: walking animations (one standing frame only), other directions, the item's own count or fluid on
  ZnoteX pages (they ask for `<id>.png`).
- nginx: `chaos_outfit.php` is an ordinary PHP script (the `\.php$` block); to keep floods off PHP add
  `limit_req_zone $binary_remote_addr zone=chaos_img:10m rate=30r/s;` and
  `location = /chaos_outfit.php { limit_req zone=chaos_img burst=100 nodelay; include snippets/chaos-php.conf; }`.
- Test: `php website/tests/chaos_sprites_test.php`, `python3 -I website/tools/gen_sprite_images_test.py` (CI); the
  `live-pair` CI job builds the set from the live pair.

## Mail

The site sends mail for **account recovery** (a one-time link) and the **e-mail login codes** of ZnoteX's website 2FA
(only when a player turns them on). Nothing else: no activation mail at registration (the game never checks it, and a
lost mail would lock the website login), no e-mail check on the account page, no newsletters.

**Settings** (`site.env`, written into `config.local.php` by `setup/write_config.php`; `site.env.example` has
placeholders only):

| Variable | What |
|---|---|
| `CHAOS_SMTP_HOST` | the SMTP relay's host name. **Empty = no mail**: the recovery page says recovery by e-mail is not available, nothing ever connects |
| `CHAOS_SMTP_PORT` | 587 (default) for `starttls`, 465 (default for `tls`) |
| `CHAOS_SMTP_TLS` | `starttls` (default, port 587), `tls` (TLS from the first byte, port 465) or `none` (only for a relay on this machine: `localhost`) |
| `CHAOS_SMTP_USER`, `CHAOS_SMTP_PASSWORD` | the relay's login (many providers use an API key as the password); put the password in single quotes |
| `CHAOS_MAIL_FROM` | the From address, e.g. `no-reply@<your domain>`: a domain you own, set up as below |
| `CHAOS_MAIL_FROM_NAME` | the From name (default "Cinders of Chaos") |

Wrong values stop the installer with a message (unknown TLS mode, `none` to a remote host, no or a malformed From
address, a line break in a value, a password without a user); the password is never printed. The password lives only in
`site.env` and `config.local.php` (mode 600). With mail off, ZnoteX's e-mail login codes are off too.

**Provider.** Any SMTP relay with TLS and authentication works: a transactional mail service, the mail service of the
domain, or a local relay that forwards to one. Most VPS hosts block outgoing port 25, so use 587 (STARTTLS) or 465. Do
not send from a free personal mailbox: its domain does not allow mail from your server, so recovery mails land in spam.

**DNS of the From domain** (the owner adds these; the provider shows the exact values):

- **SPF**: one TXT record on the domain, e.g. `v=spf1 include:<provider's SPF domain> -all` (one SPF record only;
  merge with an existing one).
- **DKIM**: the TXT or CNAME record(s) the provider gives (`<selector>._domainkey.<domain>`), so mails are signed.
- **DMARC**: TXT on `_dmarc.<domain>`, e.g. `v=DMARC1; p=quarantine; rua=mailto:dmarc@<domain>` (start with `p=none`
  for a week and read the reports if unsure).
- A reverse DNS (PTR) name only matters for a relay on your own server.

Check: request a recovery link for your own account on the live site; the mail's headers should show `spf=pass`,
`dkim=pass` and `dmarc=pass`.

**How it is built.**

- `plugins/chaos/mail_lib.php` is the one sender (`chaos_mail_send`): PHPMailer over SMTP, 15 s timeout, our From
  address, no mailer header, line breaks stripped from the subject and names, a failure logged to PHP's error log
  without the password. `patches/znotex-chaos-recovery-mail.patch` makes ZnoteX's `Mail` class call it, so the 2FA
  codes use the same settings. PHPMailer comes from `vendor/` (installer step 3); `vendor/` is denied by the web server
  rules.
- **Recovery** (`recovery.php`; the patch hands the whole page to `plugins/chaos/recovery_page.php`, so none of ZnoteX's
  modes runs: they mailed a plain new password, reset a password from a GET link with a 9-digit key that never expired,
  told which entries matched, and built links from the request's Host header):
  1. The player enters an account name or e-mail address. The answer is always the same: "If an account matches what
     you entered, we sent an e-mail ...". Unknown names, unknown addresses, accounts without an address and accounts
     over their mail limit all get it. Under PHP-FPM the answer goes out before the mail is sent, so the time does not
     tell either.
  2. Each matching account with an e-mail address (an address shared by several accounts: up to 3) gets a link
     `<CHAOS_SITE_URL>/recovery.php?reset=<token>`: 32 random bytes, only their SHA-256 stored in
     `chaos_password_resets`, valid **30 minutes**, **once**. A new request replaces the account's older link. The
     link uses `CHAOS_SITE_URL`, never the Host header. The mail names the account (so it also recovers a lost account
     name) and says "Cinders of Chaos".
  3. Opening the link shows a form (a mail scanner that opens it changes nothing). Posting the new password (6 to 29
     characters, as at account creation) uses the token up with one conditional UPDATE (two posts at once: one wins),
     writes the password with `user_change_password` (salted PBKDF2, hashed as typed; see "Passwords") and sends a
     notice "your password was changed" to the account address.
- **Limits** (`chaos_recovery_requests`, rows older than a day deleted): 5 requests per address per hour (IPv6 by /64,
  `REMOTE_ADDR` as for the login lock; the answer then says to try again later), 3 links per account per hour (silent:
  the same answer). nginx's `chaos_forms` zone already limits `recovery.php` (see "Web server"). reCAPTCHA is on the
  form when the site has it (`CHAOS_RECAPTCHA_*`); a failed check records nothing and sends nothing. The form carries
  ZnoteX's CSRF token. The page sends `Cache-Control: no-store` and `Referrer-Policy: no-referrer`.
- Not done: no notice mail after a password change on the account page (ZnoteX has none; only after a reset).
- Tests: `php website/tests/chaos_mail_test.php`, `php website/tests/chaos_recovery_test.php`.

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
  The client creates characters through the same checks (see "Client API").
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
  and titles come from the server's `leaderboard_config.lua` when `CHAOS_SERVER_DATA` points at it; boards of mode `min`
  (the fastest Cinderheart kills and Sepulchre clears) rank the lowest value first and `format = "time"` shows m:ss, as
  in the client. A board with `byClass = true` (the three Cinderheart boards) has class tabs as in the client
  (`&class=<base class id>`): "All classes" first, then one tab per base class with its ascensions (the retired ids
  2, 6, 9 with the class they move to), ordered by the base class id like `LB.classGroups`, each ranked again from 1.
  The site filters by the character's class now (`players.vocation`); the game counts the class at the kill, which
  differs only for a character that ascended during the week.
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

## Not used on this server

ZnoteX ships pages this server has no use for. They stay in the checkout (nothing of ZnoteX is deleted) but are off:

- **Shop, Buy points** (and `payment.php`): the store and Chaos Coins are in the game; donations are the Donate page.
  **The stock payment callbacks** `paygol_ipn.php`, `ipn.php`, `pagseguro_ipn.php`, `pagseguro_retorno.php` and
  `payment_webhook.php`: off. ZnoteX's `paygol_ipn.php` credited points to any account for a GET that only repeated
  the stock secret (`xxxx-xxxx-xxxx-xxxx`) and service id, whatever `paygol.enabled` said, and `pagseguro_ipn.php`
  wrote log rows for anyone. The first three load plugins and are sent to the note below before they read anything;
  `pagseguro_retorno.php` and `payment_webhook.php` never load plugins, so `patches/znotex-chaos-unused-callbacks.patch`
  makes them answer 404 at their first line. `config.local.php` also gets a random 64-hex-digit PayGol secret on every
  run, and PayGol, PagSeguro and the stock PayPal are switched off. Our donations use `chaos_pay_webhook.php` only.
  **Library > Creatures, Spells**: the client has the Bestiary and the Spellbook. **Forum** (and `forum_search.php`):
  there is none; the stock forum also printed PHP warnings when empty. Houses stay.
- Their menu entries are switched off by `setup/chaos_setup.php` (see "Install", step 5).
- `setup/write_config.php` sets `$config['shop']['enabled']`, `buypoints_enabled`, `forum.enabled`,
  `forum.guildboard`, `paygol.enabled`, `pagseguro.enabled` and `paypal.enabled` to false, and `houseConfig.shopPoints`
  (buying a house with points) off.
- A direct link to one of them (`chaos_unused_pages()` in `lib.php`, the callbacks included) is sent by the plugin to
  `page.php?plugin=chaos&p=notused&what=store|creatures|spells|forum`, a short note in our layout with the right links.
  The admin panel is not touched.
- Premium and points: there are none. `layouts/chaos/assets/css/chaos.css` hides the account header's premium badge
  and its points / premium figures, the footer's Shop link, the character page's "Account Status: Premium inactive"
  row and the staff widget's forum link; `locale/en.php` empties "You have a free account." on the account page.
  Recheck these selectors when the Void or ZnoteX pin moves.

## Passwords

Accounts use the game server's salted password format (engine patch 0014, `server/README.md` "Account passwords"):
`pbkdf2-sha256$<iterations>$<salt base64>$<key base64>` in `accounts.password`, PBKDF2-HMAC-SHA256 with a 16-byte
`random_bytes` salt, compared with `hash_equals`. `overlay/engine/function/chaos_password.php` has the functions;
`patches/znotex-chaos-passwords.patch` points ZnoteX's code at them:

- **Writes**: registration (`user_create_account`), password change and the admin panel's reset (`user_change_password`),
  the new password chosen through a recovery link (see "Mail"; ZnoteX's mailed random password is no longer used). The password is hashed as typed: ZnoteX used to hash the HTML-escaped
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
  pass the client address through to PHP there. An IPv6 address counts by its /64 network
  (`patches/znotex-chaos-ratelimit-ipv6.patch`, as the account creation limit), so one machine cannot walk through its
  addresses.
- **Accepted trade-off: the account lock can be triggered by others.** Anyone who knows an account name can lock its
  *website* login for 15 minutes with 10 wrong passwords from 2 or more addresses (one address alone is stopped by the
  IP lock after 5). The owner then waits 15 minutes or logs in to the game, which is never locked. This is kept on
  purpose: it stops password guessing spread over many addresses, and the cost to the victim is small (the website
  only; the lock ends by itself). Staff can end it early by deleting that name's failed rows in `znote_login_attempts`
  (the admin panel's Login attempts page unlocks per IP only).
- **Sessions end on a password change** (`overlay/plugins/chaos/session_guard.php`). ZnoteX ends other sessions only
  through its 2FA v2 "log out all devices", which is off here. Each logged-in session keeps a mark of the stored
  password hash and is logged out when it no longer matches: after a reset by recovery link, a change on another device
  or in the game. A rehash at login (SHA-1 to PBKDF2, a new iteration count) logs other sessions out once.
- **Not used: website 2FA.** ZnoteX's 2FA v2 is off (`twoFactorV2.enabled` false) and so is the legacy TFS token.
  If it is ever switched on: its code step has no limit on wrong codes within the 5 minutes of a pending login; add
  one before turning it on.
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
- `layouts/chaos/views/register_form.php` is ZnoteX's default form with the field added and ZnoteX's sample "Server
  Rules" replaced by a summary that links our Rules page; keep it in step with
  `layouts/default/views/register_form.php` when ZnoteX is updated. With `CHAOS_LAYOUT=void` the field is not shown.
- Tables: the game server creates them (`server/sql/chaos_referral.sql`, or at its start). Without them no code can be
  found, so a filled field is refused; an empty field works as before.
- Tested on a local install (`php -S`, own database copy): the field pre-filled from `?ref=`, an unknown code refused on
  the form, a known one recorded as pending and accepted by the game server at the first login.

## Donations (Chaos Coins)

**Packs and the first donation (2026-10-13).** The packs and prices come from the game server's `shop_coins_config.lua`
(placeholders, docs/OWNER_TODO.md): an entry pack (Handful of Coins, 80 coins, US$ 1.99 / R$ 9,95 by Pix), Pouch, Sack,
Chest, Hoard and the Vault of Coins (10,000 +30%, the anchor), Starter Coins once. The first donation of an account brings
**double coins** (`firstPurchase.bonusPct = 100`) up to +1000 extra (`firstPurchase.maxBonus`, the plugin setting
`first_bonus_max`, owner 2026-10-13: "Limite a 1000"; a pack above 1000 coins gets +1000 flat), once per account (not on the Starter Coins; a refund or chargeback
after crediting keeps the order counted, so it never repeats). The Donate page shows it; the voluntary donation wording
before and after payment is unchanged. Tests: `chaos_coins_test.php`, `chaos_pay_test.php` (also the payer hash),
`chaos_donation_page_test.php` (also the creator code field).

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
   A Mercado Pago signature older than 600 s is refused too (`CHAOS_MP_SIGNATURE_TOLERANCE`). Each PayPal check is a
   call to PayPal, so rate-limit the webhook path at the web server (see "Web server").
   The charge is then **fetched again** from the provider (`GET /v1/payments/{id}`, `GET /v2/checkout/orders/{id}`;
   PayPal is captured here once the payer approved). It is checked against the order: provider id, our token, amount in
   cents, currency, status approved. Only then the order becomes `paid`, with one conditional UPDATE, so a repeated
   webhook changes nothing. The worker checks open orders every `CHAOS_PAY_RECONCILE_SECONDS` too: a lost webhook only
   delays.
5. **Coins.** The game server sees the `paid` row within 3 s (`shop_payments.lua` poll). It credits it in one transaction
   (`shop.lua` re-reads the row locked first) and pushes the thank-you: toast and balance in the client, no relog.
6. **Ends.** Not paid by the expiry: `expired` (checked once more first, then cancelled at the provider). Cancelled by
   the player: `cancelled` (a Mercado Pago charge is cancelled; a PayPal order is simply never captured). The page's
   "Cancel this donation" link and PayPal's cancel link (`&order=N&cancel=1`) only open a confirmation; the order is
   cancelled by its POST form with the page's CSRF token, so a link alone cannot cancel a donation. A refund or
   chargeback before crediting: `refunded` (also a partial refund: Mercado Pago keeps such a payment "approved" with
   an amount refunded, which counts as a refund). After crediting: flagged on the row; the game server takes back the coins
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
   | `CHAOS_MP_NOTIFICATION_URL`, `CHAOS_MP_SIGNATURE_TOLERANCE` | optional: per-payment notification URL; max age of a signature in s (empty = 600, 0 = off) |
   | `CHAOS_PAYPAL_CLIENT_ID`, `CHAOS_PAYPAL_CLIENT_SECRET`, `CHAOS_PAYPAL_WEBHOOK_ID` | PayPal app credentials and its webhook's id |
   | `CHAOS_PAYPAL_ENV`, `CHAOS_PAYPAL_CATEGORY`, `CHAOS_PAYPAL_BRAND` | `sandbox` / `live`; `DONATION` / `DIGITAL_GOODS`; the name on PayPal's page |
   | `CHAOS_PAY_SITE_URL` | the site address for PayPal's return links (default `CHAOS_SITE_URL`) |
   | `CHAOS_PAY_PAYER_EMAIL` | Pix payer e-mail for accounts without one, with `{account}` (e.g. `donor+{account}@your-domain`) |
   | `CHAOS_PAY_RECONCILE_SECONDS`, `CHAOS_PAY_LOG` | how often open orders are checked (60); log file (order ids and amounts only) |
   | `CHAOS_PAY_MOCK_*`, `CHAOS_PAY_ALLOW_MOCK` | the mock provider (tests and demos only; see "Mock mode") |

   A variable in the real environment wins over the file. The webhook and the worker read the same file.
3. Webhook URLs, set in each dashboard: `https://<site>/chaos_pay_webhook.php?psp=mercadopago` (Mercado Pago, topic
   Payments) and `https://<site>/chaos_pay_webhook.php?psp=paypal` (PayPal events CHECKOUT.ORDER.APPROVED,
   PAYMENT.CAPTURE.COMPLETED / DENIED / PENDING / REFUNDED / REVERSED, CUSTOMER.DISPUTE.CREATED). Without `psp` the
   endpoint tells the provider by its headers.
4. The worker: `server/deploy/chaos-payworker.service` (`worker.php --site /var/www/chaos --loop`, a round every 2 s).
   Cron works too (`* * * * * www-data php /var/www/chaos/plugins/chaos/pay/worker.php --site /var/www/chaos --once`),
   but then the QR code can take up to a minute to appear. `--status` prints the methods that are on. Credited
   orders are asked again once a day for 180 days after payment (`ChaosPayService::RECHECK_DAYS`), so a refund or
   chargeback whose webhook was lost is still taken back. A second, larger refund of an order refunded in part, or a
   chargeback after it, flags the order again; the game server takes back only the difference
   (`ChaosPayCore.reversalRemaining`, `chaos_coin_payments.reversal_coins` = all coins taken back so far).
   PayPal webhooks: a call whose `PAYPAL-CERT-URL` is not https on paypal.com, or whose transmission time is more than
   6 hours from the clock, is refused before any PayPal call; the access token is kept between requests in a mode-600
   file in the system temp folder (`ChaosPayPayPal::tokenCachePath`).
5. Tables: `chaos_coin_orders` and `chaos_coin_payments` (`install.sql`, `server/sql/chaos.sql`; the game server also
   creates them at startup).

**Mock mode** (`CHAOS_PAY_*_PROVIDER=mock`): no network, no money. It only runs when the site address
(`CHAOS_PAY_SITE_URL`, else `CHAOS_SITE_URL`) is `localhost`, `127.0.0.1` or `::1`, or with `CHAOS_PAY_ALLOW_MOCK=1`.
A missing address never counts as local: `install_site.sh` refuses to run without `CHAOS_SITE_URL` and
`setup/write_config.php` no longer falls back to `http://localhost`;
otherwise the method stays off and the refusal is logged (a mock charge would credit real Chaos Coins). A charge approves itself after
`CHAOS_PAY_MOCK_APPROVE_AFTER` seconds (Pix: a well-formed EMV code with its CRC; PayPal: a fake link, then captured).
`worker.php --mock-refund <order id>` / `--mock-dispute <order id>` simulate a refund or chargeback after crediting.
Never on a live server.

**Tests** (php-cli with pdo_sqlite, no network, no credentials): `php website/tests/chaos_pay_test.php` (prices, order
rules, the charge requests, signatures good / bad / missing, unknown ids, amount / currency / reference checks,
idempotency, expiry, cancel, refunds and chargebacks before and after crediting, PayPal capture, the mock, the settings
loader); `php website/tests/chaos_donation_page_test.php` (the page: the notice in both languages before the packs,
"Donate" and never "Buy", a Pix donation, the thank-you, the history labelled "Donation", CSRF);
`php website/tests/chaos_coins_test.php`; `php website/tests/chaos_qa_security_test.php` (regressions of the security
QA: a Mercado Pago partial refund before and after crediting, a second larger refund, the daily re-check of credited
orders, the PayPal webhook pre-checks and token cache, the site address, the session guard, the terms gate's
background endpoints, the login guard's IPv6 /64).

## Creator codes

A streamer or content creator gets a code from an administrator; a donor picks it; while the pick lasts, the game server
gives the creator a share of the Chaos Coins of the donor's donations, in game (server/README.md "Creator codes": the
matching, the hold, the caps and every anti-abuse rule live there). The donor's donation and coins never change; the
page says so, and that donations are voluntary.

- `page.php?plugin=chaos&p=creator` (menu The World > Creator Codes, added by `setup/chaos_setup.php`):
  - logged in: pick a code (or stop), the current pick and until when (`supportDays`); the own code is refused
    (self-use, logged); a switched-off or unknown code is refused;
  - the account's **referral link** (`register.php?ref=CODE`, from `chaos_referral_codes`; the account gets its code in
    game at level 20);
  - a creator (an account that owns a code): its %, supporters, earned and waiting coins, the last 50 donations with the
    code (date, coins, share, state; never a name);
  - administrators (`chaos_creator_is_admin`: an admin panel account, `CHAOS_ADMIN_ACCOUNTS`, **and** a character of
    group `adminGroup`, 5): create a code for a character's account (with a shown name, its own %, a note), switch it
    off / on, set its %, read the log. Every write is a POST with the page's CSRF token; every value is escaped.
- Settings: `server/data/scripts/chaos/creator_codes_config.lua` (`sharePct` 5 is a placeholder, docs/OWNER_TODO.md).
- Tables: `chaos_creator_codes`, `chaos_creator_support`, `chaos_creator_uses`, `chaos_creator_log`, `chaos_pay_payers`
  (`install.sql`, `server/sql/chaos_creator_codes.sql`; the game server creates them too).
- **Hooks (done, 2026-10-13):**
  1. the donate page (`pages/coins.php`) has an optional "Creator code" field (form `chaos-creator-pick`, Save) that calls
     `chaos_creator_set_support($accountId, $code, REMOTE_ADDR)`; a Donate button may also carry `chaos_creator_code`,
     picked before `createOrder` (a refused code stops the donation with its message, no order is made). The page says
     the donor's pack and the first donation bonus stay the same. The client's Store > Donate tab has the same field
     (`game_shop` pay.otui `creatorCode`), sent with `pay_create {creator}`; `shop_payments.lua` checks it with the
     website's rules (`ChaosPayCore.creatorCode` / `creatorRefusal`: normalised, active, not the donor's own) and writes
     the same `chaos_creator_support` row and a `pick` log line.
  2. `pay/Service.php` writes `chaos_pay_payers` (order id, account, `ChaosPayService::payerHash(psp, payer, salt)` =
     SHA-256 of `CHAOS_PAY_PAYER_SALT|psp|payer`) when a payment is confirmed (`approved` -> paid). The payer: Mercado
     Pago's payer document (Pix: the CPF), else its payer id, else the e-mail; PayPal's payer id, else the e-mail; else
     the e-mail the charge was made with. The raw value is never stored; set `CHAOS_PAY_PAYER_SALT` once and keep it (a
     new salt makes old and new hashes differ). Skipped (logged) when the table is missing.
- Test: `php website/tests/chaos_creator_test.php`.

## Character Bazaar

Players sell characters to players for Chaos Coins on `page.php?plugin=chaos&p=bazaar` (menu The World > Character
Bazaar). The rules (`bazaar_lib.php`, class `ChaosBazaar`; numbers from the game server's `bazaar_config.lua`):

- **Listing:** a character of the logged-in account with a minimum bid (`minPrice` 100 or more), an optional buyout
  (above the minimum) and 1-7 days; at most `maxActivePerAccount` (2) auctions at once. Refused: a character online
  (`players_online`), below `minLevel` (50), a guild leader (`guilds.ownerid`) or vice-leader (rank level 2+), a season
  character whose season runs (`chaos_season_players.migrated_at = 0`), a Hardcore or Self-Found character
  (`chaos_season_modes`, not reset), a staff character (group > 1), one with an open player report (`chaos_reports`, bug
  reports aside), an account with an active ban (`account_bans`) or a chargeback or dispute in `chargebackDays` (180),
  a character already listed. The "Sell a character" tab lists every character with the reasons it cannot be listed.
  While listed the character cannot log in (the game server's lock, server/README.md "Character Bazaar").
- **Bids:** the amount is taken from the bidder's `chaos_shop_coins` at once and held on the bid row (`escrow`); an
  outbid bidder gets it back at once. The next bid beats the current one by `minStepPct` (5) % and at least `minStep`
  (10). A bid in the last `snipeMinutes` (5) moves the end. A bid at or over the buyout buys at the buyout price and ends
  the auction at once. Refused: the seller's own account, a banned account, one with a chargeback, one without a free
  character slot (the same limit as character creation), more than `maxBidsPerAccountHour` (20) bids. Each bid row keeps
  the bidder's address for staff.
- **End** (the page and the cron worker, `bazaar_worker.php`): no bid: `expired`. Otherwise the listing becomes
  `settling`, the checks run again (offline, still the seller's, not a leader, the winner has a slot and is not banned),
  then in one transaction: the winning bid's escrow is spent, `players.account_id` moves to the winner, the character
  leaves its guild, the seller gets the price less the fee (`feePct`, 8, a placeholder in the 5-10 range; the fee leaves
  the economy), the listing is `sold`. If a check fails the listing is `failed` and the escrow goes back.
- **Cancel:** the seller before the first bid; an administrator (admin panel account with a group 5+ character) at any
  time with a reason (Administration tab). Every escrow goes back.
- **Mail:** the seller's account e-mail (its security e-mail) is told when its character is listed, sold, expired,
  failed or cancelled; the winner when it wins; an outbid bidder when outbid (mail_lib.php, off without SMTP).
- **Safety:** every coin move is a conditional UPDATE in a transaction (`ChaosPayDb` of `pay/Db.php`, mysqli with the
  site's credentials): a balance drops only when it holds the amount, a listing takes a bid only if its leading bid is
  still the one the bidder saw. Writes are POSTs with the page's CSRF token; output is escaped; prepared statements only.
- **Cron:** `* * * * * www-data php <site>/plugins/chaos/bazaar_worker.php --site <site>` ends auctions on time when
  nobody opens the page.
- **One open listing per character**, held by the database: `active_player_id` is generated (`player_id` while
  `active` or `settling`, else NULL) with a unique key, so two list requests at once cannot both insert; the second gets
  "already listed". Cancel, sale, expiry and failure set NULL, so the character can be listed again. On an existing
  table `setup/chaos_setup.php` adds the column once (MySQL 5.7+ / MariaDB 10.2+); a character listed twice before
  keeps its oldest listing and the others are cancelled by the staff path (escrow refunded).
- **At most `maxActivePerAccount` open listings per seller**, held by the database too: each listing takes a
  `seller_slot` (1..max) and the generated `active_seller_id` (`seller_account_id` while open, else NULL) has a unique
  key with it, so two characters of one account listed at once cannot both take the last slot; the loser reads the
  slots again and gets "You can run 2 auctions at once". `setup/chaos_setup.php` adds both columns and the key to an
  existing table once, giving open listings made before a slot first (`assignSellerSlots`).
- Tables: `chaos_bazaar_listings`, `chaos_bazaar_bids`, `chaos_bazaar_log` (`install.sql`, `server/sql/chaos_bazaar.sql`).
- Test: `php website/tests/chaos_bazaar_test.php`. Not run against a live site.

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
    location ~ "/files/[0-9a-f]{2}/[0-9a-f]{64}$" { add_header Cache-Control "public, max-age=31536000, immutable";
                                                    default_type application/octet-stream; }
    autoindex off;
}
```

`install_site.sh` copies `overlay/updates/.htaccess` and never touches `updates/live/`.

## Client API

The game client's character select talks to the site through one endpoint, `chaos_client_api.php` (site root, POST,
JSON in and out, `Cache-Control: no-store`, a body of at most 8 KB). The client's URL setting is `Services.account` in
its `init.lua` (client base patch 0050, `client/tools/set_account_api.py`, docs/LAUNCH.md); empty turns it off and
characters are then created here only. The logic is `plugins/chaos/client_api_lib.php`; the endpoint loads ZnoteX as
a page does (database, settings, the plugin's hooks). `CHAOS_CLIENT_API=0` in `site.env` switches it off (answer 503).

| Action | Body | Answer |
|---|---|---|
| `login` | `account`, `password`, `nonce` | a session `token` (`expiresIn` 1800 s) and the state |
| `state` | `token` | the state: the account's character `looks` (look type, colours, addons, wings, aura, shader name, level, class, last login, season tag) and `account` (Terms accepted, the accept page, slots used and allowed, the seven class lines with `locked` and each line's class look for both sexes, towns, the name rules, the running season with its modes) |
| `create` | `token`, `nonce`, `name`, `vocation`, `sex`, optional `town`, `season`, `mode`, `hardcore` | `name` (as stored) and its `look`, or `errors` |
| `logout` | `token` | the token ends |

**Why the website, not a game packet.** The 10.98 login server has no creation, and every creation rule already lives
here: ZnoteX's name rules and limits, the class lock and the character slots of our plugin, the Terms. A login server
packet would have meant a second copy of all of it in C++. The looks come from here too: the login server's 10.98
character list carries the look type, colours and addons (base patch 0025 reads them), but not the wings, aura and
shader, which the base server keeps in `players.wings_id`, `aura_id` and `shader_id` (its login / logout scripts); a
change of the list's packet would break every client of the old format at once, an HTTPS call breaks nothing.

**The same checks as the form.** `patches/znotex-chaos-character-create.patch` moves the lines of `createcharacter.php`
that check and create a character, unchanged, into `engine/function/chaos_character.php`
(`chaos_character_form_errors`, `chaos_character_create`); the page calls them, the API calls them. So both refuse
the same names (letters and spaces, `minL`-`maxL` letters, at most `maxW` words, no one-letter word, the restricted
words and creature names, a taken name), a class outside `available_vocations` (the API narrows it to the account's
class lock, as `plugin.php` does for a logged-in page; a locked line gets a clear "locked for your account" message),
a town or sex that does not exist, one character more than `max_characters` (the account's slots) and a bad IP. Only
the form's CSRF token is the page's own. The `character.created` hook runs for both (class look, depot boxes).
On top, the API refuses an account without the acceptance of the current Terms (403 with the accept page's URL: the
player accepts once on the site) and checks the season choice: only the season running now, a mode of
`season_config.lua` `modes.list`, Hardcore modes only with `hardcore: true` (the client's "I understand").
A banned account (an active `account_bans` row: `expires_at` 0 is permanent, else until `expires_at`, as the game
server reads it) gets no token: `login` answers 403 `banned` with the end (`until`) and the reason, told only after the
right password. `create` with a token issued before the ban answers the same and ends the account's tokens.

**Season at creation.** A season choice writes `chaos_season_requests` (player, season, mode). The game server
carries it out at the character's first login with its own join (`season.lua` `S.applyRequest`: `S.joinCheck`, the
join, the mode; server/README.md "Seasons"), so its caches and rules stay the only ones; the row is deleted either
way and a request the server can no longer honour (the season ended, `CHAOS_DEPOT_BOXES=1` left items in the depot)
is explained to the player.

**New characters wear their class look.** ZnoteX writes its starter outfit (look type 128 / 136) into every new
character; the game server put the class look on only at the first login, so the client's character list (and the
site) showed the same plain citizen for every character not yet played. The plugin's `character.created` hook
(`chaos_apply_class_look`, `lib.php` `chaos_class_look`: `class_looks_core.lua` with its pair switches, read through
`CHAOS_SERVER_DATA`) now sets the class's look with both addons at creation, on the form and through the API. The game
server puts the same look on at the first login, so nothing changes there.

**Security.**
- HTTPS only (the web server; the client refuses an `http://` URL except 127.0.0.1 / localhost for a local test site).
- The password is checked exactly as the website login checks it: ZnoteX's login guard (5 failures per address,
  10 per account name in 15 minutes lock that address or name, shared with the website login and counted in
  `znote_login_attempts`), the dummy hash for an unknown account (same answer, about the same time), the server
  adapter's login (salted PBKDF2, an old SHA-1 still accepted), the e-mail activation when it is on.
- The client sends the password once per character select, in the login request; it is never stored by the site.
  The token is 32 random bytes; only its SHA-256 is kept (`chaos_client_tokens`) with the mark of the account's
  password hash (the session guard's): a password change, logout or 30 minutes end it.
- Replays: every login and create carries a fresh nonce (16-64 hex digits), kept two hours (`chaos_client_nonces`,
  longer than a token lives); a nonce seen twice is refused (409), so a repeated create never makes two characters.
- Floods: 30 requests per address per minute (all actions; an IPv6 address counts by its /64, as the register
  guard), 3 new characters per account and 5 per address per hour (`chaos_client_api_log`, rows older than a day
  are deleted); the nginx block above adds `limit_req`. Settings: `$config['chaos_client_api']` (`write_config.php`).
- CSRF does not apply: the API reads no cookie (ZnoteX's session cookie is ignored), the token travels in the body.
- Every query is a prepared statement; the answers are JSON (`json_encode`), nothing is printed into HTML.

Test: `php website/tests/chaos_client_api_test.php` (php-cli with pdo_sqlite: ZnoteX's functions are small stand-ins
with its behaviour). Also run against the real pinned ZnoteX with every patch applied, a local MariaDB copy of the test
server's database and the PHP built-in server (`setup/router.php`), with the Linux client (client/MANIFEST.md
"Character select").

## Mentors

`page.php?plugin=chaos&p=mentors` (menu The World > Mentors, added by `setup/chaos_setup.php`) lists the mentor
characters of the game's mentor system (server/README.md "Mentors"): only those that are mentors now and chose
"Show on website" on their mentor card, never a staff character or a banned account. Per mentor: name and level,
class, the language / region and hours text, the note, graduates and free places. Above the list: how many mentors
there are, how many apprentices learn now and how many graduated. The page only reads `chaos_mentors` and
`chaos_mentor_links`; without them it says that no mentor is listed yet. The numbers in the page's text
(`chaos_mentor_rules()`) are checked against `server/data/scripts/chaos/mentor_config.lua` by the test.

## Discord announcements

The game server queues events in `chaos_discord_queue` (server/README.md "Discord announcements"; the plugin's
`install.sql` creates the table too). `plugins/chaos/discord_worker.php` posts them to Discord channel **webhooks**
as embeds in the site's colours (`discord_lib.php`), and adds the Character Bazaar's new auctions and sales from
`chaos_bazaar_log` (its first run only notes where the log is). No bot and no token: a webhook URL per channel, from
the environment only.

- **Run it** every minute as the web server's user: `server/deploy/chaos-discord.service` + `.timer`
  (`EnvironmentFile=/etc/chaos/discord.env`, log `/var/log/chaos/discord.log`), or cron:
  `* * * * * www-data set -a; . /etc/chaos/discord.env; php <site>/plugins/chaos/discord_worker.php --site <site>`.
  `--loop [--interval 20]` keeps it running instead. Without any webhook it exits at once; the rows wait.
- **Environment** (`/etc/chaos/discord.env`, mode 600, owned by www-data; never in the repository):
  `CHAOS_DISCORD_WEBHOOK_RECORDS` (records, realm firsts), `_BOSSES` (world boss spawn and kill, Ascended,
  Cinderheart), `_PLAYERS` (levels 500 and 1000), `_ANNOUNCE` (season start and end), `_STATUS` (server up, daily
  restart, down), `_BAZAAR` (auctions and sales), `_DEFAULT` (every channel without its own); `CHAOS_DISCORD_OFF`
  (kinds not to post, comma separated: `record`, `first`, `worldboss_spawn`, `worldboss_kill`, `ascended_kill`,
  `cinderheart_kill`, `level`, `season_start`, `season_end`, `status_up`, `status_down`, `status_restart`,
  `bazaar_list`, `bazaar_sale`); `CHAOS_DISCORD_NAME` (the poster's name); `CHAOS_SITE_URL` (the bazaar link). Only
  `https://discord.com/api/webhooks/<id>/<token>` URLs are taken.
- **Rate limits:** at most 20 posts a run, 0.6 s apart per webhook; Discord's 429 `retry_after` and
  `X-RateLimit-Remaining: 0` hold that webhook's rows back. A failed post is tried again after 1, 2, 4, 8 minutes and
  then marked `failed`. Posts never ping (`allowed_mentions` empty). Rows: `new`, `sent`, `failed`, `nohook` (no webhook
  for the channel), `off`; sent rows are deleted after 14 days, failed ones after 28.
- **Invite:** `CHAOS_DISCORD_URL` (site.env) shows the Discord button of the layout and, as an https link, a last step
  "Join the community on Discord" on the downloads page.

## Balance telemetry

`page.php?plugin=chaos&p=telemetry` (Admin Panel > Balance Telemetry, added by `setup/chaos_setup.php`): admin accounts
(`CHAOS_ADMIN_ACCOUNTS`) with a character of group 5 or higher; anyone else gets "not found". Read only. Filters: level
band, class (a line or one class), a UTC date range (14 days by default, at most 400). Sections: online (average and
peak per day), hunting (experience and gold per hour per day, per class, per band), bosses (kills, average, best and
slowest time per party size), deaths per area and killer, spell casts, gold faucets and sinks, Chaos Coins per store
category (`chaos_shop_purchases`, by the buyer's level). Charts are SVG drawn by the server (`telemetry_lib.php`): no
script and no external file; a point's or bar's tooltip is its `<title>`, and each chart has a table. A rate is only
shown where at least 3 characters are behind it. Data: the game's `chaos_telemetry_*` tables (server/README.md
"Balance telemetry"); without them the page says there is no telemetry yet.

## Not done / for later

- Known small points from the security QA, left as they are: `pay/Service.php` apply() records the provider's status
  and `psp_ref` before it checks the provider id and our reference (harmless: the charge is always fetched by our own
  id); the stock `guildwar.php` prints guild names without escaping (guild names are letters only, created on this site).

- The outfit images of ZnoteX (an external image service) are off; turn them on in `config.local.php` if wanted.
- Achievements (`chaos_achievements`) and name plate titles have no page yet.
- Other languages: the layout's wording is English only (the language selector is off and `languages_enabled` is `en`
  only, so `?lang=` does not translate ZnoteX's strings around our English pages).

## Languages
The donation (`coins`), Character Bazaar, creator and leaderboards / records pages speak Portuguese (Brazil) or
English (`plugins/chaos/i18n_lib.php`): `&l=pt-BR` / `&l=en` (kept in the `chaos_lang` cookie for a year), else the
cookie, else the browser's Accept-Language, else English. `chaos_t('English %s', $x)` takes its text from
`plugins/chaos/i18n/pt-BR.php`; each page has a link to the other language. The wiki and the legal pages keep their
own texts (Portuguese by default). Test: `tests/chaos_i18n_test.php`.
