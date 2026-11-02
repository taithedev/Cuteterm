use serde::{Deserialize, Serialize};
use std::{
    collections::{BTreeMap, BTreeSet},
    env, fs, io,
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::Duration,
};

#[derive(Clone, Debug, Deserialize, Serialize)]
pub struct CustomCommand {
    pub name: String,
    pub description: String,
    pub program: String,
    #[serde(default)]
    pub args: Vec<String>,
}

pub const BUILTINS: &[(&str, &str)] = &[
    ("/help", "List interactive commands and shortcuts"),
    ("/commands", "Discover built-in, custom and installed OS commands"),
    ("/find <term>", "Search commands from your PATH"),
    ("/new", "Open a new CuteTerm workspace tab"),
    ("/tabs", "Show all workspace tabs"),
    ("/tab <n>", "Switch to workspace tab number"),
    ("/close", "Close the current workspace tab"),
    ("/rename <name>", "Rename the active workspace tab"),
    ("/clear", "Clear command output for this tab"),
    ("/theme <name>", "Change arctic, blossom, midnight, mint or oled"),
    ("/palette", "Show the five built-in color themes"),
    ("/config", "Show configuration directory and settings"),
    ("/animate on|off", "Toggle animated startup and ambient effects"),
    ("/system", "Display local Windows system information"),
    ("/history", "Show recent commands for this tab"),
    ("/cwd", "Print current working directory"),
    ("/cd <path>", "Change working directory (persists between commands)"),
    ("/shell", "Open a full interactive cmd.exe session"),
    ("/shell pwsh", "Open another installed shell interactively"),
    ("/split", "Open another Windows Terminal split pane"),
    ("/window", "Open another Windows Terminal tab"),
    ("/plugins", "List available custom commands"),
    ("/plugin new <name> <program>", "Create a command manifest without executing it"),
    ("/plugin reload", "Reload external and user-owned commands"),
    ("/plugin path", "Show user command folder"),
    ("/update check", "Check official GitHub Releases"),
    ("/update install", "Verify and install a new Windows release"),
    ("/update auto|notify|off", "Configure automatic update checks"),
    ("/about", "Show CuteTerm release and keyboard controls"),
    ("/exit", "Exit CuteTerm"),
];

fn valid_name(name: &str) -> bool {
    name.len() >= 2 && name.len() <= 40 &&
        name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

pub fn create_custom_command(folder: &Path, name: &str, program: &str) -> io::Result<PathBuf> {
    if !valid_name(name) || program.is_empty() {
        return Err(io::Error::new(io::ErrorKind::InvalidInput, "Names must be 2-40 lowercase letters, numbers or hyphens. Program is required."));
    }
    fs::create_dir_all(folder)?;
    let path = folder.join(format!("{name}.json"));
    let item = CustomCommand {
        name: name.to_string(),
        description: format!("My custom {name} command"),
        program: program.to_string(),
        args: Vec::new(),
    };
    let bytes = serde_json::to_vec_pretty(&item)?;
    let mut opts = fs::OpenOptions::new();
    opts.write(true).create_new(true);
    let mut file = opts.open(&path)?;
    use std::io::Write;
    file.write_all(&bytes)?;
    Ok(path)
}

fn read_dir_commands(dir: &Path, map: &mut BTreeMap<String, CustomCommand>) -> Vec<String> {
    let mut warnings = Vec::new();
    let Ok(iter) = fs::read_dir(dir) else { return warnings; };
    for entry in iter.flatten() {
        let file = entry.path();
        if file.extension().is_none_or(|ext| ext != "json") { continue; }
        let source = fs::read_to_string(&file);
        match source.and_then(|data| serde_json::from_str::<CustomCommand>(&data)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))) {
            Ok(item) if valid_name(&item.name) && !item.program.trim().is_empty() =>
                { map.insert(item.name.clone(), item); }
            _ => warnings.push(format!("Skipped invalid custom command: {}", file.display())),
        }
    }
    warnings
}

pub fn load_custom_commands(user_folder: &Path) -> (BTreeMap<String, CustomCommand>, Vec<String>) {
    let mut commands = BTreeMap::new();
    let mut warnings = Vec::new();
    if let Ok(exe) = env::current_exe()
        && let Some(parent) = exe.parent() {
        warnings.extend(read_dir_commands(&parent.join("commands"), &mut commands));
    }
    warnings.extend(read_dir_commands(user_folder, &mut commands));
    (commands, warnings)
}

pub fn available_executables() -> BTreeSet<String> {
    let mut results = BTreeSet::new();
    let Some(paths) = env::var_os("PATH") else { return results; };
    for folder in env::split_paths(&paths) {
        let Ok(entries) = fs::read_dir(&folder) else { continue; };
        for entry in entries.flatten() {
            let path = entry.path();
            if !path.is_file() { continue; }
            let ext = path.extension().and_then(|ext| ext.to_str()).unwrap_or_default().to_ascii_lowercase();
            #[cfg(windows)]
            if !matches!(ext.as_str(), "exe" | "com" | "bat" | "cmd") { continue; }
            #[cfg(not(windows))]
            if matches!(ext.as_str(), "json" | "txt" | "md" | "dll" | "so") { continue; }
            if let Some(stem) = path.file_stem().and_then(|s| s.to_str()) {
                results.insert(stem.to_ascii_lowercase());
            }
        }
    }
    results
}

pub fn split_words(input: &str) -> Vec<String> {
    let mut parts = Vec::new();
    let mut buffer = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;
    for ch in input.chars() {
        if escaped { buffer.push(ch); escaped = false; continue; }
        if ch == '\\' && quote == Some('"') { escaped = true; continue; }
        if ch == '"' || ch == '\'' {
            if quote == Some(ch) { quote = None; }
            else if quote.is_none() { quote = Some(ch); }
            else { buffer.push(ch); }
        } else if ch.is_whitespace() && quote.is_none() {
            if !buffer.is_empty() { parts.push(std::mem::take(&mut buffer)); }
        } else { buffer.push(ch); }
    }
    if !buffer.is_empty() { parts.push(buffer); }
    parts
}

#[derive(Debug)]
pub enum ProcessEvent {
    Output { tab: usize, text: String, error: bool },
    Finished { tab: usize, code: Option<i32> },
}

pub fn spawn_command(
    tab: usize,
    raw: String,
    cwd: PathBuf,
    custom: Option<(CustomCommand, Vec<String>)>,
    tx: Sender<ProcessEvent>,
) -> Sender<()> {
    let (cancel_tx, cancel_rx) = mpsc::channel();
    thread::spawn(move || {
        let mut command = if let Some((manifest, arguments)) = custom {
            let mut p = Command::new(&manifest.program);
            p.args(manifest.args).args(arguments);
            p
        } else {
            #[cfg(windows)]
            let mut p = {
                let mut c = Command::new("cmd.exe");
                c.args(["/D", "/C", &raw]);
                c
            };
            #[cfg(not(windows))]
            let mut p = {
                let mut c = Command::new("sh");
                c.args(["-lc", &raw]);
                c
            };
            p
        };
        command.current_dir(cwd).stdin(Stdio::null()).stdout(Stdio::piped()).stderr(Stdio::piped());
        match command.spawn() {
            Ok(mut child) => {
                if let Some(stdout) = child.stdout.take() { pipe_lines(tab, stdout, false, tx.clone()); }
                if let Some(stderr) = child.stderr.take() { pipe_lines(tab, stderr, true, tx.clone()); }
                let code = loop {
                    if cancel_rx.try_recv().is_ok() {
                        let _ = child.kill();
                    }
                    match child.try_wait() {
                        Ok(Some(status)) => break status.code(),
                        Ok(None) => thread::sleep(Duration::from_millis(70)),
                        Err(_) => break None,
                    }
                };
                let _ = tx.send(ProcessEvent::Finished { tab, code });
            }
            Err(error) => {
                let _ = tx.send(ProcessEvent::Output { tab, text: error.to_string(), error: true });
                let _ = tx.send(ProcessEvent::Finished { tab, code: None });
            }
        }
    });
    cancel_tx
}

fn pipe_lines(
    tab: usize,
    reader: impl io::Read + Send + 'static,
    error: bool,
    tx: Sender<ProcessEvent>,
) {
    thread::spawn(move || {
        use io::BufRead;
        let mut reader = io::BufReader::new(reader);
        loop {
            let mut bytes = Vec::new();
            match reader.read_until(b'\n', &mut bytes) {
                Ok(0) | Err(_) => break,
                Ok(_) => {
                    let text = String::from_utf8_lossy(&bytes).trim_end_matches(['\r', '\n']).to_string();
                    if tx.send(ProcessEvent::Output { tab, text, error }).is_err() { break; }
                }
            }
        }
    });
}

pub fn launch_interactive_shell(shell: &str, cwd: &Path) -> io::Result<()> {
    let status = Command::new(shell).current_dir(cwd).status()?;
    if status.success() { Ok(()) }
    else { Err(io::Error::other(format!("{shell} returned {status}"))) }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn quoted_arguments() {
        assert_eq!(split_words(r#"hello "a b" last"#), vec!["hello", "a b", "last"]);
        assert_eq!(split_words("hello   there"), vec!["hello", "there"]);
    }
    #[test]
    fn valid_custom_names() {
        assert!(valid_name("hello-world"));
        assert!(!valid_name("../../temp"));
        assert!(!valid_name("Bad Name"));
    }
    #[test]
    fn custom_manifest_roundtrip() {
        let value = CustomCommand { name: "hello".into(), description: "Hi".into(),
            program: "cmd.exe".into(), args: vec!["/C".into(), "echo hi".into()] };
        let parsed: CustomCommand = serde_json::from_str(&serde_json::to_string(&value).unwrap()).unwrap();
        assert_eq!(parsed.name, "hello");
    }
}
