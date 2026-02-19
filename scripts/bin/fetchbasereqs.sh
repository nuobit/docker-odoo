#!/bin/bash
set -euo pipefail

source "${HOME}/scripts/lib/common.sh"

script_name="${0##*/}"

if [[ $# -eq 0 ]]; then
  pip_install \
    wheel \
    git-aggregator \
    click_odoo_contrib \
    git+https://github.com/OCA/openupgradelib.git
else
  echo "Usage: ${script_name}" >&2
  exit 2
fi
