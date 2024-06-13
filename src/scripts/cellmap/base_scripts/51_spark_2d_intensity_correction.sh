#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 2 )); then
  echo "USAGE $0 <number of nodes> <source stack> ( e.g. 40 v3_acquire_align_destreak )"
  exit 1
fi

N_NODES="${1}"
SOURCE_STACK="${2}"

PIPELINE_JSON=$(cat <<EOF
{
  "multiProject": {
    "baseDataUrl" : "http://${SERVICE_HOST}/render-ws/v1",
    "owner" : "${RENDER_OWNER}", "project" : "${RENDER_PROJECT}",
    "stackIdWithZ" : { "stackNames": [ "${SOURCE_STACK}" ], "zValuesPerBatch": 1 }
  },
  "pipelineSteps": [
    "CORRECT_INTENSITY"
  ],
  "intensityCorrectionSetup": {
    "distributedSolve" : {
      "maxAllowedErrorGlobal" : 10.0,
      "maxIterationsGlobal" : 10000,
      "maxPlateauWidthGlobal" : 100,
      "threadsWorker" : 3,
      "threadsGlobal" : 8,
      "deriveThreadsUsingSparkConfig" : true
    },
    "intensityAdjust" : {
      "lambda1" : 0.01,
      "lambda2" : 0.01,
      "maxPixelCacheGb" : 1,
      "renderScale" : 0.1,
      "zDistance" : { "simpleZDistance" : [ 0 ] },
      "numCoefficients" : 8,
      "equilibrationWeight" : 0.0
    },
    "targetStack": {
      "stackSuffix": "_ic2d",
      "completeStack": true
    },
    "blockPartition": {
      "sizeZ": 1
    }
  }
}
EOF
)

JOB_LAUNCH_TIME=$(date +"%Y%m%d_%H%M%S")

PIPELINE_JSON_DIR="${SCRIPT_DIR}/pipeline_json"
mkdir -p "${PIPELINE_JSON_DIR}"
PIPELINE_JSON_FILE="${PIPELINE_JSON_DIR}/pipeline.ic2d.${JOB_LAUNCH_TIME}.json"

echo "${PIPELINE_JSON}" > "${PIPELINE_JSON_FILE}"

ARGS="--pipelineJson ${PIPELINE_JSON_FILE}"

#-----------------------------------------------------------
# setup for 11 cores per worker (allows 4 workers to fit on one 48 core node with 4 cores to spare for other jobs)
export N_EXECUTORS_PER_NODE=5
export N_CORES_PER_EXECUTOR=2
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

# don't start driver until all workers are available
export MIN_WORKERS="${N_NODES}"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.pipeline.AlignmentPipelineClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/ic2d-${JOB_LAUNCH_TIME}.log"

mkdir -p "${LOG_DIR}"

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh ${N_NODES} ${JAR} ${CLASS} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"
