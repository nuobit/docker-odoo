#!/bin/bash
set -euo pipefail

source "${HOME}/.local/lib/common.sh"

script_name="${0##*/}"

# Extract PostgreSQL connection info from Odoo config
PGHOST=$(grep -E "^ *db_host *=" "${ODOO_CONF}" | tail -n 1 | sed -En 's/^ *db_host *= *(.+)$/\1/p' || :)
PGUSER=${PGUSER:-postgres}
PGDB=${PGDB:-postgres}
DB_OWNER=$(grep -E "^ *db_user *=" "${ODOO_CONF}" | tail -n 1 | sed -En 's/^ *db_user *= *(.+)$/\1/p' || :)
DB_OWNER_PASSWORD=$(grep -E "^ *db_password *=" "${ODOO_CONF}" | tail -n 1 | sed -En 's/^ *db_password *= *(.+)$/\1/p' || :)
# Validate required parameters
if [[ -z "${PGHOST}" ]]; then
  echo "ERROR: PostgreSQL host not configured. Set db_host in ${ODOO_CONF}" >&2
  exit 1
fi
if [[ -z "${PGUSER}" ]]; then
  echo "ERROR: PostgreSQL user not configured. Set PGUSER environment variable" >&2
  exit 1
fi
if [[ -z "${PGDB}" ]]; then
  echo "ERROR: PostgreSQL database not configured. Set PGDB environment variable" >&2
  exit 1
fi
if [[ -z "${DB_OWNER}" ]]; then
  echo "ERROR: PostgreSQL database owner not configured. Set db_user in ${ODOO_CONF}" >&2
  exit 1
fi
if [[ -z "${DB_OWNER_PASSWORD}" ]]; then
  echo "ERROR: PostgreSQL database owner password not configured. Set db_password in ${ODOO_CONF}" >&2
  exit 1
fi

usage() {
  echo "Usage: ${script_name} <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  create <dbname>                Create a database"
  echo "  drop <dbname>                  Drop a database"
  echo "  reset <dbname>                 Drop and recreate a database"
  echo "  listdb                         List databases"
  echo "  listusers                      List PostgreSQL users"
  echo "  createuser                     Create DB owner user (password from db_password)"
  echo "  dropuser                       Drop DB owner user"
  echo ""
  echo "Configuration (from ${ODOO_CONF}):"
  echo "  db_host     PostgreSQL host"
  echo "  db_user     PostgreSQL database owner"
  echo "  db_password PostgreSQL database owner password"
  echo ""
  echo "Optional environment variables:"
  echo "  PGUSER            PostgreSQL admin user (default: postgres)"
  echo "  PGPASSWORD        PostgreSQL admin password (if set, avoids prompt)"
  exit 1
}

if [[ $# -lt 1 ]]; then
  usage
fi

command="${1}"
shift

case "${command}" in
  create)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} create <dbname>" >&2
      exit 2
    fi
    database_name="${1}"
    
    # Prompt for password once if not set
    if [[ -z "${PGPASSWORD:-}" ]]; then
      read -sp "Password for user ${PGUSER}: " pg_password
      echo ""
    else
      pg_password="${PGPASSWORD}"
    fi
    
    echo "> Creating database ${database_name}..."
    PGPASSWORD="${pg_password}" createdb -h "${PGHOST}" -U "${PGUSER}" -O "${DB_OWNER}" "${database_name}" || {
      echo "Failed to create database." >&2
      exit 1
    }
    echo "< Done!!"
    
    echo "> Creating extension unaccent..."
    PGPASSWORD="${pg_password}" psql -U "${PGUSER}" -h "${PGHOST}" -d "${database_name}" -c "CREATE EXTENSION IF NOT EXISTS unaccent;" || {
      echo "Failed to create unaccent extension." >&2
      exit 1
    }
    echo "< Done!!"
    ;;

  drop)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} drop <dbname>" >&2
      exit 2
    fi
    database_name="${1}"
    
    echo "> Dropping database ${database_name}..."
    PGPASSWORD="${DB_OWNER_PASSWORD}" dropdb -h "${PGHOST}" -U "${DB_OWNER}" --if-exists "${database_name}" || {
      echo "Failed to drop database." >&2
      exit 1
    }
    echo "< Done!!"
    ;;

  reset)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} reset <dbname>" >&2
      exit 2
    fi

    # Prompt for password once if not set
    if [[ -z "${PGPASSWORD:-}" ]]; then
      read -sp "Password for user ${PGUSER}: " pg_password
      echo ""
    else
      pg_password="${PGPASSWORD}"
    fi

    database_name="${1}"
    echo "> Dropping database ${database_name}..."
    PGPASSWORD="${DB_OWNER_PASSWORD}" dropdb -h "${PGHOST}" -U "${DB_OWNER}" --if-exists "${database_name}" || {
      echo "Failed to drop database." >&2
      exit 1
    }
    echo "< Done!!"
    
    echo "> Creating database ${database_name}..."
    PGPASSWORD="${pg_password}" createdb -h "${PGHOST}" -U "${PGUSER}" -O "${DB_OWNER}" "${database_name}" || {
      echo "Failed to create database." >&2
      exit 1
    }
    echo "< Done!!"
    
    echo "> Creating extension unaccent..."
    PGPASSWORD="${pg_password}" psql -U "${PGUSER}" -h "${PGHOST}" -d "${database_name}" -c "CREATE EXTENSION IF NOT EXISTS unaccent;" || {
      echo "Failed to create unaccent extension." >&2
      exit 1
    }
    echo "< Done!!"
    ;;

  list)
     if ! PGPASSWORD="${DB_OWNER_PASSWORD}" psql -U "${DB_OWNER}" -h "${PGHOST}" -d ${PGDB} -c "SELECT datname as \"Database\" FROM pg_database WHERE pg_catalog.pg_get_userbyid(datdba) = '${DB_OWNER}' ORDER BY datname;" 2>&1; then
      echo "" >&2
      echo "Failed to list databases." >&2
      echo "ERROR: Connection failed. User '${DB_OWNER}' probably does not exist." >&2
      echo "Try running: dbctl createuser" >&2
      exit 1
    fi
    ;;

  users)
    if ! PGPASSWORD="${DB_OWNER_PASSWORD}" psql -U "${DB_OWNER}" -h "${PGHOST}" -d ${PGDB} -c "\du" 2>&1; then
      echo "" >&2
      echo "Failed to list users." >&2
      echo "ERROR: Connection failed. User '${DB_OWNER}' probably does not exist." >&2
      echo "Try running: dbctl createuser" >&2
      exit 1
    fi
    ;;

  createuser)
    if [[ $# -eq 0 ]]; then
      exec psql -U "${PGUSER}" -h "${PGHOST}" -c "CREATE USER \"${DB_OWNER}\" WITH PASSWORD \$\$${DB_OWNER_PASSWORD}\$\$;"
    else
      echo "Usage: ${script_name} createuser" >&2
      exit 2
    fi
    ;;

  dropuser)
    if [[ $# -eq 0 ]]; then
      exec dropuser -h "${PGHOST}" -U "${PGUSER}" --if-exists "${DB_OWNER}"
    else
      echo "Usage: ${script_name} dropuser" >&2
      exit 2
    fi
    ;;

  *)
    echo "Unknown command: ${command}" >&2
    usage
    ;;
esac
