use std::{env, path::PathBuf, process};
use cuteterm::update;

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() != 4 || args[0] != "--apply" {
        eprintln!("CuteTerm updater accepts only --apply <verified zip> <target exe> <parent pid>.");
        process::exit(2);
    }
    let zip = PathBuf::from(&args[1]);
    let executable = PathBuf::from(&args[2]);
    let pid: u32 = match args[3].parse() {
        Ok(pid) => pid,
        Err(_) => {
            eprintln!("Invalid parent process ID.");
            process::exit(2);
        }
    };
    match update::apply_package(&zip, &executable, pid) {
        Ok(()) => {}
        Err(error) => {
            eprintln!("Update failed: {error}");
            process::exit(1);
        }
    }
}
