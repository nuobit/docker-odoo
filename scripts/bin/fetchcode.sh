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
  # shellcheck disable=SC2154  # SRC_DIR from defaults.env
  pushd "${SRC_DIR}" > /dev/null
  # shellcheck disable=SC2154  # INSTANCE_REPOS from defaults.env
  gitaggregate -c "${INSTANCE_REPOS}" "${addon_args[@]}" aggregate
  popd > /dev/null
else
  echo "Usage: ${script_name} [addon_path] [jobs]" >&2
  exit 2
fi
