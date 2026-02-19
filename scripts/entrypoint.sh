#!/bin/bash
set -euo pipefail

# On error, sleep indefinitely to prevent restart loops.
# The container stays running so you can: docker exec -it <name> bash
# Once fixed, restart with: docker restart <name>
on_error() {
  echo "FATAL: entrypoint failed (exit code $?). Container will stay alive for debugging." >&2
  echo "  -> docker exec -it \$(hostname) bash" >&2
  sleep infinity
}
trap on_error ERR

# get common vars and functions
source "${HOME}/scripts/lib/common.sh"

# specific entrypoint functions
STATE_DIR="${ODOO_DATA_DIR}/.bootstrap"
CID_FILE="${STATE_DIR}/container_id"
CID="$(hostname)"

#### FUNCTIONS

install_reportlab_pfbfer_fonts() {
  echo "Installing ReportLab Type1 fonts (pfbfer.zip)…"

  local rlfonts tmpdir zip
  rlfonts="$(${PYTHON_BIN} - <<'EOF'
import os, reportlab
print(os.path.join(os.path.dirname(reportlab.__file__), "fonts"))
EOF
)" || { echo "ERROR: reportlab not importable" >&2; exit 1; }

  [[ -d "${rlfonts}" ]] || { echo "ERROR: ReportLab fonts dir not found: ${rlfonts}" >&2; exit 1; }

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "${tmpdir}"' RETURN

  zip="${tmpdir}/pfbfer.zip"

  # Try download first
  if curl -fsSL -o "${zip}" https://www.reportlab.com/ftp/fonts/pfbfer.zip; then
    echo "Downloaded pfbfer.zip from Internet"
  else
    echo "WARNING: download failed; using bundled pfbfer.zip" >&2
    cp "${ASSETS_DIR}/pfbfer.zip" "${zip}"
  fi

  [[ -s "${zip}" ]] || { echo "ERROR: pfbfer.zip not available (download failed and local missing)" >&2; exit 1; }

  unzip -q "${zip}" -d "${tmpdir}/unpacked"
  find "${tmpdir}/unpacked" -type f \( -name "*.pfb" -o -name "*.afm" \) -exec cp -f {} "${rlfonts}/" \;
}

##### MAIN
if [[ ! -f "${CID_FILE}" ]] || [[ "${CID}" != "$(cat "${CID_FILE}")" ]]; then
  echo ">> New container: bootstrapping..."
  mkdir -p "${STATE_DIR}"
  echo "> Installing base Python requirements..."
  "${BIN_DIR}/fetchbasereqs"
  echo "< Done!"
  echo "> Fetching source code..."
  "${BIN_DIR}/fetchcode"
  echo "< Done!"
  echo "> Generating addons_path and updating odoo.conf..."
  "${BIN_DIR}/genaddonspath"
  echo "< Done!"
  # Install Python requirements for repos listed in FETCH_REQS_REPOS.
  # Defaults to "odoo" only. Override in settings.env, e.g.:
  #   FETCH_REQS_REPOS=odoo,oca/connector
  echo "> Installing Python requirements..."
  _reqs="${FETCH_REQS_REPOS:-odoo}"
  _reqs="${_reqs// /}"          # strip spaces (allows "odoo, oca/connector")
  IFS=',' read -ra _reqs_repos <<< "${_reqs}"
  for repo in "${_reqs_repos[@]}"; do
    [[ -z "${repo}" ]] && continue
    echo "  - ${repo}"
    "${BIN_DIR}/fetchreqs" "${repo}"
  done
  echo "< Done!"
  echo "> Installing ReportLab Type1 fonts..."
  install_reportlab_pfbfer_fonts
  echo "< Done!"
  echo "${CID}" > "${CID_FILE}"
  echo "<< Bootstrapping complete!"
fi
echo "Running Odoo..."
odoo_exec server "$@"
