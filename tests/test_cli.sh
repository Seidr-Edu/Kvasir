#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/testlib.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_common.sh"
# shellcheck source=/dev/null
source "${TOOL_ROOT}/scripts/lib/tp_cli.sh"

create_minimal_repos() {
  local root="$1"
  mkdir -p "${root}/generated" "${root}/original/src/test/java"
  cat > "${root}/generated/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>gen</artifactId><version>1</version></project>
XML
  cat > "${root}/original/pom.xml" <<'XML'
<project><modelVersion>4.0.0</modelVersion><groupId>x</groupId><artifactId>orig</artifactId><version>1</version></project>
XML
  echo "class X {}" > "${root}/original/src/test/java/ExampleTest.java"
}

case_defaults_include_builtins() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  unset TP_WRITE_SCOPE_IGNORE_PREFIXES || true
  tp_parse_args \
    --generated-repo "${tmp}/generated" \
    --original-repo "${tmp}/original" \
    --adapter codex \
    --run-dir "${tmp}/run"
  tp_validate_and_finalize_args

  local expected_maven_repo
  expected_maven_repo="$(tp_abs_path "${tmp}/run/workspace/.m2/repository")"
  tpt_assert_eq "./completion/proof/logs/:./.mvn_repo/:./.m2/:./.gradle/:./target/:./build/" "$TP_WRITE_SCOPE_IGNORED_PREFIXES_CSV" "built-in ignored prefixes must be present"
  tpt_assert_eq "$expected_maven_repo" "$TP_MAVEN_LOCAL_REPO" "maven local repo must be pinned to run workspace"
}

case_env_cli_normalization_and_dedupe() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  TP_WRITE_SCOPE_IGNORE_PREFIXES="completion//proof/logs/:custom/cache:./custom/cache/"
  tp_parse_args \
    --generated-repo "${tmp}/generated" \
    --original-repo "${tmp}/original" \
    --adapter codex \
    --run-dir "${tmp}/run" \
    --write-scope-ignore-prefix ./.mvn_repo \
    --write-scope-ignore-prefix tmp//artifacts/
  tp_validate_and_finalize_args

  tpt_assert_eq "./completion/proof/logs/:./.mvn_repo/:./.m2/:./.gradle/:./target/:./build/:./custom/cache/:./tmp/artifacts/" "$TP_WRITE_SCOPE_IGNORED_PREFIXES_CSV" "resolved ignored prefixes must normalize and deduplicate"
}

case_rejects_absolute_prefix() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  if (
    unset TP_WRITE_SCOPE_IGNORE_PREFIXES || true
    tp_parse_args \
      --generated-repo "${tmp}/generated" \
      --original-repo "${tmp}/original" \
      --adapter codex \
      --run-dir "${tmp}/run" \
      --write-scope-ignore-prefix /absolute/path
    tp_validate_and_finalize_args
  ); then
    echo "expected absolute prefix validation to fail" >&2
    return 1
  fi
}

case_rejects_parent_traversal_prefix() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  if (
    TP_WRITE_SCOPE_IGNORE_PREFIXES="../outside"
    tp_parse_args \
      --generated-repo "${tmp}/generated" \
      --original-repo "${tmp}/original" \
      --adapter codex \
      --run-dir "${tmp}/run"
    tp_validate_and_finalize_args
  ); then
    echo "expected traversal prefix validation to fail" >&2
    return 1
  fi
}

case_rejects_empty_env_prefix_entries() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  if (
    TP_WRITE_SCOPE_IGNORE_PREFIXES="valid::also-valid"
    tp_parse_args \
      --generated-repo "${tmp}/generated" \
      --original-repo "${tmp}/original" \
      --adapter codex \
      --run-dir "${tmp}/run"
    tp_validate_and_finalize_args
  ); then
    echo "expected empty env prefix entry validation to fail" >&2
    return 1
  fi
}

case_rejects_colon_in_prefix() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  if (
    unset TP_WRITE_SCOPE_IGNORE_PREFIXES || true
    tp_parse_args \
      --generated-repo "${tmp}/generated" \
      --original-repo "${tmp}/original" \
      --adapter codex \
      --run-dir "${tmp}/run" \
      --write-scope-ignore-prefix custom:cache
    tp_validate_and_finalize_args
  ); then
    echo "expected colon-containing prefix validation to fail" >&2
    return 1
  fi
}

case_requires_adapter() {
  local tmp
  tmp="$(tpt_mktemp_dir)"
  create_minimal_repos "$tmp"

  if (
    tp_parse_args \
      --generated-repo "${tmp}/generated" \
      --original-repo "${tmp}/original" \
      --run-dir "${tmp}/run"
    tp_validate_and_finalize_args
  ); then
    echo "expected missing adapter validation to fail" >&2
    return 1
  fi
}

tpt_run_case "defaults include built-in ignored prefixes" case_defaults_include_builtins
tpt_run_case "env and cli prefixes normalize and dedupe" case_env_cli_normalization_and_dedupe
tpt_run_case "absolute ignore prefix is rejected" case_rejects_absolute_prefix
tpt_run_case "parent traversal ignore prefix is rejected" case_rejects_parent_traversal_prefix
tpt_run_case "empty env ignore entries are rejected" case_rejects_empty_env_prefix_entries
tpt_run_case "colon in prefix is rejected" case_rejects_colon_in_prefix
tpt_run_case "adapter is required" case_requires_adapter

tpt_finish_suite
