#!/usr/bin/env bash
# tp_verdict.sh - behavioral verdict helpers.

set -euo pipefail

tp_compute_behavioral_verdict() {
  local failing_case_count
  local removed_original_count
  local retained_original_count
  local retained_modified_count
  local baseline_original_status
  local ported_tests_executed
  failing_case_count="${TP_EVIDENCE_JUNIT_FAILING_CASE_COUNT:-0}"
  removed_original_count="${TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT:-0}"
  retained_original_count="${TP_EVIDENCE_RETAINED_ORIGINAL_TEST_FILE_COUNT:-0}"
  retained_modified_count="${TP_EVIDENCE_RETAINED_MODIFIED_COUNT:-0}"
  baseline_original_status="${TP_BASELINE_ORIGINAL_STATUS:-skipped}"
  ported_tests_executed="${TP_PORTED_ORIGINAL_TESTS_EXECUTED:-0}"

  case "$TP_STATUS" in
    failed)
      if [[ "$TP_REASON" == "write-scope-violation" ]]; then
        TP_BEHAVIORAL_VERDICT="invalid"
        TP_BEHAVIORAL_VERDICT_REASON="write-scope-violation"
      elif [[ "$TP_REASON" == "insufficient-test-evidence" || "$TP_REASON" == "retention-policy-violation" ]]; then
        TP_BEHAVIORAL_VERDICT="invalid"
        TP_BEHAVIORAL_VERDICT_REASON="${TP_FAILURE_CLASS:-retention-policy-violation}"
      elif [[ "$failing_case_count" -gt 0 || "$TP_REASON" == "behavioral-difference-evidence" || "$TP_FAILURE_CLASS" == "assertion-failure" ]]; then
        TP_BEHAVIORAL_VERDICT="difference_detected"
        TP_BEHAVIORAL_VERDICT_REASON="assertion-mismatch-evidence"
      elif [[ "$TP_REASON" == "tests-failed" ]]; then
        TP_BEHAVIORAL_VERDICT="inconclusive"
        TP_BEHAVIORAL_VERDICT_REASON="${TP_FAILURE_CLASS:-ported-tests-failed}"
      else
        TP_BEHAVIORAL_VERDICT="inconclusive"
        TP_BEHAVIORAL_VERDICT_REASON="${TP_REASON:-stage-failed}"
      fi
      ;;
    passed)
      if [[ "$baseline_original_status" != "pass" ]]; then
        TP_BEHAVIORAL_VERDICT="inconclusive"
        TP_BEHAVIORAL_VERDICT_REASON="baseline-not-comparable"
        [[ -n "${TP_STATUS_DETAIL:-}" ]] || TP_STATUS_DETAIL="baseline_not_comparable"
      elif [[ "$ported_tests_executed" -le 0 ]]; then
        TP_BEHAVIORAL_VERDICT="no_test_signal"
        TP_BEHAVIORAL_VERDICT_REASON="no-test-signal"
        [[ -n "${TP_STATUS_DETAIL:-}" ]] || TP_STATUS_DETAIL="no_test_signal"
      elif [[ "$removed_original_count" -gt 0 ]]; then
        TP_BEHAVIORAL_VERDICT="inconclusive"
        TP_BEHAVIORAL_VERDICT_REASON="suite-reduced-during-adaptation"
      elif [[ "$retained_original_count" -gt 0 && "$retained_modified_count" -eq "$retained_original_count" && "$failing_case_count" -eq 0 ]]; then
        TP_BEHAVIORAL_VERDICT="inconclusive"
        TP_BEHAVIORAL_VERDICT_REASON="excessive-test-rewrite"
        [[ -n "${TP_STATUS_DETAIL:-}" ]] || TP_STATUS_DETAIL="post_pass_policy_failure"
      else
        TP_BEHAVIORAL_VERDICT="no_difference_detected"
        TP_BEHAVIORAL_VERDICT_REASON="retained-ported-tests-pass"
      fi
      ;;
    skipped)
      if [[ "$TP_REASON" == "no-test-signal" ]]; then
        TP_BEHAVIORAL_VERDICT="no_test_signal"
        TP_BEHAVIORAL_VERDICT_REASON="no-test-signal"
        [[ -n "${TP_STATUS_DETAIL:-}" ]] || TP_STATUS_DETAIL="no_test_signal"
      else
        TP_BEHAVIORAL_VERDICT="skipped"
        TP_BEHAVIORAL_VERDICT_REASON="${TP_REASON:-stage-skipped}"
      fi
      ;;
    *)
      TP_BEHAVIORAL_VERDICT="inconclusive"
      TP_BEHAVIORAL_VERDICT_REASON="${TP_REASON:-unknown}"
      ;;
  esac
}
