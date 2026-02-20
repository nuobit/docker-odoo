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

# Safely remove a directory with guards and confirmation.
# Rejects empty, whitespace-only, relative, root, or home-directory targets.
# Shows the target path and requires typing the directory name to confirm.
# Confirmation is skipped when force=true.
# Usage: safe_remove_dir <path> <force>
safe_remove_dir() {
  local target="${1}"
  local force="${2}"
  local dir_name
  dir_name="$(basename "${target}")"
  [[ -n "${target}" ]]              || { echo "ERROR: safe_remove_dir: target path is empty." >&2; exit 1; }
  [[ "${target}" =~ [^[:space:]] ]] || { echo "ERROR: safe_remove_dir: target path is whitespace-only." >&2; exit 1; }
  [[ "${target}" == /* ]]           || { echo "ERROR: safe_remove_dir: refusing to remove relative path '${target}'." >&2; exit 1; }
  [[ "${target}" != "/" ]]          || { echo "ERROR: safe_remove_dir: refusing to remove '/'." >&2; exit 1; }
  [[ "${target}" != "${HOME}" ]]    || { echo "ERROR: safe_remove_dir: refusing to remove HOME directory." >&2; exit 1; }
  if [[ "${force}" != true ]]; then
    echo "About to remove: '${target}'"
    read -p "Type '${dir_name}' to confirm: " confirm_input
    if [[ "${confirm_input}" != "${dir_name}" ]]; then
      echo "Confirmation failed. Aborting." >&2
      exit 1
    fi
  fi
  rm -rf "${target}"
}

# Debug helper: pause execution indefinitely.
# Not used in production. Add manually where needed during debugging.
# Usage: debug_pause "description"
debug_pause() {
  echo "DEBUG: Paused at '${1:-}'. Container will stay alive. Attach with 'docker exec'."
  sleep infinity
}