//! Cinders Admin for the PC: the window. Logic is in the library (commands, nav, output, ssh, config, update, catalog).
// A release build on Windows is a windows-subsystem program: no console window opens with it (O383, owner 2026-11-03:
// "the app always opens a cmd window"). Debug builds keep the console for `cargo run` messages.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]
use cinders_admin::cards::{self, Count, Metrics, Player, State, Status};
use cinders_admin::catalog::{self, PanelAction};
use cinders_admin::commands::{self, Action, Kind, Live, Section, ACTIONS};
use cinders_admin::config::{self, Config};
use cinders_admin::engine::{self, EngineInfo};
use cinders_admin::health::{self, Health};
use cinders_admin::infos::{self, Report, UpdateInfo};
use cinders_admin::live::{self, Level, Poller};
use cinders_admin::output::{self, State as RunState};
use cinders_admin::{keys, nav, reload, ssh, update};
use eframe::egui;
use std::collections::HashMap;
use std::sync::mpsc::{channel, Receiver, Sender};
use std::sync::Arc;

mod theme;

const VERSION: &str = env!("CARGO_PKG_VERSION");

/// One refresh of the live page.
struct LiveData {
    status: Status,
    players: Vec<Player>,
    logs: String,
    at: i64,
}

/// How the answer of a command is shown besides the output pane.
#[derive(Clone, Copy, PartialEq)]
enum Answer {
    Plain,
    /// `update-check`: the update card.
    Update,
    /// `feedback`: one card per report.
    Feedback,
    /// `engine-build status`: the card Recompilar engine (read even when the exit code says GitHub failed).
    Engine,
    /// `engine-build start`: on success the window follows the build.
    EngineStart,
}

enum Msg {
    /// Streamed output of the run `id` while it runs.
    Chunk {
        id: u64,
        text: String,
    },
    Done {
        id: u64,
        title: String,
        text: String,
        ok: bool,
        answer: Answer,
    },
    Catalog(Result<(Vec<PanelAction>, i64), String>),
    Update(Result<Option<update::Found>, String>),
    Installed(Result<(), String>),
    /// Status card: parsed `status` output, or why it failed.
    CardStatus(Result<Status, String>),
    CardPlayers(Result<Vec<Player>, String>),
    CardMetrics(Result<Metrics, String>),
    /// O397: parsed `game-health --kv`, or why it failed.
    CardHealth(Result<Health, String>),
    Live(Result<LiveData, String>),
    /// The window's own `engine-build status` while a build runs: the text, no output pane entry.
    EnginePoll(String),
    /// Names printed by `reload-files`.
    ReloadList(Result<Vec<String>, String>),
}

struct Pending {
    title: String,
    line: String,
    stdin: Option<String>,
    timeout: u64,
    reload: Option<&'static str>,
    warn: String,
    /// The answer is the JSON line of a panel action: show its message and lines.
    panel_answer: bool,
    answer: Answer,
}

struct App {
    cfg: Config,
    /// The sidebar category on screen (remembered in the settings file).
    section: Section,
    /// The sidebar search; not blank: the main area lists the matching buttons of every category.
    search: String,
    values: HashMap<usize, Vec<String>>,
    /// Output panel: one entry per run, streamed, with a history.
    out: output::Log,
    /// The output is open in its own window.
    out_window: bool,
    /// Last good `update-check`, drawn in the group "Atualizar servidor".
    update_info: Option<UpdateInfo>,
    /// Last `engine-build status`, drawn in the group "Recompilar engine".
    engine_info: Option<EngineInfo>,
    /// A build runs (or just started): `engine-build status` is asked every `engine::POLL_SECS` seconds.
    engine_watch: bool,
    engine_poller: Poller,
    /// Last good `feedback`, drawn in the group "Bugs e sugestões".
    reports: Option<Vec<Report>>,
    busy: usize,
    tx: Sender<Msg>,
    rx: Receiver<Msg>,
    confirm: Option<Pending>,
    status: String,
    update: Option<update::Found>,
    update_note: String,
    catalog: Vec<PanelAction>,
    catalog_note: String,
    filter: String,
    game_sel: Option<usize>,
    game_values: Vec<String>,
    terminal: String,
    card_status: Option<Status>,
    card_status_note: String,
    card_players: Option<Vec<Player>>,
    card_metrics: Option<Metrics>,
    card_metrics_note: String,
    card_health: Option<Health>,
    card_health_note: String,
    cards_busy: usize,
    started: std::time::Instant,
    poller: Poller,
    live_status: Option<Status>,
    live_players: Vec<Player>,
    live_logs: String,
    live_at: Option<i64>,
    live_note: String,
    live_filter: String,
    live_lines: u32,
    live_follow: bool,
    reload_names: Vec<String>,
    reload_pick: String,
    reload_note: String,
    header: egui::TextureHandle,
    icon: egui::TextureHandle,
}

impl App {
    fn new(ctx: &egui::Context) -> Self {
        let (tx, rx) = channel();
        let cfg = config::load();
        let mut app = App {
            section: nav::start_section(&cfg.last_section, cfg.configured()),
            search: String::new(),
            cfg,
            values: HashMap::new(),
            out: output::Log::default(),
            out_window: false,
            update_info: None,
            engine_info: None,
            engine_watch: false,
            engine_poller: Poller::every(engine::POLL_SECS),
            reports: None,
            busy: 0,
            tx,
            rx,
            confirm: None,
            status: String::new(),
            update: None,
            update_note: String::new(),
            catalog: Vec::new(),
            catalog_note: "Lista vazia: toque em Atualizar lista (precisa do personagem admin em Config).".into(),
            filter: String::new(),
            game_sel: None,
            game_values: Vec::new(),
            terminal: String::new(),
            card_status: None,
            card_status_note: "Toque em Atualizar.".into(),
            card_players: None,
            card_metrics: None,
            card_metrics_note: "Toque em Carregar métricas.".into(),
            card_health: None,
            card_health_note: "Toque em Carregar gráficos.".into(),
            cards_busy: 0,
            started: std::time::Instant::now(),
            poller: Poller::default(),
            live_status: None,
            live_players: Vec::new(),
            live_logs: String::new(),
            live_at: None,
            live_note: "Esperando a primeira atualização.".into(),
            live_filter: String::new(),
            live_lines: 100,
            live_follow: true,
            reload_names: Vec::new(),
            reload_pick: String::new(),
            reload_note: "Lista vazia: toque em Listar arquivos.".into(),
            header: theme::header(ctx),
            icon: theme::icon_texture(ctx),
        };
        if app.cfg.auto_update {
            app.check_update();
        }
        app
    }

    /// Runs one chaos-ctl.sh command on a thread and sends the parsed answer back.
    fn card_call(&mut self, ctx: &egui::Context, args: &'static str, timeout: u64, kind: u8) {
        self.cards_busy += 1;
        let (cfg, tx, ctx) = (self.cfg.clone(), self.tx.clone(), ctx.clone());
        std::thread::spawn(move || {
            let o = ssh::exec(&cfg, &ssh::ctl_line(&cfg, args), timeout, None);
            let first = |t: &str| t.lines().next().unwrap_or("").to_string();
            let m = match kind {
                0 => {
                    let s = Status::parse(&o.text);
                    Msg::CardStatus(if s.valid() { Ok(s) } else { Err(first(&o.text)) })
                }
                1 if o.code == 0 => Msg::CardPlayers(Ok(cards::parse_players(&o.text))),
                1 => Msg::CardPlayers(Err(first(&o.text))),
                3 => match Health::parse(&o.text) {
                    Some(h) => Msg::CardHealth(Ok(h)),
                    None => Msg::CardHealth(Err(first(&o.text))),
                },
                _ => match Metrics::parse(&o.text) {
                    Some(m) => Msg::CardMetrics(Ok(m)),
                    None => Msg::CardMetrics(Err(first(&o.text))),
                },
            };
            let _ = tx.send(m);
            ctx.request_repaint();
        });
    }

    fn now_unix() -> i64 {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0)
    }

    fn server_card_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let (gold, red, green) = (theme::WARN, theme::ERROR, theme::OK);
        ui.horizontal(|ui| {
            ui.label(theme::card_title("Servidor do jogo"));
            if let Some(s) = &self.card_status {
                let st = s.state();
                let c = match st {
                    State::Online => green,
                    State::Starting | State::Stopping | State::OnlineNoUnit => gold,
                    _ => red,
                };
                theme::state_word(ui, st.badge(), c, st == State::Online);
            }
            if ui.button("Atualizar").clicked() {
                self.card_call(ctx, "status", 30, 0);
            }
            if self.cards_busy > 0 {
                ui.spinner();
            }
        });
        match self.card_status.clone() {
            None => {
                ui.weak(&self.card_status_note);
            }
            Some(s) => {
                let on = s.state() == State::Online;
                match s.uptime_sec(Self::now_unix()) {
                    Some(up) if on => ui.label(format!("No ar há {}", cards::duration(up))),
                    _ if on => ui.label("No ar"),
                    _ => ui.label("O servidor não está rodando"),
                };
                let u = s.get("unit");
                ui.weak(format!("Unidade {}", if u.is_empty() { "chaos-server" } else { u }));
                if s.state() == State::OnlineNoUnit {
                    ui.colored_label(
                        gold,
                        "Rodando fora do systemd: Ligar, Desligar e Reiniciar precisam da unidade instalada.",
                    );
                }
                if s.state() == State::Failed {
                    ui.colored_label(red, "O serviço caiu: veja os erros em Logs");
                }
                egui::Grid::new("status_grid")
                    .num_columns(2)
                    .spacing([28.0, 8.0])
                    .show(ui, |ui| {
                        ui.label(theme::caption("Jogadores"));
                        ui.horizontal(|ui| {
                            ui.strong(s.players_text());
                            if ui.small_button("Quem está online").clicked() {
                                self.card_call(ctx, "players", 30, 1);
                            }
                        });
                        ui.end_row();
                        ui.label(theme::caption("Erros desde o início"));
                        match s.errors() {
                            Some(0) => ui.strong("nenhum"),
                            Some(n) => ui.colored_label(red, n.to_string()),
                            None => ui.strong("?"),
                        };
                        ui.end_row();
                        ui.label(theme::caption("Memória"));
                        ui.horizontal(|ui| {
                            ui.strong(s.mem_text());
                            if let Some(p) = s.mem_percent() {
                                theme::usage_bar(ui, u32::from(p));
                            }
                        });
                        ui.end_row();
                        ui.label(theme::caption("Disco"));
                        ui.horizontal(|ui| {
                            ui.strong(s.disk_text());
                            if let Some(p) = s.disk_percent() {
                                theme::usage_bar(ui, u32::from(p));
                            }
                        });
                        ui.end_row();
                        ui.label(theme::caption("Carga (1, 5, 15 min)"));
                        ui.strong(s.load_text());
                        ui.end_row();
                        ui.label(theme::caption("Último backup"));
                        ui.strong(s.backup_text());
                        ui.end_row();
                    });
            }
        }
        if let Some(p) = &self.card_players {
            sub_block(ui, &format!("Online agora ({})", p.len()), |ui| players_list(ui, p));
        }
    }

    /// O397: the charts of `game-health --kv` under the group "Saúde do jogo" (7 days; the table's button prints the
    /// text for any number of days).
    fn health_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.add_space(4.0);
        if ui.button("Carregar gráficos (7 dias)").clicked() {
            self.card_call(ctx, "game-health --kv --pt --days 7", 120, 3);
        }
        let Some(h) = self.card_health.clone() else {
            ui.weak(&self.card_health_note);
            return;
        };
        if !h.ok {
            ui.colored_label(theme::ERROR, h.error_text());
            return;
        }
        ui.label(h.headline());
        let online: Vec<Option<f64>> = h.hours.iter().map(|x| x.mean).collect();
        sub_block(ui, "Online por hora (média de cada hora; vazio = sem amostra)", |ui| {
            bars(ui, &online, h.max_online(), theme::EMBER, 80.0);
            if let (Some(a), Some(b)) = (h.hours.first(), h.hours.last()) {
                ui.weak(format!(
                    "{} a {}, hora do servidor. Pico {} em {}.",
                    a.day, b.day, h.online_peak, h.online_peak_at
                ));
            }
        });
        let hod = h.by_hour_of_day();
        let hod_max = hod.iter().flatten().copied().fold(1.0, f64::max);
        sub_block(ui, "Média por hora do dia (0h a 23h)", |ui| {
            bars(ui, &hod, hod_max, theme::TEXT_2, 60.0);
            let hour = |v: Option<u32>| v.map(|x| format!("{x}h")).unwrap_or_else(|| "-".into());
            ui.weak(format!(
                "Mais cheia: {}. Mais vazia: {}.",
                hour(h.busiest_hour),
                hour(h.quietest_hour)
            ));
        });
        let deaths: Vec<Option<f64>> = h.hours.iter().map(|x| Some(x.deaths as f64)).collect();
        let dmax = h.hours.iter().map(|x| x.deaths as f64).fold(1.0, f64::max);
        sub_block(
            ui,
            &format!(
                "Mortes por hora ({} no período, {} por hora de jogo)",
                h.deaths_total,
                h.deaths_per_play_hour.replace('.', ",")
            ),
            |ui| bars(ui, &deaths, dmax, theme::WARN, 60.0),
        );
        let hunt_rows = |v: &[health::Hunt]| -> Vec<Vec<String>> {
            v.iter()
                .map(|x| {
                    vec![
                        x.name.clone(),
                        format!("{:.1}", x.hours).replace('.', ","),
                        x.visits.text(),
                        x.kills.to_string(),
                        x.deaths.to_string(),
                    ]
                })
                .collect()
        };
        let head = ["Hunt", "Horas caçando", "Personagem-horas", "Abates", "Mortes"];
        sub_block(
            ui,
            &format!(
                "Hunts mais usadas ({} conhecidas, {} sem visita)",
                h.hunts_known, h.hunts_unvisited
            ),
            |ui| grid(ui, "gh_top", &head, hunt_rows(&h.top)),
        );
        sub_block(ui, "Hunts menos usadas", |ui| {
            grid(ui, "gh_low", &head, hunt_rows(&h.low))
        });
        sub_block(
            ui,
            &format!(
                "Ouro: entrou {}, saiu {}, saldo {}",
                health::gold(h.gold_in),
                health::gold(h.gold_out),
                health::gold(h.gold_net)
            ),
            |ui| {
                let rows = h
                    .gold
                    .iter()
                    .map(|r| {
                        let g = match r.count {
                            health::Small::N(n) => health::gold(n as i64),
                            health::Small::Hidden => "<5".into(),
                        };
                        vec![r.label.clone(), g, r.extra.to_string()]
                    })
                    .collect();
                grid(ui, "gh_gold", &["Fonte", "Ouro", "Vezes"], rows);
            },
        );
        sub_block(
            ui,
            &format!(
                "Novos jogadores (últimos {} dias): {} personagens; pararam {}",
                h.funnel_days, h.funnel_characters, h.funnel_stopped
            ),
            |ui| {
                let rows = h
                    .reached
                    .iter()
                    .chain(h.stop_level.iter().take(5))
                    .chain(h.stop_system.iter().take(5))
                    .map(|r| vec![r.label.clone(), r.count.text(), health::pct(r.pct)])
                    .collect();
                grid(ui, "gh_funnel", &["", "Personagens", "Parte"], rows);
            },
        );
    }

    fn metrics_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal(|ui| {
            ui.label(theme::card_title("Métricas dos jogadores"));
            if ui.button("Carregar métricas").clicked() {
                self.card_call(ctx, "metrics --json", 90, 2);
            }
        });
        let Some(m) = self.card_metrics.clone() else {
            ui.weak(&self.card_metrics_note);
            return;
        };
        if !m.ok {
            ui.colored_label(theme::ERROR, m.error_text());
            return;
        }
        if m.empty {
            ui.label("Ainda sem dados: a tabela se enche com o jogo.");
            return;
        }
        let c = |v: Option<Count>| v.map(Count::text).unwrap_or_else(|| "?".into());
        ui.label(format!(
            "Churn de {} dias: foram embora {}, ativos {}.",
            m.churn_days,
            c(m.gone),
            c(m.active)
        ));
        let table = |ui: &mut egui::Ui, id: &str, head: &[&str], rows: Vec<Vec<String>>| {
            if rows.is_empty() {
                ui.weak("Sem linhas.");
                return;
            }
            egui::Grid::new(id).striped(true).spacing([18.0, 2.0]).show(ui, |ui| {
                for h in head {
                    ui.strong(*h);
                }
                ui.end_row();
                for r in rows {
                    for v in r {
                        ui.label(v);
                    }
                    ui.end_row();
                }
            });
        };
        let killer_rows = |v: &[cards::Killer]| -> Vec<Vec<String>> {
            v.iter()
                .map(|k| vec![k.name.clone(), k.count.text(), k.top_band.clone()])
                .collect()
        };
        sub_block(ui, "Churn por faixa de nível", |ui| {
            let rows = m
                .bands
                .iter()
                .map(|b| vec![b.band.clone(), b.gone.text(), b.active.text(), cards::pct(b.gone_pct)])
                .collect();
            table(ui, "m_bands", &["Faixa", "Saíram", "Ativos", "Saída"], rows);
        });
        sub_block(ui, "Onde as pessoas param", |ui| {
            table(
                ui,
                "m_stops",
                &["Lugar", "Saíram", "Faixa principal"],
                killer_rows(&m.stops),
            );
        });
        sub_block(ui, "Mortes por área", |ui| {
            table(
                ui,
                "m_areas",
                &["Área", "Mortes", "Faixa principal"],
                killer_rows(&m.areas),
            );
        });
        sub_block(ui, "Mortes por monstro", |ui| {
            table(
                ui,
                "m_monsters",
                &["Monstro", "Mortes", "Faixa principal"],
                killer_rows(&m.monsters),
            );
        });
        sub_block(
            ui,
            &format!("Primeira sessão ({} personagens)", c(m.session_characters)),
            |ui| {
                let mut prev = String::new();
                let mut rows = Vec::new();
                for b in &m.sessions {
                    rows.push(vec![
                        cards::bucket_text(&b.bucket, &prev),
                        b.characters.text(),
                        cards::pct(b.pct),
                    ]);
                    prev = b.bucket.clone();
                }
                table(ui, "m_sessions", &["Duração", "Personagens", "Parte"], rows);
            },
        );
        sub_block(ui, "Tempo mediano até o nível", |ui| {
            let rows = m
                .milestones
                .iter()
                .map(|x| {
                    vec![
                        x.level.to_string(),
                        cards::minutes(x.median_minutes),
                        x.characters.text(),
                    ]
                })
                .collect();
            table(ui, "m_milestones", &["Nível", "Mediana", "Personagens"], rows);
        });
        sub_block(ui, "Retorno por semana de criação", |ui| {
            let rows = m
                .weeks
                .iter()
                .map(|w| {
                    vec![
                        w.week.clone(),
                        w.cohort.text(),
                        cards::pct(w.pct[0]),
                        cards::pct(w.pct[1]),
                        cards::pct(w.pct[2]),
                    ]
                })
                .collect();
            table(ui, "m_weeks", &["Semana", "Novos", "Dia 1", "Dia 3", "Dia 7"], rows);
        });
        sub_block(ui, "Retenção por dia de criação", |ui| {
            // newest day first; a percent only for a finished window on a day the counters covered (server/README.md O437)
            ui.weak(format!(
                "Cada personagem conta uma vez por janela. Dia 1 é o dia seguinte à criação. Contagem desde {}.",
                if m.retain_since.is_empty() {
                    "—"
                } else {
                    m.retain_since.as_str()
                }
            ));
            let mut head = vec!["Dia", "Novos"];
            head.extend(cards::RETAIN_LABELS);
            let mut rows: Vec<Vec<String>> = Vec::new();
            if !m.retain_totals.is_empty() {
                // the total over every qualifying day: the share of each window ("—" when hidden)
                let mut total = vec!["Total (janelas terminadas)".to_string(), String::new()];
                for k in cards::RETAIN_KEYS {
                    let pct = m.retain_totals.iter().find(|t| t.window == k).and_then(|t| t.pct);
                    total.push(match pct {
                        Some(_) => cards::pct(pct),
                        None => "—".into(),
                    });
                }
                rows.push(total);
            }
            for d in m.cohort_days.iter().rev() {
                let mut r = vec![
                    format!("{}{}", d.day, if d.covered { "" } else { " (parcial)" }),
                    d.cohort.text(),
                ];
                for k in 0..cards::RETAIN_KEYS.len() {
                    r.push(cards::back_text(d.back[k], d.pct[k]));
                }
                rows.push(r);
            }
            table(ui, "m_retention", &head, rows);
        });
        sub_block(ui, "Primeiro uso de cada sistema", |ui| {
            let rows = m
                .first_uses
                .iter()
                .map(|x| {
                    vec![
                        cards::system_name(&x.system).to_string(),
                        x.characters.text(),
                        cards::pct(x.pct),
                        cards::minutes(x.median_minutes),
                        x.top_band.clone(),
                    ]
                })
                .collect();
            table(
                ui,
                "m_first",
                &["Sistema", "Personagens", "Parte", "Tempo mediano", "Faixa"],
                rows,
            );
        });
    }

    fn check_update(&mut self) {
        let tx = self.tx.clone();
        let cfg = self.cfg.clone();
        self.update_note = "Procurando versão nova...".into();
        std::thread::spawn(move || {
            let _ = tx.send(Msg::Update(update::check(&cfg, VERSION)));
        });
    }

    fn run(&mut self, ctx: &egui::Context, p: Pending) {
        self.busy += 1;
        let id = self.out.start(&p.title);
        let cfg = self.cfg.clone();
        let tx = self.tx.clone();
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            let remote = if p.line.starts_with("\u{0}raw ") {
                p.line[5..].to_string()
            } else {
                ssh::ctl_line(&cfg, &p.line)
            };
            // a panel answer is one JSON line, parsed at the end: nothing to show while it runs
            let on: Option<ssh::OnText> = (!p.panel_answer).then(|| {
                let (tx, ctx) = (tx.clone(), ctx.clone());
                Arc::new(move |t: &str| {
                    let _ = tx.send(Msg::Chunk {
                        id,
                        text: t.to_string(),
                    });
                    ctx.request_repaint();
                }) as ssh::OnText
            });
            let mut o = ssh::exec_stream(&cfg, &remote, p.timeout, p.stdin.as_deref(), on);
            let mut ok = o.code == 0;
            if let (true, Some(sys)) = (ok, p.reload) {
                if cfg.actor.is_empty() {
                    o.text
                        .push_str("\nAplicar agora: preencha o personagem admin em Config.\n");
                    ok = false;
                } else {
                    let r = ssh::exec(
                        &cfg,
                        &ssh::ctl_line(&cfg, &commands::reload_args(&cfg.actor, sys)),
                        60,
                        None,
                    );
                    let (rok, msg) = catalog::parse_panel_result(&r.text);
                    o.text.push_str(&format!(
                        "\nAplicar agora (recarregar {sys}): {}\n{msg}\n",
                        if rok && r.code == 0 { "ok" } else { "falhou" }
                    ));
                    ok = rok && r.code == 0;
                }
            }
            if p.panel_answer {
                let (pok, msg) = catalog::parse_panel_result(&o.text);
                ok = pok && o.code == 0;
                o.text = msg;
            }
            if o.code != 0 {
                o.text.push_str(&format!("\n[código de saída {}]\n", o.code));
            }
            let _ = tx.send(Msg::Done {
                id,
                title: p.title,
                text: o.text,
                ok,
                answer: p.answer,
            });
            ctx.request_repaint();
        });
    }

    fn start(&mut self, ctx: &egui::Context, idx: usize, apply_live: bool) {
        let a: &Action = &ACTIONS[idx];
        let vals = self
            .values
            .get(&idx)
            .cloned()
            .unwrap_or_else(|| a.params.iter().map(|p| p.default.to_string()).collect());
        match commands::build(a, &vals) {
            Err(e) => self.status = e,
            Ok((line, stdin)) => {
                let reload = match (apply_live, a.live) {
                    (true, Live::Reload(s)) => Some(s),
                    _ => None,
                };
                let mut warn = String::new();
                if a.confirm {
                    warn = format!("Executar \"{}\"? {}", a.label, a.hint);
                }
                let p = Pending {
                    title: format!("{} > {}", a.group, a.label),
                    line,
                    stdin,
                    timeout: a.timeout,
                    reload,
                    warn,
                    panel_answer: false,
                    answer: match a.template.split(' ').next() {
                        Some("update-check") => Answer::Update,
                        Some("engine-build") if a.template == "engine-build status" => Answer::Engine,
                        Some("engine-build") if a.template.starts_with("engine-build start") => Answer::EngineStart,
                        Some("feedback") => Answer::Feedback,
                        _ => Answer::Plain,
                    },
                };
                if a.confirm {
                    self.confirm = Some(p);
                } else {
                    self.run(ctx, p);
                }
            }
        }
    }

    /// The buttons of one group. Buttons without fields share wrapped rows; a button with fields gets its own row.
    fn group_rows(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, indices: &[usize]) {
        let mut k = 0;
        while k < indices.len() {
            let mut j = k + 1;
            if ACTIONS[indices[k]].params.is_empty() {
                while j < indices.len() && ACTIONS[indices[j]].params.is_empty() {
                    j += 1;
                }
            }
            ui.horizontal_wrapped(|ui| {
                for &i in &indices[k..j] {
                    self.action_widgets(ui, ctx, i);
                }
            });
            k = j;
        }
    }

    /// One button: its fields, the button, "e aplicar agora", the caveat tag.
    fn action_widgets(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, i: usize) {
        let a: &Action = &ACTIONS[i];
        let vals = self
            .values
            .entry(i)
            .or_insert_with(|| a.params.iter().map(|p| p.default.to_string()).collect());
        for (p, v) in a.params.iter().zip(vals.iter_mut()) {
            ui.label(theme::caption(p.label));
            match p.kind {
                Kind::Choice(opts) => {
                    egui::ComboBox::from_id_salt((i, p.name))
                        .selected_text(v.clone())
                        .show_ui(ui, |ui| {
                            for o in opts {
                                ui.selectable_value(v, o.to_string(), *o);
                            }
                        });
                }
                Kind::Secret => {
                    ui.add(egui::TextEdit::singleline(v).password(true).desired_width(140.0));
                }
                _ => {
                    ui.add(
                        egui::TextEdit::singleline(v).desired_width(if matches!(p.kind, Kind::Int(..)) {
                            60.0
                        } else {
                            220.0
                        }),
                    );
                }
            }
        }
        let run = if a.confirm {
            theme::danger_button(ui, a.label)
        } else {
            ui.button(a.label)
        }
        .on_hover_text(a.hint);
        let mut go = run.clicked();
        let mut live_go = false;
        if let Live::Reload(sys) = a.live {
            live_go = ui
                .button(format!("{} e aplicar agora", a.label))
                .on_hover_text(format!("Depois recarrega {sys} no jogo"))
                .clicked();
        }
        // a quiet tag only when the change carries a caveat: it restarts the server, or waits for the next
        // restart. No dot: the ember dot is the running server's alone.
        let tag = match a.live {
            Live::Restarts => Some(theme::ERROR),
            Live::Restart => Some(theme::MUTED),
            _ => None,
        };
        if let Some(colour) = tag {
            ui.label(egui::RichText::new(a.live.label()).small().color(colour))
                .on_hover_text(a.live.hint());
        }
        if go || live_go {
            go = true;
        }
        if go {
            self.start(ctx, i, live_go);
        }
    }

    /// One group of the table as a plain titled card (O383: no collapsing headers), with the answer cards some groups
    /// draw under their buttons.
    fn group_card(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, group: &str, indices: &[usize]) {
        theme::card_full(ui, |ui| {
            ui.label(theme::card_title(group));
            ui.add_space(2.0);
            self.group_rows(ui, ctx, indices);
            match group {
                "Atualizar servidor" => self.update_card_ui(ui),
                "Recompilar engine" => self.engine_card_ui(ui),
                "Bugs e sugestões" => self.reports_ui(ui),
                "Saúde do jogo" => self.health_ui(ui, ctx),
                _ => {}
            }
        });
        ui.add_space(8.0);
    }

    /// A category: its own cards, then its groups in table order.
    fn section_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, s: Section) {
        let mut groups = nav::groups(&nav::actions_of(s));
        match s {
            Section::Panel => {
                theme::card_full(ui, |ui| self.server_card_ui(ui, ctx));
                ui.add_space(8.0);
            }
            Section::Players => {
                // the metrics card goes after the buttons: it can be long
            }
            Section::LiveView => {
                theme::card_full(ui, |ui| self.live_top_ui(ui));
                ui.add_space(8.0);
                theme::card_full(ui, |ui| self.live_console_ui(ui, ctx));
                ui.add_space(8.0);
            }
            Section::GamePanel => {
                // the table's "Recarregar um arquivo" button sits in the window's card of the same name
                let same: Vec<usize> = groups
                    .iter()
                    .filter(|(g, _)| *g == "Recarregar um arquivo")
                    .flat_map(|(_, v)| v.clone())
                    .collect();
                groups.retain(|(g, _)| *g != "Recarregar um arquivo");
                theme::card_full(ui, |ui| {
                    self.reload_ui(ui, ctx);
                    if !same.is_empty() {
                        ui.add_space(4.0);
                        self.group_rows(ui, ctx, &same);
                    }
                });
                ui.add_space(8.0);
                theme::card_full(ui, |ui| self.catalog_ui(ui, ctx));
                ui.add_space(8.0);
            }
            Section::Settings => self.settings_ui(ui),
            _ => {}
        }
        for (g, idx) in groups {
            self.group_card(ui, ctx, g, &idx);
        }
        match s {
            Section::Players => {
                theme::card_full(ui, |ui| self.metrics_ui(ui, ctx));
                ui.add_space(8.0);
            }
            Section::Logs => {
                self.terminal_ui(ui, ctx);
                ui.add_space(8.0);
            }
            _ => {}
        }
    }

    /// The card "Terminal na VPS" of Logs.
    fn terminal_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        theme::card_full(ui, |ui| {
            ui.label(theme::card_title("Terminal na VPS (qualquer comando do usuário SSH)"));
            ui.horizontal(|ui| {
                ui.add(
                    egui::TextEdit::singleline(&mut self.terminal)
                        .desired_width(420.0)
                        .font(egui::TextStyle::Monospace),
                );
                if theme::primary_button(ui, "Rodar").clicked() && !self.terminal.trim().is_empty() {
                    let p = Pending {
                        title: "Terminal".into(),
                        line: format!("\u{0}raw {}", self.terminal.trim()),
                        stdin: None,
                        timeout: 60,
                        reload: None,
                        warn: String::new(),
                        panel_answer: false,
                        answer: Answer::Plain,
                    };
                    self.run(ctx, p);
                }
            });
        });
    }

    /// Search results: the matching buttons of every category, grouped as on their own page, ready to run.
    fn search_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let hits = nav::search(&self.search);
        let n: usize = hits.iter().map(|h| h.actions.len()).sum();
        let what = if n == 1 { "botão" } else { "botões" };
        ui.label(theme::caption(&format!(
            "{n} {what} para \"{}\". Esc ou x limpa a busca. Ctrl+F volta para a busca.",
            self.search.trim()
        )));
        ui.add_space(4.0);
        if hits.is_empty() {
            ui.label("Nada encontrado. Tente outra palavra (ex.: webhook, backup, senha, reiniciar).");
        }
        for h in hits {
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new(h.section.title()).size(18.0).color(theme::GOLD));
                if ui.button("Abrir").clicked() {
                    self.go(h.section);
                }
            });
            if h.page {
                ui.label(theme::caption(&format!(
                    "Também nos cartões da página {}: clique em Abrir.",
                    h.section.title()
                )));
            }
            for (g, idx) in nav::groups(&h.actions) {
                self.group_card(ui, ctx, g, &idx);
            }
            ui.add_space(4.0);
        }
    }

    /// Opens a category, clears the search and remembers it for the next start.
    fn go(&mut self, s: Section) {
        self.section = s;
        self.search.clear();
        if self.cfg.last_section != s.key() {
            self.cfg.last_section = s.key().to_string();
            if let Err(e) = config::save_last_section(s.key()) {
                self.status = format!("Não guardei a categoria aberta: {e}");
            }
        }
    }

    /// The sidebar: search box, then the categories (only those with hits while searching, with their counts).
    fn sidebar_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let mut clear = false;
        let find = ui
            .horizontal(|ui| {
                ui.spacing_mut().item_spacing.x = 4.0;
                let find = ui.add(
                    egui::TextEdit::singleline(&mut self.search)
                        .hint_text("Buscar (ex.: webhook)")
                        .margin(egui::vec2(8.0, 6.0))
                        .desired_width(ui.available_width() - 48.0),
                );
                let searching = !self.search.trim().is_empty();
                clear = ui
                    .add_enabled(
                        searching,
                        egui::Button::new("x").min_size(egui::vec2(28.0, find.rect.height())),
                    )
                    .on_hover_text("Limpar a busca (Esc)")
                    .clicked();
                find
            })
            .inner;
        if ctx.input(|i| i.modifiers.command && i.key_pressed(egui::Key::F)) {
            find.request_focus();
        }
        if clear || (!self.search.trim().is_empty() && ctx.input(|i| i.key_pressed(egui::Key::Escape))) {
            self.search.clear();
        }
        ui.add_space(8.0);
        let hits = nav::search(&self.search);
        let searching = !self.search.trim().is_empty();
        let mut chosen = None;
        egui::ScrollArea::vertical().id_salt("nav").show(ui, |ui| {
            for s in Section::ALL {
                let label = if searching {
                    match hits.iter().find(|h| h.section == s) {
                        Some(h) if h.actions.is_empty() => s.title().to_string(),
                        Some(h) => format!("{}  ({})", s.title(), h.actions.len()),
                        None => continue,
                    }
                } else {
                    s.title().to_string()
                };
                if theme::nav_item(ui, !searching && self.section == s, &label).clicked() {
                    chosen = Some(s);
                }
            }
            if searching && hits.is_empty() {
                ui.label(theme::caption("Nenhuma categoria."));
            }
        });
        if let Some(s) = chosen {
            self.go(s);
        }
    }

    /// The output: a toolbar (history, Copiar, Limpar, Abrir em janela) over the text of the shown run, monospace,
    /// no wrapping, scrollable both ways, following the end while it streams.
    fn output_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, in_window: bool) {
        ui.horizontal(|ui| {
            if !in_window {
                let colour = if self.status.ends_with(": falhou") {
                    theme::ERROR
                } else if self.status.ends_with(": feito") {
                    theme::OK
                } else {
                    theme::TEXT
                };
                ui.colored_label(colour, &self.status);
            }
            ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                let label = if in_window { "Fechar janela" } else { "Abrir em janela" };
                if ui
                    .button(label)
                    .on_hover_text("A saída inteira numa janela própria, que pode ser maximizada")
                    .clicked()
                {
                    self.out_window = !self.out_window;
                }
                if ui
                    .button("Limpar")
                    .on_hover_text("Apaga as saídas guardadas (as que ainda rodam ficam)")
                    .clicked()
                {
                    self.out.clear();
                }
                if ui.button("Copiar").clicked() {
                    if let Some(e) = self.out.shown() {
                        ctx.copy_text(format!("{}\n{}", e.heading(), e.text));
                    }
                }
                let shown = self
                    .out
                    .shown()
                    .map(|e| e.heading())
                    .unwrap_or_else(|| "Nenhuma saída ainda".into());
                let mut pick = self.out.pinned();
                egui::ComboBox::from_id_salt(("out_history", in_window))
                    .width(260.0)
                    .selected_text(egui::RichText::new(shown).color(theme::TEXT))
                    .show_ui(ui, |ui| {
                        ui.selectable_value(&mut pick, None, "Seguir a mais recente");
                        for e in self.out.history() {
                            ui.selectable_value(&mut pick, Some(e.id), e.heading());
                        }
                    })
                    .response
                    .on_hover_text(format!("As últimas {} saídas", output::KEEP));
                if pick != self.out.pinned() {
                    self.out.pin(pick);
                }
                if !in_window {
                    ui.label(theme::caption(&format!("v{VERSION}  {}", self.update_note)));
                }
            });
        });
        let entry = self.out.shown();
        if let Some(e) = entry {
            ui.horizontal(|ui| {
                let colour = match e.state {
                    RunState::Running => theme::WARN,
                    RunState::Ok => theme::OK,
                    RunState::Failed => theme::ERROR,
                };
                ui.colored_label(colour, e.heading());
                if e.state == RunState::Running {
                    ui.add(egui::Spinner::new().color(theme::MUTED));
                }
                if e.cut {
                    ui.label(theme::caption("(o começo foi cortado: só o fim fica guardado)"));
                }
            });
        }
        theme::well().show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.set_min_height(ui.available_height());
            egui::ScrollArea::both()
                .id_salt(("out_text", in_window))
                .auto_shrink([false, false])
                .stick_to_bottom(true)
                .show(ui, |ui| {
                    let mut text: &str = entry.map(|e| e.text.as_str()).unwrap_or("");
                    let mut layouter = |ui: &egui::Ui, s: &str, _wrap: f32| {
                        let job = egui::text::LayoutJob::simple(
                            s.to_owned(),
                            egui::FontId::monospace(13.0),
                            theme::TEXT,
                            f32::INFINITY,
                        );
                        ui.fonts(|f| f.layout_job(job))
                    };
                    ui.add(
                        egui::TextEdit::multiline(&mut text)
                            .font(egui::TextStyle::Monospace)
                            .frame(false)
                            .desired_width(ui.available_width())
                            .layouter(&mut layouter),
                    );
                });
        });
    }

    /// The output in its own window (a native window where the system allows, else a window inside this one).
    fn output_window(&mut self, ctx: &egui::Context) {
        if !self.out_window {
            return;
        }
        let id = egui::ViewportId::from_hash_of("cinders_output");
        let builder = egui::ViewportBuilder::default()
            .with_title("Saída do Cinders Admin")
            .with_inner_size([1100.0, 720.0])
            .with_min_inner_size([480.0, 320.0])
            .with_icon(Arc::new(theme::icon()));
        ctx.show_viewport_immediate(id, builder, |vctx, class| {
            if class == egui::ViewportClass::Embedded {
                let mut open = true;
                egui::Window::new("Saída")
                    .open(&mut open)
                    .resizable(true)
                    .default_size([900.0, 560.0])
                    .show(vctx, |ui| self.output_ui(ui, vctx, true));
                if !open {
                    self.out_window = false;
                }
                return;
            }
            egui::CentralPanel::default()
                .frame(
                    egui::Frame::none()
                        .fill(egui::Color32::from_rgb(19, 15, 13))
                        .inner_margin(egui::Margin::symmetric(12.0, 10.0)),
                )
                .show(vctx, |ui| self.output_ui(ui, vctx, true));
            if vctx.input(|i| i.viewport().close_requested()) {
                self.out_window = false;
            }
        });
    }

    /// Keeps the answer of `engine-build status`; the window follows the build while it is queued or in progress.
    fn set_engine(&mut self, text: &str) {
        let e = EngineInfo::parse(text);
        if !e.valid() {
            // a refusal (no token, ssh trouble): shown in the status line, the follow-up goes on if it was on
            let why = engine::refusal(text);
            self.status = format!(
                "Recompilar engine: {}",
                if why.is_empty() {
                    text.lines().next().unwrap_or("sem resposta")
                } else {
                    why
                }
            );
            return;
        }
        self.engine_watch = e.running();
        self.engine_info = Some(e);
    }

    /// While a build runs: asks `engine-build status` every 20 s in the background (the output pane stays quiet).
    fn poll_engine(&mut self, ctx: &egui::Context) {
        if !self.engine_watch || !self.cfg.configured() {
            return;
        }
        let now = self.started.elapsed().as_millis() as u64;
        if self.engine_poller.due(now) {
            self.engine_poller.started(now);
            let (cfg, tx, c) = (self.cfg.clone(), self.tx.clone(), ctx.clone());
            std::thread::spawn(move || {
                let o = ssh::exec(&cfg, &ssh::ctl_line(&cfg, "engine-build status"), 90, None);
                let _ = tx.send(Msg::EnginePoll(o.text));
                c.request_repaint();
            });
        } else if let Some(ms) = self.engine_poller.wait_ms(now) {
            ctx.request_repaint_after(std::time::Duration::from_millis(ms.clamp(500, 5000)));
        }
    }

    /// The answer of "Atualizar estado" as a card: headline, lines, and a pointer to Atualizar servidor when it is done.
    fn engine_card_ui(&mut self, ui: &mut egui::Ui) {
        let Some(e) = &self.engine_info else { return };
        ui.add_space(8.0);
        theme::well().show(ui, |ui| {
            ui.set_width(ui.available_width());
            let colour = match e.state() {
                "success" if e.newer() => theme::OK,
                "failure" | "unknown" => theme::ERROR,
                "queued" | "in_progress" => theme::WARN,
                _ => theme::TEXT,
            };
            ui.horizontal(|ui| {
                ui.colored_label(colour, e.headline());
                if e.running() {
                    ui.add(egui::Spinner::new().color(theme::MUTED));
                }
            });
            for line in e.lines() {
                let colour = if line.starts_with("Sem token") || line.starts_with("Parou em") {
                    theme::WARN
                } else if line.starts_with("Próximo passo") {
                    theme::OK
                } else {
                    theme::TEXT
                };
                ui.label(egui::RichText::new(line).color(colour));
            }
        });
        ui.add_space(8.0);
    }

    /// The answer of "Verificar" as a card: headline, summary lines and the last run.
    fn update_card_ui(&mut self, ui: &mut egui::Ui) {
        let Some(u) = &self.update_info else { return };
        ui.add_space(8.0);
        theme::well().show(ui, |ui| {
            ui.set_width(ui.available_width());
            let (colour, badge) = if u.available() {
                (theme::WARN, "Atualização disponível")
            } else {
                (theme::OK, "Em dia")
            };
            ui.horizontal(|ui| {
                ui.colored_label(colour, badge);
                if u.running() {
                    ui.colored_label(theme::WARN, "Em andamento");
                }
            });
            for line in u.summary_lines() {
                let colour = if line.starts_with("Atenção") || line.contains("não consegui") {
                    theme::WARN
                } else if line.starts_with("  •") {
                    theme::MUTED
                } else {
                    theme::TEXT
                };
                ui.label(egui::RichText::new(line).color(colour));
            }
            let last = u.last_run();
            if !last.is_empty() {
                ui.label(theme::caption(&last));
            }
        });
        ui.add_space(8.0);
    }

    /// One card per report. "Usar no Fechar relatório" fills the id of the action below, like a typed value.
    fn reports_ui(&mut self, ui: &mut egui::Ui) {
        let Some(list) = &self.reports else { return };
        let close = ACTIONS.iter().position(|a| a.template.starts_with("feedback-close"));
        let mut fill: Option<u32> = None;
        ui.add_space(8.0);
        ui.label(theme::caption(&infos::reports_summary(list)));
        for r in list {
            theme::well().show(ui, |ui| {
                ui.set_width(ui.available_width());
                ui.horizontal_wrapped(|ui| {
                    ui.label(theme::card_title(&format!("#{}", r.id)));
                    ui.colored_label(theme::TEXT, infos::category_label(&r.category));
                    let (colour, word) = if r.closed {
                        (theme::MUTED, "Fechado")
                    } else {
                        (theme::WARN, "Aberto")
                    };
                    ui.colored_label(colour, word);
                    ui.label(theme::caption(&r.when));
                });
                let mut meta = format!("posição {}", r.pos);
                if !r.who.is_empty() {
                    meta.push_str(&format!("  ·  {}", r.who));
                }
                ui.label(theme::caption(&meta));
                ui.label(egui::RichText::new(&r.text).color(theme::TEXT));
                if r.closed {
                    ui.label(theme::caption(&format!("Fechado: {}", r.closed_note)));
                } else if close.is_some() && ui.button("Usar no Fechar relatório").clicked() {
                    fill = Some(r.id);
                }
            });
            ui.add_space(4.0);
        }
        if let (Some(id), Some(i)) = (fill, close) {
            let a = &ACTIONS[i];
            let vals = self
                .values
                .entry(i)
                .or_insert_with(|| a.params.iter().map(|p| p.default.to_string()).collect());
            if let Some(v) = vals.first_mut() {
                *v = id.to_string();
            }
            self.status =
                format!("Relatório #{id} no campo de Fechar relatório (confira a nota e clique em Fechar relatório).");
        }
    }

    fn catalog_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.label(
            "Tudo o que o painel de admin faz dentro do jogo, como o personagem admin de Config (pode estar offline).",
        );
        ui.horizontal(|ui| {
            if ui.button("Atualizar lista").clicked() {
                if self.cfg.actor.is_empty() {
                    self.status = "Defina o personagem admin em Config.".into();
                } else {
                    self.catalog_note = "Pedindo a lista ao jogo (até 15 s)...".into();
                    let (cfg, tx, c) = (self.cfg.clone(), self.tx.clone(), ctx.clone());
                    std::thread::spawn(move || {
                        let o = ssh::exec(
                            &cfg,
                            &ssh::ctl_line(&cfg, &format!("catalog {}", ssh::sq(&cfg.actor))),
                            40,
                            None,
                        );
                        let r = if o.code == 0 {
                            catalog::parse_catalog(&o.text)
                        } else {
                            Err(o.text)
                        };
                        let _ = tx.send(Msg::Catalog(r));
                        c.request_repaint();
                    });
                }
            }
            ui.add(egui::TextEdit::singleline(&mut self.filter).hint_text("Buscar (ban, item, spawn)"));
        });
        ui.label(&self.catalog_note);
        let q = self.filter.to_lowercase();
        let mut cats: Vec<String> = Vec::new();
        for a in &self.catalog {
            if !cats.contains(&a.cat) {
                cats.push(a.cat.clone());
            }
        }
        let mut chosen = None;
        egui::ScrollArea::vertical()
            .id_salt("game")
            .max_height(260.0)
            .show(ui, |ui| {
                for c in &cats {
                    let items: Vec<usize> = self
                        .catalog
                        .iter()
                        .enumerate()
                        .filter(|(_, a)| {
                            &a.cat == c
                                && (q.is_empty()
                                    || format!("{} {} {} {}", a.cat, a.id, a.name, a.description)
                                        .to_lowercase()
                                        .contains(&q))
                        })
                        .map(|(i, _)| i)
                        .collect();
                    if items.is_empty() {
                        continue;
                    }
                    egui::CollapsingHeader::new(format!("{c} ({})", items.len()))
                        .open(if q.is_empty() { None } else { Some(true) })
                        .show(ui, |ui| {
                            for i in items {
                                let a = &self.catalog[i];
                                if ui
                                    .selectable_label(self.game_sel == Some(i), &a.name)
                                    .on_hover_text(&a.description)
                                    .clicked()
                                {
                                    chosen = Some(i);
                                }
                            }
                        });
                }
            });
        if let Some(i) = chosen {
            self.game_sel = Some(i);
            self.game_values = self.catalog[i].params.iter().map(|_| String::new()).collect();
        }
        if let Some(i) = self.game_sel.filter(|i| *i < self.catalog.len()) {
            let a = self.catalog[i].clone();
            ui.separator();
            ui.label(theme::card_title(&format!("{} > {}", a.cat, a.name)));
            ui.label(&a.description);
            for (p, v) in a.params.iter().zip(self.game_values.iter_mut()) {
                ui.horizontal(|ui| {
                    ui.label(&p.label);
                    if p.ptype == "bool" {
                        let mut b = v == "true";
                        ui.checkbox(&mut b, "");
                        *v = b.to_string();
                    } else if !p.options.is_empty() {
                        egui::ComboBox::from_id_salt(&p.name)
                            .selected_text(v.clone())
                            .show_ui(ui, |ui| {
                                for (val, label) in &p.options {
                                    ui.selectable_value(v, val.clone(), label);
                                }
                            });
                    } else {
                        ui.text_edit_singleline(v);
                    }
                });
            }
            if theme::primary_button(ui, "Executar").clicked() {
                match catalog::build_params(&a, &self.game_values) {
                    Err(e) => self.status = e,
                    Ok(json) => {
                        let line = format!(
                            "panel {} {} {}",
                            ssh::sq(&self.cfg.actor),
                            ssh::sq(&a.id),
                            ssh::sq(&json)
                        );
                        let p = Pending {
                            title: format!("{} > {}", a.cat, a.name),
                            line,
                            stdin: None,
                            timeout: 40,
                            reload: None,
                            warn: if a.risky {
                                format!("Executar {} {json}?", a.name)
                            } else {
                                String::new()
                            },
                            panel_answer: false,
                            answer: Answer::Plain,
                        };
                        if a.risky {
                            self.confirm = Some(p);
                        } else {
                            self.run(ctx, p);
                        }
                    }
                }
            }
        }
    }

    /// Starts one refresh of the live page when the timer says so; otherwise asks for a wake-up at the next one.
    fn poll_live(&mut self, ctx: &egui::Context) {
        let now = self.started.elapsed().as_millis() as u64;
        if self.cfg.configured() && self.poller.due(now) {
            self.poller.started(now);
            let (cfg, tx, c, n) = (self.cfg.clone(), self.tx.clone(), ctx.clone(), self.live_lines);
            std::thread::spawn(move || {
                let line = live::remote_line(
                    &ssh::ctl_line(&cfg, "status"),
                    &ssh::ctl_line(&cfg, "players"),
                    &ssh::ctl_line(&cfg, &format!("logs {n}")),
                );
                let o = ssh::exec(&cfg, &line, 40, None);
                let first = |t: &str| t.lines().next().unwrap_or("").to_string();
                let r = match live::split(&o.text) {
                    None => Err(first(&o.text)),
                    Some(s) => {
                        let status = Status::parse(&s.status);
                        if status.valid() {
                            Ok(LiveData {
                                status,
                                players: cards::parse_players(&s.players),
                                logs: s.logs,
                                at: Self::now_unix(),
                            })
                        } else {
                            Err(first(&s.status))
                        }
                    }
                };
                let _ = tx.send(Msg::Live(r));
                c.request_repaint();
            });
        } else if let Some(ms) = self.poller.wait_ms(now) {
            ctx.request_repaint_after(std::time::Duration::from_millis(ms.clamp(200, 5000)));
        }
    }

    fn live_top_ui(&mut self, ui: &mut egui::Ui) {
        let (gold, red, green) = (theme::WARN, theme::ERROR, theme::OK);
        if !self.cfg.configured() {
            ui.colored_label(gold, "Preencha o servidor, o usuário e a chave em Config.");
        }
        ui.horizontal_wrapped(|ui| {
            ui.label(theme::card_title("Ao vivo"));
            ui.label("Atualizar a cada");
            egui::ComboBox::from_id_salt("live_interval")
                .selected_text(format!("{} s", self.poller.interval_secs))
                .show_ui(ui, |ui| {
                    for i in live::INTERVALS {
                        ui.selectable_value(&mut self.poller.interval_secs, i, format!("{i} s"));
                    }
                });
            ui.checkbox(&mut self.poller.paused, "Pausar");
            if ui.button("Atualizar agora").clicked() {
                self.poller.refresh_now();
            }
            if self.poller.running() {
                ui.spinner();
            }
            match self.live_at {
                Some(t) => {
                    let ago = (Self::now_unix() - t).max(0);
                    ui.weak(format!("atualizado há {}", cards::duration(ago)));
                }
                None => {
                    ui.weak("ainda sem dados");
                }
            }
        });
        if self.poller.paused {
            ui.colored_label(gold, "Pausado: nada é pedido ao servidor.");
        }
        if !self.live_note.is_empty() {
            ui.colored_label(red, &self.live_note);
        }
        if let Some(s) = self.live_status.clone() {
            let st = s.state();
            let on = st == State::Online;
            ui.horizontal_wrapped(|ui| {
                let c = match st {
                    State::Online => green,
                    State::Starting | State::Stopping | State::OnlineNoUnit => gold,
                    _ => red,
                };
                theme::state_word(ui, st.badge(), c, on);
                if let (true, Some(up)) = (on, s.uptime_sec(Self::now_unix())) {
                    ui.label(format!("no ar há {}", cards::duration(up)));
                }
                ui.label(format!("Jogadores {}", s.players_text()));
                match s.errors() {
                    Some(0) => ui.label("Erros: nenhum"),
                    Some(n) => ui.colored_label(red, format!("Erros: {n}")),
                    None => ui.label("Erros: ?"),
                };
                ui.label(format!("Memória {}", s.mem_text()));
                ui.label(format!("Carga {}", s.load_text()));
                ui.label(format!("Disco {}", s.disk_text()));
            });
        }
        sub_block(ui, &format!("Online agora ({})", self.live_players.len()), |ui| {
            players_list(ui, &self.live_players)
        });
    }

    fn live_console_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let (gold, red) = (theme::WARN, theme::ERROR);
        ui.horizontal_wrapped(|ui| {
            ui.label(theme::card_title("Console do jogo"));
            let before = self.live_lines;
            egui::ComboBox::from_id_salt("live_lines")
                .selected_text(format!("{} linhas", self.live_lines))
                .show_ui(ui, |ui| {
                    for n in live::LOG_LINES {
                        ui.selectable_value(&mut self.live_lines, n, format!("{n} linhas"));
                    }
                });
            if before != self.live_lines {
                self.poller.refresh_now();
            }
            ui.add(
                egui::TextEdit::singleline(&mut self.live_filter)
                    .hint_text("Filtrar (error, Bob)")
                    .desired_width(180.0),
            );
            ui.checkbox(&mut self.live_follow, "Seguir o fim");
            if ui.button("Copiar").clicked() {
                ctx.copy_text(live::filter_lines(&self.live_logs, &self.live_filter).join("\n"));
            }
        });
        let lines = live::filter_lines(&self.live_logs, &self.live_filter);
        theme::well().show(ui, |ui| {
            ui.set_width(ui.available_width());
            egui::ScrollArea::vertical()
                .id_salt("live_log")
                .max_height(360.0)
                .auto_shrink([false, false])
                .stick_to_bottom(self.live_follow)
                .show(ui, |ui| {
                    if lines.is_empty() {
                        ui.weak("Sem linhas.");
                    }
                    ui.spacing_mut().item_spacing.y = 2.0;
                    for l in &lines {
                        let t = egui::RichText::new(l).monospace();
                        match live::level(l) {
                            Level::Error => ui.label(t.color(red)),
                            Level::Warn => ui.label(t.color(gold)),
                            Level::Normal => ui.label(t),
                        };
                    }
                });
        });
        ui.weak("O mesmo que Painel > Estado, Jogadores > Quem está online e Logs > Console, pedidos juntos em uma conexão. Só atualiza enquanto esta página está aberta.");
    }

    /// The card "Recarregar um arquivo": one config table into the running game.
    fn reload_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.label(theme::card_title("Recarregar um arquivo"));
        ui.label(
            "Copia uma tabela *_config.lua do servidor para o jogo que está rodando, sem /reload. Precisa do \
             personagem admin de Config (grupo 6). Scripts não recarregam sozinhos: precisam de Recarregar scripts \
             (abaixo, Server > Reload system) ou de reinício.",
        );
        ui.horizontal_wrapped(|ui| {
            if ui.button("Listar arquivos").clicked() {
                self.reload_note = "Pedindo a lista...".into();
                let (cfg, tx, c) = (self.cfg.clone(), self.tx.clone(), ctx.clone());
                std::thread::spawn(move || {
                    let o = ssh::exec(&cfg, &ssh::ctl_line(&cfg, "reload-files"), 40, None);
                    let r = if o.code == 0 {
                        Ok(reload::parse_list(&o.text))
                    } else {
                        Err(o.text.lines().next().unwrap_or("").to_string())
                    };
                    let _ = tx.send(Msg::ReloadList(r));
                    c.request_repaint();
                });
            }
            ui.add(
                egui::TextEdit::singleline(&mut self.reload_pick)
                    .hint_text("pace_config")
                    .desired_width(220.0),
            );
            if ui
                .button("Quais estão vivos?")
                .on_hover_text("Lista o que o jogo já pode recarregar")
                .clicked()
            {
                self.reload_start(ctx, "");
            }
        });
        let q = self.reload_pick.trim().to_lowercase();
        let shown: Vec<String> = self
            .reload_names
            .iter()
            .filter(|n| q.is_empty() || n.contains(&q))
            .take(40)
            .cloned()
            .collect();
        if !shown.is_empty() {
            egui::ScrollArea::vertical()
                .id_salt("reload_names")
                .max_height(120.0)
                .show(ui, |ui| {
                    ui.horizontal_wrapped(|ui| {
                        for n in &shown {
                            if ui.selectable_label(self.reload_pick.trim() == n, n).clicked() {
                                self.reload_pick = n.clone();
                            }
                        }
                    });
                });
        }
        ui.weak(&self.reload_note);
        match reload::normalize(&self.reload_pick) {
            Ok(name) => {
                let k = reload::kind(&name);
                ui.label(reload::note(k));
                if ui
                    .add_enabled(
                        k == reload::Kind::Config,
                        egui::Button::new(
                            egui::RichText::new(format!("Recarregar {name}"))
                                .color(egui::Color32::from_rgb(255, 240, 215)),
                        )
                        .fill(theme::EMBER_LO),
                    )
                    .clicked()
                {
                    self.reload_start(ctx, &name);
                }
            }
            Err(e) if !self.reload_pick.trim().is_empty() => {
                ui.colored_label(theme::ERROR, e);
            }
            Err(_) => {}
        }
    }

    fn reload_start(&mut self, ctx: &egui::Context, name: &str) {
        match reload::args(&self.cfg.actor, name) {
            Err(e) => self.status = e,
            Ok(line) => {
                let p = Pending {
                    title: if name.is_empty() {
                        "Recarregar > arquivos vivos".into()
                    } else {
                        format!("Recarregar > {name}")
                    },
                    line,
                    stdin: None,
                    timeout: 40,
                    reload: None,
                    warn: format!(
                        "Recarregar {name} no jogo em andamento? Os valores novos valem para todos os jogadores agora."
                    ),
                    panel_answer: true,
                    answer: Answer::Plain,
                };
                if name.is_empty() {
                    self.run(ctx, p);
                } else {
                    self.confirm = Some(p);
                }
            }
        }
    }

    fn settings_ui(&mut self, ui: &mut egui::Ui) {
        theme::card_full(ui, |ui| {
            ui.label(theme::card_title("Servidor"));
            ui.add_space(2.0);
            let w = (ui.available_width() - 250.0).clamp(240.0, 520.0);
            egui::Grid::new("cfg")
                .num_columns(2)
                .spacing([20.0, 9.0])
                .min_col_width(210.0)
                .show(ui, |ui| {
                    let row = |ui: &mut egui::Ui, label: &str, v: &mut String, mono: bool| {
                        ui.label(theme::caption(label));
                        let mut e = egui::TextEdit::singleline(v).desired_width(w);
                        if mono {
                            e = e.font(egui::TextStyle::Monospace);
                        }
                        ui.add(e);
                        ui.end_row();
                    };
                    row(ui, "Endereço (host)", &mut self.cfg.host, false);
                    ui.label(theme::caption("Porta"));
                    let mut port = self.cfg.port as u32;
                    ui.add(egui::DragValue::new(&mut port).range(1..=65535));
                    self.cfg.port = port as u16;
                    ui.end_row();
                    row(ui, "Usuário SSH", &mut self.cfg.user, false);
                    row(ui, "Arquivo da chave privada", &mut self.cfg.key_path, true);
                    row(ui, "Caminho do chaos-ctl.sh (na VPS)", &mut self.cfg.ctl_path, true);
                    row(ui, "Personagem admin", &mut self.cfg.actor, false);
                });
        });
        ui.add_space(8.0);
        theme::card_full(ui, |ui| {
            ui.checkbox(&mut self.cfg.auto_update, "Procurar versão nova ao abrir");
            ui.horizontal(|ui| {
                if theme::primary_button(ui, "Salvar").clicked() {
                    self.status = match config::save(&self.cfg) {
                        Ok(()) => format!("Salvo em {}", config::path().display()),
                        Err(e) => format!("Não salvou: {e}"),
                    };
                }
                if ui.button("Procurar versão nova").clicked() {
                    self.check_update();
                }
            });
            ui.add_space(2.0);
            ui.label(theme::caption(&format!("Arquivo: {}", config::path().display())));
        });
        ui.add_space(8.0);
        theme::card_full(ui, |ui| {
            ui.label(theme::card_title("Chave deste PC"));
            ui.label(theme::caption(
                "Cada aparelho tem a sua chave: o celular e este PC. O comando de instalação adiciona esta e mantém as outras.",
            ));
            ui.add_space(4.0);
            ui.horizontal(|ui| {
                if self.cfg.key_path.trim().is_empty() && ui.button("Gerar chave").clicked() {
                    let path = keys::default_path();
                    self.status = match keys::generate(&path) {
                        Ok(_) => {
                            self.cfg.key_path = path.to_string_lossy().into_owned();
                            match config::save(&self.cfg) {
                                Ok(()) => "Chave gerada e salva. Agora copie o comando de instalação.".into(),
                                Err(e) => format!(
                                    "Chave gerada em {}, mas as configurações não salvaram: {e}",
                                    path.display()
                                ),
                            }
                        }
                        Err(e) => format!("Não gerou a chave: {e}"),
                    };
                }
                if theme::primary_button(ui, "Copiar comando de instalação").clicked() {
                    self.status = match keys::public_of(std::path::Path::new(self.cfg.key_path.trim())) {
                        Ok(public) => {
                            ui.ctx().copy_text(keys::install_command(&public, &self.cfg.ctl_path));
                            "Comando copiado. Cole no terminal da VPS como root (ou com sudo).".into()
                        }
                        Err(e) => format!("Sem comando: {e}"),
                    };
                }
            });
            ui.add_space(2.0);
            ui.label(theme::caption(
                "Sem arquivo de chave? Gerar chave cria uma ao lado das configurações. O comando sai da chave privada, nunca de um .pub antigo.",
            ));
        });
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        while let Ok(m) = self.rx.try_recv() {
            match m {
                Msg::Chunk { id, text } => self.out.append(id, &text),
                Msg::Done {
                    id,
                    title,
                    text,
                    ok,
                    answer,
                } => {
                    self.busy = self.busy.saturating_sub(1);
                    match answer {
                        Answer::Update if ok => {
                            let u = UpdateInfo::parse(&text);
                            self.update_info = u.valid().then_some(u);
                        }
                        Answer::Feedback if ok => self.reports = Some(infos::parse_reports(&text)),
                        // status exits 1 when GitHub could not be read, but still prints state=unknown and why
                        Answer::Engine => self.set_engine(&text),
                        Answer::EngineStart if ok => {
                            self.engine_watch = true;
                            self.engine_poller.refresh_now();
                        }
                        _ => {}
                    }
                    self.out.finish(id, text.trim_end(), ok);
                    self.status = format!("{title}: {}", if ok { "feito" } else { "falhou" });
                }
                Msg::CardStatus(r) => {
                    self.cards_busy = self.cards_busy.saturating_sub(1);
                    match r {
                        Ok(s) => self.card_status = Some(s),
                        Err(e) => {
                            self.card_status = None;
                            self.card_status_note = format!("Sem estado: {e}");
                        }
                    }
                }
                Msg::CardPlayers(r) => {
                    self.cards_busy = self.cards_busy.saturating_sub(1);
                    match r {
                        Ok(p) => self.card_players = Some(p),
                        Err(e) => self.status = format!("Jogadores: {e}"),
                    }
                }
                Msg::CardMetrics(r) => {
                    self.cards_busy = self.cards_busy.saturating_sub(1);
                    match r {
                        Ok(m) => self.card_metrics = Some(m),
                        Err(e) => {
                            self.card_metrics = None;
                            self.card_metrics_note = format!("Sem métricas: {e}");
                        }
                    }
                }
                Msg::CardHealth(r) => {
                    self.cards_busy = self.cards_busy.saturating_sub(1);
                    match r {
                        Ok(h) => self.card_health = Some(h),
                        Err(e) => {
                            self.card_health = None;
                            self.card_health_note = format!("Sem dados: {e}");
                        }
                    }
                }
                Msg::Live(r) => {
                    self.poller.finished();
                    match r {
                        Ok(d) => {
                            self.live_status = Some(d.status);
                            self.live_players = d.players;
                            self.live_logs = d.logs;
                            self.live_at = Some(d.at);
                            self.live_note.clear();
                        }
                        Err(e) => self.live_note = format!("Sem resposta: {e}"),
                    }
                }
                Msg::EnginePoll(text) => {
                    self.engine_poller.finished();
                    self.set_engine(&text);
                }
                Msg::ReloadList(r) => match r {
                    Ok(v) => {
                        self.reload_note = format!("{} arquivos de configuração.", v.len());
                        self.reload_names = v;
                    }
                    Err(e) => self.reload_note = format!("Sem lista: {e}"),
                },
                Msg::Catalog(r) => match r {
                    Ok((a, g)) => {
                        self.catalog_note = format!("{} comandos (grupo {g}).", a.len());
                        self.catalog = a;
                    }
                    Err(e) => self.catalog_note = format!("Sem lista: {}", e.lines().next().unwrap_or("")),
                },
                Msg::Update(r) => match r {
                    Ok(Some(f)) => {
                        self.update_note = format!("Versão nova: {}", f.tag);
                        self.update = Some(f);
                    }
                    Ok(None) => self.update_note = format!("Versão {VERSION}: em dia"),
                    Err(e) => self.update_note = format!("Sem checagem de versão: {e}"),
                },
                Msg::Installed(r) => match r {
                    Ok(()) => {
                        // the new program starts without a console (update::restart), then this one ends
                        match std::env::current_exe().map(|exe| update::restart(&exe)) {
                            Ok(Ok(())) => std::process::exit(0),
                            Ok(Err(e)) | Err(e) => {
                                self.update_note = format!("Atualizado; abra o app de novo ({e})");
                            }
                        }
                    }
                    Err(e) => self.update_note = format!("Atualização falhou: {e}"),
                },
            }
        }

        if self.section == Section::LiveView && self.search.trim().is_empty() {
            self.poll_live(ctx);
        }
        self.poll_engine(ctx);

        egui::TopBottomPanel::top("top")
            .frame(egui::Frame::none().fill(theme::BG))
            .show(ctx, |ui| {
                theme::header_bar(ui, &self.header, &self.icon, "Cinders Admin");
                theme::rule(ui);
                if let Some(f) = self.update.clone() {
                    egui::Frame::none()
                        .fill(egui::Color32::from_rgb(44, 32, 14))
                        .inner_margin(egui::Margin::symmetric(16.0, 8.0))
                        .show(ui, |ui| {
                            ui.set_width(ui.available_width());
                            ui.horizontal(|ui| {
                                ui.colored_label(theme::WARN, format!("Versão nova {} disponível", f.tag));
                                if theme::primary_button(ui, "Atualizar e reiniciar o app").clicked() {
                                    let (tx, c, cfg) = (self.tx.clone(), ctx.clone(), self.cfg.clone());
                                    self.update_note = "Baixando...".into();
                                    std::thread::spawn(move || {
                                        let _ = tx.send(Msg::Installed(update::install(&cfg, &f, VERSION).map(|_| ())));
                                        c.request_repaint();
                                    });
                                }
                            });
                        });
                }
            });
        // The sidebar runs the full height, left of the output panel and the page.
        egui::SidePanel::left("nav")
            .resizable(false)
            .exact_width(236.0)
            .frame(
                egui::Frame::none()
                    .fill(egui::Color32::from_rgb(19, 15, 13))
                    .stroke(egui::Stroke::new(1.0_f32, theme::CARD_EDGE))
                    .inner_margin(egui::Margin::symmetric(12.0, 12.0)),
            )
            .show(ctx, |ui| self.sidebar_ui(ui, ctx));
        // The output panel: under the page, about 40 % of the window at start, resized by dragging its top
        // edge. While the output has its own window, only the status line stays here.
        let screen_h = ctx.screen_rect().height();
        let out_frame = egui::Frame::none()
            .fill(egui::Color32::from_rgb(19, 15, 13))
            .stroke(egui::Stroke::new(1.0_f32, theme::CARD_EDGE))
            .inner_margin(egui::Margin {
                left: 16.0,
                right: 16.0,
                top: 10.0,
                bottom: 10.0,
            });
        if self.out_window {
            egui::TopBottomPanel::bottom("out_bar")
                .resizable(false)
                .frame(out_frame)
                .show(ctx, |ui| {
                    ui.horizontal(|ui| {
                        ui.colored_label(theme::TEXT, &self.status);
                        ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                            if ui.button("Trazer a saída de volta").clicked() {
                                self.out_window = false;
                            }
                            ui.label(theme::caption(&format!("v{VERSION}  {}", self.update_note)));
                        });
                    });
                });
        } else {
            egui::TopBottomPanel::bottom("out")
                .resizable(true)
                .default_height((screen_h * 0.4).max(180.0))
                .min_height(120.0)
                .max_height((screen_h * 0.85).max(240.0))
                .frame(out_frame)
                .show(ctx, |ui| {
                    theme::grip(ui);
                    self.output_ui(ui, ctx, false);
                });
        }
        egui::CentralPanel::default()
            .frame(
                egui::Frame::none()
                    .fill(theme::BG)
                    .inner_margin(egui::Margin::symmetric(16.0, 12.0)),
            )
            .show(ctx, |ui| {
                let searching = !self.search.trim().is_empty();
                ui.horizontal(|ui| {
                    let title = if searching {
                        "Busca".to_string()
                    } else {
                        self.section.title().to_string()
                    };
                    ui.label(egui::RichText::new(title).size(20.0).color(theme::TEXT));
                    if self.busy > 0 {
                        ui.add(egui::Spinner::new().color(theme::MUTED));
                        ui.label(theme::caption(&format!("{} rodando", self.busy)));
                    }
                });
                ui.add_space(6.0);
                egui::ScrollArea::vertical()
                    .id_salt(("main", searching, self.section.key()))
                    .auto_shrink([false, false])
                    .show(ui, |ui| {
                        if searching {
                            self.search_ui(ui, ctx);
                        } else {
                            self.section_ui(ui, ctx, self.section);
                        }
                    });
            });
        self.output_window(ctx);

        if let Some(p) = self.confirm.take() {
            let mut keep = true;
            let mut go = false;
            egui::Window::new("Confirmar")
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label(&p.warn);
                    ui.horizontal(|ui| {
                        go = theme::primary_button(ui, "Executar").clicked();
                        if go || ui.button("Cancelar").clicked() {
                            keep = false;
                        }
                    });
                });
            if go {
                self.run(ctx, p);
            } else if keep {
                self.confirm = Some(p);
            }
        }
    }
}

/// A sub heading inside a card with its content right under it (no collapsing: O383).
fn sub_block(ui: &mut egui::Ui, title: &str, add: impl FnOnce(&mut egui::Ui)) {
    ui.add_space(6.0);
    ui.label(egui::RichText::new(title).strong().color(theme::TEXT_2));
    add(ui);
}

/// O397: one bar per value from the left (None: a gap), scaled to max, in a strip `height` high.
fn bars(ui: &mut egui::Ui, values: &[Option<f64>], max: f64, colour: egui::Color32, height: f32) {
    let width = ui.available_width().max(100.0);
    let (rect, _) = ui.allocate_exact_size(egui::vec2(width, height), egui::Sense::hover());
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 2.0, theme::INPUT);
    if values.is_empty() {
        return;
    }
    let step = rect.width() / values.len() as f32;
    let gap = if step > 4.0 { 1.0 } else { 0.0 };
    let max = max.max(1.0);
    for (i, v) in values.iter().enumerate() {
        let Some(v) = v else { continue };
        let top = rect.bottom() - (rect.height() - 2.0) * (v / max).clamp(0.0, 1.0) as f32;
        let x = rect.left() + i as f32 * step;
        painter.rect_filled(
            egui::Rect::from_min_max(egui::pos2(x, top), egui::pos2(x + step - gap, rect.bottom())),
            0.0,
            colour,
        );
    }
}

/// A striped table with a header row.
fn grid(ui: &mut egui::Ui, id: &str, head: &[&str], rows: Vec<Vec<String>>) {
    if rows.is_empty() {
        ui.weak("Sem linhas.");
        return;
    }
    egui::Grid::new(id).striped(true).spacing([18.0, 2.0]).show(ui, |ui| {
        for h in head {
            ui.strong(*h);
        }
        ui.end_row();
        for r in rows {
            for v in r {
                ui.label(v);
            }
            ui.end_row();
        }
    });
}

fn players_list(ui: &mut egui::Ui, p: &[Player]) {
    if p.is_empty() {
        ui.label("Ninguém online.");
    }
    for x in p {
        ui.label(format!("{}  nível {}  {}", x.name, x.level, x.vocation));
    }
}

fn main() -> eframe::Result<()> {
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([1280.0, 800.0])
            .with_min_inner_size([900.0, 600.0])
            .with_icon(Arc::new(theme::icon()))
            .with_title("Cinders Admin"),
        ..Default::default()
    };
    eframe::run_native(
        "Cinders Admin",
        opts,
        Box::new(|cc| {
            theme::apply(&cc.egui_ctx);
            Ok(Box::new(App::new(&cc.egui_ctx)))
        }),
    )
}
