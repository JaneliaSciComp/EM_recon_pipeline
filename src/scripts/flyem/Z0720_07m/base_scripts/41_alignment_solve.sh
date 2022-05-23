#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

if (( $# < 1 )); then
  echo "USAGE $0 <number of nodes> (e.g. 18)"
  exit 1
fi

N_NODES="${1}"        # 18

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
ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --stack ${ACQUIRE_TRIMMED_STACK}"
ARGS="${ARGS} --targetStack ${ALIGN_STACK}"
ARGS="${ARGS} --matchCollection ${MATCH_COLLECTION}"
ARGS="${ARGS} --maxNumMatches 0"
ARGS="${ARGS} --completeTargetStack"
ARGS="${ARGS} --blockSize 500"
ARGS="${ARGS} --blockOptimizerLambdasRigid 1.0,1.0,0.9,0.3,0.01"
ARGS="${ARGS} --blockOptimizerLambdasTranslation 1.0,0.0,0.0,0.0,0.0"
ARGS="${ARGS} --blockOptimizerIterations 1000,1000,500,250,250"
ARGS="${ARGS} --blockMaxPlateauWidth 250,250,150,100,100"
ARGS="${ARGS} --maxPlateauWidthGlobal 50"
ARGS="${ARGS} --maxIterationsGlobal 10000"
ARGS="${ARGS} --dynamicLambdaFactor 0.0"
ARGS="${ARGS} --threadsWorker 1"
ARGS="${ARGS} --threadsGlobal ${N_CORES_DRIVER}"
#ARGS="${ARGS} --customSolveClass org.janelia.render.client.solver.custom.SolveSetFactoryBRSec34"

                            
# --noStitching
# --minZ 1 --maxZ 38068
# --serializerDirectory .
# --serializeMatches

# must export this for flintstone
export RUNTIME="3:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.solver.DistributedSolveSpark"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/solve-`date +"%Y%m%d_%H%M%S"`.log"

mkdir -p ${LOG_DIR}

#export SPARK_JANELIA_ARGS="--consolidate_logs"

# use shell group to tee all output to log file
{

  echo """Running with arguments:
${ARGS}
"""
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh $N_NODES $JAR $CLASS $ARGS
} 2>&1 | tee -a ${LOG_FILE}

SHUTDOWN_JOB_ID=$(awk '/PEND.*_sd/ {print $1}' ${LOG_FILE})

if (( SHUTDOWN_JOB_ID > 1234 )); then
  echo "Scheduling z correction derivation job upon completion of solve job ${SHUTDOWN_JOB_ID}"
  echo

  bsub -P ${BILL_TO} -J ${RENDER_PROJECT}_launch_z_corr -w "ended(${SHUTDOWN_JOB_ID})" -n1 -W 59 ${SCRIPT_DIR}/42_gen_z_corr_run.sh launch
fi