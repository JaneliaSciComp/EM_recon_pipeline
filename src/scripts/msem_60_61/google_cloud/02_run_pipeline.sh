#!/bin/bash

if (( $# != 4 )); then
  echo "
Usage:    $0 <render-ws-internal-ip> <pipeline-json-rel-path> <number-spark-exec-instances> <number-spark-exec-cores>

          number-spark-exec-instances must be at least 2
          number-spark-exec-cores must be 4, 8, or 16

Examples: $0 10.150.0.12 01_match/pipe.01.360.match.json 16 4
          $0 10.150.0.84 02_align/pipe.02.360.align.json 2 16
  "
  exit 1
fi

RENDER_WS_IP="${1}"
PIPELINE_JSON_REL_PATH="${2}"
SPARK_EXEC_INSTANCES="${3}"
SPARK_EXEC_CORES=${4}

if (( SPARK_EXEC_INSTANCES < 2 )); then
  echo "ERROR: must request at least 2 spark executors"
  exit 1
fi

if (( SPARK_EXEC_CORES != 4 && SPARK_EXEC_CORES != 8 && SPARK_EXEC_CORES != 16 )); then
  echo "ERROR: number of spark executor cores must be 4, 8, or 16"
  exit 1
fi

# For standard compute tier and spark runtime, total of spark.memory.offHeap.size,
# spark.executor.memory and spark.executor.memoryOverhead must be between 1024mb and 7424mb per core.
# Note that if not set, spark.executor.memoryOverhead defaults to 0.10 of spark.executor.memory.

SINGLE_CORE_MB=6700 # leave room for spark.executor.memoryOverhead, 6700 + 670 = 7370 < 7424
SPARK_EXEC_MEMORY_MB=$(( SPARK_EXEC_CORES * SINGLE_CORE_MB ))

SPARK_PROPS="spark.default.parallelism=240,spark.executor.instances=${SPARK_EXEC_INSTANCES}"
SPARK_PROPS="${SPARK_PROPS},spark.executor.cores=${SPARK_EXEC_CORES},spark.executor.memory=${SPARK_EXEC_MEMORY_MB}mb"

RUN_TIMESTAMP=$(date +"%Y%m%d-%H%M%S")

# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/spark-runtime-1.1
# see https://cloud.google.com/dataproc-serverless/docs/concepts/versions/dataproc-serverless-versions
SPARK_VERSION="1.1"

GS_JAR_URL="gs://janelia-spark-test/library/render-ws-spark-client-4.3.0-SNAPSHOT-standalone.jar"
GS_PIPELINE_JSON_DIR_URL="https://storage.googleapis.com/janelia-spark-test/library/pipeline_json"

echo "
Running gcloud dataproc batches submit spark with:
  --jars=${GS_JAR_URL}
  --properties=${SPARK_PROPS}
  --baseDataUrl http://${RENDER_WS_IP}:8080/render-ws/v1
  --pipelineJson ${GS_PIPELINE_JSON_DIR_URL}/${PIPELINE_JSON_REL_PATH}
"

# use --async to return immediately
gcloud dataproc batches submit spark \
  --region=us-east4 \
  --jars=${GS_JAR_URL} \
  --class=org.janelia.render.client.spark.pipeline.AlignmentPipelineClient \
  --batch=render-alignment-pipeline-"${RUN_TIMESTAMP}" \
  --version=${SPARK_VERSION} \
  --properties="${SPARK_PROPS}" \
  --async \
  -- \
  --baseDataUrl http://"${RENDER_WS_IP}":8080/render-ws/v1 \
  --pipelineJson ${GS_PIPELINE_JSON_DIR_URL}/${PIPELINE_JSON_REL_PATH}
