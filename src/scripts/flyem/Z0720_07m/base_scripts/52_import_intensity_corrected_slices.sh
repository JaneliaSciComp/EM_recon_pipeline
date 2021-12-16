#!/bin/bash

set -e

ABSOLUTE_SCRIPT=`readlink -m $0`
SCRIPT_DIR=`dirname ${ABSOLUTE_SCRIPT}`
source ${SCRIPT_DIR}/00_config.sh

SCAPES_BASE_DIR="${SCAPES_ROOT_DIR}/${RENDER_OWNER}/${RENDER_PROJECT}/${ALIGN_STACK}"

if [[ ! -d ${SCAPES_BASE_DIR} ]]; then
  echo "ERROR: ${SCAPES_BASE_DIR} not found"
  exit 1
fi
shopt -s nullglob
DIRS=(${SCAPES_BASE_DIR}/intensity_adjusted_scapes_*/)
shopt -u nullglob # Turn off nullglob to make sure it doesn't interfere with anything later
DIR_COUNT=${#DIRS[@]}
if (( DIR_COUNT == 0 )); then
  echo "ERROR: no directories found in ${SCAPES_BASE_DIR}"
  exit 1
elif (( DIR_COUNT == 1 )); then
  SCAPES_DIR=${DIRS[0]}
else
  PS3="Choose a source directory: "
  select SCAPES_DIR in `echo ${DIRS[@]}`; do
    break
  done
fi

SLICE_URL_FORMAT="${SCAPES_DIR}z.%05d.png"

LOG_DIR="${SCRIPT_DIR}/logs"

mkdir -p ${LOG_DIR}

ARGS="org.janelia.render.client.ImportSlicesClient"
ARGS="${ARGS} --baseDataUrl http://${SERVICE_HOST}/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${INTENSITY_CORRECTED_STACK}"
ARGS="${ARGS} --basisStack ${ALIGN_STACK}"
ARGS="${ARGS} --sliceUrlFormat ${SLICE_URL_FORMAT}"
#ARGS="${ARGS} --sliceZOffset -1"
ARGS="${ARGS} --completeStackAfterImport"
  
${RENDER_CLIENT_SCRIPT} ${RENDER_CLIENT_HEAP} ${ARGS} | tee -a ${LOG_DIR}/import_ic_slices.log
