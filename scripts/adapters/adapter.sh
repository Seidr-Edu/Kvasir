#!/usr/bin/env bash
set -euo pipefail

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "${ADAPTER_DIR}/registry.sh"

_KVASIR_LOADED_ADAPTER=""

adapter_list() {
  adapter_registry_list
}

adapter_is_supported() {
  local adapter="$1"
  [[ -n "$adapter" ]] || return 1
  adapter_registry_get_script "$adapter" >/dev/null 2>&1
}

# _adapter_load ADAPTER_NAME
# Sources the adapter implementation script on first use.
_adapter_load() {
  local adapter="$1"
  if [[ "$_KVASIR_LOADED_ADAPTER" == "$adapter" ]]; then
    return 0
  fi
  local script
  script="$(adapter_registry_get_script "$adapter")" || {
    echo "Unsupported adapter: ${adapter}" >&2
    return 1
  }
  [[ -f "$script" ]] || {
    echo "Adapter script not found: ${script}" >&2
    return 1
  }
  # shellcheck source=/dev/null
  source "$script"
  _KVASIR_LOADED_ADAPTER="$adapter"
}

adapter_check_prereqs() {
  local adapter="$1"
  _adapter_load "$adapter" || return 1
  "${adapter}_check_prereqs"
}

adapter_run_test_port_initial() {
  local adapter="$1"
  shift
  _adapter_load "$adapter" || return 1
  "${adapter}_run_test_port_initial" "$@"
}

adapter_run_test_port_iteration() {
  local adapter="$1"
  shift
  _adapter_load "$adapter" || return 1
  "${adapter}_run_test_port_iteration" "$@"
}
