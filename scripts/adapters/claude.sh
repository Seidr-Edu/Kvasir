#!/usr/bin/env bash
set -euo pipefail

timestamp_utc_adapter_claude() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_claude_adapter_event() {
  local events_log="$1"
  local phase="$2"
  local iteration="$3"
  local run_time
  run_time="$(timestamp_utc_adapter_claude)"

  printf '{"type":"test-port.adapter","adapter":"claude","phase":"%s","iteration":"%s","time":"%s"}\n' \
    "$phase" "$iteration" "$run_time" >> "$events_log"
}

append_claude_adapter_runtime_event() {
  local events_log="$1"
  local event="$2"
  local run_time
  run_time="$(timestamp_utc_adapter_claude)"

  printf '{"type":"test-port.adapter","adapter":"claude","phase":"provider-runtime","iteration":"-","event":"%s","time":"%s"}\n' \
    "$event" "$run_time" >> "$events_log"
}

_claude_prompts_dir() {
  echo "${ROOT_DIR}/prompts"
}

_claude_render_template() {
  local template_name="$1"
  shift
  local prompts_dir
  prompts_dir="$(_claude_prompts_dir)"
  local template_path="${prompts_dir}/${template_name}"

  [[ -f "$template_path" ]] || {
    echo "Prompt template not found: ${template_path}" >&2
    return 1
  }

  local content
  IFS= read -r -d '' content < "$template_path" || true

  local pair key val
  for pair in "$@"; do
    key="${pair%%=*}"
    val="${pair#*=}"
    content="${content//\$\{${key}\}/${val}}"
  done

  printf '%s' "$content"
}

claude_check_prereqs() {
  if ! command -v claude >/dev/null 2>&1; then
    echo "claude CLI not found. Install Claude Code and ensure 'claude' is on PATH." >&2
    return 1
  fi

  if ! claude --version >/dev/null 2>&1; then
    cat >&2 <<'PREREQ_EOF'
claude CLI is installed but failed a basic health check.
Run:
  claude --version
Then verify the CLI is authenticated/configured for non-interactive use.
PREREQ_EOF
    return 1
  fi

  local prompts_dir
  prompts_dir="$(_claude_prompts_dir)"
  local required_templates=(
    "test_port_initial.md"
    "test_port_iteration.md"
  )
  local tpl
  for tpl in "${required_templates[@]}"; do
    [[ -f "${prompts_dir}/${tpl}" ]] || {
      echo "Required prompt template not found: ${prompts_dir}/${tpl}" >&2
      return 1
    }
  done
}

_claude_completion_grace_sec() {
  local raw="${KVASIR_TEST_CLAUDE_COMPLETION_GRACE_SEC:-30}"
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf '%s' "$raw"
  else
    printf '30'
  fi
}

_claude_process_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

_claude_signal_process_group() {
  local signal="$1"
  local pid="$2"

  kill -s "$signal" -- "-${pid}" 2>/dev/null || kill -s "$signal" "$pid" 2>/dev/null || true
}

_claude_record_active_provider_process() {
  local pid="$1"
  local pid_file="${KVASIR_PROVIDER_PROCESS_FILE:-}"

  [[ -n "$pid_file" ]] || return 0
  mkdir -p "$(dirname "$pid_file")"
  printf '%s\n' "$pid" > "$pid_file"
}

_claude_clear_active_provider_process() {
  local pid_file="${KVASIR_PROVIDER_PROCESS_FILE:-}"
  [[ -n "$pid_file" ]] || return 0
  rm -f "$pid_file"
}

_claude_exec_in_process_group() {
  if command -v setsid >/dev/null 2>&1; then
    exec setsid "$@"
  fi

  exec python3 -c '
import os, sys
argv = sys.argv[1:]
os.setsid()
os.execvp(argv[0], argv)
' "$@"
}

_claude_flush_file_delta() {
  local source_path="$1"
  local target_path="$2"
  local previous_size="${3:-0}"

  python3 - "$source_path" "$target_path" "$previous_size" <<'PY'
import os
import sys

source_path, target_path, previous_raw = sys.argv[1:4]

try:
    previous_size = int(previous_raw)
except ValueError:
    previous_size = 0

current_size = os.path.getsize(source_path) if os.path.exists(source_path) else 0

if current_size > previous_size:
    with open(source_path, "rb") as source_file, open(target_path, "ab") as target_file:
        source_file.seek(previous_size)
        remaining = current_size - previous_size
        while remaining > 0:
            chunk = source_file.read(min(65536, remaining))
            if not chunk:
                break
            target_file.write(chunk)
            remaining -= len(chunk)

print(current_size)
PY
}

run_claude_prompt() {
  local working_repo_dir="$1"
  local prompt_file="$2"
  local events_log="$3"
  local stderr_log="$4"
  local output_last_message="$5"
  shift 5
  local -a extra_args=("$@")

  if [[ ${#extra_args[@]} -gt 0 ]]; then
    :
  fi

  local grace_sec
  grace_sec="$(_claude_completion_grace_sec)"

  local stdout_spool stderr_spool
  stdout_spool="$(mktemp)"
  stderr_spool="$(mktemp)"

  local stdout_size="0"
  local stderr_size="0"
  local last_output_change_at="0"
  local recovered_hang="false"
  local status="0"

  rm -f "$output_last_message"

  set +e
  (
    cd "$working_repo_dir"
    _claude_exec_in_process_group claude --dangerously-skip-permissions --print < "$prompt_file"
  ) > "$stdout_spool" 2> "$stderr_spool" &
  local cmd_pid=$!
  _claude_record_active_provider_process "$cmd_pid"

  while _claude_process_alive "$cmd_pid"; do
    local previous_stdout_size="$stdout_size"
    stdout_size="$(_claude_flush_file_delta "$stdout_spool" "$output_last_message" "$stdout_size")"
    stderr_size="$(_claude_flush_file_delta "$stderr_spool" "$stderr_log" "$stderr_size")"

    if (( stdout_size > previous_stdout_size )); then
      last_output_change_at="$(date +%s)"
    fi

    if [[ "$last_output_change_at" != "0" ]]; then
      local now
      now="$(date +%s)"
      if (( now - last_output_change_at >= grace_sec )); then
        append_claude_adapter_runtime_event "$events_log" "post-completion-hang-recovered"
        _claude_signal_process_group TERM "$cmd_pid"
        sleep 2
        if _claude_process_alive "$cmd_pid"; then
          _claude_signal_process_group KILL "$cmd_pid"
        fi
        recovered_hang="true"
        break
      fi
    fi

    sleep 1
  done

  wait "$cmd_pid" 2>/dev/null
  status=$?
  set -e

  stdout_size="$(_claude_flush_file_delta "$stdout_spool" "$output_last_message" "$stdout_size")"
  stderr_size="$(_claude_flush_file_delta "$stderr_spool" "$stderr_log" "$stderr_size")"

  _claude_clear_active_provider_process
  rm -f "$stdout_spool" "$stderr_spool"

  if [[ "$recovered_hang" == "true" ]]; then
    return 0
  fi

  return "$status"
}

claude_run_test_port_initial() {
  local working_repo_dir="$1"
  local _input_diagram_path="$2"
  local _original_repo_path="$3"
  local events_log="$4"
  local stderr_log="$5"
  local output_last_message="$6"

  local prompt_file
  prompt_file="$(mktemp)"
  _claude_render_template "test_port_initial.md" > "$prompt_file"

  append_claude_adapter_event "$events_log" "test-port-initial" "0"
  local status
  set +e
  run_claude_prompt \
    "$working_repo_dir" \
    "$prompt_file" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e
  rm -f "$prompt_file"
  return "$status"
}

claude_run_test_port_iteration() {
  local working_repo_dir="$1"
  local _input_diagram_path="$2"
  local _original_repo_path="$3"
  local failure_summary_file="$4"
  local events_log="$5"
  local stderr_log="$6"
  local output_last_message="$7"
  local iteration="$8"

  local prompt_file
  prompt_file="$(mktemp)"
  _claude_render_template "test_port_iteration.md" \
    "FAILURE_SUMMARY=$(cat "$failure_summary_file" 2>/dev/null || true)" \
    > "$prompt_file"

  append_claude_adapter_event "$events_log" "test-port-iter" "$iteration"
  local status
  set +e
  run_claude_prompt \
    "$working_repo_dir" \
    "$prompt_file" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message"
  status=$?
  set -e
  rm -f "$prompt_file"
  return "$status"
}
