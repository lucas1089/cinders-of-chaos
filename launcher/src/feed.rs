//! News and Changelog of the window: the website's launcher feed (website/README.md "Launcher feed").
//!
//! Optional in every way. The feed is fetched on its own thread with a short time limit, never gates the update or the
//! Play button, and a missing, broken, too big or unreachable feed only shows a short message. The last good copy is
//! kept in `.cinders_launcher/feed.json` for an offline start. Everything in the feed is plain text: control and
//! direction characters are removed, lengths and counts are capped, and a link is opened only when it is an `https://`
//! URL without spaces (or a loopback `http://` URL in the tests).
use crate::config::{loopback_http, Config};
use crate::i18n::Lang;
use crate::install::STATE_DIR;
use crate::net::Fetch;
use serde_json::Value;
use std::path::{Path, PathBuf};

/// A feed bigger than this is refused (the site writes at most 64 KiB).
pub const MAX_BYTES: usize = 128 * 1024;
pub const CACHE_FILE: &str = "feed.json";
/// Seconds the whole request may take.
pub const FETCH_SECS: u32 = 10;

pub const MAX_NEWS: usize = 10;
pub const MAX_ENTRIES: usize = 10;
pub const MAX_LINES: usize = 12;
const MAX_TITLE: usize = 120;
const MAX_TEXT: usize = 600;
const MAX_LINE: usize = 300;
const MAX_URL: usize = 300;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NewsItem {
    pub date: String,
    pub title: String,
    pub text: String,
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Entry {
    pub date: String,
    pub title: String,
    pub lines: Vec<String>,
    pub url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Feed {
    pub news: Vec<NewsItem>,
    pub changelog: Vec<Entry>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FeedError {
    TooBig,
    NotJson,
    /// Not format 1.
    Format,
}

/// What the window shows.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Panel {
    /// Fetching.
    Loading,
    /// A feed, fresh (`cached` false) or the saved copy of an earlier run.
    Ready { feed: Feed, cached: bool },
    /// No feed address, no answer and no saved copy, or a broken answer and no saved copy.
    Unavailable,
}

/// Plain text: control, direction and zero-width characters out, white space squeezed, cut to `max` characters.
pub fn clean(s: &str, max: usize) -> String {
    let mut out = String::new();
    let mut space = true;
    for c in s.chars() {
        let bad = c.is_control()
            || matches!(c, '\u{200B}'..='\u{200F}' | '\u{202A}'..='\u{202E}' | '\u{2060}'..='\u{2064}' | '\u{2066}'..='\u{2069}' | '\u{FEFF}' | '\u{2028}' | '\u{2029}');
        if bad || c.is_whitespace() {
            if !space {
                out.push(' ');
                space = true;
            }
        } else {
            out.push(c);
            space = false;
        }
    }
    let out = out.trim_end().to_string();
    if out.chars().count() > max {
        let cut: String = out.chars().take(max.saturating_sub(3)).collect();
        format!("{}...", cut.trim_end())
    } else {
        out
    }
}

/// A link the window may open: `https://host/...`, ASCII only (the site percent-encodes), no spaces or control characters, no `user@` in front of the host.
pub fn safe_link(url: &str) -> Option<String> {
    if url.len() > MAX_URL
        || !url.is_ascii()
        || url
            .chars()
            .any(|c| c.is_ascii_control() || c.is_whitespace() || matches!(c, '"' | '<' | '>' | '\\'))
    {
        return None;
    }
    let rest = url.strip_prefix("https://");
    let ok = match rest {
        Some(r) => r,
        None if loopback_http(url) => &url["http://".len()..],
        None => return None,
    };
    let host = ok.split(['/', '?', '#']).next().unwrap_or("");
    if host.is_empty() || host.contains('@') || host.starts_with('.') || host.starts_with(':') {
        return None;
    }
    Some(url.to_string())
}

/// `2026-10-29` -> `29/10/2026` in Portuguese, as it is in English; anything else is shown cleaned and short.
pub fn show_date(d: &str, lang: Lang) -> String {
    let b = d.as_bytes();
    let shaped = b.len() == 10
        && b.iter().enumerate().all(|(i, c)| {
            if i == 4 || i == 7 {
                *c == b'-'
            } else {
                c.is_ascii_digit()
            }
        });
    if shaped && lang == Lang::Pt {
        format!("{}/{}/{}", &d[8..10], &d[5..7], &d[0..4])
    } else {
        clean(d, 10)
    }
}

fn text_of(v: &Value, key: &str, max: usize) -> String {
    v.get(key)
        .and_then(Value::as_str)
        .map(|s| clean(s, max))
        .unwrap_or_default()
}

fn link_of(v: &Value) -> Option<String> {
    v.get("url").and_then(Value::as_str).and_then(safe_link)
}

fn block(root: &Value, lang: Lang) -> Option<&Value> {
    let (first, second) = match lang {
        Lang::Pt => ("pt-BR", "en"),
        Lang::En => ("en", "pt-BR"),
    };
    [first, second]
        .iter()
        .filter_map(|k| root.get(*k))
        .find(|b| b.is_object())
}

/// Reads the feed in the player's language (the other language when the block is missing). An item of the wrong shape
/// or without a title is dropped; the rest is kept.
pub fn parse(bytes: &[u8], lang: Lang) -> Result<Feed, FeedError> {
    if bytes.len() > MAX_BYTES {
        return Err(FeedError::TooBig);
    }
    let root: Value = serde_json::from_slice(bytes).map_err(|_| FeedError::NotJson)?;
    if root.get("format").and_then(Value::as_u64) != Some(1) {
        return Err(FeedError::Format);
    }
    let mut feed = Feed::default();
    let Some(b) = block(&root, lang) else {
        return Ok(feed);
    };
    for n in b.get("news").and_then(Value::as_array).into_iter().flatten() {
        let title = text_of(n, "title", MAX_TITLE);
        if title.is_empty() || !n.is_object() {
            continue;
        }
        if feed.news.len() < MAX_NEWS {
            feed.news.push(NewsItem {
                date: text_of(n, "date", 10),
                title,
                text: text_of(n, "text", MAX_TEXT),
                url: link_of(n),
            });
        }
    }
    for e in b.get("changelog").and_then(Value::as_array).into_iter().flatten() {
        let title = text_of(e, "title", MAX_TITLE);
        if title.is_empty() || !e.is_object() {
            continue;
        }
        let lines: Vec<String> = e
            .get("lines")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
            .filter_map(Value::as_str)
            .map(|l| clean(l, MAX_LINE))
            .filter(|l| !l.is_empty())
            .take(MAX_LINES)
            .collect();
        if feed.changelog.len() < MAX_ENTRIES {
            feed.changelog.push(Entry {
                date: text_of(e, "date", 10),
                title,
                lines,
                url: link_of(e),
            });
        }
    }
    Ok(feed)
}

pub fn cache_path(dir: &Path) -> PathBuf {
    dir.join(STATE_DIR).join(CACHE_FILE)
}

/// Keeps a good feed for the next start (a temporary file renamed). A failure is ignored: the cache is a convenience.
fn save(dir: &Path, bytes: &[u8]) {
    let path = cache_path(dir);
    let Some(parent) = path.parent() else { return };
    if std::fs::create_dir_all(parent).is_err() {
        return;
    }
    let tmp = path.with_extension("tmp");
    if std::fs::write(&tmp, bytes).is_ok() && std::fs::rename(&tmp, &path).is_err() {
        let _ = std::fs::remove_file(&tmp);
    }
}

fn from_cache(dir: &Path, lang: Lang) -> Option<Feed> {
    let bytes = std::fs::read(cache_path(dir)).ok()?;
    parse(&bytes, lang).ok()
}

/// Fetches the feed (short time limit), keeps a good answer, and falls back to the saved copy when the fetch fails or
/// the answer is broken. Never returns an error and never panics on bad input.
pub fn load(fetch: &dyn Fetch, cfg: &Config, lang: Lang) -> Panel {
    let Some(url) = cfg.feed.as_deref() else {
        return Panel::Unavailable;
    };
    if let Ok(bytes) = fetch.get_small(url, FETCH_SECS, MAX_BYTES as u64) {
        if let Ok(feed) = parse(&bytes, lang) {
            save(&cfg.dir, &bytes);
            return Panel::Ready { feed, cached: false };
        }
    }
    match from_cache(&cfg.dir, lang) {
        Some(feed) => Panel::Ready { feed, cached: true },
        None => Panel::Unavailable,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    const FEED: &str = r#"{"format":1,"generated":5,
      "en":{"news":[{"id":1,"date":"2026-10-29","title":"Season two","text":"Join now.","url":"https://site.test/?view=1"}],
            "changelog":[{"id":"2026-10-22","date":"2026-10-22","title":"Wings","lines":["One.","Two."],"url":"https://site.test/page?p=patchnotes"}]},
      "pt-BR":{"news":[{"id":1,"date":"2026-10-29","title":"Temporada dois","text":"Entre agora.","url":"https://site.test/?view=1"}],
            "changelog":[{"id":"2026-10-22","date":"2026-10-22","title":"Asas","lines":["Um.","Dois."],"url":null}]}}"#;

    struct Fake {
        answer: RefCell<Result<Vec<u8>, String>>,
        asked: RefCell<Vec<(String, u32, u64)>>,
    }

    impl Fake {
        fn new(a: Result<Vec<u8>, String>) -> Fake {
            Fake {
                answer: RefCell::new(a),
                asked: RefCell::new(vec![]),
            }
        }
    }

    impl Fetch for Fake {
        fn get(&self, _url: &str) -> Result<Vec<u8>, String> {
            panic!("the feed must use get_small")
        }
        fn get_small(&self, url: &str, secs: u32, max: u64) -> Result<Vec<u8>, String> {
            self.asked.borrow_mut().push((url.to_string(), secs, max));
            self.answer.borrow().clone()
        }
        fn download(&self, _: &str, _: &Path, _: &mut dyn FnMut(u64)) -> Result<(), String> {
            unreachable!()
        }
    }

    fn cfg(dir: &Path, feed: Option<&str>) -> Config {
        Config {
            manifest_url: "https://site.test/updates/live/manifest.json".into(),
            public_key: [0; 32],
            baseline: 0,
            game: "Chaos.exe".into(),
            args: vec![],
            feed: feed.map(str::to_string),
            dir: dir.to_path_buf(),
        }
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("cinders-feed-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn parses_both_languages() {
        let en = parse(FEED.as_bytes(), Lang::En).unwrap();
        assert_eq!(en.news[0].title, "Season two");
        assert_eq!(en.news[0].url.as_deref(), Some("https://site.test/?view=1"));
        assert_eq!(en.changelog[0].lines, vec!["One.", "Two."]);
        let pt = parse(FEED.as_bytes(), Lang::Pt).unwrap();
        assert_eq!(pt.news[0].title, "Temporada dois");
        assert_eq!(pt.changelog[0].title, "Asas");
        assert_eq!(pt.changelog[0].url, None);
    }

    #[test]
    fn missing_language_block_falls_back() {
        let only_en = r#"{"format":1,"en":{"news":[{"title":"A"}],"changelog":[]}}"#;
        assert_eq!(parse(only_en.as_bytes(), Lang::Pt).unwrap().news[0].title, "A");
        let none = r#"{"format":1}"#;
        assert_eq!(parse(none.as_bytes(), Lang::En).unwrap(), Feed::default());
    }

    #[test]
    fn refuses_bad_feeds() {
        assert_eq!(parse(b"<html>nope</html>", Lang::En), Err(FeedError::NotJson));
        assert_eq!(parse(b"", Lang::En), Err(FeedError::NotJson));
        assert_eq!(parse(br#"{"format":2}"#, Lang::En), Err(FeedError::Format));
        assert_eq!(parse(br#"{"en":{}}"#, Lang::En), Err(FeedError::Format));
        assert_eq!(parse(b"[1,2]", Lang::En), Err(FeedError::Format));
        let big = format!(r#"{{"format":1,"pad":"{}"}}"#, "x".repeat(MAX_BYTES));
        assert_eq!(parse(big.as_bytes(), Lang::En), Err(FeedError::TooBig));
        let edge = format!(r#"{{"format":1,"pad":"{}"}}"#, "x".repeat(MAX_BYTES - 21));
        assert_eq!(edge.len(), MAX_BYTES);
        assert!(parse(edge.as_bytes(), Lang::En).is_ok());
    }

    #[test]
    fn odd_items_are_dropped_not_fatal() {
        let t = r#"{"format":1,"en":{"news":[5,null,{"title":""},{"title":"ok","text":7,"url":3},"x"],
            "changelog":[{"title":"c","lines":[1,"a","",null,"b"]},{"lines":["no title"]}]}}"#;
        let f = parse(t.as_bytes(), Lang::En).unwrap();
        assert_eq!(f.news.len(), 1);
        assert_eq!((f.news[0].text.as_str(), f.news[0].url.clone()), ("", None));
        assert_eq!(f.changelog.len(), 1);
        assert_eq!(f.changelog[0].lines, vec!["a", "b"]);
        let t = r#"{"format":1,"en":"text"}"#;
        assert_eq!(parse(t.as_bytes(), Lang::En).unwrap(), Feed::default());
        let t = r#"{"format":1,"en":{"news":{"a":1},"changelog":"x"}}"#;
        assert_eq!(parse(t.as_bytes(), Lang::En).unwrap(), Feed::default());
    }

    #[test]
    fn counts_and_lengths_are_capped() {
        let news: Vec<String> = (0..30)
            .map(|i| format!(r#"{{"title":"N{i}","text":"{}"}}"#, "ab ".repeat(900)))
            .collect();
        let lines: Vec<String> = (0..40).map(|i| format!(r#""line {i}""#)).collect();
        let t = format!(
            r#"{{"format":1,"en":{{"news":[{}],"changelog":[{}]}}}}"#,
            news.join(","),
            (0..30)
                .map(|i| format!(r#"{{"title":"C{i}","lines":[{}]}}"#, lines.join(",")))
                .collect::<Vec<_>>()
                .join(",")
        );
        let f = parse(t.as_bytes(), Lang::En).unwrap();
        assert_eq!(f.news.len(), MAX_NEWS);
        assert_eq!(f.changelog.len(), MAX_ENTRIES);
        assert!(f.news.iter().all(|n| n.text.chars().count() <= MAX_TEXT));
        assert!(f.changelog.iter().all(|c| c.lines.len() == MAX_LINES));
    }

    #[test]
    fn text_is_plain() {
        assert_eq!(clean("a\u{0}b\u{7}c\r\n\t d", 50), "a b c d");
        assert_eq!(clean("  x\u{202E}y\u{200B}z  ", 50), "x y z");
        assert_eq!(
            clean("<b>bold</b> &amp; [url]x[/url]", 50),
            "<b>bold</b> &amp; [url]x[/url]"
        ); // shown as typed
        assert_eq!(clean("", 5), "");
        assert_eq!(clean("ação ação ação", 8), "ação...");
        let long = "é".repeat(500);
        let c = clean(&long, 100);
        assert_eq!(c.chars().count(), 100);
        assert!(c.ends_with("..."));
        assert_eq!(clean("abcdef", 6), "abcdef");
    }

    #[test]
    fn links() {
        assert!(safe_link("https://site.test/page?plugin=chaos&p=patchnotes&id=2026-10-22").is_some());
        assert!(safe_link("http://127.0.0.1:8080/x").is_some());
        for bad in [
            "http://site.test/",
            "javascript:alert(1)",
            "file:///etc/passwd",
            "ftp://site.test/",
            "https://",
            "https:///x",
            "https://user@evil.test/",
            "https://site.test/a b",
            "https://site.test/\u{202E}x",
            "https://site.test/a\nb",
            "https://site.test/\"x",
            "https://.evil/",
            "calc.exe",
            "",
        ] {
            assert_eq!(safe_link(bad), None, "{bad:?}");
        }
        assert_eq!(safe_link(&format!("https://site.test/{}", "a".repeat(400))), None);
        // in the parsed feed an unsafe link is dropped, the item stays
        let t = r#"{"format":1,"en":{"news":[{"title":"A","url":"javascript:alert(1)"}]}}"#;
        let f = parse(t.as_bytes(), Lang::En).unwrap();
        assert_eq!((f.news.len(), f.news[0].url.clone()), (1, None));
    }

    #[test]
    fn dates() {
        assert_eq!(show_date("2026-10-29", Lang::Pt), "29/10/2026");
        assert_eq!(show_date("2026-10-29", Lang::En), "2026-10-29");
        assert_eq!(show_date("tomorrow-ish!!", Lang::Pt), "tomorro...");
        assert_eq!(show_date("", Lang::Pt), "");
    }

    #[test]
    fn load_saves_a_good_feed_and_uses_it_offline() {
        let d = tmp("cache");
        let c = cfg(&d, Some("https://site.test/chaos_launcher_feed.php"));
        let up = Fake::new(Ok(FEED.as_bytes().to_vec()));
        let p = load(&up, &c, Lang::En);
        assert!(matches!(&p, Panel::Ready { cached: false, feed } if feed.news.len() == 1));
        // short time limit and size limit are passed on
        assert_eq!(
            up.asked.borrow()[0],
            (
                "https://site.test/chaos_launcher_feed.php".to_string(),
                FETCH_SECS,
                MAX_BYTES as u64
            )
        );
        assert_eq!(std::fs::read(cache_path(&d)).unwrap(), FEED.as_bytes());
        assert!(!cache_path(&d).with_extension("tmp").exists());
        // offline: the saved copy, in the language asked for
        let down = Fake::new(Err("curl 7: refused".into()));
        match load(&down, &c, Lang::Pt) {
            Panel::Ready { feed, cached: true } => assert_eq!(feed.news[0].title, "Temporada dois"),
            other => panic!("{other:?}"),
        }
        // a broken answer, a wrong format and an oversize answer keep the good copy
        for bad in [
            b"<html>".to_vec(),
            br#"{"format":9}"#.to_vec(),
            vec![b' '; MAX_BYTES + 1],
        ] {
            let f = Fake::new(Ok(bad));
            assert!(matches!(load(&f, &c, Lang::En), Panel::Ready { cached: true, .. }));
            assert_eq!(std::fs::read(cache_path(&d)).unwrap(), FEED.as_bytes());
        }
        // a newer good feed replaces it
        let newer = FEED.replace("Season two", "Season three");
        let f = Fake::new(Ok(newer.clone().into_bytes()));
        assert!(matches!(&load(&f, &c, Lang::En), Panel::Ready { feed, .. } if feed.news[0].title == "Season three"));
        assert_eq!(std::fs::read(cache_path(&d)).unwrap(), newer.as_bytes());
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn load_without_feed_or_copy_is_just_unavailable() {
        let d = tmp("none");
        let down = Fake::new(Err("timeout".into()));
        assert_eq!(
            load(&down, &cfg(&d, Some("https://site.test/f")), Lang::En),
            Panel::Unavailable
        );
        // no feed address: nothing is fetched
        let up = Fake::new(Ok(FEED.as_bytes().to_vec()));
        assert_eq!(load(&up, &cfg(&d, None), Lang::En), Panel::Unavailable);
        assert!(up.asked.borrow().is_empty());
        // a corrupt saved copy is ignored
        std::fs::create_dir_all(d.join(STATE_DIR)).unwrap();
        std::fs::write(cache_path(&d), b"\xff\xfe garbage").unwrap();
        assert_eq!(
            load(&down, &cfg(&d, Some("https://site.test/f")), Lang::En),
            Panel::Unavailable
        );
        // an unwritable state folder (a file in its place) does not stop a good feed from showing
        let _ = std::fs::remove_dir_all(d.join(STATE_DIR));
        std::fs::write(d.join(STATE_DIR), b"file").unwrap();
        assert!(matches!(
            load(&up, &cfg(&d, Some("https://site.test/f")), Lang::En),
            Panel::Ready { cached: false, .. }
        ));
        let _ = std::fs::remove_dir_all(&d);
    }
}
