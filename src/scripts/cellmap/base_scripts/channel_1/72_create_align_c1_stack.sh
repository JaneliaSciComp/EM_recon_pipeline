#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# != 1 )); then
  echo "USAGE $0 <align stack c0>     e.g. v2_acquire_align"
  exit 1
fi

ALIGN_STACK_C_ZERO="$1"
ALIGN_STACK_C_ONE="${ALIGN_STACK_C_ZERO}_channel_1"

LOG_DIR="${SCRIPT_DIR}/logs"
CURRENT_TIME=$(date +"%Y%m%d_%H%M%S")
CREATE_STACK_LOG="${LOG_DIR}/create-align-c1-${CURRENT_TIME}.log"

mkdir -p "${LOG_DIR}"

ARGS="org.janelia.render.client.multisem.HackImageUrlPathClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --stack ${ALIGN_STACK_C_ZERO} --targetStack ${ALIGN_STACK_C_ONE}"
ARGS="${ARGS} --transformationType FIBSEM_CHANNEL_ONE"

${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${ARGS} 1>>${CREATE_STACK_LOG} 2>&1
