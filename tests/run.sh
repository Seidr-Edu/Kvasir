#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "== running test_discovery.py =="
python3 -m pytest -q "${SCRIPT_DIR}/test_discovery.py"
echo

scripts=(
  test_discovery.sh
  test_adapters.sh
  test_cli.sh
  test_write_guard.sh
  test_runner.sh
  test_build_env.sh
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
