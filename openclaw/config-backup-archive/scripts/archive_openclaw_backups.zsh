#!/bin/zsh
set -euo pipefail

OPENCLAW_DIR="$HOME/.openclaw"
ARCHIVE_DIR="$OPENCLAW_DIR/.archived"
TRASH_DIR="$HOME/.Trash"
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
mkdir -p "$TRASH_DIR"

is_bak_candidate() {
  local name="$1"
  local lower="${name:l}"
  [[ "$name" == openclaw* && "$lower" == *bak* ]]
}

is_new_canonical_name() {
  local name="$1"
  [[ "$name" =~ '^openclaw\.bak\.[0-9]{8}-[0-9]{6}\.json$' ]]
}

is_old_no_bak_canonical_name() {
  local name="$1"
  [[ "$name" =~ '^openclaw\.[0-9]{8}-[0-9]{6}\.json$' ]]
}

canonical_epoch_for_file() {
  local path="$1"
  local ts

  ts=$(/usr/bin/stat -f '%c' "$path" 2>/dev/null || true)
  if [[ -z "$ts" || ! "$ts" =~ '^[0-9]+$' ]]; then
    ts=$(/usr/bin/stat -f '%m' "$path")
  fi
  print -r -- "$ts"
}

fmt_ts() {
  local epoch="$1"
  /bin/date -r "$epoch" '+%Y%m%d-%H%M%S'
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
  epoch=$(/bin/date -j -f '%Y%m%d-%H%M%S' "$ts" '+%s')
  epoch=$((epoch + 1))
  unique_archive_dest_from_epoch "$epoch"
}

unique_trash_dest() {
  local base="$1"
  local cand="$TRASH_DIR/$base"
  local stem ext i

  if [[ ! -e "$cand" ]] && ! is_reserved "$cand"; then
    print -r -- "$cand"
    return 0
  fi

  stem="${base%.*}"
  ext="${base##*.}"
  i=1
  while true; do
    cand="$TRASH_DIR/${stem}.${i}.${ext}"
    if [[ ! -e "$cand" ]] && ! is_reserved "$cand"; then
      print -r -- "$cand"
      return 0
    fi
    ((i++))
  done
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

# 1) Trash archived files older than 30 days by mtime
while IFS= read -r -d '' f; do
  dest=$(unique_trash_dest "${f:t}")
  reserve_dest "$dest"
  run_move "TRASH" "$f" "$dest" "mtime>30d"
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
