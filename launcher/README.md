# Cinders of Chaos launcher (O314)

A small Rust program that runs before the game. It updates the files the in-game updater never touches: `Chaos.exe`,
its DLLs and `chaos.pack`. Then the player presses **Jogar** and the game starts. Before it, every engine patch meant
a new download of the client from the website (`min_package`). Now the launcher fetches the change.

Status: done in code and tests (Linux). Not run on Windows. Open: code-signing certificate, install path.

## What it does

1. Starts before the game (`CindersLauncher.exe`, the entry point of the separate client download).
2. Fetches the same Ed25519-signed `manifest.json` as the in-game updater (`client/MANIFEST.md` "Signed updater") and
   checks the signature with the same public key. Wrong key, bad signature, other product, older version: nothing runs.
3. Reads the manifest's `native` section (the in-game updater ignores it). Compares each file with the install by
   SHA-256 (cache by size and mtime in `.cinders_launcher/hashcache.txt`).
4. Downloads what changed into `.cinders_launcher/stage/`. A cut download resumes with a `Range` request, 5 retries
   with backoff. Every file is checked against the signed hash before anything in the install changes.
5. Swaps the files in one transaction: journal, old file to `backup/`, staged file in place, `.exe` last. A failure
   puts the old files back. A crash in the middle is undone at the next start from the journal.
6. Updates itself: a new launcher is staged as `CindersLauncher.new` plus `CindersLauncher.new.sha256`. At its next
   start the launcher checks the hash, renames itself to `CindersLauncher.old`, puts the new one in place and starts it
   again. The same staged rename as the desktop admin app (`crates/selfupdate`).
7. Shows progress and errors in pt-BR or en (`CINDERS_LANG`, `LC_ALL`, `LANG`; pt-BR when none is set), with the
   buttons Jogar, Tentar de novo and Jogar assim mesmo. When the server is unreachable the player can still play.
8. Shows the News and the Changelog as one carousel of cards (tag, picture, build, date, text), from the website's launcher feed. See "News and Changelog" below.
9. The in-game Lua updater stays for module-only updates (`files` of the manifest). The two do not overlap: the
   launcher never touches `modules/`, `data/` and so on, the Lua updater never touches native files.

The launcher never replaces a file the manifest does not name, and only `.exe`, `.dll` and `.pack` in the install
folder itself (no sub-folders). It never deletes files. It refuses a manifest older than `baseline` of
`launcher.json` or than the last one it applied.

## Client choice (Unity client beta, O433 phase 16)

Owner 2026-11-07 (pt-BR): "Quero que os jogadores consigam jogar em ambos os clientes." The window has a row "Cliente: Cliente principal | Cliente Unity (beta)"
(`Client:` / `Main client` / `Unity client (beta)` in English) above the status card. It is there only when the Unity manifest address is known. The choice is
saved in `.cinders_launcher/settings.json` (`{"client": "unity"}`; missing or odd means the main client) and the next start opens on it. Changing it while an
update runs is not possible; changing it starts the update of the other client at once. `--client main|unity` picks one for a run of `--cli` or the window
(not saved).

- **Same code.** The Unity client goes through `Updater` like the main one: the same Ed25519 key and envelope, the same `native` section rules for hashes and
  sizes, resumed downloads, journaled swap, rollback and crash recovery. `choice::update` is the one entry point (`src/choice.rs`).
- **Own folder, own manifest.** Unity lives in `unity/` inside the game folder, with its own `.cinders_launcher/` state (version counter, hash cache, stage,
  backup, journal). Its manifest is `updates/unity/manifest.json` of the same site, written by `publish_client_update.sh --unity`. The address is derived from
  `manifest` of `launcher.json` (`.../updates/live/manifest.json` becomes `.../updates/unity/manifest.json`); optional keys `unity_manifest` (an https address;
  `""` hides the choice) and `unity_game` (default `ChaosUnity.exe`). Nothing in `launcher.json` is written by the launcher.
- **Tree layout.** The main client's `native` section is plain names (`.exe`, `.dll`, `.pack`, no sub-folders). The Unity player is a tree, so its section says
  `"layout": "tree"` and lists relative paths (`manifest.rs` `Layout::Tree`, `check_tree_path`, the same rules as `client/tools/make_unity_manifest.py`): at most
  4096 files and 12 folders deep, names of ASCII letters, digits and `. _ - space`, no device names, no script or shortcut endings, `.exe` only in the root.
  A manifest of one layout is refused as the other. Folders are made when a file goes in, and removed when the last file of an old release leaves them
  (a folder the player filled, like `unity/things/`, stays; the launcher only removes files an earlier manifest listed).
- **The launcher still updates itself.** The Unity manifest has no launcher entry. After the Unity update the launcher reads the main manifest in `launcher_only` mode
  (best effort, silent): only `CindersLauncher.exe` is looked at, nothing else is hashed, downloaded or installed, no state is saved. A player who only uses
  Unity still gets a new launcher; a dead main manifest never stops the Unity update.
- **What Unity needs on the player's side.** Nothing by hand (O433 phase 17, unity/README.md "Sprite pair"): the unity channel carries the sprite pair as the main
  client's encrypted blobs (`things_enc/*.chub`, installed like any file), and the player also finds the main client's `chaos.pack` one folder up. The window shows a
  note under the choice.
- **Channel not published (O494).** The choice is offered whenever the Unity address is known, even before the owner has run "Publicar client Unity". The manifest then
  answers 404 (or 410). The launcher tells that apart from a network failure: `net::FetchError` carries the HTTP status (`curl -w %{http_code}`, with curl's own
  "returned error: NNN" text as a fallback; `--fail` makes curl exit 22 for every status of 400 or more, so the exit code alone is not the status), and
  `install::manifest_fetch_error` maps it. For Unity, 404 or 410 is `Error::UnityNotPublished`: "The Unity client has not been published yet. Use the main client."
  (pt-BR "O cliente Unity ainda não foi publicado. Use o cliente principal."), no curl tail. The box has one button, "Use the main client", which saves the choice
  and updates the main client; "Play anyway" stays only when `unity/<unity_game>` exists. `--cli --client unity` prints the same text, exits 1 and starts nothing
  (no fallback to the main client). Rule: `choice::buttons`.

Error table (the manifest fetch):

| Answer | Error | Text (en) | Buttons |
|---|---|---|---|
| no answer (curl 6, 7, 28, 35, 60) | `Network` | Could not reach the update server. Check your internet and try again. | Try again, Play anyway |
| HTTP 400 or more, main client | `Http(status)` | The update server answered with an error (HTTP 404). Try again in a few minutes. | Try again, Play anyway |
| HTTP 404 / 410, Unity client | `UnityNotPublished` | The Unity client has not been published yet. Use the main client. | Use the main client (+ Play anyway if installed) |
| HTTP other than 404 / 410, Unity client | `Http(status)` | as for the main client | Try again, Play anyway |

The news feed and the launcher's own update are not louder: the feed falls back to the saved copy or to "could not be loaded" on any failure, a 404 included, and shows no
error; the launcher's own file is fetched inside the update, and in a Unity run its manifest read is silent.
- **Dev packages.** A Unity package built without the client key says `"dev": true` in its `native` section (`Native::dev`, absent means false). The launcher installs
  nothing of it and shows "The published Unity client is a development build ... not offered to players" (`Error::DevPackage`); testers run `--allow-dev-unity`
  (or `CINDERS_ALLOW_DEV_UNITY=1`). Only the Unity layout is checked; the main client's manifest never carries the flag.
- Tests: `src/manifest.rs`, `src/config.rs`, `src/i18n.rs` (unit), `tests/unity_update.rs` (12 cases against the local HTTP server: nested first install and no-op,
  change and removal with the player's files kept, a hand-changed file, rollback at every step, bad hash and signature, paths out of the folder, the wrong
  client's manifest, own version counter, the choice, the launcher's self-update from a Unity run, no address, the saved choice) and `tests/vector.rs`
  (a Unity manifest signed by `make_unity_manifest_test.py`). Phase 17 added the dev flag: `manifest.rs` (boolean, default false), `unity_update.rs` (a dev package refused with
  nothing installed and no state saved, allowed with `allow_dev`, a keyed one with `dev` false or absent).

## Look (O339, new look O552)

Owner, 2026-10-30 (pt-BR): "faça um launcher mais bonito". Owner, 2026-11-13: a launcher like the one in a reference picture, then "mude um
pouco o visual pra não ficar igual": the layout is our own, built from the game's ornate skin. Design record: `DESIGN.md`.

- **Window.** Borderless, fixed 1280x800 canvas (`src/layout.rs`, every rectangle in one place, unit tested for overlaps), own title bar:
  ember dot, name, version, PT | EN pill, settings gear, minimize, close; the bar drags the window. A screen smaller than the canvas
  gets `layout::scale_for` (a 1366x768 laptop draws at 0.90). Not resizable.
- **Art.** The login art as the background, the brand logo in the middle, the game skin's corner ornaments and crest, the login screen's
  octagon buttons for the link rail and JOGAR (nine-sliced). All of it is embedded from `assets/`, made by `tools/gen_launcher_art.py`
  from `client/overlay/data/images/chaos/`, `docs/brand/` and `client/fonts-src/` (`--check` in CI: copies byte for byte, pictures within
  2 of 255). Fonts: Cinzel weight 700 for titles, Alegreya Sans for text (both OFL, in `docs/CREDITS.md`).
- **Rail, left.** Discord, Site, Wiki, Conta from `launcher.json` `links` (`config::parse_links`: a key left out derives from the site of the
  manifest as `/`, `/wiki`, `/register`, Discord has no default; `""` or a non-https link hides the button). `set_launcher_config.py`
  `--discord URL --site URL --wiki URL --signup URL` writes them.
- **News strip, below the logo.** The feed's News and Changelog merged by date (`Feed::cards`, 12 at most), four cards on the strip with
  an arrow pair, a counter and dots (`src/carousel.rs`, 8 s auto-advance, paused while the mouse is on the strip or a panel is open, 24 s rest
  after a click). A card: picture, tag chip (`ATUALIZAÇÃO`, `NOTÍCIA`, `EVENTO`, `MANUTENÇÃO`, `AVISO`), title, "Build N · há 2 dias"
  (`fmt::relative`), two lines of text. A click opens the reading panel (full text, "Abrir no site"). Pictures: the item's `image` (https,
  at most 400 KB, 2000x1000, PNG or JPEG, decoded on a thread, `src/images.rs`), else the default art of its tag. See "News and Changelog".
- **Bottom bar.** Status dot and line (ember working, gold ready, red on error), the client chip (`Cliente principal · 47 ▾`, a menu with
  the two clients when the Unity address is known, disabled while updating), the progress bar (eased, ember to gold), bytes and files
  (`24,3 MB de 1,1 GB · 1/12 arquivos`), speed over 3 s and time left (`fmt::Speed`), and JOGAR (cold while updating, absent after an error,
  where "Tentar de novo" / "Jogar assim mesmo" / "Usar o cliente principal" take the progress place by the same `choice::buttons` rule).
- **Settings (gear).** Game folder with "Abrir pasta", "Fechar o launcher ao jogar" (on by default, else it minimizes), language, version.
  Saved in `.cinders_launcher/settings.json` (`config::Settings`: `client`, `lang`, `close_on_play`).
- **Window icon** is the brand icon. No icon pack and no SVG: the icons are painter shapes (`theme.rs`).
- Look at it without Windows: build with the default features and run under `xvfb-run` (needs `libxkbcommon-x11-0` and Mesa), then take the
  root window with ImageMagick `import -window root shot.png`.

## Files

- `launcher.json` (beside the exe, written by `client/tools/set_launcher_config.py` from the `Services.update`
  settings of `init.lua`, so the key, the manifest URL and the baseline cannot differ from the game's):
  `{"manifest": "https://.../updates/live/manifest.json", "public_key": "<64 hex>", "baseline": 47, "game": "Chaos.exe"}`.
  Optional `unity_manifest`, `unity_game`: the Unity client beta, see "Client choice".
  Optional `args`: extra arguments for the game. `feed`: URL of the website's launcher feed. The tool writes
  `https://<site>/chaos_launcher_feed.php` (the site of the manifest); `--feed URL` sets another, `--no-feed` writes
  `""`. An old `launcher.json` without `feed` gets the same address derived from the manifest URL (when it has
  `/updates/` in it, else no panels). An empty, non-https or odd `feed` hides the panels and is never an error.
- `.cinders_launcher/` in the install folder: `state.json`, `hashcache.txt`, `feed.json` (last good feed), `settings.json` (the client choice), and
  while a run is on `stage/`, `backup/`, `journal.json`. `unity/.cinders_launcher/` holds the same for the Unity client.
- `src/`: `manifest.rs` (envelope, signature, `native` rules), `install.rs` (diff, download, swap, rollback, recovery),
  `selfupdate.rs`, `net.rs` (the system `curl`, built into Windows 10 and 11), `config.rs` (also the client choice), `choice.rs` (update the chosen client),
  `feed.rs` (News and Changelog), `i18n.rs`, `launch.rs`,
  `main.rs` (egui window, or `--cli [--no-start] [--dir DIR] [--lang pt|en] [--client main|unity] [--allow-dev-unity]` for tests and scripts).
- `theme.rs` (colours, skin, icons, drawing helpers), `ui.rs` (the window), `layout.rs`, `carousel.rs`, `fmt.rs`, `images.rs` (pure and tested), `assets/` (embedded art), `tools/gen_launcher_art.py` (makes the art).
- `../crates/selfupdate/`: SHA-256, version compare and the staged rename, shared with `desktop/`.

## News and Changelog

The website serves one small public JSON, `chaos_launcher_feed.php` (website/README.md "Launcher feed"): the latest
news of the site (ZnoteX news, the front page's) and the changelog, which is the weekly patch notes
(`server/data/patchnotes/*.md` and their `.pt-br.md` twins), in pt-BR and en. There is no second source to keep.

- **Fetch.** `feed.rs` uses the same system `curl` (`Fetch::get_small`): 5 s to connect, 10 s in all, 128 KiB at most.
  It runs on its own thread after the window opens. It never gates the update, `Jogar` or `Jogar assim mesmo`, and a
  retry of the update fetches it again only when the panels show no fresh feed.
- **Cache.** A good feed is saved as `.cinders_launcher/feed.json` (temporary file, rename). When the fetch fails or
  the answer is broken, too big, not JSON or not format 1, the saved copy is shown with the note "Sem conexão com o
  site. Mostrando a última cópia salva." With no copy the panel says that the news could not be loaded and that the
  player can still play. No error dialog, no log to the player.
- **Plain text.** Everything is shown as text: control, direction and zero-width characters are removed, spaces
  squeezed, counts (10 items, 12 lines) and lengths capped. An item of the wrong shape is dropped, the rest is shown.
  The window has no HTML or Markdown rendering.
- **Links.** "Abrir no site" opens the item's page in the browser (egui `open_url`). Only `https://` addresses
  without spaces, non-ASCII or `user@` open (a loopback `http://` only in tests); any other link is dropped from the item.
- **Card fields (O552).** Optional per item: `tag` (`update`, `news`, `event`, `maintenance`, `notice`; anything else is `news`, a changelog
  entry without one is `update`), `build` (digits, shown as "Build N") and `image` (an https address). The site writes them from the
  header lines `Tag:`, `Build:` and `Image:` of a patch note (a plain file name under `assets/launcher/` of the site, jpg or png), see
  website/README.md "Launcher feed". Not done: an image attached in the Discord bot's `/patch` command.
- **Language.** The same pick as the rest of the window (`CINDERS_LANG`, `LC_ALL`, `LANG`; pt-BR when none).
  The feed has one block per language; a missing block falls back to the other one.

## The manifest side

`client/tools/make_update_manifest.py build ... --native-dir DIR --native-package N [--native-game Chaos.exe]
[--native-launcher CindersLauncher.exe]` adds a `native` section to the signed payload and publishes the files as
plain blobs in `updates/live/native/<sha[:2]>/<sha>` (the package ships them plain anyway; `chaos.pack` is already
ciphertext). Old clients read `files` only and ignore the new key, so they keep working. `publish_client_update.sh`
passes it by itself when the client zip holds `CindersLauncher.exe`. Details: `client/MANIFEST.md` "Game launcher".

## Release steps

A new launcher or a new engine build goes out like any client release. No manual upload of the exe.

1. Raise the client build number if the exe or the pack format changed (workflow input `client_build`, also
   `min_package`). Raise `version` in `launcher/Cargo.toml` when the launcher changed, and run `cargo build` once so
   `Cargo.lock` follows. Commit.
2. Run the workflow "Windows package" (`windows-package.yml`, manual). The client job builds `CindersLauncher.exe`
   (Rust, `--locked`, static C runtime) and puts it in the client folder. The download job writes `launcher.json`
   from the `init.lua` settings and packs. Needs the repository inputs `update_manifest` and `update_public_key`
   (a package without them has its updater off and gets no launcher). The inputs come from the private branch
   `windows-assets` as before. Never push to that branch from a launcher change.
3. Publish: admin app (phone or PC), tab Comandos, card "Site e update do client", field "Release do client"
   (winpkg-N), button "Publicar update". Shell fallback on the VPS: `chaos-ctl.sh publish-update winpkg-N`. The publisher adds the `native` section because the zip holds the
   launcher. Players with the launcher get the new exe, DLLs and pack at their next start, with no website download.
4. Check: `python3 -I client/tools/make_update_manifest.py verify /var/www/chaos/updates/live --public <key>` prints
   the native file count and package.
5. Players with an old client (no launcher) still see "A new client download is required" for a new `min_package`.
   Their one manual download is the zip that has the launcher.

The feed is tested in `src/feed.rs` (parsing, both languages, size limit, odd items, link rules, cache fallback) and in
`tests/mass_update.rs` (the feed served by the local HTTP server: fresh, 404, server down, oversize, HTML, and a dead
feed that leaves the update untouched).

Local checks: `cd launcher && cargo fmt --check && cargo clippy --locked --all-targets -- -D warnings && cargo test
--locked`. The test `tests/mass_update.rs` serves a fake manifest and files from `127.0.0.1` and updates a fake install
120 rounds in a row with random trouble, plus single cases for each failure. It needs `curl`. `tests/vector.rs` reads
a manifest signed by the Python tool (`launcher/tests/data/python_manifest.json`; rewrite it with
`UPDATE_LAUNCHER_VECTOR=1 python3 -I client/tools/make_update_manifest_test.py`).

Run in a window: `cargo run --release -- --dir PATH_WITH_launcher.json`. Without a window:
`cargo run --release -- --cli --no-start --dir PATH`.

## Open

- **Code-signing certificate.** An unsigned exe that downloads and swaps programs is what antivirus tools and
  SmartScreen distrust. Without a certificate expect warnings. Buy one (OV or EV) and sign `CindersLauncher.exe` in
  the workflow before packing, and `Chaos.exe` with it.
- **Install path.** The launcher writes into its own folder. A folder where the player has no write rights (for
  example `C:\Program Files`) fails with a disk error. Today the zip is extracted by hand (a short path in the user's
  folder). A per-user installer (`%LOCALAPPDATA%\CindersOfChaos`, no admin rights) is not built.
- **Not run on Windows.** The swap on Windows (renaming a loaded exe and DLL, a locked file while the game runs) and
  `curl.exe` there are untested. Close the game before the launcher runs. The Linux tests cover the logic.
- **Pack size.** `chaos.pack` is one file of about 0.9 GB. When it changes, the whole file is downloaded (resumable).
  A release that only changes Lua still reaches players through the in-game updater, not the pack.
- **Rollback of a bad launcher.** `CindersLauncher.old` stays after a self-update. A launcher that does not start
  needs the old file renamed back by hand.

## Credits

Crates that ship: eframe and egui, serde_json, sha2 (the shared crate), ed25519-compact (MIT), and their dependencies.
Listed in `docs/CREDITS.md`.
