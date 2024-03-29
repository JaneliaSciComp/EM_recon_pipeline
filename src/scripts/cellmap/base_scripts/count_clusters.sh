#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 1 )); then
  echo "USAGE: $0 <stack> [generate excluded cells y|n]"
  exit 1
fi

STACK="$1"
GENERATE_EXCLUDED_CELLS="${2:-n}"

LOG_DIR="${SCRIPT_DIR}/logs"
COUNT_LOG="${LOG_DIR}/cluster_count.${STACK}.log"

mkdir -p "${LOG_DIR}"

ARGS="org.janelia.render.client.ClusterCountClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${STACK}"
ARGS="${ARGS} --matchCollection ${MATCH_COLLECTION}"
ARGS="${ARGS} --maxSmallClusterSize 0 --includeMatchesOutsideGroup --maxLayersPerBatch 1000 --maxOverlapLayers 6"
ARGS="${ARGS} --maxLayersForUnconnectedEdge 50"

echo "
Connected tile cluster counts will be written to:
  ${COUNT_LOG}

Be patient, this could take a few minutes ...
"

${RENDER_CLIENT_SCRIPT} 1G ${ARGS} > "${COUNT_LOG}"

if [ "${GENERATE_EXCLUDED_CELLS}" = "y" ]; then

  JSON_FILE="${SCRIPT_DIR}/excluded_cells.json"

  echo "Parsing ${COUNT_LOG} to create:
  ${JSON_FILE}
"

  "${SCRIPT_DIR}"/gen_excluded_cells.py "${COUNT_LOG}" > "${JSON_FILE}"

else

  tail -15 "${COUNT_LOG}"

fi
