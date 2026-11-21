//! Look of the launcher window (O339, new look O552): colours, the game's ornate skin, fonts, icons and the small
//! drawing helpers. No behaviour and no text (strings are in `i18n.rs`, places in `layout.rs`).
//!
//! Everything is drawn with the painter in the 1280x800 canvas of `layout.rs`; `Cv` maps canvas pixels to the window
//! (a smaller screen scales the whole canvas). The art is embedded: `tools/gen_launcher_art.py` makes `assets/`.
use cinders_launcher::images;
use cinders_launcher::layout::R;
use eframe::egui::{
    self, epaint::Shadow, epaint::Vertex, Align2, Color32, FontFamily, FontId, Mesh, Painter, Pos2, Rect, Rounding,
    Stroke, TextureHandle, TextureOptions, Vec2,
};

pub const BG: Color32 = Color32::from_rgb(14, 11, 10);
pub fn card() -> Color32 {
    Color32::from_rgba_unmultiplied(16, 12, 11, 236)
}
pub const EDGE: Color32 = Color32::from_rgb(62, 46, 37);
pub const GOLD_LINE: Color32 = Color32::from_rgb(120, 88, 44);
pub const EMBER: Color32 = Color32::from_rgb(224, 78, 26);
pub const EMBER_HI: Color32 = Color32::from_rgb(250, 118, 44);
pub const EMBER_LO: Color32 = Color32::from_rgb(160, 48, 14);
pub const GOLD: Color32 = Color32::from_rgb(232, 190, 110);
pub const TEXT: Color32 = Color32::from_rgb(226, 216, 204);
pub const MUTED: Color32 = Color32::from_rgb(156, 142, 130);
pub const ERROR: Color32 = Color32::from_rgb(240, 98, 84);
pub const BLOOD: Color32 = Color32::from_rgb(150, 36, 24);

pub const ICON_SIZE: u32 = 128;
/// The title bar icon's size in canvas points.
pub const TITLE_ICON: f32 = 26.0;
const ICON_RGBA: &[u8] = include_bytes!("../assets/icon.rgba");

pub fn icon() -> egui::IconData {
    egui::IconData {
        rgba: ICON_RGBA.to_vec(),
        width: ICON_SIZE,
        height: ICON_SIZE,
    }
}

/// The family of the Cinzel weight 700 instance, used for titles, tags and the Play label.
pub fn title_family() -> FontFamily {
    FontFamily::Name("title".into())
}

pub fn install_fonts(ctx: &egui::Context) {
    let mut fonts = egui::FontDefinitions::default();
    fonts.font_data.insert(
        "alegreya".into(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/alegreya_sans.ttf")),
    );
    fonts.font_data.insert(
        "cinzel".into(),
        egui::FontData::from_static(include_bytes!("../assets/fonts/cinzel_bold.ttf")),
    );
    fonts
        .families
        .entry(FontFamily::Proportional)
        .or_default()
        .insert(0, "alegreya".into());
    fonts
        .families
        .insert(title_family(), vec!["cinzel".into(), "alegreya".into()]);
    ctx.set_fonts(fonts);
}

pub fn apply(ctx: &egui::Context) {
    install_fonts(ctx);
    let mut v = egui::Visuals::dark();
    v.panel_fill = BG;
    v.window_fill = BG;
    v.extreme_bg_color = Color32::from_rgb(8, 6, 5);
    v.hyperlink_color = EMBER_HI;
    v.selection.bg_fill = EMBER_LO;
    v.selection.stroke = Stroke::new(1.0_f32, GOLD);
    ctx.set_visuals(v);
    ctx.style_mut(|s| {
        s.spacing.scroll.bar_width = 5.0;
        s.spacing.scroll.floating = true;
    });
}

// ---------------------------------------------------------------- art

fn tex(ctx: &egui::Context, name: &str, bytes: &[u8], opt: TextureOptions) -> TextureHandle {
    let im = images::decode(bytes).unwrap_or(images::Rgba {
        w: 16,
        h: 16,
        rgba: vec![0; 16 * 16 * 4],
    });
    let ci = egui::ColorImage::from_rgba_unmultiplied([im.w, im.h], &im.rgba);
    ctx.load_texture(name, ci, opt)
}

/// The brand icon cut to twice its title bar size with a proper filter (the 128 px window icon shrunk by the graphics card
/// alone would alias).
fn title_icon(ctx: &egui::Context) -> TextureHandle {
    let n = (TITLE_ICON * 2.0) as u32;
    let big = image::RgbaImage::from_raw(ICON_SIZE, ICON_SIZE, ICON_RGBA.to_vec())
        .unwrap_or_else(|| image::RgbaImage::new(ICON_SIZE, ICON_SIZE));
    let small = image::imageops::resize(&big, n, n, image::imageops::FilterType::Lanczos3);
    let ci = egui::ColorImage::from_rgba_unmultiplied([n as usize, n as usize], small.as_raw());
    ctx.load_texture("title_icon", ci, TextureOptions::LINEAR)
}

/// A texture with its pixel size (for nine-slice maths).
pub struct Tex {
    pub h: TextureHandle,
    pub size: Vec2,
}

/// A skin picture. The art is drawn at twice the size it is shown at (O705), so it is filtered, not nearest-neighbour: a
/// 1x screen shrinks it by exactly 2, a 2x screen shows every pixel.
fn skin(ctx: &egui::Context, name: &str, bytes: &[u8]) -> Tex {
    let h = tex(ctx, name, bytes, TextureOptions::LINEAR);
    let size = h.size_vec2();
    Tex { h, size }
}

pub struct Art {
    /// The brand icon for the title bar, cut at 2x the 26 points it is shown at.
    pub icon: TextureHandle,
    pub hero: TextureHandle,
    pub logo: TextureHandle,
    pub corners: [Tex; 4],
    pub crest: Tex,
    pub btn: Tex,
    /// Default news pictures by `Tag::art()`: update, news, event, notice.
    pub news: [(&'static str, TextureHandle); 4],
}

impl Art {
    pub fn load(ctx: &egui::Context) -> Art {
        let lin = TextureOptions::LINEAR;
        let news = |n: &'static str, b: &[u8]| (n, tex(ctx, &format!("news_{n}"), b, lin));
        Art {
            icon: title_icon(ctx),
            hero: tex(ctx, "hero", include_bytes!("../assets/hero.jpg"), lin),
            logo: tex(ctx, "logo", include_bytes!("../assets/logo.png"), lin),
            corners: [
                skin(ctx, "c_tl", include_bytes!("../assets/skin_corner_tl.png")),
                skin(ctx, "c_tr", include_bytes!("../assets/skin_corner_tr.png")),
                skin(ctx, "c_bl", include_bytes!("../assets/skin_corner_bl.png")),
                skin(ctx, "c_br", include_bytes!("../assets/skin_corner_br.png")),
            ],
            crest: skin(ctx, "crest", include_bytes!("../assets/skin_crest.png")),
            btn: skin(ctx, "btn", include_bytes!("../assets/skin_btn.png")),
            news: [
                news("update", include_bytes!("../assets/news_update.jpg")),
                news("news", include_bytes!("../assets/news_news.jpg")),
                news("event", include_bytes!("../assets/news_event.jpg")),
                news("notice", include_bytes!("../assets/news_notice.jpg")),
            ],
        }
    }

    /// Draws the brand icon in the title bar, centred on `c` (26 canvas points wide) - the window has no frame of its own, so
    /// this is the icon the player sees on the window (O705).
    pub fn draw_icon(&self, p: &Painter, c: Pos2, k: f32) {
        p.image(
            self.icon.id(),
            Rect::from_center_size(c, Vec2::splat(TITLE_ICON * k)),
            Rect::from_min_max(Pos2::ZERO, Pos2::new(1.0, 1.0)),
            Color32::WHITE,
        );
    }

    pub fn default_news(&self, art: &str) -> &TextureHandle {
        self.news
            .iter()
            .find(|(n, _)| *n == art)
            .map(|(_, t)| t)
            .unwrap_or(&self.news[1].1)
    }
}

// ---------------------------------------------------------------- canvas

/// Maps the 1280x800 canvas to the window: `origin` is its top-left corner, `k` the scale.
#[derive(Clone, Copy)]
pub struct Cv {
    pub origin: Pos2,
    pub k: f32,
}

impl Cv {
    pub fn new(screen: Rect) -> Cv {
        Cv {
            origin: screen.min,
            k: screen.width() / cinders_launcher::layout::W,
        }
    }
    pub fn pt(&self, x: f32, y: f32) -> Pos2 {
        Pos2::new(self.origin.x + x * self.k, self.origin.y + y * self.k)
    }
    pub fn rect(&self, r: R) -> Rect {
        Rect::from_min_size(self.pt(r.x, r.y), Vec2::new(r.w * self.k, r.h * self.k))
    }
    pub fn px(&self, v: f32) -> f32 {
        v * self.k
    }
    pub fn font(&self, size: f32) -> FontId {
        FontId::new(size * self.k, FontFamily::Proportional)
    }
    pub fn title(&self, size: f32) -> FontId {
        FontId::new(size * self.k, title_family())
    }
}

// ---------------------------------------------------------------- drawing helpers

/// A textured rectangle from a part of a skin sprite (uv in 0..1).
fn quad(mesh: &mut Mesh, rect: Rect, uv: Rect, tint: Color32) {
    mesh.add_rect_with_uv(rect, uv, tint);
}

/// The button tile (`assets/skin_btn.png`, drawn by `tools/gen_launcher_art.py` at twice the size it is shown): the corner
/// is 14 texture pixels, shown 7 points wide, so one texture pixel is half a point (O705).
pub const BTN_BORDER: f32 = 14.0;
pub const BTN_SCALE: f32 = 0.5;

/// One axis of a nine-slice: the spans `(dest from, dest to, uv from, uv to)` that fill `d0..d1`. A corner is one span with
/// its whole uv range; the middle is cut into whole tiles of `tile` points, the last one cropped (never stretched), so the
/// plate keeps the pixel density it was drawn with at every size. `eps` keeps a bilinear lookup inside the tile.
pub fn axis_spans(d0: f32, d1: f32, u0: f32, u1: f32, tile: Option<f32>, eps: f32) -> Vec<(f32, f32, f32, f32)> {
    let Some(tile) = tile.filter(|t| *t > 0.5 && d1 - d0 > 0.0) else {
        return vec![(d0, d1, u0, u1)];
    };
    let (ua, ub) = (u0 + eps, u1 - eps);
    let mut out = Vec::new();
    let mut x = d0;
    while x < d1 - 0.01 {
        let e = (x + tile).min(d1);
        let f = (e - x) / tile;
        out.push((x, e, ua, ua + (ub - ua) * f));
        x = e;
    }
    out
}

/// Nine-slice of a skin picture: corners of `c` texture pixels drawn `scale` points per pixel, the edges and the middle
/// tiled at the same density (the picture's edges and middle are made to tile). Nothing is stretched or shrunk by
/// nearest-neighbour: at `scale` 0.5 and a 2x screen every texture pixel is a screen pixel (O705).
pub fn nine(p: &Painter, t: &Tex, rect: Rect, c: f32, scale: f32, tint: Color32) {
    let (sw, sh) = (t.size.x, t.size.y);
    let cs = (c * scale).min(rect.width() / 2.0).min(rect.height() / 2.0);
    let xs = [rect.min.x, rect.min.x + cs, rect.max.x - cs, rect.max.x];
    let ys = [rect.min.y, rect.min.y + cs, rect.max.y - cs, rect.max.y];
    let us = [0.0, c / sw, 1.0 - c / sw, 1.0];
    let vs = [0.0, c / sh, 1.0 - c / sh, 1.0];
    let (tw, th) = ((sw - 2.0 * c) * scale, (sh - 2.0 * c) * scale);
    let mut m = Mesh::with_texture(t.h.id());
    for j in 0..3 {
        let rows = axis_spans(ys[j], ys[j + 1], vs[j], vs[j + 1], (j == 1).then_some(th), 0.5 / sh);
        for i in 0..3 {
            let cols = axis_spans(xs[i], xs[i + 1], us[i], us[i + 1], (i == 1).then_some(tw), 0.5 / sw);
            for (y0, y1, v0, v1) in &rows {
                for (x0, x1, u0, u1) in &cols {
                    quad(
                        &mut m,
                        Rect::from_min_max(Pos2::new(*x0, *y0), Pos2::new(*x1, *y1)),
                        Rect::from_min_max(Pos2::new(*u0, *v0), Pos2::new(*u1, *v1)),
                        tint,
                    );
                }
            }
        }
    }
    p.add(m);
}

/// A button plate: the tile of the skin drawn 1:1 with the corner `BTN_BORDER` (7 points). `k` is the canvas scale.
pub fn button_plate(p: &Painter, art: &Art, rect: Rect, k: f32, tint: Color32) {
    nine(p, &art.btn, rect, BTN_BORDER, BTN_SCALE * k, tint);
}

/// A texture drawn to fill `rect`, cropped (not stretched) to the rectangle's shape.
pub fn cover(p: &Painter, t: &TextureHandle, rect: Rect, tint: Color32) {
    let s = t.size_vec2();
    let (ra, rt) = (rect.width() / rect.height(), s.x / s.y);
    let uv = if rt > ra {
        let w = ra / rt;
        Rect::from_min_max(Pos2::new((1.0 - w) / 2.0, 0.0), Pos2::new((1.0 + w) / 2.0, 1.0))
    } else {
        let h = rt / ra;
        Rect::from_min_max(Pos2::new(0.0, (1.0 - h) / 2.0), Pos2::new(1.0, (1.0 + h) / 2.0))
    };
    p.image(t.id(), rect, uv, tint);
}

/// Left to right gradient of two colours in a rectangle (square ends).
pub fn gradient_h(p: &Painter, rect: Rect, left: Color32, right: Color32) {
    let mut m = Mesh::default();
    let v = |pos: Pos2, color: Color32| Vertex {
        pos,
        uv: egui::epaint::WHITE_UV,
        color,
    };
    let i = m.vertices.len() as u32;
    m.vertices.push(v(rect.left_top(), left));
    m.vertices.push(v(rect.right_top(), right));
    m.vertices.push(v(rect.right_bottom(), right));
    m.vertices.push(v(rect.left_bottom(), left));
    m.indices.extend([i, i + 1, i + 2, i, i + 2, i + 3]);
    p.add(m);
}

/// Top to bottom gradient (used for the fades over pictures).
pub fn gradient_v(p: &Painter, rect: Rect, top: Color32, bottom: Color32) {
    let mut m = Mesh::default();
    let v = |pos: Pos2, color: Color32| Vertex {
        pos,
        uv: egui::epaint::WHITE_UV,
        color,
    };
    m.vertices.push(v(rect.left_top(), top));
    m.vertices.push(v(rect.right_top(), top));
    m.vertices.push(v(rect.right_bottom(), bottom));
    m.vertices.push(v(rect.left_bottom(), bottom));
    m.indices.extend([0, 1, 2, 0, 2, 3]);
    p.add(m);
}

/// Look of the big call-to-action button (Play, Install).
#[derive(Clone, Copy, PartialEq, Eq)]
pub enum BigBtn {
    Ready,
    Hover,
    Pressed,
    Off,
}

/// Corners of an octagon: `rect` with its four corners cut by `cut`, clockwise from the top-left.
fn octagon(rect: Rect, cut: f32) -> [Pos2; 8] {
    let (a, b) = (rect.min, rect.max);
    [
        Pos2::new(a.x + cut, a.y),
        Pos2::new(b.x - cut, a.y),
        Pos2::new(b.x, a.y + cut),
        Pos2::new(b.x, b.y - cut),
        Pos2::new(b.x - cut, b.y),
        Pos2::new(a.x + cut, b.y),
        Pos2::new(a.x, b.y - cut),
        Pos2::new(a.x, a.y + cut),
    ]
}

fn lerp_c(a: Color32, b: Color32, t: f32) -> Color32 {
    let t = t.clamp(0.0, 1.0);
    let m = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t).round() as u8;
    Color32::from_rgba_unmultiplied(m(a.r(), b.r()), m(a.g(), b.g()), m(a.b(), b.b()), m(a.a(), b.a()))
}

/// Octagon filled with a top to bottom gradient (a fan from the centre: exact for a linear gradient).
fn octagon_fill(p: &Painter, rect: Rect, cut: f32, top: Color32, bottom: Color32) {
    let col = |y: f32| lerp_c(top, bottom, (y - rect.min.y) / rect.height().max(1.0));
    let mut m = Mesh::default();
    let v = |pos: Pos2| Vertex {
        pos,
        uv: egui::epaint::WHITE_UV,
        color: col(pos.y),
    };
    m.vertices.push(v(rect.center()));
    for q in octagon(rect, cut) {
        m.vertices.push(v(q));
    }
    for i in 0..8u32 {
        m.indices.extend([0, 1 + i, 1 + (i + 1) % 8]);
    }
    p.add(m);
}

/// The big button, drawn smooth at any size: a cut-corner plate with a gradient, a soft sheen on the
/// upper half, a bright outer edge and a thin inner line. No stretched texture, so no banding.
pub fn big_button(p: &Painter, rect: Rect, k: f32, look: BigBtn) {
    let cut = (12.0 * k).min(rect.height() / 3.0);
    let (top, bottom, edge, inner) = match look {
        BigBtn::Ready => (
            Color32::from_rgb(132, 34, 18),
            Color32::from_rgb(46, 8, 6),
            Color32::from_rgb(236, 120, 64),
            Color32::from_rgba_unmultiplied(255, 196, 140, 70),
        ),
        BigBtn::Hover => (
            Color32::from_rgb(168, 48, 22),
            Color32::from_rgb(64, 12, 8),
            Color32::from_rgb(255, 160, 96),
            Color32::from_rgba_unmultiplied(255, 214, 170, 110),
        ),
        BigBtn::Pressed => (
            Color32::from_rgb(70, 14, 8),
            Color32::from_rgb(110, 26, 14),
            Color32::from_rgb(200, 96, 52),
            Color32::from_rgba_unmultiplied(255, 196, 140, 40),
        ),
        BigBtn::Off => (
            Color32::from_rgb(44, 38, 35),
            Color32::from_rgb(20, 17, 16),
            Color32::from_rgb(92, 80, 72),
            Color32::from_rgba_unmultiplied(160, 140, 124, 30),
        ),
    };
    // outer edge as a slightly bigger plate behind, then the body
    octagon_fill(p, rect, cut, edge, lerp_c(edge, bottom, 0.55));
    let body = rect.shrink(2.0 * k);
    octagon_fill(p, body, (cut - 0.8 * k).max(0.0), top, bottom);
    // sheen: the upper 45% fades from a faint light to nothing
    if look != BigBtn::Pressed {
        let sheen = Rect::from_min_max(body.min, Pos2::new(body.max.x, body.min.y + body.height() * 0.45));
        let a = if look == BigBtn::Off { 10 } else { 34 };
        octagon_top_sheen(p, body, sheen, (cut - 0.8 * k).max(0.0), a);
    }
    // thin inner line
    let inl = body.shrink(3.0 * k);
    let pts = octagon(inl, (cut - 2.5 * k).max(0.0)).to_vec();
    p.add(egui::Shape::closed_line(pts, Stroke::new(1.0 * k, inner)));
}

/// The sheen band: the octagon clipped to `band` (its top part), white fading to clear downwards.
fn octagon_top_sheen(p: &Painter, body: Rect, band: Rect, cut: f32, alpha: u8) {
    let o = octagon(body, cut);
    // the top part of the octagon: top edge corners, the side points at the band's bottom
    let yb = band.max.y;
    let side_x = |left: bool| {
        if yb >= body.min.y + cut {
            if left {
                body.min.x
            } else {
                body.max.x
            }
        } else {
            let d = cut - (yb - body.min.y);
            if left {
                body.min.x + d
            } else {
                body.max.x - d
            }
        }
    };
    let mut pts = vec![o[0], o[1]];
    if yb >= body.min.y + cut {
        pts.push(o[2]);
    }
    pts.push(Pos2::new(side_x(false), yb));
    pts.push(Pos2::new(side_x(true), yb));
    if yb >= body.min.y + cut {
        pts.push(o[7]);
    }
    let top = Color32::from_rgba_unmultiplied(255, 236, 214, alpha);
    let clear = Color32::from_rgba_unmultiplied(255, 236, 214, 0);
    let mut m = Mesh::default();
    let c = Pos2::new(body.center().x, (body.min.y + yb) / 2.0);
    let col = |y: f32| lerp_c(top, clear, (y - body.min.y) / (yb - body.min.y).max(1.0));
    m.vertices.push(Vertex {
        pos: c,
        uv: egui::epaint::WHITE_UV,
        color: col(c.y),
    });
    for q in &pts {
        m.vertices.push(Vertex {
            pos: *q,
            uv: egui::epaint::WHITE_UV,
            color: col(q.y),
        });
    }
    let n = pts.len() as u32;
    for i in 0..n {
        m.indices.extend([0, 1 + i, 1 + (i + 1) % n]);
    }
    p.add(m);
}

pub fn glow(p: &Painter, rect: Rect, round: f32, color: Color32, blur: f32) {
    p.add(
        Shadow {
            offset: Vec2::ZERO,
            blur,
            spread: 1.0,
            color,
        }
        .as_shape(rect, round),
    );
}

/// Text with letter spacing (egui has none): one glyph after the other.
pub fn tracked(p: &Painter, pos: Pos2, s: &str, font: FontId, color: Color32, track: f32, anchor: Align2) -> Rect {
    let galleys: Vec<_> = s
        .chars()
        .map(|c| p.layout_no_wrap(c.to_string(), font.clone(), color))
        .collect();
    let width: f32 = galleys.iter().map(|g| g.size().x).sum::<f32>() + track * (galleys.len().saturating_sub(1)) as f32;
    let h = galleys.iter().map(|g| g.size().y).fold(0.0_f32, f32::max);
    let x0 = match anchor.x() {
        egui::Align::Min => pos.x,
        egui::Align::Center => pos.x - width / 2.0,
        egui::Align::Max => pos.x - width,
    };
    let y0 = match anchor.y() {
        egui::Align::Min => pos.y,
        egui::Align::Center => pos.y - h / 2.0,
        egui::Align::Max => pos.y - h,
    };
    let mut x = x0;
    for g in galleys {
        let w = g.size().x;
        p.galley(Pos2::new(x, y0), g, color);
        x += w + track;
    }
    Rect::from_min_size(Pos2::new(x0, y0), Vec2::new(width, h))
}

pub fn text_width(p: &Painter, s: &str, font: FontId) -> f32 {
    p.layout_no_wrap(s.to_string(), font, Color32::WHITE).size().x
}

// ---------------------------------------------------------------- icons, drawn by hand (no icon pack)

fn st(w: f32, c: Color32) -> Stroke {
    Stroke::new(w, c)
}

pub fn ico_discord(p: &Painter, c: Pos2, s: f32, col: Color32) {
    let face = Rect::from_min_max(Pos2::new(c.x - s, c.y - s * 0.72), Pos2::new(c.x + s, c.y + s * 0.62));
    p.rect_filled(face, Rounding::same(s * 0.45), col);
    for ex in [-0.38, 0.38] {
        p.circle_filled(
            Pos2::new(c.x + ex * s, c.y - s * 0.05),
            s * 0.2,
            Color32::from_rgb(30, 24, 22),
        );
    }
    for sx in [-1.0, 1.0] {
        p.add(egui::Shape::convex_polygon(
            vec![
                Pos2::new(c.x + sx * s * 0.78, c.y + s * 0.5),
                Pos2::new(c.x + sx * s * 0.5, c.y + s * 0.95),
                Pos2::new(c.x + sx * s * 0.25, c.y + s * 0.55),
            ],
            col,
            Stroke::NONE,
        ));
    }
}

pub fn ico_globe(p: &Painter, c: Pos2, s: f32, col: Color32) {
    p.circle_stroke(c, s, st(s * 0.17, col));
    p.add(egui::Shape::ellipse_stroke(
        c,
        Vec2::new(s * 0.45, s),
        st(s * 0.15, col),
    ));
    p.line_segment([Pos2::new(c.x - s, c.y), Pos2::new(c.x + s, c.y)], st(s * 0.15, col));
    for dy in [-0.5, 0.5] {
        p.line_segment(
            [
                Pos2::new(c.x - s * 0.86, c.y + dy * s),
                Pos2::new(c.x + s * 0.86, c.y + dy * s),
            ],
            st(s * 0.12, col),
        );
    }
}

pub fn ico_book(p: &Painter, c: Pos2, s: f32, col: Color32) {
    let r = Rect::from_min_max(Pos2::new(c.x - s * 0.72, c.y - s), Pos2::new(c.x + s * 0.72, c.y + s));
    p.rect_stroke(r, Rounding::same(s * 0.25), st(s * 0.18, col));
    p.line_segment(
        [Pos2::new(c.x - s * 0.38, c.y - s), Pos2::new(c.x - s * 0.38, c.y + s)],
        st(s * 0.16, col),
    );
    for dy in [-0.35, 0.05] {
        p.line_segment(
            [
                Pos2::new(c.x - s * 0.05, c.y + dy * s),
                Pos2::new(c.x + s * 0.4, c.y + dy * s),
            ],
            st(s * 0.15, col),
        );
    }
}

pub fn ico_userplus(p: &Painter, c: Pos2, s: f32, col: Color32) {
    p.circle_stroke(Pos2::new(c.x - s * 0.25, c.y - s * 0.45), s * 0.42, st(s * 0.17, col));
    let mut pts = Vec::new();
    for i in 0..=12 {
        let a = std::f32::consts::PI + std::f32::consts::PI * i as f32 / 12.0;
        pts.push(Pos2::new(
            c.x - s * 0.25 + a.cos() * s * 0.75,
            c.y + s * 0.85 + a.sin() * s * 0.75,
        ));
    }
    p.add(egui::Shape::line(pts, st(s * 0.17, col)));
    p.line_segment(
        [
            Pos2::new(c.x + s * 0.55, c.y - s * 0.3),
            Pos2::new(c.x + s * 1.05, c.y - s * 0.3),
        ],
        st(s * 0.17, col),
    );
    p.line_segment(
        [
            Pos2::new(c.x + s * 0.8, c.y - s * 0.55),
            Pos2::new(c.x + s * 0.8, c.y - s * 0.05),
        ],
        st(s * 0.17, col),
    );
}

pub fn ico_gear(p: &Painter, c: Pos2, s: f32, col: Color32) {
    for k in 0..8 {
        let a = k as f32 * std::f32::consts::FRAC_PI_4;
        p.line_segment(
            [
                Pos2::new(c.x + a.cos() * s * 0.72, c.y + a.sin() * s * 0.72),
                Pos2::new(c.x + a.cos() * s * 1.02, c.y + a.sin() * s * 1.02),
            ],
            st(s * 0.3, col),
        );
    }
    p.circle_stroke(c, s * 0.78, st(s * 0.18, col));
    p.circle_stroke(c, s * 0.32, st(s * 0.17, col));
}

/// Direction `l`, `r` or `d`.
pub fn ico_chev(p: &Painter, c: Pos2, s: f32, col: Color32, dir: char) {
    let w = st((s * 0.32).max(1.4), col);
    let pts = match dir {
        'l' => vec![
            Pos2::new(c.x + s * 0.4, c.y - s),
            Pos2::new(c.x - s * 0.4, c.y),
            Pos2::new(c.x + s * 0.4, c.y + s),
        ],
        'r' => vec![
            Pos2::new(c.x - s * 0.4, c.y - s),
            Pos2::new(c.x + s * 0.4, c.y),
            Pos2::new(c.x - s * 0.4, c.y + s),
        ],
        _ => vec![
            Pos2::new(c.x - s, c.y - s * 0.35),
            Pos2::new(c.x, c.y + s * 0.35),
            Pos2::new(c.x + s, c.y - s * 0.35),
        ],
    };
    p.add(egui::Shape::line(pts, w));
}

pub fn ico_close(p: &Painter, c: Pos2, s: f32, col: Color32) {
    let w = st(s * 0.2, col);
    p.line_segment([Pos2::new(c.x - s, c.y - s), Pos2::new(c.x + s, c.y + s)], w);
    p.line_segment([Pos2::new(c.x + s, c.y - s), Pos2::new(c.x - s, c.y + s)], w);
}

pub fn ico_minimize(p: &Painter, c: Pos2, s: f32, col: Color32) {
    p.line_segment([Pos2::new(c.x - s, c.y), Pos2::new(c.x + s, c.y)], st(s * 0.2, col));
}

pub fn ico_play(p: &Painter, c: Pos2, s: f32, col: Color32) {
    p.add(egui::Shape::convex_polygon(
        vec![
            Pos2::new(c.x - s * 0.7, c.y - s),
            Pos2::new(c.x - s * 0.7, c.y + s),
            Pos2::new(c.x + s * 0.9, c.y),
        ],
        col,
        Stroke::NONE,
    ));
}

/// Eased value for hover glows and the progress bar: moves `cur` toward `target`, `rate` per second.
pub fn approach(cur: f32, target: f32, dt: f32, rate: f32) -> f32 {
    let d = target - cur;
    if d.abs() < 0.0005 {
        target
    } else {
        cur + d * (1.0 - (-rate * dt).exp())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn approach_reaches_its_target_and_never_overshoots() {
        let mut v = 0.0;
        for _ in 0..200 {
            let n = approach(v, 1.0, 0.016, 8.0);
            assert!(n >= v && n <= 1.0);
            v = n;
        }
        assert_eq!(v, 1.0);
        assert!(approach(1.0, 0.0, 0.016, 8.0) < 1.0);
        assert_eq!(approach(0.5, 0.5, 0.016, 8.0), 0.5);
    }

    #[test]
    fn a_corner_is_one_span_and_the_middle_is_tiled_not_stretched() {
        // corner: the whole uv range, once
        assert_eq!(axis_spans(0.0, 7.0, 0.0, 0.1, None, 0.003), vec![(0.0, 7.0, 0.0, 0.1)]);
        // middle of 100 points, tile 66: one whole tile and a cropped one, in order, no gap
        let s = axis_spans(7.0, 107.0, 0.1, 0.9, Some(66.0), 0.0);
        assert_eq!(s.len(), 2);
        assert_eq!((s[0].0, s[0].1), (7.0, 73.0));
        assert_eq!((s[1].0, s[1].1), (73.0, 107.0));
        // the whole tile spans the whole uv range, the last one only its share: the same density, nothing stretched
        assert!((s[0].2 - 0.1).abs() < 1e-6 && (s[0].3 - 0.9).abs() < 1e-6);
        let per_point = (s[0].3 - s[0].2) / (s[0].1 - s[0].0);
        let last = (s[1].3 - s[1].2) / (s[1].1 - s[1].0);
        assert!((per_point - last).abs() < 1e-6);
        // a middle shorter than one tile is one cropped tile; an empty one is nothing to draw
        assert_eq!(axis_spans(0.0, 10.0, 0.0, 1.0, Some(66.0), 0.0).len(), 1);
        assert_eq!(
            axis_spans(5.0, 5.0, 0.0, 1.0, Some(66.0), 0.0),
            vec![(5.0, 5.0, 0.0, 1.0)]
        );
    }

    #[test]
    fn the_button_tile_is_drawn_twice_the_size_it_is_shown_at() {
        // assets/skin_btn.png is 160 x 120 with 14 px corners, shown with the corner 7 points wide (O705)
        let png = include_bytes!("../assets/skin_btn.png");
        let im = cinders_launcher::images::decode(png).unwrap();
        assert_eq!((im.w, im.h), (160, 120));
        assert_eq!(BTN_BORDER * BTN_SCALE, 7.0);
        let corner = cinders_launcher::images::decode(include_bytes!("../assets/skin_corner_tl.png")).unwrap();
        assert_eq!((corner.w, corner.h), (108, 108), "shown at 54 points");
        let crest = cinders_launcher::images::decode(include_bytes!("../assets/skin_crest.png")).unwrap();
        assert_eq!((crest.w, crest.h), (264, 94), "shown at 132 x 47 points");
    }
}
