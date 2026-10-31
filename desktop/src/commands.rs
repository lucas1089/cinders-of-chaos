//! The one table of commands: tabs, groups, buttons. Mirrors the Android admin app (android/.../CommandsTab.java,
//! PanelTab.java, LogsTab.java). tools/ci/check_desktop_commands.py checks that both name the same chaos-ctl.sh commands.
use crate::ssh::sq;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Tab {
    Panel,
    Commands,
    Logs,
}

impl Tab {
    pub const ALL: [Tab; 3] = [Tab::Panel, Tab::Commands, Tab::Logs];
    pub fn title(self) -> &'static str {
        match self {
            Tab::Panel => "Painel",
            Tab::Commands => "Comandos",
            Tab::Logs => "Logs",
        }
    }
}

/// When the change reaches the running game.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Live {
    /// Read only, or the effect is immediate (a message, a kick, a unit start).
    Now,
    /// Written to a file the scripts read at start. Needs a restart, or "Apply live": the game panel's `reload`
    /// action for this system (scripts, config, ...) right after the command.
    Reload(&'static str),
    /// Applies only at the next server restart. No live path yet (see README "Gaps").
    Restart,
    /// The command itself restarts the server (players are disconnected).
    Restarts,
    /// Applies at the next install or update, no restart needed.
    NextInstall,
}

impl Live {
    /// The short tag beside the button (pt-BR, like the rest of the window). It says when the change takes effect; it
    /// is not a state of the system (the owner, 2026-10-31, read the old "live" as a status light).
    pub fn label(self) -> &'static str {
        match self {
            Live::Now => "na hora",
            Live::Reload(_) => "com Apply live",
            Live::Restart => "após reiniciar",
            Live::Restarts => "reinicia o servidor",
            Live::NextInstall => "na próxima instalação",
        }
    }

    /// The tag's tooltip: the same in a sentence.
    pub fn hint(self) -> &'static str {
        match self {
            Live::Now => "Faz efeito na hora (ou só lê).",
            Live::Reload(_) => "Grava o arquivo; o botão \"+ Apply live\" recarrega no jogo sem reiniciar.",
            Live::Restart => "Grava o arquivo; vale no próximo reinício do servidor.",
            Live::Restarts => "O comando reinicia o servidor: os jogadores caem.",
            Live::NextInstall => "Vale na próxima instalação ou atualização, sem reiniciar.",
        }
    }

    /// The tag's dot colour (r, g, b): green at once, yellow with Apply live, orange after a restart, red when it
    /// restarts the server, grey at the next install.
    pub fn rgb(self) -> (u8, u8, u8) {
        match self {
            Live::Now => (96, 196, 110),
            Live::Reload(_) => (228, 196, 72),
            Live::Restart => (232, 140, 60),
            Live::Restarts => (220, 72, 60),
            Live::NextInstall => (150, 150, 150),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    Text,
    Int(i64, i64),
    /// Goes to the command's stdin, never on a command line or in a log.
    Secret,
    Choice(&'static [&'static str]),
}

#[derive(Clone, Copy, Debug)]
pub struct Param {
    pub name: &'static str,
    pub label: &'static str,
    pub kind: Kind,
    pub default: &'static str,
}

pub const fn text(name: &'static str, label: &'static str) -> Param {
    Param {
        name,
        label,
        kind: Kind::Text,
        default: "",
    }
}
pub const fn int(name: &'static str, label: &'static str, lo: i64, hi: i64, default: &'static str) -> Param {
    Param {
        name,
        label,
        kind: Kind::Int(lo, hi),
        default,
    }
}
pub const fn secret(name: &'static str, label: &'static str) -> Param {
    Param {
        name,
        label,
        kind: Kind::Secret,
        default: "",
    }
}
pub const fn choice(name: &'static str, label: &'static str, options: &'static [&'static str]) -> Param {
    Param {
        name,
        label,
        kind: Kind::Choice(options),
        default: options[0],
    }
}

#[derive(Clone, Copy, Debug)]
pub struct Action {
    pub tab: Tab,
    pub group: &'static str,
    pub label: &'static str,
    /// chaos-ctl.sh arguments; `{name}` is replaced by the quoted value of the parameter.
    pub template: &'static str,
    pub params: &'static [Param],
    /// Ask first (the Android app asks for the same ones).
    pub confirm: bool,
    pub live: Live,
    pub timeout: u64,
    pub hint: &'static str,
}

const fn act(tab: Tab, group: &'static str, label: &'static str, template: &'static str) -> Action {
    Action {
        tab,
        group,
        label,
        template,
        params: &[],
        confirm: false,
        live: Live::Now,
        timeout: 60,
        hint: "",
    }
}
impl Action {
    const fn p(mut self, params: &'static [Param]) -> Self {
        self.params = params;
        self
    }
    const fn ask(mut self) -> Self {
        self.confirm = true;
        self
    }
    const fn live(mut self, l: Live) -> Self {
        self.live = l;
        self
    }
    const fn t(mut self, secs: u64) -> Self {
        self.timeout = secs;
        self
    }
    const fn h(mut self, hint: &'static str) -> Self {
        self.hint = hint;
        self
    }

    /// The first word of the template: the chaos-ctl.sh command.
    pub fn ctl_word(&self) -> &'static str {
        self.template.split_whitespace().next().unwrap_or("")
    }
}

use Tab::{Commands as C, Logs as L, Panel as P};

const TEXT_P: &[Param] = &[text("text", "Mensagem")];
const NAME_P: &[Param] = &[text("name", "Nome do personagem")];
const GM_P: &[Param] = &[
    text("name", "Nome do personagem"),
    int("g", "Grupo (1 jogador, 4 GM, 6 God)", 1, 6, "6"),
];
const TAG_P: &[Param] = &[text("tag", "Tag da release (ex.: winpkg-123)")];
const APK_P: &[Param] = &[text("tag", "Tag da release do app (ex.: android-31)")];
const N_P: &[Param] = &[int("n", "Linhas", 1, 500, "100")];
const SECS_P: &[Param] = &[int("secs", "Segundos de aviso", 30, 900, "300")];
const MINS_P: &[Param] = &[int("mins", "Minutos", 1, 60, "5")];
const XP_P: &[Param] = &[int("n", "Multiplicador (1 a 100)", 1, 100, "1")];
const PAIR_P: &[Param] = &[int("n", "Par do cliente", 1, 9999, "1")];
const TESTERS_P: &[Param] = &[int("n", "Bots", 1, 150, "100"), int("m", "Minutos", 1, 1440, "60")];
const ACC_P: &[Param] = &[text("name", "Conta"), secret("password", "Senha (6 a 64 caracteres)")];
const UNIT_P: &[Param] = &[text("unit", "Unidade (ex.: chaos-helpai)")];
const UNIT_ACT_P: &[Param] = &[
    text("unit", "Unidade (ex.: chaos-helpai)"),
    choice("verb", "Ação", &["start", "stop", "restart"]),
];
const DISCORD_P: &[Param] = &[
    choice(
        "channel",
        "Canal",
        &[
            "default", "records", "bosses", "players", "announce", "status", "bazaar", "drops",
        ],
    ),
    secret("url", "URL do webhook (vazio remove)"),
];
const BOT_SET_P: &[Param] = &[
    choice(
        "key",
        "Ajuste",
        &[
            "DISCORD_TOKEN",
            "ANTHROPIC_API_KEY",
            "DISCORD_OWNER_ID",
            "DISCORD_BUGS_CHANNEL_ID",
            "DISCORD_PATCH_CHANNEL_ID",
            "DISCORD_GUILD_ID",
            "DISCORD_ADMIN_ROLE_ID",
            "DISCORD_BOT_MODEL",
        ],
    ),
    secret("value", "Valor (vazio remove)"),
];
const FB_CLOSE_P: &[Param] = &[
    int("id", "Número do relatório", 1, 999_999_999, "1"),
    text("note", "Nota (200 caracteres)"),
];

/// The table. One line per button. Keep one `act(` per line: the CI check reads it.
#[rustfmt::skip]
pub static ACTIONS: &[Action] = &[
    // ---- Painel: servidor
    act(P, "Servidor", "Estado", "status"),
    act(P, "Servidor", "Ligar", "start").t(120),
    act(P, "Servidor", "Desligar", "stop").ask().t(240).h("Os jogadores são desconectados; o jogo salva antes."),
    act(P, "Servidor", "Salvar", "save"),
    act(P, "Servidor", "Reiniciar agora", "restart").ask().live(Live::Restarts).t(240),
    act(P, "Servidor", "Reiniciar com aviso", "restart {secs}").p(SECS_P).ask().live(Live::Restarts).t(60).h("Os jogadores são avisados; roda em segundo plano."),
    act(P, "Servidor", "Backup", "backup").t(600),
    act(P, "Servidor", "Saúde e espaço", "health").t(120),
    act(P, "Jogadores", "Quem está online", "players"),
    act(P, "Jogadores", "Classes", "vocations"),
    // ---- Painel: atualizar servidor
    act(P, "Atualizar servidor", "Verificar", "update-check").t(180),
    act(P, "Atualizar servidor", "Aplicar e reiniciar", "update-apply").ask().live(Live::Restarts).t(60).h("Roda em segundo plano; acompanhe em Logs > Updates."),
    act(P, "Atualizar servidor", "Voltar à versão anterior", "update-rollback").ask().live(Live::Restarts).t(60),
    act(P, "Atualizar servidor", "Estado da última atualização", "update-status"),
    // ---- Painel: métricas e relatos
    act(P, "Métricas dos jogadores", "Ver métricas", "metrics").t(90),
    act(P, "Bugs e sugestões", "Abertos (30 dias)", "feedback").t(90),
    act(P, "Bugs e sugestões", "Todos (inclui fechados)", "feedback --all").t(90),
    act(P, "Bugs e sugestões", "Fechar relatório", "feedback-close {id} {note}").p(FB_CLOSE_P).ask(),
    // ---- Comandos: ações rápidas
    act(C, "Ações rápidas", "Aviso para todos", "broadcast {text}").p(TEXT_P).t(20),
    act(C, "Ações rápidas", "Expulsar", "kick {name}").p(NAME_P).ask().t(20),
    act(C, "Ações rápidas", "Abrir login", "open").t(20),
    act(C, "Ações rápidas", "Fechar login", "close").ask().t(20),
    act(C, "Ações rápidas", "Atualizar para uma versão", "update {tag} {mode}").p(&[text("tag", "Tag da release (ex.: winpkg-123)"), choice("mode", "Quando", &["now", "at-save"])]).ask().live(Live::Restarts).h("Layout padrão com repositório."),
    act(C, "Ações rápidas", "Voltar versão", "rollback now").ask().live(Live::Restarts).t(30),
    // ---- Comandos: taxa de XP
    act(C, "Taxa de XP", "Ver", "xp-rate show").t(30),
    act(C, "Taxa de XP", "Definir (vale no próximo reinício)", "xp-rate set {n}").p(XP_P).live(Live::Restart).t(30),
    act(C, "Taxa de XP", "Definir e reiniciar", "xp-rate set {n} restart").p(XP_P).ask().live(Live::Restarts).t(240),
    act(C, "Taxa de XP", "Voltar ao padrão", "xp-rate reset").live(Live::Restart).t(30),
    // ---- Comandos: par do cliente
    act(C, "Par do cliente", "Ver", "client-pair show").t(30),
    act(C, "Par do cliente", "Definir", "client-pair set {n}").p(PAIR_P).ask().live(Live::NextInstall).t(30),
    // ---- Comandos: modo beta
    act(C, "Modo beta", "Ver", "beta-mode status").t(30),
    act(C, "Modo beta", "Ligar", "beta-mode on").live(Live::Reload("scripts")).t(30).h("Apply live recarrega os scripts."),
    act(C, "Modo beta", "Desligar", "beta-mode off").live(Live::Reload("scripts")).t(30).h("Apply live recarrega os scripts."),
    act(C, "Modo beta", "Ligar e reiniciar", "beta-mode on restart").ask().live(Live::Restarts).t(240),
    act(C, "Modo beta", "Desligar e reiniciar", "beta-mode off restart").ask().live(Live::Restarts).t(240),
    // ---- Comandos: recarregar um arquivo (o cartão com a escolha e o botão está no Painel do jogo; reload-file ACTOR NOME)
    act(C, "Recarregar um arquivo", "Listar tabelas de configuração", "reload-files").t(30).h("Recarregar uma delas: Painel do jogo > Recarregar um arquivo."),
    // ---- Comandos: serviços da tela de login
    act(C, "Serviços de login", "Ver", "clientservices-impl status").t(30),
    act(C, "Serviços de login", "Rust ligado", "clientservices-impl rust").ask().t(900).h("Compila com cargo na VPS; pode levar minutos."),
    act(C, "Serviços de login", "Python ligado", "clientservices-impl python").t(60),
    // ---- Comandos: contas
    act(C, "Contas", "Criar conta", "account-create {name}").p(ACC_P).t(60),
    act(C, "Contas", "Trocar senha", "account-password {name}").p(ACC_P).ask().t(60),
    act(C, "Contas", "Direitos de staff", "gm-set {name} {g}").p(GM_P).ask().t(60).h("O personagem precisa estar offline. 4 = GM, 6 = God; 1 tira os direitos."),
    // ---- Comandos: Discord
    act(C, "Discord", "Estado", "discord-status").t(60),
    act(C, "Discord", "Guardar webhook", "discord-set {channel}").p(DISCORD_P).t(60),
    act(C, "Discord", "Ligar avisos", "discord-enable").t(90),
    act(C, "Discord", "Desligar avisos", "discord-disable").t(90),
    act(C, "Discord", "Testar todos", "discord-test all").t(90),
    // ---- Comandos: bot do Discord (bugs e patch notes)
    act(C, "Bot do Discord", "Estado", "discord-bot status").t(40),
    act(C, "Bot do Discord", "Instalar ou atualizar", "discord-bot install").ask().t(600).h("Cria o usuário chaosbot e o virtualenv; alguns minutos. De novo atualiza o código."),
    act(C, "Bot do Discord", "Guardar ajuste", "discord-bot set {key}").p(BOT_SET_P).t(40).h("Token e chave vão pelo stdin, só ficam na VPS."),
    act(C, "Bot do Discord", "Iniciar", "discord-bot start").t(60),
    act(C, "Bot do Discord", "Reiniciar", "discord-bot restart").t(60),
    act(C, "Bot do Discord", "Parar", "discord-bot stop").ask().t(60),
    act(C, "Bot do Discord", "Logs", "discord-bot logs 80").t(40),
    act(C, "Bot do Discord", "Levar patch notes ao jogo", "discord-bot patchnotes").t(60),
    // ---- Comandos: saúde e espaço
    act(C, "Saúde e espaço", "Ver sobras a limpar", "cleanup").t(120),
    act(C, "Saúde e espaço", "Limpar sobras", "cleanup --yes").ask().t(120),
    act(C, "Saúde e espaço", "Backups", "backups"),
    // ---- Comandos: servidor como usuário chaos
    act(C, "Servidor como usuário chaos", "Ver", "server-user status").t(60),
    act(C, "Servidor como usuário chaos", "Corrigir", "server-user fix").ask().t(180),
    act(C, "Servidor como usuário chaos", "Corrigir e reiniciar", "server-user fix --restart {secs}").p(SECS_P).ask().live(Live::Restarts).t(180),
    act(C, "Servidor como usuário chaos", "Desfazer", "server-user rollback").ask().t(60),
    act(C, "Servidor como usuário chaos", "Log do reinício", "server-user log 60").t(30),
    // ---- Comandos: testers
    act(C, "Testers", "Iniciar (reinicia o servidor)", "testers start {n} {m} --restart 300").p(TESTERS_P).ask().live(Live::Restarts).t(180),
    act(C, "Testers", "Iniciar com árvore de talentos", "testers start {n} {m} --keystones --restart 300").p(TESTERS_P).ask().live(Live::Restarts).t(180),
    act(C, "Testers", "Iniciar com checagem de sistemas", "testers start {n} {m} --checks --restart 300").p(TESTERS_P).ask().live(Live::Restarts).t(180),
    act(C, "Testers", "Parar", "testers stop").ask().t(60),
    act(C, "Testers", "Estado", "testers status").t(60),
    act(C, "Testers", "Relatório", "testers report").t(120),
    act(C, "Testers", "Log das ações", "testers log 400").t(60),
    act(C, "Testers", "Apagar testers", "testers cleanup --yes").ask().t(240),
    // ---- Comandos: site e update do client
    act(C, "Site e update do client", "Reinstalar o site", "site-install").ask().t(30),
    act(C, "Site e update do client", "Publicar update do client", "publish-update {tag}").p(TAG_P).ask().t(30),
    act(C, "Site e update do client", "Publicar app Android", "publish-apk {tag}").p(APK_P).ask().t(30),
    act(C, "Site e update do client", "Tirar o app Android do update", "publish-apk --remove").ask().t(30),
    act(C, "Site e update do client", "Trocar os downloads", "update-downloads").ask().t(30),
    act(C, "Mapa", "Publicar áreas da caixa de entrada", "areas-publish").t(120),
    act(C, "Mapa", "Novo endereço das áreas", "areas-publish --rotate").ask().t(120),
    // ---- Comandos: a máquina
    act(C, "VPS", "Informações", "vps info").t(60),
    act(C, "VPS", "Atualizar o sistema", "vps upgrade").ask().t(30),
    act(C, "VPS", "Log da atualização", "vps upgrade-log 200").t(30),
    act(C, "VPS", "Reiniciar a VPS", "vps reboot {mins}").p(MINS_P).ask().t(30),
    act(C, "VPS", "Cancelar reinício", "vps reboot-cancel").t(30),
    act(C, "Unidades chaos-*", "Listar", "services").t(30),
    act(C, "Unidades chaos-*", "Ligar, desligar ou reiniciar", "service {unit} {verb}").p(UNIT_ACT_P).ask().t(240),
    // ---- Logs
    act(L, "Console", "Últimas linhas", "logs {n}").p(N_P).t(40),
    act(L, "Erros", "Desde o último início", "errors {n}").p(N_P).t(40),
    act(L, "Erros", "Incluir inícios anteriores", "errors {n} all").p(N_P).t(40),
    act(L, "Erros", "Limpar lista", "errors clear").ask().t(40).h("Só põe uma marca no log; nada é apagado."),
    act(L, "Updates", "Log do update do servidor", "update-log {n}").p(N_P).t(40),
    act(L, "Updates", "Log da publicação do client", "publish-log {n}").p(N_P).t(40),
    act(L, "Updates", "Log da instalação do site", "site-log {n}").p(N_P).t(40),
    act(L, "GM", "Registro do painel de admin", "gm-logs {n}").p(N_P).t(60),
    act(L, "Unidades", "Log de uma unidade", "service-log {unit} 200").p(UNIT_P).t(40),
    act(L, "Par do cliente", "Estado do par (spectate)", "spectate-pair status").t(40),
];

/// Fills the template: `{name}` becomes the single-quoted value. Secret parameters are not in templates; they are
/// returned as the stdin text. Errors name the parameter.
pub fn build(action: &Action, values: &[String]) -> Result<(String, Option<String>), String> {
    if values.len() != action.params.len() {
        return Err("wrong number of values".into());
    }
    let mut line = action.template.to_string();
    let mut stdin = None;
    for (p, v) in action.params.iter().zip(values) {
        let v = v.trim();
        match p.kind {
            Kind::Secret => {
                if v.is_empty() && p.name == "password" {
                    return Err(format!("{}: obrigatório", p.label));
                }
                stdin = Some(format!("{v}\n"));
                continue;
            }
            Kind::Int(lo, hi) => {
                let n: i64 = v
                    .parse()
                    .map_err(|_| format!("{}: precisa ser um número inteiro", p.label))?;
                if n < lo || n > hi {
                    return Err(format!("{}: de {lo} a {hi}", p.label));
                }
            }
            Kind::Choice(opts) => {
                if !opts.contains(&v) {
                    return Err(format!("{}: valor inválido", p.label));
                }
            }
            Kind::Text => {
                if v.is_empty() && p.name != "note" {
                    return Err(format!("{}: obrigatório", p.label));
                }
                if v.chars().any(|c| c.is_control()) {
                    return Err(format!("{}: sem caracteres de controle", p.label));
                }
            }
        }
        line = line.replace(&format!("{{{}}}", p.name), &sq(v));
    }
    Ok((line.trim().to_string(), stdin))
}

/// The game panel's reload action as chaos-ctl.sh arguments (Apply live).
pub fn reload_args(actor: &str, system: &str) -> String {
    format!(
        "panel {} reload {}",
        sq(actor),
        sq(&format!("{{\"system\":\"{system}\"}}"))
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashSet;

    #[test]
    fn live_tags_differ() {
        let all = [
            Live::Now,
            Live::Reload("scripts"),
            Live::Restart,
            Live::Restarts,
            Live::NextInstall,
        ];
        for (i, a) in all.iter().enumerate() {
            assert!(!a.label().is_empty() && !a.hint().is_empty());
            for b in &all[i + 1..] {
                assert_ne!(a.label(), b.label());
                assert_ne!(a.rgb(), b.rgb());
            }
        }
    }

    #[test]
    fn placeholders_match_params() {
        for a in ACTIONS {
            let mut rest = a.template;
            let mut found = Vec::new();
            while let Some(i) = rest.find('{') {
                let j = rest[i..].find('}').expect("closed brace") + i;
                found.push(&rest[i + 1..j]);
                rest = &rest[j + 1..];
            }
            let wanted: Vec<&str> = a
                .params
                .iter()
                .filter(|p| p.kind != Kind::Secret)
                .map(|p| p.name)
                .collect();
            assert_eq!(found.len(), wanted.len(), "{}", a.template);
            for w in wanted {
                assert!(found.contains(&w), "{} lacks {{{w}}}", a.template);
            }
        }
    }

    #[test]
    fn labels_unique_per_group_and_words_known() {
        let mut seen = HashSet::new();
        for a in ACTIONS {
            assert!(
                seen.insert((a.tab as u8, a.group, a.label)),
                "duplicate {} / {}",
                a.group,
                a.label
            );
            assert!(!a.ctl_word().is_empty() && !a.ctl_word().starts_with('{'));
            assert!(a.timeout >= 20);
        }
        assert!(ACTIONS.len() > 70);
    }

    #[test]
    fn dangerous_ones_ask() {
        for t in [
            "stop",
            "restart",
            "update-apply",
            "update-rollback",
            "cleanup --yes",
            "testers stop",
            "vps reboot {mins}",
        ] {
            let a = ACTIONS
                .iter()
                .find(|a| a.template == t)
                .unwrap_or_else(|| panic!("{t}"));
            assert!(a.confirm, "{t}");
        }
    }

    #[test]
    fn build_quotes_and_checks() {
        let a = ACTIONS.iter().find(|a| a.template == "broadcast {text}").unwrap();
        let (l, s) = build(a, &["it's $(x)".into()]).unwrap();
        assert_eq!(l, "broadcast 'it'\\''s $(x)'");
        assert!(s.is_none());
        assert!(build(a, &["".into()]).is_err());
        let x = ACTIONS.iter().find(|a| a.template == "xp-rate set {n}").unwrap();
        assert_eq!(build(x, &["10".into()]).unwrap().0, "xp-rate set '10'");
        assert!(build(x, &["101".into()]).is_err());
        assert!(build(x, &["a".into()]).is_err());
    }

    #[test]
    fn secrets_go_to_stdin() {
        let a = ACTIONS.iter().find(|a| a.template == "account-create {name}").unwrap();
        let (l, s) = build(a, &["bob".into(), "hunter22".into()]).unwrap();
        assert_eq!(l, "account-create 'bob'");
        assert_eq!(s.as_deref(), Some("hunter22\n"));
        assert!(!l.contains("hunter22"));
    }

    #[test]
    fn reload_line() {
        assert_eq!(
            reload_args("Admin One", "scripts"),
            "panel 'Admin One' reload '{\"system\":\"scripts\"}'"
        );
    }

    #[test]
    fn live_actions_name_a_known_reload_system() {
        let known = [
            "talkactions",
            "scripts",
            "monsters",
            "npcs",
            "config",
            "actions",
            "movements",
            "creaturescripts",
            "globalevents",
            "spells",
            "weapons",
            "items",
            "quests",
            "raids",
            "mounts",
            "chat",
            "events",
            "global",
            "all",
        ];
        for a in ACTIONS {
            if let Live::Reload(s) = a.live {
                assert!(known.contains(&s), "{s}");
            }
        }
    }
}
