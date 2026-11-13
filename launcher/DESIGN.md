# Launcher v2: new look, install from scratch, game starts only through the launcher (O552)

Owner, pt-BR: "faça um instalador desse tipo pra gente. onde não dá pra lançar o jogo via o exe, tem que lançar pelo launcher".
Status: round 1 was the design. Owner answers 2026-11-13: the look must not copy the reference (the layout in this file was redrawn, see launcher/README.md "Look"); the launcher installs itself; the launch check is in the client only (no server rule, so section 3 "Server side" is dropped); Unity is exempt for now; other decisions as recommended. The reference picture is style direction only: no art, name, text or icon of it is used.

Previews, 1600x1000, drawn with our real art (login art, brand logo) and the fonts we already ship:
- `preview_launcher.png`: downloading state.
- `preview_launcher_ready.png`: "Pronto para jogar".
Their sample numbers (build 47, 8,2 MB/s, 12 files) are made up. The news text is the real 2026-11-13 patch note.

## 1. Look

### Layout (logical window 1280x800, fixed size)

| Zone | Content |
|---|---|
| Title bar, 52 px | ember dot, "Cinders of Chaos Launcher" (Cinzel), version (Alegreya Sans, muted). Right: PT / EN pill, gear, separator, minimize, close. The bar drags the window. |
| Hero, left | the login art, darkened, with the brand logo at 620 px and an ember halo. Below the logo, a row of 4 buttons. |
| Buttons | Discord, Site, Wiki, Criar conta. Icons drawn by hand, no icon pack. |
| News card, right, 472x564 | header (icon, "Notícias", sub-line "Do Discord e do site", `< 1 / 12 >`), image 436x200 with tag chip, title and "Build 47 · há 2 dias" on a dark gradient, body text that scrolls, dots. |
| Bottom bar, 1240x124 | status dot and text, client chip, progress bar, bytes and file count, speed and time left, big JOGAR button. |

Palette: the one of `theme.rs` today. Dark iron `#0E0B0A` and `#19140F`, edge `#3E2E25`, ember `#E04E1A` to `#FA762C`, gold `#E8BE6E` for headings, tags, the progress end and the "ready" state, text `#E2D8CC`, muted `#9C8E82`. Blood red `#962418` stays for errors only (dot, card edge, "Tentar de novo"). Status dot: ember while working, gold when ready, red on error. No green.
Fonts: Cinzel for the title, headings, tag and JOGAR; Alegreya Sans for everything else. Both are already in `docs/CREDITS.md` under OFL and in `client/fonts-src/`.

### Data behind each element

- **Carousel.** One list: the feed's News and Changelog merged by date, newest first, 12 at most (today 6 + 6, `feed.rs` already caps both). Prev / next, clickable dots, auto-advance every 8 s, paused while the mouse is over the card or the player scrolls. The Notícias / Changelog tabs go away. The tag tells them apart.
- **Tag.** `ATUALIZAÇÃO` (patch note), `NOTÍCIA` (site news), `EVENTO`, `MANUTENÇÃO`, `AVISO`. Values `update`, `news`, `event`, `maintenance`, `notice`; an unknown value is `news`.
- **Version.** `Build N` when the note says it, else the patch note date. Client build numbers are the ones the guard already counts.
- **Relative date.** Computed in the launcher from the feed date: hoje, ontem, há N dias, semana passada, há N semanas, then the date. en twin: today, yesterday, N days ago.
- **Images, where they come from.** The feed stays `format` 1 and gains optional keys per item: `tag`, `build`, `image` (https URL). Three sources, in this order:
  1. A patch note file gets optional header lines `Tag:`, `Build:`, `Image:` beside the `Kind:` line `chaos_pn_parse` already reads. `Image:` names a file in a new site folder `launcher/` of the assets, which the feed turns into an absolute URL.
  2. The Discord bot (`server/deploy/discord_bot`, `/patch gerar` and `/patch escrever`) gets an optional `imagem` attachment. It re-encodes it (Pillow, 872x400, JPEG quality 82, under 300 KB) and writes it next to the patch note files it already writes. Same approval flow as the text. No Discord API call from the launcher and no token in the client.
  3. No image given: a default picture per tag, cut from the real art (login art, class art) by `gen_launcher_art.py` and embedded in the launcher, so a first start with no network still shows a full card.
  Site news (ZnoteX) take the first `https://` image of their body from the same site origin, else the default of their tag.
- **Buttons.** URLs come from `launcher.json`: `links: {discord, site, wiki, signup}`. Defaults derive from the manifest origin: site `/`, and the wiki and signup pages of the site (exact paths to read from the site routes in the build round). The Discord invite is a new key written by `set_launcher_config.py` from the site settings. Same link rules as `feed::safe_link` (https, no spaces, no user@). A missing URL hides its button.
- **Bottom bar.** Status text from `i18n::Status`, bytes and files from `Event::Progress` and a new `Event::Files { done, total }`, speed as a moving average over 3 s, time left from it, numbers in pt-BR format (`24,3 MB`, `2,6 GB`, `5 min 25 s`).
- **Client choice (main / Unity).** It stays in the bottom bar, on the client chip: `Cliente principal · 47 ▾`. A click opens a small menu with the two clients (and "Cliente Unity (beta)" only when the Unity manifest is known, as today). Disabled while an update runs, same rule as now. The text note about the Unity sprite pair moves into the menu.
- **Gear (settings).** A modal card over the window: install folder with "Abrir pasta", "Verificar arquivos" (repair), "Limpar cache de download", client choice, "Fechar o launcher ao jogar" (on by default, else it minimizes), language, version and "Desinstalar". Nothing else.
- **Errors.** The bottom bar turns blood red, text as `i18n::Error` gives today, buttons "Tentar de novo" and "Jogar assim mesmo" replace the Play slot or sit left of it. The rules of `choice::buttons` do not change.

### What eframe 0.29 can do and what needs care

| Need | How | Care |
|---|---|---|
| Borderless window, own title bar | `ViewportBuilder::with_decorations(false)`, drag with `ViewportCommand::StartDrag`, `Minimized`, `Close` | Windows loses its drop shadow and the snap-to-edge feel. We draw a 1 px edge and accept it. |
| Rounded window corners | `with_transparent(true)` and a rounded frame on a transparent clear colour | Transparency with no decorations had flicker and black corners on some Windows GPU drivers. Plan: radius 12, and if the Windows run shows corners black, fall back to a square window with the 1 px edge. Not testable on Linux. |
| Resizing | not needed | Fixed 1280x800 canvas, `with_resizable(false)`. On a smaller screen, `pixels_per_point` = min(1, screen / 1280, screen / 800) so a 1366x768 laptop gets 0.96. This keeps every rect exact. `ViewportCommand::BeginResize` needs a check in 0.29 and is not used. |
| Hero art | pre-composed texture (art + vignette + fade), drawn cover-fit | One 1280x800 RGBA is 4 MB raw in the exe. Better: embed as PNG (about 700 KB) and decode once at start, which needs a PNG decoder (see crates). The logo is a second texture so it can pulse a little. |
| Rounded panels, edges, glows | `Frame::rounding`, `Shadow` (already used for the Play glow), `painter.rect_filled/rect_stroke` | egui shadows are one blur size, fine for ember glows. |
| Gradients | `epaint::Mesh` with vertex colours | Used for the progress bar (ember to gold), the image bottom fade, the card fades. |
| Smooth progress bar | `ctx.animate_value_with_time(id, target, 0.25)` and `request_repaint_after(16 ms)` only while working | The byte counter jumps in big steps (curl reports per poll); the animation hides it. Idle window repaints at 0 fps. |
| Images from the feed | `image` crate decode, `ctx.load_texture` | Decode on the feed thread, hand the `ColorImage` over a channel; at most 12 textures of 872x400 (1.4 MB each in GPU memory, 17 MB in all, lazy: only the shown card and its neighbours). |
| Fonts | `FontDefinitions` with `include_bytes!` | egui (ab_glyph) does not pick a weight of a variable font, so Cinzel Bold needs a static instance. `gen_launcher_art.py` makes `assets/cinzel_bold.ttf` with fontTools instancer, named by role so no reserved name is reused. Alegreya Sans Medium is static. +390 KB in the exe. Latin accents are in both fonts (checked in the preview: Ç, Ã, Í, Ê). |
| Letter spacing (tag, JOGAR) | per-glyph painter loop | egui has no tracking. Small helper in `theme.rs`. |
| Text wrapping in the news | `ScrollArea` + `LayoutJob` with two colours (gold lead, normal text) | Feed text is plain already. Dots and counter are painter shapes. |
| Icons | painter shapes, same as the preview | Discord, globe, book, user-plus, gear, chevrons, scroll. About 120 lines. No icon font and no SVG crate. |
| Hover, pressed, disabled looks | `theme::play_button` already has them | Reuse, resize to 292x80. |

### Look implementation facts

- `main.rs` is 630 lines and mixes layout with logic. Split: `ui/mod.rs` (App, frame, title bar), `ui/news.rs`, `ui/bar.rs`, `ui/settings.rs`, `theme.rs` (colours and widgets), and a pure `layout.rs` that returns the rects for a given size. `layout.rs` is unit tested without a GUI.
- Update thread, `Event` channel, `choice::update` and `Phase` do not change. The bar only needs two more events: `Files` and `Speed` (computed in the UI from `Progress` and `Instant`, no engine change).

## 2. Full install from an empty folder

### What exists

`Updater::run` hashes the install against the manifest `native` section and downloads whatever is missing or different. For the main client that section holds `Chaos.exe`, its DLLs and `chaos.pack` (the modules, the data and the sprite shards are inside the pack, 0.9 GB of about 1.1 GB). So a folder with only `launcher.json` and `CindersLauncher.exe` already becomes a full client at the first start. Resume (Range, 5 retries), hash check before any swap, journal and rollback all apply. The Unity client does the same in `unity/`.

### What is missing

| Gap | Fix |
|---|---|
| Nobody has `launcher.json` yet. A player downloads a zip today. | The launcher exe embeds the same facts (manifest URL, public key, feed, links) as a build-time file made by `set_launcher_config.py`. With no `launcher.json` beside it and not inside a registered install, it runs in setup mode (below). |
| One 0.9 GB file: one bad byte means 0.9 GB again, one connection, no repair. | Manifest `native.files[i]` gains optional `chunk` (bytes, 33554432) and `chunks` (array of hex SHA-256, one per chunk), inside the signed payload. The published blob stays one plain file. The launcher downloads chunks with Range, 4 at a time, verifies each, resumes at chunk level, and the repair button re-fetches only chunks whose hash is wrong. Old launchers ignore the keys and use the file hash. Size of the extra data: 29 chunks x 64 hex = 2 KB. |
| Delta for the pack. | Not in this plan. With fixed chunks, an updated pack reuses a chunk only when its bytes sit at the same offset. The pack is encrypted per file with a content nonce, so unchanged files are stable but a size change shifts all later chunks. Real delta needs content-defined chunking, a separate step. Left open, said plainly. |
| No disk space check. | `need = missing bytes + largest file for the swap backup + 512 MB`. Free space through `fs2::available_space` (one call, any OS, tested with a fake trait). The setup screen and the update both refuse before the first byte with "Falta espaço em disco: precisa de 2,4 GB, tem 1,1 GB". |
| No folder choice. | Setup mode only. Default `%LOCALAPPDATA%\CindersOfChaos`, no admin rights needed, a "Escolher pasta" button with a folder picker (`rfd` crate, MIT, native dialog) and a text field fallback. The folder must be empty or an old install of ours; a path inside `Program Files` or a network drive gets a warning. |
| No repair. | Gear, "Verificar arquivos": hash cache cleared, every native file hashed, chunks checked, bad parts re-downloaded, journaled swap as today. Prints "N partes corrigidas". |
| The launcher is built in the Windows client job only and is not in the zip name players know. | The setup file is the launcher exe itself, published as `Cinders-of-Chaos-Setup.exe` (below). |
| File count in the bar. | Counts the files the run changes ("1/12"), not the chunks. For a first install: about 12 (exe, DLLs, pack). Chunk progress is in the bytes. |
| First start of the game then runs the in-game updater for module-only releases. | Kept. A fresh pack is at most one release behind the live manifest. The launcher does not download the encrypted `files` blobs (the engine decrypts and mounts those; copying that into Rust would be a second implementation to keep in step). |

### Manifest and publisher changes

1. `client/tools/make_update_manifest.py build`: `--native-chunk BYTES` (default 32 MiB, 0 off). For each native file over one chunk it writes `chunk` and `chunks`. Test in `make_update_manifest_test.py`.
2. `launcher/src/manifest.rs`: parse `chunk` / `chunks`, check count = ceil(size / chunk), size of the last chunk, 2 KB limit per file, chunk size between 1 MiB and 128 MiB, each hash 64 hex. A malformed entry refuses the manifest, as other native rules do. `NativeFile.chunks: Option<Chunks>`.
3. `server/deploy/publish_client_update.sh` passes `--native-chunk`; `verify` re-hashes the chunks of each blob; `chaos-ctl.sh publish-update` needs nothing new (admin app button "Publicar update" stays the way).
4. Setup file publication: the publisher also copies the launcher exe as `$CHAOS_SITE_DIR/download/Cinders-of-Chaos-Setup.exe` plus `Cinders-of-Chaos-Setup.exe.sha256`, atomic rename, so the site's download button always points at the newest signed launcher. The website's download page text changes from the zip to this file (zip stays as "instalação manual").
5. Per-chunk `Range` against a plain blob is already what `curl -r` does today. The static file server must answer 206, which `publish_client_update.sh` already probes for the biggest blob.

### Downloader changes (`install.rs`, `net.rs`)

- `net::Fetch` gets `get_range_to(url, offset, len, part)`. The pool is 4 threads, each running the system `curl` with `-r a-b`, writing `stage/<sha>.c<i>`. When all chunks of a file are verified they are written into `stage/<sha>` at their offsets, one at a time, so extra disk use stays under one chunk. Retries and backoff as now per chunk.
- Speed: the pool sums bytes of all workers; the UI averages. 4 connections is the same count the in-game updater uses by default (8 there for many small files).
- `hashcache.txt` stays (size and mtime). Verify ignores it.
- Everything keeps the staged-swap rule: nothing is replaced before every file is complete and hashed.

### The Windows setup: recommendation

Options: (a) a normal installer program (Inno Setup or NSIS) that unpacks the launcher and creates shortcuts, (b) the launcher exe installs itself, (c) keep the zip.

Recommended: **(b), one exe, `Cinders-of-Chaos-Setup.exe`.**
- One program to build, sign, test and update. An installer made by a third tool is a second program that never updates itself and has its own script language, CI install step and credits; antivirus tools trust a signed Rust exe no less than a packed installer, and a certificate is needed either way.
- It needs no admin rights: per-user folder, per-user registry, per-user shortcuts.
- The launcher already updates itself by staged rename, so the "installer" is also the updater. There is no second copy to drift.

How it works:
1. Start. The exe looks beside itself for `launcher.json` or the registry value `HKCU\Software\CindersOfChaos\InstallDir` pointing at the folder it runs in. Found: normal launcher. Not found: setup screen (same window, same look, `Instalar` instead of `Jogar`): folder, space needed and free, shortcuts checkboxes (desktop, start menu, both on).
2. `Instalar`: create the folder, copy itself as `CindersLauncher.exe`, write `launcher.json` from the embedded facts, create two `.lnk` shortcuts, write the uninstall entry (`HKCU\...\Uninstall\CindersOfChaos`, `DisplayName`, `UninstallString` = `CindersLauncher.exe --uninstall`), start the copy with `--first-run` and exit. The copy runs the normal update, which downloads everything, with the news already showing.
3. `--uninstall`: removes only what the launcher owns: `owned.json` files, `.cinders_launcher/`, `chaos_update/`, `unity/`, shortcuts, registry keys, then itself by a delayed delete. Player files in the write folder are asked about ("Apagar também suas configurações?").
4. Crates for it, Windows only (`cfg(windows)`), all behind two small traits (`Shell`, `Registry`) so the logic is tested on Linux with fakes: `winreg` (MIT), `mslnk` (MIT) for `.lnk`, `rfd` (MIT) for the folder dialog, `fs2` (MIT/Apache) for free space. No elevation, no PowerShell, no COM by hand.
5. Credits: each new crate, and the two fonts' "Used for" lines (launcher), go to `docs/CREDITS.md`, then `gen_credits.py`.
6. Not verifiable here: all of the Windows part (registry, `.lnk`, picker, SmartScreen). It runs on Windows only in the packaged job and by the owner. The plan keeps that part small and fenced.

Fallback if SmartScreen blocks a fresh unsigned exe: Inno Setup wrapper around the same exe, no change to the rest. The code-signing certificate stays an open owner item (README "Open").

## 3. The game starts only through the launcher

### Goal and honesty

The exe refuses to run when the launcher did not start it. **This is a deterrent, not security.** Everything the client checks is in the client binary. Anyone who can read the exe or the launcher can find the rule and start the game by hand, patch the check out or mint a ticket. What it does: stops the casual double-click on `Chaos.exe` (so a player never plays on stale files), stops the old zip habit, and puts the update gate in front of every start. The real gate stays the server's client guard (src-patch 0021, key in every client, same honesty as `server/README.md` "Client guard").

### The ticket

- **What it is.** Text: `t1.<client_build>.<launcher_build>.<expiry_unix>.<nonce_hex32>.<mac_hex64>`.
  `mac = HMAC-SHA256(sub_key, "t1|build|lbuild|expiry|nonce")`.
  `sub_key = HKDF(CHAOS_CLIENT_KEY, label "cinders-launcher-ticket-v1")`.
- **Why a sub key.** The launcher must hold something to sign with. Giving it the raw guard key would hand the login handshake key to a second binary. The sub key lets the launcher and the client agree on tickets while a leak of the launcher cannot answer the server's challenge (HKDF is one way). Both are built in the same workflow from the same secret, obfuscated the same way as `chaosguard_key.h`. Launcher side: `build.rs` reads `CHAOS_CLIENT_KEY`, writes masked arrays into `OUT_DIR`, never cached, never committed. HMAC and HKDF are 30 lines on the `sha2` the launcher already has (no new crate). Client side: OpenSSL, as the guard.
- **Expiry.** 30 s. Enough for a slow start, too short to pass around. No pid binding: the launcher may close right after the start.
- **Binding.** `client_build` is the manifest `native.package`: a ticket for build 47 does not open build 46. `launcher_build` is the launcher's own number (a new counter in `Cargo.toml` metadata) for the server log.
- **How it travels.** Environment variable `CINDERS_TICKET` set on the child process only. The client reads it before anything else, deletes it from its own environment (so children do not inherit it) and keeps the verdict in memory. Alternatives dropped: an inherited pipe (more code, same visibility to the same user), a command line (shows in task lists).
- **Single use.** The 30 s expiry is the main limit. In addition the client keeps `chaos_update/ticket_seen.txt` with the nonces of the last minute and refuses a repeat. A local file, so again a deterrent.

### What the client checks (client base patch 0198, `0198-launcher-start-only.patch`)

- New header `src/client/chaosticket.h` (header only, OpenSSL, vectors in `client/tools/chaosticket_test.cpp`, CI cuts it from the patch like `chaosfist_test.cpp`): parse, HKDF, HMAC compare in constant time, expiry, build, replay list.
- `src/main.cpp`: right at the start, before the application object and before any window or config:
  1. `CHAOS_REQUIRE_LAUNCHER` compiled out: nothing happens (dev, Linux, tests).
  2. Else read and delete `CINDERS_TICKET`, verify. Good: go on and remember "started by the launcher, launcher build L".
  3. Bad or missing: show a native message box (`MessageBoxW`, no engine yet): **"Abra o jogo pelo Launcher."** or "Open the game from the Launcher." by the system UI language, with one button. Then look for `CindersLauncher.exe` in the exe's folder, then the parent folder (the Unity player sits in `unity/`), then the registry `InstallDir`. Found: start it (`CreateProcessW`, `--play` so it opens already updating) and exit 0. Not found: text with the site download address from `init.lua` is not readable yet, so a fixed `https://<site>/download` compiled in from the CMake cache (`CHAOS_LAUNCHER_URL`), exit 1.
- **Restart.** The client restarts itself after updates (base patch 0101 `restartArgs`, the child inherits the environment). `relaunchIfRequested` mints a fresh ticket with the same sub key (it has it) and puts it in the child's environment, expiry 60 s. The launcher is not needed for a restart.
- **Lua.** `g_app.launcherBuild()` returns the launcher build or 0, for the guard hello and a line in the About window.
- **CMake.** `CHAOS_REQUIRE_LAUNCHER` option, default OFF in the source, ON in `windows-package.yml` and `windows-client.yml`. The sub key is derived at configure time next to the guard key and written in the same masked header.

### The one exe problem

`windows-package.yml` builds one `Chaos.exe` and uses it in two packages: the separate client (launcher) and the full one-PC zip (`start-client.bat`). A release exe that needs a ticket would break `start-client.bat`. Decision: the full zip also carries the launcher, and `start-client.bat` calls `CindersLauncher.exe --play-local` (no update, no network, mints the ticket, starts the game; allowed only when no `launcher.json` has a manifest, or when `--play-local` is given). The package start test of the workflow (it sets `CHAOS_UPDATE_OFF=1`) starts the game through `CindersLauncher.exe --play-local --no-window`. One rule for every Windows exe, no second build, no bypass file.

### Android and Unity

- **Android.** No launcher exists on a phone and the OS starts the app. `CHAOS_REQUIRE_LAUNCHER` stays OFF in `android-client.yml`; the APK has its own update path (O313) and its own guard builds. A check in the C++ is compiled out, not skipped at runtime.
- **Unity client.** Played through the launcher too (it is in the launcher's choice). The player checks the same ticket in C# (`HMACSHA256`, no extra library) in `Core`, with the same expiry and build rules, and the same message. The package built without the guard key (`"dev": true` in the manifest, `--allow-dev-unity`) is exempt: there is no sub key, and testers need to run it from the editor. Exempt until phase D; then required for non-dev packages. Test vector shared with the C++ one (`unity/Core.Tests`). The ticket code is a new `Core/LauncherTicket.cs` and one call in the player's start, scheduled in its own round.
- **Dev and test builds.** Linux client, CI jobs, the unity live check, journey bots, tester bots: no flag, no ticket. Windows test builds: `--allow-dev-key` workflow input already builds with the public dev key; a dev-key exe accepts tickets of a dev-key launcher only (same derivation from the dev key). The launcher has `--mint-ticket BUILD` (prints one line, refuses unless built with the dev key) for local scripts.
- **Staff / owner on the VPS.** Not affected, the server has no client.

### Server side, worth a small step

The client guard handshake today is `cg1:<build>:<hex>`. Add an optional launcher fact:
- Client answers `cg2:<build>:<launcher_build>:<hex>` when it started through a ticket, `cg1` as now when not (the HMAC message appends `u16le launcher_build` only in `cg2`). Server src-patch `0093-guard-launcher.patch` parses both.
- Config `clientGuardRequireLauncher`: `"off"` (default), `"log"` (every `cg1` login is logged `via=direct`, counted, nobody refused), `"enforce"` (a `cg1` answer from a build that is not on `clientGuardLauncherExempt` is refused with "Abra o jogo pelo Launcher: <download URL>"). Staff IPs skip it like the rest of the guard.
- Why it is worth doing: it gives the owner a number (what share of logins went through the launcher) before anything is enforced; it catches older exes in the field; and it is the only place that can refuse without trusting the player's disk. Limit: the client reports it about itself. An exe patched to send `cg2` always passes. Same limit as the key.
- Owner control: a `chaos-ctl.sh guard-launcher off|log|enforce` command and a button in the admin app, card "Client e launcher" (Android: Comandos; desktop: Comandos). The rollout order: publish launcher and 0198 exe, set `log` for a week, read the share, set `enforce` when old builds are gone from `clientGuardBuilds`.

### Failure modes to design for

| Case | Behaviour |
|---|---|
| Player copies `Chaos.exe` elsewhere | no ticket, message, launcher not found, download link. |
| Launcher cannot reach the site | it still mints a ticket and starts the game ("Jogar assim mesmo", as today). The server guard and `min_package` still decide. |
| Clock jump during the 30 s | the ticket may expire; the player presses Jogar again. |
| Antivirus kills the env var read or the launcher | nothing special; same as any launcher failure; the message box says what to do. |
| The launcher is older than the exe | the exe checks `launcher_build >= CHAOS_MIN_LAUNCHER` (compiled in), else "Atualize o Launcher" and opens it; the launcher self-update runs at its start anyway. |
| Two clients on one PC | tickets are per start; nothing shared. |

## 4. Implementation plan

Phases, each one a round with its own tests; nothing changes the game server until D. Order is chosen so the look lands first and cannot break updating.

**A. Look (no behaviour change).** Files: `launcher/src/theme.rs` (palette kept, new widgets: tag chip, pill, bar, tracking text, icons), new `launcher/src/ui/{mod,news,bar,settings}.rs`, `launcher/src/layout.rs`, `launcher/src/main.rs` (thin), `launcher/src/feed.rs` (tag, build, image, merge and relative dates in `feed.rs` pure functions), `launcher/src/i18n.rs` (new strings pt-BR and en), `launcher/tools/gen_launcher_art.py` (hero texture, default news images per tag, static Cinzel Bold; `--check`), `launcher/assets/*`. Website: `launcher_feed_lib.php` (optional keys), `chaos_pn_parse` header lines, test `chaos_launcher_feed_test.php`. Bot: `/patch` image attachment, `bot_core.py`, `bot_core_test.py`. New crate: `image` (png, jpeg features only, MIT/Apache).
Tests: `layout.rs` unit tests (rects at 1280x800 and at scale 0.96, no overlap, text fits), `feed.rs` (new keys, unknown tag, bad image URL dropped, merge order, relative date table in both languages), carousel state machine (next, prev, wrap, auto-advance, pause), number formats (pt-BR `24,3 MB`), `tests/mass_update.rs` unchanged and green. Xvfb screenshot compared by eye to the preview (not in CI).

**B. Full install and repair.** Files: `manifest.rs` (chunks), `install.rs` (pool, chunk verify, disk check, repair), `net.rs` (`get_range_to`), `ui/settings.rs` (Verificar arquivos, Limpar cache), `i18n.rs`; Python `make_update_manifest.py`, `publish_client_update.sh`; `crates/selfupdate` unchanged. New crate: `fs2`.
Tests: `manifest.rs` chunk rules; `tests/mass_update.rs` new cases: first install into an empty folder (12 files, one of them 4 chunks), 120-round loop with chunked files, cut mid chunk resumes at the chunk, one flipped byte in a staged chunk refetches that chunk only, repair of a flipped byte in the installed pack, not enough disk space refuses before any download (fake `Space`), parallel pool with one failing worker; `vector.rs` with a Python-signed manifest that has chunks; `make_update_manifest_test.py` class `Chunks`; `publish_client_update_test.py` (chunks verified, setup exe copied and its sha file).

**C. Setup mode.** Files: `launcher/src/setup.rs` (logic with `Shell` and `Registry` traits), `launcher/src/winshell.rs` (`cfg(windows)` real ones), `ui/setup.rs`, `build.rs` (embedded config), `client/tools/set_launcher_config.py` (`--embed FILE`), `windows-package.yml` (launcher build with the embedded config; publish `Cinders-of-Chaos-Setup.exe`). New crates: `winreg`, `mslnk`, `rfd`.
Tests: `setup.rs` with fakes (path rules, existing install detected, shortcuts and uninstall entry content, uninstall removes only owned files, refuses a folder with foreign files), `set_launcher_config_test.py` (`--embed`), a CI check that the Setup exe name matches the site download page (`tools/ci/check_launcher_setup.py`). The Windows parts are listed as not run.

**D. Launcher-only start.** Files: client `base-patches/0198-launcher-start-only.patch` (`chaosticket.h`, `main.cpp`, `application.cpp` restart, `luafunctions.cpp`, `CMakeLists.txt`), `client/tools/chaosticket_test.cpp`, `launcher/src/ticket.rs`, `launcher/build.rs`, `launcher/src/launch.rs` (env on the child, `--play-local`, `--mint-ticket`), `tools/windows/package/start-client.bat`, `windows-package.yml` / `windows-client.yml` (option ON, start test through the launcher), server `src-patches/0093-guard-launcher.patch`, `clientguard_core.lua`, `clientguard_config.lua`, `server/deploy/chaos-ctl.sh guard-launcher`, Android and desktop admin command tables (CI `check_desktop_commands.py` keeps them equal), Unity `Core/LauncherTicket.cs` (own round).
Tests: shared vector `launcher/tests/data/ticket_vector.json` read by `ticket.rs`, by `chaosticket_test.cpp` and by a Python test of the vector tool (`client/tools/ticket_vector_test.py`); expiry, build, wrong key, replay, bad format, restart ticket; `tests/clientguard_launcher_test.lua` (modes off, log, enforce, `cg1` and `cg2`, staff, exempt builds) in the server loop under luajit and lua5.3; a src-patch dry-run test like `fist_attack_patch_test.py`; `chaos_ctl_test.py` (`guard-launcher`); a CI check `tools/ci/check_launcher_only.py`: every workflow job that builds the Windows client passes `CHAOS_REQUIRE_LAUNCHER=ON`, `start-client.bat` starts the game through the launcher, the Android workflow does not.

CI lines to add to `ci.yml`: the existing launcher block already runs `cargo fmt`, `clippy -D warnings` and `cargo test --locked` for `launcher`; add `python3 -I tools/ci/check_launcher_setup.py`, `python3 -I tools/ci/check_launcher_only.py`, `python3 -I client/tools/ticket_vector_test.py`, the `chaosticket_test.cpp` cut step (as `chaoshdoverlay_test.cpp`), and the new Lua test via the server loop (picked up by the `tests/*_test.lua` glob). `gen_launcher_art.py --check` already runs.

Docs to keep in step: `launcher/README.md` (Look, Install, Setup, Ticket), `client/MANIFEST.md` "Game launcher" and "Signed updater" (chunks), `client/BASE.md` (0198 and the CMake option), `server/README.md` "Client guard" (cg2, mode, command), `docs/LAUNCH.md` (client downloads, rollout of the launcher-only mode), `website/README.md` "Launcher feed" (new keys, images), `server/deploy/discord_bot/README.md` (image attachment), `docs/ADMIN_APP.md` (guard button), `docs/CREDITS.md` (crates, font lines, then `gen_credits.py`), `ROADMAP.md` O552.

## 5. Decisions for the owner

1. **Setup.** One self-installing exe (recommended) or a separate installer made with a third tool.
2. **Install folder default.** `%LOCALAPPDATA%\CindersOfChaos` (no admin, recommended) or `C:\Games\CindersOfChaos`.
3. **Pack delta.** Chunk hashes for resume, repair and parallel download only (planned), or also content-defined chunking so a small release downloads a small part of the 0.9 GB (more work, later).
4. **News source.** Site news plus patch notes written through the Discord bot (planned, no Discord API in the client), or also a live feed of an announcements channel (needs a bot reading that channel and a new endpoint).
5. **News images.** Optional `imagem` on `/patch gerar` and a default art per tag (planned). Who draws the tag art later is open.
6. **Local `Chaos.exe` for the one-PC zip.** Goes through `CindersLauncher.exe --play-local` (planned). Accept that the full zip now has the launcher too.
7. **Server enforcement.** Log first, enforce later (planned), or no server rule and only the local check.
8. **Unity client.** Exempt in the first release, required from phase D plus one release (planned), or required at once.
9. **Look details.** Fixed 1280x800 canvas scaled on small screens (planned) versus a resizable window; the "Fechar o launcher ao jogar" default (close) versus minimize.
10. **Code-signing certificate.** Still open and now more important: a Setup exe from a new site with no certificate will get SmartScreen warnings.

## 6. Risks

- The borderless, transparent window and everything Windows-specific (registry, shortcuts, picker, SmartScreen, a locked exe on update) cannot be run here. Each is behind a trait or a feature gate and listed as not run, as the first launcher was.
- The key in the launcher exe is a second place to leak the sub key. Accepted: it is a deterrent layer, the server handshake key is not in it.
- `image` adds about 300 KB to the exe and a PNG and JPEG decoder to a program that fetches pictures from the network. Decode only after a size limit (400 KB, 2000x1000), on a thread, a decode failure shows the default art.
- A release that forgets `CHAOS_REQUIRE_LAUNCHER=ON` ships an exe anyone can start by hand. `check_launcher_only.py` fails CI for it.
