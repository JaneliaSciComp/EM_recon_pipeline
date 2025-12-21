#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 1 )); then
  echo "USAGE $0 <pipeline JSON file>
"
  exit 1
fi

PIPELINE_JSON="${1}"

if [ -f "${PIPELINE_JSON}" ]; then
  PIPELINE_JSON=$(readlink -m "${PIPELINE_JSON}")
else
  echo "ERROR: ${PIPELINE_JSON} not found!"
  exit 1
fi

PIPELINE_BASENAME=$(basename "${PIPELINE_JSON}")
PIPELINE_BASENAME="${PIPELINE_BASENAME%.json}"

ARGS="--pipelineJson ${PIPELINE_JSON}"

export RUNTIME="243:59"

#-----------------------------------------------------------
# Spark "big" worker setup ...

N_NODES="1"
export N_CORES_PER_EXECUTOR="120"
export N_EXECUTORS_PER_NODE=1
export N_OVERHEAD_CORES_PER_WORKER=8
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=8

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.pipeline.AlignmentPipelineClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/pipeline-$(date +"%Y%m%d_%H%M%S")-${PIPELINE_BASENAME}.log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
# shellcheck disable=SC2086
{
  echo "Running with arguments:
${ARGS}

Pipeline JSON is:
$(cat ${PIPELINE_JSON} | /groups/flyem/data/render/bin/jq '.')
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh "${N_NODES}" ${JAR} ${CLASS} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"
