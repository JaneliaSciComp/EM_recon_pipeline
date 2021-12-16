#!/bin/bash

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`

CONFIG_FILE="${SCRIPT_DIR}/00_config.sh"

if [[ -f ${CONFIG_FILE} ]]; then
  source ${CONFIG_FILE}
else
  echo "ERROR: cannot find ${CONFIG_FILE}"
  exit 1
fi

#if (( $# != 1 )); then
#  echo "USAGE: $0 <inference options file>"
#  exit 1
#fi

#INFERENCE_OPTIONS_FILE=$(readlink -m $1)
INFERENCE_OPTIONS_FILE="${SCRIPT_DIR}/inference-options.sf_0_1.json"

if [[ ! -f ${INFERENCE_OPTIONS_FILE} ]]; then
  echo "ERROR: ${INFERENCE_OPTIONS_FILE} not found"
  exit 1
fi

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh 

JAVA_CLASS="org.janelia.render.client.zspacing.ZPositionCorrectionClient"
MEMORY="13G" # 15G allocated per slot
#BATCH_AND_QUEUE_PARAMETERS="-n 1 -W 59"
BATCH_AND_QUEUE_PARAMETERS="-n 1 -W 120"
MAX_RUNNING_TASKS="1000"

JOB_NAME=`getRunDirectory z_corr`
RUN_DIR="${SCRIPT_DIR}/${JOB_NAME}"
LOG_DIR=`createLogDirectory "${RUN_DIR}"`

echo """
------------------------------------------------------------------------
Setting up job for ${JOB_NAME} ...
"""

COMMON_PARAMETERS_FILE="${RUN_DIR}/common_parameters.txt"
SOLVE_BASE_PARAMETERS_FILE="${RUN_DIR}/solve_base_parameters.txt"

echo """Generating ${COMMON_PARAMETERS_FILE}
"""

ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --stack ${ALIGN_STACK}"
ARGS="${ARGS} --rootDirectory /nrs/flyem/render/z_corr"
ARGS="${ARGS} --runName ${JOB_NAME}"
ARGS="${ARGS} --scale 0.22" # important that this forces us away from a mipmap boundary (e.g. 0.25 was bad)

echo "${ARGS}" > ${SOLVE_BASE_PARAMETERS_FILE}

ARGS="${ARGS} --optionsJson ${INFERENCE_OPTIONS_FILE}"
#ARGS="${ARGS} --debugFormat png"

echo "${ARGS}" > ${COMMON_PARAMETERS_FILE}

cat ${COMMON_PARAMETERS_FILE}

SECONDS_PER_LAYER=10  # 10 seconds for 2 tile layer at scale 0.25
MINUTES_PER_JOB=20    # keep safely on short queue

JOB_PARAMETERS_FILE="${RUN_DIR}/job_specific_parameters.txt"

echo """
Generating ${JOB_PARAMETERS_FILE}"""

${SCRIPT_DIR}/gen_z_corr_job_parameters.py ${RENDER_OWNER} ${RENDER_PROJECT} ${ALIGN_STACK} ${SECONDS_PER_LAYER} ${MINUTES_PER_JOB} > ${JOB_PARAMETERS_FILE}

FILE_COUNT=$(wc -l ${JOB_PARAMETERS_FILE} | cut -f1 -d' ')

if (( FILE_COUNT == 0 )); then

  echo """
No z correction batches found !!!
Removing ${RUN_DIR} ..."
  rm -rf ${RUN_DIR}

else

  BSUB_ARRAY_FILE="${RUN_DIR}/bsub-array.sh"

  echo """#!/bin/bash

bsub -P ${BILL_TO} -J \"${JOB_NAME}[1-${FILE_COUNT}]%${MAX_RUNNING_TASKS}\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J "${JOB_NAME}_check_logs" -w \"ended(${JOB_NAME})\" -n 1 -W 59 ${RENDER_PIPELINE_BIN}/check_logs.sh ${RUN_DIR}

bsub -P ${BILL_TO} -J "${JOB_NAME}_solve" -w \"done(${JOB_NAME}_check_logs)\" -n 1 ${SCRIPT_DIR}/43_solve_z_corr_and_plot.sh ${SOLVE_BASE_PARAMETERS_FILE} ${INFERENCE_OPTIONS_FILE}
""" > ${BSUB_ARRAY_FILE}

  chmod 755 ${BSUB_ARRAY_FILE}

  echo """
Created bsub array script for ${FILE_COUNT} jobs in:
${BSUB_ARRAY_FILE}

Logs will be written to ${LOG_DIR}
"""

  if [[ "${1}" == "launch" ]]; then
    ${BSUB_ARRAY_FILE}
  fi

fi
