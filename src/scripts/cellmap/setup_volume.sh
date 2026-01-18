#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

# only list recently modified transfer files (default is 30 days)
MODIFICATION_DAYS="${1:-30}"

BASE_SCRIPTS_DIR="${SCRIPT_DIR}/base_scripts"

FIBSEMXFER_DIR="/groups/fibsem/home/fibsemxfer"
EMRP_ROOT="${FIBSEMXFER_DIR}/git/EM_recon_pipeline"
TRANSFER_INFO_DIR="${EMRP_ROOT}/src/resources/transfer_info"

RUN_DIR=$(readlink -m ".")
cd "${TRANSFER_INFO_DIR}"

unset TRANSFER_INFO_JSON_FILE
mapfile -t TI_FILES < <(find . -type f -name "volume_transfer_info.*.json" -mtime "-${MODIFICATION_DAYS}" | cut -c3-)

if [ ${#TI_FILES[@]} -eq 0 ]; then
    echo "No volume_transfer_info files have been modified in the past ${MODIFICATION_DAYS} days"
    exit 1
fi

echo "
The following volume_transfer_info files have been modified in the past ${MODIFICATION_DAYS} days:
"
PS3="
Choose number of volume_transfer_info file for new data set: "
select TI_FILE in "${TI_FILES[@]}"; do
  break
done

TRANSFER_INFO_JSON_FILE="${TRANSFER_INFO_DIR}/${TI_FILE}"
TI_BASENAME=$(basename "${TI_FILE}")

cd "${RUN_DIR}"

if [[ ! -f "${TRANSFER_INFO_JSON_FILE}" ]]; then
  echo "ERROR: ${TRANSFER_INFO_JSON_FILE} not found!"
  exit 1
fi

VOLUME_NAME="${TI_BASENAME#volume_transfer_info.}"
VOLUME_NAME="${VOLUME_NAME%.json}"

JQ="${FIBSEMXFER_DIR}/bin/jq"

LAB_OR_PROJECT_GROUP=$(${JQ} '.render_data_set.owner' "${TRANSFER_INFO_JSON_FILE}" | sed 's/"//g')

ROW_COUNT=$(${JQ} '.scope_data_set.rows_per_z_layer' "${TRANSFER_INFO_JSON_FILE}")
COLUMN_COUNT=$(${JQ} '.scope_data_set.columns_per_z_layer' "${TRANSFER_INFO_JSON_FILE}")
NULL_VALUE="null"

if [[ "${ROW_COUNT}" -eq "${NULL_VALUE}" || "${ROW_COUNT}" -eq "0" || "${ROW_COUNT}" -eq "1" ]]; then
  if [[ "${COLUMN_COUNT}" -eq "1" ]]; then
    LAYOUT="single_tile"
  else
    LAYOUT="single_row"
  fi
 else
  LAYOUT="multi_row"
fi

# /groups/cellmap/cellmap
BASE_GROUPS_DIR="/groups/${LAB_OR_PROJECT_GROUP}/${LAB_OR_PROJECT_GROUP}"
if [[ ! -d "${BASE_GROUPS_DIR}" ]]; then
  # /groups/reiser/reiserlab
  PREV_BASE_GROUPS_DIR="${BASE_GROUPS_DIR}"
  BASE_GROUPS_DIR="/groups/${LAB_OR_PROJECT_GROUP}/${LAB_OR_PROJECT_GROUP}lab"
  if [[ ! -d "${BASE_GROUPS_DIR}" ]]; then
    echo "ERROR: can't find ${PREV_BASE_GROUPS_DIR} or ${BASE_GROUPS_DIR}"
    exit 1
  fi
fi

ALIGN_DIR="${BASE_GROUPS_DIR}/render/align/${VOLUME_NAME}"
if [[ -d "${ALIGN_DIR}" ]]; then
  echo "ERROR: ${ALIGN_DIR} already exists!"
  exit 1
fi

echo "
After parsing
  ${TRANSFER_INFO_JSON_FILE}

alignment scripts will be setup with
  owner:       ${LAB_OR_PROJECT_GROUP}
  volume name: ${VOLUME_NAME}
  layout:      ${LAYOUT}

in directory:
    ${ALIGN_DIR}
"

mkdir -p "${ALIGN_DIR}"
chmod 2775 "${ALIGN_DIR}"

cp "${BASE_SCRIPTS_DIR}"/*.* "${ALIGN_DIR}"
cp -r "${BASE_SCRIPTS_DIR}"/match_*_row "${ALIGN_DIR}"
cp -r "${BASE_SCRIPTS_DIR}"/support "${ALIGN_DIR}"
cp "${TRANSFER_INFO_JSON_FILE}" "${ALIGN_DIR}"

chmod 775 "${ALIGN_DIR}"/*.sh
chmod 775 "${ALIGN_DIR}"/support "${ALIGN_DIR}"/support/*.sh "${ALIGN_DIR}"/support/*.py
chmod 664 "${ALIGN_DIR}"/*/*.json

sed -i "
  s/export LAB_OR_PROJECT_GROUP.*/export LAB_OR_PROJECT_GROUP=\"${LAB_OR_PROJECT_GROUP}\"/
  s/export LAYOUT.*/export LAYOUT=\"${LAYOUT}\"/
" "${ALIGN_DIR}"/00_config.sh

ls "${ALIGN_DIR}"
