use std::{env, process};
use cuteterm::{app, commands, config, theme, update};

fn main() {
    if let Err(error) = run() {
        eprintln!("CuteTerm error: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let mut args: Vec<String> = env::args().skip(1).collect();
    // Explorer passes --cwd so a new shell opens at the selected folder.
    if args.len() >= 2 && args[0] == "--cwd" {
        env::set_current_dir(&args[1])?;
        args.drain(0..2);
    }
    let mut settings = config::load();
    match args.first().map(String::as_str) {
        Some("--version" | "-V" | "version") => {
            println!("CuteTerm {} / Rust + ConPTY / Windows", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        Some("--help" | "-h" | "help") => {
            println!("✦ CuteTerm {} — Windows-native interactive terminal", env!("CARGO_PKG_VERSION"));
            println!("Usage: cuteterm [command]");
            println!("  cuteterm                 start native ConPTY terminal");
            println!("  cuteterm shell [program] launch a terminal with cmd.exe, pwsh.exe, wsl.exe, etc.");
            println!("  cuteterm --cwd <folder>  open the terminal at this folder");
            println!("  cuteterm commands        show CuteTerm commands and real PATH command count");
            println!("  cuteterm doctor          check system and terminal compatibility");
            println!("  cuteterm themes          list palettes");
            println!("  cuteterm update          verify and install a newer release");
            println!("  cuteterm check-updates   check GitHub Releases without installing");
            println!("  cuteterm version         show version information");
            println!();
            println!("Within the interactive CLI: Ctrl+G opens the CuteTerm command palette.");
            println!("Ctrl+T opens a shell tab. Ctrl+W closes a tab. Alt+1..9 switches tabs.");
            println!("All other keyboard input goes straight into your persistent Windows shell.");
            return Ok(());
        }
        Some("commands") => {
            println!("CuteTerm control palette ({} commands):", commands::BUILTINS.len());
            for (name, description) in commands::BUILTINS {
                println!("  {name:<26} {description}");
            }
            let (custom, warnings) = commands::load_custom_commands(&config::commands_dir());
            println!("\nCustom command manifests ({}):", custom.len());
            for item in custom.values() { println!("  {:<26} {}", item.name, item.description); }
            for warning in warnings { eprintln!("{warning}"); }
            println!("\nReal Windows PATH executables: {}", commands::available_executables().len());
            return Ok(());
        }
        Some("doctor") => {
            println!("CuteTerm compatibility report");
            println!("  platform          {}",std::env::consts::OS);
            println!("  architecture      {}",std::env::consts::ARCH);
            println!("  ConPTY            {}", if cfg!(windows) { "Windows 10 1809+ required" } else {"unsupported on this platform"});
            println!("  default shell     {}",settings.default_shell);
            println!("  terminal profile  Windows Terminal optional (for acrylic/tab chrome)");
            println!("  command manifests {}",config::commands_dir().display());
            println!("  installed tools   {}",commands::available_executables().len());
            println!("  update mode       {}",settings.update_mode);
            let shell = std::process::Command::new("where.exe").arg(&settings.default_shell).output();
            match shell {
                Ok(result) if result.status.success() => println!("  shell available   yes"),
                _ => println!("  shell available   NO — use 'cuteterm shell cmd.exe'"),
            }
            return Ok(());
        }
        Some("themes" | "--themes") => {
            println!("CuteTerm themes: {}", theme::THEMES.join(" | "));
            return Ok(());
        }
        Some("check-updates" | "--check-update") => {
            println!("{}",update::check_for_updates(false,&settings)?);
            return Ok(());
        }
        Some("update" | "--update") => {
            println!("{}",update::check_for_updates(true,&settings)?);
            return Ok(());
        }
        Some("shell" | "--shell") => {
            if let Some(shell) = args.get(1) {settings.default_shell = shell.clone();}
        }
        Some(other) => {
            return Err(format!("Unknown CuteTerm command '{other}'. Run 'cuteterm help'.").into());
        }
        None => {}
    }

    config::startup_dirs()?;
    if update::auto_update(&settings) { return Ok(()); }
    app::run(settings)?;
    Ok(())
}
