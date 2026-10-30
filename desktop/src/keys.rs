//! The SSH key of this PC: make one with the system `ssh-keygen` and build the install command the owner runs on the
//! VPS as root (the same `install-admin -` line the Android app copies). The public key is always derived from the
//! private key file (`ssh-keygen -y`), never read from a `.pub` beside it: a stale `.pub` once made the VPS refuse
//! the PC (2026-10-30).
use crate::ssh::sq;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

/// Where a new key goes: next to the settings file.
pub fn default_path() -> PathBuf {
    crate::config::path().with_file_name("cinders_admin_ed25519")
}

/// One ssh public key line, the shape `chaos-ctl.sh install-admin` accepts.
pub fn valid_public(line: &str) -> bool {
    let mut it = line.split(' ');
    let kind = it.next().unwrap_or("");
    let body = it.next().unwrap_or("");
    matches!(kind, "ssh-rsa" | "ssh-ed25519" | "ecdsa-sha2-nistp256")
        && !body.is_empty()
        && body
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'+' || b == b'/' || b == b'=')
        && !line.chars().any(|c| c.is_control())
        && line.len() <= 2000
}

/// The line to paste on the VPS as root: adds this key for the admin user and keeps the others.
pub fn install_command(public: &str, ctl_path: &str) -> String {
    format!("echo {} | sudo {} install-admin -", sq(public.trim()), sq(ctl_path))
}

fn run(args: &[&str]) -> Result<String, String> {
    let mut cmd = Command::new("ssh-keygen");
    cmd.args(args)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        cmd.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }
    let out = cmd
        .output()
        .map_err(|e| format!("ssh-keygen não abriu ({e}). O OpenSSH está instalado?"))?;
    if out.status.success() {
        Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
    } else {
        Err(String::from_utf8_lossy(&out.stderr).trim().to_string())
    }
}

/// The public key line of a private key file (no passphrase: the app logs in with BatchMode).
pub fn public_of(private: &Path) -> Result<String, String> {
    if !private.is_file() {
        return Err(format!("o arquivo {} não existe", private.display()));
    }
    let p = private.to_string_lossy();
    let line = run(&["-y", "-P", "", "-f", &p]).map_err(|e| format!("não li a chave: {e}"))?;
    let line = line.lines().next().unwrap_or("").to_string();
    if valid_public(&line) {
        Ok(line)
    } else {
        Err("ssh-keygen não devolveu uma chave pública".into())
    }
}

/// Makes an ed25519 key without passphrase at `private`; refuses to overwrite a file that is there.
pub fn generate(private: &Path) -> Result<String, String> {
    if private.exists() {
        return Err(format!(
            "{} já existe: use essa chave ou apague o arquivo antes",
            private.display()
        ));
    }
    if let Some(dir) = private.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("não criei a pasta {}: {e}", dir.display()))?;
    }
    let p = private.to_string_lossy();
    run(&["-q", "-t", "ed25519", "-N", "", "-C", "cinders-admin-pc", "-f", &p])
        .map_err(|e| format!("ssh-keygen falhou: {e}"))?;
    public_of(private)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_line_shape() {
        assert!(valid_public(
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+b/= cinders-admin-pc"
        ));
        assert!(valid_public("ssh-rsa AAAAB3Nza"));
        assert!(!valid_public("ssh-dss AAAAB3Nza"));
        assert!(!valid_public("ssh-ed25519"));
        assert!(!valid_public("ssh-ed25519 AAAA;rm"));
        assert!(!valid_public("ssh-ed25519 AAAA x\ny"));
    }

    #[test]
    fn install_line_matches_the_phone() {
        assert_eq!(
            install_command("ssh-ed25519 AAAA pc\n", "/opt/chaos/repo/server/deploy/chaos-ctl.sh"),
            "echo 'ssh-ed25519 AAAA pc' | sudo '/opt/chaos/repo/server/deploy/chaos-ctl.sh' install-admin -"
        );
        assert_eq!(
            install_command("ssh-rsa AA it's", "/x"),
            "echo 'ssh-rsa AA it'\\''s' | sudo '/x' install-admin -"
        );
    }

    #[test]
    fn generate_and_read_back() {
        if Command::new("ssh-keygen").arg("-?").output().is_err() {
            return; // no ssh-keygen on this machine
        }
        let dir = std::env::temp_dir().join(format!("cinders-keys-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let key = dir.join("k");
        let public = generate(&key).expect("generate");
        assert!(public.starts_with("ssh-ed25519 ") && public.ends_with(" cinders-admin-pc"));
        // a stale .pub beside it does not count
        std::fs::write(dir.join("k.pub"), "ssh-ed25519 AAAAstale other\n").unwrap();
        assert_eq!(public_of(&key).unwrap(), public);
        assert!(generate(&key).is_err(), "an existing key is never overwritten");
        assert!(public_of(&dir.join("missing")).is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }
}
