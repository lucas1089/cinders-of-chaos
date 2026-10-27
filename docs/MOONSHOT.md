# Moonshot: 12 months, no limits

The owner asked on 2026-10-27 for the most ambitious plan for the game with unlimited resources and 12 months. This is
that plan, kept for later. None of it is scheduled yet. Smaller ideas are in `docs/IDEAS.md`; the working plan is
`ROADMAP.md`.

**One line:** the world that changes every week, that you can play on the bus, and where the best players become the
boss everyone wants to beat.

The game already has more systems than most servers ever ship (classes and ascensions, passive tree, orbs, rifts,
waystones, atlas, Tower, seasons, minions, cards, world bosses, Discord, admin app, tester bots). More systems is not the
moonshot. What is missing is a world that moves, reach on phones, and stories made by players.

## Pillar 1: The Living Cinderworld

The map is not fixed. Each week a "Cinderfall" burns part of the world and the generator rebuilds it. Hand-made cities,
temples and boss lairs are anchors and never change; the wild land between them does.

- **Why us:** `tools/mapstudio` already generates areas from kits, checks walls and fences, places pools and repairs
  access. Half of the system exists.
- **Hot reload of map regions** (engine src-patch): swap a region without a restart, moving players inside it to a safe
  tile first. The core technical bet.
- **Director service:** picks what changes from world state. Ash spreads where players hunted most; a new treasure zone
  opens where nobody went; guild control shapes the next borders.
- **Corruption (ash 0-100 per region):** more ash means stronger monsters, better loot and a local boss. Players push it
  back by killing, burning totems and guild control. The client world map shows it live.
- **World chronicle:** every change is news in game, on the website and on Discord, in pt-BR and English (the bilingual
  patch notes and the Discord queue are the pipe).
- **Geographic atlas:** waystones become places in a world that moves, not a list.

## Pillar 2: Play the Boss

In events, invasions and the seasonal endgame, a player (or a small group) controls the boss against the raid.

- **Unlock:** "Pyre Ash" earned in the endgame buys a place in the boss seat queue.
- **Kit:** 6-8 telegraphed attacks (ground markers with a wind-up: rings, lines, safe zones). The server decides every
  hit, so a slow phone is fair.
- **Scoring:** the boss player is rewarded for a good fight, not for winning. A 20-second wipe gives little; a close fight
  won by the raid at 5% gives the most. This stops griefing.
- **Season finale, the War of the Pyre:** the best boss players of the season take the five world bosses and every guild
  attacks at once, streamed with the cast system.
- **Spectating:** the cast relay and the admin app spectator view turn the finale into something to watch in game, on the
  website and on Discord.
- **Needs:**
  1. A telegraph language in engine and client (new patches): ground markers with a wind-up, synced to server time.
  2. A boss controller: the player's character is swapped for the boss creature with its own skill bar, health and
     resists, and back afterwards.
  3. Monster AI uses the same language, so every boss gets readable mechanics. That alone pays for the work.

## Pillar 3: The Cinder Client (phone and PC)

A new client, same server, protocol extended through patches, made to be played on an Android phone with touch. PC stays
first-class.

- **Why:** the core audience is Brazilian and Brazil is mobile-first. A good touch ARPG in the classic top-down style
  barely exists.
- **Renderer:** keep the tile grid and our sprites; add smooth movement interpolation, 60 fps, dynamic light (shaders
  exist) and an optional HD scale.
- **Touch controls:** movement stick, 6 skill buttons, swipe to aim line skills, auto-target as the main touch input, loot
  beams and the loot splitter with one tap.
- **Small-screen UI:** large layered menus, pinch-zoom passive tree, a market that works like a shop app.
- **Cross-play:** phone and PC on one server, optional PvP matchmaking filter.
- **Controller support** on PC comes nearly free from the touch work.
- **Network:** the server stays authoritative; the client predicts movement and corrects, so lag feels smaller on 4G.
- **Risk:** the most expensive pillar; needs its own client team, and it only wins if the phone experience is good, not
  just working.

## Foundations

- **A. Balance digital twin:** connect the existing models (pace, Tower, minions, store, skills, progression, roulette)
  to a headless simulator that runs the real server Lua with bots for millions of hours of every class and build each
  night. Output: who is out of line, which hunt is dead, which item nobody uses. It proposes changes inside the
  `*_config.lua` limits; a human approves; the change lands in the patch notes. The tester bots are the seed.
- **B. AI Game Master with guardrails:** a side service that reads world state and writes daily bounties tied to the
  ash, NPC lines that remember what each player did, and the chronicle. It only picks from templates and approved reward
  tables (never invents items or gold), a human approves the weekly lines, text is checked for language and content,
  every text exists in pt-BR and English. Keys live in an env file on the VPS, never in the repo.
- **C. Replays and clips:** the server sees every hit. Record each boss fight as a compact event log and replay it in the
  client. A world boss kill posts a short animated clip to Discord; the website shows the fight of the week. Bug reports
  get "show me what happened at 14:03".
- **D. Player-made dungeons:** a web `mapstudio` with only our kits. Player builds, the checks validate (walls, fences,
  access, monster budget, loot budget), the team curates, one featured dungeon per week, cosmetics and credit for the
  creator.
- **E. Guild halls:** built in game from map kit pieces, tied to territory in the living world. More territory, bigger
  and more visible hall.
- **F. Scale:** rifts, dungeons, Tower and player dungeons move to separate instance processes; the main world only runs
  the open map. Target 3,000+ online on one world. The hardening work (ASan, fuzzing, Rust side services) is the base.

## The 12 months

| Months | Theme | Work |
|---|---|---|
| 1-3 | Foundations, first visible change | Telegraph language (all current bosses readable); map region hot reload prototype on a test server; balance simulator v1 (3 classes); automatic world boss replays to Discord; Spanish (es-LA) as the third language on the pt-BR pipeline |
| 4-6 | The world starts moving | Cinderfall v1 (one region per week); ash mechanic; world chronicle (game, website, Discord); phone client closed alpha (movement, combat, inventory); guild territory on the map |
| 7-9 | Players become content | Play the Boss in invasions with the close-fight reward; web dungeon editor beta and first featured dungeons; AI Game Master v1 (bounties and chronicle, human approval); phone client open beta with cross-play |
| 10-12 | The season that shows it all | 10-week season ending in the War of the Pyre; instances as separate processes; phone client on the Play Store; guild halls tied to territory |

## Measures

| Metric | Today | Target in 12 months |
|---|---|---|
| Day-30 retention | measure in beta | 2x |
| Weekly reasons to log in | patch, events | the world changes weekly + a featured dungeon |
| Phone share of players | 0% | 40%+ |
| Players online on one world | measure | 3,000+ |
| Clips and news on Discord | manual | automatic and daily |
| Bug report to fix | manual | report, bot reproduces, fix in 48 hours |

The progress metrics report (time buckets, top 10, churn shares) is the base for measuring these.

## What not to do

- Leave the classic tile look. It is the identity; modernise how it plays, not the art style.
- Pay to win. It kills the trust that Play the Boss and seasons need. Store stays cosmetic and convenience.
- Let the AI invent content freely. Templates and human approval only; one game-breaking drop and trust is gone.
- More classes before the core is great. Seven is enough; make each one great first.

## Biggest risks

1. **The phone client runs late.** Build touch controls on the current client first; commit to the new renderer only if
   phone retention justifies it.
2. **A changing world frustrates players who like knowing the map.** Towns, temples and main hunts never change; only
   the wild land does.
3. **The boss seat turns toxic.** Close-fight reward, reports end the run, a bad history loses access.
4. **The team spreads thin.** If only one thing gets done: the telegraph language and boss mechanics. It improves every
   boss and is the base of Play the Boss.
