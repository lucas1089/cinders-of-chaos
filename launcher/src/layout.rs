//! Where everything sits in the window (O552), in logical pixels of the fixed 1280x800 canvas. No drawing, no egui:
//! the window asks for rectangles and the tests prove that none overlaps another and that all fit. A screen smaller
//! than the canvas gets a scale factor (`scale_for`), so the numbers here never change.

pub const W: f32 = 1280.0;
pub const H: f32 = 800.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct R {
    pub x: f32,
    pub y: f32,
    pub w: f32,
    pub h: f32,
}

impl R {
    pub const fn new(x: f32, y: f32, w: f32, h: f32) -> R {
        R { x, y, w, h }
    }
    pub fn right(&self) -> f32 {
        self.x + self.w
    }
    pub fn bottom(&self) -> f32 {
        self.y + self.h
    }
    pub fn overlaps(&self, o: &R) -> bool {
        self.x < o.right() && o.x < self.right() && self.y < o.bottom() && o.y < self.bottom()
    }
    pub fn inside(&self, o: &R) -> bool {
        self.x >= o.x && self.y >= o.y && self.right() <= o.right() && self.bottom() <= o.bottom()
    }
}

pub const CARDS: usize = 4;
pub const RAIL: usize = 4;

#[derive(Debug, Clone)]
pub struct Layout {
    pub canvas: R,
    pub title_bar: R,
    /// Language pill, gear, minimize, close (the title bar's right side).
    pub lang: R,
    pub gear: R,
    pub minimize: R,
    pub close: R,
    pub crest: R,
    pub logo: R,
    /// The four link buttons on the left.
    pub rail: [R; RAIL],
    pub strip_title: R,
    pub strip_prev: R,
    pub strip_next: R,
    pub strip_counter: R,
    pub strip_dots: R,
    pub cards: [R; CARDS],
    pub bar: R,
    pub status: R,
    pub chip: R,
    pub progress: R,
    pub stats: R,
    pub play: R,
    /// The open card's reading panel, over the logo and the strip.
    pub detail: R,
}

pub fn layout() -> Layout {
    let rail_y = [112.0, 192.0, 272.0, 352.0];
    let card_w = 292.0;
    let mut cards = [R::new(0.0, 0.0, 0.0, 0.0); CARDS];
    for (i, c) in cards.iter_mut().enumerate() {
        *c = R::new(34.0 + i as f32 * (card_w + 14.0), 490.0, card_w, 154.0);
    }
    Layout {
        canvas: R::new(0.0, 0.0, W, H),
        title_bar: R::new(14.0, 14.0, 1252.0, 40.0),
        lang: R::new(1006.0, 19.0, 100.0, 30.0),
        gear: R::new(1120.0, 20.0, 28.0, 28.0),
        minimize: R::new(1170.0, 20.0, 28.0, 28.0),
        close: R::new(1214.0, 20.0, 28.0, 28.0),
        crest: R::new(574.0, 4.0, 132.0, 47.0),
        logo: R::new(360.0, 62.0, 560.0, 373.0),
        rail: rail_y.map(|y| R::new(34.0, y, 68.0, 68.0)),
        strip_title: R::new(34.0, 456.0, 600.0, 24.0),
        strip_prev: R::new(1008.0, 456.0, 28.0, 24.0),
        strip_counter: R::new(1038.0, 456.0, 76.0, 24.0),
        strip_next: R::new(1116.0, 456.0, 28.0, 24.0),
        strip_dots: R::new(1150.0, 456.0, 110.0, 24.0),
        cards,
        bar: R::new(20.0, 660.0, 1240.0, 120.0),
        status: R::new(56.0, 676.0, 560.0, 30.0),
        chip: R::new(680.0, 676.0, 220.0, 32.0),
        progress: R::new(56.0, 722.0, 820.0, 12.0),
        stats: R::new(56.0, 744.0, 820.0, 24.0),
        play: R::new(930.0, 676.0, 296.0, 88.0),
        detail: R::new(34.0, 70.0, 1212.0, 570.0),
    }
}

/// The scale that fits the canvas on a screen (logical points of the monitor). 1.0 when it fits; never above 1.
pub fn scale_for(screen_w: f32, screen_h: f32) -> f32 {
    if screen_w <= 0.0 || screen_h <= 0.0 {
        return 1.0;
    }
    // leave room for the task bar and the window shadow: 94% of the screen at most
    (screen_w * 0.94 / W).min(screen_h * 0.94 / H).clamp(0.5, 1.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn everything_is_inside_the_canvas() {
        let l = layout();
        let mut all = vec![
            l.title_bar,
            l.lang,
            l.gear,
            l.minimize,
            l.close,
            l.crest,
            l.logo,
            l.strip_title,
            l.strip_prev,
            l.strip_next,
            l.strip_counter,
            l.strip_dots,
            l.bar,
            l.status,
            l.chip,
            l.progress,
            l.stats,
            l.play,
            l.detail,
        ];
        all.extend(l.rail);
        all.extend(l.cards);
        for r in all {
            assert!(r.inside(&l.canvas), "{r:?}");
        }
    }

    fn none_overlap(rs: &[R]) {
        for (i, a) in rs.iter().enumerate() {
            for b in &rs[i + 1..] {
                assert!(!a.overlaps(b), "{a:?} overlaps {b:?}");
            }
        }
    }

    #[test]
    fn the_zones_do_not_overlap() {
        let l = layout();
        // title bar controls
        none_overlap(&[l.lang, l.gear, l.minimize, l.close]);
        for r in [l.lang, l.gear, l.minimize, l.close] {
            assert!(r.inside(&l.title_bar), "{r:?}");
        }
        // the middle: rail, logo, strip header, cards, bar
        let mut mid = vec![
            l.logo,
            l.strip_title,
            l.strip_prev,
            l.strip_counter,
            l.strip_next,
            l.strip_dots,
            l.bar,
        ];
        mid.extend(l.rail);
        mid.extend(l.cards);
        none_overlap(&mid);
        // the bar's parts
        let parts = [l.status, l.chip, l.progress, l.stats, l.play];
        none_overlap(&parts);
        for r in parts {
            assert!(r.inside(&l.bar), "{r:?}");
        }
        // the crest sits in the title bar's middle, clear of its controls
        assert!(!l.crest.overlaps(&l.lang) && !l.crest.overlaps(&l.gear));
    }

    #[test]
    fn the_cards_are_one_even_row() {
        let l = layout();
        for w in l.cards.windows(2) {
            assert_eq!(w[0].y, w[1].y);
            assert_eq!(w[1].x - w[0].right(), 14.0);
        }
        // the row ends at the same margin as the window frame on the left
        assert_eq!(l.cards[3].right(), 34.0 + 4.0 * 292.0 + 3.0 * 14.0);
        assert!(l.cards[3].right() <= l.bar.right());
    }

    #[test]
    fn the_logo_is_centred() {
        let l = layout();
        assert_eq!(l.logo.x + l.logo.w / 2.0, W / 2.0);
        assert_eq!(l.crest.x + l.crest.w / 2.0, W / 2.0);
    }

    #[test]
    fn scale_fits_the_screen() {
        assert_eq!(scale_for(1920.0, 1080.0), 1.0);
        let s = scale_for(1366.0, 768.0);
        assert!((s - 0.903).abs() < 0.01, "{s}");
        assert!(W * s <= 1366.0 && H * s <= 768.0);
        assert_eq!(scale_for(0.0, 0.0), 1.0);
        assert_eq!(scale_for(300.0, 200.0), 0.5);
    }
}
