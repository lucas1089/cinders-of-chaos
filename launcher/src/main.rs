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
mod theme;

#[cfg(feature = "gui")]
mod gui {
    use super::*;
    use cinders_launcher::feed::{self, Panel};
    use cinders_launcher::i18n::{feed_text, FeedText};
    use cinders_launcher::install::Outcome;
    use eframe::egui;
    use std::sync::mpsc::{channel, Receiver, Sender};

    enum Msg {
        Ev(Event),
        Done(Result<Outcome, Error>),
    }

    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Tab {
        News,
        Changelog,
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
        panel: Panel,
        tab: Tab,
        feed_rx: Option<Receiver<Panel>>,
        banner: egui::TextureHandle,
    }

    impl App {
        fn new(cfg: Config, exe: PathBuf, lang: Lang, ctx: &egui::Context) -> App {
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
                panel: Panel::Loading,
                tab: Tab::News,
                feed_rx: None,
                banner: theme::banner(ctx),
            };
            app.start_feed();
            app.start();
            app
        }

        /// News and Changelog: fetched on a thread of their own, after and apart from the update. A slow or dead feed
        /// never holds the update, the Play button or the window.
        fn start_feed(&mut self) {
            if self.cfg.feed.is_none() {
                self.panel = Panel::Unavailable;
                return;
            }
            let (tx, rx) = channel();
            self.feed_rx = Some(rx);
            let (cfg, lang) = (self.cfg.clone(), self.lang);
            std::thread::spawn(move || {
                let _ = tx.send(feed::load(&Curl, &cfg, lang));
            });
        }

        fn feed_ui(&mut self, ui: &mut egui::Ui) {
            let lang = self.lang;
            ui.horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 4.0;
                if theme::tab(ui, self.tab == Tab::News, feed_text(FeedText::TabNews, lang)).clicked() {
                    self.tab = Tab::News;
                }
                if theme::tab(ui, self.tab == Tab::Changelog, feed_text(FeedText::TabChangelog, lang)).clicked() {
                    self.tab = Tab::Changelog;
                }
            });
            let left = ui.max_rect().left();
            let right = ui.max_rect().right();
            let y = ui.cursor().top();
            ui.painter().line_segment(
                [egui::pos2(left, y), egui::pos2(right, y)],
                egui::Stroke::new(1.0_f32, theme::CARD_EDGE),
            );
            ui.add_space(6.0);
            let mut open: Option<String> = None;
            egui::ScrollArea::vertical()
                .auto_shrink([false, false])
                .show(ui, |ui| match &self.panel {
                    Panel::Loading => {
                        ui.add_space(4.0);
                        ui.horizontal(|ui| {
                            ui.add(egui::Spinner::new().color(theme::EMBER));
                            ui.colored_label(theme::MUTED, feed_text(FeedText::Loading, lang));
                        });
                    }
                    Panel::Unavailable => {
                        ui.add_space(4.0);
                        ui.colored_label(theme::MUTED, feed_text(FeedText::Unavailable, lang));
                    }
                    Panel::Ready { feed, cached } => {
                        if *cached {
                            ui.colored_label(theme::MUTED, feed_text(FeedText::SavedCopy, lang));
                        }
                        // feed text is shown as plain text, never parsed
                        let link = |ui: &mut egui::Ui, url: &Option<String>, open: &mut Option<String>| {
                            if let Some(u) = url {
                                if ui.link(feed_text(FeedText::ReadMore, lang)).clicked() {
                                    *open = Some(u.clone());
                                }
                            }
                        };
                        let head = |ui: &mut egui::Ui, title: &str, date: &str| {
                            ui.horizontal_wrapped(|ui| {
                                ui.label(theme::card_title(title));
                                ui.label(egui::RichText::new(date).small().color(theme::MUTED));
                            });
                        };
                        match self.tab {
                            Tab::News if feed.news.is_empty() => {
                                ui.colored_label(theme::MUTED, feed_text(FeedText::NoNews, lang));
                            }
                            Tab::News => {
                                for n in &feed.news {
                                    theme::card(theme::CARD, theme::CARD_EDGE).show(ui, |ui| {
                                        ui.set_width(ui.available_width());
                                        head(ui, &n.title, &feed::show_date(&n.date, lang));
                                        if !n.text.is_empty() {
                                            ui.label(&n.text);
                                        }
                                        link(ui, &n.url, &mut open);
                                    });
                                }
                            }
                            Tab::Changelog if feed.changelog.is_empty() => {
                                ui.colored_label(theme::MUTED, feed_text(FeedText::NoChanges, lang));
                            }
                            Tab::Changelog => {
                                for e in &feed.changelog {
                                    theme::card(theme::CARD, theme::CARD_EDGE).show(ui, |ui| {
                                        ui.set_width(ui.available_width());
                                        head(ui, &e.title, &feed::show_date(&e.date, lang));
                                        for l in &e.lines {
                                            ui.horizontal_top(|ui| {
                                                ui.spacing_mut().item_spacing.x = 8.0;
                                                ui.colored_label(theme::EMBER, "\u{25C6}");
                                                ui.add(egui::Label::new(l).wrap());
                                            });
                                        }
                                        link(ui, &e.url, &mut open);
                                    });
                                }
                            }
                        }
                    }
                });
            // checked again here: only an https link leaves the launcher
            if let Some(u) = open.and_then(|u| feed::safe_link(&u)) {
                ui.ctx().open_url(egui::OpenUrl::new_tab(u));
            }
        }

        /// Home page of the game's site: the origin of the feed address, when it passes the link rules.
        fn site_link(&self) -> Option<String> {
            let f = self.cfg.feed.as_deref()?;
            let rest = f.strip_prefix("https://")?;
            let end = rest.find('/').unwrap_or(rest.len());
            feed::safe_link(&format!("https://{}", &rest[..end]))
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
            if let Some(rx) = &self.feed_rx {
                if let Ok(p) = rx.try_recv() {
                    self.panel = p;
                    self.feed_rx = None;
                }
            }
            let lang = self.lang;
            let mut play: Option<String> = None;
            let mut retry = false;
            egui::TopBottomPanel::bottom("footer")
                .frame(
                    egui::Frame::none()
                        .fill(theme::BG)
                        .inner_margin(egui::Margin::symmetric(18.0, 8.0)),
                )
                .show(ctx, |ui| {
                    ui.horizontal(|ui| {
                        ui.label(
                            egui::RichText::new(format!("v{}", env!("CARGO_PKG_VERSION")))
                                .small()
                                .color(theme::MUTED),
                        );
                        if let Some(site) = self.site_link() {
                            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                                if ui.link(egui::RichText::new(i18n::website(lang)).small()).clicked() {
                                    ui.ctx().open_url(egui::OpenUrl::new_tab(site));
                                }
                            });
                        }
                    });
                });
            egui::CentralPanel::default()
                .frame(
                    egui::Frame::none()
                        .fill(theme::BG)
                        .inner_margin(egui::Margin::symmetric(18.0, 0.0)),
                )
                .show(ctx, |ui| {
                    // hero banner: as wide as fits, never taller than 200 px; its edges fade into the window colour
                    let w = ui.available_width().min(640.0);
                    let size = egui::vec2(w, w * theme::BANNER_SIZE[1] as f32 / theme::BANNER_SIZE[0] as f32);
                    ui.vertical_centered(|ui| {
                        ui.image((self.banner.id(), size));
                    });
                    ui.add_space(-6.0);
                    let busy = matches!(self.phase, Phase::Working);
                    let failed = matches!(self.phase, Phase::Failed(_));
                    let (fill, edge) = if failed {
                        (egui::Color32::from_rgb(40, 18, 16), theme::ERROR)
                    } else {
                        (theme::CARD, theme::CARD_EDGE)
                    };
                    theme::card(fill, edge).show(ui, |ui| {
                        ui.set_width(ui.available_width());
                        ui.horizontal(|ui| {
                            let btn = egui::vec2(170.0, 56.0);
                            let reserve = if failed {
                                0.0
                            } else {
                                btn.x + ui.spacing().item_spacing.x
                            };
                            let left = (ui.available_width() - reserve).max(120.0);
                            ui.allocate_ui_with_layout(
                                egui::vec2(left, btn.y),
                                egui::Layout::top_down(egui::Align::Min),
                                |ui| {
                                    ui.set_width(left);
                                    ui.add_space(match self.phase {
                                        Phase::Working => 2.0,
                                        Phase::Ready(_) => 16.0,
                                        Phase::Failed(_) => 0.0,
                                    });
                                    match &self.phase {
                                        Phase::Working => {
                                            ui.label(egui::RichText::new(&self.status).size(16.0).color(theme::GOLD));
                                            if self.total > 0 {
                                                let frac = self.done as f32 / self.total as f32;
                                                ui.add(
                                                    egui::ProgressBar::new(frac.clamp(0.0, 1.0))
                                                        .fill(theme::EMBER)
                                                        .rounding(7.0)
                                                        .desired_height(16.0)
                                                        .text(
                                                            egui::RichText::new(format!(
                                                                "{} / {} MB  {}",
                                                                self.done / 1_000_000,
                                                                self.total / 1_000_000,
                                                                self.file
                                                            ))
                                                            .small()
                                                            .color(egui::Color32::WHITE),
                                                        ),
                                                );
                                            } else {
                                                ui.add(egui::Spinner::new().color(theme::EMBER));
                                            }
                                            ctx.request_repaint_after(std::time::Duration::from_millis(100));
                                        }
                                        Phase::Ready(_) => {
                                            ui.label(egui::RichText::new(&self.status).size(16.0).color(theme::GOLD));
                                        }
                                        Phase::Failed(e) => {
                                            ui.label(egui::RichText::new(e.text(lang)).color(theme::ERROR));
                                            ui.horizontal_wrapped(|ui| {
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
                                },
                            );
                            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                                // the Play button always has its place; cold while the update runs, absent after an error
                                if !failed && theme::play_button(ui, i18n::play(lang), !busy, btn) {
                                    if let Phase::Ready(o) = &self.phase {
                                        play = Some(o.game.clone());
                                    }
                                }
                            });
                        });
                    });
                    if let Some(e) = &self.launch_error {
                        ui.add_space(8.0);
                        ui.colored_label(theme::ERROR, e.text(lang));
                    }
                    ui.add_space(12.0);
                    self.feed_ui(ui);
                });
            if self.feed_rx.is_some() {
                ctx.request_repaint_after(std::time::Duration::from_millis(200));
            }
            if retry {
                self.launch_error = None;
                if !matches!(self.panel, Panel::Ready { cached: false, .. }) {
                    self.start_feed();
                }
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
                .with_inner_size([760.0, 700.0])
                .with_min_inner_size([600.0, 560.0])
                .with_icon(theme::icon())
                .with_title(i18n::title(lang)),
            ..Default::default()
        };
        eframe::run_native(
            i18n::title(lang),
            opts,
            Box::new(move |cc| {
                theme::apply(&cc.egui_ctx);
                Ok(Box::new(App::new(cfg, exe, lang, &cc.egui_ctx)))
            }),
        )
    }

    pub fn fatal(e: &Error, lang: Lang) -> eframe::Result<()> {
        struct Fatal(String);
        impl eframe::App for Fatal {
            fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
                egui::CentralPanel::default().show(ctx, |ui| {
                    ui.colored_label(theme::ERROR, &self.0);
                });
            }
        }
        let text = e.text(lang);
        let opts = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default()
                .with_inner_size([520.0, 160.0])
                .with_icon(theme::icon())
                .with_title(i18n::title(lang)),
            ..Default::default()
        };
        eframe::run_native(
            i18n::title(lang),
            opts,
            Box::new(move |cc| {
                theme::apply(&cc.egui_ctx);
                Ok(Box::new(Fatal(text)))
            }),
        )
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
