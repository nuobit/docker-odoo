#!/bin/bash
set -euo pipefail

# Source configuration (required)
CONFIG_FILE="${HOME}/dist/defaults.env"
if [[ -f "${CONFIG_FILE}" ]]; then
  source "${CONFIG_FILE}"
else
  echo "ERROR: Configuration file not found: ${CONFIG_FILE}" >&2
  exit 1
fi

# Install Python packages with common pip options
# Usage: pip_install [pip args...]
pip_install() {
  pip install --upgrade --user --no-cache-dir \
    --constraint "${DIST_CONSTRAINTS}" \
    "$@"
}

# Execute Odoo with common configuration
# Usage: odoo_exec <subcommand> [args...]
odoo_exec() {
  local cmd="${1:-}"
  if [[ -n "${cmd}" ]]; then
    shift
    exec "${PYTHON_BIN}" "${ODOO_BIN}" "${cmd}" --config "${ODOO_CONF}" "$@"
  else
    echo "Usage: odoo_exec <subcommand> [args...]" >&2
    exit 2
  fi
}

# Debug helper: pause execution indefinitely.
# Not used in production. Add manually where needed during debugging.
# Usage: debug_pause "description"
debug_pause() {
  echo "DEBUG: Paused at '${1:-}'. Container will stay alive. Attach with 'docker exec'."
  sleep infinity
}