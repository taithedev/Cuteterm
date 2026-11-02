//! CuteTerm v0.6 — a real Windows ConPTY shell inside a Claude Code-inspired Rust CLI.
//! Terminal input always goes to the active persistent shell except when the
//! CuteTerm command palette is open (Ctrl+G).
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    env, io,
    path::PathBuf,
    process::Command,
    time::{Duration, Instant},
};

use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseEventKind,
        EnableBracketedPaste, DisableBracketedPaste, EnableMouseCapture, DisableMouseCapture},
    execute,
};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, Paragraph, Wrap},
    DefaultTerminal, Frame,
};
use sysinfo::System;

use crate::{
    commands::{self, CustomCommand},
    config::{self, Settings},
    pty::ShellSession,
    theme::{self, Palette},
    update,
};

const TICK: Duration = Duration::from_millis(55);
const MAX_MESSAGES: usize = 10;

struct Tab {
    id: u64,
    title: String,
    session: ShellSession,
}

#[derive(Default)]
struct PaletteInput {
    open: bool,
    text: String,
    history: Vec<String>,
    history_index: usize,
}

pub struct App {
    settings: Settings,
    tabs: Vec<Tab>,
    selected: usize,
    next_id: u64,
    palette: PaletteInput,
    help: bool,
    messages: VecDeque<String>,
    custom: BTreeMap<String, CustomCommand>,
    executables: BTreeSet<String>,
    started: Instant,
    cpu: String,
    memory: String,
    os: String,
    should_exit: bool,
}

impl App {
    pub fn new(settings: Settings, width: u16, height: u16) -> io::Result<Self> {
        let mut system = System::new_all();
        system.refresh_memory();
        let cpu = system.cpus().first().map(|cpu| cpu.brand().to_string())
            .unwrap_or_else(|| "Processor unavailable".into());
        let memory = format!("{:.1} / {:.1} GiB",
            (system.total_memory().saturating_sub(system.available_memory())) as f64 / 1_073_741_824.0,
            system.total_memory() as f64 / 1_073_741_824.0);
        let os = System::long_os_version().unwrap_or_else(|| "Microsoft Windows".into());
        let (custom, warnings) = commands::load_custom_commands(&config::commands_dir());
        let executables = commands::available_executables();
        let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        let dims = shell_dimensions(width, height, settings.show_system_panel);
        let session = ShellSession::spawn(&settings.default_shell, &cwd, dims.0, dims.1)?;
        let mut messages = VecDeque::new();
        messages.push_back("CuteTerm / native Windows ConPTY. Ctrl+G opens the command palette.".into());
        for message in warnings { messages.push_back(message); }
        Ok(Self {
            settings,
            tabs: vec![Tab { id: 1, title: "terminal".into(), session }],
            selected: 0,
            next_id: 2,
            palette: PaletteInput::default(),
            help: false,
            messages,
            custom, executables,
            started: Instant::now(),
            cpu, memory, os,
            should_exit: false,
        })
    }

    fn log(&mut self, message: impl Into<String>) {
        self.messages.push_back(message.into());
        while self.messages.len() > MAX_MESSAGES { self.messages.pop_front(); }
    }

    fn tab(&self) -> &Tab { &self.tabs[self.selected] }
    fn tab_mut(&mut self) -> &mut Tab { &mut self.tabs[self.selected] }

    fn spawn_tab(&mut self, shell: &str, width: u16, height: u16) {
        let dims = shell_dimensions(width, height, self.settings.show_system_panel);
        let cwd = env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
        match ShellSession::spawn(shell, &cwd, dims.0, dims.1) {
            Ok(session) => {
                let id = self.next_id;
                self.next_id += 1;
                self.tabs.push(Tab { id, title: format!("{shell} #{id}"), session });
                self.selected = self.tabs.len()-1;
                self.help = false;
                self.log(format!("Started an independent {shell} ConPTY tab."));
            }
            Err(error) => self.log(format!("Could not launch {shell}: {error}")),
        }
    }

    fn close_tab(&mut self) {
        if self.tabs.len() == 1 {
            self.log("Last tab is kept open. Use Ctrl+Q to exit CuteTerm.");
            return;
        }
        self.tabs.remove(self.selected);
        self.selected = self.selected.min(self.tabs.len()-1);
        self.log("Closed the tab and its shell process.");
    }

    fn resize(&mut self, width: u16, height: u16) {
        let (rows, cols) = shell_dimensions(width, height, self.settings.show_system_panel);
        for tab in &mut self.tabs { tab.session.resize(rows, cols); }
    }

    fn control(&mut self, value: &str, width: u16, height: u16) {
        let value = value.trim().trim_start_matches(|c| c == '/' || c == ':');
        let words = commands::split_words(value);
        if words.is_empty() { return; }
        let name = words[0].to_ascii_lowercase();
        let arg = |i: usize| -> &str { words.get(i).map(String::as_str).unwrap_or("") };
        match name.as_str() {
            "help" | "?" => self.help = !self.help,
            "about" => self.log(format!("CuteTerm {} • native Rust • ConPTY • Windows", env!("CARGO_PKG_VERSION"))),
            "new" | "tabnew" => {
                let shell = if arg(1).is_empty() { self.settings.default_shell.clone() }
                            else { arg(1).to_owned() };
                self.spawn_tab(&shell, width, height);
            },
            "tabs" => {
                let names = self.tabs.iter().enumerate().map(|(i,t)| format!("{}:{} ({})",i+1,t.title,t.session.shell)).collect::<Vec<_>>();
                self.log(names.join(" · "));
            }
            "tab" => {
                if let Ok(index) = arg(1).parse::<usize>() {
                    if index > 0 && index <= self.tabs.len() { self.selected = index-1; }
                    else { self.log("Tab number is out of range."); }
                } else { self.log("Usage: :tab 2"); }
            }
            "close" => self.close_tab(),
            "rename" if !arg(1).is_empty() => {
                self.tab_mut().title = words[1..].join(" ").chars().take(25).collect();
            }
            "rename" => self.log("Usage: :rename <tab title>"),
            "shell" => {
                let shell = if arg(1).is_empty() { "cmd.exe" } else { arg(1) };
                self.spawn_tab(shell, width, height);
            }
            "theme" => {
                if theme::validate(arg(1)) {
                    self.settings.theme = arg(1).to_owned();
                    self.save_settings();
                    self.log(format!("Using theme {}.", arg(1)));
                } else { self.log(format!("Themes: {}", theme::THEMES.join(" · "))); }
            }
            "palette" => self.log(format!("Themes: {}", theme::THEMES.join(" · "))),
            "sidebar" => {
                let state = match arg(1) {
                    "on" => true, "off" => false,
                    _ => !self.settings.show_system_panel,
                };
                self.settings.show_system_panel = state;
                self.save_settings();
                self.resize(width,height);
                self.log(format!("System sidebar {}", if state {"on"} else {"off"}));
            }
            "animate" => {
                self.settings.animations = match arg(1) { "on" => true, "off" => false, _ => !self.settings.animations };
                self.save_settings();
            }
            "commands" => self.log(format!(
                "{} CuteTerm palette actions · {} custom commands · {} PATH executables (counts are real)",
                commands::BUILTINS.len(), self.custom.len(), self.executables.len())),
            "find" => {
                let needle = arg(1).to_ascii_lowercase();
                if needle.is_empty() { self.log("Usage: :find <command>"); }
                else {
                    let matched = self.executables.iter().filter(|name| name.contains(&needle)).take(20).cloned().collect::<Vec<_>>();
                    self.log(format!("Matching executables: {}", if matched.is_empty() { "(none)".into() } else { matched.join(", ") }));
                }
            }
            "system" => self.log(format!("{} • {} • memory {}", self.os, self.cpu, self.memory)),
            "config" => self.log(format!("Settings: {}", config::data_dir().join("config.json").display())),
            "cwd" => self.log("Shell CWD changes persist inside ConPTY. Type cd or cd /d in the shell to view/change it."),
            "plugins" => {
                let names = self.custom.keys().cloned().collect::<Vec<_>>().join(", ");
                self.log(format!("{} loaded command packs: {}", self.custom.len(), names));
            }
            "plugin" => match arg(1) {
                "path" => self.log(format!("Custom commands: {}",config::commands_dir().display())),
                "reload" => {
                    let (custom, warnings) = commands::load_custom_commands(&config::commands_dir());
                    self.custom = custom;
                    self.log(format!("Reloaded {} command manifests.", self.custom.len()));
                    for warning in warnings { self.log(warning); }
                }
                "new" => match commands::create_custom_command(&config::commands_dir(),arg(2),arg(3)) {
                    Ok(path) => self.log(format!("Created {}. Edit its arguments, then :plugin reload.", path.display())),
                    Err(error) => self.log(format!("Could not create extension: {error}")),
                },
                _ => self.log("Usage: :plugin path | reload | new NAME PROGRAM"),
            },
            "run" => {
                if let Some(item) = self.custom.get(arg(1)).cloned() {
                    let arguments = words.iter().skip(2).cloned().collect::<Vec<_>>();
                    // Run a custom command using an argument vector, not a shell-expanded string.
                    let mut process = Command::new(&item.program);
                    process.args(&item.args).args(arguments);
                    match process.spawn() {
                        Ok(child) => self.log(format!("Started '{}' with process ID {}.",item.name,child.id())),
                        Err(error) => self.log(format!("Command could not be launched: {error}")),
                    }
                } else { self.log("Usage: :run NAME  •  Use :plugins to see available commands"); }
            }
            "window" | "split" => {
                let mut cmd = Command::new("wt.exe");
                cmd.args(["-w", "0"]);
                if name == "split" { cmd.args(["split-pane", "-p", "CuteTerm"]); }
                else { cmd.args(["new-tab", "-p", "CuteTerm"]); }
                match cmd.spawn() {
                    Ok(_) => self.log("Requested a new Windows Terminal pane."),
                    Err(error) => self.log(format!("Windows Terminal unavailable: {error}")),
                }
            }
            "update" => match arg(1) {
                "check" => match update::check_for_updates(false, &self.settings) {
                    Ok(result) => self.log(result), Err(error) => self.log(format!("Update check failed: {error}")),
                },
                "install" => match update::check_for_updates(true, &self.settings) {
                    Ok(result) => {
                        if result.starts_with("Update launched:") { self.should_exit = true; }
                        self.log(result);
                    },
                    Err(error) => self.log(format!("Update failed: {error}")),
                },
                "auto" | "notify" | "off" => {
                    self.settings.update_mode = arg(1).to_owned();
                    self.save_settings();
                    self.log(format!("Update mode: {}",arg(1)));
                }
                _ => self.log("Usage: :update check | install | auto | notify | off"),
            },
            "exit" | "quit" => self.should_exit = true,
            "clear" => self.tab_mut().session.write(b"\x1b[2J\x1b[H\x1b[3J").ok().unwrap_or(()),
            _ => self.log(format!("Unknown CuteTerm command '{name}'. Ctrl+G then type help.")),
        }
    }

    fn save_settings(&mut self) {
        if let Err(error) = config::save(&self.settings) {
            self.log(format!("Couldn't save settings: {error}"));
        }
    }

    fn submit_palette(&mut self, width: u16, height: u16) {
        let value = std::mem::take(&mut self.palette.text);
        self.palette.open = false;
        if value.trim().is_empty() { return; }
        self.palette.history.push(value.clone());
        if self.palette.history.len() > 100 { self.palette.history.remove(0); }
        self.palette.history_index = self.palette.history.len();
        self.control(&value,width,height);
    }

    fn key(&mut self, key: KeyEvent, width: u16, height: u16) {
        if key.kind == KeyEventKind::Release { return; }
        let ctrl = key.modifiers.contains(KeyModifiers::CONTROL);
        let shift = key.modifiers.contains(KeyModifiers::SHIFT);
        let alt = key.modifiers.contains(KeyModifiers::ALT);

        if ctrl && matches!(key.code,KeyCode::Char('q')) {
            self.should_exit = true;
            return;
        }
        if ctrl && matches!(key.code,KeyCode::Char('t')) {
            self.spawn_tab(&self.settings.default_shell.clone(),width,height);
            return;
        }
        if ctrl && matches!(key.code,KeyCode::Char('w')) {
            self.close_tab();
            return;
        }
        if alt && let KeyCode::Char(ch) = key.code
            && ('1'..='9').contains(&ch) {
            let index = ch.to_digit(10).unwrap() as usize-1;
            if index < self.tabs.len() { self.selected = index; }
            return;
        }
        if ctrl && matches!(key.code,KeyCode::Char('g')) {
            self.palette.open = !self.palette.open;
            self.help = false;
            return;
        }
        if self.help {
            if matches!(key.code,KeyCode::Esc|KeyCode::F(1)) { self.help=false; return; }
        }
        if self.palette.open {
            match key.code {
                KeyCode::Esc => self.palette.open = false,
                KeyCode::Enter => self.submit_palette(width,height),
                KeyCode::Backspace => { self.palette.text.pop(); }
                KeyCode::Up => {
                    if !self.palette.history.is_empty() {
                        self.palette.history_index = self.palette.history_index.saturating_sub(1);
                        self.palette.text = self.palette.history[self.palette.history_index].clone();
                    }
                }
                KeyCode::Down => {
                    if !self.palette.history.is_empty() {
                        self.palette.history_index=(self.palette.history_index+1).min(self.palette.history.len());
                        self.palette.text = self.palette.history.get(self.palette.history_index).cloned().unwrap_or_default();
                    }
                }
                KeyCode::Tab => {
                    let typed=self.palette.text.trim_start_matches(|c| c == '/' || c == ':');
                    if !typed.contains(' ') {
                        let matches:Vec<_>=commands::BUILTINS.iter()
                            .map(|(name,_)| name.trim_start_matches('/').split_whitespace().next().unwrap_or(""))
                            .filter(|name| name.starts_with(typed)).collect();
                        if matches.len()==1 { self.palette.text=matches[0].to_string()+" "; }
                    }
                }
                KeyCode::Char(c) if !ctrl && !alt => self.palette.text.push(c),
                _ => {}
            }
            return;
        }

        if key.code == KeyCode::F(1) { self.help = !self.help; return; }
        if shift && key.code == KeyCode::PageUp {
            self.tab_mut().session.scroll(8);
            return;
        }
        if shift && key.code == KeyCode::PageDown {
            self.tab_mut().session.scroll(-8);
            return;
        }
        if !self.tab().session.alive {
            self.log("This shell exited. Use Ctrl+T for a new shell or Ctrl+G :shell cmd.exe.");
            return;
        }

        let application = self.tab().session.parser.screen().application_cursor();
        if let Some(bytes) = encode_key(key,application) {
            if let Err(error) = self.tab_mut().session.write(&bytes) {
                self.log(format!("Couldn't send keyboard input to ConPTY: {error}"));
            } else {
                self.tab_mut().session.reset_scrollback();
            }
        }
    }

    fn draw(&self, frame: &mut Frame) {
        let palette = theme::palette(&self.settings.theme);
        let bounds=frame.area();
        frame.render_widget(Block::default().style(Style::default().bg(palette.background)),bounds);
        let rows = Layout::default().direction(Direction::Vertical)
            .constraints([Constraint::Length(2),Constraint::Length(2),
                Constraint::Min(4),Constraint::Length(2)]).split(bounds);
        frame.render_widget(
            Paragraph::new(Line::from(vec![
                Span::styled(" ✦ cute",Style::default().fg(palette.pink).add_modifier(Modifier::BOLD)),
                Span::styled("term",Style::default().fg(palette.cyan).add_modifier(Modifier::BOLD)),
                Span::styled("  /  native Rust terminal  ",Style::default().fg(palette.muted)),
                Span::styled(format!("v{}",env!("CARGO_PKG_VERSION")),Style::default().fg(palette.green)),
            ])).style(Style::default().bg(palette.surface)),
            rows[0]);

        let mut tab_spans = vec![Span::raw(" ")];
        for (index,tab) in self.tabs.iter().enumerate().take(9) {
            let active=index==self.selected;
            tab_spans.push(Span::styled(
                format!(" {} {} ",if active {"●"} else {"○"},tab.title),
                Style::default().fg(if active {palette.pink} else {palette.muted})
                    .bg(if active {palette.surface} else {palette.background})
                    .add_modifier(if active {Modifier::BOLD} else {Modifier::empty()}),
            ));
            tab_spans.push(Span::raw(" "));
        }
        tab_spans.push(Span::styled("  + Ctrl+T",Style::default().fg(palette.cyan)));
        frame.render_widget(Paragraph::new(Line::from(tab_spans)), rows[1]);

        let panes=main_panes(rows[2],self.settings.show_system_panel);
        if panes.0.is_some() {
            self.draw_sidebar(frame,panes.0.unwrap(),palette);
        }
        self.draw_shell(frame,panes.1,palette);
        let status=self.messages.back().map(String::as_str).unwrap_or("");
        let footer=Line::from(vec![
            Span::styled("  Ctrl+G  ",Style::default().fg(palette.pink).add_modifier(Modifier::BOLD)),
            Span::styled("palette   ",Style::default().fg(palette.muted)),
            Span::styled("Ctrl+T",Style::default().fg(palette.cyan)),
            Span::styled(" tab   ",Style::default().fg(palette.muted)),
            Span::styled("Alt+1–9",Style::default().fg(palette.cyan)),
            Span::styled(" switch   ",Style::default().fg(palette.muted)),
            Span::styled("Ctrl+Q",Style::default().fg(palette.cyan)),
            Span::styled(" quit",Style::default().fg(palette.muted)),
        ]);
        frame.render_widget(Paragraph::new(vec![
            footer,
            Line::styled(truncate(status,bounds.width.saturating_sub(2) as usize),Style::default().fg(palette.green))
        ]).style(Style::default().bg(palette.surface)),rows[3]);

        if self.help { self.draw_help(frame,palette); }
        if self.palette.open { self.draw_palette(frame,palette); }
    }

    fn draw_sidebar(&self,frame:&mut Frame,area:Rect,p:Palette) {
        let index=if self.settings.animations { (self.started.elapsed().as_millis()/380) as usize % 4 } else {0};
        let sparkle=["✦","✧","⋆","✳"][index];
        let stats=vec![
            Line::styled(format!("  {sparkle} CUTE SPACE"),Style::default().fg(p.pink).add_modifier(Modifier::BOLD)),
            Line::raw(""),
            Line::styled("    /\\_/\\",Style::default().fg(p.cyan)),
            Line::styled("   ( o.o )",Style::default().fg(p.pink)),
            Line::styled("    > ^ <  ✧",Style::default().fg(p.yellow)),
            Line::raw(""),
            Line::styled("  ──────────────────",Style::default().fg(p.border)),
            Line::styled("  WINDOWS",Style::default().fg(p.pink)),
            Line::styled(format!("  {}",truncate(&self.os,23)),Style::default().fg(p.text)),
            Line::raw(""),
            Line::styled("  PROCESSOR",Style::default().fg(p.pink)),
            Line::styled(format!("  {}",truncate(&self.cpu,23)),Style::default().fg(p.text)),
            Line::raw(""),
            Line::styled("  MEMORY",Style::default().fg(p.pink)),
            Line::styled(format!("  {}",self.memory),Style::default().fg(p.green)),
            Line::raw(""),
            Line::styled("  ● ● ● ● ● ● ●",Style::default().fg(p.cyan)),
            Line::styled(format!("  theme: {}",self.settings.theme),Style::default().fg(p.muted)),
            Line::styled(format!("  {} PATH commands",self.executables.len()),Style::default().fg(p.muted)),
            Line::styled(format!("  {} custom scripts",self.custom.len()),Style::default().fg(p.muted)),
        ];
        frame.render_widget(Paragraph::new(stats).style(Style::default().bg(p.background)).block(
            Block::default().borders(Borders::RIGHT).border_style(Style::default().fg(p.border))
        ),area);
    }

    fn draw_shell(&self,frame:&mut Frame,area:Rect,p:Palette) {
        let tab=self.tab();
        let title=format!(" {} • {} ",tab.title, if tab.session.alive {"ConPTY live"} else {"shell exited"});
        let inner=Block::default().title(Span::styled(title,Style::default().fg(p.cyan)))
            .borders(Borders::ALL).border_style(Style::default().fg(p.border)).inner(area);
        // Render the vt100 cell buffer with its actual foreground/background styling.
        let screen=tab.session.parser.screen();
        let rows=inner.height.min(screen.size().0.get());
        let cols=inner.width.min(screen.size().1.get());
        let mut output=Vec::new();
        for row in 0..rows {
            let mut spans=Vec::with_capacity(cols as usize);
            for col in 0..cols {
                let Some(cell)=screen.cell(row,col) else { continue; };
                if cell.is_wide_continuation() { continue; }
                let fg=terminal_color(cell.fgcolor(),p.text);
                let bg=terminal_color(cell.bgcolor(),p.background);
                let mut style=Style::default().fg(fg).bg(bg);
                if cell.bold() { style=style.add_modifier(Modifier::BOLD); }
                if cell.dim() { style=style.add_modifier(Modifier::DIM); }
                if cell.italic() { style=style.add_modifier(Modifier::ITALIC); }
                if cell.underline() { style=style.add_modifier(Modifier::UNDERLINED); }
                if cell.inverse() { style=style.add_modifier(Modifier::REVERSED); }
                let value=if cell.has_contents() { cell.contents() } else {" "};
                spans.push(Span::styled(value.to_owned(),style));
            }
            output.push(Line::from(spans));
        }
        frame.render_widget(Paragraph::new(output).block(
            Block::default().title(Span::styled(format!(" {} ",tab.title),Style::default().fg(p.cyan)))
                .borders(Borders::ALL).border_style(Style::default().fg(p.border))
        ),area);
        if !self.palette.open && !self.help && !screen.hide_cursor() {
            let (cy,cx)=screen.cursor_position();
            if cy<rows && cx<cols {
                frame.set_cursor_position((inner.x+cx,inner.y+cy));
            }
        }
    }

    fn draw_help(&self,frame:&mut Frame,p:Palette) {
        let area=center(frame.area(),78,75);
        frame.render_widget(Clear,area);
        let mut lines=vec![
            Line::styled(" CuteTerm • full Windows terminal controls",Style::default().fg(p.pink).add_modifier(Modifier::BOLD)),
            Line::raw(""),
        ];
        for (command,description) in commands::BUILTINS {
            lines.push(Line::from(vec![
                Span::styled(format!("{command:<24}"),Style::default().fg(p.cyan)),
                Span::styled(*description,Style::default().fg(p.text)),
            ]));
        }
        lines.push(Line::raw(""));
        lines.push(Line::styled(" Ctrl+G palette • Ctrl+T new tab • Ctrl+W close • Alt+1-9 switch • F1/Esc dismiss",Style::default().fg(p.green)));
        frame.render_widget(Paragraph::new(lines).wrap(Wrap{trim:false}).scroll((0,0))
            .block(Block::default().title(" commands ").borders(Borders::ALL).border_style(Style::default().fg(p.pink)))
            .style(Style::default().bg(p.surface)),area);
    }

    fn draw_palette(&self,frame:&mut Frame,p:Palette) {
        let full=frame.area();
        let area=Rect {
            x:full.x+full.width.saturating_sub(full.width.min(82))/2,
            y:full.y+full.height.saturating_sub(5)/2,
            width:full.width.min(82),
            height:5.min(full.height)
        };
        frame.render_widget(Clear,area);
        let typed=format!(" :{}▋",self.palette.text);
        let lines=vec![
            Line::styled(typed,Style::default().fg(p.text).add_modifier(Modifier::BOLD)),
            Line::styled(" Enter to run • Esc to cancel • Tab to complete • :help for commands",Style::default().fg(p.muted))
        ];
        frame.render_widget(Paragraph::new(lines).block(
            Block::default().title(" ✦ CuteTerm command palette ").borders(Borders::ALL).border_style(Style::default().fg(p.pink)))
            .style(Style::default().bg(p.surface)),area);
    }
}

fn terminal_color(color: vt100::Color, fallback: Color) -> Color {
    match color {
        vt100::Color::Default => fallback,
        vt100::Color::Idx(n) => Color::Indexed(n),
        vt100::Color::Rgb(r,g,b) => Color::Rgb(r,g,b),
    }
}

fn truncate(s:&str,n:usize)->String {
    if s.chars().count()<=n {s.to_string()}
    else {format!("{}…",s.chars().take(n.saturating_sub(1)).collect::<String>())}
}

fn center(bounds:Rect,width_percent:u16,height_percent:u16)->Rect {
    let width=bounds.width.saturating_mul(width_percent).saturating_div(100).max(1);
    let height=bounds.height.saturating_mul(height_percent).saturating_div(100).max(1);
    Rect {x:bounds.x+(bounds.width-width)/2,y:bounds.y+(bounds.height-height)/2,width,height}
}

fn main_panes(area:Rect,sidebar:bool)->(Option<Rect>,Rect) {
    if sidebar && area.width >= 95 {
        let cols=Layout::default().direction(Direction::Horizontal)
            .constraints([Constraint::Length(28),Constraint::Min(20)]).split(area);
        (Some(cols[0]),cols[1])
    } else {(None,area)}
}

fn shell_dimensions(width:u16,height:u16,sidebar:bool)->(u16,u16) {
    let shell_width=if sidebar && width>=95 {width.saturating_sub(28)} else {width};
    (height.saturating_sub(8).max(2),shell_width.saturating_sub(2).max(10))
}

fn encode_key(key:KeyEvent,application:bool)->Option<Vec<u8>> {
    let ctrl=key.modifiers.contains(KeyModifiers::CONTROL);
    let alt=key.modifiers.contains(KeyModifiers::ALT);
    let bytes=match key.code {
        KeyCode::Enter => b"\r".to_vec(),
        KeyCode::Tab => b"\t".to_vec(),
        KeyCode::BackTab => b"\x1b[Z".to_vec(),
        KeyCode::Esc => b"\x1b".to_vec(),
        KeyCode::Backspace => b"\x7f".to_vec(),
        KeyCode::Delete => b"\x1b[3~".to_vec(),
        KeyCode::Insert => b"\x1b[2~".to_vec(),
        KeyCode::Home => b"\x1b[H".to_vec(),
        KeyCode::End => b"\x1b[F".to_vec(),
        KeyCode::PageUp => b"\x1b[5~".to_vec(),
        KeyCode::PageDown => b"\x1b[6~".to_vec(),
        KeyCode::Up => if application {b"\x1bOA".to_vec()} else {b"\x1b[A".to_vec()},
        KeyCode::Down => if application {b"\x1bOB".to_vec()} else {b"\x1b[B".to_vec()},
        KeyCode::Right => if application {b"\x1bOC".to_vec()} else {b"\x1b[C".to_vec()},
        KeyCode::Left => if application {b"\x1bOD".to_vec()} else {b"\x1b[D".to_vec()},
        KeyCode::F(1) => b"\x1bOP".to_vec(),
        KeyCode::F(2) => b"\x1bOQ".to_vec(),
        KeyCode::F(3) => b"\x1bOR".to_vec(),
        KeyCode::F(4) => b"\x1bOS".to_vec(),
        KeyCode::F(5) => b"\x1b[15~".to_vec(),
        KeyCode::F(6) => b"\x1b[17~".to_vec(),
        KeyCode::F(7) => b"\x1b[18~".to_vec(),
        KeyCode::F(8) => b"\x1b[19~".to_vec(),
        KeyCode::F(9) => b"\x1b[20~".to_vec(),
        KeyCode::F(10) => b"\x1b[21~".to_vec(),
        KeyCode::F(11) => b"\x1b[23~".to_vec(),
        KeyCode::F(12) => b"\x1b[24~".to_vec(),
        KeyCode::Char(c) if ctrl && c.is_ascii_alphabetic() => vec![(c.to_ascii_lowercase() as u8)-b'a'+1],
        KeyCode::Char(c) if !ctrl => {
            let mut out=Vec::new();
            if alt {out.push(0x1b);}
            let mut utf8=[0_u8;4];
            out.extend_from_slice(c.encode_utf8(&mut utf8).as_bytes());
            out
        }
        _ => return None,
    };
    Some(bytes)
}

pub fn run(settings:Settings)->io::Result<()> {
    let size=crossterm::terminal::size()?;
    let mut app=App::new(settings,size.0,size.1)?;
    let mut terminal=ratatui::init();
    let result=run_loop(&mut terminal,&mut app);
    ratatui::restore();
    result
}

fn run_loop(terminal:&mut DefaultTerminal,app:&mut App)->io::Result<()> {
    execute!(io::stdout(),EnableBracketedPaste,EnableMouseCapture)?;
    let result=(|| {
        loop {
            for tab in &mut app.tabs {tab.session.poll();}
            let size=terminal.size()?;
            app.resize(size.width,size.height);
            terminal.draw(|frame|app.draw(frame))?;
            if app.should_exit {break;}
            if event::poll(TICK)? {
                match event::read()? {
                    Event::Key(key)=>app.key(key,size.width,size.height),
                    Event::Resize(width,height)=>app.resize(width,height),
                    Event::Mouse(mouse)=>match mouse.kind {
                        MouseEventKind::ScrollUp=>app.tab_mut().session.scroll(4),
                        MouseEventKind::ScrollDown=>app.tab_mut().session.scroll(-4),
                        _=>{},
                    },
                    Event::Paste(text)=>{
                        if app.palette.open {
                            app.palette.text.push_str(&text.replace('\r'," ").replace('\n'," "));
                        } else if app.tab().session.alive {
                            let bracketed=app.tab().session.parser.screen().bracketed_paste();
                            if bracketed {app.tab_mut().session.write(b"\x1b[200~")?;}
                            app.tab_mut().session.write(text.as_bytes())?;
                            if bracketed {app.tab_mut().session.write(b"\x1b[201~")?;}
                        }
                    }
                    _=>{},
                }
            }
        }
        Ok(())
    })();
    let _=execute!(io::stdout(),DisableBracketedPaste,DisableMouseCapture);
    result
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn basic_keyboard_encoding() {
        assert_eq!(encode_key(KeyEvent::new(KeyCode::Enter,KeyModifiers::NONE),false),Some(vec![13]));
        assert_eq!(encode_key(KeyEvent::new(KeyCode::Char('c'),KeyModifiers::CONTROL),false),Some(vec![3]));
        assert_eq!(encode_key(KeyEvent::new(KeyCode::Up,KeyModifiers::NONE),true),Some(b"\x1bOA".to_vec()));
    }
    #[test]
    fn dimensions_are_reasonable() {
        assert_eq!(shell_dimensions(120,40,true),(32,90));
        assert_eq!(shell_dimensions(80,30,true),(22,78));
    }
}
