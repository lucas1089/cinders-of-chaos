//! `launcher.json` beside the launcher. The Windows package workflow writes it (client/tools/set_launcher_config.py);
//! it holds the same three facts as `Services.update` in the client's init.lua.
use crate::i18n::Error;
use serde_json::Value;
use std::path::{Path, PathBuf};

pub const FILE: &str = "launcher.json";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    /// URL of the signed manifest (`manifest.json`). HTTPS, or HTTP only to a loopback address (tests).
    pub manifest_url: String,
    /// Ed25519 public key, the same as `Services.update.publicKey`.
    pub public_key: [u8; 32],
    /// Update version of the package's own files (`Services.update.baseline`): a manifest below it is refused.
    pub baseline: u64,
    /// The game program, a plain file name in the install folder. The manifest's `native.game` wins when it is there.
    pub game: String,
    /// Extra arguments for the game.
    pub args: Vec<String>,
    /// The install folder: where `launcher.json` lives.
    pub dir: PathBuf,
}

pub fn decode_hex(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) || !s.is_ascii() {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

/// True for a plain file name: no folder, no drive, no dot segment.
pub fn is_plain_name(n: &str) -> bool {
    !n.is_empty()
        && n.len() <= 64
        && n.as_bytes()[0].is_ascii_alphanumeric()
        && n.bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'-'))
}

pub fn loopback_http(url: &str) -> bool {
    [
        "http://127.0.0.1:",
        "http://127.0.0.1/",
        "http://localhost:",
        "http://localhost/",
    ]
    .iter()
    .any(|p| url.starts_with(p))
}

pub fn parse(text: &str, dir: &Path) -> Result<Config, Error> {
    let bad = |d: &str| Error::Config(d.to_string());
    let v: Value = serde_json::from_str(text).map_err(|e| bad(&format!("not JSON: {e}")))?;
    let manifest_url = v
        .get("manifest")
        .and_then(Value::as_str)
        .ok_or_else(|| bad("manifest"))?
        .to_string();
    if !(manifest_url.starts_with("https://") || loopback_http(&manifest_url)) {
        return Err(bad("manifest must be an https:// URL"));
    }
    let key = v
        .get("public_key")
        .and_then(Value::as_str)
        .ok_or_else(|| bad("public_key"))?;
    let public_key: [u8; 32] = decode_hex(key)
        .and_then(|b| b.try_into().ok())
        .ok_or_else(|| bad("public_key must be 64 hex digits"))?;
    let baseline = match v.get("baseline") {
        None => 0,
        Some(b) => b.as_u64().ok_or_else(|| bad("baseline"))?,
    };
    let game = v.get("game").and_then(Value::as_str).unwrap_or("Chaos.exe").to_string();
    if !is_plain_name(&game) {
        return Err(bad("game must be a plain file name"));
    }
    let args = match v.get("args") {
        None => Vec::new(),
        Some(a) => a
            .as_array()
            .ok_or_else(|| bad("args"))?
            .iter()
            .map(|x| x.as_str().map(str::to_string).ok_or_else(|| bad("args")))
            .collect::<Result<_, _>>()?,
    };
    Ok(Config {
        manifest_url,
        public_key,
        baseline,
        game,
        args,
        dir: dir.to_path_buf(),
    })
}

pub fn load(dir: &Path) -> Result<Config, Error> {
    let text = std::fs::read_to_string(dir.join(FILE)).map_err(|e| Error::Config(format!("{FILE}: {e}")))?;
    parse(&text, dir)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &str = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a";

    fn ok(extra: &str) -> String {
        format!(r#"{{"manifest":"https://x.test/updates/live/manifest.json","public_key":"{KEY}"{extra}}}"#)
    }

    #[test]
    fn parses_and_defaults() {
        let c = parse(&ok(""), Path::new("/g")).unwrap();
        assert_eq!((c.baseline, c.game.as_str(), c.args.len()), (0, "Chaos.exe", 0));
        assert_eq!(c.public_key[0], 0xd7);
        let c = parse(
            &ok(r#","baseline":47,"game":"Game.exe","args":["-x"]"#),
            Path::new("/g"),
        )
        .unwrap();
        assert_eq!(
            (c.baseline, c.game.as_str(), c.args),
            (47, "Game.exe", vec!["-x".to_string()])
        );
    }

    #[test]
    fn refuses_bad_settings() {
        let d = Path::new("/g");
        assert!(parse("nope", d).is_err());
        assert!(parse(&ok("").replace("https://x.test", "http://x.test"), d).is_err());
        assert!(parse(&ok("").replace("https://x.test", "http://127.0.0.1:80"), d).is_ok());
        assert!(parse(&ok("").replace(KEY, "abcd"), d).is_err());
        assert!(parse(&ok("").replace(KEY, &"zz".repeat(32)), d).is_err());
        assert!(parse(&ok(r#","baseline":-1"#), d).is_err());
        assert!(parse(&ok(r#","game":"..\\x.exe""#), d).is_err());
        assert!(parse(&ok(r#","game":"sub/x.exe""#), d).is_err());
        assert!(parse(&ok(r#","args":[1]"#), d).is_err());
    }

    #[test]
    fn plain_names() {
        assert!(is_plain_name("libGLESv2.dll"));
        assert!(!is_plain_name(""));
        assert!(!is_plain_name(".hidden"));
        assert!(!is_plain_name("a b.dll"));
        assert!(!is_plain_name("a/b"));
        assert!(!is_plain_name("c:x"));
    }
}
