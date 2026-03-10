#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/service_testlib.sh"

prepare_fake_adapter_env() {
  local root="$1"
  local scenario="$2"

  export TPT_ADAPTER_SCENARIO="$scenario"
  export TPT_CODEX_CALL_COUNT_FILE="${root}/codex-call-count.txt"
  export TPT_CLAUDE_CALL_COUNT_FILE="${root}/claude-call-count.txt"
  printf '0\n' > "$TPT_CODEX_CALL_COUNT_FILE"
  printf '0\n' > "$TPT_CLAUDE_CALL_COUNT_FILE"
}

run_service_case() {
  local root="$1"
  local log_path="$2"
  shift 2

  set +e
  (
    export "$@"
    "${TOOL_ROOT}/kvasir-service.sh"
  ) >"$log_path" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc"
}

assert_report_fields() {
  local json_path="$1"
  local expected_status="$2"
  local expected_reason="$3"
  local expected_detail="$4"
  local expected_verdict="$5"

  python3 - <<'PY' "$json_path" "$expected_status" "$expected_reason" "$expected_detail" "$expected_verdict"
import json
import sys

json_path, expected_status, expected_reason, expected_detail, expected_verdict = sys.argv[1:]
with open(json_path, "r", encoding="utf-8") as f:
    obj = json.load(f)

if obj.get("status") != expected_status:
    raise SystemExit(f"expected status {expected_status!r}, got {obj.get('status')!r}")
if obj.get("reason") != expected_reason:
    raise SystemExit(f"expected reason {expected_reason!r}, got {obj.get('reason')!r}")
if obj.get("status_detail") != expected_detail:
    raise SystemExit(f"expected status_detail {expected_detail!r}, got {obj.get('status_detail')!r}")
if obj.get("behavioral_verdict") != expected_verdict:
    raise SystemExit(f"expected behavioral_verdict {expected_verdict!r}, got {obj.get('behavioral_verdict')!r}")
PY
}

case_env_only_startup_passes() {
  local tmp original_repo generated_repo run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex")"

  tpt_assert_eq "0" "$rc" "env-only service execution should exit 0"
  tpt_assert_file_exists "$json_path" "service must emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

if obj.get("status") != "passed":
    raise SystemExit(f"expected passed status, got {obj.get('status')!r}")
if obj.get("inputs", {}).get("adapter") != "codex":
    raise SystemExit(f"expected codex adapter, got {obj.get('inputs', {}).get('adapter')!r}")
PY
}

case_manifest_driven_startup_passes() {
  local tmp original_repo generated_repo run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${tmp}/kvasir-manifest.json"

  cat > "$manifest_path" <<'JSON'
{
  "version": 1,
  "run_id": "manifest-run-1",
  "adapter": "codex",
  "max_iter": 0,
  "write_scope_ignore_prefixes": [
    "custom/cache"
  ]
}
JSON

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_MANIFEST="$manifest_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir")"

  tpt_assert_eq "0" "$rc" "manifest-driven service execution should exit 0"
  tpt_assert_file_exists "$json_path" "manifest-driven service must emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

if obj.get("run_id") != "manifest-run-1":
    raise SystemExit(f"expected manifest run_id, got {obj.get('run_id')!r}")
ignored = obj.get("write_scope", {}).get("ignored_prefixes", [])
if "./custom/cache/" not in ignored:
    raise SystemExit(f"expected custom ignore prefix, got {ignored!r}")
PY
}

case_env_overrides_manifest_values() {
  local tmp original_repo generated_repo run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${tmp}/kvasir-manifest.json"

  cat > "$manifest_path" <<'JSON'
{
  "version": 1,
  "adapter": "claude",
  "max_iter": 0
}
JSON

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_MANIFEST="$manifest_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex")"

  tpt_assert_eq "0" "$rc" "env override service execution should exit 0"
  tpt_assert_file_exists "$json_path" "override service must emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

if obj.get("inputs", {}).get("adapter") != "codex":
    raise SystemExit(f"expected env adapter override to win, got {obj.get('inputs', {}).get('adapter')!r}")
PY
}

case_invalid_manifest_still_emits_report() {
  local tmp run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${tmp}/bad-manifest.json"

  printf '{invalid json\n' > "$manifest_path"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_MANIFEST="$manifest_path" \
    KVASIR_RUN_DIR="$run_dir")"

  tpt_assert_eq "1" "$rc" "invalid manifest must exit 1"
  tpt_assert_file_exists "$json_path" "invalid manifest must still emit json report"
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "invalid manifest must still emit summary"
  assert_report_fields "$json_path" "skipped" "invalid-service-manifest" "invalid_manifest" "skipped"
}

case_missing_adapter_still_emits_report() {
  local tmp original_repo generated_repo run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir")"

  tpt_assert_eq "1" "$rc" "missing adapter must exit 1"
  tpt_assert_file_exists "$json_path" "missing adapter must still emit json report"
  assert_report_fields "$json_path" "skipped" "invalid-service-config" "invalid_config" "skipped"
}

case_missing_original_repo_still_emits_report() {
  local tmp generated_repo run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  generated_repo="${tmp}/generated"
  cp -R "${SCRIPT_DIR}/fixtures/generated_repo" "$generated_repo"
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="${tmp}/missing-original" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex")"

  tpt_assert_eq "1" "$rc" "missing original repo must exit 1"
  tpt_assert_file_exists "$json_path" "missing original repo must still emit json report"
  assert_report_fields "$json_path" "skipped" "missing-original-repo" "missing_input" "skipped"
}

case_non_writable_run_dir_still_emits_report() {
  local tmp original_repo generated_repo run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  mkdir -p "${run_dir}/outputs"
  chmod 700 "${run_dir}/outputs"
  chmod 500 "$run_dir"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex")"

  chmod 700 "$run_dir"

  tpt_assert_eq "1" "$rc" "non-writable run dir must exit 1"
  tpt_assert_file_exists "$json_path" "non-writable run dir must still emit json report"
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "non-writable run dir must still emit summary"
  assert_report_fields "$json_path" "skipped" "run-dir-not-writable" "run_dir_not_writable" "skipped"
}

case_non_writable_logs_dir_still_emits_report() {
  local tmp original_repo generated_repo run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  mkdir -p "${run_dir}/outputs" "${run_dir}/logs"
  chmod 700 "${run_dir}/outputs"
  chmod 500 "${run_dir}/logs"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex")"

  chmod 700 "${run_dir}/logs"

  tpt_assert_eq "1" "$rc" "non-writable logs dir must exit 1"
  tpt_assert_file_exists "$json_path" "non-writable logs dir must still emit json report"
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "non-writable logs dir must still emit summary"
  assert_report_fields "$json_path" "skipped" "run-dir-not-writable" "run_dir_not_writable" "skipped"
}

tpt_run_case "env-only service startup passes" case_env_only_startup_passes
tpt_run_case "manifest-driven service startup passes" case_manifest_driven_startup_passes
tpt_run_case "env overrides manifest values" case_env_overrides_manifest_values
tpt_run_case "invalid manifest still emits report" case_invalid_manifest_still_emits_report
tpt_run_case "missing adapter still emits report" case_missing_adapter_still_emits_report
tpt_run_case "missing original repo still emits report" case_missing_original_repo_still_emits_report
tpt_run_case "non-writable run dir still emits report" case_non_writable_run_dir_still_emits_report
tpt_run_case "non-writable logs dir still emits report" case_non_writable_logs_dir_still_emits_report

tpt_finish_suite
