#!/bin/bash

set -e

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

#--------------------------------------------------
# select the align stack to straighten

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
PROJECT_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}"

mapfile -t STACK_NAMES < <(curl -s "${PROJECT_URL}/stackIds" | ${JQ} -r '.[].stack | select(contains("align"))' | sort)

echo "Which align stack should be straightened?"
select STACK in "${STACK_NAMES[@]}"; do
  if [ -n "${STACK}" ]; then
    break
  else
    echo "Invalid selection, try again."
  fi
done

STRAIGHT_STACK="${STACK}_straight"

#-----------------------------------------------------------
ARGS="org.janelia.render.client.StackStraighteningClient"
ARGS="${ARGS} --baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --stack ${STACK} --targetStack ${STRAIGHT_STACK}"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-java-standalone.jar"
STRAIGHTEN_JOB="${RENDER_PROJECT}_${STRAIGHT_STACK}"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/straight-$(date +"%Y%m%d_%H%M%S").log"

mkdir -p "${LOG_DIR}"

echo "
Launching job with arguments:
  ${ARGS}

Job should finish quickly (< 5 minutes).

To see job progress, use:
  tail -f ${LOG_FILE}
"

# shellcheck disable=SC2086
bsub -P "${BILL_TO}" -J "${STRAIGHTEN_JOB}" -n1 -W 59 -o "${LOG_FILE}" ${RENDER_CLIENT_SCRIPT} 13G ${ARGS}