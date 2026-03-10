#!/usr/bin/env bash
# tp_copy.sh - workspace copy/snapshot helpers.

set -euo pipefail

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
  mkdir -p "$TP_ORIGINAL_TESTS_SNAPSHOT"
  if ! rsync -a --prune-empty-dirs \
    --include='*/' \
    --include='src/test/***' \
    --include='src/*Test*/***' \
    --include='test/***' \
    --include='tests/***' \
    --exclude='*' \
    "$TP_ORIGINAL_EFFECTIVE_PATH/" "$TP_ORIGINAL_TESTS_SNAPSHOT/" >/dev/null 2>&1; then
    return 1
  fi
  if ! find "$TP_ORIGINAL_TESTS_SNAPSHOT" -type f -print -quit | grep -q .; then
    return 1
  fi
  return 0
}

tp_seed_ported_repo_with_original_tests() {
  local target_root="${TP_PORTED_EFFECTIVE_REPO:-$TP_PORTED_REPO}"
  mkdir -p "$target_root"

  find "$target_root" -type d \
    \( -path '*/src/test' -o -path '*/test' -o -path '*/tests' -o -path '*/src/*Test*' \) \
    -prune -exec rm -rf {} + 2>/dev/null || true

  rsync -a "$TP_ORIGINAL_TESTS_SNAPSHOT/" "$target_root/" >/dev/null 2>&1 || return 1
}
