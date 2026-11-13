//! Build step of the launcher (O552): the facts built into the setup program and the ticket key.
//!
//! 1. `launcher/embedded.json` is the text of a `launcher.json` (manifest address, public key, feed, links), written by
//!    `client/tools/set_launcher_config.py --embed launcher/embedded.json` in the packaging workflow and never committed.
//!    It is copied to `OUT_DIR/embedded.json` and compiled in (`setup::EMBEDDED`). A build without the file embeds an
//!    empty text: such a launcher only runs beside a `launcher.json` and shows no setup screen.
//! 2. The key of the start ticket (`src/ticket.rs`). The game's key is the client guard secret `CHAOS_CLIENT_KEY` (64 hex
//!    digits, read from the environment, never from a file of the repository, never printed, never cached by cargo
//!    beyond `rerun-if-env-changed`). The launcher does not hold that key: it holds a sub key, HKDF-SHA256 of it with the
//!    label "cinders-launcher-ticket-v1", so a leak of the launcher cannot answer the login challenge of the game server.
//!    The sub key is written shuffled and XOR-masked into `OUT_DIR/ticket_key.rs` (obfuscation, not protection: whoever has
//!    the exe can recover it). Without the variable the public DEVELOPMENT key of the client's CMake is used, which is what a
//!    client built without the secret holds too, so a development launcher and a development client still agree.
use cinders_selfupdate::hash::{hkdf_sha256_32, hmac_sha256};
use std::path::PathBuf;

/// The bytes of "DEV-KEY-cinders-of-chaos-UNSAFE!", the same public development key as the client's CMakeLists.
const DEV_KEY: &[u8; 32] = b"DEV-KEY-cinders-of-chaos-UNSAFE!";

fn unhex(s: &str) -> Option<Vec<u8>> {
    if s.len() & 1 == 1 || !s.is_ascii() {
        return None;
    }
    (0..s.len() / 2)
        .map(|i| u8::from_str_radix(&s[2 * i..2 * i + 2], 16).ok())
        .collect()
}

fn main() {
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));

    // 1. the facts of the setup program
    let src = PathBuf::from("embedded.json");
    println!("cargo:rerun-if-changed=embedded.json");
    println!("cargo:rerun-if-changed=build.rs");
    let text = std::fs::read_to_string(&src).unwrap_or_default();
    std::fs::write(out.join("embedded.json"), text).expect("write embedded.json");

    // 2. the ticket key
    println!("cargo:rerun-if-env-changed=CHAOS_CLIENT_KEY");
    let given = std::env::var("CHAOS_CLIENT_KEY").unwrap_or_default();
    let given = given.trim().to_ascii_lowercase();
    let (key, dev): (Vec<u8>, bool) = if given.is_empty() {
        println!("cargo:warning=launcher: no CHAOS_CLIENT_KEY; its tickets only open a development client");
        (DEV_KEY.to_vec(), true)
    } else {
        match unhex(&given).filter(|k| k.len() == 32) {
            Some(k) => (k, false),
            None => panic!("CHAOS_CLIENT_KEY must be 64 hex digits (32 bytes)"),
        }
    };
    let sub = hkdf_sha256_32(&key, b"cinders-launcher-ticket-v1");
    let mask = hmac_sha256(b"cinders-ticket-mask-v1", &sub);
    let shift = (mask[0] % 32) as usize;
    let (mut x, mut p) = ([0u8; 32], [0u8; 32]);
    for i in 0..32 {
        let pos = (i * 13 + shift) % 32;
        p[i] = pos as u8;
        x[i] = sub[pos] ^ mask[i];
    }
    let arr = |a: &[u8; 32]| a.iter().map(|b| format!("{b}")).collect::<Vec<_>>().join(",");
    let code = format!(
        "pub const KEY_IS_DEV: bool = {dev};\nstatic X: [u8; 32] = [{}];\nstatic M: [u8; 32] = [{}];\nstatic P: [u8; 32] = [{}];\n\
         /// The sub key, put together from the shuffled and masked arrays.\npub fn embedded_sub_key() -> [u8; 32] {{\n    let mut k = [0u8; 32];\n    \
         for i in 0..32 {{\n        k[(P[i] & 31) as usize] = X[i] ^ M[i];\n    }}\n    k\n}}\n",
        arr(&x),
        arr(&mask),
        arr(&p)
    );
    std::fs::write(out.join("ticket_key.rs"), code).expect("write ticket_key.rs");
}
