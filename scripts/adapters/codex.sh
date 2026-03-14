#!/usr/bin/env bash
set -euo pipefail

timestamp_utc_adapter() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

append_adapter_event() {
  local events_log="$1"
  local phase="$2"
  local iteration="$3"
  local run_time
  run_time="$(timestamp_utc_adapter)"

  printf '{"type":"test-port.adapter","adapter":"codex","phase":"%s","iteration":"%s","time":"%s"}\n' \
    "$phase" "$iteration" "$run_time" >> "$events_log"
}

_codex_prompts_dir() {
  echo "${ROOT_DIR}/prompts"
}

_codex_render_template() {
  local template_name="$1"
  shift
  local prompts_dir
  prompts_dir="$(_codex_prompts_dir)"
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

codex_check_prereqs() {
  if ! command -v codex >/dev/null 2>&1; then
    echo "codex CLI not found. Install Codex CLI and ensure 'codex' is on PATH." >&2
    return 1
  fi

  local codex_home="${CODEX_HOME:-${HOME}/.codex}"
  local session_dir="${codex_home}/sessions"
  if [[ -e "$codex_home" && ! -w "$codex_home" ]]; then
    cat >&2 <<PREREQ_EOF
codex CLI home is not writable: ${codex_home}
Fix ownership/permissions, for example:
  sudo chown -R \$(whoami) "${codex_home}"
PREREQ_EOF
    return 1
  fi
  if [[ -e "$session_dir" && ! -w "$session_dir" ]]; then
    cat >&2 <<PREREQ_EOF
codex CLI session directory is not writable: ${session_dir}
Fix ownership/permissions, for example:
  sudo chown -R \$(whoami) "${codex_home}"
PREREQ_EOF
    return 1
  fi

  if ! codex login status >/dev/null 2>&1; then
    cat >&2 <<'PREREQ_EOF'
codex CLI is not authenticated.
Run one of:
  codex login
  printenv OPENAI_API_KEY | codex login --with-api-key
PREREQ_EOF
    return 1
  fi

  local prompts_dir
  prompts_dir="$(_codex_prompts_dir)"
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

run_codex_prompt() {
  local working_repo_dir="$1"
  local input_diagram_path="$2"
  local prompt_file="$3"
  local events_log="$4"
  local stderr_log="$5"
  local output_last_message="$6"
  shift 6
  local -a extra_args=("$@")

  local input_dir
  input_dir="$(cd "$(dirname "$input_diagram_path")" && pwd)"

  set +e
  (
    cd "$working_repo_dir"
    # Service containers are already isolated by Docker. Bypass Codex's inner
    # sandbox so it can operate on bind-mounted workspaces reliably, including
    # Docker Desktop's fakeowner mounts on macOS.
    local -a cmd=(
      codex exec
      --skip-git-repo-check
      --dangerously-bypass-approvals-and-sandbox
      --cd "$working_repo_dir"
      --add-dir "$input_dir"
    )
    if [[ ${#extra_args[@]} -gt 0 ]]; then
      cmd+=("${extra_args[@]}")
    fi
    cmd+=(
      --json
      --output-last-message "$output_last_message"
      -
    )
    "${cmd[@]}" < "$prompt_file"
  ) >> "$events_log" 2>> "$stderr_log"
  local status=$?
  set -e

  return "$status"
}

codex_run_test_port_initial() {
  local working_repo_dir="$1"
  local input_diagram_path="$2"
  local original_repo_path="$3"
  local events_log="$4"
  local stderr_log="$5"
  local output_last_message="$6"

  local prompt_file
  prompt_file="$(mktemp)"
  _codex_render_template "test_port_initial.md" > "$prompt_file"

  append_adapter_event "$events_log" "test-port-initial" "0"
  local status
  set +e
  run_codex_prompt \
    "$working_repo_dir" \
    "$input_diagram_path" \
    "$prompt_file" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message" \
    --add-dir "$original_repo_path"
  status=$?
  set -e
  rm -f "$prompt_file"
  return "$status"
}

codex_run_test_port_iteration() {
  local working_repo_dir="$1"
  local input_diagram_path="$2"
  local original_repo_path="$3"
  local failure_summary_file="$4"
  local events_log="$5"
  local stderr_log="$6"
  local output_last_message="$7"
  local iteration="$8"

  local prompt_file
  prompt_file="$(mktemp)"
  _codex_render_template "test_port_iteration.md" \
    "FAILURE_SUMMARY=$(cat "$failure_summary_file" 2>/dev/null || true)" \
    > "$prompt_file"

  append_adapter_event "$events_log" "test-port-iter" "$iteration"
  local status
  set +e
  run_codex_prompt \
    "$working_repo_dir" \
    "$input_diagram_path" \
    "$prompt_file" \
    "$events_log" \
    "$stderr_log" \
    "$output_last_message" \
    --add-dir "$original_repo_path"
  status=$?
  set -e
  rm -f "$prompt_file"
  return "$status"
}
