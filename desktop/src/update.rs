//! Auto-update. On start the app asks the GitHub releases of this repository for the newest release whose tag starts
//! with `admin-desktop-v`, downloads the asset and its signature (`.sig`), checks the Ed25519 signature with the key
//! compiled into the app (sign.rs: it covers the version, file name, size and SHA-256), and only then swaps the program
//! file (the running exe is renamed to `.old`, the new one takes its name; Windows allows that). Without a good
//! signature nothing is replaced. The owner publishes a version with the workflow .github/workflows/admin-desktop.yml
//! (manual), which signs it. Downloads use curl (built into Windows 10+).
use crate::sign;
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
    /// The signed envelope `cinders-admin.exe.sig` (sign.rs).
    pub sig_url: String,
}

/// The suffix of the signature asset.
pub const SIG_SUFFIX: &str = ".sig";

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
        let (Some(url), Some(sig_url)) = (url_of(ASSET), url_of(&format!("{ASSET}{SIG_SUFFIX}"))) else {
            continue;
        };
        let ver = version::parse(tag)?;
        if best.as_ref().is_none_or(|(b, _)| ver > *b) {
            best = Some((
                ver,
                Found {
                    tag: tag.to_string(),
                    url,
                    sig_url,
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

/// Downloads the program and its signature with `get` and returns the program bytes only when the signature holds
/// (sign::verify with the compiled-in key `key`). Nothing is written here.
pub fn fetch_verified(
    found: &Found,
    current: &str,
    key: Option<[u8; 32]>,
    get: &dyn Fn(&str) -> Result<Vec<u8>, String>,
) -> Result<Vec<u8>, String> {
    let key = key.ok_or_else(|| sign::Error::NoKey.to_string())?;
    let sig = get(&found.sig_url)?;
    let exe = get(&found.url)?;
    sign::verify(
        &sig,
        &exe,
        &sign::Expect {
            key: &key,
            asset: ASSET,
            tag: &found.tag,
            current,
        },
    )
    .map_err(|e| e.to_string())?;
    Ok(exe)
}

/// Downloads, verifies the signature and swaps the program file. Returns the path of the new program (the caller
/// restarts it). The file that is swapped in is the very byte string that was verified.
pub fn install(found: &Found, current: &str) -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let bytes = fetch_verified(found, current, sign::public_key(), &|u| curl(u, None))?;
    let new = exe.with_extension("new");
    std::fs::write(&new, &bytes).map_err(|e| e.to_string())?;
    if let Err(e) = swap(&exe, &new) {
        let _ = std::fs::remove_file(&new);
        return Err(e);
    }
    Ok(exe)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sign::tests::{envelope, pair};

    fn rel(tag: &str, draft: bool, with_sig: bool) -> String {
        let mut assets = format!(r#"{{"name":"{ASSET}","browser_download_url":"https://x/{tag}/{ASSET}"}}"#);
        if with_sig {
            assets += &format!(r#",{{"name":"{ASSET}.sig","browser_download_url":"https://x/{tag}/sig"}}"#);
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
        assert!(f.url.ends_with(ASSET) && f.sig_url.ends_with("/sig"));
        assert!(pick(&j, "0.10.0").is_none());
        assert!(pick("not json", "0.1.0").is_none());
    }

    #[test]
    fn a_release_without_a_signature_is_not_offered() {
        let j = format!("[{}]", rel("admin-desktop-v0.3.0", false, false));
        assert!(pick(&j, "0.1.0").is_none());
    }

    const EXE: &[u8] = b"MZ the new program";

    fn found() -> Found {
        Found {
            tag: "admin-desktop-v0.2.0".into(),
            url: "https://x/exe".into(),
            sig_url: "https://x/sig".into(),
        }
    }

    /// A fake network: the exe and the signature file as given.
    fn net<'a>(exe: &'a [u8], sig: &'a [u8]) -> impl Fn(&str) -> Result<Vec<u8>, String> + 'a {
        move |u| match u {
            "https://x/exe" => Ok(exe.to_vec()),
            "https://x/sig" => Ok(sig.to_vec()),
            _ => Err(format!("404 {u}")),
        }
    }

    #[test]
    fn good_signature_gives_the_bytes() {
        let kp = pair(3);
        let sig = envelope(&kp, "0.2.0", ASSET, EXE);
        let got = fetch_verified(&found(), "0.1.0", Some(*kp.pk), &net(EXE, &sig)).unwrap();
        assert_eq!(got, EXE);
    }

    #[test]
    fn bad_signature_is_refused() {
        let kp = pair(3);
        let evil = pair(4);
        // signed by a key that is not the compiled-in one
        let sig = envelope(&evil, "0.2.0", ASSET, EXE);
        let e = fetch_verified(&found(), "0.1.0", Some(*kp.pk), &net(EXE, &sig)).unwrap_err();
        assert!(e.contains("signature is wrong") && e.contains("refused"), "{e}");
        // garbage instead of a signature
        let e = fetch_verified(&found(), "0.1.0", Some(*kp.pk), &net(EXE, b"hello")).unwrap_err();
        assert!(e.contains("refused"), "{e}");
    }

    #[test]
    fn bad_hash_is_refused() {
        let kp = pair(3);
        let sig = envelope(&kp, "0.2.0", ASSET, EXE);
        let mut tampered = EXE.to_vec();
        tampered[0] ^= 0xff; // a swapped download under a good signature file
        let e = fetch_verified(&found(), "0.1.0", Some(*kp.pk), &net(&tampered, &sig)).unwrap_err();
        assert!(e.contains("checksum differs") && e.contains("refused"), "{e}");
    }

    #[test]
    fn no_compiled_in_key_refuses_everything() {
        let kp = pair(3);
        let sig = envelope(&kp, "0.2.0", ASSET, EXE);
        let e = fetch_verified(&found(), "0.1.0", None, &net(EXE, &sig)).unwrap_err();
        assert!(e.contains("no update signing key"), "{e}");
    }

    #[test]
    fn a_failed_download_is_an_error() {
        let kp = pair(3);
        let e = fetch_verified(&found(), "0.1.0", Some(*kp.pk), &|u| Err(format!("down {u}"))).unwrap_err();
        assert!(e.starts_with("down"), "{e}");
    }
}
