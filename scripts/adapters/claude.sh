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

  local response_file
  response_file="$(mktemp)"

  set +e
  (
    cd "$working_repo_dir"
    claude --dangerously-skip-permissions --print < "$prompt_file"
  ) > "$response_file" 2>> "$stderr_log"
  local status=$?
  set -e

  cp "$response_file" "$output_last_message"
  rm -f "$response_file"

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
