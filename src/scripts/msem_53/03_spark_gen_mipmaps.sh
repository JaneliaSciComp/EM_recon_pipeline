#!/bin/bash

set -e

umask 0002

ABSOLUTE_SCRIPT=$(readlink -m "$0")
SCRIPT_DIR=$(dirname "${ABSOLUTE_SCRIPT}")
source "${SCRIPT_DIR}/00_config.sh"

if (( $# < 1 )); then
  echo "USAGE $0 <number of nodes>

Two tiles can be processed each second, so a 2000 tile z-layer would take about 17 minutes.
With the standard 10+1 core worker, try to allocate one worker for every ten z.

Wafer 53:
- 402 slabs each with with 47 z layers; each scan took roughly 36 hours
- during scanning, use 402 / 10 = 41 workers => each scan is done in 17 minutes
- after scanning, use (402 * 47) / 10 = 1890 (too many workers), use 100 workers, done in 322 minutes (6 hours)

Wafers 56/57:
- 724 slabs each with 63 z layers
- during scanning, use 724 / 10 = 73 workers => each scan is done in 17 minutes

TODO: how much faster is processing when mipmaps already exist?
"
  exit 1
fi

N_NODES="${1}"

# Note: Spark executor setup with 11 cores per worker defined in 00_config.sh
JOB_LAUNCH_TIME=$(date +"%Y%m%d_%H%M%S")

ARGS="--baseDataUrl http://${SERVICE_HOST}/render-ws/v1 --owner ${RENDER_OWNER} --project ${RENDER_PROJECT}"
ARGS="${ARGS} --rootDirectory ${DATA_MIPMAP_DIR} --maxLevel ${MAX_MIPMAP_LEVEL}"
ARGS="${ARGS} --allStacksInAllProjects"

mkdir -p "${DATA_MIPMAP_DIR}"

#export RUNTIME="3:59"

#-----------------------------------------------------------
JAR="/groups/flyTEM/flyTEM/render/lib/current-spark-standalone.jar"
CLASS="org.janelia.render.client.spark.MipmapClient"

LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/mipmap-${JOB_LAUNCH_TIME}.log"

mkdir -p "${LOG_DIR}"

# use shell group to tee all output to log file
{
  echo "Running with arguments:
${ARGS}
"
  # shellcheck disable=SC2086
  /groups/flyTEM/flyTEM/render/spark/spark-janelia/flintstone.sh "${N_NODES}" ${JAR} ${CLASS} ${ARGS}
} 2>&1 | tee -a "${LOG_FILE}"