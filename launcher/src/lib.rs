//! Cinders of Chaos game launcher (ROADMAP O314). Everything but the window is here and unit tested; the mass-update
//! test in `tests/` runs the whole update against a local HTTP server.
//!
//! Trust: the same Ed25519-signed manifest the in-game updater reads (client/MANIFEST.md "Signed updater"). The
//! launcher reads only its `native` section (exe, DLLs, chaos.pack, itself); the Lua updater reads `files` and ignores
//! `native`, so old clients are not affected by it.
pub mod config;
pub mod i18n;
pub mod install;
pub mod launch;
pub mod manifest;
pub mod net;
pub mod selfupdate;
