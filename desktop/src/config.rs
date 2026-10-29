//! Local settings file (JSON): host, port, user, key path, chaos-ctl.sh path, admin character.
use serde_json::{json, Value};
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Config {
    pub host: String,
    pub port: u16,
    pub user: String,
    pub key_path: String,
    pub ctl_path: String,
    /// Admin character the game-panel actions run as (may be offline).
    pub actor: String,
    /// Check for a new version of this app at start.
    pub auto_update: bool,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            host: String::new(),
            port: 22,
            user: "chaosadmin".into(),
            key_path: String::new(),
            ctl_path: "/opt/chaos/repo/server/deploy/chaos-ctl.sh".into(),
            actor: String::new(),
            auto_update: true,
        }
    }
}

impl Config {
    pub fn configured(&self) -> bool {
        !self.host.trim().is_empty() && !self.user.trim().is_empty() && !self.key_path.trim().is_empty()
    }

    /// Reads settings text. Unknown keys are ignored, missing ones keep the default, a bad port keeps 22.
    pub fn parse(text: &str) -> Result<Config, String> {
        let v: Value = serde_json::from_str(text).map_err(|e| format!("settings file is not JSON: {e}"))?;
        let obj = v.as_object().ok_or("settings file is not a JSON object")?;
        let mut c = Config::default();
        let s = |k: &str, dst: &mut String| {
            if let Some(x) = obj.get(k).and_then(Value::as_str) {
                *dst = x.trim().to_string();
            }
        };
        s("host", &mut c.host);
        s("user", &mut c.user);
        s("key_path", &mut c.key_path);
        s("ctl_path", &mut c.ctl_path);
        s("actor", &mut c.actor);
        if let Some(p) = obj.get("port").and_then(Value::as_u64) {
            if (1..=65535).contains(&p) {
                c.port = p as u16;
            }
        }
        if let Some(b) = obj.get("auto_update").and_then(Value::as_bool) {
            c.auto_update = b;
        }
        Ok(c)
    }

    pub fn to_text(&self) -> String {
        let v = json!({
            "host": self.host, "port": self.port, "user": self.user, "key_path": self.key_path,
            "ctl_path": self.ctl_path, "actor": self.actor, "auto_update": self.auto_update,
        });
        serde_json::to_string_pretty(&v).unwrap_or_default() + "\n"
    }
}

/// Settings file: %APPDATA%\CindersAdmin\settings.json on Windows, ~/.config/cinders-admin/settings.json elsewhere.
pub fn path() -> PathBuf {
    let base = if cfg!(windows) {
        std::env::var_os("APPDATA").map(PathBuf::from)
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(PathBuf::from)
            .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))
    };
    base.unwrap_or_else(|| PathBuf::from("."))
        .join(if cfg!(windows) { "CindersAdmin" } else { "cinders-admin" })
        .join("settings.json")
}

pub fn load() -> Config {
    std::fs::read_to_string(path())
        .ok()
        .and_then(|t| Config::parse(&t).ok())
        .unwrap_or_default()
}

pub fn save(c: &Config) -> std::io::Result<()> {
    let p = path();
    if let Some(d) = p.parent() {
        std::fs::create_dir_all(d)?;
    }
    std::fs::write(p, c.to_text())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let c = Config {
            host: "203.0.113.5".into(),
            port: 2222,
            user: "chaosadmin".into(),
            key_path: "C:\\keys\\id".into(),
            actor: "Admin One".into(),
            ..Config::default()
        };
        assert_eq!(Config::parse(&c.to_text()).unwrap(), c);
        assert!(c.configured());
    }

    #[test]
    fn defaults_and_bad_values() {
        let c = Config::parse(r#"{"host":" h ","port":70000,"extra":1}"#).unwrap();
        assert_eq!(c.host, "h");
        assert_eq!(c.port, 22);
        assert!(!c.configured());
        assert!(Config::parse("[1]").is_err());
        assert!(Config::parse("nope").is_err());
    }
}
