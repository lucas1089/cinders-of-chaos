//! Build step of the launcher (O552): the facts built into the setup program.
//!
//! `launcher/embedded.json` is the text of a `launcher.json` (manifest address, public key, feed, links), written by
//! `client/tools/set_launcher_config.py --embed launcher/embedded.json` in the packaging workflow and never committed.
//! It is copied to `OUT_DIR/embedded.json` and compiled in (`setup::EMBEDDED`). A build without the file embeds an
//! empty text: such a launcher only runs beside a `launcher.json` and shows no setup screen.
use std::path::PathBuf;

fn main() {
    let out = PathBuf::from(std::env::var("OUT_DIR").expect("OUT_DIR"));
    let src = PathBuf::from("embedded.json");
    println!("cargo:rerun-if-changed=embedded.json");
    println!("cargo:rerun-if-changed=build.rs");
    let text = std::fs::read_to_string(&src).unwrap_or_default();
    std::fs::write(out.join("embedded.json"), text).expect("write embedded.json");
}
