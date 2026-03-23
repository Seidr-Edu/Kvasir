#!/usr/bin/env bash
# tp_cli.sh - CLI parsing/validation for standalone test-port tool.

set -euo pipefail

tp_print_help() {
  cat <<'EOF'
Usage: test-port-run.sh --generated-repo PATH --original-repo PATH [options]
       kvasir-run.sh --generated-repo PATH --original-repo PATH [options]

Required:
  --generated-repo PATH       Generated repository root (read-only source; copied internally)
  --original-repo PATH        Original repository root (read-only source; copied internally)
  --adapter NAME              Adapter name (required)

Optional:
  --diagram PATH              Diagram file path (passed as read-only adapter context)
  --original-subdir PATH      Subdirectory under original repo to use for tests
  --generated-subdir PATH     Subdirectory under generated repo to run baseline/ported tests
  --run-id ID                 Explicit run id
  --run-dir PATH              Explicit run directory (default: .data/test-port/runs/<run-id>)
  --max-iter N                Adaptation iterations after initial pass (default: 5)
  --strict                    Non-zero exit if status is not passed
  --write-scope-policy NAME   Only "tests-only" is supported (default: tests-only)
  --write-scope-ignore-prefix PATH
                              Ignore repo-relative path prefix from write-scope monitoring.
                              Repeatable. Combined with TP_WRITE_SCOPE_IGNORE_PREFIXES.
  -h, --help                  Show this help
EOF
}

tp_configure_run_layout() {
  TP_LOG_DIR="${TP_RUN_DIR}/logs"
  TP_ARTIFACTS_DIR="${TP_RUN_DIR}/artifacts"
  TP_WORKSPACE_DIR="${TP_RUN_DIR}/workspace"
  TP_OUTPUT_DIR="${TP_RUN_DIR}/outputs"
  TP_SUMMARY_DIR="${TP_WORKSPACE_DIR}/summaries"
  TP_GUARDS_DIR="${TP_WORKSPACE_DIR}/write-guards"
  TP_MAVEN_LOCAL_REPO="${TP_WORKSPACE_DIR}/.m2/repository"
  TP_GRADLE_USER_HOME="${TP_WORKSPACE_DIR}/.gradle"
  TP_TMP_DIR="${TP_WORKSPACE_DIR}/tmp"

  TP_ORIGINAL_BASELINE_REPO="${TP_WORKSPACE_DIR}/original-baseline-repo"
  TP_GENERATED_BASELINE_REPO="${TP_WORKSPACE_DIR}/generated-baseline-repo"
  TP_PORTED_REPO="${TP_WORKSPACE_DIR}/ported-tests-repo"
  TP_PORTED_REPO_ARTIFACT="${TP_ARTIFACTS_DIR}/ported-tests-repo"
  TP_PORTED_REPO_ARTIFACT_EFFECTIVE="${TP_PORTED_REPO_ARTIFACT}"
  TP_PORTED_EFFECTIVE_REPO="${TP_PORTED_REPO}"
  TP_GENERATED_BASELINE_EFFECTIVE_REPO="${TP_GENERATED_BASELINE_REPO}"
  TP_ORIGINAL_TESTS_SNAPSHOT="${TP_WORKSPACE_DIR}/original-tests-snapshot"

  TP_BASELINE_ORIGINAL_LOG="${TP_LOG_DIR}/baseline-original-tests.log"
  TP_BASELINE_GENERATED_LOG="${TP_LOG_DIR}/baseline-generated-tests.log"
  TP_ADAPTER_EVENTS_LOG="${TP_LOG_DIR}/adapter-events.jsonl"
  TP_ADAPTER_STDERR_LOG="${TP_LOG_DIR}/adapter-stderr.log"
  TP_ADAPTER_LAST_MESSAGE="${TP_LOG_DIR}/adapter-last-message.md"

  TP_WRITE_SCOPE_FAILURE_PATHS_FILE="${TP_SUMMARY_DIR}/last-write-scope-failure.txt"
  TP_LAST_TEST_FAILURE_SUMMARY_FILE="${TP_SUMMARY_DIR}/last-test-failure.txt"
  TP_EVIDENCE_JSON_PATH="${TP_SUMMARY_DIR}/retention-evidence.json"
  TP_BEST_VALID_EVIDENCE_JSON_PATH="${TP_SUMMARY_DIR}/best-valid-retention-evidence.json"
  TP_WRITE_SCOPE_DIFF_FILE="${TP_GUARDS_DIR}/disallowed-change.diff"
  TP_WRITE_SCOPE_BEFORE_FILE="${TP_GUARDS_DIR}/ported-protected-before.sha256"
  TP_WRITE_SCOPE_AFTER_FILE="${TP_GUARDS_DIR}/ported-protected-after.sha256"
  TP_WRITE_SCOPE_CHANGE_SET_PATH="${TP_GUARDS_DIR}/ported-protected-change-set.tsv"
  TP_GENERATED_BEFORE_HASH_PATH="${TP_GUARDS_DIR}/new-repo-before.sha256"
  TP_GENERATED_AFTER_HASH_PATH="${TP_GUARDS_DIR}/new-repo-after.sha256"
  TP_BEST_VALID_PORTED_REPO="${TP_WORKSPACE_DIR}/best-valid-ported-tests-repo"
  TP_REMOVED_TESTS_MANIFEST_REL="./completion/proof/logs/test-port-removed-tests.tsv"
  TP_REMOVED_TESTS_MANIFEST_PATH="${TP_PORTED_REPO}/${TP_REMOVED_TESTS_MANIFEST_REL#./}"
  TP_POLICY_REJECTED_OVERRIDES_FILE="${TP_SUMMARY_DIR}/rejected-policy-overrides.txt"

  TP_JSON_PATH="${TP_OUTPUT_DIR}/test_port.json"
  TP_SUMMARY_MD_PATH="${TP_OUTPUT_DIR}/summary.md"
}

tp_is_forbidden_policy_override_prefix() {
  local prefix="$1"
  case "$prefix" in
    "./"|"./src/"|"./src/main/"|"./.github/"|"./scripts/"|"./docs/"|"./README.md/"|"./pom.xml/")
      return 0
      ;;
  esac

  case "$prefix" in
    *'*'*|*'?'*|*'['*|*']'*)
      return 0
      ;;
  esac

  local denied
  for denied in "${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[@]+"${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[@]}"}"; do
    case "$prefix" in
      "${denied}"*|"${denied}")
        return 0
        ;;
    esac
  done

  return 1
}

tp_resolve_write_scope_policy_classes() {
  TP_ALLOWED_MODEL_TEST_WRITES_GLOBS=(
    "./src/test/*"
    "./src/*Test*/*"
    "./test/*"
    "./tests/*"
  )

  TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES=(
    "./src/main/"
    "./scripts/"
    "./docs/"
    "./.github/"
  )

  local -a builtin_service_artifact_prefixes=(
    "./completion/proof/logs/"
    "./.mvn_repo/"
    "./.m2/"
    "./.gradle/"
    "./target/"
    "./build/"
  )

  local -a all_raw=("${builtin_service_artifact_prefixes[@]}")
  local -a env_raw=()
  local raw_env="${TP_WRITE_SCOPE_IGNORE_PREFIXES:-}"
  TP_POLICY_REJECTED_OVERRIDES=()

  if [[ -z "${TP_POLICY_REJECTED_OVERRIDES_FILE:-}" ]]; then
    local fallback_dir
    fallback_dir="${TP_SUMMARY_DIR:-${TP_RUN_DIR:-/tmp}}"
    TP_POLICY_REJECTED_OVERRIDES_FILE="${fallback_dir}/rejected-policy-overrides.txt"
  fi

  mkdir -p "$(dirname "$TP_POLICY_REJECTED_OVERRIDES_FILE")"
  : > "$TP_POLICY_REJECTED_OVERRIDES_FILE"

  if [[ -n "$raw_env" ]]; then
    if [[ "$raw_env" == :* || "$raw_env" == *: || "$raw_env" == *"::"* ]]; then
      tp_err "TP_WRITE_SCOPE_IGNORE_PREFIXES contains empty entries"
      return 1
    fi
    local IFS=':'
    read -r -a env_raw <<< "$raw_env"
    all_raw+=("${env_raw[@]}")
  fi
  all_raw+=("${TP_WRITE_SCOPE_IGNORE_PREFIXES_CLI[@]+"${TP_WRITE_SCOPE_IGNORE_PREFIXES_CLI[@]}"}")

  TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES=()
  local seen='|'
  local raw
  local normalized
  for raw in "${all_raw[@]}"; do
    normalized="$(tp_normalize_repo_prefix "$raw")" || {
      tp_err "invalid write-scope ignore prefix: '$raw'"
      return 1
    }

    if tp_is_forbidden_policy_override_prefix "$normalized"; then
      TP_POLICY_REJECTED_OVERRIDES+=("$normalized")
      printf '%s\n' "$normalized" >> "$TP_POLICY_REJECTED_OVERRIDES_FILE"
      continue
    fi

    case "$seen" in
      *"|${normalized}|"*) continue ;;
    esac
    seen="${seen}${normalized}|"
    TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES+=("$normalized")
  done

  TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES_CSV="$(IFS=:; printf '%s' "${TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES[*]-}")"
  TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES_CSV="$(IFS=:; printf '%s' "${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES[*]-}")"
  TP_POLICY_REJECTED_OVERRIDES_CSV="$(IFS=:; printf '%s' "${TP_POLICY_REJECTED_OVERRIDES[*]-}")"

  # Compatibility for existing report/test consumers.
  TP_WRITE_SCOPE_IGNORED_PREFIXES=("${TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES[@]+"${TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES[@]}"}")
  TP_WRITE_SCOPE_IGNORED_PREFIXES_CSV="$TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES_CSV"
}

tp_parse_args() {
  TP_GENERATED_REPO=""
  TP_ORIGINAL_REPO=""
  TP_DIAGRAM_PATH=""
  TP_ORIGINAL_SUBDIR=""
  TP_GENERATED_SUBDIR=""
  TP_RUN_ID=""
  TP_RUN_DIR=""
  TP_ADAPTER=""
  TP_MAX_ITER="5"
  TP_STRICT=false
  TP_WRITE_SCOPE_POLICY="tests-only"
  TP_WRITE_SCOPE_IGNORE_PREFIXES_CLI=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --generated-repo) TP_GENERATED_REPO="${2:-}"; shift 2 ;;
      --original-repo) TP_ORIGINAL_REPO="${2:-}"; shift 2 ;;
      --diagram) TP_DIAGRAM_PATH="${2:-}"; shift 2 ;;
      --original-subdir) TP_ORIGINAL_SUBDIR="${2:-}"; shift 2 ;;
      --generated-subdir) TP_GENERATED_SUBDIR="${2:-}"; shift 2 ;;
      --run-id) TP_RUN_ID="${2:-}"; shift 2 ;;
      --run-dir) TP_RUN_DIR="${2:-}"; shift 2 ;;
      --adapter) TP_ADAPTER="${2:-}"; shift 2 ;;
      --max-iter) TP_MAX_ITER="${2:-}"; shift 2 ;;
      --write-scope-policy) TP_WRITE_SCOPE_POLICY="${2:-}"; shift 2 ;;
      --write-scope-ignore-prefix)
        TP_WRITE_SCOPE_IGNORE_PREFIXES_CLI+=("${2:-}")
        shift 2
        ;;
      --strict) TP_STRICT=true; shift ;;
      -h|--help) tp_print_help; exit 0 ;;
      *)
        tp_fail "unknown argument: $1"
        ;;
    esac
  done
}

tp_validate_and_finalize_args() {
  [[ -n "$TP_GENERATED_REPO" ]] || tp_fail "--generated-repo is required"
  [[ -n "$TP_ORIGINAL_REPO" ]] || tp_fail "--original-repo is required"
  [[ -n "$TP_ADAPTER" ]] || tp_fail "--adapter is required"
  [[ "$TP_MAX_ITER" =~ ^[0-9]+$ ]] || tp_fail "--max-iter must be non-negative integer"
  [[ "$TP_WRITE_SCOPE_POLICY" == "tests-only" ]] || tp_fail "--write-scope-policy must be tests-only"
  tp_resolve_write_scope_policy_classes || return 1

  TP_GENERATED_REPO="$(tp_abs_path "$TP_GENERATED_REPO")"
  TP_ORIGINAL_REPO="$(tp_abs_path "$TP_ORIGINAL_REPO")"

  [[ -d "$TP_ORIGINAL_REPO" ]] || tp_fail "original repo not found: $TP_ORIGINAL_REPO"

  if [[ -n "$TP_DIAGRAM_PATH" ]]; then
    TP_DIAGRAM_PATH="$(tp_abs_path "$TP_DIAGRAM_PATH")"
    [[ -f "$TP_DIAGRAM_PATH" ]] || tp_fail "diagram not found: $TP_DIAGRAM_PATH"
  fi

  TP_ORIGINAL_EFFECTIVE_PATH="$TP_ORIGINAL_REPO"
  if [[ -n "$TP_ORIGINAL_SUBDIR" ]]; then
    TP_ORIGINAL_EFFECTIVE_PATH="${TP_ORIGINAL_REPO}/${TP_ORIGINAL_SUBDIR}"
    [[ -d "$TP_ORIGINAL_EFFECTIVE_PATH" ]] || tp_fail "--original-subdir not found: $TP_ORIGINAL_SUBDIR"
  fi

  TP_GENERATED_EFFECTIVE_SUBDIR="${TP_GENERATED_SUBDIR}"
  TP_GENERATED_EFFECTIVE_PATH="$TP_GENERATED_REPO"
  if [[ -n "$TP_GENERATED_SUBDIR" ]]; then
    TP_GENERATED_EFFECTIVE_PATH="${TP_GENERATED_REPO}/${TP_GENERATED_SUBDIR}"
    [[ -d "$TP_GENERATED_EFFECTIVE_PATH" ]] || tp_fail "--generated-subdir not found: $TP_GENERATED_SUBDIR"
  fi

  if [[ -z "$TP_RUN_ID" ]]; then
    local gen_component
    gen_component="$(tp_sanitize_id_component "$TP_GENERATED_REPO")"
    TP_RUN_ID="$(tp_timestamp_compact_utc)__${gen_component}__test-port"
  fi

  if [[ -z "$TP_RUN_DIR" ]]; then
    local runs_root
    runs_root="${TEST_PORT_RUNS_DIR:-${REPO_ROOT}/.data/test-port/runs}"
    TP_RUN_DIR="${runs_root}/${TP_RUN_ID}"
  fi
  TP_RUN_DIR="$(tp_abs_path "$TP_RUN_DIR")"
  tp_configure_run_layout
}
