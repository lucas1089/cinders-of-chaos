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
8. Shows News and a Changelog under the Play button (tabs "Notícias" / "News" and "Changelog"), from the website's
   launcher feed. See "News and Changelog" below.
9. The in-game Lua updater stays for module-only updates (`files` of the manifest). The two do not overlap: the
   launcher never touches `modules/`, `data/` and so on, the Lua updater never touches native files.

The launcher never replaces a file the manifest does not name, and only `.exe`, `.dll` and `.pack` in the install
folder itself (no sub-folders). It never deletes files. It refuses a manifest older than `baseline` of
`launcher.json` or than the last one it applied.

## Look (O339)

Owner, 2026-10-30 (pt-BR): "faça um launcher mais bonito". The window is dark fantasy: warm black background, ember
(orange-red) accent, gold headings, rounded cards. All colours and widgets are in `src/theme.rs`; `main.rs` only lays
them out.

- Hero banner with the brand logo, then a status card: status line (or progress bar) on the left, the big **Jogar**
  button on the right. The button has hover and pressed looks, and is drawn cold and unclickable while the update runs.
  After an error the card turns red and shows **Tentar de novo** / **Jogar assim mesmo**.
- News and Changelog are cards (title, date, text, "Abrir no site") under tabs with an ember underline. A changelog
  line starts with an ember diamond. The text is still plain text.
- Footer: the version (`v` + `Cargo.toml`) and "Site do jogo" / "Game website", the origin of the `feed` address (hidden
  when there is no feed or it fails the link rules).
- The window icon is the brand icon (`docs/brand/cinders_logo_icon.png`). Size 760x700, resizable, minimum 600x560.
- Art: `tools/gen_launcher_art.py` makes `assets/banner.rgba` (960x300) and `assets/icon.rgba` (128x128) from
  `docs/brand/`, raw RGBA, embedded with `include_bytes!`. `python3 -I launcher/tools/gen_launcher_art.py --check` runs in
  CI (needs Pillow and numpy, the fx venv); `--preview out.png` saves the banner. Change the colours in `theme.rs` and
  `BG` in the generator together.
- Look at it without Windows: build with the default features and run under `xvfb-run` (needs `libxkbcommon-x11-0` and
  Mesa), then take the root window with ImageMagick `import -window root shot.png`.
- No new crate and no new font: egui's built-in fonts.

## Files

- `launcher.json` (beside the exe, written by `client/tools/set_launcher_config.py` from the `Services.update`
  settings of `init.lua`, so the key, the manifest URL and the baseline cannot differ from the game's):
  `{"manifest": "https://.../updates/live/manifest.json", "public_key": "<64 hex>", "baseline": 47, "game": "Chaos.exe"}`.
  Optional `args`: extra arguments for the game. `feed`: URL of the website's launcher feed. The tool writes
  `https://<site>/chaos_launcher_feed.php` (the site of the manifest); `--feed URL` sets another, `--no-feed` writes
  `""`. An old `launcher.json` without `feed` gets the same address derived from the manifest URL (when it has
  `/updates/` in it, else no panels). An empty, non-https or odd `feed` hides the panels and is never an error.
- `.cinders_launcher/` in the install folder: `state.json`, `hashcache.txt`, `feed.json` (last good feed), and while a run is on `stage/`, `backup/`,
  `journal.json`.
- `src/`: `manifest.rs` (envelope, signature, `native` rules), `install.rs` (diff, download, swap, rollback, recovery),
  `selfupdate.rs`, `net.rs` (the system `curl`, built into Windows 10 and 11), `config.rs`, `feed.rs` (News and Changelog), `i18n.rs`, `launch.rs`,
  `main.rs` (egui window, or `--cli [--no-start] [--dir DIR] [--lang pt|en]` for tests and scripts).
- `theme.rs` (window look), `assets/` (embedded art), `tools/gen_launcher_art.py` (makes the art).
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
