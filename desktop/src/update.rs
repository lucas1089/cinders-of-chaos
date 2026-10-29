//! Auto-update. On start the app asks the GitHub releases of this repository for the newest release whose tag starts
//! with `admin-desktop-v`, downloads the asset, checks its SHA-256 against the `.sha256` asset, and swaps the program
//! file (the running exe is renamed to `.old`, the new one takes its name; Windows allows that). The owner publishes a
//! version with the workflow .github/workflows/admin-desktop.yml (manual). Downloads use curl (built into Windows 10+).
use crate::version;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::path::{Path, PathBuf};
use std::process::Command;

pub const RELEASES_URL: &str = "https://api.github.com/repos/lucas1089/cinders-of-chaos/releases?per_page=30";
pub const TAG_PREFIX: &str = "admin-desktop-v";
pub const ASSET: &str = if cfg!(windows) {
    "cinders-admin.exe"
} else {
    "cinders-admin-linux"
};

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Found {
    pub tag: String,
    pub url: String,
    pub sha_url: String,
}

/// Picks the newest (by version number) non-draft release of ours that is newer than `current`.
pub fn pick(releases_json: &str, current: &str) -> Option<Found> {
    let v: Value = serde_json::from_str(releases_json).ok()?;
    let mut best: Option<(Vec<u64>, Found)> = None;
    for r in v.as_array()? {
        let tag = r.get("tag_name").and_then(Value::as_str).unwrap_or("");
        if !tag.starts_with(TAG_PREFIX) || r.get("draft").and_then(Value::as_bool).unwrap_or(false) {
            continue;
        }
        if !version::is_newer(tag, current) {
            continue;
        }
        let assets = r.get("assets").and_then(Value::as_array)?;
        let url_of = |name: &str| {
            assets.iter().find_map(|a| {
                (a.get("name").and_then(Value::as_str) == Some(name))
                    .then(|| {
                        a.get("browser_download_url")
                            .and_then(Value::as_str)
                            .map(str::to_string)
                    })
                    .flatten()
            })
        };
        let (Some(url), Some(sha_url)) = (url_of(ASSET), url_of(&format!("{ASSET}.sha256"))) else {
            continue;
        };
        let ver = version::parse(tag)?;
        if best.as_ref().is_none_or(|(b, _)| ver > *b) {
            best = Some((
                ver,
                Found {
                    tag: tag.to_string(),
                    url,
                    sha_url,
                },
            ));
        }
    }
    best.map(|(_, f)| f)
}

/// First 64 hex digits of a `.sha256` file ("HEX  name" or just "HEX"), lower case.
pub fn parse_sha(text: &str) -> Option<String> {
    let w = text.split_whitespace().next()?.to_ascii_lowercase();
    (w.len() == 64 && w.chars().all(|c| c.is_ascii_hexdigit())).then_some(w)
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes).iter().map(|b| format!("{b:02x}")).collect()
}

fn curl(url: &str, out: Option<&Path>) -> Result<Vec<u8>, String> {
    let mut c = Command::new("curl");
    c.args([
        "-fsSL",
        "--max-time",
        "180",
        "-H",
        "User-Agent: cinders-admin",
        "-H",
        "Accept: application/vnd.github+json",
    ]);
    match out {
        Some(p) => c.arg("-o").arg(p).arg(url),
        None => c.arg(url),
    };
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x0800_0000);
    }
    let o = c.output().map_err(|e| format!("cannot start curl: {e}"))?;
    if o.status.success() {
        Ok(o.stdout)
    } else {
        Err(format!(
            "download failed ({}): {}",
            o.status,
            String::from_utf8_lossy(&o.stderr).trim()
        ))
    }
}

/// Asks GitHub whether a newer version exists.
pub fn check(current: &str) -> Result<Option<Found>, String> {
    let body = curl(RELEASES_URL, None)?;
    Ok(pick(&String::from_utf8_lossy(&body), current))
}

/// Downloads, verifies and swaps the program file. Returns the path of the new program (the caller restarts it).
pub fn install(found: &Found) -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let new = exe.with_extension("new");
    curl(&found.url, Some(&new))?;
    let want = parse_sha(&String::from_utf8_lossy(&curl(&found.sha_url, None)?)).ok_or("bad .sha256 file")?;
    let got = sha256_hex(&std::fs::read(&new).map_err(|e| e.to_string())?);
    if got != want {
        let _ = std::fs::remove_file(&new);
        return Err(format!("checksum differs (got {got}); update refused"));
    }
    swap(&exe, &new)?;
    Ok(exe)
}

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

    fn rel(tag: &str, draft: bool, with_sha: bool) -> String {
        let mut assets = format!(r#"{{"name":"{ASSET}","browser_download_url":"https://x/{tag}/{ASSET}"}}"#);
        if with_sha {
            assets += &format!(r#",{{"name":"{ASSET}.sha256","browser_download_url":"https://x/{tag}/sha"}}"#);
        }
        format!(r#"{{"tag_name":"{tag}","draft":{draft},"assets":[{assets}]}}"#)
    }

    #[test]
    fn picks_newest_of_ours() {
        let j = format!(
            "[{},{},{},{},{}]",
            rel("winpkg-900", false, true),
            rel("admin-desktop-v0.2.0", false, true),
            rel("admin-desktop-v0.10.0", false, true),
            rel("admin-desktop-v0.11.0", true, true),
            rel("admin-desktop-v0.12.0", false, false)
        );
        let f = pick(&j, "0.1.0").unwrap();
        assert_eq!(f.tag, "admin-desktop-v0.10.0");
        assert!(f.url.ends_with(ASSET) && f.sha_url.ends_with("/sha"));
        assert!(pick(&j, "0.10.0").is_none());
        assert!(pick("not json", "0.1.0").is_none());
    }

    #[test]
    fn sha_parse_and_hash() {
        let h = sha256_hex(b"abc");
        assert_eq!(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(
            parse_sha(&format!("{}  cinders-admin.exe\n", h.to_uppercase())),
            Some(h)
        );
        assert_eq!(parse_sha("short"), None);
    }

    #[test]
    fn swap_replaces_and_keeps_old() {
        let d = std::env::temp_dir().join(format!("cinders-admin-swap-{}", std::process::id()));
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
