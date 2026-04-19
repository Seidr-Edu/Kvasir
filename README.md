# Kvasir (test-port)

Standalone model-driven test adaptation/evaluation tool used by experiments.
The external service/repo name is `Kvasir`; the runner and artifact naming remain `test-port`.

## Purpose

- Run baseline tests on original and generated repos in isolated copies
- Port original tests into a generated repo copy using the local adapter prompts
- Enforce tests-only write scope
- Preserve behavioral mismatch evidence
- Emit `test_port.json` and `summary.md`

## Entry points

- Human CLI: `./test-port-run.sh`
- Human CLI alias: `./kvasir-run.sh`
- Container/service entrypoint: `./kvasir-service.sh`

Inside the monorepo this tool lives at `tools/test_port/`.
When synced into the standalone `Kvasir` repo, these files live at repo root.

## Example

```bash
./test-port-run.sh \
  --generated-repo /abs/path/to/generated-repo \
  --original-repo /abs/path/to/original-repo \
  --adapter claude \
  --diagram /abs/path/to/diagram.puml
```

`--adapter` is required.

Artifacts are written to `.data/test-port/runs/<run-id>/` by default, or to `--run-dir`.

## Container service contract

Kvasir is packaged as a service container, not just a shell script inside an image.

Mount contract:

- Read-only: `/input/original-repo`
- Read-only: `/input/generated-repo`
- Read-only optional: `/input/model`
- Writable: `/run`

Required outputs:

- `/run/outputs/test_port.json`
- `/run/outputs/summary.md`

Debug/analysis artifacts:

- `/run/logs/`
- `/run/workspace/`

Input repos are immutable from the service point of view. Kvasir copies them into `/run/workspace/` and mutates only those copies.

## Service configuration

`kvasir-service.sh` accepts env vars and an optional Kvasir-specific manifest:

- `KVASIR_MANIFEST` (optional override; default manifest path is `/run/config/manifest.yaml` when present)
- `KVASIR_ORIGINAL_REPO` (default `/input/original-repo`)
- `KVASIR_GENERATED_REPO` (default `/input/generated-repo`)
- `KVASIR_DIAGRAM` (default `/input/model/diagram.puml` when present)
- `KVASIR_RUN_DIR` (default `/run`)
- `KVASIR_ADAPTER`
- `KVASIR_ORIGINAL_SUBDIR`
- `KVASIR_GENERATED_SUBDIR`
- `KVASIR_MAX_ITER`
- `KVASIR_TEST_RUNNER_TIMEOUT_SEC` (default `7200`)
- `KVASIR_WRITE_SCOPE_IGNORE_PREFIXES`

The service entrypoint does not expose `--strict`; service verdicts belong in `test_port.json`.

Configuration precedence is:

1. Built-in defaults
2. Manifest values
3. Env var overrides

Manifest v1 fields:

- `version` (`1` required)
- `run_id`
- `adapter`
- `original_subdir`
- `generated_subdir`
- `diagram_relpath`
- `max_iter`
- `runner_timeout_sec`
- `write_scope_ignore_prefixes[]`

The manifest is intentionally service-specific so the orchestrator can mount only the configuration Kvasir is meant to consume.

## Docker

Build the standalone image from the tool root:

```bash
docker build -t kvasir:local .
docker run --rm kvasir:local --help
```

The image runs `kvasir-service.sh` as a non-root `kvasir` user (`uid=10001`, `gid=10001`).
The `/run` mount must therefore be writable by that user or otherwise permit writes.

Example container execution:

```bash
docker run --rm \
  -e KVASIR_ADAPTER=codex \
  -v /abs/path/to/original-repo:/input/original-repo:ro \
  -v /abs/path/to/generated-repo:/input/generated-repo:ro \
  -v /abs/path/to/model:/input/model:ro \
  -v /abs/path/to/run:/run \
  -v /abs/path/to/provider/bin:/opt/provider/bin:ro \
  -v /abs/path/to/provider/codex-home:/opt/provider-seed/codex-home:ro \
  kvasir:local
```

The image includes the shell, Java, and build-tool prerequisites for local execution.
Provider CLIs are not baked into the image. The caller should mount the selected provider binary directory at `/opt/provider/bin` and an authenticated Codex home at `/opt/provider-seed/codex-home`, both read-only. The service copies that auth seed into `/run/provider-state/codex-home` and sets `PATH` and `CODEX_HOME` internally before running adapter prereq checks.

## Exit semantics

For container/service usage:

- Exit `0`: a machine-readable result was emitted and the evaluation completed, regardless of verdict
- Exit `1`: contract/setup/prereq/reporting/internal failure prevented a normal evaluation result

Domain verdicts live in `test_port.json`; orchestration should read the report instead of inferring meaning from process exit codes.

Kvasir hardens provider CLI hangs in two layers:

- If the provider emits its final useful output but never exits, the adapter records `post-completion-hang-recovered`, reaps the provider process group, and preserves the normal run result.
- If the overall runner never returns before the configured timeout, service mode emits `result.reason=runner-timeout`, keeps writing reports, and exits `1`.

## Write-scope behavior

Write-scope policy remains `tests-only`, but known runtime/internal paths are ignored by default:

- `./completion/proof/logs/`
- `./.mvn_repo/`
- `./.m2/`
- `./.gradle/`
- `./target/`
- `./build/`

You can add more repo-relative ignored prefixes with:

- Repeatable CLI option: `--write-scope-ignore-prefix PATH`
- Env var: `TP_WRITE_SCOPE_IGNORE_PREFIXES` (colon-separated)

Example:

```bash
TP_WRITE_SCOPE_IGNORE_PREFIXES="tmp/cache:generated/reports" \
./test-port-run.sh \
  --generated-repo /abs/path/to/generated-repo \
  --original-repo /abs/path/to/original-repo \
  --write-scope-ignore-prefix completion/proof/logs
```

Ignored prefixes are reported in `test_port.json` under `diagnostics.write_scope.ignored_prefixes`.

## Maven local repository

When Maven is detected, test-port always runs Maven with:

`-Dmaven.repo.local=<run-dir>/workspace/.m2/repository`

This keeps dependency downloads out of copied repositories while reusing dependencies inside a single test-port run.

## Gradle cache and temp directories

When Gradle is detected, test-port runs with:

- `GRADLE_USER_HOME=<run-dir>/workspace/.gradle`
- `TMPDIR=<run-dir>/workspace/tmp`

This keeps Gradle cache/temp writes hermetic to the run workspace.

## Portable test scope

Kvasir defaults to `portable-tests` scope.

Portable tests are the tests that execute successfully in Kvasir's service environment. Integration, functional, or e2e-style tests are included when they pass without special environment assumptions. Tests or tasks are excluded from the porting scope when the original repo probe fails due missing services, credentials, Docker/Testcontainers, databases, brokers, network/config assumptions, or zero executed tests.

Maven scope selection:

- Probe broad `mvn test`.
- If broad passes and executes tests, port that scope.
- If broad fails with an environment assumption, probe a narrower command with integration-skip flags.
- If no command passes with non-zero executed tests, skip with `reason=no-portable-test-signal`.

Gradle scope selection:

- Probe candidate test tasks independently.
- Include passing tasks such as `test`, `integrationTest`, `functionalTest`, or `e2e`.
- Exclude failing environment-dependent tasks while keeping passing tasks.

Scope decisions are reported in `test_port.json` under `test_scope`, including selected commands/tasks, excluded commands/tasks with reasons, probe logs, and included/excluded test-file counts.

## Module/subdir selection

- `--original-subdir` selects the original module root for baseline snapshotting.
- `--generated-subdir` selects the generated module root for generated baseline and ported execution.
- If `--generated-subdir` is omitted, test-port attempts auto-detection from copied original tests and build markers.

## Retention policy

Test-port maximizes retained original tests across iterations:

- It does not stop at the first passing adaptation if original tests were removed.
- It keeps iterating (up to `--max-iter`) and selects the best valid iteration with the highest retained original-test count.
- It stops early only when full retention is reached.

Retained/removed metrics are reported in `test_port.json` under `evidence.retention`:

- `retained_original_test_file_count`
- `removed_original_test_file_count`
- `retention_ratio` (`retained_original/original_snapshot`)

## Removed-test manifest contract

If an original test file is removed, it must be documented in:

`./completion/proof/logs/test-port-removed-tests.tsv`

Format (tab-separated):

`<repo-relative-test-path>\t<category>\t<reason>`

Allowed categories:

- `unportable`
- `missing-target-feature`
- `generated-layout-mismatch`
- `unsupported-runtime-assumption`

Undocumented or invalidly documented removed original tests fail the iteration with:

- `reason=retention-policy-violation`
- `failure_class=invalid-removal-documentation`

The reason column must include a concrete, non-placeholder rationale.

Detailed entries are reported in `test_port.json` under `evidence.retention.removed_tests`.

## Runner preflight and no-test-signal

Before running adaptation/baselines, test-port captures runner diagnostics in `test_port.json`:

- `diagnostics.runner.detected_runner`
- `diagnostics.runner.supported`
- `diagnostics.runner.missing_capabilities[]`
- `diagnostics.runner.module_root`
- `diagnostics.runner.frameworks_detected[]`

Unsupported/missing capabilities produce:

- `result.status=skipped`
- `result.reason=unsupported-test-runner`

If tests exit `0` but `tests_executed == 0`, test-port does not emit a pass verdict:

- `result.status=skipped`
- `result.reason=no-test-signal` or `result.reason=no-portable-test-signal`
- `result.verdict=no_test_signal`

## Output schema v3 highlights

`outputs/test_port.json` uses `schema_version: "kvasir.test_port.v3"` with compact per-run sections:

- `result`
- `inputs`
- `test_scope`
- `baselines`
- `porting`
- `evidence`
- `diagnostics`
- `artifacts`

Legacy compatibility fields such as `status_detail`, `failure_class_legacy`, `runner_preflight`, `suite_shape`, Maven-specific unit/full fallback fields, and top-level `removed_original_tests` are intentionally omitted from v3.

`result.verdict=no_difference_detected` is only emitted when the selected portable original baseline is comparable/pass, ported tests pass, and non-zero tests executed.

## Runner support roadmap

Current execution support:

- Maven Surefire/Failsafe (JUnit4/JUnit5/TestNG via Maven runner)
- Gradle `Test` tasks, including custom portable tasks such as `integrationTest`, `functionalTest`, and `e2e`

Current preflight-only / planned:

- Node/Jest and non-Java runners: detected as unsupported today, surfaced via `diagnostics.runner.missing_capabilities`.
