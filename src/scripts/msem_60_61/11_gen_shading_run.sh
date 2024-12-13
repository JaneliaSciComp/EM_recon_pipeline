#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh

if (( $# < 1 )); then
  echo "USAGE $0 <render project> [any character to launch job]   (e.g. w60_serial_290_to_299 y)
"
  exit 1
fi

RENDER_PROJECT="$1"
LAUNCH_BSUB="$2"

PROJECT_STACKS_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stacks"
PROJECT_ALIGN_STACKS=$(curl -s "${PROJECT_STACKS_URL}" | jq -r '.[].stackId.stack' | grep "_align$")

MAX_RUNNING_TASKS=1000
MEMORY="13G"
JAVA_CLASS="org.janelia.render.client.multisem.ExponentialFitClient"

CORE_JOB_NAME="ExponentialFit"
TS=$(getTimestamp)
JOB_NAME="${CORE_JOB_NAME}_${TS}"
RUN_DIR="${SCRIPT_DIR}/run_${TS}_${CORE_JOB_NAME}"
LOG_DIR=$(createLogDirectory "${RUN_DIR}")

# create tmp directory for hdf5 reads
TMP_DIR="${RUN_DIR}/tmp"
mkdir "${TMP_DIR}"

COMMON_PARAMETERS_FILE="${RUN_DIR}/common_parameters.txt"
echo " --baseDataUrl http://${SERVICE_HOST}/render-ws/v1 --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --completeTargetStack" > "${COMMON_PARAMETERS_FILE}"

JOB_PARAMETERS_FILE="${RUN_DIR}/job_specific_parameters.txt"
echo -n "" > "${JOB_PARAMETERS_FILE}"

echo """
Generating ${JOB_PARAMETERS_FILE}
"""

BATCH_COUNT=0
for STACK in ${PROJECT_ALIGN_STACKS}; do
  echo " --stack ${STACK} --targetStack ${STACK}_avgshd" >> "${JOB_PARAMETERS_FILE}"
  (( BATCH_COUNT += 1 ))
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
