#!/bin/bash

set -e

#-----------------------------------------------------------------------------
# This script creates a 16-bit stack from the raw data of an align stack.
#
# It assumes that the raw h5s have been copied from nearline to nrs so that export process can read them.
# Usually Globus ( https://app.globus.org/ ) is used to copy the data.
# A Globus copy of 53T from /nearline/cellmap/data/jrc_mus-cerebellum-2 to /nrs took 3 hours 37 minutes.

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
PROJECT_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}"
RUN_TIME=$(date +"%Y%m%d_%H%M%S")

#--------------------------------------------------
# validate that the 16-bit raw data exists

RAW_ROOT_DIR="${RENDER_NRS_ROOT}/raw"

if [ ! -d "${RAW_ROOT_DIR}" ]; then
  echo "ERROR: ${RAW_ROOT_DIR} does not exist"
  exit 1
elif ! compgen -G "${RAW_ROOT_DIR}/Merlin*/" > /dev/null; then
  echo "ERROR: no Merlin directories found under ${RAW_ROOT_DIR}"
  exit 1
fi

#--------------------------------------------------
# select the align stack to "convert" to 16-bit

mapfile -t STACK_NAMES < <(curl -s "${PROJECT_URL}/stackIds" | ${JQ} -r '.[].stack | select(contains("align"))' | sort)

echo "Which align stack should be de-streaked?"
select STACK_NAME in "${STACK_NAMES[@]}"; do
  if [ -n "${STACK_NAME}" ]; then
    break
  else
    echo "Invalid selection, try again."
  fi
done

# override ALIGN_STACK loaded from the config file
ALIGN_STACK="${STACK_NAME}"
SIXTEEN_BIT_STACK="${ALIGN_STACK}_16bit"

#--------------------------------------------------
# setup and launch the LSF job to convert to 16-bit

LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/convert_to_16bit.${RUN_TIME}.log"
mkdir -p "${LOG_DIR}"

BSUB_LIMIT=1440 # limit job to 1 day of runtime
JAVA_HEAP_SIZE="13G"
JAVA_CLASS="org.janelia.render.client.stack.Create16BitH5StackClient"

ARGS="${ARGS} --baseDataUrl ${BASE_DATA_URL}"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --alignStack ${ALIGN_STACK} --rawStack ${SIXTEEN_BIT_STACK}"
ARGS="${ARGS} --rawRootDirectory ${RAW_ROOT_DIR}"
# ARGS="${ARGS} --z 5000 9740"
ARGS="${ARGS} --completeRawStack"

# shellcheck disable=SC2086
bsub -P "${BILL_TO}" -n1 -W ${BSUB_LIMIT} -o "${LOG_FILE}" \
  "${RENDER_CLIENT_SCRIPT}" ${JAVA_HEAP_SIZE} "${JAVA_CLASS}" ${ARGS}

echo "
To see progress, run:
  tail -f ${LOG_FILE}
"