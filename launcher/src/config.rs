//! `launcher.json` beside the launcher. The Windows package workflow writes it (client/tools/set_launcher_config.py);
//! it holds the same three facts as `Services.update` in the client's init.lua.
use crate::i18n::Error;
use crate::manifest::Layout;
use serde_json::Value;
use std::path::{Path, PathBuf};

pub const FILE: &str = "launcher.json";
/// The Unity client lives in this sub-folder of the install folder, with its own `.cinders_launcher` state.
pub const UNITY_DIR: &str = "unity";
pub const UNITY_GAME: &str = "ChaosUnity.exe";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
    /// URL of the signed manifest (`manifest.json`). HTTPS, or HTTP only to a loopback address (tests).
    pub manifest_url: String,
    /// Ed25519 public key, the same as `Services.update.publicKey`.
    pub public_key: [u8; 32],
    /// Update version of the package's own files (`Services.update.baseline`): a manifest below it is refused.
    pub baseline: u64,
    /// The game program, a plain file name in the install folder. The manifest's `native.game` wins when it is there.
    pub game: String,
    /// Extra arguments for the game.
    pub args: Vec<String>,
    /// URL of the website's launcher feed (news and changelog), or `None` when the panels stay hidden.
    pub feed: Option<String>,
    /// The install folder: where `launcher.json` lives.
    pub dir: PathBuf,
    /// URL of the Unity client's signed manifest, or `None` when the choice "Unity client (beta)" is not offered.
    pub unity_manifest: Option<String>,
    /// The Unity player program (the manifest's `native.game` wins when it is there).
    pub unity_game: String,
    /// How the `native` section of this config's manifest is laid out (`Tree` only for the Unity client).
    pub layout: Layout,
}

pub fn decode_hex(s: &str) -> Option<Vec<u8>> {
    if !s.len().is_multiple_of(2) || !s.is_ascii() {
        return None;
    }
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok())
        .collect()
}

/// True for a plain file name: no folder, no drive, no dot segment.
pub fn is_plain_name(n: &str) -> bool {
    !n.is_empty()
        && n.len() <= 64
        && n.as_bytes()[0].is_ascii_alphanumeric()
        && n.bytes()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'-'))
}

pub fn loopback_http(url: &str) -> bool {
    [
        "http://127.0.0.1:",
        "http://127.0.0.1/",
        "http://localhost:",
        "http://localhost/",
    ]
    .iter()
    .any(|p| url.starts_with(p))
}

/// The feed address of an old `launcher.json` without the key: the site root of the update URL
/// (`https://site/updates/live/manifest.json` -> `https://site/chaos_launcher_feed.php`), or `None`.
pub fn derive_feed(manifest_url: &str) -> Option<String> {
    let at = manifest_url.find("/updates/")?;
    Some(format!("{}/{}", &manifest_url[..at], FEED_NAME))
}

pub const FEED_NAME: &str = "chaos_launcher_feed.php";

/// The four link buttons of the window (O552). Each is `None` (the button is hidden) or an `https://` address.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Links {
    pub discord: Option<String>,
    pub site: Option<String>,
    pub wiki: Option<String>,
    pub signup: Option<String>,
}

/// `https://host` of a manifest address.
fn origin(url: &str) -> Option<String> {
    let rest = url.strip_prefix("https://")?;
    let end = rest.find('/').unwrap_or(rest.len());
    (end > 0).then(|| format!("https://{}", &rest[..end]))
}

/// Reads `links` of `launcher.json`: `{"discord": URL, "site": URL, "wiki": URL, "signup": URL}`. A key that is absent
/// is derived from the site of the manifest (`/`, `/wiki`, `/register`; Discord has no default); a key that is `""`,
/// not a string or not an `https://` address hides its button. A wrong link setting never stops anything.
pub fn parse_links(text: &str, manifest_url: &str) -> Links {
    let v: Value = serde_json::from_str(text).unwrap_or(Value::Null);
    let block = v.get("links").filter(|b| b.is_object());
    let site = origin(manifest_url);
    let pick = |key: &str, default: Option<String>| -> Option<String> {
        match block.and_then(|b| b.get(key)) {
            None => default,
            Some(u) => u
                .as_str()
                .filter(|u| {
                    (u.starts_with("https://") || loopback_http(u))
                        && u.len() <= 300
                        && u.is_ascii()
                        && !u.chars().any(|c| c.is_ascii_control() || c.is_whitespace())
                })
                .map(str::to_string),
        }
    };
    Links {
        discord: pick("discord", None),
        site: pick("site", site.as_ref().map(|s| format!("{s}/"))),
        wiki: pick("wiki", site.as_ref().map(|s| format!("{s}/wiki"))),
        signup: pick("signup", site.as_ref().map(|s| format!("{s}/register"))),
    }
}

pub fn load_links(dir: &Path, manifest_url: &str) -> Links {
    let text = std::fs::read_to_string(dir.join(FILE)).unwrap_or_default();
    parse_links(&text, manifest_url)
}

/// The Unity channel of an old `launcher.json` without the key: the same site and key, the folder `updates/unity/`
/// (`https://site/updates/live/manifest.json` -> `https://site/updates/unity/manifest.json`), or `None` when the update
/// URL does not have that shape.
pub fn derive_unity(manifest_url: &str) -> Option<String> {
    let (base, query) = match manifest_url.find(['?', '#']) {
        Some(i) => manifest_url.split_at(i),
        None => (manifest_url, ""),
    };
    let at = base.find("/updates/")? + "/updates/".len();
    let rest = &base[at..];
    let (channel, file) = rest.split_once('/')?;
    if channel.is_empty() || file != "manifest.json" {
        return None;
    }
    Some(format!("{}{UNITY_DIR}/{file}{query}", &base[..at]))
}

pub fn parse(text: &str, dir: &Path) -> Result<Config, Error> {
    let bad = |d: &str| Error::Config(d.to_string());
    let v: Value = serde_json::from_str(text).map_err(|e| bad(&format!("not JSON: {e}")))?;
    let manifest_url = v
        .get("manifest")
        .and_then(Value::as_str)
        .ok_or_else(|| bad("manifest"))?
        .to_string();
    if !(manifest_url.starts_with("https://") || loopback_http(&manifest_url)) {
        return Err(bad("manifest must be an https:// URL"));
    }
    let key = v
        .get("public_key")
        .and_then(Value::as_str)
        .ok_or_else(|| bad("public_key"))?;
    let public_key: [u8; 32] = decode_hex(key)
        .and_then(|b| b.try_into().ok())
        .ok_or_else(|| bad("public_key must be 64 hex digits"))?;
    let baseline = match v.get("baseline") {
        None => 0,
        Some(b) => b.as_u64().ok_or_else(|| bad("baseline"))?,
    };
    let game = v.get("game").and_then(Value::as_str).unwrap_or("Chaos.exe").to_string();
    if !is_plain_name(&game) {
        return Err(bad("game must be a plain file name"));
    }
    let args = match v.get("args") {
        None => Vec::new(),
        Some(a) => a
            .as_array()
            .ok_or_else(|| bad("args"))?
            .iter()
            .map(|x| x.as_str().map(str::to_string).ok_or_else(|| bad("args")))
            .collect::<Result<_, _>>()?,
    };
    // "feed": the website's launcher feed. Absent: derived from the manifest URL. Empty or not an https:// URL: the
    // panels stay hidden (a wrong feed setting never stops the update or the game).
    let feed = match v.get("feed") {
        None => derive_feed(&manifest_url),
        Some(f) => f
            .as_str()
            .filter(|u| u.starts_with("https://") || loopback_http(u))
            .map(str::to_string),
    };
    // "unity_manifest": the Unity client's manifest. Absent: derived from the update URL. Empty or not https: the choice
    // is not offered (a wrong setting never stops the main client).
    let unity_manifest = match v.get("unity_manifest") {
        None => derive_unity(&manifest_url),
        Some(u) => u
            .as_str()
            .filter(|u| u.starts_with("https://") || loopback_http(u))
            .map(str::to_string),
    };
    let unity_game = match v.get("unity_game") {
        None => UNITY_GAME.to_string(),
        Some(g) => g
            .as_str()
            .filter(|g| is_plain_name(g) && g.to_ascii_lowercase().ends_with(".exe"))
            .ok_or_else(|| bad("unity_game must be a plain .exe file name"))?
            .to_string(),
    };
    Ok(Config {
        manifest_url,
        public_key,
        baseline,
        game,
        args,
        feed,
        dir: dir.to_path_buf(),
        unity_manifest,
        unity_game,
        layout: Layout::Flat,
    })
}

/// Which client the launcher updates and starts. The main client is the default; the Unity client is a beta.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Client {
    #[default]
    Main,
    Unity,
}

impl Client {
    pub fn tag(self) -> &'static str {
        match self {
            Client::Main => "main",
            Client::Unity => "unity",
        }
    }

    pub fn from_tag(t: &str) -> Option<Client> {
        match t.trim().to_ascii_lowercase().as_str() {
            "main" => Some(Client::Main),
            "unity" => Some(Client::Unity),
            _ => None,
        }
    }
}

impl Config {
    /// The config of one client: the main one as it is; the Unity one with its own manifest, its own folder
    /// (`unity/` inside the install folder, so its files and its `.cinders_launcher` state never mix with the main
    /// client's), the tree layout and no baseline. `None` for Unity when the manifest address is not set.
    pub fn for_client(&self, client: Client) -> Option<Config> {
        match client {
            Client::Main => Some(self.clone()),
            Client::Unity => {
                let url = self.unity_manifest.clone()?;
                Some(Config {
                    manifest_url: url,
                    baseline: 0,
                    game: self.unity_game.clone(),
                    args: Vec::new(),
                    dir: self.dir.join(UNITY_DIR),
                    unity_manifest: None,
                    layout: Layout::Tree,
                    ..self.clone()
                })
            }
        }
    }
}

pub const SETTINGS: &str = "settings.json";

/// What the player chose in the window (O552), saved in `.cinders_launcher/settings.json`:
/// `{"client": "unity", "lang": "en", "close_on_play": false}`. Every key is optional; missing, unreadable or odd
/// means the default (main client, the system language, close the launcher when the game starts).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Settings {
    pub client: Client,
    pub lang: Option<crate::i18n::Lang>,
    pub close_on_play: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Settings {
            client: Client::Main,
            lang: None,
            close_on_play: true,
        }
    }
}

fn settings_path(dir: &Path) -> PathBuf {
    dir.join(crate::install::STATE_DIR).join(SETTINGS)
}

pub fn load_settings(dir: &Path) -> Settings {
    let v = std::fs::read_to_string(settings_path(dir))
        .ok()
        .and_then(|t| serde_json::from_str::<Value>(&t).ok());
    let Some(v) = v else {
        return Settings::default();
    };
    Settings {
        client: v
            .get("client")
            .and_then(Value::as_str)
            .and_then(Client::from_tag)
            .unwrap_or_default(),
        lang: v.get("lang").and_then(Value::as_str).map(crate::i18n::Lang::from_tag),
        close_on_play: v.get("close_on_play").and_then(Value::as_bool).unwrap_or(true),
    }
}

pub fn save_settings(dir: &Path, s: &Settings) -> Result<(), Error> {
    let state = dir.join(crate::install::STATE_DIR);
    let io = |e: std::io::Error| Error::Io(format!("{SETTINGS}: {e}"));
    std::fs::create_dir_all(&state).map_err(io)?;
    let mut v = serde_json::json!({"client": s.client.tag(), "close_on_play": s.close_on_play});
    if let Some(l) = s.lang {
        v["lang"] = Value::from(l.tag());
    }
    let path = settings_path(dir);
    let tmp = path.with_extension("tmp");
    std::fs::write(&tmp, v.to_string()).map_err(io)?;
    let _ = std::fs::remove_file(&path);
    std::fs::rename(&tmp, &path).map_err(io)
}

pub fn load_client(dir: &Path) -> Client {
    load_settings(dir).client
}

pub fn save_client(dir: &Path, client: Client) -> Result<(), Error> {
    let mut s = load_settings(dir);
    s.client = client;
    save_settings(dir, &s)
}

pub fn load(dir: &Path) -> Result<Config, Error> {
    let text = std::fs::read_to_string(dir.join(FILE)).map_err(|e| Error::Config(format!("{FILE}: {e}")))?;
    parse(&text, dir)
}

#[cfg(test)]
mod tests {
    use super::*;

    const KEY: &str = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a";

    fn ok(extra: &str) -> String {
        format!(r#"{{"manifest":"https://x.test/updates/live/manifest.json","public_key":"{KEY}"{extra}}}"#)
    }

    #[test]
    fn parses_and_defaults() {
        let c = parse(&ok(""), Path::new("/g")).unwrap();
        assert_eq!((c.baseline, c.game.as_str(), c.args.len()), (0, "Chaos.exe", 0));
        assert_eq!(c.public_key[0], 0xd7);
        let c = parse(
            &ok(r#","baseline":47,"game":"Game.exe","args":["-x"]"#),
            Path::new("/g"),
        )
        .unwrap();
        assert_eq!(
            (c.baseline, c.game.as_str(), c.args),
            (47, "Game.exe", vec!["-x".to_string()])
        );
    }

    #[test]
    fn refuses_bad_settings() {
        let d = Path::new("/g");
        assert!(parse("nope", d).is_err());
        assert!(parse(&ok("").replace("https://x.test", "http://x.test"), d).is_err());
        assert!(parse(&ok("").replace("https://x.test", "http://127.0.0.1:80"), d).is_ok());
        assert!(parse(&ok("").replace(KEY, "abcd"), d).is_err());
        assert!(parse(&ok("").replace(KEY, &"zz".repeat(32)), d).is_err());
        assert!(parse(&ok(r#","baseline":-1"#), d).is_err());
        assert!(parse(&ok(r#","game":"..\\x.exe""#), d).is_err());
        assert!(parse(&ok(r#","game":"sub/x.exe""#), d).is_err());
        assert!(parse(&ok(r#","args":[1]"#), d).is_err());
    }

    #[test]
    fn feed_setting() {
        let d = Path::new("/g");
        // absent: derived from the update URL
        let c = parse(&ok(""), d).unwrap();
        assert_eq!(c.feed.as_deref(), Some("https://x.test/chaos_launcher_feed.php"));
        // given
        let c = parse(&ok(r#","feed":"https://y.test/f.php""#), d).unwrap();
        assert_eq!(c.feed.as_deref(), Some("https://y.test/f.php"));
        // empty, wrong type or a plain http URL: no panels, no error
        let bad = [
            r##","feed":"""##,
            r##","feed":5"##,
            r##","feed":"http://y.test/f.php""##,
            r##","feed":null"##,
        ];
        for b in bad {
            assert_eq!(parse(&ok(b), d).unwrap().feed, None, "{b}");
        }
        assert!(parse(&ok(r#","feed":"http://127.0.0.1:81/f""#), d)
            .unwrap()
            .feed
            .is_some());
        // an update URL that is not under /updates/ gives no derived feed
        let t = ok("").replace("/updates/live/manifest.json", "/m/manifest.json");
        assert_eq!(parse(&t, d).unwrap().feed, None);
        assert_eq!(
            derive_feed("http://127.0.0.1:99/updates/live/manifest.json").as_deref(),
            Some("http://127.0.0.1:99/chaos_launcher_feed.php")
        );
    }

    #[test]
    fn unity_manifest_setting() {
        let d = Path::new("/g");
        // absent: derived from the update URL, same site
        let c = parse(&ok(""), d).unwrap();
        assert_eq!(
            c.unity_manifest.as_deref(),
            Some("https://x.test/updates/unity/manifest.json")
        );
        assert_eq!(c.unity_game, "ChaosUnity.exe");
        assert_eq!(c.layout, Layout::Flat);
        // given
        let c = parse(
            &ok(r#","unity_manifest":"https://y.test/u/manifest.json","unity_game":"Play.exe""#),
            d,
        )
        .unwrap();
        assert_eq!(c.unity_manifest.as_deref(), Some("https://y.test/u/manifest.json"));
        assert_eq!(c.unity_game, "Play.exe");
        // empty, wrong type, plain http: the choice is not offered, no error
        for b in [
            r##","unity_manifest":"""##,
            r##","unity_manifest":5"##,
            r##","unity_manifest":"http://y.test/m.json""##,
            r##","unity_manifest":null"##,
        ] {
            assert_eq!(parse(&ok(b), d).unwrap().unity_manifest, None, "{b}");
        }
        // an update URL that is not under /updates/<channel>/manifest.json derives nothing
        let t = ok("").replace("/updates/live/manifest.json", "/m/manifest.json");
        assert_eq!(parse(&t, d).unwrap().unity_manifest, None);
        let t = ok("").replace("/updates/live/manifest.json", "/updates/live/other.json");
        assert_eq!(parse(&t, d).unwrap().unity_manifest, None);
        assert_eq!(
            derive_unity("http://127.0.0.1:99/updates/live/manifest.json?t=5").as_deref(),
            Some("http://127.0.0.1:99/updates/unity/manifest.json?t=5")
        );
        // a bad unity game name is a config error (the file name is started)
        assert!(parse(&ok(r#","unity_game":"..\\x.exe""#), d).is_err());
        assert!(parse(&ok(r#","unity_game":"run.bat""#), d).is_err());
    }

    #[test]
    fn config_of_each_client() {
        let c = parse(&ok(r#","baseline":47,"args":["-x"]"#), Path::new("/g")).unwrap();
        let main = c.for_client(Client::Main).unwrap();
        assert_eq!(main, c);
        let u = c.for_client(Client::Unity).unwrap();
        assert_eq!(u.manifest_url, "https://x.test/updates/unity/manifest.json");
        assert_eq!((u.baseline, u.layout), (0, Layout::Tree));
        assert_eq!((u.game.as_str(), u.args.len()), ("ChaosUnity.exe", 0));
        assert_eq!(u.dir, Path::new("/g").join("unity"));
        assert_eq!(u.public_key, c.public_key);
        // no Unity address: no Unity config
        let none = parse(&ok(r##","unity_manifest":"""##), Path::new("/g")).unwrap();
        assert!(none.for_client(Client::Unity).is_none());
    }

    #[test]
    fn client_choice_is_saved() {
        let dir = std::env::temp_dir().join(format!("cinders-launcher-choice-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(load_client(&dir), Client::Main, "nothing saved: the main client");
        save_client(&dir, Client::Unity).unwrap();
        assert_eq!(load_client(&dir), Client::Unity);
        save_client(&dir, Client::Main).unwrap();
        assert_eq!(load_client(&dir), Client::Main);
        let f = dir.join(crate::install::STATE_DIR).join(SETTINGS);
        for junk in ["", "nope", r#"{"client":"other"}"#, r#"{"client":5}"#, "[]"] {
            std::fs::write(&f, junk).unwrap();
            assert_eq!(load_client(&dir), Client::Main, "{junk:?}");
        }
        assert_eq!(Client::from_tag(" Unity "), Some(Client::Unity));
        assert_eq!(Client::from_tag("x"), None);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn links_derive_from_the_site_and_can_be_set_or_hidden() {
        let m = "https://site.test/updates/live/manifest.json";
        let l = parse_links("{}", m);
        assert_eq!(l.site.as_deref(), Some("https://site.test/"));
        assert_eq!(l.wiki.as_deref(), Some("https://site.test/wiki"));
        assert_eq!(l.signup.as_deref(), Some("https://site.test/register"));
        assert_eq!(l.discord, None);
        let l = parse_links(
            r#"{"links":{"discord":"https://discord.test/x","wiki":"","signup":"http://x.test/","site":"https://a b"}}"#,
            m,
        );
        assert_eq!(l.discord.as_deref(), Some("https://discord.test/x"));
        assert_eq!((l.wiki, l.signup, l.site), (None, None, None));
        // junk anywhere gives the defaults, never a panic
        assert_eq!(parse_links("not json", m).site.as_deref(), Some("https://site.test/"));
        assert_eq!(
            parse_links(r#"{"links":5}"#, m).wiki.as_deref(),
            Some("https://site.test/wiki")
        );
        // a manifest on a loopback http address (tests) derives nothing
        assert_eq!(parse_links("{}", "http://127.0.0.1:1/m.json").site, None);
    }

    #[test]
    fn settings_round_trip_and_defaults() {
        use crate::i18n::Lang;
        let dir = std::env::temp_dir().join(format!("cinders-launcher-settings-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        assert_eq!(load_settings(&dir), Settings::default());
        let s = Settings {
            client: Client::Unity,
            lang: Some(Lang::En),
            close_on_play: false,
        };
        save_settings(&dir, &s).unwrap();
        assert_eq!(load_settings(&dir), s);
        // saving the client keeps the other keys
        save_client(&dir, Client::Main).unwrap();
        assert_eq!(
            load_settings(&dir),
            Settings {
                client: Client::Main,
                ..s
            }
        );
        // an old file with only the client still loads
        let f = dir.join(crate::install::STATE_DIR).join(SETTINGS);
        std::fs::write(&f, r#"{"client":"unity"}"#).unwrap();
        assert_eq!(
            load_settings(&dir),
            Settings {
                client: Client::Unity,
                lang: None,
                close_on_play: true
            }
        );
        std::fs::write(&f, r#"{"close_on_play":"no","lang":7}"#).unwrap();
        assert_eq!(load_settings(&dir), Settings::default());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn plain_names() {
        assert!(is_plain_name("libGLESv2.dll"));
        assert!(!is_plain_name(""));
        assert!(!is_plain_name(".hidden"));
        assert!(!is_plain_name("a b.dll"));
        assert!(!is_plain_name("a/b"));
        assert!(!is_plain_name("c:x"));
    }
}
