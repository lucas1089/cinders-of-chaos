//! Cinders of Chaos launcher: the window (or `--cli`). Logic is in the library.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
use cinders_launcher::config::{self, Client, Config};
use cinders_launcher::i18n::{self, Lang, Status};
use cinders_launcher::install::{Event, Options};
use cinders_launcher::net::Curl;
use cinders_launcher::{choice, launch, selfupdate, setup};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};

/// `--allow-dev-unity` (or CINDERS_ALLOW_DEV_UNITY=1): install a DEV Unity package, one built without the client key. For testers;
/// players never get one offered (O433 phase 17).
static ALLOW_DEV_UNITY: AtomicBool = AtomicBool::new(false);

/// `--verify`: hash every file again (no cache) and repair what is damaged (the settings card's "Verify files").
static VERIFY: AtomicBool = AtomicBool::new(false);

fn update_options() -> Options {
    Options {
        allow_dev: ALLOW_DEV_UNITY.load(Ordering::Relaxed),
        verify: VERIFY.load(Ordering::Relaxed),
        ..Options::default()
    }
}

struct Args {
    cli: bool,
    no_start: bool,
    uninstall: bool,
    play_local: bool,
    build: Option<u64>,
    dir: Option<PathBuf>,
    lang: Option<Lang>,
    client: Option<Client>,
    rest: Vec<String>,
}

fn parse_args() -> Args {
    let mut a = Args {
        cli: false,
        no_start: false,
        uninstall: false,
        play_local: false,
        build: None,
        dir: None,
        lang: None,
        client: None,
        rest: Vec::new(),
    };
    if std::env::var("CINDERS_ALLOW_DEV_UNITY").as_deref() == Ok("1") {
        ALLOW_DEV_UNITY.store(true, Ordering::Relaxed);
    }
    let mut it = std::env::args().skip(1);
    while let Some(x) = it.next() {
        match x.as_str() {
            "--cli" => a.cli = true,
            "--no-start" => a.no_start = true,
            "--uninstall" => a.uninstall = true,
            // start the game with no update and no network (the one-PC package's start-client.bat); `--build N` names the
            // client build, else `chaos_build.txt` beside the game, else the build the last update saved
            "--play-local" => a.play_local = true,
            "--build" => a.build = it.next().and_then(|t| t.trim().parse().ok()),
            // the game starts the launcher with it ("open the game from the launcher"): nothing else to do
            "--play" => {}
            // the setup program starts the installed copy with it; nothing else to do, the update runs as always
            "--first-run" => {}
            "--verify" => VERIFY.store(true, Ordering::Relaxed),
            "--allow-dev-unity" => ALLOW_DEV_UNITY.store(true, Ordering::Relaxed),
            "--dir" => a.dir = it.next().map(PathBuf::from),
            "--lang" => a.lang = it.next().map(|t| Lang::from_tag(&t)),
            "--client" => {
                a.client = it.next().and_then(|t| Client::from_tag(&t));
                if a.client.is_none() {
                    eprintln!("--client main|unity");
                    std::process::exit(2);
                }
            }
            "--help" | "-h" => {
                println!("cinders-launcher [--cli] [--no-start] [--dir FOLDER] [--lang pt|en] [--client main|unity] [--allow-dev-unity] [--verify]");
                std::process::exit(0);
            }
            _ => a.rest.push(x),
        }
    }
    a
}

/// A new launcher staged by an earlier run takes over now: swap, start it, leave.
fn take_over(exe: &std::path::Path) {
    if std::env::var_os(selfupdate::RESTARTED_ENV).is_some() {
        return;
    }
    if let Ok(selfupdate::Applied::Swapped) = selfupdate::apply_pending(exe) {
        let args: Vec<String> = std::env::args().skip(1).collect();
        let started = std::process::Command::new(exe)
            .args(args)
            .env(selfupdate::RESTARTED_ENV, "1")
            .spawn()
            .is_ok();
        if started {
            std::process::exit(0);
        }
    }
}

/// The client to use: the one given with `--client`, else the player's saved choice (the main client when it is not
/// offered any more or nothing was saved).
fn pick_client(cfg: &Config, given: Option<Client>) -> Client {
    match given {
        Some(c) => c,
        None => match config::load_client(&cfg.dir) {
            Client::Unity if cfg.unity_manifest.is_none() => Client::Main,
            c => c,
        },
    }
}

/// `--play-local`: starts the game of this folder with a start ticket and nothing else (no manifest, no update, no network).
/// It needs no `launcher.json`: the one-PC test package has none. The build comes from `--build`, `chaos_build.txt` or the
/// last update's state; with none of them there is no ticket and the game says so itself.
fn play_local(dir: &std::path::Path, build: Option<u64>, lang: Lang) -> i32 {
    let build = build
        .or_else(|| {
            std::fs::read_to_string(dir.join("chaos_build.txt"))
                .ok()
                .and_then(|t| t.trim().parse().ok())
        })
        .or_else(|| cinders_launcher::install::saved_package(dir));
    let cfg = Config::bare(dir);
    let ticket = build.and_then(cinders_launcher::ticket::for_launch);
    match launch::start(&cfg, &cfg.game, ticket.as_deref()) {
        Ok(()) => 0,
        Err(e) => {
            eprintln!("{}", e.text(lang));
            1
        }
    }
}

/// `--uninstall` (the entry of Windows' "Apps" list): asks once, then removes what the launcher owns.
fn uninstall(dir: &std::path::Path, exe: &std::path::Path, lang: Lang) -> i32 {
    #[cfg(windows)]
    if !cinders_launcher::winshell::confirm_uninstall(
        i18n::setup_text(i18n::SetupText::UninstallTitle, lang),
        i18n::setup_text(i18n::SetupText::UninstallAsk, lang),
    ) {
        return 0;
    }
    #[cfg(not(windows))]
    let _ = lang;
    let removed = setup::uninstall(dir, exe, &setup::SYSTEM, &setup::SYSTEM);
    println!("removed {} item(s)", removed.len());
    0
}

fn run_cli(cfg: &Config, exe: PathBuf, lang: Lang, no_start: bool, client: Client) -> i32 {
    let active = match choice::active_config(cfg, client) {
        Ok(a) => a,
        Err(e) => {
            eprintln!("{}", e.text(lang));
            return 1;
        }
    };
    let r = choice::update(cfg, client, exe, &Curl, update_options(), &mut |e| {
        if let Event::Status(s) = e {
            println!("{}", i18n::status(s, lang));
        }
    });
    let game = match &r {
        Ok((o, _)) => o.game.clone(),
        Err(e) => {
            eprintln!("{}", e.text(lang));
            active.game.clone()
        }
    };
    let code = if r.is_ok() { 0 } else { 1 };
    // after an error the game starts only where the window would offer "Play anyway" (never the main client in place
    // of an unpublished Unity one)
    let may_start = match &r {
        Ok(_) => true,
        Err(e) => choice::buttons(e, client, choice::unity_installed(cfg)).play_anyway,
    };
    if !no_start && may_start {
        println!("{}", i18n::status(Status::Launching, lang));
        // the main client wants a start ticket (O552 phase D); the Unity client is exempt for now
        let package = r.as_ref().ok().and_then(|(o, _)| o.package);
        let ticket = (client == Client::Main)
            .then(|| launch::ticket_for(&active, package))
            .flatten();
        if let Err(e) = launch::start(&active, &game, ticket.as_deref()) {
            eprintln!("{}", e.text(lang));
            return 1;
        }
    }
    code
}

#[cfg(feature = "gui")]
mod setup_ui;
#[cfg(feature = "gui")]
mod theme;
#[cfg(feature = "gui")]
mod ui;

fn main() {
    let args = parse_args();
    let lang = args.lang.unwrap_or_else(|| Lang::detect(|k| std::env::var(k).ok()));
    let exe = std::env::current_exe().unwrap_or_else(|_| PathBuf::from("cinders-launcher"));
    take_over(&exe);
    let dir = args
        .dir
        .clone()
        .or_else(|| exe.parent().map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("."));
    if args.play_local {
        std::process::exit(play_local(&dir, args.build, lang));
    }
    if args.uninstall {
        std::process::exit(uninstall(&dir, &exe, lang));
    }
    // no launcher.json beside the program but the facts built in: the setup screen (O552 phase C)
    #[cfg(feature = "gui")]
    if !args.cli && args.dir.is_none() && setup::mode(&dir, setup::EMBEDDED) == setup::Mode::Setup {
        if let Err(e) = setup_ui::run(lang, exe) {
            eprintln!("{e}");
            std::process::exit(1);
        }
        return;
    }
    let cfg = match config::load(&dir) {
        Ok(mut c) => {
            c.args.extend(args.rest.clone());
            c
        }
        Err(e) => {
            #[cfg(feature = "gui")]
            if !args.cli {
                let _ = ui::fatal(&e, lang);
                std::process::exit(1);
            }
            eprintln!("{}", e.text(lang));
            std::process::exit(1);
        }
    };
    let client = pick_client(&cfg, args.client);
    #[cfg(feature = "gui")]
    if !args.cli {
        if let Err(e) = ui::run(cfg, client, exe, lang) {
            eprintln!("{e}");
            std::process::exit(1);
        }
        return;
    }
    std::process::exit(run_cli(&cfg, exe, lang, args.no_start, client));
}
