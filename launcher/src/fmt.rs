//! Text for numbers and dates in the window (O552): bytes, speed, time left and relative dates, in pt-BR and en.
//! Pure functions, unit tested. pt-BR writes a decimal comma (`24,3 MB`), en a point (`24.3 MB`).
use crate::i18n::Lang;

fn decimal(v: f64, lang: Lang) -> String {
    let s = format!("{v:.1}");
    if lang == Lang::Pt {
        s.replace('.', ",")
    } else {
        s
    }
}

/// `1023` -> `1023 B`, `24_300_000` -> `24,3 MB`, `2_600_000_000` -> `2,6 GB` (decimal units, as download sites show them).
pub fn bytes(n: u64, lang: Lang) -> String {
    const K: f64 = 1000.0;
    let v = n as f64;
    if n < 1000 {
        format!("{n} B")
    } else if v < K * K {
        format!("{} KB", decimal(v / K, lang))
    } else if v < K * K * K {
        format!("{} MB", decimal(v / (K * K), lang))
    } else {
        format!("{} GB", decimal(v / (K * K * K), lang))
    }
}

/// Speed: `8,2 MB/s`.
pub fn rate(bytes_per_sec: f64, lang: Lang) -> String {
    format!("{}/s", bytes(bytes_per_sec.max(0.0) as u64, lang))
}

/// Time left: `5 min 25 s`, `1 h 02 min`, `40 s`.
pub fn duration(secs: u64) -> String {
    if secs >= 3600 {
        format!("{} h {:02} min", secs / 3600, secs % 3600 / 60)
    } else if secs >= 60 {
        format!("{} min {:02} s", secs / 60, secs % 60)
    } else {
        format!("{secs} s")
    }
}

/// `faltam 5 min 25 s` / `5 min 25 s left`.
pub fn time_left(secs: u64, lang: Lang) -> String {
    match lang {
        Lang::Pt => format!("faltam {}", duration(secs)),
        Lang::En => format!("{} left", duration(secs)),
    }
}

/// Days since 1970-01-01 of a `YYYY-MM-DD` date (proleptic Gregorian), None for anything else.
pub fn days_of(date: &str) -> Option<i64> {
    let b = date.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return None;
    }
    let num = |r: std::ops::Range<usize>| date.get(r)?.parse::<i64>().ok();
    let (y, m, d) = (num(0..4)?, num(5..7)?, num(8..10)?);
    if !(1..=12).contains(&m) || !(1..=31).contains(&d) {
        return None;
    }
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let mp = (m + 9) % 12;
    let doy = (153 * mp + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    Some(era * 146_097 + doe - 719_468)
}

/// Today as days since 1970-01-01 (UTC).
pub fn today() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| (d.as_secs() / 86_400) as i64)
        .unwrap_or(0)
}

/// `hoje`, `ontem`, `há 3 dias`, `semana passada`, `há 2 semanas`, then the date itself. A date in the future or one
/// that is not `YYYY-MM-DD` is shown as `show` gives it.
pub fn relative(date: &str, today: i64, lang: Lang) -> String {
    let Some(d) = days_of(date) else {
        return crate::feed::show_date(date, lang);
    };
    let ago = today - d;
    let pt = lang == Lang::Pt;
    match ago {
        i64::MIN..=-1 => crate::feed::show_date(date, lang),
        0 => (if pt { "hoje" } else { "today" }).into(),
        1 => (if pt { "ontem" } else { "yesterday" }).into(),
        2..=6 => {
            if pt {
                format!("há {ago} dias")
            } else {
                format!("{ago} days ago")
            }
        }
        7..=13 => (if pt { "semana passada" } else { "last week" }).into(),
        14..=34 => {
            let w = ago / 7;
            if pt {
                format!("há {w} semanas")
            } else {
                format!("{w} weeks ago")
            }
        }
        _ => crate::feed::show_date(date, lang),
    }
}

/// Moving speed over the last few seconds: feed it (time in seconds, bytes done) and read the rate.
#[derive(Debug, Default, Clone)]
pub struct Speed {
    samples: Vec<(f64, u64)>,
}

impl Speed {
    const WINDOW: f64 = 3.0;

    pub fn push(&mut self, t: f64, done: u64) {
        if self.samples.last().is_some_and(|&(_, d)| done < d) {
            self.samples.clear(); // a new run starts again at zero
        }
        self.samples.push((t, done));
        self.samples.retain(|&(s, _)| t - s <= Self::WINDOW);
    }

    pub fn clear(&mut self) {
        self.samples.clear();
    }

    /// Bytes per second over the window, None before two samples at least 0.5 s apart.
    pub fn rate(&self) -> Option<f64> {
        let (t0, d0) = *self.samples.first()?;
        let (t1, d1) = *self.samples.last()?;
        (t1 - t0 >= 0.5).then(|| (d1 - d0) as f64 / (t1 - t0))
    }

    /// Whole seconds left for `remaining` bytes, None when the rate is not known or zero.
    pub fn eta(&self, remaining: u64) -> Option<u64> {
        let r = self.rate().filter(|r| *r > 1.0)?;
        Some((remaining as f64 / r).ceil() as u64)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sizes_in_both_languages() {
        assert_eq!(bytes(999, Lang::Pt), "999 B");
        assert_eq!(bytes(24_300_000, Lang::Pt), "24,3 MB");
        assert_eq!(bytes(24_300_000, Lang::En), "24.3 MB");
        assert_eq!(bytes(2_600_000_000, Lang::Pt), "2,6 GB");
        assert_eq!(bytes(1_500, Lang::Pt), "1,5 KB");
        assert_eq!(rate(8_200_000.0, Lang::Pt), "8,2 MB/s");
        assert_eq!(rate(-5.0, Lang::Pt), "0 B/s");
    }

    #[test]
    fn durations() {
        assert_eq!(duration(40), "40 s");
        assert_eq!(duration(325), "5 min 25 s");
        assert_eq!(duration(3720), "1 h 02 min");
        assert_eq!(time_left(325, Lang::Pt), "faltam 5 min 25 s");
        assert_eq!(time_left(325, Lang::En), "5 min 25 s left");
    }

    #[test]
    fn dates_to_days() {
        assert_eq!(days_of("1970-01-01"), Some(0));
        assert_eq!(days_of("1970-01-02"), Some(1));
        assert_eq!(days_of("2000-03-01"), Some(11_017));
        assert_eq!(days_of("2026-11-13"), Some(20_770));
        for bad in [
            "",
            "2026-13-01",
            "2026-00-10",
            "2026/11/13",
            "26-11-13",
            "2026-11-1x",
            "2026-11-3",
        ] {
            assert_eq!(days_of(bad), None, "{bad}");
        }
    }

    #[test]
    fn relative_table_both_languages() {
        let t = days_of("2026-11-13").unwrap();
        let cases = [
            ("2026-11-13", "hoje", "today"),
            ("2026-11-12", "ontem", "yesterday"),
            ("2026-11-11", "há 2 dias", "2 days ago"),
            ("2026-11-07", "há 6 dias", "6 days ago"),
            ("2026-11-06", "semana passada", "last week"),
            ("2026-10-31", "semana passada", "last week"),
            ("2026-10-30", "há 2 semanas", "2 weeks ago"),
            ("2026-10-10", "há 4 semanas", "4 weeks ago"),
            ("2026-10-09", "09/10/2026", "2026-10-09"),
            ("2027-01-01", "01/01/2027", "2027-01-01"),
            ("soon", "soon", "soon"),
        ];
        for (d, pt, en) in cases {
            assert_eq!(relative(d, t, Lang::Pt), pt, "{d}");
            assert_eq!(relative(d, t, Lang::En), en, "{d}");
        }
    }

    #[test]
    fn speed_is_a_moving_average() {
        let mut s = Speed::default();
        assert_eq!(s.rate(), None);
        s.push(0.0, 0);
        assert_eq!(s.rate(), None);
        s.push(1.0, 1_000_000);
        s.push(2.0, 3_000_000);
        assert_eq!(s.rate(), Some(1_500_000.0));
        assert_eq!(s.eta(3_000_000), Some(2));
        // old samples fall out of the 3 s window
        s.push(10.0, 3_000_000);
        s.push(11.0, 4_000_000);
        assert_eq!(s.rate(), Some(1_000_000.0));
        // a counter that goes back starts a new run
        s.push(12.0, 0);
        s.push(13.0, 500_000);
        assert_eq!(s.rate(), Some(500_000.0));
        s.clear();
        assert_eq!(s.eta(10), None);
    }
}
