# Cinders Admin for the PC (O312)

Desktop admin app for the owner's PC. Same job as the Android app (`android/`, `docs/ADMIN_APP.md`): the same tabs, the
same `chaos-ctl.sh` commands, the same SSH key and user. Rust with egui/eframe: one small `.exe`, no installer.

Phase 1 (this folder): tabs Painel, Comandos, Logs, Painel do jogo, Config. Not yet: live view (spectate, cast), the
metrics and status dashboards as cards (the text answer shows in the output pane), the key generator.

## How it reaches the VPS

It runs the system `ssh` program (OpenSSH, built into Windows 10 and 11) with `-i KEY -p PORT user@host`, and on the
VPS `sudo -n chaos-ctl.sh ARGS`, exactly like the phone. No new port, service or opcode on the server. The host key
is pinned on first use (`StrictHostKeyChecking=accept-new`); a changed key is refused. Passwords (accounts, Discord
webhook) go to the command's stdin, never on a command line.

Install the key on the VPS the way the Android app does (Config tab, "Copiar comando de instalação", or
`chaos-ctl.sh install-admin KEYFILE`). Use the same key file as the phone or a new one: `ssh-keygen -t ed25519`.

## Settings

A JSON file, saved by the Config page:

- Windows: `%APPDATA%\CindersAdmin\settings.json`
- Linux: `~/.config/cinders-admin/settings.json`

Keys: `host`, `port` (22), `user` (`chaosadmin`), `key_path`, `ctl_path`
(`/opt/chaos/repo/server/deploy/chaos-ctl.sh`), `actor` (admin character for the game panel and Apply live),
`auto_update` (true).

## The command table

`src/commands.rs` has one table (`ACTIONS`): tab, group, button label, `chaos-ctl.sh` arguments with `{name}`
placeholders, parameters, confirm flag, live kind. The window is drawn from it. The Android app has no shared table,
so the table mirrors it. `tools/ci/check_desktop_commands.py` (CI) fails when Android calls a `chaos-ctl.sh` command
the table lacks, or the table names a command `chaos-ctl.sh` does not have. Add a button: add one `act(...)` line.

The Painel do jogo page asks the game for its admin catalog (`chaos-ctl.sh catalog ACTOR`) and builds a form per
action (`chaos-ctl.sh panel ACTOR ACTION JSON`), like the Android Comandos > Painel do jogo.

## Live apply

Every button shows how its change reaches the running game:

| Mark | Meaning | Actions |
|---|---|---|
| live | read only, or immediate | status, players, logs, broadcast, kick, open, close, save, backup, unit start and stop, accounts, Discord, site, VPS, panel actions |
| live with Apply live | the command writes a file the scripts read at start; the second button "... + Apply live" then runs the game panel action `reload` (`Game.reload`, no restart) for the named system | Modo beta ligar, desligar (reload `scripts`) |
| needs restart | no live path yet | Taxa de XP definir, voltar ao padrão |
| restarts the server | the command itself restarts, players are disconnected | restart, update-apply, rollback, testers start, XP and beta "e reiniciar", server-user fix --restart |
| next install | applies when `install_all.py` runs again | Par do cliente |

Apply live needs the admin character in Config (group 4 or more; `reload` is a dangerous panel action, so use it when few players are on).
It uses the existing `remote.cmd` path, so nothing new runs on the server.

### Gaps (not done in phase 1, no engine change)

- XP rates (`experienceStages` in `config.lua`): whether `Game.reload(config)` re-reads the stages is not checked on a
  live server. Until then the buttons say "needs restart".
- Content and balance edits (spell, item, monster numbers) are changed by `install_all.py` and `update-apply`, which
  restart. A hot reload of one script or one `*_config.lua` needs an admin action that reloads one file; `reload`
  reloads a whole system (`scripts` reloads every revscript and clears event callbacks).
- Per-script state is lost on `reload scripts` (tables built at load are rebuilt; running events restart).
- The phone's live view (`spectate`, `cast`) is not in phase 1: it needs a long ssh stream and a picture view.

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
takes the newest release tagged `admin-desktop-vX.Y.Z` that has `cinders-admin.exe` and `cinders-admin.exe.sha256`,
and if the version is higher than its own offers "Atualizar e reiniciar o app". It downloads with `curl` (in Windows
10 and 11), checks the SHA-256, renames the running program to `cinders-admin.old`, puts the new one in its place and
starts it. A wrong checksum refuses the update. No signing key yet: the trust is GitHub release access of the
repository (acceptable for a tool that runs only on the owner's PC; the checksum catches broken downloads only).

### Publish a new version

1. Raise `version` in `desktop/Cargo.toml`, run `cargo build` once so `Cargo.lock` follows, commit.
2. GitHub > Actions > "admin-desktop" > Run workflow, input the same version.
3. The workflow (manual only, like `windows-package.yml`) tests, builds on Windows and creates the release
   `admin-desktop-vX.Y.Z` with the `.exe` and its `.sha256`. Open apps pick it up at the next start.

Not yet run on GitHub: the workflow and the swap on Windows are untested (the swap has a unit test on Linux).

## Credits

Crates that ship: eframe and egui (MIT or Apache-2.0), serde_json (MIT or Apache-2.0), sha2 (MIT or Apache-2.0), and
their dependencies. Listed in `docs/CREDITS.md`.
