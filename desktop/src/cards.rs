//! Status, players and metrics cards of the Painel tab (O312). Pure parsing of the `chaos-ctl.sh status`, `players` and
//! `metrics --json` output, like android/.../StatusInfo.java, MetricsInfo.java and PanelTab.showPlayers. No I/O here.
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Online,
    OnlineNoUnit,
    Starting,
    Stopping,
    Offline,
    Failed,
    NoUnit,
    Unknown,
}

impl State {
    pub fn badge(self) -> &'static str {
        match self {
            State::Online => "NO AR",
            State::OnlineNoUnit => "NO AR, SEM SERVIÇO",
            State::Starting => "LIGANDO",
            State::Stopping => "DESLIGANDO",
            State::Offline => "PARADO",
            State::Failed => "FALHOU",
            State::NoUnit => "SEM SERVIÇO",
            State::Unknown => "?",
        }
    }
}

/// The key=value lines of `chaos-ctl.sh status`.
#[derive(Clone, Debug, Default)]
pub struct Status {
    kv: BTreeMap<String, String>,
}

impl Status {
    pub fn parse(out: &str) -> Status {
        let mut kv = BTreeMap::new();
        for line in out.lines() {
            if let Some((k, v)) = line.split_once('=') {
                if !k.is_empty() && k.bytes().all(|b| b.is_ascii_lowercase() || b == b'_') {
                    kv.insert(k.to_string(), v.trim().to_string());
                }
            }
        }
        Status { kv }
    }

    pub fn valid(&self) -> bool {
        self.kv.contains_key("service")
    }

    pub fn get(&self, k: &str) -> &str {
        self.kv.get(k).map(String::as_str).unwrap_or("")
    }

    pub fn state(&self) -> State {
        let pid = !self.get("pid").is_empty();
        if self.get("unit_state") == "not-found" {
            return if pid { State::OnlineNoUnit } else { State::NoUnit };
        }
        match self.get("service") {
            "active" | "reloading" => State::Online,
            "activating" => State::Starting,
            "deactivating" => State::Stopping,
            "failed" => State::Failed,
            "inactive" if pid => State::OnlineNoUnit,
            "inactive" => State::Offline,
            _ => State::Unknown,
        }
    }

    /// Unix seconds since the unit became active. systemd prints "Tue 2026-10-20 06:00:01 UTC" (also "+0200" offsets).
    pub fn since_unix(&self) -> Option<i64> {
        parse_since(self.get("since"))
    }

    pub fn uptime_sec(&self, now: i64) -> Option<i64> {
        self.since_unix().map(|s| (now - s).max(0))
    }

    /// "used/total MB" as percent 0..100.
    pub fn mem_percent(&self) -> Option<u8> {
        let (u, t) = two_numbers(self.get("mem"))?;
        (t > 0).then(|| (u * 100 / t).min(100) as u8)
    }

    /// "3.1G/40G (8%)" as 8.
    pub fn disk_percent(&self) -> Option<u8> {
        let d = self.get("disk");
        let a = d.find('(')? + 1;
        let b = d[a..].find('%')? + a;
        d[a..b].trim().parse::<u8>().ok().map(|p| p.min(100))
    }

    pub fn mem_text(&self) -> String {
        match two_numbers(self.get("mem")) {
            Some((u, t)) => format!("{} de {}", mb_text(u), mb_text(t)),
            None => dash(self.get("mem")),
        }
    }

    pub fn disk_text(&self) -> String {
        let d = self.get("disk");
        let used = d.split(" (").next().unwrap_or(d);
        let parts: Vec<&str> = used.split('/').collect();
        if parts.len() == 2 {
            format!("{} de {}", parts[0], parts[1])
        } else {
            dash(d)
        }
    }

    pub fn load_text(&self) -> String {
        let l: Vec<&str> = self.get("load").split_whitespace().collect();
        if l.len() >= 3 {
            format!("{}  {}  {}", l[0], l[1], l[2])
        } else {
            dash(self.get("load"))
        }
    }

    pub fn players_text(&self) -> String {
        let p = self.get("players");
        if !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()) {
            p.to_string()
        } else {
            "?".into()
        }
    }

    pub fn backup_text(&self) -> String {
        match self.get("backup") {
            "" | "none" => "nenhum".into(),
            b => b.to_string(),
        }
    }

    pub fn errors(&self) -> Option<u32> {
        self.get("errors").parse().ok()
    }
}

fn dash(s: &str) -> String {
    if s.is_empty() {
        "?".into()
    } else {
        s.to_string()
    }
}

fn two_numbers(s: &str) -> Option<(u64, u64)> {
    let (a, b) = s.split_once('/')?;
    let num = |t: &str| {
        let d: String = t.trim().chars().take_while(|c| c.is_ascii_digit()).collect();
        d.parse::<u64>().ok()
    };
    Some((num(a)?, num(b)?))
}

fn mb_text(mb: u64) -> String {
    if mb >= 1024 {
        format!("{:.1} GB", mb as f64 / 1024.0)
    } else {
        format!("{mb} MB")
    }
}

fn days_from_civil(y: i64, m: i64, d: i64) -> i64 {
    let y = if m <= 2 { y - 1 } else { y };
    let era = y.div_euclid(400);
    let yoe = y - era * 400;
    let doy = (153 * (m + if m > 2 { -3 } else { 9 }) + 2) / 5 + d - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

fn parse_since(s: &str) -> Option<i64> {
    if s.is_empty() || s.starts_with("n/a") {
        return None;
    }
    let mut date = None;
    let mut time = None;
    let mut off = 0i64;
    for w in s.split_whitespace() {
        if w.len() == 10 && w.as_bytes()[4] == b'-' {
            let p: Vec<i64> = w.split('-').filter_map(|x| x.parse().ok()).collect();
            if p.len() == 3 {
                date = Some((p[0], p[1], p[2]));
            }
        } else if w.contains(':') {
            let p: Vec<i64> = w.split(':').filter_map(|x| x.parse().ok()).collect();
            if p.len() == 3 {
                time = Some(p[0] * 3600 + p[1] * 60 + p[2]);
            }
        } else if (w.starts_with('+') || w.starts_with('-')) && w.len() == 5 {
            let sign = if w.starts_with('-') { -1 } else { 1 };
            let h: i64 = w[1..3].parse().ok()?;
            let m: i64 = w[3..5].parse().ok()?;
            off = sign * (h * 3600 + m * 60);
        }
        // weekday names and zone names (UTC) are ignored; a named zone other than UTC is read as UTC
    }
    let (y, m, d) = date?;
    Some(days_from_civil(y, m, d) * 86_400 + time.unwrap_or(0) - off)
}

/// "2d 3h 4min" style span.
pub fn duration(sec: i64) -> String {
    let s = sec.max(0);
    let (d, h, m) = (s / 86_400, s % 86_400 / 3600, s % 3600 / 60);
    if d > 0 {
        format!("{d}d {h}h {m}min")
    } else if h > 0 {
        format!("{h}h {m}min")
    } else {
        format!("{m}min")
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Player {
    pub name: String,
    pub level: String,
    pub vocation: String,
}

/// `chaos-ctl.sh players`: one `name<TAB>level<TAB>vocation` line per player. Other non-empty lines are skipped.
pub fn parse_players(out: &str) -> Vec<Player> {
    out.lines()
        .filter_map(|l| {
            let p: Vec<&str> = l.split('\t').collect();
            (p.len() >= 3 && !p[0].trim().is_empty()).then(|| Player {
                name: p[0].trim().into(),
                level: p[1].trim().into(),
                vocation: p[2].trim().into(),
            })
        })
        .collect()
}

/// A count the server hides because fewer than 5 players are behind it (it sends the text "<5").
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Count {
    N(u64),
    Small,
}

impl Count {
    fn of(o: &Value, key: &str) -> Count {
        match o.get(key) {
            Some(Value::String(_)) => Count::Small,
            Some(v) => Count::N(v.as_u64().unwrap_or(0)),
            None => Count::N(0),
        }
    }
    pub fn text(self) -> String {
        match self {
            Count::N(n) => n.to_string(),
            Count::Small => "<5".into(),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct Band {
    pub band: String,
    pub gone: Count,
    pub active: Count,
    pub gone_pct: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Killer {
    pub name: String,
    pub count: Count,
    pub top_band: String,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Bucket {
    pub bucket: String,
    pub characters: Count,
    pub pct: Option<f64>,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Milestone {
    pub level: u32,
    pub median_minutes: Option<f64>,
    pub characters: Count,
}

#[derive(Clone, Debug, PartialEq)]
pub struct Week {
    pub week: String,
    pub cohort: Count,
    pub pct: [Option<f64>; 3],
}

#[derive(Clone, Debug, PartialEq)]
pub struct FirstUse {
    pub system: String,
    pub characters: Count,
    pub pct: Option<f64>,
    pub median_minutes: Option<f64>,
    pub top_band: String,
}

/// `chaos-ctl.sh metrics --json`: anonymous aggregate counters only.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Metrics {
    pub ok: bool,
    pub error: String,
    pub empty: bool,
    pub churn_days: u32,
    pub gone: Option<Count>,
    pub active: Option<Count>,
    pub bands: Vec<Band>,
    pub areas: Vec<Killer>,
    pub monsters: Vec<Killer>,
    pub stops: Vec<Killer>,
    pub session_characters: Option<Count>,
    pub sessions: Vec<Bucket>,
    pub milestones: Vec<Milestone>,
    pub weeks: Vec<Week>,
    pub first_uses: Vec<FirstUse>,
}

fn s(o: &Value, k: &str) -> String {
    o.get(k).and_then(Value::as_str).unwrap_or("").to_string()
}
fn f(o: &Value, k: &str) -> Option<f64> {
    o.get(k).and_then(Value::as_f64)
}
fn arr<'a>(o: &'a Value, k: &str) -> impl Iterator<Item = &'a Value> {
    o.get(k).and_then(Value::as_array).into_iter().flatten()
}
fn killers(o: &Value, k: &str, field: &str) -> Vec<Killer> {
    arr(o, k)
        .map(|b| Killer {
            name: s(b, "name"),
            count: Count::of(b, field),
            top_band: s(b, "topBand"),
        })
        .collect()
}

impl Metrics {
    /// Reads the one JSON line (ssh banners and other lines are skipped); None when there is none.
    pub fn parse(out: &str) -> Option<Metrics> {
        out.lines()
            .map(str::trim)
            .filter(|l| l.starts_with('{'))
            .find_map(|l| serde_json::from_str::<Value>(l).ok())
            .map(|v| Metrics::from_json(&v))
    }

    pub fn from_json(o: &Value) -> Metrics {
        let mut m = Metrics {
            ok: o.get("ok").and_then(Value::as_bool).unwrap_or(false),
            error: s(o, "error"),
            ..Metrics::default()
        };
        if !m.ok {
            return m;
        }
        m.empty = o.get("empty").and_then(Value::as_bool).unwrap_or(false);
        if let Some(c) = o.get("churn") {
            m.churn_days = c.get("days").and_then(Value::as_u64).unwrap_or(0) as u32;
            m.gone = Some(Count::of(c, "gone"));
            m.active = Some(Count::of(c, "active"));
            m.bands = arr(c, "bands")
                .map(|b| Band {
                    band: s(b, "band"),
                    gone: Count::of(b, "gone"),
                    active: Count::of(b, "active"),
                    gone_pct: f(b, "gonePct"),
                })
                .collect();
        }
        m.areas = killers(o, "deathAreas", "deaths");
        m.monsters = killers(o, "deathMonsters", "deaths");
        m.stops = killers(o, "stops", "gone");
        m.weeks = arr(o, "returns")
            .map(|b| Week {
                week: s(b, "week"),
                cohort: Count::of(b, "cohort"),
                pct: [f(b, "d1Pct"), f(b, "d3Pct"), f(b, "d7Pct")],
            })
            .collect();
        m.first_uses = arr(o, "firstUse")
            .map(|b| FirstUse {
                system: s(b, "system"),
                characters: Count::of(b, "characters"),
                pct: f(b, "pct"),
                median_minutes: f(b, "medianMinutes"),
                top_band: s(b, "topBand"),
            })
            .collect();
        if o.get("firstSessionCharacters").is_some() {
            m.session_characters = Some(Count::of(o, "firstSessionCharacters"));
        }
        m.sessions = arr(o, "firstSession")
            .map(|b| Bucket {
                bucket: s(b, "bucket"),
                characters: Count::of(b, "characters"),
                pct: f(b, "pct"),
            })
            .collect();
        m.milestones = arr(o, "milestones")
            .map(|b| Milestone {
                level: b.get("level").and_then(Value::as_u64).unwrap_or(0) as u32,
                median_minutes: f(b, "medianMinutes"),
                characters: Count::of(b, "characters"),
            })
            .collect();
        m
    }

    /// Why the numbers could not be read, in Portuguese.
    pub fn error_text(&self) -> String {
        match self.error.as_str() {
            "no-table" => "A tabela de métricas ainda não existe. Atualize o servidor (passo sql do install_all.py) e reinicie; ela se enche com o jogo.".into(),
            "database" => "Não consegui ler o banco de dados do servidor.".into(),
            "" => "Resposta inesperada do servidor.".into(),
            e => format!("Resposta inesperada do servidor ({e})."),
        }
    }
}

/// A system of the first-use list in Portuguese; an unknown key is shown as it is.
pub fn system_name(key: &str) -> &str {
    match key {
        "dungeon" => "Masmorra",
        "rift" => "Fenda",
        "waystone" => "Pedra-guia",
        "tower" => "Torre Infinita",
        "pocketboss" => "Chefe de bolso",
        "worldboss" => "Chefe mundial",
        "invasion" => "Invasão",
        "party" => "Grupo",
        "guild" => "Guilda",
        "market" => "Mercado",
        "bounty" => "Contrato de caça",
        "craft" => "Criação",
        other => other,
    }
}

/// "12,5%"; "<5" for a hidden share.
pub fn pct(v: Option<f64>) -> String {
    match v {
        Some(v) if v >= 0.0 => format!("{v:.1}%").replace('.', ","),
        _ => "<5".into(),
    }
}

/// 15 min, 3,5 h, 2,0 dias; "sem dados" for none.
pub fn minutes(m: Option<f64>) -> String {
    match m {
        Some(m) if m >= 0.0 => {
            if m < 90.0 {
                format!("{} min", m.round() as i64)
            } else if m < 48.0 * 60.0 {
                format!("{:.1} h", m / 60.0).replace('.', ",")
            } else {
                format!("{:.1} dias", m / 1440.0).replace('.', ",")
            }
        }
        _ => "sem dados".into(),
    }
}

/// "até 30 min" or "mais de 480 min" for a first-session bucket (the last one is "inf").
pub fn bucket_text(bucket: &str, previous: &str) -> String {
    if bucket == "inf" {
        if previous.is_empty() {
            "mais longa".into()
        } else {
            format!("mais de {previous} min")
        }
    } else {
        format!("até {bucket} min")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Synthetic fixtures only: no real account, character or log data.
    const STATUS: &str = "banner line\nservice=active\nunit=chaos-server\nunit_state=loaded\npid=1234\n\
        since=Tue 2026-10-20 06:00:01 UTC\nplayers=7\nerrors=3\nmem=2048/8192\ndisk=3.1G/40G (8%)\n\
        load=0.10 0.20 0.30\nbackup=2026-10-19 03:00\n";

    #[test]
    fn status_fields() {
        let s = Status::parse(STATUS);
        assert!(s.valid());
        assert_eq!(s.state(), State::Online);
        assert_eq!(s.players_text(), "7");
        assert_eq!(s.errors(), Some(3));
        assert_eq!(s.mem_percent(), Some(25));
        assert_eq!(s.mem_text(), "2.0 GB de 8.0 GB");
        assert_eq!(s.disk_percent(), Some(8));
        assert_eq!(s.disk_text(), "3.1G de 40G");
        assert_eq!(s.load_text(), "0.10  0.20  0.30");
        assert_eq!(s.backup_text(), "2026-10-19 03:00");
    }

    #[test]
    fn status_states() {
        let st = |t: &str| Status::parse(t).state();
        assert_eq!(st("service=failed\n"), State::Failed);
        assert_eq!(st("service=activating\n"), State::Starting);
        assert_eq!(st("service=deactivating\n"), State::Stopping);
        assert_eq!(st("service=inactive\n"), State::Offline);
        assert_eq!(st("service=inactive\npid=9\n"), State::OnlineNoUnit);
        assert_eq!(st("service=inactive\nunit_state=not-found\n"), State::NoUnit);
        assert_eq!(
            st("service=inactive\nunit_state=not-found\npid=9\n"),
            State::OnlineNoUnit
        );
        assert_eq!(st("service=weird\n"), State::Unknown);
        assert!(!Status::parse("Permission denied\n").valid());
    }

    #[test]
    fn status_missing_values() {
        let s = Status::parse("service=active\nplayers=\nerrors=x\nbackup=none\nmem=\ndisk=\nload=\n");
        assert_eq!(s.players_text(), "?");
        assert_eq!(s.errors(), None);
        assert_eq!(s.backup_text(), "nenhum");
        assert_eq!(s.mem_percent(), None);
        assert_eq!(s.mem_text(), "?");
        assert_eq!(s.disk_percent(), None);
        assert_eq!(s.load_text(), "?");
        assert_eq!(s.since_unix(), None);
    }

    #[test]
    fn uptime() {
        let s = Status::parse(STATUS);
        // 2026-10-20 06:00:01 UTC
        assert_eq!(s.since_unix(), Some(1_792_476_001));
        assert_eq!(s.uptime_sec(1_792_476_001 + 90_000), Some(90_000));
        assert_eq!(s.uptime_sec(0), Some(0));
        assert_eq!(parse_since("Tue 2026-10-20 08:00:01 +0200"), Some(1_792_476_001));
        assert_eq!(parse_since("n/a"), None);
        assert_eq!(parse_since("1970-01-01 00:00:10"), Some(10));
        assert_eq!(duration(90_061), "1d 1h 1min");
        assert_eq!(duration(3_700), "1h 1min");
        assert_eq!(duration(59), "0min");
    }

    #[test]
    fn players() {
        let p = parse_players("Test One\t120\tKnight\nTest Two\t8\tMage\nNo one online\n\n");
        assert_eq!(p.len(), 2);
        assert_eq!(p[0].name, "Test One");
        assert_eq!(p[1].level, "8");
        assert_eq!(p[1].vocation, "Mage");
        assert!(parse_players("").is_empty());
    }

    const METRICS: &str = r#"banner
{"ok":true,"empty":false,"churn":{"days":14,"at":1792000000,"gone":"<5","active":40,"bands":[{"band":"1-50","gone":12,"active":20,"gonePct":37.5},{"band":"51-100","gone":"<5","active":"<5","gonePct":null}]},
"deathAreas":[{"name":"Test Cave","deaths":30,"topBand":"1-50"}],"deathMonsters":[{"name":"Test Rat","deaths":"<5","topBand":"1-50"}],
"stops":[{"name":"Test Hall","gone":6,"topBand":"51-100"}],
"returns":[{"week":"2026-W42","cohort":25,"d1":10,"d1Pct":40.0,"d3":"<5","d3Pct":null,"d7":5,"d7Pct":20.0}],
"firstUse":[{"system":"rift","characters":9,"pct":22.5,"medianMinutes":300.0,"topBand":"1-50"},{"system":"other","characters":"<5","pct":null,"medianMinutes":null,"topBand":""}],
"firstSessionCharacters":50,"firstSession":[{"bucket":"30","characters":20,"pct":40.0},{"bucket":"inf","characters":"<5","pct":null}],
"milestones":[{"level":50,"medianMinutes":125.0,"characters":18},{"level":100,"medianMinutes":null,"characters":"<5"}]}"#;

    #[test]
    fn metrics_full() {
        // the server prints the JSON on one line after any banner
        let one = format!("banner\n{}", METRICS.lines().skip(1).collect::<String>());
        let m = Metrics::parse(&one).expect("json line");
        assert!(m.ok && !m.empty);
        assert_eq!(m.churn_days, 14);
        assert_eq!(m.gone, Some(Count::Small));
        assert_eq!(m.active, Some(Count::N(40)));
        assert_eq!(m.bands.len(), 2);
        assert_eq!(m.bands[0].gone_pct, Some(37.5));
        assert_eq!(m.bands[1].gone_pct, None);
        assert_eq!(m.areas[0].count, Count::N(30));
        assert_eq!(m.monsters[0].count.text(), "<5");
        assert_eq!(m.stops[0].count, Count::N(6));
        assert_eq!(m.weeks[0].pct, [Some(40.0), None, Some(20.0)]);
        assert_eq!(m.first_uses[0].median_minutes, Some(300.0));
        assert_eq!(m.first_uses[1].characters, Count::Small);
        assert_eq!(m.session_characters, Some(Count::N(50)));
        assert_eq!(m.sessions[1].characters, Count::Small);
        assert_eq!(m.milestones[0].level, 50);
        assert_eq!(m.milestones[1].median_minutes, None);
    }

    #[test]
    fn metrics_errors() {
        let m = Metrics::parse("{\"ok\":false,\"error\":\"no-table\"}").unwrap();
        assert!(!m.ok);
        assert!(m.error_text().contains("tabela"));
        let m = Metrics::parse("{\"ok\":false,\"error\":\"database\"}").unwrap();
        assert!(m.error_text().contains("banco"));
        let m = Metrics::parse("{\"ok\":false,\"error\":\"zzz\"}").unwrap();
        assert!(m.error_text().contains("zzz"));
        assert!(Metrics::parse("Permission denied").is_none());
        assert!(Metrics::parse("{broken").is_none());
        let e = Metrics::parse("{\"ok\":true,\"empty\":true}").unwrap();
        assert!(e.ok && e.empty && e.bands.is_empty());
    }

    #[test]
    fn text_helpers() {
        assert_eq!(pct(Some(12.5)), "12,5%");
        assert_eq!(pct(None), "<5");
        assert_eq!(minutes(Some(45.4)), "45 min");
        assert_eq!(minutes(Some(210.0)), "3,5 h");
        assert_eq!(minutes(Some(4320.0)), "3,0 dias");
        assert_eq!(minutes(None), "sem dados");
        assert_eq!(bucket_text("30", ""), "até 30 min");
        assert_eq!(bucket_text("inf", "480"), "mais de 480 min");
        assert_eq!(bucket_text("inf", ""), "mais longa");
        assert_eq!(system_name("rift"), "Fenda");
        assert_eq!(system_name("zzz"), "zzz");
    }
}
