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
  `town.sets`) go on free tiles around the capital's temple (Cinderhold, town 2, since 2026-10-15). Look at them in game after `/chronicle complete`
  on a test server, and the three portals in the temple's upper hall; set `town.anchor` if they land badly. Optional
  ground swaps (`swaps`) need ground ids of the map.
- [ ] **Main city Cinderhold and the Halls of Services (a check, not a decision):** after a restart, step into the
  portal at the south end of Cinderhold's temple (Mirewake: its south-west corner): the hall holds the Oracle, the
  Keeper of Trials, Archivist Maelis, the faction NPC, the Loot Buyer, the Material Broker, the Gambler, Iselde Varrow
  and Osric behind their counters, and the Descent / raid portals. The Great Brazier moved to Cinderhold. Previews and
  the reasons for a hall instead of street booths: server/README.md "Halls of Services". A new character should leave the tutorial
  island in Cinderhold. Optional for existing characters: `server/tools/migrate_home_town.py` (server/README.md "Main
  city").

- [ ] **Stash prices (PLACEHOLDER).** Seven new store offers in "Storage & Slots" (`server/data/scripts/chaos/pact_config.lua`
  `store.storage`): Weapons, Armor, Jewellery, Materials and Creature Products Stash Tab at 150 coins each, Collectibles
  Stash Tab at 100, and Remote Stash Deposit at 300 (deposit into the stash from anywhere; also included while the
  Chaos Pact is active). Payments are off in the beta; set the real prices before launch. Also decide: keep selling "Extra Depot
  Tab" / "4 Depot Tabs" (each now also counts as a general stash tab) or remove the Depot Tabs store category, and when to
  remove the depot boxes for good (server/README.md "Stash", "Depot transition").

- [ ] **Conquest Tokens: review the prices and the income** (`server/data/scripts/chaos/conquest_config.lua`, server/README.md
  "Conquest Tokens, the Conquest vendor and bad-luck protection"). Target: a chosen item in 1-3 weeks of dedicated play
  (about 1,800 tokens a week), 3-6 weeks casual (about 360 a week). Now: monster uniques 600 + 1.5 x level, boss uniques
  1,000 + 3 x level, set pieces 900 + 1.2 x level, raid uniques 2,400 (Crown 3,600), Ascended uniques 4,200 (Signet 5,400);
  Omen Key of a chosen kind 150, attune 40, Ascended Shard 300; refinement 60 + 60 x the new rank, up to Legendary.
  Only the numbers are left for the owner; the design questions are under "Decided".

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

- Candlemarks (2026-10-15, server/README.md "Candlemarks"): the name stays Candlemarks (not "Vigil Coins": "Vigil" is
  the Vigils auras and the Vigil faction). Every online character earns 1 per 30 minutes, idle or not, into the
  account's balance; at most 2 characters per IP (the earliest logins). Prices as built, about 2.5x an active-only
  design because idle time counts (one character 4 hours a day: 56 a week; everything at the weekly caps: about 430):
  pocket boss charge 15 (3 a week), Orb of Grafting 30 (1, stays), Unmaking 12 (3), Tempering 8 (5), 2 Whetstones 8
  (5), Flawed gem 8 (5), Chipped gem 3 (10), 3 Awakening Orbs 5 (10), Ember Orb 10 (5), Crown Orb 25 (2), 10 Rune Shards 5 (5), supply
  bundles 3 / 5 / 8 (5 a week in all), and three cosmetics of our own, once per account: Candle Seal 150, Candlelight
  Name 120, Tallow Labels 100. Purchases only next to Osric the Chandler at the temple (the window works anywhere). No
  daily cap. The idle kick is raised to 1440 minutes (`patch_base_idle_kick.py --minutes N`). The rested vial and the
  bounty / kill task reroll offers light up when those APIs exist.

- **Conquest Tokens (2026-10-15).** Tokens stay per character: alts already get the experience catch-up, and no mule can
  funnel tokens. Season characters keep their own (a season character is a character of its own). Bad-luck protection
  stays per group, not per item. No repair for items ruined by the old Orb of Ruin: no live server yet, so none exist.
  The cheap low-level unique prices stay (about 2 weeks for a casual, kept for new players). The world boss
  participation unique roll and the rift chest unique roll are now under bad-luck protection too.

- **Pocket bosses (2026-10-15, owner delegated to the developers; server/README.md "Pocket bosses").**
  - 60% experience and 60% loot in every pocket (world, island, raid), kept.
  - Level floors for the open-world bosses' pockets kept: island 250, raid 150, Moloveth 250 (world bosses: the event's 300).
  - Every one of the 25 random raid bosses keeps its pocket; the Boss Spawns window lists the raid bosses by pocket level,
    then name (`pocketboss_config.lua` `sortSpawns`), and shows "Pocket: level N+" on rows without a level of their own.
  - No Ashen Sepulchre pockets (open any time, its loot is the weekly lockout).
  - The one-hour no-stacking record is kept in `chaos_pocketboss.event_at`, so a restart keeps it.
  - Multi-client characters may open pockets; each spends its own charges.
  - Still to measure live: the island and raid bosses' health and damage scaling (guesses until then), the charges (3 a day),
    the tokens (3 / 2 / 1) and the time limits.

- **Time-friendly progression, store and dungeons (2026-10-15, standing rule "follow your recommendations").**
  - Class unlocks are no longer sold: the store's "Classes" category (500 coins each) is removed; the Necromancer, Monk
    and Templar unlock for the whole account at level 200. Nobody had bought one, so nothing to refund. No quest path was
    built (the code supports a `quest` method if wanted later).
  - Stamina is not sold: the Stamina Refill (40) and the Stamina Extension (8) are removed. The Novice Pack's 5 Stamina
    Extensions (40) became 100 Supreme Health Potions (30); the pack stays at 250 coins (worth 355). Owned extensions keep
    working; the level 100 kit still gives two.
  - Dungeons: a 5 minute cooldown after a failed run (`Chaos.dungeons.failCooldownSeconds`), 15 after a clear.

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
  - **Gates in the capital's temple** (Cinderhold, town 2, the main city since your request of 2026-10-15; they were
    in Mirewake's hall before), in its upper hall on floor 6 (the stairs of the temple's two side rooms lead there):
    Breach 32362, 32240, 6; Ossuary Stair 32358, 32240, 6. On 2026-10-16 both gates and the Memorial's portal moved to
    the Halls of Services' portal rooms (server/README.md "City portals"). The Chronicle's scars are around that temple, every new character's home town is
    the capital, and the hall is off every walking line (checked on the base map: plain floor, every other tile of
    the hall still reached from both stairs). The hunt teleport room is one step away: its two great teleports stand 5
    tiles north of the temple (server/README.md "Main city"). Found in passing: the Memorial's action ids 47930-47933
    were the hunt teleports' block; moved to 47940-47944.
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
    `brlPerUsd` 5), Starter 500 for R$ 14,90; one coin about R$ 0,10. Classes **free at level 200, not sold** (500 coins or level 500 until 2026-10-15)
    (the store is a shortcut, never the only way in). Season pass 600 (320 back), packs 500 / 1500 / 2500. Loot Bag
    250, Auto Seller 400, Rarity Autoloot 300, pouches 200 / 150, Everfull Ration 100 (per-character items, cheaper for
    alts). Bazaar fee 10%, creator share 10%, referral main reward at level 250. Cosmetics, the Pact, premium, boosts,
    supplies, runes and services kept. The Donation Terms tables (EN, PT) are filled in.

- Item prices (owner, 2026-10-14; server/README.md "Item prices"):
  - Kept as built: plain equipment at 31% of its old NPC price (the gear scale), rolled copies x1.5 to x24 by rarity (1, 1.5, 3, 6, 12, 24) and
    up to x1.75 by item level; Divine is the top tier; currency, keys, 25 base quest items
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
  the rarities the Auto Seller sells: Common, Uncommon, Magic, Rare, Legendary, Divine (seven rarities since 2026-10-18,
  item 87). Default Common and Uncommon on, the rest off. Uniques never.
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
- Owner art pair 26 (2026-10-15): pair approved and on `windows-assets` (50645056), switch on (client/MANIFEST.md
  "Owner art"). Left: the store wings carry PLACEHOLDER prices of 250 each (`server/data/lib/chaos_owner_art.lua`); check
  the mapping of the looks in game (server/README.md "Owner art (pair 26)"), Ossivane's in particular; send again the small files the
  download could not save (fire medusa sheet, outfit sheets 2852 / 2719 / 2727, fifth_1, the two filth sheets).
