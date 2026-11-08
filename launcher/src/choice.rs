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
