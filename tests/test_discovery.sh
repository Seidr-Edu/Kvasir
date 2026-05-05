#!/usr/bin/env bash
# Tests for tp_discovery.sh shell helpers and the snapshot/seed pipeline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_discovery.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_copy.sh"

# ── helpers ──────────────────────────────────────────────────────────────────

make_java_test_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  printf 'class Stub {}\n' > "$path"
}

# ── tp_map_discovered_test_root_to_ported_repo_rel ───────────────────────────

case_map_root_no_subdir_passthrough() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  local result
  result="$(tp_map_discovered_test_root_to_ported_repo_rel "./src/test")"
  tpt_assert_eq "./src/test" "$result" "no subdir: root must pass through unchanged"
}

case_map_root_with_subdir_prepends_prefix() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  TP_GENERATED_EFFECTIVE_SUBDIR="myapp"
  local result
  result="$(tp_map_discovered_test_root_to_ported_repo_rel "./src/test")"
  tpt_assert_eq "./myapp/src/test" "$result" "subdir must be prepended to root"
}

case_map_root_already_under_subdir_passthrough() {
  TP_GENERATED_EFFECTIVE_SUBDIR="myapp"
  local result
  result="$(tp_map_discovered_test_root_to_ported_repo_rel "./myapp/src/test")"
  tpt_assert_eq "./myapp/src/test" "$result" "root already under subdir must pass through"
}

case_map_root_dotslash_subdir_stripped() {
  TP_GENERATED_EFFECTIVE_SUBDIR="./myapp"
  local result
  result="$(tp_map_discovered_test_root_to_ported_repo_rel "./src/test")"
  tpt_assert_eq "./myapp/src/test" "$result" "leading ./ in subdir must be normalised"
}

case_map_root_trailing_dot_subdir_preserved() {
  # Shell uses ${var#./} not strip("./"), so trailing dot must survive.
  TP_GENERATED_EFFECTIVE_SUBDIR="mymodule."
  local result
  result="$(tp_map_discovered_test_root_to_ported_repo_rel "./src/test")"
  tpt_assert_eq "./mymodule./src/test" "$result" "trailing dot in subdir must be preserved"
}

case_map_root_integration_test_sourceset() {
  TP_GENERATED_EFFECTIVE_SUBDIR="service"
  local result
  result="$(tp_map_discovered_test_root_to_ported_repo_rel "./src/integrationTest")"
  tpt_assert_eq "./service/src/integrationTest" "$result" "integration test sourceset must be remapped"
}

# ── tp_refresh_ported_discovered_test_roots_state ────────────────────────────

case_refresh_empty_roots_produces_empty_csv() {
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  TP_DISCOVERED_TEST_ROOTS_CSV=""
  tp_refresh_ported_discovered_test_roots_state
  tpt_assert_eq "" "${TP_PORTED_DISCOVERED_TEST_ROOTS_CSV:-}" "empty roots must yield empty CSV"
}

case_refresh_single_root_no_subdir() {
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  TP_DISCOVERED_TEST_ROOTS_CSV="./src/test"
  tp_refresh_ported_discovered_test_roots_state
  tpt_assert_eq "./src/test" "$TP_PORTED_DISCOVERED_TEST_ROOTS_CSV" "single root must be preserved"
}

case_refresh_multiple_roots_no_subdir() {
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  TP_DISCOVERED_TEST_ROOTS_CSV="./src/test:./src/integrationTest"
  tp_refresh_ported_discovered_test_roots_state
  tpt_assert_eq "./src/test:./src/integrationTest" "$TP_PORTED_DISCOVERED_TEST_ROOTS_CSV" "multiple roots must all be preserved"
}

case_refresh_multiple_roots_with_subdir() {
  TP_GENERATED_EFFECTIVE_SUBDIR="myapp"
  TP_DISCOVERED_TEST_ROOTS_CSV="./src/test:./src/integrationTest"
  tp_refresh_ported_discovered_test_roots_state
  tpt_assert_eq "./myapp/src/test:./myapp/src/integrationTest" "$TP_PORTED_DISCOVERED_TEST_ROOTS_CSV" "all roots must be remapped with subdir"
}

# ── tp_snapshot_original_tests ───────────────────────────────────────────────

_prepare_snapshot_env() {
  local root="$1"
  local repo="$2"
  TP_SUMMARY_DIR="${root}/summary"
  TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH="${TP_SUMMARY_DIR}/original-test-discovery.json"
  TP_ORIGINAL_TESTS_SNAPSHOT="${root}/snapshot"
  TP_ORIGINAL_EFFECTIVE_PATH="$repo"
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  TP_DISCOVERED_TEST_ROOTS_CSV=""
  TP_ORIGINAL_DISCOVERED_TEST_FILE_COUNT=0
  mkdir -p "$TP_SUMMARY_DIR"
}

case_snapshot_discovers_and_copies_test_files() {
  local tmp repo
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_snapshot_env "$tmp" "$repo"

  make_java_test_file "${repo}/src/test/java/com/example/FooTest.java"
  make_java_test_file "${repo}/src/main/java/com/example/Foo.java"

  tp_snapshot_original_tests

  tpt_assert_file_exists "${TP_ORIGINAL_TESTS_SNAPSHOT}/src/test/java/com/example/FooTest.java" \
    "test file must be copied into snapshot"
  tpt_assert_eq "false" "$( [[ -f "${TP_ORIGINAL_TESTS_SNAPSHOT}/src/main/java/com/example/Foo.java" ]] && echo true || echo false )" \
    "main source file must not be in snapshot"
}

case_snapshot_sets_discovered_file_count() {
  local tmp repo
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_snapshot_env "$tmp" "$repo"

  make_java_test_file "${repo}/src/test/java/ATest.java"
  make_java_test_file "${repo}/src/test/java/BTest.java"

  tp_snapshot_original_tests

  tpt_assert_eq "2" "$TP_ORIGINAL_DISCOVERED_TEST_FILE_COUNT" \
    "discovered file count must reflect number of test files found"
}

case_snapshot_sets_discovered_roots_csv() {
  local tmp repo
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_snapshot_env "$tmp" "$repo"

  make_java_test_file "${repo}/src/test/java/FooTest.java"

  tp_snapshot_original_tests

  tpt_assert_contains "$TP_DISCOVERED_TEST_ROOTS_CSV" "./src/test" \
    "discovered roots CSV must contain the test root"
}

case_snapshot_fails_when_no_test_files() {
  local tmp repo rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_snapshot_env "$tmp" "$repo"
  mkdir -p "${repo}/src/main/java"
  printf 'class Foo {}\n' > "${repo}/src/main/java/Foo.java"

  rc=0
  tp_snapshot_original_tests || rc=$?
  tpt_assert_failure "$rc" "snapshot must fail when no test files are found"
}

# ── tp_seed_ported_repo_with_original_tests ──────────────────────────────────

_prepare_seed_env() {
  local root="$1"
  local repo="$2"
  TP_SUMMARY_DIR="${root}/summary"
  TP_ORIGINAL_TEST_DISCOVERY_JSON_PATH="${TP_SUMMARY_DIR}/original-test-discovery.json"
  TP_ORIGINAL_TESTS_SNAPSHOT="${root}/snapshot"
  TP_ORIGINAL_EFFECTIVE_PATH="$repo"
  TP_PORTED_REPO="${root}/ported-repo"
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  TP_DISCOVERED_TEST_ROOTS_CSV=""
  mkdir -p "$TP_SUMMARY_DIR" "$TP_PORTED_REPO"
}

case_seed_places_files_in_ported_repo() {
  local tmp repo
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_seed_env "$tmp" "$repo"

  make_java_test_file "${repo}/src/test/java/FooTest.java"

  # First snapshot so the manifest and state exist.
  tp_snapshot_original_tests
  tp_seed_ported_repo_with_original_tests

  tpt_assert_file_exists "${TP_PORTED_REPO}/src/test/java/FooTest.java" \
    "test file must be placed in ported repo"
}

case_seed_with_subdir_remaps_paths() {
  local tmp repo
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_seed_env "$tmp" "$repo"
  TP_GENERATED_EFFECTIVE_SUBDIR="myapp"

  make_java_test_file "${repo}/src/test/java/FooTest.java"

  tp_snapshot_original_tests
  tp_seed_ported_repo_with_original_tests

  tpt_assert_file_exists "${TP_PORTED_REPO}/myapp/src/test/java/FooTest.java" \
    "test file must land under the generated subdir in ported repo"
  tpt_assert_eq "false" "$( [[ -f "${TP_PORTED_REPO}/src/test/java/FooTest.java" ]] && echo true || echo false )" \
    "file must not appear at the non-remapped path"
}

case_seed_clears_old_test_root_before_seeding() {
  local tmp repo stale
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_seed_env "$tmp" "$repo"

  make_java_test_file "${repo}/src/test/java/NewTest.java"

  # Plant a stale file that should be removed when seeding.
  stale="${TP_PORTED_REPO}/src/test/java/StaleTest.java"
  mkdir -p "$(dirname "$stale")"
  printf 'stale\n' > "$stale"

  tp_snapshot_original_tests
  tp_seed_ported_repo_with_original_tests

  tpt_assert_eq "false" "$( [[ -f "$stale" ]] && echo true || echo false )" \
    "stale test file must be removed before seeding"
  tpt_assert_file_exists "${TP_PORTED_REPO}/src/test/java/NewTest.java" \
    "new test file must be present after seeding"
}

case_seed_preserves_non_test_files_in_ported_repo() {
  local tmp repo main_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/original-repo"
  _prepare_seed_env "$tmp" "$repo"

  make_java_test_file "${repo}/src/test/java/FooTest.java"

  # Pre-populate a non-test source file in the ported repo.
  main_file="${TP_PORTED_REPO}/src/main/java/Foo.java"
  mkdir -p "$(dirname "$main_file")"
  printf 'class Foo {}\n' > "$main_file"

  tp_snapshot_original_tests
  tp_seed_ported_repo_with_original_tests

  tpt_assert_file_exists "$main_file" \
    "non-test source files in ported repo must not be touched by seeding"
}

# ── register all cases ────────────────────────────────────────────────────────

tpt_run_case "map root: no subdir passthrough" \
  case_map_root_no_subdir_passthrough

tpt_run_case "map root: subdir prepended" \
  case_map_root_with_subdir_prepends_prefix

tpt_run_case "map root: already under subdir passthrough" \
  case_map_root_already_under_subdir_passthrough

tpt_run_case "map root: dotslash subdir stripped" \
  case_map_root_dotslash_subdir_stripped

tpt_run_case "map root: trailing dot subdir preserved" \
  case_map_root_trailing_dot_subdir_preserved

tpt_run_case "map root: integration test sourceset remapped" \
  case_map_root_integration_test_sourceset

tpt_run_case "refresh: empty roots yields empty CSV" \
  case_refresh_empty_roots_produces_empty_csv

tpt_run_case "refresh: single root no subdir" \
  case_refresh_single_root_no_subdir

tpt_run_case "refresh: multiple roots no subdir" \
  case_refresh_multiple_roots_no_subdir

tpt_run_case "refresh: multiple roots with subdir" \
  case_refresh_multiple_roots_with_subdir

tpt_run_case "snapshot: discovers and copies test files" \
  case_snapshot_discovers_and_copies_test_files

tpt_run_case "snapshot: sets discovered file count" \
  case_snapshot_sets_discovered_file_count

tpt_run_case "snapshot: sets discovered roots CSV" \
  case_snapshot_sets_discovered_roots_csv

tpt_run_case "snapshot: fails when no test files found" \
  case_snapshot_fails_when_no_test_files

tpt_run_case "seed: places files in ported repo" \
  case_seed_places_files_in_ported_repo

tpt_run_case "seed: subdir remaps paths" \
  case_seed_with_subdir_remaps_paths

tpt_run_case "seed: clears old test root before seeding" \
  case_seed_clears_old_test_root_before_seeding

tpt_run_case "seed: preserves non-test files in ported repo" \
  case_seed_preserves_non_test_files_in_ported_repo

tpt_finish_suite
