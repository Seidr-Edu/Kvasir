#!/usr/bin/env bash
# tp_write_guard.sh - tests-only write scope and immutability guards.

set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tp_discovery.sh"

tp_line_in_file() {
  local needle="$1"
  local file="$2"
  [[ -f "$file" ]] || return 1
  LC_ALL=C grep -Fqx -- "$needle" "$file"
}

tp_link_count() {
  local path="$1"
  if stat -f '%l' "$path" >/dev/null 2>&1; then
    stat -f '%l' "$path"
  else
    stat -c '%h' "$path"
  fi
}

tp_resolve_repo_canonical_path() {
  local repo="$1"
  local rel="$2"

  python3 - <<'PY' "$repo" "$rel"
import os
import sys

repo = os.path.realpath(sys.argv[1])
rel = sys.argv[2]
if rel.startswith("./"):
    rel = rel[2:]
candidate = os.path.realpath(os.path.join(repo, rel))
if os.path.commonpath([repo, candidate]) != repo:
    raise SystemExit(1)
print(candidate)
PY
}

tp_is_allowed_write_operation() {
  local kind="$1"
  local rel="$2"
  local old_rel="${3:-}"

  case "$kind" in
    A|M|D)
      if tp_is_denied_write_scope_path "$rel"; then
        return 1
      fi
      tp_is_allowed_test_path "$rel"
      ;;
    R)
      if tp_is_denied_write_scope_path "$rel"; then
        return 1
      fi
      if [[ -n "$old_rel" ]] && tp_is_denied_write_scope_path "$old_rel"; then
        return 1
      fi
      tp_is_allowed_test_path "$rel" && { [[ -z "$old_rel" ]] || tp_is_allowed_test_path "$old_rel"; }
      ;;
    *)
      return 1
      ;;
  esac
}

tp_compute_rename_pairs() {
  local joined_file="$1"
  local pairs_file="$2"
  local old_paths_file="$3"
  local new_paths_file="$4"

  : > "$pairs_file"
  : > "$old_paths_file"
  : > "$new_paths_file"

  local add_file del_file
  add_file="$(mktemp)"
  del_file="$(mktemp)"

  awk -F $'\t' '($2 == "__MISSING__" && $3 != "__MISSING__") { print $3 "\t" $1 }' "$joined_file" | LC_ALL=C sort > "$add_file"
  awk -F $'\t' '($3 == "__MISSING__" && $2 != "__MISSING__") { print $2 "\t" $1 }' "$joined_file" | LC_ALL=C sort > "$del_file"

  if [[ -s "$add_file" && -s "$del_file" ]]; then
    join -t $'\t' -o '1.2,2.2,1.1' "$del_file" "$add_file" > "$pairs_file" || true
  fi

  awk -F $'\t' '{ print $1 }' "$pairs_file" > "$old_paths_file"
  awk -F $'\t' '{ print $2 }' "$pairs_file" > "$new_paths_file"

  rm -f "$add_file" "$del_file"
}

tp_is_allowed_test_path() {
  local rel="$1"
  local root
  local glob

  if [[ -z "${TP_DISCOVERED_TEST_ROOTS_CSV:-}" && -f "${TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH:-}" ]]; then
    eval "$(tp_discovery_load_shell_state "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH")"
  fi
  tp_refresh_ported_discovered_test_roots_state

  local -a discovered_roots=()
  IFS=':' read -r -a discovered_roots <<< "${TP_PORTED_DISCOVERED_TEST_ROOTS_CSV:-}"
  for root in "${discovered_roots[@]+"${discovered_roots[@]}"}"; do
    [[ -n "$root" ]] || continue
    case "$rel" in
      "$root"|"$root"/*)
        return 0
        ;;
    esac
  done

  for glob in "${TP_ALLOWED_MODEL_TEST_WRITES_GLOBS[@]+"${TP_ALLOWED_MODEL_TEST_WRITES_GLOBS[@]}"}"; do
    case "$rel" in
      "$glob")
        return 0
        ;;
    esac
  done

  # Backward compatibility fallback.
  case "$rel" in
    ./src/test/*|./src/*Test*/*|./src/*IT*/*|./src/*Integration*/*|./src/*Functional*/*|./src/*E2E*/*|./src/it/*|./src/integration/*|./src/functional/*|./src/e2e/*|./test/*|./tests/*) return 0 ;;
  esac
  return 1
}

tp_is_ignored_write_scope_path() {
  local rel="$1"
  local prefix
  for prefix in "${TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES[@]+"${TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES[@]}"}"; do
    case "$rel" in
      "$prefix"*) return 0 ;;
    esac
  done

  for prefix in "${TP_WRITE_SCOPE_IGNORED_PREFIXES[@]+"${TP_WRITE_SCOPE_IGNORED_PREFIXES[@]}"}"; do
    case "$rel" in
      "$prefix"*) return 0 ;;
    esac
  done

  return 1
}

tp_is_denied_write_scope_path() {
  local rel="$1"
  local prefix
  for prefix in "${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[@]+"${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[@]}"}"; do
    case "$rel" in
      "$prefix"*) return 0 ;;
    esac
  done
  return 1
}

tp_apply_workspace_write_policy() {
  local repo="$1"
  local root
  local prefix
  local abs

  for prefix in "${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[@]+"${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[@]}"}"; do
    abs="${repo}/${prefix#./}"
    while [[ "$abs" == */ ]]; do
      abs="${abs%/}"
    done
    [[ -e "$abs" ]] || continue
    if [[ -d "$abs" ]]; then
      find "$abs" -type f -exec chmod ugo-w {} + 2>/dev/null || true
      find "$abs" -type d -exec chmod u+w {} + 2>/dev/null || true
    else
      chmod ugo-w "$abs" 2>/dev/null || true
    fi
  done

  if [[ -z "${TP_DISCOVERED_TEST_ROOTS_CSV:-}" && -f "${TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH:-}" ]]; then
    eval "$(tp_discovery_load_shell_state "$TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH")"
  fi
  tp_refresh_ported_discovered_test_roots_state

  local -a discovered_roots=()
  IFS=':' read -r -a discovered_roots <<< "${TP_PORTED_DISCOVERED_TEST_ROOTS_CSV:-}"
  for root in "${discovered_roots[@]+"${discovered_roots[@]}"}"; do
    [[ -n "$root" ]] || continue
    abs="${repo}/${root#./}"
    [[ -e "$abs" ]] || continue
    chmod -R u+w "$abs" 2>/dev/null || true
  done

  for abs in "$repo/src/test" "$repo/src/it" "$repo/src/integration" "$repo/src/functional" "$repo/src/e2e" "$repo/test" "$repo/tests"; do
    [[ -e "$abs" ]] || continue
    chmod -R u+w "$abs" 2>/dev/null || true
  done

  if [[ -d "$repo/src" ]]; then
    while IFS= read -r abs; do
      [[ -n "$abs" ]] || continue
      chmod -R u+w "$abs" 2>/dev/null || true
    done < <(find "$repo/src" -type d \( -name '*Test*' -o -name '*IT*' -o -name '*Integration*' -o -name '*Functional*' -o -name '*E2E*' \) -print 2>/dev/null)
  fi

  # Ensure common writable roots remain writable for service/test tools.
  local rel
  for rel in ./target ./build ./.m2 ./.gradle ./completion/proof/logs; do
    abs="${repo}/${rel#./}"
    [[ -e "$abs" ]] || continue
    chmod -R u+w "$abs" 2>/dev/null || true
  done
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

    local canonical_abs
    if ! canonical_abs="$(tp_resolve_repo_canonical_path "$repo" "$rel")"; then
      tp_err "tp_write_guard: repo path escapes canonical root: ${rel}"
      return 2
    fi

    if [[ -L "$canonical_abs" ]]; then
      tp_err "tp_write_guard: symlink target is not allowed in manifest: ${rel}"
      return 2
    fi

    local nlink
    nlink="$(tp_link_count "$canonical_abs" 2>/dev/null || echo 1)"
    if [[ "$nlink" =~ ^[0-9]+$ ]] && [[ "$nlink" -gt 1 ]]; then
      tp_err "tp_write_guard: hard-link alias detected for ${rel}"
      return 2
    fi

    local abs="${repo}/${rel#./}"
    printf '%s\t%s\n' "$rel" "$(tp_sha256_file "$abs")" >> "$manifest_file"
  done < <(
    cd "$repo" && find . -type f ! -type l \
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
  local rename_pairs_file="${TP_GUARDS_DIR}/ported-protected-rename-pairs.tsv"
  local rename_old_paths_file="${TP_GUARDS_DIR}/ported-protected-rename-old-paths.tsv"
  local rename_new_paths_file="${TP_GUARDS_DIR}/ported-protected-rename-new-paths.tsv"

  if ! tp_write_repo_manifest "$repo" "$after_file"; then
    tp_err "tp_write_guard: failed to generate after manifest"
    return 2
  fi

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

  tp_compute_rename_pairs "$joined_file" "$rename_pairs_file" "$rename_old_paths_file" "$rename_new_paths_file"

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
      if tp_line_in_file "$rel" "$rename_new_paths_file"; then
        continue
      fi
    elif [[ "$after_hash" == "__MISSING__" ]]; then
      kind="D"
      if tp_line_in_file "$rel" "$rename_old_paths_file"; then
        continue
      fi
    elif [[ "$before_hash" != "$after_hash" ]]; then
      kind="M"
    else
      continue
    fi

    printf '%s\t%s\n' "$kind" "$rel" >> "$changes_file"

    if ! tp_is_allowed_write_operation "$kind" "$rel"; then
      printf '%s\t%s\n' "$kind" "$rel" >> "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
      printf '%s\t%s\n' "$kind" "$rel" >> "$diff_file"
      violations=$((violations + 1))
      bad=1
    fi
  done < "$joined_file"

  while IFS=$'\t' read -r old_rel new_rel _hash; do
    [[ -n "$old_rel" && -n "$new_rel" ]] || continue
    local render_rel="${old_rel} => ${new_rel}"
    printf 'R\t%s\n' "$render_rel" >> "$changes_file"
    if ! tp_is_allowed_write_operation "R" "$new_rel" "$old_rel"; then
      printf 'R\t%s\n' "$render_rel" >> "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
      printf 'R\t%s\n' "$render_rel" >> "$diff_file"
      violations=$((violations + 1))
      bad=1
    fi
  done < "$rename_pairs_file"

  TP_WRITE_SCOPE_VIOLATION_COUNT="$violations"
  return "$bad"
}

tp_finalize_generated_repo_immutability_guard() {
  TP_GENERATED_REPO_AFTER_HASH="$(tp_tree_fingerprint "$TP_GENERATED_REPO")"
  printf '%s\n' "$TP_GENERATED_REPO_AFTER_HASH" > "$TP_GENERATED_AFTER_HASH_PATH"
  [[ "$TP_GENERATED_REPO_BEFORE_HASH" == "$TP_GENERATED_REPO_AFTER_HASH" ]] || TP_GENERATED_REPO_UNCHANGED=false
}
