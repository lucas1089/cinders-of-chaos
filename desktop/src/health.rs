//! Saúde do jogo (O397): pure parsing of `chaos-ctl.sh game-health --kv --pt` (key=value lines of
//! server/tools/game_health.py), like android/.../GameHealthInfo.java. No I/O here; main.rs draws the bars.

/// A count the server hides because fewer than 5 characters are behind it ("<5"), else the number.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Small {
    N(u64),
    Hidden,
}

impl Small {
    fn of(s: &str) -> Small {
        if s.starts_with('<') {
            Small::Hidden
        } else {
            Small::N(s.trim().parse().unwrap_or(0))
        }
    }
    pub fn text(self) -> String {
        match self {
            Small::N(n) => n.to_string(),
            Small::Hidden => "<5".into(),
        }
    }
}

/// One hour of the window: mean and peak online (None: no sample), deaths.
#[derive(Clone, Debug, PartialEq)]
pub struct Hour {
    pub at: i64,
    pub day: String,
    pub hour: i32,
    pub mean: Option<f64>,
    pub peak: Option<u64>,
    pub deaths: u64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Hunt {
    pub visits: Small,
    pub hours: f64,
    pub kills: u64,
    pub deaths: u64,
    pub name: String,
}

/// A labelled row: gold (count = gold, extra = events) or the funnel (count, share).
#[derive(Clone, Debug, PartialEq)]
pub struct Row {
    pub label: String,
    pub count: Small,
    pub pct: Option<f64>,
    pub extra: u64,
}

#[derive(Clone, Debug, Default, PartialEq)]
pub struct Health {
    pub ok: bool,
    pub error: String,
    pub days: u32,
    pub online_mean: String,
    pub online_peak: String,
    pub online_peak_at: String,
    pub busiest_hour: Option<u32>,
    pub quietest_hour: Option<u32>,
    pub deaths_total: u64,
    pub deaths_per_hour: String,
    pub deaths_per_play_hour: String,
    pub hunts_known: u32,
    pub hunts_unvisited: u32,
    pub gold_in: i64,
    pub gold_out: i64,
    pub gold_net: i64,
    pub funnel_days: u32,
    pub funnel_characters: String,
    pub funnel_stopped: String,
    pub hours: Vec<Hour>,
    pub top: Vec<Hunt>,
    pub low: Vec<Hunt>,
    pub gold: Vec<Row>,
    pub reached: Vec<Row>,
    pub stop_level: Vec<Row>,
    pub stop_system: Vec<Row>,
}

fn opt_f(s: &str) -> Option<f64> {
    if s == "-" {
        None
    } else {
        s.parse().ok()
    }
}

/// The first n-1 parts split on spaces, the last one keeps its spaces (a hunt name); None when short.
fn fields(v: &str, n: usize) -> Option<Vec<&str>> {
    let p: Vec<&str> = v.trim().splitn(n, ' ').collect();
    if p.len() == n {
        Some(p)
    } else {
        None
    }
}

fn row(label: String, count: &str, pct: &str) -> Row {
    Row {
        label,
        count: Small::of(count),
        pct: opt_f(pct),
        extra: 0,
    }
}

/// "12,5%"
pub fn pct(v: Option<f64>) -> String {
    v.map(|x| format!("{x:.1}%").replace('.', ",")).unwrap_or_default()
}

/// 1234567 -> "1.234.567"
pub fn gold(v: i64) -> String {
    let s = v.unsigned_abs().to_string();
    let lead = s.len() % 3;
    let mut out = String::new();
    for (i, c) in s.chars().enumerate() {
        if i > 0 && i % 3 == lead {
            out.push('.');
        }
        out.push(c);
    }
    if v < 0 {
        format!("-{out}")
    } else {
        out
    }
}

impl Health {
    /// `game-health --kv`; None when the output is no report at all (an ssh or chaos-ctl error).
    pub fn parse(out: &str) -> Option<Health> {
        let mut h = Health {
            online_mean: "-".into(),
            online_peak: "-".into(),
            online_peak_at: "-".into(),
            deaths_per_hour: "-".into(),
            deaths_per_play_hour: "-".into(),
            funnel_days: 30,
            ..Health::default()
        };
        let mut any = false;
        for line in out.lines() {
            let Some((k, v)) = line.split_once('=') else {
                continue;
            };
            let v = v.trim();
            match k.trim() {
                "ok" => {
                    any = true;
                    h.ok = v == "1";
                }
                "error" => h.error = v.into(),
                "days" => h.days = v.parse().unwrap_or(0),
                "online_mean" => h.online_mean = v.into(),
                "online_peak" => h.online_peak = v.into(),
                "online_peak_at" => h.online_peak_at = v.into(),
                "online_busiest_hour" => h.busiest_hour = v.parse().ok(),
                "online_quietest_hour" => h.quietest_hour = v.parse().ok(),
                "deaths_total" => h.deaths_total = v.parse().unwrap_or(0),
                "deaths_per_hour" => h.deaths_per_hour = v.into(),
                "deaths_per_play_hour" => h.deaths_per_play_hour = v.into(),
                "hour" => {
                    if let Some(p) = fields(v, 6) {
                        if let Ok(at) = p[0].parse() {
                            h.hours.push(Hour {
                                at,
                                day: p[1].into(),
                                hour: p[2].parse().unwrap_or(-1),
                                mean: opt_f(p[3]),
                                peak: p[4].parse().ok(),
                                deaths: p[5].parse().unwrap_or(0),
                            });
                        }
                    }
                }
                "hunts_known" => h.hunts_known = v.parse().unwrap_or(0),
                "hunts_unvisited" => h.hunts_unvisited = v.parse().unwrap_or(0),
                k @ ("hunt_top" | "hunt_low") => {
                    if let Some(p) = fields(v, 5) {
                        let hunt = Hunt {
                            visits: Small::of(p[0]),
                            hours: p[1].parse().unwrap_or(0.0),
                            kills: p[2].parse().unwrap_or(0),
                            deaths: p[3].parse().unwrap_or(0),
                            name: p[4].into(),
                        };
                        if k == "hunt_top" {
                            h.top.push(hunt);
                        } else {
                            h.low.push(hunt);
                        }
                    }
                }
                "gold_in" => h.gold_in = v.parse().unwrap_or(0),
                "gold_out" => h.gold_out = v.parse().unwrap_or(0),
                "gold_net" => h.gold_net = v.parse().unwrap_or(0),
                "gold" => {
                    if let Some(p) = fields(v, 4) {
                        let side = if p[0] == "faucet" { "entra" } else { "sai" };
                        let mut r = row(format!("{side}: {}", p[3]), p[1], "-");
                        r.extra = p[2].parse().unwrap_or(0);
                        h.gold.push(r);
                    }
                }
                "funnel_days" => h.funnel_days = v.parse().unwrap_or(30),
                "funnel_characters" => h.funnel_characters = v.into(),
                "funnel_reached" => {
                    if let Some(p) = fields(v, 3) {
                        h.reached.push(row(format!("Nível {}", p[0]), p[1], p[2]));
                    }
                }
                "funnel_stopped" => {
                    if let Some(p) = fields(v, 3) {
                        let share = opt_f(p[2]).map(|x| format!(" ({})", pct(Some(x)))).unwrap_or_default();
                        h.funnel_stopped = format!("{} de {}{share}", p[0], p[1]);
                    }
                }
                "funnel_stop_level" => {
                    if let Some(p) = fields(v, 3) {
                        h.stop_level.push(row(format!("nível {}", p[2]), p[0], p[1]));
                    }
                }
                "funnel_stop_system" => {
                    if let Some(p) = fields(v, 3) {
                        h.stop_system.push(row(p[2].into(), p[0], p[1]));
                    }
                }
                _ => {}
            }
        }
        any.then_some(h)
    }

    /// The highest peak (or mean) of the window, at least 1: the chart's scale.
    pub fn max_online(&self) -> f64 {
        self.hours
            .iter()
            .map(|h| h.peak.map(|p| p as f64).unwrap_or(0.0).max(h.mean.unwrap_or(0.0)))
            .fold(1.0, f64::max)
    }

    /// Mean online per hour of the day (0 to 23); None where no sample.
    pub fn by_hour_of_day(&self) -> [Option<f64>; 24] {
        let mut sum = [0.0; 24];
        let mut n = [0u32; 24];
        for h in &self.hours {
            if let (Some(m), 0..=23) = (h.mean, h.hour) {
                sum[h.hour as usize] += m;
                n[h.hour as usize] += 1;
            }
        }
        let mut out = [None; 24];
        for ((o, s), c) in out.iter_mut().zip(sum).zip(n) {
            if c > 0 {
                *o = Some(s / c as f64);
            }
        }
        out
    }

    pub fn headline(&self) -> String {
        if !self.ok {
            return self.error_text();
        }
        format!(
            "Últimos {} dias: média de {} online, pico de {} ({}); {} mortes ({} por hora de jogo).",
            self.days,
            self.online_mean.replace('.', ","),
            self.online_peak,
            self.online_peak_at,
            self.deaths_total,
            self.deaths_per_play_hour.replace('.', ",")
        )
    }

    pub fn error_text(&self) -> String {
        match self.error.as_str() {
            "no-table" => "As tabelas da telemetria ainda não existem: rode o passo sql do install_all.py (ou reinicie o servidor).".into(),
            "database" => "Não deu para ler o banco de dados (está no ar?).".into(),
            "" => "Erro: resposta vazia".into(),
            e => format!("Erro: {e}"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const OUT: &str = "ok=1\ndays=7\nonline_mean=11.7\nonline_peak=25\nonline_peak_at=03/11 14h\n\
online_busiest_hour=14\nonline_quietest_hour=5\ndeaths_total=10\ndeaths_per_hour=3.33\ndeaths_per_play_hour=0.286\n\
hour=1790989200 03/11 13 10.0 14 4\nhour=1790992800 03/11 14 20.0 25 6\nhour=1790996400 03/11 15 - - 0\nhour=bad\n\
hunts_known=5\nhunts_unvisited=2\nhunt_top=40 10.0 900 7 Ashen Caves\nhunt_top=<5 0.3 50 0 Rift\n\
hunt_low=0 0.0 0 0 Bone Pits\ngold_in=520000\ngold_out=120000\ngold_net=-5\ngold=faucet 500000 300 loot\n\
gold=sink 120000 280 suprimentos\nfunnel_days=30\nfunnel_characters=60\nfunnel_reached=10 20 33.3\n\
funnel_reached=20 <5 -\nfunnel_stopped=48 60 80.0\nfunnel_stop_level=40 83.3 1-5\nfunnel_stop_system=8 16.7 Fenda\n";

    #[test]
    fn parses_the_kv_lines() {
        let h = Health::parse(OUT).unwrap();
        assert!(h.ok);
        assert_eq!(h.days, 7);
        assert_eq!(h.hours.len(), 3);
        assert_eq!(h.hours[1].mean, Some(20.0));
        assert_eq!(h.hours[1].peak, Some(25));
        assert_eq!(h.hours[1].deaths, 6);
        assert_eq!(h.hours[2].mean, None);
        assert_eq!(h.max_online(), 25.0);
        let hod = h.by_hour_of_day();
        assert_eq!(hod[14], Some(20.0));
        assert_eq!(hod[15], None);
        assert_eq!(h.top.len(), 2);
        assert_eq!(h.top[0].name, "Ashen Caves");
        assert_eq!(h.top[0].kills, 900);
        assert_eq!(h.top[1].visits, Small::Hidden);
        assert_eq!(h.top[1].visits.text(), "<5");
        assert_eq!(h.low[0].name, "Bone Pits");
        assert_eq!(h.gold_net, -5);
        assert_eq!(h.gold[1].label, "sai: suprimentos");
        assert_eq!(h.gold[1].extra, 280);
        assert_eq!(h.reached[1].count, Small::Hidden);
        assert_eq!(h.reached[1].pct, None);
        assert_eq!(h.funnel_stopped, "48 de 60 (80,0%)");
        assert_eq!(h.stop_level[0].label, "nível 1-5");
        assert_eq!(h.stop_system[0].label, "Fenda");
        assert!(h
            .headline()
            .starts_with("Últimos 7 dias: média de 11,7 online, pico de 25 (03/11 14h); 10 mortes"));
    }

    #[test]
    fn errors_and_noise() {
        let h = Health::parse("ok=0\nerror=no-table\n").unwrap();
        assert!(!h.ok);
        assert!(h.headline().contains("passo sql"));
        assert!(Health::parse("chaos-ctl: database-down").is_none());
        assert!(Health::parse("").is_none());
    }

    #[test]
    fn numbers() {
        assert_eq!(gold(1_234_567), "1.234.567");
        assert_eq!(gold(-1000), "-1.000");
        assert_eq!(gold(12), "12");
        assert_eq!(pct(Some(12.5)), "12,5%");
        assert_eq!(pct(None), "");
    }
}
