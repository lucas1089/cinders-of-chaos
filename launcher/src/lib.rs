//! Cinders of Chaos game launcher (ROADMAP O314). Everything but the window is here and unit tested; the mass-update
//! test in `tests/` runs the whole update against a local HTTP server.
//!
//! Trust: the same Ed25519-signed manifest the in-game updater reads (client/MANIFEST.md "Signed updater"). The
//! launcher reads only its `native` section (exe, DLLs, chaos.pack, itself); the Lua updater reads `files` and ignores
//! `native`, so old clients are not affected by it. The Unity client (beta) is a second manifest of the same key in its own
//! folder, chosen in the window (`choice`).
pub mod carousel;
pub mod choice;
mod chunked;
pub mod config;
pub mod feed;
pub mod fmt;
pub mod i18n;
pub mod images;
pub mod install;
pub mod launch;
pub mod layout;
pub mod manifest;
pub mod net;
pub mod selfupdate;
