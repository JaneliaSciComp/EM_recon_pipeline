#!/bin/bash

set -e

MEMORY="${MEMORY:-6G}"
MAX_RUNNING_TASKS="${MAX_RUNNING_TASKS:-390}"
BATCH_AND_QUEUE_PARAMETERS=${BATCH_AND_QUEUE_PARAMETERS:--n 1 -W 59} # default to 59 minutes to get on short queue

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh 

ABSOLUTE_SCRIPT=`readlink -m $0`

USAGE_MESSAGE="${ABSOLUTE_SCRIPT} <values URL> <java client class> <work directory> <values per batch> <common client args>"

if (( $# < 5 )); then
  exitWithErrorAndUsage "missing parameters"
fi

VALUES_URL="$1"
JAVA_CLASS="$2"
WORK_DIR="$3"
VALUES_PER_BATCH="$4"
shift 4

declare -A EXCLUDED_VALUES
if [[ -n ${EXCLUDE_FILE} && -f ${EXCLUDE_FILE} ]]; then
  for VALUE in `cat ${EXCLUDE_FILE}`; do
    EXCLUDED_VALUES["${VALUE}"]="y"
  done
  echo "found ${#EXCLUDED_VALUES[@]} excluded values in ${EXCLUDE_FILE}"
fi


echo "retrieving values from ${VALUES_URL}"
VALUES=`parseValuesFromJsonArray ${VALUES_URL}`

CORE_JOB_NAME=`echo ${JAVA_CLASS} | sed '
  s/.*\.//
  s/Client//
'`

ABSOLUTE_WORK_DIR=`readlink -m ${WORK_DIR}`
ensureDirectoryExists ${ABSOLUTE_WORK_DIR} "work"

TS=`getTimestamp`
JOB_NAME="${CORE_JOB_NAME}_${TS}"
RUN_DIR="${ABSOLUTE_WORK_DIR}/run_${TS}_${CORE_JOB_NAME}"
LOG_DIR=`createLogDirectory "${RUN_DIR}"`

COMMON_PARAMETERS_FILE="${RUN_DIR}/common_parameters.txt"
echo "$*" > ${COMMON_PARAMETERS_FILE}

JOB_PARAMETERS_FILE="${RUN_DIR}/job_specific_parameters.txt"
> ${JOB_PARAMETERS_FILE}

echo """
Generating ${JOB_PARAMETERS_FILE}
"""

unset BATCH_VALUES
BATCH_COUNT=0
VALUES_COUNT=0
for VALUE in ${VALUES}; do

  if [ -z ${EXCLUDED_VALUES[${VALUE}]+x} ]; then

    if (( VALUES_PER_BATCH > 1 && VALUES_COUNT == 0 )); then
      echo " ${VALUE}" >> ${JOB_PARAMETERS_FILE}
      (( BATCH_COUNT += 1 ))
    else
      BATCH_VALUES="${BATCH_VALUES} ${VALUE}"
    fi

    (( VALUES_COUNT += 1 ))

    if (( VALUES_COUNT % VALUES_PER_BATCH == 0 )); then
      echo "${BATCH_VALUES}" >> ${JOB_PARAMETERS_FILE}
      (( BATCH_COUNT += 1 ))
      unset BATCH_VALUES
    fi

  fi

done

if (( VALUES_COUNT % VALUES_PER_BATCH != 0 )); then
  echo "${BATCH_VALUES}" >> ${JOB_PARAMETERS_FILE}
  (( BATCH_COUNT += 1 ))
fi

if [[ -n "${POST_CHECK_COMMAND}" ]]; then
  POST_CHECK_SCRIPT="${RUN_DIR}/post_check.sh"
  echo """#!/bin/bash
${POST_CHECK_COMMAND}
""" > ${POST_CHECK_SCRIPT}
  chmod 755 ${POST_CHECK_SCRIPT}
  echo "Created ${POST_CHECK_SCRIPT}"
fi

BSUB_ARRAY_FILE="${RUN_DIR}/bsub-array.sh"
echo """#!/bin/bash

umask 0002

bsub -P ${BILL_TO} -J \"${JOB_NAME}_a[1-1]%${MAX_RUNNING_TASKS}\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J \"${JOB_NAME}_b[2-${BATCH_COUNT}]%${MAX_RUNNING_TASKS}\" -w \"done(${JOB_NAME}_a)\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J "${JOB_NAME}_check_logs" -w \"ended(${JOB_NAME}_b)\" -n 1 -W 59 ${RENDER_PIPELINE_BIN}/check_logs.sh ${RUN_DIR}
""" > ${BSUB_ARRAY_FILE}

chmod 755 ${BSUB_ARRAY_FILE}

echo """
Common parameters for array job are:
`cat ${COMMON_PARAMETERS_FILE}`

Created bsub array script for ${BATCH_COUNT} value batches in:
${BSUB_ARRAY_FILE}

Logs will be written to ${LOG_DIR}
"""

if [[ -n ${LAUNCH_BSUB} ]]; then
  echo """Launching ${BSUB_ARRAY_FILE} ...
"""
  ${BSUB_ARRAY_FILE}
fi