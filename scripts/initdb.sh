#!/bin/bash
set -euo pipefail

source "${HOME}/.local/lib/common.sh"

script_name="${0##*/}"

if [[ $# -eq 1 ]]; then
  database_name="${1}"
  odoo_exec server \
    --database "${database_name}" \
    --init base \
    --no-xmlrpc \
    --stop-after-init
else
  echo "Unknown arguments!!"
  echo ""
  echo "Usage: ${script_name} <database>"
  exit 2
fi