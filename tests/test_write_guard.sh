#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_common.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_write_guard.sh"

create_base_repo() {
  local repo="$1"
  mkdir -p "${repo}/src/test/java" "${repo}/src/main/java"
  echo "class SampleTest {}" > "${repo}/src/test/java/SampleTest.java"
  echo "class Prod {}" > "${repo}/src/main/java/Prod.java"
}

setup_guard_env() {
  local tmp="$1"
  TP_WRITE_SCOPE_POLICY="tests-only"
  TP_GUARDS_DIR="${tmp}/guards"
  TP_WRITE_SCOPE_FAILURE_PATHS_FILE="${tmp}/write-scope-failures.tsv"
  TP_WRITE_SCOPE_IGNORED_PREFIXES=(
    "./completion/proof/logs/"
    "./.mvn_repo/"
    "./.m2/"
  )
  mkdir -p "$TP_GUARDS_DIR"
  : > "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
}

case_allows_test_path_modifications() {
  local tmp repo before after
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  tp_write_repo_manifest "$repo" "$before"
  echo "// adapted" >> "${repo}/src/test/java/SampleTest.java"

  tp_check_write_scope "$repo" "$before" "$after"
  tpt_assert_eq "0" "$TP_WRITE_SCOPE_VIOLATION_COUNT" "test-path edits must stay in scope"
  [[ ! -s "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" ]]
}

case_rejects_non_test_modifications() {
  local tmp repo before after rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  tp_write_repo_manifest "$repo" "$before"
  echo "// bad edit" >> "${repo}/src/main/java/Prod.java"

  if tp_check_write_scope "$repo" "$before" "$after"; then
    echo "expected non-test edit to fail" >&2
    return 1
  else
    rc=$?
  fi

  tpt_assert_eq "1" "$rc" "write guard must fail for disallowed edits"
  tpt_assert_file_contains "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" "./src/main/java/Prod.java" "failure list must include offending path"
}

case_ignores_completion_proof_logs() {
  local tmp repo before after
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  mkdir -p "${repo}/completion/proof/logs"
  echo "initial" > "${repo}/completion/proof/logs/hard-repo-compliance.log"

  tp_write_repo_manifest "$repo" "$before"
  echo "updated" >> "${repo}/completion/proof/logs/hard-repo-compliance.log"

  tp_check_write_scope "$repo" "$before" "$after"
  tpt_assert_eq "0" "$TP_WRITE_SCOPE_VIOLATION_COUNT" "ignored completion logs should not be counted"
  [[ ! -s "${TP_GUARDS_DIR}/ported-protected-change-set.tsv" ]]
}

case_ignores_mvn_repo_changes() {
  local tmp repo before after
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  tp_write_repo_manifest "$repo" "$before"

  mkdir -p "${repo}/.mvn_repo/cache"
  echo "dependency" > "${repo}/.mvn_repo/cache/item.txt"

  tp_check_write_scope "$repo" "$before" "$after"
  tpt_assert_eq "0" "$TP_WRITE_SCOPE_VIOLATION_COUNT" "ignored maven repo writes should not be counted"
  [[ ! -s "${TP_GUARDS_DIR}/ported-protected-change-set.tsv" ]]
}

case_ignores_m2_repo_changes() {
  local tmp repo before after
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  tp_write_repo_manifest "$repo" "$before"

  mkdir -p "${repo}/.m2/repository"
  echo "dependency" > "${repo}/.m2/repository/item.txt"

  tp_check_write_scope "$repo" "$before" "$after"
  tpt_assert_eq "0" "$TP_WRITE_SCOPE_VIOLATION_COUNT" "ignored .m2 writes should not be counted"
  [[ ! -s "${TP_GUARDS_DIR}/ported-protected-change-set.tsv" ]]
}

case_custom_ignore_does_not_mask_other_paths() {
  local tmp repo before after rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"
  TP_WRITE_SCOPE_IGNORED_PREFIXES+=("./custom/cache/")

  tp_write_repo_manifest "$repo" "$before"

  mkdir -p "${repo}/custom/cache" "${repo}/custom/other"
  echo "cached" > "${repo}/custom/cache/state.txt"
  echo "not allowed" > "${repo}/custom/other/state.txt"

  if tp_check_write_scope "$repo" "$before" "$after"; then
    echo "expected custom/other write to be rejected" >&2
    return 1
  else
    rc=$?
  fi

  tpt_assert_eq "1" "$rc" "non-ignored path must still fail"
  tpt_assert_file_contains "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" "./custom/other/state.txt" "offending path should be reported"
  tpt_assert_not_file_contains "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" "./custom/cache/state.txt" "ignored path should not be reported"
}

tpt_run_case "allows test-path edits" case_allows_test_path_modifications
tpt_run_case "rejects non-test edits" case_rejects_non_test_modifications
tpt_run_case "ignores completion/proof/logs churn" case_ignores_completion_proof_logs
tpt_run_case "ignores .mvn_repo churn" case_ignores_mvn_repo_changes
tpt_run_case "ignores .m2 churn" case_ignores_m2_repo_changes
tpt_run_case "custom ignore does not mask other writes" case_custom_ignore_does_not_mask_other_paths

tpt_finish_suite
