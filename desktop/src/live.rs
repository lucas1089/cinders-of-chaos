//! Live view (O312): the page "Ao vivo" refreshes the server state, the players online and the tail of the console
//! log by itself. No daemon and no new command: one ssh call runs the existing `status`, `players` and `logs N` of
//! chaos-ctl.sh back to back (one connection for the three), and the answer is split at a marker line. The timer, the
//! split and the log filter are pure code, tested here; the window only draws.

/// A line that cannot be part of any of the three outputs.
pub const SEP: &str = "@@CINDERS-LIVE@@";
/// Refresh intervals offered, in seconds.
pub const INTERVALS: [u64; 5] = [2, 5, 10, 30, 60];
/// Log lines asked for each time.
pub const LOG_LINES: [u32; 4] = [40, 100, 200, 400];
/// The log pane keeps at most this many lines on screen after the filter.
pub const MAX_SHOWN: usize = 500;

/// The one remote command line: `status`, `players` and `logs N` with a marker line between them. `ctl` is
/// `ssh::ctl_line` of each (the path of chaos-ctl.sh is already quoted there).
pub fn remote_line(status: &str, players: &str, logs: &str) -> String {
    format!("{status}; echo {SEP}; {players}; echo {SEP}; {logs}")
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Sections {
    pub status: String,
    pub players: String,
    pub logs: String,
}

/// Splits the answer at the marker lines. None when ssh itself failed (no marker at all, or not three parts).
pub fn split(text: &str) -> Option<Sections> {
    let mut parts: Vec<String> = vec![String::new()];
    for line in text.lines() {
        if line.trim() == SEP {
            parts.push(String::new());
        } else {
            let last = parts.last_mut()?;
            last.push_str(line);
            last.push('\n');
        }
    }
    if parts.len() != 3 {
        return None;
    }
    let logs = parts.pop()?;
    let players = parts.pop()?;
    let status = parts.pop()?;
    Some(Sections { status, players, logs })
}

/// When to refresh. Times are milliseconds on any steady clock; the window passes its own.
#[derive(Debug, Clone)]
pub struct Poller {
    pub interval_secs: u64,
    pub paused: bool,
    last_ms: Option<u64>,
    in_flight: bool,
}

impl Default for Poller {
    fn default() -> Self {
        Poller {
            interval_secs: 5,
            paused: false,
            last_ms: None,
            in_flight: false,
        }
    }
}

impl Poller {
    /// True when a refresh should start now: not paused, none running (a slow ssh never piles up calls), and the
    /// interval is over since the last start.
    pub fn due(&self, now_ms: u64) -> bool {
        if self.paused || self.in_flight {
            return false;
        }
        match self.last_ms {
            None => true,
            Some(t) => now_ms.saturating_sub(t) >= self.interval_secs.max(1) * 1000,
        }
    }

    pub fn started(&mut self, now_ms: u64) {
        self.last_ms = Some(now_ms);
        self.in_flight = true;
    }

    pub fn finished(&mut self) {
        self.in_flight = false;
    }

    pub fn running(&self) -> bool {
        self.in_flight
    }

    /// Forget the last start so the next frame refreshes (the "Atualizar agora" button).
    pub fn refresh_now(&mut self) {
        self.last_ms = None;
    }

    /// Milliseconds until the next check of `due` is worth doing; None while paused or busy (an answer or a click
    /// wakes the window).
    pub fn wait_ms(&self, now_ms: u64) -> Option<u64> {
        if self.paused || self.in_flight {
            return None;
        }
        let every = self.interval_secs.max(1) * 1000;
        Some(match self.last_ms {
            None => 0,
            Some(t) => every.saturating_sub(now_ms.saturating_sub(t)),
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Level {
    Normal,
    Warn,
    Error,
}

/// How the console writes a line: the engine prints `[Error - ...]` and `[Warning - ...]`, scripts say error too.
pub fn level(line: &str) -> Level {
    let l = line.to_ascii_lowercase();
    if l.contains("[error") || l.contains("lua script error") || l.contains("stack traceback") || l.contains(" error:")
    {
        Level::Error
    } else if l.contains("[warning") || l.contains("warning -") {
        Level::Warn
    } else {
        Level::Normal
    }
}

/// The lines of `text` that contain `needle` (case-insensitive; empty keeps all), the last `MAX_SHOWN` of them.
pub fn filter_lines(text: &str, needle: &str) -> Vec<String> {
    let n = needle.trim().to_lowercase();
    let mut v: Vec<String> = text
        .lines()
        .filter(|l| n.is_empty() || l.to_lowercase().contains(&n))
        .map(str::to_string)
        .collect();
    if v.len() > MAX_SHOWN {
        v.drain(..v.len() - MAX_SHOWN);
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_line_runs_three_commands() {
        let l = remote_line("'/c' status", "'/c' players", "'/c' logs 100");
        assert_eq!(
            l,
            "'/c' status; echo @@CINDERS-LIVE@@; '/c' players; echo @@CINDERS-LIVE@@; '/c' logs 100"
        );
    }

    #[test]
    fn splits_three_parts() {
        let t = "service=active\nplayers=2\n@@CINDERS-LIVE@@\nBob\t10\tKnight\n@@CINDERS-LIVE@@\nline one\nline two\n";
        let s = split(t).unwrap();
        assert_eq!(s.status, "service=active\nplayers=2\n");
        assert_eq!(s.players, "Bob\t10\tKnight\n");
        assert_eq!(s.logs, "line one\nline two\n");
        // empty parts are fine (nobody online)
        let s = split("a=b\n@@CINDERS-LIVE@@\n@@CINDERS-LIVE@@\n").unwrap();
        assert_eq!(s.players, "");
        assert_eq!(s.logs, "");
        // ssh failed: no marker, or a cut answer
        assert!(split("ssh: connect to host x port 22: Connection refused\n").is_none());
        assert!(split("a\n@@CINDERS-LIVE@@\nb\n").is_none());
        assert!(split("").is_none());
    }

    #[test]
    fn the_status_parser_reads_a_split_part() {
        let t = "unit=chaos-server\nservice=active\nplayers=3\n@@CINDERS-LIVE@@\n@@CINDERS-LIVE@@\n";
        let s = crate::cards::Status::parse(&split(t).unwrap().status);
        assert!(s.valid());
        assert_eq!(s.get("players"), "3");
    }

    #[test]
    fn poller_waits_for_the_interval() {
        let mut p = Poller::default();
        assert!(p.due(0), "the first refresh is at once");
        p.started(1000);
        assert!(!p.due(1000) && !p.due(7000), "busy: never a second call");
        assert_eq!(p.wait_ms(1500), None);
        p.finished();
        assert!(!p.due(5999), "5 s not over");
        assert_eq!(p.wait_ms(3000), Some(3000));
        assert!(p.due(6000));
        p.interval_secs = 30;
        assert!(!p.due(6000) && p.due(31_000));
    }

    #[test]
    fn pause_stops_it_and_resume_continues() {
        let mut p = Poller {
            paused: true,
            ..Poller::default()
        };
        assert!(!p.due(1_000_000));
        assert_eq!(p.wait_ms(0), None);
        p.paused = false;
        assert!(p.due(1_000_000));
    }

    #[test]
    fn refresh_now_skips_the_wait() {
        let mut p = Poller::default();
        p.started(1000);
        p.finished();
        assert!(!p.due(2000));
        p.refresh_now();
        assert!(p.due(2000));
        // a clock that goes back never underflows
        p.started(9000);
        p.finished();
        assert!(!p.due(100));
    }

    #[test]
    fn levels() {
        assert_eq!(level("[Error - Npc::loadNpc] x"), Level::Error);
        assert_eq!(level("Lua Script Error: [Scripts Interface]"), Level::Error);
        assert_eq!(level("[Warning - Chaos] Position:sendMagicEffect"), Level::Warn);
        assert_eq!(level("> Loaded all monsters"), Level::Normal);
    }

    #[test]
    fn filter_is_case_insensitive_and_capped() {
        let t = "Alpha\nbeta ERROR here\ngamma\n";
        assert_eq!(filter_lines(t, "error"), vec!["beta ERROR here"]);
        assert_eq!(filter_lines(t, "  ").len(), 3);
        let many: String = (0..MAX_SHOWN + 20).map(|i| format!("l{i}\n")).collect();
        let v = filter_lines(&many, "");
        assert_eq!(v.len(), MAX_SHOWN);
        assert_eq!(v.last().unwrap(), &format!("l{}", MAX_SHOWN + 19));
    }
}
