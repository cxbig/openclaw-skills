#!/bin/zsh
set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
ARCHIVE_DIR="$OPENCLAW_DIR/.archived"
OS_NAME="$(uname -s)"
DRY_RUN=1

typeset -A RESERVED_DESTS

if [[ "${1:-}" == "--apply" ]]; then
  DRY_RUN=0
elif [[ "${1:-}" == "--dry-run" || -z "${1:-}" ]]; then
  DRY_RUN=1
else
  echo "Usage: $0 [--dry-run|--apply]" >&2
  exit 1
fi

mkdir -p "$ARCHIVE_DIR"

is_bak_candidate() {
  local name="$1"
  local lower="${name:l}"
  [[ "$name" == openclaw* && "$lower" == *bak* ]]
}

is_new_canonical_name() {
  local name="$1"
  [[ "$name" =~ ^openclaw\.bak\.[0-9]{8}-[0-9]{6}\.json$ ]]
}

is_old_no_bak_canonical_name() {
  local name="$1"
  [[ "$name" =~ ^openclaw\.[0-9]{8}-[0-9]{6}\.json$ ]]
}

canonical_epoch_for_file() {
  local file="$1"
  local ts=""

  # Try GNU stat first (Linux), then BSD stat (macOS). Avoid relying on uname only.
  ts=$(stat -c '%Z' "$file" 2>/dev/null || true)
  if [[ -z "$ts" || "$ts" != <-> ]]; then
    ts=$(stat -c '%Y' "$file" 2>/dev/null || true)
  fi
  if [[ -z "$ts" || "$ts" != <-> ]]; then
    ts=$(stat -f '%c' "$file" 2>/dev/null || true)
  fi
  if [[ -z "$ts" || "$ts" != <-> ]]; then
    ts=$(stat -f '%m' "$file" 2>/dev/null || true)
  fi

  if [[ -z "$ts" || "$ts" != <-> ]]; then
    echo "Failed to read timestamp for: $file" >&2
    return 1
  fi

  print -r -- "$ts"
}

fmt_ts() {
  local epoch="$1"
  if [[ "$OS_NAME" == "Darwin" ]]; then
    date -r "$epoch" '+%Y%m%d-%H%M%S'
  else
    date -d "@$epoch" '+%Y%m%d-%H%M%S'
  fi
}

parse_ts_to_epoch() {
  local ts="$1"
  if [[ "$OS_NAME" == "Darwin" ]]; then
    date -j -f '%Y%m%d-%H%M%S' "$ts" '+%s'
  else
    date -d "${ts:0:8} ${ts:9:2}:${ts:11:2}:${ts:13:2}" '+%s'
  fi
}

is_reserved() {
  local p="$1"
  [[ -n "${RESERVED_DESTS[$p]-}" ]]
}

reserve_dest() {
  local p="$1"
  RESERVED_DESTS[$p]=1
}

unique_archive_dest_from_epoch() {
  local epoch="$1"
  local ts cand

  while true; do
    ts=$(fmt_ts "$epoch")
    cand="$ARCHIVE_DIR/openclaw.bak.${ts}.json"
    if [[ ! -e "$cand" ]] && ! is_reserved "$cand"; then
      print -r -- "$cand"
      return 0
    fi
    epoch=$((epoch + 1))
  done
}

unique_archive_dest_from_ts() {
  local ts="$1"
  local cand="$ARCHIVE_DIR/openclaw.bak.${ts}.json"
  local epoch

  if [[ ! -e "$cand" ]] && ! is_reserved "$cand"; then
    print -r -- "$cand"
    return 0
  fi

  # if direct target collides, continue by +1 second
  epoch=$(parse_ts_to_epoch "$ts")
  epoch=$((epoch + 1))
  unique_archive_dest_from_epoch "$epoch"
}

detect_trash_backend() {
  if command -v trash >/dev/null 2>&1; then
    print -r -- "trash"
    return 0
  fi
  if command -v gio >/dev/null 2>&1; then
    print -r -- "gio"
    return 0
  fi
  if command -v trash-put >/dev/null 2>&1; then
    print -r -- "trash-put"
    return 0
  fi
  return 1
}

run_trash() {
  local src="$1" note="${2:-}"
  local backend="${TRASH_BACKEND:-}"

  if [[ -n "$note" ]]; then
    echo "[TRASH] $src ($note)"
  else
    echo "[TRASH] $src"
  fi

  if (( DRY_RUN == 1 )); then
    echo "        backend: ${backend:-<none>}"
    return 0
  fi

  if [[ -z "$backend" ]]; then
    echo "No trash CLI backend available (expected one of: trash, gio, trash-put)." >&2
    return 1
  fi

  case "$backend" in
    trash)
      trash -- "$src"
      ;;
    gio)
      gio trash "$src"
      ;;
    trash-put)
      trash-put "$src"
      ;;
    *)
      echo "Unsupported trash backend: $backend" >&2
      return 1
      ;;
  esac
}

run_move() {
  local tag="$1" src="$2" dst="$3" note="${4:-}"
  if [[ -n "$note" ]]; then
    echo "[$tag] $src -> $dst ($note)"
  else
    echo "[$tag] $src -> $dst"
  fi

  if (( DRY_RUN == 0 )); then
    mv "$src" "$dst"
  fi
}

TRASH_BACKEND=""
if TRASH_BACKEND=$(detect_trash_backend); then
  :
else
  TRASH_BACKEND=""
fi

# 1) Trash archived files older than 30 days by mtime
while IFS= read -r -d '' f; do
  run_trash "$f" "mtime>30d"
done < <(find "$ARCHIVE_DIR" -type f -mtime +30 -print0)

# 2) Root + archive: files starting with openclaw and containing bak
#    - if already in archive and already new canonical => skip
#    - otherwise move/rename to archive/openclaw.bak.YYYYMMDD-HHMMSS.json
while IFS= read -r -d '' f; do
  name="${f:t}"
  if ! is_bak_candidate "$name"; then
    continue
  fi

  if [[ "$f" == "$ARCHIVE_DIR"/* ]] && is_new_canonical_name "$name"; then
    continue
  fi

  epoch=$(canonical_epoch_for_file "$f")
  dest=$(unique_archive_dest_from_epoch "$epoch")
  reserve_dest "$dest"
  run_move "ARCHIVE" "$f" "$dest"
done < <(
  find "$OPENCLAW_DIR" -mindepth 1 -maxdepth 1 -type f -print0
  find "$ARCHIVE_DIR" -type f -print0
)

# 3) Fix old archived files without .bak. part:
#    openclaw.YYYYMMDD-HHMMSS.json -> openclaw.bak.YYYYMMDD-HHMMSS.json
while IFS= read -r -d '' f; do
  name="${f:t}"
  if is_old_no_bak_canonical_name "$name"; then
    ts="${name#openclaw.}"
    ts="${ts%.json}"
    dest=$(unique_archive_dest_from_ts "$ts")
    [[ "$f" == "$dest" ]] && continue
    reserve_dest "$dest"
    run_move "NORMALIZE" "$f" "$dest"
  fi
done < <(find "$ARCHIVE_DIR" -type f -print0)
