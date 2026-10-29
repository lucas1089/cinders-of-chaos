//! Cross-language check: a manifest signed by client/tools/make_update_manifest.py (fixed key, fixed time) is read and
//! verified by the launcher, so the two sides cannot drift apart. The file is rewritten by
//! `UPDATE_LAUNCHER_VECTOR=1 python3 -I client/tools/make_update_manifest_test.py`.
use cinders_launcher::config::decode_hex;
use cinders_launcher::i18n::Error;
use cinders_launcher::manifest::parse_envelope;

fn vector() -> (serde_json::Value, [u8; 32]) {
    let text =
        std::fs::read_to_string(concat!(env!("CARGO_MANIFEST_DIR"), "/tests/data/python_manifest.json")).unwrap();
    let v: serde_json::Value = serde_json::from_str(&text).unwrap();
    let pk = decode_hex(v["public_key"].as_str().unwrap())
        .unwrap()
        .try_into()
        .unwrap();
    (v["envelope"].clone(), pk)
}

#[test]
fn reads_what_the_python_tool_signed() {
    let (env, pk) = vector();
    let m = parse_envelope(env.to_string().as_bytes(), &pk).unwrap();
    assert_eq!((m.version, m.min_package), (7, 13));
    let n = m.native.unwrap();
    assert_eq!(
        (n.package, n.game.as_str(), n.launcher.as_deref()),
        (14, "Chaos.exe", Some("CindersLauncher.exe"))
    );
    assert_eq!(n.files.len(), 3);
    assert_eq!(n.files[1].path, "CindersLauncher.exe");
    assert_eq!(n.files[1].size, 8);
}

#[test]
fn the_python_signature_breaks_on_any_change() {
    let (env, pk) = vector();
    let text = env.to_string();
    assert_eq!(
        parse_envelope(text.replace("\\\"package\\\":14", "\\\"package\\\":15").as_bytes(), &pk),
        Err(Error::BadSignature)
    );
    let mut other = pk;
    other[0] ^= 1;
    assert!(parse_envelope(text.as_bytes(), &other).is_err());
}
