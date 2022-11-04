#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

FROM_STACK="${ACQUIRE_STACK}"
TO_STACK="${ACQUIRE_TRIMMED_STACK}"

LAYERS_PER_BATCH="500"

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
Z_VALUES_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${FROM_STACK}/zValues"
JAVA_CLASS="org.janelia.render.client.CopyStackClient"

# ----------------------------------------------------------
ARGS="--baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --fromStack ${FROM_STACK} --toStack ${TO_STACK}"
ARGS="${ARGS} --excludedCellsJson ${SCRIPT_DIR}/excluded_cells.json"
ARGS="${ARGS} --keepExisting"
ARGS="${ARGS} --z"

# complete stack amd count clusters if check_logs is successful
export POST_CHECK_COMMAND="${SCRIPT_DIR}/23_count_trimmed_clusters.sh"

# launch bsub after generation
export LAUNCH_BSUB="launch"

# USAGE_MESSAGE="${ABSOLUTE_SCRIPT} <values URL> <java client class> <work directory> <values per batch> <exclude file> <common client args>"
/groups/flyTEM/flyTEM/render/pipeline/bin/gen_batched_run_lsf.sh "${Z_VALUES_URL}" ${JAVA_CLASS} ${SCRIPT_DIR} ${LAYERS_PER_BATCH} ${ARGS}