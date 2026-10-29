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

/// Runs `remote` on the VPS. `stdin` goes to the command's standard input (passwords never on a command line).
pub fn exec(cfg: &Config, remote: &str, timeout_sec: u64, stdin: Option<&str>) -> Output {
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
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
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
    }
    // read both pipes on threads so a full pipe cannot stall the command
    let mut out = child.stdout.take();
    let mut err = child.stderr.take();
    let t1 = std::thread::spawn(move || {
        let mut v = Vec::new();
        if let Some(o) = out.as_mut() {
            let _ = std::io::Read::read_to_end(o, &mut v);
        }
        v
    });
    let t2 = std::thread::spawn(move || {
        let mut v = Vec::new();
        if let Some(o) = err.as_mut() {
            let _ = std::io::Read::read_to_end(o, &mut v);
        }
        v
    });
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
    fn unconfigured_does_not_spawn() {
        let o = exec(&Config::default(), "x", 1, None);
        assert_eq!(o.code, -1);
    }
}
