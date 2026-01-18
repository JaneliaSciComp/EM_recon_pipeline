#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 2 )); then
  echo "USAGE $0 <data set> <number of nodes>, e.g. /render/jrc_22ak351_leaf_2lb/v3_acquire_align___20240419_072416 4"
  exit 1
fi

DATA_SET="${1}"
N_NODES="${2}"

DATASET_ROOT_PATH="${N5_PATH}${DATA_SET}"

DATASET_S0_PATH="${DATASET_ROOT_PATH}/s0"
if [[ ! -d "${DATASET_S0_PATH}" ]]; then
  echo "ERROR: ${DATASET_S0_PATH} does not exist"
  exit 1
fi

DATASET_ROOT_ATTRIBUTES_FILE="${DATASET_ROOT_PATH}/attributes.json"
if [[ ! -f "${DATASET_ROOT_ATTRIBUTES_FILE}" ]]; then
  echo "ERROR: ${DATASET_ROOT_ATTRIBUTES_FILE} does not exist"
  exit 1
fi

REVIEW_DATASET="${DATA_SET}_review"

REVIEW_DATASET_ROOT_PATH="${N5_PATH}${REVIEW_DATASET}"
if [[ -d "${REVIEW_DATASET_ROOT_PATH}" ]]; then
  echo "ERROR: ${REVIEW_DATASET_ROOT_PATH} exists"
  exit 1
fi

REVIEW_DATASET_S0_PATH="${REVIEW_DATASET_ROOT_PATH}/s0"
mkdir -p "${REVIEW_DATASET_ROOT_PATH}"
ln -s "${DATASET_S0_PATH}" "${REVIEW_DATASET_S0_PATH}"

# copy <source>/attributes.json to <review>/attributes.json and change all z scales to 1
#     { ..., "scales": [ [1,1,1], .... [2048,2048,2048] ], ... } =>
#     { ..., "scales": [ [1,1,1], .... [2048,2048,1] ], ... }
REVIEW_DATASET_ROOT_ATTRIBUTES_FILE="${REVIEW_DATASET_ROOT_PATH}/attributes.json"
jq '.scales[][2] |= 1' "${DATASET_ROOT_ATTRIBUTES_FILE}" > "${REVIEW_DATASET_ROOT_ATTRIBUTES_FILE}"

SCALE_COUNT=$(jq '.scales | length' "${REVIEW_DATASET_ROOT_ATTRIBUTES_FILE}")
DOWNSAMPLE_COUNT=$((SCALE_COUNT - 1))

OUTPUT_DATASETS="${REVIEW_DATASET}/s1"
FACTORS="2,2,1"
for scale in $(seq 2 "${DOWNSAMPLE_COUNT}"); do
  OUTPUT_DATASETS="${OUTPUT_DATASETS} ${REVIEW_DATASET}/s${scale}"
  FACTORS="${FACTORS} 2,2,1"
done

ARGV="\
--n5Path=${N5_PATH} \
--inputDatasetPath=${REVIEW_DATASET}/s0 \
--outputDatasetPath=${OUTPUT_DATASETS} \
--factors=${FACTORS}"

CLASS="org.janelia.saalfeldlab.n5.spark.downsample.N5DownsamplerSpark"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/downsample-review-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

HOT_KNIFE_JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.7-SNAPSHOT.jar"
FLINTSTONE="/groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh"

# use shell group to tee all output to log file
{

  echo "
Running with arguments:
${ARGV}
"
  # shellcheck disable=SC2086
  ${FLINTSTONE} ${N_NODES} "${HOT_KNIFE_JAR}" ${CLASS} ${ARGV}

  echo "
When completed, view n5 using:
  n5-view.sh -i ${N5_SAMPLE_PATH} -d ${INPUT_DATASET_ROOT}
"
} 2>&1 | tee -a "${LOG_FILE}"
