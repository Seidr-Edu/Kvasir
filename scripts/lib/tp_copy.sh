#!/usr/bin/env bash
# tp_copy.sh - workspace copy/snapshot helpers.

set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tp_discovery.sh"

tp_fix_maven_offline_config() {
  # Strip a bare -o (offline) flag from .mvn/maven.config when there is no
  # accompanying local Maven repository. An offline flag without a cache will
  # cause every Maven invocation to fail with dependency-resolution errors.
  local repo="$1"
  local config="$repo/.mvn/maven.config"
  [[ -f "$config" ]] || return 0

  LC_ALL=C grep -qwF -- '-o' "$config" 2>/dev/null || return 0

  # Check for an accompanying local repo in the standard locations andvari uses
  if [[ -d "$repo/.mvn/repository" || -d "$repo/.mvn_repo" || -d "$repo/.m2" ]]; then
    return 0
  fi

  # No local cache: strip the flag
  local new_content
  new_content="$(LC_ALL=C sed -E 's/(^| )-o( |$)/\1\2/g; s/[[:space:]]+/ /g; s/^[[:space:]]+//; s/[[:space:]]+$//' "$config")"
  if [[ -z "$(printf '%s' "$new_content" | tr -d '[:space:]')" ]]; then
    rm -f "$config"
  else
    printf '%s\n' "$new_content" > "$config"
  fi
}

tp_prepare_workspace_copies() {
  mkdir -p "$TP_WORKSPACE_DIR" "$TP_LOG_DIR" "$TP_SUMMARY_DIR" "$TP_GUARDS_DIR" "$TP_OUTPUT_DIR"

  tp_copy_dir "$TP_ORIGINAL_EFFECTIVE_PATH" "$TP_ORIGINAL_BASELINE_REPO" || return 1
  tp_copy_dir "$TP_GENERATED_REPO" "$TP_GENERATED_BASELINE_REPO" || return 1
  tp_copy_dir "$TP_GENERATED_REPO" "$TP_PORTED_REPO" || return 1

  # Remove bare Maven offline flags from workspace copies if there is no
  # local Maven cache — such configs make all Maven builds fail immediately.
  tp_fix_maven_offline_config "$TP_GENERATED_BASELINE_REPO" || return 1
  tp_fix_maven_offline_config "$TP_PORTED_REPO" || return 1

  TP_GENERATED_REPO_BEFORE_HASH="$(tp_tree_fingerprint "$TP_GENERATED_REPO")"
  printf '%s\n' "$TP_GENERATED_REPO_BEFORE_HASH" > "$TP_GENERATED_BEFORE_HASH_PATH"
}

tp_snapshot_original_tests() {
  rm -rf "$TP_ORIGINAL_TESTS_SNAPSHOT"
  mkdir -p "$TP_ORIGINAL_TESTS_SNAPSHOT"

  if ! tp_discovery_scan_repo "$TP_ORIGINAL_EFFECTIVE_PATH" "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH"; then
    return 1
  fi
  eval "$(tp_discovery_load_shell_state "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH")"
  TP_ORIGINAL_DISCOVERED_TEST_FILE_COUNT="${TP_DISCOVERED_TEST_FILE_COUNT:-0}"

  local copied_count
  if ! copied_count="$(tp_discovery_copy_from_manifest "$TP_ORIGINAL_EFFECTIVE_PATH" "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH" "$TP_ORIGINAL_TESTS_SNAPSHOT")"; then
    return 1
  fi
  if [[ "${copied_count:-0}" -le 0 ]] || ! find "$TP_ORIGINAL_TESTS_SNAPSHOT" -type f -print -quit | grep -q .; then
    return 1
  fi
  return 0
}

tp_seed_ported_repo_with_original_tests() {
  mkdir -p "$TP_PORTED_REPO"

  if [[ -z "${TP_DISCOVERED_TEST_ROOTS_CSV:-}" && -f "${TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH:-}" ]]; then
    eval "$(tp_discovery_load_shell_state "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH")"
  fi
  tp_refresh_ported_discovered_test_roots_state

  local root
  local -a roots=()
  IFS=':' read -r -a roots <<< "${TP_PORTED_DISCOVERED_TEST_ROOTS_CSV:-}"
  for root in "${roots[@]+"${roots[@]}"}"; do
    [[ -n "$root" ]] || continue
    rm -rf "${TP_PORTED_REPO}/${root#./}" 2>/dev/null || true
  done

  tp_discovery_copy_from_manifest "$TP_ORIGINAL_EFFECTIVE_PATH" "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH" "$TP_PORTED_REPO" >/dev/null || return 1
}
