#!/bin/bash
set -euo pipefail

# get common vars and functions
source "${HOME}/scripts/lib/common.sh"

# specific entrypoint functions
STATE_DIR=${ODOO_DATA_DIR}/.bootstrap
CID_FILE=${STATE_DIR}/container_id
CID="$(hostname)"

#### FUNCTIONS

install_reportlab_pfbfer_fonts() {
  echo "Installing ReportLab Type1 fonts (pfbfer.zip)…"

  RLFONTS="$(${PYTHON_BIN} - <<'EOF'
import os, reportlab
print(os.path.join(os.path.dirname(reportlab.__file__), "fonts"))
EOF
)" || { echo "ERROR: reportlab not importable" >&2; exit 1; }

  [ -d "${RLFONTS}" ] || { echo "ERROR: ReportLab fonts dir not found: ${RLFONTS}" >&2; exit 1; }

  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "${TMPDIR}"' RETURN

  ZIP="${TMPDIR}/pfbfer.zip"

  # Try download first
  if curl -fsSL -o "${ZIP}" https://www.reportlab.com/ftp/fonts/pfbfer.zip; then
    echo "Downloaded pfbfer.zip from Internet"
  else
    echo "WARNING: download failed; using bundled pfbfer.zip" >&2
    cp "${DIST_ASSETS_DIR}/pfbfer.zip" "${ZIP}"
  fi

  [ -s "${ZIP}" ] || { echo "ERROR: pfbfer.zip not available (download failed and local missing)" >&2; exit 1; }

  unzip -q "${ZIP}" -d "${TMPDIR}/unpacked"
  find "${TMPDIR}/unpacked" -type f \( -name "*.pfb" -o -name "*.afm" \) -exec cp -f {} "${RLFONTS}/" \;

  echo "ReportLab Type1 fonts installed OK"
}

testing_loop() {
  echo "Looping infinitely for testing purposes..."
  while :; do
    sleep 3600
  done
}

##### MAIN
#testing_loop
if [ ! -f "${CID_FILE}" ] || [ "${CID}" != "$(cat "${CID_FILE}")" ]; then
    echo "New container: bootstrapping..."
    mkdir -p "${STATE_DIR}"
    "${DIST_BIN_DIR}/fetchbasereqs"
    "${DIST_BIN_DIR}/fetchcode"
    "${DIST_BIN_DIR}/fetchreqs" odoo
    install_reportlab_pfbfer_fonts
    echo "${CID}" > "${CID_FILE}"
else
    echo "Running Odoo..."
fi
odoo_exec server "$@"
