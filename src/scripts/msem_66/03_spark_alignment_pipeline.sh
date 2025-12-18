#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 2 )); then
  echo "USAGE $0 <number of nodes> <pipeline JSON file>
"
  exit 1
fi

N_NODES="${1}"
PIPELINE_JSON="${2}"

if [ ! -f "${PIPELINE_JSON}" ]; then
  echo "ERROR: ${PIPELINE_JSON} not found!"
  exit 1
fi

PIPELINE_BASENAME=$(basename "${PIPELINE_JSON}")
PIPELINE_BASENAME="${PIPELINE_BASENAME%.json}"

# Note: Spark executor setup with 11 cores per worker defined in 00_config.sh

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
