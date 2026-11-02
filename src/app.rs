use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    env, io,
    path::PathBuf,
    process::Command,
    sync::mpsc::{self, Receiver, Sender},
    time::{Duration, Instant},
};

use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Paragraph, Wrap},
    DefaultTerminal,
};
use sysinfo::System;

use crate::{
    commands::{self, CustomCommand, ProcessEvent},
    config::{self, Settings},
    theme::{self, Palette},
    update,
};

const MAX_LOGS: usize = 1100;
const FRAME_TIME: Duration = Duration::from_millis(80);

#[derive(Clone, Copy)]
enum LogKind { Normal, Accent, Info, Success, Error, Muted }

struct LogEntry {
    text: String,
    kind: LogKind,
}

struct Tab {
    id: usize,
    title: String,
    cwd: PathBuf,
    logs: VecDeque<LogEntry>,
    input: String,
    cursor: usize,
    history: Vec<String>,
    history_pos: usize,
    scroll: usize,
    running: bool,
    cancel: Option<Sender<()>>,
}

impl Tab {
    fn new(id: usize, name: String, cwd: PathBuf) -> Self {
        Self {
            id, title: name, cwd, logs: VecDeque::new(), input: String::new(), cursor: 0,
            history: Vec::new(), history_pos: 0, scroll: 0, running: false, cancel: None,
        }
    }

    fn push(&mut self, text: impl Into<String>, kind: LogKind) {
        let text = clean_text(&text.into());
        for line in text.lines() {
            self.logs.push_back(LogEntry { text: line.to_string(), kind });
        }
        if self.logs.len() > MAX_LOGS {
            self.logs.drain(..self.logs.len() - MAX_LOGS);
        }
        self.scroll = 0;
    }
}

fn clean_text(input: &str) -> String {
    input.chars()
        .filter(|c| *c == '\t' || !c.is_control())
        .collect::<String>()
}

#[derive(Clone, Debug)]
pub enum Action {
    Exit,
    InteractiveShell(String),
    CheckUpdate(bool),
}

pub struct App {
    settings: Settings,
    tabs: Vec<Tab>,
    selected: usize,
    next_id: usize,
    custom: BTreeMap<String, CustomCommand>,
    executables: BTreeSet<String>,
    tx: Sender<ProcessEvent>,
    rx: Receiver<ProcessEvent>,
    started: Instant,
    cpu: String,
    memory: String,
    os: String,
    status: String,
}

impl App {
    pub fn new(settings: Settings) -> Self {
        let (tx, rx) = mpsc::channel();
        let mut system = System::new_all();
        system.refresh_memory();
        let cpu = system.cpus().first().map(|c| c.brand().to_string()).unwrap_or_else(|| "CPU information unavailable".into());
        let memory = format!("{} / {} GiB",
            (system.total_memory().saturating_sub(system.available_memory())) / (1024 * 1024 * 1024),
            system.total_memory() / (1024 * 1024 * 1024));
        let os = System::long_os_version().unwrap_or_else(|| "Windows".into());
        let (custom, warnings) = commands::load_custom_commands(&config::commands_dir());
        let executables = commands::available_executables();
        let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let mut tab = Tab::new(0, "workspace".into(), cwd);
        tab.push("✦  CuteTerm / native Rust terminal workbench", LogKind::Accent);
        tab.push("   A softer side of the command line.", LogKind::Muted);
        tab.push("", LogKind::Normal);
        tab.push("   Type /help for shortcuts, /commands for actual commands.", LogKind::Info);
        tab.push("   Enter regular Windows commands directly. Use /shell for interactive programs.", LogKind::Info);
        tab.push("   Personal commands live in your CuteTerm commands folder.", LogKind::Muted);
        tab.push("", LogKind::Normal);
        for warning in warnings { tab.push(warning, LogKind::Error); }
        Self {
            settings, tabs: vec![tab], selected: 0, next_id: 1,
            custom, executables, tx, rx, started: Instant::now(), cpu, memory, os,
            status: "ready • Rust-native".into(),
        }
    }

    fn tab(&self) -> &Tab { &self.tabs[self.selected] }
    fn tab_mut(&mut self) -> &mut Tab { &mut self.tabs[self.selected] }
    fn log(&mut self, text: impl Into<String>, kind: LogKind) { self.tab_mut().push(text, kind) }
    fn ensure_tab(&mut self) {
        if self.tabs.is_empty() {
            self.tabs.push(Tab::new(self.next_id, "workspace".into(),
                env::current_dir().unwrap_or_else(|_| PathBuf::from("."))));
            self.next_id += 1;
            self.selected = 0;
        }
    }

    fn advance(&mut self) {
        while let Ok(message) = self.rx.try_recv() {
            match message {
                ProcessEvent::Output { tab, text, error } => {
                    if let Some(target) = self.tabs.iter_mut().find(|t| t.id == tab) {
                        target.push(text, if error { LogKind::Error } else { LogKind::Normal });
                    }
                }
                ProcessEvent::Finished { tab, code } => {
                    if let Some(target) = self.tabs.iter_mut().find(|t| t.id == tab) {
                        target.running = false;
                        target.cancel = None;
                        target.push(format!("  ↳ process finished • exit {}", code.map_or("?".into(), |x| x.to_string())),
                            if code == Some(0) { LogKind::Success } else { LogKind::Error });
                    }
                    self.status = "ready • Rust-native".into();
                }
            }
        }
    }

    fn switch(&mut self, index: usize) {
        if index < self.tabs.len() { self.selected = index; }
    }

    fn new_tab(&mut self) {
        let cwd = self.tab().cwd.clone();
        let id = self.next_id;
        self.next_id += 1;
        let mut tab = Tab::new(id, format!("workspace {}", id + 1), cwd);
        tab.push("✦ New CuteTerm workspace", LogKind::Accent);
        tab.push("Commands run in this tab's own working directory.", LogKind::Muted);
        self.tabs.push(tab);
        self.selected = self.tabs.len() - 1;
    }

    fn close_tab(&mut self) {
        if self.tabs.len() == 1 {
            self.tab_mut().push("Last tab cannot be closed. Use /exit to quit.", LogKind::Muted);
            return;
        }
        let mut removed = self.tabs.remove(self.selected);
        if let Some(cancel) = removed.cancel.take() { let _ = cancel.send(()); }
        self.selected = self.selected.min(self.tabs.len() - 1);
    }

    fn submit(&mut self) -> Option<Action> {
        let input = std::mem::take(&mut self.tab_mut().input);
        self.tab_mut().cursor = 0;
        let value = input.trim().to_string();
        if value.is_empty() { return None; }
        {
            let tab = self.tab_mut();
            tab.history.push(value.clone());
            if tab.history.len() > 500 { tab.history.remove(0); }
            tab.history_pos = tab.history.len();
            tab.push(format!("❯ {value}"), LogKind::Accent);
        }

        let words = commands::split_words(&value);
        let first = words.first().map(String::as_str).unwrap_or("");
        if first.starts_with('/') { return self.slash(&words); }

        if first.eq_ignore_ascii_case("cd") || first.eq_ignore_ascii_case("chdir") {
            let location = words.get(1).map(String::as_str).unwrap_or("%USERPROFILE%");
            let destination = if location == "%USERPROFILE%" || location == "~" {
                env::var_os("USERPROFILE").map(PathBuf::from).unwrap_or_else(|| self.tab().cwd.clone())
            } else {
                let given = PathBuf::from(location);
                if given.is_absolute() { given } else { self.tab().cwd.join(given) }
            };
            match destination.canonicalize() {
                Ok(path) if path.is_dir() => {
                    self.tab_mut().cwd = path.clone();
                    self.log(format!("  {}", path.display()), LogKind::Info);
                }
                _ => self.log("Directory doesn't exist.", LogKind::Error),
            }
            return None;
        }
        if first.eq_ignore_ascii_case("pwd") {
            self.log(self.tab().cwd.display().to_string(), LogKind::Info);
            return None;
        }
        if first.eq_ignore_ascii_case("cls") || first.eq_ignore_ascii_case("clear") {
            self.tab_mut().logs.clear();
            return None;
        }
        if self.tab().running {
            self.log("This workspace is busy. Ctrl+C cancels the process, or open a new tab with Ctrl+T.", LogKind::Error);
            return None;
        }
        let custom = self.custom.get(first).cloned().map(|manifest| (manifest, words[1..].to_vec()));
        let id = self.tab().id;
        let cwd = self.tab().cwd.clone();
        let cancel = commands::spawn_command(id, value, cwd, custom, self.tx.clone());
        let tab = self.tab_mut();
        tab.running = true;
        tab.cancel = Some(cancel);
        self.status = "running • Ctrl+C to cancel".into();
        None
    }

    fn slash(&mut self, words: &[String]) -> Option<Action> {
        let name = words[0].trim_start_matches('/').to_ascii_lowercase();
        let arg = |i: usize| words.get(i).map(String::as_str).unwrap_or("");
        match name.as_str() {
            "help" | "?" => {
                self.log("COMMAND PALETTE  /  native Rust", LogKind::Accent);
                for (name, description) in commands::BUILTINS {
                    self.log(format!("  {name:<24} {description}"), LogKind::Normal);
                }
                self.log("Ctrl+T  new tab    Ctrl+W  close    Alt+1..9  switch tabs", LogKind::Info);
                self.log("↑/↓  history    Tab  slash autocomplete    Ctrl+C  cancel    Ctrl+Q  exit", LogKind::Info);
            }
            "about" => {
                self.log(format!("CuteTerm v{} / Rust / Windows 11", env!("CARGO_PKG_VERSION")), LogKind::Accent);
                self.log("Pastel terminal workbench • real cmd.exe execution • custom command manifests.", LogKind::Info);
                self.log("No PowerShell dependency. Windows Terminal provides acrylic blur and native window tabs.", LogKind::Muted);
            }
            "commands" => {
                self.log(format!("{} CuteTerm slash actions • {} custom commands • {} actual PATH executables",
                    commands::BUILTINS.len(), self.custom.len(), self.executables.len()), LogKind::Success);
                self.log("Use /help for actions, /plugins for extensions, /find rust to search installed tools.", LogKind::Info);
            }
            "find" => {
                let needle = arg(1).to_ascii_lowercase();
                if needle.is_empty() {
                    self.log("Usage: /find <search text>", LogKind::Error);
                } else {
                    let matches: Vec<_> = self.executables.iter().filter(|name| name.contains(&needle)).take(45).cloned().collect();
                    self.log(format!("{} matching installed executables:", matches.len()), LogKind::Info);
                    for name in matches { self.log(format!("  • {name}"), LogKind::Normal); }
                }
            }
            "new" => self.new_tab(),
            "tabs" => {
                let summaries: Vec<_> = self.tabs.iter().enumerate().map(|(index, tab)| (index, tab.title.clone(), tab.running)).collect();
                for (index, title, running) in summaries {
                    self.log(format!("  {}. {}{}", index + 1, title, if running { "  (running)" } else { "" }), LogKind::Info);
                }
            }
            "tab" => match arg(1).parse::<usize>() {
                Ok(number) if number > 0 && number <= self.tabs.len() => self.switch(number - 1),
                _ => self.log("Usage: /tab <number>  •  Try /tabs", LogKind::Error),
            },
            "close" => self.close_tab(),
            "rename" if !arg(1).is_empty() => self.tab_mut().title = words[1..].join(" ").chars().take(30).collect(),
            "rename" => self.log("Usage: /rename <new tab title>", LogKind::Error),
            "clear" => self.tab_mut().logs.clear(),
            "cwd" => self.log(self.tab().cwd.display().to_string(), LogKind::Info),
            "cd" => {
                let directory = if arg(1).is_empty() { "~" } else { arg(1) };
                let path = if directory == "~" {
                    env::var_os("USERPROFILE").map(PathBuf::from).unwrap_or_else(|| self.tab().cwd.clone())
                } else {
                    let path = PathBuf::from(directory);
                    if path.is_absolute() { path } else { self.tab().cwd.join(path) }
                };
                match path.canonicalize() {
                    Ok(path) if path.is_dir() => {
                        self.tab_mut().cwd = path.clone();
                        self.log(format!("  {}", path.display()), LogKind::Success);
                    }
                    _ => self.log("That directory was not found.", LogKind::Error),
                }
            }
            "history" => {
                let history = self.tab().history.iter().rev().take(25).cloned().collect::<Vec<_>>();
                for item in history.into_iter().rev() { self.log(format!("  {item}"), LogKind::Muted); }
            }
            "theme" => {
                if theme::validate(arg(1)) {
                    self.settings.theme = arg(1).to_string();
                    self.save_settings();
                    self.log(format!("Theme set to {}. Windows Terminal acrylic is configured by the installer.", arg(1)), LogKind::Success);
                } else {
                    self.log(format!("Choose: {}", theme::THEMES.join(" / ")), LogKind::Info);
                }
            }
            "palette" => self.log(format!("Themes: {}", theme::THEMES.join("  •  ")), LogKind::Accent),
            "animate" => match arg(1) {
                "on" => { self.settings.animations = true; self.save_settings(); self.log("Animations enabled.", LogKind::Success); }
                "off" => { self.settings.animations = false; self.save_settings(); self.log("Animations disabled.", LogKind::Success); }
                _ => self.log("Usage: /animate on|off", LogKind::Error),
            },
            "config" => {
                self.log(format!("Settings: {}", config::data_dir().join("config.json").display()), LogKind::Info);
                self.log(format!("Theme: {} • animations: {} • updates: {} • check every {} hours",
                    self.settings.theme, self.settings.animations, self.settings.update_mode, self.settings.update_check_hours), LogKind::Normal);
            }
            "system" => {
                self.log(self.os.clone(), LogKind::Info);
                self.log(format!("CPU: {}", self.cpu), LogKind::Normal);
                self.log(format!("Memory: {}", self.memory), LogKind::Normal);
                self.log(format!("Computer: {}", env::var("COMPUTERNAME").unwrap_or_default()), LogKind::Normal);
            }
            "shell" => {
                let executable = if arg(1).is_empty() { self.settings.default_shell.clone() } else { arg(1).to_string() };
                return Some(Action::InteractiveShell(executable));
            }
            "split" | "window" => {
                let args: &[&str] = if name == "split" {
                    &["-w", "0", "split-pane", "-p", "CuteTerm"]
                } else {
                    &["-w", "0", "new-tab", "-p", "CuteTerm"]
                };
                match Command::new("wt.exe").args(args).spawn() {
                    Ok(_) => self.log("Requested new Windows Terminal pane.", LogKind::Success),
                    Err(error) => self.log(format!("Windows Terminal isn't available: {error}"), LogKind::Error),
                }
            }
            "plugins" => {
                self.log(format!("Custom commands directory: {}", config::commands_dir().display()), LogKind::Info);
                let listing: Vec<_> = self.custom.values().map(|c| format!("  /{:<16} {}", c.name, c.description)).collect();
                for item in listing { self.log(item, LogKind::Normal); }
                self.log("Create: /plugin new hello cmd.exe    •    Reload: /plugin reload", LogKind::Muted);
            }
            "plugin" => match arg(1) {
                "path" => self.log(config::commands_dir().display().to_string(), LogKind::Info),
                "reload" => {
                    let (custom, warnings) = commands::load_custom_commands(&config::commands_dir());
                    self.custom = custom;
                    self.log(format!("Loaded {} custom commands.", self.custom.len()), LogKind::Success);
                    for warning in warnings { self.log(warning, LogKind::Error); }
                }
                "new" => match commands::create_custom_command(&config::commands_dir(), arg(2), arg(3)) {
                    Ok(path) => self.log(format!("Created {}. Edit the JSON to set args, then /plugin reload.", path.display()), LogKind::Success),
                    Err(error) => self.log(error.to_string(), LogKind::Error),
                },
                _ => self.log("Usage: /plugin new <name> <program> | /plugin reload | /plugin path", LogKind::Error),
            },
            "update" => match arg(1) {
                "check" => return Some(Action::CheckUpdate(false)),
                "install" => return Some(Action::CheckUpdate(true)),
                "auto" | "notify" | "off" => {
                    self.settings.update_mode = arg(1).to_string();
                    self.save_settings();
                    self.log(format!("Update mode set to {}.", arg(1)), LogKind::Success);
                }
                _ => self.log("Usage: /update check|install|auto|notify|off", LogKind::Error),
            },
            "exit" | "quit" => return Some(Action::Exit),
            other => {
                if let Some(manifest) = self.custom.get(other).cloned() {
                    if self.tab().running {
                        self.log("Workspace busy; use Ctrl+T to open another tab.", LogKind::Error);
                    } else {
                        let cancel = commands::spawn_command(self.tab().id, String::new(), self.tab().cwd.clone(),
                            Some((manifest, words[1..].to_vec())), self.tx.clone());
                        self.tab_mut().cancel = Some(cancel);
                        self.tab_mut().running = true;
                        self.status = "running custom command".into();
                    }
                } else {
                    self.log(format!("Unknown slash command: /{other}. Try /help."), LogKind::Error);
                }
            }
        }
        None
    }

    fn save_settings(&mut self) {
        if let Err(error) = config::save(&self.settings) {
            self.log(format!("Settings could not be saved: {error}"), LogKind::Error);
        }
    }

    fn complete(&mut self) {
        let input = self.tab().input.clone();
        if !input.starts_with('/') || input.contains(' ') { return; }
        let possible: Vec<_> = commands::BUILTINS.iter()
            .map(|(name, _)| *name)
            .chain(self.custom.keys().map(String::as_str))
            .filter(|candidate| candidate.starts_with(&input))
            .collect();
        if possible.len() == 1 {
            let answer = possible[0].split_whitespace().next().unwrap_or(possible[0]).to_string();
            self.tab_mut().input = format!("{answer} ");
            self.tab_mut().cursor = self.tab().input.chars().count();
        }
    }

    fn key(&mut self, key: KeyEvent) -> Option<Action> {
        if key.kind == KeyEventKind::Release { return None; }
        match (key.code, key.modifiers) {
            (KeyCode::Char('q'), m) if m.contains(KeyModifiers::CONTROL) => return Some(Action::Exit),
            (KeyCode::Char('t'), m) if m.contains(KeyModifiers::CONTROL) => self.new_tab(),
            (KeyCode::Char('w'), m) if m.contains(KeyModifiers::CONTROL) => self.close_tab(),
            (KeyCode::Char('l'), m) if m.contains(KeyModifiers::CONTROL) => self.tab_mut().logs.clear(),
            (KeyCode::Char('c'), m) if m.contains(KeyModifiers::CONTROL) => {
                if let Some(cancel) = &self.tab().cancel {
                    let _ = cancel.send(());
                    self.log("Stopping process…", LogKind::Muted);
                } else {
                    self.tab_mut().input.clear();
                    self.tab_mut().cursor = 0;
                }
            }
            (KeyCode::Char('a'), m) if m.contains(KeyModifiers::CONTROL) => self.tab_mut().cursor = 0,
            (KeyCode::Char('e'), m) if m.contains(KeyModifiers::CONTROL) =>
                self.tab_mut().cursor = self.tab().input.chars().count(),
            (KeyCode::Char(n), m) if m.contains(KeyModifiers::ALT) && ('1'..='9').contains(&n) =>
                self.switch(n.to_digit(10).unwrap() as usize - 1),
            (KeyCode::Enter, _) => return self.submit(),
            (KeyCode::F(1), _) => return self.slash(&["/help".into()]),
            (KeyCode::Tab, _) => self.complete(),
            (KeyCode::Up, _) => {
                let tab = self.tab_mut();
                if !tab.history.is_empty() {
                    tab.history_pos = tab.history_pos.saturating_sub(1);
                    tab.input = tab.history[tab.history_pos].clone();
                    tab.cursor = tab.input.chars().count();
                }
            }
            (KeyCode::Down, _) => {
                let tab = self.tab_mut();
                if !tab.history.is_empty() {
                    tab.history_pos = (tab.history_pos + 1).min(tab.history.len());
                    tab.input = if tab.history_pos < tab.history.len() {
                        tab.history[tab.history_pos].clone()
                    } else { String::new() };
                    tab.cursor = tab.input.chars().count();
                }
            }
            (KeyCode::PageUp, _) => self.tab_mut().scroll = self.tab().scroll.saturating_add(10),
            (KeyCode::PageDown, _) => self.tab_mut().scroll = self.tab().scroll.saturating_sub(10),
            (KeyCode::Left, _) => self.tab_mut().cursor = self.tab().cursor.saturating_sub(1),
            (KeyCode::Right, _) => {
                self.tab_mut().cursor = (self.tab().cursor + 1).min(self.tab().input.chars().count());
            }
            (KeyCode::Home, _) => self.tab_mut().cursor = 0,
            (KeyCode::End, _) => self.tab_mut().cursor = self.tab().input.chars().count(),
            (KeyCode::Backspace, _) => {
                let tab = self.tab_mut();
                if tab.cursor > 0 {
                    let pos = byte_index(&tab.input, tab.cursor - 1);
                    tab.input.remove(pos);
                    tab.cursor -= 1;
                }
            }
            (KeyCode::Delete, _) => {
                let tab = self.tab_mut();
                if tab.cursor < tab.input.chars().count() {
                    let pos = byte_index(&tab.input, tab.cursor);
                    tab.input.remove(pos);
                }
            }
            (KeyCode::Char(ch), m) if !m.contains(KeyModifiers::CONTROL) && !m.contains(KeyModifiers::ALT) => {
                let tab = self.tab_mut();
                let pos = byte_index(&tab.input, tab.cursor);
                tab.input.insert(pos, ch);
                tab.cursor += 1;
            }
            _ => {}
        }
        None
    }

    fn draw(&self, frame: &mut ratatui::Frame) {
        let colors = theme::palette(&self.settings.theme);
        let area = frame.area();
        frame.render_widget(Block::default().style(Style::default().bg(colors.background)), area);
        let rows = Layout::default().direction(Direction::Vertical)
            .constraints([Constraint::Length(3), Constraint::Length(2), Constraint::Min(7),
                Constraint::Length(4), Constraint::Length(2)]).split(area);

        let title = Line::from(vec![
            Span::styled(" ✦ cuteterm ", Style::default().fg(colors.pink).add_modifier(Modifier::BOLD)),
            Span::styled(" / ", Style::default().fg(colors.muted)),
            Span::styled("Rust-native workspace", Style::default().fg(colors.text)),
            Span::styled(format!("     v{}", env!("CARGO_PKG_VERSION")), Style::default().fg(colors.muted)),
        ]);
        let header = Paragraph::new(title).block(
            Block::default().borders(Borders::BOTTOM).border_style(Style::default().fg(colors.border))
        ).style(Style::default().bg(colors.surface));
        frame.render_widget(header, rows[0]);

        let mut tabs = vec![Span::styled("  ", Style::default())];
        for (index, tab) in self.tabs.iter().enumerate().take(9) {
            let selected = index == self.selected;
            tabs.push(Span::styled(
                format!(" {} {} {} ", if selected { "●" } else { "○" }, tab.title, if tab.running { "⋯" } else { "" }),
                Style::default().fg(if selected { colors.pink } else { colors.muted })
                    .bg(if selected { colors.surface } else { colors.background })
            ));
            tabs.push(Span::raw(" "));
        }
        tabs.push(Span::styled(" + Ctrl+T", Style::default().fg(colors.cyan)));
        frame.render_widget(Paragraph::new(Line::from(tabs)), rows[1]);

        if self.settings.show_system_panel && rows[2].width >= 86 {
            let panes = Layout::default().direction(Direction::Horizontal)
                .constraints([Constraint::Length(34), Constraint::Min(15)]).split(rows[2]);
            frame.render_widget(self.system_panel(colors), panes[0]);
            self.draw_output(frame, panes[1], colors);
        } else { self.draw_output(frame, rows[2], colors); }

        let prefix = "  ❯ ";
        let input = &self.tab().input;
        let prompt = Paragraph::new(Line::from(vec![
            Span::styled(prefix, Style::default().fg(colors.pink).add_modifier(Modifier::BOLD)),
            Span::styled(input.clone(), Style::default().fg(colors.text)),
            Span::styled("▋", Style::default().fg(colors.pink))
        ])).block(Block::default().title(Span::styled(" command ", Style::default().fg(colors.pink)))
                .borders(Borders::ALL).border_style(Style::default().fg(colors.border)))
            .style(Style::default().bg(colors.surface));
        frame.render_widget(prompt, rows[3]);
        let footer = Line::from(vec![
            Span::styled(format!("  {}  ", self.status), Style::default().fg(colors.green)),
            Span::styled("Ctrl+T tab  Alt+1..9 switch  /help commands  /shell interactive  Ctrl+Q quit", Style::default().fg(colors.muted)),
        ]);
        frame.render_widget(Paragraph::new(footer), rows[4]);
    }

    fn system_panel(&self, colors: Palette) -> Paragraph<'static> {
        let stars = ['✦', '✧', '⋆', '✳'];
        let index = if self.settings.animations { (self.started.elapsed().as_millis() / 380) as usize % stars.len() } else { 0 };
        let intro = vec![
            Line::styled(format!("   {}  cute space", stars[index]), Style::default().fg(colors.pink).add_modifier(Modifier::BOLD)),
            Line::styled("", Style::default()),
            Line::styled("      /\\_/\\", Style::default().fg(colors.cyan)),
            Line::styled("     ( o.o )    ✧", Style::default().fg(colors.pink)),
            Line::styled("      > ^ < ", Style::default().fg(colors.yellow)),
            Line::styled("", Style::default()),
            Line::styled("  ──────────────────────", Style::default().fg(colors.border)),
            Line::styled("  WINDOWS", Style::default().fg(colors.pink)),
            Line::styled(format!("  {}", truncate(&self.os, 27)), Style::default().fg(colors.text)),
            Line::styled("", Style::default()),
            Line::styled("  PROCESSOR", Style::default().fg(colors.pink)),
            Line::styled(format!("  {}", truncate(&self.cpu, 27)), Style::default().fg(colors.text)),
            Line::styled("", Style::default()),
            Line::styled("  MEMORY", Style::default().fg(colors.pink)),
            Line::styled(format!("  {}", self.memory), Style::default().fg(colors.green)),
            Line::styled("", Style::default()),
            Line::styled(format!("  ● ● ● ●  {}", self.settings.theme), Style::default().fg(colors.cyan)),
            Line::styled(format!("  {} real PATH commands", self.executables.len()), Style::default().fg(colors.muted)),
            Line::styled(format!("  {} custom commands", self.custom.len()), Style::default().fg(colors.muted)),
        ];
        Paragraph::new(intro).block(Block::default()
            .borders(Borders::RIGHT).border_style(Style::default().fg(colors.border)))
            .style(Style::default().bg(colors.background))
    }

    fn draw_output(&self, frame: &mut ratatui::Frame, area: Rect, colors: Palette) {
        let inner_height = usize::from(area.height.saturating_sub(2));
        let tab = self.tab();
        let take = inner_height.max(1);
        let total = tab.logs.len();
        let end = total.saturating_sub(tab.scroll.min(total));
        let start = end.saturating_sub(take);
        let lines: Vec<Line<'_>> = tab.logs.range(start..end).map(|entry| {
            let color = match entry.kind {
                LogKind::Normal => colors.text,
                LogKind::Accent => colors.pink,
                LogKind::Info => colors.cyan,
                LogKind::Success => colors.green,
                LogKind::Error => colors.red,
                LogKind::Muted => colors.muted,
            };
            Line::styled(entry.text.as_str(), Style::default().fg(color))
        }).collect();
        let block = Block::default().title(Span::styled(" output • scroll PgUp/PgDn ", Style::default().fg(colors.muted)))
            .borders(Borders::ALL).border_style(Style::default().fg(colors.border))
            .style(Style::default().bg(colors.background));
        frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }).block(block), area);
    }
}

fn truncate(s: &str, limit: usize) -> String {
    let count = s.chars().count();
    if count <= limit { s.to_string() }
    else { format!("{}…", s.chars().take(limit.saturating_sub(1)).collect::<String>()) }
}

fn byte_index(s: &str, char_index: usize) -> usize {
    s.char_indices().nth(char_index).map(|(n, _)| n).unwrap_or(s.len())
}

pub fn run(settings: Settings) -> io::Result<()> {
    let mut app = App::new(settings);
    let mut terminal = ratatui::init();
    let result = run_loop(&mut terminal, &mut app);
    ratatui::restore();
    result
}

fn run_loop(terminal: &mut DefaultTerminal, app: &mut App) -> io::Result<()> {
    loop {
        app.advance();
        terminal.draw(|frame| app.draw(frame))?;
        if event::poll(FRAME_TIME)? && let Event::Key(key) = event::read()?
            && let Some(action) = app.key(key) {
            match action {
                Action::Exit => break,
                Action::InteractiveShell(shell) => {
                    ratatui::restore();
                    let current = app.tab().cwd.clone();
                    println!("\nEntering interactive {shell}. Type exit to return to CuteTerm.\n");
                    let result = commands::launch_interactive_shell(&shell, &current);
                    if let Err(error) = result {
                        println!("Cannot open {shell}: {error}");
                    }
                    *terminal = ratatui::init();
                    app.log(format!("Returned from {shell}."), LogKind::Success);
                }
                Action::CheckUpdate(install) => {
                    ratatui::restore();
                    let outcome = update::check_for_updates(install, &app.settings);
                    match outcome {
                        Ok(message) => {
                            println!("{message}");
                            if message.starts_with("Update launched:") { return Ok(()); }
                            app.log(message, LogKind::Info);
                        }
                        Err(error) => {
                            println!("Update unavailable: {error}");
                            app.log(format!("Update unavailable: {error}"), LogKind::Error);
                        }
                    }
                    *terminal = ratatui::init();
                }
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn text_control_codes_are_removed() {
        assert_eq!(clean_text("hi\u{1b}[31m"), "hi[31m");
    }
    #[test]
    fn handles_unicode_cursor_positions() {
        assert_eq!(byte_index("a✦b", 2), 4);
        assert_eq!(truncate("hello", 3), "he…");
    }
}
