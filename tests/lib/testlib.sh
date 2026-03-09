#!/usr/bin/env bash

set -u

TPT_CASE_COUNT=0
TPT_FAIL_COUNT=0

_tpt_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

tpt_log() {
  printf -- '[test-port-tests][%s] %s\n' "$(_tpt_now)" "$*"
}

tpt_assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="${3:-values differ}"
  if [[ "$actual" != "$expected" ]]; then
    printf -- 'ASSERT_EQ failed: %s\nexpected: %s\nactual:   %s\n' "$msg" "$expected" "$actual" >&2
    return 1
  fi
}

tpt_assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="${3:-missing expected substring}"
  if [[ "$haystack" != *"$needle"* ]]; then
    printf -- 'ASSERT_CONTAINS failed: %s\nneedle: %s\nhaystack: %s\n' "$msg" "$needle" "$haystack" >&2
    return 1
  fi
}

tpt_assert_file_exists() {
  local path="$1"
  local msg="${2:-expected file to exist}"
  if [[ ! -f "$path" ]]; then
    printf -- 'ASSERT_FILE_EXISTS failed: %s\nfile: %s\n' "$msg" "$path" >&2
    return 1
  fi
}

tpt_assert_file_contains() {
  local path="$1"
  local needle="$2"
  local msg="${3:-file does not contain expected text}"
  if ! grep -Fq -- "$needle" "$path"; then
    printf -- 'ASSERT_FILE_CONTAINS failed: %s\nfile: %s\nneedle: %s\n' "$msg" "$path" "$needle" >&2
    printf -- '---- file contents ----\n' >&2
    cat "$path" >&2 || true
    printf -- '-----------------------\n' >&2
    return 1
  fi
}

tpt_assert_not_file_contains() {
  local path="$1"
  local needle="$2"
  local msg="${3:-file unexpectedly contains text}"
  if grep -Fq -- "$needle" "$path"; then
    printf -- 'ASSERT_NOT_FILE_CONTAINS failed: %s\nfile: %s\nneedle: %s\n' "$msg" "$path" "$needle" >&2
    printf -- '---- file contents ----\n' >&2
    cat "$path" >&2 || true
    printf -- '-----------------------\n' >&2
    return 1
  fi
}

tpt_assert_success() {
  local rc="$1"
  local msg="${2:-expected success exit code}"
  if [[ "$rc" -ne 0 ]]; then
    printf -- 'ASSERT_SUCCESS failed: %s\nexit_code: %s\n' "$msg" "$rc" >&2
    return 1
  fi
}

tpt_assert_failure() {
  local rc="$1"
  local msg="${2:-expected failure exit code}"
  if [[ "$rc" -eq 0 ]]; then
    printf -- 'ASSERT_FAILURE failed: %s\nexit_code: %s\n' "$msg" "$rc" >&2
    return 1
  fi
}

tpt_mktemp_dir() {
  mktemp -d "${TMPDIR:-/tmp}/test-port-tests.XXXXXX"
}

tpt_run_case() {
  local name="$1"
  shift
  TPT_CASE_COUNT=$((TPT_CASE_COUNT + 1))

  if ( set -euo pipefail; "$@" ); then
    printf -- 'PASS %s\n' "$name"
    return 0
  fi

  local rc=$?
  TPT_FAIL_COUNT=$((TPT_FAIL_COUNT + 1))
  printf -- 'FAIL %s (exit %s)\n' "$name" "$rc" >&2
  return 0
}

tpt_finish_suite() {
  if [[ "$TPT_FAIL_COUNT" -gt 0 ]]; then
    printf -- 'FAILED %s/%s test cases\n' "$TPT_FAIL_COUNT" "$TPT_CASE_COUNT" >&2
    return 1
  fi
  printf -- 'PASSED %s test cases\n' "$TPT_CASE_COUNT"
  return 0
}
