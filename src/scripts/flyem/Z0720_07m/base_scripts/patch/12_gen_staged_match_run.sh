#!/bin/bash

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`

CONFIG_FILE="${SCRIPT_DIR}/../00_config.sh"

if [[ -f ${CONFIG_FILE} ]]; then
  source ${CONFIG_FILE}
else
  echo "ERROR: cannot find ${CONFIG_FILE}"
  exit 1
fi

for RUN_TYPE in montage cross; do

PASS="1"
PAIRS_DIR="${SCRIPT_DIR}/pairs_${RUN_TYPE}"
if [[ ! -d ${PAIRS_DIR} ]]; then
  echo "Exiting with nothing to do, cannot find ${PAIRS_DIR}"
  exit 0
fi

# define RENDER_PIPELINE_BIN, BASE_DATA_URL, exitWithErrorAndUsage(), ensureDirectoryExists(), getRunDirectory(), createLogDirectory()
. /groups/flyTEM/flyTEM/render/pipeline/bin/pipeline_common.sh 

JAVA_CLASS="org.janelia.render.client.MultiStagePointMatchClient"
MEMORY="13G" # 15G allocated per slot
#BATCH_AND_QUEUE_PARAMETERS="-n 1 -W 60" # limit to 60 minutes for short queue
BATCH_AND_QUEUE_PARAMETERS="-n 1 -W 260"
MAX_RUNNING_TASKS="1000"

JOB_NAME=`getRunDirectory multi_stage_match_${RUN_TYPE}`
RUN_DIR="${SCRIPT_DIR}/${JOB_NAME}"
LOG_DIR=`createLogDirectory "${RUN_DIR}"`

echo """
------------------------------------------------------------------------
Setting up job for ${JOB_NAME} ...
"""

STAGE_JSON_NAME="stage_parameters.${RUN_TYPE}.json"
STAGE_JSON="${RUN_DIR}/${STAGE_JSON_NAME}"
cp ${SCRIPT_DIR}/${STAGE_JSON_NAME} ${STAGE_JSON}

COMMON_PARAMETERS_FILE="${RUN_DIR}/common_parameters.txt"

echo """
Generating ${COMMON_PARAMETERS_FILE}"""

ARGS="--baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --collection ${MATCH_COLLECTION}"
ARGS="${ARGS} --stageJson ${STAGE_JSON}"
ARGS="${ARGS} --cacheFullScaleSourcePixels" # cache full scale source since we don't have mipmaps

echo "${ARGS}" > ${COMMON_PARAMETERS_FILE}

JOB_PARAMETERS_FILE="${RUN_DIR}/job_specific_parameters.txt"
> ${JOB_PARAMETERS_FILE}

echo "Generating ${JOB_PARAMETERS_FILE}"

cd ${PAIRS_DIR}
FILE_COUNT=0
for JSON_FILE in `ls tile_pairs_*.json*`; do
  echo "--pairJson ${PAIRS_DIR}/${JSON_FILE}" >> ${JOB_PARAMETERS_FILE}
  (( FILE_COUNT += 1 ))
  if (( FILE_COUNT % 100 == 0 )); then
    echo -n "."
  fi
done

if (( FILE_COUNT == 0 )); then

  echo """
No tile pair files found !!!
Removing ${RUN_DIR} ..."
  rm -rf ${RUN_DIR}

else

  BSUB_ARRAY_FILE="${RUN_DIR}/bsub-array.sh"
  JOB_GROUP="/${BILL_TO}/${RENDER_OWNER}/${RENDER_PROJECT}/match/${RUN_TYPE}"

  echo """#!/bin/bash

bsub -P ${BILL_TO} -g \"${JOB_GROUP}\" -J \"${JOB_NAME}[1-${FILE_COUNT}]%${MAX_RUNNING_TASKS}\" ${BATCH_AND_QUEUE_PARAMETERS} -o /dev/null ${RENDER_PIPELINE_BIN}/run_array_ws_client_lsf.sh ${RUN_DIR} ${MEMORY} ${JAVA_CLASS}

bsub -P ${BILL_TO} -J "check_${RENDER_OWNER}_${RENDER_PROJECT}_${RUN_TYPE}_match" -w \"ended(${JOB_NAME})\" -n 1 -W 240 ${SCRIPT_DIR}/13_check_logs_and_report_stats.sh ${RUN_DIR}
""" > ${BSUB_ARRAY_FILE}

  chmod 755 ${BSUB_ARRAY_FILE}

  echo """

Created bsub array script for ${FILE_COUNT} jobs in ${BSUB_ARRAY_FILE}

Logs will be written to ${LOG_DIR}
"""

  if [[ "${1}" == "launch" ]]; then
    ${BSUB_ARRAY_FILE}
  fi

fi

done
