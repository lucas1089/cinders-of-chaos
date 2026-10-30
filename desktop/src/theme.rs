//! Look of the admin window (O344): the launcher's dark fantasy family (warm black, ember accent, gold headings),
//! tightened for a dense tool. Only colours and drawing. No behaviour, no text (strings are in `main.rs`).
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
    v.window_rounding = egui::Rounding::same(10.0);
    v.extreme_bg_color = INPUT;
    v.faint_bg_color = Color32::from_rgb(20, 16, 14);
    v.hyperlink_color = EMBER_HI;
    v.selection.bg_fill = EMBER_LO;
    v.selection.stroke = Stroke::new(1.0_f32, GOLD);
    v.override_text_color = None;
    let r = egui::Rounding::same(6.0);
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
    v.widgets.hovered.bg_fill = Color32::from_rgb(66, 40, 30);
    v.widgets.hovered.weak_bg_fill = Color32::from_rgb(66, 40, 30);
    v.widgets.hovered.bg_stroke = Stroke::new(1.0_f32, EMBER);
    v.widgets.hovered.fg_stroke = Stroke::new(1.0_f32, GOLD);
    v.widgets.active.bg_fill = EMBER_LO;
    v.widgets.active.weak_bg_fill = EMBER_LO;
    v.widgets.active.bg_stroke = Stroke::new(1.0_f32, EMBER_HI);
    v.widgets.active.fg_stroke = Stroke::new(1.0_f32, Color32::WHITE);
    v.widgets.open.bg_fill = Color32::from_rgb(40, 31, 27);
    v.widgets.open.weak_bg_fill = Color32::from_rgb(40, 31, 27);
    v.widgets.open.bg_stroke = Stroke::new(1.0_f32, EMBER);
    ctx.set_visuals(v);
    ctx.style_mut(|s| {
        s.spacing.item_spacing = Vec2::new(8.0, 6.0);
        s.spacing.button_padding = Vec2::new(11.0, 4.0);
        s.spacing.interact_size.y = 26.0;
        s.spacing.scroll.bar_width = 6.0;
        s.spacing.indent = 16.0;
        s.text_styles
            .insert(TextStyle::Body, FontId::new(14.5, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Button, FontId::new(14.5, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Small, FontId::new(12.5, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Monospace, FontId::new(13.0, FontFamily::Monospace));
        s.text_styles
            .insert(TextStyle::Heading, FontId::new(22.0, FontFamily::Proportional));
    });
}

/// A panel with a thin warm edge. The inside is up to the caller.
pub fn card() -> egui::Frame {
    egui::Frame::none()
        .fill(CARD)
        .stroke(Stroke::new(1.0_f32, CARD_EDGE))
        .rounding(10.0)
        .inner_margin(egui::Margin::symmetric(14.0, 10.0))
}

/// A dark well for logs and command output.
pub fn well() -> egui::Frame {
    egui::Frame::none()
        .fill(INPUT)
        .stroke(Stroke::new(1.0_f32, CARD_EDGE))
        .rounding(8.0)
        .inner_margin(egui::Margin::symmetric(10.0, 6.0))
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

pub fn card_title(text: &str) -> RichText {
    RichText::new(text).size(16.5).strong().color(GOLD)
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
        w.hovered.bg_stroke = Stroke::new(1.0_f32, GOLD);
        w.active.weak_bg_fill = EMBER_LO;
        w.active.bg_fill = EMBER_LO;
        let r = ui.add(egui::Button::new(RichText::new(label).color(text).strong()));
        r.on_hover_cursor(egui::CursorIcon::PointingHand)
    })
    .inner
}

/// The ember button: the one main action of a card (Salvar, Executar, update).
pub fn primary_button(ui: &mut Ui, label: &str) -> Response {
    coloured_button(ui, label, (EMBER, EMBER_HI, EMBER_HI, Color32::from_rgb(255, 240, 215)))
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

/// A tab: text with an ember underline when selected.
pub fn tab(ui: &mut Ui, selected: bool, label: &str) -> Response {
    let font = FontId::new(15.0, FontFamily::Proportional);
    let galley = ui.painter().layout_no_wrap(label.to_owned(), font.clone(), TEXT);
    let pad = Vec2::new(13.0, 7.0);
    let (rect, resp) = ui.allocate_exact_size(galley.size() + pad * 2.0, Sense::click());
    let color = if selected {
        GOLD
    } else if resp.hovered() {
        TEXT
    } else {
        MUTED
    };
    let p = ui.painter();
    if resp.hovered() && !selected {
        p.rect_filled(rect.shrink2(Vec2::new(0.0, 2.0)), 6.0, Color32::from_rgb(30, 24, 21));
    }
    let galley = p.layout_no_wrap(label.to_owned(), font, color);
    p.galley(rect.min + pad, galley, color);
    if selected {
        let y = rect.max.y;
        p.line_segment(
            [Pos2::new(rect.min.x + 6.0, y), Pos2::new(rect.max.x - 6.0, y)],
            Stroke::new(2.5_f32, EMBER),
        );
    }
    resp.on_hover_cursor(egui::CursorIcon::PointingHand)
}

/// A hairline across the width, under the tab bar.
pub fn rule(ui: &mut Ui) {
    let y = ui.cursor().min.y;
    let x = ui.max_rect().x_range();
    ui.painter().hline(x, y, Stroke::new(1.0_f32, CARD_EDGE));
}
