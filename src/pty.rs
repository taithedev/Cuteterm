//! Persistent Windows ConPTY-backed shell sessions.
 //! Each tab has an independent terminal emulator, running command interpreter,
 //! ANSI colors, scrollback and resize handling.
use portable_pty::{native_pty_system, Child, CommandBuilder, MasterPty, PtySize, PtySystem};
use std::{
    io::{self, Read, Write},
    num::NonZeroU16,
    path::Path,
    sync::mpsc::{self, Receiver},
    thread,
};
use vt100::Parser;

pub struct ShellSession {
    master: Box<dyn MasterPty + Send>,
    writer: Box<dyn Write + Send>,
    child: Box<dyn Child + Send>,
    output: Receiver<Vec<u8>>,
    pub parser: Parser,
    pub shell: String,
    pub alive: bool,
    size: (u16, u16),
}

impl ShellSession {
    pub fn spawn(shell: &str, cwd: &Path, rows: u16, cols: u16) -> io::Result<Self> {
        Self::spawn_argv(shell, &[], cwd, rows, cols)
    }

    pub fn spawn_argv(shell: &str, args: &[String], cwd: &Path, rows: u16, cols: u16) -> io::Result<Self> {
        let rows = rows.max(2);
        let cols = cols.max(10);
        let pair = native_pty_system()
            .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
            .map_err(io::Error::other)?;
        let mut cmd = CommandBuilder::new(shell);
        cmd.args(args.iter());
        cmd.cwd(cwd.as_os_str());
        let child = pair.slave.spawn_command(cmd).map_err(io::Error::other)?;
        drop(pair.slave);
        let mut reader = pair.master.try_clone_reader().map_err(io::Error::other)?;
        let writer = pair.master.take_writer().map_err(io::Error::other)?;
        let (tx, output) = mpsc::sync_channel::<Vec<u8>>(128);
        thread::spawn(move || {
            let mut buffer = [0_u8; 16384];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => {
                        if tx.send(buffer[..n].to_vec()).is_err() { break; }
                    }
                }
            }
        });
        Ok(Self {
            master: pair.master,
            writer,
            child,
            output,
            parser: Parser::new(NonZeroU16::new(rows).unwrap(), NonZeroU16::new(cols).unwrap(), 2500),
            shell: shell.to_string(),
            alive: true,
            size: (rows, cols),
        })
    }

    pub fn resize(&mut self, rows: u16, cols: u16) {
        let rows = rows.max(2);
        let cols = cols.max(10);
        if (rows, cols) == self.size { return; }
        let _ = self.master.resize(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 });
        self.parser.set_size(NonZeroU16::new(rows).unwrap(), NonZeroU16::new(cols).unwrap());
        self.size = (rows, cols);
    }

    pub fn write(&mut self, sequence: &[u8]) -> io::Result<()> {
        self.writer.write_all(sequence)?;
        self.writer.flush()
    }

    pub fn send_command(&mut self, command: &str) -> io::Result<()> {
        // Keystrokes are sent to a persistent shell; env/cwd/history persist.
        self.write(command.as_bytes())?;
        self.write(b"\r")
    }

    pub fn poll(&mut self) {
        for _ in 0..96 {
            match self.output.try_recv() {
                Ok(bytes) => self.parser.process(&bytes),
                Err(_) => break,
            }
        }
        if self.alive && matches!(self.child.try_wait(), Ok(Some(_))) {
            self.alive = false;
        }
    }

    pub fn scroll(&mut self, delta: isize) {
        let screen = self.parser.screen_mut();
        let current = screen.scrollback() as isize;
        let max = screen.scrollback_len() as isize;
        screen.set_scrollback((current + delta).clamp(0, max) as usize);
    }

    pub fn reset_scrollback(&mut self) {
        self.parser.screen_mut().set_scrollback(0);
    }

    pub fn stop(&mut self) {
        if self.alive {
            let _ = self.child.kill();
            self.alive = false;
        }
    }
}

impl Drop for ShellSession {
    fn drop(&mut self) {
        self.stop();
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn parses_escape_sequences_and_cursor() {
        use std::num::NonZeroU16;
        let mut parser = vt100::Parser::new(NonZeroU16::new(10).unwrap(), NonZeroU16::new(80).unwrap(), 100);
        parser.process(b"\x1b[31mhello\x1b[0m\r\n");
        assert_eq!(parser.screen().cell(0, 0).unwrap().contents(), "h");
        assert_eq!(parser.screen().cell(0, 0).unwrap().fgcolor(), vt100::Color::Idx(1));
    }
    #[cfg(windows)]
    #[test]
    fn windows_cmd_conpty_executes_and_persists_environment() {
        use std::time::{Duration, Instant};
        let cwd = std::env::current_dir().expect("cwd");
        let mut session = super::ShellSession::spawn("cmd.exe", &cwd, 20, 100)
            .expect("ConPTY should start on a supported Windows runner");
        session.send_command("set CUTETERM_TEST_VAR=conpty_").expect("set variable");
        session.send_command("echo %CUTETERM_TEST_VAR%works").expect("echo saved variable");
        let start = Instant::now();
        let mut seen = false;
        while start.elapsed() < Duration::from_secs(8) {
            session.poll();
            if session.parser.screen().contents().contains("conpty_works") {
                seen = true;
                break;
            }
            std::thread::sleep(Duration::from_millis(30));
        }
        session.stop();
        assert!(seen, "Real cmd.exe must persist shell variables across commands inside ConPTY");
    }

}
