#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

if [[ $# -eq 1 ]]; then
  repo_path="${1}"
  # Resolve and verify the path stays within SRC_DIR to prevent traversal
  # shellcheck disable=SC2154  # SRC_DIR from defaults.env
  resolved="$(realpath -m "${SRC_DIR}/${repo_path}")"
  case "${resolved}" in
    "${SRC_DIR}/"*) ;;
    *) echo "ERROR: repo_path '${repo_path}' resolves outside SRC_DIR" >&2; exit 1 ;;
  esac
  pip_install \
    --requirement "${resolved}/requirements.txt"
else
  echo "Usage: ${script_name} <repo_path>" >&2
  exit 2
fi
