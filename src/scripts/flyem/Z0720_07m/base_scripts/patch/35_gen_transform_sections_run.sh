#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/../00_config.sh

MIN_Z="39584"
MAX_Z="39584"
ONLY_INCLUDE_TILES_IN_BOUNDS="--minX 18000 --maxX 25000 --minY -10000 --maxY 10000"
TRANSLATE_ARGS="-17778,0"

# if there are other layers to correct,
# edit job_parameters.txt for other z values and
# edit bsub-array.sh to change number of jobs

#--------------------------------------------------
BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
ARGV="--baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ACQUIRE_TRIMMED_STACK}"
ARGV="${ARGV} --transformId MOVE_RESTART_${MIN_Z} --transformClass mpicbg.trakem2.transform.TranslationModel2D "
ARGV="${ARGV} --transformData ${TRANSLATE_ARGS} --transformApplicationMethod PRE_CONCATENATE_LAST"
ARGV="${ARGV} ${ONLY_INCLUDE_TILES_IN_BOUNDS}"

Z_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_TRIMMED_STACK}/zValues?minZ=${MIN_Z}&maxZ=${MAX_Z}"

JAVA_CLASS="org.janelia.render.client.TransformSectionClient"
#export MEMORY="13G" # 15G allocated per slot
#export MAX_RUNNING_TASKS="150"

# 3000 z per batch for stack with 3 tiles per layer takes about 15 seconds per job
Z_PER_BATCH=3000

# complete stack if check_logs is successful
export POST_CHECK_COMMAND="curl -v -X PUT \"${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_TRIMMED_STACK}/state/COMPLETE\""

/groups/flyTEM/flyTEM/render/pipeline/bin/gen_batched_run_lsf.sh "${Z_URL}" ${JAVA_CLASS} ${SCRIPT_DIR} ${Z_PER_BATCH} ${ARGV}