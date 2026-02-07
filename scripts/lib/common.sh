#!/bin/bash
set -euo pipefail

# Source configuration (required)
CONFIG_FILE="${HOME}/config/paths.env"
if [ -f "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
else
    echo "ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
    exit 1
fi

# Install Python packages with common pip options
# Usage: pip_install [pip args...]
pip_install() {
    exec pip install --upgrade --user --no-cache-dir \
        --constraint "${DIST_CONFIG_CONSTRAINTS}" \
        "$@"
}

# Execute Odoo with common configuration
# Usage: odoo_exec <subcommand> [args...]
odoo_exec() {
  local cmd="${1:-}"
  if [ -n "${cmd}" ]; then
    shift
    exec "${PYTHON_BIN}" "${ODOO_BIN}" "${cmd}" --config "${ODOO_CONF}" "$@"
  else
    echo "Usage: odoo_exec <subcommand> [args...]" >&2
    exit 2
  fi
}