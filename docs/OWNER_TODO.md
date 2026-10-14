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
- [ ] **Store prices of 2026-10-13 (placeholders; owner approval "Pode fazer todas as mudanças recomendadas").**
  - Coin packs (`server/data/scripts/chaos/shop_coins_config.lua`): Handful of Coins 80 for US$ 1.99 (R$ 9,95 by Pix),
    Pouch 250 / 4.99, Sack 750 +10% / 14.99, Chest 1500 +15% / 29.99, Hoard 4000 +25% / 74.99, Vault of Coins 10000
    +30% / 179.99 (the anchor), Starter 250 + 250 / 2.99. Update the Donation Terms tables' R$ / US$ placeholders.
    Decided 2026-10-13 ("Limite a 1000"): the first donation is double up to +1000 extra coins; a pack above 1000 coins
    gets +1000 flat (the Vault: 10,000 + 1,000), `shop_coins_config.lua` `firstPurchase.maxBonus`, the website setting
    `first_bonus_max`. Donate page, client, Donation Terms (EN, PT) and tests say so.
  - Chaos outfit shaders (`cosmetics_config.lua` `outfitShaders`, on): 250 (Ember Glow, Frost Rime, Void Flicker,
    Heartblood), 300 (Holy Radiance, Spectral Ghost).
  - Themed appearance sets of pair 24 (`server/data/lib/chaos_theme_art.lua` `M.sets`): 350 a full set (Cryptbone,
    Wildroot, Moonsilver), 250 a class kit (Rimeglass, Emeraldine, Thornwild), sold only in the weekly "This week"
    rotation (5 offers, 10% off). Prestige, never sold: Voidmourn, Sunsworn, Oathsteel and the three Starwing kits
    (achievements in server/README.md "Weekly rotation, bundles, coin packs"). Change the split there if wanted.
  - Regalia bundles (outfit + mount + wings + aura) at 25% off; the three older bundles stay at 20%.
  - Everfull Ration, the infinite food (`shop_config.lua`, Convenience): 150 coins.
  - Rune packs (`shop_config.lua` `RUNE_GOLD_PER_COIN = 1000`, `RUNE_DISCOUNT` 5% / 10%): 100 Searing Orb 9, 500 Reaper's
    99, 100 Grand Mending 24, 100 Shackle 89 (all from the vendor prices of `data/lib/chaos_rune_supply.lua`).
  - VIP (the Chaos Pact, 300 coins / 30 days). Decided 2026-10-13 ("Vip ganha +10% de exp e restaura stamina mais
    rápido. Retire o loot bag e autoloot."; "Pode manter" for the loadout slot): while active +10% monster experience
    (inside the experience cap; not for season characters), stamina back x1.5 faster (offline and on the trainer tile),
    +1 loadout slot, the Auto Seller, a chat colour and a monthly cosmetic (six months planned, `pact_config.lua`
    `perks.monthly`). Rarity Autoloot is no longer lent by the Pact (still sold); the Loot Bag is a store item, never a
    Pact perk. The old rule "loadout slots are never sold" is replaced: the Pact's slot stays, the earned slots are not
    sold on their own. No priority login: there is no login queue. Season characters get no Pact experience
    (decided, see "Decided").
  - Loot Bag and Auto Seller, defined 2026-10-13. Loot Bag (350 coins, was "Loot Pouch"): bottomless, 255 slots (the
    most a container can have in this protocol), its contents weigh nothing (engine src-patch 0038), takes all the loot
    of your kills by default, kept at relog, back (empty) after a death. Auto Seller (500 coins, or the Pact): sells
    what is in the Loot Bag at NPC prices, once per 30 s, gold to the bank. Never sold: locked items, uniques, orbs,
    gems, keys, items no NPC buys. Rarities and the commands: decided, see "Decided".
- [ ] **Season pass price.** The premium track of the Ashen Pass costs 1000 Chaos Coins, a placeholder
  (`premium.price` in `server/data/scripts/chaos/seasonpass_config.lua`; the store offer reads it). The track is
  cosmetics and 320 coins back only (approved 2026-10-13). Decide the price; the packs (600 / 1800 / 3200) too.
- [ ] **Creator codes.** Decided 2026-10-13: the creator is paid in Chaos Coins in game. Left: the share, 5% of the
  donation's coins, a placeholder (`sharePct` in `server/data/scripts/chaos/creator_codes_config.lua`), the hold (14
  days) and the caps (500 per donation, 5000 a month). Codes are created on the website (The World > Creator Codes,
  an admin panel account with a group 5 character).
- [ ] **Referral rewards.** The main reward comes at level 150 of the friend's first character, a placeholder
  (`milestones` and `qualify` in `server/data/scripts/chaos/referral_config.lua`; the friend's account must be 7 days
  old). Tier titles at 3, 5 and 10 friends. Set `shareUrl` to `https://<site>/register.php?ref=` so the client shows
  the link too (the website shows it already).
- [ ] **Character Bazaar fee.** 8% of the final price, a placeholder in the approved 5-10% range (`feePct` in
  `server/data/scripts/chaos/bazaar_config.lua`). Also check the minimum level 50 and the minimum price 100 coins.
  Add the cron line of `website/README.md` "Character Bazaar" on the live site.
- [ ] **A lawyer must review the new clauses.** Donation Terms section 7 (Season Pass, creator codes, Character
  Bazaar) is a draft with placeholders (`[PREÇO DO PASSE PREMIUM]`, `[PERCENTUAL DO CRIADOR]`, `[TAXA DO BAZAR]`, ...;
  docs/legal/README.md "Placeholders" and "Check" item 17). It must be reviewed before the Bazaar and creator codes
  are switched on for players.
- [x] **Staff rules.** Decided 2026-10-12: the recommended rules of [docs/GM_HANDBOOK.md](GM_HANDBOOK.md) (see
  "Decided" below).
- [x] **Rune prices** (2026-10-13; rune conjuring is gone, runes come from NPCs and crafting). Decided 2026-10-13: the
  prices stay as below; Conjure Rations, Hallow Spear and Charge Staff go too ("Pode tirar, já que as ammos são
  infinitas"). Every NPC now sells each
  rune at one price, about its conjure cost in mana-potion gold: about twice the old NPC price for most runes (Searing
  Orb 45 -> 84, Reaper's Rune 50-108 -> 220, Grand Mending 175 -> 240, Shackle 700 -> 890; the unscribed rune stays 10).
  Crafting makes them for 55% of that gold (about 46% with the crafting bonus) plus herbs and ore pieces. Full table and
  the gold-per-hour share by level band: server/README.md "Rune supply"; numbers in
  `server/data/lib/chaos_rune_supply.lua` (`price`, `goldShare`). Decide:
  - the prices (300 attack runes an hour cost 14-17% of hunting gold at levels 8-20, 40% at 30, 62% at 45 with Reaper's
    Runes, 18% at 100, 7% at 300, about 1% past 500: flat prices are no sink in the late game);
  - whether Conjure Rations (food), Hallow Spear and Charge Staff, the last conjure spells that make no rune, go too
    (decided: they go).

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
