# Promo video and trailer

Two films of Cinders of Chaos, made with [Remotion](https://www.remotion.dev/) 4.0.532: the 29.5 s promo
(compositions `Promo`, `PromoVertical`, below) and the 86 s trailer with live gameplay and music (`Trailer`,
`TrailerVertical`, section "Trailer"). They share `src/components.tsx`, `theme.ts`, `layout.ts` and the scenes.

## Promo (29.5 s)

Three cuts come from one source:

| Cut | Composition | Size |
|---|---|---|
| Portuguese (Brazil), main | `Promo` | 1920x1080, 30 fps, H.264 |
| English | `Promo` with `--props=./props/en.json` | 1920x1080 |
| Portuguese, vertical for social | `PromoVertical` | 1080x1920 |

Silent. No music, no narration, no date and no URL.

## Storyboard

30 fps. Times in seconds.

| Time | Shot | Source | Caption pt-BR | Caption EN |
|---|---|---|---|---|
| 0.0-3.0 | Fire area spell over a mixed pack, then a 2x punch-in on the damage numbers. Flash and shake on each cut. | still `fight_fire_pack.png` | Uma horda. / Um feitiço. | One horde. / One spell. |
| 3.0-7.0 | Live login scene with the logo and walking monsters | footage `login_ptbr.mp4` / `login_en.mp4` | Fantasia sombria em pixel art | Dark fantasy in pixel art |
| 7.0-10.0 | Fight against a pack of ice liches | still `fight_ice_liches.png` | 88 feitiços próprios | 88 custom spells |
| 10.0-13.0 | Spider pack in a swamp hunt | still `fight_swamp_pack.png` | Monstros em bandos | Monsters come in packs |
| 13.0-16.0 | The hunt teleport room of Cinderhold | still `teleport_room.png` | Um teleporte para cada caçada | A teleport for every hunt |
| 16.0-20.0 | Class card over a dimmed hunt camp, 7 class names | still `arrival_camp.png` | 7 classes, 14 ascensões | 7 classes, 14 ascensions |
| 20.0-23.5 | The 9 dungeon banners scrolling | `client/overlay/data/images/dungeons/` | 9 dungeons, 6 dificuldades | 9 dungeons, 6 difficulties |
| 23.5-27.0 | Deep dungeon bosses drop in: Vaelith, Kharzun, Ossivane | pair 26 sprites, 4x (3x vertical) | Chefes com mecânicas próprias | Bosses with their own mechanics |
| 27.0-29.5 | Logo and call to action | `client/overlay/data/images/chaos/logo.png` | Beta em breve | Beta coming soon |

Every claim is in `docs/CONTENT_LIST.md`: 88 Chaos spells, 7 base classes with 14 ascended classes,
9 queue dungeons with 6 difficulties, pack combat (#151), boss mechanics (#129), the Cinderhold teleport room
(`docs/MAP_GUIDE.md`, step `contentareas`).

All on-screen text is in `src/strings.ts` (`ptBR`) and `props/en.json`. A new language is one more props file.

## Assets

| Path | In git | What |
|---|---|---|
| `public/stills/fight_*.png`, `teleport_room.png`, `arrival_camp.png` | yes (2.5 MB) | Real 1920x1080 client screenshots from a local test server with the area plans placed. The ping/fps overlay at the top left is covered with the tiles below it. |
| `public/stills/boss_*.png` | yes | Boss sprites of client pair 26, made by `tools/render_bosses.py PAIR26_DIR`. |
| `public/art/`, `public/fonts/` | no | Copied from the repo by `tools/prepare.sh`: logo, ember, dungeon banners, Cinzel and Alegreya Sans (OFL, `client/fonts-src/`). |
| `public/footage/login_ptbr.mp4`, `login_en.mp4` | no | Live login scene, 14 s each, made by `tools/capture_login.sh`. |

Pixel art is shown at integer scales only (1x, 2x, 3x, 4x) with nearest-neighbour scaling. The vertical cut shows a
1080x1080 window of each capture at 1x and pans across it.

## Render

```
cd video/promo
npm ci                       # or keep node_modules outside the repo and symlink it here
tools/prepare.sh             # copy repo art and fonts into public/
# footage: needs an assembled client (client/tools/assemble_client.sh) with a sprite pair; no server
tools/capture_login.sh CLIENT_DIR public/footage/login_ptbr.mp4 pt-BR 14
tools/capture_login.sh CLIENT_DIR public/footage/login_en.mp4 en 14
# optional: use a local Chromium instead of the one Remotion downloads
export REMOTION_CHROME=/path/to/chrome-headless-shell
npm run render               # out/promo_ptbr_1920x1080.mp4
npm run render:en            # out/promo_en_1920x1080.mp4
npm run render:vertical      # out/promo_ptbr_1080x1920.mp4
npm run studio               # preview and edit
```

`capture_login.sh` starts the client on its own Xvfb display at 1920x1080, waits 25 s for the login scene, moves the
mouse out of the frame and records with `ffmpeg -f x11grab` at 30 fps. Needs Xvfb, ffmpeg and xdotool.
Set `CLIENT_BIN` when the client folder holds more than one executable.

To recapture the gameplay stills: run a test server with `install_all.py` (step `contentareas` places the area plans
and grows the teleport room), log in with the client at 1920x1080 and take window screenshots
(`import -window root`). Keep the client's own name visible and no other.

## Open items (promo)

- The promo's gameplay is stills with motion; the trailer has the live clips. Its scenes 1, 3 and 4 could take
  shots of `public/footage/trailer/`.
- No date or URL in the call to action until the owner sets them.

## Trailer (86 s)

| Cut | Composition | Size | Length |
|---|---|---|---|
| Portuguese (Brazil), main | `Trailer` | 1920x1080, 30 fps, H.264 + AAC | 86 s |
| English | `Trailer` with `--props=./props/trailer_en.json` | 1920x1080 | 86 s |
| Portuguese, vertical for social | `TrailerVertical` (the `short` cut) | 1080x1920 | 60 s |

Live gameplay from a local test server with the full base map and every install step, recorded from the real
client (pair 26) at 1920x1080, 30 fps. Original music made by `tools/gen_music.py`. No narration, no date, no URL,
no prices.

### Storyboard

One shot list drives the edit, the footage cutter and the music: `src/trailer_timing.json` (`scenes`, and the `cuts`
`trailer` and `short`). Change a duration there and `Trailer.tsx`, `tools/cut_footage.py` and `tools/gen_music.py`
follow. Live = a recording of the running client; UI = a live recording of a client window, made once per client
language (`<id>_pt.mp4`, `<id>_en.mp4`).

| Time (s) | Shot | Source | Caption pt-BR | Caption EN |
|---|---|---|---|---|
| 0.0-2.5 | Elementalist, level 2000, Doomtide into a pack in Rimecrown Depths | live | | |
| 2.5-5.0 | Berserker cleaves a demon pack in the Sulphur Gallery | live | Uma horda. | One horde. |
| 5.0-8.0 | Falling Pyre and Doomtide melt a wyrm pack in Wyrmspine Hollows | live | Um feitiço. | One spell. |
| 8.0-12.0 | Logo over the live login scene | live (login) | Fantasia sombria em pixel art | Dark fantasy in pixel art |
| 12.0-16.0 | Walk through the Cinderhold teleport room into a hunt teleport | live | Um teleporte para cada caçada | A teleport for every hunt |
| 16.0-19.5 | Area spells on a Widowmere pack, damage numbers | live | Monstros em bandos | Monsters come in packs |
| 19.5-23.0 | Bonechoir Catacomb: the pack dies, loot bags, a rarity beam, Legendary and Mythic Find | live | 15 raridades de itens | 15 item rarities |
| 23.0-27.0 | Character select: four classes, scrolled with the arrows | UI | 7 classes, 14 ascensões | 7 classes, 14 ascensions |
| 27.0-30.0 | Berserker in the Hexwood Thicket, tag "Berserker" | live | Cada classe joga diferente | Every class plays differently |
| 30.0-33.0 | Bone Lord raises skeletons and the Bone Golem, then curses a pack | live | (tag Bone Lord) | (tag Bone Lord) |
| 33.0-36.0 | Inquisitor: Purging Nova and Judgement on a pack | live | (tag Inquisitor) | (tag Inquisitor) |
| 36.0-40.0 | The passive tree, dragged across | UI | Árvore passiva de 663 nós | A 663-node passive tree |
| 40.0-43.0 | Spell Supports window | UI | 20 suportes de feitiço | 20 spell supports |
| 43.0-46.0 | Codex, Modifiers tab | UI | 106 únicos, 77 modificadores | 106 uniques, 77 modifiers |
| 46.0-50.0 | Dungeons window: The Pyre Throne queued, the run starts (EN: the window, two dungeons picked) | UI + live | 9 dungeons, 6 dificuldades | 9 dungeons, 6 difficulties |
| 50.0-53.5 | The Pyre Throne: a pack, the objectives and timer HUD | live | Chefe liberado aos 85% | Boss unlocks at 85% |
| 53.5-57.0 | The Fallen Sanctum: Vaelith the Fallen Seraph, "Boss unlocked" plate | live | Chefes com mecânicas próprias | Bosses with their own mechanics |
| 57.0-60.5 | Forgewarden Kharzun: Slag Rain, the Bellows totem | live | (tag) | (tag) |
| 60.5-64.0 | The Pyre Throne: Azhkarrath the Chained Wyrm, fire rows | live | (tag) | (tag) |
| 64.0-68.0 | A tier 6 rift (Abyssal Rift), its HUD with the modifiers, a pack | live | Rifts com 36 modificadores | Rifts with 36 modifiers |
| 68.0-71.0 | Rift Atlas window | UI | Atlas de 81 nós | An 81-node Atlas |
| 71.0-75.0 | World boss Kaelgor the Infernal Warlord in his arena | live | 5 chefes mundiais | 5 world bosses |
| 75.0-81.0 | Finale: 12 cuts of 0.5 s on the beat, every third at 2x | live | | |
| 81.0-86.0 | Logo and call to action | art | Beta em breve | Beta coming soon |

The short cut (60 s, 9:16) keeps open, title, packs, loot, classes, Berserker, Bone Lord, tree, dungeons, the three
bosses, rift, world boss and the end. The vertical frame is a 1080x1080 window of each 1920x1080 shot at 1x around
the scene's `focusX`.

Claims, all in `docs/CONTENT_LIST.md` section 1 and 6: 7 base and 14 ascended classes, 663 passive tree nodes
(root included), 20 spell supports, 106 uniques, 77 item modifiers, 15 item rarities, 9 queue dungeons with
6 difficulties and the boss unlocked at 85% of the monsters, 36 rift modifiers, 81 Rift Atlas nodes, 5 world bosses.
Kharzun is shown in the Slagmourn Foundry hunt (placed there for the take); his own room is The Iron Crucible.

Captions and tags are the `strings` prop (`src/trailerStrings.ts`, `props/trailer_en.json`), six words at most.
Boss and class names stay as in the game in both languages. Pixel art at 1x or 2x, nearest-neighbour.

### Music

`tools/gen_music.py` writes the score: original music generated by the repo's own code (numpy, and scipy for
filters and the reverb when installed), owned by the project like the rest of the repo. No samples, no third-party
audio, no model. D minor at 120 BPM so the half-second cuts fall on beats; drones, a plucked i-VI-VII-V ostinato,
taiko-like drums, a pad, risers into booms on the act cuts (`mark: act`), a hit on every cut, booms on the bosses
(`big`), a quiet outro. Deterministic (`--seed`, default 1098: the same table gives the same file).

```
python3 -I tools/gen_music.py                 # public/audio/trailer_score.wav (86 s)
python3 -I tools/gen_music.py --cut short     # public/audio/short_score.wav (60 s)
```

`Trailer.tsx` plays it with `<Audio>`, faded in over 8 frames and out over the last 1.5 s. A later option for a
richer score is an open-weight music model run offline, only with a licence that allows commercial use; none is
installed or used.

### Render

```
cd video/promo
tools/prepare.sh                                   # art and fonts
python3 -I tools/cut_footage.py RAW_DIR           # public/footage/trailer/*.mp4 from the rig's raw clips
npm run music                                      # both scores
npm run render:trailer                             # out/trailer_ptbr_1920x1080.mp4
npm run render:trailer:en                          # out/trailer_en_1920x1080.mp4
npm run render:trailer:vertical                    # out/trailer_ptbr_1080x1920.mp4
```

The footage (about 170 MB) and the scores stay out of git.

### Live rig

`tools/rig/` records the raw clips. TEST ONLY: it puts a file-polled Lua hook into a scratch server and a scratch
client; never install either on a real server or ship them in a client.

1. Server: unpack `server/base-server.tar.xz` of the `windows-assets` branch into `$RIG/srv`, apply every
   `server/src-patches/*.patch` (`patch -p1`) and build (`cmake -S . -B build -DCMAKE_BUILD_TYPE=Release`,
   `cmake --build build`; the binary is `build/tfs`).
2. `RIG=$RIG tools/rig/rig.sh setup-db` (MariaDB data folder, base schema, rig ports 7891/7892 and port 3369 in
   config.lua), then `python3 -I server/tools/install_all.py $RIG/srv` (every step, `contentareas` included: the
   hunts and the Cinderhold teleport room) and load `tools/rig/chars.sql`: the test account `trailer` and four test
   characters (Ilsabet, Elementalist; Haldric, Berserker; Sorenne, Inquisitor; Ysolde, Bone Lord). No real accounts.
3. Client: `client/tools/assemble_client.sh BASE_CLIENT $RIG/game PAIR26_DIR` and build it; pair 26 is
   `things/things-1098.tar.xz` of `windows-assets` (md5s in client/MANIFEST.md). A single `Tibia.spr` also works
   (`CHAOS_SPR_SHARDS=0`).
4. `RIG=$RIG tools/rig/rig.sh hooks`, `rig.sh db`, `rig.sh server`, then `RIG=$RIG tools/rig/takes.sh [names]`.
   Each take logs a character in on Xvfb `:831` at 1920x1080 (`rig.sh char`: gear with `/testkit`, the level, then
   `client_prep.lua`: no chat panel, no fps and ping labels, a raised minimum light), teleports to the spot, plays a
   scripted key and spell sequence through `Rig.seq`, and records with `ffmpeg -f x11grab` at 30 fps into
   `$RIG/clips/`. The rig characters take 2% damage and are refilled (`rig_server.lua`), so a take is never cut
   short; spells, damage, drops, queues and boss mechanics are the game's own. GM help is setup only (gear, level,
   teleports, Kharzun placed in a hunt, a dungeon floor thinned so the boss opens within a take, a GM rift key and
   world boss start).
5. `python3 -I tools/cut_footage.py $RIG/clips` cuts the shots of the table.

The login footage of the title comes from `tools/capture_login.sh` (Promo, above).

### Open items (trailer)

- The gameplay clips were recorded with the client in Portuguese; the English cut uses English UI clips for the
  windows and the character select, but the small in-game HUD lines (dungeon objectives, timer) stay Portuguese.
  `LNG=en takes.sh` would record an English set.
- Guild wars, seasons, the bounty board and the store are not shown: their windows were empty on a fresh test
  server (no guilds, no season, no contracts), and the store shows prices.
- The Bone Lord and Inquisitor shots are short; a party take (healer, tank, damage) would show the group roles.
