#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 1 )); then
  echo """
USAGE: $0 <stack>

Examples:
  $0  w68_s000_r00_bgc_par_align_c_ic2d
"""
  exit 1
fi

RENDER_PROJECT="w68_serial_000_to_009"
STACK="${1}"

#-----------------------------------------------------------
# The normalization transformation derivation is not parallelized and is currently done in the driver
# ( see https://github.com/saalfeldlab/hot-knife/blob/d19bf4fe9acad572a72080205a20e35b1be256db/src/main/java/org/janelia/saalfeldlab/hotknife/SparkNormalizeLayerIntensityN5.java#L158 ).
# Application of the normalization transformation and export are parallelized.
#
# A sample 68 run with a 128-core driver and 10 workers took over 6 hours to complete.
# Guessing that a 60-worker run would complete in 2 hours or less.
N_NODES="60"
SOURCE_DATASET="/render/${RENDER_PROJECT}/${STACK}"

# /nrs/hess/data/hess_sample_68_full/export/hess_sample_68_full.n5/render/w68_serial_000_to_009/w68_s000_r00_bgc_par_align_c_ic2d
SOURCE_PATH="${BASE_N5_DIR}${SOURCE_DATASET}"
if [[ ! -d "${SOURCE_PATH}" ]]; then
  echo "ERROR: ${SOURCE_PATH} not found"
  exit 1
fi

export N_CORES_DRIVER=128  # need lots of memory (maybe not this much) on the driver for transformation derivation process

# must export this for flintstone
export RUNTIME="233:59"

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker defined in 00_config.sh

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.7-SNAPSHOT.cloud-cost-debug.jar"
CLASS="org.janelia.saalfeldlab.hotknife.MultiSemNormalizeLayerIntensity"

NORMALIZED_DATASET="${SOURCE_DATASET}_norm-layer-v2"
NORMALIZED_DATASET_DIR="${BASE_N5_DIR}${NORMALIZED_DATASET}"

ARGS="\
--n5Path=${BASE_N5_DIR} \
--n5DatasetInput=${SOURCE_DATASET} \
--n5DatasetOutput=${NORMALIZED_DATASET} \
--downsampleLevel 4
--aggregation MEAN
--lowerThreshold 5
--upperThreshold 250
--factors 2,2,2"
# --invert"

#if [[ ! -d ${NORMALIZED_DATASET_DIR} ]]; then
#  mkdir -p "${NORMALIZED_DATASET_DIR}"
#  if [[ -f ${SOURCE_PATH}/attributes.json ]]; then
#    cp "${SOURCE_PATH}"/attributes.json "${NORMALIZED_DATASET_DIR}"
#    echo "copied ${SOURCE_PATH}/attributes.json to ${NORMALIZED_DATASET_DIR}"
#  fi
#fi
printf "\n\nneed to:\n  cp ${SOURCE_PATH}/attributes.json ${NORMALIZED_DATASET_DIR}\n\n\n"

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