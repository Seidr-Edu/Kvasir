#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_runner.sh"

case_maven_uses_workspace_local_repo() {
  local tmp repo fake_bin log args_file local_repo
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/mvn.log"
  args_file="${tmp}/mvn-args.txt"
  local_repo="${tmp}/workspace/.m2/repository"

  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$TPT_MVN_ARGS_FILE"
repo_local=""
for arg in "$@"; do
  case "$arg" in
    -Dmaven.repo.local=*) repo_local="${arg#*=}" ;;
  esac
done
[[ -n "$repo_local" ]]
mkdir -p "$repo_local" target/surefire-reports
echo "cached" > "${repo_local}/artifact.txt"
cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_MVN_ARGS_FILE="$args_file"
  TP_MAVEN_LOCAL_REPO="$local_repo"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_run_tests "$repo" "$log"

  tpt_assert_file_contains "$args_file" "-Dmaven.repo.local=${local_repo}" "maven invocation must set workspace local repo"
  tpt_assert_file_exists "${local_repo}/artifact.txt" "maven local repo should receive runtime cache writes"
}

case_gradle_wrapper_invocation_unchanged() {
  local tmp repo log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  log="${tmp}/gradlew.log"
  args_file="${tmp}/gradlew-args.txt"

  mkdir -p "$repo"
  cat > "${repo}/gradlew" <<'GRADLEW'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$TPT_GRADLEW_ARGS_FILE"
GRADLEW
  chmod +x "${repo}/gradlew"

  export TPT_GRADLEW_ARGS_FILE="$args_file"
  tp_run_tests "$repo" "$log"

  tpt_assert_file_contains "$args_file" "test --no-daemon" "gradle wrapper invocation should remain unchanged"
}

case_gradle_invocation_unchanged() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/gradle.log"
  args_file="${tmp}/gradle-args.txt"

  mkdir -p "$repo" "$fake_bin"
  echo "plugins {}" > "${repo}/build.gradle"

  cat > "${fake_bin}/gradle" <<'GRADLE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$TPT_GRADLE_ARGS_FILE"
GRADLE
  chmod +x "${fake_bin}/gradle"

  export TPT_GRADLE_ARGS_FILE="$args_file"
  PATH="${fake_bin}:$PATH"
  hash -r
  tp_run_tests "$repo" "$log"

  tpt_assert_file_contains "$args_file" "test --no-daemon" "plain gradle invocation should remain unchanged"
}

case_unknown_runner_returns_skipped_code() {
  local tmp repo log rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  log="${tmp}/unknown.log"

  mkdir -p "$repo"

  if tp_run_tests "$repo" "$log"; then
    echo "expected unknown runner to return skip code" >&2
    return 1
  else
    rc=$?
  fi

  tpt_assert_eq "2" "$rc" "unknown runner must return code 2"
  tpt_assert_file_contains "$log" "unsupported test runner" "unknown runner log should explain skip"
}

case_maven_baseline_uses_unit_first_and_skips_full_on_success() {
  local tmp repo fake_bin log args_file call_count_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/baseline.log"
  args_file="${tmp}/mvn-args.txt"
  call_count_file="${tmp}/mvn-call-count.txt"

  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_MVN_ARGS_FILE"
count=0
if [[ -f "$TPT_MVN_CALL_COUNT_FILE" ]]; then
  count="$(cat "$TPT_MVN_CALL_COUNT_FILE")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$TPT_MVN_CALL_COUNT_FILE"
if [[ "$*" == *"-DskipITs"* ]]; then
  mkdir -p target/surefire-reports
  cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
  exit 0
fi
echo "full run should not have executed" >&2
exit 99
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_MVN_ARGS_FILE="$args_file"
  export TPT_MVN_CALL_COUNT_FILE="$call_count_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_run_baseline_tests "$repo" "$log"

  tpt_assert_eq "maven-unit-first-fallback-full" "$TP_BASELINE_LAST_STRATEGY" "baseline maven strategy should be unit-first fallback"
  tpt_assert_eq "pass" "$TP_BASELINE_LAST_STATUS" "successful unit-only baseline should pass"
  tpt_assert_eq "0" "$TP_BASELINE_LAST_UNIT_ONLY_RC" "unit-only baseline rc should be zero"
  tpt_assert_eq "-1" "$TP_BASELINE_LAST_FULL_RC" "fallback should not run when unit-only pass"
  tpt_assert_eq "1" "$(cat "$call_count_file")" "maven should be invoked exactly once"
  tpt_assert_file_contains "$args_file" "-DskipITs" "unit-only baseline must pass skipITs"
  tpt_assert_file_contains "$args_file" "-DexcludedGroups=integration,IntegrationTest" "unit-only baseline must exclude integration groups"
}

case_maven_baseline_falls_back_and_classifies_environmental_noise() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/baseline.log"
  args_file="${tmp}/mvn-args.txt"

  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_MVN_ARGS_FILE"
if [[ "$*" == *"-DskipITs"* ]]; then
  echo "Connection refused"
  exit 1
fi
echo "Non-resolvable parent POM"
exit 1
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_MVN_ARGS_FILE="$args_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  if tp_run_baseline_tests "$repo" "$log"; then
    echo "expected baseline fallback scenario to fail" >&2
    return 1
  fi

  tpt_assert_eq "maven-unit-first-fallback-full" "$TP_BASELINE_LAST_STRATEGY" "baseline maven strategy should remain unit-first fallback"
  tpt_assert_eq "fail-with-integration-skip" "$TP_BASELINE_LAST_STATUS" "failed baseline after integration skip should use dedicated status"
  tpt_assert_eq "1" "$TP_BASELINE_LAST_UNIT_ONLY_RC" "unit-only baseline should fail"
  tpt_assert_eq "1" "$TP_BASELINE_LAST_FULL_RC" "full fallback should fail"
  tpt_assert_eq "dependency-resolution-failure" "$TP_BASELINE_LAST_FAILURE_CLASS" "full fallback log should classify as dependency-resolution-failure"
  tpt_assert_eq "environmental-noise" "$TP_BASELINE_LAST_FAILURE_TYPE" "failure type should be environmental-noise"
  tpt_assert_file_contains "$log" "baseline unit-only run" "combined baseline log should include unit-only section"
  tpt_assert_file_contains "$log" "baseline full test fallback" "combined baseline log should include fallback section"
}

case_maven_baseline_fallback_passes_after_unit_only_failure() {
  local tmp repo fake_bin log args_file call_count_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/baseline.log"
  args_file="${tmp}/mvn-args.txt"
  call_count_file="${tmp}/mvn-call-count.txt"

  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_MVN_ARGS_FILE"
count=0
if [[ -f "$TPT_MVN_CALL_COUNT_FILE" ]]; then
  count="$(cat "$TPT_MVN_CALL_COUNT_FILE")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$TPT_MVN_CALL_COUNT_FILE"
if [[ "$*" == *"-DskipITs"* ]]; then
  echo "Connection refused"
  exit 1
fi
mkdir -p target/surefire-reports
cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
exit 0
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_MVN_ARGS_FILE="$args_file"
  export TPT_MVN_CALL_COUNT_FILE="$call_count_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_run_baseline_tests "$repo" "$log"

  tpt_assert_eq "maven-unit-first-fallback-full" "$TP_BASELINE_LAST_STRATEGY" "baseline maven strategy should remain unit-first fallback"
  tpt_assert_eq "pass" "$TP_BASELINE_LAST_STATUS" "full fallback success should mark baseline pass"
  tpt_assert_eq "1" "$TP_BASELINE_LAST_UNIT_ONLY_RC" "unit-only baseline should fail"
  tpt_assert_eq "0" "$TP_BASELINE_LAST_FULL_RC" "full fallback should pass"
  tpt_assert_eq "" "$TP_BASELINE_LAST_FAILURE_CLASS" "pass result should not carry failure class"
  tpt_assert_eq "" "$TP_BASELINE_LAST_FAILURE_TYPE" "pass result should not carry failure type"
  tpt_assert_eq "2" "$(cat "$call_count_file")" "maven should run both unit-only and full fallback phases"
  tpt_assert_file_contains "$log" "baseline unit-only run" "combined baseline log should include unit-only section"
  tpt_assert_file_contains "$log" "baseline full test fallback" "combined baseline log should include fallback section"
}

case_classifier_avoids_generic_error_as_compatibility() {
  local tmp log
  tmp="$(tpt_mktemp_dir)"
  log="${tmp}/failure.log"
  cat > "$log" <<'LOG'
[ERROR] error: network operation failed
LOG

  tpt_assert_eq "unknown" "$(tp_classify_test_failure_log "$log")" "generic error lines should not be forced into compatibility-build"
}

tpt_run_case "maven uses workspace local repo" case_maven_uses_workspace_local_repo
tpt_run_case "gradle wrapper invocation unchanged" case_gradle_wrapper_invocation_unchanged
tpt_run_case "gradle invocation unchanged" case_gradle_invocation_unchanged
tpt_run_case "unknown runner returns skip code" case_unknown_runner_returns_skipped_code
tpt_run_case "maven baseline unit-first skips full fallback on success" case_maven_baseline_uses_unit_first_and_skips_full_on_success
tpt_run_case "maven baseline fallback classifies environmental noise" case_maven_baseline_falls_back_and_classifies_environmental_noise
tpt_run_case "maven baseline fallback recovers from unit-only failure" case_maven_baseline_fallback_passes_after_unit_only_failure
tpt_run_case "classifier avoids generic error compatibility overfit" case_classifier_avoids_generic_error_as_compatibility

tpt_finish_suite
