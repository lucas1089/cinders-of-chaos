# Promotion plan and material (beta and launch)

For the owner. What is ready, what to record, what to post where, and when. Times: UTC-3.
Ready-to-paste post texts are in pt-BR and en. Related: docs/BETA.md (the beta itself), docs/LAUNCH.md, website/README.md
"Promo kit", "Streamer kit" and "Media kit".

## 1. What is ready

| What | Where | Made by |
|---|---|---|
| Beta and launch square posts, beta story, 7 class cards, forum banner and signature | `website/overlay/plugins/chaos/assets/promo/`; the media kit zip, folder `social/` | `website/tools/gen_promo_kit.py` |
| OBS overlays, Twitch panels, social banner 1500x500, offline screen, YouTube thumbnail template, Discord icon | `.../assets/streamer/`; media kit `streamer/` | `gen_streamer_kit.py` |
| Server list banners, social share image, class and feature images | `.../assets/img/`; media kit `art/` | `gen_site_art.py` |
| Media kit zip with a fact sheet (pt-BR, en) | `<site>/press/`, linked from the Creators page | `gen_media_kit.py` at install |
| Creator program, creator codes, referral link | site Creators page; game | O320, referral |

Dates on the posters: `website/tools/promo_source.json` `dates`. Empty today, so no date line is drawn. Ask Claude to fill
them and regenerate once the beta dates are fixed.

Not in the repo: gameplay footage and screenshots. They need the real client. Sections 3 to 5 say what to capture.

## 2. Recording setup

- Client: Windows client, window 1920x1080, UI scale 100%, graphics options at the highest.
- Cinema mode hides every panel, the chat and the top bar. Streamer mode hides private messages and names (O411).
  Hotkeys: Ctrl+Shift+H cinema mode, Ctrl+Shift+S streamer mode.
- Use a GM or test character with gear of the scene's level. Never show real players' names without their consent.
- OBS: 1920x1080, 60 fps, CQP 18 to 20, MKV, remux to MP4 after. A second scene cropped 1080x1920 for vertical video
  (game at the centre, captions above and below).
- Sound: game sound on, music on (O408), no voice. Music for videos: only the game's own tracks (own work, see
  docs/CREDITS.md). No commercial music.
- Auto screenshots (O411) catch level ups, boss kills and legendary drops while recording.

## 3. Trailer, 60 seconds

| Time | Picture | Text on screen (pt-BR / en) |
|---|---|---|
| 0-4 | Black, embers rise, the logo burns in | |
| 4-10 | Slow pan over the first town at dusk, rain on | "O mundo não acabou. Ele quebrou." / "The world did not end. It broke." |
| 10-18 | Seven quick cuts, one per class, each casting its signature spell | "7 classes. 14 ascensões." / "7 classes. 14 ascensions." |
| 18-24 | The passive tree opening, a keystone taken | "Monte sua build." / "Make your build." |
| 24-32 | A big pack pulled and cleared, loot beams, a legendary drop | "Loot que importa." / "Loot that matters." |
| 32-40 | A Rift run, then the Infinity Tower floor counter climbing | "Rifts. Torre Infinita." / "Rifts. Infinity Tower." |
| 40-48 | A raid boss fight with a full party | "Raids e chefes de mundo." / "Raids and world bosses." |
| 48-54 | Arena 3v3 and a battleground clash | "PvP quando quiser." / "PvP when you want it." |
| 54-60 | Logo, "BETA ABERTO", site, PC and Android | "Grátis. PC e Android." / "Free. PC and Android." |

Cut on the beat of the boss track. Captions in the game's display font (the poster font). Export 16:9 and a 9:16 cut.

## 4. Short videos (15 to 30 s, 9:16)

One a day from 9 days before the beta. Hook in the first second, caption on screen, the site at the end.

1. "Escolha sua classe": seven classes in seven seconds each, the class card (classes/) at the end.
2. The Elementalist clearing a whole pack with one combo.
3. The Beastmaster: the wolves do the work.
4. The Necromancer Bone Lord army growing.
5. A legendary drop with the loot beam, slow motion.
6. The passive tree: from empty to a full build in 15 s (fast forward).
7. "Morri para isso": a world boss wipe and the comeback.
8. The Infinity Tower: floors 1 to 30 sped up.
9. "Roda no celular": the same hunt on a phone, side by side with the PC.
10. Arena 1v1 best moment.

Captions: pt-BR first. Hashtags: `#mmorpg #rpg #fantasiasombria #jogosonline #gamerbr #indiegame #pixelart`
(en: `#mmorpg #rpg #darkfantasy #indiegame #pixelart #freetoplay`).

## 5. Screenshots (15)

Capture at 1920x1080, cinema mode on. Each one needs a clear subject.
1-7: one per class, mid-spell, in its best-looking area. 8: the first town. 9: the passive tree window.
10: a world boss with a party. 11: a Rift. 12: the Infinity Tower. 13: the arena. 14: a legendary drop with the item
tooltip. 15: the phone client in landscape.
Put them in the media kit: ask Claude to add a `screenshots/` folder to `gen_media_kit.py`.

## 6. Where to post

| Where | What | Notes |
|---|---|---|
| Your Discord | Announcement, countdown, patch notes, events | The funnel. Every post links here |
| The big Open Tibia forums, "Advertising" boards | Thread with banner, features, class cards, links | Read each board's rules first. Bump only when allowed |
| Open Tibia server lists | Server page with the list banner (`assets/img/`) | Vote buttons on the site help the ranking |
| Reddit: the Open Tibia subreddit; r/MMORPG self-promo threads; r/indiegames | Short text + trailer | Follow each sub's self-promotion rule |
| Facebook groups of OT and MMORPG players (BR) | Square post + text | Many groups allow posts only on set days |
| TikTok, Instagram Reels, YouTube Shorts | The shorts of section 4 | Same video on all three |
| YouTube | Trailer, a 10 min "first hour" video | Thumbnail template in `streamer/banners/` |
| Small streamers (OT, retro MMORPG, BR) | Invite with the creator program | 10 to 20 invites, creator code each |
| WhatsApp groups of OT players | Story image + site | Ask the group admin first |

## 7. Post texts

### Discord announcement (pt-BR)

> **Cinders of Chaos: BETA ABERTO**
> RPG online de fantasia sombria. Grátis, sem chave, sem convite. PC e Android.
> 7 classes e 14 ascensões, árvore passiva por classe, Rifts, Torre Infinita, raids, arena e battleground.
> Quem jogar o beta ganha o título **Beta Tester** no lançamento.
> Achou bug? Poste no canal de bugs: o bot registra e responde.
> Baixe em www.cindersofchaos.com

### Discord announcement (en)

> **Cinders of Chaos: OPEN BETA**
> A dark fantasy online RPG. Free, no key, no invite. PC and Android.
> 7 classes and 14 ascensions, a passive tree per class, Rifts, the Infinity Tower, raids, arena and battleground.
> Everyone who plays the beta gets the **Beta Tester** title at launch.
> Found a bug? Post it in the bugs channel: the bot logs it and answers.
> Download at www.cindersofchaos.com

### Forum thread (pt-BR and en, same layout)

Title: `[10.98] Cinders of Chaos | Beta aberto | Classes, árvore passiva, Rifts | PC e Android`
1. Forum banner (`forum/banner-728x90`).
2. Two lines on the game (tag + beta_sub of promo_source.json).
3. Feature list: classes and ascensions, passive tree, loot rarity, Rifts, Infinity Tower, raids, PvP modes, phone client,
   no pay to win (link the "what the store never sells" page).
4. The 7 class cards.
5. Rates and dates, links (site, Discord, download), the trailer.

### Short video caption (pt-BR)

> 7 classes, 14 ascensões e uma árvore de passivas só sua. Beta aberto, grátis, no PC e no celular. Link na bio.

## 8. Calendar (D = first beta day)

| Day | Action |
|---|---|
| D-10 | Fill the dates in promo_source.json, regenerate. Trailer recorded |
| D-9 | Discord and site countdown. Forum threads and server lists up. Short 1 |
| D-9 to D-1 | One short a day. Invites to streamers. Facebook and WhatsApp posts on D-7 and D-2 |
| D-1 | Reminder on every channel. Staff schedule checked (docs/GM_HANDBOOK.md) |
| D | Announcement at the opening hour. A GM boss hunt event in the evening |
| D+1 | "Thanks + what we fixed" post with the first patch notes |
| Between weekends | Daily bug triage (bot), a patch mid-week, the shorts continue |
| Launch D-3 | Launch post (`post/launch-1080`), wipe reminder, Beta Tester title reminder |

## 9. What to measure

The admin app shows retention (O253 progress metrics): players back on day 2, time to level 50, deaths, quits.
Count new accounts per day against the post calendar to see which channel worked. Ask new players "where did you
hear about us" (the new player survey, O374).
