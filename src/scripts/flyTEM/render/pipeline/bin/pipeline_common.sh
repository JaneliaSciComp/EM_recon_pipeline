#!/bin/bash

RENDER_PIPELINE_BIN="/groups/flyTEM/flyTEM/render/pipeline/bin"
TEM_SERVICES_IP="10.40.3.162"
BASE_DATA_URL="http://${TEM_SERVICES_IP}:8080/render-ws/v1"
VALIDATOR_PARAMS="--validatorClass org.janelia.alignment.spec.validator.TemTileSpecValidator --validatorData \"minCoordinate:-800000,maxCoordinate:800000,minSize:500,maxSize:5000\""

# expects global USAGE_MESSAGE to be defined 
function exitWithErrorAndUsage() {
  local ERROR_MESSAGE="$1"
  echo """
ERROR: ${ERROR_MESSAGE}

USAGE: ${USAGE_MESSAGE}

"""
  exit 1  
}

function ensureDirectoryExists() {
  local DIR="$1"
  local CONTEXT="$2"
  if [[ ! -d ${DIR} ]]; then
    exitWithErrorAndUsage "cannot find ${CONTEXT} directory ${DIR}"
  fi
}

function getTimestamp() {
  local DATE=`date +"%Y%m%d_%H%M%S"`
  local NS=`date +"%N"`
  local NS_WITHOUT_LEADING_ZERO="$(( 10#${NS} ))"
  local MS="$(( NS_WITHOUT_LEADING_ZERO / 1000000 ))"
  echo "${DATE}_${MS}"
}
  
function getRunDirectory() {
  local CONTEXT="$1"
  local TS=`getTimestamp`
  echo "run_${TS}_${CONTEXT}"
}
  
function createLogDirectory() {
  local DIR="${1}/logs"
  mkdir -p ${DIR}
  ensureDirectoryExists "${DIR}" "log"
  echo "${DIR}"
}

function parseValuesFromJsonArray() {
  URL="$1"
  VALUES=`curl -s ${URL} | sed '
    s/,/ /g
    s/\[//g
    s/\]//g
  '`
  echo ${VALUES}
}

