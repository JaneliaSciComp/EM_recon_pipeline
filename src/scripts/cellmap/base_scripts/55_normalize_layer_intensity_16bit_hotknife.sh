#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

STACK="v2_acquire_align_16bit_destreak_v3_sc"

#-----------------------------------------------------------
N_NODES="20" # 20 11-slot nodes took 32 minutes for 6705 z layers with 2 tiles
SOURCE_DATASET="/render/jrc_mus_heart_4/v2_acquire_align_16bit_destreak_v3_sc___20251121_093512_review" # source needs to be 2,2,1

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

JAR="/groups/hess/hesslab/render/lib/hot-knife-0.0.7-SNAPSHOT.jar"
CLASS="org.janelia.saalfeldlab.hotknife.SparkNormalizeLayerIntensityN5"

ARGS="\
--n5Path=${N5_PATH} \
--n5DatasetInput=${SOURCE_DATASET} \
--n5DatasetOutput=${NORMALIZED_DATASET} \
--downsampleLevel=6 \
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