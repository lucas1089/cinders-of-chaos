//! The launcher window (O552): the 1280x800 canvas of `layout.rs`, drawn with the painter in the game's own ornate
//! style. Logic that can be tested lives in the library (`carousel`, `fmt`, `feed`, `layout`, `choice`); this file only
//! draws and routes clicks.
use crate::theme::{self, Art, Cv};
use cinders_launcher::carousel::Carousel;
use cinders_launcher::config::{self, Client, Config, Links, Settings};
use cinders_launcher::feed::{self, Card, Panel};
use cinders_launcher::i18n::{self, Error, Lang, Status, Ui};
use cinders_launcher::install::{Event, Options, Outcome};
use cinders_launcher::layout::{self, R};
use cinders_launcher::net::Curl;
use cinders_launcher::{choice, fmt, images, launch};
use eframe::egui::{self, Align2, Color32, Pos2, Rect, Rounding, Sense, Stroke, TextureHandle, Vec2};
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::time::Instant;

enum Msg {
    Ev(Event),
    Done(Result<Outcome, Error>),
}

enum Phase {
    Working,
    Ready(Outcome),
    Failed(Error),
}

/// What the player asked for in this frame; applied after the drawing.
#[derive(Default)]
struct Actions {
    play: Option<String>,
    retry: bool,
    pick: Option<Client>,
    lang: Option<Lang>,
    open: Option<String>,
    toggle_close_on_play: bool,
    open_folder: bool,
    verify: bool,
    clear_cache: bool,
}

pub struct App {
    cfg: Config,
    links: Links,
    client: Client,
    exe: PathBuf,
    lang: Lang,
    settings: Settings,
    phase: Phase,
    status: Status,
    done: u64,
    total: u64,
    files_done: usize,
    files_total: usize,
    speed: fmt::Speed,
    shown: f32,
    started: Instant,
    launch_error: Option<Error>,
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    panel: Panel,
    cards: Vec<Card>,
    carousel: Carousel,
    feed_rx: Option<Receiver<Panel>>,
    img_tx: Sender<(String, Option<images::Rgba>)>,
    img_rx: Receiver<(String, Option<images::Rgba>)>,
    pics: HashMap<String, Option<TextureHandle>>,
    art: Art,
    detail: bool,
    settings_open: bool,
    chip_open: bool,
    scaled: bool,
    version: &'static str,
    verify_next: bool,
}

fn tag_color(t: feed::Tag) -> (Color32, Color32) {
    match t {
        feed::Tag::Update => (theme::GOLD, Color32::from_rgb(34, 18, 6)),
        feed::Tag::Maintenance | feed::Tag::Notice => (theme::EMBER, Color32::from_rgb(255, 240, 220)),
        _ => (theme::BLOOD, Color32::from_rgb(255, 232, 210)),
    }
}

impl App {
    pub fn new(cfg: Config, client: Client, exe: PathBuf, lang: Lang, ctx: &egui::Context) -> App {
        let (tx, rx) = channel();
        let (img_tx, img_rx) = channel();
        let settings = config::load_settings(&cfg.dir);
        let links = config::load_links(&cfg.dir, &cfg.manifest_url);
        let mut app = App {
            links,
            client,
            exe,
            lang: settings.lang.unwrap_or(lang),
            settings,
            phase: Phase::Working,
            status: Status::Checking,
            done: 0,
            total: 0,
            files_done: 0,
            files_total: 0,
            speed: fmt::Speed::default(),
            shown: 0.0,
            started: Instant::now(),
            launch_error: None,
            tx,
            rx,
            panel: Panel::Loading,
            cards: Vec::new(),
            carousel: Carousel::new(0, 0.0),
            feed_rx: None,
            img_tx,
            img_rx,
            pics: HashMap::new(),
            art: Art::load(ctx),
            detail: false,
            settings_open: false,
            chip_open: false,
            scaled: false,
            verify_next: false,
            version: env!("CARGO_PKG_VERSION"),
            cfg,
        };
        app.start_feed();
        app.start();
        app
    }

    fn now(&self) -> f64 {
        self.started.elapsed().as_secs_f64()
    }

    /// News: fetched on a thread of its own, after and apart from the update. A slow or dead feed never holds the
    /// update, the Play button or the window.
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

    fn feed_arrived(&mut self, p: Panel) {
        if let Panel::Ready { feed, .. } = &p {
            self.cards = feed.cards();
            self.carousel.set_len(self.cards.len());
            let mut urls: Vec<String> = self.cards.iter().filter_map(|c| c.image.clone()).collect();
            urls.sort();
            urls.dedup();
            urls.retain(|u| !self.pics.contains_key(u));
            if !urls.is_empty() {
                let tx = self.img_tx.clone();
                std::thread::spawn(move || {
                    for u in urls {
                        let r = images::load(&Curl, &u);
                        let _ = tx.send((u, r));
                    }
                });
            }
        }
        self.panel = p;
    }

    fn active(&self) -> Config {
        choice::active_config(&self.cfg, self.client).unwrap_or_else(|_| self.cfg.clone())
    }

    fn start(&mut self) {
        self.phase = Phase::Working;
        self.status = Status::Checking;
        self.speed.clear();
        (self.done, self.total, self.files_done, self.files_total) = (0, 0, 0, 0);
        self.shown = 0.0;
        let verify = std::mem::take(&mut self.verify_next);
        let (cfg, client, exe, tx) = (self.cfg.clone(), self.client, self.exe.clone(), self.tx.clone());
        std::thread::spawn(move || {
            let opts = Options {
                verify,
                ..super::update_options()
            };
            let r = choice::update(&cfg, client, exe, &Curl, opts, &mut |e| {
                let _ = tx.send(Msg::Ev(e));
            });
            let _ = tx.send(Msg::Done(r.map(|(o, _)| o)));
        });
    }

    fn save_settings(&self) {
        // a failed save is not worth an error window
        let _ = config::save_settings(&self.cfg.dir, &self.settings);
    }

    fn play(&mut self, ctx: &egui::Context, game: &str) {
        match launch::start(&self.active(), game) {
            Ok(()) => {
                if self.settings.close_on_play {
                    ctx.send_viewport_cmd(egui::ViewportCommand::Close);
                } else {
                    ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(true));
                }
            }
            Err(e) => self.launch_error = Some(e),
        }
    }

    fn pump(&mut self) {
        while let Ok(m) = self.rx.try_recv() {
            match m {
                Msg::Ev(Event::Status(s)) => self.status = s,
                Msg::Ev(Event::Progress { done, total }) => {
                    (self.done, self.total) = (done, total);
                    let t = self.now();
                    self.speed.push(t, done);
                }
                Msg::Ev(Event::Files { done, total }) => (self.files_done, self.files_total) = (done, total),
                Msg::Ev(Event::File(_)) => {}
                Msg::Done(Ok(o)) => self.phase = Phase::Ready(o),
                Msg::Done(Err(e)) => self.phase = Phase::Failed(e),
            }
        }
        if let Some(rx) = &self.feed_rx {
            if let Ok(p) = rx.try_recv() {
                self.feed_rx = None;
                self.feed_arrived(p);
            }
        }
    }

    fn pictures(&mut self, ctx: &egui::Context) {
        while let Ok((url, r)) = self.img_rx.try_recv() {
            let t = r.map(|im| {
                let ci = egui::ColorImage::from_rgba_unmultiplied([im.w, im.h], &im.rgba);
                ctx.load_texture(format!("news:{url}"), ci, egui::TextureOptions::LINEAR)
            });
            self.pics.insert(url, t);
        }
    }

    fn card_picture(&self, c: &Card) -> &TextureHandle {
        c.image
            .as_ref()
            .and_then(|u| self.pics.get(u))
            .and_then(Option::as_ref)
            .unwrap_or_else(|| self.art.default_news(c.tag.art()))
    }
}

// ---------------------------------------------------------------- small drawing pieces

/// Cuts `s` to fit `maxw` with an ellipsis.
fn fit(p: &egui::Painter, s: &str, font: &egui::FontId, maxw: f32) -> String {
    if theme::text_width(p, s, font.clone()) <= maxw {
        return s.to_string();
    }
    let mut out: String = s.to_string();
    while !out.is_empty() {
        out.pop();
        let t = format!("{}…", out.trim_end());
        if theme::text_width(p, &t, font.clone()) <= maxw {
            return t;
        }
    }
    String::new()
}

fn wrapped(
    p: &egui::Painter,
    s: &str,
    font: egui::FontId,
    color: Color32,
    width: f32,
    rows: usize,
) -> std::sync::Arc<egui::Galley> {
    let mut job = egui::text::LayoutJob::simple(s.to_string(), font, color, width);
    job.wrap.max_rows = rows;
    job.wrap.overflow_character = Some('…');
    p.layout_job(job)
}

fn small_button(ui: &egui::Ui, art: &Art, cv: Cv, rect: Rect, label: &str, id: &str, enabled: bool) -> bool {
    let p = ui.painter();
    let resp = ui.interact(
        rect,
        egui::Id::new(id),
        if enabled { Sense::click() } else { Sense::hover() },
    );
    let tint = if !enabled {
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
        if enabled { theme::TEXT } else { theme::MUTED },
    );
    if enabled {
        resp.clone().on_hover_cursor(egui::CursorIcon::PointingHand);
    }
    enabled && resp.clicked()
}

impl App {
    fn draw(&mut self, ctx: &egui::Context, ui: &mut egui::Ui, cv: Cv, act: &mut Actions) {
        let l = layout::layout();
        let lang = self.lang;
        let p = ui.painter().clone();
        let modal = self.detail || self.settings_open || self.chip_open;
        let screen = Rect::from_min_size(cv.origin, Vec2::new(layout::W * cv.k, layout::H * cv.k));

        // window: the login art, a double gold line, the skin's corner ornaments
        p.rect_filled(screen, 0.0, theme::BG);
        p.image(
            self.art.hero.id(),
            screen,
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );

        // title bar: drag area, name, version, language pill, settings, minimize, close
        let bar = cv.rect(l.title_bar);
        p.rect_filled(bar, Rounding::same(cv.px(6.0)), Color32::from_black_alpha(140));
        let drag = ui.interact(bar, egui::Id::new("drag"), Sense::drag());
        if drag.drag_started() {
            ctx.send_viewport_cmd(egui::ViewportCommand::StartDrag);
        }
        theme::glow(
            &p,
            Rect::from_center_size(cv.pt(38.0, 34.0), Vec2::splat(cv.px(6.0))),
            cv.px(3.0),
            Color32::from_rgba_unmultiplied(224, 78, 26, 160),
            cv.px(12.0),
        );
        p.circle_filled(cv.pt(38.0, 34.0), cv.px(5.0), theme::GOLD);
        let tfont = cv.title(16.0);
        let name = i18n::title(lang);
        let r = p.text(cv.pt(56.0, 34.0), Align2::LEFT_CENTER, name, tfont, theme::TEXT);
        p.text(
            Pos2::new(r.right() + cv.px(14.0), cv.pt(0.0, 35.0).y),
            Align2::LEFT_CENTER,
            format!("v{}", self.version),
            cv.font(14.0),
            theme::MUTED,
        );
        // crest
        p.image(
            self.art.crest.h.id(),
            cv.rect(l.crest),
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );
        // language pill
        let pill = cv.rect(l.lang);
        p.rect_filled(pill, Rounding::same(cv.px(15.0)), Color32::from_rgb(20, 16, 14));
        p.rect_stroke(pill, Rounding::same(cv.px(15.0)), Stroke::new(1.0_f32, theme::EDGE));
        for (i, lg) in [Lang::Pt, Lang::En].into_iter().enumerate() {
            let half = Rect::from_min_size(
                Pos2::new(
                    pill.min.x + cv.px(3.0) + i as f32 * cv.px(47.0),
                    pill.min.y + cv.px(3.0),
                ),
                Vec2::new(cv.px(46.0), cv.px(24.0)),
            );
            let resp = ui.interact(
                half,
                egui::Id::new(("lang", i)),
                if modal { Sense::hover() } else { Sense::click() },
            );
            let on = lang == lg;
            if on {
                p.rect_filled(half, Rounding::same(cv.px(12.0)), theme::GOLD);
            }
            p.text(
                half.center(),
                Align2::CENTER_CENTER,
                lg.tag().to_uppercase(),
                cv.title(13.0),
                if on { Color32::from_rgb(30, 18, 8) } else { theme::MUTED },
            );
            if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() && !on {
                act.lang = Some(lg);
            }
        }
        let icon_btn = |ui: &egui::Ui, r: R, id: &str, tip: &str| -> (egui::Response, Pos2) {
            let rect = cv.rect(r);
            let resp = ui
                .interact(
                    rect,
                    egui::Id::new(id),
                    if modal && id != "closeb" {
                        Sense::hover()
                    } else {
                        Sense::click()
                    },
                )
                .on_hover_cursor(egui::CursorIcon::PointingHand)
                .on_hover_text(tip);
            if resp.hovered() {
                ui.painter()
                    .rect_filled(rect, Rounding::same(cv.px(6.0)), Color32::from_white_alpha(14));
            }
            (resp, rect.center())
        };
        let (g, c) = icon_btn(ui, l.gear, "gear", i18n::ui(Ui::Settings, lang));
        theme::ico_gear(&p, c, cv.px(9.0), theme::MUTED);
        if g.clicked() {
            self.settings_open = !self.settings_open;
            self.detail = false;
            self.chip_open = false;
        }
        p.line_segment(
            [cv.pt(1158.0, 21.0), cv.pt(1158.0, 47.0)],
            Stroke::new(1.0_f32, theme::EDGE),
        );
        let (m, c) = icon_btn(ui, l.minimize, "minb", i18n::ui(Ui::Minimize, lang));
        theme::ico_minimize(&p, c, cv.px(7.0), theme::MUTED);
        if m.clicked() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Minimized(true));
        }
        let (x, c) = icon_btn(ui, l.close, "closeb", i18n::ui(Ui::Close, lang));
        theme::ico_close(&p, c, cv.px(6.0), theme::MUTED);
        if x.clicked() {
            ctx.send_viewport_cmd(egui::ViewportCommand::Close);
        }

        // the logo, with its warm halo
        let logo = cv.rect(l.logo);
        theme::glow(
            &p,
            logo.shrink(cv.px(120.0)),
            cv.px(60.0),
            Color32::from_rgba_unmultiplied(224, 78, 26, 40),
            cv.px(90.0),
        );
        p.image(
            self.art.logo.id(),
            logo,
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );

        // the rail: Discord, Site, Wiki, Account
        let rail = [
            (&self.links.discord, Ui::Discord, Color32::from_rgb(140, 150, 226), 0),
            (&self.links.site, Ui::Site, theme::GOLD, 1),
            (&self.links.wiki, Ui::Wiki, theme::GOLD, 2),
            (&self.links.signup, Ui::Signup, theme::GOLD, 3),
        ];
        let mut slot = 0;
        for (url, label, tint, kind) in rail {
            let Some(url) = url.clone() else { continue };
            let rect = cv.rect(l.rail[slot]);
            slot += 1;
            let resp = ui.interact(
                rect,
                egui::Id::new(("rail", kind)),
                if modal { Sense::hover() } else { Sense::click() },
            );
            let hot = resp.hovered() && !modal;
            if hot {
                theme::glow(
                    &p,
                    rect,
                    cv.px(6.0),
                    Color32::from_rgba_unmultiplied(232, 190, 110, 70),
                    cv.px(14.0),
                );
            }
            theme::nine(
                &p,
                &self.art.btn,
                rect,
                12.0,
                cv.px(0.6),
                if hot {
                    Color32::from_rgb(255, 240, 225)
                } else {
                    Color32::WHITE
                },
            );
            let c = Pos2::new(rect.center().x, rect.min.y + cv.px(25.0));
            let s = cv.px(10.0);
            match kind {
                0 => theme::ico_discord(&p, c, s, tint),
                1 => theme::ico_globe(&p, c, s, tint),
                2 => theme::ico_book(&p, c, s, tint),
                _ => theme::ico_userplus(&p, c, s, tint),
            }
            p.text(
                Pos2::new(rect.center().x, rect.min.y + cv.px(54.0)),
                Align2::CENTER_CENTER,
                i18n::ui(label, lang),
                cv.font(12.5),
                theme::TEXT,
            );
            if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() {
                act.open = Some(url);
            }
        }

        self.draw_strip(ctx, ui, cv, &l, modal, act);
        self.draw_bar(ctx, ui, cv, &l, act);

        // corner ornaments last, over the frame
        let (cw, off) = (cv.px(54.0), cv.px(6.0));
        let corners = [
            (0, Pos2::new(screen.min.x + off, screen.min.y + off)),
            (1, Pos2::new(screen.max.x - off - cw, screen.min.y + off)),
            (2, Pos2::new(screen.min.x + off, screen.max.y - off - cw)),
            (3, Pos2::new(screen.max.x - off - cw, screen.max.y - off - cw)),
        ];
        p.rect_stroke(
            screen.shrink(cv.px(5.0)),
            Rounding::same(cv.px(10.0)),
            Stroke::new(cv.px(1.4), Color32::from_rgb(88, 64, 34)),
        );
        p.rect_stroke(
            screen.shrink(cv.px(10.0)),
            Rounding::same(cv.px(8.0)),
            Stroke::new(cv.px(1.0), Color32::from_rgba_unmultiplied(150, 112, 52, 200)),
        );
        for (i, pos) in corners {
            p.image(
                self.art.corners[i].h.id(),
                Rect::from_min_size(pos, Vec2::splat(cw)),
                Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
                Color32::WHITE,
            );
        }

        if self.detail {
            self.draw_detail(ctx, ui, cv, &l, act);
        }
        if self.settings_open {
            self.draw_settings(ctx, ui, cv, act);
        }
    }

    // ---------------------------------------------------------------- news strip

    fn draw_strip(
        &mut self,
        ctx: &egui::Context,
        ui: &mut egui::Ui,
        cv: Cv,
        l: &layout::Layout,
        modal: bool,
        act: &mut Actions,
    ) {
        let lang = self.lang;
        let p = ui.painter().clone();
        let now = self.now();
        let title = p.text(
            cv.pt(l.strip_title.x, l.strip_title.y + 12.0),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::News, lang),
            cv.title(18.0),
            theme::TEXT,
        );
        p.text(
            Pos2::new(title.right() + cv.px(14.0), title.center().y + cv.px(1.0)),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::NewsSub, lang),
            cv.font(14.5),
            theme::MUTED,
        );
        match &self.panel {
            Panel::Loading => {
                p.text(
                    cv.pt(34.0, 560.0),
                    Align2::LEFT_CENTER,
                    i18n::feed_text(i18n::FeedText::Loading, lang),
                    cv.font(16.0),
                    theme::MUTED,
                );
                return;
            }
            Panel::Unavailable => {
                p.text(
                    cv.pt(34.0, 560.0),
                    Align2::LEFT_CENTER,
                    i18n::feed_text(i18n::FeedText::Unavailable, lang),
                    cv.font(16.0),
                    theme::MUTED,
                );
                return;
            }
            Panel::Ready { cached, .. } => {
                if *cached {
                    p.text(
                        cv.pt(34.0, 650.0),
                        Align2::LEFT_CENTER,
                        i18n::feed_text(i18n::FeedText::SavedCopy, lang),
                        cv.font(12.5),
                        theme::MUTED,
                    );
                }
            }
        }
        if self.cards.is_empty() {
            p.text(
                cv.pt(34.0, 560.0),
                Align2::LEFT_CENTER,
                i18n::ui(Ui::NoCards, lang),
                cv.font(16.0),
                theme::MUTED,
            );
            return;
        }
        // arrows, counter, dots
        let ar = |ui: &egui::Ui, r: R, id: &str| {
            ui.interact(
                cv.rect(r),
                egui::Id::new(id),
                if modal { Sense::hover() } else { Sense::click() },
            )
            .on_hover_cursor(egui::CursorIcon::PointingHand)
        };
        let prev = ar(ui, l.strip_prev, "sprev");
        theme::ico_chev(
            &p,
            cv.rect(l.strip_prev).center(),
            cv.px(6.0),
            if prev.hovered() { theme::GOLD } else { theme::MUTED },
            'l',
        );
        let next = ar(ui, l.strip_next, "snext");
        theme::ico_chev(
            &p,
            cv.rect(l.strip_next).center(),
            cv.px(6.0),
            if next.hovered() { theme::GOLD } else { theme::MUTED },
            'r',
        );
        p.text(
            cv.rect(l.strip_counter).center(),
            Align2::CENTER_CENTER,
            self.carousel.counter(),
            cv.font(15.0),
            theme::TEXT,
        );
        if prev.clicked() {
            self.carousel.prev(now);
        }
        if next.clicked() {
            self.carousel.next(now);
        }
        let n = self.cards.len();
        let step = (l.strip_dots.w / n.max(1) as f32).min(10.0);
        for i in 0..n {
            let c = cv.pt(l.strip_dots.x + 4.0 + i as f32 * step, l.strip_dots.y + 12.0);
            let rect = Rect::from_center_size(c, Vec2::splat(cv.px(step.max(8.0))));
            let r = ui.interact(
                rect,
                egui::Id::new(("dot", i)),
                if modal { Sense::hover() } else { Sense::click() },
            );
            let on = i == self.carousel.selected();
            p.circle_filled(
                c,
                cv.px(if on { 3.6 } else { 3.0 }),
                if on { theme::GOLD } else { Color32::from_rgb(96, 80, 68) },
            );
            if r.clicked() {
                self.carousel.select(i, now);
            }
        }

        // the four cards
        let vis = self.carousel.visible();
        let mut hover_any = false;
        let mut clicked: Option<usize> = None;
        for (slot, i) in vis.enumerate() {
            let rect = cv.rect(l.cards[slot]);
            let resp = ui.interact(
                rect,
                egui::Id::new(("card", slot)),
                if modal { Sense::hover() } else { Sense::click() },
            );
            hover_any |= resp.hovered() && !modal;
            let sel = i == self.carousel.selected();
            let c = self.cards[i].clone();
            if sel {
                theme::glow(
                    &p,
                    rect,
                    cv.px(10.0),
                    Color32::from_rgba_unmultiplied(224, 78, 26, 34),
                    cv.px(30.0),
                );
            }
            p.rect_filled(rect, Rounding::same(cv.px(10.0)), theme::card());
            p.rect_stroke(
                rect,
                Rounding::same(cv.px(10.0)),
                Stroke::new(
                    cv.px(if sel { 1.6 } else { 1.1 }),
                    if sel || resp.hovered() {
                        theme::GOLD
                    } else {
                        theme::EDGE
                    },
                ),
            );
            let img = Rect::from_min_size(
                rect.min + Vec2::splat(cv.px(6.0)),
                Vec2::new(rect.width() - cv.px(12.0), cv.px(70.0)),
            );
            theme::cover(&p, self.card_picture(&c), img, Color32::WHITE);
            theme::gradient_v(
                &p,
                Rect::from_min_max(Pos2::new(img.min.x, img.center().y), img.max),
                Color32::TRANSPARENT,
                Color32::from_black_alpha(190),
            );
            // tag chip
            let (fill, ink) = tag_color(c.tag);
            let label = c.tag.label(lang);
            let tf = cv.title(10.5);
            let tw = theme::text_width(&p, label, tf.clone()) + cv.px(1.4) * label.chars().count() as f32 + cv.px(18.0);
            let chip = Rect::from_min_size(
                rect.min + Vec2::new(cv.px(12.0), cv.px(12.0)),
                Vec2::new(tw, cv.px(20.0)),
            );
            p.rect_filled(chip, Rounding::same(cv.px(10.0)), fill);
            theme::tracked(&p, chip.center(), label, tf, ink, cv.px(1.4), Align2::CENTER_CENTER);
            // title, build and date, two lines of the text
            let inner = rect.width() - cv.px(28.0);
            let tfont = cv.title(12.5);
            let t = fit(&p, &c.title, &tfont, inner);
            p.text(
                rect.min + Vec2::new(cv.px(14.0), cv.px(88.0)),
                Align2::LEFT_CENTER,
                t,
                tfont,
                Color32::from_rgb(255, 240, 214),
            );
            let when = fmt::relative(&c.date, fmt::today(), lang);
            let meta = if c.build.is_empty() {
                when
            } else {
                format!("Build {} · {}", c.build, when)
            };
            p.text(
                rect.min + Vec2::new(cv.px(14.0), cv.px(106.0)),
                Align2::LEFT_CENTER,
                meta,
                cv.font(13.5),
                theme::GOLD,
            );
            if let Some(first) = c.body.first() {
                let g = wrapped(&p, first, cv.font(13.5), Color32::from_rgb(200, 188, 174), inner, 2);
                p.galley(rect.min + Vec2::new(cv.px(14.0), cv.px(118.0)), g, Color32::WHITE);
            }
            if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() {
                clicked = Some(i);
            }
        }
        if let Some(i) = clicked {
            self.carousel.select(i, now);
            self.detail = true;
        }
        if self.carousel.tick(now, hover_any || modal) {
            // the strip follows the open card by itself
        }
        ctx.request_repaint_after(std::time::Duration::from_millis(250));
        let _ = act;
    }

    // ---------------------------------------------------------------- the reading panel

    fn draw_detail(&mut self, ctx: &egui::Context, ui: &mut egui::Ui, cv: Cv, l: &layout::Layout, act: &mut Actions) {
        let lang = self.lang;
        let p = ui.painter().clone();
        let Some(c) = self.cards.get(self.carousel.selected()).cloned() else {
            self.detail = false;
            return;
        };
        let screen = Rect::from_min_size(cv.origin, Vec2::new(layout::W * cv.k, layout::H * cv.k));
        // a click outside closes it
        let outside = ui.interact(screen, egui::Id::new("detail_bg"), Sense::click());
        p.rect_filled(screen, 0.0, Color32::from_black_alpha(150));
        let rect = cv.rect(l.detail);
        p.rect_filled(rect, Rounding::same(cv.px(12.0)), Color32::from_rgb(14, 11, 10));
        p.rect_stroke(
            rect,
            Rounding::same(cv.px(12.0)),
            Stroke::new(cv.px(1.6), theme::GOLD_LINE),
        );
        let img = Rect::from_min_size(
            rect.min + Vec2::splat(cv.px(14.0)),
            Vec2::new(rect.width() - cv.px(28.0), cv.px(180.0)),
        );
        theme::cover(&p, self.card_picture(&c), img, Color32::WHITE);
        theme::gradient_v(
            &p,
            Rect::from_min_max(Pos2::new(img.min.x, img.min.y + img.height() * 0.35), img.max),
            Color32::TRANSPARENT,
            Color32::from_black_alpha(215),
        );
        let (fill, ink) = tag_color(c.tag);
        let label = c.tag.label(lang);
        let tf = cv.title(12.0);
        let tw = theme::text_width(&p, label, tf.clone()) + cv.px(1.6) * label.chars().count() as f32 + cv.px(24.0);
        let chip = Rect::from_min_size(img.min + Vec2::splat(cv.px(14.0)), Vec2::new(tw, cv.px(24.0)));
        p.rect_filled(chip, Rounding::same(cv.px(12.0)), fill);
        theme::tracked(&p, chip.center(), label, tf, ink, cv.px(1.6), Align2::CENTER_CENTER);
        let tfont = cv.title(22.0);
        let title = fit(&p, &c.title, &tfont, img.width() - cv.px(40.0));
        p.text(
            Pos2::new(img.min.x + cv.px(18.0), img.max.y - cv.px(40.0)),
            Align2::LEFT_CENTER,
            title,
            tfont,
            Color32::from_rgb(255, 240, 214),
        );
        let when = fmt::relative(&c.date, fmt::today(), lang);
        let meta = if c.build.is_empty() {
            when
        } else {
            format!("Build {} · {}", c.build, when)
        };
        p.text(
            Pos2::new(img.min.x + cv.px(18.0), img.max.y - cv.px(16.0)),
            Align2::LEFT_CENTER,
            meta,
            cv.font(15.0),
            theme::GOLD,
        );

        let body = Rect::from_min_max(
            Pos2::new(rect.min.x + cv.px(24.0), img.max.y + cv.px(14.0)),
            Pos2::new(rect.max.x - cv.px(24.0), rect.max.y - cv.px(64.0)),
        );
        ui.allocate_new_ui(egui::UiBuilder::new().max_rect(body), |ui| {
            egui::ScrollArea::vertical().auto_shrink([false, false]).show(ui, |ui| {
                ui.set_width(body.width() - cv.px(14.0));
                let changelog = c.tag == feed::Tag::Update || c.body.len() > 1;
                for line in &c.body {
                    ui.horizontal_top(|ui| {
                        if changelog {
                            ui.label(egui::RichText::new("\u{25C6}").size(cv.px(13.0)).color(theme::EMBER));
                        }
                        ui.add(egui::Label::new(egui::RichText::new(line).size(cv.px(15.5)).color(theme::TEXT)).wrap());
                    });
                    ui.add_space(cv.px(6.0));
                }
                if c.body.is_empty() {
                    ui.label(egui::RichText::new(i18n::ui(Ui::NoCards, lang)).color(theme::MUTED));
                }
            });
        });
        // buttons: open on the website, back
        let by = rect.max.y - cv.px(52.0);
        let back = Rect::from_min_size(
            Pos2::new(rect.max.x - cv.px(24.0 + 170.0), by),
            Vec2::new(cv.px(170.0), cv.px(38.0)),
        );
        if small_button(ui, &self.art, cv, back, i18n::ui(Ui::Back, lang), "detail_back", true) {
            self.detail = false;
        }
        if let Some(u) = c.url.as_deref().and_then(feed::safe_link) {
            let open = Rect::from_min_size(
                Pos2::new(back.min.x - cv.px(190.0), by),
                Vec2::new(cv.px(180.0), cv.px(38.0)),
            );
            if small_button(
                ui,
                &self.art,
                cv,
                open,
                i18n::ui(Ui::ReadMore, lang),
                "detail_open",
                true,
            ) {
                act.open = Some(u);
            }
        }
        if outside.clicked() && !rect.contains(outside.interact_pointer_pos().unwrap_or(Pos2::ZERO)) {
            self.detail = false;
        }
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            self.detail = false;
        }
    }

    // ---------------------------------------------------------------- settings

    fn draw_settings(&mut self, ctx: &egui::Context, ui: &mut egui::Ui, cv: Cv, act: &mut Actions) {
        let lang = self.lang;
        let p = ui.painter().clone();
        let screen = Rect::from_min_size(cv.origin, Vec2::new(layout::W * cv.k, layout::H * cv.k));
        let outside = ui.interact(screen, egui::Id::new("settings_bg"), Sense::click());
        p.rect_filled(screen, 0.0, Color32::from_black_alpha(160));
        let card = R::new(390.0, 150.0, 500.0, 460.0);
        let rect = cv.rect(card);
        p.rect_filled(rect, Rounding::same(cv.px(12.0)), Color32::from_rgb(14, 11, 10));
        p.rect_stroke(
            rect,
            Rounding::same(cv.px(12.0)),
            Stroke::new(cv.px(1.6), theme::GOLD_LINE),
        );
        p.text(
            cv.pt(card.x + 26.0, card.y + 34.0),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::Settings, lang),
            cv.title(20.0),
            theme::TEXT,
        );
        let row = |y: f32| card.y + y;
        // game folder
        p.text(
            cv.pt(card.x + 26.0, row(78.0)),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::InstallFolder, lang),
            cv.font(14.5),
            theme::MUTED,
        );
        let dir = self.cfg.dir.display().to_string();
        let tf = cv.font(14.0);
        let shown = fit(&p, &dir, &tf, cv.px(310.0));
        p.text(
            cv.pt(card.x + 26.0, row(102.0)),
            Align2::LEFT_CENTER,
            shown,
            tf,
            theme::TEXT,
        );
        let open = cv.rect(R::new(card.x + 350.0, row(84.0), 124.0, 34.0));
        if small_button(
            ui,
            &self.art,
            cv,
            open,
            i18n::ui(Ui::OpenFolder, lang),
            "set_open",
            true,
        ) {
            act.open_folder = true;
        }
        // close on play
        let cb = cv.rect(R::new(card.x + 26.0, row(142.0), 24.0, 24.0));
        let resp = ui.interact(cb.expand(cv.px(4.0)), egui::Id::new("set_close"), Sense::click());
        p.rect_stroke(
            cb,
            Rounding::same(cv.px(4.0)),
            Stroke::new(cv.px(1.4), theme::GOLD_LINE),
        );
        if self.settings.close_on_play {
            theme::ico_chev(
                &p,
                cb.center() + Vec2::new(0.0, cv.px(-2.0)),
                cv.px(6.0),
                theme::GOLD,
                'd',
            );
        }
        p.text(
            cv.pt(card.x + 62.0, row(154.0)),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::CloseOnPlay, lang),
            cv.font(14.5),
            theme::TEXT,
        );
        if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() {
            act.toggle_close_on_play = true;
        }
        // language
        p.text(
            cv.pt(card.x + 26.0, row(198.0)),
            Align2::LEFT_CENTER,
            i18n::ui(Ui::Language, lang),
            cv.font(14.5),
            theme::MUTED,
        );
        for (i, lg) in [Lang::Pt, Lang::En].into_iter().enumerate() {
            let r = cv.rect(R::new(card.x + 26.0 + i as f32 * 130.0, row(214.0), 120.0, 34.0));
            let on = lang == lg;
            let resp = ui.interact(r, egui::Id::new(("set_lang", i)), Sense::click());
            p.rect_filled(
                r,
                Rounding::same(cv.px(8.0)),
                if on { theme::GOLD } else { Color32::from_rgb(24, 19, 17) },
            );
            p.rect_stroke(r, Rounding::same(cv.px(8.0)), Stroke::new(1.0_f32, theme::GOLD_LINE));
            p.text(
                r.center(),
                Align2::CENTER_CENTER,
                if lg == Lang::Pt { "Português" } else { "English" },
                cv.font(15.0),
                if on { Color32::from_rgb(30, 18, 8) } else { theme::TEXT },
            );
            if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() && !on {
                act.lang = Some(lg);
            }
        }
        // repair and cache: not while an update runs
        let idle = !matches!(self.phase, Phase::Working);
        let vb = cv.rect(R::new(card.x + 26.0, row(268.0), 220.0, 38.0));
        if small_button(ui, &self.art, cv, vb, i18n::ui(Ui::Verify, lang), "set_verify", idle) {
            act.verify = true;
        }
        let cb2 = cv.rect(R::new(card.x + 258.0, row(268.0), 216.0, 38.0));
        if small_button(
            ui,
            &self.art,
            cv,
            cb2,
            i18n::ui(Ui::ClearCache, lang),
            "set_cache",
            idle,
        ) {
            act.clear_cache = true;
        }
        let hint = fit(&p, i18n::ui(Ui::VerifyHint, lang), &cv.font(13.0), cv.px(448.0));
        p.text(
            cv.pt(card.x + 26.0, row(322.0)),
            Align2::LEFT_CENTER,
            hint,
            cv.font(13.0),
            theme::MUTED,
        );
        // version
        p.text(
            cv.pt(card.x + 26.0, row(352.0)),
            Align2::LEFT_CENTER,
            format!("{}: {}", i18n::ui(Ui::Version, lang), self.version),
            cv.font(13.5),
            theme::MUTED,
        );
        let done = cv.rect(R::new(
            card.x + card.w - 26.0 - 150.0,
            card.y + card.h - 56.0,
            150.0,
            38.0,
        ));
        if small_button(ui, &self.art, cv, done, i18n::ui(Ui::Back, lang), "set_back", true) {
            self.settings_open = false;
        }
        if outside.clicked() && !rect.contains(outside.interact_pointer_pos().unwrap_or(Pos2::ZERO)) {
            self.settings_open = false;
        }
        if ctx.input(|i| i.key_pressed(egui::Key::Escape)) {
            self.settings_open = false;
        }
    }

    // ---------------------------------------------------------------- bottom bar

    fn draw_bar(&mut self, ctx: &egui::Context, ui: &mut egui::Ui, cv: Cv, l: &layout::Layout, act: &mut Actions) {
        let lang = self.lang;
        let p = ui.painter().clone();
        let busy = matches!(self.phase, Phase::Working);
        let modal = self.detail || self.settings_open || self.chip_open;
        let failed = matches!(self.phase, Phase::Failed(_));
        let ready = matches!(self.phase, Phase::Ready(_));
        let bar = cv.rect(l.bar);
        p.rect_filled(
            bar,
            Rounding::same(cv.px(10.0)),
            Color32::from_rgba_unmultiplied(12, 9, 8, 240),
        );
        let edge = if failed { theme::ERROR } else { theme::GOLD_LINE };
        p.rect_stroke(bar, Rounding::same(cv.px(10.0)), Stroke::new(cv.px(1.6), edge));
        p.rect_stroke(
            bar.shrink(cv.px(5.0)),
            Rounding::same(cv.px(7.0)),
            Stroke::new(cv.px(1.0), Color32::from_rgb(70, 52, 30)),
        );
        for (sx, sy) in [(7.0, 7.0), (1233.0, 7.0), (7.0, 113.0), (1233.0, 113.0)] {
            p.circle_filled(
                cv.pt(l.bar.x + sx, l.bar.y + sy),
                cv.px(3.0),
                Color32::from_rgb(170, 124, 56),
            );
        }
        // status dot and line
        let dot = cv.pt(l.bar.x + 36.0, l.status.y + 14.0);
        let dc = if failed {
            theme::ERROR
        } else if ready {
            theme::GOLD
        } else {
            theme::EMBER_HI
        };
        theme::glow(
            &p,
            Rect::from_center_size(dot, Vec2::splat(cv.px(6.0))),
            cv.px(3.0),
            Color32::from_rgba_unmultiplied(dc.r(), dc.g(), dc.b(), 150),
            cv.px(10.0),
        );
        p.circle_filled(dot, cv.px(6.0), dc);
        let status_text: String = match &self.phase {
            Phase::Working => i18n::status(self.status, lang).to_string(),
            Phase::Ready(_) => i18n::ui(Ui::Ready, lang).to_string(),
            Phase::Failed(e) => e.text(lang),
        };
        let sfont = if failed { cv.font(15.0) } else { cv.title(17.0) };
        let maxw = cv.px(if failed { 1120.0 } else { 600.0 });
        let galley = wrapped(
            &p,
            &status_text,
            sfont,
            if failed {
                theme::ERROR
            } else {
                Color32::from_rgb(240, 230, 216)
            },
            maxw,
            if failed { 2 } else { 1 },
        );
        p.galley(
            Pos2::new(cv.pt(76.0, 0.0).x, dot.y - cv.px(11.0)),
            galley,
            Color32::WHITE,
        );

        // client chip
        if !failed {
            let chip = cv.rect(l.chip);
            let label = match &self.phase {
                Phase::Ready(o) if o.package.is_some() => {
                    format!("{} · {}", i18n::client_name(self.client, lang), o.package.unwrap_or(0))
                }
                _ => i18n::client_name(self.client, lang).to_string(),
            };
            let can = !busy && self.cfg.unity_manifest.is_some() && !modal;
            let resp = ui.interact(
                chip,
                egui::Id::new("chip"),
                if can { Sense::click() } else { Sense::hover() },
            );
            p.rect_filled(chip, Rounding::same(cv.px(8.0)), Color32::from_rgb(24, 19, 17));
            p.rect_stroke(
                chip,
                Rounding::same(cv.px(8.0)),
                Stroke::new(
                    1.0_f32,
                    if resp.hovered() && can {
                        theme::GOLD
                    } else {
                        theme::GOLD_LINE
                    },
                ),
            );
            let cf = cv.font(14.5);
            let shown = fit(&p, &label, &cf, chip.width() - cv.px(48.0));
            p.text(
                chip.min + Vec2::new(cv.px(16.0), chip.height() / 2.0),
                Align2::LEFT_CENTER,
                shown,
                cf,
                Color32::from_rgb(200, 188, 174),
            );
            if self.cfg.unity_manifest.is_some() {
                theme::ico_chev(
                    &p,
                    Pos2::new(chip.max.x - cv.px(18.0), chip.center().y),
                    cv.px(4.2),
                    theme::MUTED,
                    'd',
                );
            }
            if resp
                .on_hover_cursor(if can {
                    egui::CursorIcon::PointingHand
                } else {
                    egui::CursorIcon::Default
                })
                .clicked()
                && can
            {
                self.chip_open = !self.chip_open;
            }
        }
        if self.chip_open {
            let chip = cv.rect(l.chip);
            let clients: Vec<Client> = [Client::Main, Client::Unity].into_iter().collect();
            let h = cv.px(36.0);
            let menu = Rect::from_min_size(
                Pos2::new(chip.min.x, chip.min.y - cv.px(8.0) - h * clients.len() as f32),
                Vec2::new(chip.width(), h * clients.len() as f32),
            );
            p.rect_filled(menu, Rounding::same(cv.px(8.0)), Color32::from_rgb(18, 14, 12));
            p.rect_stroke(menu, Rounding::same(cv.px(8.0)), Stroke::new(1.0_f32, theme::GOLD));
            let outside = ui.interact(
                Rect::from_min_size(cv.origin, Vec2::new(layout::W * cv.k, layout::H * cv.k)),
                egui::Id::new("menu_bg"),
                Sense::click(),
            );
            for (i, c) in clients.iter().enumerate() {
                let r = Rect::from_min_size(menu.min + Vec2::new(0.0, h * i as f32), Vec2::new(menu.width(), h));
                let resp = ui.interact(r, egui::Id::new(("menu", i)), Sense::click());
                if resp.hovered() {
                    p.rect_filled(
                        r.shrink(cv.px(2.0)),
                        Rounding::same(cv.px(6.0)),
                        Color32::from_rgb(52, 32, 24),
                    );
                }
                let on = *c == self.client;
                p.text(
                    r.min + Vec2::new(cv.px(16.0), h / 2.0),
                    Align2::LEFT_CENTER,
                    i18n::client_name(*c, lang),
                    cv.font(14.5),
                    if on { theme::GOLD } else { theme::TEXT },
                );
                if resp.on_hover_cursor(egui::CursorIcon::PointingHand).clicked() {
                    self.chip_open = false;
                    if !on {
                        act.pick = Some(*c);
                    }
                }
            }
            if outside.clicked() && !menu.contains(outside.interact_pointer_pos().unwrap_or(Pos2::ZERO)) {
                self.chip_open = false;
            }
            if self.client == Client::Unity {
                p.text(
                    Pos2::new(menu.min.x, menu.min.y - cv.px(14.0)),
                    Align2::LEFT_CENTER,
                    "",
                    cv.font(12.0),
                    theme::MUTED,
                );
            }
        }

        // progress, or the error buttons
        let pr = cv.rect(l.progress);
        if let Phase::Failed(e) = &self.phase {
            let b = choice::buttons(e, self.client, choice::unity_installed(&self.cfg));
            let mut x = l.progress.x;
            let y = l.progress.y - 4.0;
            let mut put = |ui: &egui::Ui, art: &Art, label: &str, id: &str, w: f32| -> bool {
                let r = cv.rect(R::new(x, y + 6.0, w, 38.0));
                x += w + 12.0;
                small_button(ui, art, cv, r, label, id, !modal)
            };
            if b.use_main && put(ui, &self.art, i18n::use_main_client(lang), "e_main", 230.0) {
                act.pick = Some(Client::Main);
            }
            if b.retry && put(ui, &self.art, i18n::retry(lang), "e_retry", 190.0) {
                act.retry = true;
            }
            if b.play_anyway && put(ui, &self.art, i18n::play_anyway(lang), "e_play", 210.0) {
                act.play = Some(self.active().game);
            }
        } else {
            p.rect_filled(
                pr.expand(cv.px(2.0)),
                Rounding::same(cv.px(5.0)),
                Color32::from_rgb(10, 8, 7),
            );
            p.rect_stroke(
                pr.expand(cv.px(2.0)),
                Rounding::same(cv.px(5.0)),
                Stroke::new(1.0_f32, theme::GOLD_LINE),
            );
            let target = if ready {
                1.0
            } else if self.total > 0 {
                (self.done as f32 / self.total as f32).clamp(0.0, 1.0)
            } else {
                0.0
            };
            let dt = ctx.input(|i| i.stable_dt).min(0.1);
            self.shown = theme::approach(self.shown, target, dt, 7.0);
            if self.total == 0 && busy {
                // no size known yet: a gold segment sweeps across
                let t = (self.now() as f32 * 0.9).fract();
                let w = pr.width() * 0.18;
                let x0 = pr.min.x + (pr.width() - w) * (0.5 - 0.5 * (t * std::f32::consts::TAU).cos());
                let seg = Rect::from_min_max(Pos2::new(x0, pr.min.y), Pos2::new(x0 + w, pr.max.y));
                theme::gradient_h(&p, seg, theme::EMBER_LO, theme::GOLD);
            } else if self.shown > 0.0 {
                let w = (pr.width() * self.shown).max(cv.px(6.0));
                let fill = Rect::from_min_size(pr.min, Vec2::new(w, pr.height()));
                if busy {
                    theme::glow(
                        &p,
                        Rect::from_center_size(
                            Pos2::new(fill.max.x, fill.center().y),
                            Vec2::new(cv.px(4.0), pr.height()),
                        ),
                        cv.px(2.0),
                        Color32::from_rgba_unmultiplied(224, 78, 26, 150),
                        cv.px(12.0),
                    );
                }
                theme::gradient_h(&p, fill, theme::EMBER_LO, theme::GOLD);
            }
            // numbers under the bar
            let sf = cv.font(15.0);
            let sy = cv.pt(0.0, l.stats.y + 12.0).y;
            let right_col = Color32::from_rgb(214, 196, 164);
            match &self.phase {
                Phase::Working if self.total > 0 => {
                    let of = if lang == Lang::Pt { "de" } else { "of" };
                    let left = format!(
                        "{} {of} {}  ·  {}/{} {}",
                        fmt::bytes(self.done, lang),
                        fmt::bytes(self.total, lang),
                        self.files_done,
                        self.files_total,
                        i18n::ui(Ui::Files, lang)
                    );
                    p.text(
                        Pos2::new(pr.min.x, sy),
                        Align2::LEFT_CENTER,
                        left,
                        sf.clone(),
                        theme::MUTED,
                    );
                    if let Some(r) = self.speed.rate() {
                        let tail = match self.speed.eta(self.total.saturating_sub(self.done)) {
                            Some(s) => format!("{}  ·  {}", fmt::time_left(s, lang), fmt::rate(r, lang)),
                            None => fmt::rate(r, lang),
                        };
                        p.text(Pos2::new(pr.max.x, sy), Align2::RIGHT_CENTER, tail, sf, right_col);
                    }
                }
                Phase::Ready(o) => {
                    let left = o.package.map(|n| format!("Build {n}")).unwrap_or_default();
                    p.text(
                        Pos2::new(pr.min.x, sy),
                        Align2::LEFT_CENTER,
                        left,
                        sf.clone(),
                        theme::MUTED,
                    );
                    p.text(
                        Pos2::new(pr.max.x, sy),
                        Align2::RIGHT_CENTER,
                        i18n::ui(Ui::UpToDateLine, lang),
                        sf,
                        right_col,
                    );
                }
                _ => {}
            }
        }

        // the Play button: the game's red octagon, cold while the update runs, nothing after an error
        let play = cv.rect(l.play);
        if !failed {
            let enabled = ready && !modal;
            let resp = ui.interact(
                play,
                egui::Id::new("play"),
                if enabled { Sense::click() } else { Sense::hover() },
            );
            if ready {
                theme::glow(
                    &p,
                    play,
                    cv.px(14.0),
                    Color32::from_rgba_unmultiplied(235, 80, 20, if resp.hovered() { 150 } else { 100 }),
                    cv.px(if resp.hovered() { 30.0 } else { 20.0 }),
                );
                let tint = if resp.is_pointer_button_down_on() {
                    Color32::from_rgb(210, 160, 140)
                } else if resp.hovered() {
                    Color32::from_rgb(255, 215, 190)
                } else {
                    Color32::from_rgb(255, 190, 160)
                };
                theme::nine(&p, &self.art.btn_red, play, 14.0, cv.px(1.0), tint);
            } else {
                theme::nine(&p, &self.art.btn_off, play, 14.0, cv.px(1.0), Color32::WHITE);
            }
            let ink = if ready {
                Color32::from_rgb(255, 243, 222)
            } else {
                Color32::from_rgb(118, 104, 94)
            };
            let label = i18n::play(lang).to_uppercase();
            let tf = cv.title(30.0);
            if ready {
                theme::tracked(
                    &p,
                    play.center() + Vec2::new(cv.px(1.5), cv.px(2.5)),
                    &label,
                    tf.clone(),
                    Color32::from_black_alpha(130),
                    cv.px(4.0),
                    Align2::CENTER_CENTER,
                );
            }
            let r = theme::tracked(
                &p,
                play.center() + Vec2::new(cv.px(18.0), 0.0),
                &label,
                tf,
                ink,
                cv.px(4.0),
                Align2::CENTER_CENTER,
            );
            theme::ico_play(&p, Pos2::new(r.min.x - cv.px(26.0), play.center().y), cv.px(12.0), ink);
            if enabled {
                resp.clone().on_hover_cursor(egui::CursorIcon::PointingHand);
                if resp.clicked() {
                    if let Phase::Ready(o) = &self.phase {
                        act.play = Some(o.game.clone());
                    }
                }
            }
        }
        if let Some(e) = &self.launch_error {
            p.text(
                cv.pt(56.0, 640.0 + 14.0),
                Align2::LEFT_CENTER,
                e.text(lang),
                cv.font(13.0),
                theme::ERROR,
            );
        }
        if busy {
            ctx.request_repaint_after(std::time::Duration::from_millis(33));
        }
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        self.pump();
        self.pictures(ctx);
        // a screen smaller than the canvas: the window shrinks, the drawing scales with it
        if !self.scaled {
            if let Some(m) = ctx.input(|i| i.viewport().monitor_size) {
                self.scaled = true;
                let s = layout::scale_for(m.x, m.y);
                if s < 1.0 {
                    ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize(Vec2::new(
                        layout::W * s,
                        layout::H * s,
                    )));
                }
            }
        }
        let mut act = Actions::default();
        egui::CentralPanel::default()
            .frame(egui::Frame::none().fill(theme::BG))
            .show(ctx, |ui| {
                let cv = Cv::new(ui.max_rect());
                self.draw(ctx, ui, cv, &mut act);
            });
        if let Some(l) = act.lang {
            self.lang = l;
            self.settings.lang = Some(l);
            self.save_settings();
            // the feed has a block per language: fetch again so the cards follow
            self.start_feed();
        }
        if act.toggle_close_on_play {
            self.settings.close_on_play = !self.settings.close_on_play;
            self.save_settings();
        }
        if act.clear_cache && !matches!(self.phase, Phase::Working) {
            // only the half-downloaded pieces of an earlier run; the installed files are not touched
            let _ = std::fs::remove_dir_all(self.cfg.dir.join(cinders_launcher::install::STATE_DIR).join("stage"));
        }
        if act.open_folder {
            open_folder(&self.cfg.dir);
        }
        if let Some(u) = act.open.and_then(|u| feed::safe_link(&u)) {
            ctx.open_url(egui::OpenUrl::new_tab(u));
        }
        let mut retry = act.retry;
        if act.verify && !matches!(self.phase, Phase::Working) {
            self.verify_next = true;
            retry = true;
        }
        if let Some(c) = act.pick {
            self.settings.client = c;
            self.save_settings();
            self.client = c;
            retry = true;
        }
        if retry {
            self.launch_error = None;
            self.start();
        }
        if let Some(g) = act.play {
            self.play(ctx, &g);
        }
        if self.feed_rx.is_some() {
            ctx.request_repaint_after(std::time::Duration::from_millis(200));
        }
    }
}

/// Opens the game folder in the system's file manager.
fn open_folder(dir: &std::path::Path) {
    #[cfg(windows)]
    let cmd = "explorer";
    #[cfg(target_os = "macos")]
    let cmd = "open";
    #[cfg(all(not(windows), not(target_os = "macos")))]
    let cmd = "xdg-open";
    let _ = std::process::Command::new(cmd).arg(dir).spawn();
}

pub fn run(cfg: Config, client: Client, exe: PathBuf, lang: Lang) -> eframe::Result<()> {
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([layout::W, layout::H])
            .with_decorations(false)
            .with_resizable(false)
            .with_icon(theme::icon())
            .with_title(i18n::title(lang)),
        ..Default::default()
    };
    eframe::run_native(
        i18n::title(lang),
        opts,
        Box::new(move |cc| {
            theme::apply(&cc.egui_ctx);
            Ok(Box::new(App::new(cfg, client, exe, lang, &cc.egui_ctx)))
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

#[allow(dead_code)]
fn _unused(_: Options) {}
