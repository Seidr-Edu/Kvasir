#!/usr/bin/env bash
# registry.sh - Adapter registry for Kvasir.

_REGISTRY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# adapter_registry_list
# Prints registered adapter names, space-separated.
adapter_registry_list() {
  echo "codex claude"
}

# adapter_registry_get_script ADAPTER_NAME
# Prints the absolute path to the adapter implementation script.
# Returns 1 if the adapter name is not registered.
adapter_registry_get_script() {
  local adapter="$1"
  case "$adapter" in
    codex)
      echo "${_REGISTRY_DIR}/codex.sh"
      ;;
    claude)
      echo "${_REGISTRY_DIR}/claude.sh"
      ;;
    *)
      echo "Unknown adapter: ${adapter}" >&2
      return 1
      ;;
  esac
}
