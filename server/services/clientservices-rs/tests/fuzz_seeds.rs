//! Replays the cargo-fuzz seed corpus (`fuzz/seeds/`) through the same invariants the fuzz targets check.
//! Runs on stable in `cargo test --locked`; the fuzzing itself (nightly) is in server/README.md "Rust services (O153)".

use clientservices::fuzz_checks::{check_misc, check_request};
use std::path::Path;

fn replay(dir: &str, f: fn(&[u8])) -> usize {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("fuzz/seeds").join(dir);
    let mut n = 0;
    for e in std::fs::read_dir(&root).expect("seed folder") {
        let bytes = std::fs::read(e.unwrap().path()).unwrap();
        f(&bytes);
        n += 1;
    }
    n
}

#[test]
fn request_seeds_hold_the_invariants() {
    assert!(replay("read_head", check_request) >= 8);
}

#[test]
fn misc_seeds_hold_the_invariants() {
    assert!(replay("parse_misc", check_misc) >= 6);
}
