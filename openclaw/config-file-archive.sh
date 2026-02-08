#!/usr/bin/env zsh
# Archive OpenClaw config backup files with timestamped names.
# Usage: config-file-archive.sh (no arguments needed)

set -euo pipefail

workspace="$HOME/.openclaw"

[[ -d "$workspace" ]] || { echo "Error: OpenClaw config directory not found: $workspace" >&2; exit 1; }

archived="$workspace/.archived"
[[ -d "$archived" ]] || mkdir -p "$archived"

for f in "$workspace"/openclaw.json.bak*(N); do
  old_name="${f:t}"
  # Get file creation time (birth time) on macOS
  ctime=$(stat -f '%SB' -t '%Y%m%d-%H%M%S' "$f")
  new_name="openclaw.bak.${ctime}.json"
  echo "Move backup config file: ${old_name} => .archived/${new_name}"
  mv "$f" "$archived/$new_name"
done
