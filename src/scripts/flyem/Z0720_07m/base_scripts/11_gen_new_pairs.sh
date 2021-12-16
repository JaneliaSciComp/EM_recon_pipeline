#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

for RUN_TYPE in montage cross; do

echo """
------------------------------------------------------------------------
Setting up ${RUN_TYPE} pairs (log is captured so wait for results) ...
"""

PASS="1"

#export RENDER_WS_CLIENT_JAR="/groups/flyTEM/flyTEM/render/lib/gd/render-ws-java-client-2.1.0-SNAPSHOT-standalone.jar"

if [[ "${RUN_TYPE}" == "montage" ]]; then
  PASS_ARGS="${MONTAGE_PAIR_ARGS}"
  PASS_PAIR_SECONDS="${MONTAGE_PASS_PAIR_SECONDS}"
else
  PASS_ARGS="${CROSS_PAIR_ARGS}"
  PASS_PAIR_SECONDS="${CROSS_PASS_PAIR_SECONDS}"
fi

# Try to allocate 5 minutes of match derivation work to each file.
MAX_PAIRS_PER_FILE=$(( 5 * 60 / PASS_PAIR_SECONDS ))

LOG_DIR="${SCRIPT_DIR}/logs"
PAIR_GEN_LOG="${LOG_DIR}/tile_pairs-`date +"%Y%m%d_%H%M%S"`.log"
PAIRS_DIR="${SCRIPT_DIR}/pairs_${RUN_TYPE}"

mkdir -p ${LOG_DIR}
mkdir -p ${PAIRS_DIR}

ARGS="org.janelia.render.client.TilePairClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${LOCATION_STACK}"
ARGS="${ARGS} ${PASS_ARGS}"
#ARGS="${ARGS} --excludePairsInMatchCollection ${MATCH_COLLECTION}"
ARGS="${ARGS} --maxPairsPerFile ${MAX_PAIRS_PER_FILE}"
  
#PATCH_ARGS="${ARGS} --minZ ${MIN_Z} --maxZ ${MAX_Z} --toJson ${PAIRS_DIR}/tile_pairs_${RUN_TYPE}_${MIN_Z}_${MAX_Z}.json.gz"
PATCH_ARGS="${ARGS} --toJson ${PAIRS_DIR}/tile_pairs_${RUN_TYPE}.json.gz"
${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${PATCH_ARGS} 2>&1 1>>${PAIR_GEN_LOG}

OUTPUT_HEAD=`head -40 ${PAIR_GEN_LOG} | cut -c1-400`
OUTPUT_TAIL=`tail -10 ${PAIR_GEN_LOG} | cut -c1-400`

echo """
  MAX_PAIRS_PER_FILE was set to ${MAX_PAIRS_PER_FILE}

  Full pair generation output written to:
   ${PAIR_GEN_LOG}

  Abbreviated output is:

${OUTPUT_HEAD}
...
${OUTPUT_TAIL}
   
"""

done
