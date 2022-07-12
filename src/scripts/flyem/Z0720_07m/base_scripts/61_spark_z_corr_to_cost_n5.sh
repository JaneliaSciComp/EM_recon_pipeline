#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

umask 0002

if (( $# < 2 )); then
  echo "USAGE $0 <number of nodes> <filter y or n> [band size]"
  echo "  Examples:"
  echo "      $0 30 n"
  echo "      $0 30 y 50"
  echo "      $0 30 n 400"
  exit 1
fi

N_NODES="${1}"        # 30 11-slot workers takes 2+ hours
FILTER_Y_OR_N="${2}"
BAND_SIZE="${3:-50}"

PROJECT_Z_CORR_DIR="${N5_PATH}/z_corr/${RENDER_PROJECT}"

# /nrs/flyem/render/n5/Z0720_07m_BR/z_corr/Sec39/v1_acquire_trimmed_sp1___20210410_220552

if [[ ! -d ${PROJECT_Z_CORR_DIR} ]]; then
  echo "ERROR: ${PROJECT_Z_CORR_DIR} not found"
  exit 1
fi
shopt -s nullglob
DIRS=(${PROJECT_Z_CORR_DIR}/*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "ERROR: no directories found in ${PROJECT_Z_CORR_DIR}"
  exit 1
elif (( DIR_COUNT == 1 )); then
  Z_CORR_PATH=${DIRS[0]}
else
  PS3="Choose a source directory: "
  select Z_CORR_PATH in `echo ${DIRS[@]}`; do
    break
  done
fi

# trim trailing slash
Z_CORR_PATH=$(echo "${Z_CORR_PATH}" | sed 's@/$@@')

if [[ ! -d ${Z_CORR_PATH} ]]; then
  echo "ERROR: ${Z_CORR_PATH} not found"
  exit 1
fi

# must export this for flintstone
#export RUNTIME="3:59"

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
RUN_TIME=`date +"%Y%m%d_%H%M%S"`
JAR="/groups/flyem/data/render/lib/hot-knife-0.0.4-SNAPSHOT.jar"
CLASS=org.janelia.saalfeldlab.hotknife.SparkComputeCost

# /nrs/flyem/render/n5/Z0720_07m_BR/z_corr/Sec39/v1_acquire_trimmed_sp1___20210410_220552
Z_CORR_DATASET=$(echo "${Z_CORR_PATH}" | sed 's@.*\(/z_corr/.*\)@\1@')
COST_DATASET="$(echo "${Z_CORR_DATASET}" | sed 's@/z_corr/@/cost_new/@')_gauss_band_${BAND_SIZE}"
if [ "$FILTER_Y_OR_N" == "y" ]; then
  COST_DATASET="${COST_DATASET}_w_filter"
fi

if [[ -d ${N5_PATH}${COST_DATASET} ]]; then
  COST_DATASET="${COST_DATASET}__${RUN_TIME}"
fi

HEIGHT_FIELDS_DATASET=$(echo "${COST_DATASET}" | sed 's@/cost_new/@/heightfields/@')

ARGV="\
--inputN5Path=${N5_PATH} \
--inputN5Group=${Z_CORR_DATASET}/s0 \
--outputN5Path=${N5_PATH} \
--costN5Group=${COST_DATASET} \
--firstStepScaleNumber=1 \
--costSteps=6,1,6 \
--costSteps=3,1,3 \
--costSteps=3,1,3 \
--costSteps=3,1,3 \
--costSteps=3,1,3 \
--costSteps=1,4,1 \
--costSteps=1,4,1 \
--costSteps=1,4,1 \
--axisMode=2 \
--bandSize=${BAND_SIZE} \
--maxSlope=0.04 \
--slopeCorrBandFactor=5.5 \
--slopeCorrXRange=20 \
--downsampleCostX \
--surfaceN5Output=${HEIGHT_FIELDS_DATASET} \
--surfaceFirstScale=8
--surfaceLastScale=1 \
--surfaceMaxDeltaZ=0.25 \
--surfaceInitMaxDeltaZ=0.3 \
--surfaceMinDistance=2000 \
--surfaceMaxDistance=4000"

if [ "$FILTER_Y_OR_N" == "y" ]; then
  ARGV="${ARGV} --normalizeImage"
fi

COST_DIR="${N5_PATH}${COST_DATASET}"
mkdir -p ${COST_DIR}
echo "${ARGV}" > ${COST_DIR}/args.txt

LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/zcorr_to_cost.${RUN_TIME}.out"

mkdir -p ${LOG_DIR}

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo """Running with arguments:
${ARGV}
"""
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGV

  echo """Cost n5 volume is:
  -i ${N5_PATH} -d ${COST_DATASET}
"""
} 2>&1 | tee -a ${LOG_FILE}
