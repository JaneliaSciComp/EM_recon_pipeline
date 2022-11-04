#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

if (( $# != 1 )); then
  echo "USAGE: $0 <stack>"
  exit 1
fi

STACK="$1"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG="${LOG_DIR}/unconnected_edges.${STACK}.$(date +"%Y%m%d_%H%M%S").log"

mkdir -p ${LOG_DIR}

ARGS="org.janelia.render.client.UnconnectedTileEdgesClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${STACK}"
ARGS="${ARGS} --matchCollection ${MATCH_COLLECTION}"
ARGS="${ARGS} --maxUnconnectedLayers 50"

echo """
Unconnected edge data will be written to:
  ${LOG}

Be patient, this could take a few minutes ...
"""

${RENDER_CLIENT_SCRIPT} 1G ${ARGS} > ${LOG}

grep "findUnconnectedEdges: edge" ${LOG} | sed 's/.*findUnconnectedEdges: //'
