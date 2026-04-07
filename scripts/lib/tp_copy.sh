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
  rm -rf "$TP_ORIGINAL_TESTS_SNAPSHOT"
  mkdir -p "$TP_ORIGINAL_TESTS_SNAPSHOT"

  TP_TEST_SCOPE_INCLUDED_TEST_FILE_COUNT=0
  TP_TEST_SCOPE_EXCLUDED_TEST_FILE_COUNT=0
  : > "${TP_TEST_SCOPE_EXCLUDED_TESTS_FILE:-/dev/null}"

  local scope_snapshot_assignments
  if ! scope_snapshot_assignments="$(python3 - <<'PY' \
    "$TP_ORIGINAL_EFFECTIVE_PATH" "$TP_ORIGINAL_TESTS_SNAPSHOT" "${TP_TEST_SCOPE_RUNNER:-unknown}" "${TP_TEST_SCOPE_SELECTED_MAVEN_MODE:-}" "${TP_TEST_SCOPE_SELECTED_TASKS_CSV:-}" "${TP_TEST_SCOPE_EXCLUDED_TESTS_FILE:-}"
import os
import re
import shlex
import shutil
import sys

source, target, runner, maven_mode, gradle_tasks_csv, excluded_tests_file = sys.argv[1:]
selected_tasks = {task for task in gradle_tasks_csv.split(":") if task}
included = 0
excluded = 0


def relpath(path):
    return os.path.relpath(path, source).replace(os.sep, "/")


def is_test_rel(rel):
    if rel.startswith(("src/test/", "test/", "tests/")):
        return True
    if rel.startswith("src/"):
        parts = rel.split("/", 2)
        if len(parts) >= 2:
            source_set = parts[1]
            return bool(
                re.search(r"(test|spec|integration|functional|e2e|acceptance|verification)", source_set, re.I)
                or source_set.lower() == "it"
                or re.search(r"(^[iI][tT][A-Z0-9_].*|IT$)", source_set)
            )
    return False


def is_integration_like(rel):
    parts = rel.lower().split("/")
    basename = parts[-1]
    if basename.endswith("it.java") or "integrationtest" in basename:
        return True
    return any(part in {"it", "integration", "integrationtest", "functional", "functionaltest", "e2e", "e2etest", "acceptance", "acceptancetest"} for part in parts)


def include_for_gradle(rel):
    if "test" in selected_tasks and rel.startswith(("src/test/", "test/", "tests/")):
        return True
    if rel.startswith("src/"):
        parts = rel.split("/", 2)
        if len(parts) >= 2 and parts[1] in selected_tasks:
            return True
    return False


def include_file(rel):
    if not is_test_rel(rel):
        return False, "not-test-file"
    if runner == "maven":
        if maven_mode == "narrow" and is_integration_like(rel):
            return False, "environment-scope-excluded"
        return True, ""
    if runner in {"gradle", "gradle-wrapper"}:
        if include_for_gradle(rel):
            return True, ""
        return False, "gradle-task-not-selected"
    return True, ""


PRUNED_DIR_NAMES = {
    ".cache",
    ".git",
    ".gradle",
    ".m2",
    ".nox",
    ".pnpm-store",
    ".scannerwork",
    ".tox",
    ".venv",
    ".yarn",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "out",
    "target",
    "vendor",
    "venv",
}

excluded_rows = []
for base, dirs, files in os.walk(source):
    dirs[:] = [d for d in dirs if d not in PRUNED_DIR_NAMES]
    for name in files:
        src = os.path.join(base, name)
        rel = relpath(src)
        keep, reason = include_file(rel)
        if keep:
            dst = os.path.join(target, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            included += 1
        elif is_test_rel(rel):
            excluded += 1
            excluded_rows.append((f"./{rel}", reason))

if excluded_tests_file:
    os.makedirs(os.path.dirname(excluded_tests_file), exist_ok=True)
    with open(excluded_tests_file, "w", encoding="utf-8") as f:
        for rel, reason in excluded_rows:
            f.write(f"{rel}\t{reason}\n")

print(f"TP_TEST_SCOPE_INCLUDED_TEST_FILE_COUNT={shlex.quote(str(included))}")
print(f"TP_TEST_SCOPE_EXCLUDED_TEST_FILE_COUNT={shlex.quote(str(excluded))}")
PY
  )"; then
    return 1
  fi
  eval "$scope_snapshot_assignments"
  tp_test_scope_write_json
  if ! find "$TP_ORIGINAL_TESTS_SNAPSHOT" -type f -print -quit | grep -q .; then
    return 1
  fi
  return 0
}

tp_seed_ported_repo_with_original_tests() {
  local target_root="${TP_PORTED_EFFECTIVE_REPO:-$TP_PORTED_REPO}"
  mkdir -p "$target_root"

  find "$target_root" -type d \
    \( -path '*/src/test' -o -path '*/test' -o -path '*/tests' -o -path '*/src/*Test*' -o -path '*/src/*IT*' -o -path '*/src/*Integration*' -o -path '*/src/*Functional*' -o -path '*/src/*E2E*' -o -path '*/src/it' -o -path '*/src/integration' -o -path '*/src/functional' -o -path '*/src/e2e' \) \
    -prune -exec rm -rf {} + 2>/dev/null || true

  rsync -a "$TP_ORIGINAL_TESTS_SNAPSHOT/" "$target_root/" >/dev/null 2>&1 || return 1
}
