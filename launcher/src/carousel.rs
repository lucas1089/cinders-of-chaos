//! The state of the news carousel (O552): which card is open, which four are on the strip, and the slow auto-advance.
//! No drawing and no clock of its own: the window passes the time in seconds. Unit tested.

/// Cards on the strip at once.
pub const VISIBLE: usize = 4;
/// Seconds an open card stays before the next one opens by itself.
pub const AUTO_SECS: f64 = 8.0;
/// Seconds without auto-advance after the player used an arrow, a dot or a card.
pub const IDLE_AFTER_USER: f64 = 24.0;

#[derive(Debug, Clone, PartialEq)]
pub struct Carousel {
    len: usize,
    sel: usize,
    first: usize,
    /// Time at which the next automatic step is due.
    due: f64,
}

impl Carousel {
    pub fn new(len: usize, now: f64) -> Carousel {
        Carousel {
            len,
            sel: 0,
            first: 0,
            due: now + AUTO_SECS,
        }
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    /// The open card.
    pub fn selected(&self) -> usize {
        self.sel
    }

    /// The first card on the strip; the strip shows `first .. first + VISIBLE` (fewer at the end of a short list).
    pub fn first(&self) -> usize {
        self.first
    }

    pub fn visible(&self) -> std::ops::Range<usize> {
        self.first..(self.first + VISIBLE).min(self.len)
    }

    /// `1 - 4 / 12` for the strip header: the visible range and the total.
    pub fn counter(&self) -> String {
        if self.len == 0 {
            return String::new();
        }
        let v = self.visible();
        format!("{} - {} / {}", v.start + 1, v.end, self.len)
    }

    fn follow(&mut self) {
        if self.sel < self.first {
            self.first = self.sel;
        } else if self.sel >= self.first + VISIBLE {
            self.first = self.sel + 1 - VISIBLE;
        }
    }

    /// The list changed (a fresh feed): keep the open card when it still exists.
    pub fn set_len(&mut self, len: usize) {
        self.len = len;
        if len == 0 {
            (self.sel, self.first) = (0, 0);
        } else {
            self.sel = self.sel.min(len - 1);
            self.first = self.first.min(len.saturating_sub(VISIBLE));
            self.follow();
        }
    }

    fn user(&mut self, now: f64) {
        self.due = now + IDLE_AFTER_USER;
    }

    pub fn select(&mut self, i: usize, now: f64) {
        if i < self.len {
            self.sel = i;
            self.follow();
        }
        self.user(now);
    }

    pub fn next(&mut self, now: f64) {
        if self.len > 0 {
            self.sel = (self.sel + 1) % self.len;
            self.follow();
        }
        self.user(now);
    }

    pub fn prev(&mut self, now: f64) {
        if self.len > 0 {
            self.sel = (self.sel + self.len - 1) % self.len;
            self.follow();
        }
        self.user(now);
    }

    /// Call every frame. Opens the next card when due, unless the mouse is over the carousel or a detail is open
    /// (`paused`); then the clock waits. Returns true when the open card changed.
    pub fn tick(&mut self, now: f64, paused: bool) -> bool {
        if self.len < 2 {
            return false;
        }
        if paused {
            self.due = now + AUTO_SECS;
            return false;
        }
        if now >= self.due {
            self.sel = (self.sel + 1) % self.len;
            self.follow();
            self.due = now + AUTO_SECS;
            return true;
        }
        false
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn next_and_prev_wrap() {
        let mut c = Carousel::new(6, 0.0);
        c.prev(0.0);
        assert_eq!((c.selected(), c.first()), (5, 2));
        c.next(0.0);
        assert_eq!((c.selected(), c.first()), (0, 0));
        for _ in 0..4 {
            c.next(0.0);
        }
        assert_eq!((c.selected(), c.first()), (4, 1));
        assert_eq!(c.visible(), 1..5);
    }

    #[test]
    fn counter_text() {
        let mut c = Carousel::new(12, 0.0);
        assert_eq!(c.counter(), "1 - 4 / 12");
        c.select(11, 0.0);
        assert_eq!(c.counter(), "9 - 12 / 12");
        assert_eq!(Carousel::new(2, 0.0).counter(), "1 - 2 / 2");
        assert_eq!(Carousel::new(0, 0.0).counter(), "");
    }

    #[test]
    fn auto_advance_waits_for_the_clock_and_pauses() {
        let mut c = Carousel::new(3, 0.0);
        assert!(!c.tick(7.9, false));
        assert!(c.tick(8.0, false));
        assert_eq!(c.selected(), 1);
        // paused: nothing moves, and the clock restarts when the pause ends
        assert!(!c.tick(20.0, true));
        assert!(!c.tick(27.0, false));
        assert!(c.tick(28.0, false));
        assert_eq!(c.selected(), 2);
    }

    #[test]
    fn a_user_action_gives_a_long_rest() {
        let mut c = Carousel::new(3, 0.0);
        c.next(5.0);
        assert_eq!(c.selected(), 1);
        assert!(!c.tick(28.9, false));
        assert!(c.tick(29.0, false));
    }

    #[test]
    fn short_lists_and_empty_lists() {
        let mut c = Carousel::new(1, 0.0);
        assert!(!c.tick(100.0, false));
        c.next(0.0);
        assert_eq!(c.selected(), 0);
        let mut e = Carousel::new(0, 0.0);
        e.next(0.0);
        e.prev(0.0);
        e.select(3, 0.0);
        assert_eq!((e.selected(), e.visible()), (0, 0..0));
        assert!(e.is_empty());
    }

    #[test]
    fn select_ignores_a_card_that_is_not_there() {
        let mut c = Carousel::new(5, 0.0);
        c.select(9, 0.0);
        assert_eq!(c.selected(), 0);
        c.select(4, 0.0);
        assert_eq!((c.selected(), c.first()), (4, 1));
    }

    #[test]
    fn a_new_feed_keeps_the_open_card_when_it_can() {
        let mut c = Carousel::new(12, 0.0);
        c.select(10, 0.0);
        c.set_len(6);
        assert_eq!((c.selected(), c.first()), (5, 2));
        c.set_len(0);
        assert_eq!((c.selected(), c.first()), (0, 0));
        c.set_len(3);
        assert_eq!(c.visible(), 0..3);
    }
}
