#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
BASE_SCRIPTS_DIR="${SCRIPT_DIR}/base_scripts"

if (( $# < 2 )); then
  echo "
USAGE: $0 <volume name> <single_row | multi_row> [lab | project_group]

For Example:
       $0 jrc_mus-lung-covid single_row
       $0 Z0422_17_VNC_1 multi_row fibsem
"
  exit 1
fi

VOLUME_NAME="$1"
LAYOUT="$2"
LAB_OR_PROJECT_GROUP="${3:-cellmap}"

ALIGN_DIR="/groups/${LAB_OR_PROJECT_GROUP}/${LAB_OR_PROJECT_GROUP}/render/align/${VOLUME_NAME}"
if [[ -d "${ALIGN_DIR}" ]]; then
  echo "ERROR: ${ALIGN_DIR} already exists!"
fi
mkdir -p "${ALIGN_DIR}"
chmod 2775 "${ALIGN_DIR}"

cp "${BASE_SCRIPTS_DIR}"/* "${ALIGN_DIR}"
cp -r "${BASE_SCRIPTS_DIR}"/match_*_row "${ALIGN_DIR}"

sed -i "
  s/export LAB_OR_PROJECT_GROUP.*/export LAB_OR_PROJECT_GROUP=\"${LAB_OR_PROJECT_GROUP}\"/
  s/export LAYOUT.*/export LAYOUT=\"${LAYOUT}\"/
" "${ALIGN_DIR}"/00_config.sh

echo "created ${ALIGN_DIR}"
