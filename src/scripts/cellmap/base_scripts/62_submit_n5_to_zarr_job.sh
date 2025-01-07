#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 2 )); then
  echo "USAGE $0 <number of dask client slots> <number of dask workers>     (e.g. 10 400)"
  exit 1
fi

NUM_DASK_CLIENT_SLOTS="${1}"
NUM_DASK_WORKERS="${2}"

CONVERT_SCRIPT="${SCRIPT_DIR}/support/62_convert_n5_to_cellmap_zarr.sh"
if [[ ! -f ${CONVERT_SCRIPT} ]]; then
  echo "ERROR: ${CONVERT_SCRIPT} not found"
  exit 1
fi

# ----------------------------------------------
# N5 paths
unset RENDERED_N5_PATH
shopt -s nullglob
DIRS=("${N5_PATH}"/*/"${RENDER_PROJECT}"/*/ "${N5_PATH}"/em/*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "WARNING: no ${RENDER_PROJECT} project n5 directories found in ${N5_PATH}"
elif (( DIR_COUNT == 1 )); then
  RENDERED_N5_PATH=${DIRS[0]}
else
  PS3="Choose N5 to promote as final alignment and convert to zarr: "
  select RENDERED_N5_PATH in "${DIRS[@]}"; do
    break
  done
fi

# trim trailing slash
RENDERED_N5_PATH="${RENDERED_N5_PATH%/}"

N5_S_ZERO_JSON="${RENDERED_N5_PATH}/s0/attributes.json"
if [[ ! -f ${N5_S_ZERO_JSON} ]]; then
  echo "ERROR: ${N5_S_ZERO_JSON} not found"
  exit 1
fi

# jq '.dataType' /nrs/.../s0/attributes.json
DATA_TYPE=$(${JQ} -r '.dataType' "${N5_S_ZERO_JSON}")
if [[ "${DATA_TYPE}" == "uint8" ]]; then
  FINAL_DATA_SET="/em/fibsem-uint8"
elif [[ "${DATA_TYPE}" == "uint16" ]]; then
  FINAL_DATA_SET="/em/fibsem-uint16"
else
  echo "ERROR: unknown data type: ${DATA_TYPE}"
  exit 1
fi

# /nrs/${LAB_OR_GROUP_PROJECT}/data/${VOLUME}/${VOLUME}.zarr/em/fibsem-uint8
ZARR_PATH="${RENDER_NRS_ROOT}/${VOLUME_NAME}.zarr"
FINAL_ZARR_PATH="${ZARR_PATH}${FINAL_DATA_SET}"

if [ -d "${FINAL_ZARR_PATH}" ]; then
  echo "ERROR: ${FINAL_ZARR_PATH} already exists!"
  exit 1
fi

FINAL_ZARR_PARENT_DIR=$(dirname "${FINAL_ZARR_PATH}")
mkdir -p "${FINAL_ZARR_PARENT_DIR}"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/zarr-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

echo "
submitting job ...
  source:   ${RENDERED_N5_PATH}
  target:   ${FINAL_ZARR_PATH}
  log file: ${LOG_FILE}
"

ARGS="--num_workers=${NUM_DASK_WORKERS} --cluster=lsf"
ARGS="${ARGS} --src=${RENDERED_N5_PATH}/"
ARGS="${ARGS} --dest=${FINAL_ZARR_PATH}/"

# shellcheck disable=SC2086
bsub -P "${BILL_TO}" -n ${NUM_DASK_CLIENT_SLOTS} -o "${LOG_FILE}" "${SCRIPT_DIR}"/support/62_convert_n5_to_cellmap_zarr.sh ${ARGS}