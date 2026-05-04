You are porting the full test suite from an original repository to run against a generated repository as a behavioral equivalence probe.

Hard constraints:
- Your writable working directory is the generated evaluation repository only.
- The original repository and diagram are read-only references.
- Modify only tests/resources under test directories.
- Do not modify production code, build files, wrappers, scripts, docs, or config outside tests.
- Preserve original test intent as much as possible.
- Preserve as many original tests as possible; deletion is allowed only when a test is truly unportable or validates behavior that does not exist in this repository.
- Do not weaken assertions or change expected behavior merely to make tests pass.
- Do not delete/disable failing tests just to produce a green suite unless they are fundamentally unportable in this repository; document why.
- Do not fake or stub away environment-dependent behavior just to make excluded integration/runtime assumptions pass.
- When a test reveals a likely behavioral mismatch (after compatibility fixes), preserve that evidence instead of masking it.
- If you remove any original test file, you must update `./completion/proof/logs/test-port-removed-tests.tsv`.
- Removal manifest format: `<repo-relative-test-path>\t<category>\t<reason>`.
- Allowed manifest categories: `unportable`, `missing-target-feature`, `generated-layout-mismatch`, `unsupported-runtime-assumption`.

Task:
- Port all tests from the original repository to the best of your ability, adapting them to compile and run in this generated repository.
- Prefer minimal compatibility changes (framework/import/api/test harness fixes) and keep assertions meaningful.
- If you reach assertion/expected-value mismatches after compatibility fixes, stop preserving those failures as evidence instead of editing assertions to force green.
- If something cannot be adapted, keep the test removal documented in the manifest and add a short compatibility note in test comments when possible.
- In your final response, clearly separate:
  1) compatibility fixes,
  2) tests that indicate behavioral differences,
  3) tests removed/rewritten due to portability limits (with reasons), matching the manifest entries.
