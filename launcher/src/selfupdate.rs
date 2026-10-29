//! The launcher updates itself by a staged rename at its next start, like the desktop admin app (crates/selfupdate):
//! a run downloads and checks the new launcher, puts it beside the running one as `NAME.new` with `NAME.new.sha256`;
//! the next start checks the file against that hash, renames the running exe to `NAME.old`, the new one to `NAME.exe`,
//! and starts it again. A `.new` without a matching hash (a crash while staging, a changed file) is deleted.
use cinders_selfupdate::hash::{parse_sha, sha256_file};
use std::path::{Path, PathBuf};

pub const RESTARTED_ENV: &str = "CINDERS_LAUNCHER_RESTARTED";

pub fn pending(exe: &Path) -> PathBuf {
    exe.with_extension("new")
}

pub fn pending_sha(exe: &Path) -> PathBuf {
    let mut s = pending(exe).into_os_string();
    s.push(".sha256");
    PathBuf::from(s)
}

/// Moves a verified file (named by its SHA-256) into place as the pending launcher. Sidecar first, file last, both
/// by rename, so `NAME.new` exists only when it is complete.
pub fn stage(exe: &Path, file: &Path, sha: &str) -> Result<(), String> {
    let side = pending_sha(exe);
    let tmp = side.with_extension("tmp");
    std::fs::write(&tmp, format!("{sha}\n")).map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(&side);
    std::fs::rename(&tmp, &side).map_err(|e| e.to_string())?;
    let new = pending(exe);
    let _ = std::fs::remove_file(&new);
    std::fs::rename(file, &new).map_err(|e| format!("cannot stage the new launcher: {e}"))
}

/// The SHA-256 of the staged launcher, when one is staged and whole.
pub fn staged_sha(exe: &Path) -> Option<String> {
    let want = parse_sha(&std::fs::read_to_string(pending_sha(exe)).ok()?)?;
    (sha256_file(&pending(exe)).ok()? == want).then_some(want)
}

#[derive(Debug, PartialEq, Eq)]
pub enum Applied {
    /// Nothing staged.
    None,
    /// The staged launcher is now `exe`; start it again.
    Swapped,
    /// A staged file was damaged and was deleted.
    Discarded,
}

/// First thing at start. Err means the swap itself failed and the old launcher is still in place.
pub fn apply_pending(exe: &Path) -> Result<Applied, String> {
    let (new, side) = (pending(exe), pending_sha(exe));
    if !new.exists() && !side.exists() {
        return Ok(Applied::None);
    }
    if staged_sha(exe).is_none() {
        let _ = std::fs::remove_file(&new);
        let _ = std::fs::remove_file(&side);
        return Ok(Applied::Discarded);
    }
    cinders_selfupdate::swap::swap(exe, &new)?;
    let _ = std::fs::remove_file(&side);
    Ok(Applied::Swapped)
}

#[cfg(test)]
mod tests {
    use super::*;
    use cinders_selfupdate::hash::sha256_hex;

    fn dir(n: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("cinders-launcher-self-{n}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn stage_then_apply_swaps_once() {
        let d = dir("ok");
        let exe = d.join("L.exe");
        std::fs::write(&exe, b"old launcher").unwrap();
        let f = d.join("blob");
        std::fs::write(&f, b"new launcher").unwrap();
        assert_eq!(apply_pending(&exe), Ok(Applied::None));
        stage(&exe, &f, &sha256_hex(b"new launcher")).unwrap();
        assert!(staged_sha(&exe).is_some());
        assert_eq!(apply_pending(&exe), Ok(Applied::Swapped));
        assert_eq!(std::fs::read(&exe).unwrap(), b"new launcher");
        assert_eq!(std::fs::read(d.join("L.old")).unwrap(), b"old launcher");
        assert_eq!(apply_pending(&exe), Ok(Applied::None));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn damaged_or_unmatched_staging_is_discarded() {
        let d = dir("bad");
        let exe = d.join("L.exe");
        std::fs::write(&exe, b"old").unwrap();
        // no sidecar
        std::fs::write(pending(&exe), b"half").unwrap();
        assert_eq!(apply_pending(&exe), Ok(Applied::Discarded));
        // wrong hash
        std::fs::write(pending(&exe), b"other").unwrap();
        std::fs::write(pending_sha(&exe), format!("{}\n", sha256_hex(b"expected"))).unwrap();
        assert_eq!(apply_pending(&exe), Ok(Applied::Discarded));
        assert_eq!(std::fs::read(&exe).unwrap(), b"old");
        assert!(!pending(&exe).exists() && !pending_sha(&exe).exists());
        let _ = std::fs::remove_dir_all(&d);
    }
}
