#!/bin/bash
set -euo pipefail

source "${HOME}/.local/lib/common.sh"

script_name="${0##*/}"

if [[ $# -eq 1 ]]; then
  repo_path="${1}"
  pip_install \
    --requirement "${SRC}/${repo_path}/requirements.txt"
else
  echo "Unknown arguments!!"
  echo ""
  echo "Usage: ${script_name} <repo_path>"
  exit 2
fi
