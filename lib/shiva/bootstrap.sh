#!/usr/bin/env bash

# Locate the shared Shiva library in development and installed layouts.
shiva_load_common() {
  local script_dir lib
  script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[1]}")" && pwd)"
  for lib in \
    "${SHIVA_LIB_DIR:-}" \
    "$script_dir/../lib/shiva" \
    "/usr/local/lib/shiva" \
    "/usr/lib/shiva"; do
    if [[ -n "$lib" && -r "$lib/common.sh" ]]; then
      source "$lib/common.sh"
      return 0
    fi
  done
  printf 'Shiva Toolkit library not found.\n' >&2
  return 1
}
