#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/../00_config.sh

if [[ -z "${OLD_ACQUIRE_TRIMMED_STACK}" ]] || [[ "${OLD_ACQUIRE_TRIMMED_STACK}" == "TBD" ]]; then
  echo "ERROR: need to setup OLD_ACQUIRE_TRIMMED_STACK in config"
  exit 1
fi

FROM_STACK="${OLD_ACQUIRE_TRIMMED_STACK}"
TO_STACK="${ACQUIRE_TRIMMED_STACK}"

LAYERS_PER_BATCH="500"

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
Z_VALUES_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${FROM_STACK}/zValues"
JAVA_CLASS="org.janelia.render.client.CopyStackClient"

# ----------------------------------------------------------
ARGS="--baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --fromStack ${FROM_STACK} --toStack ${TO_STACK}"
#ARGS="${ARGS} --excludedColumnsJson ${SCRIPT_DIR}/excluded_columns.json"
ARGS="${ARGS} --keepExisting"
ARGS="${ARGS} --z"

# complete stack if check_logs is successful
export POST_CHECK_COMMAND="curl -v -X PUT \"${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${TO_STACK}/state/COMPLETE\""

# launch bsub after generation
export LAUNCH_BSUB="launch"

# USAGE_MESSAGE="${ABSOLUTE_SCRIPT} <values URL> <java client class> <work directory> <values per batch> <exclude file> <common client args>"
/groups/flyTEM/flyTEM/render/pipeline/bin/gen_batched_run_lsf.sh "${Z_VALUES_URL}" ${JAVA_CLASS} ${SCRIPT_DIR} ${LAYERS_PER_BATCH} ${ARGS}
