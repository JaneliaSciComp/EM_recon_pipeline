#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 2 )); then
  echo "USAGE $0 <project> <stack> [export mask y|n]

  e.g. w60_serial_290_to_299 w60_s296_r00_d00_align_avgshd
       w60_serial_290_to_299 w60_s296_r00_d00_align y
"
  exit 1
fi

RENDER_PROJECT="${1}"
STACK="${2}"
EXPORT_MASK="${3}"

STACK_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${STACK}"
MAX_Z=$(curl -s "${STACK_URL}"  | jq -r '.stats.stackBounds.maxZ' | cut -d'.' -f1) # some curl versions return float so cut off decimal
if (( MAX_Z > 128 )); then
  MAX_Z=128
fi

N_NODES="2" # with 2 11-core worker nodes, export should take less than 2 hours

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker defined in 00_config.sh

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

LOG_PREFIX="n5"
N5_DATASET="/render/${RENDER_PROJECT}/${STACK}"
MASK_ARG=""

if [[ "${EXPORT_MASK}" == "y" ]]; then
  LOG_PREFIX="${LOG_PREFIX}_mask"
  N5_DATASET="${N5_DATASET}_mask"
  MASK_ARG="--exportMask"
fi

FULL_N5_DATASET_PATH="${BASE_N5_DIR}${N5_DATASET}"
if [ -d "${FULL_N5_DATASET_PATH}" ]; then
  echo "Note: appending run time to dataset name since ${FULL_N5_DATASET_PATH} exists"
  N5_DATASET="${N5_DATASET}___${RUN_TIME}"
fi

ARGS="--baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${STACK}"
ARGS="${ARGS} --tileWidth 2048 --tileHeight 2048 --blockSize 1024,1024,${MAX_Z} --factors 2,2,1"
ARGS="${ARGS} --n5Path ${BASE_N5_DIR} --n5Dataset ${N5_DATASET} ${MASK_ARG}"

# must export this for flintstone
export LSF_PROJECT="${BILL_TO}"
export RUNTIME="233:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.n5.N5Client"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/${LOG_PREFIX}-${RUN_TIME}.log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS

echo "
To view n5:
  n5_view -i ${BASE_N5_DIR} -d ${N5_DATASET}
"

} 2>&1 | tee -a "${LOG_FILE}"