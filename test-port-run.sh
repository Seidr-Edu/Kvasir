#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$SCRIPT_DIR"
if cd "${TOOLS_DIR}/../.." 2>/dev/null; then
  MONOREPO_ROOT_CANDIDATE="$(pwd -P)"
else
  MONOREPO_ROOT_CANDIDATE=""
fi
if [[ -n "$MONOREPO_ROOT_CANDIDATE" ]] && [[ -d "${MONOREPO_ROOT_CANDIDATE}/tools/test_port" ]] && [[ "$(cd "${MONOREPO_ROOT_CANDIDATE}/tools/test_port" && pwd -P)" == "$TOOLS_DIR" ]]; then
  REPO_ROOT="$MONOREPO_ROOT_CANDIDATE"
else
  REPO_ROOT="$TOOLS_DIR"
fi

source "${TOOLS_DIR}/scripts/lib/tp_common.sh"
source "${TOOLS_DIR}/scripts/lib/tp_cli.sh"
source "${TOOLS_DIR}/scripts/lib/tp_runner.sh"
source "${TOOLS_DIR}/scripts/lib/tp_build_env.sh"
source "${TOOLS_DIR}/scripts/lib/tp_write_guard.sh"
source "${TOOLS_DIR}/scripts/lib/tp_copy.sh"
source "${TOOLS_DIR}/scripts/lib/tp_evidence.sh"
source "${TOOLS_DIR}/scripts/lib/tp_verdict.sh"
source "${TOOLS_DIR}/scripts/lib/tp_report.sh"

ROOT_DIR="${TOOLS_DIR}"
source "${TOOLS_DIR}/scripts/adapters/adapter.sh"
source "${TOOLS_DIR}/scripts/lib/tp_adapter.sh"

tp_init_result_state() {
  TP_STARTED_AT="$(tp_timestamp_iso_utc)"
  TP_WORKSPACE_PREPARED=false

  TP_STATUS="skipped"
  TP_REASON=""
  TP_STATUS_DETAIL=""
  TP_FAILURE_CLASS=""
  TP_FAILURE_CLASS_LEGACY=""
  TP_FAILURE_PHASE=""
  TP_FAILURE_SUBCLASS=""
  TP_FAILURE_FIRST_FAILURE_LINE=""
  TP_FAILURE_LOG_EXCERPT_PATH=""
  TP_ADAPTER_PREREQS_OK=true
  TP_GENERATED_REPO_UNCHANGED=true
  TP_ITERATIONS_USED=0
  TP_ADAPTER_NONZERO_RUNS=0
  TP_WRITE_SCOPE_VIOLATION_COUNT=0
  TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES_CSV=""
  TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES_CSV=""
  TP_POLICY_REJECTED_OVERRIDES_CSV=""
  TP_ENFORCE_WORKSPACE_WRITE_POLICY="${TP_ENFORCE_WORKSPACE_WRITE_POLICY:-false}"
  TP_BEHAVIORAL_VERDICT="skipped"
  TP_BEHAVIORAL_VERDICT_REASON="not-run"

  TP_RUNNER_PREFLIGHT_DETECTED_RUNNER="unknown"
  TP_RUNNER_PREFLIGHT_SUPPORTED=false
  TP_RUNNER_PREFLIGHT_MISSING_CAPABILITIES_CSV=""
  TP_RUNNER_PREFLIGHT_MODULE_ROOT=""
  TP_RUNNER_PREFLIGHT_FRAMEWORKS_DETECTED_CSV=""

  TP_TEST_SCOPE_MODE="portable-tests"
  TP_TEST_SCOPE_STATUS="unselected"
  TP_TEST_SCOPE_RUNNER="unknown"
  TP_TEST_SCOPE_BUILD_TOOL="unknown"
  TP_TEST_SCOPE_SELECTION_REASON=""
  TP_TEST_SCOPE_SELECTED_COMMANDS_CSV=""
  TP_TEST_SCOPE_SELECTED_TASKS_CSV=""
  TP_TEST_SCOPE_SELECTED_MAVEN_MODE=""
  TP_TEST_SCOPE_INCLUDED_TEST_FILE_COUNT=0
  TP_TEST_SCOPE_EXCLUDED_TEST_FILE_COUNT=0
  TP_TEST_SCOPE_FAILURE_CLASS=""
  TP_TEST_SCOPE_FAILURE_LOG=""

  TP_BASELINE_ORIGINAL_STATUS="skipped"
  TP_BASELINE_ORIGINAL_RC=-1
  TP_BASELINE_ORIGINAL_STRATEGY="single-run"
  TP_BASELINE_ORIGINAL_UNIT_ONLY_RC=-1
  TP_BASELINE_ORIGINAL_FULL_RC=-1
  TP_BASELINE_ORIGINAL_FAILURE_CLASS=""
  TP_BASELINE_ORIGINAL_FAILURE_CLASS_LEGACY=""
  TP_BASELINE_ORIGINAL_FAILURE_TYPE=""
  TP_BASELINE_ORIGINAL_FAILURE_PHASE=""
  TP_BASELINE_ORIGINAL_FAILURE_SUBCLASS=""
  TP_BASELINE_ORIGINAL_FAILURE_FIRST_LINE=""
  TP_BASELINE_ORIGINAL_TESTS_DISCOVERED=0
  TP_BASELINE_ORIGINAL_TESTS_EXECUTED=0
  TP_BASELINE_ORIGINAL_TESTS_FAILED=0
  TP_BASELINE_ORIGINAL_TESTS_ERRORS=0
  TP_BASELINE_ORIGINAL_TESTS_SKIPPED=0
  TP_BASELINE_ORIGINAL_JUNIT_REPORTS_FOUND=0
  TP_BASELINE_GENERATED_STATUS="skipped"
  TP_BASELINE_GENERATED_RC=-1
  TP_BASELINE_GENERATED_STRATEGY="single-run"
  TP_BASELINE_GENERATED_UNIT_ONLY_RC=-1
  TP_BASELINE_GENERATED_FULL_RC=-1
  TP_BASELINE_GENERATED_FAILURE_CLASS=""
  TP_BASELINE_GENERATED_FAILURE_CLASS_LEGACY=""
  TP_BASELINE_GENERATED_FAILURE_TYPE=""
  TP_BASELINE_GENERATED_FAILURE_PHASE=""
  TP_BASELINE_GENERATED_FAILURE_SUBCLASS=""
  TP_BASELINE_GENERATED_FAILURE_FIRST_LINE=""
  TP_BASELINE_GENERATED_TESTS_DISCOVERED=0
  TP_BASELINE_GENERATED_TESTS_EXECUTED=0
  TP_BASELINE_GENERATED_TESTS_FAILED=0
  TP_BASELINE_GENERATED_TESTS_ERRORS=0
  TP_BASELINE_GENERATED_TESTS_SKIPPED=0
  TP_BASELINE_GENERATED_JUNIT_REPORTS_FOUND=0
  TP_PORTED_ORIGINAL_TESTS_STATUS="skipped"
  TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=-1
  TP_PORTED_ORIGINAL_TESTS_LOG=""
  TP_PORTED_ORIGINAL_TESTS_DISCOVERED=0
  TP_PORTED_ORIGINAL_TESTS_EXECUTED=0
  TP_PORTED_ORIGINAL_TESTS_FAILED=0
  TP_PORTED_ORIGINAL_TESTS_ERRORS=0
  TP_PORTED_ORIGINAL_TESTS_SKIPPED=0
  TP_PORTED_ORIGINAL_JUNIT_REPORTS_FOUND=0
  TP_GENERATED_BASELINE_SUCCESSFUL_JDK=""
  TP_PORTED_LAST_SUCCESSFUL_JDK=""

  tp_build_env_reset_suite_state "TP_BASELINE_ORIGINAL"
  tp_build_env_reset_suite_state "TP_BASELINE_GENERATED"
  tp_build_env_reset_suite_state "TP_PORTED_ORIGINAL"

  TP_GENERATED_REPO_BEFORE_HASH=""
  TP_GENERATED_REPO_AFTER_HASH=""

  TP_EVIDENCE_ORIGINAL_SNAPSHOT_FILE_COUNT=0
  TP_EVIDENCE_FINAL_PORTED_TEST_FILE_COUNT=0
  TP_EVIDENCE_RETAINED_ORIGINAL_TEST_FILE_COUNT=0
  TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT=0
  TP_EVIDENCE_RETENTION_RATIO=""
  TP_EVIDENCE_RETAINED_MODIFIED_COUNT=0
  TP_EVIDENCE_RETAINED_UNCHANGED_COUNT=0
  TP_EVIDENCE_ASSERTION_LINE_CHANGE_COUNT=0
  TP_EVIDENCE_UNDOCUMENTED_REMOVED_TEST_COUNT=0
  TP_EVIDENCE_JUNIT_REPORT_COUNT=0
  TP_EVIDENCE_JUNIT_FAILING_CASE_COUNT=0

  TP_BEST_VALID_ITERATION=-1
  TP_BEST_VALID_RETAINED=-1
  TP_BEST_VALID_REMOVED=2147483647
  TP_BEST_VALID_LOG=""
  TP_BEST_VALID_PORTED_TESTS_DISCOVERED=0
  TP_BEST_VALID_PORTED_TESTS_EXECUTED=0
  TP_BEST_VALID_PORTED_TESTS_FAILED=0
  TP_BEST_VALID_PORTED_TESTS_ERRORS=0
  TP_BEST_VALID_PORTED_TESTS_SKIPPED=0
  TP_BEST_VALID_PORTED_JUNIT_REPORTS_FOUND=0
  TP_RETENTION_POLICY_MODE="maximize-retained-original-tests"
  TP_RETENTION_DOCUMENTED_REMOVALS_REQUIRED=true
}

tp_stage_best_valid_candidate() {
  local iteration="$1"
  local adapt_log="$2"
  local retained removed
  retained="${TP_EVIDENCE_RETAINED_ORIGINAL_TEST_FILE_COUNT:-0}"
  removed="${TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT:-0}"

  if [[ "$retained" -lt "$TP_BEST_VALID_RETAINED" ]]; then
    return 0
  fi
  if [[ "$retained" -eq "$TP_BEST_VALID_RETAINED" && "$removed" -ge "$TP_BEST_VALID_REMOVED" ]]; then
    return 0
  fi

  tp_copy_dir "$TP_PORTED_REPO" "$TP_BEST_VALID_PORTED_REPO"
  cp "$TP_EVIDENCE_JSON_PATH" "$TP_BEST_VALID_EVIDENCE_JSON_PATH"
  TP_BEST_VALID_ITERATION="$iteration"
  TP_BEST_VALID_RETAINED="$retained"
  TP_BEST_VALID_REMOVED="$removed"
  TP_BEST_VALID_LOG="$adapt_log"
  TP_BEST_VALID_PORTED_TESTS_DISCOVERED="${TP_PORTED_ORIGINAL_TESTS_DISCOVERED:-0}"
  TP_BEST_VALID_PORTED_TESTS_EXECUTED="${TP_PORTED_ORIGINAL_TESTS_EXECUTED:-0}"
  TP_BEST_VALID_PORTED_TESTS_FAILED="${TP_PORTED_ORIGINAL_TESTS_FAILED:-0}"
  TP_BEST_VALID_PORTED_TESTS_ERRORS="${TP_PORTED_ORIGINAL_TESTS_ERRORS:-0}"
  TP_BEST_VALID_PORTED_TESTS_SKIPPED="${TP_PORTED_ORIGINAL_TESTS_SKIPPED:-0}"
  TP_BEST_VALID_PORTED_JUNIT_REPORTS_FOUND="${TP_PORTED_ORIGINAL_JUNIT_REPORTS_FOUND:-0}"
}

tp_restore_best_valid_candidate() {
  [[ "$TP_BEST_VALID_ITERATION" -ge 0 ]] || return 1
  [[ -d "$TP_BEST_VALID_PORTED_REPO" ]] || return 1
  [[ -f "$TP_BEST_VALID_EVIDENCE_JSON_PATH" ]] || return 1

  tp_copy_dir "$TP_BEST_VALID_PORTED_REPO" "$TP_PORTED_REPO"
  cp "$TP_BEST_VALID_EVIDENCE_JSON_PATH" "$TP_EVIDENCE_JSON_PATH"
  tp_load_evidence_state "$TP_EVIDENCE_JSON_PATH"

  TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=0
  TP_PORTED_ORIGINAL_TESTS_STATUS="pass"
  TP_STATUS="passed"
  TP_REASON=""
  TP_FAILURE_CLASS=""
  TP_ITERATIONS_USED="$TP_BEST_VALID_ITERATION"
  TP_PORTED_ORIGINAL_TESTS_LOG="$TP_BEST_VALID_LOG"
  TP_PORTED_ORIGINAL_TESTS_DISCOVERED="${TP_BEST_VALID_PORTED_TESTS_DISCOVERED:-0}"
  TP_PORTED_ORIGINAL_TESTS_EXECUTED="${TP_BEST_VALID_PORTED_TESTS_EXECUTED:-0}"
  TP_PORTED_ORIGINAL_TESTS_FAILED="${TP_BEST_VALID_PORTED_TESTS_FAILED:-0}"
  TP_PORTED_ORIGINAL_TESTS_ERRORS="${TP_BEST_VALID_PORTED_TESTS_ERRORS:-0}"
  TP_PORTED_ORIGINAL_TESTS_SKIPPED="${TP_BEST_VALID_PORTED_TESTS_SKIPPED:-0}"
  TP_PORTED_ORIGINAL_JUNIT_REPORTS_FOUND="${TP_BEST_VALID_PORTED_JUNIT_REPORTS_FOUND:-0}"
  return 0
}

tp_has_build_markers() {
  local dir="$1"
  [[ -f "${dir}/pom.xml" || -x "${dir}/gradlew" || -f "${dir}/build.gradle" || -f "${dir}/build.gradle.kts" ]]
}

tp_auto_detect_generated_subdir() {
  local generated_repo="$1"
  local snapshot_dir="$2"
  local candidate=""
  local multiple=false

  [[ -d "$snapshot_dir" ]] || { echo ""; return 0; }

  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rel="${rel#./}"
    case "$rel" in
      src/test/*|src/*Test*/*|test/*|tests/*|completion/*|.git/*)
        continue
        ;;
    esac
    local first="${rel%%/*}"
    [[ -n "$first" ]] || continue
    case "$first" in
      src|test|tests|completion|.git|out|build|target)
        continue
        ;;
    esac

    if [[ -z "$candidate" ]]; then
      candidate="$first"
    elif [[ "$candidate" != "$first" ]]; then
      multiple=true
      break
    fi
  done < <(cd "$snapshot_dir" && find . -type f -print | LC_ALL=C sort)

  if $multiple || [[ -z "$candidate" ]]; then
    echo ""
    return 0
  fi
  tp_has_build_markers "${generated_repo}/${candidate}" || { echo ""; return 0; }
  echo "$candidate"
}

tp_configure_generated_effective_roots() {
  local detected_subdir=""
  if [[ -z "${TP_GENERATED_EFFECTIVE_SUBDIR:-}" ]]; then
    detected_subdir="$(tp_auto_detect_generated_subdir "$TP_GENERATED_REPO" "$TP_ORIGINAL_TESTS_SNAPSHOT")"
    TP_GENERATED_EFFECTIVE_SUBDIR="$detected_subdir"
  fi

  if [[ -n "${TP_GENERATED_EFFECTIVE_SUBDIR:-}" ]]; then
    TP_GENERATED_EFFECTIVE_PATH="${TP_GENERATED_REPO}/${TP_GENERATED_EFFECTIVE_SUBDIR}"
    TP_GENERATED_BASELINE_EFFECTIVE_REPO="${TP_GENERATED_BASELINE_REPO}/${TP_GENERATED_EFFECTIVE_SUBDIR}"
    TP_PORTED_EFFECTIVE_REPO="${TP_PORTED_REPO}/${TP_GENERATED_EFFECTIVE_SUBDIR}"
    TP_PORTED_REPO_ARTIFACT_EFFECTIVE="${TP_PORTED_REPO_ARTIFACT}/${TP_GENERATED_EFFECTIVE_SUBDIR}"
  else
    TP_GENERATED_EFFECTIVE_PATH="${TP_GENERATED_REPO}"
    TP_GENERATED_BASELINE_EFFECTIVE_REPO="${TP_GENERATED_BASELINE_REPO}"
    TP_PORTED_EFFECTIVE_REPO="${TP_PORTED_REPO}"
    TP_PORTED_REPO_ARTIFACT_EFFECTIVE="${TP_PORTED_REPO_ARTIFACT}"
  fi
}

tp_capture_failure_diagnostics() {
  local log_file="$1"
  TP_FAILURE_PHASE="${TP_LAST_FAILURE_PHASE:-unknown}"
  TP_FAILURE_SUBCLASS="${TP_LAST_FAILURE_SUBCLASS:-unknown}"
  TP_FAILURE_CLASS_LEGACY="${TP_LAST_FAILURE_CLASS_LEGACY:-unknown}"
  TP_FAILURE_FIRST_FAILURE_LINE="${TP_LAST_FAILURE_FIRST_LINE:-}"
  TP_FAILURE_LOG_EXCERPT_PATH="${TP_SUMMARY_DIR}/failure-log-excerpt.txt"
  tp_write_failure_excerpt "$log_file" "$TP_FAILURE_LOG_EXCERPT_PATH" 240
}

tp_enforce_report_consistency() {
  if [[ "$TP_STATUS" == "failed" && "$TP_REASON" == "tests-failed" && "$TP_PORTED_ORIGINAL_TESTS_STATUS" == "pass" ]]; then
    TP_REASON="internal-report-inconsistency"
    TP_FAILURE_CLASS="internal-report-inconsistency"
    TP_FAILURE_CLASS_LEGACY="unknown"
    TP_STATUS_DETAIL="post_pass_policy_failure"
    TP_FAILURE_PHASE="unknown"
    TP_FAILURE_SUBCLASS="internal-report-inconsistency"
    TP_FAILURE_FIRST_FAILURE_LINE="status=failed + reason=tests-failed with ported_original_tests.status=pass"
    TP_FAILURE_LOG_EXCERPT_PATH="${TP_SUMMARY_DIR}/failure-log-excerpt.txt"
    printf '%s\n' "$TP_FAILURE_FIRST_FAILURE_LINE" > "$TP_FAILURE_LOG_EXCERPT_PATH"
  fi
}

tp_execute() {
  : > "$TP_ADAPTER_EVENTS_LOG"
  : > "$TP_ADAPTER_STDERR_LOG"
  : > "$TP_ADAPTER_LAST_MESSAGE"

  [[ -d "$TP_ORIGINAL_REPO" ]] || {
    TP_STATUS="skipped"
    TP_REASON="missing-original-repo"
    TP_STATUS_DETAIL="missing_input"
    return 0
  }
  [[ -d "$TP_GENERATED_REPO" ]] || {
    TP_STATUS="skipped"
    TP_REASON="missing-generated-repo"
    TP_STATUS_DETAIL="missing_input"
    return 0
  }

  if ! tp_adapter_check_prereqs "$TP_ADAPTER"; then
    TP_ADAPTER_PREREQS_OK=false
    TP_STATUS="skipped"
    TP_REASON="adapter-prereqs-failed"
    TP_STATUS_DETAIL="adapter_prereqs_failed"
    return 0
  fi

  if ! command -v rsync >/dev/null 2>&1; then
    TP_STATUS="skipped"
    TP_REASON="missing-rsync"
    TP_STATUS_DETAIL="missing_runtime_dependency"
    return 0
  fi

  if ! tp_prepare_workspace_copies; then
    TP_STATUS="failed"
    TP_REASON="workspace-prepare-failed"
    TP_STATUS_DETAIL="workspace_prepare_failed"
    TP_FAILURE_CLASS="workspace-prepare-failed"
    TP_FAILURE_CLASS_LEGACY="unknown"
    return 0
  fi
  TP_WORKSPACE_PREPARED=true

  set +e
  tp_select_portable_test_scope_with_build_env "TP_BASELINE_ORIGINAL" "$TP_ORIGINAL_BASELINE_REPO" "$TP_BASELINE_ORIGINAL_LOG"
  TP_BASELINE_ORIGINAL_RC=$?
  set -e

  set +e
  tp_run_baseline_tests_with_build_env "TP_BASELINE_ORIGINAL" "$TP_ORIGINAL_BASELINE_REPO" "$TP_BASELINE_ORIGINAL_LOG"
  TP_BASELINE_ORIGINAL_RC=$?
  tp_collect_execution_summary "$TP_ORIGINAL_BASELINE_REPO" "$TP_BASELINE_ORIGINAL_LOG" "TP_BASELINE_ORIGINAL"
  TP_BASELINE_ORIGINAL_STATUS="$TP_BASELINE_LAST_STATUS"
  TP_BASELINE_ORIGINAL_STRATEGY="$TP_BASELINE_LAST_STRATEGY"
  TP_BASELINE_ORIGINAL_UNIT_ONLY_RC="$TP_BASELINE_LAST_UNIT_ONLY_RC"
  TP_BASELINE_ORIGINAL_FULL_RC="$TP_BASELINE_LAST_FULL_RC"
  TP_BASELINE_ORIGINAL_FAILURE_CLASS="$TP_BASELINE_LAST_FAILURE_CLASS"
  TP_BASELINE_ORIGINAL_FAILURE_CLASS_LEGACY="$TP_BASELINE_LAST_FAILURE_CLASS_LEGACY"
  TP_BASELINE_ORIGINAL_FAILURE_TYPE="$TP_BASELINE_LAST_FAILURE_TYPE"
  TP_BASELINE_ORIGINAL_FAILURE_PHASE="$TP_BASELINE_LAST_FAILURE_PHASE"
  TP_BASELINE_ORIGINAL_FAILURE_SUBCLASS="$TP_BASELINE_LAST_FAILURE_SUBCLASS"
  TP_BASELINE_ORIGINAL_FAILURE_FIRST_LINE="$TP_BASELINE_LAST_FAILURE_FIRST_LINE"
  set -e

  if ! tp_snapshot_original_tests; then
    if [[ -d "$TP_ORIGINAL_TESTS_SNAPSHOT" ]] && ! find "$TP_ORIGINAL_TESTS_SNAPSHOT" -type f -print -quit | grep -q .; then
      TP_STATUS="skipped"
      TP_REASON="no-test-files-found"
    else
      TP_STATUS="skipped"
      TP_REASON="test-snapshot-copy-failed"
    fi
    return 0
  fi

  tp_configure_generated_effective_roots

  set +e
  tp_run_baseline_tests_with_build_env "TP_BASELINE_GENERATED" "$TP_GENERATED_BASELINE_EFFECTIVE_REPO" "$TP_BASELINE_GENERATED_LOG"
  TP_BASELINE_GENERATED_RC=$?
  tp_collect_execution_summary "$TP_GENERATED_BASELINE_EFFECTIVE_REPO" "$TP_BASELINE_GENERATED_LOG" "TP_BASELINE_GENERATED"
  TP_BASELINE_GENERATED_STATUS="$TP_BASELINE_LAST_STATUS"
  TP_BASELINE_GENERATED_STRATEGY="$TP_BASELINE_LAST_STRATEGY"
  TP_BASELINE_GENERATED_UNIT_ONLY_RC="$TP_BASELINE_LAST_UNIT_ONLY_RC"
  TP_BASELINE_GENERATED_FULL_RC="$TP_BASELINE_LAST_FULL_RC"
  TP_BASELINE_GENERATED_FAILURE_CLASS="$TP_BASELINE_LAST_FAILURE_CLASS"
  TP_BASELINE_GENERATED_FAILURE_CLASS_LEGACY="$TP_BASELINE_LAST_FAILURE_CLASS_LEGACY"
  TP_BASELINE_GENERATED_FAILURE_TYPE="$TP_BASELINE_LAST_FAILURE_TYPE"
  TP_BASELINE_GENERATED_FAILURE_PHASE="$TP_BASELINE_LAST_FAILURE_PHASE"
  TP_BASELINE_GENERATED_FAILURE_SUBCLASS="$TP_BASELINE_LAST_FAILURE_SUBCLASS"
  TP_BASELINE_GENERATED_FAILURE_FIRST_LINE="$TP_BASELINE_LAST_FAILURE_FIRST_LINE"
  set -e

  if ! tp_seed_ported_repo_with_original_tests; then
    TP_STATUS="failed"
    TP_REASON="ported-test-copy-failed"
    return 0
  fi

  if [[ "${TP_ENFORCE_WORKSPACE_WRITE_POLICY}" == "true" ]]; then
    tp_apply_workspace_write_policy "$TP_PORTED_REPO"
  fi

  tp_preflight_runner "$TP_PORTED_REPO" "${TP_GENERATED_EFFECTIVE_SUBDIR:-}"
  if [[ "${TP_RUNNER_PREFLIGHT_SUPPORTED}" != "true" ]]; then
    TP_STATUS="skipped"
    TP_REASON="unsupported-test-runner"
    TP_STATUS_DETAIL="unsupported_runner"
    TP_PORTED_ORIGINAL_TESTS_STATUS="skipped"
    TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=2
    return 0
  fi

  tp_write_repo_manifest "$TP_PORTED_REPO" "$TP_WRITE_SCOPE_BEFORE_FILE"
  : > "$TP_LAST_TEST_FAILURE_SUMMARY_FILE"
  : > "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
  : > "$TP_WRITE_SCOPE_DIFF_FILE"
  rm -rf "$TP_BEST_VALID_PORTED_REPO"
  rm -f "$TP_EVIDENCE_JSON_PATH" "$TP_BEST_VALID_EVIDENCE_JSON_PATH"

  TP_STATUS="failed"
  TP_REASON="max-iterations-reached"
  TP_STATUS_DETAIL=""

  local i
  for ((i=0; i<=TP_MAX_ITER; i++)); do
    if [[ $i -eq 0 ]]; then
      tp_adapter_run_initial "$TP_ADAPTER" || TP_ADAPTER_NONZERO_RUNS=$((TP_ADAPTER_NONZERO_RUNS + 1))
    else
      tp_adapter_run_iteration "$TP_ADAPTER" "$i" || TP_ADAPTER_NONZERO_RUNS=$((TP_ADAPTER_NONZERO_RUNS + 1))
    fi

    : > "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE"
    : > "$TP_WRITE_SCOPE_DIFF_FILE"
    if tp_check_write_scope "$TP_PORTED_REPO" "$TP_WRITE_SCOPE_BEFORE_FILE" "$TP_WRITE_SCOPE_AFTER_FILE"; then
      :
    else
      local write_scope_rc=$?
      TP_STATUS="failed"
      TP_PORTED_ORIGINAL_TESTS_STATUS="fail"
      TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=1
      TP_ITERATIONS_USED="$i"
      if [[ "$write_scope_rc" -eq 1 ]]; then
        TP_REASON="write-scope-violation"
        TP_FAILURE_CLASS="write-scope-violation"
        TP_FAILURE_CLASS_LEGACY="unknown"
      else
        TP_REASON="write-scope-check-failed"
        TP_FAILURE_CLASS="write-scope-check-failed"
        TP_FAILURE_CLASS_LEGACY="unknown"
      fi
      break
    fi

    local adapt_log="${TP_LOG_DIR}/adapt-iter-${i}.log"
    TP_PORTED_ORIGINAL_TESTS_LOG="$adapt_log"
    if tp_run_tests_with_build_env "TP_PORTED_ORIGINAL" "$TP_PORTED_EFFECTIVE_REPO" "$adapt_log"; then
      TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=0
      TP_PORTED_ORIGINAL_TESTS_STATUS="pass"
      TP_ITERATIONS_USED="$i"
      tp_collect_execution_summary "$TP_PORTED_EFFECTIVE_REPO" "$adapt_log" "TP_PORTED_ORIGINAL"

      if [[ "${TP_PORTED_ORIGINAL_TESTS_EXECUTED:-0}" -le 0 ]]; then
        TP_STATUS="skipped"
        TP_REASON="no-test-signal"
        TP_STATUS_DETAIL="no_test_signal"
        TP_FAILURE_CLASS=""
        TP_FAILURE_CLASS_LEGACY=""
        break
      fi

      tp_refresh_evidence_state "$TP_PORTED_EFFECTIVE_REPO" "$TP_ORIGINAL_TESTS_SNAPSHOT" "$TP_REMOVED_TESTS_MANIFEST_PATH" "$TP_EVIDENCE_JSON_PATH"

      if [[ "${TP_EVIDENCE_UNDOCUMENTED_REMOVED_TEST_COUNT:-0}" -gt 0 ]]; then
        TP_STATUS="failed"
        TP_REASON="retention-policy-violation"
        TP_FAILURE_CLASS="invalid-removal-documentation"
        TP_FAILURE_CLASS_LEGACY="unknown"
        TP_STATUS_DETAIL="post_pass_policy_failure"
        TP_PORTED_ORIGINAL_TESTS_STATUS="fail"
        TP_PORTED_ORIGINAL_TESTS_EXIT_CODE=1
        tp_write_evidence_feedback_summary \
          "$TP_LAST_TEST_FAILURE_SUMMARY_FILE" \
          "$TP_EVIDENCE_JSON_PATH" \
          "Original tests were removed without valid retention-policy documentation. Restore them or use an allowed reason code with a concrete rationale in the required manifest." \
          "$TP_REMOVED_TESTS_MANIFEST_REL"
        if [[ "$i" -lt "$TP_MAX_ITER" ]]; then
          continue
        fi
        break
      fi

      tp_stage_best_valid_candidate "$i" "$adapt_log"

      TP_STATUS="passed"
      TP_REASON=""
      TP_STATUS_DETAIL=""
      TP_FAILURE_CLASS=""
      TP_FAILURE_CLASS_LEGACY=""

      if [[ "${TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT:-0}" -eq 0 ]]; then
        break
      fi
      if [[ "$i" -lt "$TP_MAX_ITER" ]]; then
        tp_write_evidence_feedback_summary \
          "$TP_LAST_TEST_FAILURE_SUMMARY_FILE" \
          "$TP_EVIDENCE_JSON_PATH" \
          "Tests pass, but retention policy requires restoring as many removed original tests as possible before finishing." \
          "$TP_REMOVED_TESTS_MANIFEST_REL"
        continue
      fi
      break
    else
      local adapt_rc=$?
      TP_PORTED_ORIGINAL_TESTS_EXIT_CODE="$adapt_rc"
      TP_PORTED_ORIGINAL_TESTS_STATUS="$(tp_test_rc_status "$adapt_rc")"
      TP_ITERATIONS_USED="$i"
      tp_collect_execution_summary "$TP_PORTED_EFFECTIVE_REPO" "$adapt_log" "TP_PORTED_ORIGINAL"

      if [[ "$adapt_rc" -eq 2 ]]; then
        TP_STATUS="skipped"
        TP_REASON="unsupported-test-runner"
        TP_STATUS_DETAIL="unsupported_runner"
        break
      fi

      tail -n 200 "$adapt_log" > "$TP_LAST_TEST_FAILURE_SUMMARY_FILE" || true
      TP_STATUS="failed"
      TP_STATUS_DETAIL=""
      tp_classify_test_failure_log "$adapt_log" >/dev/null
      TP_FAILURE_CLASS="${TP_LAST_FAILURE_CLASS:-unknown}"
      tp_capture_failure_diagnostics "$adapt_log"
      if [[ "$TP_FAILURE_CLASS" == "assertion-failure" ]]; then
        TP_REASON="behavioral-difference-evidence"
        break
      fi
      TP_REASON="tests-failed"
    fi
  done

  if [[ "$TP_BEST_VALID_ITERATION" -ge 0 && "$TP_REASON" != "write-scope-violation" && "$TP_REASON" != "write-scope-check-failed" ]]; then
    tp_restore_best_valid_candidate || true
    if [[ "${TP_ENFORCE_WORKSPACE_WRITE_POLICY}" == "true" ]]; then
      tp_apply_workspace_write_policy "$TP_PORTED_REPO"
    fi
  elif [[ -f "$TP_EVIDENCE_JSON_PATH" ]]; then
    tp_load_evidence_state "$TP_EVIDENCE_JSON_PATH"
  fi

  tp_enforce_report_consistency

  return 0
}

main() {
  tp_parse_args "$@"
  tp_validate_and_finalize_args
  tp_adapter_validate_supported "$TP_ADAPTER"
  tp_init_result_state
  mkdir -p "$TP_LOG_DIR" "$TP_OUTPUT_DIR" "$TP_TMP_DIR"
  tp_build_env_prepare_runtime_toolcache
  export TMPDIR="$TP_TMP_DIR"

  # Codex adapter requires a diagram path to derive a readable context dir. When no
  # diagram is supplied, use a synthetic path under the generated repo (dirname exists).
  TP_ADAPTER_INPUT_DIAGRAM_PATH="${TP_DIAGRAM_PATH:-${TP_GENERATED_REPO}/.test-port-no-diagram.puml}"

  tp_log "run dir: $TP_RUN_DIR"
  tp_log "generated repo: $TP_GENERATED_REPO"
  tp_log "original repo: $TP_ORIGINAL_REPO"
  [[ -n "$TP_ORIGINAL_SUBDIR" ]] && tp_log "original subdir: $TP_ORIGINAL_SUBDIR"
  [[ -n "$TP_GENERATED_SUBDIR" ]] && tp_log "generated subdir (requested): $TP_GENERATED_SUBDIR"

  tp_execute

  if $TP_WORKSPACE_PREPARED; then
    tp_finalize_generated_repo_immutability_guard
  fi

  if [[ -d "${TP_PORTED_EFFECTIVE_REPO:-}" && -d "${TP_ORIGINAL_TESTS_SNAPSHOT:-}" ]]; then
    tp_refresh_evidence_state "$TP_PORTED_EFFECTIVE_REPO" "$TP_ORIGINAL_TESTS_SNAPSHOT" "$TP_REMOVED_TESTS_MANIFEST_PATH" "$TP_EVIDENCE_JSON_PATH" || true
  fi

  tp_compute_behavioral_verdict
  if ! tp_promote_ported_repo_artifact; then
    tp_warn "failed to promote ported repo artifact to ${TP_PORTED_REPO_ARTIFACT}"
  fi
  tp_write_reports
  if ! tp_cleanup_temporary_workspace_repos; then
    tp_warn "failed to clean temporary workspace repo copies"
  fi

  tp_log "summary: $TP_SUMMARY_MD_PATH"
  tp_log "json: $TP_JSON_PATH"

  if $TP_STRICT && [[ "$TP_STATUS" != "passed" ]]; then
    return 1
  fi
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
