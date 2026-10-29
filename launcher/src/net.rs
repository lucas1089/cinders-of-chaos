//! Network: the system `curl` (built into Windows 10 and 11, the same choice as the desktop admin app's updater), so
//! the launcher carries no TLS code of its own. A trait lets the tests use any fetcher; the integration test uses the
//! real one against a local HTTP server.
use std::path::Path;
use std::process::{Command, Stdio};
use std::time::Duration;

pub trait Fetch {
    /// Small answer in memory (the manifest).
    fn get(&self, url: &str) -> Result<Vec<u8>, String>;
    /// A small optional answer (the launcher feed): a short time limit and a size limit. Never used for the update.
    fn get_small(&self, url: &str, _max_secs: u32, _max_bytes: u64) -> Result<Vec<u8>, String> {
        self.get(url)
    }
    /// Appends to `part` from the byte it already holds (a `Range` request), calls `progress` with the size of `part`.
    /// Ok means the transfer ended without error; the caller still checks size and hash.
    fn download(&self, url: &str, part: &Path, progress: &mut dyn FnMut(u64)) -> Result<(), String>;
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

impl Fetch for Curl {
    fn get(&self, url: &str) -> Result<Vec<u8>, String> {
        let mut c = base(url);
        c.args(["--max-time", "60", "--max-filesize", "4194304"]);
        let o = c.output().map_err(|e| format!("cannot start curl: {e}"))?;
        if o.status.success() {
            Ok(o.stdout)
        } else {
            Err(failure(o.status.code(), &o.stderr))
        }
    }

    fn get_small(&self, url: &str, max_secs: u32, max_bytes: u64) -> Result<Vec<u8>, String> {
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
        if o.status.success() {
            Ok(o.stdout)
        } else {
            Err(failure(o.status.code(), &o.stderr))
        }
    }

    fn download(&self, url: &str, part: &Path, progress: &mut dyn FnMut(u64)) -> Result<(), String> {
        let have = std::fs::metadata(part).map(|m| m.len()).unwrap_or(0);
        let mut c = base(url);
        // no overall time limit (the pack is large); a stalled link (under 1 KB/s for 30 s) ends the attempt
        c.args(["--speed-limit", "1024", "--speed-time", "30"]);
        if have > 0 {
            c.args(["-C", "-"]);
        }
        c.arg("-o").arg(part);
        c.stdout(Stdio::null()).stderr(Stdio::piped());
        let mut child = c.spawn().map_err(|e| format!("cannot start curl: {e}"))?;
        loop {
            match child.try_wait() {
                Ok(Some(_)) => break,
                Ok(None) => {
                    progress(std::fs::metadata(part).map(|m| m.len()).unwrap_or(0));
                    std::thread::sleep(Duration::from_millis(25));
                }
                Err(e) => return Err(e.to_string()),
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
            Err(failure(code, &o.stderr))
        }
    }
}
