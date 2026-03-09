#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

scripts=(
  test_cli.sh
  test_write_guard.sh
  test_runner.sh
  test_verdict.sh
  test_report.sh
  test_e2e_hermetic.sh
  test_service.sh
  test_container_integration.sh
)

for script in "${scripts[@]}"; do
  echo "== running ${script} =="
  bash "${SCRIPT_DIR}/${script}"
  echo
done

echo "All test-port test suites passed."
