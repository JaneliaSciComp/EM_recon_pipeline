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
  $0 w60_serial_290_to_299 w60_s296_r00_d00_align_avgshd_ic_norm-layer
"""
  exit 1
fi

RENDER_PROJECT="${1}"
STACK="${2}"

#-----------------------------------------------------------
N_NODES="20" # 20 11-slot nodes took ? minutes for w60_s296_r00_d00_align_avgshd_ic_norm-layer
SOURCE_DATASET="/render/${RENDER_PROJECT}/${STACK}"
CLAHE_DATASET="${SOURCE_DATASET}_clahe"

# /nrs/hess/data/hess_wafers_60_61/export/hess_wafers_60_61.n5/render/w60_serial_290_to_299/w60_s296_r00_d00_align_avgshd_ic_norm-layer
SOURCE_PATH="${BASE_N5_DIR}/${SOURCE_DATASET}"
if [[ ! -d "${SOURCE_PATH}" ]]; then
  echo "ERROR: ${SOURCE_PATH} not found"
  exit 1
fi

CLAHE_PATH="${BASE_N5_DIR}/${CLAHE_DATASET}"
if [[ -d "${CLAHE_PATH}" ]]; then
  echo "ERROR: ${CLAHE_PATH} already exists"
  exit 1
fi

# must export this for flintstone
export RUNTIME="233:59"

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker defined in 00_config.sh

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.5-SNAPSHOT.jar" # jar with hack fixed maxHeight of 51
CLASS="org.janelia.saalfeldlab.hotknife.SparkMaskedCLAHEMultiSEM"

# using blockFactorXY 1 instead of default 8 to avoid OOM with larger 1024,1024,maxZ blocks
ARGS="\
--n5PathInput=${BASE_N5_DIR} \
--n5DatasetInput=${SOURCE_DATASET} \
--n5DatasetOutput=${CLAHE_DATASET} \
--blockFactorXY 1 \
--blockFactorZ 1 \
--invert"

if [[ ! -d ${CLAHE_PATH} ]]; then
  mkdir -p "${CLAHE_PATH}"
  if [[ -f ${SOURCE_PATH}/attributes.json ]]; then
    cp "${SOURCE_PATH}"/attributes.json "${CLAHE_PATH}"
    echo "copied ${SOURCE_PATH}/attributes.json to ${CLAHE_PATH}"
  fi
fi

LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/clahe.${RUN_TIME}.out"

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
  n5_view -i ${BASE_N5_DIR} -d ${CLAHE_DATASET}
"

} 2>&1 | tee -a "${LOG_FILE}"
