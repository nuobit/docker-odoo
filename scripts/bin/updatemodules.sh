#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

if [[ $# -eq 2 ]]; then
  database_name="${1}"
  mode="${2}"
  if [[ ${mode} == "changed" ]]; then
      exec env PYTHONPATH="${ODOO_DIR}" click-odoo-update \
        --config "${ODOO_CONF}" \
        --database "${database_name}"
  else
      odoo_exec server \
        --database "${database_name}" \
        --no-xmlrpc \
        --update "${mode}" \
        --stop-after-init
  fi
else
  echo "Unknown arguments!!"
  echo ""
  echo "Usage: ${script_name} <database> <all|module_list|changed>"
  exit 2
fi