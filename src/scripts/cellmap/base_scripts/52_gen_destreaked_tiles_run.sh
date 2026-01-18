#!/bin/bash

set -e

#-----------------------------------------------------------------------------
# This script generates a batched LSF job array to de-streak a stack of tiles
# using a filter list specified in a json file.
#
# The script prompts the user to select the align stack to de-streak and the render type to use.

ABSOLUTE_SCRIPT=$(readlink -m "${0}")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}"/00_config.sh

if (( $# < 1 )); then
  echo "USAGE $0 <filter list path>     e.g. destreak_filter.json"
  exit 1
fi

FILTER_LIST_PATH=$(readlink -m "${1}")

IS_VALID_FILTER_LIST=$(${JQ} '
  has("namedFilterSpecLists")                       # ensure the top-level key exists
  and (.namedFilterSpecLists | keys | length == 1)  # ensure exactly one subkey
' "${FILTER_LIST_PATH}")

if [ "${IS_VALID_FILTER_LIST}" != "true" ]; then
  echo "
ERROR: ${FILTER_LIST_PATH} does not contain exactly one namedFilterSpecLists element

It should look like this:
  {
    \"namedFilterSpecLists\" : {
      \"any-name\" : [
        {
          \"className\" : \"org.janelia.alignment.destreak.LocalSmoothMaskStreakCorrector\",
          \"parameters\" : {
            \"dataString\" : \"4621,8190,35,8,0.0,10,10.0,0.05\"
          }
        }
      ]
    }
  }
"
  exit 1
fi

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
PROJECT_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}"
RUN_TIME=$(date +"%Y%m%d_%H%M%S")

#--------------------------------------------------
# validate that the 16-bit raw data exists

RAW_ROOT_DIR="${RENDER_NRS_ROOT}/raw"
unset RAW_DATA_FOUND_ON_NRS
if [ ! -d "${RAW_ROOT_DIR}" ]; then
  echo "ERROR: ${RAW_ROOT_DIR} does not exist"
  exit 1
elif ! compgen -G "${RAW_ROOT_DIR}/Merlin*/" > /dev/null; then
  echo "ERROR: no Merlin directories found under ${RAW_ROOT_DIR}"
  exit 1
fi

#--------------------------------------------------
# select the align stack to de-streak

mapfile -t STACK_NAMES < <(curl -s "${PROJECT_URL}/stackIds" | ${JQ} -r '.[].stack | select(contains("align"))' | sort)

echo "Which align stack should be the basis for the 16-bit stack?"
select STACK_NAME in "${STACK_NAMES[@]}"; do
  if [ -n "${STACK_NAME}" ]; then
    break
  else
    echo "Invalid selection, try again."
  fi
done

# override ALIGN_STACK loaded from the config file
ALIGN_STACK="${STACK_NAME}"
DESTREAK_STACK="${ALIGN_STACK}_destreak"

#--------------------------------------------------
# select the render type

RENDER_TYPES=("EIGHT_BIT" "SIXTEEN_BIT" "ARGB")

echo "Which render type should be used?"
select RENDER_TYPE in "${RENDER_TYPES[@]}"; do
  if [ -n "${RENDER_TYPE}" ]; then
    break
  else
    echo "Invalid selection, try again."
  fi
done

#--------------------------------------------------
# set up the output directory

OUTPUT_DIR="${RENDER_NRS_ROOT}/tiles_destreak"
mkdir -p "${OUTPUT_DIR}"
chmod 2775 "${OUTPUT_DIR}"

#--------------------------------------------------
# build the job array run script and arguments

BASE_DATA_URL="http://${SERVICE_HOST}/render-ws/v1"
ARGV="--baseDataUrl ${BASE_DATA_URL} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${ALIGN_STACK}"
ARGV="${ARGV} --rootDirectory ${OUTPUT_DIR}"
ARGV="${ARGV} --runTimestamp ${RUN_TIME}"
ARGV="${ARGV} --scale 1.0 --format png"
ARGV="${ARGV} --excludeMask --excludeAllTransforms"
ARGV="${ARGV} --filterListPath ${FILTER_LIST_PATH}"
#ARGV="${ARGV} --tileIdPattern .*0-0-.*"
ARGV="${ARGV} --hackStack ${DESTREAK_STACK}"
ARGV="${ARGV} --renderType ${RENDER_TYPE}"
ARGV="${ARGV} --z"

#Z_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ALIGN_STACK}/zValues?minZ=${MIN_Z}&maxZ=${MAX_Z}"
Z_URL="${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${ALIGN_STACK}/zValues"

JAVA_CLASS="org.janelia.render.client.tile.RenderTilesClient"
#export MEMORY="13G" # 15G allocated per slot
#export MAX_RUNNING_TASKS="150"

# 1 z with 3 images (e.g. 0-.-2 pattern) takes 3 minutes, so 10 z per batch should take about 30 minutes per job
Z_PER_BATCH=10

# cap job array at 2000 concurrent tasks
export MAX_RUNNING_TASKS=2000

# limit jobs to 1 slot and 10 days hard runtime
export BATCH_AND_QUEUE_PARAMETERS="-n 1 -W 14400"

# complete stack if check_logs is successful
export POST_CHECK_COMMAND="curl -v -X PUT \"${BASE_DATA_URL}/owner/${RENDER_OWNER}/project/${RENDER_PROJECT}/stack/${DESTREAK_STACK}/state/COMPLETE\""

# shellcheck disable=SC2086
/groups/flyTEM/flyTEM/render/pipeline/bin/gen_batched_run_lsf.sh "${Z_URL}" ${JAVA_CLASS} ${SCRIPT_DIR} ${Z_PER_BATCH} ${ARGV}