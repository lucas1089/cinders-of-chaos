//! Cinders of Chaos login-screen services (boosted creature / boss, event calendar, players online).
//!
//! A Rust port of `server/tools/clientservices.py`, same behaviour and same command line. The game server writes
//! `data/chaos_clientservices.json`; this program serves it over HTTP on the client's `clientServicesLink`.
//! server/README.md "Engine hardening (sanitizers, fuzzing)", part (3), and "Rust services (O153)".
//!
//! The protocol code is pure: [`read_head`] reads one request head from any `BufRead`, [`plan`] and [`finish`] turn
//! a head (and body) into a [`Reply`]. `main.rs` only owns the sockets, the threads and the clock.
#![forbid(unsafe_code)]

use serde_json::{json, Map, Value};
use std::io::{BufRead, Read};

pub mod fuzz_checks;

/// The three parts the client asks for.
pub const TYPES: [&str; 3] = ["boostedcreature", "eventschedule", "cacheinfo"];
/// A POST body larger than this is refused with 413 (as the Python service).
pub const MAX_BODY: i64 = 64 * 1024;
/// One request or header line, as http.server: 65536 bytes.
pub const MAX_LINE: usize = 65536;
/// This many header lines or more are refused (http.client: more than 100 lines with the empty one).
pub const MAX_HEADERS: usize = 100;
/// All header bytes together (the Python service has no total limit, only 100 x 64 KiB).
pub const MAX_HEAD_BYTES: usize = 128 * 1024;
/// The data file is ignored (served as empty) when it is larger than this.
pub const MAX_DATA_FILE: u64 = 16 * 1024 * 1024;

/// What the service answers for a part the file does not have.
pub fn empty_part(kind: &str) -> Value {
    match kind {
        "boostedcreature" => json!({}),
        "eventschedule" => json!({"eventlist": []}),
        _ => json!({"playersonline": 0, "online": "0 players online"}),
    }
}

/// The data file's top level object; anything else (missing, unreadable, not JSON, not an object) is empty.
pub fn parse_data(bytes: &[u8]) -> Map<String, Value> {
    match serde_json::from_slice::<Value>(bytes) {
        Ok(Value::Object(m)) => m,
        _ => Map::new(),
    }
}

/// Reads the data file (at most [`MAX_DATA_FILE`] bytes) on every request, so it never needs a restart.
pub fn load(path: &std::path::Path) -> Map<String, Value> {
    let Ok(f) = std::fs::File::open(path) else {
        return Map::new();
    };
    let mut buf = Vec::new();
    if f.take(MAX_DATA_FILE + 1).read_to_end(&mut buf).is_err() || buf.len() as u64 > MAX_DATA_FILE {
        return Map::new();
    }
    parse_data(&buf)
}

/// One part of the file; the Lua encoder writes an empty table as `[]`, the client wants an object.
pub fn answer(data: &Map<String, Value>, kind: &str) -> Value {
    match data.get(kind) {
        Some(v @ Value::Object(_)) => v.clone(),
        _ => empty_part(kind),
    }
}

/// Every part, for a GET without (or with an unknown) `type`.
pub fn answer_all(data: &Map<String, Value>) -> Value {
    let mut m = Map::new();
    for k in TYPES {
        m.insert(k.to_string(), answer(data, k));
    }
    Value::Object(m)
}

/// The last `type=` of the query string of a request target, not percent-decoded (as the Python service).
pub fn query_type(target: &str) -> Option<&str> {
    let (_, query) = target.split_once('?')?;
    let mut kind = None;
    for pair in query.split('&') {
        let (key, value) = match pair.split_once('=') {
            Some((k, v)) => (k, v),
            None => (pair, ""),
        };
        if key == "type" {
            kind = Some(value);
        }
    }
    kind
}

/// `Content-Length` as Python's `int(value or 0)` then `< 0 or > 64 KiB` reads it: absent or empty is 0, a value that
/// is not a number is -1. Numbers too big for an i64 count as huge. A minus sign always reads below 0, "-0" too: the
/// header is digits only, so a signed zero is refused rather than taken as an empty body.
pub fn parse_content_length(value: Option<&str>) -> i64 {
    let v = match value {
        Some(v) if !v.trim().is_empty() => v.trim(),
        _ => return 0,
    };
    let (neg, digits) = match v.as_bytes().first() {
        Some(b'-') => (true, &v[1..]),
        Some(b'+') => (false, &v[1..]),
        _ => (false, v),
    };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return -1;
    }
    match digits.parse::<i64>() {
        Ok(n) if neg => -n.max(1),
        Ok(n) => n,
        Err(_) if neg => -1,
        Err(_) => i64::MAX,
    }
}

/// Why a request head could not be read.
#[derive(Debug, PartialEq, Eq, Clone, Copy)]
pub enum HeadError {
    /// The connection ended or sent nothing usable before a request line: closed silently.
    Closed,
    /// A read failed (timeout, reset): closed silently.
    Io,
    /// 414: the request line is longer than [`MAX_LINE`].
    LineTooLong,
    /// 431: a header line is too long, there are too many, or they are too big together.
    HeadersTooLarge,
    /// 400: not a request line this service understands.
    Bad,
    /// 505: HTTP/2 or later in the request line.
    Version,
}

/// A request head: the method, the target, and the headers as received (names as sent, values trimmed).
#[derive(Debug, PartialEq, Eq, Clone)]
pub struct Head {
    pub method: String,
    pub target: String,
    pub headers: Vec<(String, String)>,
}

impl Head {
    /// The first header of that name (case-insensitive), as `email.message.get` finds it.
    pub fn header(&self, name: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|(k, _)| k.eq_ignore_ascii_case(name))
            .map(|(_, v)| v.as_str())
    }
}

/// Bytes as ISO-8859-1, which is how http.server decodes the head: never fails.
fn latin1(b: &[u8]) -> String {
    b.iter().map(|&c| c as char).collect()
}

/// One line without its `\r\n` or `\n`. `Ok(None)` at the end of the stream with nothing read.
fn read_line<R: BufRead>(r: &mut R) -> Result<Option<Vec<u8>>, HeadError> {
    let mut buf = Vec::new();
    match r.by_ref().take(MAX_LINE as u64 + 1).read_until(b'\n', &mut buf) {
        Err(_) => return Err(HeadError::Io),
        Ok(0) => return Ok(None),
        Ok(_) => {}
    }
    if buf.len() > MAX_LINE {
        return Err(HeadError::LineTooLong);
    }
    if buf.last() == Some(&b'\n') {
        buf.pop();
        if buf.last() == Some(&b'\r') {
            buf.pop();
        }
    }
    Ok(Some(buf))
}

/// Reads the request line and the headers (up to the empty line) the way http.server does: ISO-8859-1, `\n` or
/// `\r\n` ends a line, a header line without a colon is ignored. Never reads the body.
pub fn read_head<R: BufRead>(r: &mut R) -> Result<Head, HeadError> {
    let Some(line) = read_line(r)? else {
        return Err(HeadError::Closed);
    };
    let text = latin1(&line);
    let words: Vec<&str> = text.split_whitespace().collect();
    let (method, target, version) = match words.as_slice() {
        [] => return Err(HeadError::Closed),
        [m, t, v] => (*m, *t, *v),
        // HTTP/0.9 ("GET /path") is not served
        _ => return Err(HeadError::Bad),
    };
    let Some(num) = version.strip_prefix("HTTP/") else {
        return Err(HeadError::Bad);
    };
    let mut parts = num.split('.');
    let (Some(maj), Some(min), None) = (parts.next(), parts.next(), parts.next()) else {
        return Err(HeadError::Bad);
    };
    let (Ok(maj), Ok(_min)) = (maj.parse::<u32>(), min.parse::<u32>()) else {
        return Err(HeadError::Bad);
    };
    if maj >= 2 {
        return Err(HeadError::Version);
    }
    let mut headers = Vec::new();
    let mut lines = 0usize;
    let mut total = 0usize;
    // http.client counts the empty line that ends the head too, so 100 header lines are already too many
    let mut parsing = true;
    loop {
        let line = match read_line(r) {
            Ok(Some(l)) => l,
            Ok(None) => break,
            Err(HeadError::LineTooLong) => return Err(HeadError::HeadersTooLarge),
            Err(e) => return Err(e),
        };
        if line.is_empty() {
            break;
        }
        lines += 1;
        total += line.len();
        if lines >= MAX_HEADERS || total > MAX_HEAD_BYTES {
            return Err(HeadError::HeadersTooLarge);
        }
        if !parsing {
            continue;
        }
        let s = latin1(&line);
        if s.starts_with([' ', '\t']) {
            continue; // an obsolete folded line: nothing here reads a folded header
        }
        match s.split_once(':') {
            Some((k, v)) => headers.push((k.trim().to_string(), v.trim().to_string())),
            // the email parser behind http.server ends the headers at a line that is not one: the rest is body
            None => parsing = false,
        }
    }
    Ok(Head {
        method: method.to_string(),
        target: target.to_string(),
        headers,
    })
}

/// What to send: a status and a JSON body (`None`: an empty body, for 204).
#[derive(Debug, PartialEq, Clone)]
pub struct Reply {
    pub code: u16,
    pub body: Option<Value>,
}

impl Reply {
    fn json(code: u16, body: Value) -> Reply {
        Reply { code, body: Some(body) }
    }
    fn error(code: u16, msg: &str) -> Reply {
        Reply::json(code, json!({ "error": msg }))
    }
}

/// The reason phrase of a status this service sends.
pub fn reason(code: u16) -> &'static str {
    match code {
        200 => "OK",
        204 => "No Content",
        400 => "Bad Request",
        413 => "Payload Too Large",
        414 => "URI Too Long",
        431 => "Request Header Fields Too Large",
        501 => "Not Implemented",
        505 => "HTTP Version Not Supported",
        _ => "Error",
    }
}

/// The answer to a head that failed to parse, `None` when the connection is just closed.
pub fn head_error_reply(e: HeadError) -> Option<Reply> {
    match e {
        HeadError::Closed | HeadError::Io => None,
        HeadError::LineTooLong => Some(Reply::error(414, "request line too long")),
        HeadError::HeadersTooLarge => Some(Reply::error(431, "headers too large")),
        HeadError::Bad => Some(Reply::error(400, "bad request")),
        HeadError::Version => Some(Reply::error(505, "http version not supported")),
    }
}

/// The next step for a parsed head.
#[derive(Debug, PartialEq, Clone)]
pub enum Step {
    /// Answer now.
    Reply(Reply),
    /// Read this many body bytes (at most [`MAX_BODY`]; fewer if the client closes early), then call [`finish`].
    ReadBody(usize),
}

pub fn plan(head: &Head, data: &Map<String, Value>) -> Step {
    match head.method.as_str() {
        "OPTIONS" => Step::Reply(Reply { code: 204, body: None }),
        "GET" => {
            // handy for checking the endpoint from a browser: /?type=eventschedule, or everything
            let body = match query_type(&head.target) {
                Some(k) if TYPES.contains(&k) => answer(data, k),
                _ => answer_all(data),
            };
            Step::Reply(Reply::json(200, body))
        }
        "POST" => {
            let len = parse_content_length(head.header("content-length"));
            if !(0..=MAX_BODY).contains(&len) {
                Step::Reply(Reply::error(413, "request too large"))
            } else {
                Step::ReadBody(len as usize)
            }
        }
        _ => Step::Reply(Reply::error(501, "unsupported method")),
    }
}

/// The answer to a POST with its body.
pub fn finish(body: &[u8], data: &Map<String, Value>) -> Reply {
    // an empty body is `{}`, as the Python service
    let parsed: Result<Value, _> = if body.is_empty() {
        Ok(json!({}))
    } else {
        serde_json::from_slice(body)
    };
    let Ok(request) = parsed else {
        return Reply::error(400, "invalid json");
    };
    let kind = request.as_object().and_then(|o| o.get("type")).and_then(Value::as_str);
    match kind {
        Some(k) if TYPES.contains(&k) => Reply::json(200, answer(data, k)),
        _ => Reply::json(400, json!({"error": "unknown type", "types": TYPES})),
    }
}

/// `Sun, 06 Nov 1994 08:49:37 GMT` for a Unix time.
pub fn http_date(secs: u64) -> String {
    const DAYS: [&str; 7] = ["Thu", "Fri", "Sat", "Sun", "Mon", "Tue", "Wed"];
    const MONTHS: [&str; 12] = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ];
    let days = secs / 86400;
    let rem = secs % 86400;
    // civil date from days since 1970-01-01 (Howard Hinnant's algorithm)
    let z = days as i64 + 719468;
    let era = z.div_euclid(146097);
    let doe = z.rem_euclid(146097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = yoe + era * 400 + i64::from(m <= 2);
    format!(
        "{}, {:02} {} {} {:02}:{:02}:{:02} GMT",
        DAYS[(days % 7) as usize],
        d,
        MONTHS[(m - 1) as usize],
        y,
        rem / 3600,
        rem % 3600 / 60,
        rem % 60
    )
}

/// The response bytes: status line, headers, body.
pub fn render(reply: &Reply, now_secs: u64) -> Vec<u8> {
    let body = reply
        .body
        .as_ref()
        .map(|v| serde_json::to_vec(v).unwrap_or_else(|_| b"{}".to_vec()));
    let body = body.unwrap_or_default();
    let mut out = format!(
        "HTTP/1.0 {} {}\r\nServer: ChaosClientServices/1.0\r\nDate: {}\r\n",
        reply.code,
        reason(reply.code),
        http_date(now_secs)
    );
    if reply.code != 204 {
        out.push_str("Content-Type: application/json\r\n");
    }
    out.push_str(&format!(
        "Content-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Headers: Content-Type\r\nConnection: close\r\n\r\n",
        body.len()
    ));
    let mut bytes = out.into_bytes();
    bytes.extend_from_slice(&body);
    bytes
}

/// A request line made safe for the log: control characters escaped (no forged log lines), at most 200 characters.
pub fn log_safe(s: &str) -> String {
    let mut out = String::new();
    for c in s.chars().take(200) {
        if c < ' ' || ('\u{7f}'..='\u{9f}').contains(&c) {
            out.push_str(&format!("\\x{:02x}", c as u32));
        } else {
            out.push(c);
        }
    }
    out
}
