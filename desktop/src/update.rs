//! Auto-update. The GitHub repository is private (O530), so this app has no access to its releases and holds no token.
//! It asks the VPS, over the same ssh channel as every other command: `chaos-ctl.sh admin-desktop-releases` lists the
//! releases whose tag starts with `admin-desktop-v` (JSON: tag, draft, asset names), and `admin-desktop-asset-url TAG
//! NAME` gives a short-lived signed address for one asset, which this app downloads with curl (built into Windows 10+).
//! The token stays on the VPS. The signature check is still the gate: the program and its signature (`.sig`) are
//! checked with the Ed25519 key compiled into the app (sign.rs: it covers the version, file name, size and SHA-256),
//! and only then the program file is swapped (the running exe is renamed to `.old`, the new one takes its name; Windows
//! allows that). Without a good signature nothing is replaced. The owner publishes a version with the workflow
//! .github/workflows/admin-desktop.yml (manual), which signs it.
use crate::config::Config;
use crate::sign;
use crate::ssh;
use crate::version;
pub use cinders_selfupdate::hash::{parse_sha, sha256_hex};
pub use cinders_selfupdate::swap::swap;
use serde_json::Value;
use std::path::{Path, PathBuf};
use std::process::Command;

pub const TAG_PREFIX: &str = "admin-desktop-v";
pub const ASSET: &str = if cfg!(windows) {
    "cinders-admin.exe"
} else {
    "cinders-admin-linux"
};

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Found {
    pub tag: String,
    /// The name of the program asset of the release.
    pub asset: String,
    /// The name of the signed envelope `cinders-admin.exe.sig` (sign.rs).
    pub sig_asset: String,
}

/// The suffix of the signature asset.
pub const SIG_SUFFIX: &str = ".sig";

/// Picks the newest (by version number) non-draft release of ours that is newer than `current`.
pub fn pick(releases_json: &str, current: &str) -> Option<Found> {
    let v = first_json(releases_json)?;
    let mut best: Option<(Vec<u64>, Found)> = None;
    for r in v.as_array()? {
        let tag = r.get("tag_name").and_then(Value::as_str).unwrap_or("");
        if !tag.starts_with(TAG_PREFIX) || r.get("draft").and_then(Value::as_bool).unwrap_or(false) {
            continue;
        }
        if !version::is_newer(tag, current) {
            continue;
        }
        let Some(assets) = r.get("assets").and_then(Value::as_array) else {
            continue;
        };
        let has = |name: &str| {
            assets
                .iter()
                .any(|a| a.get("name").and_then(Value::as_str) == Some(name))
        };
        let sig = format!("{ASSET}{SIG_SUFFIX}");
        if !has(ASSET) || !has(&sig) {
            continue;
        }
        let ver = version::parse(tag)?;
        if best.as_ref().is_none_or(|(b, _)| ver > *b) {
            best = Some((
                ver,
                Found {
                    tag: tag.to_string(),
                    asset: ASSET.to_string(),
                    sig_asset: sig,
                },
            ));
        }
    }
    best.map(|(_, f)| f)
}

/// The first JSON value in `text`, from its first `[` or `{`. The ssh program may print a warning (a new host key)
/// before or after the answer, so the whole text is not one JSON document.
pub fn first_json(text: &str) -> Option<Value> {
    let start = text.find(['[', '{'])?;
    serde_json::Deserializer::from_str(&text[start..])
        .into_iter::<Value>()
        .next()?
        .ok()
}

/// What the owner reads when a chaos-ctl.sh command of the update answers with an error: the word at the start of the
/// message (`chaos-ctl: WORD: sentence`) in Portuguese. Unknown text is kept, its first line.
pub fn friendly(text: &str) -> String {
    let t = text.trim();
    let has = |w: &str| t.contains(w);
    if has("private-repo") {
        return "Repositório privado: defina o token do GitHub (Atualizações > Repositório privado > Definir token do GitHub)."
            .into();
    }
    if has("token-refused") {
        return "O GitHub recusou o token (401). Ele pode ter vencido: defina um novo em Atualizações > Repositório privado."
            .into();
    }
    if has("no-access") {
        return "O token do GitHub não alcança este repositório (precisa de Contents leitura). Defina um novo em Atualizações > Repositório privado."
            .into();
    }
    if has("no-asset") || has("no-release") {
        return "A release não tem o arquivo do app (o workflow admin-desktop já publicou esta versão?).".into();
    }
    if has("github-unreachable") {
        return "O GitHub não respondeu à VPS. Tente de novo em alguns minutos.".into();
    }
    if has("unknown command") {
        return "A VPS ainda não tem este comando: atualize o servidor (Atualizações > Atualizar servidor).".into();
    }
    if has("Not configured") {
        return "Falta configurar o servidor (host, usuário e chave em Configurações).".into();
    }
    let line = t.lines().next().unwrap_or("").trim();
    format!("a VPS respondeu: {}", if line.is_empty() { "sem texto" } else { line })
}

/// Runs one chaos-ctl.sh command on the VPS and gives its output, or the friendly error.
fn ctl(cfg: &Config, args: &str, timeout_sec: u64) -> Result<String, String> {
    let o = ssh::exec(cfg, &ssh::ctl_line(cfg, args), timeout_sec, None);
    if o.code == 0 {
        Ok(o.text)
    } else {
        Err(friendly(&o.text))
    }
}

/// Downloads one address with curl. The address is the signed one of the VPS: no token goes with it.
fn curl(url: &str) -> Result<Vec<u8>, String> {
    let mut c = Command::new("curl");
    c.args([
        "-fsSL",
        "--max-time",
        "180",
        "--proto",
        "=https",
        "--proto-redir",
        "=https",
        "-H",
        "User-Agent: cinders-admin",
        "-H",
        "Accept: application/octet-stream",
        url,
    ]);
    c.stdin(std::process::Stdio::null());
    ssh::hide_console(&mut c);
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

/// The signed address from the answer of `admin-desktop-asset-url` (one `https://` line, no white space or quote).
pub fn parse_url(answer: &str) -> Result<String, String> {
    answer
        .lines()
        .map(str::trim)
        .find(|l| l.starts_with("https://"))
        .filter(|l| !l.contains(char::is_whitespace) && !l.contains('"') && !l.contains('\''))
        .map(str::to_string)
        .ok_or_else(|| "a VPS não deu o endereço do arquivo".to_string())
}

/// Asks the VPS (through `run`, which takes the chaos-ctl.sh arguments and gives its output) whether a newer version
/// exists.
pub fn check_with(run: &dyn Fn(&str) -> Result<String, String>, current: &str) -> Result<Option<Found>, String> {
    let body = run("admin-desktop-releases")?;
    if first_json(&body).is_none_or(|v| !v.is_array()) {
        return Err("a VPS não deu a lista de versões (ela precisa do chaos-ctl.sh novo)".into());
    }
    Ok(pick(&body, current))
}

/// Asks the VPS whether a newer version exists.
pub fn check(cfg: &Config, current: &str) -> Result<Option<Found>, String> {
    check_with(&|args| ctl(cfg, args, 60), current)
}

/// Downloads the program and its signature with `get` (which takes the asset name) and returns the program bytes only
/// when the signature holds (sign::verify with the compiled-in key `key`). Nothing is written here.
pub fn fetch_verified(
    found: &Found,
    current: &str,
    key: Option<[u8; 32]>,
    get: &dyn Fn(&str) -> Result<Vec<u8>, String>,
) -> Result<Vec<u8>, String> {
    let key = key.ok_or_else(|| sign::Error::NoKey.to_string())?;
    let sig = get(&found.sig_asset)?;
    let exe = get(&found.asset)?;
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
/// restarts it). The file that is swapped in is the very byte string that was verified. Each file is asked of the VPS
/// right before its download: the signed address lives a few minutes.
pub fn install(cfg: &Config, found: &Found, current: &str) -> Result<PathBuf, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let get = |name: &str| {
        let answer = ctl(cfg, &format!("admin-desktop-asset-url {} {}", found.tag, name), 60)?;
        curl(&parse_url(&answer)?)
    };
    let bytes = fetch_verified(found, current, sign::public_key(), &get)?;
    let new = exe.with_extension("new");
    std::fs::write(&new, &bytes).map_err(|e| e.to_string())?;
    if let Err(e) = swap(&exe, &new) {
        let _ = std::fs::remove_file(&new);
        return Err(e);
    }
    Ok(exe)
}

/// Starts the program at `exe` again after an update: no console, no inherited pipes (the app has none on Windows),
/// its own folder as the working folder. The caller exits right after.
pub fn restart(exe: &Path) -> std::io::Result<()> {
    let mut c = Command::new(exe);
    c.stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null());
    if let Some(dir) = exe.parent() {
        c.current_dir(dir);
    }
    ssh::hide_console(&mut c);
    c.spawn().map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::sign::tests::{envelope, pair};

    /// A release as `admin-desktop-releases` prints it: tag, draft, asset names and sizes, no addresses.
    fn rel(tag: &str, draft: bool, with_sig: bool) -> String {
        let mut assets = format!(r#"{{"name":"{ASSET}","size":100}}"#);
        if with_sig {
            assets += &format!(r#",{{"name":"{ASSET}.sig","size":90}}"#);
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
        assert_eq!(f.asset, ASSET);
        assert_eq!(f.sig_asset, format!("{ASSET}.sig"));
        assert!(pick(&j, "0.10.0").is_none());
        assert!(pick("not json", "0.1.0").is_none());
    }

    #[test]
    fn a_release_without_a_signature_is_not_offered() {
        let j = format!("[{}]", rel("admin-desktop-v0.3.0", false, false));
        assert!(pick(&j, "0.1.0").is_none());
    }

    #[test]
    fn ssh_noise_around_the_answer_is_ignored() {
        let j = format!(
            "Warning: Permanently added 'vps' (ED25519) to the list of known hosts.\n[{}]\nsome stderr after\n",
            rel("admin-desktop-v0.3.0", false, true)
        );
        assert_eq!(pick(&j, "0.1.0").unwrap().tag, "admin-desktop-v0.3.0");
        assert!(first_json("no json here").is_none());
        assert!(first_json("[1,2").is_none());
    }

    #[test]
    fn the_vps_gives_the_list_and_the_token_never_comes_here() {
        let list = format!("[{}]", rel("admin-desktop-v0.3.0", false, true));
        let seen = std::cell::RefCell::new(Vec::new());
        let run = |args: &str| {
            seen.borrow_mut().push(args.to_string());
            Ok(list.clone())
        };
        let f = check_with(&run, "0.1.0").unwrap().unwrap();
        assert_eq!(f.tag, "admin-desktop-v0.3.0");
        assert_eq!(*seen.borrow(), vec!["admin-desktop-releases".to_string()]);
        assert!(check_with(&run, "0.3.0").unwrap().is_none());
        // a VPS without the command, or an answer that is no list, is an error and not "up to date"
        let junk = |_: &str| Ok("{}".to_string());
        assert!(check_with(&junk, "0.1.0").unwrap_err().contains("chaos-ctl.sh novo"));
    }

    #[test]
    fn a_private_repository_without_a_token_says_what_to_do() {
        let run = |_: &str| {
            Err(friendly(
                "chaos-ctl: private-repo: GitHub says 404 and no GitHub token is saved: o/r is private.",
            ))
        };
        let e = check_with(&run, "0.1.0").unwrap_err();
        assert!(e.starts_with("Repositório privado: defina o token do GitHub"), "{e}");
        assert!(friendly("chaos-ctl: token-refused: GitHub refused the token (401)").contains("recusou o token"));
        assert!(friendly("chaos-ctl: no-access: GitHub says 404").contains("Contents"));
        assert!(friendly("chaos-ctl: no-asset: release x has no y").contains("release não tem"));
        assert!(friendly("chaos-ctl: github-unreachable: HTTP 502").contains("não respondeu"));
        assert!(
            friendly("chaos-ctl: unknown command: admin-desktop-releases (chaos-ctl.sh help)")
                .contains("ainda não tem")
        );
        assert!(friendly("Not configured: fill host").contains("Falta configurar"));
        assert_eq!(friendly("boom\nsecond"), "a VPS respondeu: boom");
        assert_eq!(friendly(""), "a VPS respondeu: sem texto");
    }

    #[test]
    fn only_a_plain_https_address_is_downloaded() {
        assert_eq!(
            parse_url("Warning: x\nhttps://objects.example.org/a/b?sig=1\n").unwrap(),
            "https://objects.example.org/a/b?sig=1"
        );
        assert!(parse_url("http://objects.example.org/a").is_err());
        assert!(parse_url("").is_err());
        assert!(parse_url("https://x/a b").is_err());
        assert!(parse_url("https://x/a\"b").is_err());
        assert!(parse_url("https://x/a'b").is_err());
    }

    const EXE: &[u8] = b"MZ the new program";

    fn found() -> Found {
        Found {
            tag: "admin-desktop-v0.2.0".into(),
            asset: ASSET.into(),
            sig_asset: format!("{ASSET}.sig"),
        }
    }

    /// A fake network: the exe and the signature file as given, asked by asset name.
    fn net<'a>(exe: &'a [u8], sig: &'a [u8]) -> impl Fn(&str) -> Result<Vec<u8>, String> + 'a {
        move |name| {
            if name == ASSET {
                Ok(exe.to_vec())
            } else if name == format!("{ASSET}.sig") {
                Ok(sig.to_vec())
            } else {
                Err(format!("404 {name}"))
            }
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
        let e = fetch_verified(&found(), "0.1.0", Some(*kp.pk), &|n| Err(format!("down {n}"))).unwrap_err();
        assert!(e.starts_with("down"), "{e}");
    }
}
