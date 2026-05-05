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
  TP_ALLOWED_MODEL_TEST_WRITES_GLOBS=(
    "./src/test/*"
    "./src/*Test*/*"
    "./test/*"
    "./tests/*"
  )
  TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES=()
  TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES=(
    "./src/main/"
    "./scripts/"
    "./docs/"
    "./.github/"
  )
  mkdir -p "$TP_GUARDS_DIR"
  : > "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
}

case_rename_test_path_is_allowed() {
  local tmp repo before after
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  tp_write_repo_manifest "$repo" "$before"
  mv "${repo}/src/test/java/SampleTest.java" "${repo}/src/test/java/RenamedSampleTest.java"

  tp_check_write_scope "$repo" "$before" "$after"
  tpt_assert_eq "0" "$TP_WRITE_SCOPE_VIOLATION_COUNT" "rename inside test paths should be allowed"
  tpt_assert_file_contains "${TP_GUARDS_DIR}/ported-protected-change-set.tsv" $'R\t./src/test/java/SampleTest.java => ./src/test/java/RenamedSampleTest.java' "rename should be recorded as operation R"
}

case_rename_into_denied_path_is_rejected() {
  local tmp repo before after rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  tp_write_repo_manifest "$repo" "$before"
  mv "${repo}/src/test/java/SampleTest.java" "${repo}/src/main/java/SampleTest.java"

  if tp_check_write_scope "$repo" "$before" "$after"; then
    echo "expected rename into denied path to fail" >&2
    return 1
  else
    rc=$?
  fi

  tpt_assert_eq "1" "$rc" "rename into denied path must fail"
  tpt_assert_file_contains "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" "./src/test/java/SampleTest.java => ./src/main/java/SampleTest.java" "failure list should include denied rename"
}

case_manifest_rejects_escape_path() {
  local tmp repo before rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"

  mkdir -p "${repo}/src/test/java/escape"
  ln -s ../../../../.. "${repo}/src/test/java/escape/root-link"
  if tp_write_repo_manifest "$repo" "$before"; then
    # The symlink itself is ignored by find -type f; add an escaped rel check directly.
    if tp_resolve_repo_canonical_path "$repo" "./src/test/java/escape/../../../../../../../../etc/passwd" >/dev/null 2>&1; then
      echo "expected canonical escape path resolution to fail" >&2
      return 1
    fi
  else
    rc=$?
    tpt_assert_eq "2" "$rc" "manifest escape detection failures should return 2"
  fi
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

case_allows_discovered_custom_test_root_modifications() {
  local tmp repo before after
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  before="${tmp}/before.tsv"
  after="${tmp}/after.tsv"

  create_base_repo "$repo"
  setup_guard_env "$tmp"
  TP_DISCOVERED_TEST_ROOTS_CSV="./starter/src/contract/java"

  mkdir -p "${repo}/starter/src/contract/java"
  echo "class ContractPortTest {}" > "${repo}/starter/src/contract/java/ContractPortTest.java"

  tp_write_repo_manifest "$repo" "$before"
  echo "// adapted" >> "${repo}/starter/src/contract/java/ContractPortTest.java"

  tp_check_write_scope "$repo" "$before" "$after"
  tpt_assert_eq "0" "$TP_WRITE_SCOPE_VIOLATION_COUNT" "discovered custom test roots must be writable"
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
tpt_run_case "allows discovered custom test-root edits" case_allows_discovered_custom_test_root_modifications
tpt_run_case "rejects non-test edits" case_rejects_non_test_modifications
tpt_run_case "ignores completion/proof/logs churn" case_ignores_completion_proof_logs
tpt_run_case "ignores .mvn_repo churn" case_ignores_mvn_repo_changes
tpt_run_case "ignores .m2 churn" case_ignores_m2_repo_changes
tpt_run_case "custom ignore does not mask other writes" case_custom_ignore_does_not_mask_other_paths
tpt_run_case "rename in test paths is allowed" case_rename_test_path_is_allowed
tpt_run_case "rename into denied path is rejected" case_rename_into_denied_path_is_rejected
tpt_run_case "canonical escape path is rejected" case_manifest_rejects_escape_path

tpt_finish_suite
