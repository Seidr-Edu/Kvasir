#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KVASIR_SERVICE_PROVIDER_BIN="${KVASIR_SERVICE_PROVIDER_BIN:-/opt/provider/bin}"
KVASIR_SERVICE_PROVIDER_SEED="${KVASIR_SERVICE_PROVIDER_SEED:-/opt/provider-seed/codex-home}"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/test-port-run.sh"

kvasir_service_print_help() {
  cat <<'EOF'
Usage: kvasir-service.sh

Container contract:
  Read-only:
    /input/original-repo
    /input/generated-repo
    /input/model (optional)
  Writable:
    /run

Environment:
  KVASIR_MANIFEST                         Optional Kvasir-specific YAML manifest path
                                          (default: /run/config/manifest.yaml when present)
  KVASIR_ORIGINAL_REPO                   Default: /input/original-repo
  KVASIR_GENERATED_REPO                  Default: /input/generated-repo
  KVASIR_DIAGRAM                         Default: /input/model/diagram.puml when present
  KVASIR_RUN_DIR                         Default: /run
  KVASIR_ADAPTER                         Required unless supplied by manifest
  KVASIR_ORIGINAL_SUBDIR                 Optional
  KVASIR_GENERATED_SUBDIR                Optional
  KVASIR_MAX_ITER                        Optional non-negative integer
  KVASIR_WRITE_SCOPE_IGNORE_PREFIXES     Optional colon-separated repo-relative prefixes
  KVASIR_STRICT_WRITE_SCOPE_OVERRIDES    Optional (default: true). When true, reject external write-scope overrides.
  KVASIR_ALLOW_WRITE_SCOPE_OVERRIDES     Optional (default: false). Set true to allow overrides when strict mode is enabled.

Provider mounts (for adapter=codex):
  Read-only: /opt/provider/bin
  Read-only: /opt/provider-seed/codex-home
  Writable:  /run/provider-state/codex-home (created by the service)

Manifest v1 fields:
  version (required, must be 1)
  run_id
  adapter
  original_subdir
  generated_subdir
  diagram_relpath
  max_iter
  write_scope_ignore_prefixes[]
EOF
}

kvasir_service_normalize_rel_path() {
  local raw="$1"
  [[ -n "$raw" ]] || return 1
  [[ "$raw" != /* ]] || return 1
  [[ "$raw" != *:* ]] || return 1

  while [[ "$raw" == ./* ]]; do
    raw="${raw#./}"
  done

  raw="$(printf '%s' "$raw" | sed -E 's#/+#/#g')"

  while [[ "$raw" == */ ]]; do
    raw="${raw%/}"
  done

  [[ -n "$raw" ]] || return 1
  case "$raw" in
    .|..|../*|*/..|*/../*|./*|*/.|*/./*)
      return 1
      ;;
  esac

  printf '%s\n' "$raw"
}

kvasir_service_load_manifest() {
  local manifest_path="$1"
  python3 - <<'PY' "$manifest_path"
import re
import shlex
import sys

path = sys.argv[1]
allowed = {
    "version",
    "run_id",
    "adapter",
    "original_subdir",
    "generated_subdir",
    "diagram_relpath",
    "max_iter",
    "write_scope_ignore_prefixes",
}


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def strip_inline_comment(value):
    return re.split(r"\s+#", value, maxsplit=1)[0].rstrip()


def parse_scalar(raw_value, lineno):
    value = raw_value.strip()
    if not value:
        return None

    if value.startswith(("{", "[", "|", ">")) or value == "-":
        fail(f"invalid manifest YAML: unsupported value syntax on line {lineno}")

    if value[0] == '"':
        match = re.match(r'^"((?:[^"\\]|\\.)*)"(?:\s+#.*)?$', value)
        if not match:
            fail(f"invalid manifest YAML: malformed double-quoted string on line {lineno}")
        return bytes(match.group(1), "utf-8").decode("unicode_escape")

    if value[0] == "'":
        match = re.match(r"^'((?:[^']|'')*)'(?:\s+#.*)?$", value)
        if not match:
            fail(f"invalid manifest YAML: malformed single-quoted string on line {lineno}")
        return match.group(1).replace("''", "'")

    value = strip_inline_comment(value)
    if value.startswith(("{", "[", "|", ">", "- ")):
        fail(f"invalid manifest YAML: unsupported value syntax on line {lineno}")

    if value in ("null", "Null", "NULL", "~"):
        return None

    if re.fullmatch(r"-?\d+", value):
        return int(value)

    return value

try:
    with open(path, "r", encoding="utf-8") as f:
        raw_lines = f.read().splitlines()
except FileNotFoundError:
    fail(f"missing manifest: {path}")
except Exception as exc:
    fail(f"invalid manifest YAML: {exc}")

line_re = re.compile(r"^([A-Za-z0-9_]+)\s*:\s*(.*?)\s*$")
item_re = re.compile(r"^(\s*)-\s*(.*?)\s*$")

data = {}
list_key = None
list_indent = -1

for lineno, raw_line in enumerate(raw_lines, start=1):
    stripped = raw_line.strip()

    if list_key is not None:
        if not stripped or stripped.startswith("#"):
            continue
        item_match = item_re.match(raw_line)
        if item_match and len(item_match.group(1)) > list_indent:
            item = parse_scalar(item_match.group(2), lineno)
            if item is None or not isinstance(item, str):
                fail(f"manifest field {list_key!r} must contain only strings")
            data[list_key].append(item)
            continue
        list_key = None
        list_indent = -1

    if not stripped or stripped.startswith("#"):
        continue

    if raw_line[:1].isspace():
        fail(f"invalid manifest YAML: unsupported indentation on line {lineno}")

    match = line_re.match(raw_line)
    if not match:
        fail(f"invalid manifest YAML: unsupported syntax on line {lineno}")

    key, raw_value = match.groups()
    if key in data:
        fail(f"duplicate manifest key: {key}")
    if key not in allowed:
        fail(f"unknown manifest key: {key}")

    if key == "write_scope_ignore_prefixes":
        value = strip_inline_comment(raw_value.strip())
        if not value:
            data[key] = []
            list_key = key
            list_indent = 0
            continue
        if re.fullmatch(r"\[\s*\]", value):
            data[key] = []
            continue
        fail("manifest field 'write_scope_ignore_prefixes' must be an array of strings")

    data[key] = parse_scalar(raw_value, lineno)

version = data.get("version")
if version != 1:
    fail(f"unsupported manifest version: {version!r}")


def opt_str(name):
    value = data.get(name)
    if value is None:
        return ""
    if not isinstance(value, str):
        fail(f"manifest field {name!r} must be a string")
    return value


def opt_int(name):
    value = data.get(name)
    if value is None:
        return ""
    if not isinstance(value, int):
        fail(f"manifest field {name!r} must be an integer")
    return str(value)


def opt_str_list(name):
    value = data.get(name)
    if value is None:
        return ""
    if not isinstance(value, list) or any(not isinstance(item, str) for item in value):
        fail(f"manifest field {name!r} must be an array of strings")
    return ":".join(value)

assignments = {
    "KVASIR_SERVICE_MANIFEST_RUN_ID": opt_str("run_id"),
    "KVASIR_SERVICE_MANIFEST_ADAPTER": opt_str("adapter"),
    "KVASIR_SERVICE_MANIFEST_ORIGINAL_SUBDIR": opt_str("original_subdir"),
    "KVASIR_SERVICE_MANIFEST_GENERATED_SUBDIR": opt_str("generated_subdir"),
    "KVASIR_SERVICE_MANIFEST_DIAGRAM_RELPATH": opt_str("diagram_relpath"),
    "KVASIR_SERVICE_MANIFEST_MAX_ITER": opt_int("max_iter"),
    "KVASIR_SERVICE_MANIFEST_WRITE_SCOPE_IGNORE_PREFIXES": opt_str_list("write_scope_ignore_prefixes"),
}

for key, value in assignments.items():
    print(f"{key}={shlex.quote(value)}")
PY
}

kvasir_service_prepare_output_dir() {
  local probe
  mkdir -p "$TP_OUTPUT_DIR" >/dev/null 2>&1 || return 1
  probe="${TP_OUTPUT_DIR}/.kvasir-output-write-test.$$"
  : > "$probe" >/dev/null 2>&1 || return 1
  rm -f "$probe"
}

kvasir_service_prepare_runtime_dirs() {
  local dir
  local probe
  mkdir -p "$TP_LOG_DIR" "$TP_WORKSPACE_DIR" "$TP_SUMMARY_DIR" "$TP_GUARDS_DIR" "$TP_TMP_DIR" >/dev/null 2>&1 || return 1

  for dir in "$TP_LOG_DIR" "$TP_WORKSPACE_DIR" "$TP_SUMMARY_DIR" "$TP_GUARDS_DIR" "$TP_TMP_DIR"; do
    probe="${dir}/.kvasir-write-test.$$"
    : > "$probe" >/dev/null 2>&1 || return 1
    rm -f "$probe"
  done
}

kvasir_service_bootstrap_provider() {
  local adapter="$1"

  case "$adapter" in
    codex)
      local runtime_dir="${TP_RUN_DIR}/provider-state/codex-home"
      if [[ -d "$KVASIR_SERVICE_PROVIDER_BIN" || -d "$KVASIR_SERVICE_PROVIDER_SEED" ]]; then
        mkdir -p "${runtime_dir}/sessions" >/dev/null 2>&1 || return 1
        if [[ -d "$KVASIR_SERVICE_PROVIDER_SEED" ]]; then
          # Avoid preserving source ownership so read-only host auth mounts still
          # copy into the writable runtime home under the container user.
          cp -R "${KVASIR_SERVICE_PROVIDER_SEED}/." "${runtime_dir}/" >/dev/null 2>&1 || return 1
        fi
        export CODEX_HOME="$runtime_dir"
      fi
      if [[ -d "$KVASIR_SERVICE_PROVIDER_BIN" ]]; then
        export PATH="${KVASIR_SERVICE_PROVIDER_BIN}:${PATH}"
      fi
      ;;
  esac
}

kvasir_service_apply_failure() {
  local reason="$1"
  local status_detail="$2"

  TP_STATUS="skipped"
  TP_REASON="$reason"
  TP_STATUS_DETAIL="$status_detail"
  TP_FAILURE_CLASS=""
  TP_FAILURE_CLASS_LEGACY=""
}

kvasir_service_write_reports_or_fail() {
  tp_compute_behavioral_verdict
  tp_write_reports
}

kvasir_service_exit_code_for_result() {
  case "${TP_REASON:-}" in
    invalid-service-manifest|invalid-service-config|missing-original-repo|missing-generated-repo|run-dir-not-writable|unsupported-adapter|adapter-prereqs-failed|missing-rsync|workspace-prepare-failed|internal-report-inconsistency)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

kvasir_service_main() {
  if [[ $# -gt 0 ]]; then
    case "$1" in
      -h|--help)
        kvasir_service_print_help
        return 0
        ;;
      *)
        printf 'kvasir-service.sh does not accept positional arguments; use env vars or KVASIR_MANIFEST.\n' >&2
        return 1
        ;;
    esac
  fi

  local manifest_path="${KVASIR_MANIFEST:-}"
  local resolved_run_dir="${KVASIR_RUN_DIR:-/run}"
  local default_diagram=""
  local manifest_run_id=""
  local manifest_adapter=""
  local manifest_original_subdir=""
  local manifest_generated_subdir=""
  local manifest_diagram_relpath=""
  local manifest_max_iter=""
  local manifest_write_scope_prefixes=""
  local resolved_original_repo="/input/original-repo"
  local resolved_generated_repo="/input/generated-repo"
  local resolved_adapter=""
  local resolved_original_subdir=""
  local resolved_generated_subdir=""
  local resolved_diagram=""
  local resolved_max_iter="5"
  local resolved_write_scope_prefixes=""
  local strict_write_scope_overrides="${KVASIR_STRICT_WRITE_SCOPE_OVERRIDES:-true}"
  local allow_write_scope_overrides="${KVASIR_ALLOW_WRITE_SCOPE_OVERRIDES:-false}"
  local service_exit_code=0

  TP_RUN_ID="$(tp_timestamp_compact_utc)__service__test-port"
  TP_RUN_DIR="$(tp_abs_path "$resolved_run_dir")"
  tp_configure_run_layout

  TP_GENERATED_REPO=""
  TP_ORIGINAL_REPO=""
  TP_DIAGRAM_PATH=""
  TP_ORIGINAL_SUBDIR=""
  TP_GENERATED_SUBDIR=""
  TP_GENERATED_EFFECTIVE_SUBDIR=""
  TP_ORIGINAL_EFFECTIVE_PATH=""
  TP_GENERATED_EFFECTIVE_PATH=""
  TP_ADAPTER=""
  TP_MAX_ITER="5"
  TP_STRICT=false
  TP_WRITE_SCOPE_POLICY="tests-only"
  TP_WRITE_SCOPE_IGNORE_PREFIXES_CLI=()
  TP_WRITE_SCOPE_IGNORE_PREFIXES=""
  TP_WRITE_SCOPE_IGNORED_PREFIXES=()
  TP_WRITE_SCOPE_IGNORED_PREFIXES_CSV=""
  TP_ENFORCE_WORKSPACE_WRITE_POLICY="true"
  TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES=()
  TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES_CSV=""
  TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES=()
  TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES_CSV=""
  TP_POLICY_REJECTED_OVERRIDES=()
  TP_POLICY_REJECTED_OVERRIDES_CSV=""

  tp_init_result_state

  if ! kvasir_service_prepare_output_dir; then
    tp_err "service outputs dir is not writable: ${TP_OUTPUT_DIR}"
    return 1
  fi

  if [[ -z "$manifest_path" ]]; then
    local default_manifest_path="${TP_RUN_DIR}/config/manifest.yaml"
    if [[ -f "$default_manifest_path" ]]; then
      manifest_path="$default_manifest_path"
    fi
  fi

  if [[ -f "/input/model/diagram.puml" ]]; then
    default_diagram="/input/model/diagram.puml"
  fi

  if [[ -n "$manifest_path" ]]; then
    local manifest_assignments
    manifest_path="$(tp_abs_path "$manifest_path")"
    if ! manifest_assignments="$(kvasir_service_load_manifest "$manifest_path")"; then
      kvasir_service_apply_failure "invalid-service-manifest" "invalid_manifest"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    fi
    eval "$manifest_assignments"
    manifest_run_id="${KVASIR_SERVICE_MANIFEST_RUN_ID:-}"
    manifest_adapter="${KVASIR_SERVICE_MANIFEST_ADAPTER:-}"
    manifest_original_subdir="${KVASIR_SERVICE_MANIFEST_ORIGINAL_SUBDIR:-}"
    manifest_generated_subdir="${KVASIR_SERVICE_MANIFEST_GENERATED_SUBDIR:-}"
    manifest_diagram_relpath="${KVASIR_SERVICE_MANIFEST_DIAGRAM_RELPATH:-}"
    manifest_max_iter="${KVASIR_SERVICE_MANIFEST_MAX_ITER:-}"
    manifest_write_scope_prefixes="${KVASIR_SERVICE_MANIFEST_WRITE_SCOPE_IGNORE_PREFIXES:-}"
  fi

  if [[ -n "$manifest_run_id" ]]; then
    TP_RUN_ID="$manifest_run_id"
  fi

  if [[ -n "$manifest_adapter" ]]; then
    resolved_adapter="$manifest_adapter"
  fi
  if [[ -n "$manifest_original_subdir" ]]; then
    resolved_original_subdir="$manifest_original_subdir"
  fi
  if [[ -n "$manifest_generated_subdir" ]]; then
    resolved_generated_subdir="$manifest_generated_subdir"
  fi
  if [[ -n "$manifest_max_iter" ]]; then
    resolved_max_iter="$manifest_max_iter"
  fi
  if [[ -n "$manifest_write_scope_prefixes" ]]; then
    resolved_write_scope_prefixes="$manifest_write_scope_prefixes"
  fi
  if [[ -n "$manifest_diagram_relpath" ]]; then
    local normalized_diagram_relpath
    normalized_diagram_relpath="$(kvasir_service_normalize_rel_path "$manifest_diagram_relpath")" || {
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    }
    resolved_diagram="/input/model/${normalized_diagram_relpath}"
  else
    resolved_diagram="$default_diagram"
  fi

  if [[ "${KVASIR_ORIGINAL_REPO+x}" == "x" ]]; then
    resolved_original_repo="$KVASIR_ORIGINAL_REPO"
  fi
  if [[ "${KVASIR_GENERATED_REPO+x}" == "x" ]]; then
    resolved_generated_repo="$KVASIR_GENERATED_REPO"
  fi
  if [[ "${KVASIR_ADAPTER+x}" == "x" ]]; then
    resolved_adapter="$KVASIR_ADAPTER"
  fi
  if [[ "${KVASIR_ORIGINAL_SUBDIR+x}" == "x" ]]; then
    resolved_original_subdir="$KVASIR_ORIGINAL_SUBDIR"
  fi
  if [[ "${KVASIR_GENERATED_SUBDIR+x}" == "x" ]]; then
    resolved_generated_subdir="$KVASIR_GENERATED_SUBDIR"
  fi
  if [[ "${KVASIR_DIAGRAM+x}" == "x" ]]; then
    resolved_diagram="$KVASIR_DIAGRAM"
  fi
  if [[ "${KVASIR_MAX_ITER+x}" == "x" ]]; then
    resolved_max_iter="$KVASIR_MAX_ITER"
  fi
  if [[ "${KVASIR_WRITE_SCOPE_IGNORE_PREFIXES+x}" == "x" ]]; then
    resolved_write_scope_prefixes="$KVASIR_WRITE_SCOPE_IGNORE_PREFIXES"
  fi

  case "$strict_write_scope_overrides" in
    true|false) ;;
    *)
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
      ;;
  esac

  case "$allow_write_scope_overrides" in
    true|false) ;;
    *)
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
      ;;
  esac

  if [[ "$strict_write_scope_overrides" == "true" && "$allow_write_scope_overrides" != "true" ]]; then
    if [[ -n "$manifest_write_scope_prefixes" || "${KVASIR_WRITE_SCOPE_IGNORE_PREFIXES+x}" == "x" ]]; then
      TP_POLICY_REJECTED_OVERRIDES_CSV="${manifest_write_scope_prefixes}:${KVASIR_WRITE_SCOPE_IGNORE_PREFIXES:-}"
      kvasir_service_apply_failure "invalid-service-config" "policy_override_rejected"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    fi
  fi

  if [[ -z "$resolved_original_repo" || -z "$resolved_generated_repo" || -z "$resolved_adapter" ]]; then
    kvasir_service_apply_failure "invalid-service-config" "invalid_config"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi
  if [[ ! "$resolved_max_iter" =~ ^[0-9]+$ ]]; then
    kvasir_service_apply_failure "invalid-service-config" "invalid_config"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi
  if [[ -n "$resolved_original_subdir" ]]; then
    resolved_original_subdir="$(kvasir_service_normalize_rel_path "$resolved_original_subdir")" || {
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    }
  fi
  if [[ -n "$resolved_generated_subdir" ]]; then
    resolved_generated_subdir="$(kvasir_service_normalize_rel_path "$resolved_generated_subdir")" || {
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    }
  fi

  TP_ORIGINAL_REPO="$(tp_abs_path "$resolved_original_repo")"
  TP_GENERATED_REPO="$(tp_abs_path "$resolved_generated_repo")"
  TP_ADAPTER="$resolved_adapter"
  TP_MAX_ITER="$resolved_max_iter"
  TP_ORIGINAL_SUBDIR="$resolved_original_subdir"
  TP_GENERATED_SUBDIR="$resolved_generated_subdir"
  TP_GENERATED_EFFECTIVE_SUBDIR="$TP_GENERATED_SUBDIR"

  if [[ ! -d "$TP_ORIGINAL_REPO" ]]; then
    kvasir_service_apply_failure "missing-original-repo" "missing_input"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi
  if [[ ! -d "$TP_GENERATED_REPO" ]]; then
    kvasir_service_apply_failure "missing-generated-repo" "missing_input"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi

  TP_ORIGINAL_EFFECTIVE_PATH="$TP_ORIGINAL_REPO"
  if [[ -n "$TP_ORIGINAL_SUBDIR" ]]; then
    TP_ORIGINAL_EFFECTIVE_PATH="${TP_ORIGINAL_REPO}/${TP_ORIGINAL_SUBDIR}"
    if [[ ! -d "$TP_ORIGINAL_EFFECTIVE_PATH" ]]; then
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    fi
  fi

  TP_GENERATED_EFFECTIVE_PATH="$TP_GENERATED_REPO"
  if [[ -n "$TP_GENERATED_SUBDIR" ]]; then
    TP_GENERATED_EFFECTIVE_PATH="${TP_GENERATED_REPO}/${TP_GENERATED_SUBDIR}"
    if [[ ! -d "$TP_GENERATED_EFFECTIVE_PATH" ]]; then
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    fi
  fi

  TP_DIAGRAM_PATH=""
  if [[ -n "$resolved_diagram" ]]; then
    TP_DIAGRAM_PATH="$(tp_abs_path "$resolved_diagram")"
    if [[ ! -f "$TP_DIAGRAM_PATH" ]]; then
      kvasir_service_apply_failure "invalid-service-config" "invalid_config"
      if ! kvasir_service_write_reports_or_fail; then
        return 1
      fi
      return 1
    fi
  fi

  TP_WRITE_SCOPE_IGNORE_PREFIXES="$resolved_write_scope_prefixes"
  if ! tp_resolve_write_scope_policy_classes; then
    kvasir_service_apply_failure "invalid-service-config" "invalid_config"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi

  if ! adapter_is_supported "$TP_ADAPTER"; then
    kvasir_service_apply_failure "unsupported-adapter" "unsupported_adapter"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi

  if ! kvasir_service_prepare_runtime_dirs; then
    kvasir_service_apply_failure "run-dir-not-writable" "run_dir_not_writable"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi

  if ! kvasir_service_bootstrap_provider "$TP_ADAPTER"; then
    kvasir_service_apply_failure "adapter-prereqs-failed" "provider_bootstrap_failed"
    if ! kvasir_service_write_reports_or_fail; then
      return 1
    fi
    return 1
  fi

  export TMPDIR="$TP_TMP_DIR"

  TP_ADAPTER_INPUT_DIAGRAM_PATH="${TP_DIAGRAM_PATH:-${TP_GENERATED_REPO}/.test-port-no-diagram.puml}"

  tp_log "service run dir: $TP_RUN_DIR"
  tp_log "service generated repo: $TP_GENERATED_REPO"
  tp_log "service original repo: $TP_ORIGINAL_REPO"
  [[ -n "$TP_ORIGINAL_SUBDIR" ]] && tp_log "service original subdir: $TP_ORIGINAL_SUBDIR"
  [[ -n "$TP_GENERATED_SUBDIR" ]] && tp_log "service generated subdir: $TP_GENERATED_SUBDIR"

  tp_execute

  if $TP_WORKSPACE_PREPARED; then
    tp_finalize_generated_repo_immutability_guard
  fi

  if [[ -d "${TP_PORTED_EFFECTIVE_REPO:-}" && -d "${TP_ORIGINAL_TESTS_SNAPSHOT:-}" ]]; then
    tp_refresh_evidence_state "$TP_PORTED_EFFECTIVE_REPO" "$TP_ORIGINAL_TESTS_SNAPSHOT" "$TP_REMOVED_TESTS_MANIFEST_PATH" "$TP_EVIDENCE_JSON_PATH" || true
  fi

  if ! kvasir_service_write_reports_or_fail; then
    return 1
  fi

  tp_log "summary: $TP_SUMMARY_MD_PATH"
  tp_log "json: $TP_JSON_PATH"

  if kvasir_service_exit_code_for_result; then
    service_exit_code=0
  else
    service_exit_code=1
  fi
  return "$service_exit_code"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  kvasir_service_main "$@"
fi
