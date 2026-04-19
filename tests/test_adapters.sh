#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/service_testlib.sh"

ROOT_DIR="$TOOL_ROOT"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/adapters/adapter.sh"

case_codex_adapter_happy_path_writes_output_last_message() {
  local tmp repo_dir diagram_path events_log stderr_log output_last_message status output_text events_text
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  export TPT_ADAPTER_SCENARIO="ignored-writes"
  repo_dir="${tmp}/repo"
  diagram_path="${tmp}/diagram.puml"
  events_log="${tmp}/adapter_events.jsonl"
  stderr_log="${tmp}/adapter_stderr.log"
  output_last_message="${tmp}/last_message.txt"
  mkdir -p "$repo_dir"
  printf '@startuml\n@enduml\n' > "$diagram_path"

  adapter_check_prereqs "codex"

  status=0
  set +e
  adapter_run_test_port_initial \
    "codex" \
    "$repo_dir" \
    "$diagram_path" \
    "$repo_dir" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e

  tpt_assert_eq "0" "$status" "codex adapter happy path should succeed"
  tpt_assert_file_exists "$output_last_message" "codex adapter should materialize output_last_message"
  output_text="$(cat "$output_last_message")"
  tpt_assert_contains "$output_text" "fake adapter message" "codex output should be preserved"
  events_text="$(cat "$events_log")"
  if [[ "$events_text" == *"post-completion-hang-recovered"* ]]; then
    echo "ASSERT failed: happy-path codex run must not log hang recovery" >&2
    return 1
  fi
}

case_codex_adapter_complete_then_hang_recovers() {
  local tmp repo_dir diagram_path events_log stderr_log output_last_message pid_file status output_text events_text
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  export TPT_ADAPTER_SCENARIO="complete-then-hang"
  export TPT_CODEX_PID_FILE="${tmp}/codex.pid"
  export KVASIR_TEST_CODEX_COMPLETION_GRACE_SEC="1"
  repo_dir="${tmp}/repo"
  diagram_path="${tmp}/diagram.puml"
  events_log="${tmp}/adapter_events.jsonl"
  stderr_log="${tmp}/adapter_stderr.log"
  output_last_message="${tmp}/last_message.txt"
  pid_file="${tmp}/codex.pid"
  mkdir -p "$repo_dir"
  printf '@startuml\n@enduml\n' > "$diagram_path"

  adapter_check_prereqs "codex"

  status=0
  set +e
  adapter_run_test_port_initial \
    "codex" \
    "$repo_dir" \
    "$diagram_path" \
    "$repo_dir" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e

  tpt_assert_eq "0" "$status" "codex adapter should recover a post-completion hang"
  tpt_assert_file_exists "$output_last_message" "recovered codex run should still write output_last_message"
  output_text="$(cat "$output_last_message")"
  tpt_assert_contains "$output_text" "fake adapter message" "recovered codex output should be preserved"
  events_text="$(cat "$events_log")"
  tpt_assert_contains "$events_text" "post-completion-hang-recovered" "codex adapter should log hang recovery"
  tpt_assert_pid_file_reaped "$pid_file" "codex adapter should reap the recovered provider process"
}

case_claude_adapter_happy_path_writes_output_last_message() {
  local tmp repo_dir diagram_path events_log stderr_log output_last_message status output_text events_text
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  export TPT_ADAPTER_SCENARIO="ignored-writes"
  repo_dir="${tmp}/repo"
  diagram_path="${tmp}/diagram.puml"
  events_log="${tmp}/adapter_events.jsonl"
  stderr_log="${tmp}/adapter_stderr.log"
  output_last_message="${tmp}/last_message.txt"
  mkdir -p "$repo_dir"
  printf '@startuml\n@enduml\n' > "$diagram_path"

  adapter_check_prereqs "claude"

  status=0
  set +e
  adapter_run_test_port_initial \
    "claude" \
    "$repo_dir" \
    "$diagram_path" \
    "$repo_dir" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e

  tpt_assert_eq "0" "$status" "claude adapter happy path should succeed"
  tpt_assert_file_exists "$output_last_message" "claude adapter should materialize output_last_message"
  output_text="$(cat "$output_last_message")"
  tpt_assert_contains "$output_text" "fake adapter message" "claude output should be preserved"
  events_text="$(cat "$events_log")"
  if [[ "$events_text" == *"post-completion-hang-recovered"* ]]; then
    echo "ASSERT failed: happy-path claude run must not log hang recovery" >&2
    return 1
  fi
}

case_claude_adapter_complete_then_hang_recovers() {
  local tmp repo_dir diagram_path events_log stderr_log output_last_message pid_file status output_text events_text
  tmp="$(tpt_mktemp_dir)"
  setup_fake_tools "$tmp"
  export TPT_ADAPTER_SCENARIO="complete-then-hang"
  export TPT_CLAUDE_PID_FILE="${tmp}/claude.pid"
  export KVASIR_TEST_CLAUDE_COMPLETION_GRACE_SEC="1"
  repo_dir="${tmp}/repo"
  diagram_path="${tmp}/diagram.puml"
  events_log="${tmp}/adapter_events.jsonl"
  stderr_log="${tmp}/adapter_stderr.log"
  output_last_message="${tmp}/last_message.txt"
  pid_file="${tmp}/claude.pid"
  mkdir -p "$repo_dir"
  printf '@startuml\n@enduml\n' > "$diagram_path"

  adapter_check_prereqs "claude"

  status=0
  set +e
  adapter_run_test_port_initial \
    "claude" \
    "$repo_dir" \
    "$diagram_path" \
    "$repo_dir" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e

  tpt_assert_eq "0" "$status" "claude adapter should recover a post-completion hang"
  tpt_assert_file_exists "$output_last_message" "recovered claude run should still write output_last_message"
  output_text="$(cat "$output_last_message")"
  tpt_assert_contains "$output_text" "fake adapter message" "recovered claude output should be preserved"
  events_text="$(cat "$events_log")"
  tpt_assert_contains "$events_text" "post-completion-hang-recovered" "claude adapter should log hang recovery"
  tpt_assert_pid_file_reaped "$pid_file" "claude adapter should reap the recovered provider process"
}

tpt_run_case "codex adapter happy path writes output_last_message" case_codex_adapter_happy_path_writes_output_last_message
tpt_run_case "codex adapter complete then hang recovers" case_codex_adapter_complete_then_hang_recovers
tpt_run_case "claude adapter happy path writes output_last_message" case_claude_adapter_happy_path_writes_output_last_message
tpt_run_case "claude adapter complete then hang recovers" case_claude_adapter_complete_then_hang_recovers

tpt_finish_suite
