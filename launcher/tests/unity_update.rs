//! The client choice (ROADMAP O433 phase 16): the Unity client goes through the launcher's own update code, in a
//! folder of its own (`unity/`), from its own signed manifest, with sub-folders. A fake update server on 127.0.0.1 and
//! the real `curl`, as in mass_update.rs. Covers a nested first install, a no-op second run, a changed and a removed
//! file, a swap that fails half way (rollback with nested folders), a bad hash, a bad signature, a manifest of the
//! wrong client, and the choice itself (the main client untouched, the launcher still updating itself).
mod common;
use cinders_launcher::choice;
use cinders_launcher::config::{self, Client};
use cinders_launcher::i18n::Error;
use cinders_launcher::install::{Fault, Options, STATE_DIR};
use cinders_launcher::selfupdate;
use cinders_selfupdate::hash::sha256_hex;
use common::*;

fn urel(version: u64, files: &[(&str, &[u8])]) -> UnityRelease {
    UnityRelease {
        version,
        package: 31,
        files: files.iter().map(|(n, d)| (n.to_string(), d.to_vec())).collect(),
        dev: None,
    }
}

fn player_v1() -> Vec<(&'static str, &'static [u8])> {
    vec![
        ("ChaosUnity.exe", b"exe v1"),
        ("UnityPlayer.dll", b"player v1"),
        ("ChaosUnity_Data/globalgamemanagers", b"ggm v1"),
        ("ChaosUnity_Data/Managed/Assembly-CSharp.dll", b"asm v1"),
        ("ChaosUnity_Data/Resources/unity default resources", b"res v1"),
        (
            "ChaosUnity_Data/StreamingAssets/overlay/modules/game_chaossound/sounds/a.ogg",
            b"ogg v1",
        ),
    ]
}

fn run_unity(w: &World, opts: Options) -> Result<cinders_launcher::install::Outcome, Error> {
    let cfg = w.unity_cfg();
    w.unity_updater(&cfg, opts).run(&mut |_| {})
}

fn assert_player(w: &World, r: &UnityRelease) {
    for (n, d) in &r.files {
        assert_eq!(w.unity_read(n).as_deref(), Some(&d[..]), "{n} of release {}", r.version);
    }
}

fn assert_unity_clean(w: &World) {
    let st = w.dir.join("unity").join(STATE_DIR);
    assert!(!st.join("journal.json").exists(), "journal left");
    assert!(!st.join("backup").exists(), "backup left");
    assert!(!st.join("stage").exists(), "stage left");
}

#[test]
fn nested_first_install_then_no_op() {
    let w = World::new("u-first");
    let r1 = urel(1, &player_v1());
    r1.publish(&w.srv, &w.kp);
    let o = run_unity(&w, World::fast()).unwrap();
    assert_eq!((o.version, o.package, o.game.as_str()), (1, Some(31), "ChaosUnity.exe"));
    assert_eq!(o.replaced.len(), 6);
    assert_eq!(
        o.replaced.last().map(String::as_str),
        Some("ChaosUnity.exe"),
        "the exe is last"
    );
    assert_player(&w, &r1);
    assert_unity_clean(&w);
    // its own folder: nothing of it in the install folder, no state of the main client made
    assert!(w.read("ChaosUnity.exe").is_none() && w.read("UnityPlayer.dll").is_none());
    assert!(!w.dir.join(STATE_DIR).join("state.json").exists());
    assert!(w.dir.join("unity").join(STATE_DIR).join("state.json").exists());

    w.srv.clear_hits();
    let o = run_unity(&w, World::fast()).unwrap();
    assert!(o.replaced.is_empty() && o.downloaded == 0);
    assert_eq!(w.srv.hits_for("/updates/unity/native/").len(), 0);
    assert_eq!(w.srv.hits_for("/updates/unity/manifest.json").len(), 1);
    assert_eq!(
        w.srv.hits_for("/updates/live/").len(),
        0,
        "the main manifest is not asked"
    );
}

#[test]
fn a_changed_file_is_replaced_a_dropped_file_goes_and_the_players_files_stay() {
    let w = World::new("u-change");
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();
    // what the player put there himself (the sprite pair) is never touched
    let things = w.dir.join("unity").join("things");
    std::fs::create_dir_all(&things).unwrap();
    std::fs::write(things.join("Tibia.dat"), b"pair").unwrap();

    let mut files = player_v1();
    files.retain(|(n, _)| !n.contains("game_chaossound"));
    files.push(("ChaosUnity_Data/Managed/New.dll", b"new v2"));
    files[0] = ("ChaosUnity.exe", b"exe v2 longer");
    let r2 = urel(2, &files);
    r2.publish(&w.srv, &w.kp);
    w.srv.clear_hits();
    let o = run_unity(&w, World::fast()).unwrap();
    assert_eq!(
        o.replaced,
        vec![
            "ChaosUnity_Data/Managed/New.dll".to_string(),
            "ChaosUnity.exe".to_string()
        ]
    );
    assert_eq!(w.srv.hits_for("/updates/unity/native/").len(), 2);
    assert_player(&w, &r2);
    assert_eq!(
        o.removed,
        vec!["ChaosUnity_Data/StreamingAssets/overlay/modules/game_chaossound/sounds/a.ogg".to_string()]
    );
    assert!(
        !w.dir
            .join("unity")
            .join("ChaosUnity_Data")
            .join("StreamingAssets")
            .exists(),
        "the folders the dropped file left empty are gone"
    );
    assert_eq!(std::fs::read(things.join("Tibia.dat")).unwrap(), b"pair");
    assert_unity_clean(&w);
}

#[test]
fn a_file_changed_by_hand_in_a_sub_folder_is_repaired() {
    let w = World::new("u-hand");
    let r = urel(1, &player_v1());
    r.publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();
    std::fs::write(
        w.dir
            .join("unity")
            .join("ChaosUnity_Data")
            .join("Managed")
            .join("Assembly-CSharp.dll"),
        b"xxx v1",
    )
    .unwrap();
    let o = run_unity(&w, World::fast()).unwrap();
    assert_eq!(
        o.replaced,
        vec!["ChaosUnity_Data/Managed/Assembly-CSharp.dll".to_string()]
    );
    assert_player(&w, &r);
    std::fs::remove_dir_all(w.dir.join("unity").join("ChaosUnity_Data")).unwrap();
    run_unity(&w, World::fast()).unwrap();
    assert_player(&w, &r);
}

#[test]
fn rollback_puts_nested_files_back() {
    let w = World::new("u-rollback");
    let old = urel(1, &player_v1());
    old.publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();
    let new_files: Vec<(&str, &[u8])> = vec![
        ("ChaosUnity.exe", b"exe v2"),
        ("UnityPlayer.dll", b"player v2"),
        ("ChaosUnity_Data/globalgamemanagers", b"ggm v2"),
        ("ChaosUnity_Data/Managed/Assembly-CSharp.dll", b"asm v2"),
        ("ChaosUnity_Data/Managed/Added.dll", b"added v2"),
        ("ChaosUnity_Data/Resources/unity default resources", b"res v2"),
    ];
    let new = urel(2, &new_files);
    new.publish(&w.srv, &w.kp);
    for n in 0..6 {
        let opts = Options {
            fault: Fault::FailApplyAfter(n),
            ..World::fast()
        };
        let err = run_unity(&w, opts).unwrap_err();
        assert!(matches!(err, Error::Apply(_)), "{n}: {err:?}");
        assert_player(&w, &old);
        assert!(!w.dir.join("unity").join(STATE_DIR).join("journal.json").exists());
    }
    // no fault: the update goes through, from the files the failed runs kept staged
    run_unity(&w, World::fast()).unwrap();
    assert_player(&w, &new);
    assert_unity_clean(&w);
}

#[test]
fn a_bad_hash_and_a_bad_signature_install_nothing() {
    let w = World::new("u-bad");
    let old = urel(1, &player_v1());
    old.publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();

    let mut files = player_v1();
    files[3] = ("ChaosUnity_Data/Managed/Assembly-CSharp.dll", b"asm v2");
    let new = urel(2, &files);
    new.publish(&w.srv, &w.kp);
    w.srv.set(
        &unity_blob_path(&sha256_hex(b"asm v2")),
        b"EVIL v2".iter().copied().take(6).collect(),
    );
    let err = run_unity(&w, World::fast()).unwrap_err();
    assert_eq!(
        err,
        Error::HashMismatch("ChaosUnity_Data/Managed/Assembly-CSharp.dll".into())
    );
    assert_player(&w, &old);

    // another key signed it
    new.publish(&w.srv, &keypair(99));
    w.srv.clear_hits();
    assert_eq!(run_unity(&w, World::fast()), Err(Error::BadSignature));
    assert_eq!(w.srv.hits_for("/updates/unity/native/").len(), 0);
    assert_player(&w, &old);
}

#[test]
fn a_path_out_of_the_folder_is_refused() {
    let w = World::new("u-path");
    for bad in ["../evil.dll", "a/../../evil.dll", "run.bat", "sub/x.exe", "C:evil.dll"] {
        let mut files = player_v1();
        files.push((bad, b"x"));
        urel(1, &files).publish(&w.srv, &w.kp);
        let err = run_unity(&w, World::fast()).unwrap_err();
        assert!(matches!(err, Error::BadManifest(_)), "{bad}: {err:?}");
        assert!(w.unity_read("ChaosUnity.exe").is_none());
        assert!(!w.dir.join("evil.dll").exists() && !w.dir.parent().unwrap().join("evil.dll").exists());
    }
}

#[test]
fn a_manifest_of_the_wrong_client_is_refused() {
    let w = World::new("u-wrong");
    // the main client's manifest at the Unity address
    let main = Release {
        version: 1,
        package: 14,
        files: vec![("Chaos.exe".into(), b"exe".to_vec())],
        launcher: None,
    };
    w.srv
        .set("/updates/unity/manifest.json", main.envelope(&w.kp).into_bytes());
    let err = run_unity(&w, World::fast()).unwrap_err();
    assert!(matches!(err, Error::BadManifest(_)), "{err:?}");
    // the Unity manifest at the main client's address
    let unity = urel(1, &player_v1());
    w.srv
        .set("/updates/live/manifest.json", unity.envelope(&w.kp).into_bytes());
    let err = w.updater(World::fast()).run(&mut |_| {}).unwrap_err();
    assert!(matches!(err, Error::BadManifest(_)), "{err:?}");
    assert!(w.read("Chaos.exe").is_none() && w.read("ChaosUnity.exe").is_none());
}

#[test]
fn the_unity_version_counter_is_its_own() {
    let w = World::new("u-version");
    // the main client is at version 50; the Unity channel starts at 1
    let main = Release {
        version: 50,
        package: 14,
        files: vec![("Chaos.exe".into(), b"exe".to_vec())],
        launcher: None,
    };
    main.publish(&w.srv, &w.kp);
    w.updater(World::fast()).run(&mut |_| {}).unwrap();
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();
    assert_eq!(w.applied_version(), 50);
    // an older Unity manifest is refused like any other
    urel(2, &player_v1()).publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    assert_eq!(
        run_unity(&w, World::fast()),
        Err(Error::OlderManifest { got: 1, have: 2 })
    );
}

#[test]
fn the_choice_updates_the_chosen_client_only() {
    let w = World::new("u-choice");
    let main = Release {
        version: 5,
        package: 14,
        files: vec![("Chaos.exe".into(), b"exe v1".to_vec())],
        launcher: None,
    };
    main.publish(&w.srv, &w.kp);
    let r1 = urel(1, &player_v1());
    r1.publish(&w.srv, &w.kp);

    // Unity chosen: Unity is installed in unity/, the main client is not
    let (o, active) = choice::update(
        &w.cfg,
        Client::Unity,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    )
    .unwrap();
    assert_eq!(o.game, "ChaosUnity.exe");
    assert_eq!(active.dir, w.dir.join("unity"));
    assert_player(&w, &r1);
    assert!(
        w.read("Chaos.exe").is_none(),
        "the main client's files are not installed"
    );
    assert!(!w.dir.join(STATE_DIR).join("state.json").exists());
    assert_eq!(
        config::load_client(&w.dir),
        Client::Main,
        "the update does not save the choice"
    );

    // main chosen: the main client is installed, unity/ is left alone
    w.srv.clear_hits();
    let (o, active) = choice::update(
        &w.cfg,
        Client::Main,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    )
    .unwrap();
    assert_eq!((o.game.as_str(), active.dir.as_path()), ("Chaos.exe", w.dir.as_path()));
    assert_eq!(w.read("Chaos.exe").unwrap(), b"exe v1");
    assert_eq!(w.srv.hits_for("/updates/unity/").len(), 0);
    assert_player(&w, &r1);
}

#[test]
fn a_unity_only_player_still_gets_a_new_launcher() {
    let w = World::new("u-self");
    let main = Release {
        version: 5,
        package: 14,
        files: vec![
            ("Chaos.exe".into(), b"exe v1".to_vec()),
            ("CindersLauncher.exe".into(), b"launcher v1".to_vec()),
        ],
        launcher: Some("CindersLauncher.exe".into()),
    };
    main.publish(&w.srv, &w.kp);
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    w.srv.clear_hits();
    let (o, _) = choice::update(
        &w.cfg,
        Client::Unity,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    )
    .unwrap();
    assert!(!o.launcher_staged, "the outcome is the Unity one");
    assert!(selfupdate::pending(&w.exe).exists(), "the new launcher is staged");
    assert_eq!(selfupdate::staged_sha(&w.exe), Some(sha256_hex(b"launcher v1")));
    assert!(
        w.read("Chaos.exe").is_none(),
        "nothing else of the main client is installed or even downloaded"
    );
    assert_eq!(w.srv.hits_for(&blob_path(&sha256_hex(b"exe v1"))).len(), 0);
    assert_eq!(w.srv.hits_for(&blob_path(&sha256_hex(b"launcher v1"))).len(), 1);
    assert!(
        !w.dir.join(STATE_DIR).join("state.json").exists(),
        "no state of the main client either"
    );
    assert_eq!(selfupdate::apply_pending(&w.exe), Ok(selfupdate::Applied::Swapped));
    assert_eq!(w.read("CindersLauncher.exe").unwrap(), b"launcher v1");

    // a dead main manifest never stops the Unity update
    w.srv.state.lock().unwrap().routes.remove("/updates/live/manifest.json");
    urel(2, &player_v1()).publish(&w.srv, &w.kp);
    let (o, _) = choice::update(
        &w.cfg,
        Client::Unity,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    )
    .unwrap();
    assert_eq!(o.version, 2);
}

fn choose(
    w: &World,
    client: Client,
) -> Result<(cinders_launcher::install::Outcome, cinders_launcher::config::Config), Error> {
    choice::update(
        &w.cfg,
        client,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    )
}

#[test]
fn an_unpublished_unity_channel_says_so_and_the_main_client_works() {
    // O494: the main manifest is there, the Unity one answers 404
    let w = World::new("u-unpublished");
    let main = Release {
        version: 5,
        package: 14,
        files: vec![("Chaos.exe".into(), b"exe v1".to_vec())],
        launcher: None,
    };
    main.publish(&w.srv, &w.kp);
    assert!(!choice::unity_installed(&w.cfg));

    let err = choose(&w, Client::Unity).unwrap_err();
    assert_eq!(err, Error::UnityNotPublished);
    assert!(!err.text(cinders_launcher::i18n::Lang::En).contains("curl"));
    // nothing of Unity on the disk, no state
    assert!(w.unity_read("ChaosUnity.exe").is_none());
    assert!(!w.dir.join("unity").join("ChaosUnity.exe").exists());
    // the box: only the way back to the main client
    let b = choice::buttons(&err, Client::Unity, choice::unity_installed(&w.cfg));
    assert_eq!((b.retry, b.play_anyway, b.use_main), (false, false, true));
    // the way back: the choice is saved as a click on the tab saves it, and the main client updates
    config::save_client(&w.dir, Client::Main).unwrap();
    assert_eq!(config::load_client(&w.dir), Client::Main);
    let (o, _) = choose(&w, Client::Main).unwrap();
    assert_eq!(o.game, "Chaos.exe");
    assert_eq!(w.read("Chaos.exe").unwrap(), b"exe v1");

    // the main client's own 404 is a server answer, not the Unity text and not a network failure
    w.srv.state.lock().unwrap().routes.remove("/updates/live/manifest.json");
    assert_eq!(choose(&w, Client::Main).unwrap_err(), Error::Http(404));

    // once the channel is published the same choice installs
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    let (o, _) = choose(&w, Client::Unity).unwrap();
    assert_eq!(o.game, "ChaosUnity.exe");
    assert!(choice::unity_installed(&w.cfg));
}

#[test]
fn an_unpublished_channel_with_an_installed_unity_tree_keeps_play_anyway() {
    let w = World::new("u-unpublished-installed");
    let r1 = urel(1, &player_v1());
    r1.publish(&w.srv, &w.kp);
    choose(&w, Client::Unity).unwrap();
    assert!(choice::unity_installed(&w.cfg));

    // the channel is taken down later
    w.srv
        .state
        .lock()
        .unwrap()
        .routes
        .remove("/updates/unity/manifest.json");
    let err = choose(&w, Client::Unity).unwrap_err();
    assert_eq!(err, Error::UnityNotPublished);
    assert_player(&w, &r1);
    // the failed fetch left no half-done swap (an empty stage folder is made before the fetch and is harmless)
    let st = w.dir.join("unity").join(STATE_DIR);
    assert!(!st.join("journal.json").exists() && !st.join("backup").exists());
    let b = choice::buttons(&err, Client::Unity, choice::unity_installed(&w.cfg));
    assert_eq!((b.retry, b.play_anyway, b.use_main), (false, true, true));
}

#[test]
fn a_server_down_is_still_a_network_error_for_unity() {
    let w = World::new("u-offline");
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    w.srv.state.lock().unwrap().offline = true;
    assert!(matches!(choose(&w, Client::Unity), Err(Error::Network(_))));
}

#[test]
fn unity_is_not_offered_without_an_address() {
    let mut w = World::new("u-none");
    w.cfg.unity_manifest = None;
    let err = choice::update(
        &w.cfg,
        Client::Unity,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    )
    .unwrap_err();
    assert!(matches!(err, Error::Config(_)), "{err:?}");
    assert!(!w.dir.join("unity").exists());
}

#[test]
fn the_choice_survives_a_restart() {
    let w = World::new("u-saved");
    assert_eq!(config::load_client(&w.dir), Client::Main);
    config::save_client(&w.dir, Client::Unity).unwrap();
    assert_eq!(config::load_client(&w.dir), Client::Unity);
    // the settings file sits in the state folder and is not touched by an update of either client
    urel(1, &player_v1()).publish(&w.srv, &w.kp);
    run_unity(&w, World::fast()).unwrap();
    assert_eq!(config::load_client(&w.dir), Client::Unity);
}

#[test]
fn a_dev_package_is_not_offered_unless_allowed() {
    // O433 phase 17: a Unity package built without the client key says "dev": true; the launcher installs nothing of it for a
    // player, and says why; the tester's switch (Options::allow_dev, the flag --allow-dev-unity) installs it
    let w = World::new("u-dev");
    let mut r1 = urel(1, &player_v1());
    r1.dev = Some(true);
    r1.publish(&w.srv, &w.kp);
    let err = run_unity(&w, World::fast()).unwrap_err();
    assert!(matches!(err, Error::DevPackage), "{err:?}");
    assert!(
        w.unity_read("ChaosUnity.exe").is_none(),
        "nothing of a dev package is installed"
    );
    assert!(
        !w.dir.join("unity").join(STATE_DIR).join("state.json").exists(),
        "no state saved for a refused package"
    );
    assert!(err.text(cinders_launcher::i18n::Lang::En).contains("development build"));
    assert!(err.text(cinders_launcher::i18n::Lang::Pt).contains("desenvolvimento"));
    // through the choice, the way the window and --cli call it
    let via_choice = choice::update(
        &w.cfg,
        Client::Unity,
        w.exe.clone(),
        &cinders_launcher::net::Curl,
        World::fast(),
        &mut |_| {},
    );
    assert!(matches!(via_choice, Err(Error::DevPackage)));
    // a tester allows it
    let opts = Options {
        allow_dev: true,
        ..World::fast()
    };
    run_unity(&w, opts).unwrap();
    assert_player(&w, &r1);
    assert_unity_clean(&w);
}

#[test]
fn a_keyed_package_is_installed_with_dev_false_or_absent() {
    for (name, dev) in [("u-keyed-false", Some(false)), ("u-keyed-absent", None)] {
        let w = World::new(name);
        let mut r1 = urel(1, &player_v1());
        r1.dev = dev;
        r1.publish(&w.srv, &w.kp);
        run_unity(&w, World::fast()).unwrap();
        assert_player(&w, &r1);
    }
}
