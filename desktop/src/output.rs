//! The output panel's data (O383): one entry per command run, filled while the command streams, the last ones kept
//! as a history the owner can pick from. Pure, so the window only draws it.
use std::collections::VecDeque;

/// Entries kept in the history.
pub const KEEP: usize = 30;
/// Characters kept per entry; older text is dropped from the start (a whole line at a time).
pub const MAX_CHARS: usize = 1_000_000;

/// How the status line is coloured: by its ending (`: falhou` / `: feito`), plain otherwise.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StatusKind {
    Failed,
    Done,
    Plain,
}

impl StatusKind {
    pub fn of(status: &str) -> Self {
        let t = status.trim_end();
        if t.ends_with(": falhou") {
            Self::Failed
        } else if t.ends_with(": feito") {
            Self::Done
        } else {
            Self::Plain
        }
    }
}

/// The status as one line: every run of whitespace (newlines of an error included) becomes one space, so the
/// label never draws a second line over the next widget.
pub fn one_line(status: &str) -> String {
    status.split_whitespace().collect::<Vec<_>>().join(" ")
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum State {
    Running,
    Ok,
    Failed,
}

#[derive(Clone, Debug)]
pub struct Entry {
    pub id: u64,
    pub title: String,
    pub text: String,
    pub state: State,
    /// Text was dropped from the start to stay under MAX_CHARS.
    pub cut: bool,
}

impl Entry {
    /// The line for the history list and the panel heading.
    pub fn heading(&self) -> String {
        let s = match self.state {
            State::Running => "...",
            State::Ok => "OK",
            State::Failed => "ERRO",
        };
        format!("{s} {}", self.title)
    }
}

/// Drops whole lines from the start of `text` until it has at most `max` bytes. True when something was dropped.
pub fn keep_tail(text: &mut String, max: usize) -> bool {
    if text.len() <= max {
        return false;
    }
    let mut from = text.len() - max;
    while !text.is_char_boundary(from) {
        from += 1;
    }
    if let Some(nl) = text[from..].find('\n') {
        from += nl + 1;
    }
    text.drain(..from);
    true
}

#[derive(Default)]
pub struct Log {
    /// Oldest first.
    entries: VecDeque<Entry>,
    next: u64,
    /// The entry the panel shows; None follows the newest.
    pinned: Option<u64>,
}

impl Log {
    /// A new running entry; the panel follows it unless the owner picked an older one.
    pub fn start(&mut self, title: &str) -> u64 {
        self.next += 1;
        let id = self.next;
        self.entries.push_back(Entry {
            id,
            title: title.to_string(),
            text: String::new(),
            state: State::Running,
            cut: false,
        });
        // drop the oldest finished entries; running ones stay so their answer has a place to land
        while self.entries.len() > KEEP {
            match self.entries.iter().position(|e| e.state != State::Running) {
                Some(i) => {
                    let gone = self.entries.remove(i).map(|e| e.id);
                    if gone == self.pinned {
                        self.pinned = None;
                    }
                }
                None => break,
            }
        }
        id
    }

    fn get_mut(&mut self, id: u64) -> Option<&mut Entry> {
        self.entries.iter_mut().find(|e| e.id == id)
    }

    /// Streamed text of a running entry. Ignored once it finished or was cleared.
    pub fn append(&mut self, id: u64, chunk: &str) {
        if let Some(e) = self.get_mut(id).filter(|e| e.state == State::Running) {
            e.text.push_str(chunk);
            if keep_tail(&mut e.text, MAX_CHARS) {
                e.cut = true;
            }
        }
    }

    /// The final text replaces what streamed (it has the exit code and the parsed answer).
    pub fn finish(&mut self, id: u64, text: &str, ok: bool) {
        if let Some(e) = self.get_mut(id) {
            e.text = text.to_string();
            e.cut = keep_tail(&mut e.text, MAX_CHARS);
            e.state = if ok { State::Ok } else { State::Failed };
        }
    }

    /// "Limpar": forgets the finished entries; a running one stays (empty) so it can still show its answer.
    pub fn clear(&mut self) {
        self.entries.retain(|e| e.state == State::Running);
        for e in self.entries.iter_mut() {
            e.text.clear();
            e.cut = false;
        }
        self.pinned = None;
    }

    /// Shows an older entry (None: follow the newest).
    pub fn pin(&mut self, id: Option<u64>) {
        self.pinned = id.filter(|i| self.entries.iter().any(|e| e.id == *i));
    }

    pub fn pinned(&self) -> Option<u64> {
        self.pinned
    }

    /// The entry the panel shows.
    pub fn shown(&self) -> Option<&Entry> {
        match self.pinned {
            Some(id) => self.entries.iter().find(|e| e.id == id),
            None => self.entries.back(),
        }
    }

    /// Newest first, for the history list.
    pub fn history(&self) -> impl Iterator<Item = &Entry> {
        self.entries.iter().rev()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// Turns pipe reads into text without breaking a character cut between two reads.
#[derive(Default)]
pub struct Utf8Chunks {
    rest: Vec<u8>,
}

impl Utf8Chunks {
    /// The text of `bytes` (with what was left over before), keeping an unfinished character for the next call.
    pub fn push(&mut self, bytes: &[u8]) -> String {
        self.rest.extend_from_slice(bytes);
        let valid = match std::str::from_utf8(&self.rest) {
            Ok(_) => self.rest.len(),
            Err(e) if e.error_len().is_none() => e.valid_up_to(),
            // a byte that never makes a character: decode lossily and move on
            Err(_) => self.rest.len(),
        };
        let out = String::from_utf8_lossy(&self.rest[..valid]).into_owned();
        self.rest.drain(..valid);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_kind_by_ending() {
        assert_eq!(StatusKind::of("Backup: falhou"), StatusKind::Failed);
        assert_eq!(StatusKind::of("Backup: feito\n"), StatusKind::Done);
        assert_eq!(StatusKind::of("curl: (22) 404"), StatusKind::Plain);
        assert_eq!(StatusKind::of(""), StatusKind::Plain);
    }

    #[test]
    fn status_is_one_line() {
        assert_eq!(
            one_line("failed (22)\n  The requested URL\r\nreturned 404 "),
            "failed (22) The requested URL returned 404"
        );
        assert_eq!(one_line(""), "");
    }

    #[test]
    fn streams_then_final_text() {
        let mut l = Log::default();
        let id = l.start("Painel > Backup");
        l.append(id, "a\n");
        l.append(id, "b\n");
        assert_eq!(l.shown().unwrap().text, "a\nb\n");
        assert_eq!(l.shown().unwrap().heading(), "... Painel > Backup");
        l.finish(id, "a\nb\n[código de saída 1]\n", false);
        let e = l.shown().unwrap();
        assert_eq!(e.state, State::Failed);
        assert!(e.text.ends_with("[código de saída 1]\n"));
        assert_eq!(e.heading(), "ERRO Painel > Backup");
        // chunks after the end are ignored
        l.append(id, "late");
        assert!(!l.shown().unwrap().text.contains("late"));
    }

    #[test]
    fn follows_newest_unless_pinned() {
        let mut l = Log::default();
        let a = l.start("a");
        l.finish(a, "A", true);
        let b = l.start("b");
        assert_eq!(l.shown().unwrap().id, b);
        l.pin(Some(a));
        assert_eq!(l.shown().unwrap().text, "A");
        let _c = l.start("c");
        assert_eq!(l.shown().unwrap().id, a, "a pinned entry stays shown");
        l.pin(None);
        assert_eq!(l.shown().unwrap().title, "c");
        l.pin(Some(999));
        assert_eq!(l.pinned(), None);
        let order: Vec<&str> = l.history().map(|e| e.title.as_str()).collect();
        assert_eq!(order, ["c", "b", "a"]);
    }

    #[test]
    fn keeps_a_bounded_history() {
        let mut l = Log::default();
        let first = l.start("first");
        l.finish(first, "x", true);
        l.pin(Some(first));
        let running = l.start("long");
        for i in 0..KEEP + 5 {
            let id = l.start(&i.to_string());
            l.finish(id, "", true);
        }
        assert_eq!(l.len(), KEEP);
        assert!(l.history().any(|e| e.id == running), "a running entry is never dropped");
        assert!(!l.history().any(|e| e.id == first));
        assert_eq!(l.pinned(), None, "the pin goes with its entry");
    }

    #[test]
    fn clear_keeps_running_ones() {
        let mut l = Log::default();
        let a = l.start("a");
        l.finish(a, "done", true);
        let b = l.start("b");
        l.append(b, "half");
        l.clear();
        assert_eq!(l.len(), 1);
        assert_eq!(l.shown().unwrap().text, "");
        l.finish(b, "all", true);
        assert_eq!(l.shown().unwrap().text, "all");
        l.clear();
        assert!(l.is_empty() && l.shown().is_none());
    }

    #[test]
    fn tail_is_cut_at_a_line() {
        let mut s = "line one\nline two\nline three\n".to_string();
        assert!(!keep_tail(&mut s, 100));
        assert!(keep_tail(&mut s, 15));
        assert_eq!(s, "line three\n");
        let mut s = "ééééé\nok".to_string();
        assert!(keep_tail(&mut s, 5));
        assert_eq!(s, "ok");
    }

    #[test]
    fn long_streams_stay_bounded() {
        let mut l = Log::default();
        let id = l.start("big");
        let line = "x".repeat(99) + "\n";
        for _ in 0..(MAX_CHARS / 100 + 50) {
            l.append(id, &line);
        }
        let e = l.shown().unwrap();
        assert!(e.text.len() <= MAX_CHARS && e.cut);
        assert!(e.text.starts_with('x'));
    }

    #[test]
    fn split_characters_join() {
        let mut u = Utf8Chunks::default();
        let bytes = "ação".as_bytes();
        // "ç" is two bytes; cut it in half
        let cut = 2;
        assert_eq!(u.push(&bytes[..cut]), "a");
        assert_eq!(u.push(&bytes[cut..]), "ção");
        assert_eq!(u.push(b"\xff ok"), "\u{fffd} ok");
    }
}
