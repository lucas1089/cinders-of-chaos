//! The card Recompilar engine of Atualizações (O436). Pure parsing and pt-BR wording of `chaos-ctl.sh engine-build status`
//! (the run of windows-package.yml on GitHub), of the refusals of `engine-build start` and `engine-build-token-set`, like
//! android/.../EngineBuildInfo.java. No I/O here. The token never shows here: it goes to `engine-build-token-set` on stdin.
use std::collections::BTreeMap;

/// How long GitHub takes, for the confirmation and the hint.
pub const DURATION: &str =
    "de 20 a 60 minutos (a primeira vez, ou depois de uma mudança grande, pode passar de uma hora)";

/// Seconds between two asks of `engine-build status` while a build is queued or in progress.
pub const POLL_SECS: u64 = 20;

/// The key=value lines of `engine-build status` (the lines after a line that starts with `@` are not read).
#[derive(Clone, Debug, Default)]
pub struct EngineInfo {
    kv: BTreeMap<String, String>,
}

impl EngineInfo {
    pub fn parse(out: &str) -> EngineInfo {
        let mut e = EngineInfo::default();
        for line in out.split('\n') {
            if line.starts_with('@') {
                break;
            }
            let Some(eq) = line.find('=') else { continue };
            if eq == 0 {
                continue;
            }
            e.kv.entry(line[..eq].trim().to_string())
                .or_insert_with(|| line[eq + 1..].trim().to_string());
        }
        e
    }

    /// A value; empty when missing or "-".
    pub fn get(&self, k: &str) -> &str {
        match self.kv.get(k).map(String::as_str) {
            Some("-") | None => "",
            Some(v) => v,
        }
    }

    pub fn valid(&self) -> bool {
        self.kv.contains_key("state")
    }

    pub fn state(&self) -> &str {
        self.get("state")
    }

    /// Queued or in progress: the window keeps asking.
    pub fn running(&self) -> bool {
        matches!(self.state(), "queued" | "in_progress")
    }

    pub fn has_token(&self) -> bool {
        self.get("token") == "yes"
    }

    /// Done, the release has the engine and it is newer than the installed one: Atualizar servidor installs it.
    pub fn newer(&self) -> bool {
        self.state() == "success" && self.get("release_newer") == "yes"
    }

    fn secs(&self) -> u64 {
        self.get("elapsed_s").parse().unwrap_or(0)
    }

    /// One line over the card.
    pub fn headline(&self) -> String {
        let tag = self.get("release_tag");
        match self.state() {
            "none" => "Nenhuma recompilação feita ainda.".into(),
            "queued" => "Na fila do GitHub.".into(),
            "in_progress" => format!("Compilando no GitHub há {}.", elapsed(self.secs())),
            "success" => {
                if self.get("release_newer") == "yes" {
                    format!("Pronto: {tag} tem o engine novo.")
                } else if self.get("release_ready") == "no" {
                    format!("Terminou, mas {tag} ainda não mostra o engine. Atualize o estado em um minuto.")
                } else {
                    format!("Pronto, mas {tag} é a versão que já está instalada.")
                }
            }
            "failure" => {
                if self.get("conclusion") == "cancelled" {
                    "A recompilação foi cancelada no GitHub.".into()
                } else {
                    "A recompilação falhou no GitHub.".into()
                }
            }
            "unknown" => "Não consegui ler o GitHub.".into(),
            _ => String::new(),
        }
    }

    /// The lines under the headline: run, step, result, what to do next.
    pub fn lines(&self) -> Vec<String> {
        let mut b: Vec<String> = Vec::new();
        if !self.get("run_number").is_empty() {
            let mut l = format!("Rodada {}", self.get("run_number"));
            if !self.get("commit").is_empty() {
                l.push_str(&format!(", código {}", self.get("commit")));
            }
            let cb = self.get("client_build");
            if !cb.is_empty() && cb != "unknown" {
                l.push_str(&format!(", client build {cb}"));
            }
            b.push(l);
        }
        if self.running() {
            if !self.get("job").is_empty() {
                let mut l = format!("Etapa: {}", self.get("job"));
                if !self.get("step").is_empty() {
                    l.push_str(&format!(" > {}", self.get("step")));
                }
                b.push(l);
            }
            if !self.get("jobs_done").is_empty() {
                b.push(format!("Etapas prontas: {}", self.get("jobs_done")));
            }
            b.push("O jogo segue no ar. Pode fechar o app; a compilação continua no GitHub.".into());
        } else if self.state() == "failure" {
            if !self.get("failed_job").is_empty() {
                let mut l = format!("Parou em {}", self.get("failed_job"));
                if !self.get("failed_step").is_empty() {
                    l.push_str(&format!(" > {}", self.get("failed_step")));
                }
                b.push(l);
            }
            b.push(
                "Nada foi trocado no servidor. Veja os passos em Ver passos; o log completo está na página da rodada no GitHub."
                    .into(),
            );
        } else if self.state() == "success" {
            if self.secs() > 0 {
                b.push(format!("Levou {}.", elapsed(self.secs())));
            }
            if self.newer() {
                b.push(
                    "Próximo passo: em Atualizar servidor, clique em Verificar e depois em Aplicar e reiniciar. \
                     Ele baixa o engine novo, instala e confere se o servidor ligou."
                        .into(),
                );
            }
        }
        let inst = self.get("installed_release");
        if !inst.is_empty() && self.state() != "unknown" {
            b.push(format!(
                "Instalado no servidor: {}",
                if inst == "unknown" {
                    "desconhecido".to_string()
                } else {
                    format!("winpkg-{inst}")
                }
            ));
        }
        if !self.has_token() {
            b.push("Sem token do GitHub: use Definir token do GitHub antes de recompilar.".into());
        }
        b
    }
}

/// "37 min", "1 h 05 min", "40 s".
pub fn elapsed(secs: u64) -> String {
    if secs < 60 {
        return format!("{secs} s");
    }
    let min = secs / 60;
    if min < 60 {
        return format!("{min} min");
    }
    format!("{} h {:02} min", min / 60, min % 60)
}

/// The text of the confirmation before a build starts.
pub fn confirm_text() -> String {
    format!(
        "O GitHub compila o engine do servidor com todos os patches do código novo. Leva {DURATION}. \
         O jogo segue no ar e nada é trocado no servidor agora. Quando terminar, use Atualizar servidor para instalar."
    )
}

/// A refusal of chaos-ctl.sh (its "word: text" error line) in Portuguese; empty when the text is not one of ours.
pub fn refusal(out: &str) -> &'static str {
    const WORDS: [(&str, &str); 12] = [
        ("token-missing", "Falta o token do GitHub. Use Definir token do GitHub com um token só deste repositório, com Actions leitura e escrita."),
        ("token-refused", "O GitHub recusou o token (401). Ele pode ter vencido ou sido apagado: defina um novo."),
        ("no-access", "O token não alcança o repositório ou não tem Actions leitura e escrita. Crie outro com essas permissões."),
        ("build-running", "Já há uma recompilação em andamento. Espere ela terminar."),
        ("client-changed", "O programa do client mudou desde o client publicado: o mesmo número de client apontaria para dois executáveis diferentes. Suba o número do client (e coloque o novo em clientGuardBuilds) antes de recompilar; veja docs/ADMIN_APP.md."),
        ("client-build-backwards", "O número do client não pode ser menor que o do client publicado."),
        ("client-build-unknown", "Não há update de client publicado para tirar o número do client. Dê o número na linha de comando."),
        ("client-check-failed", "Não consegui comparar o programa do client com o publicado. Rode Atualizar servidor uma vez e tente de novo."),
        ("fetch-failed", "A VPS não conseguiu buscar o código no GitHub."),
        ("workflow-refused", "O GitHub recusou o pedido (422): a branch não tem o workflow manual de pacote."),
        ("dispatch-failed", "O GitHub não aceitou o pedido. Tente de novo em alguns minutos."),
        ("github-unreachable", "O GitHub não respondeu. Tente de novo em alguns minutos."),
    ];
    for (w, text) in WORDS {
        if out.contains(&format!("{w}:")) {
            return text;
        }
    }
    ""
}

/// The same shape check of the GitHub token as `engine-build-token-set`; empty is fine (it removes the token).
pub fn token_ok(t: &str) -> bool {
    let tail = |rest: &str, lo: usize, hi: usize, us: bool| {
        (lo..=hi).contains(&rest.len()) && rest.bytes().all(|b| b.is_ascii_alphanumeric() || (us && b == b'_'))
    };
    if let Some(rest) = t.strip_prefix("github_pat_") {
        return tail(rest, 20, 250, true);
    }
    for p in ["ghp_", "gho_", "ghu_", "ghs_", "ghr_"] {
        if let Some(rest) = t.strip_prefix(p) {
            return tail(rest, 30, 250, false);
        }
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn states_in_portuguese() {
        let none =
            EngineInfo::parse("token=yes\nstate=none\nclient_build=30\ninstalled_release=100\nrelease_newer=no\n");
        assert!(none.valid() && !none.running() && none.has_token() && !none.newer());
        assert_eq!(none.headline(), "Nenhuma recompilação feita ainda.");
        let q = EngineInfo::parse("token=yes\nstate=queued\nrun_number=101\n");
        assert!(q.running());
        assert_eq!(q.headline(), "Na fila do GitHub.");
        let run = EngineInfo::parse(
            "token=yes\nstate=in_progress\nrun_number=101\ncommit=a1b2c3d\nclient_build=30\nelapsed_s=2232\njob=engine-linux\n\
             step=Build the engine\njobs_done=1/3\ninstalled_release=100\nrelease_newer=no\n",
        );
        assert!(run.running());
        assert_eq!(run.headline(), "Compilando no GitHub há 37 min.");
        let l = run.lines();
        assert_eq!(l[0], "Rodada 101, código a1b2c3d, client build 30");
        assert!(l.contains(&"Etapa: engine-linux > Build the engine".to_string()));
        assert!(l.contains(&"Etapas prontas: 1/3".to_string()));
        assert!(l.iter().any(|x| x.contains("O jogo segue no ar")));
    }

    #[test]
    fn success_points_to_the_update() {
        let ok = EngineInfo::parse(
            "token=yes\nstate=success\nrun_number=101\nelapsed_s=3900\nrelease_tag=winpkg-101\nrelease_ready=yes\n\
             release_newer=yes\ninstalled_release=100\n",
        );
        assert!(ok.newer() && !ok.running());
        assert_eq!(ok.headline(), "Pronto: winpkg-101 tem o engine novo.");
        let l = ok.lines();
        assert!(l.contains(&"Levou 1 h 05 min.".to_string()));
        assert!(l.iter().any(|x| x.contains("Atualizar servidor")));
        assert!(l.contains(&"Instalado no servidor: winpkg-100".to_string()));
        let same = EngineInfo::parse(
            "token=yes\nstate=success\nrelease_tag=winpkg-100\nrelease_ready=yes\nrelease_newer=no\n",
        );
        assert!(!same.newer());
        assert_eq!(
            same.headline(),
            "Pronto, mas winpkg-100 é a versão que já está instalada."
        );
        let wait =
            EngineInfo::parse("token=yes\nstate=success\nrelease_tag=winpkg-101\nrelease_ready=no\nrelease_newer=no\n");
        assert!(wait.headline().contains("ainda não mostra o engine"));
    }

    #[test]
    fn failures_name_the_step() {
        let f = EngineInfo::parse(
            "token=yes\nstate=failure\nconclusion=failure\nfailed_job=engine-linux\nfailed_step=Compile the engine\nrelease_newer=no\n",
        );
        assert_eq!(f.headline(), "A recompilação falhou no GitHub.");
        let l = f.lines();
        assert!(l.contains(&"Parou em engine-linux > Compile the engine".to_string()));
        assert!(l.iter().any(|x| x.starts_with("Nada foi trocado")));
        let c = EngineInfo::parse("state=failure\nconclusion=cancelled\ntoken=yes\n");
        assert_eq!(c.headline(), "A recompilação foi cancelada no GitHub.");
        let no = EngineInfo::parse("token=no\nstate=none\n");
        assert!(no.lines().iter().any(|x| x.contains("Definir token do GitHub")));
    }

    #[test]
    fn parsing_edges() {
        let e = EngineInfo::parse("state=failure\nfailed_job=-\nstate=success\n@jobs\nfailed_step=x\n");
        assert_eq!(e.state(), "failure", "the first value wins");
        assert!(e.get("failed_job").is_empty(), "a dash is nothing");
        assert!(e.get("failed_step").is_empty(), "nothing after an @ line");
        assert!(!EngineInfo::parse("chaos-ctl: token-missing: no token").valid());
        assert!(!EngineInfo::parse("").valid());
        assert_eq!(elapsed(40), "40 s");
        assert_eq!(elapsed(125), "2 min");
        assert_eq!(elapsed(3600), "1 h 00 min");
    }

    #[test]
    fn words_and_token_shape() {
        assert!(confirm_text().contains("20 a 60 minutos") && confirm_text().contains("Atualizar servidor"));
        for w in [
            "token-missing",
            "token-refused",
            "no-access",
            "build-running",
            "client-changed",
            "client-build-backwards",
            "client-build-unknown",
            "client-check-failed",
            "fetch-failed",
            "workflow-refused",
            "dispatch-failed",
            "github-unreachable",
        ] {
            assert!(!refusal(&format!("chaos-ctl: {w}: x")).is_empty(), "{w}");
        }
        assert!(refusal("chaos-ctl: something else").is_empty());
        assert!(refusal("chaos-ctl: client-changed: x").contains("clientGuardBuilds"));
        let tok = format!("github_pat_{}", "aB1_".repeat(12));
        assert!(token_ok(&tok));
        assert!(token_ok(&format!("ghp_{}", "a1B2c3D4e5".repeat(4))));
        for bad in [
            String::new(),
            "github_pat_short".to_string(),
            format!("{tok}$(id)"),
            format!("{tok}\nX=1"),
            format!(" {tok}"),
            "ghp_short".to_string(),
            format!("github_pat_{}", "x".repeat(300)),
            "not a token".to_string(),
        ] {
            assert!(!token_ok(&bad), "{bad:?}");
        }
    }
}
