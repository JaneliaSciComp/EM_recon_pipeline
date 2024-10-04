#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 1 )); then
  echo "USAGE $0 <number of nodes> [stack]"
  exit 1
fi

N_NODES="${1}"
STACK="${2:-${INTENSITY_CORRECTED_STACK}}"

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker ...

export N_EXECUTORS_PER_NODE=2 # 6
export N_CORES_PER_EXECUTOR=5 # 5
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

#-----------------------------------------------------------
ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${STACK}"
ARGS="${ARGS} --scale 0.22"
ARGS="${ARGS} --n5Path ${N5_PATH}"
ARGS="${ARGS} --resinMaskingEnabled false" # resin masking should be disabled for regional cross-correlation (it is needed for layer cross-correlation)
ARGS="${ARGS} --regionSize 500"

# must export this for flintstone
export LSF_PROJECT="${BILL_TO}"
export RUNTIME="333:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.n5.CorrelationN5Client"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/ccn5-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS

echo "
To find neuroglancer url file:
  grep 'neuroglancer URL' 04-driver.log
"

} 2>&1 | tee -a "${LOG_FILE}"
