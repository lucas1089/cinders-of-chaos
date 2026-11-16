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
//! 3. The icon of the exe (Windows, MSVC): `assets/app.ico` (written by `tools/gen_launcher_art.py`) turned into a
//!    resource file `OUT_DIR/app.res` (one RT_ICON per frame, one RT_GROUP_ICON with id 1) and handed to link.exe. It is the
//!    icon of the setup program, the installed launcher and the shortcuts the setup makes (they point at the exe). No
//!    resource compiler is needed. Other targets (the Linux tests, the GNU type check) skip it.
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

fn le16(v: &mut Vec<u8>, x: u16) {
    v.extend_from_slice(&x.to_le_bytes());
}

fn le32(v: &mut Vec<u8>, x: u32) {
    v.extend_from_slice(&x.to_le_bytes());
}

/// One entry of a .res file: header (numeric type and name), the data, padded to 4 bytes.
fn res_entry(out: &mut Vec<u8>, kind: u16, id: u16, flags: u16, data: &[u8]) {
    le32(out, data.len() as u32);
    le32(out, 32);
    le16(out, 0xFFFF);
    le16(out, kind);
    le16(out, 0xFFFF);
    le16(out, id);
    le32(out, 0); // data version
    le16(out, flags);
    le16(out, 0x0409); // language: en-US, the neutral choice of the resource compilers
    le32(out, 0); // version
    le32(out, 0); // characteristics
    out.extend_from_slice(data);
    while !out.len().is_multiple_of(4) {
        out.push(0);
    }
}

/// The .res text of an .ico file: every frame as RT_ICON (ids 1..), the group as RT_GROUP_ICON 1.
fn ico_to_res(ico: &[u8]) -> Result<Vec<u8>, String> {
    let u16at = |o: usize| -> Result<u16, String> {
        ico.get(o..o + 2)
            .map(|b| u16::from_le_bytes([b[0], b[1]]))
            .ok_or_else(|| "ico: short".to_string())
    };
    let u32at = |o: usize| -> Result<u32, String> {
        ico.get(o..o + 4)
            .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
            .ok_or_else(|| "ico: short".to_string())
    };
    if u16at(0)? != 0 || u16at(2)? != 1 {
        return Err("ico: not an icon file".into());
    }
    let n = u16at(4)? as usize;
    if n == 0 {
        return Err("ico: no frames".into());
    }
    let mut res = Vec::new();
    res_entry(&mut res, 0, 0, 0, &[]); // the empty first entry every .res file starts with
    let mut group = Vec::new();
    le16(&mut group, 0);
    le16(&mut group, 1);
    le16(&mut group, n as u16);
    for i in 0..n {
        let e = 6 + 16 * i;
        let head = ico.get(e..e + 8).ok_or("ico: short")?;
        let size = u32at(e + 8)? as usize;
        let off = u32at(e + 12)? as usize;
        let data = ico.get(off..off + size).ok_or("ico: frame out of the file")?;
        res_entry(&mut res, 3, (i + 1) as u16, 0x1010, data); // RT_ICON, moveable | discardable
        group.extend_from_slice(head); // width, height, colours, reserved, planes, bit count
        le32(&mut group, size as u32);
        le16(&mut group, (i + 1) as u16);
    }
    res_entry(&mut res, 14, 1, 0x1030, &group); // RT_GROUP_ICON 1, moveable | pure | discardable
    Ok(res)
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

    // 3. the icon of the exe
    println!("cargo:rerun-if-changed=assets/app.ico");
    let os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let env = std::env::var("CARGO_CFG_TARGET_ENV").unwrap_or_default();
    if os == "windows" && env == "msvc" {
        let ico = std::fs::read("assets/app.ico").expect("read assets/app.ico");
        let res = ico_to_res(&ico).expect("assets/app.ico");
        let path = out.join("app.res");
        std::fs::write(&path, res).expect("write app.res");
        println!("cargo:rustc-link-arg-bins={}", path.display());
    }
}
