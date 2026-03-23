#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/service_testlib.sh"

case_container_contract_emits_report() {
  local tmp original_repo generated_repo provider_bin provider_seed run_dir image_tag build_log run_log jdk_log rc
  tmp="$(tpt_mktemp_dir)"
  build_log="${tmp}/docker-build.log"
  run_log="${tmp}/docker-run.log"
  jdk_log="${tmp}/docker-jdks.log"

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
  IFS=$'\t' read -r provider_bin provider_seed < <(prepare_fake_provider_mounts "$tmp")

  run_dir="${tmp}/run"
  mkdir -p "$run_dir"
  chmod 0777 "$run_dir"
  chmod -R a+rX "$original_repo" "$generated_repo" "$provider_bin" "$provider_seed"

  image_tag="kvasir-test:$(date +%s)"
  if ! docker build -t "$image_tag" "$TOOL_ROOT" >"$build_log" 2>&1; then
    cat "$build_log" >&2
    return 1
  fi
  trap 'docker image rm -f "$image_tag" >/dev/null 2>&1 || true' RETURN

  set +e
  docker run --rm \
    -e KVASIR_ADAPTER=codex \
    -e TPT_ADAPTER_SCENARIO="$TPT_ADAPTER_SCENARIO" \
    -e TPT_CODEX_CALL_COUNT_FILE="$TPT_CODEX_CALL_COUNT_FILE" \
    -e TPT_CLAUDE_CALL_COUNT_FILE="$TPT_CLAUDE_CALL_COUNT_FILE" \
    -e TPT_EXPECT_CODEX_HOME_PREFIX="/run/provider-state/codex-home" \
    -v "${original_repo}:/input/original-repo:ro" \
    -v "${generated_repo}:/input/generated-repo:ro" \
    -v "${run_dir}:/run" \
    -v "${provider_bin}:/opt/provider/bin:ro" \
    -v "${provider_seed}:/opt/provider-seed/codex-home:ro" \
    "$image_tag" >"$run_log" 2>&1
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    cat "$run_log" >&2
    return 1
  fi

  if ! docker run --rm --entrypoint bash "$image_tag" -lc 'source /app/scripts/lib/tp_build_env.sh && tp_build_env_list_available_jdks' >"$jdk_log" 2>&1; then
    cat "$jdk_log" >&2
    return 1
  fi

  tpt_assert_file_exists "${run_dir}/outputs/test_port.json" "container contract must emit test_port.json"
  tpt_assert_file_exists "${run_dir}/provider-state/codex-home/sessions/auth-state.json" "container contract should copy provider seed into runtime CODEX_HOME"
  tpt_assert_file_contains "$jdk_log" "25" "container image should include JDK 25"
  tpt_assert_file_contains "$jdk_log" "21" "container image should include JDK 21"
  tpt_assert_file_contains "$jdk_log" "17" "container image should include JDK 17"
  tpt_assert_file_contains "$jdk_log" "11" "container image should include JDK 11"
  tpt_assert_file_contains "$jdk_log" "8" "container image should include JDK 8"
}

tpt_run_case "container contract emits json report" case_container_contract_emits_report

tpt_finish_suite
