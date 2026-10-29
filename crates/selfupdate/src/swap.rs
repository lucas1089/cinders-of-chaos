//! Staged rename of a program file (the running exe is renamed to `.old`, the new one takes its name; Windows allows
//! renaming a running exe, not overwriting it).
use std::path::Path;

/// `exe` -> `exe.old`, `new` -> `exe`. Puts the old one back when the second rename fails.
pub fn swap(exe: &Path, new: &Path) -> Result<(), String> {
    let old = exe.with_extension("old");
    let _ = std::fs::remove_file(&old);
    std::fs::rename(exe, &old).map_err(|e| format!("cannot move the running program: {e}"))?;
    if let Err(e) = std::fs::rename(new, exe) {
        let _ = std::fs::rename(&old, exe);
        return Err(format!("cannot put the new program in place: {e}"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = std::fs::set_permissions(exe, std::fs::Permissions::from_mode(0o755));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn swap_replaces_and_keeps_old() {
        let d = std::env::temp_dir().join(format!("cinders-selfupdate-swap-{}", std::process::id()));
        std::fs::create_dir_all(&d).unwrap();
        let exe = d.join("app.exe");
        let new = d.join("app.new");
        std::fs::write(&exe, b"old").unwrap();
        std::fs::write(&new, b"new").unwrap();
        swap(&exe, &new).unwrap();
        assert_eq!(std::fs::read(&exe).unwrap(), b"new");
        assert_eq!(std::fs::read(d.join("app.old")).unwrap(), b"old");
        // missing new file: the old program is put back
        assert!(swap(&exe, &d.join("none")).is_err());
        assert_eq!(std::fs::read(&exe).unwrap(), b"new");
        let _ = std::fs::remove_dir_all(&d);
    }
}
