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

    pub fn tag(self) -> &'static str {
        match self {
            Lang::Pt => "pt",
            Lang::En => "en",
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
    /// "Verify files": the same check with no hash cache.
    Verifying,
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
        (Status::Verifying, Lang::Pt) => "Conferindo e consertando os arquivos...",
        (Status::Verifying, Lang::En) => "Checking and repairing the files...",
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

/// The one button of the "Unity client not published" box: back to the main client.
pub fn use_main_client(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Usar o cliente principal",
        Lang::En => "Use the main client",
    }
}

/// Texts of the window's own parts (O552): the rail, the news strip, the bottom bar and the settings card.
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Ui {
    Ready,
    Discord,
    Site,
    Wiki,
    Signup,
    News,
    NewsSub,
    Settings,
    Close,
    Minimize,
    InstallFolder,
    OpenFolder,
    Verify,
    VerifyHint,
    Verifying,
    ClearCache,
    CloseOnPlay,
    Language,
    Version,
    Files,
    UpToDateLine,
    ReadMore,
    Back,
    NoCards,
    NoSpaceHint,
}

pub fn ui(t: Ui, l: Lang) -> &'static str {
    match (t, l) {
        (Ui::Ready, Lang::Pt) => "Pronto para jogar",
        (Ui::Ready, Lang::En) => "Ready to play",
        (Ui::Discord, _) => "Discord",
        (Ui::Site, _) => "Site",
        (Ui::Wiki, _) => "Wiki",
        (Ui::Signup, Lang::Pt) => "Conta",
        (Ui::Signup, Lang::En) => "Account",
        (Ui::News, Lang::Pt) => "Notícias",
        (Ui::News, Lang::En) => "News",
        (Ui::NewsSub, Lang::Pt) => "do Discord e do site",
        (Ui::NewsSub, Lang::En) => "from Discord and the website",
        (Ui::Settings, Lang::Pt) => "Configurações",
        (Ui::Settings, Lang::En) => "Settings",
        (Ui::Close, Lang::Pt) => "Fechar",
        (Ui::Close, Lang::En) => "Close",
        (Ui::Minimize, Lang::Pt) => "Minimizar",
        (Ui::Minimize, Lang::En) => "Minimize",
        (Ui::InstallFolder, Lang::Pt) => "Pasta do jogo",
        (Ui::InstallFolder, Lang::En) => "Game folder",
        (Ui::OpenFolder, Lang::Pt) => "Abrir pasta",
        (Ui::OpenFolder, Lang::En) => "Open folder",
        (Ui::Verify, Lang::Pt) => "Verificar arquivos",
        (Ui::Verify, Lang::En) => "Verify files",
        (Ui::VerifyHint, Lang::Pt) => "Confere cada arquivo do jogo e baixa de novo só o que estiver errado.",
        (Ui::VerifyHint, Lang::En) => "Checks every game file and downloads again only what is wrong.",
        (Ui::Verifying, Lang::Pt) => "Conferindo e consertando os arquivos...",
        (Ui::Verifying, Lang::En) => "Checking and repairing the files...",
        (Ui::ClearCache, Lang::Pt) => "Limpar cache de download",
        (Ui::ClearCache, Lang::En) => "Clear download cache",
        (Ui::CloseOnPlay, Lang::Pt) => "Fechar o launcher ao jogar",
        (Ui::CloseOnPlay, Lang::En) => "Close the launcher when the game starts",
        (Ui::Language, Lang::Pt) => "Idioma",
        (Ui::Language, Lang::En) => "Language",
        (Ui::Version, Lang::Pt) => "Versão do launcher",
        (Ui::Version, Lang::En) => "Launcher version",
        (Ui::Files, Lang::Pt) => "arquivos",
        (Ui::Files, Lang::En) => "files",
        (Ui::UpToDateLine, Lang::Pt) => "Tudo em dia",
        (Ui::UpToDateLine, Lang::En) => "All up to date",
        (Ui::ReadMore, Lang::Pt) => "Abrir no site",
        (Ui::ReadMore, Lang::En) => "Open on the website",
        (Ui::Back, Lang::Pt) => "Voltar",
        (Ui::Back, Lang::En) => "Back",
        (Ui::NoCards, Lang::Pt) => "Nenhuma novidade por enquanto.",
        (Ui::NoCards, Lang::En) => "No news yet.",
        (Ui::NoSpaceHint, Lang::Pt) => "Libere espaço no disco ou escolha outra pasta.",
        (Ui::NoSpaceHint, Lang::En) => "Free some disk space or pick another folder.",
    }
}

pub fn title(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Cinders of Chaos Launcher",
        Lang::En => "Cinders of Chaos Launcher",
    }
}

/// Footer link to the game's website.
pub fn website(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Site do jogo",
        Lang::En => "Game website",
    }
}

/// The client choice (ROADMAP O433 phase 16): the label, the two names and the note under the Unity one.
pub fn client_label(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Cliente:",
        Lang::En => "Client:",
    }
}

pub fn client_name(c: crate::config::Client, l: Lang) -> &'static str {
    use crate::config::Client;
    match (c, l) {
        (Client::Main, Lang::Pt) => "Cliente principal",
        (Client::Main, Lang::En) => "Main client",
        (Client::Unity, Lang::Pt) => "Cliente Unity (beta)",
        (Client::Unity, Lang::En) => "Unity client (beta)",
    }
}

pub fn unity_note(l: Lang) -> &'static str {
    match l {
        Lang::Pt => "Versão beta, instalada na pasta unity/ do jogo. Ela lê as imagens do jogo dos arquivos cifrados que o launcher instala, ou do chaos.pack do cliente principal.",
        Lang::En => {
            "Beta version, installed in the game's unity/ folder. It reads the game art from the encrypted files the launcher installs, or from the main client's chaos.pack."
        }
    }
}

/// Texts of the News and Changelog panels (src/feed.rs).
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum FeedText {
    TabNews,
    TabChangelog,
    Loading,
    Unavailable,
    SavedCopy,
    NoNews,
    NoChanges,
    ReadMore,
}

pub fn feed_text(t: FeedText, l: Lang) -> &'static str {
    match (t, l) {
        (FeedText::TabNews, Lang::Pt) => "Notícias",
        (FeedText::TabNews, Lang::En) => "News",
        (FeedText::TabChangelog, _) => "Changelog",
        (FeedText::Loading, Lang::Pt) => "Carregando...",
        (FeedText::Loading, Lang::En) => "Loading...",
        (FeedText::Unavailable, Lang::Pt) => {
            "Não foi possível carregar as novidades agora. Você pode jogar normalmente."
        }
        (FeedText::Unavailable, Lang::En) => "The latest news could not be loaded now. You can still play.",
        (FeedText::SavedCopy, Lang::Pt) => "Sem conexão com o site. Mostrando a última cópia salva.",
        (FeedText::SavedCopy, Lang::En) => "Cannot reach the website. Showing the last saved copy.",
        (FeedText::NoNews, Lang::Pt) => "Nenhuma notícia por enquanto.",
        (FeedText::NoNews, Lang::En) => "No news yet.",
        (FeedText::NoChanges, Lang::Pt) => "Nenhuma mudança publicada ainda.",
        (FeedText::NoChanges, Lang::En) => "No changes published yet.",
        (FeedText::ReadMore, Lang::Pt) => "Abrir no site",
        (FeedText::ReadMore, Lang::En) => "Open on the website",
    }
}

/// Everything that can stop an update. Nothing here leaves the install half changed: files are staged and checked
/// first, then swapped with a rollback.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Error {
    /// The manifest could not be fetched: no answer from the server (resolve, connect, timeout, TLS).
    Network(String),
    /// The server answered the manifest request with an HTTP error (400 or more).
    Http(u16),
    /// The Unity manifest answered 404 or 410: the Unity channel was never published (O494).
    UnityNotPublished,
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
    /// The folder cannot hold the download (checked before the first byte).
    NoSpace { need: u64, free: u64 },
    /// The published Unity package is a DEV build (no client key inside): not offered to players.
    DevPackage,
}

impl Error {
    pub fn text(&self, l: Lang) -> String {
        match (self, l) {
            (Error::Network(d), Lang::Pt) => format!("Não foi possível falar com o servidor de atualização. Confira a internet e tente de novo. ({d})"),
            (Error::Network(d), Lang::En) => format!("Could not reach the update server. Check your internet and try again. ({d})"),
            (Error::Http(s), Lang::Pt) => format!("O servidor de atualização respondeu com erro (HTTP {s}). Tente de novo em alguns minutos."),
            (Error::Http(s), Lang::En) => format!("The update server answered with an error (HTTP {s}). Try again in a few minutes."),
            (Error::UnityNotPublished, Lang::Pt) => "O cliente Unity ainda não foi publicado. Use o cliente principal.".into(),
            (Error::UnityNotPublished, Lang::En) => "The Unity client has not been published yet. Use the main client.".into(),
            (Error::BadSignature, Lang::Pt) => "A assinatura da atualização não confere. Nada foi instalado.".into(),
            (Error::BadSignature, Lang::En) => "The update signature does not match. Nothing was installed.".into(),
            (Error::DevPackage, Lang::Pt) => "O cliente Unity publicado é uma versão de desenvolvimento, sem a chave do cliente, e não é oferecido aos jogadores. Nada foi instalado. Use o cliente principal.".into(),
            (Error::DevPackage, Lang::En) => "The published Unity client is a development build without the client key and is not offered to players. Nothing was installed. Use the main client.".into(),
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
            (Error::NoSpace { need, free }, Lang::Pt) => format!(
                "Falta espaço em disco: precisa de {}, tem {}. {}",
                crate::fmt::bytes(*need, l),
                crate::fmt::bytes(*free, l),
                ui(Ui::NoSpaceHint, l)
            ),
            (Error::NoSpace { need, free }, Lang::En) => format!(
                "Not enough disk space: {} needed, {} free. {}",
                crate::fmt::bytes(*need, l),
                crate::fmt::bytes(*free, l),
                ui(Ui::NoSpaceHint, l)
            ),
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
            Error::Http(404),
            Error::UnityNotPublished,
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
            Error::DevPackage,
            Error::NoSpace {
                need: 2_400_000_000,
                free: 1_100_000_000,
            },
        ];
        for e in all {
            let (pt, en) = (e.text(Lang::Pt), e.text(Lang::En));
            assert!(!pt.is_empty() && !en.is_empty() && pt != en, "{e:?}");
        }
    }

    #[test]
    fn the_missing_channel_and_http_texts_in_full() {
        assert_eq!(
            Error::UnityNotPublished.text(Lang::En),
            "The Unity client has not been published yet. Use the main client."
        );
        assert_eq!(
            Error::UnityNotPublished.text(Lang::Pt),
            "O cliente Unity ainda não foi publicado. Use o cliente principal."
        );
        assert_eq!(
            Error::Http(404).text(Lang::En),
            "The update server answered with an error (HTTP 404). Try again in a few minutes."
        );
        assert_eq!(
            Error::Http(503).text(Lang::Pt),
            "O servidor de atualização respondeu com erro (HTTP 503). Tente de novo em alguns minutos."
        );
        // neither blames the player's internet, and neither shows a curl tail
        for e in [Error::UnityNotPublished, Error::Http(404)] {
            for l in [Lang::Pt, Lang::En] {
                let t = e.text(l);
                assert!(!t.contains("curl") && !t.to_lowercase().contains("internet"), "{t}");
            }
        }
        // a transport failure still says so
        assert!(Error::Network("curl 7: x".into()).text(Lang::En).contains("internet"));
        assert_ne!(use_main_client(Lang::Pt), use_main_client(Lang::En));
    }

    #[test]
    fn feed_texts_have_both_languages() {
        for t in [
            FeedText::TabNews,
            FeedText::Loading,
            FeedText::Unavailable,
            FeedText::SavedCopy,
            FeedText::NoNews,
            FeedText::NoChanges,
            FeedText::ReadMore,
        ] {
            assert_ne!(feed_text(t, Lang::Pt), feed_text(t, Lang::En), "{t:?}");
        }
        // "Changelog" is the same word in both
        assert_eq!(feed_text(FeedText::TabChangelog, Lang::Pt), "Changelog");
        assert_eq!(feed_text(FeedText::TabNews, Lang::Pt), "Notícias");
    }

    #[test]
    fn window_texts_have_both_languages() {
        let same = [Ui::Discord, Ui::Site, Ui::Wiki];
        for t in [
            Ui::Ready,
            Ui::Discord,
            Ui::Site,
            Ui::Wiki,
            Ui::Signup,
            Ui::News,
            Ui::NewsSub,
            Ui::Settings,
            Ui::Close,
            Ui::Minimize,
            Ui::InstallFolder,
            Ui::OpenFolder,
            Ui::Verify,
            Ui::VerifyHint,
            Ui::Verifying,
            Ui::ClearCache,
            Ui::CloseOnPlay,
            Ui::Language,
            Ui::Version,
            Ui::Files,
            Ui::UpToDateLine,
            Ui::ReadMore,
            Ui::Back,
            Ui::NoCards,
            Ui::NoSpaceHint,
        ] {
            let (pt, en) = (ui(t, Lang::Pt), ui(t, Lang::En));
            assert!(!pt.is_empty() && !en.is_empty(), "{t:?}");
            assert_eq!(pt == en, same.contains(&t), "{t:?}");
        }
    }

    #[test]
    fn client_choice_texts_have_both_languages() {
        use crate::config::Client;
        assert_ne!(client_label(Lang::Pt), client_label(Lang::En));
        assert_ne!(unity_note(Lang::Pt), unity_note(Lang::En));
        for c in [Client::Main, Client::Unity] {
            assert_ne!(client_name(c, Lang::Pt), client_name(c, Lang::En), "{c:?}");
        }
        assert!(client_name(Client::Unity, Lang::En).contains("beta"));
    }

    #[test]
    fn statuses_differ_by_language() {
        for s in [
            Status::Checking,
            Status::Hashing,
            Status::Verifying,
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
