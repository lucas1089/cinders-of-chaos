//! The invariants the cargo-fuzz targets (`fuzz/`) check, as plain functions: the fuzzers call them on arbitrary
//! bytes and `tests/fuzz_seeds.rs` replays the seed corpus through them on stable, so CI needs no nightly.
//! Every function panics (assert) when an invariant breaks.

use crate::*;
use std::io::Cursor;

fn sample() -> Map<String, Value> {
    parse_data(br#"{"boostedcreature":{"name":"Rotworm"},"eventschedule":{"eventlist":[1]},"cacheinfo":[]}"#)
}

fn check_reply(r: &Reply, now: u64) {
    let out = render(r, now);
    assert!(out.starts_with(b"HTTP/1."), "status line");
    let split = out.windows(4).position(|w| w == b"\r\n\r\n").expect("end of head") + 4;
    let head = std::str::from_utf8(&out[..split]).expect("head is ASCII");
    let len: usize = head
        .lines()
        .find_map(|l| l.strip_prefix("Content-Length: "))
        .expect("Content-Length")
        .parse()
        .expect("number");
    assert_eq!(len, out.len() - split, "Content-Length matches the body");
    if r.code == 204 {
        assert_eq!(len, 0);
    } else if len > 0 {
        serde_json::from_slice::<Value>(&out[split..]).expect("body is JSON");
    }
}

/// Target 1: arbitrary bytes as one connection: head, then plan, then finish on the rest as the body.
pub fn check_request(raw: &[u8]) {
    let data = sample();
    let mut cur = Cursor::new(raw);
    match read_head(&mut cur) {
        Err(e) => {
            if let Some(r) = head_error_reply(e) {
                assert!((400..=505).contains(&r.code));
                check_reply(&r, 0);
            }
        }
        Ok(head) => {
            assert!(cur.position() <= raw.len() as u64);
            assert!(head.headers.len() < MAX_HEADERS);
            match plan(&head, &data) {
                Step::Reply(r) => check_reply(&r, u64::from(raw.len() as u32) << 20),
                Step::ReadBody(n) => {
                    assert!(n as i64 <= MAX_BODY);
                    let pos = cur.position() as usize;
                    let body = &raw[pos..raw.len().min(pos + n)];
                    let r = finish(body, &data);
                    assert!(r.code == 200 || r.code == 400);
                    check_reply(&r, u64::MAX);
                }
            }
            let _ = log_safe(&format!("{} {}", head.method, head.target));
        }
    }
}

/// Target 2: the same bytes as a data file, a target, a header value, a log line and a body.
pub fn check_misc(raw: &[u8]) {
    let data = parse_data(raw);
    let all = answer_all(&data);
    assert_eq!(all.as_object().expect("object").len(), TYPES.len());
    for k in TYPES {
        assert!(answer(&data, k).is_object());
    }
    let text = String::from_utf8_lossy(raw);
    let _ = query_type(&text);
    if let Some(k) = query_type(&text) {
        assert!(text.contains(k));
    }
    let _ = parse_content_length(Some(&text));
    let _ = parse_content_length(None);
    let safe = log_safe(&text);
    assert!(safe.chars().count() <= 200 * 4);
    assert!(
        !safe.chars().any(|c| c < ' ' || ('\u{7f}'..='\u{9f}').contains(&c)),
        "control char in log line"
    );
    let r = finish(raw, &sample());
    assert!(r.code == 200 || r.code == 400);
    check_reply(&r, raw.len() as u64);
    let secs = raw.iter().take(8).fold(0u64, |a, &b| a << 8 | u64::from(b));
    let d = http_date(secs);
    assert!(d.ends_with(" GMT"));
}
