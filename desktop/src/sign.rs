//! Signed releases (O312). The self-update replaces the running program, so it trusts nothing but an Ed25519
//! signature made with a key the owner keeps. Same scheme as the game updater and the launcher (client/MANIFEST.md
//! "Signed updater"): an envelope `{format, key, signature, payload}`, where `payload` is a JSON text and the signature
//! covers its exact bytes. The public key is compiled in (`desktop/update_public_key.hex`), never read from settings, a
//! release or the network. The payload names the program, the version, the file name, its SHA-256 and its size, so a
//! signature is good for one file of one version: an old signed release cannot be offered as a newer one, and a
//! swapped file fails the hash.
//!
//! Made by `desktop/tools/sign_release.py` in the release workflow (.github/workflows/admin-desktop.yml).
use crate::version;
use cinders_selfupdate::hash::{is_sha256_hex, sha256_hex};
use serde_json::Value;

/// The envelope `format` field.
pub const FORMAT: &str = "cinders-admin-release-1";
/// The payload `product` field.
pub const PRODUCT: &str = "cinders-admin";
/// The key that signs releases, 64 hex digits (an Ed25519 public key). Empty or zeros: no key set yet.
pub const PUBLIC_KEY_HEX: &str = include_str!("../update_public_key.hex");
/// A signature file is small; refuse anything bigger before parsing.
pub const MAX_SIG_BYTES: usize = 16 * 1024;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// No public key is compiled into this build: updates are refused.
    NoKey,
    /// The signature file is not an envelope of ours, or its payload breaks a rule.
    BadFile(String),
    /// The signature does not match the payload and the compiled-in key.
    BadSignature,
    /// The signature is good but the file or version it names is not what was downloaded.
    Mismatch(String),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::NoKey => write!(
                f,
                "this build has no update signing key (desktop/update_public_key.hex); update refused"
            ),
            Error::BadFile(s) => write!(f, "bad signature file: {s}; update refused"),
            Error::BadSignature => write!(f, "the signature is wrong; update refused"),
            Error::Mismatch(s) => write!(f, "{s}; update refused"),
        }
    }
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

/// The compiled-in key, or None while the file holds no real key (empty, not 64 hex digits, or all zeros).
pub fn public_key() -> Option<[u8; 32]> {
    parse_key(PUBLIC_KEY_HEX)
}

pub fn parse_key(text: &str) -> Option<[u8; 32]> {
    let k: [u8; 32] = decode_hex(text.trim())?.try_into().ok()?;
    (k != [0u8; 32]).then_some(k)
}

/// What a good signature vouches for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Release {
    pub version: String,
    pub asset: String,
    pub sha256: String,
    pub size: u64,
}

/// What the caller expects. `tag` is the release tag, `current` the running version.
pub struct Expect<'a> {
    pub key: &'a [u8; 32],
    pub asset: &'a str,
    pub tag: &'a str,
    pub current: &'a str,
}

/// Checks the signature file `envelope` against the downloaded program bytes `exe`. Nothing is trusted before the
/// signature; after it, the product, file name, version (the tag's, and newer than the running one), size and SHA-256
/// must all match.
pub fn verify(envelope: &[u8], exe: &[u8], want: &Expect) -> Result<Release, Error> {
    if envelope.len() > MAX_SIG_BYTES {
        return Err(Error::BadFile("too big".into()));
    }
    let env: Value = serde_json::from_slice(envelope).map_err(|_| Error::BadFile("not JSON".into()))?;
    if env.get("format").and_then(Value::as_str) != Some(FORMAT) {
        return Err(Error::BadFile("unknown format".into()));
    }
    let payload = match env.get("payload").and_then(Value::as_str) {
        Some(p) if !p.is_empty() => p,
        _ => return Err(Error::BadFile("no payload".into())),
    };
    let sig: [u8; 64] = env
        .get("signature")
        .and_then(Value::as_str)
        .and_then(decode_hex)
        .and_then(|b| b.try_into().ok())
        .ok_or(Error::BadSignature)?;
    if let Some(k) = env.get("key").and_then(Value::as_str) {
        if decode_hex(k).as_deref() != Some(&want.key[..]) {
            return Err(Error::BadSignature);
        }
    }
    let pk = ed25519_compact::PublicKey::from_slice(want.key).map_err(|_| Error::BadSignature)?;
    let sig = ed25519_compact::Signature::from_slice(&sig).map_err(|_| Error::BadSignature)?;
    pk.verify(payload.as_bytes(), &sig).map_err(|_| Error::BadSignature)?;

    let p: Value = serde_json::from_str(payload).map_err(|_| Error::BadFile("payload is not JSON".into()))?;
    let text = |k: &str| p.get(k).and_then(Value::as_str).unwrap_or("").to_string();
    if p.get("format").and_then(Value::as_u64) != Some(1) {
        return Err(Error::BadFile("unknown payload format".into()));
    }
    if text("product") != PRODUCT {
        return Err(Error::Mismatch("the signature is for another product".into()));
    }
    let rel = Release {
        version: text("version"),
        asset: text("asset"),
        sha256: text("sha256"),
        size: p.get("size").and_then(Value::as_u64).unwrap_or(u64::MAX),
    };
    if rel.asset != want.asset {
        return Err(Error::Mismatch(format!(
            "the signature is for {} not {}",
            rel.asset, want.asset
        )));
    }
    if version::parse(&rel.version).is_none() || version::parse(want.tag) != version::parse(&rel.version) {
        return Err(Error::Mismatch(format!(
            "the signed version {} is not the release {}",
            rel.version, want.tag
        )));
    }
    if !version::is_newer(&rel.version, want.current) {
        return Err(Error::Mismatch(format!(
            "the signed version {} is not newer than {}",
            rel.version, want.current
        )));
    }
    if !is_sha256_hex(&rel.sha256) {
        return Err(Error::BadFile("bad sha256".into()));
    }
    if rel.size != exe.len() as u64 {
        return Err(Error::Mismatch(format!(
            "size {} differs from the signed {}",
            exe.len(),
            rel.size
        )));
    }
    let got = sha256_hex(exe);
    if got != rel.sha256 {
        return Err(Error::Mismatch(format!("checksum differs (got {got})")));
    }
    Ok(rel)
}

#[cfg(test)]
pub mod tests {
    use super::*;
    use ed25519_compact::{KeyPair, Seed};

    pub fn pair(seed: u8) -> KeyPair {
        KeyPair::from_seed(Seed::new([seed; 32]))
    }

    pub fn hex(b: &[u8]) -> String {
        b.iter().map(|x| format!("{x:02x}")).collect()
    }

    /// A signed envelope for `exe` the way sign_release.py makes it.
    pub fn envelope(kp: &KeyPair, version: &str, asset: &str, exe: &[u8]) -> Vec<u8> {
        let payload = format!(
            r#"{{"format":1,"product":"{PRODUCT}","version":"{version}","asset":"{asset}","sha256":"{}","size":{}}}"#,
            sha256_hex(exe),
            exe.len()
        );
        let sig = kp.sk.sign(payload.as_bytes(), None);
        serde_json::json!({
            "format": FORMAT,
            "key": hex(&kp.pk[..]),
            "signature": hex(&sig[..]),
            "payload": payload,
        })
        .to_string()
        .into_bytes()
    }

    const EXE: &[u8] = b"MZ pretend program bytes";

    fn want<'a>(key: &'a [u8; 32]) -> Expect<'a> {
        Expect {
            key,
            asset: "cinders-admin.exe",
            tag: "admin-desktop-v0.2.0",
            current: "0.1.0",
        }
    }

    fn key_of(kp: &KeyPair) -> [u8; 32] {
        *kp.pk
    }

    #[test]
    fn good_release_passes() {
        let kp = pair(7);
        let k = key_of(&kp);
        let env = envelope(&kp, "0.2.0", "cinders-admin.exe", EXE);
        let r = verify(&env, EXE, &want(&k)).unwrap();
        assert_eq!(r.version, "0.2.0");
        assert_eq!(r.size, EXE.len() as u64);
    }

    #[test]
    fn bad_hash_is_refused() {
        let kp = pair(7);
        let k = key_of(&kp);
        let env = envelope(&kp, "0.2.0", "cinders-admin.exe", EXE);
        let mut other = EXE.to_vec();
        other[3] ^= 1; // same size, one bit changed
        match verify(&env, &other, &want(&k)) {
            Err(Error::Mismatch(m)) => assert!(m.contains("checksum differs"), "{m}"),
            x => panic!("{x:?}"),
        }
        // a longer or shorter file fails on size before the hash
        match verify(&env, b"short", &want(&k)) {
            Err(Error::Mismatch(m)) => assert!(m.contains("size"), "{m}"),
            x => panic!("{x:?}"),
        }
    }

    #[test]
    fn bad_signature_is_refused() {
        let kp = pair(7);
        let k = key_of(&kp);
        // signed by another key, with the right key named in the envelope
        let evil = pair(9);
        let mut env: Value = serde_json::from_slice(&envelope(&evil, "0.2.0", "cinders-admin.exe", EXE)).unwrap();
        env["key"] = Value::String(hex(&kp.pk[..]));
        assert_eq!(
            verify(env.to_string().as_bytes(), EXE, &want(&k)),
            Err(Error::BadSignature)
        );
        // the envelope names another key: refused before the signature is tried
        let own = envelope(&evil, "0.2.0", "cinders-admin.exe", EXE);
        assert_eq!(verify(&own, EXE, &want(&k)), Err(Error::BadSignature));
        // payload changed after signing (a different hash): the signature no longer matches
        let mut env: Value = serde_json::from_slice(&envelope(&kp, "0.2.0", "cinders-admin.exe", EXE)).unwrap();
        let p = env["payload"].as_str().unwrap().replace("0.2.0", "0.9.0");
        env["payload"] = Value::String(p);
        assert_eq!(
            verify(env.to_string().as_bytes(), EXE, &want(&k)),
            Err(Error::BadSignature)
        );
        // a signature of 63 bytes, a non hex one, and none
        for bad in [
            Value::String("ab".repeat(63)),
            Value::String("zz".repeat(64)),
            Value::Null,
        ] {
            let mut env: Value = serde_json::from_slice(&envelope(&kp, "0.2.0", "cinders-admin.exe", EXE)).unwrap();
            env["signature"] = bad;
            assert_eq!(
                verify(env.to_string().as_bytes(), EXE, &want(&k)),
                Err(Error::BadSignature)
            );
        }
    }

    #[test]
    fn envelope_rules() {
        let kp = pair(7);
        let k = key_of(&kp);
        assert!(matches!(verify(b"not json", EXE, &want(&k)), Err(Error::BadFile(_))));
        assert!(matches!(verify(b"{}", EXE, &want(&k)), Err(Error::BadFile(_))));
        let big = vec![b' '; MAX_SIG_BYTES + 1];
        assert!(matches!(verify(&big, EXE, &want(&k)), Err(Error::BadFile(_))));
        let mut env: Value = serde_json::from_slice(&envelope(&kp, "0.2.0", "cinders-admin.exe", EXE)).unwrap();
        env["format"] = Value::String("chaos-update-1".into());
        assert!(matches!(
            verify(env.to_string().as_bytes(), EXE, &want(&k)),
            Err(Error::BadFile(_))
        ));
    }

    #[test]
    fn signed_payload_must_match_the_download() {
        let kp = pair(7);
        let k = key_of(&kp);
        // another file name (the Linux build signed, the exe asked for)
        let env = envelope(&kp, "0.2.0", "cinders-admin-linux", EXE);
        assert!(matches!(verify(&env, EXE, &want(&k)), Err(Error::Mismatch(_))));
        // a signed version that is not the release tag (a replayed signature under a new tag)
        let env = envelope(&kp, "0.1.5", "cinders-admin.exe", EXE);
        assert!(matches!(verify(&env, EXE, &want(&k)), Err(Error::Mismatch(_))));
        // an old release, tag and signature agree, but it is not newer than the running app (downgrade)
        let env = envelope(&kp, "0.1.0", "cinders-admin.exe", EXE);
        let mut w = want(&k);
        w.tag = "admin-desktop-v0.1.0";
        assert!(matches!(verify(&env, EXE, &w), Err(Error::Mismatch(_))));
        // another product
        let payload = format!(
            r#"{{"format":1,"product":"cinders-of-chaos","version":"0.2.0","asset":"cinders-admin.exe","sha256":"{}","size":{}}}"#,
            sha256_hex(EXE),
            EXE.len()
        );
        let sig = kp.sk.sign(payload.as_bytes(), None);
        let env = serde_json::json!({"format": FORMAT, "signature": hex(&sig[..]), "payload": payload})
            .to_string()
            .into_bytes();
        assert!(matches!(verify(&env, EXE, &want(&k)), Err(Error::Mismatch(_))));
    }

    /// Made by desktop/tools/sign_release.py (seed 0x42 x 32, the bytes below, version 0.2.0); the Python test checks
    /// that the signer still makes exactly this file.
    #[test]
    fn the_python_signer_and_this_verifier_agree() {
        const VECTOR: &str = include_str!("../testdata/sign_vector.json");
        let key = parse_key("2152f8d19b791d24453242e15f2eab6cb7cffa7b6a5ed30097960e069881db12").unwrap();
        let exe = b"cinders-admin test program\n";
        let r = verify(VECTOR.as_bytes(), exe, &want(&key)).unwrap();
        assert_eq!((r.version.as_str(), r.size), ("0.2.0", 27));
        // one changed byte of the file, one of the key
        let mut bad = exe.to_vec();
        bad[0] ^= 1;
        assert!(matches!(
            verify(VECTOR.as_bytes(), &bad, &want(&key)),
            Err(Error::Mismatch(_))
        ));
        let mut other = key;
        other[0] ^= 1;
        assert_eq!(verify(VECTOR.as_bytes(), exe, &want(&other)), Err(Error::BadSignature));
    }

    #[test]
    fn key_file_rules() {
        assert_eq!(parse_key(""), None);
        assert_eq!(parse_key(&"0".repeat(64)), None);
        assert_eq!(parse_key("abcd"), None);
        assert_eq!(parse_key(&"zz".repeat(32)), None);
        assert_eq!(parse_key(&format!("{}\n", "ab".repeat(32))), Some([0xab; 32]));
        // the shipped file is either empty/zero (updates refused) or a real key; never a half key
        let shipped = PUBLIC_KEY_HEX.trim();
        assert!(
            shipped.is_empty() || shipped.len() == 64,
            "update_public_key.hex must hold 64 hex digits"
        );
    }
}
