#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 1 )); then
  echo "USAGE $0 <number of nodes>"
  exit 1
fi

N_NODES="${1}"        # 4, 10, 20

ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ALIGN_STACK}"
ARGS="${ARGS} --intensityCorrectedFilterStack ${INTENSITY_CORRECTED_STACK}"
ARGS="${ARGS} --completeCorrectedStack"

#ARGS="${ARGS} --minZ 1225 --maxZ 1228"

# must export this for flintstone
export LSF_PROJECT="${BILL_TO}"
#export RUNTIME="3:59"

#-----------------------------------------------------------
# setup for 11 cores per worker (allows 4 workers to fit on one 48 core node with 4 cores to spare for other jobs)
export N_EXECUTORS_PER_NODE=5
export N_CORES_PER_EXECUTOR=2
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.IntensityAdjustedScapeClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/ic-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS
} 2>&1 | tee -a "${LOG_FILE}"
