//! `clientservices-rs [JSON_FILE] [--port 8090] [--host 0.0.0.0]`: the same command line as
//! `server/tools/clientservices.py`. Sockets, threads and the clock only; the protocol is in `lib.rs`.
#![forbid(unsafe_code)]

use clientservices::{finish, head_error_reply, load, log_safe, plan, read_head, render, Reply, Step};
use std::io::{BufReader, Read, Write};
use std::net::{Shutdown, TcpListener, TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

/// A read or write that makes no progress for this long ends the connection (the Python service: 10 s).
const IO_TIMEOUT: Duration = Duration::from_secs(10);
/// A whole request (head and body) must arrive within this time, so a trickle cannot hold a thread for ever.
const REQUEST_DEADLINE: Duration = Duration::from_secs(30);
/// Open connections at once; more are closed at once (the Python service has no limit).
const MAX_CONNECTIONS: usize = 256;

/// Reads from the socket, never waiting past the request's deadline.
struct DeadlineStream<'a> {
    stream: &'a TcpStream,
    deadline: Instant,
}

impl Read for DeadlineStream<'_> {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        let left = self.deadline.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(std::io::ErrorKind::TimedOut.into());
        }
        self.stream.set_read_timeout(Some(left.min(IO_TIMEOUT)))?;
        let mut s = self.stream;
        s.read(buf)
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn log(peer: &str, what: &str) {
    eprintln!("[clientservices] {} {}", peer, what);
}

fn send(stream: &TcpStream, peer: &str, line: &str, reply: &Reply) {
    let bytes = render(reply, now_secs());
    let mut s = stream;
    let _ = s.write_all(&bytes).and_then(|_| s.flush());
    log(peer, &format!("\"{}\" {} -", log_safe(line), reply.code));
}

fn handle(stream: TcpStream, data_file: &Path) {
    let peer = stream
        .peer_addr()
        .map(|a| a.ip().to_string())
        .unwrap_or_else(|_| "?".into());
    let _ = stream.set_write_timeout(Some(IO_TIMEOUT));
    let mut reader = BufReader::new(DeadlineStream {
        stream: &stream,
        deadline: Instant::now() + REQUEST_DEADLINE,
    });
    match read_head(&mut reader) {
        Err(e) => {
            if let Some(reply) = head_error_reply(e) {
                send(&stream, &peer, "-", &reply);
            }
        }
        Ok(head) => {
            let line = format!("{} {}", head.method, head.target);
            let data = load(data_file);
            let reply = match plan(&head, &data) {
                Step::Reply(r) => Some(r),
                Step::ReadBody(n) => {
                    let mut body = Vec::new();
                    match reader.by_ref().take(n as u64).read_to_end(&mut body) {
                        // a client that stops short gets the answer for what it sent (Python: json.loads of it)
                        Ok(_) => Some(finish(&body, &data)),
                        Err(_) => None,
                    }
                }
            };
            if let Some(reply) = reply {
                send(&stream, &peer, &line, &reply);
            }
        }
    }
    let _ = stream.shutdown(Shutdown::Both);
}

/// One of the open connection slots.
struct Slot(Arc<AtomicUsize>);

impl Drop for Slot {
    fn drop(&mut self) {
        self.0.fetch_sub(1, Ordering::SeqCst);
    }
}

struct Args {
    file: PathBuf,
    host: String,
    port: u16,
}

fn usage() -> String {
    "usage: clientservices-rs [-h] [--port PORT] [--host HOST] [file]".to_string()
}

fn parse_args(args: &[String]) -> Result<Args, String> {
    let default_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(Path::to_path_buf))
        .unwrap_or_default();
    let mut file: Option<PathBuf> = None;
    let mut host = "0.0.0.0".to_string();
    let mut port: u16 = 8090;
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let (flag, inline) = match a.split_once('=') {
            Some((f, v)) if f.starts_with("--") => (f, Some(v.to_string())),
            _ => (a.as_str(), None),
        };
        match flag {
            "-h" | "--help" => return Err(usage()),
            "--port" | "--host" => {
                let v = match inline {
                    Some(v) => v,
                    None => it.next().cloned().ok_or(format!(
                        "{}\nerror: argument {}: expected one argument",
                        usage(),
                        flag
                    ))?,
                };
                if flag == "--host" {
                    host = v;
                } else {
                    port = v
                        .parse()
                        .map_err(|_| format!("{}\nerror: argument --port: invalid port value: '{}'", usage(), v))?;
                }
            }
            f if f.starts_with("--") => return Err(format!("{}\nerror: unrecognized arguments: {}", usage(), a)),
            _ if file.is_none() => file = Some(PathBuf::from(a)),
            _ => return Err(format!("{}\nerror: unrecognized arguments: {}", usage(), a)),
        }
    }
    let file = file.unwrap_or_else(|| default_dir.join("..").join("data").join("chaos_clientservices.json"));
    let file = if file.is_absolute() {
        file
    } else {
        std::env::current_dir().map(|d| d.join(&file)).unwrap_or(file)
    };
    Ok(Args { file, host, port })
}

fn main() {
    let argv: Vec<String> = std::env::args().skip(1).collect();
    let args = match parse_args(&argv) {
        Ok(a) => a,
        Err(m) => {
            eprintln!("{}", m);
            std::process::exit(if m.starts_with("usage") && !m.contains("error:") {
                0
            } else {
                2
            });
        }
    };
    let addr = match (args.host.as_str(), args.port)
        .to_socket_addrs()
        .ok()
        .and_then(|mut a| a.next())
    {
        Some(a) => a,
        None => {
            eprintln!("clientservices-rs: cannot resolve host {}", args.host);
            std::process::exit(1);
        }
    };
    let listener = match TcpListener::bind(addr) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("clientservices-rs: cannot listen on {}: {}", addr, e);
            std::process::exit(1);
        }
    };
    println!("serving {} on http://{}:{}/", args.file.display(), args.host, args.port);
    let _ = std::io::stdout().flush();
    let open = Arc::new(AtomicUsize::new(0));
    let file = Arc::new(args.file);
    for conn in listener.incoming() {
        let Ok(stream) = conn else { continue };
        if open.fetch_add(1, Ordering::SeqCst) >= MAX_CONNECTIONS {
            open.fetch_sub(1, Ordering::SeqCst);
            continue; // dropped: closed at once
        }
        let (open, file) = (Arc::clone(&open), Arc::clone(&file));
        // the guard gives the slot back when the thread ends, also after a panic
        let guard = Slot(open);
        let _ = thread::Builder::new().stack_size(512 * 1024).spawn(move || {
            let _guard = guard;
            handle(stream, &file);
        });
    }
}
