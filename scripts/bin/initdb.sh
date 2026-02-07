#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

if [[ ($# -eq 1 || ($# -eq 2 && "$2" == "demo")) ]]; then
  database_name="${1}"
  demo_flag="--without-demo=all"
  if [[ $# -eq 2 && "$2" == "demo" ]]; then
    demo_flag=""
  fi
  odoo_exec server \
    --database "${database_name}" \
    --init base \
    ${demo_flag} \
    --no-xmlrpc \
    --stop-after-init
else
  echo "Unknown arguments!!"
  echo ""
  echo "Usage: ${script_name} <database> [demo]"
  exit 2
fi