//! The game starts with a ticket (O552 phase D), on a system with shell scripts: a fake game program writes the
//! environment it was started with; the tests prove what the launcher puts in it, what it keeps out of it, and that
//! `--play-local` needs neither a manifest nor a network.
#![cfg(unix)]
use cinders_launcher::config::Config;
use cinders_launcher::ticket::{self, Verdict};
use cinders_launcher::{install, launch};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

fn world(name: &str) -> PathBuf {
    let d = std::env::temp_dir().join(format!("cinders-launch-ticket-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    std::fs::create_dir_all(&d).unwrap();
    // the "game": writes its ticket variable (or "none") and its arguments to a file
    let script = "#!/bin/sh\nprintf '%s\\n' \"${CINDERS_TICKET:-none}\" > \"$(dirname \"$0\")/seen.txt\"\n";
    let exe = d.join("Chaos.exe");
    std::fs::write(&exe, script).unwrap();
    std::fs::set_permissions(&exe, std::fs::Permissions::from_mode(0o755)).unwrap();
    d
}

fn seen(d: &Path) -> String {
    let f = d.join("seen.txt");
    let t0 = Instant::now();
    while t0.elapsed() < Duration::from_secs(10) {
        if let Ok(t) = std::fs::read_to_string(&f) {
            if t.ends_with('\n') {
                return t.trim().to_string();
            }
        }
        std::thread::sleep(Duration::from_millis(20));
    }
    panic!("the fake game wrote nothing");
}

#[test]
fn the_game_gets_a_ticket_for_its_build_and_nothing_else_does() {
    let d = world("env");
    let cfg = Config::bare(&d);
    let t = launch::ticket_for(&cfg, Some(47)).expect("a ticket");
    launch::start(&cfg, "Chaos.exe", Some(&t)).unwrap();
    let got = seen(&d);
    assert_eq!(got, t);
    let v = ticket::verify(&ticket::embedded_sub_key(), &got, ticket::unix_now(), 47);
    assert!(matches!(v, Verdict::Ok { build: 47, .. }), "{v:?}");
    assert_eq!(
        ticket::verify(&ticket::embedded_sub_key(), &got, ticket::unix_now(), 46),
        Verdict::WrongBuild
    );

    // no ticket given: the game gets none, even when this process has one of its own
    let _ = std::fs::remove_file(d.join("seen.txt"));
    std::env::set_var(ticket::ENV, "t1.1.1.1.00.00");
    launch::start(&cfg, "Chaos.exe", None).unwrap();
    assert_eq!(seen(&d), "none");
    std::env::remove_var(ticket::ENV);
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn the_build_comes_from_the_run_or_from_the_last_saved_one() {
    let d = world("build");
    let cfg = Config::bare(&d);
    // nothing known: no ticket (the game then says "open it from the launcher" itself)
    assert_eq!(launch::ticket_for(&cfg, None), None);
    // the run's own number wins
    let t = launch::ticket_for(&cfg, Some(51)).unwrap();
    assert!(t.starts_with("t1.51."));
    // an earlier good run left its package in state.json ("play anyway" after an error)
    std::fs::create_dir_all(d.join(install::STATE_DIR)).unwrap();
    std::fs::write(
        d.join(install::STATE_DIR).join("state.json"),
        r#"{"version":9,"package":47}"#,
    )
    .unwrap();
    assert_eq!(install::saved_package(&d), Some(47));
    assert!(launch::ticket_for(&cfg, None).unwrap().starts_with("t1.47."));
    assert!(launch::ticket_for(&cfg, Some(51)).unwrap().starts_with("t1.51."));
    // a damaged state file is no build
    std::fs::write(d.join(install::STATE_DIR).join("state.json"), "junk").unwrap();
    assert_eq!(install::saved_package(&d), None);
    let _ = std::fs::remove_dir_all(&d);
}

#[test]
fn play_local_needs_no_manifest_and_no_network() {
    let d = world("local");
    let bin = env!("CARGO_BIN_EXE_cinders-launcher");
    // --build names the client build
    let st = std::process::Command::new(bin)
        .args(["--play-local", "--build", "47", "--dir"])
        .arg(&d)
        .status()
        .unwrap();
    assert!(st.success());
    let got = seen(&d);
    assert!(
        matches!(
            ticket::verify(&ticket::embedded_sub_key(), &got, ticket::unix_now(), 47),
            Verdict::Ok { build: 47, .. }
        ),
        "{got}"
    );
    // chaos_build.txt beside the game: the way the package's start-client.bat finds it
    let _ = std::fs::remove_file(d.join("seen.txt"));
    std::fs::write(d.join("chaos_build.txt"), "52\n").unwrap();
    let st = std::process::Command::new(bin)
        .args(["--play-local", "--dir"])
        .arg(&d)
        .status()
        .unwrap();
    assert!(st.success());
    assert!(seen(&d).starts_with("t1.52."));
    // no build anywhere: no ticket, and the game decides what to say
    let _ = std::fs::remove_file(d.join("seen.txt"));
    let _ = std::fs::remove_file(d.join("chaos_build.txt"));
    let st = std::process::Command::new(bin)
        .args(["--play-local", "--dir"])
        .arg(&d)
        .status()
        .unwrap();
    assert!(st.success());
    assert_eq!(seen(&d), "none");
    // a folder with no game says so and fails
    let empty = std::env::temp_dir().join(format!("cinders-launch-ticket-empty-{}", std::process::id()));
    std::fs::create_dir_all(&empty).unwrap();
    let st = std::process::Command::new(bin)
        .args(["--play-local", "--build", "1", "--dir"])
        .arg(&empty)
        .status()
        .unwrap();
    assert!(!st.success());
    let _ = std::fs::remove_dir_all(&empty);
    let _ = std::fs::remove_dir_all(&d);
}
