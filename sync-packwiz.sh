#!/usr/bin/env bash
# Bring packwiz/mods into parity with a Modrinth modpack index
# (default: archive/modrinth.index.json).
#
#   ./sync-packwiz.sh            # dry run, prints planned changes
#   ./sync-packwiz.sh --apply    # applies changes, then runs packwiz refresh
#   ./sync-packwiz.sh --apply --pin   # also pins every synced mod
#   ./sync-packwiz.sh [--apply] [index.json]
#
# Rules:
#   - Mods in the index at a different version are re-added at the index version.
#   - Mods in the index but missing from packwiz are added.
#   - Mods in packwiz but absent from the index (or not from Modrinth) are removed.
#   - Index entries ending in ".disabled" are treated as absent (removed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PW_DIR="$ROOT/packwiz"
PW="$ROOT/bin/packwiz"
INDEX="$ROOT/archive/modrinth.index.json"
APPLY=0
PIN=0

for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    --pin) PIN=1 ;;
    -h|--help) sed -n '2,15p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) INDEX="$arg" ;;
  esac
done

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }
[ -x "$PW" ] || PW="$(command -v packwiz || true)"
[ -n "$PW" ] || { echo "packwiz not found" >&2; exit 1; }
[ -f "$INDEX" ] || { echo "index not found: $INDEX" >&2; exit 1; }

run() {
  if [ "$APPLY" -eq 1 ]; then "$@"; else echo "  (dry-run) $*"; fi
}

# project-id<TAB>version-id<TAB>filename for each enabled index entry
desired="$(jq -r '.files[]
  | select(.path | endswith(".disabled") | not)
  | .downloads[0] as $u
  | ($u | capture("data/(?<p>[^/]+)/versions/(?<v>[^/]+)/")) as $m
  | [$m.p, $m.v, (.path | sub("^mods/"; ""))] | @tsv' "$INDEX")"

# project-id<TAB>version-id<TAB>metafile for each packwiz mod
current="$(cd "$PW_DIR" && for f in mods/*.pw.toml; do
  p="$(sed -n 's/^mod-id *= *"\(.*\)"/\1/p' "$f" | head -1)"
  v="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$f" | head -1)"
  printf '%s\t%s\t%s\n' "${p:--}" "${v:--}" "$f"
done)"

added=0 updated=0 removed=0 same=0

cd "$PW_DIR"

# Remove first so that re-adding a mod can't be undone by a later removal.
# Non-Modrinth entries (e.g. CurseForge) are always replaced by the index.
while IFS=$'\t' read -r pid _ f; do
  [ -n "$f" ] || continue
  if [ "$pid" = "-" ] || ! cut -f1 <<<"$desired" | grep -qx "$pid"; then
    echo "REMOVE  $f ($([ "$pid" = "-" ] && echo non-Modrinth || echo "$pid"))"
    run "$PW" remove -y "$(basename "$f" .pw.toml)"
    removed=$((removed + 1))
  fi
done <<<"$current"

# Add or update
while IFS=$'\t' read -r pid vid fname; do
  [ -n "$pid" ] || continue
  cur="$(awk -F'\t' -v p="$pid" '$1==p {print $2 "\t" $3; exit}' <<<"$current")"
  if [ -z "$cur" ]; then
    echo "ADD     $fname ($pid @ $vid)"
    run "$PW" modrinth add --project-id "$pid" --version-id "$vid" -y
    added=$((added + 1))
  else
    cur_v="${cur%%$'\t'*}"
    cur_f="${cur#*$'\t'}"
    if [ "$cur_v" != "$vid" ]; then
      echo "UPDATE  $cur_f: $cur_v -> $vid ($fname)"
      run "$PW" remove -y "$(basename "$cur_f" .pw.toml)"
      run "$PW" modrinth add --project-id "$pid" --version-id "$vid" -y
      updated=$((updated + 1))
    else
      same=$((same + 1))
    fi
  fi
  if [ "$PIN" -eq 1 ] && [ "$APPLY" -eq 1 ]; then
    slug="$(basename "$(grep -l "^mod-id *= *\"$pid\"" mods/*.pw.toml | head -1)" .pw.toml)"
    "$PW" pin "$slug" || true
  fi
done <<<"$desired"

echo
echo "unchanged: $same  added: $added  updated: $updated  removed: $removed"

if [ "$APPLY" -eq 1 ]; then
  "$PW" refresh
else
  echo "Dry run only. Re-run with --apply to make changes."
fi
