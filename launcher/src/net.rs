//! Network: the system `curl` (built into Windows 10 and 11, the same choice as the desktop admin app's updater), so
//! the launcher carries no TLS code of its own. A trait lets the tests use any fetcher; the integration test uses the
//! real one against a local HTTP server.
use std::fmt;
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::Duration;

/// A failed fetch: the text for the log line, and the HTTP status when the server answered with an error
/// (O494). With `--fail` curl exits 22 for every status of 400 or more, so the exit code alone says nothing about
/// 404 against 500. `http` is `None` for a transport failure (resolve, connect, timeout, TLS) and for a fake.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FetchError {
    pub detail: String,
    pub http: Option<u16>,
}

impl FetchError {
    pub fn http(status: u16, detail: impl Into<String>) -> FetchError {
        FetchError {
            detail: detail.into(),
            http: Some(status),
        }
    }
}

impl fmt::Display for FetchError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.detail)
    }
}

impl From<String> for FetchError {
    fn from(detail: String) -> Self {
        FetchError { detail, http: None }
    }
}

impl From<&str> for FetchError {
    fn from(detail: &str) -> Self {
        FetchError::from(detail.to_string())
    }
}

pub trait Fetch {
    /// Small answer in memory (the manifest).
    fn get(&self, url: &str) -> Result<Vec<u8>, FetchError>;
    /// A small optional answer (the launcher feed): a short time limit and a size limit. Never used for the update.
    fn get_small(&self, url: &str, _max_secs: u32, _max_bytes: u64) -> Result<Vec<u8>, FetchError> {
        self.get(url)
    }
    /// Appends to `part` from the byte it already holds (a `Range` request), calls `progress` with the size of `part`.
    /// Ok means the transfer ended without error; the caller still checks size and hash.
    fn download(&self, url: &str, part: &Path, progress: &mut dyn FnMut(u64)) -> Result<(), FetchError>;
}

pub struct Curl;

fn base(url: &str) -> Command {
    let mut c = Command::new("curl");
    c.args([
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--proto",
        "=http,https",
        "--proto-redir",
        "=https",
        "--connect-timeout",
        "20",
        // the HTTP status goes to stdout after the body (nothing but the status on a failure, `--fail` drops the
        // body). More robust than reading curl's error text: `%{http_code}` is the same on every curl, Windows
        // included, and is not a message that a curl release may reword.
        "-w",
        "%{http_code}",
        "-H",
        "User-Agent: cinders-launcher",
    ]);
    c.arg(url);
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        c.creation_flags(0x0800_0000);
    }
    c
}

fn failure(code: Option<i32>, stderr: &[u8]) -> String {
    format!(
        "curl {}: {}",
        code.map(|c| c.to_string()).unwrap_or_else(|| "killed".into()),
        String::from_utf8_lossy(stderr).trim()
    )
}

/// Cuts the `-w` status (the last three ASCII digits) off curl's stdout: the body and the status.
pub fn split_status(out: &[u8]) -> (&[u8], Option<u16>) {
    if out.len() >= 3 && out[out.len() - 3..].iter().all(u8::is_ascii_digit) {
        let (body, st) = out.split_at(out.len() - 3);
        let n = st.iter().fold(0u16, |a, d| a * 10 + u16::from(d - b'0'));
        return (body, Some(n));
    }
    (out, None)
}

/// The status in curl's own text, "The requested URL returned error: 404" (with " Not Found" on an old curl). Only a
/// fallback for when the `-w` status is missing.
pub fn status_from_stderr(stderr: &str) -> Option<u16> {
    const KEY: &str = "returned error: ";
    let rest = &stderr[stderr.find(KEY)? + KEY.len()..];
    let digits: String = rest.chars().take_while(char::is_ascii_digit).collect();
    digits.parse().ok().filter(|n| (400..=599).contains(n))
}

/// The error of a curl run that failed. Only exit 22 (`--fail`: the server answered with 400 or more) can carry an
/// HTTP status, and it must be a real error one. Every other exit code is a transport failure.
pub fn classify(code: Option<i32>, status: Option<u16>, stderr: &[u8]) -> FetchError {
    let detail = failure(code, stderr);
    let http = if code == Some(22) {
        status
            .filter(|n| (400..=599).contains(n))
            .or_else(|| status_from_stderr(&String::from_utf8_lossy(stderr)))
    } else {
        None
    };
    FetchError { detail, http }
}

fn finish(o: std::process::Output) -> Result<Vec<u8>, FetchError> {
    let (body, status) = split_status(&o.stdout);
    if o.status.success() {
        Ok(body.to_vec())
    } else {
        Err(classify(o.status.code(), status, &o.stderr))
    }
}

impl Fetch for Curl {
    fn get(&self, url: &str) -> Result<Vec<u8>, FetchError> {
        let mut c = base(url);
        c.args(["--max-time", "60", "--max-filesize", "4194304"]);
        let o = c.output().map_err(|e| format!("cannot start curl: {e}"))?;
        finish(o)
    }

    fn get_small(&self, url: &str, max_secs: u32, max_bytes: u64) -> Result<Vec<u8>, FetchError> {
        let mut c = base(url);
        c.args([
            "--connect-timeout",
            "5",
            "--max-time",
            &max_secs.to_string(),
            "--max-filesize",
            &max_bytes.to_string(),
        ]);
        let o = c.output().map_err(|e| format!("cannot start curl: {e}"))?;
        finish(o)
    }

    fn download(&self, url: &str, part: &Path, progress: &mut dyn FnMut(u64)) -> Result<(), FetchError> {
        let have = std::fs::metadata(part).map(|m| m.len()).unwrap_or(0);
        let mut c = base(url);
        // no overall time limit (the pack is large); a stalled link (under 1 KB/s for 30 s) ends the attempt
        c.args(["--speed-limit", "1024", "--speed-time", "30"]);
        if have > 0 {
            c.args(["-C", "-"]);
        }
        c.arg("-o").arg(part);
        c.stdout(Stdio::piped()).stderr(Stdio::piped());
        let mut child = c.spawn().map_err(|e| format!("cannot start curl: {e}"))?;
        loop {
            match child.try_wait() {
                Ok(Some(_)) => break,
                Ok(None) => {
                    progress(std::fs::metadata(part).map(|m| m.len()).unwrap_or(0));
                    std::thread::sleep(Duration::from_millis(25));
                }
                Err(e) => return Err(e.to_string().into()),
            }
        }
        let o = child.wait_with_output().map_err(|e| e.to_string())?;
        progress(std::fs::metadata(part).map(|m| m.len()).unwrap_or(0));
        if o.status.success() {
            Ok(())
        } else {
            let code = o.status.code();
            // 33: the server ignored the Range request; 36: bad resume offset. The bytes on disk are of no use.
            if matches!(code, Some(33) | Some(36)) {
                let _ = std::fs::remove_file(part);
            }
            Err(classify(code, split_status(&o.stdout).1, &o.stderr))
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn http_of(code: Option<i32>, status: Option<u16>, stderr: &str) -> Option<u16> {
        classify(code, status, stderr.as_bytes()).http
    }

    #[test]
    fn status_is_cut_off_the_output() {
        assert_eq!(split_status(b"404"), (&b""[..], Some(404)));
        assert_eq!(split_status(b"{\"a\":1}200"), (&b"{\"a\":1}"[..], Some(200)));
        assert_eq!(split_status(b"body"), (&b"body"[..], None));
        assert_eq!(split_status(b""), (&b""[..], None));
        assert_eq!(split_status(b"12"), (&b"12"[..], None));
        // a body that itself ends in digits is cut at the last three only
        assert_eq!(split_status(b"v1234200"), (&b"v1234"[..], Some(200)));
    }

    #[test]
    fn status_from_curl_text() {
        let m = "curl: (22) The requested URL returned error: 404";
        assert_eq!(status_from_stderr(m), Some(404));
        assert_eq!(
            status_from_stderr("curl: (22) The requested URL returned error: 410 Gone"),
            Some(410)
        );
        assert_eq!(status_from_stderr("curl: (6) Could not resolve host: x.test"), None);
        assert_eq!(status_from_stderr("returned error: 200"), None);
        assert_eq!(status_from_stderr("returned error: "), None);
    }

    #[test]
    fn exit_22_carries_the_status() {
        for n in [404u16, 410, 500, 403, 503] {
            assert_eq!(http_of(Some(22), Some(n), "curl: (22) x"), Some(n));
        }
        // no -w status: curl's own text
        let m = "curl: (22) The requested URL returned error: 404";
        assert_eq!(http_of(Some(22), None, m), Some(404));
        // exit 22 with no status anywhere: no HTTP status, a plain failure
        assert_eq!(http_of(Some(22), None, "curl: (22) odd"), None);
        assert_eq!(http_of(Some(22), Some(0), "curl: (22) odd"), None);
        assert_eq!(http_of(Some(22), Some(200), "curl: (22) odd"), None);
    }

    #[test]
    fn transport_failures_have_no_status() {
        for code in [6, 7, 28, 35, 60] {
            // even when a status is present (a redirect chain that ended in an error page, say)
            assert_eq!(http_of(Some(code), Some(404), "curl: x"), None, "{code}");
            assert_eq!(http_of(Some(code), None, "curl: x"), None, "{code}");
        }
        assert_eq!(http_of(None, None, ""), None);
        let e = classify(Some(7), None, b"curl: (7) refused");
        assert_eq!(e.detail, "curl 7: curl: (7) refused");
        assert_eq!(e.to_string(), e.detail);
    }
}
