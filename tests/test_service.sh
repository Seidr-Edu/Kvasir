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
  local _root="$1"
  local log_path="$2"
  shift 2

  set +e
  (
    env "$@" "${TOOL_ROOT}/kvasir-service.sh"
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

if obj.get("schema_version") != "kvasir.test_port.v3":
    raise SystemExit(f"expected v3 schema, got {obj.get('schema_version')!r}")
result = obj.get("result", {})
if result.get("status") != expected_status:
    raise SystemExit(f"expected status {expected_status!r}, got {result.get('status')!r}")
if result.get("reason") != expected_reason:
    raise SystemExit(f"expected reason {expected_reason!r}, got {result.get('reason')!r}")
if result.get("verdict") != expected_verdict:
    raise SystemExit(f"expected verdict {expected_verdict!r}, got {result.get('verdict')!r}")
if expected_detail and result.get("verdict_reason") not in {expected_detail, expected_detail.replace("_", "-"), expected_reason}:
    raise SystemExit(f"expected related verdict reason for {expected_detail!r}, got {result.get('verdict_reason')!r}")
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

if obj.get("schema_version") != "kvasir.test_port.v3":
    raise SystemExit(f"expected v3 schema, got {obj.get('schema_version')!r}")
if obj.get("result", {}).get("status") != "passed":
    raise SystemExit(f"expected passed status, got {obj.get('result')!r}")
if obj.get("inputs", {}).get("adapter") != "codex":
    raise SystemExit(f"expected codex adapter, got {obj.get('inputs', {}).get('adapter')!r}")
if not obj.get("artifacts", {}).get("ported_repo"):
    raise SystemExit(f"expected promoted ported repo artifact, got {obj.get('artifacts')!r}")
PY
  [[ -d "${run_dir}/artifacts/ported-tests-repo" ]] || {
    echo "ASSERT failed: service should promote the final ported repo" >&2
    return 1
  }
  [[ ! -e "${run_dir}/workspace/original-baseline-repo" ]] || {
    echo "ASSERT failed: service should clean original baseline copy" >&2
    return 1
  }
  [[ ! -e "${run_dir}/workspace/generated-baseline-repo" ]] || {
    echo "ASSERT failed: service should clean generated baseline copy" >&2
    return 1
  }
  [[ ! -e "${run_dir}/workspace/ported-tests-repo" ]] || {
    echo "ASSERT failed: service should clean workspace ported repo copy" >&2
    return 1
  }
  [[ ! -e "${run_dir}/workspace/original-tests-snapshot" ]] || {
    echo "ASSERT failed: service should clean original test snapshot" >&2
    return 1
  }
}

case_codex_exec_uses_container_safe_flags() {
  local tmp original_repo generated_repo run_dir log_path json_path rc args_log
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  args_log="${tmp}/codex-args.log"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex" \
    TPT_CODEX_ARGS_LOG="$args_log")"

  tpt_assert_eq "0" "$rc" "service execution should exit 0"
  tpt_assert_file_exists "$json_path" "service must emit json report"
  tpt_assert_file_exists "$args_log" "fake codex must record exec arguments"

  if ! grep -q -- '--dangerously-bypass-approvals-and-sandbox' "$args_log"; then
    echo "ASSERT failed: codex exec must bypass the inner sandbox in service mode" >&2
    return 1
  fi
  if grep -q -- '--full-auto' "$args_log"; then
    echo "ASSERT failed: codex exec must not rely on --full-auto in service mode" >&2
    return 1
  fi
  if ! grep -q -- '--cd' "$args_log"; then
    echo "ASSERT failed: codex exec must set an explicit working root" >&2
    return 1
  fi
  if ! grep -q -- '/ported-tests-repo' "$args_log"; then
    echo "ASSERT failed: codex exec must target the staged ported-tests workspace" >&2
    return 1
  fi
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
  manifest_path="${run_dir}/config/manifest.yaml"
  mkdir -p "${run_dir}/config"

  cat > "$manifest_path" <<'YAML'
version: 1
run_id: manifest-run-1
adapter: codex
max_iter: 0
runner_timeout_sec: 120
write_scope_ignore_prefixes:
  - custom/cache
YAML

  rc="$(run_service_case "$tmp" "$log_path" \
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
if obj.get("inputs", {}).get("max_iter") != 0:
    raise SystemExit(f"expected max_iter 0, got {obj.get('inputs', {}).get('max_iter')!r}")
ignored = obj.get("diagnostics", {}).get("write_scope", {}).get("ignored_prefixes", [])
if "./custom/cache/" not in ignored:
    raise SystemExit(f"expected custom ignore prefix, got {ignored!r}")
PY
}

case_post_completion_hang_recovers_and_preserves_result() {
  local tmp original_repo generated_repo run_dir log_path json_path pid_file rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "complete-then-hang"
  export TPT_CODEX_PID_FILE="${tmp}/codex.pid"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  pid_file="${tmp}/codex.pid"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex" \
    KVASIR_TEST_CODEX_COMPLETION_GRACE_SEC="1")"

  tpt_assert_eq "0" "$rc" "post-completion hang should still exit 0"
  tpt_assert_file_exists "$json_path" "recovered hang must still emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

result = obj.get("result", {})
if result.get("status") != "passed":
    raise SystemExit(f"expected passed status, got {result!r}")
if result.get("reason") not in ("", None):
    raise SystemExit(f"recovered hang should not rewrite reason, got {result!r}")
PY
  tpt_assert_file_contains "${run_dir}/logs/adapter-events.jsonl" "post-completion-hang-recovered" "service should preserve recovery runtime event"
  tpt_assert_pid_file_reaped "$pid_file" "service should reap recovered provider process"
}

case_pre_completion_hang_emits_timeout_report() {
  local tmp original_repo generated_repo run_dir log_path json_path pid_file rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "hang-before-complete"
  export TPT_CODEX_PID_FILE="${tmp}/codex.pid"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  pid_file="${tmp}/codex.pid"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex" \
    KVASIR_TEST_RUNNER_TIMEOUT_SEC="8")"

  tpt_assert_eq "1" "$rc" "pre-completion hang should exit non-zero"
  tpt_assert_file_exists "$json_path" "runner timeout must still emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

result = obj.get("result", {})
if result.get("status") != "failed":
    raise SystemExit(f"expected failed status, got {result!r}")
if result.get("reason") != "runner-timeout":
    raise SystemExit(f"expected runner-timeout reason, got {result!r}")
if result.get("verdict_reason") not in {"runner_timeout", "runner-timeout"}:
    raise SystemExit(f"expected runner timeout verdict reason, got {result!r}")
PY
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "runner timeout must still emit summary"
  tpt_assert_pid_file_reaped "$pid_file" "service should reap timed out provider process"
}

case_runner_nonzero_after_report_exits_nonzero() {
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
    KVASIR_ADAPTER="codex" \
    TPT_BASH_WRAPPER_MODE="kvasir-run-nonzero-after-report")"

  tpt_assert_eq "1" "$rc" "unexpected non-timeout runner exits must fail the service"
  tpt_assert_file_exists "$json_path" "non-timeout runner failure must preserve the canonical report when it exists"
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "non-timeout runner failure must still emit summary"
}

case_missing_report_after_success_emits_internal_report_inconsistency() {
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
    KVASIR_ADAPTER="codex" \
    TPT_BASH_WRAPPER_MODE="kvasir-run-drop-report-after-success")"

  tpt_assert_eq "1" "$rc" "missing canonical report after a successful runner exit must fail the service"
  tpt_assert_file_exists "$json_path" "service must rewrite a canonical report when sync fails"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

result = obj.get("result", {})
if result.get("status") != "failed":
    raise SystemExit(f"expected failed status, got {result!r}")
if result.get("reason") != "internal-report-inconsistency":
    raise SystemExit(f"expected internal-report-inconsistency reason, got {result!r}")
if result.get("verdict") != "inconclusive":
    raise SystemExit(f"expected inconclusive verdict, got {result!r}")
if result.get("verdict_reason") not in {"internal-report-inconsistency", "internal_report_inconsistency"}:
    raise SystemExit(f"expected internal-report-inconsistency verdict reason, got {result!r}")
PY
}

case_env_override_rejected_in_strict_mode() {
  local tmp original_repo generated_repo run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${run_dir}/config/manifest.yaml"
  mkdir -p "${run_dir}/config"

  cat > "$manifest_path" <<'YAML'
version: 1
adapter: codex
YAML

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_WRITE_SCOPE_IGNORE_PREFIXES="custom/cache")"

  tpt_assert_eq "1" "$rc" "strict mode must reject env write-scope overrides"
  tpt_assert_file_exists "$json_path" "strict override rejection must still emit json report"
  assert_report_fields "$json_path" "skipped" "invalid-service-config" "policy_override_rejected" "skipped"
}

case_env_override_allowed_when_explicitly_enabled() {
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
    KVASIR_ADAPTER="codex" \
    KVASIR_WRITE_SCOPE_IGNORE_PREFIXES="custom/cache" \
    KVASIR_ALLOW_WRITE_SCOPE_OVERRIDES="true")"

  tpt_assert_eq "0" "$rc" "explicitly allowed env overrides should pass"
  tpt_assert_file_exists "$json_path" "allowed env override must emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

ignored = obj.get("diagnostics", {}).get("write_scope", {}).get("ignored_prefixes", [])
if "./custom/cache/" not in ignored:
    raise SystemExit(f"expected custom env override prefix, got {ignored!r}")
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
  manifest_path="${tmp}/kvasir-manifest.yaml"

  cat > "$manifest_path" <<'YAML'
version: 1
adapter: claude
max_iter: 0
YAML

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

case_build_hints_select_subdir_and_surface_hint_metadata() {
  local tmp original_repo generated_repo run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  original_repo="${tmp}/original-monorepo"
  generated_repo="${tmp}/generated-monorepo"
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  mkdir -p "${original_repo}/app/src/test/java" "${generated_repo}/app/src/main/java"
  cp "${SCRIPT_DIR}/fixtures/original_repo/pom.xml" "${original_repo}/app/pom.xml"
  cp "${SCRIPT_DIR}/fixtures/generated_repo/pom.xml" "${generated_repo}/app/pom.xml"
  cp "${SCRIPT_DIR}/fixtures/original_repo/src/test/java/OriginalFixtureTest.java" "${original_repo}/app/src/test/java/OriginalFixtureTest.java"
  cp "${SCRIPT_DIR}/fixtures/generated_repo/src/main/java/Prod.java" "${generated_repo}/app/src/main/java/Prod.java"
  mkdir -p "${run_dir}/config"
  cat > "${run_dir}/config/build-hints.json" <<'JSON'
{
  "original": {
    "build_tool": "maven",
    "build_subdir": "app",
    "java_version_hint": "17",
    "source": "lidskjalv-original"
  },
  "generated": {
    "build_tool": "maven",
    "build_subdir": "app",
    "java_version_hint": "17",
    "source": "lidskjalv-generated"
  }
}
JSON

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex")"

  tpt_assert_eq "0" "$rc" "build hints should let service run against hinted module subdirs"
  tpt_assert_file_exists "$json_path" "hint-driven service run must emit json report"
  python3 - <<'PY' "$json_path"
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)

if obj.get("inputs", {}).get("original_subdir") != "app":
    raise SystemExit(f"expected original_subdir from hints, got {obj.get('inputs', {}).get('original_subdir')!r}")
if obj.get("inputs", {}).get("generated_subdir") != "app":
    raise SystemExit(f"expected generated_subdir from hints, got {obj.get('inputs', {}).get('generated_subdir')!r}")
baseline_original = obj.get("baselines", {}).get("original", {}).get("build_environment", {})
baseline_generated = obj.get("baselines", {}).get("generated", {}).get("build_environment", {})
if baseline_original.get("hint", {}).get("source") != "lidskjalv-original":
    raise SystemExit(f"expected original hint source, got {baseline_original!r}")
if baseline_generated.get("hint", {}).get("source") != "lidskjalv-generated":
    raise SystemExit(f"expected generated hint source, got {baseline_generated!r}")
PY
}

case_invalid_manifest_still_emits_report() {
  local tmp run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${tmp}/bad-manifest.yaml"

  printf 'version: 1\nadapter: [bad\n' > "$manifest_path"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_MANIFEST="$manifest_path" \
    KVASIR_RUN_DIR="$run_dir")"

  tpt_assert_eq "1" "$rc" "invalid manifest must exit 1"
  tpt_assert_file_exists "$json_path" "invalid manifest must still emit json report"
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "invalid manifest must still emit summary"
  assert_report_fields "$json_path" "skipped" "invalid-service-manifest" "invalid_manifest" "skipped"
}

case_unknown_manifest_key_still_emits_report() {
  local tmp run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${tmp}/bad-manifest.yaml"

  cat > "$manifest_path" <<'YAML'
version: 1
adapter: codex
unexpected: true
YAML

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_MANIFEST="$manifest_path" \
    KVASIR_RUN_DIR="$run_dir")"

  tpt_assert_eq "1" "$rc" "unknown manifest key must exit 1"
  tpt_assert_file_exists "$json_path" "unknown manifest key must still emit json report"
  assert_report_fields "$json_path" "skipped" "invalid-service-manifest" "invalid_manifest" "skipped"
}

case_invalid_run_id_still_emits_report() {
  local tmp original_repo generated_repo run_dir log_path json_path manifest_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  manifest_path="${run_dir}/config/manifest.yaml"
  mkdir -p "${run_dir}/config"

  cat > "$manifest_path" <<'YAML'
version: 1
run_id: ../bad/run-id
adapter: codex
YAML

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir")"

  tpt_assert_eq "1" "$rc" "invalid run_id must exit 1"
  tpt_assert_file_exists "$json_path" "invalid run_id must still emit json report"
  tpt_assert_file_exists "${run_dir}/outputs/summary.md" "invalid run_id must still emit summary"
  assert_report_fields "$json_path" "skipped" "invalid-run-id" "" "skipped"
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

case_codex_provider_bootstrap_uses_runtime_home() {
  local tmp original_repo generated_repo provider_bin provider_seed run_dir runtime_home log_path json_path capture_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  IFS=$'\t' read -r provider_bin provider_seed < <(prepare_fake_provider_mounts "$tmp")
  run_dir="${tmp}/run"
  runtime_home="$(python3 - <<'PY' "$run_dir"
import os
import sys

print(os.path.abspath(sys.argv[1]) + "/provider-state/codex-home")
PY
)"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"
  capture_path="${tmp}/captured-codex-home.txt"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex" \
    KVASIR_SERVICE_PROVIDER_BIN="$provider_bin" \
    KVASIR_SERVICE_PROVIDER_SEED="$provider_seed" \
    TPT_EXPECT_CODEX_HOME_PREFIX="$runtime_home" \
    TPT_CODEX_HOME_CAPTURE_FILE="$capture_path")"

  tpt_assert_eq "0" "$rc" "provider bootstrap service execution should exit 0"
  tpt_assert_file_exists "$json_path" "provider bootstrap must emit json report"
  tpt_assert_file_exists "${runtime_home}/sessions/auth-state.json" "provider seed should be copied into runtime CODEX_HOME"
  tpt_assert_eq "$runtime_home" "$(cat "$capture_path")" "service should use runtime CODEX_HOME"
}

case_provider_bootstrap_failure_still_emits_report() {
  local tmp original_repo generated_repo provider_bin provider_seed run_dir log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  IFS=$'\t' read -r provider_bin provider_seed < <(prepare_fake_provider_mounts "$tmp")
  run_dir="${tmp}/run"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  chmod 000 "$provider_seed"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex" \
    KVASIR_SERVICE_PROVIDER_BIN="$provider_bin" \
    KVASIR_SERVICE_PROVIDER_SEED="$provider_seed")"

  chmod 700 "$provider_seed"

  tpt_assert_eq "1" "$rc" "provider bootstrap failure must exit 1"
  tpt_assert_file_exists "$json_path" "provider bootstrap failure must still emit json report"
  assert_report_fields "$json_path" "skipped" "adapter-prereqs-failed" "provider_bootstrap_failed" "skipped"
}

case_failed_login_status_reports_adapter_prereqs_failed() {
  local tmp original_repo generated_repo provider_bin run_dir runtime_home log_path json_path rc
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  prepare_fake_adapter_env "$tmp" "ignored-writes"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")
  provider_bin="${tmp}/provider-bin"
  mkdir -p "$provider_bin"
  cp -R "${tmp}/bin/." "${provider_bin}/"
  run_dir="${tmp}/run"
  runtime_home="$(python3 - <<'PY' "$run_dir"
import os
import sys

print(os.path.abspath(sys.argv[1]) + "/provider-state/codex-home")
PY
)"
  log_path="${tmp}/service.log"
  json_path="${run_dir}/outputs/test_port.json"

  rc="$(run_service_case "$tmp" "$log_path" \
    KVASIR_ORIGINAL_REPO="$original_repo" \
    KVASIR_GENERATED_REPO="$generated_repo" \
    KVASIR_RUN_DIR="$run_dir" \
    KVASIR_ADAPTER="codex" \
    KVASIR_SERVICE_PROVIDER_BIN="$provider_bin" \
    KVASIR_SERVICE_PROVIDER_SEED="${tmp}/missing-provider-seed" \
    TPT_EXPECT_CODEX_HOME_PREFIX="$runtime_home")"

  tpt_assert_eq "1" "$rc" "failed provider login status must exit 1"
  tpt_assert_file_exists "$json_path" "failed provider login must still emit json report"
  assert_report_fields "$json_path" "skipped" "adapter-prereqs-failed" "adapter_prereqs_failed" "skipped"
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
tpt_run_case "codex exec uses container-safe flags" case_codex_exec_uses_container_safe_flags
tpt_run_case "manifest-driven service startup passes" case_manifest_driven_startup_passes
tpt_run_case "strict mode rejects env write-scope overrides" case_env_override_rejected_in_strict_mode
tpt_run_case "env write-scope overrides work when explicitly allowed" case_env_override_allowed_when_explicitly_enabled
tpt_run_case "env overrides manifest values" case_env_overrides_manifest_values
tpt_run_case "build hints select subdir and surface hint metadata" case_build_hints_select_subdir_and_surface_hint_metadata
tpt_run_case "invalid manifest still emits report" case_invalid_manifest_still_emits_report
tpt_run_case "unknown manifest key still emits report" case_unknown_manifest_key_still_emits_report
tpt_run_case "invalid run_id still emits report" case_invalid_run_id_still_emits_report
tpt_run_case "missing adapter still emits report" case_missing_adapter_still_emits_report
tpt_run_case "codex provider bootstrap uses runtime home" case_codex_provider_bootstrap_uses_runtime_home
tpt_run_case "provider bootstrap failure still emits report" case_provider_bootstrap_failure_still_emits_report
tpt_run_case "failed login status reports adapter prereqs failed" case_failed_login_status_reports_adapter_prereqs_failed
tpt_run_case "post completion hang recovers and preserves result" case_post_completion_hang_recovers_and_preserves_result
tpt_run_case "pre completion hang emits timeout report" case_pre_completion_hang_emits_timeout_report
tpt_run_case "runner nonzero after report exits nonzero" case_runner_nonzero_after_report_exits_nonzero
tpt_run_case "missing report after success emits internal inconsistency" case_missing_report_after_success_emits_internal_report_inconsistency
tpt_run_case "missing original repo still emits report" case_missing_original_repo_still_emits_report
tpt_run_case "non-writable run dir still emits report" case_non_writable_run_dir_still_emits_report
tpt_run_case "non-writable logs dir still emits report" case_non_writable_logs_dir_still_emits_report

tpt_finish_suite
