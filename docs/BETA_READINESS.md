# Beta readiness: go / no-go checklist

Written 2026-10-14 from what the repository holds. Dates are the proposal of docs/OWNER_TODO.md "Dates":
open beta weekends Sat 31 Oct and Sat 7 Nov 2026, launch Fri 20 Nov 2026 15:00 (UTC-3).
The full beta plan is docs/BETA.md. The install steps are docs/LAUNCH.md. This file only says what must be true, who
does it and how to check it.

**State today.** A live integrated test passed on 2026-10-14 on a local test server with the Linux client. Its fixes
are committed (`0ff264b2`, `6f4c0435`). Nothing has run on a production host yet. No public host, domain, payment
account, Discord server or signing key exists yet.

## How to read it

| Class | Meaning |
|---|---|
| **B** Blocker for beta | No beta on 31 Oct without it. Done by **Wed 28 Oct**. |
| **S** Should before beta | The beta can open without it, with the listed fallback. Target **Fri 30 Oct**. |
| **L** Before launch | Needed by **Wed 18 Nov**, the wipe and launch install. |
| **N** Nice to have | No date. |

Owner = the project owner: a decision, an account, a key, a text or money. Dev = the developer.

**Go rule.** Fri 30 Oct 20:00 staff smoke test (B20). Go when every B row is checked. Any B row open: no-go, or a
closed staff-only weekend.

## Blockers for beta (B)

| # | Item | Who | How to verify |
|---|---|---|---|
| B1 | **Beta host.** Game server with a fast core (3 GHz+), 16 GB RAM, MariaDB on local NVMe. Choice in docs/HOSTING.md. | Owner | `fio` fsync test of LAUNCH.md section 2 prints a few ms or less. |
| B2 | **Domain and HTTPS.** Site address `https://...` and a DNS name for the game. | Owner | `curl -I https://<site>` gives 200 with a valid certificate. The play host resolves. |
| B3 | **Beta dates and owner decisions in docs/BETA.md.** Open or closed, the wipe scope, test coins, Blood Moon on or off. It is still "draft, nothing decided". | Owner | BETA.md status line no longer says draft. |
| B4 | **Season 1 start.** `season_config.lua` still starts Season 1 on 1 Nov 12:00, in the middle of weekend 1. PvP epoch is 5 Oct, so PvP Season 1 would end 30 Nov. | Owner decides, Dev edits | `/season status` on the beta server: not started. `season_test.lua` passes. |
| B5 | **Pace rebalance committed or switched off.** `pace.lua`, `pace_core.lua`, `pace_config.lua` and `tests/pace_test.lua` are untracked work in progress. `enabled = true`. ROADMAP #151 says LIVECHECK. `chaos_update.sh` refuses a dirty checkout. | Dev | `git status --short` clean on the beta tag. CI green. One live hunt with pace on. |
| B6 | **Load test with packs.** Pace adds monsters and faster respawn. `maxPlayers` 300 came from the pre-pace full-map test. | Dev | `loadtest.py setup --spread`, `run --hunt` at 300 bots on the full map. Game loop busy under about 60%, lag average under 75 ms. Then `loadtest.py cleanup`. Fallback: `pace_config.lua` `enabled = false`. |
| B7 | **CI green and a clean install** on the beta commit. | Dev | All CLAUDE.md checks pass. `install_all.py --dry-run`, real run, second run reports 0 changes. |
| B8 | **Engine build 0001-0039** on the beta host. 0039 was never run in a client. | Dev | The chain applies with no fuzz and builds. A listed Bazaar character gets the "Login Error" box. |
| B9 | **Client key.** GitHub secret `CHAOS_CLIENT_KEY` and the same value in `/etc/chaos/chaos.env`. `clientGuardMode = "enforce"` kicks everyone without it. | Owner | Server console says the key is set. A release client logs in. A development client is refused. |
| B10 | **Beta client downloads.** Run `windows-package.yml` on the beta commit: `server_host` = play host, a new `client_build`, pair 25 from `windows-assets` (ebe1b2b2). | Dev, Owner starts the run | Release `winpkg-<n>` has 5 files. Windows client on a clean PC and the Linux client log in to the beta server. |
| B11 | **Payments off.** `payments.env`: both providers `off`, never `mock`. Beta copy of `shop_coins_config.lua`: Pix and PayPal disabled. | Owner, Dev | `worker.php --status` lists no method. Donate is hidden in the client and on the site. |
| B12 | **Website live.** `install_site.sh`, SMTP, reCAPTCHA keys, nginx block with `limit_req`, `fastcgi_param HTTPS on`, `expose_php = Off`, the real client IP behind a proxy. | Owner keys, Dev install | Sign-up with captcha works. A recovery mail arrives with `spf=pass dkim=pass dmarc=pass`. A new character is level 1. A locked class is refused. Client API curl returns 401 `token`. |
| B13 | **Legal minimum for public sign-up.** Terms and Privacy placeholders filled: name, CPF or CNPJ, contact and DPO e-mail, city, minimum age, moderation record period. Rerun `install_site.sh`. | Owner | No `[...]` placeholder left on the legal pages. `moderation_purge_config.lua` `days` matches the Privacy Policy. |
| B14 | **Production config and never-ship list.** `prod_config.py --max-players 300`, timezone `America/Sao_Paulo`, LAUNCH.md section 11 files gone. | Dev | `timedatectl` shows Sao_Paulo. No `zz_*` or `ztest` files. `/lua` is not a command. No `loadbot*` accounts. |
| B15 | **systemd units, logrotate, watchdog, health timer.** Never run on a real host (ROADMAP #27). | Dev | `systemctl list-timers 'chaos-*'`. `kill -9` of the engine: back in 5 s with a crash log and an alert. The 06:00 save restart posts nothing. |
| B16 | **Backups and one restore drill.** `chaos-backup.timer`, an off-site target and an encryption key. | Owner target and key, Dev setup | `backup.log` has a dump and `offsite:` lines. Restore drill of LAUNCH.md section 7: counts match. Write down the minutes. |
| B17 | **Alert and report webhooks.** `CHAOS_ALERT_WEBHOOK`, `CHAOS_REPORTS_WEBHOOK` to staff-only Discord channels. | Owner | `chaos_health.py --test-alert` posts. `--dry-run` shows every check `ok`. |
| B18 | **Staff for weekend 1.** GM, admin and developer names per slot (BETA.md section 10). Staff characters in groups 4-6. | Owner | Schedule posted. Each GM opens the admin panel. |
| B19 | **Firewall at least.** ufw rules of LAUNCH.md section 5: 3306 closed, 22 from your addresses only. | Dev | `nmap` from outside: only 7171, 7172, 8090, 80, 443 open. |
| B20 | **Staff smoke test, Fri 30 Oct 20:00.** Server closed to players. | Dev, staff | Log in, store with test coins, crafting orb, bank, stash, a rift, one dungeon to the 85% boss unlock, one bug report from a normal account. |

## Should before beta (S)

| # | Item | Who | How to verify | Fallback |
|---|---|---|---|---|
| S1 | **Gateways and DDoS.** 2-3 gateway VPS, DNS A record per gateway, a backend IP never public. `setup_gateway.sh`, `setup_backend_firewall.sh`, `prod_config.py --proxy-trusted ... --proxy-required yes`. | Owner buys, Dev sets up | LAUNCH.md "Check it": a client logs in through each gateway. Backend refuses direct 7172. | Beta without gateways. Then the backend IP is public: change it before launch. |
| S2 | **Signed updater.** Ed25519 key ceremony offline, `update_manifest` and `update_public_key` in the package. | Owner | `make_update_manifest.py verify` passes. A test update reaches a client. | A full client download between weekends. |
| S3 | **Discord server and invite.** Invite in `ChaosTopBar.COMMUNITY_URL` (empty now) and `site.env`. Beta channels of BETA.md section 6. | Owner | The client top bar link opens the invite. | Link on the site only. |
| S4 | **Discord announcements.** Webhooks in `/etc/chaos/discord.env`, `chaos-discord.timer`. Never run against Discord (#144). | Owner, Dev | Restart: "Server online" in the status channel. `chaos_discord_queue` rows sent. | Set `discord_config.lua` `enabled = false`. |
| S5 | **First live run of never-live systems** on the beta host, before players. Table "Never run" below, rows marked S. | Dev | Each row works once on the beta server. | Switch off what fails. |
| S6 | **Language option.** Client base patch 0053 was never run in a client. | Dev | Options > Interface > Language switches to pt-BR and stays after a restart. | Language link on the login screen. |
| S7 | **Bot review and anti-cheat posture.** `failAction = "log"`, no automatic punishment. Helper rule 2.2 decision is open. GMs escalate (GM_HANDBOOK.md 3a). | Owner | Rules page shows the decision. `antibot_config.lua` `failAction` is `"log"`. | GMs escalate and give no penalty. |
| S8 | **Patch note and known issues.** `2026-10-31.md` exists. BETA.md section 8 is stale: pair 17 wings and the base rename are done. | Dev | The note opens at first login. The known issues list matches today. | |
| S9 | **Telemetry on a live database.** Never run against one (#107, #143). | Dev | `chaos_telemetry_*` gets hourly rows. The website telemetry page draws. | Hunt tracker and logs only. |
| S10 | **Bazaar and creator codes posture.** Both `enabled = true`. Lawyer review of Donation Terms section 7 is pending. Beta has only test coins. | Owner | Decide: test the Bazaar in the beta or switch both off. | `enabled = false` in both configs. |
| S11 | **Referral link.** `referral_config.lua` `shareUrl = ""`. Referral codes survive the wipe. | Owner, Dev | The client shows the register link with `?ref=`. | Site shows it already. |
| S12 | **Rules page** current, with line 7.9 if the site was installed before 2026-10-12. | Owner | Rules page shows 7.9 and the penalty ladder. | |
| S13 | **Lawyer review started.** At least Privacy Policy and the bot review privacy line, since the beta collects e-mails and IPs. | Owner | Lawyer has the texts and the "Check" list of docs/legal/README.md. | Launch at the latest (L3). |

## Before launch (L)

| # | Item | Who | How to verify |
|---|---|---|---|
| L1 | **Real prices.** Coin packs `usdCents` and `brlPerUsd`, class unlock 750, season pass 1000 and packs, Bazaar fee 8%, creator share 5%, referral level 150. All placeholders. | Owner | Donation Terms tables match `shop_coins_config.lua`. |
| L2 | **Payments live.** Mercado Pago and PayPal Business accounts, sandbox run of LAUNCH.md "Donations" step 6, then live credentials. Only the mock was ever run (#47). | Owner, Dev | Sandbox: Pix and PayPal credit coins, cancel, expiry, refund takes coins back, bad signature gets 401. Live: one real donation each, refunded. |
| L3 | **Lawyer review** of all legal texts: Donation Terms section 7, minors, bans and refunds, LGPD transfers, bot review line. | Owner | Lawyer sign-off. `install_site.sh` rerun writes the new texts version. |
| L4 | **Wipe** per BETA.md section 9. Final beta backup kept and restore-proven. Rehearse it once on a copy first. | Dev | Step 6 counts: 0 players, all accounts, 0 coins, 0 owned houses. |
| L5 | **Launch config.** `maxPlayers` 400, Season 1 and PvP dates, launch patch note. | Dev | `config.lua`, `/season status`, `/towerseason`. |
| L6 | **Group content validated** in the beta. Raid, Omens and Cinderheart in party, battleground 5v5+, party rifts, Descent with friends, bounty and bestiary party credit, Scorched Marches. | Staff, Dev | Beta log results. ROADMAP rows updated. |
| L7 | **Pace calibration.** Walk times from the beta hunt tracker; `pace_config.lua` `scale` (xp 1.3, loot 1.2 from the live check of 2026-10-14). Elementalist, Mystic, Berserker and Beastmaster model at 1.3-1.6x the median class: owner decision 2026-10-14, keep them as they are through the beta and decide from real data (options: less area damage, which also touches PvP, or a per-class experience factor). | Owner, Dev | Telemetry XP/h and gold/h per band and per class near the leveling model. |
| L8 | **Classes in progress.** C2, C3, C4 polish, Necromancer effect skins. Decide what ships. | Owner | ROADMAP C rows say done or deferred. |
| L9 | **Chronicle.** Approve the five chapters and goal numbers. Place the Breach, the Ossuary Stair and the Memorial plaza, or keep them closed. | Owner | `/chronicle` lists the placed areas. |
| L10 | **Release client.** Final `client_build`, updater on, dress rehearsal Thu 19 Nov (LAUNCH.md section 13). | Dev, staff | Section 13 steps all pass. |
| L11 | **Gateways** if S1 slipped, and a new backend IP. | Owner, Dev | As S1. |

## Nice to have (N)

| # | Item | Who | How to verify |
|---|---|---|---|
| N1 | Shader polish, client base patch 0044 (#113): never built into a client. Keep off. | Dev | Built and run in a client. |
| N2 | Painted icons (#114) and the 25-100% effect opacity slider (#117): not run in a client. | Dev | Seen in a client. |
| N3 | Client-side list of hosts for gateway failover: proposal, not built. | Dev | Login tries the next host. |
| N4 | Tester thank-you cosmetic from the final beta backup: not built. | Owner decides | |
| N5 | Rule that refuses a rift in the last 10 minutes before the save: not built. | Owner decides | |
| N6 | Doc drift. `server/README.md` header still says nothing ran on a TFS server. ROADMAP #130 says the `runes` step waits, but `install_all.py` has it. `HANDOFF.md` is outdated. | Dev | Texts match the code. |
| N7 | Sharded sprite file (#118) is not in the Windows package yet. | Dev | Package ships shards. |

## Never run on a real server or real client

"Real" means a production host or a released Windows client. Local test servers and the Linux client do not count.
**S** = run once on the beta host before players (S5). **Beta** = needs real players, on the BETA.md section 7 list.

| What | What did run | What never ran | When |
|---|---|---|---|
| Engine patch 0037, display scale | Local test server 2026-10-13, one player, Linux client | Two players, PvP, party, energy shield and tooltips in a client, Windows build | S |
| Engine patch 0038, weightless Loot Bag | Test server 2026-10-14, engine 0001-0038 | Production host, Windows build | S |
| Engine patch 0039, login refusal box | Built against 0001-0038 after today's live test | Any client | S |
| Client base patch 0053, language option | `patch --dry-run` on its context | Any client | S |
| Client base patch 0054, login panels `tr()` | Linux client 2026-10-14 | Windows client | S |
| Windows package with 0037-0039, 0053-0054 and pair 25 | Not recorded in the repo | A run on the current commit | B10 |
| Dungeon gate at 85% and the four dungeons 1000-2000 (#150) | Unit and mocked engine | Any live server | S |
| Pace, pack combat (#151) | Unit, mocked engine, model | Committed code, live hunt, load test with packs | B5, B6 |
| systemd units, watchdog, health timer, logrotate (#27) | Unit tests of the Python tools | A real host | B15 |
| Gateways, HAProxy, nftables, PROXY protocol | Engine patch 0025 tested | Real gateways; client failover unchecked | S1 |
| Payments (#47) | Mock provider, local site | Sandbox and live providers | L2 |
| Discord announcements (#144) | Mock HTTP endpoint | Discord | S4 |
| Telemetry (#107, #143) | Unit, mocked, PHP | A live database | S9 |
| Bot detection, bot review, anti-bot (#56, #148) | Unit, synthetic traces, load test | Real players, false positive rate | Beta |
| Bazaar (#134), creator codes (#132) | Local site 2026-10-14 | Public site | S10 |
| Raid (#61), Omens party (#57), battleground 5v5+ (#71), Descent party (#59), party rifts (#8), bounty party credit (#10), Scorched Marches (#77), invasion bar (#102) | Solo or mocked | A real group | Beta |
| Not run on a live server: Rift Atlas (#54), factions (#58), community goals (#60), Seasonal Journey (#67), Party Finder (#53), mentors (#66), Boss Spawns (#52), market history (#64), notifications (#81), path notables (#105), instance limits (#108), boss mechanics (#129), no conjuring (#130), season pass (#131), referral (#133), records (#135), Everfull Ration (#136), item prices (#139), Nemesis (#141), content coverage (#142), Chronicle (#145), Memorial (#146), generated area entrances on the full map (#109) | Unit and mocked engine | A live server | S for the first login paths, Beta for the rest |
| Computed, not measured: second keystones (#106), build archetypes (#110), solo kill times (#127), Overgrowth and Thorns, monster lint retunes | Models | In game | Beta weekend 2 |
| Restore from backup | Test database | Real host, off-site copy with the key | B16 |

## Timeline

| Date | Gate |
|---|---|
| Fri 23 Oct | B1, B2, B9, B13 owner items done. Host ordered. Keys made. |
| Wed 28 Oct | Every B row checked. Beta commit tagged. Client package built. |
| Thu 29 Oct | S rows done or fallback chosen. |
| Fri 30 Oct 20:00 | B20 smoke test. Go or no-go. |
| Sat 31 Oct 15:00 | Weekend 1 opens. |
| Sat 7 Nov 15:00 | Weekend 2 opens. |
| Wed 18 Nov | Every L row done. Wipe and launch install. |
| Fri 20 Nov 15:00 | Launch. |
