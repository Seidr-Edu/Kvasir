#!/usr/bin/env bash
# tp_write_guard.sh - tests-only write scope and immutability guards.

set -euo pipefail

tp_is_allowed_test_path() {
  local rel="$1"
  case "$TP_WRITE_SCOPE_POLICY" in
    tests-only)
      case "$rel" in
        ./src/test/*|./src/*Test*/*|./test/*|./tests/*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

tp_is_ignored_write_scope_path() {
  local rel="$1"
  local prefix
  for prefix in "${TP_WRITE_SCOPE_IGNORED_PREFIXES[@]+"${TP_WRITE_SCOPE_IGNORED_PREFIXES[@]}"}"; do
    case "$rel" in
      "$prefix"*) return 0 ;;
    esac
  done
  return 1
}

tp_write_repo_manifest() {
  local repo="$1"
  local manifest_file="$2"

  : > "$manifest_file"
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    if tp_is_ignored_write_scope_path "$rel"; then
      continue
    fi
    local abs="${repo}/${rel#./}"
    printf '%s\t%s\n' "$rel" "$(tp_sha256_file "$abs")" >> "$manifest_file"
  done < <(
    cd "$repo" && find . -type f \
      ! -path './.git/*' \
      ! -path './.mvn_repo/*' \
      ! -path './.m2/*' \
      ! -path './target/*' \
      ! -path './build/*' \
      ! -path './.gradle/*' \
      ! -path './.scannerwork/*' \
      ! -path './out/*' \
      -print | LC_ALL=C sort
  )
}

tp_check_write_scope() {
  local repo="$1"
  local before_file="$2"
  local after_file="$3"

  local joined_file="${TP_GUARDS_DIR}/ported-protected-joined.tsv"
  local changes_file="${TP_GUARDS_DIR}/ported-protected-change-set.tsv"
  local diff_file="${TP_GUARDS_DIR}/disallowed-change.diff"

  tp_write_repo_manifest "$repo" "$after_file"

  : > "$joined_file"
  : > "$changes_file"
  : > "$diff_file"

  if ! command -v join >/dev/null 2>&1; then
    tp_err "tp_write_guard: required command 'join' not found"
    return 2
  fi

  if ! join -t $'\t' -a1 -a2 -e '__MISSING__' -o '0,1.2,2.2' \
    "$before_file" "$after_file" > "$joined_file"; then
    tp_err "tp_write_guard: failed to compute write-scope change set"
    return 2
  fi

  local bad=0
  local violations=0
  while IFS=$'\t' read -r rel before_hash after_hash; do
    [[ -n "$rel" ]] || continue
    if tp_is_ignored_write_scope_path "$rel"; then
      continue
    fi

    local kind=""
    if [[ "$before_hash" == "__MISSING__" ]]; then
      kind="A"
    elif [[ "$after_hash" == "__MISSING__" ]]; then
      kind="D"
    elif [[ "$before_hash" != "$after_hash" ]]; then
      kind="M"
    else
      continue
    fi

    printf '%s\t%s\n' "$kind" "$rel" >> "$changes_file"

    if ! tp_is_allowed_test_path "$rel"; then
      printf '%s\t%s\n' "$kind" "$rel" >> "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
      printf '%s\t%s\n' "$kind" "$rel" >> "$diff_file"
      violations=$((violations + 1))
      bad=1
    fi
  done < "$joined_file"

  TP_WRITE_SCOPE_VIOLATION_COUNT="$violations"
  return "$bad"
}

tp_finalize_generated_repo_immutability_guard() {
  TP_GENERATED_REPO_AFTER_HASH="$(tp_tree_fingerprint "$TP_GENERATED_REPO")"
  printf '%s\n' "$TP_GENERATED_REPO_AFTER_HASH" > "$TP_GENERATED_AFTER_HASH_PATH"
  [[ "$TP_GENERATED_REPO_BEFORE_HASH" == "$TP_GENERATED_REPO_AFTER_HASH" ]] || TP_GENERATED_REPO_UNCHANGED=false
}
