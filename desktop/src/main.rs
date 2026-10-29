//! Cinders Admin for the PC: the window. Logic is in the library (commands, ssh, config, update, catalog).
use cinders_admin::catalog::{self, PanelAction};
use cinders_admin::commands::{self, Action, Kind, Live, Tab, ACTIONS};
use cinders_admin::config::{self, Config};
use cinders_admin::{ssh, update};
use eframe::egui;
use std::collections::HashMap;
use std::sync::mpsc::{channel, Receiver, Sender};

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(PartialEq, Clone, Copy)]
enum Page {
    Tab(Tab),
    Game,
    Settings,
}

enum Msg {
    Done { title: String, text: String, ok: bool },
    Catalog(Result<(Vec<PanelAction>, i64), String>),
    Update(Result<Option<update::Found>, String>),
    Installed(Result<(), String>),
}

struct Pending {
    title: String,
    line: String,
    stdin: Option<String>,
    timeout: u64,
    reload: Option<&'static str>,
    warn: String,
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
        };
        if app.cfg.auto_update {
            app.check_update();
        }
        app
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

        egui::TopBottomPanel::top("top").show(ctx, |ui| {
            ui.horizontal(|ui| {
                ui.heading("Cinders Admin");
                for t in Tab::ALL {
                    ui.selectable_value(&mut self.page, Page::Tab(t), t.title());
                }
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
                            let _ = tx.send(Msg::Installed(update::install(&f).map(|_| ())));
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
                                    };
                                    self.run(ctx, p);
                                }
                            });
                        }
                    }
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
