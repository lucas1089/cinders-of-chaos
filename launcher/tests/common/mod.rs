//! A fake update server on 127.0.0.1 (manifest, plain native blobs, `Range`, dropped connections, corrupt blobs) and a
//! fake install folder, shared by the integration tests.
#![allow(dead_code)]
use cinders_launcher::config::Config;
use cinders_launcher::install::{Options, Updater};
use cinders_launcher::net::Curl;
use cinders_selfupdate::hash::sha256_hex;
use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

#[derive(Default)]
pub struct ServerState {
    pub routes: HashMap<String, Vec<u8>>,
    /// path -> bytes to send before the connection is cut (used once)
    pub cut_once: HashMap<String, usize>,
    /// path -> bytes served instead of the real ones (used once, same length)
    pub corrupt_once: HashMap<String, Vec<u8>>,
    /// every request: path and the start of its Range, if any
    pub hits: Vec<(String, Option<u64>)>,
    pub offline: bool,
}

pub struct Server {
    pub base: String,
    pub state: Arc<Mutex<ServerState>>,
}

fn serve(mut s: TcpStream, st: Arc<Mutex<ServerState>>) {
    let mut buf = Vec::new();
    let mut tmp = [0u8; 1024];
    while !buf.windows(4).any(|w| w == b"\r\n\r\n") {
        match s.read(&mut tmp) {
            Ok(0) | Err(_) => return,
            Ok(n) => buf.extend_from_slice(&tmp[..n]),
        }
    }
    let head = String::from_utf8_lossy(&buf).to_string();
    let path = head
        .lines()
        .next()
        .and_then(|l| l.split_whitespace().nth(1))
        .unwrap_or("/")
        .split('?')
        .next()
        .unwrap_or("/")
        .to_string();
    let range = head.lines().find_map(|l| {
        let l = l.to_ascii_lowercase();
        l.strip_prefix("range: bytes=")
            .and_then(|r| r.trim_end_matches('-').parse::<u64>().ok())
    });
    let (body, cut) = {
        let mut g = st.lock().unwrap();
        g.hits.push((path.clone(), range));
        if g.offline {
            return; // closes the connection
        }
        let body = match g.corrupt_once.remove(&path) {
            Some(b) => Some(b),
            None => g.routes.get(&path).cloned(),
        };
        (body, g.cut_once.remove(&path))
    };
    let Some(body) = body else {
        let _ = s.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        return;
    };
    let start = range.unwrap_or(0).min(body.len() as u64) as usize;
    let part = &body[start..];
    let head = if range.is_some() {
        format!(
            "HTTP/1.1 206 Partial Content\r\nContent-Length: {}\r\nContent-Range: bytes {}-{}/{}\r\nConnection: close\r\n\r\n",
            part.len(),
            start,
            body.len().saturating_sub(1),
            body.len()
        )
    } else {
        format!(
            "HTTP/1.1 200 OK\r\nContent-Length: {}\r\nConnection: close\r\n\r\n",
            part.len()
        )
    };
    let _ = s.write_all(head.as_bytes());
    let send = cut.map(|c| c.min(part.len())).unwrap_or(part.len());
    let _ = s.write_all(&part[..send]);
    let _ = s.flush();
}

impl Server {
    pub fn start() -> Server {
        let l = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://127.0.0.1:{}", l.local_addr().unwrap().port());
        let state = Arc::new(Mutex::new(ServerState::default()));
        let st = state.clone();
        std::thread::spawn(move || {
            for c in l.incoming().flatten() {
                let st = st.clone();
                std::thread::spawn(move || serve(c, st));
            }
        });
        Server { base, state }
    }

    pub fn manifest_url(&self) -> String {
        format!("{}/updates/live/manifest.json", self.base)
    }

    pub fn set(&self, path: &str, body: Vec<u8>) {
        self.state.lock().unwrap().routes.insert(path.to_string(), body);
    }

    pub fn hits_for(&self, needle: &str) -> Vec<(String, Option<u64>)> {
        self.state
            .lock()
            .unwrap()
            .hits
            .iter()
            .filter(|(p, _)| p.contains(needle))
            .cloned()
            .collect()
    }

    pub fn blob_hits(&self) -> usize {
        self.hits_for("/native/").len()
    }

    pub fn clear_hits(&self) {
        self.state.lock().unwrap().hits.clear();
    }
}

pub fn blob_path(sha: &str) -> String {
    format!("/updates/live/native/{}/{sha}", &sha[..2])
}

pub fn keypair(seed: u8) -> ed25519_compact::KeyPair {
    ed25519_compact::KeyPair::from_seed(ed25519_compact::Seed::new([seed; 32]))
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

/// One published release: the files of the `native` section.
#[derive(Clone)]
pub struct Release {
    pub version: u64,
    pub package: u64,
    pub files: Vec<(String, Vec<u8>)>,
    pub launcher: Option<String>,
}

impl Release {
    pub fn payload(&self) -> String {
        let files: Vec<_> = self
            .files
            .iter()
            .map(|(n, d)| serde_json::json!({"path": n, "sha256": sha256_hex(d), "size": d.len()}))
            .collect();
        let mut native = serde_json::json!({
            "package": self.package, "game": "Chaos.exe", "files_url": "native/", "files": files
        });
        if let Some(l) = &self.launcher {
            native["launcher"] = serde_json::json!(l);
        }
        // the part the in-game Lua updater reads, to prove both live in one manifest
        serde_json::json!({
            "format": 1, "product": "cinders-of-chaos", "version": self.version, "min_version": 0,
            "min_package": 13, "encryption": "chaos-blob-1", "files_url": "files/", "files": [],
            "native": native
        })
        .to_string()
    }

    pub fn envelope(&self, kp: &ed25519_compact::KeyPair) -> String {
        let payload = self.payload();
        let sig = kp.sk.sign(payload.as_bytes(), None);
        serde_json::json!({
            "format": "chaos-update-1", "key": hex(&kp.pk[..]), "signature": hex(&sig[..]), "payload": payload
        })
        .to_string()
    }

    pub fn publish(&self, srv: &Server, kp: &ed25519_compact::KeyPair) {
        for (_, d) in &self.files {
            srv.set(&blob_path(&sha256_hex(d)), d.clone());
        }
        srv.set("/updates/live/manifest.json", self.envelope(kp).into_bytes());
    }
}

pub struct World {
    pub srv: Server,
    pub kp: ed25519_compact::KeyPair,
    pub dir: PathBuf,
    pub cfg: Config,
    pub exe: PathBuf,
}

impl World {
    pub fn new(name: &str) -> World {
        let dir = std::env::temp_dir().join(format!("cinders-launcher-it-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let srv = Server::start();
        let kp = keypair(7);
        let cfg = Config {
            manifest_url: srv.manifest_url(),
            public_key: *kp.pk,
            baseline: 0,
            game: "Chaos.exe".into(),
            args: vec![],
            feed: Some(format!("{}/{}", srv.base, cinders_launcher::config::FEED_NAME)),
            dir: dir.clone(),
        };
        let exe = dir.join("CindersLauncher.exe");
        std::fs::write(&exe, b"launcher v0").unwrap();
        World { srv, kp, dir, cfg, exe }
    }

    pub fn updater(&self, opts: Options) -> Updater<'_> {
        Updater {
            cfg: &self.cfg,
            fetch: &Curl,
            exe: self.exe.clone(),
            opts,
        }
    }

    pub fn fast() -> Options {
        Options {
            retries: 3,
            backoff_ms: 1,
            ..Options::default()
        }
    }

    pub fn applied_version(&self) -> u64 {
        self.updater(Options::default()).applied_version()
    }

    pub fn read(&self, name: &str) -> Option<Vec<u8>> {
        std::fs::read(self.dir.join(name)).ok()
    }

    /// The install holds exactly the release's files (other files are not looked at).
    pub fn assert_is(&self, r: &Release) {
        for (n, d) in &r.files {
            if r.launcher.as_deref() == Some(n) {
                continue;
            }
            assert_eq!(self.read(n).as_deref(), Some(&d[..]), "{n} of release {}", r.version);
        }
    }

    /// No stage, backup, journal or part file left in the state folder after a finished run.
    pub fn assert_clean(&self) {
        let st = self.dir.join(cinders_launcher::install::STATE_DIR);
        assert!(!st.join("journal.json").exists(), "journal left");
        assert!(!st.join("backup").exists(), "backup left");
        assert!(!st.join("stage").exists(), "stage left");
    }
}

impl Drop for World {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

pub fn path_in(dir: &Path, n: &str) -> PathBuf {
    dir.join(n)
}

/// Small deterministic random numbers (xorshift64*), so a failing run repeats.
pub struct Rng(pub u64);

impl Rng {
    pub fn next(&mut self) -> u64 {
        self.0 ^= self.0 >> 12;
        self.0 ^= self.0 << 25;
        self.0 ^= self.0 >> 27;
        self.0.wrapping_mul(0x2545_F491_4F6C_DD1D)
    }
    pub fn below(&mut self, n: u64) -> u64 {
        self.next() % n
    }
    pub fn bytes(&mut self, len: usize) -> Vec<u8> {
        (0..len).map(|_| (self.next() >> 24) as u8).collect()
    }
}
