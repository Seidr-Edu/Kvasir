#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_common.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_build_env.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_report.sh"

case_report_emits_ignored_prefixes() {
  local tmp
  tmp="$(tpt_mktemp_dir)"

  TP_JSON_PATH="${tmp}/outputs/test_port.json"
  TP_SUMMARY_MD_PATH="${tmp}/outputs/summary.md"
  TP_RUN_ID="run-1"
  TP_STARTED_AT="2026-03-01T00:00:00Z"
  TP_GENERATED_REPO="${tmp}/generated"
  TP_ORIGINAL_REPO="${tmp}/original"
  TP_ORIGINAL_SUBDIR=""
  TP_ORIGINAL_EFFECTIVE_PATH="${tmp}/original"
  TP_DIAGRAM_PATH="${tmp}/diagram.puml"
  TP_ADAPTER="codex"
  TP_MAX_ITER="1"
  TP_STRICT=false
  TP_WRITE_SCOPE_POLICY="tests-only"
  TP_STATUS="failed"
  TP_REASON="write-scope-violation"
  TP_FAILURE_CLASS="write-scope-violation"
  TP_ADAPTER_PREREQS_OK=true
  TP_BEHAVIORAL_VERDICT="invalid"
  TP_BEHAVIORAL_VERDICT_REASON="write-scope-violation"
  TP_GENERATED_REPO_UNCHANGED=true
  TP_GENERATED_BEFORE_HASH_PATH="${tmp}/before.sha256"
  TP_GENERATED_AFTER_HASH_PATH="${tmp}/after.sha256"
  TP_WRITE_SCOPE_VIOLATION_COUNT=1
  TP_WRITE_SCOPE_FAILURE_PATHS_FILE="${tmp}/last-write-scope-failure.txt"
  TP_WRITE_SCOPE_DIFF_FILE="${tmp}/disallowed-change.diff"
  TP_WRITE_SCOPE_CHANGE_SET_PATH="${tmp}/ported-protected-change-set.tsv"
  TP_WRITE_SCOPE_IGNORED_PREFIXES_CSV="./completion/proof/logs/:./.mvn_repo/:./custom/cache/"
  TP_EVIDENCE_JSON_PATH="${tmp}/retention-evidence.json"
  TP_TEST_SCOPE_JSON_PATH="${tmp}/test-scope.json"
  TP_REMOVED_TESTS_MANIFEST_REL="./completion/proof/logs/test-port-removed-tests.tsv"
  TP_RETENTION_POLICY_MODE="maximize-retained-original-tests"
  TP_RETENTION_DOCUMENTED_REMOVALS_REQUIRED=true
  TP_BASELINE_ORIGINAL_STATUS="pass"
  TP_BASELINE_ORIGINAL_RC=0
  TP_BASELINE_ORIGINAL_LOG="${tmp}/baseline-original.log"
  TP_BASELINE_ORIGINAL_STRATEGY="maven-unit-first-fallback-full"
  TP_BASELINE_ORIGINAL_UNIT_ONLY_RC=0
  TP_BASELINE_ORIGINAL_FULL_RC=-1
  TP_BASELINE_ORIGINAL_FAILURE_CLASS=""
  TP_BASELINE_ORIGINAL_FAILURE_TYPE=""
  TP_BASELINE_GENERATED_STATUS="pass"
  TP_BASELINE_GENERATED_RC=0
  TP_BASELINE_GENERATED_LOG="${tmp}/baseline-generated.log"
  TP_BASELINE_GENERATED_STRATEGY="maven-unit-first-fallback-full"
  TP_BASELINE_GENERATED_UNIT_ONLY_RC=0
  TP_BASELINE_GENERATED_FULL_RC=-1
  TP_BASELINE_GENERATED_FAILURE_CLASS=""
  TP_BASELINE_GENERATED_FAILURE_TYPE=""
  TP_PORTED_ORIGINAL_TESTS_STATUS="fail"
  TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=1
  TP_PORTED_ORIGINAL_TESTS_LOG="${tmp}/ported.log"
  TP_ITERATIONS_USED=1
  TP_ADAPTER_NONZERO_RUNS=0
  TP_ADAPTER_EVENTS_LOG="${tmp}/adapter-events.jsonl"
  TP_ADAPTER_STDERR_LOG="${tmp}/adapter-stderr.log"
  TP_ADAPTER_LAST_MESSAGE="${tmp}/adapter-last-message.md"
  TP_RUN_DIR="${tmp}"
  TP_ARTIFACTS_DIR="${tmp}/artifacts"
  TP_LOG_DIR="${tmp}/logs"
  TP_WORKSPACE_DIR="${tmp}/workspace"
  TP_OUTPUT_DIR="${tmp}/outputs"
  TP_PORTED_REPO="${tmp}/workspace/ported-tests-repo"
  TP_PORTED_REPO_ARTIFACT="${tmp}/artifacts/ported-tests-repo"
  TP_PORTED_REPO_ARTIFACT_AVAILABLE="${tmp}/artifacts/ported-tests-repo"
  TP_PORTED_REPO_ARTIFACT_EFFECTIVE="${tmp}/artifacts/ported-tests-repo"
  TP_ORIGINAL_TESTS_SNAPSHOT="${tmp}/workspace/original-tests-snapshot"

  tp_build_env_reset_suite_state "TP_BASELINE_ORIGINAL"
  tp_build_env_suite_set "TP_BASELINE_ORIGINAL" "DETECTED_RUNNER" "maven"
  tp_build_env_suite_set "TP_BASELINE_ORIGINAL" "BUILD_TOOL" "maven"
  tp_build_env_suite_set "TP_BASELINE_ORIGINAL" "JAVA_VERSION_HINT" "17"
  tp_build_env_suite_set "TP_BASELINE_ORIGINAL" "SELECTED_JDK" "17"
  tp_build_env_suite_set "TP_BASELINE_ORIGINAL" "ATTEMPTED_JDKS_CSV" "17"
  tp_build_env_reset_suite_state "TP_BASELINE_GENERATED"
  tp_build_env_suite_set "TP_BASELINE_GENERATED" "DETECTED_RUNNER" "maven"
  tp_build_env_suite_set "TP_BASELINE_GENERATED" "BUILD_TOOL" "maven"
  tp_build_env_suite_set "TP_BASELINE_GENERATED" "JAVA_VERSION_HINT" "11"
  tp_build_env_suite_set "TP_BASELINE_GENERATED" "SELECTED_JDK" "17"
  tp_build_env_suite_set "TP_BASELINE_GENERATED" "ATTEMPTED_JDKS_CSV" "11:17"
  tp_build_env_suite_set "TP_BASELINE_GENERATED" "HINT_SOURCE" "lidskjalv-generated"
  tp_build_env_reset_suite_state "TP_PORTED_ORIGINAL"
  tp_build_env_suite_set "TP_PORTED_ORIGINAL" "DETECTED_RUNNER" "maven"
  tp_build_env_suite_set "TP_PORTED_ORIGINAL" "BUILD_TOOL" "maven"
  tp_build_env_suite_set "TP_PORTED_ORIGINAL" "JAVA_VERSION_HINT" "11"
  tp_build_env_suite_set "TP_PORTED_ORIGINAL" "SELECTED_JDK" "17"
  tp_build_env_suite_set "TP_PORTED_ORIGINAL" "ATTEMPTED_JDKS_CSV" "17"

  mkdir -p "${tmp}/outputs" "${tmp}/artifacts/ported-tests-repo/src/test/java" "${tmp}/workspace/ported-tests-repo/src/test/java" "${tmp}/workspace/original-tests-snapshot/src/test/java"
  echo "digest" > "$TP_GENERATED_BEFORE_HASH_PATH"
  echo "digest" > "$TP_GENERATED_AFTER_HASH_PATH"
  cat > "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" <<'TSV'
M	./src/main/java/Prod.java
TSV
  cat > "$TP_WRITE_SCOPE_DIFF_FILE" <<'TSV'
M	./src/main/java/Prod.java
TSV
  cat > "$TP_WRITE_SCOPE_CHANGE_SET_PATH" <<'TSV'
M	./src/test/java/AdaptedTest.java
TSV
  cat > "$TP_EVIDENCE_JSON_PATH" <<'JSON'
{
  "original_snapshot_file_count": 2,
  "final_ported_test_file_count": 3,
  "retained_original_test_file_count": 1,
  "removed_original_test_file_count": 1,
  "retention_ratio": 0.5,
  "removed_original_tests": [
    {
      "path": "./src/test/java/OriginalRemovedTest.java",
      "category": "unportable",
      "reason": "requires unavailable runtime",
      "documented": true
    }
  ],
  "documented_removed_test_count": 1,
  "removed_tests_by_category": {
    "unportable": 1
  },
  "undocumented_removed_test_count": 0,
  "junit_report_count": 1,
  "junit_report_files": [
    "target/surefire-reports/TEST-fake.xml"
  ]
}
JSON
  cat > "$TP_TEST_SCOPE_JSON_PATH" <<'JSON'
{
  "mode": "portable-tests",
  "status": "selected",
  "runner": "maven",
  "build_tool": "maven",
  "selection_reason": "broad-command-passed",
  "selected_commands": ["mvn test"],
  "selected_tasks": [],
  "excluded_commands": [],
  "probes": []
}
JSON
  echo "class AdaptedTest {}" > "${TP_PORTED_REPO}/src/test/java/AdaptedTest.java"
  mkdir -p "${TP_PORTED_REPO}/target/surefire-reports"
  cat > "${TP_PORTED_REPO}/target/surefire-reports/TEST-fake.xml" <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
  echo "class AdaptedTest {}" > "${TP_PORTED_REPO_ARTIFACT}/src/test/java/AdaptedTest.java"
  mkdir -p "${TP_PORTED_REPO_ARTIFACT}/target/surefire-reports"
  cat > "${TP_PORTED_REPO_ARTIFACT}/target/surefire-reports/TEST-fake.xml" <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
  echo "class OriginalTest {}" > "${TP_ORIGINAL_TESTS_SNAPSHOT}/src/test/java/OriginalTest.java"

  tp_write_reports

  tpt_assert_file_exists "$TP_JSON_PATH" "json report must be written"
  tpt_assert_file_exists "$TP_SUMMARY_MD_PATH" "markdown summary must be written"

  python3 - <<'PY' "$TP_JSON_PATH"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("schema_version") != "kvasir.test_port.v3":
    raise SystemExit(f"unexpected schema: {obj.get('schema_version')}")
for removed in ("status", "status_detail", "failure_class_legacy", "baseline_original_tests", "baseline_generated_tests", "ported_original_tests", "suite_shape", "removed_original_tests", "unit_only_exit_code", "full_fallback_exit_code"):
    if removed in obj:
        raise SystemExit(f"legacy field should be absent: {removed}")
if obj.get("result", {}).get("status") != "failed":
    raise SystemExit(f"unexpected result: {obj.get('result')}")
expected = ["./completion/proof/logs/", "./.mvn_repo/", "./custom/cache/"]
actual = obj["diagnostics"]["write_scope"].get("ignored_prefixes", [])
if actual != expected:
    raise SystemExit(f"unexpected ignored_prefixes: {actual}")
if obj["diagnostics"]["write_scope"].get("violation_count") != 1:
    raise SystemExit("unexpected violation_count")
if "policy" in obj["diagnostics"]["write_scope"]:
    raise SystemExit(f"write-scope policy plumbing should be absent: {obj['diagnostics']['write_scope']}")
scope = obj.get("test_scope", {})
if scope.get("mode") != "portable-tests" or scope.get("selected_commands") != ["mvn test"]:
    raise SystemExit(f"unexpected test scope: {scope}")
shape = obj.get("evidence", {}).get("retention", {})
if shape.get("retained_original_test_file_count") != 1:
    raise SystemExit(f"unexpected retained count: {shape}")
if shape.get("removed_original_test_file_count") != 1:
    raise SystemExit(f"unexpected removed count: {shape}")
if shape.get("retention_ratio") != 0.5:
    raise SystemExit(f"unexpected retention ratio: {shape}")
removed = shape.get("removed_tests", [])
if len(removed) != 1 or removed[0].get("path") != "./src/test/java/OriginalRemovedTest.java":
    raise SystemExit(f"unexpected removed_original_tests: {removed}")
if shape.get("documented_removed_test_count") != 1:
    raise SystemExit(f"unexpected documented removed count: {shape}")
if shape.get("removed_tests_by_category") != {"unportable": 1}:
    raise SystemExit(f"unexpected removed test categories: {shape}")
for removed_field in ("policy", "documented_removals_required", "manifest_rel_path"):
    if removed_field in shape:
        raise SystemExit(f"retention policy plumbing should be absent: {shape}")
if shape.get("undocumented_removed_test_count") != 0:
    raise SystemExit(f"unexpected undocumented count: {shape}")
baseline = obj.get("baselines", {}).get("original", {})
if baseline.get("strategy") != "maven-unit-first-fallback-full":
    raise SystemExit(f"unexpected baseline strategy: {baseline}")
build_env = baseline.get("build_environment", {})
if build_env.get("selected_jdk") != "17":
    raise SystemExit(f"unexpected baseline selected_jdk: {build_env}")
generated_env = obj.get("baselines", {}).get("generated", {}).get("build_environment", {})
if generated_env.get("attempted_jdks") != ["11", "17"]:
    raise SystemExit(f"unexpected generated attempted_jdks: {generated_env}")
if generated_env.get("hint", {}).get("source") != "lidskjalv-generated":
    raise SystemExit(f"unexpected generated hint source: {generated_env}")
artifacts = obj.get("artifacts", {})
if artifacts.get("ported_repo") is None:
    raise SystemExit(f"expected promoted ported repo artifact, got {artifacts}")
PY

  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Schema: kvasir.test_port.v3" "summary should mention v3 schema"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Original probe scope" "summary should mention probe diagnostics"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Original test files discovered" "summary should include discovered original test files"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Documented removed tests" "summary should include documented removal count"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Removed original tests by category" "summary should include removal categories"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Evidence interpretation" "summary should characterize evidence quality"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Baseline generated" "summary should include generated baseline"
}

tpt_run_case "report includes ignored prefixes in json and summary" case_report_emits_ignored_prefixes

tpt_finish_suite
