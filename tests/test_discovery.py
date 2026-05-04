#!/usr/bin/env python3
"""Tests for scripts/lib/tp_discovery.py"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts" / "lib"))
from tp_discovery import (
    build_manifest,
    main,
    map_rel_to_ported_repo,
    minimize_roots,
    normalize_candidate_dir,
    source_set_is_test_like,
    standard_test_root_for_parts,
)


def make_file(path: Path, content: str = "") -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


# ── source_set_is_test_like ──────────────────────────────────────────────────

class TestSourceSetIsTestLike:
    def test_empty_returns_false(self):
        assert source_set_is_test_like("") is False

    @pytest.mark.parametrize("name", ["testFixtures", "testfixtures", "TESTFIXTURES"])
    def test_testfixtures_excluded(self, name):
        assert source_set_is_test_like(name) is False

    @pytest.mark.parametrize("name", [
        "test", "Test", "tests",
        "integration", "integrationTest", "IntegrationTest",
        "IT", "it",
        "myIT", "SomethingIT",
        "spec", "Spec",
        "functional", "e2e", "acceptance", "verification",
    ])
    def test_test_like_names(self, name):
        assert source_set_is_test_like(name) is True

    @pytest.mark.parametrize("name", ["main", "java", "kotlin", "resources", "docs"])
    def test_non_test_names(self, name):
        assert source_set_is_test_like(name) is False


# ── standard_test_root_for_parts ─────────────────────────────────────────────

class TestStandardTestRootForParts:
    def test_too_short_returns_none(self):
        assert standard_test_root_for_parts([]) is None
        assert standard_test_root_for_parts(["Foo.java"]) is None

    def test_top_level_test_dir(self):
        assert standard_test_root_for_parts(["test", "Foo.java"]) == "./test"

    def test_top_level_tests_dir(self):
        assert standard_test_root_for_parts(["tests", "Foo.java"]) == "./tests"

    def test_src_test_layout(self):
        assert standard_test_root_for_parts(["src", "test", "java", "Foo.java"]) == "./src/test"

    def test_src_integration_test_sourceset(self):
        assert standard_test_root_for_parts(["src", "integrationTest", "java", "Foo.java"]) == "./src/integrationTest"

    def test_src_main_not_test(self):
        assert standard_test_root_for_parts(["src", "main", "java", "Foo.java"]) is None

    def test_no_test_segment_returns_none(self):
        assert standard_test_root_for_parts(["src", "main", "resources", "config.xml"]) is None

    def test_nested_test_segment_at_non_zero_index(self):
        # docs/test/example.txt — test segment at idx=1 (after docs).
        # This is the documented over-broad case: any test/ directory qualifies.
        assert standard_test_root_for_parts(["docs", "test", "example.txt"]) == "./docs/test"


# ── normalize_candidate_dir ──────────────────────────────────────────────────

class TestNormalizeCandidateDir:
    def test_empty_returns_none(self, tmp_path):
        assert normalize_candidate_dir(tmp_path, tmp_path, "") is None
        assert normalize_candidate_dir(tmp_path, tmp_path, "   ") is None

    def test_variable_ref_returns_none(self, tmp_path):
        assert normalize_candidate_dir(tmp_path, tmp_path, "${project.build.directory}/test") is None
        assert normalize_candidate_dir(tmp_path, tmp_path, "$HOME/test") is None

    def test_url_returns_none(self, tmp_path):
        assert normalize_candidate_dir(tmp_path, tmp_path, "http://example.com/test") is None

    def test_nonexistent_dir_returns_none(self, tmp_path):
        assert normalize_candidate_dir(tmp_path, tmp_path, "src/test") is None

    def test_outside_repo_returns_none(self, tmp_path):
        assert normalize_candidate_dir(tmp_path, tmp_path, str(tmp_path.parent)) is None

    def test_valid_relative_path(self, tmp_path):
        target = tmp_path / "src" / "test"
        target.mkdir(parents=True)
        assert normalize_candidate_dir(tmp_path, tmp_path, "src/test") == target

    def test_absolute_path_inside_repo(self, tmp_path):
        target = tmp_path / "src" / "test"
        target.mkdir(parents=True)
        assert normalize_candidate_dir(tmp_path, tmp_path, str(target)) == target

    def test_pruned_dir_returns_none(self, tmp_path):
        (tmp_path / "node_modules" / "test").mkdir(parents=True)
        assert normalize_candidate_dir(tmp_path, tmp_path, "node_modules/test") is None

    def test_file_not_dir_returns_none(self, tmp_path):
        make_file(tmp_path / "src" / "test")
        assert normalize_candidate_dir(tmp_path, tmp_path, "src/test") is None


# ── minimize_roots ───────────────────────────────────────────────────────────

class TestMinimizeRoots:
    def test_single_root_kept(self, tmp_path):
        r = tmp_path / "src" / "test"
        assert minimize_roots(tmp_path, {r}) == [r]

    def test_parent_dominates_child(self, tmp_path):
        parent = tmp_path / "src" / "test"
        child = tmp_path / "src" / "test" / "java"
        result = minimize_roots(tmp_path, {parent, child})
        assert result == [parent]

    def test_siblings_both_kept(self, tmp_path):
        a = tmp_path / "src" / "test"
        b = tmp_path / "src" / "integrationTest"
        result = minimize_roots(tmp_path, {a, b})
        assert set(result) == {a, b}

    def test_three_levels_keeps_shallowest(self, tmp_path):
        grandparent = tmp_path / "test"
        parent = tmp_path / "test" / "unit"
        child = tmp_path / "test" / "unit" / "java"
        result = minimize_roots(tmp_path, {grandparent, parent, child})
        assert result == [grandparent]

    def test_empty_set_returns_empty(self, tmp_path):
        assert minimize_roots(tmp_path, set()) == []


# ── map_rel_to_ported_repo ───────────────────────────────────────────────────

class TestMapRelToPortedRepo:
    def test_no_subdir_passthrough(self):
        assert map_rel_to_ported_repo("./src/test/Foo.java", None) == "./src/test/Foo.java"
        assert map_rel_to_ported_repo("./src/test/Foo.java", "") == "./src/test/Foo.java"

    def test_plain_subdir(self):
        assert map_rel_to_ported_repo("./src/test/Foo.java", "myapp") == "./myapp/src/test/Foo.java"

    def test_dotslash_prefixed_subdir(self):
        assert map_rel_to_ported_repo("./src/test/Foo.java", "./myapp") == "./myapp/src/test/Foo.java"

    def test_already_under_subdir_passthrough(self):
        assert map_rel_to_ported_repo("./myapp/src/test/Foo.java", "myapp") == "./myapp/src/test/Foo.java"

    def test_nested_subdir(self):
        assert map_rel_to_ported_repo("./src/test/Foo.java", "a/b") == "./a/b/src/test/Foo.java"

    def test_trailing_dot_subdir_preserved(self):
        # Regression test for strip("./") → lstrip("./") fix.
        # The old strip("./") would strip the trailing dot, giving "./mymodule/..."
        # lstrip("./") preserves it, matching shell ${var#./} behavior.
        result = map_rel_to_ported_repo("./src/test/Foo.java", "mymodule.")
        assert result == "./mymodule./src/test/Foo.java"


# ── build_manifest – standard layouts ────────────────────────────────────────

class TestBuildManifestStandard:
    def test_src_test_layout(self, tmp_path):
        make_file(tmp_path / "src/test/java/com/example/FooTest.java")
        make_file(tmp_path / "src/main/java/com/example/Foo.java")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1
        paths = [f["path"] for f in m["files"]]
        assert "./src/test/java/com/example/FooTest.java" in paths
        assert "./src/main/java/com/example/Foo.java" not in paths

    def test_top_level_test_dir(self, tmp_path):
        make_file(tmp_path / "test/FooTest.java")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1
        assert m["files"][0]["path"] == "./test/FooTest.java"

    def test_top_level_tests_dir(self, tmp_path):
        make_file(tmp_path / "tests/FooTest.java")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_integration_test_sourceset(self, tmp_path):
        make_file(tmp_path / "src/integrationTest/java/FooIT.java")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1
        assert "./src/integrationTest" in m["roots"]

    def test_no_test_files_empty_manifest(self, tmp_path):
        make_file(tmp_path / "src/main/java/Foo.java")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 0
        assert m["files"] == []
        assert m["roots"] == []

    def test_files_sorted(self, tmp_path):
        make_file(tmp_path / "src/test/java/ZTest.java")
        make_file(tmp_path / "src/test/java/ATest.java")
        m = build_manifest(tmp_path)
        paths = [f["path"] for f in m["files"]]
        assert paths == sorted(paths)

    def test_pruned_dirs_excluded(self, tmp_path):
        for pruned in ("node_modules", "target", "build", ".gradle", "vendor"):
            make_file(tmp_path / pruned / "test" / "SomeTest.java")
        make_file(tmp_path / "src/test/java/RealTest.java")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1
        assert all(
            pruned not in f["path"]
            for f in m["files"]
            for pruned in ("node_modules", "target", "build", ".gradle", "vendor")
        )

    def test_root_minimized_to_shallowest(self, tmp_path):
        # src/test is the canonical root; src/test/java should not appear separately.
        make_file(tmp_path / "src/test/java/FooTest.java")
        m = build_manifest(tmp_path)
        assert "./src/test" in m["roots"]
        assert "./src/test/java" not in m["roots"]

    def test_file_deduplication_across_strategies(self, tmp_path):
        # Maven points at src/test/java; standard discovery finds src/test.
        # After minimization the file must be counted exactly once.
        make_file(tmp_path / "src/test/java/FooTest.java")
        pom = (
            "<project><build>"
            "<testSourceDirectory>src/test/java</testSourceDirectory>"
            "</build></project>"
        )
        make_file(tmp_path / "pom.xml", pom)
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_repo_root_in_manifest(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        m = build_manifest(tmp_path)
        assert m["repo_root"] == str(tmp_path.resolve())


# ── build_manifest – Maven ───────────────────────────────────────────────────

class TestBuildManifestMaven:
    def test_custom_test_source_directory(self, tmp_path):
        make_file(tmp_path / "src/custom-tests/FooTest.java")
        pom = (
            "<project><build>"
            "<testSourceDirectory>src/custom-tests</testSourceDirectory>"
            "</build></project>"
        )
        make_file(tmp_path / "pom.xml", pom)
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1
        assert "./src/custom-tests" in m["roots"]

    def test_namespaced_xml(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        pom = (
            '<project xmlns="http://maven.apache.org/POM/4.0.0">'
            "<build><testSourceDirectory>src/test/java</testSourceDirectory></build>"
            "</project>"
        )
        make_file(tmp_path / "pom.xml", pom)
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_variable_reference_ignored(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        pom = (
            "<project><build>"
            "<testSourceDirectory>${project.build.directory}/test-sources</testSourceDirectory>"
            "</build></project>"
        )
        make_file(tmp_path / "pom.xml", pom)
        m = build_manifest(tmp_path)
        # Variable ref is skipped; standard discovery still finds the file.
        assert m["discovered_test_file_count"] == 1

    def test_malformed_pom_does_not_crash(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        make_file(tmp_path / "pom.xml", "<<< not xml >>>")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_nonexistent_test_directory_skipped(self, tmp_path):
        pom = (
            "<project><build>"
            "<testSourceDirectory>src/does-not-exist</testSourceDirectory>"
            "</build></project>"
        )
        make_file(tmp_path / "pom.xml", pom)
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 0

    def test_multimodule_maven(self, tmp_path):
        make_file(tmp_path / "module-a/src/test/java/ATest.java")
        make_file(tmp_path / "module-b/src/test/java/BTest.java")
        make_file(tmp_path / "pom.xml", "<project/>")
        make_file(tmp_path / "module-a/pom.xml", "<project/>")
        make_file(tmp_path / "module-b/pom.xml", "<project/>")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 2


# ── build_manifest – Gradle ──────────────────────────────────────────────────

class TestBuildManifestGradle:
    def test_standard_test_sourceset(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        make_file(tmp_path / "build.gradle", "apply plugin: 'java'")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_custom_sourceset_identifier_creates_root(self, tmp_path):
        # 'integration' identifier in the build file + src/integration/ on disk → discovered.
        make_file(tmp_path / "src/integration/java/FooIT.java")
        make_file(tmp_path / "build.gradle", "sourceSets { integration { } }")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_quoted_srcdir_path(self, tmp_path):
        # A quoted path inside a srcDir context that has a test-like segment.
        make_file(tmp_path / "src/it/java/FooIT.java")
        gradle = (
            "sourceSets {\n"
            "    integrationTest {\n"
            "        java { srcDir 'src/it/java' }\n"
            "    }\n"
            "}\n"
        )
        make_file(tmp_path / "build.gradle", gradle)
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1
        paths = [f["path"] for f in m["files"]]
        assert "./src/it/java/FooIT.java" in paths

    def test_build_gradle_kts_supported(self, tmp_path):
        make_file(tmp_path / "src/test/kotlin/FooTest.kt")
        make_file(tmp_path / "build.gradle.kts", 'plugins { kotlin("jvm") }')
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1

    def test_nonexistent_sourceset_dir_not_added(self, tmp_path):
        # Identifier present but src/integration/ doesn't exist → no root added.
        make_file(tmp_path / "build.gradle", "sourceSets { integration { } }")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 0

    def test_malformed_build_file_does_not_crash(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        make_file(tmp_path / "build.gradle", "\x00\xff invalid \x00")
        m = build_manifest(tmp_path)
        assert m["discovered_test_file_count"] == 1


# ── cmd_scan via main() ───────────────────────────────────────────────────────

class TestCmdScan:
    def test_writes_json_with_correct_structure(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        out = tmp_path / "manifest.json"
        rc = main(["scan", str(tmp_path), "--json-out", str(out)])
        assert rc == 0
        data = json.loads(out.read_text())
        assert data["discovered_test_file_count"] == 1
        assert data["repo_root"] == str(tmp_path.resolve())
        assert "./src/test/java/FooTest.java" in [f["path"] for f in data["files"]]

    def test_creates_parent_dirs(self, tmp_path):
        make_file(tmp_path / "src/test/java/FooTest.java")
        out = tmp_path / "deep/nested/manifest.json"
        rc = main(["scan", str(tmp_path), "--json-out", str(out)])
        assert rc == 0
        assert out.exists()

    def test_prints_to_stdout_without_json_out(self, tmp_path, capsys):
        make_file(tmp_path / "src/test/java/FooTest.java")
        rc = main(["scan", str(tmp_path)])
        assert rc == 0
        data = json.loads(capsys.readouterr().out)
        assert data["discovered_test_file_count"] == 1


# ── cmd_shell_state via main() ────────────────────────────────────────────────

class TestCmdShellState:
    def _write_manifest(self, path: Path, roots: list[str], count: int) -> None:
        path.write_text(
            json.dumps({"repo_root": "/repo", "discovered_test_file_count": count, "roots": roots, "files": []}),
            encoding="utf-8",
        )

    def test_outputs_shell_assignments(self, tmp_path, capsys):
        p = tmp_path / "manifest.json"
        self._write_manifest(p, ["./src/test", "./src/integrationTest"], 3)
        rc = main(["shell-state", str(p)])
        assert rc == 0
        out = capsys.readouterr().out
        # shlex.quote omits quotes for safe strings, so just check key=value presence.
        assert "TP_DISCOVERED_TEST_FILE_COUNT=" in out
        assert "3" in out
        assert "TP_DISCOVERED_TEST_ROOTS_CSV=" in out
        assert "./src/test" in out
        assert "./src/integrationTest" in out

    def test_empty_roots(self, tmp_path, capsys):
        p = tmp_path / "manifest.json"
        self._write_manifest(p, [], 0)
        rc = main(["shell-state", str(p)])
        assert rc == 0
        out = capsys.readouterr().out
        assert "TP_DISCOVERED_TEST_FILE_COUNT=" in out
        assert "0" in out


# ── cmd_copy via main() ───────────────────────────────────────────────────────

class TestCmdCopy:
    def _write_manifest(self, path: Path, source: Path, files: list[str]) -> None:
        path.write_text(
            json.dumps({
                "repo_root": str(source),
                "discovered_test_file_count": len(files),
                "roots": ["./src/test"],
                "files": [{"path": f, "root": "./src/test"} for f in files],
            }),
            encoding="utf-8",
        )

    def test_basic_copy(self, tmp_path):
        source = tmp_path / "source"
        make_file(source / "src/test/java/FooTest.java", "class FooTest {}")
        manifest = tmp_path / "manifest.json"
        self._write_manifest(manifest, source, ["./src/test/java/FooTest.java"])
        target = tmp_path / "target"
        rc = main(["copy", str(source), str(manifest), str(target)])
        assert rc == 0
        assert (target / "src/test/java/FooTest.java").read_text() == "class FooTest {}"

    def test_copy_with_generated_subdir(self, tmp_path):
        source = tmp_path / "source"
        make_file(source / "src/test/java/FooTest.java")
        manifest = tmp_path / "manifest.json"
        self._write_manifest(manifest, source, ["./src/test/java/FooTest.java"])
        target = tmp_path / "target"
        rc = main(["copy", str(source), str(manifest), str(target), "--generated-subdir", "myapp"])
        assert rc == 0
        assert (target / "myapp/src/test/java/FooTest.java").exists()
        assert not (target / "src/test/java/FooTest.java").exists()

    def test_copy_trailing_dot_subdir(self, tmp_path):
        # Regression for lstrip("./") fix: subdir with trailing dot must not be stripped.
        source = tmp_path / "source"
        make_file(source / "src/test/FooTest.java")
        manifest = tmp_path / "manifest.json"
        self._write_manifest(manifest, source, ["./src/test/FooTest.java"])
        target = tmp_path / "target"
        rc = main(["copy", str(source), str(manifest), str(target), "--generated-subdir", "mymodule."])
        assert rc == 0
        assert (target / "mymodule./src/test/FooTest.java").exists()

    def test_missing_source_file_is_skipped(self, tmp_path):
        source = tmp_path / "source"
        source.mkdir()
        manifest = tmp_path / "manifest.json"
        self._write_manifest(manifest, source, ["./src/test/java/Missing.java"])
        target = tmp_path / "target"
        rc = main(["copy", str(source), str(manifest), str(target)])
        assert rc == 0
        assert not list(target.rglob("*.java"))

    def test_existing_files_not_wiped(self, tmp_path):
        # cmd_copy must not rmtree the target; pre-existing files must survive.
        source = tmp_path / "source"
        make_file(source / "src/test/FooTest.java")
        manifest = tmp_path / "manifest.json"
        self._write_manifest(manifest, source, ["./src/test/FooTest.java"])
        target = tmp_path / "target"
        existing = target / "existing.txt"
        existing.parent.mkdir(parents=True)
        existing.write_text("keep me")
        main(["copy", str(source), str(manifest), str(target)])
        assert existing.read_text() == "keep me"

    def test_copy_multiple_files(self, tmp_path):
        source = tmp_path / "source"
        make_file(source / "src/test/java/ATest.java")
        make_file(source / "src/test/java/BTest.java")
        manifest = tmp_path / "manifest.json"
        self._write_manifest(manifest, source, [
            "./src/test/java/ATest.java",
            "./src/test/java/BTest.java",
        ])
        target = tmp_path / "target"
        rc = main(["copy", str(source), str(manifest), str(target)])
        assert rc == 0
        assert (target / "src/test/java/ATest.java").exists()
        assert (target / "src/test/java/BTest.java").exists()
