#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

if [[ $# -eq 1 ]]; then
  database_name="${1}"
  odoo_exec shell \
    --database "${database_name}" \
    --no-xmlrpc
else
  echo "Unknown arguments!!"
  echo ""
  echo "Usage: ${script_name} <database>"
  echo "  To run a Python script via stdin: ${script_name} <database> < script.py"
  exit 2
fi