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
[[ -n "${DB_OWNER}" ]]         || { echo "ERROR: PostgreSQL database owner not configured. Set db_user in ${ODOO_CONF}" >&2; exit 1; }
[[ -n "${DB_OWNER_PASSWORD}" ]] || { echo "ERROR: PostgreSQL database owner password not configured. Set db_password in ${ODOO_CONF}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: ${script_name} [-f|--force] [-j|--jobs N] <command> [args...]"
  echo ""
  echo "Commands:"
  echo "  create [-n \"note\"] [--no-filestore] <dbname> <snapshot-name>"
  echo "                             Create a snapshot of database and filestore"
  echo "  restore <snapshot-name> [dbname]"
  echo "                             Restore a named snapshot (default: original database)"
  echo "  list                       List available snapshots"
  echo "  remove <snapshot-name>     Delete a snapshot"
  echo ""
  echo "Options:"
  echo "  -f, --force       Skip all confirmation prompts (sets CONFIRM_LEVEL=none)"
  echo "  -j, --jobs N      Parallel workers for pg_dump/pg_restore (default: ${SNAPSHOT_JOBS})"
  echo ""
  echo "Configuration:"
  echo "  SNAPSHOT_DIR      Snapshot storage directory (default: /opt/odoo/snapshots)"
  echo "  SNAPSHOT_JOBS     Default parallel workers (default: 2)"
  exit 2
}

# Warn the user about a destructive action and ask for y/N confirmation.
# Shown only when confirm_level=all. Skipped at "deletions" or "none".
# Usage: confirm_destructive <description> <confirm_level>
confirm_destructive() {
  local description="${1}"
  local level="${2}"
  if [[ "${level}" != "all" ]]; then
    return
  fi
  echo "WARNING: ${description}"
  echo "This action CANNOT be undone."
  read -p "Continue? [y/N] " answer
  if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
}

# Validate that the snapshot directory is accessible.
require_snapshot_dir() {
  if [[ ! -d "${SNAPSHOT_DIR}" ]]; then
    echo "ERROR: Snapshot directory '${SNAPSHOT_DIR}' does not exist or is not accessible." >&2
    exit 1
  fi
}

# Validate that a snapshot exists.
# Usage: require_snapshot <snapshot-name>
require_snapshot() {
  local name="${1}"
  if [[ ! -d "${SNAPSHOT_DIR}/${name}" ]]; then
    echo "ERROR: Snapshot '${name}' not found in ${SNAPSHOT_DIR}." >&2
    exit 1
  fi
}

# Read a field from a snapshot's metadata.json.
# Usage: metadata_get <snapshot-name> <field>
metadata_get() {
  local name="${1}"
  local field="${2}"
  "${PYTHON_BIN}" -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
v = data.get(sys.argv[2], '')
if v:
    print(v)
" "${SNAPSHOT_DIR}/${name}/metadata.json" "${field}"
}

# Write metadata.json for a snapshot.
# Usage: write_metadata <snapshot-dir> <source_db> <note> <has_filestore>
write_metadata() {
  local snap_dir="${1}"
  local source_db="${2}"
  local note="${3}"
  local has_filestore="${4}"

  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local pg_version
  pg_version=$(PGPASSWORD="${DB_OWNER_PASSWORD}" psql -h "${DB_HOST}" -U "${DB_OWNER}" \
    -t -A -c "SHOW server_version;" 2>/dev/null || echo "unknown")

  local size_db
  size_db=$(du -sh "${snap_dir}/db/" | cut -f1)

  local size_filestore=""
  if [[ "${has_filestore}" == true ]]; then
    size_filestore=$(du -sh "${snap_dir}/filestore/" | cut -f1)
  fi

  local size_total
  size_total=$(du -sh "${snap_dir}" | cut -f1)

  "${PYTHON_BIN}" -c "
import collections, json, sys
data = collections.OrderedDict()
data['source_db'] = sys.argv[1]
data['timestamp'] = sys.argv[2]
data['odoo_version'] = '10.0'
data['pg_version'] = sys.argv[3]
if sys.argv[4]:
    data['note'] = sys.argv[4]
data['size_db'] = sys.argv[5]
if sys.argv[6]:
    data['size_filestore'] = sys.argv[6]
data['size_total'] = sys.argv[7]
with open(sys.argv[8], 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
" "${source_db}" "${timestamp}" "${pg_version}" "${note}" "${size_db}" "${size_filestore}" "${size_total}" "${snap_dir}/metadata.json"
}

# ---------------------------------------------------------------------------
# Parse global flags
# ---------------------------------------------------------------------------

CONFIRM_LEVEL="${CONFIRM_LEVEL,,}"
JOBS="${SNAPSHOT_JOBS}"

while [[ $# -gt 0 ]]; do
  case "${1}" in
    -f|--force)
      CONFIRM_LEVEL=none
      shift
      ;;
    -j|--jobs)
      JOBS="${2}"
      shift 2
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
    # Parse command-specific flags
    note=""
    no_filestore=false
    while [[ $# -gt 0 ]]; do
      case "${1}" in
        -n|--note)
          note="${2}"
          shift 2
          ;;
        --no-filestore)
          no_filestore=true
          shift
          ;;
        *)
          break
          ;;
      esac
    done

    if [[ $# -ne 2 ]]; then
      echo "Usage: ${script_name} create [-n \"note\"] [--no-filestore] <dbname> <snapshot-name>" >&2
      exit 2
    fi

    dbname="${1}"
    snap_name="${2}"
    snap_dir="${SNAPSHOT_DIR}/${snap_name}"

    require_snapshot_dir

    if [[ -d "${snap_dir}" ]]; then
      echo "ERROR: Snapshot '${snap_name}' already exists. Remove it first or choose a different name." >&2
      exit 1
    fi

    # Clean up partially created snapshot on failure
    cleanup() {
      echo ""
      echo "WARNING: Snapshot creation failed. Leftover files found at: ${snap_dir}"
      safe_remove_dir "${snap_dir}" "${CONFIRM_LEVEL}"
    }
    trap cleanup ERR

    mkdir -p "${snap_dir}/db"

    echo "> Dumping database ${dbname}..."
    PGPASSWORD="${DB_OWNER_PASSWORD}" pg_dump -Fd -j "${JOBS}" --no-owner --no-acl \
      -h "${DB_HOST}" -U "${DB_OWNER}" -d "${dbname}" \
      -f "${snap_dir}/db/"
    echo "< Done!!"

    has_filestore=false
    filestore_src="${ODOO_DATA_DIR}/filestore/${dbname}"
    if [[ "${no_filestore}" == false ]]; then
      if [[ -d "${filestore_src}" ]]; then
        mkdir -p "${snap_dir}/filestore"
        echo "> Copying filestore..."
        rsync -a "${filestore_src}/" "${snap_dir}/filestore/"
        echo "< Done!!"
        has_filestore=true
      else
        echo "WARNING: No filestore found for '${dbname}'. Backing up database only." >&2
      fi
    fi

    echo "> Writing metadata..."
    write_metadata "${snap_dir}" "${dbname}" "${note}" "${has_filestore}"
    echo "< Done!!"

    trap - ERR
    echo "Snapshot '${snap_name}' created successfully."
    ;;

  restore)
    if [[ $# -lt 1 || $# -gt 2 ]]; then
      echo "Usage: ${script_name} restore [-f] <snapshot-name> [dbname]" >&2
      exit 2
    fi

    snap_name="${1}"
    snap_dir="${SNAPSHOT_DIR}/${snap_name}"

    require_snapshot_dir
    require_snapshot "${snap_name}"

    # Resolve target database name
    if [[ $# -ge 2 ]]; then
      dbname="${2}"
    else
      dbname=$(metadata_get "${snap_name}" "source_db")
      if [[ -z "${dbname}" ]]; then
        echo "ERROR: Could not determine target database name from snapshot metadata." >&2
        exit 1
      fi
    fi

    confirm_destructive \
      "You are about to drop and recreate database '${dbname}' from snapshot '${snap_name}'." \
      "${CONFIRM_LEVEL}"

    # Warn if snapshot has no filestore but target database does
    has_snap_filestore=false
    if [[ -d "${snap_dir}/filestore" ]]; then
      has_snap_filestore=true
    fi

    filestore_target="${ODOO_DATA_DIR}/filestore/${dbname}"
    if [[ "${has_snap_filestore}" == false && -d "${filestore_target}" ]]; then
      if [[ "${CONFIRM_LEVEL}" == "all" ]]; then
        echo "WARNING: Snapshot '${snap_name}' has no filestore, but '${dbname}' has an existing filestore."
        echo "The existing filestore will NOT be modified."
        read -p "Continue? [y/N] " answer
        if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
          echo "Aborted." >&2
          exit 1
        fi
      fi
    fi

    echo "> Dropping database ${dbname}..."
    db -f drop "${dbname}"

    echo "> Creating database ${dbname}..."
    db create "${dbname}"

    echo "> Restoring database dump..."
    rc=0
    PGPASSWORD="${DB_OWNER_PASSWORD}" pg_restore -Fd -j "${JOBS}" --no-owner --no-acl \
      -h "${DB_HOST}" -U "${DB_OWNER}" -d "${dbname}" \
      "${snap_dir}/db/" || rc=$?
    if [[ $rc -gt 1 ]]; then
      echo "ERROR: pg_restore failed." >&2
      exit 1
    fi
    if [[ $rc -eq 1 ]]; then
      echo "WARNING: pg_restore completed with warnings." >&2
    fi
    echo "< Done!!"

    if [[ "${has_snap_filestore}" == true ]]; then
      echo "> Restoring filestore..."
      mkdir -p "${filestore_target}"
      rsync -a --delete "${snap_dir}/filestore/" "${filestore_target}/"
      echo "< Done!!"
    fi

    echo "Snapshot '${snap_name}' restored to database '${dbname}'."
    ;;

  list)
    if [[ $# -ne 0 ]]; then
      echo "Usage: ${script_name} list" >&2
      exit 2
    fi

    require_snapshot_dir

    "${PYTHON_BIN}" - "${SNAPSHOT_DIR}" <<'PYEOF'
import json, os, sys

snap_dir = sys.argv[1]
entries = []

for name in os.listdir(snap_dir):
    meta_path = os.path.join(snap_dir, name, 'metadata.json')
    if not os.path.isfile(meta_path):
        continue
    try:
        with open(meta_path) as f:
            meta = json.load(f)
        entries.append((name, meta))
    except (ValueError, IOError):
        continue

if not entries:
    print("No snapshots found.")
    sys.exit(0)

# Sort by timestamp, newest first
entries.sort(key=lambda x: x[1].get('timestamp', ''), reverse=True)

fmt = "{:<21s}{:<14s}{:<22s}{:<8s}{:<11s}{}"
print(fmt.format("NAME", "SOURCE DB", "DATE", "DB", "FILESTORE", "TOTAL"))
for name, meta in entries:
    ts = meta.get('timestamp', '').replace('T', ' ').replace('Z', '')
    print(fmt.format(
        name[:20],
        meta.get('source_db', '')[:13],
        ts[:21],
        meta.get('size_db', '-'),
        meta.get('size_filestore', '-'),
        meta.get('size_total', '-'),
    ))
    note = meta.get('note', '')
    if note:
        print("  Note: {}".format(note))
PYEOF
    ;;

  remove)
    if [[ $# -ne 1 ]]; then
      echo "Usage: ${script_name} remove [-f] <snapshot-name>" >&2
      exit 2
    fi

    snap_name="${1}"

    require_snapshot_dir
    require_snapshot "${snap_name}"

    confirm_destructive \
      "You are about to permanently delete snapshot '${snap_name}'." \
      "${CONFIRM_LEVEL}"

    echo "> Removing snapshot ${snap_name}..."
    safe_remove_dir "${SNAPSHOT_DIR}/${snap_name}" "${CONFIRM_LEVEL}"
    echo "< Done!!"
    ;;

  *)
    echo "Unknown command: ${command}" >&2
    usage
    ;;
esac
