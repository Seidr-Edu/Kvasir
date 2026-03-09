#!/usr/bin/env bash
# tp_runner.sh - test command detection/execution and diagnostics helpers.

set -euo pipefail

tp_detect_test_runner() {
  local repo="$1"
  if [[ -f "$repo/pom.xml" ]]; then
    echo "maven"
  elif [[ -x "$repo/gradlew" ]]; then
    echo "gradle-wrapper"
  elif [[ -f "$repo/build.gradle" || -f "$repo/build.gradle.kts" ]]; then
    echo "gradle"
  else
    echo "unknown"
  fi
}

tp_test_rc_status() {
  local rc="$1"
  case "$rc" in
    0) echo "pass" ;;
    2) echo "skipped" ;;
    *) echo "fail" ;;
  esac
}

tp_clean_junit_outputs() {
  local repo="$1"
  rm -rf \
    "${repo}/target/surefire-reports" \
    "${repo}/target/failsafe-reports" \
    "${repo}/build/test-results" \
    >/dev/null 2>&1 || true
}

tp_maven_local_repo_path() {
  local repo="$1"
  echo "${TP_MAVEN_LOCAL_REPO:-${repo}/.m2/repository}"
}

tp_detect_test_source_dirs() {
  local repo="$1"
  local -a dirs=()

  # Standard locations
  for d in "$repo/src/test" "$repo/test" "$repo/tests"; do
    [[ -d "$d" ]] && dirs+=("$d")
  done
  # Non-standard Gradle source sets under src/ (e.g. src/jarFileTest, src/intTest)
  if [[ -d "$repo/src" ]]; then
    while IFS= read -r d; do
      [[ "$d" == "$repo/src/main" ]] && continue
      [[ "$d" == "$repo/src/test" ]] && continue
      dirs+=("$d")
    done < <(find "$repo/src" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
  fi

  printf '%s\n' "${dirs[@]+${dirs[@]}}"
}

tp_detect_gradle_test_task() {
  local repo="$1"

  # Standard layout: src/test/java has Java files → use default 'test' task
  if find "$repo/src/test" -name '*.java' -print -quit 2>/dev/null | grep -q .; then
    echo "test"
    return 0
  fi

  # Parse build.gradle / build.gradle.kts for declared source set or task names
  local custom_task=""
  for build_file in "$repo/build.gradle" "$repo/build.gradle.kts"; do
    [[ -f "$build_file" ]] || continue
    while IFS= read -r line; do
      # Match indented identifier followed by '{' — these are sourceSet declarations
      local name
      name="$(printf '%s' "$line" | grep -oE '^[[:space:]]+[A-Za-z][A-Za-z0-9_]+[[:space:]]*\{' | grep -oE '[A-Za-z][A-Za-z0-9_]+' | head -1 || true)"
      if [[ -n "$name" && "$name" != "main" && "$name" != "test" && "$name" != "java" && "$name" != "kotlin" ]]; then
        if printf '%s' "$name" | grep -qiE '(test|spec|it$|^it[A-Z]|integration|functional|e2e|acceptance|verification)'; then
          custom_task="$name"
          break
        fi
      fi
    done < "$build_file"
    [[ -n "$custom_task" ]] && break
  done

  if [[ -n "$custom_task" ]]; then
    echo "$custom_task"
    return 0
  fi

  # Fallback: first non-main/non-test src/ subdir that actually contains Java files
  if [[ -d "$repo/src" ]]; then
    while IFS= read -r src_dir; do
      local name="${src_dir##*/}"
      [[ "$name" == "main" || "$name" == "test" ]] && continue
      if find "$src_dir" -name '*.java' -print -quit 2>/dev/null | grep -q .; then
        echo "$name"
        return 0
      fi
    done < <(find "$repo/src" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
  fi

  echo "test"
}

tp_detect_test_frameworks() {
  local repo="$1"
  local found_junit5=false
  local found_junit4=false
  local found_testng=false
  local -a test_src_dirs=()

  while IFS= read -r d; do
    [[ -n "$d" ]] && test_src_dirs+=("$d")
  done < <(tp_detect_test_source_dirs "$repo")

  if [[ "${#test_src_dirs[@]}" -eq 0 ]]; then
    printf '%s' "unknown"
    return 0
  fi

  if LC_ALL=C grep -R -E -q --include='*.java' 'org\.junit\.jupiter|org\.opentest4j' "${test_src_dirs[@]}" 2>/dev/null; then
    found_junit5=true
  fi
  if LC_ALL=C grep -R -E -q --include='*.java' 'org\.junit\.Test|junit\.framework' "${test_src_dirs[@]}" 2>/dev/null; then
    found_junit4=true
  fi
  if LC_ALL=C grep -R -E -q --include='*.java' 'org\.testng\.' "${test_src_dirs[@]}" 2>/dev/null; then
    found_testng=true
  fi

  local -a frameworks=()
  $found_junit4 && frameworks+=("junit4")
  $found_junit5 && frameworks+=("junit5")
  $found_testng && frameworks+=("testng")
  if [[ "${#frameworks[@]}" -eq 0 ]]; then
    frameworks+=("unknown")
  fi

  local IFS=':'
  printf '%s' "${frameworks[*]}"
}

tp_preflight_runner() {
  local repo="$1"
  local module_subdir="${2:-}"
  local module_root="$repo"

  TP_RUNNER_PREFLIGHT_DETECTED_RUNNER="unknown"
  TP_RUNNER_PREFLIGHT_SUPPORTED=true
  TP_RUNNER_PREFLIGHT_MISSING_CAPABILITIES_CSV=""
  TP_RUNNER_PREFLIGHT_MODULE_ROOT="$repo"
  TP_RUNNER_PREFLIGHT_FRAMEWORKS_DETECTED_CSV="unknown"

  local -a missing=()

  if [[ -n "$module_subdir" ]]; then
    module_root="${repo}/${module_subdir}"
  fi
  TP_RUNNER_PREFLIGHT_MODULE_ROOT="$module_root"

  if [[ ! -d "$module_root" ]]; then
    missing+=("module-root-missing")
    TP_RUNNER_PREFLIGHT_SUPPORTED=false
  else
    TP_RUNNER_PREFLIGHT_DETECTED_RUNNER="$(tp_detect_test_runner "$module_root")"
    TP_RUNNER_PREFLIGHT_FRAMEWORKS_DETECTED_CSV="$(tp_detect_test_frameworks "$module_root")"

    case "$TP_RUNNER_PREFLIGHT_DETECTED_RUNNER" in
      maven)
        command -v mvn >/dev/null 2>&1 || {
          missing+=("maven-cli-missing")
          TP_RUNNER_PREFLIGHT_SUPPORTED=false
        }
        ;;
      gradle-wrapper)
        [[ -x "$module_root/gradlew" ]] || {
          missing+=("gradle-wrapper-missing")
          TP_RUNNER_PREFLIGHT_SUPPORTED=false
        }
        if [[ -f "$module_root/build.gradle" || -f "$module_root/build.gradle.kts" ]]; then
          if LC_ALL=C grep -Eiq 'test\s*\{[^}]*enabled\s*=\s*false|tasks\.named\(["'"'"']test["'"'"']\)\s*\{[^}]*enabled\s*=\s*false' "$module_root"/build.gradle* 2>/dev/null; then
            missing+=("gradle-test-task-disabled")
            TP_RUNNER_PREFLIGHT_SUPPORTED=false
          fi
        fi
        ;;
      gradle)
        command -v gradle >/dev/null 2>&1 || {
          missing+=("gradle-cli-missing")
          TP_RUNNER_PREFLIGHT_SUPPORTED=false
        }
        if [[ -f "$module_root/build.gradle" || -f "$module_root/build.gradle.kts" ]]; then
          if LC_ALL=C grep -Eiq 'test\s*\{[^}]*enabled\s*=\s*false|tasks\.named\(["'"'"']test["'"'"']\)\s*\{[^}]*enabled\s*=\s*false' "$module_root"/build.gradle* 2>/dev/null; then
            missing+=("gradle-test-task-disabled")
            TP_RUNNER_PREFLIGHT_SUPPORTED=false
          fi
        fi
        ;;
      *)
        missing+=("unsupported-test-runner")
        TP_RUNNER_PREFLIGHT_SUPPORTED=false
        ;;
    esac
  fi

  if [[ "${#missing[@]}" -gt 0 ]]; then
    local IFS=':'
    TP_RUNNER_PREFLIGHT_MISSING_CAPABILITIES_CSV="${missing[*]}"
  fi
}

tp_run_maven_test() {
  local repo="$1"
  local log_file="$2"
  shift 2

  local maven_local_repo
  maven_local_repo="$(tp_maven_local_repo_path "$repo")"
  mkdir -p "$maven_local_repo"
  (cd "$repo" && mvn -q "-Dmaven.repo.local=${maven_local_repo}" "$@") >"$log_file" 2>&1
}

tp_run_gradle_test() {
  local repo="$1"
  local log_file="$2"
  local runner="$3"
  local gradle_user_home tmp_dir test_task

  gradle_user_home="${TP_GRADLE_USER_HOME:-${repo}/.gradle}"
  tmp_dir="${TP_TMP_DIR:-${repo}/tmp}"
  test_task="$(tp_detect_gradle_test_task "$repo")"
  mkdir -p "$gradle_user_home" "$tmp_dir"

  if [[ "$runner" == "gradle-wrapper" ]]; then
    (cd "$repo" && env "GRADLE_USER_HOME=$gradle_user_home" "TMPDIR=$tmp_dir" ./gradlew "$test_task" --no-daemon) >"$log_file" 2>&1
  else
    (cd "$repo" && env "GRADLE_USER_HOME=$gradle_user_home" "TMPDIR=$tmp_dir" gradle "$test_task" --no-daemon) >"$log_file" 2>&1
  fi
}

tp_run_tests() {
  local repo="$1"
  local log_file="$2"
  local runner
  runner="$(tp_detect_test_runner "$repo")"
  local had_errexit=false
  [[ $- == *e* ]] && had_errexit=true

  mkdir -p "$(dirname "$log_file")"
  tp_clean_junit_outputs "$repo"

  set +e
  case "$runner" in
    maven) tp_run_maven_test "$repo" "$log_file" test ;;
    gradle-wrapper|gradle) tp_run_gradle_test "$repo" "$log_file" "$runner" ;;
    *)
      echo "unsupported test runner" >"$log_file"
      $had_errexit && set -e || set +e
      return 2
      ;;
  esac
  local rc=$?
  $had_errexit && set -e || set +e
  return "$rc"
}

tp_collect_execution_summary() {
  local repo="$1"
  local log_file="$2"
  local prefix="$3"

  eval "$(python3 - <<'PY' "$repo" "$log_file" "$prefix"
import glob
import os
import re
import shlex
import sys
import xml.etree.ElementTree as ET

repo, log_file, prefix = sys.argv[1:]

patterns = [
    "target/surefire-reports/*.xml",
    "target/failsafe-reports/*.xml",
    "build/test-results/test/*.xml",
    "build/test-results/**/*.xml",
]

report_files = []
seen = set()
for pat in patterns:
    for path in glob.glob(os.path.join(repo, pat), recursive=True):
        if not os.path.isfile(path) or not path.lower().endswith(".xml"):
            continue
        if path in seen:
            continue
        seen.add(path)
        report_files.append(path)

report_files.sort()

executed = 0
failed = 0
errors = 0
skipped = 0

for report_path in report_files:
    try:
        root = ET.parse(report_path).getroot()
    except Exception:
        continue

    root_tests = root.attrib.get("tests")
    root_failures = root.attrib.get("failures")
    root_errors = root.attrib.get("errors")
    root_skipped = root.attrib.get("skipped")

    if root_tests is not None:
        try:
            executed += int(root_tests)
        except Exception:
            pass
    if root_failures is not None:
        try:
            failed += int(root_failures)
        except Exception:
            pass
    if root_errors is not None:
        try:
            errors += int(root_errors)
        except Exception:
            pass
    if root_skipped is not None:
        try:
            skipped += int(root_skipped)
        except Exception:
            pass

if executed == 0 and report_files:
    # Fallback for non-standard XML that omits root counters.
    for report_path in report_files:
        try:
            root = ET.parse(report_path).getroot()
        except Exception:
            continue
        for tc in root.iter("testcase"):
            executed += 1
            has_failure = False
            has_error = False
            has_skipped = False
            for child in list(tc):
                tag = child.tag.lower()
                if tag == "failure":
                    has_failure = True
                elif tag == "error":
                    has_error = True
                elif tag in {"skipped", "ignore"}:
                    has_skipped = True
            if has_failure:
                failed += 1
            if has_error:
                errors += 1
            if has_skipped:
                skipped += 1

if executed == 0 and os.path.isfile(log_file):
    with open(log_file, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.search(r"Tests run:\s*(\d+)\s*,\s*Failures:\s*(\d+)\s*,\s*Errors:\s*(\d+)\s*,\s*Skipped:\s*(\d+)", line)
            if m:
                executed += int(m.group(1))
                failed += int(m.group(2))
                errors += int(m.group(3))
                skipped += int(m.group(4))
                continue
            g = re.search(r"(\d+)\s+tests completed(?:,\s*(\d+)\s+failed)?(?:,\s*(\d+)\s+skipped)?", line, re.IGNORECASE)
            if g:
                executed += int(g.group(1))
                failed += int(g.group(2) or "0")
                skipped += int(g.group(3) or "0")

discovered = executed

assignments = {
    f"{prefix}_TESTS_DISCOVERED": discovered,
    f"{prefix}_TESTS_EXECUTED": executed,
    f"{prefix}_TESTS_FAILED": failed,
    f"{prefix}_TESTS_ERRORS": errors,
    f"{prefix}_TESTS_SKIPPED": skipped,
    f"{prefix}_JUNIT_REPORTS_FOUND": len(report_files),
}

for key, value in assignments.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
  )"
}

tp_failure_class_to_legacy() {
  local failure_class="$1"
  case "$failure_class" in
    dependency-resolution-failure) echo "environmental-build" ;;
    compilation-failure) echo "compatibility-build" ;;
    assertion-failure) echo "behavioral-mismatch" ;;
    test-launcher-crash|runtime-test-failure) echo "runtime-test-failure" ;;
    *) echo "unknown" ;;
  esac
}

tp_baseline_failure_type_from_class() {
  local failure_class="$1"
  case "$failure_class" in
    dependency-resolution-failure) echo "environmental-noise" ;;
    compilation-failure) echo "compatibility" ;;
    assertion-failure) echo "behavioral" ;;
    test-launcher-crash|runtime-test-failure) echo "runtime" ;;
    *) echo "unknown" ;;
  esac
}

tp_infer_baseline_failure_type() {
  local unit_class="$1"
  local full_class="$2"
  local unit_rc="$3"
  local full_rc="$4"

  if [[ "$full_rc" -eq 0 ]]; then
    echo ""
    return 0
  fi

  if [[ "$unit_rc" -eq 0 && "$full_rc" -ne 0 ]]; then
    echo "environmental-noise"
    return 0
  fi

  case "$full_class" in
    dependency-resolution-failure)
      echo "environmental-noise"
      return 0
      ;;
    compilation-failure)
      echo "compatibility"
      return 0
      ;;
    assertion-failure)
      echo "behavioral"
      return 0
      ;;
    test-launcher-crash|runtime-test-failure)
      case "$unit_class" in
        dependency-resolution-failure|test-launcher-crash|runtime-test-failure|unknown) echo "environmental-noise" ;;
        *) echo "runtime" ;;
      esac
      return 0
      ;;
  esac

  case "$unit_class" in
    dependency-resolution-failure) echo "environmental-noise" ;;
    compilation-failure) echo "compatibility" ;;
    assertion-failure) echo "behavioral" ;;
    test-launcher-crash|runtime-test-failure) echo "runtime" ;;
    *) echo "unknown" ;;
  esac
}

tp_extract_first_failure_line() {
  local log_file="$1"
  [[ -f "$log_file" ]] || { echo ""; return 0; }

  local line
  line="$(LC_ALL=C grep -n -m1 -E 'COMPILATION ERROR|cannot find symbol|Assertion(Error|FailedError)|expected:<|BUILD FAILED|FAILURE: Build failed|Failed to execute goal|Exception|\[ERROR\]' "$log_file" || true)"
  if [[ -n "$line" ]]; then
    printf '%s' "$line"
    return 0
  fi

  line="$(LC_ALL=C grep -n -m1 -v '^\s*$' "$log_file" || true)"
  printf '%s' "$line"
}

tp_write_failure_excerpt() {
  local log_file="$1"
  local excerpt_file="$2"
  local max_lines="${3:-200}"

  : > "$excerpt_file"
  [[ -f "$log_file" ]] || return 0
  tail -n "$max_lines" "$log_file" > "$excerpt_file" || true
}

tp_classify_test_failure_log() {
  local log_file="$1"
  [[ -f "$log_file" ]] || {
    TP_LAST_FAILURE_CLASS="unknown"
    TP_LAST_FAILURE_PHASE="unknown"
    TP_LAST_FAILURE_SUBCLASS="unknown"
    TP_LAST_FAILURE_CLASS_LEGACY="unknown"
    TP_LAST_FAILURE_FIRST_LINE=""
    echo "unknown"
    return 0
  }

  local class="unknown"
  local phase="unknown"
  local subclass="unknown"

  if LC_ALL=C grep -Eiq \
    'Non-resolvable parent POM|Could not transfer artifact|Could not find artifact|Could not resolve (dependencies|artifact)|Unknown host|No such host|Connection refused|Connection timed out|Read timed out|Temporary failure in name resolution|nodename nor servname provided|PKIX path building failed|Network is unreachable|No route to host|Failed to connect to' \
    "$log_file"; then
    class="dependency-resolution-failure"
    phase="dependency-resolution"
    subclass="dependency-resolution-failure"
  elif LC_ALL=C grep -Eiq \
    'COMPILATION ERROR|cannot find symbol|package [^ ]+ does not exist|error: cannot find symbol|error: package [^ ]+ does not exist|error: incompatible types|Execution failed for task .*compile(Test|Java|Kotlin)|Compilation failed|Could not compile' \
    "$log_file"; then
    class="compilation-failure"
    phase="compile"
    subclass="compilation-failure"
  elif LC_ALL=C grep -Eiq \
    'Assertion(Error|FailedError)|ComparisonFailure|org\.opentest4j\.AssertionFailedError|expected:<.*> but was:<.*>|There were test failures|Tests run: .*Failures: [1-9]' \
    "$log_file"; then
    class="assertion-failure"
    phase="assertion"
    subclass="assertion-failure"
  elif LC_ALL=C grep -Eiq \
    'SurefireBooterForkException|forked VM terminated|The forked VM terminated|Failed to execute goal .*surefire|No tests were executed|TestEngine with ID .* failed to discover tests|Could not find or load main class org\.gradle' \
    "$log_file"; then
    class="test-launcher-crash"
    phase="test-launch"
    subclass="test-launcher-crash"
  elif LC_ALL=C grep -Eiq \
    'Tests run: .*Errors: [1-9]|BUILD FAILED|FAILURE: Build failed' \
    "$log_file"; then
    class="runtime-test-failure"
    phase="runtime"
    subclass="runtime-test-failure"
  fi

  TP_LAST_FAILURE_PHASE="$phase"
  TP_LAST_FAILURE_SUBCLASS="$subclass"
  TP_LAST_FAILURE_CLASS_LEGACY="$(tp_failure_class_to_legacy "$class")"
  TP_LAST_FAILURE_CLASS="$class"
  TP_LAST_FAILURE_FIRST_LINE="$(tp_extract_first_failure_line "$log_file")"
  echo "$class"
}

tp_run_baseline_tests() {
  local repo="$1"
  local log_file="$2"
  local runner
  runner="$(tp_detect_test_runner "$repo")"
  local had_errexit=false
  [[ $- == *e* ]] && had_errexit=true
  local rc=0
  local unit_rc=0
  local full_rc=0
  local unit_log=""
  local full_log=""
  local unit_class=""
  local full_class=""

  mkdir -p "$(dirname "$log_file")"
  tp_clean_junit_outputs "$repo"

  TP_BASELINE_LAST_STRATEGY="single-run"
  TP_BASELINE_LAST_STATUS="skipped"
  TP_BASELINE_LAST_UNIT_ONLY_RC=-1
  TP_BASELINE_LAST_FULL_RC=-1
  TP_BASELINE_LAST_FAILURE_CLASS=""
  TP_BASELINE_LAST_FAILURE_CLASS_LEGACY=""
  TP_BASELINE_LAST_FAILURE_TYPE=""
  TP_BASELINE_LAST_FAILURE_PHASE=""
  TP_BASELINE_LAST_FAILURE_SUBCLASS=""
  TP_BASELINE_LAST_FAILURE_FIRST_LINE=""

  set +e
  case "$runner" in
    maven)
      TP_BASELINE_LAST_STRATEGY="maven-unit-first-fallback-full"
      unit_log="${log_file}.unit-only.log"
      full_log="${log_file}.full.log"

      tp_run_maven_test "$repo" "$unit_log" \
        "-DskipITs" "-DskipIT=true" "-DskipIntegrationTests=true" \
        "-DexcludedGroups=integration,IntegrationTest" \
        test
      unit_rc=$?
      TP_BASELINE_LAST_UNIT_ONLY_RC="$unit_rc"

      if [[ "$unit_rc" -eq 0 ]]; then
        cp "$unit_log" "$log_file"
        TP_BASELINE_LAST_STATUS="pass"
        $had_errexit && set -e || set +e
        return 0
      fi

      tp_run_maven_test "$repo" "$full_log" test
      full_rc=$?
      TP_BASELINE_LAST_FULL_RC="$full_rc"

      {
        printf '=== baseline unit-only run (integration-skip flags) rc=%s ===\n' "$unit_rc"
        cat "$unit_log"
        printf '\n=== baseline full test fallback rc=%s ===\n' "$full_rc"
        cat "$full_log"
      } >"$log_file"

      if [[ "$full_rc" -eq 0 ]]; then
        TP_BASELINE_LAST_STATUS="pass"
        TP_BASELINE_LAST_FAILURE_CLASS=""
        TP_BASELINE_LAST_FAILURE_CLASS_LEGACY=""
        TP_BASELINE_LAST_FAILURE_TYPE=""
        $had_errexit && set -e || set +e
        return 0
      fi

      tp_classify_test_failure_log "$unit_log" >/dev/null
      unit_class="${TP_LAST_FAILURE_CLASS:-unknown}"
      tp_classify_test_failure_log "$full_log" >/dev/null
      full_class="${TP_LAST_FAILURE_CLASS:-unknown}"
      TP_BASELINE_LAST_FAILURE_CLASS="$full_class"
      TP_BASELINE_LAST_FAILURE_CLASS_LEGACY="$TP_LAST_FAILURE_CLASS_LEGACY"
      TP_BASELINE_LAST_FAILURE_PHASE="$TP_LAST_FAILURE_PHASE"
      TP_BASELINE_LAST_FAILURE_SUBCLASS="$TP_LAST_FAILURE_SUBCLASS"
      TP_BASELINE_LAST_FAILURE_FIRST_LINE="$TP_LAST_FAILURE_FIRST_LINE"
      TP_BASELINE_LAST_FAILURE_TYPE="$(tp_infer_baseline_failure_type "$unit_class" "$full_class" "$unit_rc" "$full_rc")"
      TP_BASELINE_LAST_STATUS="fail-with-integration-skip"
      $had_errexit && set -e || set +e
      return "$full_rc"
      ;;
    gradle-wrapper|gradle)
      tp_run_gradle_test "$repo" "$log_file" "$runner"
      rc=$?
      ;;
    *)
      echo "unsupported test runner" >"$log_file"
      TP_BASELINE_LAST_STATUS="skipped"
      $had_errexit && set -e || set +e
      return 2
      ;;
  esac

  TP_BASELINE_LAST_STATUS="$(tp_test_rc_status "$rc")"
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
    tp_classify_test_failure_log "$log_file" >/dev/null
    TP_BASELINE_LAST_FAILURE_CLASS="${TP_LAST_FAILURE_CLASS:-unknown}"
    TP_BASELINE_LAST_FAILURE_CLASS_LEGACY="$TP_LAST_FAILURE_CLASS_LEGACY"
    TP_BASELINE_LAST_FAILURE_PHASE="$TP_LAST_FAILURE_PHASE"
    TP_BASELINE_LAST_FAILURE_SUBCLASS="$TP_LAST_FAILURE_SUBCLASS"
    TP_BASELINE_LAST_FAILURE_FIRST_LINE="$TP_LAST_FAILURE_FIRST_LINE"
    TP_BASELINE_LAST_FAILURE_TYPE="$(tp_baseline_failure_type_from_class "$TP_BASELINE_LAST_FAILURE_CLASS")"
  fi

  $had_errexit && set -e || set +e
  return "$rc"
}
