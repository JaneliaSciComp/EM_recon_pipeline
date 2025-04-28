#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")

source "/groups/hess/hesslab/render/GCIBMSEM/align/wafer_53d/00_config.sh"

N_NODES="10"
PIPELINE_JSON="${SCRIPT_DIR}/pipe.copy-match-pairs.json"

if [ ! -f "${PIPELINE_JSON}" ]; then
  echo "ERROR: ${PIPELINE_JSON} not found!"
  exit 1
fi

# Note: Spark executor setup with 11 cores per worker defined in 00_config.sh
JOB_LAUNCH_TIME=$(date +"%Y%m%d_%H%M%S")

ARGS="--pipelineJson ${PIPELINE_JSON}"

export RUNTIME="243:59"
export N_CORES_DRIVER=1

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.pipeline.AlignmentPipelineClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/pipeline-${JOB_LAUNCH_TIME}.log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
{
  echo "Running with arguments:
${ARGS}

Pipeline JSON is:
$(cat ${PIPELINE_JSON} | /groups/flyem/data/render/bin/jq '.')
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh "${N_NODES}" ${JAR} ${CLASS} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"
