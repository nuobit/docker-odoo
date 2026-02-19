#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

if [[ $# -le 2 ]]; then
  addon_args=()
  if [[ -n "${1:-}" ]]; then
    addon_args+=(-d "${1}")
  fi
  if [[ -n "${2:-}" ]]; then
    addon_args+=(-j "${2}")
  fi
  pushd "${SRC_DIR}" > /dev/null
  gitaggregate -c "${INSTANCE_REPOS}" "${addon_args[@]}" aggregate
  popd > /dev/null
else
  echo "Usage: ${script_name} [addon_path] [jobs]" >&2
  exit 2
fi
