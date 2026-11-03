//! Look of the admin window (O344): the launcher's dark fantasy family, tightened for a dense tool. A forge on the night
//! shift: warm neutral iron, one ember. Ember marks the one main action and the live dot of a running server; gold marks
//! only the selected category of the sidebar (O383). Headings use the text colour. Sizes sit on a 4 px grid (type 12, 13, 14, 16, 20).
//! Only colours and drawing. No behaviour, no text (strings are in `main.rs`).
//! The Android app (android/.../res/values/colors.xml) uses the same ramp.
//! Colours match `launcher/src/theme.rs`; the crates share no code on purpose (two small files, no cross dependency).
use eframe::egui::{
    self, Color32, FontFamily, FontId, Pos2, Rect, Response, RichText, Sense, Stroke, TextStyle, Ui, Vec2,
};

/// Window colour. `desktop/tools/gen_admin_art.py` fades the header strip into the same value.
pub const BG: Color32 = Color32::from_rgb(14, 11, 10);
pub const CARD: Color32 = Color32::from_rgb(25, 20, 18);
pub const CARD_EDGE: Color32 = Color32::from_rgb(56, 42, 34);
pub const INPUT: Color32 = Color32::from_rgb(10, 8, 7);
pub const EMBER: Color32 = Color32::from_rgb(224, 78, 26);
pub const EMBER_HI: Color32 = Color32::from_rgb(250, 118, 44);
pub const EMBER_LO: Color32 = Color32::from_rgb(160, 48, 14);
pub const GOLD: Color32 = Color32::from_rgb(232, 190, 110);
pub const TEXT: Color32 = Color32::from_rgb(222, 212, 200);
/// Secondary text and bars: between TEXT and MUTED.
pub const TEXT_2: Color32 = Color32::from_rgb(188, 176, 164);
pub const MUTED: Color32 = Color32::from_rgb(150, 136, 124);
/// Status colours, the same everywhere: ok, warning, error.
pub const OK: Color32 = Color32::from_rgb(110, 200, 120);
pub const WARN: Color32 = Color32::from_rgb(238, 172, 60);
pub const ERROR: Color32 = Color32::from_rgb(240, 98, 84);

/// The header strip (1280x64) and the window icon (128x128), raw RGBA made by `tools/gen_admin_art.py`.
pub const HEADER_SIZE: [usize; 2] = [1280, 64];
pub const ICON_SIZE: u32 = 128;
const HEADER_RGBA: &[u8] = include_bytes!("../assets/header.rgba");
const ICON_RGBA: &[u8] = include_bytes!("../assets/icon.rgba");

pub fn icon() -> egui::IconData {
    egui::IconData {
        rgba: ICON_RGBA.to_vec(),
        width: ICON_SIZE,
        height: ICON_SIZE,
    }
}

pub fn header(ctx: &egui::Context) -> egui::TextureHandle {
    let img = egui::ColorImage::from_rgba_unmultiplied(HEADER_SIZE, HEADER_RGBA);
    ctx.load_texture("header", img, egui::TextureOptions::LINEAR)
}

pub fn icon_texture(ctx: &egui::Context) -> egui::TextureHandle {
    let img = egui::ColorImage::from_rgba_unmultiplied([ICON_SIZE as usize; 2], ICON_RGBA);
    ctx.load_texture("icon", img, egui::TextureOptions::LINEAR)
}

/// Colours, spacing and text sizes for the whole window.
pub fn apply(ctx: &egui::Context) {
    let mut v = egui::Visuals::dark();
    v.panel_fill = BG;
    v.window_fill = CARD;
    v.window_stroke = Stroke::new(1.0_f32, CARD_EDGE);
    v.window_rounding = egui::Rounding::same(12.0);
    v.extreme_bg_color = INPUT;
    v.faint_bg_color = Color32::from_rgb(20, 16, 14);
    v.hyperlink_color = TEXT;
    v.selection.bg_fill = Color32::from_rgb(72, 54, 44);
    v.selection.stroke = Stroke::new(1.0_f32, TEXT);
    v.override_text_color = None;
    let r = egui::Rounding::same(8.0);
    for w in [
        &mut v.widgets.noninteractive,
        &mut v.widgets.inactive,
        &mut v.widgets.hovered,
        &mut v.widgets.active,
        &mut v.widgets.open,
    ] {
        w.rounding = r;
    }
    v.widgets.noninteractive.bg_fill = CARD;
    v.widgets.noninteractive.bg_stroke = Stroke::new(1.0_f32, CARD_EDGE);
    v.widgets.noninteractive.fg_stroke = Stroke::new(1.0_f32, TEXT);
    v.widgets.inactive.bg_fill = Color32::from_rgb(40, 31, 27);
    v.widgets.inactive.weak_bg_fill = Color32::from_rgb(40, 31, 27);
    v.widgets.inactive.bg_stroke = Stroke::new(1.0_f32, CARD_EDGE);
    v.widgets.inactive.fg_stroke = Stroke::new(1.0_f32, TEXT);
    v.widgets.hovered.bg_fill = Color32::from_rgb(52, 41, 35);
    v.widgets.hovered.weak_bg_fill = Color32::from_rgb(52, 41, 35);
    v.widgets.hovered.bg_stroke = Stroke::new(1.0_f32, Color32::from_rgb(92, 72, 60));
    v.widgets.hovered.fg_stroke = Stroke::new(1.0_f32, TEXT);
    v.widgets.active.bg_fill = Color32::from_rgb(64, 50, 42);
    v.widgets.active.weak_bg_fill = Color32::from_rgb(64, 50, 42);
    v.widgets.active.bg_stroke = Stroke::new(1.0_f32, Color32::from_rgb(110, 88, 74));
    v.widgets.active.fg_stroke = Stroke::new(1.0_f32, TEXT);
    v.widgets.open.bg_fill = Color32::from_rgb(40, 31, 27);
    v.widgets.open.weak_bg_fill = Color32::from_rgb(40, 31, 27);
    v.widgets.open.bg_stroke = Stroke::new(1.0_f32, Color32::from_rgb(92, 72, 60));
    ctx.set_visuals(v);
    ctx.style_mut(|s| {
        s.spacing.item_spacing = Vec2::new(8.0, 8.0);
        s.spacing.button_padding = Vec2::new(12.0, 4.0);
        s.spacing.interact_size.y = 28.0;
        s.spacing.scroll.bar_width = 8.0;
        s.spacing.indent = 16.0;
        s.text_styles
            .insert(TextStyle::Body, FontId::new(14.0, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Button, FontId::new(14.0, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Small, FontId::new(12.0, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Monospace, FontId::new(13.0, FontFamily::Monospace));
        s.text_styles
            .insert(TextStyle::Heading, FontId::new(20.0, FontFamily::Proportional));
    });
}

/// A panel with a thin warm edge. The inside is up to the caller.
pub fn card() -> egui::Frame {
    egui::Frame::none()
        .fill(CARD)
        .stroke(Stroke::new(1.0_f32, CARD_EDGE))
        .rounding(12.0)
        .inner_margin(egui::Margin::same(16.0))
}

/// A dark well for logs and command output.
pub fn well() -> egui::Frame {
    egui::Frame::none()
        .fill(INPUT)
        .stroke(Stroke::new(1.0_f32, CARD_EDGE))
        .rounding(8.0)
        .inner_margin(egui::Margin::symmetric(12.0, 8.0))
}

/// A card that fills the width, with `add` inside.
pub fn card_full<R>(ui: &mut Ui, add: impl FnOnce(&mut Ui) -> R) -> R {
    card()
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            add(ui)
        })
        .inner
}

/// A card heading: sentence case, text colour, a step above the body.
pub fn card_title(text: &str) -> RichText {
    RichText::new(text).size(16.0).color(TEXT)
}

/// A server state word in its status colour. `live` puts the ember dot before it: the one mark of a running server.
pub fn state_word(ui: &mut Ui, word: &str, colour: Color32, live: bool) {
    if live {
        let (dot, _) = ui.allocate_exact_size(Vec2::splat(12.0), Sense::hover());
        ui.painter().circle_filled(dot.center(), 4.0, EMBER);
    }
    ui.colored_label(colour, word);
}

/// A usage bar (memory, disk): neutral, warning from 80 %, error from 90 %.
pub fn usage_bar(ui: &mut Ui, percent: u32) {
    let fill = match percent {
        90.. => ERROR,
        80..=89 => WARN,
        _ => TEXT_2,
    };
    ui.add(
        egui::ProgressBar::new(percent.min(100) as f32 / 100.0)
            .desired_width(120.0)
            .desired_height(8.0)
            .fill(fill),
    );
}

/// Small muted caption (a field label, a hint).
pub fn caption(text: &str) -> RichText {
    RichText::new(text).color(MUTED)
}

/// A button with its own colours: `(fill, hover fill, edge, text)`.
fn coloured_button(ui: &mut Ui, label: &str, look: (Color32, Color32, Color32, Color32)) -> Response {
    ui.scope(|ui| {
        let (fill, hover, edge, text) = look;
        let w = &mut ui.visuals_mut().widgets;
        w.inactive.weak_bg_fill = fill;
        w.inactive.bg_fill = fill;
        w.inactive.bg_stroke = Stroke::new(1.0_f32, edge);
        w.hovered.weak_bg_fill = hover;
        w.hovered.bg_fill = hover;
        w.hovered.bg_stroke = Stroke::new(1.0_f32, edge);
        w.active.weak_bg_fill = edge;
        w.active.bg_fill = edge;
        let r = ui.add(egui::Button::new(RichText::new(label).color(text)));
        r.on_hover_cursor(egui::CursorIcon::PointingHand)
    })
    .inner
}

/// The ember button: the one main action of a screen (Salvar, Executar, update). A darker ember than the dot, so the
/// light text keeps 4.5:1.
pub fn primary_button(ui: &mut Ui, label: &str) -> Response {
    coloured_button(
        ui,
        label,
        (
            Color32::from_rgb(190, 62, 20),
            EMBER,
            EMBER_HI,
            Color32::from_rgb(255, 240, 215),
        ),
    )
}

/// A red-edged button for a command that asks for a confirmation (restart, rollback, kick).
pub fn danger_button(ui: &mut Ui, label: &str) -> Response {
    coloured_button(
        ui,
        label,
        (
            Color32::from_rgb(52, 28, 24),
            Color32::from_rgb(86, 36, 28),
            Color32::from_rgb(150, 60, 48),
            Color32::from_rgb(255, 214, 204),
        ),
    )
}

/// The brand strip: the header art with the icon and the title on it. Items on the right go in the same row, after it.
pub fn header_bar(ui: &mut Ui, strip: &egui::TextureHandle, icon: &egui::TextureHandle, title: &str) {
    let h = 52.0;
    let (rect, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), h), Sense::hover());
    let size = Vec2::new(HEADER_SIZE[0] as f32, HEADER_SIZE[1] as f32);
    let art = Rect::from_min_size(rect.min - Vec2::new(0.0, (size.y - h) / 2.0), size);
    let p = ui.painter().with_clip_rect(rect);
    p.image(
        strip.id(),
        art,
        Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
        Color32::WHITE,
    );
    let ir = Rect::from_min_size(rect.min + Vec2::new(14.0, 8.0), Vec2::splat(h - 16.0));
    p.image(
        icon.id(),
        ir,
        Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
        Color32::WHITE,
    );
    let font = FontId::new(21.0, FontFamily::Proportional);
    let at = Pos2::new(ir.max.x + 12.0, rect.center().y);
    p.text(
        at + Vec2::new(0.0, 1.0),
        egui::Align2::LEFT_CENTER,
        title,
        font.clone(),
        Color32::from_black_alpha(140),
    );
    p.text(at, egui::Align2::LEFT_CENTER, title, font, GOLD);
}

/// A sidebar category (O383): a full-width row, the selected one with a gold bar on the left and gold text (gold
/// marks only the selected category).
pub fn nav_item(ui: &mut Ui, selected: bool, label: &str) -> Response {
    let font = FontId::new(14.0, FontFamily::Proportional);
    let h = 32.0;
    let (rect, resp) = ui.allocate_exact_size(Vec2::new(ui.available_width(), h), Sense::click());
    let color = if selected {
        GOLD
    } else if resp.hovered() {
        TEXT
    } else {
        TEXT_2
    };
    let p = ui.painter();
    if selected {
        p.rect_filled(rect, 8.0, Color32::from_rgb(36, 28, 23));
        p.rect_filled(
            Rect::from_min_size(rect.min + Vec2::new(0.0, 6.0), Vec2::new(3.0, h - 12.0)),
            2.0,
            GOLD,
        );
    } else if resp.hovered() {
        p.rect_filled(rect, 8.0, Color32::from_rgb(30, 24, 21));
    }
    let galley = p.layout_no_wrap(label.to_owned(), font, color);
    let at = Pos2::new(rect.min.x + 14.0, rect.center().y - galley.size().y / 2.0);
    p.with_clip_rect(rect).galley(at, galley, color);
    resp.on_hover_cursor(egui::CursorIcon::PointingHand)
}

/// A short bar at the top centre of a resizable panel: the place to drag it (the whole top edge drags).
pub fn grip(ui: &mut Ui) {
    let (r, _) = ui.allocate_exact_size(Vec2::new(ui.available_width(), 6.0), Sense::hover());
    ui.painter().rect_filled(
        Rect::from_center_size(Pos2::new(r.center().x, r.min.y), Vec2::new(48.0, 4.0)),
        2.0,
        Color32::from_rgb(92, 72, 60),
    );
}

/// A hairline across the width, under the header.
pub fn rule(ui: &mut Ui) {
    let y = ui.cursor().min.y;
    let x = ui.max_rect().x_range();
    ui.painter().hline(x, y, Stroke::new(1.0_f32, CARD_EDGE));
}
