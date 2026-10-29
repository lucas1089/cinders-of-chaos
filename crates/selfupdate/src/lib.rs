//! Shared update helpers of the desktop admin app (O312, `desktop/`) and the game launcher (O314, `launcher/`):
//! SHA-256, version compare and the staged rename of a program file. No network, no GUI.
pub mod hash;
pub mod swap;
pub mod version;
