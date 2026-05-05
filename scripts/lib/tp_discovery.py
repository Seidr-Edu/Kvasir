#!/usr/bin/env python3
"""Canonical test discovery for Kvasir test-port."""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import shutil
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

PRUNED_DIR_NAMES = {
    ".cache",
    ".git",
    ".gradle",
    ".idea",
    ".m2",
    ".nox",
    ".pnpm-store",
    ".scannerwork",
    ".tox",
    ".venv",
    ".yarn",
    "__pycache__",
    "build",
    "coverage",
    "dist",
    "node_modules",
    "out",
    "target",
    "vendor",
    "venv",
}

TEST_IDENTIFIER_RE = re.compile(
    r"(^[iI][tT]$|^[iI][tT][A-Z0-9_].*|IT$|[Tt]est|[Ss]pec|[Ii]ntegration|[Ff]unctional|[Ee]2[Ee]|[Aa]cceptance|[Vv]erification)"
)
QUOTED_STRING_RE = re.compile(r"""(['"])(?P<value>.+?)\1""")


def relpath(root: Path, path: Path) -> str:
    return "./" + os.path.relpath(path, root).replace(os.sep, "/")


def local_name(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def source_set_is_test_like(name: str) -> bool:
    if not name:
        return False
    if name.lower() == "testfixtures":
        return False
    return bool(TEST_IDENTIFIER_RE.search(name))


def path_has_test_like_segment(path_value: str) -> bool:
    segments = [segment for segment in path_value.replace("\\", "/").split("/") if segment]
    return any(source_set_is_test_like(segment) for segment in segments)


def standard_test_root_for_parts(parts: list[str]) -> str | None:
    if len(parts) < 2:
        return None
    last_dir_idx = len(parts) - 2
    for idx in range(last_dir_idx + 1):
        part = parts[idx]
        if idx == 0 and part in {"test", "tests"}:
            return "./" + "/".join(parts[: idx + 1])
        if part == "src" and idx + 1 <= last_dir_idx:
            source_set = parts[idx + 1]
            if source_set_is_test_like(source_set):
                return "./" + "/".join(parts[: idx + 2])
    return None


def normalize_candidate_dir(repo_root: Path, base_dir: Path, raw_value: str) -> Path | None:
    text = raw_value.strip()
    if not text:
        return None
    if text.startswith("${") or text.startswith("$"):
        return None
    if "://" in text:
        return None

    candidate = Path(text)
    if not candidate.is_absolute():
        candidate = (base_dir / candidate).resolve()
    else:
        candidate = candidate.resolve()

    try:
        candidate.relative_to(repo_root)
    except ValueError:
        return None

    if not candidate.is_dir():
        return None
    if any(part in PRUNED_DIR_NAMES for part in candidate.relative_to(repo_root).parts):
        return None
    return candidate


def walk_build_files(repo_root: Path, names: set[str]) -> list[Path]:
    found: list[Path] = []
    for base, dirs, files in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in PRUNED_DIR_NAMES]
        for name in files:
            if name in names:
                found.append(Path(base) / name)
    found.sort()
    return found


def add_candidate_root(repo_root: Path, roots: set[Path], candidate: Path | None) -> None:
    if candidate is None:
        return
    if not candidate.is_dir():
        return
    try:
        candidate.relative_to(repo_root)
    except ValueError:
        return
    roots.add(candidate)


def discover_maven_roots(repo_root: Path, roots: set[Path]) -> None:
    for pom in walk_build_files(repo_root, {"pom.xml"}):
        module_dir = pom.parent
        try:
            root = ET.parse(pom).getroot()
        except Exception:
            continue

        for elem in root.iter():
            lname = local_name(elem.tag)
            if lname not in {"testSourceDirectory", "testSource"}:
                continue
            if elem.text is None:
                continue
            candidate = normalize_candidate_dir(repo_root, module_dir, elem.text)
            add_candidate_root(repo_root, roots, candidate)


def discover_gradle_roots(repo_root: Path, roots: set[Path]) -> None:
    build_files = walk_build_files(repo_root, {"build.gradle", "build.gradle.kts"})
    for build_file in build_files:
        base_dir = build_file.parent
        try:
            text = build_file.read_text(encoding="utf-8", errors="replace")
        except Exception:
            continue

        # Test-like identifiers often imply the default src/<name> source root.
        for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*)\b", text):
            name = match.group(1)
            if not source_set_is_test_like(name):
                continue
            default_root = normalize_candidate_dir(repo_root, base_dir, f"src/{name}")
            add_candidate_root(repo_root, roots, default_root)

        for match in QUOTED_STRING_RE.finditer(text):
            raw_path = match.group("value")
            candidate = normalize_candidate_dir(repo_root, base_dir, raw_path)
            if candidate is None:
                continue

            context_start = max(0, match.start() - 240)
            context_end = min(len(text), match.end() + 240)
            context = text[context_start:context_end]
            if not re.search(r"srcDir|srcDirs|setSrcDirs|testing|suite|sourceSet", context):
                continue
            if not path_has_test_like_segment(raw_path) and not TEST_IDENTIFIER_RE.search(context):
                continue

            add_candidate_root(repo_root, roots, candidate)


def discover_standard_roots(repo_root: Path, roots: set[Path]) -> None:
    for base, dirs, files in os.walk(repo_root):
        dirs[:] = [d for d in dirs if d not in PRUNED_DIR_NAMES]
        base_path = Path(base)
        for name in files:
            file_path = base_path / name
            rel_parts = file_path.relative_to(repo_root).parts
            root_rel = standard_test_root_for_parts(list(rel_parts))
            if root_rel is None:
                continue
            add_candidate_root(repo_root, roots, repo_root / root_rel[2:])


def minimize_roots(repo_root: Path, roots: set[Path]) -> list[Path]:
    ordered = sorted(roots, key=lambda path: (len(path.relative_to(repo_root).parts), str(path)))
    kept: list[Path] = []
    for candidate in ordered:
        if any(candidate == existing or existing in candidate.parents for existing in kept):
            continue
        kept.append(candidate)
    return kept


def collect_files(repo_root: Path, roots: list[Path]) -> tuple[list[dict[str, str]], list[str]]:
    file_rows: list[dict[str, str]] = []
    roots_with_files: set[str] = set()
    seen_files: set[str] = set()

    for root in roots:
        root_rel = relpath(repo_root, root)
        for base, dirs, files in os.walk(root):
            dirs[:] = [d for d in dirs if d not in PRUNED_DIR_NAMES]
            for name in files:
                file_path = Path(base) / name
                rel = relpath(repo_root, file_path)
                if rel in seen_files:
                    continue
                seen_files.add(rel)
                roots_with_files.add(root_rel)
                file_rows.append({"path": rel, "root": root_rel})

    file_rows.sort(key=lambda row: row["path"])
    return file_rows, sorted(roots_with_files)


def build_manifest(repo_root: Path) -> dict[str, object]:
    repo_root = repo_root.resolve()
    roots: set[Path] = set()

    discover_standard_roots(repo_root, roots)
    discover_maven_roots(repo_root, roots)
    discover_gradle_roots(repo_root, roots)

    minimized_roots = minimize_roots(repo_root, roots)
    files, roots_with_files = collect_files(repo_root, minimized_roots)

    return {
        "repo_root": str(repo_root),
        "discovered_test_file_count": len(files),
        "roots": roots_with_files,
        "files": files,
    }


def cmd_scan(args: argparse.Namespace) -> int:
    manifest = build_manifest(Path(args.repo))
    payload = json.dumps(manifest, indent=2)
    if args.json_out:
        Path(args.json_out).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json_out).write_text(payload + "\n", encoding="utf-8")
    else:
        print(payload)
    return 0


def load_manifest(path: str) -> dict[str, object]:
    with open(path, "r", encoding="utf-8") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise SystemExit("invalid discovery manifest")
    return obj


def map_rel_to_ported_repo(rel: str, generated_subdir: str | None) -> str:
    if not generated_subdir:
        return rel
    prefix = "./" + generated_subdir.lstrip("./")
    if rel == prefix or rel.startswith(prefix + "/"):
        return rel
    return prefix + "/" + rel[2:]


def cmd_count(args: argparse.Namespace) -> int:
    manifest = build_manifest(Path(args.repo))
    print(int(manifest.get("discovered_test_file_count", 0)))
    return 0


def cmd_roots(args: argparse.Namespace) -> int:
    manifest = build_manifest(Path(args.repo))
    for root in manifest.get("roots", []):
        print(root)
    return 0


def cmd_shell_state(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest_json)
    roots = manifest.get("roots", [])
    if not isinstance(roots, list):
        roots = []
    roots = [str(root) for root in roots if isinstance(root, str)]
    count = int(manifest.get("discovered_test_file_count", 0))
    print(f"TP_DISCOVERED_TEST_ROOTS_CSV={shlex.quote(':'.join(roots))}")
    print(f"TP_DISCOVERED_TEST_FILE_COUNT={shlex.quote(str(count))}")
    return 0


def cmd_copy(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest_json)
    source = Path(args.source).resolve()
    target = Path(args.target)

    target.mkdir(parents=True, exist_ok=True)

    files = manifest.get("files", [])
    if not isinstance(files, list):
        raise SystemExit("invalid discovery manifest files")

    copied = 0
    for row in files:
        if not isinstance(row, dict):
            continue
        rel = row.get("path")
        if not isinstance(rel, str) or not rel.startswith("./"):
            continue
        src = source / rel[2:]
        if not src.is_file():
            continue
        mapped_rel = map_rel_to_ported_repo(rel, args.generated_subdir)
        dst = target / mapped_rel[2:]
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        copied += 1

    print(copied)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    scan = sub.add_parser("scan")
    scan.add_argument("repo")
    scan.add_argument("--json-out")
    scan.set_defaults(func=cmd_scan)

    count = sub.add_parser("count")
    count.add_argument("repo")
    count.set_defaults(func=cmd_count)

    roots = sub.add_parser("roots")
    roots.add_argument("repo")
    roots.set_defaults(func=cmd_roots)

    shell_state = sub.add_parser("shell-state")
    shell_state.add_argument("manifest_json")
    shell_state.set_defaults(func=cmd_shell_state)

    copy = sub.add_parser("copy")
    copy.add_argument("source")
    copy.add_argument("manifest_json")
    copy.add_argument("target")
    copy.add_argument("--generated-subdir")
    copy.set_defaults(func=cmd_copy)

    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
