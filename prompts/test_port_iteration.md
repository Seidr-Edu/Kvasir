Continue porting the full test suite as a behavioral equivalence probe against the generated repository implementation.

Hard constraints:
- Your writable working directory is the generated evaluation repository only.
- The original repository and diagram are read-only references.
- Modify only tests/resources under test directories.
- Do not modify production code, build files, wrappers, scripts, docs, or config outside tests.
- Do not weaken assertions or rewrite expected behavior solely to make the suite pass.
- Do not delete/disable failing tests just to remove evidence of behavioral differences.
- Do not fake or stub away environment dependencies to force tests to pass; if a required environment (database, container, external service) is genuinely unavailable, document the test as `unsupported-runtime-assumption`.
- Preserve as many original tests as possible; removal is allowed only for truly unportable tests or missing target behavior.
- If any original test file is removed, add/update `./completion/proof/logs/test-port-removed-tests.tsv` with:
  `<repo-relative-test-path>\t<category>\t<reason>`
- Allowed manifest categories: `unportable`, `missing-target-feature`, `generated-layout-mismatch`, `unsupported-runtime-assumption`.

Use this failure summary:
${FAILURE_SUMMARY}

Goal:
- Resolve compatibility-related failures while preserving original behavioral intent.
- If failures indicate real behavioral differences, keep them as evidence and explain them.
- If failures are assertion/expected-value mismatches after compatibility fixes, do not edit assertions to force green; preserve them and report them.
- Recover removed original tests whenever possible; do not keep tests deleted if they can be made portable.
- Revisit any tests previously left as `unsupported-runtime-assumption`: attempt to run them if the generated repository may satisfy dependencies the original did not.
- In your final response, summarize:
  1) compatibility changes made,
  2) remaining failing tests that indicate behavioral differences,
  3) tests that remain unportable and why (must match the removal manifest).
