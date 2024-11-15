#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 2 )); then
  echo "USAGE $0 <number of nodes> <pipeline group>  (e.g. 10 w60-serial-290-299)
"
  exit 1
fi

N_NODES="${1}"
PIPELINE_GROUP="${2}"
PIPELINE_JSON="${SCRIPT_DIR}/pipeline_json/02_align/pipe.02.align.${PIPELINE_GROUP}.json"

if [ ! -f "${PIPELINE_JSON}" ]; then
  echo "ERROR: ${PIPELINE_JSON} not found!"
  exit 1
fi

PIPELINE_BASENAME=$(basename "${PIPELINE_JSON}")
PIPELINE_BASENAME="${PIPELINE_BASENAME%.json}"

ARGS="--pipelineJson ${PIPELINE_JSON}"

export RUNTIME="243:59"

#-----------------------------------------------------------
# Spark "big" worker setup ...

export N_CORES_PER_EXECUTOR="10"
export N_EXECUTORS_PER_NODE=1
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

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
