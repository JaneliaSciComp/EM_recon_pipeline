#!/bin/bash

######################
#   - generate new run directory
#   - create job_specific_parameters.txt (for directory of input files or list of z values)
#   - match memory to slots
#
#   <working dir>/run-<type>-<timestamp>/
#     common_parameters.txt (memory, java class, other common parameters)
#     job_specific_parameters.txt
#     logs/
#     bsub-array.sh
#
#  check for log errors
#  store aggregate stack data
#  backup data to tier2
########################

set -e

MEMORY="${MEMORY:-6G}"
MAX_RUNNING_TASKS="${MAX_RUNNING_TASKS:-390}"
Z_PER_BATCH="${Z_PER_BATCH:-1}"

BATCH_AND_QUEUE_PARAMETERS="-n 1 -W 59" # 1 hour == 60 minutes

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh 

ABSOLUTE_SCRIPT=`readlink -m $0`

USAGE_MESSAGE="${ABSOLUTE_SCRIPT} <z values URL> <java client class> <work directory> <common client args>"

if (( $# < 4 )); then
  exitWithErrorAndUsage "missing parameters"
fi

Z_URL="$1"
JAVA_CLASS="$2"
WORK_DIR="$3"
shift 3

if [[ ${Z_URL} = http* ]]; then

  echo """
Retrieving z values from ${Z_URL}
"""
  Z_VALUES=`parseValuesFromJsonArray ${Z_URL}`

elif [[ -f "${Z_URL}" ]]; then

  Z_VALUES=`cat ${Z_URL}`

else

  exitWithErrorAndUsage "invalid z values URL specified"
  
fi

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

echo "Generating ${JOB_PARAMETERS_FILE}"

Z_COUNT=1
Z_BATCH_COUNT=1
for Z in ${Z_VALUES}; do
  echo -n "${Z} " >> ${JOB_PARAMETERS_FILE}
  if (( (Z_COUNT == 1) || (Z_COUNT % Z_PER_BATCH == 0) )); then
    echo "" >> ${JOB_PARAMETERS_FILE}
    (( Z_BATCH_COUNT += 1 ))
    echo -n "."
  fi
  (( Z_COUNT += 1 ))
done

if (( Z_COUNT % Z_PER_BATCH > 0 )); then
  echo "" >> ${JOB_PARAMETERS_FILE}
  (( Z_BATCH_COUNT += 1 ))
  echo -n "."
fi

(( Z_BATCH_COUNT -= 1 ))
echo

BSUB_ARRAY_FILE="${RUN_DIR}/bsub-array.sh"
echo """#!/bin/bash

umask 0002

bsub -P ${BILL_TO} -J \"${JOB_NAME}_a[1-1]%${MAX_RUNNING_TASKS}\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J \"${JOB_NAME}_b[2-${Z_BATCH_COUNT}]%${MAX_RUNNING_TASKS}\" -w \"done(${JOB_NAME}_a)\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J "check_logs" -w \"ended(${JOB_NAME}_b)\" -n 1 -W 59 ${RENDER_PIPELINE_BIN}/check_logs.sh ${RUN_DIR}
""" > ${BSUB_ARRAY_FILE}

chmod 755 ${BSUB_ARRAY_FILE}

echo """
Common parameters for array job are:
`cat ${COMMON_PARAMETERS_FILE}`

Created bsub array script for ${Z_BATCH_COUNT} jobs (z or z batches) in:
${BSUB_ARRAY_FILE}

Logs will be written to:
${LOG_DIR}
"""
