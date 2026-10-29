//! The signed manifest, as the launcher reads it. Same envelope and signature as the in-game updater
//! (`updater_core.lua` checkEnvelope): `{format, key, signature, payload}`, Ed25519 over the exact bytes of the
//! `payload` text. The launcher uses the payload's `native` section only; the rules for it are the same as
//! `check_native` in client/tools/make_update_manifest.py.
use crate::config::{self, decode_hex};
use crate::i18n::Error;
use cinders_selfupdate::hash::is_sha256_hex;
use serde_json::Value;

pub const FORMAT: &str = "chaos-update-1";
pub const PRODUCT: &str = "cinders-of-chaos";
pub const NATIVE_DIR: &str = "native/";
pub const MAX_FILES: usize = 64;
pub const MAX_FILE_SIZE: u64 = 2 * 1024 * 1024 * 1024;
const EXT: [&str; 3] = ["exe", "dll", "pack"];
const RESERVED: [&str; 4] = ["con", "prn", "aux", "nul"];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NativeFile {
    pub path: String,
    pub sha256: String,
    pub size: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Native {
    pub package: u64,
    pub game: String,
    pub launcher: Option<String>,
    pub files: Vec<NativeFile>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Manifest {
    pub version: u64,
    pub min_package: u64,
    pub native: Option<Native>,
}

/// The reason a name is not a native file name, or None. Plain name, .exe .dll .pack only, no device name.
pub fn check_native_name(n: &str) -> Option<&'static str> {
    if !config::is_plain_name(n) || n.ends_with('.') {
        return Some("bad file name");
    }
    let lower = n.to_ascii_lowercase();
    if RESERVED.contains(&lower.split('.').next().unwrap_or("")) || is_com_lpt(&lower) {
        return Some("device name");
    }
    let ext = lower.rsplit_once('.').map(|(_, e)| e).unwrap_or("");
    if !EXT.contains(&ext) {
        return Some("only .exe .dll .pack");
    }
    None
}

fn is_com_lpt(lower: &str) -> bool {
    let stem = lower.split('.').next().unwrap_or("");
    (stem.starts_with("com") || stem.starts_with("lpt")) && stem.len() == 4 && matches!(stem.as_bytes()[3], b'1'..=b'9')
}

fn bad<T>(d: impl Into<String>) -> Result<T, Error> {
    Err(Error::BadManifest(d.into()))
}

fn parse_native(n: &Value) -> Result<Native, Error> {
    let Some(obj) = n.as_object() else {
        return bad("native is not an object");
    };
    let Some(package) = obj.get("package").and_then(Value::as_u64) else {
        return bad("native: bad package");
    };
    if obj.get("files_url").and_then(Value::as_str) != Some(NATIVE_DIR) {
        return bad("native: bad files_url");
    }
    let Some(list) = obj.get("files").and_then(Value::as_array) else {
        return bad("native: bad file list");
    };
    if list.is_empty() || list.len() > MAX_FILES {
        return bad("native: bad file list");
    }
    let mut files: Vec<NativeFile> = Vec::new();
    for f in list {
        let path = f.get("path").and_then(Value::as_str).unwrap_or("");
        if let Some(why) = check_native_name(path) {
            return bad(format!("native: refused path {path:?}: {why}"));
        }
        if files.iter().any(|x| x.path.eq_ignore_ascii_case(path)) {
            return bad(format!("native: duplicate path {path}"));
        }
        let sha = f.get("sha256").and_then(Value::as_str).unwrap_or("");
        if !is_sha256_hex(sha) {
            return bad(format!("native: bad sha256 for {path}"));
        }
        let size = f.get("size").and_then(Value::as_u64);
        let Some(size) = size.filter(|s| *s <= MAX_FILE_SIZE) else {
            return bad(format!("native: bad size for {path}"));
        };
        files.push(NativeFile {
            path: path.to_string(),
            sha256: sha.to_string(),
            size,
        });
    }
    let find = |name: &str| files.iter().any(|f| f.path.eq_ignore_ascii_case(name));
    let game = obj.get("game").and_then(Value::as_str).unwrap_or("");
    if check_native_name(game).is_some() || !game.to_ascii_lowercase().ends_with(".exe") || !find(game) {
        return bad("native: game is not an .exe of the file list");
    }
    let launcher = match obj.get("launcher") {
        None => None,
        Some(l) => {
            let l = l.as_str().unwrap_or("");
            if check_native_name(l).is_some()
                || !l.to_ascii_lowercase().ends_with(".exe")
                || !find(l)
                || l.eq_ignore_ascii_case(game)
            {
                return bad("native: launcher is not another .exe of the file list");
            }
            Some(l.to_string())
        }
    };
    Ok(Native {
        package,
        game: game.to_string(),
        launcher,
        files,
    })
}

/// Checks the signature with `public_key` and the rules of the payload. Nothing is trusted before the signature.
pub fn parse_envelope(bytes: &[u8], public_key: &[u8; 32]) -> Result<Manifest, Error> {
    let env: Value = serde_json::from_slice(bytes).map_err(|_| Error::BadManifest("not JSON".into()))?;
    if env.get("format").and_then(Value::as_str) != Some(FORMAT) {
        return bad("unknown manifest format");
    }
    let payload = match env.get("payload").and_then(Value::as_str) {
        Some(p) if !p.is_empty() => p,
        _ => return bad("no payload"),
    };
    let sig: [u8; 64] = env
        .get("signature")
        .and_then(Value::as_str)
        .and_then(decode_hex)
        .and_then(|b| b.try_into().ok())
        .ok_or(Error::BadSignature)?;
    if let Some(k) = env.get("key").and_then(Value::as_str) {
        if decode_hex(k).as_deref() != Some(&public_key[..]) {
            return Err(Error::BadSignature);
        }
    }
    let pk = ed25519_compact::PublicKey::from_slice(public_key).map_err(|_| Error::BadSignature)?;
    pk.verify(
        payload.as_bytes(),
        &ed25519_compact::Signature::from_slice(&sig).map_err(|_| Error::BadSignature)?,
    )
    .map_err(|_| Error::BadSignature)?;

    let m: Value = serde_json::from_str(payload).map_err(|_| Error::BadManifest("payload is not JSON".into()))?;
    if m.get("format").and_then(Value::as_u64) != Some(1) {
        return bad("unknown payload format");
    }
    if m.get("product").and_then(Value::as_str) != Some(PRODUCT) {
        return bad("manifest of another product");
    }
    let Some(version) = m.get("version").and_then(Value::as_u64).filter(|v| *v >= 1) else {
        return bad("bad version");
    };
    let min_package = m.get("min_package").and_then(Value::as_u64).unwrap_or(0);
    let native = m.get("native").map(parse_native).transpose()?;
    Ok(Manifest {
        version,
        min_package,
        native,
    })
}

/// URL of a native file: `native/<sha[:2]>/<sha>` beside the manifest.
pub fn blob_url(manifest_url: &str, sha: &str) -> String {
    let base = manifest_url.split(['?', '#']).next().unwrap_or("");
    let dir = base.rsplit_once('/').map(|(d, _)| d).unwrap_or(base);
    format!("{dir}/{NATIVE_DIR}{}/{sha}", &sha[..2])
}

#[cfg(test)]
mod tests {
    use super::*;

    pub fn sign(seed: u8, payload: &str) -> (String, [u8; 32]) {
        let kp = ed25519_compact::KeyPair::from_seed(ed25519_compact::Seed::new([seed; 32]));
        let sig = kp.sk.sign(payload.as_bytes(), None);
        let env = serde_json::json!({
            "format": FORMAT, "key": hex(&kp.pk[..]), "signature": hex(&sig[..]), "payload": payload
        });
        (env.to_string(), *kp.pk)
    }

    fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    const SHA: &str = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";

    fn payload(native: &str) -> String {
        format!(r#"{{"format":1,"product":"cinders-of-chaos","version":5,"min_package":13,"files":[]{native}}}"#)
    }

    fn native(files: &str, extra: &str) -> String {
        format!(r#","native":{{"package":14,"game":"Chaos.exe","files_url":"native/","files":[{files}]{extra}}}"#)
    }

    fn file(path: &str) -> String {
        format!(r#"{{"path":"{path}","sha256":"{SHA}","size":3}}"#)
    }

    #[test]
    fn reads_a_good_manifest() {
        let p = payload(&native(&format!("{},{}", file("Chaos.exe"), file("x.dll")), ""));
        let (env, pk) = sign(1, &p);
        let m = parse_envelope(env.as_bytes(), &pk).unwrap();
        assert_eq!((m.version, m.min_package), (5, 13));
        let n = m.native.unwrap();
        assert_eq!(
            (n.package, n.game.as_str(), n.files.len(), n.launcher),
            (14, "Chaos.exe", 2, None)
        );
    }

    #[test]
    fn manifest_without_native_is_fine() {
        let (env, pk) = sign(1, &payload(""));
        assert_eq!(parse_envelope(env.as_bytes(), &pk).unwrap().native, None);
    }

    #[test]
    fn signature_rules() {
        let p = payload(&native(&file("Chaos.exe"), ""));
        let (env, pk) = sign(1, &p);
        let (_, other) = sign(2, &p);
        assert_eq!(parse_envelope(env.as_bytes(), &other), Err(Error::BadSignature));
        // a changed payload byte
        let tampered = env.replace("\\\"version\\\":5", "\\\"version\\\":6");
        assert_ne!(tampered, env);
        assert_eq!(parse_envelope(tampered.as_bytes(), &pk), Err(Error::BadSignature));
        // unsigned, short signature, wrong format
        let mut v: Value = serde_json::from_str(&env).unwrap();
        v["signature"] = Value::String("00".repeat(10));
        assert_eq!(parse_envelope(v.to_string().as_bytes(), &pk), Err(Error::BadSignature));
        v.as_object_mut().unwrap().remove("signature");
        assert_eq!(parse_envelope(v.to_string().as_bytes(), &pk), Err(Error::BadSignature));
        assert!(matches!(parse_envelope(b"{}", &pk), Err(Error::BadManifest(_))));
        assert!(matches!(parse_envelope(b"junk", &pk), Err(Error::BadManifest(_))));
    }

    #[test]
    fn payload_and_native_rules() {
        let cases = [
            native(&file("run.bat"), ""),
            native(&file("sub/Chaos.exe"), ""),
            native(&file("..\\Chaos.exe"), ""),
            native(&file("con.exe"), ""),
            native(&file("com1.dll"), ""),
            native(&file("Chaos.exe").replace(SHA, &SHA.to_uppercase()), ""),
            native(&file("Chaos.exe").replace("\"size\":3", "\"size\":-1"), ""),
            native(&file("Chaos.exe").replace("\"size\":3", "\"size\":3000000000"), ""),
            native(&format!("{},{}", file("Chaos.exe"), file("chaos.EXE")), ""),
            native("", ""),
            native(&file("x.dll"), ""),
            native(&file("Chaos.exe"), r#","launcher":"Chaos.exe""#),
            native(&file("Chaos.exe"), r#","launcher":"Missing.exe""#),
            native(&file("Chaos.exe"), "").replace("native/", "files/"),
            native(&file("Chaos.exe"), "").replace("\"package\":14", "\"package\":-2"),
        ];
        for c in cases {
            let (env, pk) = sign(1, &payload(&c));
            assert!(
                matches!(parse_envelope(env.as_bytes(), &pk), Err(Error::BadManifest(_))),
                "{c}"
            );
        }
        let (env, pk) = sign(1, &payload("").replace("cinders-of-chaos", "other"));
        assert!(matches!(
            parse_envelope(env.as_bytes(), &pk),
            Err(Error::BadManifest(_))
        ));
        let (env, pk) = sign(1, &payload("").replace("\"version\":5", "\"version\":0"));
        assert!(matches!(
            parse_envelope(env.as_bytes(), &pk),
            Err(Error::BadManifest(_))
        ));
        let ok = payload(&native(
            &format!("{},{}", file("Chaos.exe"), file("CindersLauncher.exe")),
            r#","launcher":"CindersLauncher.exe""#,
        ));
        let (env, pk) = sign(1, &ok);
        let m = parse_envelope(env.as_bytes(), &pk).unwrap();
        assert_eq!(m.native.unwrap().launcher.as_deref(), Some("CindersLauncher.exe"));
    }

    #[test]
    fn blob_urls() {
        assert_eq!(
            blob_url("https://x.test/updates/live/manifest.json?t=1", SHA),
            format!("https://x.test/updates/live/native/ba/{SHA}")
        );
        assert_eq!(
            blob_url("http://127.0.0.1:80/manifest.json", SHA),
            format!("http://127.0.0.1:80/native/ba/{SHA}")
        );
    }
}
