//! Cinders of Chaos launcher: the window (or `--cli`). Logic is in the library.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
use cinders_launcher::config::{self, Config};
use cinders_launcher::i18n::{self, Error, Lang, Status};
use cinders_launcher::install::{Event, Options, Updater};
use cinders_launcher::net::Curl;
use cinders_launcher::{launch, selfupdate};
use std::path::PathBuf;

struct Args {
    cli: bool,
    no_start: bool,
    dir: Option<PathBuf>,
    lang: Option<Lang>,
    rest: Vec<String>,
}

fn parse_args() -> Args {
    let mut a = Args {
        cli: false,
        no_start: false,
        dir: None,
        lang: None,
        rest: Vec::new(),
    };
    let mut it = std::env::args().skip(1);
    while let Some(x) = it.next() {
        match x.as_str() {
            "--cli" => a.cli = true,
            "--no-start" => a.no_start = true,
            "--dir" => a.dir = it.next().map(PathBuf::from),
            "--lang" => a.lang = it.next().map(|t| Lang::from_tag(&t)),
            "--help" | "-h" => {
                println!("cinders-launcher [--cli] [--no-start] [--dir FOLDER] [--lang pt|en]");
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

fn updater<'a>(cfg: &'a Config, exe: PathBuf) -> Updater<'a> {
    Updater {
        cfg,
        fetch: &Curl,
        exe,
        opts: Options::default(),
    }
}

fn run_cli(cfg: &Config, exe: PathBuf, lang: Lang, no_start: bool) -> i32 {
    let r = updater(cfg, exe).run(&mut |e| {
        if let Event::Status(s) = e {
            println!("{}", i18n::status(s, lang));
        }
    });
    let game = match &r {
        Ok(o) => o.game.clone(),
        Err(e) => {
            eprintln!("{}", e.text(lang));
            cfg.game.clone()
        }
    };
    let code = if r.is_ok() { 0 } else { 1 };
    if !no_start && !matches!(r, Err(Error::Rollback(_))) {
        println!("{}", i18n::status(Status::Launching, lang));
        if let Err(e) = launch::start(cfg, &game) {
            eprintln!("{}", e.text(lang));
            return 1;
        }
    }
    code
}

#[cfg(feature = "gui")]
mod gui {
    use super::*;
    use cinders_launcher::install::Outcome;
    use eframe::egui;
    use std::sync::mpsc::{channel, Receiver, Sender};

    enum Msg {
        Ev(Event),
        Done(Result<Outcome, Error>),
    }

    enum Phase {
        Working,
        Ready(Outcome),
        Failed(Error),
    }

    struct App {
        cfg: Config,
        exe: PathBuf,
        lang: Lang,
        phase: Phase,
        status: String,
        file: String,
        done: u64,
        total: u64,
        launch_error: Option<Error>,
        tx: Sender<Msg>,
        rx: Receiver<Msg>,
    }

    impl App {
        fn new(cfg: Config, exe: PathBuf, lang: Lang) -> App {
            let (tx, rx) = channel();
            let mut app = App {
                cfg,
                exe,
                lang,
                phase: Phase::Working,
                status: String::new(),
                file: String::new(),
                done: 0,
                total: 0,
                launch_error: None,
                tx,
                rx,
            };
            app.start();
            app
        }

        fn start(&mut self) {
            self.phase = Phase::Working;
            self.status = i18n::status(Status::Checking, self.lang).into();
            self.file.clear();
            (self.done, self.total) = (0, 0);
            let (cfg, exe, tx) = (self.cfg.clone(), self.exe.clone(), self.tx.clone());
            std::thread::spawn(move || {
                let up = updater(&cfg, exe);
                let r = up.run(&mut |e| {
                    let _ = tx.send(Msg::Ev(e));
                });
                let _ = tx.send(Msg::Done(r));
            });
        }

        fn play(&mut self, ctx: &egui::Context, game: &str) {
            match launch::start(&self.cfg, game) {
                Ok(()) => ctx.send_viewport_cmd(egui::ViewportCommand::Close),
                Err(e) => self.launch_error = Some(e),
            }
        }
    }

    impl eframe::App for App {
        fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
            while let Ok(m) = self.rx.try_recv() {
                match m {
                    Msg::Ev(Event::Status(s)) => self.status = i18n::status(s, self.lang).into(),
                    Msg::Ev(Event::Progress { done, total }) => (self.done, self.total) = (done, total),
                    Msg::Ev(Event::File(f)) => self.file = f,
                    Msg::Done(Ok(o)) => self.phase = Phase::Ready(o),
                    Msg::Done(Err(e)) => self.phase = Phase::Failed(e),
                }
            }
            let lang = self.lang;
            let mut play: Option<String> = None;
            let mut retry = false;
            egui::CentralPanel::default().show(ctx, |ui| {
                ui.add_space(8.0);
                ui.heading("Cinders of Chaos");
                ui.add_space(12.0);
                match &self.phase {
                    Phase::Working => {
                        ui.label(&self.status);
                        if self.total > 0 {
                            let frac = self.done as f32 / self.total as f32;
                            ui.add(egui::ProgressBar::new(frac.clamp(0.0, 1.0)).text(format!(
                                "{} / {} MB  {}",
                                self.done / 1_000_000,
                                self.total / 1_000_000,
                                self.file
                            )));
                        } else {
                            ui.add(egui::Spinner::new());
                        }
                        ctx.request_repaint_after(std::time::Duration::from_millis(100));
                    }
                    Phase::Ready(o) => {
                        ui.label(&self.status);
                        ui.add_space(12.0);
                        if ui
                            .add_sized(
                                [160.0, 40.0],
                                egui::Button::new(egui::RichText::new(i18n::play(lang)).size(20.0)),
                            )
                            .clicked()
                        {
                            play = Some(o.game.clone());
                        }
                    }
                    Phase::Failed(e) => {
                        ui.colored_label(egui::Color32::from_rgb(230, 90, 80), e.text(lang));
                        ui.add_space(12.0);
                        ui.horizontal(|ui| {
                            if ui.button(i18n::retry(lang)).clicked() {
                                retry = true;
                            }
                            // a half-restored install is repaired by the next run, never started
                            if !matches!(e, Error::Rollback(_) | Error::Config(_))
                                && ui.button(i18n::play_anyway(lang)).clicked()
                            {
                                play = Some(self.cfg.game.clone());
                            }
                        });
                    }
                }
                if let Some(e) = &self.launch_error {
                    ui.add_space(8.0);
                    ui.colored_label(egui::Color32::from_rgb(230, 90, 80), e.text(lang));
                }
            });
            if retry {
                self.launch_error = None;
                self.start();
            }
            if let Some(g) = play {
                self.play(ctx, &g);
            }
        }
    }

    pub fn run(cfg: Config, exe: PathBuf, lang: Lang) -> eframe::Result<()> {
        let opts = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([520.0, 240.0])
                .with_resizable(false)
                .with_title(i18n::title(lang)),
            ..Default::default()
        };
        eframe::run_native(
            i18n::title(lang),
            opts,
            Box::new(move |_cc| Ok(Box::new(App::new(cfg, exe, lang)))),
        )
    }

    pub fn fatal(e: &Error, lang: Lang) -> eframe::Result<()> {
        struct Fatal(String);
        impl eframe::App for Fatal {
            fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
                egui::CentralPanel::default().show(ctx, |ui| {
                    ui.colored_label(egui::Color32::from_rgb(230, 90, 80), &self.0);
                });
            }
        }
        let text = e.text(lang);
        let opts = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([520.0, 160.0])
                .with_title(i18n::title(lang)),
            ..Default::default()
        };
        eframe::run_native(i18n::title(lang), opts, Box::new(move |_| Ok(Box::new(Fatal(text)))))
    }
}

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
    let cfg = match config::load(&dir) {
        Ok(mut c) => {
            c.args.extend(args.rest.clone());
            c
        }
        Err(e) => {
            #[cfg(feature = "gui")]
            if !args.cli {
                let _ = gui::fatal(&e, lang);
                std::process::exit(1);
            }
            eprintln!("{}", e.text(lang));
            std::process::exit(1);
        }
    };
    #[cfg(feature = "gui")]
    if !args.cli {
        if let Err(e) = gui::run(cfg, exe, lang) {
            eprintln!("{e}");
            std::process::exit(1);
        }
        return;
    }
    std::process::exit(run_cli(&cfg, exe, lang, args.no_start));
}
