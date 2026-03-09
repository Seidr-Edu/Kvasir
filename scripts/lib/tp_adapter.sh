#!/usr/bin/env bash
# tp_adapter.sh - bridge to Andvari adapter interface for test-port prompts.

set -euo pipefail

tp_adapter_validate_supported() {
  local adapter="$1"
  if ! adapter_is_supported "$adapter"; then
    tp_fail "Unsupported adapter: ${adapter}. Supported adapters: $(adapter_list)"
  fi
}

tp_adapter_check_prereqs() {
  local adapter="$1"
  adapter_check_prereqs "$adapter"
}

tp_adapter_run_initial() {
  local adapter="$1"
  adapter_run_test_port_initial \
    "$adapter" \
    "$TP_PORTED_REPO" \
    "$TP_ADAPTER_INPUT_DIAGRAM_PATH" \
    "$TP_ORIGINAL_EFFECTIVE_PATH" \
    "$TP_ADAPTER_EVENTS_LOG" \
    "$TP_ADAPTER_STDERR_LOG" \
    "$TP_ADAPTER_LAST_MESSAGE"
}

tp_adapter_run_iteration() {
  local adapter="$1"
  local iteration="$2"
  adapter_run_test_port_iteration \
    "$adapter" \
    "$TP_PORTED_REPO" \
    "$TP_ADAPTER_INPUT_DIAGRAM_PATH" \
    "$TP_ORIGINAL_EFFECTIVE_PATH" \
    "$TP_LAST_TEST_FAILURE_SUMMARY_FILE" \
    "$TP_ADAPTER_EVENTS_LOG" \
    "$TP_ADAPTER_STDERR_LOG" \
    "$TP_ADAPTER_LAST_MESSAGE" \
    "$iteration"
}
