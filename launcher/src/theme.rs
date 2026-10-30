//! Look of the launcher window (O339): dark fantasy colours, the ember Play button, tabs, cards, the embedded art.
//! Only colours and drawing. No behaviour, no text (strings are in `i18n.rs`).
use eframe::egui::{
    self, epaint::Shadow, Color32, FontFamily, FontId, Pos2, Rect, Response, RichText, Sense, Stroke, TextStyle, Ui,
    Vec2,
};

/// Window colour. `launcher/tools/gen_launcher_art.py` fades the banner into the same value.
pub const BG: Color32 = Color32::from_rgb(14, 11, 10);
pub const CARD: Color32 = Color32::from_rgb(25, 20, 18);
pub const CARD_EDGE: Color32 = Color32::from_rgb(56, 42, 34);
pub const EMBER: Color32 = Color32::from_rgb(224, 78, 26);
pub const EMBER_HI: Color32 = Color32::from_rgb(250, 118, 44);
pub const EMBER_LO: Color32 = Color32::from_rgb(160, 48, 14);
pub const GOLD: Color32 = Color32::from_rgb(232, 190, 110);
pub const TEXT: Color32 = Color32::from_rgb(222, 212, 200);
pub const MUTED: Color32 = Color32::from_rgb(150, 136, 124);
pub const ERROR: Color32 = Color32::from_rgb(240, 98, 84);

/// The banner (960x300) and the window icon (128x128), raw RGBA made by `tools/gen_launcher_art.py`.
pub const BANNER_SIZE: [usize; 2] = [960, 300];
pub const ICON_SIZE: u32 = 128;
const BANNER_RGBA: &[u8] = include_bytes!("../assets/banner.rgba");
const ICON_RGBA: &[u8] = include_bytes!("../assets/icon.rgba");

pub fn icon() -> egui::IconData {
    egui::IconData {
        rgba: ICON_RGBA.to_vec(),
        width: ICON_SIZE,
        height: ICON_SIZE,
    }
}

pub fn banner(ctx: &egui::Context) -> egui::TextureHandle {
    let img = egui::ColorImage::from_rgba_unmultiplied(BANNER_SIZE, BANNER_RGBA);
    ctx.load_texture("banner", img, egui::TextureOptions::LINEAR)
}

/// Colours, spacing and text sizes for the whole window.
pub fn apply(ctx: &egui::Context) {
    let mut v = egui::Visuals::dark();
    v.panel_fill = BG;
    v.window_fill = CARD;
    v.extreme_bg_color = Color32::from_rgb(8, 6, 5);
    v.faint_bg_color = CARD;
    v.hyperlink_color = EMBER_HI;
    v.selection.bg_fill = EMBER_LO;
    v.selection.stroke = Stroke::new(1.0_f32, GOLD);
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
    v.widgets.hovered.bg_fill = Color32::from_rgb(66, 40, 30);
    v.widgets.hovered.weak_bg_fill = Color32::from_rgb(66, 40, 30);
    v.widgets.hovered.bg_stroke = Stroke::new(1.0_f32, EMBER);
    v.widgets.hovered.fg_stroke = Stroke::new(1.0_f32, GOLD);
    v.widgets.active.bg_fill = EMBER_LO;
    v.widgets.active.weak_bg_fill = EMBER_LO;
    v.widgets.active.bg_stroke = Stroke::new(1.0_f32, EMBER_HI);
    v.widgets.active.fg_stroke = Stroke::new(1.0_f32, Color32::WHITE);
    ctx.set_visuals(v);
    ctx.style_mut(|s| {
        s.spacing.item_spacing = Vec2::new(10.0, 8.0);
        s.spacing.button_padding = Vec2::new(14.0, 7.0);
        s.spacing.scroll.bar_width = 6.0;
        s.text_styles
            .insert(TextStyle::Body, FontId::new(15.0, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Button, FontId::new(15.0, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Small, FontId::new(12.5, FontFamily::Proportional));
        s.text_styles
            .insert(TextStyle::Heading, FontId::new(24.0, FontFamily::Proportional));
    });
}

/// A panel with a thin warm edge. The inside is up to the caller.
pub fn card(fill: Color32, edge: Color32) -> egui::Frame {
    egui::Frame::none()
        .fill(fill)
        .stroke(Stroke::new(1.0_f32, edge))
        .rounding(10.0)
        .inner_margin(egui::Margin::symmetric(16.0, 12.0))
}

pub fn card_title(text: &str) -> RichText {
    RichText::new(text).size(17.0).strong().color(GOLD)
}

/// The big ember Play button. `enabled == false` draws it cold and gives no click (the update is still running).
/// Returns true on a click.
pub fn play_button(ui: &mut Ui, label: &str, enabled: bool, size: Vec2) -> bool {
    let sense = if enabled { Sense::click() } else { Sense::hover() };
    let (rect, resp) = ui.allocate_exact_size(size, sense);
    if ui.is_rect_visible(rect) {
        let (top, bottom, edge, text) = if !enabled {
            (
                Color32::from_rgb(46, 37, 33),
                Color32::from_rgb(34, 28, 25),
                Color32::from_rgb(64, 52, 45),
                MUTED,
            )
        } else if resp.is_pointer_button_down_on() {
            (
                EMBER_LO,
                Color32::from_rgb(120, 34, 10),
                EMBER,
                Color32::from_rgb(255, 235, 205),
            )
        } else if resp.hovered() {
            (EMBER_HI, EMBER, GOLD, Color32::WHITE)
        } else {
            (EMBER, EMBER_LO, EMBER_HI, Color32::from_rgb(255, 240, 215))
        };
        let round = 10.0;
        if enabled {
            let glow = if resp.hovered() { 26.0 } else { 16.0 };
            ui.painter().add(
                Shadow {
                    offset: Vec2::ZERO,
                    blur: glow,
                    spread: 1.0,
                    color: Color32::from_rgba_unmultiplied(235, 80, 20, if resp.hovered() { 120 } else { 80 }),
                }
                .as_shape(rect, round),
            );
        }
        let p = ui.painter();
        let mid = Color32::from_rgb(
            ((top.r() as u16 + bottom.r() as u16) / 2) as u8,
            ((top.g() as u16 + bottom.g() as u16) / 2) as u8,
            ((top.b() as u16 + bottom.b() as u16) / 2) as u8,
        );
        p.rect_filled(rect, round, mid);
        // soft gloss on the upper half
        let gloss = Rect::from_min_max(
            rect.min + Vec2::splat(2.0),
            Pos2::new(rect.max.x - 2.0, rect.center().y),
        );
        let r = round - 2.0;
        let gloss_round = egui::Rounding {
            nw: r,
            ne: r,
            sw: 3.0,
            se: 3.0,
        };
        p.rect_filled(
            gloss,
            gloss_round,
            Color32::from_white_alpha(if enabled { 2 } else { 0 }),
        );
        p.rect_stroke(rect, round, Stroke::new(1.5_f32, edge));
        let font = FontId::new(24.0, FontFamily::Proportional);
        // dark shadow under the text keeps it readable on the bright fill
        if enabled {
            p.text(
                rect.center() + Vec2::new(0.0, 1.5),
                egui::Align2::CENTER_CENTER,
                label,
                font.clone(),
                Color32::from_black_alpha(120),
            );
        }
        p.text(rect.center(), egui::Align2::CENTER_CENTER, label, font, text);
    }
    if enabled {
        resp.clone().on_hover_cursor(egui::CursorIcon::PointingHand);
    }
    enabled && resp.clicked()
}

/// A tab: text with an ember underline when selected.
pub fn tab(ui: &mut Ui, selected: bool, label: &str) -> Response {
    let font = FontId::new(16.0, FontFamily::Proportional);
    let galley = ui.painter().layout_no_wrap(label.to_owned(), font, TEXT);
    let pad = Vec2::new(14.0, 8.0);
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
        p.rect_filled(rect, 6.0, Color32::from_rgb(30, 24, 21));
    }
    let galley = p.layout_no_wrap(label.to_owned(), FontId::new(16.0, FontFamily::Proportional), color);
    p.galley(rect.min + pad, galley, color);
    if selected {
        let y = rect.max.y - 1.0;
        p.line_segment(
            [Pos2::new(rect.min.x + 8.0, y), Pos2::new(rect.max.x - 8.0, y)],
            Stroke::new(2.5_f32, EMBER),
        );
    }
    resp.on_hover_cursor(egui::CursorIcon::PointingHand)
}
