#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_verdict.sh"

reset_verdict_env() {
  TP_STATUS="failed"
  TP_REASON="tests-failed"
  TP_FAILURE_CLASS="compilation-failure"
  TP_EVIDENCE_JUNIT_FAILING_CASE_COUNT=0
  TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT=0
  TP_EVIDENCE_RETAINED_ORIGINAL_TEST_FILE_COUNT=1
  TP_EVIDENCE_RETAINED_MODIFIED_COUNT=0
  TP_BASELINE_ORIGINAL_STATUS="pass"
  TP_PORTED_ORIGINAL_TESTS_EXECUTED=1
  TP_STATUS_DETAIL=""
  TP_BEHAVIORAL_VERDICT=""
  TP_BEHAVIORAL_VERDICT_REASON=""
}

case_prefers_junit_failure_evidence() {
  reset_verdict_env
  TP_EVIDENCE_JUNIT_FAILING_CASE_COUNT=3

  tp_compute_behavioral_verdict

  tpt_assert_eq "difference_detected" "$TP_BEHAVIORAL_VERDICT" "JUnit failures should force difference_detected"
  tpt_assert_eq "assertion-mismatch-evidence" "$TP_BEHAVIORAL_VERDICT_REASON" "verdict reason should reflect assertion evidence"
}

case_insufficient_evidence_is_invalid() {
  reset_verdict_env
  TP_REASON="insufficient-test-evidence"
  TP_FAILURE_CLASS="undocumented-test-removal"

  tp_compute_behavioral_verdict

  tpt_assert_eq "invalid" "$TP_BEHAVIORAL_VERDICT" "insufficient evidence should be invalid"
  tpt_assert_eq "undocumented-test-removal" "$TP_BEHAVIORAL_VERDICT_REASON" "invalid reason should preserve failure class"
}

case_pass_with_removed_tests_is_inconclusive() {
  reset_verdict_env
  TP_STATUS="passed"
  TP_REASON=""
  TP_FAILURE_CLASS=""
  TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT=2

  tp_compute_behavioral_verdict

  tpt_assert_eq "inconclusive" "$TP_BEHAVIORAL_VERDICT" "removed original tests should keep verdict inconclusive"
  tpt_assert_eq "suite-reduced-during-adaptation" "$TP_BEHAVIORAL_VERDICT_REASON" "reason should reflect suite reduction"
}

case_pass_without_removed_tests_is_no_difference() {
  reset_verdict_env
  TP_STATUS="passed"
  TP_REASON=""
  TP_FAILURE_CLASS=""
  TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT=0

  tp_compute_behavioral_verdict

  tpt_assert_eq "no_difference_detected" "$TP_BEHAVIORAL_VERDICT" "full retained suite should report no_difference_detected"
  tpt_assert_eq "retained-ported-tests-pass" "$TP_BEHAVIORAL_VERDICT_REASON" "reason should reflect full-retention pass"
}

tpt_run_case "prefers junit failure evidence over classifier" case_prefers_junit_failure_evidence
tpt_run_case "insufficient evidence verdict is invalid" case_insufficient_evidence_is_invalid
tpt_run_case "pass with removed tests stays inconclusive" case_pass_with_removed_tests_is_inconclusive
tpt_run_case "pass without removed tests is no_difference" case_pass_without_removed_tests_is_no_difference

tpt_finish_suite
