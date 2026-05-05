#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURES_DIR="${SCRIPT_DIR}/fixtures"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"

setup_fake_tools() {
  local root="$1"
  local fake_bin="${root}/bin"
  mkdir -p "$fake_bin"

  cat > "${fake_bin}/adapter_mutate_fixture.sh" <<'ADAPTER'
#!/usr/bin/env bash
set -euo pipefail

scenario="${1:-}"
call_no="${2:-1}"

case "$scenario" in
  ignored-writes)
    mkdir -p completion/proof/logs .mvn_repo/runtime src/test/java
    printf 'replayed\n' >> completion/proof/logs/hard-repo-compliance.log
    printf 'cache\n' > .mvn_repo/runtime/dependency.txt
    printf '// adapted\n' >> src/test/java/OriginalFixtureTest.java
    ;;
  prod-write)
    mkdir -p src/main/java
    printf '// disallowed\n' >> src/main/java/Prod.java
    ;;
  undocumented-removal)
    rm -f src/test/java/OriginalFixtureTest.java
    ;;
  invalid-removal-reason)
    mkdir -p completion/proof/logs
    rm -f src/test/java/OriginalFixtureTest.java
    printf './src/test/java/OriginalFixtureTest.java\tunknown\tna\n' > completion/proof/logs/test-port-removed-tests.tsv
    ;;
  maximize-retention)
    mkdir -p completion/proof/logs src/test/java
    if [[ "$call_no" -eq 1 ]]; then
      rm -f src/test/java/OriginalFixtureTest.java
      printf './src/test/java/OriginalFixtureTest.java\tunportable\ttemporary compatibility mismatch\n' > completion/proof/logs/test-port-removed-tests.tsv
    else
      cat > src/test/java/OriginalFixtureTest.java <<'JAVA'
class OriginalFixtureTest {}
JAVA
      : > completion/proof/logs/test-port-removed-tests.tsv
    fi
    ;;
  behavioral-evidence)
    :
    ;;
  *)
    ;;
esac
ADAPTER

  cat > "${fake_bin}/codex" <<'CODEX'
#!/usr/bin/env bash
set -euo pipefail

increment_call_counter() {
  local counter_file="${TPT_CODEX_CALL_COUNT_FILE:-}"
  if [[ -z "$counter_file" ]]; then
    echo 1
    return 0
  fi
  local current=0
  if [[ -f "$counter_file" ]]; then
    current="$(cat "$counter_file" 2>/dev/null || echo 0)"
  fi
  current=$((current + 1))
  printf '%s\n' "$current" > "$counter_file"
  printf '%s\n' "$current"
}

subcommand="${1:-}"
case "$subcommand" in
  login)
    if [[ "${2:-}" == "status" ]]; then
      exit 0
    fi
    ;;
  exec)
    shift
    output_last=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --output-last-message)
          output_last="${2:-}"
          shift 2
          ;;
        --add-dir)
          shift 2
          ;;
        --cd)
          shift 2
          ;;
        --json|--skip-git-repo-check|--dangerously-bypass-approvals-and-sandbox|-)
          shift
          ;;
        *)
          shift
          ;;
      esac
    done

    if [[ -n "$output_last" ]]; then
      printf 'fake adapter message\n' > "$output_last"
    fi

    call_no="$(increment_call_counter)"

    adapter_mutate_fixture.sh "${TPT_ADAPTER_SCENARIO:-}" "$call_no"

    printf '%s\n' '{"type":"response.output_text","text":"ok"}'
    exit 0
    ;;
esac

printf 'unsupported fake codex invocation\n' >&2
exit 1
CODEX

cat > "${fake_bin}/claude" <<'CLAUDE'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--version" ]]; then
  printf 'claude-fake 1.0.0\n'
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dangerously-skip-permissions)
      shift
      ;;
    --print)
      break
      ;;
    *)
      break
      ;;
  esac
done

if [[ "${1:-}" == "--print" ]]; then
  call_no_file="${TPT_CLAUDE_CALL_COUNT_FILE:-}"
  call_no=1
  if [[ -n "$call_no_file" ]]; then
    if [[ -f "$call_no_file" ]]; then
      call_no="$(cat "$call_no_file" 2>/dev/null || echo 0)"
      call_no=$((call_no + 1))
    fi
    printf '%s\n' "$call_no" > "$call_no_file"
  fi

  adapter_mutate_fixture.sh "${TPT_ADAPTER_SCENARIO:-}" "$call_no"
  printf 'fake adapter message\n'
  exit 0
fi

printf 'unsupported fake claude invocation\n' >&2
exit 1
CLAUDE

  cat > "${fake_bin}/mvn" <<'MVN'
#!/usr/bin/env bash
set -euo pipefail

repo_local=""
for arg in "$@"; do
  case "$arg" in
    -Dmaven.repo.local=*) repo_local="${arg#*=}" ;;
  esac
done

if [[ -z "$repo_local" ]]; then
  printf 'missing maven.repo.local\n' >&2
  exit 12
fi

mkdir -p "$repo_local" target/surefire-reports
printf 'downloaded\n' > "$repo_local/dependency.txt"
case "${TPT_ADAPTER_SCENARIO:-}" in
  zero-junit)
    printf 'BUILD SUCCESS\n'
    exit 0
    ;;
  behavioral-evidence)
    case "${PWD:-}" in
      *original-baseline-repo|*generated-baseline-repo)
        if [[ "$*" == *"-DskipITs"* ]]; then
          cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
          exit 0
        fi
        echo "Connection refused"
        exit 1
        ;;
    esac
    cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="1" errors="0">
  <testcase classname="fake.behavior" name="detectDifference">
    <failure message="expected:&lt;1&gt; but was:&lt;2&gt;">AssertionFailedError</failure>
  </testcase>
</testsuite>
XML
    printf 'COMPILATION ERROR\n'
    printf 'AssertionFailedError: expected:<1> but was:<2>\n'
    exit 1
    ;;
  *)
    cat > target/surefire-reports/TEST-fake.xml <<'XML'
<testsuite tests="1" failures="0" errors="0"><testcase classname="fake" name="ok"/></testsuite>
XML
    exit 0
    ;;
esac
MVN

  chmod +x "${fake_bin}/adapter_mutate_fixture.sh" "${fake_bin}/codex" "${fake_bin}/claude" "${fake_bin}/mvn"

  export PATH="${fake_bin}:$PATH"
  export CODEX_HOME="${root}/codex-home"
  mkdir -p "${CODEX_HOME}/sessions"
}

prepare_fixture_repos() {
  local root="$1"
  local original_repo="${root}/original"
  local generated_repo="${root}/generated"

  cp -R "${FIXTURES_DIR}/original_repo" "$original_repo"
  cp -R "${FIXTURES_DIR}/generated_repo" "$generated_repo"

  printf '%s\t%s\n' "$original_repo" "$generated_repo"
}

run_test_port_case() {
  local scenario="$1"
  local root="$2"
  local max_iter="${3:-0}"
  local adapter="${4:-codex}"

  local original_repo generated_repo run_dir json_path
  IFS=$'\t' read -r original_repo generated_repo < <(prepare_fixture_repos "$root")
  if [[ "$scenario" == "behavioral-evidence" ]]; then
    cat > "${original_repo}/src/test/java/DatabaseIT.java" <<'JAVA'
class DatabaseIT {}
JAVA
  fi
  run_dir="${root}/run"
  json_path="${run_dir}/outputs/test_port.json"

  export TPT_ADAPTER_SCENARIO="$scenario"
  export TPT_CODEX_CALL_COUNT_FILE="${root}/codex-call-count.txt"
  export TPT_CLAUDE_CALL_COUNT_FILE="${root}/claude-call-count.txt"
  printf '0\n' > "$TPT_CODEX_CALL_COUNT_FILE"
  printf '0\n' > "$TPT_CLAUDE_CALL_COUNT_FILE"

  "${TOOL_ROOT}/test-port-run.sh" \
    --generated-repo "$generated_repo" \
    --original-repo "$original_repo" \
    --run-dir "$run_dir" \
    --adapter "$adapter" \
    --max-iter "$max_iter" \
    > "${root}/test-port.log" 2>&1

  tpt_assert_file_exists "$json_path" "test-port json output must exist"

  printf '%s\t%s\n' "$json_path" "$run_dir"
}

case_claude_adapter_path_passes() {
  local tmp json_path
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path _ < <(run_test_port_case "ignored-writes" "$tmp" 0 "claude")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "passed":
    raise SystemExit(f"expected passed status, got {obj.get('result', {}).get('status')}")
if obj.get("inputs", {}).get("adapter") != "claude":
    raise SystemExit(f"expected claude adapter in report, got {obj.get('inputs', {}).get('adapter')}")
PY
}

case_ignored_runtime_writes_do_not_fail() {
  local tmp json_path run_dir
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path run_dir < <(run_test_port_case "ignored-writes" "$tmp")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "passed":
    raise SystemExit(f"expected passed status, got {obj.get('result')}")
if obj.get("diagnostics", {}).get("write_scope", {}).get("violation_count") != 0:
    raise SystemExit(f"expected zero violations, got {obj.get('diagnostics', {}).get('write_scope', {}).get('violation_count')}")
ignored = obj.get("diagnostics", {}).get("write_scope", {}).get("ignored_prefixes", [])
for expected in ("./completion/proof/logs/", "./.mvn_repo/", "./.m2/"):
    if expected not in ignored:
        raise SystemExit(f"missing ignored prefix: {expected}")
PY

  tpt_assert_file_exists "${run_dir}/artifacts/ported-tests-repo/src/test/java/OriginalFixtureTest.java" "final ported repo should be promoted to a canonical artifact"
  if [[ -e "${run_dir}/workspace/.m2" ]]; then
    echo "ASSERT failed: temporary maven cache should be cleaned after the run" >&2
    return 1
  fi
}

case_disallowed_source_write_fails() {
  local tmp json_path
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path _ < <(run_test_port_case "prod-write" "$tmp")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "failed":
    raise SystemExit(f"expected failed status, got {obj.get('result')}")
if obj.get("result", {}).get("reason") != "write-scope-violation":
    raise SystemExit(f"expected write-scope-violation reason, got {obj.get('result')}")
violations = obj.get("diagnostics", {}).get("write_scope", {}).get("violations", [])
paths = [item.get("path", "") for item in violations]
if "./src/main/java/Prod.java" not in paths:
    raise SystemExit(f"expected ./src/main/java/Prod.java violation, got {paths}")
PY
}

case_zero_junit_reports_emits_no_signal() {
  local tmp json_path
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path _ < <(run_test_port_case "zero-junit" "$tmp")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "skipped":
    raise SystemExit(f"expected skipped status, got {obj.get('result')}")
if obj.get("result", {}).get("reason") != "no-test-signal":
    raise SystemExit(f"expected no-test-signal reason, got {obj.get('result')}")
if obj.get("result", {}).get("verdict") != "no_test_signal":
    raise SystemExit(f"expected no_test_signal verdict, got {obj.get('result')}")
PY
}

case_undocumented_removed_test_fails_evidence_guard() {
  local tmp json_path
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path _ < <(run_test_port_case "undocumented-removal" "$tmp")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "failed":
    raise SystemExit(f"expected failed status, got {obj.get('result')}")
if obj.get("result", {}).get("reason") != "retention-policy-violation":
  raise SystemExit(f"expected retention-policy-violation reason, got {obj.get('result')}")
if obj.get("result", {}).get("failure_class") != "invalid-removal-documentation":
  raise SystemExit(f"expected invalid-removal-documentation, got {obj.get('result')}")
retention = obj.get("evidence", {}).get("retention", {})
removed = retention.get("removed_tests", [])
if not removed or removed[0].get("documented") is not False:
    raise SystemExit(f"expected undocumented removed tests, got {removed}")
if retention.get("undocumented_removed_test_count", 0) < 1:
    raise SystemExit("expected undocumented removed test count >= 1")
PY
}

case_invalid_reason_code_fails_retention_policy() {
  local tmp json_path
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path _ < <(run_test_port_case "invalid-removal-reason" "$tmp")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
  obj = json.load(f)
if obj.get("result", {}).get("status") != "failed":
  raise SystemExit(f"expected failed status, got {obj.get('result')}")
if obj.get("result", {}).get("reason") != "retention-policy-violation":
  raise SystemExit(f"expected retention-policy-violation reason, got {obj.get('result')}")
if obj.get("result", {}).get("failure_class") != "invalid-removal-documentation":
  raise SystemExit(f"expected invalid-removal-documentation, got {obj.get('result')}")
removed = obj.get("evidence", {}).get("retention", {}).get("removed_tests", [])
if not removed:
  raise SystemExit("expected removed test entries")
if removed[0].get("documented") is not False:
  raise SystemExit(f"expected invalid documentation flag, got {removed[0]}")
PY
}

case_retention_maximization_selects_best_iteration() {
  local tmp json_path
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path _ < <(run_test_port_case "maximize-retention" "$tmp" 1)

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "passed":
    raise SystemExit(f"expected passed status, got {obj.get('result')}")
ported = obj.get("porting", {})
if ported.get("iterations_used") != 1:
    raise SystemExit(f"expected best iteration 1, got {ported.get('iterations_used')}")
shape = obj.get("evidence", {}).get("retention", {})
if shape.get("removed_original_test_file_count") != 0:
    raise SystemExit(f"expected zero removed original tests, got {shape}")
if shape.get("retained_original_test_file_count") != shape.get("original_snapshot_file_count"):
    raise SystemExit(f"expected full retention, got {shape}")
PY
}

case_verdict_prefers_junit_evidence_over_compatibility_class() {
  local tmp json_path run_dir
  tmp="$(tpt_mktemp_dir)"

  setup_fake_tools "$tmp"
  IFS=$'\t' read -r json_path run_dir < <(run_test_port_case "behavioral-evidence" "$tmp")

  python3 - <<'PY' "$json_path"
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    obj = json.load(f)
if obj.get("result", {}).get("status") != "failed":
    raise SystemExit(f"expected failed status, got {obj.get('result')}")
if obj.get("result", {}).get("reason") != "tests-failed":
    raise SystemExit(f"expected tests-failed reason, got {obj.get('result')}")
if obj.get("result", {}).get("failure_class") != "compilation-failure":
    raise SystemExit(f"expected compilation-failure classifier, got {obj.get('result')}")
if obj.get("result", {}).get("verdict") != "difference_detected":
    raise SystemExit(f"expected difference_detected verdict, got {obj.get('result')}")
if obj.get("evidence", {}).get("behavioral", {}).get("failing_case_count", 0) < 1:
    raise SystemExit("expected junit failing_case_count >= 1")
baseline = obj.get("baselines", {}).get("original", {})
if baseline.get("status") != "pass":
    raise SystemExit(f"expected selected portable original baseline pass, got {baseline}")
scope = obj.get("test_scope", {})
if not scope.get("excluded_commands"):
    raise SystemExit(f"expected environment-excluded scope command, got {scope}")
if scope["excluded_commands"][0].get("failure_class") != "environment-assumption-failure":
    raise SystemExit(f"expected environment-assumption-failure exclusion, got {scope}")
if baseline.get("failure", {}).get("type") not in ("", None):
    raise SystemExit(f"expected baseline environmental-noise failure type, got {baseline}")
PY

  if [[ ! -e "${run_dir}/artifacts/ported-tests-repo/src/test/java/DatabaseIT.java" ]]; then
    echo "ASSERT failed: DatabaseIT.java should be attempted in the promoted full-suite ported repo" >&2
    return 1
  fi
}

tpt_run_case "ignored runtime writes do not fail write-scope" case_ignored_runtime_writes_do_not_fail
tpt_run_case "disallowed source writes fail write-scope" case_disallowed_source_write_fails
tpt_run_case "zero junit reports emit no-test-signal" case_zero_junit_reports_emits_no_signal
tpt_run_case "undocumented removed test fails evidence guard" case_undocumented_removed_test_fails_evidence_guard
tpt_run_case "invalid reason code fails retention policy" case_invalid_reason_code_fails_retention_policy
tpt_run_case "retention maximization selects best iteration" case_retention_maximization_selects_best_iteration
tpt_run_case "verdict prefers junit evidence over compatibility classifier" case_verdict_prefers_junit_evidence_over_compatibility_class
tpt_run_case "claude adapter path executes successfully" case_claude_adapter_path_passes

tpt_finish_suite
