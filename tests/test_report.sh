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
  "undocumented_removed_test_count": 0,
  "junit_report_count": 1,
  "junit_report_files": [
    "target/surefire-reports/TEST-fake.xml"
  ]
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
expected = ["./completion/proof/logs/", "./.mvn_repo/", "./custom/cache/"]
actual = obj["write_scope"].get("ignored_prefixes", [])
if actual != expected:
    raise SystemExit(f"unexpected ignored_prefixes: {actual}")
if obj["write_scope"].get("violation_count") != 1:
    raise SystemExit("unexpected violation_count")
shape = obj.get("suite_shape", {})
if shape.get("retained_original_test_file_count") != 1:
    raise SystemExit(f"unexpected retained count: {shape}")
if shape.get("removed_original_test_file_count") != 1:
    raise SystemExit(f"unexpected removed count: {shape}")
if shape.get("retention_ratio") != 0.5:
    raise SystemExit(f"unexpected retention ratio: {shape}")
removed = obj.get("removed_original_tests", [])
if len(removed) != 1 or removed[0].get("path") != "./src/test/java/OriginalRemovedTest.java":
    raise SystemExit(f"unexpected removed_original_tests: {removed}")
policy = obj.get("retention_policy", {})
if policy.get("mode") != "maximize-retained-original-tests":
    raise SystemExit(f"unexpected retention policy mode: {policy}")
if policy.get("undocumented_removed_test_count") != 0:
    raise SystemExit(f"unexpected undocumented count: {policy}")
baseline = obj.get("baseline_original_tests", {})
if baseline.get("strategy") != "maven-unit-first-fallback-full":
    raise SystemExit(f"unexpected baseline strategy: {baseline}")
if baseline.get("unit_only_exit_code") != 0:
    raise SystemExit(f"unexpected baseline unit-only rc: {baseline}")
build_env = baseline.get("build_environment", {})
if build_env.get("selected_jdk") != "17":
    raise SystemExit(f"unexpected baseline selected_jdk: {build_env}")
generated_env = obj.get("baseline_generated_tests", {}).get("build_environment", {})
if generated_env.get("attempted_jdks") != ["11", "17"]:
    raise SystemExit(f"unexpected generated attempted_jdks: {generated_env}")
if generated_env.get("hint", {}).get("source") != "lidskjalv-generated":
    raise SystemExit(f"unexpected generated hint source: {generated_env}")
artifacts = obj.get("artifacts", {})
if artifacts.get("ported_repo") is None:
    raise SystemExit(f"expected promoted ported repo artifact, got {artifacts}")
PY

  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Write-scope ignored prefixes" "summary should mention ignored prefixes"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "./completion/proof/logs/" "summary should include resolved ignored prefixes"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Retention policy" "summary should mention retention policy"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Removed original tests" "summary should include removed-test count"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "Baseline generated build env" "summary should include generated build environment"
  tpt_assert_file_contains "$TP_SUMMARY_MD_PATH" "selected_jdk=17" "summary should include selected JDK details"
}

tpt_run_case "report includes ignored prefixes in json and summary" case_report_emits_ignored_prefixes

tpt_finish_suite
