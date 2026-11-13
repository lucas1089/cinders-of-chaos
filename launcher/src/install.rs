//! The update itself: fetch and verify the manifest, compare the install with its `native` section, download what
//! changed into a staging folder, check every hash, swap the files in one transaction with a journal and a rollback.
//!
//! Folder `.cinders_launcher/` in the install folder:
//!   stage/<sha256>        a downloaded, verified file; `<sha256>.part` is a download in progress (resumed)
//!   backup/<name>         the files a swap replaced, until the swap is done
//!   journal.json          present only while a swap runs; a start that finds it puts the old files back first
//!   state.json            {"version", "package"} of the last manifest applied (no replay of an older one)
//!   hashcache.txt         name, size, mtime and SHA-256 of installed files (a 900 MB pack is not read every start)
//!   owned.json            {"files": [names]} the native files of the last manifest applied; a name that the next
//!                         manifest no longer lists is an old file of this launcher and is removed (see `remove_stale`)
//!
//! The Unity client (ROADMAP O433 phase 16) goes through the same code with `cfg.layout == Layout::Tree`: its `cfg.dir`
//! is the `unity/` folder inside the install folder, its names are relative paths with sub-folders, and a folder
//! is made before a file is put in it. Its state folder is its own, so nothing is shared with the main client.
use crate::config::Config;
use crate::i18n::{Error, Status};
use crate::manifest::{self, blob_url, Layout, Manifest, NativeFile};
use crate::net::{Fetch, FetchError};
use crate::selfupdate;
use cinders_selfupdate::hash::{is_sha256_hex, sha256_file};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub const STATE_DIR: &str = ".cinders_launcher";

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Event {
    Status(Status),
    /// Bytes downloaded so far and in total for this run.
    Progress {
        done: u64,
        total: u64,
    },
    /// The file being downloaded.
    File(String),
    /// Files finished and files to do in this run (O552: "1/12 files").
    Files {
        done: usize,
        total: usize,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Outcome {
    pub version: u64,
    pub package: Option<u64>,
    /// Files put in place by this run.
    pub replaced: Vec<String>,
    pub downloaded: u64,
    /// Files of an older release that the new manifest no longer lists, deleted from the install folder.
    pub removed: Vec<String>,
    /// A new launcher is staged and takes over at the next start.
    pub launcher_staged: bool,
    /// The program to start (`native.game` of the manifest, or the configured one).
    pub game: String,
}

/// Test hook: makes the swap fail on purpose, to prove the rollback. Always `None` in the program.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Fault {
    #[default]
    None,
    /// Fail before the (n+1)th file is put in place.
    FailApplyAfter(usize),
}

#[derive(Debug, Clone)]
pub struct Options {
    /// Extra tries per file after the first.
    pub retries: u32,
    /// First wait before a retry in milliseconds; doubles each time.
    pub backoff_ms: u64,
    pub fault: Fault,
    /// Only the launcher's own file: nothing else is downloaded or installed and no state is saved. The Unity choice
    /// runs the main manifest this way after its own update, so a player who only uses the Unity client still gets a
    /// new launcher.
    pub launcher_only: bool,
    /// Install a DEV Unity package (one built without the client guard key, manifest `"dev": true`). Off for players: such a
    /// build cannot log in to a live server or open the sprite pair. The launcher's `--allow-dev-unity` turns it on (testers).
    pub allow_dev: bool,
    /// "Verify files" (O552): the hash cache is ignored and every installed file is hashed again; a damaged file is
    /// repaired piece by piece when the manifest has chunk hashes.
    pub verify: bool,
    /// Pieces fetched at the same time for a chunked file.
    pub parallel: usize,
    /// Test hook: pretends this many bytes are free in the install folder. `None` in the program (the real figure).
    pub free_space: Option<u64>,
}

impl Default for Options {
    fn default() -> Self {
        Options {
            retries: 5,
            backoff_ms: 500,
            fault: Fault::None,
            launcher_only: false,
            allow_dev: false,
            verify: false,
            parallel: 4,
            free_space: None,
        }
    }
}

/// What a failed fetch of the manifest means (O494). A server answer of 400 or more is `Error::Http`, not a network
/// failure; for the Unity client (`unity`: the tree layout) a 404 or 410 means the channel was never published. Only
/// a transport failure (no answer at all) is `Error::Network`.
pub fn manifest_fetch_error(e: FetchError, unity: bool) -> Error {
    match e.http {
        Some(404 | 410) if unity => Error::UnityNotPublished,
        Some(status) => Error::Http(status),
        None => Error::Network(e.detail),
    }
}

/// Fetches the signed manifest of a config and checks the signature and the rules of its layout. Nothing is trusted
/// before the signature is good. The query string defeats caches.
pub fn fetch_manifest(fetch: &dyn Fetch, cfg: &Config) -> Result<Manifest, Error> {
    let stamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let sep = if cfg.manifest_url.contains('?') { '&' } else { '?' };
    let url = format!("{}{sep}t={stamp}", cfg.manifest_url);
    let body = fetch
        .get(&url)
        .map_err(|e| manifest_fetch_error(e, cfg.layout == Layout::Tree))?;
    manifest::parse_envelope_for(&body, &cfg.public_key, cfg.layout)
}

pub struct Updater<'a> {
    pub cfg: &'a Config,
    pub fetch: &'a dyn Fetch,
    /// The running launcher (compared with `native.launcher`, replaced by a staged rename).
    pub exe: PathBuf,
    pub opts: Options,
}

// ---------------------------------------------------------------- small file helpers

pub(crate) fn io<T>(r: std::io::Result<T>, what: &str) -> Result<T, Error> {
    r.map_err(|e| Error::Io(format!("{what}: {e}")))
}

fn write_atomic(path: &Path, text: &str) -> Result<(), Error> {
    let tmp = path.with_extension("tmp");
    io(std::fs::write(&tmp, text), "write")?;
    let _ = std::fs::remove_file(path);
    io(std::fs::rename(&tmp, path), "rename")
}

pub(crate) fn mtime_key(path: &Path) -> Option<(u64, u128)> {
    let m = std::fs::metadata(path).ok()?;
    let t = m.modified().ok()?.duration_since(UNIX_EPOCH).ok()?;
    Some((m.len(), t.as_nanos()))
}

pub(crate) fn move_over(from: &Path, to: &Path) -> std::io::Result<()> {
    if to.exists() {
        std::fs::remove_file(to)?;
    }
    std::fs::rename(from, to)
}

/// Free bytes kept on top of the download for the swap, the journal and the player's own files.
pub const SPACE_MARGIN: u64 = 256 * 1024 * 1024;

/// `.exe` last: the other files are in place before the program that loads them.
fn apply_order(name: &str) -> bool {
    name.to_ascii_lowercase().ends_with(".exe")
}

impl<'a> Updater<'a> {
    fn state_dir(&self) -> PathBuf {
        self.cfg.dir.join(STATE_DIR)
    }
    pub(crate) fn stage_dir(&self) -> PathBuf {
        self.state_dir().join("stage")
    }
    fn backup_dir(&self) -> PathBuf {
        self.state_dir().join("backup")
    }
    fn journal(&self) -> PathBuf {
        self.state_dir().join("journal.json")
    }

    // ------------------------------------------------------------ state and hash cache

    pub fn applied_version(&self) -> u64 {
        std::fs::read_to_string(self.state_dir().join("state.json"))
            .ok()
            .and_then(|t| serde_json::from_str::<Value>(&t).ok())
            .and_then(|v| v.get("version").and_then(Value::as_u64))
            .unwrap_or(0)
    }

    fn save_state(&self, m: &Manifest) -> Result<(), Error> {
        let v = json!({"version": m.version, "package": m.native.as_ref().map(|n| n.package)});
        write_atomic(&self.state_dir().join("state.json"), &v.to_string())
    }

    fn owned_path(&self) -> PathBuf {
        self.state_dir().join("owned.json")
    }

    /// The native files an earlier run put in the install folder (empty before the first run of this version).
    fn load_owned(&self) -> Vec<String> {
        std::fs::read_to_string(self.owned_path())
            .ok()
            .and_then(|t| serde_json::from_str::<Value>(&t).ok())
            .and_then(|v| v.get("files").and_then(Value::as_array).cloned())
            .unwrap_or_default()
            .iter()
            .filter_map(|n| n.as_str().map(str::to_string))
            .collect()
    }

    /// Old files of this launcher's own releases: removes every name the last run installed that the manifest now
    /// leaves out (a renamed DLL, a pack of an older name), so no old file stays beside the new ones and gets loaded
    /// first. Safe by construction: only names that pass `check_native_name` (a plain file name with an .exe, .dll or
    /// .pack ending), only names an earlier manifest listed, never the game, the launcher or the running program,
    /// only a regular file directly in the install folder (a link, a folder or a missing file is left alone). A file
    /// that cannot be removed now (still in use) stays on the list and is tried again at the next run.
    fn remove_stale(&self, native: &manifest::Native) -> Vec<String> {
        let current = |n: &str| native.files.iter().any(|f| f.path.eq_ignore_ascii_case(n));
        let me = self
            .exe
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_default();
        let mut keep: Vec<String> = native.files.iter().map(|f| f.path.clone()).collect();
        let mut removed = Vec::new();
        for name in self.load_owned() {
            if current(&name) || self.cfg.layout.check_path(&name).is_some() {
                continue;
            }
            if name.eq_ignore_ascii_case(&native.game)
                || name.eq_ignore_ascii_case(&me)
                || native
                    .launcher
                    .as_deref()
                    .is_some_and(|l| l.eq_ignore_ascii_case(&name))
            {
                continue;
            }
            let path = self.cfg.dir.join(&name);
            match std::fs::symlink_metadata(&path) {
                Ok(m) if m.is_file() => {
                    if std::fs::remove_file(&path).is_ok() {
                        if self.cfg.layout == Layout::Tree {
                            self.remove_empty_parents(&path);
                        }
                        removed.push(name);
                    } else {
                        keep.push(name);
                    }
                }
                _ => {}
            }
        }
        let v = json!({"files": keep});
        let _ = write_atomic(&self.owned_path(), &v.to_string());
        removed
    }

    /// Takes away the folders a removed file leaves empty, up to (not including) the install folder. `remove_dir` only
    /// removes an empty folder, so a folder with anything in it (a `things/` the player added) stays.
    fn remove_empty_parents(&self, file: &Path) {
        let mut at = file.parent();
        while let Some(d) = at {
            if d == self.cfg.dir || !d.starts_with(&self.cfg.dir) || std::fs::remove_dir(d).is_err() {
                break;
            }
            at = d.parent();
        }
    }

    fn load_cache(&self) -> HashMap<String, (u64, u128, String)> {
        let mut out = HashMap::new();
        let text = std::fs::read_to_string(self.state_dir().join("hashcache.txt")).unwrap_or_default();
        for line in text.lines() {
            let p: Vec<&str> = line.split('\t').collect();
            if let [name, size, ns, sha] = p[..] {
                if let (Ok(s), Ok(n)) = (size.parse(), ns.parse()) {
                    if is_sha256_hex(sha) {
                        out.insert(name.to_string(), (s, n, sha.to_string()));
                    }
                }
            }
        }
        out
    }

    fn save_cache(&self, cache: &HashMap<String, (u64, u128, String)>) {
        let mut names: Vec<_> = cache.keys().collect();
        names.sort();
        let text: String = names
            .iter()
            .map(|n| {
                let (s, t, h) = &cache[*n];
                format!("{n}\t{s}\t{t}\t{h}\n")
            })
            .collect();
        let _ = write_atomic(&self.state_dir().join("hashcache.txt"), &text);
    }

    /// SHA-256 of an installed file; None when it is not there. Uses the cache while size and mtime are the same.
    fn local_hash(
        &self,
        name: &str,
        path: &Path,
        cache: &mut HashMap<String, (u64, u128, String)>,
    ) -> Result<Option<String>, Error> {
        let Some((size, ns)) = mtime_key(path) else {
            return Ok(None);
        };
        if let Some((s, n, h)) = cache.get(name) {
            if *s == size && *n == ns {
                return Ok(Some(h.clone()));
            }
        }
        let h = io(sha256_file(path), name)?;
        cache.insert(name.to_string(), (size, ns, h.clone()));
        Ok(Some(h))
    }

    // ------------------------------------------------------------ recovery

    /// Puts the old files back when a swap was cut short (a crash, a power cut), then clears the leftovers.
    pub fn recover(&self) -> Result<(), Error> {
        let j = self.journal();
        if let Ok(text) = std::fs::read_to_string(&j) {
            let v: Value = serde_json::from_str(&text).unwrap_or(Value::Null);
            let entries = parse_journal(&v, self.cfg.layout);
            self.rollback(&entries).map_err(Error::Rollback)?;
            let _ = std::fs::remove_file(&j);
        }
        let _ = std::fs::remove_dir_all(self.backup_dir());
        Ok(())
    }

    fn rollback(&self, entries: &[JournalEntry]) -> Result<(), String> {
        let mut failed = Vec::new();
        for e in entries.iter().rev() {
            let dest = self.cfg.dir.join(&e.path);
            let backup = self.backup_dir().join(&e.path);
            let saved = self.stage_dir().join(&e.sha);
            let r = (|| -> std::io::Result<()> {
                if e.had_old && !backup.exists() {
                    return Ok(()); // the old file was never moved: dest is still the old one
                }
                if dest.exists() {
                    // the new file: keep it staged so the next run does not download it again
                    if is_sha256_hex(&e.sha) && std::fs::create_dir_all(self.stage_dir()).is_ok() {
                        if move_over(&dest, &saved).is_err() {
                            std::fs::remove_file(&dest)?;
                        }
                    } else {
                        std::fs::remove_file(&dest)?;
                    }
                }
                if e.had_old {
                    std::fs::rename(&backup, &dest)?;
                }
                Ok(())
            })();
            if let Err(err) = r {
                failed.push(format!("{}: {err}", e.path));
            }
        }
        if failed.is_empty() {
            Ok(())
        } else {
            Err(failed.join("; "))
        }
    }

    // ------------------------------------------------------------ disk space

    /// Bytes of this file already in the stage folder (a finished file, or the pieces and the part of an earlier run).
    fn staged_bytes(&self, f: &NativeFile) -> u64 {
        let stage = self.stage_dir();
        if let Some((n, _)) = mtime_key(&stage.join(&f.sha256)) {
            return n;
        }
        let mut sum = mtime_key(&stage.join(format!("{}.part", f.sha256))).map_or(0, |k| k.0);
        if let Ok(rd) = std::fs::read_dir(stage.join(format!("{}.chunks", f.sha256))) {
            sum += rd
                .flatten()
                .filter_map(|e| e.metadata().ok())
                .map(|m| m.len())
                .sum::<u64>();
        }
        sum.min(f.size)
    }

    /// Refuses before the first byte when the folder cannot hold the download: what is still to fetch, plus the margin.
    fn check_space(&self, jobs: &[&NativeFile], total: u64) -> Result<(), Error> {
        let staged: u64 = jobs.iter().map(|f| self.staged_bytes(f)).sum();
        let need = total.saturating_sub(staged) + if total > 0 { SPACE_MARGIN } else { 0 };
        if need == 0 {
            return Ok(());
        }
        let free = match self.opts.free_space {
            Some(f) => Some(f),
            None => fs2::available_space(&self.cfg.dir).ok(),
        };
        match free {
            Some(free) if free < need => Err(Error::NoSpace { need, free }),
            _ => Ok(()), // an unknown figure never blocks an update
        }
    }

    // ------------------------------------------------------------ the run

    /// Checks for an update and installs it. Nothing in the install changes before every file is downloaded and
    /// verified; the swap is undone when it fails.
    pub fn run(&self, ev: &mut dyn FnMut(Event)) -> Result<Outcome, Error> {
        io(std::fs::create_dir_all(self.stage_dir()), "create the launcher folder")?;
        self.recover()?;

        ev(Event::Status(Status::Checking));
        let m = fetch_manifest(self.fetch, self.cfg)?;
        let have = self.cfg.baseline.max(self.applied_version());
        if m.version < have {
            return Err(Error::OlderManifest { got: m.version, have });
        }
        let Some(native) = m.native.clone() else {
            // a manifest of modules only: nothing for the launcher
            if !self.opts.launcher_only {
                self.save_state(&m)?;
            }
            return Ok(Outcome {
                version: m.version,
                game: self.cfg.game.clone(),
                ..Outcome::default()
            });
        };

        // a DEV Unity package is not offered to players (O433 phase 17): nothing is downloaded or changed
        if native.dev && self.cfg.layout == manifest::Layout::Tree && !self.opts.allow_dev {
            return Err(Error::DevPackage);
        }

        ev(Event::Status(if self.opts.verify {
            Status::Verifying
        } else {
            Status::Hashing
        }));
        let mut cache = if self.opts.verify {
            HashMap::new()
        } else {
            self.load_cache()
        };
        let mut todo: Vec<&NativeFile> = Vec::new();
        let mut launcher: Option<&NativeFile> = None;
        for f in &native.files {
            if native
                .launcher
                .as_deref()
                .is_some_and(|l| l.eq_ignore_ascii_case(&f.path))
            {
                let mine = io(sha256_file(&self.exe), "the launcher")?;
                if mine != f.sha256 && selfupdate::staged_sha(&self.exe).as_deref() != Some(&f.sha256) {
                    launcher = Some(f);
                }
                continue;
            }
            if self.opts.launcher_only {
                continue; // no hashing of the pack and the rest: only the launcher's own file matters now
            }
            let path = self.cfg.dir.join(&f.path);
            if self.local_hash(&f.path, &path, &mut cache)?.as_deref() != Some(&f.sha256) {
                todo.push(f);
            }
        }
        self.save_cache(&cache);

        let mut jobs: Vec<&NativeFile> = todo.clone();
        jobs.extend(launcher);
        let total: u64 = jobs.iter().map(|f| f.size).sum();
        self.check_space(&jobs, total)?;
        let mut done_before = 0u64;
        if !jobs.is_empty() {
            ev(Event::Status(Status::Downloading));
        }
        ev(Event::Progress { done: 0, total });
        ev(Event::Files {
            done: 0,
            total: jobs.len(),
        });
        for (n, f) in jobs.iter().enumerate() {
            ev(Event::File(f.path.clone()));
            self.fetch_file(f, &mut |n| {
                ev(Event::Progress {
                    done: done_before + n,
                    total,
                })
            })?;
            done_before += f.size;
            ev(Event::Progress {
                done: done_before,
                total,
            });
            ev(Event::Files {
                done: n + 1,
                total: jobs.len(),
            });
        }

        let mut replaced = Vec::new();
        if !todo.is_empty() {
            ev(Event::Status(Status::Applying));
            let mut items: Vec<&NativeFile> = todo.clone();
            items.sort_by_key(|f| (apply_order(&f.path), f.path.to_ascii_lowercase()));
            self.apply(&items)?;
            for f in &items {
                if let Some((size, ns)) = mtime_key(&self.cfg.dir.join(&f.path)) {
                    cache.insert(f.path.clone(), (size, ns, f.sha256.clone()));
                }
                replaced.push(f.path.clone());
            }
            self.save_cache(&cache);
        }
        let mut removed = Vec::new();
        if !self.opts.launcher_only {
            self.save_state(&m)?;
            removed = self.remove_stale(&native);
        }
        let mut staged = false;
        if let Some(f) = launcher {
            io(
                selfupdate::stage(&self.exe, &self.stage_dir().join(&f.sha256), &f.sha256)
                    .map_err(std::io::Error::other),
                "stage the launcher",
            )?;
            staged = true;
            ev(Event::Status(Status::LauncherStaged));
        }
        let _ = std::fs::remove_dir_all(self.stage_dir());
        ev(Event::Status(if replaced.is_empty() && !staged {
            Status::UpToDate
        } else {
            Status::Updated
        }));
        Ok(Outcome {
            version: m.version,
            package: Some(native.package),
            replaced,
            removed,
            downloaded: total,
            launcher_staged: staged,
            game: native.game,
        })
    }

    /// Downloads one file into `stage/<sha>`, resuming a `.part`, retrying with a growing wait. A file whose hash is
    /// wrong is deleted and fetched again; after the last try the error says which.
    fn fetch_file(&self, f: &NativeFile, progress: &mut dyn FnMut(u64)) -> Result<(), Error> {
        if f.chunks.is_some() && self.fetch.supports_ranges() {
            return self.fetch_chunked(f, progress);
        }
        let done = self.stage_dir().join(&f.sha256);
        if done.is_file() && mtime_key(&done).map(|k| k.0) == Some(f.size) {
            if sha256_file(&done).ok().as_deref() == Some(&f.sha256) {
                progress(f.size);
                return Ok(());
            }
            let _ = std::fs::remove_file(&done);
        }
        let part = self.stage_dir().join(format!("{}.part", f.sha256));
        let url = blob_url(&self.cfg.manifest_url, &f.sha256);
        let mut last = Error::Download {
            file: f.path.clone(),
            detail: "no try".into(),
        };
        for attempt in 0..=self.opts.retries {
            if attempt > 0 {
                let wait = self.opts.backoff_ms.saturating_mul(1 << (attempt - 1).min(6));
                std::thread::sleep(Duration::from_millis(wait));
            }
            let have = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
            if have > f.size {
                let _ = std::fs::remove_file(&part);
            }
            if have != f.size {
                if let Err(e) = self.fetch.download(&url, &part, progress) {
                    last = Error::Download {
                        file: f.path.clone(),
                        detail: e.detail,
                    };
                    continue;
                }
            }
            let got = std::fs::metadata(&part).map(|m| m.len()).unwrap_or(0);
            if got != f.size {
                // cut short without an error, or too long: keep a short part (resume), drop a long one
                if got > f.size {
                    let _ = std::fs::remove_file(&part);
                }
                last = Error::Download {
                    file: f.path.clone(),
                    detail: format!("{got} of {} bytes", f.size),
                };
                continue;
            }
            if io(sha256_file(&part), &f.path)? == f.sha256 {
                io(move_over(&part, &done), "stage")?;
                return Ok(());
            }
            let _ = std::fs::remove_file(&part);
            last = Error::HashMismatch(f.path.clone());
        }
        Err(last)
    }

    /// The swap: journal, old file to `backup/`, staged file in place; undone entirely on the first failure.
    fn apply(&self, items: &[&NativeFile]) -> Result<(), Error> {
        let backup = self.backup_dir();
        let _ = std::fs::remove_dir_all(&backup);
        io(std::fs::create_dir_all(&backup), "backup folder")?;
        let entries: Vec<JournalEntry> = items
            .iter()
            .map(|f| JournalEntry {
                path: f.path.clone(),
                sha: f.sha256.clone(),
                had_old: self.cfg.dir.join(&f.path).exists(),
            })
            .collect();
        let j = json!({"files": entries.iter().map(|e| json!({"path": e.path, "sha": e.sha, "had_old": e.had_old})).collect::<Vec<_>>()});
        write_atomic(&self.journal(), &j.to_string())?;
        let result = self.swap_all(&entries);
        if let Err(why) = result {
            return match self.rollback(&entries) {
                Ok(()) => {
                    let _ = std::fs::remove_file(self.journal());
                    let _ = std::fs::remove_dir_all(&backup);
                    Err(Error::Apply(why))
                }
                Err(rb) => Err(Error::Rollback(rb)),
            };
        }
        let _ = std::fs::remove_file(self.journal());
        let _ = std::fs::remove_dir_all(&backup);
        Ok(())
    }

    fn swap_all(&self, entries: &[JournalEntry]) -> Result<(), String> {
        for (i, e) in entries.iter().enumerate() {
            if self.opts.fault == Fault::FailApplyAfter(i) {
                return Err("injected failure".into());
            }
            let dest = self.cfg.dir.join(&e.path);
            if e.had_old {
                let backup = self.backup_dir().join(&e.path);
                if let Some(parent) = backup.parent() {
                    std::fs::create_dir_all(parent).map_err(|err| format!("{}: {err}", e.path))?;
                }
                std::fs::rename(&dest, &backup).map_err(|err| format!("{}: {err}", e.path))?;
            }
            if let Some(parent) = dest.parent() {
                std::fs::create_dir_all(parent).map_err(|err| format!("{}: {err}", e.path))?;
            }
            std::fs::rename(self.stage_dir().join(&e.sha), &dest).map_err(|err| format!("{}: {err}", e.path))?;
            #[cfg(unix)]
            {
                use std::os::unix::fs::PermissionsExt;
                if apply_order(&e.path) {
                    let _ = std::fs::set_permissions(&dest, std::fs::Permissions::from_mode(0o755));
                }
            }
        }
        Ok(())
    }
}

#[derive(Debug, Clone)]
struct JournalEntry {
    path: String,
    sha: String,
    had_old: bool,
}

fn parse_journal(v: &Value, layout: Layout) -> Vec<JournalEntry> {
    let mut out = Vec::new();
    for f in v.get("files").and_then(Value::as_array).into_iter().flatten() {
        let path = f.get("path").and_then(Value::as_str).unwrap_or("");
        // a journal is local, but never follow a path out of the install folder
        if layout.check_path(path).is_some() {
            continue;
        }
        out.push(JournalEntry {
            path: path.to_string(),
            sha: f.get("sha").and_then(Value::as_str).unwrap_or("").to_string(),
            had_old: f.get("had_old").and_then(Value::as_bool).unwrap_or(false),
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn http(n: u16) -> FetchError {
        FetchError::http(n, format!("curl 22: returned error: {n}"))
    }

    #[test]
    fn a_missing_unity_manifest_is_not_published() {
        assert_eq!(manifest_fetch_error(http(404), true), Error::UnityNotPublished);
        assert_eq!(manifest_fetch_error(http(410), true), Error::UnityNotPublished);
    }

    #[test]
    fn other_unity_answers_are_server_errors() {
        for n in [403u16, 500, 503] {
            assert_eq!(manifest_fetch_error(http(n), true), Error::Http(n));
        }
    }

    #[test]
    fn the_main_client_never_gets_the_unity_text() {
        assert_eq!(manifest_fetch_error(http(404), false), Error::Http(404));
        assert_eq!(manifest_fetch_error(http(410), false), Error::Http(410));
        assert_eq!(manifest_fetch_error(http(500), false), Error::Http(500));
    }

    #[test]
    fn a_transport_failure_stays_a_network_error_for_both() {
        for unity in [false, true] {
            let e = FetchError::from("curl 7: refused");
            assert_eq!(manifest_fetch_error(e, unity), Error::Network("curl 7: refused".into()));
        }
    }
}
