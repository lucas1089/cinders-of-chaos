//! The whole way from a downloaded setup program to a played-ready folder (O552 phase C), against the fake update server:
//! the size the setup screen shows, the install of the launcher into a new folder, and the first run of the installed
//! copy, which downloads every file of the client.
mod common;
use cinders_launcher::config;
use cinders_launcher::install::Updater;
use cinders_launcher::net::Curl;
use cinders_launcher::setup::{self, Choices, Mode, Plain};
use common::*;

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

#[test]
fn from_the_setup_program_to_a_full_install() {
    let w = World::new("setup");
    let r = Release {
        version: 3,
        package: 14,
        files: vec![
            ("Chaos.exe".into(), b"exe bytes".to_vec()),
            ("libssl-3-x64.dll".into(), vec![5u8; 3000]),
            ("chaos.pack".into(), Rng(11).bytes(200_000)),
        ],
        launcher: None,
    };
    r.publish(&w.srv, &w.kp);
    // the facts built into the setup program: what set_launcher_config.py --embed writes
    let embedded = format!(
        r#"{{"manifest":"{}","public_key":"{}"}}"#,
        w.srv.manifest_url(),
        hex(&w.kp.pk[..])
    );
    let beside_setup = w.dir.join("Downloads");
    std::fs::create_dir_all(&beside_setup).unwrap();
    let setup_exe = beside_setup.join("Cinders-of-Chaos-Setup.exe");
    std::fs::write(&setup_exe, b"the launcher program").unwrap();
    assert_eq!(setup::mode(&beside_setup, &embedded), Mode::Setup);

    // the screen's size line comes from the signed manifest
    let probe = config::parse(&embedded, &beside_setup).unwrap();
    let need = setup::download_size(&Curl, &probe).unwrap();
    assert_eq!(need, Some(9 + 3000 + 200_000));
    assert!(setup::free_space(&w.dir.join("not").join("there")).is_some_and(|f| f > 0));

    // install into a new folder
    let dir = w.dir.join("Games").join("Cinders");
    let done = setup::install(&setup_exe, &dir, &embedded, Choices::default(), "0.2.0", &Plain, &Plain).unwrap();
    assert_eq!(setup::mode(&dir, ""), Mode::Normal);

    // the installed copy runs the ordinary update: an empty folder becomes the whole client
    let cfg = config::load(&dir).unwrap();
    let u = Updater {
        cfg: &cfg,
        fetch: &Curl,
        exe: done.exe.clone(),
        opts: World::fast(),
    };
    let o = u.run(&mut |_| {}).unwrap();
    assert_eq!(o.replaced.len(), 3);
    for (n, d) in &r.files {
        assert_eq!(std::fs::read(dir.join(n)).unwrap(), *d, "{n}");
    }
    assert_eq!(
        std::fs::read(dir.join("CindersLauncher.exe")).unwrap(),
        b"the launcher program"
    );
    // and the uninstall takes exactly that away again
    std::fs::write(dir.join("my_notes.txt"), b"player file").unwrap();
    let gone = setup::uninstall(&dir, &done.exe, &Plain, &Plain);
    assert!(gone.contains(&"Chaos.exe".to_string()) && gone.contains(&"chaos.pack".to_string()));
    assert!(!dir.join("chaos.pack").exists() && !dir.join("launcher.json").exists());
    assert!(dir.join("my_notes.txt").is_file());
}

#[test]
fn a_setup_with_a_wrong_key_or_address_installs_nothing_it_cannot_trust() {
    let w = World::new("setupbad");
    Release {
        version: 1,
        package: 14,
        files: vec![("Chaos.exe".into(), b"exe".to_vec())],
        launcher: None,
    }
    .publish(&w.srv, &w.kp);
    let other = keypair(9);
    let embedded = format!(
        r#"{{"manifest":"{}","public_key":"{}"}}"#,
        w.srv.manifest_url(),
        hex(&other.pk[..])
    );
    let cfg = config::parse(&embedded, &w.dir).unwrap();
    // the size line refuses a manifest the built-in key did not sign
    assert!(setup::download_size(&Curl, &cfg).is_err());
    // a setup that has no facts built in does not offer to install
    assert_eq!(setup::mode(&w.dir, ""), Mode::Broken);
}
