#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

if (( $# < 2 )); then
  echo "USAGE $0 <number of nodes> <Zcoords.txt>"
  exit 1
fi

N_NODES="${1}"        # 4, 10, 20
Z_COORDS_FILE="${2}"

if [[ ! -f ${Z_COORDS_FILE} ]]; then
  echo "ERROR: ${Z_COORDS_FILE} not found"
  exit 1
fi

RUN_TIME=`date +"%Y%m%d_%H%M%S"`

ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${INTENSITY_CORRECTED_STACK}"
ARGS="${ARGS} --n5Path ${N5_PATH}"
ARGS="${ARGS} --n5Dataset /z_corr/${RENDER_PROJECT}/${INTENSITY_CORRECTED_STACK}___${RUN_TIME}"
ARGS="${ARGS} --tileWidth 4096 --tileHeight 4096 --blockSize 128,128,64 --factors 2,2,2"
ARGS="${ARGS} --z_coords ${Z_COORDS_FILE}"

#-----------------------------------------------------------
# Spark executor setup with 11 cores per worker ...

export N_EXECUTORS_PER_NODE=2 # 6
export N_CORES_PER_EXECUTOR=5 # 5
# To distribute work evenly, recommended number of tasks/partitions is 3 times the number of cores.
#N_TASKS_PER_EXECUTOR_CORE=3
export N_OVERHEAD_CORES_PER_WORKER=1
#N_CORES_PER_WORKER=$(( (N_EXECUTORS_PER_NODE * N_CORES_PER_EXECUTOR) + N_OVERHEAD_CORES_PER_WORKER ))
export N_CORES_DRIVER=1

# must export this for flintstone
export LSF_PROJECT="flyem"
export RUNTIME="3:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.n5.N5Client"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/gen_n5.log"

mkdir -p ${LOG_DIR}

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo """Running with arguments:
${ARGS}
"""
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS

echo """
To get n5_view.sh command:
  grep n5_view 04-driver.log
"""

} 2>&1 | tee -a ${LOG_FILE}
