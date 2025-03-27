#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh

if (( $# < 1 )); then
  echo "USAGE $0 <render project> [any character to launch job]   (e.g. w60_serial_360_to_369 y)
"
  exit 1
fi

RENDER_PROJECT="${1}"
LAUNCH_BSUB="${2}"

WAFER_PREFIX=$(echo "${RENDER_PROJECT}" | cut -d'_' -f1)
PADDED_FIRST_SERIAL=$(echo "${RENDER_PROJECT}" | cut -d'_' -f3 | cut -c1-3)
FIRST_SERIAL=$((10#${PADDED_FIRST_SERIAL}))
LAST_SERIAL=$((FIRST_SERIAL + 9))

STACK_ARRAY=()
for (( SERIAL_NUMBER=FIRST_SERIAL; SERIAL_NUMBER<=LAST_SERIAL; SERIAL_NUMBER++ )); do
  PADDED_SERIAL=$(printf "%03d" "${SERIAL_NUMBER}")
  STACK="${WAFER_PREFIX}_s${PADDED_SERIAL}_r00_d30_gc"
  STACK_ARRAY+=( "${STACK}" )
done

ROOT_PREVIEW_DIR="${BASE_DATA_DIR}/preview"

MIN_X=60000
MAX_X=90000
MIN_Y=120000
MAX_Y=140000
SCALE="0.02"

COMMON_ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
COMMON_ARGS="${COMMON_ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
COMMON_ARGS="${COMMON_ARGS} --bounds ${MIN_X},${MAX_X},${MIN_Y},${MAX_Y}"
COMMON_ARGS="${COMMON_ARGS} --padFileNamesWithZeros"
COMMON_ARGS="${COMMON_ARGS} --rootDirectory ${ROOT_PREVIEW_DIR}"
COMMON_ARGS="${COMMON_ARGS} --scale ${SCALE}"
COMMON_ARGS="${COMMON_ARGS} --format jpg"
COMMON_ARGS="${COMMON_ARGS} --convertToGray"

MAX_RUNNING_TASKS=1000
MEMORY="13G"
JAVA_CLASS="org.janelia.render.client.RenderSectionClient"

CORE_JOB_NAME="RenderSection"
TS=$(getTimestamp)
JOB_NAME="${CORE_JOB_NAME}_${TS}"
RUN_DIR="${SCRIPT_DIR}/run_${TS}_${CORE_JOB_NAME}"
LOG_DIR=$(createLogDirectory "${RUN_DIR}")

# create tmp directory for hdf5 reads
TMP_DIR="${RUN_DIR}/tmp"
mkdir "${TMP_DIR}"

COMMON_PARAMETERS_FILE="${RUN_DIR}/common_parameters.txt"
echo "${COMMON_ARGS}" > "${COMMON_PARAMETERS_FILE}"

JOB_PARAMETERS_FILE="${RUN_DIR}/job_specific_parameters.txt"
echo -n "" > "${JOB_PARAMETERS_FILE}"

echo """
Generating ${JOB_PARAMETERS_FILE}
"""

PROJECT_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}"
BATCH_COUNT=0
for STACK in "${STACK_ARRAY[@]}"; do

  OUT_FOLDER="${STACK}/box_${MIN_X}_${MAX_X}_${MIN_Y}_${MAX_Y}_at_${SCALE}"

  echo "fetching max z for ${STACK} ..."
  MAX_Z=$(curl -s "${PROJECT_URL}/stack/${STACK}" | jq -r '.stats.stackBounds.maxZ | floor')

  for Z in $(seq 1 "${MAX_Z}"); do
    echo " --stack ${STACK} --customOutputFolder ${OUT_FOLDER} ${Z}" >> "${JOB_PARAMETERS_FILE}"
    (( BATCH_COUNT += 1 ))
  done

done

BSUB_ARRAY_FILE="${RUN_DIR}/bsub-array.sh"

echo "#!/bin/bash" > "${BSUB_ARRAY_FILE}"
# shellcheck disable=SC2086
echo "
umask 0002

bsub -P ${BILL_TO} -J \"${JOB_NAME}[1-${BATCH_COUNT}]%${MAX_RUNNING_TASKS}\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J "${JOB_NAME}_check_logs" -w \"ended(${JOB_NAME})\" -n 1 -W 59 ${RENDER_PIPELINE_BIN}/check_logs.sh ${RUN_DIR}
" >> "${BSUB_ARRAY_FILE}"

chmod 755 "${BSUB_ARRAY_FILE}"

echo "
Common parameters for array job are:
$(cat "${COMMON_PARAMETERS_FILE}")

Created bsub array script for ${BATCH_COUNT} value batches in:
${BSUB_ARRAY_FILE}

Logs will be written to ${LOG_DIR}
"

if [[ -n ${LAUNCH_BSUB} ]]; then
  echo "Launching ${BSUB_ARRAY_FILE} ...
"
  ${BSUB_ARRAY_FILE}
fi
