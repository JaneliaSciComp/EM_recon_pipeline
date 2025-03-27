#!/bin/bash

if (( $# != 5 )); then
  echo "
Usage:    $0 <render-ws-internal-ip> <render-project> <render-stack> <max-z> <number-spark-exec-instances>

          number-spark-exec-instances must be at least 2

Examples: $0 10.150.0.5 w60_serial_360_to_369 w60_s360_r00_d20_gc_align 76 100
  "
  exit 1
fi

RENDER_WS_IP="${1}"
RENDER_PROJECT="${2}"
STACK="${3}"
MAX_Z="${4}"
SPARK_EXEC_INSTANCES="${5}"

if (( SPARK_EXEC_INSTANCES < 2 )); then
  echo "ERROR: must request at least 2 spark executors"
  exit 1
fi

SPARK_EXEC_CORES=4 # must be 4, 8, or 16

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

RENDER_OWNER="hess_wafers_60_61"
N5_PATH="gs://janelia-spark-test/hess_wafers_60_61_export"          # /nrs/hess/data/hess_wafers_60_61/export/hess_wafers_60_61.n5
N5_DATASET="/render/${RENDER_PROJECT}/${STACK}___${RUN_TIMESTAMP}"  # /render/w60_serial_360_to_369/w60_s360_r00_d20_gc_align___20250320_131555

# For standard compute tier and spark runtime, total of spark.memory.offHeap.size,
# spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
# Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.

SINGLE_CORE_MB=6700 # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424
SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="spark.default.parallelism=240,spark.executor.instances=${SPARK_EXEC_INSTANCES}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}mb"

# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-1.1
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="1.1"

GS_JAR_URL="gs://janelia-spark-test/library/render-ws-spark-client-4.3.0-SNAPSHOT-standalone.jar"

CLASS="org.janelia.render.client.spark.n5.N5Client"

ARGS="--baseDataUrl http://${RENDER_WS_IP}:8080/render-ws/v1"
ARGS="${ARGS} --owner ${RENDER_OWNER} --project ${RENDER_PROJECT} --stack ${STACK}"
ARGS="${ARGS} --n5Path ${N5_PATH} "
ARGS="${ARGS} --n5Dataset ${N5_DATASET}"
ARGS="${ARGS} --tileWidth 2048 --tileHeight 2048 --blockSize 1024,1024,${MAX_Z} --factors 2,2,1"
ARGS="${ARGS} --minZ 1 --maxZ ${MAX_Z}"
# ARGS="${ARGS} --minX 84000 --maxX 94000 --minY 70000 --maxY 80000"

echo "
Running gcloud dataproc batches submit spark with:
  --jars=${GS_JAR_URL}
  --class=${CLASS}
  --properties=${SPARK_PROPS}
  ${ARGS}
"

# use --async to return immediately
gcloud dataproc batches submit spark \
  --region=us-east4 \
  --jars=${GS_JAR_URL} \
  --class=${CLASS} \
  --batch=render-n5-export-"${RUN_TIMESTAMP}" \
  --version=${SPARK_VERSION} \
  --properties="${SPARK_PROPS}" \
  --async \
  -- \
  ${ARGS}
