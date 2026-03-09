#!/usr/bin/env bash

set -euo pipefail

SERVICE_TESTLIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_TESTLIB_FIXTURES_DIR="$(cd "${SERVICE_TESTLIB_DIR}/.." && pwd)/fixtures"

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
        --json|--skip-git-repo-check|--full-auto|-)
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
          echo "Connection refused"
          exit 1
        fi
        echo "Non-resolvable parent POM"
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

  cp -R "${SERVICE_TESTLIB_FIXTURES_DIR}/original_repo" "$original_repo"
  cp -R "${SERVICE_TESTLIB_FIXTURES_DIR}/generated_repo" "$generated_repo"

  printf '%s\t%s\n' "$original_repo" "$generated_repo"
}
