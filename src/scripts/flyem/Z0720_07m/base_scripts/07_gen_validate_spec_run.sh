#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

ARGV="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1 --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ACQUIRE_STACK}"
ARGV="${ARGV} --validatorClass org.janelia.alignment.spec.validator.TemTileSpecValidator"
ARGV="${ARGV} --validatorData minCoordinate:-999999,maxCoordinate:999999,minSize:1000,maxSize:99999"

Z_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_STACK}/zValues"

JAVA_CLASS="org.janelia.render.client.ValidateTilesClient"
#export MEMORY="13G" # 15G allocated per slot
#export MAX_RUNNING_TASKS="150"

# 3000 z per batch for stack with 3 tiles per layer takes about 15 seconds per job
export Z_PER_BATCH=3000

/groups/flyTEM/flyTEM/render/pipeline/bin/gen_z_based_run_lsf.sh "${Z_URL}" ${JAVA_CLASS} ${SCRIPT_DIR} ${ARGV}
