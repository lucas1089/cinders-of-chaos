# Cinders Admin for the PC (O312)

Desktop admin app for the owner's PC. Same job as the Android app (`android/`, `docs/ADMIN_APP.md`): the same
`chaos-ctl.sh` commands, the same SSH key and user. Rust with egui/eframe: one small `.exe`, no installer.

Phase 1 (this folder): a sidebar of categories (below, "Layout (O383)"). Painel starts with the server card: state and
uptime, players online (with the list), errors, memory, disk, load, last backup. Jogadores ends with the progress
metrics (churn, stops, deaths, first session, time to level, returns, first use). They call `status`, `players` and
`metrics --json`; the parsing is pure code in `src/cards.rs` with fixture tests. Also: the page Ao vivo (below), the card Recarregar um
arquivo on Painel do jogo (below) and signed self-updates (below). Not yet: the phone's picture views (spectate, cast),
the key generator.

## Layout (O383)

Owner, 2026-11-03, on 0.3.2: "the app always opens a cmd window", "too many collapsible sections, hard to find what I
look for", "a bigger window for console output". Version 0.4.0:

- **No console.** A release build is a Windows-subsystem program (`#![cfg_attr(all(windows, not(debug_assertions)),
  windows_subsystem = "windows")]` in `src/main.rs`), so no console or Windows Terminal tab opens with it. Every child
  (ssh, ssh-keygen, curl, the restart after a self-update) goes through `ssh::hide_console` (`CREATE_NO_WINDOW`), so no
  console flashes on a button. Nothing needs a console: ssh runs with `BatchMode=yes` and
  `StrictHostKeyChecking=accept-new` (never a password or host key prompt; a refusal lands in the output), ssh-keygen
  gets `-N ""` / `-P ""` and stdin from nowhere, the restart gets no inherited pipes. A debug build (`cargo run`) keeps
  its console.
- **Sidebar.** Left, full height: a search box, then the categories (`Section` in `src/commands.rs`, sidebar order):
  Painel, Ao vivo, Jogadores, Ajustes do jogo, Painel do jogo, Atualizações, Discord, Testers, VPS e manutenção, Logs,
  Config. The selected one has a gold bar. The window opens on the last category (`last_section` in the settings file,
  written alone so an unsaved Config edit stays unsaved); Config while host, user or key are empty.
- **Groups are plain titled cards**, never collapsing headers. Buttons without fields share a wrapped row; a button with
  fields gets its own row. The metrics tables and the online lists are sub headings, always open. Only the game
  catalog (Painel do jogo) keeps its folding categories: it is long and has its own search.
- **Search.** Typing in the box lists the matching buttons of every category in the main area, as the same cards, ready
  to run (fields, confirm, timeouts as on their page). It reads category, card title, button label, help text and field
  labels, without case or accents, every word must match ("webhook" gives Discord > Guardar webhook; "bot reiniciar" gives
  Bot do Discord > Reiniciar). Pages with their own cards (Config, Ao vivo, Painel, Jogadores, Painel do jogo, Logs) are
  found by their words too ("chave" offers Config). The sidebar then shows only the categories with hits and their
  counts. Esc or x clears, Ctrl+F jumps back to the box. Pure code: `src/nav.rs`, tests in `cargo test`.
- **Output panel.** Bottom, under the page, about 40 % of the window at start, resized by dragging its top edge (grip
  in the middle). Monospace, no wrapping, scrolls both ways, follows the end while a command streams: ssh output is shown
  as it arrives (`ssh::exec_stream`), and the final text with the exit code replaces it at the end. Toolbar: the history
  (the last 30 runs, "Seguir a mais recente" or any older one), Copiar (the shown run), Limpar (forgets finished runs;
  running ones stay), Abrir em janela (the output in its own resizable window, which can be maximized; the main window
  keeps a one-line status bar with "Trazer a saída de volta"). The status line and the version with the update note
  stay on the toolbar. One run keeps at most 1 MB of text (the start is dropped a line at a time). `src/output.rs`.
- **Window** 1280x800 at start, minimum 900x600.

The command strings are unchanged; rows only moved between groups and categories (`check_desktop_commands.py` passes).
Moves: Ações rápidas > Atualizar para uma versão and Voltar versão became Atualizações > Versão específica; Logs >
Updates became Atualizações > Logs das atualizações; Logs > Unidades > Log de uma unidade joined VPS e manutenção >
Unidades chaos-*.

## Live view (Ao vivo)

A page that refreshes by itself while it is open: the server state (badge, uptime, players, errors, memory, load, disk),
the players online and the tail of the console log. One ssh call runs the existing `status`, `players` and `logs N`
back to back (a marker line between them, `src/live.rs`), so there is no new command and no daemon on the VPS. Refresh
every 2, 5, 10, 30 or 60 seconds, "Pausar" stops all requests, "Atualizar agora" asks at once, one refresh at a time (a
slow ssh never piles calls up). The log pane shows 40 to 400 lines, filters by text, colours `[Error` and `[Warning`
lines, follows the end or not, and copies what is shown. Nothing is asked while another page is open.

## How it reaches the VPS

It runs the system `ssh` program (OpenSSH, built into Windows 10 and 11) with `-i KEY -p PORT user@host`, and on the
VPS `sudo -n chaos-ctl.sh ARGS`, exactly like the phone. No new port, service or opcode on the server. The host key
is pinned on first use (`StrictHostKeyChecking=accept-new`); a changed key is refused. Passwords (accounts, Discord
webhook) go to the command's stdin, never on a command line.

Install the key on the VPS the way the Android app does. Config page, card "Chave deste PC": "Gerar chave" (only while
the key path is empty) makes an ed25519 key without passphrase next to the settings file (`cinders_admin_ed25519`) and
saves its path; "Copiar comando de instalação" copies `echo 'PUBLIC KEY' | sudo 'CHAOS-CTL' install-admin -` for the VPS
root shell. The public key comes from the private key file (`ssh-keygen -y`), never from a `.pub` beside it (a stale `.pub`
made the VPS refuse the PC on 2026-10-30). `install-admin` adds the key and keeps the others, so the phone and the PC each
keep theirs. `src/keys.rs`, tests in `cargo test`. Fallback: `ssh-keygen -t ed25519` and `chaos-ctl.sh install-admin KEYFILE`.

## Settings

A JSON file, saved by the Config page:

- Windows: `%APPDATA%\CindersAdmin\settings.json`
- Linux: `~/.config/cinders-admin/settings.json`

Keys: `host`, `port` (22), `user` (`chaosadmin`), `key_path`, `ctl_path`
(`/opt/chaos/repo/server/deploy/chaos-ctl.sh`), `actor` (admin character for the game panel and "e aplicar agora"),
`auto_update` (true), `last_section` (the category open last, O383).

## The command table

`src/commands.rs` has one table (`ACTIONS`): category, group, button label, `chaos-ctl.sh` arguments with `{name}`
placeholders, parameters, confirm flag, live kind. The window is drawn from it. The Android app has no shared table,
so the table mirrors it. `tools/ci/check_desktop_commands.py` (CI) fails when Android calls a `chaos-ctl.sh` command
the table lacks, or the table names a command `chaos-ctl.sh` does not have. Add a button: add one `act(...)` line.

The Painel do jogo page asks the game for its admin catalog (`chaos-ctl.sh catalog ACTOR`) and builds a form per
action (`chaos-ctl.sh panel ACTOR ACTION JSON`), like the Android Comandos > Painel do jogo.

## Live apply

Each action has a live kind (`Live` in `src/commands.rs`): when its change takes effect, not a state (owner 2026-10-31
read the old "live" text as a status light). Only kinds with a caveat show a quiet tag beside the button, no dot.
Every kind keeps its tooltip (`Live::label`, `hint`; `rgb` stays for the tests).

| Kind | Tag shown | Meaning | Actions |
|---|---|---|---|
| `Now` | none | read only, or immediate | status, players, logs, broadcast, kick, open, close, save, backup, unit start and stop, accounts, Discord, site, VPS, panel actions |
| `Reload` | none: a second button "... e aplicar agora" | the command writes a file the scripts read at start; the second button then runs the game panel action `reload` (`Game.reload`, no restart) for the named system | Modo beta ligar, desligar (reload `scripts`) |
| `Restart` | "após reiniciar", muted | no live path yet | Taxa de XP definir, voltar ao padrão |
| `Restarts` | "reinicia o servidor", red | the command itself restarts, players are disconnected | restart, update-apply, rollback, testers start, XP and beta "e reiniciar", server-user fix --restart |
| `NextInstall` | none | applies when `install_all.py` runs again | Par do cliente |

"e aplicar agora" needs the admin character in Config (group 4 or more; `reload` is a dangerous panel action, so use it
when few players are on).
It uses the existing `remote.cmd` path, so nothing new runs on the server.

### Gaps (not done in phase 1, no engine change)

- XP rates (`experienceStages` in `config.lua`): whether `Game.reload(config)` re-reads the stages is not checked on a
  live server. Until then the buttons say "needs restart".
- Content edits (spell, item, monster data) are changed by `install_all.py` and `update-apply`, which restart. Balance
  numbers in a `*_config.lua` can be reloaded one file at a time (next section).
- Per-script state is lost on `reload scripts` (tables built at load are rebuilt; running events restart).
- The phone's picture views (`spectate`, `cast`) are not in the desktop app: they need a long ssh stream and a picture view.

## Update and bug report cards (Atualizações, Jogadores)

Two answers show as cards under their group, next to the raw text in the output pane. Atualizações > Atualizar servidor >
Verificar draws a card with "Há atualização" or "Tudo em dia", the new commits, engine, map master, client update,
downloads, site and the last run (`src/infos.rs`, the wording of the phone's `UpdateInfo.java`). Jogadores > Bugs e
sugestões > Abertos (30 dias) or Todos draws one card per report: number, category, open or closed, date, position,
level and class, text and the closing note (`FeedbackInfo.java` and `server/tools/feedback_format.py`). The `from:` name
line is never read. An open report has the button "Usar no Fechar relatório", which writes its number into the id field
of the action Fechar relatório; add a note and press that button. The cards keep the last good answer until the next one.

## Reload one file (Painel do jogo > Recarregar um arquivo)

Pick a config table (`Listar arquivos` fills the list from `chaos-ctl.sh reload-files`; type to filter) and press
`Recarregar NOME`: `chaos-ctl.sh reload-file ACTOR NAME` runs the panel action `server.reload_file`, which copies the new
values of `data/scripts/chaos/NAME.lua` into the running game's tables (server/README.md "Reload one config table
(O312)"). Needs the admin character of Config in group 6, like the system reload. The name is checked here
(`src/reload.rs`: a-z, 0-9, `_`, nothing else), in `chaos-ctl.sh` and in the game. `Quais estão vivos?` lists the tables
the game can reload now. The card says what a reload cannot do: a script file (not `*_config`) is not reloaded alone
(use Server > Reload system > scripts below, or restart), a value a script copied when it loaded changes only after
a scripts reload or restart, and `remote_cmd_config` needs a restart. The reload button is off for anything but a config.

## Look (O344)

Owner, 2026-10-30 (pt-BR): "melhore esse design também". Same family as the game launcher (`launcher/README.md` "Look
(O339)"), tightened for a dense tool. Polish pass 2026-11-02: a forge on the night shift. Quiet warm neutral chrome,
richness only in the header strip and the server status.

- One warm neutral ramp, shared with the Android app (`android/.../res/values/colors.xml`): `BG`, `CARD`, `CARD_EDGE`,
  `INPUT`; text `TEXT`, `TEXT_2`, `MUTED`.
- Ember only for the one main action of a screen and the live dot. The ember dot sits before "No ar" (server card and
  Ao vivo) and nowhere else. Gold only for the selected category of the sidebar (text and bar).
- Headings in sentence case, text colour, 16 px, regular weight. Type scale 12, 13, 14, 16, 20. Status words in
  sentence case, plain coloured text, no pills.
- 4 px grid: button padding 12x4, widget height 28, item spacing 8, card padding 16, card radius 12, controls 8.
- Memory and disk bars: neutral, amber from 80 %, red from 90 %.
- Slim header (52 px) with the brand icon and the title over a strip of ember glow and sparks and a hairline; the
  categories are in the sidebar (O383).
- Every group of commands, the server and metrics cards, the live page and the settings are cards. Settings has aligned
  labels and inputs (paths in monospace) and a second card for the update checkbox and the buttons.
- Buttons: deep ember for the one main action of a card (Salvar, Executar, Rodar, update; light text at 4.5:1), plain
  for the rest, red-edged for a command that asks for a confirmation (restart, rollback, kick).
- Status colours are the same everywhere: ok green, warning amber, error red (`theme.rs` `OK`, `WARN`, `ERROR`): server
  badge, errors count, update banner, console `[Warning` and `[Error` lines, the status text at the bottom ("feito"
  green, "falhou" red).
- Logs and command output sit in dark monospace wells. Output panel toolbar: status, version and update note,
  history, Copiar, Limpar, Abrir em janela.
- Window icon is the brand icon (`docs/brand/cinders_logo_icon.png`). 1280x800, resizable, minimum 900x600.
- Art: `tools/gen_admin_art.py` makes `assets/icon.rgba` (128x128) and `assets/header.rgba` (1280x64) from `docs/brand/`,
  raw RGBA, embedded with `include_bytes!`. `python3 -I desktop/tools/gen_admin_art.py --check` runs in CI (needs
  Pillow and numpy, the fx venv); `--preview out.png` saves the header. Change the colours in `src/theme.rs` and `BG` in
  the generator together. `theme.rs` is adapted from `launcher/src/theme.rs` (no shared crate: two small files).
- Look at it without Windows: build and run under `xvfb-run` (needs `libxkbcommon-x11-0` and Mesa), then
  `import -window root shot.png`. No new crate and no new font.

## Build and run

```
cd desktop
cargo test --locked
cargo run --release
```

Windows needs the Rust toolchain (`rustup`, MSVC target). Linux needs a desktop session (X11 or Wayland). The CI job
"Native checks" runs `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test --locked` and the command table check.

## Updates

At start (and with the Config page button "Procurar versão nova") the app reads the GitHub releases of this repository,
takes the newest release tagged `admin-desktop-vX.Y.Z` that has `cinders-admin.exe` and `cinders-admin.exe.sig`,
and if the version is higher than its own offers "Atualizar e reiniciar o app". It downloads both with `curl` (in
Windows 10 and 11), verifies the signature, renames the running program to `cinders-admin.old`, puts the new one in its
place (the very bytes that were verified) and starts it.

Signed: the same scheme as the game updater and the launcher (`client/MANIFEST.md` "Signed updater"). The `.sig` is an
envelope `{format, key, signature, payload}`; the Ed25519 signature covers the exact bytes of `payload`, a JSON text with
product, version, file name, size and SHA-256. The public key is compiled in from `update_public_key.hex` (never read
from settings, a release or the network). The app refuses (and replaces nothing) when: the build has no key, the
signature is wrong or by another key, the file differs by one byte (hash or size), the signed file name or product is
another, the signed version is not the release tag (a replayed old signature under a new tag) or is not newer than the
running app (downgrade). A release without a `.sig` is not offered. The `.sha256` asset stays for a human to compare.

### One-time key setup

1. `python3 -I client/tools/make_update_manifest.py keygen --private ~/cinders-admin-update.key` (outside the
   repository; the tool refuses a path inside a git work tree). It prints the public key.
2. Put the public key (64 hex digits) in `desktop/update_public_key.hex` instead of the zeros and commit. Until then
   every build refuses every update (and the workflow refuses to publish).
3. GitHub > Settings > Secrets > Actions: `ADMIN_DESKTOP_SIGNING_KEY` = the text of the private key file. Back the file up
   offline. Losing it means shipping a new build by hand with a new public key; old apps then cannot self-update.

### Publish a new version

1. Raise `version` in `desktop/Cargo.toml`, run `cargo build` once so `Cargo.lock` follows, commit.
2. GitHub > Actions > "admin-desktop" > Run workflow, input the same version.
3. The workflow (manual only, like `windows-package.yml`) tests, builds on Windows, signs with
   `tools/sign_release.py` (it refuses a key that is not the one in `update_public_key.hex`, then verifies its own
   output) and creates the release `admin-desktop-vX.Y.Z` with the `.exe`, the `.sig` and the `.sha256`. Open apps pick
   it up at the next start.

Not yet run on GitHub: the workflow and the swap on Windows are untested (the swap has a unit test on Linux). The Python
signer and the Rust verifier share one test vector (`testdata/sign_vector.json`, checked by both
`tools/sign_release_test.py` and `cargo test`).

## Shared code

SHA-256, version compare and the staged rename live in `../crates/selfupdate/`, shared with the game launcher
(`../launcher/`, O314).

## Credits

Crates that ship: eframe and egui (MIT or Apache-2.0), serde_json (MIT or Apache-2.0), sha2 (MIT or Apache-2.0),
ed25519-compact (MIT), and their dependencies. Listed in `docs/CREDITS.md`.
