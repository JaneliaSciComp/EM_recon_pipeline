#!/bin/bash

set -e

EMRP_ROOT="/groups/flyem/data/render/git/EM_recon_pipeline"
VERSIONED_TRANSFER_INFO_DIR="${EMRP_ROOT}/src/resources/transfer_info"
TRANSFER_CONFIG_DIR="/groups/flyem/home/flyem/bin/dat_transfer/2022/config"

if (( $# != 1 )); then
  echo "USAGE $0 <relative transfer info path> (e.g. fibsem/volume_transfer_info.Z0422-17_VNC_1b.json)"
  exit 1
fi

VERSIONED_TRANSFER_INFO_FILE="${VERSIONED_TRANSFER_INFO_DIR}/${1}"

if [ ! -f "${VERSIONED_TRANSFER_INFO_FILE}" ]; then
  echo "ERROR: ${VERSIONED_TRANSFER_INFO_FILE} not found"
  exit 1
fi

# ----------------------------------------------
JQ="/groups/flyem/data/render/bin/jq"
function setupTransferPath() {
  local JSON_FILTER="$1"
  local TRANSFER_PATH
  TRANSFER_PATH=$(${JQ} "${JSON_FILTER}" "${VERSIONED_TRANSFER_INFO_FILE}" | sed 's/"//g')
  TRANSFER_PATH_PARENT=$(dirname "${TRANSFER_PATH}")
  mkdir -p "${TRANSFER_PATH}"
  chmod 2775 "${TRANSFER_PATH_PARENT}" "${TRANSFER_PATH}"
  ls -ald "${TRANSFER_PATH_PARENT}" "${TRANSFER_PATH}"
  echo
}

echo """
Reading ${VERSIONED_TRANSFER_INFO_FILE} to set up transfer paths ...
"""
setupTransferPath ".cluster_root_paths.raw_dat"
setupTransferPath ".cluster_root_paths.raw_h5"
setupTransferPath ".cluster_root_paths.align_h5"
setupTransferPath ".archive_root_paths.raw_h5"

TRANSFER_INFO_FILENAME=$(basename "${VERSIONED_TRANSFER_INFO_FILE}")

read -p "Do transfer paths look correct - is it ok to copy transfer file and start transfers (y | n)? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

cp "${VERSIONED_TRANSFER_INFO_FILE}" "${TRANSFER_CONFIG_DIR}"
chmod 664 "${TRANSFER_CONFIG_DIR}/${TRANSFER_INFO_FILENAME}"
echo """
ls -al ${TRANSFER_CONFIG_DIR}:
"""
ls -al "${TRANSFER_CONFIG_DIR}"