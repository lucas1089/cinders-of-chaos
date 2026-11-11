//! The client choice (ROADMAP O433 phase 16): "Main client" or "Unity client (beta)". One entry point updates the chosen
//! client with the same `Updater` (same signed manifest, same key, same hash checks, same journaled swap) and says
//! which config to start it with.
use crate::config::{Client, Config};
use crate::i18n::Error;
use crate::install::{Event, Options, Outcome, Updater};
use crate::net::Fetch;
use std::path::PathBuf;

/// The config the chosen client runs with: `cfg` itself for the main client, the Unity one (`Config::for_client`)
/// otherwise. A Unity choice without a Unity manifest address is a config error, never a silent fall back.
pub fn active_config(cfg: &Config, client: Client) -> Result<Config, Error> {
    cfg.for_client(client)
        .ok_or_else(|| Error::Config("no Unity client address (unity_manifest)".into()))
}

/// Updates the chosen client. For Unity the Unity manifest is applied into `<install>/unity/`; then, best effort and
/// without a word when it fails, the main manifest is read for the launcher's own file only, so a player who only uses
/// the Unity client still gets a new launcher. Returns the outcome and the config to start the game with.
pub fn update(
    cfg: &Config,
    client: Client,
    exe: PathBuf,
    fetch: &dyn Fetch,
    opts: Options,
    ev: &mut dyn FnMut(Event),
) -> Result<(Outcome, Config), Error> {
    let active = active_config(cfg, client)?;
    let outcome = Updater {
        cfg: &active,
        fetch,
        exe: exe.clone(),
        opts: opts.clone(),
    }
    .run(ev)?;
    if client == Client::Unity {
        let own = Options {
            launcher_only: true,
            ..opts
        };
        let _ = Updater {
            cfg,
            fetch,
            exe,
            opts: own,
        }
        .run(&mut |_| {});
    }
    Ok((outcome, active))
}

/// True when a Unity client is on the disk: its player program is in `unity/`.
pub fn unity_installed(cfg: &Config) -> bool {
    cfg.dir.join(crate::config::UNITY_DIR).join(&cfg.unity_game).is_file()
}

/// The buttons of the error box (O494).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Buttons {
    /// "Try again".
    pub retry: bool,
    /// "Play anyway".
    pub play_anyway: bool,
    /// "Use the main client": switches the choice back to the main client (saved, as a click on the tab does).
    pub use_main: bool,
}

/// Which buttons an error box shows. A Unity channel that was never published offers only the way back to the main
/// client (a retry would give the same answer) and "Play anyway" only when a Unity install exists. Every other error
/// keeps "Try again" and "Play anyway", except that a half-restored install (`Rollback`) is repaired by the next run
/// and never started, and a settings error has nothing to start.
pub fn buttons(e: &Error, client: Client, unity_installed: bool) -> Buttons {
    match e {
        Error::UnityNotPublished => Buttons {
            retry: false,
            play_anyway: unity_installed,
            use_main: client == Client::Unity,
        },
        Error::Rollback(_) | Error::Config(_) => Buttons {
            retry: true,
            play_anyway: false,
            use_main: false,
        },
        _ => Buttons {
            retry: true,
            play_anyway: true,
            use_main: false,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const B: fn(bool, bool, bool) -> Buttons = |retry, play_anyway, use_main| Buttons {
        retry,
        play_anyway,
        use_main,
    };

    #[test]
    fn not_published_offers_the_main_client_only() {
        let e = Error::UnityNotPublished;
        assert_eq!(buttons(&e, Client::Unity, false), B(false, false, true));
        // a Unity install exists: Play anyway stays
        assert_eq!(buttons(&e, Client::Unity, true), B(false, true, true));
    }

    #[test]
    fn other_errors_keep_the_old_buttons() {
        for client in [Client::Main, Client::Unity] {
            for inst in [false, true] {
                for e in [
                    Error::Network("x".into()),
                    Error::Http(404),
                    Error::BadSignature,
                    Error::DevPackage,
                    Error::Io("x".into()),
                ] {
                    assert_eq!(buttons(&e, client, inst), B(true, true, false), "{e:?}");
                }
                for e in [Error::Rollback("x".into()), Error::Config("x".into())] {
                    assert_eq!(buttons(&e, client, inst), B(true, false, false), "{e:?}");
                }
            }
        }
    }

    #[test]
    fn unity_install_is_the_player_program_in_unity_dir() {
        let dir = std::env::temp_dir().join(format!("cinders-choice-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join(crate::config::UNITY_DIR)).unwrap();
        let cfg = Config {
            manifest_url: "https://x.test/updates/live/manifest.json".into(),
            public_key: [0; 32],
            baseline: 0,
            game: "Chaos.exe".into(),
            args: vec![],
            feed: None,
            dir: dir.clone(),
            unity_manifest: Some("https://x.test/updates/unity/manifest.json".into()),
            unity_game: "ChaosUnity.exe".into(),
            layout: crate::manifest::Layout::Flat,
        };
        assert!(!unity_installed(&cfg));
        // the main client's program one folder up does not count
        std::fs::write(dir.join("ChaosUnity.exe"), b"x").unwrap();
        assert!(!unity_installed(&cfg));
        std::fs::write(dir.join(crate::config::UNITY_DIR).join("ChaosUnity.exe"), b"x").unwrap();
        assert!(unity_installed(&cfg));
        let _ = std::fs::remove_dir_all(&dir);
    }
}
