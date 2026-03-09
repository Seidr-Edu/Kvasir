#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/service_testlib.sh"

case_container_contract_emits_report() {
  local tmp original_repo generated_repo run_dir image_tag build_log run_log provider_mount path_env rc
  tmp="$(tpt_mktemp_dir)"
  build_log="${tmp}/docker-build.log"
  run_log="${tmp}/docker-run.log"

  if ! command -v docker >/dev/null 2>&1; then
    tpt_log "skipping container integration test: docker not installed"
    return 0
  fi
  if ! docker version >/dev/null 2>&1; then
    tpt_log "skipping container integration test: docker daemon unavailable"
    return 0
  fi
  if ! docker image inspect ubuntu:24.04 >/dev/null 2>&1; then
    tpt_log "skipping container integration test: ubuntu:24.04 base image not cached locally"
    return 0
  fi

  setup_fake_tools "$tmp"
  export TPT_ADAPTER_SCENARIO="ignored-writes"
  export TPT_CODEX_CALL_COUNT_FILE="/run/logs/codex-call-count.txt"
  export TPT_CLAUDE_CALL_COUNT_FILE="/run/logs/claude-call-count.txt"
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$tmp")

  run_dir="${tmp}/run"
  mkdir -p "$run_dir"
  chmod 0777 "$run_dir"
  chmod -R a+rX "$original_repo" "$generated_repo" "${tmp}/bin"

  image_tag="kvasir-test:$(date +%s)"
  if ! docker build -t "$image_tag" "$TOOL_ROOT" >"$build_log" 2>&1; then
    cat "$build_log" >&2
    return 1
  fi
  trap 'docker image rm -f "$image_tag" >/dev/null 2>&1 || true' RETURN

  provider_mount="/opt/provider/bin"
  path_env="${provider_mount}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

  set +e
  docker run --rm \
    -e PATH="$path_env" \
    -e CODEX_HOME=/run/codex-home \
    -e KVASIR_ADAPTER=codex \
    -e TPT_ADAPTER_SCENARIO="$TPT_ADAPTER_SCENARIO" \
    -e TPT_CODEX_CALL_COUNT_FILE="$TPT_CODEX_CALL_COUNT_FILE" \
    -e TPT_CLAUDE_CALL_COUNT_FILE="$TPT_CLAUDE_CALL_COUNT_FILE" \
    -v "${original_repo}:/input/original-repo:ro" \
    -v "${generated_repo}:/input/generated-repo:ro" \
    -v "${run_dir}:/run" \
    -v "${tmp}/bin:${provider_mount}:ro" \
    "$image_tag" >"$run_log" 2>&1
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    cat "$run_log" >&2
    return 1
  fi

  tpt_assert_file_exists "${run_dir}/outputs/test_port.json" "container contract must emit test_port.json"
}

tpt_run_case "container contract emits json report" case_container_contract_emits_report

tpt_finish_suite
