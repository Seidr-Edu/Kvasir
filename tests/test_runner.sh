#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_runner.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_copy.sh"

prepare_scope_env() {
  local root="$1"
  TP_LOG_DIR="${root}/logs"
  TP_SUMMARY_DIR="${root}/summary"
  TP_TEST_SCOPE_JSON_PATH="${TP_SUMMARY_DIR}/test-scope.json"
  TP_TEST_SCOPE_PROBES_FILE="${TP_SUMMARY_DIR}/test-scope-probes.jsonl"
  TP_TEST_SCOPE_EXCLUDED_COMMANDS_FILE="${TP_SUMMARY_DIR}/test-scope-excluded-commands.tsv"
  TP_TEST_SCOPE_EXCLUDED_TESTS_FILE="${TP_SUMMARY_DIR}/test-scope-excluded-tests.tsv"
  TP_MAVEN_LOCAL_REPO="${root}/workspace/.m2/repository"
  TP_GRADLE_USER_HOME="${root}/workspace/.gradle"
  TP_TMP_DIR="${root}/workspace/tmp"
  mkdir -p "$TP_LOG_DIR" "$TP_SUMMARY_DIR" "${root}/workspace"
}

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

case_gradle_full_suite_runs_all_detected_test_tasks() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/gradle.log"
  args_file="${tmp}/gradle-args.txt"

  mkdir -p "$repo/src/test/java" "$repo/src/integrationTest/java" "$fake_bin"
  cat > "${repo}/build.gradle" <<'GRADLE'
plugins {}
tasks.register('integrationTest', Test)
GRADLE

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

  tpt_assert_file_contains "$args_file" "test" "full-suite Gradle run should include the default test task"
  tpt_assert_file_contains "$args_file" "integrationTest" "full-suite Gradle run should include detected integration tasks"
  tpt_assert_file_contains "$args_file" "--no-daemon" "full-suite Gradle run should retain no-daemon"
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

case_portable_scope_maven_selects_broad_when_it_passes() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/portable.log"
  args_file="${tmp}/mvn-args.txt"

  prepare_scope_env "$tmp"
  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_MVN_ARGS_FILE"
if [[ "$*" == *"-DskipITs"* ]]; then
  echo "narrow command should not run" >&2
  exit 99
fi
mkdir -p target/surefire-reports
cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="2" failures="0" errors="0"><testcase classname="fake" name="one"/><testcase classname="fake" name="two"/></testsuite>
XML
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_MVN_ARGS_FILE="$args_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_select_and_run_portable_scope "$repo" "$log"

  tpt_assert_eq "selected" "$TP_TEST_SCOPE_STATUS" "portable scope should be selected"
  tpt_assert_eq "broad" "$TP_TEST_SCOPE_SELECTED_MAVEN_MODE" "passing Maven broad command should be selected"
  tpt_assert_eq "mvn test" "$TP_TEST_SCOPE_SELECTED_COMMANDS_CSV" "selected command should be broad mvn test"
  tpt_assert_eq "portable-tests" "$TP_BASELINE_LAST_STRATEGY" "baseline strategy should be portable-tests"
  tpt_assert_eq "pass" "$TP_BASELINE_LAST_STATUS" "portable baseline should pass"
  tp_collect_execution_summary "$repo" "$log" "TPT_FINAL"
  tpt_assert_eq "2" "$TPT_FINAL_TESTS_EXECUTED" "portable baseline should record execution count"
  tpt_assert_not_file_contains "$args_file" "-DskipITs" "narrow Maven flags should not run when broad passes"
}

case_portable_scope_maven_falls_back_to_narrow_after_environment_failure() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/portable.log"
  args_file="${tmp}/mvn-args.txt"

  prepare_scope_env "$tmp"
  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_MVN_ARGS_FILE"
if [[ "$*" != *"-DskipITs"* ]]; then
  echo "Connection refused"
  exit 1
fi
mkdir -p target/surefire-reports
cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="unit"/></testsuite>
XML
MVN
  chmod +x "${fake_bin}/mvn"

  export TPT_MVN_ARGS_FILE="$args_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_select_and_run_portable_scope "$repo" "$log"

  tpt_assert_eq "selected" "$TP_TEST_SCOPE_STATUS" "portable scope should be selected after fallback"
  tpt_assert_eq "narrow" "$TP_TEST_SCOPE_SELECTED_MAVEN_MODE" "Maven narrow command should be selected"
  tpt_assert_file_contains "$TP_TEST_SCOPE_EXCLUDED_COMMANDS_FILE" "environment-assumption-failure" "broad Maven env failure should be excluded"
  tpt_assert_file_contains "$args_file" "-DskipITs" "narrow Maven flags should run after env failure"
  tpt_assert_eq "pass" "$TP_BASELINE_LAST_STATUS" "narrow portable baseline should pass"
}

case_portable_scope_maven_skips_when_no_portable_signal_exists() {
  local tmp repo fake_bin log rc
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/portable.log"

  prepare_scope_env "$tmp"
  mkdir -p "$repo" "$fake_bin"
  echo "<project/>" > "${repo}/pom.xml"

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != *"-DskipITs"* ]]; then
  echo "Connection refused"
  exit 1
fi
printf 'BUILD SUCCESS with no tests\n'
exit 0
MVN
  chmod +x "${fake_bin}/mvn"

  PATH="${fake_bin}:$PATH"
  hash -r

  if tp_select_and_run_portable_scope "$repo" "$log"; then
    echo "expected no portable scope to be skipped" >&2
    return 1
  else
    rc=$?
  fi

  tpt_assert_eq "2" "$rc" "no portable signal should return skip code"
  tpt_assert_eq "none" "$TP_TEST_SCOPE_STATUS" "scope should be marked none"
  tpt_assert_eq "no-portable-test-signal" "$TP_TEST_SCOPE_SELECTION_REASON" "scope should explain no portable signal"
  tpt_assert_file_contains "$TP_TEST_SCOPE_EXCLUDED_COMMANDS_FILE" "mvn test" "broad Maven command should be recorded as excluded"
}

case_portable_scope_gradle_selects_multiple_passing_tasks() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/portable.log"
  args_file="${tmp}/gradle-args.txt"

  prepare_scope_env "$tmp"
  mkdir -p "$repo/src/test/java" "$repo/src/integrationTest/java" "$fake_bin"
  echo "tasks.register('integrationTest', Test)" > "${repo}/build.gradle"

  cat > "${fake_bin}/gradle" <<'GRADLE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_GRADLE_ARGS_FILE"
for task in "$@"; do
  case "$task" in
    test)
      mkdir -p build/test-results/test
      cat > build/test-results/test/TEST-test.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="unit"/></testsuite>
XML
      ;;
    integrationTest)
      mkdir -p build/test-results/integrationTest
      cat > build/test-results/integrationTest/TEST-integration.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="integration"/></testsuite>
XML
      ;;
  esac
done
GRADLE
  chmod +x "${fake_bin}/gradle"

  export TPT_GRADLE_ARGS_FILE="$args_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_select_and_run_portable_scope "$repo" "$log"

  tpt_assert_eq "selected" "$TP_TEST_SCOPE_STATUS" "passing Gradle tasks should select a portable scope"
  tpt_assert_eq "test:integrationTest" "$TP_TEST_SCOPE_SELECTED_TASKS_CSV" "both passing Gradle test tasks should be selected"
  tp_collect_execution_summary "$repo" "$log" "TPT_FINAL"
  tpt_assert_eq "2" "$TPT_FINAL_TESTS_EXECUTED" "final selected Gradle run should execute both suites"
}

case_portable_scope_gradle_excludes_environment_task_but_keeps_unit_task() {
  local tmp repo fake_bin log args_file
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  fake_bin="${tmp}/bin"
  log="${tmp}/portable.log"
  args_file="${tmp}/gradle-args.txt"

  prepare_scope_env "$tmp"
  mkdir -p "$repo/src/test/java" "$repo/src/integrationTest/java" "$fake_bin"
  echo "tasks.register('integrationTest', Test)" > "${repo}/build.gradle"

  cat > "${fake_bin}/gradle" <<'GRADLE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$TPT_GRADLE_ARGS_FILE"
case " $* " in
  *" integrationTest "*)
    echo "Cannot connect to the Docker daemon"
    exit 1
    ;;
esac
mkdir -p build/test-results/test
cat > build/test-results/test/TEST-test.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="unit"/></testsuite>
XML
GRADLE
  chmod +x "${fake_bin}/gradle"

  export TPT_GRADLE_ARGS_FILE="$args_file"
  PATH="${fake_bin}:$PATH"
  hash -r

  tp_select_and_run_portable_scope "$repo" "$log"

  tpt_assert_eq "selected" "$TP_TEST_SCOPE_STATUS" "unit Gradle task should keep portable scope selected"
  tpt_assert_eq "test" "$TP_TEST_SCOPE_SELECTED_TASKS_CSV" "environment-failing Gradle task should be excluded"
  tpt_assert_file_contains "$TP_TEST_SCOPE_EXCLUDED_COMMANDS_FILE" "integrationTest" "excluded Gradle task should be recorded"
  tpt_assert_file_contains "$TP_TEST_SCOPE_EXCLUDED_COMMANDS_FILE" "environment-assumption-failure" "excluded Gradle task should preserve reason"
  tpt_assert_eq "pass" "$TP_BASELINE_LAST_STATUS" "final selected Gradle run should pass"
}

case_gradle_task_detection_does_not_treat_git_or_bit_as_it_tasks() {
  local tmp repo tasks
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"

  mkdir -p "$repo/src/git/java" "$repo/src/bit/java" "$repo/src/it/java" "$repo/src/smokeIT/java"
  cat > "${repo}/build.gradle" <<'GRADLE'
plugins {}
// The word it in prose should not create an it task.
tasks.register('integrationTest', Test)
GRADLE

  tasks="$(tp_detect_gradle_test_tasks "$repo")"

  printf '%s\n' "$tasks" | grep -qx "test" || {
    echo "ASSERT failed: expected default test task" >&2
    return 1
  }
  printf '%s\n' "$tasks" | grep -qx "it" || {
    echo "ASSERT failed: expected explicit it source set" >&2
    return 1
  }
  printf '%s\n' "$tasks" | grep -qx "smokeIT" || {
    echo "ASSERT failed: expected smokeIT source set" >&2
    return 1
  }
  printf '%s\n' "$tasks" | grep -qx "integrationTest" || {
    echo "ASSERT failed: expected integrationTest build task" >&2
    return 1
  }
  if printf '%s\n' "$tasks" | grep -Eqx 'git|bit'; then
    echo "ASSERT failed: git/bit source sets must not be detected as test tasks: ${tasks}" >&2
    return 1
  fi
}

case_snapshot_original_tests_avoids_false_it_suffixes_and_pruned_trees() {
  local tmp repo snapshot
  tmp="$(tpt_mktemp_dir)"
  repo="${tmp}/repo"
  snapshot="${tmp}/snapshot"

  prepare_scope_env "$tmp"
  TP_ORIGINAL_EFFECTIVE_PATH="$repo"
  TP_ORIGINAL_TESTS_SNAPSHOT="$snapshot"
  TP_TEST_SCOPE_RUNNER="maven"
  TP_TEST_SCOPE_SELECTED_MAVEN_MODE="narrow"
  TP_TEST_SCOPE_SELECTED_TASKS_CSV=""

  mkdir -p \
    "$repo/src/test/java" \
    "$repo/src/it/java" \
    "$repo/src/git/java" \
    "$repo/src/bit/java" \
    "$repo/src/smokeIT/java" \
    "$repo/node_modules/pkg/src/test/java"
  echo "class UnitTest {}" > "$repo/src/test/java/UnitTest.java"
  echo "class DatabaseIT {}" > "$repo/src/it/java/DatabaseIT.java"
  echo "class GitHelper {}" > "$repo/src/git/java/GitHelper.java"
  echo "class BitHelper {}" > "$repo/src/bit/java/BitHelper.java"
  echo "class SmokeIT {}" > "$repo/src/smokeIT/java/SmokeIT.java"
  echo "class VendorTest {}" > "$repo/node_modules/pkg/src/test/java/VendorTest.java"

  tp_snapshot_original_tests

  tpt_assert_file_exists "$snapshot/src/test/java/UnitTest.java" "snapshot should include standard tests"
  tpt_assert_file_exists "$snapshot/src/it/java/DatabaseIT.java" "snapshot should keep integration-style tests even when the probe chose a narrow scope"
  tpt_assert_file_exists "$snapshot/src/smokeIT/java/SmokeIT.java" "snapshot should include explicit IT source sets"
  if [[ -e "$snapshot/src/git/java/GitHelper.java" || -e "$snapshot/src/bit/java/BitHelper.java" ]]; then
    echo "ASSERT failed: git/bit source sets must not be snapshotted as tests" >&2
    return 1
  fi
  if [[ -e "$snapshot/node_modules/pkg/src/test/java/VendorTest.java" ]]; then
    echo "ASSERT failed: pruned dependency trees must not be snapshotted" >&2
    return 1
  fi
}

tpt_run_case "maven uses workspace local repo" case_maven_uses_workspace_local_repo
tpt_run_case "gradle wrapper invocation unchanged" case_gradle_wrapper_invocation_unchanged
tpt_run_case "gradle invocation unchanged" case_gradle_invocation_unchanged
tpt_run_case "gradle full-suite run includes detected integration tasks" case_gradle_full_suite_runs_all_detected_test_tasks
tpt_run_case "unknown runner returns skip code" case_unknown_runner_returns_skipped_code
tpt_run_case "maven baseline unit-first skips full fallback on success" case_maven_baseline_uses_unit_first_and_skips_full_on_success
tpt_run_case "maven baseline fallback classifies environmental noise" case_maven_baseline_falls_back_and_classifies_environmental_noise
tpt_run_case "maven baseline fallback recovers from unit-only failure" case_maven_baseline_fallback_passes_after_unit_only_failure
tpt_run_case "classifier avoids generic error compatibility overfit" case_classifier_avoids_generic_error_as_compatibility
tpt_run_case "portable scope Maven selects broad passing command" case_portable_scope_maven_selects_broad_when_it_passes
tpt_run_case "portable scope Maven falls back to narrow command" case_portable_scope_maven_falls_back_to_narrow_after_environment_failure
tpt_run_case "portable scope Maven skips when no signal exists" case_portable_scope_maven_skips_when_no_portable_signal_exists
tpt_run_case "portable scope Gradle selects multiple passing tasks" case_portable_scope_gradle_selects_multiple_passing_tasks
tpt_run_case "portable scope Gradle excludes environment task" case_portable_scope_gradle_excludes_environment_task_but_keeps_unit_task
tpt_run_case "gradle task detection avoids false it suffixes" case_gradle_task_detection_does_not_treat_git_or_bit_as_it_tasks
tpt_run_case "snapshot avoids false it suffixes and pruned trees" case_snapshot_original_tests_avoids_false_it_suffixes_and_pruned_trees

tpt_finish_suite
