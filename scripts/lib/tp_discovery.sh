#!/usr/bin/env bash
# tp_discovery.sh - canonical original test discovery helpers.

set -euo pipefail

TP_DISCOVERY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TP_DISCOVERY_PY="${TP_DISCOVERY_SCRIPT_DIR}/tp_discovery.py"

tp_discovery_scan_repo() {
  local repo="$1"
  local out_json="$2"
  python3 "$TP_DISCOVERY_PY" scan "$repo" --json-out "$out_json"
}

tp_discovery_count_test_files() {
  local repo="$1"
  python3 "$TP_DISCOVERY_PY" count "$repo"
}

tp_discovery_print_roots() {
  local repo="$1"
  python3 "$TP_DISCOVERY_PY" roots "$repo"
}

tp_discovery_load_shell_state() {
  local manifest_json="$1"
  python3 "$TP_DISCOVERY_PY" shell-state "$manifest_json"
}

tp_discovery_copy_from_manifest() {
  local source="$1"
  local manifest_json="$2"
  local target="$3"
  if [[ -n "${TP_GENERATED_EFFECTIVE_SUBDIR:-}" ]]; then
    python3 "$TP_DISCOVERY_PY" copy "$source" "$manifest_json" "$target" --generated-subdir "$TP_GENERATED_EFFECTIVE_SUBDIR"
  else
    python3 "$TP_DISCOVERY_PY" copy "$source" "$manifest_json" "$target"
  fi
}

tp_map_discovered_test_root_to_ported_repo_rel() {
  local root="$1"
  local generated_subdir="${TP_GENERATED_EFFECTIVE_SUBDIR:-}"
  if [[ -z "$generated_subdir" ]]; then
    printf '%s\n' "$root"
    return 0
  fi

  local prefix="./${generated_subdir#./}"
  prefix="${prefix%/}"
  case "$root" in
    "$prefix"|"$prefix"/*)
      printf '%s\n' "$root"
      ;;
    *)
      printf '%s/%s\n' "$prefix" "${root#./}"
      ;;
  esac
}

tp_refresh_ported_discovered_test_roots_state() {
  TP_PORTED_DISCOVERED_TEST_ROOTS_CSV=""
  local root mapped
  local -a roots=()
  IFS=':' read -r -a roots <<< "${TP_DISCOVERED_TEST_ROOTS_CSV:-}"
  for root in "${roots[@]+"${roots[@]}"}"; do
    [[ -n "$root" ]] || continue
    mapped="$(tp_map_discovered_test_root_to_ported_repo_rel "$root")"
    if [[ -z "$TP_PORTED_DISCOVERED_TEST_ROOTS_CSV" ]]; then
      TP_PORTED_DISCOVERED_TEST_ROOTS_CSV="$mapped"
    else
      TP_PORTED_DISCOVERED_TEST_ROOTS_CSV="${TP_PORTED_DISCOVERED_TEST_ROOTS_CSV}:$mapped"
    fi
  done
}
