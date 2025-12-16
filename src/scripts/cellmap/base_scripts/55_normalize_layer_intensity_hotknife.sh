#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

N_NODES="${1:-20}" # 20 11-slot nodes took 32 minutes for 6705 z layers with 2 tiles

# ----------------------------------------------
# N5 paths
unset RENDERED_N5_PATH
shopt -s nullglob
DIRS=("${N5_PATH}"/render/"${RENDER_PROJECT}"/*_review/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "
ERROR: no ${RENDER_PROJECT} project '_review' n5 directories (with 2,2,1 downsampling) found in ${N5_PATH}

To downsample a 2,2,2 n5, copy and run /groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline/src/scripts/cellmap/base_scripts/old/47_spark_downsample_for_review.sh
"
  exit 1
else
  echo "
The following n5s exist:
"
  find "${N5_PATH}/render/${RENDER_PROJECT}" -mindepth 1 -maxdepth 1 -type d ! -name attributes.json -print
  echo "
To downsample a 2,2,2 n5, copy and run /groups/fibsem/home/fibsemxfer/git/EM_recon_pipeline/src/scripts/cellmap/base_scripts/old/47_spark_downsample_for_review.sh

This subset of review n5s have already been downsampled with 2,2,1 factors:
"
  PS3="
Choose the number of a review N5 to normalize (or hit ctrl-C to quit if you need to downsample an n5 first): "
  select RENDERED_N5_PATH in "${DIRS[@]}"; do
    break
  done
fi

# trim trailing slash
RENDERED_N5_PATH="${RENDERED_N5_PATH%/}" # /nrs/cellmap/data/jrc_mus-heart-6/jrc_mus-heart-6.n5/render/jrc_mus_heart_6/v4_acquire_...

# identify source dataset
SOURCE_DATASET="${RENDERED_N5_PATH#"${N5_PATH}"}"  # /render/jrc_mus_heart_6/v4_acquire_align_16bit_destreak_straight_sc___20251202_103022

#-----------------------------------------------------------
SOURCE_PATH="${N5_PATH}${SOURCE_DATASET}"
if [[ ! -d "${SOURCE_PATH}" ]]; then
  echo "ERROR: ${SOURCE_PATH} not found"
  exit 1
fi

NORMALIZED_DATASET="${SOURCE_DATASET}_norm-layer"
NORMALIZED_DATASET_DIR="${N5_PATH}${NORMALIZED_DATASET}"

# must export this for flintstone
export RUNTIME="233:59"

#-----------------------------------------------------------
# setup for 11 cores per worker (allows 4 workers to fit on one 48 core node with 4 cores to spare for other jobs)
export N_EXECUTORS_PER_NODE=5
export N_CORES_PER_EXECUTOR=2
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))

# use 8 driver cores per Innerberger suggestion here: https://github.com/JaneliaSciComp/recon_fibsem/issues/89#issuecomment-2619787900
export N_CORES_DRIVER=8

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker defined in 00_config.sh

RUN_TIME=$(date +"%Y%m%d_%H%M%S")

# JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.7-SNAPSHOT.jar"
JAR="/groups/shroff/shrofflab/render/align/jrc_steinernema-20251017/hot-knife-0.0.7-SNAPSHOT.jar"  # built from feature/multi-sem-normalization branch
CLASS="org.janelia.saalfeldlab.hotknife.FibSemNormalizeLayerIntensity"

ARGS="\
--n5Path=${N5_PATH} \
--n5DatasetInput=${SOURCE_DATASET} \
--n5DatasetOutput=${NORMALIZED_DATASET} \
--downsampleLevel=4 \
--shift=MEAN \
--scale=GAUSS \
--factors=2,2,2"

#--spreadIntensities \

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
  n5_view -i ${N5_PATH} -d ${NORMALIZED_DATASET}
"

} 2>&1 | tee -a "${LOG_FILE}"