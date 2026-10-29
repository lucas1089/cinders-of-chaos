//! Starts the game program from the install folder.
use crate::config::{is_plain_name, Config};
use crate::i18n::Error;
use std::process::{Command, Stdio};

/// Starts `game` (a plain file name in the install folder) and leaves it running on its own.
pub fn start(cfg: &Config, game: &str) -> Result<(), Error> {
    if !is_plain_name(game) {
        return Err(Error::NoGame(game.to_string()));
    }
    let exe = cfg.dir.join(game);
    if !exe.is_file() {
        return Err(Error::NoGame(game.to_string()));
    }
    let mut c = Command::new(&exe);
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
