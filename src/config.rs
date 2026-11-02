use serde::{Deserialize, Serialize};
use std::{env, fs, io, path::PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub theme: String,
    pub animations: bool,
    pub update_mode: String,
    pub update_check_hours: u64,
    pub default_shell: String,
    pub show_system_panel: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "arctic".into(),
            animations: true,
            update_mode: "auto".into(),
            update_check_hours: 24,
            default_shell: "cmd.exe".into(),
            show_system_panel: true,
        }
    }
}

pub fn data_dir() -> PathBuf {
    if let Some(path) = env::var_os("LOCALAPPDATA") {
        PathBuf::from(path).join("CuteTerm")
    } else if let Some(path) = env::var_os("HOME") {
        PathBuf::from(path).join(".cuteterm")
    } else {
        PathBuf::from(".cuteterm")
    }
}

pub fn load() -> Settings {
    let path = data_dir().join("config.json");
    fs::read_to_string(path)
        .ok()
        .and_then(|value| serde_json::from_str::<Settings>(&value).ok())
        .unwrap_or_default()
}

pub fn save(settings: &Settings) -> io::Result<()> {
    let dir = data_dir();
    fs::create_dir_all(&dir)?;
    let file = dir.join("config.json");
    let tmp = dir.join("config.json.tmp");
    let contents = serde_json::to_vec_pretty(settings)?;
    fs::write(&tmp, contents)?;
    fs::rename(tmp, file)
}

pub fn commands_dir() -> PathBuf {
    data_dir().join("commands")
}

pub fn history_file() -> PathBuf {
    data_dir().join("history.txt")
}

pub fn startup_dirs() -> io::Result<()> {
    fs::create_dir_all(commands_dir())?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn defaults_are_reasonable() {
        let s = Settings::default();
        assert_eq!(s.theme, "arctic");
        assert_eq!(s.update_mode, "auto");
        assert!(s.update_check_hours > 0);
    }
}
