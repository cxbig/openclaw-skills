#!/usr/bin/env zsh
set -euo pipefail

# User-run script.
# Build the Rust release binary and place it in this skill's scripts/ directory.
# No system-wide install is performed.

cd "${0:A:h}/.."

if ! command -v cargo >/dev/null 2>&1; then
  echo "ERROR: Rust toolchain not found (cargo missing)." >&2
  echo "Install Rust first, e.g.: https://rustup.rs" >&2
  exit 2
fi

cargo build --release

bin="target/release/git-repo-batch-refresh"
out="scripts/git-repo-batch-refresh"

if [[ ! -f "$bin" ]]; then
  echo "ERROR: build succeeded but binary not found: $bin" >&2
  exit 3
fi

cp -f "$bin" "$out"
chmod 0755 "$out"

echo "Built: $bin"
echo "Output: $out (mode 0755)"
echo "Note: run this script manually when you want to rebuild the CLI."
