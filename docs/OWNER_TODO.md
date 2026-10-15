# Owner to-do for launch

These items need the owner: a decision, an account, a key or a text. Everything else is in `docs/LAUNCH.md`.
Never put keys, passwords or tokens in the repo. They go in the server's env files or in GitHub secrets.

## Decisions

Item 6 of 2026-10-14 ("Decida tudo sobre o item 6"): the developers decided every pure game or design question below;
each is under "Decided" with its reason. Left here: what needs the owner's own answer or a real-world action.

- [ ] **Dates.**
  - Proposal: launch on 20 Nov 2026 at 15:00 (UTC-3).
  - Open betas on the weekends of 31 Oct and 7 Nov.
  - The Season 1 start (now 1 Nov in `season_config.lua`) moves to the launch date. The Chronicle's goal sizes assume
    it does (server/README.md "The Ashen Chronicle", "Goal sizes").
- [ ] **The beta plan.** Who joins, the wipe before launch, coins and donations in the beta, the Season 1 start and
  the staff schedule: every decision is in [docs/BETA.md](BETA.md) (draft), each marked "Owner decides" with a
  recommendation. The go / no-go list for the beta, with owner and dev items: [docs/BETA_READINESS.md](BETA_READINESS.md).
- [ ] **A lawyer must review the new clauses.** Donation Terms section 7 (Season Pass, creator codes, Character
  Bazaar): its numbers are filled in now (pass 600 coins, creator 10%, Bazaar 10%, 14 days each); left
  `[REGRAS DE DIVULGAÇÃO DO CRIADOR]` and the review itself (docs/legal/README.md "Placeholders" and "Check" item 17). It
  must be reviewed before the Bazaar and creator codes are switched on for players. The Terms' new helper sentence
  (section 6) and the pack prices go to the same review.
- [ ] **Referral link.** Set `shareUrl` in `server/data/scripts/chaos/referral_config.lua` to
  `https://<site>/register.php?ref=` once the domain exists, so the client shows the link too.
- [ ] **Character Bazaar cron.** Add the cron line of `website/README.md` "Character Bazaar" on the live site.
- [ ] **Town scars of the Chronicle (a check, not a decision):** the decoration sets (`chronicle_config.lua`
  `town.sets`) go on free tiles around the capital's temple (town 1). Look at them in game after `/chronicle complete`
  on a test server, and the three portals in the temple's upper hall; set `town.anchor` if they land badly. Optional
  ground swaps (`swaps`) need ground ids of the map.

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
- [ ] **Discord webhooks** for the game's announcements (no bot, no token): in Discord, Server Settings > Integrations >
  Webhooks, create one per channel: records and realm firsts, bosses (world boss, Ascended, Cinderheart), players (levels
  500 and 1000), announcements (season start and end), server status (up, daily restart, down), Character Bazaar. Put
  the URLs in `/etc/chaos/discord.env` on the server (`CHAOS_DISCORD_WEBHOOK_RECORDS`, `_BOSSES`, `_PLAYERS`,
  `_ANNOUNCE`, `_STATUS`, `_BAZAAR`; never in the repository) and enable `chaos-discord.timer`. Steps: docs/LAUNCH.md
  "Discord announcements". The invite link above (`CHAOS_DISCORD_URL`) also shows on the downloads page.
- [ ] **Payment accounts:** Mercado Pago (Pix) and PayPal, with live credentials in `payments.env`.

## Keys

- [ ] **Signed updater key ceremony.** Generate the Ed25519 key offline and keep the private key off the server. See `docs/LAUNCH.md` "Client updates".
- [ ] **Official client key.** Set the GitHub secret `CHAOS_CLIENT_KEY` and the matching server env value. See server/README.md "Client guard".

## Texts

- [ ] **Bot review privacy line:** a lawyer should review the new suspicion-score sentence (EN and PT) and its 30/90-day
  retention, with the other legal texts.
- [ ] **Legal texts:** terms of use, privacy policy and donation terms. Drafts in Portuguese and English are in
  [docs/legal/](legal/README.md) and on the website (footer, account creation checkbox, donation page). Left for the
  owner: fill in the placeholders (name, CPF or CNPJ, contact and DPO e-mail, city, providers, prices, notice periods,
  minimum age), have a lawyer review the texts and the "Check" list of docs/legal/README.md, then run
  `website/install_site.sh` again. Donations say they are voluntary before and after payment (the site sends no mail
  after a donation).
- [ ] **Moderation record period:** pick `[PRAZO DOS REGISTROS DE MODERAÇÃO]` (Privacy Policy section 4) and set the
  same number of days in `server/data/scripts/chaos/moderation_purge_config.lua` `days` (default 730 = 2 years). The
  daily purge is built (server/README.md "Moderation record purge").
- [ ] **Rules page on a site installed before 2026-10-14:** the installer adds the Rules page once and never
  overwrites it. Paste lines 2.2 and 7.4 (the helper, 2026-10-14) and, if installed before 2026-10-12, 7.9 (chargeback
  fraud) of `website/setup/rules.bbcode` in Admin Panel > Pages > Rules.

## On the live server

- [ ] Machine timezone `America/Sao_Paulo` (`timedatectl set-timezone America/Sao_Paulo`). Weekly resets, events and the Gambler's 4-hour refresh use server time.
- [ ] `expose_php = Off` in php.ini.
- [ ] The nginx server block, the `limit_req_zone` lines and `fastcgi_param HTTPS on` from website/README.md "Web server".
- [ ] No `mock` provider in `payments.env`.
- [ ] Behind a proxy, pass the real client address through to PHP. The register limit and the login lock use it.

## Decided

- **Decided 2026-10-14 (owner delegated, "Decida tudo sobre o item 6"):**
  - **The Ashen Chronicle, Season 1 text: approved after an edit**, because the draft had a few slips: ash that "melts",
    "colossi" for the Five (only Vharok is one), the "weekly raid" in the story, the city's wardens mixed with
    Varkhul's, "as cinzas se erguem" (rise) for "lift". Fixed in `chronicle_text.lua` (EN and pt-BR, more natural
    Brazilian Portuguese: "veio de brasas", "quantas vezes for preciso", "se dissipam", "se reergue"); the codex and the
    wiki are regenerated.
  - **The Chronicler is Archivist Maelis** (one name, not a second keeper), because she already keeps the realm's
    ledger in ink mixed with ash (lore_data.lua) and already answers "chronicle": the intro names her, pt-BR says "a
    Cronista", and she answers "cronista" too.
  - **Chronicle goal sizes** (`chronicle_config.lua` `chapters.s1`): I 250 characters to level 300 + 1,200 rifts of
    tiers 1-5; II 20 world bosses + 1,200 rifts of 6-10; III 180 Omens + 600 rifts of 11-14; IV 12 Sepulchre clears + 30
    Ascended; V 10 Cinderhearts + 80 characters to 600 + 6 invasions. Because pack combat and 100-300 online made the
    old ones hours (chapter I) or weeks (40 raids, 10 invasions): now each chapter takes days, the arc about 37 days at
    150 online, 50 at 100, 28 at 300. The arithmetic: server/README.md "The Ashen Chronicle", "Goal sizes".
  - **Chronicle areas placed by the install**, because nobody should edit the map by hand: install step `contentareas`
    places the Breach (14910, 15140, 7; moved 10 east of its cell to keep 10+ tiles from cinderglass_sanctum), the
    Ossuary Stair (15100, 15140, 9) and the Memorial plaza (14800, 14800, 7) at their plan origins, idempotent,
    refusing taken tiles; `at` is set to those origins (a test checks it). Tried on a copy of the base map: placed,
    and a second run changed nothing.
  - **Gates in the capital's temple** (Mirewake, town 1), in its upper hall on floor 6 (the temple stairs lead there):
    Breach 32962, 32076, 6; Ossuary Stair 32962, 32079, 6; the Memorial's portal 32956, 32080, 6 (new: `memorial.lua`
    puts it there, `plaza.portal`). Because the Chronicle's scars are around that temple, every player's home town is
    the capital by default, and the hall is off every walking line (checked on the base map: plain floor, the hall stays
    connected). Not the hunt teleport room: it is in Cinderhold, not the capital. Found in passing: the Memorial's
    action ids 47930-47933 were the hunt teleports' block; moved to 47940-47944.
  - **Helper rule** (Rules 2.2 and 7.4, the Terms section 6 EN / pt-BR, the wiki's rules guide, docs/GM_HANDBOOK.md
    3a and 4): "The official client's helper (healing, spell rules, auto rotation, targeting) is allowed while you
    play. Leaving it running for hours with nobody at the keyboard counts as botting (7.4)." First time a warning, then
    the 7.4 ladder. A gamemaster counts a case only with an hour of unattended signals, a missed presence check and no
    answer to them within 5 minutes; no escalation needed below a 30-day ban. Because the proposal was sound and GMs
    had no rule to apply.
  - **Presence check failure stays "log"** (`antibot_config.lua` `failAction`), because a check is one signal and
    can fail for someone who stepped away for a minute; staff decide with the bot review (no automatic punishment).
  - **Prices:** the sheet and the reasons are [docs/PRICES.md](PRICES.md). Coin packs 100 / 250 / 525 / 1100 / 2875 /
    6000 coins for R$ 9,90 / 24,90 / 49,90 / 99,90 / 249,90 / 499,90 by Pix (US$ 1.98 ... 99.98 by PayPal,
    `brlPerUsd` 5), Starter 500 for R$ 14,90; one coin about R$ 0,10. Classes 500 coins each **or free at level 500**
    (the store is a shortcut, never the only way in). Season pass 600 (320 back), packs 500 / 1500 / 2500. Loot Bag
    250, Auto Seller 400, Rarity Autoloot 300, pouches 200 / 150, Everfull Ration 100 (per-character items, cheaper for
    alts). Bazaar fee 10%, creator share 10%, referral main reward at level 250. Cosmetics, the Pact, premium, boosts,
    supplies, runes and services kept. The Donation Terms tables (EN, PT) are filled in.

- Item prices (owner, 2026-10-14; server/README.md "Item prices"):
  - Kept as built: plain equipment at 31% of its old NPC price (the gear scale), rolled copies x1.5 to x32 by rarity and
    up to x1.75 by item level; the rarities above Legendary +2 a tier; currency, keys, 25 base quest items
    (`server/data/items/item_price_rules.csv`), store items and the profession materials not sold to NPCs.
  - Wandering Merchant's Orb of Gilding: 250,000 (was 60,000; "Ok"). Every plain equipment price is capped at 30,252
    so neither Gilding nor his Orb of Fate on a plain copy pays off at item level 150 (tested).
  - Uniques are not sold to NPCs ("faça o que você recomendar"): reason "unique: salvage or market". The Auto Seller
    never sold them.
  - Crafted equipment: floor 20% of its materials (was 40%), at most an hour of hunting gold at its level band; the
    inferniarch weapons (14.9M before) are at the 30,252 cap now. Non-equipment crafts stay worth at least their
    materials.
  - The unspawned base staff NPC that sold gear for 1-720 gold has its buy prices raised to twice the sell price.

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
- Pact experience and season characters (owner, 2026-10-13: "Ok"): season characters get no Pact experience, as
  with World Experience (`pact_perks.lua`).
- Auto Seller rarities (owner, 2026-10-13: "Deixe o jogador configurar o autosell por raridade"): each character ticks
  the rarities the Auto Seller sells: Common, Uncommon (the game's name for the "Magic" tier, rarity 2), Rare, Epic,
  Legendary+ (Legendary and every rarity above it). Default Common and Uncommon on, the rest off. Uniques never.
- Auto Seller commands (owner, 2026-10-13: "Tire os comandos do autosell e coloque no topmenu"): no `!autosell` and no
  Info & Services page; the Auto Seller window is in the top menu (Economy > Auto Seller): Sell all with its 30 s
  countdown, the last sale, the rarity checkboxes, the corpse list.
- Chargeback fraud (2026-10-12): coins taken back, what they bought removed, the account locked until the dispute is
  settled; fraud again: permanent, by an administrator (GM handbook ladder, Rules 7.9, Donation Terms section 6).

- Sprite pair 16 (mount rider seats): approved and pushed to `windows-assets` (1cae7c3).
- Sprite pair 17 (achievement wings): approved and pushed to `windows-assets` (854d34c).
- Sprite pair 24 (themed sets, rift rank variants, pack and large effects, bigger guardians): approved and pushed to
  `windows-assets` (407ad9b6, 2026-10-13). Its switches are on since 2026-10-13 (pair 24 at 407ad9b6; owner: "pode
  ligar todos os switches"): `ChaosThemeArt.PAIR24`, `ChaosPackFx.PACK_FX`, `ChaosBigFx.BIG_FX`, rift
  `looks.variantsOn` and `looks.bigGuardiansOn`. The 18 themed transmog sets: 12 in the store's weekly rotation, 6
  prestige achievement rewards (2026-10-13, prices above).
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
