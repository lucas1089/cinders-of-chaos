//! SHA-256 helpers.
use sha2::{Digest, Sha256};
use std::io::Read;
use std::path::Path;

pub fn sha256_hex(bytes: &[u8]) -> String {
    hex(&Sha256::digest(bytes))
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// SHA-256 of a file, read in 1 MB blocks (a 900 MB pack is never held in memory).
pub fn sha256_file(path: &Path) -> std::io::Result<String> {
    let mut f = std::fs::File::open(path)?;
    let mut h = Sha256::new();
    let mut buf = vec![0u8; 1 << 20];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Ok(hex(&h.finalize()))
}

/// True for 64 lower-case hex digits.
pub fn is_sha256_hex(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f'))
}

/// First 64 hex digits of a `.sha256` file ("HEX  name" or just "HEX"), lower case.
pub fn parse_sha(text: &str) -> Option<String> {
    let w = text.split_whitespace().next()?.to_ascii_lowercase();
    (w.len() == 64 && w.chars().all(|c| c.is_ascii_hexdigit())).then_some(w)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sha_parse_and_hash() {
        let h = sha256_hex(b"abc");
        assert_eq!(h, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
        assert_eq!(
            parse_sha(&format!("{}  cinders-admin.exe\n", h.to_uppercase())),
            Some(h)
        );
        assert_eq!(parse_sha("short"), None);
    }

    #[test]
    fn file_hash_matches_bytes() {
        let p = std::env::temp_dir().join(format!("cinders-selfupdate-hash-{}", std::process::id()));
        let data = vec![7u8; 3 * (1 << 20) + 5];
        std::fs::write(&p, &data).unwrap();
        assert_eq!(sha256_file(&p).unwrap(), sha256_hex(&data));
        let _ = std::fs::remove_file(&p);
        assert!(sha256_file(&p).is_err());
    }

    #[test]
    fn hex_check() {
        assert!(is_sha256_hex(&sha256_hex(b"x")));
        assert!(!is_sha256_hex("ABC"));
        assert!(!is_sha256_hex(&"A".repeat(64)));
    }
}
