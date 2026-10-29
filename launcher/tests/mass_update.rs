//! Mass-update test (O314): a fake update server on 127.0.0.1 and a fake install folder, updated many times in a row
//! with the real launcher code and the real `curl`. Covers a normal update, an interrupted download (resumed with a
//! `Range`), a bad hash, a bad signature, a rollback of the swap, a swap cut short by a crash, an older manifest,
//! a path out of the folder, an unreachable server, and the launcher updating itself.
mod common;
use cinders_launcher::i18n::Error;
use cinders_launcher::install::{Event, Fault, Options, STATE_DIR};
use cinders_launcher::selfupdate::{self, Applied};
use cinders_selfupdate::hash::sha256_hex;
use common::*;

fn rel(version: u64, files: &[(&str, &[u8])]) -> Release {
    Release {
        version,
        package: 14,
        files: files.iter().map(|(n, d)| (n.to_string(), d.to_vec())).collect(),
        launcher: None,
    }
}

fn run(w: &World, opts: Options) -> Result<cinders_launcher::install::Outcome, Error> {
    w.updater(opts).run(&mut |_| {})
}

#[test]
fn first_install_then_no_op() {
    let w = World::new("first");
    let r1 = rel(
        1,
        &[
            ("Chaos.exe", b"exe v1"),
            ("libssl-3-x64.dll", b"dll v1"),
            ("chaos.pack", &[9u8; 100_000]),
        ],
    );
    r1.publish(&w.srv, &w.kp);
    let mut events = Vec::new();
    let o = w.updater(World::fast()).run(&mut |e| events.push(e)).unwrap();
    assert_eq!((o.version, o.package, o.game.as_str()), (1, Some(14), "Chaos.exe"));
    assert_eq!(o.replaced.len(), 3);
    assert_eq!(o.downloaded, 6 + 6 + 100_000);
    w.assert_is(&r1);
    w.assert_clean();
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::Progress { done, total } if done == total && *total > 0)));
    // the exe is applied last
    assert_eq!(o.replaced.last().map(String::as_str), Some("Chaos.exe"));

    // second run: nothing changed, nothing downloaded (the hash cache answers, no blob is requested)
    w.srv.clear_hits();
    let o = run(&w, World::fast()).unwrap();
    assert!(o.replaced.is_empty() && o.downloaded == 0);
    assert_eq!(w.srv.blob_hits(), 0);
    assert_eq!(w.srv.hits_for("manifest.json").len(), 1);
}

#[test]
fn changed_file_is_replaced_and_the_rest_is_kept() {
    let w = World::new("changed");
    rel(1, &[("Chaos.exe", b"exe v1"), ("a.dll", b"dll v1")]).publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();
    let r2 = rel(2, &[("Chaos.exe", b"exe v2 longer"), ("a.dll", b"dll v1")]);
    r2.publish(&w.srv, &w.kp);
    w.srv.clear_hits();
    let o = run(&w, World::fast()).unwrap();
    assert_eq!(o.replaced, vec!["Chaos.exe".to_string()]);
    assert_eq!(w.srv.blob_hits(), 1);
    w.assert_is(&r2);
    w.assert_clean();
}

#[test]
fn a_file_changed_by_hand_is_repaired() {
    let w = World::new("hand");
    let r = rel(1, &[("Chaos.exe", b"exe v1"), ("a.dll", b"dll v1")]);
    r.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();
    std::fs::write(w.dir.join("a.dll"), b"xxx v1").unwrap(); // same size, new mtime
    let o = run(&w, World::fast()).unwrap();
    assert_eq!(o.replaced, vec!["a.dll".to_string()]);
    w.assert_is(&r);
    std::fs::remove_file(w.dir.join("a.dll")).unwrap();
    run(&w, World::fast()).unwrap();
    w.assert_is(&r);
}

#[test]
fn interrupted_download_resumes_with_a_range() {
    let w = World::new("cut");
    let big: Vec<u8> = (0..300_000u32).map(|i| (i % 251) as u8).collect();
    let r = rel(1, &[("Chaos.exe", b"exe"), ("chaos.pack", &big)]);
    r.publish(&w.srv, &w.kp);
    let pack = blob_path(&sha256_hex(&big));
    w.srv.state.lock().unwrap().cut_once.insert(pack.clone(), 120_000);

    // no retries: the run fails, the install is untouched, the half download stays for the next run
    let opts = Options {
        retries: 0,
        backoff_ms: 1,
        ..Options::default()
    };
    let err = run(&w, opts).unwrap_err();
    assert!(matches!(err, Error::Download { .. }), "{err:?}");
    assert!(
        w.read("Chaos.exe").is_none() && w.read("chaos.pack").is_none(),
        "nothing installed"
    );
    let part = w
        .dir
        .join(STATE_DIR)
        .join("stage")
        .join(format!("{}.part", sha256_hex(&big)));
    let held = std::fs::metadata(&part).unwrap().len();
    assert!(held > 0 && held < big.len() as u64, "{held}");

    // the next run asks only for the rest
    w.srv.clear_hits();
    run(&w, World::fast()).unwrap();
    w.assert_is(&r);
    let hits = w.srv.hits_for(&pack);
    assert_eq!(hits.len(), 1);
    assert_eq!(hits[0].1, Some(held), "resumed from the byte it held");
    w.assert_clean();
}

#[test]
fn cut_connection_is_retried_inside_one_run() {
    let w = World::new("retry");
    let big: Vec<u8> = (0..200_000u32).map(|i| (i * 7 % 253) as u8).collect();
    let r = rel(1, &[("Chaos.exe", b"exe"), ("chaos.pack", &big)]);
    r.publish(&w.srv, &w.kp);
    w.srv
        .state
        .lock()
        .unwrap()
        .cut_once
        .insert(blob_path(&sha256_hex(&big)), 50_000);
    run(&w, World::fast()).unwrap();
    w.assert_is(&r);
    let hits = w.srv.hits_for(&blob_path(&sha256_hex(&big)));
    assert_eq!(hits.len(), 2);
    assert!(hits[1].1.is_some());
}

#[test]
fn bad_hash_is_never_installed() {
    let w = World::new("hash");
    let old = rel(1, &[("Chaos.exe", b"exe v1"), ("a.dll", b"dll v1")]);
    old.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();

    let new = rel(2, &[("a.dll", b"dll v2"), ("Chaos.exe", b"exe v2")]);
    new.publish(&w.srv, &w.kp);
    // the exe blob is always served damaged (same length, other bytes)
    let exe_path = blob_path(&sha256_hex(b"exe v2"));
    w.srv.set(&exe_path, b"EVIL v2".to_vec().into_iter().take(6).collect());
    let err = run(&w, World::fast()).unwrap_err();
    assert_eq!(err, Error::HashMismatch("Chaos.exe".into()));
    // not even the good dll was applied: the old release is whole
    w.assert_is(&old);
    assert!(!w.dir.join(STATE_DIR).join("journal.json").exists());
    assert_eq!(w.srv.hits_for(&exe_path).len(), 4, "1 try + 3 retries");

    // the server is fixed: the next run succeeds, and the good dll was kept from the failed run
    new.publish(&w.srv, &w.kp);
    w.srv.clear_hits();
    run(&w, World::fast()).unwrap();
    w.assert_is(&new);
    assert_eq!(
        w.srv.hits_for(&blob_path(&sha256_hex(b"dll v2"))).len(),
        0,
        "kept in the stage folder"
    );
    w.assert_clean();
}

#[test]
fn a_damaged_blob_once_is_fetched_again() {
    let w = World::new("hash-once");
    let r = rel(1, &[("Chaos.exe", b"exe v1")]);
    r.publish(&w.srv, &w.kp);
    w.srv
        .state
        .lock()
        .unwrap()
        .corrupt_once
        .insert(blob_path(&sha256_hex(b"exe v1")), b"exe vX".to_vec());
    run(&w, World::fast()).unwrap();
    w.assert_is(&r);
}

#[test]
fn bad_signature_installs_nothing() {
    let w = World::new("sig");
    let old = rel(1, &[("Chaos.exe", b"exe v1")]);
    old.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();

    let new = rel(2, &[("Chaos.exe", b"exe v2")]);
    // signed by another key
    let other = keypair(99);
    new.publish(&w.srv, &other);
    w.srv.clear_hits();
    assert_eq!(run(&w, World::fast()), Err(Error::BadSignature));
    assert_eq!(w.srv.blob_hits(), 0, "no download before the signature is good");
    w.assert_is(&old);

    // right key, payload changed after signing
    new.publish(&w.srv, &w.kp);
    let env = new.envelope(&w.kp).replace("\\\"version\\\":2", "\\\"version\\\":3");
    w.srv.set("/updates/live/manifest.json", env.into_bytes());
    assert_eq!(run(&w, World::fast()), Err(Error::BadSignature));

    // not signed at all
    let mut v: serde_json::Value = serde_json::from_str(&new.envelope(&w.kp)).unwrap();
    v.as_object_mut().unwrap().remove("signature");
    w.srv.set("/updates/live/manifest.json", v.to_string().into_bytes());
    assert_eq!(run(&w, World::fast()), Err(Error::BadSignature));
    w.assert_is(&old);
    assert_eq!(w.srv.blob_hits(), 0);
}

#[test]
fn a_signed_manifest_with_a_bad_path_is_refused() {
    let w = World::new("path");
    let mut r = rel(1, &[("Chaos.exe", b"exe v1")]);
    r.files.push(("../evil.dll".into(), b"x".to_vec()));
    r.publish(&w.srv, &w.kp);
    let err = run(&w, World::fast()).unwrap_err();
    assert!(matches!(err, Error::BadManifest(_)), "{err:?}");
    assert!(w.read("Chaos.exe").is_none());
    assert!(!w.dir.parent().unwrap().join("evil.dll").exists());
}

#[test]
fn rollback_when_the_swap_fails() {
    let w = World::new("rollback");
    let old = rel(
        1,
        &[
            ("Chaos.exe", b"exe v1"),
            ("a.dll", b"dll v1"),
            ("chaos.pack", b"pack v1"),
        ],
    );
    old.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();

    let new = rel(
        2,
        &[
            ("Chaos.exe", b"exe v2"),
            ("a.dll", b"dll v2"),
            ("chaos.pack", b"pack v2"),
        ],
    );
    new.publish(&w.srv, &w.kp);
    for n in 0..3 {
        let opts = Options {
            fault: Fault::FailApplyAfter(n),
            ..World::fast()
        };
        let err = run(&w, opts).unwrap_err();
        assert!(matches!(err, Error::Apply(_)), "fail after {n}: {err:?}");
        w.assert_is(&old);
        let st = w.dir.join(STATE_DIR);
        assert!(!st.join("journal.json").exists() && !st.join("backup").exists());
        // the downloads survive in the stage folder
        assert_eq!(w.applied_version(), 1);
    }
    // the next run installs without downloading again
    w.srv.clear_hits();
    run(&w, World::fast()).unwrap();
    w.assert_is(&new);
    assert_eq!(w.srv.blob_hits(), 0);
    assert_eq!(w.applied_version(), 2);
    w.assert_clean();
}

#[test]
fn a_swap_cut_short_by_a_crash_is_undone_at_the_next_start() {
    let w = World::new("crash");
    let old = rel(1, &[("Chaos.exe", b"exe v1"), ("a.dll", b"dll v1")]);
    old.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();

    // the state a crash leaves: a.dll already new, Chaos.exe moved to backup, new exe not yet in place
    let st = w.dir.join(STATE_DIR);
    std::fs::create_dir_all(st.join("backup")).unwrap();
    std::fs::create_dir_all(st.join("stage")).unwrap();
    std::fs::rename(w.dir.join("a.dll"), st.join("backup").join("a.dll")).unwrap();
    std::fs::write(w.dir.join("a.dll"), b"dll v2").unwrap();
    std::fs::rename(w.dir.join("Chaos.exe"), st.join("backup").join("Chaos.exe")).unwrap();
    std::fs::write(st.join("stage").join(sha256_hex(b"exe v2")), b"exe v2").unwrap();
    let journal = serde_json::json!({"files": [
        {"path": "a.dll", "sha": sha256_hex(b"dll v2"), "had_old": true},
        {"path": "Chaos.exe", "sha": sha256_hex(b"exe v2"), "had_old": true},
    ]});
    std::fs::write(st.join("journal.json"), journal.to_string()).unwrap();

    w.updater(World::fast()).recover().unwrap();
    w.assert_is(&old);
    assert!(!st.join("journal.json").exists() && !st.join("backup").exists());

    // and a full run after it brings the new release
    let new = rel(2, &[("Chaos.exe", b"exe v2"), ("a.dll", b"dll v2")]);
    new.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();
    w.assert_is(&new);
}

#[test]
fn an_older_manifest_is_not_applied() {
    let mut w = World::new("older");
    let r5 = rel(5, &[("Chaos.exe", b"exe v5")]);
    r5.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();
    rel(4, &[("Chaos.exe", b"exe v4")]).publish(&w.srv, &w.kp);
    assert_eq!(run(&w, World::fast()), Err(Error::OlderManifest { got: 4, have: 5 }));
    w.assert_is(&r5);
    // same version again is fine (nothing to do)
    r5.publish(&w.srv, &w.kp);
    assert!(run(&w, World::fast()).unwrap().replaced.is_empty());
    // a package built after the live update: its baseline stops the downgrade on a fresh install
    let _ = std::fs::remove_dir_all(w.dir.join(STATE_DIR));
    w.cfg.baseline = 9;
    assert_eq!(run(&w, World::fast()), Err(Error::OlderManifest { got: 5, have: 9 }));
}

#[test]
fn unreachable_server_changes_nothing() {
    let w = World::new("offline");
    let r = rel(1, &[("Chaos.exe", b"exe v1")]);
    r.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();
    w.srv.state.lock().unwrap().offline = true;
    assert!(matches!(run(&w, World::fast()), Err(Error::Network(_))));
    w.assert_is(&r);
    w.srv.state.lock().unwrap().offline = false;
    w.srv.state.lock().unwrap().routes.remove("/updates/live/manifest.json");
    assert!(matches!(run(&w, World::fast()), Err(Error::Network(_))), "404");
}

#[test]
fn a_manifest_without_native_files_is_not_an_error() {
    let w = World::new("nonative");
    let payload = serde_json::json!({
        "format": 1, "product": "cinders-of-chaos", "version": 3, "min_package": 13,
        "encryption": "chaos-blob-1", "files_url": "files/", "files": []
    })
    .to_string();
    let sig = w.kp.sk.sign(payload.as_bytes(), None);
    let hex = |b: &[u8]| b.iter().map(|x| format!("{x:02x}")).collect::<String>();
    let env = serde_json::json!({
        "format": "chaos-update-1", "key": hex(&w.kp.pk[..]), "signature": hex(&sig[..]), "payload": payload
    });
    w.srv.set("/updates/live/manifest.json", env.to_string().into_bytes());
    let o = run(&w, World::fast()).unwrap();
    assert!(o.replaced.is_empty() && o.package.is_none());
    assert_eq!(o.game, "Chaos.exe");
}

#[test]
fn the_launcher_updates_itself_at_its_next_start() {
    let w = World::new("self");
    let mut r1 = rel(1, &[("Chaos.exe", b"exe v1"), ("CindersLauncher.exe", b"launcher v1")]);
    r1.launcher = Some("CindersLauncher.exe".into());
    r1.publish(&w.srv, &w.kp);

    let o = run(&w, World::fast()).unwrap();
    assert!(o.launcher_staged);
    assert_eq!(
        o.replaced,
        vec!["Chaos.exe".to_string()],
        "the launcher is not in the swap"
    );
    assert_eq!(
        w.read("CindersLauncher.exe").unwrap(),
        b"launcher v0",
        "the running one is untouched"
    );
    assert!(selfupdate::pending(&w.exe).exists());
    w.assert_clean();

    // before the restart: a second run neither downloads nor stages it again
    w.srv.clear_hits();
    let o2 = run(&w, World::fast()).unwrap();
    assert!(!o2.launcher_staged);
    assert_eq!(w.srv.blob_hits(), 0);

    // next start
    assert_eq!(selfupdate::apply_pending(&w.exe), Ok(Applied::Swapped));
    assert_eq!(w.read("CindersLauncher.exe").unwrap(), b"launcher v1");
    assert_eq!(w.read("CindersLauncher.old").unwrap(), b"launcher v0");
    assert_eq!(selfupdate::apply_pending(&w.exe), Ok(Applied::None));

    // up to date: no job for the launcher
    w.srv.clear_hits();
    let o3 = run(&w, World::fast()).unwrap();
    assert!(!o3.launcher_staged && w.srv.blob_hits() == 0);

    // a later release changes the launcher again
    let mut r2 = rel(2, &[("Chaos.exe", b"exe v1"), ("CindersLauncher.exe", b"launcher v2")]);
    r2.launcher = Some("CindersLauncher.exe".into());
    r2.publish(&w.srv, &w.kp);
    assert!(run(&w, World::fast()).unwrap().launcher_staged);
    assert_eq!(selfupdate::apply_pending(&w.exe), Ok(Applied::Swapped));
    assert_eq!(w.read("CindersLauncher.exe").unwrap(), b"launcher v2");
}

#[test]
fn a_bad_launcher_download_is_never_staged() {
    let w = World::new("self-bad");
    let mut r = rel(1, &[("Chaos.exe", b"exe v1"), ("CindersLauncher.exe", b"launcher v1")]);
    r.launcher = Some("CindersLauncher.exe".into());
    r.publish(&w.srv, &w.kp);
    w.srv
        .set(&blob_path(&sha256_hex(b"launcher v1")), b"launcher XX".to_vec());
    let err = run(&w, World::fast()).unwrap_err();
    assert_eq!(err, Error::HashMismatch("CindersLauncher.exe".into()));
    assert!(!selfupdate::pending(&w.exe).exists());
    assert_eq!(w.read("CindersLauncher.exe").unwrap(), b"launcher v0");
    assert!(w.read("Chaos.exe").is_none(), "nothing applied when a download failed");
}

/// Many updates in a row, each round with a random release and a random trouble. After every round the install is
/// exactly the last release that went through, never a mix; and after a clean round it is exactly the newest one.
#[test]
fn mass_update_many_rounds() {
    let w = World::new("mass");
    let mut rng = Rng(0x00C1_0DE5_0F0C_4A05);
    let names = [
        "Chaos.exe",
        "libssl-3-x64.dll",
        "libcrypto-3-x64.dll",
        "zlib1.dll",
        "chaos.pack",
        "CindersLauncher.exe",
    ];
    let mut files: Vec<(String, Vec<u8>)> = names
        .iter()
        .map(|n| {
            let len = 200 + rng.below(30_000) as usize;
            (n.to_string(), rng.bytes(len))
        })
        .collect();
    let mut good: Option<Release> = None;
    let (mut ok_rounds, mut failed_rounds, mut selfs) = (0, 0, 0);
    let rounds = 120;
    for round in 1..=rounds {
        // change 0..3 files; the pack is the big one
        for _ in 0..rng.below(4) {
            let i = rng.below(files.len() as u64) as usize;
            let len = if files[i].0 == "chaos.pack" {
                60_000 + rng.below(80_000) as usize
            } else {
                100 + rng.below(20_000) as usize
            };
            files[i].1 = rng.bytes(len);
        }
        let release = Release {
            version: round,
            package: 14 + round / 40,
            files: files.clone(),
            launcher: Some("CindersLauncher.exe".into()),
        };
        release.publish(&w.srv, &w.kp);
        let trouble = rng.below(9);
        let mut opts = World::fast();
        let changed: Vec<&(String, Vec<u8>)> = release
            .files
            .iter()
            .filter(|(n, d)| n != "CindersLauncher.exe" && w.read(n).as_deref() != Some(&d[..]))
            .collect();
        let mut expect_fail = false;
        match trouble {
            1 if !changed.is_empty() => {
                // a connection cut in the middle of a changed file (retried)
                let (_, d) = changed[rng.below(changed.len() as u64) as usize];
                w.srv
                    .state
                    .lock()
                    .unwrap()
                    .cut_once
                    .insert(blob_path(&sha256_hex(d)), d.len() / 2);
            }
            2 if !changed.is_empty() => {
                // one changed file arrives wrong for good
                let (n, d) = changed[rng.below(changed.len() as u64) as usize];
                let mut bad = d.clone();
                bad[0] ^= 0xff;
                w.srv.set(&blob_path(&sha256_hex(d)), bad);
                expect_fail = true;
                let _ = n;
            }
            3 if !changed.is_empty() => {
                opts.fault = Fault::FailApplyAfter(rng.below(changed.len() as u64) as usize);
                expect_fail = true;
            }
            4 => {
                release.publish(&w.srv, &keypair(50 + round as u8));
                expect_fail = true;
            }
            5 => {
                w.srv.state.lock().unwrap().offline = true;
                expect_fail = true;
            }
            _ => {}
        }
        let r = run(&w, opts);
        w.srv.state.lock().unwrap().offline = false;
        match r {
            Ok(o) => {
                assert!(!expect_fail, "round {round} trouble {trouble} should have failed");
                w.assert_is(&release);
                w.assert_clean();
                ok_rounds += 1;
                if o.launcher_staged {
                    assert_eq!(selfupdate::apply_pending(&w.exe), Ok(Applied::Swapped), "round {round}");
                    assert_eq!(
                        w.read("CindersLauncher.exe").unwrap(),
                        files.iter().find(|f| f.0 == "CindersLauncher.exe").unwrap().1
                    );
                    selfs += 1;
                }
                good = Some(release);
            }
            Err(e) => {
                assert!(expect_fail, "round {round} trouble {trouble}: {e:?}");
                failed_rounds += 1;
                // whole old release or nothing yet; never a mix
                match &good {
                    Some(g) => w.assert_is(g),
                    None => {
                        for (n, _) in &release.files {
                            assert!(
                                w.read(n).is_none() || n == "CindersLauncher.exe",
                                "round {round}: {n} half installed"
                            );
                        }
                    }
                }
                let st = w.dir.join(STATE_DIR);
                assert!(
                    !st.join("journal.json").exists() && !st.join("backup").exists(),
                    "round {round}"
                );
                // drop the nasty server state so the next round starts normal
                release.publish(&w.srv, &w.kp);
            }
        }
    }
    assert!(
        ok_rounds > 60 && failed_rounds > 10 && selfs > 10,
        "{ok_rounds} ok, {failed_rounds} failed, {selfs} launcher updates"
    );
    // a last clean run lands on the newest release
    let last = Release {
        version: rounds + 1,
        package: 17,
        files: files.clone(),
        launcher: Some("CindersLauncher.exe".into()),
    };
    last.publish(&w.srv, &w.kp);
    run(&w, World::fast()).unwrap();
    w.assert_is(&last);
    assert_eq!(w.applied_version(), rounds + 1);
}

// ---------------------------------------------------------------- News and Changelog (the website's launcher feed)

const FEED: &str = r#"{"format":1,"generated":1,
  "en":{"news":[{"id":1,"date":"2026-10-29","title":"Season two","text":"Join now.","url":"https://site.test/?view=1"}],
        "changelog":[{"id":"2026-10-22","date":"2026-10-22","title":"Wings","lines":["One."],"url":"https://site.test/p"}]},
  "pt-BR":{"news":[{"id":1,"date":"2026-10-29","title":"Temporada dois","text":"Entre agora.","url":"https://site.test/?view=1"}],
        "changelog":[]}}"#;

#[test]
fn feed_comes_from_the_server_and_survives_it_going_away() {
    use cinders_launcher::feed::{self, Panel};
    use cinders_launcher::i18n::Lang;
    use cinders_launcher::net::Curl;
    let w = World::new("feed");
    let path = format!("/{}", cinders_launcher::config::FEED_NAME);
    w.srv.set(&path, FEED.as_bytes().to_vec());
    match feed::load(&Curl, &w.cfg, Lang::Pt) {
        Panel::Ready { feed, cached: false } => assert_eq!(feed.news[0].title, "Temporada dois"),
        other => panic!("{other:?}"),
    }
    assert_eq!(w.srv.hits_for("chaos_launcher_feed").len(), 1);
    assert!(feed::cache_path(&w.dir).exists());
    // the server answers 404 (feed not installed yet), then is unreachable: the saved copy is shown
    w.srv.state.lock().unwrap().routes.remove(&path);
    assert!(matches!(
        feed::load(&Curl, &w.cfg, Lang::En),
        Panel::Ready { cached: true, .. }
    ));
    w.srv.state.lock().unwrap().offline = true;
    match feed::load(&Curl, &w.cfg, Lang::En) {
        Panel::Ready { feed, cached: true } => assert_eq!(feed.changelog[0].title, "Wings"),
        other => panic!("{other:?}"),
    }
    // a feed that is too big (curl stops at the size limit) or HTML keeps the saved copy as well
    w.srv.state.lock().unwrap().offline = false;
    w.srv.set(&path, vec![b'x'; feed::MAX_BYTES + 5000]);
    assert!(matches!(
        feed::load(&Curl, &w.cfg, Lang::En),
        Panel::Ready { cached: true, .. }
    ));
    w.srv.set(&path, b"<html>maintenance</html>".to_vec());
    assert!(matches!(
        feed::load(&Curl, &w.cfg, Lang::En),
        Panel::Ready { cached: true, .. }
    ));
    // no saved copy and no feed: a short message state, no error
    let _ = std::fs::remove_file(feed::cache_path(&w.dir));
    assert_eq!(feed::load(&Curl, &w.cfg, Lang::En), Panel::Unavailable);
}

#[test]
fn a_dead_feed_does_not_touch_the_update() {
    use cinders_launcher::feed;
    use cinders_launcher::i18n::Lang;
    use cinders_launcher::net::Curl;
    let w = World::new("deadfeed");
    let r1 = rel(1, &[("Chaos.exe", b"exe v1"), ("chaos.pack", &[3u8; 5000])]);
    r1.publish(&w.srv, &w.kp);
    // the feed path is not served at all: the update runs and the panel is only unavailable
    assert_eq!(feed::load(&Curl, &w.cfg, Lang::Pt), feed::Panel::Unavailable);
    run(&w, World::fast()).unwrap();
    w.assert_is(&r1);
    w.assert_clean();
}
