//! Texts in pt-BR and en. The launcher shows no other language.
use std::fmt;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Lang {
    Pt,
    En,
}

impl Lang {
    /// "en", "en-US", "en_GB.UTF-8" give English; anything else Portuguese (the game's players are Brazilian).
    pub fn from_tag(tag: &str) -> Lang {
        let t = tag.trim().to_ascii_lowercase();
        if t == "en" || t.starts_with("en-") || t.starts_with("en_") || t == "c" || t == "posix" {
            Lang::En
        } else {
            Lang::Pt
        }
    }

    /// `CINDERS_LANG`, then `LC_ALL`, then `LANG`; Portuguese when none is set.
    pub fn detect(get: impl Fn(&str) -> Option<String>) -> Lang {
        for k in ["CINDERS_LANG", "LC_ALL", "LANG"] {
            if let Some(v) = get(k).filter(|v| !v.trim().is_empty()) {
                return Lang::from_tag(&v);
            }
        }
        Lang::Pt
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Status {
    Checking,
    Hashing,
    Downloading,
    Applying,
    LauncherStaged,
    UpToDate,
    Updated,
    Launching,
}

pub fn status(s: Status, l: Lang) -> &'static str {
    match (s, l) {
        (Status::Checking, Lang::Pt) => "Procurando atualizações...",
        (Status::Checking, Lang::En) => "Looking for updates...",
        (Status::Hashing, Lang::Pt) => "Conferindo os arquivos do jogo...",
        (Status::Hashing, Lang::En) => "Checking the game files...",
        (Status::Downloading, Lang::Pt) => "Baixando atualização...",
        (Status::Downloading, Lang::En) => "Downloading the update...",
        (Status::Applying, Lang::Pt) => "Instalando os arquivos...",
        (Status::Applying, Lang::En) => "Installing the files...",
        (Status::LauncherStaged, Lang::Pt) => "Nova versão do launcher pronta. Ela entra na próxima vez que abrir.",
        (Status::LauncherStaged, Lang::En) => "A new launcher version is ready. It starts next time you open it.",
        (Status::UpToDate, Lang::Pt) => "O jogo está atualizado.",
        (Status::UpToDate, Lang::En) => "The game is up to date.",
        (Status::Updated, Lang::Pt) => "Atualização instalada.",
        (Status::Updated, Lang::En) => "Update installed.",
        (Status::Launching, Lang::Pt) => "Abrindo o jogo...",
        (Status::Launching, Lang::En) => "Starting the game...",
    }
}

pub fn play(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Jogar",
        Lang::En => "Play",
    }
}

pub fn retry(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Tentar de novo",
        Lang::En => "Try again",
    }
}

pub fn play_anyway(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Jogar assim mesmo",
        Lang::En => "Play anyway",
    }
}

pub fn title(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Cinders of Chaos Launcher",
        Lang::En => "Cinders of Chaos Launcher",
    }
}

/// Everything that can stop an update. Nothing here leaves the install half changed: files are staged and checked
/// first, then swapped with a rollback.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// Manifest or file could not be fetched: the server is unreachable or answered an error.
    Network(String),
    /// Signature missing, malformed, wrong key or wrong bytes.
    BadSignature,
    /// Signed, but the content breaks a rule (path, hash, size, product).
    BadManifest(String),
    /// The manifest is older than the one already applied or than this package.
    OlderManifest { got: u64, have: u64 },
    /// A downloaded file does not hash to the signed value (after all retries).
    HashMismatch(String),
    /// The download of a file failed after all retries.
    Download { file: String, detail: String },
    /// Swapping the files failed; the old files were put back.
    Apply(String),
    /// The old files could not be put back; a rerun repairs it from the journal.
    Rollback(String),
    /// The settings file (`launcher.json`) is missing or wrong.
    Config(String),
    /// The game program is not in the install folder.
    NoGame(String),
    /// A local file operation failed.
    Io(String),
}

impl Error {
    pub fn text(&self, l: Lang) -> String {
        match (self, l) {
            (Error::Network(d), Lang::Pt) => format!("Não foi possível falar com o servidor de atualização. Confira a internet e tente de novo. ({d})"),
            (Error::Network(d), Lang::En) => format!("Could not reach the update server. Check your internet and try again. ({d})"),
            (Error::BadSignature, Lang::Pt) => "A assinatura da atualização não confere. Nada foi instalado.".into(),
            (Error::BadSignature, Lang::En) => "The update signature does not match. Nothing was installed.".into(),
            (Error::BadManifest(d), Lang::Pt) => format!("A lista de atualização é inválida. Nada foi instalado. ({d})"),
            (Error::BadManifest(d), Lang::En) => format!("The update list is invalid. Nothing was installed. ({d})"),
            (Error::OlderManifest { got, have }, Lang::Pt) => format!("A atualização do servidor ({got}) é mais velha que a sua ({have}). Nada foi mudado."),
            (Error::OlderManifest { got, have }, Lang::En) => format!("The server update ({got}) is older than yours ({have}). Nothing was changed."),
            (Error::HashMismatch(f), Lang::Pt) => format!("O arquivo {f} veio corrompido. Nada foi instalado. Tente de novo."),
            (Error::HashMismatch(f), Lang::En) => format!("The file {f} arrived damaged. Nothing was installed. Try again."),
            (Error::Download { file, detail }, Lang::Pt) => format!("Falha ao baixar {file}. Tente de novo. O que já veio não se perde. ({detail})"),
            (Error::Download { file, detail }, Lang::En) => format!("Could not download {file}. Try again. What already arrived is kept. ({detail})"),
            (Error::Apply(d), Lang::Pt) => format!("Não foi possível instalar os arquivos. Os antigos foram devolvidos. Feche o jogo e tente de novo. ({d})"),
            (Error::Apply(d), Lang::En) => format!("Could not install the files. The old ones were put back. Close the game and try again. ({d})"),
            (Error::Rollback(d), Lang::Pt) => format!("A instalação falhou e os arquivos antigos não voltaram todos. Abra o launcher de novo para consertar. ({d})"),
            (Error::Rollback(d), Lang::En) => format!("The install failed and not every old file came back. Open the launcher again to repair it. ({d})"),
            (Error::Config(d), Lang::Pt) => format!("Configuração do launcher inválida (launcher.json). Baixe o jogo de novo no site. ({d})"),
            (Error::Config(d), Lang::En) => format!("The launcher settings (launcher.json) are invalid. Download the game again from the website. ({d})"),
            (Error::NoGame(f), Lang::Pt) => format!("O programa do jogo ({f}) não está na pasta. Atualize ou baixe o jogo de novo."),
            (Error::NoGame(f), Lang::En) => format!("The game program ({f}) is not in the folder. Update or download the game again."),
            (Error::Io(d), Lang::Pt) => format!("Erro com arquivos no disco. Confira o espaço livre. ({d})"),
            (Error::Io(d), Lang::En) => format!("Disk error. Check the free space. ({d})"),
        }
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.text(Lang::En))
    }
}

impl std::error::Error for Error {}

impl From<std::io::Error> for Error {
    fn from(e: std::io::Error) -> Self {
        Error::Io(e.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn language_detection() {
        assert_eq!(Lang::from_tag("en_US.UTF-8"), Lang::En);
        assert_eq!(Lang::from_tag("EN"), Lang::En);
        assert_eq!(Lang::from_tag("pt_BR.UTF-8"), Lang::Pt);
        assert_eq!(Lang::from_tag("de_DE"), Lang::Pt);
        let env = |k: &str| (k == "LANG").then(|| "en_GB".to_string());
        assert_eq!(Lang::detect(env), Lang::En);
        assert_eq!(Lang::detect(|_| None), Lang::Pt);
        let both = |k: &str| match k {
            "CINDERS_LANG" => Some("pt-BR".to_string()),
            "LANG" => Some("en_US".to_string()),
            _ => None,
        };
        assert_eq!(Lang::detect(both), Lang::Pt);
    }

    #[test]
    fn every_error_has_both_languages() {
        let all = [
            Error::Network("x".into()),
            Error::BadSignature,
            Error::BadManifest("x".into()),
            Error::OlderManifest { got: 1, have: 2 },
            Error::HashMismatch("Chaos.exe".into()),
            Error::Download {
                file: "a.dll".into(),
                detail: "x".into(),
            },
            Error::Apply("x".into()),
            Error::Rollback("x".into()),
            Error::Config("x".into()),
            Error::NoGame("Chaos.exe".into()),
            Error::Io("x".into()),
        ];
        for e in all {
            let (pt, en) = (e.text(Lang::Pt), e.text(Lang::En));
            assert!(!pt.is_empty() && !en.is_empty() && pt != en, "{e:?}");
        }
    }

    #[test]
    fn statuses_differ_by_language() {
        for s in [
            Status::Checking,
            Status::Hashing,
            Status::Downloading,
            Status::Applying,
            Status::LauncherStaged,
            Status::UpToDate,
            Status::Updated,
            Status::Launching,
        ] {
            assert_ne!(status(s, Lang::Pt), status(s, Lang::En));
        }
    }
}
