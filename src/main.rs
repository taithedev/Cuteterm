use std::{env, process};
use cuteterm::{app, commands, config, theme, update};

fn main() {
    if let Err(error) = run() {
        eprintln!("CuteTerm error: {error}");
        process::exit(1);
    }
}

fn run() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().skip(1).collect();
    let settings = config::load();

    match args.first().map(String::as_str) {
        Some("--version" | "-V" | "version") => {
            println!("CuteTerm v{} / Rust-native Windows CLI", env!("CARGO_PKG_VERSION"));
            return Ok(());
        }
        Some("--help" | "-h" | "help") => {
            println!("CuteTerm v{} — a softer side of the command line", env!("CARGO_PKG_VERSION"));
            println!("Run cuteterm without arguments for the interactive workspace.");
            println!("  cuteterm commands        list real commands");
            println!("  cuteterm --check-update  check GitHub Releases");
            println!("  cuteterm --update        verify and install the newest release");
            println!("  cuteterm --version       show version");
            println!("Inside the app, type /help for shortcuts.");
            return Ok(());
        }
        Some("commands") => {
            println!("CuteTerm actions ({}):", commands::BUILTINS.len());
            for (name, description) in commands::BUILTINS {
                println!("  {name:<26} {description}");
            }
            let (user_commands, warnings) = commands::load_custom_commands(&config::commands_dir());
            println!("\nUser and bundled commands ({}):", user_commands.len());
            for item in user_commands.values() { println!("  /{:<25} {}", item.name, item.description); }
            for warning in warnings { eprintln!("{warning}"); }
            let found = commands::available_executables();
            println!("\nExecutable commands discovered in PATH: {}", found.len());
            return Ok(());
        }
        Some("--check-update") => {
            println!("{}", update::check_for_updates(false, &settings)?);
            return Ok(());
        }
        Some("--update") => {
            println!("{}", update::check_for_updates(true, &settings)?);
            return Ok(());
        }
        Some("--themes") => {
            println!("CuteTerm themes: {}", theme::THEMES.join(", "));
            return Ok(());
        }
        Some(other) => {
            return Err(format!("Unknown CLI option {other}. Try cuteterm --help").into());
        }
        None => {}
    }

    config::startup_dirs()?;
    if update::auto_update(&settings) { return Ok(()); }
    app::run(settings)?;
    Ok(())
}
