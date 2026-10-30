//! Cinders Admin for the PC: the window. Logic is in the library (commands, ssh, config, update, catalog).
use cinders_admin::cards::{self, Count, Metrics, Player, State, Status};
use cinders_admin::catalog::{self, PanelAction};
use cinders_admin::commands::{self, Action, Kind, Live, Tab, ACTIONS};
use cinders_admin::config::{self, Config};
use cinders_admin::live::{self, Level, Poller};
use cinders_admin::{reload, ssh, update};
use eframe::egui;
use std::collections::HashMap;
use std::sync::mpsc::{channel, Receiver, Sender};

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(PartialEq, Clone, Copy)]
enum Page {
    Tab(Tab),
    Live,
    Game,
    Settings,
}

/// One refresh of the live page.
struct LiveData {
    status: Status,
    players: Vec<Player>,
    logs: String,
    at: i64,
}

enum Msg {
    Done {
        title: String,
        text: String,
        ok: bool,
    },
    Catalog(Result<(Vec<PanelAction>, i64), String>),
    Update(Result<Option<update::Found>, String>),
    Installed(Result<(), String>),
    /// Status card: parsed `status` output, or why it failed.
    CardStatus(Result<Status, String>),
    CardPlayers(Result<Vec<Player>, String>),
    CardMetrics(Result<Metrics, String>),
    Live(Result<LiveData, String>),
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
}

struct App {
    cfg: Config,
    page: Page,
    values: HashMap<usize, Vec<String>>,
    output: String,
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
}

impl App {
    fn new() -> Self {
        let (tx, rx) = channel();
        let cfg = config::load();
        let mut app = App {
            page: if cfg.configured() {
                Page::Tab(Tab::Panel)
            } else {
                Page::Settings
            },
            cfg,
            values: HashMap::new(),
            output: String::new(),
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

    fn cards_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let gold = egui::Color32::from_rgb(230, 170, 60);
        let red = egui::Color32::from_rgb(220, 80, 60);
        let green = egui::Color32::from_rgb(90, 190, 100);
        ui.horizontal(|ui| {
            ui.heading("Servidor do jogo");
            if let Some(s) = &self.card_status {
                let st = s.state();
                let c = match st {
                    State::Online => green,
                    State::Starting | State::Stopping | State::OnlineNoUnit => gold,
                    _ => red,
                };
                ui.colored_label(c, st.badge());
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
                    _ if on => ui.label("No ar."),
                    _ => ui.label("O servidor não está rodando."),
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
                    ui.colored_label(red, "O serviço caiu. Veja os erros na aba Logs.");
                }
                egui::Grid::new("status_grid")
                    .num_columns(2)
                    .spacing([24.0, 4.0])
                    .show(ui, |ui| {
                        ui.label("Jogadores");
                        ui.horizontal(|ui| {
                            ui.strong(s.players_text());
                            if ui.small_button("Quem está online").clicked() {
                                self.card_call(ctx, "players", 30, 1);
                            }
                        });
                        ui.end_row();
                        ui.label("Erros desde o início");
                        match s.errors() {
                            Some(0) => ui.strong("nenhum"),
                            Some(n) => ui.colored_label(red, n.to_string()),
                            None => ui.strong("?"),
                        };
                        ui.end_row();
                        ui.label("Memória");
                        ui.horizontal(|ui| {
                            ui.strong(s.mem_text());
                            if let Some(p) = s.mem_percent() {
                                ui.add(egui::ProgressBar::new(p as f32 / 100.0).desired_width(120.0));
                            }
                        });
                        ui.end_row();
                        ui.label("Disco");
                        ui.horizontal(|ui| {
                            ui.strong(s.disk_text());
                            if let Some(p) = s.disk_percent() {
                                ui.add(egui::ProgressBar::new(p as f32 / 100.0).desired_width(120.0));
                            }
                        });
                        ui.end_row();
                        ui.label("Carga (1, 5, 15 min)");
                        ui.strong(s.load_text());
                        ui.end_row();
                        ui.label("Último backup");
                        ui.strong(s.backup_text());
                        ui.end_row();
                    });
            }
        }
        if let Some(p) = &self.card_players {
            egui::CollapsingHeader::new(format!("Online agora ({})", p.len()))
                .default_open(true)
                .show(ui, |ui| {
                    if p.is_empty() {
                        ui.label("Ninguém online.");
                    }
                    for x in p {
                        ui.label(format!("{}  nível {}  {}", x.name, x.level, x.vocation));
                    }
                });
        }
        ui.separator();
        self.metrics_ui(ui, ctx);
        ui.separator();
    }

    fn metrics_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.horizontal(|ui| {
            ui.heading("Métricas dos jogadores");
            if ui.button("Carregar métricas").clicked() {
                self.card_call(ctx, "metrics --json", 90, 2);
            }
        });
        let Some(m) = self.card_metrics.clone() else {
            ui.weak(&self.card_metrics_note);
            return;
        };
        if !m.ok {
            ui.colored_label(egui::Color32::from_rgb(220, 80, 60), m.error_text());
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
        egui::CollapsingHeader::new("Churn por faixa de nível").show(ui, |ui| {
            let rows = m
                .bands
                .iter()
                .map(|b| vec![b.band.clone(), b.gone.text(), b.active.text(), cards::pct(b.gone_pct)])
                .collect();
            table(ui, "m_bands", &["Faixa", "Saíram", "Ativos", "Saída"], rows);
        });
        egui::CollapsingHeader::new("Onde as pessoas param").show(ui, |ui| {
            table(
                ui,
                "m_stops",
                &["Lugar", "Saíram", "Faixa principal"],
                killer_rows(&m.stops),
            );
        });
        egui::CollapsingHeader::new("Mortes por área").show(ui, |ui| {
            table(
                ui,
                "m_areas",
                &["Área", "Mortes", "Faixa principal"],
                killer_rows(&m.areas),
            );
        });
        egui::CollapsingHeader::new("Mortes por monstro").show(ui, |ui| {
            table(
                ui,
                "m_monsters",
                &["Monstro", "Mortes", "Faixa principal"],
                killer_rows(&m.monsters),
            );
        });
        egui::CollapsingHeader::new(format!("Primeira sessão ({} personagens)", c(m.session_characters))).show(
            ui,
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
        egui::CollapsingHeader::new("Tempo mediano até o nível").show(ui, |ui| {
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
        egui::CollapsingHeader::new("Retorno por semana de criação").show(ui, |ui| {
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
        egui::CollapsingHeader::new("Primeiro uso de cada sistema").show(ui, |ui| {
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
        self.update_note = "Procurando versão nova...".into();
        std::thread::spawn(move || {
            let _ = tx.send(Msg::Update(update::check(VERSION)));
        });
    }

    fn run(&mut self, ctx: &egui::Context, p: Pending) {
        self.busy += 1;
        let cfg = self.cfg.clone();
        let tx = self.tx.clone();
        let ctx = ctx.clone();
        std::thread::spawn(move || {
            let remote = if p.line.starts_with("\u{0}raw ") {
                p.line[5..].to_string()
            } else {
                ssh::ctl_line(&cfg, &p.line)
            };
            let mut o = ssh::exec(&cfg, &remote, p.timeout, p.stdin.as_deref());
            let mut ok = o.code == 0;
            if let (true, Some(sys)) = (ok, p.reload) {
                if cfg.actor.is_empty() {
                    o.text.push_str("\nApply live: set the admin character in Settings.\n");
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
                        "\nApply live (reload {sys}): {}\n{msg}\n",
                        if rok && r.code == 0 { "ok" } else { "FAILED" }
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
                o.text.push_str(&format!("\n[exit code {}]\n", o.code));
            }
            let _ = tx.send(Msg::Done {
                title: p.title,
                text: o.text,
                ok,
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
                };
                if a.confirm {
                    self.confirm = Some(p);
                } else {
                    self.run(ctx, p);
                }
            }
        }
    }

    fn actions_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context, tab: Tab) {
        let mut groups: Vec<&'static str> = Vec::new();
        for a in ACTIONS.iter().filter(|a| a.tab == tab) {
            if !groups.contains(&a.group) {
                groups.push(a.group);
            }
        }
        for g in groups {
            egui::CollapsingHeader::new(g)
                .default_open(g == "Servidor")
                .show(ui, |ui| {
                    for (i, a) in ACTIONS.iter().enumerate().filter(|(_, a)| a.tab == tab && a.group == g) {
                        ui.horizontal_wrapped(|ui| {
                            let vals = self
                                .values
                                .entry(i)
                                .or_insert_with(|| a.params.iter().map(|p| p.default.to_string()).collect());
                            for (p, v) in a.params.iter().zip(vals.iter_mut()) {
                                ui.label(p.label);
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
                                            egui::TextEdit::singleline(v).desired_width(
                                                if matches!(p.kind, Kind::Int(..)) { 60.0 } else { 220.0 },
                                            ),
                                        );
                                    }
                                }
                            }
                            let run = ui.button(a.label).on_hover_text(a.hint);
                            let mut go = run.clicked();
                            let mut live_go = false;
                            if let Live::Reload(sys) = a.live {
                                live_go = ui
                                    .button(format!("{} + Apply live", a.label))
                                    .on_hover_text(format!("then reloads {sys} in the game"))
                                    .clicked();
                            }
                            ui.weak(a.live.label());
                            if go || live_go {
                                go = true;
                            }
                            if go {
                                self.start(ctx, i, live_go);
                            }
                        });
                    }
                });
        }
    }

    fn game_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        self.reload_ui(ui, ctx);
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
            ui.heading(format!("{} > {}", a.cat, a.name));
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
            if ui.button("Executar").clicked() {
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

    fn live_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let gold = egui::Color32::from_rgb(230, 170, 60);
        let red = egui::Color32::from_rgb(220, 80, 60);
        let green = egui::Color32::from_rgb(90, 190, 100);
        if !self.cfg.configured() {
            ui.colored_label(gold, "Preencha o servidor, o usuário e a chave em Config.");
        }
        ui.horizontal_wrapped(|ui| {
            ui.heading("Ao vivo");
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
                ui.colored_label(c, st.badge());
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
        egui::CollapsingHeader::new(format!("Online agora ({})", self.live_players.len()))
            .default_open(true)
            .show(ui, |ui| {
                if self.live_players.is_empty() {
                    ui.label("Ninguém online.");
                }
                for x in &self.live_players {
                    ui.label(format!("{}  nível {}  {}", x.name, x.level, x.vocation));
                }
            });
        ui.separator();
        ui.horizontal_wrapped(|ui| {
            ui.strong("Console do jogo");
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
        egui::ScrollArea::vertical()
            .id_salt("live_log")
            .max_height(360.0)
            .auto_shrink([false, false])
            .stick_to_bottom(self.live_follow)
            .show(ui, |ui| {
                if lines.is_empty() {
                    ui.weak("Sem linhas.");
                }
                for l in &lines {
                    let t = egui::RichText::new(l).monospace();
                    match live::level(l) {
                        Level::Error => ui.label(t.color(red)),
                        Level::Warn => ui.label(t.color(gold)),
                        Level::Normal => ui.label(t),
                    };
                }
            });
        ui.weak("O mesmo que Painel > Estado, Jogadores e Logs > Console, pedidos juntos em uma conexão. Só atualiza enquanto esta página está aberta.");
    }

    /// The card "Recarregar um arquivo": one config table into the running game.
    fn reload_ui(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        ui.heading("Recarregar um arquivo");
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
                        egui::Button::new(format!("Recarregar {name}")),
                    )
                    .clicked()
                {
                    self.reload_start(ctx, &name);
                }
            }
            Err(e) if !self.reload_pick.trim().is_empty() => {
                ui.colored_label(egui::Color32::from_rgb(220, 80, 60), e);
            }
            Err(_) => {}
        }
        ui.separator();
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
        ui.heading("Servidor");
        egui::Grid::new("cfg").num_columns(2).show(ui, |ui| {
            ui.label("Endereço (host)");
            ui.text_edit_singleline(&mut self.cfg.host);
            ui.end_row();
            ui.label("Porta");
            let mut port = self.cfg.port as u32;
            ui.add(egui::DragValue::new(&mut port).range(1..=65535));
            self.cfg.port = port as u16;
            ui.end_row();
            ui.label("Usuário SSH");
            ui.text_edit_singleline(&mut self.cfg.user);
            ui.end_row();
            ui.label("Arquivo da chave privada");
            ui.text_edit_singleline(&mut self.cfg.key_path);
            ui.end_row();
            ui.label("Caminho do chaos-ctl.sh (na VPS)");
            ui.text_edit_singleline(&mut self.cfg.ctl_path);
            ui.end_row();
            ui.label("Personagem admin");
            ui.text_edit_singleline(&mut self.cfg.actor);
            ui.end_row();
        });
        ui.checkbox(&mut self.cfg.auto_update, "Procurar versão nova ao abrir");
        ui.horizontal(|ui| {
            if ui.button("Salvar").clicked() {
                self.status = match config::save(&self.cfg) {
                    Ok(()) => format!("Salvo em {}", config::path().display()),
                    Err(e) => format!("Não salvou: {e}"),
                };
            }
            if ui.button("Procurar versão nova").clicked() {
                self.check_update();
            }
        });
        ui.weak(format!("Arquivo: {}", config::path().display()));
        ui.weak("A chave é a mesma do app Android (aba Config > Copiar comando de instalação, ou ssh-keygen e chaos-ctl.sh install-admin).");
    }
}

impl eframe::App for App {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        while let Ok(m) = self.rx.try_recv() {
            match m {
                Msg::Done { title, text, ok } => {
                    self.busy = self.busy.saturating_sub(1);
                    self.output = format!("{} {}\n{}", if ok { "OK" } else { "ERRO" }, title, text.trim_end());
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
                    Ok(None) => self.update_note = format!("Versão {VERSION}: em dia."),
                    Err(e) => self.update_note = format!("Sem checagem de versão: {e}"),
                },
                Msg::Installed(r) => match r {
                    Ok(()) => {
                        if let Ok(exe) = std::env::current_exe() {
                            let _ = std::process::Command::new(exe).spawn();
                        }
                        std::process::exit(0);
                    }
                    Err(e) => self.update_note = format!("Atualização falhou: {e}"),
                },
            }
        }

        if self.page == Page::Live {
            self.poll_live(ctx);
        }

        egui::TopBottomPanel::top("top").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.heading("Cinders Admin");
                for t in Tab::ALL {
                    ui.selectable_value(&mut self.page, Page::Tab(t), t.title());
                }
                ui.selectable_value(&mut self.page, Page::Live, "Ao vivo");
                ui.selectable_value(&mut self.page, Page::Game, "Painel do jogo");
                ui.selectable_value(&mut self.page, Page::Settings, "Config");
                if self.busy > 0 {
                    ui.spinner();
                }
            });
            if let Some(f) = self.update.clone() {
                ui.horizontal(|ui| {
                    ui.colored_label(
                        egui::Color32::from_rgb(230, 170, 60),
                        format!("Versão nova {} disponível.", f.tag),
                    );
                    if ui.button("Atualizar e reiniciar o app").clicked() {
                        let (tx, c) = (self.tx.clone(), ctx.clone());
                        self.update_note = "Baixando...".into();
                        std::thread::spawn(move || {
                            let _ = tx.send(Msg::Installed(update::install(&f, VERSION).map(|_| ())));
                            c.request_repaint();
                        });
                    }
                });
            }
        });
        egui::TopBottomPanel::bottom("out")
            .resizable(true)
            .min_height(120.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.label(&self.status);
                    if ui.button("Copiar").clicked() {
                        ctx.copy_text(self.output.clone());
                    }
                    ui.weak(format!("v{VERSION}  {}", self.update_note));
                });
                egui::ScrollArea::both().stick_to_bottom(false).show(ui, |ui| {
                    ui.add(
                        egui::TextEdit::multiline(&mut self.output.as_str())
                            .font(egui::TextStyle::Monospace)
                            .desired_width(f32::INFINITY),
                    );
                });
            });
        egui::CentralPanel::default().show(ctx, |ui| {
            egui::ScrollArea::vertical()
                .id_salt("main")
                .show(ui, |ui| match self.page {
                    Page::Tab(t) => {
                        if t == Tab::Panel {
                            self.cards_ui(ui, ctx);
                        }
                        self.actions_ui(ui, ctx, t);
                        if t == Tab::Logs {
                            ui.separator();
                            ui.label("Terminal na VPS (qualquer comando do usuário SSH)");
                            ui.horizontal(|ui| {
                                ui.add(egui::TextEdit::singleline(&mut self.terminal).desired_width(420.0));
                                if ui.button("Rodar").clicked() && !self.terminal.trim().is_empty() {
                                    let p = Pending {
                                        title: "Terminal".into(),
                                        line: format!("\u{0}raw {}", self.terminal.trim()),
                                        stdin: None,
                                        timeout: 60,
                                        reload: None,
                                        warn: String::new(),
                                        panel_answer: false,
                                    };
                                    self.run(ctx, p);
                                }
                            });
                        }
                    }
                    Page::Live => self.live_ui(ui, ctx),
                    Page::Game => self.game_ui(ui, ctx),
                    Page::Settings => self.settings_ui(ui),
                });
        });

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
                        go = ui.button("Executar").clicked();
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

fn main() -> eframe::Result<()> {
    let opts = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([980.0, 720.0])
            .with_title("Cinders Admin"),
        ..Default::default()
    };
    eframe::run_native("Cinders Admin", opts, Box::new(|_cc| Ok(Box::new(App::new()))))
}
