#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

# Read a value from odoo.conf by key name (last occurrence wins, whitespace trimmed).
odoo_conf_get() {
  grep -E "^ *${1} *=" "${ODOO_CONF}" | tail -n 1 | sed -En "s/^ *${1} *= *(\S+)\s*$/\1/p" || :
}

# Extract PostgreSQL connection info from Odoo config
DB_HOST=$(odoo_conf_get db_host)
DB_OWNER=$(odoo_conf_get db_user)
DB_OWNER_PASSWORD=$(odoo_conf_get db_password)

# Validate required parameters
[[ -n "${DB_HOST}" ]]           || { echo "ERROR: PostgreSQL host not configured. Set db_host in ${ODOO_CONF} or DB_HOST in settings.env" >&2; exit 1; }
[[ -n "${DB_PGUSER}" ]]        || { echo "ERROR: PostgreSQL admin user not configured. Set DB_PGUSER in settings.env" >&2; exit 1; }
[[ -n "${DB_PGDB}" ]]          || { echo "ERROR: PostgreSQL maintenance database not configured. Set DB_PGDB in settings.env" >&2; exit 1; }
[[ -n "${DB_OWNER}" ]]         || { echo "ERROR: PostgreSQL database owner not configured. Set db_user in ${ODOO_CONF}" >&2; exit 1; }
[[ -n "${DB_OWNER_PASSWORD}" ]] || { echo "ERROR: PostgreSQL database owner password not configured. Set db_password in ${ODOO_CONF}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: ${script_name} [-f|--force] <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  create <dbname>                Create a database"
  echo "  init <dbname> [demo]           Initialize Odoo base module in database"
  echo "  drop <dbname>                  Drop a database (terminates active connections)"
  echo "  reset <dbname>                 Drop and recreate a database (terminates active connections)"
  echo "  list                           List databases"
  echo "  users                          List PostgreSQL users"
  echo "  createuser                     Create DB owner user (password from db_password)"
  echo "  dropuser                       Drop DB owner user"
  echo ""
  echo "Options:"
  echo "  -f, --force       Skip database name confirmation prompt (drop/reset)"
  echo ""
  echo "Configuration:"
  echo "  Connection settings from odoo.conf (db_host, db_user, db_password)."
  echo "  Admin credentials from defaults.env (overridable in settings.env):"
  echo "    DB_PGUSER             PostgreSQL admin user (default: postgres)"
  echo "    DB_PGDB               PostgreSQL maintenance database (default: postgres)"
  echo "    DB_PGUSER_PASSWORD    PostgreSQL admin password (prompted if unset)"
  echo "    DB_FORCE              Skip database name confirmation on drop/reset"
  exit 2
}

# Ensure DB_PGUSER_PASSWORD is set, prompting interactively if needed.
require_pguser_password() {
  if [[ -z "${DB_PGUSER_PASSWORD:-}" ]]; then
    read -sp "Password for user ${DB_PGUSER}: " DB_PGUSER_PASSWORD
    echo ""
  fi
}

# Run a command as the PostgreSQL admin user.
# Usage: pg_admin <command> [args...]
pg_admin() {
  PGPASSWORD="${DB_PGUSER_PASSWORD}" "$@"
}

# Create a database with the unaccent extension.
# Usage: do_create_db <dbname>
do_create_db() {
  local dbname="${1}"
  echo "> Creating database ${dbname}..."
  pg_admin createdb -h "${DB_HOST}" -U "${DB_PGUSER}" -O "${DB_OWNER}" -- "${dbname}" || {
    echo "Failed to create database." >&2
    exit 1
  }
  echo "< Done!!"

  echo "> Creating extension unaccent..."
  pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" -d "${dbname}" -c "CREATE EXTENSION IF NOT EXISTS unaccent;" || {
    echo "Failed to create unaccent extension." >&2
    exit 1
  }
  echo "< Done!!"
}

# Block ALL new connections to a database (including superusers).
# Sets datallowconn = false. Use do_unblock_all_connections to reverse.
# Usage: do_block_all_connections <dbname>
do_block_all_connections() {
  local dbname="${1}"
  echo "> Blocking all connections to ${dbname}..."
  pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" -d "${DB_PGDB}" \
    -c "UPDATE pg_database SET datallowconn = false WHERE datname = '${dbname}';" \
    > /dev/null 2>&1 || true
  echo "< Done!!"
}

# Unblock ALL connections to a database.
# Sets datallowconn = true. Reverses do_block_all_connections.
# Usage: do_unblock_all_connections <dbname>
do_unblock_all_connections() {
  local dbname="${1}"
  echo "> Unblocking all connections to ${dbname}..."
  pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" -d "${DB_PGDB}" \
    -c "UPDATE pg_database SET datallowconn = true WHERE datname = '${dbname}';" \
    > /dev/null 2>&1 || true
  echo "< Done!!"
}

# Block non-superuser connections (sets CONNECTION LIMIT 0).
# Superusers can still connect. Use do_block_all_connections for a full block.
# Usage: do_block_user_connections <dbname>
do_block_user_connections() {
  local dbname="${1}"
  echo "> Blocking user connections to ${dbname} (limit=0)..."
  pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" -d "${DB_PGDB}" \
    -c "ALTER DATABASE \"${dbname}\" WITH CONNECTION LIMIT 0;" \
    > /dev/null 2>&1 || true
  echo "< Done!!"
}

# Unblock non-superuser connections (sets CONNECTION LIMIT -1 = unlimited).
# Reverses do_block_user_connections.
# Usage: do_unblock_user_connections <dbname>
do_unblock_user_connections() {
  local dbname="${1}"
  echo "> Unblocking user connections to ${dbname} (unlimited)..."
  pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" -d "${DB_PGDB}" \
    -c "ALTER DATABASE \"${dbname}\" WITH CONNECTION LIMIT -1;" \
    > /dev/null 2>&1 || true
  echo "< Done!!"
}

# Terminate all active connections to a database.
# Usage: do_terminate_connections <dbname>
do_terminate_connections() {
  local dbname="${1}"
  echo "> Terminating active connections to ${dbname}..."
  pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" -d "${DB_PGDB}" \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${dbname}' AND pid <> pg_backend_pid();" \
    > /dev/null 2>&1 || true
  echo "< Done!!"
}

# Drop a database.
# Usage: do_drop_db <dbname>
do_drop_db() {
  local dbname="${1}"
  do_block_all_connections "${dbname}"
  do_terminate_connections "${dbname}"
  echo "> Dropping database ${dbname}..."
  pg_admin dropdb -h "${DB_HOST}" -U "${DB_PGUSER}" --if-exists -- "${dbname}" || {
    echo "Failed to drop database." >&2
    exit 1
  }
  echo "< Done!!"
}

# Ask the user to type the database name as a safety confirmation.
# Usage: confirm_destructive <dbname> <action_description>
confirm_destructive() {
  local dbname="${1}"
  local description="${2}"
  if [[ "${FORCE}" == true ]]; then
    return
  fi
  echo "WARNING: ${description}"
  echo "This action CANNOT be undone."
  read -p "Type the database name to confirm: " confirm_name
  if [[ "${confirm_name}" != "${dbname}" ]]; then
    echo "Confirmation failed. Database name does not match. Aborting." >&2
    exit 1
  fi
}

# Run a query as the DB owner (uses DB_OWNER credentials).
# Usage: pg_owner <psql args...>
pg_owner() {
  PGPASSWORD="${DB_OWNER_PASSWORD}" psql -U "${DB_OWNER}" -h "${DB_HOST}" -d "${DB_PGDB}" "$@"
}

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------

FORCE="${DB_FORCE,,}"
while [[ $# -gt 0 ]]; do
  case "${1}" in
    -f|--force)
      FORCE=true
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -lt 1 ]]; then
  usage
fi

command="${1}"
shift

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

case "${command}" in
  create)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} create <dbname>" >&2
      exit 2
    fi
    require_pguser_password
    do_create_db "${1}"
    ;;

  init)
    if [[ $# -lt 1 || $# -gt 2 ]]; then
      echo "Usage: ${script_name} init <dbname> [demo]" >&2
      exit 2
    fi
    if [[ $# -eq 2 && "${2}" != "demo" ]]; then
      echo "ERROR: Invalid argument '${2}'. Expected 'demo' or nothing." >&2
      echo "Usage: ${script_name} init <dbname> [demo]" >&2
      exit 2
    fi
    database_name="${1}"
    demo_args=()
    if [[ $# -lt 2 || "${2}" != "demo" ]]; then
      demo_args=("--without-demo=all")
    fi
    echo "> Initializing Odoo in database ${database_name}..."
    odoo_exec server \
      --database "${database_name}" \
      --init base \
      "${demo_args[@]}" \
      --no-xmlrpc \
      --stop-after-init
    ;;

  drop)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} drop <dbname>" >&2
      exit 2
    fi
    confirm_destructive "${1}" "You are about to permanently drop database '${1}'."
    require_pguser_password
    do_drop_db "${1}"
    ;;

  reset)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} reset <dbname>" >&2
      exit 2
    fi
    confirm_destructive "${1}" "You are about to drop and recreate database '${1}'. All data will be PERMANENTLY LOST."
    require_pguser_password
    do_drop_db "${1}"
    do_create_db "${1}"
    ;;

  list)
    if ! pg_owner -c "SELECT datname AS \"Database\" FROM pg_database WHERE pg_catalog.pg_get_userbyid(datdba) = current_user ORDER BY datname;"; then
      echo "" >&2
      echo "Failed to list databases." >&2
      echo "ERROR: Connection failed. User '${DB_OWNER}' probably does not exist." >&2
      echo "Try running: ${script_name} createuser" >&2
      exit 1
    fi
    ;;

  users)
    if ! pg_owner -c "\du"; then
      echo "" >&2
      echo "Failed to list users." >&2
      echo "ERROR: Connection failed. User '${DB_OWNER}' probably does not exist." >&2
      echo "Try running: ${script_name} createuser" >&2
      exit 1
    fi
    ;;

  createuser)
    if [[ $# -ne 0 ]]; then
      echo "Usage: ${script_name} createuser" >&2
      exit 2
    fi
    require_pguser_password
    echo "> Creating user ${DB_OWNER}..."
    pg_admin psql -h "${DB_HOST}" -U "${DB_PGUSER}" \
      -c "CREATE USER :\"owner_name\" WITH PASSWORD :'owner_pwd'" \
      -v "owner_name=${DB_OWNER}" \
      -v "owner_pwd=${DB_OWNER_PASSWORD}"
    echo "< Done!!"
    ;;

  dropuser)
    if [[ $# -ne 0 ]]; then
      echo "Usage: ${script_name} dropuser" >&2
      exit 2
    fi
    require_pguser_password
    echo "> Dropping user ${DB_OWNER}..."
    pg_admin dropuser -h "${DB_HOST}" -U "${DB_PGUSER}" --if-exists -- "${DB_OWNER}"
    echo "< Done!!"
    ;;

  *)
    echo "Unknown command: ${command}" >&2
    usage
    ;;
esac
