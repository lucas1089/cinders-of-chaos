//! The one table of commands: categories (the sidebar), groups (titled cards), buttons. Mirrors the Android admin
//! app (android/.../CommandsTab.java, PanelTab.java, LogsTab.java). tools/ci/check_desktop_commands.py checks that
//! both name the same chaos-ctl.sh commands.
use crate::ssh::sq;

/// A category of the sidebar (O383). Most hold groups of the table; Ao vivo and Config are pages only, Painel,
/// Jogadores, Painel do jogo and Logs add cards of their own to their groups.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Section {
    Panel,
    LiveView,
    Players,
    Game,
    GamePanel,
    Updates,
    Discord,
    Testers,
    Machine,
    Logs,
    Settings,
}

impl Section {
    /// Sidebar order.
    pub const ALL: [Section; 11] = [
        Section::Panel,
        Section::LiveView,
        Section::Players,
        Section::Game,
        Section::GamePanel,
        Section::Updates,
        Section::Discord,
        Section::Testers,
        Section::Machine,
        Section::Logs,
        Section::Settings,
    ];

    pub fn title(self) -> &'static str {
        match self {
            Section::Panel => "Painel",
            Section::LiveView => "Ao vivo",
            Section::Players => "Jogadores",
            Section::Game => "Ajustes do jogo",
            Section::GamePanel => "Painel do jogo",
            Section::Updates => "Atualizações",
            Section::Discord => "Discord",
            Section::Testers => "Testers",
            Section::Machine => "VPS e manutenção",
            Section::Logs => "Logs",
            Section::Settings => "Config",
        }
    }

    /// Stable name in the settings file (`last_section`): never shown, never translated.
    pub fn key(self) -> &'static str {
        match self {
            Section::Panel => "panel",
            Section::LiveView => "live",
            Section::Players => "players",
            Section::Game => "game",
            Section::GamePanel => "game-panel",
            Section::Updates => "updates",
            Section::Discord => "discord",
            Section::Testers => "testers",
            Section::Machine => "machine",
            Section::Logs => "logs",
            Section::Settings => "settings",
        }
    }

    pub fn from_key(key: &str) -> Option<Section> {
        Section::ALL.into_iter().find(|s| s.key() == key)
    }

    /// What the category shows besides its buttons (cards, pages), for the search. Empty: buttons only.
    pub fn page_words(self) -> &'static str {
        match self {
            Section::Panel => "estado do servidor no ar memória disco carga último backup erros jogadores online",
            Section::LiveView => "ao vivo tempo real console do jogo log atualizar a cada pausar filtrar seguir",
            Section::Players => {
                "métricas churn faixa de nível mortes por área monstro primeira sessão retorno \
                 saúde do jogo online por hora hunts mais usadas menos usadas ouro economia \
                 relatório de equilíbrio balanceamento classes season sugestões"
            }
            Section::GamePanel => "catálogo painel de admin ban item spawn recarregar arquivo tabela config lua",
            Section::Logs => "terminal na vps qualquer comando shell",
            Section::Settings => {
                "configurações host endereço porta usuário ssh chave privada gerar chave comando de instalação \
                 caminho chaos-ctl personagem admin versão nova atualizar o app"
            }
            _ => "",
        }
    }
}

/// When the change reaches the running game.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Live {
    /// Read only, or the effect is immediate (a message, a kick, a unit start).
    Now,
    /// Written to a file the scripts read at start. Needs a restart, or "e aplicar agora": the game panel's `reload`
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
            Live::Reload(_) => "ao aplicar agora",
            Live::Restart => "após reiniciar",
            Live::Restarts => "reinicia o servidor",
            Live::NextInstall => "na próxima instalação",
        }
    }

    /// The tag's tooltip: the same in a sentence.
    pub fn hint(self) -> &'static str {
        match self {
            Live::Now => "Faz efeito na hora (ou só lê).",
            Live::Reload(_) => "Grava o arquivo; o botão \"e aplicar agora\" recarrega no jogo sem reiniciar.",
            Live::Restart => "Grava o arquivo; vale no próximo reinício do servidor.",
            Live::Restarts => "O comando reinicia o servidor: os jogadores caem.",
            Live::NextInstall => "Vale na próxima instalação ou atualização, sem reiniciar.",
        }
    }

    /// The tag's dot colour (r, g, b): green at once, yellow with "aplicar agora", orange after a restart, red when it
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
    pub section: Section,
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

const fn act(section: Section, group: &'static str, label: &'static str, template: &'static str) -> Action {
    Action {
        section,
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

use Section::{Discord, Game, GamePanel, Logs, Machine, Panel, Players, Testers, Updates};

const TEXT_P: &[Param] = &[text("text", "Mensagem")];
const NAME_P: &[Param] = &[text("name", "Nome do personagem")];
const GM_P: &[Param] = &[
    text("name", "Nome do personagem"),
    int("g", "Grupo (1 jogador, 4 GM, 6 God)", 1, 6, "6"),
];
const TAG_P: &[Param] = &[text("tag", "Tag da release (ex.: winpkg-123)")];
const APK_P: &[Param] = &[text("tag", "Tag da release do app (ex.: android-31)")];
const UNITY_P: &[Param] = &[text("tag", "Tag da release do client Unity (ex.: unity-3)")];
const N_P: &[Param] = &[int("n", "Linhas", 1, 500, "100")];
const SECS_P: &[Param] = &[int("secs", "Segundos de aviso", 30, 900, "300")];
const MINS_P: &[Param] = &[int("mins", "Minutos", 1, 60, "5")];
const XP_P: &[Param] = &[int("n", "Multiplicador (1 a 100)", 1, 100, "1")];
const PAIR_P: &[Param] = &[int("n", "Par do cliente", 1, 9999, "1")];
const ENGINE_TOKEN_P: &[Param] = &[secret("token", "Token do GitHub (vazio apaga)")];
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
            "DISCORD_BOT_PATCH_AUTO",
        ],
    ),
    secret("value", "Valor (vazio remove)"),
];
const PAY_SET_P: &[Param] = &[
    choice(
        "key",
        "Ajuste",
        &[
            "CHAOS_PAY_PIX_PROVIDER",
            "CHAOS_PAY_PAYPAL_PROVIDER",
            "CHAOS_PAY_SITE_URL",
            "CHAOS_PAY_PAYER_EMAIL",
            "CHAOS_MP_ACCESS_TOKEN",
            "CHAOS_MP_WEBHOOK_SECRET",
            "CHAOS_PAYPAL_CLIENT_ID",
            "CHAOS_PAYPAL_CLIENT_SECRET",
            "CHAOS_PAYPAL_WEBHOOK_ID",
            "CHAOS_PAYPAL_ENV",
            "CHAOS_PAYPAL_CATEGORY",
        ],
    ),
    secret("value", "Valor (vazio apaga)"),
];
const NP_DAYS_P: &[Param] = &[int("days", "Últimos dias", 1, 3650, "30")];
const GH_DAYS_P: &[Param] = &[int("days", "Últimos dias", 1, 90, "7")];
const BAL_DAYS_P: &[Param] = &[int("days", "Últimos dias", 1, 730, "30")];
const FB_CLOSE_P: &[Param] = &[
    int("id", "Número do relatório", 1, 999_999_999, "1"),
    text("note", "Nota (200 caracteres)"),
];

/// The table. One line per button: category, group (a titled card), label, chaos-ctl.sh arguments. Keep one
/// `act(` per line: the CI check reads it. Rows are in sidebar order, groups in the order they are drawn.
#[rustfmt::skip]
pub static ACTIONS: &[Action] = &[
    // ---- Painel
    act(Panel, "Servidor", "Estado", "status"),
    act(Panel, "Servidor", "Ligar", "start").t(120),
    act(Panel, "Servidor", "Desligar", "stop").ask().t(240).h("Os jogadores são desconectados; o jogo salva antes."),
    act(Panel, "Servidor", "Salvar", "save"),
    act(Panel, "Servidor", "Reiniciar agora", "restart").ask().live(Live::Restarts).t(240),
    act(Panel, "Servidor", "Reiniciar com aviso", "restart {secs}").p(SECS_P).ask().live(Live::Restarts).t(60).h("Os jogadores são avisados; roda em segundo plano."),
    act(Panel, "Servidor", "Backup", "backup").t(600),
    act(Panel, "Servidor", "Saúde e espaço", "health").t(120),
    act(Panel, "Ações rápidas", "Aviso para todos", "broadcast {text}").p(TEXT_P).t(20),
    act(Panel, "Ações rápidas", "Expulsar", "kick {name}").p(NAME_P).ask().t(20),
    act(Panel, "Ações rápidas", "Abrir login", "open").t(20),
    act(Panel, "Ações rápidas", "Fechar login", "close").ask().t(20),
    // ---- Jogadores
    act(Players, "Jogadores", "Quem está online", "players"),
    act(Players, "Jogadores", "Classes", "vocations"),
    act(Players, "Contas", "Criar conta", "account-create {name}").p(ACC_P).t(60),
    act(Players, "Contas", "Trocar senha", "account-password {name}").p(ACC_P).ask().t(60),
    act(Players, "Contas", "Direitos de staff", "gm-set {name} {g}").p(GM_P).ask().t(60).h("O personagem precisa estar offline. 4 = GM, 6 = God; 1 tira os direitos."),
    act(Players, "Bugs e sugestões", "Abertos (30 dias)", "feedback").t(90),
    act(Players, "Bugs e sugestões", "Todos (inclui fechados)", "feedback --all").t(90),
    act(Players, "Bugs e sugestões", "Fechar relatório", "feedback-close {id} {note}").p(FB_CLOSE_P).ask(),
    act(Players, "Novos jogadores", "Funil", "newplayer-funnel --pt --days {days}").p(NP_DAYS_P).t(90).h("Níveis 10 a 100, horas jogadas e onde pararam os que sumiram há 7+ dias."),
    act(Players, "Novos jogadores", "Pesquisa", "survey --pt --texts 100 --days {days}").p(NP_DAYS_P).t(90).h("Respostas da pesquisa dos níveis 20 e 50."),
    act(Players, "Métricas dos jogadores", "Ver métricas", "metrics").t(90),
    act(Players, "Saúde do jogo", "Ver como texto", "game-health --pt --days {days}").p(GH_DAYS_P).t(120).h("Online por hora, mortes, hunts mais e menos usadas, ouro e novos jogadores. O gráfico fica no card abaixo."),
    act(Players, "Relatório de equilíbrio", "Últimos dias", "balance-report --pt --days {days}").p(BAL_DAYS_P).t(180).h("Classes por faixa de nível: minutos por nível, mortes e dano por hora, feitiços mais usados e sugestões."),
    act(Players, "Relatório de equilíbrio", "Season atual", "balance-report --pt --season current").t(180),
    act(Players, "Relatório de equilíbrio", "Enviar por DM", "balance-report --pt --days {days} --dm").p(BAL_DAYS_P).t(180).h("Guarda no servidor e o bot do Discord manda por DM em até 1 minuto."),
    act(Players, "Relatório de equilíbrio", "Último salvo", "balance-report last").t(60),
    act(Players, "Relatório de equilíbrio", "Ligar automático", "balance-report timer on").t(60).h("Todo dia: quando uma season termina, o relatório dela sai sozinho e vai por DM."),
    act(Players, "Relatório de equilíbrio", "Desligar automático", "balance-report timer off").t(60),
    act(Players, "Relatório de equilíbrio", "Estado do automático", "balance-report timer status").t(60),
    // ---- Ajustes do jogo
    act(Game, "Taxa de XP", "Ver", "xp-rate show").t(30),
    act(Game, "Taxa de XP", "Definir (vale no próximo reinício)", "xp-rate set {n}").p(XP_P).live(Live::Restart).t(30),
    act(Game, "Taxa de XP", "Definir e reiniciar", "xp-rate set {n} restart").p(XP_P).ask().live(Live::Restarts).t(240),
    act(Game, "Taxa de XP", "Voltar ao padrão", "xp-rate reset").live(Live::Restart).t(30),
    act(Game, "Modo beta", "Ver", "beta-mode status").t(30),
    act(Game, "Modo beta", "Ligar", "beta-mode on").live(Live::Reload("scripts")).t(30).h("Aplicar agora recarrega os scripts."),
    act(Game, "Modo beta", "Desligar", "beta-mode off").live(Live::Reload("scripts")).t(30).h("Aplicar agora recarrega os scripts."),
    act(Game, "Modo beta", "Ligar e reiniciar", "beta-mode on restart").ask().live(Live::Restarts).t(240),
    act(Game, "Modo beta", "Desligar e reiniciar", "beta-mode off restart").ask().live(Live::Restarts).t(240),
    act(Game, "Serviços de login", "Ver", "clientservices-impl status").t(30),
    act(Game, "Serviços de login", "Rust ligado", "clientservices-impl rust").ask().t(900).h("Compila com cargo na VPS; pode levar minutos."),
    act(Game, "Serviços de login", "Python ligado", "clientservices-impl python").t(60),
    act(Game, "Par do cliente", "Ver", "client-pair show").t(30),
    act(Game, "Par do cliente", "Definir", "client-pair set {n}").p(PAIR_P).ask().live(Live::NextInstall).t(30),
    act(Game, "Mapa", "Publicar áreas da caixa de entrada", "areas-publish").t(120),
    act(Game, "Mapa", "Novo endereço das áreas", "areas-publish --rotate").ask().t(120),
    // ---- Painel do jogo
    // the card with the choice and the button is drawn by the window (reload-file ACTOR NAME)
    act(GamePanel, "Recarregar um arquivo", "Listar tabelas de configuração", "reload-files").t(30).h("Recarregar uma delas: Painel do jogo > Recarregar um arquivo."),
    // ---- Atualizações
    act(Updates, "Atualizar servidor", "Verificar", "update-check").t(180),
    act(Updates, "Atualizar servidor", "Aplicar e reiniciar", "update-apply").ask().live(Live::Restarts).t(60).h("Roda em segundo plano; acompanhe em Atualizações > Logs das atualizações."),
    act(Updates, "Atualizar servidor", "Voltar à versão anterior", "update-rollback").ask().live(Live::Restarts).t(60),
    act(Updates, "Atualizar servidor", "Estado da última atualização", "update-status"),
    act(Updates, "Recompilar engine", "Recompilar", "engine-build start").ask().t(120).h("O GitHub compila o engine do servidor com todos os patches do código novo. Leva de 20 a 60 minutos (a primeira vez, ou depois de uma mudança grande, pode passar de uma hora). O jogo segue no ar e nada é trocado no servidor agora. Quando terminar, use Atualizar servidor para instalar."),
    act(Updates, "Recompilar engine", "Recompilar com client novo", "engine-build start --new-client").ask().t(120).h("Use quando o cartão disser que o programa do client mudou. O GitHub compila o engine e um client novo, com o número de build seguinte ao publicado (o atual continua aceito pelo servidor). O número entra sozinho na lista clientGuardBuilds do config.lua. Leva de 20 a 60 minutos (a primeira vez, ou depois de uma mudança grande, pode passar de uma hora). O jogo segue no ar. Depois, em Atualizar servidor, o client novo é publicado e os jogadores o recebem pelo atualizador; o APK do Android precisa acompanhar (android-client.yml com o mesmo client_build), senão os celulares ficam sem poder jogar."),
    act(Updates, "Recompilar engine", "Atualizar estado", "engine-build status").t(90).h("Pergunta ao GitHub como está a última recompilação. Enquanto ela roda, a janela pergunta sozinha a cada 20 segundos."),
    act(Updates, "Recompilar engine", "Ver passos", "engine-build log 20").t(90).h("Os jobs da rodada, o passo que falhou e o histórico das partidas."),
    act(Updates, "Recompilar engine", "Definir token do GitHub", "engine-build-token-set").p(ENGINE_TOKEN_P).t(60).h("Token fine-grained só deste repositório, com Actions leitura e escrita. Vai pelo stdin e só fica na VPS (/etc/chaos/engine-build.token, modo 600). Vazio apaga. docs/ADMIN_APP.md"),
    act(Updates, "Versão específica", "Atualizar para uma versão", "update {tag} {mode}").p(&[text("tag", "Tag da release (ex.: winpkg-123)"), choice("mode", "Quando", &["now", "at-save"])]).ask().live(Live::Restarts).h("Layout padrão com repositório."),
    act(Updates, "Versão específica", "Voltar versão", "rollback now").ask().live(Live::Restarts).t(30),
    act(Updates, "Site e update do client", "Reinstalar o site", "site-install").ask().t(30),
    act(Updates, "Site e update do client", "Publicar update do client", "publish-update {tag}").p(TAG_P).ask().t(30),
    act(Updates, "Site e update do client", "Publicar app Android", "publish-apk {tag}").p(APK_P).ask().t(30),
    act(Updates, "Site e update do client", "Tirar o app Android do update", "publish-apk --remove").ask().t(30),
    act(Updates, "Site e update do client", "Publicar client Unity (beta)", "publish-unity {tag}").p(UNITY_P).ask().t(30),
    act(Updates, "Site e update do client", "Trocar os downloads", "update-downloads").ask().t(30),
    act(Updates, "Logs das atualizações", "Log do update do servidor", "update-log {n}").p(N_P).t(40),
    act(Updates, "Logs das atualizações", "Log da publicação do client", "publish-log {n}").p(N_P).t(40),
    act(Updates, "Logs das atualizações", "Log da instalação do site", "site-log {n}").p(N_P).t(40),
    // ---- Discord
    act(Discord, "Discord", "Estado", "discord-status").t(60),
    act(Discord, "Discord", "Guardar webhook", "discord-set {channel}").p(DISCORD_P).t(60),
    act(Discord, "Discord", "Ligar avisos", "discord-enable").t(90),
    act(Discord, "Discord", "Desligar avisos", "discord-disable").t(90),
    act(Discord, "Discord", "Testar todos", "discord-test all").t(90),
    act(Discord, "Bot do Discord", "Estado", "discord-bot status").t(40),
    act(Discord, "Bot do Discord", "Instalar ou atualizar", "discord-bot install").ask().t(600).h("Cria o usuário chaosbot e o virtualenv; alguns minutos. De novo atualiza o código."),
    act(Discord, "Bot do Discord", "Guardar ajuste", "discord-bot set {key}").p(BOT_SET_P).t(40).h("Token e chave vão pelo stdin, só ficam na VPS."),
    act(Discord, "Bot do Discord", "Iniciar", "discord-bot start").t(60),
    act(Discord, "Bot do Discord", "Reiniciar", "discord-bot restart").t(60),
    act(Discord, "Bot do Discord", "Parar", "discord-bot stop").ask().t(60),
    act(Discord, "Bot do Discord", "Logs", "discord-bot logs 80").t(40),
    act(Discord, "Bot do Discord", "Levar patch notes ao jogo", "discord-bot patchnotes").t(60),
    // ---- Testers
    act(Testers, "Testers", "Iniciar (reinicia o servidor)", "testers start {n} {m} --restart 300").p(TESTERS_P).ask().live(Live::Restarts).t(180),
    act(Testers, "Testers", "Iniciar com árvore de talentos", "testers start {n} {m} --keystones --restart 300").p(TESTERS_P).ask().live(Live::Restarts).t(180),
    act(Testers, "Testers", "Iniciar com checagem de sistemas", "testers start {n} {m} --checks --restart 300").p(TESTERS_P).ask().live(Live::Restarts).t(180),
    act(Testers, "Testers", "Parar", "testers stop").ask().t(60),
    act(Testers, "Testers", "Estado", "testers status").t(60),
    act(Testers, "Testers", "Relatório", "testers report").t(120),
    act(Testers, "Testers", "Log das ações", "testers log 400").t(60),
    act(Testers, "Testers", "Apagar testers", "testers cleanup --yes").ask().t(240),
    // ---- VPS e manutenção
    act(Machine, "Saúde e espaço", "Ver sobras a limpar", "cleanup").t(120),
    act(Machine, "Saúde e espaço", "Limpar sobras", "cleanup --yes").ask().t(120),
    act(Machine, "Saúde e espaço", "Backups", "backups"),
    act(Machine, "Saúde e espaço", "Ver fuso horário", "timezone").t(60).h("O jogo usa a hora da VPS: precisa ser São Paulo (UTC-3). Sai 1 quando o fuso está errado."),
    act(Machine, "Saúde e espaço", "Ajustar para São Paulo", "timezone set").ask().live(Live::Restart).t(60).h("Ajusta o fuso da VPS. O jogo que já está rodando só pega o fuso novo ao reiniciar (Painel > Servidor); nada é reiniciado."),
    act(Machine, "Conferir lançamento", "Conferir", "launch-check").t(120).h("Lê o servidor instalado e não muda nada: beta e cron das moedas de teste desligados, pagamentos sem mock, arquivos de teste, fuso, datas da Season 1 e do Founder Pack, chave do client, patch notes, contagens do banco, backup e versão instalada. A última linha soma FAIL, WARN e OK; sai 1 quando algo é FAIL."),
    act(Machine, "VPS", "Informações", "vps info").t(60),
    act(Machine, "VPS", "Atualizar o sistema", "vps upgrade").ask().t(30),
    act(Machine, "VPS", "Log da atualização", "vps upgrade-log 200").t(30),
    act(Machine, "VPS", "Reiniciar a VPS", "vps reboot {mins}").p(MINS_P).ask().t(30),
    act(Machine, "VPS", "Cancelar reinício", "vps reboot-cancel").t(30),
    act(Machine, "Unidades chaos-*", "Listar", "services").t(30),
    act(Machine, "Unidades chaos-*", "Ligar, desligar ou reiniciar", "service {unit} {verb}").p(UNIT_ACT_P).ask().t(240),
    act(Machine, "Unidades chaos-*", "Log de uma unidade", "service-log {unit} 200").p(UNIT_P).t(40),
    act(Machine, "Servidor como usuário chaos", "Ver", "server-user status").t(60),
    act(Machine, "Servidor como usuário chaos", "Corrigir", "server-user fix").ask().t(180),
    act(Machine, "Servidor como usuário chaos", "Corrigir e reiniciar", "server-user fix --restart {secs}").p(SECS_P).ask().live(Live::Restarts).t(180),
    act(Machine, "Servidor como usuário chaos", "Desfazer", "server-user rollback").ask().t(60),
    act(Machine, "Servidor como usuário chaos", "Log do reinício", "server-user log 60").t(30),
    act(Machine, "Pagamentos (doações)", "Estado", "pay-status").t(60).h("O que está salvo (sim ou não, nunca o valor) e os endereços para colar nos painéis do Mercado Pago e do PayPal. docs/PAYMENTS.md"),
    act(Machine, "Pagamentos (doações)", "Guardar ajuste", "pay-set {key}").p(PAY_SET_P).t(60).h("O valor vai pelo stdin e só fica na VPS (/etc/chaos/payments.env, modo 640). Provedor: mercadopago, paypal ou off; ambiente: sandbox ou live."),
    act(Machine, "Pagamentos (doações)", "Testar", "pay-test").t(120).h("Só lê: confere as chaves no Mercado Pago e no PayPal e se a página de aviso responde 401. Nenhuma cobrança."),
    act(Machine, "Pagamentos (doações)", "Ativar worker", "pay-enable").t(90),
    act(Machine, "Pagamentos (doações)", "Desativar worker", "pay-disable").ask().t(60).h("Doações novas esperam a cobrança até ativar de novo."),
    // ---- Logs
    act(Logs, "Console", "Últimas linhas", "logs {n}").p(N_P).t(40),
    act(Logs, "Erros", "Desde o último início", "errors {n}").p(N_P).t(40),
    act(Logs, "Erros", "Incluir inícios anteriores", "errors {n} all").p(N_P).t(40),
    act(Logs, "Erros", "Limpar lista", "errors clear").ask().t(40).h("Só põe uma marca no log; nada é apagado."),
    act(Logs, "GM", "Registro do painel de admin", "gm-logs {n}").p(N_P).t(60),
    act(Logs, "Par do cliente", "Estado do par (spectate)", "spectate-pair status").t(40),
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

/// The game panel's reload action as chaos-ctl.sh arguments ("e aplicar agora").
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
                seen.insert((a.section as u8, a.group, a.label)),
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
    fn engine_build_card_commands() {
        let find = |t: &str| {
            ACTIONS
                .iter()
                .find(|a| a.template == t)
                .unwrap_or_else(|| panic!("{t}"))
        };
        let start = find("engine-build start");
        assert!(start.confirm, "Recompilar asks first");
        assert_eq!(start.group, "Recompilar engine");
        assert!(start.hint.contains("20 a 60 minutos") && start.hint.contains("Atualizar servidor"));
        assert!(crate::engine::DURATION.contains("20 a 60 minutos"));
        let nc = find("engine-build start --new-client");
        assert!(
            nc.confirm
                && nc.hint.contains("clientGuardBuilds")
                && nc.hint.contains("APK")
                && nc.hint.contains("20 a 60 minutos")
        );
        assert!(!find("engine-build status").confirm && !find("engine-build log 20").confirm);
        let tok = find("engine-build-token-set");
        let (line, stdin) = build(tok, &["github_pat_x".into()]).unwrap();
        assert_eq!(line, "engine-build-token-set", "the token is never on the command line");
        assert_eq!(stdin.as_deref(), Some("github_pat_x\n"));
        assert_eq!(
            build(tok, &["".into()]).unwrap().1.as_deref(),
            Some("\n"),
            "empty removes the token"
        );
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
