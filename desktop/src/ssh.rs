//! Transport: the system `ssh` program (OpenSSH, built into Windows 10 and 11), the same key, host and user the Android
//! app uses, running the same `chaos-ctl.sh` commands. No new port or service on the VPS, no ssh library in this app.
use crate::config::Config;
use std::io::Write;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

/// Single quotes around a text for the remote shell.
pub fn sq(s: &str) -> String {
    format!("'{}'", s.replace('\'', "'\\''"))
}

/// The remote command line for one chaos-ctl.sh call: `'/path/chaos-ctl.sh' args`.
pub fn ctl_line(cfg: &Config, args: &str) -> String {
    format!("{} {}", sq(&cfg.ctl_path), args)
}

/// The arguments of the `ssh` program (the remote command is one argument).
pub fn ssh_args(cfg: &Config, remote: &str) -> Vec<String> {
    let mut a: Vec<String> = vec![
        "-i".into(),
        cfg.key_path.clone(),
        "-p".into(),
        cfg.port.to_string(),
        "-o".into(),
        "BatchMode=yes".into(),
        "-o".into(),
        "IdentitiesOnly=yes".into(),
        // the host key is pinned on first use, like the phone app; a changed key is refused
        "-o".into(),
        "StrictHostKeyChecking=accept-new".into(),
        "-o".into(),
        "ConnectTimeout=12".into(),
        "-o".into(),
        "ServerAliveInterval=15".into(),
        format!("{}@{}", cfg.user, cfg.host),
        "--".into(),
    ];
    a.push(remote.to_string());
    a
}

#[derive(Debug, Clone)]
pub struct Output {
    pub text: String,
    /// Exit status of the remote command; -1 when it was cut (timeout) or ssh did not start.
    pub code: i32,
}

/// Windows: the child gets no console window (CREATE_NO_WINDOW). The app is a windows-subsystem program with no
/// console of its own (O383), so without this flag every ssh, ssh-keygen or curl call would flash a new console.
/// Other systems: nothing to do.
pub fn hide_console(cmd: &mut Command) -> &mut Command {
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    cmd
}

/// The Windows process creation flag of `hide_console`.
pub const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Streamed output: called with each piece of stdout or stderr text as it arrives (from reader threads).
pub type OnText = std::sync::Arc<dyn Fn(&str) + Send + Sync>;

/// Runs `remote` on the VPS. `stdin` goes to the command's standard input (passwords never on a command line).
pub fn exec(cfg: &Config, remote: &str, timeout_sec: u64, stdin: Option<&str>) -> Output {
    exec_stream(cfg, remote, timeout_sec, stdin, None)
}

/// Reads one pipe to the end; each piece also goes to `on` as text.
fn drain<R: std::io::Read>(pipe: Option<R>, on: Option<OnText>) -> Vec<u8> {
    let mut all = Vec::new();
    let Some(mut r) = pipe else { return all };
    let mut buf = [0u8; 8192];
    let mut text = crate::output::Utf8Chunks::default();
    loop {
        match r.read(&mut buf) {
            Ok(0) | Err(_) => break,
            Ok(n) => {
                all.extend_from_slice(&buf[..n]);
                if let Some(f) = &on {
                    let t = text.push(&buf[..n]);
                    if !t.is_empty() {
                        f(&t);
                    }
                }
            }
        }
    }
    all
}

/// `exec`, and every piece of output also goes to `on` while the command runs (the output panel follows it). The
/// returned text is the same as `exec` gives (stdout, then stderr).
pub fn exec_stream(cfg: &Config, remote: &str, timeout_sec: u64, stdin: Option<&str>, on: Option<OnText>) -> Output {
    if !cfg.configured() {
        return Output {
            text: "Not configured: fill host, user and key path in Settings.".into(),
            code: -1,
        };
    }
    let mut cmd = Command::new("ssh");
    cmd.args(ssh_args(cfg, remote))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    hide_console(&mut cmd);
    let mut child = match cmd.spawn() {
        Ok(c) => c,
        Err(e) => {
            return Output {
                text: format!("Cannot start ssh ({e}). Is OpenSSH installed?"),
                code: -1,
            };
        }
    };
    if let Some(mut si) = child.stdin.take() {
        if let Some(s) = stdin {
            let _ = si.write_all(s.as_bytes());
        }
        // dropped here: the remote command sees the end of its input and never waits on it
    }
    // read both pipes on threads so a full pipe cannot stall the command
    let out = child.stdout.take();
    let err = child.stderr.take();
    let on2 = on.clone();
    let t1 = std::thread::spawn(move || drain(out, on));
    let t2 = std::thread::spawn(move || drain(err, on2));
    let end = Instant::now() + Duration::from_secs(timeout_sec);
    let mut code = -1;
    let mut timed_out = false;
    loop {
        match child.try_wait() {
            Ok(Some(st)) => {
                code = st.code().unwrap_or(-1);
                break;
            }
            Ok(None) if Instant::now() > end => {
                let _ = child.kill();
                let _ = child.wait();
                timed_out = true;
                break;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(60)),
            Err(_) => break,
        }
    }
    let mut text = String::from_utf8_lossy(&t1.join().unwrap_or_default()).into_owned();
    let e = String::from_utf8_lossy(&t2.join().unwrap_or_default()).into_owned();
    if !e.trim().is_empty() {
        if !text.is_empty() && !text.ends_with('\n') {
            text.push('\n');
        }
        text.push_str(&e);
    }
    if timed_out {
        text.push_str("\n[timed out]\n");
    }
    Output { text, code }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn quotes() {
        assert_eq!(sq("a b"), "'a b'");
        assert_eq!(sq("it's"), "'it'\\''s'");
        assert_eq!(sq("$(rm -rf /)"), "'$(rm -rf /)'");
    }

    #[test]
    fn args_shape() {
        let cfg = Config {
            host: "h".into(),
            user: "u".into(),
            key_path: "k".into(),
            port: 2200,
            ..Config::default()
        };
        let a = ssh_args(&cfg, "x");
        assert_eq!(a[..4], ["-i", "k", "-p", "2200"]);
        assert_eq!(a[a.len() - 3], "u@h");
        assert_eq!(a[a.len() - 2], "--");
        assert_eq!(a[a.len() - 1], "x");
        assert!(ctl_line(&cfg, "status").ends_with(" status"));
    }

    #[test]
    fn drain_streams_every_piece() {
        use std::sync::{Arc, Mutex};
        let seen = Arc::new(Mutex::new(String::new()));
        let s2 = seen.clone();
        let on: OnText = Arc::new(move |t: &str| s2.lock().unwrap().push_str(t));
        let text = "linha um\nação dois\n".repeat(2000);
        let all = drain(Some(std::io::Cursor::new(text.clone().into_bytes())), Some(on));
        assert_eq!(all, text.as_bytes());
        assert_eq!(*seen.lock().unwrap(), text);
        assert!(drain(None::<std::io::Cursor<Vec<u8>>>, None).is_empty());
    }

    #[test]
    fn unconfigured_does_not_spawn() {
        let o = exec(&Config::default(), "x", 1, None);
        assert_eq!(o.code, -1);
    }
}
