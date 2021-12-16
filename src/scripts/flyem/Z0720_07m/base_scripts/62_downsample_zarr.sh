#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

umask 0002

if (( $# < 1 )); then
  echo "USAGE $0 <number of nodes>"
  exit 1
fi

N_NODES="${1}"        # 30 11-slot workers takes 2+ hours

BASE_ZARR_COST_DIR="/nrs/flyem/bukharih"
N5_FIELD_PATH="/nrs/flyem/render/n5/${RENDER_OWNER}"

if [[ ! -d ${BASE_ZARR_COST_DIR} ]]; then
  echo "ERROR: ${BASE_ZARR_COST_DIR} not found"
  exit 1
fi

# ZARR_PATH="/nrs/flyem/bukharih/Sec25_trn_vld_single_head_jitter_flips_12-5-3-2-2-4_s3_s2_ft_20_cosine.zarr"
shopt -s nullglob
DIRS=("${BASE_ZARR_COST_DIR}/${RENDER_PROJECT}"_*.zarr/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "ERROR: no ${BASE_ZARR_COST_DIR}/${RENDER_PROJECT}_*.zarr directories found"
  exit 1
elif (( DIR_COUNT == 1 )); then
  ZARR_PATH=${DIRS[0]}
else
  PS3="Choose a source directory: "
  select ZARR_PATH in "${DIRS[@]}"; do
    break
  done
fi

# trim trailing slash
ZARR_PATH=${ZARR_PATH%/}

if [[ ! -d ${ZARR_PATH} ]]; then
  echo "ERROR: ${ZARR_PATH} not found"
  exit 1
fi

INPUT_DATASET="prediction"

ARGS="--zarrPath ${ZARR_PATH}"
ARGS="${ARGS} --inputDatasetPath ${INPUT_DATASET}"

# s1 = 4,4,4 (the prediction from Habib)
# s2 = 4,1,4 >>> 16,4,16 
# s3 = 3,1,3 >>> 48,4,48
# s4 = 3,1,3 >>> 144,4,144
# s5 = 3,1,3 >>> 432,4,432
# s6 = 1,4,1 >>> 432,16,432
# s7 = 1,4,1 >>> 432,64,432

for s in 2 3 4 5 6 7; do
  ARGS="${ARGS} --outputDatasetPath /s${s}" # need at least one slash in dataset name to work around bug
done

for f in 4,1,4 3,1,3 3,1,3 3,1,3 1,4,1 1,4,1; do
  ARGS="${ARGS} --factors ${f}"
done

# must export this for flintstone
export LSF_PROJECT="flyem"
export RUNTIME="3:59"

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
# prepend newer gson jar to spark classpaths to fix bug
# see https://hadoopsters.com/2019/05/08/how-to-override-a-spark-dependency-in-client-or-cluster-mode/
GSON_JAR="gson-2.8.6.jar"
GSON_JAR_PATH="/groups/flyem/data/trautmane/hot-knife/${GSON_JAR}"
export SUBMIT_ARGS="--conf spark.driver.extraClassPath=${GSON_JAR_PATH} --conf spark.executor.extraClassPath=${GSON_JAR_PATH}"

#-----------------------------------------------------------
JAR="/groups/flyem/data/render/lib/hot-knife-0.0.4-SNAPSHOT.jar"
CLASS="org.janelia.saalfeldlab.hotknife.SparkDownsampleZarr"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/downsample-zarr-`date +"%Y%m%d_%H%M%S"`.log"

mkdir -p ${LOG_DIR}

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo """Running with arguments:
${ARGS}
"""
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS

  echo """To view completed n5 volume:
  n5_view.sh -i ${ZARR_PATH} -d ${OUTPUT_DATASET}
"""
} 2>&1 | tee -a ${LOG_FILE}
