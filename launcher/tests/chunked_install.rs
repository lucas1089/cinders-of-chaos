//! Install from an empty folder, repair and the chunk pool (O552), with the real launcher code, the real `curl` and the
//! fake update server of `common`: a first install, a second run that does nothing, a flipped byte found by "verify"
//! and repaired by one piece, a cut piece, a corrupt piece, an update that changes one piece, a full disk, a manifest
//! whose piece hash is wrong.
mod common;
use cinders_launcher::i18n::Error;
use cinders_launcher::install::{Event, Options, SPACE_MARGIN};
use cinders_selfupdate::hash::sha256_hex;
use common::*;

const MB: usize = 1024 * 1024;

/// A release whose `chaos.pack` has chunk hashes (pieces of 1 MiB, the smallest the launcher accepts).
#[derive(Clone)]
struct Rel {
    version: u64,
    pack: Vec<u8>,
    /// replaces the signed hash of one piece
    wrong_piece: Option<usize>,
    small: Vec<(String, Vec<u8>)>,
}

impl Rel {
    fn new(version: u64, pack: Vec<u8>) -> Rel {
        let small = (0..10)
            .map(|i| (format!("lib{i}.dll"), format!("dll {i} v{version}").into_bytes()))
            .chain([("Chaos.exe".to_string(), format!("exe v{version}").into_bytes())])
            .collect();
        Rel {
            version,
            pack,
            wrong_piece: None,
            small,
        }
    }

    fn payload(&self) -> String {
        let mut files: Vec<serde_json::Value> = self
            .small
            .iter()
            .map(|(n, d)| serde_json::json!({"path": n, "sha256": sha256_hex(d), "size": d.len()}))
            .collect();
        let mut hashes: Vec<String> = self.pack.chunks(MB).map(sha256_hex).collect();
        if let Some(i) = self.wrong_piece {
            hashes[i] = sha256_hex(b"not this piece");
        }
        files.push(serde_json::json!({
            "path": "chaos.pack", "sha256": sha256_hex(&self.pack), "size": self.pack.len(),
            "chunk": MB, "chunks": hashes
        }));
        serde_json::json!({
            "format": 1, "product": "cinders-of-chaos", "version": self.version, "min_version": 0,
            "min_package": 13, "encryption": "chaos-blob-1", "files_url": "files/", "files": [],
            "native": {"package": 14, "game": "Chaos.exe", "files_url": "native/", "files": files}
        })
        .to_string()
    }

    fn publish(&self, w: &World) {
        for (_, d) in &self.small {
            w.srv.set(&blob_path(&sha256_hex(d)), d.clone());
        }
        w.srv.set(&blob_path(&sha256_hex(&self.pack)), self.pack.clone());
        let payload = self.payload();
        let sig = w.kp.sk.sign(payload.as_bytes(), None);
        let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
        let env = serde_json::json!({
            "format": "chaos-update-1", "key": hex(&w.kp.pk[..]), "signature": hex(&sig[..]), "payload": payload
        });
        w.srv.set("/updates/live/manifest.json", env.to_string().into_bytes());
    }

    fn assert_installed(&self, w: &World) {
        assert_eq!(
            w.read("chaos.pack").as_deref(),
            Some(&self.pack[..]),
            "pack of release {}",
            self.version
        );
        for (n, d) in &self.small {
            assert_eq!(w.read(n).as_deref(), Some(&d[..]), "{n}");
        }
    }
}

fn pack(len: usize, seed: u64) -> Vec<u8> {
    Rng(seed).bytes(len)
}

fn fast() -> Options {
    Options {
        retries: 3,
        backoff_ms: 1,
        // a test machine's own free space must not decide these runs
        free_space: Some(u64::MAX),
        ..Options::default()
    }
}

/// Start offsets of the Range requests for the blob of `data`, sorted.
fn ranges_of(w: &World, data: &[u8]) -> Vec<u64> {
    let mut v: Vec<u64> = w
        .srv
        .hits_for(&sha256_hex(data))
        .into_iter()
        .filter_map(|(_, r)| r)
        .collect();
    v.sort();
    v
}

#[test]
fn an_empty_folder_becomes_a_full_install_and_the_second_run_does_nothing() {
    let w = World::new("fresh");
    let r1 = Rel::new(1, pack(3 * MB + 1234, 1));
    r1.publish(&w);
    let mut events = Vec::new();
    let o = w.updater(fast()).run(&mut |e| events.push(e)).unwrap();
    assert_eq!(o.replaced.len(), 12);
    assert_eq!(
        o.downloaded,
        r1.pack.len() as u64 + r1.small.iter().map(|(_, d)| d.len() as u64).sum::<u64>()
    );
    r1.assert_installed(&w);
    w.assert_clean();
    // the pack came in four pieces, each its own Range, no whole-file request
    assert_eq!(
        ranges_of(&w, &r1.pack),
        vec![0, MB as u64, 2 * MB as u64, 3 * MB as u64]
    );
    // the window can say "n/12 files" and a growing byte count
    let files: Vec<(usize, usize)> = events
        .iter()
        .filter_map(|e| match e {
            Event::Files { done, total } => Some((*done, *total)),
            _ => None,
        })
        .collect();
    assert_eq!(files.first(), Some(&(0, 12)));
    assert_eq!(files.last(), Some(&(12, 12)));
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::Progress { done, total } if done == total && *total > 3 * MB as u64)));
    w.srv.clear_hits();
    let o = w.updater(fast()).run(&mut |_| {}).unwrap();
    assert!(o.replaced.is_empty() && o.downloaded == 0);
    assert_eq!(w.srv.blob_hits(), 0);
}

#[test]
fn verify_finds_a_flipped_byte_the_cache_hides_and_repairs_one_piece() {
    let w = World::new("repair");
    let r1 = Rel::new(1, pack(4 * MB, 2));
    r1.publish(&w);
    w.updater(fast()).run(&mut |_| {}).unwrap();
    // flip one byte in piece 2 and put the modification time back: size and mtime are what the cache goes by
    let path = w.dir.join("chaos.pack");
    let before = std::fs::metadata(&path).unwrap().modified().unwrap();
    let mut bad = std::fs::read(&path).unwrap();
    bad[2 * MB + 77] ^= 0xFF;
    std::fs::write(&path, &bad).unwrap();
    std::fs::OpenOptions::new()
        .write(true)
        .open(&path)
        .unwrap()
        .set_modified(before)
        .unwrap();
    // a normal run trusts the cache
    w.srv.clear_hits();
    let o = w.updater(fast()).run(&mut |_| {}).unwrap();
    assert!(o.replaced.is_empty());
    assert_eq!(w.read("chaos.pack").unwrap(), bad);
    // "verify" hashes again and fetches only the damaged piece
    w.srv.clear_hits();
    let o = w.updater(Options { verify: true, ..fast() }).run(&mut |_| {}).unwrap();
    assert_eq!(o.replaced, vec!["chaos.pack".to_string()]);
    r1.assert_installed(&w);
    w.assert_clean();
    assert_eq!(
        ranges_of(&w, &r1.pack),
        vec![2 * MB as u64],
        "one piece, not the whole pack"
    );
    // and it is quiet again
    w.srv.clear_hits();
    let o = w.updater(Options { verify: true, ..fast() }).run(&mut |_| {}).unwrap();
    assert!(o.replaced.is_empty());
    assert_eq!(w.srv.blob_hits(), 0);
}

#[test]
fn a_new_pack_with_one_changed_piece_downloads_one_piece() {
    let w = World::new("onepiece");
    let r1 = Rel::new(1, pack(4 * MB, 3));
    r1.publish(&w);
    w.updater(fast()).run(&mut |_| {}).unwrap();
    let mut p2 = r1.pack.clone();
    for b in &mut p2[MB..MB + 5000] {
        *b ^= 0x5A;
    }
    let r2 = Rel::new(2, p2);
    r2.publish(&w);
    w.srv.clear_hits();
    let o = w.updater(fast()).run(&mut |_| {}).unwrap();
    assert!(o.replaced.contains(&"chaos.pack".to_string()));
    r2.assert_installed(&w);
    w.assert_clean();
    assert_eq!(
        ranges_of(&w, &r2.pack),
        vec![MB as u64],
        "the three unchanged pieces came from the old pack"
    );
}

#[test]
fn a_cut_piece_is_fetched_again_and_a_corrupt_one_too() {
    for (name, cut, corrupt) in [("cutpiece", true, false), ("corruptpiece", false, true)] {
        let w = World::new(name);
        let r1 = Rel::new(1, pack(3 * MB, 4));
        r1.publish(&w);
        let blob = blob_path(&sha256_hex(&r1.pack));
        {
            let mut g = w.srv.state.lock().unwrap();
            if cut {
                g.cut_once.insert(blob.clone(), 100_000);
            }
            if corrupt {
                let mut bad = r1.pack.clone();
                for k in 0..3 {
                    bad[k * MB + 10] ^= 1; // whichever piece is asked first is wrong
                }
                g.corrupt_once.insert(blob, bad);
            }
        }
        w.updater(fast()).run(&mut |_| {}).unwrap();
        r1.assert_installed(&w);
        w.assert_clean();
        // three pieces plus the retry of the one that failed
        assert!(w.srv.hits_for(&sha256_hex(&r1.pack)).len() >= 4, "{name}");
    }
}

#[test]
fn a_full_disk_refuses_before_the_first_byte() {
    let w = World::new("nospace");
    let r1 = Rel::new(1, pack(3 * MB, 5));
    r1.publish(&w);
    let total = (3 * MB) as u64 + r1.small.iter().map(|(_, d)| d.len() as u64).sum::<u64>();
    let err = w
        .updater(Options {
            free_space: Some(total + SPACE_MARGIN - 1),
            ..fast()
        })
        .run(&mut |_| {})
        .unwrap_err();
    assert_eq!(
        err,
        Error::NoSpace {
            need: total + SPACE_MARGIN,
            free: total + SPACE_MARGIN - 1
        }
    );
    assert_eq!(w.srv.blob_hits(), 0, "nothing was downloaded");
    assert!(w.read("chaos.pack").is_none());
    // exactly enough is enough
    w.updater(Options {
        free_space: Some(total + SPACE_MARGIN),
        ..fast()
    })
    .run(&mut |_| {})
    .unwrap();
    r1.assert_installed(&w);
}

#[test]
fn what_is_already_staged_is_not_counted_again() {
    // an earlier run left its pieces: the second run needs only the rest
    let w = World::new("staged");
    let r1 = Rel::new(1, pack(3 * MB, 6));
    r1.publish(&w);
    let total = (3 * MB) as u64 + r1.small.iter().map(|(_, d)| d.len() as u64).sum::<u64>();
    let dir = w
        .dir
        .join(cinders_launcher::install::STATE_DIR)
        .join("stage")
        .join(format!("{}.chunks", sha256_hex(&r1.pack)));
    std::fs::create_dir_all(&dir).unwrap();
    for (i, piece) in r1.pack.chunks(MB).enumerate().take(2) {
        std::fs::write(dir.join(format!("c{i}")), piece).unwrap();
    }
    let tight = total - 2 * MB as u64 + SPACE_MARGIN;
    w.updater(Options {
        free_space: Some(tight),
        ..fast()
    })
    .run(&mut |_| {})
    .unwrap();
    r1.assert_installed(&w);
    assert_eq!(
        ranges_of(&w, &r1.pack),
        vec![2 * MB as u64],
        "the staged pieces were kept"
    );
}

#[test]
fn a_wrong_piece_hash_in_the_manifest_installs_nothing() {
    let w = World::new("wrongpiece");
    let mut r1 = Rel::new(1, pack(3 * MB, 7));
    r1.wrong_piece = Some(1);
    r1.publish(&w);
    let err = w.updater(fast()).run(&mut |_| {}).unwrap_err();
    assert!(
        matches!(err, Error::HashMismatch(ref f) if f == "chaos.pack"),
        "{err:?}"
    );
    assert!(
        w.read("chaos.pack").is_none() && w.read("Chaos.exe").is_none(),
        "nothing was installed"
    );
}

#[test]
fn a_manifest_without_chunks_still_installs_as_before() {
    // the publisher of before: no chunk keys; the same files, one request each
    let w = World::new("nochunks");
    let r = Release {
        version: 1,
        package: 14,
        files: vec![
            ("Chaos.exe".into(), b"exe".to_vec()),
            ("chaos.pack".into(), pack(2 * MB, 8)),
        ],
        launcher: None,
    };
    r.publish(&w.srv, &w.kp);
    w.updater(fast()).run(&mut |_| {}).unwrap();
    w.assert_is(&r);
    assert!(ranges_of(&w, &r.files[1].1).is_empty(), "one plain request, no Range");
}
