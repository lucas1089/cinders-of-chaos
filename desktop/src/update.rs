//! Auto-update. On start the app asks the GitHub releases of this repository for the newest release whose tag starts
//! with `admin-desktop-v`, downloads the asset, checks its SHA-256 against the `.sha256` asset, and swaps the program
//! file (the running exe is renamed to `.old`, the new one takes its name; Windows allows that). The owner publishes a
//! version with the workflow .github/workflows/admin-desktop.yml (manual). Downloads use curl (built into Windows 10+).
use crate::version;
pub use cinders_selfupdate::hash::{parse_sha, sha256_hex};
pub use cinders_selfupdate::swap::swap;
use serde_json::Value;
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
}
