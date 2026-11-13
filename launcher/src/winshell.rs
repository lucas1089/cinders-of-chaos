//! The real Windows side of the setup (O552 phase C): shortcuts (`.lnk`), the per-user registry entries, the folder
//! dialog and the delayed delete of the running program. Compiled on Windows only; the logic that uses it is in
//! `setup.rs` and is tested with fakes. Not run in this repository's CI (Linux): the first real run is on Windows.
use crate::setup::{Registry, Shell, UninstallEntry, APP_KEY, UNINSTALL_KEY};
use std::path::{Path, PathBuf};
use winreg::enums::HKEY_CURRENT_USER;
use winreg::RegKey;

pub struct Real;

fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name).map(PathBuf::from).filter(|p| p.is_dir())
}

impl Shell for Real {
    fn make_shortcut(&self, link: &Path, target: &Path, args: &str, workdir: &Path, icon: &Path) -> Result<(), String> {
        let mut sl = mslnk::ShellLink::new(target).map_err(|e| e.to_string())?;
        if !args.is_empty() {
            sl.set_arguments(Some(args.to_string()));
        }
        sl.set_working_dir(Some(workdir.display().to_string()));
        sl.set_icon_location(Some(icon.display().to_string()));
        sl.create_lnk(link).map_err(|e| e.to_string())
    }

    fn desktop_dir(&self) -> Option<PathBuf> {
        // the user's Desktop; a OneDrive-redirected one is tried first
        env_path("OneDrive")
            .map(|p| p.join("Desktop"))
            .filter(|p| p.is_dir())
            .or_else(|| {
                env_path("USERPROFILE")
                    .map(|p| p.join("Desktop"))
                    .filter(|p| p.is_dir())
            })
    }

    fn start_menu_dir(&self) -> Option<PathBuf> {
        env_path("APPDATA").map(|p| p.join("Microsoft").join("Windows").join("Start Menu").join("Programs"))
    }

    fn pick_folder(&self, start: &Path) -> Option<PathBuf> {
        let mut d = rfd::FileDialog::new();
        if start.is_dir() {
            d = d.set_directory(start);
        } else if let Some(p) = start.parent().filter(|p| p.is_dir()) {
            d = d.set_directory(p);
        }
        d.pick_folder()
    }

    fn delete_self_later(&self, exe: &Path, dir: &Path) {
        use std::os::windows::process::CommandExt;
        // after this process has exited: delete the program, then the folder if it is empty (`rmdir` never removes files)
        let script = format!(
            "ping 127.0.0.1 -n 3 >nul & del /f /q \"{}\" & rmdir \"{}\"",
            exe.display(),
            dir.display()
        );
        let _ = std::process::Command::new("cmd")
            .args(["/C", &script])
            .creation_flags(0x0800_0000) // CREATE_NO_WINDOW
            .spawn();
    }
}

impl Registry for Real {
    fn write_install(&self, e: &UninstallEntry) -> Result<(), String> {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        let (k, _) = hkcu.create_subkey(UNINSTALL_KEY).map_err(|x| x.to_string())?;
        let s = |k: &RegKey, n: &str, v: &str| k.set_value(n, &v.to_string()).map_err(|x| x.to_string());
        s(&k, "DisplayName", &e.name)?;
        s(&k, "DisplayVersion", &e.version)?;
        s(&k, "Publisher", &e.publisher)?;
        s(&k, "InstallLocation", &e.dir.display().to_string())?;
        s(&k, "DisplayIcon", &e.exe.display().to_string())?;
        s(&k, "UninstallString", &format!("\"{}\" --uninstall", e.exe.display()))?;
        k.set_value("NoModify", &1u32).map_err(|x| x.to_string())?;
        k.set_value("NoRepair", &1u32).map_err(|x| x.to_string())?;
        k.set_value("EstimatedSize", &e.size_kb).map_err(|x| x.to_string())?;
        let (a, _) = hkcu.create_subkey(APP_KEY).map_err(|x| x.to_string())?;
        s(&a, "InstallDir", &e.dir.display().to_string())
    }

    fn remove_install(&self) -> Result<(), String> {
        let hkcu = RegKey::predef(HKEY_CURRENT_USER);
        // a key that is not there is not an error
        let _ = hkcu.delete_subkey_all(UNINSTALL_KEY);
        let _ = hkcu.delete_subkey_all(APP_KEY);
        Ok(())
    }

    fn install_dir(&self) -> Option<PathBuf> {
        let k = RegKey::predef(HKEY_CURRENT_USER).open_subkey(APP_KEY).ok()?;
        k.get_value::<String, _>("InstallDir").ok().map(PathBuf::from)
    }
}

/// "Uninstall?" box. True on Yes.
pub fn confirm_uninstall(title: &str, text: &str) -> bool {
    rfd::MessageDialog::new()
        .set_title(title)
        .set_description(text)
        .set_buttons(rfd::MessageButtons::YesNo)
        .show()
        == rfd::MessageDialogResult::Yes
}
