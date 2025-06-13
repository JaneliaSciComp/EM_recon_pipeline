#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 1 )); then
  echo "USAGE $0 <number of nodes>"
  exit 1
fi

N_NODES="${1}" # This took 1h for one 10-core worker on a stack with size ~15000x13000x4000

#--------------------------------------------------
# select the align stack to normalize

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
PROJECT_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}"

mapfile -t STACK_NAMES < <(curl -s "${PROJECT_URL}/stackIds" | ${JQ} -r '.[].stack | select(contains("align"))' | sort)

echo "Which stack should be the basis for the layer normalization?"
select STACK in "${STACK_NAMES[@]}"; do
  if [ -n "${STACK}" ]; then
    break
  else
    echo "Invalid selection, try again."
  fi
done

CORRECTED_STACK="${STACK}_norm"

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker ...

export N_EXECUTORS_PER_NODE=2
export N_CORES_PER_EXECUTOR=5
export N_OVERHEAD_CORES_PER_WORKER=1
export N_CORES_DRIVER=1

#-----------------------------------------------------------
ARGS="--baseDataUrl ${BASE_DATA_URL}"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${STACK}"
ARGS="${ARGS} --targetStack ${CORRECTED_STACK}"

# must export this for flintstone
export LSF_PROJECT="${BILL_TO}"
export RUNTIME="233:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.intensityadjust.LayerNormalization16bitClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/norm-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS

} 2>&1 | tee -a "${LOG_FILE}"
