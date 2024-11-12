#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 2 )); then
  echo "USAGE $0 <number of nodes> <match run JSON file>
"
  exit 1
fi

N_NODES="${1}"
MATCH_RUN_JSON="${2}"

if [ ! -f "${MATCH_RUN_JSON}" ]; then
  echo "ERROR: ${MATCH_RUN_JSON} not found!"
  exit 1
fi

# Note: Spark executor setup with 11 cores per worker defined in 00_config.sh
JOB_LAUNCH_TIME=$(date +"%Y%m%d_%H%M%S")

ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1 --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
#ARGS="${ARGS} --allStacksInAllProjects"
ARGS="${ARGS} --allStacksInProject"
ARGS="${ARGS} --matchRunJson ${MATCH_RUN_JSON}"
ARGS="${ARGS} --maxFeatureSourceCacheGb 10 --gdMaxPeakCacheGb 10"

#export RUNTIME="3:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.match.MultiStagePointMatchClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/match-${JOB_LAUNCH_TIME}.log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
{
  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh "${N_NODES}" ${JAR} ${CLASS} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"