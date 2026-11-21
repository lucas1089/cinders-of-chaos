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

/// Upper bound of what `warm` reads in one run (a pack is about 0.9 GB; more than this is not a game file of ours).
pub const WARM_LIMIT: u64 = 4 << 30;

/// The files `warm` reads, in order: the game program, then every `*.pack` directly in the folder (O705). Plain names only,
/// regular files only, sorted so the order is the same every run.
pub fn warm_list(dir: &std::path::Path, game: &str) -> Vec<std::path::PathBuf> {
    let mut out = Vec::new();
    if is_plain_name(game) && dir.join(game).is_file() {
        out.push(dir.join(game));
    }
    let mut packs: Vec<std::path::PathBuf> = std::fs::read_dir(dir)
        .map(|rd| {
            rd.flatten()
                .map(|e| e.path())
                .filter(|p| {
                    p.is_file()
                        && p.extension().is_some_and(|x| x.eq_ignore_ascii_case("pack"))
                        && p.file_name().and_then(|n| n.to_str()).is_some_and(is_plain_name)
                })
                .collect()
        })
        .unwrap_or_default();
    packs.sort();
    out.extend(packs);
    out
}

/// Reads the game's big files once, front to back, and throws the bytes away, so that the operating system's file cache
/// holds them when the player presses Play (O705). The game reads `chaos.pack` (about 0.9 GB) at its start, decrypts and
/// inflates it into memory; from a cold disk that read is the first seconds of "Play" (a hard disk gives 80-150 MB/s), from
/// the cache it is a memory copy. The launcher is open for several seconds anyway (the news, the update check), so this
/// costs the player nothing. Meant for a thread of its own; `stop` ends it (the player pressed Play: from then on two
/// readers would only make a hard disk seek). Errors end it quietly: it is an optimisation, never a reason to show a
/// message. Returns the bytes read.
pub fn warm(dir: &std::path::Path, game: &str, stop: &std::sync::atomic::AtomicBool) -> u64 {
    use std::io::Read;
    use std::sync::atomic::Ordering;
    let mut buf = vec![0u8; 4 << 20];
    let mut total = 0u64;
    for path in warm_list(dir, game) {
        let Ok(mut f) = open_sequential(&path) else {
            continue;
        };
        loop {
            if stop.load(Ordering::Relaxed) || total >= WARM_LIMIT {
                return total;
            }
            match f.read(&mut buf) {
                Ok(0) | Err(_) => break,
                Ok(n) => total += n as u64,
            }
        }
    }
    total
}

/// Opens a file for one front-to-back read (the cache manager reads ahead on Windows with FILE_FLAG_SEQUENTIAL_SCAN).
fn open_sequential(path: &std::path::Path) -> std::io::Result<std::fs::File> {
    let mut o = std::fs::OpenOptions::new();
    o.read(true);
    #[cfg(windows)]
    {
        use std::os::windows::fs::OpenOptionsExt;
        o.custom_flags(0x0800_0000); // FILE_FLAG_SEQUENTIAL_SCAN
    }
    o.open(path)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicBool, Ordering};

    fn tmp(name: &str) -> std::path::PathBuf {
        let d = std::env::temp_dir().join(format!("cinders-warm-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn warm_reads_the_game_and_the_packs_and_nothing_else() {
        let d = tmp("list");
        std::fs::write(d.join("Chaos.exe"), vec![1u8; 1000]).unwrap();
        std::fs::write(d.join("chaos.pack"), vec![2u8; (9 << 20) + 5]).unwrap(); // more than two chunks
        std::fs::write(d.join("Other.PACK"), vec![3u8; 10]).unwrap();
        std::fs::write(d.join("notes.txt"), vec![4u8; 77]).unwrap();
        std::fs::write(d.join("launcher.json"), "{}").unwrap();
        std::fs::create_dir_all(d.join("sub.pack")).unwrap(); // a folder is not a file
        let names: Vec<String> = warm_list(&d, "Chaos.exe")
            .iter()
            .map(|p| p.file_name().unwrap().to_string_lossy().into_owned())
            .collect();
        assert_eq!(names.len(), 3, "{names:?}");
        assert_eq!(names[0], "Chaos.exe", "the program first");
        assert!(names.contains(&"chaos.pack".to_string()) && names.contains(&"Other.PACK".to_string()));
        let stop = AtomicBool::new(false);
        assert_eq!(warm(&d, "Chaos.exe", &stop), 1000 + (9 << 20) + 5 + 10);
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn warm_stops_when_told_and_survives_a_missing_game() {
        let d = tmp("stop");
        std::fs::write(d.join("chaos.pack"), vec![2u8; 6 << 20]).unwrap();
        let stop = AtomicBool::new(true);
        assert_eq!(warm(&d, "Chaos.exe", &stop), 0, "stopped before the first chunk");
        stop.store(false, Ordering::Relaxed);
        assert_eq!(
            warm(&d, "Chaos.exe", &stop),
            6 << 20,
            "no game file: the pack is still read"
        );
        // a game name with a path is not read
        assert!(warm_list(&d, "../x.exe")
            .iter()
            .all(|p| p.extension().is_some_and(|x| x == "pack")));
        assert_eq!(warm(&d.join("missing"), "Chaos.exe", &stop), 0);
        let _ = std::fs::remove_dir_all(&d);
    }
}
