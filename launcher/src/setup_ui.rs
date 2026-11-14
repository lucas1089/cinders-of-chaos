//! The setup screen (O552 phase C): the same look as the launcher window, one card with the folder, the size, the two
//! shortcuts and the Install button. The logic is `setup.rs`; this file only draws it and starts the installed copy.
use crate::theme::{self, Art, Cv};
use cinders_launcher::config;
use cinders_launcher::fmt;
use cinders_launcher::i18n::{self, Error, Lang, SetupText, Ui};
use cinders_launcher::layout::{self, R};
use cinders_launcher::net::Curl;
use cinders_launcher::setup::{self, Choices, Dir, DirRefuse, DirWarn, Shell};
use eframe::egui::{self, Align2, Color32, Pos2, Rect, Rounding, Sense, Stroke, Vec2};
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver};

struct SetupApp {
    lang: Lang,
    exe: PathBuf,
    path: String,
    choices: Choices,
    art: Art,
    /// The size of the install, asked from the signed manifest on a thread of its own.
    size: Option<Result<Option<u64>, Error>>,
    size_rx: Option<Receiver<Result<Option<u64>, Error>>>,
    error: Option<String>,
    working: bool,
    done_rx: Option<Receiver<Result<setup::Installed, Error>>>,
}

fn small_btn(ui: &egui::Ui, art: &Art, cv: Cv, rect: Rect, label: &str, id: &str, on: bool) -> bool {
    let p = ui.painter();
    let resp = ui.interact(
        rect,
        egui::Id::new(id),
        if on { Sense::click() } else { Sense::hover() },
    );
    let tint = if !on {
        Color32::from_gray(120)
    } else if resp.hovered() {
        Color32::from_rgb(255, 235, 215)
    } else {
        Color32::WHITE
    };
    theme::nine(p, &art.btn, rect, 12.0, cv.px(0.6), tint);
    p.text(
        rect.center(),
        Align2::CENTER_CENTER,
        label,
        cv.font(14.5),
        if on { theme::TEXT } else { theme::MUTED },
    );
    on && resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked()
}

impl SetupApp {
    fn new(lang: Lang, exe: PathBuf, ctx: &egui::Context) -> SetupApp {
        let path = setup::default_dir(|k| std::env::var(k).ok())
            .map(|p| p.display().to_string())
            .unwrap_or_default();
        let (tx, rx) = channel();
        // the manifest's size line; the facts built in were checked by `setup::mode`
        if let Ok(cfg) = config::parse(setup::EMBEDDED, std::path::Path::new(".")) {
            std::thread::spawn(move || {
                let _ = tx.send(setup::download_size(&Curl, &cfg));
            });
        }
        SetupApp {
            lang,
            exe,
            path,
            choices: Choices::default(),
            art: Art::load(ctx),
            size: None,
            size_rx: Some(rx),
            error: None,
            working: false,
            done_rx: None,
        }
    }

    fn check(&self) -> Dir {
        setup::check_dir(std::path::Path::new(self.path.trim()))
    }

    /// The line under the folder: the size and free space, or the reason the folder is not good.
    fn status_line(&self) -> (String, bool) {
        let l = self.lang;
        match self.check() {
            Dir::Refuse(DirRefuse::NotEmpty) => return (i18n::setup_text(SetupText::NotEmpty, l).into(), true),
            Dir::Refuse(_) => return (i18n::setup_text(SetupText::BadFolder, l).into(), true),
            Dir::Warn(DirWarn::ProgramFiles) => {
                return (i18n::setup_text(SetupText::WarnProgramFiles, l).into(), false)
            }
            Dir::Warn(DirWarn::Network) => return (i18n::setup_text(SetupText::WarnNetwork, l).into(), false),
            Dir::Ok => {}
        }
        match &self.size {
            None => (i18n::setup_text(SetupText::Checking, l).into(), false),
            Some(Err(e)) => (e.text(l), true),
            Some(Ok(None)) => (String::new(), false),
            Some(Ok(Some(need))) => {
                let free = setup::free_space(std::path::Path::new(self.path.trim()));
                let need = need + cinders_launcher::install::SPACE_MARGIN;
                match free {
                    Some(f) if f < need => (Error::NoSpace { need, free: f }.text(l), true),
                    Some(f) => {
                        let (a, b) = (fmt::bytes(need, l), fmt::bytes(f, l));
                        (
                            if l == Lang::Pt {
                                format!("Precisa de {a}. Livre na pasta: {b}.")
                            } else {
                                format!("Needs {a}. Free in the folder: {b}.")
                            },
                            false,
                        )
                    }
                    None => (String::new(), false),
                }
            }
        }
    }

    fn can_install(&self) -> bool {
        !self.working
            && matches!(self.check(), Dir::Ok | Dir::Warn(_))
            && matches!(&self.size, Some(Ok(_)))
            && !self.status_line().1
    }

    fn start_install(&mut self) {
        let dir = PathBuf::from(self.path.trim());
        let (exe, choices) = (self.exe.clone(), self.choices);
        let (tx, rx) = channel();
        self.done_rx = Some(rx);
        self.working = true;
        self.error = None;
        std::thread::spawn(move || {
            let r = setup::install(
                &exe,
                &dir,
                setup::EMBEDDED,
                choices,
                env!("CARGO_PKG_VERSION"),
                &setup::SYSTEM,
                &setup::SYSTEM,
            );
            let _ = tx.send(r);
        });
    }
}

impl eframe::App for SetupApp {
    fn update(&mut self, ctx: &egui::Context, _f: &mut eframe::Frame) {
        if let Some(rx) = &self.size_rx {
            if let Ok(r) = rx.try_recv() {
                self.size = Some(r);
                self.size_rx = None;
            }
        }
        if let Some(rx) = &self.done_rx {
            if let Ok(r) = rx.try_recv() {
                self.done_rx = None;
                self.working = false;
                match r {
                    Ok(done) => {
                        // the installed copy runs the first update and shows the window
                        let started = std::process::Command::new(&done.exe)
                            .arg("--first-run")
                            .current_dir(done.exe.parent().unwrap_or(std::path::Path::new(".")))
                            .spawn()
                            .is_ok();
                        if started {
                            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                        } else {
                            self.error = Some(Error::NoGame(done.exe.display().to_string()).text(self.lang));
                        }
                    }
                    Err(e) => self.error = Some(e.text(self.lang)),
                }
            }
        }
        if self.working || self.size_rx.is_some() {
            ctx.request_repaint_after(std::time::Duration::from_millis(100));
        }
        egui::CentralPanel::default()
            .frame(egui::Frame::none().fill(theme::BG))
            .show(ctx, |ui| {
                let cv = Cv::new(ui.max_rect());
                self.draw(ctx, ui, cv);
            });
    }
}

impl SetupApp {
    fn draw(&mut self, ctx: &egui::Context, ui: &mut egui::Ui, cv: Cv) {
        let l = layout::layout();
        let lang = self.lang;
        let p = ui.painter().clone();
        let screen = Rect::from_min_size(cv.origin, Vec2::new(layout::W * cv.k, layout::H * cv.k));
        p.image(
            self.art.hero.id(),
            screen,
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );
        // title bar: drag, name, close
        let bar = cv.rect(l.title_bar);
        p.rect_filled(bar, Rounding::same(cv.px(6.0)), Color32::from_black_alpha(140));
        if ui.interact(bar, egui::Id::new("drag"), Sense::drag()).drag_started() {
            ctx.send_viewport_cmd(egui::ViewportCommand::StartDrag);
        }
        p.circle_filled(cv.pt(38.0, 34.0), cv.px(5.0), theme::GOLD);
        p.text(
            cv.pt(56.0, 34.0),
            Align2::LEFT_CENTER,
            i18n::title(lang),
            cv.title(16.0),
            theme::TEXT,
        );
        p.image(
            self.art.crest.h.id(),
            cv.rect(l.crest),
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );
        let close = cv.rect(l.close);
        let r = ui
            .interact(close, egui::Id::new("closeb"), Sense::click())
            .on_hover_cursor(egui::CursorIcon::PointingHand);
        theme::ico_close(&p, close.center(), cv.px(6.0), theme::MUTED);
        if r.clicked() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }
        // the logo, a little smaller than in the launcher so the card fits under it
        let logo = Rect::from_center_size(
            cv.pt(640.0, 215.0),
            Vec2::new(cv.px(440.0), cv.px(440.0 * 373.0 / 560.0)),
        );
        p.image(
            self.art.logo.id(),
            logo,
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );

        // the card
        let card = R::new(290.0, 400.0, 700.0, 360.0);
        let rect = cv.rect(card);
        p.rect_filled(
            rect,
            Rounding::same(cv.px(12.0)),
            Color32::from_rgba_unmultiplied(12, 9, 8, 236),
        );
        p.rect_stroke(
            rect,
            Rounding::same(cv.px(12.0)),
            Stroke::new(cv.px(1.6), theme::GOLD_LINE),
        );
        p.text(
            cv.pt(card.x + 28.0, card.y + 34.0),
            Align2::LEFT_CENTER,
            i18n::setup_text(SetupText::Title, lang),
            cv.title(20.0),
            theme::TEXT,
        );
        p.text(
            cv.pt(card.x + 28.0, card.y + 74.0),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::InstallFolder, lang),
            cv.font(14.5),
            theme::MUTED,
        );
        // the folder field and "Choose folder"
        let field = cv.rect(R::new(card.x + 28.0, card.y + 90.0, 470.0, 38.0));
        p.rect_filled(field, Rounding::same(cv.px(6.0)), Color32::from_rgb(10, 8, 7));
        p.rect_stroke(
            field,
            Rounding::same(cv.px(6.0)),
            Stroke::new(1.0_f32, theme::GOLD_LINE),
        );
        let edit = egui::TextEdit::singleline(&mut self.path)
            .font(cv.font(14.5))
            .text_color(theme::TEXT)
            .frame(false)
            .margin(Vec2::new(cv.px(10.0), cv.px(8.0)))
            .desired_width(field.width());
        ui.put(field, edit);
        let choose = cv.rect(R::new(card.x + 512.0, card.y + 90.0, 160.0, 38.0));
        if small_btn(
            ui,
            &self.art,
            cv,
            choose,
            i18n::setup_text(SetupText::Choose, lang),
            "choose",
            !self.working,
        ) {
            if let Some(p) = setup::SYSTEM.pick_folder(std::path::Path::new(self.path.trim())) {
                // a folder the player picked gets its own sub-folder, so the game never lands in the middle of other files
                let nonempty = std::fs::read_dir(&p).map(|mut d| d.next().is_some()).unwrap_or(false);
                let ours = p.join(config::FILE).is_file();
                self.path = if nonempty && !ours { p.join("CindersOfChaos") } else { p }
                    .display()
                    .to_string();
            }
        }
        // size, free space, warnings
        let (line, bad) = self.status_line();
        let col = if bad { theme::ERROR } else { theme::MUTED };
        let font = cv.font(14.0);
        let g = p.layout(line, font, col, cv.px(640.0));
        p.galley(cv.pt(card.x + 28.0, card.y + 140.0), g, col);
        // the two shortcuts
        for (i, (label, flag)) in [
            (SetupText::DesktopLink, self.choices.desktop),
            (SetupText::MenuLink, self.choices.start_menu),
        ]
        .into_iter()
        .enumerate()
        {
            let y = card.y + 196.0 + i as f32 * 38.0;
            let cb = cv.rect(R::new(card.x + 28.0, y, 24.0, 24.0));
            let resp = ui.interact(cb.expand(cv.px(4.0)), egui::Id::new(("cb", i)), Sense::click());
            p.rect_stroke(
                cb,
                Rounding::same(cv.px(4.0)),
                Stroke::new(cv.px(1.4), theme::GOLD_LINE),
            );
            if flag {
                theme::ico_chev(
                    &p,
                    cb.center() + Vec2::new(0.0, cv.px(-2.0)),
                    cv.px(6.0),
                    theme::GOLD,
                    'd',
                );
            }
            p.text(
                cv.pt(card.x + 64.0, y + 12.0),
                Align2::LEFT_CENTER,
                i18n::setup_text(label, lang),
                cv.font(14.5),
                theme::TEXT,
            );
            if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() {
                if i == 0 {
                    self.choices.desktop = !self.choices.desktop;
                } else {
                    self.choices.start_menu = !self.choices.start_menu;
                }
            }
        }
        if let Some(e) = &self.error {
            let g = p.layout(e.clone(), cv.font(13.5), theme::ERROR, cv.px(430.0));
            p.galley(cv.pt(card.x + 28.0, card.y + 280.0), g, theme::ERROR);
        }
        // Install: the game's red octagon button
        let play = cv.rect(R::new(
            card.x + card.w - 28.0 - 230.0,
            card.y + card.h - 24.0 - 76.0,
            230.0,
            76.0,
        ));
        let on = self.can_install();
        let resp = ui.interact(
            play,
            egui::Id::new("install"),
            if on { Sense::click() } else { Sense::hover() },
        );
        if on {
            theme::glow(
                &p,
                play,
                cv.px(14.0),
                Color32::from_rgba_unmultiplied(235, 80, 20, if resp.hovered() { 150 } else { 100 }),
                cv.px(22.0),
            );
            let look = if resp.is_pointer_button_down_on() {
                theme::BigBtn::Pressed
            } else if resp.hovered() {
                theme::BigBtn::Hover
            } else {
                theme::BigBtn::Ready
            };
            theme::big_button(&p, play, cv.px(1.0), look);
        } else {
            theme::big_button(&p, play, cv.px(1.0), theme::BigBtn::Off);
        }
        let label = if self.working {
            i18n::setup_text(SetupText::Installing, lang)
        } else {
            i18n::setup_text(SetupText::Install, lang)
        }
        .to_uppercase();
        let ink = if on {
            Color32::from_rgb(255, 243, 222)
        } else {
            Color32::from_rgb(118, 104, 94)
        };
        theme::tracked(
            &p,
            play.center(),
            &label,
            cv.title(26.0),
            ink,
            cv.px(3.0),
            Align2::CENTER_CENTER,
        );
        if on && resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() {
            self.start_install();
        }
    }
}

pub fn run(lang: Lang, exe: PathBuf) -> eframe::Result<()> {
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([layout::W, layout::H])
            .with_decorations(false)
            .with_resizable(false)
            .with_icon(theme::icon())
            .with_title(i18n::setup_text(SetupText::Title, lang)),
        ..Default::default()
    };
    eframe::run_native(
        i18n::setup_text(SetupText::Title, lang),
        opts,
        Box::new(move |cc| {
            theme::apply(&cc.egui_ctx);
            Ok(Box::new(SetupApp::new(lang, exe, &cc.egui_ctx)))
        }),
    )
}
