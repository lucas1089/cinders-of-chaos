//! The start ticket (O552 phase D): the game program starts only through the launcher.
//!
//! The launcher puts a short-lived ticket in the environment variable `CINDERS_TICKET` of the game process; the game
//! (client base patch 0198, `src/client/chaosticket.h`) checks it before it opens a window. No ticket, a wrong one or an
//! old one: the game says "Abra o jogo pelo Launcher" and starts the launcher.
//!
//! **This is a deterrent, not security.** The key is in the launcher and in the game, only obfuscated. Whoever reads the
//! launcher can mint a ticket; whoever patches the game can skip the check. It stops the double click on `Chaos.exe` (so
//! nobody plays on stale files by habit); the real gate is the game server's client guard.
//!
//! Format: `t1.<build>.<launcher>.<expiry>.<nonce>.<mac>`: the client build the ticket is for (the manifest's native
//! package), the launcher's own number, the Unix time it stops being good, 16 random bytes in hex, and
//! `mac = hex(HMAC-SHA256(sub_key, "t1|<build>|<launcher>|<expiry>|<nonce>"))`. `sub_key = HKDF-SHA256(client_key,
//! "cinders-launcher-ticket-v1")`, so the launcher never holds the key the game proves itself to the server with.
//! The same layout is in the C++ header and in `client/tools/ticket_vector_test.py`; all three read one vector
//! (`tests/data/ticket_vector.json`, made with a test key, never a real one).
use cinders_selfupdate::hash::{hkdf_sha256_32, hmac_sha256};

include!(concat!(env!("OUT_DIR"), "/ticket_key.rs"));

pub const ENV: &str = "CINDERS_TICKET";
pub const INFO: &[u8] = b"cinders-launcher-ticket-v1";
/// Seconds a ticket is good for: long enough for a slow start, too short to pass around.
pub const LIFETIME_SECS: u64 = 30;
/// A game restart (after an update) mints its own, a little longer, because the old process shuts down first.
pub const RESTART_LIFETIME_SECS: u64 = 60;

/// The sub key of a client guard key.
pub fn sub_key(client_key: &[u8]) -> [u8; 32] {
    hkdf_sha256_32(client_key, INFO)
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn message(build: u64, launcher: u64, expiry: u64, nonce: &str) -> String {
    format!("t1|{build}|{launcher}|{expiry}|{nonce}")
}

/// The ticket text for these values (the nonce is 32 lower-case hex digits).
pub fn mint(sub: &[u8; 32], build: u64, launcher: u64, expiry: u64, nonce: &str) -> String {
    let mac = hmac_sha256(sub, message(build, launcher, expiry, nonce).as_bytes());
    format!("t1.{build}.{launcher}.{expiry}.{nonce}.{}", hex(&mac))
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Verdict {
    Ok { build: u64, launcher: u64, expiry: u64 },
    Malformed,
    BadMac,
    Expired,
    WrongBuild,
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    a.len() == b.len() && a.iter().zip(b).fold(0u8, |d, (x, y)| d | (x ^ y)) == 0
}

/// What the game does with a ticket: parse it, check the mac, the expiry and the build. Kept here so the launcher's tests
/// can prove its own tickets pass the rules the C++ header implements.
pub fn verify(sub: &[u8; 32], text: &str, now: u64, expect_build: u64) -> Verdict {
    let parts: Vec<&str> = text.split('.').collect();
    let [tag, build, launcher, expiry, nonce, mac] = parts[..] else {
        return Verdict::Malformed;
    };
    let num = |s: &str| {
        (!s.is_empty() && s.len() <= 12 && s.bytes().all(|c| c.is_ascii_digit()))
            .then(|| s.parse::<u64>().ok())
            .flatten()
    };
    let (Some(build), Some(launcher), Some(expiry)) = (num(build), num(launcher), num(expiry)) else {
        return Verdict::Malformed;
    };
    let lower_hex = |s: &str, n: usize| s.len() == n && s.bytes().all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f'));
    if tag != "t1" || !lower_hex(nonce, 32) || !lower_hex(mac, 64) {
        return Verdict::Malformed;
    }
    let want = hex(&hmac_sha256(sub, message(build, launcher, expiry, nonce).as_bytes()));
    if !constant_time_eq(want.as_bytes(), mac.as_bytes()) {
        return Verdict::BadMac;
    }
    if now > expiry {
        return Verdict::Expired;
    }
    if build != expect_build {
        return Verdict::WrongBuild;
    }
    Verdict::Ok {
        build,
        launcher,
        expiry,
    }
}

/// The launcher's own number from `Cargo.toml`: 0.2.0 is 200, 1.4.12 is 10412.
pub fn launcher_build() -> u64 {
    let n = |s: &str| s.parse::<u64>().unwrap_or(0);
    n(env!("CARGO_PKG_VERSION_MAJOR")) * 10_000
        + n(env!("CARGO_PKG_VERSION_MINOR")) * 100
        + n(env!("CARGO_PKG_VERSION_PATCH"))
}

/// 16 random bytes as 32 hex digits, from the system's generator. None when it fails (no ticket is better than a weak one).
pub fn random_nonce() -> Option<String> {
    let mut b = [0u8; 16];
    getrandom::fill(&mut b).ok()?;
    Some(hex(&b))
}

pub fn unix_now() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// A ticket for the game of `build`, good for `LIFETIME_SECS`, made with the key built into this launcher.
pub fn for_launch(build: u64) -> Option<String> {
    let nonce = random_nonce()?;
    Some(mint(
        &embedded_sub_key(),
        build,
        launcher_build(),
        unix_now() + LIFETIME_SECS,
        &nonce,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The key of the vector: a TEST key, never a real one (the real one never enters the repository, a log or a test).
    const TEST_KEY: [u8; 32] = [0x11; 32];
    const NONCE: &str = "00112233445566778899aabbccddeeff";

    fn vector() -> serde_json::Value {
        let text = std::fs::read_to_string("tests/data/ticket_vector.json").expect("tests/data/ticket_vector.json");
        serde_json::from_str(&text).unwrap()
    }

    #[test]
    fn the_shared_vector() {
        let v = vector();
        assert_eq!(v["client_key_hex"], "11".repeat(32));
        let sub = sub_key(&TEST_KEY);
        assert_eq!(v["sub_key_hex"], hex(&sub), "the sub key");
        let t = mint(&sub, 47, 200, 1_800_000_000, NONCE);
        assert_eq!(v["ticket"], t.as_str(), "the ticket text");
        // what the C++ header must answer for the same ticket at the same times
        assert_eq!(
            verify(&sub, &t, 1_799_999_990, 47),
            Verdict::Ok {
                build: 47,
                launcher: 200,
                expiry: 1_800_000_000
            }
        );
        assert_eq!(
            verify(&sub, &t, 1_800_000_000, 47),
            Verdict::Ok {
                build: 47,
                launcher: 200,
                expiry: 1_800_000_000
            },
            "the last second counts"
        );
        assert_eq!(verify(&sub, &t, 1_800_000_001, 47), Verdict::Expired);
        assert_eq!(verify(&sub, &t, 1_799_999_990, 48), Verdict::WrongBuild);
        assert_eq!(verify(&[0x22; 32], &t, 1_799_999_990, 47), Verdict::BadMac);
    }

    #[test]
    fn any_change_breaks_the_mac_and_odd_text_is_malformed() {
        let sub = sub_key(&TEST_KEY);
        let t = mint(&sub, 47, 200, 2_000_000_000, NONCE);
        let parts: Vec<&str> = t.split('.').collect();
        for i in 1..5 {
            let mut p: Vec<String> = parts.iter().map(|s| s.to_string()).collect();
            p[i] = if i == 4 {
                "ff".repeat(16)
            } else {
                (p[i].parse::<u64>().unwrap() + 1).to_string()
            };
            assert_eq!(verify(&sub, &p.join("."), 1, 47), Verdict::BadMac, "field {i}");
        }
        let mut flipped = t.clone();
        flipped.replace_range(t.len() - 1.., if t.ends_with('0') { "1" } else { "0" });
        assert_eq!(verify(&sub, &flipped, 1, 47), Verdict::BadMac);
        for bad in [
            "",
            "t1",
            "t1.47.200.2000000000.x.y",
            &t.to_uppercase(),
            &format!("{t}.extra"),
            &t.replace("t1.", "t2."),
            &t.replace(".47.", ".-47."),
            &t.replace(".47.", ". 47."),
            &t.replace(".47.", ".+47."),
            &t.replace(NONCE, "0011"),
            &t[..t.len() - 1],
        ] {
            assert_eq!(verify(&sub, bad, 1, 47), Verdict::Malformed, "{bad:?}");
        }
    }

    #[test]
    fn the_built_in_key_makes_tickets_the_same_rules_accept() {
        // the key built into this test binary is the development key or a real one; either way mint and verify agree
        let t = for_launch(47).expect("random bytes");
        assert!(t.starts_with("t1.47."));
        let v = verify(&embedded_sub_key(), &t, unix_now(), 47);
        assert!(matches!(v, Verdict::Ok { build: 47, .. }), "{v:?}");
        // each ticket has its own nonce
        assert_ne!(for_launch(47), for_launch(47));
        // a ticket is good for 30 s
        let Verdict::Ok { expiry, .. } = v else { unreachable!() };
        assert!(expiry >= unix_now() + LIFETIME_SECS - 2 && expiry <= unix_now() + LIFETIME_SECS + 2);
        assert_eq!(verify(&embedded_sub_key(), &t, unix_now() + 31, 47), Verdict::Expired);
    }

    #[test]
    fn the_build_script_derives_the_same_sub_key_as_the_spec() {
        // build.rs makes the built-in sub key from CHAOS_CLIENT_KEY (or the public development key when it is unset); the
        // result must be what `sub_key` gives for that client key. Only the two keys that are public are compared; a real
        // key (a release build) is never read here, printed or compared.
        match option_env!("CHAOS_CLIENT_KEY") {
            None | Some("") => {
                assert!(std::hint::black_box(KEY_IS_DEV));
                assert_eq!(embedded_sub_key(), sub_key(b"DEV-KEY-cinders-of-chaos-UNSAFE!"));
            }
            Some(k) if k.eq_ignore_ascii_case(&"11".repeat(32)) => {
                assert!(!std::hint::black_box(KEY_IS_DEV));
                assert_eq!(embedded_sub_key(), sub_key(&TEST_KEY));
            }
            Some(_) => assert!(!std::hint::black_box(KEY_IS_DEV)),
        }
    }

    #[test]
    fn the_launcher_number_follows_cargo_toml() {
        let v = env!("CARGO_PKG_VERSION");
        let p: Vec<u64> = v.split('.').map(|s| s.parse().unwrap()).collect();
        assert_eq!(launcher_build(), p[0] * 10_000 + p[1] * 100 + p[2]);
    }

    #[test]
    fn the_key_is_not_in_the_binary_as_plain_text() {
        // X and M hold the sub key shuffled and masked: the sub key of the built-in key is not a literal of the arrays
        let sub = embedded_sub_key();
        assert!(!X.windows(8).any(|w| w == &sub[..8]));
        assert_ne!(X, sub);
    }
}
