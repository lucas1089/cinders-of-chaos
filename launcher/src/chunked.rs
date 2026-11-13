//! Download of a file that has chunk hashes (O552): the pieces are fetched four at a time with `Range`, each checked
//! against its signed hash before it counts, then joined into `stage/<sha>.part` and the whole file is checked again.
//!
//! * Resume and repair work at piece level: a piece that is on disk and hashes right is kept, one that does not is
//!   fetched again, whatever the reason (a cut download, a flipped byte).
//! * The installed file seeds the pieces: a piece of the old file at the same place that hashes to the new value is
//!   copied locally and never downloaded. That is the repair of a damaged pack ("Verify files") and, when a new pack
//!   only changed some pieces, a small download.
//! * Nothing here touches the installed files; the swap (`Updater::apply`) stays the one place that does.
use crate::i18n::Error;
use crate::install::{io, move_over, mtime_key, Updater};
use crate::manifest::{blob_url, Chunks, NativeFile};
use cinders_selfupdate::hash::sha256_file;
use std::fs::File;
use std::io::{Read, Seek, SeekFrom, Write};
use std::path::Path;
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

/// SHA-256 of `len` bytes of an open file from `start`, or None when the file is too short or unreadable.
fn hash_range(f: &mut File, start: u64, len: u64) -> Option<String> {
    use cinders_selfupdate::hash::Sha256Stream;
    f.seek(SeekFrom::Start(start)).ok()?;
    let mut h = Sha256Stream::new();
    let mut buf = vec![0u8; 1 << 20];
    let mut left = len;
    while left > 0 {
        let n = (left as usize).min(buf.len());
        f.read_exact(&mut buf[..n]).ok()?;
        h.update(&buf[..n]);
        left -= n as u64;
    }
    Some(h.finish_hex())
}

/// Copies `len` bytes of `from` (at `start`) into a new file `to`.
fn copy_range(from: &mut File, start: u64, len: u64, to: &Path) -> std::io::Result<()> {
    from.seek(SeekFrom::Start(start))?;
    let mut out = File::create(to)?;
    std::io::copy(&mut from.take(len), &mut out)?;
    out.flush()
}

impl Updater<'_> {
    /// One piece: already on disk and right, copied from the installed file, or downloaded (with retries).
    #[allow(clippy::too_many_arguments)]
    fn fetch_piece(
        &self,
        f: &NativeFile,
        ch: &Chunks,
        i: usize,
        dir: &Path,
        url: &str,
        seed: Option<&Path>,
        bytes: &AtomicU64,
    ) -> Result<(), Error> {
        let (start, end) = ch.range(i, f.size);
        let len = end - start;
        let piece = dir.join(format!("c{i}"));
        let want = &ch.hashes[i];
        if mtime_key(&piece).map(|k| k.0) == Some(len) && sha256_file(&piece).ok().as_deref() == Some(want) {
            bytes.store(len, Ordering::Relaxed);
            return Ok(());
        }
        let _ = std::fs::remove_file(&piece);
        if let Some(path) = seed {
            if let Ok(mut old) = File::open(path) {
                if hash_range(&mut old, start, len).as_deref() == Some(want)
                    && copy_range(&mut old, start, len, &piece).is_ok()
                {
                    bytes.store(len, Ordering::Relaxed);
                    return Ok(());
                }
            }
        }
        let part = dir.join(format!("c{i}.part"));
        let mut last = Error::Download {
            file: f.path.clone(),
            detail: "no try".into(),
        };
        for attempt in 0..=self.opts.retries {
            if attempt > 0 {
                let wait = self.opts.backoff_ms.saturating_mul(1 << (attempt - 1).min(6));
                std::thread::sleep(Duration::from_millis(wait));
            }
            bytes.store(0, Ordering::Relaxed);
            if let Err(e) = self.fetch.download_range(url, start, end, &part, &mut |n| {
                bytes.store(n.min(len), Ordering::Relaxed)
            }) {
                last = Error::Download {
                    file: f.path.clone(),
                    detail: e.detail,
                };
                continue;
            }
            let got = mtime_key(&part).map_or(0, |k| k.0);
            if got != len {
                last = Error::Download {
                    file: f.path.clone(),
                    detail: format!("piece {} of {}: {got} of {len} bytes", i + 1, ch.count()),
                };
                continue;
            }
            if sha256_file(&part).ok().as_deref() == Some(want) {
                io(move_over(&part, &piece), "stage")?;
                bytes.store(len, Ordering::Relaxed);
                return Ok(());
            }
            let _ = std::fs::remove_file(&part);
            last = Error::HashMismatch(f.path.clone());
        }
        bytes.store(0, Ordering::Relaxed);
        Err(last)
    }

    /// Downloads `f` into `stage/<sha>` through its pieces. Same result as `fetch_file`: the whole file, hash checked.
    pub(crate) fn fetch_chunked(&self, f: &NativeFile, progress: &mut dyn FnMut(u64)) -> Result<(), Error> {
        let Some(ch) = f.chunks.as_ref() else {
            return Err(Error::Download {
                file: f.path.clone(),
                detail: "no chunk list".into(),
            });
        };
        let stage = self.stage_dir();
        let done = stage.join(&f.sha256);
        if mtime_key(&done).map(|k| k.0) == Some(f.size) {
            if sha256_file(&done).ok().as_deref() == Some(&f.sha256) {
                progress(f.size);
                return Ok(());
            }
            let _ = std::fs::remove_file(&done);
        }
        let dir = stage.join(format!("{}.chunks", f.sha256));
        io(std::fs::create_dir_all(&dir), "create the piece folder")?;
        let url = blob_url(&self.cfg.manifest_url, &f.sha256);
        let installed = self.cfg.dir.join(&f.path);
        let seed = installed.is_file().then_some(installed.as_path());
        let n = ch.count();
        let bytes: Vec<AtomicU64> = (0..n).map(|_| AtomicU64::new(0)).collect();
        let next = AtomicUsize::new(0);
        let finished = AtomicUsize::new(0);
        let stop = AtomicBool::new(false);
        let first_error: Mutex<Option<Error>> = Mutex::new(None);
        let workers = self.opts.parallel.clamp(1, n);
        std::thread::scope(|sc| {
            for _ in 0..workers {
                sc.spawn(|| {
                    while !stop.load(Ordering::Relaxed) {
                        let i = next.fetch_add(1, Ordering::Relaxed);
                        if i >= n {
                            break;
                        }
                        match self.fetch_piece(f, ch, i, &dir, &url, seed, &bytes[i]) {
                            Ok(()) => {
                                finished.fetch_add(1, Ordering::Relaxed);
                            }
                            Err(e) => {
                                stop.store(true, Ordering::Relaxed);
                                first_error.lock().unwrap().get_or_insert(e);
                            }
                        }
                    }
                });
            }
            // this thread reports the sum while the workers run
            loop {
                progress(bytes.iter().map(|b| b.load(Ordering::Relaxed)).sum());
                if stop.load(Ordering::Relaxed) || finished.load(Ordering::Relaxed) == n {
                    break;
                }
                std::thread::sleep(Duration::from_millis(40));
            }
        });
        if let Some(e) = first_error.into_inner().unwrap() {
            return Err(e);
        }
        // join the pieces: each is appended and removed, so the extra disk use stays at about one piece
        let part = stage.join(format!("{}.part", f.sha256));
        {
            let mut out = io(File::create(&part), &f.path)?;
            for i in 0..n {
                let piece = dir.join(format!("c{i}"));
                let mut src = io(File::open(&piece), &f.path)?;
                io(std::io::copy(&mut src, &mut out), &f.path)?;
                drop(src);
                let _ = std::fs::remove_file(&piece);
            }
            io(out.flush(), &f.path)?;
        }
        if io(sha256_file(&part), &f.path)? == f.sha256 {
            io(move_over(&part, &done), "stage")?;
            let _ = std::fs::remove_dir_all(&dir);
            progress(f.size);
            Ok(())
        } else {
            // every piece was right and the whole is not: the manifest is inconsistent, not the network
            let _ = std::fs::remove_file(&part);
            let _ = std::fs::remove_dir_all(&dir);
            Err(Error::HashMismatch(f.path.clone()))
        }
    }
}
