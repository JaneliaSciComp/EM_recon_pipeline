#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

# make sure trimmed stack is complete
COMPLETE_URL="http://${SERVICE_HOST}/render-ws/v1/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ACQUIRE_TRIMMED_STACK}/state/COMPLETE"
curl -v -X PUT "${COMPLETE_URL}"

"${SCRIPT_DIR}"/count_clusters.sh "${ACQUIRE_TRIMMED_STACK}"
