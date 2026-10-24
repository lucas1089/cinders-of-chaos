//! Unit tests and property tests of the request parser and the handlers (no sockets).
//! `cargo test --locked`. The parser is the untrusted surface: whatever bytes arrive, it returns a value or an
//! error, never panics, and never reads more than its limits.

use clientservices::*;
use proptest::prelude::*;
use serde_json::{json, Map, Value};
use std::io::Cursor;

fn data() -> Map<String, Value> {
    match json!({
        "boostedcreature": {"name": "Rotworm"},
        "eventschedule": [],
        "cacheinfo": {"playersonline": 3, "online": "3 players online"}
    }) {
        Value::Object(m) => m,
        _ => unreachable!(),
    }
}

fn head(raw: &[u8]) -> Result<Head, HeadError> {
    read_head(&mut Cursor::new(raw.to_vec()))
}

#[test]
fn parses_a_get() {
    let h = head(b"GET /clientservices?type=cacheinfo HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\n\r\n").unwrap();
    assert_eq!(h.method, "GET");
    assert_eq!(h.target, "/clientservices?type=cacheinfo");
    assert_eq!(h.header("content-length"), Some("5"));
    assert_eq!(h.header("HOST"), Some("x"));
}

#[test]
fn head_errors() {
    assert_eq!(head(b""), Err(HeadError::Closed));
    assert_eq!(head(b"\r\n"), Err(HeadError::Closed));
    assert_eq!(head(b"GET /\r\n\r\n"), Err(HeadError::Bad));
    assert_eq!(head(b"GET / FTP/1.0\r\n\r\n"), Err(HeadError::Bad));
    assert_eq!(head(b"GET / HTTP/1.x\r\n\r\n"), Err(HeadError::Bad));
    assert_eq!(head(b"GET / HTTP/1.1.1\r\n\r\n"), Err(HeadError::Bad));
    assert_eq!(head(b"GET / HTTP/2.0\r\n\r\n"), Err(HeadError::Version));
    let long = [b"GET /".as_slice(), &vec![b'a'; MAX_LINE], b" HTTP/1.1\r\n\r\n"].concat();
    assert_eq!(head(&long), Err(HeadError::LineTooLong));
    let long = [b"GET / HTTP/1.1\r\nX: ".as_slice(), &vec![b'a'; MAX_LINE], b"\r\n\r\n"].concat();
    assert_eq!(head(&long), Err(HeadError::HeadersTooLarge));
    let many: Vec<u8> = (0..MAX_HEADERS)
        .flat_map(|i| format!("X{i}: 1\r\n").into_bytes())
        .collect();
    assert_eq!(
        head(&[b"GET / HTTP/1.1\r\n".as_slice(), &many, b"\r\n"].concat()),
        Err(HeadError::HeadersTooLarge)
    );
    let ok: Vec<u8> = (0..MAX_HEADERS - 1)
        .flat_map(|i| format!("X{i}: 1\r\n").into_bytes())
        .collect();
    assert!(head(&[b"GET / HTTP/1.1\r\n".as_slice(), &ok, b"\r\n"].concat()).is_ok());
}

#[test]
fn a_line_that_is_not_a_header_ends_the_headers() {
    let h = head(b"POST / HTTP/1.1\r\nbroken\r\nContent-Length: 20\r\n\r\n").unwrap();
    assert_eq!(h.header("content-length"), None);
}

#[test]
fn content_length() {
    assert_eq!(parse_content_length(None), 0);
    assert_eq!(parse_content_length(Some("")), 0);
    assert_eq!(parse_content_length(Some("  12 ")), 12);
    assert_eq!(parse_content_length(Some("+12")), 12);
    assert_eq!(parse_content_length(Some("-3")), -3);
    assert_eq!(parse_content_length(Some("abc")), -1);
    assert_eq!(parse_content_length(Some("1 2")), -1);
    assert_eq!(parse_content_length(Some("-")), -1);
    assert_eq!(parse_content_length(Some("99999999999999999999999")), i64::MAX);
    assert_eq!(parse_content_length(Some("-99999999999999999999999")), -1);
}

#[test]
fn query() {
    assert_eq!(query_type("/"), None);
    assert_eq!(query_type("/?type=a"), Some("a"));
    assert_eq!(query_type("/?x=1&type=a&type=b"), Some("b"));
    assert_eq!(query_type("/?type"), Some(""));
    assert_eq!(query_type("/?a?type=x"), None);
    assert_eq!(query_type("/?Type=a"), None);
}

#[test]
fn get_answers() {
    let d = data();
    let get = |t: &str| {
        plan(
            &Head {
                method: "GET".into(),
                target: t.into(),
                headers: vec![],
            },
            &d,
        )
    };
    assert_eq!(
        get("/?type=cacheinfo"),
        Step::Reply(Reply {
            code: 200,
            body: Some(json!({"playersonline": 3, "online": "3 players online"}))
        })
    );
    // [] in the file (Lua's empty table) becomes the empty object / list the client wants
    assert_eq!(
        get("/?type=eventschedule"),
        Step::Reply(Reply {
            code: 200,
            body: Some(json!({"eventlist": []}))
        })
    );
    match get("/") {
        Step::Reply(Reply {
            code: 200,
            body: Some(Value::Object(m)),
        }) => assert_eq!(m.len(), 3),
        other => panic!("{other:?}"),
    }
    assert_eq!(get("/?type=zzz"), get("/"));
}

#[test]
fn post_answers() {
    let d = data();
    let r = finish(br#"{"type": "boostedcreature"}"#, &d);
    assert_eq!((r.code, r.body), (200, Some(json!({"name": "Rotworm"}))));
    for bad in [
        &b"{"[..],
        b"[]",
        b"5",
        b"{\"type\":1}",
        b"{\"type\":null}",
        b"{}",
        b"",
        b"\xff",
    ] {
        let r = finish(bad, &d);
        assert_eq!(r.code, 400, "{bad:?}");
    }
    assert_eq!(finish(b"{", &d).body, Some(json!({"error": "invalid json"})));
    assert_eq!(
        finish(b"{}", &d).body,
        Some(json!({"error": "unknown type", "types": TYPES}))
    );
    let post = |len: &str| {
        plan(
            &Head {
                method: "POST".into(),
                target: "/".into(),
                headers: vec![("Content-Length".into(), len.into())],
            },
            &d,
        )
    };
    assert_eq!(post("65536"), Step::ReadBody(65536));
    assert_eq!(post("0"), Step::ReadBody(0));
    for len in ["65537", "-1", "x", "99999999999999999999999"] {
        assert!(matches!(post(len), Step::Reply(Reply { code: 413, .. })), "{len}");
    }
}

#[test]
fn other_methods() {
    let d = data();
    for m in ["PUT", "DELETE", "HEAD", "PATCH", "get", "CONNECT", "TRACE"] {
        let s = plan(
            &Head {
                method: m.into(),
                target: "/".into(),
                headers: vec![],
            },
            &d,
        );
        assert!(matches!(s, Step::Reply(Reply { code: 501, .. })), "{m}");
    }
    let s = plan(
        &Head {
            method: "OPTIONS".into(),
            target: "/".into(),
            headers: vec![],
        },
        &d,
    );
    assert_eq!(s, Step::Reply(Reply { code: 204, body: None }));
}

#[test]
fn data_files() {
    assert!(parse_data(b"[1]").is_empty());
    assert!(parse_data(b"garbage").is_empty());
    assert!(parse_data(b"").is_empty());
    assert_eq!(parse_data(b"{\"a\": 1}").len(), 1);
    assert!(load(std::path::Path::new("/nonexistent/clientservices.json")).is_empty());
}

#[test]
fn rendering() {
    assert_eq!(http_date(784111777), "Sun, 06 Nov 1994 08:49:37 GMT");
    assert_eq!(http_date(0), "Thu, 01 Jan 1970 00:00:00 GMT");
    assert_eq!(http_date(951782400), "Tue, 29 Feb 2000 00:00:00 GMT");
    let out = String::from_utf8(render(
        &Reply {
            code: 200,
            body: Some(json!({"a": 1})),
        },
        0,
    ))
    .unwrap();
    assert!(out.starts_with("HTTP/1.0 200 OK\r\n"));
    assert!(out.contains("Content-Length: 7\r\n"));
    assert!(out.contains("Access-Control-Allow-Origin: *\r\n"));
    assert!(out.ends_with("\r\n\r\n{\"a\":1}"));
    let out = String::from_utf8(render(&Reply { code: 204, body: None }, 0)).unwrap();
    assert!(out.contains("Content-Length: 0\r\n") && !out.contains("Content-Type: application"));
    assert_eq!(log_safe("GET /\r\nFAKE 200"), "GET /\\x0d\\x0aFAKE 200");
    assert_eq!(log_safe(&"a".repeat(500)).len(), 200);
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(2000))]

    /// Any bytes: a head or an error, no panic, and the reader is never read past the limits.
    #[test]
    fn read_head_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..4096)) {
        let mut c = Cursor::new(bytes.clone());
        let _ = read_head(&mut c);
        prop_assert!(c.position() as usize <= bytes.len());
    }

    /// Request-shaped input (so the parser goes past the first line): same promise.
    #[test]
    fn read_head_on_request_shapes(
        method in "[A-Za-z]{0,8}", target in "[ -~]{0,64}", ver in "HTTP/[0-9]\\.[0-9]|[ -~]{0,8}",
        hdrs in proptest::collection::vec(("[A-Za-z-]{0,16}", "[ -~\\t]{0,64}"), 0..120),
        nl in prop_oneof![Just("\r\n"), Just("\n")],
    ) {
        let mut raw = format!("{method} {target} {ver}{nl}");
        for (k, v) in &hdrs {
            raw.push_str(&format!("{k}: {v}{nl}"));
        }
        raw.push_str(nl);
        if let Ok(h) = read_head(&mut Cursor::new(raw.into_bytes())) {
            prop_assert!(h.headers.len() < MAX_HEADERS);
        }
    }

    /// A parsed head always plans to a reply or a body read inside the limit.
    #[test]
    fn plan_is_bounded(method in "[A-Z]{1,8}", target in "[ -~]{0,64}", len in "[ -~]{0,30}") {
        let h = Head { method, target, headers: vec![("Content-Length".into(), len)] };
        match plan(&h, &data()) {
            Step::ReadBody(n) => prop_assert!(n as i64 <= MAX_BODY),
            Step::Reply(r) => prop_assert!([200, 204, 413, 501].contains(&r.code)),
        }
    }

    /// Any POST body: 200 with a part of the file, or 400; never a panic.
    #[test]
    fn finish_never_panics(body in proptest::collection::vec(any::<u8>(), 0..2048)) {
        let r = finish(&body, &data());
        prop_assert!(r.code == 200 || r.code == 400);
    }

    /// Any data file: a map, never a panic; every answer is a JSON object.
    #[test]
    fn data_file_never_panics(bytes in proptest::collection::vec(any::<u8>(), 0..2048)) {
        let m = parse_data(&bytes);
        for k in TYPES {
            prop_assert!(answer(&m, k).is_object());
        }
    }

    /// The Content-Length rule: in range only for a plain number up to 64 KiB.
    #[test]
    fn content_length_in_range_means_a_number(s in "[ -~]{0,12}") {
        let n = parse_content_length(Some(&s));
        if (0..=MAX_BODY).contains(&n) && !s.trim().is_empty() {
            prop_assert!(s.trim().trim_start_matches('+').bytes().all(|b| b.is_ascii_digit()));
        }
    }

    /// query_type returns a slice of the target.
    #[test]
    fn query_type_is_inside_the_target(t in "[ -~]{0,80}") {
        if let Some(v) = query_type(&t) {
            prop_assert!(t.contains(v));
        }
    }
}
