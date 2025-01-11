#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 2 )); then
  echo "USAGE $0 <number of dask client slots> <number of dask workers>     (e.g. 4 400)"
  exit 1
fi

#  4 client slots with  400 workers took 13 minutes for jrc_celegans_20241007 with 6K single tile layers
# 10 client slots with 1300 workers took 40 minutes for jrc_mus-pancreas-5 with 30K layers and 240K tiles
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

ZARR_PATH="${RENDER_NRS_ROOT}/${VOLUME_NAME}.zarr"            # /nrs/cellmap/data/jrc_mus-pancreas-5/jrc_mus-pancreas-5.zarr
FINAL_ZARR_PATH="${ZARR_PATH}/recon-1/em/fibsem-${DATA_TYPE}" # /nrs/cellmap/data/jrc_mus-pancreas-5/jrc_mus-pancreas-5.zarr/recon-1/em/fibsem-uint8
FINAL_ZARR_PATH_WITHOUT_NRS_ROOT="${FINAL_ZARR_PATH#/nrs/}"   # cellmap/data/jrc_mus-pancreas-5/jrc_mus-pancreas-5.zarr/recon-1/em/fibsem-uint8

if [ -d "${FINAL_ZARR_PATH}" ]; then
  echo "ERROR: ${FINAL_ZARR_PATH} already exists!"
  exit 1
fi

mkdir -p "${ZARR_PATH}"

WORK_DIR="${SCRIPT_DIR}/logs/zarr-$(date +"%Y%m%d_%H%M%S")"
BSUB_LOG_FILE="${WORK_DIR}/bsub.log"
LAUNCH_LOG_FILE="${WORK_DIR}/launch.log"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

CONVERT_JOB_NAME="convert_to_zarr_${RENDER_PROJECT}_$(date +"%Y%m%d_%H%M%S")"

ARGS="--num_workers=${NUM_DASK_WORKERS} --cluster=lsf"
ARGS="${ARGS} --src=${RENDERED_N5_PATH}/"
ARGS="${ARGS} --dest=${ZARR_PATH}/"
ARGS="${ARGS} --lsf_runtime_limit=240:00"                     # 10 days - [hours:]minutes
ARGS="${ARGS} --lsf_project_name=${BILL_TO}"
ARGS="${ARGS} --lsf_worker_log_dir=${WORK_DIR}"

NG_LAYER_SOURCE="zarr://http://renderer.int.janelia.org:8080/n5_sources/${FINAL_ZARR_PATH_WITHOUT_NRS_ROOT}"
NG_LAYER_NAME="${VOLUME_NAME} ${DATA_TYPE}"
NG_LAYERS='"layers":[{"type":"image","source":"'"${NG_LAYER_SOURCE}"'","tab":"source","name":"'"${NG_LAYER_NAME}"'"}]'
NG_SELECTED_LAYER='"selectedLayer":{"visible":true,"layer":"'"${NG_LAYER_NAME}"'"}'
NG_DATA='{'"${NG_LAYERS}"','"${NG_SELECTED_LAYER}"',"layout":"4panel"}'

# jq options:
#   --raw-output outputs the raw contents of strings instead of JSON string literals
#   --raw-input  treats input lines as strings instead of parsing them as JSON
#   --slurp      reads the input into a single string (omit if you don't want to replace linefeeds with %0A)
#   @uri         applies percent-encoding, by mapping all reserved URI characters to a %XX sequence
URL_ENCODED_NG_DATA=$(echo "${NG_DATA}" | ${JQ} --raw-output --raw-input --slurp @uri)
NG_LINK="http://renderer.int.janelia.org:8080/ng/#!${URL_ENCODED_NG_DATA}"

echo "
submitting conversion job:

  job name:  ${CONVERT_JOB_NAME}
  source:    ${RENDERED_N5_PATH}
  target:    ${FINAL_ZARR_PATH}
  log:       ${BSUB_LOG_FILE}

  script arguments:
    ${ARGS}

  neuroglancer link (will work after job completes):
    http://renderer.int.janelia.org:8080/ng/#!${URL_ENCODED_NG_DATA}
" | tee "${LAUNCH_LOG_FILE}"


# submit job that converts n5 to zarr
# shellcheck disable=SC2086
bsub -P "${BILL_TO}" -n ${NUM_DASK_CLIENT_SLOTS} -J "${CONVERT_JOB_NAME}" -o "${BSUB_LOG_FILE}" -e "${BSUB_LOG_FILE}" "${SCRIPT_DIR}"/support/62_convert_n5_to_cellmap_zarr.sh ${ARGS}

# submit job that emails tail of launch log file when convert job completes
bsub -P "${BILL_TO}" -n 1 -W 59 -J "tail_${CONVERT_JOB_NAME}" -w "ended(${CONVERT_JOB_NAME})" tail -50 "${BSUB_LOG_FILE}"