//! Starts the game program from the install folder.
use crate::config::{is_plain_name, Config};
use crate::i18n::Error;
use std::process::{Command, Stdio};

/// The ticket for the main client's game (O552 phase D), for the client build `package` (the manifest's native package, the
/// one the run just applied) or, when the run says none (an error, "play anyway"), the one the last good run saved. None when
/// no build is known or the system has no random bytes: the game then shows its own "open it from the launcher" box.
pub fn ticket_for(cfg: &Config, package: Option<u64>) -> Option<String> {
    let build = package.or_else(|| crate::install::saved_package(&cfg.dir))?;
    crate::ticket::for_launch(build)
}

/// Starts `game` (a plain file name in the install folder) and leaves it running on its own. `ticket` goes to the game in
/// the environment variable `CINDERS_TICKET` (and only to it: a ticket in this process's own environment is removed first,
/// so a game can never inherit one that was not made for it).
pub fn start(cfg: &Config, game: &str, ticket: Option<&str>) -> Result<(), Error> {
    if !is_plain_name(game) {
        return Err(Error::NoGame(game.to_string()));
    }
    let exe = cfg.dir.join(game);
    if !exe.is_file() {
        return Err(Error::NoGame(game.to_string()));
    }
    let mut c = Command::new(&exe);
    match ticket {
        Some(t) => c.env(crate::ticket::ENV, t),
        None => c.env_remove(crate::ticket::ENV),
    };
    c.args(&cfg.args)
        .current_dir(&cfg.dir)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
        c.creation_flags(0x0000_0008 | 0x0000_0200);
    }
    c.spawn().map(drop).map_err(|e| Error::Io(format!("{game}: {e}")))
}
