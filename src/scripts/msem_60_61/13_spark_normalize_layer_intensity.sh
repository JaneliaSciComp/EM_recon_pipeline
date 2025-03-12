#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 2 )); then
  echo """
USAGE: $0 <render project> <stack>

Examples:
  $0  w60_serial_360_to_369  w60_s360_r00_d20_gc_align_small_block
"""
  exit 1
fi

RENDER_PROJECT="${1}"
STACK="${2}"

#-----------------------------------------------------------
N_NODES="2" # 2 11-slot nodes took 228 minutes for w60_s360_r00_d20_gc_align_small_block
SOURCE_DATASET="/render/${RENDER_PROJECT}/${STACK}"

# /nrs/hess/data/hess_wafers_60_61/export/hess_wafers_60_61.n5/render/w60_serial_290_to_299/w60_s296_r00_d00_align_avgshd
SOURCE_PATH="${BASE_N5_DIR}${SOURCE_DATASET}"
if [[ ! -d "${SOURCE_PATH}" ]]; then
  echo "ERROR: ${SOURCE_PATH} not found"
  exit 1
fi

# TODO: remove this hack when hotknife repo gets updated
cp "${BASE_N5_DIR}"/attributes.3.json "${BASE_N5_DIR}"/attributes.json

# must export this for flintstone
export RUNTIME="233:59"

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker defined in 00_config.sh

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

JAR="/groups/flyem/data/render/lib/hot-knife-0.0.5-SNAPSHOT.jar"
CLASS="org.janelia.saalfeldlab.hotknife.SparkNormalizeLayerIntensityN5"

ARGS="\
--n5PathInput=${BASE_N5_DIR} \
--n5DatasetInput=${SOURCE_DATASET} \
--factors 2,2,1"
# --invert"

NORMALIZED_DATASET="${SOURCE_DATASET}_norm-layer"
NORMALIZED_DATASET_DIR="${BASE_N5_DIR}${NORMALIZED_DATASET}"

if [[ ! -d ${NORMALIZED_DATASET_DIR} ]]; then
  mkdir -p "${NORMALIZED_DATASET_DIR}"
  if [[ -f ${SOURCE_PATH}/attributes.json ]]; then
    cp "${SOURCE_PATH}"/attributes.json "${NORMALIZED_DATASET_DIR}"
    echo "copied ${SOURCE_PATH}/attributes.json to ${NORMALIZED_DATASET_DIR}"
  fi
fi

LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/norm.${RUN_TIME}.out"

mkdir -p ${LOG_DIR}

# use shell group to tee all output to log file
{

  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS

echo "
To view n5:
  n5_view -i ${BASE_N5_DIR} -d ${NORMALIZED_DATASET}
"

} 2>&1 | tee -a "${LOG_FILE}"
