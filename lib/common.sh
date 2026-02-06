#!/bin/bash
set -euo pipefail

ODOO_DATA_DIR=${ODOO_DATA_DIR:-/var/lib/odoo}
SRC=${SRC:-/opt/odoo/src}
ODOO_CONF_DIR=${ODOO_CONF_DIR:-/etc/odoo}
ODOO_CONF=${ODOO_CONF:-${ODOO_CONF_DIR}/odoo.conf}

ODOO_DIR=${ODOO_DIR:-${SRC}/odoo}
ODOO_BIN=${ODOO_BIN:-${ODOO_DIR}/odoo-bin}

ODOO_SHELL_PORT=${ODOO_SHELL_PORT:-19999}

AGG=${AGG:-repos.yaml}

PYTHON=${PYTHON:-python}

SCRIPTS_BIN=${SCRIPTS_BIN:-${HOME}/.local/bin}

# Install Python packages with common pip options
# Usage: pip_install [pip args...]
pip_install() {
  exec pip install --upgrade --user --no-cache-dir \
    --constraint "${ODOO_CONF_DIR}/constraints.txt" \
    "$@"
}

# Execute Odoo with common configuration
# Usage: odoo_exec <subcommand> [args...]
odoo_exec() {
  local cmd="${1:-}"
  if [ -n "${cmd}" ]; then
    shift
    exec "${PYTHON}" "${ODOO_BIN}" "${cmd}" --config "${ODOO_CONF}" "$@"
  else
    echo "Usage: odoo_exec <subcommand> [args...]" >&2
    exit 2
  fi
}