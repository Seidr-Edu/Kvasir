#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_common.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_runner.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_build_env.sh"

make_fake_jdk() {
  local root="$1"
  local version="$2"
  local home="${root}/jdk${version}"

  mkdir -p "${home}/bin"
  cat > "${home}/bin/java" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'openjdk version "%s"\n' "${version}.0.1" >&2
EOF
  chmod +x "${home}/bin/java"

  printf '%s\n' "$home"
}

make_fake_maven() {
  local root="$1"
  local mode="$2"
  local fake_bin="${root}/bin"

  mkdir -p "$fake_bin"
  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail

java_home_basename="$(basename "${JAVA_HOME:-missing}")"
printf '%s\n' "$java_home_basename" >> "${TPT_BUILD_ENV_JDK_LOG}"

case "${TPT_BUILD_ENV_MAVEN_MODE}" in
  retry-on-toolchain)
    if [[ "$java_home_basename" == "jdk11" ]]; then
      printf '%s\n' "Unsupported class file major version 61"
      exit 1
    fi
    mkdir -p target/surefire-reports
    cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
    exit 0
    ;;
  assertion-no-retry)
    printf '%s\n' "AssertionFailedError: expected:<1> but was:<2>"
    exit 1
    ;;
  *)
    printf '%s\n' "unknown fake maven mode" >&2
    exit 99
    ;;
esac
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_BUILD_ENV_MAVEN_MODE="$mode"
  export PATH="${fake_bin}:$PATH"
  hash -r
}

make_maven_repo() {
  local root="$1"
  local java_version="$2"
  local repo="${root}/repo"

  mkdir -p "$repo"
  cat > "${repo}/pom.xml" <<EOF
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>example</groupId>
  <artifactId>fake</artifactId>
  <version>1.0.0</version>
  <properties>
    <maven.compiler.source>${java_version}</maven.compiler.source>
    <maven.compiler.target>${java_version}</maven.compiler.target>
  </properties>
</project>
EOF

  printf '%s\n' "$repo"
}

case_discover_jdks_uses_override_search_dirs() {
  local tmp root jdk11 jdk17 listed
  tmp="$(tpt_mktemp_dir)"
  root="${tmp}/jdks"
  mkdir -p "$root"

  jdk11="$(make_fake_jdk "$root" 11)"
  jdk17="$(make_fake_jdk "$root" 17)"
  [[ -d "$jdk11" && -d "$jdk17" ]]

  TP_BUILD_ENV_PLATFORM_OVERRIDE="Linux"
  TP_BUILD_ENV_JDK_SEARCH_DIRS="$root"
  tp_build_env_reset_discovered_jdks

  listed="$(tp_build_env_list_available_jdks)"

  tpt_assert_eq $'17\n11' "$listed" "discovered JDKs should be sorted high to low"
}

case_baseline_retries_toolchain_failure_and_caches_generated_jdk() {
  local tmp root repo log_file jdk_log rc attempts
  tmp="$(tpt_mktemp_dir)"
  root="${tmp}/runtime"
  mkdir -p "$root"
  make_fake_jdk "$root" 11 >/dev/null
  make_fake_jdk "$root" 17 >/dev/null
  repo="$(make_maven_repo "$tmp" 11)"
  log_file="${tmp}/baseline.log"
  jdk_log="${tmp}/jdk-attempts.log"
  : > "$jdk_log"

  TP_BUILD_ENV_PLATFORM_OVERRIDE="Linux"
  TP_BUILD_ENV_JDK_SEARCH_DIRS="$root"
  TP_GENERATED_BASELINE_SUCCESSFUL_JDK=""
  TP_RUN_DIR="$tmp/run"
  export TPT_BUILD_ENV_JDK_LOG="$jdk_log"
  make_fake_maven "$tmp" "retry-on-toolchain"
  tp_build_env_prepare_runtime_toolcache

  set +e
  tp_run_baseline_tests_with_build_env "TP_BASELINE_GENERATED" "$repo" "$log_file"
  rc=$?
  set -e

  tpt_assert_eq "0" "$rc" "toolchain mismatch should recover on a newer JDK"
  tpt_assert_eq "17" "$TP_GENERATED_BASELINE_SUCCESSFUL_JDK" "generated baseline should cache the winning JDK"
  tpt_assert_eq "17" "$(tp_build_env_suite_get "TP_BASELINE_GENERATED" "SELECTED_JDK")" "suite metadata should record the selected JDK"
  tpt_assert_eq "11:17" "$(tp_build_env_suite_get "TP_BASELINE_GENERATED" "ATTEMPTED_JDKS_CSV")" "suite metadata should record retry order"

  attempts="$(cat "$jdk_log")"
  tpt_assert_eq $'jdk11\njdk11\njdk17' "$attempts" "baseline should retry with the next compatible JDK after exhausting the first JDK's baseline strategy"
}

case_ported_prefers_generated_successful_jdk() {
  local tmp root repo log_file jdk_log rc attempts
  tmp="$(tpt_mktemp_dir)"
  root="${tmp}/runtime"
  mkdir -p "$root"
  make_fake_jdk "$root" 11 >/dev/null
  make_fake_jdk "$root" 17 >/dev/null
  repo="$(make_maven_repo "$tmp" 11)"
  log_file="${tmp}/ported.log"
  jdk_log="${tmp}/jdk-attempts.log"
  : > "$jdk_log"

  TP_BUILD_ENV_PLATFORM_OVERRIDE="Linux"
  TP_BUILD_ENV_JDK_SEARCH_DIRS="$root"
  TP_GENERATED_BASELINE_SUCCESSFUL_JDK="17"
  TP_PORTED_LAST_SUCCESSFUL_JDK=""
  TP_RUN_DIR="$tmp/run"
  export TPT_BUILD_ENV_JDK_LOG="$jdk_log"
  make_fake_maven "$tmp" "retry-on-toolchain"
  tp_build_env_prepare_runtime_toolcache

  set +e
  tp_run_tests_with_build_env "TP_PORTED_ORIGINAL" "$repo" "$log_file"
  rc=$?
  set -e

  tpt_assert_eq "0" "$rc" "ported run should succeed on cached generated baseline JDK"
  tpt_assert_eq "17" "$TP_PORTED_LAST_SUCCESSFUL_JDK" "ported runs should remember the last successful JDK"
  tpt_assert_eq "17" "$(tp_build_env_suite_get "TP_PORTED_ORIGINAL" "SELECTED_JDK")" "ported suite should record the selected JDK"
  tpt_assert_eq "17" "$(tp_build_env_suite_get "TP_PORTED_ORIGINAL" "ATTEMPTED_JDKS_CSV")" "ported suite should try cached generated JDK before hinted fallback"

  attempts="$(cat "$jdk_log")"
  tpt_assert_eq "jdk17" "$attempts" "ported run should reuse the generated baseline JDK before probing older JDKs"
}

case_assertion_failures_do_not_retry_across_jdks() {
  local tmp root repo log_file jdk_log rc attempts
  tmp="$(tpt_mktemp_dir)"
  root="${tmp}/runtime"
  mkdir -p "$root"
  make_fake_jdk "$root" 11 >/dev/null
  make_fake_jdk "$root" 17 >/dev/null
  repo="$(make_maven_repo "$tmp" 11)"
  log_file="${tmp}/ported.log"
  jdk_log="${tmp}/jdk-attempts.log"
  : > "$jdk_log"

  TP_BUILD_ENV_PLATFORM_OVERRIDE="Linux"
  TP_BUILD_ENV_JDK_SEARCH_DIRS="$root"
  TP_GENERATED_BASELINE_SUCCESSFUL_JDK=""
  TP_PORTED_LAST_SUCCESSFUL_JDK=""
  TP_RUN_DIR="$tmp/run"
  export TPT_BUILD_ENV_JDK_LOG="$jdk_log"
  make_fake_maven "$tmp" "assertion-no-retry"
  tp_build_env_prepare_runtime_toolcache

  set +e
  tp_run_tests_with_build_env "TP_PORTED_ORIGINAL" "$repo" "$log_file"
  rc=$?
  set -e

  tpt_assert_eq "1" "$rc" "assertion failures should propagate without cross-JDK retries"
  tpt_assert_eq "11" "$(tp_build_env_suite_get "TP_PORTED_ORIGINAL" "ATTEMPTED_JDKS_CSV")" "assertion failures should stop after the first attempt"

  attempts="$(cat "$jdk_log")"
  tpt_assert_eq "jdk11" "$attempts" "assertion failures should not probe a second JDK"
}

tpt_run_case "discover jdks uses override search dirs" case_discover_jdks_uses_override_search_dirs
tpt_run_case "baseline retries toolchain failure and caches generated jdk" case_baseline_retries_toolchain_failure_and_caches_generated_jdk
tpt_run_case "ported prefers generated successful jdk" case_ported_prefers_generated_successful_jdk
tpt_run_case "assertion failures do not retry across jdks" case_assertion_failures_do_not_retry_across_jdks

tpt_finish_suite
