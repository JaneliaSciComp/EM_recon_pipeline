#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# != 2 )); then
  echo "USAGE: $0 <project> <stack>    e.g. slab_000_to_009 s001_m239_align_no35"
  exit 1
fi

RENDER_PROJECT="${1}"
STACK="${2}"
TARGET_STACK="${STACK}_hayworth_ic"

LOG_DIR="${SCRIPT_DIR}/logs/hack_source"
LOG_FILE="${LOG_DIR}/run-${STACK}-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

ARGS="org.janelia.render.client.multisem.HackImageUrlPathClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --stack ${STACK} --targetStack ${TARGET_STACK}"
  
echo "running with:
  ${ARGS}

log file is:
  ${LOG_FILE}
"

# shellcheck disable=SC2086
${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${ARGS} 1>>${LOG_FILE} 2>&1
