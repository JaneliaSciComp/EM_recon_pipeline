#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/../00_config.sh

if (( $# != 2 )); then
  echo "USAGE: $0 <project> <stack>"
  exit 1
fi

PROJECT="${1}"
STACK="${2}"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/copy_stacks.log"

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
JAVA_CLASS="org.janelia.render.client.CopyStackClient"

# ----------------------------------------------------------
ARGS="--baseDataUrl ${BASE_DATA_URL}"
ARGS="${ARGS} --owner hess_wafer_53d --project ${PROJECT} --fromStack ${STACK}"
ARGS="${ARGS} --toOwner ${RENDER_OWNER} --toProject ${PROJECT} --toStack ${STACK}"
ARGS="${ARGS} --includeTileIdsWithPattern _0000(05|06|09|10|11|14|15)_"
ARGS="${ARGS} --keepExisting --completeToStackAfterCopy"

${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${JAVA_CLASS} ${ARGS} | tee -a "${LOG_FILE}"
