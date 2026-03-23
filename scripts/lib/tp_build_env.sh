#!/usr/bin/env bash
# tp_build_env.sh - JDK discovery/selection and build-environment metadata.

set -euo pipefail

TP_BUILD_ENV_AVAILABLE_JDKS=()
TP_BUILD_ENV_DISCOVERED_JDK_KEYS=()

tp_build_env_jdk_home_var_name() {
  printf '_TP_BUILD_ENV_JDK_HOME_%s' "$1"
}

tp_build_env_set_jdk_home() {
  local version="$1"
  local path="$2"
  local var_name
  var_name="$(tp_build_env_jdk_home_var_name "$version")"
  printf -v "$var_name" '%s' "$path"
}

tp_build_env_get_jdk_home() {
  local version="$1"
  local var_name
  var_name="$(tp_build_env_jdk_home_var_name "$version")"
  printf '%s' "${!var_name:-}"
}

tp_build_env_has_jdk_home() {
  local version="$1"
  local home
  home="$(tp_build_env_get_jdk_home "$version")"
  [[ -n "$home" ]]
}

tp_build_env_record_jdk() {
  local version="$1"
  local path="$2"
  [[ -n "$version" && -n "$path" && -d "$path" ]] || return 0
  if tp_build_env_has_jdk_home "$version"; then
    return 0
  fi
  TP_BUILD_ENV_AVAILABLE_JDKS+=("$version")
  TP_BUILD_ENV_DISCOVERED_JDK_KEYS+=("$version")
  tp_build_env_set_jdk_home "$version" "$path"
}

tp_build_env_reset_discovered_jdks() {
  local version
  if [[ ${#TP_BUILD_ENV_DISCOVERED_JDK_KEYS[@]} -gt 0 ]]; then
    for version in "${TP_BUILD_ENV_DISCOVERED_JDK_KEYS[@]}"; do
      unset "_TP_BUILD_ENV_JDK_HOME_${version}" || true
    done
  fi
  TP_BUILD_ENV_DISCOVERED_JDK_KEYS=()
  TP_BUILD_ENV_AVAILABLE_JDKS=()
}

tp_build_env_normalize_java_version() {
  local version="$1"
  [[ -n "$version" ]] || {
    printf '%s' ""
    return 0
  }

  if [[ "$version" =~ ^1\.([0-9]+) ]]; then
    version="${BASH_REMATCH[1]}"
  else
    version="$(printf '%s' "$version" | sed -E 's/^([0-9]+).*$/\1/')"
  fi

  printf '%s' "$version"
}

tp_build_env_discover_jdks_macos() {
  local java_home_output
  java_home_output="$(/usr/libexec/java_home -V 2>&1 || true)"

  while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]+([0-9]+) ]]; then
      local version="${BASH_REMATCH[1]}"
      local jdk_path=""
      jdk_path="$(/usr/libexec/java_home -v "$version" 2>/dev/null || true)"
      tp_build_env_record_jdk "$version" "$jdk_path"
    fi
  done <<< "$java_home_output"

  local jdk_dir
  for jdk_dir in /opt/homebrew/opt/openjdk@* /usr/local/opt/openjdk@*; do
    [[ -d "$jdk_dir" ]] || continue
    local version
    version="$(basename "$jdk_dir" | sed 's/openjdk@//')"
    if [[ -d "${jdk_dir}/libexec/openjdk.jdk/Contents/Home" ]]; then
      tp_build_env_record_jdk "$version" "${jdk_dir}/libexec/openjdk.jdk/Contents/Home"
    fi
  done
}

tp_build_env_discover_jdks_linux() {
  local search_roots_default="/usr/lib/jvm:/usr/java:/opt/java"
  if [[ -n "${HOME:-}" ]]; then
    search_roots_default="${search_roots_default}:${HOME}/.sdkman/candidates/java"
  fi
  local search_roots="${TP_BUILD_ENV_JDK_SEARCH_DIRS:-$search_roots_default}"
  local -a roots=()
  local root
  local IFS=':'
  read -r -a roots <<< "$search_roots"

  for root in "${roots[@]}"; do
    [[ -n "$root" && -d "$root" ]] || continue

    if [[ -x "${root}/bin/java" ]]; then
      local root_version=""
      root_version="$("${root}/bin/java" -version 2>&1 | head -1 | sed -n 's/.*version "\([^"]*\)".*/\1/p')"
      root_version="$(tp_build_env_normalize_java_version "$root_version")"
      tp_build_env_record_jdk "$root_version" "$root"
    fi

    local jdk_dir
    for jdk_dir in "${root}"/*; do
      [[ -d "$jdk_dir" && -x "${jdk_dir}/bin/java" ]] || continue
      local version=""
      version="$("${jdk_dir}/bin/java" -version 2>&1 | head -1 | sed -n 's/.*version "\([^"]*\)".*/\1/p')"
      version="$(tp_build_env_normalize_java_version "$version")"
      tp_build_env_record_jdk "$version" "$jdk_dir"
    done
  done
}

tp_build_env_discover_jdks_generic() {
  if ! command -v java >/dev/null 2>&1; then
    return 0
  fi
  local version=""
  version="$(java -version 2>&1 | head -1 | sed -n 's/.*version "\([^"]*\)".*/\1/p')"
  version="$(tp_build_env_normalize_java_version "$version")"
  local java_home="${JAVA_HOME:-$(dirname "$(dirname "$(command -v java)")")}"
  tp_build_env_record_jdk "$version" "$java_home"
}

tp_build_env_discover_jdks() {
  if [[ ${#TP_BUILD_ENV_AVAILABLE_JDKS[@]} -gt 0 ]]; then
    return 0
  fi

  tp_build_env_reset_discovered_jdks

  case "${TP_BUILD_ENV_PLATFORM_OVERRIDE:-$(uname -s)}" in
    Darwin)
      tp_build_env_discover_jdks_macos
      ;;
    Linux)
      tp_build_env_discover_jdks_linux
      ;;
    *)
      tp_build_env_discover_jdks_generic
      ;;
  esac

  if [[ ${#TP_BUILD_ENV_AVAILABLE_JDKS[@]} -gt 0 ]]; then
    local sorted
    sorted="$(printf '%s\n' "${TP_BUILD_ENV_AVAILABLE_JDKS[@]}" | sort -rn | uniq)"
    TP_BUILD_ENV_AVAILABLE_JDKS=()
    local discovered_version=""
    while IFS= read -r discovered_version; do
      [[ -n "$discovered_version" ]] && TP_BUILD_ENV_AVAILABLE_JDKS+=("$discovered_version")
    done <<< "$sorted"
  fi
}

tp_build_env_list_available_jdks() {
  tp_build_env_discover_jdks
  printf '%s\n' "${TP_BUILD_ENV_AVAILABLE_JDKS[@]}"
}

tp_build_env_prepare_runtime_toolcache() {
  TP_TOOLCACHE_DIR="${TP_TOOLCACHE_DIR:-${TP_RUN_DIR}/toolcache}"
  TP_TOOLCACHE_BIN_DIR="${TP_TOOLCACHE_DIR}/bin"
  mkdir -p "$TP_TOOLCACHE_BIN_DIR"
  case ":$PATH:" in
    *":${TP_TOOLCACHE_BIN_DIR}:"*) ;;
    *)
      export PATH="${TP_TOOLCACHE_BIN_DIR}:$PATH"
      ;;
  esac
  export TP_BUILD_ENV_BASE_PATH="$PATH"
}

tp_build_env_select_jdk() {
  local version="$1"
  tp_build_env_discover_jdks

  local jdk_home=""
  jdk_home="$(tp_build_env_get_jdk_home "$version")"
  if [[ -z "$jdk_home" ]]; then
    return 1
  fi

  if [[ -z "${TP_BUILD_ENV_BASE_PATH:-}" ]]; then
    export TP_BUILD_ENV_BASE_PATH="$PATH"
  fi

  export JAVA_HOME="$jdk_home"
  export PATH="${JAVA_HOME}/bin:${TP_BUILD_ENV_BASE_PATH}"

  if ! java -version >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

tp_build_env_extract_maven_java_version() {
  local pom_file="$1"
  local version=""

  local pattern
  for pattern in \
    "maven.compiler.source" \
    "maven.compiler.target" \
    "maven.compiler.release" \
    "java.version" \
    "jdk.version"; do
    version="$(sed -n "s/.*<${pattern}>\\([^<]*\\)<.*/\\1/p" "$pom_file" 2>/dev/null | head -1)"
    if [[ -n "$version" ]]; then
      version="$(tp_build_env_normalize_java_version "$version")"
      break
    fi
  done

  printf '%s' "$version"
}

tp_build_env_extract_gradle_java_version() {
  local build_file="$1"
  local version=""

  version="$(sed -n "s/.*sourceCompatibility[[:space:]]*=[[:space:]]*['\"\\\`]*\\([0-9.]*\\).*/\\1/p" "$build_file" 2>/dev/null | head -1)"
  if [[ -z "$version" ]]; then
    version="$(sed -n 's/.*JavaLanguageVersion\.of[[:space:]]*([[:space:]]*\([0-9]*\).*/\1/p' "$build_file" 2>/dev/null | tail -1)"
  fi
  if [[ -z "$version" ]]; then
    version="$(sed -n 's/.*JavaVersion\.VERSION_\([0-9_]*\).*/\1/p' "$build_file" 2>/dev/null | head -1 | tr -d '_')"
  fi
  if [[ -n "$version" ]]; then
    version="$(tp_build_env_normalize_java_version "$version")"
  fi

  printf '%s' "$version"
}

tp_build_env_runner_to_build_tool() {
  local runner="$1"
  case "$runner" in
    maven) printf '%s' "maven" ;;
    gradle|gradle-wrapper) printf '%s' "gradle" ;;
    *) printf '%s' "unknown" ;;
  esac
}

tp_build_env_detect_java_version_hint() {
  local repo="$1"
  local build_tool="$2"
  local version=""

  case "$build_tool" in
    maven)
      if [[ -f "${repo}/pom.xml" ]]; then
        version="$(tp_build_env_extract_maven_java_version "${repo}/pom.xml")"
      fi
      ;;
    gradle)
      if [[ -f "${repo}/build.gradle" ]]; then
        version="$(tp_build_env_extract_gradle_java_version "${repo}/build.gradle")"
      elif [[ -f "${repo}/build.gradle.kts" ]]; then
        version="$(tp_build_env_extract_gradle_java_version "${repo}/build.gradle.kts")"
      fi
      ;;
  esac

  printf '%s' "$version"
}

tp_build_env_resolve_requested_jdk() {
  local requested
  requested="$(tp_build_env_normalize_java_version "${1:-}")"
  [[ -n "$requested" ]] || return 1

  if [[ "$requested" =~ ^[0-9]+$ ]]; then
    if (( requested <= 8 )); then
      printf '%s' "8"
    elif (( requested == 9 || requested == 10 )); then
      printf '%s' "11"
    else
      printf '%s' "$requested"
    fi
    return 0
  fi

  return 1
}

tp_build_env_suite_prefix() {
  printf '%s_BUILD_ENV' "$1"
}

tp_build_env_suite_var_name() {
  local suite="$1"
  local field="$2"
  printf '%s_%s' "$(tp_build_env_suite_prefix "$suite")" "$field"
}

tp_build_env_suite_set() {
  local suite="$1"
  local field="$2"
  local value="${3:-}"
  local var_name
  var_name="$(tp_build_env_suite_var_name "$suite" "$field")"
  printf -v "$var_name" '%s' "$value"
}

tp_build_env_suite_get() {
  local suite="$1"
  local field="$2"
  local var_name
  var_name="$(tp_build_env_suite_var_name "$suite" "$field")"
  printf '%s' "${!var_name:-}"
}

tp_build_env_suite_append_attempted_jdk() {
  local suite="$1"
  local version="$2"
  local current
  current="$(tp_build_env_suite_get "$suite" "ATTEMPTED_JDKS_CSV")"
  if [[ -z "$current" ]]; then
    tp_build_env_suite_set "$suite" "ATTEMPTED_JDKS_CSV" "$version"
  else
    tp_build_env_suite_set "$suite" "ATTEMPTED_JDKS_CSV" "${current}:${version}"
  fi
}

tp_build_env_reset_suite_state() {
  local suite="$1"
  local field
  for field in \
    DETECTED_RUNNER BUILD_TOOL MODULE_ROOT BUILD_SUBDIR JAVA_VERSION_HINT \
    SELECTED_JDK ATTEMPTED_JDKS_CSV HINT_BUILD_TOOL HINT_BUILD_JDK \
    HINT_JAVA_VERSION_HINT HINT_BUILD_SUBDIR HINT_SOURCE; do
    tp_build_env_suite_set "$suite" "$field" ""
  done
}

tp_build_env_hint_kind_for_suite() {
  local suite="$1"
  case "$suite" in
    TP_BASELINE_ORIGINAL)
      printf '%s' "ORIGINAL"
      ;;
    *)
      printf '%s' "GENERATED"
      ;;
  esac
}

tp_build_env_effective_subdir_for_suite() {
  local suite="$1"
  case "$suite" in
    TP_BASELINE_ORIGINAL)
      printf '%s' "${TP_ORIGINAL_SUBDIR:-}"
      ;;
    *)
      printf '%s' "${TP_GENERATED_EFFECTIVE_SUBDIR:-${TP_GENERATED_SUBDIR:-}}"
      ;;
  esac
}

tp_build_env_prepare_suite_state() {
  local suite="$1"
  local repo="$2"
  tp_build_env_reset_suite_state "$suite"

  local runner
  runner="$(tp_detect_test_runner "$repo")"
  local build_tool
  build_tool="$(tp_build_env_runner_to_build_tool "$runner")"
  local java_version_hint=""
  if [[ "$build_tool" != "unknown" ]]; then
    java_version_hint="$(tp_build_env_detect_java_version_hint "$repo" "$build_tool")"
  fi

  tp_build_env_suite_set "$suite" "DETECTED_RUNNER" "$runner"
  tp_build_env_suite_set "$suite" "BUILD_TOOL" "$build_tool"
  tp_build_env_suite_set "$suite" "MODULE_ROOT" "$repo"
  tp_build_env_suite_set "$suite" "BUILD_SUBDIR" "$(tp_build_env_effective_subdir_for_suite "$suite")"
  tp_build_env_suite_set "$suite" "JAVA_VERSION_HINT" "$java_version_hint"

  local hint_kind
  hint_kind="$(tp_build_env_hint_kind_for_suite "$suite")"
  local hint_field
  for hint_field in BUILD_TOOL BUILD_JDK JAVA_VERSION_HINT BUILD_SUBDIR SOURCE; do
    local value=""
    local hint_var_name="TP_HINT_${hint_kind}_${hint_field}"
    value="${!hint_var_name:-}"
    tp_build_env_suite_set "$suite" "HINT_${hint_field}" "$value"
  done
}

tp_build_env_add_candidate_version() {
  local version="$1"
  local target_name="$2"
  [[ -n "$version" ]] || return 0
  if ! tp_build_env_has_jdk_home "$version"; then
    return 0
  fi
  local existing
  eval "for existing in \"\${${target_name}[@]-}\"; do
    if [[ \"\$existing\" == \"$version\" ]]; then
      return 0
    fi
  done"
  eval "${target_name}+=(\"\$version\")"
}

tp_build_env_candidate_jdks_for_suite() {
  local suite="$1"
  tp_build_env_discover_jdks

  local -a candidates=()
  local version=""

  if [[ "$suite" == "TP_PORTED_ORIGINAL" ]]; then
    tp_build_env_add_candidate_version "${TP_PORTED_LAST_SUCCESSFUL_JDK:-}" candidates
    tp_build_env_add_candidate_version "${TP_GENERATED_BASELINE_SUCCESSFUL_JDK:-}" candidates
  fi

  local hint_build_jdk=""
  hint_build_jdk="$(tp_build_env_suite_get "$suite" "HINT_BUILD_JDK")"
  if version="$(tp_build_env_resolve_requested_jdk "$hint_build_jdk" 2>/dev/null || true)"; then
    tp_build_env_add_candidate_version "$version" candidates
  fi

  local java_version_hint=""
  java_version_hint="$(tp_build_env_suite_get "$suite" "JAVA_VERSION_HINT")"
  if version="$(tp_build_env_resolve_requested_jdk "$java_version_hint" 2>/dev/null || true)"; then
    tp_build_env_add_candidate_version "$version" candidates
  fi

  local hint_java_version=""
  hint_java_version="$(tp_build_env_suite_get "$suite" "HINT_JAVA_VERSION_HINT")"
  if version="$(tp_build_env_resolve_requested_jdk "$hint_java_version" 2>/dev/null || true)"; then
    tp_build_env_add_candidate_version "$version" candidates
  fi

  local preferred
  for preferred in 25 21 17 11 8; do
    tp_build_env_add_candidate_version "$preferred" candidates
  done

  for version in "${TP_BUILD_ENV_AVAILABLE_JDKS[@]}"; do
    tp_build_env_add_candidate_version "$version" candidates
  done

  printf '%s\n' "${candidates[@]}"
}

tp_build_env_log_indicates_toolchain_mismatch() {
  local log_file="$1"
  [[ -f "$log_file" ]] || return 1

  LC_ALL=C grep -Eiq \
    'release version .* not supported|invalid target release|Source option [0-9]+ is no longer supported|Target option [0-9]+ is no longer supported|Unsupported class file major version|java\.lang\.UnsupportedClassVersionError|class file has wrong version|NoSuchMethodError|Could not determine java version from|toolchain|Unsupported Java|requires Java' \
    "$log_file"
}

tp_build_env_should_retry_failure() {
  local failure_class="${1:-unknown}"
  local log_file="$2"
  local attempt_no="$3"
  local total_candidates="$4"

  [[ "$attempt_no" -lt "$total_candidates" ]] || return 1

  case "$failure_class" in
    assertion-failure|dependency-resolution-failure)
      return 1
      ;;
  esac

  tp_build_env_log_indicates_toolchain_mismatch "$log_file"
}

tp_build_env_suite_report_json() {
  local suite="$1"
  python3 - <<'PY' \
    "$(tp_build_env_suite_get "$suite" "DETECTED_RUNNER")" \
    "$(tp_build_env_suite_get "$suite" "BUILD_TOOL")" \
    "$(tp_build_env_suite_get "$suite" "MODULE_ROOT")" \
    "$(tp_build_env_suite_get "$suite" "BUILD_SUBDIR")" \
    "$(tp_build_env_suite_get "$suite" "JAVA_VERSION_HINT")" \
    "$(tp_build_env_suite_get "$suite" "SELECTED_JDK")" \
    "$(tp_build_env_suite_get "$suite" "ATTEMPTED_JDKS_CSV")" \
    "$(tp_build_env_suite_get "$suite" "HINT_BUILD_TOOL")" \
    "$(tp_build_env_suite_get "$suite" "HINT_BUILD_JDK")" \
    "$(tp_build_env_suite_get "$suite" "HINT_JAVA_VERSION_HINT")" \
    "$(tp_build_env_suite_get "$suite" "HINT_BUILD_SUBDIR")" \
    "$(tp_build_env_suite_get "$suite" "HINT_SOURCE")"
import json
import sys

(
    detected_runner,
    build_tool,
    module_root,
    build_subdir,
    java_version_hint,
    selected_jdk,
    attempted_jdks_csv,
    hint_build_tool,
    hint_build_jdk,
    hint_java_version_hint,
    hint_build_subdir,
    hint_source,
) = sys.argv[1:]

attempted_jdks = [value for value in attempted_jdks_csv.split(":") if value]
hint = {
    "build_tool": hint_build_tool or None,
    "build_jdk": hint_build_jdk or None,
    "java_version_hint": hint_java_version_hint or None,
    "build_subdir": hint_build_subdir or None,
    "source": hint_source or None,
}
if not any(hint.values()):
    hint = None

obj = {
    "detected_runner": detected_runner or None,
    "build_tool": build_tool or None,
    "module_root": module_root or None,
    "build_subdir": build_subdir or None,
    "java_version_hint": java_version_hint or None,
    "selected_jdk": selected_jdk or None,
    "attempted_jdks": attempted_jdks,
    "hint": hint,
}
print(json.dumps(obj, separators=(",", ":")))
PY
}

tp_run_baseline_tests_with_build_env() {
  local suite="$1"
  local repo="$2"
  local log_file="$3"
  local -a candidates=()
  local jdk=""
  local rc=1
  local attempt_no=0

  tp_build_env_prepare_suite_state "$suite" "$repo"
  while IFS= read -r jdk; do
    [[ -n "$jdk" ]] && candidates+=("$jdk")
  done < <(tp_build_env_candidate_jdks_for_suite "$suite")

  if [[ ${#candidates[@]} -eq 0 ]]; then
    tp_run_baseline_tests "$repo" "$log_file"
    return $?
  fi

  for jdk in "${candidates[@]}"; do
    ((attempt_no+=1))
    tp_build_env_suite_append_attempted_jdk "$suite" "$jdk"
    if ! tp_build_env_select_jdk "$jdk"; then
      continue
    fi
    tp_log "[$suite] baseline run with JDK $jdk"
    tp_run_baseline_tests "$repo" "$log_file"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      tp_build_env_suite_set "$suite" "SELECTED_JDK" "$jdk"
      if [[ "$suite" == "TP_BASELINE_GENERATED" ]]; then
        TP_GENERATED_BASELINE_SUCCESSFUL_JDK="$jdk"
      fi
      return 0
    fi
    if [[ "$rc" -eq 2 ]]; then
      return 2
    fi
    if tp_build_env_should_retry_failure "${TP_BASELINE_LAST_FAILURE_CLASS:-unknown}" "$log_file" "$attempt_no" "${#candidates[@]}"; then
      tp_warn "[$suite] retrying after toolchain-sensitive baseline failure on JDK $jdk"
      continue
    fi
    break
  done

  return "$rc"
}

tp_run_tests_with_build_env() {
  local suite="$1"
  local repo="$2"
  local log_file="$3"
  local -a candidates=()
  local jdk=""
  local rc=1
  local attempt_no=0

  tp_build_env_prepare_suite_state "$suite" "$repo"
  while IFS= read -r jdk; do
    [[ -n "$jdk" ]] && candidates+=("$jdk")
  done < <(tp_build_env_candidate_jdks_for_suite "$suite")

  if [[ ${#candidates[@]} -eq 0 ]]; then
    tp_run_tests "$repo" "$log_file"
    return $?
  fi

  for jdk in "${candidates[@]}"; do
    ((attempt_no+=1))
    tp_build_env_suite_append_attempted_jdk "$suite" "$jdk"
    if ! tp_build_env_select_jdk "$jdk"; then
      continue
    fi
    tp_log "[$suite] test run with JDK $jdk"
    tp_run_tests "$repo" "$log_file"
    rc=$?
    if [[ "$rc" -eq 0 ]]; then
      tp_build_env_suite_set "$suite" "SELECTED_JDK" "$jdk"
      if [[ "$suite" == "TP_PORTED_ORIGINAL" ]]; then
        TP_PORTED_LAST_SUCCESSFUL_JDK="$jdk"
      fi
      return 0
    fi
    if [[ "$rc" -eq 2 ]]; then
      return 2
    fi
    tp_classify_test_failure_log "$log_file" >/dev/null
    if tp_build_env_should_retry_failure "${TP_LAST_FAILURE_CLASS:-unknown}" "$log_file" "$attempt_no" "${#candidates[@]}"; then
      tp_warn "[$suite] retrying after toolchain-sensitive failure on JDK $jdk"
      continue
    fi
    break
  done

  return "$rc"
}
