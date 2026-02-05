#!/bin/bash
set -euo pipefail

source "${HOME}/.local/lib/common.sh"

script_name="${0##*/}"

if [[ $# -le 2 ]]; then
  addon_path="${1:-}"
  jobs="${2:-}"
  addon_flag=""
  jobs_flag=""
  if [ -n "${addon_path}" ]; then
    addon_flag="-d ${addon_path}"
  fi
  if [ -n "${jobs}" ]; then
    jobs_flag="-j ${jobs}"
  fi
  pushd "${SRC}" > /dev/null
  gitaggregate -c "${AGG}" ${addon_flag} ${jobs_flag} aggregate
  popd > /dev/null
else
  echo "Unknown arguments!!"
  echo ""
  echo "Usage: ${script_name} [addon_path] [jobs]"
  exit 2
fi
