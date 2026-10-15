# Promo video

A 29.5 s promo of Cinders of Chaos, made with [Remotion](https://www.remotion.dev/) 4.0.532.
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

## Open items

- Gameplay is stills with motion, not video: the full map was not on the capture machine. A real hunt clip
  (walk-in, area spell on a pack, loot) would replace scenes 1, 3 and 4.
- No music or narration. Only sounds with a licence for this use, or sounds made by repo tools.
- No date or URL in the call to action until the owner sets them.
