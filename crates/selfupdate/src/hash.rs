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

/// Hash of a stream in pieces (a part of a big file is hashed without holding it in memory).
#[derive(Default)]
pub struct Sha256Stream(Sha256);

impl Sha256Stream {
    pub fn new() -> Self {
        Sha256Stream(Sha256::new())
    }

    pub fn update(&mut self, bytes: &[u8]) {
        self.0.update(bytes);
    }

    pub fn finish_hex(self) -> String {
        hex(&self.0.finalize())
    }
}

/// HMAC-SHA256 (RFC 2104) of `msg` under `key`. Used for the launcher's start ticket (O552).
pub fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    const BLOCK: usize = 64;
    let mut k = [0u8; BLOCK];
    if key.len() > BLOCK {
        k[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut inner = Sha256::new();
    inner.update(k.map(|b| b ^ 0x36));
    inner.update(msg);
    let mut outer = Sha256::new();
    outer.update(k.map(|b| b ^ 0x5c));
    outer.update(inner.finalize());
    outer.finalize().into()
}

/// HKDF-SHA256 (RFC 5869) with an empty salt, for one 32-byte output block: `T(1) = HMAC(PRK, info || 0x01)`.
pub fn hkdf_sha256_32(ikm: &[u8], info: &[u8]) -> [u8; 32] {
    let prk = hmac_sha256(&[0u8; 32], ikm);
    let mut msg = info.to_vec();
    msg.push(1);
    hmac_sha256(&prk, &msg)
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
    fn hmac_rfc4231_vectors() {
        // test case 1
        assert_eq!(
            hex(&hmac_sha256(&[0x0b; 20], b"Hi There")),
            "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
        );
        // test case 2
        assert_eq!(
            hex(&hmac_sha256(b"Jefe", b"what do ya want for nothing?")),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
        // test case 6: a key longer than the block
        assert_eq!(
            hex(&hmac_sha256(
                &[0xaa; 131],
                b"Test Using Larger Than Block-Size Key - Hash Key First"
            )),
            "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
        );
    }

    #[test]
    fn hkdf_rfc5869_case_3_has_an_empty_salt() {
        // RFC 5869 test case 3 (SHA-256, zero-length salt and info): the first 32 bytes of the 42-byte output
        let okm = hkdf_sha256_32(&[0x0b; 22], b"");
        assert_eq!(
            hex(&okm),
            "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d"
        );
    }

    #[test]
    fn stream_hash_matches_one_shot() {
        let mut s = Sha256Stream::new();
        s.update(b"a");
        s.update(b"bc");
        assert_eq!(s.finish_hex(), sha256_hex(b"abc"));
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
