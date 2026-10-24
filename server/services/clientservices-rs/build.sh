#!/usr/bin/env bash
# Builds the Rust login-screen services (server/README.md "Rust services (O153)") and installs the binary.
#   build.sh OUT_BINARY        e.g. /opt/chaos/bin/clientservices-rs
# cargo comes from PATH, ~/.cargo/bin or /root/.cargo/bin (rustup, https://rustup.rs). The build uses a temporary target
# folder, removed afterwards, and --locked: the crate versions are the ones in Cargo.lock. The binary is replaced by a
# rename, so a running service keeps its old file until it restarts. Run by chaos-ctl.sh clientservices-impl rust and by
# chaos_update.sh (only when the switch is on). No secrets.
set -euo pipefail

out=${1:-}
[ -n "$out" ] || { echo "usage: build.sh OUT_BINARY" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

cargo=$(command -v cargo || true)
for c in "$HOME/.cargo/bin/cargo" /root/.cargo/bin/cargo; do
	[ -n "$cargo" ] || { [ -x "$c" ] && cargo=$c; }
done
[ -n "$cargo" ] || { echo "build.sh: cargo not found (install Rust with rustup, https://rustup.rs)" >&2; exit 3; }

target=$(mktemp -d "${TMPDIR:-/var/tmp}/clientservices-rs-build.XXXXXX")
trap 'rm -rf "$target"' EXIT
CARGO_TARGET_DIR=$target "$cargo" build --release --locked --manifest-path "$here/Cargo.toml"

mkdir -p "$(dirname "$out")"
install -m 0755 "$target/release/clientservices-rs" "$out.new"
mv -f "$out.new" "$out"
echo "built $out"
