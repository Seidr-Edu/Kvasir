#!/usr/bin/env bash
# tp_common.sh - shared utilities for standalone test-port runs.

set -euo pipefail

tp_timestamp_compact_utc() { date -u +"%Y%m%dT%H%M%SZ"; }
tp_timestamp_iso_utc() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

tp_log() { printf '[test-port][INFO] %s %s\n' "$(tp_timestamp_iso_utc)" "$*" >&2; }
tp_warn() { printf '[test-port][WARN] %s %s\n' "$(tp_timestamp_iso_utc)" "$*" >&2; }
tp_err() { printf '[test-port][ERROR] %s %s\n' "$(tp_timestamp_iso_utc)" "$*" >&2; }
tp_fail() { tp_err "$*"; exit 1; }

tp_sha256_file() {
  local target="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$target" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$target" | awk '{print $1}'
  else
    cksum "$target" | awk '{print $1}'
  fi
}

tp_tree_fingerprint() {
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    echo "missing"
    return 0
  fi
  local manifest
  manifest="$(mktemp)"
  (
    cd "$dir"
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      printf '%s\t%s\n' "$rel" "$(tp_sha256_file "${dir}/${rel#./}")"
    done < <(find . -type f ! -path './.git/*' -print | LC_ALL=C sort)
  ) > "$manifest"
  tp_sha256_file "$manifest"
  rm -f "$manifest"
}

tp_copy_dir() {
  local src="$1"
  local dest="$2"
  rm -rf "$dest"
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
}

tp_abs_path() {
  local p="$1"
  python3 - <<'PY' "$p"
import os,sys
print(os.path.abspath(sys.argv[1]))
PY
}

tp_sanitize_id_component() {
  local raw="$1"
  raw="${raw##*/}"
  raw="${raw%.git}"
  raw="$(printf '%s' "$raw" | tr '[:space:]/:@' '_____' | tr -cd 'A-Za-z0-9._-')"
  [[ -n "$raw" ]] || raw="repo"
  printf '%s\n' "$raw"
}

tp_normalize_repo_prefix() {
  local raw="$1"
  [[ -n "$raw" ]] || return 1
  [[ "$raw" != /* ]] || return 1
  [[ "$raw" != *:* ]] || return 1

  while [[ "$raw" == ./* ]]; do
    raw="${raw#./}"
  done

  raw="$(printf '%s' "$raw" | sed -E 's#/+#/#g')"

  while [[ "$raw" == */ ]]; do
    raw="${raw%/}"
  done

  [[ -n "$raw" ]] || return 1
  case "$raw" in
    .|..|../*|*/..|*/../*|./*|*/.|*/./*)
      return 1
      ;;
  esac

  printf './%s/\n' "$raw"
}
