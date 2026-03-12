#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 1 )); then

  unset PIPELINE_JSON
  shopt -s nullglob
  JSON_FILES=(pipeline_json/03_correct_intensity/*.json)
  shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
  FILE_COUNT=${#JSON_FILES[@]}
  if (( FILE_COUNT == 0 )); then
    echo "ERROR: no pipeline json files found"
    exit 1
  else
    PS3="Choose pipeline json file for run: "
    select PIPELINE_JSON in "${JSON_FILES[@]}"; do
      break
    done
  fi

else
  PIPELINE_JSON="${1}"
fi

if [ -f "${PIPELINE_JSON}" ]; then
  PIPELINE_JSON=$(readlink -m "${PIPELINE_JSON}")
else
  echo "ERROR: ${PIPELINE_JSON} not found!"
  exit 1
fi

PIPELINE_BASENAME=$(basename "${PIPELINE_JSON}")
PIPELINE_BASENAME="${PIPELINE_BASENAME%.json}"

# Note: Spark executor setup with 11 cores per worker defined in 00_config.sh
N_NODES="160"              # with 160 workers, ic2d for 300 sample 68 z layers took 30 minutes
export N_CORES_DRIVER=128  # need lots of memory for the driver since everything gets pulled back from workers to save in one batch

ARGS="--pipelineJson ${PIPELINE_JSON}"

#export RUNTIME="3:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.pipeline.AlignmentPipelineClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/pipeline-$(date +"%Y%m%d_%H%M%S")-${PIPELINE_BASENAME}.log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
{
  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh "${N_NODES}" ${JAR} ${CLASS} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"
