//! The launcher installs itself (O552 phase C): started from anywhere with no `launcher.json` beside it, it shows a
//! setup screen, copies itself into the chosen folder, writes `launcher.json` from the facts built into it, makes the
//! shortcuts and the uninstall entry, and starts the copy, which then downloads the whole client like any update.
//! No admin rights: a per-user folder, per-user registry keys, per-user shortcuts.
//!
//! Everything that touches Windows goes through the traits `Shell` and `Registry`, so the logic here is tested on
//! Linux with fakes; the real ones are in `winshell.rs` (Windows only, not run in CI on a Windows machine).
use crate::config;
use crate::i18n::Error;
use crate::install::{io, STATE_DIR};
use std::path::{Path, PathBuf};

pub const EXE_NAME: &str = "CindersLauncher.exe";
pub const APP_NAME: &str = "Cinders of Chaos";
pub const UNINSTALL_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Uninstall\CindersOfChaos";
pub const APP_KEY: &str = r"Software\CindersOfChaos";

/// The facts built into this launcher (the text of a `launcher.json`, written by `set_launcher_config.py --embed`),
/// or empty for a build that has none.
pub const EMBEDDED: &str = include_str!(concat!(env!("OUT_DIR"), "/embedded.json"));

/// The real system side: Windows shortcuts, registry and dialogs on Windows, nothing elsewhere.
#[cfg(windows)]
pub const SYSTEM: crate::winshell::Real = crate::winshell::Real;
#[cfg(not(windows))]
pub const SYSTEM: Plain = Plain;

/// The size of a first install in bytes: every native file of the signed manifest, for the setup screen's "needs 1,1 GB".
/// None when the manifest has no native section (nothing for the launcher to install).
pub fn download_size(fetch: &dyn crate::net::Fetch, cfg: &config::Config) -> Result<Option<u64>, Error> {
    let m = crate::install::fetch_manifest(fetch, cfg)?;
    Ok(m.native.map(|n| n.files.iter().map(|f| f.size).sum()))
}

/// Free bytes in the folder a path will live in (the nearest folder that exists), None when unknown.
pub fn free_space(path: &Path) -> Option<u64> {
    let mut at = Some(path);
    while let Some(p) = at {
        if p.is_dir() {
            return fs2::available_space(p).ok();
        }
        at = p.parent();
    }
    None
}

/// What the launcher does at start.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Mode {
    /// `launcher.json` is beside the program: the normal launcher.
    Normal,
    /// No `launcher.json`, but facts are built in: the setup screen.
    Setup,
    /// Neither: the old "launcher.json is missing" error.
    Broken,
}

pub fn mode(dir: &Path, embedded: &str) -> Mode {
    if dir.join(config::FILE).is_file() {
        Mode::Normal
    } else if config::parse(embedded, dir).is_ok() {
        Mode::Setup
    } else {
        Mode::Broken
    }
}

/// `%LOCALAPPDATA%\CindersOfChaos`, else a folder in the user's home (Linux tests), else None.
pub fn default_dir(get: impl Fn(&str) -> Option<String>) -> Option<PathBuf> {
    if let Some(p) = get("LOCALAPPDATA").filter(|p| !p.trim().is_empty()) {
        return Some(PathBuf::from(p).join("CindersOfChaos"));
    }
    let home = get("HOME").filter(|p| !p.trim().is_empty())?;
    Some(PathBuf::from(home).join(".local").join("share").join("CindersOfChaos"))
}

/// What is wrong with a chosen folder. `Warn` can be overridden by the player, `Refuse` cannot.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Dir {
    Ok,
    Warn(DirWarn),
    Refuse(DirRefuse),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DirWarn {
    /// Program Files: the launcher has no admin rights there and will fail to write.
    ProgramFiles,
    /// A network path.
    Network,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DirRefuse {
    Empty,
    NotAbsolute,
    /// The folder exists and holds files that are not ours: the game is never mixed into them.
    NotEmpty,
    /// The path is a file.
    IsFile,
    /// A drive root or a system folder.
    Root,
}

pub fn check_dir(p: &Path) -> Dir {
    let text = p.to_string_lossy();
    if text.trim().is_empty() {
        return Dir::Refuse(DirRefuse::Empty);
    }
    // `C:\...`, `\\server\...` and `/...` count as absolute whatever the system running the check
    let win_abs = text.len() > 2 && text.as_bytes()[1] == b':' && text.as_bytes()[0].is_ascii_alphabetic();
    let unc = text.starts_with("\\\\") || text.starts_with("//");
    if !(p.is_absolute() || win_abs || unc) {
        return Dir::Refuse(DirRefuse::NotAbsolute);
    }
    let norm = text.replace('/', "\\").to_ascii_lowercase();
    let trimmed = norm.trim_end_matches('\\');
    if trimmed.is_empty() || (trimmed.len() == 2 && trimmed.ends_with(':')) || p.parent().is_none() {
        return Dir::Refuse(DirRefuse::Root);
    }
    if trimmed.ends_with("\\windows") || trimmed.ends_with("\\system32") {
        return Dir::Refuse(DirRefuse::Root);
    }
    if p.is_file() {
        return Dir::Refuse(DirRefuse::IsFile);
    }
    if p.is_dir() {
        let ours = p.join(config::FILE).is_file() || p.join(STATE_DIR).is_dir();
        let empty = std::fs::read_dir(p).map(|mut d| d.next().is_none()).unwrap_or(false);
        if !ours && !empty {
            return Dir::Refuse(DirRefuse::NotEmpty);
        }
    }
    if unc {
        return Dir::Warn(DirWarn::Network);
    }
    if norm.contains("\\program files") {
        return Dir::Warn(DirWarn::ProgramFiles);
    }
    Dir::Ok
}

/// What the real Windows (or a fake) does for the setup.
pub trait Shell {
    /// A `.lnk` file at `link` that starts `target` with `args` in `workdir`, with the icon of `icon`.
    fn make_shortcut(&self, link: &Path, target: &Path, args: &str, workdir: &Path, icon: &Path) -> Result<(), String>;
    fn desktop_dir(&self) -> Option<PathBuf>;
    fn start_menu_dir(&self) -> Option<PathBuf>;
    /// A folder dialog; None when the player cancels or the system has none.
    fn pick_folder(&self, start: &Path) -> Option<PathBuf>;
    /// Removes the running program and its folder a moment after it exits (Windows cannot delete a running exe).
    fn delete_self_later(&self, exe: &Path, dir: &Path);
}

pub struct UninstallEntry {
    pub name: String,
    pub version: String,
    pub publisher: String,
    pub dir: PathBuf,
    pub exe: PathBuf,
    pub size_kb: u32,
}

pub trait Registry {
    fn write_install(&self, entry: &UninstallEntry) -> Result<(), String>;
    fn remove_install(&self) -> Result<(), String>;
    fn install_dir(&self) -> Option<PathBuf>;
}

/// The system side on a machine with no Windows (a Linux run for development): no shortcuts, no registry, no dialog.
pub struct Plain;

impl Shell for Plain {
    fn make_shortcut(&self, _l: &Path, _t: &Path, _a: &str, _w: &Path, _i: &Path) -> Result<(), String> {
        Err("no shortcuts on this system".into())
    }
    fn desktop_dir(&self) -> Option<PathBuf> {
        None
    }
    fn start_menu_dir(&self) -> Option<PathBuf> {
        None
    }
    fn pick_folder(&self, _s: &Path) -> Option<PathBuf> {
        None
    }
    fn delete_self_later(&self, _e: &Path, _d: &Path) {}
}

impl Registry for Plain {
    fn write_install(&self, _e: &UninstallEntry) -> Result<(), String> {
        Ok(())
    }
    fn remove_install(&self) -> Result<(), String> {
        Ok(())
    }
    fn install_dir(&self) -> Option<PathBuf> {
        None
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Choices {
    pub desktop: bool,
    pub start_menu: bool,
}

impl Default for Choices {
    fn default() -> Self {
        Choices {
            desktop: true,
            start_menu: true,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Installed {
    pub exe: PathBuf,
    pub shortcuts: Vec<PathBuf>,
}

fn link_name() -> String {
    format!("{APP_NAME}.lnk")
}

/// Puts the launcher in `dir` and wires it into the system. `me` is the running program (copied, not moved).
/// Shortcut and registry failures are not fatal (the game still runs from the folder); a folder or copy failure is.
pub fn install(
    me: &Path,
    dir: &Path,
    embedded: &str,
    choices: Choices,
    version: &str,
    shell: &dyn Shell,
    reg: &dyn Registry,
) -> Result<Installed, Error> {
    match check_dir(dir) {
        Dir::Refuse(_) => {
            return Err(Error::Io(format!(
                "{}: not a folder the game can be installed in",
                dir.display()
            )))
        }
        Dir::Ok | Dir::Warn(_) => {}
    }
    config::parse(embedded, dir)?; // the facts built in must be good before anything is written
    io(std::fs::create_dir_all(dir), "create the game folder")?;
    let exe = dir.join(EXE_NAME);
    // a copy beside the final name, then a rename: a half-copied program is never started
    let tmp = dir.join(format!("{EXE_NAME}.new"));
    io(std::fs::copy(me, &tmp), "copy the launcher")?;
    let _ = std::fs::remove_file(&exe);
    io(std::fs::rename(&tmp, &exe), "put the launcher in place")?;
    io(std::fs::write(dir.join(config::FILE), embedded), "write launcher.json")?;
    let mut shortcuts = Vec::new();
    let mut shortcut = |base: Option<PathBuf>| {
        if let Some(b) = base {
            let _ = std::fs::create_dir_all(&b);
            let link = b.join(link_name());
            if shell.make_shortcut(&link, &exe, "", dir, &exe).is_ok() {
                shortcuts.push(link);
            }
        }
    };
    if choices.desktop {
        shortcut(shell.desktop_dir());
    }
    if choices.start_menu {
        shortcut(shell.start_menu_dir());
    }
    let size_kb = std::fs::metadata(&exe).map(|m| (m.len() / 1024) as u32).unwrap_or(0);
    let _ = reg.write_install(&UninstallEntry {
        name: APP_NAME.to_string(),
        version: version.to_string(),
        publisher: APP_NAME.to_string(),
        dir: dir.to_path_buf(),
        exe: exe.clone(),
        size_kb,
    });
    Ok(Installed { exe, shortcuts })
}

/// Removes what the launcher owns and nothing else: the native files an earlier run listed in `owned.json`, its state
/// folder, `chaos_update/` (the in-game updater's folder), `unity/` when `with_unity`, `launcher.json`, the shortcuts and the
/// registry entries; then the launcher itself after it exits. The folder is removed only if that leaves it empty; a
/// file the player put there stays, and so does the folder around it. Returns what was removed.
pub fn uninstall(dir: &Path, me: &Path, shell: &dyn Shell, reg: &dyn Registry) -> Vec<String> {
    let mut removed = Vec::new();
    let owned: Vec<String> = std::fs::read_to_string(dir.join(STATE_DIR).join("owned.json"))
        .ok()
        .and_then(|t| serde_json::from_str::<serde_json::Value>(&t).ok())
        .and_then(|v| v.get("files").and_then(|f| f.as_array().cloned()))
        .unwrap_or_default()
        .iter()
        .filter_map(|n| n.as_str().map(str::to_string))
        .collect();
    for n in owned {
        // only plain names directly in the folder, as the update itself does
        if crate::manifest::check_native_name(&n).is_none() && !n.eq_ignore_ascii_case(EXE_NAME) {
            let p = dir.join(&n);
            if p.is_file() && std::fs::remove_file(&p).is_ok() {
                removed.push(n);
            }
        }
    }
    for sub in [STATE_DIR, "chaos_update", "unity"] {
        let p = dir.join(sub);
        if p.is_dir() && std::fs::remove_dir_all(&p).is_ok() {
            removed.push(format!("{sub}/"));
        }
    }
    for f in [config::FILE, "launcher.json.bak"] {
        if std::fs::remove_file(dir.join(f)).is_ok() {
            removed.push(f.to_string());
        }
    }
    for base in [shell.desktop_dir(), shell.start_menu_dir()].into_iter().flatten() {
        let link = base.join(link_name());
        if std::fs::remove_file(&link).is_ok() {
            removed.push(link.display().to_string());
        }
    }
    let _ = reg.remove_install();
    shell.delete_self_later(me, dir);
    removed
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    const KEY: &str = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a";

    fn embedded() -> String {
        format!(r#"{{"manifest":"https://x.test/updates/live/manifest.json","public_key":"{KEY}"}}"#)
    }

    struct FakeShell {
        desktop: PathBuf,
        menu: PathBuf,
        made: RefCell<Vec<(PathBuf, PathBuf, String)>>,
        fail: bool,
        deleted: RefCell<Option<(PathBuf, PathBuf)>>,
    }

    impl Shell for FakeShell {
        fn make_shortcut(&self, link: &Path, target: &Path, args: &str, _w: &Path, _i: &Path) -> Result<(), String> {
            if self.fail {
                return Err("no shell".into());
            }
            std::fs::write(link, format!("lnk to {}", target.display())).map_err(|e| e.to_string())?;
            self.made
                .borrow_mut()
                .push((link.to_path_buf(), target.to_path_buf(), args.to_string()));
            Ok(())
        }
        fn desktop_dir(&self) -> Option<PathBuf> {
            Some(self.desktop.clone())
        }
        fn start_menu_dir(&self) -> Option<PathBuf> {
            Some(self.menu.clone())
        }
        fn pick_folder(&self, _s: &Path) -> Option<PathBuf> {
            None
        }
        fn delete_self_later(&self, exe: &Path, dir: &Path) {
            *self.deleted.borrow_mut() = Some((exe.to_path_buf(), dir.to_path_buf()));
        }
    }

    #[derive(Default)]
    struct FakeReg {
        entry: RefCell<Option<(String, String, PathBuf, PathBuf)>>,
    }

    impl Registry for FakeReg {
        fn write_install(&self, e: &UninstallEntry) -> Result<(), String> {
            *self.entry.borrow_mut() = Some((e.name.clone(), e.version.clone(), e.dir.clone(), e.exe.clone()));
            Ok(())
        }
        fn remove_install(&self) -> Result<(), String> {
            *self.entry.borrow_mut() = None;
            Ok(())
        }
        fn install_dir(&self) -> Option<PathBuf> {
            self.entry.borrow().as_ref().map(|e| e.2.clone())
        }
    }

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("cinders-setup-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn shell(root: &Path, fail: bool) -> FakeShell {
        FakeShell {
            desktop: root.join("Desktop"),
            menu: root.join("Programs"),
            made: RefCell::new(vec![]),
            fail,
            deleted: RefCell::new(None),
        }
    }

    #[test]
    fn the_mode_follows_what_is_beside_the_program() {
        let d = tmp("mode");
        assert_eq!(mode(&d, &embedded()), Mode::Setup);
        assert_eq!(mode(&d, ""), Mode::Broken);
        assert_eq!(mode(&d, "{}"), Mode::Broken);
        std::fs::write(d.join(config::FILE), embedded()).unwrap();
        assert_eq!(
            mode(&d, ""),
            Mode::Normal,
            "a launcher.json wins over anything built in"
        );
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn default_folder_is_per_user() {
        let get = |k: &str| (k == "LOCALAPPDATA").then(|| r"C:\Users\Ana\AppData\Local".to_string());
        assert_eq!(
            default_dir(get),
            Some(PathBuf::from(r"C:\Users\Ana\AppData\Local").join("CindersOfChaos"))
        );
        let home = |k: &str| (k == "HOME").then(|| "/home/ana".to_string());
        assert_eq!(
            default_dir(home),
            Some(PathBuf::from("/home/ana/.local/share/CindersOfChaos"))
        );
        assert_eq!(default_dir(|_| None), None);
        assert_eq!(default_dir(|_| Some("  ".into())), None);
    }

    #[test]
    fn folder_rules() {
        let d = tmp("dirs");
        let new = d.join("Game");
        assert_eq!(check_dir(&new), Dir::Ok);
        std::fs::create_dir_all(&new).unwrap();
        assert_eq!(check_dir(&new), Dir::Ok, "an empty folder");
        std::fs::write(new.join("notes.txt"), b"x").unwrap();
        assert_eq!(
            check_dir(&new),
            Dir::Refuse(DirRefuse::NotEmpty),
            "someone else's files"
        );
        std::fs::write(new.join(config::FILE), b"{}").unwrap();
        assert_eq!(check_dir(&new), Dir::Ok, "an earlier install of ours");
        assert_eq!(check_dir(&new.join("notes.txt")), Dir::Refuse(DirRefuse::IsFile));
        assert_eq!(check_dir(Path::new("")), Dir::Refuse(DirRefuse::Empty));
        assert_eq!(
            check_dir(Path::new("games/cinders")),
            Dir::Refuse(DirRefuse::NotAbsolute)
        );
        assert_eq!(check_dir(Path::new(r"C:\")), Dir::Refuse(DirRefuse::Root));
        assert_eq!(check_dir(Path::new("/")), Dir::Refuse(DirRefuse::Root));
        assert_eq!(check_dir(Path::new(r"C:\Windows")), Dir::Refuse(DirRefuse::Root));
        assert_eq!(
            check_dir(Path::new(r"C:\Program Files\Cinders")),
            Dir::Warn(DirWarn::ProgramFiles)
        );
        assert_eq!(
            check_dir(Path::new(r"\\server\share\game")),
            Dir::Warn(DirWarn::Network)
        );
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn install_copies_the_program_writes_the_facts_and_wires_the_system() {
        let d = tmp("install");
        let me = d.join("Cinders-of-Chaos-Setup.exe");
        std::fs::write(&me, b"launcher bytes").unwrap();
        let dir = d.join("Games").join("CindersOfChaos");
        let sh = shell(&d, false);
        let reg = FakeReg::default();
        let r = install(&me, &dir, &embedded(), Choices::default(), "0.2.0", &sh, &reg).unwrap();
        assert_eq!(r.exe, dir.join(EXE_NAME));
        assert_eq!(std::fs::read(&r.exe).unwrap(), b"launcher bytes");
        assert!(!dir.join(format!("{EXE_NAME}.new")).exists(), "no half copy left");
        assert_eq!(std::fs::read_to_string(dir.join(config::FILE)).unwrap(), embedded());
        // the folder now reads as a normal install
        assert_eq!(mode(&dir, ""), Mode::Normal);
        assert!(config::load(&dir).is_ok());
        // two shortcuts, both to the installed program; the setup file itself is untouched
        assert_eq!(r.shortcuts.len(), 2);
        assert!(sh.made.borrow().iter().all(|(_, t, _)| *t == r.exe));
        assert!(me.is_file());
        let e = reg.entry.borrow().clone().unwrap();
        assert_eq!(
            (e.0.as_str(), e.1.as_str(), e.2.clone(), e.3),
            ("Cinders of Chaos", "0.2.0", dir, r.exe)
        );
        // the player's choices
        let sh2 = shell(&d, false);
        let r2 = install(
            &me,
            &d.join("Two"),
            &embedded(),
            Choices {
                desktop: false,
                start_menu: true,
            },
            "0.2.0",
            &sh2,
            &FakeReg::default(),
        )
        .unwrap();
        assert_eq!(r2.shortcuts.len(), 1);
        assert!(r2.shortcuts[0].starts_with(d.join("Programs")));
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn install_twice_is_fine_and_a_failed_shortcut_is_not_fatal() {
        let d = tmp("twice");
        let me = d.join("setup.exe");
        std::fs::write(&me, b"v1").unwrap();
        let dir = d.join("Game");
        let reg = FakeReg::default();
        install(&me, &dir, &embedded(), Choices::default(), "1", &shell(&d, false), &reg).unwrap();
        std::fs::write(&me, b"v2").unwrap();
        let r = install(&me, &dir, &embedded(), Choices::default(), "2", &shell(&d, true), &reg).unwrap();
        assert!(r.shortcuts.is_empty());
        assert_eq!(std::fs::read(dir.join(EXE_NAME)).unwrap(), b"v2");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn install_refuses_before_writing_anything() {
        let d = tmp("refuse");
        let me = d.join("setup.exe");
        std::fs::write(&me, b"x").unwrap();
        let full = d.join("Full");
        std::fs::create_dir_all(&full).unwrap();
        std::fs::write(full.join("mine.txt"), b"mine").unwrap();
        let reg = FakeReg::default();
        assert!(install(
            &me,
            &full,
            &embedded(),
            Choices::default(),
            "1",
            &shell(&d, false),
            &reg
        )
        .is_err());
        assert!(!full.join(EXE_NAME).exists() && !full.join(config::FILE).exists());
        assert!(reg.entry.borrow().is_none());
        // facts that do not parse stop it too
        let ok = d.join("Ok");
        assert!(install(&me, &ok, "{}", Choices::default(), "1", &shell(&d, false), &reg).is_err());
        assert!(!ok.exists(), "nothing was created");
        let _ = std::fs::remove_dir_all(&d);
    }

    #[test]
    fn uninstall_removes_only_what_the_launcher_owns() {
        let d = tmp("uninstall");
        let me = d.join("setup.exe");
        std::fs::write(&me, b"x").unwrap();
        let dir = d.join("Game");
        let sh = shell(&d, false);
        let reg = FakeReg::default();
        install(&me, &dir, &embedded(), Choices::default(), "1", &sh, &reg).unwrap();
        // what an update leaves: native files, the state folder, the in-game updater's folder, a Unity folder
        std::fs::write(dir.join("Chaos.exe"), b"exe").unwrap();
        std::fs::write(dir.join("a.dll"), b"dll").unwrap();
        std::fs::create_dir_all(dir.join(STATE_DIR)).unwrap();
        std::fs::write(
            dir.join(STATE_DIR).join("owned.json"),
            r#"{"files":["Chaos.exe","a.dll","../outside.dll","notes.txt","CindersLauncher.exe"]}"#,
        )
        .unwrap();
        std::fs::create_dir_all(dir.join("chaos_update").join("files")).unwrap();
        std::fs::create_dir_all(dir.join("unity")).unwrap();
        // the player's own files, and a file the list names that is not a native name
        std::fs::write(dir.join("notes.txt"), b"keep me").unwrap();
        std::fs::write(dir.join("screenshot.png"), b"keep me too").unwrap();
        std::fs::write(d.join("outside.dll"), b"not ours").unwrap();
        let removed = uninstall(&dir, &dir.join(EXE_NAME), &sh, &reg);
        assert!(removed.contains(&"Chaos.exe".to_string()) && removed.contains(&"a.dll".to_string()));
        for gone in ["Chaos.exe", "a.dll", "launcher.json"] {
            assert!(!dir.join(gone).exists(), "{gone}");
        }
        for gone in [STATE_DIR, "chaos_update", "unity"] {
            assert!(!dir.join(gone).exists(), "{gone}");
        }
        assert_eq!(std::fs::read(dir.join("notes.txt")).unwrap(), b"keep me");
        assert!(dir.join("screenshot.png").is_file());
        assert!(d.join("outside.dll").is_file(), "nothing outside the folder");
        assert!(
            dir.join(EXE_NAME).is_file(),
            "the running program is left to delete_self_later"
        );
        assert!(!d.join("Desktop").join(link_name()).exists() && !d.join("Programs").join(link_name()).exists());
        assert!(reg.entry.borrow().is_none());
        assert_eq!(sh.deleted.borrow().clone(), Some((dir.join(EXE_NAME), dir.clone())));
        let _ = std::fs::remove_dir_all(&d);
    }
}
