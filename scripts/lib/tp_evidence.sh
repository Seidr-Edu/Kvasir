#!/usr/bin/env bash
# tp_evidence.sh - shared test-port evidence and retention helpers.

set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tp_discovery.sh"

tp_compute_evidence_json() {
  local repo_dir="$1"
  local snapshot_dir="$2"
  local manifest_path="$3"
  local out_json="$4"
  local final_ported_test_file_count=0

  mkdir -p "$(dirname "$out_json")"
  final_ported_test_file_count="$(tp_discovery_count_test_files "$repo_dir" 2>/dev/null || echo 0)"

  python3 - <<'PY' "$repo_dir" "$snapshot_dir" "$manifest_path" "$out_json" "$final_ported_test_file_count" "${TP_GENERATED_EFFECTIVE_SUBDIR:-}"
import difflib
import glob
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

repo_dir, snapshot_dir, manifest_path, out_json, final_ported_test_file_count, generated_subdir = sys.argv[1:]

ALLOWED_CATEGORIES = {
    "unportable",
    "missing-target-feature",
    "generated-layout-mismatch",
    "unsupported-runtime-assumption",
}
WEAK_REASONS = {
    "n/a",
    "na",
    "none",
    "unknown",
    "tbd",
    "todo",
    "same",
    "-",
}


def reason_is_valid(reason):
    if reason is None:
        return False
    text = reason.strip()
    if not text:
        return False
    if len(text) < 12:
        return False
    if text.lower() in WEAK_REASONS:
        return False
    return True


def normalize_rel_file(raw):
    if raw is None:
        return None
    text = raw.strip()
    if not text:
        return None
    if text.startswith("/") or ":" in text:
        return None
    while text.startswith("./"):
        text = text[2:]
    text = re.sub(r"/+", "/", text)
    while text.endswith("/"):
        text = text[:-1]
    if not text:
        return None
    parts = text.split("/")
    if any(p in {"", ".", ".."} for p in parts):
        return None
    return "./" + text


def rel_path(root, path):
    return "./" + os.path.relpath(path, root).replace(os.sep, "/")


def map_snapshot_rel_to_repo_rel(rel):
    if not generated_subdir:
        return rel
    prefix = "./" + generated_subdir.lstrip("./")
    if rel == prefix or rel.startswith(prefix + "/"):
        return rel
    return prefix + "/" + rel[2:]


def list_files(root):
    out = []
    if not root or not os.path.isdir(root):
        return out
    for base, _, files in os.walk(root):
        for name in files:
            out.append(rel_path(root, os.path.join(base, name)))
    out.sort()
    return out


def parse_removal_manifest(path):
    rows = {}
    malformed = []
    if not path or not os.path.isfile(path):
        return rows, malformed

    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f, 1):
            raw = line.rstrip("\n")
            if not raw.strip():
                continue
            parts = raw.split("\t", 2)
            if len(parts) != 3:
                malformed.append({"line": i, "raw": raw})
                continue
            p_raw, category_raw, reason_raw = parts
            norm_path = normalize_rel_file(p_raw)
            if norm_path is None:
                malformed.append({"line": i, "raw": raw})
                continue
            category = category_raw.strip()
            reason = reason_raw.strip()
            rows[norm_path] = {
                "path": norm_path,
                "category": category,
                "reason": reason,
                "well_formed": True,
                "category_valid": category in ALLOWED_CATEGORIES,
                "reason_valid": reason_is_valid(reason),
            }
    return rows, malformed


def collect_junit_stats(repo):
    out = {
        "junit_report_count": 0,
        "junit_report_files": [],
        "junit_failing_case_count": 0,
    }
    if not repo or not os.path.isdir(repo):
        return out

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

    out["junit_report_count"] = len(report_files)
    out["junit_report_files"] = [os.path.relpath(p, repo).replace(os.sep, "/") for p in report_files]

    seen_cases = set()
    for report_path in report_files:
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
                msg = (child.attrib.get("message") or "").strip()
                if not msg:
                    msg = " ".join((child.text or "").split())[:240]
                key = (classname, name, child.tag, msg)
                if key in seen_cases:
                    continue
                seen_cases.add(key)
                out["junit_failing_case_count"] += 1
    return out


def count_assertion_line_changes(original_path, adapted_path):
    try:
        with open(original_path, "r", encoding="utf-8", errors="replace") as f:
            original_lines = f.read().splitlines()
        with open(adapted_path, "r", encoding="utf-8", errors="replace") as f:
            adapted_lines = f.read().splitlines()
    except Exception:
        return 0

    count = 0
    for line in difflib.ndiff(original_lines, adapted_lines):
        if not line or line[0] not in {"+", "-"}:
            continue
        body = line[2:]
        if re.search(r"\bassert[A-Za-z0-9_]*\b|Assertions\.", body):
            count += 1
    return count


snapshot_files = list_files(snapshot_dir)

retained = []
removed = []
for rel in snapshot_files:
    mapped_rel = map_snapshot_rel_to_repo_rel(rel)
    candidate = os.path.join(repo_dir, mapped_rel[2:])
    if os.path.isfile(candidate):
        retained.append(rel)
    else:
        removed.append(rel)

retained_modified_count = 0
retained_unchanged_count = 0
assertion_line_change_count = 0
for rel in retained:
    original_file = os.path.join(snapshot_dir, rel[2:])
    mapped_rel = map_snapshot_rel_to_repo_rel(rel)
    adapted_file = os.path.join(repo_dir, mapped_rel[2:])
    try:
        with open(original_file, "rb") as f:
            original_bytes = f.read()
        with open(adapted_file, "rb") as f:
            adapted_bytes = f.read()
    except Exception:
        retained_modified_count += 1
        continue

    if original_bytes == adapted_bytes:
        retained_unchanged_count += 1
        continue

    retained_modified_count += 1
    assertion_line_change_count += count_assertion_line_changes(original_file, adapted_file)

manifest_rows, malformed_manifest_rows = parse_removal_manifest(manifest_path)

removed_entries = []
undocumented = []
documented_removed_count = 0
removed_tests_by_category = {}
for rel in removed:
    manifest_row = manifest_rows.get(rel)
    category = ""
    reason = ""
    documented = False
    if manifest_row:
        category = manifest_row.get("category", "")
        reason = manifest_row.get("reason", "")
        documented = (
            manifest_row.get("well_formed", False)
            and manifest_row.get("category_valid", False)
            and manifest_row.get("reason_valid", False)
        )

    row = {
        "path": rel,
        "category": category,
        "reason": reason,
        "documented": documented,
    }
    removed_entries.append(row)
    if not documented:
        undocumented.append(row)
    else:
        documented_removed_count += 1
        removed_tests_by_category[category] = removed_tests_by_category.get(category, 0) + 1

junit = collect_junit_stats(repo_dir)

original_count = len(snapshot_files)
retained_count = len(retained)
removed_count = len(removed)
retention_ratio = None
if original_count > 0:
    retention_ratio = retained_count / original_count

obj = {
    "original_snapshot_file_count": original_count,
    "final_ported_test_file_count": int(final_ported_test_file_count),
    "retained_original_test_file_count": retained_count,
    "removed_original_test_file_count": removed_count,
    "retention_ratio": retention_ratio,
    "retained_modified_count": retained_modified_count,
    "retained_unchanged_count": retained_unchanged_count,
    "assertion_line_change_count": assertion_line_change_count,
    "removed_original_tests": removed_entries,
    "undocumented_removed_original_tests": undocumented,
    "undocumented_removed_test_count": len(undocumented),
    "documented_removed_test_count": documented_removed_count,
    "removed_tests_by_category": removed_tests_by_category,
    "removal_manifest_path": manifest_path,
    "removal_manifest_missing": not os.path.isfile(manifest_path),
    "removal_manifest_malformed_rows": malformed_manifest_rows,
    "removal_manifest_entry_count": len(manifest_rows),
    "junit_report_count": junit["junit_report_count"],
    "junit_report_files": junit["junit_report_files"],
    "junit_failing_case_count": junit["junit_failing_case_count"],
}

with open(out_json, "w", encoding="utf-8") as f:
    json.dump(obj, f, indent=2)
PY
}

tp_load_evidence_state() {
  local evidence_json="$1"
  eval "$(
    python3 - <<'PY' "$evidence_json"
import json
import shlex
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    obj = json.load(f)

def to_s(value):
    if value is None:
        return ""
    return str(value)

assignments = {
    "TP_EVIDENCE_ORIGINAL_SNAPSHOT_FILE_COUNT": obj.get("original_snapshot_file_count", 0),
    "TP_EVIDENCE_FINAL_PORTED_TEST_FILE_COUNT": obj.get("final_ported_test_file_count", 0),
    "TP_EVIDENCE_RETAINED_ORIGINAL_TEST_FILE_COUNT": obj.get("retained_original_test_file_count", 0),
    "TP_EVIDENCE_REMOVED_ORIGINAL_TEST_FILE_COUNT": obj.get("removed_original_test_file_count", 0),
    "TP_EVIDENCE_RETENTION_RATIO": to_s(obj.get("retention_ratio")),
    "TP_EVIDENCE_RETAINED_MODIFIED_COUNT": obj.get("retained_modified_count", 0),
    "TP_EVIDENCE_RETAINED_UNCHANGED_COUNT": obj.get("retained_unchanged_count", 0),
    "TP_EVIDENCE_ASSERTION_LINE_CHANGE_COUNT": obj.get("assertion_line_change_count", 0),
    "TP_EVIDENCE_UNDOCUMENTED_REMOVED_TEST_COUNT": obj.get("undocumented_removed_test_count", 0),
    "TP_EVIDENCE_JUNIT_REPORT_COUNT": obj.get("junit_report_count", 0),
    "TP_EVIDENCE_JUNIT_FAILING_CASE_COUNT": obj.get("junit_failing_case_count", 0),
}

for key, value in assignments.items():
    print(f"{key}={shlex.quote(to_s(value))}")
PY
  )"
}

tp_refresh_evidence_state() {
  local repo_dir="$1"
  local snapshot_dir="$2"
  local manifest_path="$3"
  local evidence_json="$4"
  tp_compute_evidence_json "$repo_dir" "$snapshot_dir" "$manifest_path" "$evidence_json"
  tp_load_evidence_state "$evidence_json"
}

tp_write_evidence_feedback_summary() {
  local out_path="$1"
  local evidence_json="$2"
  local headline="$3"
  local manifest_rel="$4"

  python3 - <<'PY' "$out_path" "$evidence_json" "$headline" "$manifest_rel"
import json
import sys

out_path, evidence_path, headline, manifest_rel = sys.argv[1:]
with open(evidence_path, "r", encoding="utf-8") as f:
    obj = json.load(f)

ratio = obj.get("retention_ratio")
ratio_s = "n/a" if ratio is None else f"{ratio:.3f}"

lines = [
    headline,
    "",
    f"JUnit reports: {obj.get('junit_report_count', 0)}",
    f"JUnit failing cases: {obj.get('junit_failing_case_count', 0)}",
    f"Retained original tests: {obj.get('retained_original_test_file_count', 0)}/{obj.get('original_snapshot_file_count', 0)}",
    f"Removed original tests: {obj.get('removed_original_test_file_count', 0)}",
    f"Retention ratio: {ratio_s}",
    f"Undocumented removals: {obj.get('undocumented_removed_test_count', 0)}",
    f"Removal manifest path: {manifest_rel}",
]

undocumented = obj.get("undocumented_removed_original_tests", [])
if undocumented:
    lines.append("")
    lines.append("Undocumented removed tests:")
    for entry in undocumented[:50]:
        lines.append(f"- {entry.get('path', '<unknown>')}")

removed = obj.get("removed_original_tests", [])
if removed:
    lines.append("")
    lines.append("Removed tests:")
    for entry in removed[:50]:
        category = entry.get("category", "")
        reason = entry.get("reason", "")
        documented = "yes" if entry.get("documented") else "no"
        lines.append(f"- {entry.get('path', '<unknown>')} | documented={documented} | category={category or '<none>'} | reason={reason or '<none>'}")

with open(out_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY
}
