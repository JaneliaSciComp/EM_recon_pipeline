#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

# root directory for all acquisition tile mipmaps
MIPMAP_ROOT_DIR="/nrs/flyem/render/mipmaps"

if [[ ! -d ${MIPMAP_ROOT_DIR} ]]; then
  mkdir -p ${MIPMAP_ROOT_DIR}
  chmod 2775 ${MIPMAP_ROOT_DIR}
fi

ARGV="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1 --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ACQUIRE_STACK}"
ARGV="${ARGV} --rootDirectory ${MIPMAP_ROOT_DIR} --maxLevel 9"

Z_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_STACK}/zValues"

JAVA_CLASS="org.janelia.render.client.MipmapClient"
export MEMORY="13G" # 15G allocated per slot
export MAX_RUNNING_TASKS="1000"

# 25 z per batch for stack with 4 tiles per layer takes about 4 minutes per job
export Z_PER_BATCH=25

/groups/flyTEM/flyTEM/render/pipeline/bin/gen_z_based_run_lsf.sh "${Z_URL}" ${JAVA_CLASS} ${SCRIPT_DIR} ${ARGV}
