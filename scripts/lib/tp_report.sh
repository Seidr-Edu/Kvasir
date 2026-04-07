#!/usr/bin/env bash
# tp_report.sh - standalone test-port JSON/markdown reporting.

set -euo pipefail

tp_promote_ported_repo_artifact() {
  TP_PORTED_REPO_ARTIFACT_AVAILABLE=""
  TP_PORTED_REPO_ARTIFACT_EFFECTIVE=""

  [[ -n "${TP_PORTED_REPO_ARTIFACT:-}" ]] || return 0
  [[ -d "${TP_PORTED_REPO:-}" ]] || return 0

  tp_copy_dir "$TP_PORTED_REPO" "$TP_PORTED_REPO_ARTIFACT" || return 1
  TP_PORTED_REPO_ARTIFACT_AVAILABLE="$TP_PORTED_REPO_ARTIFACT"
  if [[ -n "${TP_GENERATED_EFFECTIVE_SUBDIR:-}" ]] && [[ -d "${TP_PORTED_REPO_ARTIFACT}/${TP_GENERATED_EFFECTIVE_SUBDIR}" ]]; then
    TP_PORTED_REPO_ARTIFACT_EFFECTIVE="${TP_PORTED_REPO_ARTIFACT}/${TP_GENERATED_EFFECTIVE_SUBDIR}"
  else
    TP_PORTED_REPO_ARTIFACT_EFFECTIVE="$TP_PORTED_REPO_ARTIFACT"
  fi
}

tp_cleanup_temporary_workspace_repos() {
  local path
  for path in \
    "${TP_ORIGINAL_BASELINE_REPO:-}" \
    "${TP_GENERATED_BASELINE_REPO:-}" \
    "${TP_PORTED_REPO:-}" \
    "${TP_ORIGINAL_TESTS_SNAPSHOT:-}" \
    "${TP_BEST_VALID_PORTED_REPO:-}" \
    "${TP_TMP_DIR:-}"; do
    [[ -n "$path" ]] || continue
    rm -rf "$path"
  done

  if [[ -n "${TP_WORKSPACE_DIR:-}" ]]; then
    rm -rf "${TP_WORKSPACE_DIR}/.m2" "${TP_WORKSPACE_DIR}/.gradle"
  fi
}

tp_write_reports() {
  local finished
  local report_ported_repo
  local ported_repo_artifact
  local ported_repo_artifact_effective
  finished="$(tp_timestamp_iso_utc)"
  report_ported_repo="${TP_PORTED_REPO_ARTIFACT_EFFECTIVE:-${TP_PORTED_EFFECTIVE_REPO:-$TP_PORTED_REPO}}"
  ported_repo_artifact="${TP_PORTED_REPO_ARTIFACT_AVAILABLE:-}"
  ported_repo_artifact_effective=""
  if [[ -n "$ported_repo_artifact" ]]; then
    ported_repo_artifact_effective="${TP_PORTED_REPO_ARTIFACT_EFFECTIVE:-$ported_repo_artifact}"
  fi

  TP_REPORT_BASELINE_ORIGINAL_BUILD_ENV_JSON="$(tp_build_env_suite_report_json "TP_BASELINE_ORIGINAL")" \
  TP_REPORT_BASELINE_GENERATED_BUILD_ENV_JSON="$(tp_build_env_suite_report_json "TP_BASELINE_GENERATED")" \
  TP_REPORT_PORTED_ORIGINAL_BUILD_ENV_JSON="$(tp_build_env_suite_report_json "TP_PORTED_ORIGINAL")" \
  python3 - <<'PY' \
    "$TP_JSON_PATH" "$TP_SUMMARY_MD_PATH" "$TP_RUN_ID" "$TP_STARTED_AT" "$finished" \
    "$TP_GENERATED_REPO" "$TP_ORIGINAL_REPO" "$TP_ORIGINAL_SUBDIR" "${TP_GENERATED_EFFECTIVE_SUBDIR:-}" "$TP_ORIGINAL_EFFECTIVE_PATH" "${TP_GENERATED_EFFECTIVE_PATH:-$TP_GENERATED_REPO}" "$TP_DIAGRAM_PATH" \
    "$TP_ADAPTER" "$TP_MAX_ITER" "$TP_STRICT" "$TP_WRITE_SCOPE_POLICY" \
    "$TP_STATUS" "$TP_REASON" "${TP_STATUS_DETAIL:-}" "$TP_FAILURE_CLASS" "${TP_FAILURE_CLASS_LEGACY:-}" "$TP_ADAPTER_PREREQS_OK" \
    "$TP_BEHAVIORAL_VERDICT" "$TP_BEHAVIORAL_VERDICT_REASON" \
    "${TP_FAILURE_PHASE:-}" "${TP_FAILURE_SUBCLASS:-}" "${TP_FAILURE_FIRST_FAILURE_LINE:-}" "${TP_FAILURE_LOG_EXCERPT_PATH:-}" \
    "${TP_RUNNER_PREFLIGHT_DETECTED_RUNNER:-unknown}" "${TP_RUNNER_PREFLIGHT_SUPPORTED:-false}" "${TP_RUNNER_PREFLIGHT_MISSING_CAPABILITIES_CSV:-}" "${TP_RUNNER_PREFLIGHT_MODULE_ROOT:-}" "${TP_RUNNER_PREFLIGHT_FRAMEWORKS_DETECTED_CSV:-}" \
    "$TP_GENERATED_REPO_UNCHANGED" "$TP_GENERATED_BEFORE_HASH_PATH" "$TP_GENERATED_AFTER_HASH_PATH" \
    "$TP_WRITE_SCOPE_VIOLATION_COUNT" "$TP_WRITE_SCOPE_FAILURE_PATHS_FILE" "$TP_WRITE_SCOPE_DIFF_FILE" "$TP_WRITE_SCOPE_CHANGE_SET_PATH" \
    "$TP_WRITE_SCOPE_IGNORED_PREFIXES_CSV" "${TP_ALLOWED_SERVICE_ARTIFACT_PREFIXES_CSV:-}" "${TP_IMMUTABLE_OR_DENIED_TARGET_PREFIXES_CSV:-}" "${TP_POLICY_REJECTED_OVERRIDES_CSV:-}" \
    "$TP_EVIDENCE_JSON_PATH" "${TP_TEST_SCOPE_JSON_PATH:-}" "$TP_REMOVED_TESTS_MANIFEST_REL" "$TP_RETENTION_POLICY_MODE" "$TP_RETENTION_DOCUMENTED_REMOVALS_REQUIRED" \
    "$TP_BASELINE_ORIGINAL_STATUS" "$TP_BASELINE_ORIGINAL_RC" "$TP_BASELINE_ORIGINAL_LOG" \
    "$TP_BASELINE_ORIGINAL_STRATEGY" "$TP_BASELINE_ORIGINAL_UNIT_ONLY_RC" "$TP_BASELINE_ORIGINAL_FULL_RC" \
    "$TP_BASELINE_ORIGINAL_FAILURE_CLASS" "${TP_BASELINE_ORIGINAL_FAILURE_CLASS_LEGACY:-}" "$TP_BASELINE_ORIGINAL_FAILURE_TYPE" "${TP_BASELINE_ORIGINAL_FAILURE_PHASE:-}" "${TP_BASELINE_ORIGINAL_FAILURE_SUBCLASS:-}" "${TP_BASELINE_ORIGINAL_FAILURE_FIRST_LINE:-}" \
    "${TP_BASELINE_ORIGINAL_TESTS_DISCOVERED:-0}" "${TP_BASELINE_ORIGINAL_TESTS_EXECUTED:-0}" "${TP_BASELINE_ORIGINAL_TESTS_FAILED:-0}" "${TP_BASELINE_ORIGINAL_TESTS_ERRORS:-0}" "${TP_BASELINE_ORIGINAL_TESTS_SKIPPED:-0}" "${TP_BASELINE_ORIGINAL_JUNIT_REPORTS_FOUND:-0}" \
    "$TP_BASELINE_GENERATED_STATUS" "$TP_BASELINE_GENERATED_RC" "$TP_BASELINE_GENERATED_LOG" \
    "$TP_BASELINE_GENERATED_STRATEGY" "$TP_BASELINE_GENERATED_UNIT_ONLY_RC" "$TP_BASELINE_GENERATED_FULL_RC" \
    "$TP_BASELINE_GENERATED_FAILURE_CLASS" "${TP_BASELINE_GENERATED_FAILURE_CLASS_LEGACY:-}" "$TP_BASELINE_GENERATED_FAILURE_TYPE" "${TP_BASELINE_GENERATED_FAILURE_PHASE:-}" "${TP_BASELINE_GENERATED_FAILURE_SUBCLASS:-}" "${TP_BASELINE_GENERATED_FAILURE_FIRST_LINE:-}" \
    "${TP_BASELINE_GENERATED_TESTS_DISCOVERED:-0}" "${TP_BASELINE_GENERATED_TESTS_EXECUTED:-0}" "${TP_BASELINE_GENERATED_TESTS_FAILED:-0}" "${TP_BASELINE_GENERATED_TESTS_ERRORS:-0}" "${TP_BASELINE_GENERATED_TESTS_SKIPPED:-0}" "${TP_BASELINE_GENERATED_JUNIT_REPORTS_FOUND:-0}" \
    "$TP_PORTED_ORIGINAL_TESTS_STATUS" "$TP_PORTED_ORIGINAL_TESTS_EXIT_CODE" "$TP_PORTED_ORIGINAL_TESTS_LOG" \
    "$TP_ITERATIONS_USED" "$TP_ADAPTER_NONZERO_RUNS" \
    "${TP_PORTED_ORIGINAL_TESTS_DISCOVERED:-0}" "${TP_PORTED_ORIGINAL_TESTS_EXECUTED:-0}" "${TP_PORTED_ORIGINAL_TESTS_FAILED:-0}" "${TP_PORTED_ORIGINAL_TESTS_ERRORS:-0}" "${TP_PORTED_ORIGINAL_TESTS_SKIPPED:-0}" "${TP_PORTED_ORIGINAL_JUNIT_REPORTS_FOUND:-0}" \
    "$TP_ADAPTER_EVENTS_LOG" "$TP_ADAPTER_STDERR_LOG" "$TP_ADAPTER_LAST_MESSAGE" \
    "$TP_RUN_DIR" "$TP_LOG_DIR" "$TP_WORKSPACE_DIR" "$TP_OUTPUT_DIR" \
    "$ported_repo_artifact" "$ported_repo_artifact_effective" "$report_ported_repo" "$TP_ORIGINAL_TESTS_SNAPSHOT"
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

(
  json_path, summary_path, run_id, started_at, finished_at,
  generated_repo, original_repo, original_subdir, generated_subdir, original_effective_path, generated_effective_path, diagram_path,
  adapter, max_iter, strict_b, write_scope_policy,
  status, reason, status_detail, failure_class, failure_class_legacy, adapter_prereqs_ok,
  behavioral_verdict, behavioral_verdict_reason,
  failure_phase, failure_subclass, failure_first_line, failure_log_excerpt_path,
  preflight_runner, preflight_supported, preflight_missing_csv, preflight_module_root, preflight_frameworks_csv,
  generated_unchanged, generated_before_hash_path, generated_after_hash_path,
  write_scope_violation_count, write_scope_fail_paths, write_scope_diff_path, write_scope_change_set_path,
    write_scope_ignored_prefixes_csv, write_scope_service_artifact_prefixes_csv, write_scope_denied_prefixes_csv, write_scope_rejected_overrides_csv,
  evidence_json_path, test_scope_json_path, removed_tests_manifest_rel, retention_policy_mode, retention_documented_removals_required,
  baseline_orig_status, baseline_orig_rc, baseline_orig_log,
  baseline_orig_strategy, baseline_orig_unit_rc, baseline_orig_full_rc,
  baseline_orig_failure_class, baseline_orig_failure_class_legacy, baseline_orig_failure_type, baseline_orig_failure_phase, baseline_orig_failure_subclass, baseline_orig_failure_first_line,
  baseline_orig_tests_discovered, baseline_orig_tests_executed, baseline_orig_tests_failed, baseline_orig_tests_errors, baseline_orig_tests_skipped, baseline_orig_junit_reports_found,
  baseline_gen_status, baseline_gen_rc, baseline_gen_log,
  baseline_gen_strategy, baseline_gen_unit_rc, baseline_gen_full_rc,
  baseline_gen_failure_class, baseline_gen_failure_class_legacy, baseline_gen_failure_type, baseline_gen_failure_phase, baseline_gen_failure_subclass, baseline_gen_failure_first_line,
  baseline_gen_tests_discovered, baseline_gen_tests_executed, baseline_gen_tests_failed, baseline_gen_tests_errors, baseline_gen_tests_skipped, baseline_gen_junit_reports_found,
  ported_status, ported_rc, ported_log,
  iterations_used, adapter_nonzero_runs,
  ported_tests_discovered, ported_tests_executed, ported_tests_failed, ported_tests_errors, ported_tests_skipped, ported_junit_reports_found,
  adapter_events_log, adapter_stderr_log, adapter_last_message,
  run_dir, log_dir, workspace_dir, output_dir,
  ported_repo_artifact, ported_repo_effective_dir, ported_repo_dir, original_tests_snapshot_dir
) = sys.argv[1:]


def to_int(v, default=0):
    try:
        return int(v)
    except Exception:
        return default


def to_float(v):
    try:
        return float(v)
    except Exception:
        return None


def to_bool(v):
    return str(v).lower() == "true"


def env_json(name, default):
    raw = os.environ.get(name, "")
    if not raw:
        return default
    try:
        return json.loads(raw)
    except Exception:
        return default


def split_csv(value):
    if not value:
        return []
    return [p for p in value.split(":") if p]


def load_evidence_json(path):
    if not path or not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            obj = json.load(f)
    except Exception:
        return {}
    return obj if isinstance(obj, dict) else {}


def read_violation_entries(path):
    out = []
    if not path or not os.path.exists(path):
        return out
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 1)
            if len(parts) == 2:
                out.append({"kind": parts[0], "path": parts[1]})
            else:
                out.append({"kind": "", "path": line})
    return out


def read_change_set_stats(path):
    stats = {"A": 0, "M": 0, "D": 0, "R": 0, "total": 0}
    if not path or not os.path.exists(path):
        return stats
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            if not line:
                continue
            parts = line.split("\t", 1)
            kind = parts[0] if parts else ""
            if kind in stats:
                stats[kind] += 1
            stats["total"] += 1
    return stats


def collect_junit_failing_cases(repo_dir, max_cases=200, max_groups=500, max_sample_reports=3):
    out = {
        "junit_report_count": 0,
        "junit_report_files": [],
        "failing_case_count": 0,
        "failing_case_unique_count": 0,
        "failing_case_occurrence_count": 0,
        "failing_cases": [],
        "grouped_failing_cases": [],
        "truncated": False,
        "grouped_truncated": False,
    }
    if not repo_dir or not os.path.isdir(repo_dir):
        return out

    patterns = [
        "target/surefire-reports/*.xml",
        "target/failsafe-reports/*.xml",
        "build/test-results/test/*.xml",
        "build/test-results/**/*.xml",
    ]
    report_files = []
    seen_files = set()
    for pat in patterns:
        for path in glob.glob(os.path.join(repo_dir, pat), recursive=True):
            if not os.path.isfile(path) or not path.lower().endswith(".xml"):
                continue
            if path in seen_files:
                continue
            seen_files.add(path)
            report_files.append(path)
    report_files.sort()
    out["junit_report_count"] = len(report_files)
    out["junit_report_files"] = [os.path.relpath(p, repo_dir).replace(os.sep, "/") for p in report_files]

    grouped_index = {}
    unique_case_count = 0
    for report_path in report_files:
        rel_report = os.path.relpath(report_path, repo_dir).replace(os.sep, "/")
        try:
            root = ET.parse(report_path).getroot()
        except Exception:
            continue
        for tc in root.iter("testcase"):
            classname = tc.attrib.get("classname") or ""
            name = tc.attrib.get("name") or ""
            for child in list(tc):
                if child.tag not in {"failure", "error"}:
                    continue
                out["failing_case_occurrence_count"] += 1
                msg = (child.attrib.get("message") or "").strip()
                if not msg:
                    msg = " ".join((child.text or "").split())[:240]
                elif len(msg) > 240:
                    msg = msg[:237] + "..."
                kind = child.tag
                key = (classname, name, kind, msg)

                group_idx = grouped_index.get(key)
                if group_idx is None:
                    unique_case_count += 1
                    if len(out["grouped_failing_cases"]) < max_groups:
                        out["grouped_failing_cases"].append({
                            "class": classname,
                            "name": name,
                            "kind": kind,
                            "message": msg,
                            "occurrence_count": 1,
                            "sample_report_files": [rel_report],
                        })
                        group_idx = len(out["grouped_failing_cases"]) - 1
                        grouped_index[key] = group_idx
                    else:
                        out["grouped_truncated"] = True

                    if len(out["failing_cases"]) < max_cases:
                        out["failing_cases"].append({
                            "class": classname,
                            "name": name,
                            "kind": kind,
                            "message": msg,
                            "report_file": rel_report,
                        })
                    else:
                        out["truncated"] = True
                else:
                    group = out["grouped_failing_cases"][group_idx]
                    group["occurrence_count"] += 1
                    samples = group["sample_report_files"]
                    if rel_report not in samples and len(samples) < max_sample_reports:
                        samples.append(rel_report)

    out["failing_case_unique_count"] = unique_case_count
    out["failing_case_count"] = unique_case_count
    return out


def execution_summary(discovered, executed, failed, errors, skipped, reports):
    return {
        "tests_discovered": to_int(discovered, 0),
        "tests_executed": to_int(executed, 0),
        "tests_failed": to_int(failed, 0),
        "tests_errors": to_int(errors, 0),
        "tests_skipped": to_int(skipped, 0),
        "junit_reports_found": to_int(reports, 0),
    }


suite_changes = read_change_set_stats(write_scope_change_set_path)
evidence_data = load_evidence_json(evidence_json_path)
orig_snapshot_file_count = to_int(evidence_data.get("original_snapshot_file_count"), 0)
final_ported_test_file_count = to_int(evidence_data.get("final_ported_test_file_count"), 0)
retained_original_test_file_count = to_int(evidence_data.get("retained_original_test_file_count"), 0)
removed_original_test_file_count = to_int(evidence_data.get("removed_original_test_file_count"), 0)
retention_ratio = to_float(evidence_data.get("retention_ratio"))
retained_modified_count = to_int(evidence_data.get("retained_modified_count"), 0)
retained_unchanged_count = to_int(evidence_data.get("retained_unchanged_count"), 0)
assertion_line_change_count = to_int(evidence_data.get("assertion_line_change_count"), 0)
removed_original_tests = evidence_data.get("removed_original_tests")
if not isinstance(removed_original_tests, list):
    removed_original_tests = []
undocumented_removed_test_count = to_int(evidence_data.get("undocumented_removed_test_count"), 0)
behavioral_evidence = collect_junit_failing_cases(ported_repo_dir)
if "junit_report_count" in evidence_data:
    behavioral_evidence["junit_report_count"] = to_int(evidence_data.get("junit_report_count"), behavioral_evidence.get("junit_report_count", 0))
if "junit_report_files" in evidence_data and isinstance(evidence_data.get("junit_report_files"), list):
    behavioral_evidence["junit_report_files"] = evidence_data.get("junit_report_files")
if "junit_failing_case_count" in evidence_data:
    unique_count = to_int(evidence_data.get("junit_failing_case_count"), behavioral_evidence.get("failing_case_unique_count", 0))
    behavioral_evidence["failing_case_count"] = unique_count
    behavioral_evidence["failing_case_unique_count"] = unique_count

test_scope = load_evidence_json(test_scope_json_path)
if not test_scope:
    test_scope = {
        "mode": "portable-tests",
        "status": "unselected",
        "runner": preflight_runner,
        "build_tool": None,
        "selection_reason": None,
        "selected_commands": [],
        "selected_tasks": [],
        "excluded_commands": [],
        "included_test_file_count": 0,
        "excluded_test_file_count": 0,
        "excluded_tests": [],
        "probes": [],
    }


def suite_result(status_value, rc_value, log_path, build_env_name, strategy, failure_cls, failure_type, phase, subclass, first_line, discovered, executed, failed, errors, skipped, reports):
    return {
        "status": status_value,
        "exit_code": to_int(rc_value, -1),
        "strategy": strategy or None,
        "log_path": log_path or None,
        "build_environment": env_json(build_env_name, {}),
        "failure": {
            "class": failure_cls or None,
            "type": failure_type or None,
            "phase": phase or None,
            "subclass": subclass or None,
            "first_line": first_line or None,
        },
        "execution": execution_summary(discovered, executed, failed, errors, skipped, reports),
    }


original_baseline = suite_result(
    baseline_orig_status,
    baseline_orig_rc,
    baseline_orig_log,
    "TP_REPORT_BASELINE_ORIGINAL_BUILD_ENV_JSON",
    baseline_orig_strategy,
    baseline_orig_failure_class,
    baseline_orig_failure_type,
    baseline_orig_failure_phase,
    baseline_orig_failure_subclass,
    baseline_orig_failure_first_line,
    baseline_orig_tests_discovered,
    baseline_orig_tests_executed,
    baseline_orig_tests_failed,
    baseline_orig_tests_errors,
    baseline_orig_tests_skipped,
    baseline_orig_junit_reports_found,
)
generated_baseline = suite_result(
    baseline_gen_status,
    baseline_gen_rc,
    baseline_gen_log,
    "TP_REPORT_BASELINE_GENERATED_BUILD_ENV_JSON",
    baseline_gen_strategy,
    baseline_gen_failure_class,
    baseline_gen_failure_type,
    baseline_gen_failure_phase,
    baseline_gen_failure_subclass,
    baseline_gen_failure_first_line,
    baseline_gen_tests_discovered,
    baseline_gen_tests_executed,
    baseline_gen_tests_failed,
    baseline_gen_tests_errors,
    baseline_gen_tests_skipped,
    baseline_gen_junit_reports_found,
)
ported_execution = execution_summary(
    ported_tests_discovered,
    ported_tests_executed,
    ported_tests_failed,
    ported_tests_errors,
    ported_tests_skipped,
    ported_junit_reports_found,
)

obj = {
    "schema_version": "kvasir.test_port.v3",
    "run_id": run_id,
    "started_at": started_at,
    "finished_at": finished_at,
    "result": {
        "status": status or "skipped",
        "reason": reason or None,
        "verdict": behavioral_verdict,
        "verdict_reason": behavioral_verdict_reason,
        "failure_class": failure_class or None,
    },
    "inputs": {
        "generated_repo": generated_repo,
        "generated_subdir": generated_subdir or None,
        "generated_effective_path": generated_effective_path,
        "original_repo": original_repo,
        "original_subdir": original_subdir or None,
        "original_effective_path": original_effective_path,
        "diagram_path": diagram_path or None,
        "adapter": adapter,
        "max_iter": to_int(max_iter, 0),
        "strict": to_bool(strict_b),
    },
    "test_scope": test_scope,
    "baselines": {
        "original": original_baseline,
        "generated": generated_baseline,
    },
    "porting": {
        "status": ported_status,
        "exit_code": to_int(ported_rc, -1),
        "iterations_used": to_int(iterations_used, 0),
        "adapter_nonzero_runs": to_int(adapter_nonzero_runs, 0),
        "log_path": ported_log or None,
        "build_environment": env_json("TP_REPORT_PORTED_ORIGINAL_BUILD_ENV_JSON", {}),
        "execution": ported_execution,
        "adapter": {
            "name": adapter,
            "events_log": adapter_events_log,
            "stderr_log": adapter_stderr_log,
            "last_message_path": adapter_last_message,
        },
    },
    "evidence": {
        "behavioral": behavioral_evidence,
        "suite_changes": {
            "added": suite_changes["A"],
            "modified": suite_changes["M"],
            "deleted": suite_changes["D"],
            "renamed": suite_changes["R"],
            "total": suite_changes["total"],
        },
        "retention": {
            "original_snapshot_file_count": orig_snapshot_file_count,
            "final_ported_test_file_count": final_ported_test_file_count,
            "retained_original_test_file_count": retained_original_test_file_count,
            "removed_original_test_file_count": removed_original_test_file_count,
            "retention_ratio": retention_ratio,
            "retained_modified_count": retained_modified_count,
            "retained_unchanged_count": retained_unchanged_count,
            "assertion_line_change_count": assertion_line_change_count,
            "undocumented_removed_test_count": undocumented_removed_test_count,
            "removed_tests": removed_original_tests,
        },
    },
    "diagnostics": {
        "adapter_prereqs_ok": to_bool(adapter_prereqs_ok),
        "generated_repo_unchanged": to_bool(generated_unchanged),
        "failure": {
            "phase": failure_phase or None,
            "subclass": failure_subclass or None,
            "first_line": failure_first_line or None,
            "log_excerpt_path": failure_log_excerpt_path or None,
        },
        "runner": {
            "detected_runner": preflight_runner,
            "supported": to_bool(preflight_supported),
            "missing_capabilities": split_csv(preflight_missing_csv),
            "module_root": preflight_module_root or None,
            "frameworks_detected": split_csv(preflight_frameworks_csv),
        },
        "write_scope": {
            "violation_count": to_int(write_scope_violation_count, 0),
            "violations": read_violation_entries(write_scope_fail_paths),
            "ignored_prefixes": split_csv(write_scope_ignored_prefixes_csv),
            "rejected_overrides": split_csv(write_scope_rejected_overrides_csv),
        },
    },
    "artifacts": {
        "run_dir": run_dir,
        "logs_dir": log_dir,
        "outputs_dir": output_dir,
        "ported_repo": ported_repo_artifact or None,
        "ported_effective_repo": ported_repo_effective_dir or None,
        "summary_md": summary_path,
    },
}

os.makedirs(os.path.dirname(json_path), exist_ok=True)
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)

def summarize_reasons(rows):
    counts = {}
    for row in rows or []:
        reason = row.get("reason") or "unknown"
        counts[reason] = counts.get(reason, 0) + 1
    if not counts:
        return "<none>"
    return ", ".join(f"{reason}={count}" for reason, count in sorted(counts.items()))

summary_lines = [
    "# Test-Port Summary",
    "",
    f"- Run ID: {obj['run_id']}",
    f"- Schema: {obj['schema_version']}",
    f"- Generated repo: {obj['inputs']['generated_repo']}",
    f"- Generated subdir: {obj['inputs']['generated_subdir'] or '<none>'}",
    f"- Original repo: {obj['inputs']['original_repo']}",
    f"- Original subdir: {obj['inputs']['original_subdir'] or '<none>'}",
    f"- Diagram: {obj['inputs']['diagram_path'] or '<none>'}",
    f"- Adapter: {obj['inputs']['adapter']}",
    f"- Status: **{obj['result']['status']}**",
    f"- Reason: {obj['result'].get('reason') or '<none>'}",
    f"- Behavioral verdict: **{obj['result'].get('verdict') or '<none>'}**",
    f"- Behavioral verdict reason: {obj['result'].get('verdict_reason') or '<none>'}",
    f"- Failure classifier: {obj['result'].get('failure_class') or '<none>'}",
    f"- Test scope: **{obj['test_scope'].get('mode')}** ({obj['test_scope'].get('status')})",
    f"- Selected test commands: {', '.join(obj['test_scope'].get('selected_commands', [])) if obj['test_scope'].get('selected_commands') else '<none>'}",
    f"- Excluded test commands: **{len(obj['test_scope'].get('excluded_commands', []))}**",
    f"- Excluded test command reasons: {summarize_reasons(obj['test_scope'].get('excluded_commands', []))}",
    f"- Portable test files included/excluded: **{obj['test_scope'].get('included_test_file_count', 0)}/{obj['test_scope'].get('excluded_test_file_count', 0)}**",
    f"- Excluded test file reasons: {summarize_reasons(obj['test_scope'].get('excluded_tests', []))}",
    f"- Adapter prereqs OK: **{str(obj['diagnostics'].get('adapter_prereqs_ok', False)).lower()}**",
    f"- Generated repo unchanged: **{str(obj['diagnostics'].get('generated_repo_unchanged', False)).lower()}**",
    f"- Write-scope violations: **{obj['diagnostics']['write_scope']['violation_count']}**",
    f"- Ported repo artifact: {obj['artifacts'].get('ported_repo') or '<none>'}",
    f"- Retained original tests: **{obj['evidence']['retention']['retained_original_test_file_count']}**",
    f"- Removed original tests: **{obj['evidence']['retention']['removed_original_test_file_count']}**",
    f"- Retention ratio: **{obj['evidence']['retention']['retention_ratio'] if obj['evidence']['retention']['retention_ratio'] is not None else '<none>'}**",
    f"- Assertion line changes in retained tests: **{obj['evidence']['retention']['assertion_line_change_count']}**",
    f"- Observed failing test cases: **{obj['evidence']['behavioral']['failing_case_count']} unique / {obj['evidence']['behavioral'].get('failing_case_occurrence_count', obj['evidence']['behavioral']['failing_case_count'])} occurrences**",
    f"- Baseline original: **{obj['baselines']['original']['status']}** (exit {obj['baselines']['original']['exit_code']}) log: {obj['baselines']['original']['log_path'] or '<none>'}",
    f"- Baseline generated: **{obj['baselines']['generated']['status']}** (exit {obj['baselines']['generated']['exit_code']}) log: {obj['baselines']['generated']['log_path'] or '<none>'}",
    f"- Ported tests: **{obj['porting']['status']}** (exit {obj['porting']['exit_code']}, iterations {obj['porting']['iterations_used']}) log: {obj['porting']['log_path'] or '<none>'}",
    "- Detailed failing cases are in `test_port.json` under `evidence.behavioral.grouped_failing_cases`.",
]

os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as f:
    f.write("\n".join(summary_lines) + "\n")
PY
}
