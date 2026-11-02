use std::{
    fs::{self, File},
    io::{self, Read, Write},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::{SystemTime, UNIX_EPOCH},
};
use serde::Deserialize;
use sha2::{Digest, Sha256};
use crate::config::{self, Settings};

const API: &str = "https://api.github.com/repos/taithedev/Cuteterm/releases/latest";
const ASSET_NAME: &str = "CuteTerm-Windows-x64.zip";

#[derive(Debug, Deserialize)]
struct Release {
    tag_name: String,
    draft: bool,
    prerelease: bool,
    assets: Vec<Asset>,
}

#[derive(Debug, Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
    digest: Option<String>,
}

pub fn version_tuple(name: &str) -> Option<(u32, u32, u32)> {
    let stripped = name.strip_prefix('v').unwrap_or(name);
    let parts: Vec<_> = stripped.split('.').collect();
    if parts.len() != 3 { return None; }
    Some((parts[0].parse().ok()?, parts[1].parse().ok()?, parts[2].parse().ok()?))
}

fn fetch_json() -> Result<Release, String> {
    // curl ships with Windows 10/11. Explicit timeouts ensure offline startup never hangs.
    let result = Command::new("curl.exe")
        .args(["--fail", "--silent", "--show-error", "--location",
            "--connect-timeout", "4", "--max-time", "12",
            "-H", "Accept: application/vnd.github+json",
            "-A", "CuteTerm-Rust-Updater/0.5", API])
        .output()
        .map_err(|error| format!("curl.exe unavailable: {error}"))?;
    if !result.status.success() { return Err("GitHub Releases is currently unavailable.".into()); }
    let release: Release = serde_json::from_slice(&result.stdout)
        .map_err(|error| format!("Invalid GitHub Releases response: {error}"))?;
    if release.draft || release.prerelease || version_tuple(&release.tag_name).is_none() {
        return Err("Latest GitHub release is not a stable semantic version.".into());
    }
    Ok(release)
}

fn download(url: &str, output: &Path) -> Result<(), String> {
    let status = Command::new("curl.exe")
        .args(["--fail", "--silent", "--show-error", "--location", "--retry", "1",
            "--connect-timeout", "5", "--max-time", "120",
            "-A", "CuteTerm-Rust-Updater/0.5",
            "--output"])
        .arg(output)
        .arg(url)
        .stdin(Stdio::null())
        .status()
        .map_err(|error| format!("Failed to start curl.exe: {error}"))?;
    if status.success() { Ok(()) } else { Err("Release download failed.".into()) }
}

fn file_sha256(path: &Path) -> io::Result<String> {
    let mut file = File::open(path)?;
    let mut digest = Sha256::new();
    let mut buffer = [0u8; 65536];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 { break; }
        digest.update(&buffer[..read]);
    }
    Ok(format!("{:x}", digest.finalize()))
}

fn check_release() -> Result<(Release, (u32, u32, u32)), String> {
    let release = fetch_json()?;
    let newest = version_tuple(&release.tag_name).ok_or("Invalid release version")?;
    Ok((release, newest))
}

pub fn check_for_updates(install: bool, _settings: &Settings) -> Result<String, String> {
    let (release, latest) = check_release()?;
    let current = version_tuple(env!("CARGO_PKG_VERSION")).ok_or("Invalid current version")?;
    if latest <= current {
        return Ok(format!("CuteTerm v{} is current. No update is needed.", env!("CARGO_PKG_VERSION")));
    }
    if !install {
        return Ok(format!("CuteTerm {} is available. Type /update install to install.", release.tag_name));
    }
    let asset = release.assets.iter().find(|item| item.name == ASSET_NAME)
        .ok_or("The release is missing the Windows-x64 update ZIP")?;
    let expected = asset.digest.as_ref().and_then(|value| value.strip_prefix("sha256:"))
        .ok_or("GitHub did not provide an SHA-256 digest; update cancelled")?;
    if expected.len() != 64 || !expected.bytes().all(|ch| ch.is_ascii_hexdigit()) {
        return Err("Invalid GitHub SHA-256 digest; update cancelled".into());
    }
    let url_prefix = format!("https://github.com/taithedev/Cuteterm/releases/download/{}/", release.tag_name);
    if asset.browser_download_url != format!("{url_prefix}{ASSET_NAME}") {
        return Err("Unexpected asset URL; update cancelled.".into());
    }
    let home = config::data_dir().join("updates");
    fs::create_dir_all(&home).map_err(|error| error.to_string())?;
    let zip = home.join(format!("CuteTerm-{}.zip", release.tag_name));
    download(&asset.browser_download_url, &zip)?;
    let actual = file_sha256(&zip).map_err(|error| error.to_string())?;
    if !actual.eq_ignore_ascii_case(expected) {
        let _ = fs::remove_file(&zip);
        return Err("SHA-256 checksum mismatch. The release was not installed.".into());
    }
    let current_exe = std::env::current_exe().map_err(|error| error.to_string())?;
    let helper = current_exe.with_file_name("cuteterm-updater.exe");
    if !helper.is_file() {
        return Err("cuteterm-updater.exe missing. Reinstall from the official Windows installer.".into());
    }
    Command::new(helper)
        .arg("--apply")
        .arg(&zip)
        .arg(&current_exe)
        .arg(std::process::id().to_string())
        .stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null())
        .spawn().map_err(|error| format!("Could not start update helper: {error}"))?;
    Ok(format!("Update launched: {}. CuteTerm will exit and the updater will replace the executable.", release.tag_name))
}

pub fn auto_update(settings: &Settings) -> bool {
    if settings.update_mode != "auto" && settings.update_mode != "notify" { return false; }
    let home = config::data_dir();
    if fs::create_dir_all(&home).is_err() { return false; }
    let cache = home.join("last-check.txt");
    let now = SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_secs());
    let last: u64 = fs::read_to_string(&cache).ok().and_then(|s| s.trim().parse().ok()).unwrap_or(0);
    let interval = settings.update_check_hours.clamp(1, 168) * 3600;
    if now.saturating_sub(last) < interval { return false; }
    // Cache check attempt even if offline: don't hammer the network at startup.
    let _ = fs::write(cache, now.to_string());
    match check_for_updates(settings.update_mode == "auto", settings) {
        Ok(msg) => {
            if msg.starts_with("Update launched:") {
                println!("{msg}");
                true
            } else {
                if msg.contains("available") { println!("{msg}"); }
                false
            }
        }
        Err(_) => false, // Offline launches without update prompts or crashes.
    }
}

pub fn apply_package(zip_path: &Path, executable: &Path, parent_pid: u32) -> Result<(), String> {
    if !zip_path.is_file() || !executable.is_file() { return Err("Invalid update paths".into()); }
    let archive = File::open(zip_path).map_err(|error| error.to_string())?;
    let mut zip = zip::ZipArchive::new(archive).map_err(|error| error.to_string())?;
    // We extract exactly the named executable. Never extract arbitrary paths from an archive.
    let mut entry = zip.by_name("cuteterm.exe").map_err(|_| "Update ZIP missing cuteterm.exe")?;
    if entry.size() < 10_000 || entry.size() > 80_000_000 {
        return Err("Update executable size is outside expected bounds".into());
    }
    let pending = executable.with_extension(format!("{parent_pid}.pending.exe"));
    let backup = executable.with_extension(format!("{parent_pid}.previous.exe"));
    {
        let mut output = File::create(&pending).map_err(|error| error.to_string())?;
        io::copy(&mut entry, &mut output).map_err(|error| error.to_string())?;
        output.flush().map_err(|error| error.to_string())?;
    }
    // The original process must exit before Windows permits replacement.
    for _ in 0..100 {
        if fs::rename(executable, &backup).is_ok() {
            match fs::rename(&pending, executable) {
                Ok(()) => {
                    let _ = fs::remove_file(backup);
                    let _ = fs::remove_file(zip_path);
                    return Ok(());
                }
                Err(error) => {
                    let _ = fs::rename(&backup, executable);
                    return Err(format!("Could not install verified executable: {error}"));
                }
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(250));
    }
    let _ = fs::remove_file(&pending);
    Err("CuteTerm was still running or its install directory is not writable".into())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn semantic_versions() {
        assert!(version_tuple("v0.5.1") > version_tuple("0.5.0"));
        assert_eq!(version_tuple("v1.2.3"), Some((1,2,3)));
        assert!(version_tuple("latest").is_none());
        assert!(version_tuple("v1.2").is_none());
    }
}
