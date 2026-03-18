#!/usr/bin/env bash
# tp_report.sh - standalone test-port JSON/markdown reporting.

set -euo pipefail

tp_write_reports() {
  local finished
  finished="$(tp_timestamp_iso_utc)"

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
    "$TP_EVIDENCE_JSON_PATH" "$TP_REMOVED_TESTS_MANIFEST_REL" "$TP_RETENTION_POLICY_MODE" "$TP_RETENTION_DOCUMENTED_REMOVALS_REQUIRED" \
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
    "${TP_PORTED_EFFECTIVE_REPO:-$TP_PORTED_REPO}" "$TP_ORIGINAL_TESTS_SNAPSHOT"
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
  evidence_json_path, removed_tests_manifest_rel, retention_policy_mode, retention_documented_removals_required,
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
  ported_repo_dir, original_tests_snapshot_dir
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
    stats = {"A": 0, "M": 0, "D": 0, "total": 0}
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

obj = {
    "version": 2,
    "run_id": run_id,
    "status": status or "skipped",
    "reason": reason,
    "status_detail": status_detail,
    "failure_class": failure_class,
    "failure_class_legacy": failure_class_legacy,
    "started_at": started_at,
    "finished_at": finished_at,
    "inputs": {
        "generated_repo": generated_repo,
        "generated_subdir": generated_subdir,
        "generated_effective_path": generated_effective_path,
        "original_repo": original_repo,
        "original_subdir": original_subdir,
        "original_effective_path": original_effective_path,
        "diagram_path": diagram_path,
        "adapter": adapter,
        "max_iter": to_int(max_iter, 0),
        "strict": to_bool(strict_b),
        "write_scope_policy": write_scope_policy,
    },
    "adapter_prereqs_ok": to_bool(adapter_prereqs_ok),
    "runner_preflight": {
        "detected_runner": preflight_runner,
        "supported": to_bool(preflight_supported),
        "missing_capabilities": split_csv(preflight_missing_csv),
        "module_root": preflight_module_root,
        "frameworks_detected": split_csv(preflight_frameworks_csv),
    },
    "failure_diagnostics": {
        "phase": failure_phase or "",
        "subclass": failure_subclass or "",
        "first_failure_line": failure_first_line,
        "log_excerpt_path": failure_log_excerpt_path,
    },
    "immutability": {
        "generated_repo_unchanged": to_bool(generated_unchanged),
        "before_hash_path": generated_before_hash_path,
        "after_hash_path": generated_after_hash_path,
    },
    "write_scope": {
        "policy": write_scope_policy,
        "violation_count": to_int(write_scope_violation_count, 0),
        "violations": read_violation_entries(write_scope_fail_paths),
        "violations_log_path": write_scope_fail_paths,
        "diff_path": write_scope_diff_path,
        "change_set_path": write_scope_change_set_path,
        "ignored_prefixes": split_csv(write_scope_ignored_prefixes_csv),
        "allowed_service_artifacts": split_csv(write_scope_service_artifact_prefixes_csv),
        "immutable_or_denied_targets": split_csv(write_scope_denied_prefixes_csv),
        "rejected_overrides": split_csv(write_scope_rejected_overrides_csv),
    },
    "baseline_original_tests": {
        "status": baseline_orig_status,
        "exit_code": to_int(baseline_orig_rc, -1),
        "log_path": baseline_orig_log,
        "strategy": baseline_orig_strategy,
        "unit_only_exit_code": to_int(baseline_orig_unit_rc, -1),
        "full_fallback_exit_code": to_int(baseline_orig_full_rc, -1),
        "failure_class": baseline_orig_failure_class,
        "failure_class_legacy": baseline_orig_failure_class_legacy,
        "failure_type": baseline_orig_failure_type,
        "failure_diagnostics": {
            "phase": baseline_orig_failure_phase,
            "subclass": baseline_orig_failure_subclass,
            "first_failure_line": baseline_orig_failure_first_line,
        },
        "execution_summary": execution_summary(
            baseline_orig_tests_discovered,
            baseline_orig_tests_executed,
            baseline_orig_tests_failed,
            baseline_orig_tests_errors,
            baseline_orig_tests_skipped,
            baseline_orig_junit_reports_found,
        ),
    },
    "baseline_generated_tests": {
        "status": baseline_gen_status,
        "exit_code": to_int(baseline_gen_rc, -1),
        "log_path": baseline_gen_log,
        "strategy": baseline_gen_strategy,
        "unit_only_exit_code": to_int(baseline_gen_unit_rc, -1),
        "full_fallback_exit_code": to_int(baseline_gen_full_rc, -1),
        "failure_class": baseline_gen_failure_class,
        "failure_class_legacy": baseline_gen_failure_class_legacy,
        "failure_type": baseline_gen_failure_type,
        "failure_diagnostics": {
            "phase": baseline_gen_failure_phase,
            "subclass": baseline_gen_failure_subclass,
            "first_failure_line": baseline_gen_failure_first_line,
        },
        "execution_summary": execution_summary(
            baseline_gen_tests_discovered,
            baseline_gen_tests_executed,
            baseline_gen_tests_failed,
            baseline_gen_tests_errors,
            baseline_gen_tests_skipped,
            baseline_gen_junit_reports_found,
        ),
    },
    "ported_original_tests": {
        "status": ported_status,
        "exit_code": to_int(ported_rc, -1),
        "iterations_used": to_int(iterations_used, 0),
        "adapter_nonzero_runs": to_int(adapter_nonzero_runs, 0),
        "log_path": ported_log,
        "execution_summary": execution_summary(
            ported_tests_discovered,
            ported_tests_executed,
            ported_tests_failed,
            ported_tests_errors,
            ported_tests_skipped,
            ported_junit_reports_found,
        ),
    },
    "behavioral_verdict": behavioral_verdict,
    "behavioral_verdict_reason": behavioral_verdict_reason,
    "behavioral_evidence": behavioral_evidence,
    "suite_changes": {
        "added": suite_changes["A"],
        "modified": suite_changes["M"],
        "deleted": suite_changes["D"],
        "total": suite_changes["total"],
    },
    "suite_shape": {
        "original_snapshot_file_count": orig_snapshot_file_count,
        "final_ported_test_file_count": final_ported_test_file_count,
        "retained_original_test_file_count": retained_original_test_file_count,
        "removed_original_test_file_count": removed_original_test_file_count,
        "retention_ratio": retention_ratio,
        "retained_modified_count": retained_modified_count,
        "retained_unchanged_count": retained_unchanged_count,
        "assertion_line_change_count": assertion_line_change_count,
    },
    "removed_original_tests": removed_original_tests,
    "retention_policy": {
        "mode": retention_policy_mode,
        "documented_removals_required": to_bool(retention_documented_removals_required),
        "hard_cap_ratio": None,
        "manifest_rel_path": removed_tests_manifest_rel,
        "undocumented_removed_test_count": undocumented_removed_test_count,
    },
    "adapter": {
        "events_log": adapter_events_log,
        "stderr_log": adapter_stderr_log,
        "last_message_path": adapter_last_message,
    },
    "artifacts": {
        "run_dir": run_dir,
        "logs_dir": log_dir,
        "workspace_dir": workspace_dir,
        "outputs_dir": output_dir,
        "summary_md": summary_path,
    },
}

os.makedirs(os.path.dirname(json_path), exist_ok=True)
with open(json_path, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)

summary_lines = [
    "# Test-Port Summary",
    "",
    f"- Run ID: {obj['run_id']}",
    f"- Generated repo: {obj['inputs']['generated_repo']}",
    f"- Generated subdir: {obj['inputs']['generated_subdir'] or '<none>'}",
    f"- Original repo: {obj['inputs']['original_repo']}",
    f"- Original subdir: {obj['inputs']['original_subdir'] or '<none>'}",
    f"- Diagram: {obj['inputs']['diagram_path'] or '<none>'}",
    f"- Adapter: {obj['inputs']['adapter']}",
    f"- Status: **{obj['status']}**",
    f"- Reason: {obj.get('reason') or '<none>'}",
    f"- Status detail: {obj.get('status_detail') or '<none>'}",
    f"- Failure classifier: {obj.get('failure_class') or '<none>'}",
    f"- Failure classifier (legacy): {obj.get('failure_class_legacy') or '<none>'}",
    f"- Behavioral verdict: **{obj.get('behavioral_verdict') or '<none>'}**",
    f"- Behavioral verdict reason: {obj.get('behavioral_verdict_reason') or '<none>'}",
    f"- Adapter prereqs OK: **{str(obj.get('adapter_prereqs_ok', False)).lower()}**",
    f"- Runner preflight: runner={obj['runner_preflight']['detected_runner'] or '<none>'}, supported={str(obj['runner_preflight']['supported']).lower()}, module_root={obj['runner_preflight']['module_root'] or '<none>'}",
    f"- Runner missing capabilities: {', '.join(obj['runner_preflight']['missing_capabilities']) if obj['runner_preflight']['missing_capabilities'] else '<none>'}",
    f"- Runner frameworks detected: {', '.join(obj['runner_preflight']['frameworks_detected']) if obj['runner_preflight']['frameworks_detected'] else '<none>'}",
    f"- Failure diagnostics phase/subclass: {obj['failure_diagnostics'].get('phase') or '<none>'}/{obj['failure_diagnostics'].get('subclass') or '<none>'}",
    f"- Failure diagnostics first line: {obj['failure_diagnostics'].get('first_failure_line') or '<none>'}",
    f"- Generated repo unchanged: **{str(obj['immutability']['generated_repo_unchanged']).lower()}**",
    f"- Write-scope policy: **{obj['write_scope']['policy']}**",
    f"- Write-scope ignored prefixes: **{', '.join(obj['write_scope']['ignored_prefixes']) if obj['write_scope']['ignored_prefixes'] else '<none>'}**",
    f"- Write-scope violations: **{obj['write_scope']['violation_count']}**",
    f"- Retention policy: **{obj['retention_policy']['mode']}**",
    f"- Documented removals required: **{str(obj['retention_policy']['documented_removals_required']).lower()}**",
    f"- Removal manifest: **{obj['retention_policy']['manifest_rel_path'] or '<none>'}**",
    f"- Undocumented removed tests: **{obj['retention_policy']['undocumented_removed_test_count']}**",
    f"- Suite changes (A/M/D/total): **{obj['suite_changes']['added']}/{obj['suite_changes']['modified']}/{obj['suite_changes']['deleted']}/{obj['suite_changes']['total']}**",
    f"- Test files (original snapshot -> final ported): **{obj['suite_shape']['original_snapshot_file_count']} -> {obj['suite_shape']['final_ported_test_file_count']}**",
    f"- Retained original tests: **{obj['suite_shape']['retained_original_test_file_count']}**",
    f"- Removed original tests: **{obj['suite_shape']['removed_original_test_file_count']}**",
    f"- Retention ratio: **{obj['suite_shape']['retention_ratio'] if obj['suite_shape']['retention_ratio'] is not None else '<none>'}**",
    f"- Retained modified/unchanged: **{obj['suite_shape']['retained_modified_count']}/{obj['suite_shape']['retained_unchanged_count']}**",
    f"- Assertion line changes in retained tests: **{obj['suite_shape']['assertion_line_change_count']}**",
    f"- Observed failing test cases (from JUnit reports): **{obj['behavioral_evidence']['failing_case_count']} unique / {obj['behavioral_evidence'].get('failing_case_occurrence_count', obj['behavioral_evidence']['failing_case_count'])} occurrences**",
    f"- Iterations used: **{obj['ported_original_tests']['iterations_used']}**",
    f"- Adapter non-zero runs: **{obj['ported_original_tests']['adapter_nonzero_runs']}**",
    f"- Baseline original tests: **{obj['baseline_original_tests']['status']}** (exit {obj['baseline_original_tests']['exit_code']}, strategy {obj['baseline_original_tests'].get('strategy') or '<none>'}, failure type {obj['baseline_original_tests'].get('failure_type') or '<none>'}) log: {obj['baseline_original_tests']['log_path'] or '<none>'}",
    f"- Baseline original execution summary: discovered={obj['baseline_original_tests']['execution_summary']['tests_discovered']}, executed={obj['baseline_original_tests']['execution_summary']['tests_executed']}, failed={obj['baseline_original_tests']['execution_summary']['tests_failed']}, errors={obj['baseline_original_tests']['execution_summary']['tests_errors']}, skipped={obj['baseline_original_tests']['execution_summary']['tests_skipped']}, reports={obj['baseline_original_tests']['execution_summary']['junit_reports_found']}",
    f"- Baseline generated tests: **{obj['baseline_generated_tests']['status']}** (exit {obj['baseline_generated_tests']['exit_code']}, strategy {obj['baseline_generated_tests'].get('strategy') or '<none>'}, failure type {obj['baseline_generated_tests'].get('failure_type') or '<none>'}) log: {obj['baseline_generated_tests']['log_path'] or '<none>'}",
    f"- Baseline generated execution summary: discovered={obj['baseline_generated_tests']['execution_summary']['tests_discovered']}, executed={obj['baseline_generated_tests']['execution_summary']['tests_executed']}, failed={obj['baseline_generated_tests']['execution_summary']['tests_failed']}, errors={obj['baseline_generated_tests']['execution_summary']['tests_errors']}, skipped={obj['baseline_generated_tests']['execution_summary']['tests_skipped']}, reports={obj['baseline_generated_tests']['execution_summary']['junit_reports_found']}",
    f"- Ported original tests: **{obj['ported_original_tests']['status']}** (exit {obj['ported_original_tests']['exit_code']}) log: {obj['ported_original_tests']['log_path'] or '<none>'}",
    f"- Ported execution summary: discovered={obj['ported_original_tests']['execution_summary']['tests_discovered']}, executed={obj['ported_original_tests']['execution_summary']['tests_executed']}, failed={obj['ported_original_tests']['execution_summary']['tests_failed']}, errors={obj['ported_original_tests']['execution_summary']['tests_errors']}, skipped={obj['ported_original_tests']['execution_summary']['tests_skipped']}, reports={obj['ported_original_tests']['execution_summary']['junit_reports_found']}",
    "- Detailed failing cases are in `test_port.json` under `behavioral_evidence.grouped_failing_cases`.",
]

os.makedirs(os.path.dirname(summary_path), exist_ok=True)
with open(summary_path, "w", encoding="utf-8") as f:
    f.write("\n".join(summary_lines) + "\n")
PY
}
